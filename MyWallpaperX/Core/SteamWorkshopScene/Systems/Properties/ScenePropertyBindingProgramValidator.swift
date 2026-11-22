import Foundation

nonisolated struct ScenePropertyBindingProgramValidation: Equatable {
    let definitionsByTarget: [SceneDynamicTarget: SceneDynamicTargetDefinition]
    let instructions: [ScenePropertyBindingInstruction]
    let diagnostics: [ScenePropertyBindingDiagnostic]
}

nonisolated struct ScenePropertyBindingProgramValidator {
    nonisolated func validate(
        definitions: [SceneDynamicTargetDefinition],
        instructions: [ScenePropertyBindingInstruction]
    ) -> ScenePropertyBindingProgramValidation {
        let definitionsByTarget = Dictionary(grouping: definitions, by: \.target)
        let instructionsByTarget = Dictionary(grouping: instructions, by: \.target)
        var diagnostics: [ScenePropertyBindingDiagnostic] = []

        for (target, definitions) in definitionsByTarget where definitions.count > 1 {
            diagnostics.append(.structure(
                code: .duplicateProgramDefinition,
                instruction: instructionsByTarget[target]?.first,
                target: target,
                message: String(localized: "The binding program contains a duplicate target definition.")
            ))
        }
        for (target, instructions) in instructionsByTarget where instructions.count > 1 {
            diagnostics.append(.structure(
                code: .duplicateProgramInstruction,
                instruction: Self.sorted(instructions).first,
                target: target,
                message: String(localized: "The binding program contains a duplicate target instruction.")
            ))
        }

        var validInstructions: [ScenePropertyBindingInstruction] = []
        for (target, instructions) in instructionsByTarget where instructions.count == 1 {
            guard let instruction = instructions.first else { continue }
            guard let definitions = definitionsByTarget[target], !definitions.isEmpty else {
                diagnostics.append(.structure(
                    code: .missingProgramDefinition,
                    instruction: instruction,
                    target: target,
                    message: String(localized: "The instruction has no matching target definition.")
                ))
                continue
            }
            guard definitions.count == 1, let definition = definitions.first else {
                continue
            }
            guard definition.valueType == instruction.valueType else {
                diagnostics.append(.structure(
                    code: .programTypeMismatch,
                    instruction: instruction,
                    target: target,
                    message: String(localized: "The instruction and target definition value types don’t match.")
                ))
                continue
            }
            guard instruction.condition == nil || instruction.valueType == .bool else {
                diagnostics.append(.structure(
                    code: .programTypeMismatch,
                    instruction: instruction,
                    target: target,
                    message: String(localized: "A conditional instruction must produce a Boolean target.")
                ))
                continue
            }
            validInstructions.append(instruction)
        }

        let validDefinitions = definitionsByTarget.compactMapValues { definitions in
            definitions.count == 1 ? definitions.first : nil
        }
        diagnostics.sort(by: ScenePropertyBindingDiagnostic.areInIncreasingOrder)
        return .init(
            definitionsByTarget: validDefinitions,
            instructions: Self.sorted(validInstructions),
            diagnostics: diagnostics
        )
    }

    private nonisolated static func sorted(
        _ instructions: [ScenePropertyBindingInstruction]
    ) -> [ScenePropertyBindingInstruction] {
        instructions.sorted {
            let lhs = [targetKey($0.target), $0.path.description, $0.propertyKey]
                .joined(separator: "\u{1f}")
            let rhs = [targetKey($1.target), $1.path.description, $1.propertyKey]
                .joined(separator: "\u{1f}")
            return lhs < rhs
        }
    }

    private nonisolated static func targetKey(_ target: SceneDynamicTarget) -> String {
        ScenePropertyBindingDiagnostic.targetKey(target)
    }
}

nonisolated struct ScenePropertyBindingDiagnostic: Codable, Equatable {
    enum Stage: String, Codable {
        case compile
        case structure
        case runtime
    }

    enum Code: String, Codable {
        case malformedInputBinding
        case unsupportedTarget
        case conditionalBinding
        case duplicateTarget
        case missingPropertyDefinition
        case duplicatePropertyDefinition
        case propertyKindMismatch
        case missingPropertyDefault
        case propertyDefaultTypeMismatch
        case invalidPropertyDefaultValue
        case nonFinitePropertyDefaultValue
        case missingAuthoredValue
        case authoredTypeMismatch
        case invalidAuthoredValue
        case nonFiniteAuthoredValue
        case duplicateProgramDefinition
        case duplicateProgramInstruction
        case missingProgramDefinition
        case programTypeMismatch
        case missingEffectiveValue
        case runtimeTypeMismatch
        case invalidRuntimeValue
        case nonFiniteRuntimeValue
    }

    let stage: Stage
    let code: Code
    let path: SceneUserPropertyPath?
    let propertyKey: String?
    let target: SceneDynamicTarget?
    let message: String

    nonisolated static func runtime(
        code: Code,
        instruction: ScenePropertyBindingInstruction,
        message: String
    ) -> ScenePropertyBindingDiagnostic {
        .init(
            stage: .runtime,
            code: code,
            path: instruction.path,
            propertyKey: instruction.propertyKey,
            target: instruction.target,
            message: message
        )
    }

    nonisolated static func structure(
        code: Code,
        instruction: ScenePropertyBindingInstruction?,
        target: SceneDynamicTarget,
        message: String
    ) -> ScenePropertyBindingDiagnostic {
        .init(
            stage: .structure,
            code: code,
            path: instruction?.path,
            propertyKey: instruction?.propertyKey,
            target: target,
            message: message
        )
    }

    nonisolated static func areInIncreasingOrder(
        _ lhs: ScenePropertyBindingDiagnostic,
        _ rhs: ScenePropertyBindingDiagnostic
    ) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    nonisolated static func targetKey(_ target: SceneDynamicTarget?) -> String {
        guard let target else { return "" }
        switch target {
        case let .layer(layerID, field):
            return "layer:\(layerID):\(field.rawValue)"
        case let .text(layerID, field):
            return "layer:\(layerID):text:\(field.rawValue)"
        default:
            return String(describing: target)
        }
    }

    private nonisolated var sortKey: String {
        [
            stage.rawValue,
            Self.targetKey(target),
            path?.description ?? "",
            propertyKey ?? "",
            code.rawValue,
            message,
        ].joined(separator: "\u{1f}")
    }
}

extension ScenePropertyBindingCompiler {
    nonisolated static func inputDiagnostic(
        _ diagnostic: SceneUserPropertyBindingDiagnostic
    ) -> ScenePropertyBindingDiagnostic? {
        guard diagnostic.kind == .malformedUserReference else { return nil }
        return .init(
            stage: .compile,
            code: .malformedInputBinding,
            path: diagnostic.path,
            propertyKey: diagnostic.propertyKey,
            target: nil,
            message: diagnostic.message
        )
    }

    nonisolated static func compileDiagnostic(
        code: ScenePropertyBindingDiagnostic.Code,
        binding: SceneUserPropertyBinding,
        target: SceneDynamicTarget?,
        message: String
    ) -> ScenePropertyBindingDiagnostic {
        .init(
            stage: .compile,
            code: code,
            path: binding.path,
            propertyKey: binding.reference.key,
            target: target,
            message: message
        )
    }

    nonisolated static func authoredCode(
        _ error: ScenePropertyBindingProgram.ValueError
    ) -> ScenePropertyBindingDiagnostic.Code {
        switch error {
        case .typeMismatch, .unsupportedType: .authoredTypeMismatch
        case .invalidFormat: .invalidAuthoredValue
        case .nonFinite: .nonFiniteAuthoredValue
        }
    }

    nonisolated static func authoredMessage(
        _ error: ScenePropertyBindingProgram.ValueError
    ) -> String {
        switch error {
        case .typeMismatch: String(localized: "Authored fallback type doesn’t match the target.")
        case .invalidFormat: String(localized: "Authored colors must consist of three whitespace-separated numbers.")
        case .nonFinite: String(localized: "Authored fallback contains a non-finite number.")
        case .unsupportedType: String(localized: "The binding program doesn’t support this authored type.")
        }
    }

    nonisolated static func propertyDefaultCode(
        _ error: ScenePropertyBindingProgram.ValueError
    ) -> ScenePropertyBindingDiagnostic.Code {
        switch error {
        case .typeMismatch, .unsupportedType: .propertyDefaultTypeMismatch
        case .invalidFormat: .invalidPropertyDefaultValue
        case .nonFinite: .nonFinitePropertyDefaultValue
        }
    }

    nonisolated static func propertyDefaultMessage(
        _ error: ScenePropertyBindingProgram.ValueError
    ) -> String {
        switch error {
        case .typeMismatch: String(localized: "The property default type doesn’t match the target.")
        case .invalidFormat: String(localized: "A color property default must be three numbers separated by whitespace.")
        case .nonFinite: String(localized: "The property default contains a non-finite number.")
        case .unsupportedType: String(localized: "The binding program doesn’t support this property default type.")
        }
    }

    nonisolated static func unsupportedMessage(
        _ target: SceneUserPropertyBindingTarget
    ) -> String {
        if case let .unsupported(reason) = target { return reason }
        return String(localized: "The current binding program doesn’t support this property target or execution profile.")
    }
}
