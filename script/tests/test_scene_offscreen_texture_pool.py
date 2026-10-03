#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Rendering/Composition/SceneMainPassEncoder.swift",
    SOURCE_ROOT / "Rendering/Targets/SceneOffscreenTexturePool+SceneColor.swift",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Clear.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Extent.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetFormat.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState+Validation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState+Identity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetTable.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetTable+Mapped.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneLayerFullFramePairPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneLayerGraphTargetPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetLease.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetLease+Publication.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureResidency.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache+SharedPair.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache+Batch.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache+PreparationAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureFramePreflight.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTexturePool+PersistentGraphTargets.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/ScenePersistentGraphTargetAllocator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureResidentBudgetPolicy.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTexturePool.swift",
]


HARNESS = "".join(
    (Path(__file__).with_name("fixtures") / name).read_text(encoding="utf-8")
    for name in (
        "SceneOffscreenPoolSupport.swift",
        "SceneOffscreenPoolHarness.swift",
        "SceneOffscreenPoolPlanningChecks.swift",
        "SceneOffscreenPoolSharedBatchChecks.swift",
        "SceneOffscreenPoolInFlightResidencyChecks.swift",
        "SceneOffscreenPoolHistoryChecks.swift",
    )
)


class SceneOffscreenTexturePoolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-pool-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-offscreen-pool"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-module-cache-path",
                str(root / "module-cache"),
                "-framework",
                "Metal",
                "-o",
                str(binary),
            ],
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
        if destination := os.environ.get("MWX_REFLECTION_EVIDENCE"):
            Path(destination).mkdir(parents=True, exist_ok=True)
            (Path(destination)/"pool.json").write_text(json.dumps(cls.result, indent=2))
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_reflection_resources_are_atomic_budgeted_and_submission_pinned(self) -> None:
        for key, passed in self.result["reflectionResidency"].items():
            self.assertTrue(passed, key)

    def test_automatic_budget_admits_302_shape_without_weakening_explicit_cap(self) -> None:
        self.assertTrue(self.result["automaticBudgetBoundsAreStable"])
        self.assertTrue(self.result["defaultPoolUsesDeviceBudget"])
        self.assertTrue(self.result["explicit128BudgetIsPreserved"])
        self.assertEqual(self.result["sample302RequiredBytes"], 134_683_872)
        self.assertTrue(self.result["sample302ShapeIsExact"])
        self.assertTrue(self.result["sample302FitsAutomaticBudget"])
        self.assertTrue(
            self.result["sample302Explicit128RejectedWithoutMutation"]
        )
        self.assertTrue(self.result["zeroByteResidentDoesNotStopLRUEviction"])

    def test_shared_fbo_graphs_share_pair_with_separate_residency(self) -> None:
        self.assertTrue(self.result["sharedFBOFramePairShared"])
        self.assertTrue(self.result["sharedFBOFramebuffersDistinct"])
        self.assertTrue(self.result["sharedFBOStateOwnsOnlyFBO"])
        self.assertTrue(self.result["sharedFBOBudgetExact"])
        self.assertTrue(self.result["sharedFBOPairRetainedAfterOneRelease"])
        self.assertTrue(self.result["sharedFBOPairRetainedAfterAllRelease"])
        self.assertTrue(self.result["overBudgetSharedFBORejected"])
        self.assertTrue(self.result["unsafeUnsubmittedSharedPairRejected"])
        self.assertTrue(self.result["differentQueueSharedPairRejected"])
        self.assertTrue(self.result["sharedPairOrderedReuseAndReleaseStable"])

    def test_shared_and_owned_targets_charge_actual_format_and_physical_owner(self) -> None:
        for case, passed in self.result["formatAccounting"].items():
            with self.subTest(case=case):
                self.assertTrue(passed)

    def test_whole_frame_shared_pair_residency_is_atomic(self) -> None:
        self.assertTrue(self.result["wholeFrameSharedPairSetIsAtomic"])

    def test_incompatible_copy_extent_keeps_typed_frame_local_reason(self) -> None:
        self.assertTrue(self.result["incompatibleCopyProbeAccepted"])
        self.assertEqual(
            self.result["incompatibleCopyFrameReason"],
            "frame-target-plan-unsupported-target-descriptor",
        )

    def test_fit_extent_reaches_actual_plan_and_keeps_typed_mismatch(self) -> None:
        self.assertEqual(
            self.result["fitCopyFrameExtents"],
            [[256, 144], [256, 144]],
        )
        self.assertTrue(self.result["incompatibleFitProbeAccepted"])
        self.assertEqual(
            self.result["incompatibleFitFrameReason"],
            "frame-target-plan-unsupported-target-descriptor",
        )

    def test_fit_scale_combination_uses_actual_plan_and_typed_mismatch(self) -> None:
        self.assertEqual(
            self.result["fitScaleFrameExtents"],
            [[128, 72], [128, 72]],
        )
        self.assertTrue(self.result["incompatibleFitScaleProbeAccepted"])
        self.assertEqual(
            self.result["incompatibleFitScaleFrameReason"],
            "frame-target-plan-unsupported-target-descriptor",
        )

    def test_absolute_extent_reaches_actual_plan_and_rejects_mismatch(self) -> None:
        self.assertEqual(
            self.result["absoluteCopyFrameExtents"],
            [[640, 360], [640, 360]],
        )
        self.assertFalse(self.result["incompatibleAbsoluteProbeAccepted"])
        self.assertEqual(
            self.result["incompatibleAbsoluteFrameReason"],
            "frame-target-plan-unsupported-target-descriptor",
        )

    def test_single_axis_extent_preserves_other_axis_and_rejects_mismatch(
        self,
    ) -> None:
        self.assertEqual(
            self.result["singleAxisFrameExtents"],
            [[640, 1152], [640, 1152]],
        )
        self.assertFalse(self.result["incompatibleSingleAxisProbeAccepted"])
        self.assertEqual(
            self.result["incompatibleSingleAxisFrameReason"],
            "frame-target-plan-unsupported-target-descriptor",
        )

    def test_resolved_batch_shares_full_frame_working_pair(self) -> None:
        self.assertTrue(self.result["batchPlansShareOneWorkingPair"])
        self.assertTrue(
            self.result["sharedResolvedPublicationsUseChainGeneration"]
        )
        self.assertTrue(self.result["batchPrepareOnlyPublishesSharedPair"])
        self.assertTrue(self.result["sharedPairBudgetRejectsBeforeAllocation"])

    def test_persistent_chain_uses_one_two_member_full_frame_pair(self) -> None:
        self.assertTrue(self.result["persistentPairSharedAcrossStages"])
        self.assertTrue(self.result["persistentPairHasTwoPhysicalObjects"])
        self.assertTrue(self.result["persistentStateProjectionExcludesPair"])
        self.assertTrue(self.result["persistentPairHandoffContinuous"])
        self.assertTrue(self.result["persistentPairBaseMapped"])
        self.assertTrue(self.result["persistentPairTerminalFixed"])
        self.assertTrue(self.result["persistentPairHitGenerationStable"])
        self.assertEqual(self.result["persistentPairResetAllocationCount"], 0)
        self.assertTrue(self.result["persistentPairResetGenerationAdvanced"])
        self.assertTrue(self.result["persistentPairResetTokensChanged"])

    def test_r8_persistent_targets_use_single_channel_budget_and_allocation(self) -> None:
        self.assertTrue(self.result["r8PersistentAllocationTyped"])
        self.assertTrue(self.result["r8BudgetRejectsBeforeAllocation"])

    def test_r8_history_retire_and_rehydrate_preserve_single_channel_budget(self) -> None:
        self.assertTrue(self.result["r8HistoryCurrentCostExact"])
        self.assertTrue(self.result["r8HistoryRetiredCostExact"])
        self.assertTrue(self.result["r8HistoryReleaseRestoresCurrentCost"])
        self.assertTrue(self.result["r8HistoryFinalReleaseClearsResidency"])

    def test_compose_parity_controls_only_endpoint_aliasing(self) -> None:
        self.assertEqual(self.result["composeEndpointAliases"], [False, True, False])
        self.assertTrue(self.result["composePairBijection"])
        self.assertTrue(self.result["composeTerminalFixed"])

    def test_whole_chain_reuses_two_slots_and_clamps_to_standard_extent(self) -> None:
        # 缺口 5b 候选 A：近预算 4000x4000 poolLimit 请求在规划入口降档，
        # 整链仍复用两 slot、单 allocation，实际驻留为 standard 档
        # 2048x2048 双纹理（2048^2*2*4 = 33_554_432）；graphPlanNearBudgetBytes
        # 是绕过规划入口的直接 make（4000x4000），不受档位规则影响。
        self.assertTrue(self.result["persistentGraphStable"])
        self.assertTrue(self.result["persistentPrepareNoMutation"])
        self.assertTrue(self.result["persistentRepeatedCommitRejected"])
        self.assertTrue(self.result["persistentSubmissionAndHistorySeparated"])
        self.assertTrue(self.result["chainStageHandoffContinuous"])
        self.assertEqual(self.result["graphPlanNearBudgetBytes"], 128_000_000)
        self.assertEqual(self.result["graphPlanSlotCount"], 2)
        self.assertEqual(self.result["chainPhysicalObjectCount"], 2)
        self.assertEqual(self.result["persistentGraphAllocationCount"], 1)
        self.assertEqual(self.result["persistentGraphTextureCount"], 2)
        self.assertEqual(self.result["persistentGraphBytes"], 33_554_432)

    def test_typed_persistent_extent_policy_defaults_to_standard_cap(self) -> None:
        # 缺口 5b 候选 A：非 exact 层链规划 extent 一律 .standard 档——
        # 裸 poolLimit 请求在规划入口整体降档到 ≤2048，与默认档同 extent；
        # standard+exact 的矛盾组合仍被 exactness 硬拒。
        standard_extent = self.result["typedStandardExtent"]
        pool_limit_extent = self.result["typedPoolLimitExtent"]
        self.assertLessEqual(max(standard_extent), 2_048)
        self.assertLessEqual(max(pool_limit_extent), 2_048)
        self.assertEqual(pool_limit_extent, standard_extent)
        self.assertTrue(self.result["typedExactStandardClampRejected"])

    def test_geometry_sampling_extent_is_exact_inside_existing_pool_limit(self) -> None:
        # 缺口 5b 候选 A 回归门：exact 合同层链规划逐字保留原 policy——
        # 4000x3000 请求按输入原幅规划（若被错误降档会变 2048x1536），
        # 超 hardLimit 的 exact 请求仍硬拒。
        self.assertEqual(
            self.result["exactSamplingTextureExtent"], [5_000, 2_200]
        )
        self.assertEqual(self.result["typedExactChainExtent"], [4_000, 3_000])
        self.assertTrue(self.result["oversizedExactSamplingTextureRejected"])

    def test_two_inflight_generations_are_bounded_and_reusable(self) -> None:
        self.assertTrue(self.result["inFlightAllocationsAreDistinct"])
        self.assertTrue(self.result["inFlightCapacityFailsBeforeAllocation"])
        self.assertTrue(
            self.result[
                "requiredSharedResidencySurvivesTransientCapacityDeferral"
            ]
        )
        self.assertTrue(self.result["stableTwoSlotRingAvoidsTextureChurn"])
        self.assertTrue(self.result["resetInvalidatedSlotNeverReentersRing"])
        self.assertTrue(self.result["pinnedSecondSlotBudgetFailsBeforeAllocation"])
        self.assertTrue(self.result["pinnedOneSlotFramePreflightDefers"])
        self.assertTrue(self.result["releasedOneSlotFramePreflightReady"])
        self.assertTrue(self.result["reverseReleaseNeverReusesPinnedSlot"])
        self.assertTrue(
            self.result["idleRetiredLRUEvictableUnderOtherChainPressure"]
        )
        self.assertTrue(self.result["aggregateFrameHardOverBudget"])
        self.assertTrue(self.result["aggregateFrameReadyAtExactBudget"])
        self.assertTrue(
            self.result["mixedHistoryAndTransientRejectsImmediately"]
        )
        self.assertTrue(
            self.result["mixedHistoryRemainsHardAfterTransientRelease"]
        )
        self.assertTrue(self.result["mixedFrameReadyAfterHistoryRelease"])
        self.assertTrue(self.result["inFlightHistoryPreservesPinnedSeed"])

    def test_fit_transient_blocker_is_not_reported_as_byte_budget(self) -> None:
        self.assertTrue(
            self.result[
                "requiredSharedResidencySurvivesTransientCapacityDeferral"
            ]
        )
        source = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureFramePreflight.swift"
        ).read_text(encoding="utf-8")
        branch = source.index(
            "if requiredBytes.map({ $0 > byteBudget }) != false {"
        )
        log = source.index("phase=frame-target-budget-blocked")
        rejection = source.index(
            'return .rejected(reasonCode: "frame-target-byte-budget-exceeded")'
        )
        transient = source.index("let transientIDs = Set(")
        self.assertLess(branch, log)
        self.assertLess(log, rejection)
        self.assertLess(rejection, transient)

    def test_same_queue_reuse_is_bounded_and_fail_closed(self) -> None:
        self.assertTrue(
            self.result["sameQueueReusesOneTrackedPhysicalAllocation"]
        )
        self.assertTrue(
            self.result["sharedResetRetainsOneInvalidatedGeneration"]
        )
        self.assertTrue(self.result["forwardReleasePreservesNewerPin"])
        self.assertTrue(self.result["forwardFinalReleaseReturnsIdle"])
        self.assertTrue(
            self.result["submittedCurrentBufferRejectsSharedCommit"]
        )
        self.assertTrue(
            self.result["completedOrderingContextRejectedBeforeAllocation"]
        )
        self.assertTrue(self.result["differentSameQueueBufferRejectsCommit"])
        self.assertTrue(self.result["differentQueueBufferRejectsCommit"])
        self.assertTrue(self.result["reverseReleasePreservesOlderPin"])
        self.assertTrue(self.result["reverseFinalReleaseReturnsIdle"])
        self.assertTrue(self.result["thirdPinRejectedBeforeAllocation"])
        self.assertTrue(
            self.result["releasingOneSharedPinKeepsOtherGenerationResident"]
        )
        self.assertTrue(self.result["differentQueueStaysCopyOnWrite"])
        self.assertTrue(self.result["oldNotEnqueuedStaysCopyOnWrite"])
        self.assertTrue(self.result["historyOwnershipAlwaysUsesCopyOnWrite"])
        self.assertTrue(self.result["untrackedStaysCopyOnWrite"])

    def test_true_overbudget_rejects_before_any_texture_factory_call(self) -> None:
        self.assertEqual(self.result["defaultBudgetFailure"], "byteBudgetExceeded")
        self.assertTrue(self.result["overBudgetZeroPhysicalAllocation"])

    def test_unique_slots_are_not_reused_across_effects(self) -> None:
        self.assertTrue(self.result["uniqueNeverCrossEffectReused"])
        self.assertTrue(self.result["ordinaryCrossStageReuse"])
        self.assertTrue(self.result["differentFramebufferNamesNeverAlias"])
        self.assertTrue(self.result["ordinaryCacheIdentityOmitsEffect"])
        self.assertTrue(self.result["uniqueCacheIdentityIncludesEffect"])

    def test_dynamic_history_uses_copy_on_write_and_survives_gpu_failure(self) -> None:
        self.assertTrue(self.result["historySwapPinnedFinalMapping"])
        self.assertTrue(self.result["historyClosureContractAligned"])
        self.assertTrue(self.result["sharedHistoryUsesPrivateFBOResidency"])
        self.assertTrue(self.result["historyMissingTokenRejected"])
        self.assertTrue(self.result["historyExtraTokenRejected"])
        self.assertTrue(self.result["discardHistoryRequiresTypedDisposition"])
        self.assertTrue(
            self.result["discardHistoryRejectsSimultaneousPublication"]
        )
        self.assertTrue(self.result["discardHistoryRejectsUnexpectedEffect"])
        self.assertTrue(
            self.result["typedHistoryDiscardKeepsSubmissionWithoutHistoryPin"]
        )
        self.assertTrue(
            self.result["typedHistoryDiscardDoesNotPublishHistorySeed"]
        )
        self.assertTrue(self.result["historyCopyOnWriteIsolated"])
        self.assertTrue(self.result["partialGPUWritePreservedCommittedPixels"])
        self.assertTrue(self.result["gpuFailurePreservedCommittedHistory"])
        self.assertTrue(self.result["rehydrateGenerationChanged"])
        self.assertTrue(self.result["resetRetainedOnlyDynamicHistory"])
        self.assertTrue(self.result["finalReleaseClearedResidency"])

    def test_history_resize_preserves_only_storage_compatible_semantics(self) -> None:
        self.assertTrue(self.result["fixedHistorySurvivesPairResize"])
        self.assertTrue(self.result["dynamicHistoryResizeStartsFresh"])
        self.assertTrue(self.result["changedHistorySemanticsDoNotSeed"])

    def test_stale_prepared_token_is_one_shot_and_zero_mutation(self) -> None:
        self.assertTrue(self.result["stalePreparedRejected"])

    def test_whole_frame_target_batch_is_atomic_and_revision_bound(self) -> None:
        self.assertTrue(self.result["batchPrepareHasNoVisibleMutation"])
        self.assertTrue(self.result["batchCommitPublishesAtomically"])
        self.assertTrue(self.result["secondCandidateFailureHasZeroMutation"])
        self.assertTrue(self.result["secondMaterializationFailureHasZeroMutation"])
        self.assertTrue(self.result["unrelatedReleaseRevalidatesWholeBatch"])
        self.assertTrue(self.result["resetInvalidatesWholePreparedBatch"])

    def test_residency_counters_fail_closed_instead_of_wrapping(self) -> None:
        source = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache.swift"
        ).read_text(encoding="utf-8")
        issuer = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTexturePool.swift"
        ).read_text(encoding="utf-8")
        self.assertNotIn("&+=", source)
        self.assertIn("addingReportingOverflow(1)", source)
        self.assertNotIn("preservedTokensByTexture", source + issuer)

    def test_authored_shader_resolution_policy_does_not_raise_standard_effect_extent(self) -> None:
        self.assertEqual(self.result["standardMaximumDimension"], 2048)
        self.assertEqual(self.result["authoredShaderMaximumDimension"], 4096)


if __name__ == "__main__":
    unittest.main()
