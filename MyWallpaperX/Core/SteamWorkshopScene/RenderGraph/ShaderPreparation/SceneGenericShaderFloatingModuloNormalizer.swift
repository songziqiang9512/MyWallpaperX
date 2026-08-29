import Foundation

/// Makes the bounded authored floating-remainder assignment explicit for
/// Vulkan GLSL. Complex operands remain untouched and fail closed downstream.
nonisolated enum SceneGenericShaderFloatingModuloNormalizer {
    static func rewrite(_ source: String) -> String {
        let declaration = try! NSRegularExpression(pattern:
            #"\b(float|int|uint)\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
        )
        var types: [String: String] = [:]
        for match in declaration.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) {
            guard let typeRange = Range(match.range(at: 1), in: source),
                  let nameRange = Range(match.range(at: 2), in: source) else { continue }
            types[String(source[nameRange])] = String(source[typeRange])
        }
        let atom = #"(?:[A-Za-z_][A-Za-z0-9_]*|[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))"#
        let assignment = try! NSRegularExpression(pattern:
            #"\b(float|int|uint)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("#
                + atom + #")\s*%\s*("# + atom + #")\s*;"#
        )
        var result = source
        for match in assignment.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let targetRange = Range(match.range(at: 1), in: source),
                  let nameRange = Range(match.range(at: 2), in: source),
                  let leftRange = Range(match.range(at: 3), in: source),
                  let rightRange = Range(match.range(at: 4), in: source),
                  let fullRange = Range(match.range, in: result) else { continue }
            let target = String(source[targetRange])
            let left = String(source[leftRange])
            let right = String(source[rightRange])
            guard scalarType(left, declarations: types) == "float"
                    || scalarType(right, declarations: types) == "float" else { continue }
            let remainder = "mod(float(\(left)), float(\(right)))"
            let value = target == "float" ? remainder : "\(target)(\(remainder))"
            let name = String(source[nameRange])
            result.replaceSubrange(fullRange, with: "\(target) \(name) = \(value);")
        }
        return result
    }

    private static func scalarType(
        _ atom: String,
        declarations: [String: String]
    ) -> String {
        declarations[atom] ?? (atom.contains(".") ? "float" : "int")
    }
}
