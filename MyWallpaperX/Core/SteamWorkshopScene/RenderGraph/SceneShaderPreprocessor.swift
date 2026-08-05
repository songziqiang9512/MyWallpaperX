import Foundation

nonisolated struct SceneShaderPreprocessor {
    func preprocess(
        rootRelativePath: String,
        graph: SceneShaderSourceGraph,
        environment: SceneShaderVariantEnvironment,
        limits: Limits = .default
    ) -> Result<SceneShaderPreparedSource, Failure> {
        guard let root = graph.node(at: rootRelativePath) else {
            return .failure(Failure(diagnostics: [Diagnostic(
                code: .missingRoot,
                message: "Shader source root is unavailable.",
                relativePath: rootRelativePath,
                line: nil
            )]))
        }
        var state = State(graph: graph, environment: environment, limits: limits)
        do {
            try state.process(root, stack: [])
            return .success(try state.prepared(rootRelativePath: root.virtualPath))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            preconditionFailure("Unexpected Scene shader preprocessor error: \(error)")
        }
    }
}

extension SceneShaderPreprocessor {
    nonisolated struct State {
        let graph: SceneShaderSourceGraph
        let environment: SceneShaderVariantEnvironment
        let limits: Limits
        let selectedDefinitions: [String: SceneShaderMacroDefinition]
        var macros: [String: SceneShaderMacroValue]
        var functionMacros: [String: SceneShaderFunctionMacro] = [:]
        var conditions: [ConditionalFrame] = []
        var outputLines: [String] = []
        var sourceMap: [SceneShaderSourceMapEntry] = []
        var annotations: [SceneShaderActiveAnnotation] = []
        var declarations: [SceneShaderActiveDeclaration] = []
        var dependencies: [String: String] = [:]
        var inputBytes = 0
        var outputBytes = 0

        init(
            graph: SceneShaderSourceGraph,
            environment: SceneShaderVariantEnvironment,
            limits: Limits
        ) {
            self.graph = graph
            self.environment = environment
            self.limits = limits
            selectedDefinitions = environment.selectedMacroDefinitions()
            macros = environment.initialMacroTable()
        }

        mutating func process(_ node: SceneShaderSourceGraph.Node, stack: [String]) throws {
            guard stack.count < limits.maximumIncludeDepth else {
                throw failure(.budgetExceeded, "Shader include depth exceeds its budget.", node.virtualPath)
            }
            let identity = node.virtualPath.lowercased()
            guard !stack.contains(identity) else {
                throw failure(.includeCycle, "Shader include cycle contains '\(node.virtualPath)'.", node.virtualPath)
            }
            let actualHash = SceneShaderStableDigest.hash(Data(node.source.utf8))
            guard actualHash == node.rawSHA256.lowercased() else {
                throw failure(.sourceIdentityMismatch, "Shader source bytes do not match their identity.", node.virtualPath)
            }
            if let existing = dependencies[node.virtualPath], existing != actualHash {
                throw failure(.sourceIdentityMismatch, "Shader dependency changed during preprocessing.", node.virtualPath)
            }
            dependencies[node.virtualPath] = actualHash
            guard dependencies.count <= limits.maximumDependencies else {
                throw failure(.budgetExceeded, "Shader dependency count exceeds its budget.", node.virtualPath)
            }
            inputBytes += node.source.utf8.count
            guard inputBytes <= limits.maximumInputBytes else {
                throw failure(.budgetExceeded, "Shader input bytes exceed their budget.", node.virtualPath)
            }

            let floor = conditions.count
            let parsed = SceneShaderContractSourceParser().parse(
                node.source,
                stageRelativePath: node.virtualPath
            )
            let diagnosticsByLine = Dictionary(grouping: parsed.diagnostics, by: \.line)
            if let diagnostics = diagnosticsByLine[nil] {
                throw sourceFailure(diagnostics, fallbackPath: node.virtualPath)
            }
            let annotationLines = Dictionary(grouping: parsed.annotations, by: \.line)
            let declarationLines = Dictionary(grouping: parsed.declarations, by: \.line)
            let lines = node.source.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            var inBlockComment = false
            for (offset, substring) in lines.enumerated() {
                let lineNumber = offset + 1
                let line = String(substring)
                let lexical = SceneShaderLexicalScanner.scan(
                    line,
                    inBlockComment: &inBlockComment
                )
                if let directive = SceneShaderDirective.parse(lexical.code) {
                    if directive.metadataIsActive(
                        currentActive: currentActive,
                        closingParentActive: conditions.count > floor
                            ? conditions.last?.parentActive : nil
                    ) {
                        if let diagnostics = diagnosticsByLine[lineNumber] {
                            throw sourceFailure(diagnostics, fallbackPath: node.virtualPath)
                        }
                        if !(annotationLines[lineNumber] ?? []).isEmpty {
                            throw failure(
                                .unsupportedAnnotationPlacement,
                                "Shader combo annotations on directive lines are unsupported.",
                                node.virtualPath,
                                lineNumber
                            )
                        }
                    }
                    try handle(directive, node: node, line: lineNumber, floor: floor, stack: stack)
                } else if currentActive {
                    if let diagnostics = diagnosticsByLine[lineNumber] {
                        throw sourceFailure(diagnostics, fallbackPath: node.virtualPath)
                    }
                    try append(
                        try expand(lexical, path: node.virtualPath, line: lineNumber),
                        path: node.virtualPath,
                        line: lineNumber
                    )
                    for annotation in annotationLines[lineNumber] ?? [] {
                        annotations.append(.init(sourcePath: node.virtualPath, annotation: annotation))
                    }
                    for declaration in declarationLines[lineNumber] ?? [] {
                        declarations.append(.init(sourcePath: node.virtualPath, declaration: declaration))
                    }
                }
            }
            guard !inBlockComment else {
                throw failure(
                    .unterminatedBlockComment,
                    "Shader source ends inside a block comment.",
                    node.virtualPath
                )
            }
            guard conditions.count == floor else {
                throw failure(
                    .unterminatedConditional,
                    "Shader source ends with an unterminated conditional.",
                    node.virtualPath
                )
            }
        }

        mutating func prepared(rootRelativePath: String) throws -> SceneShaderPreparedSource {
            let sortedDependencies = dependencies.keys.sorted().map {
                SceneShaderSourceDependency(relativePath: $0, rawSHA256: dependencies[$0]!)
            }
            let dependencyHash = SceneShaderStableDigest.hash(sortedDependencies)
            let source = outputLines.joined(separator: "\n")
            let payload = PreparedDigestPayload(
                frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion,
                sourceDialect: environment.sourceDialect,
                backend: environment.backend,
                stage: environment.stage,
                rootRelativePath: rootRelativePath,
                source: source,
                sourceMap: sourceMap,
                activeAnnotations: annotations,
                activeDeclarations: declarations,
                dependencySHA256: dependencyHash,
                variantSHA256: environment.variantSHA256
            )
            return SceneShaderPreparedSource(
                frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion,
                sourceDialect: environment.sourceDialect,
                backend: environment.backend,
                stage: environment.stage,
                rootRelativePath: rootRelativePath,
                source: source,
                sourceMap: sourceMap,
                activeAnnotations: annotations,
                activeDeclarations: declarations,
                dependencies: sortedDependencies,
                dependencySHA256: dependencyHash,
                variantSHA256: environment.variantSHA256,
                preparedSHA256: SceneShaderStableDigest.hash(payload)
            )
        }

        var currentActive: Bool { conditions.last?.isActive ?? true }

        mutating func include(
            _ path: String,
            node: SceneShaderSourceGraph.Node,
            line: Int,
            stack: [String]
        ) throws {
            guard let edge = graph.edge(parentVirtualPath: node.virtualPath, line: line),
                  edge.request == path else {
                throw failure(.rejectedInclude, "Shader include graph does not match the active directive.", node.virtualPath, line)
            }
            switch edge.outcome {
            case let .resolved(virtualPath):
                guard let included = graph.node(at: virtualPath) else {
                    throw failure(.rejectedInclude, "Shader include graph resolved to an unavailable node.", node.virtualPath, line)
                }
                try process(included, stack: stack + [node.virtualPath.lowercased()])
            case .missing:
                throw failure(.missingInclude, "Shader include '\(path)' is missing.", node.virtualPath, line)
            case let .ambiguous(candidates):
                let names = candidates.sorted().joined(separator: ", ")
                throw failure(.ambiguousInclude, "Shader include '\(path)' is ambiguous: \(names).", node.virtualPath, line)
            case .cycle:
                throw failure(.includeCycle, "Shader include '\(path)' forms a cycle.", node.virtualPath, line)
            case let .failed(reason):
                let code: DiagnosticCode = reason == .missing ? .missingInclude : .rejectedInclude
                throw failure(code, "Shader include '\(path)' failed: \(reason.rawValue).", node.virtualPath, line)
            case .graphBudgetExceeded:
                throw failure(.budgetExceeded, "Shader include graph exceeds its budget.", node.virtualPath, line)
            }
        }

        mutating func append(_ lineText: String, path: String, line: Int) throws {
            let addedBytes = lineText.utf8.count + (outputLines.isEmpty ? 0 : 1)
            guard outputLines.count < limits.maximumOutputLines,
                  outputBytes + addedBytes <= limits.maximumOutputBytes else {
                throw failure(.budgetExceeded, "Prepared shader output exceeds its budget.", path, line)
            }
            outputBytes += addedBytes
            outputLines.append(lineText)
            sourceMap.append(.init(outputLine: outputLines.count, sourcePath: path, sourceLine: line))
        }

        mutating func expand(_ line: SceneShaderLexicalLine, path: String, line lineNumber: Int) throws -> String {
            do {
                return try SceneShaderLexicalExpander.expand(
                    line,
                    objectMacros: macros,
                    functionMacros: functionMacros,
                    limits: limits
                ) { name in
                    if let requirement = SceneShaderVariantEnvironment.unresolvedRequirement(for: name) {
                        throw Failure(diagnostics: [Diagnostic(
                            code: .unresolvedEnvironmentDefine,
                            message: "Shader macro '\(name)' requires an explicit \(requirement.rawValue) source.",
                            relativePath: path,
                            line: lineNumber
                        )])
                    }
                }
            } catch let error as SceneShaderMacroExpansionError {
                let code: DiagnosticCode = error.kind == .budgetExceeded
                    ? .budgetExceeded : .functionLikeMacro
                throw failure(code, error.message, path, lineNumber)
            }
        }

        func sourceFailure(
            _ diagnostics: [SceneShaderContract.Diagnostic], fallbackPath: String
        ) -> Failure {
            Failure(diagnostics: diagnostics.map {
                Diagnostic(
                    code: $0.code == .unterminatedBlockComment
                        ? .unterminatedBlockComment
                        : .malformedSourceAnnotation,
                    message: $0.message,
                    relativePath: $0.relativePath ?? fallbackPath,
                    line: $0.line
                )
            })
        }

        func evaluate(_ expression: String, path: String, line: Int) throws -> Bool {
            do {
                let tokens = try ExpressionLexer.tokenize(expression, limit: limits.maximumExpressionTokens)
                for case let .identifier(name) in tokens
                    where name != "defined" && macros[name] == nil && functionMacros[name] == nil {
                    if let requirement = SceneShaderVariantEnvironment.unresolvedRequirement(for: name) {
                        throw unresolvedEnvironment(name, requirement, path, line)
                    }
                }
                var parser = ExpressionParser(
                    tokens: tokens,
                    macros: macros,
                    definedNames: Set(macros.keys).union(functionMacros.keys)
                )
                return try parser.parse() != 0
            } catch let failure as Failure {
                throw failure
            } catch let error as ExpressionError {
                throw failure(.invalidExpression, error.message, path, line)
            }
        }

        func failure(
            _ code: DiagnosticCode,
            _ message: String,
            _ path: String,
            _ line: Int? = nil
        ) -> Failure {
            .init(diagnostics: [
                .init(code: code, message: message, relativePath: path, line: line),
            ])
        }

        func unresolvedEnvironment(
            _ name: String,
            _ requirement: SceneShaderEnvironmentRequirement,
            _ path: String,
            _ line: Int
        ) -> Failure {
            failure(.unresolvedEnvironmentDefine, "Shader macro '\(name)' requires an explicit "
                + "\(requirement.rawValue) source.", path, line)
        }
    }
}
