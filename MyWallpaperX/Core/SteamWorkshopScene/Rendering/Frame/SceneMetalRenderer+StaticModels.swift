import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    struct StaticModelDraw {
        let entry: ScenePreparedStaticModelResources.Entry
        let mesh: SceneStaticModelMesh
        let texture: MTLTexture
        let textureFrame: SceneTextureUVTransform
        let sampling: SceneTextureSampling
        let premultiplied: Bool
        let world: simd_float4x4
        let normalMatrix: simd_float3x3
        let material: SceneStaticModelMaterial
        let alpha: Float
    }

    /// Pass-scoped scene depth in one command buffer. Models and qualified
    /// terminals share first-clear/resource decisions, including failed leases.
    final class StaticModelFrame {
        struct VolumeOccluder {
            let mesh: SceneStaticModelMesh
            let modelToClip: simd_float4x4
            let cullMode: MTLCullMode
            let testsDepth: Bool
        }

        struct Depth {
            let acquisition: SceneParticleDepthTargetPool.Acquisition
            /// Particle depth retains its original independent clear policy.
            let clears: Bool

            var lease: SceneParticleDepthTargetLease? {
                if case let .acquired(lease) = acquisition { return lease }
                return nil
            }
        }
        private final class SceneDepthDomain {
            let pass: SceneMainPassEncoder
            let acquisition: SceneParticleDepthTargetPool.Acquisition
            var wasCleared = false

            init(pass: SceneMainPassEncoder, acquisition: SceneParticleDepthTargetPool.Acquisition) {
                self.pass = pass
                self.acquisition = acquisition
            }
            var lease: SceneParticleDepthTargetLease? {
                if case let .acquired(lease) = acquisition { return lease }
                return nil
            }
        }
        private let commandBuffer: MTLCommandBuffer
        let collectsVolumeOccluders: Bool
        var volumeOccluders: [VolumeOccluder] = []
        // A present nil rejects this frame's direct draw; absence preserves the
        // immutable static resource. All passes consume this one publication.
        private var directMeshes: [Int: SceneStaticModelMesh?] = [:]
        private var sceneDepthByPass: [ObjectIdentifier: SceneDepthDomain] = [:]
        private var acceptsDepthBindings = true
        private(set) var depthDeferralReason: String?
        // Late publication refreshes draw payloads, never a domain's resource
        // decision (including a failed acquisition) or first-clear ownership.
        var prepared: [Int: [StaticModelDraw]]?
        var particleDepth: [Int: Depth] = [:]
        var plainLighting: [Int: SceneLitCapturePayloadResolution] = [:]
        var imageMaterialStates: [Int: SceneMaterialRenderState] = [:]
        var unavailableImageMaterialLayerIDs: Set<Int> = []
        var sceneDepthFailureReason: String?
        var shadows: [SceneStaticModelShadow] = []
        var pins: [SceneGraphRenderTargetResidencyPin] = []

        init(commandBuffer: MTLCommandBuffer, collectsVolumeOccluders: Bool = false) {
            self.commandBuffer = commandBuffer
            self.collectsVolumeOccluders = collectsVolumeOccluders
        }

        func publishDirectModelMesh(_ mesh: SceneStaticModelMesh?, for layerID: Int,
                                    on commandBuffer: MTLCommandBuffer) {
            guard self.commandBuffer === commandBuffer else {
                directMeshes.updateValue(nil, forKey: layerID)
                return
            }
            directMeshes.updateValue(mesh, forKey: layerID)
        }

        func mesh(for layerID: Int, bind: SceneStaticModelMesh) -> SceneStaticModelMesh? {
            if let publication = directMeshes[layerID] { return publication }
            return bind
        }

        func sharedDepth(pass: SceneMainPassEncoder, pool: SceneParticleDepthTargetPool,
                         device: MTLDevice, commandBuffer: MTLCommandBuffer,
                         leases: inout [SceneParticleDepthTargetLease]) -> Depth {
            guard acceptsDepthBindings else { return Depth(acquisition: .allocationFailed, clears: true) }
            guard self.commandBuffer === commandBuffer, pass.belongs(to: commandBuffer) else {
                sceneDepthFailureReason = "scene-depth-command-buffer-mismatch"
                return Depth(acquisition: .allocationFailed, clears: true)
            }
            let key = ObjectIdentifier(pass)
            if let domain = sceneDepthByPass[key] {
                return Depth(acquisition: domain.acquisition, clears: true)
            }
            let extent = pass.targetExtent
            let acquisition = pool.acquire(device: device, width: extent.width,
                height: extent.height, on: commandBuffer)
            sceneDepthByPass[key] = SceneDepthDomain(pass: pass, acquisition: acquisition)
            if case let .acquired(lease) = acquisition { leases.append(lease) }
            if case .busyOtherFrame = acquisition {
                depthDeferralReason = "static-model-depth-in-flight"
            }
            return Depth(acquisition: acquisition, clears: true)
        }

        private func qualifiedSceneDepthDomain(pass: SceneMainPassEncoder,
                                               commandBuffer: MTLCommandBuffer) -> SceneDepthDomain? {
            guard acceptsDepthBindings else { return nil }
            guard self.commandBuffer === commandBuffer, pass.belongs(to: commandBuffer) else {
                sceneDepthFailureReason = "scene-depth-command-buffer-mismatch"
                return nil
            }
            guard let domain = sceneDepthByPass[ObjectIdentifier(pass)],
                  let lease = domain.lease else { return nil }
            let texture = lease.texture
            let extent = pass.targetExtent
            guard domain.pass === pass, texture.pixelFormat == .depth32Float,
                  texture.sampleCount == 1, texture.width == extent.width,
                  texture.height == extent.height else {
                sceneDepthFailureReason = "scene-depth-domain-identity-mismatch"
                return nil
            }
            return domain
        }

        func sceneDepthEncoder(pass: SceneMainPassEncoder,
                               commandBuffer: MTLCommandBuffer) -> MTLRenderCommandEncoder? {
            guard let domain = qualifiedSceneDepthDomain(pass: pass, commandBuffer: commandBuffer),
                  let texture = domain.lease?.texture,
                  let encoder = pass.encoder(depthTexture: texture,
                      clearsDepth: !domain.wasCleared, clearDepth: 0) else { return nil }
            domain.wasCleared = true
            return encoder
        }

        func terminalDepthBinding(pass: SceneMainPassEncoder,
                                  commandBuffer: MTLCommandBuffer) -> SceneImageLayerTerminalDepthBinding? {
            guard qualifiedSceneDepthDomain(pass: pass, commandBuffer: commandBuffer) != nil else { return nil }
            return .init { [weak self, weak pass] actualPass in
                guard let self, let pass else { return nil }
                guard actualPass === pass else {
                    self.sceneDepthFailureReason = "scene-depth-terminal-pass-mismatch"
                    return nil
                }
                return self.sceneDepthEncoder(pass: pass, commandBuffer: commandBuffer)
            }
        }

        func arm(on commandBuffer: MTLCommandBuffer) {
            guard self.commandBuffer === commandBuffer else {
                sceneDepthFailureReason = "scene-depth-command-buffer-mismatch"
                return
            }
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
                         state: StaticModelFrame? = nil,
                         requiresCompleteNamedInputs: Bool = false) -> [StaticModelDraw]? {
        guard let parts = staticModelResources[layer.id] else { return [] }
        let world = staticModelWorld(for: layer.id, worldFrames: worldFrames)
        guard SceneStaticModelPipeline.isFinite(world) else { return [] }
        let normalMatrix = parts.contains { $0.material.requiresSurfaceNormal }
            ? SceneStaticModelPipeline.normalMatrix(for: world) : nil
        var hasMissingInput = false
        let draws: [StaticModelDraw] = parts.compactMap { entry in
            guard let partNormalMatrix = entry.material.requiresSurfaceNormal
                ? normalMatrix : matrix_identity_float3x3 else { return nil }
            let mesh: SceneStaticModelMesh
            if let state {
                guard let current = state.mesh(for: layer.id, bind: entry.mesh) else { return nil }
                mesh = current
            } else { mesh = entry.mesh }
            let texture: MTLTexture
            let frame: SceneTextureUVTransform
            let sampling: SceneTextureSampling
            let premultiplied: Bool
            switch entry.albedoSource {
            case let .asset(identity):
                guard let albedo = textureRegistry.resource(for: .asset(identity)) else { return nil }
                let candidate = albedo.publication.candidate
                texture = candidate.texture; frame = candidate.uvTransform
                sampling = candidate.sampling
                premultiplied = candidate.content == .color(.resolved(.premultipliedAlpha))
            case let .named(reference):
                guard let albedo = dependencyRuntime.staticModelNamedAlbedo(
                    for: layer.id, materialPath: entry.materialPath,
                    expectedReference: reference, textureRegistry: textureRegistry) else {
                    hasMissingInput = true
                    dependencyRuntime.recordStaticModelBindingFailure(for: layer.id)
                    return nil
                }
                texture = albedo.texture; frame = albedo.textureFrame
                sampling = albedo.sampling; premultiplied = albedo.isPremultiplied
            }
            let material = entry.material.resolvingDynamicValues(
                layerID: layer.id, materialPath: entry.dynamicMaterialPath, snapshot: snapshot
            ).resolvingDynamicViewTintBack(SceneDynamicLayerValues.color(
                layerID: layer.id,
                authoredValue: entry.material.viewTint.map { [$0.back.x, $0.back.y, $0.back.z] },
                snapshot: snapshot))
            return StaticModelDraw(entry: entry, mesh: mesh, texture: texture, textureFrame: frame,
                sampling: sampling, premultiplied: premultiplied,
                world: world, normalMatrix: partNormalMatrix, material: material,
                alpha: Float(SceneDynamicLayerValues.alpha(layerID: layer.id,
                    authoredValue: layer.alpha, snapshot: snapshot)))
        }
        return requiresCompleteNamedInputs && hasMissingInput ? nil : draws
    }

    func staticModelWorld(for layerID: Int,
                          worldFrames: [Int: simd_float4x4]) -> simd_float4x4 {
        var world = worldFrames[layerID] ?? SceneMatrix.identity()
        if let height = renderDescriptor.camera.orthoHeight, height > 0 {
            // The canonical canvas frame is F * authoredWorld * F. Static
            // model vertices remain authored Y-up, so consume them as F * v.
            // Keep this complete matrix shared by color, normals and shadow.
            world.columns.1 = -world.columns.1
        }
        return world
    }

    func drawStaticModel(layer: SceneRenderDescriptor.Layer, state: StaticModelFrame,
                         worldFrames: [Int: simd_float4x4], frameContext: SceneFrameContext,
                         cameraFrame: SceneParticleCameraFrame, lighting: SceneLightSnapshot,
                         reflection: SceneFrameTextureResource? = nil,
                         pass: SceneMainPassEncoder, commandBuffer: MTLCommandBuffer,
                         leases: inout [SceneParticleDepthTargetLease]) -> Bool {
        guard let pipeline = staticModelResources.pipeline else { return false }
        let draws = state.prepared?[layer.id]
            ?? staticModelDraws(layer: layer, worldFrames: worldFrames, snapshot: frameContext.dynamicValues, state: state) ?? []
        let usesPerspective = cameraFrame.resolvesPerspective(for: layer)
        let viewProjection = pass.rasterClipProjection(cameraFrame.reverseDepthViewProjection(
            usesPerspective: usesPerspective))
        let frontFacing = pass.rasterFrontFacing
        var encodedLit = false
        for draw in draws {
            _ = state.sharedDepth(pass: pass, pool: staticModelDepthTargetPool,
                device: device, commandBuffer: commandBuffer, leases: &leases)
            if state.depthDeferralReason != nil || state.sceneDepthFailureReason != nil { return encodedLit }
            guard let encoder = state.sceneDepthEncoder(pass: pass, commandBuffer: commandBuffer) else { continue }
            let environment = usesPerspective && pipeline.supportsReflection
                && (draw.material.surfaceProfile?.reflectivity ?? 0) > 0 ? reflection : nil
            let encoded = pipeline.draw(mesh: draw.mesh, texture: draw.texture,
                colorTextureIsPremultiplied: draw.premultiplied,
                materialMap: draw.entry.materialMap,
                normalMap: draw.entry.normalMap,
                gradient: draw.entry.gradient,
                pigment: draw.entry.pigment,
                modelMatrix: draw.world,
                normalMatrix: draw.normalMatrix,
                viewProjection: viewProjection,
                frontFacing: frontFacing,
                cameraPosition: cameraFrame.perspectiveEyePosition,
                textureFrame: draw.textureFrame, sampling: draw.sampling,
                layerAlpha: draw.alpha, material: draw.material,
                materialColorIsOpaque: draw.entry.materialBlending == .normal,
                additiveRGB: draw.entry.materialBlending == .additive, lighting: lighting,
                writesDepth: draw.entry.writesDepth, testsDepth: draw.entry.testsDepth, shadows: state.shadows,
                reflectionTexture: environment?.publication.texture,
                frameEpoch: textureRegistry.frameEpoch, commandBuffer: commandBuffer, encoder: encoder)
            if encoded && state.collectsVolumeOccluders && usesPerspective && pass.isSceneRoot
                && draw.entry.writesDepth && draw.entry.materialBlending == .normal && draw.alpha == 1 {
                state.volumeOccluders.append(.init(mesh: draw.mesh,
                    modelToClip: viewProjection * draw.world, cullMode: draw.material.cullMode,
                    testsDepth: draw.entry.testsDepth))
            }
#if DEBUG
            if let trace = pass.compositionTrace, trace.isCompositionSelected {
                var source = SceneCompositionTextureObservation(draw.texture, role: "model-color")
                source.sampling = String(describing: draw.sampling)
                source.uv = [draw.textureFrame.origin.x, draw.textureFrame.origin.y,
                    draw.textureFrame.xAxis.x, draw.textureFrame.xAxis.y,
                    draw.textureFrame.yAxis.x, draw.textureFrame.yAxis.y]
                trace.recordComposition(.init(kind: "model", layerID: layer.id, slot: 0,
                    source: source, target: pass.compositionTarget,
                    outcome: encoded ? "draw-encoded" : "failed",
                    reason: "model-internal-material-bindings-not-observed",
                    details: ["blending": draw.entry.materialBlending?.rawValue ?? "legacy",
                        "depthTest": String(draw.entry.testsDepth), "depthWrite": String(draw.entry.writesDepth)]))
                if encoded, let normal = draw.entry.normalMap {
                    trace.recordComposition(.init(kind: "model-normal", layerID: layer.id, slot: 7,
                        source: .init(normal.texture, role: "model-normal-data"),
                        target: pass.compositionTarget,
                        details: ["encoding": String(normal.encoding.rawValue)]))
                }
                if encoded, let map = draw.entry.materialMap {
                    trace.recordComposition(.init(kind: "model-material-map", layerID: layer.id, slot: 1,
                        source: .init(map.texture, role: "model-material-data"),
                        target: pass.compositionTarget,
                        details: ["components": String(map.components)]))
                }
                if encoded, let gradient = draw.entry.gradient {
                    trace.recordComposition(.init(kind: "model-gradient", layerID: layer.id, slot: 8,
                        source: .init(gradient.texture, role: "model-shading-gradient-data"),
                        target: pass.compositionTarget,
                        details: ["channels": gradient.replicatesRed ? "r" : "rgb"]))
                }
                if encoded, let environment,
                   case let .provider(.sceneEnvironment(_, _, producer)) = environment.publication.candidate.identity {
                    trace.recordComposition(.init(kind: "model-reflection", layerID: layer.id, slot: 6,
                        source: .init(environment.publication.texture, role: "scene-environment"),
                        target: pass.compositionTarget, details: ["producerFrameIndex": String(producer.frameIndex)]))
                }
            }
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow && frameContext.frameIndex <= 2 {
                let w = draw.world
                let world = [w.columns.0.x, w.columns.0.y, w.columns.0.z, w.columns.0.w,
                    w.columns.1.x, w.columns.1.y, w.columns.1.z, w.columns.1.w,
                    w.columns.2.x, w.columns.2.y, w.columns.2.z, w.columns.2.w,
                    w.columns.3.x, w.columns.3.y, w.columns.3.z, w.columns.3.w]
                    .map { String($0) }.joined(separator: ",")
                NSLog("MWX Scene model-depth frame=%llu layer=%d material=%@ domain=scene pass=%@ command=%@ encoded=%@ world=[%@]",
                    frameContext.frameIndex, layer.id, draw.entry.materialPath,
                    String(describing: ObjectIdentifier(pass)),
                    String(describing: ObjectIdentifier(commandBuffer)), String(encoded), world)
            }
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

    func encodeVolumeOccluderDepth(
        state: StaticModelFrame, pass: SceneMainPassEncoder, pool: SceneOffscreenTexturePool?,
        groups: SceneCompositionGroupFrameRuntime?, needsTerminalScratch: Bool
    ) -> MTLTexture? {
        guard !state.volumeOccluders.isEmpty, let pipeline = staticModelResources.pipeline,
              let pool else { return nil }
        let extent = pass.targetExtent
        return pass.withReadableTarget { color, commandBuffer -> MTLTexture? in
            if needsTerminalScratch, groups?.terminalScratch(matching: color, on: commandBuffer) == nil {
                guard let scratch = pool.reserveDisplayScratch(width: extent.width,
                    height: extent.height, commandBuffer: commandBuffer) else { return nil }
                pass.retainCompositionPin(scratch.pin)
            }
            guard let target = pool.reserveModelCameraDepth(width: extent.width,
                height: extent.height, commandBuffer: commandBuffer) else { return nil }
            state.pins.append(target.pin)
            let descriptor = MTLRenderPassDescriptor()
            descriptor.depthAttachment.texture = target.texture
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.clearDepth = 0
#if DEBUG
            let encoder = SceneGPUStageTimestampHook.render(commandBuffer, descriptor, role: "volume-occluder-depth")
#else
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
#endif
            guard let encoder else { return nil }
            let winding = pass.rasterFrontFacing
            for occluder in state.volumeOccluders {
                pipeline.drawCameraDepth(mesh: occluder.mesh, modelToClip: occluder.modelToClip,
                    frontFacing: winding, cullMode: occluder.cullMode,
                    testsDepth: occluder.testsDepth, encoder: encoder)
            }
            encoder.endEncoding()
#if DEBUG
            if let trace = pass.compositionTrace, trace.isCompositionSelected {
                trace.recordComposition(.init(kind: "volume-occluder-depth",
                    target: .init(target.texture, role: "model-camera-depth"), outcome: "encoded",
                    details: ["partCount": String(state.volumeOccluders.count)]))
            }
#endif
            return target.texture
        } ?? nil
    }

    /// Returns a complete draw set only when its original late bindings are already
    /// known. Pending named producers keep the original draw/lease path for this frame.
    func shadowDrawCandidates(orderedLayers: [SceneRenderDescriptor.Layer], visible: Set<Int>,
                              worldFrames: [Int: simd_float4x4], snapshot: SceneDynamicSnapshot,
                              groups: SceneCompositionGroupFrameRuntime?, state: StaticModelFrame? = nil) -> [Int: [StaticModelDraw]]? {
        let prefix = staticModelDrawPrefix(orderedLayers: orderedLayers, visible: visible,
            worldFrames: worldFrames, snapshot: snapshot, groups: groups, state: state)
        return prefix.count == orderedLayers.count ? prefix.draws : nil
    }

    private func staticModelDrawPrefix(orderedLayers: [SceneRenderDescriptor.Layer], visible: Set<Int>,
        worldFrames: [Int: simd_float4x4], snapshot: SceneDynamicSnapshot,
        groups: SceneCompositionGroupFrameRuntime?, state: StaticModelFrame?
    ) -> (draws: [Int: [StaticModelDraw]], count: Int) {
        var result: [Int: [StaticModelDraw]] = [:]
        for (index, layer) in orderedLayers.enumerated()
        where visible.contains(layer.id) && layer.contentKind == "model" {
            if let groups, groups.renderPass(forLayerID: layer.id) == nil { continue }
            guard let draws = staticModelDraws(layer: layer, worldFrames: worldFrames, snapshot: snapshot, state: state,
                requiresCompleteNamedInputs: true) else { return (result, index) }
            result[layer.id] = draws
        }
        return (result, orderedLayers.count)
    }

    private func visitFramebufferSnapshotConsumers(
        layer: SceneRenderDescriptor.Layer, includesLayer: Bool,
        framePlans: [Int: SceneResolvedMaterialFrameTargetPlan], imageTextures: SceneBaseImageTextureSnapshot,
        frameContext: SceneFrameContext, batches: [Int: [SceneParticleMetalPipeline.PreparedBatch]],
        particlePipeline: SceneParticleMetalPipeline?, mainPass: SceneMainPassEncoder,
        groups: SceneCompositionGroupFrameRuntime?,
        utilityExecution: SceneUtilityLayerRuntimePlanner.Execution,
        color: (SceneMainPassEncoder) -> Bool, particle: (SceneMainPassEncoder) -> Bool
    ) -> Bool {
        if includesLayer,
           let pass = groups?.renderPass(forLayerID: layer.id) ?? (groups == nil ? mainPass : nil) {
            if particlePipeline != nil,
               batches[layer.id]?.contains(where: { $0.draw.refraction != nil }) == true,
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
        frameContext: SceneFrameContext, batches: [Int: [SceneParticleMetalPipeline.PreparedBatch]],
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
        batches: [Int: [SceneParticleMetalPipeline.PreparedBatch]], particlePipeline: SceneParticleMetalPipeline?,
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
        batches: [Int: [SceneParticleMetalPipeline.PreparedBatch]], particlePipeline: SceneParticleMetalPipeline?,
        mainPass: SceneMainPassEncoder, groups: SceneCompositionGroupFrameRuntime?,
        commandBuffer: MTLCommandBuffer,
        leases: inout [SceneParticleDepthTargetLease], prefixCount: Int? = nil
    ) -> Bool {
        let prepared = state.prepared ?? candidates
        if prefixCount == nil { state.prepared = prepared }
        var complete = true
        for layer in orderedLayers.prefix(prefixCount ?? orderedLayers.count)
        where visible.contains(layer.id) {
            let modelNeedsDepth = staticModelResources.pipeline != nil && prepared[layer.id]?.isEmpty == false
            let particleNeedsDepth = particlePipeline != nil
                && batches[layer.id]?.contains(where: { $0.draw.renderState.depthWriteEnabled }) == true
            guard modelNeedsDepth || particleNeedsDepth,
                  let pass = groups?.renderPass(forLayerID: layer.id) ?? (groups == nil ? mainPass : nil)
            else { continue }
            if modelNeedsDepth {
                let depth = state.sharedDepth(pass: pass, pool: staticModelDepthTargetPool,
                    device: device, commandBuffer: commandBuffer, leases: &leases)
                complete = complete && depth.lease != nil
                if state.depthDeferralReason != nil || state.sceneDepthFailureReason != nil { return false }
            }
            if particleNeedsDepth, let particlePipeline {
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
        return complete
    }

    /// Qualify optional terminal consumers before they own graph candidates.
    /// Complete real draws keep their original mandatory allocation order. A
    /// pending named model keeps its late path. Ordinary terminals establish
    /// the same pass domain even when no model color is ready yet.
    func unavailableSharedTerminalDepthLayers(
        _ layerIDs: Set<Int>, state: StaticModelFrame,
        orderedLayers: [SceneRenderDescriptor.Layer], ordinaryLayerIDs: Set<Int> = [],
        visible: Set<Int>,
        worldFrames: [Int: simd_float4x4], snapshot: SceneDynamicSnapshot,
        batches: [Int: [SceneParticleMetalPipeline.PreparedBatch]], particlePipeline: SceneParticleMetalPipeline?,
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
        if let groups {
            for layer in orderedLayers where visible.contains(layer.id) {
                let requiresDepth = staticModelResources.pipeline != nil && layer.contentKind == "model"
                    || (particlePipeline != nil && batches[layer.id]?.contains(where: {
                        $0.draw.renderState.depthWriteEnabled
                    }) == true)
                if requiresDepth, groups.renderPass(forLayerID: layer.id) == nil { return consumers }
            }
        }
        let prefix = staticModelDrawPrefix(orderedLayers: orderedLayers, visible: visible,
            worldFrames: worldFrames, snapshot: snapshot, groups: groups, state: state)
        let complete = prefix.count == orderedLayers.count
        let eligible = complete ? mainConsumers : mainConsumers.intersection(ordinaryLayerIDs)
        let prefixCount: Int?
        if complete {
            prefixCount = nil
        } else {
            guard !eligible.isEmpty else { return consumers }
            let firstMain = orderedLayers.prefix(prefix.count).firstIndex { layer in
                prefix.draws[layer.id]?.isEmpty == false
                    && (groups == nil || groups?.renderPass(forLayerID: layer.id) === mainPass)
            }
            prefixCount = firstMain.map { $0 + 1 } ?? prefix.count
        }
        // Ordinary failed model parts keep their existing local failure. Once
        // their allocation attempts have priority; a valid scene-domain lease
        // remains usable if another mandatory resource could not be acquired.
        _ = prepareMandatoryDepth(state: state, candidates: prefix.draws, orderedLayers: orderedLayers,
            visible: visible, batches: batches, particlePipeline: particlePipeline,
            mainPass: mainPass, groups: groups, commandBuffer: commandBuffer, leases: &leases,
            prefixCount: prefixCount)
        if state.depthDeferralReason != nil || state.sceneDepthFailureReason != nil { return consumers }
        if !eligible.isEmpty {
            _ = state.sharedDepth(pass: mainPass, pool: staticModelDepthTargetPool,
                device: device, commandBuffer: commandBuffer, leases: &leases)
        }
        return state.terminalDepthBinding(pass: mainPass, commandBuffer: commandBuffer) == nil
            ? consumers : consumers.subtracting(eligible)
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
        batches: [Int: [SceneParticleMetalPipeline.PreparedBatch]], particlePipeline: SceneParticleMetalPipeline?,
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
                        guard let draws = staticModelDraws(layer: layer, worldFrames: worldFrames,
                            snapshot: frameContext.dynamicValues, state: state, requiresCompleteNamedInputs: true) else { return nil }
                        state.prepared?[layer.id] = draws
                        if !draws.isEmpty {
                            let depth = state.sharedDepth(pass: pass, pool: staticModelDepthTargetPool,
                                device: device, commandBuffer: commandBuffer, leases: &leases)
                            guard depth.lease != nil else { return nil }
                        }
                    }
                    if let particlePipeline, batches[layer.id]?.contains(where: { $0.draw.renderState.depthWriteEnabled }) == true {
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
                                textPlacement: imageTextures.layerSourceTextPlacement(for: layer.id),
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
                if casts {
                    casters.append((draw, frontFacing))
                }
                if includesDirectional && (casts || draw.material.receivesLighting) {
                    let item = (draw.mesh.boundsMinimum, draw.mesh.boundsMaximum, draw.world)
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
                    encoded = pipeline.drawShadow(mesh: draw.mesh, texture: draw.texture,
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
