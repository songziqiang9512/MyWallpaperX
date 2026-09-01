#!/usr/bin/env python3

"""Frame visibility consumes committed Boolean values and parent propagation."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneLayerVisibility.swift",
]

HARNESS = r'''
import Foundation

struct SceneLayerDisplayScriptOwnership {
    let visible: Bool
    let alpha: Bool
    var isEmpty: Bool { !visible && !alpha }
    var fields: [String] { [] }
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let visible: Bool?
        let parentID: Int?
        let displayScriptOwnership: SceneLayerDisplayScriptOwnership?
    }
    let layers: [Layer]
}

private let root = SceneDynamicTarget.layer(layerID: 1, field: .visibility)
private let child = SceneDynamicTarget.layer(layerID: 2, field: .visibility)
private let owned = SceneDynamicTarget.layer(layerID: 4, field: .visibility)
private let alphaOwned = SceneDynamicTarget.layer(layerID: 6, field: .visibility)
private let sideEffect = SceneDynamicTarget.layer(layerID: 3, field: .visibility)
private let authoredHidden = SceneDynamicTarget.layer(layerID: 5, field: .visibility)
private let definitions = [
    SceneDynamicTargetDefinition(target: root, valueType: .bool, authoredValue: .bool(false)),
    SceneDynamicTargetDefinition(target: child, valueType: .bool, authoredValue: .bool(true)),
    SceneDynamicTargetDefinition(target: owned, valueType: .bool, authoredValue: .bool(true)),
    SceneDynamicTargetDefinition(
        target: alphaOwned, valueType: .bool, authoredValue: .bool(true)
    ),
    SceneDynamicTargetDefinition(
        target: sideEffect, valueType: .bool, authoredValue: .bool(true)
    ),
    SceneDynamicTargetDefinition(
        target: authoredHidden, valueType: .bool, authoredValue: .bool(false)
    ),
]
private let descriptor = SceneRenderDescriptor(layers: [
    .init(
        id: 1,
        visible: false,
        parentID: nil,
        displayScriptOwnership: .init(visible: true, alpha: false)
    ),
    .init(
        id: 2,
        visible: true,
        parentID: 1,
        displayScriptOwnership: .init(visible: true, alpha: false)
    ),
    .init(id: 3, visible: true, parentID: nil, displayScriptOwnership: nil),
    .init(
        id: 4,
        visible: true,
        parentID: nil,
        displayScriptOwnership: .init(visible: true, alpha: false)
    ),
    .init(id: 5, visible: false, parentID: nil, displayScriptOwnership: nil),
    .init(
        id: 6,
        visible: true,
        parentID: nil,
        displayScriptOwnership: .init(visible: true, alpha: true)
    ),
])

private func visible(
    _ values: [SceneDynamicTarget: SceneDynamicValue],
    userValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
) -> [Int] {
    let snapshot = SceneDynamicSnapshotResolver().resolve(
        frameIndex: 1,
        generation: 1,
        definitions: definitions,
        userValues: userValues,
        sceneScriptValues: values
    ).snapshot
    return SceneLayerVisibility.visibleLayerIDs(
        in: descriptor,
        snapshot: snapshot
    ).sorted()
}

private func sourceAuthority(
    layerID: Int,
    _ values: [SceneDynamicTarget: SceneDynamicValue],
    userValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
) -> Bool {
    let snapshot = SceneDynamicSnapshotResolver().resolve(
        frameIndex: 1,
        generation: 1,
        definitions: definitions,
        userValues: userValues,
        sceneScriptValues: values
    ).snapshot
    let layer = descriptor.layers.first { $0.id == layerID }!
    return SceneLayerVisibility.hasCurrentSourceDisplayAuthority(
        for: layer,
        snapshot: snapshot
    )
}

@main
enum Harness {
    static func main() throws {
        let payload: [String: Any] = [
            "rootRestored": visible([root: .bool(true), child: .bool(true)]),
            "rootHidden": visible([root: .bool(false), child: .bool(true)]),
            "childHidden": visible([root: .bool(true), child: .bool(false)]),
            "ownedStillSuppressed": visible([root: .bool(true), child: .bool(true)]),
            "userSourceStillSuppressed": visible(
                [root: .bool(true), child: .bool(true)],
                userValues: [owned: .bool(true)]
            ),
            "scriptTrueHasSourceAuthority": sourceAuthority(
                layerID: 1,
                [root: .bool(true)]
            ),
            "scriptFalseHasSourceAuthority": sourceAuthority(
                layerID: 1,
                [root: .bool(false)]
            ),
            "missingScriptHasSourceAuthority": sourceAuthority(
                layerID: 4,
                [:]
            ),
            "userSourceHasSourceAuthority": sourceAuthority(
                layerID: 4,
                [:],
                userValues: [owned: .bool(true)]
            ),
            "unownedHasSourceAuthority": sourceAuthority(
                layerID: 3,
                [:]
            ),
            "authoredHiddenHasSourceAuthority": sourceAuthority(
                layerID: 5,
                [:]
            ),
            "alphaOwnerHasSourceAuthority": sourceAuthority(
                layerID: 6,
                [alphaOwned: .bool(true)]
            ),
            "sideEffectHidden": visible([sideEffect: .bool(false)]),
            "sideEffectShown": visible([sideEffect: .bool(true)]),
            "userPropertyHidesUnowned": visible(
                [:],
                userValues: [sideEffect: .bool(false)]
            ),
            "userPropertyRestoresAuthoredHidden": visible(
                [:],
                userValues: [authoredHidden: .bool(true)]
            ),
            "sideEffectHasSourceAuthority": sourceAuthority(
                layerID: 3,
                [sideEffect: .bool(true)]
            ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDynamicLayerVisibilityTests(unittest.TestCase):
    def test_dynamic_visibility_and_parent_propagation(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-layer-visible-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            binary = directory / "layer-visible"
            harness.write_text(HARNESS, encoding="utf-8")
            result = subprocess.run(
                ["swiftc", *map(str, SOURCES), str(harness), "-o", str(binary)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            run = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
            value = json.loads(run.stdout)

        self.assertEqual(value["rootRestored"], [1, 2, 3, 4])
        self.assertEqual(value["rootHidden"], [3, 4])
        self.assertEqual(value["childHidden"], [1, 3, 4])
        self.assertEqual(value["ownedStillSuppressed"], [1, 2, 3, 4])
        self.assertEqual(value["userSourceStillSuppressed"], [1, 2, 3, 4])
        self.assertTrue(value["scriptTrueHasSourceAuthority"])
        self.assertFalse(value["scriptFalseHasSourceAuthority"])
        self.assertTrue(value["missingScriptHasSourceAuthority"])
        self.assertTrue(value["userSourceHasSourceAuthority"])
        self.assertTrue(value["unownedHasSourceAuthority"])
        self.assertFalse(value["authoredHiddenHasSourceAuthority"])
        self.assertFalse(value["alphaOwnerHasSourceAuthority"])
        self.assertEqual(value["sideEffectHidden"], [4])
        self.assertEqual(value["sideEffectShown"], [3, 4])
        self.assertEqual(value["userPropertyHidesUnowned"], [4])
        self.assertEqual(value["userPropertyRestoresAuthoredHidden"], [3, 4, 5])
        self.assertTrue(value["sideEffectHasSourceAuthority"])


if __name__ == "__main__":
    unittest.main()
