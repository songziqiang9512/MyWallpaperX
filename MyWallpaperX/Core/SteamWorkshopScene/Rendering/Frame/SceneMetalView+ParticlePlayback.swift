import Foundation

extension SceneMetalView {
    var particlePlaybackIdentity: UUID? { particlePlayback?.lifecycleIdentity }
    var particlePlaybackSimulators: [(Int, SceneParticleSimulator)] { particlePlayback?.playbackSimulators ?? [] }
    func particlePlaybackVisibility(layerID: Int, dynamicValues: SceneDynamicSnapshot)
        -> SceneParticlePlaybackVisibility? {
        particlePlayback?.playbackVisibility(layerID: layerID, dynamicValues: dynamicValues)
    }
    func installParticlePlaybackCandidate(layerID: Int, state: SceneParticleSimulator.FrameSnapshot,
                                         visibility: SceneParticlePlaybackVisibility?) {
        precondition(particlePlayback != nil)
        particlePlayback?.installPlaybackCandidate(layerID: layerID, state: state, visibility: visibility)
    }
    func particleLiveCount(charging: (UInt64) throws -> Void) throws -> Int {
        try particlePlayback?.playbackLiveCount(charging: charging) ?? 0
    }
    func clearStoppedParticlePlaybackCaches(_ ids: Set<Int>) { particlePlayback?.clearStoppedPlaybackCaches(ids) }
    func particleEmissionContext(layerID: Int, timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot, topology: SceneScriptLayerTopologySnapshot,
        attachments: ScenePuppetAttachmentFrameSnapshot, audio: SceneAudioSpectrumSnapshot
    ) throws -> SceneParticleSimulator.EmissionContext {
        guard let particlePlayback else { throw SceneParticleEmissionFailure.unavailable }
        let context = makeFrameContext(timing: timing, dynamicValues: dynamicValues,
            parallax: parallaxPointerSmoother.preview(delta: timing.simulationFrameTime,
                delay: dynamicValues.cameraPropertyProjection().parallaxDelay ?? renderer.renderDescriptor.camera.parallaxDelay),
            audioSpectrum: audio)
        let projection = renderer.resolveFrameWorldProjection(layerTopology: topology,
            dynamicValues: dynamicValues, puppetAttachmentFrames: attachments)
        let pointers = renderer.particlePointerLocalPositions(frameContext: context,
            cameraFrame: renderer.makeCameraFrame(frameContext: context), frameProjection: projection,
            demandedLayerIDs: particlePlayback.pointerControlPointLayerIDs.intersection([layerID]))
        return try particlePlayback.emissionContext(layerID: layerID, dynamicValues: dynamicValues,
            pointerLocalPosition: pointers[layerID],
            audio: .init(left: audio.left, right: audio.right, generation: audio.generation),
            worldFrame: projection.worldFrames[layerID])
    }

    func particlePlaybackObservation(layerID: Int) -> SceneParticlePlaybackObservation? {
        particlePlayback?.playbackObservation(layerID: layerID)
    }

    func validateParticlePlaybackTransitions(_ transitions: [SceneParticlePlaybackTransition]) -> Bool {
        transitions.isEmpty || particlePlayback?.validatePlaybackTransitions(transitions) == true
    }

    func applyParticlePlaybackTransitions(_ transitions: [SceneParticlePlaybackTransition]) {
        particlePlayback?.applyPlaybackTransitions(transitions)
    }

    var hasParticleAudioConsumer: Bool {
        particlePlayback?.hasAudioConsumer == true
    }

    func advanceParticles(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        frameProjection: SceneMetalRendererFrameWorldProjection,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil
    ) -> [SceneParticleDrawBatch] {
        guard let particlePlayback else { return [] }
        performanceTelemetry?.beginStage("particle-pointer-projection")
        let pointerLocalPositions = renderer.particlePointerLocalPositions(
            frameContext: frameContext,
            cameraFrame: cameraFrame,
            frameProjection: frameProjection,
            demandedLayerIDs: particlePlayback.pointerControlPointLayerIDs
        )
        performanceTelemetry?.endStage("particle-pointer-projection")
        performanceTelemetry?.beginStage("particle-advance")
        let batches = particlePlayback.advance(
            by: timing.simulationFrameTime,
            dynamicValues: dynamicValues,
            pointerLocalPositions: pointerLocalPositions,
            audioSpectrum: frameContext.audioSpectrum,
            layerWorldFrames: frameProjection.worldFrames
        )
        performanceTelemetry?.endStage("particle-advance")
        return batches
    }

    func teardownParticlePlayback(reason: SceneGraphExecutionResetReason) {
        defer { particlePlayback = nil }
        guard let observation = particlePlayback?.teardown(reason: reason.rawValue) else {
            return
        }
        let snapshot = observation.snapshotBeforeTeardown
        NSLog(
            "MWX Particle: lifecycle=teardown id=%@ reason=%@ layers=%d rootSystems=%d childSystems=%d rootParticles=%d childParticles=%d batches=%d route=generic-only",
            observation.lifecycleIdentity.uuidString,
            observation.reason,
            snapshot.activeLayerCount,
            snapshot.rootSystemCount,
            snapshot.childSystemCount,
            snapshot.rootParticleCount,
            snapshot.childParticleCount,
            observation.batchCountBeforeTeardown
        )
    }
}

extension SceneMetalView {
    func particleEmissionTransformValues(owner: OpaquePointer, layerID: Int) throws
        -> [SceneDynamicTarget: SceneDynamicValue] {
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var visited = Set<Int>()
        var current: Int? = layerID
        while let id = current {
            guard visited.insert(id).inserted, let layer = renderer.layersByID[id] else {
                throw SceneScriptScalarRuntimeFailure.staleOwner
            }
            var origin = [Double](repeating: 0, count: 3)
            var scale = origin, angles = origin
            guard mwx_scene_quickjs_owner_particle_transform(owner, Int64(id), &origin, &scale, &angles) == MWX_SCENE_QUICKJS_OK else {
                throw SceneScriptScalarRuntimeFailure.staleOwner
            }
            values[.layer(layerID: id, field: .origin)] = .vector3(origin[0], origin[1], origin[2])
            values[.layer(layerID: id, field: .scale)] = .vector3(scale[0], scale[1], scale[2])
            values[.layer(layerID: id, field: .angles)] = .vector3(
                SceneScriptAngleUnits.radians(fromDegrees: angles[0]),
                SceneScriptAngleUnits.radians(fromDegrees: angles[1]),
                SceneScriptAngleUnits.radians(fromDegrees: angles[2]))
            current = layer.parentID
        }
        return values
    }
}

#if DEBUG
extension SceneMetalView {
    func logExplicitParticleInstall(_ transitions: [SceneParticlePlaybackTransition], frame: UInt64, surface: UInt32) {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return }
        let emitted = Set(transitions.filter { $0.action == .emit }.map(\.layerID))
        for (id, simulator) in particlePlaybackSimulators where emitted.contains(id) {
            let births = simulator.birthEvents.dropFirst(simulator.explicitBirthEventStart ?? simulator.birthEvents.count)
            NSLog("MWX DEBUG SCENE: phase=particle-explicit-installed frame=%llu layer=%d surface=%u revision=%llu births=%d live=%d firstID=%@ lastID=%@",
                  frame, id, surface, simulator.playback.revision, births.count, simulator.particles.count,
                  births.first.map { String($0.id) } ?? "none", births.last.map { String($0.id) } ?? "none")
        }
    }
}
#endif
