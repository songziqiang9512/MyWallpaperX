#!/usr/bin/env python3
"""Water Flow must bind the phase texture's address mode at the Effect slot."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Effects/SceneWaterFlowPipeline.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneWaterFlowExecutionPlan {
    let speed: Float
    let strength: Float
    let phaseScale: Float
    let phaseFeather: Float?
}

@main
enum Harness {
    static let size = 32

    static func colorTexture(
        device: MTLDevice,
        renderTarget: Bool = false
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = renderTarget ? [.renderTarget, .shaderRead] : .shaderRead
        return device.makeTexture(descriptor: descriptor)!
    }

    static func dataTexture(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int,
        height: Int
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        return device.makeTexture(descriptor: descriptor)!
    }

    static func uploadSource(_ texture: MTLTexture) {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                let checker = ((x / 2) + (y / 2)).isMultiple(of: 2)
                bytes[offset] = UInt8((x * 7 + y * 3) % 256)
                bytes[offset + 1] = checker ? 230 : 24
                bytes[offset + 2] = UInt8((x * 5 + 40) % 256)
                bytes[offset + 3] = 255
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: &bytes,
            bytesPerRow: size * 4
        )
    }

    static func read(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return bytes
    }

    static func render(
        phaseSampling: SceneTextureSampling,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWaterFlowPipeline
    ) -> (Bool, [UInt8]) {
        let source = colorTexture(device: device)
        let target = colorTexture(device: device, renderTarget: true)
        let flow = dataTexture(device: device, format: .rg8Unorm, width: 1, height: 1)
        let phase = dataTexture(device: device, format: .r8Unorm, width: 2, height: 2)
        uploadSource(source)
        var flowBytes: [UInt8] = [255, 127]
        flow.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &flowBytes,
            bytesPerRow: 2
        )
        var phaseBytes: [UInt8] = [0, 255, 0, 255]
        phase.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: &phaseBytes,
            bytesPerRow: 2
        )
        let command = queue.makeCommandBuffer()!
        let encoded = pipeline.encode(
            source: source,
            flowTexture: flow,
            phaseTexture: phase,
            target: target,
            plan: .init(
                speed: 0.4,
                strength: 1,
                phaseScale: 2,
                phaseFeather: nil
            ),
            time: 0.73,
            maskUVScale: SIMD2(repeating: 1),
            flowSampling: .linearClamp,
            phaseSampling: phaseSampling,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        return (encoded && command.status == .completed, read(target))
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneWaterFlowPipeline(device: device) else {
            print("SKIP")
            return
        }
        let clamp = render(
            phaseSampling: .linearClamp,
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let repeating = render(
            phaseSampling: .linearRepeat,
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let changed = (0..<(size * size)).filter { pixel in
            let offset = pixel * 4
            return clamp.1[offset..<(offset + 4)] != repeating.1[offset..<(offset + 4)]
        }.count
        let result: [String: Any] = [
            "encoded": clamp.0 && repeating.0,
            "changedPixels": changed,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneWaterFlowTextureSamplingTests(unittest.TestCase):
    def test_phase_address_mode_changes_real_waterflow_pixels(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-waterflow-sampling-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "waterflow-sampling-test"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
        if completed.stdout.strip() == "SKIP":
            self.skipTest("Metal is unavailable")
        result = json.loads(completed.stdout)
        self.assertTrue(result["encoded"], result)
        self.assertGreater(result["changedPixels"], 128, result)


if __name__ == "__main__":
    unittest.main()
