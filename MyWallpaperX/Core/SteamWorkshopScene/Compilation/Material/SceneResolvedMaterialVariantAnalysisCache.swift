import Foundation

/// Persistent tier for the per-variant compilation analysis prefix: the
/// canonicalized prepared sources, loop/combos/schema facts. Every cached
/// item is a deterministic
/// function of the key inputs (contract content, combos, inactive combo
/// providers, readiness, resolved texture formats, template declaration
/// shape, framebuffer identity and the RGBA8-unorm output flag), so a key
/// hit reproduces exactly the values a fresh computation would produce.
/// The fact-family analyzers, the eligibility slot resolutions and cheap
/// derived sets are deliberately NOT cached: the eligibility trio depends on
/// per-node template facts outside this key (graphRole, effectContext,
/// owner eligibility, exact candidate identities), so caching it would let
/// one node's admission authority leak to another node sharing the key.
/// `schemaVersion` is the sole invalidation lever: any change to shader
/// preparation, source canonicalization or any cached analyzer's semantics
/// must bump it and retire the tier as a safe miss. Entries publish only on
/// successful variant compilation, the read path never creates the cache
/// directory, and a failed or stale record degrades to a full recompute.
nonisolated enum SceneResolvedMaterialVariantAnalysisCache {
    private static let schemaVersion = 8
    private static let maximumEntryBytes = 512 * 1_024
    private static let retainedEntryLimit = 4_096
    private static let lock = NSLock()
    private static var pruned = false

    struct Record {
        let canonicalVertex: String
        let canonicalFragment: String
        let activeSamplerNames: Set<String>
        let resolvedIntegerCombos: [String: Int]
        let sourceActiveSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
        let sourceColorTransfer: SceneShaderColorTransfer
        let rgba8UnormAccumulatorSourceSlot: Int?
        let spatialWeightedColorBlend: SpatialWeightedColorBlendMirror?
        let sourceCarriedRGBA: SourceCarriedRGBAMirror?
        let conditionalGeneratedRGB: ConditionalGeneratedRGBMirror?
        let sameAlphaReconstructedRGB: SameAlphaReconstructedMirror?
        let neutralTextureResolution: NeutralTextureResolutionMirror?
        let alphaAttenuationFact: AuxiliaryRedCarrierMirror?
        let colorBlendFact: ColorBlendCarrierMirror?
        let previousBlurredCompositeFact: PreviousBlurredCompositeShapeMirror?
    }

    struct SpatialWeightedColorBlendMirror: Codable, Equatable {
        let sourceSlot: Int
        let straightColorSlot: Int
        let preservedRedAlphaSlot: Int
        let optionalMaskSlot: Int?
    }

    struct SourceCarriedRGBAMirror: Codable, Equatable {
        enum Transfer: String, Codable, Equatable { case preserving, straight }
        enum Shape: String, Codable, Equatable { case existing, generatedCarrier }
        let sourceSlot: Int
        let transfer: Transfer
        let shape: Shape
        let auxiliaryDataSlots: Set<Int>
    }

    struct ConditionalGeneratedRGBMirror: Codable, Equatable {
        let alphaCarrierSlot: Int
        let generatedOpaqueColorSlots: Set<Int>
        let scalarRedSlots: Set<Int>
        let scalarGreenSlots: Set<Int>
        let scalarBlueSlots: Set<Int>
        let scalarAlphaSlots: Set<Int>
    }

    struct SameAlphaReconstructedMirror: Codable, Equatable {
        let sourceSlot: Int
        let auxiliarySlots: Set<Int>
        let preservesSnapshotAlpha: Bool
    }

    struct NeutralTextureResolutionMirror: Codable, Equatable {
        let resolutionSlot: Int
        let coordinateTextureSlot: Int
        let varyingName: String
        let sourceComponents: String
        let targetComponents: String
    }

    struct AuxiliaryRedCarrierMirror: Codable, Equatable {
        let sourceSlot: Int
        let auxiliaryRedSlots: Set<Int>
    }

    struct ColorBlendCarrierMirror: Codable, Equatable {
        enum AlphaOutput: String, Codable, Equatable { case preserved, opaque }
        let sourceSlot: Int
        let auxiliaryRedSlots: Set<Int>
        let alphaOutput: AlphaOutput
    }

    struct PreviousBlurredCompositeShapeMirror: Codable, Equatable {
        let blurredSlot: Int
        let previousSlot: Int
        let maskSlot: Int?
        let colorUniform: String
    }

    private struct PersistedRecord: Codable {
        let canonicalVertex: String
        let canonicalFragment: String
        let activeSamplerNames: [String]
        let resolvedIntegerCombos: [ComboPair]
        let samplers: [ScenePersistentSamplerRecord]
        let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
        let sourceColorTransfer: SceneShaderColorTransfer
        let rgba8UnormAccumulatorSourceSlot: Int?
        let spatialWeightedColorBlend: SpatialWeightedColorBlendMirror?
        let sourceCarriedRGBA: SourceCarriedRGBAMirror?
        let conditionalGeneratedRGB: ConditionalGeneratedRGBMirror?
        let sameAlphaReconstructedRGB: SameAlphaReconstructedMirror?
        let neutralTextureResolution: NeutralTextureResolutionMirror?
        let alphaAttenuationFact: AuxiliaryRedCarrierMirror?
        let colorBlendFact: ColorBlendCarrierMirror?
        let previousBlurredCompositeFact: PreviousBlurredCompositeShapeMirror?
    }

    private struct ComboPair: Codable {
        let name: String
        let value: Int
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let keySHA256: String
        let recordSHA256: String
        let payload: PersistedRecord
    }

    // MARK: - Key

    static func keyDigest(
        contractIdentity: String,
        contractCanonicalSHA256: String,
        textureSlotShapes: [String?],
        combos: [String: Int],
        inheritedInactiveCombos: Set<String>,
        uniformDeclarations: [SceneResolvedMaterialTemplate.UniformDeclaration],
        compatibilityTarget: SceneShaderCompatibilityTarget,
        implicitFramebufferIdentity:
            SceneAuthoredEffectRenderPlan.TextureIdentity?,
        readinessMask: UInt8,
        resolvedTextureFormats: [Int: SceneShaderTextureFormat],
        outputIsRGBA8Unorm: Bool
    ) -> String? {
        var digest = ScenePersistentCacheDigest()
        digest.append("mwx-variant-analysis-key-v2")
        digest.append(contractIdentity)
        digest.append(contractCanonicalSHA256)
        for slot in textureSlotShapes {
            digest.append(slot ?? "-")
        }
        digest.append(
            combos.map { "\($0.key)=\($0.value)" }
                .sorted().joined(separator: ";")
        )
        digest.append(inheritedInactiveCombos.sorted().joined(separator: ";"))
        digest.append(
            uniformDeclarations
                .map { "\($0.name)=" + SceneMaterialDemandAnalysisPersistentCache.uniformValue($0.value) }
                .sorted().joined(separator: "\n")
        )
        digest.append(compatibilityTarget.rawValue)
        if let identity = implicitFramebufferIdentity {
            digest.append("identity:\(String(describing: identity))")
        } else {
            digest.append("identity:-")
        }
        digest.append("readiness:\(readinessMask)")
        digest.append(
            "formats:"
                + resolvedTextureFormats
                    .map { "\($0.key)=\($0.value.rawValue)" }
                    .sorted().joined(separator: ";")
        )
        digest.append(outputIsRGBA8Unorm ? "rgba8:1" : "rgba8:0")
        return digest.sha256Hex()
    }

    // MARK: - Payload projection

    private static func persisted(
        record: Record
    ) -> PersistedRecord {
        let mirrored = record.sourceActiveSamplers.keys.sorted().flatMap {
            slot -> [ScenePersistentSamplerRecord] in
            guard let sampler = record.sourceActiveSamplers[slot] else {
                return []
            }
            return [ScenePersistentSamplerRecord(sampler: sampler)]
        }.sorted {
            $0.slot != $1.slot
                ? $0.slot < $1.slot
                : $0.canonicalSortKey < $1.canonicalSortKey
        }
        return PersistedRecord(
            canonicalVertex: record.canonicalVertex,
            canonicalFragment: record.canonicalFragment,
            activeSamplerNames: record.activeSamplerNames.sorted(),
            resolvedIntegerCombos: record.resolvedIntegerCombos
                .map { ComboPair(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name },
            samplers: mirrored,
            runtimeLoopBounds: record.runtimeLoopBounds,
            sourceColorTransfer: record.sourceColorTransfer,
            rgba8UnormAccumulatorSourceSlot:
                record.rgba8UnormAccumulatorSourceSlot,
            spatialWeightedColorBlend: record.spatialWeightedColorBlend,
            sourceCarriedRGBA: record.sourceCarriedRGBA,
            conditionalGeneratedRGB: record.conditionalGeneratedRGB,
            sameAlphaReconstructedRGB: record.sameAlphaReconstructedRGB,
            neutralTextureResolution: record.neutralTextureResolution,
            alphaAttenuationFact: record.alphaAttenuationFact,
            colorBlendFact: record.colorBlendFact,
            previousBlurredCompositeFact: record.previousBlurredCompositeFact
        )
    }

    private static func recordDigest(
        _ payload: PersistedRecord
    ) -> String? {
        ScenePersistentCacheSupport.jsonPayloadSHA256(payload)
    }

    // MARK: - Load / store

    static func load(keySHA256: String) -> Record? {
        guard let directory = cacheDirectory(createIfNeeded: false) else {
            return nil
        }
        let url = directory.appendingPathComponent(
            "\(keySHA256).json", isDirectory: false
        )
        guard let data = ScenePersistentCacheSupport.regularFileData(
            url, maximumBytes: maximumEntryBytes
        ),
            let envelope = try? JSONDecoder().decode(
                Envelope.self, from: data
            ),
            envelope.schemaVersion == schemaVersion,
            envelope.keySHA256 == keySHA256,
            let recomputed = recordDigest(envelope.payload),
            recomputed == envelope.recordSHA256 else { return nil }
        var samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler] = [:]
        for mirrored in envelope.payload.samplers {
            guard let sampler = mirrored.rebuild() else { return nil }
            samplers[mirrored.slot] = sampler
        }
        let payload = envelope.payload
        return Record(
            canonicalVertex: payload.canonicalVertex,
            canonicalFragment: payload.canonicalFragment,
            activeSamplerNames: Set(payload.activeSamplerNames),
            resolvedIntegerCombos: Dictionary(
                uniqueKeysWithValues: payload.resolvedIntegerCombos
                    .map { ($0.name, $0.value) }
            ),
            sourceActiveSamplers: samplers,
            runtimeLoopBounds: payload.runtimeLoopBounds,
            sourceColorTransfer: payload.sourceColorTransfer,
            rgba8UnormAccumulatorSourceSlot:
                payload.rgba8UnormAccumulatorSourceSlot,
            spatialWeightedColorBlend: payload.spatialWeightedColorBlend,
            sourceCarriedRGBA: payload.sourceCarriedRGBA,
            conditionalGeneratedRGB: payload.conditionalGeneratedRGB,
            sameAlphaReconstructedRGB: payload.sameAlphaReconstructedRGB,
            neutralTextureResolution: payload.neutralTextureResolution,
            alphaAttenuationFact: payload.alphaAttenuationFact,
            colorBlendFact: payload.colorBlendFact,
            previousBlurredCompositeFact: payload.previousBlurredCompositeFact
        )
    }

    static func store(record: Record, keySHA256: String) {
        guard let directory = cacheDirectory(createIfNeeded: true) else {
            return
        }
        let payload = persisted(record: record)
        guard let recordSHA = recordDigest(payload) else { return }
        let envelope = Envelope(
            schemaVersion: schemaVersion,
            keySHA256: keySHA256,
            recordSHA256: recordSHA,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(envelope),
              (1 ... maximumEntryBytes).contains(data.count) else {
            return
        }
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
                        "\(keySHA256).json", isDirectory: false
                    ),
                    options: .atomic
                )
            } catch {
                // Cache publication is optional; the freshly computed
                // in-process result still serves this launch.
            }
        }
    }

    // MARK: - Directory

    private static func cacheDirectory(
        createIfNeeded: Bool
    ) -> URL? {
        ScenePersistentCacheSupport.versionedCacheDirectory(
            environmentKey: "MWX_SCENE_GENERIC_SHADER_CACHE",
            versionedName: "SceneVariantAnalysis-v\(schemaVersion)",
            createIfNeeded: createIfNeeded
        )
    }
}

// MARK: - Mirror ↔ analyzer fact rebuilds

extension SceneResolvedMaterialVariantAnalysisCache {

    static func rebuild(
        _ mirror: SpatialWeightedColorBlendMirror?
    ) -> SceneAuthoredShaderSpatialWeightedColorBlendFact? {
        guard let mirror else { return nil }
        return .init(
            sourceSlot: mirror.sourceSlot,
            straightColorSlot: mirror.straightColorSlot,
            preservedRedAlphaSlot: mirror.preservedRedAlphaSlot,
            optionalMaskSlot: mirror.optionalMaskSlot
        )
    }

    static func mirror(
        _ fact: SceneAuthoredShaderSpatialWeightedColorBlendFact
    ) -> SpatialWeightedColorBlendMirror {
        .init(
            sourceSlot: fact.sourceSlot,
            straightColorSlot: fact.straightColorSlot,
            preservedRedAlphaSlot: fact.preservedRedAlphaSlot,
            optionalMaskSlot: fact.optionalMaskSlot
        )
    }

    static func rebuild(
        _ mirror: SourceCarriedRGBAMirror?
    ) -> SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.SourceCarriedFact? {
        guard let mirror else { return nil }
        let transfer: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
            .SourceCarriedTransfer =
            mirror.transfer == .preserving ? .preserving : .straight
        let shape: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
            .SourceCarriedShape =
            mirror.shape == .existing ? .existing : .generatedCarrier
        return .init(
            sourceSlot: mirror.sourceSlot,
            transfer: transfer,
            shape: shape,
            auxiliaryDataSlots: mirror.auxiliaryDataSlots
        )
    }

    static func mirror(
        _ fact: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.SourceCarriedFact
    ) -> SourceCarriedRGBAMirror {
        .init(
            sourceSlot: fact.sourceSlot,
            transfer: fact.transfer == .preserving ? .preserving : .straight,
            shape: fact.shape == .existing ? .existing : .generatedCarrier,
            auxiliaryDataSlots: fact.auxiliaryDataSlots
        )
    }

    static func rebuild(
        _ mirror: ConditionalGeneratedRGBMirror?
    ) -> SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact? {
        guard let mirror else { return nil }
        return .init(
            alphaCarrierSlot: mirror.alphaCarrierSlot,
            generatedOpaqueColorSlots: mirror.generatedOpaqueColorSlots,
            scalarRedSlots: mirror.scalarRedSlots,
            scalarGreenSlots: mirror.scalarGreenSlots,
            scalarBlueSlots: mirror.scalarBlueSlots,
            scalarAlphaSlots: mirror.scalarAlphaSlots,
            sampleCallCounts: [:],
            generatedSampleCallCounts: [:],
            scalarRedSampleCallCounts: [:],
            scalarGreenSampleCallCounts: [:],
            scalarBlueSampleCallCounts: [:],
            scalarAlphaSampleCallCounts: [:]
        )
    }

    static func mirror(
        _ fact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact
    ) -> ConditionalGeneratedRGBMirror {
        .init(
            alphaCarrierSlot: fact.alphaCarrierSlot,
            generatedOpaqueColorSlots: fact.generatedOpaqueColorSlots,
            scalarRedSlots: fact.scalarRedSlots,
            scalarGreenSlots: fact.scalarGreenSlots,
            scalarBlueSlots: fact.scalarBlueSlots,
            scalarAlphaSlots: fact.scalarAlphaSlots
        )
    }

    static func rebuild(
        _ mirror: SameAlphaReconstructedMirror?
    ) -> SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact? {
        guard let mirror else { return nil }
        return SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact(
            mirror: mirror
        )
    }

    static func mirror(
        _ fact: SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact
    ) -> SameAlphaReconstructedMirror {
        .init(
            sourceSlot: fact.sourceSlot,
            auxiliarySlots: fact.auxiliarySlots,
            preservesSnapshotAlpha: fact.preservesSnapshotAlpha
        )
    }

    static func rebuild(
        _ mirror: NeutralTextureResolutionMirror?
    ) -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        guard let mirror else { return nil }
        return .init(
            resolutionSlot: mirror.resolutionSlot,
            coordinateTextureSlot: mirror.coordinateTextureSlot,
            varyingName: mirror.varyingName,
            sourceComponents: mirror.sourceComponents,
            targetComponents: mirror.targetComponents
        )
    }

    static func mirror(
        _ fact: SceneAuthoredShaderNeutralTextureResolutionFact
    ) -> NeutralTextureResolutionMirror {
        .init(
            resolutionSlot: fact.resolutionSlot,
            coordinateTextureSlot: fact.coordinateTextureSlot,
            varyingName: fact.varyingName,
            sourceComponents: fact.sourceComponents,
            targetComponents: fact.targetComponents
        )
    }

    static func rebuild(
        _ mirror: AuxiliaryRedCarrierMirror?
    ) -> SceneAuthoredShaderAlphaAttenuationFact? {
        guard let mirror else { return nil }
        return .init(
            sourceSlot: mirror.sourceSlot,
            auxiliaryRedSlots: mirror.auxiliaryRedSlots
        )
    }

    static func mirror(
        _ fact: SceneAuthoredShaderAlphaAttenuationFact
    ) -> AuxiliaryRedCarrierMirror {
        .init(
            sourceSlot: fact.sourceSlot,
            auxiliaryRedSlots: fact.auxiliaryRedSlots
        )
    }

    static func rebuild(
        _ mirror: ColorBlendCarrierMirror?
    ) -> SceneAuthoredShaderGraphInputColorBlendFact? {
        guard let mirror else { return nil }
        let alphaOutput: SceneAuthoredShaderGraphInputColorBlendFact
            .AlphaOutput =
            mirror.alphaOutput == .preserved ? .preserved : .opaque
        return .init(
            sourceSlot: mirror.sourceSlot,
            auxiliaryRedSlots: mirror.auxiliaryRedSlots,
            alphaOutput: alphaOutput
        )
    }

    static func mirror(
        _ fact: SceneAuthoredShaderGraphInputColorBlendFact
    ) -> ColorBlendCarrierMirror {
        .init(
            sourceSlot: fact.sourceSlot,
            auxiliaryRedSlots: fact.auxiliaryRedSlots,
            alphaOutput: fact.alphaOutput == .preserved ? .preserved : .opaque
        )
    }

    static func rebuild(
        _ mirror: PreviousBlurredCompositeShapeMirror?
    ) -> SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.Fact? {
        guard let mirror else { return nil }
        return .init(
            blurredSlot: mirror.blurredSlot,
            previousSlot: mirror.previousSlot,
            maskSlot: mirror.maskSlot,
            colorUniform: mirror.colorUniform
        )
    }

    static func mirror(
        _ fact: SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.Fact
    ) -> PreviousBlurredCompositeShapeMirror {
        .init(
            blurredSlot: fact.blurredSlot,
            previousSlot: fact.previousSlot,
            maskSlot: fact.maskSlot,
            colorUniform: fact.colorUniform
        )
    }
}

extension SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact {
    /// Rebuilds the fact from its persisted mirror. The sample-count
    /// dictionaries are not consumed by the compilation path (only the
    /// `auxiliarySlots` derivation is), so they are reconstructed to the
    /// exact stored slot set with one entry per slot.
    init(mirror: SceneResolvedMaterialVariantAnalysisCache.SameAlphaReconstructedMirror) {
        self.init(
            sourceSlot: mirror.sourceSlot,
            sourceSampleCallCounts: [:],
            dataSampleCallCounts: Dictionary(
                uniqueKeysWithValues: mirror.auxiliarySlots.sorted().map {
                    ($0, [:])
                }
            ),
            preservesSnapshotAlpha: mirror.preservesSnapshotAlpha
        )
    }
}
