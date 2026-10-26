#!/usr/bin/env python3
"""验证 Scene snapshot、原子 demand、共享 analyzer 与 capture-scope 接线。"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift"
)
ANALYZER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift"
)
CAPTURE_BUFFER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/SystemAudioCaptureBuffer.swift"
)
SERVICE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/SystemAudioSpectrumService.swift"
)
GRAPH_EXECUTOR_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift"
)
GRAPH_PREPARATION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Preparation.swift"
)

HARNESS = (REPOSITORY_ROOT / "script/tests/fixtures/SceneAudioSpectrumInputHarness.swift").read_text(encoding="utf-8")


class SceneAudioSpectrumInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-audio-spectrum-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-audio-spectrum"
        compilation = subprocess.run(
            [
                "swiftc",
                str(SNAPSHOT_SOURCE),
                str(CAPTURE_BUFFER_SOURCE),
                str(ANALYZER_SOURCE),
                str(REPOSITORY_ROOT / "script/tests/fixtures/SystemAudioSpectrumTestCapture.swift"),
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

    # MARK: snapshot

    def test_snapshot_carries_the_official_sixteen_band_shape(self) -> None:
        snapshot = self.result["snapshot"]
        self.assertEqual(snapshot["bandCount"], 16)
        self.assertEqual(len(snapshot["acceptedLeft"]), 16)
        self.assertEqual(snapshot["acceptedGeneration"], 7)
        self.assertFalse(snapshot["acceptedIsSilent"])

    def test_snapshot_carries_the_workshop_sixty_four_band_shape(self) -> None:
        snapshot = self.result["snapshot"]
        self.assertEqual(snapshot["extendedBandCount"], 64)
        self.assertEqual(len(snapshot["acceptedLeft64"]), 64)

    def test_snapshot_carries_the_workshop_thirty_two_band_shape(self) -> None:
        snapshot = self.result["snapshot"]
        self.assertEqual(snapshot["mediumBandCount"], 32)
        self.assertEqual(len(snapshot["acceptedLeft32"]), 32)

    def test_snapshot_zeroes_wrong_length_and_non_finite_values(self) -> None:
        snapshot = self.result["snapshot"]
        self.assertEqual(
            snapshot["shortInputLeft"],
            [0.0] * 16,
            "长度不符的输入必须整体归零，不能截断或补齐后当作有效频谱",
        )
        self.assertTrue(
            snapshot["shortInputRightUnchanged"],
            "一侧非法不应污染另一侧",
        )
        sanitized = snapshot["sanitizedLeft"]
        self.assertEqual(sanitized[2], 0.0, "NaN 必须归零")
        self.assertEqual(sanitized[3], 0.0, "inf 必须归零")
        self.assertEqual(sanitized[4], 0.0, "负值必须归零：官方合同是正值")
        self.assertNotEqual(sanitized[5], 0.0, "合法频段不应被牵连归零")

    def test_silent_snapshot_is_a_stable_zero_input(self) -> None:
        snapshot = self.result["snapshot"]
        self.assertTrue(snapshot["silentIsSilent"])
        self.assertEqual(snapshot["silentGeneration"], 0)
        self.assertEqual(snapshot["silentCount"], 16)
        self.assertEqual(snapshot["silentMediumCount"], 32)
        self.assertEqual(snapshot["silentExtendedCount"], 64)

    # MARK: inbox

    def test_inbox_starts_silent_and_increments_generation_per_publish(self) -> None:
        inbox = self.result["inbox"]
        self.assertTrue(inbox["initialIsSilent"])
        self.assertEqual(inbox["initialGeneration"], 0)
        self.assertEqual(inbox["firstLeft"], [0.25] * 16)
        self.assertEqual(inbox["firstRight"], [0.5] * 16)
        self.assertEqual(inbox["firstLeft32"], [0.625] * 32)
        self.assertEqual(inbox["firstRight32"], [0.875] * 32)
        self.assertEqual(inbox["firstLeft64"], [0.75] * 64)
        self.assertEqual(inbox["firstRight64"], [1.0] * 64)
        self.assertEqual(inbox["firstGeneration"], 1)
        self.assertEqual(
            inbox["secondGeneration"],
            2,
            "每次发布都要递增代际，消费者据此区分新采样与重复读取",
        )

    def test_revoking_demand_clears_the_last_snapshot(self) -> None:
        inbox = self.result["inbox"]
        self.assertFalse(inbox["demandedBefore"], "默认不请求采集")
        self.assertTrue(inbox["demandedAfter"])
        self.assertTrue(inbox["noConsumerIncludeNormalizesToNone"])
        self.assertTrue(inbox["scopeChangeClearsSnapshot"])
        self.assertTrue(inbox["scopeChangePublishesAtomically"])
        self.assertTrue(inbox["policyChangeNotifiesOnce"])
        self.assertFalse(inbox["beforeRevokeIsSilent"])
        self.assertTrue(
            inbox["afterRevokeIsSilent"],
            "撤销需求后必须归零，否则停止采集会残留最后一帧非零数据",
        )
        self.assertFalse(inbox["afterRevokeDemanded"])

    def test_demand_observer_only_fires_on_real_changes(self) -> None:
        self.assertEqual(
            self.result["inbox"]["observed"],
            [True, True, False, True, False],
            "重复设置同一需求值不得重复通知，避免反复重启采集",
        )

    def test_reset_restores_the_initial_state(self) -> None:
        inbox = self.result["inbox"]
        self.assertGreater(inbox["generationBeforeReset"], 0)
        self.assertEqual(inbox["afterResetGeneration"], 0)
        self.assertTrue(inbox["afterResetIsSilent"])
        self.assertTrue(inbox["afterResetDemandIsNone"])

    def test_stale_snapshot_fails_closed_instead_of_freezing(self) -> None:
        inbox = self.result["inbox"]
        self.assertFalse(
            inbox["beforeStaleDeadlineIsSilent"],
            "正常采集间隔内不得误清仍有效的频谱",
        )
        self.assertTrue(
            inbox["afterStaleDeadlineIsSilent"],
            "producer 停止发布后必须归零，不能留下被 Scroll 平移的静态波形",
        )
        self.assertTrue(inbox["staleCandidateIsSilent"])
        self.assertEqual(
            inbox["staleCandidateSourceGeneration"],
            inbox["staleRetrySourceGeneration"],
            "dropped stale candidate 不得提前改写 shared generation",
        )
        self.assertTrue(inbox["staleRetryRemainsPending"])
        self.assertGreater(
            inbox["staleRevocationGeneration"],
            1,
            "stale 撤销必须有独立代际，便于消费者区分最后活动帧与归零帧",
        )

    # MARK: analyzer

    def test_analyzer_is_available_and_emits_sixteen_bands(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(analyzer["available"], "FFT setup 必须可用")
        self.assertEqual(analyzer["bandCount"], 16)
        self.assertEqual(len(analyzer["stereoLeft"]), 16)
        self.assertEqual(len(analyzer["stereoRight"]), 16)

    def test_analyzer_emits_sixty_four_bands_from_the_same_fft(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(analyzer["extendedBandCount"], 64)
        self.assertEqual(len(analyzer["stereoLeft64"]), 64)
        self.assertEqual(len(analyzer["stereoRight64"]), 64)
        self.assertLess(
            analyzer["stereoLeft64PeakBand"],
            analyzer["stereoRight64PeakBand"],
        )
        self.assertTrue(analyzer["left16PeakMatches64Group"])
        self.assertTrue(analyzer["right16PeakMatches64Group"])

    def test_analyzer_emits_thirty_two_bands_from_the_same_fft(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(analyzer["mediumBandCount"], 32)
        self.assertEqual(len(analyzer["stereoLeft32"]), 32)
        self.assertEqual(len(analyzer["stereoRight32"]), 32)
        self.assertLess(
            analyzer["stereoLeft32PeakBand"],
            analyzer["stereoRight32PeakBand"],
        )
        self.assertTrue(analyzer["left32PeakMatches64Group"])
        self.assertTrue(analyzer["right32PeakMatches64Group"])

    def test_silence_produces_a_stable_zero_spectrum(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(
            analyzer["silentLeft"],
            [0.0] * 16,
            "静音必须输出稳定零，不得产生假波形",
        )
        self.assertEqual(analyzer["silentRight"], [0.0] * 16)

    def test_tones_land_in_the_expected_low_to_high_bands(self) -> None:
        analyzer = self.result["analyzer"]
        # 官方只给出低频到高频的顺序，不公开 440 Hz/5 kHz 的精确 band
        # 边界；不能把当前 producer 的私有 warp 常数写成验收标准。
        for resolution, low_key, high_key in (
            (16, "stereoLeftPeakBand", "stereoRightPeakBand"),
            (32, "stereoLeft32PeakBand", "stereoRight32PeakBand"),
            (64, "stereoLeft64PeakBand", "stereoRight64PeakBand"),
        ):
            self.assertIn(analyzer[low_key], range(resolution))
            self.assertIn(analyzer[high_key], range(resolution))
            self.assertLess(
                analyzer[low_key],
                analyzer[high_key],
                f"{resolution} 档必须保留 440 Hz 到 5 kHz 的频率顺序",
            )

    def test_author_output_stays_finite_and_positive(self) -> None:
        self.assertTrue(self.result["analyzer"]["allFinitePositive"])

    def test_bass_dominant_input_keeps_unrelated_upper_bands_bounded(self) -> None:
        analyzer = self.result["analyzer"]
        # 旧测试要求纯低频输入必须合成右半轴活动底；这会把一个真实
        # 低频峰复制成多个无关柱。官方没有要求纯 bass 的上半轴全零，
        # 因此这里只约束不能由其产生比主峰还高的人工上半轴。
        self.assertGreater(analyzer["bassOnlyPeak"], 0)
        self.assertLessEqual(
            analyzer["bassOnlyUpperPeak"], analyzer["bassOnlyPeak"]
        )
        self.assertLessEqual(analyzer["bassOnlyUpperNonZero"], 8)

    def test_scene_retains_listening_volume_changes_and_visible_weak_bands(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertGreater(analyzer["loudPeak"] - analyzer["quietPeak"], 0.1)
        self.assertGreater(
            analyzer["loudPeak"],
            0.31,
            "正常 PCM 必须经过共享分贝响应进入作者 shader 的可见高度区间",
        )
        self.assertGreater(
            analyzer["quietPeak"],
            0.05,
            "普通弱音必须经过可视响应后仍能驱动作者波形，不能缩成不可见细线",
        )

    def test_fixed_spectral_shape_tracks_a_real_pcm_energy_pulse(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertGreater(
            analyzer["rhythmFirstRise"],
            analyzer["rhythmFirstFall"] * 1.35,
            "同一频谱形状的起音与回落必须在 producer 输出中保持可见节奏",
        )
        self.assertGreater(
            analyzer["rhythmSecondRise"],
            analyzer["rhythmSecondFall"] * 1.35,
            "重复的 PCM 能量脉冲必须重复产生 rise/fall，而不是只在首帧跳动",
        )
        self.assertGreater(
            analyzer["rhythmPeakRange"],
            0.12,
            "频谱柱的全局强弱必须对真实 PCM 能量有足够响应",
        )
        self.assertGreaterEqual(
            analyzer["rhythmBandCountRange"],
            1,
            "能量脉冲不能被压成一条恒定高度的静态柱列",
        )

    def test_near_silent_input_remains_bounded_below_normal_audio(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertGreaterEqual(analyzer["noiseFloorPeak"], 0)
        self.assertLess(
            analyzer["noiseFloorPeak"],
            analyzer["quietPeak"],
            "接近门限的输入不能比正常弱音更强",
        )

    def test_visual_envelope_attacks_quickly_and_releases_monotonically(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertGreater(analyzer["attackFirstPeak"], 0)
        self.assertGreater(analyzer["attackSecondPeak"], analyzer["attackFirstPeak"])
        self.assertLess(analyzer["releaseFirstPeak"], analyzer["attackSecondPeak"])
        self.assertLess(analyzer["releaseSecondPeak"], analyzer["releaseFirstPeak"])
        self.assertGreater(
            analyzer["releaseSecondPeak"],
            0,
            "尾音应连续衰减而不是每个采集 tick 硬切闪烁",
        )

    def test_capture_produces_no_frame_until_complete_window(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(analyzer["firstPartialHasNoFrame"])
        self.assertTrue(analyzer["secondPartialNonZero"])

    def test_analysis_is_deterministic_for_the_same_input(self) -> None:
        self.assertTrue(
            self.result["analyzer"]["deterministic"],
            "同输入必须同输出，否则粒子 simulation 的确定性门无法成立",
        )

    def test_mono_input_mirrors_both_channels(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(
            analyzer["monoMirrors"],
            "单声道时左右必须一致，使 AUDIOPROCESSING=3 的左右平均等于该声道",
        )
        self.assertTrue(analyzer["monoMatchesStereoLeft"])

    def test_format_switch_resets_previous_envelopes_atomically(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(
            analyzer["channelSwitchMatchesFresh"],
            "stereo→mono 后不得把旧右声道或旧包络泄漏到镜像输出",
        )
        self.assertTrue(
            analyzer["sampleRateSwitchMatchesFresh"],
            "采样率改变后必须按新 FFT bin identity 从干净包络开始",
        )

    def test_invalid_inputs_fail_closed_to_zero(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(
            analyzer["invalidRateLeft"], [0.0] * 16, "非法采样率必须归零"
        )
        self.assertTrue(analyzer["emptyCaptureHasNoFrame"], "空缓冲不得伪造分析帧")
        self.assertTrue(
            analyzer["highRateNonZero"],
            "高采样率分析窗必须有界截断，不能因超过FFT容量而让整链归零",
        )

    def test_non_finite_samples_do_not_corrupt_the_spectrum(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(analyzer["sanitizedToneFinite"])
        self.assertEqual(
            analyzer["sanitizedTonePeakBand"],
            analyzer["stereoLeftPeakBand"],
            "个别非有限采样被置零后，主频段判定仍应成立",
        )

    def test_dc_bias_is_removed_before_frequency_banding(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(
            analyzer["biasedPeakBand"],
            analyzer["stereoLeftPeakBand"],
            "tap 直流偏置不得把主频从 440 Hz 推到第 0 柱",
        )
        self.assertAlmostEqual(
            analyzer["biasedFirstBand"],
            analyzer["unbiasedFirstBand"],
            delta=0.000_1,
        )
        self.assertLess(
            analyzer["biasedToneDelta"],
            0.000_01,
            "去直流后，同一波形的频谱不应因固定偏置变形",
        )

    def test_long_running_upper_bands_keep_updating_without_dc_first_bar_takeover(
        self,
    ) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(
            analyzer["changedUpperBandCount"],
            8,
            "连续高频输入必须让右半全部频段持续更新，不得冻结",
        )
        self.assertEqual(
            analyzer["changedUpperBandCountLate"],
            8,
            "第二个完整扫描周期仍必须让右半全部频段变化，不能只靠早期变化过门",
        )
        self.assertGreater(
            analyzer["lateConsecutiveShapeChanges"],
            0,
            "第二周期必须存在相邻帧形态变化，不能在后半程冻结",
        )
        self.assertLess(
            analyzer["continuityFirstBandRatio"],
            0.20,
            "第 0 柱不得超过同帧主峰的20%，不能吞掉高频响应",
        )


class SceneAudioSpectrumWiringTests(unittest.TestCase):
    """静态接线断言：确保采集服务与播放引擎按 A0 合同接线。"""

    def test_service_gates_capture_on_any_consumer(self) -> None:
        source = SERVICE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("var sceneEnabled = false", source)  # 拆分批(3079ec35)后不再 private
        self.assertIn(
            "overlayEnabled || webEnabled || sceneEnabled",
            source,
            "任一消费者存在才采集",
        )
        self.assertIn("self.onSceneLevels = onSceneLevels", source)
        self.assertRegex(
            source,
            r"(?s)let requestedProcessScope: ProcessScope = sceneEnabled.*?"
            r"case \.includesCurrentProcess:\s*excludedProcessIDs = \[\]\s*"
            r"case \.excludesCurrentProcess:.*?throw .*?currentProcessUnavailable.*?"
            r"excludedProcessIDs = \[currentProcessObjectID\]",
        )
        self.assertRegex(source, r"(?s)private func reconcileCaptureState\(\).*?startCaptureIfNeeded\(\)")

    def test_service_clears_scene_levels_on_stop_and_failure(self) -> None:
        source = SERVICE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("count: SystemAudioSceneSpectrumAnalyzer.bandCount", source)
        self.assertIn("count: SystemAudioSceneSpectrumAnalyzer.mediumBandCount", source)
        self.assertIn("count: SystemAudioSceneSpectrumAnalyzer.extendedBandCount", source)
        self.assertIn(
            "sceneAnalyzer?.reset()",
            source,
            "停止或撤销 consumer 时必须丢弃未完成分析窗，不能跨 capture 混入旧数据",
        )

    def test_inbox_owns_the_stale_snapshot_fail_closed_boundary(self) -> None:
        source = SNAPSHOT_SOURCE.read_text(encoding="utf-8")
        self.assertIn("maximumSnapshotAge", source)
        self.assertIn("publishedAtUptime", source)
        self.assertIn("now - publishedAtUptime", source)
        self.assertNotIn("sin(", source, "stale 处理不得生成时间驱动的假波形")

    def test_debug_audio_consumption_proof_joins_encoded_uniform_to_snapshot(self) -> None:
        source = GRAPH_EXECUTOR_SOURCE.read_text(encoding="utf-8")
        preparation = GRAPH_PREPARATION_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "func recordTypedAudioSpectrumUniformConsumptions(",
            source,
        )
        self.assertIn(
            "audioSpectrum.generation",
            source,
            "consumer evidence must retain the producer generation",
        )
        self.assertIn(
            "zip(encoded, expected).allSatisfy",
            source,
            "evidence must prove the bytes sent to the uniform match the shared snapshot",
        )
        self.assertIn(
            "MWX typed input consumption: channel=audio-spectrum",
            source,
        )
        self.assertIn(
            "recordTypedAudioSpectrumUniformConsumptions(",
            preparation,
            "the proof must run at the existing prepared Program consumer boundary",
        )


if __name__ == "__main__":
    unittest.main()
