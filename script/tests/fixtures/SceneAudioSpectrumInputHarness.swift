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
        let mirroredStereo = analyzeFresh(signedChannels: [toneA, toneA], sampleRate: sampleRate)

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
        let highRateTone = (0 ..< SystemAudioSceneSpectrumAnalyzer.analysisWindowCount(sampleRate: highSampleRate)).map { index in
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
            signedChannels: [sineWave(frequency: 440, frameCount: 3_096, startSample: 1_000)],
            sampleRate: sampleRate
        )

        let continuityAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        var previousContinuity: [Float]?
        var changedUpperBands = Set<Int>()
        var changedUpperBandsLate = Set<Int>()
        var lateConsecutiveShapeChanges = 0
        var continuityFirstBandRatio: Float = 0
        let partialFrameCount = 1_600
        var continuityPhase: Double = 0
        for frame in 0 ..< 192 {
            let targetBand = 8 + (frame / 12) % 8
            let centerProgress = (Float(targetBand) + 0.5) / 16
            let frequency = 32 * pow(16_000 / 32, centerProgress)
            // Keep phase continuous across frequency steps. Restarting phase
            // creates real broadband transients, not a DC-removal regression.
            let input = (0..<partialFrameCount).map { _ -> Float in
                continuityPhase += 2 * Double.pi * Double(frequency) / Double(sampleRate)
                return Float(0.12 * sin(continuityPhase)) + 0.25
            }
            let levels = continuityAnalyzer.analyze(
                signedChannels: [input],
                sampleRate: sampleRate
            )
            if let peak = levels.left.max(), peak > 0 {
                continuityFirstBandRatio = max(continuityFirstBandRatio, levels.left[0] / peak)
            }
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

        // A fixed spectral shape with a deterministic amplitude pulse is the
        // smallest producer-side rhythm probe. It must rise and fall with the
        // PCM envelope; this does not assert a private FFT constant or an
        // official beat detector.
        let rhythmAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        var rhythmPeaks: [Float] = []
        var rhythmBandCounts: [Int] = []
        let rhythmFrameCount = 1_600
        for frame in 0 ..< 96 {
            let pulse = 0.04 + 0.42 * (0.5 + 0.5 * sin(
                Float(frame) * 2 * .pi / 24
            ))
            let input = (0 ..< rhythmFrameCount).map { index in
                let sample = Float(frame * rhythmFrameCount + index)
                return pulse * (
                    0.42 * sin(2 * .pi * 110 * sample / sampleRate)
                    + 0.28 * sin(2 * .pi * 440 * sample / sampleRate)
                    + 0.18 * sin(2 * .pi * 2_200 * sample / sampleRate)
                    + 0.12 * sin(2 * .pi * 8_000 * sample / sampleRate)
                )
            }
            let levels = rhythmAnalyzer.analyze(
                signedChannels: [input],
                sampleRate: sampleRate
            )
            rhythmPeaks.append(levels.left64.max() ?? 0)
            rhythmBandCounts.append(levels.left64.filter { $0 > 0.03 }.count)
        }
        let rhythmFirstRise = rhythmPeaks.dropFirst(24).prefix(12).max() ?? 0
        let rhythmFirstFall = rhythmPeaks.dropFirst(36).prefix(12).min() ?? 0
        let rhythmSecondRise = rhythmPeaks.dropFirst(48).prefix(12).max() ?? 0
        let rhythmSecondFall = rhythmPeaks.dropFirst(60).prefix(12).min() ?? 0

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
            "bassOnlyPeak": bassOnly.left.max() ?? 0,
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
            "loudPeak": mono.left.max() ?? 0,
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
            "continuityFirstBandRatio": continuityFirstBandRatio,
            "rhythmFirstRise": rhythmFirstRise,
            "rhythmFirstFall": rhythmFirstFall,
            "rhythmSecondRise": rhythmSecondRise,
            "rhythmSecondFall": rhythmSecondFall,
            "rhythmPeakRange": (rhythmPeaks.max() ?? 0) - (rhythmPeaks.min() ?? 0),
            "rhythmBandCountRange": (rhythmBandCounts.max() ?? 0)
                - (rhythmBandCounts.min() ?? 0),
            "deterministic": repeated.left == stereo.left
                && repeated.right == stereo.right
                && repeated.left32 == stereo.left32
                && repeated.right32 == stereo.right32
                && repeated.left64 == stereo.left64
                && repeated.right64 == stereo.right64,
            "monoMirrors": mono.left == mono.right
                && mono.left32 == mono.right32
                && mono.left64 == mono.right64,
            "monoMatchesStereoLeft": mono.left == mirroredStereo.left
                && mono.left32 == mirroredStereo.left32
                && mono.left64 == mirroredStereo.left64,
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
            "unbiasedFirstBand": mono.left[0],
            "biasedToneDelta": meanAbsoluteDelta(biasedResult.left, mono.left),
            "allFinitePositive": (stereo.left + stereo.right)
                .allSatisfy { $0.isFinite && $0 >= 0 }
                && (stereo.left32 + stereo.right32)
                    .allSatisfy { $0.isFinite && $0 >= 0 }
                && (stereo.left64 + stereo.right64)
                    .allSatisfy { $0.isFinite && $0 >= 0 },
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
