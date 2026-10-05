import Foundation

extension SceneScriptVectorProgram {
    var hasAudioConsumers: Bool {
        bindings.contains(where: { $0.owner.hasAudioRegistration })
    }
    var livePropertyInputTargets: Set<SceneDynamicTarget> {
        bindings.reduce(into: Set<SceneDynamicTarget>()) {
            $0.formUnion($1.livePropertyInputTargets)
        }
    }
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
            guard !binding.owner.exportedCursorEvents.isEmpty else {
                return nil
            }
            let layerID: Int
            switch binding.definition.target {
            case let .layer(value, _), let .text(value, _), let .particle(value, _),
                 let .effectConstant(value, _, _, _),
                 let .materialConstant(value, _, _, _),
                 let .effectVisibility(value, _):
                layerID = value
            default:
                return nil
            }
            guard descriptor.layers.contains(where: {
                      $0.id == layerID
                  }) else { return nil }
            return .init(
                layerID: layerID,
                authoredOrdinal: binding.authoredOrdinal,
                target: binding.definition.target,
                seedValue: binding.definition.authoredValue,
                owner: binding.owner,
                scriptProperties: binding.properties
            )
        }
    }
    func teardown(
        frame: SceneScriptFrameInput,
        effectivePropertyValues: [String: SceneUserPropertyValue],
        userPropertiesJSON: String
    ) -> [SceneScriptOwnerTeardownOutcome] {
        bindings.map { binding in
            let propertiesJSON =
                SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                binding.properties,
                effectiveValues: effectivePropertyValues
            ) ?? ""
            return binding.owner.teardown(
                frame: frame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userPropertiesJSON
            )
        }
    }
}
