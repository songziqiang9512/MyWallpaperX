#!/usr/bin/env python3
"""Shared effect-local texture demand states and purpose identity."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SCENE_ROOT / "Resources/SceneEffectTextureLoadResult.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd
import CoreGraphics

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        cacheDirectory: URL,
        device: MTLDevice
    ) { return nil }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 8,
            height: 4,
            mipmapped: true
        )
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        let candidate = SceneTextureCandidate(
            texture: texture,
            identity: .builtIn(name: "binding-test"),
            generation: .immutable(revision: 7),
            purpose: .mask,
            content: .data,
            physicalSize: CGSize(width: 8, height: 4),
            mappedSize: CGSize(width: 4, height: 4),
            uvTransform: .init(
                origin: .zero,
                xAxis: SIMD2(0.5, 0),
                yAxis: SIMD2(0, 1)
            ),
            sampling: .linearClamp
        )
        let readyResult = SceneEffectTextureLoadResult(
            candidate: candidate,
            texture: texture,
            mappedUVScale: SIMD2(0.5, 1),
            sampling: .linearClamp,
            message: ""
        )
        let ready = SceneEffectTextureBinding(
            path: "Masks\\Ready",
            purpose: .mask,
            loadResult: readyResult
        )
        let wrongPurpose = SceneEffectTextureBinding(
            path: "masks/ready",
            purpose: .noise,
            loadResult: readyResult
        )
        let absent = SceneEffectTextureBinding.absent(purpose: .mask)
        let unavailable = SceneEffectTextureBinding.unavailable(
            path: "masks/missing",
            purpose: .mask
        )
        let pending = SceneEffectTextureBinding.pending(
            path: "masks/pending",
            purpose: .mask
        )
        let result: [String: Any] = [
            "available": true,
            "absent": absent.state == .absent && !absent.matches(path: "masks/missing"),
            "unavailable": unavailable.state == .unavailable
                && !unavailable.isReady
                && !unavailable.matches(path: "masks/missing"),
            "purpose": unavailable.purpose == .mask,
            "ready": ready.isReady
                && ready.matches(path: "masks/ready")
                && ready.texture === texture,
            "generation": generationIsRevisionSeven(ready.generation),
            "extent": ready.physicalSize == CGSize(width: 8, height: 4)
                && ready.mappedSize == CGSize(width: 4, height: 4)
                && ready.mappedUVScale == SIMD2<Float>(0.5, 1)
                && (ready.texture?.mipmapLevelCount ?? 0) > 1,
            "pending": pending.state == .pending
                && !pending.isReady
                && !pending.matches(path: "masks/pending"),
            "wrongPurpose": wrongPurpose.state == .unavailable
                && wrongPurpose.texture == nil,
        ]
        print(String(
            decoding: try JSONSerialization.data(
                withJSONObject: result,
                options: [.sortedKeys]
            ),
            as: UTF8.self
        ))
    }

    static func generationIsRevisionSeven(
        _ generation: SceneTextureResourceGeneration?
    ) -> Bool {
        guard case .immutable(revision: 7)? = generation else { return false }
        return true
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSharedEffectTextureBindingTests(unittest.TestCase):
    def test_absent_and_unavailable_are_distinct_and_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-shared-effect-binding-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "shared-effect-binding-test"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            execution = subprocess.run(
                [str(binary)], capture_output=True, text=True, check=False
            )
            self.assertEqual(execution.returncode, 0, execution.stderr)
            result = json.loads(execution.stdout)
            if not result.get("available", False):
                self.skipTest("Metal device unavailable")
            self.assertEqual(
                result,
                {
                    "absent": True,
                    "available": True,
                    "extent": True,
                    "generation": True,
                    "pending": True,
                    "purpose": True,
                    "ready": True,
                    "unavailable": True,
                    "wrongPurpose": True,
                },
            )


if __name__ == "__main__":
    unittest.main()
