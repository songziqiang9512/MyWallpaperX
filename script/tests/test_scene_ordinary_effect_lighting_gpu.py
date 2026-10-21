#!/usr/bin/env python3
"""Small ordinary-light host gate through the real graph/finalizer/Metal path.

The shared graph scaffold supplies leaf descriptor/capture adapters. Production
FrameInputs/copy, request/source replacement, snapshot, VariantCache, Finalizer,
uniform encoder, graph executor and pass encoder own the measured path. This
does not exercise App FramePreflight, official shaders or signed generic tools.
``--compile-only DIR`` freezes Swift inputs and creates an executable without
running it, creating a Metal device, compiling a Metal library or submitting GPU
work. Normal unittest execution is the explicit GPU entry point.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_effect_draw_alpha as alpha_fixture
from script.tests import test_scene_resolved_material_graph_executor as graph_fixture
from script.tests.scene_harness_io import separate_graph_debug_output
from script.tests.test_scene_property_live_routing import method_body

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


def support_source() -> str:
    support = alpha_fixture.runtime_frame_support()
    bridge = (SCENE / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift").read_text()
    request = method_body(bridge, "struct FramePreparationRequest {")
    # Claim/target allocation and image lookup are fixture leaves. The request
    # DTO and its source replacement are copied verbatim from their real owners.
    declarations = """
    struct ClaimedExecution {
        let layerID: Int
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
    }
""" + request
    support = support.replace("final class SceneResolvedMaterialRuntimeBridge {",
        "final class SceneResolvedMaterialRuntimeBridge {\n" + declarations, 1)
    source_materials = (SCENE / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge+SourceMaterials.swift").read_text()
    resolver = (SCENE / "Resources/Textures/SceneBaseImageTextureCandidateSupport.swift").read_text()
    support += "\n" + r'''
struct SceneResolvedMaterialFrameTargetPlan {}
struct SceneBaseImageTextureSnapshot {
    let textures: [Int: MTLTexture]
    let candidates: [Int: SceneTextureCandidate]
    subscript(_ id: Int) -> MTLTexture? { textures[id] }
    func candidate(for id: Int, matching texture: MTLTexture) -> SceneTextureCandidate? {
        guard let candidate = candidates[id], candidate.texture === texture else { return nil }
        return candidate
    }
}
enum SceneBaseImageTextureCandidateResolver {
''' + method_body(resolver, "static func sample(") + "\n" + method_body(
        resolver, "static func supportsColorSampling(") + "\n}\n"
    support += "extension SceneResolvedMaterialRuntimeBridge.FramePreparationRequest {\n"
    support += method_body(source_materials, "func replacingSource(") + "\n}\n"
    return support


HELPERS = graph_fixture.HARNESS.split("@main\nprivate enum Harness", 1)[0].replace(
    "Plan.PixelExtent(width: 2, height: 2)", "Plan.PixelExtent(width: 8, height: 8)", 1)

HARNESS = HELPERS + r'''
// These are self-owned scalar echoes, not a lighting algorithm. Target pixels
// go through the actual host model; CPU expectations below are independent
// scalar expressions for the chosen 90-degree affine transform.
private func ownedShader(_ node: Graph.Node, renamed: Bool, colors: Bool,
                         constant: Bool = false) -> SceneShaderContract {
    let worldName = renamed ? "v_AuthoredPoint" : "v_World"
    let uvName = renamed ? "v_PanelUV" : "v_TexCoord"
    let worldExpression = renamed
        ? "mul(vec4(a_Position.xy, a_Position.z, 1.0), g_EffectModelMatrix).xy"
        : "mul(vec4(a_Position, 1.0), g_EffectModelMatrix).xy"
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    uniform mat4 g_ModelViewProjectionMatrix;
    \(colors || constant ? "" : "uniform mat4 g_EffectModelMatrix; varying vec2 \(worldName);")
    varying vec2 \(uvName);
    void main() {
        \(uvName) = a_TexCoord;
        \(colors || constant ? "" : "\(worldName) = \(worldExpression);")
        gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    }
    """
    let fragment: String
    if constant {
        fragment = "void main(){ gl_FragColor = vec4(0.2, 0.4, 0.6, 1.0); }"
    } else if colors {
        fragment = """
        varying vec2 \(uvName);
        uniform vec4 g_LightsColorPremultiplied[3];
        void main() {
            vec3 \(renamed ? "energy" : "signal") = g_LightsColorPremultiplied[0].xyz;
            if (\(uvName).x >= 0.25) { \(renamed ? "energy" : "signal") = g_LightsColorPremultiplied[1].xyz; }
            if (\(uvName).x >= 0.5) { \(renamed ? "energy" : "signal") = g_LightsColorPremultiplied[2].xyz; }
            if (\(uvName).x >= 0.75) {
                \(renamed ? "energy" : "signal") = vec3(g_LightsColorPremultiplied[0].w,
                    g_LightsColorPremultiplied[1].w, g_LightsColorPremultiplied[2].w);
            }
            gl_FragColor = vec4(\(renamed ? "energy * 0.0625" : "signal / 16.0"), 1.0);
        }
        """
    } else {
        fragment = """
        varying vec2 \(worldName);
        uniform vec3 g_LightsPosition[4];
        void main() {
            gl_FragColor = vec4(\(worldName) / 1000.0, g_LightsPosition[0].y / 1000.0, 1.0);
        }
        """
    }
    let prefix = renamed ? "owned/renamed-signal" : "owned/world-signal"
    let sourceStages: [(SceneShaderContract.StageKind, String)] = [(.vertex, vertex), (.fragment, fragment)]
    let stages: [SceneShaderContract.Stage] = sourceStages.map { kind, source in
        let path = "\(prefix)-\(node.nodeIndex).\(kind == .vertex ? "vert" : "frag")"
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
        return .init(kind: kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
            annotations: parsed.annotations, declarations: parsed.declarations)
    }
    let graph = SceneShaderSourceGraph(roots: stages.map {
        .init(label: $0.kind.rawValue, virtualPath: $0.relativePath)
    }, nodes: stages.map {
        .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
            rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
    }, edges: [], diagnostics: [], dependencySHA256: SceneShaderStableDigest.hash(stages))
    return .init(identity: "\(prefix)-\(node.nodeIndex)", sourceKind: .authoredSource, stages: stages,
        diagnostics: [], canonicalSHA256: SceneShaderStableDigest.hash(stages), sourceGraph: graph)
}

private func ownedTemplate(_ node: Graph.Node, renamed: Bool,
                           colors: Bool, constant: Bool = false) -> Template {
    let base = template(for: node)
    let shader = ownedShader(node, renamed: renamed, colors: colors, constant: constant)
    return Template.validated(textureSlots: base.textureSlots, combos: [], uniformDeclarations: [],
        renderState: base.renderState, graphRole: base.graphRole,
        effectContext: .init(key: node.effect,
            input: node.effect == chainedFirstEffect ? input : chainedFirstOutput),
        shaderContract: shader, diagnosticProvenance: .init(nodeIndex: node.nodeIndex,
            authoredShaderPath: shader.identity, contractIdentity: shader.identity,
            contractCanonicalSHA256: shader.canonicalSHA256, textureSources: [], uniformSources: []))!
}

private func lightInputs(_ iteration: Int) -> SceneAuthoredShaderLightingInputs {
    var builder = SceneAuthoredShaderLightingInputs.Builder(
        orthographicHeight: 786, ambient: [0.125, 0.25, 0.375])
    let red: Float = iteration == 0 ? 0.125 : 0.375
    builder.appendPoint(renderWorldPosition: .init(100, 606, 20),
        color: .init(red, 0.25, 0.5), intensity: iteration == 0 ? 0.5 : 1,
        radius: iteration == 2 ? 0 : 4)
    for (position, color) in [
        (SIMD3<Float>(200,500,30), SIMD3<Float>(0.25,0.5,0.125)),
        (SIMD3<Float>(300,400,40), SIMD3<Float>(0.5,0.125,0.25)),
        (SIMD3<Float>(400,300,50), SIMD3<Float>(0.375,0.625,0.875))
    ] {
        builder.appendPoint(renderWorldPosition: position, color: color, intensity: 0.5, radius: 4)
    }
    return builder.finish()
}

private func lightFrame(_ index: UInt64, lighting: SceneAuthoredShaderLightingInputs)
    -> SceneResolvedMaterialFrameSnapshot {
    try! .validated(textureSnapshot: .init(frameEpoch: index, frameIndex: index, entries: [:]),
        dynamicSnapshot: .empty(frameIndex: index), frameInputs: .init(frameIndex: index,
            screenSize: .init(width: 1210, height: 786), sceneTime: Float(index), dayTime: 0,
            frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero,
            lighting: lighting)).get()
}

private func transformedCard() -> simd_float4x4 {
    let parent = SceneMatrix.translation(.init(300,500,7))
        * SceneMatrix.rotationZ(.pi / 2) * SceneMatrix.scale(.init(2,3,1))
    return parent * SceneMatrix.translation(.init(30,-40,0))
        * SceneMatrix.scale(.init(100,-60,1)) * SceneMatrix.translation(.init(-0.2,0.1,0))
}

private func inputCarrier(model: simd_float4x4?) -> SceneResolvedMaterialRuntimeBridge.FrameInputs {
    .init(dynamicValues: .empty(frameIndex: 0), cursorUV: .zero, previousCursorUV: .zero,
        pointerIsInside: true, previousPointerIsInside: true, pointerMovement: 0,
        primaryButtonIsDown: false, layerModelMatrix: SceneMatrix.translation(.init(999,888,77)),
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectUnitModelMatrix: model,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        frameTime: 1 / 60, time: 0, audioSpectrum: .silent)
        .withDependencyEffects([])
}

private func sourceCandidate(_ texture: MTLTexture) -> SceneTextureCandidate {
    .init(texture: texture, identity: .builtIn(name: "owned-source-\(texture.width)"),
        generation: .immutable(revision: 1), purpose: .premultipliedColor,
        content: .color(.resolved(.opaque)),
        physicalSize: .init(width: texture.width, height: texture.height),
        mappedSize: .init(width: texture.width, height: texture.height),
        uvTransform: .identity, sampling: .linearClamp)
}

private func replacedRequest(old: MTLTexture, new: MTLTexture,
                             sourcePipeline: SceneImageLayerPipeline,
                             inputs: SceneResolvedMaterialRuntimeBridge.FrameInputs)
    -> SceneResolvedMaterialRuntimeBridge.FramePreparationRequest {
    let request = SceneResolvedMaterialRuntimeBridge.FramePreparationRequest(
        claim: .init(layerID: layerID, sourceRoute: .capturedLayerTexture), targetPlan: .init(),
        sourceTexture: old, sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
        frameInputs: inputs)
    return request.replacingSource(
        original: .init(textures: [layerID: old], candidates: [layerID: sourceCandidate(old)]),
        prepared: .init(textures: [layerID: new], candidates: [layerID: sourceCandidate(new)]))
}

private func expectedWorld(_ x: Int, _ y: Int, width: Int, height: Int) -> [UInt8] {
    let u = (Float(x) + 0.5) / Float(width) - 0.5
    let v = 0.5 - (Float(y) + 0.5) / Float(height)
    // parent T(300,500)*R90*S(2,3), child T(30,-40)*S(100,-60)*T(-.2,.1)
    // yields render-world (438+180v, 520+200u). Host flips Y about 786.
    return [180, (266 - 200*u), (438 + 180*v)].map { UInt8(($0 / 1000 * 255).rounded()) } + [255]
}

private func expectedColor(_ x: Int, iteration: Int) -> [UInt8] {
    let first: [Float] = iteration == 0 ? [1,2,4] : iteration == 1 ? [6,4,8] : [0,0,0]
    let rgb: [Float] = x < 2 ? first : x < 4 ? [2,4,1] : x < 6 ? [4,1,2] : [3,5,7]
    return [rgb[2],rgb[1],rgb[0]].map { UInt8(($0 / 16 * 255).rounded()) } + [255]
}

private func close(_ actual: [UInt8], _ expected: [UInt8]) -> Bool {
    zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
}

private func runCase(device: MTLDevice, queue: MTLCommandQueue, renamed: Bool,
                     nilWorld: Bool = false, noLighting: Bool = false) -> [String: Any] {
    let small = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID,
        effect: chainedFirstEffect, name: renamed ? "renamed-downsample" : "probe-small")
    let nodes = [
        material(0, ordinal: 0, target: small, read: input, owner: chainedFirstEffect),
        material(1, ordinal: 1, target: chainedFirstOutput, read: small, owner: chainedFirstEffect),
        material(2, ordinal: 0, target: chainedSecondOutput, read: chainedFirstOutput, owner: chainedSecondEffect)]
    let value = Graph(layerID: layerID, effects: [
        .init(key: chainedFirstEffect, definitionPath: "owned/affine.json", input: input,
            output: chainedFirstOutput, nodeIndices: [0,1]),
        .init(key: chainedSecondEffect, definitionPath: "owned/peer.json", input: chainedFirstOutput,
            output: chainedSecondOutput, nodeIndices: [2])],
        renderTargets: [rawTarget(small, width: 4, height: 4)], nodes: nodes,
        finalOutput: chainedSecondOutput, blockers: [])
    let admitted = orderedLayerGraph(value)
    let catalog = SceneResolvedMaterialRuntimeCatalog(entries: Dictionary(uniqueKeysWithValues:
        nodes.map { node in
            (SceneResolvedMaterialRuntimeCatalog.Key(effect: node.effect, nodeIndex: node.nodeIndex),
             SceneResolvedMaterialRuntimeCatalog.Entry.template(ownedTemplate(node,
                renamed: renamed, colors: node.nodeIndex == 2,
                constant: noLighting && node.nodeIndex == 2)))
        }), resourceDemandIssues: [])
    let caps = capabilities(admitted, catalog: catalog)
    guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
          let executor = Executor(device: device, capabilities: caps),
          let leases = makeChainedLeases(capability, device: device) else {
        return ["failure": "setup", "reports": caps.reportLines]
    }
    let sourcePipeline = makeSourcePipeline(device)
    let old = makeSource(device, width: 8, height: 8, bgra: [12,23,34,255])
    let new = makeSource(device, width: 8, height: 8, bgra: [67,89,123,255])
    var rows: [[String: Any]] = []
    var states: [Graph.EffectKey: Executor.State] = [:]
    var resources: [Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]] = [:]
    var firstKeys: [[String]] = []
    var firstFrontend = 0, firstLibrary = 0
    let variants = nodes.compactMap { capability.material(for: $0)?.variants }
    for iteration in 0..<(nilWorld ? 1 : 3) {
        let model = nilWorld ? nil : transformedCard()
        let request = replacedRequest(old: old, new: new, sourcePipeline: sourcePipeline,
            inputs: inputCarrier(model: model))
        let index = UInt64(iteration + 1)
        let snapshot = lightFrame(index, lighting: noLighting ? .unavailable : lightInputs(iteration))
        let command = queue.makeCommandBuffer()!
        let preparation = executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: snapshot,
            sourceTexture: request.sourceTexture, sourceUniforms: request.sourceUniforms,
            sourcePipeline: request.sourcePipeline, frameInputs: request.frameInputs,
            commandBuffer: command, previousStates: states, previousGraphResources: resources,
            effectGeneration: 1, resetGeneration: 1)
        guard case let .success(prepared) = preparation,
              executor.encode(prepared, commandBuffer: command), prepared.stages.count == 2,
              let finalRead = appendReadback(prepared.finalTexture, commandBuffer: command),
              let largeRead = appendReadback(prepared.stages[0].effectOutputResource.publication.texture,
                  commandBuffer: command) else {
            return ["failure": failureCode(preparation), "frames": rows]
        }
        let smallRead = nilWorld ? nil : prepared.stages[0].frameResources[small].flatMap {
            appendReadback($0.publication.texture, commandBuffer: command)
        }
        command.commit(); command.waitUntilCompleted()
        let keys = prepared.stages.map(\.programCacheKeys)
        let frontendCount = variants.reduce(0) { $0 + $1.counters.frontendCompilationCount }
        let libraryCount = executor.materialEncoder.metalLibraryCompilationAttemptCount
        if iteration == 0 { firstKeys = keys; firstFrontend = frontendCount; firstLibrary = libraryCount }
        let finalExpected = (0..<8).map { x in noLighting ? [153,102,51,255].map(UInt8.init)
            : expectedColor(x, iteration: iteration) }
        let peerMatches = (0..<8).allSatisfy { y in (0..<8).allSatisfy { x in
            close(finalRead.pixel(x: x, y: y), finalExpected[x])
        } }
        let worldMatches: Bool
        if nilWorld {
            worldMatches = largeRead.allTexels.allSatisfy { close($0, [67,89,123,255]) }
        } else if let smallRead {
            worldMatches = [smallRead, largeRead].allSatisfy { read in
                (0..<read.height).allSatisfy { y in (0..<read.width).allSatisfy { x in
                    close(read.pixel(x: x, y: y), expectedWorld(x,y,width: read.width,height: read.height))
                } }
            }
        } else { worldMatches = false }
        rows.append(["iteration": iteration, "gpuCompleted": command.status == .completed && command.error == nil,
            "sourceWasReplaced": request.sourceTexture === new,
            "modelSurvivedCopies": model.map { request.frameInputs.effectUnitModelMatrix == $0 } ??
                (request.frameInputs.effectUnitModelMatrix == nil),
            "worldPixelsMatch": worldMatches, "peerPixelsMatch": peerMatches,
            "worldFailure": prepared.stages[0].effectLocalFailureReasonCode ?? "none",
            "peerFailure": prepared.stages[1].effectLocalFailureReasonCode ?? "none",
            "smallExtent": smallRead.map { [$0.width,$0.height] } ?? [],
            "largeExtent": [largeRead.width,largeRead.height],
            "worldFirst": largeRead.firstPixel,
            "worldExpectedFirst": nilWorld ? [67,89,123,255] : expectedWorld(0,0,width:8,height:8).map(Int.init),
            "colorBands": [0,2,4,6].map { finalRead.pixel(x:$0,y:0) },
            "expectedBands": [0,2,4,6].map { finalExpected[$0] },
            "samePreparedPrograms": keys == firstKeys,
            "noRecompile": frontendCount == firstFrontend && libraryCount == firstLibrary])
        states = Dictionary(uniqueKeysWithValues: prepared.stages.map { ($0.effect,$0.transition.nextState) })
        resources = Dictionary(uniqueKeysWithValues: prepared.stages.map { ($0.effect,$0.persistentResources) })
    }
    return ["frames": rows, "renamed": renamed, "nilWorld": nilWorld, "noLighting": noLighting]
}

@main private enum OrdinaryLightGPU {
    static func main() throws {
        // The bounded compiler gate owns authored AST/Metal execution. Signed
        // production generic tooling is outside this portable Swift carrier.
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"skip\":\"Metal unavailable\"}"); return
        }
        let result = [
            "affine": runCase(device:device,queue:queue,renamed:false),
            "renamedEquivalent": runCase(device:device,queue:queue,renamed:true),
            "nilWorld": runCase(device:device,queue:queue,renamed:false,nilWorld:true),
            "nilWorldNoLighting": runCase(device:device,queue:queue,renamed:false,nilWorld:true,noLighting:true)]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options:[.sortedKeys]), as:UTF8.self))
    }
}
'''


def compile_carrier(directory: Path) -> tuple[subprocess.CompletedProcess, Path, dict[str, str]]:
    """Freeze inputs, compile CPU executable only; never execute it here."""
    directory.mkdir(parents=True, exist_ok=True)
    extracted_owners = [SCENE / path for path in (
        "Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift",
        "Rendering/Graph/SceneResolvedMaterialRuntimeBridge+SourceMaterials.swift",
        "Resources/Textures/SceneBaseImageTextureCandidateSupport.swift",
        "Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift",
        "Rendering/Composition/SceneImageLayerDrawRequest.swift")]
    hashes = {str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in extracted_owners}
    support = directory / "Support.swift"
    harness = directory / "Harness.swift"
    support.write_text(support_source())
    harness.write_text(HARNESS)
    sources = list(dict.fromkeys([*graph_fixture.CONTRACT_FIXTURE["SWIFT_SOURCES"],
                                 SCENE / "Rendering/Geometry/SceneMatrix.swift"]))
    frozen = []
    for index, source in enumerate(sources):
        data = source.read_bytes()
        hashes[str(source)] = hashlib.sha256(data).hexdigest()
        target = directory / f"source-{index:03d}-{source.name}"
        target.write_bytes(data)
        frozen.append(target)
    binary = directory / "ordinary-effect-lighting-gpu"
    env = os.environ.copy()
    env.update(CLANG_MODULE_CACHE_PATH=str(directory / "clang-cache"),
               SWIFT_MODULECACHE_PATH=str(directory / "swift-cache"))
    compiled = subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
        *graph_fixture.CONTRACT_FIXTURE["GRAPH_SWIFT_FLAGS"], str(support), *map(str,frozen),
        str(harness), "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
        "-module-cache-path", str(directory / "module-cache"), "-o", str(binary)],
        cwd=ROOT, env=env, capture_output=True, text=True)
    (directory / "compile.stdout").write_text(compiled.stdout)
    (directory / "compile.stderr").write_text(compiled.stderr)
    manifest = {"scope":"compile-only; no Metal/GPU execution", "returncode":compiled.returncode,
                "binary":str(binary), "sources":hashes,
                "generated":{"Support.swift":hashlib.sha256(support.read_bytes()).hexdigest(),
                             "Harness.swift":hashlib.sha256(harness.read_bytes()).hexdigest()}}
    (directory / "compile-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    return compiled, binary, hashes


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class OrdinaryEffectLightingGPUTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.work = tempfile.TemporaryDirectory(prefix="mwx-ordinary-light-gpu-")
        cls.addClassCleanup(cls.work.cleanup)
        work = Path(cls.work.name)
        compiled, binary, hashes = compile_carrier(work)
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        env = os.environ.copy()
        env["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(work / "scene-cache")
        env["MWX_SCENE_PIPELINE_BINARY_ARCHIVE"] = str(work / "scene-cache")
        completed = separate_graph_debug_output(subprocess.run([str(binary)],cwd=ROOT,
            env=env,capture_output=True,text=True))
        if completed.returncode:
            raise AssertionError(completed.stderr)
        cls.result = json.loads(completed.stdout)
        if "skip" in cls.result:
            raise unittest.SkipTest(cls.result["skip"])
        if hashes != {path:hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in hashes}:
            raise AssertionError("product sources changed during frozen GPU gate")

    def test_world_carrier_two_actual_targets_and_live_packed_arrays(self) -> None:
        for name in ("affine","renamedEquivalent"):
            case = self.result[name]
            self.assertNotIn("failure",case,case)
            self.assertEqual(len(case["frames"]),3,case)
            for frame in case["frames"]:
                with self.subTest(case=name,iteration=frame["iteration"]):
                    for key in ("gpuCompleted","sourceWasReplaced","modelSurvivedCopies",
                                "worldPixelsMatch","peerPixelsMatch","samePreparedPrograms","noRecompile"):
                        self.assertTrue(frame[key],frame)
                    self.assertEqual(frame["smallExtent"],[4,4],frame)
                    self.assertEqual(frame["largeExtent"],[8,8],frame)
                    self.assertEqual(frame["worldFailure"],"none",frame)
                    self.assertEqual(frame["peerFailure"],"none",frame)
            self.assertNotEqual(case["frames"][0]["colorBands"][0],case["frames"][1]["colorBands"][0])
            self.assertEqual(case["frames"][2]["colorBands"][0],[0,0,0,255])

    def test_missing_world_is_local_and_does_not_invent_identity(self) -> None:
        for name in ("nilWorld","nilWorldNoLighting"):
            case = self.result[name]
            self.assertNotIn("failure",case,case)
            self.assertEqual(len(case["frames"]),1,case)
            frame = case["frames"][0]
            for key in ("gpuCompleted","sourceWasReplaced","modelSurvivedCopies",
                        "worldPixelsMatch","peerPixelsMatch"):
                self.assertTrue(frame[key],frame)
            self.assertNotEqual(frame["worldFailure"],"none",frame)
            self.assertEqual(frame["peerFailure"],"none",frame)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--compile-only",type=Path)
    args,remaining = parser.parse_known_args()
    if args.compile_only:
        completed,binary,_ = compile_carrier(args.compile_only.resolve())
        print(json.dumps({"returncode":completed.returncode,"binary":str(binary),
                          "executed":False,"stderr":completed.stderr[-12000:]},indent=2))
        raise SystemExit(completed.returncode)
    unittest.main(argv=[__file__,*remaining])
