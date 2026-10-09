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
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift",
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
            renderSizeWH: [16_384, 4_096],
            textCenterOffsetY: 40
        )
        guard valid?.renderSizeWH == [16_384, 4_096],
              valid?.textCenterOffsetY == 40,
              SceneLayerSourcePublication(layerID: 8, publication: validPublication,
                renderSizeWH: [100, 50], textCenterOffsetY: .infinity) == nil,
              SceneLayerSourcePublication(layerID: 8, publication: validPublication,
                textCenterOffsetY: 40) == nil,
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

        // One evaluated material texture may serve a prototype and clones,
        // but each consumer owns its publication identity and geometry.
        let sharedMaterialAtoms = [8, -1, -2].enumerated().map { index, layerID in
            SceneLayerSourcePublication(
                layerID: layerID,
                publication: publication(layerID: layerID,
                    provider: .materialSource(layerID: layerID,
                        frameEpoch: 17, allocationGeneration: 4)),
                renderSizeWH: [Float(20 + index), 10]
            )
        }
        guard sharedMaterialAtoms.allSatisfy({ $0?.publication.texture === texture }),
              sharedMaterialAtoms[0]?.renderSizeWH == [20, 10],
              sharedMaterialAtoms[1]?.renderSizeWH == [21, 10],
              sharedMaterialAtoms[2]?.renderSizeWH == [22, 10],
              SceneLayerSourcePublication(layerID: -1,
                publication: sharedMaterialAtoms[0]!.publication) == nil
        else { fatalError("shared material output lost consumer identity or geometry") }
        let sharedFrame = SceneFrameTextureRegistrySnapshot(
            frameEpoch: 17, frameIndex: 3, entries: [:])
        let staleMaterial = SceneLayerSourcePublication(layerID: -1,
            publication: publication(layerID: -1,
                provider: .materialSource(layerID: -1,
                    frameEpoch: 16, allocationGeneration: 4)))!
        guard sharedFrame.overlayingLayerSources([
            8: sharedMaterialAtoms[0]!, -1: sharedMaterialAtoms[1]!, -2: sharedMaterialAtoms[2]!
        ])?.resource(for: .layerSource(-2))?.publication.texture === texture,
              sharedFrame.overlayingLayerSources([-1: staleMaterial]) == nil
        else { fatalError("shared material frame accepted stale source epoch") }

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
