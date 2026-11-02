#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from .test_scene_prepared_script_resource_catalog import swift_declaration


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
READINESS_SOURCE = SCENE / "Resources/Textures/SceneBaseImageTextureLoad.swift"
SOURCES = [
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    ROOT / "MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSnapshotStore.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMediaThumbnailInbox.swift",
    SCENE / "Format/SceneJSONValue.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLookupIdentity.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureCandidateSupport.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseMaterialTextureResolver.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneMediaThumbnailTextureStore.swift",
    ROOT / "script/tests/fixtures/SceneMediaThumbnailTestSupport.swift",
    ROOT / "script/tests/fixtures/SceneMediaThumbnailLifecycleChecks.swift",
    ROOT / "script/tests/fixtures/SceneMediaThumbnailEventChecks.swift",
    ROOT / "script/tests/fixtures/SceneMediaThumbnailFallbackChecks.swift",
    ROOT / "script/tests/fixtures/SceneMediaThumbnailMaskChecks.swift",
]

HARNESS = r'''
import Foundation
import Metal

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal unavailable")
}
let a = png(red: 255, green: 0, blue: 0)
let b = png(red: 0, green: 255, blue: 0)
var result = checkMediaThumbnailLifecycle(device: device, firstImage: a, nextImage: b)
result["clearRetirement"] = checkMediaThumbnailClearRetirement(device: device, firstImage: a, nextImage: b)
result["cancellation"] = checkMediaThumbnailCancellation(device: device, firstImage: a, nextImage: b)
result.merge(checkMediaThumbnailEvents(firstImage: a, nextImage: b)) { _, _ in
    fatalError("Duplicate media fixture result key")
}
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
            readiness = root / "SceneOrdinaryVideoFrameReadiness.swift"
            readiness.write_text(swift_declaration(
                READINESS_SOURCE.read_text(), "enum SceneOrdinaryVideoFrameReadiness:"
            ) + "\n", encoding="utf-8")
            binary = root / "provider"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            subprocess.run(
                ["swiftc", *map(str, SOURCES), str(readiness), str(harness), "-o", str(binary)],
                check=True,
                cwd=ROOT,
                env=environment,
            )
            result = json.loads(subprocess.check_output([str(binary)], text=True))
        for name, passed in result["solidAssetFallback"].items():
            with self.subTest(solid_fallback=name):
                self.assertTrue(passed)
        for name, passed in result["maskPublications"].items():
            with self.subTest(mask_publication=name):
                self.assertTrue(passed)
        for name, passed in result["cancellation"].items():
            with self.subTest(cancellation=name):
                self.assertTrue(passed, name)
        for name, passed in result["clearRetirement"].items():
            with self.subTest(clear_retirement=name):
                self.assertTrue(passed, name)
        self.assertEqual(result["generation"], 3)
        self.assertTrue(result["initialEmptyStatesAbsent"])
        self.assertEqual(result["initialPendingGeneration"], 3)
        self.assertTrue(result["initialPendingExact"])
        self.assertTrue(result["initialPendingStatesExact"])
        self.assertEqual(result["currentPixel"], [0, 0, 0, 0])
        self.assertEqual(result["preservedCurrentPixel"], [231, 17, 149, 0])
        self.assertTrue(result["currentPublicationComplete"])
        self.assertTrue(result["preservedPublicationComplete"])
        self.assertTrue(result["initialPreviousUnavailable"])
        self.assertTrue(result["firstReadyStatesExact"])
        self.assertTrue(result["currentRequestExact"])
        self.assertTrue(result["preservedRequestExact"])
        self.assertTrue(result["purposeQualifiedSystemAtoms"])
        self.assertTrue(result["baseMaterialReadyProviderExact"])
        self.assertTrue(result["baseMaterialReadyImageProviderOwnsExtent"])
        self.assertTrue(result["baseMaterialReadyPreservesDynamicTint"])
        self.assertTrue(result["baseMaterialMissingRegistryRejectsOnlyProvider"])
        self.assertTrue(
            result["baseMaterialMissingRegistryWithoutFallbackKeepsReason"]
        )
        self.assertTrue(result["baseMaterialUnavailableKeepsAuthoredFallback"])
        self.assertTrue(result["baseMaterialIncompleteRejectsOnlyProvider"])
        self.assertTrue(result["baseMaterialUserPropertyReadyExact"])
        self.assertTrue(
            result["baseMaterialUserPropertyAbsentKeepsAuthoredFallback"]
        )
        self.assertTrue(
            result[
                "baseMaterialUserPropertyUnavailableRejectsOnlyReplacement"
            ]
        )
        self.assertTrue(
            result[
                "baseMaterialUserPropertyIncompleteRejectsOnlyReplacement"
            ]
        )
        self.assertTrue(
            result["baseMaterialUserPropertyCannotConsumeSystemProvider"]
        )
        self.assertTrue(result["systemAndLayerRequestsAreDistinctAtoms"])
        self.assertTrue(result["currentPublicationPremultiplied"])
        self.assertTrue(result["preservedPublicationData"])
        self.assertEqual(result["rapidDecodeCount"], 1)
        self.assertEqual(result["colorOnlyGeneration"], 2)
        self.assertTrue(result["colorOnlyNoPending"])
        self.assertTrue(result["colorOnlyRetainsTexture"])
        self.assertEqual(result["colorOnlyDecodeCount"], 1)
        self.assertTrue(result["duplicateAccepted"])
        self.assertTrue(result["duplicateGenerationStable"])
        self.assertTrue(result["oversizedRejected"])
        self.assertEqual(result["pendingGeneration"], 3)
        self.assertEqual(result["pendingRequestGeneration"], 4)
        self.assertTrue(result["pendingIdentitiesExact"])
        self.assertEqual(result["pendingCurrentPixel"], [0, 0, 0, 0])
        self.assertEqual(result["pendingPreservedPixel"], [231, 17, 149, 0])
        self.assertTrue(result["pendingPreviousUnavailable"])
        self.assertTrue(result["replacementPendingStatesExact"])
        self.assertEqual(result["fourthCurrentPixel"], [255, 0, 0, 255])
        self.assertEqual(result["fourthPreservedPixel"], [255, 0, 0, 255])
        self.assertEqual(result["fourthPreviousPixel"], [0, 0, 0, 0])
        self.assertEqual(
            result["fourthPreservedPreviousPixel"], [231, 17, 149, 0]
        )
        self.assertTrue(result["fourthPreviousExact"])
        self.assertTrue(result["replacementReadyStatesExact"])
        self.assertTrue(result["baseMaterialPreviousReadyExact"])
        self.assertTrue(
            result["baseMaterialPreviousUnavailableKeepsAuthoredFallback"]
        )
        self.assertTrue(result["baseMaterialCurrentCannotMasqueradeAsPrevious"])
        self.assertEqual(result["failurePendingGeneration"], 4)
        self.assertEqual(result["failurePendingCurrentPixel"], [255, 0, 0, 255])
        self.assertEqual(result["failurePendingPreservedPixel"], [255, 0, 0, 255])
        self.assertEqual(result["failurePendingPreviousPixel"], [0, 0, 0, 0])
        self.assertEqual(
            result["failurePendingPreservedPreviousPixel"], [231, 17, 149, 0]
        )
        self.assertEqual(result["failedGeneration"], 5)
        self.assertTrue(result["failedCurrent"])
        self.assertTrue(result["failedPreserved"])
        self.assertTrue(result["failedPrevious"])
        self.assertTrue(result["failedPreservedPrevious"])
        self.assertTrue(result["decodeFailureStatesUnavailable"])
        self.assertEqual(result["recoveryPendingGeneration"], 6)
        self.assertTrue(result["recoveryPendingExact"])
        self.assertTrue(result["recoveryPendingStatesExact"])
        self.assertEqual(result["recoveredCurrentPixel"], [0, 255, 0, 255])
        self.assertEqual(result["recoveredPreservedPixel"], [0, 255, 0, 255])
        self.assertEqual(result["recoveredPreviousPixel"], [255, 0, 0, 255])
        self.assertEqual(
            result["recoveredPreservedPreviousPixel"], [255, 0, 0, 255]
        )
        self.assertTrue(result["recoveredStatesExact"])
        self.assertEqual(result["clearedGeneration"], 7)
        self.assertTrue(result["clearedCurrent"])
        self.assertTrue(result["clearedPreserved"])
        self.assertTrue(result["clearedPrevious"])
        self.assertTrue(result["clearedPreservedPrevious"])
        self.assertTrue(result["clearStatesAbsent"])
        self.assertTrue(result["oversizedSourceColorReady"])
        self.assertTrue(result["oversizedSourceRetainsBothWhilePending"])
        self.assertTrue(result["oversizedSourcePreservedReady"])
        self.assertTrue(result["partialPurposeStatesExact"])
        self.assertTrue(result["firstMalformedHasNoInventedPrevious"])
        self.assertTrue(result["firstRecoveryPendingKeepsPreviousAbsent"])
        self.assertTrue(result["firstRecoveryKeepsPreviousAbsent"])
        self.assertTrue(result["oversizedSourceRotatesPreviousAtomically"])
        self.assertTrue(result["eventInitialEmpty"])
        self.assertTrue(result["propertiesAccepted"])
        self.assertEqual(result["propertiesGeneration"], 1)
        self.assertTrue(result["propertiesPreserveOtherGenerations"])
        self.assertTrue(result["propertiesExact"])
        self.assertTrue(result["duplicatePropertiesAccepted"])
        self.assertTrue(result["duplicatePropertiesStable"])
        self.assertTrue(result["titleChangeAccepted"])
        self.assertTrue(result["titleChangeAtomic"])
        self.assertTrue(result["artistChangeAccepted"])
        self.assertTrue(result["artistChangeAtomic"])
        self.assertTrue(result["controlPropertyRejected"])
        self.assertTrue(result["oversizedPropertyRejected"])
        self.assertTrue(result["invalidPropertiesPreserveSnapshot"])
        self.assertTrue(result["timelineAccepted"])
        self.assertEqual(result["timelineGeneration"], 1)
        self.assertTrue(result["timelineExact"])
        self.assertTrue(result["duplicateTimelineAccepted"])
        self.assertTrue(result["duplicateTimelineStable"])
        self.assertTrue(result["seekTimelineAccepted"])
        self.assertTrue(result["seekTimelineAllowsDecrease"])
        self.assertTrue(result["negativeTimelineRejected"])
        self.assertTrue(result["nonFiniteTimelineRejected"])
        self.assertTrue(result["invalidTimelinePreservesSnapshot"])
        self.assertTrue(result["imageColorAccepted"])
        self.assertEqual(result["imageColorGeneration"], 1)
        self.assertEqual(result["imageColorPlaybackGeneration"], 0)
        self.assertTrue(result["imageColorPreservesProperties"])
        self.assertTrue(result["imageColorPreservesTimeline"])
        self.assertTrue(result["imageColorExact"])
        self.assertTrue(result["duplicateImageColorAccepted"])
        self.assertTrue(result["duplicateImageColorGenerationStable"])
        self.assertTrue(result["replacementColorAccepted"])
        self.assertEqual(result["replacementColorGeneration"], 2)
        self.assertTrue(result["replacementColorExact"])
        self.assertTrue(result["nanColorRejected"])
        self.assertTrue(result["negativeColorRejected"])
        self.assertTrue(result["oversizedColorRejected"])
        self.assertTrue(result["emptyImageWithColorRejected"])
        self.assertTrue(result["invalidColorsPreserveSnapshot"])
        self.assertTrue(result["playbackAccepted"])
        self.assertEqual(result["playbackState"], 1)
        self.assertEqual(result["playbackGeneration"], 1)
        self.assertTrue(result["playbackPreservesImageGeneration"])
        self.assertTrue(result["duplicatePlaybackAccepted"])
        self.assertTrue(result["duplicatePlaybackGenerationStable"])
        self.assertTrue(result["pausedAccepted"])
        self.assertEqual(result["pausedState"], 2)
        self.assertEqual(result["pausedGeneration"], 2)
        self.assertTrue(result["negativePlaybackRejected"])
        self.assertTrue(result["oversizedPlaybackRejected"])
        self.assertTrue(result["invalidPlaybackPreservesSnapshot"])
        self.assertTrue(result["nextImageAccepted"])
        self.assertEqual(result["nextImageGeneration"], 3)
        self.assertTrue(result["nextImagePreservesPlaybackGeneration"])
        self.assertEqual(result["eventClearGeneration"], 4)
        self.assertTrue(result["eventClearColorIsZero"])
        self.assertTrue(result["eventClearPreservesPlayback"])
        self.assertTrue(result["eventClearPreservesProperties"])
        self.assertTrue(result["eventClearPreservesTimeline"])
        self.assertTrue(result["duplicateEventClearStable"])
        self.assertTrue(result["emptyPropertiesAccepted"])
        self.assertTrue(result["emptyPropertiesClearOldValues"])
        self.assertEqual(result["emptyPropertiesGeneration"], 4)
        self.assertTrue(result["emptyPropertiesPreserveOtherGenerations"])
        self.assertTrue(result["duplicateEmptyPropertiesAccepted"])
        self.assertTrue(result["duplicateEmptyPropertiesStable"])


if __name__ == "__main__":
    unittest.main()
