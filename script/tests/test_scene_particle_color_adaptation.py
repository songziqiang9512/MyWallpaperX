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
        let queue = device.makeCommandQueue()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void readColor(texture2d<float, access::read> texture [[texture(0)]],
                              device float4 *out [[buffer(0)]],
                              constant uint &level [[buffer(1)]], uint2 xy [[thread_position_in_grid]]) {
            if (xy.x < texture.get_width(level) && xy.y < texture.get_height(level))
                out[xy.y * texture.get_width(level) + xy.x] = texture.read(xy, level);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "readColor")!)
        func pixels(_ texture: MTLTexture, level: Int = 0) -> [UInt8] {
            let width = max(1, texture.width >> level), height = max(1, texture.height >> level)
            let output = device.makeBuffer(length: width * height * 16, options: .storageModeShared)!
            let command = queue.makeCommandBuffer()!, encoder = command.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(pipeline); encoder.setTexture(texture, index: 0)
            encoder.setBuffer(output, offset: 0, index: 0)
            var mip = UInt32(level); encoder.setBytes(&mip, length: 4, index: 1)
            encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            guard command.status == .completed else { return [] }
            let values = output.contents().bindMemory(to: Float.self, capacity: width * height * 4)
            return (0..<width * height * 4).map { UInt8(clamping: Int((values[$0] * 255).rounded())) }
        }
        let valid = SceneParticleColorTextureAdapter.adapt(rg8)!
        let pixel = pixels(valid)
        let copy = queue.makeCommandBuffer()!, blit = copy.makeBlitCommandEncoder()!
        blit.copy(from: rg8, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0,y: 0,z: 0),
                  sourceSize: MTLSize(width: 1,height: 1,depth: 1), to: privateRG8,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0,y: 0,z: 0))
        blit.endEncoding(); copy.commit(); copy.waitUntilCompleted()
        let privateView = SceneParticleColorTextureAdapter.adapt(privateRG8)!
        let privateStoragePreserved = copy.status == .completed && pixels(privateView) == pixel
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
                let color = UInt8(luminance)
                expected += [color, color, color, UInt8(alpha)]
            }
            source.withUnsafeBytes { bytes in
                atlas.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: level,
                              withBytes: bytes.baseAddress!, bytesPerRow: width * 2)
            }
            expectedLevels.append(expected)
        }
        let converted = SceneParticleColorTextureAdapter.adapt(atlas)!
        let mipPixelsPreserved = converted.mipmapLevelCount == atlas.mipmapLevelCount
            && (0..<atlas.mipmapLevelCount).allSatisfy { level in
                return pixels(converted, level: level) == expectedLevels[level]
            }
        MWXRejectColorResources(device, r8)
        let rejectedR: MTLTexture? = SceneParticleColorTextureAdapter.adapt(r8)
        let rejectedRG: MTLTexture? = SceneParticleColorTextureAdapter.adapt(rg8)
        let unchanged: MTLTexture? = SceneParticleColorTextureAdapter.adapt(rgba)
        let result: [String: Any] = [
            "validPixel": pixel,
            "mipPixelsPreserved": mipPixelsPreserved,
            "privateStoragePreserved": privateStoragePreserved,
            "viewFailureRejected": rejectedR == nil,
            "rgViewFailureRejected": rejectedRG == nil,
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
        self.assertEqual(result["validPixel"], [200, 200, 200, 128])
        self.assertTrue(result["mipPixelsPreserved"])
        for key in ("privateStoragePreserved", "viewFailureRejected",
                    "rgViewFailureRejected", "rgbaPreserved"):
            with self.subTest(case=key):
                self.assertTrue(result[key])


if __name__ == "__main__":
    unittest.main()
