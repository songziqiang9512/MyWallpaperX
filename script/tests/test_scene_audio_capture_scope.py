#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift"

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let bands = Array(
        repeating: Float(0.5),
        count: SceneAudioSpectrumSnapshot.bandCount
    )
    static let bands32 = Array(
        repeating: Float(0.5),
        count: SceneAudioSpectrumSnapshot.mediumBandCount
    )
    static let bands64 = Array(
        repeating: Float(0.5),
        count: SceneAudioSpectrumSnapshot.extendedBandCount
    )

    static func publish(
        _ inbox: SceneAudioSpectrumInbox,
        token: SceneAudioSpectrumCaptureToken
    ) {
        inbox.publishSystemCapture(
            left: bands,
            right: bands,
            left32: bands32,
            right32: bands32,
            left64: bands64,
            right64: bands64,
            token: token
        )
    }

    static func main() throws {
        let inbox = SceneAudioSpectrumInbox()
        var observedRequiresSpectrum: [Bool] = []
        var observedIncludesCurrentProcess: [Bool] = []
        var observedScopeEpochs: [UInt64] = []
        inbox.setDemandObserver { demand in
            observedRequiresSpectrum.append(demand.requiresSpectrum)
            observedIncludesCurrentProcess.append(
                demand.includesCurrentProcessOutput
            )
            observedScopeEpochs.append(demand.scopeEpoch)
        }

        inbox.setDemand(true)
        let excludeDemand = inbox.captureDemand
        let excludeToken = SceneAudioSpectrumCaptureToken(
            scopeEpoch: excludeDemand.scopeEpoch,
            includesCurrentProcessOutput: false
        )
        publish(inbox, token: excludeToken)
        let excludeAccepted = inbox.latest()

        inbox.setDemand(true, requiresCurrentProcessAudioCapture: true)
        let includeDemand = inbox.captureDemand
        let clearedForInclude = inbox.latest()
        publish(inbox, token: excludeToken)
        let staleExcludeRejected = inbox.latest()
        let includeToken = SceneAudioSpectrumCaptureToken(
            scopeEpoch: includeDemand.scopeEpoch,
            includesCurrentProcessOutput: true
        )
        publish(inbox, token: includeToken)
        let includeAccepted = inbox.latest()

        inbox.setDemand(true, requiresCurrentProcessAudioCapture: false)
        let secondExcludeDemand = inbox.captureDemand
        let clearedForExclude = inbox.latest()
        publish(inbox, token: includeToken)
        let staleIncludeRejected = inbox.latest()
        let secondExcludeToken = SceneAudioSpectrumCaptureToken(
            scopeEpoch: secondExcludeDemand.scopeEpoch,
            includesCurrentProcessOutput: false
        )
        publish(inbox, token: secondExcludeToken)
        let secondExcludeAccepted = inbox.latest()

        let notificationsBeforeDuplicate = observedRequiresSpectrum.count
        inbox.setDemand(true, requiresCurrentProcessAudioCapture: false)
        let duplicateWasQuiet = observedRequiresSpectrum.count
            == notificationsBeforeDuplicate
            && inbox.captureDemand.scopeEpoch == secondExcludeDemand.scopeEpoch
        inbox.setDemand(false)
        publish(inbox, token: secondExcludeToken)
        let undemandedRejected = inbox.latest()

        inbox.setDemand(true, requiresCurrentProcessAudioCapture: false)
        let reenabledDemand = inbox.captureDemand
        let reenabledCleared = inbox.latest()
        publish(inbox, token: secondExcludeToken)
        let staleAfterReenableRejected = inbox.latest()
        let reenabledToken = SceneAudioSpectrumCaptureToken(
            scopeEpoch: reenabledDemand.scopeEpoch,
            includesCurrentProcessOutput: false
        )
        publish(inbox, token: reenabledToken)
        let reenabledAccepted = inbox.latest()

        let payload: [String: Any] = [
            "excludeAccepted": !excludeAccepted.isSilent,
            "includeEpochAdvanced": includeDemand.scopeEpoch > excludeDemand.scopeEpoch,
            "clearedForInclude": clearedForInclude.isSilent,
            "staleExcludeRejected": staleExcludeRejected.isSilent,
            "includeAccepted": !includeAccepted.isSilent,
            "excludeEpochAdvancedAgain":
                secondExcludeDemand.scopeEpoch > includeDemand.scopeEpoch,
            "clearedForExclude": clearedForExclude.isSilent,
            "staleIncludeRejected": staleIncludeRejected.isSilent,
            "secondExcludeAccepted": !secondExcludeAccepted.isSilent,
            "duplicateWasQuiet": duplicateWasQuiet,
            "undemandedRejected": undemandedRejected.isSilent,
            "reenableEpochAdvanced":
                reenabledDemand.scopeEpoch > secondExcludeDemand.scopeEpoch,
            "reenabledCleared": reenabledCleared.isSilent,
            "staleAfterReenableRejected": staleAfterReenableRejected.isSilent,
            "reenabledAccepted": !reenabledAccepted.isSilent,
            "acceptedGenerations": [
                excludeAccepted.generation,
                includeAccepted.generation,
                secondExcludeAccepted.generation,
            ],
            "observedRequiresSpectrum": observedRequiresSpectrum,
            "observedIncludesCurrentProcess": observedIncludesCurrentProcess,
            "observedScopeEpochs": observedScopeEpochs,
            "routing": routingChecks(),
            "latestHandoff": latestHandoffChecks(),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func routingChecks() -> [String: Bool] {
        let localDemand = SceneAudioSpectrumCaptureDemand(
            requiresSpectrum: true,
            includesCurrentProcessOutput: true,
            scopeEpoch: 11
        )
        let daemonDemand = SceneAudioSpectrumCaptureDemand(
            requiresSpectrum: true,
            includesCurrentProcessOutput: true,
            scopeEpoch: 21
        )
        let daemonRoute = SceneAudioSpectrumCaptureRoutingState.resolvedRoute(
            captureAllowed: true,
            debugFixtureOwnsInbox: false,
            localDemand: localDemand,
            daemonDemand: daemonDemand,
            daemonGeneration: 7
        )
        var state = SceneAudioSpectrumCaptureRoutingState()
        let firstChanged = state.update(route: daemonRoute)
        let firstEpoch = state.scopeEpoch
        let matchingToken = SceneAudioSpectrumCaptureToken(
            scopeEpoch: firstEpoch,
            includesCurrentProcessOutput: false
        )
        let matchingTokenAccepted = firstChanged
            && state.accepts(matchingToken)
        let duplicateWasQuiet = !state.update(route: daemonRoute)
            && state.scopeEpoch == firstEpoch
        let replacementRoute = SceneAudioSpectrumCaptureRoute.daemon(
            daemonDemand,
            generation: 8
        )
        let generationAdvanced = state.update(route: replacementRoute)
            && state.scopeEpoch > firstEpoch
            && !state.accepts(matchingToken)
        let localRoute = SceneAudioSpectrumCaptureRoutingState.resolvedRoute(
            captureAllowed: true,
            debugFixtureOwnsInbox: false,
            localDemand: localDemand,
            daemonDemand: .none,
            daemonGeneration: nil
        )
        let localScope = localRoute.includesCaptureProcessOutput
        let blockedRoute = SceneAudioSpectrumCaptureRoutingState.resolvedRoute(
            captureAllowed: false,
            debugFixtureOwnsInbox: false,
            localDemand: localDemand,
            daemonDemand: daemonDemand,
            daemonGeneration: 8
        )
        let fixtureRoute = SceneAudioSpectrumCaptureRoutingState.resolvedRoute(
            captureAllowed: true,
            debugFixtureOwnsInbox: true,
            localDemand: localDemand,
            daemonDemand: daemonDemand,
            daemonGeneration: 8
        )
        return [
            "daemonPreemptsLocal": daemonRoute == .daemon(
                daemonDemand,
                generation: 7
            ),
            "daemonTapExcludesApp": !daemonRoute.includesCaptureProcessOutput,
            "matchingTokenAccepted": matchingTokenAccepted,
            "duplicateWasQuiet": duplicateWasQuiet,
            "generationRejectsStale": generationAdvanced,
            "localIncludesCaptureProcess": localScope,
            "interruptionDisablesRoute": blockedRoute == .none,
            "fixtureDisablesSystemRoute": fixtureRoute == .none,
        ]
    }

    static func latestHandoffChecks() -> [String: Bool] {
        let handoff = LatestValueHandoff<Int>()
        var scheduledDrainCount = 0
        handoff.submit(1) { scheduledDrainCount += 1 }
        handoff.submit(2) { scheduledDrainCount += 1 }
        let firstLatest = handoff.takeLatest()
        handoff.submit(3) { scheduledDrainCount += 1 }
        handoff.discardPendingValue()
        handoff.submit(4) { scheduledDrainCount += 1 }
        let replacementLatest = handoff.takeLatest()
        return [
            "oneWakeupPerPendingDrain": scheduledDrainCount == 2,
            "latestReplacesOlderValue": firstLatest == 2,
            "invalidationKeepsWakeupForReplacement": replacementLatest == 4,
        ]
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneAudioCaptureScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-audio-capture-scope-"
        )
        temporary = Path(cls.temporary_directory.name)
        harness = temporary / "Harness.swift"
        binary = temporary / "scene-audio-capture-scope"
        harness.write_text(HARNESS, encoding="utf-8")
        subprocess.run(
            [shutil.which("swiftc"), str(SOURCE), str(harness), "-o", str(binary)],
            cwd=ROOT,
            check=True,
        )
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.payload = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_only_matching_applied_scope_tokens_publish(self) -> None:
        for key in (
            "excludeAccepted",
            "clearedForInclude",
            "staleExcludeRejected",
            "includeAccepted",
            "clearedForExclude",
            "staleIncludeRejected",
            "secondExcludeAccepted",
            "undemandedRejected",
            "reenabledCleared",
            "staleAfterReenableRejected",
            "reenabledAccepted",
        ):
            self.assertTrue(self.payload[key], key)

    def test_scope_epoch_advances_but_duplicate_policy_is_quiet(self) -> None:
        self.assertTrue(self.payload["includeEpochAdvanced"])
        self.assertTrue(self.payload["excludeEpochAdvancedAgain"])
        self.assertTrue(self.payload["duplicateWasQuiet"])
        self.assertTrue(self.payload["reenableEpochAdvanced"])

    def test_rejected_tokens_do_not_consume_snapshot_generations(self) -> None:
        self.assertEqual(self.payload["acceptedGenerations"], [1, 2, 3])

    def test_observer_publishes_complete_demand_identity(self) -> None:
        self.assertEqual(
            self.payload["observedRequiresSpectrum"],
            [True, True, True, False, True],
        )
        self.assertEqual(
            self.payload["observedIncludesCurrentProcess"],
            [False, True, False, False, False],
        )
        epochs = self.payload["observedScopeEpochs"]
        self.assertEqual(len(epochs), 5)
        self.assertTrue(all(
            current > previous
            for previous, current in zip(epochs, epochs[1:])
        ))

    def test_daemon_route_preempts_local_and_translates_process_scope(self) -> None:
        routing = self.payload["routing"]
        for key in (
            "daemonPreemptsLocal",
            "daemonTapExcludesApp",
            "localIncludesCaptureProcess",
        ):
            self.assertTrue(routing[key], key)

    def test_route_epoch_rejects_replaced_daemon_generation(self) -> None:
        routing = self.payload["routing"]
        for key in (
            "matchingTokenAccepted",
            "duplicateWasQuiet",
            "generationRejectsStale",
        ):
            self.assertTrue(routing[key], key)

    def test_interruptions_and_debug_fixture_disable_system_route(self) -> None:
        routing = self.payload["routing"]
        self.assertTrue(routing["interruptionDisablesRoute"])
        self.assertTrue(routing["fixtureDisablesSystemRoute"])

    def test_latest_handoff_bounds_each_capture_to_main_queue(self) -> None:
        self.assertTrue(all(self.payload["latestHandoff"].values()))


if __name__ == "__main__":
    unittest.main()
