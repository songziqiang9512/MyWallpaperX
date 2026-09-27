#!/usr/bin/env python3
"""Stock-noise distribution, GPU mip readiness, and failed-upload publication."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_sampler_default_purpose import (
    REPOSITORY_ROOT, SUPPORT, SWIFT_SOURCES,
)

STORE = REPOSITORY_ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/"
    "SceneStockNoiseTextureStore.swift"
)

# Forward real Metal work while injecting failures at the API boundary. No
# product algorithm is reimplemented and no GPU fault is induced on the device.
PROXY_HEADER = r'''
#import <Metal/Metal.h>
id<MTLDevice> noiseFaultDevice(id<MTLDevice> device, NSInteger mode);
NSInteger noiseTextureCount(void);
NSInteger noiseCommandCount(void);
NSInteger noiseWaitCount(void);
void noiseResetCounts(void);
'''
PROXY = r'''
#import "Fault.h"
#import <Foundation/Foundation.h>
static NSInteger textureCount, commandCount, waitCount;
NSInteger noiseTextureCount(void) { return textureCount; }
NSInteger noiseCommandCount(void) { return commandCount; }
NSInteger noiseWaitCount(void) { return waitCount; }
void noiseResetCounts(void) { textureCount = commandCount = waitCount = 0; }
@interface NoiseFaultProxy : NSProxy
@property(strong) id target;
@property NSInteger mode;
@end
static id wrap(id target, NSInteger mode) {
    NoiseFaultProxy *proxy = [NoiseFaultProxy alloc];
    proxy.target = target; proxy.mode = mode;
    return proxy;
}
@implementation NoiseFaultProxy
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [self.target methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:self.target];
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor {
    textureCount++;
    return [self.target newTextureWithDescriptor:descriptor];
}
- (void)waitUntilCompleted {
    [self.target waitUntilCompleted];
    waitCount++;
}
- (id<MTLCommandQueue>)newCommandQueue {
    return wrap([self.target newCommandQueue], self.mode);
}
- (id<MTLCommandBuffer>)commandBuffer {
    commandCount++;
    return wrap([self.target commandBuffer], self.mode);
}
- (id<MTLBlitCommandEncoder>)blitCommandEncoder {
    if (self.mode == 1) return nil;
    return [self.target blitCommandEncoder];
}
- (MTLCommandBufferStatus)status {
    if (self.mode == 2) return MTLCommandBufferStatusError;
    return [self.target status];
}
- (NSError *)error {
    if (self.mode == 3) return [NSError errorWithDomain:@"NoiseTest" code:1 userInfo:nil];
    return [self.target error];
}
@end
id<MTLDevice> noiseFaultDevice(id<MTLDevice> device, NSInteger mode) {
    return wrap(device, mode);
}
'''
HARNESS = r'''
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw NSError(domain: "MetalUnavailable", code: 1)
        }
        let demands = SceneStockTextureSemanticRegistry.noiseTexturePaths.map {
            SceneSystemProviderTextureIdentity(name: $0, purpose: .noise)
        }
        let assets = Dictionary(uniqueKeysWithValues: demands.map {
            (SceneAssetTextureIdentity(virtualPath: $0.name, purpose: .noise)!, SceneAssetTextureLaunchState.absent)
        })
        let observedDevice = noiseFaultDevice(device, 0)!
        noiseResetCounts()
        let store = try SceneStockNoiseTextureStore(assetStates: assets, device: observedDevice)
        var preparation: [String: Bool] = [
            "singleBatch": noiseTextureCount() == 6 && noiseCommandCount() == 1 && noiseWaitCount() == 1,
            "deviceIdentity": store.deviceRegistryID == device.registryID,
        ]
        let independent = try SceneStockNoiseTextureStore(assetStates: assets, device: device)
        var summaries: [String: Any] = [:]
        // Read via GPU blit into shared memory, so managed GPU mip writes are
        // observed without assuming CPU/GPU coherence of the texture storage.
        func read(_ texture: MTLTexture, level: Int) -> [UInt8] {
            let width = max(1, texture.width >> level)
            let height = max(1, texture.height >> level)
            let row = 256
            let output = device.makeBuffer(length: row * height, options: .storageModeShared)!
            let command = queue.makeCommandBuffer()!
            let blit = command.makeBlitCommandEncoder()!
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: level,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: output, destinationOffset: 0,
                      destinationBytesPerRow: row, destinationBytesPerImage: row * height)
            blit.endEncoding()
            command.commit(); command.waitUntilCompleted()
            precondition(command.status == .completed && command.error == nil)
            let bytes = output.contents().assumingMemoryBound(to: UInt8.self)
            return (0..<height).flatMap { y in (0..<width).map { bytes[y * row + $0] } }
        }
        for demand in demands {
            guard case let .ready(first)? = store.states[demand],
                  case let .ready(next)? = store.states[demand],
                  case let .ready(other)? = independent.states[demand] else {
                throw NSError(domain: "PublicationMissing", code: 2)
            }
            let pixels = read(first.texture, level: 0)
            let mean = Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count)
            let mips = (0..<first.texture.mipmapLevelCount).map { level in
                let data = read(first.texture, level: level)
                return Double(data.reduce(0) { $0 + Int($1) }) / Double(data.count)
            }
            summaries[demand.name] = [
                "complete": first.isComplete,
                "cached": first.texture === next.texture && first.isSameAtom(as: next),
                "deterministic": pixels == read(other.texture, level: 0),
                "nextFrameStable": pixels == read(next.texture, level: 0),
                "mean": mean, "min": pixels.min()!, "max": pixels.max()!,
                "upperHalfFraction": Double(pixels.filter { $0 >= 128 }.count) / Double(pixels.count),
                "mipMeans": mips,
            ]
        }
        let demand = demands.first { $0.name == "util/uniform_256" }!
        let asset = SceneAssetTextureIdentity(virtualPath: demand.name, purpose: .noise)!
        var failures: [String: Bool] = [:]
        for mode in 1...3 {
            let proxy = noiseFaultDevice(device, mode)!
            let failedStore = try SceneStockNoiseTextureStore(assetStates: [asset: .absent], device: proxy)
            if case .unavailable? = failedStore.states[demand] { failures["rejected\(mode)"] = true }
            else { failures["rejected\(mode)"] = false }
            // Only a new explicit preparation retries failed resources.
            let retry = try SceneStockNoiseTextureStore(assetStates: [asset: .absent], device: device)
            if case let .ready(publication)? = retry.states[demand] {
                failures["recovered\(mode)"] = publication.isComplete
            } else { failures["recovered\(mode)"] = false }
        }
        noiseResetCounts()
        let one = try SceneStockNoiseTextureStore(assetStates: [asset: .absent], device: observedDevice)
        preparation["demandOnly"] = one.states.count == 1 && noiseTextureCount() == 1
        let texturesBeforeFrames = noiseTextureCount()
        let commandsBeforeFrames = noiseCommandCount()
        let waitsBeforeFrames = noiseWaitCount()
        let firstSurface = SceneFrameTextureRegistry()
        let secondSurface = SceneFrameTextureRegistry()
        var sameTexture = true
        for frame: UInt64 in 1...120 {
            for registry in [firstSurface, secondSurface] {
                registry.beginFrame(frameIndex: frame, layerSources: [:], systemProviderStates: one.states)
                guard case let .ready(expected)? = one.states[demand],
                      let actual = registry.resource(for: .system(demand)) else {
                    sameTexture = false; continue
                }
                sameTexture = sameTexture && actual.publication.isSameAtom(as: expected)
                registry.commitFramePublication()
            }
        }
        preparation["sharedAcrossSurfaces"] = sameTexture
        preparation["noFrameUploads"] = noiseTextureCount() == texturesBeforeFrames
            && noiseCommandCount() == commandsBeforeFrames && noiseWaitCount() == waitsBeforeFrames
        noiseResetCounts()
        let absent = try SceneStockNoiseTextureStore(assetStates: [:], device: observedDevice)
        let unavailable = try SceneStockNoiseTextureStore(assetStates: [asset: .unavailable], device: observedDevice)
        let ready = try SceneStockNoiseTextureStore(assetStates: [asset: .ready(.data)], device: observedDevice)
        let pending = try SceneStockNoiseTextureStore(assetStates: [asset: .pending], device: observedDevice)
        let wrongPurpose = try SceneStockNoiseTextureStore(
            assetStates: [SceneAssetTextureIdentity(virtualPath: demand.name, purpose: .mask)!: .absent],
            systemDemands: [.init(name: demand.name, purpose: .mask), .init(name: "unknown/noise", purpose: .noise)],
            device: observedDevice)
        preparation["noUnauthorizedSubstitution"] = [absent, unavailable, ready, pending, wrongPurpose]
            .allSatisfy { $0.states.isEmpty } && noiseTextureCount() == 0 && noiseCommandCount() == 0
        let explicit = try SceneStockNoiseTextureStore(
            assetStates: [:], systemDemands: [demand], device: observedDevice)
        preparation["explicitSystemDemand"] = explicit.states.count == 1
        enum Cancel: Error { case requested }
        noiseResetCounts()
        do {
            _ = try SceneStockNoiseTextureStore(assetStates: assets, device: observedDevice,
                cancellationCheck: { if noiseTextureCount() > 0 { throw Cancel.requested } })
            preparation["cancelBeforeSubmission"] = false
        } catch Cancel.requested {
            preparation["cancelBeforeSubmission"] = noiseTextureCount() == 1 && noiseCommandCount() == 0
        }
        noiseResetCounts()
        do {
            _ = try SceneStockNoiseTextureStore(assetStates: [asset: .absent], device: observedDevice,
                cancellationCheck: { if noiseWaitCount() > 0 { throw Cancel.requested } })
            preparation["cancelAfterCompletion"] = false
        } catch Cancel.requested {
            preparation["cancelAfterCompletion"] = noiseWaitCount() == 1
        }
        let result: [String: Any] = ["textures": summaries, "failures": failures, "preparation": preparation]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
'''


def run_harness(store: Path = STORE) -> dict:
    with tempfile.TemporaryDirectory(prefix="mwx-stock-noise-") as directory:
        root = Path(directory)
        for name, content in (("Support.swift", SUPPORT), ("Harness.swift", HARNESS),
                              ("Fault.h", PROXY_HEADER), ("Fault.m", PROXY)):
            (root / name).write_text(content)
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        commands = [
            ["xcrun", "clang", "-fobjc-arc", "-c", str(root / "Fault.m"), "-o", str(root / "Fault.o")],
            ["xcrun", "swiftc", "-parse-as-library", str(root / "Support.swift"),
             *(str(path) for path in SWIFT_SOURCES), str(store), str(root / "Harness.swift"),
             str(root / "Fault.o"), "-import-objc-header", str(root / "Fault.h"),
             "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
             "-module-cache-path", str(root / "module-cache"), "-o", str(root / "harness")],
            [str(root / "harness")],
        ]
        for command in commands:
            result = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
                                    capture_output=True, text=True, timeout=180)
            if result.returncode:
                raise RuntimeError(result.stderr or result.stdout)
        return json.loads(result.stdout)


class StockNoiseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.result = run_harness()

    def test_uniform_noise_uses_full_normalized_range(self) -> None:
        for name in ("util/noise", "util/uniform_256"):
            texture = self.result["textures"][name]
            with self.subTest(name=name):
                self.assertLess(texture["min"], 5)
                self.assertGreater(texture["max"], 250)
                self.assertTrue(120 < texture["mean"] < 135, texture)
                self.assertTrue(0.45 < texture["upperHalfFraction"] < 0.55, texture)

    def test_cloud_noise_is_not_confined_to_lower_half(self) -> None:
        for name in ("util/clouds_256", "util/perlin_256"):
            texture = self.result["textures"][name]
            with self.subTest(name=name):
                self.assertGreater(texture["max"], 160)
                self.assertGreater(texture["upperHalfFraction"], 0.1)

    def test_publications_are_complete_stable_and_have_initialized_mips(self) -> None:
        self.assertEqual(len(self.result["textures"]), 6)
        for name, texture in self.result["textures"].items():
            with self.subTest(name=name):
                for key in ("complete", "cached", "deterministic", "nextFrameStable"):
                    self.assertTrue(texture[key], key)
                self.assertEqual(len(texture["mipMeans"]), 9)
                for mean in texture["mipMeans"]:
                    self.assertLess(abs(mean - texture["mean"]), 5, texture)

    def test_preparation_is_demand_scoped_shared_and_cancellable(self) -> None:
        self.assertTrue(all(self.result["preparation"].values()), self.result["preparation"])

    def test_upload_failures_do_not_publish_or_poison_cache(self) -> None:
        self.assertTrue(all(self.result["failures"].values()), self.result["failures"])


if __name__ == "__main__":
    unittest.main()
