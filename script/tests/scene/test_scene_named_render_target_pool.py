#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneNamedRenderTargetPool.swift"
)

HARNESS_SOURCE = r'''
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.metalUnavailable
        }

        let identityPool = SceneNamedRenderTargetPool(
            device: device,
            maxDimension: 32,
            byteBudget: 4_096
        )
        let first = identityPool.texture(for: 10, width: 8, height: 8)
        let repeated = identityPool.texture(for: 10, width: 8, height: 8)
        let differentProvider = identityPool.texture(for: 11, width: 8, height: 8)
        let clamped = identityPool.texture(for: 12, width: 64, height: 32)
        let normalizedRepeat = identityPool.texture(for: 12, width: 32, height: 16)

        let replacementPool = SceneNamedRenderTargetPool(
            device: device,
            maxDimension: 32,
            byteBudget: 1_024
        )
        let beforeResize = replacementPool.texture(for: 20, width: 8, height: 8)
        let afterResize = replacementPool.texture(for: 20, width: 16, height: 16)
        let refusedResize = replacementPool.texture(for: 20, width: 32, height: 32)
        let retainedAfterRefusal = replacementPool.texture(for: 20, width: 16, height: 16)

        let budgetPool = SceneNamedRenderTargetPool(
            device: device,
            maxDimension: 32,
            byteBudget: 512
        )
        let budgetFirst = budgetPool.texture(for: 30, width: 8, height: 8)
        let budgetSecond = budgetPool.texture(for: 31, width: 8, height: 8)
        let overBudget = budgetPool.texture(for: 32, width: 1, height: 1)
        let costAfterBudgetRefusal = budgetPool.residentByteCost

        let floatPool = SceneNamedRenderTargetPool(
            device: device, pixelFormat: .rgba16Float, byteBudget: 512
        )
        let floatTexture = floatPool.texture(for: 50, width: 8, height: 8)
        let floatOverflow = floatPool.texture(for: 51, width: 1, height: 1)
        let historyPool = SceneNamedRenderTargetPool(device: device, byteBudget: 512)
        let historyA = historyPool.texture(for: 60, width: 8, height: 8)
        let historyB = historyPool.texture(for: 60, width: 8, height: 8, avoiding: historyA)
        let nextA = historyPool.texture(for: 60, width: 8, height: 8, avoiding: historyB)
        let nextB = historyPool.texture(for: 60, width: 8, height: 8, avoiding: nextA)
        let historyBlockedPeer = historyPool.texture(for: 61, width: 1, height: 1)
        let historySizeAndCost = [historyPool.residentTextureCount, historyPool.residentByteCost]
        let squeezed = SceneNamedRenderTargetPool(device: device, byteBudget: 256)
        let single = squeezed.texture(for: 62, width: 8, height: 8)
        let deniedAlternate = squeezed.texture(for: 62, width: 8, height: 8, avoiding: single)
        let fallbackPrimary = squeezed.texture(for: 62, width: 8, height: 8)

        let historyResize = SceneNamedRenderTargetPool(device: device, byteBudget: 1_024)
        let bothCountedDuringResize = autoreleasepool {
            let a = historyResize.texture(for: 63, width: 8, height: 8)
            let b = historyResize.texture(for: 63, width: 8, height: 8, avoiding: a)
            let unavailable = historyResize.texture(for: 63, width: 16, height: 16, avoiding: b)
            let stillB = historyResize.texture(for: 63, width: 8, height: 8, avoiding: a)
            historyResize.retireHistory(for: 63, keeping: nil)
            return withExtendedLifetime((a, b, stillB)) {
                a != nil && b != nil && unavailable == nil && stillB === b
                    && historyResize.residentByteCost == 512
            }
        }
        let reclaimedResize = historyResize.texture(for: 63, width: 16, height: 16)
        let gpuRetirement = try retirementAcrossSubmission(device: device)

        let invalidPool = SceneNamedRenderTargetPool(device: device)
        let negativeProvider = invalidPool.texture(for: -1, width: 8, height: 8)
        let zeroWidth = invalidPool.texture(for: 40, width: 0, height: 8)
        let negativeHeight = invalidPool.texture(for: 41, width: 8, height: -1)

        let result: [String: Any] = [
            "floatFormatAndBudget": floatTexture?.pixelFormat == .rgba16Float
                && floatPool.residentByteCost == 512 && floatOverflow == nil,
            "defaultMaximumDimension": SceneNamedRenderTargetPool.maximumDimension,
            "defaultByteBudget": SceneNamedRenderTargetPool.defaultByteBudget,
            "sameProviderReused": first === repeated,
            "differentProvidersIsolated": first !== differentProvider,
            "identityCount": identityPool.residentTextureCount,
            "identityCost": identityPool.residentByteCost,
            "clampedSize": [clamped?.width ?? 0, clamped?.height ?? 0],
            "normalizedRequestReused": clamped === normalizedRepeat,
            "usesBGRA8Unorm": first?.pixelFormat == .bgra8Unorm,
            "usesPrivateStorage": first?.storageMode == .private,
            "hasRenderTargetUsage": first?.usage.contains(.renderTarget) ?? false,
            "hasShaderReadUsage": first?.usage.contains(.shaderRead) ?? false,
            "resizeReplacedTexture": beforeResize !== afterResize,
            "resizeCount": replacementPool.residentTextureCount,
            "resizeCost": replacementPool.residentByteCost,
            "resizeOverBudgetRefused": refusedResize == nil,
            "resizeFailurePreservedOld": retainedAfterRefusal === afterResize,
            "budgetAllocatedTwo": budgetFirst != nil && budgetSecond != nil,
            "newProviderOverBudgetRefused": overBudget == nil,
            "budgetCount": budgetPool.residentTextureCount,
            "budgetCost": costAfterBudgetRefusal,
            "historyDistinctAndRotates": historyA != nil && historyB != nil && historyA !== historyB
                && historyA === nextA && historyB === nextB,
            "historySizeAndCost": historySizeAndCost,
            "historyBlockedPeer": historyBlockedPeer == nil,
            "historyFailureKeepsSingle": single != nil && deniedAlternate == nil
                && fallbackPrimary === single && squeezed.residentByteCost == 256,
            "bothCountedDuringResize": bothCountedDuringResize,
            "reclaimedResize": reclaimedResize?.width == 16 && historyResize.residentByteCost == 1_024,
            "gpuRetirement": gpuRetirement,
            "invalidSizesRefused": negativeProvider == nil && zeroWidth == nil && negativeHeight == nil,
            "invalidCount": invalidPool.residentTextureCount,
            "invalidCost": invalidPool.residentByteCost,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    enum HarnessError: Error {
        case metalUnavailable
    }

    static func retirementAcrossSubmission(device: MTLDevice) throws -> [String: Bool] {
        let pool = SceneNamedRenderTargetPool(device: device, byteBudget: 512)
        guard let queue = device.makeCommandQueue() else { throw HarnessError.metalUnavailable }
        let held = try autoreleasepool {
            guard let command = queue.makeCommandBuffer() else { throw HarnessError.metalUnavailable }
            let preserved = try autoreleasepool {
                guard let old = pool.texture(for: 70, width: 8, height: 8),
                      let next = pool.texture(for: 70, width: 8, height: 8, avoiding: old)
                else { throw HarnessError.metalUnavailable }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = old
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                guard let encoder = command.makeRenderCommandEncoder(descriptor: pass)
                else { throw HarnessError.metalUnavailable }
                encoder.endEncoding()
                pool.retireHistory(for: 70, keeping: next)
                return pool.texture(for: 70, width: 8, height: 8) === next
            }
            // No CPU variable or render-pass descriptor still owns the old
            // member. The retaining Metal submission prevents overbooking.
            let blocked = pool.residentByteCost == 512 && pool.residentTextureCount == 2
                && pool.texture(for: 71, width: 8, height: 8) == nil
            command.commit()
            command.waitUntilCompleted()
            return preserved && blocked && command.status == .completed
        }
        let afterRetirement = pool.residentTextureCount == 1 && pool.residentByteCost == 256
        let replacement = pool.texture(for: 71, width: 8, height: 8)
        return ["liveCharge": held, "terminalRelease": afterRetirement && replacement != nil]
    }
}
'''


class SceneNamedRenderTargetPoolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-named-target-pool-"
        )
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-named-target-pool"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                str(SOURCE),
                str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift"),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    def test_defaults_and_metal_contract_are_bounded(self) -> None:
        self.assertTrue(self.result["floatFormatAndBudget"])
        self.assertEqual(self.result["defaultMaximumDimension"], 2_048)
        self.assertEqual(self.result["defaultByteBudget"], 64 * 1_024 * 1_024)
        self.assertTrue(self.result["usesBGRA8Unorm"])
        self.assertTrue(self.result["usesPrivateStorage"])
        self.assertTrue(self.result["hasRenderTargetUsage"])
        self.assertTrue(self.result["hasShaderReadUsage"])

    def test_provider_identity_is_stable_and_never_shared(self) -> None:
        self.assertTrue(self.result["sameProviderReused"])
        self.assertTrue(self.result["differentProvidersIsolated"])
        self.assertEqual(self.result["identityCount"], 3)
        self.assertEqual(self.result["identityCost"], 2_560)

    def test_dimensions_are_clamped_before_cache_lookup(self) -> None:
        self.assertEqual(self.result["clampedSize"], [32, 16])
        self.assertTrue(self.result["normalizedRequestReused"])

    def test_resize_replaces_and_reaccounts_transactionally(self) -> None:
        self.assertTrue(self.result["resizeReplacedTexture"])
        self.assertEqual(self.result["resizeCount"], 1)
        self.assertEqual(self.result["resizeCost"], 1_024)
        self.assertTrue(self.result["resizeOverBudgetRefused"])
        self.assertTrue(self.result["resizeFailurePreservedOld"])

    def test_budget_and_invalid_dimensions_fail_closed(self) -> None:
        self.assertTrue(self.result["budgetAllocatedTwo"])
        self.assertTrue(self.result["newProviderOverBudgetRefused"])
        self.assertEqual(self.result["budgetCount"], 2)
        self.assertEqual(self.result["budgetCost"], 512)
        self.assertTrue(self.result["invalidSizesRefused"])
        self.assertEqual(self.result["invalidCount"], 0)
        self.assertEqual(self.result["invalidCost"], 0)

    def test_history_uses_two_targets_and_refuses_more_than_the_pool_budget(self) -> None:
        self.assertTrue(self.result["historyDistinctAndRotates"])
        self.assertEqual(self.result["historySizeAndCost"], [2, 512])
        self.assertTrue(self.result["historyBlockedPeer"])
        self.assertTrue(self.result["historyFailureKeepsSingle"])

    def test_history_resize_and_retirement_preserve_the_cost_of_live_targets(self) -> None:
        self.assertTrue(self.result["bothCountedDuringResize"])
        self.assertTrue(self.result["reclaimedResize"])

    def test_retired_history_remains_charged_until_metal_releases_it(self) -> None:
        self.assertEqual(self.result["gpuRetirement"], {"liveCharge": True, "terminalRelease": True})


if __name__ == "__main__":
    unittest.main()
