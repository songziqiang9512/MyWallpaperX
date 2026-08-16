#!/usr/bin/env python3

"""R4 production resolved-material graph executor Metal gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PUBLICATION_GATE = Path(__file__).with_name(
    "test_scene_graph_texture_publication.py"
)
PUBLICATION_FIXTURE = runpy.run_path(str(PUBLICATION_GATE))
RESOURCE_ENCODER_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneGraphResourcePassEncoder.swift"
)
EXECUTOR_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor.swift"
)
PROGRAM_FIRST_STAGES_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
VISUAL_FAILURE_PASSTHROUGH_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
)
SWIFT_SOURCES = [
    *PUBLICATION_FIXTURE["SWIFT_SOURCES"],
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialAttachmentKind.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialAttachmentStorage.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder+Failure.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder+Warmup.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder.swift",
    RESOURCE_ENCODER_SOURCE,
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenResolutionPolicy.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneGraphConditionAdmission.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneGraphAdmissionCompiler.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Material.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+PipelineWarmup.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityTemplateAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+EnvelopeDiagnostics.swift",
    EXECUTOR_SOURCE,
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Attachment.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Preparation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+DedicatedPreparation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Validation.swift",
]


SUPPORT = PUBLICATION_FIXTURE["SUPPORT"].replace(
    "    var supportsUnifiedFullFrameComposeStage: Bool { false }\n",
    """    var supportsUnifiedFullFrameComposeStage: Bool {
        materialNodeCount == 2 && logicalRenderTargetCount == 0
    }
""",
) + r'''

import simd

struct HarnessDedicatedAudioExecutionPlan { let audio: Bool? }
struct SceneProceduralNoiseExecutionPlan {
    enum Variant { case worleyColorV1 }

    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let variant: Variant
    let dependencyProviderLayerID: Int?
    let dependencySlotIndex: Int?
}
struct SceneClippingMaskExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let providerLayerID: Int
    let blendMode: Int
}
struct SceneBlendExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let dependencyProviderLayerID: Int?
}

extension SceneEffectStageExecutionPlan {
    var clippingMask: SceneClippingMaskExecutionPlan? { nil }
    var proceduralNoise: SceneProceduralNoiseExecutionPlan? { nil }
    var blend: SceneBlendExecutionPlan? { nil }
    var shake: HarnessDedicatedAudioExecutionPlan? { nil }
    var pulse: HarnessDedicatedAudioExecutionPlan? { nil }
    var workshopAudioBars: SceneOpacityExecutionPlan? { nil }
}

struct SceneEffectExactRuntimeSubject: Hashable {
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let family: String
}

struct SceneEffectDefinition {
    let relativePath: String
    let functions: SceneJSONValue?
}

struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }
    let kind: Kind
}

struct SceneRenderDescriptor {
    struct PassDescriptor {
        let passIndex: Int
        let combos: [String: Int]
    }

    struct EffectDescriptor {
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
        let contentKind: String = "image"
        let utilityLayer: SceneUtilityLayer? = nil
        let childLayerIDs: [Int] = []
        let dependencyLayerIDs: [Int] = []
        let authoredDependencies: [String] = []
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let combos: [String: Int]
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        Set(descriptor.layers.map(\.id))
    }
}

struct SceneDependencyRenderPlan {
    struct Reference: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: SceneNamedTextureReference.Variant
    }

    struct Binding: Hashable {
        enum Kind: Hashable {
            case clippingMask, proceduralNoiseLayer, imageLayerBlend
        }
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let blendMode: Int
        let kind: Kind
    }

    let references: [Reference]
    let namedReferenceConsumerLayerIDs: Set<Int>
    let bindingsByConsumerLayerID: [Int: Binding]

    init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int> = []
    ) {
        _ = descriptor
        _ = visibleLayerIDs
        _ = executableUtilityConsumerLayerIDs
        references = []
        namedReferenceConsumerLayerIDs = []
        bindingsByConsumerLayerID = [:]
    }
}

struct SceneEffectStageProgram {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let inputRole: SceneAuthoredEffectInputRole
    let stageGraph: SceneAuthoredEffectRenderPlan
    let executionPlan: SceneEffectStageExecutionPlan
}

struct AdmittedLayerGraph {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let stagePrograms: [SceneEffectStageProgram]

    var executionStages: [SceneEffectStageExecutionPlan] {
        stagePrograms.map(\.executionPlan)
    }
}

final class SceneResolvedMaterialRuntimeBridge {
    struct DedicatedFrameInputs {
        let time: Float = 0
        let layerModelMatrix = matrix_identity_float4x4
        let effectTextureProjectionMatrixInverse = matrix_identity_float4x4
    }
}

enum SceneEffectStageRenderer {
    struct PreparedStage {
        let sourceTexture: MTLTexture
        let composeTexture: MTLTexture
        let outputTexture: MTLTexture
    }
    enum StagePreparation {
        case ready(PreparedStage)
        case rejected(reason: String)
    }

    static func prepareStage(
        _ stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        targets: SceneGraphRenderTargetTable,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float,
        sourceSampleExtent: SIMD2<Float>
    ) -> StagePreparation {
        _ = inputs
        _ = sourcePipeline
        _ = time
        guard stage.supportsUnifiedFullFrameComposeStage,
              sourceSampleExtent.x > 0,
              sourceSampleExtent.y > 0,
              targets.plan.logicalTargets.isEmpty,
              targets.inputOutputAliased,
              targets.inputTexture === sourceTexture,
              targets.outputTexture === sourceTexture,
              targets.fullFramePair.first !== targets.fullFramePair.second else {
            return .rejected(reason: "fixture-stage-unavailable")
        }
        let composeTexture: MTLTexture
        if sourceTexture === targets.fullFramePair.first {
            composeTexture = targets.fullFramePair.second
        } else if sourceTexture === targets.fullFramePair.second {
            composeTexture = targets.fullFramePair.first
        } else {
            return .rejected(reason: "fixture-pair-endpoint")
        }
        return .ready(.init(
            sourceTexture: sourceTexture,
            composeTexture: composeTexture,
            outputTexture: targets.outputTexture
        ))
    }

    static func encodePreparedStage(
        _ stage: PreparedStage,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard stage.sourceTexture !== stage.composeTexture,
              stage.composeTexture !== stage.outputTexture,
              stage.sourceTexture.width == stage.composeTexture.width,
              stage.sourceTexture.height == stage.composeTexture.height,
              stage.composeTexture.width == stage.outputTexture.width,
              stage.composeTexture.height == stage.outputTexture.height,
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            return false
        }
        let size = MTLSize(
            width: stage.sourceTexture.width,
            height: stage.sourceTexture.height,
            depth: 1
        )
        encoder.copy(
            from: stage.sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: size,
            to: stage.composeTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.copy(
            from: stage.composeTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: size,
            to: stage.outputTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        return true
    }
}

struct SceneResolvedMaterialRuntimeCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct Key: Hashable {
        let effect: Graph.EffectKey
        let nodeIndex: Int
    }

    enum Entry {
        case template(SceneResolvedMaterialTemplate)
        case failure(SceneResolvedMaterialFailure)
    }

    struct ResourceDemandIssue: Hashable {
        let key: Key
        let slot: Int
    }

    let entries: [Key: Entry]
    let resourceDemandIssues: Set<ResourceDemandIssue>

    init(
        entries: [Key: Entry],
        resourceDemandIssues: Set<ResourceDemandIssue> = []
    ) {
        self.entries = entries
        self.resourceDemandIssues = resourceDemandIssues
    }

    func entry(for node: Graph.Node) -> Entry? {
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)]
    }

    func admittedEntry(
        for node: Graph.Node,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Entry? {
        _ = graph
        _ = descriptor
        return entry(for: node)
    }
}

final class ScenePreparedPersistentGraphTargets {
    struct HistoryRehydrateCopy {
        let sourceToken: SceneGraphExecutionState.PhysicalToken
        let sourceTexture: MTLTexture
        let targetToken: SceneGraphExecutionState.PhysicalToken
        let targetTexture: MTLTexture
    }
}

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    func claim(
        _ admittedGraph: AdmittedLayerGraph
    ) -> ClaimedLayer? {
        claim(layerID: admittedGraph.layerID)
    }

    func resolve(
        _ token: Token,
        for admittedGraph: AdmittedLayerGraph
    ) -> LayerCapability? {
        guard let capability = resolve(token),
              capability.layerID == admittedGraph.layerID else { return nil }
        return capability
    }
}

struct SceneLayerFragmentUniforms {
    let tint: SIMD4<Float>

    static func neutral() -> Self {
        .init(tint: SIMD4<Float>(repeating: 1))
    }
}

struct SceneImageLayerPipeline {
    private struct Vertex {
        let position: SIMD2<Float>
        let texcoord: SIMD2<Float>
    }

    private static let vertices = [
        Vertex(position: .init(-0.5, -0.5), texcoord: .init(0, 1)),
        Vertex(position: .init( 0.5, -0.5), texcoord: .init(1, 1)),
        Vertex(position: .init(-0.5,  0.5), texcoord: .init(0, 0)),
        Vertex(position: .init( 0.5,  0.5), texcoord: .init(1, 0)),
    ]

    let state: MTLRenderPipelineState

    func bind(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(state)
        var vertices = Self.vertices
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            index: 0
        )
    }

    func drawLayer(
        texture: MTLTexture,
        dependencyTexture: MTLTexture? = nil,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        encoder: MTLRenderCommandEncoder
    ) {
        _ = dependencyTexture
        var mvp = mvp
        var uniforms = uniforms
        encoder.setVertexBytes(
            &mvp,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneLayerFragmentUniforms>.size,
            index: 0
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
    }
}
'''


HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Plan = SceneGraphRenderTargetPlan
private typealias Executor = SceneResolvedMaterialGraphExecutor
private typealias Template = SceneResolvedMaterialTemplate
private typealias Capabilities = SceneResolvedMaterialExecutionCapabilityCatalog

private let layerID = 81
private let effect = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "executor-fixture"
)
private let chainedFirstEffect = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "pixel-admittedGraph-first"
)
private let chainedSecondEffect = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 1,
    descriptorID: "pixel-admittedGraph-second"
)
private let chainedThirdEffect = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 2,
    descriptorID: "pixel-admittedGraph-third"
)
private let input = Graph.TextureIdentity(
    kind: .layerSource,
    layerID: layerID,
    effect: nil,
    name: nil
)
private let output = Graph.TextureIdentity(
    kind: .effectOutput,
    layerID: layerID,
    effect: effect,
    name: nil
)
private let chainedFirstOutput = Graph.TextureIdentity(
    kind: .effectOutput,
    layerID: layerID,
    effect: chainedFirstEffect,
    name: nil
)
private let chainedSecondOutput = Graph.TextureIdentity(
    kind: .effectOutput,
    layerID: layerID,
    effect: chainedSecondEffect,
    name: nil
)
private let chainedFinalOutput = Graph.TextureIdentity(
    kind: .effectOutput,
    layerID: layerID,
    effect: chainedThirdEffect,
    name: nil
)
private let first = Graph.TextureIdentity(
    kind: .framebuffer,
    layerID: layerID,
    effect: effect,
    name: "first"
)
private let second = Graph.TextureIdentity(
    kind: .framebuffer,
    layerID: layerID,
    effect: effect,
    name: "second"
)
private let extent = Plan.PixelExtent(width: 2, height: 2)

private let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private func fragmentSource(
    pass: Bool,
    internalDefault: Bool = false,
    frontendInvalid: Bool = false,
    uniformSchemaInvalid: Bool = false,
    dynamicUniform: Bool = false,
    staticUniformMissingDefault: Bool = false,
    pixelTransform: Int? = nil,
    scalarProducer: Bool = false,
    scalarConsumer: String? = nil
) -> String {
    let annotation = pass ? "// [PASS] shadow shadowcasterdemo\n" : ""
    let sampler = internalDefault
        ? #"uniform sampler2D g_Texture0; // {"default":"_rt_history"}"#
        : "uniform sampler2D g_Texture0;"
    let varying = frontendInvalid
        ? "varying vec3 v_TexCoord;"
        : "varying vec2 v_TexCoord;"
    let uniform = uniformSchemaInvalid
        ? #"uniform float g_InvalidUniform; // {"material":3}"#
        : dynamicUniform
            ? #"uniform float u_Gain; // {"material":"Gain","default":1}"#
            : staticUniformMissingDefault
                ? #"uniform float u_Static; // {"material":"Static"}"#
                : ""
    let expression = if uniformSchemaInvalid {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord)"
            + " * g_InvalidUniform;"
    } else if staticUniformMissingDefault {
        "vec4 color = texSample2D(g_Texture0, v_TexCoord);"
            + " color.rgb *= u_Static; gl_FragColor = color;"
    } else if scalarProducer {
        "gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0);"
    } else if scalarConsumer == "red" {
        "float scalar = texSample2D(g_Texture0, v_TexCoord).r;"
            + " gl_FragColor = vec4(scalar, 0.0, 0.0, 1.0);"
    } else if scalarConsumer == "green" {
        "float scalar = texSample2D(g_Texture0, v_TexCoord).g;"
            + " gl_FragColor = vec4(scalar, 0.0, 0.0, 1.0);"
    } else if scalarConsumer == "alias" {
        "vec4 sampled = texSample2D(g_Texture0, v_TexCoord);"
            + " gl_FragColor = vec4(sampled.r, 0.0, 0.0, 1.0);"
    } else if scalarConsumer == "whole" {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
    } else if pixelTransform != nil {
        if dynamicUniform {
            """
            vec4 color = texSample2D(g_Texture0, v_TexCoord);
            color.rgb = color.rgb.gbr;
            color.rgb *= u_Gain;
            gl_FragColor = color;
            """
        } else {
            """
            vec4 color = texSample2D(g_Texture0, v_TexCoord);
            color.rgb = color.rgb.gbr;
            gl_FragColor = color;
            """
        }
    } else if dynamicUniform {
        """
        vec4 color = texSample2D(g_Texture0, v_TexCoord);
        color.rgb *= u_Gain;
        gl_FragColor = color;
        """
    } else if frontendInvalid {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord.xy);"
    } else {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
    }
    return annotation + """
    \(varying)
    \(sampler)
    \(uniform)
    void main() {
        \(expression)
    }
    """
}

private func binding(
    _ identity: Graph.TextureIdentity,
    conditions: SceneJSONValue? = nil
) -> Graph.Binding {
    return .init(
        slot: 0,
        authoredName: identity.name ?? "previous",
        texture: identity,
        conditions: conditions
    )
}

private func material(
    _ nodeIndex: Int,
    ordinal: Int,
    target: Graph.TextureIdentity,
    read: Graph.TextureIdentity,
    compose: SceneJSONValue? = nil,
    conditions: SceneJSONValue? = nil,
    owner: Graph.EffectKey = effect
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: owner,
        definitionPassIndex: nodeIndex,
        materialOrdinal: ordinal,
        instancePassIndex: ordinal,
        kind: .material,
        materialPath: "materials/executor-\(owner.effectIndex).json",
        materialPassID: "executor-\(owner.effectIndex)#\(ordinal)",
        target: target,
        bindings: [binding(read)],
        commandSource: nil,
        commandTarget: nil,
        compose: compose,
        conditions: conditions
    )
}

private func implicitFramebufferMaterial(
    _ nodeIndex: Int,
    ordinal: Int,
    target: Graph.TextureIdentity
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: effect,
        definitionPassIndex: nodeIndex,
        materialOrdinal: ordinal,
        instancePassIndex: ordinal,
        kind: .material,
        materialPath: "materials/implicit-framebuffer.json",
        materialPassID: "implicit-framebuffer#\(ordinal)",
        target: target,
        bindings: [],
        commandSource: nil,
        commandTarget: nil,
        compose: nil,
        conditions: nil
    )
}

private func fullFrameComposeMaterial(
    _ nodeIndex: Int,
    ordinal: Int,
    compose: SceneJSONValue?
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: effect,
        definitionPassIndex: nodeIndex,
        materialOrdinal: ordinal,
        instancePassIndex: ordinal,
        kind: .material,
        materialPath: "materials/full-frame-compose.json",
        materialPassID: "full-frame-compose#\(ordinal)",
        target: output,
        bindings: [],
        commandSource: nil,
        commandTarget: nil,
        compose: compose,
        conditions: nil
    )
}

private func command(
    _ nodeIndex: Int,
    kind: Graph.NodeKind,
    source: Graph.TextureIdentity,
    target: Graph.TextureIdentity
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: effect,
        definitionPassIndex: nodeIndex,
        materialOrdinal: nil,
        instancePassIndex: nil,
        kind: kind,
        materialPath: nil,
        materialPassID: nil,
        target: nil,
        bindings: [],
        commandSource: source,
        commandTarget: target,
        compose: nil,
        conditions: nil
    )
}

private func rawTarget(
    _ identity: Graph.TextureIdentity,
    width: Double? = nil,
    height: Double? = nil,
    format: String = "rgba_backbuffer",
    unique: Bool = false,
    clear: SceneJSONValue? = nil,
    uvs: SceneJSONValue? = nil
) -> Graph.RenderTarget {
    .init(
        texture: identity,
        extent: .init(width: width, height: height, fit: nil, scale: nil),
        format: format,
        declaredUnique: unique,
        clear: clear,
        uvs: uvs,
        conditions: nil
    )
}

private func graph(
    targets: [Graph.RenderTarget],
    nodes: [Graph.Node]
) -> Graph {
    .init(
        layerID: layerID,
        effects: [.init(
            key: effect,
            definitionPath: "effects/executor/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: targets,
        nodes: nodes,
        finalOutput: output,
        blockers: []
    )
}

private func chainedGraph() -> Graph {
    let nodes = [
        material(
            0,
            ordinal: 0,
            target: chainedFirstOutput,
            read: input,
            owner: chainedFirstEffect
        ),
        material(
            1,
            ordinal: 0,
            target: chainedSecondOutput,
            read: chainedFirstOutput,
            owner: chainedSecondEffect
        ),
        material(
            2,
            ordinal: 0,
            target: chainedFinalOutput,
            read: chainedSecondOutput,
            owner: chainedThirdEffect
        ),
    ]
    return .init(
        layerID: layerID,
        effects: [
            .init(
                key: chainedFirstEffect,
                definitionPath: "effects/pixel-admittedGraph-first/effect.json",
                input: input,
                output: chainedFirstOutput,
                nodeIndices: [0]
            ),
            .init(
                key: chainedSecondEffect,
                definitionPath: "effects/pixel-admittedGraph-second/effect.json",
                input: chainedFirstOutput,
                output: chainedSecondOutput,
                nodeIndices: [1]
            ),
            .init(
                key: chainedThirdEffect,
                definitionPath: "effects/pixel-admittedGraph-third/effect.json",
                input: chainedSecondOutput,
                output: chainedFinalOutput,
                nodeIndices: [2]
            ),
        ],
        renderTargets: [],
        nodes: nodes,
        finalOutput: chainedFinalOutput,
        blockers: []
    )
}

private func executionPlan(
    for graph: Graph,
    inputRole: SceneAuthoredEffectInputRole = .layerSource
) -> SceneEffectStageExecutionPlan {
    .init(
        layerID: graph.layerID,
        materialNodeCount: graph.nodes.filter { $0.kind == .material }.count,
        logicalRenderTargetCount: graph.renderTargets.count,
        inputRole: inputRole,
        cursorRipple: nil
    )
}

private func admittedGraph(_ graph: Graph) -> AdmittedLayerGraph {
    let execution = executionPlan(for: graph)
    return .init(
        layerID: graph.layerID,
        renderGraph: graph,
        stagePrograms: [.init(
            effectKey: effect,
            inputRole: .layerSource,
            stageGraph: graph,
            executionPlan: execution
        )]
    )
}

private func orderedLayerGraph(_ graph: Graph) -> AdmittedLayerGraph {
    precondition(graph.renderTargets.isEmpty && graph.effects.count == 3)
    let stages = graph.effects.enumerated().map { index, effect in
        let stageGraph = Graph(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: [],
            nodes: graph.nodes.filter { $0.effect == effect.key },
            finalOutput: effect.output,
            blockers: []
        )
        let inputRole: SceneAuthoredEffectInputRole = index == 0
            ? .layerSource : .priorEffectOutput
        return SceneEffectStageProgram(
            effectKey: effect.key,
            inputRole: inputRole,
            stageGraph: stageGraph,
            executionPlan: executionPlan(for: stageGraph, inputRole: inputRole)
        )
    }
    return .init(
        layerID: graph.layerID,
        renderGraph: graph,
        stagePrograms: stages
    )
}

private func role(
    _ identity: Graph.TextureIdentity
) -> Template.GraphTextureRole {
    switch identity.kind {
    case .layerSource: .layerSource
    case .effectOutput: .effectOutput
    case .framebuffer: .framebuffer
    case .unresolved: fatalError("unresolved graph fixture")
    }
}

private func shaderContract(
    nodeIndex: Int,
    pass: Bool,
    internalDefault: Bool = false,
    frontendInvalid: Bool = false,
    uniformSchemaInvalid: Bool = false,
    dynamicUniform: Bool = false,
    staticUniformMissingDefault: Bool = false,
    pixelTransform: Int? = nil,
    implicitFramebuffer: Bool = false,
    implicitFramebufferAnnotation: Bool = true,
    historicalFramebufferAlias: Bool = false,
    scalarProducer: Bool = false,
    scalarConsumer: String? = nil
) -> SceneShaderContract {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        path: String,
        source: String
    ) -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(
            source,
            stageRelativePath: path
        )
        return .init(
            kind: kind,
            relativePath: path,
            source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes,
            annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let prefix = "fixture/executor-\(nodeIndex)"
    let explicitFramebufferFragment = historicalFramebufferAlias ? """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0; // {"material":"ui_editor_properties_framebuffer","hidden":true}
    uniform vec4 g_Texture0Resolution;
    void main() {
        gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
    }
    """ : """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
    uniform vec4 g_Texture0Resolution;
    void main() {
        gl_FragColor = vec4(g_Texture0Resolution.xy * 0.0, 0.0, 1.0);
    }
    """
    let fragment = implicitFramebuffer ? (implicitFramebufferAnnotation
        ? explicitFramebufferFragment : """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() {
        gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
    }
    """ ) : fragmentSource(
        pass: pass,
        internalDefault: internalDefault,
        frontendInvalid: frontendInvalid,
        uniformSchemaInvalid: uniformSchemaInvalid,
        dynamicUniform: dynamicUniform,
        staticUniformMissingDefault: staticUniformMissingDefault,
        pixelTransform: pixelTransform,
        scalarProducer: scalarProducer,
        scalarConsumer: scalarConsumer
    )
    let stages = [
        stage(.vertex, path: "\(prefix).vert", source: vertexSource),
        stage(
            .fragment,
            path: "\(prefix).frag",
            source: fragment
        ),
    ]
    let sourceGraph = SceneShaderSourceGraph(
        roots: [
            .init(label: "vertex", virtualPath: "\(prefix).vert"),
            .init(label: "fragment", virtualPath: "\(prefix).frag"),
        ],
        nodes: stages.map {
            .init(
                virtualPath: $0.relativePath,
                provenance: .package,
                source: $0.source,
                rawSHA256: $0.rawSHA256,
                byteCount: $0.source.utf8.count
            )
        },
        edges: [],
        diagnostics: [],
        dependencySHA256: "executor-dependency-\(nodeIndex)"
    )
    return .init(
        identity: "fixture/executor-\(nodeIndex)",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "executor-contract-\(nodeIndex)",
        sourceGraph: sourceGraph
    )
}

private func implicitFramebufferTemplate(
    for node: Graph.Node,
    historicalAlias: Bool = false
) -> Template {
    guard let target = node.target, node.bindings.isEmpty else {
        fatalError("implicit framebuffer fixture is incomplete")
    }
    let contract = shaderContract(
        nodeIndex: node.nodeIndex,
        pass: false,
        implicitFramebuffer: true,
        implicitFramebufferAnnotation: historicalAlias,
        historicalFramebufferAlias: historicalAlias
    )
    return Template.validated(
        textureSlots: Array(repeating: nil, count: 8),
        combos: [],
        uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )!,
        graphRole: .init(
            effectInput: role(input),
            effectOutput: role(output),
            nodeTarget: role(target),
            bindings: []
        ),
        shaderContract: contract,
        diagnosticProvenance: .init(
            nodeIndex: node.nodeIndex,
            authoredShaderPath: contract.identity,
            contractIdentity: contract.identity,
            contractCanonicalSHA256: contract.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
}

private func template(
    for node: Graph.Node,
    pass: Bool = false,
    internalDefault: Bool = false,
    overwrite: Bool = true,
    frontendInvalid: Bool = false,
    uniformSchemaInvalid: Bool = false,
    dynamicUniform: Bool = false,
    staticUniformMissingDefault: Bool = false,
    scalarProducer: Bool = false,
    scalarConsumer: String? = nil
) -> Template {
    guard let target = node.target,
          let inputBinding = node.bindings.first,
          let slot = inputBinding.slot else {
        fatalError("material fixture is incomplete")
    }
    let pixelTransform: Int? = if node.effect == chainedFirstEffect {
        1
    } else if node.effect == chainedSecondEffect {
        2
    } else if node.effect == chainedThirdEffect {
        3
    } else {
        nil
    }
    let contract = shaderContract(
        nodeIndex: node.nodeIndex,
        pass: pass,
        internalDefault: internalDefault,
        frontendInvalid: frontendInvalid,
        uniformSchemaInvalid: uniformSchemaInvalid,
        dynamicUniform: dynamicUniform,
        staticUniformMissingDefault: staticUniformMissingDefault,
        pixelTransform: pixelTransform,
        scalarProducer: scalarProducer,
        scalarConsumer: scalarConsumer
    )
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[slot] = .init(index: slot, candidates: [
        .init(
            reference: .graph(inputBinding.texture),
            provenance: .explicitBinding
        ),
    ])
    let effectInput: Template.GraphTextureRole
    if node.effect == chainedSecondEffect {
        effectInput = role(chainedFirstOutput)
    } else if node.effect == chainedThirdEffect {
        effectInput = role(chainedSecondOutput)
    } else {
        effectInput = role(input)
    }
    return Template.validated(
        textureSlots: slots,
        combos: [],
        uniformDeclarations: dynamicUniform
            ? [dynamicUniformDeclaration(for: node)] : [],
        renderState: SceneMaterialRenderState.compile(
            blending: overwrite ? "normal" : "translucent",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )!,
        graphRole: .init(
            effectInput: effectInput,
            effectOutput: role(output),
            nodeTarget: role(target),
            bindings: [.init(slot: slot, texture: role(inputBinding.texture))]
        ),
        shaderContract: contract,
        diagnosticProvenance: .init(
            nodeIndex: node.nodeIndex,
            authoredShaderPath: contract.identity,
            contractIdentity: contract.identity,
            contractCanonicalSHA256: contract.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
}

private func dynamicUniformTarget(_ node: Graph.Node) -> SceneDynamicTarget {
    .effectConstant(
        layerID: node.effect.layerID,
        effectIndex: node.effect.effectIndex,
        passIndex: node.instancePassIndex!,
        name: "Gain"
    )
}

private func dynamicUniformDeclaration(
    for node: Graph.Node
) -> Template.UniformDeclaration {
    .init(
        name: "Gain",
        value: .dynamic(.init(
            target: dynamicUniformTarget(node),
            valueContributors: [.timeline],
            scriptAttachments: [],
            authoredFallback: .init(
                valueKind: "fixture",
                componentBitPatterns: [Double(1).bitPattern],
                authoredBindingKeys: ["value"]
            ),
            authoredBindingKeys: ["value"]
        ))
    )
}

private func catalog(
    for graph: Graph,
    passNodes: Set<Int> = [],
    nonOverwriteNodes: Set<Int> = [],
    internalDefaultNodes: Set<Int> = [],
    frontendInvalidNodes: Set<Int> = [],
    uniformSchemaInvalidNodes: Set<Int> = [],
    dynamicUniformNodes: Set<Int> = [],
    staticUniformMissingDefaultNodes: Set<Int> = [],
    omittedNodes: Set<Int> = [],
    demandIssueNodes: Set<Int> = [],
    implicitFramebufferNodes: Set<Int> = [],
    historicalFramebufferNodes: Set<Int> = [],
    scalarProducerNodes: Set<Int> = [],
    scalarConsumerNodes: [Int: String] = [:]
) -> SceneResolvedMaterialRuntimeCatalog {
    var entries: [
        SceneResolvedMaterialRuntimeCatalog.Key:
            SceneResolvedMaterialRuntimeCatalog.Entry
    ] = [:]
    for node in graph.nodes where node.kind == .material {
        guard !omittedNodes.contains(node.nodeIndex) else { continue }
        let value = implicitFramebufferNodes.contains(node.nodeIndex)
            ? implicitFramebufferTemplate(
                for: node,
                historicalAlias: historicalFramebufferNodes.contains(node.nodeIndex)
            )
            : template(
                for: node,
                pass: passNodes.contains(node.nodeIndex),
                internalDefault: internalDefaultNodes.contains(node.nodeIndex),
                overwrite: !nonOverwriteNodes.contains(node.nodeIndex),
                frontendInvalid: frontendInvalidNodes.contains(node.nodeIndex),
                uniformSchemaInvalid:
                    uniformSchemaInvalidNodes.contains(node.nodeIndex),
                dynamicUniform: dynamicUniformNodes.contains(node.nodeIndex),
                staticUniformMissingDefault:
                    staticUniformMissingDefaultNodes.contains(node.nodeIndex),
                scalarProducer: scalarProducerNodes.contains(node.nodeIndex),
                scalarConsumer: scalarConsumerNodes[node.nodeIndex]
            )
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(value)
    }
    let issues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue> =
        Set(demandIssueNodes.map { nodeIndex in
            let slot = graph.nodes.first(where: {
                $0.nodeIndex == nodeIndex
            })?.bindings.first?.slot ?? 0
            return SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue(
                key: .init(effect: effect, nodeIndex: nodeIndex),
                slot: slot
            )
        })
    return .init(entries: entries, resourceDemandIssues: issues)
}

private func requirePlan(
    _ graph: Graph,
    width: Int = extent.width,
    height: Int = extent.height
) -> Plan {
    switch Plan.make(
        executionPlan: executionPlan(for: graph),
        graph: graph,
        inputWidth: width,
        inputHeight: height
    ) {
    case let .success(value): value
    case let .failure(failure): fatalError("plan failed: \(failure.rawValue)")
    }
}

private func requireR4Plan(_ graph: Graph) -> Plan {
    switch Plan.make(
        graph: graph,
        inputRole: .layerSource,
        inputWidth: extent.width,
        inputHeight: extent.height
    ) {
    case let .success(value): value
    case let .failure(failure): fatalError("R4 plan failed: \(failure.rawValue)")
    }
}

private func makeLease(
    _ plan: Plan,
    device: MTLDevice,
    generation: UInt64 = 7
) -> SceneGraphRenderTargetLease {
    let table: SceneGraphRenderTargetTable
    switch SceneGraphRenderTargetTable.make(
        plan: plan,
        device: device,
        byteBudget: 1_048_576
    ) {
    case let .success(value): table = value
    case let .failure(failure): fatalError("table failed: \(failure.rawValue)")
    }
    var ordinal = 0
    switch SceneGraphRenderTargetLease.make(
        table: table,
        generation: generation,
        tokenForTexture: { _ in
            defer { ordinal += 1 }
            return .init(rawValue: "executor-physical-\(generation)-\(ordinal)")
        }
    ) {
    case let .success(value): return value
    case let .failure(failure): fatalError("lease failed: \(failure.rawValue)")
    }
}

private func makeChainedLeases(
    _ capability: Capabilities.LayerCapability,
    device: MTLDevice,
    generation: UInt64 = 17
) -> [SceneGraphRenderTargetLease]? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: extent.width,
        height: extent.height,
        mipmapped: false
    )
    descriptor.storageMode = .private
    descriptor.usage = [.renderTarget, .shaderRead]
    guard let zero = device.makeTexture(descriptor: descriptor),
          let one = device.makeTexture(descriptor: descriptor) else { return nil }
    let zeroToken = Executor.State.PhysicalToken(rawValue: "pixel-admittedGraph-zero")
    let oneToken = Executor.State.PhysicalToken(rawValue: "pixel-admittedGraph-one")
    func texture(_ member: SceneLayerFullFramePairPlan.Member) -> MTLTexture {
        member == .zero ? zero : one
    }
    var leases: [SceneGraphRenderTargetLease] = []
    for index in capability.admittedProducts.indices {
        let graph = capability.admittedProducts[index].graph
        let role: SceneAuthoredEffectInputRole = index == 0
            ? .layerSource : .priorEffectOutput
        let plan: Plan
        switch Plan.make(
            graph: graph,
            inputRole: role,
            inputWidth: extent.width,
            inputHeight: extent.height
        ) {
        case let .success(value): plan = value
        case .failure: return nil
        }
        let step = capability.pairPlan.effects[index]
        let mapped: SceneGraphRenderTargetTable
        switch SceneGraphRenderTargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: [
                plan.input: texture(step.inputMember),
                plan.output: texture(step.outputMember),
            ],
            fullFramePair: .init(first: zero, second: one),
            expectsInputOutputAlias: step.inputMember == step.outputMember
        ) {
        case let .success(value): mapped = value
        case .failure: return nil
        }
        let lease: SceneGraphRenderTargetLease
        switch SceneGraphRenderTargetLease.make(
            table: mapped,
            generation: generation,
            tokenForTexture: { object in
                object === zero ? zeroToken : oneToken
            },
            fullFramePairGeneration: generation,
            tokenForPairTexture: { object in
                object === zero ? zeroToken : oneToken
            }
        ) {
        case let .success(value): lease = value
        case .failure: return nil
        }
        leases.append(lease)
    }
    return leases
}

private func manualPlan(
    targets: [Plan.LogicalTarget],
    commands: [Plan.Command]
) -> Plan {
    .testingPlan(
        layerID: layerID,
        input: input,
        output: output,
        inputExtent: extent,
        logicalTargets: targets,
        commands: commands
    )
}

private func logical(
    _ identity: Graph.TextureIdentity,
    width: Int = 2,
    height: Int = 2,
    format: Plan.TextureFormat = .rgbaBackbuffer,
    unique: Bool = false,
    firstWrite: Int,
    lastWrite: Int,
    firstRead: Int?,
    lastRead: Int?
) -> Plan.LogicalTarget {
    .init(
        identity: identity,
        extent: .init(width: width, height: height),
        format: format,
        isUnique: unique,
        lifetime: .init(
            firstWriteNodeIndex: firstWrite,
            lastWriteNodeIndex: lastWrite,
            firstReadNodeIndex: firstRead,
            lastReadNodeIndex: lastRead
        ),
        initialClear: nil
    )
}

private func makeSource(
    _ device: MTLDevice,
    width: Int = 1,
    height: Int = 1,
    usage: MTLTextureUsage = .shaderRead,
    bgra: [UInt8] = [0, 0, 255, 255]
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = usage
    let texture = device.makeTexture(descriptor: descriptor)!
    precondition(bgra.count == 4)
    let red = (0 ..< width * height).flatMap { _ in bgra }
    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: red,
        bytesPerRow: width * 4
    )
    return texture
}

private func makeSourcePipeline(_ device: MTLDevice) -> SceneImageLayerPipeline {
    let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float2 position; float2 texcoord; };
    struct Varying { float4 position [[position]]; float2 texcoord; };
    struct Uniforms { float4 tint; };
    vertex Varying fixtureVertex(
        const device Vertex *vertices [[buffer(0)]],
        constant float4x4 &mvp [[buffer(1)]],
        uint id [[vertex_id]]
    ) {
        Varying out;
        out.position = mvp * float4(vertices[id].position, 0, 1);
        out.texcoord = vertices[id].texcoord;
        return out;
    }
    fragment float4 fixtureFragment(
        Varying in [[stage_in]],
        texture2d<float> source [[texture(0)]],
        constant Uniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge,
                            filter::nearest);
        return source.sample(s, in.texcoord) * uniforms.tint;
    }
    """
    let library = try! device.makeLibrary(source: source, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "fixtureVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "fixtureFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    return .init(state: try! device.makeRenderPipelineState(descriptor: descriptor))
}

private func frame(
    _ index: UInt64,
    width: Int = extent.width,
    height: Int = extent.height,
    dynamicDefinitions: [SceneDynamicTargetDefinition] = [],
    timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
) -> SceneResolvedMaterialFrameSnapshot {
    let dynamic = SceneDynamicSnapshotResolver().resolve(
        frameIndex: index,
        generation: index,
        definitions: dynamicDefinitions,
        timelineValues: timelineValues
    )
    let result = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: .init(
            frameEpoch: index,
            frameIndex: index,
            entries: [:]
        ),
        dynamicSnapshot: dynamic.snapshot,
        frameInputs: .init(
            frameIndex: index,
            screenSize: CGSize(width: width, height: height),
            sceneTime: Float(index),
            dayTime: 0,
            frameTime: 1 / 60,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero
        )
    )
    guard case let .success(value) = result else {
        fatalError("frame snapshot failed")
    }
    return value
}

private func clear(
    _ lease: SceneGraphRenderTargetLease,
    queue: MTLCommandQueue
) -> Bool {
    guard let buffer = queue.makeCommandBuffer() else { return false }
    for texture in lease.texturesByToken.values {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1)
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else { return false }
        encoder.endEncoding()
    }
    buffer.commit()
    buffer.waitUntilCompleted()
    return buffer.status == .completed && buffer.error == nil
}

private struct Readback {
    let buffer: MTLBuffer
    let bytesPerRow: Int
    let width: Int
    let height: Int

    var firstPixel: [UInt8] {
        let pointer = buffer.contents().assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: 4))
    }

    var lastPixel: [UInt8] {
        let offset = (height - 1) * bytesPerRow + (width - 1) * 4
        let pointer = buffer.contents().advanced(by: offset)
            .assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: 4))
    }
}

private func appendReadback(
    _ texture: MTLTexture,
    commandBuffer: MTLCommandBuffer
) -> Readback? {
    let bytesPerRow = 256
    guard let destination = texture.device.makeBuffer(
        length: bytesPerRow * texture.height,
        options: .storageModeShared
    ), let encoder = commandBuffer.makeBlitCommandEncoder() else {
        return nil
    }
    encoder.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: .init(x: 0, y: 0, z: 0),
        sourceSize: .init(
            width: texture.width,
            height: texture.height,
            depth: 1
        ),
        to: destination,
        destinationOffset: 0,
        destinationBytesPerRow: bytesPerRow,
        destinationBytesPerImage: bytesPerRow * texture.height
    )
    encoder.endEncoding()
    return .init(
        buffer: destination,
        bytesPerRow: bytesPerRow,
        width: texture.width,
        height: texture.height
    )
}

private struct ScalarReadback {
    let buffer: MTLBuffer
    let bytesPerRow: Int
    let width: Int
    let height: Int

    var first: UInt8 {
        buffer.contents().assumingMemoryBound(to: UInt8.self).pointee
    }

    var last: UInt8 {
        let offset = (height - 1) * bytesPerRow + width - 1
        return buffer.contents().advanced(by: offset)
            .assumingMemoryBound(to: UInt8.self).pointee
    }
}

private func appendScalarReadback(
    _ texture: MTLTexture,
    commandBuffer: MTLCommandBuffer
) -> ScalarReadback? {
    guard texture.pixelFormat == .r8Unorm else { return nil }
    let bytesPerRow = 256
    guard let destination = texture.device.makeBuffer(
        length: bytesPerRow * texture.height,
        options: .storageModeShared
    ), let encoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
    encoder.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: .init(x: 0, y: 0, z: 0),
        sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
        to: destination,
        destinationOffset: 0,
        destinationBytesPerRow: bytesPerRow,
        destinationBytesPerImage: bytesPerRow * texture.height
    )
    encoder.endEncoding()
    return .init(
        buffer: destination,
        bytesPerRow: bytesPerRow,
        width: texture.width,
        height: texture.height
    )
}

private func matches(_ pixel: [UInt8], _ expected: [UInt8]) -> Bool {
    pixel.count == expected.count && zip(pixel, expected).allSatisfy {
        abs(Int($0) - Int($1)) <= 2
    }
}

private func fill(
    _ texture: MTLTexture,
    color: MTLClearColor,
    queue: MTLCommandQueue
) -> Bool {
    guard let buffer = queue.makeCommandBuffer() else { return false }
    let descriptor = MTLRenderPassDescriptor()
    descriptor.colorAttachments[0].texture = texture
    descriptor.colorAttachments[0].loadAction = .clear
    descriptor.colorAttachments[0].storeAction = .store
    descriptor.colorAttachments[0].clearColor = color
    guard let encoder = buffer.makeRenderCommandEncoder(
        descriptor: descriptor
    ) else { return false }
    encoder.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    return buffer.status == .completed && buffer.error == nil
}

private func historyGraph(fixedSize: Bool) -> Graph {
    let width = fixedSize ? 2.0 : nil
    let height = fixedSize ? 2.0 : nil
    return graph(
        targets: [
            rawTarget(first, width: width, height: height, unique: true),
            rawTarget(second, width: width, height: height, unique: true),
        ],
        nodes: [
            material(0, ordinal: 0, target: second, read: first),
            command(1, kind: .swap, source: first, target: second),
            material(2, ordinal: 1, target: output, read: first),
        ]
    )
}

private func historyCopies(
    transition: Executor.PreparedStage,
    sourceLease: SceneGraphRenderTargetLease,
    targetLease: SceneGraphRenderTargetLease
) -> [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]? {
    let state = transition.transition.nextState
    let authoredSlotByToken = Dictionary(uniqueKeysWithValues:
        state.authoredResources.map { ($0.value.token, $0.key) }
    )
    let sourceTokens = Set(state.logicalMapping.values.compactMap {
        $0.contentGeneration > 0 ? $0.token : nil
    }).sorted { $0.rawValue < $1.rawValue }
    var copies: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy] = []
    for sourceToken in sourceTokens {
        guard let identity = authoredSlotByToken[sourceToken],
              let sourceTexture = sourceLease.texturesByToken[sourceToken],
              let target = targetLease.framebufferAllocation.resources[identity],
              let targetTexture = targetLease.texturesByToken[target.token] else {
            return nil
        }
        copies.append(.init(
            sourceToken: sourceToken,
            sourceTexture: sourceTexture,
            targetToken: target.token,
            targetTexture: targetTexture
        ))
    }
    return copies
}

private func preservesPermutation(
    previous: Executor.State,
    mapping: [Graph.TextureIdentity: Executor.State.VersionedResource],
    targetLease: SceneGraphRenderTargetLease,
    preservesContent: Bool
) -> Bool {
    guard Set(mapping.keys) == Set(previous.logicalMapping.keys) else {
        return false
    }
    let authoredSlotByToken = Dictionary(uniqueKeysWithValues:
        previous.authoredResources.map { ($0.value.token, $0.key) }
    )
    return previous.logicalMapping.allSatisfy { identity, old in
        guard let authoredSlot = authoredSlotByToken[old.token],
              let replacement = targetLease.framebufferAllocation
                .resources[authoredSlot],
              let rebased = mapping[identity] else { return false }
        return rebased.token == replacement.token
            && rebased.descriptor == replacement.descriptor
            && rebased.contentGeneration
                == (preservesContent ? old.contentGeneration : 0)
    }
}

private struct HistoryScenarioResult {
    var fixtureHasSwapPermutation = false
    var noCopiesBehavior = false
    var incompleteCopiesBehavior = false
    var unexpectedCopiesRejected = false
    var mappingBehavior = false
    var preparedAndEncoded = false
    var pixelBehavior = false
}

private func runHistoryScenario(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline,
    fixedSize: Bool,
    resizedWidth: Int,
    resizedHeight: Int,
    preservesDescriptors: Bool
) -> HistoryScenarioResult {
    let graph = historyGraph(fixedSize: fixedSize)
    let admittedGraph = admittedGraph(graph)
    let capabilities = capabilities(admittedGraph, catalog: catalog(for: graph))
    guard let claim = capabilities.claim(admittedGraph),
          let executor = Executor(device: device, capabilities: capabilities),
          let firstBuffer = queue.makeCommandBuffer() else { return .init() }
    let firstLease = makeLease(
        requirePlan(graph),
        device: device,
        generation: 30
    )
    let firstPreparation = executor.prepare(
        token: claim.token,
        leases: [firstLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(30),
        sourceTexture: makeSource(device),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        dedicatedInputs: .init(),
        commandBuffer: firstBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(firstPrepared) = firstPreparation,
          executor.encode(firstPrepared, commandBuffer: firstBuffer),
          let transition = firstPrepared.stages.first else {
        return .init()
    }
    firstBuffer.commit()
    firstBuffer.waitUntilCompleted()
    guard firstBuffer.status == .completed, firstBuffer.error == nil,
          let historicalFirst = transition.persistentResources[first]?.publication
            .texture,
          let historicalSecond = transition.persistentResources[second]?.publication
            .texture,
          fill(
              historicalFirst,
              color: MTLClearColorMake(0, 1, 0, 1),
              queue: queue
          ), fill(
              historicalSecond,
              color: MTLClearColorMake(0, 0, 1, 1),
              queue: queue
          ) else { return .init() }

    let previous = transition.transition.nextState
    var result = HistoryScenarioResult()
    result.fixtureHasSwapPermutation =
        previous.logicalMapping[first]?.token
            == previous.authoredResources[second]?.token
        && previous.logicalMapping[second]?.token
            == previous.authoredResources[first]?.token

    let nextLease = makeLease(
        requirePlan(
            graph,
            width: resizedWidth,
            height: resizedHeight
        ),
        device: device,
        generation: 31
    )
    guard let copies = historyCopies(
        transition: transition,
        sourceLease: firstLease,
        targetLease: nextLease
    ), copies.count == 2 else { return result }
    let nextSource = makeSource(
        device,
        width: resizedWidth,
        height: resizedHeight
    )

    guard let noCopiesBuffer = queue.makeCommandBuffer() else { return result }
    let noCopies = executor.prepare(
        token: claim.token,
        leases: [nextLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(31, width: resizedWidth, height: resizedHeight),
        sourceTexture: nextSource,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        dedicatedInputs: .init(),
        commandBuffer: noCopiesBuffer,
        previousStates: [effect: previous],
        previousGraphResources: [effect: transition.persistentResources],
        effectGeneration: 1,
        resetGeneration: 1
    )

    if preservesDescriptors {
        result.noCopiesBehavior = failureCode(noCopies)
            == Executor.Failure.historyRejected.rawValue
        guard let incompleteBuffer = queue.makeCommandBuffer() else {
            return result
        }
        let incomplete = executor.prepare(
            token: claim.token,
            leases: [nextLease],
            historyRehydrateCopiesByEffect: [effect: [copies[0]]],
            frame: frame(32, width: resizedWidth, height: resizedHeight),
            sourceTexture: nextSource,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: incompleteBuffer,
            previousStates: [effect: previous],
            previousGraphResources: [effect: transition.persistentResources],
            effectGeneration: 1,
            resetGeneration: 1
        )
        result.incompleteCopiesBehavior = failureCode(incomplete)
            == Executor.Failure.historyRejected.rawValue
    } else {
        guard let unexpectedBuffer = queue.makeCommandBuffer() else {
            return result
        }
        let unexpected = executor.prepare(
            token: claim.token,
            leases: [nextLease],
            historyRehydrateCopiesByEffect: [effect: copies],
            frame: frame(32, width: resizedWidth, height: resizedHeight),
            sourceTexture: nextSource,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: unexpectedBuffer,
            previousStates: [effect: previous],
            previousGraphResources: [effect: transition.persistentResources],
            effectGeneration: 1,
            resetGeneration: 1
        )
        result.unexpectedCopiesRejected = failureCode(unexpected)
            == Executor.Failure.historyRejected.rawValue
    }

    let acceptedPreparation: Result<Executor.PreparedGraph, Executor.Failure>
    let acceptedBuffer: MTLCommandBuffer
    if preservesDescriptors {
        guard let buffer = queue.makeCommandBuffer() else { return result }
        acceptedBuffer = buffer
        acceptedPreparation = executor.prepare(
            token: claim.token,
            leases: [nextLease],
            historyRehydrateCopiesByEffect: [effect: copies],
            frame: frame(33, width: resizedWidth, height: resizedHeight),
            sourceTexture: nextSource,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: buffer,
            previousStates: [effect: previous],
            previousGraphResources: [effect: transition.persistentResources],
            effectGeneration: 1,
            resetGeneration: 1
        )
    } else {
        acceptedBuffer = noCopiesBuffer
        acceptedPreparation = noCopies
        result.noCopiesBehavior = failureCode(noCopies) == "success"
    }

    guard case let .success(accepted) = acceptedPreparation,
          let acceptedTransition = accepted.stages.first else {
        return result
    }
    result.mappingBehavior = preservesPermutation(
        previous: previous,
        mapping: acceptedTransition.transition.transaction.mappingBefore,
        targetLease: nextLease,
        preservesContent: preservesDescriptors
    )
    result.preparedAndEncoded = executor.encode(
        accepted,
        commandBuffer: acceptedBuffer
    )
    guard result.preparedAndEncoded,
          let readback = appendReadback(
              accepted.finalTexture,
              commandBuffer: acceptedBuffer
          ) else { return result }
    acceptedBuffer.commit()
    acceptedBuffer.waitUntilCompleted()
    result.preparedAndEncoded = acceptedBuffer.status == .completed
        && acceptedBuffer.error == nil
    result.pixelBehavior = matches(
        readback.firstPixel,
        preservesDescriptors ? [0, 255, 0, 255] : [0, 0, 0, 0]
    )
    return result
}

private func failureCode(
    _ result: Result<Executor.PreparedGraph, Executor.Failure>
) -> String {
    switch result {
    case .success: "success"
    case let .failure(failure): failure.rawValue
    }
}

private func variantFailureCode(
    _ result: Result<SceneResolvedMaterialCompiledVariant, SceneResolvedMaterialFailure>
) -> String {
    switch result {
    case .success: return "success"
    case let .failure(failure): return "\(failure.phase.rawValue):\(failure.code.rawValue):\(failure.boundedDetails.joined(separator: ","))"
    }
}

private func intentKinds(
    _ admittedGraph: Executor.PreparedGraph
) -> [String] {
    admittedGraph.stages.flatMap { value in
        value.transition.transaction.intents.map { intent in
            switch intent {
            case .initialize: "initialize"
            case .material: "material"
            case .copy: "copy"
            case .swap: "swap"
            }
        }
    }
}

private func capabilities(
    _ admittedGraph: AdmittedLayerGraph,
    catalog: SceneResolvedMaterialRuntimeCatalog,
    dynamicProducers: Capabilities.DynamicProducerCatalog = .empty,
    dedicatedFullFrameComposeStageKeys: Set<Graph.EffectKey> = []
) -> Capabilities {
    let graph = admittedGraph.renderGraph
    let materialNodes = graph.nodes.filter { $0.kind == .material }
        .sorted { ($0.materialOrdinal ?? -1) < ($1.materialOrdinal ?? -1) }
    let instancePasses = Dictionary(grouping: materialNodes, by: \.effect)
        .mapValues { nodes in
            nodes.map {
                SceneRenderDescriptor.PassDescriptor(
                    passIndex: $0.instancePassIndex!,
                    combos: [:]
                )
            }
        }
    let materialPasses = materialNodes.map {
        SceneRenderDescriptor.MaterialPassDescriptor(
            id: $0.materialPassID!,
            materialPath: $0.materialPath!,
            combos: [:]
        )
    }
    let descriptor = SceneRenderDescriptor(
        layers: [.init(
            id: graph.layerID,
            effects: graph.effects.map {
                .init(
                    id: $0.key.descriptorID,
                    file: $0.definitionPath,
                    visible: true,
                    passes: instancePasses[$0.key] ?? []
                )
            }
        )],
        materialPasses: materialPasses,
        effectDefinitions: graph.effects.map {
            .init(relativePath: $0.definitionPath, functions: nil)
        }
    )
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [graph],
        dedicatedStagePrograms: dedicatedFullFrameComposeStageKeys.isEmpty
            ? [] : admittedGraph.stagePrograms
    )
    return .init(
        admissionCandidates: candidates,
        materialCatalog: catalog,
        dynamicProducers: dynamicProducers,
        dedicatedStageFamilies: Dictionary(
            uniqueKeysWithValues: dedicatedFullFrameComposeStageKeys.map {
                ($0, "fixture-full-frame-compose")
            }
        ),
        dedicatedFullFrameComposeStageKeys: dedicatedFullFrameComposeStageKeys
    )
}

private func compilerCounts(
    _ capability: Capabilities.LayerCapability
) -> (shader: Int, frontend: Int) {
    capability.materials.values.reduce(into: (0, 0)) { result, material in
        let counters = material.variants.counters
        result.0 += counters.shaderPreparationCount
        result.1 += counters.frontendCompilationCount
    }
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let source = makeSource(device)
        let sourcePipeline = makeSourcePipeline(device)

        let pixelGraph = chainedGraph()
        let pixelChain = orderedLayerGraph(pixelGraph)
        let pixelCapabilities = capabilities(
            pixelChain,
            catalog: catalog(for: pixelGraph)
        )
        var chainedStagesPrepared = false
        var chainedStagesEncoded = false
        var chainedStagesGPUCompleted = false
        var chainedStagePixelsPreserved = false
        var chainedMiddleProgramKey: String?
        var pixelChainFailure = "setup"
        let pixelClaim = pixelCapabilities.claim(pixelChain)
        let pixelCapability = pixelClaim.flatMap {
            pixelCapabilities.resolve($0.token, for: pixelChain)
        }
        let pixelLeases = pixelCapability.flatMap {
            makeChainedLeases($0, device: device)
        }
        if let claim = pixelClaim,
           let leases = pixelLeases,
           let executor = Executor(device: device, capabilities: pixelCapabilities),
           let command = queue.makeCommandBuffer() {
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(1),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 1,
                resetGeneration: 1
            )
            pixelChainFailure = failureCode(preparation)
            if case let .success(prepared) = preparation,
               prepared.stages.count == 3,
               prepared.stages.map(\.effect) == [
                    chainedFirstEffect,
                    chainedSecondEffect,
                    chainedThirdEffect,
               ],
               prepared.stages[1].pairStep.inputIdentity
                    == prepared.stages[0].pairStep.outputIdentity,
               prepared.stages[2].pairStep.inputIdentity
                    == prepared.stages[1].pairStep.outputIdentity,
               prepared.stages[0].effectOutputResource.publication.texture
                    === executor.pairTexture(
                        lease: leases[1],
                        member: prepared.stages[1].pairStep.inputMember
                    ),
               prepared.stages[1].effectOutputResource.publication.texture
                    === executor.pairTexture(
                        lease: leases[2],
                        member: prepared.stages[2].pairStep.inputMember
                    ),
               prepared.stages[0].effectOutputResource.publication.texture
                    === prepared.stages[2]
                        .effectOutputResource.publication.texture {
                chainedStagesPrepared = true
                chainedMiddleProgramKey = prepared.stages[1].programCacheKeys.first
                var observedStageIndices: [Int] = []
                var stageReadbacks: [Readback] = []
                chainedStagesEncoded = executor.encode(
                    prepared,
                    commandBuffer: command,
                    stageBoundaryObserver: { stageIndex, transition, buffer in
                        guard let readback = appendReadback(
                            transition.effectOutputResource.publication.texture,
                            commandBuffer: buffer
                        ) else { return false }
                        observedStageIndices.append(stageIndex)
                        stageReadbacks.append(readback)
                        return true
                    }
                )
                if chainedStagesEncoded,
                   let finalRead = appendReadback(
                        prepared.finalTexture,
                        commandBuffer: command
                   ) {
                    command.commit()
                    command.waitUntilCompleted()
                    chainedStagesGPUCompleted = command.status == .completed
                        && command.error == nil
                    let expectedPixels: [[UInt8]] = [
                        [255, 0, 0, 255],
                        [0, 255, 0, 255],
                        [0, 0, 255, 255],
                    ]
                    chainedStagePixelsPreserved = observedStageIndices
                        == [0, 1, 2] && stageReadbacks.count == 3
                        && zip(stageReadbacks, expectedPixels).allSatisfy {
                            matches($0.firstPixel, $1)
                                && matches($0.lastPixel, $1)
                        }
                        && matches(finalRead.firstPixel, expectedPixels[2])
                        && matches(finalRead.lastPixel, expectedPixels[2])
                }
            }
        } else if pixelCapability != nil && pixelLeases == nil {
            pixelChainFailure = "leases"
        }

        let dynamicNode = pixelGraph.nodes[1]
        let dynamicTarget = dynamicUniformTarget(dynamicNode)
        let dynamicDefinition = SceneDynamicTargetDefinition(
            target: dynamicTarget,
            valueType: .scalar,
            authoredValue: .scalar(1)
        )
        let dynamicPixelCapabilities = capabilities(
            pixelChain,
            catalog: catalog(for: pixelGraph, dynamicUniformNodes: [1]),
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [dynamicTarget],
                sceneScriptTargets: []
            )
        )
        let dynamicPixelClaim = dynamicPixelCapabilities.claim(pixelChain)
        let dynamicPixelCapability = dynamicPixelClaim.flatMap {
            dynamicPixelCapabilities.resolve($0.token, for: pixelChain)
        }
        let staticPixelCapabilities = capabilities(
            pixelChain,
            catalog: catalog(
                for: pixelGraph,
                staticUniformMissingDefaultNodes: [1]
            )
        )
        let staticPixelClaim = staticPixelCapabilities.claim(pixelChain)
        let staticPixelCapability = staticPixelClaim.flatMap {
            staticPixelCapabilities.resolve($0.token, for: pixelChain)
        }
        var dynamicUniformValidFramePrepares = false
        if let claim = dynamicPixelClaim,
           let capability = dynamicPixelCapability,
           let leases = makeChainedLeases(capability, device: device, generation: 20),
           let executor = Executor(
               device: device,
               capabilities: dynamicPixelCapabilities
           ), let command = queue.makeCommandBuffer() {
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(
                    4,
                    dynamicDefinitions: [dynamicDefinition],
                    timelineValues: [dynamicTarget: .scalar(1)]
                ),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 4,
                resetGeneration: 4
            )
            if case let .success(prepared) = preparation {
                dynamicUniformValidFramePrepares = prepared.stages.count == 3
                    && prepared.stages[1].effectLocalFailureReasonCode == nil
                    && prepared.stages[1].programCacheKeys.allSatisfy {
                        !$0.hasPrefix("visual-failure-passthrough:")
                    }
            }
        }

        var dynamicUniformFailurePassthroughPrepared = false
        var dynamicUniformFailurePassthroughEncoded = false
        var dynamicUniformFailurePassthroughGPUCompleted = false
        var dynamicUniformFailurePreservesPreviousAndContinuesSuffix = false
        if let claim = dynamicPixelClaim,
           let capability = dynamicPixelCapability,
           let leases = makeChainedLeases(capability, device: device, generation: 21),
           let executor = Executor(
               device: device,
               capabilities: dynamicPixelCapabilities
           ), let command = queue.makeCommandBuffer() {
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(5),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 5,
                resetGeneration: 5
            )
            if case let .success(prepared) = preparation,
               prepared.stages.count == 3,
               prepared.stages[1].programCacheKeys == [
                   "visual-failure-passthrough:"
                       + "material-finalizer-dynamic-uniform-binding"
               ], prepared.stages[1].effectLocalFailureReasonCode
                    == "material-finalizer-dynamic-uniform-binding" {
                dynamicUniformFailurePassthroughPrepared = true
                var observedStageIndices: [Int] = []
                var stageReadbacks: [Readback] = []
                dynamicUniformFailurePassthroughEncoded = executor.encode(
                    prepared,
                    commandBuffer: command,
                    stageBoundaryObserver: { stageIndex, transition, buffer in
                        guard let readback = appendReadback(
                            transition.effectOutputResource.publication.texture,
                            commandBuffer: buffer
                        ) else { return false }
                        observedStageIndices.append(stageIndex)
                        stageReadbacks.append(readback)
                        return true
                    }
                )
                if dynamicUniformFailurePassthroughEncoded,
                   let finalReadback = appendReadback(
                       prepared.finalTexture,
                       commandBuffer: command
                   ) {
                    command.commit()
                    command.waitUntilCompleted()
                    dynamicUniformFailurePassthroughGPUCompleted =
                        command.status == .completed && command.error == nil
                    let expectedPixels: [[UInt8]] = [
                        [255, 0, 0, 255],
                        [255, 0, 0, 255],
                        [0, 255, 0, 255],
                    ]
                    dynamicUniformFailurePreservesPreviousAndContinuesSuffix =
                        observedStageIndices == [0, 1, 2]
                        && stageReadbacks.count == 3
                        && zip(stageReadbacks, expectedPixels).allSatisfy {
                            matches($0.firstPixel, $1)
                                && matches($0.lastPixel, $1)
                        }
                        && matches(finalReadback.firstPixel, expectedPixels[2])
                        && matches(finalReadback.lastPixel, expectedPixels[2])
                }
            }
        }

        var staticUniformFailurePassthroughPrepared = false
        var staticUniformFailurePassthroughEncoded = false
        var staticUniformFailurePassthroughGPUCompleted = false
        var staticUniformFailurePreservesPreviousAndContinuesSuffix = false
        if let claim = staticPixelClaim,
           let capability = staticPixelCapability,
           let leases = makeChainedLeases(capability, device: device, generation: 23),
           let executor = Executor(
               device: device,
               capabilities: staticPixelCapabilities
           ), let command = queue.makeCommandBuffer() {
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(7),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 7,
                resetGeneration: 7
            )
            if case let .success(prepared) = preparation,
               prepared.stages.count == 3,
               prepared.stages[1].programCacheKeys == [
                   "visual-failure-passthrough:"
                       + "material-finalizer-static-uniform-binding"
               ], prepared.stages[1].effectLocalFailureReasonCode
                    == "material-finalizer-static-uniform-binding" {
                staticUniformFailurePassthroughPrepared = true
                var observedStageIndices: [Int] = []
                var stageReadbacks: [Readback] = []
                staticUniformFailurePassthroughEncoded = executor.encode(
                    prepared,
                    commandBuffer: command,
                    stageBoundaryObserver: { stageIndex, transition, buffer in
                        guard let readback = appendReadback(
                            transition.effectOutputResource.publication.texture,
                            commandBuffer: buffer
                        ) else { return false }
                        observedStageIndices.append(stageIndex)
                        stageReadbacks.append(readback)
                        return true
                    }
                )
                if staticUniformFailurePassthroughEncoded,
                   let finalReadback = appendReadback(
                       prepared.finalTexture,
                       commandBuffer: command
                   ) {
                    command.commit()
                    command.waitUntilCompleted()
                    staticUniformFailurePassthroughGPUCompleted =
                        command.status == .completed && command.error == nil
                    let expectedPixels: [[UInt8]] = [
                        [255, 0, 0, 255],
                        [255, 0, 0, 255],
                        [0, 255, 0, 255],
                    ]
                    staticUniformFailurePreservesPreviousAndContinuesSuffix =
                        observedStageIndices == [0, 1, 2]
                        && stageReadbacks.count == 3
                        && zip(stageReadbacks, expectedPixels).allSatisfy {
                            matches($0.firstPixel, $1)
                                && matches($0.lastPixel, $1)
                        }
                        && matches(finalReadback.firstPixel, expectedPixels[2])
                        && matches(finalReadback.lastPixel, expectedPixels[2])
                }
            }
        }

        var rendererFailurePassthroughPrepared = false
        var rendererFailurePassthroughEncoded = false
        var rendererFailurePassthroughGPUCompleted = false
        var rendererFailurePreservesPreviousAndContinuesSuffix = false
        if let claim = pixelClaim,
           let capability = pixelCapability,
           let failedKey = chainedMiddleProgramKey,
           let leases = makeChainedLeases(capability, device: device, generation: 19),
           let executor = Executor(device: device, capabilities: pixelCapabilities),
           let command = queue.makeCommandBuffer() {
            executor.materialEncoder.installTestingPreparationFailure(
                .libraryCompilationRejected(diagnostic: "fixture"),
                preparedKey: failedKey
            )
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(3),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 3,
                resetGeneration: 3
            )
            if case let .success(prepared) = preparation,
               prepared.stages.count == 3,
               prepared.stages[1].programCacheKeys == [
                    "visual-failure-passthrough:"
                        + "material-pass-preparation-library-compilation"
               ],
               prepared.stages[1].effectLocalFailureReasonCode
                    == "material-pass-preparation-library-compilation" {
                rendererFailurePassthroughPrepared = true
                var observedStageIndices: [Int] = []
                var stageReadbacks: [Readback] = []
                rendererFailurePassthroughEncoded = executor.encode(
                    prepared,
                    commandBuffer: command,
                    stageBoundaryObserver: { stageIndex, transition, buffer in
                        guard let readback = appendReadback(
                            transition.effectOutputResource.publication.texture,
                            commandBuffer: buffer
                        ) else { return false }
                        observedStageIndices.append(stageIndex)
                        stageReadbacks.append(readback)
                        return true
                    }
                )
                if rendererFailurePassthroughEncoded,
                   let finalReadback = appendReadback(
                       prepared.finalTexture,
                       commandBuffer: command
                   ) {
                    command.commit()
                    command.waitUntilCompleted()
                    rendererFailurePassthroughGPUCompleted =
                        command.status == .completed && command.error == nil
                    let expectedPixels: [[UInt8]] = [
                        [255, 0, 0, 255],
                        [255, 0, 0, 255],
                        [0, 255, 0, 255],
                    ]
                    rendererFailurePreservesPreviousAndContinuesSuffix =
                        observedStageIndices == [0, 1, 2]
                        && stageReadbacks.count == 3
                        && zip(stageReadbacks, expectedPixels).allSatisfy {
                            matches($0.firstPixel, $1)
                                && matches($0.lastPixel, $1)
                        }
                        && matches(finalReadback.firstPixel, expectedPixels[2])
                        && matches(finalReadback.lastPixel, expectedPixels[2])
                }
            }
        }

        let passthroughCapabilities = capabilities(
            pixelChain,
            catalog: catalog(
                for: pixelGraph,
                uniformSchemaInvalidNodes: [1]
            )
        )
        var visualFailureCanClaimEffectLocalPassthrough = false
        var visualFailurePassthroughPrepared = false
        var visualFailurePassthroughEncoded = false
        var visualFailurePassthroughGPUCompleted = false
        var visualFailurePreservesPreviousAndContinuesSuffix = false
        var visualFailurePassthroughIsTypedAndCounted = false
        var visualFailureObservedPixels: [[UInt8]] = []
        let passthroughClaim = passthroughCapabilities.claim(pixelChain)
        let passthroughCapability = passthroughClaim.flatMap {
            passthroughCapabilities.resolve($0.token, for: pixelChain)
        }
        visualFailureCanClaimEffectLocalPassthrough = passthroughClaim != nil
            && passthroughCapability?.stages.count == 3
            && passthroughCapability?.stages[1].visualFailureReasonCode
                == "material-variant-envelope-uniform-schema"
        visualFailurePassthroughIsTypedAndCounted =
            passthroughCapabilities.reportLines.contains {
                $0 == "resolved material execution capability fallback:"
                    + " state=prefer-generic outcome=effect-local-passthrough"
                    + " reason=material-variant-envelope-uniform-schema count=1"
            }
        let passthroughLeases = passthroughCapability.flatMap {
            makeChainedLeases($0, device: device, generation: 18)
        }
        if let claim = passthroughClaim,
           let leases = passthroughLeases,
           let executor = Executor(
               device: device,
               capabilities: passthroughCapabilities
           ),
           let command = queue.makeCommandBuffer() {
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(2),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 2,
                resetGeneration: 2
            )
            if case let .success(prepared) = preparation,
               prepared.stages.count == 3,
               prepared.stages[1].programCacheKeys == [
                   "visual-failure-passthrough:"
                       + "material-variant-envelope-uniform-schema"
               ] {
                visualFailurePassthroughPrepared = true
                var observedStageIndices: [Int] = []
                var stageReadbacks: [Readback] = []
                visualFailurePassthroughEncoded = executor.encode(
                    prepared,
                    commandBuffer: command,
                    stageBoundaryObserver: { stageIndex, transition, buffer in
                        guard let readback = appendReadback(
                            transition.effectOutputResource.publication.texture,
                            commandBuffer: buffer
                        ) else { return false }
                        observedStageIndices.append(stageIndex)
                        stageReadbacks.append(readback)
                        return true
                    }
                )
                if visualFailurePassthroughEncoded,
                   let finalReadback = appendReadback(
                       prepared.finalTexture,
                       commandBuffer: command
                   ) {
                    command.commit()
                    command.waitUntilCompleted()
                    visualFailurePassthroughGPUCompleted =
                        command.status == .completed && command.error == nil
                    let expectedPixels: [[UInt8]] = [
                        [255, 0, 0, 255],
                        [255, 0, 0, 255],
                        [0, 255, 0, 255],
                    ]
                    visualFailureObservedPixels = stageReadbacks.map(\.firstPixel)
                        + [finalReadback.firstPixel]
                    visualFailurePreservesPreviousAndContinuesSuffix =
                        observedStageIndices == [0, 1, 2]
                        && stageReadbacks.count == 3
                        && zip(stageReadbacks, expectedPixels).allSatisfy {
                            matches($0.firstPixel, $1)
                                && matches($0.lastPixel, $1)
                        }
                        && matches(finalReadback.firstPixel, expectedPixels[2])
                        && matches(finalReadback.lastPixel, expectedPixels[2])
                }
            }
        }

        let ordinaryGraph = graph(
            targets: [rawTarget(first)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let ordinaryChain = admittedGraph(ordinaryGraph)
        let ordinaryCatalog = catalog(for: ordinaryGraph)
        let ordinaryCapabilities = capabilities(
            ordinaryChain,
            catalog: ordinaryCatalog
        )
        let uniformSchemaMultiNodeCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(
                for: ordinaryGraph,
                uniformSchemaInvalidNodes: [0]
            )
        )
        let ordinaryClaim = ordinaryCapabilities.claim(ordinaryChain)!
        let ordinaryExecutor = Executor(
            device: device,
            capabilities: ordinaryCapabilities
        )!
        let ordinaryWarmupReport = ordinaryExecutor.pipelineWarmupReport
        let ordinaryAttemptsAfterWarmup = ordinaryExecutor.materialEncoder
            .pipelineCompilationAttemptCount
        let ordinaryPlan = requirePlan(ordinaryGraph)
        let ordinaryLease = makeLease(ordinaryPlan, device: device)
        let dynamicMultiTarget = dynamicUniformTarget(ordinaryGraph.nodes[0])
        let dynamicMultiCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(for: ordinaryGraph, dynamicUniformNodes: [0]),
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [dynamicMultiTarget],
                sceneScriptTargets: []
            )
        )
        let staticUniformMultiNodeCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(
                for: ordinaryGraph,
                staticUniformMissingDefaultNodes: [0]
            )
        )
        var dynamicUniformMultiNodeRemainsHardRejected = false
        var dynamicUniformMultiNodeFailure = "not-claimed"
        if let claim = dynamicMultiCapabilities.claim(ordinaryChain),
           let executor = Executor(
               device: device,
               capabilities: dynamicMultiCapabilities
           ), let command = queue.makeCommandBuffer() {
            let failure = failureCode(executor.prepare(
                token: claim.token,
                leases: [makeLease(ordinaryPlan, device: device, generation: 22)],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(6),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 6,
                resetGeneration: 6
            ))
            dynamicUniformMultiNodeFailure = failure
            dynamicUniformMultiNodeRemainsHardRejected = failure.contains(
                "finalizer-uniform-dynamicUniformBindingInvalid"
            )
        }
        var staticUniformMultiNodeRemainsHardRejected = false
        var staticUniformMultiNodeFailure = "not-claimed"
        if let claim = staticUniformMultiNodeCapabilities.claim(ordinaryChain),
           let executor = Executor(
               device: device,
               capabilities: staticUniformMultiNodeCapabilities
           ), let command = queue.makeCommandBuffer() {
            let failure = failureCode(executor.prepare(
                token: claim.token,
                leases: [makeLease(ordinaryPlan, device: device, generation: 24)],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(8),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 8,
                resetGeneration: 8
            ))
            staticUniformMultiNodeFailure = failure
            staticUniformMultiNodeRemainsHardRejected = failure.contains(
                "finalizer-uniform-staticUniformBindingInvalid"
            )
        }

        let scalarGraph = graph(
            targets: [rawTarget(first, format: "r8")],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let scalarChain = admittedGraph(scalarGraph)
        let scalarCapabilities = capabilities(
            scalarChain,
            catalog: catalog(
                for: scalarGraph,
                scalarConsumerNodes: [1: "red"]
            )
        )
        guard let scalarClaim = scalarCapabilities.claim(scalarChain) else {
            fatalError("scalar capability rejected: \(scalarCapabilities.reportLines)")
        }
        let scalarExecutor = Executor(
            device: device,
            capabilities: scalarCapabilities
        )!
        let scalarLease = makeLease(requirePlan(scalarGraph), device: device)
        guard let scalarTarget = scalarLease.texture(for: first),
              fill(
                  scalarTarget,
                  color: MTLClearColorMake(1, 0, 0, 1),
                  queue: queue
              ), let scalarPreparationBuffer = queue.makeCommandBuffer() else {
            fatalError("scalar preparation setup failed")
        }
        let scalarSource = makeSource(
            device,
            bgra: [191, 128, 64, 255]
        )
        let scalarPreparation = scalarExecutor.prepare(
            token: scalarClaim.token,
            leases: [scalarLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(0),
            sourceTexture: scalarSource,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: scalarPreparationBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        guard case let .success(scalarPrepared) = scalarPreparation,
              let scalarPrepareRead = appendScalarReadback(
                  scalarTarget,
                  commandBuffer: scalarPreparationBuffer
              ) else {
            fatalError("scalar preparation failed: \(failureCode(scalarPreparation))")
        }
        scalarPreparationBuffer.commit()
        scalarPreparationBuffer.waitUntilCompleted()
        let scalarPrepareHasNoWrite = scalarPreparationBuffer.status == .completed
            && scalarPrepareRead.first == 255
            && scalarPrepareRead.last == 255
        let scalarStage = scalarPrepared.stages[0]
        let scalarPublication = scalarStage.frameResources[first]
        let scalarPublicationContract = scalarPrepared.stages.count == 1
            && scalarStage.programCacheKeys.count == 2
            && intentKinds(scalarPrepared) == ["material", "material"]
            && scalarPublication?.publication.requestIdentity == .graph(first)
            && scalarPublication?.publication.candidate.content == .scalarRedUnorm
            && scalarPublication?.publication.candidate.purpose == .preservedChannels
            && scalarPublication?.publication.candidate.pixelFormat == .r8Unorm
            && scalarPublication?.publication.candidate.authoredFormat == nil
            && scalarPublication?.publication.candidate.sampling == .directImageFallback
            && scalarPrepared.finalResource.publication.candidate.content
                != .scalarRedUnorm
        guard let scalarEncodeBuffer = queue.makeCommandBuffer() else {
            fatalError("scalar encode buffer unavailable")
        }
        let scalarEncoded = scalarExecutor.encode(
            scalarPrepared,
            commandBuffer: scalarEncodeBuffer
        )
        guard let scalarStorageRead = appendScalarReadback(
                  scalarTarget,
                  commandBuffer: scalarEncodeBuffer
              ), let scalarFinalRead = appendReadback(
                  scalarPrepared.finalTexture,
                  commandBuffer: scalarEncodeBuffer
              ) else { fatalError("scalar readback unavailable") }
        scalarEncodeBuffer.commit()
        scalarEncodeBuffer.waitUntilCompleted()
        let scalarGPUCompleted = scalarEncoded
            && scalarEncodeBuffer.status == .completed
            && scalarEncodeBuffer.error == nil
        let scalarRedStored = abs(Int(scalarStorageRead.first) - 64) <= 2
            && abs(Int(scalarStorageRead.last) - 64) <= 2
        let scalarTerminalMatches = matches(
            scalarFinalRead.firstPixel,
            [0, 0, 64, 255]
        ) && matches(scalarFinalRead.lastPixel, [0, 0, 64, 255])
        func scalarRejection(
            _ candidateGraph: Graph,
            consumers: [Int: String] = [:],
            expectedCode: String = "r8-scalar-graph-unproven"
        ) -> Bool {
            let chain = admittedGraph(candidateGraph)
            let candidateCapabilities = capabilities(
                chain,
                catalog: catalog(
                    for: candidateGraph,
                    scalarConsumerNodes: consumers
                )
            )
            return candidateCapabilities.claim(chain) == nil
                && candidateCapabilities.reportLines.contains {
                    $0.contains("rejection: \(expectedCode) count=1")
                }
        }
        func scalarConsumerGraph() -> Graph {
            graph(
                targets: [rawTarget(first, format: "r8")],
                nodes: [
                    material(0, ordinal: 0, target: first, read: input),
                    material(1, ordinal: 1, target: output, read: first),
                ]
            )
        }
        let scalarGreenGraph = scalarConsumerGraph()
        let scalarWholeGraph = scalarConsumerGraph()
        let scalarAliasGraph = scalarConsumerGraph()
        let scalarClearGraph = graph(
            targets: [rawTarget(
                first,
                format: "r8",
                clear: .string("0 0 0 0")
            )],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let scalarUniqueGraph = graph(
            targets: [rawTarget(first, format: "r8", unique: true)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let scalarNoConsumerGraph = graph(
            targets: [rawTarget(first, format: "r8")],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: input),
            ]
        )
        let scalarMultipleWriterGraph = graph(
            targets: [rawTarget(first, format: "r8")],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: first, read: input),
                material(2, ordinal: 2, target: output, read: first),
            ]
        )
        let scalarCopyGraph = graph(
            targets: [
                rawTarget(first, format: "r8"),
                rawTarget(second, format: "r8"),
            ],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                command(1, kind: .copy, source: first, target: second),
                material(2, ordinal: 1, target: output, read: second),
            ]
        )
        let scalarSwapGraph = graph(
            targets: [
                rawTarget(first, format: "r8", unique: true),
                rawTarget(second, format: "r8", unique: true),
            ],
            nodes: [
                material(0, ordinal: 0, target: second, read: first),
                command(1, kind: .swap, source: first, target: second),
                material(2, ordinal: 1, target: output, read: first),
            ]
        )
        let scalarRepeatGraph = graph(
            targets: [rawTarget(
                first,
                format: "r8",
                uvs: .string("repeat")
            )],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )

        let implicitFramebufferGraph = graph(
            targets: [],
            nodes: [
                implicitFramebufferMaterial(0, ordinal: 0, target: output),
            ]
        )
        let implicitFramebufferChain = admittedGraph(implicitFramebufferGraph)
        let implicitFramebufferCapabilities = capabilities(
            implicitFramebufferChain,
            catalog: catalog(
                for: implicitFramebufferGraph,
                implicitFramebufferNodes: [0]
            )
        )
        let implicitFramebufferClaim = implicitFramebufferCapabilities.claim(
            implicitFramebufferChain
        )!
        let implicitFramebufferExecutor = Executor(
            device: device,
            capabilities: implicitFramebufferCapabilities
        )!
        let implicitFramebufferLease = makeLease(
            requireR4Plan(implicitFramebufferGraph),
            device: device
        )
        guard let implicitFramebufferBuffer = queue.makeCommandBuffer() else {
            fatalError("implicit framebuffer buffer unavailable")
        }
        let implicitFramebufferPreparation = implicitFramebufferExecutor.prepare(
            token: implicitFramebufferClaim.token,
            leases: [implicitFramebufferLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(0),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: implicitFramebufferBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )

        let historicalFramebufferCapabilities = capabilities(
            implicitFramebufferChain,
            catalog: catalog(
                for: implicitFramebufferGraph,
                implicitFramebufferNodes: [0],
                historicalFramebufferNodes: [0]
            )
        )
        let historicalFramebufferClaim = historicalFramebufferCapabilities.claim(
            implicitFramebufferChain
        )!
        let historicalFramebufferExecutor = Executor(
            device: device,
            capabilities: historicalFramebufferCapabilities
        )!
        let historicalFramebufferLease = makeLease(
            requireR4Plan(implicitFramebufferGraph),
            device: device
        )
        guard let historicalFramebufferBuffer = queue.makeCommandBuffer() else {
            fatalError("historical framebuffer buffer unavailable")
        }
        let historicalFramebufferPreparation = historicalFramebufferExecutor.prepare(
            token: historicalFramebufferClaim.token,
            leases: [historicalFramebufferLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(0),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: historicalFramebufferBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        var historicalFramebufferPublication = false
        var historicalFramebufferEncoded = false
        if case let .success(prepared) = historicalFramebufferPreparation {
            historicalFramebufferPublication = prepared.stages.count == 1
                && prepared.stages[0].effectOutputResource.publication.requestIdentity
                    == .graph(output)
                && prepared.stages[0].programCacheKeys.count == 1
            historicalFramebufferEncoded = historicalFramebufferExecutor.encode(
                prepared,
                commandBuffer: historicalFramebufferBuffer
            )
            guard let readback = appendReadback(
                prepared.finalTexture,
                commandBuffer: historicalFramebufferBuffer
            ) else { fatalError("historical framebuffer readback unavailable") }
            historicalFramebufferBuffer.commit()
            historicalFramebufferBuffer.waitUntilCompleted()
            historicalFramebufferEncoded = historicalFramebufferEncoded
                && historicalFramebufferBuffer.status == .completed
                && historicalFramebufferBuffer.error == nil
                && matches(readback.firstPixel, [0, 0, 255, 255])
        }

        guard let unreadableCaptureBuffer = queue.makeCommandBuffer() else {
            fatalError("unreadable source capture buffer unavailable")
        }
        let unreadableCapturePreparation = ordinaryExecutor.prepare(
            token: ordinaryClaim.token,
            leases: [ordinaryLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(0),
            sourceTexture: makeSource(device, usage: .renderTarget),
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: unreadableCaptureBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )

        let conditionGraph = graph(
            targets: [rawTarget(first)],
            nodes: [
                material(
                    0,
                    ordinal: 0,
                    target: first,
                    read: input,
                    conditions: .bool(true)
                ),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let composeGraph = graph(
            targets: [rawTarget(first)],
            nodes: [
                material(
                    0,
                    ordinal: 0,
                    target: first,
                    read: input,
                    compose: .bool(true)
                ),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let admittedComposeGraph = graph(
            targets: [],
            nodes: [
                fullFrameComposeMaterial(
                    0,
                    ordinal: 0,
                    compose: .bool(true)
                ),
                fullFrameComposeMaterial(1, ordinal: 1, compose: nil),
            ]
        )
        let admittedComposeChain = admittedGraph(admittedComposeGraph)
        let admittedComposeCapabilities = capabilities(
            admittedComposeChain,
            catalog: catalog(
                for: admittedComposeGraph,
                demandIssueNodes: [0, 1],
                implicitFramebufferNodes: [0, 1]
            ),
            dedicatedFullFrameComposeStageKeys: [effect]
        )
        let admittedComposeClaim = admittedComposeCapabilities.claim(
            admittedComposeChain
        )!
        let admittedComposeCapability = admittedComposeCapabilities.resolve(
            admittedComposeClaim.token,
            for: admittedComposeChain
        )!
        let admittedComposeExecutor = Executor(
            device: device,
            capabilities: admittedComposeCapabilities
        )!
        let admittedComposeLease = makeChainedLeases(
            admittedComposeCapability,
            device: device
        )!.first!
        let inactiveComposeGraph = graph(
            targets: [rawTarget(first)],
            nodes: [
                material(
                    0,
                    ordinal: 0,
                    target: first,
                    read: input,
                    compose: .bool(false)
                ),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let repeatTargetGraph = graph(
            targets: [rawTarget(first, uvs: .string("repeat"))],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let nonzeroClearGraph = graph(
            targets: [rawTarget(first, clear: .string("1 0 0 0"))],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let passCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(for: ordinaryGraph, passNodes: [1])
        )
        let missingCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(for: ordinaryGraph, omittedNodes: [1])
        )
        let nonOverwriteCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(for: ordinaryGraph, nonOverwriteNodes: [1])
        )
        let demandIssueCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(for: ordinaryGraph, demandIssueNodes: [1])
        )
        let internalDefaultCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(for: ordinaryGraph, internalDefaultNodes: [1])
        )
        let repeatTargetCapabilities = capabilities(
            admittedGraph(repeatTargetGraph),
            catalog: catalog(for: repeatTargetGraph)
        )
        let nonzeroClearCapabilities = capabilities(
            admittedGraph(nonzeroClearGraph),
            catalog: catalog(for: nonzeroClearGraph)
        )
        let oversizedNodeGraph = graph(
            targets: [],
            nodes: (0 ... Executor.State.maximumNodeCount).map { index in
                material(
                    index,
                    ordinal: index,
                    target: output,
                    read: input
                )
            }
        )
        let oversizedLogicalTargets = (
            0 ... Executor.State.maximumLogicalBindingCount - 2
        ).map { index in
            Graph.TextureIdentity(
                kind: .framebuffer,
                layerID: layerID,
                effect: effect,
                name: "oversized-\(index)"
            )
        }
        let oversizedLogicalGraph = graph(
            targets: oversizedLogicalTargets.map { rawTarget($0) },
            nodes: [material(0, ordinal: 0, target: output, read: input)]
        )

        guard clear(ordinaryLease, queue: queue),
              let preparationBuffer = queue.makeCommandBuffer() else {
            fatalError("ordinary preparation setup failed")
        }
        let preparation = ordinaryExecutor.prepare(
            token: ordinaryClaim.token,
            leases: [ordinaryLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(1),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: preparationBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        guard case let .success(prepared) = preparation,
              let firstTexture = ordinaryLease.texture(for: first),
              let outputTexture = ordinaryLease.texture(for: output),
              let prepareFirstRead = appendReadback(
                  firstTexture,
                  commandBuffer: preparationBuffer
              ),
              let prepareOutputRead = appendReadback(
                  outputTexture,
                  commandBuffer: preparationBuffer
              ) else {
            fatalError("ordinary preparation failed: \(failureCode(preparation))")
        }
        let ordinaryCapability = ordinaryCapabilities.resolve(
            ordinaryClaim.token,
            for: ordinaryChain
        )!
        let ordinaryAttemptsAfterFirstPreparation = ordinaryExecutor.materialEncoder
            .pipelineCompilationAttemptCount
        let ordinaryWarmupHitsAfterFirstPreparation = ordinaryExecutor.materialEncoder
            .launchWarmupHitCount
        let compilerCountsAfterFirst = compilerCounts(ordinaryCapability)
        preparationBuffer.commit()
        preparationBuffer.waitUntilCompleted()
        let prepareHasNoEncodingSideEffect = preparationBuffer.status == .completed
            && matches(prepareFirstRead.firstPixel, [255, 0, 0, 255])
            && matches(prepareOutputRead.firstPixel, [255, 0, 0, 255])

        let lateCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(for: ordinaryGraph, nonOverwriteNodes: [1])
        )
        let lateExecutor = Executor(
            device: device,
            capabilities: lateCapabilities
        )!
        guard let lateBuffer = queue.makeCommandBuffer() else {
            fatalError("late failure buffer unavailable")
        }
        let latePreparation = lateExecutor.prepare(
            token: ordinaryClaim.token,
            leases: [ordinaryLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(1),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: lateBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        guard let lateFirstRead = appendReadback(
                  firstTexture,
                  commandBuffer: lateBuffer
              ),
              let lateOutputRead = appendReadback(
                  outputTexture,
                  commandBuffer: lateBuffer
              ) else {
            fatalError("late readback unavailable")
        }
        lateBuffer.commit()
        lateBuffer.waitUntilCompleted()
        let staticClaimRejectionHasNoPartialWrite = failureCode(latePreparation)
                == Executor.Failure.invalidClaim.rawValue
            && matches(lateFirstRead.firstPixel, [255, 0, 0, 255])
            && matches(lateOutputRead.firstPixel, [255, 0, 0, 255])

        guard let encodeBuffer = queue.makeCommandBuffer() else {
            fatalError("encode buffer unavailable")
        }
        let encoded = ordinaryExecutor.encode(
            prepared,
            commandBuffer: encodeBuffer
        )
        guard let encodedRead = appendReadback(
            prepared.finalTexture,
            commandBuffer: encodeBuffer
        ) else { fatalError("encoded readback unavailable") }
        encodeBuffer.commit()
        encodeBuffer.waitUntilCompleted()
        let encodedOutputReadable = encoded
            && encodeBuffer.status == .completed
            && encodeBuffer.error == nil
            && matches(encodedRead.firstPixel, [0, 0, 255, 255])
        let sourceCaptureCoversFullTarget = encodedOutputReadable
            && matches(encodedRead.lastPixel, [0, 0, 255, 255])

        guard let composeBuffer = queue.makeCommandBuffer() else {
            fatalError("compose buffer unavailable")
        }
        let composePreparation = admittedComposeExecutor.prepare(
            token: admittedComposeClaim.token,
            leases: [admittedComposeLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(2),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: composeBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        let composeAppended: Bool
        var composePublicationContract = false
        var composeReadback: Readback?
        if case let .success(value) = composePreparation {
            let stage = value.stages[0]
            let firstPairNode = stage.pairStep.nodes[0]
            let secondPairNode = stage.pairStep.nodes[1]
            composePublicationContract = value.stages.count == 1
                && stage.programCacheKeys.count == 1
                && stage.programCacheKeys[0].hasPrefix("dedicated:")
                && stage.persistentResources.isEmpty
                && intentKinds(value) == ["material", "material"]
                && admittedComposeLease.table.plan.logicalTargets.isEmpty
                && admittedComposeLease.table.inputOutputAliased
                && admittedComposeLease.table.inputTexture
                    === admittedComposeLease.table.outputTexture
                && admittedComposeLease.table.fullFramePair.first
                    !== admittedComposeLease.table.fullFramePair.second
                && stage.pairStep.nodes.count == 2
                && stage.pairStep.fullFrameOutputWriteCount == 2
                && firstPairNode.currentMemberBeforeNode == .zero
                && firstPairNode.fullFrameWriteMember == .one
                && firstPairNode.rotatesAfterNode
                && firstPairNode.currentMemberAfterNode == .one
                && secondPairNode.currentMemberBeforeNode == .one
                && secondPairNode.fullFrameWriteMember == .zero
                && !secondPairNode.rotatesAfterNode
                && secondPairNode.currentMemberAfterNode == .one
                && stage.effectOutputResource.resourceGeneration == 3
                && stage.effectOutputResource.publication.requestIdentity
                    == .graph(output)
                && stage.effectOutputResource.publication.texture
                    === admittedComposeLease.table.outputTexture
                && value.finalResource.publication.isSameAtom(
                    as: stage.effectOutputResource.publication
                )
            composeAppended = admittedComposeExecutor.encode(
                value,
                commandBuffer: composeBuffer
            )
                && value.stages[0].pairStep.composeTransitionCount == 1
                && value.stages[0].pairStep.inputMember == .zero
                && value.stages[0].pairStep.outputMember == .zero
                && value.finalTexture
                    === admittedComposeLease.table.fullFramePair.first
            composeReadback = appendReadback(
                value.finalTexture,
                commandBuffer: composeBuffer
            )
        } else {
            composeAppended = false
        }
        composeBuffer.commit()
        composeBuffer.waitUntilCompleted()
        let composeEncoded = composeAppended
            && composeBuffer.status == .completed && composeBuffer.error == nil
        let composePixelsPreserved = composeReadback.map {
            matches($0.firstPixel, [0, 0, 255, 255])
                && matches($0.lastPixel, [0, 0, 255, 255])
        } ?? false

        guard let secondFrameBuffer = queue.makeCommandBuffer() else {
            fatalError("second frame buffer unavailable")
        }
        let firstTransition = prepared.stages[0]
        let secondFrame = ordinaryExecutor.prepare(
            token: ordinaryClaim.token,
            leases: [ordinaryLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(2),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: secondFrameBuffer,
            previousStates: [effect: firstTransition.transition.nextState],
            previousGraphResources: [effect: firstTransition.persistentResources],
            effectGeneration: 1,
            resetGeneration: 1
        )
        let compilerCountsAfterSecond = compilerCounts(ordinaryCapability)

        let cacheTemplate = template(for: ordinaryGraph.nodes[0])
        let boundedCache = SceneResolvedMaterialVariantCache(
            template: cacheTemplate,
            maximumVariantCount: 1
        )!
        var readyResources = prepared.stages[0].frameResources
        readyResources[input] = prepared.stages[0].effectOutputResource
            .rewrappedForGraphIdentity(input)!
        let readyVariantFrame = frame(3).overlayingGraphResources(readyResources)!
        let readyVariant = boundedCache.resolve(
            readyVariantFrame.finalizationInput(
                template: cacheTemplate,
                renderSize: CGSize(width: extent.width, height: extent.height),
                modelViewProjection: Executor.fullTargetMVP(firstTexture),
                layerModelMatrix: matrix_identity_float4x4,
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4
            )
        )
        let absentVariantFrame: SceneResolvedMaterialFrameSnapshot = {
            let result = SceneResolvedMaterialFrameSnapshot.validated(
                textureSnapshot: .init(
                    frameEpoch: 4,
                    frameIndex: 4,
                    entries: [.graph(input): .absent]
                ),
                dynamicSnapshot: .empty(frameIndex: 4),
                frameInputs: .init(
                    frameIndex: 4,
                    screenSize: CGSize(width: extent.width, height: extent.height),
                    sceneTime: 4,
                    dayTime: 0,
                    frameTime: 1 / 60,
                    pointerCurrentNDC: .zero,
                    pointerPreviousNDC: .zero
                )
            )
            guard case let .success(value) = result else {
                fatalError("absent variant frame failed")
            }
            return value
        }()
        let overflowVariant = boundedCache.resolve(
            absentVariantFrame.finalizationInput(
                template: cacheTemplate,
                renderSize: CGSize(width: extent.width, height: extent.height),
                modelViewProjection: Executor.fullTargetMVP(firstTexture),
                layerModelMatrix: matrix_identity_float4x4,
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4
            )
        )
        let overflowRejected: Bool
        if case let .failure(failure) = overflowVariant {
            overflowRejected = failure.boundedDetails == ["variant-cache-capacity"]
                && boundedCache.counters.capacityRejectionCount == 1
        } else {
            overflowRejected = false
        }

        let failingCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(
                for: ordinaryGraph,
                frontendInvalidNodes: [0]
            )
        )
        let failingTemplate = template(
            for: ordinaryGraph.nodes[0],
            frontendInvalid: true
        )
        let failingVariantCache = SceneResolvedMaterialVariantCache(
            template: failingTemplate,
            maximumVariantCount: 1
        )!
        let failingInput = readyVariantFrame.finalizationInput(
            template: failingTemplate,
            renderSize: CGSize(width: extent.width, height: extent.height),
            modelViewProjection: Executor.fullTargetMVP(firstTexture),
            layerModelMatrix: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4
        )
        let firstFailedVariant = failingVariantCache.resolve(failingInput)
        let failedCountsAfterFirst = failingVariantCache.counters
        let secondFailedVariant = failingVariantCache.resolve(failingInput)
        let failedCountsAfterSecond = failingVariantCache.counters
        let failedVariantRejectionIsCached: Bool = {
            guard case let .failure(firstFailure) = firstFailedVariant,
                  case let .failure(secondFailure) = secondFailedVariant else {
                return false
            }
            return firstFailure.code == .shaderFrontendFailed
                && secondFailure.code == firstFailure.code
                && failedCountsAfterFirst.cachedVariantCount == 1
                && failedCountsAfterFirst.shaderPreparationCount == 1
                && failedCountsAfterFirst.frontendCompilationCount == 1
                && failedCountsAfterSecond == failedCountsAfterFirst
        }()

        let mixedGraph = graph(
            targets: [rawTarget(first), rawTarget(second)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: second, read: input),
                command(2, kind: .copy, source: first, target: second),
                command(3, kind: .swap, source: first, target: second),
                material(4, ordinal: 2, target: output, read: first),
            ]
        )
        let mixedChain = admittedGraph(mixedGraph)
        let mixedCapabilities = capabilities(
            mixedChain,
            catalog: catalog(for: mixedGraph)
        )
        let mixedClaim = mixedCapabilities.claim(mixedChain)!
        let mixedExecutor = Executor(
            device: device,
            capabilities: mixedCapabilities
        )!
        let mixedLease = makeLease(requirePlan(mixedGraph), device: device)
        guard let mixedBuffer = queue.makeCommandBuffer() else {
            fatalError("mixed buffer unavailable")
        }
        let mixedPreparation = mixedExecutor.prepare(
            token: mixedClaim.token,
            leases: [mixedLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(1),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: mixedBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )

        let freshCopyGraph = graph(
            targets: [rawTarget(first), rawTarget(second)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                command(1, kind: .copy, source: first, target: second),
                material(2, ordinal: 1, target: output, read: second),
            ]
        )
        let freshCopyChain = admittedGraph(freshCopyGraph)
        let freshCopyCapabilities = capabilities(
            freshCopyChain,
            catalog: catalog(for: freshCopyGraph)
        )
        let freshCopyClaim = freshCopyCapabilities.claim(freshCopyChain)!
        let freshCopyExecutor = Executor(
            device: device,
            capabilities: freshCopyCapabilities
        )!
        let freshCopyLease = makeLease(
            requirePlan(freshCopyGraph),
            device: device
        )
        guard let freshCopyBuffer = queue.makeCommandBuffer() else {
            fatalError("fresh copy buffer unavailable")
        }
        let freshCopyPreparation = freshCopyExecutor.prepare(
            token: freshCopyClaim.token,
            leases: [freshCopyLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(1),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: freshCopyBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        var freshCopyPreparedAndEncoded = false
        var freshCopyPublicationMatches = false
        if case let .success(value) = freshCopyPreparation,
           let transition = value.stages.first,
           let mapped = transition.transition.transaction.mappingAfter[second],
           let published = transition.frameResources[second],
           let targetTexture = freshCopyLease.texture(for: second) {
            if case let .provider(.graph(generation, token)) =
                published.publication.candidate.identity {
                freshCopyPublicationMatches = generation == freshCopyLease.generation
                    && token == mapped.token.rawValue
                    && published.publication.requestIdentity == .graph(second)
                    && published.resourceGeneration == mapped.contentGeneration
                    && published.publication.contentGeneration
                        == mapped.contentGeneration
                    && published.publication.texture === targetTexture
            }
            let appended = freshCopyExecutor.encode(
                value,
                commandBuffer: freshCopyBuffer
            )
            guard let readback = appendReadback(
                targetTexture,
                commandBuffer: freshCopyBuffer
            ) else { fatalError("fresh copy readback unavailable") }
            freshCopyBuffer.commit()
            freshCopyBuffer.waitUntilCompleted()
            freshCopyPreparedAndEncoded = appended
                && freshCopyBuffer.status == .completed
                && freshCopyBuffer.error == nil
                && matches(readback.firstPixel, [0, 0, 255, 255])
        }

        let copyMismatchGraph = graph(
            targets: [rawTarget(first), rawTarget(second, width: 1, height: 2)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                command(1, kind: .copy, source: first, target: second),
                material(2, ordinal: 1, target: output, read: second),
            ]
        )
        let copyMismatchPlan = manualPlan(
            targets: [
                logical(
                    first,
                    firstWrite: 0,
                    lastWrite: 0,
                    firstRead: 1,
                    lastRead: 1
                ),
                logical(
                    second,
                    width: 1,
                    height: 2,
                    firstWrite: 1,
                    lastWrite: 1,
                    firstRead: 2,
                    lastRead: 2
                ),
            ],
            commands: [.init(
                nodeIndex: 1,
                kind: .copy,
                source: first,
                target: second
            )]
        )
        let copyMismatchChain = admittedGraph(copyMismatchGraph)
        let copyMismatchCapabilities = capabilities(
            copyMismatchChain,
            catalog: catalog(for: copyMismatchGraph)
        )
        let copyMismatchClaim = copyMismatchCapabilities.claim(
            copyMismatchChain
        )!
        let copyMismatchExecutor = Executor(
            device: device,
            capabilities: copyMismatchCapabilities
        )!
        let copyMismatchLease = makeLease(copyMismatchPlan, device: device)
        guard let copyMismatchBuffer = queue.makeCommandBuffer() else {
            fatalError("copy mismatch buffer unavailable")
        }
        let copyMismatch = copyMismatchExecutor.prepare(
            token: copyMismatchClaim.token,
            leases: [copyMismatchLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(1),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: copyMismatchBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )

        let swapMismatchGraph = graph(
            targets: [rawTarget(first), rawTarget(second, unique: true)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: second, read: input),
                command(2, kind: .swap, source: first, target: second),
                material(3, ordinal: 2, target: output, read: first),
            ]
        )
        let swapMismatchPlan = manualPlan(
            targets: [
                logical(
                    first,
                    firstWrite: 0,
                    lastWrite: 2,
                    firstRead: 2,
                    lastRead: 3
                ),
                logical(
                    second,
                    unique: true,
                    firstWrite: 1,
                    lastWrite: 2,
                    firstRead: 2,
                    lastRead: 2
                ),
            ],
            commands: [.init(
                nodeIndex: 2,
                kind: .swap,
                source: first,
                target: second
            )]
        )
        let swapMismatchChain = admittedGraph(swapMismatchGraph)
        let swapMismatchCapabilities = capabilities(
            swapMismatchChain,
            catalog: catalog(for: swapMismatchGraph)
        )
        let swapMismatchClaim = swapMismatchCapabilities.claim(
            swapMismatchChain
        )!
        let swapMismatchExecutor = Executor(
            device: device,
            capabilities: swapMismatchCapabilities
        )!
        let swapMismatchLease = makeLease(swapMismatchPlan, device: device)
        guard let swapMismatchBuffer = queue.makeCommandBuffer() else {
            fatalError("swap mismatch buffer unavailable")
        }
        let swapMismatch = swapMismatchExecutor.prepare(
            token: swapMismatchClaim.token,
            leases: [swapMismatchLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(1),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: swapMismatchBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )

        let mixedKinds: [String]
        let mixedPublicationChain: Bool
        switch mixedPreparation {
        case let .success(value):
            mixedKinds = intentKinds(value)
            let transition = value.stages[0]
            mixedPublicationChain = transition.programCacheKeys.count == 3
                && transition.frameResources[first] != nil
                && transition.frameResources[second] != nil
                && transition.effectOutputResource.publication.requestIdentity
                    == .graph(output)
        case .failure:
            mixedKinds = []
            mixedPublicationChain = false
        }

        let sameDescriptorHistory = runHistoryScenario(
            device: device,
            queue: queue,
            sourcePipeline: sourcePipeline,
            fixedSize: false,
            resizedWidth: extent.width,
            resizedHeight: extent.height,
            preservesDescriptors: true
        )
        let dynamicResizeHistory = runHistoryScenario(
            device: device,
            queue: queue,
            sourcePipeline: sourcePipeline,
            fixedSize: false,
            resizedWidth: 3,
            resizedHeight: 3,
            preservesDescriptors: false
        )
        let fixedResizeHistory = runHistoryScenario(
            device: device,
            queue: queue,
            sourcePipeline: sourcePipeline,
            fixedSize: true,
            resizedWidth: 3,
            resizedHeight: 3,
            preservesDescriptors: true
        )

        let results: [String: Bool] = [
            "ordinaryCanClaim": ordinaryCapabilities.claim(ordinaryChain) != nil,
            "implicitFramebufferStructuralInferenceBindsEffectInput":
                failureCode(implicitFramebufferPreparation) == "success",
            "historicalFramebufferAliasBindsEffectInput":
                failureCode(historicalFramebufferPreparation) == "success",
            "historicalFramebufferAliasPublishesTypedOutput":
                historicalFramebufferPublication,
            "historicalFramebufferAliasEncodesOnGPU": historicalFramebufferEncoded,
            "foreignCatalogTokenRejected": lateCapabilities.resolve(
                ordinaryClaim.token
            ) == nil,
            "conditionRejected": capabilities(
                admittedGraph(conditionGraph), catalog: catalog(for: conditionGraph)
            ).claim(admittedGraph(conditionGraph)) == nil,
            "composeRejected": capabilities(
                admittedGraph(composeGraph), catalog: catalog(for: composeGraph)
            ).claim(admittedGraph(composeGraph)) == nil,
            "inactiveComposeAccepted": {
                let value = admittedGraph(inactiveComposeGraph)
                return capabilities(
                    value,
                    catalog: catalog(for: inactiveComposeGraph)
                ).claim(value) != nil
            }(),
            "activePassRejectedByLaunchEnvelope":
                passCapabilities.claim(ordinaryChain) == nil
                    && passCapabilities.reportLines.contains {
                        $0.contains(
                            "rejection: material-variant-envelope-sampler-schema count=1"
                        )
                    },
            "typedPreflightFailureCodesAreStable":
                Executor.Failure.graphStructureRejected.rawValue
                    == "graph-structure-rejected"
                    && Executor.Failure.materialPassEncoderRejected.rawValue
                        == "material-pass-encoder-rejected",
            "finalizerFailureIncludesBoundedSanitizedField":
                Executor.Failure.materialFinalizerRejected(
                    stageIndex: 1,
                    effect: .init(
                        layerID: 7,
                        effectIndex: 4,
                        descriptorID: "fixture-effect"
                    ),
                    nodeIndex: 3,
                    materialOrdinal: 2,
                    failure: .init(
                        phase: .uniform,
                        code: .uniformBindingInvalid,
                        details: ["g_Test[0] bad/field"]
                    )
                ).rawValue
                    == "stage-1-layer-7-effect-4-descriptor-"
                        + "6de7b3207797"
                        + "-node-3-material-2-finalizer-uniform-"
                        + "uniformBindingInvalid-detail-g_Test_0__bad_field",
            "missingTemplateRejected": missingCapabilities.claim(ordinaryChain) == nil,
            "nonOverwriteRejectedBeforeFrame": nonOverwriteCapabilities.claim(
                ordinaryChain
            ) == nil,
            "resourceDemandIssueRejectedBeforeFrame":
                demandIssueCapabilities.claim(ordinaryChain) == nil,
            "internalDefaultRejectedBeforeFrame":
                internalDefaultCapabilities.claim(ordinaryChain) == nil,
            "repeatTargetRejectedBeforeFrame": repeatTargetCapabilities.claim(
                admittedGraph(repeatTargetGraph)
            ) == nil,
            "nonzeroClearRejectedBeforeFrame": nonzeroClearCapabilities.claim(
                admittedGraph(nonzeroClearGraph)
            ) == nil,
            "oversizedNodeGraphRejectedBeforeGPU": capabilities(
                admittedGraph(oversizedNodeGraph), catalog: catalog(for: oversizedNodeGraph)
            ).claim(admittedGraph(oversizedNodeGraph)) == nil,
            "oversizedLogicalGraphRejectedBeforeGPU": capabilities(
                admittedGraph(oversizedLogicalGraph), catalog: catalog(for: oversizedLogicalGraph)
            ).claim(admittedGraph(oversizedLogicalGraph)) == nil,
            "prepareHasNoEncodingSideEffect": prepareHasNoEncodingSideEffect,
            "launchWarmupPreparesEveryUniqueOrdinaryPipeline":
                ordinaryWarmupReport.plannedPlanCount == 2
                    && ordinaryWarmupReport.uniqueKeyCount > 0
                    && ordinaryWarmupReport.readyKeyCount
                        == ordinaryWarmupReport.uniqueKeyCount
                    && ordinaryWarmupReport.failedKeyCount == 0
                    && ordinaryWarmupReport.compilationAttemptCount
                        == ordinaryWarmupReport.uniqueKeyCount
                    && ordinaryAttemptsAfterWarmup
                        == ordinaryWarmupReport.uniqueKeyCount,
            "firstFrameConsumesLaunchWarmupWithoutMetalCompilation":
                ordinaryAttemptsAfterFirstPreparation == ordinaryAttemptsAfterWarmup
                    && ordinaryWarmupHitsAfterFirstPreparation > 0,
            "unreadableSourceCaptureRejectedDuringPreflight":
                failureCode(unreadableCapturePreparation)
                    == Executor.Failure.captureRejected.rawValue,
            "staticClaimRejectionHasNoPartialWrite":
                staticClaimRejectionHasNoPartialWrite,
            "twoMaterialPublicationFinalized": prepared.stages.count == 1
                && prepared.stages[0].programCacheKeys.count == 2
                && prepared.stages[0].frameResources[first] != nil
                && prepared.stages[0].effectOutputResource.publication
                    .requestIdentity == .graph(output),
            "encodedOutputReadable": encodedOutputReadable,
            "sourceCaptureRendersAcrossFullTarget":
                sourceCaptureCoversFullTarget,
            "scalarCapabilityCarriesExactAttachmentKinds": {
                guard let capability = scalarCapabilities.resolve(
                    scalarClaim.token,
                    for: scalarChain
                ) else { return false }
                return capability.material(for: scalarGraph.nodes[0])?
                        .attachmentStorage == .scalarRedUnorm
                    && capability.material(for: scalarGraph.nodes[1])?
                        .attachmentStorage == .color
            }(),
            "scalarPrepareHasNoEncodingSideEffect": scalarPrepareHasNoWrite,
            "scalarPublicationIsTypedAndComplete": scalarPublicationContract,
            "scalarGraphEncoded": scalarEncoded,
            "scalarGraphGPUCompleted": scalarGPUCompleted,
            "scalarProducerStoresRedComponent": scalarRedStored,
            "scalarDirectRedConsumerReachesColorTerminal": scalarTerminalMatches,
            "scalarGreenConsumerRejectedBeforeFrame": scalarRejection(
                scalarGreenGraph,
                consumers: [1: "green"]
            ),
            "scalarWholeConsumerRejectedBeforeFrame": scalarRejection(
                scalarWholeGraph,
                consumers: [1: "whole"]
            ),
            "scalarAliasConsumerRejectedBeforeFrame": scalarRejection(
                scalarAliasGraph,
                consumers: [1: "alias"]
            ),
            "scalarClearRejectedBeforeFrame": scalarRejection(
                scalarClearGraph,
                consumers: [1: "red"]
            ),
            "scalarUniqueHistoryRejectedBeforeFrame": scalarRejection(
                scalarUniqueGraph,
                consumers: [1: "red"]
            ),
            "scalarNoConsumerRejectedBeforeFrame": scalarRejection(
                scalarNoConsumerGraph
            ),
            "scalarMultipleWriterRejectedBeforeFrame": scalarRejection(
                scalarMultipleWriterGraph,
                consumers: [2: "red"]
            ),
            "scalarCopyRejectedBeforeFrame": scalarRejection(
                scalarCopyGraph,
                consumers: [2: "red"]
            ),
            "scalarSwapRejectedBeforeFrame": scalarRejection(
                scalarSwapGraph,
                consumers: [2: "red"]
            ),
            "scalarRepeatRejectedBeforeFrame": scalarRejection(
                scalarRepeatGraph,
                consumers: [1: "red"],
                expectedCode: "admitted-graph-structure"
            ),
            "orderedStagesPreparedTogether": chainedStagesPrepared,
            "orderedStagesEncodedTogether": chainedStagesEncoded,
            "orderedStagesGPUCompleted": chainedStagesGPUCompleted,
            "orderedStagesPreservePriorPixelContribution":
                chainedStagePixelsPreserved,
            "dynamicUniformValidFramePreparesProgram":
                dynamicUniformValidFramePrepares,
            "dynamicUniformFailurePassthroughPrepared":
                dynamicUniformFailurePassthroughPrepared,
            "dynamicUniformFailurePassthroughEncoded":
                dynamicUniformFailurePassthroughEncoded,
            "dynamicUniformFailurePassthroughGPUCompleted":
                dynamicUniformFailurePassthroughGPUCompleted,
            "dynamicUniformFailurePreservesPreviousAndContinuesSuffix":
                dynamicUniformFailurePreservesPreviousAndContinuesSuffix,
            "staticUniformFailurePassthroughPrepared":
                staticUniformFailurePassthroughPrepared,
            "staticUniformFailurePassthroughEncoded":
                staticUniformFailurePassthroughEncoded,
            "staticUniformFailurePassthroughGPUCompleted":
                staticUniformFailurePassthroughGPUCompleted,
            "staticUniformFailurePreservesPreviousAndContinuesSuffix":
                staticUniformFailurePreservesPreviousAndContinuesSuffix,
            "dynamicUniformMultiNodeRemainsHardRejected":
                dynamicUniformMultiNodeRemainsHardRejected,
            "staticUniformMultiNodeRemainsHardRejected":
                staticUniformMultiNodeRemainsHardRejected,
            "visualUniformSchemaFailureCanClaimEffectLocalPassthrough":
                visualFailureCanClaimEffectLocalPassthrough,
            "visualUniformSchemaFailurePassthroughPrepared":
                visualFailurePassthroughPrepared,
            "visualUniformSchemaFailurePassthroughEncoded":
                visualFailurePassthroughEncoded,
            "visualUniformSchemaFailurePassthroughGPUCompleted":
                visualFailurePassthroughGPUCompleted,
            "visualUniformSchemaFailurePreservesPreviousAndContinuesSuffix":
                visualFailurePreservesPreviousAndContinuesSuffix,
            "visualUniformSchemaFailurePassthroughIsTypedAndCounted":
                visualFailurePassthroughIsTypedAndCounted,
            "visualUniformSchemaMultiNodeRemainsHardRejected":
                uniformSchemaMultiNodeCapabilities.claim(ordinaryChain) == nil
                    && uniformSchemaMultiNodeCapabilities.reportLines.contains {
                        $0.contains(
                            "rejection: material-variant-envelope-uniform-schema"
                                + " count=1"
                        )
                    },
            "rendererFailurePassthroughPrepared":
                rendererFailurePassthroughPrepared,
            "rendererFailurePassthroughEncoded":
                rendererFailurePassthroughEncoded,
            "rendererFailurePassthroughGPUCompleted":
                rendererFailurePassthroughGPUCompleted,
            "rendererFailurePreservesPreviousAndContinuesSuffix":
                rendererFailurePreservesPreviousAndContinuesSuffix,
            "ordinaryComposeRotatesWithinEffectAndReturnsTerminalZero":
                failureCode(composePreparation) == "success"
                    && composePublicationContract
                    && composeEncoded
                    && composePixelsPreserved,
            "secondFramePreviousStateAndResourcesPrepared": failureCode(secondFrame)
                == "success",
            "secondFrameReusesShaderAndFrontendVariant":
                compilerCountsAfterFirst.shader > 0
                    && compilerCountsAfterFirst.frontend > 0
                    && compilerCountsAfterSecond.shader
                        == compilerCountsAfterFirst.shader
                    && compilerCountsAfterSecond.frontend
                        == compilerCountsAfterFirst.frontend,
            "boundedVariantOverflowFailsClosed": {
                if case .success = readyVariant { return overflowRejected }
                return false
            }(),
            "independentFailedVariantRejectionIsCached":
                failedVariantRejectionIsCached,
            "frontendInvalidRejectedByLaunchEnvelope":
                failingCapabilities.claim(ordinaryChain) == nil
                    && failingCapabilities.reportLines.contains {
                        $0.contains(
                            "rejection: material-variant-envelope-frontend count=1"
                        )
                    },
            "copyAndSwapPrepared": failureCode(mixedPreparation) == "success"
                && mixedKinds.contains("copy")
                && mixedKinds.contains("swap")
                && mixedPublicationChain,
            "freshCopyTargetPreparedAndEncoded":
                failureCode(freshCopyPreparation) == "success"
                    && freshCopyPreparedAndEncoded,
            "freshCopyPublicationMatchesTargetVersion":
                freshCopyPublicationMatches,
            "copyExtentMismatchRejectedBeforeFrame": failureCode(copyMismatch)
                == Executor.Failure.invalidClaim.rawValue,
            "swapDescriptorMismatchRejectedBeforeFrame": failureCode(swapMismatch)
                == Executor.Failure.invalidClaim.rawValue,
            "freshSameDescriptorLeaseWithoutCopiesRejectsHistory":
                sameDescriptorHistory.noCopiesBehavior,
            "freshSameDescriptorLeaseWithIncompleteCopiesRejectsHistory":
                sameDescriptorHistory.incompleteCopiesBehavior,
            "completeHistoryCopiesPreserveSwapPermutationAndGeneration":
                sameDescriptorHistory.fixtureHasSwapPermutation
                    && sameDescriptorHistory.mappingBehavior,
            "completeHistoryCopiesEncodePreservedPixels":
                sameDescriptorHistory.preparedAndEncoded
                    && sameDescriptorHistory.pixelBehavior,
            "dynamicFramebufferResizeRejectsStaleCopies":
                dynamicResizeHistory.unexpectedCopiesRejected,
            "dynamicFramebufferResizeResetsWithoutCopies":
                dynamicResizeHistory.noCopiesBehavior
                    && dynamicResizeHistory.fixtureHasSwapPermutation
                    && dynamicResizeHistory.mappingBehavior
                    && dynamicResizeHistory.preparedAndEncoded
                    && dynamicResizeHistory.pixelBehavior,
            "fixedFramebufferPairResizeRequiresCompleteCopies":
                fixedResizeHistory.noCopiesBehavior
                    && fixedResizeHistory.incompleteCopiesBehavior,
            "fixedFramebufferPairResizePreservesHistory":
                fixedResizeHistory.fixtureHasSwapPermutation
                    && fixedResizeHistory.mappingBehavior
                    && fixedResizeHistory.preparedAndEncoded
                    && fixedResizeHistory.pixelBehavior,
        ]
        let payload: [String: Any] = [
            "metalAvailable": true,
            "results": results,
            "failureCodes": [
                "late": failureCode(latePreparation),
                "copyMismatch": failureCode(copyMismatch),
                "swapMismatch": failureCode(swapMismatch),
                "firstFailedVariant": variantFailureCode(firstFailedVariant),
                "secondFailedVariant": variantFailureCode(secondFailedVariant),
            ],
            "composeDiagnostics": [
                "failure": failureCode(composePreparation),
                "publication": String(composePublicationContract),
                "encoded": String(composeEncoded),
                "pixels": String(composePixelsPreserved),
            ],
            "mixedKinds": mixedKinds,
            "encodedPixel": encodedRead.firstPixel,
            "encodedLastPixel": encodedRead.lastPixel,
            "pixelChainCanClaim": pixelCapabilities.claim(pixelChain) != nil,
            "pixelChainReport": pixelCapabilities.reportLines,
            "pixelChainFailure": pixelChainFailure,
            "visualFailureObservedPixels": visualFailureObservedPixels,
            "dynamicUniformMultiNodeFailure": dynamicUniformMultiNodeFailure,
            "dynamicUniformMultiNodeReport": dynamicMultiCapabilities.reportLines,
            "staticUniformMultiNodeFailure": staticUniformMultiNodeFailure,
            "staticUniformMultiNodeReport":
                staticUniformMultiNodeCapabilities.reportLines,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialGraphExecutorTests(unittest.TestCase):
    def test_visual_failure_passthrough_keeps_exact_launch_reason_allowlist(
        self,
    ) -> None:
        for source in (
            PROGRAM_FIRST_STAGES_SOURCE,
            VISUAL_FAILURE_PASSTHROUGH_SOURCE,
        ):
            text = source.read_text(encoding="utf-8")
            self.assertIn('"material-variant-envelope-frontend"', text)
            self.assertIn(
                '"material-variant-envelope-shader-preparation"',
                text,
            )
            self.assertIn(
                '"material-variant-envelope-color-contract"',
                text,
            )
            self.assertIn(
                '"material-variant-envelope-uniform-schema"',
                text,
            )
            self.assertNotIn('"material-variant-envelope-texture"', text)
            self.assertNotIn('"material-variant-envelope-target"', text)
            self.assertNotIn('"material-variant-envelope-runtime-encode"', text)
        visual_text = VISUAL_FAILURE_PASSTHROUGH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            '"material-finalizer-dynamic-uniform-binding"',
            visual_text,
        )
        self.assertIn(
            '"material-dynamic-uniform-contributor-policy"',
            visual_text,
        )
        self.assertIn(
            '"material-dynamic-uniform-contributor-producer-unavailable"',
            visual_text,
        )
        self.assertIn(
            '"material-dynamic-uniform-script-attachment-unproven"',
            visual_text,
        )
        self.assertIn(
            '"material-dynamic-uniform-producer-unavailable"',
            visual_text,
        )

    def test_production_executor_preflights_and_executes_atomic_graph(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-graph-executor-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "resolved-material-graph-executor-test"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    "-D",
                    "SCENE_GRAPH_TESTING",
                    str(support),
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-framework",
                    "CoreGraphics",
                    "-framework",
                    "ImageIO",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

        self.assertNotIn(
            "SceneOffscreenEffectRenderer",
            EXECUTOR_SOURCE.read_text(encoding="utf-8"),
        )
        self.assertNotIn("SceneOffscreenEffectRenderer", SUPPORT)

        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [
                name
                for name, passed in payload["results"].items()
                if not passed
            ],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
