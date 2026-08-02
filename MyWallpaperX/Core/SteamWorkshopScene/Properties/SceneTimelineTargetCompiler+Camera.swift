import Foundation

/// Bounded 2D camera-path Timeline profile.
///
/// Camera path records are not drawable layers. A single default-camera record may expose the
/// editor's Combined `origin` owner + `zoom` child pair; both members are normalized onto the
/// owner's clock and committed through the shared dynamic snapshot. Multiple path selection and
/// 3D camera paths remain fail closed because their queue/visibility lifecycle is a separate
/// contract.
nonisolated enum Scene2DCameraTimelineCompiler {
    private static let maximumOriginMagnitude = 10_000_000.0
    private static let minimumZoom = 0.01
    private static let maximumZoom = 100.0

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
        guard group.count == 2,
              let origin = group.first(where: { $0.host == .origin })?.animation,
              let zoom = group.first(where: { $0.host == .zoom })?.animation,
              origin.options.parent == nil,
              origin.options.children.map(\.key) == ["zoom"],
              zoom.options.parent?.key == "origin",
              zoom.options.children.isEmpty else {
            return rejected(labels, reason: "combinedAnimationUnsupported")
        }
        guard origin.componentCount == 3, zoom.componentCount == 1 else {
            return rejected(labels, reason: "componentMismatch")
        }
        guard origin.hasExecutableWrapLoop, zoom.hasExecutableWrapLoop else {
            return rejected(labels, reason: "invalidWrapLoop")
        }
        guard origin.isRelative, !zoom.isRelative,
              let authoredOrigin = layer.originXYZ,
              authoredOrigin.count == 3,
              let authoredZoom = path.zoom,
              boundedOrigin(
                authoredOrigin,
                animation: origin,
                nearZ: Double(descriptor.camera.nearZ),
                farZ: Double(descriptor.camera.farZ)
              ),
              boundedZoom(authoredZoom, animation: zoom) else {
            return rejected(labels, reason: "valueOutOfRange")
        }

        let clock = ownerClock(origin.options)
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
            animation: animation(origin, clock: clock),
            composition: .additive
        )
        let zoomBinding = SceneTimelineBinding(
            definition: .init(
                target: .camera(.zoom),
                valueType: .scalar,
                authoredValue: .scalar(authoredZoom)
            ),
            animation: animation(zoom, clock: clock),
            composition: .absolute
        )
        return SceneTimelineProgram(
            bindings: [originBinding, zoomBinding],
            diagnostics: []
        )
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

    private nonisolated static func boundedOrigin(
        _ authored: [Float],
        animation: SceneTimelineAnimation,
        nearZ: Double,
        farZ: Double
    ) -> Bool {
        guard nearZ.isFinite, farZ.isFinite, nearZ >= 0, farZ > nearZ else { return false }
        guard authored.allSatisfy({ $0.isFinite && abs(Double($0)) <= maximumOriginMagnitude })
        else { return false }
        for (index, lane) in animation.lanes.enumerated() {
            let base = Double(authored[index])
            guard animation.consumedControlValues(in: lane).allSatisfy({ control in
                let value = base + control
                let bounded = value.isFinite && abs(value) <= maximumOriginMagnitude
                return index == 2 ? bounded && value > nearZ && value < farZ : bounded
            }) else { return false }
        }
        return true
    }

    private nonisolated static func boundedZoom(
        _ authored: Double,
        animation: SceneTimelineAnimation
    ) -> Bool {
        guard authored.isFinite, minimumZoom ... maximumZoom ~= authored else { return false }
        let lane = animation.lanes[0]
        return animation.consumedControlValues(in: lane).allSatisfy {
            $0.isFinite && minimumZoom ... maximumZoom ~= $0
        }
    }

    private nonisolated static func ownerClock(
        _ options: SceneTimelineOptions
    ) -> SceneTimelineOptions {
        SceneTimelineOptions(
            fps: options.fps,
            length: options.length,
            mode: options.mode,
            startsPaused: options.startsPaused,
            wrapsLoop: options.wrapsLoop,
            smoothing: options.smoothing,
            stiffness: options.stiffness,
            parent: nil,
            children: []
        )
    }

    private nonisolated static func animation(
        _ animation: SceneTimelineAnimation,
        clock: SceneTimelineOptions
    ) -> SceneTimelineAnimation {
        SceneTimelineAnimation(
            lanes: animation.lanes,
            options: clock,
            isRelative: animation.isRelative,
            previewValue: animation.previewValue
        )
    }
}
