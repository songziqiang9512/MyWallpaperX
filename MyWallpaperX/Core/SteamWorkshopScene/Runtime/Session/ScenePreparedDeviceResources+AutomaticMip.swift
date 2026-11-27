import Foundation
import Metal

extension ScenePreparedBaseImageResources {
    struct ImagePlanning {
        let models: Set<String>
        var retainsModelDefaultAliases = false
        var automaticMipConstraints: AutomaticMipConstraints?
        var scalableEffectColorLayerIDs: Set<Int> = []
    }

    struct AutomaticMipConstraints {
        let dynamicLayerIDs: Set<Int>
        let exactSources: Set<SceneTextureLoader.SourceKey>
    }

    struct AutomaticMipTail {
        let use: SceneAutomaticTextureProjection.Source
        let input: SceneResourceView.FileInput
        // A planned dormant source has no uploaded texture to promote.
        var promotionThreshold: Double?
    }

    static func mipPreparationInputs(
        descriptor: SceneRenderDescriptor, drawable: CGSize?, ordinaryColorMipLongEdge: Int?
    ) -> (SceneAutomaticTextureProjection?, Set<Int>) {
        let camera = descriptor.camera
        let automaticProjection = drawable != nil && camera.authoredOrthographicProjectionActive == true
            && camera.default2DInputLayerID == nil ? SceneAutomaticTextureProjection(
                canvasWidth: camera.orthoWidth, canvasHeight: camera.orthoHeight, zoom: camera.generalZoom) : nil
        guard ordinaryColorMipLongEdge != nil || automaticProjection != nil else { return (nil, []) }
        var fullResolutionLayerIDs = SceneNamedTextureDependencyReferenceAnalysis.participatingLayerIDs(
            in: descriptor.layers, includingPotential: true)
        fullResolutionLayerIDs.formUnion(descriptor.materialPasses.lazy.flatMap(\.textureSlots)
            .compactMap { SceneNamedTextureReference.parse($0)?.providerLayerID })
        for layer in descriptor.layers {
            fullResolutionLayerIDs.formUnion(layer.dependencyLayerIDs)
            for dependency in layer.authoredDependencies { fullResolutionLayerIDs.insert(dependency.layerID) }
        }
        return (automaticProjection, fullResolutionLayerIDs)
    }

    static func automaticMipWorldExtent(_ layer: SceneRenderDescriptor.Layer, size: [Float]?) -> SIMD2<Double>? {
        guard layer.usesPerspective != true,
              layer.anglesXYZ?.prefix(2).allSatisfy({ $0 == 0 }) != false else { return nil }
        return SceneAutomaticTextureProjection.worldExtent(size: size ?? layer.renderSizeWH, scale: layer.scaleXYZ)
    }

    typealias AutomaticMipPlan = (source: SceneAutomaticTextureProjection.Source, selection: SceneOrdinaryImageMipSelection)

    static func publishedAutomaticMip(
        _ source: SceneAutomaticTextureProjection.Source,
        entries: [Int: Entry], cover: Double
    ) -> SceneBaseImageTextureLoad.Loaded? {
        for layerID in source.layerIDs {
            guard case let .loaded(loaded)? = entries[layerID]?.outcome,
                  let candidate = loaded.candidate else { continue }
            if candidate.embeddedBaseMip == 0 || source.maximumCoverScale(for: candidate.physicalSize) >= cover {
                return loaded
            }
        }
        return nil
    }

    static func automaticMipPlans(
        _ candidates: [SceneTextureLoader.SourceKey: SceneAutomaticTextureProjection.Source],
        cover: Double?, exactSources: Set<SceneTextureLoader.SourceKey>, constraints: AutomaticMipConstraints?
    ) -> [SceneTextureLoader.SourceKey: AutomaticMipPlan] {
        guard let cover, let constraints else { return [:] }
        return candidates.reduce(into: [:]) { plans, element in
            let (source, use) = element
            guard !exactSources.contains(source), !constraints.exactSources.contains(source),
                  constraints.dynamicLayerIDs.isDisjoint(with: use.layerIDs),
                  let minimum = SceneAutomaticTextureProjection.minimumExtent(worldExtent: use.worldExtent,
                    coverScale: cover) else { return }
            plans[source] = (use, .minimumExtent(minimum))
        }
    }

    static func mipAliasDonors(
        _ layers: [SceneRenderDescriptor.Layer], deferred: Set<Int>, entries: [Int: Entry],
        materials: ScenePreparedImageMaterialCatalog,
        resolver: SceneTexturePathResolver, loader: SceneTextureLoader
    ) throws -> [Int: SceneBaseMaterialLightingProfile] {
        var donors: [Int: SceneBaseMaterialLightingProfile] = [:]
        for layer in layers where layer.contentKind == "image" && !deferred.contains(layer.id) {
            guard let model = layer.imagePath, let entry = entries[layer.id] else { continue }
            donors[layer.id] = try modelDefaultProfile(layer, model: model, entry: entry,
                materials: materials, resolver: resolver, loader: loader)
        }
        return donors
    }

    static func modelDefaultProfile(
        _ layer: SceneRenderDescriptor.Layer, model: String, entry: Entry,
        materials: ScenePreparedImageMaterialCatalog, resolver: SceneTexturePathResolver, loader: SceneTextureLoader
    ) throws -> SceneBaseMaterialLightingProfile? {
        guard let profile = materials.profiles[SceneModelResourceIdentity(model).value],
              layer.puppetMeshPath == nil || !profile.surfaceEnabled else { return nil }
        if layer.staticBaseTexturePath == nil { return profile }
        guard let modelInput = resolver.resolvePrimaryTexture(modelPath: model),
              try (modelInput == entry.input || loader.sourceKey(for: modelInput) == entry.source) else { return nil }
        return profile
    }

    static func keepPublishedAutomaticTails(
        _ plans: [SceneTextureLoader.SourceKey: AutomaticMipPlan], entries: [Int: Entry],
        deferredLayerIDs: Set<Int>, loader: SceneTextureLoader
    ) -> [SceneTextureLoader.SourceKey: AutomaticMipTail] {
        var tails: [SceneTextureLoader.SourceKey: AutomaticMipTail] = [:]
        var textures: [MTLTexture] = []
        for (source, plan) in plans {
            if let deferredID = plan.source.layerIDs.first(where: { deferredLayerIDs.contains($0) }),
               let entry = entries[deferredID] {
                tails[source] = .init(use: plan.source, input: entry.input, promotionThreshold: nil)
            }
            for id in plan.source.layerIDs {
                guard let entry = entries[id], case let .loaded(loaded)? = entry.outcome,
                      let candidate = loaded.candidate else { continue }
                if candidate.embeddedBaseMip > 0 {
                    tails[source] = .init(use: plan.source, input: entry.input,
                        promotionThreshold: plan.source.maximumCoverScale(for: candidate.physicalSize))
                    textures.append(loaded.texture)
                } else { tails[source] = nil }
                break
            }
        }
        // Prepared entries are the shared owner of promotable tails.
        loader.evictTextures(containedIn: textures)
        return tails
    }

    static func prepareAutomaticMipPromotions(
        _ requests: [SceneTextureLoader.SourceKey: AutomaticMipTail], cover: Double,
        loader: SceneTextureLoader, device: MTLDevice, checkCancellation: @escaping () throws -> Void
    ) -> [SceneTextureLoader.SourceKey: SceneBaseImageTextureLoad.Loaded] {
        var updates: [SceneTextureLoader.SourceKey: SceneBaseImageTextureLoad.Loaded] = [:]
        for (source, request) in requests {
            guard let minimum = SceneAutomaticTextureProjection.minimumExtent(
                worldExtent: request.use.worldExtent, coverScale: cover
            ) else { continue }
            do {
                defer { loader.evictDecodedCaches() }
                try checkCancellation()
                guard let prepared = try loader.prepareTexSource(from: request.input,
                        source: source, checkCancellation: checkCancellation),
                      case let .loaded(loaded) = try SceneBaseImageTextureLoad.loadOrdinaryCandidate(
                        from: request.input, loader: loader, device: device, preparedTexSource: prepared,
                        mipSelection: .minimumExtent(minimum), checkCancellation: checkCancellation) else { continue }
                loader.evictTextures(containedIn: [loaded.texture])
                updates[source] = loaded
            } catch is CancellationError { break } catch { continue }
        }
        return updates
    }

#if DEBUG
    static func reportAutomaticMipRetirement(
        entries: [Int: Entry], layerIDs: Dictionary<Int, SceneBaseImageTextureLoad.Loaded>.Keys
    ) {
        guard ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_INITIAL_WINDOW_SCALE"] != nil else { return }
        for layerID in layerIDs {
            guard case let .loaded(old)? = entries[layerID]?.outcome else { continue }
            let texture = old.texture
            let size = "\(texture.width)x\(texture.height)"
            let allocation = texture.allocatedSize
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak texture] in
                NSLog("MWX Scene: phase=automatic-mip-retirement layer=%ld size=%@ bytes=%ld released=%@",
                    layerID, size, allocation, texture == nil ? "true" : "false")
            }
        }
    }
#endif
}
