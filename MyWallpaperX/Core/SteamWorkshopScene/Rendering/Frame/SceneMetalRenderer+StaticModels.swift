import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    struct StaticModelDraw {
        let entry: ScenePreparedStaticModelResources.Entry
        let texture: MTLTexture
        let textureFrame: SceneTextureUVTransform
        let sampling: SceneTextureSampling
        let premultiplied: Bool
        let world: simd_float4x4
        let material: SceneStaticModelMaterial
        let alpha: Float
        var depth: StaticModelFrame.Depth?
        var partIndex: Int = 0
    }

    /// One frame's original model depth plan, optionally prepared ahead of shadow.
    /// A failed prepared lease remains a failed draw, rather than requesting twice.
    final class StaticModelFrame {
        struct Depth {
            let acquisition: SceneParticleDepthTargetPool.Acquisition
            let clears: Bool
            var shared: Bool = false

            var lease: SceneParticleDepthTargetLease? {
                if case let .acquired(lease) = acquisition { return lease }
                return nil
            }
        }
        var plan = SceneStaticModelDepthPlan()
        private var sharedAcquisition: SceneParticleDepthTargetPool.Acquisition?
        private weak var sharedPass: SceneMainPassEncoder?
        private var sharedCommandBuffer: MTLCommandBuffer?
        private var acceptsDepthBindings = true
        private(set) var depthDeferralReason: String?
        var sharedLease: SceneParticleDepthTargetLease? {
            if case let .acquired(lease)? = sharedAcquisition { return lease }
            return nil
        }
        var sharedWasCleared = false
        // Draw payloads may be rebuilt after late publication or an ordered
        // prepass exit. Depth selection/results outlive those payloads in this
        // same frame owner, including failed attempts that must not retry.
        private var modelDepthByLayerID: [Int: [Int: Depth]] = [:]
        var prepared: [Int: [StaticModelDraw]]?
        var particleDepth: [Int: Depth] = [:]
        var plainLighting: [Int: SceneLitCapturePayloadResolution] = [:]
        var imageMaterialStates: [Int: SceneMaterialRenderState] = [:]
        var unavailableImageMaterialLayerIDs: Set<Int> = []
        var terminalDepthFailureReason: String?
        var shadows: [SceneStaticModelShadow] = []
        var pins: [SceneGraphRenderTargetResidencyPin] = []

        func depth(for draw: StaticModelDraw, layerID: Int? = nil, pass: SceneMainPassEncoder,
                   pool: SceneParticleDepthTargetPool, device: MTLDevice,
                   commandBuffer: MTLCommandBuffer,
                   leases: inout [SceneParticleDepthTargetLease]) -> Depth {
            if let layerID, let existing = modelDepthByLayerID[layerID]?[draw.partIndex] {
                return existing
            }
            let target = plan.target(geometryIdentity: draw.entry.geometryIdentity, modelMatrix: draw.world)
            let extent = pass.targetExtent
            let acquisition: SceneParticleDepthTargetPool.Acquisition
            let shared: Bool
            switch target {
            case .shared:
                acquisition = sharedDepth(pass: pass, pool: pool, device: device,
                    commandBuffer: commandBuffer, leases: &leases).acquisition
                shared = true
            case .isolated:
                acquisition = pool.acquire(device: device, width: extent.width,
                    height: extent.height, on: commandBuffer)
                if case let .acquired(lease) = acquisition { leases.append(lease) }
                shared = false
            }
            if case .busyOtherFrame = acquisition {
                depthDeferralReason = "static-model-depth-in-flight"
            }
            let depth = Depth(acquisition: acquisition, clears: true, shared: shared)
            if let layerID { modelDepthByLayerID[layerID, default: [:]][draw.partIndex] = depth }
            return depth
        }

        func sharedDepth(pass: SceneMainPassEncoder, pool: SceneParticleDepthTargetPool,
                         device: MTLDevice, commandBuffer: MTLCommandBuffer,
                         leases: inout [SceneParticleDepthTargetLease]) -> Depth {
            if let sharedAcquisition {
                return Depth(acquisition: sharedAcquisition, clears: true, shared: true)
            }
            let extent = pass.targetExtent
            let acquisition = pool.acquire(device: device, width: extent.width,
                height: extent.height, on: commandBuffer)
            sharedAcquisition = acquisition
            sharedPass = pass
            sharedCommandBuffer = commandBuffer
            if case let .acquired(lease) = acquisition { leases.append(lease) }
            if case .busyOtherFrame = acquisition {
                depthDeferralReason = "static-model-depth-in-flight"
            }
            return Depth(acquisition: acquisition, clears: true, shared: true)
        }

        func terminalDepthBinding(pass: SceneMainPassEncoder,
                                  commandBuffer: MTLCommandBuffer) -> SceneImageLayerTerminalDepthBinding? {
            guard acceptsDepthBindings, sharedPass === pass,
                  sharedCommandBuffer === commandBuffer, pass.belongs(to: commandBuffer),
                  let lease = sharedLease else { return nil }
            let texture = lease.texture
            let extent = pass.targetExtent
            guard texture.pixelFormat == .depth32Float, texture.sampleCount == 1,
                  texture.width == extent.width, texture.height == extent.height else { return nil }
            return .init { [weak self, weak pass] actualPass in
                guard let self, let pass, self.acceptsDepthBindings,
                      actualPass === pass, self.sharedPass === pass,
                      self.sharedCommandBuffer === commandBuffer, pass.belongs(to: commandBuffer),
                      self.sharedLease?.texture === texture,
                      let encoder = pass.encoder(depthTexture: texture,
                          clearsDepth: !self.sharedWasCleared, clearDepth: 0) else { return nil }
                self.sharedWasCleared = true
                return encoder
            }
        }

        func arm(on commandBuffer: MTLCommandBuffer) {
            acceptsDepthBindings = false
            let submitted = pins
            commandBuffer.addCompletedHandler { _ in submitted.forEach { $0.release() } }
            pins.removeAll(); shadows.removeAll()
        }
        func cancel() {
            acceptsDepthBindings = false
            pins.forEach { $0.release() }
            pins.removeAll(); shadows.removeAll()
        }
    }

    func staticModelDraws(layer: SceneRenderDescriptor.Layer,
                         worldFrames: [Int: simd_float4x4], snapshot: SceneDynamicSnapshot,
                         requiresCompleteNamedInputs: Bool = false) -> [StaticModelDraw]? {
        guard let parts = staticModelResources[layer.id] else { return [] }
        var world = worldFrames[layer.id] ?? SceneMatrix.identity()
        if let height = renderDescriptor.camera.orthoHeight, height > 0 {
            // The canonical canvas frame is F * authoredWorld * F. Static
            // model vertices remain authored Y-up, so consume them as F * v.
            // Keep this complete matrix shared by color, normals and shadow.
            world.columns.1 = -world.columns.1
        }
        // Authored zero scale can leave planar geometry while the color draw
        // rejects its singular normal transform. Apply that same admission before
        // collecting depth leases, shadow bounds or casters for this layer.
        guard SceneStaticModelPipeline.normalMatrix(for: world) != nil else { return [] }
        var hasMissingInput = false
        let draws: [StaticModelDraw] = parts.enumerated().compactMap { partIndex, entry in
            let texture: MTLTexture
            let frame: SceneTextureUVTransform
            let sampling: SceneTextureSampling
            let premultiplied: Bool
            if let albedo = entry.albedo {
                texture = albedo.texture; frame = albedo.uvTransform
                sampling = albedo.sampling; premultiplied = false
            } else if let reference = entry.namedAlbedo,
                      let albedo = dependencyRuntime.staticModelNamedAlbedo(
                        for: layer.id, materialPath: entry.materialPath,
                        expectedReference: reference, textureRegistry: textureRegistry) {
                texture = albedo.texture; frame = albedo.textureFrame
                sampling = albedo.sampling; premultiplied = albedo.isPremultiplied
            } else {
                hasMissingInput = true
                dependencyRuntime.recordStaticModelBindingFailure(for: layer.id)
                return nil
            }
            let material = entry.material.resolvingDynamicValues(
                layerID: layer.id, materialPath: entry.dynamicMaterialPath, snapshot: snapshot
            ).resolvingDynamicViewTintBack(SceneDynamicLayerValues.color(
                layerID: layer.id,
                authoredValue: entry.material.viewTint.map { [$0.back.x, $0.back.y, $0.back.z] },
                snapshot: snapshot))
            return StaticModelDraw(entry: entry, texture: texture, textureFrame: frame,
                sampling: sampling, premultiplied: premultiplied,
                world: world, material: material,
                alpha: Float(SceneDynamicLayerValues.alpha(layerID: layer.id,
                    authoredValue: layer.alpha, snapshot: snapshot)), partIndex: partIndex)
        }
        return requiresCompleteNamedInputs && hasMissingInput ? nil : draws
    }

    func drawStaticModel(layer: SceneRenderDescriptor.Layer, state: StaticModelFrame,
                         worldFrames: [Int: simd_float4x4], frameContext: SceneFrameContext,
                         cameraFrame: SceneParticleCameraFrame, lighting: SceneLightSnapshot,
                         pass: SceneMainPassEncoder, commandBuffer: MTLCommandBuffer,
                         leases: inout [SceneParticleDepthTargetLease]) -> Bool {
        guard let pipeline = staticModelResources.pipeline else { return false }
        let draws = state.prepared?[layer.id]
            ?? staticModelDraws(layer: layer, worldFrames: worldFrames, snapshot: frameContext.dynamicValues) ?? []
        var encodedLit = false
        for draw in draws {
            let depth = draw.depth ?? state.depth(for: draw, layerID: layer.id, pass: pass,
                pool: staticModelDepthTargetPool, device: device,
                commandBuffer: commandBuffer, leases: &leases)
            if state.depthDeferralReason != nil { return encodedLit }
            guard case let .acquired(lease) = depth.acquisition, let encoder = pass.encoder(
                depthTexture: lease.texture, clearsDepth: depth.shared ? !state.sharedWasCleared : depth.clears,
                clearDepth: 0) else { continue }
            if depth.shared { state.sharedWasCleared = true }
            let encoded = pipeline.draw(mesh: draw.entry.mesh, texture: draw.texture,
                colorTextureIsPremultiplied: draw.premultiplied,
                emissiveMask: draw.entry.emissiveMask?.texture,
                emissiveMaskTextureFrame: draw.entry.emissiveMask?.uvTransform,
                emissiveMaskSampling: draw.entry.emissiveMask?.sampling,
                modelMatrix: draw.world,
                viewProjection: cameraFrame.reverseDepthViewProjection(
                    usesPerspective: cameraFrame.resolvesPerspective(for: layer)),
                cameraPosition: cameraFrame.perspectiveEyePosition,
                textureFrame: draw.textureFrame, sampling: draw.sampling,
                layerAlpha: draw.alpha, material: draw.material,
                materialColorIsOpaque: draw.entry.materialBlending == .normal, lighting: lighting,
                writesDepth: draw.entry.writesDepth, shadows: state.shadows,
                frameEpoch: textureRegistry.frameEpoch, commandBuffer: commandBuffer, encoder: encoder)
#if DEBUG
            if encoded, draw.material.receivesLighting,
               SceneDesktopWallpaperHost.usesDebugEvidenceWindow && frameContext.frameIndex <= 2 {
                for shadow in state.shadows {
                    NSLog("MWX Scene shadow phase=receiver epoch=%llu light=%d generation=%llu layer=%d",
                        shadow.frameEpoch, shadow.lightLayerID, shadow.generation, layer.id)
                }
            }
#endif
            encodedLit = encodedLit || (encoded && draw.material.receivesLighting)
            dependencyRuntime.recordStaticModelBindingIfRequired(
                for: layer.id, encoded: encoded, on: commandBuffer)
        }
        return encodedLit
    }

    /// Returns a complete draw set only when its original late bindings are already
    /// known. Pending named producers keep the original draw/lease path for this frame.
    func shadowDrawCandidates(orderedLayers: [SceneRenderDescriptor.Layer], visible: Set<Int>,
                              worldFrames: [Int: simd_float4x4], snapshot: SceneDynamicSnapshot,
                              groups: SceneCompositionGroupFrameRuntime?) -> [Int: [StaticModelDraw]]? {
        var result: [Int: [StaticModelDraw]] = [:]
        for layer in orderedLayers where visible.contains(layer.id) && layer.contentKind == "model" {
            if let groups, groups.renderPass(forLayerID: layer.id) == nil { continue }
            guard let draws = staticModelDraws(layer: layer, worldFrames: worldFrames, snapshot: snapshot,
                requiresCompleteNamedInputs: true) else { return nil }
            result[layer.id] = draws
        }
        return result
    }

    private func visitFramebufferSnapshotConsumers(
        layer: SceneRenderDescriptor.Layer, includesLayer: Bool,
        framePlans: [Int: SceneResolvedMaterialFrameTargetPlan], imageTextures: SceneBaseImageTextureSnapshot,
        frameContext: SceneFrameContext, batches: [Int: [SceneParticleDrawBatch]],
        particlePipeline: SceneParticleMetalPipeline?, mainPass: SceneMainPassEncoder,
        groups: SceneCompositionGroupFrameRuntime?,
        utilityExecution: SceneUtilityLayerRuntimePlanner.Execution,
        color: (SceneMainPassEncoder) -> Bool, particle: (SceneMainPassEncoder) -> Bool
    ) -> Bool {
        if includesLayer,
           let pass = groups?.renderPass(forLayerID: layer.id) ?? (groups == nil ? mainPass : nil) {
            if particlePipeline != nil,
               batches[layer.id]?.contains(where: { $0.refraction != nil }) == true,
               !particle(pass) { return false }
            let blend = layer.colorBlendMode ?? 0
            if ["image", "solid", "text"].contains(layer.contentKind), blend > 0,
               SceneLayerColorBlendRenderer.supports(blend),
               framePlans[layer.id] != nil
                || baseMaterialTextureSelection(for: layer, imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor: baseMaterialReadyProviderUsesAuthoredLayerColor(
                        for: layer, dynamicValues: frameContext.dynamicValues)).source != nil,
               !color(pass) { return false }
        }
        // The layer-loop defer executes these admitted plans even when its
        // trigger layer is hidden. Named inputs may publish later in this
        // frame, so readiness comes from the frame plan, not a texture lookup.
        for plan in utilityExecution.plansByTriggerLayerID[layer.id] ?? [] where framePlans[plan.layerID] != nil {
            guard let root = layersByID[plan.layerID], let blend = root.colorBlendMode,
                  blend > 0, SceneLayerColorBlendRenderer.supports(blend),
                  !plan.usesIsolatedGroupTarget || groups?.sourceIsAvailable(forLayerID: plan.layerID) == true,
                  let pass = groups?.compositeTargetPass(forRootID: plan.layerID)
                    ?? (groups == nil ? mainPass : nil) else { continue }
            if !color(pass) { return false }
        }
        return true
    }

    private func includeSnapshotTarget(_ pass: SceneMainPassEncoder,
                                       in required: inout SceneMainPassEncoder?) -> Bool {
        if let required {
            // A later extent must not replace an earlier unencoded snapshot slot.
            return required.targetExtent == pass.targetExtent
                && required.targetPixelFormat == pass.targetPixelFormat
        }
        required = pass
        return true
    }

    /// Protect each original snapshot's single slot before optional shadow.
    /// Capacity is shared by a surface's consumers; their background copies are not.
    func prepareFramebufferSnapshotCapacity(
        orderedLayers: [SceneRenderDescriptor.Layer], visible: Set<Int>,
        framePlans: [Int: SceneResolvedMaterialFrameTargetPlan], imageTextures: SceneBaseImageTextureSnapshot,
        frameContext: SceneFrameContext, batches: [Int: [SceneParticleDrawBatch]],
        particlePipeline: SceneParticleMetalPipeline?, mainPass: SceneMainPassEncoder,
        groups: SceneCompositionGroupFrameRuntime?,
        utilityExecution: SceneUtilityLayerRuntimePlanner.Execution
    ) -> Bool {
        var colorPass: SceneMainPassEncoder?
        var particlePass: SceneMainPassEncoder?
        for layer in orderedLayers {
            guard visitFramebufferSnapshotConsumers(layer: layer, includesLayer: visible.contains(layer.id),
                framePlans: framePlans, imageTextures: imageTextures, frameContext: frameContext,
                batches: batches, particlePipeline: particlePipeline, mainPass: mainPass, groups: groups,
                utilityExecution: utilityExecution,
                color: { includeSnapshotTarget($0, in: &colorPass) },
                particle: { includeSnapshotTarget($0, in: &particlePass) }) else { return false }
        }
        let prepareParticle = { () -> Bool in
            guard let pass = particlePass, let particlePipeline else { return true }
            let extent = pass.targetExtent
            return particlePipeline.framebufferSnapshot.prepareCapacity(width: extent.width, height: extent.height,
                pixelFormat: pass.targetPixelFormat, then: { true })
        }
        guard let pass = colorPass else { return prepareParticle() }
        let extent = pass.targetExtent
        // A later owner failure restores the earlier owner's old slot. Fixed
        // preparation order therefore cannot change the original draw's budget priority.
        return imageCompositor.prepareSnapshotCapacity(width: extent.width, height: extent.height,
            pixelFormat: pass.targetPixelFormat, then: prepareParticle)
    }

    func prepareModelShadow(
        state: StaticModelFrame, candidates: [Int: [StaticModelDraw]], lights: [SceneLightSnapshot.ShadowLight],
        orderedLayers: [SceneRenderDescriptor.Layer], visible: Set<Int>,
        batches: [Int: [SceneParticleDrawBatch]], particlePipeline: SceneParticleMetalPipeline?,
        mainPass: SceneMainPassEncoder, groups: SceneCompositionGroupFrameRuntime?,
        pool: SceneOffscreenTexturePool, commandBuffer: MTLCommandBuffer,
        leases: inout [SceneParticleDepthTargetLease], mandatoryCapacity: () -> Bool,
        recordsEvidence: Bool, cameraFrame: SceneParticleCameraFrame
    ) {
        guard staticModelResources.pipeline != nil else { return }
        guard prepareMandatoryDepth(state: state, candidates: candidates,
            orderedLayers: orderedLayers, visible: visible, batches: batches,
            particlePipeline: particlePipeline, mainPass: mainPass, groups: groups,
            commandBuffer: commandBuffer, leases: &leases) else { return }
        emitModelShadow(state: state, lights: lights, orderedLayers: orderedLayers,
            mainPass: mainPass, groups: groups, pool: pool, commandBuffer: commandBuffer,
            recordsEvidence: recordsEvidence, cameraFrame: cameraFrame,
            mandatoryCapacity: mandatoryCapacity)
    }

    /// Both optional producers protect the real draws' leases. Particle depth
    /// is independent of whether this scene has a static-model pipeline.
    func prepareMandatoryDepth(
        state: StaticModelFrame, candidates: [Int: [StaticModelDraw]],
        orderedLayers: [SceneRenderDescriptor.Layer], visible: Set<Int>,
        batches: [Int: [SceneParticleDrawBatch]], particlePipeline: SceneParticleMetalPipeline?,
        mainPass: SceneMainPassEncoder, groups: SceneCompositionGroupFrameRuntime?,
        commandBuffer: MTLCommandBuffer,
        leases: inout [SceneParticleDepthTargetLease]
    ) -> Bool {
        var prepared = state.prepared ?? candidates
        var complete = true
        for layer in orderedLayers where visible.contains(layer.id) {
            guard let pass = groups?.renderPass(forLayerID: layer.id) ?? (groups == nil ? mainPass : nil) else { continue }
            if staticModelResources.pipeline != nil, var draws = prepared[layer.id] {
                for index in draws.indices {
                    let depth = draws[index].depth ?? state.depth(for: draws[index], layerID: layer.id, pass: pass,
                        pool: staticModelDepthTargetPool, device: device,
                        commandBuffer: commandBuffer, leases: &leases)
                    draws[index].depth = depth
                    complete = complete && depth.lease != nil
                    if state.depthDeferralReason != nil {
                        prepared[layer.id] = draws
                        state.prepared = prepared
                        return false
                    }
                }
                prepared[layer.id] = draws
            }
            if let particlePipeline, let layerBatches = batches[layer.id],
               layerBatches.contains(where: { $0.renderState.requiresDepthAttachment }) {
                let extent = pass.targetExtent
                if let existing = state.particleDepth[layer.id] {
                    complete = complete && existing.lease != nil
                } else {
                    let acquisition = particlePipeline.acquireDepthTarget(width: extent.width,
                        height: extent.height, on: commandBuffer)
                    state.particleDepth[layer.id] = .init(acquisition: acquisition, clears: true)
                    if case let .acquired(lease) = acquisition { leases.append(lease) }
                    else { complete = false }
                }
            }
        }
        state.prepared = prepared
        return complete
    }

    /// Qualify optional terminal consumers before they own graph candidates.
    /// Complete real draws keep their original mandatory allocation order. A
    /// pending named model keeps its late path and excludes only this consumer.
    func unavailableSharedTerminalDepthLayers(
        _ layerIDs: Set<Int>, state: StaticModelFrame,
        orderedLayers: [SceneRenderDescriptor.Layer], ordinaryLayerIDs: Set<Int> = [],
        visible: Set<Int>,
        worldFrames: [Int: simd_float4x4], snapshot: SceneDynamicSnapshot,
        batches: [Int: [SceneParticleDrawBatch]], particlePipeline: SceneParticleMetalPipeline?,
        mainPass: SceneMainPassEncoder, groups: SceneCompositionGroupFrameRuntime?,
        commandBuffer: MTLCommandBuffer, leases: inout [SceneParticleDepthTargetLease]
    ) -> Set<Int> {
        let consumers = layerIDs.union(ordinaryLayerIDs)
        guard !consumers.isEmpty else { return [] }
        let mainConsumers = Set(layerIDs.filter {
            groups?.compositeTargetPass(forRootID: $0) === mainPass || groups == nil
        }).union(ordinaryLayerIDs.filter {
            groups?.renderPass(forLayerID: $0) === mainPass || groups == nil
        })
        guard !mainConsumers.isEmpty else { return consumers }
        // A degraded/unreserved group may become drawable in admission. Its
        // mandatory depth cannot be promised by this earlier complete plan.
        for layer in orderedLayers where visible.contains(layer.id) {
            let requiresDepth = staticModelResources.pipeline != nil && layer.contentKind == "model"
                || (particlePipeline != nil && batches[layer.id]?.contains(where: {
                    $0.renderState.requiresDepthAttachment
                }) == true)
            if requiresDepth, let groups, groups.renderPass(forLayerID: layer.id) == nil { return consumers }
        }
        guard let candidates = shadowDrawCandidates(orderedLayers: orderedLayers, visible: visible,
            worldFrames: worldFrames, snapshot: snapshot, groups: groups) else { return consumers }
        // Ordinary failed model parts keep their existing local failure. Once
        // their allocation attempts have priority, a valid shared lease remains
        // usable even if an isolated part could not obtain its own depth.
        _ = prepareMandatoryDepth(state: state, candidates: candidates, orderedLayers: orderedLayers,
            visible: visible, batches: batches, particlePipeline: particlePipeline,
            mainPass: mainPass, groups: groups, commandBuffer: commandBuffer, leases: &leases)
        if state.depthDeferralReason != nil { return consumers }
        _ = state.sharedDepth(pass: mainPass, pool: staticModelDepthTargetPool,
            device: device, commandBuffer: commandBuffer, leases: &leases)
        return state.terminalDepthBinding(pass: mainPass, commandBuffer: commandBuffer) == nil
            ? consumers : consumers.subtracting(mainConsumers)
    }

    /// Preserve the original mandatory allocation prefix before optional shadow.
    /// Only an actual capture's typed invalid result aborts the frame. A resource
    /// miss leaves the prefix for the original draw and the suffix unprepared.
    func prepareOrderedModelShadow(
        state: StaticModelFrame, lights: [SceneLightSnapshot.ShadowLight], lighting: SceneLightSnapshot,
        orderedLayers: [SceneRenderDescriptor.Layer], visible: Set<Int>,
        activeNamedModels: Set<Int>, forwardGraphProviders: Set<Int>,
        framePlans: [Int: SceneResolvedMaterialFrameTargetPlan], imageTextures: SceneBaseImageTextureSnapshot,
        imagePipeline: SceneImageLayerPipeline, frameContext: SceneFrameContext,
        worldFrames: [Int: simd_float4x4], cameraFrame: SceneParticleCameraFrame,
        parallax: SceneLayerParallax.Configuration, viewportSize: CGSize,
        batches: [Int: [SceneParticleDrawBatch]], particlePipeline: SceneParticleMetalPipeline?,
        mainPass: SceneMainPassEncoder, groups: SceneCompositionGroupFrameRuntime?,
        utilityExecution: SceneUtilityLayerRuntimePlanner.Execution,
        pool: SceneOffscreenTexturePool, commandBuffer: MTLCommandBuffer,
        leases: inout [SceneParticleDepthTargetLease], terminalCapacity: () -> Bool,
        recordsEvidence: Bool, executionTrace: SceneEffectExecutionFrameTrace? = nil,
        environmentSource: ((MTLCommandBuffer) -> SceneFrameTextureResource?)? = nil
    ) -> String? {
        guard staticModelResources.pipeline != nil else { return nil }
        state.prepared = [:]
        var colorPass: SceneMainPassEncoder?
        var particlePass: SceneMainPassEncoder?
        for layer in orderedLayers {
            let pass = groups?.renderPass(forLayerID: layer.id) ?? (groups == nil ? mainPass : nil)
            let drawsLayer = pass != nil && !forwardGraphProviders.contains(layer.id)
                && !(dependencyRuntime.requiresDemandedGraphOutputCapture(for: layer.id) && !visible.contains(layer.id))
            if let pass, drawsLayer {
                if dependencyRuntime.requiresCapture(for: layer.id, activeStaticModelConsumerLayerIDs: activeNamedModels),
                   !dependencyRuntime.requiresGraphOutputCapture(for: layer.id) {
                    let source = baseMaterialTextureSelection(for: layer, imageTextures: imageTextures,
                        readyProviderUsesAuthoredLayerColor: baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: layer, dynamicValues: frameContext.dynamicValues)).source
                    let result = captureRawDependencyProvider(layer: layer, source: source,
                        imageTextures: imageTextures, imagePipeline: imagePipeline, frameContext: frameContext,
                        worldFrames: worldFrames, cameraFrame: cameraFrame, parallax: parallax,
                        viewportSize: viewportSize, mainPass: pass,
                        preparesCapacityOnly: !dependencyRuntime.isStaticModelSourceProvider(layer.id))
                    if case let .invalid(reason)? = result {
#if DEBUG
                        executionTrace?.recordRouteOperation(layerID: layer.id,
                            origin: Self.effectExecutionOrigin(for: layer.contentKind),
                            operation: "named-provider-capture", outcome: .failed(reasonCode: reason))
#endif

                        return reason
                    }
                    if case .unavailable? = result { return nil }
                }
                if visible.contains(layer.id) {
                    if layer.contentKind == "model" {
                        guard var draws = staticModelDraws(layer: layer, worldFrames: worldFrames,
                            snapshot: frameContext.dynamicValues, requiresCompleteNamedInputs: true) else { return nil }
                        state.prepared?[layer.id] = draws
                        for index in draws.indices {
                            let depth = state.depth(for: draws[index], layerID: layer.id,
                                pass: pass, pool: staticModelDepthTargetPool,
                                device: device, commandBuffer: commandBuffer, leases: &leases)
                            draws[index].depth = depth
                            state.prepared?[layer.id] = draws
                            guard depth.lease != nil else { return nil }
                        }
                    }
                    if let particlePipeline, batches[layer.id]?.contains(where: { $0.renderState.requiresDepthAttachment }) == true {
                        if let existing = state.particleDepth[layer.id] {
                            guard existing.lease != nil else { return nil }
                        } else {
                            let extent = pass.targetExtent
                            let acquisition = particlePipeline.acquireDepthTarget(width: extent.width,
                                height: extent.height, on: commandBuffer)
                            state.particleDepth[layer.id] = .init(acquisition: acquisition, clears: true)
                            guard case let .acquired(lease) = acquisition else { return nil }
                            leases.append(lease)
                        }
                    }
                    if framePlans[layer.id] == nil, ["image", "solid", "text"].contains(layer.contentKind) {
                        let resolution: SceneLitCapturePayloadResolution
                        if let profile = baseMaterialProviderBindings.lightingProfile(for: layer), profile.surfaceEnabled {
                            let model = imageModelMatrix(for: layer, worldFramesByLayerID: worldFrames,
                                renderSizeOverride: imageTextures.layerSourceRenderSize(for: layer.id),
                                textCenterOffsetY: imageTextures.layerSourceTextCenterOffsetY(for: layer.id) ?? 0,
                                parallaxMouseNormalized: frameContext.cameraParallaxPosition, configuration: parallax,
                                visibleHalfExtents: cameraFrame.coverHalfExtents,
                                usesPerspective: cameraFrame.resolvesPerspective(for: layer))
                            // This only constructs the original typed payload. Its
                            // environment closure still runs at the original draw.
                            resolution = makeLitCapturePayload(profile: profile, snapshot: lighting,
                                dynamicValues: frameContext.dynamicValues, layerModelMatrix: model,
                                layerWorldFrame: worldFrames[layer.id] ?? SceneMatrix.identity(),
                                usesPerspective: cameraFrame.resolvesPerspective(for: layer), cameraFrame: cameraFrame,
                                sceneViewProjection: cameraFrame.viewProjection(for: layer),
                                environmentSource: environmentSource, geometryProduct: imageTextures.geometryProducts[layer.id])
                            state.plainLighting[layer.id] = resolution
                        } else { resolution = .miss(.profileMissing) }
                        guard let dimensions = compositionScratchDimensions(for: layer, pool: pool,
                            imageTextures: imageTextures, frameContext: frameContext, worldFrames: worldFrames,
                            cameraFrame: cameraFrame, parallax: parallax, lightingResolution: resolution),
                              let targets = pool.reserveCompositionTargets(dimensions: dimensions, commandBuffer: commandBuffer)
                        else { return nil }
                        targets.forEach { mainPass.retainCompositionPin($0.pin) }
                    }
                }
            }
            guard visitFramebufferSnapshotConsumers(layer: layer, includesLayer: drawsLayer && visible.contains(layer.id),
                framePlans: framePlans, imageTextures: imageTextures, frameContext: frameContext,
                batches: batches, particlePipeline: particlePipeline, mainPass: mainPass, groups: groups,
                utilityExecution: utilityExecution,
                color: { pass in
                    guard includeSnapshotTarget(pass, in: &colorPass) else { return false }
                    return imageCompositor.prepareSnapshotCapacity(width: pass.targetExtent.width,
                        height: pass.targetExtent.height, pixelFormat: pass.targetPixelFormat, then: { true })
                }, particle: { pass in
                    guard includeSnapshotTarget(pass, in: &particlePass), let particlePipeline else { return false }
                    return particlePipeline.framebufferSnapshot.prepareCapacity(width: pass.targetExtent.width,
                        height: pass.targetExtent.height, pixelFormat: pass.targetPixelFormat, then: { true })
                }) else { return nil }
        }
        guard terminalCapacity() else { return nil }
        emitModelShadow(state: state, lights: lights, orderedLayers: orderedLayers,
            mainPass: mainPass, groups: groups, pool: pool, commandBuffer: commandBuffer,
            recordsEvidence: recordsEvidence, cameraFrame: cameraFrame)
        return nil
    }

    private func emitModelShadow(
        state: StaticModelFrame, lights: [SceneLightSnapshot.ShadowLight],
        orderedLayers: [SceneRenderDescriptor.Layer], mainPass: SceneMainPassEncoder,
        groups: SceneCompositionGroupFrameRuntime?, pool: SceneOffscreenTexturePool,
        commandBuffer: MTLCommandBuffer, recordsEvidence: Bool,
        cameraFrame: SceneParticleCameraFrame, mandatoryCapacity: () -> Bool = { true }
    ) {
        guard let pipeline = staticModelResources.pipeline else { return }
        let includesDirectional = lights.contains { if case .directional = $0 { return true }; return false }
        var casters: [(draw: StaticModelDraw, frontFacing: MTLWinding)] = []
        var bounds: [(minimum: SIMD3<Float>, maximum: SIMD3<Float>, world: simd_float4x4)] = []
        var receiverBounds: [(minimum: SIMD3<Float>, maximum: SIMD3<Float>, world: simd_float4x4)] = []
        for layer in orderedLayers {
            // Native models use Y-up world winding. Canvas and fitted cameras
            // retain their reflected authored convention in the same light map.
            let frontFacing: MTLWinding = cameraFrame.defaultsToPerspective
                && cameraFrame.resolvesPerspective(for: layer) ? .clockwise : .counterClockwise
            for draw in state.prepared?[layer.id] ?? [] {
                let casts = layer.modelShadowCastIntent?.modelCastsShadow ?? true
                // Alpha-blended model parts do not contribute the depth-only
                // caster pass. Preserve color, receivers and existing bounds.
                if casts && draw.entry.materialBlending != .translucent {
                    casters.append((draw, frontFacing))
                }
                if includesDirectional && (casts || draw.material.receivesLighting) {
                    let item = (draw.entry.mesh.boundsMinimum, draw.entry.mesh.boundsMaximum, draw.world)
                    if casts { bounds.append(item) }
                    receiverBounds.append(item)
                }
            }
        }
        guard !casters.isEmpty, mandatoryCapacity() else { return }
        for (slot, light) in lights.enumerated() {
            guard let lightID = light.layerID else { continue }
            let projection: SceneStaticModelShadowProjection
            switch light {
            case .directional(let value):
                guard let value = SceneDirectionalShadowProjection.make(bounds: bounds,
                    receiverBounds: receiverBounds,
                    directionTowardLight: value.directionTowardLight, resolution: 1024) else { continue }
                projection = .directional(value)
            case .spot(let value):
                guard let value = SceneSpotShadowProjection.make(light: value) else { continue }
                projection = .spot(value)
            case .point(let value):
                projection = .point(ScenePointShadowProjection(light: value))
            }
            guard let target = pool.reserveModelShadow(slot: slot,
                width: 1024 * projection.atlasColumns, height: 1024 * projection.atlasRows,
                commandBuffer: commandBuffer) else { continue }
            state.pins.append(target.pin)
            mainPass.closeForOffscreen(); groups?.closeAllGroupEncoders()
            let descriptor = MTLRenderPassDescriptor()
            descriptor.depthAttachment.texture = target.texture
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.clearDepth = 1
            #if DEBUG
            let timestampEncoder = SceneGPUStageTimestampHook.render(commandBuffer, descriptor, role: "model-shadow")
            #else
            let timestampEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            #endif
            guard let encoder = timestampEncoder else { continue }
            encoder.label = "Scene model shadow slot \(slot)"
            var encoded = true
            for face in 0..<projection.faceCount {
                let viewport = projection.viewport(face: face, width: target.texture.width, height: target.texture.height)
                encoder.setViewport(viewport)
                encoder.setScissorRect(MTLScissorRect(x: Int(viewport.originX), y: Int(viewport.originY),
                    width: Int(viewport.width), height: Int(viewport.height)))
                for caster in casters {
                    let draw = caster.draw
                    encoded = pipeline.drawShadow(mesh: draw.entry.mesh, texture: draw.texture,
                        textureFrame: draw.textureFrame, sampling: draw.sampling,
                        modelMatrix: draw.world, projection: projection, face: face, viewport: viewport,
                        layerAlpha: draw.alpha, material: draw.material, encoder: encoder,
                        frontFacing: caster.frontFacing) && encoded
                }
            }
            encoder.endEncoding()
            // An incomplete map is never published, but any encoded access
            // retains its submission pin until this command buffer finishes.
            guard encoded else { continue }
#if DEBUG
            if recordsEvidence {
                NSLog("MWX Scene shadow phase=depth-written epoch=%llu light=%d generation=%llu casters=%d",
                    textureRegistry.frameEpoch, lightID, target.pin.generation, casters.count)
                let epoch = textureRegistry.frameEpoch, generation = target.pin.generation
                commandBuffer.addCompletedHandler { completed in
                    NSLog("MWX Scene shadow phase=completed epoch=%llu light=%d generation=%llu status=%ld",
                        epoch, lightID, generation, completed.status.rawValue)
                }
            }
#endif
            state.shadows.append(SceneStaticModelShadow(texture: target.texture, frameEpoch: textureRegistry.frameEpoch,
                generation: target.pin.generation, lightLayerID: lightID,
                projection: projection, commandBuffer: commandBuffer))
        }
    }
}
