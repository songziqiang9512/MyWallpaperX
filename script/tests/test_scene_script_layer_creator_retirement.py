#!/usr/bin/env python3
"""Authored leaf retirement removes its creators' dynamic copies in one plan."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_script_dynamic_layer_runtime import HARNESS as SUPPORT, SCENE_SCRIPT, SOURCES


HARNESS = SUPPORT.split("@main\n", 1)[0] + r'''
func retirementRuntime() -> SceneScriptDynamicLayerRuntime {
    .init(descriptor: .init(layers: [
        .init(id: 10, visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], anglesXYZ: [0, 0, 0]),
        .init(id: 20, visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], anglesXYZ: [0, 0, 0],
            contentKind: "text", text: "target", textStyle: .init(fontPath: nil)),
    ], renderOrderLayerIDs: [10, 20]), authoredMutationLayerIDs: [10, 20])
}
let controller = SceneDynamicTarget.layer(layerID: 10, field: .origin)
let targetOwner = SceneDynamicTarget.text(layerID: 20, field: .content)
func destroyTarget(order: Int = 1) -> SceneScriptLayerMutation {
    mutation(20, dynamic: false, kind: .destroy, order: order, ownerTarget: controller)
}
func sortingRuntime() -> SceneScriptDynamicLayerRuntime {
    .init(descriptor: .init(layers: [10, 20, 30, 40].map {
        .init(id: $0, visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], anglesXYZ: [0, 0, 0])
    }, renderOrderLayerIDs: [10, 20, 30, 40]), authoredMutationLayerIDs: [10, 20, 30, 40])
}
func seed(_ runtime: SceneScriptDynamicLayerRuntime) throws {
    try runtime.apply([
        mutation(-1, order: 2, ownerTarget: targetOwner),
        mutation(-2, order: 3, ownerTarget: controller),
        mutation(20, dynamic: false, text: "written", fields: [.text], ownerTarget: targetOwner),
    ]).get()
}
func ids(_ runtime: SceneScriptDynamicLayerRuntime) -> [Int] {
    runtime.snapshot().dynamicLayers.map(\.id).sorted()
}

@main enum RetirementHarness {
    static func main() throws {
        var output: [String: Any] = [:]
        let runtime = retirementRuntime()
        try seed(runtime)
        let original = runtime.snapshot()
        let originalCreators = runtime.preflightIsolatingOwners([]).dynamicLayerCreatorTargetsByID
        let plan = runtime.preflightIsolatingOwners([destroyTarget()])
        output["admission"] = ["readOnly": ids(runtime) == [-2, -1]
            && runtime.snapshot().destroyedAuthoredLayerIDs.isEmpty,
            "creatorRecorded": originalCreators[-1] == targetOwner && originalCreators[-2] == controller,
            "candidateCopies": plan.dynamicLayersByID.keys.sorted(),
            "candidateCreators": plan.dynamicLayerCreatorTargetsByID.keys.sorted(),
            "candidateOrder": plan.order, "candidateTextRemoved": plan.authoredLayerValues[
                .text(layerID: 20, field: .content)] == nil,
            "candidateDefinitionRemoved": !plan.authoredDefinitionOrder.contains(.text(layerID: 20, field: .content))
                && !plan.authoredDefinitionOrder.contains(.layer(layerID: 20, field: .visibility))]
        let revisionBefore = runtime.authoredDefinitionRevision
        runtime.commit(plan)
        output["committed"] = ["copies": ids(runtime), "order": runtime.snapshot().renderOrderLayerIDs,
            "deleted": runtime.snapshot().destroyedAuthoredLayerIDs.sorted(),
            "creators": runtime.preflightIsolatingOwners([]).dynamicLayerCreatorTargetsByID.keys.sorted(),
            "schemaChanged": runtime.authoredDefinitionRevision > revisionBefore,
            "oldSnapshotRetained": original.dynamicLayers.map(\.id).sorted() == [-2, -1]
                && original.destroyedAuthoredLayerIDs.isEmpty]

        var orders: [[Int]] = [], remaining: [[Int]] = []
        for createsFirst in [true, false] {
            let owner = retirementRuntime()
            try seed(owner)
            let create = SceneScriptOwnerEffects(ownerTarget: targetOwner,
                layerMutations: [mutation(-3, order: 4, ownerTarget: targetOwner)])
            let destroy = SceneScriptOwnerEffects(ownerTarget: controller, layerMutations: [destroyTarget()])
            let admission = owner.preflightOwnerEffects(createsFirst ? [create, destroy] : [destroy, create])
            owner.commit(admission.layerPlan)
            orders.append(owner.snapshot().renderOrderLayerIDs)
            remaining.append(ids(owner))
        }
        output["sameCadence"] = ["orders": orders, "copies": remaining]

        let fixedPoint = retirementRuntime()
        try seed(fixedPoint)
        let externallyRejected = fixedPoint.preflightOwnerEffectsToFixedPoint([
            .init(ownerTarget: controller, layerMutations: [destroyTarget()]),
            .init(ownerTarget: targetOwner, layerMutations: [mutation(-3, order: 4, ownerTarget: targetOwner)]),
        ], rejectingExternally: { effects in
            Set(effects.filter { $0.ownerTarget == controller }.map(\.ownerTarget))
        })
        fixedPoint.commit(externallyRejected.admission.layerPlan)
        output["fixedPoint"] = ["copies": ids(fixedPoint),
            "targetAlive": fixedPoint.snapshot().destroyedAuthoredLayerIDs.isEmpty,
            "creatorRetained": fixedPoint.preflightIsolatingOwners([]).dynamicLayerCreatorTargetsByID[-1] == targetOwner,
            "targetWriteRetained": fixedPoint.snapshot().authoredLayerValues[.text(layerID: 20, field: .content)]
                == .string("written")]

        let rejected = retirementRuntime()
        try seed(rejected)
        let duplicateBatch = rejected.apply([destroyTarget(), destroyTarget()])
        let writeAfterDelete = rejected.apply([destroyTarget(), mutation(20, dynamic: false,
            text: "write-after-delete", fields: [.text], ownerTarget: controller)])
        let failed = rejected.apply([destroyTarget(), mutation(-3, order: 4, alpha: .nan, ownerTarget: controller)])
        let untouched = rejected.preflightOwnerEffectsToFixedPoint([
            .init(ownerTarget: controller, layerMutations: [destroyTarget()]),
        ], excludingOwners: [controller], rejectingExternally: { _ in [] })
        rejected.commit(untouched.admission.layerPlan)
        output["rejection"] = ["badBundleRejected": !succeeded(failed),
            "duplicateBatchRejected": !succeeded(duplicateBatch), "writeAfterDeleteRejected": !succeeded(writeAfterDelete), "copies": ids(rejected),
            "order": rejected.snapshot().renderOrderLayerIDs,
            "targetAlive": rejected.snapshot().destroyedAuthoredLayerIDs.isEmpty,
            "creatorRetained": rejected.preflightIsolatingOwners([]).dynamicLayerCreatorTargetsByID[-1] == targetOwner]

        let sequential = retirementRuntime()
        let createDestroy = sequential.apply([
            mutation(-1, order: 2, ownerTarget: targetOwner), mutation(-1, kind: .destroy, ownerTarget: targetOwner),
            mutation(20, dynamic: false, fields: [.origin], origin: .init(7, 8, 9), ownerTarget: controller),
            mutation(20, dynamic: false, order: 0, ownerTarget: controller), destroyTarget(order: 0),
        ])
        output["sequential"] = ["accepted": succeeded(createDestroy), "copies": ids(sequential),
            "order": sequential.snapshot().renderOrderLayerIDs,
            "creatorsEmpty": sequential.preflightIsolatingOwners([]).dynamicLayerCreatorTargetsByID.isEmpty,
            "valuesEmpty": sequential.snapshot().authoredLayerValues.isEmpty]

        let stale = retirementRuntime()
        try seed(stale)
        stale.commit(stale.preflightIsolatingOwners([destroyTarget()]))
        let duplicate = stale.apply([destroyTarget()])
        let writeAfterDead = stale.preflightOwnerEffects([
            .init(ownerTarget: targetOwner, layerMutations: [mutation(20, dynamic: false,
                text: "resurrect", fields: [.text], ownerTarget: targetOwner)]),
            .init(ownerTarget: controller, layerMutations: [mutation(-4, order: 2, ownerTarget: controller)]),
        ])
        stale.commit(writeAfterDead.layerPlan)
        output["stale"] = ["duplicateRejected": !succeeded(duplicate),
            "rejectedOwner": writeAfterDead.rejectedOwners.first?.ownerTarget == targetOwner,
            "healthyAdmitted": writeAfterDead.admittedEffects.map(\.ownerTarget) == [controller],
            "copies": ids(stale), "deleted": stale.snapshot().destroyedAuthoredLayerIDs.sorted()]

        let provenance = retirementRuntime()
        try seed(provenance)
        try provenance.apply([mutation(-1, order: 2, text: "full-value-upsert", ownerTarget: controller)]).get()
        let creatorPreserved = provenance.preflightIsolatingOwners([]).dynamicLayerCreatorTargetsByID[-1] == targetOwner
        provenance.commit(provenance.preflightIsolatingOwners([destroyTarget()]))
        output["provenance"] = ["creatorPreserved": creatorPreserved, "copies": ids(provenance)]

        let typedCreators: [SceneDynamicTarget] = [
            .layer(layerID: 20, field: .origin), .text(layerID: 20, field: .content),
            .effectVisibility(layerID: 20, effectIndex: 0),
            .effectConstant(layerID: 20, effectIndex: 0, passIndex: 0, name: "value"),
            .materialConstant(layerID: 20, passIndex: 0, name: "value", materialPath: "material"),
            .particle(layerID: 20, field: .alpha), .scriptInstanceProperty(layerID: 20, path: ["visible"]),
        ]
        let cohort = retirementRuntime()
        var created = typedCreators.enumerated().map { index, target in
            mutation(-index - 1, order: index + 2, ownerTarget: target)
        }
        created.append(mutation(-100, order: 10, ownerTarget: controller))
        created.append(mutation(-200, order: 11))
        try cohort.apply(created).get()
        cohort.commit(cohort.preflightIsolatingOwners([destroyTarget()]))
        output["typedCohort"] = ids(cohort)

        let sorter = SceneDynamicTarget.layer(layerID: 20, field: .origin)
        let deleter = SceneDynamicTarget.layer(layerID: 40, field: .origin)
        let destroyFirst = mutation(10, dynamic: false, kind: .destroy, order: 0, ownerTarget: deleter)
        var survivingSortOrders: [[Int]] = [], creatorSortOrders: [[Int]] = []
        for sortFirst in [true, false] {
            // C's raw final catalog is [10, 30, 20, 40]. Authored 10 still
            // occupies its slot until the shared commit retires it.
            let owner = sortingRuntime()
            let sort = mutation(20, dynamic: false, order: 2, ownerTarget: sorter)
            let admission = owner.preflightIsolatingOwners(sortFirst ? [sort, destroyFirst] : [destroyFirst, sort])
            precondition(admission.outcome.failures.isEmpty, "surviving authored sort accepted")
            owner.commit(admission)
            survivingSortOrders.append(owner.snapshot().renderOrderLayerIDs)

            // C also retains the deleted author's copy in [10, -1, 30, 20,
            // 40] until owner teardown. Project both deferred slots together.
            let withCopy = sortingRuntime()
            try withCopy.apply([mutation(-1, order: 1,
                ownerTarget: .layer(layerID: 10, field: .origin))]).get()
            let sortPastCopy = mutation(20, dynamic: false, order: 3, ownerTarget: sorter)
            let plan = withCopy.preflightIsolatingOwners(sortFirst
                ? [sortPastCopy, destroyFirst] : [destroyFirst, sortPastCopy])
            precondition(plan.outcome.failures.isEmpty, "surviving sort past retired copy accepted")
            withCopy.commit(plan)
            creatorSortOrders.append(withCopy.snapshot().renderOrderLayerIDs)
            precondition(ids(withCopy).isEmpty, "retired creator copy removed")
        }
        let direct = sortingRuntime()
        try direct.apply([mutation(20, dynamic: false, order: 2, ownerTarget: sorter), destroyFirst]).get()
        survivingSortOrders.append(direct.snapshot().renderOrderLayerIDs)
        output["survivingSort"] = survivingSortOrders
        output["survivingCreatorSort"] = creatorSortOrders

        // Explicit dynamic deletion is immediate in C: the later sort's raw
        // index already excludes -1 and must not be compressed a second time.
        let immediate = sortingRuntime()
        try immediate.apply([mutation(-1, order: 1, ownerTarget: sorter)]).get()
        let immediatePlan = immediate.preflightIsolatingOwners([
            mutation(-1, kind: .destroy, ownerTarget: sorter),
            mutation(20, dynamic: false, order: 2, ownerTarget: sorter),
        ])
        immediate.commit(immediatePlan)
        output["explicitDynamicSort"] = ["accepted": immediatePlan.outcome.failures.isEmpty,
            "order": immediate.snapshot().renderOrderLayerIDs, "copies": ids(immediate)]

        let rejectedRetirement = sortingRuntime()
        let rejection = rejectedRetirement.preflightOwnerEffectsToFixedPoint([
            .init(ownerTarget: sorter, layerMutations: [mutation(20, dynamic: false, order: 2, ownerTarget: sorter)]),
            .init(ownerTarget: deleter, layerMutations: [destroyFirst]),
        ], rejectingExternally: { effects in
            Set(effects.filter { $0.ownerTarget == deleter }.map(\.ownerTarget))
        })
        rejectedRetirement.commit(rejection.admission.layerPlan)
        output["rejectedRetirementSort"] = ["order": rejectedRetirement.snapshot().renderOrderLayerIDs,
            "deleted": rejectedRetirement.snapshot().destroyedAuthoredLayerIDs.sorted()]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneScriptLayerCreatorRetirementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("Swift toolchain unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-script-creator-retirement-") as directory:
            root = Path(directory)
            source, binary = root / "Harness.swift", root / "runtime"
            source.write_text(HARNESS, encoding="utf-8")
            command = ["swiftc", "-import-objc-header", str(SCENE_SCRIPT / "SceneQuickJS.h"),
                       *map(str, SOURCES), str(source), "-o", str(binary)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=30)
            cls.result = json.loads(result.stdout)

    def test_candidate_and_commit_remove_creator_copies_order_values_definitions_atomically(self) -> None:
        candidate, committed = self.result["admission"], self.result["committed"]
        for key in ("readOnly", "creatorRecorded", "candidateTextRemoved", "candidateDefinitionRemoved"):
            self.assertTrue(candidate[key], key)
        self.assertEqual(candidate["candidateCopies"], [-2])
        self.assertEqual(candidate["candidateCreators"], [-2])
        self.assertEqual(candidate["candidateOrder"], [10, -2])
        self.assertEqual(committed["copies"], [-2])
        self.assertEqual(committed["order"], [10, -2])
        self.assertEqual(committed["deleted"], [20])
        self.assertEqual(committed["creators"], [-2])
        self.assertTrue(committed["schemaChanged"])
        self.assertTrue(committed["oldSnapshotRetained"])

    def test_same_cadence_target_create_disappears_before_or_after_destroy_owner(self) -> None:
        self.assertEqual(self.result["sameCadence"], {"orders": [[10, -2], [10, -2]], "copies": [[-2], [-2]]})

    def test_fixed_point_rejecting_destroy_restores_creator_and_accepts_healthy_create(self) -> None:
        result = self.result["fixedPoint"]
        self.assertEqual(result["copies"], [-3, -2, -1])
        for key in ("targetAlive", "creatorRetained", "targetWriteRetained"):
            self.assertTrue(result[key], key)

    def test_rejected_or_discarded_delete_leaves_all_committed_creator_state_alive(self) -> None:
        result = self.result["rejection"]
        self.assertTrue(result["badBundleRejected"])
        self.assertTrue(result["duplicateBatchRejected"])
        self.assertTrue(result["writeAfterDeleteRejected"])
        self.assertEqual(result["copies"], [-2, -1])
        self.assertEqual(result["order"], [10, 20, -1, -2])
        self.assertTrue(result["targetAlive"])
        self.assertTrue(result["creatorRetained"])

    def test_sequential_create_destroy_and_sort_destroy_leave_no_ghost_order(self) -> None:
        result = self.result["sequential"]
        self.assertTrue(result["accepted"])
        self.assertEqual(result["copies"], [])
        self.assertEqual(result["order"], [10])
        self.assertTrue(result["creatorsEmpty"])
        self.assertTrue(result["valuesEmpty"])

    def test_duplicate_destroy_and_write_after_dead_reject_locally_and_keep_healthy_creator(self) -> None:
        result = self.result["stale"]
        for key in ("duplicateRejected", "rejectedOwner", "healthyAdmitted"):
            self.assertTrue(result[key], key)
        self.assertEqual(result["copies"], [-4, -2])
        self.assertEqual(result["deleted"], [20])

    def test_complete_value_upserts_cannot_reassign_original_creator(self) -> None:
        self.assertEqual(self.result["provenance"], {"creatorPreserved": True, "copies": [-2]})

    def test_all_layer_scoped_typed_creator_targets_retire_without_cross_talk(self) -> None:
        self.assertEqual(self.result["typedCohort"], [-200, -100])

    def test_surviving_sort_uses_full_raw_positions_before_authored_retirement(self) -> None:
        self.assertEqual(self.result["survivingSort"], [[30, 20, 40]] * 3)
        self.assertEqual(self.result["rejectedRetirementSort"], {"order": [10, 30, 20, 40], "deleted": []})

    def test_surviving_sort_projects_creator_copy_slots_only_after_raw_order(self) -> None:
        self.assertEqual(self.result["survivingCreatorSort"], [[30, 20, 40]] * 2)

    def test_explicit_dynamic_destroy_preserves_immediate_order_compression(self) -> None:
        self.assertEqual(self.result["explicitDynamicSort"],
                         {"accepted": True, "order": [10, 30, 20, 40], "copies": []})


if __name__ == "__main__":
    unittest.main()
