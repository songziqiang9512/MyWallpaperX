import Foundation

nonisolated struct ScenePropertyBindingInstruction: Codable, Equatable {
    let propertyKey: String
    let path: SceneUserPropertyPath
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType
}

nonisolated struct ScenePropertyBindingProgram: Codable, Equatable {
    let definitions: [SceneDynamicTargetDefinition]
    let instructions: [ScenePropertyBindingInstruction]
    let rebuildRequiredPropertyKeys: [String]

    nonisolated init(
        definitions: [SceneDynamicTargetDefinition],
        instructions: [ScenePropertyBindingInstruction],
        rebuildRequiredPropertyKeys: [String] = []
    ) {
        self.definitions = definitions
        self.instructions = instructions
        self.rebuildRequiredPropertyKeys = Array(Set(rebuildRequiredPropertyKeys)).sorted()
    }

    nonisolated func evaluate(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> ScenePropertyBindingEvaluation {
        let validation = ScenePropertyBindingProgramValidator().validate(self)
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
            switch Self.convert(value, as: instruction.valueType) {
            case let .success(dynamicValue):
                userValues[instruction.target] = dynamicValue
            case let .failure(error):
                diagnostics.append(.runtime(
                    code: error.runtimeCode,
                    instruction: instruction,
                    message: error.runtimeMessage
                ))
            }
        }

        return ScenePropertyBindingEvaluation(
            userValues: userValues,
            diagnostics: diagnostics.sorted(by: ScenePropertyBindingDiagnostic.areInIncreasingOrder)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case definitions
        case instructions
        case rebuildRequiredPropertyKeys
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let program = ScenePropertyBindingProgram(
            definitions: try container.decode([SceneDynamicTargetDefinition].self, forKey: .definitions),
            instructions: try container.decode([ScenePropertyBindingInstruction].self, forKey: .instructions),
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
        try container.encode(rebuildRequiredPropertyKeys, forKey: .rebuildRequiredPropertyKeys)
    }

    fileprivate nonisolated static func convert(
        _ value: SceneUserPropertyValue,
        as type: SceneDynamicValueType
    ) -> Result<SceneDynamicValue, ValueError> {
        switch (type, value) {
        case let (.scalar, .number(number)):
            return number.isFinite ? .success(.scalar(number)) : .failure(.nonFinite)
        case let (.vector3, .string(string)):
            return parseColor(string)
        case (.scalar, _), (.vector3, _):
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
        var targetBindings: [SceneDynamicTarget: [SceneUserPropertyBinding]] = [:]
        for binding in sortedBindings {
            guard let target = Self.map(binding.target)?.target else { continue }
            targetBindings[target, default: []].append(binding)
        }
        var definitions: [SceneDynamicTargetDefinition] = []
        var instructions: [ScenePropertyBindingInstruction] = []

        for binding in sortedBindings {
            guard let mapped = Self.map(binding.target) else {
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
            if binding.reference.isConditional {
                isValid = false
                diagnostics.append(Self.compileDiagnostic(
                    code: .conditionalBinding,
                    binding: binding,
                    target: mapped.target,
                    message: "当前 binding program 仅接受 direct binding。"
                ))
            }
            let propertyDefinitions = propertiesByKey[binding.reference.key] ?? []
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
                guard let defaultValue = property.defaultValue else {
                    isValid = false
                    rebuildRequiredKeys.insert(binding.reference.key)
                    diagnostics.append(Self.compileDiagnostic(
                        code: .missingPropertyDefault,
                        binding: binding,
                        target: mapped.target,
                        message: "绑定引用的属性没有默认值。"
                    ))
                    continue
                }
                if case let .failure(error) = ScenePropertyBindingProgram.convert(
                    defaultValue,
                    as: mapped.valueType
                ) {
                    isValid = false
                    diagnostics.append(Self.compileDiagnostic(
                        code: Self.propertyDefaultCode(error),
                        binding: binding,
                        target: mapped.target,
                        message: Self.propertyDefaultMessage(error)
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
            switch ScenePropertyBindingProgram.convert(fallback, as: mapped.valueType) {
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
            guard isValid, targetBindings[mapped.target]?.count == 1 else {
                rebuildRequiredKeys.insert(binding.reference.key)
                continue
            }
            definitions.append(.init(
                target: mapped.target,
                valueType: mapped.valueType,
                authoredValue: authoredValue
            ))
            instructions.append(.init(
                propertyKey: binding.reference.key,
                path: binding.path,
                target: mapped.target,
                valueType: mapped.valueType
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
                rebuildRequiredPropertyKeys: rebuildRequiredKeys.sorted()
            ),
            diagnostics: diagnostics
        )
    }
    private nonisolated static func map(
        _ target: SceneUserPropertyBindingTarget
    ) -> (
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType,
        propertyKind: SceneUserPropertyKind
    )? {
        switch target {
        case let .layerAlpha(layerID):
            (.layer(layerID: layerID, field: .alpha), .scalar, .slider)
        case let .layerColor(layerID):
            (.layer(layerID: layerID, field: .color), .vector3, .color)
        default:
            nil
        }
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
