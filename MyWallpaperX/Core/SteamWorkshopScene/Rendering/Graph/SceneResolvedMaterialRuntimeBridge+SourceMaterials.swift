import CoreGraphics
import Foundation
import Metal
import simd

extension SceneResolvedMaterialRuntimeBridge.FramePreparationRequest {
    func replacingSource(
        original: SceneBaseImageTextureSnapshot,
        prepared: SceneBaseImageTextureSnapshot
    ) -> Self {
        guard case .capturedLayerTexture = claim.sourceRoute, sourceLighting == nil,
              let old = original[claim.layerID], sourceTexture === old,
              let texture = prepared[claim.layerID], texture !== old,
              let candidate = prepared.candidate(for: claim.layerID, matching: texture),
              SceneBaseImageTextureCandidateResolver.sample(candidate: candidate, sourceTexture: texture) != nil
        else { return self }
        var uniforms = sourceUniforms
        uniforms?.textureFrame0 = candidate.uvTransform.uniform0
        uniforms?.textureFrame1 = candidate.uvTransform.uniform1
        return .init(claim: claim, targetPlan: targetPlan,
            materialFunctionInvocations: materialFunctionInvocations,
            sceneBackgroundResource: sceneBackgroundResource, sourceTexture: texture,
            sourceUniforms: uniforms, sourcePipeline: sourcePipeline,
            sourceLighting: sourceLighting, terminalReplayTarget: terminalReplayTarget,
            frameInputs: frameInputs)
    }
}

extension SceneResolvedMaterialRuntimeBridge {
    struct PreparedSourceMaterial {
        let template: SceneResolvedMaterialTemplate
        let bindFrame: (SceneResolvedMaterialFinalizationInput)
            -> Result<SceneResolvedMaterialProgram, SceneResolvedMaterialFailure>
        let pixelFormat: MTLPixelFormat
        let sourceIdentity: SceneAssetTextureIdentity
    }

    /// Produces source atoms before any graph request freezes its inputs.
    /// The same MainPass submission owner retains all writes, including writes
    /// whose subsequent publication fails. There is no persistent source cache.
    func prepareSourceMaterials(
        imageTextures: SceneBaseImageTextureSnapshot,
        layerIDs: [Int],
        registry: SceneFrameTextureRegistry,
        pool: SceneOffscreenTexturePool?,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer
    ) -> SceneBaseImageTextureSnapshot {
        guard !sourceMaterials.isEmpty, let pool,
              let encoder = submissions.executor?.materialEncoder else { return imageTextures }
        submissions.lock.lock()
        let canPrepare = submissions.frameIsActive && !submissions.framePreparationComplete
            && !submissions.frameRequiresDrop && submissions.frameFailure == nil
            && submissions.activeTransactions.isEmpty
        let original = canPrepare ? submissions.frame : nil
        submissions.lock.unlock()
        guard let original, original.frameIndex == registry.frameIndex,
              original.textureRegistrySnapshot.frameEpoch == registry.frameEpoch else { return imageTextures }
        var sources: [Int: SceneLayerSourcePublication] = [:]
        for layerID in layerIDs {
            guard let material = sourceMaterials[layerID], material.pixelFormat == pool.pixelFormat,
                  let base = imageTextures[layerID],
                  imageTextures.candidate(for: layerID, matching: base) != nil,
                  let source = original.textureRegistrySnapshot.resource(for: .asset(material.sourceIdentity)),
                  source.publication.candidate.materialProgramUVTransform() != nil,
                  !source.publication.candidate.isSpriteSheet,
                  let target = pool.reserveSourceMaterial(layerID: layerID,
                    width: source.publication.texture.width, height: source.publication.texture.height,
                    commandBuffer: commandBuffer) else { continue }
            let sourceCandidate = source.publication.candidate
            let size = CGSize(width: target.texture.width, height: target.texture.height)
            let input = original.finalizationInput(template: material.template, layerID: layerID,
                renderSize: size,
                modelViewProjection: SceneResolvedMaterialGraphExecutor.fullTargetMVP(target.texture),
                layerModelMatrix: matrix_identity_float4x4,
                effectOutputModelViewProjection: matrix_identity_float4x4,
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4)
            let finalized = material.bindFrame(input)
            if case let .failure(failure) = finalized, original.frameIndex <= 2 {
                submissions.logSink("source material frame rejected: layer=\(layerID) reason=\(failure)")
            }
            guard case let .success(program) = finalized,
                  program.textureSlots.first??.registryIdentity == .asset(material.sourceIdentity),
                  let pass = encoder.prepare(program: program, target: target.texture),
                  pass.storedContent == .color(.resolved(.premultipliedAlpha))
                    || pass.storedContent == .color(.resolved(.opaque)) else {
                target.pin.release(); continue
            }
            // A write can remain in a command buffer even if a later atom
            // validation fails; only submission completion/cancellation releases it.
            mainPass.retainCompositionPin(target.pin)
            guard encoder.encode(pass, commandBuffer: commandBuffer) else { continue }
            let candidate = SceneTextureCandidate(texture: target.texture,
                identity: .provider(.materialSource(layerID: layerID,
                    frameEpoch: registry.frameEpoch, allocationGeneration: target.pin.generation)),
                generation: .provider(contentGeneration: registry.frameEpoch),
                purpose: .premultipliedColor, content: pass.storedContent,
                physicalSize: size, mappedSize: sourceCandidate.mappedSize,
                uvTransform: sourceCandidate.uvTransform,
                sampling: sourceCandidate.sampling)
            let publication = SceneTextureProviderPublication(requestIdentity: .layerSource(layerID),
                candidate: candidate, contentGeneration: registry.frameEpoch)
            guard let source = SceneLayerSourcePublication(layerID: layerID, publication: publication,
                renderSizeWH: imageTextures.layerSourceRenderSize(for: layerID),
                effectRenderSizeWH: imageTextures.layerSourceEffectRenderSize(for: layerID)) else { continue }
            sources[layerID] = source
            if original.frameIndex <= 2 {
                submissions.logSink("source material encoded: layer=\(layerID) frame=\(original.frameIndex) target=\(target.texture.width)x\(target.texture.height)")
            }
        }
        guard !sources.isEmpty,
              let textures = original.textureRegistrySnapshot.overlayingLayerSources(sources),
              let updated = original.replacingTextureSnapshot(textures) else { return imageTextures }
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
