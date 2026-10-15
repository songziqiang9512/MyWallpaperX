#!/usr/bin/env python3

"""Self-authored prepared default-mask admission; no asset pixels or GPU work.

The source grammar below is authored for the current public product analyzer.
It does not import the mixed standard-Blur harness or any stock shader, asset,
payload, or formula. The complete production schema and sampler-purpose code
participate. The only shared test support is the separately self-authored
FinalizerSupport DTO file; its GPU/finalizer runners are not imported.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


# Reuse the real standalone preparation/finalization source boundary, not a
# replacement Schema, purpose registry, selector, Eligibility, or shader parser.
# Metal is a link dependency of those types; this harness never creates a device.
SWIFT_SOURCES = list(dict.fromkeys([
    SCENE_ROOT / "Resources/Textures/SceneResourceBudget.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderContractLoader.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift",
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
    *scene_swift_sources("resolved_material_frame_finalization"),
]))

SUPPORT_SOURCE = (
    Path(__file__).with_name("fixtures") / "SceneResolvedMaterialFinalizerSupport.swift"
)

HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Template = SceneResolvedMaterialTemplate
private typealias Schema = SceneResolvedMaterialShaderSchema
private typealias Eligibility = SceneResolvedMaterialPreviousBlurredCompositeEligibility

private let consumer = Graph.EffectKey(
    layerID: 901, effectIndex: 0, descriptorID: "own-default-mask-stage")
private let ingress = Graph.TextureIdentity(
    kind: .layerSource, layerID: 901, effect: nil, name: nil)
private let intermediate = Graph.TextureIdentity(
    kind: .framebuffer, layerID: 901, effect: consumer, name: "own-quarter-result")

private struct Prepared {
    let shader: SceneShaderContract
    let program: SceneShaderPreparedProgram
    let samplers: [Int: Schema.Sampler]
    let fact: SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.Fact
    let tintKey: String
}

private func require(_ value: Bool, _ identity: String) throws {
    guard value else {
        throw NSError(domain: "self-authored-default-mask-\(identity)", code: 1)
    }
}

private func ownPrepared(
    variant: Int = 0,
    defaultPath: String? = "fixtures/unseen-mask-one.tex",
    mode: String? = "opacitymask"
) throws -> Prepared {
    let coordinate = variant == 0 ? "ownCoordinate" : "independentCoordinate"
    let tint = variant == 0 ? "ownTint" : "independentTint"
    let tintKey = variant == 0 ? "OwnTintValue" : "IndependentTintValue"
    let first = variant == 0 ? "ownReduced" : "independentReduced"
    let previous = variant == 0 ? "ownPrevious" : "independentPrevious"
    let mask = variant == 0 ? "ownCoverage" : "independentCoverage"
    let divisor = variant == 0 ? "ownDivisor" : "independentDivisor"
    let helper = variant == 0 ? "ownTintedValue" : "independentTintedValue"
    let sample = variant == 0 ? "texSample2D" : "texture2D"
    var maskMetadata: [String: String] = [:]
    if let mode { maskMetadata["mode"] = mode }
    if let defaultPath { maskMetadata["default"] = defaultPath }
    let maskJSON = String(data: try JSONSerialization.data(
        withJSONObject: maskMetadata, options: [.sortedKeys]), encoding: .utf8)!
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec4 \(coordinate);
    void main() {
        \(coordinate) = vec4(a_TexCoord, a_TexCoord);
        gl_Position = vec4(a_Position, 1.0);
    }
    """
    // A self-authored, no-kernel two-input tint/mask program. This exercises
    // source recognition as well as host admission; no image is loaded.
    let fragment = """
    varying vec4 \(coordinate);
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1; // \(maskJSON)
    uniform sampler2D g_Texture2;
    uniform vec3 \(tint); // {"material":"\(tintKey)","default":"0.3 0.6 0.9"}
    vec4 \(helper)(vec4 sourceValue, vec4 resultValue) {
        resultValue.rgb *= \(tint);
        return resultValue;
    }
    void main() {
        vec4 \(first) = \(sample)(g_Texture0, \(coordinate).xy);
        vec4 \(previous) = \(sample)(g_Texture2, \(coordinate).xy);
        float \(mask) = \(sample)(g_Texture1, \(coordinate).xy).r;
        float \(divisor) = mix(\(first).a, 1, step(\(first).a, 0));
        \(first) = \(helper)(\(previous), vec4(\(first).rgb / \(divisor), \(first).a));
        \(first) = mix(\(previous), \(first), \(mask));
        gl_FragColor = \(first);
    }
    """
    func stage(_ kind: SceneShaderContract.StageKind, _ source: String)
        -> SceneShaderContract.Stage {
        let path = "self-authored/default-mask/\(variant)/\(kind.rawValue)"
        let parsed = SceneShaderContractSourceParser().parse(
            source, stageRelativePath: path)
        return .init(kind: kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes, annotations: parsed.annotations,
            declarations: parsed.declarations)
    }
    let stages = [stage(.vertex, vertex), stage(.fragment, fragment)]
    let nodes = stages.map {
        SceneShaderSourceGraph.Node(virtualPath: $0.relativePath,
            provenance: .package, source: $0.source, rawSHA256: $0.rawSHA256,
            byteCount: $0.source.utf8.count)
    }
    let shader = SceneShaderContract(
        identity: "self-authored/default-mask/\(variant)",
        sourceKind: .authoredSource, stages: stages, diagnostics: [],
        canonicalSHA256: SceneShaderStableDigest.hash(Data((vertex + fragment).utf8)),
        sourceGraph: .init(
            roots: zip(["vertex", "fragment"], stages).map {
                .init(label: $0.0, virtualPath: $0.1.relativePath)
            }, nodes: nodes, edges: [], diagnostics: [],
            dependencySHA256: SceneShaderSourceGraph.dependencySHA256(nodes: nodes, edges: [])))
    let program: SceneShaderPreparedProgram
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: shader, combos: [:], textureReadiness: [0: true, 1: true, 2: true]) {
    case let .accepted(value): program = value
    case .notApplicable, .rejected:
        throw NSError(domain: "self-authored-default-mask-preparation", code: 1)
    }
    guard let names = SceneAuthoredShaderDeadBindingAnalyzer.activeSamplerNames(
            vertexSource: program.vertex.source, fragmentSource: program.fragment.source),
          let fact = SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.analyze(
            fragmentSource: program.fragment.source) else {
        throw NSError(domain: "self-authored-default-mask-source-proof", code: 1)
    }
    let samplers = try Schema.activeSamplers(program, activeNames: names)
    try require(Set(samplers.keys) == [0, 1, 2], "active-three-samplers")
    try require(fact.blurredSlot == 0 && fact.previousSlot == 2 && fact.maskSlot == 1,
        "real-analyzer-slots")
    return .init(shader: shader, program: program, samplers: samplers,
        fact: fact, tintKey: tintKey)
}

private func template(
    _ prepared: Prepared,
    maskCandidates: [Template.TextureCandidate]? = nil,
    owner: Bool = true,
    tintComponents: [Double] = [0.2, 0.4, 0.8],
    dynamicTint: Bool = false
) -> Template? {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[0] = .init(index: 0, candidates: [
        .init(reference: .graph(intermediate), provenance: .explicitBinding)])
    slots[2] = .init(index: 2, candidates: [
        .init(reference: .graph(ingress), provenance: .explicitBinding)])
    if let maskCandidates { slots[1] = .init(index: 1, candidates: maskCandidates) }
    let value = Template.StaticUniformValue(valueKind: "self-authored-vector",
        componentBitPatterns: tintComponents.map(\.bitPattern), authoredBindingKeys: [])
    let uniform: Template.UniformValue = dynamicTint
        ? .dynamic(.init(target: .effectConstant(layerID: 901, effectIndex: 0,
            passIndex: 3, name: prepared.tintKey), valueContributors: [.timeline],
            scriptAttachments: [], authoredFallback: value, authoredBindingKeys: []))
        : .staticExact(value)
    return Template.validated(textureSlots: slots, combos: [],
        uniformDeclarations: [.init(name: prepared.tintKey, value: uniform)],
        renderState: SceneMaterialRenderState.compile(blending: "normal",
            depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull",
            alphaWriting: nil)!,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: [.init(slot: 0, texture: .framebuffer),
                       .init(slot: 2, texture: .layerSource)]),
        previousBlurredCompositeGenericOwnerEligible: owner,
        effectContext: .init(key: consumer, input: ingress),
        shaderContract: prepared.shader,
        diagnosticProvenance: .init(nodeIndex: 3,
            authoredShaderPath: prepared.shader.identity,
            contractIdentity: prepared.shader.identity,
            contractCanonicalSHA256: prepared.shader.canonicalSHA256,
            textureSources: [], uniformSources: []))
}

private func validated(
    _ prepared: Prepared, template candidate: Template? = nil,
    samplers: [Int: Schema.Sampler]? = nil,
    input: Graph.TextureIdentity = ingress,
    activeGraph: [Int: Graph.TextureIdentity] = [0: intermediate, 2: ingress]
) -> Eligibility.Slots? {
    Eligibility.validated(shape: prepared.fact, prepared: prepared.program,
        samplers: samplers ?? prepared.samplers,
        template: candidate ?? template(prepared)!,
        implicitFramebufferIdentity: input,
        activeGraphTextureIdentities: activeGraph)
}

private func sourceSlots(_ prepared: Prepared, _ candidate: Template) -> Eligibility.Slots? {
    Eligibility.slots(fragmentSource: prepared.program.fragment.source,
        prepared: prepared.program, samplers: prepared.samplers, template: candidate,
        implicitFramebufferIdentity: ingress,
        activeGraphTextureIdentities: [0: intermediate, 2: ingress])
}

@main private enum Main {
    static func main() throws {
        let first = try ownPrepared()
        let renamed = try ownPrepared(variant: 1, defaultPath: "independent/renamed-mask.tex")
        let expected = Eligibility.Slots(blurred: 0, previous: 2, mask: 1)
        let firstTemplate = template(first)!
        let positives: [String: Bool] = [
            "defaultAssetValidated": validated(first) == expected,
            "defaultAssetSourceEntry": sourceSlots(first, firstTemplate) == expected,
            "renamedResourceAndVariables": validated(renamed) == expected
                && sourceSlots(renamed, template(renamed)!) == expected,
            "originalPurposePath": first.samplers[1]?.hasTypedAuxiliaryDefault == true
                && first.samplers[1]?.purpose(for: .asset(
                    SceneVFSAssetPath("fixtures/unseen-mask-one.tex")!)) == .mask,
            "explicitAssetOverrideStillAccepted": validated(first, template: template(first,
                maskCandidates: [.init(reference: .asset(
                    SceneVFSAssetPath("self-authored/explicit-mask.tex")!),
                    provenance: .instance)])!) == expected,
        ]
        let noDefault = try ownPrepared(defaultPath: nil)
        let internalDefault = try ownPrepared(defaultPath: "_rt_unseen_default")
        let regular = try ownPrepared(mode: nil)
        let rgb = try ownPrepared(mode: "rgbmask")
        let unowned = template(first, owner: false)!
        let badOverrides: [(String, Template.TextureReference)] = [
            ("providerOverride", .provider(.namedLayerTarget(
                .init(providerLayerID: 902, variant: .primary)))),
            ("userPropertyOverride", .userProperty(.init(key: "self-authored-mask-property"))),
            ("graphOverride", .graph(ingress)),
        ]
        var negatives: [String: Bool] = [
            "nilDefault": validated(noDefault) == nil,
            "internalTargetDefault": validated(internalDefault) == nil,
            "regularSampler": validated(regular) == nil,
            "rgbMaskSampler": validated(rgb) == nil,
            "emptyMalformedOverrideRejectedAtTemplate": template(first, maskCandidates: []) == nil,
            "wrongPreviousIdentity": validated(first, input: .init(
                kind: .layerSource, layerID: 902, effect: nil, name: nil)) == nil,
            "wrongBlurredIdentity": validated(first, activeGraph: [0: .init(
                kind: .framebuffer, layerID: 901,
                effect: .init(layerID: 901, effectIndex: 1, descriptorID: "wrong-stage"),
                name: "wrong-quarter"), 2: ingress]) == nil,
            "wrongStaticColorArity": validated(first, template: template(first,
                tintComponents: [0.2, 0.4])!) == nil,
            "nonfiniteStaticColor": validated(first, template: template(first,
                tintComponents: [0.2, .infinity, 0.8])!) == nil,
            "dynamicColor": validated(first, template: template(first, dynamicTint: true)!) == nil,
            "ownerEntryRejects": sourceSlots(first, unowned) == nil,
            // validated is deliberately only the per-node proof. This positive
            // control prevents conflating that API with the whole-owner gate.
            "validatedDoesNotGrantOwner": validated(first, template: unowned) == expected,
        ]
        for (name, reference) in badOverrides {
            negatives[name] = validated(first, template: template(first,
                maskCandidates: [.init(reference: reference, provenance: .instance)])!) == nil
        }
        var conflicting = first.samplers
        conflicting[1] = conflicting[1]!.withSourceProvenPurpose(.straightAlbedo)
        negatives["conflictingDefaultPurpose"] = conflicting[1]?.hasTypedAuxiliaryDefault == false
            && validated(first, samplers: conflicting) == nil
        let output: [String: Any] = [
            "schema": "self-authored-prepared-default-mask-v1",
            "positives": positives, "negatives": negatives,
            "activeSamplerSlots": first.samplers.keys.sorted(),
            "sourceAnalyzerMaskSlot": first.fact.maskSlot ?? -1,
            "assetPixelsRead": false, "metalDeviceCreated": false,
            "evidenceCeiling": "Real source preparation/schema/purpose and host Eligibility only; no asset readiness, compiler artifact, route, GPU or official parity.",
        ]
        FileHandle.standardOutput.write(try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]))
    }
}
'''


def source_hashes(paths: list[Path]) -> dict[str, str]:
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


@unittest.skipUnless(shutil.which("xcrun"), "Xcode tools are required")
class ScenePreviousCompositeDefaultMaskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary_parent = os.environ.get("MWX_SCENE_DEFAULT_MASK_TEST_ROOT")
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-own-prepared-default-mask-", dir=temporary_parent)
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        harness = root / "DefaultMaskHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        sources = [*SWIFT_SOURCES, SUPPORT_SOURCE, harness]
        before = source_hashes(sources)
        sdk = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                             capture_output=True, text=True, check=True).stdout.strip()
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        binary = root / "default-mask-probe"
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-sdk", sdk,
                   "-target", "arm64-apple-macosx26.0", "-parse-as-library",
                   *map(str, sources), "-framework", "Metal", "-framework", "CoreGraphics",
                   "-framework", "ImageIO", "-module-cache-path", str(root / "module-cache"),
                   "-o", str(binary)]
        receipt_path = os.environ.get("MWX_SCENE_DEFAULT_MASK_TEST_RECEIPT")
        receipt = {"schema": "self-authored-default-mask-test-receipt-v1",
                   "compileArgv": command, "runArgv": [str(binary)],
                   "sourceSHA256Before": before, "assetPixelsRead": False,
                   "metalDeviceCreated": False}

        def save_receipt():
            if receipt_path:
                Path(receipt_path).write_text(json.dumps(receipt, indent=2) + "\n",
                                              encoding="utf-8")

        started = time.monotonic()
        compiled = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
                                  capture_output=True, text=True)
        receipt.update(compileExitCode=compiled.returncode,
                       compileSeconds=time.monotonic() - started,
                       compileStderr=compiled.stderr)
        save_receipt()
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        started = time.monotonic()
        completed = subprocess.run([str(binary)], cwd=REPOSITORY_ROOT, env=environment,
                                   capture_output=True, text=True, timeout=60)
        after = source_hashes(sources)
        receipt.update(runExitCode=completed.returncode,
                       runSeconds=time.monotonic() - started,
                       runStderr=completed.stderr, sourceSHA256After=after,
                       sourceDrift=[path for path, digest in before.items()
                                    if after[path] != digest])
        save_receipt()
        if completed.returncode:
            raise RuntimeError(completed.stderr or completed.stdout)
        if before != after:
            raise RuntimeError("Default-mask qualification inputs changed during compilation/run")
        cls.result = json.loads(completed.stdout)
        receipt["result"] = cls.result
        save_receipt()

    def test_real_prepared_asset_default_and_renamed_inputs_are_admitted(self):
        self.assertEqual(self.result["activeSamplerSlots"], [0, 1, 2])
        self.assertEqual(self.result["sourceAnalyzerMaskSlot"], 1)
        self.assertTrue(all(self.result["positives"].values()), self.result["positives"])

    def test_adjacent_unsupported_inputs_and_owner_boundary_remain_rejected(self):
        self.assertTrue(all(self.result["negatives"].values()), self.result["negatives"])
        self.assertFalse(self.result["assetPixelsRead"])
        self.assertFalse(self.result["metalDeviceCreated"])


if __name__ == "__main__":
    unittest.main()
