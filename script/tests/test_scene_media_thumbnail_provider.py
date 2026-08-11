#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Runtime/SceneMediaThumbnailInbox.swift",
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE / "Resources/SceneTextureSampling.swift",
    SCENE / "Resources/SceneTextureUVTransform.swift",
    SCENE / "Resources/SceneTextureCandidate.swift",
    SCENE / "Resources/SceneNamedTextureReference.swift",
    SCENE / "Resources/SceneTextureSlotBinding.swift",
    SCENE / "Resources/SceneTextureProviderPublication.swift",
    SCENE / "Resources/SceneFrameTextureRegistry.swift",
    SCENE / "Resources/SceneImageTextureUploader.swift",
    SCENE / "Resources/SceneMediaThumbnailTextureStore.swift",
]

HARNESS = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

struct SceneMediaThumbnailBindingProgram {
    static let currentIdentity = "$mediaThumbnail"
}

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

func png(red: UInt8, green: UInt8, blue: UInt8) -> Data {
    let bytes = [red, green, blue, 255]
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(
        width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent
    )!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

func pixel(_ texture: MTLTexture?) -> [UInt8] {
    guard let texture else { return [] }
    var bytes = [UInt8](repeating: 0, count: 4)
    texture.getBytes(
        &bytes,
        bytesPerRow: 4,
        from: MTLRegionMake2D(0, 0, 1, 1),
        mipmapLevel: 0
    )
    return bytes
}

func waitFor(_ store: SceneMediaThumbnailTextureStore, generation: UInt64) -> SceneMediaThumbnailTextureStore.Snapshot {
    for _ in 0..<200 {
        let snapshot = store.snapshot()
        if snapshot.generation == generation { return snapshot }
        Thread.sleep(forTimeInterval: 0.005)
    }
    return store.snapshot()
}

final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func decode(_ data: Data) -> CGImage? {
        lock.lock()
        count += 1
        lock.unlock()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal unavailable")
}
let inbox = SceneMediaThumbnailInbox()
let decodingQueue = DispatchQueue(label: "fixture.media-thumbnail")
decodingQueue.suspend()
let decodeCounter = DecodeCounter()
let store = SceneMediaThumbnailTextureStore(
    device: device,
    decodingQueue: decodingQueue,
    imageDecoder: decodeCounter.decode
)
let a = png(red: 255, green: 0, blue: 0)
let b = png(red: 0, green: 255, blue: 0)
let c = png(red: 0, green: 0, blue: 255)

_ = inbox.publish(a)
store.update(from: inbox.latest())
_ = inbox.publish(b)
store.update(from: inbox.latest())
_ = inbox.publish(c)
store.update(from: inbox.latest())
decodingQueue.resume()
let third = waitFor(store, generation: 3)
let layerRequest = SceneFrameTextureIdentity.layerSource(77)
let layerPublication = third.current?.publication(for: layerRequest)
let rapidDecodeCount = decodeCounter.value
let duplicateAccepted = inbox.publish(c)
let duplicateGeneration = inbox.latest().generation
let oversizedRejected = !inbox.publish(
    Data(count: SceneMediaThumbnailInbox.maximumEncodedByteCount + 1)
)

decodingQueue.suspend()
_ = inbox.publish(a)
store.update(from: inbox.latest())
let retainedDuringPending = store.snapshot()
decodingQueue.resume()
let fourth = waitFor(store, generation: 4)

decodingQueue.suspend()
_ = inbox.publish(Data([0, 1, 2, 3]))
store.update(from: inbox.latest())
let retainedDuringDecodeFailure = store.snapshot()
decodingQueue.resume()
let failed = waitFor(store, generation: 5)

inbox.clear()
store.update(from: inbox.latest())
let cleared = waitFor(store, generation: 6)

let result: [String: Any] = [
    "generation": third.generation,
    "currentPixel": pixel(third.current?.texture),
    "currentPublicationComplete": third.current?.isComplete == true,
    "currentRequestExact": third.current?.requestIdentity
        == .system(SceneMediaThumbnailBindingProgram.currentIdentity),
    "systemAndLayerRequestsAreDistinctAtoms":
        layerPublication?.requestIdentity == layerRequest
        && layerPublication?.requestIdentity != third.current?.requestIdentity
        && layerPublication?.texture === third.current?.texture
        && layerPublication?.contentGeneration == third.current?.contentGeneration,
    "currentPublicationPremultiplied":
        third.current?.candidate.purpose == .premultipliedColor
        && third.current?.candidate.content
            == .color(.resolved(.premultipliedAlpha))
        && third.current?.candidate.identity
            == .provider(.mediaThumbnailCurrent)
        && third.current?.candidate.generation
            == .provider(contentGeneration: third.generation),
    "rapidDecodeCount": rapidDecodeCount,
    "duplicateAccepted": duplicateAccepted,
    "duplicateGenerationStable": duplicateGeneration == 3,
    "oversizedRejected": oversizedRejected,
    "pendingGeneration": retainedDuringPending.generation,
    "pendingCurrentPixel": pixel(retainedDuringPending.current?.texture),
    "fourthCurrentPixel": pixel(fourth.current?.texture),
    "failurePendingGeneration": retainedDuringDecodeFailure.generation,
    "failurePendingCurrentPixel": pixel(retainedDuringDecodeFailure.current?.texture),
    "failedGeneration": failed.generation,
    "failedCurrent": failed.current == nil,
    "clearedGeneration": cleared.generation,
    "clearedCurrent": cleared.current == nil,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''


class SceneMediaThumbnailProviderTests(unittest.TestCase):
    def test_current_provider_stale_rejection_last_ready_and_clear(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-media-provider-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "provider"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            subprocess.run(
                ["swiftc", *map(str, SOURCES), str(harness), "-o", str(binary)],
                check=True,
                cwd=ROOT,
                env=environment,
            )
            result = json.loads(subprocess.check_output([str(binary)], text=True))
        self.assertEqual(result["generation"], 3)
        self.assertEqual(result["currentPixel"], [0, 0, 255, 255])
        self.assertTrue(result["currentPublicationComplete"])
        self.assertTrue(result["currentRequestExact"])
        self.assertTrue(result["systemAndLayerRequestsAreDistinctAtoms"])
        self.assertTrue(result["currentPublicationPremultiplied"])
        self.assertEqual(result["rapidDecodeCount"], 1)
        self.assertTrue(result["duplicateAccepted"])
        self.assertTrue(result["duplicateGenerationStable"])
        self.assertTrue(result["oversizedRejected"])
        self.assertEqual(result["pendingGeneration"], 3)
        self.assertEqual(result["pendingCurrentPixel"], [0, 0, 255, 255])
        self.assertEqual(result["fourthCurrentPixel"], [255, 0, 0, 255])
        self.assertEqual(result["failurePendingGeneration"], 4)
        self.assertEqual(result["failurePendingCurrentPixel"], [255, 0, 0, 255])
        self.assertEqual(result["failedGeneration"], 5)
        self.assertTrue(result["failedCurrent"])
        self.assertEqual(result["clearedGeneration"], 6)
        self.assertTrue(result["clearedCurrent"])


if __name__ == "__main__":
    unittest.main()
