import Foundation

extension SceneDesktopWallpaperSession {
    func beginParticleEmissionFrame(
        context: SceneDesktopWallpaperLaunchContext, timing: SceneFrameTiming,
        preliminary: SceneDynamicSnapshotResolution,
        topology: SceneScriptLayerTopologySnapshot,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        definitionIndex: SceneDynamicSnapshotDefinitionIndex,
        poses: [UInt32: ScenePuppetScriptPoseFrame], audio: SceneAudioSpectrumSnapshot,
        inputSurfaceIDs: Set<UInt32>
    ) -> SceneParticlePlaybackTransaction? {
        guard let domain = context.propertyVectorScriptProgram.domain else { return nil }
        let capturedSurfaces = surfaces
        var identities: [UInt32: UUID?] = [:]
        func captureInstances() -> [SceneParticlePlaybackTransaction.Instance] {
            identities = capturedSurfaces.mapValues { $0.particlePlayback?.lifecycleIdentity }
            return capturedSurfaces.flatMap { id, surface in
                (surface.particlePlayback?.playbackSimulators ?? []).map { layerID, simulator in
                    .init(surfaceID: id, layerID: layerID, simulator: simulator,
                        visibility: surface.particlePlayback?.playbackVisibility(layerID: layerID,
                            dynamicValues: preliminary.snapshot),
                        install: { state, visibility in MainActor.assumeIsolated {
                            precondition(surface.particlePlayback != nil)
                            surface.particlePlayback?.installPlaybackCandidate(layerID: layerID,
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
                            && surface.particlePlayback?.lifecycleIdentity == identities[id]!
                    }
            } }, totalLiveCount: { try MainActor.assumeIsolated {
                try capturedSurfaces.values.reduce(0) { count, surface in
                    count + (try surface.particlePlayback?.playbackLiveCount(
                        charging: { try domain.chargeParticleWork($0, bytes: 0) }) ?? 0)
                }
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
                    let input = try Self.particleEmissionInputs(owner: owner,
                        layerID: instance.layerID, layersByID: layersByID, index: definitionIndex,
                        cameraOriginLayerID: context.runtimeInput.renderDescriptor.camera.default2DOriginInputLayerID)
                    let snapshot = SceneDynamicSnapshotResolver().resolve(
                        frameIndex: timing.frameIndex, generation: 0,
                        index: definitionIndex, base: preliminary,
                        sceneScriptValues: input.values, candidateDefinitions: input.definitions).snapshot
                    return try surface.particleEmissionContext(layerID: instance.layerID,
                        timing: timing, dynamicValues: snapshot, topology: topology,
                        attachments: poses[instance.surfaceID]?.attachmentFrames ?? .empty, audio: audio)
                }
            }
        }
        return transaction
    }

    private static func particleEmissionInputs(
        owner: OpaquePointer, layerID: Int,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        index: SceneDynamicSnapshotDefinitionIndex, cameraOriginLayerID: Int?
    ) throws -> (values: [SceneDynamicTarget: SceneDynamicValue],
                 definitions: [SceneDynamicTarget: SceneDynamicTargetDefinition]) {
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var definitions: [SceneDynamicTarget: SceneDynamicTargetDefinition] = [:]
        var visited = Set<Int>()
        var current: Int? = layerID
        while let id = current {
            guard visited.insert(id).inserted, let layer = layersByID[id] else {
                throw SceneScriptScalarRuntimeFailure.staleOwner
            }
            var origin = [Double](repeating: 0, count: 3)
            var scale = origin, angles = origin
            guard mwx_scene_quickjs_owner_particle_transform(owner, Int64(id), &origin, &scale, &angles) == MWX_SCENE_QUICKJS_OK else {
                throw SceneScriptScalarRuntimeFailure.staleOwner
            }
            func record(_ field: SceneDynamicLayerField, _ value: SIMD3<Double>) {
                let target = SceneScriptDynamicLayerRuntime.authoredTransformTarget(
                    layerID: id, field: field, cameraOriginInputLayerID: cameraOriginLayerID)
                guard case .layer = target else { return }
                if !index.contains(target) {
                    // The world resolver consumes Float. A degrees/radians
                    // round trip alone must not turn a static angle dynamic.
                    guard let definition = SceneScriptDynamicLayerRuntime.definition(for: target, layer: layer),
                          case let .vector3(x, y, z) = definition.authoredValue,
                          SIMD3<Float>(value) != SIMD3(Float(x), Float(y), Float(z)) else { return }
                    definitions[target] = definition
                }
                values[target] = .vector3(value.x, value.y, value.z)
            }
            record(.origin, .init(origin[0], origin[1], origin[2]))
            record(.scale, .init(scale[0], scale[1], scale[2]))
            record(.angles, .init(SceneScriptAngleUnits.radians(fromDegrees: angles[0]),
                SceneScriptAngleUnits.radians(fromDegrees: angles[1]),
                SceneScriptAngleUnits.radians(fromDegrees: angles[2])))
            current = layer.parentID
        }
        var alpha = 1.0
        guard mwx_scene_quickjs_owner_particle_instance_alpha(owner, Int64(layerID), &alpha) == MWX_SCENE_QUICKJS_OK,
              alpha.isFinite else {
            throw SceneScriptScalarRuntimeFailure.staleOwner
        }
        values[.particle(layerID: layerID, field: .alpha)] = .scalar(alpha)
        return (values, definitions)
    }
}

extension SceneDesktopWallpaperSession {
    func particlePlaybackObservations(
        context: SceneDesktopWallpaperLaunchContext,
        committed: [Int: SceneParticlePlaybackSnapshot]
    ) -> [Int: SceneParticlePlaybackObservation] {
        guard !surfaces.isEmpty, Set(surfaces.keys) == preparedSurfaceIDs,
              surfaces.values.allSatisfy({ $0.scriptGeneration == context.propertyVectorScriptProgram.generation }) else { return [:] }
        var observations: [Int: SceneParticlePlaybackObservation] = [:]
        for layer in context.runtimeInput.renderDescriptor.layers where layer.contentKind == "particle" {
            let current = committed[layer.id] ?? .init()
            var live = false, pending = false, rearm = false, complete = true
            for surface in surfaces.values {
                guard let value = surface.particlePlayback?.playbackObservation(layerID: layer.id),
                      value.intent == current.intent, value.revision == current.revision else { complete = false; break }
                live = live || value.liveAny
                pending = pending || value.emissionPending
                rearm = rearm || value.rearmHasWork
            }
            if complete {
                observations[layer.id] = .init(liveAny: live, emissionPending: pending,
                    rearmHasWork: rearm, intent: current.intent, revision: current.revision)
            }
        }
        return observations
    }
}
