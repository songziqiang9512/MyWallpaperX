#!/usr/bin/env python3
"""Fragment derivative aliases through the production compiler and Metal."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
from scene_swift_source_sets import scene_swift_sources
from script.tests.test_scene_generic_shader_texture_transform_compiler import compiler_bundle

SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = list(dict.fromkeys([
    *scene_swift_sources("authored_shader_frontend_core"),
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialGenericShaderRequest.swift",
]))
VERTEX = """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord; }
"""

HARNESS = r'''
import Foundation
import Metal

@main private enum DerivativeAliasHarness {
    static func main() throws {
        let arguments = CommandLine.arguments
        let input = try JSONSerialization.jsonObject(with:
            Data(contentsOf: URL(fileURLWithPath: arguments[1]))) as! [String: Any]
        let vertex = input["vertex"] as! String
        let fragment = input["fragment"] as! String
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex, fragmentSource: fragment)
        var output: [String: Any] = [
            "boundedDiagnostics": bounded.diagnostics.map { $0.code.rawValue },
        ]
        if let program = bounded.program {
            output["boundedMetal"] = program.metalSource
            output["boundedMetalError"] = metalError(program)
            if input["render"] as? Bool == true, metalError(program).isEmpty {
                output["boundedPixels"] = try render(program)
            }
        }
        if case let .success(pair) = SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertex, fragmentSource: fragment,
            maximumStageSourceBytes: 512 * 1024) {
            output["normalizedVertex"] = pair.vertex
            output["normalizedFragment"] = pair.fragment
        }
        let key = SceneResolvedMaterialGenericShaderRequest.key(
            vertexSource: vertex, fragmentSource: fragment,
            outputSemantics: .color, expectedColorTransfer: nil,
            premultipliedColorInputSlots: [])
        try FileManager.default.createDirectory(
            atPath: arguments[3], withIntermediateDirectories: true)
        switch SceneGenericShaderCompiler.compile(
            requestKey: key, vertexSource: vertex, fragmentSource: fragment,
            cacheRoot: URL(fileURLWithPath: arguments[3]), bundle: Bundle(path: arguments[2])!) {
        case let .failure(failure): output["genericFailure"] = String(describing: failure)
        case let .success(url):
            let data = try Data(contentsOf: url)
            let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self, from: data)
            output["artifactSHA256"] = SceneGenericShaderProgramArtifact.sha256(data)
            output["genericMetal"] = artifact.program.metalSource
            guard let program = artifact.makeProgram(expectedKey: key,
                expectedColorTransfer: bounded.program?.colorTransfer ?? .unresolved,
                expectedFragmentOutputChannelUse: bounded.program?.fragmentOutputChannelUse ?? .unproven)
            else { output["genericPublicationRejected"] = true; break }
            output["genericMetalError"] = metalError(program)
            if input["render"] as? Bool == true, metalError(program).isEmpty {
                output["genericPixels"] = try render(program)
            }
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]))
    }

    private static func metalError(_ program: SceneAuthoredShaderProgram) -> String {
        guard let device = MTLCreateSystemDefaultDevice() else { return "no Metal device" }
        do { _ = try device.makeLibrary(source: program.metalSource, options: nil); return "" }
        catch { return String(describing: error) }
    }

    private static func render(_ program: SceneAuthoredShaderProgram) throws -> [Float] {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try device.makeLibrary(source: program.metalSource, options: nil)
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: program.vertexFunctionName)
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: program.fragmentFunctionName)
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 8, height: 8, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let output = device.makeTexture(descriptor: descriptor)!
        descriptor.width = 1
        descriptor.height = 1
        let source = device.makeTexture(descriptor: descriptor)!
        var white: [Float] = [1, 1, 1, 1]
        white.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 16) }
        let sampler = device.makeSamplerState(descriptor: MTLSamplerDescriptor())!
        var uniforms = Data(count: max(16, program.uniformLayout.byteSize))
        for field in program.uniformLayout.fields where field.authoredName == "mwxRenderSize" {
            [Float(8), Float(8)].withUnsafeBytes { values in
                uniforms.replaceSubrange(field.offset..<(field.offset + 8), with: values)
            }
        }
        let buffer = uniforms.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)!
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let command = device.makeCommandQueue()!.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: program.uniformBufferIndex)
        encoder.setFragmentBuffer(buffer, offset: 0, index: program.uniformBufferIndex)
        for texture in program.textureBindings {
            encoder.setVertexTexture(source, index: texture.slot)
            encoder.setFragmentTexture(source, index: texture.slot)
            encoder.setVertexSamplerState(sampler, index: texture.slot)
            encoder.setFragmentSamplerState(sampler, index: texture.slot)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            throw NSError(domain: "derivative-GPU-completion", code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(describing: command.error)])
        }
        var values = [Float](repeating: 0, count: 4)
        values.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 16,
            from: MTLRegionMake2D(3, 3, 1, 1), mipmapLevel: 0) }
        return values
    }
}
'''


def fragment(body: str, helpers: str = "") -> str:
    return ("uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n" + helpers
            + "\nvoid main() {\nvec4 pix = texSample2D(g_Texture0, v_TexCoord);\n"
            + body + "\n}\n")


class SceneShaderDerivativeAliasTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-derivative-alias-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.bundle = compiler_bundle(cls.root)
        cls.binary = cls.root / "probe"
        harness = cls.root / "Harness.swift"
        harness.write_text(HARNESS)
        cls.evidence = Path(os.environ["MWX_DERIVATIVE_EVIDENCE"]) if os.environ.get(
            "MWX_DERIVATIVE_EVIDENCE") else None
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(cls.root / "clang-cache")
        command = ["xcrun", "swiftc", *(str(p) for p in SOURCES), str(harness),
                   "-module-cache-path", str(cls.root / "swift-cache"), "-o", str(cls.binary)]
        completed = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
                                   capture_output=True, text=True, timeout=180)
        if cls.evidence:
            cls.evidence.mkdir(parents=True, exist_ok=True)
            (cls.evidence / "build.json").write_text(json.dumps({
                "command": command, "returncode": completed.returncode,
                "stderr": completed.stderr,
                "harnessSHA256": hashlib.sha256(HARNESS.encode()).hexdigest(),
                "sources": {str(p.relative_to(REPOSITORY_ROOT)): hashlib.sha256(
                    p.read_bytes()).hexdigest() for p in SOURCES},
            }, indent=2) + "\n")
        if completed.returncode:
            raise RuntimeError(completed.stderr)

    def compile(self, body: str, *, helpers: str = "", vertex: str = VERTEX,
                render: bool = False) -> dict:
        request = {"vertex": vertex, "fragment": fragment(body, helpers), "render": render}
        key = hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()
        path = self.root / f"{key}.json"
        path.write_text(json.dumps(request))
        completed = subprocess.run([str(self.binary), str(path), str(self.bundle),
                                    str(self.root / "artifacts")], cwd=REPOSITORY_ROOT,
                                   capture_output=True, text=True, timeout=90)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        output = json.loads(completed.stdout)
        if self.evidence:
            (self.evidence / f"{key}.input.json").write_text(json.dumps(request, indent=2))
            (self.evidence / f"{key}.result.json").write_text(json.dumps(output, indent=2))
        return output

    def assert_compiles(self, result: dict) -> None:
        self.assertEqual(result["boundedDiagnostics"], [], result)
        self.assertEqual(result.get("boundedMetalError"), "", result)
        self.assertNotIn("genericFailure", result)
        self.assertNotIn("genericPublicationRejected", result)
        self.assertEqual(result.get("genericMetalError"), "", result)

    def test_scalar_and_vector_fragment_derivatives_execute(self) -> None:
        result = self.compile("""float d = v_TexCoord.x;
float px = abs(ddx(d)) + abs(ddy(d));
vec2 gradient = abs(ddx(v_TexCoord)) + abs(ddy(v_TexCoord));
gl_FragColor = vec4(px, gradient.y, gradient.x + gradient.y, pix.a);""", render=True)
        self.assert_compiles(result)
        for backend in ("bounded", "generic"):
            for actual, expected in zip(result[f"{backend}Pixels"], [.125, .125, .25, 1]):
                self.assertAlmostEqual(actual, expected, delta=1e-5, msg=f"{backend}: {result}")

    def test_authored_functions_and_same_name_variables_are_preserved(self) -> None:
        result = self.compile("""float value = ddx(v_TexCoord.x) + ddy(v_TexCoord.y);
gl_FragColor = vec4(pix.rgb * value, pix.a);""",
            helpers="float ddx(float value) { return value; }\n"
                    "float ddy(float value) { return value; }")
        self.assert_compiles(result)
        self.assertIn("float ddx(float value)", result["normalizedFragment"])
        self.assertNotIn("dFdx", result["normalizedFragment"])
        self.assertIn("mwxF_ddx", result["boundedMetal"])
        variable = self.compile("""float ddx = 0.25; float ddy = 0.5;
gl_FragColor = vec4(pix.rgb * (ddx + ddy), pix.a);""")
        self.assert_compiles(variable)
        self.assertIn("float ddx =", variable["normalizedFragment"])
        self.assertNotIn("dfdx", variable["boundedMetal"])
        for declaration in ("float ddx = 0.25;", "float anchor = 0.0, ddx = 0.25;",
                            "float anchor, ddx;", "float values[1], ddx;"):
            with self.subTest(declaration=declaration):
                shadowed = self.compile(declaration +
                    "\ngl_FragColor = vec4(pix.rgb * ddx(v_TexCoord.x), pix.a);")
                self.assertTrue(shadowed["boundedDiagnostics"] or
                                shadowed.get("boundedMetalError"), shadowed)
                self.assertIn("genericFailure", shadowed)

    def test_calls_in_helpers_and_per_name_overrides(self) -> None:
        result = self.compile("""float value = derivative(v_TexCoord.x);
gl_FragColor = vec4(pix.rgb * value, pix.a);""",
            helpers="// float ddx(float value) { fake definition }\n"
                    "float derivative(float value) { return abs(ddx(value)); }")
        self.assert_compiles(result)
        self.assertIn("return abs(dFdx(value))", result["normalizedFragment"])
        self.assertIn("// float ddx(float value)", result["normalizedFragment"])
        mixed = self.compile("""float value = ddx(v_TexCoord.x) + abs(ddy(v_TexCoord.y));
gl_FragColor = vec4(pix.rgb * value, pix.a);""",
            helpers="float ddx(float value) { return value; }")
        self.assert_compiles(mixed)
        self.assertIn("dFdy", mixed["normalizedFragment"])
        self.assertNotIn("dFdx", mixed["normalizedFragment"])

    def test_invalid_calls_are_not_repaired(self) -> None:
        macro = self.compile("gl_FragColor = vec4(pix.rgb * ddx(v_TexCoord.x), pix.a);",
                             helpers="#define ddx 4")
        self.assertTrue(macro["boundedDiagnostics"] or macro.get("boundedMetalError"), macro)
        self.assertIn("genericFailure", macro)
        prototype = self.compile("gl_FragColor = vec4(pix.rgb * ddx(v_TexCoord.x), pix.a);",
                                 helpers="float ddx(float value);")
        self.assertTrue(prototype["boundedDiagnostics"] or prototype.get("boundedMetalError"), prototype)
        self.assertIn("genericFailure", prototype)
        for call in ("ddx()", "ddy(v_TexCoord.x, v_TexCoord.y)", "v_TexCoord.ddx(1.0)"):
            with self.subTest(call=call):
                result = self.compile(f"gl_FragColor = vec4(pix.rgb * {call}, pix.a);")
                self.assertNotEqual(result.get("boundedMetalError", ""), "", result)
                self.assertIn("genericFailure", result)
                if ".ddx" in call:
                    self.assertIn(".ddx", result["normalizedFragment"])
                    self.assertNotIn(".dFdx", result["normalizedFragment"])

    def test_vertex_derivative_remains_rejected(self) -> None:
        vertex = VERTEX.replace("vec4(a_Position, 1.0)",
                                "vec4(a_Position + vec3(ddx(a_TexCoord.x)), 1.0)")
        result = self.compile("gl_FragColor = pix;", vertex=vertex)
        self.assertIn("ddx", result.get("boundedMetalError", ""), result)
        self.assertIn("genericFailure", result)
        self.assertIn("ddx", result["normalizedVertex"])
        self.assertNotIn("dFdx", result["normalizedVertex"])


if __name__ == "__main__":
    unittest.main()
