#!/usr/bin/env python3
"""验证 Scene 作者频谱、快照、原子需求与 capture scope。"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
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
GRAPH_DIAGNOSTICS_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+DynamicUniformDiagnostics.swift"
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

    # MARK: author analyzer

    def test_author_spectrum_uses_the_contiguous_rectangular_tail_and_keeps_dc_leakage(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(analyzer["usesTail"])
        self.assertTrue(analyzer["incompleteTailSilent"])
        center, half = analyzer["center64"], analyzer["half64"]
        self.assertGreater(center[10], 0)
        self.assertGreater(center[11], 0)
        self.assertGreater(half[11], 0)
        # Ratio across the two PCM arms cancels the same-group gain and fixed bin weights.
        # Official ~.05, versus ~.72 for Hann on the same 1392/2089 window.
        cross_ratio = (half[10] / half[11]) / (center[10] / center[11])
        self.assertGreater(cross_ratio, 0.03)
        self.assertLess(cross_ratio, 0.08)
        dc = analyzer["dc64"]
        self.assertGreater(dc[0], 0)
        self.assertAlmostEqual(dc[1] / dc[0], 0.5, delta=0.03)
        self.assertLess(dc[2], dc[0] * 0.01)

    def test_author_channels_fold_by_peak_and_preserve_above_one(self) -> None:
        analyzer = self.result["analyzer"]
        left64, right64, left32, right32, left16, right16 = analyzer["stereo"]
        self.assertEqual(len(left64), 64)
        self.assertEqual(len(right64), 64)
        self.assertEqual(left64.index(max(left64)), 11)
        self.assertEqual(right64.index(max(right64)), 48)
        for fine, medium, coarse in ((left64, left32, left16), (right64, right32, right16)):
            self.assertEqual(medium, [max(fine[i:i + 2]) for i in range(0, 64, 2)])
            self.assertEqual(coarse, [max(fine[i:i + 4]) for i in range(0, 64, 4)])
            self.assertTrue(all(0 <= value < float("inf") for value in fine))
        self.assertGreater(analyzer["hotPeak"], 1)
        self.assertTrue(analyzer["hotRightSilent"])
        self.assertTrue(analyzer["monoMirrors"])
        self.assertTrue(analyzer["monoMatchesStereo"])

    def test_author_silence_and_format_transitions_keep_their_own_history(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(analyzer["silent"])
        self.assertGreaterEqual(analyzer["nearSilentPeak"], 0)
        self.assertLess(analyzer["nearSilentPeak"], 0.1)
        self.assertTrue(analyzer["staleFormatPreservesCurrent"])
        self.assertTrue(analyzer["newRateMatchesFresh"])
        other_rate = analyzer["changedRate64"]
        self.assertGreater(max(other_rate), 0)
        self.assertEqual(other_rate.index(max(other_rate)), 11)
        self.assertTrue(analyzer["returnTo48kMatchesFresh"])
        self.assertTrue(analyzer["invalidRateSilent"])
        self.assertTrue(analyzer["recoveryMatchesFresh"])
        self.assertTrue(analyzer["authorResetMatchesFresh"])
        self.assertTrue(analyzer["authorResetPreservesDisplay"])

    def test_author_reentry_distinguishes_short_and_long_quiet_capture_time(self) -> None:
        reentry = self.result["analyzer"]["reentry"]
        self.assertGreater(reentry["fresh"], 0)
        self.assertGreater(reentry["short30"], reentry["fresh"] * 1.5)
        for capture in ("long30", "long60"):
            self.assertAlmostEqual(reentry[capture], reentry["fresh"], delta=0.000_1)

    def test_author_shared_peak_moves_each_group_from_its_own_history(self) -> None:
        before, attack, held = self.result["analyzer"]["sharedAttack"]
        self.assertGreater(before[0], .98)
        self.assertGreater(before[1], .6)
        self.assertLess(attack[0], before[0] * .9)
        self.assertLess(attack[1] / before[1], attack[0] / before[0])
        self.assertAlmostEqual(held[0], .183, delta=.01)
        self.assertAlmostEqual(held[1], .05, delta=.01)

    def test_author_bands_take_one_step_and_hold_history_during_silence(self) -> None:
        for result in self.result["analyzer"]["bandSteps"]:
            before, first, repeated, second, release, quiet, stale, resumed, reset = result
            self.assertAlmostEqual(first - before, 1, delta=0.0001)
            self.assertEqual(repeated, first)
            self.assertAlmostEqual(second - first, 1, delta=0.0001)
            self.assertAlmostEqual(second - release, 1, delta=0.0001)
            self.assertEqual((quiet, stale), (0, 0))
            self.assertAlmostEqual(resumed - release, 1, delta=0.0001)
            self.assertAlmostEqual(reset, 1, delta=0.0001)


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
        source = GRAPH_DIAGNOSTICS_SOURCE.read_text(encoding="utf-8")
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
            source.split("func recordTypedUserPropertyUniformPublications(", 1)[0],
        )
        self.assertIn(
            "recordPreparedMaterialDiagnostics(",
            preparation,
            "the proof must run at the existing prepared Program consumer boundary",
        )


if __name__ == "__main__":
    unittest.main()
