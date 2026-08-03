#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Text/SceneDynamicTextGenerationState.swift"
STORE_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Text/SceneDynamicTextTextureStore.swift"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let authored = SceneDynamicTextSignature(
            content: "A", pointSize: 8, colorRGB: [1, 1, 1], maxWidth: 100
        )
        let second = SceneDynamicTextSignature(
            content: "B", pointSize: 9, colorRGB: [1, 0, 0], maxWidth: 200
        )
        let latest = SceneDynamicTextSignature(
            content: "C", pointSize: 10, colorRGB: [0, 1, 0], maxWidth: 300
        )
        var state = SceneDynamicTextGenerationState()
        state.registerInitial(layerID: 1, signature: authored, isReady: true)
        let initialReadyGeneration = state.readyGeneration(layerID: 1)
        let duplicate = state.request(layerID: 1, signature: authored)
        let generationB = state.request(layerID: 1, signature: second)!
        let generationC = state.request(layerID: 1, signature: latest)!
        let staleAccepted = state.complete(layerID: 1, generation: generationB, succeeded: true)
        let failureAccepted = state.complete(layerID: 1, generation: generationC, succeeded: false)
        let readyAfterFailure = state.readySignature(layerID: 1)!
        let generationAfterFailure = state.readyGeneration(layerID: 1)
        let latestAccepted = state.complete(layerID: 1, generation: generationC, succeeded: true)
        let readyAfterSuccess = state.readySignature(layerID: 1)!
        let generationAfterSuccess = state.readyGeneration(layerID: 1)

        var scheduledState = SceneDynamicTextGenerationState()
        scheduledState.registerInitial(layerID: 2, signature: authored, isReady: true)
        let scheduledSecond = scheduledState.schedule(layerID: 2, signature: second)!
        let queuedLatest = scheduledState.schedule(layerID: 2, signature: latest)
        let staleCompletion = scheduledState.finish(scheduledSecond, succeeded: true)
        let latestCompletion = scheduledState.finish(staleCompletion.next!, succeeded: true)
        state.reset()
        let payload: [String: Any] = [
            "duplicate": duplicate as Any,
            "initialReadyGeneration": initialReadyGeneration as Any,
            "ordered": generationC > generationB,
            "staleAccepted": staleAccepted,
            "failureAccepted": failureAccepted,
            "readyAfterFailure": readyAfterFailure.content,
            "generationAfterFailure": generationAfterFailure as Any,
            "latestAccepted": latestAccepted,
            "readyAfterSuccess": readyAfterSuccess.content,
            "generationAfterSuccess": generationAfterSuccess as Any,
            "queuedLatestStartedImmediately": queuedLatest != nil,
            "scheduledStaleAccepted": staleCompletion.accepted,
            "scheduledNextContent": staleCompletion.next?.signature.content as Any,
            "scheduledLatestAccepted": latestCompletion.accepted,
            "scheduledHasThirdTask": latestCompletion.next != nil,
            "scheduledReadyWidth": scheduledState.readySignature(layerID: 2)?.maxWidth as Any,
            "readyAfterReset": state.readySignature(layerID: 1) as Any,
            "generationAfterReset": state.readyGeneration(layerID: 1) as Any,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDynamicTextGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-text-generation-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "text-generation"
        compilation = subprocess.run(
            ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = json.loads(subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_same_value_is_deduplicated_and_generations_are_monotonic(self) -> None:
        self.assertIsNone(self.result["duplicate"])
        self.assertTrue(self.result["ordered"])

    def test_stale_or_failed_results_never_replace_the_last_ready_value(self) -> None:
        self.assertFalse(self.result["staleAccepted"])
        self.assertFalse(self.result["failureAccepted"])
        self.assertEqual(self.result["readyAfterFailure"], "A")
        self.assertEqual(
            self.result["generationAfterFailure"],
            self.result["initialReadyGeneration"],
        )
        self.assertTrue(self.result["latestAccepted"])
        self.assertEqual(self.result["readyAfterSuccess"], "C")
        self.assertGreater(
            self.result["generationAfterSuccess"],
            self.result["generationAfterFailure"],
        )
        self.assertIsNone(self.result["readyAfterReset"])
        self.assertIsNone(self.result["generationAfterReset"])

    def test_continuous_updates_keep_only_one_render_in_flight_and_then_latest(self) -> None:
        self.assertFalse(self.result["queuedLatestStartedImmediately"])
        # 单在途调度保证按 generation 完成；中间结果可安全发布，随后只追最新，
        # 避免连续 Timeline 因永远落后一帧而饿死。
        self.assertTrue(self.result["scheduledStaleAccepted"])
        self.assertEqual(self.result["scheduledNextContent"], "C")
        self.assertTrue(self.result["scheduledLatestAccepted"])
        self.assertFalse(self.result["scheduledHasThirdTask"])
        self.assertEqual(self.result["scheduledReadyWidth"], 300)

    def test_ready_texture_publication_declares_premultiplied_metadata(self) -> None:
        source = STORE_SOURCE.read_text(encoding="utf-8")
        for token in (
            "SceneTextureProviderPublication(",
            "requestIdentity: .layerSource(layerID)",
            "candidate: SceneTextureCandidate(",
            "identity: .provider(.dynamicText(layerID: layerID))",
            "generation: .provider(contentGeneration: generation)",
            "purpose: .premultipliedColor",
            "content: .color(.resolved(.premultipliedAlpha))",
        ):
            self.assertIn(token, source)


if __name__ == "__main__":
    unittest.main()
