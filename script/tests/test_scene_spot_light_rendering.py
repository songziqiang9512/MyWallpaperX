#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Effects/SceneSpotLightPipeline.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
}

struct SceneSpotLightPlan {
    let color: SIMD3<Float>
    let intensity: Float
    let radius: Float
    let innerConeRadians: Float
    let outerConeRadians: Float
    let density: Float
    let exponent: Float
    let volumetricsExponent: Float
    let baseAngle: Float

    func authoredAngle(at sceneTime: Double) -> Float? {
        baseAngle + Float(sceneTime) * 0.2
    }
}

@main
enum Harness {
    static let width = 128
    static let height = 96

    static func plan(outerDegrees: Float = 5.72) -> SceneSpotLightPlan {
        .init(
            color: SIMD3(0.34118, 0.36078, 0.49804),
            intensity: 80,
            radius: 1.55,
            innerConeRadians: 1.87 * .pi / 180,
            outerConeRadians: outerDegrees * .pi / 180,
            density: 3.93,
            exponent: 2.68,
            volumetricsExponent: 2.82,
            baseAngle: .pi / 2
        )
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneSpotLightPipeline,
        plan: SceneSpotLightPlan,
        time: Double,
        origin: SIMD2<Float> = SIMD2(-0.55, 0.82),
        background: Float = 0
    ) -> (accepted: Bool, bytes: [UInt8]) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        let target = device.makeTexture(descriptor: descriptor)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(
            Double(background), Double(background), Double(background), 0
        )
        pass.colorAttachments[0].storeAction = .store
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        let accepted = pipeline.draw(
            plan: plan,
            worldOrigin: origin,
            viewProjection: matrix_identity_float4x4,
            sceneTime: time,
            encoder: encoder
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(
            &bytes,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return (accepted, bytes)
    }

    static func alphaTotal(_ bytes: [UInt8], rows: Range<Int>) -> Int {
        var total = 0
        for y in rows {
            for x in 0..<width {
                total += Int(bytes[(y * width + x) * 4 + 3])
            }
        }
        return total
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneSpotLightPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let first = render(device: device, queue: queue, pipeline: pipeline, plan: plan(), time: 0)
        let second = render(device: device, queue: queue, pipeline: pipeline, plan: plan(), time: 2)
        let narrow = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            plan: plan(outerDegrees: 2.91),
            time: 0
        )
        let invalid = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            plan: plan(),
            time: 0,
            origin: SIMD2(.nan, 0)
        )
        let brightBackground = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            plan: plan(),
            time: 0,
            background: 1
        )
        let visibleOffsets = stride(from: 0, to: first.bytes.count, by: 4).filter {
            first.bytes[$0 + 3] > 3
        }
        let premultiplied = visibleOffsets.allSatisfy { offset in
            max(first.bytes[offset], first.bytes[offset + 1], first.bytes[offset + 2])
                <= first.bytes[offset + 3]
        }
        let alphaValues = visibleOffsets.map { first.bytes[$0 + 3] }
        let featherPixels = alphaValues.filter { (4..<40).contains($0) }.count
        let corePixels = alphaValues.filter { $0 > 80 }.count
        let blue = visibleOffsets.reduce(0) { $0 + Int(first.bytes[$1]) }
        let green = visibleOffsets.reduce(0) { $0 + Int(first.bytes[$1 + 1]) }
        let result: [String: Any] = [
            "metalUnavailable": false,
            "accepted": first.accepted && second.accepted && narrow.accepted,
            "invalidRejected": !invalid.accepted,
            "visiblePixels": visibleOffsets.count,
            "premultiplied": premultiplied,
            "semiTransparent": (alphaValues.max() ?? 255) < 128,
            "visibleEnergy": (alphaValues.max() ?? 0) > 80,
            "featheredEdge": featherPixels > corePixels,
            "preservesLitBackground": stride(
                from: 0, to: brightBackground.bytes.count, by: 4
            ).allSatisfy {
                brightBackground.bytes[$0] == 255
                    && brightBackground.bytes[$0 + 1] == 255
                    && brightBackground.bytes[$0 + 2] == 255
            },
            "projectsUpward": alphaTotal(first.bytes, rows: 0..<(height / 2))
                > alphaTotal(first.bytes, rows: (height * 3 / 4)..<height),
            "timelineMovesBeam": first.bytes != second.bytes,
            "outerConeChangesWidth": first.bytes != narrow.bytes,
            "authoredBlue": blue > green,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneSpotLightRenderingTests(unittest.TestCase):
    def test_soft_cone_is_visible_animated_and_premultiplied(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-spot-light-rendering-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-spot-light-rendering"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                ["xcrun", "--sdk", "macosx", "swiftc", *(str(path) for path in SOURCES), str(harness), "-framework", "Metal", "-o", str(binary)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        result = json.loads(completed.stdout)
        if result["metalUnavailable"]:
            self.skipTest("Metal is unavailable")
        self.assertTrue(result["accepted"], result)
        self.assertTrue(result["invalidRejected"], result)
        self.assertGreater(result["visiblePixels"], 30, result)
        self.assertTrue(result["premultiplied"], result)
        self.assertTrue(result["semiTransparent"], result)
        self.assertTrue(result["visibleEnergy"], result)
        self.assertTrue(result["featheredEdge"], result)
        self.assertTrue(result["preservesLitBackground"], result)
        self.assertTrue(result["projectsUpward"], result)
        self.assertTrue(result["timelineMovesBeam"], result)
        self.assertTrue(result["outerConeChangesWidth"], result)
        self.assertTrue(result["authoredBlue"], result)


if __name__ == "__main__":
    unittest.main()
