"""Real production unlit Metal multiplication over finite authored factors.

The independent oracle multiplies exact stored Float32 inputs in Decimal;
this gate measures shader arithmetic, not App/official visual compatibility.
"""
from decimal import Decimal, localcontext
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SHADER = SCENE / "Rendering/Composition/SceneImageLayer.metal"
FOG_HEADER = SHADER.with_name("SceneDistanceFog.metalh")
SOURCES = [SCENE / "Rendering/Metal/SceneMetalPipeline.swift",
           SCENE / "Diagnostics/ScenePerformanceCounterHub.swift"]


def f32(value):
    return struct.unpack("f", struct.pack("f", value))[0]


def vectors():
    def row(name, source=(4, 4, 4, 1), tint=(1e38, 1e38, 1e38, 1),
            alpha=1e-37, coverage=1, clip=255):
        return dict(name=name, source=list(source), tint=list(tint), alpha=alpha,
                    vertexCoverage=coverage, clipByte=clip)
    return [row("finite-intermediate-overflow"),
            row("signed-overflow", source=(4, -4, 2, 1), tint=(1e38, 1e38, -1e38, 1)),
            row("zero-opacity", alpha=0), row("zero-tint", tint=(0, 1e38, 0, 1)),
            row("ordinary-hdr", source=(8, 4, 2, .5), tint=(2, 2, 2, 1), alpha=1),
            row("ordinary-style", source=(4, 2, 1, .8), tint=(.25, .5, 2, .5), alpha=.25),
            row("tiny-factor-order", source=(1e38, 1e38, 1e38, 1),
                tint=(1e-37, 1e-37, 1e-37, 1), alpha=.01),
            row("tiny-finite-opacity", source=(1, 1, 1, 1), tint=(1, 1, 1, 1)),
            row("source-alpha-coverage", source=(4, 4, 4, .5)),
            # Keep the final alpha normal under App fast-math. The previous
            # combination with source.a=.5 had a pre-existing finite RGB
            # underflow; that diagnostic retains its failing math oracle.
            row("vertex-and-clip-coverage", source=(8, 8, 8, 1),
                tint=(5e37, 5e37, 5e37, 1), coverage=.25, clip=128),
            row("zero-vertex-coverage", coverage=0), row("zero-clip-coverage", clip=0),
            row("alpha-channel-overflow", source=(4, 4, 4, 4), tint=(1e38,) * 4),
            row("unrepresentable-half", tint=(1e5, 1e5, 1e5, 1), alpha=1),
            row("unrepresentable-float", source=(1e38, 1e38, 1e38, 1), tint=(4, 4, 4, 1), alpha=1)]


def oracle(row, weighted, pixel_format):
    values = []
    with localcontext() as context:
        context.prec = 100
        for channel in range(4):
            factors = [row["source"][channel], row["tint"][channel], row["alpha"],
                       row["vertexCoverage"], f32(row["clipByte"] / 255)]
            if weighted and channel < 3:
                factors.append(row["source"][3])
            value = Decimal(1)
            for factor in factors:
                value *= Decimal.from_float(f32(factor))
            raw = float(value)
            try:
                values.append(struct.unpack("e", struct.pack("e", raw))[0]
                              if pixel_format == "rgba16Float" else f32(raw))
            except OverflowError:
                values.append(math.copysign(math.inf, raw))
    return values


HARNESS = r'''
import Foundation
import Metal
import simd
@main enum Harness {
    static func values(_ row: [String:Any], _ key: String) -> [Float] {
        (row[key] as! [NSNumber]).map(\.floatValue)
    }
    static func scalar(_ row: [String:Any], _ key: String) -> Float {
        (row[key] as! NSNumber).floatValue
    }
    static func texture(_ device: MTLDevice, _ format: MTLPixelFormat) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,
            width:1,height:1,mipmapped:false)
        d.storageMode = .shared; d.usage = [.shaderRead,.renderTarget]
        return device.makeTexture(descriptor:d)!
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"gpuUnavailable\":true}"); return
        }
        let library = try device.makeLibrary(URL:URL(fileURLWithPath:CommandLine.arguments[1]))
        let rows = try JSONSerialization.jsonObject(with:Data(contentsOf:
            URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]]
        var results: [[String:Any]] = []
        for (label,format) in [("rgba16Float",MTLPixelFormat.rgba16Float),
                               ("rgba32Float",MTLPixelFormat.rgba32Float)] {
            for weighted in [false,true] {
                let pipeline = SceneImageLayerPipeline(device:device,pixelFormat:format,
                    blendMode:weighted ? .alphaWeightedAdditive : .sourceOver,library:library)!
                for row in rows {
                    // rgba32 source preserves the registered inputs; targets
                    // independently measure half storage and float arithmetic.
                    let source = texture(device,.rgba32Float), target = texture(device,format)
                    let rgba = values(row,"source")
                    rgba.withUnsafeBytes { source.replace(region:MTLRegionMake2D(0,0,1,1),
                        mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:16) }
                    let maskDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.r8Unorm,
                        width:1,height:1,mipmapped:false)
                    maskDescriptor.storageMode = .shared; maskDescriptor.usage = .shaderRead
                    let mask = device.makeTexture(descriptor:maskDescriptor)!
                    var byte = (row["clipByte"] as! NSNumber).uint8Value
                    mask.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,
                        withBytes:&byte,bytesPerRow:1)
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = target
                    pass.colorAttachments[0].loadAction = .clear
                    pass.colorAttachments[0].storeAction = .store
                    pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
                    let command = queue.makeCommandBuffer()!
                    let encoder = command.makeRenderCommandEncoder(descriptor:pass)!
                    pipeline.bind(encoder:encoder)
                    let coverage = scalar(row,"vertexCoverage")
                    var vertices = [SceneQuadVertex(position:SIMD2(-0.5,-0.5),texcoord:SIMD2(0,1),vertexCoverage:coverage),
                        SceneQuadVertex(position:SIMD2(0.5,-0.5),texcoord:SIMD2(1,1),vertexCoverage:coverage),
                        SceneQuadVertex(position:SIMD2(-0.5,0.5),texcoord:SIMD2(0,0),vertexCoverage:coverage),
                        SceneQuadVertex(position:SIMD2(0.5,0.5),texcoord:SIMD2(1,0),vertexCoverage:coverage)]
                    encoder.setVertexBytes(&vertices,length:vertices.count * MemoryLayout<SceneQuadVertex>.stride,index:0)
                    var mvp = simd_float4x4(diagonal:SIMD4<Float>(2,2,1,1))
                    encoder.setVertexBytes(&mvp,length:MemoryLayout<simd_float4x4>.stride,index:1)
                    var uniforms = SceneLayerFragmentUniforms(time:0,alpha:scalar(row,"alpha"),
                        dependencyBlendMode:0,usesDependencyBlend:0,cursorUV:.zero,sourceSampling:.zero,
                        tint:SIMD4(values(row,"tint")),textureFrame0:SIMD4(0,0,1,0),textureFrame1:SIMD4(0,1,0,0))
                    encoder.setFragmentBytes(&uniforms,length:MemoryLayout<SceneLayerFragmentUniforms>.stride,index:0)
                    encoder.setFragmentTexture(source,index:0); encoder.setFragmentTexture(source,index:1)
                    SceneImageLayerPipeline.bindClipMask(encoder:encoder,texture:mask,transform:SIMD4(0.5,0.5,1,1))
                    encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4)
                    encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                    var actual: [Float]
                    if format == .rgba32Float {
                        actual = Array(repeating:0,count:4)
                        actual.withUnsafeMutableBytes { target.getBytes($0.baseAddress!,bytesPerRow:16,
                            from:MTLRegionMake2D(0,0,1,1),mipmapLevel:0) }
                    } else {
                        var half = [Float16](repeating:0,count:4)
                        half.withUnsafeMutableBytes { target.getBytes($0.baseAddress!,bytesPerRow:8,
                            from:MTLRegionMake2D(0,0,1,1),mipmapLevel:0) }
                        actual = half.map(Float.init)
                    }
                    let safe: [Any] = actual.map { value in
                        value.isFinite ? value as Any : (value.isNaN ? "NaN" : value > 0 ? "Infinity" : "-Infinity")
                    }
                    results.append(["name":row["name"]!,"format":label,"weightsSourceAlpha":weighted,
                        "actual":safe,"completed":command.status == .completed && command.error == nil])
                }
            }
        }
        print(String(data:try JSONSerialization.data(withJSONObject:["rows":results],options:.sortedKeys),encoding:.utf8)!)
    }
}
'''


class SceneUnlitImageMultiplicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("Swift unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-unlit-product-")
        cls.addClassCleanup(cls.temporary.cleanup)
        folder = Path(cls.temporary.name)
        original = Path(os.environ.get("MWX_UNLIT_IMAGE_SHADER", SHADER))
        shader = folder / "SceneImageLayer.metal"
        shader.write_bytes(original.read_bytes())
        (folder / FOG_HEADER.name).write_bytes(FOG_HEADER.read_bytes())
        identity_paths = [*SOURCES, original, FOG_HEADER]
        source_hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in identity_paths}
        inputs = vectors()
        (folder / "vectors.json").write_text(json.dumps(inputs, indent=2))
        (folder / "Harness.swift").write_text(HARNESS)
        injected = os.environ.get("MWX_UNLIT_IMAGE_METALLIB")
        library = Path(injected) if injected else folder / "fixture.metallib"
        library_before = hashlib.sha256(library.read_bytes()).hexdigest() if injected else None
        metal_flags = ["-fmetal-math-mode=fast", "-fmetal-math-fp32-functions=fast"]
        commands = ([] if injected else [
            ["xcrun", "-sdk", "macosx", "metal", *metal_flags, "-c", str(shader), "-o", str(folder / "image.air")],
            ["xcrun", "-sdk", "macosx", "metallib", str(folder / "image.air"), "-o", str(folder / "fixture.metallib")],
        ]) + [
            ["swiftc", *map(str, SOURCES), str(folder / "Harness.swift"),
             "-module-cache-path", str(folder / "module-cache"), "-o", str(folder / "test")],
        ]
        build_log = []
        for command in commands:
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            build_log.append(dict(command=command, exit=result.returncode, stdout=result.stdout, stderr=result.stderr))
            if result.returncode:
                raise RuntimeError(result.stderr)
        run = subprocess.run([str(folder / "test"), str(library),
                              str(folder / "vectors.json")], capture_output=True, text=True, timeout=60)
        if run.returncode:
            raise RuntimeError(run.stderr)
        cls.output = json.loads(run.stdout)
        if cls.output.get("gpuUnavailable"):
            raise unittest.SkipTest("Metal unavailable")
        cls.inputs = {v["name"]: v for v in inputs}
        if len(cls.output["rows"]) != 4 * len(inputs):
            raise RuntimeError("incomplete GPU format/function-constant matrix")
        if configured := os.environ.get("MWX_UNLIT_GPU_EVIDENCE"):
            evidence = Path(configured); evidence.mkdir(parents=True, exist_ok=True)
            report = {"shaderPath": str(original), "shaderSHA256": hashlib.sha256(shader.read_bytes()).hexdigest(),
                      "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                      "sourceSHA256": source_hashes, "metalCompileFlags": metal_flags,
                      "metallibPath": str(library), "metallibSHA256": hashlib.sha256(library.read_bytes()).hexdigest(),
                      "libraryMode": "injected App library" if injected else "compiled frozen product shader",
                      "build": build_log,
                      "input": inputs, "runExit": run.returncode, "stderr": run.stderr, "output": cls.output,
                      "scope": "real fixed product pipeline and shader; numerical readback only, no App/parity"}
            (evidence / "gpu-output.json").write_text(json.dumps(report, indent=2, sort_keys=True))
        if source_hashes != {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in identity_paths}:
            raise RuntimeError("product source or Fog header changed during compilation/run")
        if injected and library_before != hashlib.sha256(library.read_bytes()).hexdigest():
            raise RuntimeError("injected product metallib changed during GPU run")

    def check_rows(self, names):
        for result in self.output["rows"]:
            if result["name"] not in names:
                continue
            with self.subTest(name=result["name"], format=result["format"], weighted=result["weightsSourceAlpha"]):
                self.assertTrue(result["completed"], result)
                expected = oracle(self.inputs[result["name"]], result["weightsSourceAlpha"], result["format"])
                for channel, (actual, target) in enumerate(zip(result["actual"], expected)):
                    self.assertIsInstance(actual, (float, int), (channel, result))
                    self.assertTrue(math.isfinite(actual), (channel, result))
                    # Half permits two store ULPs; float permits normal rounded
                    # finite multiplication error, without an absolute tiny-value floor.
                    tolerance = max(abs(target) * (2 ** -9 if result["format"] == "rgba16Float" else 2e-6),
                                    2 ** -23 if result["format"] == "rgba16Float" else 1e-43)
                    self.assertAlmostEqual(actual, target, delta=tolerance, msg=(channel, result, expected))

    def test_finite_final_product_survives_intermediate_overflow(self):
        self.check_rows({"finite-intermediate-overflow", "alpha-channel-overflow"})

    def test_ordinary_hdr_style_and_tiny_factor_order(self):
        self.check_rows({"ordinary-hdr", "ordinary-style", "tiny-factor-order", "tiny-finite-opacity"})

    def test_signed_and_zero_factors_keep_their_meaning(self):
        self.check_rows({"signed-overflow", "zero-opacity", "zero-tint"})

    def test_vertex_clip_coverage_and_alpha_weighting_apply_once(self):
        self.check_rows({"source-alpha-coverage", "vertex-and-clip-coverage", "zero-vertex-coverage", "zero-clip-coverage"})

    def test_unrepresentable_final_product_is_not_capped(self):
        names = {"unrepresentable-half", "unrepresentable-float"}
        for result in self.output["rows"]:
            if result["name"] not in names:
                continue
            if result["format"] != "rgba32Float":
                # A half render target may saturate finite >65504 during
                # hardware store. Float readback distinguishes a shader cap;
                # the raw report still records both half storage observations.
                continue
            with self.subTest(name=result["name"], format=result["format"], weighted=result["weightsSourceAlpha"]):
                self.assertTrue(result["completed"], result)
                expected = oracle(self.inputs[result["name"]], result["weightsSourceAlpha"], result["format"])
                for actual, target in zip(result["actual"], expected):
                    if math.isinf(target):
                        self.assertEqual(actual, "Infinity", result)
                    else:
                        self.assertAlmostEqual(actual, target, delta=abs(target) * 2e-6, msg=result)


if __name__ == "__main__":
    unittest.main()
