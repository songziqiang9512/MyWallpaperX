import Metal

extension SceneImageLayerCompositor {
    func renderLegacyAuthoredChain(
        _ chain: SceneAuthoredEffectExecutionChain,
        request: SceneImageLayerDrawRequest,
        pool _: SceneOffscreenTexturePool,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        mainPass: SceneMainPassEncoder,
        frameTransaction _: SceneSourceUpdateTransaction?,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> MTLTexture? {
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

        // Frame-batch path ONLY — no per-chain reserve/commit fallback.
        // The production renderer must prepare the batch before the loop.
        guard let frameTables = request.legacyAuthoredFrameTables else {
            recordAllocationFailure()
            return nil
        }
        return mainPass.encodeOffscreen { commandBuffer in
            render(frameTables.tables, commandBuffer)
        }
    }
}
