#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
POLICY_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureResidentBudgetPolicy.swift"
)
POOL_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTexturePool.swift"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let mibibyte = 1_024 * 1_024
        let oldBudget = 397_284_864
        let requiredBytes = 411_292_672
        let measuredRecommendedWorkingSet = UInt64(oldBudget) * 32
        let result: [String: Any] = [
            "floor": SceneOffscreenTextureResidentBudgetPolicy.automatic(
                recommendedMaxWorkingSetSize: 0
            ),
            "middle": SceneOffscreenTextureResidentBudgetPolicy.automatic(
                recommendedMaxWorkingSetSize: UInt64(8) * 1_024 * 1_024 * 1_024
            ),
            "measuredDevice": SceneOffscreenTextureResidentBudgetPolicy.automatic(
                recommendedMaxWorkingSetSize: measuredRecommendedWorkingSet
            ),
            "ceiling": SceneOffscreenTextureResidentBudgetPolicy.automatic(
                recommendedMaxWorkingSetSize: UInt64(32) * 1_024 * 1_024 * 1_024
            ),
            "overflowSafeCeiling": SceneOffscreenTextureResidentBudgetPolicy.automatic(
                recommendedMaxWorkingSetSize: UInt64.max
            ),
            "floorExpected": 192 * mibibyte,
            "middleExpected": 512 * mibibyte,
            "measuredExpected": 794_569_728,
            "ceilingExpected": 1_536 * mibibyte,
            "oldBudgetBelowRequirement": oldBudget < requiredBytes,
            "measuredBudgetAdmitsRequirement": requiredBytes
                < SceneOffscreenTextureResidentBudgetPolicy.automatic(
                    recommendedMaxWorkingSetSize: measuredRecommendedWorkingSet
                ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneOffscreenTextureResidentBudgetPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-resident-budget-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-resident-budget"
        compilation = subprocess.run(
            ["swiftc", str(POLICY_SOURCE), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=False, capture_output=True, text=True
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_floor_share_and_cap_are_exact_and_overflow_safe(self) -> None:
        self.assertEqual(self.result["floor"], self.result["floorExpected"])
        self.assertEqual(self.result["middle"], self.result["middleExpected"])
        self.assertEqual(
            self.result["measuredDevice"], self.result["measuredExpected"]
        )
        self.assertEqual(self.result["ceiling"], self.result["ceilingExpected"])
        self.assertEqual(
            self.result["overflowSafeCeiling"], self.result["ceilingExpected"]
        )

    def test_measured_requirement_crosses_only_the_device_share(self) -> None:
        self.assertTrue(self.result["oldBudgetBelowRequirement"])
        self.assertTrue(self.result["measuredBudgetAdmitsRequirement"])

    def test_pool_delegates_only_automatic_budget_selection(self) -> None:
        source = POOL_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "residentByteBudget ?? Self.automaticResidentByteBudget(", source
        )
        self.assertIn(
            "SceneOffscreenTextureResidentBudgetPolicy.automatic(", source
        )
        self.assertIn("allocationCache = .init(byteBudget: normalizedBudget)", source)


if __name__ == "__main__":
    unittest.main()
