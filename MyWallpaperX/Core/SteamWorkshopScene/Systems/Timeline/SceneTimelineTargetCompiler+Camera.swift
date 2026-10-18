import Foundation

/// Bounded 2D camera-path Timeline profile.
///
/// Camera path records are not drawable layers. A single default-camera record may expose the
/// editor's Combined `origin` owner + `zoom` child pair or independent Single fields.
/// A Combined pair shares its owner's clock; independent fields retain their own playback
/// positions on SceneClock. Both publish through the same dynamic snapshot.
nonisolated enum Scene2DCameraTimelineCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor
    ) -> SceneTimelineProgram {
        let paths = descriptor.layers.filter { $0.cameraPath != nil }
        guard paths.count == 1, let layer = paths.first else {
            return rejectedMultiplePaths(paths)
        }
        let group = layer.timelines.filter { $0.host == .origin || $0.host == .zoom }
        guard !group.isEmpty else { return .empty }
        let labels = group.map { "layer \(layer.id) \($0.host.rawValue)" }
        guard let path = layer.cameraPath,
              path.camera.lowercased() == "default",
              path.queueMode == nil || path.queueMode == "random"
                || path.queueMode == "sequential" else {
            return rejected(labels, reason: "cameraProfileUnsupported")
        }
        // The bounded pair must also be a complete authored component. Its
        // outgoing references are checked below; a third lane may not point in.
        guard case let .object(authored)? = layer.initialConfiguration else {
            return rejected(labels, reason: "cameraProfileUnsupported")
        }
        let hasIncomingPeer = [SceneDocument.SceneObjectTimeline.Host.origin, .zoom].contains {
            SceneDefault2DCameraInputProfile.hasDeclaredIncomingPeer(
                to: $0, authored: authored, excludingHosts: [.origin, .zoom])
        }
        guard !hasIncomingPeer, group.count == 2,
              let origin = group.first(where: { $0.host == .origin })?.animation,
              let zoom = group.first(where: { $0.host == .zoom })?.animation,
              origin.options.parent == nil,
              origin.options.children.map(\.key) == ["zoom"],
              zoom.options.parent?.key == "origin",
              zoom.options.children.isEmpty else {
            return independentProgram(layer: layer, descriptor: descriptor, group: group)
        }
        let groupedOrigin = SceneTimelineTargetCompiler.groupedAnimation(
            origin, owner: origin, isOwner: true
        )
        let groupedZoom = SceneTimelineTargetCompiler.groupedAnimation(
            zoom, owner: origin, isOwner: false
        )
        guard groupedOrigin.componentCount == 3, groupedZoom.componentCount == 1 else {
            return rejected(labels, reason: "componentMismatch")
        }
        guard groupedOrigin.hasExecutableWrapLoop, groupedZoom.hasExecutableWrapLoop else {
            return rejected(labels, reason: "invalidWrapLoop")
        }
        guard origin.isRelative, !zoom.isRelative,
              let authoredOrigin = layer.originXYZ,
              authoredOrigin.count == 3,
              let authoredZoom = path.zoom,
              SceneDefault2DCameraInputProfile.acceptsOrigin(
                authoredOrigin,
                animation: groupedOrigin,
                nearZ: Double(descriptor.camera.nearZ),
                farZ: Double(descriptor.camera.farZ)
              ),
              SceneDefault2DCameraInputProfile.acceptsZoom(authoredZoom, animation: groupedZoom) else {
            return rejected(labels, reason: "valueOutOfRange")
        }

        let originBinding = SceneTimelineBinding(
            definition: .init(
                target: .camera(.origin),
                valueType: .vector3,
                authoredValue: .vector3(
                    Double(authoredOrigin[0]),
                    Double(authoredOrigin[1]),
                    Double(authoredOrigin[2])
                )
            ),
            animation: groupedOrigin,
            composition: .additive,
            playbackOwner: .camera(.origin)
        )
        let zoomBinding = SceneTimelineBinding(
            definition: .init(
                target: .camera(.zoom),
                valueType: .scalar,
                authoredValue: .scalar(authoredZoom)
            ),
            animation: groupedZoom,
            composition: .absolute,
            playbackOwner: .camera(.origin)
        )
        return SceneTimelineProgram(
            bindings: [originBinding, zoomBinding],
            diagnostics: []
        )
    }

    private nonisolated static func independentProgram(
        layer: SceneRenderDescriptor.Layer,
        descriptor: SceneRenderDescriptor,
        group: [SceneDocument.SceneObjectTimeline]
    ) -> SceneTimelineProgram {
        let labels = group.map { "layer \(layer.id) \($0.host.rawValue)" }
        let independent = group.compactMap { timeline in
            SceneDefault2DCameraInputProfile.independentAnimation(
                host: timeline.host, timelines: layer.timelines,
                authoredConfiguration: layer.initialConfiguration
            ).map { (timeline.host, $0) }
        }
        guard !independent.isEmpty else {
            return rejected(labels, reason: "combinedAnimationUnsupported")
        }
        guard descriptor.camera.default2DInputLayerID == layer.id else {
            return rejected(labels, reason: "cameraProfileUnsupported")
        }
        var bindings: [SceneTimelineBinding] = []
        var diagnostics: [String] = []
        for timeline in group {
            let label = "layer \(layer.id) \(timeline.host.rawValue)"
            guard let animation = independent.first(where: { $0.0 == timeline.host })?.1 else {
                diagnostics.append("\(label): combinedAnimationUnsupported")
                continue
            }
            switch timeline.host {
            case .origin:
                guard descriptor.camera.default2DOriginInputLayerID == layer.id,
                      let origin = layer.originXYZ,
                      SceneDefault2DCameraInputProfile.acceptsOrigin(origin,
                        animation: animation, nearZ: Double(descriptor.camera.nearZ),
                        farZ: Double(descriptor.camera.farZ)) else {
                    diagnostics.append("\(label): valueOutOfRange")
                    continue
                }
                bindings.append(.init(definition: .init(target: .camera(.origin),
                    valueType: .vector3, authoredValue: .vector3(
                        Double(origin[0]), Double(origin[1]), Double(origin[2]))),
                    animation: animation, composition: .additive))
            case .zoom:
                guard let zoom = layer.cameraPath?.zoom,
                      SceneDefault2DCameraInputProfile.acceptsZoom(zoom, animation: animation) else {
                    diagnostics.append("\(label): valueOutOfRange")
                    continue
                }
                bindings.append(.init(definition: .init(target: .camera(.zoom),
                    valueType: .scalar, authoredValue: .scalar(zoom)),
                    animation: animation, composition: .absolute))
            default: break
            }
        }
        return SceneTimelineProgram(bindings: bindings, diagnostics: diagnostics.sorted())
    }

    private nonisolated static func rejectedMultiplePaths(
        _ paths: [SceneRenderDescriptor.Layer]
    ) -> SceneTimelineProgram {
        guard paths.count > 1 else { return .empty }
        let diagnostics = paths.flatMap { layer in
            layer.timelines.compactMap { timeline -> String? in
                guard timeline.host == .origin || timeline.host == .zoom else { return nil }
                return "layer \(layer.id) \(timeline.host.rawValue): cameraPathSelectionUnsupported"
            }
        }
        return SceneTimelineProgram(bindings: [], diagnostics: diagnostics.sorted())
    }

    private nonisolated static func rejected(
        _ labels: [String],
        reason: String
    ) -> SceneTimelineProgram {
        SceneTimelineProgram(
            bindings: [],
            diagnostics: labels.map { "\($0): \(reason)" }.sorted()
        )
    }

}
