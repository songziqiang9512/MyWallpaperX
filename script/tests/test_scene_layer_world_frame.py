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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAttachmentFrameSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerWorldFrameResolver.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerDynamicWorldFrameResolver.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerWorldTransformProjection.swift",
]

HARNESS = r'''
import Foundation
import simd

struct SceneParticleCameraFrame {
    struct NativePerspectiveOverride {}
    static func usesNativePerspective(camera: SceneRenderDescriptor.Camera, nativePerspectiveOverride: NativePerspectiveOverride? = nil) -> Bool { false }
    static func nativePerspectiveOverride(
        descriptor: SceneRenderDescriptor, layersByID: [Int: SceneRenderDescriptor.Layer],
        worldFrames: [Int: simd_float4x4], dynamicValues: SceneDynamicSnapshot
    ) -> NativePerspectiveOverride? { nil }
}

struct SceneRenderDescriptor {
    struct Camera {
        let orthoHeight: Float?
        var default2DOriginInputLayerID: Int? { nil }
    }
    struct Layer {
        var cameraPath: Bool? = nil
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

func fixedDynamicBirthResult(orthoHeight: Float?) -> [String: [String: [Double]]] {
    let birth = SceneRenderDescriptor.Layer(
        id: 10, parentID: nil, originXYZ: [10, 20, 3], scaleXYZ: [1, 1, 1],
        anglesXYZ: [0, 0, 0], parentAttachmentBindFrame: nil
    )
    let parent = SceneRenderDescriptor.Layer(
        id: 1, parentID: nil, originXYZ: [100, 50, 0], scaleXYZ: [2, 2, 1],
        anglesXYZ: [0, 0, 0], parentAttachmentBindFrame: nil
    )
    let child = SceneRenderDescriptor.Layer(
        id: 2, parentID: 1, attachmentName: "Attachment",
        originXYZ: [10, 20, 0], scaleXYZ: nil, anglesXYZ: nil,
        parentAttachmentBindFrame: attachmentFrame(x: 30, y: 40)
    )
    let descriptor = SceneRenderDescriptor(layers: [parent, child, birth],
        camera: .init(orthoHeight: orthoHeight))
    let byID = [1: parent, 2: child, 10: birth]
    let staticFrames = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: byID)
    let origin = SceneDynamicTarget.layer(layerID: 10, field: .origin)
    let scale = SceneDynamicTarget.layer(layerID: 10, field: .scale)
    let angles = SceneDynamicTarget.layer(layerID: 10, field: .angles)
    let parentAngles = SceneDynamicTarget.layer(layerID: 1, field: .angles)
    let definitions: [SceneDynamicTargetDefinition] = [
        .init(target: origin, valueType: .vector3, authoredValue: .vector3(10, 20, 3)),
        .init(target: scale, valueType: .vector3, authoredValue: .vector3(1, 1, 1)),
        .init(target: angles, valueType: .vector3, authoredValue: .vector3(0, 0, 0)),
        .init(target: parentAngles, valueType: .vector3, authoredValue: .vector3(0, 0, 0)),
    ]
    func resolved(_ phase: UInt64, rotateParent: Bool = false,
                  attachments: ScenePuppetAttachmentFrameSnapshot = .empty) -> [Int: simd_float4x4] {
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: phase, generation: phase, definitions: definitions,
            timelineValues: rotateParent ? [parentAngles: .vector3(0, 0, Double.pi / 2)] : [:],
            sceneScriptValues: [
                origin: phase == 1 ? .vector3(30, 40, 5) : .vector3(60, 70, 9),
                scale: phase == 1 ? .vector3(2, 3, 4) : .vector3(4, 2, 1),
                angles: .vector3(0, 0, phase == 1 ? 0 : Double.pi / 2),
            ]
        ).snapshot
        return SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: descriptor, byID: byID, snapshot: snapshot, staticFrames: staticFrames,
            dynamicLayerIDs: [10], puppetAttachmentFrames: attachments)
    }
    let first = resolved(1), second = resolved(2)
    let repeatedFirst = resolved(1)
    let mixed = resolved(2, rotateParent: true)
    let attached = resolved(1, attachments: .init(framesByParentLayerID: [
        1: ["Attachment": simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(50, 60, 0, 1)
        ))]
    ]))
    return ["birth": staticFrames, "first": first, "second": second,
            "repeatedFirst": repeatedFirst, "mixed": mixed, "attached": attached].mapValues { frames in
        Dictionary(uniqueKeysWithValues: frames.map { id, frame in
            (String(id), SceneScriptLayerWorldTransformProjection.columnMajorValues(frame))
        })
    }
}

func overRangeOriginResult(_ origin: Double) -> [String: [Double]] {
    let layer = SceneRenderDescriptor.Layer(
        id: 1, parentID: nil, originXYZ: [10, 20, 0], scaleXYZ: nil,
        anglesXYZ: nil, parentAttachmentBindFrame: nil
    )
    let descriptor = SceneRenderDescriptor(
        layers: [layer], camera: .init(orthoHeight: 1_000)
    )
    let target = SceneDynamicTarget.layer(layerID: 1, field: .origin)
    let snapshot = SceneDynamicSnapshotResolver().resolve(
        frameIndex: 1,
        generation: 1,
        definitions: [.init(
            target: target, valueType: .vector3,
            authoredValue: .vector3(10, 20, 0)
        )],
        sceneScriptValues: [target: .vector3(origin, 0, 0)]
    ).snapshot
    guard let projection = SceneScriptLayerWorldTransformProjection(
        descriptor: descriptor, catalogSignature: "over-range"
    ), let frame = projection.worldFrames(for: snapshot)[1] else {
        fatalError("over-range projection failed")
    }
    return ["translation": [
        Double(frame.columns.3.x), Double(frame.columns.3.y),
    ]]
}

func mixedRangeTransformResult() -> [String: [Double]] {
    let layer = SceneRenderDescriptor.Layer(
        id: 1, parentID: nil, originXYZ: [10, 20, 0], scaleXYZ: [1, 1, 1],
        anglesXYZ: nil, parentAttachmentBindFrame: nil
    )
    let descriptor = SceneRenderDescriptor(
        layers: [layer], camera: .init(orthoHeight: 1_000)
    )
    let originTarget = SceneDynamicTarget.layer(layerID: 1, field: .origin)
    let scaleTarget = SceneDynamicTarget.layer(layerID: 1, field: .scale)
    let snapshot = SceneDynamicSnapshotResolver().resolve(
        frameIndex: 1,
        generation: 1,
        definitions: [
            .init(target: originTarget, valueType: .vector3,
                  authoredValue: .vector3(10, 20, 0)),
            .init(target: scaleTarget, valueType: .vector3,
                  authoredValue: .vector3(1, 1, 1)),
        ],
        sceneScriptValues: [
            originTarget: .vector3(4.67278316e38, 0, 0),
            scaleTarget: .vector3(2, 2, 1),
        ]
    ).snapshot
    guard let projection = SceneScriptLayerWorldTransformProjection(
        descriptor: descriptor, catalogSignature: "mixed-range"
    ), let frame = projection.worldFrames(for: snapshot)[1] else {
        fatalError("mixed-range projection failed")
    }
    return ["translation": [
        Double(frame.columns.3.x), Double(frame.columns.3.y),
    ], "scale": [Double(frame.columns.0.x), Double(frame.columns.1.y)]]
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


// Compare a complete hierarchy in author space with its converted runtime
// points. The oracle reflects world points, rather than editing Euler angles.
func reflectedHierarchyResult(dynamic: Bool, orthoHeight: Float?) -> Double {
    let parent = SceneRenderDescriptor.Layer(
        id: 1, parentID: nil, originXYZ: [100, 50, 7],
        scaleXYZ: [2, -1.5, 0.75], anglesXYZ: [0.4, -0.3, 0.6],
        parentAttachmentBindFrame: nil
    )
    let child = SceneRenderDescriptor.Layer(
        id: 2, parentID: 1, originXYZ: [10, 20, 9],
        scaleXYZ: [0.8, 1.2, -1], anglesXYZ: [-0.7, 0.2, -0.1],
        parentAttachmentBindFrame: nil
    )
    let descriptor = SceneRenderDescriptor(layers: [parent, child],
        camera: .init(orthoHeight: orthoHeight))
    let byID = [1: parent, 2: child]
    let staticFrames = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: byID)
    let angles = SIMD3<Float>(-0.25, 0.55, -0.45)
    let target = SceneDynamicTarget.layer(layerID: 1, field: .angles)
    let snapshot = SceneDynamicSnapshotResolver().resolve(
        frameIndex: 3, generation: 1,
        definitions: [.init(target: target, valueType: .vector3,
            authoredValue: .vector3(0.4, -0.3, 0.6))],
        timelineValues: dynamic ? [target: .vector3(Double(angles.x), Double(angles.y), Double(angles.z))] : [:]
    ).snapshot
    let frames = SceneLayerDynamicWorldFrameResolver.resolve(
        descriptor: descriptor, byID: byID, snapshot: snapshot, staticFrames: staticFrames)
    func authored(_ layer: SceneRenderDescriptor.Layer, angles: SIMD3<Float>? = nil) -> simd_float4x4 {
        SceneMatrix.translation(SIMD3(layer.originXYZ!, fill: 0))
            * SceneMatrix.eulerXYZ(angles ?? SIMD3(layer.anglesXYZ!, fill: 0))
            * SceneMatrix.scale(SIMD3(layer.scaleXYZ!, fill: 1))
    }
    let parentAuthor = authored(parent, angles: dynamic ? angles : nil)
    let authoredFrames = [1: parentAuthor, 2: parentAuthor * authored(child)]
    var maxError: Float = 0
    for id in [1, 2] {
        for point in [SIMD4<Float>(0,0,0,1), SIMD4(4,7,11,1), SIMD4(-3,5,-2,1)] {
            var local = point
            var expected = authoredFrames[id]! * point
            if let height = orthoHeight {
                local.y = -local.y
                expected.y = height - expected.y
            }
            maxError = max(maxError, simd_distance(frames[id]! * local, expected))
        }
    }
    return Double(maxError)
}

@main
enum Harness {
    static func main() throws {
        let result: [String: Any] = [
            "reflectedStatic": reflectedHierarchyResult(dynamic: false, orthoHeight: 1000),
            "reflectedDynamic": reflectedHierarchyResult(dynamic: true, orthoHeight: 1000),
            "unreflectedDynamic": reflectedHierarchyResult(dynamic: true, orthoHeight: nil),
            "plain": result(attachment: nil),
            "attached": result(attachment: attachmentFrame(x: 30, y: 40)),
            "scaledParent": result(
                parentScale: [2, 2, 1],
                attachment: attachmentFrame(x: 30, y: 40)
            ),
            "invalidFrame": result(attachment: [1, 2, 3]),
            "dynamic": dynamicResult(),
            "fixedBirthCanvas": fixedDynamicBirthResult(orthoHeight: 1000),
            "fixedBirthNative": fixedDynamicBirthResult(orthoHeight: nil),
            "dynamicAttachment": dynamicAttachmentResult(),
            "projectionColumnMajor": projectionColumnMajorResult(),
            "projectionRejectsNonFinite": rejectsNonFiniteProjection(),
            "nativePerspective": nativePerspectiveResult(),
            "inRangeOrigin": overRangeOriginResult(30),
            "outOfRangeOrigin": overRangeOriginResult(4.67278316e38),
            "mixedRange": mixedRangeTransformResult(),
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

    def test_mixed_axis_hierarchy_preserves_points_under_y_basis_conversion(self) -> None:
        self.assertLess(self.result["reflectedStatic"], 0.0002)
        self.assertLess(self.result["reflectedDynamic"], 0.0002)

    def test_native_3d_dynamic_hierarchy_does_not_reflect_axes(self) -> None:
        self.assertLess(self.result["unreflectedDynamic"], 0.0002)

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

    def test_fixed_dynamic_birth_consumes_each_typed_transform_snapshot(self) -> None:
        for key, sign, height in (("fixedBirthCanvas", -1, 1000), ("fixedBirthNative", 1, 0)):
            with self.subTest(projection=key):
                row = self.result[key]
                y = lambda value: height - value if height else value
                self.assertEqual(row["birth"]["10"][12:15], [10, y(20), 3])
                self.assertEqual(row["first"]["10"], [
                    2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 30, y(40), 5, 1,
                ])
                expected = [0, sign * 4, 0, 0, -sign * 2, 0, 0, 0,
                            0, 0, 1, 0, 60, y(70), 9, 1]
                for actual, value in zip(row["second"]["10"], expected, strict=True):
                    self.assertAlmostEqual(actual, value, places=5)
                self.assertEqual(row["repeatedFirst"], row["first"])
                for layer_id in ("1", "2"):
                    self.assertEqual(row["first"][layer_id], row["birth"][layer_id])
                    self.assertEqual(row["second"][layer_id], row["birth"][layer_id])

    def test_dynamic_root_updates_preserve_authored_hierarchy_and_live_attachments(self) -> None:
        for key, child_translation, attached_translation in (
            ("fixedBirthCanvas", [140, 870, 0], [220, 1030, 0]),
            ("fixedBirthNative", [-20, 130, 0], [220, 210, 0]),
        ):
            with self.subTest(projection=key):
                row = self.result[key]
                self.assertEqual(row["mixed"]["10"], row["second"]["10"])
                self.assertEqual(row["attached"]["10"], row["first"]["10"])
                for actual, expected in zip(row["mixed"]["2"][12:15], child_translation, strict=True):
                    self.assertAlmostEqual(actual, expected, places=4)
                self.assertEqual(row["attached"]["2"][12:15], attached_translation)

    def test_scenescript_projection_preserves_column_major_mat4_abi(self) -> None:
        matrix = self.result["projectionColumnMajor"]
        self.assertEqual(len(matrix), 16)
        self.assertEqual(matrix[0:2], [1, 0])
        self.assertEqual(matrix[12:14], [110, 930])

    def test_over_range_dynamic_transform_falls_back_to_authored(self) -> None:
        # A finite Double the Float conversion cannot hold would otherwise turn
        # this layer's world matrix into NaN and fail the shared snapshot for
        # every consumer; the layer keeps its authored transform instead.
        # In range the override is applied (y maps through orthoHeight); out of
        # Float range the same layer keeps its authored transform.
        self.assertEqual(self.result["inRangeOrigin"], {"translation": [30, 1000]})
        self.assertEqual(
            self.result["outOfRangeOrigin"], {"translation": [10, 980]}
        )

    def test_out_of_range_field_falls_back_alone_next_to_in_range_field(self) -> None:
        # The unsafe unit is the field: the out-of-range origin keeps the
        # authored value while the in-range scale next to it still applies.
        mixed = self.result["mixedRange"]
        self.assertEqual(mixed["translation"], [10, 980])
        self.assertEqual(mixed["scale"], [2, 2])

    def test_scenescript_projection_rejects_nonfinite_world_frames(self) -> None:
        self.assertTrue(self.result["projectionRejectsNonFinite"])


if __name__ == "__main__":
    unittest.main()
