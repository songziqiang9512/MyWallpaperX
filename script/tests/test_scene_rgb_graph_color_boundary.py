#!/usr/bin/env python3
"""Three sampled colors retain source alpha through real Program/graph execution."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.tests import test_scene_graph_source_color_purpose as color_fixture
from script.tests import test_scene_resolved_material_graph_executor as fixture
from script.tests.scene_harness_io import separate_graph_debug_output

ROOT = Path(__file__).resolve().parents[2]
SOURCES = list(fixture.CONTRACT_FIXTURE["SWIFT_SOURCES"])

HARNESS = r'''
private struct RGBCase {
    let name: String
    let property: String
    let asset: SceneVFSAssetPath
    let shader: SceneShaderContract
    let graph: Graph
    let template: Template
    let usesUser: Bool
}

private func rgbContract(_ path: String, fragment: String) -> SceneShaderContract {
    let vertex = """
    uniform mat4 g_ModelViewProjectionMatrix;
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() {
        v_TexCoord = a_TexCoord;
        gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    }
    """
    let stageSources: [(SceneShaderContract.StageKind, String)] = [(.vertex, vertex), (.fragment, fragment)]
    let stages: [SceneShaderContract.Stage] = stageSources.map { kind, source in
        let file = path + (kind == .vertex ? ".vert" : ".frag")
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: file)
        return .init(kind: kind, relativePath: file, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
            annotations: parsed.annotations, declarations: parsed.declarations)
    }
    let digest = SceneShaderStableDigest.hash(stages)
    return .init(identity: path, sourceKind: .authoredSource, stages: stages, diagnostics: [],
        canonicalSHA256: digest, sourceGraph: .init(roots: stages.map {
            .init(label: $0.kind == .vertex ? "vertex" : "fragment", virtualPath: $0.relativePath)
        }, nodes: stages.map {
            .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
                rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
        }, edges: [], diagnostics: [], dependencySHA256: digest))
}

private func rgbCase(_ name: String, renamed: Bool = false, usesUser: Bool = true,
    wrongRT: Bool = false) -> RGBCase {
    let source = renamed ? "canvas" : "source"
    let replacement = renamed ? "picture" : "replacement"
    let background = renamed ? "behind" : "background"
    let weight = renamed ? "amount" : "coverage"
    let mix = renamed ? "lerp" : "mix"
    let helper = renamed ? "JoinInk" : "BlendPaint"
    let rt = wrongRT ? "_rt_owned_unknown" : (renamed ? "_RT_FULLFRAMEBUFFER" : "_rt_FullFrameBuffer")
    let fragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
    uniform sampler2D g_Texture1; // {"material":"selectedImage"}
    uniform sampler2D g_Texture3; // {"default":"\(rt)","material":"backgroundTexture","hidden":true}
    vec3 \(helper)(int mode, vec3 under, vec3 over, float factor) {
        return \(mix)(under, over, factor);
    }
    void main() {
        vec4 \(source) = texSample2D(g_Texture0, v_TexCoord);
        vec4 \(replacement) = texSample2D(g_Texture1, v_TexCoord);
        vec4 \(background) = texSample2D(g_Texture3, v_TexCoord);
        \(source).rgb = \(mix)(\(background).rgb, \(source).rgb, \(source).a);
        float \(weight) = 0.5 * \(replacement).a;
        \(source).rgb = \(helper)(0, \(source).rgb, \(replacement).rgb, \(weight));
        gl_FragColor = \(source);
    }
    """
    let path = renamed ? "fixtures/relocated/ink-assembly" : "fixtures/owned/rgb-assembly"
    let shader = rgbContract(path, fragment: fragment)
    let raw = graph(targets: [], nodes: [material(0, ordinal: 0, target: output, read: input)])
    let property = renamed ? "_renamedPicture" : "_ownedPicture"
    let asset = SceneVFSAssetPath(renamed ? "fixtures/relocated/chosen-image" : "fixtures/owned/chosen-image")!
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[0] = .init(index: 0, candidates: [.init(reference: .graph(input), provenance: .explicitBinding)])
    slots[1] = .init(index: 1, candidates: [.init(
        reference: usesUser ? .userProperty(.init(key: property)) : .asset(asset), provenance: .userTexture)])
    // Slot 3 has no manufactured graph/provider candidate. Its authored RT
    // default and effect context must select the real scene-background owner.
    let value = Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
            depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .effectOutput, bindings: [.init(slot: 0, texture: .layerSource)]),
        effectContext: .init(key: effect, input: input), shaderContract: shader,
        diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: path, contractIdentity: path,
            contractCanonicalSHA256: shader.canonicalSHA256, textureSources: [], uniformSources: []))!
    return .init(name: name, property: property, asset: asset, shader: shader,
        graph: raw, template: value, usesUser: usesUser)
}

private func rgbCache(_ value: RGBCase) -> Result<SceneResolvedMaterialVariantCache, SceneResolvedMaterialFailure> {
    SceneResolvedMaterialVariantCache.launchValidated(template: value.template, maximumVariantCount: 8)
}

private func rgbLaunch(_ cache: SceneResolvedMaterialVariantCache, value: RGBCase) -> String {
    launchEnvelopeFailureCode(cache.precompileLaunchEnvelope(implicitFramebufferIdentity: input,
        outputIsRGBA8Unorm: true,
        graphTextureFormatFacts: [input: .rgba8888],
        graphTextureContentFacts: [input: .color(.resolved(.premultipliedAlpha))],
        assetStates: [.init(path: value.asset, purpose: .straightAlbedo): .ready(.color(.resolved(.straightAlpha)))]))
}

private func rgbBoundary(_ boundary: SceneShaderColorBoundary?) throws -> [String: Any] {
    guard let boundary else { return [:] }
    return try JSONSerialization.jsonObject(with: JSONEncoder().encode(boundary)) as! [String: Any]
}

private func rgbCPU(_ value: RGBCase) throws -> [String: Any] {
    let admitted = admittedGraph(value.graph)
    var row: [String: Any] = ["case": value.name,
        "admittedStageCount": admitted.stagePrograms.count,
        "admittedEffectCount": admitted.renderGraph.effects.count]
    switch rgbCache(value) {
    case let .failure(failure): row["launch"] = diagnostic(failure)
    case let .success(cache):
        row["launch"] = rgbLaunch(cache, value: value)
        let snapshot = cache.launchEnvelopeCapabilitySnapshot()
        row["allEntriesReady"] = snapshot.allEntriesReady
        row["variants"] = try snapshot.variants.map { variant -> [String: Any] in
            let slots = variant.activeSamplers.keys.sorted()
            return ["slots": slots, "boundary": try rgbBoundary(variant.frontendProgram.colorBoundary),
                "transfer": SceneResolvedMaterialProgramIdentity.colorTransferToken(variant.frontendProgram.colorTransfer),
                "sourcePurposes": slots.map { variant.activeSamplers[$0]?.sourceProvenPurpose?.reportToken ?? "nil" },
                "slot3Default": String(describing: variant.activeSamplers[3]?.defaultTexture),
                "terminalReplay": variant.frontendProgram.supportsTerminalMaterialReplay]
        }
    }
    return row
}

private func rgbResource(_ device: MTLDevice, request: SceneFrameTextureIdentity,
    identity: SceneTextureProviderIdentity, purpose: SceneTextureLoadPurpose,
    content: SceneTextureContent, bgra: [UInt8], frameEpoch: UInt64 = 1) -> SceneFrameTextureResource {
    let texture = makeSource(device, width: 2, height: 2, usage: [.renderTarget, .shaderRead], bgra: bgra)
    let candidate = SceneTextureCandidate(texture: texture, identity: .provider(identity),
        generation: .provider(contentGeneration: frameEpoch), purpose: purpose, content: content,
        physicalSize: CGSize(width: 2, height: 2), mappedSize: CGSize(width: 2, height: 2),
        uvTransform: .identity, sampling: .linearClamp)
    return .init(publication: .init(requestIdentity: request, candidate: candidate,
        contentGeneration: frameEpoch), resourceGeneration: 1)
}

private func rgbReplacementIdentity(_ value: RGBCase,
    purpose: SceneTextureLoadPurpose = .straightAlbedo) -> SceneFrameTextureIdentity {
    value.usesUser ? .materialUserProperty(SceneUserPropertyTextureIdentity(propertyKey: value.property, purpose: purpose)!)
        : .asset(.init(path: value.asset, purpose: purpose))
}

private func rgbFinalization(_ cache: SceneResolvedMaterialVariantCache, value: RGBCase,
    device: MTLDevice, source: SceneFrameTextureResource, replacement: SceneFrameTextureResource,
    background: SceneFrameTextureResource) -> Result<SceneResolvedMaterialProgram, SceneResolvedMaterialFailure> {
    let entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [
        .graph(input): .ready(source), replacement.publication.requestIdentity: .ready(replacement)]
    guard let snapshot = frame(1, textureEntries: entries).overlayingSceneBackground(
        consumerLayerID: layerID, resource: background) else {
        return .failure(.init(phase: .texture, code: .resourceSnapshotUnresolved))
    }
    return SceneResolvedMaterialProgramFinalizer.finalize(snapshot.finalizationInput(template: value.template,
        layerID: layerID, renderSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        implicitFramebufferIdentity: input), variantCache: cache)
}

private func rgbRun(_ value: RGBCase, device: MTLDevice, queue: MTLCommandQueue) throws -> [String: Any] {
    var row: [String: Any] = ["case": value.name]
    let source = rgbResource(device, request: .graph(input), identity: .graph(allocationGeneration: 1,
        physicalToken: "owned-rgb-source"), purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)), bgra: [64,32,96,128])
    let replacement = rgbResource(device, request: rgbReplacementIdentity(value), identity: .dynamicText(layerID: 901),
        purpose: .straightAlbedo, content: .color(.resolved(.straightAlpha)), bgra: [32,192,64,128])
    let background = rgbResource(device, request: .sceneBackground(layerID),
        identity: .sceneBackground(consumerLayerID: layerID, frameEpoch: 1), purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)), bgra: [48,16,8,64])
    row["inputComplete"] = [source, replacement, background].map { $0.publication.isComplete }
    row["backgroundQualified"] = background.isCompleteSceneBackground(consumerLayerID: layerID, frameEpoch: 1)
    guard case let .success(cache) = rgbCache(value) else { row["failure"] = "cache"; return row }
    row["launch"] = rgbLaunch(cache, value: value)
    switch rgbFinalization(cache, value: value, device: device, source: source,
        replacement: replacement, background: background) {
    case let .failure(failure): row["finalization"] = diagnostic(failure); return row
    case let .success(program):
        row["finalization"] = "success"
        row["boundary"] = try rgbBoundary(program.frontendProgram.colorBoundary)
        row["transfer"] = SceneResolvedMaterialProgramIdentity.colorTransferToken(program.frontendProgram.colorTransfer)
        row["outputContract"] = String(describing: program.outputContract)
        row["slotPurposes"] = [0,1,3].map { program.textureSlots[$0]?.expectedPurpose.reportToken ?? "nil" }
        row["slotIdentities"] = [0,1,3].map { program.textureSlots[$0]?.registryIdentity.reportToken ?? "nil" }
        row["sameAtoms"] = zip([0,1,3], [source, replacement, background]).map { slot, resource in
            program.textureSlots[slot]?.resource.publication.isSameAtom(as: resource.publication) ?? false
        }
        row["inputMask"] = program.resolvedUniforms.first {
            $0.field.name == SceneShaderColorBoundary.uniformName
        }.map { $0.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } } ?? 0
    }
    let chain = admittedGraph(value.graph)
    let catalog = SceneResolvedMaterialRuntimeCatalog(entries: [
        .init(effect: effect, nodeIndex: 0): .template(value.template)], resourceDemandIssues: [])
    let caps = capabilities(chain, catalog: catalog,
        assetStates: [.init(path: value.asset, purpose: .straightAlbedo): .ready(.color(.resolved(.straightAlpha)))])
    row["capabilityReports"] = caps.reportLines
    guard let claim = caps.claim(chain), let capability = caps.resolve(claim.token, for: chain),
          let leases = makeChainedLeases(capability, device: device),
          let executor = Executor(device: device, capabilities: caps), let command = queue.makeCommandBuffer()
    else { row["failure"] = "execution-setup"; return row }
    row["sceneBackgroundRequirement"] = capability.sceneBackgroundRequirement != nil
    row["capabilityTerminalReplay"] = capability.supportsTerminalMaterialReplay
    let target = makeSource(device, width: 4, height: 4, usage: [.renderTarget, .shaderRead], bgra: [8,16,24,64])
    let state = frame(1, textureEntries: [replacement.publication.requestIdentity: .ready(replacement)])
    let preparation = executor.prepare(token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
        frame: state, sceneBackgroundResource: background, sourceTexture: source.publication.texture,
        sourceUniforms: .neutral(), sourcePipeline: makeSourcePipeline(device),
        frameInputs: .init(),
        commandBuffer: command, previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1)
    row["preparation"] = failureCode(preparation)
    guard case let .success(prepared) = preparation else { return row }
    row["stageFailures"] = prepared.stages.map { $0.effectLocalFailureReasonCode ?? "none" }
    row["programKeys"] = prepared.stages.flatMap(\.programCacheKeys)
    row["finalContent"] = String(describing: prepared.finalResource.publication.candidate.content)
    row["sameBackgroundAtom"] = prepared.sceneBackgroundResource?.publication.isSameAtom(as: background.publication) ?? false
    row["terminalPrepared"] = prepared.terminalMaterialReplay != nil
    guard executor.encode(prepared, commandBuffer: command),
          let read = appendReadback(prepared.finalTexture, commandBuffer: command) else {
        row["failure"] = "encode"; return row
    }
    let main = SceneMainPassEncoder(commandBuffer: command, target: target,
        clearColor: .init(red: 0, green: 0, blue: 0, alpha: 0), clearEnabled: false)
    guard case let .color(.resolved(representation)) = prepared.finalResource.publication.candidate.content,
          representation != .independentAlphaSignal,
          let compositor = makeProductionSourcePipeline(device) else {
        row["failure"] = "ordinary-compositor-setup"; return row
    }
    // Same typed straight/PMA selection as the ordinary image compositor.
    // The shared helper binds the real SceneImageLayer.metal fragment and
    // normal PMA source-over PSO; it supplies no substitute fragment math.
    var uniforms = SceneLayerFragmentUniforms.neutral()
    uniforms.sourceSampling.y = representation == .straightAlpha ? 1 : 0
    row["compositorSourceRepresentation"] = representation.rawValue
    row["compositorSourceSampling"] = uniforms.sourceSampling.y
    row["ordinaryCompositorEncoded"] = main.encodePreparedDraw { actualTarget, buffer in
        guard actualTarget === target, buffer === command else { return nil }
        return { encoder in
            compositor.bind(encoder: encoder)
            compositor.drawLayer(texture: prepared.finalTexture, mvp: matrix_identity_float4x4,
                uniforms: uniforms, encoder: encoder)
        }
    }
    row["mainFinished"] = main.finishEnsuringClear()
    let terminal = appendReadback(target, commandBuffer: command)
    command.commit(); command.waitUntilCompleted()
    row["gpuCompleted"] = command.status == .completed && command.error == nil
    row["frameEpoch"] = state.textureRegistrySnapshot.frameEpoch
    row["pixelsBGRA"] = read.allTexels
    row["terminalPixelsBGRA"] = terminal?.allTexels ?? []
    return row
}

private func rgbRejects(_ value: RGBCase, device: MTLDevice) -> [String: Any] {
    guard case let .success(cache) = rgbCache(value) else { return ["failure": "cache"] }
    _ = rgbLaunch(cache, value: value)
    let source = rgbResource(device, request: .graph(input), identity: .graph(allocationGeneration: 1,
        physicalToken: "owned-rgb-negative"), purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)), bgra: [64,32,96,128])
    let background = rgbResource(device, request: .sceneBackground(layerID),
        identity: .sceneBackground(consumerLayerID: layerID, frameEpoch: 1), purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)), bgra: [48,16,8,64])
    let data = rgbResource(device, request: rgbReplacementIdentity(value), identity: .dynamicText(layerID: 902),
        purpose: .straightAlbedo, content: .data, bgra: [32,192,64,128])
    let wrongPurpose = rgbResource(device, request: rgbReplacementIdentity(value, purpose: .premultipliedColor),
        identity: .dynamicText(layerID: 903), purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)), bgra: [16,96,32,128])
    func rejection(_ replacement: SceneFrameTextureResource) -> String {
        switch rgbFinalization(cache, value: value, device: device, source: source,
            replacement: replacement, background: background) {
        case .success: return "UNEXPECTED_SUCCESS"
        case let .failure(failure): return diagnostic(failure)
        }
    }
    return ["dataPublication": rejection(data), "wrongPurposePMA": rejection(wrongPurpose)]
}

@main private enum RGBGraphBoundaryHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        let cases = [rgbCase("user"), rgbCase("renamed-lerp", renamed: true), rgbCase("asset", usesUser: false)]
        var result: [String: Any] = ["cpu": try cases.map(rgbCPU),
            "wrongRT": try rgbCPU(rgbCase("wrong-RT", wrongRT: true))]
        if !CommandLine.arguments.contains("--cpu-only") {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
                throw NSError(domain: "owned-rgb-metal-unavailable", code: 1)
            }
            result["metalDevice"] = device.name
            result["gpu"] = try cases.map { try rgbRun($0, device: device, queue: queue) }
            result["rejections"] = rgbRejects(cases[0], device: device)
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def harness_text() -> str:
    prefix, marker, _ = fixture.HARNESS.partition("@main\nprivate enum Harness")
    helpers, helper_marker, _ = color_fixture.HARNESS.partition("private func traceMaterial")
    if not marker or not helper_marker:
        raise RuntimeError("existing graph helper boundaries changed")
    return prefix + helpers + HARNESS


def support_text() -> str:
    # The reused graph leaf shell predates the neutral Key move. Bind its
    # catalog to the actual production value; do not duplicate that DTO.
    old = """    struct Key: Hashable {
        let effect: Graph.EffectKey
        let nodeIndex: Int
    }"""
    if fixture.SUPPORT.count(old) != 1:
        raise RuntimeError("shared graph Key shell changed; review its production alias")
    return fixture.SUPPORT.replace(old, "    typealias Key = SceneResolvedMaterialKey")


def prepare_gate(directory: Path) -> dict:
    """Compile and run only the CPU branch; retain the exact binary for GPU release."""
    directory.mkdir(parents=True, exist_ok=True)
    sources = []
    inputs = {}
    for source in SOURCES:
        relative = source.relative_to(ROOT)
        target = directory / "sources" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = source.read_bytes()
        target.write_bytes(payload)
        inputs[str(relative)] = hashlib.sha256(payload).hexdigest()
        sources.append(target)
    support, harness = directory / "Support.swift", directory / "Harness.swift"
    support.write_text(support_text())
    harness.write_text(harness_text())
    binary = directory / "probe"
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(directory / "module-cache"),
        SWIFT_MODULECACHE_PATH=str(directory / "module-cache"),
        MWX_SCENE_GENERIC_SHADER_CACHE=str(directory / "shader-cache"),
        MWX_SCENE_PIPELINE_BINARY_ARCHIVE=str(directory / "pipeline-cache"))
    command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-Onone",
        "-whole-module-optimization", "-num-threads", "2", *fixture.CONTRACT_FIXTURE["GRAPH_SWIFT_FLAGS"],
        str(support), *map(str, sources), str(harness), "-framework", "Metal", "-framework", "CoreGraphics",
        "-framework", "ImageIO", "-framework", "Security", "-module-cache-path", str(directory / "module-cache"),
        "-o", str(binary)]
    metal = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayer.metal"
    metal_header = metal.with_name("SceneDistanceFog.metalh")
    metal_inputs = {str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest()
                    for source in (metal, metal_header)}
    air = directory / "scene-image.air"
    metal_commands = [
        ["xcrun", "--sdk", "macosx", "metal", "-c", str(metal), "-o", str(air)],
        ["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(directory / "default.metallib")],
    ]
    metal_logs = []
    for metal_command in metal_commands:
        compiled = subprocess.run(metal_command, cwd=ROOT, env=environment,
            capture_output=True, text=True, timeout=90)
        metal_logs.append(compiled.stdout + compiled.stderr)
        (directory / "metal-compile.log").write_text("\n".join(metal_logs))
        if compiled.returncode:
            raise RuntimeError("Production image Metal offline compile failed: " + compiled.stderr)
    compilation = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=240)
    (directory / "compile.log").write_text(compilation.stdout + compilation.stderr)
    manifest = {"sources": inputs, "harnessSHA256": hashlib.sha256(harness.read_bytes()).hexdigest(),
        "supportSHA256": hashlib.sha256(support.read_bytes()).hexdigest(),
        "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "command": command, "compileExit": compilation.returncode, "gpuRun": False,
        "metalSources": metal_inputs, "metalCommands": metal_commands,
        "metallibSHA256": hashlib.sha256((directory / "default.metallib").read_bytes()).hexdigest()}
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if compilation.returncode:
        raise RuntimeError(compilation.stderr)
    completed = separate_graph_debug_output(subprocess.run([str(binary), "--cpu-only"],
        cwd=directory, env=environment, capture_output=True, text=True, timeout=90))
    (directory / "cpu.stdout").write_text(completed.stdout)
    (directory / "cpu.stderr").write_text(completed.stderr)
    if completed.returncode:
        raise RuntimeError(completed.stderr or completed.stdout)
    if any(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != digest
           for path, digest in {**inputs, **metal_inputs}.items()):
        raise RuntimeError("RGB graph gate product inputs changed during compile/CPU run")
    return json.loads(completed.stdout)


def run_prepared(directory: Path) -> dict:
    """Explicit device phase; refuse to execute a stale CPU-prepared gate."""
    manifest = json.loads((directory / "manifest.json").read_text())
    if manifest["compileExit"] != 0 or manifest["testSHA256"] != hashlib.sha256(Path(__file__).read_bytes()).hexdigest():
        raise RuntimeError("RGB graph gate test identity changed")
    if manifest["metallibSHA256"] != hashlib.sha256((directory / "default.metallib").read_bytes()).hexdigest():
        raise RuntimeError("RGB graph product Metal library identity changed")
    for path, digest in {**manifest["sources"], **manifest["metalSources"]}.items():
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != digest:
            raise RuntimeError("RGB graph gate source identity changed: " + path)
    if manifest["harnessSHA256"] != hashlib.sha256(harness_text().encode()).hexdigest():
        raise RuntimeError("RGB graph helper identity changed")
    if manifest["supportSHA256"] != hashlib.sha256(support_text().encode()).hexdigest():
        raise RuntimeError("RGB graph support identity changed")
    environment = dict(os.environ, MWX_SCENE_GENERIC_SHADER_CACHE=str(directory / "shader-cache"),
        MWX_SCENE_PIPELINE_BINARY_ARCHIVE=str(directory / "pipeline-cache"))
    completed = separate_graph_debug_output(subprocess.run([str(directory / "probe")], cwd=directory,
        env=environment, capture_output=True, text=True, timeout=120))
    (directory / "gpu.stdout").write_text(completed.stdout)
    (directory / "gpu.stderr").write_text(completed.stderr)
    if completed.returncode:
        raise RuntimeError(completed.stderr or completed.stdout)
    return json.loads(completed.stdout)


class SceneRGBGraphColorBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-rgb-boundary-")
        directory = Path(cls.temporary.name)
        prepare_gate(directory)
        cls.result = run_prepared(directory)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary"):
            cls.temporary.cleanup()

    def test_real_schema_boundary_and_rt_default_are_exact(self) -> None:
        self.assertEqual(len(self.result["cpu"]), 3)
        for row in self.result["cpu"]:
            with self.subTest(case=row["case"]):
                self.assertEqual(row["launch"], "success", row)
                self.assertEqual(row["admittedStageCount"], 1, row)
                self.assertEqual(row["admittedEffectCount"], 1, row)
                self.assertTrue(row["allEntriesReady"], row)
                self.assertEqual(len(row["variants"]), 1, row)
                variant = row["variants"][0]
                self.assertEqual(variant["slots"], [0, 1, 3], row)
                # Graph input and RT provider retain their existing nominal purpose
                # owners; only the ambiguous selected-image slot needs a new
                # source-proven load-purpose fact.
                self.assertEqual(variant["sourcePurposes"], ["nil", "straight-albedo", "nil"], row)
                self.assertEqual(variant["transfer"], "straight-preserving-0", row)
                self.assertEqual(variant["boundary"]["colorInputSlots"], [0, 1, 3], row)
                self.assertEqual(variant["boundary"].get("alphaInputSlots", []), [], row)
                self.assertEqual(variant["boundary"]["outputRepresentation"], "straight-alpha", row)
                self.assertIn("typedFrameInput", variant["slot3Default"], row)
                self.assertTrue(variant["terminalReplay"], row)

    def test_exact_publications_feed_real_program_and_same_frame_graph(self) -> None:
        rows = self.result["gpu"]
        self.assertEqual(len(rows), 3)
        for row in rows:
            with self.subTest(case=row["case"]):
                self.assertNotIn("failure", row)
                self.assertEqual(row["inputComplete"], [True] * 3, row)
                self.assertTrue(row["backgroundQualified"], row)
                self.assertEqual(row["launch"], "success", row)
                self.assertEqual(row["finalization"], "success", row)
                self.assertEqual(row["slotPurposes"], ["premultiplied-color", "straight-albedo", "premultiplied-color"], row)
                self.assertEqual(row["sameAtoms"], [True] * 3, row)
                self.assertEqual(row["inputMask"], 9, row)
                self.assertEqual(row["boundary"]["colorInputSlots"], [0, 1, 3], row)
                self.assertEqual(row["preparation"], "success", row)
                self.assertEqual(row["stageFailures"], ["none"], row)
                self.assertEqual(len(row["programKeys"]), 1, row)
                self.assertTrue(row["sceneBackgroundRequirement"], row)
                self.assertTrue(row["sameBackgroundAtom"], row)
                self.assertEqual(row["frameEpoch"], 1, row)
                self.assertTrue(row["gpuCompleted"], row)
                self.assertFalse(row["capabilityTerminalReplay"], row)
                self.assertFalse(row["terminalPrepared"], row)
                self.assertEqual(row["compositorSourceRepresentation"], "straight-alpha", row)
                self.assertEqual(row["compositorSourceSampling"], 1, row)
                self.assertTrue(row["ordinaryCompositorEncoded"], row)
                self.assertTrue(row["mainFinished"], row)

    def test_partial_alpha_rgb_and_terminal_attachment_have_independent_pixels(self) -> None:
        # Fixed input BGRA: source PMA [64,32,96,128], background PMA
        # [48,16,8,64], selected straight [32,192,64,128]. The two authored
        # RGB mixes retain A0; terminal source-over loads [8,16,24,64].
        # These constants are the independent arithmetic oracle, not a fit to
        # a captured image or a reimplementation of the boundary lowering.
        # Ordinary compositor identity placement covers central 2x2 of the 4x4 terminal;
        # its twelve exterior pixels must preserve the partial-alpha load.
        for row in self.result["gpu"]:
            with self.subTest(case=row["case"]):
                self.assertEqual(len(row["pixelsBGRA"]), 4, row)
                self.assertEqual(len(row["terminalPixelsBGRA"]), 16, row)
                for pixel in row["pixelsBGRA"]:
                    self.assertTrue(all(abs(a-b) <= 1 for a,b in zip(pixel, [127,96,100,128])), row)
                for index, pixel in enumerate(row["terminalPixelsBGRA"]):
                    x, y = index % 4, index // 4
                    expected = [68,56,62,160] if x in (1,2) and y in (1,2) else [8,16,24,64]
                    self.assertTrue(all(abs(a-b) <= 1 for a,b in zip(pixel, expected)), row)

    def test_wrong_rt_and_data_or_wrong_purpose_publication_stay_rejected(self) -> None:
        self.assertNotEqual(self.result["wrongRT"]["launch"], "success", self.result["wrongRT"])
        for name in ("dataPublication", "wrongPurposePMA"):
            with self.subTest(case=name):
                self.assertNotEqual(self.result["rejections"][name], "UNEXPECTED_SUCCESS", self.result["rejections"])


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--prepare":
        print(json.dumps(prepare_gate(Path(sys.argv[2]).resolve()), indent=2))
    elif len(sys.argv) == 3 and sys.argv[1] == "--run-prepared":
        SceneRGBGraphColorBoundaryTests.result = run_prepared(Path(sys.argv[2]).resolve())
        SceneRGBGraphColorBoundaryTests.setUpClass = classmethod(lambda cls: None)
        SceneRGBGraphColorBoundaryTests.tearDownClass = classmethod(lambda cls: None)
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(SceneRGBGraphColorBoundaryTests)
        raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
    else:
        unittest.main()
