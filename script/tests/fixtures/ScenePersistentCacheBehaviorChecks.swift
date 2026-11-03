
import Foundation

private struct ProbeOutput: Codable {
    let tier: String
    var checks: [String] = []
    var failure: String?
}

private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    into output: inout ProbeOutput,
    _ condition: @autoclosure () -> Bool,
    _ check: String
) throws {
    guard condition() else {
        throw ProbeFailure(description: "check failed: \(check)")
    }
    output.checks.append(check)
}

private func cacheRoot() throws -> String {
    guard let raw = ProcessInfo.processInfo
        .environment["MWX_SCENE_GENERIC_SHADER_CACHE"], !raw.isEmpty else {
        throw ProbeFailure(description: "MWX_SCENE_GENERIC_SHADER_CACHE is unset")
    }
    return raw
}

private func tierDirectory(root: String, name: String) -> URL {
    URL(fileURLWithPath: root, isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
}

private func jsonEntries(_ directory: URL) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
    )) ?? [])
        .filter { $0.pathExtension == "json" }
        .sorted { $0.path < $1.path }
}

private func waitForPublication(
    _ directory: URL, count: Int = 1, matches: (URL) -> Bool = { _ in true }
) throws -> [URL] {
    let deadline = Date().addingTimeInterval(2)
    repeat {
        let entries = jsonEntries(directory)
        if entries.count == count, entries.allSatisfy(matches) { return entries }
        Thread.sleep(forTimeInterval: 0.005)
    } while Date() < deadline
    throw ProbeFailure(description: "publication deadline: \(directory.path)")
}

private func publishedProgram<Value: Decodable>(_ entry: URL, as type: Value.Type) -> Value? {
    guard let bytes = try? Data(contentsOf: entry),
          let envelope = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
          let program = envelope["program"],
          let data = try? JSONSerialization.data(withJSONObject: program) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

private func rewriteEntry(_ url: URL, _ transform: (String) -> String) throws {
    let text = try String(contentsOf: url, encoding: .utf8)
    try transform(text).write(to: url, atomically: true, encoding: .utf8)
}

private func damageEntry(_ url: URL) throws -> Data {
    let snapshot = try Data(contentsOf: url)
    try Data(repeating: 0xFF, count: 64).write(to: url)
    return snapshot
}

// MARK: - Generic analysis tier

private func makeGenericInput(
    marker: String, graphDataSlots: Set<Int> = [], backgroundColorSlots: Set<Int> = []
) -> SceneResolvedMaterialGenericShaderResolutionCache.Input {
    .init(
        vertexSource: "// probe vertex \(marker)\n",
        fragmentSource: "// probe fragment \(marker)\n",
        alphaAttenuationSourceSlot: nil,
        colorBlendSourceSlot: nil,
        previousBlurredCompositeBlurredSlot: nil,
        previousBlurredCompositePreviousSlot: nil,
        previousBlurredCompositeMaskSlot: nil,
        hasExternalProviderTexture: false,
        producesScalarRedOutput: false,
        producesRedGreenUnormOutput: false,
        hasOnlyScalarDataInputs: false,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: [],
        graphInputTextureSlots: [0, 1],
        graphDataTextureSlots: graphDataSlots,
        activeTextureSlots: [0],
        activeOpacityMaskSlots: [],
        typedStaticDataAuxiliarySlots: [],
        preservedChannelsExternalProviderTextureSlots: [],
        premultipliedColorAuxiliarySlots: [],
        sceneBackgroundColorSlots: backgroundColorSlots,
        spatialWeightedColorBlendSourceSlot: nil,
        spatialWeightedColorBlendActiveSlots: [],
        spatialWeightedColorBlendTypedAuxiliarySlots: [],
        spatialWeightedColorBlendExternalColorSlot: nil,
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasOnlyTypedOpacityMaskAuxiliary: false,
        hasOnlyGraphInputSampler: false,
        outputIsRGBA8Unorm: false,
        sourceColorTransfer: nil,
        outputSemantics: .color,
        runtimeLoopBounds: .none
    )
}

private func genericProbeAnalysis() -> SceneGenericShaderAnalysis {
    .init(
        profile: .ordinaryShader,
        colorTransfer: .passthrough(textureSlot: 0),
        expectedColorTransfer: nil,
        premultipliedColorInputSlots: [1, 2],
        defaultBoundaryColorSlots: [3]
    )
}

private func runGenericRootProbe(_ mode: String) throws -> ProbeOutput {
    var output = ProbeOutput(tier: mode)
    let input = makeGenericInput(marker: "root-probe")
    let name = "SceneGenericShaderAnalysis-v18"
    if mode == "generic-root-read" {
        try expect(into: &output,
            ScenePersistentCacheSupport.versionedCacheDirectory(
                environmentKey: "MWX_SCENE_GENERIC_SHADER_CACHE", versionedName: name,
                createIfNeeded: false) == nil
                && SceneGenericShaderAnalysisCache.load(input: input) == nil,
            "read-only-missing-root")
        return output
    }
    if mode == "generic-root-denied" {
        SceneGenericShaderAnalysisCache.store(analysis: genericProbeAnalysis(), input: input)
        try expect(into: &output,
            ScenePersistentCacheSupport.versionedCacheDirectory(
                environmentKey: "MWX_SCENE_GENERIC_SHADER_CACHE", versionedName: name,
                createIfNeeded: true) == nil
                && SceneGenericShaderAnalysisCache.load(input: input) == nil,
            "root-write-unavailable")
        return output
    }
    if mode == "generic-root-write" {
        SceneGenericShaderAnalysisCache.store(analysis: genericProbeAnalysis(), input: input)
        let directory = tierDirectory(root: try cacheRoot(), name: name)
        try expect(into: &output,
            jsonEntries(directory).count == 1,
            "standalone-analysis-write")
    }
    let loaded = SceneGenericShaderAnalysisCache.load(input: input)
    try expect(into: &output,
        loaded?.profile == .ordinaryShader
            && loaded?.colorTransfer == .passthrough(textureSlot: 0)
            && loaded?.expectedColorTransfer == nil
            && loaded?.premultipliedColorInputSlots == [1, 2]
            && loaded?.defaultBoundaryColorSlots == [3],
        "persisted-analysis-hit")
    return output
}

private func runGenericProbe() throws -> ProbeOutput {
    var output = ProbeOutput(tier: "generic")
    let root = try cacheRoot()
    let directory = tierDirectory(
        root: root, name: "SceneGenericShaderAnalysis-v18"
    )
    let input = makeGenericInput(marker: "probe-a")
    try expect(
        into: &output,
        SceneGenericShaderAnalysisCache.load(input: input) == nil
            && !FileManager.default.fileExists(atPath: root)
            && !FileManager.default.fileExists(atPath: directory.path),
        "read-only-miss"
    )
    let analysis = genericProbeAnalysis()
    SceneGenericShaderAnalysisCache.store(analysis: analysis, input: input)
    let entries = jsonEntries(directory)
    try expect(into: &output, entries.count == 1, "publish")
    let loaded = SceneGenericShaderAnalysisCache.load(input: input)
    try expect(
        into: &output,
        loaded?.profile == .ordinaryShader
            && loaded?.colorTransfer == .passthrough(textureSlot: 0)
            && loaded?.premultipliedColorInputSlots == [1, 2]
            && loaded?.defaultBoundaryColorSlots == [3],
        "hit"
    )
    let dataInput = makeGenericInput(marker: "probe-a", graphDataSlots: [0])
    try expect(into: &output,
        dataInput != input
            && SceneGenericShaderAnalysisCache.inputDigest(of: dataInput)
                != SceneGenericShaderAnalysisCache.inputDigest(of: input)
            && SceneGenericShaderAnalysisCache.load(input: dataInput) == nil,
        "graph-content-key-miss")
    let backgroundInput = makeGenericInput(marker: "probe-a", backgroundColorSlots: [3])
    let backgroundAnalysis = SceneResolvedMaterialGenericShaderArtifactCache
        .computeAnalysis(input: backgroundInput).analysis
    try expect(into: &output,
        backgroundInput != input
            && SceneGenericShaderAnalysisCache.inputDigest(of: backgroundInput)
                != SceneGenericShaderAnalysisCache.inputDigest(of: input)
            && SceneGenericShaderAnalysisCache.load(input: backgroundInput) == nil
            && backgroundAnalysis.premultipliedColorInputSlots == [3]
            && backgroundAnalysis.defaultBoundaryColorSlots == [0, 1, 3],
        "background-color-fact-key-and-abi")
    let colorAnalysis = SceneResolvedMaterialGenericShaderArtifactCache
        .computeAnalysis(input: input).analysis
    let dataAnalysis = SceneResolvedMaterialGenericShaderArtifactCache
        .computeAnalysis(input: dataInput).analysis
    try expect(into: &output,
        colorAnalysis.defaultBoundaryColorSlots == [0, 1]
            && dataAnalysis.defaultBoundaryColorSlots == [1],
        "graph-data-excluded-from-color-boundary")
    let msl = """
    using namespace metal;
    fragment Output f() {
        Output out = {};
        float4 state = g_Texture0.sample(stateSampler, uv);
        float4 bg = g_Texture1.sample(colorSampler, uv);
        out.mwxFragColor = float4(bg.xyz * state.y, bg.w);
        return out;
    }
    """
    let lowered = SceneGenericShaderDefaultStraightColorBoundaryLowering.lower(
        msl, colorSlots: dataAnalysis.defaultBoundaryColorSlots)
    try expect(into: &output,
        lowered?.appliedSlots == [1]
            && lowered?.msl.contains("float4 state = g_Texture0.sample(stateSampler, uv);") == true
            && lowered?.msl.contains("mwxGenericUnpremultiply(g_Texture1.sample") == true
            && lowered?.msl.components(separatedBy:
                "out.mwxFragColor = mwxGenericPremultiply(out.mwxFragColor);").count == 2,
        "graph-data-sample-preserved-color-converted-once")
    let entry = entries[0]
    let original = try damageEntry(entry)
    try expect(
        into: &output,
        SceneGenericShaderAnalysisCache.load(input: input) == nil,
        "corrupt-safe-miss"
    )
    try original.write(to: entry)
    try rewriteEntry(entry) {
        $0.replacingOccurrences(
            of: "\"analysisSHA256\":\"[0-9a-f]+\"",
            with: "\"analysisSHA256\":\"0000000000000000\"",
            options: .regularExpression
        )
    }
    try expect(
        into: &output,
        SceneGenericShaderAnalysisCache.load(input: input) == nil,
        "tampered-digest-miss"
    )
    try original.write(to: entry)
    try rewriteEntry(entry) {
        $0.replacingOccurrences(
            of: #""schemaVersion":\d+"#,
            with: "\"schemaVersion\":12",
            options: .regularExpression
        )
    }
    try expect(
        into: &output,
        SceneGenericShaderAnalysisCache.load(input: input) == nil,
        "stale-schema-miss"
    )
    try original.write(to: entry)
    try expect(
        into: &output,
        SceneGenericShaderAnalysisCache.load(
            input: makeGenericInput(marker: "probe-b")
        ) == nil,
        "wrong-key-miss"
    )
    return output
}

// MARK: - Variant analysis tier

private func runVariantProbe(denied: Bool = false) throws -> ProbeOutput {
    var output = ProbeOutput(tier: "variant")
    let samplerSeed = SceneResolvedMaterialPreparedSamplerSchema(
        name: "g_Texture2", slot: 2, mode: .regular, materialKey: nil,
        isHidden: false, defaultTexture: nil, readinessCombo: nil
    )
    let purposeCases: [(String, SceneTextureLoadPurpose)] = [
        ("premultiplied-color", .premultipliedColor), ("straight-albedo", .straightAlbedo),
        ("preserved-channels", .preservedChannels), ("mask", .mask),
        ("noise", .noise), ("flow", .flow), ("phase", .phase),
        ("normal", .normal), ("depth", .depth), ("lookup-table", .lookupTable),
    ]
    var roundtripsMatch = true
    for (token, purpose) in purposeCases {
        let sampler = samplerSeed.withSourceProvenPurpose(purpose)
        let mirror = ScenePersistentSamplerRecord(sampler: sampler)
        let data = try JSONEncoder().encode(mirror)
        let decoded = try JSONDecoder().decode(ScenePersistentSamplerRecord.self, from: data)
        roundtripsMatch = roundtripsMatch && mirror.sourceProvenPurpose == token
            && purpose.reportToken == token && SceneTextureLoadPurpose(reportToken: token) == purpose
            && decoded.rebuild() == sampler
    }
    try expect(into: &output, roundtripsMatch, "sampler-purpose-roundtrip")
    let absentPurpose = ScenePersistentSamplerRecord(sampler: samplerSeed)
    let absentData = try JSONEncoder().encode(absentPurpose)
    let absentDecoded = try JSONDecoder().decode(ScenePersistentSamplerRecord.self, from: absentData)
    try expect(into: &output,
        absentDecoded.sourceProvenPurpose == nil && absentDecoded.rebuild() == samplerSeed,
        "sampler-purpose-absent")
    var unknownPayload = try JSONSerialization.jsonObject(with: absentData) as! [String: Any]
    unknownPayload["sourceProvenPurpose"] = "unrecognized-future-purpose"
    let unknown = try JSONDecoder().decode(ScenePersistentSamplerRecord.self,
        from: JSONSerialization.data(withJSONObject: unknownPayload))
    try expect(into: &output, unknown.rebuild() == nil, "sampler-purpose-unknown-miss")
    let root = try cacheRoot()
    let directory = tierDirectory(root: root, name: "SceneVariantAnalysis-v29")
    let key = "probe-variant-key"
    try expect(
        into: &output,
        SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: key) == nil
            && !FileManager.default.fileExists(atPath: directory.path),
        "read-only-miss"
    )
    let record = SceneResolvedMaterialVariantAnalysisCache.Record(
        canonicalVertex: "// probe vertex",
        canonicalFragment: "// probe fragment",
        activeSamplerNames: ["g_Probe"],
        resolvedIntegerCombos: ["COMBO_A": 1],
        sourceActiveSamplers: [2: samplerSeed.withSourceProvenPurpose(.mask)],
        runtimeLoopBounds: .none,
        sourceColorTransfer: .passthrough(textureSlot: 2),
        rgba8UnormAccumulatorSourceSlot: nil,
        spatialWeightedColorBlend: nil,
        sourceCarriedRGBA: nil,
        conditionalGeneratedRGB: nil,
        sameAlphaReconstructedRGB: nil,
        neutralTextureResolution: nil,
        alphaAttenuationFact: nil,
        colorBlendFact: nil,
        previousBlurredCompositeFact: nil
    )
    SceneResolvedMaterialVariantAnalysisCache.store(record: record, keySHA256: key)
    if denied {
        try expect(into: &output, SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: key) == nil,
            "optional-publish-unavailable")
        return output
    }
    let entries = try waitForPublication(directory)
    try expect(into: &output, entries.count == 1, "publish")
    let loaded = SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: key)
    try expect(
        into: &output,
        loaded?.canonicalVertex == "// probe vertex"
            && loaded?.canonicalFragment == "// probe fragment"
            && loaded?.activeSamplerNames == ["g_Probe"]
            && loaded?.resolvedIntegerCombos == ["COMBO_A": 1]
            && loaded?.sourceActiveSamplers == [2: samplerSeed.withSourceProvenPurpose(.mask)]
            && loaded?.sourceColorTransfer == .passthrough(textureSlot: 2),
        "hit"
    )
    let entry = entries[0]
    let original = try damageEntry(entry)
    try expect(
        into: &output,
        SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: key) == nil,
        "corrupt-safe-miss"
    )
    try original.write(to: entry)
    try rewriteEntry(entry) {
        $0.replacingOccurrences(
            of: "\"recordSHA256\":\"[0-9a-f]+\"",
            with: "\"recordSHA256\":\"0000000000000000\"",
            options: .regularExpression
        )
    }
    try expect(
        into: &output,
        SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: key) == nil,
        "tampered-digest-miss"
    )
    try original.write(to: entry)
    try rewriteEntry(entry) {
        $0.replacingOccurrences(
            of: #""schemaVersion":\d+"#,
            with: "\"schemaVersion\":19",
            options: .regularExpression
        )
    }
    try expect(
        into: &output,
        SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: key) == nil,
        "stale-schema-miss"
    )
    try original.write(to: entry)
    return output
}

// MARK: - Material demand tier

private func makeProbeContract() -> SceneShaderContract {
    .init(
        identity: "probe-contract",
        sourceKind: .authoredSource,
        stages: [],
        diagnostics: [],
        canonicalSHA256: "probe-sha",
        sourceGraph: nil
    )
}

private func makeProbeTemplate(
    contract: SceneShaderContract = makeProbeContract()
) throws -> SceneResolvedMaterialTemplate {
    guard let renderState = SceneMaterialRenderState.compile(
        blending: "normal",
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: nil
    ) else {
        throw ProbeFailure(description: "probe render state failed to compile")
    }
    guard let template = SceneResolvedMaterialTemplate.validated(
        textureSlots: Array(repeating: nil, count: 8),
        combos: [],
        inheritedInactiveCombos: [],
        uniformDeclarations: [],
        renderState: renderState,
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .framebuffer,
            bindings: []
        ),
        compatibilityTarget: .unprofiledMetal,
        shaderContract: contract,
        diagnosticProvenance: .init(
            nodeIndex: 0,
            authoredShaderPath: "shaders/probe.vert",
            contractIdentity: "probe-contract",
            contractCanonicalSHA256: "probe-sha",
            textureSources: [],
            uniformSources: []
        )
    ) else {
        throw ProbeFailure(description: "probe template failed validation")
    }
    return template
}

private func runDemandProbe(denied: Bool = false) throws -> ProbeOutput {
    var output = ProbeOutput(tier: "demand")
    let root = try cacheRoot()
    let directory = tierDirectory(
        root: root, name: "SceneMaterialDemandAnalysis-v10"
    )
    let key = SceneMaterialDemandAnalysisPersistentCache
        .ResourceDemandAnalysisKey(
            template: try makeProbeTemplate(),
            implicitFramebufferIdentity: nil
        )
    try expect(
        into: &output,
        SceneMaterialDemandAnalysisPersistentCache.load(key: key) == nil
            && !FileManager.default.fileExists(atPath: directory.path),
        "read-only-miss"
    )
    SceneMaterialDemandAnalysisPersistentCache.store(
        textureFormatSlots: [0, 3],
        samplers: [:],
        reachableSamplerSlots: [0, 3],
        key: key
    )
    if denied {
        try expect(into: &output, SceneMaterialDemandAnalysisPersistentCache.load(key: key) == nil,
            "optional-publish-unavailable")
        return output
    }
    let entries = try waitForPublication(directory)
    try expect(into: &output, entries.count == 1, "publish")
    let loaded = SceneMaterialDemandAnalysisPersistentCache.load(key: key)
    try expect(
        into: &output,
        loaded?.textureFormatSlots == [0, 3]
            && loaded?.samplers.isEmpty == true
            && loaded?.reachableSamplerSlots == [0, 3],
        "hit"
    )
    let entry = entries[0]
    let original = try damageEntry(entry)
    try expect(
        into: &output,
        SceneMaterialDemandAnalysisPersistentCache.load(key: key) == nil,
        "corrupt-safe-miss"
    )
    try original.write(to: entry)
    try rewriteEntry(entry) {
        $0.replacingOccurrences(
            of: "\"analysisSHA256\":\"[0-9a-f]+\"",
            with: "\"analysisSHA256\":\"0000000000000000\"",
            options: .regularExpression
        )
    }
    try expect(
        into: &output,
        SceneMaterialDemandAnalysisPersistentCache.load(key: key) == nil,
        "tampered-digest-miss"
    )
    try original.write(to: entry)
    try rewriteEntry(entry) {
        $0.replacingOccurrences(
            of: #""schemaVersion":\d+"#,
            with: "\"schemaVersion\":0",
            options: .regularExpression
        )
    }
    try expect(
        into: &output,
        SceneMaterialDemandAnalysisPersistentCache.load(key: key) == nil,
        "stale-schema-miss"
    )
    try original.write(to: entry)
    return output
}

// MARK: - Preparation tier through its real consumer

private func makeProgramStage(
    _ kind: SceneShaderContract.StageKind,
    path: String,
    source: String
) -> SceneShaderContract.Stage {
    let parsed = SceneShaderContractSourceParser().parse(
        source,
        stageRelativePath: path
    )
    return .init(
        kind: kind,
        relativePath: path,
        source: source,
        rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
        includes: parsed.includes,
        annotations: parsed.annotations,
        declarations: parsed.declarations
    )
}

private func makePreparationContract() -> SceneShaderContract {
    let stages = [
        makeProgramStage(
            .vertex,
            path: "shaders/probe.vert",
            source: "// probe vertex\n"
        ),
        makeProgramStage(
            .fragment,
            path: "shaders/probe.frag",
            source: "// probe fragment\n"
        ),
    ]
    let nodes = stages.map { stage in
        SceneShaderSourceGraph.Node(
            virtualPath: stage.relativePath,
            provenance: .loose,
            source: stage.source,
            rawSHA256: stage.rawSHA256,
            byteCount: stage.source.utf8.count
        )
    }
    let graph = SceneShaderSourceGraph(
        roots: stages.map {
            .init(label: $0.kind.rawValue, virtualPath: $0.relativePath)
        },
        nodes: nodes,
        edges: [],
        diagnostics: [],
        dependencySHA256: SceneShaderStableDigest.hash(nodes)
    )
    return .init(
        identity: "probe-preparation",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: SceneShaderStableDigest.hash(stages),
        sourceGraph: graph
    )
}

private func runPreparationProbe(rejected: Bool, denied: Bool = false) throws -> ProbeOutput {
    var output = ProbeOutput(
        tier: rejected ? "preparation-rejected" : "preparation-accepted"
    )
    try expect(into: &output, SceneShaderVariantEnvironment.frontendSchemaVersion == 53,
        "current-frontend-schema")
    if rejected {
        let result = SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: makeProbeContract(),
            combos: [:]
        )
        var rejectedForMissingGraph = false
        if case let .rejected(failure) = result {
            rejectedForMissingGraph = failure.code == .shaderSourceGraphMissing
        }
        try expect(into: &output, rejectedForMissingGraph, "rejected")
        return output
    }
    let result = SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: makePreparationContract(),
        compatibilityTarget: .windowsDX11ShaderModel4,
        combos: [:]
    )
    var accepted = false
    if case .accepted = result {
        accepted = true
    }
    try expect(into: &output, accepted, "accepted")
    if case let .accepted(program) = result {
        let repeatResult = SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: makePreparationContract(), compatibilityTarget: .windowsDX11ShaderModel4, combos: [:])
        guard case let .accepted(repeated) = repeatResult, repeated == program,
              SceneAuthoredShaderPreparation.completedCacheSnapshot.completedEntries == 1,
              SceneAuthoredShaderPreparation.completedCacheSnapshot.inFlightOperations == 0 else {
            throw ProbeFailure(description: "preparation memory result was not shared")
        }
        if !denied {
            _ = try waitForPublication(tierDirectory(root: try cacheRoot(), name: "SceneShaderPreparation-v1")) {
                publishedProgram($0, as: SceneShaderPreparedProgram.self) == program
            }
        }
    }
    return output
}

// MARK: - Frontend through its real Bundle-bound cache and compile entry

private func frontendDirectory() throws -> URL {
    guard Bundle.main.bundleIdentifier == "com.songziqiang.MyWallpaperX",
          let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
          let isolatedHome = ProcessInfo.processInfo.environment["MWX_CACHE_PROBE_HOME"],
          root.resolvingSymlinksInPath().path.hasPrefix(
            URL(fileURLWithPath: isolatedHome).resolvingSymlinksInPath().path + "/") else {
        throw ProbeFailure(description: "frontend probe must use its isolated App bundle")
    }
    return root.appendingPathComponent("MyWallpaperX/SceneShaderFrontend-v1", isDirectory: true)
}

private let frontendCacheMarker = "// persisted-frontend-probe-marker"

private func runFrontendProbe(_ mode: String) throws -> ProbeOutput {
    var output = ProbeOutput(tier: mode)
    let directory = try frontendDirectory()
    if mode == "frontend-tag" {
        let entry = try waitForPublication(directory)[0]
        var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: entry)) as! [String: Any]
        var program = envelope["program"] as! [String: Any]
        program["metalSource"] = (program["metalSource"] as! String) + "\n" + frontendCacheMarker
        let decoded = try JSONDecoder().decode(SceneAuthoredShaderProgram.self,
            from: JSONSerialization.data(withJSONObject: program))
        envelope["program"] = program
        envelope["programSHA256"] = SceneShaderStableDigest.hash(decoded)
        try JSONSerialization.data(withJSONObject: envelope).write(to: entry)
        output.checks = ["tagged-valid-cached-program"]
        return output
    }
    let vertex = "attribute vec3 a_Position; void main() { gl_Position = vec4(a_Position, 1.0); }"
    let fragment = "void main() { gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0); }"
    let first = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: fragment)
    guard let program = first.program, first.diagnostics.isEmpty else {
        throw ProbeFailure(description: "frontend compile failed: \(first.diagnostics)")
    }
    try expect(into: &output, !program.metalSource.isEmpty, "bounded-program-adopted")
    let repeated = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: fragment)
    try expect(into: &output, repeated.program?.metalSource == program.metalSource
        && repeated.diagnostics.isEmpty && SceneAuthoredShaderFrontend.completedCacheSnapshot.completedEntries == 1,
        "immediate-memory-hit")
    if mode == "frontend-warm" {
        try expect(into: &output, program.metalSource.contains(frontendCacheMarker), "fresh-process-disk-hit")
    } else if mode != "frontend-denied" {
        _ = try waitForPublication(directory) {
            publishedProgram($0, as: SceneAuthoredShaderProgram.self)?.metalSource == program.metalSource
        }
    }
    return output
}

// MARK: - Entry

@main
private enum ProbeEntrypoint {
    static func main() {
        let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
        do {
            let output: ProbeOutput
            switch mode {
            case "generic-root-read", "generic-root-write", "generic-root-warm", "generic-root-denied":
                output = try runGenericRootProbe(mode)
            case "generic":
                output = try runGenericProbe()
            case "variant":
                output = try runVariantProbe()
            case "variant-denied":
                output = try runVariantProbe(denied: true)
            case "demand":
                output = try runDemandProbe()
            case "demand-denied":
                output = try runDemandProbe(denied: true)
            case "preparation-accepted":
                output = try runPreparationProbe(rejected: false)
            case "preparation-denied":
                output = try runPreparationProbe(rejected: false, denied: true)
            case "frontend-accepted", "frontend-denied", "frontend-tag", "frontend-warm":
                output = try runFrontendProbe(mode)
            case "preparation-tampered-stage":
                let directory = tierDirectory(root: try cacheRoot(), name: "SceneShaderPreparation-v1")
                let entry = jsonEntries(directory)[0]
                var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: entry)) as! [String: Any]
                var program = envelope["program"] as! [String: Any]
                var vertex = program["vertex"] as! [String: Any]
                vertex["stage"] = "fragment"
                program["vertex"] = vertex
                let decoded = try JSONDecoder().decode(SceneShaderPreparedProgram.self,
                    from: JSONSerialization.data(withJSONObject: program))
                envelope["program"] = program
                envelope["programSHA256"] = SceneShaderStableDigest.hash(decoded)
                try JSONSerialization.data(withJSONObject: envelope).write(to: entry)
                output = try runPreparationProbe(rejected: false)
            case "preparation-rejected":
                output = try runPreparationProbe(rejected: true)
            default:
                output = ProbeOutput(
                    tier: "unknown", failure: "unknown mode \(mode)"
                )
            }
            emit(output)
        } catch {
            let currentMode = CommandLine.arguments.count > 1
                ? CommandLine.arguments[1] : ""
            emit(ProbeOutput(
                tier: currentMode, checks: [], failure: String(describing: error)
            ))
            exit(1)
        }
    }

    private static func emit(_ output: ProbeOutput) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(output) else { return }
        print(String(decoding: data, as: UTF8.self))
    }
}
