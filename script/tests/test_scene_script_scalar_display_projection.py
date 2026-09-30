#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarDisplayProjection.swift"
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

FALLBACK_HARNESS = r'''
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
enum FallbackHarness {
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
        let claimedTargets: Set<SceneDynamicTarget> = [
            // The alpha publication union (shared ∪ scalar-projected ∪
            // timeline) claims layer 20's alpha target; layer 10 only carries
            // a visible-shaped claim, which never blocks an alpha release.
            .layer(layerID: 20, field: .alpha),
            .layer(layerID: 20, field: .visible),
            .layer(layerID: 10, field: .visible),
            .unrelated(7),
        ]
        let projected = SceneScriptScalarDisplayProjection.applyUnclaimedFallback(
            claimedTargets: claimedTargets,
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
                shell=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run(
                ["/usr/bin/env", str(binary)],
                shell=False,
                check=True,
                capture_output=True,
                text=True,
            )
            payload = json.loads(result.stdout)

        self.assertEqual(payload[0], {"id": 10, "visible": True, "alpha": False})
        self.assertEqual(payload[1], {"id": 20, "visible": True, "alpha": True})
        self.assertEqual(payload[2], {"id": 30, "visible": False, "alpha": False})
        self.assertEqual(payload[3], {"id": 40, "visible": None, "alpha": None})
        self.assertEqual(payload[4], {"id": 50, "visible": False, "alpha": False})

    def test_unclaimed_alpha_ownership_falls_back_to_authored_display(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scalar-display-fallback-") as raw:
            directory = Path(raw)
            harness = directory / "FallbackHarness.swift"
            binary = directory / "scalar-display-fallback"
            harness.write_text(FALLBACK_HARNESS, encoding="utf-8")
            compile_result = subprocess.run(
                ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
                shell=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run(
                ["/usr/bin/env", str(binary)],
                shell=False,
                check=True,
                capture_output=True,
                text=True,
            )
            payload = json.loads(result.stdout)

        self.assertEqual(payload[0], {"id": 10, "visible": True, "alpha": False})
        # 压制解除：`.layer(10, .alpha)` 不在 claimed（shared ∪ scalar ∪
        # timeline 的 alpha publication 集合）里，所有权释放为 false，authored
        # 显示态生效；仅 visible 形的认领不阻止 alpha 释放。
        self.assertEqual(payload[1], {"id": 20, "visible": True, "alpha": True})
        # claimed alpha target 不动：admit 优先，同一 target 不产生第二 owner。
        self.assertEqual(payload[2], {"id": 30, "visible": False, "alpha": False})
        # alpha 释放但 visible 所有权原样保留：visible 权语义未被 fallback 触碰。
        self.assertEqual(payload[3], {"id": 40, "visible": None, "alpha": None})
        self.assertEqual(payload[4], {"id": 50, "visible": False, "alpha": False})
        # 无 alpha 所有权与 visible-owned 层零触碰（反例守卫）。


if __name__ == "__main__":
    unittest.main()
