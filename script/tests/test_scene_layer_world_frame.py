#!/usr/bin/env python3

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
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/ScenePuppetAttachmentFrameSnapshot.swift",
    SCENE_ROOT / "Rendering/SceneLayerWorldFrameResolver.swift",
    SCENE_ROOT / "Rendering/SceneLayerDynamicWorldFrameResolver.swift",
    SCENE_ROOT
    / "Runtime/SceneScript/SceneScriptLayerWorldTransformProjection.swift",
]

HARNESS = r'''
import Foundation
import simd

struct SceneRenderDescriptor {
    struct Camera { let orthoHeight: Float? }
    struct Layer {
        let id: Int
        let parentID: Int?
        var attachmentName: String? = nil
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        let parentAttachmentBindFrame: [Float]?
    }
    let layers: [Layer]
    let camera: Camera
}

func attachmentFrame(x: Float, y: Float) -> [Float] {
    [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, 0, 1,
    ]
}

func result(
    parentScale: [Float] = [1, 1, 1],
    attachment: [Float]?
) -> [String: [Double]] {
    let parent = SceneRenderDescriptor.Layer(
        id: 1,
        parentID: nil,
        originXYZ: [100, 50, 0],
        scaleXYZ: parentScale,
        anglesXYZ: nil,
        parentAttachmentBindFrame: nil
    )
    let child = SceneRenderDescriptor.Layer(
        id: 2,
        parentID: 1,
        originXYZ: [10, 20, 0],
        scaleXYZ: nil,
        anglesXYZ: nil,
        parentAttachmentBindFrame: attachment
    )
    let frames = SceneLayerWorldFrameResolver.compute(
        layers: [parent, child],
        byID: [1: parent, 2: child],
        sceneOrthoHeight: 1_000
    )
    return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
        (
            String(id),
            [Double(frame.columns.3.x), Double(frame.columns.3.y)]
        )
    })
}

func dynamicResult() -> [String: [Double]] {
    let parent = SceneRenderDescriptor.Layer(
        id: 1, parentID: nil, originXYZ: [100, 50, 0], scaleXYZ: nil,
        anglesXYZ: [0, 0, 0], parentAttachmentBindFrame: nil
    )
    let child = SceneRenderDescriptor.Layer(
        id: 2, parentID: 1, originXYZ: [10, 0, 0], scaleXYZ: nil,
        anglesXYZ: nil, parentAttachmentBindFrame: nil
    )
    let descriptor = SceneRenderDescriptor(
        layers: [parent, child], camera: .init(orthoHeight: 1_000)
    )
    let byID = [1: parent, 2: child]
    let staticFrames = SceneLayerWorldFrameResolver.compute(
        layers: descriptor.layers, byID: byID, sceneOrthoHeight: 1_000
    )
    let target = SceneDynamicTarget.layer(layerID: 1, field: .angles)
    let snapshot = SceneDynamicSnapshotResolver().resolve(
        frameIndex: 1,
        generation: 1,
        definitions: [.init(
            target: target, valueType: .vector3, authoredValue: .vector3(0, 0, 0)
        )],
        timelineValues: [target: .vector3(0, 0, Double.pi / 2)]
    ).snapshot
    guard let projection = SceneScriptLayerWorldTransformProjection(
        descriptor: descriptor, catalogSignature: "dynamic"
    ) else { fatalError("projection preparation failed") }
    let frames = projection.worldFrames(for: snapshot)
    return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
        (String(id), [
            Double(frame.columns.0.x), Double(frame.columns.0.y),
            Double(frame.columns.3.x), Double(frame.columns.3.y),
        ])
    })
}

func dynamicAttachmentResult() -> [String: [Double]] {
    let parent = SceneRenderDescriptor.Layer(
        id: 1, parentID: nil, originXYZ: [100, 50, 0], scaleXYZ: nil,
        anglesXYZ: nil, parentAttachmentBindFrame: nil
    )
    let child = SceneRenderDescriptor.Layer(
        id: 2, parentID: 1, attachmentName: "Attachment",
        originXYZ: [10, 20, 0], scaleXYZ: nil,
        anglesXYZ: nil, parentAttachmentBindFrame: attachmentFrame(x: 30, y: 40)
    )
    let descriptor = SceneRenderDescriptor(
        layers: [parent, child], camera: .init(orthoHeight: 1_000)
    )
    guard let projection = SceneScriptLayerWorldTransformProjection(
        descriptor: descriptor, catalogSignature: "dynamic-attachment"
    ) else { fatalError("dynamic attachment projection failed") }
    let frames = projection.worldFrames(
        for: .empty(frameIndex: 0),
        puppetAttachmentFrames: .init(framesByParentLayerID: [
            1: ["Attachment": simd_float4x4(columns: (
                SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
                SIMD4(0, 0, 1, 0), SIMD4(50, 60, 0, 1)
            ))]
        ])
    )
    return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
        (String(id), [Double(frame.columns.3.x), Double(frame.columns.3.y)])
    })
}

func projectionColumnMajorResult() -> [Double] {
    let parent = SceneRenderDescriptor.Layer(
        id: 1, parentID: nil, originXYZ: [100, 50, 0], scaleXYZ: nil,
        anglesXYZ: nil, parentAttachmentBindFrame: nil
    )
    let child = SceneRenderDescriptor.Layer(
        id: 2, parentID: 1, originXYZ: [10, 20, 0], scaleXYZ: nil,
        anglesXYZ: nil, parentAttachmentBindFrame: nil
    )
    let descriptor = SceneRenderDescriptor(
        layers: [parent, child], camera: .init(orthoHeight: 1_000)
    )
    guard let projection = SceneScriptLayerWorldTransformProjection(
        descriptor: descriptor, catalogSignature: "column-major"
    ), let childFrame = projection.worldFrames(
        for: .empty(frameIndex: 0)
    )[2] else { fatalError("static projection failed") }
    return SceneScriptLayerWorldTransformProjection
        .columnMajorValues(childFrame)
}

func rejectsNonFiniteProjection() -> Bool {
    let invalid = SceneRenderDescriptor.Layer(
        id: 1, parentID: nil, originXYZ: [0, 0, 0],
        scaleXYZ: [.infinity, 1, 1], anglesXYZ: nil,
        parentAttachmentBindFrame: nil
    )
    let descriptor = SceneRenderDescriptor(
        layers: [invalid], camera: .init(orthoHeight: 1_000)
    )
    return SceneScriptLayerWorldTransformProjection(
        descriptor: descriptor, catalogSignature: "invalid"
    ) == nil
}

func nativePerspectiveResult() -> [String: [Double]] {
    let parent = SceneRenderDescriptor.Layer(
        id: 1,
        parentID: nil,
        originXYZ: [1, 2, 3],
        scaleXYZ: nil,
        anglesXYZ: [0, 0, 0.25],
        parentAttachmentBindFrame: nil
    )
    let child = SceneRenderDescriptor.Layer(
        id: 2,
        parentID: 1,
        originXYZ: [0, 4, 0],
        scaleXYZ: nil,
        anglesXYZ: nil,
        parentAttachmentBindFrame: nil
    )
    let frames = SceneLayerWorldFrameResolver.compute(
        layers: [parent, child],
        byID: [1: parent, 2: child],
        sceneOrthoHeight: nil
    )
    return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
        (String(id), [
            Double(frame.columns.0.x), Double(frame.columns.0.y),
            Double(frame.columns.3.x), Double(frame.columns.3.y),
            Double(frame.columns.3.z),
        ])
    })
}

@main
enum Harness {
    static func main() throws {
        let result: [String: Any] = [
            "plain": result(attachment: nil),
            "attached": result(attachment: attachmentFrame(x: 30, y: 40)),
            "scaledParent": result(
                parentScale: [2, 2, 1],
                attachment: attachmentFrame(x: 30, y: 40)
            ),
            "invalidFrame": result(attachment: [1, 2, 3]),
            "dynamic": dynamicResult(),
            "dynamicAttachment": dynamicAttachmentResult(),
            "projectionColumnMajor": projectionColumnMajorResult(),
            "projectionRejectsNonFinite": rejectsNonFiniteProjection(),
            "nativePerspective": nativePerspectiveResult(),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneLayerWorldFrameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-layer-world-frame-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-layer-world-frame"
        subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *map(str, SWIFT_SOURCES),
                str(harness),
                "-o",
                str(binary),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_attachment_frame_is_between_parent_and_child_local_frame(self) -> None:
        self.assertEqual(self.result["plain"]["2"], [110, 930])
        self.assertEqual(self.result["attached"]["2"], [140, 970])

    def test_parent_transform_applies_before_attachment_frame(self) -> None:
        self.assertEqual(self.result["scaledParent"]["2"], [180, 990])

    def test_invalid_attachment_frame_falls_back_to_normal_parenting(self) -> None:
        self.assertEqual(self.result["invalidFrame"]["2"], [110, 930])

    def test_current_puppet_attachment_replaces_bind_frame_in_canonical_hierarchy(self) -> None:
        self.assertEqual(self.result["dynamicAttachment"]["2"], [160, 990])

    def test_dynamic_parent_rotation_updates_its_basis_and_child_world_frame(self) -> None:
        parent = self.result["dynamic"]["1"]
        child = self.result["dynamic"]["2"]
        self.assertAlmostEqual(parent[0], 0, places=5)
        self.assertAlmostEqual(parent[1], -1, places=5)
        self.assertAlmostEqual(child[2], 100, places=5)
        self.assertAlmostEqual(child[3], 940, places=5)

    def test_native_perspective_hierarchy_preserves_authored_world_axes(self) -> None:
        parent = self.result["nativePerspective"]["1"]
        child = self.result["nativePerspective"]["2"]
        self.assertAlmostEqual(parent[0], 0.9689124, places=5)
        self.assertAlmostEqual(parent[1], 0.2474040, places=5)
        self.assertEqual(parent[2:], [1, 2, 3])
        self.assertAlmostEqual(child[2], 1 - 4 * 0.2474040, places=5)
        self.assertAlmostEqual(child[3], 2 + 4 * 0.9689124, places=5)
        self.assertAlmostEqual(child[4], 3, places=5)

    def test_dynamic_world_frame_uses_snapshot_transform_index(self) -> None:
        resolver = (
            SCENE_ROOT / "Rendering/SceneLayerDynamicWorldFrameResolver.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("snapshot.dynamicTransformLayerIDsForFrame", resolver)
        self.assertIn("guard let layer = byID[layerID]", resolver)

    def test_scenescript_projection_preserves_column_major_mat4_abi(self) -> None:
        matrix = self.result["projectionColumnMajor"]
        self.assertEqual(len(matrix), 16)
        self.assertEqual(matrix[0:2], [1, 0])
        self.assertEqual(matrix[12:14], [110, 930])

    def test_scenescript_projection_rejects_nonfinite_world_frames(self) -> None:
        self.assertTrue(self.result["projectionRejectsNonFinite"])


if __name__ == "__main__":
    unittest.main()
