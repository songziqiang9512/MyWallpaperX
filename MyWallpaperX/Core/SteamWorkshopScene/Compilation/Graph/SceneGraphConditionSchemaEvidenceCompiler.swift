import Foundation

/// Projects only stable zero-valued authored combo defaults into graph
/// admission. Runtime readiness, format, disabled, ambiguous, and nonzero
/// schemas never become an implicit condition provider.
nonisolated enum SceneGraphConditionSchemaEvidenceCompiler {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Evidence = SceneGraphConditionSchemaEvidence

    private struct ContractFacts {
        let stableZeroKeys: Set<String>
        let unsafeKeys: Set<String>
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        authoredPlans: [Graph],
        shaderContracts: [SceneShaderContract]
    ) -> [Graph.EffectKey: Evidence] {
        let records = Dictionary(grouping: authoredPlans.flatMap { graph in
            graph.effects.map { (key: $0.key, graph: graph, effect: $0) }
        }, by: { $0.key })
        var result: [Graph.EffectKey: Evidence] = [:]
        for key in records.keys.sorted(by: less) {
            guard let matches = records[key], matches.count == 1,
                  let record = matches.first,
                  let evidence = evidence(
                      graph: record.graph,
                      effect: record.effect,
                      descriptor: descriptor,
                      shaderContracts: shaderContracts
                  ) else { continue }
            result[key] = evidence
        }
        return result
    }

    private static func evidence(
        graph: Graph,
        effect: Graph.Effect,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> Evidence? {
        guard graph.layerID == effect.key.layerID,
              let layer = unique(descriptor.layers.filter { $0.id == graph.layerID }),
              layer.effects.indices.contains(effect.key.effectIndex),
              layer.effects[effect.key.effectIndex].id == effect.key.descriptorID else {
            return nil
        }
        let nodes = graph.nodes.filter { $0.effect == effect.key && $0.kind == .material }
        guard !nodes.isEmpty else { return nil }

        var stableZeroKeys: Set<String> = []
        var unsafeKeys: Set<String> = []
        for node in nodes {
            guard let materialID = node.materialPassID,
                  let material = unique(descriptor.materialPasses.filter {
                      $0.id == materialID
                  }), normalized(material.materialPath) == normalized(node.materialPath ?? ""),
                  let shaderPath = material.shaderPath,
                  let contract = unique(shaderContracts.filter {
                      normalized($0.identity) == normalized(shaderPath)
                  }), let facts = contractFacts(contract) else { return nil }
            stableZeroKeys.formUnion(facts.stableZeroKeys)
            unsafeKeys.formUnion(facts.unsafeKeys)
        }
        stableZeroKeys.subtract(unsafeKeys)
        return Evidence(keysProvenZeroWhenMissing: stableZeroKeys)
    }

    private static func contractFacts(_ contract: SceneShaderContract) -> ContractFacts? {
        guard contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              Set(contract.stages.map(\.kind)) == Set([.vertex, .fragment]),
              let graph = contract.sourceGraph,
              graph.diagnostics.isEmpty else { return nil }
        var collector = UnconditionalEvidenceCollector(graph: graph)
        guard contract.stages.allSatisfy({ collector.collect($0.relativePath) }) else {
            return nil
        }
        let base = collector.sources
        guard let probes = SceneShaderVariantSchemaSeed.ambiguityProbeSeeds(
            baseSources: base,
            graph: graph,
            limit: 8
        ) else { return nil }

        var stable: Set<String>?
        var declared: Set<String> = []
        for seed in [base] + probes {
            let schemas: [SceneShaderVariantResolver.Schema]
            do {
                schemas = try seed.flatMap(SceneShaderVariantResolver.schemas(in:))
            } catch {
                return nil
            }
            let grouped = Dictionary(grouping: schemas, by: \.combo)
            let safe = Set(grouped.compactMap { name, values in
                values.allSatisfy { schema in
                    schema.origin == .authoredCombo
                        && schema.defaultValue == 0
                        && (schema.options?.contains(0) ?? true)
                } ? name : nil
            })
            declared.formUnion(grouped.keys)
            stable = stable.map { $0.intersection(safe) } ?? safe
        }
        let stableZeroKeys = stable ?? []
        return .init(
            stableZeroKeys: stableZeroKeys,
            unsafeKeys: declared.subtracting(stableZeroKeys)
        )
    }

    /// Evidence admission needs the lexical location of an authored schema,
    /// even when a later independent requirement directive is not part of the
    /// shader preprocessor's bootstrap vocabulary. Structural uncertainty still
    /// rejects the contract, and conditional annotations remain probe-only.
    private struct UnconditionalEvidenceCollector {
        let graph: SceneShaderSourceGraph
        var visited: Set<String> = []
        var annotations: [String: [SceneShaderContract.Annotation]] = [:]
        var declarations: [String: [SceneShaderContract.Declaration]] = [:]

        var sources: [SceneShaderVariantSchemaSource] {
            Set(annotations.keys).union(declarations.keys).sorted().map { path in
                .init(
                    relativePath: path,
                    annotations: annotations[path] ?? [],
                    declarations: declarations[path] ?? []
                )
            }
        }

        mutating func collect(_ path: String) -> Bool {
            let identity = path.lowercased()
            guard !visited.contains(identity) else { return true }
            visited.insert(identity)
            guard let node = graph.node(at: path) else { return false }
            let parsed = SceneShaderContractSourceParser().parse(
                node.source,
                stageRelativePath: node.virtualPath
            )
            let annotationsByLine = Dictionary(grouping: parsed.annotations, by: \.line)
            let declarationsByLine = Dictionary(grouping: parsed.declarations, by: \.line)
            var localAnnotations: [SceneShaderContract.Annotation] = []
            var localDeclarations: [SceneShaderContract.Declaration] = []
            var includes: [(line: Int, path: String)] = []
            var conditionalElse: [Bool] = []
            var inBlockComment = false
            let lines = node.source.split(
                omittingEmptySubsequences: false,
                whereSeparator: { $0.isNewline }
            )

            for (offset, substring) in lines.enumerated() {
                let line = offset + 1
                let lexical = SceneShaderLexicalScanner.scan(
                    String(substring),
                    inBlockComment: &inBlockComment
                )
                if let directive = SceneShaderDirective.parse(lexical.code) {
                    switch directive {
                    case .ifExpression, .ifdef:
                        conditionalElse.append(false)
                    case .elifExpression:
                        guard !conditionalElse.isEmpty,
                              conditionalElse[conditionalElse.count - 1] == false else {
                            return false
                        }
                    case .elseDirective:
                        guard !conditionalElse.isEmpty,
                              conditionalElse[conditionalElse.count - 1] == false else {
                            return false
                        }
                        conditionalElse[conditionalElse.count - 1] = true
                    case .endif:
                        guard !conditionalElse.isEmpty else { return false }
                        conditionalElse.removeLast()
                    case .include(let includePath) where conditionalElse.isEmpty:
                        includes.append((line, includePath))
                    case .define, .defineFunction, .undef, .include, .require:
                        break
                    case .malformedRequire, .unsupported, .unknown,
                         .unsupportedFunctionMacro, .malformed:
                        return false
                    }
                    continue
                }
                if lexical.code.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    return false
                }
                guard conditionalElse.isEmpty else { continue }
                localAnnotations.append(contentsOf: annotationsByLine[line] ?? [])
                localDeclarations.append(contentsOf: declarationsByLine[line] ?? [])
            }
            guard !inBlockComment, conditionalElse.isEmpty else { return false }
            annotations[node.virtualPath] = localAnnotations
            declarations[node.virtualPath] = localDeclarations
            for include in includes {
                guard let edge = graph.edge(
                          parentVirtualPath: node.virtualPath,
                          line: include.line
                      ),
                      edge.request == include.path,
                      case let .resolved(childPath) = edge.outcome,
                      collect(childPath) else { return false }
            }
            return true
        }
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func unique<T>(_ values: [T]) -> T? {
        values.count == 1 ? values[0] : nil
    }

    private static func less(_ lhs: Graph.EffectKey, _ rhs: Graph.EffectKey) -> Bool {
        (lhs.layerID, lhs.effectIndex, lhs.descriptorID)
            < (rhs.layerID, rhs.effectIndex, rhs.descriptorID)
    }
}
