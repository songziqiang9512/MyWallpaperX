#!/usr/bin/env python3
"""Timeline 绝对 scene-time 求值门。

时间基与关键帧取自真实作者数据：

  * `single` —— `2067939514` 的 effect `multiply`（fps=15/length=15，值 1→0）
  * `loop_vector` —— `2134765860` 的 layer `angles`（fps=4/length=2，c2 值 0→2π）
  * `start_paused` —— 同 `2067939514`，保留其 `startpaused: true`

`mirror`、`three_keyframes` 与 `offset_lane` 是同结构派生 fixture，分别覆盖反向
播放、多区间定位和关键帧范围不从 0 起的情况。

本门同时锁定默认、单侧关闭、双侧关闭与真实 camera 自定义 handle。X 以当前 segment
span 归一化，Y 使用 property value offset；期望值由测试内独立常量锁定，不复用 Swift
实现。
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format"
IR_SOURCE = SOURCE_ROOT / "SceneTimelineAnimation.swift"
EVALUATOR_SOURCE = SOURCE_ROOT / "SceneTimelineEvaluator.swift"

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let request = try JSONSerialization.jsonObject(
            with: Data(FileHandle.standardInput.readDataToEndOfFile())
        ) as! [String: Any]
        let cases = request["cases"] as! [String: [String: Any]]
        let samples = request["samples"] as! [Double]
        var output: [String: Any] = [:]
        for (name, host) in cases {
            guard let animation = SceneTimelineAnimationParser.parse(host: host).animation else {
                output[name] = ["error": "parse-failed"]
                continue
            }
            output[name] = [
                "frames": samples.map {
                    SceneTimelineEvaluator.framePosition(of: animation, sceneTime: $0)
                },
                "values": samples.map {
                    SceneTimelineEvaluator.values(of: animation, sceneTime: $0)
                },
                "outOfRangeComponent": SceneTimelineEvaluator.value(
                    of: animation, component: animation.componentCount, sceneTime: 0
                ).map { "\($0)" } ?? "-",
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


def keyframe(
    frame,
    value,
    *,
    front_enabled=True,
    back_enabled=True,
    front=(1, 0),
    back=(-1, 0),
):
    return {
        "back": {"enabled": back_enabled, "x": back[0], "y": back[1]},
        "frame": frame,
        "front": {"enabled": front_enabled, "x": front[0], "y": front[1]},
        "lockangle": True,
        "locklength": True,
        "value": value,
    }


TAU = 6.2831855

CASES = {
    "single": {
        "value": 0,
        "animation": {
            "c0": [keyframe(0, 1), keyframe(15, 0)],
            "options": {"fps": 15, "length": 15, "mode": "single"},
        },
    },
    "start_paused": {
        "value": 0,
        "animation": {
            "c0": [keyframe(0, 1), keyframe(15, 0)],
            "options": {
                "fps": 15,
                "length": 15,
                "mode": "single",
                "startpaused": True,
            },
        },
    },
    "loop_vector": {
        "value": "0.00000 0.00000 0.00000",
        "animation": {
            "c0": [keyframe(0, 0), keyframe(2, 0)],
            "c1": [keyframe(0, 0), keyframe(2, 0)],
            "c2": [keyframe(0, 0), keyframe(2, TAU)],
            "options": {"fps": 4, "length": 2, "mode": "loop"},
            "relative": True,
        },
    },
    "mirror": {
        "value": 0,
        "animation": {
            "c0": [keyframe(0, 0), keyframe(10, 1)],
            "options": {"fps": 10, "length": 10, "mode": "mirror"},
        },
    },
    "three_keyframes": {
        "value": 0,
        "animation": {
            "c0": [keyframe(0, 0), keyframe(10, 1), keyframe(30, 0)],
            "options": {"fps": 10, "length": 30, "mode": "single"},
        },
    },
    "offset_lane": {
        "value": 0,
        "animation": {
            "c0": [keyframe(10, 5), keyframe(20, 15)],
            "options": {"fps": 10, "length": 30, "mode": "single"},
        },
    },
    "linear_disabled": {
        "value": 0,
        "animation": {
            "c0": [
                keyframe(0, 0, front_enabled=False, back_enabled=False),
                keyframe(10, 1, front_enabled=False, back_enabled=False),
            ],
            "options": {"fps": 10, "length": 10, "mode": "single"},
        },
    },
    "one_sided_text_width": {
        "value": 730,
        "animation": {
            "c0": [
                keyframe(0, 730, front_enabled=False),
                keyframe(59, 888),
            ],
            "options": {"fps": 59, "length": 59, "mode": "single"},
        },
    },
    "custom_camera": {
        "value": -100,
        "animation": {
            "c0": [
                keyframe(0, -100, front=(0.75, 10)),
                keyframe(120, 0, back=(-0.75, 0)),
            ],
            "options": {"fps": 120, "length": 120, "mode": "single"},
        },
    },
}

# 采样点单位是秒。
SAMPLES = [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]


class SceneTimelineEvaluatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-timeline-eval-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-timeline-eval"
        compilation = subprocess.run(
            [
                "swiftc",
                str(IR_SOURCE),
                str(EVALUATOR_SOURCE),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            input=json.dumps({"cases": CASES, "samples": SAMPLES}),
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def at(self, name, seconds):
        index = SAMPLES.index(seconds)
        entry = self.result[name]
        return entry["frames"][index], entry["values"][index]

    def test_single_advances_then_holds_the_final_value(self) -> None:
        # fps=15 → 0.5s 落在第 7.5 帧，正好是 15 帧段的中点
        frame, values = self.at("single", 0.5)
        self.assertAlmostEqual(frame, 7.5)
        self.assertAlmostEqual(values[0], 0.5)
        # 到达末帧后不再前进，值保持末值而不是回绕
        for seconds in (1.0, 1.5, 3.0):
            frame, values = self.at("single", seconds)
            self.assertAlmostEqual(frame, 15.0)
            self.assertAlmostEqual(values[0], 0.0)

    def test_default_handles_apply_bezier_ease_in_and_out(self) -> None:
        self.assertAlmostEqual(self.at("single", 0.25)[1][0], 0.970275394488)
        self.assertAlmostEqual(self.at("single", 0.75)[1][0], 0.029724605512)

    def test_single_starts_at_the_authored_first_value(self) -> None:
        frame, values = self.at("single", 0.0)
        self.assertAlmostEqual(frame, 0.0)
        self.assertAlmostEqual(values[0], 1.0)

    def test_start_paused_never_advances(self) -> None:
        for seconds in SAMPLES:
            frame, values = self.at("start_paused", seconds)
            self.assertAlmostEqual(frame, 0.0)
            self.assertAlmostEqual(values[0], 1.0)

    def test_loop_wraps_on_absolute_time(self) -> None:
        # fps=4、length=2 → 周期 0.5s
        _, quarter = self.at("loop_vector", 0.25)
        self.assertAlmostEqual(quarter[2], TAU / 2)
        # 0.5s 是整周期边界，回到起点而不是停在末值
        frame, boundary = self.at("loop_vector", 0.5)
        self.assertAlmostEqual(frame, 0.0)
        self.assertAlmostEqual(boundary[2], 0.0)
        # 跨多个周期后仍与首周期同相位
        _, later = self.at("loop_vector", 0.75)
        self.assertAlmostEqual(later[2], TAU / 2)
        _, much_later = self.at("loop_vector", 3.0)
        self.assertAlmostEqual(much_later[2], 0.0)

    def test_vector_lanes_are_evaluated_independently(self) -> None:
        _, values = self.at("loop_vector", 0.25)
        self.assertEqual(len(values), 3)
        # 只有 c2 是非零旋转，前两轴保持 0
        self.assertAlmostEqual(values[0], 0.0)
        self.assertAlmostEqual(values[1], 0.0)
        self.assertGreater(values[2], 0.0)

    def test_mirror_reverses_at_the_end_and_repeats(self) -> None:
        # fps=10、length=10 → 单程 1s，周期 2s
        self.assertAlmostEqual(self.at("mirror", 0.5)[1][0], 0.5)
        self.assertAlmostEqual(self.at("mirror", 1.0)[1][0], 1.0)
        # 折返段：1.5s 与 0.5s 同值
        self.assertAlmostEqual(self.at("mirror", 1.5)[1][0], 0.5)
        # 一个完整周期后回到起点
        self.assertAlmostEqual(self.at("mirror", 2.0)[0], 0.0)
        self.assertAlmostEqual(self.at("mirror", 2.0)[1][0], 0.0)
        # 第二个周期与第一个一致
        self.assertAlmostEqual(self.at("mirror", 3.0)[1][0], 1.0)

    def test_interpolation_picks_the_correct_keyframe_span(self) -> None:
        # 0→10 帧升到 1，再 10→30 帧回到 0
        self.assertAlmostEqual(self.at("three_keyframes", 0.5)[1][0], 0.5)
        self.assertAlmostEqual(self.at("three_keyframes", 1.0)[1][0], 1.0)
        # 1.5s → 第 15 帧，落在第二段 1/4 处
        self.assertAlmostEqual(
            self.at("three_keyframes", 1.5)[1][0], 0.970275394488
        )
        self.assertAlmostEqual(self.at("three_keyframes", 2.0)[1][0], 0.5)

    def test_disabled_handles_are_exactly_linear(self) -> None:
        self.assertAlmostEqual(self.at("linear_disabled", 0.25)[1][0], 0.25)
        self.assertAlmostEqual(self.at("linear_disabled", 0.75)[1][0], 0.75)

    def test_one_sided_and_custom_real_wire_handles_are_consumed(self) -> None:
        self.assertAlmostEqual(
            self.at("one_sided_text_width", 0.25)[1][0], 839.107024658232
        )
        self.assertAlmostEqual(
            self.at("custom_camera", 0.25)[1][0], -91.455796420255
        )
        self.assertAlmostEqual(self.at("custom_camera", 0.5)[1][0], -46.25)
        self.assertAlmostEqual(
            self.at("custom_camera", 0.75)[1][0], -4.905885405246
        )

    def test_frames_before_and_after_the_lane_hold_the_endpoints(self) -> None:
        # lane 只覆盖第 10～20 帧，之前保持首值、之后保持末值，不外推
        self.assertAlmostEqual(self.at("offset_lane", 0.0)[1][0], 5.0)
        self.assertAlmostEqual(self.at("offset_lane", 0.5)[1][0], 5.0)
        self.assertAlmostEqual(self.at("offset_lane", 1.5)[1][0], 10.0)
        self.assertAlmostEqual(self.at("offset_lane", 2.0)[1][0], 15.0)
        self.assertAlmostEqual(self.at("offset_lane", 3.0)[1][0], 15.0)

    def test_out_of_range_component_returns_nothing(self) -> None:
        for name in CASES:
            with self.subTest(case=name):
                self.assertEqual(self.result[name]["outOfRangeComponent"], "-")


if __name__ == "__main__":
    unittest.main()
