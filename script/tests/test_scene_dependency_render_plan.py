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
ADMISSION_CATALOG_SOURCE = (
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectAdmissionCatalog.swift"
)
DEPENDENCY_RUNTIME_SOURCE = (
    SOURCE_ROOT / "RenderGraph/LayerDependencies/SceneDependencyFrameRuntime.swift"
)
METAL_RENDERER_SOURCE = SOURCE_ROOT / "Rendering/SceneMetalRenderer.swift"
LAUNCH_SOURCE = SOURCE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT
    / "RenderGraph/LayerDependencies/SceneImageLayerBlendDependencyContract.swift",
    SOURCE_ROOT / "RenderGraph/LayerDependencies/SceneDependencyGraphAnalysis.swift",
    SOURCE_ROOT / "RenderGraph/LayerDependencies/SceneDependencyRenderPlan.swift",
]

HARNESS_SOURCE = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "number",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}
struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }
    let kind: Kind
}
struct SceneAuthoredEffectRenderPlan {
    struct EffectKey: Hashable {
        let layerID: Int
        let effectIndex: Int
        let descriptorID: String
    }
}
struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [Int?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]

            init(
                passIndex: Int,
                texturePaths: [String] = [],
                textureSlots: [String?],
                userTextureInputs: [Int?] = [],
                combos: [String: Int],
                constantShaderValues: [String: SceneDocument.ShaderValue]
            ) {
                self.passIndex = passIndex
                self.texturePaths = texturePaths
                self.textureSlots = textureSlots
                self.userTextureInputs = userTextureInputs
                self.combos = combos
                self.constantShaderValues = constantShaderValues
            }
        }
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
    struct Layer {
        let id: Int
        let contentKind: String
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        let childLayerIDs: [Int]
        let visible: Bool?
        let effects: [EffectDescriptor]
    }
    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
}

@main
enum Harness {
    static func main() throws {
        let provider = layer(1, kind: .composition, visible: false)
        let visibleConsumer = consumer(2, provider: 1, dependencies: [])
        let hiddenConsumer = consumer(3, provider: 1, visible: false)
        let cycleA = layer(4, kind: .composition, dependencies: [5])
        let cycleB = layer(5, kind: .composition, dependencies: [4])
        let forwardConsumer = consumer(6, provider: 7)
        let forwardProvider = layer(7, kind: .composition)
        let partialConsumer = consumer(8, provider: 1, extraEffect: true)
        let neutralOpacityConsumer = consumer(9, provider: 1, opacity: 1)
        let nonNeutralOpacityConsumer = consumer(10, provider: 1, opacity: 0.5)
        let alternateEffectConsumer = consumer(
            11,
            provider: 1,
            effectPath: "effects/blend/effect.json"
        )
        let alternatePathConsumer = consumer(
            16,
            provider: 1,
            effectPath: "effects/workshop/other/clipping_mask/effect.json"
        )
        let supportedGradientConsumer = gradientConsumer(12, provider: 1)
        let reversedGradientConsumer = gradientConsumer(13, provider: 1, reversed: true)
        let invalidGradientConsumer = gradientConsumer(14, provider: 1, axis: 2)
        let utilityConsumer = SceneRenderDescriptor.Layer(
            id: 15,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 15, provider: 1)]
        )
        let projectUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 17,
            contentKind: "project",
            utilityLayer: .init(kind: .project),
            dependencyLayerIDs: [1],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 17, provider: 1)]
        )
        let childUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 18,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1],
            childLayerIDs: [99],
            visible: true,
            effects: [effect(id: 18, provider: 1)]
        )
        let extraDependencyUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 19,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1, 7],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 19, provider: 1)]
        )
        let legacyNoiseProvider = SceneRenderDescriptor.Layer(
            id: 30,
            contentKind: "solid",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let legacyNoiseConsumer = SceneRenderDescriptor.Layer(
            id: 31,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [30],
            childLayerIDs: [],
            visible: true,
            effects: [proceduralNoiseEffect(id: 31, provider: 30)]
        )
        let missingProviderConsumer = consumer(32, provider: 999)
        let secondaryConsumer = consumer(33, provider: 1, variantSuffix: "b")
        let secondaryDescriptor = SceneRenderDescriptor(
            layers: [provider, secondaryConsumer],
            renderOrderLayerIDs: [1, 33]
        )
        let secondaryPlan = SceneDependencyRenderPlan(
            descriptor: secondaryDescriptor,
            visibleLayerIDs: [1, 33]
        )
        let routeProvider = layer(400, kind: .composition, visible: false)
        let routeConsumer = consumer(401, provider: 400)
        let routePlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [routeProvider, routeConsumer],
                renderOrderLayerIDs: [routeProvider.id, routeConsumer.id]
            ),
            visibleLayerIDs: [routeProvider.id, routeConsumer.id]
        )
        let shadowedProvider = layer(420, kind: .composition, visible: false)
        let shadowedConsumer = SceneRenderDescriptor.Layer(
            id: 421,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [shadowedProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [
                effect(id: 421, provider: shadowedProvider.id),
                shadowedEffect(id: 422, provider: shadowedProvider.id),
                shadowedEffect(id: 423, provider: shadowedProvider.id),
            ]
        )
        let shadowedPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [shadowedProvider, shadowedConsumer],
                renderOrderLayerIDs: [shadowedProvider.id, shadowedConsumer.id]
            ),
            visibleLayerIDs: [shadowedProvider.id, shadowedConsumer.id]
        )
        let selectedMultiReferenceConsumer = SceneRenderDescriptor.Layer(
            id: 431,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [shadowedProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [
                effect(id: 431, provider: shadowedProvider.id),
                effect(id: 432, provider: shadowedProvider.id),
            ]
        )
        let selectedMultiReferencePlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [shadowedProvider, selectedMultiReferenceConsumer],
                renderOrderLayerIDs: [
                    shadowedProvider.id, selectedMultiReferenceConsumer.id,
                ]
            ),
            visibleLayerIDs: [
                shadowedProvider.id, selectedMultiReferenceConsumer.id,
            ]
        )
        let routeUtilityProvider = layer(410, kind: .composition, visible: false)
        let routeUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 411,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [routeUtilityProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 411, provider: routeUtilityProvider.id)]
        )
        let routeUtilityPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [routeUtilityProvider, routeUtilityConsumer],
                renderOrderLayerIDs: [routeUtilityProvider.id, routeUtilityConsumer.id]
            ),
            visibleLayerIDs: [routeUtilityProvider.id, routeUtilityConsumer.id]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                provider, visibleConsumer, hiddenConsumer,
                cycleA, cycleB, forwardConsumer, forwardProvider, partialConsumer,
                neutralOpacityConsumer, nonNeutralOpacityConsumer, alternateEffectConsumer,
                supportedGradientConsumer, reversedGradientConsumer, invalidGradientConsumer,
                utilityConsumer, alternatePathConsumer, projectUtilityConsumer,
                childUtilityConsumer, extraDependencyUtilityConsumer,
                legacyNoiseProvider, legacyNoiseConsumer, missingProviderConsumer,
            ],
            renderOrderLayerIDs: [
                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
                30, 31, 32,
            ]
        )
        let visibleLayerIDs: Set<Int> = [
            1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 31, 32,
        ]
        let plan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: [15, 31]
        )
        let defaultPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs
        )
        let matrixProviders = (10...15).map { layer($0, kind: .composition) }
        let matrixProviderIDs = [10, 10, 10, 11, 12, 13, 14, 15]
        let matrixConsumers = matrixProviderIDs.enumerated().map { offset, providerID in
            consumer(20 + offset, provider: providerID, visible: offset != 2)
        }
        let matrixLayers = matrixProviders + matrixConsumers
        let matrixDescriptor = SceneRenderDescriptor(
            layers: matrixLayers,
            renderOrderLayerIDs: matrixLayers.map(\.id)
        )
        let matrixVisible = Set(matrixLayers.compactMap {
            $0.visible == false ? nil : $0.id
        })
        let matrixPlan = SceneDependencyRenderPlan(
            descriptor: matrixDescriptor,
            visibleLayerIDs: matrixVisible
        )
        let visibleNamedProvider = layer(100)
        let visibleUnboundConsumer = consumer(
            101,
            provider: 100,
            dependencies: [],
            effectPath: "effects/blend/effect.json"
        )
        let hiddenNamedProvider = layer(110)
        let hiddenNamedConsumer = consumer(
            111,
            provider: 110,
            visible: false,
            effectPath: "effects/blend/effect.json"
        )
        let selfReferenceConsumer = consumer(
            120,
            provider: 120,
            dependencies: [],
            effectPath: "effects/blend/effect.json"
        )
        let unreferencedProvider = layer(130)
        let explicitDependencyProvider = layer(140)
        let explicitDependencyConsumer = layer(141, dependencies: [140])
        let dependencySafetyLayers = [
            visibleNamedProvider,
            visibleUnboundConsumer,
            hiddenNamedProvider,
            hiddenNamedConsumer,
            selfReferenceConsumer,
            unreferencedProvider,
            explicitDependencyProvider,
            explicitDependencyConsumer,
        ]
        let dependencySafetyPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: dependencySafetyLayers,
                renderOrderLayerIDs: dependencySafetyLayers.map(\.id)
            ),
            visibleLayerIDs: [100, 101, 110, 120, 130, 140, 141]
        )
        let xRayProviderLayer = layer(200)
        let xRayLayers: [SceneRenderDescriptor.Layer] = [
            xRayProviderLayer,
            xRayConsumer(201, provider: 200),
            xRayConsumer(202, provider: 200, dependencies: [200, 7]),
            xRayConsumer(203, provider: 200, combos: ["OPACITYMASK": 1]),
            xRayConsumer(204, provider: 200, combos: ["BLENDMODE": 5]),
            xRayConsumer(
                205,
                provider: 200,
                file: "effects/workshop/9/xray/effect.json"
            ),
            xRayConsumer(
                206,
                provider: 200,
                slots: [
                    nil,
                    "_rt_imageLayerComposite_200_a",
                    "_rt_imageLayerComposite_200_b",
                ]
            ),
            xRayConsumer(
                207,
                provider: 200,
                slots: [nil, "_rt_imageLayerComposite_999_a", "particle/halo_6"]
            ),
            xRayConsumer(208, provider: 200, extraEffect: true),
            xRayConsumer(209, provider: 200, passCount: 2),
            xRayConsumer(211, provider: 200),
            consumer(212, provider: 211),
        ]
        let xRayPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: xRayLayers,
                renderOrderLayerIDs: xRayLayers.map(\.id)
            ),
            visibleLayerIDs: Set(xRayLayers.map(\.id)),
            verifiedXRayStageKeys: Set(
                [201, 202, 203, 204, 206, 207, 208, 209, 211].map {
                    xRayKey(layerID: $0)
                }
            )
        )
        let exactXRayLayers = [
            layer(220),
            xRayConsumer(221, provider: 220),
        ]
        let exactXRayPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: exactXRayLayers,
                renderOrderLayerIDs: exactXRayLayers.map(\.id)
            ),
            visibleLayerIDs: Set(exactXRayLayers.map(\.id)),
            verifiedXRayStageKeys: [xRayKey(layerID: 221)]
        )
        let missingProviderXRay = xRayConsumer(231, provider: 230)
        let missingProviderXRayPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [missingProviderXRay],
                renderOrderLayerIDs: [missingProviderXRay.id]
            ),
            visibleLayerIDs: [missingProviderXRay.id],
            verifiedXRayStageKeys: [xRayKey(layerID: missingProviderXRay.id)]
        )
        let unverifiedStockPathLayers = [
            layer(240),
            xRayConsumer(241, provider: 240),
        ]
        let unverifiedStockPathPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: unverifiedStockPathLayers,
                renderOrderLayerIDs: unverifiedStockPathLayers.map(\.id)
            ),
            visibleLayerIDs: Set(unverifiedStockPathLayers.map(\.id))
        )
        let multiEffectXRayLayers = [
            layer(250),
            xRayConsumer(
                251,
                provider: 250,
                localEffectsBefore: 1,
                localEffectsAfter: 1
            ),
        ]
        let multiEffectXRayPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: multiEffectXRayLayers,
                renderOrderLayerIDs: multiEffectXRayLayers.map(\.id)
            ),
            visibleLayerIDs: Set(multiEffectXRayLayers.map(\.id)),
            verifiedXRayStageKeys: [xRayKey(layerID: 251, effectIndex: 1)]
        )
        let parsed = [
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42")?.variant.rawValue ?? "nil",
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42_a")?.variant.rawValue ?? "nil",
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42_b")?.variant.rawValue ?? "nil",
        ]
        let legacyNoiseBinding = plan.bindingsByConsumerLayerID[31]
        let imageBlend = imageBlendBinding()
        let result: [String: Any] = [
            "parsedVariants": parsed,
            "invalidReference": SceneNamedTextureReference.parse("_rt_imageLayerComposite_bad_a") == nil,
            "referenceCount": plan.references.count,
            "namedConsumers": plan.namedReferenceConsumerLayerIDs.sorted(),
            "executableUtilityConsumers": plan.executableUtilityConsumerLayerIDs.sorted(),
            "requiredEffectConsumers": plan.requiredEffectConsumerLayerIDs.sorted(),
            "bindingConsumers": plan.bindingsByConsumerLayerID.keys.sorted(),
            "defaultUtilityBinding": defaultPlan.bindingsByConsumerLayerID[15] != nil,
            "requiredProviders": plan.requiredProviderLayerIDs.sorted(),
            "cycles": plan.cyclicLayerIDs.sorted(),
            "issues": plan.issues.map { "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)" },
            "secondaryBinding": secondaryPlan.bindingsByConsumerLayerID[33] != nil,
            "secondaryIssues": secondaryPlan.issues.map {
                "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
            },
            "resolvedMaterialRoute": [
                "binding": routePlan.bindingsByConsumerLayerID[routeConsumer.id] != nil,
                "resolvedMaterial": routePlan.bindingsByConsumerLayerID[routeConsumer.id]?.kind
                    == .resolvedMaterial,
                "requiredEffect": routePlan.requiredEffectConsumerLayerIDs
                    .contains(routeConsumer.id),
                "requiredProviders": routePlan.requiredProviderLayerIDs.sorted(),
                "issues": routePlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "shadowedNamedReferences": [
                "referenceCount": shadowedPlan.references.count,
                "binding": shadowedPlan.bindingsByConsumerLayerID[
                    shadowedConsumer.id
                ]?.kind == .resolvedMaterial,
                "provider": shadowedPlan.bindingsByConsumerLayerID[
                    shadowedConsumer.id
                ]?.providerLayerID ?? -1,
                "issues": shadowedPlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "selectedMultiReferenceRejected":
                selectedMultiReferencePlan.bindingsByConsumerLayerID[
                    selectedMultiReferenceConsumer.id
                ] == nil
                && selectedMultiReferencePlan.issues.contains {
                    $0.layerID == selectedMultiReferenceConsumer.id
                        && $0.kind == .unsupportedConsumer
                },
            "resolvedMaterialUtilityRoute": [
                "binding": routeUtilityPlan.bindingsByConsumerLayerID[
                    routeUtilityConsumer.id
                ] != nil,
                "requiredEffect": routeUtilityPlan.requiredEffectConsumerLayerIDs
                    .contains(routeUtilityConsumer.id),
                "requiredProviders": routeUtilityPlan.requiredProviderLayerIDs.sorted(),
                "issues": routeUtilityPlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "matrixBindingCount": matrixPlan.bindingsByConsumerLayerID.count,
            "matrixRequiredProviders": matrixPlan.requiredProviderLayerIDs.sorted(),
            "staticPassthroughBlocks": [
                "namedProvider": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 100),
                "namedConsumer": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 101),
                "hiddenNamedProvider": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 110),
                "hiddenNamedConsumer": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 111),
                "selfReference": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 120),
                "unreferenced": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 130),
                "explicitProvider": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 140),
                "explicitConsumer": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 141),
                "requiredProvidersEmpty": dependencySafetyPlan.requiredProviderLayerIDs.isEmpty,
            ],
            "staticPassthroughXRayBlocks": [
                "exemptConsumer": xRayPlan.blocksStaticLayerSourcePassthrough(for: 201),
                "xRayProvider": xRayPlan.blocksStaticLayerSourcePassthrough(for: 200),
                "extraDependency": xRayPlan.blocksStaticLayerSourcePassthrough(for: 202),
                "opacityMaskCombo": xRayPlan.blocksStaticLayerSourcePassthrough(for: 203),
                "blendModeCombo": xRayPlan.blocksStaticLayerSourcePassthrough(for: 204),
                "nonStockDefinition": xRayPlan.blocksStaticLayerSourcePassthrough(for: 205),
                "secondNamedSlot": xRayPlan.blocksStaticLayerSourcePassthrough(for: 206),
                "mismatchedProvider": xRayPlan.blocksStaticLayerSourcePassthrough(for: 207),
                "secondNamedReference": xRayPlan.blocksStaticLayerSourcePassthrough(for: 208),
                "multiplePasses": xRayPlan.blocksStaticLayerSourcePassthrough(for: 209),
                "exemptThenProvider": xRayPlan.blocksStaticLayerSourcePassthrough(for: 211),
                "upperConsumer": xRayPlan.blocksStaticLayerSourcePassthrough(for: 212),
            ],
            "isolatedXRayPassthroughBlocks": [
                "exactProvider": exactXRayPlan.blocksStaticLayerSourcePassthrough(for: 220),
                "exactConsumer": exactXRayPlan.blocksStaticLayerSourcePassthrough(for: 221),
                "missingProviderConsumer": missingProviderXRayPlan
                    .blocksStaticLayerSourcePassthrough(for: 231),
                "unverifiedStockPathProvider": unverifiedStockPathPlan
                    .blocksStaticLayerSourcePassthrough(for: 240),
                "unverifiedStockPathConsumer": unverifiedStockPathPlan
                    .blocksStaticLayerSourcePassthrough(for: 241),
                "multiEffectProvider": multiEffectXRayPlan
                    .blocksStaticLayerSourcePassthrough(for: 250),
                "multiEffectConsumer": multiEffectXRayPlan
                    .blocksStaticLayerSourcePassthrough(for: 251),
            ],
            "legacyNoiseBinding": [
                "consumer": legacyNoiseBinding?.consumerLayerID ?? -1,
                "provider": legacyNoiseBinding?.providerLayerID ?? -1,
                "effect": legacyNoiseBinding?.slot.effectID ?? "",
                "pass": legacyNoiseBinding?.slot.passIndex ?? -1,
                "slot": legacyNoiseBinding?.slot.slotIndex ?? -1,
                "blend": legacyNoiseBinding?.blendMode ?? -1,
                "procedural": legacyNoiseBinding?.kind == .proceduralNoiseLayer,
            ],
            "legacyNoiseRejects": [
                "modern": proceduralBinding(effectPath: "effects/procedural_noise/effect.json") == nil,
                "visibleProvider": proceduralBinding(providerVisible: true) == nil,
                "wrongProviderKind": proceduralBinding(providerContentKind: "image") == nil,
                "secondary": proceduralBinding(variantSuffix: "b") == nil,
                "wrongEffect": proceduralBinding(effectPath: "effects/workshop/other/procedural_noise/effect.json") == nil,
                "wrongPass": proceduralBinding(passIndex: 1) == nil,
                "wrongSlot": proceduralBinding(slotIndex: 2) == nil,
                "wrongCombos": proceduralBinding(extraCombos: ["BLENDMODE": 5]) == nil,
                "extraReference": proceduralBinding(extraReference: true) == nil,
            ],
            "imageBlendBinding": [
                "consumer": imageBlend?.consumerLayerID ?? -1,
                "provider": imageBlend?.providerLayerID ?? -1,
                "effect": imageBlend?.slot.effectID ?? "",
                "pass": imageBlend?.slot.passIndex ?? -1,
                "slot": imageBlend?.slot.slotIndex ?? -1,
                "blend": imageBlend?.blendMode ?? -1,
                "imageBlend": imageBlend?.kind == .imageLayerBlend,
            ],
            "imageBlendRejects": [
                "visibleProvider": imageBlendBinding(providerVisible: true) == nil,
                "effectfulProvider": imageBlendBinding(providerEffectful: true) == nil,
                "wrongProviderKind": imageBlendBinding(providerContentKind: "solid") == nil,
                "secondary": imageBlendBinding(variantSuffix: "b") == nil,
                "userTextureOverride": imageBlendBinding(userTextureOverride: true) == nil,
                "extraReference": imageBlendBinding(extraReference: true) == nil,
                "transformed": imageBlendBinding(extraCombos: ["TRANSFORMUV": 1]) == nil,
                "partialStrength": imageBlendBinding(multiply: 0.5) == nil,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func layer(
        _ id: Int,
        kind: SceneUtilityLayer.Kind? = nil,
        dependencies: [Int] = [],
        visible: Bool? = true
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            contentKind: kind == nil ? "image" : "composition",
            utilityLayer: kind.map(SceneUtilityLayer.init(kind:)),
            dependencyLayerIDs: dependencies,
            childLayerIDs: [],
            visible: visible,
            effects: []
        )
    }

    static func consumer(
        _ id: Int,
        provider: Int,
        dependencies: [Int]? = nil,
        visible: Bool? = true,
        extraEffect: Bool = false,
        opacity: Double? = nil,
        variantSuffix: String = "a",
        effectPath: String = "effects/workshop/2800594362/clipping_mask/effect.json"
    ) -> SceneRenderDescriptor.Layer {
        var effects = [effect(
            id: id,
            provider: provider,
            opacity: opacity,
            variantSuffix: variantSuffix,
            path: effectPath
        )]
        if extraEffect {
            effects.append(.init(id: "tint", file: "effects/tint/effect.json", visible: true, passes: []))
        }
        return .init(
            id: id,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: dependencies ?? [provider],
            childLayerIDs: [],
            visible: visible,
            effects: effects
        )
    }

    static func xRayEffect(
        id: String,
        provider: Int,
        combos: [String: Int] = [:],
        slots: [String?]? = nil,
        file: String = "effects/xray/effect.json",
        passCount: Int = 1
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let authoredSlots = slots
            ?? [nil, "_rt_imageLayerComposite_\(provider)_a", "particle/halo_6"]
        let authoredPaths = authoredSlots.compactMap { $0 }
        let template = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: authoredPaths,
            textureSlots: authoredSlots,
            userTextureInputs: [],
            combos: combos,
            constantShaderValues: [:]
        )
        return .init(
            id: id,
            file: file,
            visible: true,
            passes: (0 ..< passCount).map { index in
                .init(
                    passIndex: index,
                    texturePaths: template.texturePaths,
                    textureSlots: template.textureSlots,
                    userTextureInputs: template.userTextureInputs,
                    combos: template.combos,
                    constantShaderValues: template.constantShaderValues
                )
            }
        )
    }

    static func xRayConsumer(
        _ id: Int,
        provider: Int,
        dependencies: [Int]? = nil,
        combos: [String: Int] = [:],
        slots: [String?]? = nil,
        file: String = "effects/xray/effect.json",
        passCount: Int = 1,
        extraEffect: Bool = false,
        localEffectsBefore: Int = 0,
        localEffectsAfter: Int = 0
    ) -> SceneRenderDescriptor.Layer {
        let xRay = [
            xRayEffect(
                id: "xray-\(id)",
                provider: provider,
                combos: combos,
                slots: slots,
                file: file,
                passCount: passCount
            ),
        ]
        var effects = localEffects(
            layerID: id,
            count: localEffectsBefore,
            suffix: "before"
        ) + xRay + localEffects(
            layerID: id,
            count: localEffectsAfter,
            suffix: "after"
        )
        if extraEffect {
            effects.append(.init(
                id: "extra-\(id)",
                file: "effects/blend/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: ["_rt_imageLayerComposite_\(provider)_a"],
                    textureSlots: [nil, "_rt_imageLayerComposite_\(provider)_a"],
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                )]
            ))
        }
        return .init(
            id: id,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: dependencies ?? [provider],
            childLayerIDs: [],
            visible: true,
            effects: effects
        )
    }

    static func localEffects(
        layerID: Int,
        count: Int,
        suffix: String
    ) -> [SceneRenderDescriptor.EffectDescriptor] {
        (0 ..< count).map { index in
            .init(
                id: "local-\(layerID)-\(suffix)-\(index)",
                file: "effects/tint/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [],
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                )]
            )
        }
    }

    static func xRayKey(
        layerID: Int,
        effectIndex: Int = 0
    ) -> SceneAuthoredEffectRenderPlan.EffectKey {
        .init(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "xray-\(layerID)"
        )
    }

    static func effect(
        id: Int,
        provider: Int,
        opacity: Double? = nil,
        variantSuffix: String = "a",
        path: String = "effects/workshop/2800594362/clipping_mask/effect.json"
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: "effect-\(id)",
            file: path,
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: ["_rt_imageLayerComposite_\(provider)_\(variantSuffix)"],
                textureSlots: opacity == nil
                    ? [nil, "_rt_imageLayerComposite_\(provider)_\(variantSuffix)"]
                    : [nil, "_rt_imageLayerComposite_\(provider)_\(variantSuffix)", nil],
                combos: opacity == nil ? ["BLENDMODE": 5] : [:],
                constantShaderValues: opacity.map {
                    ["Opacity": SceneDocument.ShaderValue(components: [$0])]
                } ?? [:]
            )]
        )
    }

    static func shadowedEffect(
        id: Int,
        provider: Int
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let path = "_rt_imageLayerComposite_\(provider)_a"
        return .init(
            id: "effect-\(id)",
            file: "effects/blend/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: [path],
                textureSlots: [nil, path],
                userTextureInputs: [nil, 1],
                combos: ["BLENDMODE": 0],
                constantShaderValues: [
                    "alpha": .init(components: [1]),
                    "multiply": .init(components: [1]),
                ]
            )]
        )
    }

    static func gradientConsumer(
        _ id: Int,
        provider: Int,
        reversed: Bool = false,
        axis: Int = 1
    ) -> SceneRenderDescriptor.Layer {
        let gradient = SceneRenderDescriptor.EffectDescriptor(
            id: "gradient-\(id)",
            file: "effects/workshop/2552475732/gradient_color/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                textureSlots: [],
                combos: ["AXIS": axis, "BLENDMODE": 0],
                constantShaderValues: [
                    "Amount": .init(components: [1]),
                    "Color 1": .init(components: [1, 0, 0.2]),
                    "Color 2": .init(components: [0, 0, 1]),
                    "Hue Speed": .init(components: [0]),
                    "Opacity": .init(components: [1]),
                    "Oscillate": .init(components: [0]),
                ]
            )]
        )
        let externalPrimary = effect(id: id, provider: provider)
        return .init(
            id: id,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [provider],
            childLayerIDs: [],
            visible: true,
            effects: reversed ? [externalPrimary, gradient] : [gradient, externalPrimary]
        )
    }

    static func proceduralNoiseEffect(
        id: Int,
        provider: Int,
        effectPath: String = "effects/workshop/2924967132/procedural_noise/effect.json",
        passIndex: Int = 0,
        slotIndex: Int = 3,
        variantSuffix: String = "a",
        extraCombos: [String: Int] = [:],
        extraReference: Bool = false
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let path = "_rt_imageLayerComposite_\(provider)_\(variantSuffix)"
        var slots = Array<String?>(repeating: nil, count: 4)
        slots[slotIndex] = path
        if extraReference {
            slots[1] = "_rt_imageLayerComposite_\(provider)_a"
        }
        var combos = [
            "AB_TYPECOLOR": 3,
            "PERSPSWITCH": 1,
            "WRITEALPHA": 1,
        ]
        combos.merge(extraCombos) { _, new in new }
        return .init(
            id: "\(id)#effect#noise",
            file: effectPath,
            visible: true,
            passes: [.init(
                passIndex: passIndex,
                texturePaths: extraReference
                    ? [path, "_rt_imageLayerComposite_\(provider)_a"] : [path],
                textureSlots: slots,
                combos: combos,
                constantShaderValues: [:]
            )]
        )
    }

    static func proceduralBinding(
        providerVisible: Bool? = false,
        providerContentKind: String = "solid",
        effectPath: String = "effects/workshop/2924967132/procedural_noise/effect.json",
        passIndex: Int = 0,
        slotIndex: Int = 3,
        variantSuffix: String = "a",
        extraCombos: [String: Int] = [:],
        extraReference: Bool = false
    ) -> SceneDependencyRenderPlan.Binding? {
        let providerID = 90
        let consumerID = 91
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: providerContentKind,
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: providerVisible,
            effects: []
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [proceduralNoiseEffect(
                id: consumerID,
                provider: providerID,
                effectPath: effectPath,
                passIndex: passIndex,
                slotIndex: slotIndex,
                variantSuffix: variantSuffix,
                extraCombos: extraCombos,
                extraReference: extraReference
            )]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer],
            renderOrderLayerIDs: [providerID, consumerID]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [consumerID],
            executableUtilityConsumerLayerIDs: [consumerID]
        ).bindingsByConsumerLayerID[consumerID]
    }

    static func imageBlendBinding(
        providerVisible: Bool? = false,
        providerContentKind: String = "image",
        providerEffectful: Bool = false,
        variantSuffix: String = "a",
        userTextureOverride: Bool = false,
        extraReference: Bool = false,
        dependencyMismatch: Bool = false,
        extraCombos: [String: Int] = [:],
        multiply: Double = 1
    ) -> SceneDependencyRenderPlan.Binding? {
        let providerID = 300
        let consumerID = 301
        let providerEffects: [SceneRenderDescriptor.EffectDescriptor] = providerEffectful
            ? [.init(
                id: "provider-effect",
                file: "effects/tint/effect.json",
                visible: true,
                passes: []
            )] : []
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: providerContentKind,
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: providerVisible,
            effects: providerEffects
        )
        let primary = "_rt_imageLayerComposite_\(providerID)_\(variantSuffix)"
        let extra = "_rt_imageLayerComposite_299_a"
        var slots: [String?] = [nil, primary]
        if extraReference { slots.append(extra) }
        var combos = ["BLENDMODE": 0]
        combos.merge(extraCombos) { _, new in new }
        let blend = SceneRenderDescriptor.EffectDescriptor(
            id: "image-blend",
            file: "effects/blend/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: extraReference ? [primary, extra] : [primary],
                textureSlots: slots,
                userTextureInputs: userTextureOverride ? [nil, 1] : [],
                combos: combos,
                constantShaderValues: [
                    "multiply": .init(components: [multiply]),
                    "alpha": .init(components: [1]),
                ]
            )]
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: dependencyMismatch ? [299] : [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [blend]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer],
            renderOrderLayerIDs: [providerID, consumerID]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [consumerID]
        ).bindingsByConsumerLayerID[consumerID]
    }
}
'''


class SceneDependencyRenderPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-dependency-plan-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-dependency-plan"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        default_environment = os.environ.copy()
        default_environment.pop("MWX_SCENE_NAMED_PROVIDER_ROUTE", None)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
            env=default_environment,
        )
        cls.result = json.loads(completed.stdout)
        disabled_environment = default_environment.copy()
        disabled_environment["MWX_SCENE_NAMED_PROVIDER_ROUTE"] = "disable-generic"
        disabled = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
            env=disabled_environment,
        )
        cls.route_disabled_result = json.loads(disabled.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_named_reference_variants_are_typed(self) -> None:
        self.assertEqual(self.result["parsedVariants"], ["unspecified", "a", "b"])
        self.assertTrue(self.result["invalidReference"])
        self.assertFalse(self.result["secondaryBinding"])
        self.assertEqual(
            self.result["secondaryIssues"],
            ["33:unsupportedVariant:1"],
        )

    def test_named_consumers_share_path_independent_backward_binding(self) -> None:
        self.assertEqual(self.result["referenceCount"], 17)
        self.assertEqual(
            self.result["namedConsumers"],
            [2, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 31, 32],
        )
        self.assertEqual(
            self.result["requiredEffectConsumers"],
            [2, 6, 8, 9, 11, 12, 13, 14, 15, 16, 31, 32],
        )
        self.assertEqual(self.result["executableUtilityConsumers"], [15, 31])
        self.assertEqual(
            self.result["bindingConsumers"],
            [2, 8, 9, 11, 12, 13, 14, 15, 16, 31],
        )
        self.assertFalse(self.result["defaultUtilityBinding"])
        self.assertEqual(self.result["requiredProviders"], [1, 30])

    def test_named_provider_route_rollback_is_generic_only_and_fail_closed(self) -> None:
        self.assertEqual(
            self.result["resolvedMaterialRoute"],
            {
                "binding": True,
                "resolvedMaterial": True,
                "requiredEffect": True,
                "requiredProviders": [400],
                "issues": [],
            },
        )
        self.assertEqual(
            self.route_disabled_result["resolvedMaterialRoute"],
            {
                "binding": False,
                "resolvedMaterial": False,
                "requiredEffect": True,
                "requiredProviders": [],
                "issues": ["401:resolvedMaterialRouteDisabled:400"],
            },
        )
        self.assertEqual(
            self.result["resolvedMaterialUtilityRoute"],
            {
                "binding": False,
                "requiredEffect": False,
                "requiredProviders": [],
                "issues": ["411:unsupportedConsumer:-1"],
            },
        )
        self.assertEqual(
            self.route_disabled_result["resolvedMaterialUtilityRoute"],
            {
                "binding": False,
                "requiredEffect": True,
                "requiredProviders": [],
                "issues": ["411:resolvedMaterialRouteDisabled:410"],
            },
        )
        self.assertEqual(
            self.route_disabled_result["legacyNoiseBinding"],
            self.result["legacyNoiseBinding"],
        )
        self.assertEqual(
            self.route_disabled_result["imageBlendBinding"],
            self.result["imageBlendBinding"],
        )

    def test_shadowed_named_references_do_not_create_execution_dependencies(self) -> None:
        self.assertEqual(
            self.result["shadowedNamedReferences"],
            {
                "referenceCount": 1,
                "binding": True,
                "provider": 420,
                "issues": [],
            },
        )
        self.assertTrue(self.result["selectedMultiReferenceRejected"])

    def test_cycle_forward_and_invalid_external_primary_contracts_fail_closed(self) -> None:
        self.assertEqual(self.result["cycles"], [4, 5])
        self.assertIn("2:dependencyMismatch:1", self.result["issues"])
        self.assertIn("6:forwardUtilityProvider:7", self.result["issues"])
        self.assertIn("32:missingProvider:999", self.result["issues"])
        self.assertIn("10:unsupportedConsumer:-1", self.result["issues"])
        self.assertNotIn("15:unsupportedConsumer:-1", self.result["issues"])
        self.assertNotIn("16:unsupportedConsumer:-1", self.result["issues"])
        for layer_id in (17, 18, 19):
            self.assertIn(
                f"{layer_id}:unsupportedConsumer:-1",
                self.result["issues"],
            )

    def test_matrix_shape_keeps_hidden_consumer_out_of_runtime_liveness(self) -> None:
        self.assertEqual(self.result["matrixBindingCount"], 7)
        self.assertEqual(self.result["matrixRequiredProviders"], [10, 11, 12, 13, 14, 15])

    def test_visible_dependency_edge_blocks_both_sides_from_static_passthrough(self) -> None:
        self.assertEqual(
            self.result["staticPassthroughBlocks"],
            {
                "namedProvider": True,
                "namedConsumer": True,
                "hiddenNamedProvider": False,
                "hiddenNamedConsumer": False,
                "selfReference": False,
                "unreferenced": False,
                "explicitProvider": True,
                "explicitConsumer": True,
                "requiredProvidersEmpty": True,
            },
        )

    def test_xray_consumer_passthrough_exemption_is_typed_and_provider_sided(
        self,
    ) -> None:
        self.assertEqual(
            self.result["staticPassthroughXRayBlocks"],
            {
                "exemptConsumer": False,
                "xRayProvider": True,
                "extraDependency": True,
                "opacityMaskCombo": True,
                "blendModeCombo": True,
                "nonStockDefinition": True,
                "secondNamedSlot": True,
                "mismatchedProvider": True,
                "secondNamedReference": True,
                "multiplePasses": True,
                "exemptThenProvider": True,
                "upperConsumer": True,
            },
        )

    def test_xray_passthrough_requires_verified_identity_and_existing_provider(
        self,
    ) -> None:
        self.assertEqual(
            self.result["isolatedXRayPassthroughBlocks"],
            {
                "exactProvider": True,
                "exactConsumer": False,
                "missingProviderConsumer": True,
                "unverifiedStockPathProvider": True,
                "unverifiedStockPathConsumer": True,
                "multiEffectProvider": True,
                "multiEffectConsumer": False,
            },
        )

    def test_verified_xray_authority_flows_from_stock_identity_to_dependency_plan(
        self,
    ) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        catalog = ADMISSION_CATALOG_SOURCE.read_text(encoding="utf-8")
        renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8")
        dependency_runtime = DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "SceneAuthoredXRayPlanner.verifiedStockIdentityEffectKeys(",
            launch,
        )
        self.assertIn(
            "descriptor: runtimeInput.renderDescriptor",
            launch,
        )
        self.assertIn(
            "shaderContracts: runtimeInput.shaderContracts",
            launch,
        )
        self.assertIn(
            "verifiedXRayStageKeys: verifiedXRayStockIdentityKeys",
            launch,
        )
        self.assertIn(
            "self.verifiedXRayStageKeys = verifiedXRayStageKeys.intersection(",
            catalog,
        )
        self.assertIn(
            "verifiedXRayStageKeys: effectAdmissionCatalog.verifiedXRayStageKeys",
            renderer,
        )
        self.assertIn(
            "verifiedXRayStageKeys: verifiedXRayStageKeys",
            dependency_runtime,
        )

    def test_exact_legacy_procedural_dependency_is_typed_and_fail_closed(self) -> None:
        self.assertEqual(
            self.result["legacyNoiseBinding"],
            {
                "consumer": 31,
                "provider": 30,
                "effect": "31#effect#noise",
                "pass": 0,
                "slot": 3,
                "blend": 0,
                "procedural": True,
            },
        )
        self.assertTrue(all(self.result["legacyNoiseRejects"].values()))

    def test_exact_plain_image_blend_dependency_is_typed_and_fail_closed(self) -> None:
        self.assertEqual(
            self.result["imageBlendBinding"],
            {
                "consumer": 301,
                "provider": 300,
                "effect": "image-blend",
                "pass": 0,
                "slot": 1,
                "blend": 0,
                "imageBlend": True,
            },
        )
        self.assertTrue(all(self.result["imageBlendRejects"].values()))

if __name__ == "__main__":
    unittest.main()
