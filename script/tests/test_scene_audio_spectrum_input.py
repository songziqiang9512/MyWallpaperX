#!/usr/bin/env python3
"""Scene 音频频谱输入管线（A0）门。

覆盖三段：
  1. `SceneAudioSpectrumSnapshot` 的形状与非法值归零；
  2. `SceneAudioSpectrumInbox` 的发布/代际/需求生命周期；
  3. `SystemAudioSceneSpectrumAnalyzer` 的 16/64 频段输出、静音零输入与确定性。

这里只验证输入管线本身。A0 阶段没有任何 effect / particle 消费者，
因此不存在渲染侧断言。
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
ANALYZER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift"
)
CAPTURE_BUFFER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/SystemAudioCaptureBuffer.swift"
)
SERVICE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/SystemAudioSpectrumService.swift"
)
ENGINE_SPECTRUM_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+SystemAudioSpectrum.swift"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let sampleRate: Float = 48_000

    static func main() throws {
        var payload: [String: Any] = [:]
        payload["snapshot"] = snapshotChecks()
        payload["inbox"] = inboxChecks()
        payload["analyzer"] = analyzerChecks()
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Snapshot

    static func snapshotChecks() -> [String: Any] {
        let bandCount = SceneAudioSpectrumSnapshot.bandCount
        let extendedBandCount = SceneAudioSpectrumSnapshot.extendedBandCount
        let valid = (0 ..< bandCount).map { Float($0) / Float(bandCount) }
        let valid64 = (0 ..< extendedBandCount).map {
            Float($0) / Float(extendedBandCount)
        }
        let accepted = SceneAudioSpectrumSnapshot(
            left: valid,
            right: valid,
            left64: valid64,
            right64: valid64,
            generation: 7
        )
        let shortInput = SceneAudioSpectrumSnapshot(
            left: Array(repeating: Float(0.5), count: 8),
            right: valid,
            generation: 1
        )
        var dirty = valid
        dirty[2] = .nan
        dirty[3] = .infinity
        dirty[4] = -1
        let sanitized = SceneAudioSpectrumSnapshot(
            left: dirty,
            right: dirty,
            generation: 2
        )
        return [
            "bandCount": bandCount,
            "extendedBandCount": extendedBandCount,
            "acceptedLeft": accepted.left,
            "acceptedLeft64": accepted.left64,
            "acceptedGeneration": accepted.generation,
            "acceptedIsSilent": accepted.isSilent,
            "shortInputLeft": shortInput.left,
            "shortInputRightUnchanged": shortInput.right == valid,
            "sanitizedLeft": sanitized.left,
            "silentIsSilent": SceneAudioSpectrumSnapshot.silent.isSilent,
            "silentGeneration": SceneAudioSpectrumSnapshot.silent.generation,
            "silentCount": SceneAudioSpectrumSnapshot.silent.left.count,
            "silentExtendedCount": SceneAudioSpectrumSnapshot.silent.left64.count,
        ]
    }

    // MARK: - Inbox

    static func inboxChecks() -> [String: Any] {
        let inbox = SceneAudioSpectrumInbox()
        let bandCount = SceneAudioSpectrumSnapshot.bandCount
        let ones = Array(repeating: Float(0.25), count: bandCount)
        let twos = Array(repeating: Float(0.5), count: bandCount)
        let ones64 = Array(
            repeating: Float(0.75),
            count: SceneAudioSpectrumSnapshot.extendedBandCount
        )
        let twos64 = Array(
            repeating: Float(1),
            count: SceneAudioSpectrumSnapshot.extendedBandCount
        )

        var observed: [Bool] = []
        inbox.setDemandObserver { observed.append($0) }

        let initial = inbox.latest()
        inbox.publish(left: ones, right: twos, left64: ones64, right64: twos64)
        let first = inbox.latest()
        inbox.publish(left: twos, right: ones)
        let second = inbox.latest()

        let demandedBefore = inbox.isDemanded
        inbox.setDemand(true)
        let demandedAfter = inbox.isDemanded
        inbox.setDemand(true) // 重复设置不应再次通知
        inbox.publish(left: ones, right: ones)
        let beforeRevoke = inbox.latest()
        inbox.setDemand(false)
        let afterRevoke = inbox.latest()

        inbox.publish(left: twos, right: twos)
        let generationBeforeReset = inbox.latest().generation
        inbox.reset()
        let afterReset = inbox.latest()

        return [
            "initialIsSilent": initial.isSilent,
            "initialGeneration": initial.generation,
            "firstLeft": first.left,
            "firstRight": first.right,
            "firstLeft64": first.left64,
            "firstRight64": first.right64,
            "firstGeneration": first.generation,
            "secondGeneration": second.generation,
            "demandedBefore": demandedBefore,
            "demandedAfter": demandedAfter,
            "observed": observed,
            "beforeRevokeIsSilent": beforeRevoke.isSilent,
            "afterRevokeIsSilent": afterRevoke.isSilent,
            "afterRevokeDemanded": inbox.isDemanded,
            "generationBeforeReset": generationBeforeReset,
            "afterResetGeneration": afterReset.generation,
            "afterResetIsSilent": afterReset.isSilent,
        ]
    }

    // MARK: - Analyzer

    static func analyzerChecks() -> [String: Any] {
        guard let analyzer = SystemAudioSceneSpectrumAnalyzer() else {
            return ["available": false]
        }
        let bandCount = SystemAudioSceneSpectrumAnalyzer.bandCount
        let frameCount = 4_096

        let silence = Array(repeating: Float(0), count: frameCount)
        let silent = analyzer.analyze(
            signedChannels: [silence, silence],
            sampleRate: sampleRate
        )

        let toneA = sineWave(frequency: 440, frameCount: frameCount)
        let toneB = sineWave(frequency: 5_000, frameCount: frameCount)
        let stereo = analyzer.analyze(
            signedChannels: [toneA, toneB],
            sampleRate: sampleRate
        )
        let repeated = analyzer.analyze(
            signedChannels: [toneA, toneB],
            sampleRate: sampleRate
        )
        let mono = analyzer.analyze(signedChannels: [toneA], sampleRate: sampleRate)

        let invalidRate = analyzer.analyze(
            signedChannels: [toneA, toneB],
            sampleRate: 0
        )
        let empty = analyzer.analyze(signedChannels: [], sampleRate: sampleRate)

        var withNaN = toneA
        withNaN[10] = .nan
        withNaN[11] = .infinity
        let sanitizedTone = analyzer.analyze(
            signedChannels: [withNaN],
            sampleRate: sampleRate
        )

        // 直流偏置不应把能量堆到最低频段。
        let biased = toneA.map { $0 + 0.5 }
        let biasedResult = analyzer.analyze(
            signedChannels: [biased],
            sampleRate: sampleRate
        )

        return [
            "available": true,
            "bandCount": bandCount,
            "extendedBandCount": SystemAudioSceneSpectrumAnalyzer.extendedBandCount,
            "silentLeft": silent.left,
            "silentRight": silent.right,
            "stereoLeft": stereo.left,
            "stereoRight": stereo.right,
            "stereoLeft64": stereo.left64,
            "stereoRight64": stereo.right64,
            "stereoLeftPeakBand": peakBand(stereo.left),
            "stereoRightPeakBand": peakBand(stereo.right),
            "stereoLeft64PeakBand": peakBand(stereo.left64),
            "stereoRight64PeakBand": peakBand(stereo.right64),
            "deterministic": repeated.left == stereo.left
                && repeated.right == stereo.right
                && repeated.left64 == stereo.left64
                && repeated.right64 == stereo.right64,
            "monoMirrors": mono.left == mono.right && mono.left64 == mono.right64,
            "monoMatchesStereoLeft": mono.left == stereo.left
                && mono.left64 == stereo.left64,
            "invalidRateLeft": invalidRate.left,
            "emptyLeft": empty.left,
            "sanitizedToneFinite": sanitizedTone.left.allSatisfy { $0.isFinite },
            "sanitizedTonePeakBand": peakBand(sanitizedTone.left),
            "biasedPeakBand": peakBand(biasedResult.left),
            "allWithinUnitRange": (stereo.left + stereo.right)
                .allSatisfy { $0 >= 0 && $0 <= 1 }
                && (stereo.left64 + stereo.right64)
                    .allSatisfy { $0 >= 0 && $0 <= 1 },
        ]
    }

    static func sineWave(frequency: Float, frameCount: Int) -> [Float] {
        (0 ..< frameCount).map { index in
            sin(2 * .pi * frequency * Float(index) / sampleRate) * 0.5
        }
    }

    static func peakBand(_ levels: [Float]) -> Int {
        var bestIndex = -1
        var bestValue: Float = 0
        for (index, value) in levels.enumerated() where value > bestValue {
            bestValue = value
            bestIndex = index
        }
        return bestIndex
    }
}
'''


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
        self.assertEqual(snapshot["silentExtendedCount"], 64)

    # MARK: inbox

    def test_inbox_starts_silent_and_increments_generation_per_publish(self) -> None:
        inbox = self.result["inbox"]
        self.assertTrue(inbox["initialIsSilent"])
        self.assertEqual(inbox["initialGeneration"], 0)
        self.assertEqual(inbox["firstLeft"], [0.25] * 16)
        self.assertEqual(inbox["firstRight"], [0.5] * 16)
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
        self.assertFalse(inbox["beforeRevokeIsSilent"])
        self.assertTrue(
            inbox["afterRevokeIsSilent"],
            "撤销需求后必须归零，否则停止采集会残留最后一帧非零数据",
        )
        self.assertFalse(inbox["afterRevokeDemanded"])

    def test_demand_observer_only_fires_on_real_changes(self) -> None:
        self.assertEqual(
            self.result["inbox"]["observed"],
            [True, False],
            "重复设置同一需求值不得重复通知，避免反复重启采集",
        )

    def test_reset_restores_the_initial_state(self) -> None:
        inbox = self.result["inbox"]
        self.assertGreater(inbox["generationBeforeReset"], 0)
        self.assertEqual(inbox["afterResetGeneration"], 0)
        self.assertTrue(inbox["afterResetIsSilent"])

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
        # 频段按 32 Hz -> 16 kHz 对数划分（ratio=500）：
        # band b 的下沿为 32 * 500^(b/16)，440 Hz 落在 band 6（328.9~485 Hz），
        # 5 kHz 落在 band 13（4989~7364 Hz）。
        self.assertEqual(
            analyzer["stereoLeftPeakBand"],
            6,
            "440 Hz 必须落在对数划分下的第 6 段",
        )
        self.assertEqual(
            analyzer["stereoRightPeakBand"],
            13,
            "5 kHz 必须落在更高频段，证明频段顺序由低到高",
        )
        self.assertLess(
            analyzer["stereoLeftPeakBand"],
            analyzer["stereoRightPeakBand"],
        )

    def test_output_stays_positive_and_within_unit_range(self) -> None:
        self.assertTrue(self.result["analyzer"]["allWithinUnitRange"])

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

    def test_invalid_inputs_fail_closed_to_zero(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(
            analyzer["invalidRateLeft"], [0.0] * 16, "非法采样率必须归零"
        )
        self.assertEqual(analyzer["emptyLeft"], [0.0] * 16, "空输入必须归零")

    def test_non_finite_samples_do_not_corrupt_the_spectrum(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(analyzer["sanitizedToneFinite"])
        self.assertEqual(
            analyzer["sanitizedTonePeakBand"],
            6,
            "个别非有限采样被置零后，主频段判定仍应成立",
        )

    def test_dc_bias_does_not_pile_energy_into_the_lowest_band(self) -> None:
        self.assertEqual(
            self.result["analyzer"]["biasedPeakBand"],
            6,
            "去直流后带偏置的信号仍应在原频段出现峰值",
        )


class SceneAudioSpectrumWiringTests(unittest.TestCase):
    """静态接线断言：确保采集服务与播放引擎按 A0 合同接线。"""

    def test_service_gates_capture_on_any_consumer(self) -> None:
        source = SERVICE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("private var sceneEnabled = false", source)
        self.assertIn(
            "overlayEnabled || webEnabled || sceneEnabled",
            source,
            "任一消费者存在才采集",
        )
        self.assertIn("var onSceneLevels:", source)

    def test_service_clears_scene_levels_on_stop_and_failure(self) -> None:
        source = SERVICE_SOURCE.read_text(encoding="utf-8")
        self.assertEqual(
            source.count("clearSceneLevels()"),
            5,
            "消费者切换、采集停止、FFT 不可用与采集失败四处都必须调用统一归零入口",
        )
        self.assertIn("count: SystemAudioSceneSpectrumAnalyzer.bandCount", source)
        self.assertIn("count: SystemAudioSceneSpectrumAnalyzer.extendedBandCount", source)

    def test_engine_routes_scene_levels_into_the_inbox(self) -> None:
        source = ENGINE_SPECTRUM_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "left64: left64",
            source,
        )
        self.assertIn("SceneAudioSpectrumInbox.shared.isDemanded", source)
        self.assertIn("sceneEnabled: sceneCaptureRequested", source)

    def test_engine_stops_scene_capture_under_system_interruptions(self) -> None:
        source = ENGINE_SPECTRUM_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let sceneCaptureRequested = captureAllowed", source)
        self.assertIn(
            "SceneAudioSpectrumInbox.shared.clearSnapshot()",
            source,
            "锁屏/休眠/暂停时必须归零而不是保留最后一帧",
        )


if __name__ == "__main__":
    unittest.main()
