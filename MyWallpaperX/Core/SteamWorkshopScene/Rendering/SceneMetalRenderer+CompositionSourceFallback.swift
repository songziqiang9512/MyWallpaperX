import simd

extension SceneMetalRenderer {
    /// Executes the lossless source prefix of an otherwise unsupported
    /// composition. Later effects remain omitted; the first neutral Blend
    /// input is drawn through the normal compositor pipeline at the
    /// composition's authored position.
    func drawCompositionSourceFallback(
        layer: SceneRenderDescriptor.Layer,
        imageTextures: SceneBaseImageTextureSnapshot,
        imagePipeline: SceneImageLayerPipeline,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        time: Float,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool? {
        guard layer.utilityLayer?.kind == .composition,
              layer.childLayerIDs.isEmpty,
              let firstEffect = layer.effects.first(where: {
                  $0.visible != false
              }),
              let declaration = SceneImageLayerBlendDependencyContract
                .declaration(for: firstEffect),
              declaration.blendMode == 0,
              !declaration.requiresResolvedMaterialProgram,
              layer.dependencyLayerIDs.contains(
                  declaration.providerLayerID
              ),
              let provider = layersByID[declaration.providerLayerID],
              provider.contentKind == "image",
              provider.utilityLayer == nil,
              provider.visible == false,
              provider.childLayerIDs.isEmpty,
              provider.dependencyLayerIDs.isEmpty,
              (provider.colorBlendMode ?? 0) == 0,
              let source = baseMaterialTextureSelection(
                  for: provider,
                  imageTextures: imageTextures,
                  readyProviderUsesAuthoredLayerColor:
                      baseMaterialReadyProviderUsesAuthoredLayerColor(
                          for: provider,
                          dynamicValues: frameContext.dynamicValues
                      )
              ).source,
              let candidate = source.candidate,
              let sample = SceneBaseImageTextureCandidateResolver.sample(
                  candidate: candidate,
                  sourceTexture: source.texture
              ) else {
            return nil
        }
        let model = imageModelMatrix(
            for: provider,
            worldFramesByLayerID: worldFramesByLayerID,
            renderSizeOverride: imageTextures.layerSourceRenderSize(
                for: provider.id
            ),
            parallaxMouseNormalized: frameContext.cameraParallaxPosition,
            configuration: parallaxConfiguration,
            visibleHalfExtents: cameraFrame.coverHalfExtents
        )
        let providerAlpha = SceneDynamicLayerValues.alpha(
            layerID: provider.id,
            authoredValue: provider.alpha,
            snapshot: frameContext.dynamicValues
        )
        let compositionAlpha = SceneDynamicLayerValues.alpha(
            layerID: layer.id,
            authoredValue: layer.alpha,
            snapshot: frameContext.dynamicValues
        )
        let authoredTint = SceneDynamicLayerValues.color(
            layerID: provider.id,
            authoredValue: provider.colorRGB,
            snapshot: frameContext.dynamicValues
        )
        let tint = source.usesAuthoredLayerColor
            ? authoredTint * max(0, Float(provider.brightness ?? 1))
            : SIMD3<Float>(repeating: 1)
        let uniforms = imageCompositor.makeFragmentUniforms(
            values: .init(
                time: time,
                alpha: providerAlpha * compositionAlpha,
                cursorUV: .zero,
                cursorIsInside: false,
                tint: tint
            ),
            textureFrame: sample.textureFrame,
            tint: tint,
            dependencyBlendMode: nil,
            sourceSampling: sample.sampling
        )
        let encoded = SceneImageLayerMainPassRenderer.draw(
            texture: source.texture,
            mvp: cameraFrame.viewProjection(for: provider) * model,
            uniforms: uniforms,
            dependencyTexture: nil,
            layer: provider,
            pipeline: imagePipeline,
            colorBlendPipeline: nil,
            mainPass: mainPass
        )
        executionTrace.recordRouteOperation(
            layerID: layer.id,
            origin: .utilityComposition,
            operation: "degraded-composition-source-prefix",
            outcome: encoded
                ? .encoded
                : .failed(reasonCode: "main-pass-encode-failed")
        )
        return encoded
    }
}
