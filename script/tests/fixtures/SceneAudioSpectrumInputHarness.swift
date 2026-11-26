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

    // MARK: - Author analysis

    typealias AuthorLevels = SystemAudioSceneSpectrumAnalyzer.AuthorLevels

    static func analyzerChecks() -> [String: Any] {
        let frameCount = SystemAudioSceneSpectrumAnalyzer.analysisWindowCount(sampleRate: sampleRate)
        let zero = Array(repeating: Float(0), count: frameCount)
        let centerTone = tone(275.730014, amplitude: 0.12)
        let halfTone = tone(287.218765, amplitude: 0.12)
        let highTone = tone(4_800, amplitude: 0.28)
        let centerFrame = captured([centerTone])
        let stereoFrame = captured([centerTone, highTone])

        let center = freshAuthor(centerFrame, sampleRate: sampleRate)
        let half = freshAuthor(captured([halfTone]), sampleRate: sampleRate)
        let dcFrame = captured([Array(repeating: 0.125, count: frameCount)])
        let dc = freshAuthor(dcFrame, sampleRate: sampleRate)
        let stereo = freshAuthor(stereoFrame, sampleRate: sampleRate)
        let hotAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        let hotFrame = captured([highTone, zero])
        _ = hotAnalyzer.analyzeAuthor(hotFrame, sampleRate: sampleRate, timestamp: 1)
        let hot = hotAnalyzer.analyzeAuthor(hotFrame, sampleRate: sampleRate, timestamp: 1.04)
        let silent = freshAuthor(captured([zero]), sampleRate: sampleRate)
        let nearSilentFrame = captured([tone(275.730014, amplitude: 0.000_001)])
        let nearSilent = freshAuthor(nearSilentFrame, sampleRate: sampleRate)

        let ignoredPrefix = Array(repeating: Float(0.8), count: frameCount - 1_392)
        let sameTail = captured([ignoredPrefix + Array(centerTone.suffix(1_392))])
        let incompleteTail = SystemAudioCapturedFrame(
            signedChannels: [Array(centerTone.suffix(1_391))]
        )
        let mirroredStereo = freshAuthor(captured([centerTone, centerTone]), sampleRate: sampleRate)

        let changedRate: Float = 44_100
        let changedFrame = captured([tone(275.730014, amplitude: 0.12, at: changedRate)], at: changedRate)
        let formatAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
        let first = formatAnalyzer.analyzeAuthor(stereoFrame, sampleRate: sampleRate, timestamp: 1)
        let stale = formatAnalyzer.analyzeAuthor(changedFrame, sampleRate: changedRate, timestamp: 0.95)
        let afterStale = formatAnalyzer.analyzeAuthor(stereoFrame, sampleRate: sampleRate, timestamp: 1.04)
        let uninterrupted = SystemAudioSceneSpectrumAnalyzer()!
        _ = uninterrupted.analyzeAuthor(stereoFrame, sampleRate: sampleRate, timestamp: 1)
        let expectedAfterStale = uninterrupted.analyzeAuthor(stereoFrame, sampleRate: sampleRate, timestamp: 1.04)
        let switched = formatAnalyzer.analyzeAuthor(changedFrame, sampleRate: changedRate, timestamp: 2)
        let returned = formatAnalyzer.analyzeAuthor(stereoFrame, sampleRate: sampleRate, timestamp: 3)
        let invalid = formatAnalyzer.analyzeAuthor(stereoFrame, sampleRate: 0, timestamp: 4)
        let afterInvalid = formatAnalyzer.analyzeAuthor(stereoFrame, sampleRate: sampleRate, timestamp: 5)

        let display = SystemAudioSceneSpectrumAnalyzer()!
        let displayReference = SystemAudioSceneSpectrumAnalyzer()!
        _ = display.analyze(stereoFrame, sampleRate: sampleRate, timestamp: 1)
        _ = displayReference.analyze(stereoFrame, sampleRate: sampleRate, timestamp: 1)
        _ = display.analyzeAuthor(stereoFrame, sampleRate: sampleRate, timestamp: 2)
        display.resetAuthor()
        let displayNext = display.analyze(stereoFrame, sampleRate: sampleRate, timestamp: 1.04)
        let displayExpected = displayReference.analyze(stereoFrame, sampleRate: sampleRate, timestamp: 1.04)
        let restartedAuthor = display.analyzeAuthor(stereoFrame, sampleRate: sampleRate, timestamp: 2)

        return [
            "center64": center.left64,
            "half64": half.left64,
            "dc64": dc.left64,
            "stereo": arrays(stereo),
            "hotPeak": hot.left64.max() ?? 0,
            "hotRightSilent": hot.right64.allSatisfy { $0 == 0 },
            "silent": arrays(silent).joined().allSatisfy { $0 == 0 },
            "nearSilentPeak": nearSilent.left64.max() ?? 0,
            "reentry": reentryChecks(active: dcFrame, quiet: nearSilentFrame),
            "sharedAttack": sharedAttackChecks(),
            "bandSteps": bandStepChecks(),
            "groupRelease": groupReleaseChecks(),
            "usesTail": arrays(freshAuthor(sameTail, sampleRate: sampleRate)) == arrays(center),
            "incompleteTailSilent": arrays(freshAuthor(incompleteTail, sampleRate: sampleRate))
                .joined().allSatisfy { $0 == 0 },
            "monoMirrors": center.left64 == center.right64 && center.left32 == center.right32 && center.left == center.right,
            "monoMatchesStereo": arrays(center) == arrays(mirroredStereo),
            "staleFormatPreservesCurrent": arrays(stale) == arrays(first)
                && arrays(afterStale) == arrays(expectedAfterStale),
            "newRateMatchesFresh": arrays(switched) == arrays(freshAuthor(changedFrame, sampleRate: changedRate)),
            "changedRate64": switched.left64,
            "returnTo48kMatchesFresh": arrays(returned) == arrays(stereo),
            "invalidRateSilent": arrays(invalid).joined().allSatisfy { $0 == 0 },
            "recoveryMatchesFresh": arrays(afterInvalid) == arrays(stereo),
            "authorResetMatchesFresh": arrays(restartedAuthor) == arrays(stereo),
            "authorResetPreservesDisplay": displayNext.left64 == displayExpected.left64
                && displayNext.right64 == displayExpected.right64,
        ]
    }

    static func captured(_ signedChannels: [[Float]], at sourceSampleRate: Float = sampleRate) -> SystemAudioCapturedFrame {
        SystemAudioSpectrumTestCapture.frame(signedChannels, sampleRate: sourceSampleRate)
    }

    static func freshAuthor(_ frame: SystemAudioCapturedFrame, sampleRate: Float) -> AuthorLevels {
        SystemAudioSceneSpectrumAnalyzer()!.analyzeAuthor(frame, sampleRate: sampleRate, timestamp: 1)
    }

    static func reentryChecks(active: SystemAudioCapturedFrame, quiet: SystemAudioCapturedFrame) -> [String: Float] {
        func restart(quietSeconds: Double, cadence: Int) -> Float {
            let analyzer = SystemAudioSceneSpectrumAnalyzer()!
            for tick in 0...90 {
                _ = analyzer.analyzeAuthor(active, sampleRate: sampleRate, timestamp: Double(tick) / 30)
            }
            for tick in 1...Int((quietSeconds * Double(cadence)).rounded()) {
                _ = analyzer.analyzeAuthor(quiet, sampleRate: sampleRate, timestamp: 3 + Double(tick) / Double(cadence))
            }
            let output = analyzer.analyzeAuthor(active, sampleRate: sampleRate, timestamp: 3 + quietSeconds + 1 / 30)
            return output.left64[0]
        }
        return [
            "short30": restart(quietSeconds: 0.2, cadence: 30),
            "long30": restart(quietSeconds: 0.7, cadence: 30),
            "long60": restart(quietSeconds: 0.7, cadence: 60),
            "fresh": freshAuthor(active, sampleRate: sampleRate).left64[0],
        ]
    }

    static func sharedAttackChecks() -> [[Float]] {
        let right = zip(
            tone(758.257539, amplitude: 0.03964522),
            tone(9_604.595500, amplitude: 0.00114217)
        ).map { reference, witness in reference + witness }
        let quiet = captured([tone(1_102.920057, amplitude: 0.03426054), right])
        let pressure = captured([tone(1_493.537578, amplitude: 0.36), right])
        let analyzer = SystemAudioSceneSpectrumAnalyzer()!
        func at(_ frame: SystemAudioCapturedFrame, tick: Int) -> [Float] {
            let bands = analyzer.analyzeAuthor(frame, sampleRate: sampleRate, timestamp: Double(tick) / 30)
            return [bands.right64[30], bands.right64[57]]
        }
        for tick in 0..<90 { _ = at(quiet, tick: tick) }
        let before = at(quiet, tick: 90)
        let attack = at(pressure, tick: 91)
        for tick in 92..<180 { _ = at(pressure, tick: tick) }
        return [before, attack, at(pressure, tick: 180)]
    }

    static func bandStepChecks() -> [[Float]] {
        let reference = tone(758.257539, amplitude: 0.03964522)
        let low = captured([tone(1_102.920057, amplitude: 0.03426054), reference])
        let high = captured([tone(1_493.537578, amplitude: 0.36), reference])
        let zero = Array(repeating: Float(0), count: reference.count)
        let silent = captured([zero, zero])

        return [1.0 / 60, 1.0 / 24].map { interval in
            let analyzer = SystemAudioSceneSpectrumAnalyzer()!
            func at(_ frame: SystemAudioCapturedFrame, _ time: Double) -> Float {
                analyzer.analyzeAuthor(frame, sampleRate: sampleRate, timestamp: time).left64[36]
            }
            for tick in 0..<90 { _ = at(low, Double(tick) / 30) }
            let before = at(low, 3)
            let first = at(high, 3 + interval)
            let repeatTime = at(high, 3 + interval)
            let second = at(high, 3 + 2 * interval)
            let release = at(low, 3 + 3 * interval)
            let quiet = at(silent, 3.3)
            let staleWhileQuiet = at(high, 3.3)
            for tick in 1...21 { _ = at(silent, 3.3 + Double(tick) / 30) }
            let resumed = at(high, 4.04)
            analyzer.resetAuthor()
            return [before, first, repeatTime, second, release, quiet, staleWhileQuiet, resumed, at(high, 4.08)]
        }
    }

    static func groupReleaseChecks() -> [[Float]] {
        func stepDown(_ peak: Float, intervals: [Double]) -> [Float] {
            let before = captured([tone(1_493.537578, amplitude: peak)])
            let after = captured([tone(1_493.537578, amplitude: peak / 2)])
            let analyzer = SystemAudioSceneSpectrumAnalyzer()!
            for tick in 0...75 {
                _ = analyzer.analyzeAuthor(before, sampleRate: sampleRate, timestamp: Double(tick) / 25)
            }
            var time = 3.0
            return intervals.map { interval in
                time += interval
                return analyzer.analyzeAuthor(after, sampleRate: sampleRate, timestamp: time).left64[36]
            }
        }
        let slowTicks = Array(repeating: 0.04, count: 20)
        let high = stepDown(0.048, intervals: slowTicks)
        let low = stepDown(0.012, intervals: slowTicks)
        let split = stepDown(0.012, intervals: [0.04, 0.04, 0.02, 0.02])
        return [high, low, [low[2], split[3]]]
    }

    static func tone(_ frequency: Double, amplitude: Float, at sourceSampleRate: Float = sampleRate) -> [Float] {
        let count = SystemAudioSceneSpectrumAnalyzer.analysisWindowCount(sampleRate: sourceSampleRate)
        return (0..<count).map { sample in
            amplitude * Float(sin(2 * .pi * frequency * Double(sample) / Double(sourceSampleRate)))
        }
    }

    static func arrays(_ levels: AuthorLevels) -> [[Float]] {
        [levels.left64, levels.right64, levels.left32, levels.right32, levels.left, levels.right]
    }
}
