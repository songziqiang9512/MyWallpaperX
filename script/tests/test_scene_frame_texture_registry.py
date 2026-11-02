#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
REGISTRY_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift"
BASE_IMAGE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureLoad.swift"
FRAME_ASSEMBLY_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFrameLayerTextureAssembly.swift"
SWIFT_SOURCES = [
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLookupIdentity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    REGISTRY_SOURCE,
]

TEST_ACCESS_SOURCE = (Path(__file__).with_name("fixtures") / "SceneFrameTextureRegistryTestAccess.swift").read_text(encoding="utf-8")

FIXTURE_ROOT = Path(__file__).with_name("fixtures")
HARNESS_SUPPORT_SOURCE = (FIXTURE_ROOT / "SceneFrameTextureRegistrySupport.swift").read_text(encoding="utf-8")
HARNESS_SOURCE = HARNESS_SUPPORT_SOURCE + "".join(
    (FIXTURE_ROOT / name).read_text(encoding="utf-8")
    for name in (
        "SceneFrameTextureRegistryHarness.swift",
        "SceneFrameTextureRegistryCurrentCases.swift",
        "SceneFrameTextureRegistryPublicationCases.swift",
        "SceneFrameTextureRegistryLifecycleCases.swift",
    )
)


class SceneFrameTextureRegistryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-texture-registry-")
        root = Path(cls.temporary_directory.name)
        test_registry_source = root / REGISTRY_SOURCE.name
        test_registry_source.write_text(
            REGISTRY_SOURCE.read_text(encoding="utf-8") + TEST_ACCESS_SOURCE,
            encoding="utf-8",
        )
        swift_sources = [
            test_registry_source if source == REGISTRY_SOURCE else source
            for source in SWIFT_SOURCES
        ]
        harness = root / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = root / "texture-registry"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(source) for source in swift_sources),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        if destination := os.environ.get("MWX_REFLECTION_EVIDENCE"):
            Path(destination).mkdir(parents=True, exist_ok=True)
            (Path(destination)/"registry.json").write_text(json.dumps(cls.result, indent=2))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_environment_publication_identifies_consumer_and_completed_source(self) -> None:
        for key, passed in self.result["environmentPublication"].items():
            self.assertTrue(passed, key)

    def test_typed_provider_requires_a_complete_publication(self) -> None:
        for key in (
            "missingIsNotAbsent",
            "absentIsExplicit",
            "pendingFailsClosed",
            "unavailableFailsClosed",
            "incompleteFailsClosed",
            "bareExactPropertyFailsClosed",
            "readyOverride",
        ):
            self.assertTrue(self.result[key], key)

    def test_named_target_identity_and_frame_lifetime_are_preserved(self) -> None:
        for key in (
            "frameEpochAdvanced",
            "primaryReady",
            "secondaryIsolated",
            "exactNamedOverlayReady",
            "typedNamedDataRetained",
            "namedDataCannotBecomeColor",
            "staleNamedDataRejected",
            "unsupportedNamedContentRejected",
            "typedNamedPublicationSucceeded",
            "typedNamedPublicationIsComplete",
            "namedPublicationAfterOtherResourcesSucceeded",
            "namedPublicationAfterOtherResourcesComplete",
            "bareNamedConsumerRejected",
            "staleTypedPublicationRejected",
            "secondaryNamedReservationRejected",
            "missingRenderTargetUsageRejected",
            "staleNamedOverlayRejected",
            "wrongNamedOverlayRejected",
            "namedCleared",
            "namedGenerationAdvanced",
        ):
            self.assertTrue(self.result[key], key)

    def test_persistent_resource_generations_change_only_with_publication(self) -> None:
        for key in (
            "persistentGenerationsStable",
            "replacementGenerationsAdvanced",
            "restoredGenerationsAdvanced",
            "persistentEntriesCleared",
        ):
            self.assertTrue(self.result[key], key)

    def test_registry_rejects_stale_or_mutated_atoms_within_one_lifecycle(
        self,
    ) -> None:
        for key in (
            "explicitContentGenerationAdvanced",
            "sameExplicitGenerationStable",
            "sameGenerationReplacementRejected",
            "lowerProducerGenerationRejected",
            "mismatchedPublicationRejected",
            "explicitSystemGenerationAdvanced",
            "sameExplicitSystemGenerationReplacementRejected",
            "lowerExplicitSystemGenerationRejected",
            "typedSetIdentityIsStable",
            "typedSetStableAcrossFrames",
            "sameFrameStaleABAPreservesNewest",
            "videoLifecycleGenerationIsAtomic",
        ):
            self.assertTrue(self.result[key], key)

    def test_frame_publication_discard_restores_previous_generation(self) -> None:
        self.assertTrue(self.result["framePublicationDiscardRestoresPrevious"])

    def test_property_reset_retires_resources_only_after_frame_acceptance(self) -> None:
        for name, passed in self.result["propertyResetRetirement"].items():
            self.assertTrue(passed, name)

    def test_system_provider_lookup_is_purpose_qualified(self) -> None:
        self.assertTrue(self.result["systemPurposesDoNotAlias"])
        self.assertTrue(self.result["systemPurposeMismatchRemainsTypedReady"])
        self.assertTrue(self.result["currentCandidateCannotSatisfyPreviousRequest"])
        self.assertTrue(self.result["exactPreviousCandidateIsReady"])

    def test_bare_generation_changes_when_typed_metadata_is_removed(self) -> None:
        for key in (
            "typedToBareAdvancesGeneration",
            "exactIdentityMismatchRejectedWithoutEntry",
            "mismatchToBareAdvancesGeneration",
            "bareToBareKeepsGeneration",
        ):
            self.assertTrue(self.result[key], key)

    def test_typed_lookup_is_atomic_identity_based_and_fail_closed(self) -> None:
        for key in (
            "bareLookupIsIncomplete",
            "bareTypedLookupRejected",
            "typedPublicationIsAtomic",
            "snapshotUsesDirectIdentity",
            "explicitLayerPublishesExactGraphIdentity",
            "sameGenerationMetadataMutationPreservesAtom",
            "bareLayerSourceIsIncomplete",
            "bareLayerDoesNotPublishTypedGraph",
            "unresolvedColorIsIncomplete",
            "dataPurposeAndSourceRevisionPreserved",
            "mismatchedContentRejected",
            "normalizedAssetIdentity",
            "colonAssetIdentity",
            "purposeMismatchedAssetIncomplete",
            "purposeMismatchReplacesOldReady",
            "mismatchedIdentityGenerationIncomplete",
            "providerGenerationMismatchIncomplete",
            "volumePurposeOn2DIncomplete",
            "purposeQualifiedUserPropertyReady",
            "purposeMismatchedUserPropertyIncomplete",
            "typedPendingIsExplicit",
            "typedUnavailableIsExplicit",
            "typedAbsentIsExplicit",
            "frameIndexIsFrozen",
            "assetStatePublishesExactRequest",
            "assetAbsentIsExplicit",
            "exactRequestMismatchRejected",
            "programSamplerAdmissionIsBounded",
        ):
            self.assertTrue(self.result[key], key)

    def test_layer_publishers_bind_each_logical_request_exactly(self) -> None:
        base = BASE_IMAGE_SOURCE.read_text(encoding="utf-8")
        assembly = FRAME_ASSEMBLY_SOURCE.read_text(encoding="utf-8")
        self.assertIn("requestIdentity: .layerSource(layerID)", base)
        self.assertIn("layerSource.isComplete(layerID: layerID, matching: texture)", base)
        self.assertIn("dynamicText.layerSources", assembly)
        self.assertIn("layerSourcePublications[layerID] = layerSource", assembly)
        self.assertIn("layerSourcePublications: layerSourcePublications", assembly)
        self.assertNotIn("textures[layerID] = mediaThumbnail", assembly)



if __name__ == "__main__":
    unittest.main()
