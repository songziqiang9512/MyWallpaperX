import Foundation
import Metal

extension SceneMetalView {
    /// Direct geometry joins the same layer registry and launch playback clock.
    /// Every surface allocates its own storage from immutable preparation.
    func installDirectModelAnimations() {
        guard let pipeline = renderer.staticModelResources.pipeline else { return }
        for layer in renderer.renderDescriptor.layers where layer.staticModelPath != nil {
            guard let animation = renderer.staticModelResources.animation(for: layer.id),
                  let entries = renderer.staticModelResources[layer.id], entries.count == 1 else { continue }
            switch ScenePuppetPlaybackState.makeDirectModel(layerID: layer.id,
                vertices: animation.vertices, mesh: entries[0].mesh,
                evaluator: animation.evaluator, selection: animation.selection,
                attachments: animation.attachments, pipeline: pipeline) {
            case .success(let state):
                guard case .success = puppetAnimationPlaybackRuntime.register(
                    layerID: layer.id, selection: state.selection,
                    authoredLayers: layer.puppetAnimationLayers) else { continue }
                puppetPlaybackStates[layer.id] = state
#if DEBUG
                let unconsumedRate = state.selection.clips.contains {
                    $0.layer.hasRateScript == true || $0.layer.rateBinding != nil
                }
                NSLog("MWX Scene model-animation layer=%d state=prepared clips=%d rateSource=%@",
                    layer.id, state.selection.clips.count,
                    unconsumedRate ? "authored-fallback-dynamic-source-unconsumed" : "authored-static")
#endif
            case .failure(let failure):
#if DEBUG
                NSLog("MWX Scene model-animation layer=%d state=bind-only reason=%@",
                    layer.id, String(describing: failure))
#endif
            }
        }
    }

    /// Source and dynamic layers share the same instance allocator, clipping
    /// domain, animation registration and geometry publication contract.
    func instantiatePuppetGeometry(
        for layer: SceneRenderDescriptor.Layer,
        pose: ScenePuppetLayerLoad.PreparedPose,
        atlasTexture: MTLTexture,
        resources: ScenePreparedBaseImageResources,
        resolver: SceneTexturePathResolver
    ) -> ScenePuppetLayerLoad.Outcome? {
        guard let imagePipeline else { return nil }
        let loader = resources.textureLoader
        let clippingPipeline = ScenePipelineSlot<MTLRenderPipelineState> { [metalDevice] in
            ScenePuppetClipping.makePipeline(device: metalDevice)
        }
        let clippingDomain = UUID()
        guard let outcome = ScenePuppetLayerLoad.preparedGeometry(
            for: layer, preparedPose: pose, atlasTexture: atlasTexture,
            device: metalDevice, pipeline: imagePipeline,
            clippingPipeline: { clippingPipeline.resolve() },
            loadClippingMask: { [metalDevice] name in
                guard let url = resolver.resolveTextureFile(named: name),
                      case let .loaded(texture) = loader.loadDataTexture(from: url, device: metalDevice)
                else { return nil }
                return texture
            },
            allocateClippingMask: { [offscreenTexturePool] clip, width, height, commandBuffer in
                guard let target = offscreenTexturePool.reservePuppetClipping(
                    layerID: layer.id, clipID: clip, domain: clippingDomain,
                    width: width, height: height, commandBuffer: commandBuffer) else { return nil }
                let pin = target.pin
                return .init(texture: target.texture, release: { pin.release() })
            }) else { return nil }
        if let playback = outcome.playback,
           case let .failure(failure) = puppetAnimationPlaybackRuntime.register(
               layerID: layer.id, selection: playback.selection,
               authoredLayers: layer.puppetAnimationLayers) {
#if DEBUG
            NSLog("MWX Puppet: layer=%d animation definition rejected: %@",
                layer.id, String(describing: failure))
#endif
            return .init(geometryProduct: nil, playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: "puppet animation definition rejected")
        }
        return outcome
    }

    /// Revision-only reconciliation consumes the original committed topology.
    /// Failed allocations stay local; no atlas is published as a complete quad.
    func synchronizeDynamicPuppets(_ topology: SceneScriptLayerTopologySnapshot) {
        guard dynamicPuppetTopologyRevision != topology.topologyRevision,
              let resources = preparedBaseImages, let resourceView = puppetResourceView else { return }
        let layers = topology.dynamicLayers.filter { $0.puppetMeshPath != nil }
        let live = Set(layers.map(\.id))
        let retired = dynamicPuppetLayerIDs.subtracting(live)
        for layerID in retired {
            puppetPlaybackStates.removeValue(forKey: layerID)
            imageTextures[layerID] = nil
        }
        let resolver = SceneTexturePathResolver(resourceView: resourceView,
            descriptor: renderer.renderDescriptor)
        for layer in layers where !dynamicPuppetLayerIDs.contains(layer.id) {
            guard let model = layer.imagePath,
                  let resource = resources.dynamicImageResources[model.lowercased()],
                  let mesh = resource.puppetMeshPath,
                  mesh.caseInsensitiveCompare(layer.puppetMeshPath ?? "") == .orderedSame,
                  let pose = resource.puppetPose,
                  let outcome = instantiatePuppetGeometry(for: layer, pose: pose,
                      atlasTexture: resource.loaded.texture, resources: resources, resolver: resolver),
                  let product = outcome.geometryProduct else { continue }
            imageTextures.setPuppetGeometry(product, samplingAtlas: resource.loaded.texture,
                samplingCandidate: resource.loaded.candidate, layerID: layer.id)
            puppetPlaybackStates[layer.id] = outcome.playback
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                NSLog("MWX DEBUG SCENE: phase=dynamic-puppet layer=%d state=ready playback=%d geometry=%@",
                    layer.id, outcome.playback != nil ? 1 : 0, outcome.message)
            }
#endif
        }
        dynamicPuppetLayerIDs = live
        dynamicPuppetTopologyRevision = topology.topologyRevision
    }
}
