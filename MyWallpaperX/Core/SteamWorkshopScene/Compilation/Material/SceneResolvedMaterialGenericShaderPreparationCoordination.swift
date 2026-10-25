import Foundation

/// Pure analysis outcome of the generic-shader route admission that can be
/// reused across processes. It carries only derived admission facts; route
/// state, artifact lookup and compilation stay per-process decisions.
struct SceneGenericShaderAnalysis {
    let profile: SceneGenericShaderCapabilityProfile
    let colorTransfer: SceneShaderColorTransfer
    let expectedColorTransfer: SceneGenericShaderExpectedColorTransfer?
    let premultipliedColorInputSlots: Set<Int>
    let defaultBoundaryColorSlots: Set<Int>
}

/// Persistent tier for the generic-shader analysis prefix. The analyzer
/// family, source normalization and profile classification re-run on every
/// process even when the compiled artifact cache hits, which measured as the
/// dominant launch stage on shader-heavy scenes; this cache removes that
/// repeated CPU work. Entries are keyed by a digest over the full resolution
/// input and the build-time compiler identity. `schemaVersion` owns storage
/// compatibility; producer changes invalidate without a manual schema bump.
/// Only resolutions that end accepted are published, and the read path never
/// creates the cache directory; this follows the persistent-tier doctrine the
/// frontend/preparation cache tests already lock, and is deliberately
/// stricter than the program artifact tier's own read/write behaviour.
nonisolated enum SceneGenericShaderAnalysisCache {
    /// Storage contract version, independent of the automatic producer identity.
    /// v11: dead resource work shares the conservative deletion Projection.
    /// v13: shared varying-prefix proof and scalar/vector conversion semantics.
    /// v18: scalar-local RGBA reconstruction and helper purity proof.
    private static let schemaVersion = 18
    private static let maximumEntryBytes = 64 * 1_024
    private static let retainedEntryLimit = 4_096
    private static let lock = NSLock()
    private static var pruned = false

    struct ExpectedTransferMirror: Codable, Equatable {
        let cacheKey: String
        let accumulatorLoopWork: Int?
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let inputSHA256: String
        let analysisSHA256: String
        let profile: String
        let colorTransfer: SceneShaderColorTransfer
        let expectedTransfer: ExpectedTransferMirror?
        let premultipliedColorInputSlots: [Int]
        let defaultBoundaryColorSlots: [Int]
    }

    // MARK: - Input digest

    static func inputDigest(
        of input: SceneResolvedMaterialGenericShaderResolutionCache.Input
    ) -> String? {
        func encodeCodable(_ value: some Encodable) -> String? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(value) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        var digest = ScenePersistentCacheDigest()
        digest.append(SceneShaderCacheIdentity.semantics)
        func append(_ value: String) {
            digest.append(value)
        }
        func appendSlot(_ value: Int?) {
            append(value.map(String.init) ?? "-")
        }
        func appendSet(_ value: Set<Int>) {
            append(value.sorted().map(String.init).joined(separator: ","))
        }
        append("mwx-generic-shader-analysis-input-v2")
        append(input.vertexSource)
        append(input.fragmentSource)
        appendSlot(input.alphaAttenuationSourceSlot)
        appendSlot(input.colorBlendSourceSlot)
        appendSlot(input.previousBlurredCompositeBlurredSlot)
        appendSlot(input.previousBlurredCompositePreviousSlot)
        appendSlot(input.previousBlurredCompositeMaskSlot)
        append(input.hasExternalProviderTexture ? "1" : "0")
        append(input.producesScalarRedOutput ? "1" : "0")
        append(input.producesRedGreenUnormOutput ? "1" : "0")
        append(input.hasOnlyScalarDataInputs ? "1" : "0")
        append(input.isSourceIndependentPremultipliedOutput ? "1" : "0")
        appendSet(input.graphTextureSlots)
        appendSet(input.graphInputTextureSlots)
        appendSet(input.graphDataTextureSlots)
        appendSet(input.activeTextureSlots)
        appendSet(input.activeOpacityMaskSlots)
        appendSet(input.typedStaticDataAuxiliarySlots)
        appendSet(input.preservedChannelsExternalProviderTextureSlots)
        appendSet(input.premultipliedColorAuxiliarySlots)
        appendSet(input.sceneBackgroundColorSlots)
        appendSlot(input.spatialWeightedColorBlendSourceSlot)
        appendSet(input.spatialWeightedColorBlendActiveSlots)
        appendSet(input.spatialWeightedColorBlendTypedAuxiliarySlots)
        appendSlot(input.spatialWeightedColorBlendExternalColorSlot)
        appendSet(input.r8TextureSlots)
        append(input.hasDefaultedOpacityMaskSampler ? "1" : "0")
        append(input.hasOnlyTypedOpacityMaskAuxiliary ? "1" : "0")
        append(input.hasOnlyGraphInputSampler ? "1" : "0")
        append(input.outputIsRGBA8Unorm ? "1" : "0")
        guard let sourceTransfer = encodeCodable(
            input.sourceColorTransfer
        ) else { return nil }
        append(sourceTransfer)
        append(input.outputSemantics.rawValue)
        append(input.colorBoundary?.cacheKey ?? "-")
        guard let loopBounds = encodeCodable(input.runtimeLoopBounds) else {
            return nil
        }
        append(loopBounds)
        return digest.sha256Hex()
    }

    // MARK: - Analysis digest

    private static func analysisDigest(
        profile: String,
        colorTransfer: SceneShaderColorTransfer,
        expectedTransfer: ExpectedTransferMirror?,
        premultipliedColorInputSlots: Set<Int>,
        defaultBoundaryColorSlots: Set<Int>
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = Envelope(
            schemaVersion: schemaVersion,
            inputSHA256: "",
            analysisSHA256: "",
            profile: profile,
            colorTransfer: colorTransfer,
            expectedTransfer: expectedTransfer,
            premultipliedColorInputSlots:
                premultipliedColorInputSlots.sorted(),
            defaultBoundaryColorSlots: defaultBoundaryColorSlots.sorted()
        )
        guard let data = try? encoder.encode(payload) else { return nil }
        return SceneGenericShaderProgramArtifact.sha256(data)
    }

    // MARK: - Load / store

    static func load(
        input: SceneResolvedMaterialGenericShaderResolutionCache.Input
    ) -> SceneGenericShaderAnalysis? {
        guard let directory = cacheDirectory(createIfNeeded: false),
              let digest = inputDigest(of: input) else { return nil }
        let url = directory.appendingPathComponent(
            "\(digest).json", isDirectory: false
        )
        guard let data = ScenePersistentCacheSupport.regularFileData(
            url, maximumBytes: maximumEntryBytes
            ),
              let envelope = try? JSONDecoder().decode(
                  Envelope.self, from: data
              ),
              envelope.schemaVersion == schemaVersion,
              envelope.inputSHA256 == digest,
              let recomputed = analysisDigest(
                  profile: envelope.profile,
                  colorTransfer: envelope.colorTransfer,
                  expectedTransfer: envelope.expectedTransfer,
                  premultipliedColorInputSlots:
                      Set(envelope.premultipliedColorInputSlots),
                  defaultBoundaryColorSlots:
                      Set(envelope.defaultBoundaryColorSlots)
              ),
              recomputed == envelope.analysisSHA256,
              let profile = SceneGenericShaderCapabilityProfile(
                  rawValue: envelope.profile
              ) else { return nil }
        var expectedTransfer: SceneGenericShaderExpectedColorTransfer?
        if let mirror = envelope.expectedTransfer {
            guard let rebuilt = rebuildExpectedTransfer(
                from: mirror,
                colorTransfer: envelope.colorTransfer,
                profile: profile
            ) else { return nil }
            expectedTransfer = rebuilt
        }
        return SceneGenericShaderAnalysis(
            profile: profile,
            colorTransfer: envelope.colorTransfer,
            expectedColorTransfer: expectedTransfer,
            premultipliedColorInputSlots:
                Set(envelope.premultipliedColorInputSlots),
            defaultBoundaryColorSlots:
                Set(envelope.defaultBoundaryColorSlots)
        )
    }

    static func store(
        analysis: SceneGenericShaderAnalysis,
        input: SceneResolvedMaterialGenericShaderResolutionCache.Input
    ) {
        guard let directory = cacheDirectory(createIfNeeded: true),
              let digest = inputDigest(of: input) else { return }
        let expectedMirror = analysis.expectedColorTransfer.map {
            ExpectedTransferMirror(
                cacheKey: $0.cacheKey,
                accumulatorLoopWork: $0.accumulatorLoopWork
            )
        }
        guard let analysisSHA = analysisDigest(
            profile: analysis.profile.rawValue,
            colorTransfer: analysis.colorTransfer,
            expectedTransfer: expectedMirror,
            premultipliedColorInputSlots:
                analysis.premultipliedColorInputSlots,
            defaultBoundaryColorSlots: analysis.defaultBoundaryColorSlots
        ) else { return }
        let envelope = Envelope(
            schemaVersion: schemaVersion,
            inputSHA256: digest,
            analysisSHA256: analysisSHA,
            profile: analysis.profile.rawValue,
            colorTransfer: analysis.colorTransfer,
            expectedTransfer: expectedMirror,
            premultipliedColorInputSlots:
                analysis.premultipliedColorInputSlots.sorted(),
            defaultBoundaryColorSlots:
                analysis.defaultBoundaryColorSlots.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(envelope),
              (1 ... maximumEntryBytes).contains(data.count) else { return }
        lock.withLock {
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                if !pruned {
                    ScenePersistentCacheSupport.prune(
                        directory, retainedEntryLimit: retainedEntryLimit
                    )
                    pruned = true
                }
                try data.write(
                    to: directory.appendingPathComponent(
                        "\(digest).json", isDirectory: false
                    ),
                    options: .atomic
                )
            } catch {
                // Cache publication is optional; the freshly computed
                // in-process result still serves this launch.
            }
        }
    }

    /// Rebuilds the validated transfer value from stored facts. Both
    /// profile-derived booleans mirror the live derivation in the artifact
    /// cache resolve path; a mismatch in the validating initializer or the
    /// cache key rejects the entry as a miss.
    private static func rebuildExpectedTransfer(
        from mirror: ExpectedTransferMirror,
        colorTransfer: SceneShaderColorTransfer,
        profile: SceneGenericShaderCapabilityProfile
    ) -> SceneGenericShaderExpectedColorTransfer? {
        let rebuilt = SceneGenericShaderExpectedColorTransfer(
            colorTransfer,
            accumulatorLoopWork: mirror.accumulatorLoopWork,
            usesRGBA8UnormAttachmentBoundary:
                profile == .sourceProvenGraphTargetIndependentSignalUNormAccumulator,
            permitsStraightAlphaPreserving:
                profile == .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary
                || profile
                    == .sourceProvenGraphInputStageUniformStraightAlphaPreservingStaticAuxiliary
                || profile == .sourceProvenGraphInputOverlayColorBlendAlphaPreserving
                || profile == .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha
        )
        return rebuilt?.cacheKey == mirror.cacheKey ? rebuilt : nil
    }

    // MARK: - Directory

    private static func cacheDirectory(
        createIfNeeded: Bool
    ) -> URL? {
        ScenePersistentCacheSupport.versionedCacheDirectory(
            environmentKey: "MWX_SCENE_GENERIC_SHADER_CACHE",
            versionedName: "SceneGenericShaderAnalysis-v\(schemaVersion)",
            createIfNeeded: createIfNeeded
        )
    }
}

/// Process-lifetime single-flight for immutable accepted generic Programs.
/// Failures are deliberately not cached so a repairable compiler/cache failure
/// can retry without requiring a new process.
nonisolated final class SceneResolvedMaterialGenericShaderResolutionCache:
    @unchecked Sendable
{
    struct Input: Hashable {
        let vertexSource: String
        let fragmentSource: String
        let alphaAttenuationSourceSlot: Int?
        let colorBlendSourceSlot: Int?
        let previousBlurredCompositeBlurredSlot: Int?
        let previousBlurredCompositePreviousSlot: Int?
        let previousBlurredCompositeMaskSlot: Int?
        let hasExternalProviderTexture: Bool
        let producesScalarRedOutput: Bool
        let producesRedGreenUnormOutput: Bool
        let hasOnlyScalarDataInputs: Bool
        let isSourceIndependentPremultipliedOutput: Bool
        let graphTextureSlots: Set<Int>
        let graphInputTextureSlots: Set<Int>
        let graphDataTextureSlots: Set<Int>
        let activeTextureSlots: Set<Int>
        let activeOpacityMaskSlots: Set<Int>
        let typedStaticDataAuxiliarySlots: Set<Int>
        let preservedChannelsExternalProviderTextureSlots: Set<Int>
        let premultipliedColorAuxiliarySlots: Set<Int>
        let sceneBackgroundColorSlots: Set<Int>
        let spatialWeightedColorBlendSourceSlot: Int?
        let spatialWeightedColorBlendActiveSlots: Set<Int>
        let spatialWeightedColorBlendTypedAuxiliarySlots: Set<Int>
        let spatialWeightedColorBlendExternalColorSlot: Int?
        let r8TextureSlots: Set<Int>
        let hasDefaultedOpacityMaskSampler: Bool
        let hasOnlyTypedOpacityMaskAuxiliary: Bool
        let hasOnlyGraphInputSampler: Bool
        let outputIsRGBA8Unorm: Bool
        let sourceColorTransfer: SceneShaderColorTransfer?
        let outputSemantics: SceneGenericShaderOutputSemantics
        let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
        var colorBoundary: SceneShaderColorBoundary? = nil

        func retainedCost(
            program: SceneAuthoredShaderProgram, premultipliedColorInputSlots: Set<Int>, requestKey: String,
            decision: SceneGenericShaderRouteDecision
        ) -> Int {
            var cost = SceneShaderCacheCost()
            cost.string(vertexSource)
            cost.string(fragmentSource)
            for count in [graphTextureSlots.count, graphInputTextureSlots.count,
                graphDataTextureSlots.count, activeTextureSlots.count, activeOpacityMaskSlots.count,
                typedStaticDataAuxiliarySlots.count, preservedChannelsExternalProviderTextureSlots.count,
                premultipliedColorAuxiliarySlots.count, sceneBackgroundColorSlots.count,
                spatialWeightedColorBlendActiveSlots.count, spatialWeightedColorBlendTypedAuxiliarySlots.count,
                r8TextureSlots.count] { cost.slots(count) }
            cost.runtimeLoopBounds(runtimeLoopBounds)
            cost.colorTransfer(sourceColorTransfer)
            cost.colorBoundary(colorBoundary)
            cost.program(program)
            cost.slots(premultipliedColorInputSlots.count)
            cost.string(requestKey)
            cost.string(decision.profile)
            cost.string(decision.state)
            cost.string(decision.fallbackOwner)
            return cost.bytes
        }
    }

    struct Outcome {
        let resolution: SceneResolvedMaterialGenericShaderArtifactCache.Resolution
        let cacheHit: Bool
    }

    private let condition = NSCondition()
    private var accepted: SceneShaderCompletedCacheStorage<
        Input, SceneResolvedMaterialGenericShaderArtifactCache.Resolution
    >
    private var inFlight: [Input: SceneShaderCacheFlight<
        SceneResolvedMaterialGenericShaderArtifactCache.Resolution
    >] = [:]

    init(maximumBytes: Int = 16 * 1_024 * 1_024, maximumEntries: Int = 1_024) {
        accepted = .init(maximumBytes: maximumBytes, maximumEntries: maximumEntries)
    }

    var snapshot: SceneShaderCompletedCacheSnapshot {
        condition.lock()
        defer { condition.unlock() }
        return .init(completedEntries: accepted.count, retainedBytes: accepted.retainedBytes,
            inFlightOperations: inFlight.count,
            waitingCallers: inFlight.values.reduce(0) { $0 + $1.waiters })
    }

    func perform(
        key: Input,
        operation: () -> SceneResolvedMaterialGenericShaderArtifactCache.Resolution
    ) -> Outcome {
        condition.lock()
        if let resolution = accepted.value(for: key) {
            condition.unlock()
            return .init(resolution: resolution, cacheHit: true)
        }
        if let flight = inFlight[key] {
            flight.waiters += 1
            while case .none = flight.result { condition.wait() }
            let resolution = flight.result!
            flight.waiters -= 1
            condition.unlock()
            return .init(resolution: resolution, cacheHit: true)
        }
        let flight = SceneShaderCacheFlight<SceneResolvedMaterialGenericShaderArtifactCache.Resolution>()
        inFlight[key] = flight
        condition.unlock()

        let resolution = operation()
        let retainedCost: Int?
        if case let .accepted(program, slots, requestKey, decision) = resolution {
            retainedCost = key.retainedCost(program: program, premultipliedColorInputSlots: slots,
                requestKey: requestKey, decision: decision)
        } else { retainedCost = nil }

        condition.lock()
        if let retainedCost {
            accepted.insert(resolution, for: key, cost: retainedCost)
        }
        flight.result = resolution
        inFlight.removeValue(forKey: key)
        condition.broadcast()
        condition.unlock()
        return .init(resolution: resolution, cacheHit: false)
    }
}

/// Shares an active compiler operation across equivalent launch-time requests.
/// Accepted Programs remain in the outer bounded resolution cache; a completed
/// URL is not proof that a disk entry still exists or satisfies its contract.
nonisolated final class SceneResolvedMaterialGenericShaderCompilationCoordinator:
    @unchecked Sendable
{
    typealias ProductResult = Result<
        SceneAuthoredShaderProgram,
        SceneResolvedMaterialGenericShaderArtifactCache.ProgramLoadFailure
    >

    /// An accepted Program belongs to its actual consumption contract, which
    /// can be more specific than the compiler's persistent artifact key.
    struct Key: Hashable, Sendable {
        let requestKey: String
        let outputSemantics: SceneGenericShaderOutputSemantics
        let premultipliedColorInputSlots: Set<Int>
        let colorBoundary: SceneShaderColorBoundary?
        let colorTransfer: SceneShaderColorTransfer
        let fragmentOutputChannelUse:
            SceneAuthoredShaderProgram.FragmentOutputChannelUse
    }

    enum Source: String {
        case spawn
        case joinedFlight = "joined-flight"
    }

    struct Outcome {
        let result: ProductResult
        let source: Source
    }

    private let condition = NSCondition()
    private var active: [Key: SceneShaderCacheFlight<ProductResult>] = [:]
    var snapshot: SceneShaderCompletedCacheSnapshot {
        condition.lock()
        defer { condition.unlock() }
        return .init(completedEntries: 0, retainedBytes: 0,
            inFlightOperations: active.count,
            waitingCallers: active.values.reduce(0) { $0 + $1.waiters })
    }

    func perform(
        key: Key,
        operation: () -> ProductResult
    ) -> Outcome {
        condition.lock()
        if let flight = active[key] {
            flight.waiters += 1
            while case .none = flight.result { condition.wait() }
            let result = flight.result!
            flight.waiters -= 1
            condition.unlock()
            return .init(result: result, source: .joinedFlight)
        }
        let flight = SceneShaderCacheFlight<ProductResult>()
        active[key] = flight
        condition.unlock()

        let result = operation()
        condition.lock()
        // Existing waiters consume this accepted Program or failure. Nothing
        // is retained: later requests read their current cache entry again.
        flight.result = result
        active.removeValue(forKey: key)
        condition.broadcast()
        condition.unlock()
        return .init(result: result, source: .spawn)
    }
}

nonisolated extension SceneResolvedMaterialGenericShaderArtifactCache {

    /// Load the pure analysis prefix from the persistent tier, or compute it
    /// through the analyzer family. Publication is the caller's decision: the
    /// persistent tier only holds entries whose final resolution was accepted,
    /// following the persistent-tier doctrine (see
    /// test_scene_shader_persistent_cache's only-stores-accepted-products
    /// contract for the frontend/preparation tiers).
    static func resolvedAnalysis(
        for input: SceneResolvedMaterialGenericShaderResolutionCache.Input
    ) -> (analysis: SceneGenericShaderAnalysis, fromCache: Bool) {
        if let cached = SceneGenericShaderAnalysisCache.load(input: input) {
            return (cached, true)
        }
        return (computeAnalysis(input: input), false)
    }

    /// The deterministic analyzer-family prefix of a generic-shader route
    /// resolution. Extracted verbatim from the artifact-cache resolve path;
    /// its outputs are exactly the facts the persistent analysis tier caches.
    static func computeAnalysis(
        input: SceneResolvedMaterialGenericShaderResolutionCache.Input
    ) -> SceneGenericShaderAnalysis {
        let vertexSource = input.vertexSource
        let fragmentSource = input.fragmentSource
        let sourceColorTransfer = input.sourceColorTransfer
        let alphaAttenuationSourceSlot = input.alphaAttenuationSourceSlot
        let colorBlendSourceSlot = input.colorBlendSourceSlot
        let previousBlurredCompositeBlurredSlot =
            input.previousBlurredCompositeBlurredSlot
        let previousBlurredCompositePreviousSlot =
            input.previousBlurredCompositePreviousSlot
        let previousBlurredCompositeMaskSlot =
            input.previousBlurredCompositeMaskSlot
        let hasExternalProviderTexture = input.hasExternalProviderTexture
        let producesScalarRedOutput = input.producesScalarRedOutput
        let producesRedGreenUnormOutput = input.producesRedGreenUnormOutput
        let hasOnlyScalarDataInputs = input.hasOnlyScalarDataInputs
        let isSourceIndependentPremultipliedOutput =
            input.isSourceIndependentPremultipliedOutput
        let graphTextureSlots = input.graphTextureSlots
        let graphInputTextureSlots = input.graphInputTextureSlots
        let activeTextureSlots = input.activeTextureSlots
        let activeOpacityMaskSlots = input.activeOpacityMaskSlots
        let typedStaticDataAuxiliarySlots = input.typedStaticDataAuxiliarySlots
        let preservedChannelsExternalProviderTextureSlots =
            input.preservedChannelsExternalProviderTextureSlots
        let premultipliedColorAuxiliarySlots =
            input.premultipliedColorAuxiliarySlots
        let spatialWeightedColorBlendSourceSlot =
            input.spatialWeightedColorBlendSourceSlot
        let spatialWeightedColorBlendActiveSlots =
            input.spatialWeightedColorBlendActiveSlots
        let spatialWeightedColorBlendTypedAuxiliarySlots =
            input.spatialWeightedColorBlendTypedAuxiliarySlots
        let spatialWeightedColorBlendExternalColorSlot =
            input.spatialWeightedColorBlendExternalColorSlot
        let r8TextureSlots = input.r8TextureSlots
        let hasDefaultedOpacityMaskSampler =
            input.hasDefaultedOpacityMaskSampler
        let hasOnlyTypedOpacityMaskAuxiliary =
            input.hasOnlyTypedOpacityMaskAuxiliary
        let hasOnlyGraphInputSampler = input.hasOnlyGraphInputSampler
        let outputIsRGBA8Unorm = input.outputIsRGBA8Unorm
        let outputSemantics = input.outputSemantics
        let runtimeLoopBounds = input.runtimeLoopBounds

        let colorSourceAnalysis = SceneAuthoredShaderColorTransferAnalyzer
            .SourceAnalysis(fragmentSource: fragmentSource)
        let colorTransfer = sourceColorTransfer
            ?? SceneAuthoredShaderColorTransferAnalyzer.analyze(
                sourceAnalysis: colorSourceAnalysis
            )
        let conditionalStraightUnionSourceSlot =
            SceneAuthoredShaderColorTransferAnalyzer
                .conditionalStraightUnionSourceSlot(
                    sourceAnalysis: colorSourceAnalysis
                )
        let singleSamplerAlphaMutationSourceSlot =
            SceneAuthoredShaderColorTransferAnalyzer
                .singleSamplerAlphaMutationSourceSlot(
                    sourceAnalysis: colorSourceAnalysis
                )
        let sameSlotChannelReconstructionSourceSlot =
            SceneAuthoredShaderColorTransferAnalyzer
                .sameSlotChannelReconstructionSourceSlot(
                    sourceAnalysis: colorSourceAnalysis
                )
        let blendSourceSlots = SceneAuthoredShaderColorTransferAnalyzer
            .blendSourceSlots(sourceAnalysis: colorSourceAnalysis)
        let associatedOverBlendFact =
            SceneAuthoredShaderAssociatedOverBlendAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
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
            .straightRGBScalarAlphaFact(sourceAnalysis: colorSourceAnalysis)
        let preservedAlphaRGBFilterTextureSlots =
            preservedAlphaRGBFilterFact?.sampledTextureSlots ?? []
        let previousBlurredCompositeSourceFact =
            SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let normalizedRouteFacts: SceneGenericShaderSourceNormalizer.Pair?
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            maximumStageSourceBytes:
                SceneResolvedMaterialGenericShaderArtifactCache
                    .maximumRouteAnalysisSourceBytes
        ) {
        case let .success(value): normalizedRouteFacts = value
        case .failure: normalizedRouteFacts = nil
        }
        let activeAudioSpectrumArrays =
            normalizedRouteFacts?.activeAudioSpectrumArrays ?? []
        let profile = SceneGenericShaderCapabilityProfile(
            fragmentSource: fragmentSource,
            colorTransfer: colorTransfer,
            alphaAttenuationSourceSlot: alphaAttenuationSourceSlot,
            colorBlendSourceSlot: colorBlendSourceSlot,
            overlayAlphaBlendSourceSlot: blendSourceSlots.overlayAlpha?.source,
            overlayAlphaBlendAuxiliarySlot: blendSourceSlots.overlayAlpha?.overlay,
            overlayAlphaPreservingBlendSourceSlot:
                blendSourceSlots.overlayAlphaPreserving?.source,
            overlayAlphaPreservingBlendAuxiliarySlot:
                blendSourceSlots.overlayAlphaPreserving?.overlay,
            associatedOverBlendSourceSlot: associatedOverBlendFact?.sourceSlot,
            associatedOverBlendOverlaySlot: associatedOverBlendFact?.overlaySlot,
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
                SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
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
            preservedChannelsExternalProviderTextureSlots:
                preservedChannelsExternalProviderTextureSlots,
            premultipliedColorAuxiliarySlots:
                premultipliedColorAuxiliarySlots,
            spatialWeightedColorBlendSourceSlot:
                spatialWeightedColorBlendSourceSlot,
            spatialWeightedColorBlendActiveSlots:
                spatialWeightedColorBlendActiveSlots,
            spatialWeightedColorBlendTypedAuxiliarySlots:
                spatialWeightedColorBlendTypedAuxiliarySlots,
            spatialWeightedColorBlendExternalColorSlot:
                spatialWeightedColorBlendExternalColorSlot,
            previousBlurredCompositeBlurredSlot: previousBlurredCompositeBlurredSlot,
            previousBlurredCompositePreviousSlot: previousBlurredCompositePreviousSlot,
            previousBlurredCompositeMaskSlot: previousBlurredCompositeMaskSlot,
            previousBlurredCompositeSourceBlurredSlot:
                previousBlurredCompositeSourceFact?.blurredSlot,
            previousBlurredCompositeSourcePreviousSlot:
                previousBlurredCompositeSourceFact?.previousSlot,
            previousBlurredCompositeSourceMaskSlot: previousBlurredCompositeSourceFact?.maskSlot,
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
                    sourceAnalysis: colorSourceAnalysis
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
            usesRGBA8UnormAttachmentBoundary:
                profile
                    == .sourceProvenGraphTargetIndependentSignalUNormAccumulator,
            permitsStraightAlphaPreserving:
                profile
                    == .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary
                    || profile
                        == .sourceProvenGraphInputStageUniformStraightAlphaPreservingStaticAuxiliary
                    || profile
                        == .sourceProvenGraphInputOverlayColorBlendAlphaPreserving
                    || profile
                        == .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha
        )
        let profileInputSlots: Set<Int> = switch profile {
        case .providerBackedGraphInputSpatialWeightedColorBlend:
            spatialWeightedColorBlendExternalColorSlot.map { [$0] } ?? []
        case .ordinaryShader:
            outputSemantics == .color ? premultipliedColorAuxiliarySlots : []
        case .sourceProvenGraphInputOverlayAlphaBlend,
             .sourceProvenGraphInputOverlayColorBlendAlphaPreserving,
             .sourceProvenGraphInputAssociatedOverBlend,
             .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha:
            premultipliedColorAuxiliarySlots
        default:
            []
        }
        let premultipliedColorInputSlots = profileInputSlots
            .union(input.sceneBackgroundColorSlots)
        // Approved product default for an unclassified color pass: graph
        // color inputs (excluding producer-proven data) and premultiplied providers cross the straight
        // color boundary and the terminal output is premultiplied once.
        let defaultBoundaryColorSlots: Set<Int> =
            colorTransfer.permitsDefaultStraightColorBoundary
            ? graphInputTextureSlots.subtracting(input.graphDataTextureSlots)
                .union(premultipliedColorAuxiliarySlots)
                .union(input.sceneBackgroundColorSlots)
            : []
        return SceneGenericShaderAnalysis(
            profile: profile,
            colorTransfer: colorTransfer,
            expectedColorTransfer: expectedColorTransfer,
            premultipliedColorInputSlots: premultipliedColorInputSlots,
            defaultBoundaryColorSlots: defaultBoundaryColorSlots
        )
    }
}
