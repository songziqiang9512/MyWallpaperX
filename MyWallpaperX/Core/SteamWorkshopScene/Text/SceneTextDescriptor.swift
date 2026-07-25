import Foundation

struct SceneTextDescriptor: Codable {
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
            backgroundBrightness: max(0, number(root["backgroundbrightness"]) ?? 1)
        )
    }

    nonisolated func replacing(
        pointSize: Float? = nil,
        colorRGB: [Float]? = nil
    ) -> SceneTextDescriptor {
        SceneTextDescriptor(
            fontPath: fontPath,
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
            maxWidth: maxWidth,
            useEllipsis: useEllipsis,
            opaqueBackground: opaqueBackground,
            backgroundColorRGB: backgroundColorRGB,
            backgroundBrightness: backgroundBrightness
        )
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
