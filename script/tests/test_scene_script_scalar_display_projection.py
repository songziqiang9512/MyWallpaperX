#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript"
    / "SceneScriptScalarDisplayProjection.swift"
)

HARNESS = r'''
import Foundation

enum SceneDynamicLayerField: Hashable {
    case visible
    case alpha
}

enum SceneDynamicTarget: Hashable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
    case unrelated(Int)
}

struct SceneLayerDisplayScriptOwnership {
    let visible: Bool
    let alpha: Bool
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership?
    }

    var layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(
                id: 10,
                displayScriptOwnership: .init(visible: true, alpha: true)
            ),
            .init(
                id: 20,
                displayScriptOwnership: .init(visible: true, alpha: true)
            ),
            .init(
                id: 30,
                displayScriptOwnership: .init(visible: false, alpha: true)
            ),
            .init(id: 40, displayScriptOwnership: nil),
            .init(
                id: 50,
                displayScriptOwnership: .init(visible: false, alpha: false)
            ),
        ])
        let projected = SceneScriptScalarDisplayProjection.apply(
            admittedTargets: [
                .layer(layerID: 10, field: .alpha),
                .layer(layerID: 20, field: .visible),
                .layer(layerID: 30, field: .alpha),
                .layer(layerID: 40, field: .alpha),
                .layer(layerID: 50, field: .alpha),
                .unrelated(10),
            ],
            to: descriptor
        )
        let payload: [[String: Any]] = projected.layers.map { layer in
            [
                "id": layer.id,
                "visible": layer.displayScriptOwnership?.visible as Any,
                "alpha": layer.displayScriptOwnership?.alpha as Any,
            ]
        }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneScriptScalarDisplayProjectionTests(unittest.TestCase):
    def test_only_admitted_alpha_releases_alpha_suppression(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scalar-display-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            binary = directory / "scalar-display"
            harness.write_text(HARNESS, encoding="utf-8")
            compile_result = subprocess.run(
                ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
            payload = json.loads(result.stdout)

        self.assertEqual(payload[0], {"id": 10, "visible": True, "alpha": False})
        self.assertEqual(payload[1], {"id": 20, "visible": True, "alpha": True})
        self.assertEqual(payload[2], {"id": 30, "visible": False, "alpha": False})
        self.assertEqual(payload[3], {"id": 40, "visible": None, "alpha": None})
        self.assertEqual(payload[4], {"id": 50, "visible": False, "alpha": False})


if __name__ == "__main__":
    unittest.main()
