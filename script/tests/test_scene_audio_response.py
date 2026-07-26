#!/usr/bin/env python3
"""Scene audio response 求值器（A1）门。

对照源：stock `effects/shake/shaders/effects/shake.vert` 与
`effects/pulse/shaders/effects/pulse.vert` 的 `CreateAudioResponse`
（两份逐字一致）。

本门分两类断言：
  1. 逐字复现官方公式的数值对照（含官方自身的退化路径）；
  2. 官方未定义行为（GLSL UB）被替换为安全行为后的结果。
两类必须分开，不能把 UB 兜底写成「官方语义」。
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneAudioSpectrum.swift"
)
RESPONSE_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneAudioResponse.swift"
)
SHAKE_VERT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle"
    / "assets/effects/shake/shaders/effects/shake.vert"
)
PULSE_VERT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle"
    / "assets/effects/pulse/shaders/effects/pulse.vert"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let bandCount = SceneAudioSpectrumSnapshot.bandCount
        // left[i] = 0.8 恒定，right[i] = 0.4 恒定，便于手算对照。
        let flat = SceneAudioSpectrumSnapshot(
            left: Array(repeating: 0.8, count: bandCount),
            right: Array(repeating: 0.4, count: bandCount),
            generation: 1
        )
        // 逐段递增，用于验证频段区间选择确实生效。
        let ramp = SceneAudioSpectrumSnapshot(
            left: (0 ..< bandCount).map { Float($0) / 15.0 },
            right: (0 ..< bandCount).map { 1 - Float($0) / 15.0 },
            generation: 2
        )
        let silent = SceneAudioSpectrumSnapshot.silent

        var results: [String: Any] = [:]

        func record(
            _ name: String,
            _ spectrum: SceneAudioSpectrumSnapshot,
            channel: Int,
            min minimum: Float,
            max maximum: Float,
            lower: Float,
            upper: Float,
            exponent: Float,
            multiply: Float
        ) {
            let parameters = SceneAudioResponse.Parameters(
                channel: SceneAudioResponse.Channel(comboValue: channel) ?? .off,
                frequencyMin: minimum,
                frequencyMax: maximum,
                boundsLower: lower,
                boundsUpper: upper,
                exponent: exponent,
                multiply: multiply
            )
            let value = SceneAudioResponse.evaluate(
                spectrum: spectrum,
                parameters: parameters
            )
            results[name] = Double(value)
        }

        // --- 官方公式数值对照 ---
        // mode 1: sum(left[0...3]) = 3.2, /4 = 0.8
        // smoothstep(0,1,0.8) = 0.8^2*(3-1.6) = 0.896; pow(,1)=0.896; *1
        record("leftAverage", flat, channel: 1, min: 0, max: 3,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // mode 2: sum(right[0...3]) = 1.6, /4 = 0.4
        // smoothstep(0,1,0.4) = 0.16*(3-0.8) = 0.352
        record("rightAverage", flat, channel: 2, min: 0, max: 3,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // mode 3: sum(left+right over 0...3) = 3.2+1.6 = 4.8, /(4*2)=0.6
        // smoothstep(0,1,0.6) = 0.36*(3-1.2) = 0.648
        record("stereoAverage", flat, channel: 3, min: 0, max: 3,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // mode 0 恒零
        record("channelOff", flat, channel: 0, min: 0, max: 3,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // 单频段：left[5] = 0.8, /1 = 0.8 -> 0.896
        record("singleBand", flat, channel: 1, min: 5, max: 5,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // 区间选择：ramp left[12..15] = 12/15,13/15,14/15,15/15
        // sum = (12+13+14+15)/15 = 54/15 = 3.6, /4 = 0.9
        // smoothstep(0,1,0.9) = 0.81*(3-1.8) = 0.972
        record("highBands", ramp, channel: 1, min: 12, max: 15,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // multiply 可以把结果推过 1：0.896 * 2 = 1.792
        record("multiplyAboveOne", flat, channel: 1, min: 0, max: 3,
               lower: 0, upper: 1, exponent: 1, multiply: 2)
        // exponent: 0.896^2 = 0.802816
        record("exponentSquared", flat, channel: 1, min: 0, max: 3,
               lower: 0, upper: 1, exponent: 2, multiply: 1)
        // bounds 收窄：averaged=0.8, smoothstep(0.5,1.0,0.8): t=0.6
        // 0.36*(3-1.2) = 0.648
        record("narrowBounds", flat, channel: 1, min: 0, max: 3,
               lower: 0.5, upper: 1.0, exponent: 1, multiply: 1)
        // averaged 低于 bounds 下沿 -> 0
        record("belowBounds", flat, channel: 1, min: 0, max: 3,
               lower: 0.9, upper: 1.0, exponent: 1, multiply: 1)
        // 静音 -> smoothstep(0,1,0) = 0
        record("silence", silent, channel: 3, min: 0, max: 15,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // stock shake 默认 bounds 0.0 1.2：averaged=0.8, t=2/3
        // (4/9)*(3-4/3) = 0.444444*1.666667 = 0.740741
        record("shakeDefaultBounds", flat, channel: 1, min: 0, max: 3,
               lower: 0.0, upper: 1.2, exponent: 1, multiply: 1)

        // --- 官方自身的退化路径（不是 UB）---
        // min > max：循环不执行 -> 0；除数 = 2-5+1 = -2；0/-2 = -0
        // smoothstep(0, 1.2, -0) = 0
        record("minAboveMaxZeroBounds", flat, channel: 1, min: 5, max: 2,
               lower: 0, upper: 1.2, exponent: 1, multiply: 1)
        // 同样 min > max，但 bounds 下沿为负：smoothstep(-1, 1, 0)
        // t = 0.5 -> 0.25*(3-1) = 0.5
        record("minAboveMaxNegativeBounds", flat, channel: 1, min: 5, max: 2,
               lower: -1, upper: 1, exponent: 1, multiply: 1)

        // --- UB 替换 ---
        // 除数为零：min = max + 1 -> (2-3+1) = 0
        record("zeroDivisor", flat, channel: 1, min: 3, max: 2,
               lower: 0, upper: 1.2, exponent: 1, multiply: 1)
        // 频段上界越界：max=99 时官方会越界读，这里夹到 15
        // sum(left[0...15]) = 12.8，除数 = 99-0+1 = 100 -> 0.128
        // smoothstep(0,1,0.128) = 0.016384*(3-0.256) = 0.044957
        record("upperBandClamped", flat, channel: 1, min: 0, max: 99,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // 频段下界为负：夹到 0，除数 = 3-(-4)+1 = 8
        // sum(left[0...3]) = 3.2 -> 0.4 -> smoothstep(0,1,0.4)=0.352
        record("lowerBandClamped", flat, channel: 1, min: -4, max: 3,
               lower: 0, upper: 1, exponent: 1, multiply: 1)
        // bounds 反序：upper <= lower 时退化为阶跃，averaged=0.8 >= upper=0.5 -> 1
        record("invertedBounds", flat, channel: 1, min: 0, max: 3,
               lower: 1.0, upper: 0.5, exponent: 1, multiply: 1)
        // 非有限参数一律归零
        record("nanExponent", flat, channel: 1, min: 0, max: 3,
               lower: 0, upper: 1, exponent: .nan, multiply: 1)
        record("infiniteMultiply", flat, channel: 1, min: 0, max: 3,
               lower: 0, upper: 1, exponent: 1, multiply: .infinity)
        record("nanBounds", flat, channel: 1, min: 0, max: 3,
               lower: .nan, upper: 1, exponent: 1, multiply: 1)

        results["channelFromCombo"] = [
            SceneAudioResponse.Channel(comboValue: 0)?.rawValue ?? -1,
            SceneAudioResponse.Channel(comboValue: 1)?.rawValue ?? -1,
            SceneAudioResponse.Channel(comboValue: 2)?.rawValue ?? -1,
            SceneAudioResponse.Channel(comboValue: 3)?.rawValue ?? -1,
            SceneAudioResponse.Channel(comboValue: 4)?.rawValue ?? -1,
            SceneAudioResponse.Channel(comboValue: -1)?.rawValue ?? -1,
        ]

        let data = try JSONSerialization.data(
            withJSONObject: results,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAudioResponseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-audio-response-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-audio-response"
        compilation = subprocess.run(
            [
                "swiftc",
                str(SNAPSHOT_SOURCE),
                str(RESPONSE_SOURCE),
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
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def assertClose(self, name: str, expected: float) -> None:
        self.assertAlmostEqual(
            self.result[name], expected, places=5, msg=f"{name} 偏离官方公式"
        )

    # --- 官方公式数值对照 ---

    def test_channel_modes_average_the_declared_buffers(self) -> None:
        # mode 1/2 除以 (max-min+1)，mode 3 再额外除以 2
        self.assertClose("leftAverage", 0.896)
        self.assertClose("rightAverage", 0.352)
        self.assertClose("stereoAverage", 0.648)

    def test_channel_off_is_always_zero(self) -> None:
        self.assertEqual(self.result["channelOff"], 0.0)

    def test_single_band_and_band_range_selection(self) -> None:
        self.assertClose("singleBand", 0.896)
        self.assertClose("highBands", 0.972)

    def test_multiply_applies_after_saturate_so_result_may_exceed_one(self) -> None:
        self.assertClose(
            "multiplyAboveOne",
            1.792,
            )
        self.assertGreater(
            self.result["multiplyAboveOne"],
            1.0,
            "saturate 只作用于 pow 结果，audioamount 可把响应推过 1",
        )

    def test_exponent_applies_before_saturate(self) -> None:
        self.assertClose("exponentSquared", 0.802816)

    def test_bounds_shape_the_response(self) -> None:
        self.assertClose("narrowBounds", 0.648)
        self.assertEqual(self.result["belowBounds"], 0.0)
        self.assertClose("shakeDefaultBounds", 0.740741)

    def test_silence_yields_zero_response(self) -> None:
        self.assertEqual(
            self.result["silence"], 0.0, "静音必须得到零响应"
        )

    # --- 官方自身的退化路径 ---

    def test_min_above_max_follows_the_official_degenerate_path(self) -> None:
        # 官方除数未经 max() 修正：循环不执行、除数为负，结果是 smoothstep(bounds, 0)。
        # 这不是「非法输入」，不能在求值层 fail closed。
        self.assertEqual(
            self.result["minAboveMaxZeroBounds"],
            0.0,
            "bounds 下沿为 0 时官方退化路径得零",
        )
        self.assertClose("minAboveMaxNegativeBounds", 0.5)

    # --- UB 替换 ---

    def test_zero_divisor_fails_closed_instead_of_propagating_nan(self) -> None:
        self.assertEqual(
            self.result["zeroDivisor"],
            0.0,
            "官方 0/0 得 NaN；我方必须归零",
        )

    def test_band_indices_are_clamped_without_changing_the_divisor(self) -> None:
        # 夹断只影响读取范围，除数仍用作者原值，因此结果明显被稀释。
        self.assertClose("upperBandClamped", 0.044957)
        self.assertClose("lowerBandClamped", 0.352)

    def test_inverted_bounds_degrade_to_a_step(self) -> None:
        self.assertEqual(self.result["invertedBounds"], 1.0)

    def test_non_finite_parameters_yield_zero(self) -> None:
        self.assertEqual(self.result["nanExponent"], 0.0)
        self.assertEqual(self.result["infiniteMultiply"], 0.0)
        self.assertEqual(self.result["nanBounds"], 0.0)

    def test_channel_only_accepts_the_four_official_combo_values(self) -> None:
        self.assertEqual(
            self.result["channelFromCombo"],
            [0, 1, 2, 3, -1, -1],
            "AUDIOPROCESSING 只有 0..3 四个官方取值",
        )


class SceneAudioResponseSourceContractTests(unittest.TestCase):
    """锁定取证来源：stock shader 的算法若变化，本门必须一起复核。"""

    def test_shake_and_pulse_share_one_audio_response_function(self) -> None:
        def extract(path: Path) -> str:
            text = path.read_text(encoding="utf-8")
            start = text.index("float CreateAudioResponse")
            end = text.index("\n}", start)
            return text[start:end]

        self.assertEqual(
            extract(SHAKE_VERT),
            extract(PULSE_VERT),
            "两者一旦分叉，effect 侧不能再共用同一个求值器",
        )

    def test_official_divisor_is_not_corrected_by_max(self) -> None:
        text = SHAKE_VERT.read_text(encoding="utf-8")
        self.assertIn(
            "audioResponse /= (g_AudioFrequencyMax - g_AudioFrequencyMin + 1.0)",
            text,
            "除数必须是未经 max() 修正的原始差值",
        )
        self.assertIn(
            "float audioFrequencyEnd = max(g_AudioFrequencyMin, g_AudioFrequencyMax);",
            text,
            "官方死代码仍在；若官方改为使用它，退化路径断言需要重做",
        )

    def test_official_saturates_before_multiplying(self) -> None:
        text = SHAKE_VERT.read_text(encoding="utf-8")
        self.assertIn(
            "saturate(pow(audioResponse, g_AudioPower)) * g_AudioMultiply",
            text,
        )


if __name__ == "__main__":
    unittest.main()
