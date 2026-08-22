import Foundation
import Metal

/// Scene/device assets prepared before the first frame. The catalog exclusively
/// owns animated asset providers; frame publication remains the registry's job.
final class SceneMaterialAssetTextureCatalog {
    fileprivate struct AnimatedDefinition {
        let identity: SceneAssetTextureIdentity
        let base: SceneTextureCandidate
        let frames: [SceneTexContainer.SpriteFrame]
        let durations: [Double]
        let duration: Double

        init(identity: SceneAssetTextureIdentity, asset: SceneAnimatedTextureCandidate) {
            self.identity = identity
            base = asset.candidate
            frames = asset.frames
            durations = asset.frames.map {
                $0.duration > 0 ? Double($0.duration) : 1.0 / 60.0
            }
            duration = durations.reduce(0, +)
        }
    }

    /// Per-runtime/surface playback state created from immutable launch facts.
    /// It emits typed provider values only; the frame registry owns publication.
    final class FrameProvider {
        private struct Cursor {
            let frameIndex: Int
            let contentGeneration: UInt64
        }

        private let staticStates: [
            SceneAssetTextureIdentity: SceneTextureProviderState
        ]
        private let definitions: [SceneAssetTextureIdentity: AnimatedDefinition]
        private var cursors: [SceneAssetTextureIdentity: Cursor] = [:]

        fileprivate init(
            staticStates: [SceneAssetTextureIdentity: SceneTextureProviderState],
            definitions: [SceneAssetTextureIdentity: AnimatedDefinition]
        ) {
            self.staticStates = staticStates
            self.definitions = definitions
        }

        func states(sceneTime: TimeInterval) -> [
            SceneAssetTextureIdentity: SceneTextureProviderState
        ] {
            var result = staticStates
            for identity in definitions.keys.sorted(by: SceneMaterialAssetTextureCatalog.less) {
                guard let definition = definitions[identity] else { continue }
                result[identity] = state(definition, sceneTime: sceneTime)
            }
            return result
        }

        private func state(
            _ definition: AnimatedDefinition,
            sceneTime: TimeInterval
        ) -> SceneTextureProviderState {
            guard sceneTime.isFinite, definition.duration.isFinite,
                  definition.duration > 0,
                  let frameIndex = frameIndex(
                      at: sceneTime,
                      durations: definition.durations,
                      totalDuration: definition.duration
                  ) else {
                return .unavailable
            }
            let previous = cursors[definition.identity]
            let contentGeneration: UInt64
            if previous?.frameIndex == frameIndex {
                contentGeneration = previous!.contentGeneration
            } else {
                let next = (previous?.contentGeneration ?? 0)
                    .addingReportingOverflow(1)
                guard !next.overflow else { return .unavailable }
                contentGeneration = next.partialValue
                cursors[definition.identity] = .init(
                    frameIndex: frameIndex,
                    contentGeneration: contentGeneration
                )
            }
            let frame = definition.frames[frameIndex]
            let base = definition.base
            let candidate = SceneTextureCandidate(
                texture: definition.base.texture,
                identity: base.identity,
                generation: base.generation,
                purpose: base.purpose,
                content: base.content,
                physicalSize: base.physicalSize,
                mappedSize: base.mappedSize,
                uvTransform: .init(
                    origin: frame.origin,
                    xAxis: frame.xAxis,
                    yAxis: frame.yAxis
                ),
                sampling: base.sampling,
                authoredFormat: base.authoredFormat
            )
            let publication = SceneTextureProviderPublication(
                requestIdentity: .asset(definition.identity),
                candidate: candidate,
                contentGeneration: contentGeneration
            )
            return publication.isComplete ? .ready(publication) : .unavailable
        }

        private func frameIndex(
            at sceneTime: TimeInterval,
            durations: [Double],
            totalDuration: Double
        ) -> Int? {
            var remaining = sceneTime.truncatingRemainder(
                dividingBy: totalDuration
            )
            if remaining < 0 { remaining += totalDuration }
            for (index, frameDuration) in durations.enumerated() {
                if remaining < frameDuration { return index }
                remaining -= frameDuration
            }
            return durations.indices.last
        }
    }

    private let staticStates: [SceneAssetTextureIdentity: SceneTextureProviderState]
    private let animatedDefinitions: [SceneAssetTextureIdentity: AnimatedDefinition]
    private let launchStatesByIdentity: [
        SceneAssetTextureIdentity: SceneAssetTextureLaunchState
    ]

    init(
        demands: Set<SceneAssetTextureIdentity>,
        resourceView: SceneResourceView,
        descriptor: SceneRenderDescriptor,
        device: MTLDevice
    ) {
        let resolver = SceneTexturePathResolver(
            resourceView: resourceView,
            descriptor: descriptor
        )
        let loader = SceneTextureLoader()
        var loaded: [SceneAssetTextureIdentity: SceneTextureProviderState] = [:]
        var animated: [SceneAssetTextureIdentity: AnimatedDefinition] = [:]
        var launchStates: [
            SceneAssetTextureIdentity: SceneAssetTextureLaunchState
        ] = [:]
        for identity in demands.sorted(by: Self.less) {
            guard let url = resolver.resolveTextureFile(named: identity.path.value) else {
                loaded[identity] = .absent
                launchStates[identity] = .absent
                continue
            }
            let container = url.pathExtension.lowercased() == "tex"
                ? loader.texContainer(from: url) : nil
            if let container,
               container.isAnimated || !container.spriteFrames.isEmpty
                    || container.imageCount != 1 {
                if loader.materialAtlasAdmission(container)
                    == .invalidFrameMetadata {
                    loaded[identity] = .unavailable
                    launchStates[identity] = .effectLocalUnavailable(
                        .animatedFrameMetadataInvalid
                    )
                    continue
                }
                switch loader.loadAnimatedMaterialCandidate(
                    from: url,
                    purpose: identity.purpose,
                    device: device
                ) {
                case .failed:
                    loaded[identity] = .unavailable
                    launchStates[identity] = .unavailable
                case let .loaded(asset):
                    guard asset.candidate.purpose == identity.purpose else {
                        loaded[identity] = .unavailable
                        launchStates[identity] = .unavailable
                        continue
                    }
                    animated[identity] = AnimatedDefinition(
                        identity: identity,
                        asset: asset
                    )
                    launchStates[identity] = .ready(asset.candidate.content)
                }
                continue
            }
            switch loader.loadCandidate(
                from: url,
                purpose: identity.purpose,
                device: device
            ) {
            case .failed:
                loaded[identity] = .unavailable
                launchStates[identity] = .unavailable
            case let .loaded(candidate):
                let request = SceneFrameTextureIdentity.asset(identity)
                let publication = SceneTextureProviderPublication(
                    requestIdentity: request,
                    candidate: candidate,
                    contentGeneration: 1
                )
                guard candidate.purpose == identity.purpose,
                      publication.isComplete else {
                    loaded[identity] = .unavailable
                    launchStates[identity] = .unavailable
                    continue
                }
                loaded[identity] = .ready(publication)
                launchStates[identity] = .ready(candidate.content)
            }
        }
        staticStates = loaded
        animatedDefinitions = animated
        launchStatesByIdentity = launchStates
    }

    func makeFrameProvider() -> FrameProvider {
        FrameProvider(
            staticStates: staticStates,
            definitions: animatedDefinitions
        )
    }

    var reportLines: [String] {
        var ready = 0
        var absent = 0
        var pending = 0
        var unavailable = 0
        for state in staticStates.values {
            switch state {
            case .ready: ready += 1
            case .absent: absent += 1
            case .pending: pending += 1
            case .unavailable: unavailable += 1
            }
        }
        return [
            "resolved material asset catalog: schema=r4-frame-assets-v1"
                + " demands=\(staticStates.count + animatedDefinitions.count)"
                + " ready=\(ready + animatedDefinitions.count) absent=\(absent)"
                + " pending=\(pending) unavailable=\(unavailable)"
        ]
    }

    /// Ready values are the official 0...12 format enum. -1 is proven absent;
    /// -2 is present but not safely attributable to an authored TEX format.
    var launchFormatFacts: [String: Int] {
        var values = Dictionary(uniqueKeysWithValues: staticStates.map { identity, state in
            let value: Int
            switch state {
            case let .ready(publication):
                guard let format = publication.candidate.authoredFormat else {
                    return (identity.reportToken, -2)
                }
                value = format.macroValue
            case .absent:
                value = -1
            case .pending, .unavailable:
                value = -2
            }
            return (identity.reportToken, value)
        })
        for (identity, definition) in animatedDefinitions {
            values[identity.reportToken] = definition.base.authoredFormat?.macroValue ?? -2
        }
        return values
    }

    var launchStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] {
        launchStatesByIdentity
    }

    private nonisolated static func less(
        _ lhs: SceneAssetTextureIdentity,
        _ rhs: SceneAssetTextureIdentity
    ) -> Bool {
        lhs.reportToken < rhs.reportToken
    }
}
