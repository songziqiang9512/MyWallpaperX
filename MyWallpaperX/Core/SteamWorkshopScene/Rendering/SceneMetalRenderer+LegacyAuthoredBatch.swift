import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    /// Collects every legacy authored chain (visible image/solid/text
    /// layers + executable utility capture plans) that is NOT already
    /// claimed by resolved-material or SceneScript Audio Bars, builds one
    /// frame plan per chain, and aggregately reserves + commits them
    /// against a single cache snapshot.
    ///
    /// Returns a **frame-local** `[layerID: LegacyAuthoredFrameTables]`
    /// dictionary, or `nil` on any failure.  On failure the pool cache is
    /// unmodified, the resolved-material frame is rolled back, and the
    /// caller must abort the frame.
    ///
    /// Must be called after `admitResolvedMaterialFrameTargets` and before
    /// the main-pass frame loop.
    func prepareLegacyAuthoredFrameBatch(
        resolvedMaterialPlans: [Int: SceneResolvedMaterialFrameTargetPlan],
        offscreenTexturePool: SceneOffscreenTexturePool?,
        imageTextures: SceneBaseImageTextureSnapshot,
        dynamicTextRenderSizes: [Int: [Float]],
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        commandBuffer: MTLCommandBuffer
    ) -> [Int: SceneOffscreenTexturePool.LegacyAuthoredFrameTables]? {
        guard let offscreenTexturePool else { return [:] }
        let orderingContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: commandBuffer
        )
        let viewportSize = frameContext.screenSize
        let orderedLayers = renderDescriptor.renderOrderLayerIDs.compactMap {
            layersByID[$0]
        }
        var framePlans: [ScenePersistentGraphTargetFramePlan] = []
        var seenLayerIDs = Set<Int>()

        // --- ordinary visible image/solid/text layers ---
        for layer in orderedLayers {
            guard visibleLayerIDs.contains(layer.id) else { continue }
            guard layer.contentKind == "image"
                || layer.contentKind == "solid"
                || layer.contentKind == "text"
            else { continue }
            // SceneScript Audio Bars — not a legacy authored chain.
            guard sceneScriptAudioBarsPlansByLayerID[layer.id] == nil else {
                continue
            }
            // Already claimed by resolved-material path.
            guard resolvedMaterialPlans[layer.id] == nil else { continue }
            guard imageTextures[layer.id] != nil else { continue }
            guard let chain = authoredEffectChain(for: layer.id) else {
                continue
            }
            guard seenLayerIDs.insert(layer.id).inserted else { continue }

            let desiredSize = layerOffscreenSize(
                for: layer,
                imageTextures: imageTextures,
                dynamicTextRenderSizes: dynamicTextRenderSizes,
                viewportSize: viewportSize,
                worldFramesByLayerID: worldFramesByLayerID,
                cameraFrame: cameraFrame,
                parallaxConfiguration: parallaxConfiguration,
                parallaxMouse: frameContext.cameraParallaxPosition
            )
            guard let framePlan = offscreenTexturePool
                .legacyAuthoredChainFramePlan(
                    for: chain,
                    requestedWidth: max(1, Int(desiredSize.width.rounded(.up))),
                    requestedHeight: max(1, Int(desiredSize.height.rounded(.up))),
                    orderingContext: orderingContext
                )
            else { return nil }
            framePlans.append(framePlan)
        }

        // --- utility capture plans ---
        for (_, plans) in utilityPlansByTriggerLayerID {
            for plan in plans where plan.shouldCapture {
                guard seenLayerIDs.insert(plan.layerID).inserted else {
                    continue
                }
                guard resolvedMaterialPlans[plan.layerID] == nil else {
                    continue
                }
                guard let chain = authoredEffectChain(
                    for: plan.layerID
                ) else { continue }
                guard let layer = layersByID[plan.layerID] else {
                    continue
                }
                guard visibleLayerIDs.contains(layer.id) else { continue }

                let desiredSize = utilityOffscreenSize(
                    plan: plan,
                    layer: layer,
                    worldFramesByLayerID: worldFramesByLayerID,
                    cameraFrame: cameraFrame,
                    viewportSize: viewportSize,
                    parallaxConfiguration: parallaxConfiguration,
                    parallaxMouse: frameContext.cameraParallaxPosition
                )
                guard let framePlan = offscreenTexturePool
                    .legacyAuthoredChainFramePlan(
                        for: chain,
                        requestedWidth: max(
                            1, Int(desiredSize.width.rounded(.up))
                        ),
                        requestedHeight: max(
                            1, Int(desiredSize.height.rounded(.up))
                        ),
                        orderingContext: orderingContext
                    )
                else { return nil }
                framePlans.append(framePlan)
            }
        }

        guard !framePlans.isEmpty else { return [:] }

        return offscreenTexturePool.prepareLegacyAuthoredFrameBatch(
            framePlans: framePlans,
            orderingContext: orderingContext
        )
    }

    /// Convenience that prepares the batch, registers release, and
    /// handles resolved-material rollback on failure. Returns the
    /// frame-local tables dictionary or nil.
    static func prepareAndRegisterLegacyAuthoredBatch(
        renderer: SceneMetalRenderer,
        resolvedMaterialPlans: [Int: SceneResolvedMaterialFrameTargetPlan],
        offscreenTexturePool: SceneOffscreenTexturePool?,
        imageTextures: SceneBaseImageTextureSnapshot,
        dynamicTextRenderSizes: [Int: [Float]],
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        commandBuffer: MTLCommandBuffer,
        compositor: SceneImageLayerCompositor,
        transaction: SceneSourceUpdateTransaction
    ) -> [Int: SceneOffscreenTexturePool.LegacyAuthoredFrameTables]? {
        guard let tables = renderer.prepareLegacyAuthoredFrameBatch(
            resolvedMaterialPlans: resolvedMaterialPlans,
            offscreenTexturePool: offscreenTexturePool,
            imageTextures: imageTextures,
            dynamicTextRenderSizes: dynamicTextRenderSizes,
            frameContext: frameContext,
            worldFramesByLayerID: worldFramesByLayerID,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            commandBuffer: commandBuffer
        ) else {
            _ = compositor.endResolvedMaterialFrame(on: commandBuffer)
            return nil
        }
        let commits = tables.values.map(\.commit)
        if !commits.isEmpty {
            transaction.registerResolution(
                completed: { for c in commits { c.releaseAll() } },
                rollback: { for c in commits.reversed() { c.releaseAll() } }
            )
        }
        return tables
    }

    // MARK: - Offscreen size (matching dispatch-time compositor calc)

    private func layerOffscreenSize(
        for layer: SceneRenderDescriptor.Layer,
        imageTextures: SceneBaseImageTextureSnapshot,
        dynamicTextRenderSizes: [Int: [Float]],
        viewportSize: CGSize,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        parallaxMouse: SIMD2<Float>
    ) -> CGSize {
        if layer.contentKind == "solid" {
            let model = imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFramesByLayerID,
                renderSizeOverride: dynamicTextRenderSizes[layer.id],
                parallaxMouseNormalized: parallaxMouse,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents
            )
            if let projected = SceneCaptureGeometryResolver.projectedPixelSize(
                layerMVP: cameraFrame.orthographicViewProjection * model,
                viewportSize: viewportSize
            ) {
                return projected
            }
        }
        guard let texture = imageTextures[layer.id] else {
            return viewportSize
        }
        return CGSize(width: texture.width, height: texture.height)
    }

    private func utilityOffscreenSize(
        plan: SceneUtilityLayerRuntimePlan,
        layer: SceneRenderDescriptor.Layer,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        viewportSize: CGSize,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        parallaxMouse: SIMD2<Float>
    ) -> CGSize {
        let model = imageModelMatrix(
            for: layer,
            worldFramesByLayerID: worldFramesByLayerID,
            parallaxMouseNormalized: parallaxMouse,
            configuration: parallaxConfiguration,
            visibleHalfExtents: cameraFrame.coverHalfExtents
        )
        let mvp = cameraFrame.orthographicViewProjection * model
        if let geometry = SceneCaptureGeometryResolver.resolve(
            kind: plan.kind,
            layerMVP: mvp,
            viewportSize: viewportSize
        ) {
            return geometry.pixelSize
        }
        return viewportSize
    }
}
