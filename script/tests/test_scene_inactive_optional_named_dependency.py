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

SWIFT_SOURCES = list(dict.fromkeys([
    *SWIFT_SOURCES,
    Path(__file__).resolve().parents[2]
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
]))


HARNESS = r'''
import Foundation
import Metal

extension SceneOffscreenTexturePool {
    var maxDimension: Int { fatalError("GPU allocation is outside dependency planning") }
}

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
        passIndex: Int = 0,
        file: String = "effects/blend/effect.json"
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let path = "_rt_imageLayerComposite_\(namedProviderID)_\(variant)"
        var paths = Array<String?>(repeating: nil, count: slot + 1)
        paths[slot] = path
        var inputs = Array<SceneEffectTextureInput?>(
            repeating: nil, count: slot + 1
        )
        if let kind { inputs[slot] = .init(kind: kind, value: value) }
        return .init(
            id: id, file: file, visible: visible,
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
        providerAfterConsumer: Bool = false,
        providerVisible: Bool = false,
        providerEffects: [SceneRenderDescriptor.EffectDescriptor] = []
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
            childLayerIDs: providerChildren, visible: providerVisible,
            effects: providerEffects
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

    static func slotRows(_ binding: SceneDependencyRenderPlan.Binding?)
        -> [[String: Any]] {
        (binding?.referenceSlots ?? []).map {
            ["effect": $0.effectID, "pass": $0.passIndex, "slot": $0.slotIndex]
        }
    }

    static func bindingRow(_ binding: SceneDependencyRenderPlan.Binding?) -> [String: Any] {
        guard let binding else { return [:] }
        return [
            "consumer": binding.consumerLayerID, "provider": binding.providerLayerID,
            "slot": ["effect": binding.slot.effectID,
                     "pass": binding.slot.passIndex, "slot": binding.slot.slotIndex],
            "referenceSlots": slotRows(binding), "blendMode": binding.blendMode,
            "kind": String(describing: binding.kind),
            "requiresForwardCapture": binding.requiresForwardCapture,
            "requiresProgram": binding.requiresResolvedMaterialProgram,
        ]
    }

    static func inspect(
        _ descriptor: SceneRenderDescriptor,
        admittedReferences: Set<SceneDependencyRenderPlan.Reference>? = nil
    ) -> [String: Any] {
        let direct = SceneDependencyGraphAnalysis.references(
            in: descriptor.layers
        )
        let potential = SceneDependencyGraphAnalysis
            .potentialNamedReferences(in: descriptor.layers)
        let visible = Set(descriptor.layers.filter { $0.visible != false }.map(\.id))
        let carriers = SceneDependencyRenderPlan
            .potentialNamedBindings(
                descriptor: descriptor, visibleLayerIDs: visible
            )[consumerID] ?? []
        let plan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: visible
        )
        let admittedPlan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: visible,
            admittedResolvedMaterialReferences: admittedReferences
                ?? Set(direct + potential)
        )
        let runtimeBinding = plan.bindingsByConsumerLayerID[consumerID]
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
            "runtimeKind": runtimeBinding.map { String(describing: $0.kind) } ?? "none",
            "runtimeIdentity": bindingRow(runtimeBinding),
            "runtimeSlots": slotRows(runtimeBinding),
            "carrierKinds": carriers.map { String(describing: $0.kind) },
            "carrierIdentities": carriers.map { bindingRow($0) },
            "productEdges": (edges[consumerID] ?? []).sorted(),
            "admittedReferenceEffects": admittedBinding?.referenceSlots
                .map(\.effectID) ?? [],
            "admittedRequiresProgram": admittedBinding?
                .requiresResolvedMaterialProgram ?? false,
            "admittedForwardCapture": admittedBinding?
                .requiresForwardCapture ?? false,
            "admittedProviders": admittedPlan.requiredProviderLayerIDs.sorted(),
            "admittedGraphProviders": admittedPlan.requiredGraphOutputProviderLayerIDs.sorted(),
            "admittedKind": admittedBinding.map { String(describing: $0.kind) } ?? "none",
            "admittedIdentity": bindingRow(admittedBinding),
            "admittedSlots": slotRows(admittedBinding),
            "admittedEffectConsumers": admittedPlan.requiredEffectConsumerLayerIDs.sorted(),
        ]
    }

    // Resource names are deliberately unrelated to the stock blend declaration.
    // The provider is visible and effectful, so only graph-final publication is safe.
    static func graphDescriptor(
        ids: [String] = ["z-direct", "m-current", "a-previous"],
        resource: String = "effects/owned/cover-select/effect.json",
        optionalProviderID: Int = providerID,
        optionalSlot: Int = 1,
        optionalPass: Int = 0,
        forward: Bool = false,
        effectOrder: [Int] = [0, 1, 2]
    ) -> SceneRenderDescriptor {
        let effects = [
            effect(id: ids[0], visible: true, kind: nil, file: resource),
            effect(id: ids[1], file: resource),
            effect(id: ids[2], visible: true, value: "$mediaPreviousThumbnail",
                   namedProviderID: optionalProviderID, slot: optionalSlot,
                   passIndex: optionalPass, file: resource),
        ]
        return descriptor(effects: effectOrder.map { effects[$0] },
           providerAfterConsumer: forward, providerVisible: true,
           providerEffects: [.init(id: "provider-tint",
               file: "effects/tint/effect.json", visible: true, passes: [])])
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
        var payload = cases.mapValues { inspect($0) }
        let graph = graphDescriptor()
        let direct = SceneDependencyGraphAnalysis.references(in: graph.layers)
        let potential = SceneDependencyGraphAnalysis.potentialNamedReferences(in: graph.layers)
        payload["graphThree"] = inspect(graph)
        payload["graphRenamed"] = inspect(graphDescriptor(
            ids: ["stage-80", "stage-04", "stage-57"],
            resource: "effects/renamed/independent-resource/effect.json"
        ))
        payload["graphNoProgram"] = inspect(graph, admittedReferences: [])
        payload["graphOnlyCurrentAdmitted"] = inspect(graph,
            admittedReferences: Set(direct + potential.filter { $0.slot.effectID == "m-current" }))
        for (name, bad) in [
            ("graphForeignAdmission", SceneDependencyRenderPlan.Reference(
                consumerLayerID: consumerID, providerLayerID: 999,
                slot: potential[0].slot, variant: .primary)),
            ("graphWrongSlotAdmission", .init(
                consumerLayerID: consumerID, providerLayerID: providerID,
                slot: .init(effectID: potential[0].slot.effectID, passIndex: 0, slotIndex: 2),
                variant: .primary)),
        ] {
            payload[name] = inspect(graph, admittedReferences: Set(direct + [bad]))
        }
        payload["graphForward"] = inspect(graphDescriptor(forward: true))
        payload["graphWrongProvider"] = inspect(graphDescriptor(optionalProviderID: 999))
        payload["graphWrongSlot"] = inspect(graphDescriptor(optionalSlot: 2))
        payload["graphWrongPass"] = inspect(graphDescriptor(optionalPass: 1))
        payload["graphOptionalBeforeDirect"] = inspect(graphDescriptor(
            ids: ["direct-b", "optional-a", "unused"], effectOrder: [1, 0]))
        payload["graphUniqueOptional"] = inspect(graphDescriptor(
            ids: ["unused", "only-optional", "unused-peer"], effectOrder: [1]))
        // Call the production helper directly with deliberately inconsistent
        // effect metadata; this is not a claim that author parsing emits it.
        let consumer = graph.layers.first { $0.id == consumerID }!
        let layersByID = Dictionary(uniqueKeysWithValues: graph.layers.map { ($0.id, $0) })
        let pair = direct + [potential[0]]
        let control = SceneDependencyRenderPlan.visibleImageGraphOutputReferences(
            layer: consumer, visibleEffects: Array(consumer.effects.prefix(2)),
            references: pair, layersByID: layersByID,
            visibleLayerIDs: [providerID, consumerID])
        let duplicate = SceneDependencyRenderPlan.visibleImageGraphOutputReferences(
            layer: consumer, visibleEffects: [consumer.effects[0], consumer.effects[0]],
            references: pair, layersByID: layersByID,
            visibleLayerIDs: [providerID, consumerID])
        payload["graphDuplicateEffectMissingSibling"] = [
            "controlEffects": control?.map { $0.slot.effectID } ?? [],
            "rejected": duplicate == nil,
        ]
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

    def test_visible_effectful_provider_keeps_exact_optional_carriers(self) -> None:
        for name, ids in (
            ("graphThree", ["z-direct", "m-current", "a-previous"]),
            ("graphRenamed", ["stage-80", "stage-04", "stage-57"]),
        ):
            row = self.results[name]
            with self.subTest(name=name, boundary="base"):
                self.assertEqual(row["runtimeKind"], "visibleImageGraphOutput")
                self.assertEqual(row["runtimeSlots"], [
                    {"effect": ids[0], "pass": 0, "slot": 1}
                ])
                self.assertFalse(row["runtimeRequiresProgram"])
                self.assertEqual(row["runtimeProviders"], [101])
                self.assertEqual(row["runtimeGraphProviders"], [101])
                self.assertEqual([ref["effect"] for ref in row["potential"]], ids[1:])
            with self.subTest(name=name, boundary="potential"):
                self.assertEqual(len(row["carriers"]), 2)
                self.assertEqual(row["carrierKinds"], ["visibleImageGraphOutput"] * 2)
                self.assertEqual({carrier["effect"] for carrier in row["carriers"]}, set(ids[1:]))
                for carrier in row["carriers"]:
                    self.assertEqual(carrier, {
                        "consumer": 202, "provider": 101, "effect": carrier["effect"],
                        "pass": 0, "slot": 1, "requiresProgram": True,
                        "referenceEffects": [carrier["effect"]],
                    })
        unique = self.results["graphUniqueOptional"]
        only_slot = {"effect": "only-optional", "pass": 0, "slot": 1}
        self.assertEqual(unique["runtimeIdentity"], {})
        self.assertEqual(unique["carrierIdentities"], [{
            "consumer": 202, "provider": 101, "slot": only_slot,
            "referenceSlots": [only_slot], "blendMode": 0,
            "kind": "visibleImageGraphOutput", "requiresForwardCapture": False,
            "requiresProgram": True,
        }])
        self.assertEqual(unique["admittedIdentity"], unique["carrierIdentities"][0])

    def test_admitted_visible_graph_slots_preserve_author_order_and_one_provider(self) -> None:
        # This seam represents an already-proved Program's exact references;
        # it does not prove Program compilation, media readiness or activation.
        for name, ids in (
            ("graphThree", ["z-direct", "m-current", "a-previous"]),
            ("graphRenamed", ["stage-80", "stage-04", "stage-57"]),
            ("graphOnlyCurrentAdmitted", ["z-direct", "m-current"]),
        ):
            with self.subTest(name=name):
                row = self.results[name]
                self.assertEqual(row["admittedKind"], "visibleImageGraphOutput")
                self.assertEqual(row["admittedSlots"], [
                    {"effect": effect, "pass": 0, "slot": 1} for effect in ids
                ])
                self.assertTrue(row["admittedRequiresProgram"])
                self.assertFalse(row["admittedForwardCapture"])
                self.assertEqual(row["admittedProviders"], [101])
                self.assertEqual(row["admittedGraphProviders"], [101])
                self.assertEqual(row["admittedEffectConsumers"], [202])
        for name in ("graphNoProgram", "graphForeignAdmission", "graphWrongSlotAdmission"):
            with self.subTest(name=name):
                self.assertEqual(self.results[name]["admittedSlots"], [
                    {"effect": "z-direct", "pass": 0, "slot": 1}
                ])
                self.assertFalse(self.results[name]["admittedRequiresProgram"])
        for name in ("graphWrongProvider", "graphWrongSlot", "graphWrongPass"):
            with self.subTest(name=name):
                self.assertNotIn("a-previous", self.results[name]["admittedReferenceEffects"])
                self.assertTrue(all(carrier["effect"] != "a-previous"
                                    for carrier in self.results[name]["carriers"]))
        forward = self.results["graphForward"]
        self.assertEqual(forward["carriers"], [])
        self.assertEqual(forward["runtimeSlots"], [])
        self.assertEqual(forward["admittedSlots"], [])
        duplicate = self.results["graphDuplicateEffectMissingSibling"]
        self.assertEqual(duplicate["controlEffects"], ["z-direct", "m-current"])
        self.assertTrue(duplicate["rejected"])
        before = self.results["graphOptionalBeforeDirect"]
        direct_slot = {"effect": "direct-b", "pass": 0, "slot": 1}
        optional_slot = {"effect": "optional-a", "pass": 0, "slot": 1}
        expected_base = {
            "consumer": 202, "provider": 101, "slot": direct_slot,
            "referenceSlots": [direct_slot], "blendMode": 0,
            "kind": "visibleImageGraphOutput", "requiresForwardCapture": False,
            "requiresProgram": False,
        }
        self.assertEqual(before["runtimeIdentity"], expected_base)
        self.assertEqual(before["admittedIdentity"], {
            **expected_base, "referenceSlots": [optional_slot, direct_slot],
            "requiresProgram": True,
        })

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
