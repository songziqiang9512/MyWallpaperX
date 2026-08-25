import Foundation

/// Conservative bootstrap for the active-schema fixed point. Metadata outside
/// conditional regions and metadata from unconditional includes form the
/// normal seed. One conditional exception is source-proven: a sampler may seed
/// its own texture-readiness combo when its sole guard is that exact combo's
/// positive branch. The actual slot readiness still selects the branch.
nonisolated enum SceneShaderVariantSchemaSeed {
    static func unconditional(
        contract: SceneShaderContract,
        graph: SceneShaderSourceGraph
    ) -> [SceneShaderVariantSchemaSource] {
        var collector = Collector(graph: graph)
        for stage in contract.stages {
            collector.collect(stage.relativePath)
        }
        return collector.sources
    }

    static func ambiguityProbeSeeds(
        baseSources: [SceneShaderVariantSchemaSource],
        graph: SceneShaderSourceGraph,
        limit: Int
    ) -> [[SceneShaderVariantSchemaSource]]? {
        let baseIdentities = Set(baseSources.flatMap { source in
            source.annotations.map {
                SceneShaderMetadataIdentity.annotation($0, path: source.relativePath)
            }
        })
        guard let candidates = allCandidates(
            in: graph,
            excluding: baseIdentities,
            limit: limit
        ) else { return nil }
        let probeCount = (1 << candidates.count) - 1
        let graphBytes = graph.nodes.reduce(0) { $0 + $1.byteCount }
        guard graphBytes == 0
                || probeCount <= 256 * 1_024 * 1_024 / 16 / graphBytes else { return nil }
        return (1 ..< probeCount + 1).map { mask in
            candidates.enumerated().reduce(baseSources) { sources, item in
                guard mask & (1 << item.offset) != 0 else { return sources }
                return merging(item.element, into: sources)
            }
        }
    }

    private static func allCandidates(
        in graph: SceneShaderSourceGraph,
        excluding baseIdentities: Set<String>,
        limit: Int
    ) -> [SceneShaderVariantSchemaSource]? {
        var result: [SceneShaderVariantSchemaSource] = []
        for node in graph.nodes.sorted(by: { $0.virtualPath < $1.virtualPath }) {
            let parsed = SceneShaderContractSourceParser().parse(
                node.source,
                stageRelativePath: node.virtualPath
            )
            let declarationsByLine = Dictionary(grouping: parsed.declarations, by: \.line)
            for annotation in parsed.annotations {
                let identity = SceneShaderMetadataIdentity.annotation(
                    annotation,
                    path: node.virtualPath
                )
                guard !baseIdentities.contains(identity) else { continue }
                let source = SceneShaderVariantSchemaSource(
                    relativePath: node.virtualPath,
                    source: node.source,
                    annotations: [annotation],
                    declarations: declarationsByLine[annotation.line] ?? []
                )
                guard let schemas = try? SceneShaderVariantResolver.schemas(in: source),
                      !schemas.isEmpty else { continue }
                result.append(source)
                guard result.count <= limit else { return nil }
            }
        }
        return result
    }

    private static func merging(
        _ candidate: SceneShaderVariantSchemaSource,
        into sources: [SceneShaderVariantSchemaSource]
    ) -> [SceneShaderVariantSchemaSource] {
        var result = sources
        if let index = result.firstIndex(where: {
            $0.relativePath == candidate.relativePath
        }) {
            let existing = result[index]
            result[index] = .init(
                relativePath: existing.relativePath,
                source: existing.source,
                annotations: existing.annotations + candidate.annotations.filter {
                    !existing.annotations.contains($0)
                },
                declarations: existing.declarations + candidate.declarations.filter {
                    !existing.declarations.contains($0)
                }
            )
        } else {
            result.append(candidate)
        }
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    private struct Collector {
        private struct SelfGatedReadinessCandidate {
            let annotation: SceneShaderContract.Annotation
            let declaration: SceneShaderContract.Declaration
        }

        private struct ConditionalFrame {
            var selfGatedReadinessCombo: String?
            var reachedElse = false
            var candidates: [SelfGatedReadinessCandidate] = []
        }

        let graph: SceneShaderSourceGraph
        var visited: Set<String> = []
        var annotations: [String: [SceneShaderContract.Annotation]] = [:]
        var declarations: [String: [SceneShaderContract.Declaration]] = [:]

        var sources: [SceneShaderVariantSchemaSource] {
            graph.nodes.sorted { $0.virtualPath < $1.virtualPath }.map { node in
                .init(
                    relativePath: node.virtualPath,
                    source: node.source,
                    annotations: annotations[node.virtualPath] ?? [],
                    declarations: declarations[node.virtualPath] ?? []
                )
            }
        }

        mutating func collect(_ path: String) {
            guard visited.insert(path.lowercased()).inserted,
                  let node = graph.node(at: path) else { return }
            let parsed = SceneShaderContractSourceParser().parse(
                node.source,
                stageRelativePath: node.virtualPath
            )
            let annotationsByLine = Dictionary(grouping: parsed.annotations, by: \.line)
            let declarationsByLine = Dictionary(grouping: parsed.declarations, by: \.line)
            var localAnnotations: [SceneShaderContract.Annotation] = []
            var localDeclarations: [SceneShaderContract.Declaration] = []
            var includes: [(line: Int, path: String)] = []
            var conditionalFrames: [ConditionalFrame] = []
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
                    case .ifExpression(let expression):
                        conditionalFrames.append(
                            .init(selfGatedReadinessCombo: Self.positiveUnitCombo(in: expression))
                        )
                    case .ifdef(_, _):
                        conditionalFrames.append(.init(selfGatedReadinessCombo: nil))
                    case .elifExpression:
                        guard !conditionalFrames.isEmpty,
                              !conditionalFrames[conditionalFrames.count - 1].reachedElse else { return }
                        conditionalFrames[conditionalFrames.count - 1]
                            .selfGatedReadinessCombo = nil
                        conditionalFrames[conditionalFrames.count - 1].candidates.removeAll()
                    case .elseDirective:
                        guard !conditionalFrames.isEmpty,
                              !conditionalFrames[conditionalFrames.count - 1].reachedElse else { return }
                        conditionalFrames[conditionalFrames.count - 1].reachedElse = true
                        conditionalFrames[conditionalFrames.count - 1]
                            .selfGatedReadinessCombo = nil
                        conditionalFrames[conditionalFrames.count - 1].candidates.removeAll()
                    case .endif:
                        guard !conditionalFrames.isEmpty else { return }
                        let frame = conditionalFrames.removeLast()
                        if conditionalFrames.isEmpty,
                           frame.selfGatedReadinessCombo != nil,
                           !frame.reachedElse {
                            localAnnotations.append(contentsOf: frame.candidates.map(\.annotation))
                            localDeclarations.append(contentsOf: frame.candidates.map(\.declaration))
                        }
                    case .include(let includePath) where conditionalFrames.isEmpty:
                        includes.append((line, includePath))
                    case .define, .defineFunction, .undef, .include, .require:
                        break
                    case .malformedRequire, .unsupported, .unknown,
                         .unsupportedFunctionMacro, .malformed:
                        return
                    }
                    continue
                }
                if lexical.code.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    return
                }
                if conditionalFrames.isEmpty {
                    localAnnotations.append(contentsOf: annotationsByLine[line] ?? [])
                    localDeclarations.append(contentsOf: declarationsByLine[line] ?? [])
                } else if conditionalFrames.count == 1,
                          let gate = conditionalFrames[0].selfGatedReadinessCombo,
                          let candidate = Self.selfGatedReadinessCandidate(
                              gate: gate,
                              path: node.virtualPath,
                              source: node.source,
                              annotations: annotationsByLine[line] ?? [],
                              declarations: declarationsByLine[line] ?? []
                          ) {
                    conditionalFrames[0].candidates.append(candidate)
                }
            }
            guard !inBlockComment, conditionalFrames.isEmpty else { return }
            annotations[node.virtualPath] = localAnnotations
            declarations[node.virtualPath] = localDeclarations
            for include in includes {
                guard let edge = graph.edge(
                          parentVirtualPath: node.virtualPath,
                          line: include.line
                      ),
                      edge.request == include.path,
                      case let .resolved(childPath) = edge.outcome else { continue }
                collect(childPath)
            }
        }

        private static func positiveUnitCombo(in expression: String) -> String? {
            guard let tokens = try? SceneShaderPreprocessor.ExpressionLexer
                .tokenize(expression, limit: 8) else { return nil }
            if tokens.count == 2,
               case let .identifier(name) = tokens[0],
               tokens[1] == .end {
                return name
            }
            if tokens.count == 4,
               case let .identifier(name) = tokens[0],
               tokens[1] == .equal,
               tokens[2] == .number(1),
               tokens[3] == .end {
                return name
            }
            if tokens.count == 4,
               tokens[0] == .number(1),
               tokens[1] == .equal,
               case let .identifier(name) = tokens[2],
               tokens[3] == .end {
                return name
            }
            return nil
        }

        private static func selfGatedReadinessCandidate(
            gate: String,
            path: String,
            source: String,
            annotations: [SceneShaderContract.Annotation],
            declarations: [SceneShaderContract.Declaration]
        ) -> SelfGatedReadinessCandidate? {
            guard declarations.count == 1, let declaration = declarations.first else {
                return nil
            }
            let matches = annotations.compactMap { annotation -> SceneShaderContract.Annotation? in
                let candidate = SceneShaderVariantSchemaSource(
                    relativePath: path,
                    source: source,
                    annotations: [annotation],
                    declarations: [declaration]
                )
                guard let schemas = try? SceneShaderVariantResolver.schemas(in: candidate),
                      schemas.count == 1, let schema = schemas.first,
                      schema.combo == gate,
                      schema.requirements.isEmpty,
                      !schema.requireAny,
                      case .textureReadiness = schema.origin else { return nil }
                return annotation
            }
            guard matches.count == 1, let annotation = matches.first else { return nil }
            return .init(annotation: annotation, declaration: declaration)
        }
    }
}
