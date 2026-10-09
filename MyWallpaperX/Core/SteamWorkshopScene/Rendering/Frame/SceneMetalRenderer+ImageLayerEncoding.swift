import Foundation
import Metal
import QuartzCore
import simd

extension SceneMetalRenderer {
    /// A local dependency miss skips this layer; an identity failure stops
    /// the caller's loop. The caller retains its utility defer in both cases.
    func encodeImageLayer(
        layer: SceneRenderDescriptor.Layer,
        baseSource: SceneBaseMaterialTextureSource,
        imageTextures: SceneBaseImageTextureSnapshot,
        imagePipeline: SceneImageLayerPipeline,
        specializedBaseTextureSamplings: [Int: SceneTextureSampling],
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        resolvedMaterialFrameTargetPlans: [Int: SceneResolvedMaterialFrameTargetPlan],
        frameContext: SceneFrameContext,
        frameWorldFrames: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxMouseNormalized: SIMD2<Float>,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        viewportSize: CGSize,
        time: Float,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameLightSnapshot: SceneLightSnapshot,
        reflection: ReflectionFrame,
        environmentSource: @escaping (MTLCommandBuffer) -> SceneFrameTextureResource?,
        modelFrame: StaticModelFrame,
        layerMainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        effectExecutionTrace: SceneEffectExecutionFrameTrace?
    ) -> (stop: Bool, outcome: SceneImageLayerCompositor.DrawOutcome?) {
        let texture = baseSource.texture
        let resolvedFramePlan = resolvedMaterialFrameTargetPlans[layer.id]
        let dependencyBypassReason = resolvedFramePlan == nil
            ? nil
            : imageCompositor
                .preparedResolvedMaterialExternalDependencyBypassReason(
                    layerID: layer.id
                )
        let requiresDependencyEffect = (
            resolvedFramePlan?.consumesExternalPrimaryDependency
                ?? dependencyRuntime.requiresEffect(for: layer.id)
        ) && dependencyBypassReason == nil
        let dependencyResolution = resolveDependencyEffectInputs(
            layerID: layer.id,
            requiresDependencyEffect: requiresDependencyEffect,
            hasResolvedFramePlan: resolvedFramePlan != nil,
            bypassReason: dependencyBypassReason,
            dependencyRuntime: dependencyRuntime,
            textureRegistry: textureRegistry
        )
        let dependencyEffects = dependencyResolution.dependencyEffects
        let resolvedDependencyFailure = dependencyResolution.failure
        let geometryProduct = imageTextures.geometryProducts[layer.id]
        let layerAlpha = SceneDynamicLayerValues.alpha(
            layerID: layer.id, authoredValue: layer.alpha,
            snapshot: frameContext.dynamicValues
        )
        let usesPerspective = cameraFrame.resolvesPerspective(for: layer)
        let model = geometryProduct.map {
            geometryModelMatrix(
                for: layer,
                worldFramesByLayerID: frameWorldFrames,
                authoredSize: $0.authoredSize,
                parallaxMouseNormalized: parallaxMouseNormalized,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents,
                usesPerspective: usesPerspective
            )
        } ?? imageModelMatrix(
            for: layer, worldFramesByLayerID: frameWorldFrames,
            renderSizeOverride: imageTextures.layerSourceRenderSize(for: layer.id),
            textCenterOffsetY: imageTextures.layerSourceTextCenterOffsetY(for: layer.id) ?? 0,
            parallaxMouseNormalized: parallaxMouseNormalized,
            configuration: parallaxConfiguration,
            visibleHalfExtents: cameraFrame.coverHalfExtents,
            usesPerspective: usesPerspective
        )
        let mvp = cameraFrame.viewProjection(for: layer) * model
        // The native camera contract is proven for world-space images.
        // Orthographic Fog's distance domain remains unproven; neither canvas
        // depth nor the fitted perspective eye is established by current probes.
        let fog = cameraFrame.defaultsToPerspective && usesPerspective ? SceneImageDistanceFogUniforms(
            color: frameLightSnapshot.distanceFogColor,
            range: frameLightSnapshot.distanceFogRange,
            cameraRelativeOrigin: model.columns.3
                - SIMD4(cameraFrame.perspectiveEyePosition, 0),
            modelX: model.columns.0,
            modelY: model.columns.1
        ) : .init()
        let cursorUV = SceneLayerCursorGeometry.layerUV(
            mouseNormalized: frameContext.pointer.current,
            modelViewProjection: mvp
        )
        let previousCursorUV = SceneLayerCursorGeometry.layerUV(
            mouseNormalized: frameContext.pointer.previous,
            modelViewProjection: mvp
        )
        let effectSourceExtent: SceneLayerEffectSourceExtent?
        if layer.contentKind == "solid" {
            effectSourceExtent = SceneCaptureGeometryResolver
                .projectedPixelSize(
                    layerMVP: mvp,
                    viewportSize: viewportSize
                )
                .flatMap(SceneLayerEffectSourceExtent.init(pixelSize:))
        } else {
            effectSourceExtent = SceneLayerEffectSourceExtent.resolve(
                publishedRenderSizeWH:
                    imageTextures.layerSourceRenderSize(for: layer.id),
                authoredRenderSizeWH: layer.renderSizeWH,
                candidateMappedSize: baseSource.candidate?.mappedSize
            )
        }
        var request = SceneImageLayerDrawRequest(
            layer: layer,
            texture: texture,
            baseTextureCandidate: baseSource.candidate,
            baseTextureSampling: specializedBaseTextureSamplings[layer.id],
            masks: .empty,
            textureFrame: spriteAnimations[layer.id].map {
                $0.transform(
                    at: spriteAnimationPlaybackTimes[layer.id] ?? 0
                )
            } ?? .identity,
            mvp: mvp,
            uniforms: SceneImageLayerUniformValues(
                time: time,
                alpha: layerAlpha,
                cursorUV: cursorUV ?? .zero,
                previousCursorUV: previousCursorUV ?? cursorUV ?? .zero,
                cursorIsInside: frameContext.pointer.isInside && cursorUV != nil,
                previousCursorIsInside: frameContext.pointer.isInside
                    && previousCursorUV != nil,
                primaryButtonIsDown: frameContext.pointer.isPrimaryButtonDown,
                frameTime: Float(frameContext.frameTime),
                tint: baseSource.usesAuthoredLayerColor
                    ? SceneDynamicLayerValues.color(
                        layerID: layer.id,
                        authoredValue: layer.colorRGB,
                        snapshot: frameContext.dynamicValues
                    )
                    : SIMD3(repeating: 1)
            ),
            sourceMaterialAlpha: baseMaterialProviderBindings.sourceMaterialAlpha(
                layer: layer, snapshot: frameContext.dynamicValues
            ),
            sourceMaterialColor: baseMaterialProviderBindings.sourceMaterialColor(
                        layer: layer, snapshot: frameContext.dynamicValues
                    ),
            offscreenTexturePool: offscreenTexturePool,
            resolvedMaterialFrameTargetPlan:
                resolvedFramePlan,
            effectSourceExtent: effectSourceExtent,
            requiresSourceCopy: false,
            finalCompositeAlpha: nil,
            dependencyEffects: dependencyEffects,
            requiresDependencyEffect: requiresDependencyEffect,
            blocksStaticLayerSourcePassthrough:
                dependencyRuntime.blocksStaticLayerSourcePassthrough(
                    for: layer.id
                ),
            dynamicValues: frameContext.dynamicValues,
            audioSpectrum: frameContext.audioSpectrum,
            authoredShaderFrameInputs: .init(frameContext: frameContext),
            geometryProduct: geometryProduct,
            distanceFog: fog
        )
        preparePlainSourceLighting(request: &request, snapshot: frameLightSnapshot,
            model: model, worldFrame: frameWorldFrames[layer.id] ?? SceneMatrix.identity(),
            cameraFrame: cameraFrame, usesPerspective: usesPerspective,
            environmentSource: reflection.scratchReady ? environmentSource : nil,
            preparedResolution: modelFrame.plainLighting[layer.id])
        let explicitLayerSourcePublication = imageTextures
            .explicitLayerSourcePublication(
                for: layer.id,
                matching: texture
            )
        let layerSourceGraphFallbackPublisher: ((MTLTexture) -> Bool)?
        if geometryProduct == nil,
           dependencyRuntime.requiresDemandedGraphOutputCapture(for: layer.id) {
            layerSourceGraphFallbackPublisher = { fallbackTexture in
                guard fallbackTexture === texture else { return false }
                return dependencyRuntime
                    .captureGraphSourceFallbackIfRequired(
                        layer: layer,
                        sourceTexture: fallbackTexture,
                        sourceCandidate: baseSource.candidate,
                        usesAuthoredLayerColor:
                            baseSource.usesAuthoredLayerColor,
                        layerMVP: mvp,
                        viewportSize: viewportSize,
                        pipeline: imagePipeline,
                        textureRegistry: textureRegistry,
                        mainPass: layerMainPass
                    ) == .published
            }
        } else {
            layerSourceGraphFallbackPublisher = nil
        }
        let resolvedMaterialGraphOutputPublisher: ((
            MTLTexture,
            SceneTextureContent
        ) -> SceneGraphOutputPublicationResult)?
        if dependencyRuntime.requiresDemandedGraphOutputCapture(
            for: layer.id
        ) {
            resolvedMaterialGraphOutputPublisher = { graphOutput, content in
                dependencyRuntime.publishGraphOutputIfRequired(
                    layerID: layer.id,
                    texture: graphOutput,
                    publicationRole: .visibleMainLoop,
                    textureRegistry: textureRegistry,
                    commandBuffer: commandBuffer,
                    geometryProduct: geometryProduct,
                    content: content,
                    imagePipeline: imagePipeline,
                    retainAuxiliary: layerMainPass.retainAuxiliaryRelease
                ) ?? .invalid(
                    reasonCode: "named-provider-publication-route-missing"
                )
            }
        } else {
            resolvedMaterialGraphOutputPublisher = nil
        }
        if let failure = resolvedDependencyFailure {
            dependencyRuntime.recordBindingFailure(for: layer.id)
            if failure.isOrdinaryUnavailable,
               imageCompositor
                .rejectResolvedMaterialDependencySubgraphLocally(
                    layerID: layer.id,
                    reasonCode: failure.reasonCode
                ) {
                return (false, nil)
            }
            imageCompositor.recordResolvedMaterialFramePreflightFailure(
                failure.reasonCode
            )
            return (true, nil)
        }
        if request.requiresDependencyEffect,
           request.dependencyEffects.isEmpty {
            dependencyRuntime.recordBindingFailure(for: layer.id)
            return (false, nil)
        }
        let drawOutcome = imageCompositor.drawOutcome(
            request,
            explicitLayerSourcePublication: explicitLayerSourcePublication,
            resolvedMaterialGraphOutputPublisher:
                resolvedMaterialGraphOutputPublisher,
            layerSourceGraphFallbackPublisher:
                layerSourceGraphFallbackPublisher,
            allowsUnpublishedStaticSourceDraw:
                layerSourceGraphFallbackPublisher == nil,
            pipeline: imagePipeline,
            mainPass: layerMainPass,
            executionTrace: effectExecutionTrace,
            executionOrigin: Self.effectExecutionOrigin(
                for: layer.contentKind
            )
        )
        if case .layerSourcePassthrough = drawOutcome {
            ScenePerformanceCounterHub.shared.bump(.fallbackBranches)
        }
        return (false, drawOutcome)
    }
}
