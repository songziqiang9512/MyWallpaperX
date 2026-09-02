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
    Path(__file__).with_name("fixtures")
    / "SceneDependencyRenderPlanTestSupport.swift",
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT
    / "RenderGraph/LayerDependencies/SceneImageLayerBlendDependencyContract.swift",
    SOURCE_ROOT
    / "RenderGraph/LayerDependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
    SOURCE_ROOT / "RenderGraph/LayerDependencies/SceneDependencyGraphAnalysis.swift",
    SOURCE_ROOT
    / "RenderGraph/LayerDependencies/SceneDependencyRenderPlan+ImageProgramReference.swift",
    SOURCE_ROOT
    / "RenderGraph/LayerDependencies/SceneDependencyRenderPlan+ForwardPreparation.swift",
    SOURCE_ROOT / "RenderGraph/LayerDependencies/SceneDependencyRenderPlan.swift",
]

HARNESS_SOURCE = r'''
import Foundation

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
        let solidCarrierProvider = SceneRenderDescriptor.Layer(
            id: 30,
            contentKind: "solid",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let solidCarrierConsumer = SceneRenderDescriptor.Layer(
            id: 31,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [30],
            childLayerIDs: [],
            visible: true,
            effects: [slot3SolidCarrierEffect(id: 31, provider: 30)]
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
                shadowedEffect(
                    id: 423,
                    provider: shadowedProvider.id,
                    userTextureKind: .system
                ),
                shadowedEffect(
                    id: 424,
                    provider: shadowedProvider.id,
                    userTextureKind: .path
                ),
                shadowedEffect(
                    id: 425,
                    provider: shadowedProvider.id,
                    userTextureKind: .unknown
                ),
            ]
        )
        let shadowedPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [shadowedProvider, shadowedConsumer],
                renderOrderLayerIDs: [shadowedProvider.id, shadowedConsumer.id]
            ),
            visibleLayerIDs: [shadowedProvider.id, shadowedConsumer.id]
        )
        let mixedProvider = layer(1321, visible: false)
        let mixedConsumer = SceneRenderDescriptor.Layer(
            id: 1509,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [mixedProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [
                shadowedEffect(
                    id: 961,
                    provider: mixedProvider.id,
                    userTextureKind: .system
                ),
                shadowedEffect(
                    id: 962,
                    provider: mixedProvider.id,
                    userTextureKind: .system
                ),
                .init(
                    id: "suffix",
                    file: "effects/waterwaves/effect.json",
                    visible: true,
                    passes: [.init(
                        passIndex: 0,
                        texturePaths: [],
                        textureSlots: [],
                        combos: [:],
                        constantShaderValues: [:]
                    )]
                ),
            ]
        )
        let mixedProviderDescriptor = SceneRenderDescriptor(
            layers: [mixedConsumer, mixedProvider],
            renderOrderLayerIDs: [mixedConsumer.id, mixedProvider.id]
        )
        let allMixedPotentialReferences = Set(
            SceneDependencyGraphAnalysis
                .potentialOptionalNamedFallbackReferences(
                    in: mixedProviderDescriptor.layers
                )
        )
        let mixedPotentialReferences = Set(
            allMixedPotentialReferences.filter {
                $0.slot.effectID == "effect-961"
            }
        )
        let mixedProviderUnadmittedPlan = SceneDependencyRenderPlan(
            descriptor: mixedProviderDescriptor,
            visibleLayerIDs: [mixedConsumer.id]
        )
        let mixedProviderPlan = SceneDependencyRenderPlan(
            descriptor: mixedProviderDescriptor,
            visibleLayerIDs: [mixedConsumer.id],
            admittedResolvedMaterialReferences: mixedPotentialReferences
        )
        let propertyProvider = layer(1331, visible: false)
        let propertyConsumer = SceneRenderDescriptor.Layer(
            id: 1511,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [propertyProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [shadowedEffect(
                id: 963,
                provider: propertyProvider.id,
                userTextureKind: .property
            )]
        )
        let propertyDescriptor = SceneRenderDescriptor(
            layers: [propertyConsumer, propertyProvider],
            renderOrderLayerIDs: [propertyConsumer.id, propertyProvider.id]
        )
        let propertyPotentialReferences = Set(
            SceneDependencyGraphAnalysis
                .potentialOptionalNamedFallbackReferences(
                    in: propertyDescriptor.layers
                )
        )
        let propertyUnadmittedPlan = SceneDependencyRenderPlan(
            descriptor: propertyDescriptor,
            visibleLayerIDs: [propertyConsumer.id]
        )
        let propertyAdmittedPlan = SceneDependencyRenderPlan(
            descriptor: propertyDescriptor,
            visibleLayerIDs: [propertyConsumer.id],
            admittedResolvedMaterialReferences: propertyPotentialReferences
        )
        let isolatedConsumer = layer(
            1510,
            dependencies: [1331, 1332]
        )
        let isolatedProvider = layer(1331, visible: false)
        let cyclicPotentialProvider = layer(
            1332,
            dependencies: [isolatedConsumer.id],
            visible: false
        )
        let isolatedReference = SceneDependencyRenderPlan.Reference(
            consumerLayerID: isolatedConsumer.id,
            providerLayerID: isolatedProvider.id,
            slot: .init(effectID: "isolated", passIndex: 0, slotIndex: 1),
            variant: .primary
        )
        let unadmittedCycleReference = SceneDependencyRenderPlan.Reference(
            consumerLayerID: isolatedConsumer.id,
            providerLayerID: cyclicPotentialProvider.id,
            slot: .init(effectID: "cycle-out", passIndex: 0, slotIndex: 2),
            variant: .primary
        )
        let unadmittedCycleReturn = SceneDependencyRenderPlan.Reference(
            consumerLayerID: cyclicPotentialProvider.id,
            providerLayerID: isolatedConsumer.id,
            slot: .init(effectID: "cycle-back", passIndex: 0, slotIndex: 1),
            variant: .primary
        )
        let isolationLayers = [
            isolatedConsumer, isolatedProvider, cyclicPotentialProvider,
        ]
        let isolationPotentials: Set<SceneDependencyRenderPlan.Reference> = [
            isolatedReference,
            unadmittedCycleReference,
            unadmittedCycleReturn,
        ]
        let isolatedEdges = SceneDependencyRenderPlan.productDependencyEdges(
            layers: isolationLayers,
            references: [isolatedReference],
            productReferences: [],
            potentialReferences: isolationPotentials,
            admittedPotentialReferences: [isolatedReference]
        )
        let broadPotentialEdges = SceneDependencyGraphAnalysis.dependencyEdges(
            layers: isolationLayers,
            references: Array(isolationPotentials)
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
                solidCarrierProvider, solidCarrierConsumer, missingProviderConsumer,
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
        let hiddenVideoXRayLayers = [
            layer(260, visible: false),
            xRayConsumer(261, provider: 260),
        ]
        let hiddenVideoXRayDescriptor = SceneRenderDescriptor(
            layers: hiddenVideoXRayLayers,
            renderOrderLayerIDs: [261, 260]
        )
        let hiddenVideoXRayReferences = Set(
            SceneDependencyGraphAnalysis.references(
                in: hiddenVideoXRayDescriptor.layers
            )
        )
        let hiddenVideoXRayPlan = SceneDependencyRenderPlan(
            descriptor: hiddenVideoXRayDescriptor,
            visibleLayerIDs: [261],
            admittedResolvedMaterialReferences: hiddenVideoXRayReferences
        )
        let admittedHiddenVideoXRayPlan = SceneDependencyRenderPlan(
            descriptor: hiddenVideoXRayDescriptor,
            visibleLayerIDs: [261],
            admittedResolvedMaterialReferences: hiddenVideoXRayReferences
        )
        let rejectedHiddenVideoXRayPlan = SceneDependencyRenderPlan(
            descriptor: hiddenVideoXRayDescriptor,
            visibleLayerIDs: [261],
            admittedResolvedMaterialReferences: []
        )
        let parsed = [
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42")?.variant.rawValue ?? "nil",
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42_a")?.variant.rawValue ?? "nil",
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42_b")?.variant.rawValue ?? "nil",
        ]
        let solidCarrier = plan.bindingsByConsumerLayerID[31]
        let imageBlend = imageBlendBinding()
        let forwardImageBlend = imageBlendBinding(providerFirst: false)
        let forwardEffectfulImageBlend = imageBlendBinding(
            providerEffectful: true,
            providerFirst: false
        )
        let transformedImageBlend = imageBlendBinding(
            extraCombos: ["TRANSFORMUV": 1, "TRANSFORMREPEAT": 0],
            extraConstantShaderValues: [
                "blendangle": .init(components: [0]),
                "blendoffset": .init(components: [1164, 0]),
                "blendscale": .init(components: [1]),
            ]
        )
        let imageBlendWithGraphInternalPrevious = imageBlendBinding(
            sameLayerPreviousReference: true
        )
        let nonNormalTransformedImageBlend = imageBlendBinding(
            extraCombos: ["BLENDMODE": 6, "TRANSFORMUV": 1],
            extraConstantShaderValues: [
                "blendangle": .init(components: [0]),
                "blendoffset": .init(components: [100, 200]),
                "blendscale": .init(components: [1.5]),
            ],
            multiply: 1.5
        )
        let nestedImageBlend = nestedImageBlendPlan()
        let nestedProgramReference = nestedProgramReferencePlan()
        let unexplainedProgramDependency = nestedProgramReferencePlan(
            includeInactiveAlternative: false
        )
        let forwardNestedImageBlend = nestedImageBlendPlan(
            forwardToConsumer: true
        )
        let forwardNestedPreparationOrder = forwardNestedImageBlend
            .resolvedMaterialPreparationOrder(
                authoredLayerIDs: [399, 402, 400, 401]
            )
        let forwardNestedProviders = forwardNestedImageBlend
            .forwardDependencyPreparationOrder(
                authoredLayerIDs: [399, 402, 400, 401],
                activeExecutionLayerIDs: [400, 401, 402]
            )
        let brokenNestedImageBlend = nestedImageBlendPlan(
            middleDependencyMismatch: true,
            forwardToConsumer: true
        )
        let forwardPreparation = forwardPreparationPlan()
        let forwardPreparationOrder = forwardPreparation.plan
            .resolvedMaterialPreparationOrder(
                authoredLayerIDs: forwardPreparation.authoredLayerIDs
            )
        let forwardStaticPreparation = forwardPreparationPlan(
            providerEffectful: false
        )
        let forwardStaticPreparationOrder = forwardStaticPreparation.plan
            .resolvedMaterialPreparationOrder(
                authoredLayerIDs: forwardStaticPreparation.authoredLayerIDs
            )
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
            "mixedSystemNamedProvider": [
                "potentialCount": allMixedPotentialReferences.count,
                "references": mixedProviderPlan.references.count,
                "bindingKind": mixedProviderPlan.bindingsByConsumerLayerID[
                    mixedConsumer.id
                ].map { String(describing: $0.kind) } ?? "none",
                "requiresForwardCapture": mixedProviderPlan
                    .bindingsByConsumerLayerID[mixedConsumer.id]?
                    .requiresForwardCapture == true,
                "requiresProgram": mixedProviderPlan.bindingsByConsumerLayerID[
                    mixedConsumer.id
                ]?.requiresResolvedMaterialProgram == true,
                "provider": mixedProviderPlan.bindingsByConsumerLayerID[
                    mixedConsumer.id
                ]?.providerLayerID ?? -1,
                "issues": mixedProviderPlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "mixedSystemNamedUnadmitted": [
                "references": mixedProviderUnadmittedPlan.references.count,
                "binding": mixedProviderUnadmittedPlan
                    .bindingsByConsumerLayerID[mixedConsumer.id] != nil,
                "requiresEffect": mixedProviderUnadmittedPlan
                    .requiredEffectConsumerLayerIDs.contains(mixedConsumer.id),
                "consumerBlocked": mixedProviderUnadmittedPlan
                    .blocksStaticLayerSourcePassthrough(for: mixedConsumer.id),
                "providerBlocked": mixedProviderUnadmittedPlan
                    .blocksStaticLayerSourcePassthrough(for: mixedProvider.id),
            ],
            "mixedPropertyNamedProvider": [
                "potentialCount": propertyPotentialReferences.count,
                "unadmittedReferences": propertyUnadmittedPlan.references.count,
                "unadmittedBinding": propertyUnadmittedPlan
                    .bindingsByConsumerLayerID[propertyConsumer.id] != nil,
                "unadmittedConsumerBlocked": propertyUnadmittedPlan
                    .blocksStaticLayerSourcePassthrough(for: propertyConsumer.id),
                "unadmittedProviderBlocked": propertyUnadmittedPlan
                    .blocksStaticLayerSourcePassthrough(for: propertyProvider.id),
                "admittedReferences": propertyAdmittedPlan.references.count,
                "admittedBinding": propertyAdmittedPlan
                    .bindingsByConsumerLayerID[propertyConsumer.id]?
                    .requiresResolvedMaterialProgram == true,
                "admittedProvider": propertyAdmittedPlan
                    .bindingsByConsumerLayerID[propertyConsumer.id]?
                    .providerLayerID ?? -1,
            ],
            "potentialCycleIsolation": [
                "broadCycles": SceneDependencyGraphAnalysis.cyclicLayerIDs(
                    edges: broadPotentialEdges
                ).sorted(),
                "isolatedCycles": SceneDependencyGraphAnalysis.cyclicLayerIDs(
                    edges: isolatedEdges
                ).sorted(),
                "isolatedConsumerEdges": Array(
                    isolatedEdges[isolatedConsumer.id] ?? []
                ).sorted(),
                "unadmittedProviderEdges": Array(
                    isolatedEdges[cyclicPotentialProvider.id] ?? []
                ).sorted(),
            ],
            "selectedMultiReferenceAccepted":
                selectedMultiReferencePlan.bindingsByConsumerLayerID[
                    selectedMultiReferenceConsumer.id
                ]?.kind == .resolvedMaterial
                && selectedMultiReferencePlan.references.filter {
                    $0.consumerLayerID == selectedMultiReferenceConsumer.id
                }.count == 2
                && selectedMultiReferencePlan.requiredProviderLayerIDs == [
                    shadowedProvider.id
                ],
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
            "hiddenVideoXRayProgramBinding": [
                "provisional": hiddenVideoXRayPlan.bindingsByConsumerLayerID[261]?
                    .kind == .imageLayerBlend,
                "provider": hiddenVideoXRayPlan.bindingsByConsumerLayerID[261]?
                    .providerLayerID ?? -1,
                "slot": hiddenVideoXRayPlan.bindingsByConsumerLayerID[261]?
                    .slot.slotIndex ?? -1,
                "requiresProgram": hiddenVideoXRayPlan
                    .bindingsByConsumerLayerID[261]?
                    .requiresResolvedMaterialProgram ?? false,
                "forward": hiddenVideoXRayPlan.bindingsByConsumerLayerID[261]?
                    .requiresForwardCapture ?? false,
                "runtimeAdmitted": admittedHiddenVideoXRayPlan
                    .bindingsByConsumerLayerID[261] != nil,
                "runtimeRejected": rejectedHiddenVideoXRayPlan
                    .bindingsByConsumerLayerID[261] == nil,
                "providerRequired": hiddenVideoXRayPlan.requiredProviderLayerIDs
                    .contains(260),
                "consumerRequiresEffect": hiddenVideoXRayPlan
                    .requiredEffectConsumerLayerIDs.contains(261),
                "activeExecution": admittedHiddenVideoXRayPlan
                    .resolvedMaterialExecutionLayerIDs(
                        visibleRootLayerIDs: [261],
                        availableExecutionLayerIDs: [261]
                    ).sorted(),
                "inactiveExecution": admittedHiddenVideoXRayPlan
                    .resolvedMaterialExecutionLayerIDs(
                        visibleRootLayerIDs: [],
                        availableExecutionLayerIDs: [261]
                    ).sorted(),
            ],
            "solidCarrierBinding": [
                "consumer": solidCarrier?.consumerLayerID ?? -1,
                "provider": solidCarrier?.providerLayerID ?? -1,
                "effect": solidCarrier?.slot.effectID ?? "",
                "pass": solidCarrier?.slot.passIndex ?? -1,
                "slot": solidCarrier?.slot.slotIndex ?? -1,
                "blend": solidCarrier?.blendMode ?? -1,
                "solid": solidCarrier?.kind == .solidLayer,
            ],
            "solidCarrierRoute": [
                "binding": solidCarrier != nil,
                "solid": solidCarrier?.kind == .solidLayer,
                "requiredEffect": plan.requiredEffectConsumerLayerIDs.contains(31),
                "requiredProvider": plan.requiredProviderLayerIDs.contains(30),
                "issues": plan.issues.filter { $0.layerID == 31 }.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "solidCarrierWithoutExecutableID": [
                "binding": defaultPlan.bindingsByConsumerLayerID[31] != nil,
                "requiredEffect": defaultPlan.requiredEffectConsumerLayerIDs.contains(31),
                "requiredProvider": defaultPlan.requiredProviderLayerIDs.contains(30),
                "issues": defaultPlan.issues.filter { $0.layerID == 31 }.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "solidCarrierGeneralizesAuthoredShaderShape":
                solidCarrierBinding(
                    effectPath: "effects/workshop/unseen/volumetric_cloud/effect.json",
                    extraCombos: ["AB_TYPECOLOR": 27, "UNSEEN_COMBO": 9],
                    constantShaderValues: [
                        "Unseen Constant": .init(components: [0.125, 4]),
                    ]
                )?.kind == .solidLayer,
            "solidCarrierRejects": [
                "visibleProvider": solidCarrierBinding(providerVisible: true) == nil,
                "wrongProviderKind": solidCarrierBinding(providerContentKind: "image") == nil,
                "providerUtility": solidCarrierBinding(providerUtility: true) == nil,
                "effectfulProvider": solidCarrierBinding(providerEffectful: true) == nil,
                "secondary": solidCarrierBinding(variantSuffix: "b") == nil,
                "wrongPass": solidCarrierBinding(passIndex: 1) == nil,
                "wrongSlot": solidCarrierBinding(slotIndex: 2) == nil,
                "userTextureOverride": solidCarrierBinding(userTextureOverride: true) == nil,
                "extraPass": solidCarrierBinding(extraPass: true) == nil,
                "extraReference": solidCarrierBinding(extraReference: true) == nil,
                "forwardProvider": solidCarrierBinding(providerFirst: false) == nil,
                "cycle": solidCarrierBinding(providerDependencies: [91]) == nil,
            ],
            "imageBlendBinding": [
                "consumer": imageBlend?.consumerLayerID ?? -1,
                "provider": imageBlend?.providerLayerID ?? -1,
                "effect": imageBlend?.slot.effectID ?? "",
                "pass": imageBlend?.slot.passIndex ?? -1,
                "slot": imageBlend?.slot.slotIndex ?? -1,
                "blend": imageBlend?.blendMode ?? -1,
                "imageBlend": imageBlend?.kind == .imageLayerBlend,
                "forwardCapture": imageBlend?.requiresForwardCapture ?? false,
            ],
            "forwardImageBlendBinding": [
                "consumer": forwardImageBlend?.consumerLayerID ?? -1,
                "provider": forwardImageBlend?.providerLayerID ?? -1,
                "imageBlend": forwardImageBlend?.kind == .imageLayerBlend,
                "forwardCapture": forwardImageBlend?.requiresForwardCapture ?? false,
            ],
            "forwardEffectfulImageBlendBinding": [
                "consumer": forwardEffectfulImageBlend?.consumerLayerID ?? -1,
                "provider": forwardEffectfulImageBlend?.providerLayerID ?? -1,
                "imageBlend": forwardEffectfulImageBlend?.kind == .imageLayerBlend,
                "forwardCapture": forwardEffectfulImageBlend?
                    .requiresForwardCapture ?? false,
            ],
            "forwardEffectfulPreparationOrder": [
                "authored": forwardPreparation.authoredLayerIDs,
                "prepared": forwardPreparationOrder ?? [],
                "duplicateRejected": forwardPreparation.plan
                    .resolvedMaterialPreparationOrder(
                        authoredLayerIDs:
                            forwardPreparation.authoredLayerIDs + [900]
                    ) == nil,
            ],
            "forwardStaticPreparationOrder": [
                "authored": forwardStaticPreparation.authoredLayerIDs,
                "prepared": forwardStaticPreparationOrder ?? [],
            ],
            "transformedImageBlendBinding": [
                "provider": transformedImageBlend?.providerLayerID ?? -1,
                "imageBlend": transformedImageBlend?.kind == .imageLayerBlend,
                "requiresProgram": transformedImageBlend?
                    .requiresResolvedMaterialProgram ?? false,
            ],
            "imageBlendWithGraphInternalPrevious": [
                "provider": imageBlendWithGraphInternalPrevious?
                    .providerLayerID ?? -1,
                "requiresProgram": imageBlendWithGraphInternalPrevious?
                    .requiresResolvedMaterialProgram ?? false,
            ],
            "nonNormalTransformedImageBlend": [
                "provider": nonNormalTransformedImageBlend?
                    .providerLayerID ?? -1,
                "blend": nonNormalTransformedImageBlend?.blendMode ?? -1,
                "requiresProgram": nonNormalTransformedImageBlend?
                    .requiresResolvedMaterialProgram ?? false,
            ],
            "programRequiredRuntimeRejects": [
                "transform": imageBlendBinding(
                    extraCombos: ["TRANSFORMUV": 1],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "graphInternal": imageBlendBinding(
                    sameLayerPreviousReference: true,
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
            ],
            "imageBlendRejects": [
                "visibleProvider": imageBlendBinding(providerVisible: true) == nil,
                "wrongProviderKind": imageBlendBinding(providerContentKind: "solid") == nil,
                "secondary": imageBlendBinding(variantSuffix: "b") == nil,
                "userTextureOverride": imageBlendBinding(userTextureOverride: true) == nil,
                "extraReference": imageBlendBinding(extraReference: true) == nil,
                "invalidTransform": imageBlendBinding(
                    extraCombos: ["TRANSFORMUV": 2],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "repeatWithoutTransform": imageBlendBinding(
                    extraCombos: ["TRANSFORMREPEAT": 1],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "invalidTransformOffset": imageBlendBinding(
                    extraCombos: ["TRANSFORMUV": 1],
                    extraConstantShaderValues: [
                        "blendoffset": .init(components: [1]),
                    ],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "invalidTransformScale": imageBlendBinding(
                    extraCombos: ["TRANSFORMUV": 1],
                    extraConstantShaderValues: [
                        "blendscale": .init(components: [0]),
                    ],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "invalidBlendMode": imageBlendBinding(
                    extraCombos: ["BLENDMODE": 33],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
            ],
            "partialStrengthRequiresProgram":
                imageBlendBinding(multiply: 0.5)?
                    .requiresResolvedMaterialProgram == true,
            "imageBlendEffectfulProvider":
                imageBlendBinding(providerEffectful: true)?.providerLayerID == 300,
            "forwardImageBlendOrderIndependentAssetProvider":
                imageBlendBinding(
                    providerEffectful: true,
                    providerTexturePaths: ["assets/noise.tex"],
                    providerFirst: false
                )?.providerLayerID == 300,
            "forwardImageBlendRejects": [
                "inactiveEffect": imageBlendBinding(
                    providerEffectful: true,
                    providerEffectVisible: false,
                    providerFirst: false
                ) == nil,
                "dependency": imageBlendBinding(
                    providerDependencies: [299], providerFirst: false
                ) == nil,
                "child": imageBlendBinding(
                    providerChildLayerIDs: [302], providerFirst: false
                ) == nil,
                "secondary": imageBlendBinding(
                    variantSuffix: "b", providerFirst: false
                ) == nil,
                "sceneBackground": imageBlendBinding(
                    providerEffectful: true,
                    providerTexturePaths: ["_rt_FullFrameBuffer"],
                    providerFirst: false
                ) == nil,
                "implicitNamedInput": imageBlendBinding(
                    providerEffectful: true,
                    providerTexturePaths: ["_rt_imageLayerComposite_299_a"],
                    providerFirst: false
                ) == nil,
            ],
            "nestedImageBlend": [
                "bindings": nestedImageBlend.bindingsByConsumerLayerID.keys.sorted(),
                "providers": nestedImageBlend.requiredProviderLayerIDs.sorted(),
                "graphProviders": nestedImageBlend
                    .requiredGraphOutputProviderLayerIDs.sorted(),
                "effectConsumers": nestedImageBlend
                    .requiredEffectConsumerLayerIDs.sorted(),
                "passthroughBlocked": [400, 401, 402].filter {
                    nestedImageBlend.blocksStaticLayerSourcePassthrough(for: $0)
                },
                "issues": nestedImageBlend.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "nestedProgramReference": [
                "bindings": nestedProgramReference
                    .bindingsByConsumerLayerID.keys.sorted(),
                "providers": nestedProgramReference
                    .requiredProviderLayerIDs.sorted(),
                "graphProviders": nestedProgramReference
                    .requiredGraphOutputProviderLayerIDs.sorted(),
                "effectConsumers": nestedProgramReference
                    .requiredEffectConsumerLayerIDs.sorted(),
                "issues": nestedProgramReference.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "unexplainedProgramDependencyRejected":
                unexplainedProgramDependency.bindingsByConsumerLayerID[502]
                    == nil,
            "forwardNestedImageBlend": [
                "bindings": forwardNestedImageBlend
                    .bindingsByConsumerLayerID.keys.sorted(),
                "providers": forwardNestedImageBlend
                    .requiredProviderLayerIDs.sorted(),
                "graphProviders": forwardNestedImageBlend
                    .requiredGraphOutputProviderLayerIDs.sorted(),
                "forwardProviders": forwardNestedProviders ?? [],
                "prepared": forwardNestedPreparationOrder ?? [],
                "issues": forwardNestedImageBlend.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "brokenNestedImageBlend": [
                "bindings": brokenNestedImageBlend
                    .bindingsByConsumerLayerID.keys.sorted(),
                "providers": brokenNestedImageBlend.requiredProviderLayerIDs.sorted(),
                "graphProviders": brokenNestedImageBlend
                    .requiredGraphOutputProviderLayerIDs.sorted(),
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
        provider: Int,
        userTextureKind: SceneEffectTextureInput.Kind = .property
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
                userTextureInputs: [nil, .init(
                    kind: userTextureKind,
                    value: userTextureKind == .system
                        ? "$mediaThumbnail" : "userTexture"
                )],
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

    static func slot3SolidCarrierEffect(
        id: Int,
        provider: Int,
        effectPath: String = "effects/workshop/2924967132/procedural_noise/effect.json",
        passIndex: Int = 0,
        slotIndex: Int = 3,
        variantSuffix: String = "a",
        extraCombos: [String: Int] = [:],
        constantShaderValues: [String: SceneDocument.ShaderValue] = [:],
        userTextureOverride: Bool = false,
        extraPass: Bool = false,
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
        let mainPass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: passIndex,
            texturePaths: extraReference
                ? [path, "_rt_imageLayerComposite_\(provider)_a"] : [path],
            textureSlots: slots,
            userTextureInputs: userTextureOverride ? [
                nil, nil, nil,
                .init(kind: .property, value: "userTexture"),
            ] : [],
            combos: combos,
            constantShaderValues: constantShaderValues
        )
        let passes: [SceneRenderDescriptor.EffectDescriptor.PassDescriptor]
        if extraPass {
            passes = [
                mainPass,
                .init(
                    passIndex: 1,
                    textureSlots: [],
                    combos: [:],
                    constantShaderValues: [:]
                ),
            ]
        } else {
            passes = [mainPass]
        }
        return .init(
            id: "\(id)#effect#slot3-solid",
            file: effectPath,
            visible: true,
            passes: passes
        )
    }

    static func solidCarrierBinding(
        providerVisible: Bool? = false,
        providerContentKind: String = "solid",
        providerUtility: Bool = false,
        providerEffectful: Bool = false,
        providerDependencies: [Int] = [],
        providerFirst: Bool = true,
        effectPath: String = "effects/workshop/2924967132/procedural_noise/effect.json",
        passIndex: Int = 0,
        slotIndex: Int = 3,
        variantSuffix: String = "a",
        extraCombos: [String: Int] = [:],
        constantShaderValues: [String: SceneDocument.ShaderValue] = [:],
        userTextureOverride: Bool = false,
        extraPass: Bool = false,
        extraReference: Bool = false
    ) -> SceneDependencyRenderPlan.Binding? {
        let providerID = 90
        let consumerID = 91
        let providerEffects: [SceneRenderDescriptor.EffectDescriptor] =
            providerEffectful ? [.init(
                id: "provider-effect",
                file: "effects/unseen/provider/effect.json",
                visible: true,
                passes: []
            )] : []
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: providerContentKind,
            utilityLayer: providerUtility ? .init(kind: .composition) : nil,
            dependencyLayerIDs: providerDependencies,
            childLayerIDs: [],
            visible: providerVisible,
            effects: providerEffects
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [slot3SolidCarrierEffect(
                id: consumerID,
                provider: providerID,
                effectPath: effectPath,
                passIndex: passIndex,
                slotIndex: slotIndex,
                variantSuffix: variantSuffix,
                extraCombos: extraCombos,
                constantShaderValues: constantShaderValues,
                userTextureOverride: userTextureOverride,
                extraPass: extraPass,
                extraReference: extraReference
            )]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer],
            renderOrderLayerIDs: providerFirst
                ? [providerID, consumerID] : [consumerID, providerID]
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
        providerEffectVisible: Bool? = true,
        providerTexturePaths: [String] = [],
        providerDependencies: [Int] = [],
        providerChildLayerIDs: [Int] = [],
        variantSuffix: String = "a",
        userTextureOverride: Bool = false,
        extraReference: Bool = false,
        dependencyMismatch: Bool = false,
        extraCombos: [String: Int] = [:],
        extraConstantShaderValues: [String: SceneDocument.ShaderValue] = [:],
        sameLayerPreviousReference: Bool = false,
        resolvedMaterialConsumerLayerIDs: Set<Int>? = nil,
        multiply: Double = 1,
        providerFirst: Bool = true
    ) -> SceneDependencyRenderPlan.Binding? {
        let providerID = 300
        let consumerID = 301
        let providerEffects: [SceneRenderDescriptor.EffectDescriptor] = providerEffectful
            ? [.init(
                id: "provider-effect",
                file: "effects/tint/effect.json",
                visible: providerEffectVisible,
                passes: providerTexturePaths.isEmpty ? [] : [.init(
                    passIndex: 0,
                    texturePaths: providerTexturePaths,
                    textureSlots: providerTexturePaths.map(Optional.some),
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                )]
            )] : []
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: providerContentKind,
            utilityLayer: nil,
            dependencyLayerIDs: providerDependencies,
            childLayerIDs: providerChildLayerIDs,
            visible: providerVisible,
            effects: providerEffects
        )
        let primary = "_rt_imageLayerComposite_\(providerID)_\(variantSuffix)"
        let extra = "_rt_imageLayerComposite_299_a"
        var slots: [String?] = [nil, primary]
        if extraReference { slots.append(extra) }
        var combos = ["BLENDMODE": 0]
        combos.merge(extraCombos) { _, new in new }
        var constantShaderValues: [String: SceneDocument.ShaderValue] = [
            "multiply": .init(components: [multiply]),
            "alpha": .init(components: [1]),
        ]
        constantShaderValues.merge(extraConstantShaderValues) { _, new in new }
        let blend = SceneRenderDescriptor.EffectDescriptor(
            id: "image-blend",
            file: "effects/blend/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: extraReference ? [primary, extra] : [primary],
                textureSlots: slots,
                userTextureInputs: userTextureOverride ? [
                    nil,
                    .init(kind: .property, value: "userTexture"),
                ] : [],
                combos: combos,
                constantShaderValues: constantShaderValues
            )]
        )
        let previousPath = "_rt_imageLayerComposite_\(consumerID)_b"
        let graphInternalPrevious = SceneRenderDescriptor.EffectDescriptor(
            id: "graph-internal-previous",
            file: "effects/localcontrast/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: [previousPath],
                textureSlots: [nil, previousPath],
                userTextureInputs: [],
                combos: [:],
                constantShaderValues: [:]
            )]
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: dependencyMismatch ? [299] : [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [blend] + (sameLayerPreviousReference
                ? [graphInternalPrevious] : [])
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer],
            renderOrderLayerIDs: providerFirst
                ? [providerID, consumerID] : [consumerID, providerID]
        )
        let admittedReferences: Set<SceneDependencyRenderPlan.Reference> =
            resolvedMaterialConsumerLayerIDs == [] ? [] : Set(
                SceneDependencyGraphAnalysis.references(in: descriptor.layers)
            )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [consumerID],
            admittedResolvedMaterialReferences: admittedReferences
        ).bindingsByConsumerLayerID[consumerID]
    }

    static func nestedImageBlendPlan(
        middleDependencyMismatch: Bool = false,
        forwardToConsumer: Bool = false
    ) -> SceneDependencyRenderPlan {
        func blend(_ id: Int, provider: Int) ->
            SceneRenderDescriptor.EffectDescriptor {
            let path = "_rt_imageLayerComposite_\(provider)_a"
            return .init(
                id: "blend-\(id)",
                file: "effects/blend/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [path],
                    textureSlots: [nil, path],
                    combos: ["BLENDMODE": 0],
                    constantShaderValues: [
                        "multiply": .init(components: [1]),
                        "alpha": .init(components: [1]),
                    ]
                )]
            )
        }
        let rootProvider = SceneRenderDescriptor.Layer(
            id: 400,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: [.init(
                id: "provider-color",
                file: "effects/tint/effect.json",
                visible: true,
                passes: []
            )]
        )
        let middleProvider = SceneRenderDescriptor.Layer(
            id: 401,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: middleDependencyMismatch ? [499] : [400],
            childLayerIDs: [],
            visible: false,
            effects: [blend(401, provider: 400)]
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: 402,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [401],
            childLayerIDs: [],
            visible: true,
            effects: [blend(402, provider: 401)]
        )
        let independent = SceneRenderDescriptor.Layer(
            id: 399,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: true,
            effects: []
        )
        let descriptor = SceneRenderDescriptor(
            layers: [independent, rootProvider, middleProvider, consumer],
            renderOrderLayerIDs: forwardToConsumer
                ? [399, 402, 400, 401] : [399, 400, 401, 402]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [402]
        )
    }

    static func nestedProgramReferencePlan(
        includeInactiveAlternative: Bool = true
    ) -> SceneDependencyRenderPlan {
        func programEffect(_ id: Int, provider: Int) ->
            SceneRenderDescriptor.EffectDescriptor {
            let path = "_rt_imageLayerComposite_\(provider)_a"
            return .init(
                id: "program-reference-\(id)",
                file: "effects/workshop/unseen/program/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [path, "util/white"],
                    textureSlots: [nil, path, "util/white"],
                    combos: ["UNSEEN": 7],
                    constantShaderValues: [
                        "amount": .init(components: [0.375]),
                    ]
                )]
            )
        }
        let root = SceneRenderDescriptor.Layer(
            id: 500,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: [.init(
                id: "root-effect",
                file: "effects/workshop/unseen/root/effect.json",
                visible: true,
                passes: []
            )]
        )
        let middle = SceneRenderDescriptor.Layer(
            id: 501,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [root.id],
            childLayerIDs: [],
            visible: false,
            effects: [
                .init(
                    id: "middle-prefix",
                    file: "effects/workshop/unseen/prefix/effect.json",
                    visible: true,
                    passes: []
                ),
                programEffect(501, provider: root.id),
            ]
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: 502,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [middle.id, 503],
            childLayerIDs: [],
            visible: true,
            effects: [
                .init(
                    id: "consumer-prefix",
                    file: "effects/workshop/unseen/prefix/effect.json",
                    visible: true,
                    passes: []
                ),
                programEffect(502, provider: middle.id),
            ] + (includeInactiveAlternative ? [
                .init(
                    id: "inactive-alternative",
                    file: "effects/workshop/unseen/alternate/effect.json",
                    visible: false,
                    passes: [.init(
                        passIndex: 0,
                        texturePaths: ["_rt_imageLayerComposite_503_a"],
                        textureSlots: [
                            nil, "_rt_imageLayerComposite_503_a",
                        ],
                        combos: [:],
                        constantShaderValues: [:]
                    )]
                ),
            ] : [])
        )
        let inactiveAlternative = SceneRenderDescriptor.Layer(
            id: 503,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let descriptor = SceneRenderDescriptor(
            layers: [root, middle, inactiveAlternative, consumer],
            renderOrderLayerIDs: [
                root.id, middle.id, inactiveAlternative.id, consumer.id,
            ]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [consumer.id],
            admittedResolvedMaterialReferences: Set(
                SceneDependencyGraphAnalysis.references(in: descriptor.layers)
            )
        )
    }

    static func forwardPreparationPlan(
        providerEffectful: Bool = true
    ) -> (
        plan: SceneDependencyRenderPlan,
        authoredLayerIDs: [Int]
    ) {
        let providerID = 300
        let consumerID = 301
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: providerEffectful ? [.init(
                id: "provider-effect",
                file: "effects/tint/effect.json",
                visible: true,
                passes: []
            )] : []
        )
        let reference = "_rt_imageLayerComposite_\(providerID)_a"
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [.init(
                id: "image-blend",
                file: "effects/blend/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [reference],
                    textureSlots: [nil, reference],
                    combos: ["BLENDMODE": 0],
                    constantShaderValues: [
                        "multiply": .init(components: [1]),
                        "alpha": .init(components: [1]),
                    ]
                )]
            )]
        )
        let independentLayerIDs = [800, 850, 900]
        let independent = independentLayerIDs.map { layer($0) }
        let authored = [800, consumerID, 850, providerID, 900]
        let descriptor = SceneRenderDescriptor(
            layers: independent + [provider, consumer],
            renderOrderLayerIDs: authored
        )
        let admittedReferences = Set(
            SceneDependencyGraphAnalysis.references(in: descriptor.layers)
        )
        return (
            SceneDependencyRenderPlan(
                descriptor: descriptor,
                visibleLayerIDs: Set(independentLayerIDs + [consumerID]),
                admittedResolvedMaterialReferences: admittedReferences
            ),
            authored
        )
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
                "issues": ["401:namedProviderRouteDisabled:400"],
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
                "issues": ["411:namedProviderRouteDisabled:410"],
            },
        )
        self.assertEqual(
            self.result["solidCarrierRoute"],
            {
                "binding": True,
                "solid": True,
                "requiredEffect": True,
                "requiredProvider": True,
                "issues": [],
            },
        )
        self.assertEqual(
            self.route_disabled_result["solidCarrierRoute"],
            {
                "binding": False,
                "solid": False,
                "requiredEffect": True,
                "requiredProvider": False,
                "issues": ["31:namedProviderRouteDisabled:30"],
            },
        )

        self.assertEqual(
            self.result["solidCarrierWithoutExecutableID"],
            {
                "binding": False,
                "requiredEffect": False,
                "requiredProvider": False,
                "issues": ["31:unsupportedConsumer:-1"],
            },
        )

        self.assertEqual(
            self.route_disabled_result["solidCarrierWithoutExecutableID"],
            {
                "binding": False,
                "requiredEffect": True,
                "requiredProvider": False,
                "issues": ["31:namedProviderRouteDisabled:30"],
            },
        )
        self.assertEqual(
            self.route_disabled_result["imageBlendBinding"],
            {
                "consumer": -1,
                "provider": -1,
                "effect": "",
                "pass": -1,
                "slot": -1,
                "blend": -1,
                "imageBlend": False,
                "forwardCapture": False,
            },
        )
        self.assertEqual(
            self.route_disabled_result["nestedImageBlend"],
            {
                "bindings": [],
                "providers": [],
                "graphProviders": [],
                "effectConsumers": [401, 402],
                # Route rollback keeps both provider identities blocked, but
                # the terminal unbound consumer may retain its base source.
                "passthroughBlocked": [400, 401],
                "issues": [
                    "401:namedProviderRouteDisabled:400",
                    "402:namedProviderRouteDisabled:401",
                ],
            },
        )

    def test_only_exact_optional_user_texture_retains_lower_named_dependency(
        self,
    ) -> None:
        self.assertEqual(
            self.result["shadowedNamedReferences"],
            {
                "referenceCount": 1,
                "binding": True,
                "provider": 420,
                "issues": [],
            },
        )

    def test_mixed_system_named_provider_builds_forward_program_binding(
        self,
    ) -> None:
        self.assertEqual(
            self.result["mixedSystemNamedProvider"],
            {
                "potentialCount": 2,
                "references": 1,
                "bindingKind": "imageLayerBlend",
                "requiresForwardCapture": True,
                "requiresProgram": True,
                "provider": 1321,
                "issues": [],
            },
            self.result,
        )
        self.assertEqual(
            self.result["mixedSystemNamedUnadmitted"],
            {
                "references": 0,
                "binding": False,
                "requiresEffect": False,
                "consumerBlocked": False,
                "providerBlocked": False,
            },
            self.result,
        )
        self.assertTrue(self.result["selectedMultiReferenceAccepted"])
        self.assertEqual(
            self.result["potentialCycleIsolation"],
            {
                "broadCycles": [1332, 1510],
                "isolatedCycles": [],
                "isolatedConsumerEdges": [1331],
                "unadmittedProviderEdges": [],
            },
            self.result,
        )

    def test_mixed_property_named_provider_requires_exact_program_admission(
        self,
    ) -> None:
        self.assertEqual(
            self.result["mixedPropertyNamedProvider"],
            {
                "potentialCount": 1,
                "unadmittedReferences": 0,
                "unadmittedBinding": False,
                "unadmittedConsumerBlocked": False,
                "unadmittedProviderBlocked": False,
                "admittedReferences": 1,
                "admittedBinding": True,
                "admittedProvider": 1331,
            },
        )

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

    def test_unbound_consumer_preserves_base_while_provider_stays_blocked(self) -> None:
        self.assertEqual(
            self.result["staticPassthroughBlocks"],
            {
                "namedProvider": True,
                "namedConsumer": False,
                "hiddenNamedProvider": False,
                "hiddenNamedConsumer": False,
                "selfReference": False,
                "unreferenced": False,
                "explicitProvider": True,
                "explicitConsumer": False,
                "requiredProvidersEmpty": True,
            },
        )

    def test_unbound_xray_shapes_keep_provider_sided_safety(
        self,
    ) -> None:
        self.assertEqual(
            self.result["staticPassthroughXRayBlocks"],
            {
                "exemptConsumer": False,
                "xRayProvider": True,
                "extraDependency": False,
                "opacityMaskCombo": False,
                "blendModeCombo": False,
                "nonStockDefinition": False,
                "secondNamedSlot": False,
                "mismatchedProvider": False,
                "secondNamedReference": False,
                "multiplePasses": False,
                "exemptThenProvider": True,
                "upperConsumer": False,
            },
        )

    def test_xray_provider_safety_does_not_block_unbound_consumer_fallback(
        self,
    ) -> None:
        self.assertEqual(
            self.result["isolatedXRayPassthroughBlocks"],
            {
                "exactProvider": True,
                "exactConsumer": False,
                "missingProviderConsumer": False,
                "unverifiedStockPathProvider": True,
                "unverifiedStockPathConsumer": False,
                "multiEffectProvider": True,
                "multiEffectConsumer": False,
            },
        )

    def test_hidden_image_provider_is_a_program_gated_external_primary(self) -> None:
        self.assertEqual(
            self.result["hiddenVideoXRayProgramBinding"],
            {
                "provisional": True,
                "provider": 260,
                "slot": 1,
                "requiresProgram": True,
                "forward": True,
                "runtimeAdmitted": True,
                "runtimeRejected": True,
                "providerRequired": True,
                "consumerRequiresEffect": True,
                "activeExecution": [261],
                "inactiveExecution": [],
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
            "SceneXRayStockIdentityVerifier.verifiedStockIdentityEffectKeys(",
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

    def test_parent_aware_visibility_precedes_layer_draw_request(self) -> None:
        renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8")
        visibility_guard = renderer.index(
            "guard frameVisibleLayerIDs.contains(layer.id) else { continue }"
        )
        draw_outcome = renderer.index("let drawOutcome = imageCompositor.drawOutcome(")
        self.assertLess(visibility_guard, draw_outcome)

    def test_forward_image_provider_preparation_precedes_authored_layer_loop(self) -> None:
        renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8")
        dependency_runtime = DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        main_pass = renderer.index("let mainPass = SceneMainPassEncoder(")
        forward_preparation = renderer.index(
            "prepareForwardDependencyProviders(", main_pass
        )
        authored_loop = renderer.index("frameLayers: for layer in orderedLayers")
        self.assertLess(main_pass, forward_preparation)
        self.assertLess(forward_preparation, authored_loop)
        prepass = renderer[forward_preparation:authored_loop]
        self.assertIn("framePlans: resolvedMaterialFrameTargetPlans", prepass)
        self.assertIn(
            ".forwardDependencyPreparationOrder(\n"
            "                    authoredLayerIDs: orderedLayers.map(\\.id),\n"
            "                    activeExecutionLayerIDs: activeExecutionLayerIDs",
            renderer,
        )
        self.assertIn(
            "resolvedMaterialExecutionLayerIDs(",
            dependency_runtime,
        )
        self.assertIn(
            "executeDependencyGraphProviderIfRequired(",
            renderer[renderer.index("private func prepareForwardDependencyProviders("):],
        )
        self.assertIn(
            "forwardGraphProviderLayerIDs.contains(layer.id)",
            renderer,
        )
        self.assertIn(
            "$0.requiresForwardCapture",
            dependency_runtime,
        )

    def test_structural_slot3_hidden_solid_dependency_is_generic_and_fail_closed(
        self,
    ) -> None:
        self.assertEqual(
            self.result["solidCarrierBinding"],
            {
                "consumer": 31,
                "provider": 30,
                "effect": "31#effect#slot3-solid",
                "pass": 0,
                "slot": 3,
                "blend": 0,
                "solid": True,
            },
        )
        self.assertTrue(self.result["solidCarrierGeneralizesAuthoredShaderShape"])
        self.assertTrue(all(self.result["solidCarrierRejects"].values()))

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
                "forwardCapture": False,
            },
        )
        self.assertEqual(
            self.result["forwardImageBlendBinding"],
            {
                "consumer": 301,
                "provider": 300,
                "imageBlend": True,
                "forwardCapture": True,
            },
        )
        self.assertEqual(
            self.result["forwardEffectfulImageBlendBinding"],
            {
                "consumer": 301,
                "provider": 300,
                "imageBlend": True,
                "forwardCapture": True,
            },
        )
        self.assertEqual(
            self.result["forwardEffectfulPreparationOrder"],
            {
                "authored": [800, 301, 850, 300, 900],
                "prepared": [300, 800, 301, 850, 900],
                "duplicateRejected": True,
            },
        )
        self.assertEqual(
            self.result["forwardStaticPreparationOrder"],
            {
                "authored": [800, 301, 850, 300, 900],
                "prepared": [800, 301, 850, 300, 900],
            },
        )
        self.assertEqual(
            self.result["transformedImageBlendBinding"],
            {"provider": 300, "imageBlend": True, "requiresProgram": True},
        )
        self.assertEqual(
            self.result["imageBlendWithGraphInternalPrevious"],
            {"provider": 300, "requiresProgram": True},
        )
        self.assertEqual(
            self.result["nonNormalTransformedImageBlend"],
            {"provider": 300, "blend": 6, "requiresProgram": True},
        )
        self.assertTrue(all(self.result["programRequiredRuntimeRejects"].values()))
        self.assertTrue(self.result["partialStrengthRequiresProgram"])
        self.assertTrue(all(self.result["imageBlendRejects"].values()))
        self.assertTrue(self.result["imageBlendEffectfulProvider"])
        self.assertTrue(
            self.result["forwardImageBlendOrderIndependentAssetProvider"]
        )
        self.assertTrue(all(self.result["forwardImageBlendRejects"].values()))
        self.assertEqual(
            self.result["nestedImageBlend"],
            {
                "bindings": [401, 402],
                "providers": [400, 401],
                "graphProviders": [400, 401],
                "effectConsumers": [401, 402],
                "passthroughBlocked": [400, 401, 402],
                "issues": [],
            },
        )
        self.assertEqual(
            self.result["nestedProgramReference"],
            {
                "bindings": [501, 502],
                "providers": [500, 501],
                "graphProviders": [500, 501],
                "effectConsumers": [501, 502],
                "issues": [],
            },
        )
        self.assertTrue(
            self.result["unexplainedProgramDependencyRejected"]
        )
        self.assertEqual(
            self.result["forwardNestedImageBlend"],
            {
                "bindings": [401, 402],
                "providers": [400, 401],
                "graphProviders": [400, 401],
                "forwardProviders": [400, 401],
                "prepared": [400, 401, 399, 402],
                "issues": [],
            },
        )
        self.assertEqual(
            self.result["brokenNestedImageBlend"],
            {"bindings": [], "providers": [], "graphProviders": []},
        )

if __name__ == "__main__":
    unittest.main()
