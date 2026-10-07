import Foundation

/// Launch-owned animation positions. The existing SceneClock supplies cadence;
/// surfaces retain pose/physics/GPU resources and consume this one sample frame.
nonisolated final class ScenePuppetAnimationPlaybackRuntime: @unchecked Sendable {
    struct LayerFrame {
        let samples: [ScenePuppetAnimationEvaluator.FrameSample?]
    }

    struct FrameSnapshot {
        let frameIndex: UInt64
        let sceneTime: Double
        fileprivate let layers: [Int: LayerFrame]

        subscript(layerID: Int) -> LayerFrame? { layers[layerID] }
    }

    enum Failure: Error, Equatable {
        case conflictingDefinition(layerID: Int)
        case unmatchedAnimationLayer(layerID: Int)
    }

    private struct ClipIdentity: Equatable {
        let authoredPosition: Int
        let animationLayerID: Int?
    }

    private struct ClipDefinition: Equatable {
        let identity: ClipIdentity
        let layer: ScenePuppetAnimationLayer
        let animation: SceneMdlPuppetAnimation

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identity == rhs.identity && lhs.layer == rhs.layer
                && lhs.animation.id == rhs.animation.id
                && lhs.animation.name == rhs.animation.name
                && lhs.animation.mode == rhs.animation.mode
                && lhs.animation.framesPerSecond == rhs.animation.framesPerSecond
                && lhs.animation.frameCount == rhs.animation.frameCount
                && lhs.animation.transformsByBone == rhs.animation.transformsByBone
                && lhs.animation.alphaByBone == rhs.animation.alphaByBone
        }

        func isVisible(layerID: Int, snapshot: SceneDynamicSnapshot) -> Bool {
            guard layer.visibilityBinding != nil else { return layer.visible == true }
            guard let id = layer.id,
                  let resolved = snapshot[ScenePuppetAnimationPropertyTarget.visibility(
                      layerID: layerID, animationLayerID: id
                  )], case let .bool(visible) = resolved.value else { return false }
            return visible
        }
    }

    private struct LayerDefinition: Equatable {
        let composition: String
        let clips: [ClipDefinition]
    }

    private struct ClipState {
        var playbackTime: Double?
    }

    private let lock = NSLock()
    private var definitions: [Int: LayerDefinition] = [:]
    private var states: [Int: [ClipState]] = [:]
    private var lastSceneTime: Double?
    private var latestFrame: FrameSnapshot?

    /// Only preparation compares immutable tracks. Registering the same layer
    /// for a second surface or rebuild preserves the launch's consumed position.
    @discardableResult
    func register(
        layerID: Int,
        selection: ScenePuppetAnimationSelection,
        authoredLayers: [ScenePuppetAnimationLayer]
    ) -> Result<Void, Failure> {
        var clips: [ClipDefinition] = []
        var nextAuthoredPosition = 0
        for clip in selection.clips {
            guard let position = authoredLayers.indices.dropFirst(nextAuthoredPosition)
                .first(where: { authoredLayers[$0] == clip.layer }) else {
                return .failure(.unmatchedAnimationLayer(layerID: layerID))
            }
            nextAuthoredPosition = position + 1
            clips.append(.init(identity: .init(authoredPosition: position,
                animationLayerID: clip.layer.id), layer: clip.layer,
                animation: clip.animation))
        }
        let definition = LayerDefinition(composition: selection.composition.rawValue, clips: clips)
        lock.lock()
        defer { lock.unlock() }
        if let previous = definitions[layerID] {
            return previous == definition ? .success(())
                : .failure(.conflictingDefinition(layerID: layerID))
        }
        definitions[layerID] = definition
        states[layerID] = clips.map { _ in ClipState() }
        return .success(())
    }

    /// Consume cadence once, before any surface or GPU work. Hidden clips keep
    /// their position but publish nil samples so the existing bind-pose fallback
    /// remains intact. Restoring visibility adds only this cadence's increment.
    func advance(
        frameIndex: UInt64,
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot
    ) -> FrameSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if let latestFrame, frameIndex < latestFrame.frameIndex { return latestFrame }
        let sameCadence = latestFrame?.frameIndex == frameIndex
        let currentSceneTime = sameCadence ? latestFrame!.sceneTime : sceneTime
        var layers: [Int: LayerFrame] = sameCadence ? latestFrame!.layers : [:]
        if let latestFrame, sameCadence, layers.count == definitions.count { return latestFrame }
        let elapsed = sameCadence ? 0 : max(0, currentSceneTime - (lastSceneTime ?? currentSceneTime))
        layers.reserveCapacity(definitions.count)
        for (layerID, definition) in definitions {
            // Paused surface rebuilding may register a newly prepared layer
            // after this cadence was consumed. Fill only that missing parent;
            // existing samples and their visibility decisions remain frozen.
            guard layers[layerID] == nil else { continue }
            var local = states[layerID]!
            var samples: [ScenePuppetAnimationEvaluator.FrameSample?] = []
            samples.reserveCapacity(definition.clips.count)
            for index in definition.clips.indices {
                let clip = definition.clips[index]
                let visible = clip.isVisible(layerID: layerID, snapshot: dynamicValues)
                if local[index].playbackTime == nil {
                    // Keep existing first-visible nonzero sceneTime behavior;
                    // an initially hidden layer starts its frozen position at 0.
                    local[index].playbackTime = visible ? max(0, currentSceneTime) : 0
                } else if visible {
                    local[index].playbackTime! += elapsed
                }
                samples.append(visible ? ScenePuppetAnimationEvaluator.frameSample(
                    sceneTime: local[index].playbackTime!, rate: clip.layer.rate ?? 1,
                    animation: clip.animation
                ) : nil)
            }
            states[layerID] = local
            layers[layerID] = LayerFrame(samples: samples)
        }
        let frame = FrameSnapshot(frameIndex: frameIndex, sceneTime: currentSceneTime, layers: layers)
        latestFrame = frame
        lastSceneTime = currentSceneTime
        return frame
    }
}
