#!/usr/bin/env python3
"""Hidden effectful solids retain exact named graph demands, not raw sources."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

try:
    from .test_scene_dependency_render_plan import SWIFT_SOURCES
except ImportError:
    from test_scene_dependency_render_plan import SWIFT_SOURCES


HARNESS = r'''
import Foundation
import Metal

extension SceneMainPassEncoder {
    convenience init(commandBuffer: MTLCommandBuffer, target: MTLTexture,
                     clearColor: MTLClearColor, clearEnabled: Bool,
                     submissionOwner: SceneMainPassEncoder) {
        self.init(commandBuffer: commandBuffer, target: target,
                  clearColor: clearColor, clearEnabled: clearEnabled)
    }
}

@main
enum Harness {
    static let providerID = 41
    static let consumerID = 52

    static func inspect(
        consumerVisible: Bool = true,
        providerEffectVisible: Bool = true,
        consumerEffectVisible: Bool = true,
        admitted: Bool = true,
        slot: Int = 1,
        providerFirst: Bool = true,
        cycle: Bool = false
    ) -> [String: Any] {
        let provider = SceneRenderDescriptor.Layer(
            id: providerID, contentKind: "solid", utilityLayer: nil,
            dependencyLayerIDs: cycle ? [consumerID] : [], childLayerIDs: [],
            visible: false,
            effects: [.init(
                id: "provider-stage", file: "effects/self/data/effect.json",
                visible: providerEffectVisible, passes: [.init(
                    passIndex: 0, texturePaths: [], textureSlots: [],
                    userTextureInputs: [], combos: [:], constantShaderValues: [:]
                )]
            )]
        )
        let path = "_rt_imageLayerComposite_\(providerID)_a"
        var slots = Array<String?>(repeating: nil, count: 2)
        slots[slot] = path
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID, contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [providerID], childLayerIDs: [],
            visible: consumerVisible,
            effects: [.init(
                id: "consumer-stage", file: "effects/self/display/effect.json",
                visible: consumerEffectVisible, passes: [.init(
                    passIndex: 0, texturePaths: [path], textureSlots: slots,
                    userTextureInputs: [], combos: [:], constantShaderValues: [:]
                )]
            )]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer], renderOrderLayerIDs: providerFirst
                ? [providerID, consumerID] : [consumerID, providerID]
        )
        let references = Set(SceneDependencyGraphAnalysis.references(
            in: descriptor.layers
        ))
        // The launch preparation set may include a currently hidden typed
        // visibility owner. Frame activation must still use current visibility.
        let plan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: [consumerID],
            executableUtilityConsumerLayerIDs: SceneUtilityLayerRuntimePlanner
                .executableUtilityConsumerLayerIDs(
                    in: descriptor, resolvedMaterialLayerIDs: [providerID, consumerID]
                ),
            admittedResolvedMaterialReferences: admitted ? references : []
        )
        let binding = plan.bindingsByConsumerLayerID[consumerID]
        let available: Set<Int> = [providerID, consumerID]
        let plans = SceneUtilityLayerRuntimePlanner.plans(
            in: descriptor, dependencyPlan: plan, resolvedMaterialLayerIDs: available
        )
        let utilityExecution = SceneUtilityLayerRuntimePlanner.execution(
            in: descriptor, plans: plans
        )
        func execution(_ visible: Set<Int>) -> [Int] {
            plan.resolvedMaterialExecutionLayerIDs(
                visibleRootLayerIDs: visible, availableExecutionLayerIDs: available
            ).sorted()
        }
        return [
            "binding": binding != nil,
            "capturePrepared": utilityExecution.captureLayerIDs.contains(consumerID),
            "kindSolid": binding?.kind == .solidLayer,
            "requiresProgram": binding?.requiresResolvedMaterialProgram ?? false,
            "provider": binding?.providerLayerID ?? -1,
            "slots": binding?.referenceSlots.map {
                "\($0.effectID):\($0.passIndex):\($0.slotIndex)"
            } ?? [],
            "requiredProviders": plan.requiredProviderLayerIDs.sorted(),
            "requiredGraphs": plan.requiredGraphOutputProviderLayerIDs.sorted(),
            "effectConsumers": plan.requiredEffectConsumerLayerIDs.sorted(),
            "blocksRawProvider": plan.blocksStaticLayerSourcePassthrough(
                for: providerID
            ),
            "forward": binding?.requiresForwardCapture ?? false,
            "currentExecution": execution(consumerVisible ? [consumerID] : []),
            "shownExecution": execution([consumerID]),
            "hiddenExecution": execution([]),
            "preparationOrder": plan.resolvedMaterialPreparationOrder(
                authoredLayerIDs: [consumerID, providerID]
            ) ?? [],
        ]
    }

    static func main() throws {
        let results = [
            "active": inspect(),
            "startupHidden": inspect(consumerVisible: false),
            "unadmitted": inspect(admitted: false),
            "providerEffectDisabled": inspect(providerEffectVisible: false),
            "consumerEffectDisabled": inspect(consumerEffectVisible: false),
            "wrongSlot": inspect(slot: 0),
            "forward": inspect(providerFirst: false),
            "cycle": inspect(cycle: true),
        ]
        let data = try JSONSerialization.data(withJSONObject: results)
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneHiddenSolidProviderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-hidden-solid-plan-") as temporary:
            directory = Path(temporary)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = directory / "hidden-solid-plan"
            compilation = subprocess.run(
                ["xcrun", "--sdk", "macosx", "swiftc",
                 *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(binary)],
                capture_output=True, text=True,
            )
            if compilation.returncode != 0:
                raise RuntimeError(compilation.stderr)
            environment = os.environ.copy()
            environment.pop("MWX_SCENE_NAMED_PROVIDER_ROUTE", None)
            completed = subprocess.run(
                [str(binary)], check=True, capture_output=True,
                text=True, env=environment,
            )
            cls.results = json.loads(completed.stdout)

    def assert_graph_carrier(self, result: dict) -> None:
        self.assertTrue(result["binding"])
        self.assertTrue(result["capturePrepared"])
        self.assertTrue(result["kindSolid"])
        self.assertTrue(result["requiresProgram"])
        self.assertEqual(result["provider"], 41)
        self.assertEqual(result["slots"], ["consumer-stage:0:1"])
        self.assertEqual(result["requiredProviders"], [41])
        self.assertEqual(result["requiredGraphs"], [41])
        self.assertEqual(result["effectConsumers"], [52])
        self.assertTrue(result["blocksRawProvider"])
        self.assertFalse(result["forward"])
        self.assertEqual(result["preparationOrder"], [41, 52])

    def test_active_consumer_demands_hidden_graph_instead_of_raw_source(self) -> None:
        result = self.results["active"]
        self.assert_graph_carrier(result)
        self.assertEqual(result["currentExecution"], [41, 52])
        self.assertEqual(result["hiddenExecution"], [])

    def test_startup_hidden_consumer_retains_demand_without_executing(self) -> None:
        result = self.results["startupHidden"]
        self.assert_graph_carrier(result)
        self.assertEqual(result["currentExecution"], [])
        self.assertEqual(result["shownExecution"], [41, 52])
        self.assertEqual(result["hiddenExecution"], [])

    def test_unproven_and_invalid_carriers_keep_rejecting(self) -> None:
        for name in ("unadmitted", "providerEffectDisabled", "consumerEffectDisabled",
                     "wrongSlot", "forward", "cycle"):
            with self.subTest(name=name):
                result = self.results[name]
                self.assertFalse(result["binding"])
                self.assertEqual(result["requiredProviders"], [])
                self.assertEqual(result["requiredGraphs"], [])


if __name__ == "__main__":
    unittest.main()
