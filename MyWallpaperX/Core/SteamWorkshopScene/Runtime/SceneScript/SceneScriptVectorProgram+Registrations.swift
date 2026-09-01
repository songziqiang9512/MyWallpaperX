import Foundation

extension SceneScriptVectorProgram {
    var admittedScaleLayerIDs: Set<Int> {
        Set(bindings.compactMap { binding in
            guard case let .layer(layerID, .scale) = binding.definition.target else {
                return nil
            }
            return layerID
        })
    }

    var animationTargets: Set<SceneDynamicTarget> {
        Set(bindings.compactMap { binding in
            binding.hasCurrentAnimation ? binding.definition.target : nil
        })
    }

    var mediaThumbnailTargets: Set<SceneDynamicTarget> {
        Set(bindings.compactMap { binding in
            binding.handlesMediaThumbnail ? binding.definition.target : nil
        })
    }

    var mediaOwnerTargets: Set<SceneDynamicTarget> {
        Set(mediaOwnerRegistrations.map(\.target))
    }

    var mediaOwnerRegistrations: [SceneScriptMediaOwnerRegistration] {
        bindings.compactMap { binding in
            guard binding.handlesMediaPlayback
                    || binding.handlesMediaProperties
                    || binding.handlesMediaThumbnail
                    || binding.handlesMediaTimeline else { return nil }
            return .init(
                authoredOrdinal: binding.authoredOrdinal,
                target: binding.definition.target,
                family: .vector
            )
        }
    }

    var cursorOwnerRegistrations: [SceneScriptCursorOwnerRegistration] {
        bindings.compactMap { binding in
            let layerID: Int
            switch binding.definition.target {
            case let .layer(value, _), let .text(value, _):
                layerID = value
            default:
                return nil
            }
            guard let authoredOrder = descriptor.layers.firstIndex(where: {
                      $0.id == layerID
                  }) else { return nil }
            return .init(
                layerID: layerID,
                authoredOrder: authoredOrder,
                owner: binding.owner
            )
        }
    }
}
