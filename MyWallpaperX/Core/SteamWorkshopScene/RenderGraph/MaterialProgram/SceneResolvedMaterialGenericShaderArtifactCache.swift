import Foundation

/// Product preparation cache for exact-source-keyed generic Program artifacts.
/// Cache misses may invoke the separately killable bundled compiler worker;
/// malformed or failed output is either an effect-local typed fallback or a
/// profile-local rejection after the bounded product owner has been revoked.
nonisolated enum SceneResolvedMaterialGenericShaderArtifactCache {
    typealias RouteDecision = SceneGenericShaderRouteDecision
    typealias RouteState = SceneGenericShaderRouteState
    typealias CapabilityProfile = SceneGenericShaderCapabilityProfile

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

    private static let routeEnvironment = "MWX_SCENE_GENERIC_SHADER_ROUTE"
    /// Comma-separated profile-local route overrides.
    private static let profileRouteEnvironment =
        "MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES"
    private static let cacheEnvironment = "MWX_SCENE_GENERIC_SHADER_CACHE"
    private static let maximumArtifactBytes = 2 * 1_024 * 1_024
    private static let maximumRouteAnalysisSourceBytes = 512 * 1_024
    static let routeTelemetry = RouteTelemetry()
    private static let compilationCoordinator = CompilationCoordinator()

    final class RouteTelemetry: @unchecked Sendable {
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
        unitCompositeMaskSlot: Int? = nil,
        hasExternalProviderTexture: Bool = false,
        producesScalarRedOutput: Bool = false,
        producesRedGreenUnormOutput: Bool = false,
        hasOnlyScalarDataInputs: Bool = false,
        isSourceIndependentPremultipliedOutput: Bool = false,
        graphTextureSlots: Set<Int> = [],
        graphInputTextureSlots: Set<Int> = [],
        activeTextureSlots: Set<Int> = [],
        activeOpacityMaskSlots: Set<Int> = [],
        typedStaticDataAuxiliarySlots: Set<Int> = [],
        spatialWeightedColorBlendSourceSlot: Int? = nil,
        spatialWeightedColorBlendActiveSlots: Set<Int> = [],
        spatialWeightedColorBlendTypedAuxiliarySlots: Set<Int> = [],
        spatialWeightedColorBlendExternalColorSlot: Int? = nil,
        r8TextureSlots: Set<Int> = [],
        hasDefaultedOpacityMaskSampler: Bool = false,
        hasOnlyTypedOpacityMaskAuxiliary: Bool = false,
        hasOnlyGraphInputSampler: Bool = false,
        outputIsRGBA8Unorm: Bool = false,
        sourceColorTransfer: SceneShaderColorTransfer? = nil,
        outputSemantics: SceneGenericShaderOutputSemantics = .color,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds = .none
    ) -> Resolution {
        let colorTransfer = sourceColorTransfer
            ?? SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: fragmentSource
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
        let blendSourceSlots = SceneAuthoredShaderColorTransferAnalyzer
            .blendSourceSlots(fragmentSource: fragmentSource)
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
        let typedDataRGBFilterFact =
            SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let sameAlphaReconstructedRGBFilterFact =
            SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let straightRGBScalarAlphaFact = SceneAuthoredShaderColorTransferAnalyzer
            .straightRGBScalarAlphaFact(fragmentSource: fragmentSource)
        let preservedAlphaRGBFilterTextureSlots =
            preservedAlphaRGBFilterFact?.sampledTextureSlots ?? []
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
            fragmentSource: fragmentSource,
            colorTransfer: colorTransfer,
            alphaAttenuationSourceSlot: alphaAttenuationSourceSlot,
            colorBlendSourceSlot: colorBlendSourceSlot,
            overlayAlphaBlendSourceSlot: blendSourceSlots.overlayAlpha?.source,
            overlayAlphaBlendAuxiliarySlot: blendSourceSlots.overlayAlpha?.overlay,
            conditionalStraightUnionSourceSlot: conditionalStraightUnionSourceSlot,
            singleSamplerAlphaMutationSourceSlot:
                singleSamplerAlphaMutationSourceSlot,
            sameSlotChannelReconstructionSourceSlot:
                sameSlotChannelReconstructionSourceSlot,
            auxiliaryRGBMixSourceSlot: blendSourceSlots.auxiliaryRGB,
            normalizedSampleSumSourceSlot: normalizedSampleSumSourceSlot,
            independentSignalAccumulatorSourceSlot:
                SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer.sourceSlot(
                    fragmentSource: fragmentSource
                ),
            independentSignalUNormAccumulatorSourceSlot:
                SceneAuthoredShaderIndependentSignalInlineAccumulatorAnalyzer
                    .rgba8UnormAttachmentSourceSlot(
                        fragmentSource: fragmentSource
                    ),
            alphaWeightedSampleAverageSourceSlot:
                alphaWeightedSampleAverageSourceSlot,
            preservedAlphaRGBFilterSourceSlot:
                preservedAlphaRGBFilterFact?.sourceSlot,
            preservedAlphaRGBFilterTextureSlots:
                preservedAlphaRGBFilterTextureSlots,
            typedDataRGBFilterSourceSlot:
                typedDataRGBFilterFact?.sourceSlot,
            typedDataRGBFilterAuxiliarySlots:
                typedDataRGBFilterFact?.auxiliarySlots ?? [],
            sameAlphaReconstructedRGBFilterSourceSlot:
                sameAlphaReconstructedRGBFilterFact?.sourceSlot,
            sameAlphaReconstructedRGBFilterAuxiliarySlots:
                sameAlphaReconstructedRGBFilterFact?.auxiliarySlots ?? [],
            straightRGBScalarAlphaSourceSlot:
                straightRGBScalarAlphaFact?.sourceSlot,
            straightRGBScalarAlphaAuxiliarySlots:
                straightRGBScalarAlphaFact?.auxiliarySlots ?? [],
            straightRGBScalarAlphaMaskSlot: straightRGBScalarAlphaFact?.maskSlot,
            activeTextureSlots: activeTextureSlots,
            activeOpacityMaskSlots: activeOpacityMaskSlots,
            typedStaticDataAuxiliarySlots: typedStaticDataAuxiliarySlots,
            spatialWeightedColorBlendSourceSlot:
                spatialWeightedColorBlendSourceSlot,
            spatialWeightedColorBlendActiveSlots:
                spatialWeightedColorBlendActiveSlots,
            spatialWeightedColorBlendTypedAuxiliarySlots:
                spatialWeightedColorBlendTypedAuxiliarySlots,
            spatialWeightedColorBlendExternalColorSlot:
                spatialWeightedColorBlendExternalColorSlot,
            unitCompositeBlurredSlot: unitCompositeBlurredSlot,
            unitCompositePreviousSlot: unitCompositePreviousSlot,
            unitCompositeMaskSlot: unitCompositeMaskSlot,
            unitCompositeSourceBlurredSlot:
                unitCompositeSourceFact?.blurredSlot,
            unitCompositeSourcePreviousSlot:
                unitCompositeSourceFact?.previousSlot,
            unitCompositeSourceMaskSlot: unitCompositeSourceFact?.maskSlot,
            hasExternalProviderTexture: hasExternalProviderTexture,
            producesScalarRedOutput: producesScalarRedOutput,
            producesRedGreenUnormOutput: producesRedGreenUnormOutput,
            producesPreservedRGBAOutput: outputSemantics == .preservedRGBAUnorm,
            hasDefiniteWholeOutput:
                SceneAuthoredShaderFragmentOutputAnalyzer.analyze(
                    source: fragmentSource
                ) == .redDefined,
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
            hasOnlyTypedOpacityMaskAuxiliary: hasOnlyTypedOpacityMaskAuxiliary,
            hasOnlyGraphInputSampler: hasOnlyGraphInputSampler,
            outputIsRGBA8Unorm: outputIsRGBA8Unorm,
            hasStageScopedUniformBindings: SceneGenericShaderStageUniformAnalyzer.hasScopedBindings(
                vertexSource: vertexSource,
                fragmentSource: fragmentSource,
                runtimeLoopBounds: runtimeLoopBounds
            ),
            hasStereoAudioSpectrumArrays: [16, 32, 64].contains { count in
                activeAudioSpectrumArrays.isSuperset(of: [
                    "g_AudioSpectrum\(count)Left",
                    "g_AudioSpectrum\(count)Right",
                ])
            }
        )
        let expectedColorTransfer = SceneGenericShaderExpectedColorTransfer(
            colorTransfer,
            fragmentSource: fragmentSource,
            permitsStraightAlphaPreserving:
                profile
                    == .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary
                    || profile
                        == .sourceProvenGraphInputStageUniformStraightAlphaPreservingStaticAuxiliary
        )
        let premultipliedColorInputSlots = Set(
            profile == .providerBackedGraphInputSpatialWeightedColorBlend
                ? spatialWeightedColorBlendExternalColorSlot.map { [$0] } ?? []
                : []
        )
        let key = SceneResolvedMaterialGenericShaderRequest.key(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            outputSemantics: outputSemantics,
            expectedColorTransfer: expectedColorTransfer,
            premultipliedColorInputSlots: premultipliedColorInputSlots
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
        SceneResolvedMaterialGenericShaderRequest.export(
            key: key,
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            outputSemantics: outputSemantics,
            expectedColorTransfer: expectedColorTransfer,
            premultipliedColorInputSlots: premultipliedColorInputSlots
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
                    premultipliedColorInputSlots: premultipliedColorInputSlots,
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
        let fragmentOutputChannelUse = SceneAuthoredShaderFragmentOutputAnalyzer.analyze(
            source: fragmentSource
        )
        guard let program = artifact.makeProgram(
                  expectedKey: key,
                  expectedOutputSemantics: outputSemantics,
                  expectedPremultipliedColorInputSlots:
                      premultipliedColorInputSlots,
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

    private static func fallback(
        state: RouteState,
        profile: CapabilityProfile,
        code: String,
        requestKey: String
    ) -> Resolution {
        routeTelemetry.record(
            state: state,
            profile: profile,
            outcome: profile.artifactFallbackOutcome(routeState: state),
            reason: code,
            requestKey: requestKey
        )
        return .unavailableOrDeferred(
            code: code,
            requestKey: requestKey,
            permitsBoundedFrontend: profile.permitsBoundedFrontendAfterArtifactFailure(
                routeState: state
            ),
            routeDecision: makeRouteDecision(
                profile: profile,
                state: state.rawValue
            )
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
            profile.ignoresLegacyProcessRoute ? nil : environment[routeEnvironment],
            defaultState: profile.defaultRouteState
        )
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
            .appendingPathComponent("SceneGenericShaderPrograms-v9", isDirectory: true)
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

}
