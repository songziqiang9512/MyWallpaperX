import Foundation
import Metal

extension SceneDesktopWallpaperSession.Surface {
    var preparedDirectModelAnimationVisibilityTargets: Set<SceneDynamicTarget> {
        puppetPlaybackStates.reduce(into: []) { targets, entry in
            guard entry.value.isDirectModel else { return }
            targets.formUnion(ScenePuppetAnimationPropertyPreparation.visibilityTargets(
                layerID: entry.key, selection: entry.value.selection))
        }
    }

    func installDirectModelAnimations(
        playbackRuntime: ScenePuppetAnimationPlaybackRuntime,
        destroyedAuthoredLayerIDs: Set<Int>
    ) {
        let resources = metalView.renderer.staticModelResources
        guard let pipeline = resources.pipeline else { return }
        for layer in metalView.renderer.renderDescriptor.layers
        where layer.staticModelPath != nil && !destroyedAuthoredLayerIDs.contains(layer.id) {
            guard let animation = resources.animation(for: layer.id),
                  let entries = resources[layer.id], entries.count == 1 else { continue }
            let state: ScenePuppetPlaybackState
            switch ScenePuppetPlaybackState.makeDirectModel(layerID: layer.id,
                vertices: animation.vertices, evaluator: animation.evaluator,
                selection: animation.selection, attachments: animation.attachments) {
            case let .success(value): state = value
            case let .failure(failure):
#if DEBUG
                NSLog("MWX Scene model-animation layer=%d state=bind-only reason=%@",
                    layer.id, String(describing: failure))
#endif
                continue
            }
            let geometry: ScenePuppetMeshGeometry
            switch ScenePuppetMeshGeometry.prepareDirectModel(layerID: layer.id,
                vertices: animation.vertices, mesh: entries[0].mesh,
                pipeline: pipeline, selection: animation.selection) {
            case let .success(value): geometry = value
            case let .failure(failure):
#if DEBUG
                NSLog("MWX Scene model-animation layer=%d state=bind-only reason=%@",
                    layer.id, "direct model vertex stream: \(failure.rawValue)")
#endif
                continue
            }
            guard case .success = playbackRuntime.register(
                layerID: layer.id, selection: state.selection,
                authoredLayers: layer.puppetAnimationLayers) else { continue }
            puppetPlaybackStates[layer.id] = state
            metalView.puppetGeometries[layer.id] = geometry
#if DEBUG
            let unconsumedRate = state.selection.clips.contains {
                $0.layer.hasRateScript == true || $0.layer.rateBinding != nil
            }
            NSLog("MWX Scene model-animation layer=%d state=prepared clips=%d rateSource=%@",
                layer.id, state.selection.clips.count,
                unconsumedRate ? "authored-fallback-dynamic-source-unconsumed" : "authored-static")
#endif
        }
    }

    func instantiatePuppetGeometry(
        for layer: SceneRenderDescriptor.Layer,
        pose: ScenePuppetLayerLoad.PreparedPose,
        atlasTexture: MTLTexture,
        preparedResources: ScenePreparedDeviceResources,
        playbackRuntime: ScenePuppetAnimationPlaybackRuntime
    ) -> ScenePuppetMeshGeometry.Outcome {
        let asset: ScenePuppetLayerLoad.PreparedAsset
        let evaluated: (ScenePuppetAnimationSelection, ScenePuppetAnimationEvaluator,
                        ScenePuppetLayerLoad.PreparedPose.PlaybackKind)?
        var fallbackMessage: String?
        switch pose.geometry {
        case let .unavailable(allowsMissing, message):
            return .init(geometryProduct: nil, allowsMissingMeshTextureProduct: allowsMissing,
                message: message)
        case let .bind(value, message):
            asset = value
            evaluated = nil
            fallbackMessage = message
        case let .evaluated(value, selection, evaluator, kind, message):
            asset = value
            evaluated = (selection, evaluator, kind)
            fallbackMessage = message
        }
        let clippingResources = preparedResources.baseImages.puppetClipping[asset.meshPath.lowercased()]
#if DEBUG
        for index in asset.mesh.clipRecords.indices where clippingResources?.paintTextures[index] == nil {
            NSLog("MWX Puppet: layer=%d clip=%d mask unavailable; target part hidden", layer.id, index)
        }
#endif
        guard clippingResources?.readFailed != true else {
            return .init(geometryProduct: nil, allowsMissingMeshTextureProduct: false,
                message: "puppet clipping source read failed")
        }
        let clipping: ScenePuppetClipping?
        if asset.mesh.clipRecords.isEmpty {
            clipping = nil
        } else {
            let domain = UUID()
            let layerID = layer.id
            let pool = metalView.offscreenTexturePool
            clipping = ScenePuppetClipping(mesh: asset.mesh,
                pipeline: preparedResources.pipelineRepository.puppetClipping,
                paintTextures: clippingResources?.paintTextures ?? [:],
                allocate: { clip, width, height, commandBuffer in
                    guard let target = pool.reservePuppetClipping(layerID: layerID,
                        clipID: clip, domain: domain, width: width, height: height,
                        commandBuffer: commandBuffer) else { return nil }
                    let pin = target.pin
                    return .init(texture: target.texture, release: { pin.release() })
                })
        }
        let size = layer.renderSizeWH ?? []
        let width = size.first ?? 0
        let height = size.count > 1 ? size[1] : 0
        if let (selection, evaluator, kind) = evaluated {
            switch ScenePuppetMeshGeometry.prepare(layerID: layer.id, mesh: asset.mesh,
                atlasTexture: atlasTexture, layerWidth: width, layerHeight: height,
                device: metalView.metalDevice, pipeline: preparedResources.imageLayerPipeline,
                clipping: clipping, animated: true) {
            case let .success(output):
                let state = ScenePuppetPlaybackState.make(layerID: layer.id, mesh: asset.mesh,
                    evaluator: evaluator, selection: selection, attachments: asset.attachments)
                if case let .failure(failure) = playbackRuntime.register(layerID: layer.id,
                    selection: selection, authoredLayers: layer.puppetAnimationLayers) {
#if DEBUG
                    NSLog("MWX Puppet: layer=%d animation definition rejected: %@",
                        layer.id, String(describing: failure))
#endif
                    return .init(geometryProduct: nil, allowsMissingMeshTextureProduct: false,
                        message: "puppet animation definition rejected")
                }
                puppetPlaybackStates[layer.id] = state
                metalView.puppetGeometries[layer.id] = output.geometry
                let message: String
                switch kind {
                case .animation:
                    message = String(format: "puppet world geometry OK %@ mode=%@ ids=%@ clips=%d verts=%d tris=%d",
                        asset.mesh.version, selection.composition.rawValue,
                        selection.clips.map { String($0.animation.id) }.joined(separator: ","),
                        selection.clips.count, asset.mesh.vertices.count, asset.mesh.triangleCount)
                case .reference: message = "puppet reference world geometry prepared"
                case .script: message = "puppet script world geometry prepared"
                }
                return .init(geometryProduct: output.product, allowsMissingMeshTextureProduct: false,
                    message: message + (fallbackMessage.map { "; " + $0 } ?? ""))
            case let .failure(failure):
                fallbackMessage = (fallbackMessage.map { $0 + "; " } ?? "")
                    + "\(kind.failurePrefix): \(failure.description)"
            }
        }
        switch ScenePuppetMeshGeometry.prepare(layerID: layer.id, mesh: asset.mesh,
            atlasTexture: atlasTexture, layerWidth: width, layerHeight: height,
            device: metalView.metalDevice, pipeline: preparedResources.imageLayerPipeline,
            clipping: clipping) {
        case let .success(output):
            metalView.puppetGeometries[layer.id] = output.geometry
            return .init(geometryProduct: output.product, allowsMissingMeshTextureProduct: false,
                message: String(format: "puppet bind-pose world geometry OK %@ stride=%d verts=%d tris=%d",
                    asset.mesh.version, asset.mesh.vertexStride, output.vertexCount, output.triangleCount)
                    + (fallbackMessage.map { "; " + $0 } ?? ""))
        case let .failure(failure):
            return .init(geometryProduct: nil, allowsMissingMeshTextureProduct: false,
                message: "puppet geometry preparation failed: \(failure.description) (\(layer.puppetMeshPath ?? "unknown"))"
                    + (fallbackMessage.map { "; " + $0 } ?? ""))
        }
    }

    func synchronizeDynamicPuppets(
        _ topology: SceneScriptLayerTopologySnapshot,
        preparedResources: ScenePreparedDeviceResources,
        playbackRuntime: ScenePuppetAnimationPlaybackRuntime
    ) {
        guard dynamicPuppetTopologyRevision != topology.topologyRevision else { return }
        let layers = topology.dynamicLayers.filter { $0.puppetMeshPath != nil }
        let live = Set(layers.map(\.id))
        let retired = dynamicPuppetLayerIDs.subtracting(live).union(
            topology.destroyedAuthoredLayerIDs.filter {
                puppetPlaybackStates[$0] != nil || metalView.puppetGeometries[$0] != nil
            })
        for layerID in retired {
            puppetPlaybackStates.removeValue(forKey: layerID)
            metalView.puppetGeometries.removeValue(forKey: layerID)
            metalView.imageTextures[layerID] = nil
        }
        for layer in layers where !dynamicPuppetLayerIDs.contains(layer.id) {
            guard let model = layer.imagePath,
                  let resource = preparedResources.baseImages.dynamicImageResources[model.lowercased()],
                  case let .image(candidate) = resource.product,
                  let mesh = resource.puppetMeshPath,
                  mesh.caseInsensitiveCompare(layer.puppetMeshPath ?? "") == .orderedSame,
                  let pose = resource.puppetPose else { continue }
            let outcome = instantiatePuppetGeometry(for: layer, pose: pose,
                atlasTexture: candidate.texture, preparedResources: preparedResources,
                playbackRuntime: playbackRuntime)
            guard let product = outcome.geometryProduct else { continue }
            metalView.imageTextures.setPuppetGeometry(product, samplingAtlas: candidate.texture,
                samplingCandidate: candidate, layerID: layer.id)
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                NSLog("MWX DEBUG SCENE: phase=dynamic-puppet layer=%d state=ready playback=%d geometry=%@",
                    layer.id, puppetPlaybackStates[layer.id] != nil ? 1 : 0, outcome.message)
            }
#endif
        }
        dynamicPuppetLayerIDs = live
        dynamicPuppetTopologyRevision = topology.topologyRevision
    }
}
