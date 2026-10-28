#!/usr/bin/env python3

from __future__ import annotations

import json
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_SCRIPT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script"
)
SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneMaterialRenderState.swift",
    SCENE_SCRIPT.parent / "Particles/SceneParticlePlaybackModels.swift",
    SCENE_SCRIPT / "SceneScriptDynamicLayerRuntime+ParticlePlayback.swift",
    SCENE_SCRIPT / "SceneScriptLayerMutation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerTopologyModels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime+Values.swift",
]

HARNESS = (Path(__file__).parent / "fixtures/SceneScriptDynamicLayerRuntimeHarness.swift").read_text(encoding="utf-8")
CAMERA_PROFILE = SCENE_SCRIPT.parent / "Properties/SceneDefault2DCameraInputProfile.swift"


def camera_numeric_leaf() -> str:
    """Compile the unchanged real numeric owner, without the unrelated parser DTOs.

    This tiny gate tests runtime transactions. The camera-input gate links the
    complete Profile and real parser; this projection cannot replace that gate.
    """
    source = CAMERA_PROFILE.read_text(encoding="utf-8")
    constants = re.findall(r"(?m)^    static let maximumOriginMagnitude = [^\n]+", source)
    signatures = list(re.finditer(
        r"    static func acceptsOrigin\(_ values: \[Double\], nearZ: Double, farZ: Double\) -> Bool \{",
        source))
    if len(constants) != 1 or len(signatures) != 1:
        raise AssertionError("camera numeric owner missing or ambiguous")
    start = signatures[0].start()
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth and end < len(source):
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    if depth:
        raise AssertionError("camera numeric owner is incomplete")
    return ("nonisolated enum SceneDefault2DCameraInputProfile {\n"
            + constants[0] + "\n" + source[start:end] + "\n}\n")


class SceneScriptDynamicLayerRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-script-dynamic-layer-"
        )
        directory = Path(cls.temporary_directory.name)
        inputs = [*SOURCES, CAMERA_PROFILE,
                  Path(__file__), Path(__file__).parent / "fixtures/SceneScriptDynamicLayerRuntimeHarness.swift",
                  *SCENE_SCRIPT.rglob("*.h")]
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        frozen = directory / "source"
        for source in inputs:
            target = frozen / source.relative_to(REPOSITORY_ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS + "\n" + camera_numeric_leaf(), encoding="utf-8")
        binary = directory / "dynamic-layer-runtime"
        compilation = subprocess.run(
            ["swiftc", "-import-objc-header", str(frozen / (SCENE_SCRIPT / "SceneQuickJS.h").relative_to(REPOSITORY_ROOT)),
             *(str(frozen / p.relative_to(REPOSITORY_ROOT)) for p in SOURCES),
             str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = json.loads(
            subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            ).stdout
        )
        drift = [str(p) for p in inputs if hashlib.sha256(p.read_bytes()).hexdigest() != before[str(p)]]
        proof = os.environ.get("MWX_SCENE_PROPERTY_PROOF")
        if proof:
            output = Path(proof)
            output.mkdir(parents=True, exist_ok=True)
            (output / "runtime-input-freeze.json").write_text(json.dumps(before, indent=2) + "\n")
            (output / "runtime-result.json").write_text(json.dumps(cls.result, indent=2) + "\n")
            (output / "runtime-execution.json").write_text(json.dumps({
                "compiledFromFrozenCopy": True, "inputDrift": drift,
                "profileNumericLeafOnly": True,
            }, indent=2) + "\n")
        if drift:
            raise AssertionError(f"focused input drift: {drift}")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_perspective_is_typed_atomic_and_rejects_missing_consumers_locally(self) -> None:
        for key in ("perspectivePreflightReadOnly", "perspectiveImageTextAccepted",
                    "perspectiveFalseAndMissingBool", "perspectiveValueChangeKeepsSchemaAndTopology",
                    "perspectiveUnsupportedIsLocal"):
            self.assertTrue(self.result[key], key)

    def test_prepared_text_birth_projection_and_cascade_use_committed_membership(self) -> None:
        for key in ("templateBirthReadOnly", "templateBirthSeparatesSeedAndInit",
                    "templateUserAliasOnlyPreparedUser", "templateUserBoundsAreTargetLocal", "templateMirrorUsesLiveMembership",
                    "templateUnknownOrMissingRejectLocally", "templateExplicitSetterPublished",
                    "templateCreatorCascadeRetiresDescendants", "templateCascadeReleasesValuesDefinitionsAndAliases"):
            self.assertTrue(self.result[key], key)

    def test_create_and_value_update_publish_only_through_snapshots(self) -> None:
        self.assertTrue(self.result["createSucceeded"])
        self.assertTrue(self.result["priorSnapshotStable"])
        self.assertEqual(self.result["createdIDs"], [-1])
        self.assertTrue(self.result["moveSucceeded"])

    def test_static_transform_mutation_and_failed_batch_are_atomic(self) -> None:
        self.assertTrue(self.result["staticAccepted"])
        self.assertTrue(self.result["staticAnglesPublished"])
        self.assertTrue(self.result["staticVisibilityPublished"])
        self.assertTrue(self.result["peerUpdateAccepted"])
        self.assertTrue(self.result["peerScalePublished"])
        self.assertTrue(self.result["peerTextPublished"])
        self.assertTrue(self.result["peerFontPublished"])
        self.assertEqual(self.result["authoredDefinitionCount"], 12)
        self.assertTrue(self.result["authoredDefinitionTargets"])
        self.assertTrue(self.result["rejected"])
        self.assertTrue(self.result["failedBatchTextRolledBack"])
        self.assertEqual(self.result["rollbackLayers"], [-1])
        self.assertEqual(self.result["rollbackOrder"], [10, 20, -1])

    def test_visibility_lane_exists_before_the_first_authored_handle_write(self) -> None:
        self.assertTrue(self.result["visibilityLanesPreparedBeforeFirstWrite"])
        self.assertTrue(self.result["visibilityCandidatePublishedBeforeCommit"])
        self.assertTrue(self.result["visibilityPreflightIsReadOnly"])
        self.assertTrue(self.result["visibilityCommitRetainsLaneWithoutSchemaChange"])

    def test_instance_alpha_cannot_be_admitted_for_an_ordinary_layer(self) -> None:
        self.assertTrue(self.result["nonParticleInstanceAlphaRejected"])

    def test_destroy_removes_only_the_dynamic_layer(self) -> None:
        self.assertTrue(self.result["destroySucceeded"])
        self.assertEqual(self.result["destroyedIDs"], [])
        self.assertEqual(self.result["destroyedOrder"], [10, 20])

    def test_authored_self_destroy_is_atomic_persistent_topology(self) -> None:
        self.assertTrue(self.result["authoredDestroyPreflightWasReadOnly"])
        self.assertTrue(self.result["authoredDestroySucceeded"])
        self.assertEqual(self.result["authoredDestroyedIDs"], [10])
        self.assertEqual(self.result["authoredDestroyedOrder"], [20])
        self.assertTrue(self.result["authoredDestroyBumpsTopology"])
        self.assertTrue(self.result["authoredResurrectionRejected"])

    def test_bad_owner_does_not_reject_disjoint_owner_mutations(self) -> None:
        self.assertEqual(self.result["isolatedCommittedMutationCount"], 2)
        self.assertEqual(self.result["isolatedFailureCount"], 1)
        self.assertTrue(self.result["isolatedFailureOwnerIsB"])
        self.assertEqual(self.result["isolatedAdmittedOwnerCount"], 2)
        self.assertTrue(self.result["isolatedPreflightWasReadOnly"])
        self.assertTrue(self.result["isolatedPeerScalePublished"])
        self.assertTrue(self.result["isolatedDisjointAnglesPublished"])
        self.assertTrue(self.result["isolatedBadTextAbsent"])

    def test_identical_duplicate_owner_writes_coalesce_but_disagreement_rejects(self) -> None:
        self.assertTrue(self.result["identicalDuplicateOwnersAdmitted"])
        self.assertTrue(self.result["identicalDuplicateValuePublished"])
        self.assertTrue(self.result["conflictingLaterOwnerRejected"])

    def test_external_rejection_reaches_layer_admission_fixed_point(self) -> None:
        self.assertTrue(self.result["fixedPointSeeded"])
        self.assertTrue(self.result["fixedPointExternalRejectsA"])
        self.assertTrue(self.result["fixedPointLayerRejectsB"])
        self.assertTrue(self.result["fixedPointAdmitsOnlyC"])
        self.assertTrue(self.result["fixedPointPreservesFullTopology"])
        self.assertTrue(self.result["fixedPointCommitsDisjointC"])

    def test_particle_preflight_sees_this_round_rejected_owner_and_preserves_peer(self) -> None:
        self.assertTrue(self.result["particleSeesCurrentExternalReject"])
        self.assertTrue(self.result["particleFiltersWholeRejectedBundle"])
        self.assertTrue(self.result["particleKeepsValidPeer"])

    def test_dependency_rejection_replaces_previous_projection_candidate(self) -> None:
        self.assertTrue(self.result["laterRejectionReplacesProjection"])
        self.assertTrue(self.result["laterRejectionKeepsValidPeer"])
        self.assertTrue(self.result["typedOnlyReaderRejected"])

    def test_dynamic_image_preserves_its_own_color_in_stable_snapshots(self) -> None:
        self.assertTrue(self.result["dynamicImageSucceeded"])
        self.assertEqual(self.result["dynamicImageColor"], [0.25, 0.5, 0.75])
        self.assertTrue(self.result["dynamicImageUpdateSucceeded"])
        for actual, expected in zip(self.result["dynamicImageUpdatedColor"], [0.8, 0.4, 0.2]):
            self.assertAlmostEqual(actual, expected, places=6)

    def test_admitted_play_releases_setter_without_losing_rejected_or_paused_values(self) -> None:
        for key in (
            "replayCandidateIsReadOnly",
            "replayReleasesOnlyTargetIncludingImmediatePauseStop",
            "pausedSetterWithoutPlayIsRetained",
            "externallyRejectedPlayPreservesSetter",
            "invalidOwnerPlayPreservesSetter",
            "replayCommitKeepsSchemaAndPeer",
        ):
            with self.subTest(key=key):
                self.assertTrue(self.result[key])

    def test_definition_revision_tracks_schema_changes_only(self) -> None:
        self.assertTrue(self.result["definitionRevisionBumped"])
        self.assertTrue(self.result["valueOnlyRevisionStable"])

    def test_topology_revision_tracks_dynamic_projection_only(self) -> None:
        self.assertTrue(self.result["styleBeforeCommit"])
        self.assertTrue(self.result["styleAlphaPublished"])
        self.assertTrue(self.result["styleColorPublished"])
        self.assertTrue(self.result["styleFailurePreservesCurrent"])
        self.assertTrue(self.result["topologyRevisionStartsAtZero"])
        self.assertTrue(self.result["dynamicTopologyRevisionBumped"])
        self.assertTrue(self.result["dynamicValueKeepsTopologyRevision"])
        self.assertTrue(self.result["dynamicBeforeValueOrigin"])
        self.assertTrue(self.result["dynamicBeforeValueScale"])
        self.assertTrue(self.result["dynamicValueOriginPublished"])
        self.assertTrue(self.result["dynamicValueScalePublished"])
        self.assertTrue(self.result["authoredValueKeepsTopologyRevision"])


if __name__ == "__main__":
    unittest.main()
