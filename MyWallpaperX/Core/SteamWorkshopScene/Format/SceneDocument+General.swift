import Foundation

extension SceneDocument {
    // general.* fields that participate in the current 2D runtime.
    struct GeneralDescriptor: Codable {
        struct DistanceFog: Codable {
            let color: [Float]
            let start: Float
            let end: Float
            let startDensity: Float
            let endDensity: Float
        }
        struct CameraShakeDescriptor: Codable {
            /// `nil` preserves an authored value whose type could not be proven.
            let enabled: Bool?
            let amplitude: Float?
            let roughness: Float?
            let speed: Float?
        }

        /// `general.lightconfig` gates which light classes the scene admits.
        /// A nil descriptor means the author field is absent: official clients
        /// leave directional, point and spot lights inert in that state
        /// (bounded own-fixture black-box observation, WE 2.8.0.42,
        /// 2026-10-06; spot key confirmed by the SP1/SP2 pair), so the
        /// parsed form defaults all classes to disabled.
        struct LightClassesDescriptor: Codable {
            var directional: Bool = false
            var point: Bool = false
            var spot: Bool = false
        }

        let orthoWidth: Float?     // general.orthogonalprojection.width
        let orthoHeight: Float?    // general.orthogonalprojection.height
        var fovDegrees: Float? = nil
        var perspectiveOverrideFOVDegrees: Float? = nil
        var ambientColorRGB: [Float]? = nil
        var skylightColorRGB: [Float]? = nil
        var lightClasses: LightClassesDescriptor = .init()
        var distanceFog: DistanceFog? = nil
        var hdrEnabled: Bool = false
        let clearColor: [Float]?   // [r, g, b] in 0..1, from general.clearcolor
        let clearEnabled: Bool
        let nearZ: Float?
        let farZ: Float?
        let cameraParallaxEnabled: Bool
        let cameraParallaxAmount: Float
        let cameraParallaxDelay: Float
        let cameraParallaxMouseInfluence: Float
        let cameraShake: CameraShakeDescriptor
        let bloomEnabled: Bool
        let bloomStrength: Float
        let bloomThreshold: Float
        let bloomTint: [Float]
        var bloomHDRStrength: Float? = nil
        var bloomHDRThreshold: Float? = nil
        var bloomHDRScatter: Float? = nil
        var bloomHDRFeather: Float? = nil
        var bloomHDRIterations: Float? = nil
    }
}

extension SceneDocumentLoader {
    nonisolated private static func distanceFog(
        _ root: [String: Any]?
    ) -> SceneDocument.GeneralDescriptor.DistanceFog? {
        guard visibleValue(root?["fogdistance"]) == true,
              let color = floatVector(root?["fogdistancecolor"]),
              color.count == 3, color.allSatisfy({ $0.isFinite && $0 >= 0 }),
              let start = root?["fogdistancestart"].flatMap(Self.floatValue),
              let end = root?["fogdistanceend"].flatMap(Self.floatValue),
              let startDensity = root?["fogdistancestartdensity"].flatMap(Self.floatValue),
              let endDensity = root?["fogdistanceenddensity"].flatMap(Self.floatValue),
              [start, end, startDensity, endDensity].allSatisfy(\.isFinite),
              start >= 0, end > start,
              (0...1).contains(startDensity), (0...1).contains(endDensity) else {
            return nil
        }
        return .init(color: color, start: start, end: end,
                     startDensity: startDensity, endDensity: endDensity)
    }

    nonisolated private static func lightClasses(
        _ value: Any?
    ) -> SceneDocument.GeneralDescriptor.LightClassesDescriptor {
        guard let config = value as? [String: Any] else {
            return .init()
        }
        return .init(
            directional: (config["directional"] as? NSNumber)?.intValue != 0,
            point: (config["point"] as? NSNumber)?.intValue != 0,
            spot: (config["spot"] as? NSNumber)?.intValue != 0
        )
    }

    nonisolated static func parseGeneral(
        _ root: [String: Any]?
    ) -> SceneDocument.GeneralDescriptor {
        let ortho = root?["orthogonalprojection"] as? [String: Any]
        let width = ortho?["width"].flatMap(Self.floatValue)
        let height = ortho?["height"].flatMap(Self.floatValue)
        return SceneDocument.GeneralDescriptor(
            orthoWidth: width,
            orthoHeight: height,
            fovDegrees: root?["fov"].flatMap(Self.floatValue),
            perspectiveOverrideFOVDegrees: root?["perspectiveoverridefov"]
                .flatMap(Self.floatValue),
            ambientColorRGB: floatVector(root?["ambientcolor"]),
            skylightColorRGB: floatVector(root?["skylightcolor"]),
            lightClasses: lightClasses(root?["lightconfig"]),
            distanceFog: distanceFog(root),
            hdrEnabled: visibleValue(root?["hdr"]) ?? false,
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
            ),
            bloomEnabled: visibleValue(root?["bloom"]) ?? false,
            bloomStrength: root?["bloomstrength"].flatMap(Self.floatValue) ?? 1,
            bloomThreshold: root?["bloomthreshold"].flatMap(Self.floatValue) ?? 0.65,
            bloomTint: floatVector(root?["bloomtint"]) ?? [1, 1, 1],
            bloomHDRStrength: root?["bloomhdrstrength"].flatMap(Self.floatValue),
            bloomHDRThreshold: root?["bloomhdrthreshold"].flatMap(Self.floatValue),
            bloomHDRScatter: root?["bloomhdrscatter"].flatMap(Self.floatValue),
            bloomHDRFeather: root?["bloomhdrfeather"].flatMap(Self.floatValue),
            bloomHDRIterations: root?["bloomhdriterations"].flatMap(Self.floatValue)
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
