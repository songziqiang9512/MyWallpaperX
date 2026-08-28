import Foundation

nonisolated struct SceneScriptScalarFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
}

/// Generic pass-constant SceneScript owners. The program is deliberately
/// source/identity based rather than effect-name based; runtime failure keeps
/// the lower-priority authored/property/Timeline value for the affected owner.
nonisolated final class SceneScriptScalarProgram: @unchecked Sendable {
    let definitions: [SceneDynamicTargetDefinition]
    let bindings: [SceneScriptScalarOwner]
    let domain: SceneScriptQuickJSDomain?
    let generation: UInt64
    private var disabledTargets: Set<SceneDynamicTarget> = []
    private var reportedTargets: Set<SceneDynamicTarget> = []

    private init(
        domain: SceneScriptQuickJSDomain?,
        bindings: [SceneScriptScalarOwner],
        generation: UInt64
    ) {
        self.domain = domain
        self.bindings = bindings
        self.generation = generation
        definitions = bindings.map {
            .init(
                target: $0.target,
                valueType: .scalar,
                authoredValue: .scalar($0.authoredValue)
            )
        }
    }

    static func compile(
        domain sharedDomain: SceneScriptQuickJSDomain? = nil,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        excludedTargets: Set<SceneDynamicTarget> = [],
        generation: UInt64 = 1,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptScalarProgram {
        let domain: SceneScriptQuickJSDomain
        if let sharedDomain {
            domain = sharedDomain
        } else if let created = try? SceneScriptQuickJSDomain(budget: budget) {
            domain = created
        } else {
            return empty(budget: budget, generation: generation)
        }
        let candidates: [(SceneScriptBindingIR, SceneDynamicTarget, Double)] =
            scriptBindings.compactMap { binding in
                guard let target = projection(binding, descriptor: descriptor),
                      !excludedTargets.contains(target),
                      let authored = binding.authoredValue?.numberValue,
                      authored.isFinite else { return nil }
                return (binding, target, authored)
            }
        let counts = Dictionary(grouping: candidates, by: { $0.1 })
            .mapValues(\.count)
        var owners: [SceneScriptScalarOwner] = []
        for (binding, target, authored) in candidates {
            guard counts[target] == 1,
                  let owner = try? SceneScriptScalarOwner(
                      domain: domain,
                      source: binding.source,
                      target: target,
                      authoredValue: authored,
                      generation: generation,
                      budget: budget
                  ) else { continue }
            owners.append(owner)
        }
        return SceneScriptScalarProgram(
            domain: domain,
            bindings: owners,
            generation: generation
        )
    }

    func evaluate(
        inputs: [SceneDynamicTarget: SceneDynamicValue],
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String = "{}",
        interruptBudget: UInt64? = nil
    ) -> SceneScriptScalarFrameResult {
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
        for binding in bindings {
            guard !disabledTargets.contains(binding.target) else { continue }
            guard let input = inputs[binding.target],
                  case let .scalar(value) = input else { continue }
            switch binding.evaluate(
                input: value,
                frame: frame,
                userPropertiesJSON: userPropertiesJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget
            ) {
            case let .success(evaluation):
                values[binding.target] = evaluation.value
                materialFunctionMutations.append(contentsOf: evaluation.materialFunctionMutations)
                if reportedTargets.insert(binding.target).inserted,
                   case let .scalar(inputValue) = input,
                   case let .scalar(outputValue) = evaluation.value {
                    let mutationSummary = evaluation.materialFunctionMutations.map {
                        "\($0.effectIndex):\($0.functionName)"
                    }.joined(separator: ",")
                    NSLog(
                        "MWX SceneScript VM: target=%@ callback=completed input=%.9g output=%.9g mutations=%d mutationTargets=%@ route=generic-only",
                        String(describing: binding.target),
                        inputValue,
                        outputValue,
                        evaluation.materialFunctionMutations.count,
                        mutationSummary
                    )
                }
            case let .failure(failure):
                failures[binding.target] = failure
                disabledTargets.insert(binding.target)
            }
        }
        return .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctionMutations
        )
    }

    func invalidate() {
        bindings.forEach { $0.invalidate() }
    }

    private static func empty(
        budget: SceneScriptScalarBudget,
        generation: UInt64
    ) -> SceneScriptScalarProgram {
        // A domain should only fail construction for a machine-level resource
        // error. Keep the failure local and preserve bounded fallbacks.
        return .init(domain: nil, bindings: [], generation: generation)
    }

    private static func projection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor
    ) -> SceneDynamicTarget? {
        guard binding.owner.kind == .pass,
              binding.properties.isEmpty,
              binding.valueType == .number,
              let authored = binding.authoredValue?.numberValue,
              authored.isFinite,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              let effectIndex = binding.owner.effectIndex,
              let passIndex = binding.owner.passIndex,
              descriptor.layers.indices.contains(objectIndex),
              descriptor.layers[objectIndex].id == layerID,
              descriptor.layers[objectIndex].layerIndex == objectIndex,
              descriptor.layers[objectIndex].effects.indices.contains(effectIndex) else {
            return nil
        }
        let effect = descriptor.layers[objectIndex].effects[effectIndex]
        guard effect.effectID == binding.owner.effectID,
              effect.passes.indices.contains(passIndex) else { return nil }
        let pass = effect.passes[passIndex]
        let name = binding.targetKey
        guard pass.passIndex == passIndex,
              pass.id == binding.owner.passID,
              !name.isEmpty,
              binding.targetPath == expectedPath(
                  objectIndex: objectIndex,
                  effectIndex: effectIndex,
                  passIndex: passIndex,
                  name: name
              ),
              let value = pass.constantShaderValues[name],
              value.scriptSource == binding.source,
              value.components?.count == 1,
              value.components?.first?.bitPattern == authored.bitPattern else {
            return nil
        }
        return .effectConstant(
            layerID: layerID,
            effectIndex: effectIndex,
            passIndex: passIndex,
            name: name
        )
    }

    private static func expectedPath(
        objectIndex: Int,
        effectIndex: Int,
        passIndex: Int,
        name: String
    ) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(objectIndex),
            .key("effects"), .index(effectIndex),
            .key("passes"), .index(passIndex),
            .key("constantshadervalues"), .key(name),
        ]
    }
}
