import Foundation

nonisolated struct SceneScriptVectorFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
}

nonisolated enum SceneScriptHostValue: Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case vector3(Double, Double, Double)

    var jsonObject: Any {
        switch self {
        case let .bool(value): value
        case let .number(value): value
        case let .string(value): value
        case let .vector3(x, y, z): ["x": x, "y": y, "z": z]
        }
    }
}

nonisolated struct SceneScriptPropertyInput: Equatable, Sendable {
    let fallback: SceneScriptHostValue
    let userPropertyKey: String?

    func resolve(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> SceneScriptHostValue? {
        guard let userPropertyKey,
              let live = effectiveValues[userPropertyKey] else { return fallback }
        switch (fallback, live) {
        case (_, .number(let value)) where !value.isFinite:
            return nil
        case (.number, .number(let value)):
            return .number(value)
        case (.bool, .bool(let value)):
            return .bool(value)
        case (.string, .string(let value)):
            return .string(value)
        default:
            return nil
        }
    }
}

nonisolated struct SceneScriptVectorBinding: @unchecked Sendable {
    let definition: SceneDynamicTargetDefinition
    let properties: [String: SceneScriptPropertyInput]
    let hasCurrentAnimation: Bool
    let owner: SceneScriptVectorOwner
}

/// Generic object-property Vec3 VM route. Admission is based only on the
/// loss-preserving binding owner/path/type and descriptor identity. JavaScript
/// semantics remain owned by QuickJS; there is no source-shape interpreter.
nonisolated final class SceneScriptVectorProgram: @unchecked Sendable {
    let definitions: [SceneDynamicTargetDefinition]
    let bindings: [SceneScriptVectorBinding]
    let domain: SceneScriptQuickJSDomain?
    let generation: UInt64
    private let descriptor: SceneRenderDescriptor
    private let userPropertyKinds: [String: SceneUserPropertyKind]
    private var disabledTargets: Set<SceneDynamicTarget> = []
    private var reportedTargets: Set<SceneDynamicTarget> = []

    private init(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        bindings: [SceneScriptVectorBinding],
        generation: UInt64,
        userPropertyDefinitions: [SceneUserPropertyDefinition]
    ) {
        self.domain = domain
        self.descriptor = descriptor
        self.bindings = bindings
        self.generation = generation
        definitions = bindings.map(\.definition)
        userPropertyKinds = Dictionary(
            uniqueKeysWithValues: userPropertyDefinitions.map { ($0.key, $0.kind) }
        )
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

    static func compile(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        userPropertyDefinitions: [SceneUserPropertyDefinition],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = [],
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptVectorProgram {
        guard let domain else {
            return .init(
                domain: nil, descriptor: descriptor,
                bindings: [], generation: generation,
                userPropertyDefinitions: userPropertyDefinitions
            )
        }
        guard (try? domain.configureLayerCatalog(descriptor)) != nil else {
            return .init(
                domain: nil, descriptor: descriptor,
                bindings: [], generation: generation,
                userPropertyDefinitions: userPropertyDefinitions
            )
        }
        let candidates = scriptBindings.compactMap {
            projection(
                $0,
                descriptor: descriptor,
                timelineTargets: timelineTargets
            )
        }.filter { !excludedTargets.contains($0.definition.target) }
        let counts = Dictionary(grouping: candidates, by: { $0.definition.target })
            .mapValues(\.count)
        let bindings = candidates.compactMap { candidate -> SceneScriptVectorBinding? in
            guard counts[candidate.definition.target] == 1,
                  case let .layer(layerID, _) = candidate.definition.target,
                  let layer = descriptor.layers.first(where: { $0.id == layerID }),
                  let owner = try? SceneScriptVectorOwner(
                      domain: domain,
                      source: candidate.source,
                      target: candidate.definition.target,
                      effectNames: layer.effects.map(\.name),
                      hasCurrentAnimation: candidate.hasCurrentAnimation,
                      generation: generation,
                      budget: budget
                  ) else { return nil }
            return .init(
                definition: candidate.definition,
                properties: candidate.properties,
                hasCurrentAnimation: candidate.hasCurrentAnimation,
                owner: owner
            )
        }.sorted {
            String(describing: $0.definition.target)
                < String(describing: $1.definition.target)
        }
        return .init(
            domain: domain, descriptor: descriptor,
            bindings: bindings,
            generation: generation,
            userPropertyDefinitions: userPropertyDefinitions
        )
    }

    func evaluate(
        inputs: [SceneDynamicTarget: SceneDynamicValue],
        effectivePropertyValues: [String: SceneUserPropertyValue],
        frame: SceneScriptFrameInput,
        layerSnapshot: SceneDynamicSnapshot? = nil,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptVectorFrameResult {
        let userJSON = userPropertiesJSON(
            effectiveValues: effectivePropertyValues
        )
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
        var animationMutations: [SceneTimelinePlaybackMutation] = []
        if let domain {
            do {
                try domain.publishLayerSnapshot(
                    layerSnapshot ?? .empty(frameIndex: 0),
                    descriptor: descriptor
                )
            } catch let failure as SceneScriptScalarRuntimeFailure {
                for binding in bindings {
                    failures[binding.definition.target] = failure
                }
                return .init(
                    values: [:], failures: failures,
                    materialFunctionMutations: [],
                    animationMutations: []
                )
            } catch {
                for binding in bindings {
                    failures[binding.definition.target] = .invalidArgument(
                        String(describing: error)
                    )
                }
                return .init(
                    values: [:], failures: failures,
                    materialFunctionMutations: [],
                    animationMutations: []
                )
            }
        }
        for binding in bindings {
            let target = binding.definition.target
            guard !disabledTargets.contains(target),
                  let input = inputs[target],
                  case let .vector3(x, y, z) = input,
                  let propertiesJSON = Self.scriptPropertiesJSON(
                      binding.properties,
                      effectiveValues: effectivePropertyValues
                  ) else { continue }
            switch binding.owner.evaluate(
                input: SIMD3(x, y, z),
                frame: frame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget
            ) {
            case let .success(evaluation):
                let value = evaluation.value
                values[target] = value
                materialFunctionMutations.append(
                    contentsOf: evaluation.materialFunctionMutations
                )
                animationMutations.append(contentsOf: evaluation.animationMutations)
                if reportedTargets.insert(target).inserted,
                   case let .vector3(outputX, outputY, outputZ) = value {
                    NSLog(
                        "MWX SceneScript VM: target=%@ callback=completed type=Vec3 input=(%.9g,%.9g,%.9g) output=(%.9g,%.9g,%.9g) route=generic-only",
                        String(describing: target),
                        x, y, z,
                        outputX, outputY, outputZ
                    )
                }
            case let .failure(failure):
                failures[target] = failure
                disabledTargets.insert(target)
            }
        }
        return .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctionMutations,
            animationMutations: animationMutations
        )
    }

    func userPropertiesJSON(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> String {
        Self.userPropertiesJSON(
            values: effectiveValues,
            kinds: userPropertyKinds
        )
    }

    func invalidate() {
        bindings.forEach { $0.owner.invalidate() }
    }

    private struct Candidate {
        let source: String
        let definition: SceneDynamicTargetDefinition
        let properties: [String: SceneScriptPropertyInput]
        let hasCurrentAnimation: Bool
    }

    private static func projection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor,
        timelineTargets: Set<SceneDynamicTarget>
    ) -> Candidate? {
        guard binding.owner.kind == .object,
              binding.targetKey == "origin" || binding.targetKey == "scale",
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

    private static func propertyInput(
        _ value: SceneJSONValue
    ) -> SceneScriptPropertyInput? {
        if let fallback = hostValue(value) {
            return .init(fallback: fallback, userPropertyKey: nil)
        }
        guard case let .object(wrapper) = value,
              wrapper.keys.sorted() == ["user", "value"],
              case let .string(key)? = wrapper["user"], validName(key),
              let fallbackValue = wrapper["value"],
              let fallback = hostValue(fallbackValue) else { return nil }
        return .init(fallback: fallback, userPropertyKey: key)
    }

    private static func hostValue(_ value: SceneJSONValue) -> SceneScriptHostValue? {
        switch value {
        case let .number(number) where number.isFinite: .number(number)
        case let .bool(value): .bool(value)
        case let .string(value): .string(value)
        default: nil
        }
    }

    private static func vector3(_ value: String) -> SIMD3<Double>? {
        let parts = value.split { $0.isWhitespace || $0 == "," }
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == 3, numbers.allSatisfy(\.isFinite) else { return nil }
        return .init(numbers[0], numbers[1], numbers[2])
    }

    private static func validName(_ value: String) -> Bool {
        !value.isEmpty && value != "__proto__" && value.utf8.count <= 256
    }

    private static func scriptPropertiesJSON(
        _ inputs: [String: SceneScriptPropertyInput],
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> String? {
        if inputs.isEmpty { return "" }
        var object: [String: Any] = [:]
        for (key, input) in inputs {
            guard let value = input.resolve(effectiveValues: effectiveValues) else {
                return nil
            }
            object[key] = value.jsonObject
        }
        return json(object)
    }

    private static func userPropertiesJSON(
        values: [String: SceneUserPropertyValue],
        kinds: [String: SceneUserPropertyKind]
    ) -> String {
        let object = values.reduce(into: [String: Any]()) { result, entry in
            guard validName(entry.key) else { return }
            switch (kinds[entry.key], entry.value) {
            case (.color, .string(let value)):
                if let color = vector3(value) {
                    result[entry.key] = SceneScriptHostValue.vector3(
                        color.x, color.y, color.z
                    ).jsonObject
                }
            case (_, .number(let value)) where value.isFinite:
                result[entry.key] = value
            case (_, .bool(let value)):
                result[entry.key] = value
            case (_, .string(let value)):
                result[entry.key] = value
            default:
                break
            }
        }
        return json(object) ?? "{}"
    }

    private static func json(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
