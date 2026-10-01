#!/usr/bin/env python3
"""Real direct-draw routing and image Metal pipeline over a known background.

Only the graph output producer and renderer container are shims. The production
quad entry point chooses the pipeline; its selected state draws real GPU pixels.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [SCENE / path for path in (
    "Diagnostics/ScenePerformanceCounterHub.swift",
    "Rendering/Metal/SceneMetalPipeline.swift",
    # Mechanical sync: the repository gained the lit base-capture pipeline
    # slot (D3 first slice); the slot's type ships with the lit pipeline.
    "Rendering/Metal/SceneLitImageLayerPipeline.swift",
    "Rendering/Metal/SceneImageEffectPipelineRepository.swift",
    "Rendering/Composition/SceneDirectDrawLayerRenderer.swift",
)]
SHADER = SCENE / "Rendering/Composition/SceneImageLayer.metal"
HARNESS = r'''
import Foundation
import Metal
import simd

final class SceneSpotLightPipeline { init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {} }
final class SceneLayerColorBlendPipelineState { init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {} }
struct SceneRenderDescriptor { struct Layer { let id = 7; var alpha: Float = 1 } }
struct SceneResolvedMaterialFrameTargetPlan {}
struct SceneEffectExecutionFrameTrace {}
struct SceneFrameContext { let dynamicValues = 0 }
enum SceneDynamicLayerValues {
    static func alpha(layerID: Int, authoredValue: Float, snapshot: Int) -> Float { authoredValue }
}
final class SceneMainPassEncoder {
    let encoder: MTLRenderCommandEncoder
    init(_ encoder: MTLRenderCommandEncoder) { self.encoder = encoder }
}
struct Compositor {
    let texture: MTLTexture
    func drawResolvedDirectDrawQuad(
        layer: SceneRenderDescriptor.Layer, alpha: Float,
        framePlan: SceneResolvedMaterialFrameTargetPlan, pipeline: SceneImageLayerPipeline,
        mainPass: SceneMainPassEncoder, executionTrace: SceneEffectExecutionFrameTrace?
    ) -> Bool {
        let uniforms = SceneLayerFragmentUniforms(time: 0, alpha: alpha,
            dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
            sourceSampling: .zero, tint: SIMD4(repeating: 1),
            textureFrame0: SIMD4(0,0,1,0), textureFrame1: SIMD4(0,1,0,0))
        pipeline.bind(encoder: mainPass.encoder)
        pipeline.drawLayer(texture: texture, mvp: matrix_identity_float4x4 * 2,
            uniforms: uniforms, encoder: mainPass.encoder)
        return true
    }
}
struct SceneMetalRenderer {
    let pipelineRepository: SceneImageEffectPipelineRepository
    let imageCompositor: Compositor
}
@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"gpuUnavailable\":true}"); return
        }
        // The production repository uses the default library, loaded from the
        // test executable's sibling default.metallib just like the App bundle.
        let repo = SceneImageEffectPipelineRepository(device: device)
        let unprepared = repo.directDraw == nil
        guard repo.prepareDirectDraw() else { fatalError("direct-draw preparation") }
        guard let additive = repo.directDraw,
              let normal = SceneImageLayerPipeline(device: device),
              let queue = device.makeCommandQueue() else { fatalError("pipeline preparation") }
        guard repo.prepareDirectDraw() else { fatalError("repeated preparation") }
        let reused = repo.directDraw!.state === additive.state
        func draw(_ bytes: [UInt8], alpha: Float = 1, prepared: Bool = true,
                  ordinaryImage: Bool = false, hasPlan: Bool = true) -> [String: Any] {
            let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
            sourceDescriptor.storageMode = .shared
            let source = device.makeTexture(descriptor: sourceDescriptor)!
            bytes.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0,0,1,1),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4) }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
            desc.usage = [.renderTarget]; desc.storageMode = .shared
            let target = device.makeTexture(descriptor: desc)!
            let command = queue.makeCommandBuffer()!
            let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0.4,0.5,0.6,1)
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            let mainPass = SceneMainPassEncoder(encoder)
            let compositor = Compositor(texture: source)
            let renderer = SceneMetalRenderer(pipelineRepository:
                prepared ? repo : SceneImageEffectPipelineRepository(device: device),
                imageCompositor: compositor)
            let layer = SceneRenderDescriptor.Layer(alpha: alpha)
            let drawn: Bool
            if ordinaryImage {
                drawn = compositor.drawResolvedDirectDrawQuad(layer: layer, alpha: alpha,
                    framePlan: .init(), pipeline: normal, mainPass: mainPass, executionTrace: nil)
            } else {
                drawn = renderer.drawQuadLayer(layer: layer, resolvedFramePlan: hasPlan ? .init() : nil,
                    frameContext: .init(), mainPass: mainPass, executionTrace: nil)
            }
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            guard command.status == .completed, command.error == nil else { fatalError("GPU completion") }
            var pixels = [UInt8](repeating: 0, count: 8*8*4)
            pixels.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: 32,
                from: MTLRegionMake2D(0,0,8,8), mipmapLevel: 0) }
            let i = (4*8+4)*4
            return ["drawn":drawn,"rgba":[pixels[i+2],pixels[i+1],pixels[i],pixels[i+3]]]
        }
        let result: [String: Any] = ["unprepared":unprepared,"reused":reused,
            "light":draw([51,0,26,128]), "faded":draw([51,0,26,128],alpha:0.5),
            "transparent":draw([0,0,0,0]),
            "zeroCoverage":draw([51,0,26,0]),
            "quarterCoverage":draw([51,0,26,64]),
            "fullCoverage":draw([51,0,26,255]), "missing":draw([51,0,26,128],prepared:false),
            "unplanned":draw([51,0,26,128],prepared:false,hasPlan:false),
            "ordinary":draw([51,0,26,128],ordinaryImage:true),
            "nextFrame":draw([51,0,26,128])]
        print(String(data:try JSONSerialization.data(withJSONObject:result),encoding:.utf8)!)
    }
}
'''

class DirectDrawCompositionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("Swift unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-direct-draw-gpu-")
        cls.addClassCleanup(cls.temp.cleanup)
        folder = Path(cls.temp.name)
        harness = folder / "Harness.swift"
        harness.write_text(HARNESS)
        commands = [
            ["xcrun", "-sdk", "macosx", "metal", "-c", str(SHADER), "-o", str(folder/"image.air")],
            ["xcrun", "-sdk", "macosx", "metallib", str(folder/"image.air"), "-o", str(folder/"default.metallib")],
            ["swiftc", *map(str, SOURCES), str(harness), "-o", str(folder/"test")],
        ]
        for command in commands:
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            if result.returncode:
                raise RuntimeError(result.stderr)
        result = subprocess.run([str(folder/"test")], cwd=folder, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError(result.stderr)
        cls.result = json.loads(result.stdout)
        if cls.result.get("gpuUnavailable"):
            raise unittest.SkipTest("Metal device unavailable")

    def pixels(self, name, expected):
        for actual, target in zip(self.result[name]["rgba"], expected):
            self.assertAlmostEqual(actual, target, delta=1, msg=name)

    def test_emitted_light_preserves_background_channels(self):
        self.assertTrue(self.result["light"]["drawn"])
        self.pixels("light", [128,128,166,255])
        self.pixels("faded", [115,128,160,255])
        self.pixels("transparent", [102,128,153,255])
        self.assertEqual(self.result["light"], self.result["nextFrame"])

    def test_authored_coverage_attenuates_light_before_layer_opacity(self):
        self.pixels("zeroCoverage", [102,128,153,255])
        self.pixels("quarterCoverage", [115,128,160,255])
        self.pixels("fullCoverage", [153,128,179,255])
        self.pixels("faded", [115,128,160,255])

    def test_missing_preparation_does_not_fall_back_to_cover_blending(self):
        self.assertTrue(self.result["unprepared"])
        self.assertTrue(self.result["reused"])
        self.assertFalse(self.result["missing"]["drawn"])
        self.pixels("missing", [102,128,153,255])
        self.assertTrue(self.result["unplanned"]["drawn"])
        self.pixels("unplanned", [102,128,153,255])

    def test_ordinary_image_keeps_source_over(self):
        self.pixels("ordinary", [102,64,102,255])

if __name__ == "__main__":
    unittest.main()
