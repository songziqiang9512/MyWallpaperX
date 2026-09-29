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
/// input plus the frontend schema version, so any analyzer semantics change
/// that bumps either constant invalidates the whole tier as a safe miss.
nonisolated enum SceneGenericShaderAnalysisCache {
    /// The only invalidation lever for this tier: bump when any analyzer,
    /// normalizer or profile-classification semantic change lands (the shared
    /// frontendSchemaVersion constant has no mechanical bump guarantee).
    private static let schemaVersion = 1
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
        var data = Data()
        func append(_ value: String) {
            let encoded = Data(value.utf8)
            var length = UInt64(encoded.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(encoded)
        }
        func appendSlot(_ value: Int?) {
            append(value.map(String.init) ?? "-")
        }
        func appendSet(_ value: Set<Int>) {
            append(value.sorted().map(String.init).joined(separator: ","))
        }
        append("mwx-generic-shader-analysis-input-v1")
        append(String(SceneShaderVariantEnvironment.frontendSchemaVersion))
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
        appendSet(input.activeTextureSlots)
        appendSet(input.activeOpacityMaskSlots)
        appendSet(input.typedStaticDataAuxiliarySlots)
        appendSet(input.preservedChannelsExternalProviderTextureSlots)
        appendSet(input.premultipliedColorAuxiliarySlots)
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
        guard let loopBounds = encodeCodable(input.runtimeLoopBounds) else {
            return nil
        }
        append(loopBounds)
        return SceneGenericShaderProgramArtifact.sha256(data)
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
        guard let directory = cacheDirectory(),
              let digest = inputDigest(of: input) else { return nil }
        let url = directory.appendingPathComponent(
            "\(digest).json", isDirectory: false
        )
        guard let data = regularFileData(url),
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
        guard let directory = cacheDirectory(),
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
                    prune(directory)
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

    private static func cacheDirectory() -> URL? {
        let versionedName = "SceneGenericShaderAnalysis-v\(schemaVersion)"
        let environment = ProcessInfo.processInfo.environment
        if let rawRoot = environment["MWX_SCENE_GENERIC_SHADER_CACHE"] {
            // The override may point at a root shared with the program
            // artifact tier; keep a private subdirectory so pruning here can
            // never remove that tier's entries.
            guard let root = validatedDirectory(rawRoot) else { return nil }
            let scoped = root.appendingPathComponent(
                versionedName, isDirectory: true
            )
            do {
                try FileManager.default.createDirectory(
                    at: scoped, withIntermediateDirectories: true
                )
            } catch {
                return nil
            }
            return validatedDirectory(scoped.path)
        }
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else { return nil }
        let root = caches
            .appendingPathComponent(
                "com.songziqiang.MyWallpaperX", isDirectory: true
            )
            .appendingPathComponent(versionedName, isDirectory: true)
            .standardizedFileURL
        do {
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }
        return validatedDirectory(root.path)
    }

    private static func validatedDirectory(_ rawPath: String) -> URL? {
        guard !rawPath.isEmpty else { return nil }
        let url = URL(
            fileURLWithPath: rawPath, isDirectory: true
        ).standardizedFileURL
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true else { return nil }
        return url
    }

    private static func regularFileData(_ url: URL) -> Data? {
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let size = values?.fileSize,
              (1 ... maximumEntryBytes).contains(size) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func prune(_ directory: URL) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        var dated: [(URL, Date)] = []
        for url in entries where url.pathExtension == "json" {
            guard let date = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate else { continue }
            dated.append((url, date))
        }
        guard dated.count > retainedEntryLimit else { return }
        dated.sort { $0.1 < $1.1 }
        for (url, _) in dated.prefix(dated.count - retainedEntryLimit) {
            try? fileManager.removeItem(at: url)
        }
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
        let activeTextureSlots: Set<Int>
        let activeOpacityMaskSlots: Set<Int>
        let typedStaticDataAuxiliarySlots: Set<Int>
        let preservedChannelsExternalProviderTextureSlots: Set<Int>
        let premultipliedColorAuxiliarySlots: Set<Int>
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
    }

    struct Outcome {
        let resolution: SceneResolvedMaterialGenericShaderArtifactCache.Resolution
        let cacheHit: Bool
    }

    private let condition = NSCondition()
    private var accepted: [
        Input: SceneResolvedMaterialGenericShaderArtifactCache.Resolution
    ] = [:]
    private var inFlight: Set<Input> = []

    func perform(
        key: Input,
        operation: () -> SceneResolvedMaterialGenericShaderArtifactCache.Resolution
    ) -> Outcome {
        condition.lock()
        while true {
            if let resolution = accepted[key] {
                condition.unlock()
                return .init(resolution: resolution, cacheHit: true)
            }
            if inFlight.insert(key).inserted { break }
            condition.wait()
        }
        condition.unlock()

        let resolution = operation()

        condition.lock()
        if case .accepted = resolution {
            accepted[key] = resolution
        }
        inFlight.remove(key)
        condition.broadcast()
        condition.unlock()
        return .init(resolution: resolution, cacheHit: false)
    }
}

/// Shares compiler outcomes across equivalent launch-time requests after the
/// outer Program-resolution cache has admitted the exact authored inputs.
nonisolated final class SceneResolvedMaterialGenericShaderCompilationCoordinator:
    @unchecked Sendable
{
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
    private var completed: [
        String: Result<URL, SceneGenericShaderCompiler.Failure>
    ] = [:]

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

extension SceneResolvedMaterialGenericShaderArtifactCache {

    /// Load the pure analysis prefix from the persistent tier, or compute it
    /// through the analyzer family and publish it for later launches.
    static func resolvedAnalysis(
        for input: SceneResolvedMaterialGenericShaderResolutionCache.Input
    ) -> SceneGenericShaderAnalysis {
        if let cached = SceneGenericShaderAnalysisCache.load(input: input) {
            return cached
        }
        let computed = computeAnalysis(input: input)
        SceneGenericShaderAnalysisCache.store(
            analysis: computed,
            input: input
        )
        return computed
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
            .straightRGBScalarAlphaFact(fragmentSource: fragmentSource)
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
        let premultipliedColorInputSlots: Set<Int> = switch profile {
        case .providerBackedGraphInputSpatialWeightedColorBlend:
            spatialWeightedColorBlendExternalColorSlot.map { [$0] } ?? []
        case .sourceProvenGraphInputOverlayAlphaBlend,
             .sourceProvenGraphInputOverlayColorBlendAlphaPreserving,
             .sourceProvenGraphInputAssociatedOverBlend,
             .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha:
            premultipliedColorAuxiliarySlots
        default:
            []
        }
        // Approved product default for an unclassified color pass: graph
        // inputs and proven premultiplied provider slots cross the straight
        // color boundary and the terminal output is premultiplied once.
        let defaultBoundaryColorSlots: Set<Int> =
            colorTransfer.permitsDefaultStraightColorBoundary
            ? graphInputTextureSlots.union(premultipliedColorAuxiliarySlots)
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
