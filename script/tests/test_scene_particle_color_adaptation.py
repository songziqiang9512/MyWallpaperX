#!/usr/bin/env python3
"""Verify particle color adaptation rejects unusable Metal results."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
HEADER = '#import <Metal/Metal.h>\nvoid MWXRejectColorResources(id<MTLDevice>, id<MTLTexture>);\n'
FAULTS = r'''
#import <Metal/Metal.h>
#import <objc/runtime.h>

static id rejectTexture(id self, SEL selector, MTLTextureDescriptor *descriptor) {
    return nil;
}
static id rejectView(id self, SEL selector, MTLPixelFormat format, MTLTextureType type,
                     NSRange levels, NSRange slices, MTLTextureSwizzleChannels swizzle) {
    return nil;
}
void MWXRejectColorResources(id<MTLDevice> device, id<MTLTexture> texture) {
    SEL allocation = @selector(newTextureWithDescriptor:);
    SEL view = @selector(newTextureViewWithPixelFormat:textureType:levels:slices:swizzle:);
    Class deviceClass = object_getClass(device), textureClass = object_getClass(texture);
    class_replaceMethod(deviceClass, allocation, (IMP)rejectTexture,
        method_getTypeEncoding(class_getInstanceMethod(deviceClass, allocation)));
    class_replaceMethod(textureClass, view, (IMP)rejectView,
        method_getTypeEncoding(class_getInstanceMethod(textureClass, view)));
}
'''
HARNESS = r'''
import Foundation
import Metal

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        func make(_ format: MTLPixelFormat, storage: MTLStorageMode = .shared) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: 1, height: 1, mipmapped: false
            )
            descriptor.storageMode = storage
            descriptor.usage = .shaderRead
            return device.makeTexture(descriptor: descriptor)!
        }
        let r8 = make(.r8Unorm)
        let rg8 = make(.rg8Unorm)
        let privateRG8 = make(.rg8Unorm, storage: .private)
        let rgba = make(.rgba8Unorm)
        var r: UInt8 = 200
        r8.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                   withBytes: &r, bytesPerRow: 1)
        var rg: [UInt8] = [200, 128]
        rg8.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: &rg, bytesPerRow: 2)
        let valid: MTLTexture? = SceneParticleColorTextureAdapter.adapt(rg8, device: device)
        var pixel = [UInt8](repeating: 0, count: 4)
        valid?.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        let unsupported: MTLTexture? = SceneParticleColorTextureAdapter.adapt(privateRG8, device: device)
        let atlasDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm, width: 513, height: 197, mipmapped: true
        )
        atlasDescriptor.storageMode = .shared
        atlasDescriptor.usage = .shaderRead
        let atlas = device.makeTexture(descriptor: atlasDescriptor)!
        var expectedLevels: [[UInt8]] = []
        for level in 0..<atlas.mipmapLevelCount {
            let width = max(1, atlas.width >> level)
            let height = max(1, atlas.height >> level)
            var source: [UInt8] = []
            var expected: [UInt8] = []
            for index in 0..<(width * height) {
                let luminance = (index + level * 17) % 256
                let alpha = (index / width * 31 + index * 7 + level) % 256
                source += [UInt8(luminance), UInt8(alpha)]
                let color = UInt8((luminance * alpha + 127) / 255)
                expected += [color, color, color, UInt8(alpha)]
            }
            source.withUnsafeBytes { bytes in
                atlas.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: level,
                              withBytes: bytes.baseAddress!, bytesPerRow: width * 2)
            }
            expectedLevels.append(expected)
        }
        let converted = SceneParticleColorTextureAdapter.adapt(atlas, device: device)!
        let mipPixelsPreserved = converted.mipmapLevelCount == atlas.mipmapLevelCount
            && (0..<atlas.mipmapLevelCount).allSatisfy { level in
                let width = max(1, atlas.width >> level)
                let height = max(1, atlas.height >> level)
                var actual = [UInt8](repeating: 0, count: width * height * 4)
                converted.getBytes(&actual, bytesPerRow: width * 4,
                                   from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: level)
                return actual == expectedLevels[level]
            }
        MWXRejectColorResources(device, r8)
        let rejectedR: MTLTexture? = SceneParticleColorTextureAdapter.adapt(r8, device: device)
        let rejectedRG: MTLTexture? = SceneParticleColorTextureAdapter.adapt(rg8, device: device)
        let unchanged: MTLTexture? = SceneParticleColorTextureAdapter.adapt(rgba, device: device)
        let result: [String: Any] = [
            "validPixel": pixel,
            "mipPixelsPreserved": mipPixelsPreserved,
            "unsupportedStorageRejected": unsupported == nil,
            "viewFailureRejected": rejectedR == nil,
            "allocationFailureRejected": rejectedRG == nil,
            "rgbaPreserved": unchanged === rgba,
        ]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result))
    }
}
'''


class SceneParticleColorAdaptationTests(unittest.TestCase):
    def test_color_contract_survives_resource_failures(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-particle-color-") as folder:
            root = Path(folder)
            (root / "faults.h").write_text(HEADER)
            (root / "faults.m").write_text(FAULTS)
            (root / "harness.swift").write_text(HARNESS)
            commands = [
                ["clang", "-c", str(root / "faults.m"), "-o", str(root / "faults.o")],
                ["swiftc", "-import-objc-header", str(root / "faults.h"),
                 str(SCENE / "Resources/Textures/SceneTextureSampling.swift"),
                 str(SCENE / "Systems/Particles/SceneParticleTextureSource.swift"),
                 str(root / "harness.swift"), str(root / "faults.o"), "-o", str(root / "harness")],
            ]
            for command in commands:
                run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                self.assertEqual(run.returncode, 0, run.stderr)
            run = subprocess.run([str(root / "harness")], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            if run.stdout.strip() == "SKIP":
                self.skipTest("Metal unavailable")
            result = json.loads(run.stdout)
        self.assertEqual(result["validPixel"], [100, 100, 100, 128])
        self.assertTrue(result["mipPixelsPreserved"])
        for key in ("unsupportedStorageRejected", "viewFailureRejected",
                    "allocationFailureRejected", "rgbaPreserved"):
            with self.subTest(case=key):
                self.assertTrue(result[key])


if __name__ == "__main__":
    unittest.main()
