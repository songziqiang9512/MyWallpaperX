import Foundation
import Metal

final class SceneParticlePlaybackState {
    private struct FrameTransaction {
        let runtime: SceneParticleRuntime.FrameSnapshot
        let batches: [SceneParticleDrawBatch]
    }

    private nonisolated static let maximumRealtimeSimulationDelta: TimeInterval = 2.0 / 60.0

    let lifecycleIdentity = UUID()
    let pipeline: SceneParticleMetalPipeline
    private let runtime: SceneParticleRuntime
    /// Prepared once with the playback graph; no per-frame particle topology
    /// scan is needed to decide whether pointer projection is required.
    let pointerControlPointLayerIDs: Set<Int>
    private(set) var batches: [SceneParticleDrawBatch]
    /// Union of layer IDs that produced a draw batch at ANY point in the run.
    /// The snapshot-instant batch list undercounts bursty/short-lifetime
    /// particle systems whose particles may all be dead between frames; this
    /// sticky set is the "did the system ever execute" evidence.
    private(set) var stickyBatchLayerIDs: Set<Int> = []
    private var didTeardown = false
    private var frameTransaction: FrameTransaction?
    var hasAudioConsumer: Bool { runtime.hasAudioConsumer }
    var lifecycleSnapshot: SceneParticleRuntimeLifecycleSnapshot {
        runtime.lifecycleSnapshot
    }

    init?(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        resourceView: SceneResourceView? = nil,
        textureLoader: SceneTextureLoader = SceneTextureLoader(),
        layerImage: SceneParticleLayerImageEmitterCompilation = .empty,
        initialDynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0)
    ) {
        guard let pipeline = SceneParticleMetalPipeline(device: device) else { return nil }
        self.pipeline = pipeline
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cacheDirectory,
            device: device,
            resourceView: resourceView,
            textureLoader: textureLoader,
            layerImageEmissionMaps: layerImage.mapsByLayerID,
            initialDiagnostics: layerImage.diagnostics,
            staticWorldSpaceFrames: descriptor.staticParticleWorldSpaceFrames,
            initialDynamicValues: initialDynamicValues
        )
        self.runtime = runtime
        self.pointerControlPointLayerIDs = runtime.pointerControlPointLayerIDs
        self.batches = runtime.advance(by: 0)
        stickyBatchLayerIDs.formUnion(self.batches.map(\.layerID))
    }

    func advance(
        by simulationFrameDelta: TimeInterval,
        dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        pointerLocalPositions: [Int: SIMD3<Double>] = [:],
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent
    ) -> [SceneParticleDrawBatch] {
        guard !didTeardown else { return [] }
        batches.removeAll(keepingCapacity: true)
        batches = runtime.advance(
            by: Self.boundedRealtimeSimulationDelta(simulationFrameDelta),
            dynamicValues: dynamicValues,
            pointerLocalPositions: pointerLocalPositions,
            audioInput: SceneParticleAudioInput(
                left: audioSpectrum.left,
                right: audioSpectrum.right
            )
        )
        stickyBatchLayerIDs.formUnion(batches.map(\.layerID))
        return batches
    }

    /// Begins a host-frame transaction before simulation mutates its live
    /// producer state. The host commits it only after every surface submits;
    /// a deferred/dropped surface restores the prior particle timeline.
    func prepareFrame() {
        guard !didTeardown, frameTransaction == nil else { return }
        frameTransaction = FrameTransaction(
            runtime: runtime.frameSnapshot(),
            batches: batches
        )
    }

    func commitPreparedFrame() {
        frameTransaction = nil
    }

    func discardPreparedFrame() {
        guard let frameTransaction else { return }
        runtime.restoreFrame(frameTransaction.runtime)
        batches = frameTransaction.batches
        stickyBatchLayerIDs.formUnion(batches.map(\.layerID))
        self.frameTransaction = nil
    }

    /// Product playback drops overdue wall-clock debt instead of recursively making
    /// an already slow frame run an unbounded number of fixed simulation steps.
    nonisolated static func boundedRealtimeSimulationDelta(
        _ simulationFrameDelta: TimeInterval
    ) -> TimeInterval {
        guard simulationFrameDelta.isFinite else { return 0 }
        return min(max(simulationFrameDelta, 0), maximumRealtimeSimulationDelta)
    }

    /// Returns one observation for the only successful active -> terminated
    /// transition. Repeated host teardown is deliberately idempotent.
    func teardown(reason: String) -> SceneParticlePlaybackTeardownObservation? {
        guard !didTeardown else { return nil }
        didTeardown = true
        frameTransaction = nil
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
            "particle sticky loaded: \(stickyBatchLayerIDs.union(batches.map(\.layerID)).count) / \(renderableLayers.count)"
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
}
