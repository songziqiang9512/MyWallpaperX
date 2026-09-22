import Foundation

extension SceneScriptVectorProgram {
    /// Installs launch-prepared Puppet rig identity into matching owners. The
    /// owner remains the sole QuickJS mutation journal; this is only a
    /// launch-time snapshot and performs no sample-specific dispatch.
    @discardableResult
    func configurePuppetBones(
        layerID: Int,
        worldMatrices: [Double],
        localMatrices: [Double],
        names: [String],
        parents: [Int32]? = nil,
        layerToWorld: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    ) throws -> Bool {
        var configured = false
        for binding in bindings {
            guard SceneScriptLayerMutationBridge.layerID(
                for: binding.definition.target
            ) == layerID else { continue }
            try binding.owner.configurePuppetBones(
                layerID: layerID,
                worldMatrices: worldMatrices,
                localMatrices: localMatrices,
                names: names, parents: parents, layerToWorld: layerToWorld
            )
            configured = true
        }
        return configured
    }

    var hasAudioConsumers: Bool {
        bindings.contains(where: { $0.owner.hasAudioRegistration })
    }
    var requiresSharedFrameTransaction: Bool {
        bindings.contains(where: \.requiresStatefulOwner)
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
