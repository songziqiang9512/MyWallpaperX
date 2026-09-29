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
    private static let schemaVersion = 1
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
    }

    private struct PersistedRecord: Codable {
        let canonicalVertex: String
        let canonicalFragment: String
        let activeSamplerNames: [String]
        let resolvedIntegerCombos: [ComboPair]
        let samplers: [ScenePersistentSamplerRecord]
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
        digest.append("mwx-variant-analysis-key-v1")
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
            samplers: mirrored
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
            sourceActiveSamplers: samplers
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
