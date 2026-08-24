import Foundation

/// Product preparation cache for exact-source-keyed generic Program artifacts.
/// Cache misses may invoke the separately killable bundled compiler worker;
/// malformed or failed output is either an effect-local typed fallback or a
/// profile-local rejection after the bounded product owner has been revoked.
nonisolated enum SceneResolvedMaterialGenericShaderArtifactCache {
    typealias RouteDecision = SceneGenericShaderRouteDecision
    private typealias RouteState = SceneGenericShaderRouteState
    private typealias FallbackOwner = SceneGenericShaderFallbackOwner
    private typealias CapabilityProfile = SceneGenericShaderCapabilityProfile

    enum Resolution {
        case accepted(
            program: SceneAuthoredShaderProgram,
            requestKey: String,
            routeDecision: RouteDecision
        )
        case ownerDeferred(
            code: String, requestKey: String,
            routeDecision: RouteDecision
        )
        case unavailable(
            code: String,
            requestKey: String,
            permitsBoundedFrontend: Bool,
            routeDecision: RouteDecision
        )
    }

    private struct Request: Encodable {
        struct Stage: Encodable {
            let stage: String
            let entryPoint: String
            let source: String
        }

        struct ExpectedColorTransfer: Encodable {
            let kind: String
            let slot: Int
        }

        let schemaVersion = 4
        let requestID: String
        let sourceDialect = "wallpaper-engine-glsl-like-v0"
        let outputSemantics: SceneGenericShaderOutputSemantics
        let expectedColorTransfer: ExpectedColorTransfer?
        let defines: [String: Int] = [:]
        let stages: [Stage]
    }

    private static let routeEnvironment = "MWX_SCENE_GENERIC_SHADER_ROUTE"
    /// Comma-separated profile-local route overrides.
    private static let profileRouteEnvironment =
        "MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES"
    private static let cacheEnvironment = "MWX_SCENE_GENERIC_SHADER_CACHE"
    private static let requestEnvironment = "MWX_SCENE_GENERIC_SHADER_REQUESTS"
    private static let maximumArtifactBytes = 2 * 1_024 * 1_024
    private static let maximumRouteAnalysisSourceBytes = 512 * 1_024
    private static let routeTelemetry = RouteTelemetry()
    private static let compilationCoordinator = CompilationCoordinator()

    private final class RouteTelemetry: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var executedIdentities = Set<String>()

        func record(
            state: RouteState,
            profile: CapabilityProfile,
            outcome: String,
            reason: String,
            requestKey: String
        ) {
            let count = lock.withLock {
                let identity = [
                    state.rawValue, profile.rawValue, outcome, reason,
                ].joined(separator: ":")
                let updated = counts[identity, default: 0] + 1
                counts[identity] = updated
                return updated
            }
            NSLog(
                "MWX generic shader route state=%@ profile=%@ outcome=%@ reason=%@ request=%@ count=%d",
                state.rawValue,
                profile.rawValue,
                outcome,
                reason,
                requestKey,
                count
            )
        }

        func recordInvalid(
            profile: CapabilityProfile,
            requestKey: String,
            reason: String
        ) {
            let count = lock.withLock {
                let identity = [
                    "route-invalid", profile.rawValue, reason,
                ].joined(separator: ":")
                let updated = counts[identity, default: 0] + 1
                counts[identity] = updated
                return updated
            }
            NSLog(
                "MWX generic shader route-invalid profile=%@ reason=%@ request=%@ count=%d",
                profile.rawValue,
                reason,
                requestKey,
                count
            )
        }

        func recordExecution(
            routeDecision: RouteDecision,
            backend: SceneAuthoredShaderProgram.Backend,
            graphInputDiagnostics: [String],
            layerID: Int,
            effectIndex: Int,
            descriptorID: String,
            nodeIndex: Int,
            preparedKey: String
        ) {
            let graphInputs = graphInputDiagnostics.joined(separator: ",")
            let identity = [
                String(layerID), String(effectIndex), descriptorID,
                String(nodeIndex), backend.rawValue, preparedKey, graphInputs,
            ].joined(separator: "|")
            guard lock.withLock({ executedIdentities.insert(identity).inserted }) else {
                return
            }
            NSLog(
                "MWX generic shader execution state=%@ profile=%@ layer=%d effect=%d descriptor=%@ node=%d backend=%@ prepared=%@ graphInputs=%@",
                routeDecision.state,
                routeDecision.profile,
                layerID,
                effectIndex,
                descriptorID,
                nodeIndex,
                backend.rawValue,
                preparedKey,
                graphInputs.isEmpty ? "-" : graphInputs
            )
        }

        func recordCompilerLifecycle(
            source: CompilationCoordinator.Source,
            outcome: String,
            reason: String,
            requestKey: String
        ) {
            let count = lock.withLock {
                let identity = "compiler:\(source.rawValue):\(outcome):\(reason)"
                let updated = counts[identity, default: 0] + 1
                counts[identity] = updated
                return updated
            }
            NSLog(
                "MWX generic shader compiler lifecycle phase=launch-preparation source=%@ outcome=%@ reason=%@ request=%@ count=%d",
                source.rawValue,
                outcome,
                reason,
                requestKey,
                count
            )
        }
    }

    final class CompilationCoordinator: @unchecked Sendable {
        enum Source: String {
            case spawn
            case launchResultCache = "launch-result-cache"
        }

        struct Outcome {
            let result: Result<URL, SceneGenericShaderCompiler.Failure>
            let source: Source
        }

        private let condition = NSCondition()
        private var active = Set<String>()
        private var completed: [String: Result<URL, SceneGenericShaderCompiler.Failure>] = [:]

        func perform(
            key: String,
            operation: () -> Result<URL, SceneGenericShaderCompiler.Failure>
        ) -> Outcome {
            condition.lock()
            while active.contains(key) {
                condition.wait()
            }
            if let result = completed[key] {
                condition.unlock()
                return .init(result: result, source: .launchResultCache)
            }
            active.insert(key)
            condition.unlock()
            let result = operation()
            condition.lock()
            completed[key] = result
            active.remove(key)
            condition.broadcast()
            condition.unlock()
            return .init(result: result, source: .spawn)
        }
    }

    static func resolve(
        vertexSource: String,
        fragmentSource: String,
        alphaAttenuationSourceSlot: Int? = nil,
        colorBlendSourceSlot: Int? = nil,
        unitCompositeBlurredSlot: Int? = nil,
        unitCompositePreviousSlot: Int? = nil,
        hasExternalProviderTexture: Bool = false,
        producesScalarRedOutput: Bool = false,
        producesRedGreenUnormOutput: Bool = false,
        hasOnlyScalarDataInputs: Bool = false,
        isSourceIndependentPremultipliedOutput: Bool = false,
        graphTextureSlots: Set<Int> = [],
        graphInputTextureSlots: Set<Int> = [],
        r8TextureSlots: Set<Int> = [],
        hasDefaultedOpacityMaskSampler: Bool = false,
        hasOnlyGraphInputSampler: Bool = false,
        sourceColorTransfer: SceneShaderColorTransfer? = nil,
        outputSemantics: SceneGenericShaderOutputSemantics = .color
    ) -> Resolution {
        let colorTransfer = sourceColorTransfer
            ?? SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let key = requestKey(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            outputSemantics: outputSemantics,
            colorTransfer: colorTransfer
        )
        let conditionalStraightUnionSourceSlot =
            SceneAuthoredShaderColorTransferAnalyzer
                .conditionalStraightUnionSourceSlot(
                    fragmentSource: fragmentSource
                )
        let singleSamplerAlphaMutationSourceSlot =
            SceneAuthoredShaderColorTransferAnalyzer
                .singleSamplerAlphaMutationSourceSlot(
                    fragmentSource: fragmentSource
                )
        let sameSlotChannelReconstructionSourceSlot =
            SceneAuthoredShaderColorTransferAnalyzer
                .sameSlotChannelReconstructionSourceSlot(
                    fragmentSource: fragmentSource
                )
        let auxiliaryRGBMixSourceSlot =
            SceneAuthoredShaderColorTransferAnalyzer
                .auxiliaryRGBMixSourceSlot(fragmentSource: fragmentSource)
        let normalizedSampleSumSourceSlot =
            SceneAuthoredShaderNormalizedSampleSumAnalyzer.sourceSlot(
                fragmentSource: fragmentSource
            )
        let alphaWeightedSampleAverageSourceSlot =
            SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                fragmentSource: fragmentSource
            )?.textureSlot
        let preservedAlphaRGBFilterFact =
            SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny(
                fragmentSource: fragmentSource
            )
        let preservedAlphaRGBFilterTextureSlots: Set<Int>
        if let preservedAlphaRGBFilterFact {
            preservedAlphaRGBFilterTextureSlots = Set(
                preservedAlphaRGBFilterFact.colorSampleCallCounts.keys
            ).union(preservedAlphaRGBFilterFact.dataSampleCallCounts.keys)
        } else {
            preservedAlphaRGBFilterTextureSlots = []
        }
        let unitCompositeSourceFact =
            SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let normalizedRouteFacts: SceneGenericShaderSourceNormalizer.Pair?
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            maximumStageSourceBytes: maximumRouteAnalysisSourceBytes
        ) {
        case let .success(value): normalizedRouteFacts = value
        case .failure: normalizedRouteFacts = nil
        }
        let activeAudioSpectrumArrays =
            normalizedRouteFacts?.activeAudioSpectrumArrays ?? []
        let profile = CapabilityProfile(
            colorTransfer: colorTransfer,
            alphaAttenuationSourceSlot: alphaAttenuationSourceSlot,
            colorBlendSourceSlot: colorBlendSourceSlot,
            conditionalStraightUnionSourceSlot:
                conditionalStraightUnionSourceSlot,
            singleSamplerAlphaMutationSourceSlot:
                singleSamplerAlphaMutationSourceSlot,
            sameSlotChannelReconstructionSourceSlot:
                sameSlotChannelReconstructionSourceSlot,
            auxiliaryRGBMixSourceSlot: auxiliaryRGBMixSourceSlot,
            normalizedSampleSumSourceSlot: normalizedSampleSumSourceSlot,
            alphaWeightedSampleAverageSourceSlot:
                alphaWeightedSampleAverageSourceSlot,
            preservedAlphaRGBFilterSourceSlot:
                preservedAlphaRGBFilterFact?.sourceSlot,
            preservedAlphaRGBFilterTextureSlots:
                preservedAlphaRGBFilterTextureSlots,
            unitCompositeBlurredSlot: unitCompositeBlurredSlot,
            unitCompositePreviousSlot: unitCompositePreviousSlot,
            unitCompositeSourceBlurredSlot:
                unitCompositeSourceFact?.blurredSlot,
            unitCompositeSourcePreviousSlot:
                unitCompositeSourceFact?.previousSlot,
            hasExternalProviderTexture: hasExternalProviderTexture,
            producesScalarRedOutput: producesScalarRedOutput,
            producesRedGreenUnormOutput: producesRedGreenUnormOutput,
            isScalarSplatOutput:
                SceneAuthoredShaderColorTransferAnalyzer.isScalarSplatOutput(
                    fragmentSource: fragmentSource
                ),
            hasOnlyScalarDataInputs: hasOnlyScalarDataInputs,
            isSourceIndependentPremultipliedOutput:
                isSourceIndependentPremultipliedOutput,
            graphTextureSlots: graphTextureSlots,
            graphInputTextureSlots: graphInputTextureSlots,
            r8TextureSlots: r8TextureSlots,
            hasDefaultedOpacityMaskSampler: hasDefaultedOpacityMaskSampler,
            hasOnlyGraphInputSampler: hasOnlyGraphInputSampler,
            hasStageScopedUniformBindings: SceneGenericShaderStageUniformAnalyzer.hasScopedBindings(
                vertexSource: vertexSource,
                fragmentSource: fragmentSource
            ),
            hasStereoAudioSpectrumArrays: [16, 32, 64].contains { count in
                activeAudioSpectrumArrays.isSuperset(of: [
                    "g_AudioSpectrum\(count)Left",
                    "g_AudioSpectrum\(count)Right",
                ])
            },
            hasLocalizedMutableFragmentVarying:
                normalizedRouteFacts?.localizedMutableFragmentVaryings.isEmpty
                    == false
        )
        let environment = ProcessInfo.processInfo.environment
        guard let routeState = routeState(
            for: profile,
            environment: environment
        ) else {
            routeTelemetry.recordInvalid(
                profile: profile,
                requestKey: key,
                reason: "route-configuration-invalid"
            )
            return .unavailableOrDeferred(
                code: "route-invalid",
                requestKey: key,
                permitsBoundedFrontend:
                    profile.defaultRouteState != .genericOnly
                        && profile.validatedRollbackOwner == .boundedFrontend,
                routeDecision: makeRouteDecision(
                    profile: profile,
                    state: "route-invalid"
                )
            )
        }
        let routeDecision = makeRouteDecision(
            profile: profile,
            state: routeState.rawValue
        )
        guard routeState != .disableGeneric else {
            routeTelemetry.record(
                state: routeState,
                profile: profile,
                outcome: "fallback",
                reason: "route-disabled",
                requestKey: key
            )
            return .unavailableOrDeferred(
                code: "route-disabled",
                requestKey: key,
                permitsBoundedFrontend:
                    profile.validatedRollbackOwner == .boundedFrontend,
                routeDecision: routeDecision
            )
        }
        exportRequest(
            key: key,
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            outputSemantics: outputSemantics,
            colorTransfer: colorTransfer
        )
        guard routeState == .preferGeneric || routeState == .genericOnly else {
            routeTelemetry.record(
                state: routeState,
                profile: profile,
                outcome: "observed",
                reason: "route-observe-only",
                requestKey: key
            )
            return .unavailableOrDeferred(
                code: "route-observe-only",
                requestKey: key,
                permitsBoundedFrontend:
                    profile.defaultRouteState != .genericOnly
                        && profile.validatedRollbackOwner == .boundedFrontend,
                routeDecision: routeDecision
            )
        }
        guard let root = cacheDirectory(environment: environment) else {
            return fallback(
                state: routeState,
                profile: profile,
                code: "cache-unavailable",
                requestKey: key
            )
        }
        let artifactURL = root.appendingPathComponent("\(key).json", isDirectory: false)
        var data = regularFileData(artifactURL)
        if data == nil {
            let compilation = compilationCoordinator.perform(key: key) {
                if regularFileData(artifactURL) != nil {
                    return .success(artifactURL)
                }
                return SceneGenericShaderCompiler.compile(
                    requestKey: key,
                    vertexSource: vertexSource,
                    fragmentSource: fragmentSource,
                    outputSemantics: outputSemantics,
                    cacheRoot: root
                )
            }
            switch compilation.result {
            case .success:
                routeTelemetry.recordCompilerLifecycle(
                    source: compilation.source,
                    outcome: "published",
                    reason: "-",
                    requestKey: key
                )
                data = regularFileData(artifactURL)
            case let .failure(failure):
                let code = compilerFallbackCode(failure)
                routeTelemetry.recordCompilerLifecycle(
                    source: compilation.source,
                    outcome: "failed",
                    reason: code,
                    requestKey: key
                )
                return fallback(
                    state: routeState,
                    profile: profile,
                    code: code,
                    requestKey: key
                )
            }
        }
        guard let data else {
            return fallback(
                state: routeState,
                profile: profile,
                code: "compiler-publication-missing",
                requestKey: key
            )
        }
        let artifact: SceneGenericShaderProgramArtifact
        do {
            artifact = try JSONDecoder().decode(
                SceneGenericShaderProgramArtifact.self,
                from: data
            )
        } catch {
            return fallback(
                state: routeState,
                profile: profile,
                code: "artifact-invalid-json",
                requestKey: key
            )
        }
        let fragmentOutputChannelUse = fragmentOutputChannelUse(fragmentSource)
        guard let program = artifact.makeProgram(
                  expectedKey: key,
                  expectedOutputSemantics: outputSemantics,
                  expectedColorTransfer: colorTransfer,
                  expectedFragmentOutputChannelUse: fragmentOutputChannelUse
              ) else {
            return fallback(
                state: routeState,
                profile: profile,
                code: "artifact-contract-rejected",
                requestKey: key
            )
        }
        routeTelemetry.record(
            state: routeState,
            profile: profile,
            outcome: "accepted",
            reason: "-",
            requestKey: key
        )
        return .accepted(
            program: program,
            requestKey: key,
            routeDecision: routeDecision
        )
    }

    private static func fragmentOutputChannelUse(
        _ source: String
    ) -> SceneAuthoredShaderProgram.FragmentOutputChannelUse {
        let lexerOutput = SceneAuthoredShaderLexer.lex(
            source: source,
            stage: .fragment
        )
        let syntaxOutput = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: lexerOutput,
            stage: .fragment
        )
        guard syntaxOutput.diagnostics.isEmpty,
              let fragment = syntaxOutput.unit else { return .unproven }
        return SceneAuthoredShaderFragmentOutputAnalyzer.analyze(fragment)
    }

    private static func fallback(
        state: RouteState,
        profile: CapabilityProfile,
        code: String,
        requestKey: String
    ) -> Resolution {
        routeTelemetry.record(
            state: state,
            profile: profile,
            outcome: state == .genericOnly ? "rejected" : "fallback",
            reason: code,
            requestKey: requestKey
        )
        return .unavailableOrDeferred(
            code: code,
            requestKey: requestKey,
            permitsBoundedFrontend:
                state != .genericOnly
                    && profile.validatedRollbackOwner == .boundedFrontend,
            routeDecision: makeRouteDecision(
                profile: profile,
                state: state.rawValue
            )
        )
    }

    static func recordExecution(
        routeDecision: RouteDecision?,
        backend: SceneAuthoredShaderProgram.Backend,
        graphInputDiagnostics: [String],
        layerID: Int,
        effectIndex: Int,
        descriptorID: String,
        nodeIndex: Int,
        preparedKey: String
    ) {
        guard let routeDecision else { return }
        routeTelemetry.recordExecution(
            routeDecision: routeDecision,
            backend: backend,
            graphInputDiagnostics: graphInputDiagnostics,
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: descriptorID,
            nodeIndex: nodeIndex,
            preparedKey: preparedKey
        )
    }
    private static func makeRouteDecision(
        profile: CapabilityProfile,
        state: String
    ) -> RouteDecision {
        RouteDecision(
            profile: profile.rawValue,
            state: state,
            fallbackOwner: profile.validatedRollbackOwner.rawValue
        )
    }

    /// Resolve a strict profile map, then the legacy process route.
    private static func routeState(
        for profile: CapabilityProfile,
        environment: [String: String]
    ) -> RouteState? {
        if let rawOverrides = environment[profileRouteEnvironment] {
            guard !rawOverrides.isEmpty else { return nil }
            var overrides: [CapabilityProfile: RouteState] = [:]
            for rawEntry in rawOverrides.split(
                separator: ",",
                omittingEmptySubsequences: false
            ) {
                let pair = rawEntry.split(
                    separator: "=",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                guard pair.count == 2,
                      let mappedProfile = CapabilityProfile(
                          rawValue: String(pair[0])
                      ),
                      let requestedState = RouteState(
                          rawValue: String(pair[1])
                      ),
                      overrides[mappedProfile] == nil else {
                    return nil
                }
                overrides[mappedProfile] = requestedState
            }
            if let requestedState = overrides[profile] {
                switch requestedState {
                case .genericOnly:
                    guard profile.defaultRouteState == .genericOnly else {
                        return nil
                    }
                case .preferGeneric, .observeOnly:
                    guard profile.defaultRouteState != .genericOnly else {
                        return nil
                    }
                case .disableGeneric: break
                }
                return requestedState
            }
            // A validated registry owns the full profile map. An omitted
            // profile retains its own default and never inherits the legacy
            // process-wide switch.
            return profile.defaultRouteState
        }
        return RouteState.resolve(
            environment[routeEnvironment],
            defaultState: profile.defaultRouteState
        )
    }

    private static func requestKey(
        vertexSource: String,
        fragmentSource: String,
        outputSemantics: SceneGenericShaderOutputSemantics,
        colorTransfer: SceneShaderColorTransfer
    ) -> String {
        var data = Data()
        for value in [
            "mwx-generic-shader-request-v9",
            "wallpaper-engine-glsl-like-v0",
            outputSemantics.rawValue,
            vertexSource,
            fragmentSource,
            expectedColorTransferKey(colorTransfer),
            "{}",
        ] {
            let encoded = Data(value.utf8)
            var length = UInt64(encoded.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(encoded)
        }
        return sha256(data)
    }

    private static func exportRequest(
        key: String,
        vertexSource: String,
        fragmentSource: String,
        outputSemantics: SceneGenericShaderOutputSemantics,
        colorTransfer: SceneShaderColorTransfer
    ) {
        let environment = ProcessInfo.processInfo.environment
        guard let rawRoot = environment[requestEnvironment],
              let root = validatedDirectory(rawRoot) else { return }
        let request = Request(
            requestID: key,
            outputSemantics: outputSemantics,
            expectedColorTransfer: expectedColorTransfer(colorTransfer),
            stages: [
                .init(stage: "vertex", entryPoint: "main", source: vertexSource),
                .init(stage: "fragment", entryPoint: "main", source: fragmentSource),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(request) else { return }
        let url = root.appendingPathComponent("\(key).json", isDirectory: false)
        if let existing = try? Data(contentsOf: url) {
            if existing != data {
                NSLog("MWX generic shader request collision request=%@", key)
            }
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            NSLog("MWX generic shader request exported request=%@", key)
        } catch {
            NSLog("MWX generic shader request export failed request=%@", key)
        }
    }

    private static func expectedColorTransfer(
        _ transfer: SceneShaderColorTransfer
    ) -> Request.ExpectedColorTransfer? {
        guard case let .independentAlphaSignalPreserving(slot) = transfer,
              (0 ..< 8).contains(slot) else { return nil }
        return .init(
            kind: "independent-alpha-signal-preserving",
            slot: slot
        )
    }

    private static func expectedColorTransferKey(
        _ transfer: SceneShaderColorTransfer
    ) -> String {
        guard let expected = expectedColorTransfer(transfer) else { return "-" }
        return "\(expected.kind):\(expected.slot)"
    }

    private static func validatedDirectory(_ rawPath: String) -> URL? {
        guard !rawPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            return nil
        }
        return url
    }

    private static func cacheDirectory(
        environment: [String: String]
    ) -> URL? {
        if let rawRoot = environment[cacheEnvironment] {
            return validatedDirectory(rawRoot)
        }
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let root = caches
            .appendingPathComponent("com.songziqiang.MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SceneGenericShaderPrograms-v8", isDirectory: true)
            .standardizedFileURL
        do {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }
        return validatedDirectory(root.path)
    }

    private static func compilerFallbackCode(
        _ failure: SceneGenericShaderCompiler.Failure
    ) -> String {
        switch failure {
        case let .configuration(reason):
            return "compiler-configuration-\(sanitize(reason))"
        case let .normalization(reason):
            return "compiler-normalization-\(sanitize(reason))"
        case .workspace:
            return "compiler-workspace"
        case let .tool(reason):
            return "compiler-tool-\(sanitize(reason))"
        case let .artifact(reason):
            return "compiler-artifact-\(sanitize(reason))"
        case .publication:
            return "compiler-publication"
        }
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .prefix(96)
            .lowercased()
    }

    private static func regularFileData(_ url: URL) -> Data? {
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let size = values?.fileSize,
              (1 ... maximumArtifactBytes).contains(size) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func sha256(_ data: Data) -> String {
        SceneGenericShaderProgramArtifact.sha256(data)
    }
}
