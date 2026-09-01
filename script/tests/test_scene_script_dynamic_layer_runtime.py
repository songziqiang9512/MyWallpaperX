#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptDynamicLayerRuntime.swift"
)

HARNESS = r'''
import Foundation

nonisolated enum SceneScriptScalarRuntimeFailure: Error, Equatable, Sendable {
    case mutationOverflow(String)
    case invalidArgument(String)
    case staleOwner
}

nonisolated struct SceneScriptLayerMutation: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case upsert, destroy }
    struct Fields: OptionSet, Equatable, Sendable {
        let rawValue: UInt32
        static let origin = Self(rawValue: 1 << 0)
        static let scale = Self(rawValue: 1 << 1)
        static let angles = Self(rawValue: 1 << 2)
        static let visibility = Self(rawValue: 1 << 3)
        static let text = Self(rawValue: 1 << 4)
        static let authoredFields: Self = [
            .origin, .scale, .angles, .visibility, .text,
        ]
    }
    let kind: Kind
    let isDynamic: Bool
    let fields: Fields
    let layerID: Int
    let orderIndex: Int
    let visible: Bool
    let alpha: Double
    let origin: SIMD3<Double>
    let scale: SIMD3<Double>
    let angles: SIMD3<Double>
    let color: SIMD3<Double>
    let pointSize: Double
    let text: String
    let font: String
    let assetPath: String?
    let ownerTarget: SceneDynamicTarget?
}

nonisolated enum SceneDynamicValueType: Sendable { case bool, string, vector3 }
nonisolated enum SceneDynamicValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case vector3(Double, Double, Double)
}
nonisolated enum SceneDynamicSource: Sendable { case sceneScript }
nonisolated struct SceneDynamicResolvedValue: Sendable {
    let value: SceneDynamicValue
    let source: SceneDynamicSource
}
nonisolated struct SceneDynamicSnapshot: Sendable {
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? {
        values[target]
    }
}
nonisolated enum SceneDynamicLayerField: Hashable, Sendable {
    case visibility, origin, scale, angles, color
}
nonisolated enum SceneDynamicTextField: Hashable, Sendable { case content }
nonisolated enum SceneDynamicTarget: Hashable, Sendable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
    case text(layerID: Int, field: SceneDynamicTextField)
}
nonisolated struct SceneScriptOwnerEffects: Sendable {
    let ownerTarget: SceneDynamicTarget
    let layerMutations: [SceneScriptLayerMutation]
}
nonisolated struct SceneDynamicTargetDefinition: Sendable {
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType
    let authoredValue: SceneDynamicValue
}

nonisolated struct SceneRenderDescriptor: Sendable {
    struct Layer: Sendable {
        struct TextStyle: Sendable { let fontPath: String? }
        let id: Int
        let visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        let contentKind: String
        let text: String?
        let textStyle: TextStyle?
        let imagePath: String?
        var colorRGB: [Float]?

        static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
            guard mutation.isDynamic, mutation.kind == .upsert else { return nil }
            return .init(
                id: mutation.layerID,
                visible: mutation.visible,
                originXYZ: nil, scaleXYZ: nil, anglesXYZ: nil,
                contentKind: "text", text: mutation.text,
                textStyle: .init(fontPath: mutation.font)
            )
        }

        static func dynamicImage(
            _ mutation: SceneScriptLayerMutation,
            template: SceneScriptDynamicImageLayerTemplate
        ) -> Self? {
            guard mutation.isDynamic, mutation.kind == .upsert,
                  mutation.assetPath == template.modelPath else { return nil }
            return .init(
                id: mutation.layerID,
                visible: mutation.visible,
                originXYZ: nil,
                scaleXYZ: nil,
                anglesXYZ: nil,
                contentKind: "image",
                text: nil,
                textStyle: nil,
                imagePath: template.modelPath,
                colorRGB: [
                    Float(mutation.color.x),
                    Float(mutation.color.y),
                    Float(mutation.color.z),
                ]
            )
        }

        init(
            id: Int,
            visible: Bool?,
            originXYZ: [Float]?,
            scaleXYZ: [Float]?,
            anglesXYZ: [Float]?,
            contentKind: String = "image",
            text: String? = nil,
            textStyle: TextStyle? = nil,
            imagePath: String? = nil,
            colorRGB: [Float]? = nil
        ) {
            self.id = id
            self.visible = visible
            self.originXYZ = originXYZ
            self.scaleXYZ = scaleXYZ
            self.anglesXYZ = anglesXYZ
            self.contentKind = contentKind
            self.text = text
            self.textStyle = textStyle
            self.imagePath = imagePath
            self.colorRGB = colorRGB
        }
    }

    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
}

func mutation(
    _ id: Int,
    dynamic: Bool = true,
    kind: SceneScriptLayerMutation.Kind = .upsert,
    order: Int = 0,
    alpha: Double = 1,
    text: String = "text",
    fields: SceneScriptLayerMutation.Fields = [],
    scale: SIMD3<Double> = .init(repeating: 1),
    angles: SIMD3<Double> = .zero,
    visible: Bool = true,
    assetPath: String? = nil,
    ownerTarget: SceneDynamicTarget? = nil
) -> SceneScriptLayerMutation {
    .init(
        kind: kind, isDynamic: dynamic, fields: fields,
        layerID: id, orderIndex: order,
        visible: visible, alpha: alpha, origin: .zero,
        scale: scale, angles: angles,
        color: .init(repeating: 1), pointSize: 32, text: text, font: "",
        assetPath: assetPath, ownerTarget: ownerTarget
    )
}

func succeeded(
    _ result: Result<Void, SceneScriptScalarRuntimeFailure>
) -> Bool {
    if case .success = result { return true }
    return false
}

@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(
            layers: [
                .init(id: 10, visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], anglesXYZ: [0, 0, 0]),
                .init(
                    id: 20, visible: true, originXYZ: [0, 0, 0],
                    scaleXYZ: [1, 1, 1], anglesXYZ: [0, 0, 0],
                    contentKind: "text", text: "authored",
                    textStyle: .init(fontPath: nil)
                ),
            ],
            renderOrderLayerIDs: [10, 20]
        )
        let runtime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let beforeCreate = runtime.snapshot()
        let create = runtime.apply([mutation(-1, order: 1)])
        let afterCreate = runtime.snapshot()
        let move = runtime.apply([mutation(-1, order: 2, text: "updated")])
        let afterMove = runtime.snapshot()
        let staticUpdate = runtime.apply([
            mutation(
                10, dynamic: false,
                fields: [.angles, .visibility],
                angles: .init(7, 8, 9), visible: false
            )
        ])
        let afterStatic = runtime.snapshot()
        let peerUpdate = runtime.apply([
            mutation(
                20, dynamic: false, text: "~",
                fields: [.scale, .text]
            )
        ])
        let afterPeer = runtime.snapshot()
        let rejected = runtime.apply([
            mutation(20, dynamic: false, text: "must-not-publish", fields: [.text]),
            mutation(10, dynamic: false, text: "invalid-image-text", fields: [.text]),
        ])
        let afterRejected = runtime.snapshot()
        let isolatedRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: []
        )
        let ownerA = SceneDynamicTarget.layer(layerID: 10, field: .origin)
        let ownerB = SceneDynamicTarget.layer(layerID: 20, field: .origin)
        let ownerC = SceneDynamicTarget.layer(layerID: 10, field: .angles)
        let ownerEffects = [
            SceneScriptOwnerEffects(ownerTarget: ownerA, layerMutations: [
                mutation(
                    20, dynamic: false, fields: [.scale],
                    scale: .init(2, 3, 4), ownerTarget: ownerA
                ),
            ]),
            SceneScriptOwnerEffects(ownerTarget: ownerB, layerMutations: [
                mutation(
                    10, dynamic: false, text: "invalid-image-text",
                    fields: [.text], ownerTarget: ownerB
                ),
            ]),
            SceneScriptOwnerEffects(ownerTarget: ownerC, layerMutations: [
                mutation(
                    10, dynamic: false, fields: [.angles],
                    angles: .init(5, 6, 7), ownerTarget: ownerC
                ),
            ]),
        ]
        let admission = isolatedRuntime.preflightOwnerEffects(ownerEffects)
        let preflightSnapshot = isolatedRuntime.snapshot()
        let isolated = admission.layerPlan.outcome
        isolatedRuntime.commit(admission.layerPlan)
        let afterIsolated = isolatedRuntime.snapshot()
        let budgetRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let seededFirstHalf = succeeded(budgetRuntime.apply((1...128).map {
            mutation(-$0, order: $0)
        }))
        let seededSecondHalf = succeeded(budgetRuntime.apply((129...256).map {
            mutation(-$0, order: $0)
        }))
        let budgetOwnerA = SceneDynamicTarget.layer(
            layerID: 10, field: .origin
        )
        let budgetOwnerB = SceneDynamicTarget.layer(
            layerID: 20, field: .origin
        )
        let budgetOwnerC = SceneDynamicTarget.layer(
            layerID: 10, field: .angles
        )
        let budgetEffects = [
            SceneScriptOwnerEffects(
                ownerTarget: budgetOwnerA,
                layerMutations: [mutation(
                    -1, kind: .destroy, ownerTarget: budgetOwnerA
                )]
            ),
            SceneScriptOwnerEffects(
                ownerTarget: budgetOwnerB,
                layerMutations: [mutation(
                    -257, order: 1, ownerTarget: budgetOwnerB
                )]
            ),
            SceneScriptOwnerEffects(
                ownerTarget: budgetOwnerC,
                layerMutations: [mutation(
                    10, dynamic: false, fields: [.angles],
                    angles: .init(9, 8, 7), ownerTarget: budgetOwnerC
                )]
            ),
        ]
        let fixedPoint = budgetRuntime.preflightOwnerEffectsToFixedPoint(
            budgetEffects
        ) { admitted in
            admitted.contains { $0.ownerTarget == budgetOwnerA }
                ? [budgetOwnerA] : []
        }
        budgetRuntime.commit(fixedPoint.admission.layerPlan)
        let afterFixedPoint = budgetRuntime.snapshot()
        let destroy = runtime.apply([mutation(-1, kind: .destroy, order: 2)])
        let afterDestroy = runtime.snapshot()
        let colorTarget = SceneDynamicTarget.layer(layerID: 20, field: .color)
        let imageRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [],
            dynamicImageTemplates: [
                "models/bar.json": .init(
                    modelPath: "models/bar.json",
                    renderSizeWH: [4, 4],
                    materialColorTarget: colorTarget
                ),
            ]
        )
        let imageCreate = imageRuntime.apply([
            mutation(-2, order: 1, assetPath: "models/bar.json"),
        ])
        let imageSnapshot = imageRuntime.snapshot()
        let resolvedImage = imageSnapshot.resolvingDynamicMaterialColors(
            from: .init(values: [
                colorTarget: .init(
                    value: .vector3(0.25, 0.5, 0.75),
                    source: .sceneScript
                ),
            ])
        )
        let payload: [String: Any] = [
            "createSucceeded": succeeded(create),
            "priorSnapshotStable": beforeCreate.dynamicLayers.isEmpty,
            "createdIDs": afterCreate.dynamicLayers.map(\.id),
            "createdOrder": afterCreate.renderOrderLayerIDs,
            "moveSucceeded": succeeded(move),
            "movedOrder": afterMove.renderOrderLayerIDs,
            "staticAccepted": succeeded(staticUpdate),
            "staticAnglesPublished": afterStatic.authoredLayerValues[
                .layer(layerID: 10, field: .angles)
            ] == .vector3(7, 8, 9),
            "staticVisibilityPublished": afterStatic.authoredLayerValues[
                .layer(layerID: 10, field: .visibility)
            ] == .bool(false),
            "peerUpdateAccepted": succeeded(peerUpdate),
            "peerScalePublished": afterPeer.authoredLayerValues[
                .layer(layerID: 20, field: .scale)
            ] == .vector3(1, 1, 1),
            "peerTextPublished": afterPeer.authoredLayerValues[
                .text(layerID: 20, field: .content)
            ] == .string("~"),
            "authoredDefinitionCount": runtime.authoredLayerDefinitions.count,
            "rejected": !succeeded(rejected),
            "failedBatchTextRolledBack": afterRejected.authoredLayerValues[
                .text(layerID: 20, field: .content)
            ] == .string("~"),
            "rollbackLayers": afterRejected.dynamicLayers.map(\.id),
            "rollbackOrder": afterRejected.renderOrderLayerIDs,
            "isolatedCommittedMutationCount": isolated.committedMutationCount,
            "isolatedFailureCount": admission.rejectedOwners.count,
            "isolatedFailureOwnerIsB": admission.rejectedOwners.first?
                .ownerTarget == ownerB,
            "isolatedAdmittedOwnerCount": admission.admittedEffects.count,
            "isolatedPreflightWasReadOnly": preflightSnapshot.authoredLayerValues.isEmpty,
            "isolatedPeerScalePublished": afterIsolated.authoredLayerValues[
                .layer(layerID: 20, field: .scale)
            ] == .vector3(2, 3, 4),
            "isolatedDisjointAnglesPublished": afterIsolated.authoredLayerValues[
                .layer(layerID: 10, field: .angles)
            ] == .vector3(5, 6, 7),
            "isolatedBadTextAbsent": afterIsolated.authoredLayerValues[
                .text(layerID: 10, field: .content)
            ] == nil,
            "fixedPointSeeded": seededFirstHalf && seededSecondHalf,
            "fixedPointExternalRejectsA":
                fixedPoint.externallyRejectedOwners == [budgetOwnerA],
            "fixedPointLayerRejectsB":
                fixedPoint.admission.rejectedOwners.contains {
                    $0.ownerTarget == budgetOwnerB
                },
            "fixedPointAdmitsOnlyC":
                fixedPoint.admission.admittedEffects.map(\.ownerTarget)
                    == [budgetOwnerC],
            "fixedPointPreservesFullTopology":
                afterFixedPoint.dynamicLayers.count == 256
                    && !afterFixedPoint.dynamicLayers.contains {
                        $0.id == -257
                    },
            "fixedPointCommitsDisjointC": afterFixedPoint.authoredLayerValues[
                .layer(layerID: 10, field: .angles)
            ] == .vector3(9, 8, 7),
            "destroySucceeded": succeeded(destroy),
            "destroyedIDs": afterDestroy.dynamicLayers.map(\.id),
            "destroyedOrder": afterDestroy.renderOrderLayerIDs,
            "dynamicImageSucceeded": succeeded(imageCreate),
            "dynamicImageColorTarget":
                imageSnapshot.dynamicMaterialColorTargetsByLayerID[-2]
                    == colorTarget,
            "dynamicImageColor": resolvedImage.dynamicLayers.first?
                .colorRGB?.map(Double.init) ?? [],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneScriptDynamicLayerRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-script-dynamic-layer-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "dynamic-layer-runtime"
        compilation = subprocess.run(
            ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
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

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_create_and_sort_publish_only_through_snapshots(self) -> None:
        self.assertTrue(self.result["createSucceeded"])
        self.assertTrue(self.result["priorSnapshotStable"])
        self.assertEqual(self.result["createdIDs"], [-1])
        self.assertEqual(self.result["createdOrder"], [10, -1, 20])
        self.assertTrue(self.result["moveSucceeded"])
        self.assertEqual(self.result["movedOrder"], [10, 20, -1])

    def test_static_transform_mutation_and_failed_batch_are_atomic(self) -> None:
        self.assertTrue(self.result["staticAccepted"])
        self.assertTrue(self.result["staticAnglesPublished"])
        self.assertTrue(self.result["staticVisibilityPublished"])
        self.assertTrue(self.result["peerUpdateAccepted"])
        self.assertTrue(self.result["peerScalePublished"])
        self.assertTrue(self.result["peerTextPublished"])
        self.assertEqual(self.result["authoredDefinitionCount"], 6)
        self.assertTrue(self.result["rejected"])
        self.assertTrue(self.result["failedBatchTextRolledBack"])
        self.assertEqual(self.result["rollbackLayers"], [-1])
        self.assertEqual(self.result["rollbackOrder"], [10, 20, -1])

    def test_destroy_removes_only_the_dynamic_layer(self) -> None:
        self.assertTrue(self.result["destroySucceeded"])
        self.assertEqual(self.result["destroyedIDs"], [])
        self.assertEqual(self.result["destroyedOrder"], [10, 20])

    def test_bad_owner_does_not_reject_disjoint_owner_mutations(self) -> None:
        self.assertEqual(self.result["isolatedCommittedMutationCount"], 2)
        self.assertEqual(self.result["isolatedFailureCount"], 1)
        self.assertTrue(self.result["isolatedFailureOwnerIsB"])
        self.assertEqual(self.result["isolatedAdmittedOwnerCount"], 2)
        self.assertTrue(self.result["isolatedPreflightWasReadOnly"])
        self.assertTrue(self.result["isolatedPeerScalePublished"])
        self.assertTrue(self.result["isolatedDisjointAnglesPublished"])
        self.assertTrue(self.result["isolatedBadTextAbsent"])

    def test_external_rejection_reaches_layer_admission_fixed_point(self) -> None:
        self.assertTrue(self.result["fixedPointSeeded"])
        self.assertTrue(self.result["fixedPointExternalRejectsA"])
        self.assertTrue(self.result["fixedPointLayerRejectsB"])
        self.assertTrue(self.result["fixedPointAdmitsOnlyC"])
        self.assertTrue(self.result["fixedPointPreservesFullTopology"])
        self.assertTrue(self.result["fixedPointCommitsDisjointC"])

    def test_dynamic_image_inherits_typed_material_color(self) -> None:
        self.assertTrue(self.result["dynamicImageSucceeded"])
        self.assertTrue(self.result["dynamicImageColorTarget"])
        self.assertEqual(self.result["dynamicImageColor"], [0.25, 0.5, 0.75])


if __name__ == "__main__":
    unittest.main()
