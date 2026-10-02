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
    }

    /// One frame's original model depth plan, optionally prepared ahead of shadow.
    /// A failed prepared lease remains a failed draw, rather than requesting twice.
    final class StaticModelFrame {
        struct Depth {
            let lease: SceneParticleDepthTargetLease?
            let clears: Bool
            var shared: Bool = false
        }
        var plan = SceneStaticModelDepthPlan()
        var sharedLease: SceneParticleDepthTargetLease?
        var sharedWasCleared = false
        var prepared: [Int: [StaticModelDraw]]?
        var particleDepth: [Int: Depth] = [:]
        var shadow: SceneStaticModelShadow?
        var pins: [SceneGraphRenderTargetResidencyPin] = []

        func depth(for draw: StaticModelDraw, pass: SceneMainPassEncoder,
                   pool: SceneParticleDepthTargetPool, device: MTLDevice,
                   leases: inout [SceneParticleDepthTargetLease]) -> Depth {
            let target = plan.target(geometryIdentity: draw.entry.geometryIdentity, modelMatrix: draw.world)
            let extent = pass.targetExtent
            switch target {
            case .shared:
                if sharedLease == nil {
                    sharedLease = pool.acquire(device: device, width: extent.width, height: extent.height)
                    if let sharedLease { leases.append(sharedLease) }
                }
                let result = Depth(lease: sharedLease, clears: true, shared: true)
                return result
            case .isolated:
                let lease = pool.acquire(device: device, width: extent.width, height: extent.height)
                if let lease { leases.append(lease) }
                return Depth(lease: lease, clears: true)
            }
        }

        func arm(on commandBuffer: MTLCommandBuffer) {
            let submitted = pins
            commandBuffer.addCompletedHandler { _ in submitted.forEach { $0.release() } }
            pins.removeAll(); shadow = nil
        }
        func cancel() {
            pins.forEach { $0.release() }
            pins.removeAll(); shadow = nil
        }
    }

    func staticModelDraws(layer: SceneRenderDescriptor.Layer,
                         worldFrames: [Int: simd_float4x4], snapshot: SceneDynamicSnapshot) -> [StaticModelDraw] {
        guard let parts = staticModelResources[layer.id] else { return [] }
        let world = worldFrames[layer.id] ?? SceneMatrix.identity()
        // Authored zero scale can leave planar geometry while the color draw
        // rejects its singular normal transform. Apply that same admission before
        // collecting depth leases, shadow bounds or casters for this layer.
        guard SceneStaticModelPipeline.normalMatrix(for: world) != nil else { return [] }
        return parts.compactMap { entry in
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
                    authoredValue: layer.alpha, snapshot: snapshot)))
        }
    }

    func drawStaticModel(layer: SceneRenderDescriptor.Layer, state: StaticModelFrame,
                         worldFrames: [Int: simd_float4x4], frameContext: SceneFrameContext,
                         cameraFrame: SceneParticleCameraFrame, lighting: SceneLightSnapshot,
                         pass: SceneMainPassEncoder, commandBuffer: MTLCommandBuffer,
                         leases: inout [SceneParticleDepthTargetLease]) -> Bool {
        guard let pipeline = staticModelResources.pipeline else { return false }
        let draws = state.prepared?[layer.id]
            ?? staticModelDraws(layer: layer, worldFrames: worldFrames, snapshot: frameContext.dynamicValues)
        var encodedLit = false
        for draw in draws {
            let depth = draw.depth ?? state.depth(for: draw, pass: pass,
                pool: staticModelDepthTargetPool, device: device, leases: &leases)
            guard let lease = depth.lease, let encoder = pass.encoder(
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
                layerAlpha: draw.alpha, material: draw.material, lighting: lighting,
                writesDepth: draw.entry.writesDepth, shadow: state.shadow,
                frameEpoch: textureRegistry.frameEpoch, commandBuffer: commandBuffer, encoder: encoder)
#if DEBUG
            if encoded, draw.material.receivesLighting, let shadow = state.shadow,
               SceneDesktopWallpaperHost.usesDebugEvidenceWindow && frameContext.frameIndex <= 2 {
                NSLog("MWX Scene shadow phase=receiver epoch=%llu light=%d generation=%llu layer=%d",
                    shadow.frameEpoch, shadow.lightLayerID, shadow.generation, layer.id)
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
            guard let parts = staticModelResources[layer.id] else { continue }
            for part in parts where part.namedAlbedo != nil {
                guard let reference = part.namedAlbedo,
                      dependencyRuntime.staticModelNamedAlbedo(for: layer.id,
                        materialPath: part.materialPath, expectedReference: reference,
                        textureRegistry: textureRegistry) != nil else { return nil }
            }
            result[layer.id] = staticModelDraws(layer: layer, worldFrames: worldFrames, snapshot: snapshot)
        }
        return result
    }

    func prepareModelShadow(
        state: StaticModelFrame, candidates: [Int: [StaticModelDraw]], light: SceneLightSnapshot.Directional,
        orderedLayers: [SceneRenderDescriptor.Layer], visible: Set<Int>,
        batches: [Int: [SceneParticleDrawBatch]], particlePipeline: SceneParticleMetalPipeline?,
        mainPass: SceneMainPassEncoder, groups: SceneCompositionGroupFrameRuntime?,
        pool: SceneOffscreenTexturePool, commandBuffer: MTLCommandBuffer,
        leases: inout [SceneParticleDepthTargetLease], mandatoryCapacity: () -> Bool,
        recordsEvidence: Bool
    ) {
        guard let pipeline = staticModelResources.pipeline, let lightID = light.layerID else { return }
        var prepared = candidates
        var complete = true
        var casters: [StaticModelDraw] = []
        var bounds: [(minimum: SIMD3<Float>, maximum: SIMD3<Float>, world: simd_float4x4)] = []
        for layer in orderedLayers where visible.contains(layer.id) {
            guard let pass = groups?.renderPass(forLayerID: layer.id) ?? (groups == nil ? mainPass : nil) else { continue }
            if var draws = prepared[layer.id] {
                for index in draws.indices {
                    let depth = state.depth(for: draws[index], pass: pass, pool: staticModelDepthTargetPool,
                                            device: device, leases: &leases)
                    draws[index].depth = depth
                    complete = complete && depth.lease != nil
                    let draw = draws[index]
                    let casts = (layer.modelShadowCastIntent?.modelCastsShadow ?? true)
                        && draw.entry.albedo != nil
                    if casts { casters.append(draw) }
                    if casts || draw.material.receivesLighting {
                        bounds.append((draw.entry.mesh.boundsMinimum, draw.entry.mesh.boundsMaximum, draw.world))
                    }
                }
                prepared[layer.id] = draws
            }
            if let particlePipeline, let layerBatches = batches[layer.id],
               layerBatches.contains(where: { $0.renderState.requiresDepthAttachment }) {
                let extent = pass.targetExtent
                let lease = particlePipeline.acquireDepthTarget(width: extent.width, height: extent.height)
                state.particleDepth[layer.id] = .init(lease: lease, clears: true)
                if let lease { leases.append(lease) } else { complete = false }
            }
        }
        state.prepared = prepared
        guard complete, !casters.isEmpty, mandatoryCapacity(),
              let projection = SceneDirectionalShadowProjection.make(bounds: bounds,
                directionTowardLight: light.directionTowardLight, resolution: 1024),
              let target = pool.reserveDirectionalShadow(width: 1024, height: 1024,
                commandBuffer: commandBuffer) else { return }
        state.pins.append(target.pin)
        mainPass.closeForOffscreen(); groups?.closeAllGroupEncoders()
        let descriptor = MTLRenderPassDescriptor()
        descriptor.depthAttachment.texture = target.texture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = 1
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "Scene directional model shadow"
        var encoded = true
        for draw in casters {
            encoded = pipeline.drawShadow(mesh: draw.entry.mesh, texture: draw.texture,
                textureFrame: draw.textureFrame, sampling: draw.sampling,
                modelMatrix: draw.world, lightViewProjection: projection.worldToClip,
                layerAlpha: draw.alpha, material: draw.material, encoder: encoder) && encoded
        }
        encoder.endEncoding()
        guard encoded else { return }
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
        state.shadow = SceneStaticModelShadow(texture: target.texture, frameEpoch: textureRegistry.frameEpoch,
            generation: target.pin.generation, lightLayerID: lightID,
            worldToLightClip: projection.worldToClip, depthBias: projection.depthBias, commandBuffer: commandBuffer)
    }
}
