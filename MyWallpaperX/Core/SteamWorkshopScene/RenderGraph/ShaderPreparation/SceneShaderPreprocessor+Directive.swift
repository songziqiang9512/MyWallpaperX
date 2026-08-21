import Foundation

extension SceneShaderPreprocessor.State {
    /// Some shipped authored sources contain one duplicated top-level
    /// `#endif` between two otherwise balanced conditional blocks. Accept the
    /// inert duplicate only for that complete structural shape; a standalone,
    /// trailing, repeated, or code-separated unmatched directive still fails.
    nonisolated static func recoverableRedundantEndifLines(
        in lines: [Substring]
    ) -> Set<Int> {
        var depth = 0
        var inBlockComment = false
        var justClosedTopLevel = false
        var pendingCandidate: Int?
        var recovered: [Int] = []

        for (offset, substring) in lines.enumerated() {
            let lexical = SceneShaderLexicalScanner.scan(
                String(substring),
                inBlockComment: &inBlockComment
            )
            let code = lexical.code.trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty else { continue }
            guard let directive = SceneShaderDirective.parse(code) else {
                if pendingCandidate != nil { return [] }
                justClosedTopLevel = false
                continue
            }
            switch directive {
            case .ifExpression, .ifdef:
                if let candidate = pendingCandidate {
                    recovered.append(candidate)
                    pendingCandidate = nil
                }
                depth += 1
                justClosedTopLevel = false
            case .endif:
                if depth > 0 {
                    depth -= 1
                    justClosedTopLevel = depth == 0
                } else if justClosedTopLevel,
                          pendingCandidate == nil,
                          recovered.isEmpty {
                    pendingCandidate = offset + 1
                    justClosedTopLevel = false
                } else {
                    return []
                }
            case .elifExpression, .elseDirective:
                guard depth > 0, pendingCandidate == nil else { return [] }
                justClosedTopLevel = false
            default:
                if pendingCandidate != nil { return [] }
                justClosedTopLevel = false
            }
        }
        guard depth == 0,
              pendingCandidate == nil,
              recovered.count == 1 else { return [] }
        return Set(recovered)
    }

    nonisolated mutating func handle(
        _ directive: SceneShaderDirective,
        node: SceneShaderSourceGraph.Node,
        line: Int,
        floor: Int,
        stack: [String]
    ) throws {
        switch directive {
        case let .define(name, value):
            guard currentActive else { return }
            if let requirement = SceneShaderVariantEnvironment.unresolvedRequirement(for: name) {
                throw unresolvedEnvironment(name, requirement, node.virtualPath, line)
            }
            if let selected = selectedDefinitions[name] {
                guard selected == .defined(value) else {
                    throw failure(.conflictingMacro, "Selected macro '\(name)' cannot be redefined by source.", node.virtualPath, line)
                }
                macros[name] = value
                return
            }
            if functionMacros[name] != nil {
                throw failure(.conflictingMacro, "Macro '\(name)' changes from function-like to object-like.", node.virtualPath, line)
            }
            if let existing = macros[name], existing != value {
                throw failure(.conflictingMacro, "Macro '\(name)' is redefined with another value.", node.virtualPath, line)
            }
            macros[name] = value
        case let .defineFunction(macro):
            guard currentActive else { return }
            guard macro.parameters.count <= limits.maximumFunctionMacroParameters else {
                throw failure(.budgetExceeded, "Function-like shader macro parameter count exceeds its budget.", node.virtualPath, line)
            }
            if let requirement = SceneShaderVariantEnvironment.unresolvedRequirement(for: macro.name) {
                throw unresolvedEnvironment(macro.name, requirement, node.virtualPath, line)
            }
            if selectedDefinitions[macro.name] != nil || macros[macro.name] != nil {
                throw failure(.conflictingMacro, "Macro '\(macro.name)' changes from object-like to function-like.", node.virtualPath, line)
            }
            if let existing = functionMacros[macro.name], existing != macro {
                throw failure(.conflictingMacro, "Function-like macro '\(macro.name)' is redefined.", node.virtualPath, line)
            }
            functionMacros[macro.name] = macro
        case let .undef(name):
            guard currentActive else { return }
            if let requirement = SceneShaderVariantEnvironment.unresolvedRequirement(for: name) {
                throw unresolvedEnvironment(name, requirement, node.virtualPath, line)
            }
            if let selected = selectedDefinitions[name] {
                guard selected == .undefined else {
                    throw failure(.conflictingMacro, "Selected macro '\(name)' cannot be undefined by source.", node.virtualPath, line)
                }
                return
            }
            macros.removeValue(forKey: name)
            functionMacros.removeValue(forKey: name)
        case let .include(path):
            guard currentActive else { return }
            try include(path, node: node, line: line, stack: stack)
        case let .require(name):
            requireDirectiveOrdinal += 1
            guard currentActive else { return }
            try resolveModule(
                name,
                node: node,
                line: line,
                ordinal: requireDirectiveOrdinal
            )
        case let .malformedRequire(message):
            throw failure(
                .moduleDirectiveSyntax,
                message,
                node.virtualPath,
                line
            )
        case let .ifExpression(expression):
            let parent = currentActive
            let result = parent
                ? try evaluate(expression, path: node.virtualPath, line: line)
                : false
            conditions.append(.init(
                parentActive: parent,
                branchWasTrue: result,
                isActive: parent && result,
                sawElse: false
            ))
        case let .ifdef(name, inverted):
            let parent = currentActive
            if parent,
               macros[name] == nil, functionMacros[name] == nil,
               selectedDefinitions[name] == nil,
               let requirement = SceneShaderVariantEnvironment.unresolvedRequirement(for: name),
               !SceneShaderVariantEnvironment.permitsUndefinedZeroInCondition(name) {
                throw unresolvedEnvironment(name, requirement, node.virtualPath, line)
            }
            let result = parent && (macros[name] != nil || functionMacros[name] != nil)
            let selected = inverted ? !result : result
            conditions.append(.init(
                parentActive: parent,
                branchWasTrue: selected,
                isActive: parent && selected,
                sawElse: false
            ))
        case let .elifExpression(expression):
            guard conditions.count > floor else {
                throw failure(
                    .unmatchedElif,
                    "Shader #elif has no matching conditional.",
                    node.virtualPath,
                    line
                )
            }
            guard !conditions[conditions.count - 1].sawElse else {
                throw failure(
                    .elifAfterElse,
                    "Shader #elif cannot follow #else.",
                    node.virtualPath,
                    line
                )
            }
            let parent = conditions[conditions.count - 1].parentActive
            let priorMatched = conditions[conditions.count - 1].branchWasTrue
            let result = parent && !priorMatched
                ? try evaluate(expression, path: node.virtualPath, line: line)
                : false
            conditions[conditions.count - 1].isActive = parent && !priorMatched && result
            conditions[conditions.count - 1].branchWasTrue = priorMatched || result
        case .elseDirective:
            guard conditions.count > floor else {
                throw failure(.unmatchedElse, "Shader #else has no matching conditional.", node.virtualPath, line)
            }
            guard !conditions[conditions.count - 1].sawElse else {
                throw failure(.duplicateElse, "Shader conditional contains more than one #else.", node.virtualPath, line)
            }
            conditions[conditions.count - 1].sawElse = true
            conditions[conditions.count - 1].isActive = conditions.last!.parentActive
                && !conditions.last!.branchWasTrue
            conditions[conditions.count - 1].branchWasTrue = true
        case .endif:
            guard conditions.count > floor else {
                throw failure(.unmatchedEndif, "Shader #endif has no matching conditional.", node.virtualPath, line)
            }
            conditions.removeLast()
        case let .unsupported(name):
            throw failure(.unsupportedDirective, "Shader directive '#\(name)' is unsupported.", node.virtualPath, line)
        case let .unknown(name):
            throw failure(.unknownDirective, "Shader directive '#\(name)' is unknown.", node.virtualPath, line)
        case let .unsupportedFunctionMacro(message):
            throw failure(.functionLikeMacro, message, node.virtualPath, line)
        case let .malformed(message):
            throw failure(.malformedDirective, message, node.virtualPath, line)
        }
    }

    nonisolated mutating func resolveModule(
        _ name: String,
        node: SceneShaderSourceGraph.Node,
        line: Int,
        ordinal: Int
    ) throws {
        let lighting = SceneShaderModuleIdentity.lightingV1
        guard name == lighting.rawValue else {
            let code: SceneShaderPreprocessor.DiagnosticCode =
                name.caseInsensitiveCompare(lighting.rawValue) == .orderedSame
                    ? .moduleCaseMismatch : .moduleUnknown
            let message = code == .moduleCaseMismatch
                ? "Shader module names are case-sensitive."
                : "Shader module '\(name)' is unsupported."
            throw failure(code, message, node.virtualPath, line)
        }
        guard let value = macros["LIGHTING"] else {
            let code: SceneShaderPreprocessor.DiagnosticCode =
                functionMacros["LIGHTING"] == nil
                    ? .moduleLightingMacroMissing
                    : .moduleLightingMacroNoninteger
            throw failure(
                code,
                code == .moduleLightingMacroMissing
                    ? "LightingV1 requires a typed integer LIGHTING macro."
                    : "LightingV1 does not accept a function-like LIGHTING macro.",
                node.virtualPath,
                line
            )
        }
        guard case let .integer(integer) = value else {
            throw failure(
                .moduleLightingMacroNoninteger,
                "LightingV1 requires LIGHTING to be a typed integer.",
                node.virtualPath,
                line
            )
        }
        guard integer == 0 else {
            throw failure(
                .moduleLightingNonzero,
                "LightingV1 only accepts the bounded LIGHTING=0 profile.",
                node.virtualPath,
                line
            )
        }
        moduleDependencies.append(.init(
            module: lighting,
            stage: environment.stage,
            sourcePath: node.virtualPath,
            sourceLine: line,
            directiveOrdinal: ordinal,
            macroEnvironmentSHA256: SceneShaderModuleMacroEnvironment.digest(
                objectMacros: macros,
                functionMacros: functionMacros.values.map {
                    .init(
                        name: $0.name,
                        parameters: $0.parameters,
                        replacement: $0.replacement
                    )
                }
            ),
            outcome: .zeroSourceContribution
        ))
    }
}
