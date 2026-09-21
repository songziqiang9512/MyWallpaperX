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
        inbox.setDemandObserver { observed.append($0.requiresSpectrum) }

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
        let staleCandidate = staleInbox.prepareFrame()
        let retryBeforeCommit = staleInbox.prepareFrame()
        staleInbox.commitFrame(staleCandidate)
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
            "staleCandidateIsSilent": staleCandidate.snapshot.isSilent,
            "staleCandidateSourceGeneration": staleCandidate.sourceGeneration,
            "staleRetrySourceGeneration": retryBeforeCommit.sourceGeneration,
            "staleRetryRemainsPending": retryBeforeCommit.expiresStalePublication,
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
        let bassOnly = analyzeFresh(
            signedChannels: [
                sineWave(frequency: 120, frameCount: frameCount, amplitude: 0.12)
            ],
            sampleRate: sampleRate
        )
        let bassOnlyQuiet = analyzeFresh(
            signedChannels: [
                sineWave(frequency: 120, frameCount: frameCount, amplitude: 0.06)
            ],
            sampleRate: sampleRate
        )
        let bassContinuityAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        var previousBass: [Float]?
        var bassUpperChangesLate = 0
        for frame in 0 ..< 96 {
            let amplitude = 0.06 + 0.05 * (0.5 + 0.5 * sin(
                Float(frame) * 2 * .pi / 24
            ))
            let levels = bassContinuityAnalyzer.analyze(
                signedChannels: [
                    sineWave(
                        frequency: 120,
                        frameCount: 1_600,
                        amplitude: amplitude,
                        startSample: frame * 1_600
                    )
                ],
                sampleRate: sampleRate
            )
            if frame >= 48, let previousBass,
               zip(levels.left.dropFirst(bandCount / 2), previousBass.dropFirst(bandCount / 2))
                    .contains(where: { abs($0 - $1) > 0.001 }) {
                bassUpperChangesLate += 1
            }
            previousBass = levels.left
        }
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

        let channelSwitchAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        _ = channelSwitchAnalyzer.analyze(
            signedChannels: [toneA, toneB],
            sampleRate: sampleRate
        )
        let monoAfterStereo = channelSwitchAnalyzer.analyze(
            signedChannels: [toneA],
            sampleRate: sampleRate
        )
        let freshMonoAfterStereo = analyzeFresh(
            signedChannels: [toneA],
            sampleRate: sampleRate
        )

        let changedSampleRate: Float = 44_100
        let changedRateTone = sineWave(
            frequency: 440,
            frameCount: frameCount,
            at: changedSampleRate
        )
        let rateSwitchAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        _ = rateSwitchAnalyzer.analyze(
            signedChannels: [toneB],
            sampleRate: sampleRate
        )
        let afterRateSwitch = rateSwitchAnalyzer.analyze(
            signedChannels: [changedRateTone],
            sampleRate: changedSampleRate
        )
        let freshChangedRate = analyzeFresh(
            signedChannels: [changedRateTone],
            sampleRate: changedSampleRate
        )

        let invalidRate = analyzeFresh(
            signedChannels: [toneA, toneB],
            sampleRate: 0
        )
        let empty = analyzeFresh(signedChannels: [], sampleRate: sampleRate)
        let highSampleRate: Float = 192_000
        let highRateTone = (0 ..< frameCount).map { index in
            sin(2 * .pi * 440 * Float(index) / highSampleRate) * 0.5
        }
        let highRate = analyzeFresh(
            signedChannels: [highRateTone],
            sampleRate: highSampleRate
        )

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

        let continuityAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        var previousContinuity: [Float]?
        var changedUpperBands = Set<Int>()
        var changedUpperBandsLate = Set<Int>()
        var lateConsecutiveShapeChanges = 0
        var continuityFirstBandPeak: Float = 0
        let partialFrameCount = 1_600
        for frame in 0 ..< 192 {
            let targetBand = 8 + (frame / 12) % 8
            let centerProgress = (Float(targetBand) + 0.5) / 16
            let frequency = 32 * pow(16_000 / 32, centerProgress)
            let input = sineWave(
                frequency: frequency,
                frameCount: partialFrameCount,
                amplitude: 0.12,
                startSample: frame * partialFrameCount
            ).map { $0 + 0.25 }
            let levels = continuityAnalyzer.analyze(
                signedChannels: [input],
                sampleRate: sampleRate
            )
            continuityFirstBandPeak = max(continuityFirstBandPeak, levels.left[0])
            if let previousContinuity {
                for index in 8 ..< 16
                where abs(levels.left[index] - previousContinuity[index]) > 0.001 {
                    changedUpperBands.insert(index)
                    if frame >= 96 {
                        changedUpperBandsLate.insert(index)
                    }
                }
                if frame >= 96,
                   zip(levels.left[8 ..< 16], previousContinuity[8 ..< 16])
                    .contains(where: { pair in abs(pair.0 - pair.1) > 0.001 }) {
                    lateConsecutiveShapeChanges += 1
                }
            }
            previousContinuity = levels.left
        }

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
            "bassOnlyUpperNonZero": bassOnly.left.dropFirst(bandCount / 2)
                .filter { $0 > 0 }.count,
            "bassOnlyUpperPeak": bassOnly.left.dropFirst(bandCount / 2).max() ?? 0,
            "bassOnlyQuietUpperPeak": bassOnlyQuiet.left
                .dropFirst(bandCount / 2).max() ?? 0,
            "bassUpperChangesLate": bassUpperChangesLate,
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
            "left16PeakMatches64Group": peakBand(stereo.left64) / 4
                == peakBand(stereo.left),
            "right16PeakMatches64Group": peakBand(stereo.right64) / 4
                == peakBand(stereo.right),
            "left32PeakMatches64Group": peakBand(stereo.left64) / 2
                == peakBand(stereo.left32),
            "right32PeakMatches64Group": peakBand(stereo.right64) / 2
                == peakBand(stereo.right32),
            "firstPartialSilent": firstPartial.left.allSatisfy { $0 == 0 },
            "secondPartialNonZero": secondPartial.left.contains { $0 > 0 },
            "changedUpperBandCount": changedUpperBands.count,
            "changedUpperBandCountLate": changedUpperBandsLate.count,
            "lateConsecutiveShapeChanges": lateConsecutiveShapeChanges,
            "continuityFirstBandPeak": continuityFirstBandPeak,
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
            "channelSwitchMatchesFresh": levelsEqual(
                monoAfterStereo,
                freshMonoAfterStereo
            ) && monoAfterStereo.left == monoAfterStereo.right
                && monoAfterStereo.left32 == monoAfterStereo.right32
                && monoAfterStereo.left64 == monoAfterStereo.right64,
            "sampleRateSwitchMatchesFresh": levelsEqual(
                afterRateSwitch,
                freshChangedRate
            ),
            "invalidRateLeft": invalidRate.left,
            "emptyLeft": empty.left,
            "highRateNonZero": highRate.left.contains { $0 > 0 },
            "sanitizedToneFinite": sanitizedTone.left.allSatisfy { $0.isFinite },
            "sanitizedTonePeakBand": peakBand(sanitizedTone.left),
            "biasedPeakBand": peakBand(biasedResult.left),
            "biasedFirstBand": biasedResult.left[0],
            "unbiasedFirstBand": stereo.left[0],
            "biasedToneDelta": meanAbsoluteDelta(biasedResult.left, stereo.left),
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
        amplitude: Float = 0.5,
        startSample: Int = 0,
        at sourceSampleRate: Float = Harness.sampleRate
    ) -> [Float] {
        (0 ..< frameCount).map { index in
            sin(
                2 * .pi * frequency * Float(startSample + index) / sourceSampleRate
            ) * amplitude
        }
    }

    static func levelsEqual(
        _ lhs: SystemAudioSceneSpectrumAnalyzer.Levels,
        _ rhs: SystemAudioSceneSpectrumAnalyzer.Levels
    ) -> Bool {
        lhs.left == rhs.left && lhs.right == rhs.right
            && lhs.left32 == rhs.left32 && lhs.right32 == rhs.right32
            && lhs.left64 == rhs.left64 && lhs.right64 == rhs.right64
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

    static func meanAbsoluteDelta(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        return zip(lhs, rhs).reduce(0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        } / Float(lhs.count)
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
        # 公开合同只要求低频到高频。Scene producer 以 32 Hz -> 16 kHz
        # 的对数边界把常见音乐频率分布到整个横轴，16/32/64 档都从
        # 同一 FFT 直接求值，不用会把能量压到左侧的 sqrt-like 私有映射。
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
        self.assertEqual(analyzer["stereoLeft64PeakBand"], 27)
        self.assertEqual(analyzer["stereoRight64PeakBand"], 52)
        self.assertEqual(analyzer["stereoLeft32PeakBand"], 13)
        self.assertEqual(analyzer["stereoRight32PeakBand"], 26)
        self.assertLess(
            analyzer["stereoLeftPeakBand"],
            analyzer["stereoRightPeakBand"],
        )

    def test_output_stays_positive_and_within_unit_range(self) -> None:
        self.assertTrue(self.result["analyzer"]["allWithinUnitRange"])

    def test_bass_dominant_input_keeps_the_upper_axis_active(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertGreaterEqual(
            analyzer["bassOnlyUpperNonZero"],
            8,
            "真实低频主导输入不能把右半频谱压成静态零值",
        )
        self.assertGreater(
            analyzer["bassOnlyUpperPeak"],
            0,
            "上半轴活动底必须来自同一帧的真实 broadband energy",
        )
        self.assertGreater(
            analyzer["bassOnlyUpperPeak"],
            analyzer["bassOnlyQuietUpperPeak"],
            "活动底必须随输入能量变化，不能用常数或随机抖动伪造动态",
        )
        self.assertGreater(
            analyzer["bassUpperChangesLate"],
            0,
            "长时低频主导输入下，上半轴也必须随真实能量持续更新",
        )

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
        self.assertEqual(analyzer["emptyLeft"], [0.0] * 16, "空输入必须归零")
        self.assertTrue(
            analyzer["highRateNonZero"],
            "高采样率分析窗必须有界截断，不能因超过FFT容量而让整链归零",
        )

    def test_non_finite_samples_do_not_corrupt_the_spectrum(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertTrue(analyzer["sanitizedToneFinite"])
        self.assertEqual(
            analyzer["sanitizedTonePeakBand"],
            6,
            "个别非有限采样被置零后，主频段判定仍应成立",
        )

    def test_dc_bias_is_removed_before_frequency_banding(self) -> None:
        analyzer = self.result["analyzer"]
        self.assertEqual(
            analyzer["biasedPeakBand"],
            6,
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
            analyzer["continuityFirstBandPeak"],
            0.30,
            "活动底必须有界，不能让第 0 柱重新吞掉整条频谱",
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
