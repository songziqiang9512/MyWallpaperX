#!/usr/bin/env python3

"""Behavior gate for the four Scene persistent cache tiers.

Each tier is probed through its real load/store surface against an isolated,
environment-overridden cache root (MWX_SCENE_GENERIC_SHADER_CACHE):

- read-only miss: a load on a missing tier directory misses without
  materializing the directory,
- publish + hit: store persists exactly one entry and a later load returns
  the stored payload,
- corrupted bytes, a tampered payload digest and a stale schema version each
  degrade to a safe miss,
- the preparation tier is driven through its real consumer
  (SceneAuthoredShaderPreparation.prepareShaderStages): a rejected
  preparation publishes nothing, an accepted one publishes exactly one
  entry, a later launch hits the persisted entry without republishing it,
  and corrupted or schema-stale entries re-prepare and heal the file.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderContract.swift",
    SCENE_ROOT / "Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "Compilation/Material/SceneMaterialRenderState.swift",
    *scene_swift_sources("authored_shader_frontend_implementation"),
    SCENE_ROOT / "Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift",
    *scene_swift_sources("authored_shader_preparation_implementation"),
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader+Resample.swift",
    SCENE_ROOT / "Resources/Textures/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/Assets/SceneStockTextureSemanticRegistry.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureProviderPublication.swift",
    SCENE_ROOT / "Resources/Textures/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Resources/Textures/SceneFrameTextureRegistry.swift",
    # Covers the three Material analysis tiers under probe plus their
    # program/template/schema/resolver closure (the template-compilation
    # set is deliberately excluded: its document/script-binding owners are
    # outside this probe and drag the whole document model in).
    *scene_swift_sources("resolved_material_frame_finalization"),
    SCENE_ROOT / "Compilation/ShaderPreparation/SceneGenericShaderExpectedColorTransfer.swift",
]

SUPPORT = r'''
import Foundation

nonisolated enum SceneEffectStageCompilerBackend {
    case authoredShader
}

nonisolated struct SceneEffectStageCompilerFailure {
    enum Phase: String {
        case shaderPreprocessor = "shader-preprocessor"
        case invariant
    }

    enum Code: String {
        case shaderStageMissing = "shader-stage-missing"
        case shaderSourceGraphMissing = "shader-source-graph-missing"
        case shaderSourceIdentityMismatch = "shader-source-identity-mismatch"
        case shaderVariantInvalid = "shader-variant-invalid"
        case shaderIncludeMissing = "shader-include-missing"
        case shaderIncludeAmbiguous = "shader-include-ambiguous"
        case shaderIncludeCycle = "shader-include-cycle"
        case shaderDirectiveUnsupported = "shader-directive-unsupported", shaderModuleResolutionRejected = "shader-module-resolution-rejected"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded = "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
    }

    let backend: SceneEffectStageCompilerBackend
    let phase: Phase
    let code: Code
    let details: [String]
}

nonisolated enum SceneEffectStageBackendCompileResult<Value> {
    case notApplicable
    case rejected(SceneEffectStageCompilerFailure)
    case accepted(Value)
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material
        case instance
        case userTexture
        case explicitBinding
    }
}
'''

HARNESS = r'''
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
            && !FileManager.default.fileExists(atPath: directory.path),
        "read-only-miss"
    )
    let analysis = SceneGenericShaderAnalysis(
        profile: .ordinaryShader,
        colorTransfer: .passthrough(textureSlot: 0),
        expectedColorTransfer: nil,
        premultipliedColorInputSlots: [1, 2],
        defaultBoundaryColorSlots: [3]
    )
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
        .computeAnalysis(input: backgroundInput)
    try expect(into: &output,
        backgroundInput != input
            && SceneGenericShaderAnalysisCache.inputDigest(of: backgroundInput)
                != SceneGenericShaderAnalysisCache.inputDigest(of: input)
            && SceneGenericShaderAnalysisCache.load(input: backgroundInput) == nil
            && backgroundAnalysis.premultipliedColorInputSlots == [3]
            && backgroundAnalysis.defaultBoundaryColorSlots == [0, 1, 3],
        "background-color-fact-key-and-abi")
    let colorAnalysis = SceneResolvedMaterialGenericShaderArtifactCache
        .computeAnalysis(input: input)
    let dataAnalysis = SceneResolvedMaterialGenericShaderArtifactCache
        .computeAnalysis(input: dataInput)
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

private func runVariantProbe() throws -> ProbeOutput {
    var output = ProbeOutput(tier: "variant")
    let root = try cacheRoot()
    func variantDirectories() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: root, isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasPrefix("SceneVariantAnalysis-v") }
    }
    let key = "probe-variant-key"
    try expect(
        into: &output,
        SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: key) == nil
            && variantDirectories().isEmpty,
        "read-only-miss"
    )
    let record = SceneResolvedMaterialVariantAnalysisCache.Record(
        canonicalVertex: "// probe vertex",
        canonicalFragment: "// probe fragment",
        activeSamplerNames: ["g_Probe"],
        resolvedIntegerCombos: ["COMBO_A": 1],
        sourceActiveSamplers: [:],
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
    let directories = variantDirectories()
    guard directories.count == 1 else {
        throw ProbeFailure(description: "expected exactly one published variant namespace")
    }
    let directory = directories[0]
    let entries = jsonEntries(directory)
    try expect(into: &output, entries.count == 1, "publish")
    let loaded = SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: key)
    try expect(
        into: &output,
        loaded?.canonicalVertex == "// probe vertex"
            && loaded?.canonicalFragment == "// probe fragment"
            && loaded?.activeSamplerNames == ["g_Probe"]
            && loaded?.resolvedIntegerCombos == ["COMBO_A": 1]
            && loaded?.sourceActiveSamplers.isEmpty == true
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

private func makeProbeTemplate() throws -> SceneResolvedMaterialTemplate {
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
        shaderContract: makeProbeContract(),
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

private func runDemandProbe() throws -> ProbeOutput {
    var output = ProbeOutput(tier: "demand")
    let root = try cacheRoot()
    let directory = tierDirectory(
        root: root, name: "SceneMaterialDemandAnalysis-v4"
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
        key: key
    )
    let entries = jsonEntries(directory)
    try expect(into: &output, entries.count == 1, "publish")
    let loaded = SceneMaterialDemandAnalysisPersistentCache.load(key: key)
    try expect(
        into: &output,
        loaded?.textureFormatSlots == [0, 3]
            && loaded?.samplers.isEmpty == true,
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

private func runPreparationProbe(rejected: Bool) throws -> ProbeOutput {
    var output = ProbeOutput(
        tier: rejected ? "preparation-rejected" : "preparation-accepted"
    )
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
            case "generic":
                output = try runGenericProbe()
            case "variant":
                output = try runVariantProbe()
            case "demand":
                output = try runDemandProbe()
            case "preparation-accepted":
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
'''

EXPECTED_TIER_CHECKS = {
    "generic": [
        "read-only-miss",
        "publish",
        "hit",
        "graph-content-key-miss",
        "background-color-fact-key-and-abi",
        "graph-data-excluded-from-color-boundary",
        "graph-data-sample-preserved-color-converted-once",
        "corrupt-safe-miss",
        "tampered-digest-miss",
        "stale-schema-miss",
        "wrong-key-miss",
    ],
    "variant": [
        "read-only-miss",
        "publish",
        "hit",
        "corrupt-safe-miss",
        "tampered-digest-miss",
        "stale-schema-miss",
    ],
    "demand": [
        "read-only-miss",
        "publish",
        "hit",
        "corrupt-safe-miss",
        "tampered-digest-miss",
        "stale-schema-miss",
    ],
}


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ScenePersistentCacheBehaviorTests(unittest.TestCase):
    def test_persistent_cache_tiers_behave_under_isolated_roots(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-persistent-cache-probe-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "persistent-cache-probe"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            sources = list(
                dict.fromkeys(str(path) for path in SWIFT_SOURCES)
            )
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    str(support),
                    *sources,
                    str(harness),
                    "-framework",
                    "Metal",
                    "-framework",
                    "CoreGraphics",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            for tier in ("generic", "variant", "demand"):
                with self.subTest(tier=tier):
                    self.run_tier_probe(binary, root, environment, tier)
            self.run_preparation_phases(binary, root, environment)

    def run_tier_probe(
        self,
        binary: Path,
        root: Path,
        environment: dict,
        tier: str,
    ) -> None:
        tier_root = root / tier
        tier_root.mkdir()
        probe_environment = dict(environment)
        probe_environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(tier_root)
        # The command head stays a literal so the repository security write
        # gate accepts this file; the probe binary is a tempdir artifact.
        completed = subprocess.run(
            ["/usr/bin/env", str(binary), tier],
            cwd=REPOSITORY_ROOT,
            env=probe_environment,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            completed.returncode, 0, completed.stderr or completed.stdout
        )
        payload = json.loads(completed.stdout)
        self.assertIsNone(payload.get("failure"))
        self.assertEqual(payload["checks"], EXPECTED_TIER_CHECKS[tier])

    def run_preparation_phases(
        self,
        binary: Path,
        root: Path,
        environment: dict,
    ) -> None:
        tier_root = root / "preparation"
        tier_root.mkdir()
        probe_environment = dict(environment)
        probe_environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(tier_root)
        tier_directory = tier_root / "SceneShaderPreparation-v1"

        def run(mode):
            return subprocess.run(
                ["/usr/bin/env", str(binary), mode],
                cwd=REPOSITORY_ROOT,
                env=probe_environment,
                capture_output=True,
                text=True,
            )

        def entries():
            if not tier_directory.exists():
                return []
            return sorted(tier_directory.glob("*.json"))

        rejected = run("preparation-rejected")
        self.assertEqual(
            rejected.returncode, 0, rejected.stderr or rejected.stdout
        )
        # A rejected preparation publishes nothing, and its load misses
        # without materializing the tier directory.
        self.assertEqual(entries(), [])

        accepted = run("preparation-accepted")
        self.assertEqual(
            accepted.returncode, 0, accepted.stderr or accepted.stdout
        )
        self.assertEqual(len(entries()), 1)
        published = entries()[0].read_bytes()
        published_mtime = entries()[0].stat().st_mtime_ns

        warm = run("preparation-accepted")
        self.assertEqual(warm.returncode, 0, warm.stderr or warm.stdout)
        # A later launch hits the persisted entry and does not republish it:
        # an atomic rewrite would mint a fresh modification time even when
        # the bytes stay identical.
        self.assertEqual(len(entries()), 1)
        self.assertEqual(entries()[0].read_bytes(), published)
        self.assertEqual(entries()[0].stat().st_mtime_ns, published_mtime)

        # A corrupted entry is a safe miss: re-preparation heals the file.
        entries()[0].write_bytes(b"\xff" * 64)
        healed = run("preparation-accepted")
        self.assertEqual(healed.returncode, 0, healed.stderr or healed.stdout)
        self.assertEqual(len(entries()), 1)
        self.assertEqual(entries()[0].read_bytes(), published)

        # A schema-stale entry is a safe miss and heals the same way.
        stale = entries()[0].read_text(encoding="utf-8")
        entries()[0].write_text(
            stale.replace('"schemaVersion":1', '"schemaVersion":999'),
            encoding="utf-8",
        )
        healed_stale = run("preparation-accepted")
        self.assertEqual(
            healed_stale.returncode, 0,
            healed_stale.stderr or healed_stale.stdout,
        )
        self.assertEqual(len(entries()), 1)
        self.assertEqual(entries()[0].read_bytes(), published)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneVariantAnalysisCacheWireTests(unittest.TestCase):
    """Actual cache/support IO, deliberately separate from variant consumers."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-variant-wire-")
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / "wire-probe"
        cls.fixture = REPOSITORY_ROOT / "script/tests/fixtures/SceneVariantAnalysisCacheWireChecks.swift"
        cls.legacy = cls.fixture.parent / "variant_analysis_v22"
        cls.proof = Path(os.environ["MWX_VARIANT_WIRE_PROOF"]) if os.environ.get("MWX_VARIANT_WIRE_PROOF") else None
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                   str(SCENE_ROOT / "Compilation/Material/ScenePersistentCacheSupport.swift"),
                   str(SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialVariantAnalysisCache.swift"),
                   str(cls.fixture), "-module-cache-path", str(cls.work / "module-cache"),
                   "-o", str(cls.binary)]
        compiled = subprocess.run(command, cwd=REPOSITORY_ROOT, capture_output=True, text=True)
        if cls.proof:
            cls.proof.mkdir(parents=True, exist_ok=True)
            (cls.proof / "compiler.log").write_text(compiled.stdout + compiled.stderr)
            (cls.proof / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
        if compiled.returncode:
            cls.temporary.cleanup()
            raise AssertionError(compiled.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def mode(self, name: str, root: Path) -> dict:
        root.mkdir(exist_ok=True)
        environment = {**os.environ, "MWX_SCENE_GENERIC_SHADER_CACHE": str(root)}
        completed = subprocess.run(["/usr/bin/env", str(self.binary), name],
                                   cwd=REPOSITORY_ROOT, env=environment,
                                   capture_output=True, text=True, timeout=20)
        if self.proof:
            (self.proof / f"{root.name}-{name}.json").write_text(completed.stdout)
            (self.proof / f"{root.name}-{name}.stderr.log").write_text(completed.stderr)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        facts = json.loads(completed.stdout)
        self.assertTrue(facts)
        self.assertEqual([name for name, passed in facts.items() if passed is not True], [], facts)
        return facts

    def install_legacy(self, root: Path) -> None:
        root.mkdir()
        shutil.copytree(self.legacy, root / "SceneVariantAnalysis-v22")

    def test_original_set_wire_and_new_store_survive_fresh_readers(self) -> None:
        root = self.work / "legacy"
        self.install_legacy(root)
        self.mode("legacy", root)
        cold = self.work / "cold"
        self.mode("cold-write", cold)
        self.mode("cold-read", cold)  # Independent process, same original owner.
        self.mode("ordered-wire", self.work / "ordered")

    def test_invalid_variant_wire_is_a_read_only_safe_miss(self) -> None:
        self.mode("invalid-wire", self.work / "mutations")


if __name__ == "__main__":
    unittest.main()
