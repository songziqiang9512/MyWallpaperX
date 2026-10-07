"""Execute production image and ColorBlend clipping fragments with real Metal."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCENE = Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [SCENE / path for path in (
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Composition/SceneBlendModeShaderSource.swift",
    "Rendering/Composition/SceneFramebufferSnapshot.swift",
    "Resources/Textures/SceneResourceBudget.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
    "Diagnostics/SceneGPUCensus.swift",
)]

HARNESS = r'''
import Foundation
import Metal
import simd

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}"); return
        }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let image = SceneImageLayerPipeline(device: device, library: library)!
        let additive = SceneImageLayerPipeline(device: device, blendMode: .alphaWeightedAdditive,
                                              library: library)!
        let blend = SceneLayerColorBlendPipeline(device: device)!
        func texture(_ format: MTLPixelFormat, _ width: Int, _ height: Int,
                     _ pixels: [UInt8] = [], target: Bool = false) -> MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: width, height: height, mipmapped: false)
            desc.storageMode = .shared
            desc.usage = target ? [.renderTarget] : [.shaderRead]
            let result = device.makeTexture(descriptor: desc)!
            if !pixels.isEmpty {
                pixels.withUnsafeBytes {
                    result.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: width * (format == .r8Unorm ? 1 : 4))
                }
            }
            return result
        }
        let source = texture(.rgba8Unorm, 1, 1, [64, 32, 16, 128])
        let background = texture(.rgba8Unorm, 8, 8,
            (0..<64).flatMap { _ in [UInt8(64), 96, 128, 255] })
        let black = texture(.r8Unorm, 4, 4, Array(repeating: 0, count: 16))
        let gray = texture(.r8Unorm, 4, 4, Array(repeating: 128, count: 16))
        let white = texture(.r8Unorm, 4, 4, Array(repeating: 255, count: 16))
        let split = texture(.r8Unorm, 8, 8, (0..<64).map { $0 % 8 < 4 ? 0 : 255 })
        let identityClip = SIMD4<Float>(0.5, 0.5, 1, 1)
        func draw(mask: MTLTexture, transform: SIMD4<Float> = identityClip,
                  coverage: Float = 1, alpha: Float = 1, blendMode: Int? = nil,
                  ordinaryReset: Bool = false, additiveMode: Bool = false) -> [[UInt8]] {
            let command = queue.makeCommandBuffer()!
            let target = texture(.bgra8Unorm, 8, 8, target: true)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            let pipeline = additiveMode ? additive : image
            var mvp = matrix_identity_float4x4
            mvp.columns.0.x = 2; mvp.columns.1.y = 2
            var uniforms = SceneLayerFragmentUniforms(time: 0, alpha: alpha,
                dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
                sourceSampling: .zero, tint: SIMD4(repeating: 1),
                textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
            if let mode = blendMode {
                // Seed stale state before the real production binder. Its
                // default must turn clipping off for an ordinary draw.
                SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: black,
                                                     transform: identityClip)
                blend.bindGeometry(layerTexture: source, backgroundTexture: background,
                    blendMode: mode, mvp: mvp, encoder: encoder)
            } else {
                pipeline.bind(encoder: encoder)
                encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneLayerFragmentUniforms>.size, index: 0)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentTexture(source, index: 1)
            }
            if ordinaryReset && blendMode == nil {
                SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: black,
                                                     transform: identityClip)
                pipeline.drawLayer(texture: source, mvp: mvp, uniforms: uniforms, encoder: encoder)
            } else {
                // Source UV is constant. Only the modelPosition varying can
                // reproduce the left/right split mask across this geometry.
                var vertices = [SIMD2<Float>(-0.5, -0.5), SIMD2(0.5, -0.5),
                                SIMD2(-0.5, 0.5), SIMD2(0.5, 0.5)].map {
                    SceneQuadVertex(position: $0, texcoord: SIMD2(0.1, 0.9), vertexCoverage: coverage)
                }
                encoder.setVertexBytes(&vertices, length: vertices.count * MemoryLayout<SceneQuadVertex>.stride, index: 0)
                if !ordinaryReset {
                    SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: mask, transform: transform)
                }
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            guard command.status == .completed, command.error == nil else { fatalError("GPU completion") }
            var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
            pixels.withUnsafeMutableBytes {
                target.getBytes($0.baseAddress!, bytesPerRow: 32, from: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0)
            }
            return [1, 4, 6].map { x in
                let offset = (4 * 8 + x) * 4
                return [pixels[offset + 2], pixels[offset + 1], pixels[offset], pixels[offset + 3]]
            }
        }
        let lit = MTLRenderPipelineDescriptor()
        lit.vertexFunction = library.makeFunction(name: "sceneImageLayerVert")
        lit.fragmentFunction = library.makeFunction(name: "sceneLitImageLayerFrag")
        lit.colorAttachments[0].pixelFormat = .bgra8Unorm
        let litCompatible = (try? device.makeRenderPipelineState(descriptor: lit)) != nil
        let rows: [String: Any] = [
            "vertexStride": MemoryLayout<SceneQuadVertex>.stride, "litCompatible": litCompatible,
            "black": draw(mask: black, coverage: 0.5, alpha: 0.5),
            "gray": draw(mask: gray, coverage: 0.5, alpha: 0.5),
            "white": draw(mask: white, coverage: 0.5, alpha: 0.5),
            "disabled": draw(mask: black, transform: .zero, coverage: 0.5, alpha: 0.5),
            "imageReset": draw(mask: black, ordinaryReset: true),
            "split": draw(mask: split),
            "outside": draw(mask: white, transform: SIMD4(2.5, 0.5, 1, 1)),
            "additiveGray": draw(mask: gray, coverage: 0.5, alpha: 0.5, additiveMode: true),
            "blendBlack": draw(mask: black, coverage: 0.5, blendMode: 2),
            "blendGray": draw(mask: gray, coverage: 0.5, blendMode: 2),
            "blendAddGray": draw(mask: gray, coverage: 0.5, blendMode: 31),
            "blendReset": draw(mask: black, blendMode: 31, ordinaryReset: true),
            "blendSplit": draw(mask: split, blendMode: 31),
            "blendOutside": draw(mask: white, transform: SIMD4(2.5, 0.5, 1, 1), blendMode: 2),
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class ScenePuppetClippingShaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-clip-shader-") as directory:
            root = Path(directory)
            source = root / "Harness.swift"
            source.write_text(HARNESS)
            blend = root / "ColorBlend.swift"
            # Keep both the real shader state and its production bindGeometry;
            # only the unrelated compositor entry point is outside this gate.
            blend.write_text((SCENE / "Rendering/Composition/SceneLayerColorBlendPipeline.swift")
                             .read_text().split("enum SceneLayerColorBlendRenderer {", 1)[0])
            airs = []
            for name in ("SceneImageLayer", "SceneLitImageLayer"):
                air = root / f"{name}.air"
                airs.append(air)
                cls.run_command(["xcrun", "--sdk", "macosx", "metal", "-c",
                                 str(SCENE / f"Rendering/Composition/{name}.metal"), "-o", str(air)])
            library, binary = root / "shader.metallib", root / "shader"
            cls.run_command(["xcrun", "--sdk", "macosx", "metallib", *map(str, airs), "-o", str(library)])
            cls.run_command(["swiftc", *map(str, SOURCES), str(blend), str(source),
                             "-module-cache-path", str(root / "module-cache"), "-o", str(binary)])
            cls.result = json.loads(cls.run_command([str(binary), str(library)]))
        if cls.result.get("metalUnavailable"):
            raise unittest.SkipTest("Metal unavailable")

    @staticmethod
    def run_command(command):
        ran = subprocess.run(command, capture_output=True, text=True, timeout=120)
        if ran.returncode:
            raise RuntimeError(ran.stdout + ran.stderr)
        return ran.stdout

    def assert_pixel(self, name, expected, index=1):
        for actual, wanted in zip(self.result[name][index], expected):
            self.assertAlmostEqual(actual, wanted, delta=1, msg=name)

    def test_mask_multiplies_premultiplied_color_and_alpha_once(self):
        self.assert_pixel("black", [0, 0, 0, 0])
        self.assert_pixel("gray", [8, 4, 2, 16])
        self.assert_pixel("white", [16, 8, 4, 32])
        self.assert_pixel("additiveGray", [4, 2, 1, 16])

    def test_mask_uses_model_position_and_zero_outside_roi(self):
        self.assert_pixel("split", [0, 0, 0, 0], index=0)
        self.assert_pixel("split", [64, 32, 16, 128], index=2)
        self.assert_pixel("outside", [0, 0, 0, 0])

    def test_disabled_clip_and_ordinary_image_draw_reset_stale_state(self):
        self.assert_pixel("disabled", [16, 8, 4, 32])
        self.assert_pixel("imageReset", [64, 32, 16, 128])

    def test_color_blend_receives_coverage_before_unpremultiplication(self):
        self.assert_pixel("blendBlack", [64, 96, 128, 255])
        factor = 0.5 * 128 / 255
        expected = [round(bg * (1 - 128 / 255 * factor + src / 255 * factor))
                    for bg, src in zip([64, 96, 128], [64, 32, 16])]
        self.assert_pixel("blendGray", expected + [255])
        self.assert_pixel("blendAddGray", [80, 104, 132, 255])

    def test_color_blend_mapping_outside_and_default_bind_reset(self):
        self.assert_pixel("blendSplit", [64, 96, 128, 255], index=0)
        self.assert_pixel("blendSplit", [128, 128, 144, 255], index=2)
        self.assert_pixel("blendOutside", [64, 96, 128, 255])
        self.assert_pixel("blendReset", [128, 128, 144, 255])

    def test_vertex_abi_and_lit_capture_pipeline_remain_compatible(self):
        self.assertEqual(self.result["vertexStride"], 24)
        self.assertTrue(self.result["litCompatible"])
