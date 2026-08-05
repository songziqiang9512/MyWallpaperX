import Foundation

nonisolated struct SceneShaderVariantSchemaSource: Codable, Equatable, Sendable {
    let relativePath: String
    let annotations: [SceneShaderContract.Annotation]
    let declarations: [SceneShaderContract.Declaration]

    init(stage: SceneShaderContract.Stage) {
        relativePath = stage.relativePath
        annotations = stage.annotations
        declarations = stage.declarations
    }

    init(
        relativePath: String,
        annotations: [SceneShaderContract.Annotation],
        declarations: [SceneShaderContract.Declaration]
    ) {
        self.relativePath = relativePath
        self.annotations = annotations
        self.declarations = declarations
    }
}

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
                    case .elseDirective:
                        guard !conditionalElse.isEmpty,
                              conditionalElse[conditionalElse.count - 1] == false else { return }
                        conditionalElse[conditionalElse.count - 1] = true
                    case .endif:
                        guard !conditionalElse.isEmpty else { return }
                        conditionalElse.removeLast()
                    case .include(let includePath) where conditionalElse.isEmpty:
                        includes.append((line, includePath))
                    case .define, .defineFunction, .undef, .include:
                        break
                    case .unsupported, .unknown, .unsupportedFunctionMacro, .malformed:
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

extension SceneShaderVariantResolver {
    nonisolated struct Schema: Equatable {
        nonisolated enum Origin: Equatable {
            case authoredCombo
            case textureReadiness(slot: Int)
        }

        let combo: String
        let defaultValue: Int64?
        let options: Set<Int64>?
        let requirements: [String: Int64]
        let requireAny: Bool
        let origin: Origin

        var samplerSlot: Int? {
            guard case let .textureReadiness(slot) = origin else { return nil }
            return slot
        }

        var isAuthoredComboMarker: Bool { origin == .authoredCombo }
    }

    nonisolated static func schemas(
        in source: SceneShaderVariantSchemaSource
    ) throws -> [Schema] {
        let declarations = Dictionary(grouping: source.declarations, by: \.line)
        return try source.annotations.compactMap { annotation in
            let markerRequiresCombo = annotation.marker != nil
                && annotation.marker != "[PASS]"
            guard case .object(let object) = annotation.variantValue else {
                if markerRequiresCombo {
                    throw Failure(
                        code: .invalidAnnotation,
                        combo: nil,
                        message: "Shader combo marker requires an object payload."
                    )
                }
                return nil
            }
            guard let comboValue = object["combo"] else {
                if markerRequiresCombo {
                    throw Failure(
                        code: .invalidAnnotation,
                        combo: nil,
                        message: "Shader combo marker requires a combo identifier."
                    )
                }
                return nil
            }
            guard let combo = comboValue.stringValue,
                  !combo.isEmpty else {
                throw Failure(
                    code: .invalidAnnotation,
                    combo: comboValue.stringValue,
                    message: "Shader combo annotation has no valid identifier."
                )
            }
            if isDisabled(annotation.marker) {
                throw Failure(
                    code: .disabledComboAnnotation,
                    combo: combo,
                    message: "Disabled shader combo annotation is recognized but not enabled."
                )
            }
            let requireAny: Bool
            if let rawRequireAny = object["requireany"] {
                guard let value = rawRequireAny.boolValue else {
                    throw Failure(
                        code: .invalidAnnotation,
                        combo: combo,
                        message: "Shader combo requireany must be a boolean."
                    )
                }
                requireAny = value
            } else {
                requireAny = false
            }
            let requirements = try requirements(object["require"], combo: combo)
            if annotation.marker == "[COMBO]" {
                return Schema(
                    combo: combo,
                    defaultValue: try integer(object["default"], combo: combo),
                    options: try options(object["options"], combo: combo),
                    requirements: requirements,
                    requireAny: requireAny,
                    origin: .authoredCombo
                )
            }
            guard annotation.marker == nil,
                  let slot = declarations[annotation.line]?
                    .compactMap(samplerSlot).first else {
                throw Failure(
                    code: .invalidAnnotation,
                    combo: combo,
                    message: "Unmarked shader combo metadata must belong to a texture sampler."
                )
            }
            return Schema(
                combo: combo,
                defaultValue: nil,
                options: nil,
                requirements: requirements,
                requireAny: requireAny,
                origin: .textureReadiness(slot: slot)
            )
        }
    }

    private nonisolated static func integer(
        _ value: SceneShaderAnnotationValue?,
        combo: String
    ) throws -> Int64? {
        guard let value else { return nil }
        if let bool = value.boolValue { return bool ? 1 : 0 }
        guard let integer = value.integerValue else {
            throw Failure(
                code: .invalidAnnotation,
                combo: combo,
                message: "Shader combo value must be an integer or boolean."
            )
        }
        return integer
    }

    private nonisolated static func options(
        _ value: SceneShaderAnnotationValue?,
        combo: String
    ) throws -> Set<Int64>? {
        guard let value else { return nil }
        let values: [SceneShaderAnnotationValue]
        switch value {
        case .array(let array): values = array
        case .object(let object): values = Array(object.values)
        default:
            throw Failure(
                code: .invalidAnnotation,
                combo: combo,
                message: "Shader combo options must be an array or object."
            )
        }
        let parsed = try values.map { try integer($0, combo: combo)! }
        return Set(parsed)
    }

    private nonisolated static func requirements(
        _ value: SceneShaderAnnotationValue?,
        combo: String
    ) throws -> [String: Int64] {
        guard let value else { return [:] }
        guard case .object(let object) = value else {
            throw Failure(
                code: .invalidAnnotation,
                combo: combo,
                message: "Shader combo requirements must be an object."
            )
        }
        var result: [String: Int64] = [:]
        for (name, raw) in object {
            guard let parsed = try integer(raw, combo: combo) else {
                throw Failure(
                    code: .invalidAnnotation,
                    combo: combo,
                    message: "Shader combo requirement has no value."
                )
            }
            result[name] = parsed
        }
        return result
    }

    private nonisolated static func samplerSlot(
        _ declaration: SceneShaderContract.Declaration
    ) -> Int? {
        guard declaration.kind == .uniform,
              declaration.type.caseInsensitiveCompare("sampler2D") == .orderedSame,
              declaration.name.hasPrefix("g_Texture"),
              let slot = Int(declaration.name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else { return nil }
        return slot
    }

    private nonisolated static func isDisabled(_ marker: String?) -> Bool {
        guard let marker else { return false }
        return ["[COMBO_DISABLED]", "[OFF_COMBO]", "[COMBO_OFF]"]
            .contains(marker)
    }
}
