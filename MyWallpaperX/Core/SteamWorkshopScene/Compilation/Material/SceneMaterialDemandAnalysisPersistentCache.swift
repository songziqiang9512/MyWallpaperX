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
    typealias ResourceDemandAnalysisKey =
        SceneResolvedMaterialRuntimeCatalog.ResourceDemandAnalysisKey
    private typealias Template = SceneResolvedMaterialTemplate
    private static let schemaVersion = 1
    private static let maximumEntryBytes = 256 * 1_024
    private static let retainedEntryLimit = 4_096
    private static let lock = NSLock()
    private static var pruned = false

    private struct PersistedSampler: Codable {
        let name: String
        let slot: Int
        let mode: String
        let materialKey: String?
        let labelKey: String?
        let formatKey: String?
        let isHidden: Bool
        let defaultTextureKind: Int?
        let defaultTextureValue: String?
        let readinessCombo: String?
        let channelUse: String
        let sourceProvenPurpose: String?
    }

    private struct PersistedSlot: Codable {
        let slot: Int
        let samplers: [PersistedSampler]
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

        private static func referenceKind(
            _ kind: SceneResolvedMaterialRuntimeCatalog
                .ResourceDemandReferenceKind
        ) -> String {
            switch kind {
            case .asset: return "a"
            case .userProperty: return "u"
            case .provider: return "p"
            case .graph: return "g"
            }
        }

        private static func uniformValue(
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

    private static func staticUniformCompact(
        _ value: Template.StaticUniformValue
    ) -> String {
        value.valueKind + ":"
            + value.componentBitPatterns
                .map { String($0, radix: 16) }.joined(separator: ",")
    }

    private static func uniformSource(
        _ source: Template.DynamicUniformSource
    ) -> String {
        switch source {
        case let .userProperty(key): return "u:\(key)"
        case .timeline: return "t"
        case .sceneScript: return "s"
        }
    }

        private static func particleField(
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

        private static func dynamicTarget(
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
            var mirrored: [PersistedSampler] = []
            for sampler in samplers[slot] ?? [] {
                let defaultKind: Int?
                let defaultValue: String?
                switch sampler.defaultTexture {
                case nil:
                    defaultKind = nil
                    defaultValue = nil
                case let .asset(path):
                    defaultKind = 0
                    defaultValue = path.value
                case let .internalTarget(name):
                    defaultKind = 1
                    defaultValue = name
                }
                mirrored.append(PersistedSampler(
                    name: sampler.name,
                    slot: sampler.slot,
                    mode: textureMode(sampler.mode),
                    materialKey: sampler.materialKey,
                    labelKey: sampler.labelKey,
                    formatKey: sampler.formatKey,
                    isHidden: sampler.isHidden,
                    defaultTextureKind: defaultKind,
                    defaultTextureValue: defaultValue,
                    readinessCombo: sampler.readinessCombo,
                    channelUse: sampler.channelUse.rawValue,
                    sourceProvenPurpose: sampler.sourceProvenPurpose
                        .map(loadPurpose)
                ))
            }
            // A stable order keeps the payload digest deterministic
            // across processes despite the Set iteration order.
            mirrored.sort {
                $0.name != $1.name
                    ? $0.name < $1.name
                    : canonicalSortKey($0) < canonicalSortKey($1)
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

    private static func canonicalSortKey(
        _ sampler: PersistedSampler
    ) -> String {
        [
            sampler.name, String(sampler.slot), sampler.mode,
            sampler.materialKey ?? "-", sampler.labelKey ?? "-",
            sampler.formatKey ?? "-", sampler.isHidden ? "1" : "0",
            sampler.defaultTextureKind.map(String.init) ?? "-",
            sampler.defaultTextureValue ?? "-",
            sampler.readinessCombo ?? "-", sampler.channelUse,
            sampler.sourceProvenPurpose ?? "-",
        ].joined(separator: "|")
    }

    private static func textureMode(
        _ mode: SceneResolvedMaterialShaderSchema.TextureMode
    ) -> String {
        switch mode {
        case .regular: return "regular"
        case .opacityMask: return "opacity-mask"
        case .rgbMask: return "rgb-mask"
        case .flowMask: return "flow-mask"
        case .depth: return "depth"
        }
    }

    private static func loadPurpose(
        _ purpose: SceneTextureLoadPurpose
    ) -> String {
        switch purpose {
        case .premultipliedColor: return "premultiplied-color"
        case .straightAlbedo: return "straight-albedo"
        case .preservedChannels: return "preserved-channels"
        case .mask: return "mask"
        case .noise: return "noise"
        case .flow: return "flow"
        case .phase: return "phase"
        case .normal: return "normal"
        case .depth: return "depth"
        case .lookupTable: return "lookup-table"
        }
    }

    private static func analysisDigest(
        _ payload: PersistedAnalysis
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else { return nil }
        return SceneGenericShaderProgramArtifact.sha256(data)
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
                guard let sampler = rebuild(mirrored) else { return nil }
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

    private static func rebuild(
        _ mirrored: PersistedSampler
    ) -> SceneResolvedMaterialShaderSchema.Sampler? {
        let mode: SceneResolvedMaterialShaderSchema.TextureMode
        switch mirrored.mode {
        case "regular": mode = .regular
        case "opacity-mask": mode = .opacityMask
        case "rgb-mask": mode = .rgbMask
        case "flow-mask": mode = .flowMask
        case "depth": mode = .depth
        default: return nil
        }
        let defaultTexture: SceneResolvedMaterialShaderSchema.DefaultTexture?
        switch mirrored.defaultTextureKind {
        case nil: defaultTexture = nil
        case 0:
            guard let value = mirrored.defaultTextureValue,
                  let path = SceneVFSAssetPath(value) else { return nil }
            defaultTexture = .asset(path)
        case 1:
            guard let value = mirrored.defaultTextureValue,
                  !value.isEmpty else { return nil }
            defaultTexture = .internalTarget(value)
        default: return nil
        }
        let purpose: SceneTextureLoadPurpose?
        switch mirrored.sourceProvenPurpose {
        case nil: purpose = nil
        case "premultiplied-color": purpose = .premultipliedColor
        case "straight-albedo": purpose = .straightAlbedo
        case "preserved-channels": purpose = .preservedChannels
        case "mask": purpose = .mask
        case "noise": purpose = .noise
        case "flow": purpose = .flow
        case "phase": purpose = .phase
        case "normal": purpose = .normal
        case "depth": purpose = .depth
        case "lookup-table": purpose = .lookupTable
        default: return nil
        }
        guard let channelUse = SceneAuthoredShaderProgram
            .TextureBinding.ChannelUse(rawValue: mirrored.channelUse)
        else { return nil }
        return SceneResolvedMaterialShaderSchema.Sampler(
            name: mirrored.name,
            slot: mirrored.slot,
            mode: mode,
            materialKey: mirrored.materialKey,
            labelKey: mirrored.labelKey,
            formatKey: mirrored.formatKey,
            isHidden: mirrored.isHidden,
            defaultTexture: defaultTexture,
            readinessCombo: mirrored.readinessCombo,
            channelUse: channelUse,
            sourceProvenPurpose: purpose
        )
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
