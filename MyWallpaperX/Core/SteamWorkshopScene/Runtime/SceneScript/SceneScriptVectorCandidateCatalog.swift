import Foundation

nonisolated struct SceneScriptVectorCandidate: Sendable {
    let source: String
    let definition: SceneDynamicTargetDefinition
    let properties: [String: SceneScriptPropertyInput]
    let hasCurrentAnimation: Bool
}

/// Side-effect-free projection of authored Vec2/Vec3 bindings. Pass-owned
/// candidates are only metadata until resolved-material admission identifies
/// an actual consumer; projecting this catalog never evaluates JavaScript.
nonisolated struct SceneScriptVectorCandidateCatalog: Sendable {
    let candidates: [SceneScriptVectorCandidate]
    let duplicateTargets: Set<SceneDynamicTarget>

    static let empty = Self(candidates: [])

    init(candidates: [SceneScriptVectorCandidate]) {
        self.candidates = candidates
        let counts = Dictionary(grouping: candidates, by: { $0.definition.target })
            .mapValues(\.count)
        duplicateTargets = Set(counts.compactMap { target, count in
            count > 1 ? target : nil
        })
    }

    var uniqueCandidates: [SceneScriptVectorCandidate] {
        candidates.filter { !duplicateTargets.contains($0.definition.target) }
    }

    var definitions: [SceneDynamicTargetDefinition] {
        candidates.map(\.definition)
    }

    var targets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.map { $0.definition.target })
    }

    var passTargets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.compactMap { candidate in
            guard case .effectConstant = candidate.definition.target else {
                return nil
            }
            return candidate.definition.target
        })
    }

    var nonPassTargets: Set<SceneDynamicTarget> {
        targets.subtracting(passTargets)
    }

    var animationTargets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.compactMap { candidate in
            candidate.hasCurrentAnimation ? candidate.definition.target : nil
        })
    }

    var admittedScaleLayerIDs: Set<Int> {
        Set(uniqueCandidates.compactMap { candidate in
            guard case let .layer(layerID, .scale) = candidate.definition.target else {
                return nil
            }
            return layerID
        })
    }
}

nonisolated struct SceneScriptVectorPassCompilation: Sendable {
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]

    var failedTargets: Set<SceneDynamicTarget> { Set(failures.keys) }
    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failedTargets)
    }
}

nonisolated struct SceneScriptVectorProgramConstruction: @unchecked Sendable {
    let program: SceneScriptVectorProgram
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]

    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failures.keys)
    }
}

nonisolated extension SceneScriptVectorProgram {
    static func project(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> SceneScriptVectorCandidateCatalog {
        .init(candidates: scriptBindings.compactMap {
            projection(
                $0,
                descriptor: descriptor,
                timelineTargets: timelineTargets
            )
        }.filter { !excludedTargets.contains($0.definition.target) })
    }

    private static func projection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor,
        timelineTargets: Set<SceneDynamicTarget>
    ) -> SceneScriptVectorCandidate? {
        if let candidate = passVectorProjection(binding, descriptor: descriptor) {
            return candidate
        }
        guard binding.owner.kind == .object,
              ["origin", "scale", "angles"].contains(binding.targetKey),
              binding.valueType == .string,
              let sourceValue = binding.authoredValue?.stringValue,
              let authored = vector3(sourceValue),
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              descriptor.layers.indices.contains(objectIndex) else { return nil }
        let layer = descriptor.layers[objectIndex]
        guard layer.id == layerID, layer.layerIndex == objectIndex,
              binding.targetPath == [
                  .key("objects"), .index(objectIndex), .key(binding.targetKey),
              ] else { return nil }
        let descriptorValue: [Float]?
        let target: SceneDynamicTarget
        switch binding.targetKey {
        case "origin":
            descriptorValue = layer.originXYZ
            target = .layer(layerID: layerID, field: .origin)
        case "scale":
            descriptorValue = layer.scaleXYZ
            target = .layer(layerID: layerID, field: .scale)
        case "angles":
            descriptorValue = layer.anglesXYZ
            target = .layer(layerID: layerID, field: .angles)
        default:
            return nil
        }
        let hasCurrentAnimation = timelineTargets.contains(target)
        let validWrapper =
            (binding.wrapperKeys == ["script", "value"] && binding.properties.isEmpty)
            || binding.wrapperKeys == ["script", "scriptproperties", "value"]
            || binding.wrapperKeys == ["script", "scriptproperties", "user", "value"]
            || (binding.wrapperKeys == ["animation", "script", "value"]
                && binding.properties.isEmpty && hasCurrentAnimation)
        guard validWrapper else { return nil }
        guard let descriptorValue, descriptorValue.count == 3,
              Float(authored.x).bitPattern == descriptorValue[0].bitPattern,
              Float(authored.y).bitPattern == descriptorValue[1].bitPattern,
              Float(authored.z).bitPattern == descriptorValue[2].bitPattern else {
            return nil
        }
        var properties: [String: SceneScriptPropertyInput] = [:]
        for entry in binding.properties {
            guard validName(entry.key),
                  let input = propertyInput(entry.value) else { return nil }
            properties[entry.key] = input
        }
        return .init(
            source: binding.source,
            definition: .init(
                target: target,
                valueType: .vector3,
                authoredValue: .vector3(authored.x, authored.y, authored.z)
            ),
            properties: properties,
            hasCurrentAnimation: hasCurrentAnimation
        )
    }

    private static func passVectorProjection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor
    ) -> SceneScriptVectorCandidate? {
        guard binding.owner.kind == .pass,
              binding.valueType == .string,
              let sourceValue = binding.authoredValue?.stringValue,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              let effectIndex = binding.owner.effectIndex,
              let passIndex = binding.owner.passIndex,
              descriptor.layers.indices.contains(objectIndex) else { return nil }
        let layer = descriptor.layers[objectIndex]
        guard layer.id == layerID, layer.layerIndex == objectIndex,
              layer.effects.indices.contains(effectIndex) else { return nil }
        let effect = layer.effects[effectIndex]
        guard effect.effectID == binding.owner.effectID,
              effect.passes.indices.contains(passIndex) else { return nil }
        let pass = effect.passes[passIndex]
        let name = binding.targetKey
        guard pass.passIndex == passIndex, pass.id == binding.owner.passID,
              !name.isEmpty,
              binding.targetPath == passConstantPath(
                  objectIndex: objectIndex, effectIndex: effectIndex,
                  passIndex: passIndex, name: name
              ),
              let descriptorValue = pass.constantShaderValues[name],
              descriptorValue.scriptSource == binding.source else {
            return nil
        }
        let definition: SceneDynamicTargetDefinition
        if let authored = vector2(sourceValue),
           descriptorValue.components?.count == 2,
           descriptorValue.components?[0].bitPattern == authored.x.bitPattern,
           descriptorValue.components?[1].bitPattern == authored.y.bitPattern {
            definition = .init(
                target: .effectConstant(
                    layerID: layerID, effectIndex: effectIndex,
                    passIndex: passIndex, name: name
                ),
                valueType: .vector2,
                authoredValue: .vector2(authored.x, authored.y)
            )
        } else if let authored = vector3(sourceValue),
                  descriptorValue.components?.count == 3,
                  descriptorValue.components?[0].bitPattern == authored.x.bitPattern,
                  descriptorValue.components?[1].bitPattern == authored.y.bitPattern,
                  descriptorValue.components?[2].bitPattern == authored.z.bitPattern {
            definition = .init(
                target: .effectConstant(
                    layerID: layerID, effectIndex: effectIndex,
                    passIndex: passIndex, name: name
                ),
                valueType: .vector3,
                authoredValue: .vector3(authored.x, authored.y, authored.z)
            )
        } else {
            return nil
        }
        let validWrapper =
            (binding.wrapperKeys == ["script", "value"]
                && binding.properties.isEmpty
                && descriptorValue.userValueKind == nil)
            || (binding.wrapperKeys == ["script", "scriptproperties", "value"]
                && descriptorValue.userValueKind == nil)
            || (binding.wrapperKeys == ["script", "scriptproperties", "user", "value"]
                && descriptorValue.userValueKind == .null)
            || (binding.wrapperKeys == ["script", "user", "value"]
                && binding.properties.isEmpty
                && descriptorValue.userValueKind == .null)
        guard validWrapper else { return nil }
        var properties: [String: SceneScriptPropertyInput] = [:]
        for entry in binding.properties {
            guard validName(entry.key),
                  let input = propertyInput(entry.value) else { return nil }
            properties[entry.key] = input
        }
        return .init(
            source: binding.source,
            definition: definition,
            properties: properties,
            hasCurrentAnimation: false
        )
    }
}
