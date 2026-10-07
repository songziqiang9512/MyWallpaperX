import Foundation

extension SceneResolvedMaterialShaderSchema {
    /// Proves literal, unconditional model-channel metadata without preparing
    /// unrelated samplers or admitting the shader's executable expressions.
    /// Conditional, include or macro ambiguity leaves the old model route.
    nonisolated static func unconditionalStaticModelUniforms(
        _ fields: [SceneAuthoredShaderUniformLayout.Field],
        contract: SceneShaderContract,
        explicitCombos: [String: Int] = [:]
    ) -> [String: Uniform]? {
        guard let records = staticModelInterfaceRecords(
            contract: contract, explicitCombos: explicitCombos
        ) else { return nil }
        var result: [String: Uniform] = [:]
        for field in fields {
            guard field.stage == .fragment else { return nil }
            let matches = records.potential.filter {
                $0.declaration.kind == .uniform && $0.declaration.name == field.authoredName
            }
            let fragment = matches.filter { $0.stage == .fragment }
            let vertex = matches.filter { $0.stage == .vertex }
            guard fragment.count == 1, vertex.count <= 1,
                  matches.allSatisfy({ record in
                      record.declaration.arraySuffix == nil
                          && record.declaration.arraySize == nil
                          && SceneAuthoredShaderValueType(
                              authoredName: record.declaration.type
                          ) == field.type
                          && records.unconditional.contains(where: {
                              $0.stage == record.stage && $0.sourcePath == record.sourcePath
                                  && $0.declaration == record.declaration
                          })
                  }),
                  let schema = try? uniformSchema(field, records: records.potential) else { return nil }
            if !vertex.isEmpty {
                let vertexField = SceneAuthoredShaderUniformLayout.Field(
                    name: field.authoredName, stage: .vertex, type: field.type, offset: 0
                )
                guard let vertexSchema = try? uniformSchema(
                    vertexField, records: records.potential
                ), vertexSchema.materialKeys == schema.materialKeys,
                   vertexSchema.defaultValue == schema.defaultValue else { return nil }
            }
            // A potential conditional owner still makes an unconditional key
            // ambiguous. Use the existing exact annotation projection for both.
            for record in records.potential where record.declaration.kind == .uniform
                && !isSampler2D(record.declaration.type)
                && record.declaration.name != field.authoredName
            {
                let other = SceneAuthoredShaderUniformLayout.Field(
                    name: record.declaration.name, stage: record.stage,
                    type: SceneAuthoredShaderValueType(authoredName: record.declaration.type)
                        ?? .float,
                    offset: 0
                )
                guard let owner = try? uniformSchema(
                    other, records: records.potential
                ), Set(owner.materialKeys).isDisjoint(with: schema.materialKeys) else { return nil }
            }
            guard result.updateValue(schema, forKey: field.authoredName) == nil else { return nil }
        }
        return result
    }

    private nonisolated static func staticModelInterfaceRecords(
        contract: SceneShaderContract,
        explicitCombos: [String: Int]
    ) -> (unconditional: [Record], potential: [Record])? {
        guard contract.sourceKind == .authoredSource, contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              Set(contract.stages.map { $0.kind.rawValue }) == Set([
                  SceneShaderContract.StageKind.vertex.rawValue,
                  SceneShaderContract.StageKind.fragment.rawValue,
              ]),
              let graph = contract.sourceGraph,
              graph.dependencySHA256 == graph.recomputedDependencySHA256,
              graph.diagnostics.allSatisfy({ $0.code == .shadowedRootContentConflict }),
              Set(graph.nodes.map { $0.virtualPath.lowercased() }).count == graph.nodes.count,
              graph.edges.allSatisfy({
                  if case let .resolved(path) = $0.outcome { return graph.node(at: path) != nil }
                  return false
              }) else { return nil }
        let parsed = Dictionary(uniqueKeysWithValues: graph.nodes.map { node in
            (node.virtualPath.lowercased(), SceneShaderContractSourceParser().parse(
                node.source, stageRelativePath: node.virtualPath
            ))
        })
        var protected = Set(["uniform", "attribute", "varying", "float", "vec3"])
        for projection in parsed.values {
            guard projection.diagnostics.isEmpty else { return nil }
            for declaration in projection.declarations {
                protected.insert(declaration.name)
                protected.insert(declaration.type)
            }
        }
        var environmentNames = Set(explicitCombos.keys)
            .union(SceneShaderCompatibilityTarget.windowsDX11ShaderModel4
                .languageMacroBindings.map(\.name))
        for node in graph.nodes {
            guard let projection = parsed[node.virtualPath.lowercased()],
                  let schemas = try? SceneShaderVariantResolver.schemas(in: .init(
                    relativePath: node.virtualPath, source: node.source,
                    annotations: projection.annotations, declarations: projection.declarations
                  )) else { return nil }
            environmentNames.formUnion(schemas.map(\.combo))
        }
        guard environmentNames.isDisjoint(with: protected) else { return nil }
        for node in graph.nodes {
            guard node.byteCount == node.source.utf8.count,
                  node.rawSHA256 == SceneShaderStableDigest.hash(Data(node.source.utf8)),
                  staticModelDirectivesAreSafe(node, graph: graph, protected: protected) else { return nil }
        }
        var unconditional: [Record] = []
        var potential: [Record] = []
        for stage in contract.stages {
            guard let root = graph.node(at: stage.relativePath),
                  root.source == stage.source, root.rawSHA256 == stage.rawSHA256 else { return nil }
            var visited: Set<String> = []
            func collect(_ path: String) -> Bool {
                let identity = path.lowercased()
                guard visited.insert(identity).inserted,
                      let node = graph.node(at: path),
                      let projection = parsed[identity] else { return false }
                potential.append(contentsOf: projection.declarations.map { declaration in
                    Record(
                        stage: stage.kind, sourcePath: node.virtualPath,
                        declaration: declaration,
                        annotations: projection.annotations.filter { $0.line == declaration.line }
                    )
                })
                for include in projection.includes {
                    guard let edge = graph.edge(parentVirtualPath: path, line: include.line),
                          edge.request == include.relativePath,
                          case let .resolved(child) = edge.outcome,
                          collect(child) else { return false }
                }
                return true
            }
            guard collect(stage.relativePath) else { return nil }
            for source in SceneShaderVariantSchemaSeed.unconditional(
                rootRelativePath: stage.relativePath, graph: graph
            ) {
                unconditional.append(contentsOf: source.declarations.map { declaration in
                    Record(
                        stage: stage.kind, sourcePath: source.relativePath,
                        declaration: declaration,
                        annotations: source.annotations.filter { $0.line == declaration.line }
                    )
                })
            }
        }
        return (unconditional, potential)
    }

    private nonisolated static func staticModelDirectivesAreSafe(
        _ node: SceneShaderSourceGraph.Node,
        graph: SceneShaderSourceGraph,
        protected: Set<String>
    ) -> Bool {
        var inBlockComment = false
        var sawElse: [Bool] = []
        for (index, line) in node.source.split(
            omittingEmptySubsequences: false, whereSeparator: \.isNewline
        ).enumerated() {
            let code = SceneShaderLexicalScanner.scan(
                String(line), inBlockComment: &inBlockComment
            ).code
            guard let directive = SceneShaderDirective.parse(code) else {
                let storage = SceneShaderSourceTextFacts.matches(
                    #"(?i)\b(?:uniform|attribute|varying)\b"#, in: code
                )
                if !storage.isEmpty {
                    let declarations = SceneShaderContractSourceParser().parse(
                        code, stageRelativePath: node.virtualPath
                    ).declarations
                    guard storage.count == 1, declarations.count == 1,
                          (code as NSString).substring(with: storage[0].range)
                            == declarations[0].kind.rawValue,
                          code.filter({ $0 == ";" }).count == 1,
                          code.trimmingCharacters(in: .whitespaces).last == ";" else { return false }
                }
                continue
            }
            switch directive {
            case let .define(name, value):
                guard !protected.contains(name) else { return false }
                if case let .tokenSequence(replacement) = value,
                   SceneShaderSourceTextFacts.matches(
                    #"\b(?:uniform|attribute|varying)\b"#, in: replacement
                   ).isEmpty == false { return false }
            case let .undef(name):
                guard !protected.contains(name) else { return false }
            case let .include(path):
                guard let edge = graph.edge(parentVirtualPath: node.virtualPath, line: index + 1),
                      edge.request == path, case .resolved = edge.outcome else { return false }
            case let .ifExpression(expression), let .elifExpression(expression):
                guard (try? SceneShaderPreprocessor.ExpressionLexer.tokenize(
                    expression, limit: 512
                )) != nil else { return false }
                if case .ifExpression = directive { sawElse.append(false) }
                else if sawElse.isEmpty || sawElse.last == true { return false }
            case .ifdef: sawElse.append(false)
            case .elseDirective:
                guard !sawElse.isEmpty, sawElse.last == false else { return false }
                sawElse[sawElse.count - 1] = true
            case .endif:
                guard !sawElse.isEmpty else { return false }
                sawElse.removeLast()
            // A well-formed `#require <module>` (e.g. `#require LightingV1`,
            // present in every stock lighting shader such as generic4) only
            // requests an engine feature module; it never rewrites, renames
            // or conditions the declarations this proof reads. Rejecting it
            // made the whole model-material interface unprovable for every
            // lighting-capable stock shader and rendered those models unlit
            // (3589454154: 23 layers fell back with shader-interface-unproven).
            // Malformed requires and the genuinely rewriting directives stay
            // rejected below.
            case .require:
                continue
            case .defineFunction, .malformedRequire, .unsupported,
                 .unknown, .unsupportedFunctionMacro, .malformed:
                return false
            }
        }
        return !inBlockComment && sawElse.isEmpty
    }
}
