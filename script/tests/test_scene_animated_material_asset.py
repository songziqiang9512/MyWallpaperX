#!/usr/bin/env python3

"""Stock atlas parser, per-surface provider, and registry lifecycle gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

from script.tests.test_scene_sampler_default_purpose import (
    REPOSITORY_ROOT,
    SCENE_ROOT,
    SUPPORT,
    SWIFT_SOURCES,
)


STOCK_FOG2 = REPOSITORY_ROOT / (
    "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/"
    "materials/particle/fog/fog2.tex"
)


def animated_r8_tex(
    frames: list[tuple[int, float, tuple[float, float, float, float, float, float]]],
    *,
    image_count: int = 1,
) -> bytes:
    data = bytearray(b"TEXV0005\0TEXI0001\0")
    data.extend(struct.pack("<7I", 9, 4, 4, 4, 4, 4, 0))
    data.extend(b"TEXB0002\0")
    data.extend(struct.pack("<I", image_count))
    for image in range(image_count):
        payload = bytes([64 + image] * 16)
        data.extend(struct.pack("<6I", 1, 4, 4, 0, 0, len(payload)))
        data.extend(payload)
    data.extend(b"TEXS0002\0")
    data.extend(struct.pack("<I", len(frames)))
    for image_index, duration, coordinates in frames:
        data.extend(struct.pack("<If6f", image_index, duration, *coordinates))
    return bytes(data)


HARNESS = r'''
import Foundation
import Metal

private let firstPath = SceneVFSAssetPath("particle/fog/fog2-a")!
private let secondPath = SceneVFSAssetPath("particle/fog/fog2-b")!
private let zeroDurationPath = SceneVFSAssetPath("valid/zero-duration")!
private let invalidPaths = [
    "rotated", "nonfinite", "out-of-range", "duration-overflow",
    "empty", "multi-image", "decode",
].map { SceneVFSAssetPath("invalid/\($0)")! }

private func publication(
    _ states: [SceneAssetTextureIdentity: SceneTextureProviderState],
    _ identity: SceneAssetTextureIdentity
) -> SceneTextureProviderPublication? {
    guard case let .ready(value)? = states[identity] else { return nil }
    return value
}

@main
private enum Main {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              CommandLine.arguments.count == 2 else {
            print(#"{"metalAvailable":false}"#)
            return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let view = SceneResourceView(
            projectRootURL: root, packageRootURL: nil,
            stockAssetsRootURL: root
        )
        let first = SceneAssetTextureIdentity(
            path: firstPath, purpose: .preservedChannels
        )
        let second = SceneAssetTextureIdentity(
            path: secondPath, purpose: .preservedChannels
        )
        let zeroDuration = SceneAssetTextureIdentity(
            path: zeroDurationPath, purpose: .preservedChannels
        )
        let invalid = invalidPaths.map {
            SceneAssetTextureIdentity(path: $0, purpose: .preservedChannels)
        }
        let catalog = SceneMaterialAssetTextureCatalog(
            demands: Set([first, second, zeroDuration] + invalid),
            resourceView: view,
            descriptor: SceneRenderDescriptor(),
            device: device
        )
        let provider = catalog.makeFrameProvider()
        let frame0States = provider.states(sceneTime: 0)
        let stableStates = provider.states(sceneTime: 0.001)
        let zeroBeforeBoundaryStates = provider.states(sceneTime: 0.016)
        let zeroAfterBoundaryStates = provider.states(sceneTime: 0.017)
        let laterStates = provider.states(sceneTime: 0.02)
        let wrapStates = provider.states(sceneTime: 1.001)
        let independentStates = catalog.makeFrameProvider().states(sceneTime: 0.02)
        guard let frame0 = publication(frame0States, first),
              let stable = publication(stableStates, first),
              let later = publication(laterStates, first),
              let wrap = publication(wrapStates, first),
              let secondFrame0 = publication(frame0States, second),
              let zeroFrame0 = publication(frame0States, zeroDuration),
              let zeroStable = publication(stableStates, zeroDuration),
              let zeroBeforeBoundary = publication(
                  zeroBeforeBoundaryStates, zeroDuration
              ),
              let zeroAfterBoundary = publication(
                  zeroAfterBoundaryStates, zeroDuration
              ),
              let independent = publication(independentStates, first) else {
            throw NSError(domain: "animated-provider", code: 1)
        }

        let registry = SceneFrameTextureRegistry()
        _ = registry.beginFrame(
            frameIndex: 1, layerSources: [:],
            assetStates: [first: .ready(later)]
        )
        _ = registry.beginFrame(
            frameIndex: 2, layerSources: [:],
            assetStates: [first: .ready(frame0)]
        )
        let staleRetained: Bool
        if case let .ready(resource)? = registry.lookup(.asset(first)) {
            staleRetained = resource.publication.isSameAtom(as: later)
        } else { staleRetained = false }

        let firstURL = root.appendingPathComponent("particle/fog/fog2-a.tex")
        let oldDate = try firstURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate!
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate.addingTimeInterval(2)],
            ofItemAtPath: firstURL.path
        )
        let revisedCatalog = SceneMaterialAssetTextureCatalog(
            demands: [first], resourceView: view,
            descriptor: SceneRenderDescriptor(), device: device
        )
        guard let revised = publication(
            revisedCatalog.makeFrameProvider().states(sceneTime: 0), first
        ) else { throw NSError(domain: "animated-provider", code: 2) }
        _ = registry.beginFrame(
            frameIndex: 3, layerSources: [:],
            assetStates: [first: .ready(revised)]
        )
        let revisionRecovered: Bool
        if case let .ready(resource)? = registry.lookup(.asset(first)) {
            revisionRecovered = resource.publication.isSameAtom(as: revised)
        } else { revisionRecovered = false }

        let wrongPurpose = SceneAssetTextureIdentity(
            path: firstPath, purpose: .noise
        )
        let wrongPurposePublication = SceneTextureProviderPublication(
            requestIdentity: .asset(wrongPurpose),
            candidate: frame0.candidate,
            contentGeneration: frame0.contentGeneration
        )
        let wrongRequestRegistry = SceneFrameTextureRegistry()
        _ = wrongRequestRegistry.beginFrame(frameIndex: 1, layerSources: [:])
        wrongRequestRegistry.set(frame0, for: .asset(second))
        let providerCandidate = SceneTextureCandidate(
            texture: frame0.texture,
            identity: .provider(.video(layerID: 7, lifecycleEpoch: 1)),
            generation: .provider(contentGeneration: 4),
            purpose: .preservedChannels,
            content: .data,
            physicalSize: frame0.candidate.physicalSize,
            mappedSize: frame0.candidate.mappedSize,
            uvTransform: frame0.candidate.uvTransform,
            sampling: frame0.candidate.sampling,
            authoredFormat: frame0.candidate.authoredFormat
        )
        let wrongProviderGeneration = SceneTextureProviderPublication(
            requestIdentity: .asset(first),
            candidate: providerCandidate,
            contentGeneration: 5
        )

        let parsed = SceneTextureLoader().texContainer(from: firstURL)!
        let totalDuration = parsed.spriteFrames.reduce(Float(0)) {
            $0 + ($1.duration > 0 ? $1.duration : 1 / 60)
        }
        let shape = parsed.containerVersion == .texb0003
            && parsed.format == 8
            && parsed.imageCount == 1
            && parsed.mips.count == 10
            && parsed.textureWidth == 1024
            && parsed.textureHeight == 1024
            && parsed.spriteFrames.count == 64
            && parsed.spriteFrames.allSatisfy {
                $0.imageIndex == 0
                    && $0.xAxis.y == 0 && $0.yAxis.x == 0
                    && abs($0.xAxis.x - 0.125) < 0.000_001
                    && abs($0.yAxis.y - 0.125) < 0.000_001
            }
            && abs(totalDuration - 1) < 0.000_01
        let invalidUnavailable = invalid.allSatisfy {
            if case .unavailable? = frame0States[$0] { return true }
            return false
        }
        let metadataInvalidVisual = [invalid[0], invalid[2], invalid[3]]
            .allSatisfy {
            if case .effectLocalUnavailable(.animatedFrameMetadataInvalid)? =
                    catalog.launchStates[$0] { return true }
            return false
        }
        let hardInvalidLaunch = [invalid[1], invalid[4], invalid[5], invalid[6]]
            .allSatisfy {
            if case .unavailable? = catalog.launchStates[$0] { return true }
            return false
        }
        let volume = SceneTexContainer(
            format: parsed.format, flags: parsed.flags,
            textureWidth: parsed.textureWidth,
            textureHeight: parsed.textureHeight, textureDepth: 2,
            imageWidth: parsed.imageWidth, imageHeight: parsed.imageHeight,
            containerVersion: parsed.containerVersion,
            freeImageFormat: parsed.freeImageFormat,
            isVideoMp4: parsed.isVideoMp4, images: parsed.images,
            spriteFrames: parsed.spriteFrames
        )
        let structuralHard = SceneTextureLoader()
            .materialAtlasAdmission(volume) == .unsupportedStructure
        let launchReady = catalog.launchStates[first]
            == .ready(.data)
            && catalog.launchFormatFacts[first.reportToken] == 8
        let result: [String: Any] = [
            "metalAvailable": true,
            "stockShape": shape,
            "launchReady": launchReady,
            "twoIdentities": secondFrame0.requestIdentity == .asset(second)
                && secondFrame0.candidate.physicalSize
                    == frame0.candidate.physicalSize
                && secondFrame0.texture !== frame0.texture,
            "sameFrameStable": stable.contentGeneration
                    == frame0.contentGeneration
                && stable.isSameAtom(as: frame0),
            "laterMonotonic": later.contentGeneration
                    > stable.contentGeneration
                && later.candidate.uvTransform != frame0.candidate.uvTransform,
            "wrapMonotonic": wrap.contentGeneration > later.contentGeneration
                && wrap.candidate.uvTransform == frame0.candidate.uvTransform,
            "physicalStable": frame0.texture === later.texture
                && later.texture === wrap.texture
                && frame0.lifecycleIdentity == wrap.lifecycleIdentity
                && frame0.requestIdentity == .asset(first)
                && frame0.candidate.purpose == .preservedChannels,
            "perSurfaceIndependent": independent.contentGeneration == 1
                && independent.candidate.uvTransform
                    == later.candidate.uvTransform,
            "zeroDurationEffectiveFrame": zeroStable.isSameAtom(as: zeroFrame0)
                && zeroBeforeBoundary.isSameAtom(as: zeroFrame0)
                && zeroAfterBoundary.contentGeneration
                    > zeroBeforeBoundary.contentGeneration
                && zeroAfterBoundary.candidate.uvTransform
                    != zeroFrame0.candidate.uvTransform,
            "staleRetained": staleRetained,
            "sourceRevisionLifecycle": revised.lifecycleIdentity
                    != frame0.lifecycleIdentity
                && revised.contentGeneration == 1
                && revisionRecovered,
            "invalidUnavailable": invalidUnavailable,
            "metadataInvalidVisual": metadataInvalidVisual,
            "hardInvalidLaunch": hardInvalidLaunch,
            "structuralHard": structuralHard,
            "wrongPurposeIncomplete": !wrongPurposePublication.isComplete,
            "wrongRequestRejected": wrongRequestRegistry.lookup(.asset(second)) == nil,
            "wrongProviderGeneration": !wrongProviderGeneration.isComplete,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result, options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneAnimatedMaterialAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-animated-material-asset-"
        )
        root = Path(cls.temporary_directory.name)
        resources = root / "resources"
        (resources / "particle/fog").mkdir(parents=True)
        (resources / "invalid").mkdir(parents=True)
        (resources / "valid").mkdir(parents=True)
        shutil.copyfile(STOCK_FOG2, resources / "particle/fog/fog2-a.tex")
        shutil.copyfile(STOCK_FOG2, resources / "particle/fog/fog2-b.tex")
        (resources / "valid/zero-duration.tex").write_bytes(
            animated_r8_tex([
                (0, 0, (0, 0, 2, 0, 0, 4)),
                (0, 0, (2, 0, 2, 0, 0, 4)),
            ])
        )
        valid = (0, 0.1, (0, 0, 4, 0, 0, 4))
        fixtures = {
            "rotated": animated_r8_tex([(0, 0.1, (0, 0, 0, 4, 4, 0))]),
            "nonfinite": animated_r8_tex([
                (0, 0.1, (float("nan"), 0, 4, 0, 0, 4))
            ]),
            "out-of-range": animated_r8_tex([
                (0, 0.1, (3, 0, 3, 0, 0, 4))
            ]),
            "duration-overflow": animated_r8_tex([
                (0, 3.4e38, (0, 0, 4, 0, 0, 4)),
                (0, 3.4e38, (0, 0, 4, 0, 0, 4)),
            ]),
            "empty": animated_r8_tex([]),
            "multi-image": animated_r8_tex([valid], image_count=2),
            "decode": b"not-a-tex",
        }
        for name, value in fixtures.items():
            (resources / f"invalid/{name}.tex").write_bytes(value)

        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "animated-material-asset"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support), *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-module-cache-path", str(root / "module-cache"),
                "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary), str(resources)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_stock_shape_and_frame_provider_lifecycle(self) -> None:
        self.assertEqual(
            [key for key, value in self.result.items()
             if key != "metalAvailable" and not value],
            [],
            self.result,
        )


if __name__ == "__main__":
    unittest.main()
