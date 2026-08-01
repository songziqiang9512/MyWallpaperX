#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Resources/SceneTextureSampling.swift",
    SCENE / "Effects/SceneMediaThumbnailTransitionPipeline.swift",
]

HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneMediaThumbnailTransitionTexture {
    struct Arguments {
        let texture: MTLTexture
        let uvScale: SIMD2<Float>
        let sampling: SceneTextureSampling
    }
}

guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue(),
      let pipeline = SceneMediaThumbnailTransitionPipeline(device: device) else {
    fatalError("Metal unavailable")
}

func texture(format: MTLPixelFormat, usage: MTLTextureUsage) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: 4, height: 1, mipmapped: false
    )
    descriptor.usage = usage
    descriptor.storageMode = .shared
    return device.makeTexture(descriptor: descriptor)!
}

let current = texture(format: .rgba8Unorm, usage: .shaderRead)
let previous = texture(format: .rgba8Unorm, usage: .shaderRead)
let gradient = texture(format: .r8Unorm, usage: .shaderRead)
let target = texture(format: .bgra8Unorm, usage: [.shaderRead, .renderTarget])
var currentBytes = Array(repeating: UInt8(0), count: 16)
var previousBytes = Array(repeating: UInt8(0), count: 16)
for index in 0..<4 {
    currentBytes[index * 4] = 255
    currentBytes[index * 4 + 3] = 255
    previousBytes[index * 4 + 2] = 255
    previousBytes[index * 4 + 3] = 255
}
var gradientBytes: [UInt8] = [0, 85, 170, 255]
current.replace(region: MTLRegionMake2D(0, 0, 4, 1), mipmapLevel: 0,
                withBytes: &currentBytes, bytesPerRow: 16)
previous.replace(region: MTLRegionMake2D(0, 0, 4, 1), mipmapLevel: 0,
                 withBytes: &previousBytes, bytesPerRow: 16)
gradient.replace(region: MTLRegionMake2D(0, 0, 4, 1), mipmapLevel: 0,
                 withBytes: &gradientBytes, bytesPerRow: 4)
let arguments = SceneMediaThumbnailTransitionTexture.Arguments(
    texture: gradient, uvScale: SIMD2(repeating: 1), sampling: .linearClamp
)

func render(amount: Float) -> [UInt8] {
    let commandBuffer = queue.makeCommandBuffer()!
    guard pipeline.encode(
        current: current, previous: previous, gradient: arguments, target: target,
        amount: amount, gradientScale: 0.05, commandBuffer: commandBuffer
    ) else { fatalError("encode rejected") }
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    guard commandBuffer.status == .completed else { fatalError("GPU failed") }
    var bytes = Array(repeating: UInt8(0), count: 16)
    target.getBytes(&bytes, bytesPerRow: 16,
                    from: MTLRegionMake2D(0, 0, 4, 1), mipmapLevel: 0)
    return bytes
}

let atPrevious = render(amount: 1)
let atCurrent = render(amount: 0)
let atMidpoint = render(amount: 0.5)
let result: [String: Any] = [
    "previous": atPrevious,
    "current": atCurrent,
    "midpoint": atMidpoint,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''


class SceneMediaThumbnailTransitionPipelineTests(unittest.TestCase):
    def test_gpu_endpoints_and_gradient_direction(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-media-transition-gpu-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "pipeline"
            subprocess.run(
                ["swiftc", *map(str, SOURCES), str(harness), "-o", str(binary)],
                check=True,
                cwd=ROOT,
            )
            result = json.loads(subprocess.check_output([str(binary)], text=True))

        previous = result["previous"]
        current = result["current"]
        midpoint = result["midpoint"]
        for offset in range(0, 16, 4):
            self.assertEqual(previous[offset : offset + 4], [255, 0, 0, 255])
            self.assertEqual(current[offset : offset + 4], [0, 0, 255, 255])
        self.assertGreater(midpoint[0], midpoint[2])
        self.assertGreater(midpoint[14], midpoint[12])


if __name__ == "__main__":
    unittest.main()
