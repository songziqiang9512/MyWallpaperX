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
    SOURCE_ROOT / "SceneShaderContract.swift",
    SOURCE_ROOT / "SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "SceneAuthoredLocalContrastPlanner.swift",
    SOURCE_ROOT / "SceneAuthoredEffectExecutionChain.swift",
    SOURCE_ROOT / "SceneAuthoredEffectExecutionPlan.swift",
    SOURCE_ROOT / "SceneAuthoredStandardBlurPlanner.swift",
    SOURCE_ROOT / "SceneGraphRenderTargetPlan.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "vector",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}

struct SceneEffectTextureInput {
    let name: String
}

struct SceneGaussianBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let sampleResolutionScale: Float
    let isPrecise: Bool
}

struct SceneWorkshopShadowExecutionPlan: Equatable, Sendable {
    let alpha: Float
    let color: SIMD3<Float>
    let drawBorder: Float
    let offset: SIMD2<Float>
}

enum SceneAuthoredWorkshopShadowPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopShadowExecutionPlan? {
        nil
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let parentID: Int?
        let visible: Bool?
        let contentKind: String
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let shaderPath: String?
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return Set(descriptor.layers.compactMap { layer in
            var current: SceneRenderDescriptor.Layer? = layer
            var visited = Set<Int>()
            while let candidate = current {
                guard candidate.visible != false, visited.insert(candidate.id).inserted else {
                    return nil
                }
                current = candidate.parentID.flatMap { byID[$0] }
            }
            return layer.id
        })
    }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func texture(
        _ kind: Graph.TextureKind,
        layerID: Int,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func instanceEffect(
        layerID: Int,
        scale: Double = 1.28,
        scaleComponents: [Double]? = nil,
        valueKind: String = "vector",
        userBinding: String? = nil,
        duplicateScaleKey: Bool = false
    ) -> SceneRenderDescriptor.EffectDescriptor {
        var scaleValues = [
            "scale": SceneDocument.ShaderValue(
                valueKind: valueKind,
                userBinding: userBinding,
                components: scaleComponents ?? [scale, scale]
            ),
        ]
        if duplicateScaleKey {
            scaleValues["Scale"] = .init(components: [scale, scale])
        }
        return .init(
            id: "\(layerID)#effect#1",
            visible: true,
            passes: [
                .init(
                    passIndex: 0, textureSlots: [], userTextureInputs: [], combos: [:],
                    constantShaderValues: scaleValues
                ),
                .init(
                    passIndex: 1, textureSlots: [], userTextureInputs: [],
                    combos: ["VERTICAL": 1, "ENABLEMASK": 1],
                    constantShaderValues: scaleValues
                ),
            ]
        )
    }

    static func materials(
        shader: String = "workshop/1/effects/blur_precise_gaussian",
        blending: String = "normal",
        verticalCombos: [String: Int] = ["VERTICAL": 1, "ENABLEMASK": 1]
    ) -> [SceneRenderDescriptor.MaterialPassDescriptor] {
        [
            .init(
                id: "materials/x.json#0", materialPath: "materials/x.json",
                shaderPath: shader, textureSlots: [], userTextureInputs: [],
                combos: [:], constantShaderValues: [:],
                blending: blending, depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull"
            ),
            .init(
                id: "materials/y.json#0", materialPath: "materials/y.json",
                shaderPath: shader, textureSlots: [], userTextureInputs: [],
                combos: verticalCombos,
                constantShaderValues: [:], blending: blending, depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull"
            ),
        ]
    }

    static func descriptorForLayer10(
        effect: SceneRenderDescriptor.EffectDescriptor
    ) -> SceneRenderDescriptor {
        .init(
            layers: [
                .init(
                    id: 10, parentID: nil, visible: true, contentKind: "text",
                    effects: [effect]
                ),
            ],
            materialPasses: materials()
        )
    }

    static func graph(
        layerID: Int,
        blockers: [Graph.Blocker] = [],
        extraEffect: Bool = false,
        unique: Bool = false,
        maskCombo: Bool = false
    ) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "\(layerID)#effect#1"
        )
        let source = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let rt = texture(.framebuffer, layerID: layerID, effect: key, name: "full")
        let nodes = [
            Graph.Node(
                nodeIndex: 0, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
                instancePassIndex: 0, kind: .material, materialPath: "materials/x.json",
                materialPassID: "materials/x.json#0", target: rt, bindings: [],
                commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
            ),
            Graph.Node(
                nodeIndex: 1, effect: key, definitionPassIndex: 1, materialOrdinal: 1,
                instancePassIndex: 1, kind: .material, materialPath: "materials/y.json",
                materialPassID: "materials/y.json#0", target: output,
                bindings: [
                    .init(slot: 0, authoredName: "full", texture: rt, conditions: nil),
                    .init(slot: maskCombo ? 2 : 1, authoredName: "previous", texture: source, conditions: nil),
                ], commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
            ),
        ]
        let effect = Graph.Effect(
            key: key, definitionPath: "effects/workshop/1/blurprecise/effect.json", input: source,
            output: output, nodeIndices: [0, 1]
        )
        return Graph(
            layerID: layerID,
            effects: extraEffect ? [effect, effect] : [effect],
            renderTargets: [
                .init(
                    texture: rt, extent: .init(kind: .input, first: nil, second: nil),
                    format: "rgba_backbuffer", declaredUnique: unique, clear: nil,
                    uvs: nil, conditions: nil
                ),
            ],
            nodes: nodes,
            finalOutput: output,
            blockers: blockers
        )
    }

    static func standardBlurInstanceEffect(
        layerID: Int = 530,
        gaussianCombos: [String: Int] = [:],
        combineCombos: [String: Int] = [:]
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let scale = SceneDocument.ShaderValue(
            valueKind: "binding", userBinding: "newproperty", components: [0.6]
        )
        return .init(
            id: "\(layerID)#effect#0",
            visible: true,
            passes: [
                .init(
                    passIndex: 0, textureSlots: [], userTextureInputs: [], combos: [:],
                    constantShaderValues: [:]
                ),
                .init(
                    passIndex: 1, textureSlots: [], userTextureInputs: [],
                    combos: gaussianCombos, constantShaderValues: ["scale": scale]
                ),
                .init(
                    passIndex: 2, textureSlots: [], userTextureInputs: [], combos: [:],
                    constantShaderValues: ["scale": scale]
                ),
                .init(
                    passIndex: 3, textureSlots: [], userTextureInputs: [],
                    combos: combineCombos,
                    constantShaderValues: [
                        "compositecolor": .init(components: [1, 1, 1]),
                    ]
                ),
            ]
        )
    }

    static func standardBlurMaterials(
        gaussianShader: String = "effects/blur_gaussian",
        blending: String = "normal",
        combineCombos: [String: Int] = [:]
    ) -> [SceneRenderDescriptor.MaterialPassDescriptor] {
        func material(
            _ name: String,
            shader: String,
            combos: [String: Int] = [:]
        ) -> SceneRenderDescriptor.MaterialPassDescriptor {
            .init(
                id: "materials/effects/\(name).json#0",
                materialPath: "materials/effects/\(name).json",
                shaderPath: shader, textureSlots: [], userTextureInputs: [], combos: combos,
                constantShaderValues: [:], blending: blending, depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull"
            )
        }
        return [
            material("blur_downsample4", shader: "effects/blur_downsample4"),
            material("blur_gaussian_x", shader: gaussianShader),
            material(
                "blur_gaussian_y", shader: gaussianShader,
                combos: ["VERTICAL": 1]
            ),
            material(
                "blur_combine", shader: "effects/blur_combine", combos: combineCombos
            ),
        ]
    }

    static func standardBlurDescriptor(
        effect: SceneRenderDescriptor.EffectDescriptor = standardBlurInstanceEffect(),
        materials: [SceneRenderDescriptor.MaterialPassDescriptor] = standardBlurMaterials()
    ) -> SceneRenderDescriptor {
        .init(
            layers: [
                .init(
                    id: 530, parentID: nil, visible: true, contentKind: "composition",
                    effects: [effect]
                ),
            ],
            materialPasses: materials
        )
    }

    static func standardBlurGraph(
        wrongExtent: Bool = false,
        wrongBinding: Bool = false,
        extraMixedEffect: Bool = false
    ) -> Graph {
        let layerID = 530
        let key = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "530#effect#0"
        )
        let source = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let quarterA = texture(
            .framebuffer, layerID: layerID, effect: key,
            name: "_rt_QuarterCompoBuffer1"
        )
        let quarterB = texture(
            .framebuffer, layerID: layerID, effect: key,
            name: "_rt_QuarterCompoBuffer2"
        )
        let materials = [
            "materials/effects/blur_downsample4.json",
            "materials/effects/blur_gaussian_x.json",
            "materials/effects/blur_gaussian_y.json",
            "materials/effects/blur_combine.json",
        ]
        let bindings: [[Graph.Binding]] = [
            [
                .init(
                    slot: wrongBinding ? 1 : 0, authoredName: "previous",
                    texture: source, conditions: nil
                ),
            ],
            [.init(slot: 0, authoredName: "_rt_QuarterCompoBuffer1", texture: quarterA, conditions: nil)],
            [.init(slot: 0, authoredName: "_rt_QuarterCompoBuffer2", texture: quarterB, conditions: nil)],
            [
                .init(slot: 0, authoredName: "_rt_QuarterCompoBuffer1", texture: quarterA, conditions: nil),
                .init(slot: 2, authoredName: "previous", texture: source, conditions: nil),
            ],
        ]
        let targets: [Graph.TextureIdentity] = [quarterA, quarterB, quarterA, output]
        let nodes = materials.indices.map { ordinal in
            Graph.Node(
                nodeIndex: ordinal, effect: key, definitionPassIndex: ordinal,
                materialOrdinal: ordinal, instancePassIndex: ordinal, kind: .material,
                materialPath: materials[ordinal],
                materialPassID: "\(materials[ordinal])#0", target: targets[ordinal],
                bindings: bindings[ordinal], commandSource: nil, commandTarget: nil,
                compose: nil, conditions: nil
            )
        }
        let effect = Graph.Effect(
            key: key, definitionPath: "effects/blur/effect.json", input: source,
            output: output, nodeIndices: [0, 1, 2, 3]
        )
        let mixedKey = Graph.EffectKey(
            layerID: layerID, effectIndex: 1, descriptorID: "530#effect#1"
        )
        let mixed = Graph.Effect(
            key: mixedKey, definitionPath: "effects/water/effect.json", input: output,
            output: texture(.effectOutput, layerID: layerID, effect: mixedKey),
            nodeIndices: []
        )
        return Graph(
            layerID: layerID,
            effects: extraMixedEffect ? [effect, mixed] : [effect],
            renderTargets: [quarterA, quarterB].enumerated().map { index, texture in
                .init(
                    texture: texture,
                    extent: .init(
                        kind: wrongExtent && index == 0 ? .input : .scale,
                        first: wrongExtent && index == 0 ? nil : 4,
                        second: nil
                    ),
                    format: "rgba_backbuffer", declaredUnique: false, clear: nil,
                    uvs: nil, conditions: nil
                )
            },
            nodes: nodes, finalOutput: output, blockers: []
        )
    }

    static func resolverPrecedence() -> [[String]] {
        let key = Graph.EffectKey(layerID: 99, effectIndex: 0, descriptorID: "resolver")
        let graphTexture = texture(.layerSource, layerID: 99)
        let node = Graph.Node(
            nodeIndex: 0, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
            instancePassIndex: 0, kind: .material, materialPath: "materials/resolver.json",
            materialPassID: "materials/resolver.json#0", target: graphTexture,
            bindings: [.init(slot: 1, authoredName: "previous", texture: graphTexture, conditions: nil)],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
        )
        let effect = Graph.Effect(
            key: key, definitionPath: "effect.json", input: graphTexture,
            output: graphTexture, nodeIndices: [0]
        )
        let graph = Graph(
            layerID: 99, effects: [effect], renderTargets: [], nodes: [node],
            finalOutput: graphTexture, blockers: []
        )
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            textureSlots: [nil, "instance-one", "instance-two"],
            userTextureInputs: [nil, nil, .init(name: "user-two")],
            combos: ["INSTANCE": 2],
            constantShaderValues: ["value": .init(components: [2])]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                .init(
                    id: 99, parentID: nil, visible: true, contentKind: "image",
                    effects: [.init(id: "resolver", visible: true, passes: [pass])]
                ),
            ],
            materialPasses: [
                .init(
                    id: "materials/resolver.json#0", materialPath: "materials/resolver.json",
                    shaderPath: "effects/test",
                    textureSlots: ["material-zero", "material-one", "material-two"],
                    userTextureInputs: [nil, .init(name: "material-user-one")],
                    combos: ["MATERIAL": 1],
                    constantShaderValues: ["value": .init(components: [1])],
                    blending: "normal", depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull"
                ),
            ]
        )
        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node, graph: graph, descriptor: descriptor
        )
        return resolution.node!.textureSlots.map { slot in
            slot?.candidates.map(\.provenance.rawValue) ?? ["hole"]
        }
    }

    static func main() throws {
        let layers: [SceneRenderDescriptor.Layer] = [
            .init(id: 10, parentID: nil, visible: true, contentKind: "text", effects: [instanceEffect(layerID: 10, scale: 1.28)]),
            .init(id: 20, parentID: nil, visible: false, contentKind: "text", effects: [instanceEffect(layerID: 20, scale: 0.43)]),
            .init(id: 21, parentID: 20, visible: true, contentKind: "text", effects: [instanceEffect(layerID: 21, scale: 1.33)]),
            .init(id: 30, parentID: nil, visible: true, contentKind: "text", effects: [instanceEffect(layerID: 30, scale: 0.43)]),
        ]
        let descriptor = SceneRenderDescriptor(layers: layers, materialPasses: materials())
        let catalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: descriptor,
            authoredPlans: [
                graph(layerID: 10), graph(layerID: 20), graph(layerID: 21),
                graph(layerID: 30, extraEffect: true),
            ]
        )
        let visiblePlan = catalog.plansByLayerID[10]!
        let preciseBlur = visiblePlan.gaussianBlur!
        let preciseRenderTargetPlan: SceneGraphRenderTargetPlan = {
            switch SceneGraphRenderTargetPlan.make(
                executionPlan: visiblePlan,
                graph: visiblePlan.renderGraph,
                inputWidth: 1279,
                inputHeight: 719
            ) {
            case .success(let plan): return plan
            case .failure(let failure):
                fatalError("precise render target plan failed: \(failure.rawValue)")
            }
        }()
        let preciseBackendMatched: Bool = {
            if case .preciseGaussian = visiblePlan.backend { return true }
            return false
        }()
        let badStateDescriptor = SceneRenderDescriptor(layers: layers, materialPasses: materials(blending: "additive"))
        let badShaderDescriptor = SceneRenderDescriptor(layers: layers, materialPasses: materials(shader: "effects/unknown"))
        let duplicateComboDescriptor = SceneRenderDescriptor(
            layers: layers,
            materialPasses: materials(verticalCombos: ["VERTICAL": 1, "vertical": 1, "ENABLEMASK": 1])
        )
        let dynamicScaleDescriptor = descriptorForLayer10(
            effect: instanceEffect(layerID: 10, scale: 1.28, userBinding: "user.scale")
        )
        let outOfRangeScaleDescriptor = descriptorForLayer10(
            effect: instanceEffect(layerID: 10, scale: -1)
        )
        let duplicateScaleDescriptor = descriptorForLayer10(
            effect: instanceEffect(layerID: 10, scale: 1.28, duplicateScaleKey: true)
        )
        let threeComponentScaleDescriptor = descriptorForLayer10(
            effect: instanceEffect(layerID: 10, scaleComponents: [1.28, 1.28, 1.28])
        )
        let missingMaterialDescriptor = SceneRenderDescriptor(layers: layers, materialPasses: [])
        let blocker = Graph.Blocker(
            effect: Graph.EffectKey(layerID: 10, effectIndex: 0, descriptorID: "10#effect#1"),
            definitionPassIndex: nil, reason: .unsupportedCondition, detail: "fixture"
        )
        let standardDescriptor = standardBlurDescriptor()
        let standardGraph = standardBlurGraph()
        let standardPlan = SceneAuthoredStandardBlurPlanner.plan(
            graph: standardGraph, descriptor: standardDescriptor
        )!
        let standardBlur = standardPlan.standardBlur!
        let standardRenderTargetPlan: SceneGraphRenderTargetPlan = {
            switch SceneGraphRenderTargetPlan.make(
                executionPlan: standardPlan,
                graph: standardPlan.renderGraph,
                inputWidth: 1920,
                inputHeight: 1080
            ) {
            case .success(let plan): return plan
            case .failure(let failure):
                fatalError("standard render target plan failed: \(failure.rawValue)")
            }
        }()
        let standardBackendMatched: Bool = {
            if case .standardBlur = standardPlan.backend { return true }
            return false
        }()
        let standardCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: standardDescriptor, authoredPlans: [standardGraph]
        )
        let standardBadStateDescriptor = standardBlurDescriptor(
            materials: standardBlurMaterials(blending: "additive")
        )
        let standardBadShaderDescriptor = standardBlurDescriptor(
            materials: standardBlurMaterials(gaussianShader: "effects/unknown")
        )
        let standardKernelDescriptor = standardBlurDescriptor(
            effect: standardBlurInstanceEffect(gaussianCombos: ["KERNEL": 2])
        )
        let standardCompositeDescriptor = standardBlurDescriptor(
            effect: standardBlurInstanceEffect(combineCombos: ["COMPOSITE": 2])
        )
        func standardRejected(
            graph: Graph = standardGraph,
            descriptor: SceneRenderDescriptor = standardDescriptor
        ) -> Bool {
            SceneAuthoredStandardBlurPlanner.plan(graph: graph, descriptor: descriptor) == nil
        }
        func standardLegacyBlocked(
            graph: Graph,
            descriptor: SceneRenderDescriptor = standardDescriptor
        ) -> [Int] {
            SceneAuthoredEffectExecutionCatalog(
                descriptor: descriptor, authoredPlans: [graph]
            ).legacyGaussianBlurBlockedLayerIDs.sorted()
        }
        let result: [String: Any] = [
            "planned": catalog.plansByLayerID.keys.sorted(),
            "hidden": catalog.hiddenEligibleLayerIDs,
            "legacyBlurBlocked": catalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
            "scale": [preciseBlur.horizontalStep, preciseBlur.verticalStep],
            "nodes": visiblePlan.materialNodeCount,
            "targets": visiblePlan.logicalRenderTargetCount,
            "preciseGraphTargetCount": preciseRenderTargetPlan.logicalTargets.count,
            "preciseGraphTargetExtents": preciseRenderTargetPlan.logicalTargets.map {
                [$0.extent.width, $0.extent.height]
            },
            "preciseGraphIdentityMatched":
                preciseRenderTargetPlan.layerID == visiblePlan.renderGraph.layerID
                && preciseRenderTargetPlan.input == visiblePlan.renderGraph.effects[0].input
                && preciseRenderTargetPlan.output == visiblePlan.renderGraph.finalOutput
                && preciseRenderTargetPlan.logicalTargets.map(\.identity)
                    == visiblePlan.renderGraph.renderTargets.map(\.texture),
            "preciseBackendMatched": preciseBackendMatched
                && visiblePlan.standardBlur == nil
                && visiblePlan.requiresExactInputExtent,
            "precedence": resolverPrecedence(),
            "extraEffectRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10, extraEffect: true), descriptor: descriptor) == nil,
            "blockerRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10, blockers: [blocker]), descriptor: descriptor) == nil,
            "uniqueRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10, unique: true), descriptor: descriptor) == nil,
            "bindingRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10, maskCombo: true), descriptor: descriptor) == nil,
            "stateRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: badStateDescriptor) == nil,
            "shaderRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: badShaderDescriptor) == nil,
            "duplicateComboRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: duplicateComboDescriptor) == nil,
            "dynamicScaleRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: dynamicScaleDescriptor) == nil,
            "outOfRangeScaleRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: outOfRangeScaleDescriptor) == nil,
            "duplicateScaleRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: duplicateScaleDescriptor) == nil,
            "threeComponentScaleRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: threeComponentScaleDescriptor) == nil,
            "badShaderLegacyBlocked": SceneAuthoredEffectExecutionCatalog(descriptor: badShaderDescriptor, authoredPlans: [graph(layerID: 10)]).legacyGaussianBlurBlockedLayerIDs.sorted(),
            "missingMaterialLegacyBlocked": SceneAuthoredEffectExecutionCatalog(descriptor: missingMaterialDescriptor, authoredPlans: [graph(layerID: 10)]).legacyGaussianBlurBlockedLayerIDs.sorted(),
            "standardPlanned": standardCatalog.plansByLayerID.keys.sorted(),
            "standardScale": [standardBlur.horizontalStep, standardBlur.verticalStep],
            "standardRTScale": standardBlur.renderTargetScale,
            "standardNodes": standardPlan.materialNodeCount,
            "standardTargets": standardPlan.logicalRenderTargetCount,
            "standardGraphTargetCount": standardRenderTargetPlan.logicalTargets.count,
            "standardGraphTargetExtents": standardRenderTargetPlan.logicalTargets.map {
                [$0.extent.width, $0.extent.height]
            },
            "standardGraphIdentityMatched":
                standardRenderTargetPlan.layerID == standardPlan.renderGraph.layerID
                && standardRenderTargetPlan.input == standardPlan.renderGraph.effects[0].input
                && standardRenderTargetPlan.output == standardPlan.renderGraph.finalOutput
                && standardRenderTargetPlan.logicalTargets.map(\.identity)
                    == standardPlan.renderGraph.renderTargets.map(\.texture),
            "standardBackendMatched": standardBackendMatched
                && standardPlan.gaussianBlur == nil
                && !standardPlan.requiresExactInputExtent,
            "standardLegacyBlocked": standardCatalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
            "standardWrongExtentRejected": standardRejected(graph: standardBlurGraph(wrongExtent: true)),
            "standardWrongBindingRejected": standardRejected(graph: standardBlurGraph(wrongBinding: true)),
            "standardBadShaderRejected": standardRejected(descriptor: standardBadShaderDescriptor),
            "standardBadStateRejected": standardRejected(descriptor: standardBadStateDescriptor),
            "standardKernelRejected": standardRejected(descriptor: standardKernelDescriptor),
            "standardCompositeRejected": standardRejected(descriptor: standardCompositeDescriptor),
            "standardMixedEffectRejected": standardRejected(graph: standardBlurGraph(extraMixedEffect: true)),
            "standardWrongExtentLegacyBlocked": standardLegacyBlocked(graph: standardBlurGraph(wrongExtent: true)),
            "standardWrongBindingLegacyBlocked": standardLegacyBlocked(graph: standardBlurGraph(wrongBinding: true)),
            "standardBadShaderLegacyBlocked": standardLegacyBlocked(graph: standardGraph, descriptor: standardBadShaderDescriptor),
            "standardBadStateLegacyBlocked": standardLegacyBlocked(graph: standardGraph, descriptor: standardBadStateDescriptor),
            "standardKernelLegacyBlocked": standardLegacyBlocked(graph: standardGraph, descriptor: standardKernelDescriptor),
            "standardCompositeLegacyBlocked": standardLegacyBlocked(graph: standardGraph, descriptor: standardCompositeDescriptor),
            "standardMixedEffectLegacyBlocked": standardLegacyBlocked(graph: standardBlurGraph(extraMixedEffect: true)),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAuthoredEffectExecutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-authored-execution-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-authored-execution"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
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

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_only_effectively_visible_complete_graph_is_planned(self) -> None:
        self.assertEqual(self.result["planned"], [10])
        self.assertEqual(self.result["hidden"], [20, 21])
        self.assertEqual(self.result["legacyBlurBlocked"], [30])
        self.assertEqual(self.result["nodes"], 2)
        self.assertEqual(self.result["targets"], 1)
        self.assertAlmostEqual(self.result["scale"][0], 1.28, places=5)
        self.assertAlmostEqual(self.result["scale"][1], 1.28, places=5)
        self.assertEqual(self.result["preciseGraphTargetCount"], 1)
        self.assertEqual(self.result["preciseGraphTargetExtents"], [[1279, 719]])
        self.assertTrue(self.result["preciseGraphIdentityMatched"])
        self.assertTrue(self.result["preciseBackendMatched"])

    def test_default_standard_blur_graph_is_planned(self) -> None:
        self.assertEqual(self.result["standardPlanned"], [530])
        self.assertEqual(self.result["standardLegacyBlocked"], [])
        self.assertEqual(self.result["standardNodes"], 4)
        self.assertEqual(self.result["standardTargets"], 2)
        self.assertEqual(self.result["standardRTScale"], 4)
        self.assertAlmostEqual(self.result["standardScale"][0], 0.6, places=5)
        self.assertAlmostEqual(self.result["standardScale"][1], 0.6, places=5)
        self.assertEqual(self.result["standardGraphTargetCount"], 2)
        self.assertEqual(
            self.result["standardGraphTargetExtents"],
            [[480, 270], [480, 270]],
        )
        self.assertTrue(self.result["standardGraphIdentityMatched"])
        self.assertTrue(self.result["standardBackendMatched"])

    def test_texture_precedence_preserves_slots(self) -> None:
        self.assertEqual(
            self.result["precedence"],
            [
                ["material"],
                ["material", "userTexture", "instance", "explicitBinding"],
                ["material", "instance", "userTexture"],
                ["hole"], ["hole"], ["hole"], ["hole"], ["hole"],
            ],
        )

    def test_unsupported_graph_shapes_fail_closed(self) -> None:
        for key in (
            "extraEffectRejected",
            "blockerRejected",
            "uniqueRejected",
            "bindingRejected",
            "stateRejected",
            "shaderRejected",
            "duplicateComboRejected",
            "dynamicScaleRejected",
            "outOfRangeScaleRejected",
            "duplicateScaleRejected",
            "threeComponentScaleRejected",
        ):
            self.assertTrue(self.result[key], key)
        self.assertEqual(self.result["badShaderLegacyBlocked"], [10])
        self.assertEqual(self.result["missingMaterialLegacyBlocked"], [10])

    def test_unsupported_standard_blur_shapes_fail_closed(self) -> None:
        rejection_keys = (
            "standardWrongExtentRejected",
            "standardWrongBindingRejected",
            "standardBadShaderRejected",
            "standardBadStateRejected",
            "standardKernelRejected",
            "standardCompositeRejected",
            "standardMixedEffectRejected",
        )
        for key in rejection_keys:
            self.assertTrue(self.result[key], key)
        blocking_keys = (
            "standardWrongExtentLegacyBlocked",
            "standardWrongBindingLegacyBlocked",
            "standardBadShaderLegacyBlocked",
            "standardBadStateLegacyBlocked",
            "standardKernelLegacyBlocked",
            "standardCompositeLegacyBlocked",
            "standardMixedEffectLegacyBlocked",
        )
        for key in blocking_keys:
            self.assertEqual(self.result[key], [530], key)


if __name__ == "__main__":
    unittest.main()
