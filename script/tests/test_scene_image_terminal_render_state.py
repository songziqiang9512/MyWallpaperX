"""Finite ordinary-plane terminal state through production draw owners.

Depth/cull and additive RGB use the real image PSO and MainPass renderer.
This does not execute the full effect graph, advanced-blend matrix or App.
Compile-only never invokes Metal.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_color_blend_capture_region as shared


ADDITIVE_HARNESS = r'''
extension BlendCaptureProbe {
    static func additiveTerminalStates(_ device: MTLDevice, _ queue: MTLCommandQueue,
                                       _ library: MTLLibrary) -> [String: Any] {
        let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float,
            library: library, preparesDepth: true, preparesAdditive: true)!
        let unprepared = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float,
            library: library, preparesDepth: true)!
        let weighted = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float,
            blendMode: .alphaWeightedAdditive, library: library, preparesAdditive: true)!
        func policy(_ alpha: String? = nil, read: String = "disabled",
                    write: String = "disabled", cull: String = "nocull") -> SceneMaterialRenderState {
            SceneMaterialRenderState.compile(blending: "additive", depthTest: read,
                depthWrite: write, cullMode: cull, alphaWriting: alpha)!
        }
        func texture(_ rgba: SIMD4<Float>) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: 1, height: 1, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .renderTarget]
            let texture = device.makeTexture(descriptor: descriptor)!
            var bytes = (0..<4).map { Float16(rgba[$0]) }
            bytes.withUnsafeMutableBytes { texture.replace(region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
            return texture
        }
        func pixel(_ texture: MTLTexture) -> [Float] {
            var bytes = [Float16](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 8,
                from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0) }
            return bytes.map(Float.init)
        }
        let authored = SIMD3<Float>(1.5, 0.6, 0.25)
        let tint = SIMD3<Float>(0.5, 0.25, 0.75)
        let background = SIMD4<Float>(0.125, 0.25, 0.375, 0.2)
        func draw(_ input: MTLTexture, uniforms: SceneLayerFragmentUniforms,
                  state: SceneMaterialRenderState?, layerState: SceneMaterialRenderState?,
                  selected: SceneImageLayerPipeline) -> [String: Any] {
            let output = texture(background), command = queue.makeCommandBuffer()!
            let pass = SceneMainPassEncoder(commandBuffer: command, target: output,
                clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: false)
            let layer = SceneRenderDescriptor.Layer(id: 9182, colorBlendMode: 0,
                imageMaterialRenderState: layerState)
            let drawn = SceneImageLayerMainPassRenderer.draw(texture: input,
                mvp: simd_float4x4(diagonal: SIMD4(2, 2, 1, 1)), uniforms: uniforms,
                dependencyTexture: nil, layer: layer, pipeline: selected,
                colorBlendPipeline: nil, terminalMaterialState: state, mainPass: pass)
            precondition(pass.finishEnsuringClear())
            command.commit(); command.waitUntilCompleted()
            return ["drawn": drawn, "actual": pixel(output),
                "completed": command.status == .completed && command.error == nil]
        }
        let ordinary = SceneMaterialRenderState.compile(blending: "translucent",
            depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!
        var rows: [[String: Any]] = []
        for alphaWriting: String? in [nil, "default"] {
            let state = policy(alphaWriting)
            for straight in [false, true] {
                for coverage: Float in [0, 0.5, 1] {
                    for opacity: Float in [0, 0.5, 1] {
                        let rgb = authored * (straight ? 1 : coverage)
                        let input = texture(SIMD4(rgb.x, rgb.y, rgb.z, coverage))
                        let original = pixel(input)
                        let uniforms = SceneLayerFragmentUniforms(time: 0, alpha: opacity,
                            dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
                            sourceSampling: SIMD2(0, straight ? 1 : 0),
                            tint: SIMD4(tint.x, tint.y, tint.z, 1),
                            textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
                        let additive = draw(input, uniforms: uniforms, state: state,
                            layerState: state, selected: pipeline)
                        let sourceOver = draw(input, uniforms: uniforms, state: ordinary,
                            layerState: ordinary, selected: pipeline)
                        let defaultBind = draw(input, uniforms: uniforms, state: nil,
                            layerState: nil, selected: pipeline)
                        let contribution = authored * tint * coverage * opacity
                        let alpha = coverage * opacity
                        let expected = [background.x + contribution.x,
                            background.y + contribution.y, background.z + contribution.z,
                            alpha + background.w * (1 - alpha)]
                        let ordinaryRGB = contribution + SIMD3(background.x, background.y, background.z) * (1 - alpha)
                        rows.append(["alphaWriting": alphaWriting ?? "omitted", "straight": straight,
                            "coverage": coverage, "opacity": opacity, "actual": additive["actual"]!,
                            "expected": expected, "sourceOver": sourceOver["actual"]!,
                            "expectedSourceOver": [ordinaryRGB.x, ordinaryRGB.y, ordinaryRGB.z, expected[3]],
                            "defaultBind": defaultBind["actual"]!,
                            "drawn": additive["drawn"] as! Bool && sourceOver["drawn"] as! Bool
                                && defaultBind["drawn"] as! Bool,
                            "completed": additive["completed"] as! Bool && sourceOver["completed"] as! Bool
                                && defaultBind["completed"] as! Bool,
                            "sourceUnchanged": pixel(input) == original])
                    }
                }
            }
        }
        let state = policy()
        let input = texture(SIMD4(0.75, 0.3, 0.125, 0.5))
        let uniforms = SceneLayerFragmentUniforms(time: 0, alpha: 0.5,
            dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
            sourceSampling: .zero, tint: SIMD4(repeating: 1),
            textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
        var boundaries: [String: Bool] = [
            "preparedSupports": pipeline.supports(state),
            "defaultSupports": pipeline.supports(policy("default")),
            "unpreparedRejects": !unprepared.supports(state),
            "weightedRejects": !weighted.supports(state),
            "depthReadRejects": !pipeline.supports(policy(read: "enabled")),
            "depthWriteRejects": !pipeline.supports(policy(write: "enabled")),
            "backCullRejects": !pipeline.supports(policy(cull: "normal")),
            "enabledAlphaRejects": !pipeline.supports(policy("enabled")),
        ]
        for (name, layerState, selected) in [
            ("mismatchedState", Optional(ordinary), pipeline),
            ("absentState", Optional<SceneMaterialRenderState>.none, pipeline),
            ("unpreparedState", Optional(state), unprepared),
        ] {
            let rejected = draw(input, uniforms: uniforms, state: state,
                layerState: layerState, selected: selected)
            boundaries[name] = rejected["drawn"] as? Bool == false
                && rejected["completed"] as? Bool == true
                && rejected["actual"] as? [Float] == pixel(texture(background))
        }
        return ["rows": rows, "boundaries": boundaries]
    }
}
'''


class SceneImageTerminalRenderStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        cls.compile_only = os.environ.get("MWX_IMAGE_TERMINAL_COMPILE_ONLY") == "1"
        require_validation = os.environ.get("MWX_IMAGE_TERMINAL_METAL_VALIDATION") == "1" and not cls.compile_only
        output = Path(os.environ.get("MWX_IMAGE_TERMINAL_EVIDENCE", "/private/tmp/mwx-image-terminal"))
        output.mkdir(parents=True, exist_ok=True)
        paths = [Path(__file__), shared.HARNESS, shared.PROJECTION_SOURCE, *shared.SOURCES,
                 shared.SHADER, shared.FOG, Path(shared.__file__),
                 Path(__file__).with_name("scene_color_blend_capture_test_support.py")]
        identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="terminal-", dir=output) as directory:
            root = Path(directory)
            support, binary = root / "Projection.swift", root / "probe"
            support.write_text(shared.projection_support())
            harness = root / "Terminal.swift"
            harness_source = shared.HARNESS.read_text().replace(
                '"finiteStates": finiteTerminalStates(device, queue, library),',
                '"finiteStates": finiteTerminalStates(device, queue, library), '
                '"additiveStates": additiveTerminalStates(device, queue, library),')
            harness.write_text(harness_source + ADDITIVE_HARNESS)
            commands = [["swiftc", "-DDEBUG", *map(str, shared.SOURCES), str(support),
                         str(harness), "-module-cache-path", str(root / "cache"), "-o", str(binary)]]
            if cls.compile_only:
                commands.append([str(binary), "--compile-only"])
            else:
                air, library = root / "image.air", root / "image.metallib"
                commands += [["xcrun", "--sdk", "macosx", "metal", "-c", str(shared.SHADER), "-o", str(air)],
                             ["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(library)],
                             [str(binary), str(library), "--terminal-finite-only"]]
            outputs, command_logs = [], []
            for command in commands:
                environment = dict(os.environ)
                if require_validation and command[0] == str(binary):
                    environment["MTL_DEBUG_LAYER"] = "1"
                ran = subprocess.run(command, capture_output=True, text=True, timeout=180, env=environment)
                outputs.append(ran.stdout + ran.stderr)
                command_logs.append({"command": command, "exitCode": ran.returncode,
                                     "stdout": ran.stdout, "stderr": ran.stderr})
                (output / "command-log.json").write_text(json.dumps(command_logs, indent=2))
                if ran.returncode:
                    (output / "first-failure.log").write_text("\n".join(outputs))
                    raise AssertionError(ran.stdout + ran.stderr)
            validation_observed = "Metal API Validation Enabled" in outputs[-1]
            (output / "validation.json").write_text(json.dumps({
                "requested": require_validation, "observed": validation_observed,
                "actualMarker": "Metal API Validation Enabled" if validation_observed else None}, indent=2))
            assert not require_validation or validation_observed, "Metal API validation was not observed"
            cls.result = json.loads(ran.stdout)
        assert identity == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, "source identity drift"
        (output / "source-identity.json").write_text(json.dumps(identity, indent=2))
        (output / "report.json").write_text(json.dumps(cls.result, indent=2))
        if cls.result.get("metalUnavailable"):
            raise unittest.SkipTest("Metal unavailable")

    def test_fixture_compiles_without_requiring_gpu_execution(self):
        if self.compile_only:
            self.assertEqual(self.result, {"compiled": True, "gpuExecuted": False})

    def test_finite_terminal_state_pixels_and_failure_boundaries(self):
        if self.compile_only:
            self.skipTest("compile-only: finite GPU semantics not executed")
        rows = self.result["finiteStates"]
        self.assertEqual(len(rows), 11)
        amber, blue, green, black = [0, 128, 255, 255], [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 0, 255]
        for row in rows:
            name = row["name"]
            needs_depth = name not in ("neither", "normal-front-no-depth", "transparent-no-write")
            with self.subTest(name=name):
                self.assertTrue(row["completed"] and row["drawn"] and row["supports"], row)
                self.assertTrue(row["stateMismatchRejected"] and row["wrongPassRejected"] and row["unsupportedPoliciesRejected"], row)
                self.assertTrue(row["overlayDrawn"], row)
                self.assertEqual(row["overlay"], [192, 32, 192, 255], row)
                self.assertEqual(row["baseSupports"], not needs_depth, row)
                self.assertEqual(row["missingRejected"], needs_depth, row)
                self.assertEqual(row["left"], blue if name in ("write-only", "neither", "normal-front-no-depth") else amber, row)
                self.assertEqual(row["right"], black if name in ("normal-back", "transparent-write", "transparent-no-write") else blue, row)
                expected_far = blue if name in ("read-write", "write-only") else black if name == "transparent-write" else green
                self.assertEqual(row["farPeer"], expected_far, row)
        # The existing captured-main role retains read-only behavior, even when
        # a preceding color-only encoder detached the scene depth attachment.
        for row in self.result["terminalDepth"]:
            self.assertTrue(row["completed"] and row["drawn"] and row["missingRejected"], row)
            self.assertEqual(row["left"], amber if row["writer"] else blue, row)
            self.assertEqual(row["right"], blue, row)
            self.assertEqual(row["farPeer"], green, row)

    def test_additive_rgb_uses_single_coverage_and_preserves_ordinary_alpha(self):
        if self.compile_only:
            self.skipTest("compile-only: additive GPU semantics not executed")
        additive = self.result["additiveStates"]
        self.assertTrue(all(additive["boundaries"].values()), additive["boundaries"])
        self.assertEqual(len(additive["rows"]), 36)
        for row in additive["rows"]:
            with self.subTest(alpha=row["alphaWriting"], straight=row["straight"],
                              coverage=row["coverage"], opacity=row["opacity"]):
                self.assertTrue(row["drawn"] and row["completed"] and row["sourceUnchanged"], row)
                for actual, expected in zip(row["actual"], row["expected"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=0.002, msg=row)
                for actual, expected in zip(row["sourceOver"], row["expectedSourceOver"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=0.002, msg=row)
                self.assertEqual(row["actual"][3], row["sourceOver"][3], row)
                self.assertEqual(row["defaultBind"], row["sourceOver"], row)
        for omitted, default in zip(additive["rows"][:18], additive["rows"][18:], strict=True):
            self.assertEqual(omitted["actual"], default["actual"])


if __name__ == "__main__":
    unittest.main()
