#!/usr/bin/env python3

"""Authored texture coordinates through the real bounded Program/Metal path."""

from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_resolved_material_pass_encoder import (
    REPOSITORY_ROOT,
    SCENE_ROOT,
    SUPPORT as PASS_ENCODER_SUPPORT,
    SWIFT_SOURCES as PASS_ENCODER_SOURCES,
)


SUPPORT = PASS_ENCODER_SUPPORT.replace(
    """nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored, userProperty, timeline, sceneScript
}

""",
    "",
)

EXTRA_SOURCES = [
    SCENE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift",
    SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialHostUniformSchema.swift",
    SCENE_ROOT / "Rendering/Bindings/SceneResolvedMaterialUniformEncoder.swift",
]
SWIFT_SOURCES = list(dict.fromkeys([*PASS_ENCODER_SOURCES, *EXTRA_SOURCES]))


COORDINATE_HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

private typealias Program = SceneResolvedMaterialProgram
private typealias Graph = SceneAuthoredEffectRenderPlan

private struct CoordinateFixture {
    let name: String
    let vertex: String
    let fragment: String
    let slot: Int
}

private let point = "vec2(0.0891089141368866, 0.6699029207229614)"
private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private func fixture(
    _ name: String, output: String, slot: Int = 1, vertexSource: String = vertex,
    helper: String = ""
) -> CoordinateFixture {
    .init(name: name, vertex: vertexSource, fragment: """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture\(slot);
    \(helper)
    void main() { \(output) }
    """, slot: slot)
}

private let coordinateFixtures = [
    fixture("literal", output: "gl_FragColor = texSample2D(g_Texture1, \(point));"),
    fixture("explicit", output: """
        vec2 mapped = vec2(0.125) + 0.25 * \(point);
        gl_FragColor = texSample2D(g_Texture1, mapped);
        """),
    fixture("mixed", output: """
        vec4 raw = texSample2D(g_Texture1, \(point));
        vec2 mapped = vec2(0.125) + 0.25 * \(point);
        vec4 authored = texSample2D(g_Texture1, mapped);
        gl_FragColor = vec4(raw.r, authored.g, authored.b, 1.0);
        """),
    fixture("varying", output: "gl_FragColor = texSample2D(g_Texture1, v_TexCoord);",
        vertexSource: vertex.replacingOccurrences(of: "v_TexCoord = a_TexCoord;",
            with: "v_TexCoord = \(point);")),
    fixture("vertex-explicit", output: "gl_FragColor = texSample2D(g_Texture1, v_TexCoord);",
        vertexSource: vertex.replacingOccurrences(of: "v_TexCoord = a_TexCoord;",
            with: "v_TexCoord = vec2(0.125) + 0.25 * \(point);")),
    fixture("helper-explicit", output: "gl_FragColor = texSample2D(g_Texture1, ownMap(\(point)));", helper: """
        vec2 ownMap(vec2 arbitraryName) {
            return vec2(0.125) + 0.25 * arbitraryName;
        }
        """),
    fixture("lod-zero", output: "vec4 c = texSample2DLod(g_Texture1, \(point), 0.0); gl_FragColor = vec4(c.rgb, 1.0);"),
    fixture("lod-one", output: "vec4 c = texSample2DLod(g_Texture1, \(point), 1.0); gl_FragColor = vec4(c.rgb, 1.0);"),
    fixture("texture-lod-one", output: "vec4 c = texture2DLod(g_Texture1, \(point), 1.0); gl_FragColor = vec4(c.rgb, 1.0);"),
    fixture("slot-zero", output: "gl_FragColor = texSample2D(g_Texture0, \(point));", slot: 0),
    fixture("slot-seven", output: "gl_FragColor = texSample2D(g_Texture7, \(point));", slot: 7),
]

private func prepared(_ fixture: CoordinateFixture) -> SceneShaderPreparedProgram {
    func stage(_ kind: SceneShaderContract.StageKind, _ source: String) -> SceneShaderPreparedSource {
        let digest = SceneGenericShaderProgramArtifact.sha256(Data(source.utf8))
        return .init(
            frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion,
            sourceDialect: .wallpaperEngineGLSLLike, backend: .mwxMetal, stage: kind,
            rootRelativePath: "self-authored/\(fixture.name)/\(kind.rawValue).shader",
            source: source, sourceMap: [], activeAnnotations: [], activeDeclarations: [],
            dependencies: [], dependencySHA256: digest, variantSHA256: digest,
            preparedSHA256: digest
        )
    }
    return .init(vertex: stage(.vertex, fixture.vertex),
        fragment: stage(.fragment, fixture.fragment),
        colorContract: .unresolvedAuthoredPass, cacheKey: "own-\(fixture.name)")
}

private func texture(_ device: MTLDevice, redOffset: UInt8 = 0) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 384, height: 192, mipmapped: true)
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let value = device.makeTexture(descriptor: descriptor)!
    for level in 0..<value.mipmapLevelCount {
        let width = max(1, 384 >> level), height = max(1, 192 >> level)
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                if level == 0 {
                    let c = x / 24, r = y / 24
                    bytes += [UInt8(16 + 14*c) + redOffset, UInt8(16 + 14*r),
                        UInt8(32 + 7*((c + 3*r) % 24)), 255]
                } else {
                    // Every authored level is initialized; level 1 differs from level 0.
                    bytes += [77 + redOffset, 123, 201, 255]
                }
            }
        }
        bytes.withUnsafeBytes {
            value.replace(region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: level, withBytes: $0.baseAddress!, bytesPerRow: width * 4)
        }
    }
    return value
}

private func target(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: descriptor)!
}

private func selectedSlot(
    index: Int, texture: MTLTexture, transform: SceneTextureUVTransform,
    generation: UInt64
) -> Program.TextureSlot {
    let effect = Graph.EffectKey(layerID: 42, effectIndex: 1, descriptorID: "own-atlas")
    let identity = Graph.TextureIdentity(kind: .framebuffer, layerID: 42,
        effect: effect, name: "own-atlas")
    let candidate = SceneTextureCandidate(
        texture: texture, identity: .provider(.video(layerID: 42, lifecycleEpoch: 1)),
        generation: .provider(contentGeneration: generation), purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)),
        physicalSize: CGSize(width: 384, height: 192),
        mappedSize: CGSize(width: 384, height: 192), uvTransform: transform,
        sampling: .init(texFlags: 3))
    return .init(index: index, reference: .graph(identity), registryIdentity: .graph(identity),
        diagnosticSelectionProvenance: .authored(.explicitBinding),
        expectedPurpose: .premultipliedColor,
        resource: .init(publication: .init(requestIdentity: .graph(identity),
            candidate: candidate, contentGeneration: generation),
            resourceGeneration: generation))
}

private func inputs(index: Int, generation: UInt64) -> SceneAuthoredShaderUniformInputs {
    .init(frameIndex: generation, renderSize: CGSize(width: 2, height: 2),
        screenSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        sceneTime: Float(generation), dayTime: 0, frameTime: 1 / 60,
        pointerCurrentNDC: .zero, pointerPreviousNDC: .zero,
        texturePhysicalSizes: [index: CGSize(width: 384, height: 192)])
}

private func assembly(
    fixture: CoordinateFixture, frontend: SceneAuthoredShaderProgram,
    selected: Program.TextureSlot, generation: UInt64
) -> Program.AssemblyInput? {
    var slots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    slots[fixture.slot] = selected
    var resolved: [Program.ResolvedUniform] = []
    for field in frontend.uniformLayout.fields {
        guard let host = SceneResolvedMaterialUniformEncoder.hostUniform(field, slots: slots),
              let value = SceneResolvedMaterialUniformEncoder.encodeHost(host,
                type: field.type, inputs: inputs(index: fixture.slot, generation: generation),
                slots: slots) else { return nil }
        resolved.append(.init(field: field, source: .host(host), encodedValue: value))
    }
    return .init(preparedShader: prepared(fixture), textureSlots: slots,
        resolvedUniforms: resolved,
        renderState: SceneMaterialRenderState.compile(blending: "normal",
            depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull",
            alphaWriting: nil)!,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .framebuffer, bindings: [.init(slot: fixture.slot, texture: .framebuffer)]))
}

private func render(
    _ program: Program, encoder: SceneResolvedMaterialPassEncoder,
    queue: MTLCommandQueue, device: MTLDevice
) throws -> [String: Any] {
    let output = target(device)
    guard let pass = encoder.prepare(program: program, target: output),
          let command = queue.makeCommandBuffer(),
          encoder.encode(pass, commandBuffer: command) else {
        throw NSError(domain: "pass-encode", code: 1)
    }
    command.commit()
    command.waitUntilCompleted()
    let completed = command.status == .completed && command.error == nil
    var pixels = [UInt8](repeating: 0, count: 16)
    if completed {
        pixels.withUnsafeMutableBytes {
            output.getBytes($0.baseAddress!, bytesPerRow: 8,
                from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
        }
    }
    return ["completed": completed, "pixels": pixels,
        "pipelineAttempts": encoder.pipelineCompilationAttemptCount]
}

private func runCoordinates(
    generic: Bool, frontend: (CoordinateFixture) throws -> SceneAuthoredShaderProgram
) throws -> [String: Any] {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
          let encoder = SceneResolvedMaterialPassEncoder(device: device) else {
        return ["metalAvailable": false]
    }
    let original = texture(device), replacement = texture(device, redOffset: 7)
    let transforms = [SceneTextureUVTransform.identity,
        SceneTextureUVTransform(origin: SIMD2(0.125, 0.125),
            xAxis: SIMD2(0.25, 0), yAxis: SIMD2(0, 0.25)),
        SceneTextureUVTransform.identity]
    var results: [String: Any] = [:]
    for fixture in coordinateFixtures {
        let compiled = try frontend(fixture)
        var frames: [[String: Any]] = []
        var previous: Program?
        for (index, transform) in transforms.enumerated() {
            let generation = UInt64(index + 1)
            let selected = selectedSlot(index: fixture.slot,
                texture: index == 2 ? replacement : original,
                transform: transform, generation: generation)
            guard let input = assembly(fixture: fixture, frontend: compiled,
                    selected: selected, generation: generation) else {
                throw NSError(domain: "assembly-input-\(fixture.name)", code: index)
            }
            let program = generic ? Program.assembleCompiled(input, frontend: compiled,
                routeDecision: .init(profile: "ordinary-shader", state: "prefer-generic",
                    fallbackOwner: "bounded-frontend"),
                conditionalGeneratedRGBInputContract: nil) : Program.assemble(input)
            guard let program else {
                throw NSError(domain: "program-\(fixture.name)", code: index,
                    userInfo: [NSLocalizedDescriptionKey: "transfer=\(compiled.colorTransfer)"])
            }
            var frame = try render(program, encoder: encoder, queue: queue, device: device)
            frame["generation"] = generation
            frame["exactIdentityChanged"] = previous.map {
                $0.exactIdentity != program.exactIdentity
            } ?? true
            frame["resourceGeneration"] = selected.resource.resourceGeneration
            frames.append(frame)
            previous = program
        }
        results[fixture.name] = ["slot": fixture.slot,
            "backend": String(describing: compiled.backend),
            "physicalSize": [384, 192],
            "vertexSHA256": SceneGenericShaderProgramArtifact.sha256(Data(fixture.vertex.utf8)),
            "fragmentSHA256": SceneGenericShaderProgramArtifact.sha256(Data(fixture.fragment.utf8)),
            "metalSHA256": SceneGenericShaderProgramArtifact.sha256(Data(compiled.metalSource.utf8)),
            "frames": frames]
    }
    return ["metalAvailable": true, "device": device.name, "fixtures": results]
}
'''

HARNESS = COORDINATE_HARNESS + r'''
@main private enum Main {
    static func main() throws {
        let result = try runCoordinates(generic: false) { fixture in
            let compiled = SceneAuthoredShaderFrontend.compile(
                vertexSource: fixture.vertex, fragmentSource: fixture.fragment)
            guard let frontend = compiled.program else {
                throw NSError(domain: "bounded-\(fixture.name)", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: String(describing: compiled.diagnostics)])
            }
            return frontend
        }
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
'''


def source_hashes(paths: list[Path]) -> dict[str, str]:
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def fixture_environment(root: Path) -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        CLANG_MODULE_CACHE_PATH=str(root / "clang-cache"),
        SWIFT_MODULECACHE_PATH=str(root / "swift-cache"),
        MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "program-cache"),
    )
    return environment


def preserve_evidence(
    root: Path, name: str, before: dict[str, str], after: dict[str, str],
    command: list[str], compile_result: subprocess.CompletedProcess[str],
    completed: subprocess.CompletedProcess[str],
) -> None:
    destination = os.environ.get("MWX_SCENE_COORDINATE_EVIDENCE")
    if not destination:
        return
    output = Path(destination) / name
    output.mkdir(parents=True, exist_ok=False)
    for path in root.iterdir():
        if path.is_file():
            shutil.copy2(path, output / path.name)
        elif path.name in ("artifacts", "Compiler.bundle"):
            shutil.copytree(path, output / path.name)
    (output / "identity.json").write_text(json.dumps({
        "command": command, "inputHashesBefore": before, "inputHashesAfter": after,
        "sameInputs": before == after, "compileExit": compile_result.returncode,
        "runExit": completed.returncode,
        "outputHashes": source_hashes([path for path in output.rglob("*") if path.is_file()]),
    }, indent=2), encoding="utf-8")
    (output / "compile.stderr").write_text(compile_result.stderr, encoding="utf-8")
    (output / "result.json").write_text(completed.stdout, encoding="utf-8")
    (output / "run.stderr").write_text(completed.stderr, encoding="utf-8")


def assert_coordinate_pixels(test: unittest.TestCase, result: dict, backend: str) -> None:
    # Independent fixed oracle for the self-authored nearest-sampled atlas.
    expected = {
        "literal": [30, 86, 144, 255], "explicit": [44, 44, 88, 255],
        "mixed": [30, 44, 88, 255], "varying": [30, 86, 144, 255],
        "vertex-explicit": [44, 44, 88, 255], "helper-explicit": [44, 44, 88, 255],
        "lod-zero": [30, 86, 144, 255], "lod-one": [77, 123, 201, 255],
        "texture-lod-one": [77, 123, 201, 255],
        "slot-zero": [30, 86, 144, 255], "slot-seven": [30, 86, 144, 255],
    }
    test.assertEqual(set(result["fixtures"]), set(expected), result)
    for name, pixel in expected.items():
        with test.subTest(fixture=name):
            fixture = result["fixtures"][name]
            test.assertEqual(fixture["backend"], backend)
            test.assertEqual(fixture["physicalSize"], [384, 192])
            test.assertEqual(fixture["slot"], {"slot-zero": 0, "slot-seven": 7}.get(name, 1))
            test.assertEqual(len(fixture["frames"]), 3)
            for index, frame in enumerate(fixture["frames"]):
                test.assertTrue(frame["completed"], frame)
                test.assertTrue(frame["exactIdentityChanged"], frame)
                test.assertEqual(frame["generation"], index + 1)
                test.assertEqual(frame["resourceGeneration"], index + 1)
                rgba = pixel.copy()
                if index == 2:
                    rgba[0] += 7
                test.assertEqual(frame["pixels"], rgba * 4, (name, index, frame))
            test.assertEqual(len({f["pipelineAttempts"] for f in fixture["frames"]}), 1, fixture)


class SceneMaterialTextureTransformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-authored-coordinate-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        root = Path(cls.temporary_directory.name)
        support, harness, binary = root / "Support.swift", root / "Harness.swift", root / "probe"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        before = source_hashes([*SWIFT_SOURCES, support, harness])
        command = [
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            str(support), *map(str, SWIFT_SOURCES), str(harness),
            "-framework", "Metal", "-framework", "CoreGraphics",
            "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
        ]
        environment = fixture_environment(root)
        compilation = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True, timeout=180)
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary)], cwd=root, env=environment,
            capture_output=True, text=True, timeout=90)
        after = source_hashes([*SWIFT_SOURCES, support, harness])
        preserve_evidence(root, "bounded", before, after, command, compilation, completed)
        if before != after:
            raise RuntimeError("Compilation inputs changed during the coordinate gate")
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable; no coordinate behavior evidence")

    def test_authored_coordinates_survive_metadata_and_next_generation_on_gpu(self) -> None:
        assert_coordinate_pixels(self, self.result, "boundedSwift")


if __name__ == "__main__":
    unittest.main()
