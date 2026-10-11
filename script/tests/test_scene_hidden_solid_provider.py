#!/usr/bin/env python3
"""Admitted consumers retain hidden solid graph demands, not raw sources."""

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
        cycle: Bool = false,
        consumerKind: String = "composition",
        puppetChildren: Bool = false,
        extraAssets: Bool = false,
        extraEffect: Bool = false,
        userOverride: Bool = false,
        providerMissing: Bool = false,
        providerEffectless: Bool = false,
        providerChildren: Bool = false,
        secondary: Bool = false,
        passIndex: Int = 0
    ) -> [String: Any] {
        let provider = SceneRenderDescriptor.Layer(
            id: providerID, contentKind: "solid", utilityLayer: nil,
            dependencyLayerIDs: cycle ? [consumerID] : [],
            childLayerIDs: providerChildren ? [74] : [],
            visible: false,
            effects: providerEffectless ? [] : [.init(
                id: "provider-stage", file: "effects/self/data/effect.json",
                visible: providerEffectVisible, passes: [.init(
                    passIndex: 0, texturePaths: [], textureSlots: [],
                    userTextureInputs: [], combos: [:], constantShaderValues: [:]
                )]
            )]
        )
        let path = "_rt_imageLayerComposite_\(providerID)_\(secondary ? "b" : "a")"
        var slots = Array<String?>(repeating: nil, count: extraAssets ? 3 : 2)
        slots[slot] = path
        if extraAssets { slots[0] = "assets/source.png"; slots[2] = "assets/noise.png" }
        var effects: [SceneRenderDescriptor.EffectDescriptor] = [.init(
            id: "consumer-stage", file: "effects/self/display/effect.json",
            visible: consumerEffectVisible, passes: [.init(
                passIndex: passIndex, texturePaths: slots.compactMap { $0 }, textureSlots: slots,
                userTextureInputs: userOverride ? [nil, .init(kind: .path, value: "assets/override.png")] : [],
                combos: [:], constantShaderValues: [:]
            )]
        )]
        if extraEffect {
            effects.append(.init(id: "independent-stage", file: "effects/self/peer/effect.json",
                visible: true, passes: [.init(passIndex: 0, textureSlots: [nil],
                    combos: [:], constantShaderValues: [:])]))
        }
        var consumer = SceneRenderDescriptor.Layer(
            id: consumerID, contentKind: consumerKind,
            utilityLayer: consumerKind == "composition" ? .init(kind: .composition) : nil,
            dependencyLayerIDs: [providerID], childLayerIDs: puppetChildren ? [73] : [],
            visible: consumerVisible,
            effects: effects
        )
        if puppetChildren { consumer.puppetMeshPath = "models/self/body.mdl" }
        var children: [SceneRenderDescriptor.Layer] = []
        for (id, parent) in [(73, puppetChildren ? consumerID : -1),
                             (74, providerChildren ? providerID : -1)] where parent != -1 {
            var child = SceneRenderDescriptor.Layer(id: id, contentKind: "image", utilityLayer: nil,
                dependencyLayerIDs: [], childLayerIDs: [], visible: true, effects: [])
            child.parentID = parent
            children.append(child)
        }
        let order = (providerFirst ? [providerID, consumerID] : [consumerID, providerID])
            .filter { !providerMissing || $0 != providerID } + children.map(\.id)
        let descriptor = SceneRenderDescriptor(
            layers: (providerMissing ? [consumer] : [provider, consumer]) + children,
            renderOrderLayerIDs: order
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
            "utilityConsumer": consumerKind == "composition",
            "childIDs": children.map(\.id),
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
                authoredLayerIDs: [consumerID, providerID] + children.map(\.id)
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
            "image": inspect(consumerKind: "image"),
            "text": inspect(consumerKind: "text"),
            "solid": inspect(consumerKind: "solid"),
            "puppetChildren": inspect(consumerKind: "image", puppetChildren: true),
            "assetSlots": inspect(consumerKind: "image", extraAssets: true),
            "independentEffect": inspect(consumerKind: "image", extraEffect: true),
            "badUserOverride": inspect(consumerKind: "image", userOverride: true),
            "missingProvider": inspect(consumerKind: "image", providerMissing: true),
            "effectlessProvider": inspect(consumerKind: "image", providerEffectless: true),
            "providerChildren": inspect(consumerKind: "image", providerChildren: true),
            "secondary": inspect(consumerKind: "image", secondary: true),
            "wrongPass": inspect(consumerKind: "image", passIndex: 1),
            "imageUnadmitted": inspect(admitted: false, consumerKind: "image"),
            "imageForward": inspect(providerFirst: false, consumerKind: "image"),
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
        self.assertEqual(result["capturePrepared"], result["utilityConsumer"])
        self.assertTrue(result["kindSolid"])
        self.assertTrue(result["requiresProgram"])
        self.assertEqual(result["provider"], 41)
        self.assertEqual(result["slots"], ["consumer-stage:0:1"])
        self.assertEqual(result["requiredProviders"], [41])
        self.assertEqual(result["requiredGraphs"], [41])
        self.assertEqual(result["effectConsumers"], [52])
        self.assertTrue(result["blocksRawProvider"])
        self.assertFalse(result["forward"])
        self.assertEqual(result["preparationOrder"], [41, 52] + result["childIDs"])

    def test_ordinary_consumers_share_the_same_admitted_graph_carrier(self) -> None:
        for name in ("image", "text", "solid", "puppetChildren", "assetSlots", "independentEffect"):
            with self.subTest(name=name):
                result = self.results[name]
                self.assert_graph_carrier(result)
                self.assertEqual(result["currentExecution"], [41, 52])
                self.assertEqual(result["hiddenExecution"], [])

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
                     "wrongSlot", "forward", "cycle", "badUserOverride", "missingProvider",
                     "effectlessProvider", "providerChildren", "secondary", "wrongPass",
                     "imageUnadmitted", "imageForward"):
            with self.subTest(name=name):
                result = self.results[name]
                self.assertFalse(result["binding"])
                self.assertEqual(result["requiredProviders"], [])
                self.assertEqual(result["requiredGraphs"], [])


if __name__ == "__main__":
    unittest.main()
