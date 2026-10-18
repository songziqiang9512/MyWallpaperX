// Appended to the persistent-cache behavior harness so domain fixtures and the
// production source closure remain shared. All sources below are self-authored.
private func dependencyContract(
    value: String,
    staleMarkers: Bool = false
) -> SceneShaderContract {
    let stages = [
        makeProgramStage(.vertex, path: "shaders/dependency.vert", source:
            "attribute vec3 a_Position;\nvoid main() { gl_Position = vec4(a_Position, 1.0); }\n"),
        makeProgramStage(.fragment, path: "shaders/dependency.frag", source:
            "#include \"dependency.inc\"\nvoid main() { gl_FragColor = vec4(INCLUDE_VALUE); }\n"),
    ]
    let include = "#define INCLUDE_VALUE \(value)\n"
    let originalInclude = "#define INCLUDE_VALUE 0.25\n"
    let includeSHA = SceneShaderStableDigest.hash(
        Data((staleMarkers ? originalInclude : include).utf8)
    )
    let nodes = stages.map { stage in
        SceneShaderSourceGraph.Node(
            virtualPath: stage.relativePath, provenance: .loose,
            source: stage.source, rawSHA256: stage.rawSHA256,
            byteCount: stage.source.utf8.count
        )
    } + [.init(virtualPath: "shaders/dependency.inc", provenance: .loose,
        source: include, rawSHA256: includeSHA,
        byteCount: (staleMarkers ? originalInclude : include).utf8.count)]
    let edges = [SceneShaderSourceGraph.Edge(
        parentVirtualPath: "shaders/dependency.frag", line: 1,
        request: "dependency.inc",
        candidates: [.init(virtualPath: "shaders/dependency.inc",
            provenance: .loose, outcome: .resolved(rawSHA256: includeSHA))],
        outcome: .resolved(virtualPath: "shaders/dependency.inc")
    )]
    let graph = SceneShaderSourceGraph(
        roots: stages.map {
            .init(label: $0.kind.rawValue, virtualPath: $0.relativePath)
        }, nodes: nodes, edges: edges, diagnostics: [],
        dependencySHA256: staleMarkers ? "unchanged-self-reported-marker"
            : SceneShaderSourceGraph.dependencySHA256(nodes: nodes, edges: edges)
    )
    return .init(identity: "dependency", sourceKind: .authoredSource,
        stages: stages, diagnostics: [],
        canonicalSHA256: SceneShaderStableDigest.hash(stages), sourceGraph: graph)
}

private func variantDependencyKey(_ contract: SceneShaderContract) throws -> String {
    guard let key = SceneResolvedMaterialVariantAnalysisCache.keyDigest(
        contractIdentity: contract.identity,
        contractCanonicalSHA256: contract.canonicalSHA256,
        sourceGraphCacheSHA256: contract.sourceGraphCacheSHA256,
        textureSlotShapes: Array(repeating: nil, count: 8),
        combos: [:], inheritedInactiveCombos: [], uniformDeclarations: [],
        compatibilityTarget: .unprofiledMetal,
        implicitFramebufferIdentity: nil, readinessMask: 0,
        resolvedTextureFormats: [:], outputIsRGBA8Unorm: false
    ) else { throw ProbeFailure(description: "variant key missing") }
    return key
}

private func demandDependencyKey(_ contract: SceneShaderContract) throws
    -> SceneMaterialDemandAnalysisPersistentCache.ResourceDemandAnalysisKey {
    .init(template: try makeProbeTemplate(contract: contract),
        implicitFramebufferIdentity: nil)
}

private func dependencyRecord(vertex: String, fragment: String)
    -> SceneResolvedMaterialVariantAnalysisCache.Record {
    .init(canonicalVertex: vertex, canonicalFragment: fragment,
        activeSamplerNames: [], resolvedIntegerCombos: [:],
        sourceActiveSamplers: [:], runtimeLoopBounds: .none,
        sourceColorTransfer: .passthrough(textureSlot: 0),
        rgba8UnormAccumulatorSourceSlot: nil, spatialWeightedColorBlend: nil,
        sourceCarriedRGBA: nil, conditionalGeneratedRGB: nil,
        sameAlphaReconstructedRGB: nil, neutralTextureResolution: nil,
        alphaAttenuationFact: nil, colorBlendFact: nil,
        previousBlurredCompositeFact: nil)
}

private func identityProbe() throws -> ProbeOutput {
    var output = ProbeOutput(tier: "dependency-identity")
    let original = dependencyContract(value: "0.25")
    let changed = dependencyContract(value: "0.75")
    let staleOriginal = dependencyContract(value: "0.25", staleMarkers: true)
    let staleChanged = dependencyContract(value: "0.75", staleMarkers: true)
    try expect(into: &output, original.canonicalSHA256 == changed.canonicalSHA256,
        "root-admission-identity-unchanged")
    try expect(into: &output,
        original.sourceGraphCacheSHA256 == dependencyContract(value: "0.25")
            .sourceGraphCacheSHA256,
        "identical-content-stable")
    try expect(into: &output,
        original.sourceGraphCacheSHA256 != changed.sourceGraphCacheSHA256,
        "include-content-invalidates")
    try expect(into: &output,
        staleOriginal.sourceGraph?.dependencySHA256
            == staleChanged.sourceGraph?.dependencySHA256
            && staleOriginal.sourceGraph?.nodes.last?.rawSHA256
                == staleChanged.sourceGraph?.nodes.last?.rawSHA256
            && staleOriginal.sourceGraphCacheSHA256 != staleChanged.sourceGraphCacheSHA256,
        "self-reported-hashes-cannot-hide-source-change")
    let encoder = JSONEncoder()
    let bytes = try encoder.encode(original)
    var wire = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    try expect(into: &output, wire["sourceGraphCacheSHA256"] == nil,
        "derived-digest-not-serialized")
    let restored = try JSONDecoder().decode(SceneShaderContract.self, from: bytes)
    try expect(into: &output,
        restored == original && restored.sourceGraphCacheSHA256 == original.sourceGraphCacheSHA256,
        "legacy-wire-decodes-and-recomputes")
    let changedWire = try JSONSerialization.jsonObject(with: encoder.encode(changed)) as! [String: Any]
    wire["sourceGraph"] = changedWire["sourceGraph"]
    wire["sourceGraphCacheSHA256"] = original.sourceGraphCacheSHA256
    let injected = try JSONDecoder().decode(SceneShaderContract.self,
        from: JSONSerialization.data(withJSONObject: wire))
    try expect(into: &output,
        injected.sourceGraphCacheSHA256 == changed.sourceGraphCacheSHA256,
        "injected-derived-digest-ignored")
    let originalDemandKey = try demandDependencyKey(original)
    let changedDemandKey = try demandDependencyKey(changed)
    try expect(into: &output,
        originalDemandKey != changedDemandKey,
        "in-process-demand-key-covers-dependencies")
    let staleOriginalVariantKey = try variantDependencyKey(staleOriginal)
    let staleChangedVariantKey = try variantDependencyKey(staleChanged)
    try expect(into: &output,
        staleOriginalVariantKey != staleChangedVariantKey,
        "variant-key-covers-actual-dependencies")
    return output
}

private func dependencyCacheProbe(write: Bool) throws -> ProbeOutput {
    var output = ProbeOutput(tier: write ? "dependency-cold" : "dependency-warm")
    let original = dependencyContract(value: "0.25")
    let changed = dependencyContract(value: "0.75")
    let firstVariant = try variantDependencyKey(original)
    let secondVariant = try variantDependencyKey(changed)
    let firstDemand = try demandDependencyKey(original)
    let secondDemand = try demandDependencyKey(changed)
    if write {
        try expect(into: &output,
            SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: firstVariant) == nil
                && SceneMaterialDemandAnalysisPersistentCache.load(key: firstDemand) == nil,
            "cold-miss")
        SceneResolvedMaterialVariantAnalysisCache.store(
            record: dependencyRecord(vertex: "old vertex", fragment: "old include"),
            keySHA256: firstVariant)
        SceneMaterialDemandAnalysisPersistentCache.store(
            textureFormatSlots: [1], samplers: [:], reachableSamplerSlots: [1], key: firstDemand)
        try expect(into: &output,
            SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: secondVariant) == nil
                && SceneMaterialDemandAnalysisPersistentCache.load(key: secondDemand) == nil,
            "include-change-misses-old-records")
        SceneResolvedMaterialVariantAnalysisCache.store(
            record: dependencyRecord(vertex: "new vertex", fragment: "new include"),
            keySHA256: secondVariant)
        SceneMaterialDemandAnalysisPersistentCache.store(
            textureFormatSlots: [5], samplers: [:], reachableSamplerSlots: [5], key: secondDemand)
    }
    try expect(into: &output,
        SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: firstVariant)?.canonicalFragment
            == "old include"
            && SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: secondVariant)?.canonicalFragment
                == "new include",
        "variant-records-remain-distinct")
    try expect(into: &output,
        SceneMaterialDemandAnalysisPersistentCache.load(key: firstDemand)?.reachableSamplerSlots == [1]
            && SceneMaterialDemandAnalysisPersistentCache.load(key: secondDemand)?.reachableSamplerSlots == [5],
        "demand-records-remain-distinct")
    return output
}

private func dependencyConsumerProbe() throws -> ProbeOutput {
    var output = ProbeOutput(tier: "dependency-consumer")
    let original = dependencyContract(value: "0.25")
    let changed = dependencyContract(value: "0.75")
    guard let key = SceneResolvedMaterialVariantKey(readinessMask: 0,
        textureFormats: Array(repeating: nil, count: 8)) else {
        throw ProbeFailure(description: "variant key rejected")
    }
    func prepare(_ contract: SceneShaderContract) throws -> (
        String?, SceneResolvedMaterialVariantAnalysisCache.Record?, String, String
    ) {
        let value = try SceneResolvedMaterialVariantCache.prepareVariantSources(
            template: makeProbeTemplate(contract: contract), variantKey: key,
            readinessMask: 0, readiness: [:], implicitFramebufferIdentity: nil,
            outputIsRGBA8Unorm: false)
        return (value.variantAnalysisKey, value.cachedAnalysis,
            value.compilerSources.vertex, value.compilerSources.fragment)
    }
    let first = try prepare(original)
    guard let originalKey = first.0 else {
        throw ProbeFailure(description: "consumer key missing")
    }
    SceneResolvedMaterialVariantAnalysisCache.store(
        record: dependencyRecord(vertex: first.2, fragment: first.3), keySHA256: originalKey)
    let repeated = try prepare(original)
    let updated = try prepare(changed)
    try expect(into: &output, repeated.1 != nil && repeated.3 == first.3,
        "unchanged-consumer-reuses-canonical-sources")
    try expect(into: &output,
        updated.0 != first.0 && updated.1 == nil && updated.3.contains("0.75")
            && !updated.3.contains("0.25"),
        "new-include-cannot-be-overwritten-by-old-canonical-source")
    return output
}

@main
private enum DependencyCacheEntrypoint {
    static func main() throws {
        let output: ProbeOutput
        switch CommandLine.arguments[1] {
        case "identity": output = try identityProbe()
        case "cold-write": output = try dependencyCacheProbe(write: true)
        case "warm-read": output = try dependencyCacheProbe(write: false)
        case "consumer": output = try dependencyConsumerProbe()
        default: throw ProbeFailure(description: "unknown mode")
        }
        print(String(decoding: try JSONEncoder().encode(output), as: UTF8.self))
    }
}
