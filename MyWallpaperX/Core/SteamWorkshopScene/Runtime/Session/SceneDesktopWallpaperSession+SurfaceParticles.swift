import AppKit
import Foundation

extension SceneDesktopWallpaperSession.Surface {
    func particleEmissionContext(layerID: Int, timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot, topology: SceneScriptLayerTopologySnapshot,
        attachments: ScenePuppetAttachmentFrameSnapshot, audio: SceneAudioSpectrumSnapshot
    ) throws -> SceneParticleSimulator.EmissionContext {
        guard let particlePlayback else { throw SceneParticleEmissionFailure.unavailable }
        let context = metalView.makeFrameContext(timing: timing, dynamicValues: dynamicValues,
            parallax: metalView.parallaxPointerSmoother.preview(delta: timing.simulationFrameTime,
                delay: dynamicValues.cameraPropertyProjection().parallaxDelay ?? metalView.renderer.renderDescriptor.camera.parallaxDelay),
            audioSpectrum: audio)
        let projection = metalView.renderer.resolveFrameWorldProjection(layerTopology: topology,
            dynamicValues: dynamicValues, puppetAttachmentFrames: attachments)
        let pointers = particlePlayback.pointerControlPointDemands.contains(layerID)
            ? metalView.renderer.particlePointerLocalPositions(frameContext: context,
                cameraFrame: metalView.renderer.makeCameraFrame(frameContext: context,
                    descriptor: projection.descriptor, layersByID: projection.layersByID,
                    worldFrames: projection.worldFrames, adjustment: metalView.cameraAdjustment), frameProjection: projection,
                demands: CollectionOfOne(layerID)) : [:]
        return try particlePlayback.emissionContext(layerID: layerID, sceneTime: timing.sceneTime, dynamicValues: dynamicValues,
            pointerLocalPosition: pointers[layerID],
            audio: .init(left: audio.left, right: audio.right, generation: audio.generation),
            worldFrame: projection.worldFrames[layerID])
    }

    func advanceParticles(
        timing: SceneFrameTiming,
        renderFrameInterval: TimeInterval?,
        dynamicValues: SceneDynamicSnapshot,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        frameProjection: SceneMetalRendererFrameWorldProjection,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil
    ) -> [SceneParticleDrawBatch] {
        guard let particlePlayback else { return [] }
#if DEBUG
        performanceTelemetry?.beginStage("particle-pointer-projection")
#endif

        let pointerLocalPositions = metalView.renderer.particlePointerLocalPositions(
            frameContext: frameContext,
            cameraFrame: cameraFrame,
            frameProjection: frameProjection,
            demands: particlePlayback.pointerControlPointDemands
        )
#if DEBUG
        performanceTelemetry?.endStage("particle-pointer-projection")
#endif

#if DEBUG
        performanceTelemetry?.beginStage("particle-advance")
#endif

        let batches = particlePlayback.advance(
            by: timing.simulationFrameTime, sceneTime: timing.sceneTime,
            rawFrameDelta: timing.rawFrameTime,
            renderFrameInterval: renderFrameInterval,
            dynamicValues: dynamicValues,
            pointerLocalPositions: pointerLocalPositions,
            audioSpectrum: frameContext.audioSpectrum,
            layerWorldFrames: frameProjection.worldFrames
        )
#if DEBUG
        performanceTelemetry?.endStage("particle-advance")
#endif

        return batches
    }

    func teardownParticlePlayback(reason: SceneGraphExecutionResetReason) {
        defer { particlePlayback = nil }
        guard let observation = particlePlayback?.teardown(reason: reason.rawValue) else {
            return
        }
        let snapshot = observation.snapshotBeforeTeardown
#if DEBUG
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
#endif
    }
}

#if DEBUG
extension SceneDesktopWallpaperSession.Surface {
    func logExplicitParticleInstall(_ transitions: [SceneParticlePlaybackTransition], frame: UInt64, surface: UInt32) {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return }
        let emitted = Set(transitions.filter { $0.action == .emit }.map(\.layerID))
        for (id, simulator) in particlePlayback?.playbackSimulators ?? [] where emitted.contains(id) {
            let births = simulator.birthEvents.dropFirst(simulator.explicitBirthEventStart ?? simulator.birthEvents.count)
            NSLog("MWX DEBUG SCENE: phase=particle-explicit-installed frame=%llu layer=%d surface=%u revision=%llu births=%d live=%d firstID=%@ lastID=%@",
                  frame, id, surface, simulator.playback.revision, births.count, simulator.particles.count,
                  births.first.map { String($0.id) } ?? "none", births.last.map { String($0.id) } ?? "none")
        }
    }
}
#endif


extension SceneDesktopWallpaperSession {
    static func surfaceScreens(topology: [SceneScreenTopology])
        -> [(NSScreen, CGDirectDisplayID)] {
        let allScreens = NSScreen.screens
        let target = topology.isEmpty ? SceneScreenTopology.capture(screens: allScreens) : topology
        var liveScreensByID = Dictionary(uniqueKeysWithValues: allScreens.compactMap { screen in
            screenID(for: screen).map { ($0, screen) }
        })
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
           let requested = ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_SURFACE_COUNT"].flatMap(Int.init),
           (2...4).contains(requested),
           let firstID = liveScreensByID.keys.min(),
           let first = liveScreensByID[firstID] {
            for index in 1..<requested {
                liveScreensByID[CGDirectDisplayID.max - UInt32(index)] = first
            }
        }
#endif
        return target.compactMap { entry in
            liveScreensByID[entry.displayID].map { ($0, entry.displayID) }
        }
    }

#if DEBUG
    static func debugSurfacePool() -> [SceneScreenTopology] {
        var screens = SceneScreenTopology.capture()
        if let requested = ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_SURFACE_COUNT"].flatMap(Int.init),
           (2...4).contains(requested), let first = screens.first {
            while screens.count < requested {
                screens.append(.init(displayID: CGDirectDisplayID.max - UInt32(screens.count),
                    frame: first.frame, backingScaleFactor: first.backingScaleFactor,
                    modeRefreshRate: first.modeRefreshRate, unknownModeRefreshLimit: first.unknownModeRefreshLimit))
            }
        }
        return screens
    }

    static func debugInitialSurfaceTopology(_ topology: [SceneScreenTopology]) -> [SceneScreenTopology] {
        guard ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_SURFACE_COUNT"] != nil
            || ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_SURFACE_INITIAL_INDICES"] != nil else { return topology }
        let pool = debugSurfacePool()
        if let raw = ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_SURFACE_INITIAL_INDICES"] {
            let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
            let indices = parts.compactMap { Int($0) }
            guard indices.count == parts.count, !indices.isEmpty,
                  Set(indices).count == indices.count, indices.allSatisfy({ pool.indices.contains($0) }) else { return topology }
            return indices.map { pool[$0] }
        }
        return pool
    }
#endif
}
