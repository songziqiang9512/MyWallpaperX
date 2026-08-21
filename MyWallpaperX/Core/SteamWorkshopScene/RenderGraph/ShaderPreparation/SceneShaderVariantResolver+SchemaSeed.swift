import Foundation

/// Conservative bootstrap for the active-schema fixed point. Only metadata
/// outside conditional regions, plus metadata from unconditional includes, may
/// influence the first variant. Conditional metadata is discovered by the
/// normal preprocess/resolve iterations after its provider facts are known.
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
                              conditionalElse[conditionalElse.count - 1] == false else { return }
                    case .elseDirective:
                        guard !conditionalElse.isEmpty,
                              conditionalElse[conditionalElse.count - 1] == false else { return }
                        conditionalElse[conditionalElse.count - 1] = true
                    case .endif:
                        guard !conditionalElse.isEmpty else { return }
                        conditionalElse.removeLast()
                    case .include(let includePath) where conditionalElse.isEmpty:
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
                guard conditionalElse.isEmpty else { continue }
                localAnnotations.append(contentsOf: annotationsByLine[line] ?? [])
                localDeclarations.append(contentsOf: declarationsByLine[line] ?? [])
            }
            guard !inBlockComment, conditionalElse.isEmpty else { return }
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
    }
}
