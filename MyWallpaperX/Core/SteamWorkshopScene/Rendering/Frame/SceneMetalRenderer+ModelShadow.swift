import Foundation
import Metal
import simd

extension SceneMetalRenderer {
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

    func emitModelShadow(
        state: StaticModelFrame, lights: [SceneLightSnapshot.ShadowLight],
        orderedLayers: [SceneRenderDescriptor.Layer], mainPass: SceneMainPassEncoder,
        groups: SceneCompositionGroupFrameRuntime?, pool: SceneOffscreenTexturePool,
        commandBuffer: MTLCommandBuffer, recordsEvidence: Bool,
        cameraFrame: SceneParticleCameraFrame, shadowOnlyDraws: [Int: [StaticModelDraw]] = [:],
        mandatoryCapacity: () -> Bool = { true }
    ) {
        guard let pipeline = staticModelResources.pipeline,
              let dimensionLimit = staticModelResources.directionalShadowDimensionLimit else { return }
        let includesDirectional = lights.contains { if case .directional = $0 { return true }; return false }
        let includesLocal = lights.contains { if case .directional = $0 { return false }; return true }
        var casters: [(draw: StaticModelDraw, frontFacing: MTLWinding, directional: Bool)] = []
        var bounds: [(minimum: SIMD3<Float>, maximum: SIMD3<Float>, world: simd_float4x4)] = []
        var receiverBounds: [(minimum: SIMD3<Float>, maximum: SIMD3<Float>, world: simd_float4x4,
                              clip: simd_float4x4?)] = []
        var receiverExtent = 0
        for layer in orderedLayers {
            let draws = state.prepared?[layer.id] ?? shadowOnlyDraws[layer.id] ?? []
            if draws.isEmpty { continue }
            // Native models use Y-up world winding. Canvas and fitted cameras
            // retain their reflected authored convention in the same light map.
            let usesPerspective = cameraFrame.resolvesPerspective(for: layer)
            let frontFacing: MTLWinding = cameraFrame.defaultsToPerspective
                && usesPerspective ? .clockwise : .counterClockwise
            let receiverClip: simd_float4x4?
            if includesDirectional && draws.contains(where: { $0.material.receivesLighting }) {
                let pass = groups?.renderPass(forLayerID: layer.id) ?? (groups == nil ? mainPass : nil)
                receiverClip = pass.map {
                    state.cameraClipProjection(for: layer, camera: cameraFrame,
                        usesPerspective: usesPerspective, pass: $0)
                }
                if let extent = pass?.targetExtent {
                    receiverExtent = max(receiverExtent, extent.width, extent.height)
                }
            } else { receiverClip = nil }
            for draw in draws {
                let casts = (layer.modelShadowCastIntent?.modelCastsShadow ?? true) && draw.material.opacity > 0
                let directional = draw.entry.materialBlending != .translucent
                    || draw.material.surfaceProfile?.kind != .generic4
                if casts && (directional || includesLocal) {
                    casters.append((draw, frontFacing, directional))
                }
                if includesDirectional {
                    let item = (draw.mesh.boundsMinimum, draw.mesh.boundsMaximum, draw.world)
                    if casts && directional { bounds.append(item) }
                    if draw.material.receivesLighting {
                        receiverBounds.append((item.0, item.1, item.2, receiverClip))
                    }
                }
            }
        }
        guard !casters.isEmpty else {
            state.shadowUse = .noReceiver
            return
        }
        guard mandatoryCapacity() else { return }
        let baseResolution = min(1024, dimensionLimit)
        let directionalResolution: Int
        if receiverExtent > 2048 { directionalResolution = 4096 }
        else if receiverExtent > 1024 { directionalResolution = 2048 }
        else { directionalResolution = 1024 }
        var plans: [(slot: Int, lightID: Int, projection: SceneStaticModelShadowProjection,
                     resolution: Int)] = []
        for (slot, light) in lights.enumerated() {
            guard let lightID = light.layerID else { continue }
            let projection: SceneStaticModelShadowProjection
            var resolution = baseResolution
            switch light {
            case .directional(let value):
                // The conservative base-map border also covers denser maps,
                // so allocation fallback reuses this fit without clipping again.
                guard let value = SceneDirectionalShadowProjection.make(bounds: bounds,
                    receiverBounds: receiverBounds,
                    directionTowardLight: value.directionTowardLight, resolution: baseResolution,
                    noInfluence: { state.shadowLights.removeAll { $0.layerID == lightID } }) else { continue }
                projection = .directional(value)
                resolution = min(directionalResolution, dimensionLimit)
            case .spot(let value):
                guard let value = SceneSpotShadowProjection.make(light: value) else { continue }
                projection = .spot(value)
            case .point(let value):
                projection = .point(ScenePointShadowProjection(light: value))
            }
            plans.append((slot, lightID, projection, resolution))
        }
        let targets: [Int: SceneOffscreenTexturePool.PinnedTexture]?
        if plans.contains(where: { $0.resolution > baseResolution }) {
            targets = pool.reserveModelShadows(dimensions: plans.map { plan in
                (plan.slot, plan.resolution * plan.projection.atlasColumns,
                    plan.resolution * plan.projection.atlasRows)
            }, fallbackDimensions: plans.map { plan in
                (plan.slot, baseResolution * plan.projection.atlasColumns, baseResolution * plan.projection.atlasRows)
            }, commandBuffer: commandBuffer)
        } else { targets = nil }
        // Upgrade the complete light set atomically; one large map must not
        // consume the smaller maps that the original allocation could retain.
        for (slot, lightID, projection, plannedFace) in plans {
            let target: SceneOffscreenTexturePool.PinnedTexture?
            if let targets { target = targets[slot] }
            else {
                target = pool.reserveModelShadow(slot: slot,
                    width: baseResolution * projection.atlasColumns, height: baseResolution * projection.atlasRows,
                    commandBuffer: commandBuffer)
            }
            guard let target else { continue }
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
            let isDirectional = if case .directional = projection { true } else { false }
            var encoded = true
            for face in 0..<projection.faceCount {
                let viewport = projection.viewport(face: face, width: target.texture.width, height: target.texture.height)
                encoder.setViewport(viewport)
                encoder.setScissorRect(MTLScissorRect(x: Int(viewport.originX), y: Int(viewport.originY),
                    width: Int(viewport.width), height: Int(viewport.height)))
                for caster in casters where !isDirectional || caster.directional {
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
                NSLog("MWX Scene shadow phase=depth-written epoch=%llu light=%d generation=%llu casters=%d width=%d height=%d faces=%d",
                    textureRegistry.frameEpoch, lightID, target.pin.generation, isDirectional ? bounds.count : casters.count,
                    target.texture.width, target.texture.height, projection.faceCount)
                let epoch = textureRegistry.frameEpoch, generation = target.pin.generation
                commandBuffer.addCompletedHandler { completed in
                    NSLog("MWX Scene shadow phase=completed epoch=%llu light=%d generation=%llu status=%ld",
                        epoch, lightID, generation, completed.status.rawValue)
                }
            }
#endif
            let face = target.texture.width / projection.atlasColumns
            let ceiling = isDirectional ? directionalResolution : 1024
            let limit: SceneStaticModelShadow.ResolutionLimit?
            if face < plannedFace { limit = .reduced }
            else if face == ceiling && ceiling < 4096 { limit = .ceiling }
            else { limit = nil }
            state.shadows.append(SceneStaticModelShadow(texture: target.texture, frameEpoch: textureRegistry.frameEpoch,
                generation: target.pin.generation, lightLayerID: lightID,
                projection: projection, commandBuffer: commandBuffer, resolutionLimit: limit))
        }
    }
}

extension SceneMetalRenderer.StaticModelFrame {
    func finishShadowUse(drewCompleteMainColor: Bool) {
        if drewCompleteMainColor {
            shadowUse = shadowUse ?? (hadEligibleShadowReceiver ? .unavailable : .noReceiver)
        } else {
            shadowUse = nil
        }
    }

    func recordShadowUse(_ bindings: ArraySlice<SceneStaticModelPipeline.ShadowBinding>) {
        guard !bindings.isEmpty else {
            shadowUse = .unavailable
            return
        }
        var maps: [SceneShadowUse.Map] = bindings.map { shadow, _ in
            let family: SceneShadowUse.Family = switch shadow.projection {
            case .directional: .directional
            case .point: .point
            case .spot: .spot
            }
            let face = shadow.texture.width / shadow.projection.atlasColumns
            let limit: SceneShadowUse.Limit? = switch shadow.resolutionLimit {
            case .reduced: .reduced
            case .ceiling: family == .directional ? .receiverExtent : .lightFamily
            case nil: nil
            }
            return .init(family: family, face: face, limit: limit)
        }
        for light in shadowLights.prefix(SceneLightSnapshot.maximumLightCount)
            where maps.count < SceneLightSnapshot.maximumLightCount {
            guard let lightID = light.layerID,
                  !bindings.contains(where: { $0.shadow.lightLayerID == lightID }) else { continue }
            let family: SceneShadowUse.Family = switch light {
            case .directional: .directional
            case .point: .point
            case .spot: .spot
            }
            maps.append(.init(family: family, face: nil))
        }
        shadowUse = .active(maps)
    }
}
