#!/usr/bin/env python3
"""Cold named source candidates and typed final Plan demand remain distinct."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

try:
    from script.tests.scene.test_scene_dependency_render_plan import SWIFT_SOURCES
except ImportError:
    from script.tests.scene.test_scene_dependency_render_plan import SWIFT_SOURCES

SWIFT_SOURCES = list(dict.fromkeys([
    *SWIFT_SOURCES,
    Path(__file__).resolve().parents[3]
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
]))


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
        providerKind: String = "image",
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
            id: providerID, contentKind: providerKind, utilityLayer: nil,
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
        admittedReferences: Set<SceneDependencyRenderPlan.Reference>? = nil,
        consumer: Int = consumerID,
        sourceAfter: [Int: Int] = [:],
        executionOrder: [Int]? = nil,
        previousEligible: Set<Int> = [],
        previousIneligibleConsumers: Set<Int> = [],
        excluded: [Int: Set<SceneEffectPassSlot>] = [:]
    ) -> [String: Any] {
        let consumerID = consumer
        let direct = SceneDependencyGraphAnalysis.references(
            in: descriptor.layers
        )
        let potential = SceneDependencyGraphAnalysis
            .potentialNamedReferences(in: descriptor.layers)
        let visible = Set(descriptor.layers.filter { $0.visible != false }.map(\.id))
        let allCarriers = SceneDependencyRenderPlan
            .potentialNamedBindings(
                descriptor: descriptor, visibleLayerIDs: visible
            )
        let carriers = allCarriers[consumerID] ?? []
        let plan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: visible
        )
        // The Set parameter is a cold auxiliary seam, not Program execution authority.
        let admittedPlan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: visible,
            admittedResolvedMaterialReferences: admittedReferences
                ?? Set(direct + potential)
        )
        // Typed selection input only. Program compilation/readiness is covered
        // by the real Program/GraphExecutor gates, not by these descriptor rows.
        let selected = admittedReferences ?? Set(direct + potential)
        let preparedInputs = Dictionary(uniqueKeysWithValues: descriptor.layers.map { layer in
            (layer.id, (allCarriers[layer.id] ?? []).filter {
                selected.contains(.init(consumerLayerID: $0.consumerLayerID,
                    providerLayerID: $0.providerLayerID, slot: $0.slot, variant: .primary))
            })
        })
        let preparedPlan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: visible,
            preparedNamedInputBindingsByConsumerLayerID: preparedInputs
        )
        let preparedVector = preparedPlan.multiProviderAggregatesByConsumerLayerID[consumerID]?.bindings
            ?? preparedPlan.bindingsByConsumerLayerID[consumerID].map { [$0] } ?? []
        let preparedSlots: [[String: Any]] = preparedVector.flatMap { slotRows($0) }
        let directAdmittedPlan = SceneDependencyRenderPlan(
            descriptor: descriptor, visibleLayerIDs: visible,
            admittedResolvedMaterialReferences: Set(direct)
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
        var result: [String: Any] = [
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
            "runtimeAggregateConsumers": plan.multiProviderAggregatesByConsumerLayerID.keys.sorted(),
            "runtimeRequiresProgram": plan.bindingsByConsumerLayerID[consumerID]?
                .requiresResolvedMaterialProgram ?? false,
            "runtimeProviders": plan.requiredProviderLayerIDs.sorted(),
            "runtimeGraphProviders": plan.requiredGraphOutputProviderLayerIDs.sorted(),
            "runtimeKind": runtimeBinding.map { String(describing: $0.kind) } ?? "none",
            "runtimeIdentity": bindingRow(runtimeBinding),
            "directAdmittedIdentity": bindingRow(
                directAdmittedPlan.bindingsByConsumerLayerID[consumerID]),
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
        result["preparedSlots"] = preparedSlots
        result["preparedProviders"] = preparedPlan.requiredProviderLayerIDs.sorted()
        result["preparedGraphProviders"] = preparedPlan.requiredGraphOutputProviderLayerIDs.sorted()
        result["preparedEffects"] = preparedVector.flatMap(\.referenceSlots).map(\.effectID)
        result["preparedRequiresProgram"] = preparedVector.allSatisfy(\.requiresResolvedMaterialProgram)
        result["preparedForward"] = preparedVector.map(\.requiresForwardCapture)
        result["preparedEffectConsumers"] = preparedPlan.requiredEffectConsumerLayerIDs.sorted()
        result["allPreparedBindings"] = preparedPlan.bindingsByConsumerLayerID.values
            .sorted { $0.consumerLayerID < $1.consumerLayerID }.map { bindingRow($0) }
        let graphs = Set(descriptor.layers.filter { $0.effects.contains { $0.visible != false } }.map(\.id))
        if let sources = preparedPlan.sourcePreparationPlan(
            authoredLayerIDs: executionOrder ?? descriptor.renderOrderLayerIDs, availableExecutionLayerIDs: graphs,
            visibleRootLayerIDs: visible, activeStaticModelConsumerLayerIDs: [],
            sourceAfterLayerIDByLayerID: sourceAfter,
            previousEligibleProviderLayerIDs: previousEligible,
            previousIneligibleConsumerLayerIDs: previousIneligibleConsumers) {
            let schedule = sources.preparationSchedule(excludingSlotsByConsumerLayerID: excluded)
            result["schedule"] = ["preparation": schedule.preparationLayerIDs,
                "prepass": schedule.prepassProviderLayerIDs,
                "scheduled": schedule.scheduledGraphProviderLayerIDs.sorted(),
                "before": Dictionary(uniqueKeysWithValues:
                    schedule.providersBeforeLayerID.map { (String($0.key), $0.value) })] as [String: Any]
            result["previousProviders"] = schedule.previousProviderLayerIDs.sorted()
            result["previousConsumers"] = Dictionary(uniqueKeysWithValues:
                schedule.previousProvidersByConsumerLayerID.map { (String($0.key), $0.value.sorted()) })
        }
        return result
    }

    static func compositionNamedCuts(renamed: Bool, arm: String) -> [String: Any] {
        let p = renamed ? 719 : 101, c = renamed ? 354 : 202, d = renamed ? 912 : 303
        let trigger = renamed ? 802 : 410
        let bridge = renamed ? 815 : 411
        let resource = renamed ? "effects/alternate/canvas/effect.json" : "effects/owned/paint/effect.json"
        let early = effect(id: renamed ? "early-relabel" : "early", visible: true,
            kind: nil, namedProviderID: p, file: resource)
        let second = effect(id: renamed ? "alternate-slot" : "second", visible: true,
            kind: nil, namedProviderID: p, slot: 3, file: resource)
        let late = effect(id: renamed ? "late-relabel" : "late", visible: true,
            kind: nil, namedProviderID: p, file: resource)
        var utility = SceneUtilityLayer(kind: .composition)
        utility.copyBackground = !arm.hasPrefix("transparent")
        if arm.hasSuffix("framebuffer") { utility.framebufferSource = "shaders/alternate" }
        var provider = SceneRenderDescriptor.Layer(id: p, contentKind: "composition",
            utilityLayer: utility, dependencyLayerIDs: [],
            childLayerIDs: arm == "members" ? [trigger] : [], visible: arm.hasSuffix("provider-visible"),
            effects: [.init(id: "producer", file: resource, visible: true, passes: [])])
        if arm == "nested-provider" { provider.parentID = trigger }
        let consumer = SceneRenderDescriptor.Layer(id: c, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [p], childLayerIDs: [], visible: arm != "hidden-chain",
            effects: [early, second])
        let later = SceneRenderDescriptor.Layer(id: d, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [p], childLayerIDs: [],
            visible: !["early-only", "all-inactive", "hidden-chain"].contains(arm),
            effects: [late])
        let mark = SceneRenderDescriptor.Layer(id: trigger, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [], childLayerIDs: [], visible: true, effects: [])
        let downstream = SceneRenderDescriptor.Layer(id: bridge, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [c], childLayerIDs: [], visible: true,
            effects: [effect(id: "downstream", visible: true, kind: nil, namedProviderID: c, file: resource)])
        let layers = [provider, consumer, mark, later] + (arm == "hidden-chain" ? [downstream] : [])
        let order: [Int] = (arm == "expanded" ? [p, c, trigger, d] : [c, trigger, p, d])
            + (arm == "hidden-chain" ? [bridge] : [])
        let executionOrder = arm == "expanded" ? [c, trigger, p, d] : order
        let descriptor = SceneRenderDescriptor(layers: layers, renderOrderLayerIDs: order)
        let eligible: Set<Int> = arm == "not-eligible" ? [] : [p]
        let excluded: Set<SceneEffectPassSlot>
        switch arm {
        case "one-off":
            excluded = [.init(effectID: early.id, passIndex: 0, slotIndex: 1)]
        case "both-off", "all-inactive":
            excluded = [.init(effectID: early.id, passIndex: 0, slotIndex: 1),
                .init(effectID: second.id, passIndex: 0, slotIndex: 3)]
        default:
            excluded = []
        }
        var row = inspect(descriptor, consumer: c, sourceAfter: [p: p],
            executionOrder: executionOrder, previousEligible: eligible,
            previousIneligibleConsumers: arm == "different-attachment" ? [c] : [],
            excluded: [c: excluded])
        row["provider"] = p; row["early"] = c; row["late"] = d; row["bridge"] = bridge
        return row
    }

    static func forwardVisibleChain(
        puppet: Bool = false, renamed: Bool = false, fault: String = "none"
    ) -> [String: Any] {
        let p = renamed ? 719 : 101, c = renamed ? 354 : 202, d = renamed ? 912 : 303
        let early = renamed ? "renamed-early" : "early", late = renamed ? "renamed-late" : "late"
        let resource = renamed ? "effects/alternate/layer-mix/effect.json" : "effects/owned/mix/effect.json"
        let providerSource = fault == "background" ? "_rt_FullFrameBuffer" : "textures/independent-color.png"
        var provider = SceneRenderDescriptor.Layer(id: p, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [], childLayerIDs: [], visible: true,
            effects: [.init(id: renamed ? "renamed-source" : "source", file: resource, visible: true,
                passes: [.init(passIndex: 0, texturePaths: [providerSource], textureSlots: [providerSource],
                    userTextureInputs: [], combos: [:], constantShaderValues: [:])])])
        if puppet { provider.puppetMeshPath = renamed ? "models/alternate-pose.mdl" : "models/pose.mdl" }
        let consumer = SceneRenderDescriptor.Layer(id: c, contentKind: "text", utilityLayer: nil,
            dependencyLayerIDs: [p], childLayerIDs: [], visible: true,
            effects: [effect(id: early, visible: true, kind: nil, namedProviderID: p,
                variant: fault == "secondary" ? "b" : "a", file: resource)])
        let later = SceneRenderDescriptor.Layer(id: d, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [p], childLayerIDs: [], visible: true,
            effects: [effect(id: late, visible: true, kind: nil, namedProviderID: p, file: resource)])
        let layers = fault == "missing" ? [consumer, later] : [consumer, provider, later]
        let descriptor = SceneRenderDescriptor(layers: layers, renderOrderLayerIDs: layers.map(\.id))
        var selected = Set(SceneDependencyGraphAnalysis.references(in: descriptor.layers))
        if fault == "no-program" { selected = [] }
        if fault == "wrong-slot", let reference = selected.first(where: { $0.consumerLayerID == c }) {
            selected.remove(reference)
            selected.insert(.init(consumerLayerID: c, providerLayerID: p,
                slot: .init(effectID: early, passIndex: 0, slotIndex: 2), variant: .primary))
        }
        var row = inspect(descriptor, admittedReferences: selected, consumer: c,
            sourceAfter: fault == "background" ? [p: p] : [:])
        row["provider"] = p; row["early"] = c; row["late"] = d
        row["sourceIndependent"] = SceneDependencyRenderPlan.providerGraphIsAuthoredOrderIndependent(provider)
        return row
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

    // A static text publication uses the same generic image carrier as an
    // ordinary image. Resource names deliberately avoid the legacy Blend route.
    static func genericDescriptor(
        consumerKind: String = "text",
        providerKind: String = "text",
        ids: [String] = ["dormant-mask", "active-mask"],
        resource: String = "effects/owned/text-mask/effect.json",
        effectOrder: [Int] = [0, 1]
    ) -> SceneRenderDescriptor {
        let effects = [
            effect(id: ids[0], kind: nil, file: resource),
            effect(id: ids[1], visible: true, kind: nil, file: resource),
        ]
        return descriptor(effects: effectOrder.map { effects[$0] },
            consumerKind: consumerKind, providerKind: providerKind,
            providerVisible: true)
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
            "solidConsumer": descriptor(effects: [effect()], consumerKind: "solid"),
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
        for puppet in [false, true] {
            for renamed in [false, true] {
                payload["forward-\(puppet)-\(renamed)"] = forwardVisibleChain(puppet: puppet, renamed: renamed)
            }
        }
        for fault in ["no-program", "wrong-slot", "secondary", "missing", "background"] {
            payload["forward-\(fault)"] = forwardVisibleChain(puppet: true, fault: fault)
        }
        for arm in ["both", "expanded", "early-only", "one-off", "both-off", "all-inactive", "hidden-chain",
                    "not-eligible", "different-attachment", "provider-visible", "transparent",
                    "members", "nested-provider", "framebuffer", "transparent-framebuffer",
                    "transparent-provider-visible"] {
            for renamed in [false, true] {
                payload["composition-\(arm)-\(renamed)"] = compositionNamedCuts(renamed: renamed, arm: arm)
            }
        }
        payload["graphWrongProvider"] = inspect(graphDescriptor(optionalProviderID: 999))
        payload["graphWrongSlot"] = inspect(graphDescriptor(optionalSlot: 2))
        payload["graphWrongPass"] = inspect(graphDescriptor(optionalPass: 1))
        payload["graphOptionalBeforeDirect"] = inspect(graphDescriptor(
            ids: ["direct-b", "optional-a", "unused"], effectOrder: [1, 0]))
        payload["graphUniqueOptional"] = inspect(graphDescriptor(
            ids: ["unused", "only-optional", "unused-peer"], effectOrder: [1]))
        let generic = genericDescriptor()
        payload["textInactiveBeforeDirect"] = inspect(generic)
        payload["imageInactiveBeforeDirect"] = inspect(genericDescriptor(
            consumerKind: "image", providerKind: "image"))
        payload["genericRenamed"] = inspect(genericDescriptor(
            ids: ["z-sleep", "a-live"],
            resource: "effects/renamed/unseen-mask/effect.json"))
        payload["genericDirectBeforeInactive"] = inspect(genericDescriptor(
            effectOrder: [1, 0]))
        payload["genericOptionalOnly"] = inspect(genericDescriptor(effectOrder: [0]))
        payload["genericNoProgram"] = inspect(generic, admittedReferences: [])
        let genericDirect = SceneDependencyGraphAnalysis.references(in: generic.layers)
        let genericPotential = SceneDependencyGraphAnalysis
            .potentialNamedReferences(in: generic.layers)
        for (name, bad) in [
            ("genericForeignAdmission", SceneDependencyRenderPlan.Reference(
                consumerLayerID: consumerID, providerLayerID: 999,
                slot: genericPotential[0].slot, variant: .primary)),
            ("genericWrongSlotAdmission", .init(
                consumerLayerID: consumerID, providerLayerID: providerID,
                slot: .init(effectID: genericPotential[0].slot.effectID,
                    passIndex: 0, slotIndex: 2), variant: .primary)),
        ] {
            payload[name] = inspect(generic, admittedReferences: Set(genericDirect + [bad]))
        }
        let cycleDescriptor = descriptor(effects: [effect(visible: true, kind: nil)],
            providerDependencies: [consumerID], providerEffects: [effect(
                id: "back", visible: true, kind: nil, namedProviderID: consumerID)])
        let outward = SceneDependencyRenderPlan.Binding(consumerLayerID: consumerID,
            providerLayerID: providerID,
            slot: .init(effectID: "optional-stage", passIndex: 0, slotIndex: 1),
            blendMode: 0, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
        let inward = SceneDependencyRenderPlan.Binding(consumerLayerID: providerID,
            providerLayerID: consumerID, slot: .init(effectID: "back", passIndex: 0, slotIndex: 1),
            blendMode: 0, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
        let cyclicPlan = SceneDependencyRenderPlan(descriptor: cycleDescriptor,
            visibleLayerIDs: [consumerID], preparedNamedInputBindingsByConsumerLayerID: [
                consumerID: [outward], providerID: [inward]])
        payload["preparedCycle"] = ["hasCycle": cyclicPlan.issues.contains { $0.kind == .cyclicDependency },
            "providers": cyclicPlan.requiredProviderLayerIDs.sorted()]
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
        for name in ("inactiveSystem", "inactiveProperty", "activeSystem", "providerChildren"):
            with self.subTest(name=name):
                self.assertEqual(self.results[name]["potential"], [expected_reference])
                self.assertEqual(self.results[name]["carriers"], [expected_carrier])
                self.assertEqual(
                    self.results[name]["admittedReferenceEffects"], ["optional-stage"]
                )
                self.assertTrue(self.results[name]["admittedRequiresProgram"])
                self.assertEqual(self.results[name]["admittedProviders"], [101])
                self.assertEqual(self.results[name]["admittedEffectConsumers"], [202])
                self.assertEqual(self.results[name]["preparedSlots"], [
                    {"effect": "optional-stage", "pass": 0, "slot": 1},
                ])
                self.assertEqual(self.results[name]["preparedEffects"], ["optional-stage"])
                self.assertEqual(self.results[name]["preparedProviders"], [101])
                self.assertEqual(self.results[name]["preparedGraphProviders"], [])
                self.assertTrue(self.results[name]["preparedRequiresProgram"])
                self.assertEqual(self.results[name]["preparedForward"], [False])
                self.assertEqual(self.results[name]["preparedEffectConsumers"], [202])

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
        for name, forward in (("activeDirectWithInactiveOptional", False),
                              ("forwardDirectWithInactiveOptional", True)):
            with self.subTest(name=name):
                row = self.results[name]
                self.assertEqual(row["runtimeBindings"], ["direct-stage"])
                self.assertEqual([c["effect"] for c in row["carriers"]],
                                 ["direct-stage", "optional-stage"])
                self.assertTrue(all(c["requiresProgram"] for c in row["carriers"]))
                self.assertEqual(row["preparedEffects"], ["direct-stage", "optional-stage"])
                self.assertEqual(row["preparedProviders"], [101])
                self.assertTrue(row["preparedRequiresProgram"])
                self.assertEqual(row["preparedForward"], [forward, forward])
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
        for name, ids in (("graphThree", ["z-direct", "m-current", "a-previous"]),
                          ("graphRenamed", ["stage-80", "stage-04", "stage-57"])):
            row = self.results[name]
            with self.subTest(name=name):
                self.assertEqual(row["runtimeKind"], "visibleImageGraphOutput")
                self.assertEqual(row["runtimeSlots"], [{"effect": ids[0], "pass": 0, "slot": 1}])
                self.assertFalse(row["runtimeRequiresProgram"])
                self.assertEqual(row["runtimeGraphProviders"], [101])
                self.assertEqual([ref["effect"] for ref in row["potential"]], ids[1:])
                # Source candidates include the direct read and optional reads;
                # each still requires an actual Program before consumption.
                self.assertEqual([c["effect"] for c in row["carriers"]], ids)
                self.assertEqual(row["carrierKinds"], ["visibleImageGraphOutput"] * 3)
                self.assertTrue(all(c["requiresProgram"] for c in row["carriers"]))
                self.assertEqual(row["preparedEffects"], ids)
                self.assertEqual(row["preparedProviders"], [101])
        unique = self.results["graphUniqueOptional"]
        self.assertEqual(unique["runtimeIdentity"], {})
        self.assertEqual(unique["preparedSlots"], [{"effect": "only-optional", "pass": 0, "slot": 1}])
        self.assertEqual(unique["preparedProviders"], [101])
        self.assertTrue(unique["preparedRequiresProgram"])

    def test_admitted_visible_graph_slots_preserve_author_order_and_one_provider(self) -> None:
        # Already-selected typed inputs exercise the final Plan. They do not
        # stand in for actual Program compilation, readiness or activation.
        for name, ids in (("graphThree", ["z-direct", "m-current", "a-previous"]),
                          ("graphRenamed", ["stage-80", "stage-04", "stage-57"]),
                          ("graphOnlyCurrentAdmitted", ["z-direct", "m-current"])):
            with self.subTest(name=name):
                row = self.results[name]
                self.assertEqual(row["preparedSlots"], [{"effect": effect, "pass": 0, "slot": 1} for effect in ids])
                self.assertTrue(row["preparedRequiresProgram"])
                self.assertEqual(row["preparedForward"], [False] * len(ids))
                self.assertEqual(row["preparedProviders"], [101])
                self.assertEqual(row["preparedGraphProviders"], [101])
                self.assertEqual(row["preparedEffectConsumers"], [202])
        empty = self.results["graphNoProgram"]
        self.assertEqual(empty["preparedSlots"], [])
        self.assertEqual(empty["preparedProviders"], [])
        self.assertEqual(empty["preparedEffectConsumers"], [])
        for name in ("graphForeignAdmission", "graphWrongSlotAdmission"):
            self.assertEqual(self.results[name]["preparedEffects"], ["z-direct"])
        missing = self.results["graphWrongProvider"]
        self.assertEqual(missing["preparedEffects"], ["z-direct", "m-current"])
        self.assertEqual(missing["preparedProviders"], [101])
        for name, last in (("graphWrongSlot", {"effect": "a-previous", "pass": 0, "slot": 2}),
                           ("graphWrongPass", {"effect": "a-previous", "pass": 1, "slot": 1})):
            with self.subTest(name=name):
                self.assertEqual(self.results[name]["preparedEffects"], ["z-direct", "m-current", "a-previous"])
                self.assertEqual(self.results[name]["preparedSlots"][-1], last)
        forward = self.results["graphForward"]
        self.assertEqual([c["effect"] for c in forward["carriers"]], ["z-direct", "m-current", "a-previous"])
        self.assertEqual(forward["preparedEffects"], ["z-direct", "m-current", "a-previous"])
        self.assertEqual(forward["preparedForward"], [True] * 3)
        self.assertEqual(forward["schedule"]["prepass"], [101])
        before = self.results["graphOptionalBeforeDirect"]
        self.assertEqual(before["runtimeSlots"], [{"effect": "direct-b", "pass": 0, "slot": 1}])
        self.assertEqual(before["preparedEffects"], ["optional-a", "direct-b"])
        self.assertEqual(before["preparedProviders"], [101])

    def test_forward_visible_image_and_geometry_share_one_prepared_provider_with_late_reader(self) -> None:
        for puppet in (False, True):
            for renamed in (False, True):
                with self.subTest(puppet=puppet, renamed=renamed):
                    row = self.results[f"forward-{str(puppet).lower()}-{str(renamed).lower()}"]
                    p, c, d = row["provider"], row["early"], row["late"]
                    kind = "geometryLayer" if puppet else "visibleImageGraphOutput"
                    self.assertEqual(row["carrierKinds"], [kind])
                    self.assertEqual(row["preparedSlots"], [{"effect": "renamed-early" if renamed else "early",
                        "pass": 0, "slot": 1}])
                    self.assertTrue(row["sourceIndependent"])
                    self.assertEqual(row["preparedForward"], [True])
                    self.assertEqual(row["preparedProviders"], [p])
                    self.assertEqual(row["preparedGraphProviders"], [p])
                    self.assertEqual(row["preparedEffectConsumers"], sorted([c, d]))
                    bindings = row["allPreparedBindings"]
                    self.assertEqual([b["provider"] for b in bindings], [p, p])
                    self.assertEqual({b["consumer"]: b["requiresForwardCapture"] for b in bindings},
                                     {c: True, d: False})
                    self.assertTrue(all(b["requiresProgram"] and b["kind"] == kind for b in bindings))
                    self.assertEqual(row["schedule"], {"preparation": [p, c, d],
                        "prepass": [p], "scheduled": [p], "before": {}})

    def test_forward_carriers_do_not_replace_program_selection_or_source_availability(self) -> None:
        empty = self.results["forward-no-program"]
        self.assertTrue(empty["carriers"])
        self.assertEqual(empty["preparedProviders"], [])
        for fault in ("no-program", "wrong-slot", "secondary", "missing"):
            with self.subTest(fault=fault):
                row = self.results[f"forward-{fault}"]
                self.assertEqual(row["preparedSlots"], [])
                self.assertEqual(row["schedule"]["prepass"], [])
        for fault in ("wrong-slot", "secondary"):
            row = self.results[f"forward-{fault}"]
            self.assertEqual(row["preparedEffectConsumers"], [row["late"]])
        background = self.results["forward-background"]
        self.assertFalse(background["sourceIndependent"])
        self.assertEqual(background["schedule"], {"preparation": [202, 101, 303],
            "prepass": [], "scheduled": [], "before": {}})

    def test_source_boundaries_and_final_cycle_remain_distinct_from_program_permission(self) -> None:
        for name in ("missingProvider", "secondary", "unsupportedPath",
                     "unsupportedKind", "emptyOptional"):
            with self.subTest(name=name):
                self.assertEqual(self.results[name]["carriers"], [])
                self.assertEqual(self.results[name]["preparedSlots"], [])
                self.assertEqual(self.results[name]["preparedProviders"], [])
        for name in ("unsupportedPath", "unsupportedKind", "emptyOptional"):
            self.assertEqual(self.results[name]["potential"], [])
        for name, pass_index, slot_index in (("wrongProvider", 0, 1), ("unsupportedSlot", 0, 0),
                                            ("unsupportedPass", 1, 1), ("providerCycle", 0, 1),
                                            ("unsupportedConsumer", 0, 1), ("solidConsumer", 0, 1)):
            with self.subTest(name=name):
                carrier = self.results[name]["carriers"]
                self.assertEqual([(c["provider"], c["pass"], c["slot"]) for c in carrier],
                                 [(101, pass_index, slot_index)])
                self.assertTrue(carrier[0]["requiresProgram"])
        self.assertTrue(self.results["preparedCycle"]["hasCycle"])
        self.assertEqual(self.results["preparedCycle"]["providers"], [])

    def test_composition_early_reader_keeps_one_authored_write(self) -> None:
        for arm in ("both", "transparent", "expanded", "early-only", "one-off", "hidden-chain"):
            for renamed in ("false", "true"):
                with self.subTest(arm=arm, renamed=renamed):
                    row = self.results[f"composition-{arm}-{renamed}"]
                    provider, early, late, bridge = (row[k] for k in ("provider", "early", "late", "bridge"))
                    self.assertEqual(row["carrierKinds"], ["resolvedMaterial"] * 2)
                    self.assertEqual(row["preparedForward"], [arm != "expanded"] * 2)
                    if arm != "expanded":
                        self.assertNotIn(early, row["runtimeAggregateConsumers"])
                    self.assertEqual(row["previousProviders"], [provider])
                    self.assertEqual(row["previousConsumers"], {str(early): [provider]})
                    expected = [early, provider]
                    if arm == "hidden-chain":
                        expected.append(bridge)
                    elif arm != "early-only":
                        expected.append(late)
                    self.assertEqual(row["schedule"], {
                        "preparation": expected, "prepass": [], "scheduled": [], "before": {},
                    })

    def test_history_demand_tracks_selected_slots_and_preserves_late_reads(self) -> None:
        for arm in ("both-off", "all-inactive", "different-attachment", "not-eligible", "provider-visible"):
            row = self.results[f"composition-{arm}-false"]
            with self.subTest(arm=arm):
                self.assertEqual(row["previousProviders"], [])
                self.assertEqual(row["previousConsumers"], {})
                self.assertEqual(row["schedule"]["preparation"], [row["early"]] if arm == "all-inactive"
                                 else [row["early"], row["provider"], row["late"]])
                self.assertEqual(row["schedule"]["prepass"], [])

    def test_forward_composition_candidate_leaves_other_utility_sources_unchanged(self) -> None:
        for arm in ("members", "nested-provider", "framebuffer", "transparent-framebuffer",
                    "transparent-provider-visible"):
            row = self.results[f"composition-{arm}-false"]
            with self.subTest(arm=arm):
                self.assertEqual(row["carrierKinds"], [])
                self.assertEqual(row["previousProviders"], [])

    def test_debug_switch_controls_legacy_route_not_prepared_program_inputs(self) -> None:
        for name in ("inactiveSystem", "inactiveProperty", "activeSystem", "activeDirect"):
            with self.subTest(name=name):
                row, disabled = self.results[name], self.disabled_results[name]
                self.assertEqual(disabled["carriers"], row["carriers"])
                self.assertEqual(disabled["preparedSlots"], row["preparedSlots"])
                self.assertEqual(disabled["preparedProviders"], row["preparedProviders"])
        self.assertEqual(self.disabled_results["activeDirect"]["runtimeBindings"], [])
        self.assertEqual(self.disabled_results["graphThree"]["runtimeSlots"],
                         self.results["graphThree"]["runtimeSlots"])

    def test_generic_direct_anchor_survives_earlier_inactive_admission(self) -> None:
        # The cold auxiliary API retains its direct anchor; the typed prepared
        # rows above cover final demand without claiming to compile a Program.
        for name, direct, order in (
            ("textInactiveBeforeDirect", "active-mask", ["dormant-mask", "active-mask"]),
            ("imageInactiveBeforeDirect", "active-mask", ["dormant-mask", "active-mask"]),
            ("genericRenamed", "a-live", ["z-sleep", "a-live"]),
            ("genericDirectBeforeInactive", "active-mask", ["active-mask", "dormant-mask"]),
        ):
            with self.subTest(name=name):
                row = self.results[name]
                slot = {"effect": direct, "pass": 0, "slot": 1}
                base = {
                    "consumer": 202, "provider": 101, "slot": slot,
                    "referenceSlots": [slot], "blendMode": 0,
                    "kind": "imageLayerBlend", "requiresForwardCapture": False,
                    "requiresProgram": True,
                }
                self.assertEqual(row["directAdmittedIdentity"], base)
                self.assertEqual(row["admittedSlots"], [
                    {"effect": effect, "pass": 0, "slot": 1} for effect in order
                ])
                self.assertEqual(row["admittedIdentity"], {
                    **base, "referenceSlots": row["admittedSlots"],
                })
                self.assertEqual(row["admittedProviders"], [101])

    def test_generic_optional_only_uses_its_one_authorized_carrier(self) -> None:
        row = self.results["genericOptionalOnly"]
        self.assertEqual(row["direct"], [])
        self.assertEqual(row["directAdmittedIdentity"], {})
        self.assertEqual(row["runtimeIdentity"], {})
        self.assertEqual(len(row["carrierIdentities"]), 1)
        self.assertEqual(row["admittedIdentity"], row["carrierIdentities"][0])
        self.assertEqual(row["admittedSlots"], [
            {"effect": "dormant-mask", "pass": 0, "slot": 1}
        ])

    def test_generic_typed_selection_cannot_revive_unread_siblings(self) -> None:
        self.assertEqual(self.results["genericNoProgram"]["preparedSlots"], [])
        self.assertEqual(self.results["genericNoProgram"]["preparedProviders"], [])
        for name in ("genericForeignAdmission", "genericWrongSlotAdmission"):
            with self.subTest(name=name):
                row = self.results[name]
                self.assertEqual(row["preparedEffects"], ["active-mask"])
                self.assertEqual(row["preparedProviders"], [101])
                self.assertTrue(row["preparedRequiresProgram"])


if __name__ == "__main__":
    unittest.main()
