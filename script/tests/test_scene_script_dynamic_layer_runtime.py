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

# Add behavior to the existing harness while leaving its shared fixture intact.
HARNESS = HARNESS.replace('let payload: [String: Any] = [', 'var payload: [String: Any] = [').replace(
    '        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])',
    '        payload["ownerCallbacks"] = callbackCoalescing()\n'
    '        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])')
HARNESS += r'''
extension Harness {
    static func callbackCoalescing() -> [String: Bool] {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: 10, visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], anglesXYZ: [0,0,0]),
            .init(id: 20, visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], anglesXYZ: [0,0,0],
                contentKind: "text", text: "authored", textStyle: .init(fontPath: nil))],
            renderOrderLayerIDs: [10,20])
        let a = SceneDynamicTarget.layer(layerID: 10, field: .origin)
        let b = SceneDynamicTarget.layer(layerID: 20, field: .origin)
        let bad = SceneDynamicTarget.layer(layerID: 10, field: .angles)
        let peer = SceneDynamicTarget.layer(layerID: 20, field: .angles)
        let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [])
        let effects = [
            SceneScriptOwnerEffects(ownerTarget: a, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.2, fields: [.alpha, .scale], scale: .init(2,3,4), ownerTarget: a)]),
            SceneScriptOwnerEffects(ownerTarget: b, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.1, fields: [.alpha], ownerTarget: b),
                mutation(20, dynamic: false, text: "retained", fields: [.text], ownerTarget: b)]),
            SceneScriptOwnerEffects(ownerTarget: a, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.6, fields: [.alpha, .visibility], visible: false, ownerTarget: a)]),
            SceneScriptOwnerEffects(ownerTarget: b, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.6, fields: [.alpha], ownerTarget: b)]),
            SceneScriptOwnerEffects(ownerTarget: bad, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.6, fields: [.alpha], ownerTarget: bad),
                mutation(20, dynamic: false, fields: [.visibility], visible: false, ownerTarget: bad)]),
            SceneScriptOwnerEffects(ownerTarget: bad, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.8, fields: [.alpha], ownerTarget: bad)]),
            SceneScriptOwnerEffects(ownerTarget: peer, layerMutations: [
                mutation(20, dynamic: false, fields: [.scale], scale: .init(5,6,7), ownerTarget: peer)])]
        let admission = runtime.preflightOwnerEffects(effects)
        let readOnly = runtime.snapshot().authoredLayerValues.isEmpty
        runtime.commit(admission.layerPlan)
        let snapshot = runtime.snapshot()
        let rawRejected = [0.2, 0.6].allSatisfy { alpha in
            let raw = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [])
            let result = raw.apply([
                mutation(10, dynamic: false, alpha: 0.2, fields: [.alpha], ownerTarget: a),
                mutation(10, dynamic: false, alpha: alpha, fields: [.alpha], ownerTarget: a)])
            return !succeeded(result) && raw.snapshot().authoredLayerValues.isEmpty
        }
        let order = OrderInput()
        order.value = [10,-2,20,-1]
        let dynamic = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [],
            layerOrderProjection: { _ in .success(order.value) })
        let births = [mutation(-1, text: "seed", fields: [.created], origin: .init(1,2,3),
                              scale: .init(2,2,2), ownerTarget: a),
                      mutation(-2, text: "peer birth", fields: [.created], ownerTarget: a),
                      mutation(-3, text: "transient", fields: [.created], ownerTarget: a)]
        let birth = dynamic.preflightOwnerEffects([
            .init(ownerTarget: a, layerMutations: births),
            .init(ownerTarget: a, layerMutations: [
                mutation(-1, order: 2, text: "complete final", origin: .init(9,8,7), visible: false, ownerTarget: a),
                mutation(-3, kind: .destroy, ownerTarget: a),
                mutation(-3, text: "cannot resurrect", ownerTarget: a)])])
        let birthReadOnly = dynamic.snapshot().dynamicLayers.isEmpty
        dynamic.commit(birth.layerPlan)
        let born = dynamic.snapshot()
        let final = born.dynamicLayers.first { $0.id == -1 }
        let staleBirth = dynamic.preflightOwnerEffects([.init(ownerTarget: a, layerMutations: [births[0]])])
        order.value = [10,20]
        let retire = dynamic.preflightOwnerEffects([
            .init(ownerTarget: a, layerMutations: [mutation(-1, kind: .destroy, ownerTarget: a)]),
            .init(ownerTarget: a, layerMutations: [mutation(-2, kind: .destroy, ownerTarget: a)])])
        dynamic.commit(retire.layerPlan)
        let retired = dynamic.snapshot()
        let single = mutation(10, dynamic: false, fields: [.visibility], ownerTarget: a)
        return [
            "preflightReadOnly": readOnly && birthReadOnly,
            "lastCallbackWinsAndPreservesFields": snapshot.authoredLayerValues[.layer(layerID: 10, field: .alpha)] == .scalar(0.6)
                && snapshot.authoredLayerValues[.layer(layerID: 10, field: .scale)] == .vector3(2,3,4)
                && snapshot.authoredLayerValues[.layer(layerID: 10, field: .visibility)] == .bool(false),
            "conflictUsesFinalValues": admission.admittedEffects.map(\.ownerTarget) == [a,b,a,b,peer]
                && snapshot.authoredLayerValues[.text(layerID: 20, field: .content)] == .string("retained"),
            "divergentOwnerRejectedAtomically": admission.rejectedOwners.map(\.ownerTarget) == [bad]
                && snapshot.authoredLayerValues[.layer(layerID: 20, field: .visibility)] == nil,
            "healthyPeerSurvives": snapshot.authoredLayerValues[.layer(layerID: 20, field: .scale)] == .vector3(5,6,7),
            "rawDuplicatesStillReject": rawRejected,
            "emptyAndSingleInputUnchanged": SceneScriptLayerMutation.coalescing([]).isEmpty
                && SceneScriptLayerMutation.coalescing([single]) == [single],
            "dynamicUsesCompleteLatestRecord": birth.rejectedOwners.isEmpty && final?.text == "complete final"
                && final?.originXYZ == [9,8,7] && final?.scaleXYZ == [1,1,1] && final?.visible == false,
            "createdMarkerAndOrderSurvive": birth.layerPlan.dynamicLayerCreatorTargetsByID[-1] == a
                && Set(birth.layerPlan.createdDynamicLayerMutations.map(\.layerID)) == [-1,-2,-3]
                && born.renderOrderLayerIDs == [10,-2,20,-1],
            "destroyIsTerminalWithinOwner": born.dynamicLayers.map(\.id).sorted() == [-2,-1]
                && birth.layerPlan.dynamicLayerCreatorTargetsByID[-3] == nil,
            "newbornCannotReplaceCommittedLayer": staleBirth.rejectedOwners.map(\.ownerTarget) == [a],
            "retirementPreservesStableSnapshots": retire.rejectedOwners.isEmpty && retired.dynamicLayers.isEmpty
                && retired.renderOrderLayerIDs == [10,20] && born.dynamicLayers.count == 2
                && retired.topologyRevision > born.topologyRevision]
    }
}
'''


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

    def test_ordered_owner_callbacks_coalesce_before_conflict_admission(self) -> None:
        for behavior, passed in self.result["ownerCallbacks"].items():
            self.assertTrue(passed, behavior)

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

    def test_unpublished_parent_still_retires_its_live_creator_descendants(self) -> None:
        self.assertTrue(self.result["transientCreatorClosureReadOnly"])
        self.assertTrue(self.result["transientCreatorClosureRetiresDescendants"])

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
