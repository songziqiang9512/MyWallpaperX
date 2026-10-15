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
HOST_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
SWIFT_SOURCES = [
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    SOURCE_ROOT / "Format/SceneBCTextureDecoder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyTextureLoader.swift",
]

HARNESS_SOURCE = (Path(__file__).with_name("fixtures") / "SceneUserPropertyTextureHarness.swift").read_text(encoding="utf-8")


class SceneUserPropertyTextureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-user-property-textures-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-user-property-textures"
        compilation = subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-module-cache-path", str(directory / "module-cache"),
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        fixture_directory = directory / "fixture"
        completed = subprocess.run(
            [str(cls.binary), str(fixture_directory)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_direct_and_embedded_jpeg_share_display_layout(self) -> None:
        expected_corners = [[0, 1, 2, 3], [0, 1, 2, 3], [1, 0, 3, 2],
                            [3, 2, 1, 0], [2, 3, 0, 1], [0, 2, 1, 3],
                            [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]]
        rows = self.result["jpegLayout"]["rows"]
        self.assertEqual(len(rows), 10)
        for row in rows:
            orientation = row["orientation"]
            with self.subTest(case=row["case"], orientation=orientation):
                extent = [32, 48] if orientation >= 5 else [48, 32]
                for key in ["colorSize", "straightSize", "naturalSize", "dataExtent", "embeddedExtent", "embeddedSize"]:
                    self.assertEqual(row[key], extent)
                self.assertEqual(row["candidateExtent"], extent * 2)
                for key in ["colorCorners", "straightCorners", "embeddedCorners"]:
                    self.assertEqual(row[key], expected_corners[orientation])
                self.assertTrue(row["complete"])
                self.assertTrue(row["strictRejectsNonidentity"])

    def test_invalid_jpeg_metadata_does_not_publish(self) -> None:
        self.assertTrue(self.result["jpegLayout"]["invalidMetadataRejected"])
        self.assertTrue(self.result["jpegLayout"]["truncatedMetadataRejected"])

    def test_png_and_both_jpeg_extensions_load(self) -> None:
        self.assertEqual(self.result["loadedKeys"], ["jpeg", "jpg", "png"])
        self.assertEqual(self.result["candidateKeys"], ["jpeg", "jpg", "png"])
        self.assertEqual(self.result["reportLines"][0], "sceneUserTextureRequestedCount: 5")
        self.assertEqual(self.result["reportLines"][-3], "sceneUserTextureLoadedCount: 3")
        self.assertEqual(
            self.result["reportLines"][-2],
            "sceneUserTextureStraightAlbedoLoadedCount: 2",
        )
        self.assertEqual(
            self.result["reportLines"][-1],
            "sceneUserTexturePreservedLoadedCount: 1",
        )
        self.assertEqual(
            self.result["dimensions"],
            {
                "jpeg": {"height": 2, "width": 3},
                "jpg": {"height": 2, "width": 3},
                "png": {"height": 1, "width": 2},
            },
        )

    def test_color_textures_publish_atomic_candidates(self) -> None:
        self.assertTrue(self.result["candidateSharesTexture"])
        self.assertTrue(self.result["candidatePurpose"])
        self.assertEqual(self.result["candidatePhysicalMapped"], [2, 1, 2, 1])

    def test_all_requested_roles_publish_purpose_qualified_atoms(self) -> None:
        self.assertEqual(
            self.result["publicationTokens"],
            [
                "property:3#jpg:premultiplied-color",
                "property:3#png:mask",
                "property:3#png:premultiplied-color",
                "property:3#png:preserved-channels",
                "property:3#png:straight-albedo",
                "property:4#jpeg:premultiplied-color",
                "property:4#jpeg:straight-albedo",
            ],
        )
        self.assertTrue(self.result["publicationAtomsComplete"])
        self.assertTrue(self.result["publicationTexturesMatchPurpose"])
        self.assertEqual(
            self.result["unavailableTokens"],
            [
                "property:11#unsupported:premultiplied-color",
                "property:6#broken:flow",
                "property:6#broken:premultiplied-color",
            ],
        )
        self.assertEqual(
            self.result["absentTokens"],
            ["property:12#not-selected:premultiplied-color"],
        )

    def test_requested_property_has_a_separate_preserved_texture(self) -> None:
        self.assertEqual(self.result["preservedLoadedKeys"], ["png"])
        self.assertEqual(
            self.result["preservedDimensions"],
            {"png": {"height": 1, "width": 2}},
        )
        self.assertTrue(self.result["differentPurposeTexture"])

    def test_xray_property_roles_publish_separate_straight_albedo(self) -> None:
        self.assertEqual(
            self.result["straightAlbedoLoadedKeys"],
            ["jpeg", "png"],
        )
        self.assertEqual(
            self.result["straightAlbedoDimensions"],
            {
                "jpeg": {"height": 2, "width": 3},
                "png": {"height": 1, "width": 2},
            },
        )

    def test_png_channel_purpose_preserves_hidden_and_straight_rgb(self) -> None:
        self.assertEqual(
            self.result["preservedPixels"],
            [231, 17, 149, 0, 200, 100, 50, 64],
        )
        self.assertEqual(
            self.result["colorPixels"],
            [0, 0, 0, 0, 50, 25, 13, 64],
        )
        self.assertEqual(
            self.result["reversedPreservedPixels"],
            self.result["preservedPixels"],
        )
        self.assertEqual(
            self.result["reversedColorPixels"],
            self.result["colorPixels"],
        )
        self.assertEqual(
            self.result["embeddedDataPixels"],
            self.result["preservedPixels"],
        )

    def test_premultiplied_data_input_fails_closed(self) -> None:
        self.assertTrue(self.result["premultipliedDataRejected"])
        self.assertTrue(self.result["resizedDataRejected"])
        self.assertTrue(self.result["decodedDataRejected"])

    def test_straight_albedo_only_resizes_explicitly_opaque_images(self) -> None:
        self.assertEqual(self.result["resizedOpaqueAlbedo"][-1], 255)
        self.assertTrue(self.result["embeddedStraightAlbedoPixels"])
        self.assertEqual(
            set(self.result["embeddedStraightAlbedoPixels"][3::4]),
            {255},
        )
        self.assertTrue(self.result["resizedTransparentAlbedoRejected"])
        self.assertTrue(self.result["premultipliedAlbedoRejected"])

    def test_explicit_32_bit_byte_orders_preserve_rgba_channels(self) -> None:
        expected = [231, 17, 149, 0]
        self.assertEqual(self.result["explicitBigPixels"], expected)
        self.assertEqual(self.result["explicitLittlePixels"], expected)

    def test_encoded_preserved_channels_decode_is_bounded_and_typed(self) -> None:
        self.assertEqual(
            self.result["encodedPreservedPixels"],
            self.result["preservedPixels"],
        )
        self.assertEqual(self.result["encodedOversizeDimensions"], [256, 1])
        self.assertEqual(
            self.result["encodedOversizePixels"][:4], [231, 17, 149, 0]
        )
        self.assertTrue(self.result["encodedSourceLimitRejected"])
        self.assertTrue(self.result["encodedOrientationRejected"])
        self.assertTrue(self.result["encodedPremultipliedRejected"])
        self.assertEqual(set(self.result["encodedOpaquePixels"][3::4]), {255})

    def test_corrupt_and_unsupported_files_fail_closed(self) -> None:
        report = "\n".join(self.result["reportLines"])
        self.assertIn("broken", report)
        self.assertIn("unsupported", report)
        self.assertNotIn("broken", self.result["loadedKeys"])
        self.assertNotIn("unsupported", self.result["loadedKeys"])

    def test_failed_retry_does_not_retain_an_old_texture(self) -> None:
        self.assertEqual(self.result["retryLoadedKeys"], [])
        self.assertEqual(self.result["retryCandidateKeys"], [])
        self.assertEqual(self.result["retryPublicationTokens"], [])
        self.assertEqual(
            self.result["retryUnavailableTokens"],
            ["property:3#png:premultiplied-color"],
        )
        self.assertEqual(
            [
                self.result["retryReportLines"][0],
                self.result["retryReportLines"][-3],
                self.result["retryReportLines"][-2],
                self.result["retryReportLines"][-1],
            ],
            [
                "sceneUserTextureRequestedCount: 1",
                "sceneUserTextureLoadedCount: 0",
                "sceneUserTextureStraightAlbedoLoadedCount: 0",
                "sceneUserTexturePreservedLoadedCount: 0",
            ],
        )
        self.assertEqual(self.result["retryPreservedLoadedKeys"], [])

    def test_empty_input_is_a_noop(self) -> None:
        self.assertEqual(self.result["emptyLoadedKeys"], [])
        self.assertEqual(self.result["emptyCandidateKeys"], [])
        self.assertEqual(self.result["emptyPreservedLoadedKeys"], [])
        self.assertEqual(self.result["emptyStraightAlbedoLoadedKeys"], [])
        self.assertEqual(self.result["emptyPublicationTokens"], [])
        self.assertEqual(self.result["emptyProviderStateCount"], 0)
        self.assertEqual(self.result["emptyReportLines"], [])

    def test_loader_reuses_unchanged_textures_but_invalidates_changed_user_files(self) -> None:
        self.assertTrue(self.result["reusedTexture"])
        self.assertTrue(self.result["reusedPreservedTexture"])
        self.assertTrue(self.result["differentPurposeTexture"])
        self.assertEqual(self.result["sharedDecodeAttempts"], 1)
        self.assertEqual(self.result["sharedUploadQueueAttempts"], 1)
        self.assertTrue(self.result["changedFileInvalidatedCache"])

    def test_loader_reuses_embedded_tex_decode_across_texture_purposes(self) -> None:
        self.assertTrue(self.result["embeddedTexDifferentPurpose"])
        self.assertEqual(self.result["embeddedTexDecodeAttempts"], 1)

    def test_two_loaders_share_one_injected_upload_command_queue(self) -> None:
        self.assertEqual(self.result["launchUploadQueueAttempts"], 1)

    def test_decode_cache_budget_applies_to_next_admission(self) -> None:
        self.assertGreater(self.result["admittedDecodeBytes"], 0)
        self.assertEqual(self.result["deniedDecodeAttempts"], 2)
        self.assertGreaterEqual(self.result["decodeBudgetRejectedAdmissions"], 2)
        self.assertEqual(
            self.result["decodeBudgetBytesAfterDenial"],
            self.result["admittedDecodeBytes"],
        )

    def test_decode_cache_budget_releases_with_loader(self) -> None:
        self.assertGreater(self.result["leasedDecodeBytes"], 0)
        self.assertEqual(self.result["releasedDecodeBytes"], 0)



if __name__ == "__main__":
    unittest.main()
