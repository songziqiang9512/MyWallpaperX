import Foundation

/// Persistent tier for the per-variant material demand analysis; see the
/// in-process tier in SceneResolvedMaterialRuntimeCatalog for the
/// single-flight contract this extends across launches. The analysis re-pays
/// the prepared-source decode, canonicalization and source scans for every
/// distinct variant on every process, which measured as the dominant
/// warm-launch catalog cost. Entries mirror the exact in-process analysis
/// key as a digest; `schemaVersion` is the sole invalidation lever, so any
/// change to shader preparation, source canonicalization, sampler/channel
/// analysis or demand projection semantics must bump it and retire the tier
/// as a safe miss. Only ready results are published, and the read path never
/// creates the cache directory.
enum SceneMaterialDemandAnalysisPersistentCache {
/// Resource-demand reachability is a shader/template property, not a
/// material-node identity property. Authored graphs commonly instantiate
/// the same material many times; analyzing every node separately turns
/// launch into repeated preprocessing of identical shader variants.
enum ResourceDemandReferenceKind: Hashable {
    case asset
    case userProperty
    case provider
    case graph
}

struct ResourceDemandTextureSlotShape: Hashable {
    let index: Int
    let references: [ResourceDemandReferenceKind]
}

struct ResourceDemandAnalysisKey: Hashable {
    let shaderIdentity: String
    let shaderCanonicalSHA256: String
    let textureSlots: [ResourceDemandTextureSlotShape?]
    let combos: [Template.Combo]
    let inheritedInactiveCombos: [String]
    let uniformDeclarations: [Template.UniformDeclaration]
    let compatibilityTarget: SceneShaderCompatibilityTarget
    let hasImplicitFramebuffer: Bool

    init(
        template: Template,
        implicitFramebufferIdentity:
            SceneAuthoredEffectRenderPlan.TextureIdentity?
    ) {
        shaderIdentity = template.shaderContract.identity
        shaderCanonicalSHA256 = template.shaderContract.canonicalSHA256
        textureSlots = template.textureSlots.map { slot in
            slot.map {
                ResourceDemandTextureSlotShape(
                    index: $0.index,
                    references: $0.candidates.map { candidate in
                        switch candidate.reference {
                        case .asset: .asset
                        case .userProperty: .userProperty
                        case .provider: .provider
                        case .graph: .graph
                        }
                    }
                )
            }
        }
        combos = template.combos
        inheritedInactiveCombos = template.inheritedInactiveCombos
        uniformDeclarations = template.uniformDeclarations
        compatibilityTarget = template.compatibilityTarget
        hasImplicitFramebuffer = implicitFramebufferIdentity != nil
    }
}


    typealias Template = SceneResolvedMaterialTemplate
    private static let schemaVersion = 3
    private static let maximumEntryBytes = 256 * 1_024
    private static let retainedEntryLimit = 4_096
    private static let lock = NSLock()
    private static var pruned = false

        private struct PersistedSlot: Codable {
            let slot: Int
            let samplers: [ScenePersistentSamplerRecord]
        }

        private struct PersistedAnalysis: Codable {
            let textureFormatSlots: [Int]
            let samplers: [PersistedSlot]
        }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let keySHA256: String
        let analysisSHA256: String
        let payload: PersistedAnalysis
    }

    // MARK: - Key digest

    private static func keyDigest(
        _ key: ResourceDemandAnalysisKey
    ) -> String? {
        var digest = ScenePersistentCacheDigest()
        func append(_ value: String) {
            digest.append(value)
        }
        append("mwx-material-demand-analysis-key-v1")
        append(key.shaderIdentity)
        append(key.shaderCanonicalSHA256)
        for slot in key.textureSlots {
            guard let slot else {
                append("-")
                continue
            }
            append(
                "\(slot.index):"
                    + slot.references.map(referenceKind)
                        .joined(separator: ",")
            )
        }
        append(
            key.combos
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: ";")
        )
        append(key.inheritedInactiveCombos.joined(separator: ";"))
        append(
            key.uniformDeclarations
                .map { "\($0.name)=" + uniformValue($0.value) }
                .joined(separator: "\n")
        )
        append(key.compatibilityTarget.rawValue)
        append(key.hasImplicitFramebuffer ? "1" : "0")
        return digest.sha256Hex()
    }

        static func referenceKind(
            _ kind: ResourceDemandReferenceKind
        ) -> String {
            switch kind {
            case .asset: return "a"
            case .userProperty: return "u"
            case .provider: return "p"
            case .graph: return "g"
            }
        }

        static func uniformValue(
        _ value: Template.UniformValue
    ) -> String {
        switch value {
        case let .staticExact(staticValue):
            return "s|"
                + staticValue.valueKind + "|"
                + staticValue.componentBitPatterns
                    .map { String($0, radix: 16) }.joined(separator: ",")
                + "|"
                + staticValue.authoredBindingKeys.joined(separator: ",")
                + "|"
                + (staticValue.authoredScalarProjectionProven
                    ? "1" : "0")
        case let .dynamic(dynamic):
            return "d|"
                + dynamicTarget(dynamic.target) + "|"
                + dynamic.valueContributors
                    .map(uniformSource).joined(separator: ",") + "|"
                + String(dynamic.scriptAttachments.count) + "|"
                + (dynamic.authoredFallback.map {
                    "f:" + staticUniformCompact($0)
                } ?? "-") + "|"
                + dynamic.authoredBindingKeys.joined(separator: ",")
        }
    }

    static func staticUniformCompact(
        _ value: Template.StaticUniformValue
    ) -> String {
        value.valueKind + ":"
            + value.componentBitPatterns
                .map { String($0, radix: 16) }.joined(separator: ",")
    }

    static func uniformSource(
        _ source: Template.DynamicUniformSource
    ) -> String {
        switch source {
        case let .userProperty(key): return "u:\(key)"
        case .timeline: return "t"
        case .sceneScript: return "s"
        }
    }

        static func particleField(
            _ field: SceneDynamicParticleField
        ) -> String {
            switch field {
            case .alpha: return "alpha"
            case .size: return "size"
            case .lifetime: return "lifetime"
            case .rate: return "rate"
            case .speed: return "speed"
            case .count: return "count"
            case .brightness: return "brightness"
            case .color: return "color"
            case .normalizedColor: return "normalized-color"
            case let .controlPoint(index): return "control-point:\(index)"
            case let .controlPointAngles(index):
                return "control-point-angles:\(index)"
            }
        }

        static func dynamicTarget(
        _ target: SceneDynamicTarget
    ) -> String {
        switch target {
        case let .scene(field):
            return "scene:\(field.rawValue)"
        case let .camera(field):
            return "camera:\(field.rawValue)"
        case let .layer(layerID, field):
            return "layer:\(layerID):\(field.rawValue)"
        case let .effectVisibility(layerID, effectIndex):
            return "effect-visibility:\(layerID):\(effectIndex)"
        case let .effectConstant(
            layerID, effectIndex, passIndex, name
        ):
            return "effect-constant:\(layerID):\(effectIndex):\(passIndex):\(name)"
        case let .materialConstant(
            layerID, passIndex, name, materialPath
        ):
            return "material-constant:\(layerID):\(passIndex):\(name):\(materialPath)"
        case let .text(layerID, field):
            return "text:\(layerID):\(field.rawValue)"
        case let .particle(layerID, field):
            return "particle:\(layerID):\(particleField(field))"
        case let .scriptInstanceProperty(layerID, path):
            return "script:\(layerID):\(path.joined(separator: "/"))"
        }
    }

    // MARK: - Payload projection

        private static func persisted(
            textureFormatSlots: Set<Int>,
            samplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
        ) -> PersistedAnalysis? {
            var persistedSlots: [PersistedSlot] = []
            for slot in samplers.keys.sorted() {
                var mirrored: [ScenePersistentSamplerRecord] = []
                for sampler in samplers[slot] ?? [] {
                    mirrored.append(ScenePersistentSamplerRecord(
                        sampler: sampler
                    ))
                }
                // A stable order keeps the payload digest deterministic
                // across processes despite the Set iteration order.
                mirrored.sort {
                    $0.name != $1.name
                        ? $0.name < $1.name
                        : $0.canonicalSortKey < $1.canonicalSortKey
                }
                persistedSlots.append(
                    .init(slot: slot, samplers: mirrored)
                )
            }
            return PersistedAnalysis(
                textureFormatSlots: textureFormatSlots.sorted(),
                samplers: persistedSlots
            )
        }

    private static func analysisDigest(
        _ payload: PersistedAnalysis
    ) -> String? {
        ScenePersistentCacheSupport.jsonPayloadSHA256(payload)
    }

    // MARK: - Load / store

    static func load(
        key: ResourceDemandAnalysisKey
    ) -> (textureFormatSlots: Set<Int>, samplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>])? {
        guard let directory = cacheDirectory(createIfNeeded: false),
              let digest = keyDigest(key) else { return nil }
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
              envelope.keySHA256 == digest,
              let recomputed = analysisDigest(envelope.payload),
              recomputed == envelope.analysisSHA256 else { return nil }
        var samplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>] = [:]
        for slot in envelope.payload.samplers {
            var rebuilt: Set<SceneResolvedMaterialShaderSchema.Sampler> = []
            for mirrored in slot.samplers {
                guard let sampler = mirrored.rebuild() else { return nil }
                rebuilt.insert(sampler)
            }
            samplers[slot.slot] = rebuilt
        }
        return (
            Set(envelope.payload.textureFormatSlots),
            samplers
        )
    }

    static func store(
        textureFormatSlots: Set<Int>,
        samplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>],
        key: ResourceDemandAnalysisKey
    ) {
        guard let directory = cacheDirectory(createIfNeeded: true),
              let digest = keyDigest(key),
              let payload = persisted(
                  textureFormatSlots: textureFormatSlots,
                  samplers: samplers
              ),
              let analysisSHA = analysisDigest(payload) else { return }
        let envelope = Envelope(
            schemaVersion: schemaVersion,
            keySHA256: digest,
            analysisSHA256: analysisSHA,
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

    // MARK: - Directory

    private static func cacheDirectory(
        createIfNeeded: Bool
    ) -> URL? {
        ScenePersistentCacheSupport.versionedCacheDirectory(
            environmentKey: "MWX_SCENE_GENERIC_SHADER_CACHE",
            versionedName: "SceneMaterialDemandAnalysis-v\(schemaVersion)",
            createIfNeeded: createIfNeeded
        )
    }
}
