#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticlePeriodicEmission.swift",
    SOURCE_ROOT / "Particles/SceneParticleLayerImageEmissionMap.swift",
]

HARNESS_SOURCE = r'''
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 2, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        var bytes = [UInt8](repeating: 0, count: 4 * 2 * 4)
        bytes[3] = 255
        bytes[(7 * 4) + 3] = 255
        bytes.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, 4, 2), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 16
            )
        }
        let map = SceneParticleLayerImageEmissionMap(
            texture: texture, sourceSize: SIMD2(40, 20)
        )!

        let transparent = device.makeTexture(descriptor: descriptor)!
        [UInt8](repeating: 0, count: 32).withUnsafeBytes {
            transparent.replace(
                region: MTLRegionMake2D(0, 0, 4, 2), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 16
            )
        }
        let privateDescriptor = descriptor.copy() as! MTLTextureDescriptor
        privateDescriptor.storageMode = .private
        let privateTexture = device.makeTexture(descriptor: privateDescriptor)!
        let result: [String: Any] = [
            "positions": map.positions.map { [$0.x, $0.y, $0.z] },
            "transparentRejected": SceneParticleLayerImageEmissionMap(
                texture: transparent, sourceSize: SIMD2(40, 20)
            ) == nil,
            "privateRejected": SceneParticleLayerImageEmissionMap(
                texture: privateTexture, sourceSize: SIMD2(40, 20)
            ) == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneParticleLayerImageEmitterTests(unittest.TestCase):
    def test_alpha_pixels_map_to_centered_layer_local_positions(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-layer-image-emitter-") as raw_directory:
            directory = Path(raw_directory)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS_SOURCE, encoding="utf-8")
            binary = directory / "layer-image"
            subprocess.run(
                ["swiftc", *(str(path) for path in SOURCES), str(harness), "-o", str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
        if not completed.stdout.strip():
            self.skipTest("Metal device is unavailable")
        result = json.loads(completed.stdout)
        self.assertEqual(result["positions"], [[-15, 5, 0], [15, -5, 0]])
        self.assertTrue(result["transparentRejected"])
        self.assertTrue(result["privateRejected"])


if __name__ == "__main__":
    unittest.main()
