import Foundation

/// A bounded compatibility reader for legacy annotation JSON. It only removes
/// redundant leading zeroes from bare integer values at JSON token boundaries;
/// raw shader and annotation text remain unchanged in the contract.
nonisolated enum SceneShaderLegacyAnnotationJSON {
    private static let maximumPayloadBytes = 16 * 1_024

    static func decodedValues(
        from text: String
    ) -> (SceneJSONValue, SceneShaderAnnotationValue)? {
        guard let strictData = text.data(using: .utf8) else { return nil }
        let candidates = [strictData, recoveredData(from: text)].compactMap { $0 }
        for data in candidates {
            guard let object = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            ),
            let value = SceneJSONValue(jsonObject: object),
            let variantValue = try? JSONDecoder().decode(
                SceneShaderAnnotationValue.self,
                from: data
            ) else { continue }
            return (value, variantValue)
        }
        return nil
    }

    static func recoveredData(from text: String) -> Data? {
        let bytes = Array(text.utf8)
        guard bytes.count <= maximumPayloadBytes else { return nil }

        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        var inString = false
        var escaped = false
        var changed = false

        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                result.append(byte)
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                index += 1
                continue
            }
            if byte == 0x22 {
                inString = true
                result.append(byte)
                index += 1
                continue
            }

            let hasMinus = byte == 0x2D
            let digitStart = hasMinus ? index + 1 : index
            guard isValueBoundary(before: index, in: bytes),
                  digitStart < bytes.count,
                  bytes[digitStart] == 0x30 else {
                result.append(byte)
                index += 1
                continue
            }

            var end = digitStart
            while end < bytes.count, isDigit(bytes[end]) { end += 1 }
            guard end - digitStart > 1,
                  isValueBoundary(after: end, in: bytes) else {
                result.append(byte)
                index += 1
                continue
            }

            if hasMinus { result.append(byte) }
            var firstSignificant = digitStart
            while firstSignificant + 1 < end, bytes[firstSignificant] == 0x30 {
                firstSignificant += 1
            }
            result.append(contentsOf: bytes[firstSignificant..<end])
            changed = true
            index = end
        }

        return changed ? Data(result) : nil
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private static func isValueBoundary(before index: Int, in bytes: [UInt8]) -> Bool {
        index == 0 || isWhitespace(bytes[index - 1])
            || [0x5B, 0x7B, 0x2C, 0x3A].contains(bytes[index - 1])
    }

    private static func isValueBoundary(after index: Int, in bytes: [UInt8]) -> Bool {
        index == bytes.count || isWhitespace(bytes[index])
            || [0x5D, 0x7D, 0x2C].contains(bytes[index])
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
