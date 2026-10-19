import Foundation

/// Bridges an admitted typed producer into launch-only animation demand.
/// Conditions remain in BindingProgram; this projection never evaluates them.
nonisolated enum ScenePuppetAnimationPropertyPreparation {
    nonisolated static func applyingBindings(
        _ program: ScenePropertyBindingProgram,
        report: SceneUserPropertyBindingReport,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        let validated = ScenePropertyBindingProgramValidator().validate(program)
        let definitions = Dictionary(uniqueKeysWithValues:
            validated.definitions.map { ($0.target, $0) })
        let bindingsByPath = Dictionary(grouping: report.bindings, by: \.path)
        let rebuildRequired = Set(program.rebuildRequiredPropertyKeys)
        let layerIndices = Dictionary(grouping: descriptor.layers.indices,
            by: { descriptor.layers[$0].id })
        var prepared = descriptor
        for instruction in validated.instructions {
            guard instruction.valueType == .bool,
                  !rebuildRequired.contains(instruction.propertyKey),
                  let definition = definitions[instruction.target],
                  definition.valueType == .bool,
                  case .bool = definition.authoredValue,
                  let bindings = bindingsByPath[instruction.path], bindings.count == 1,
                  let binding = bindings.first,
                  binding.reference.key == instruction.propertyKey,
                  binding.reference.condition == instruction.condition,
                  case let .puppetAnimationVisibility(layerID, animationLayerID) = binding.target,
                  instruction.target == ScenePuppetAnimationPropertyTarget.visibility(
                    layerID: layerID, animationLayerID: animationLayerID),
                  let indices = layerIndices[layerID], indices.count == 1,
                  let layerIndex = indices.first,
                  prepared.layers[layerIndex].staticModelPath != nil,
                  let animationIndex = animationIndex(in: instruction.path),
                  prepared.layers[layerIndex].puppetAnimationLayers.indices.contains(animationIndex)
            else { continue }
            let layers = prepared.layers[layerIndex].puppetAnimationLayers
            guard layers[animationIndex].id == animationLayerID,
                  layers.filter({ $0.id == animationLayerID }).count == 1,
                  layers[animationIndex].visibilityBinding == nil else { continue }
            prepared.layers[layerIndex].puppetAnimationLayers[animationIndex]
                .visibilityBinding = instruction.propertyKey
            prepared.layers[layerIndex].puppetAnimationLayers[animationIndex]
                .hasPreparedVisibilityProperty = true
        }
        return prepared
    }

    /// Qualified direct consumers only. One unsupported selected resource must
    /// not authorize an atomic property group that could activate bind fallback.
    nonisolated static func visibilityTargets(
        layerID: Int,
        selection: ScenePuppetAnimationSelection
    ) -> Set<SceneDynamicTarget> {
        guard selection.clips.allSatisfy(\.supportsDirectModelChannels) else { return [] }
        return Set(selection.clips.compactMap { clip in
            guard clip.layer.visibilityBinding != nil, let id = clip.layer.id else { return nil }
            return ScenePuppetAnimationPropertyTarget.visibility(
                layerID: layerID, animationLayerID: id)
        })
    }

    private nonisolated static func animationIndex(in path: SceneUserPropertyPath) -> Int? {
        let parts = path.components
        guard parts.count == 5, parts[0] == .key("objects"),
              case let .index(objectIndex) = parts[1], objectIndex >= 0,
              parts[2] == .key("animationlayers"),
              case let .index(animationIndex) = parts[3], animationIndex >= 0,
              parts[4] == .key("visible") else { return nil }
        return animationIndex
    }
}
