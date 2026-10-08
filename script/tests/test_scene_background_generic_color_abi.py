#!/usr/bin/env python3
"""Default background color ABI through the real launch producer and Metal."""

from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import runpy
import subprocess
import tempfile
import unittest

from script.tests.test_scene_generic_shader_texture_transform_compiler import compiler_bundle


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = runpy.run_path(str(Path(__file__).with_name(
    "test_scene_resolved_material_program_finalizer.py")))
SOURCES = list(dict.fromkeys(FIXTURE["SWIFT_SOURCES"]))

HARNESS = r'''
import Foundation
import Metal

@main private enum BackgroundColorABIHarness {
    typealias Template = SceneResolvedMaterialTemplate
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func contract(_ fragment: String) -> SceneShaderContract {
        let vertex = """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord; }
        """
        let stages = [(.vertex, "own/root.vert", vertex),
                      (.fragment, "own/root.frag", fragment)].map {
            (kind: SceneShaderContract.StageKind, path: String, source: String)
                -> SceneShaderContract.Stage in
            let parsed = SceneShaderContractSourceParser().parse(
                source, stageRelativePath: path)
            return .init(kind: kind, relativePath: path, source: source,
                rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
                includes: parsed.includes, annotations: parsed.annotations,
                declarations: parsed.declarations)
        }
        let nodes: [SceneShaderSourceGraph.Node] = stages.map {
            .init(virtualPath: $0.relativePath, provenance: .package,
                source: $0.source, rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
        }
        let graph = SceneShaderSourceGraph(
            roots: stages.map { .init(label: $0.kind.rawValue, virtualPath: $0.relativePath) },
            nodes: nodes, edges: [], diagnostics: [],
            dependencySHA256: SceneShaderSourceGraph.dependencySHA256(nodes: nodes, edges: []))
        return .init(identity: "own/background-color", sourceKind: .authoredSource,
            stages: stages, diagnostics: [],
            canonicalSHA256: SceneShaderStableDigest.hash(Data(fragment.utf8)),
            sourceGraph: graph)
    }

    static func evaluate(_ name: String, defaultName: String = "_rt_FullFrameBuffer",
                         mode: String? = nil, override: Bool = false,
                         opaque: Bool = false) throws -> [String: Any] {
        var metadata: [String: Any] = ["hidden": true, "default": defaultName,
                                      "material": "albedo"]
        if let mode { metadata["mode"] = mode }
        let annotation = String(data: try JSONSerialization.data(withJSONObject: metadata,
            options: [.sortedKeys]), encoding: .utf8)!
        let fragment = """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"hidden":true,"material":"framebuffer"}
        uniform sampler2D g_Texture3; // \(annotation)
        void main() {
            vec4 p = texSample2D(g_Texture0, v_TexCoord);
            vec4 b = texSample2D(g_Texture3, v_TexCoord);
            \(opaque ? "gl_FragColor = vec4(mix(p.rgb, b.rgb, 0.4), 1.0);" : "p.rgb = mix(p.rgb, b.rgb, 0.4); p.a = sqrt(p.a); gl_FragColor = p;")
        }
        """
        let shader = contract(fragment)
        let input = Graph.TextureIdentity(kind: .layerSource, layerID: 42,
                                          effect: nil, name: nil)
        let fallback = SceneVFSAssetPath("own/fallback")!
        var slots = [Template.TextureSlot?](repeating: nil, count: 8)
        if override {
            slots[3] = .init(index: 3, candidates: [
                .init(reference: .asset(fallback), provenance: .material)])
        }
        let template = Template.validated(textureSlots: slots, combos: [],
            uniformDeclarations: [], renderState: SceneMaterialRenderState.compile(
                blending: "normal", depthTest: "disabled", depthWrite: "disabled",
                cullMode: "nocull", alphaWriting: nil)!,
            graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
                             nodeTarget: .effectOutput, bindings: []),
            effectContext: .init(key: .init(layerID: 42, effectIndex: 0,
                                           descriptorID: name), input: input),
            compatibilityTarget: .windowsDX11ShaderModel4, shaderContract: shader,
            diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: shader.identity,
                contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        let cache = try SceneResolvedMaterialVariantCache.launchValidated(
            template: template, maximumVariantCount: 256).get()
        let launch = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: input,
            outputStorage: .color, outputIsRGBA8Unorm: false,
            assetStates: [.init(path: fallback, purpose: .straightAlbedo):
                .ready(.color(.resolved(.straightAlpha)))])
        let snapshot = cache.launchEnvelopeCapabilitySnapshot()
        let variants = try snapshot.variants.map { variant -> [String: Any] in
            let program = variant.frontendProgram
            var result: [String: Any] = ["pmaSlots": variant.premultipliedColorInputSlots.sorted(),
                "backend": program.backend.rawValue, "profile": variant.routeDecision.profile,
                "colorTransfer": String(describing: program.colorTransfer),
                "metalSource": program.metalSource,
                "metalSHA256": SceneShaderStableDigest.hash(Data(program.metalSource.utf8))]
            if name == "source-default" || name == "opaque-output" {
                result["pixels"] = try render(program)
            }
            return result
        }
        return ["launch": String(describing: launch), "ready": snapshot.allEntriesReady,
                "variants": variants, "vertex": shader.stages[0].source,
                "fragment": fragment]
    }

    static func render(_ program: SceneAuthoredShaderProgram) throws -> [Float] {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try device.makeLibrary(source: program.metalSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: program.vertexFunctionName)
        descriptor.fragmentFunction = library.makeFunction(name: program.fragmentFunctionName)
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 8, height: 8, mipmapped: false)
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        let output = device.makeTexture(descriptor: textureDescriptor)!
        textureDescriptor.width = 1
        textureDescriptor.height = 1
        let primary = device.makeTexture(descriptor: textureDescriptor)!
        let background = device.makeTexture(descriptor: textureDescriptor)!
        for (texture, values) in [(primary, [Float(0.2), 0.1, 0.05, 0.5]),
                                  (background, [Float(0.1), 0.3, 0.2, 0.5])] {
            values.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 16) }
        }
        var uniforms = Data(count: max(16, program.uniformLayout.byteSize))
        for field in program.uniformLayout.fields where field.authoredName == "mwxRenderSize" {
            [Float(8), Float(8)].withUnsafeBytes { uniforms.replaceSubrange(
                field.offset..<(field.offset + 8), with: $0) }
        }
        let buffer = uniforms.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)!
        }
        let sampler = device.makeSamplerState(descriptor: MTLSamplerDescriptor())!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let command = device.makeCommandQueue()!.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: program.uniformBufferIndex)
        encoder.setFragmentBuffer(buffer, offset: 0, index: program.uniformBufferIndex)
        for binding in program.textureBindings {
            let texture = binding.slot == 3 ? background : primary
            encoder.setVertexTexture(texture, index: binding.slot)
            encoder.setFragmentTexture(texture, index: binding.slot)
            encoder.setVertexSamplerState(sampler, index: binding.slot)
            encoder.setFragmentSamplerState(sampler, index: binding.slot)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            throw NSError(domain: "background-color-GPU", code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(describing: command.error)])
        }
        var values = [Float](repeating: 0, count: 4)
        values.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 16,
            from: MTLRegionMake2D(3, 3, 1, 1), mipmapLevel: 0) }
        return values
    }

    static func main() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { print("{}"); return }
        let result = ["source-default": try evaluate("source-default"),
            "opaque-output": try evaluate("opaque-output", opaque: true),
            "author-override": try evaluate("author-override", override: true),
            "data-default": try evaluate("data-default", mode: "rgbmask"),
            "unknown-target": try evaluate("unknown-target", defaultName: "_rt_Unknown")]
        print(String(data: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


def hashes(paths: list[Path]) -> dict[str, str]:
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


class SceneBackgroundGenericColorABITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-background-color-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        app = compiler_bundle(root).rename(root / "Probe.app")
        plist = app / "Contents/Info.plist"
        identity = plistlib.loads(plist.read_bytes())
        identity.update(CFBundlePackageType="APPL", CFBundleExecutable="Probe")
        plist.write_bytes(plistlib.dumps(identity))
        (app / "Contents/MacOS").mkdir()
        binary = app / "Contents/MacOS/Probe"
        support, harness = root / "Support.swift", root / "Harness.swift"
        support.write_text(FIXTURE["SUPPORT"])
        harness.write_text(HARNESS)
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        before = hashes(SOURCES + [support, harness])
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            str(support), *map(str, SOURCES), str(harness), "-framework", "Metal",
            "-framework", "CoreGraphics", "-framework", "ImageIO", "-framework", "Security",
            "-module-cache-path", str(root / "modules"), "-o", str(binary)]
        compiled = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
                                  capture_output=True, text=True, timeout=240)
        evidence_raw = os.environ.get("MWX_BACKGROUND_COLOR_EVIDENCE")
        evidence = Path(evidence_raw) if evidence_raw else None
        if evidence:
            evidence.mkdir(parents=True, exist_ok=True)
            (evidence / "compile.json").write_text(json.dumps({"command": command,
                "returncode": compiled.returncode, "stderr": compiled.stderr,
                "before": before, "after": hashes(SOURCES + [support, harness])}, indent=2) + "\n")
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        cls.results = {}
        for route in ("prefer-generic", "disable-generic"):
            cache = root / route
            cache.mkdir()
            requests = cache / "requests"
            requests.mkdir()
            environment.update(MWX_SCENE_GENERIC_SHADER_ROUTE=route,
                               MWX_SCENE_GENERIC_SHADER_CACHE=str(cache),
                               MWX_SCENE_GENERIC_SHADER_REQUESTS=str(requests))
            environment.pop("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", None)
            if route == "disable-generic":
                environment["MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES"] = "ordinary-shader=disable-generic"
            completed = subprocess.run([str(binary)], cwd=REPOSITORY_ROOT, env=environment,
                                       capture_output=True, text=True, timeout=120)
            if evidence:
                (evidence / f"{route}.log").write_text(completed.stderr)
                (evidence / f"{route}.json").write_text(completed.stdout)
                (evidence / f"{route}-requests.json").write_text(json.dumps([
                    json.loads(path.read_text()) for path in sorted(requests.glob("*.json"))
                ], indent=2) + "\n")
            if completed.returncode:
                raise RuntimeError(completed.stderr or completed.stdout)
            cls.results[route] = json.loads(completed.stdout)
        if before != hashes(SOURCES + [support, harness]):
            raise RuntimeError("Production inputs changed during the background ABI gate")
        if not all(cls.results.values()):
            raise unittest.SkipTest("Metal unavailable; no background ABI/GPU evidence")

    def test_default_background_fact_reaches_both_compilers(self) -> None:
        for route, name, backend in (
            ("prefer-generic", "source-default", "genericCompilerArtifact"),
            ("disable-generic", "opaque-output", "boundedSwift"),
        ):
            with self.subTest(route=route, name=name):
                result = self.results[route][name]
                self.assertTrue(result["ready"], result)
                self.assertTrue(result["variants"], result)
                for variant in result["variants"]:
                    self.assertEqual(variant["backend"], backend, variant)
                    self.assertEqual(variant["pmaSlots"], [3], variant)
        # Input facts do not admit an unproved output on the bounded route.
        bounded_unclassified = self.results["disable-generic"]["source-default"]
        self.assertEqual(bounded_unclassified["variants"], [])
        self.assertIn("colorContractUnproven", bounded_unclassified["launch"])

    def test_background_is_unpremultiplied_once_at_the_author_boundary(self) -> None:
        expected = [value * math.sqrt(0.5) for value in (0.32, 0.36, 0.22)] + [math.sqrt(0.5)]
        for route, name, wanted in (
            ("prefer-generic", "source-default", expected),
            ("disable-generic", "opaque-output", [0.2, 0.3, 0.19, 1.0]),
        ):
            for variant in self.results[route][name]["variants"]:
                with self.subTest(route=route):
                    for observed, value in zip(variant["pixels"], wanted, strict=True):
                        self.assertAlmostEqual(observed, value, delta=0.00003)

    def test_overrides_data_and_unknown_targets_do_not_gain_background_color_authority(self) -> None:
        for route, results in self.results.items():
            with self.subTest(route=route):
                self.assertTrue(results["unknown-target"]["launch"].startswith("failure("))
                self.assertEqual(results["unknown-target"]["variants"], [])
                for name in ("author-override", "data-default"):
                    if route == "prefer-generic":
                        self.assertTrue(results[name]["variants"], results[name])
                    else:
                        self.assertTrue(results[name]["launch"].startswith("failure("))
                    for variant in results[name]["variants"]:
                        self.assertNotIn(3, variant["pmaSlots"], variant)


if __name__ == "__main__":
    unittest.main()
