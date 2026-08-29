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
    let kind: Kind
    let isDynamic: Bool
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
}

nonisolated struct SceneRenderDescriptor: Sendable {
    struct Layer: Sendable {
        let id: Int

        static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
            guard mutation.isDynamic, mutation.kind == .upsert else { return nil }
            return .init(id: mutation.layerID)
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
    text: String = "text"
) -> SceneScriptLayerMutation {
    .init(
        kind: kind, isDynamic: dynamic, layerID: id, orderIndex: order,
        visible: true, alpha: alpha, origin: .zero,
        scale: .init(repeating: 1), angles: .zero,
        color: .init(repeating: 1), pointSize: 32, text: text, font: ""
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
            layers: [.init(id: 10), .init(id: 20)],
            renderOrderLayerIDs: [10, 20]
        )
        let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor)
        let beforeCreate = runtime.snapshot()
        let create = runtime.apply([mutation(-1, order: 1)])
        let afterCreate = runtime.snapshot()
        let move = runtime.apply([mutation(-1, order: 2, text: "updated")])
        let afterMove = runtime.snapshot()
        let staticUpdate = runtime.apply([mutation(10, dynamic: false)])
        let beforeRejected = runtime.snapshot()
        let rejected = runtime.apply([
            mutation(-2, order: 0),
            mutation(-3, order: 0, alpha: 2),
        ])
        let afterRejected = runtime.snapshot()
        let destroy = runtime.apply([mutation(-1, kind: .destroy, order: 2)])
        let afterDestroy = runtime.snapshot()
        let payload: [String: Any] = [
            "createSucceeded": succeeded(create),
            "priorSnapshotStable": beforeCreate.dynamicLayers.isEmpty,
            "createdIDs": afterCreate.dynamicLayers.map(\.id),
            "createdOrder": afterCreate.renderOrderLayerIDs,
            "moveSucceeded": succeeded(move),
            "movedOrder": afterMove.renderOrderLayerIDs,
            "staticRejected": !succeeded(staticUpdate),
            "rejected": !succeeded(rejected),
            "rollbackLayers": afterRejected.dynamicLayers.map(\.id),
            "rollbackOrder": afterRejected.renderOrderLayerIDs,
            "destroySucceeded": succeeded(destroy),
            "destroyedIDs": afterDestroy.dynamicLayers.map(\.id),
            "destroyedOrder": afterDestroy.renderOrderLayerIDs,
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

    def test_static_mutation_and_failed_batch_are_rejected_atomically(self) -> None:
        self.assertTrue(self.result["staticRejected"])
        self.assertTrue(self.result["rejected"])
        self.assertEqual(self.result["rollbackLayers"], [-1])
        self.assertEqual(self.result["rollbackOrder"], [10, 20, -1])

    def test_destroy_removes_only_the_dynamic_layer(self) -> None:
        self.assertTrue(self.result["destroySucceeded"])
        self.assertEqual(self.result["destroyedIDs"], [])
        self.assertEqual(self.result["destroyedOrder"], [10, 20])


if __name__ == "__main__":
    unittest.main()
