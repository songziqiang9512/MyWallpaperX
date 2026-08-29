#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SOURCE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SOURCE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SOURCE_ROOT / "Resources/SceneFrameTextureRegistry.swift",
]


HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import Metal

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

@main
enum Harness {
    static func main() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal unavailable")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        let texture = device.makeTexture(descriptor: descriptor)!
        let replacement = device.makeTexture(descriptor: descriptor)!

        func publication(
            layerID: Int = 8,
            candidateLayerID: Int = 8,
            generation: UInt64 = 17,
            candidateGeneration: UInt64 = 17,
            provider: SceneTextureProviderIdentity? = nil,
            content: SceneTextureContent =
                .color(.resolved(.premultipliedAlpha)),
            selectedTexture: MTLTexture? = nil
        ) -> SceneTextureProviderPublication {
            let selectedTexture = selectedTexture ?? texture
            let identity = provider ?? .dynamicText(layerID: candidateLayerID)
            let size = CGSize(
                width: selectedTexture.width,
                height: selectedTexture.height
            )
            return SceneTextureProviderPublication(
                requestIdentity: .layerSource(layerID),
                candidate: SceneTextureCandidate(
                    texture: selectedTexture,
                    identity: .provider(identity),
                    generation: .provider(contentGeneration: candidateGeneration),
                    purpose: .premultipliedColor,
                    content: content,
                    physicalSize: size,
                    mappedSize: size,
                    uvTransform: .identity,
                    sampling: .linearClamp
                ),
                contentGeneration: generation
            )
        }

        let validPublication = publication()
        let valid = SceneLayerSourcePublication(
            layerID: 8,
            publication: validPublication,
            renderSizeWH: [16_384, 4_096]
        )
        guard valid?.renderSizeWH == [16_384, 4_096],
              valid?.isComplete(layerID: 8, matching: texture) == true,
              valid?.isComplete(layerID: 8, matching: replacement) == false,
              SceneLayerSourcePublication(
                layerID: 9,
                publication: validPublication,
                renderSizeWH: [640, 320]
              ) == nil,
              SceneLayerSourcePublication(
                layerID: 8,
                publication: publication(candidateGeneration: 16),
                renderSizeWH: [640, 320]
              ) == nil,
              SceneLayerSourcePublication(
                layerID: 8,
                publication: validPublication,
                renderSizeWH: [.infinity, 320]
              ) == nil else {
            fatalError("layer-source atom contract failed")
        }

        let negativeLayerPublication = publication(
            layerID: -1,
            candidateLayerID: -1,
            generation: 1,
            candidateGeneration: 1
        )
        guard SceneLayerSourcePublication(
            layerID: -1,
            publication: negativeLayerPublication,
            renderSizeWH: [640, 320]
        ) != nil else {
            fatalError("dynamic script text layer was rejected")
        }

        guard SceneLayerSourcePublication(
            layerID: 8,
            publication: publication(candidateLayerID: 9),
            renderSizeWH: [640, 320]
        ) == nil,
        SceneLayerSourcePublication(
            layerID: 8,
            publication: publication(provider: .mediaThumbnailCurrent),
            renderSizeWH: [640, 320]
        ) == nil,
        SceneLayerSourcePublication(
            layerID: 8,
            publication: publication(provider: .graph(
                allocationGeneration: 4,
                physicalToken: "fixture"
            )),
            renderSizeWH: [640, 320]
        ) == nil,
        SceneLayerSourcePublication(
            layerID: 8,
            publication: publication(provider: .video(
                layerID: 9,
                lifecycleEpoch: 2
            )),
            renderSizeWH: nil
        ) == nil else {
            fatalError("foreign provider identity entered layer-source atom")
        }

        let unresolvedVideo = publication(
            provider: .video(layerID: 8, lifecycleEpoch: 2),
            content: .color(.unresolved)
        )
        guard SceneLayerSourcePublication.supportsDirectTextureLane(
            layerID: 8,
            publication: unresolvedVideo
        ),
        !unresolvedVideo.isComplete,
        !SceneLayerSourcePublication.supportsDirectTextureLane(
            layerID: 8,
            publication: validPublication
        ),
        !SceneLayerSourcePublication.supportsDirectTextureLane(
            layerID: 8,
            publication: publication(provider: .mediaThumbnailCurrent)
        ),
        !SceneLayerSourcePublication.supportsDirectTextureLane(
            layerID: 8,
            publication: publication(
                layerID: 9,
                candidateLayerID: 8,
                provider: .video(layerID: 8, lifecycleEpoch: 2)
            )
        ) else {
            fatalError("legacy direct-video lane was not bounded")
        }
        print("bounded")
    }
}
'''


class SceneLayerSourcePublicationTests(unittest.TestCase):
    def test_layer_source_atom_and_legacy_video_lane_are_identity_bounded(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="mwx-layer-source-publication-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "layer-source-publication"
            harness.write_text(HARNESS_SOURCE, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(completed.stdout.strip(), "bounded")


if __name__ == "__main__":
    unittest.main()
