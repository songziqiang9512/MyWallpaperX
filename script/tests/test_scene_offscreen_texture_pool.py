#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "SceneJSONValue.swift",
    SOURCE_ROOT / "SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "SceneGraphRenderTargetTable.swift",
    SOURCE_ROOT / "SceneGraphCommandRuntime.swift",
    SOURCE_ROOT / "SceneOffscreenTexturePool.swift",
]


HARNESS = r'''
import Foundation
import Metal

struct SceneAuthoredEffectExecutionPlan {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let requiresExactInputExtent: Bool
    let inputRole: SceneAuthoredEffectInputRole
}

struct SceneAuthoredEffectExecutionChain {
    let layerID: Int
    let stages: [SceneAuthoredEffectExecutionPlan]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct Fixture {
        let execution: SceneAuthoredEffectExecutionPlan
        let framebufferIdentities: [Graph.TextureIdentity]
    }

    static func texture(
        _ kind: Graph.TextureKind,
        layerID: Int,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func binding(
        _ texture: Graph.TextureIdentity,
        slot: Int
    ) -> Graph.Binding {
        .init(
            slot: slot,
            authoredName: texture.name ?? "previous",
            texture: texture,
            conditions: nil
        )
    }

    static func node(
        index: Int,
        effect: Graph.EffectKey,
        target: Graph.TextureIdentity,
        reads: [(Int, Graph.TextureIdentity)]
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: effect,
            definitionPassIndex: index,
            materialOrdinal: index,
            instancePassIndex: index,
            kind: .material,
            materialPath: "materials/\(index).json",
            materialPassID: "materials/\(index).json#0",
            target: target,
            bindings: reads.map { binding($0.1, slot: $0.0) },
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }

    static func fixture(
        effectIndex: Int,
        layerID: Int = 10,
        precise: Bool = false,
        framebufferFormat: String = "rgba_backbuffer",
        input authoredInput: Graph.TextureIdentity? = nil
    ) -> Fixture {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = authoredInput ?? texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let targets: [Graph.RenderTarget]
        let nodes: [Graph.Node]
        let identities: [Graph.TextureIdentity]

        if precise {
            let full = texture(.framebuffer, layerID: layerID, effect: key, name: "shared")
            identities = [full]
            targets = [.init(
                texture: full,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )]
            nodes = [
                node(index: 0, effect: key, target: full, reads: []),
                node(
                    index: 1,
                    effect: key,
                    target: output,
                    reads: [(0, full), (1, input)]
                ),
            ]
        } else {
            let quarterA = texture(
                .framebuffer, layerID: layerID, effect: key, name: "sharedA"
            )
            let quarterB = texture(
                .framebuffer, layerID: layerID, effect: key, name: "sharedB"
            )
            identities = [quarterA, quarterB]
            let scaled = Graph.TargetExtent(kind: .scale, first: 4, second: nil)
            targets = [quarterA, quarterB].map {
                .init(
                    texture: $0,
                    extent: scaled,
                    format: framebufferFormat,
                    declaredUnique: false,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                )
            }
            nodes = [
                node(index: 0, effect: key, target: quarterA, reads: [(0, input)]),
                node(index: 1, effect: key, target: quarterB, reads: [(0, quarterA)]),
                node(index: 2, effect: key, target: quarterA, reads: [(0, quarterB)]),
                node(
                    index: 3,
                    effect: key,
                    target: output,
                    reads: [(0, quarterA), (2, input)]
                ),
            ]
        }

        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: precise
                    ? "effects/blurprecise/effect.json"
                    : "effects/blur/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return Fixture(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: nodes.count,
                logicalRenderTargetCount: targets.count,
                requiresExactInputExtent: precise,
                inputRole: input.kind == .layerSource
                    ? .layerSource
                    : .priorEffectOutput
            ),
            framebufferIdentities: identities
        )
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}")
            return
        }

        let first = fixture(effectIndex: 0)
        let second = fixture(effectIndex: 1)
        let third = fixture(effectIndex: 2)
        let lruPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 1_200
        )
        guard let firstTable = lruPool.graphTargets(
            for: first.execution, requestedWidth: 8, requestedHeight: 8
        ), let secondTable = lruPool.graphTargets(
            for: second.execution, requestedWidth: 8, requestedHeight: 8
        ), let firstHit = lruPool.graphTargets(
            for: first.execution, requestedWidth: 8, requestedHeight: 8
        ) else {
            fatalError("initial graph cache allocation failed")
        }
        let sameNameDifferentEffectsAreDistinct = firstTable.inputTexture !== secondTable.inputTexture
            && firstTable.texture(for: first.framebufferIdentities[0])
                !== secondTable.texture(for: second.framebufferIdentities[0])
        guard let thirdTable = lruPool.graphTargets(
            for: third.execution, requestedWidth: 8, requestedHeight: 8
        ), let firstAfterEviction = lruPool.graphTargets(
            for: first.execution, requestedWidth: 8, requestedHeight: 8
        ), let recreatedSecond = lruPool.graphTargets(
            for: second.execution, requestedWidth: 8, requestedHeight: 8
        ) else {
            fatalError("LRU graph allocation failed")
        }
        _ = thirdTable

        let resizePool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 8_000
        )
        guard let beforeResize = resizePool.graphTargets(
            for: first.execution, requestedWidth: 8, requestedHeight: 8
        ), let afterResize = resizePool.graphTargets(
            for: first.execution, requestedWidth: 16, requestedHeight: 8
        ), let resizeHit = resizePool.graphTargets(
            for: first.execution, requestedWidth: 16, requestedHeight: 8
        ) else {
            fatalError("resize graph allocation failed")
        }

        let residentBudgetPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 1_200
        )
        guard let residentBudgetOriginal = residentBudgetPool.graphTargets(
            for: first.execution, requestedWidth: 8, requestedHeight: 8
        ) else {
            fatalError("resident budget fixture allocation failed")
        }
        let refusedResize = residentBudgetPool.graphTargets(
            for: first.execution, requestedWidth: 32, requestedHeight: 16
        ) == nil
        guard let residentBudgetOriginalAgain = residentBudgetPool.graphTargets(
            for: first.execution, requestedWidth: 8, requestedHeight: 8
        ) else {
            fatalError("resident budget failure removed original allocation")
        }

        let clampPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 8,
            residentByteBudget: 2_000
        )
        let precise = fixture(effectIndex: 3, precise: true)
        let exactClampRejected = clampPool.graphTargets(
            for: precise.execution, requestedWidth: 16, requestedHeight: 8
        ) == nil
        guard let clampedStandard = clampPool.graphTargets(
            for: first.execution, requestedWidth: 16, requestedHeight: 8
        ) else {
            fatalError("standard clamp allocation failed")
        }

        let legacyPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 1_000
        )
        guard let legacySmall = legacyPool.textures(width: 8, height: 8) else {
            fatalError("legacy pair fixture allocation failed")
        }
        let legacyLargeRejected = legacyPool.textures(width: 16, height: 16) == nil
        guard let legacySmallAgain = legacyPool.textures(width: 8, height: 8) else {
            fatalError("legacy resident budget failure removed original allocation")
        }
        let legacyClampPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 30_000
        )
        guard let legacyClamped = legacyClampPool.textures(width: 128, height: 64) else {
            fatalError("legacy clamp allocation failed")
        }
        let legacyLRUPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 3_300
        )
        guard let legacyFirstSmall = legacyLRUPool.textures(width: 8, height: 8),
              legacyLRUPool.textures(width: 16, height: 16) != nil,
              let legacyRecreatedSmall = legacyLRUPool.textures(width: 8, height: 8) else {
            fatalError("legacy LRU allocation failed")
        }

        let formatPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 8_000
        )
        let rgbaFixture = fixture(effectIndex: 0, framebufferFormat: "rgba8888")
        guard let bgraTable = formatPool.graphTargets(
            for: first.execution, requestedWidth: 8, requestedHeight: 8
        ), let rgbaTable = formatPool.graphTargets(
            for: rgbaFixture.execution, requestedWidth: 8, requestedHeight: 8
        ), let rgbaHit = formatPool.graphTargets(
            for: rgbaFixture.execution, requestedWidth: 8, requestedHeight: 8
        ), let rgbaFramebuffer = rgbaTable.texture(
            for: rgbaFixture.framebufferIdentities[0]
        ), let bgraFramebuffer = bgraTable.texture(
            for: first.framebufferIdentities[0]
        ) else {
            fatalError("format replacement fixture failed")
        }

        let chainPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 1_200
        )
        let chainFirst = fixture(effectIndex: 10)
        let chainSecond = fixture(
            effectIndex: 11,
            input: chainFirst.execution.renderGraph.finalOutput
        )
        let chain = SceneAuthoredEffectExecutionChain(
            layerID: 10,
            stages: [chainFirst.execution, chainSecond.execution]
        )
        guard let chainTables = chainPool.graphTargets(
            for: chain, requestedWidth: 8, requestedHeight: 8
        ), let chainHit = chainPool.graphTargets(
            for: chain, requestedWidth: 8, requestedHeight: 8
        ), chainTables.count == 2, chainHit.count == 2 else {
            fatalError("ordered chain allocation failed")
        }

        let rollbackPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 1_200
        )
        let rollbackFirst = fixture(effectIndex: 20)
        let rollbackSecond = fixture(
            effectIndex: 21,
            input: rollbackFirst.execution.renderGraph.finalOutput
        )
        guard let rollbackOriginal = rollbackPool.graphTargets(
            for: rollbackFirst.execution, requestedWidth: 8, requestedHeight: 8
        ) else {
            fatalError("transaction rollback fixture allocation failed")
        }
        let oversizedChain = SceneAuthoredEffectExecutionChain(
            layerID: 10,
            stages: [rollbackFirst.execution, rollbackSecond.execution]
        )
        let oversizedChainRejected = rollbackPool.graphTargets(
            for: oversizedChain, requestedWidth: 16, requestedHeight: 8
        ) == nil
        let rollbackAllocationCount = rollbackPool.residentAllocationCount
        let rollbackTextureCount = rollbackPool.residentTextureCount
        let rollbackBytes = rollbackPool.residentByteCost
        guard let rollbackOriginalAgain = rollbackPool.graphTargets(
            for: rollbackFirst.execution, requestedWidth: 8, requestedHeight: 8
        ) else {
            fatalError("failed chain removed resident graph allocation")
        }

        let accessRollbackPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 1_200
        )
        let accessFirst = fixture(effectIndex: 30)
        let accessSecond = fixture(effectIndex: 31)
        let accessThird = fixture(effectIndex: 32)
        let wrongOrderStage = fixture(effectIndex: 33)
        let accessChainSecond = fixture(
            effectIndex: 34,
            input: accessFirst.execution.renderGraph.finalOutput
        )
        let accessChainThird = fixture(
            effectIndex: 35,
            input: accessChainSecond.execution.renderGraph.finalOutput
        )
        guard let accessFirstTable = accessRollbackPool.graphTargets(
            for: accessFirst.execution, requestedWidth: 8, requestedHeight: 8
        ), accessRollbackPool.graphTargets(
            for: accessSecond.execution, requestedWidth: 8, requestedHeight: 8
        ) != nil else {
            fatalError("access rollback fixture allocation failed")
        }
        let wrongOrderChain = SceneAuthoredEffectExecutionChain(
            layerID: 10,
            stages: [accessFirst.execution, wrongOrderStage.execution]
        )
        let wrongOrderRejected = accessRollbackPool.graphTargets(
            for: wrongOrderChain, requestedWidth: 8, requestedHeight: 8
        ) == nil
        let overBudgetAccessChain = SceneAuthoredEffectExecutionChain(
            layerID: 10,
            stages: [
                accessFirst.execution,
                accessChainSecond.execution,
                accessChainThird.execution,
            ]
        )
        let overBudgetAccessRejected = accessRollbackPool.graphTargets(
            for: overBudgetAccessChain, requestedWidth: 8, requestedHeight: 8
        ) == nil
        let accessFailureAllocationCount = accessRollbackPool.residentAllocationCount
        let accessFailureTextureCount = accessRollbackPool.residentTextureCount
        let accessFailureBytes = accessRollbackPool.residentByteCost
        guard accessRollbackPool.graphTargets(
            for: accessThird.execution, requestedWidth: 8, requestedHeight: 8
        ) != nil, let accessFirstAfterEviction = accessRollbackPool.graphTargets(
            for: accessFirst.execution, requestedWidth: 8, requestedHeight: 8
        ) else {
            fatalError("access rollback LRU fixture failed")
        }

        let result: [String: Any] = [
            "metalUnavailable": false,
            "stableReuse": firstTable.inputTexture === firstHit.inputTexture
                && firstTable.outputTexture === firstHit.outputTexture,
            "effectIsolation": sameNameDifferentEffectsAreDistinct,
            "lruKeptRecent": firstTable.inputTexture === firstAfterEviction.inputTexture,
            "lruRecreatedOldest": secondTable.inputTexture !== recreatedSecond.inputTexture,
            "lruAllocationCount": lruPool.residentAllocationCount,
            "lruTextureCount": lruPool.residentTextureCount,
            "lruBytes": lruPool.residentByteCost,
            "resizeReplaced": beforeResize.inputTexture !== afterResize.inputTexture,
            "resizeStable": afterResize.inputTexture === resizeHit.inputTexture,
            "resizeAllocationCount": resizePool.residentAllocationCount,
            "resizeTextureCount": resizePool.residentTextureCount,
            "resizeBytes": resizePool.residentByteCost,
            "residentBudgetResizeRejected": refusedResize,
            "residentBudgetPreservedIdentity": residentBudgetOriginal.inputTexture
                === residentBudgetOriginalAgain.inputTexture,
            "residentBudgetAllocationCount": residentBudgetPool.residentAllocationCount,
            "residentBudgetTextureCount": residentBudgetPool.residentTextureCount,
            "residentBudgetBytes": residentBudgetPool.residentByteCost,
            "exactClampRejected": exactClampRejected,
            "standardClampSize": [
                clampedStandard.inputTexture.width,
                clampedStandard.inputTexture.height,
            ],
            "legacyLargeRejected": legacyLargeRejected,
            "legacyPreservedIdentity": legacySmall.primary === legacySmallAgain.primary,
            "legacyAllocationCount": legacyPool.residentAllocationCount,
            "legacyTextureCount": legacyPool.residentTextureCount,
            "legacyBytes": legacyPool.residentByteCost,
            "legacyClampedSize": [
                legacyClamped.primary.width,
                legacyClamped.primary.height,
            ],
            "legacyEvictedAffordable": legacyFirstSmall.primary
                !== legacyRecreatedSmall.primary,
            "formatChangeReplaced": bgraTable.inputTexture !== rgbaTable.inputTexture,
            "formatChangeStable": rgbaTable.inputTexture === rgbaHit.inputTexture,
            "formatChangeInputOutputBGRA": rgbaTable.inputTexture.pixelFormat == .bgra8Unorm
                && rgbaTable.outputTexture.pixelFormat == .bgra8Unorm,
            "backbufferFramebufferBGRA": bgraFramebuffer.pixelFormat == .bgra8Unorm,
            "formatChangeFramebufferRGBA": rgbaFramebuffer.pixelFormat == .rgba8Unorm,
            "formatChangeAllocationCount": formatPool.residentAllocationCount,
            "formatChangeTextureCount": formatPool.residentTextureCount,
            "formatChangeBytes": formatPool.residentByteCost,
            "chainOrder": chainTables.compactMap { $0.plan.output.effect?.effectIndex },
            "chainStableReuse": zip(chainTables, chainHit).allSatisfy {
                $0.inputTexture === $1.inputTexture && $0.outputTexture === $1.outputTexture
            },
            "chainAllocationCount": chainPool.residentAllocationCount,
            "chainTextureCount": chainPool.residentTextureCount,
            "chainBytes": chainPool.residentByteCost,
            "oversizedChainRejected": oversizedChainRejected,
            "rollbackPreservedIdentity": rollbackOriginal.inputTexture
                === rollbackOriginalAgain.inputTexture,
            "rollbackAllocationCount": rollbackAllocationCount,
            "rollbackTextureCount": rollbackTextureCount,
            "rollbackBytes": rollbackBytes,
            "wrongOrderRejected": wrongOrderRejected,
            "overBudgetAccessRejected": overBudgetAccessRejected,
            "accessFailureAllocationCount": accessFailureAllocationCount,
            "accessFailureTextureCount": accessFailureTextureCount,
            "accessFailureBytes": accessFailureBytes,
            "failedChainDidNotRefreshLRU": accessFirstTable.inputTexture
                !== accessFirstAfterEviction.inputTexture,
        ]
        resizePool.reset()
        var finalResult = result
        finalResult["resetAllocationCount"] = resizePool.residentAllocationCount
        finalResult["resetTextureCount"] = resizePool.residentTextureCount
        finalResult["resetBytes"] = resizePool.residentByteCost
        let data = try JSONSerialization.data(withJSONObject: finalResult, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


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
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_reuses_same_effect_and_isolates_different_effects(self) -> None:
        self.assertTrue(self.result["stableReuse"])
        self.assertTrue(self.result["effectIsolation"])

    def test_lru_evicts_the_oldest_graph_allocation_as_a_unit(self) -> None:
        self.assertTrue(self.result["lruKeptRecent"])
        self.assertTrue(self.result["lruRecreatedOldest"])
        self.assertEqual(self.result["lruAllocationCount"], 2)
        self.assertEqual(self.result["lruTextureCount"], 8)
        self.assertEqual(self.result["lruBytes"], 1_088)

    def test_resize_atomically_replaces_one_effect_table(self) -> None:
        self.assertTrue(self.result["resizeReplaced"])
        self.assertTrue(self.result["resizeStable"])
        self.assertEqual(self.result["resizeAllocationCount"], 1)
        self.assertEqual(self.result["resizeTextureCount"], 4)
        self.assertEqual(self.result["resizeBytes"], 1_088)

    def test_format_change_atomically_replaces_one_effect_table(self) -> None:
        self.assertTrue(self.result["formatChangeReplaced"])
        self.assertTrue(self.result["formatChangeStable"])
        self.assertTrue(self.result["formatChangeInputOutputBGRA"])
        self.assertTrue(self.result["backbufferFramebufferBGRA"])
        self.assertTrue(self.result["formatChangeFramebufferRGBA"])
        self.assertEqual(self.result["formatChangeAllocationCount"], 1)
        self.assertEqual(self.result["formatChangeTextureCount"], 4)
        self.assertEqual(self.result["formatChangeBytes"], 544)

    def test_chain_returns_one_stable_table_per_ordered_stage(self) -> None:
        self.assertEqual(self.result["chainOrder"], [10, 11])
        self.assertTrue(self.result["chainStableReuse"])
        self.assertEqual(self.result["chainAllocationCount"], 2)
        self.assertEqual(self.result["chainTextureCount"], 8)
        self.assertEqual(self.result["chainBytes"], 1_088)

    def test_chain_budget_failure_preserves_all_resident_state(self) -> None:
        self.assertTrue(self.result["oversizedChainRejected"])
        self.assertTrue(self.result["rollbackPreservedIdentity"])
        self.assertEqual(self.result["rollbackAllocationCount"], 1)
        self.assertEqual(self.result["rollbackTextureCount"], 4)
        self.assertEqual(self.result["rollbackBytes"], 544)

    def test_rejected_chains_do_not_refresh_partial_hit_lru_state(self) -> None:
        self.assertTrue(self.result["wrongOrderRejected"])
        self.assertTrue(self.result["overBudgetAccessRejected"])
        self.assertEqual(self.result["accessFailureAllocationCount"], 2)
        self.assertEqual(self.result["accessFailureTextureCount"], 8)
        self.assertEqual(self.result["accessFailureBytes"], 1_088)
        self.assertTrue(self.result["failedChainDidNotRefreshLRU"])

    def test_resident_budget_failure_preserves_existing_cache_accounting(self) -> None:
        self.assertTrue(self.result["residentBudgetResizeRejected"])
        self.assertTrue(self.result["residentBudgetPreservedIdentity"])
        self.assertEqual(self.result["residentBudgetAllocationCount"], 1)
        self.assertEqual(self.result["residentBudgetTextureCount"], 4)
        self.assertEqual(self.result["residentBudgetBytes"], 544)

    def test_precise_rejects_clamp_while_standard_uses_limited_extent(self) -> None:
        self.assertTrue(self.result["exactClampRejected"])
        self.assertEqual(self.result["standardClampSize"], [8, 4])

    def test_legacy_pair_over_resident_budget_preserves_existing_pair(self) -> None:
        self.assertTrue(self.result["legacyLargeRejected"])
        self.assertTrue(self.result["legacyPreservedIdentity"])
        self.assertEqual(self.result["legacyAllocationCount"], 1)
        self.assertEqual(self.result["legacyTextureCount"], 3)
        self.assertEqual(self.result["legacyBytes"], 768)

    def test_legacy_pair_preserves_clamp_and_affordable_lru_behavior(self) -> None:
        self.assertEqual(self.result["legacyClampedSize"], [64, 32])
        self.assertTrue(self.result["legacyEvictedAffordable"])

    def test_reset_clears_all_resident_accounting(self) -> None:
        self.assertEqual(self.result["resetAllocationCount"], 0)
        self.assertEqual(self.result["resetTextureCount"], 0)
        self.assertEqual(self.result["resetBytes"], 0)


if __name__ == "__main__":
    unittest.main()
