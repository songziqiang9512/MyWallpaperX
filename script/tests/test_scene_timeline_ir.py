#!/usr/bin/env python3
"""Timeline IR 无损解析门。

正向 fixture 是从 45 样本隔离缓存中逐字提取的作者 `scene.json` 片段：

  * `single_start_paused` —— `2067939514` 的 effect `multiply`（fps=15/length=15，
    `startpaused: true`，`wraploop: null`）
  * `loop_relative_vector` —— `2134765860` 的 layer `angles`（fps=4/length=2，
    三 lane，`relative: true`，c2 末值 2π）
  * `single_preview_value` —— `2902406982` 的 effect `multiply`（fps=120/length=60，
    带 `previewvalue`）

`mirror_wrap_loop` 与 `tangent_disabled` 是在同一真实结构上改单个字段得到的派生
fixture，用来覆盖随包样本中存在但未逐字 dump 的 `mode: mirror`、`wraploop: true`
和 `enabled: false` 三种取值。
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTimelineAnimation.swift"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        var output: [String: Any] = [:]
        let cases = try JSONSerialization.jsonObject(
            with: Data(FileHandle.standardInput.readDataToEndOfFile())
        ) as! [String: [String: Any]]
        for (name, host) in cases {
            let result = SceneTimelineAnimationParser.parse(host: host)
            var entry: [String: Any] = [
                "diagnostics": result.diagnostics.map { diagnostic in
                    [
                        "code": diagnostic.code.rawValue,
                        "lane": diagnostic.laneIndex.map(String.init) ?? "-",
                    ]
                },
            ]
            if let animation = result.animation {
                entry["animation"] = encode(animation)
            }
            output[name] = entry
        }
        let data = try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func encode(_ animation: SceneTimelineAnimation) -> [String: Any] {
        [
            "componentCount": animation.componentCount,
            "isRelative": animation.isRelative,
            "previewValue": animation.previewValue.map { "\($0)" } ?? "-",
            "options": [
                "fps": animation.options.fps,
                "length": animation.options.length,
                "mode": animation.options.mode.rawValue,
                "startsPaused": animation.options.startsPaused,
                "wrapsLoop": animation.options.wrapsLoop,
                "durationSeconds": animation.options.durationSeconds,
            ],
            "lanes": animation.lanes.map { lane in
                lane.map { keyframe in
                    [
                        "frame": keyframe.frame,
                        "value": keyframe.value,
                        "front": encode(keyframe.front),
                        "back": encode(keyframe.back),
                        "locksAngle": keyframe.locksAngle.map { $0 ? "true" : "false" } ?? "-",
                        "locksLength": keyframe.locksLength.map { $0 ? "true" : "false" } ?? "-",
                    ]
                }
            },
        ]
    }

    static func encode(_ tangent: SceneTimelineTangent?) -> Any {
        guard let tangent else { return "-" }
        return ["enabled": tangent.isEnabled, "x": tangent.x, "y": tangent.y]
    }
}
'''


def keyframe(frame, value, front=True, back=True):
    return {
        "back": {"enabled": back, "x": -1, "y": 0},
        "frame": frame,
        "front": {"enabled": front, "x": 1, "y": 0},
        "lockangle": True,
        "locklength": True,
        "value": value,
    }


CASES = {
    # --- 逐字提取的真实作者数据 ---
    "single_start_paused": {
        "value": 0,
        "animation": {
            "c0": [keyframe(0, 1), keyframe(15, 0)],
            "options": {
                "fps": 15,
                "length": 15,
                "mode": "single",
                "startpaused": True,
                "wraploop": None,
            },
        },
    },
    "loop_relative_vector": {
        "value": "0.00000 0.00000 0.00000",
        "animation": {
            "c0": [keyframe(0, 0), keyframe(2, 0)],
            "c1": [keyframe(0, 0), keyframe(2, 0)],
            "c2": [keyframe(0, 0), keyframe(2, 6.2831855)],
            "options": {"fps": 4, "length": 2, "mode": "loop"},
            "relative": True,
        },
    },
    "single_preview_value": {
        "value": 1,
        "animation": {
            "c0": [keyframe(0, 0), keyframe(60, 1)],
            "options": {
                "fps": 120,
                "length": 60,
                "mode": "single",
                "wraploop": None,
            },
            "previewvalue": 1,
        },
    },
    # --- 同结构派生 fixture ---
    "mirror_wrap_loop": {
        "value": 1,
        "animation": {
            "c0": [keyframe(0, 0), keyframe(30, 1)],
            "options": {
                "fps": 30,
                "length": 30,
                "mode": "mirror",
                "wraploop": True,
            },
        },
    },
    "tangent_disabled": {
        "value": 1,
        "animation": {
            "c0": [keyframe(0, 0, front=False, back=False), keyframe(30, 1)],
            "options": {"fps": 1.2, "length": 144, "mode": "loop"},
        },
    },
    # --- 负例 ---
    "no_animation": {"value": 1},
    "missing_options": {"value": 1, "animation": {"c0": [keyframe(0, 0)]}},
    "unknown_mode": {
        "value": 1,
        "animation": {
            "c0": [keyframe(0, 0)],
            "options": {"fps": 30, "length": 30, "mode": "pingpong"},
        },
    },
    "zero_fps": {
        "value": 1,
        "animation": {
            "c0": [keyframe(0, 0)],
            "options": {"fps": 0, "length": 30, "mode": "loop"},
        },
    },
    "unordered_frames": {
        "value": 1,
        "animation": {
            "c0": [keyframe(30, 0), keyframe(0, 1)],
            "options": {"fps": 30, "length": 30, "mode": "loop"},
        },
    },
    "lane_gap": {
        "value": 1,
        "animation": {
            "c0": [keyframe(0, 0)],
            "c2": [keyframe(0, 0)],
            "options": {"fps": 30, "length": 30, "mode": "loop"},
        },
    },
    "empty_lane": {
        "value": 1,
        "animation": {
            "c0": [],
            "options": {"fps": 30, "length": 30, "mode": "loop"},
        },
    },
    "missing_lanes": {
        "value": 1,
        "animation": {"options": {"fps": 30, "length": 30, "mode": "loop"}},
    },
}


class SceneTimelineIRTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-timeline-ir-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-timeline-ir"
        compilation = subprocess.run(
            ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            input=json.dumps(CASES),
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def animation(self, name):
        entry = self.result[name]
        self.assertIn("animation", entry, f"{name} 应当解析成功: {entry}")
        return entry["animation"]

    def diagnostic_codes(self, name):
        return [d["code"] for d in self.result[name]["diagnostics"]]

    def test_authored_single_keeps_start_paused_and_frame_timebase(self) -> None:
        animation = self.animation("single_start_paused")
        options = animation["options"]
        self.assertEqual(options["mode"], "single")
        self.assertTrue(options["startsPaused"])
        # wraploop: null 必须落成 false，而不是被当作 true
        self.assertFalse(options["wrapsLoop"])
        self.assertEqual(options["fps"], 15)
        self.assertEqual(options["length"], 15)
        # 时长来自 length / fps，不是把 length 当秒
        self.assertAlmostEqual(options["durationSeconds"], 1.0)
        self.assertEqual(animation["componentCount"], 1)
        self.assertEqual(
            [k["value"] for k in animation["lanes"][0]], [1, 0]
        )
        self.assertEqual([k["frame"] for k in animation["lanes"][0]], [0, 15])

    def test_authored_vector_lane_keeps_order_and_relative_flag(self) -> None:
        animation = self.animation("loop_relative_vector")
        self.assertEqual(animation["componentCount"], 3)
        self.assertTrue(animation["isRelative"])
        self.assertEqual(animation["options"]["mode"], "loop")
        self.assertAlmostEqual(animation["options"]["durationSeconds"], 0.5)
        # lane 顺序即 component 下标：只有 c2 是非零旋转
        self.assertEqual([k["value"] for k in animation["lanes"][0]], [0, 0])
        self.assertEqual([k["value"] for k in animation["lanes"][1]], [0, 0])
        self.assertAlmostEqual(animation["lanes"][2][1]["value"], 6.2831855)

    def test_preview_value_is_retained_separately_from_authored_value(self) -> None:
        animation = self.animation("single_preview_value")
        self.assertEqual(animation["previewValue"], "1.0")
        self.assertAlmostEqual(animation["options"]["durationSeconds"], 0.5)

    def test_mirror_and_wrap_loop_round_trip(self) -> None:
        options = self.animation("mirror_wrap_loop")["options"]
        self.assertEqual(options["mode"], "mirror")
        self.assertTrue(options["wrapsLoop"])

    def test_disabled_tangent_and_fractional_fps_survive(self) -> None:
        animation = self.animation("tangent_disabled")
        first = animation["lanes"][0][0]
        self.assertFalse(first["front"]["enabled"])
        self.assertFalse(first["back"]["enabled"])
        # 第二个关键帧仍是 enabled，两侧独立保存
        self.assertTrue(animation["lanes"][0][1]["front"]["enabled"])
        self.assertEqual(animation["options"]["fps"], 1.2)
        self.assertAlmostEqual(animation["options"]["durationSeconds"], 120.0)

    def test_editor_only_handle_locks_round_trip(self) -> None:
        first = self.animation("single_start_paused")["lanes"][0][0]
        self.assertEqual(first["locksAngle"], "true")
        self.assertEqual(first["locksLength"], "true")
        self.assertEqual(first["front"]["x"], 1)
        self.assertEqual(first["back"]["x"], -1)

    def test_absent_animation_is_not_a_diagnostic(self) -> None:
        self.assertNotIn("animation", self.result["no_animation"])
        self.assertEqual(self.diagnostic_codes("no_animation"), [])

    def test_malformed_animations_fail_closed_with_diagnostics(self) -> None:
        expected = {
            "missing_options": "missingOptions",
            "unknown_mode": "unknownMode",
            "zero_fps": "invalidFPS",
            "unordered_frames": "unorderedFrames",
            "lane_gap": "laneGap",
            "empty_lane": "emptyLane",
            "missing_lanes": "missingLanes",
        }
        for name, code in expected.items():
            with self.subTest(case=name):
                self.assertNotIn("animation", self.result[name])
                self.assertIn(code, self.diagnostic_codes(name))


if __name__ == "__main__":
    unittest.main()
