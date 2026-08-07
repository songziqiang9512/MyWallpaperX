import Foundation

nonisolated struct SceneAuthoredShaderPreparationFailure {
    let phase: SceneEffectStageCompilerFailure.Phase
    let code: SceneEffectStageCompilerFailure.Code
    let details: [String]
}

nonisolated enum SceneAuthoredShaderPreparationResult<Value> {
    case notApplicable
    case rejected(SceneAuthoredShaderPreparationFailure)
    case accepted(Value)
}

nonisolated enum SceneAuthoredShaderPreparation {
    private nonisolated struct PreparedPair {
        let vertex: SceneShaderPreparedSource
        let fragment: SceneShaderPreparedSource
    }
    private nonisolated struct StablePreparation {
        let pair: PreparedPair
        let signature: String
    }
    private nonisolated struct PreparedProgramIdentity: Encodable {
        let frontendSchemaVersion: Int
        let contractCanonicalSHA256: String
        let vertexPreparedSHA256: String
        let fragmentPreparedSHA256: String
        let colorContract: SceneShaderColorContract
    }

    private nonisolated struct PreparationIterationIdentity: Encodable {
        let vertexPreparedSHA256: String
        let fragmentPreparedSHA256: String
        let activeSchemaSources: [SceneShaderVariantSchemaSource]
    }

    nonisolated static func prepareShaderStages(
        contract: SceneShaderContract,
        combos: [String: Int],
        textureReadiness: [Int: Bool] = [:]
    ) -> SceneAuthoredShaderPreparationResult<SceneShaderPreparedProgram> {
        let graph: SceneShaderSourceGraph
        if let loadedGraph = contract.sourceGraph {
            graph = loadedGraph
        } else if contract.stages.allSatisfy({ $0.includes.isEmpty }) {
            graph = fallbackGraph(for: contract)
        } else {
            return .rejected(failure(
                phase: .shaderPreprocessor,
                code: .shaderSourceGraphMissing
            ))
        }

        for stage in contract.stages {
            guard let node = graph.node(at: stage.relativePath),
                  node.source == stage.source,
                  node.rawSHA256.caseInsensitiveCompare(stage.rawSHA256) == .orderedSame else {
                return .rejected(failure(
                    phase: .shaderPreprocessor,
                    code: .shaderSourceIdentityMismatch,
                    details: [stage.kind.rawValue]
                ))
            }
        }
        // Bootstrap only with lexically unconditional root/include metadata.
        // Conditional graph nodes remain outside the seed and are discovered
        // by the bounded active-schema iterations below.
        let schemaSources = SceneShaderVariantSchemaSeed.unconditional(
            contract: contract,
            graph: graph
        )
        let baselineResult = converge(
            contract: contract,
            graph: graph,
            initialSources: schemaSources,
            combos: combos,
            textureReadiness: textureReadiness
        )
        let baseline: StablePreparation
        switch baselineResult {
        case .accepted(let value): baseline = value
        case .rejected(let failure): return .rejected(failure)
        case .notApplicable:
            return .rejected(failure(
                phase: .invariant,
                code: .shaderPreparationInvariant
            ))
        }
        guard let probeSeeds = SceneShaderVariantSchemaSeed.ambiguityProbeSeeds(
            baseSources: schemaSources,
            graph: graph,
            limit: 8
        ) else { return unstableVariantFailure("active-schema-audit-budget") }
        for probeSeed in probeSeeds {
            if case let .accepted(alternate) = converge(
                contract: contract,
                graph: graph,
                initialSources: probeSeed,
                combos: combos,
                textureReadiness: textureReadiness
            ), alternate.signature != baseline.signature {
                return unstableVariantFailure("active-schema-ambiguous")
            }
        }
        return .accepted(preparedProgram(baseline.pair, contract: contract))
    }

    private nonisolated static func converge(
        contract: SceneShaderContract,
        graph: SceneShaderSourceGraph,
        initialSources: [SceneShaderVariantSchemaSource],
        combos: [String: Int],
        textureReadiness: [Int: Bool]
    ) -> SceneAuthoredShaderPreparationResult<StablePreparation> {
        var schemaSources = initialSources
        var previousSignature: String?
        var signatures: Set<String> = []
        for _ in 0 ..< 8 {
            let result = preparePair(
                contract: contract,
                graph: graph,
                schemaSources: schemaSources,
                combos: combos,
                textureReadiness: textureReadiness
            )
            guard case let .accepted(pair) = result else {
                switch result {
                case .rejected(let failure): return .rejected(failure)
                default: return .notApplicable
                }
            }
            let activeSources = activeSchemaSources(pair)
            let signature = SceneShaderStableDigest.hash(PreparationIterationIdentity(
                vertexPreparedSHA256: pair.vertex.preparedSHA256,
                fragmentPreparedSHA256: pair.fragment.preparedSHA256,
                activeSchemaSources: activeSources
            ))
            if signature == previousSignature {
                return .accepted(.init(
                    pair: pair,
                    signature: signature
                ))
            }
            guard signatures.insert(signature).inserted else {
                return unstableVariantFailure("active-schema-cycle")
            }
            previousSignature = signature
            schemaSources = activeSources
        }
        return unstableVariantFailure("active-schema-budget")
    }

    private nonisolated static func preparePair(
        contract: SceneShaderContract,
        graph: SceneShaderSourceGraph,
        schemaSources: [SceneShaderVariantSchemaSource],
        combos: [String: Int],
        textureReadiness: [Int: Bool]
    ) -> SceneAuthoredShaderPreparationResult<PreparedPair> {
        let vertex = prepare(
            .vertex,
            contract: contract,
            graph: graph,
            schemaSources: schemaSources,
            combos: combos,
            textureReadiness: textureReadiness
        )
        let fragment = prepare(
            .fragment,
            contract: contract,
            graph: graph,
            schemaSources: schemaSources,
            combos: combos,
            textureReadiness: textureReadiness
        )
        switch (vertex, fragment) {
        case let (.accepted(vertex), .accepted(fragment)):
            return .accepted(.init(vertex: vertex, fragment: fragment))
        case let (.rejected(failure), _), let (_, .rejected(failure)):
            return .rejected(failure)
        default:
            return .notApplicable
        }
    }

    private nonisolated static func activeSchemaSources(
        _ pair: PreparedPair
    ) -> [SceneShaderVariantSchemaSource] {
        var annotations: [String: [SceneShaderContract.Annotation]] = [:]
        var declarations: [String: [SceneShaderContract.Declaration]] = [:]
        var seenAnnotations: Set<String> = []
        var seenDeclarations: Set<String> = []
        for stage in [pair.vertex, pair.fragment] {
            for active in stage.activeAnnotations {
                let key = SceneShaderMetadataIdentity.annotation(active.annotation, path: active.sourcePath)
                guard seenAnnotations.insert(key).inserted else { continue }
                annotations[active.sourcePath, default: []].append(active.annotation)
            }
            for active in stage.activeDeclarations {
                let key = SceneShaderMetadataIdentity.declaration(active.declaration, path: active.sourcePath)
                guard seenDeclarations.insert(key).inserted else { continue }
                declarations[active.sourcePath, default: []].append(active.declaration)
            }
        }
        return Set(annotations.keys).union(declarations.keys).sorted().map { path in
            .init(
                relativePath: path,
                annotations: annotations[path] ?? [],
                declarations: declarations[path] ?? []
            )
        }
    }

    private nonisolated static func preparedProgram(
        _ pair: PreparedPair,
        contract: SceneShaderContract
    ) -> SceneShaderPreparedProgram {
        let colorContract = SceneShaderColorContract.unresolvedAuthoredPass
        let identity = PreparedProgramIdentity(
            frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion,
            contractCanonicalSHA256: contract.canonicalSHA256,
            vertexPreparedSHA256: pair.vertex.preparedSHA256,
            fragmentPreparedSHA256: pair.fragment.preparedSHA256,
            colorContract: colorContract
        )
        return .init(
            vertex: pair.vertex,
            fragment: pair.fragment,
            colorContract: colorContract,
            cacheKey: SceneShaderStableDigest.hash(identity)
        )
    }

    private nonisolated static func unstableVariantFailure<Value>(
        _ reason: String
    ) -> SceneAuthoredShaderPreparationResult<Value> {
        .rejected(failure(
            phase: .shaderPreprocessor,
            code: .shaderVariantInvalid,
            details: [reason]
        ))
    }

    nonisolated static func unresolvedColorContractReasons(
        _ contract: SceneShaderContract
    ) -> [String] {
        var reasons: Set<String> = []
        if contract.stages.contains(where: { stage in
            stage.annotations.contains { annotation in
                guard case let .object(object) = annotation.variantValue else { return false }
                return object["combo"] != nil
            }
        }) {
            reasons.insert("combo-schema")
        }

        var mergedDefines: [String: SceneShaderMacroValue] = [:]
        for stage in contract.stages {
            var stageDefines: Set<String> = []
            for line in stage.source.split(
                omittingEmptySubsequences: false,
                whereSeparator: { $0.isNewline }
            ) {
                guard let directive = SceneShaderDirective.parse(String(line)) else {
                    continue
                }
                switch directive {
                case let .define(name, value):
                    switch value {
                    case .integer, .floatingLiteral:
                        if !stageDefines.insert(name).inserted {
                            reasons.insert("duplicate-define")
                        }
                        if let existing = mergedDefines[name], existing != value {
                            reasons.insert("cross-stage-define-conflict")
                        } else {
                            mergedDefines[name] = value
                        }
                    case .bare, .tokenSequence:
                        reasons.insert("prepared-directive")
                    }
                case .defineFunction, .undef, .include, .ifExpression, .ifdef,
                     .elseDirective, .endif, .unsupported, .unknown,
                     .unsupportedFunctionMacro, .malformed:
                    reasons.insert("prepared-directive")
                }
            }
        }
        return reasons.sorted()
    }

    private nonisolated static func prepare(
        _ kind: SceneShaderContract.StageKind,
        contract: SceneShaderContract,
        graph: SceneShaderSourceGraph,
        schemaSources: [SceneShaderVariantSchemaSource],
        combos: [String: Int],
        textureReadiness: [Int: Bool]
    ) -> SceneAuthoredShaderPreparationResult<SceneShaderPreparedSource> {
        guard let stage = contract.stages.first(where: { $0.kind == kind }) else {
            return .rejected(failure(
                phase: .invariant,
                code: .shaderStageMissing
            ))
        }
        let variantResult = SceneShaderVariantResolver.resolve(
            stage: kind,
            schemaSources: schemaSources,
            explicitCombos: combos,
            textureReadiness: textureReadiness
        )
        let environment: SceneShaderVariantEnvironment
        switch variantResult {
        case .success(let value): environment = value
        case .failure(let failure):
            return .rejected(Self.failure(
                phase: .shaderPreprocessor,
                code: .shaderVariantInvalid,
                details: [failure.code.rawValue, failure.combo ?? "<none>"]
            ))
        }

        switch SceneShaderPreprocessor().preprocess(
            rootRelativePath: stage.relativePath,
            graph: graph,
            environment: environment
        ) {
        case .success(let prepared): return .accepted(prepared)
        case .failure(let failure):
            return .rejected(preprocessorFailure(failure))
        }
    }

    private nonisolated static func preprocessorFailure(
        _ failure: SceneShaderPreprocessor.Failure
    ) -> SceneAuthoredShaderPreparationFailure {
        guard let diagnostic = failure.diagnostics.first else {
            return Self.failure(
                phase: .invariant,
                code: .shaderPreparationInvariant
            )
        }
        let code: SceneEffectStageCompilerFailure.Code
        switch diagnostic.code {
        case .missingRoot: code = .shaderSourceGraphMissing
        case .sourceIdentityMismatch: code = .shaderSourceIdentityMismatch
        case .missingInclude: code = .shaderIncludeMissing
        case .ambiguousInclude: code = .shaderIncludeAmbiguous
        case .includeCycle: code = .shaderIncludeCycle
        case .unsupportedDirective, .unknownDirective, .functionLikeMacro,
             .malformedDirective:
            code = .shaderDirectiveUnsupported
        case .invalidExpression, .unmatchedElse, .duplicateElse,
             .unmatchedEndif, .unterminatedConditional:
            code = .shaderConditionInvalid
        case .budgetExceeded: code = .shaderPreprocessorBudgetExceeded
        case .conflictingMacro, .unresolvedEnvironmentDefine:
            code = .shaderVariantInvalid
        case .rejectedInclude, .malformedSourceAnnotation,
             .unterminatedBlockComment, .unsupportedAnnotationPlacement:
            code = .shaderPreprocessorDiagnostic
        }
        return Self.failure(
            phase: .shaderPreprocessor,
            code: code,
            details: failure.diagnostics.map { $0.code.rawValue }
        )
    }

}
