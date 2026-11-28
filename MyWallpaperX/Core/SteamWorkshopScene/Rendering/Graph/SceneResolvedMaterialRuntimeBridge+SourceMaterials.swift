import CoreGraphics
import Foundation
import Metal
import simd

extension SceneResolvedMaterialRuntimeBridge.FramePreparationRequest {
    func replacingSource(
        original: SceneBaseImageTextureSnapshot,
        prepared: SceneBaseImageTextureSnapshot
    ) -> Self {
        guard case .capturedLayerTexture = claim.sourceRoute,
              let old = original[claim.layerID], sourceTexture === old,
              let texture = prepared[claim.layerID], texture !== old,
              let candidate = prepared.candidate(for: claim.layerID, matching: texture),
              SceneBaseImageTextureCandidateResolver.sample(candidate: candidate, sourceTexture: texture) != nil
        else { return self }
        var uniforms = sourceUniforms
        uniforms?.textureFrame0 = candidate.uvTransform.uniform0
        uniforms?.textureFrame1 = candidate.uvTransform.uniform1
        if var sampling = uniforms?.sourceSampling {
            sampling.y &= ~UInt32(1)
            if candidate.content == .color(.resolved(.straightAlpha)) { sampling.y |= 1 }
            uniforms?.sourceSampling = sampling
        }
        uniforms?.consumeCompletedMaterialSource(candidate.identity)
        return .init(claim: claim, targetPlan: targetPlan,
            materialFunctionInvocations: materialFunctionInvocations,
            sceneBackgroundResource: sceneBackgroundResource, sourceTexture: texture,
            sourceUniforms: uniforms, sourcePipeline: sourcePipeline,
            terminalReplayTarget: terminalReplayTarget, terminalReplayBlendMode: terminalReplayBlendMode,
            terminalReplayIsOptional: terminalReplayIsOptional,
            frameInputs: frameInputs)
    }
}

extension SceneResolvedMaterialRuntimeBridge {
    struct PreparedSourceMaterial {
        /// VM admission includes declarations inactive in the current variants.
        let declaredDynamicTargets: Set<SceneDynamicTarget>
        let hasAudioSpectrumConsumer: Bool
        let requiresSceneEnvironment: Bool
        let bindFrame: (SceneResolvedMaterialFinalizationInput)
            -> Result<SceneResolvedMaterialProgram, SceneResolvedMaterialFailure>
        let pixelFormat: MTLPixelFormat
        enum OutputDomain {
            case sampledAsset(SceneAssetTextureIdentity)
            case baseImage
            case capturedMain

            func matchesSampledSource(_ program: SceneResolvedMaterialProgram) -> Bool {
                switch self {
                case let .sampledAsset(identity):
                    program.textureSlots.first??.registryIdentity == .asset(identity)
                case .baseImage:
                    (program.textureSlots.first ?? nil) == nil
                case .capturedMain:
                    false // Ordered main sources are validated with their frame resource.
                }
            }
        }
        let outputDomain: OutputDomain
        var sharedModelPath: String? = nil
        var bindsImageLayerColor = false
    }

    /// A prepared material and the exact ordered main attachment it reads.
    /// This is a frame input, never a published asset or persistent source cache.
    struct FramebufferSourceMaterial {
        let material: PreparedSourceMaterial
        let source: SceneFrameTextureResource
        let unitModelMatrix: simd_float4x4
    }

    struct SourceMaterialConsumer {
        let layerID: Int
        let prototypeLayerID: Int
    }

    func sourceMaterialConsumer(layerID: Int, modelPath: String?) -> SourceMaterialConsumer? {
        if sourceMaterials[layerID] != nil {
            return .init(layerID: layerID, prototypeLayerID: layerID)
        }
        guard let modelPath else { return nil }
        let normalized = SceneModelResourceIdentity(modelPath).value
        guard let prototype = sourceMaterialPrototypeByModel[normalized] else { return nil }
        return .init(layerID: layerID, prototypeLayerID: prototype)
    }

    /// A deferred optional environment lets independent outputs take their
    /// leases first. Both phases read the original source images.
    func prepareSourceMaterials(
        imageTextures: SceneBaseImageTextureSnapshot,
        consumers: [SourceMaterialConsumer],
        registry: SceneFrameTextureRegistry,
        pool: SceneOffscreenTexturePool?,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        prepareOptionalEnvironment: (() -> Bool)?,
        sourceDrawColor4: (Int) -> SIMD4<Float>?
    ) -> SceneBaseImageTextureSnapshot? {
        guard let pool, let encoder = submissions.executor?.materialEncoder else {
            return prepareOptionalEnvironment?() == false ? nil : imageTextures
        }
        submissions.lock.lock()
        let canPrepare = submissions.frameIsActive && !submissions.framePreparationComplete
            && !submissions.frameRequiresDrop && submissions.frameFailure == nil
            && submissions.activeTransactions.isEmpty
        let original = canPrepare ? submissions.frame : nil
        submissions.lock.unlock()
        guard let original, original.frameIndex == registry.frameIndex,
              original.textureRegistrySnapshot.frameEpoch == registry.frameEpoch else {
            return prepareOptionalEnvironment?() == false ? nil : imageTextures
        }
        var sources: [Int: SceneLayerSourcePublication] = [:]
        func encodeSource(layerID: Int, consumers: [SourceMaterialConsumer],
                          material: PreparedSourceMaterial, frame: SceneResolvedMaterialFrameSnapshot) {
            let layerIDs = consumers.compactMap { consumer -> Int? in
                let id = consumer.layerID
                guard let base = imageTextures[id],
                      imageTextures.candidate(for: id, matching: base) != nil else { return nil }
                return id
            }
            guard !layerIDs.isEmpty else { return }
            let sourceCandidate: SceneTextureCandidate?
            switch material.outputDomain {
            case let .sampledAsset(identity):
                sourceCandidate = frame.textureRegistrySnapshot.resource(for: .asset(identity))?
                    .publication.candidate
            case .baseImage:
                sourceCandidate = imageTextures[layerID].flatMap {
                    imageTextures.candidate(for: layerID, matching: $0)
                }
            case .capturedMain:
                return // Its source exists only at the authored layer-loop boundary.
            }
            guard let sourceCandidate,
                  sourceCandidate.axisAlignedSourceUVTransform() != nil,
                  !sourceCandidate.isSpriteSheet,
                  let target = pool.reserveSourceMaterial(layerID: layerID,
                    width: sourceCandidate.texture.width, height: sourceCandidate.texture.height,
                    commandBuffer: commandBuffer) else { return }
            let size = CGSize(width: target.texture.width, height: target.texture.height)
            let input = frame.finalizationInput(layerID: layerID,
                renderSize: size,
                modelViewProjection: SceneResolvedMaterialGraphExecutor.fullTargetMVP(target.texture),
                layerModelMatrix: matrix_identity_float4x4,
                effectOutputModelViewProjection: matrix_identity_float4x4,
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                sourceDrawColor4: material.bindsImageLayerColor ? sourceDrawColor4(layerID) : nil)
            let finalized = material.bindFrame(input)
            if case let .failure(failure) = finalized, frame.frameIndex <= 2 {
#if DEBUG
                submissions.logSink("source material frame rejected: layer=\(layerID) reason=\(failure)")
#endif
            }
            guard case let .success(program) = finalized,
                  material.outputDomain.matchesSampledSource(program),
                  let pass = encoder.prepare(program: program, target: target.texture),
                  pass.storedContent == .color(.resolved(.premultipliedAlpha))
                    || pass.storedContent == .color(.resolved(.straightAlpha))
                    || pass.storedContent == .color(.resolved(.opaque)) else {
                target.pin.release()
                return
            }
            // A write can remain in a command buffer even if a later atom
            // validation fails; only submission completion/cancellation releases it.
            mainPass.retainCompositionPin(target.pin)
            guard encoder.encode(pass, commandBuffer: commandBuffer) else { return }
            for consumerID in layerIDs {
                let candidate = SceneTextureCandidate(texture: target.texture,
                    identity: .provider(.materialSource(layerID: consumerID,
                        frameEpoch: registry.frameEpoch, allocationGeneration: target.pin.generation)),
                    generation: .provider(contentGeneration: registry.frameEpoch),
                    purpose: pass.storedContent == .color(.resolved(.straightAlpha))
                        ? .straightAlbedo : .premultipliedColor, content: pass.storedContent,
                    physicalSize: size, mappedSize: sourceCandidate.mappedSize,
                    uvTransform: sourceCandidate.uvTransform,
                    sampling: sourceCandidate.sampling)
                let publication = SceneTextureProviderPublication(requestIdentity: .layerSource(consumerID),
                    candidate: candidate, contentGeneration: registry.frameEpoch)
                guard let source = SceneLayerSourcePublication(layerID: consumerID, publication: publication,
                    renderSizeWH: imageTextures.layerSourceRenderSize(for: consumerID),
                    effectRenderSizeWH: imageTextures.layerSourceEffectRenderSize(for: consumerID),
                    textPlacement: imageTextures.layerSourceTextPlacement(for: consumerID)) else { continue }
                sources[consumerID] = source
            }
            if frame.frameIndex <= 2 {
#if DEBUG
                submissions.logSink("source material encoded: layer=\(layerID) frame=\(frame.frameIndex) consumers=\(layerIDs.count) target=\(target.texture.width)x\(target.texture.height)")
#endif
            }
        }
        let groups = Dictionary(grouping: consumers, by: \.prototypeLayerID)
        var environmentGroups: [(layerID: Int, consumers: [SourceMaterialConsumer], material: PreparedSourceMaterial)] = []
        for layerID in groups.keys.sorted() {
            guard let consumers = groups[layerID], let material = sourceMaterials[layerID],
                  material.pixelFormat == pool.pixelFormat else { continue }
            if prepareOptionalEnvironment != nil, material.requiresSceneEnvironment {
                environmentGroups.append((layerID, consumers, material))
            } else {
                encodeSource(layerID: layerID, consumers: consumers, material: material, frame: original)
            }
        }
        let publicationFrame: SceneResolvedMaterialFrameSnapshot
        if let prepareOptionalEnvironment {
            guard prepareOptionalEnvironment() else { return nil }
            guard !sources.isEmpty || !environmentGroups.isEmpty else { return imageTextures }
            submissions.lock.lock()
            let overlaid = submissions.frame
            submissions.lock.unlock()
            guard let overlaid, overlaid.frameIndex == original.frameIndex,
                  overlaid.textureRegistrySnapshot.frameEpoch == original.textureRegistrySnapshot.frameEpoch
            else { return imageTextures }
            for group in environmentGroups {
                encodeSource(layerID: group.layerID, consumers: group.consumers, material: group.material, frame: overlaid)
            }
            publicationFrame = overlaid
        } else {
            publicationFrame = original
        }
        guard !sources.isEmpty,
              let textures = publicationFrame.textureRegistrySnapshot.overlayingLayerSources(sources),
              let updated = publicationFrame.replacingTextureSnapshot(textures) else { return imageTextures }
        submissions.lock.lock()
        let canPublish = submissions.frameIsActive && !submissions.framePreparationComplete
            && !submissions.frameRequiresDrop && submissions.frameFailure == nil
            && submissions.activeTransactions.isEmpty
            && submissions.frame?.textureRegistrySnapshot.frameEpoch == textures.frameEpoch
            && submissions.frame?.frameIndex == textures.frameIndex
        if canPublish { submissions.frame = updated }
        submissions.lock.unlock()
        guard canPublish else { return imageTextures }
        for (layerID, source) in sources { registry.set(source.publication, for: .layerSource(layerID)) }
        return imageTextures.replacingLayerSources(sources)
    }
}
