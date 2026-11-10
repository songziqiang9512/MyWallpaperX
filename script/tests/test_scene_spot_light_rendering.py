#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

if __package__:
    from . import test_scene_spot_light_plan as plan_fixture
else:
    import test_scene_spot_light_plan as plan_fixture

ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [*plan_fixture.SOURCES,
    SCENE_ROOT / "Rendering/Composition/SceneMainPassEncoder.swift",
    SCENE_ROOT / "Rendering/Lighting/SceneSpotLightPipeline.swift",
]

HARNESS = plan_fixture.CARRIERS + r'''
import Metal

// PRODUCTION_QUAD_VERTEX

// This gate does not acquire graph pins. MainPass itself remains production.
final class SceneGraphRenderTargetResidencyPin { func release() {} }

@main enum Harness {
    static let width = 128
    static let height = 96

    static func plan(radius: Float = 1.55, inner: Float = 1.87, outer: Float = 5.72,
                     intensity: Float = 80, density: Float = 3.93) -> SceneSpotLightPlan {
        SceneSpotLightPlan(layer: SpotLightInputs.layer(light: SpotLightInputs.light(
            intensity: intensity, radius: radius, inner: inner, outer: outer, density: density)))!
    }

    static func render(
        device: MTLDevice, queue: MTLCommandQueue, pipeline: SceneSpotLightPipeline,
        plan: SceneSpotLightPlan,
        worldFrame: simd_float4x4 = SceneMatrix.translation(SIMD3(-0.8, 0, 0.5)),
        viewProjection: simd_float4x4 = matrix_identity_float4x4,
        map: simd_float4x4? = nil,
        color: SIMD3<Float>? = nil, alpha: Float? = nil,
        background: Float = 0, peerFrame: simd_float4x4? = nil
    ) -> (accepted: Bool, peerAccepted: Bool, bytes: [UInt8]) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        let target = device.makeTexture(descriptor: descriptor)!
        let command = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: command, target: target,
            clearColor: MTLClearColorMake(Double(background), Double(background), Double(background), 0),
            clearEnabled: true, worldClipToTargetClip: map)
        let encoder = pass.encoder()!
        let projection = pass.rasterClipProjection(viewProjection)
        let resolvedAlpha = alpha ?? SceneDynamicLayerValues.alpha(layerID: plan.layerID,
            authoredValue: plan.alpha, snapshot: .empty(frameIndex: 0))
        let accepted = pipeline.draw(plan: plan, color: color ?? plan.color, intensity: plan.intensity,
            alpha: resolvedAlpha, worldFrame: worldFrame, viewProjection: projection, encoder: encoder)
        let peerAccepted = peerFrame.map {
            pipeline.draw(plan: plan, color: plan.color, intensity: plan.intensity,
                alpha: resolvedAlpha, worldFrame: $0, viewProjection: projection, encoder: encoder)
        } ?? false
        _ = pass.finishEnsuringClear()
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed, "SpotLight command buffer failed")
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return (accepted, peerAccepted, bytes)
    }

    static func bounds(_ bytes: [UInt8]) -> [Int] {
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 3 {
                xs.append(x)
                ys.append(y)
            }
        }
        return [xs.min() ?? -1, ys.min() ?? -1, xs.max() ?? -1, ys.max() ?? -1]
    }

    static func moments(_ bytes: [UInt8]) -> [Double] {
        var weight = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let a = Double(bytes[(y * width + x) * 4 + 3])
                let wx = (Double(x) + 0.5) * 2 / Double(width) - 1
                let wy = 1 - (Double(y) + 0.5) * 2 / Double(height)
                weight += a
                sx += a * wx
                sy += a * wy
                sxx += a * wx * wx
                sxy += a * wx * wy
                syy += a * wy * wy
            }
        }
        guard weight > 0 else { return [0, 0, 0, 0, 0, 0] }
        let mx = sx / weight, my = sy / weight
        return [weight, mx, my, sxx / weight - mx * mx, sxy / weight - mx * my, syy / weight - my * my]
    }

    static func clear(_ bytes: [UInt8]) -> Bool {
        !stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let pipeline = SceneSpotLightPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        func draw(_ plan: SceneSpotLightPlan = plan(), frame: simd_float4x4? = nil,
                  projection: simd_float4x4 = matrix_identity_float4x4, map: simd_float4x4? = nil,
                  alpha: Float? = nil) -> (accepted: Bool, peerAccepted: Bool, bytes: [UInt8]) {
            render(device: device, queue: queue, pipeline: pipeline, plan: plan,
                worldFrame: frame ?? SceneMatrix.translation(SIMD3(-0.8, 0, 0.5)),
                viewProjection: projection, map: map, alpha: alpha)
        }
        let first = draw(), same = draw(), narrow = draw(plan(outer: 2.91))
        let half = draw(alpha: 0.5), invisible = draw(alpha: 0)
        let zeroIntensity = draw(plan(intensity: 0))
        let zeroRadius = draw(plan(radius: 0)), zeroDensity = draw(plan(density: 0))
        let moved = draw(frame: SceneMatrix.translation(SIMD3(-0.8, -0.2, 0.5))
            * SceneMatrix.rotationZ(0.4))
        let bright = render(device: device, queue: queue, pipeline: pipeline, plan: plan(), background: 1)
        let red = render(device: device, queue: queue, pipeline: pipeline, plan: plan(), color: SIMD3(1, 0, 0))
        let parent = SceneMatrix.translation(SIMD3(0, -0.75, 0.5))
            * SceneMatrix.rotationZ(.pi / 2) * SceneMatrix.scale(SIMD3(2, 2, 1))
        let parented = draw(plan(radius: 0.6), frame: parent)
        let unscaled = draw(plan(radius: 0.6), frame: SceneMatrix.translation(SIMD3(0, -0.75, 0.5))
            * SceneMatrix.rotationZ(.pi / 2))
        let wide = plan(radius: 0.5, inner: 30, outer: 90)
        let source = draw(wide, frame: SceneMatrix.translation(SIMD3(-0.25, 0, 0.5)))
        let sheared = draw(wide, frame: SceneMatrix.translation(SIMD3(-0.6, -0.25, 0.5))
            * SceneMatrix.scale(SIMD3(2, 1, 1)) * SceneMatrix.rotationZ(.pi / 4))
        let mirror = draw(frame: SceneMatrix.translation(SIMD3(0.8, 0, 0.5))
            * SceneMatrix.scale(SIMD3(-1, 1, 1)))
        let map = simd_float4x4(columns: (SIMD4(2, 0, 0, 0), SIMD4(0, 2, 0, 0),
            SIMD4(0, 0, 9, 0), SIMD4(0, 0, 4, 2)))
        let mapped = draw(map: map)
        let perspective = SceneMatrix.perspectiveRHMetal(fovYRadians: .pi / 2,
            aspect: Float(width) / Float(height), near: 1, far: 10)
        let inside = draw(frame: SceneMatrix.translation(SIMD3(-0.8, 0, -2)), projection: perspective, map: map)
        let rootInside = draw(frame: SceneMatrix.translation(SIMD3(-0.8, 0, -2)), projection: perspective)
        let near = draw(frame: SceneMatrix.translation(SIMD3(-0.8, 0, -0.5)), projection: perspective, map: map)
        let far = draw(frame: SceneMatrix.translation(SIMD3(-0.8, 0, -11)), projection: perspective, map: map)
        var invalid = matrix_identity_float4x4
        invalid.columns.3.x = .nan
        let bad = draw(frame: invalid)
        let overflow = render(device: device, queue: queue, pipeline: pipeline, plan: plan(),
            worldFrame: SceneMatrix.scale(SIMD3(repeating: .greatestFiniteMagnitude)),
            peerFrame: SceneMatrix.translation(SIMD3(-0.8, 0, 0.5)))
        let visible = stride(from: 0, to: first.bytes.count, by: 4).filter { first.bytes[$0 + 3] > 3 }
        let alphaValues = visible.map { first.bytes[$0 + 3] }
        let featherPixels = alphaValues.filter { (4..<40).contains($0) }.count
        let corePixels = alphaValues.filter { $0 > 80 }.count
        let alphaScales = first.bytes.indices.allSatisfy {
            abs(Int(half.bytes[$0]) * 2 - Int(first.bytes[$0])) <= 2
        }
        let mirrored = (0..<height).allSatisfy { y in
            (0..<width).allSatisfy { x in
                (0..<4).allSatisfy { channel in
                    abs(Int(mirror.bytes[(y * width + x) * 4 + channel])
                        - Int(first.bytes[(y * width + width - 1 - x) * 4 + channel])) <= 1
                }
            }
        }
        let result: [String: Any] = [
            "metalUnavailable": false, "vertexStride": MemoryLayout<SceneQuadVertex>.stride,
            "accepted": [first, same, narrow, half, invisible, zeroIntensity, zeroRadius, zeroDensity,
                moved, parented, unscaled, source, sheared, mirror, mapped, inside, rootInside, near, far]
                .allSatisfy { $0.accepted },
            "visiblePixels": visible.count,
            "premultiplied": visible.allSatisfy {
                max(first.bytes[$0], first.bytes[$0 + 1], first.bytes[$0 + 2]) <= first.bytes[$0 + 3]
            },
            "semiTransparent": (alphaValues.max() ?? 255) < 128,
            "visibleEnergy": (alphaValues.max() ?? 0) > 80,
            "featheredEdge": featherPixels > corePixels,
            "preservesLitBackground": stride(from: 0, to: bright.bytes.count, by: 4).allSatisfy {
                bright.bytes[$0] == 255 && bright.bytes[$0 + 1] == 255 && bright.bytes[$0 + 2] == 255
            },
            "sameFramePixelsStable": same.bytes == first.bytes,
            "worldFrameMovesBeam": moved.bytes != first.bytes,
            "outerConeChangesWidth": narrow.bytes != first.bytes,
            "zeroInputsClear": [invisible, zeroIntensity, zeroRadius, zeroDensity].allSatisfy { clear($0.bytes) },
            "alphaScalesPMA": alphaScales && half.bytes != first.bytes,
            "dynamicColorChangesCone": red.accepted && red.bytes != first.bytes,
            "authoredBlue": visible.reduce(0) { $0 + Int(first.bytes[$1]) }
                > visible.reduce(0) { $0 + Int(first.bytes[$1 + 1]) },
            "parentBounds": bounds(parented.bytes), "unscaledBounds": bounds(unscaled.bytes),
            "rootMoments": moments(source.bytes), "shearMoments": moments(sheared.bytes),
            "mirroredPixels": mirror.accepted && mirrored,
            "mapIdentityPreservesRoot": mapped.bytes == first.bytes,
            "mapPreservesPerspectiveZW": inside.bytes == rootInside.bytes && !clear(inside.bytes),
            "nearFarClipped": clear(near.bytes) && clear(far.bytes),
            "invalidMatrixRejected": !bad.accepted && clear(bad.bytes),
            "overflowLocalToCone": !overflow.accepted && overflow.peerAccepted && overflow.bytes == first.bytes,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneSpotLightRenderingTests(unittest.TestCase):
    def test_soft_cone_uses_world_frame_and_is_premultiplied(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-spot-light-rendering-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-spot-light-rendering"
            vertex_source = (SCENE_ROOT / "Rendering/Metal/SceneMetalPipeline.swift").read_text()
            start = vertex_source.index("struct SceneQuadVertex {")
            vertex = vertex_source[start:vertex_source.index("\n}", start) + 2]
            harness.write_text(HARNESS.replace("// PRODUCTION_QUAD_VERTEX", vertex), encoding="utf-8")
            compilation = subprocess.run(
                ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-module-cache-path",
                 str(temporary / "module-cache"), *(str(path) for path in SOURCES),
                 str(harness), "-framework", "Metal", "-o", str(binary)],
                capture_output=True, text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        result = json.loads(completed.stdout)
        if result["metalUnavailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(result["vertexStride"], 24)
        for field in ("accepted", "premultiplied", "semiTransparent", "visibleEnergy", "featheredEdge",
                      "preservesLitBackground", "sameFramePixelsStable", "worldFrameMovesBeam",
                      "outerConeChangesWidth", "zeroInputsClear", "alphaScalesPMA", "dynamicColorChangesCone",
                      "authoredBlue", "mirroredPixels", "mapIdentityPreservesRoot", "mapPreservesPerspectiveZW",
                      "nearFarClipped", "invalidMatrixRejected", "overflowLocalToCone"):
            self.assertTrue(result[field], (field, result))
        self.assertGreater(result["visiblePixels"], 30, result)
        left, top, right, bottom = result["parentBounds"]
        self.assertGreaterEqual(left, 58, result)
        self.assertLessEqual(right, 69, result)
        self.assertGreaterEqual(top, 26, result)
        self.assertLess(top, 40, result)
        # Both cones share the apex at row boundary 84; thresholded coverage
        # can stop before that boundary while preserving the same apex.
        self.assertLessEqual(abs(bottom - result["unscaledBounds"][3]), 2, result)
        self.assertLessEqual(max(bottom, result["unscaledBounds"][3]), 84, result)
        self.assertGreater(result["unscaledBounds"][1] - top, 20, result)
        root, shear = result["rootMoments"], result["shearMoments"]
        self.assertGreater(root[0], 1000, result)
        self.assertGreater(shear[0], 1000, result)
        # Literal S(2,1) R(45deg) maps image moments; this oracle does not
        # reconstruct the renderer's model/MVP or approximate a cone shader.
        mx, my, xx, xy, yy = root[1] + 0.25, root[2], root[3], root[4], root[5]
        expected = [-0.6 + math.sqrt(2) * (mx - my), -0.25 + math.sqrt(0.5) * (mx + my),
                    2 * (xx + yy - 2 * xy), xx - yy, 0.5 * (xx + yy + 2 * xy)]
        for actual, target in zip(shear[1:], expected):
            self.assertAlmostEqual(actual, target, delta=0.002, msg=str(result))


if __name__ == "__main__":
    unittest.main()
