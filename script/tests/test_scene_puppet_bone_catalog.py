#!/usr/bin/env python3

"""Contract tests for the fail-closed Puppet bone identity catalog."""

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
    SCENE_ROOT / "Format/SceneMdlPuppetMeshReader.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetRigReader.swift",
    SCENE_ROOT / "Format/ScenePuppetBoneCatalog.swift",
    SCENE_ROOT / "Runtime/SceneScript/ScenePuppetBoneTransformBridge.swift",
]

HARNESS = r'''
import Foundation
import simd

func rig(_ names: [String], parents: [Int]) -> SceneMdlPuppetRig {
    SceneMdlPuppetRig(
        bones: names.enumerated().map { index, name in
            .init(name: name, parentIndex: parents[index], bindLocalMatrixColumnMajor: [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            ])
        },
        vertexWeights: []
    )
}

func translation(_ x: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0), SIMD4(x, 0, 0, 1)
    ))
}

func rejected<T>(_ result: Result<T, Error>) -> Bool {
    if case .failure = result { return true }
    return false
}

@main
enum Harness {
    static func main() throws {
        let valid = try ScenePuppetBoneCatalog(rig: rig(
            ["root", "MouseBone", "tip"], parents: [-1, 0, 1]
        ))
        let duplicate = Result { try ScenePuppetBoneCatalog(rig: rig(
            ["root", "root"], parents: [-1, 0]
        )) }
        let unnamed = try ScenePuppetBoneCatalog(rig: rig(
            ["", ""], parents: [-1, 0]
        ))
        let invalidParent = Result { try ScenePuppetBoneCatalog(rig: rig(
            ["root", "child"], parents: [-1, 2]
        )) }
        var payload: [String: Any] = [
            "entries": valid.entries.map { [
                "index": $0.index,
                "name": $0.name,
                "parent": $0.parentIndex,
            ] },
            "mouseIndex": valid.index(forName: "MouseBone") as Any,
            "boneCount": valid.boneCount,
            "tipName": valid.name(at: 2) as Any,
            "unknownIndex": valid.index(forName: "missing") as Any,
            "emptyIndex": valid.index(forName: "") as Any,
            "tipParent": valid.parentIndex(of: 2) as Any,
            "outOfRange": valid.entry(at: 99) as Any,
            "duplicateRejected": rejected(duplicate),
            "unnamedCount": unnamed.boneCount,
            "unnamedIndex": unnamed.index(forName: "") as Any,
            "unnamedNumericIndex": ScenePuppetBoneScriptIndex.denseIndex(
                fromScriptIndex: 1, catalog: unnamed
            ) as Any,
            "invalidParentRejected": rejected(invalidParent),
            "computedView": rig(["root", "MouseBone"], parents: [-1, 0]).boneCatalog != nil,
        ]
        var frame = try ScenePuppetBoneTransformFrame(
            rig: rig(["root", "MouseBone"], parents: [-1, 0]),
            animatedLocalMatrices: [
                translation(2),
                translation(3),
            ]
        )
        let initialWorld = frame.getBoneTransform(forScriptIndex: 1)!
        try frame.setBoneTransform(
            translation(10),
            forScriptIndex: 1,
            rig: rig(["root", "MouseBone"], parents: [-1, 0])
        )
        let updatedLocal = frame.localTransform(forScriptIndex: 1)!
        let updatedWorld = frame.worldTransform(forScriptIndex: 1)!
        payload["scriptRootIndex"] = ScenePuppetBoneScriptIndex.getBoneIndex(
            "root", catalog: valid
        )
        payload["scriptUnknownIndex"] = ScenePuppetBoneScriptIndex.scriptIndex(
            forName: "missing", catalog: valid
        )
        payload["numericNegativeUnknown"] = frame.worldTransform(forScriptIndex: -1) == nil
        payload["initialWorldX"] = initialWorld.columns.3.x
        payload["updatedLocalX"] = updatedLocal.columns.3.x
        payload["updatedWorldX"] = updatedWorld.columns.3.x
        let boneRig = rig(["root", "MouseBone"], parents: [-1, 0])
        var placedFrame = try ScenePuppetBoneTransformFrame(
            rig: boneRig, animatedLocalMatrices: [translation(2), translation(3)],
            layerToWorld: translation(100)
        )
        payload["placedChildWorldX"] = placedFrame.worldMatrices[1].columns.3.x
        try placedFrame.setWorldTransform(translation(110), forScriptIndex: 0, rig: boneRig)
        payload["placedRootLocalX"] = placedFrame.localMatrices[0].columns.3.x
        payload["placedUpdatedChildWorldX"] = placedFrame.worldMatrices[1].columns.3.x
        let beforeLocal = frame.localMatrices
        let beforeWorld = frame.worldMatrices
        var nonFinite = matrix_identity_float4x4
        nonFinite.columns.0.x = .infinity
        payload["nonFiniteRejected"] = rejected(Result {
            try frame.setLocalTransform(nonFinite, forScriptIndex: 0, rig: boneRig)
        })
        payload["foreignRigRejected"] = rejected(Result {
            try frame.setBoneTransform(translation(7), forScriptIndex: 1,
                rig: rig(["other", "tip"], parents: [-1, 0]))
        })
        payload["rejectionsPreserveFrame"] = frame.localMatrices == beforeLocal
            && frame.worldMatrices == beforeWorld
        let huge = Float.greatestFiniteMagnitude
        var overflowFrame = try ScenePuppetBoneTransformFrame(
            rig: boneRig, animatedLocalMatrices: [translation(huge), translation(0)]
        )
        let overflowBefore = overflowFrame.worldMatrices
        payload["worldOverflowRejected"] = rejected(Result {
            try overflowFrame.setLocalTransform(
                translation(huge), forScriptIndex: 1, rig: boneRig
            )
        })
        payload["overflowPreservesFrame"] = overflowFrame.worldMatrices == overflowBefore
            && overflowFrame.localMatrices[1] == translation(0)
        var singular = matrix_identity_float4x4
        singular.columns.0 = .zero
        var singularFrame = try ScenePuppetBoneTransformFrame(
            rig: boneRig, animatedLocalMatrices: [singular, translation(0)]
        )
        payload["singularParentRejected"] = rejected(Result {
            try singularFrame.setBoneTransform(translation(1), forScriptIndex: 1, rig: boneRig)
        })
        let data = try JSONSerialization.data(withJSONObject: payload)
        FileHandle.standardOutput.write(data)
    }
}
'''


class ScenePuppetBoneCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        harness = tmp / "harness.swift"
        harness.write_text(HARNESS)
        cls.binary = tmp / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")
        completed = subprocess.run(
            [str(cls.binary)], capture_output=True, text=True
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_quickjs_layer_host_exposes_typed_puppet_bone_transaction(self):
        host = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJSLayerHost.c"
        ).read_text()
        for method in (
            "getBoneCount", "getBoneIndex", "getBoneTransform",
            "getLocalBoneTransform", "setBoneTransform",
            "setLocalBoneTransform",
        ):
            self.assertIn(f'"{method}"', host)
        self.assertIn("MWXSceneQuickJSPuppetBoneMutation", host)

    def test_launch_prepares_rig_and_installs_it_into_existing_owners(self):
        layer_load = (
            SCENE_ROOT / "Rendering/ScenePuppetLayerLoad.swift"
        ).read_text()
        launch = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text()
        vector = (
            SCENE_ROOT
            / "Runtime/SceneScript/SceneScriptVectorProgram+Registrations.swift"
        ).read_text()
        cursor = (
            SCENE_ROOT
            / "Runtime/SceneScript/SceneScriptCursorProgram+PuppetBones.swift"
        ).read_text()
        self.assertIn("static func boneConfiguration(", layer_load)
        self.assertIn("SceneMdlPuppetRigReader.read", layer_load)
        self.assertIn("context.configurePreparedPuppetBones()", launch)
        self.assertIn("configurePuppetBones(", vector)
        self.assertIn("configurePuppetBones(", cursor)

    def test_layer_world_transform_is_applied_to_root_and_world_setter(self):
        self.assertEqual(self.result["placedChildWorldX"], 105)
        self.assertEqual(self.result["placedRootLocalX"], 10)
        self.assertEqual(self.result["placedUpdatedChildWorldX"], 113)

    def test_preserves_authored_dense_identity_and_parent_links(self):
        self.assertEqual(
            self.result["entries"],
            [
                {"index": 0, "name": "root", "parent": -1},
                {"index": 1, "name": "MouseBone", "parent": 0},
                {"index": 2, "name": "tip", "parent": 1},
            ],
        )
        self.assertEqual(self.result["mouseIndex"], 1)
        self.assertEqual(self.result["boneCount"], 3)
        self.assertEqual(self.result["tipName"], "tip")
        self.assertEqual(self.result["tipParent"], 1)
        self.assertTrue(self.result["computedView"])

    def test_unknown_empty_and_out_of_range_queries_fail_closed(self):
        self.assertIsNone(self.result["unknownIndex"])
        self.assertIsNone(self.result["emptyIndex"])
        self.assertIsNone(self.result["outOfRange"])
        self.assertEqual(self.result["scriptRootIndex"], 0)
        self.assertEqual(self.result["scriptUnknownIndex"], -1)
        self.assertTrue(self.result["numericNegativeUnknown"])

    def test_world_transform_is_not_skin_inverse_bind_and_world_setter_is_parent_relative(self):
        self.assertEqual(self.result["initialWorldX"], 5)
        self.assertEqual(self.result["updatedLocalX"], 8)
        self.assertEqual(self.result["updatedWorldX"], 10)

    def test_ambiguous_or_invalid_authored_identity_is_rejected(self):
        self.assertTrue(self.result["duplicateRejected"])
        self.assertTrue(self.result["invalidParentRejected"])

    def test_unnamed_bones_retain_numeric_identity(self):
        self.assertEqual(self.result["unnamedCount"], 2)
        self.assertIsNone(self.result["unnamedIndex"])
        self.assertEqual(self.result["unnamedNumericIndex"], 1)

    def test_invalid_transform_transactions_preserve_previous_frame(self):
        for key in ["nonFiniteRejected", "foreignRigRejected", "rejectionsPreserveFrame",
                    "worldOverflowRejected", "overflowPreservesFrame", "singularParentRejected"]:
            self.assertTrue(self.result[key], key)


if __name__ == "__main__":
    unittest.main()
