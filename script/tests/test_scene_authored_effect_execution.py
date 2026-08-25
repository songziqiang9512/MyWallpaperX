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
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageGraph.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectProgramCompiler+DedicatedStages.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageCompiler.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectAdmissionCatalog.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectAdmissionCatalog+ResolvedMaterial.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageProgram.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageAdmission.swift",
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageExecutionPlan+Backend.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
]
PROGRAM_COMPILER_SOURCE = (
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectProgramCompiler+DedicatedStages.swift"
)
CHAIN_BACKEND_SOURCE = (
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageExecutionPlan+Backend.swift"
)
CHAIN_RENDERER_SOURCE = (
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer.swift"
)
CHAIN_SPECIALIZED_STAGE_SOURCE = (
    SOURCE_ROOT
    / "RenderGraph/EffectExecution/SceneEffectStageRenderer+SpecializedStage.swift"
)
CHAIN_TOPOLOGY_SOURCE = (
    SOURCE_ROOT
    / "RenderGraph/EffectExecution/SceneEffectStageRenderer+Topology.swift"
)
COMPOSITOR_SOURCE = SOURCE_ROOT / "Rendering/SceneImageLayerCompositor.swift"
DRAW_REQUEST_SOURCE = SOURCE_ROOT / "Rendering/SceneImageLayerDrawRequest.swift"
EFFECT_TEXTURE_LOADER_SOURCE = (
    SOURCE_ROOT / "Resources/SceneLayerEffectTextureLoader.swift"
)
HARNESS = r'''
import Foundation

struct SceneEffectExactRuntimeSubject: Hashable {
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let family: String
}

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

struct SceneXRayExecutionPlan {
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

enum SceneAuthoredXRayPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneXRayExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/xray/effect.json" ? SceneXRayExecutionPlan() : nil
    }
}

struct ScenePulseExecutionPlan {
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

enum SceneAuthoredPulsePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> ScenePulseExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/pulse/effect.json" ? ScenePulseExecutionPlan() : nil
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
        let file: String
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
        var userShaderValues: [String: String] { [:] }
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String? = nil
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

nonisolated protocol HarnessDedicatedPlanner {
    associatedtype DedicatedPlan

    static var compilerBackend: SceneEffectStageCompilerBackend { get }

    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> DedicatedPlan?
}

extension HarnessDedicatedPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<DedicatedPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: compilerBackend,
            candidate: { false },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    shaderContracts: input.shaderContracts,
                    inputRole: input.inputRole
                )
            }
        )
    }
}

extension SceneAuthoredStandardBlurPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneEffectStageExecutionPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: .standardBlur,
            candidate: { false },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    inputRole: input.inputRole
                )
            }
        )
    }
}

extension SceneAuthoredXRayPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneXRayExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .xRay }
}
extension SceneAuthoredPulsePlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = ScenePulseExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .pulse }
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
        duplicateScaleKey: Bool = false,
        fullFrameCompose: Bool = false,
        kernel: Int = 0,
        verticalKernel: Int? = nil,
        horizontalExtraCombos: [String: Int] = [:],
        verticalExtraCombos: [String: Int] = [:]
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
        var horizontalCombos = kernel == 0 ? [:] : ["KERNEL": kernel]
        horizontalCombos.merge(horizontalExtraCombos) { _, replacement in replacement }
        var verticalCombos = fullFrameCompose
            ? ["VERTICAL": 1]
            : ["VERTICAL": 1, "ENABLEMASK": 1]
        let resolvedVerticalKernel = verticalKernel ?? kernel
        if resolvedVerticalKernel != 0 {
            verticalCombos["KERNEL"] = resolvedVerticalKernel
        }
        verticalCombos.merge(verticalExtraCombos) { _, replacement in replacement }
        return .init(
            id: "\(layerID)#effect#1",
            file: "effects/workshop/blurprecise/effect.json",
            visible: true,
            passes: [
                .init(
                    passIndex: 0, textureSlots: [], userTextureInputs: [],
                    combos: horizontalCombos,
                    constantShaderValues: scaleValues
                ),
                .init(
                    passIndex: 1, textureSlots: [], userTextureInputs: [],
                    combos: verticalCombos,
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
        maskCombo: Bool = false,
        fullFrameCompose: Bool = false,
        firstCompose: SceneJSONValue? = .bool(true),
        terminalCompose: SceneJSONValue? = nil,
        composeTargetsFramebuffer: Bool = false,
        fullFrameBinding: Bool = false
    ) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "\(layerID)#effect#1"
        )
        let source = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let rt = texture(.framebuffer, layerID: layerID, effect: key, name: "full")
        let verticalBindings: [Graph.Binding]
        if fullFrameCompose {
            verticalBindings = composeTargetsFramebuffer ? [
                .init(slot: 0, authoredName: "full", texture: rt, conditions: nil),
            ] : []
        } else {
            verticalBindings = [
                .init(slot: 0, authoredName: "full", texture: rt, conditions: nil),
                .init(
                    slot: maskCombo ? 2 : 1, authoredName: "previous",
                    texture: source, conditions: nil
                ),
            ]
        }
        let nodes = [
            Graph.Node(
                nodeIndex: 0, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
                instancePassIndex: 0, kind: .material, materialPath: "materials/x.json",
                materialPassID: "materials/x.json#0",
                target: fullFrameCompose && !composeTargetsFramebuffer ? output : rt,
                bindings: fullFrameCompose && fullFrameBinding
                    ? [.init(slot: 0, authoredName: "previous", texture: source, conditions: nil)]
                    : [],
                commandSource: nil, commandTarget: nil,
                compose: fullFrameCompose ? firstCompose : nil, conditions: nil
            ),
            Graph.Node(
                nodeIndex: 1, effect: key, definitionPassIndex: 1, materialOrdinal: 1,
                instancePassIndex: 1, kind: .material, materialPath: "materials/y.json",
                materialPassID: "materials/y.json#0", target: output,
                bindings: verticalBindings, commandSource: nil, commandTarget: nil,
                compose: fullFrameCompose ? terminalCompose : nil, conditions: nil
            ),
        ]
        let effect = Graph.Effect(
            key: key, definitionPath: "effects/workshop/1/blurprecise/effect.json", input: source,
            output: output, nodeIndices: [0, 1]
        )
        return Graph(
            layerID: layerID,
            effects: extraEffect ? [effect, effect] : [effect],
            renderTargets: fullFrameCompose && !composeTargetsFramebuffer ? [] : [
                .init(
                    texture: rt,
                    extent: .init(kind: .input, first: nil, second: nil),
                    format: "rgba_backbuffer", declaredUnique: unique, clear: nil,
                    uvs: nil, conditions: nil
                ),
            ],
            nodes: nodes,
            finalOutput: output,
            blockers: blockers
        )
    }

    static func interleavedGraph(
        commandKind: Graph.NodeKind,
        commandAfterVertical: Bool = false,
        commandCompose: SceneJSONValue? = nil,
        sourceUnique: Bool? = nil,
        targetUnique: Bool? = nil
    ) -> Graph {
        let layerID = 10
        let key = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "\(layerID)#effect#1"
        )
        let source = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let first = texture(.framebuffer, layerID: layerID, effect: key, name: "first")
        let second = texture(.framebuffer, layerID: layerID, effect: key, name: "second")
        let commandIndex = commandAfterVertical ? 2 : 1
        let verticalIndex = commandAfterVertical ? 1 : 2
        let horizontal = Graph.Node(
            nodeIndex: 0, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
            instancePassIndex: 0, kind: .material, materialPath: "materials/x.json",
            materialPassID: "materials/x.json#0", target: first, bindings: [],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
        )
        let command = Graph.Node(
            nodeIndex: commandIndex, effect: key, definitionPassIndex: 1,
            materialOrdinal: nil, instancePassIndex: nil, kind: commandKind,
            materialPath: nil, materialPassID: nil, target: nil, bindings: [],
            commandSource: first, commandTarget: second, compose: commandCompose,
            conditions: nil
        )
        let vertical = Graph.Node(
            nodeIndex: verticalIndex, effect: key, definitionPassIndex: 2,
            materialOrdinal: 1, instancePassIndex: 1, kind: .material,
            materialPath: "materials/y.json", materialPassID: "materials/y.json#0",
            target: output,
            bindings: [
                .init(slot: 0, authoredName: "second", texture: second, conditions: nil),
                .init(slot: 1, authoredName: "previous", texture: source, conditions: nil),
            ],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
        )
        let nodes = commandAfterVertical
            ? [horizontal, vertical, command]
            : [horizontal, command, vertical]
        return Graph(
            layerID: layerID,
            effects: [
                .init(
                    key: key,
                    definitionPath: "effects/workshop/1/blurprecise/effect.json",
                    input: source,
                    output: output,
                    nodeIndices: nodes.map(\.nodeIndex)
                ),
            ],
            renderTargets: [
                .init(
                    texture: first, extent: .init(kind: .input, first: nil, second: nil),
                    format: "rgba_backbuffer",
                    declaredUnique: sourceUnique ?? (commandKind == .swap),
                    clear: nil,
                    uvs: nil, conditions: nil
                ),
                .init(
                    texture: second, extent: .init(kind: .input, first: nil, second: nil),
                    format: "rgba_backbuffer",
                    declaredUnique: targetUnique ?? (commandKind == .swap),
                    clear: nil, uvs: nil, conditions: nil
                ),
            ],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func standardBlurInstanceEffect(
        layerID: Int = 530,
        gaussianCombos: [String: Int] = [:],
        combineCombos: [String: Int] = [:],
        maskPath: String? = nil
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let scale = SceneDocument.ShaderValue(
            valueKind: "binding", userBinding: "newproperty", components: [0.6]
        )
        return .init(
            id: "\(layerID)#effect#0",
            file: "effects/blur/effect.json",
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
                    passIndex: 3, textureSlots: [nil, maskPath], userTextureInputs: [],
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
                    effects: [.init(
                        id: "resolver",
                        file: "effects/resolver/effect.json",
                        visible: true,
                        passes: [pass]
                    )]
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

    static func materialOnlyResolverEvidence() -> [String: Any] {
        let layerID = 99
        let key = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "material-only"
        )
        let source = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let node = Graph.Node(
            nodeIndex: 0, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
            instancePassIndex: nil, kind: .material,
            materialPath: "materials/material-only.json",
            materialPassID: "materials/material-only.json#0", target: output,
            bindings: [
                .init(
                    slot: 1, authoredName: "previous", texture: source,
                    conditions: nil
                ),
            ],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
        )
        let graph = Graph(
            layerID: layerID,
            effects: [
                .init(
                    key: key, definitionPath: "effects/material-only/effect.json",
                    input: source, output: output, nodeIndices: [0]
                ),
            ],
            renderTargets: [], nodes: [node], finalOutput: output, blockers: []
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "materials/material-only.json#0",
            materialPath: "materials/material-only.json",
            shaderPath: "effects/material-only",
            textureSlots: ["textures/material-zero", nil, "textures/material-two"],
            userTextureInputs: [], combos: ["STATIC_MODE": 7],
            constantShaderValues: [
                "gain": .init(components: [0.25, 0.75]),
            ],
            blending: "normal", depthTest: "disabled", depthWrite: "disabled",
            cullMode: "nocull"
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                .init(
                    id: layerID, parentID: nil, visible: true,
                    contentKind: "image",
                    effects: [
                        .init(
                            id: key.descriptorID,
                            file: "effects/material-only/effect.json",
                            visible: true, passes: []
                        ),
                    ]
                ),
            ],
            materialPasses: [material]
        )
        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node, graph: graph, descriptor: descriptor
        )

        let dynamicDescriptor = SceneRenderDescriptor(
            layers: [
                .init(
                    id: layerID, parentID: nil, visible: true,
                    contentKind: "image",
                    effects: [
                        .init(
                            id: key.descriptorID,
                            file: "effects/material-only/effect.json",
                            visible: true,
                            passes: [
                                .init(
                                    passIndex: 0, textureSlots: [],
                                    userTextureInputs: [], combos: [:],
                                    constantShaderValues: [
                                        "gain": .init(
                                            userBinding: "user.gain", components: nil
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            materialPasses: [material]
        )
        let dynamicResolution = SceneAuthoredMaterialResolver.resolve(
            node: node, graph: graph, descriptor: dynamicDescriptor
        )

        guard let resolved = resolution.node else {
            return [
                "resolved": false,
                "issues": resolution.issues,
                "dynamicPassWithoutIdentityRejected": !dynamicResolution.isResolved,
            ]
        }
        let slot0Asset: String = {
            guard let slot = resolved.textureSlots[0],
                  case .asset(let path) = slot.source else { return "" }
            return path
        }()
        let slot1Binding: [String: Any] = {
            guard let slot = resolved.textureSlots[1],
                  case .graph(let identity) = slot.source else { return [:] }
            return [
                "provenance": slot.provenance.rawValue,
                "kind": identity.kind.rawValue,
                "layerID": identity.layerID,
            ]
        }()
        let slot2Asset: String = {
            guard let slot = resolved.textureSlots[2],
                  case .asset(let path) = slot.source else { return "" }
            return path
        }()
        return [
            "resolved": resolution.isResolved,
            "issues": resolution.issues,
            "shader": resolved.shaderPath,
            "slot0Asset": slot0Asset,
            "slot1Binding": slot1Binding,
            "slot2Asset": slot2Asset,
            "slotProvenance": resolved.textureSlots.prefix(3).map {
                $0?.provenance.rawValue ?? "hole"
            },
            "staticMode": resolved.combos["STATIC_MODE"] ?? -1,
            "gain": resolved.constants["gain"]?.components ?? [],
            "dynamicPassWithoutIdentityRejected":
                dynamicResolution.node == nil
                && dynamicResolution.issues
                    == ["Effect instance pass does not match the graph ordinal."],
        ]
    }

    static func orderedGraph(
        layerID: Int,
        stageNames: [String]
    ) -> (graph: Graph, descriptor: SceneRenderDescriptor) {
        var priorOutput = texture(.layerSource, layerID: layerID)
        var effects: [Graph.Effect] = []
        var nodes: [Graph.Node] = []
        var descriptors: [SceneRenderDescriptor.EffectDescriptor] = []
        for (effectIndex, stageName) in stageNames.enumerated() {
            let key = Graph.EffectKey(
                layerID: layerID,
                effectIndex: effectIndex,
                descriptorID: "\(layerID)#effect#\(effectIndex)"
            )
            let output = texture(.effectOutput, layerID: layerID, effect: key)
            let definitionPath = "effects/\(stageName.lowercased())/effect.json"
            effects.append(.init(
                key: key,
                definitionPath: definitionPath,
                input: priorOutput,
                output: output,
                nodeIndices: [effectIndex]
            ))
            nodes.append(.init(
                nodeIndex: effectIndex,
                effect: key,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: .material,
                materialPath: "materials/\(stageName.lowercased()).json",
                materialPassID: "materials/\(stageName.lowercased()).json#0",
                target: output,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            ))
            descriptors.append(.init(
                id: key.descriptorID,
                file: definitionPath,
                visible: true,
                passes: []
            ))
            priorOutput = output
        }
        return (
            Graph(
                layerID: layerID,
                effects: effects,
                renderTargets: [],
                nodes: nodes,
                finalOutput: priorOutput,
                blockers: []
            ),
            SceneRenderDescriptor(
                layers: [
                    .init(
                        id: layerID,
                        parentID: nil,
                        visible: true,
                        contentKind: "image",
                        effects: descriptors
                    ),
                ],
                materialPasses: []
            )
        )
    }

    static func hiddenCapabilityAdmissionEvidence() -> [String: Any] {
        let fixture = orderedGraph(
            layerID: 940,
            stageNames: ["scroll", "transform"]
        )
        let hiddenDescriptor = SceneRenderDescriptor(
            layers: fixture.descriptor.layers.map { layer in
                .init(
                    id: layer.id,
                    parentID: layer.parentID,
                    visible: false,
                    contentKind: layer.contentKind,
                    effects: layer.effects
                )
            },
            materialPasses: fixture.descriptor.materialPasses
        )
        let subjects = fixture.graph.effects.map {
            SceneEffectExactRuntimeSubject(
                key: $0.key,
                family: "resolved-material"
            )
        }
        let owned = SceneEffectAdmissionCatalog(
            descriptor: hiddenDescriptor,
            authoredPlans: [fixture.graph],
            resolvedMaterialSubjects: subjects
        )
        let unowned = SceneEffectAdmissionCatalog(
            descriptor: hiddenDescriptor,
            authoredPlans: [fixture.graph]
        )
        let incomplete = SceneEffectAdmissionCatalog(
            descriptor: hiddenDescriptor,
            authoredPlans: [fixture.graph],
            resolvedMaterialSubjects: Array(subjects.prefix(1))
        )
        func values(
            _ catalog: SceneEffectAdmissionCatalog
        ) -> [[String]] {
            catalog.stageAdmissions.map {
                [$0.activity.rawValue, $0.admission.rawValue, $0.coverage.rawValue]
            }
        }
        return [
            "owned": values(owned),
            "unowned": values(unowned),
            "incomplete": values(incomplete),
            "ownedStageCount": owned.unifiedExecutionStageKeys.count,
            "unownedStageCount": unowned.unifiedExecutionStageKeys.count,
            "incompleteStageCount": incomplete.unifiedExecutionStageKeys.count,
        ]
    }

    static func stageEvidence(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> [[Any]] {
        SceneEffectProgramCompiler.compileDedicatedLeaves(
            graph: graph,
            descriptor: descriptor,
            shaderContracts: []
        ).map { program in
            let stage = program.executionPlan
            let effectIndex = stage.renderGraph.effects[0].key.effectIndex
            let backend: String
            switch stage.backend {
            case .standardBlur: backend = "standardBlur"
            case .xRay: backend = "xRay"
            case .pulse: backend = "pulse"
            }
            return [effectIndex, backend]
        }
    }

    static func main() throws {
        let standardDescriptor = standardBlurDescriptor()
        let standardGraph = standardBlurGraph()
        let standardPlan = SceneAuthoredStandardBlurPlanner.plan(
            graph: standardGraph, descriptor: standardDescriptor
        )!
        let standardBlur = standardPlan.standardBlur!
        let standardMaskedDescriptor = standardBlurDescriptor(
            effect: standardBlurInstanceEffect(maskPath: "masks/blur-mask")
        )
        let standardMaskedPlan = SceneAuthoredStandardBlurPlanner.plan(
            graph: standardGraph,
            descriptor: standardMaskedDescriptor
        )?.standardBlur
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
        let standardMaskWithoutTextureDescriptor = standardBlurDescriptor(
            effect: standardBlurInstanceEffect(combineCombos: ["MASK": 1])
        )
        let standardUnknownMaskComboDescriptor = standardBlurDescriptor(
            effect: standardBlurInstanceEffect(
                combineCombos: ["MASK": 2],
                maskPath: "masks/blur-mask"
            )
        )
        func standardRejected(
            graph: Graph = standardGraph,
            descriptor: SceneRenderDescriptor = standardDescriptor
        ) -> Bool {
            SceneAuthoredStandardBlurPlanner.plan(graph: graph, descriptor: descriptor) == nil
        }
        let result: [String: Any] = [
            "precedence": resolverPrecedence(),
            "materialOnly": materialOnlyResolverEvidence(),
            "hiddenCapabilityAdmission": hiddenCapabilityAdmissionEvidence(),
            "standardScale": [standardBlur.horizontalStep, standardBlur.verticalStep],
            "standardRTScale": standardBlur.renderTargetScale,
            "standardEffectDescriptorID": standardBlur.effectDescriptorID,
            "standardMaskPath": (standardBlur.maskTexturePath as Any?) ?? NSNull(),
            "standardMaskedPath": (standardMaskedPlan?.maskTexturePath as Any?)
                ?? NSNull(),
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
            "standardBackendMatched": standardBackendMatched,
            "standardSupportsUtilityCapture": standardPlan.supportsUtilityCapture,
            "standardWrongExtentRejected": standardRejected(graph: standardBlurGraph(wrongExtent: true)),
            "standardWrongBindingRejected": standardRejected(graph: standardBlurGraph(wrongBinding: true)),
            "standardBadShaderRejected": standardRejected(descriptor: standardBadShaderDescriptor),
            "standardBadStateRejected": standardRejected(descriptor: standardBadStateDescriptor),
            "standardKernelRejected": standardRejected(descriptor: standardKernelDescriptor),
            "standardCompositeRejected": standardRejected(descriptor: standardCompositeDescriptor),
            "standardMaskWithoutTextureRejected": standardRejected(
                descriptor: standardMaskWithoutTextureDescriptor
            ),
            "standardUnknownMaskComboRejected": standardRejected(
                descriptor: standardUnknownMaskComboDescriptor
            ),
            "standardMixedEffectRejected": standardRejected(graph: standardBlurGraph(extraMixedEffect: true)),
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

    def test_authored_material_backends_keep_typed_pair_contracts(self) -> None:
        backend = CHAIN_BACKEND_SOURCE.read_text(encoding="utf-8")
        leaf_start = backend.index("        var supportsUnifiedPairLeaf: Bool")
        logical_start = backend.index(
            "    nonisolated var supportsUnifiedLogicalTargetStage: Bool",
            leaf_start,
        )
        leaf_body = backend[leaf_start:logical_start]
        topology = CHAIN_TOPOLOGY_SOURCE.read_text(encoding="utf-8")

        self.assertNotIn(".waterFlow", backend)
        self.assertNotIn("yieldsToResolvedMaterialProgram", backend)
        self.assertNotIn(".spin", backend)

        self.assertNotIn(".workshopAudioBars", leaf_body)
        self.assertNotIn("case .waterFlow", topology)
        self.assertNotIn("waterFlowEffects", topology)
        self.assertNotIn("fisheyeZeroDistortion", leaf_body)
        self.assertNotIn("fisheye-pipeline-missing", topology)
        self.assertNotIn(".waterWaves", leaf_body)
        self.assertNotIn(".transform", leaf_body)
        self.assertNotIn("case .transform", topology)
        self.assertIn(".pulse", leaf_body)
        self.assertNotIn("proceduralNoise", leaf_body)
        self.assertIn(".xRay", leaf_body)
        self.assertIn("case .xRay(let plan):", topology)
        self.assertIn("SceneXRayRuntimePlanner.resolve(", topology)
        self.assertIn('return "x-ray-runtime-unsupported"', topology)

        x_ray = (SOURCE_ROOT / (
            "RenderGraph/EffectExecution/"
            "SceneEffectStageRenderer+XRay.swift"
        )).read_text(encoding="utf-8")
        self.assertIn("sourceTexture !== targets.inputTexture", x_ray)
        self.assertIn("copyIdentityOutput(", x_ray)
        self.assertIn('encoder.label = "Scene X-Ray identity output"', x_ray)

    def test_default_standard_blur_graph_is_planned(self) -> None:
        self.assertEqual(self.result["standardNodes"], 4)
        self.assertEqual(self.result["standardTargets"], 2)
        self.assertEqual(self.result["standardRTScale"], 4)
        self.assertEqual(self.result["standardEffectDescriptorID"], "530#effect#0")
        self.assertIsNone(self.result["standardMaskPath"])
        self.assertEqual(self.result["standardMaskedPath"], "masks/blur-mask")
        self.assertAlmostEqual(self.result["standardScale"][0], 0.6, places=5)
        self.assertAlmostEqual(self.result["standardScale"][1], 0.6, places=5)
        self.assertEqual(self.result["standardGraphTargetCount"], 2)
        self.assertEqual(
            self.result["standardGraphTargetExtents"],
            [[480, 270], [480, 270]],
        )
        self.assertTrue(self.result["standardGraphIdentityMatched"])
        self.assertTrue(self.result["standardBackendMatched"])
        self.assertTrue(self.result["standardSupportsUtilityCapture"])

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

    def test_material_only_descriptor_preserves_material_payload(self) -> None:
        evidence = self.result["materialOnly"]
        self.assertTrue(evidence["resolved"])
        self.assertEqual(evidence["issues"], [])
        self.assertEqual(evidence["shader"], "effects/material-only")
        self.assertEqual(evidence["slot0Asset"], "textures/material-zero")
        self.assertEqual(
            evidence["slot1Binding"],
            {
                "provenance": "explicitBinding",
                "kind": "layerSource",
                "layerID": 99,
            },
        )
        self.assertEqual(evidence["slot2Asset"], "textures/material-two")
        self.assertEqual(
            evidence["slotProvenance"],
            ["material", "explicitBinding", "material"],
        )
        self.assertEqual(evidence["staticMode"], 7)
        self.assertEqual(evidence["gain"], [0.25, 0.75])
        self.assertTrue(evidence["dynamicPassWithoutIdentityRejected"])

    def test_hidden_effect_stages_are_active_only_for_complete_capability_ownership(
        self,
    ) -> None:
        evidence = self.result["hiddenCapabilityAdmission"]
        self.assertEqual(
            evidence["owned"],
            [
                ["active", "admitted-generic", "complete"],
                ["active", "admitted-generic", "complete"],
            ],
        )
        for key in ("unowned", "incomplete"):
            self.assertEqual(
                evidence[key],
                [
                    ["layer-hidden", "inactive", "inactive"],
                    ["layer-hidden", "inactive", "inactive"],
                ],
            )
        self.assertEqual(evidence["ownedStageCount"], 2)
        self.assertEqual(evidence["unownedStageCount"], 0)
        self.assertEqual(evidence["incompleteStageCount"], 0)

    def test_unsupported_standard_blur_shapes_fail_closed(self) -> None:
        rejection_keys = (
            "standardWrongExtentRejected",
            "standardWrongBindingRejected",
            "standardBadShaderRejected",
            "standardBadStateRejected",
            "standardKernelRejected",
            "standardCompositeRejected",
            "standardMaskWithoutTextureRejected",
            "standardUnknownMaskComboRejected",
            "standardMixedEffectRejected",
        )
        for key in rejection_keys:
            self.assertTrue(self.result[key], key)

    def test_retired_dedicated_owner_families_are_absent(self) -> None:
        product_sources = "\n".join(
            path.read_text(encoding="utf-8")
            for path in SOURCE_ROOT.rglob("*.swift")
        )
        for marker in (
            "SceneEffectStageExecutionPlanner",
            "preciseGaussian",
            "SceneGaussianBlurPipeline",
            "SceneGaussianBlurPlan",
            "SceneAuthoredBlendPlanner",
            "SceneBlendExecutionPlan",
            "SceneBlendPipeline",
            "SceneBlendEffectTextureLoader",
            "SceneAuthoredTransformPlanner",
            "SceneTransformExecutionPlan",
            "SceneTransformShaderProfile",
            "renderTransform(",
        ):
            self.assertNotIn(marker, product_sources)

        self.assertFalse((SOURCE_ROOT / (
            "RenderGraph/EffectExecution/SceneEffectStageRenderer+Transform.swift"
        )).exists())

    def test_later_authored_stages_retain_required_resources(self) -> None:
        source = DRAW_REQUEST_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("authoredEffectResourcesOnly", source)
        self.assertNotIn("waterWavesEffects", source)
        for resource in ("standardBlurEffects", "xRay"):
            self.assertIn(f"let {resource}", source)

        layer_loader = EFFECT_TEXTURE_LOADER_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("SceneShakeEffectTextureLoader", layer_loader)

    def test_partial_recovery_helpers_and_iris_composite_path_are_absent(self) -> None:
        compiler = PROGRAM_COMPILER_SOURCE.read_text(encoding="utf-8")
        compositor = COMPOSITOR_SOURCE.read_text(encoding="utf-8")

        for marker in (
            "recoveredAdmission",
            "legacyRecovery",
            "irisInlineSuffix",
            "isolatedCursorRippleChain",
            "isolatedShineChain",
            "xRayPrefix",
        ):
            self.assertNotIn(marker, compiler)
        for marker in (
            "SceneAuthoredEffectExecutionChain",
            "SceneAuthoredEffectGraphPlanner",
            "authoredEffectChain",
            "chainsByLayerID",
            "legacy-authored-chain-product-dispatch",
        ):
            self.assertNotIn(marker, "\n".join(
                path.read_text(encoding="utf-8")
                for path in SOURCE_ROOT.rglob("*.swift")
            ))
        self.assertNotIn("irisSuffix", compositor)
        for relative in (
            "RenderGraph/SceneAuthoredEffectIrisInlineSuffix.swift",
            "RenderGraph/SceneAuthoredIrisInlineSuffixPlanner.swift",
            "RenderGraph/SceneIrisInlineSuffixPlan.swift",
            "RenderGraph/SceneAuthoredEffectCursorRippleIsolation.swift",
            "RenderGraph/SceneAuthoredEffectShineIsolation.swift",
            "RenderGraph/SceneAuthoredEffectXRayPrefix.swift",
            "RenderGraph/SceneAuthoredEffectStageRebase.swift",
        ):
            self.assertFalse((SOURCE_ROOT / relative).exists(), relative)


if __name__ == "__main__":
    unittest.main()
