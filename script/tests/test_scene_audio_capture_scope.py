#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneAudioSpectrum.swift"

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
        var observations: [Bool] = []
        inbox.setDemandObserver { observations.append($0) }

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

        let notificationsBeforeDuplicate = observations.count
        inbox.setDemand(true, requiresCurrentProcessAudioCapture: false)
        let duplicateWasQuiet = observations.count == notificationsBeforeDuplicate
            && inbox.captureDemand.scopeEpoch == secondExcludeDemand.scopeEpoch
        inbox.setDemand(false)
        publish(inbox, token: secondExcludeToken)
        let undemandedRejected = inbox.latest()

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
            "acceptedGenerations": [
                excludeAccepted.generation,
                includeAccepted.generation,
                secondExcludeAccepted.generation,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
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
        ):
            self.assertTrue(self.payload[key], key)

    def test_scope_epoch_advances_but_duplicate_policy_is_quiet(self) -> None:
        self.assertTrue(self.payload["includeEpochAdvanced"])
        self.assertTrue(self.payload["excludeEpochAdvancedAgain"])
        self.assertTrue(self.payload["duplicateWasQuiet"])

    def test_rejected_tokens_do_not_consume_snapshot_generations(self) -> None:
        self.assertEqual(self.payload["acceptedGenerations"], [1, 2, 3])


if __name__ == "__main__":
    unittest.main()
