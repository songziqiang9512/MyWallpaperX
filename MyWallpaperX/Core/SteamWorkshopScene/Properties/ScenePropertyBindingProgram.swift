import Foundation

nonisolated struct ScenePropertyBindingInstruction: Codable, Equatable {
    let propertyKey: String
    let path: SceneUserPropertyPath
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType
    let condition: SceneUserPropertyValue?

    nonisolated init(
        propertyKey: String,
        path: SceneUserPropertyPath,
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType,
        condition: SceneUserPropertyValue? = nil
    ) {
        self.propertyKey = propertyKey
        self.path = path
        self.target = target
        self.valueType = valueType
        self.condition = condition
    }
}

nonisolated struct ScenePropertyBindingProgram: Codable, Equatable {
    let definitions: [SceneDynamicTargetDefinition]
    let instructions: [ScenePropertyBindingInstruction]
    /// Full authored Combo domains for admitted conditional layer groups.
    /// Keeping unused options is necessary because an option may intentionally
    /// hide every conditional layer in the group.
    let conditionalValueDomainsByPropertyKey: [String: [String]]
    let rebuildRequiredPropertyKeys: [String]

    nonisolated init(
        definitions: [SceneDynamicTargetDefinition],
        instructions: [ScenePropertyBindingInstruction],
        conditionalValueDomainsByPropertyKey: [String: [String]] = [:],
        rebuildRequiredPropertyKeys: [String] = []
    ) {
        self.definitions = definitions
        self.instructions = instructions
        self.conditionalValueDomainsByPropertyKey =
            conditionalValueDomainsByPropertyKey
        self.rebuildRequiredPropertyKeys = Array(Set(rebuildRequiredPropertyKeys)).sorted()
    }

    nonisolated func evaluate(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> ScenePropertyBindingEvaluation {
        let validation = ScenePropertyBindingProgramValidator().validate(self)
        let definitionsByTarget = Dictionary(
            uniqueKeysWithValues: validation.definitions.map { ($0.target, $0) }
        )
        var userValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var diagnostics = validation.diagnostics

        for instruction in validation.instructions {
            guard let value = effectiveValues[instruction.propertyKey] else {
                diagnostics.append(.runtime(
                    code: .missingEffectiveValue,
                    instruction: instruction,
                    message: "属性没有有效值。"
                ))
                continue
            }
            let conversion: Result<SceneDynamicValue, ValueError>
            if let condition = instruction.condition {
                if instruction.valueType == .bool,
                   case let .string(value) = value,
                   case let .string(condition) = condition {
                    conversion = .success(.bool(value == condition))
                } else {
                    conversion = .failure(.typeMismatch)
                }
            } else {
                conversion = Self.convert(value, as: instruction.valueType)
            }
            switch conversion {
            case let .success(dynamicValue):
                guard definitionsByTarget[instruction.target]?
                    .acceptsUserPropertyValue(dynamicValue) == true else {
                    diagnostics.append(.runtime(
                        code: .invalidRuntimeValue,
                        instruction: instruction,
                        message: "属性值超出作者声明的数值域。"
                    ))
                    continue
                }
                userValues[instruction.target] = dynamicValue
            case let .failure(error):
                diagnostics.append(.runtime(
                    code: error.runtimeCode,
                    instruction: instruction,
                    message: error.runtimeMessage
                ))
            }
        }

        let conditionalGroups = Dictionary(
            grouping: validation.instructions.filter { $0.condition != nil },
            by: \.propertyKey
        )
        for (propertyKey, instructions) in conditionalGroups {
            let allTargetsResolved = instructions.allSatisfy {
                userValues[$0.target] != nil
            }
            let hasValidSelection: Bool
            if let domain = conditionalValueDomainsByPropertyKey[propertyKey] {
                hasValidSelection = {
                    guard case let .string(selected)? = effectiveValues[propertyKey],
                          domain.contains(selected) else { return false }
                    return instructions.allSatisfy { instruction in
                        guard case let .string(condition)? = instruction.condition,
                              domain.contains(condition),
                              case let .bool(isVisible)? = userValues[instruction.target]
                        else { return false }
                        return isVisible == (selected == condition)
                    }
                }()
            } else {
                // Preserve decode/runtime compatibility for older exact
                // one-layer-per-option programs that predate domain capture.
                hasValidSelection = instructions.reduce(into: 0) {
                    count, instruction in
                    guard case .bool(true)? = userValues[instruction.target]
                    else { return }
                    count += 1
                } == 1
            }
            guard allTargetsResolved, hasValidSelection else {
                instructions.forEach { userValues.removeValue(forKey: $0.target) }
                if let instruction = instructions.first {
                    diagnostics.append(.runtime(
                        code: .invalidRuntimeValue,
                        instruction: instruction,
                        message: "Combo 图层选择必须命中声明域并原子解析完整图层组。"
                    ))
                }
                continue
            }
        }

        return ScenePropertyBindingEvaluation(
            userValues: userValues,
            diagnostics: diagnostics.sorted(by: ScenePropertyBindingDiagnostic.areInIncreasingOrder)
        )
    }

    /// Exact direct bool producers that may keep an authored effect stage in
    /// the launch graph while its current property value is false. The
    /// validated binding program remains the only property identity owner.
    nonisolated var directBoolEffectVisibilityTargets: Set<SceneDynamicTarget> {
        let validation = ScenePropertyBindingProgramValidator().validate(self)
        let definitions = Dictionary(
            uniqueKeysWithValues: validation.definitions.map { ($0.target, $0) }
        )
        let instructionsByPropertyKey = Dictionary(
            grouping: validation.instructions,
            by: \.propertyKey
        )
        let rebuildRequired = Set(rebuildRequiredPropertyKeys)
        return Set(validation.instructions.compactMap { instruction in
            guard instruction.valueType == .bool,
                  instruction.condition == nil,
                  instructionsByPropertyKey[instruction.propertyKey]?.count == 1,
                  !rebuildRequired.contains(instruction.propertyKey),
                  case .effectVisibility = instruction.target,
                  let definition = definitions[instruction.target],
                  definition.valueType == .bool,
                  case .bool = definition.authoredValue else { return nil }
            return instruction.target
        })
    }

    /// Exact direct-bool effect targets that may transfer an already-active
    /// stage candidate to the shared Program route. One property may fan out
    /// to multiple visibility targets, but it may not mix target kinds or
    /// value types; launch route admission further limits lifecycle ownership.
    nonisolated var effectLocalDirectBoolEffectVisibilityTargets:
        Set<SceneDynamicTarget> {
        let validation = ScenePropertyBindingProgramValidator().validate(self)
        guard validation.diagnostics.isEmpty else { return [] }
        let definitions = Dictionary(
            uniqueKeysWithValues: validation.definitions.map { ($0.target, $0) }
        )
        let instructionsByPropertyKey = Dictionary(
            grouping: validation.instructions,
            by: \.propertyKey
        )
        let rebuildRequired = Set(rebuildRequiredPropertyKeys)
        return Set(validation.instructions.compactMap { instruction in
            let siblings = instructionsByPropertyKey[instruction.propertyKey] ?? []
            guard !siblings.isEmpty,
                  siblings.allSatisfy({ sibling in
                      guard sibling.valueType == .bool,
                            sibling.condition == nil,
                            case .effectVisibility = sibling.target else {
                          return false
                      }
                      return true
                  }),
                  !rebuildRequired.contains(instruction.propertyKey),
                  let definition = definitions[instruction.target],
                  definition.valueType == .bool,
                  case .bool = definition.authoredValue else { return nil }
            return instruction.target
        })
    }

    /// Layer visibility producers admitted by the typed binding program. A
    /// controlling key may fan out to multiple layers; live-state still
    /// requires every sibling target to be active before committing the key.
    nonisolated var liveLayerVisibilityTargets: Set<SceneDynamicTarget> {
        let validation = ScenePropertyBindingProgramValidator().validate(self)
        let definitions = Dictionary(
            uniqueKeysWithValues: validation.definitions.map { ($0.target, $0) }
        )
        let rebuildRequired = Set(rebuildRequiredPropertyKeys)
        return Set(validation.instructions.compactMap { instruction in
            guard !rebuildRequired.contains(instruction.propertyKey),
                  instruction.valueType == .bool,
                  case .layer(_, .visibility) = instruction.target,
                  let definition = definitions[instruction.target],
                  definition.valueType == .bool,
                  case .bool = definition.authoredValue else { return nil }
            return instruction.target
        })
    }

    nonisolated var liveConditionalLayerVisibilityTargets:
        Set<SceneDynamicTarget> {
        let conditionalTargets = Set(instructions.compactMap { instruction in
            instruction.condition == nil ? nil : instruction.target
        })
        return liveLayerVisibilityTargets.intersection(conditionalTargets)
    }

    private enum CodingKeys: String, CodingKey {
        case definitions
        case instructions
        case conditionalValueDomainsByPropertyKey
        case rebuildRequiredPropertyKeys
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let program = ScenePropertyBindingProgram(
            definitions: try container.decode([SceneDynamicTargetDefinition].self, forKey: .definitions),
            instructions: try container.decode([ScenePropertyBindingInstruction].self, forKey: .instructions),
            conditionalValueDomainsByPropertyKey: try container.decodeIfPresent(
                [String: [String]].self,
                forKey: .conditionalValueDomainsByPropertyKey
            ) ?? [:],
            rebuildRequiredPropertyKeys: try container.decode(
                [String].self,
                forKey: .rebuildRequiredPropertyKeys
            )
        )
        let validation = ScenePropertyBindingProgramValidator().validate(program)
        guard validation.diagnostics.isEmpty else {
            let codes = validation.diagnostics.map(\.code.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .instructions,
                in: container,
                debugDescription: "Invalid property binding program: \(codes)"
            )
        }
        self = program
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definitions, forKey: .definitions)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(
            conditionalValueDomainsByPropertyKey,
            forKey: .conditionalValueDomainsByPropertyKey
        )
        try container.encode(rebuildRequiredPropertyKeys, forKey: .rebuildRequiredPropertyKeys)
    }

    fileprivate nonisolated static func convert(
        _ value: SceneUserPropertyValue,
        as type: SceneDynamicValueType
    ) -> Result<SceneDynamicValue, ValueError> {
        switch (type, value) {
        case let (.bool, .bool(value)):
            return .success(.bool(value))
        case let (.scalar, .number(number)):
            return number.isFinite ? .success(.scalar(number)) : .failure(.nonFinite)
        case let (.vector3, .string(string)):
            return parseColor(string)
        case let (.string, .string(string)):
            return .success(.string(string))
        case (.bool, _), (.scalar, _), (.vector3, _), (.string, _):
            return .failure(.typeMismatch)
        default:
            return .failure(.unsupportedType)
        }
    }

    private nonisolated static func parseColor(
        _ value: String
    ) -> Result<SceneDynamicValue, ValueError> {
        let components = value.split(whereSeparator: \Character.isWhitespace)
        guard components.count == 3,
              let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2]) else {
            return .failure(.invalidFormat)
        }
        guard red.isFinite, green.isFinite, blue.isFinite else {
            return .failure(.nonFinite)
        }
        return .success(.vector3(red, green, blue))
    }

    enum ValueError: Error {
        case typeMismatch
        case invalidFormat
        case nonFinite
        case unsupportedType

        var runtimeCode: ScenePropertyBindingDiagnostic.Code {
            switch self {
            case .typeMismatch, .unsupportedType: .runtimeTypeMismatch
            case .invalidFormat: .invalidRuntimeValue
            case .nonFinite: .nonFiniteRuntimeValue
            }
        }

        var runtimeMessage: String {
            switch self {
            case .typeMismatch: "属性值类型与目标不匹配。"
            case .invalidFormat: "颜色值必须由三个空白分隔的数字组成。"
            case .nonFinite: "属性值包含非有限数字。"
            case .unsupportedType: "绑定程序不支持该动态值类型。"
            }
        }
    }
}

nonisolated struct ScenePropertyBindingCompilation: Codable, Equatable {
    let program: ScenePropertyBindingProgram
    let diagnostics: [ScenePropertyBindingDiagnostic]
}
nonisolated struct ScenePropertyBindingEvaluation: Equatable {
    let userValues: [SceneDynamicTarget: SceneDynamicValue]
    let diagnostics: [ScenePropertyBindingDiagnostic]
}

nonisolated struct ScenePropertyBindingCompiler {
    nonisolated func compile(
        report: SceneUserPropertyBindingReport,
        catalog: SceneUserPropertyCatalog
    ) -> ScenePropertyBindingCompilation {
        var diagnostics = report.diagnostics.compactMap(Self.inputDiagnostic)
        var rebuildRequiredKeys = Set(report.diagnostics.compactMap(\.propertyKey))
        let propertiesByKey = Dictionary(grouping: catalog.definitions, by: \.key)
        let sortedBindings = report.bindings.sorted(by: Self.bindingOrder)
        let bindingsByPropertyKey = Dictionary(
            grouping: sortedBindings,
            by: \.reference.key
        )
        let conditionalLayerVisibilityDomains = Dictionary(
            uniqueKeysWithValues: bindingsByPropertyKey.compactMap {
                propertyKey, bindings -> (String, [String])? in
                guard let domain = Self.conditionalLayerVisibilityDomain(
                    bindings: bindings,
                    definitions: propertiesByKey[propertyKey] ?? []
                ) else { return nil }
                return (propertyKey, domain)
            }
        )
        let admittedConditionalLayerVisibilityKeys = Set(
            conditionalLayerVisibilityDomains.keys
        )
        var targetBindings: [SceneDynamicTarget: [SceneUserPropertyBinding]] = [:]
        for binding in sortedBindings {
            let definitions = propertiesByKey[binding.reference.key] ?? []
            let propertyKind = definitions.count == 1 ? definitions[0].kind : nil
            guard let target = Self.map(
                binding,
                propertyKind: propertyKind
            )?.target else { continue }
            targetBindings[target, default: []].append(binding)
        }
        var definitions: [SceneDynamicTargetDefinition] = []
        var instructions: [ScenePropertyBindingInstruction] = []

        for binding in sortedBindings {
            let propertyDefinitions = propertiesByKey[binding.reference.key] ?? []
            let propertyKind = propertyDefinitions.count == 1
                ? propertyDefinitions[0].kind
                : nil
            guard let mapped = Self.map(
                binding,
                propertyKind: propertyKind
            ) else {
                rebuildRequiredKeys.insert(binding.reference.key)
                diagnostics.append(Self.compileDiagnostic(
                    code: .unsupportedTarget,
                    binding: binding,
                    target: nil,
                    message: Self.unsupportedMessage(binding.target)
                ))
                continue
            }

            var isValid = true
            if binding.reference.isConditional,
               !admittedConditionalLayerVisibilityKeys.contains(
                   binding.reference.key
               ) {
                isValid = false
                diagnostics.append(Self.compileDiagnostic(
                    code: .conditionalBinding,
                    binding: binding,
                    target: mapped.target,
                    message: "conditional binding 未形成完整的 Combo 图层选择组。"
                ))
            }
            switch propertyDefinitions.count {
            case 0:
                isValid = false
                diagnostics.append(Self.compileDiagnostic(
                    code: .missingPropertyDefinition,
                    binding: binding,
                    target: mapped.target,
                    message: "绑定引用的属性未定义。"
                ))
            case 1:
                break
            default:
                isValid = false
                diagnostics.append(Self.compileDiagnostic(
                    code: .duplicatePropertyDefinition,
                    binding: binding,
                    target: mapped.target,
                    message: "绑定引用的属性定义不唯一。"
                ))
            }
            if let property = propertyDefinitions.first, propertyDefinitions.count == 1 {
                if property.kind != mapped.propertyKind {
                    isValid = false
                    diagnostics.append(Self.compileDiagnostic(
                        code: .propertyKindMismatch,
                        binding: binding,
                        target: mapped.target,
                        message: "属性 kind 与绑定目标不匹配。"
                    ))
                }
                if let defaultValue = property.defaultValue {
                    let defaultValidation = binding.reference.isConditional
                        && admittedConditionalLayerVisibilityKeys.contains(
                            binding.reference.key
                        )
                        ? Self.validateConditionalValue(
                            defaultValue,
                            condition: binding.reference.condition,
                            propertyKind: property.kind
                        )
                        : ScenePropertyBindingProgram.convert(
                            defaultValue,
                            as: mapped.valueType
                        ).map { _ in () }
                    if case let .failure(error) = defaultValidation {
                        isValid = false
                        diagnostics.append(Self.compileDiagnostic(
                            code: Self.propertyDefaultCode(error),
                            binding: binding,
                            target: mapped.target,
                            message: Self.propertyDefaultMessage(error)
                        ))
                    }
                } else {
                    isValid = false
                    rebuildRequiredKeys.insert(binding.reference.key)
                    diagnostics.append(Self.compileDiagnostic(
                        code: .missingPropertyDefault,
                        binding: binding,
                        target: mapped.target,
                        message: "绑定引用的属性没有默认值。"
                    ))
                }
            }
            guard let fallback = binding.fallbackValue else {
                rebuildRequiredKeys.insert(binding.reference.key)
                diagnostics.append(Self.compileDiagnostic(
                    code: .missingAuthoredValue,
                    binding: binding,
                    target: mapped.target,
                    message: "绑定缺少可用的 authored fallback。"
                ))
                continue
            }
            let authoredValue: SceneDynamicValue
            switch Self.convertAuthoredFallback(
                fallback,
                target: binding.target,
                as: mapped.valueType
            ) {
            case let .success(value):
                authoredValue = value
            case let .failure(error):
                rebuildRequiredKeys.insert(binding.reference.key)
                diagnostics.append(Self.compileDiagnostic(
                    code: Self.authoredCode(error),
                    binding: binding,
                    target: mapped.target,
                    message: Self.authoredMessage(error)
                ))
                continue
            }
            guard targetBindings[mapped.target]?.count == 1 else {
                rebuildRequiredKeys.insert(binding.reference.key)
                continue
            }
            definitions.append(.init(
                target: mapped.target,
                valueType: mapped.valueType,
                authoredValue: authoredValue,
                userPropertyNumericRange: Self.userPropertyNumericRange(
                    propertyDefinitions.first,
                    propertyKind: mapped.propertyKind,
                    valueType: mapped.valueType
                )
            ))
            guard isValid else {
                rebuildRequiredKeys.insert(binding.reference.key)
                continue
            }
            instructions.append(.init(
                propertyKey: binding.reference.key,
                path: binding.path,
                target: mapped.target,
                valueType: mapped.valueType,
                condition: binding.reference.condition
            ))
        }

        for (target, bindings) in targetBindings where bindings.count > 1 {
            guard let binding = bindings.first else { continue }
            diagnostics.append(Self.compileDiagnostic(
                code: .duplicateTarget,
                binding: binding,
                target: target,
                message: "多个绑定写入同一动态目标，已全部禁用。"
            ))
        }

        definitions.sort { Self.definitionKey($0) < Self.definitionKey($1) }
        instructions.sort { Self.instructionKey($0) < Self.instructionKey($1) }
        diagnostics.sort(by: ScenePropertyBindingDiagnostic.areInIncreasingOrder)
        return .init(
            program: .init(
                definitions: definitions,
                instructions: instructions,
                conditionalValueDomainsByPropertyKey:
                    conditionalLayerVisibilityDomains,
                rebuildRequiredPropertyKeys: rebuildRequiredKeys.sorted()
            ),
            diagnostics: diagnostics
        )
    }

    private nonisolated static func userPropertyNumericRange(
        _ property: SceneUserPropertyDefinition?,
        propertyKind: SceneUserPropertyKind,
        valueType: SceneDynamicValueType
    ) -> ClosedRange<Double>? {
        guard propertyKind == .slider, valueType == .scalar,
              let minimum = property?.minimumValue,
              let maximum = property?.maximumValue,
              minimum.isFinite, maximum.isFinite,
              minimum <= maximum else { return nil }
        return minimum ... maximum
    }

    /// A slider remains a scalar producer even when an authored shader
    /// wrapper records the same fallback in both lanes of a float2. Preserve
    /// that producer type here; the MaterialProgram consumer owns the exact
    /// reflected scalar-to-float2 projection.
    private nonisolated static func convertAuthoredFallback(
        _ fallback: SceneUserPropertyValue,
        target: SceneUserPropertyBindingTarget,
        as valueType: SceneDynamicValueType
    ) -> Result<SceneDynamicValue, ScenePropertyBindingProgram.ValueError> {
        if target.isShaderValue,
           valueType == .scalar,
           case let .string(rawValue) = fallback,
           let value = scalarShaderFallback(rawValue) {
            return .success(.scalar(value))
        }
        return ScenePropertyBindingProgram.convert(fallback, as: valueType)
    }

    private nonisolated static func validateConditionalValue(
        _ value: SceneUserPropertyValue,
        condition: SceneUserPropertyValue?,
        propertyKind: SceneUserPropertyKind
    ) -> Result<Void, ScenePropertyBindingProgram.ValueError> {
        guard let condition else { return .failure(.unsupportedType) }
        switch (propertyKind, value, condition) {
        case (.combo, .string, .string):
            return .success(())
        default:
            return .failure(.typeMismatch)
        }
    }

    private nonisolated static func conditionalLayerVisibilityDomain(
        bindings: [SceneUserPropertyBinding],
        definitions: [SceneUserPropertyDefinition]
    ) -> [String]? {
        guard (1 ... 256).contains(bindings.count),
              definitions.count == 1,
              let property = definitions.first,
              property.kind == .combo,
              case let .string(defaultValue)? = property.defaultValue
        else { return nil }

        let optionValues = property.options.compactMap { option -> String? in
            guard case let .string(value) = option.value else { return nil }
            return value
        }
        let optionValueSet = Set(optionValues)
        guard !optionValues.isEmpty,
              optionValues.count == property.options.count,
              optionValueSet.count == optionValues.count,
              optionValueSet.contains(defaultValue) else { return nil }

        var layerIDs = Set<Int>()
        for binding in bindings {
            guard case let .layerVisibility(layerID) = binding.target,
                  layerID >= 0,
                  layerIDs.insert(layerID).inserted,
                  case let .string(condition)? = binding.reference.condition,
                  optionValueSet.contains(condition),
                  case let .bool(fallback)? = binding.fallbackValue,
                  fallback == (condition == defaultValue) else {
                return nil
            }
        }
        return optionValues
    }

    private nonisolated static func bindingOrder(
        _ lhs: SceneUserPropertyBinding,
        _ rhs: SceneUserPropertyBinding
    ) -> Bool {
        bindingKey(lhs) < bindingKey(rhs)
    }

    private nonisolated static func bindingKey(_ binding: SceneUserPropertyBinding) -> String {
        let target = map(binding.target)?.target
        return [
            ScenePropertyBindingDiagnostic.targetKey(target),
            binding.path.description,
            binding.reference.key,
        ].joined(separator: "\u{1f}")
    }

    private nonisolated static func definitionKey(
        _ definition: SceneDynamicTargetDefinition
    ) -> String {
        ScenePropertyBindingDiagnostic.targetKey(definition.target)
    }

    private nonisolated static func instructionKey(
        _ instruction: ScenePropertyBindingInstruction
    ) -> String {
        [
            ScenePropertyBindingDiagnostic.targetKey(instruction.target),
            instruction.path.description,
            instruction.propertyKey,
        ].joined(separator: "\u{1f}")
    }

}

private extension SceneUserPropertyBindingTarget {
    nonisolated var isShaderValue: Bool {
        switch self {
        case .shaderValue, .materialShaderValue: true
        default: false
        }
    }
}
