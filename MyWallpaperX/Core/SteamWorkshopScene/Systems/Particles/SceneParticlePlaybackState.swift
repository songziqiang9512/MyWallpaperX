import Foundation
import Metal
import simd

final class SceneParticlePlaybackState {
    private nonisolated static let maximumRealtimeSimulationDelta: TimeInterval = 2.0 / 60.0

    let lifecycleIdentity = UUID()
    var requiredPipelineVariants: Set<SceneParticlePipelineVariant> { runtime.requiredPipelineVariants }
    private let runtime: SceneParticleRuntime
    private var retainedLayerIDs: Set<Int>
    var preparedLayerIDs: Set<Int> { didTeardown ? [] : retainedLayerIDs }
    var pointerControlPointDemands: Set<Int> {
        runtime.pointerControlPointDemands
    }
    private(set) var batches: [SceneParticleDrawBatch]
    /// Resource admission history. Empty batches are valid and do not prove
    /// that a layer produced particles or reached the GPU.
#if DEBUG
    private(set) var stickyBatchLayerIDs: Set<Int> = []
    /// Nonempty batches in committed host frames, retained across dormant
    /// periods. This is producer evidence, not GPU completion or visibility.
    private(set) var committedNonemptyBatchLayerIDs: Set<Int> = []
    private var reportedAudioEvaluationIdentities:
        Set<SceneParticleRuntimeAudioEvaluationIdentity> = []
    private var reportedComponentObservationIdentities:
        Set<SceneParticleRuntimeComponentObservationIdentity>? =
            SceneParticleDefinitionParser.componentObservationEnabled ? [] : nil
    private var didReportComponentObservationTruncation = false
#endif
    private var didTeardown = false
    var hasAudioConsumer: Bool { runtime.hasAudioConsumer }
    var lifecycleSnapshot: SceneParticleRuntimeLifecycleSnapshot {
        runtime.lifecycleSnapshot
    }

    init(
        descriptor: SceneRenderDescriptor,
        preparedAssets: SceneParticleAssetGraph,
        device: MTLDevice,
        textureLoader: SceneTextureLoader = SceneTextureLoader(),
        layerImage: SceneParticleLayerImageEmitterCompilation = .empty,
        preparedParticleVisibilityLayerIDs: Set<Int> = [],
        initialDynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        initialPlayback: [Int: SceneParticlePlaybackSnapshot] = [:],
        destroyedAuthoredLayerIDs: Set<Int> = [],
        rootPrewarmStepBudget: Int? = 3_600,
        shouldCancelPrewarm: (() -> Bool)? = nil
    ) {
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            preparedAssets: preparedAssets,
            device: device,
            textureLoader: textureLoader,
            layerImage: layerImage,
            staticWorldSpaceFrames: descriptor.staticParticleWorldSpaceFrames,
            preparedParticleVisibilityLayerIDs:
                preparedParticleVisibilityLayerIDs,
            initialDynamicValues: initialDynamicValues,
            initialPlayback: initialPlayback,
            destroyedAuthoredLayerIDs: destroyedAuthoredLayerIDs,
            rootPrewarmStepBudget: rootPrewarmStepBudget,
            shouldCancelPrewarm: shouldCancelPrewarm
        )
        self.runtime = runtime
        self.retainedLayerIDs = Set(runtime.activeLayerIDs)
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let initialWorldFrames = SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: descriptor, byID: layersByID, snapshot: initialDynamicValues,
            staticFrames: SceneLayerWorldFrameResolver.compute(
                layers: descriptor.layers, byID: layersByID,
                sceneOrthoHeight: descriptor.camera.orthoHeight
            )
        )
        self.batches = runtime.advance(
            by: 0, dynamicValues: initialDynamicValues, layerWorldFrames: initialWorldFrames
        )
#if DEBUG
        stickyBatchLayerIDs.formUnion(self.batches.map(\.layerID))
#endif
    }

    func playbackLiveCount(charging: (UInt64) throws -> Void) throws -> Int {
        try runtime.playbackLiveCount(charging: charging)
    }
    var playbackSimulators: [(Int, SceneParticleSimulator)] { didTeardown ? [] : runtime.playbackSimulators }
    func playbackVisibility(layerID: Int, dynamicValues: SceneDynamicSnapshot)
        -> SceneParticlePlaybackVisibility? {
        runtime.playbackVisibility(layerID: layerID, dynamicValues: dynamicValues)
    }
    func installPlaybackCandidate(layerID: Int, state: SceneParticleSimulator.FrameSnapshot,
                                  visibility: SceneParticlePlaybackVisibility?) {
        runtime.installPlaybackCandidate(layerID: layerID, state: state, visibility: visibility)
    }
    func emissionContext(layerID: Int, dynamicValues: SceneDynamicSnapshot,
                         pointerLocalPosition: SIMD3<Double>?, audio: SceneParticleAudioInput,
                         worldFrame: simd_float4x4?) throws -> SceneParticleSimulator.EmissionContext {
        guard !didTeardown else { throw SceneParticleEmissionFailure.unavailable }
        return try runtime.emissionContext(layerID: layerID, dynamicValues: dynamicValues,
            pointerLocalPosition: pointerLocalPosition, audio: audio, worldFrame: worldFrame)
    }
    func clearStoppedPlaybackCaches(_ layerIDs: Set<Int>) {
        runtime.clearStoppedPlaybackCaches(layerIDs)
        batches.removeAll { layerIDs.contains($0.layerID) }
    }

    func playbackObservation(layerID: Int) -> SceneParticlePlaybackObservation? {
        runtime.playbackObservation(layerID: layerID)
    }

    func validatePlaybackTransitions(_ transitions: [SceneParticlePlaybackTransition]) -> Bool {
        !didTeardown && runtime.validatePlaybackTransitions(transitions)
    }

    func applyPlaybackTransitions(_ transitions: [SceneParticlePlaybackTransition]) {
        let stopped = Set(transitions.compactMap { transition -> Int? in
            guard transition.action == .stop,
                  let current = runtime.playbackObservation(layerID: transition.layerID),
                  transition.revision > current.revision else { return nil }
            return transition.layerID
        })
        runtime.applyPlaybackTransitions(transitions)
        batches.removeAll { stopped.contains($0.layerID) }
    }

    func advance(
        by simulationFrameDelta: TimeInterval,
        dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        pointerLocalPositions: [Int: SIMD3<Double>] = [:],
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        layerWorldFrames: [Int: simd_float4x4] = [:]
    ) -> [SceneParticleDrawBatch] {
        guard !didTeardown else { return [] }
        batches.removeAll(keepingCapacity: true)
        batches = runtime.advance(
            by: Self.boundedRealtimeSimulationDelta(simulationFrameDelta),
            dynamicValues: dynamicValues,
            pointerLocalPositions: pointerLocalPositions,
            audioInput: SceneParticleAudioInput(
                left: audioSpectrum.left,
                right: audioSpectrum.right,
                generation: audioSpectrum.generation
            ),
            layerWorldFrames: layerWorldFrames
        )
#if DEBUG
        stickyBatchLayerIDs.formUnion(batches.map(\.layerID))
        for batch in batches where !batch.instances.isEmpty {
            committedNonemptyBatchLayerIDs.insert(batch.layerID)
        }
        publishCommittedAudioEvaluationObservations()
        publishCommittedComponentObservations()
#endif
        return batches
    }

#if DEBUG
    private func publishCommittedComponentObservations() {
        guard reportedComponentObservationIdentities != nil else { return }
        for observation in runtime.consumeComponentObservations() {
            let identity = SceneParticleRuntimeComponentObservationIdentity(observation)
            guard reportedComponentObservationIdentities?.contains(identity) == false else { continue }
            let reportingTruncation = (reportedComponentObservationIdentities?.count ?? 0) >= 8192
            if reportingTruncation {
                guard !didReportComponentObservationTruncation else { continue }
                didReportComponentObservationTruncation = true
            } else {
                reportedComponentObservationIdentities?.insert(identity)
            }
            let value = observation.evaluation
            var payload: [String: Any] = [
                "schemaVersion": 1, "layerID": observation.layerID,
                "particlePath": observation.particlePath,
                "childTemplateIndex": observation.childTemplateIndex as Any? ?? NSNull(),
                "childSystemID": observation.childSystemID as Any? ?? NSNull(),
                "childParticlePath": observation.childParticlePath as Any? ?? NSNull(),
                "category": value.category, "componentIndex": value.componentIndex,
                "kind": value.kind, "stage": value.stage, "reason": value.reason,
                "origin": value.origin, "simulationTime": value.simulationTime,
                "particleID": value.particleID as Any? ?? NSNull(),
                "observationScope": "first-fact-per-template",
                "instanceWitness": "unknown", "finalContribution": "unknown"
            ]
            if reportingTruncation {
                payload["category"] = "observation"
                payload["componentIndex"] = -1
                payload["stage"] = "truncated"
                payload["reason"] = "playback-first-fact-capacity-8192"
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                NSLog("MWX SCENE PARTICLE COMPONENT OBSERVATION: %@", String(decoding: data, as: UTF8.self))
            } catch {
                NSLog("MWX particle component observation serialization failed: %@", String(describing: error))
            }
        }
    }

    private func publishCommittedAudioEvaluationObservations() {
        for observation in runtime.consumeAudioEvaluationObservations() {
            let evaluation = observation.evaluation
            let identity = SceneParticleRuntimeAudioEvaluationIdentity(
                layerID: observation.layerID,
                particlePath: observation.particlePath,
                componentKind: evaluation.componentKind,
                componentIndex: evaluation.componentIndex
            )
            guard reportedAudioEvaluationIdentities.insert(identity).inserted else {
                continue
            }
            let encodedPath = Data(observation.particlePath.utf8).base64EncodedString()
            NSLog(
                "MWX particle audio: consumer=particle-component layer=%d "
                    + "pathBase64=%@ component=%@ index=%d generation=%llu "
                    + "channel=%d frequencyStart=%d frequencyEnd=%d "
                    + "selectedNonZero=%d route=generic-only",
                observation.layerID,
                encodedPath,
                evaluation.componentKind.rawValue,
                evaluation.componentIndex,
                evaluation.generation,
                evaluation.channel,
                evaluation.frequencyStart,
                evaluation.frequencyEnd,
                evaluation.selectedNonZeroInputCount
            )
        }
    }
#endif

    /// Product playback drops overdue wall-clock debt instead of recursively making
    /// an already slow frame run an unbounded number of fixed simulation steps.
    nonisolated static func boundedRealtimeSimulationDelta(
        _ simulationFrameDelta: TimeInterval
    ) -> TimeInterval {
        guard simulationFrameDelta.isFinite else { return 0 }
        return min(max(simulationFrameDelta, 0), maximumRealtimeSimulationDelta)
    }

    func retire(layerIDs: Set<Int>) {
        let retired = retainedLayerIDs.intersection(layerIDs)
        guard !retired.isEmpty else { return }
        runtime.retire(layerIDs: retired)
        retainedLayerIDs.subtract(retired)
        batches.removeAll { retired.contains($0.layerID) }
    }

    /// Returns one observation for the only successful active -> terminated
    /// transition. Repeated host teardown is deliberately idempotent.
    func teardown(reason: String) -> SceneParticlePlaybackTeardownObservation? {
        guard !didTeardown else { return nil }
        didTeardown = true
        let observation = SceneParticlePlaybackTeardownObservation(
            lifecycleIdentity: lifecycleIdentity,
            reason: reason,
            snapshotBeforeTeardown: runtime.lifecycleSnapshot,
            batchCountBeforeTeardown: batches.count
        )
        batches.removeAll(keepingCapacity: false)
        runtime.teardown()
        return observation
    }

#if DEBUG
    func loadReportLines(descriptor: SceneRenderDescriptor) -> [String] {
        let particleLayers = descriptor.layers.filter { $0.contentKind == "particle" }
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let visibleLayers = particleLayers.filter { visibleIDs.contains($0.id) }
        let renderableLayers = visibleLayers.filter {
            $0.particleInstanceOverride?.alpha?.isStaticZeroScalar != true
        }
        let batchesByID = Dictionary(grouping: batches, by: \.layerID)
        var lines = [
            "particle authored: \(particleLayers.count)",
            "particle visible: \(visibleLayers.count)",
            "particle lifecycle: id=\(lifecycleIdentity.uuidString) state=active "
                + "layers=\(lifecycleSnapshot.activeLayerCount)"
        ]

        for layer in particleLayers {
            let name = layer.name ?? "(unnamed)"
            guard visibleIDs.contains(layer.id) else {
                lines.append("particle layer \(layer.id) \"\(name)\": skipped hidden")
                continue
            }
            guard layer.particleInstanceOverride?.alpha?.isStaticZeroScalar != true else {
                lines.append("particle layer \(layer.id) \"\(name)\": skipped transparent")
                continue
            }
            guard let batch = batchesByID[layer.id]?.first else {
                lines.append("particle layer \(layer.id) \"\(name)\": unavailable")
                continue
            }
            lines.append(
                "particle layer \(layer.id) \"\(name)\": OK \(batch.texture.width)x\(batch.texture.height) "
                    + "blend=\(batch.renderState.blendMode.rawValue) "
                    + "initial=\(batch.instances.count) perspective=\(batch.usesPerspective) "
                    + "refract=\(batch.refraction != nil)"
            )
        }
        for summary in runtime.childRuntimeSummaries {
            lines.append("particle child runtime \(summary)")
        }
        for value in runtime.diagnostics {
            lines.append(
                "particle diagnostic \(value.kind.rawValue) layer=\(value.layerID.map(String.init) ?? "nil") "
                    + "path=\(value.particlePath) detail=\(value.detail ?? "")"
            )
        }
        lines.append(Self.loadedSummaryLine(
            batchLayerIDs: batches.map(\.layerID),
            visibleLayerCount: renderableLayers.count
        ))
        lines.append(
            "particle sticky loaded: \(stickyBatchLayerIDs.count) / \(renderableLayers.count)"
        )
        lines.append(
            "particle current nonempty: layers=\(Set(batches.filter { !$0.instances.isEmpty }.map(\.layerID)).sorted())"
        )
        lines.append(
            "particle committed nonempty: layers=\(committedNonemptyBatchLayerIDs.sorted())"
        )
        lines.append(
            "particle refract loaded: \(Set(batches.filter { $0.refraction != nil }.map(\.layerID)).count)"
        )
        lines.append("particle initial live: \(batches.reduce(0) { $0 + $1.instances.count })")
        lines.append("particle skipped hidden: \(particleLayers.count - visibleLayers.count)")
        lines.append("particle skipped transparent: \(visibleLayers.count - renderableLayers.count)")
        return lines
    }

    nonisolated static func loadedSummaryLine(
        batchLayerIDs: [Int],
        visibleLayerCount: Int
    ) -> String {
        "particle loaded: \(Set(batchLayerIDs).count) / \(visibleLayerCount)"
    }
#endif
}
