import Foundation

extension SceneDesktopWallpaperSession {
    func beginParticleEmissionFrame(
        context: SceneDesktopWallpaperLaunchContext, timing: SceneFrameTiming,
        preliminary: SceneDynamicSnapshotResolution,
        topology: SceneScriptLayerTopologySnapshot,
        poses: [UInt32: ScenePuppetScriptPoseFrame], audio: SceneAudioSpectrumSnapshot,
        inputSurfaceIDs: Set<UInt32>
    ) -> SceneParticlePlaybackTransaction? {
        guard let domain = context.propertyVectorScriptProgram.domain else { return nil }
        let capturedSurfaces = surfaces
        var identities: [UInt32: UUID?] = [:]
        func captureInstances() -> [SceneParticlePlaybackTransaction.Instance] {
            identities = capturedSurfaces.mapValues { $0.metalView.particlePlaybackIdentity }
            return capturedSurfaces.flatMap { id, surface in
                surface.metalView.particlePlaybackSimulators.map { layerID, simulator in
                    .init(surfaceID: id, layerID: layerID, simulator: simulator,
                        visibility: surface.metalView.particlePlaybackVisibility(layerID: layerID,
                            dynamicValues: preliminary.snapshot),
                        install: { state, visibility in MainActor.assumeIsolated {
                            surface.metalView.installParticlePlaybackCandidate(layerID: layerID,
                                state: state, visibility: visibility)
                        } })
                }
            }
        }
        let metadataBytes = 4096 + capturedSurfaces.count * (context.runtimeInput.renderDescriptor.layers.count + 1) * 2048
        let transaction = SceneParticlePlaybackTransaction(instances: captureInstances(), metadataBytes: metadataBytes, surfaceIDs: inputSurfaceIDs,
            charge: { try domain.chargeParticleWork($0, bytes: $1) },
            release: { domain.releaseParticleStorage($0) },
            isCurrent: { MainActor.assumeIsolated {
                !self.surfaces.isEmpty && Set(self.surfaces.keys) == self.preparedSurfaceIDs
                    && Set(self.surfaces.keys) == inputSurfaceIDs
                    && Set(capturedSurfaces.keys) == inputSurfaceIDs
                    && capturedSurfaces.allSatisfy { id, surface in
                        self.surfaces[id] === surface
                            && surface.scriptGeneration == context.propertyVectorScriptProgram.generation
                            && surface.metalView.particlePlaybackIdentity == identities[id]!
                    }
            } }, totalLiveCount: { try MainActor.assumeIsolated {
                try capturedSurfaces.values.reduce(0) { try $0 + $1.metalView.particleLiveCount(charging: { try domain.chargeParticleWork($0, bytes: 0) }) }
            } })
        domain.beginParticlePlaybackFrame(onBoundary: { owner, discarded in
            transaction.callbackBoundary(owner: UInt(bitPattern: owner), discardOwner: discarded)
        }) { owner, raw in
            guard Thread.isMainThread else { throw SceneScriptScalarRuntimeFailure.staleOwner }
            return try MainActor.assumeIsolated {
                let prefixBytes = (Int(mwx_scene_quickjs_owner_particle_playback_command_count(owner)) + 1)
                    * (MemoryLayout<SceneScriptParticlePlaybackCommand>.stride
                       + MemoryLayout<SceneParticlePlaybackTransition>.stride) * 3 + 512
                try domain.chargeParticleWork(UInt64((prefixBytes + 63) / 64), bytes: prefixBytes)
                defer { domain.releaseParticleStorage(prefixBytes) }
                let prior = try SceneScriptParticlePlaybackCommandBridge.commands(owner: owner).get()
                    .filter { $0.callbackEpoch == raw.callback_epoch }
                var prefix = prior.map { SceneParticlePlaybackTransition(layerID: $0.layerID,
                    action: $0.action, revision: 0, count: $0.count,
                    callbackEpoch: $0.callbackEpoch, ordinal: $0.ordinal) }
                prefix.append(.init(layerID: Int(raw.layer_id), action: .emit, revision: 0,
                    count: Int(raw.count), callbackEpoch: raw.callback_epoch, ordinal: raw.ordinal))
                return try transaction.preview(owner: UInt(bitPattern: owner), prefix: prefix) { instance in
                    guard let surface = capturedSurfaces[instance.surfaceID] else {
                        throw SceneScriptScalarRuntimeFailure.staleOwner
                    }
                    // Reserve the resolver's temporary dictionaries/matrices before
                    // copying the published snapshot or creating its transform lane.
                    let layerCount = context.runtimeInput.renderDescriptor.layers.count
                    let bytes = (preliminary.snapshot.count + layerCount + 16) * 512
                    try domain.chargeParticleWork(UInt64((bytes + 63) / 64), bytes: bytes)
                    defer { domain.releaseParticleStorage(bytes) }
                    let values = try surface.metalView.particleEmissionTransformValues(
                        owner: owner, layerID: instance.layerID)
                    let snapshot = SceneDynamicSnapshotResolver().resolve(
                        frameIndex: timing.frameIndex, generation: 0,
                        index: context.dynamicDefinitionIndex, base: preliminary,
                        sceneScriptValues: values).snapshot
                    return try surface.metalView.particleEmissionContext(layerID: instance.layerID,
                        timing: timing, dynamicValues: snapshot, topology: topology,
                        attachments: poses[instance.surfaceID]?.attachmentFrames ?? .empty, audio: audio)
                }
            }
        }
        return transaction
    }
}
