"""Read actual image/ColorBlend Metal output for world-distance Fog.

Distance weights are fixed independent vectors, not computed from the product
header. This gate proves shader/binder pixels, not App or official parity.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SHADER = SCENE / "Rendering/Composition/SceneImageLayer.metal"
FOG_HEADER = SHADER.with_name("SceneDistanceFog.metalh")
COLOR_BLEND = SHADER.with_name("SceneLayerColorBlendPipeline.swift")
SOURCES = [SCENE / path for path in (
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Composition/SceneBlendModeShaderSource.swift",
    "Rendering/Composition/SceneFramebufferSnapshot.swift",
    "Resources/Textures/SceneResourceBudget.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
    "Diagnostics/SceneGPUCensus.swift",
)]


def vectors():
    def row(name, *, density=0.25, interval=(0, 2, 0, 1), origin=(0, 0, 1),
            basis_x=(0, 0, 0), basis_y=(0, 0, 0), sample=(1, 1), **options):
        return dict(name=name, density=density, fogRange=list(interval),
                    origin=list(origin), basisX=list(basis_x), basisY=list(basis_y),
                    sample=list(sample), source=[0.5, 0.25, 0.75], fogColor=[0.125, 0.5, 0.25],
                    coverage=1, opacity=1, vertexCoverage=1, clipCoverage=1,
                    straight=False, enabled=True, **options)

    distance = [
        row("quarter-distance", density=0.0625, interval=(0, 4, 0, 1)),
        row("half-distance"),
        row("three-quarter-distance", density=0.5625, interval=(0, 4 / 3, 0, 1)),
        row("shifted-distance-interval", interval=(0.5, 1.5, 0, 1)),
        row("before-near-endpoint", density=0.2, interval=(2, 4, 0.2, 0.8)),
        row("after-far-endpoint", density=0.8, interval=(0, 0.5, 0.2, 0.8)),
        row("linear-density-endpoints", density=0.35, interval=(0, 2, 0.2, 0.8)),
        row("radial-off-axis", density=0.5, origin=(1, 0, 1)),
        # At this 3x3 pixel center the independent local coordinates are
        # (1/3, 1/3): the full basis yields (2, 1, 1), distance squared 6.
        row("nonuniform-basis", density=0.375, interval=(0, 4, 0, 1),
            basis_x=(6, 0, 0), basis_y=(0, 3, 0), sample=(2, 0)),
        row("rotated-nonuniform-basis", density=0.375, interval=(0, 4, 0, 1),
            basis_x=(0, 6, 0), basis_y=(-3, 0, 0), sample=(2, 0)),
        # The tilted basis produces (2, 0, 2), distance squared 8.
        row("tilted-world-basis", density=0.5, interval=(0, 4, 0, 1),
            basis_x=(6, 0, 0), basis_y=(0, 0, 3), sample=(2, 0)),
    ]
    coverage = []
    for straight in (False, True):
        for additive in (False, True):
            for alpha in (0, 0.5, 1):
                for weight in (1, 0.125):
                    entry = row(f"coverage-{straight}-{additive}-{alpha}-{weight}")
                    entry.update(straight=straight, additive=additive, coverage=alpha, opacity=weight,
                                 vertexCoverage=0.5, clipCoverage=0.5)
                    coverage.append(entry)
        disabled = row(f"disabled-{straight}", density=0)
        disabled.update(straight=straight, enabled=False, coverage=0.5, opacity=0.25)
        coverage.append(disabled)
        raw = row(f"raw-capture-default-{straight}", density=0)
        raw.update(straight=straight, enabled=False, rawCapture=True,
                   coverage=0.5, opacity=0.25, vertexCoverage=0.5, clipCoverage=0.5)
        coverage.append(raw)
    screen = []
    for straight in (False, True):
        entry = row(f"screen-after-blend-{straight}", density=0.5, interval=(0, 2, 0.5, 0.5))
        # Official controlled alpha=1 result: 128 source / 64 background /
        # black Fog .5 -> 80, distinguishing Fog-after-blend from 112 before.
        # Exact binary-rational inputs use the corresponding 5/16 output.
        entry.update(straight=straight, source=[0.5, 0.5, 0.5], fogColor=[0, 0, 0],
                     blendMode=7, background=[0.25, 0.25, 0.25, 1],
                     expected=[0.3125, 0.3125, 0.3125, 1])
        screen.append(entry)
        partial = dict(entry, name=f"screen-after-alpha-half-{straight}", opacity=0.5,
                       expected=[0.21875, 0.21875, 0.21875, 1])
        # Official layer.alpha=.5 result 56 distinguishes Fog-after-existing
        # alpha composition from Fog-before-final-coverage (72).
        screen.append(partial)
        screen.append(dict(partial, name=f"screen-nonblack-alpha-{straight}",
                           fogColor=[0.125, 0.5, 0.25], background=[0.25, 0.25, 0.25, 0.625],
                           expected=[0.28125, 0.46875, 0.34375, 0.625]))
        screen.append(dict(entry, name=f"screen-disabled-{straight}", enabled=False,
                           expected=[0.625, 0.625, 0.625, 1]))
        screen.append(dict(entry, name=f"screen-default-reset-{straight}", resetFogToDefault=True,
                           expected=[0.625, 0.625, 0.625, 1]))
        # Shape coverage interpolates the Fogged style result over the
        # untouched background. It is distinct from final layer opacity.
        for name, vertex, clip, opacity, rgb in (
            ("zero-vertex", 0, 1, 1, 0.25),
            ("zero-clip", 1, 0, 1, 0.25),
            ("half-vertex", 0.5, 1, 1, 0.28125),
            ("half-clip", 1, 0.5, 1, 0.28125),
            ("quarter-combined", 0.5, 0.5, 1, 0.265625),
            ("half-style-half-shape", 0.5, 1, 0.5, 0.234375),
        ):
            screen.append(dict(entry, name=f"screen-shape-{name}-{straight}",
                               vertexCoverage=vertex, clipCoverage=clip, opacity=opacity,
                               expected=[rgb, rgb, rgb, 1]))
    transformed_screen = row("screen-transformed-basis", density=0.375, interval=(0, 4, 0, 1),
                             basis_x=(0, 6, 0), basis_y=(-3, 0, 0), sample=(2, 0))
    transformed_screen.update(blendMode=7, source=[0.5, 0.5, 0.5], fogColor=[0, 0, 0],
                              background=[0.25, 0.25, 0.25, 0.375],
                              expected=[0.390625, 0.390625, 0.390625, 0.375])
    screen.append(transformed_screen)
    tinted = row("fog-after-tint", expected=[0.21875, 0.171875, 0.484375, 1], tint=[0.5, 0.25, 0.75])
    return distance + coverage + screen + [tinted]


def expected_pixel(row):
    if "expected" in row:
        return row["expected"]
    alpha = row["coverage"] * row["opacity"] * row["vertexCoverage"] * row["clipCoverage"]
    if row.get("rawCapture") and row["straight"]:
        return row["source"] + [alpha]
    density = row["density"]
    # Additive retains its separate authored source-alpha weight. This does
    # not square layer opacity or vertex/clip coverage, or alter alpha.
    rgb_weight = alpha * (row["coverage"] if row.get("additive") else 1)
    rgb = [(source * (1 - density) + fog * density) * rgb_weight
           for source, fog in zip(row["source"], row["fogColor"], strict=True)]
    return rgb + [alpha]


HARNESS = r'''
import Foundation
import Metal
import simd

@main enum FogHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}"); return
        }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float, library: library)!
        let additive = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float,
            blendMode: .alphaWeightedAdditive, library: library)!
        let fogSource = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
        let colorBlend = SceneLayerColorBlendPipeline(device: device,
            state: SceneLayerColorBlendPipelineState(device: device, pixelFormat: .rgba16Float,
                fogShaderSource: fogSource)!)
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String: Any]]
        func scalar(_ row: [String: Any], _ key: String) -> Float {
            Float((row[key] as! NSNumber).doubleValue)
        }
        func vector(_ row: [String: Any], _ key: String) -> SIMD3<Float> {
            let value = row[key] as! [NSNumber]
            return SIMD3(value.map { Float($0.doubleValue) })
        }
        func texture(_ width: Int, _ height: Int, _ value: SIMD4<Float>) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .renderTarget]
            let result = device.makeTexture(descriptor: descriptor)!
            var data = (0..<(width * height)).flatMap { _ in (0..<4).map { Float16(value[$0]) } }
            data.withUnsafeMutableBytes {
                result.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: width * 8)
            }
            return result
        }
        func pixels(_ texture: MTLTexture) -> [Float] {
            var data = [Float16](repeating: 0, count: texture.width * texture.height * 4)
            data.withUnsafeMutableBytes {
                texture.getBytes($0.baseAddress!, bytesPerRow: texture.width * 8,
                    from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            }
            return data.map(Float.init)
        }
        var output: [[String: Any]] = []
        for row in rows {
            let straight = row["straight"] as! Bool
            let raw = row["rawCapture"] as? Bool ?? false
            let coverage = scalar(row, "coverage")
            // ColorBlend consumes a completed material/effect texture: its
            // stored alpha has already received final layer opacity.
            let preparedCoverage = row["blendMode"] == nil ? coverage : coverage * scalar(row, "opacity")
            let color = vector(row, "source") * (straight ? 1 : preparedCoverage)
            let source = texture(1, 1, SIMD4(color, preparedCoverage))
            let original = pixels(source)
            let target = texture(3, 3, .zero)
            // All sampled model coordinates stay within this constant mask;
            // a 1x1 clamp-to-zero mask would fade at off-center probes.
            let mask = texture(8, 8, SIMD4(repeating: scalar(row, "clipCoverage")))
            let command = queue.makeCommandBuffer()!
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .load
            pass.colorAttachments[0].storeAction = .store
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            (row["additive"] as? Bool == true ? additive : pipeline).bind(encoder: encoder)
            var vertices = [SIMD2<Float>(-0.5, -0.5), SIMD2(0.5, -0.5),
                            SIMD2(-0.5, 0.5), SIMD2(0.5, 0.5)].map {
                // Constant UV makes world-distance variation independent of sampling.
                SceneQuadVertex(position: $0, texcoord: SIMD2(0.1, 0.9),
                    vertexCoverage: scalar(row, "vertexCoverage"))
            }
            var mvp = simd_float4x4(diagonal: SIMD4(2, 2, 1, 1))
            var uniforms = SceneLayerFragmentUniforms(time: 0, alpha: scalar(row, "opacity"),
                dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
                sourceSampling: SIMD2(0, straight ? (raw ? 3 : 1) : 0), tint: SIMD4(repeating: 1),
                textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
            if row["tint"] != nil { uniforms.tint = SIMD4(vector(row, "tint"), 1) }
            if row["enabled"] as! Bool {
                let range = row["fogRange"] as! [NSNumber]
                uniforms.distanceFog = SceneImageDistanceFogUniforms(
                    color: SIMD4(vector(row, "fogColor"), 1),
                    range: SIMD4(range.map { Float($0.doubleValue) }),
                    cameraRelativeOrigin: SIMD4(vector(row, "origin"), 0),
                    modelX: SIMD4(vector(row, "basisX"), 0), modelY: SIMD4(vector(row, "basisY"), 0))
            }
            encoder.setVertexBytes(&vertices, length: vertices.count * MemoryLayout<SceneQuadVertex>.stride, index: 0)
            if let mode = row["blendMode"] as? Int {
                let values = row["background"] as! [NSNumber]
                let background = texture(3, 3, SIMD4(values.map { Float($0.doubleValue) }))
                colorBlend.bindGeometry(layerTexture: source, backgroundTexture: background,
                    blendMode: mode, mvp: mvp, sourceIsStraightAlpha: straight,
                    distanceFog: uniforms.distanceFog, encoder: encoder)
                if row["resetFogToDefault"] as? Bool == true {
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    // The second real binder omits Fog, overwriting stale
                    // enabled bytes on this same encoder before the draw.
                    colorBlend.bindGeometry(layerTexture: source, backgroundTexture: background,
                        blendMode: mode, mvp: mvp, sourceIsStraightAlpha: straight, encoder: encoder)
                }
            } else {
                encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneLayerFragmentUniforms>.size, index: 0)
                encoder.setFragmentTexture(source, index: 0); encoder.setFragmentTexture(source, index: 1)
            }
            SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: mask,
                transform: SIMD4(0.5, 0.5, 0.1, 0.1))
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            let sample = row["sample"] as! [Int]
            let offset = (sample[1] * 3 + sample[0]) * 4
            output.append(["name": row["name"]!,
                "completed": command.status == .completed && command.error == nil,
                "sourceUnchanged": pixels(source) == original,
                "actual": Array(pixels(target)[offset..<(offset + 4)])])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": output],
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneImageDistanceFogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        temporary = tempfile.TemporaryDirectory(prefix="mwx-image-distance-fog-")
        cls.addClassCleanup(temporary.cleanup)
        work = Path(temporary.name)
        identity_paths = [Path(__file__), *SOURCES, SHADER, FOG_HEADER, COLOR_BLEND]
        identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in identity_paths}
        (work / SHADER.name).write_bytes(SHADER.read_bytes())
        (work / FOG_HEADER.name).write_bytes(FOG_HEADER.read_bytes())
        (work / "Harness.swift").write_text(HARNESS)
        # Use the real pipeline state/binder; the unrelated high-level renderer
        # requires the full graph and does not belong to this pixel gate.
        (work / "ColorBlend.swift").write_text(COLOR_BLEND.read_text().split(
            "enum SceneLayerColorBlendRenderer {", 1)[0])
        cls.inputs = {row["name"]: row for row in vectors()}
        (work / "input.json").write_text(json.dumps(list(cls.inputs.values()), indent=2))
        commands = [
            ["xcrun", "--sdk", "macosx", "metal", "-c", str(work / SHADER.name), "-o", str(work / "image.air")],
            ["xcrun", "--sdk", "macosx", "metallib", str(work / "image.air"), "-o", str(work / "image.metallib")],
            ["swiftc", *map(str, SOURCES), str(work / "ColorBlend.swift"), str(work / "Harness.swift"),
             "-module-cache-path", str(work / "module-cache"), "-o", str(work / "probe")],
        ]
        build_log = []
        for command in commands:
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            build_log.append(dict(command=command, exit=result.returncode, stdout=result.stdout, stderr=result.stderr))
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
        ran = subprocess.run([str(work / "probe"), str(work / "image.metallib"), str(work / "input.json"),
                              str(work / FOG_HEADER.name)],
                             capture_output=True, text=True, timeout=60)
        if ran.returncode:
            raise RuntimeError(ran.stdout + ran.stderr)
        cls.result = json.loads(ran.stdout)
        if identity != {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in identity_paths}:
            raise RuntimeError("product source or Fog header changed during GPU gate")
        if cls.result.get("metalUnavailable"):
            raise unittest.SkipTest("Metal unavailable")
        if len(cls.result["rows"]) != len(cls.inputs) or {row["name"] for row in cls.result["rows"]} != cls.inputs.keys():
            raise RuntimeError("incomplete image Fog GPU matrix")
        if configured := os.environ.get("MWX_IMAGE_DISTANCE_FOG_EVIDENCE"):
            evidence = Path(configured); evidence.mkdir(parents=True, exist_ok=True)
            (evidence / "gpu-output.json").write_text(json.dumps(dict(
                sourceSHA256=identity, input=list(cls.inputs.values()), output=cls.result,
                build=build_log, runExit=ran.returncode, stderr=ran.stderr,
                metallibSHA256=hashlib.sha256((work / "image.metallib").read_bytes()).hexdigest(),
                binarySHA256=hashlib.sha256((work / "probe").read_bytes()).hexdigest(),
                scope="actual image/ColorBlend pipeline pixels; no App/full corpus/official parity"),
                indent=2, sort_keys=True))

    def check_rows(self, names):
        for result in self.result["rows"]:
            if result["name"] not in names:
                continue
            with self.subTest(name=result["name"]):
                self.assertTrue(result["completed"], result)
                self.assertTrue(result["sourceUnchanged"], result)
                expected = expected_pixel(self.inputs[result["name"]])
                for actual, wanted in zip(result["actual"], expected, strict=True):
                    self.assertTrue(math.isfinite(actual), result)
                    self.assertAlmostEqual(actual, wanted, delta=0.002, msg=(result, expected))

    def test_quadratic_distance_and_linear_density_endpoints(self):
        self.check_rows({name for name in self.inputs if name.endswith("distance")
                         or "endpoint" in name or "interval" in name})

    def test_full_world_basis_and_radial_distance_do_not_use_uv(self):
        self.check_rows({"radial-off-axis", "nonuniform-basis", "rotated-nonuniform-basis", "tilted-world-basis"})

    def test_nonblack_fog_keeps_alpha_and_premultiplied_coverage(self):
        self.check_rows({name for name in self.inputs if name.startswith("coverage-")})

    def test_disabled_fog_and_raw_capture_keep_original_pixels(self):
        self.check_rows({name for name in self.inputs if name.startswith(("disabled-", "raw-capture-default-"))})

    def test_screen_fog_applies_after_color_blend_once(self):
        self.check_rows({name for name in self.inputs if name.startswith("screen-")
                         and not name.startswith("screen-shape-")})

    def test_shape_coverage_preserves_background_after_fog(self):
        self.check_rows({name for name in self.inputs if name.startswith("screen-shape-")})

    def test_fog_applies_after_layer_tint(self):
        self.check_rows({"fog-after-tint"})


if __name__ == "__main__":
    unittest.main()
