#!/usr/bin/env python3
"""Real image compositor GPU gate for storage association and additive weighting."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneMetalPipeline.swift"
SHADER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayer.metal"

HARNESS = r'''
import Foundation
import Metal
import simd

enum ScenePerformanceCounter { case pipelineStateBinds }
final class ScenePerformanceCounterHub {
    static let shared = ScenePerformanceCounterHub()
    func bump(_ value: ScenePerformanceCounter) {}
    func recordDraw(usesGeometry: Bool) {}
}

func texture(_ device: MTLDevice, _ value: SIMD4<Float>) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.shaderRead, .renderTarget]
    let texture = device.makeTexture(descriptor: descriptor)!
    var bytes = (0..<4).map { Float16(value[$0]) }
    bytes.withUnsafeMutableBytes {
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: 8)
    }
    return texture
}

func pixel(_ texture: MTLTexture) -> [Float] {
    var bytes = [Float16](repeating: 0, count: 4)
    bytes.withUnsafeMutableBytes {
        texture.getBytes($0.baseAddress!, bytesPerRow: 8,
            from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
    }
    return bytes.map(Float.init)
}

@main struct Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let authored = SIMD3<Float>(2, 0.6, 0.25)
        let tint = SIMD3<Float>(0.5, 0.25, 0.75)
        let background = SIMD4<Float>(0.125, 0.25, 0.375, 0.2)
        var results: [[String: Any]] = []
        for additive in [false, true] {
            let pipeline = SceneImageLayerPipeline(device: device,
                pixelFormat: .rgba16Float,
                blendMode: additive ? .alphaWeightedAdditive : .sourceOver,
                library: library)!
            for straight in [false, true] {
                for coverage: Float in [0, 0.5, 1] {
                    let rgb = straight ? authored : authored * coverage
                    let input = texture(device, SIMD4(rgb.x, rgb.y, rgb.z, coverage))
                    let original = pixel(input)
                    let output = texture(device, background)
                    let command = queue.makeCommandBuffer()!
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = output
                    pass.colorAttachments[0].loadAction = .load
                    pass.colorAttachments[0].storeAction = .store
                    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
                    pipeline.bind(encoder: encoder)
                    var vertices = [
                        SceneQuadVertex(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1), vertexCoverage: 0.75),
                        SceneQuadVertex(position: SIMD2( 0.5, -0.5), texcoord: SIMD2(1, 1), vertexCoverage: 0.75),
                        SceneQuadVertex(position: SIMD2(-0.5,  0.5), texcoord: SIMD2(0, 0), vertexCoverage: 0.75),
                        SceneQuadVertex(position: SIMD2( 0.5,  0.5), texcoord: SIMD2(1, 0), vertexCoverage: 0.75)
                    ]
                    encoder.setVertexBytes(&vertices,
                        length: vertices.count * MemoryLayout<SceneQuadVertex>.stride, index: 0)
                    let uniforms = SceneLayerFragmentUniforms(time: 0, alpha: 0.4,
                        dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
                        sourceSampling: SIMD2(0, straight ? 1 : 0),
                        tint: SIMD4(tint.x, tint.y, tint.z, 1),
                        textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
                    pipeline.drawLayer(texture: input,
                        mvp: simd_float4x4(diagonal: SIMD4(2, 2, 1, 1)),
                        uniforms: uniforms, encoder: encoder)
                    encoder.endEncoding()
                    command.commit()
                    command.waitUntilCompleted()
                    let sourceAlpha = coverage * 0.4 * 0.75
                    let contribution = authored * tint * sourceAlpha * (additive ? coverage : 1)
                    let backgroundScale: Float = additive ? 1 : 1 - sourceAlpha
                    let expected = [
                        contribution.x + background.x * backgroundScale,
                        contribution.y + background.y * backgroundScale,
                        contribution.z + background.z * backgroundScale,
                        sourceAlpha + background.w * (1 - sourceAlpha)
                    ]
                    results.append([
                        "additive": additive, "straight": straight, "coverage": coverage,
                        "completed": command.status == .completed,
                        "sourceUnchanged": pixel(input) == original,
                        "actual": pixel(output), "expected": expected
                    ])
                }
            }
        }
        let payload: [String: Any] = ["metalAvailable": true, "cases": results]
        print(String(data: try JSONSerialization.data(withJSONObject: payload,
            options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneImageCompositorRepresentationGPUTests(unittest.TestCase):
    def test_straight_association_is_independent_of_additive_weighting(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-image-representation-gpu-") as directory:
            folder = Path(directory)
            harness = folder / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = folder / "image-representation"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(folder / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(folder / "swift-cache")
            compiled = subprocess.run([
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(PIPELINE), str(harness), "-framework", "Metal",
                "-module-cache-path", str(folder / "module-cache"), "-o", str(binary)
            ], cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            executed = subprocess.run([str(binary), str(SHADER)], cwd=ROOT,
                env=environment, capture_output=True, text=True)
            self.assertEqual(executed.returncode, 0, executed.stderr)
            payload = json.loads(executed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(len(payload["cases"]), 12)
        for case in payload["cases"]:
            self.assertTrue(case["completed"], case)
            self.assertTrue(case["sourceUnchanged"], case)
            for actual, expected in zip(case["actual"], case["expected"], strict=True):
                self.assertAlmostEqual(actual, expected, delta=0.002, msg=case)
        for additive in (False, True):
            cases = [case for case in payload["cases"] if case["additive"] == additive]
            for coverage in (0, 0.5, 1):
                pair = [case["actual"] for case in cases if case["coverage"] == coverage]
                self.assertEqual(pair[0], pair[1])


if __name__ == "__main__":
    unittest.main()
