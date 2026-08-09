import Foundation

extension SceneDocument {
    // general.* fields that participate in the current 2D runtime.
    struct GeneralDescriptor: Codable {
        struct CameraShakeDescriptor: Codable {
            /// `nil` preserves an authored value whose type could not be proven.
            let enabled: Bool?
            let amplitude: Float?
            let roughness: Float?
            let speed: Float?
        }

        let orthoWidth: Float?     // general.orthogonalprojection.width
        let orthoHeight: Float?    // general.orthogonalprojection.height
        let clearColor: [Float]?   // [r, g, b] in 0..1, from general.clearcolor
        let clearEnabled: Bool
        let nearZ: Float?
        let farZ: Float?
        let cameraParallaxEnabled: Bool
        let cameraParallaxAmount: Float
        let cameraParallaxDelay: Float
        let cameraParallaxMouseInfluence: Float
        let cameraShake: CameraShakeDescriptor
    }
}

extension SceneDocumentLoader {
    nonisolated static func parseGeneral(
        _ root: [String: Any]?
    ) -> SceneDocument.GeneralDescriptor {
        let ortho = root?["orthogonalprojection"] as? [String: Any]
        let width = ortho?["width"].flatMap(Self.floatValue)
        let height = ortho?["height"].flatMap(Self.floatValue)
        return SceneDocument.GeneralDescriptor(
            orthoWidth: width,
            orthoHeight: height,
            clearColor: floatVector(root?["clearcolor"]),
            clearEnabled: (root?["clearenabled"] as? Bool) ?? true,
            nearZ: root?["nearz"].flatMap(Self.floatValue),
            farZ: root?["farz"].flatMap(Self.floatValue),
            cameraParallaxEnabled: visibleValue(root?["cameraparallax"]) ?? false,
            cameraParallaxAmount: root?["cameraparallaxamount"].flatMap(Self.floatValue) ?? 0,
            cameraParallaxDelay: root?["cameraparallaxdelay"].flatMap(Self.floatValue) ?? 0,
            cameraParallaxMouseInfluence:
                root?["cameraparallaxmouseinfluence"].flatMap(Self.floatValue) ?? 0,
            cameraShake: .init(
                enabled: cameraShakeEnabled(root),
                amplitude: cameraShakeScalar(
                    root, key: "camerashakeamplitude", missingDefault: 0.5
                ),
                roughness: cameraShakeScalar(
                    root, key: "camerashakeroughness", missingDefault: 1
                ),
                speed: cameraShakeScalar(
                    root, key: "camerashakespeed", missingDefault: 3
                )
            )
        )
    }

    nonisolated private static func cameraShakeEnabled(
        _ root: [String: Any]?
    ) -> Bool? {
        guard let raw = root?["camerashake"] else { return false }
        return visibleValue(raw)
    }

    nonisolated private static func cameraShakeScalar(
        _ root: [String: Any]?,
        key: String,
        missingDefault: Float
    ) -> Float? {
        guard let raw = root?[key] else { return missingDefault }
        guard let value = floatValue(raw), value.isFinite else { return nil }
        return value
    }
}
