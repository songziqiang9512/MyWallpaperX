#!/usr/bin/env python3
"""Descriptor-only optional fallbacks survive an inactive authored stage."""

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
    static let providerID = 101
    static let consumerID = 202

    static func effect(
        id: String = "optional-stage",
        visible: Bool = false,
        kind: SceneEffectTextureInput.Kind? = .system,
        value: String = "$mediaThumbnail",
        namedProviderID: Int = providerID,
        variant: String = "a",
        slot: Int = 1,
        passIndex: Int = 0
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let path = "_rt_imageLayerComposite_\(namedProviderID)_\(variant)"
        var paths = Array<String?>(repeating: nil, count: slot + 1)
        paths[slot] = path
        var inputs = Array<SceneEffectTextureInput?>(
            repeating: nil, count: slot + 1
        )
        if let kind { inputs[slot] = .init(kind: kind, value: value) }
        return .init(
            id: id, file: "effects/blend/effect.json", visible: visible,
            passes: [.init(
                passIndex: passIndex, texturePaths: [path], textureSlots: paths,
                userTextureInputs: kind == nil ? [] : inputs,
                combos: ["BLENDMODE": 0],
                constantShaderValues: [
                    "alpha": .init(components: [1]),
                    "multiply": .init(components: [1]),
                ]
            )]
        )
    }

    static func descriptor(
        effects: [SceneRenderDescriptor.EffectDescriptor],
        includeProvider: Bool = true,
        providerChildren: [Int] = [],
        providerDependencies: [Int] = [],
        declaredDependencies: [Int]? = nil,
        consumerKind: String = "image",
        providerAfterConsumer: Bool = false
    ) -> SceneRenderDescriptor {
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID, contentKind: consumerKind, utilityLayer: nil,
            dependencyLayerIDs: declaredDependencies ?? [providerID],
            childLayerIDs: [],
            visible: true, effects: effects
        )
        let provider = SceneRenderDescriptor.Layer(
            id: providerID, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: providerDependencies,
            childLayerIDs: providerChildren, visible: false, effects: []
        )
        return .init(
            layers: includeProvider ? [provider, consumer] : [consumer],
            renderOrderLayerIDs: includeProvider
                ? (providerAfterConsumer
                    ? [consumerID, providerID] : [providerID, consumerID])
                : [consumerID]
        )
    }

    static func referenceRow(
        _ reference: SceneDependencyRenderPlan.Reference
    ) -> [String: Any] {
        [
            "consumer": reference.consumerLayerID,
            "provider": reference.providerLayerID,
            "effect": reference.slot.effectID,
            "pass": reference.slot.passIndex,
            "slot": reference.slot.slotIndex,
            "primary": reference.variant == .primary,
        ]
    }

    static func inspect(_ descriptor: SceneRenderDescriptor) -> [String: Any] {
        let direct = SceneDependencyGraphAnalysis.references(
            in: descriptor.layers
        )
        let potential = SceneDependencyGraphAnalysis
            .potentialNamedReferences(in: descriptor.layers)
        let carriers = SceneDependencyRenderPlan
            .potentialNamedBindings(
                descriptor: descriptor, visibleLayerIDs: [consumerID]
            )[consumerID] ?? []
        let plan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: [consumerID]
        )
        let admittedPlan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: [consumerID],
            admittedResolvedMaterialReferences: Set(direct + potential)
        )
        let admittedBinding = admittedPlan.bindingsByConsumerLayerID[consumerID]
        let edges = SceneDependencyRenderPlan.productDependencyEdges(
            layers: descriptor.layers,
            references: direct,
            productReferences: direct,
            potentialReferences: Set(potential),
            admittedPotentialReferences: []
        )
        return [
            "allDirect": SceneNamedTextureDependencyReferenceAnalysis.references(
                in: descriptor.layers, includingInactiveEffects: true).map { ["provider": $0.providerLayerID] },
            "direct": direct.map(referenceRow),
            "potential": potential.map(referenceRow),
            "carriers": carriers.map { binding -> [String: Any] in
                [
                    "consumer": binding.consumerLayerID,
                    "provider": binding.providerLayerID,
                    "effect": binding.slot.effectID,
                    "pass": binding.slot.passIndex,
                    "slot": binding.slot.slotIndex,
                    "requiresProgram": binding.requiresResolvedMaterialProgram,
                    "referenceEffects": binding.referenceSlots.map(\.effectID),
                ]
            },
            "runtimeReferences": plan.references.map(referenceRow),
            "runtimeBindings": plan.bindingsByConsumerLayerID.values
                .map { $0.slot.effectID }.sorted(),
            "runtimeRequiresProgram": plan.bindingsByConsumerLayerID[consumerID]?
                .requiresResolvedMaterialProgram ?? false,
            "runtimeProviders": plan.requiredProviderLayerIDs.sorted(),
            "runtimeGraphProviders": plan.requiredGraphOutputProviderLayerIDs.sorted(),
            "productEdges": (edges[consumerID] ?? []).sorted(),
            "admittedReferenceEffects": admittedBinding?.referenceSlots
                .map(\.effectID) ?? [],
            "admittedRequiresProgram": admittedBinding?
                .requiresResolvedMaterialProgram ?? false,
            "admittedForwardCapture": admittedBinding?
                .requiresForwardCapture ?? false,
            "admittedProviders": admittedPlan.requiredProviderLayerIDs.sorted(),
            "admittedEffectConsumers": admittedPlan.requiredEffectConsumerLayerIDs.sorted(),
        ]
    }

    static func main() throws {
        let cases: [String: SceneRenderDescriptor] = [
            "inactiveSystem": descriptor(effects: [effect()]),
            "inactiveProperty": descriptor(effects: [effect(
                kind: .property, value: "cover-file"
            )]),
            "activeSystem": descriptor(effects: [effect(visible: true)]),
            "activeDirect": descriptor(effects: [effect(
                id: "direct-stage", visible: true, kind: nil
            )]),
            "inactiveDirect": descriptor(effects: [effect(kind: nil)]),
            "activeDirectWithInactiveDirect": descriptor(effects: [
                effect(id: "direct-stage", visible: true, kind: nil),
                effect(id: "inactive-direct", kind: nil),
                effect(),
            ]),
            "activeDirectWithInactiveOptional": descriptor(effects: [
                effect(id: "direct-stage", visible: true, kind: nil),
                effect(),
            ]),
            "forwardDirectWithInactiveOptional": descriptor(effects: [
                effect(id: "direct-stage", visible: true, kind: nil),
                effect(),
            ], providerAfterConsumer: true),
            "missingProvider": descriptor(
                effects: [effect()], includeProvider: false
            ),
            "wrongProvider": descriptor(
                effects: [effect()], declaredDependencies: [303]
            ),
            "secondary": descriptor(effects: [effect(variant: "b")]),
            "unsupportedPath": descriptor(effects: [effect(
                kind: .path, value: "materials/cover.png"
            )]),
            "unsupportedKind": descriptor(effects: [effect(kind: .unknown)]),
            "emptyOptional": descriptor(effects: [effect(value: "")]),
            "unsupportedSlot": descriptor(effects: [effect(slot: 0)]),
            "unsupportedPass": descriptor(effects: [effect(passIndex: 1)]),
            "providerChildren": descriptor(
                effects: [effect()], providerChildren: [404]
            ),
            "providerCycle": descriptor(
                effects: [effect()], providerDependencies: [consumerID]
            ),
            "unsupportedConsumer": descriptor(
                effects: [effect()], consumerKind: "particle"
            ),
        ]
        let payload = cases.mapValues(inspect)
        let data = try JSONSerialization.data(withJSONObject: payload)
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneInactiveOptionalNamedDependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-inactive-optional-"
        )
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "inactive-optional"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(binary),
            ],
            capture_output=True, text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        environment = os.environ.copy()
        environment.pop("MWX_SCENE_NAMED_PROVIDER_ROUTE", None)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True,
            env=environment,
        )
        cls.results = json.loads(completed.stdout)
        environment["MWX_SCENE_NAMED_PROVIDER_ROUTE"] = "disable-generic"
        disabled = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True,
            env=environment,
        )
        cls.disabled_results = json.loads(disabled.stdout)

    def test_inactive_optional_stage_keeps_exact_potential_carrier(self) -> None:
        expected_reference = {
            "consumer": 202, "provider": 101, "effect": "optional-stage",
            "pass": 0, "slot": 1, "primary": True,
        }
        expected_carrier = {
            "consumer": 202, "provider": 101, "effect": "optional-stage",
            "pass": 0, "slot": 1, "requiresProgram": True,
            "referenceEffects": ["optional-stage"],
        }
        for name in ("inactiveSystem", "inactiveProperty", "activeSystem"):
            with self.subTest(name=name):
                self.assertEqual(self.results[name]["potential"], [expected_reference])
                self.assertEqual(self.results[name]["carriers"], [expected_carrier])
                self.assertEqual(
                    self.results[name]["admittedReferenceEffects"], ["optional-stage"]
                )
                self.assertTrue(self.results[name]["admittedRequiresProgram"])
                self.assertEqual(self.results[name]["admittedProviders"], [101])
                self.assertEqual(self.results[name]["admittedEffectConsumers"], [202])

    def test_descriptor_candidates_do_not_grant_product_authority(self) -> None:
        for name in ("inactiveSystem", "inactiveProperty", "activeSystem"):
            for field in (
                "direct", "runtimeReferences", "runtimeBindings",
                "runtimeProviders", "runtimeGraphProviders", "productEdges",
            ):
                with self.subTest(name=name, field=field):
                    self.assertEqual(self.results[name][field], [])

    def test_active_direct_owner_keeps_its_exact_slot(self) -> None:
        direct = self.results["activeDirect"]
        self.assertEqual([row["effect"] for row in direct["direct"]], ["direct-stage"])
        self.assertEqual(direct["runtimeBindings"], ["direct-stage"])
        self.assertFalse(direct["runtimeRequiresProgram"])
        self.assertEqual(direct["runtimeProviders"], [101])
        self.assertEqual(direct["potential"], [])
        mixed = self.results["activeDirectWithInactiveOptional"]
        self.assertEqual(mixed["direct"], direct["direct"])
        self.assertEqual(mixed["runtimeBindings"], direct["runtimeBindings"])
        self.assertFalse(mixed["runtimeRequiresProgram"])
        self.assertEqual(mixed["productEdges"], [101])
        self.assertEqual(
            [row["effect"] for row in mixed["carriers"]], ["optional-stage"]
        )
        self.assertEqual(
            mixed["carriers"][0]["referenceEffects"], ["optional-stage"]
        )
        self.assertTrue(mixed["carriers"][0]["requiresProgram"])
        for name in (
            "activeDirectWithInactiveOptional", "forwardDirectWithInactiveOptional",
        ):
            with self.subTest(name=name):
                self.assertEqual(
                    self.results[name]["runtimeBindings"], ["direct-stage"]
                )
                self.assertEqual(
                    self.results[name]["admittedReferenceEffects"],
                    ["direct-stage", "optional-stage"],
                )
                self.assertTrue(self.results[name]["admittedRequiresProgram"])
                self.assertEqual(self.results[name]["admittedProviders"], [101])
                self.assertEqual(self.results[name]["admittedEffectConsumers"], [202])
        self.assertFalse(mixed["admittedForwardCapture"])
        self.assertTrue(
            self.results["forwardDirectWithInactiveOptional"]["admittedForwardCapture"]
        )
        for field in ("direct", "runtimeBindings", "productEdges"):
            self.assertEqual(self.results["inactiveDirect"][field], [])

    def test_inactive_direct_uses_candidate_admission(self) -> None:
        inactive = self.results["inactiveDirect"]
        self.assertEqual(len(inactive["potential"]), 1)
        self.assertEqual(len(inactive["carriers"]), 1)
        self.assertEqual(inactive["admittedReferenceEffects"], ["optional-stage"])
        mixed = self.results["activeDirectWithInactiveDirect"]
        self.assertEqual(mixed["runtimeBindings"], ["direct-stage"])
        self.assertEqual(mixed["admittedReferenceEffects"],
                         ["direct-stage", "inactive-direct", "optional-stage"])
        self.assertTrue(mixed["admittedRequiresProgram"])

    def test_inactive_direct_reference_can_reserve_material_source_ownership(self) -> None:
        self.assertEqual(self.results["inactiveDirect"]["direct"], [])
        self.assertEqual(len(self.results["inactiveDirect"]["allDirect"]), 1)
        self.assertEqual(self.results["inactiveDirect"]["allDirect"][0]["provider"], 101)
        self.assertEqual(self.results["inactiveSystem"]["allDirect"], [])
        self.assertEqual(len(self.results["inactiveSystem"]["potential"]), 1)

    def test_invalid_candidates_and_disabled_route_keep_rejecting(self) -> None:
        for name in (
            "missingProvider", "wrongProvider", "secondary", "unsupportedSlot",
            "unsupportedPass", "providerChildren", "providerCycle", "unsupportedConsumer",
            "unsupportedPath", "unsupportedKind", "emptyOptional",
        ):
            with self.subTest(name=name):
                self.assertEqual(self.results[name]["carriers"], [])
                self.assertEqual(self.results[name]["admittedReferenceEffects"], [])
        for name in ("unsupportedPath", "unsupportedKind", "emptyOptional"):
            self.assertEqual(self.results[name]["potential"], [])
        for name in ("inactiveSystem", "inactiveProperty", "activeSystem"):
            self.assertEqual(self.disabled_results[name]["carriers"], [])
            self.assertEqual(self.disabled_results[name]["runtimeBindings"], [])


if __name__ == "__main__":
    unittest.main()
