import Foundation

extension SceneDocument {
    /// Authored scene-level host identity; interpolation stays in the shared
    /// Timeline IR and execution remains the existing prepared Program's job.
    struct SceneGeneralTimeline: Codable, Equatable {
        enum Host: String, CaseIterable, Codable {
            case bloomStrength = "bloomstrength"
            case zoom
        }
        let host: Host
        let animation: SceneTimelineAnimation
        let authoredValue: Float
        let hasScript: Bool
        var hasUserProperty: Bool? = nil
        var hasDeclaredIncomingPeer: Bool? = nil
    }

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

        /// Source shader arrays use the authored four-bit capacities. The
        /// native light consumers still use the historical nonzero gates.
        nonisolated struct LightClassesDescriptor: Codable {
            private let directionalValue: Double
            private let pointValue: Double
            private let spotValue: Double
            private let tubeValue: Double

            private enum CodingKeys: String, CodingKey {
                case directionalValue = "directional"
                case pointValue = "point"
                case spotValue = "spot"
                case tubeValue = "tube"
            }

            var directional: Bool { directionalValue != 0 }
            var point: Bool { pointValue != 0 }
            var spot: Bool { spotValue != 0 }
            var tube: Bool { tubeValue != 0 }

            var pointCount: Int { Self.slotCount(pointValue) }
            var spotCount: Int { Self.slotCount(spotValue) }

            init(directional: Bool = false, point: Bool = false, spot: Bool = false, tube: Bool = false) {
                self.init(directional: directional ? 1 : 0, point: point ? 1 : 0,
                          spot: spot ? 1 : 0, tube: tube ? 1 : 0)
            }

            init(directional: Double, point: Double, spot: Double, tube: Double) {
                directionalValue = directional
                pointValue = point
                spotValue = spot
                tubeValue = tube
            }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                func numeric(_ key: CodingKeys) throws -> Double {
                    if let number = try? values.decode(Double.self, forKey: key) { return number }
                    return try values.decode(Bool.self, forKey: key) ? 1 : 0
                }
                self.init(directional: try numeric(.directionalValue), point: try numeric(.pointValue),
                          spot: try numeric(.spotValue), tube: try numeric(.tubeValue))
            }

            private static func slotCount(_ value: Double) -> Int {
                guard let number = Int(exactly: value), (0 ... 15).contains(number) else { return 0 }
                return number
            }
        }

        let orthoWidth: Float?     // general.orthogonalprojection.width
        let orthoHeight: Float?    // general.orthogonalprojection.height
        /// Source mode, independent of any renderer fallback projection.
        var authoredOrthographicProjectionActive: Bool? = nil
        var fovDegrees: Float? = nil
        var perspectiveOverrideFOVDegrees: Float? = nil
        var zoom: Float? = nil
        var ambientColorRGB: [Float]? = nil
        var skylightColorRGB: [Float]? = nil
        var lightClasses: LightClassesDescriptor = .init()
        var distanceFog: DistanceFog? = nil
        var hdrEnabled: Bool = false
        var transparentSorting: Bool? = nil
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
        // Optional for decoding descriptors written before general Timelines.
        var timelines: [SceneGeneralTimeline]? = nil
        var timelineDiagnostics: [String]? = nil
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
        func numeric(_ key: String) -> Double {
            guard let number = config[key] as? NSNumber, number.doubleValue.isFinite else { return 0 }
            return number.doubleValue
        }
        return .init(
            directional: numeric("directional"),
            point: numeric("point"),
            spot: numeric("spot"),
            tube: numeric("tube")
        )
    }

    nonisolated static func parseGeneral(
        _ root: [String: Any]?,
        authoredRoot: [String: Any]? = nil
    ) -> SceneDocument.GeneralDescriptor {
        let ortho = root?["orthogonalprojection"] as? [String: Any]
        let width = ortho?["width"].flatMap(Self.floatValue)
        let height = ortho?["height"].flatMap(Self.floatValue)
        let authoredOrtho = (authoredRoot ?? root)?["orthogonalprojection"] as? [String: Any]
        let authoredWidth = authoredOrtho?["width"].flatMap(Self.floatValue)
        let authoredHeight = authoredOrtho?["height"].flatMap(Self.floatValue)
        let activeOrtho = visibleValue(authoredOrtho?["auto"]) == true
            || (authoredWidth.map { $0.isFinite && $0 > 0 } == true
                && authoredHeight.map { $0.isFinite && $0 > 0 } == true)
        let timelines = generalTimelines(authoredRoot ?? root)
        let zoomInput = (authoredRoot ?? root)?["zoom"]
        let zoomFallback = (zoomInput as? [String: Any])?["value"] ?? zoomInput
        let zoom = zoomFallback.flatMap { SceneJSONValue(jsonObject: $0)?.numberValue }
            .map(Self.saturatingFloat)
        return SceneDocument.GeneralDescriptor(
            orthoWidth: width,
            orthoHeight: height,
            authoredOrthographicProjectionActive: activeOrtho,
            fovDegrees: root?["fov"].flatMap(Self.floatValue),
            perspectiveOverrideFOVDegrees: root?["perspectiveoverridefov"]
                .flatMap(Self.floatValue),
            zoom: zoom,
            ambientColorRGB: floatVector(root?["ambientcolor"]),
            skylightColorRGB: floatVector(root?["skylightcolor"]),
            lightClasses: lightClasses(root?["lightconfig"]),
            distanceFog: distanceFog(root),
            hdrEnabled: visibleValue(root?["hdr"]) ?? false,
            transparentSorting: (authoredRoot ?? root)?["transparentsorting"] as? Bool,
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
            bloomHDRIterations: root?["bloomhdriterations"].flatMap(Self.floatValue),
            timelines: timelines.animations.isEmpty ? nil : timelines.animations,
            timelineDiagnostics: timelines.diagnostics.isEmpty ? nil : timelines.diagnostics
        )
    }

    nonisolated private static func generalTimelines(
        _ root: [String: Any]?
    ) -> (animations: [SceneDocument.SceneGeneralTimeline], diagnostics: [String]) {
        var animations: [SceneDocument.SceneGeneralTimeline] = []
        var diagnostics: [String] = []
        var zoomHasDeclaredIncomingPeer = false
        for host in SceneDocument.SceneGeneralTimeline.Host.allCases {
            let raw = root?[host.rawValue]
            let wrapper = raw as? [String: Any]
            // Rejected mode/lanes must not erase a declared connection to zoom.
            if host != .zoom,
               let animation = wrapper?["animation"] as? [String: Any],
               let options = animation["options"] as? [String: Any] {
                zoomHasDeclaredIncomingPeer = zoomHasDeclaredIncomingPeer
                    || SceneTimelineAnimationParser.declaredGroupReferences(
                        parent: options["parent"], children: options["children"]
                    ).contains { $0.key == "zoom" }
            }
            let result = SceneTimelineAnimationParser.parse(host: raw)
            if let animation = result.animation {
                let script = wrapper?["script"]
                animations.append(.init(
                    host: host, animation: animation,
                    authoredValue: Self.floatValue(raw) ?? 1,
                    hasScript: script != nil && !(script is NSNull),
                    hasUserProperty: wrapper?["user"].map { !($0 is NSNull) } ?? false
                ))
            }
            diagnostics.append(contentsOf: result.diagnostics.map {
                "\(host.rawValue):\($0.token)"
            })
        }
        for index in animations.indices where animations[index].host == .zoom {
            animations[index].hasDeclaredIncomingPeer = zoomHasDeclaredIncomingPeer
        }
        return (animations, diagnostics)
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
