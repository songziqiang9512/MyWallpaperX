import Foundation
import Metal

extension ScenePreparedBaseImageResources {
    struct ImagePlanning {
        let models: Set<String>
        var retainsModelDefaultAliases = false
        var automaticMipConstraints: AutomaticMipConstraints?
    }

    struct AutomaticMipConstraints {
        let dynamicLayerIDs: Set<Int>
        let exactSources: Set<SceneTextureLoader.SourceKey>
    }

    struct AutomaticMipTail {
        let layerIDs: [Int]
        let input: SceneResourceView.FileInput
        let maximumCoverScale: Double
    }

    static func automaticMipWorldExtent(_ layer: SceneRenderDescriptor.Layer, size: [Float]?) -> SIMD2<Double>? {
        guard layer.usesPerspective != true,
              layer.anglesXYZ?.prefix(2).allSatisfy({ $0 == 0 }) != false else { return nil }
        return SceneAutomaticTextureProjection.worldExtent(size: size ?? layer.renderSizeWH, scale: layer.scaleXYZ)
    }

    typealias AutomaticMipPlan = (source: SceneAutomaticTextureProjection.Source, selection: SceneOrdinaryImageMipSelection)

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

    static func keepPublishedAutomaticTails(
        _ plans: [SceneTextureLoader.SourceKey: AutomaticMipPlan],
        entries: [Int: Entry], loader: SceneTextureLoader
    ) -> [SceneTextureLoader.SourceKey: AutomaticMipTail] {
        var tails: [SceneTextureLoader.SourceKey: AutomaticMipTail] = [:]
        var textures: [MTLTexture] = []
        for (source, plan) in plans {
            for id in plan.source.layerIDs {
                guard let entry = entries[id], case let .loaded(loaded)? = entry.outcome,
                      let candidate = loaded.candidate, candidate.embeddedBaseMip > 0 else { continue }
                tails[source] = .init(layerIDs: plan.source.layerIDs, input: entry.input,
                    maximumCoverScale: plan.source.maximumCoverScale(for: candidate.physicalSize))
                textures.append(loaded.texture)
                break
            }
        }
        // Prepared entries are the shared owner of promotable tails.
        loader.evictTextures(containedIn: textures)
        return tails
    }
}
