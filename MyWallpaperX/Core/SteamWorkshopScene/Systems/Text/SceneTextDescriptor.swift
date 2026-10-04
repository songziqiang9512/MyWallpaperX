import Foundation

struct SceneTextDescriptor: Codable {
    struct Outline: Codable {
        static let miterLimit: Float = 3
        let thickness: Float
        let colorRGB: [Float]
    }

    struct DropShadow: Codable {
        let offset: [Float]
        let size: Float
        let opacity: Float
        let colorRGB: [Float]
    }

    let fontPath: String?
    let pointSize: Float
    let colorRGB: [Float]
    let brightness: Float
    let horizontalAlignment: String
    let verticalAlignment: String
    // `anchor`（编辑器里的 Screen anchor）只在 text layer 上存在，取值见
    // lib.sceneScript.d.ts 的 ITextLayer：none/center/top/topright/right/
    // bottomright/bottom/bottomleft/left/topleft。它把 layer 钉在可见屏幕矩形的
    // 对应边角上而不是作者画布上，栅格化不消费它（见 SceneLayerScreenAnchor）。
    let screenAnchor: String
    let padding: Float
    // 官方 ITextLayer 的 Limit rows / Max rows / Limit width / Max width
    // （编辑器 `ui_editor_properties_limit_rows` 等）。`maxrows`/`maxwidth` 只在对应
    // 开关打开时生效，`maxwidth` 的单位是像素。`limituseellipsis` 不在 typings 里，
    // 但编辑器有 `ui_editor_properties_overflow_ellipsis`（Overflow ellipsis）。
    let limitRows: Bool
    let maxRows: Int
    let limitWidth: Bool
    let maxWidth: Float
    let useEllipsis: Bool
    let opaqueBackground: Bool
    let backgroundColorRGB: [Float]
    let backgroundBrightness: Float
    let outline: Outline?
    let dropShadow: DropShadow?

    // Logical margin shared by raster preparation and the existing quad pivot.
    // The glyph content box remains unchanged when this border is added.
    var decorationInset: Float {
        let outlineRadius = (outline?.thickness ?? 0) * Outline.miterLimit
        guard let shadow = dropShadow else { return outlineRadius }
        return outlineRadius + max(abs(shadow.offset[0]), abs(shadow.offset[1]))
            + max(4, shadow.size) * 2
    }

    nonisolated static func parse(_ root: [String: Any]) -> SceneTextDescriptor {
        SceneTextDescriptor(
            fontPath: normalizedPath(string(root["font"])),
            pointSize: max(1, number(root["pointsize"]) ?? 32),
            colorRGB: paddedColor(SceneDocumentLoader.floatVector(root["color"]), fill: 1),
            brightness: max(0, number(root["brightness"]) ?? 1),
            horizontalAlignment: string(root["horizontalalign"]) ?? "center",
            verticalAlignment: string(root["verticalalign"]) ?? "center",
            screenAnchor: string(root["anchor"]) ?? "none",
            padding: max(0, number(root["padding"]) ?? 0),
            limitRows: bool(root["limitrows"]) ?? false,
            maxRows: Int(max(1, (number(root["maxrows"]) ?? 1).rounded())),
            limitWidth: bool(root["limitwidth"]) ?? false,
            maxWidth: max(0, number(root["maxwidth"]) ?? 0),
            useEllipsis: bool(root["limituseellipsis"]) ?? false,
            opaqueBackground: bool(root["opaquebackground"]) ?? false,
            backgroundColorRGB: paddedColor(SceneDocumentLoader.floatVector(root["backgroundcolor"]), fill: 0),
            backgroundBrightness: max(0, number(root["backgroundbrightness"]) ?? 1),
            outline: parseOutline(root),
            dropShadow: parseDropShadow(root)
        )
    }

    nonisolated func replacing(
        fontPath: String? = nil,
        pointSize: Float? = nil,
        colorRGB: [Float]? = nil,
        maxWidth: Float? = nil
    ) -> SceneTextDescriptor {
        SceneTextDescriptor(
            fontPath: fontPath ?? self.fontPath,
            pointSize: max(1, pointSize ?? self.pointSize),
            colorRGB: Self.paddedColor(colorRGB ?? self.colorRGB, fill: 1),
            brightness: brightness,
            horizontalAlignment: horizontalAlignment,
            verticalAlignment: verticalAlignment,
            screenAnchor: screenAnchor,
            padding: padding,
            limitRows: limitRows,
            maxRows: maxRows,
            limitWidth: limitWidth,
            maxWidth: max(0, maxWidth ?? self.maxWidth),
            useEllipsis: useEllipsis,
            opaqueBackground: opaqueBackground,
            backgroundColorRGB: backgroundColorRGB,
            backgroundBrightness: backgroundBrightness,
            outline: outline,
            dropShadow: dropShadow
        )
    }

    nonisolated private static func parseOutline(_ root: [String: Any]) -> Outline? {
        guard bool(root["outline"]) == true,
              let thickness = decorationNumber(root["outlinethickness"] ?? 4),
              thickness > 0, thickness <= 4096,
              let color = decorationVector(root["outlinecolor"] ?? "0 0 0", count: 3)
        else { return nil }
        return Outline(thickness: thickness, colorRGB: color)
    }

    nonisolated private static func parseDropShadow(_ root: [String: Any]) -> DropShadow? {
        guard bool(root["dropshadow"]) == true,
              let size = decorationNumber(root["dropshadowsize"] ?? 6), size >= 0,
              let opacity = decorationNumber(root["dropshadowopacity"] ?? 1),
              opacity > 0, opacity <= 1,
              let offset = decorationVector(root["dropshadowoffset"] ?? "4 4", count: 2),
              let color = decorationVector(root["dropshadowcolor"] ?? "0 0 0", count: 3),
              Double(max(abs(offset[0]), abs(offset[1]))) + Double(max(4, size)) * 2 <= 4096
        else { return nil }
        return DropShadow(offset: offset, size: size, opacity: opacity, colorRGB: color)
    }

    nonisolated private static func decorationNumber(_ value: Any?) -> Float? {
        let raw = unwrapped(value)
        let number: Double?
        if let value = raw as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            number = value.doubleValue
        } else if let value = raw as? String {
            number = Double(value)
        } else {
            number = nil
        }
        guard let number, number.isFinite,
              abs(number) <= Double(Float.greatestFiniteMagnitude) else { return nil }
        return Float(number)
    }

    nonisolated private static func decorationVector(_ value: Any?, count: Int) -> [Float]? {
        let value = unwrapped(value)
        if let array = value as? [Any] {
            guard array.count == count else { return nil }
            let components = array.compactMap(decorationNumber)
            return components.count == count ? components : nil
        }
        guard let string = value as? String else { return nil }
        let parts = string.split { $0.isWhitespace || $0 == "," }
        guard parts.count == count else { return nil }
        let components = parts.compactMap { decorationNumber(String($0)) }
        guard components.count == count else { return nil }
        return components
    }

    nonisolated private static func unwrapped(_ value: Any?) -> Any? {
        if let keyed = value as? [String: Any] {
            return keyed["value"]
        }
        return value
    }

    nonisolated private static func string(_ value: Any?) -> String? {
        unwrapped(value) as? String
    }

    nonisolated private static func number(_ value: Any?) -> Float? {
        SceneDocumentLoader.floatValue(value)
            ?? SceneDocumentLoader.floatVector(value)?.first
    }

    nonisolated private static func bool(_ value: Any?) -> Bool? {
        unwrapped(value) as? Bool
    }

    nonisolated private static func normalizedPath(_ value: String?) -> String? {
        guard let value else { return nil }
        let path = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        return path.isEmpty ? nil : path
    }

    nonisolated private static func paddedColor(_ value: [Float]?, fill: Float) -> [Float] {
        var result = Array((value ?? []).prefix(3))
        while result.count < 3 { result.append(fill) }
        return result
    }
}
