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
DEBUG_FIXTURE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner+AudioSpectrum.swift"
)

HARNESS = r'''
import Foundation

final class TestUptimeClock: @unchecked Sendable {
    var now: TimeInterval = 0
}

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
        let mediumBandCount = SceneAudioSpectrumSnapshot.mediumBandCount
        let extendedBandCount = SceneAudioSpectrumSnapshot.extendedBandCount
        let valid = (0 ..< bandCount).map { Float($0) / Float(bandCount) }
        let valid32 = (0 ..< mediumBandCount).map {
            Float($0) / Float(mediumBandCount)
        }
        let valid64 = (0 ..< extendedBandCount).map {
            Float($0) / Float(extendedBandCount)
        }
        let accepted = SceneAudioSpectrumSnapshot(
            left: valid,
            right: valid,
            left32: valid32,
            right32: valid32,
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
            "mediumBandCount": mediumBandCount,
            "extendedBandCount": extendedBandCount,
            "acceptedLeft": accepted.left,
            "acceptedLeft32": accepted.left32,
            "acceptedLeft64": accepted.left64,
            "acceptedGeneration": accepted.generation,
            "acceptedIsSilent": accepted.isSilent,
            "shortInputLeft": shortInput.left,
            "shortInputRightUnchanged": shortInput.right == valid,
            "sanitizedLeft": sanitized.left,
            "silentIsSilent": SceneAudioSpectrumSnapshot.silent.isSilent,
            "silentGeneration": SceneAudioSpectrumSnapshot.silent.generation,
            "silentCount": SceneAudioSpectrumSnapshot.silent.left.count,
            "silentMediumCount": SceneAudioSpectrumSnapshot.silent.left32.count,
            "silentExtendedCount": SceneAudioSpectrumSnapshot.silent.left64.count,
        ]
    }

    // MARK: - Inbox

    static func inboxChecks() -> [String: Any] {
        let inbox = SceneAudioSpectrumInbox()
        let normalizedNoConsumerDemand = SceneAudioSpectrumCaptureDemand(
            requiresSpectrum: false, includesCurrentProcessOutput: true
        )
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
        let ones32 = Array(
            repeating: Float(0.625),
            count: SceneAudioSpectrumSnapshot.mediumBandCount
        )
        let twos32 = Array(
            repeating: Float(0.875),
            count: SceneAudioSpectrumSnapshot.mediumBandCount
        )

        var observed: [Bool] = []
        inbox.setDemandObserver { observed.append($0) }

        let initial = inbox.latest()
        inbox.publish(
            left: ones,
            right: twos,
            left32: ones32,
            right32: twos32,
            left64: ones64,
            right64: twos64
        )
        let first = inbox.latest()
        inbox.publish(left: twos, right: ones)
        let second = inbox.latest()

        let demandedBefore = inbox.isDemanded
        inbox.setDemand(true)
        let demandedAfter = inbox.isDemanded
        inbox.setDemand(true) // 重复设置不应再次通知
        inbox.publish(left: ones, right: ones)
        let beforeScopeChange = inbox.latest()
        inbox.setDemand(true, requiresCurrentProcessAudioCapture: true)
        let scopedDemand = inbox.captureDemand
        let afterScopeChange = inbox.latest()
        let notificationsAfterScopeChange = observed.count
        inbox.setDemand(true, requiresCurrentProcessAudioCapture: true)
        let duplicatePolicyWasQuiet = observed.count == notificationsAfterScopeChange
        inbox.publish(left: ones, right: ones)
        let beforeRevoke = inbox.latest()
        inbox.setDemand(false, requiresCurrentProcessAudioCapture: true)
        let afterRevoke = inbox.latest()

        inbox.publish(left: twos, right: twos)
        let generationBeforeReset = inbox.latest().generation
        inbox.setDemand(true, requiresCurrentProcessAudioCapture: true)
        inbox.reset()
        let afterReset = inbox.latest()

        let staleClock = TestUptimeClock()
        let staleInbox = SceneAudioSpectrumInbox(uptime: { staleClock.now })
        staleInbox.setDemand(true)
        staleClock.now = 10
        staleInbox.publish(
            left: ones,
            right: twos,
            left32: ones32,
            right32: twos32,
            left64: ones64,
            right64: twos64
        )
        staleClock.now += 0.25
        let beforeDeadline = staleInbox.latest()
        staleClock.now += 0.02
        let afterDeadline = staleInbox.latest()

        return [
            "initialIsSilent": initial.isSilent,
            "initialGeneration": initial.generation,
            "firstLeft": first.left,
            "firstRight": first.right,
            "firstLeft32": first.left32,
            "firstRight32": first.right32,
            "firstLeft64": first.left64,
            "firstRight64": first.right64,
            "firstGeneration": first.generation,
            "secondGeneration": second.generation,
            "demandedBefore": demandedBefore,
            "demandedAfter": demandedAfter,
            "noConsumerIncludeNormalizesToNone": normalizedNoConsumerDemand == .none,
            "scopeChangeClearsSnapshot": !beforeScopeChange.isSilent && afterScopeChange.isSilent,
            "scopeChangePublishesAtomically": scopedDemand.requiresSpectrum
                && scopedDemand.includesCurrentProcessOutput,
            "policyChangeNotifiesOnce": notificationsAfterScopeChange == 2
                && duplicatePolicyWasQuiet,
            "observed": observed,
            "beforeRevokeIsSilent": beforeRevoke.isSilent,
            "afterRevokeIsSilent": afterRevoke.isSilent,
            "afterRevokeDemanded": inbox.isDemanded,
            "generationBeforeReset": generationBeforeReset,
            "afterResetGeneration": afterReset.generation,
            "afterResetIsSilent": afterReset.isSilent,
            "afterResetDemandIsNone": !inbox.captureDemand.requiresSpectrum && !inbox.captureDemand.includesCurrentProcessOutput,
            "beforeStaleDeadlineIsSilent": beforeDeadline.isSilent,
            "afterStaleDeadlineIsSilent": afterDeadline.isSilent,
            "staleRevocationGeneration": afterDeadline.generation,
        ]
    }

    // MARK: - Analyzer

    static func analyzerChecks() -> [String: Any] {
        guard SystemAudioSceneSpectrumAnalyzer() != nil else {
            return ["available": false]
        }
        let bandCount = SystemAudioSceneSpectrumAnalyzer.bandCount
        let frameCount = 4_096

        let silence = Array(repeating: Float(0), count: frameCount)
        let silent = analyzeFresh(
            signedChannels: [silence, silence],
            sampleRate: sampleRate
        )

        let toneA = sineWave(frequency: 440, frameCount: frameCount)
        let toneB = sineWave(frequency: 5_000, frameCount: frameCount)
        let quietToneA = sineWave(
            frequency: 440,
            frameCount: frameCount,
            amplitude: 0.05
        )
        let noiseFloorTone = sineWave(
            frequency: 440,
            frameCount: frameCount,
            amplitude: 0.002
        )
        let stereo = analyzeFresh(
            signedChannels: [toneA, toneB],
            sampleRate: sampleRate
        )
        let quiet = analyzeFresh(
            signedChannels: [quietToneA],
            sampleRate: sampleRate
        )
        let noiseFloor = analyzeFresh(
            signedChannels: [noiseFloorTone],
            sampleRate: sampleRate
        )
        let repeated = analyzeFresh(
            signedChannels: [toneA, toneB],
            sampleRate: sampleRate
        )
        let mono = analyzeFresh(signedChannels: [toneA], sampleRate: sampleRate)

        let invalidRate = analyzeFresh(
            signedChannels: [toneA, toneB],
            sampleRate: 0
        )
        let empty = analyzeFresh(signedChannels: [], sampleRate: sampleRate)

        var withNaN = toneA
        withNaN[10] = .nan
        withNaN[11] = .infinity
        let sanitizedTone = analyzeFresh(
            signedChannels: [withNaN],
            sampleRate: sampleRate
        )

        // 直流偏置不应把能量堆到最低频段。
        let biased = toneA.map { $0 + 0.5 }
        let biasedResult = analyzeFresh(
            signedChannels: [biased],
            sampleRate: sampleRate
        )

        let envelopeAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        let attackFirst = envelopeAnalyzer.analyze(
            signedChannels: [toneA],
            sampleRate: sampleRate
        )
        let attackSecond = envelopeAnalyzer.analyze(
            signedChannels: [toneA],
            sampleRate: sampleRate
        )
        let releaseFirst = envelopeAnalyzer.analyze(
            signedChannels: [silence],
            sampleRate: sampleRate
        )
        let releaseSecond = envelopeAnalyzer.analyze(
            signedChannels: [silence],
            sampleRate: sampleRate
        )

        let primingAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        let firstPartial = primingAnalyzer.analyze(
            signedChannels: [sineWave(frequency: 440, frameCount: 1_000)],
            sampleRate: sampleRate
        )
        let secondPartial = primingAnalyzer.analyze(
            signedChannels: [sineWave(frequency: 440, frameCount: 1_200)],
            sampleRate: sampleRate
        )

        return [
            "available": true,
            "bandCount": bandCount,
            "extendedBandCount": SystemAudioSceneSpectrumAnalyzer.extendedBandCount,
            "mediumBandCount": SystemAudioSceneSpectrumAnalyzer.mediumBandCount,
            "silentLeft": silent.left,
            "silentRight": silent.right,
            "stereoLeft": stereo.left,
            "stereoRight": stereo.right,
            "stereoLeft64": stereo.left64,
            "stereoRight64": stereo.right64,
            "stereoLeft32": stereo.left32,
            "stereoRight32": stereo.right32,
            "stereoLeftPeakBand": peakBand(stereo.left),
            "stereoRightPeakBand": peakBand(stereo.right),
            "stereoLeft64PeakBand": peakBand(stereo.left64),
            "stereoRight64PeakBand": peakBand(stereo.right64),
            "stereoLeft32PeakBand": peakBand(stereo.left32),
            "stereoRight32PeakBand": peakBand(stereo.right32),
            "loudPeak": stereo.left.max() ?? 0,
            "quietPeak": quiet.left.max() ?? 0,
            "noiseFloorPeak": noiseFloor.left.max() ?? 0,
            "attackFirstPeak": attackFirst.left64.max() ?? 0,
            "attackSecondPeak": attackSecond.left64.max() ?? 0,
            "releaseFirstPeak": releaseFirst.left64.max() ?? 0,
            "releaseSecondPeak": releaseSecond.left64.max() ?? 0,
            "left16DerivedFrom64": averageResample(stereo.left64, count: 16)
                == stereo.left,
            "left32DerivedFrom64": averageResample(stereo.left64, count: 32)
                == stereo.left32,
            "firstPartialSilent": firstPartial.left.allSatisfy { $0 == 0 },
            "secondPartialNonZero": secondPartial.left.contains { $0 > 0 },
            "deterministic": repeated.left == stereo.left
                && repeated.right == stereo.right
                && repeated.left32 == stereo.left32
                && repeated.right32 == stereo.right32
                && repeated.left64 == stereo.left64
                && repeated.right64 == stereo.right64,
            "monoMirrors": mono.left == mono.right
                && mono.left32 == mono.right32
                && mono.left64 == mono.right64,
            "monoMatchesStereoLeft": mono.left == stereo.left
                && mono.left32 == stereo.left32
                && mono.left64 == stereo.left64,
            "invalidRateLeft": invalidRate.left,
            "emptyLeft": empty.left,
            "sanitizedToneFinite": sanitizedTone.left.allSatisfy { $0.isFinite },
            "sanitizedTonePeakBand": peakBand(sanitizedTone.left),
            "biasedPeakBand": peakBand(biasedResult.left),
            "allWithinUnitRange": (stereo.left + stereo.right)
                .allSatisfy { $0 >= 0 && $0 <= 1 }
                && (stereo.left32 + stereo.right32)
                    .allSatisfy { $0 >= 0 && $0 <= 1 }
                && (stereo.left64 + stereo.right64)
                    .allSatisfy { $0 >= 0 && $0 <= 1 },
        ]
    }

    static func analyzeFresh(
        signedChannels: [[Float]],
        sampleRate: Float
    ) -> SystemAudioSceneSpectrumAnalyzer.Levels {
        SystemAudioSceneSpectrumAnalyzer()!.analyze(
            signedChannels: signedChannels,
            sampleRate: sampleRate
        )
    }

    static func sineWave(
        frequency: Float,
        frameCount: Int,
        amplitude: Float = 0.5
    ) -> [Float] {
        (0 ..< frameCount).map { index in
            sin(2 * .pi * frequency * Float(index) / sampleRate) * amplitude
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

    static func averageResample(_ values: [Float], count: Int) -> [Float] {
        let stride = values.count / count
        return (0 ..< count).map { outputIndex in
            let start = outputIndex * stride
            return values[start ..< start + stride].reduce(0, +) / Float(stride)
        }
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
        self.assertTrue(analyzer["left16DerivedFrom64"])

    def test_analyzer_emits_thirty_two_bands_from_the_same_fft(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(analyzer["mediumBandCount"], 32)
        self.assertEqual(len(analyzer["stereoLeft32"]), 32)
        self.assertEqual(len(analyzer["stereoRight32"]), 32)
        self.assertLess(
            analyzer["stereoLeft32PeakBand"],
            analyzer["stereoRight32PeakBand"],
        )
        self.assertTrue(analyzer["left32DerivedFrom64"])

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
        # 官方 producer 先以 sqrt-like 曲线映射到 64 档，再对相邻档求平均：
        # 440 Hz 落在 64 档的 10（投影后 16 档的 2），5 kHz 落在 64 档的 37
        #（投影后 16 档的 9）。这同时锁住 producer 与投影方向。
        self.assertEqual(
            analyzer["stereoLeftPeakBand"],
            2,
            "440 Hz 必须落在官方 64-to-16 投影下的第 2 段",
        )
        self.assertEqual(
            analyzer["stereoRightPeakBand"],
            9,
            "5 kHz 必须落在更高频段，证明频段顺序由低到高",
        )
        self.assertEqual(analyzer["stereoLeft64PeakBand"], 10)
        self.assertEqual(analyzer["stereoRight64PeakBand"], 37)
        self.assertEqual(analyzer["stereoLeft32PeakBand"], 5)
        self.assertEqual(analyzer["stereoRight32PeakBand"], 18)
        self.assertLess(
            analyzer["stereoLeftPeakBand"],
            analyzer["stereoRightPeakBand"],
        )

    def test_output_stays_positive_and_within_unit_range(self) -> None:
        self.assertTrue(self.result["analyzer"]["allWithinUnitRange"])

    def test_scene_dynamic_range_separates_quiet_and_loud_bands(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertGreater(analyzer["loudPeak"], analyzer["quietPeak"])
        self.assertGreater(
            analyzer["loudPeak"],
            0.31,
            "正常 PCM 必须经过项目既有根压缩进入作者 shader 的可见高度区间",
        )
        self.assertGreater(
            analyzer["quietPeak"],
            0.05,
            "普通弱音必须经过可视响应后仍能驱动作者波形，不能缩成不可见细线",
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

    def test_first_partial_window_fails_closed_until_primed(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(analyzer["firstPartialSilent"])
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
            2,
            "个别非有限采样被置零后，主频段判定仍应成立",
        )

    def test_dc_bias_remains_finite_and_bounded(self) -> None:
        self.assertEqual(
            self.result["analyzer"]["biasedPeakBand"],
            0,
            "官方 producer 跳过 DC bin，但不私自减均值；偏置应落在最低可见档",
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
        self.assertRegex(
            source,
            r"(?s)let requestedProcessScope: ProcessScope = sceneEnabled.*?"
            r"case \.includesCurrentProcess:\s*excludedProcessIDs = \[\]\s*"
            r"case \.excludesCurrentProcess:.*?throw .*?currentProcessUnavailable.*?"
            r"excludedProcessIDs = \[currentProcessObjectID\]",
        )
        scope_start = source.index("if processScopeChanged {")
        stop = source.index("self.stopCapture()", scope_start)
        reconcile = source.index("self.reconcileCaptureState()", stop)
        self.assertLess(stop, reconcile)
        self.assertRegex(source, r"(?s)private func reconcileCaptureState\(\).*?startCaptureIfNeeded\(\)")

    def test_service_clears_scene_levels_on_stop_and_failure(self) -> None:
        source = SERVICE_SOURCE.read_text(encoding="utf-8")
        self.assertGreaterEqual(
            source.count("clearSceneLevels()"),
            5,
            "消费者切换、采集停止、FFT 不可用与采集失败都必须调用统一归零入口",
        )
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

    def test_engine_routes_scene_levels_into_the_inbox(self) -> None:
        source = ENGINE_SPECTRUM_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "left64: left64",
            source,
        )
        self.assertIn("left32: left32", source)
        self.assertEqual(
            source.count("SceneAudioSpectrumInbox.shared.captureDemand"),
            1,
            "consumer 与 capture scope 必须由同一次原子快照读取",
        )
        self.assertIn("sceneEnabled: sceneCaptureRequested", source)
        self.assertEqual(source.count("includeCurrentProcessAudio:"), 1)
        self.assertIn("sceneCaptureScopeEpoch: sceneDemand.scopeEpoch", source)

    def test_debug_fixture_exclusively_owns_the_scene_inbox(self) -> None:
        source = ENGINE_SPECTRUM_SOURCE.read_text(encoding="utf-8")
        self.assertIn("debugSceneFixtureOwnsInbox", source)
        self.assertIn('"--mwx-debug-scene-audio-spectrum-fixture"', source)
        self.assertIn('"--mwx-debug-scene-audio-silence-fixture"', source)
        self.assertIn("&& !debugSceneFixtureOwnsInbox", source)
        fixture = DEBUG_FIXTURE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("MWX DEBUG SCENE AUDIO: mode=silence", fixture)
        self.assertIn("SceneAudioSpectrumInbox.shared.clearSnapshot()", fixture)

    def test_engine_stops_scene_capture_under_system_interruptions(self) -> None:
        source = ENGINE_SPECTRUM_SOURCE.read_text(encoding="utf-8")
        self.assertRegex(
            source,
            r"let sceneCaptureRequested = captureAllowed\s*"
            r"&& sceneDemand\.requiresSpectrum",
        )
        service = SERVICE_SOURCE.read_text(encoding="utf-8")
        self.assertRegex(
            service,
            r"if self\.sceneEnabled != sceneEnabled \{\s*"
            r"self\.clearSceneLevels\(\)",
            "锁屏/休眠/暂停撤销 Scene consumer 时必须由唯一 service 归零",
        )


if __name__ == "__main__":
    unittest.main()
