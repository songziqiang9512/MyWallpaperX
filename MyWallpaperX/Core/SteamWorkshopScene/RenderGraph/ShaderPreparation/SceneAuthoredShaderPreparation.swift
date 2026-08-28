import Foundation

nonisolated struct SceneAuthoredShaderPreparationFailure {
    enum Phase: String {
        case shaderPreprocessor = "shader-preprocessor"
        case invariant
    }

    enum Code: String {
        case shaderStageMissing = "shader-stage-missing"
        case shaderSourceGraphMissing = "shader-source-graph-missing"
        case shaderSourceIdentityMismatch = "shader-source-identity-mismatch"
        case shaderVariantInvalid = "shader-variant-invalid"
        case shaderIncludeMissing = "shader-include-missing"
        case shaderIncludeAmbiguous = "shader-include-ambiguous"
        case shaderIncludeCycle = "shader-include-cycle"
        case shaderDirectiveUnsupported = "shader-directive-unsupported"
        case shaderModuleResolutionRejected = "shader-module-resolution-rejected"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded =
            "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
    }

    let phase: Phase
    let code: Code
    let details: [String]
}

nonisolated enum SceneAuthoredShaderPreparationResult<Value> {
    case notApplicable
    case rejected(SceneAuthoredShaderPreparationFailure)
    case accepted(Value)
}

nonisolated enum SceneAuthoredShaderPreparation {
    private struct PreparationCacheKey: Codable, Hashable {
        struct Combo: Codable, Hashable {
            let name: String
            let value: Int
        }

        struct Readiness: Codable, Hashable {
            let slot: Int
            let isReady: Bool
        }

        struct TextureFormat: Codable, Hashable {
            let slot: Int
            let format: SceneShaderTextureFormat
        }

        let frontendSchemaVersion: Int
        let contractCanonicalSHA256: String
        let sourceGraphSHA256: String
        let combos: [Combo]
        let inactiveComboProviders: [String]
        let textureReadiness: [Readiness]
        let textureFormats: [TextureFormat]

        init(
            contract: SceneShaderContract,
            graph: SceneShaderSourceGraph,
            combos: [String: Int],
            inactiveComboProviders: Set<String>,
            textureReadiness: [Int: Bool],
            textureFormats: [Int: SceneShaderTextureFormat]
        ) {
            frontendSchemaVersion = SceneShaderVariantEnvironment
                .frontendSchemaVersion
            contractCanonicalSHA256 = contract.canonicalSHA256
            // The contract digest deliberately tracks root stages. Cache
            // identity additionally hashes the complete immutable VFS graph,
            // including actual include source, so reuse cannot hide a changed
            // include behind a stale dependency marker.
            sourceGraphSHA256 = SceneShaderStableDigest.hash(graph)
            self.combos = combos.map {
                Combo(name: $0.key, value: $0.value)
            }.sorted { $0.name < $1.name }
            self.inactiveComboProviders = inactiveComboProviders.sorted()
            self.textureReadiness = textureReadiness.map {
                Readiness(slot: $0.key, isReady: $0.value)
            }.sorted { $0.slot < $1.slot }
            self.textureFormats = textureFormats.map {
                TextureFormat(slot: $0.key, format: $0.value)
            }.sorted { $0.slot < $1.slot }
        }
    }

    /// Process-lifetime, bounded single-flight cache for immutable authored
    /// preparation. Both successful and rejected results are cached so a bad
    /// variant cannot repeatedly consume launch CPU. The complete key carries
    /// every preparation input and the current frontend schema version.
    private final class PreparationCache: @unchecked Sendable {
        typealias Result = SceneAuthoredShaderPreparationResult<
            SceneShaderPreparedProgram
        >

        private struct Entry {
            let result: Result
            var lastAccess: UInt64
        }

        private let capacity: Int
        private let condition = NSCondition()
        private var entries: [PreparationCacheKey: Entry] = [:]
        private var inFlight: Set<PreparationCacheKey> = []
        private var accessClock: UInt64 = 0

        init(capacity: Int) {
            precondition(capacity > 0)
            self.capacity = capacity
        }

        func result(
            for key: PreparationCacheKey,
            prepare: () -> Result
        ) -> Result {
            condition.lock()
            while true {
                if var entry = entries[key] {
                    accessClock &+= 1
                    entry.lastAccess = accessClock
                    entries[key] = entry
                    condition.unlock()
                    return entry.result
                }
                if inFlight.insert(key).inserted { break }
                condition.wait()
            }
            condition.unlock()

            let result = prepare()

            condition.lock()
            accessClock &+= 1
            if entries.count >= capacity,
               let oldest = entries.min(by: {
                   $0.value.lastAccess < $1.value.lastAccess
               })?.key {
                entries.removeValue(forKey: oldest)
            }
            entries[key] = Entry(result: result, lastAccess: accessClock)
            inFlight.remove(key)
            condition.broadcast()
            condition.unlock()
            return result
        }
    }

    private static let preparationCache = PreparationCache(capacity: 256)

    /// Process restarts must not turn immutable authored source into repeated
    /// preprocessing work. The disk tier stores only accepted prepared source;
    /// failures remain process-local so a repaired cache/input is never held by
    /// a stale negative entry. Full source-graph, combo, readiness, format and
    /// frontend-schema identity lives in the filename digest.
    private final class PersistentPreparationCache: @unchecked Sendable {
        private struct Envelope: Codable {
            let schemaVersion: Int
            let key: PreparationCacheKey
            let keySHA256: String
            let programSHA256: String
            let program: SceneShaderPreparedProgram
        }

        private let schemaVersion = 1
        private let retainedEntryLimit = 2_048
        private let lock = NSLock()
        private var pruned = false

        func load(
            key: PreparationCacheKey,
            contract: SceneShaderContract
        ) -> SceneShaderPreparedProgram? {
            guard let directory = directoryURL() else { return nil }
            let keySHA256 = SceneShaderStableDigest.hash(key)
            let url = directory.appendingPathComponent(
                "\(keySHA256).json",
                isDirectory: false
            )
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  envelope.schemaVersion == schemaVersion,
                  envelope.key == key,
                  envelope.keySHA256 == keySHA256,
                  envelope.keySHA256 == SceneShaderStableDigest.hash(envelope.key),
                  envelope.programSHA256 == SceneShaderStableDigest.hash(envelope.program),
                  valid(envelope.program, key: key, contract: contract) else {
                return nil
            }
            return envelope.program
        }

        func store(
            _ program: SceneShaderPreparedProgram,
            key: PreparationCacheKey,
            contract: SceneShaderContract
        ) {
            guard valid(program, key: key, contract: contract),
                  let directory = directoryURL() else { return }
            let keySHA256 = SceneShaderStableDigest.hash(key)
            let envelope = Envelope(
                schemaVersion: schemaVersion,
                key: key,
                keySHA256: keySHA256,
                programSHA256: SceneShaderStableDigest.hash(program),
                program: program
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(envelope) else {
                return
            }
            lock.withLock {
                do {
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                    if !pruned {
                        prune(directory)
                        pruned = true
                    }
                    try data.write(
                        to: directory.appendingPathComponent("\(keySHA256).json"),
                        options: .atomic
                    )
                } catch {
                    // Cache publication is optional; launch keeps the freshly
                    // prepared in-memory result when disk is unavailable.
                }
            }
        }

        private func directoryURL() -> URL? {
            guard Bundle.main.bundleIdentifier == "com.songziqiang.MyWallpaperX",
                  let root = FileManager.default.urls(
                      for: .cachesDirectory,
                      in: .userDomainMask
                  ).first else { return nil }
            return root
                .appendingPathComponent("MyWallpaperX", isDirectory: true)
                .appendingPathComponent(
                    "SceneShaderPreparation-v\(schemaVersion)",
                    isDirectory: true
                )
        }

        private func valid(
            _ program: SceneShaderPreparedProgram,
            key: PreparationCacheKey,
            contract: SceneShaderContract
        ) -> Bool {
            guard program.vertex.frontendSchemaVersion == key.frontendSchemaVersion,
                  program.fragment.frontendSchemaVersion == key.frontendSchemaVersion,
                  program.vertex.stage == .vertex,
                  program.fragment.stage == .fragment else { return false }
            let identity = PreparedProgramIdentity(
                frontendSchemaVersion: key.frontendSchemaVersion,
                contractCanonicalSHA256: contract.canonicalSHA256,
                vertexPreparedSHA256: program.vertex.preparedSHA256,
                fragmentPreparedSHA256: program.fragment.preparedSHA256,
                colorContract: program.colorContract
            )
            return program.cacheKey == SceneShaderStableDigest.hash(identity)
        }

        private func prune(_ directory: URL) {
            let keys: Set<URLResourceKey> = [.contentModificationDateKey]
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ), files.count > retainedEntryLimit else { return }
            let sorted = files.sorted {
                let lhs = try? $0.resourceValues(forKeys: keys)
                    .contentModificationDate
                let rhs = try? $1.resourceValues(forKeys: keys)
                    .contentModificationDate
                return (lhs ?? .distantPast) > (rhs ?? .distantPast)
            }
            for url in sorted.dropFirst(retainedEntryLimit) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static let persistentPreparationCache = PersistentPreparationCache()

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
        inactiveComboProviders: Set<String> = [],
        textureReadiness: [Int: Bool] = [:],
        textureFormats: [Int: SceneShaderTextureFormat] = [:]
    ) -> SceneAuthoredShaderPreparationResult<SceneShaderPreparedProgram> {
        guard let graph = contract.sourceGraph else {
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
        let cacheKey = PreparationCacheKey(
            contract: contract,
            graph: graph,
            combos: combos,
            inactiveComboProviders: inactiveComboProviders,
            textureReadiness: textureReadiness,
            textureFormats: textureFormats
        )
        return preparationCache.result(for: cacheKey) {
            if let cached = persistentPreparationCache.load(
                key: cacheKey,
                contract: contract
            ) {
                return .accepted(cached)
            }
            let result = prepareShaderStagesUncached(
                contract: contract,
                graph: graph,
                combos: combos,
                inactiveComboProviders: inactiveComboProviders,
                textureReadiness: textureReadiness,
                textureFormats: textureFormats
            )
            if case let .accepted(program) = result {
                persistentPreparationCache.store(
                    program,
                    key: cacheKey,
                    contract: contract
                )
            }
            return result
        }
    }

    private static func prepareShaderStagesUncached(
        contract: SceneShaderContract,
        graph: SceneShaderSourceGraph,
        combos: [String: Int],
        inactiveComboProviders: Set<String>,
        textureReadiness: [Int: Bool],
        textureFormats: [Int: SceneShaderTextureFormat]
    ) -> SceneAuthoredShaderPreparationResult<SceneShaderPreparedProgram> {
        // Bootstrap with the conservative root/include metadata seed. Apart
        // from source-proven self-gated readiness samplers, conditional graph
        // nodes are discovered by the bounded active-schema iterations below.
        let schemaSources = SceneShaderVariantSchemaSeed.unconditional(
            contract: contract,
            graph: graph
        )
        let baselineResult = converge(
            contract: contract,
            graph: graph,
            initialSources: schemaSources,
            combos: combos,
            inactiveComboProviders: inactiveComboProviders,
            textureReadiness: textureReadiness,
            textureFormats: textureFormats
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
                inactiveComboProviders: inactiveComboProviders,
                textureReadiness: textureReadiness,
                textureFormats: textureFormats
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
        inactiveComboProviders: Set<String>,
        textureReadiness: [Int: Bool],
        textureFormats: [Int: SceneShaderTextureFormat]
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
                inactiveComboProviders: inactiveComboProviders,
                textureReadiness: textureReadiness,
                textureFormats: textureFormats
            )
            guard case let .accepted(pair) = result else {
                switch result {
                case .rejected(let failure): return .rejected(failure)
                default: return .notApplicable
                }
            }
            let activeSources = activeSchemaSources(
                [pair.vertex, pair.fragment],
                graph: graph
            )
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
        inactiveComboProviders: Set<String>,
        textureReadiness: [Int: Bool],
        textureFormats: [Int: SceneShaderTextureFormat]
    ) -> SceneAuthoredShaderPreparationResult<PreparedPair> {
        let vertex = prepare(
            .vertex,
            contract: contract,
            graph: graph,
            schemaSources: schemaSources,
            combos: combos,
            inactiveComboProviders: inactiveComboProviders,
            textureReadiness: textureReadiness,
            textureFormats: textureFormats
        )
        let fragment = prepare(
            .fragment,
            contract: contract,
            graph: graph,
            schemaSources: schemaSources,
            combos: combos,
            inactiveComboProviders: inactiveComboProviders,
            textureReadiness: textureReadiness,
            textureFormats: textureFormats
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
        _ stages: [SceneShaderPreparedSource],
        graph: SceneShaderSourceGraph
    ) -> [SceneShaderVariantSchemaSource] {
        var annotations: [String: [SceneShaderContract.Annotation]] = [:]
        var declarations: [String: [SceneShaderContract.Declaration]] = [:]
        var seenAnnotations: Set<String> = []
        var seenDeclarations: Set<String> = []
        for stage in stages {
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
        return graph.nodes.sorted { $0.virtualPath < $1.virtualPath }.map { node in
            .init(
                relativePath: node.virtualPath,
                source: node.source,
                annotations: annotations[node.virtualPath] ?? [],
                declarations: declarations[node.virtualPath] ?? []
            )
        }
    }

    /// Reprojects the exact converged active schema into integer macro facts.
    /// Prepared source deliberately preserves authored identifiers in ordinary
    /// expressions, so source analyzers use these facts instead of guessing
    /// annotation defaults or substituting tokens by name.
    nonisolated static func resolvedIntegerCombos(
        contract: SceneShaderContract,
        prepared: SceneShaderPreparedProgram,
        combos: [String: Int],
        inactiveComboProviders: Set<String> = [],
        textureReadiness: [Int: Bool] = [:],
        textureFormats: [Int: SceneShaderTextureFormat] = [:]
    ) -> [String: Int]? {
        guard let graph = contract.sourceGraph else { return nil }
        let sources = activeSchemaSources(prepared.all, graph: graph)
        let environment: SceneShaderVariantEnvironment
        switch SceneShaderVariantResolver.resolve(
            stage: .fragment,
            schemaSources: sources,
            explicitCombos: combos,
            inactiveComboProviders: inactiveComboProviders,
            textureReadiness: textureReadiness,
            textureFormats: textureFormats
        ) {
        case let .success(value): environment = value
        case .failure: return nil
        }
        return Dictionary(uniqueKeysWithValues:
            environment.comboResolutions.compactMap { resolution in
                guard case let .defined(.integer(value)) =
                        resolution.binding.definition,
                      let exact = Int(exactly: value) else { return nil }
                return (resolution.binding.name, exact)
            }
        )
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
                     .require, .malformedRequire, .elifExpression,
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
        inactiveComboProviders: Set<String>,
        textureReadiness: [Int: Bool],
        textureFormats: [Int: SceneShaderTextureFormat]
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
            inactiveComboProviders: inactiveComboProviders,
            textureReadiness: textureReadiness,
            textureFormats: textureFormats
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
        let code: SceneAuthoredShaderPreparationFailure.Code
        switch diagnostic.code {
        case .missingRoot: code = .shaderSourceGraphMissing
        case .sourceIdentityMismatch: code = .shaderSourceIdentityMismatch
        case .missingInclude: code = .shaderIncludeMissing
        case .ambiguousInclude: code = .shaderIncludeAmbiguous
        case .includeCycle: code = .shaderIncludeCycle
        case .unsupportedDirective, .unknownDirective, .functionLikeMacro,
             .malformedDirective:
            code = .shaderDirectiveUnsupported
        case .moduleDirectiveSyntax, .moduleUnknown, .moduleCaseMismatch,
             .moduleLightingNonzero, .moduleLightingMacroMissing,
             .moduleLightingMacroNoninteger:
            code = .shaderModuleResolutionRejected
        case .invalidExpression, .unmatchedElse, .duplicateElse,
             .unmatchedEndif, .unmatchedElif, .elifAfterElse,
             .unterminatedConditional:
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
            details: failure.diagnostics.flatMap { diagnostic in
                [
                    diagnostic.code.rawValue,
                    diagnostic.relativePath,
                    diagnostic.line.map(String.init) ?? "<none>",
                    diagnostic.message,
                ]
            }
        )
    }

}
