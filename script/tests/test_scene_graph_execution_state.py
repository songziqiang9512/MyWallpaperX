#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STATE_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState+Validation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState+Identity.swift",
]
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Clear.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Extent.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneLayerFullFramePairPlan.swift",
    *STATE_SOURCES,
]


HARNESS = "".join(
    (Path(__file__).with_name("fixtures") / name).read_text(encoding="utf-8")
    for name in ("SceneGraphExecutionStateSupport.swift", "SceneGraphExecutionStateCases.swift")
)


class SceneGraphExecutionStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-graph-state-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-graph-state"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-D",
                "SCENE_GRAPH_TESTING",
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], capture_output=True, text=True
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_prepared_execution_preserves_commands_and_dynamic_failures(self) -> None:
        for name, passed in self.result["preparedChecks"].items():
            self.assertTrue(passed, name)

    def test_pair_endpoints_never_enter_persistent_state(self) -> None:
        self.assertEqual(self.result["ordinaryKinds"], ["material"])
        self.assertEqual(self.result["ordinaryMappings"], [0, 0])
        self.assertEqual(self.result["ordinaryMaterialShapes"], [["", "pair"]])
        self.assertEqual(self.result["prunedMaterialOrdinals"], [2])
        self.assertEqual(self.result["endpointAllocationFailure"], "missingIdentity")

    def test_pair_only_allocation_generation_can_reprepare(self) -> None:
        self.assertEqual(self.result["ordinaryRepreparedGeneration"], 2)
        self.assertEqual(self.result["ordinaryRepreparedMappings"], [0, 0])
        self.assertEqual(self.result["ordinaryRepreparedKinds"], ["material"])

    def test_single_and_multiple_compose_are_pair_validated_only(self) -> None:
        self.assertEqual(self.result["singleComposeKinds"], ["material", "material"])
        self.assertEqual(self.result["singleComposeMappingCount"], 0)
        self.assertEqual(
            self.result["multipleComposeKinds"],
            ["material", "material", "material"],
        )
        self.assertEqual(self.result["multipleComposeMappingCount"], 0)
        self.assertEqual(self.result["pairMismatchFailure"], "pairStepMismatch")

    def test_copy_and_swap_keep_only_fbo_state(self) -> None:
        self.assertEqual(
            self.result["swapKinds"],
            ["material", "material", "swap", "material"],
        )
        self.assertEqual(self.result["swapAfter1"], ["swap-q2", "swap-q1"])
        self.assertEqual(self.result["swapBefore2"], self.result["swapAfter1"])
        self.assertEqual(self.result["swapAfter2"], ["swap-q1", "swap-q2"])
        self.assertEqual(self.result["copyKinds"], ["material", "copy", "material"])
        self.assertEqual(
            self.result["unchangedFBOsWithFreshGenerationFailure"],
            "freshAllocationTokenReuse",
        )

    def test_tail_keeps_only_non_history_initialization_state(self) -> None:
        self.assertTrue(all(
            generation > 0
            for generation in self.result["swapTransactionGenerations"]
        ))
        self.assertEqual(self.result["swapCommittedGenerations"], [0, 0])
        self.assertEqual(self.result["swapCommittedInitialized"], 0)
        self.assertEqual(
            self.result["clearInitializations"],
            [["clear-q1"], [], ["clear-q1"], ["clear-fresh-q1"]],
        )
        self.assertEqual(self.result["clearCommittedGeneration"], 0)
        self.assertEqual(self.result["clearCommittedInitialized"], 1)

    def test_reset_reparse_and_resize_keep_the_fbo_contract(self) -> None:
        expected = ["swap-q1", "swap-q2"]
        self.assertEqual(self.result["resetMappingBefore"], expected)
        self.assertEqual(self.result["reparseMappingBefore"], expected)
        self.assertEqual(self.result["resizeExtents"], ["200x100", "200x100"])
        self.assertEqual(
            self.result["resizeMappingBefore"],
            ["resize-large-q2", "resize-large-q1"],
        )

    def test_explicit_function_clear_is_ordered_versioned_and_atomic(self) -> None:
        self.assertEqual(
            self.result["functionClearReasons"],
            ["reset:0:0", "reset:0:1", "reset:1:0", "reset:1:1"],
        )
        self.assertEqual(self.result["functionClearGeneration"], 4)
        self.assertEqual(
            self.result["functionClearMissingTargetFailure"],
            "functionUnavailable",
        )

    def test_history_rehydration_is_explicit_and_closure_bounded(self) -> None:
        self.assertEqual(self.result["historyDirectCount"], 1)
        self.assertEqual(self.result["historyClosureCount"], 2)
        self.assertTrue(all(
            generation > 0
            for generation in self.result["historyCommittedGenerations"]
        ))
        self.assertEqual(self.result["historyFirstInitializations"], ["history-old-q1"])
        self.assertEqual(self.result["rehydratedInitializations"], [])
        self.assertEqual(
            self.result["rehydratedGenerationBefore"],
            self.result["rehydratedExpectedGeneration"],
        )
        self.assertEqual(
            self.result["missingRehydrationInitializations"],
            ["history-new-q2"],
        )
        self.assertEqual(
            self.result["invalidRehydration"], "historyRehydrationMismatch"
        )
        self.assertEqual(
            self.result["outsideRehydration"], "historyRehydrationMismatch"
        )
        self.assertEqual(
            self.result["reusedTokenFailure"], "freshAllocationTokenReuse"
        )

    def test_transition_is_a_pre_gpu_pure_candidate(self) -> None:
        self.assertTrue(self.result["pureCandidateEqual"])
        self.assertTrue(self.result["previousStateUnchanged"])
        self.assertEqual(self.result["historyResetInitializations"], ["history-old-q1"])

    def test_address_mode_changes_reset_history_and_reject_stale_rehydration(self) -> None:
        self.assertTrue(self.result["clampToRepeatHistoryResets"])
        self.assertTrue(self.result["repeatToClampHistoryResets"])
        self.assertEqual(
            self.result["clampToRepeatRehydrationFailure"],
            "historyRehydrationMismatch",
        )
        self.assertEqual(
            self.result["repeatToClampRehydrationFailure"],
            "historyRehydrationMismatch",
        )

    def test_fbo_hazards_and_aliases_remain_fail_closed(self) -> None:
        self.assertEqual(self.result["aliasFailure"], "physicalAlias")
        self.assertEqual(self.result["hazardFailure"], "readWriteHazard")
        self.assertEqual(self.result["readBeforeWriteFailure"], "readBeforeWrite")

    def test_valid_graphs_larger_than_diagnostic_capacity_keep_playing(self) -> None:
        self.assertEqual(self.result["largeNodeCount"], 513)
        self.assertEqual(self.result["largeTargetCount"], 513)
        self.assertTrue(self.result["largeNodeRawPreparedMatch"])
        self.assertTrue(self.result["largeTargetRawPreparedMatch"])


if __name__ == "__main__":
    unittest.main()
