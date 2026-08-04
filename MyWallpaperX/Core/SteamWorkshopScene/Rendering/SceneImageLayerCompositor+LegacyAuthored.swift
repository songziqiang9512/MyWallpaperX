import Metal

extension SceneImageLayerCompositor {
    func renderLegacyAuthoredChain(
        _ chain: SceneAuthoredEffectExecutionChain,
        request: SceneImageLayerDrawRequest,
        pool: SceneOffscreenTexturePool,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        mainPass: SceneMainPassEncoder,
        frameTransaction: SceneSourceUpdateTransaction?,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> MTLTexture? {
        let dimensions = legacyOffscreenDimensions(
            for: request,
            authoredChain: chain
        )
        let render: ([SceneGraphRenderTargetTable], MTLCommandBuffer) -> MTLTexture? = {
            targets, commandBuffer in
            SceneAuthoredEffectChainRenderer.render(
                sourceTexture: request.texture,
                masks: request.masks,
                targets: targets,
                chain: chain,
                dynamicValues: request.dynamicValues,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                pipelines: pipelines,
                cursorUV: request.uniforms.cursorUV,
                previousCursorUV: request.uniforms.previousCursorUV,
                pointerIsInside: request.uniforms.cursorIsInside,
                previousPointerIsInside: request.uniforms.previousCursorIsInside,
                frameTime: request.uniforms.frameTime,
                audioSpectrum: request.audioSpectrum,
                authoredShaderFrameInputs: request.authoredShaderFrameInputs,
                dependencyEffect: request.dependencyEffect,
                commandBuffer: commandBuffer,
                executionTrace: executionTrace,
                executionOrigin: executionOrigin
            )
        }
        func recordAllocationFailure() {
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "authored-target-allocation",
                outcome: .failed(reasonCode: "graph-targets-unavailable")
            )
        }

        if pool.usesPairOnlyLegacyTargets(for: chain) {
            guard let targets = pool.graphTargets(
                for: chain,
                requestedWidth: dimensions.width,
                requestedHeight: dimensions.height
            ) else {
                recordAllocationFailure()
                return nil
            }
            return mainPass.encodeOffscreen { commandBuffer in
                render(targets, commandBuffer)
            }
        }

        guard let frameTransaction else { return nil }
        return mainPass.encodeOffscreen { commandBuffer in
            guard let framePlan = pool.framePlanForPersistentGraphTargets(
                for: chain,
                requestedWidth: dimensions.width,
                requestedHeight: dimensions.height,
                orderingContext: .init(commandBuffer: commandBuffer)
            ), let prepared = pool.preparePersistentGraphTargets(
                framePlan: framePlan
            ), let commit = prepared.commitAndPin(
                historyTokensByEffect: [:],
                commandBuffer: commandBuffer
            ) else {
                recordAllocationFailure()
                return nil
            }
            frameTransaction.registerResolution(
                completed: { commit.releaseAll() },
                rollback: { commit.releaseAll() }
            )
            return render(commit.leases.map(\.table), commandBuffer)
        }
    }
}
