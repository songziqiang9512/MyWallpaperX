#!/usr/bin/env python3

"""R4 production resolved-material graph executor Metal gate."""

from __future__ import annotations

import json
from pathlib import Path
import runpy
import shutil
import unittest


CONTRACT_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_visual_failure_contract.py"
)
CONTRACT_FIXTURE = runpy.run_path(str(CONTRACT_GATE))
PUBLICATION_FIXTURE = CONTRACT_FIXTURE["PUBLICATION_FIXTURE"]
compile_harness = CONTRACT_FIXTURE["compile_harness"]


SUPPORT = PUBLICATION_FIXTURE["SUPPORT"] + r'''

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
struct SceneBlendExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let dependencyProviderLayerID: Int?
}

extension SceneEffectStageExecutionPlan {
    var proceduralNoise: SceneProceduralNoiseExecutionPlan? { nil }
    var blend: SceneBlendExecutionPlan? { nil }
    var shake: HarnessDedicatedAudioExecutionPlan? { nil }
    var pulse: HarnessDedicatedAudioExecutionPlan? { nil }
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
        var contentKind: String = "image"
        var utilityLayer: SceneUtilityLayer? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [String] = []
        var namedReferences: [SceneDependencyRenderPlan.Reference] = []
        var namedBindings: [SceneDependencyRenderPlan.Binding] = []
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
            case resolvedMaterial, proceduralNoiseLayer, imageLayerBlend
        }
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
        }
    }

    let references: [Reference]
    let namedReferenceConsumerLayerIDs: Set<Int>
    let bindingsByConsumerLayerID: [Int: Binding]

    init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int> = []
    ) {
        references = descriptor.layers.flatMap(\.namedReferences)
        namedReferenceConsumerLayerIDs = Set(references.compactMap {
            visibleLayerIDs.contains($0.consumerLayerID) ? $0.consumerLayerID : nil
        })
        var bindings: [Int: Binding] = [:]
        for layer in descriptor.layers where visibleLayerIDs.contains(layer.id) {
            guard layer.utilityLayer == nil
                    || executableUtilityConsumerLayerIDs.contains(layer.id) else {
                continue
            }
            let matches = layer.namedBindings.filter {
                $0.consumerLayerID == layer.id
            }
            if matches.count == 1 {
                bindings[layer.id] = matches[0]
            }
        }
        bindingsByConsumerLayerID = bindings
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
        let time: Float
        let layerModelMatrix: simd_float4x4
        let effectTextureProjectionMatrixInverse: simd_float4x4
        let dependencyEffect: SceneDependencyEffectInput?

        init(dependencyEffect: SceneDependencyEffectInput? = nil) {
            time = 0
            layerModelMatrix = matrix_identity_float4x4
            effectTextureProjectionMatrixInverse = matrix_identity_float4x4
            self.dependencyEffect = dependencyEffect
        }
    }
}

struct SceneDependencyEffectInput {
    let frameEpoch: UInt64
    let namedReference: SceneNamedTextureReference
    let reservedMaterialResource: SceneFrameTextureResource?
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
        time: Float
    ) -> StagePreparation {
        _ = inputs
        _ = sourcePipeline
        _ = time
        guard targets.inputTexture === sourceTexture,
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
private let colorBlendMaskPath = SceneVFSAssetPath(
    "textures/unseen-color-blend-mask.tex"
)!
private let colorBlendMaskIdentity = SceneAssetTextureIdentity(
    path: colorBlendMaskPath,
    purpose: .mask
)

private let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private let colorBlendVertexSource = """
uniform mat4 g_ModelViewProjectionMatrix;

#if MASK
uniform vec4 g_Texture1Resolution;
#endif

attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_TexCoord;
void main() {
    gl_Position = mul(
        vec4(a_Position, 1.0),
        g_ModelViewProjectionMatrix
    );
    v_TexCoord = a_TexCoord.xyxy;

#if MASK
    v_TexCoord.zw = vec2(
        v_TexCoord.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
        v_TexCoord.y * g_Texture1Resolution.w / g_Texture1Resolution.y
    );
#endif
}
"""

private func fragmentSource(
    pass: Bool,
    internalDefault: Bool = false,
    samplerSchemaInvalid: Bool = false,
    frontendInvalid: Bool = false,
    uniformSchemaInvalid: Bool = false,
    dynamicUniform: Bool = false,
    staticUniformMissingDefault: Bool = false,
    uniformDeclarationConflict: Bool = false,
    hostUniformDeclarationConflict: Bool = false,
    pixelTransform: Int? = nil,
    scalarProducer: Bool = false,
    scalarProducerUnproven: Bool = false,
    scalarConsumer: String? = nil,
    repeatProbe: Bool = false,
    crossLayerMix: Bool = false,
    colorBlend: Bool = false
) -> String {
    if colorBlend {
        return """
        // [COMBO] {"material":"ui_editor_properties_blend_mode","combo":"BLENDMODE","type":"imageblending","default":30}
        varying vec4 v_TexCoord;
        uniform sampler2D g_Texture0; // {"hidden":true}
        uniform sampler2D g_Texture1; // {"mode":"opacitymask","combo":"MASK"}
        uniform float g_BlendAlpha; // {"material":"alpha","default":1}
        uniform vec3 g_TintColor; // {"material":"color","type":"color","default":"1 0 0"}
        vec3 ApplyBlending(
            const int mode,
            in vec3 base,
            in vec3 blend,
            in float opacity
        ) {
            return mix(base, blend, opacity);
        }
        void main() {
            vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);
            float influence = g_BlendAlpha;
        #if MASK
            influence *= texSample2D(g_Texture1, v_TexCoord.zw).r;
        #endif
            carrier.rgb = ApplyBlending(
                BLENDMODE,
                carrier.rgb,
                g_TintColor,
                influence
            );
            gl_FragColor = carrier;
        }
        """
    }
    let annotation = pass ? "// [PASS] shadow shadowcasterdemo\n" : ""
    let primarySampler = internalDefault
        ? #"uniform sampler2D g_Texture0; // {"default":"_rt_history"}"#
        : samplerSchemaInvalid
            ? #"uniform sampler2D g_Texture0; // {"mode":"mystery"}"#
            : "uniform sampler2D g_Texture0;"
    let samplers = crossLayerMix
        ? primarySampler + "\nuniform sampler2D g_Texture1;"
        : primarySampler
    let varying = frontendInvalid
        ? "varying vec3 v_TexCoord;"
        : "varying vec2 v_TexCoord;"
    let uniform = uniformSchemaInvalid
        ? #"uniform float g_InvalidUniform; // {"material":3}"#
        : dynamicUniform
            ? #"uniform float u_Gain; // {"material":"Gain","default":1}"#
            : staticUniformMissingDefault
                ? #"uniform float u_Static; // {"material":"Static"}"#
                : uniformDeclarationConflict
                    ? #"uniform float u_Alpha; // {"material":"alpha"}"#
                    : hostUniformDeclarationConflict
                        ? "uniform float g_Time;"
                        : ""
    let sampleCoordinate = repeatProbe
        ? "v_TexCoord + vec2(1.0)" : "v_TexCoord"
    let expression = if crossLayerMix {
        "gl_FragColor = mix("
            + "texSample2D(g_Texture0, v_TexCoord), "
            + "texSample2D(g_Texture1, v_TexCoord), 0.5);"
    } else if uniformSchemaInvalid {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord)"
            + " * g_InvalidUniform;"
    } else if staticUniformMissingDefault {
        "vec4 color = texSample2D(g_Texture0, v_TexCoord);"
            + " color.rgb *= u_Static; gl_FragColor = color;"
    } else if uniformDeclarationConflict {
        "vec4 color = texSample2D(g_Texture0, v_TexCoord);"
            + " color.rgb *= u_Alpha; gl_FragColor = color;"
    } else if hostUniformDeclarationConflict {
        "float hostProbe = g_Time;"
            + " gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
    } else if scalarProducerUnproven {
        "if (v_TexCoord.x > 0.5) gl_FragColor = vec4(0.25);"
    } else if scalarProducer {
        "float signal = 0.5 * 0.5;"
            + " gl_FragColor = vec4(signal, signal * 2.0, 0.75, 0.0);"
    } else if scalarConsumer == "red" {
        "float scalar = texSample2D(g_Texture0, \(sampleCoordinate)).r;"
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
    } else if repeatProbe {
        "gl_FragColor = texSample2D("
            + "g_Texture0, v_TexCoord + vec2(1.0));"
    } else {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
    }
    return annotation + """
    \(varying)
    \(samplers)
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
    samplerSchemaInvalid: Bool = false,
    frontendInvalid: Bool = false,
    uniformSchemaInvalid: Bool = false,
    dynamicUniform: Bool = false,
    staticUniformMissingDefault: Bool = false,
    uniformDeclarationConflict: Bool = false,
    hostUniformDeclarationConflict: Bool = false,
    pixelTransform: Int? = nil,
    implicitFramebuffer: Bool = false,
    implicitFramebufferAnnotation: Bool = true,
    historicalFramebufferAlias: Bool = false,
    scalarProducer: Bool = false,
    scalarProducerUnproven: Bool = false,
    scalarConsumer: String? = nil,
    repeatProbe: Bool = false,
    crossLayerMix: Bool = false,
    colorBlend: Bool = false
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
        samplerSchemaInvalid: samplerSchemaInvalid,
        frontendInvalid: frontendInvalid,
        uniformSchemaInvalid: uniformSchemaInvalid,
        dynamicUniform: dynamicUniform,
        staticUniformMissingDefault: staticUniformMissingDefault,
        uniformDeclarationConflict: uniformDeclarationConflict,
        hostUniformDeclarationConflict: hostUniformDeclarationConflict,
        pixelTransform: pixelTransform,
        scalarProducer: scalarProducer,
        scalarProducerUnproven: scalarProducerUnproven,
        scalarConsumer: scalarConsumer,
        repeatProbe: repeatProbe,
        crossLayerMix: crossLayerMix,
        colorBlend: colorBlend
    )
    let stages = [
        stage(
            .vertex,
            path: "\(prefix).vert",
            source: colorBlend ? colorBlendVertexSource : vertexSource
        ),
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
    samplerSchemaInvalid: Bool = false,
    overwrite: Bool = true,
    frontendInvalid: Bool = false,
    uniformSchemaInvalid: Bool = false,
    dynamicUniform: Bool = false,
    staticUniformMissingDefault: Bool = false,
    uniformDeclarationConflict: Bool = false,
    hostUniformDeclarationConflict: Bool = false,
    scalarProducer: Bool = false,
    scalarProducerUnproven: Bool = false,
    scalarConsumer: String? = nil,
    repeatProbe: Bool = false,
    pixelTransform explicitPixelTransform: Int? = nil,
    namedProvider: SceneNamedTextureReference? = nil,
    colorBlendMaskPath: SceneVFSAssetPath? = nil
) -> Template {
    guard let target = node.target,
          let inputBinding = node.bindings.first,
          let slot = inputBinding.slot else {
        fatalError("material fixture is incomplete")
    }
    let pixelTransform: Int? = if let explicitPixelTransform {
        explicitPixelTransform
    } else if node.effect == chainedFirstEffect {
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
        samplerSchemaInvalid: samplerSchemaInvalid,
        frontendInvalid: frontendInvalid,
        uniformSchemaInvalid: uniformSchemaInvalid,
        dynamicUniform: dynamicUniform,
        staticUniformMissingDefault: staticUniformMissingDefault,
        uniformDeclarationConflict: uniformDeclarationConflict,
        hostUniformDeclarationConflict: hostUniformDeclarationConflict,
        pixelTransform: pixelTransform,
        scalarProducer: scalarProducer,
        scalarProducerUnproven: scalarProducerUnproven,
        scalarConsumer: scalarConsumer,
        repeatProbe: repeatProbe,
        crossLayerMix: namedProvider != nil,
        colorBlend: colorBlendMaskPath != nil
    )
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[slot] = .init(index: slot, candidates: [
        .init(
            reference: .graph(inputBinding.texture),
            provenance: .explicitBinding
        ),
    ])
    if let namedProvider {
        slots[1] = .init(index: 1, candidates: [
            .init(
                reference: .provider(.namedLayerTarget(namedProvider)),
                provenance: .instance
            ),
        ])
    }
    if let colorBlendMaskPath {
        slots[1] = .init(index: 1, candidates: [
            .init(
                reference: .asset(colorBlendMaskPath),
                provenance: .material
            ),
        ])
    }
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
        combos: colorBlendMaskPath == nil
            ? [] : [.init(name: "BLENDMODE", value: 30)],
        uniformDeclarations: dynamicUniform
            ? [dynamicUniformDeclaration(for: node)]
            : uniformDeclarationConflict
                ? uniformDeclarationConflictDeclarations()
                : hostUniformDeclarationConflict
                    ? [hostUniformConflictDeclaration()]
                    : [],
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

private func hostUniformConflictDeclaration() -> Template.UniformDeclaration {
    .init(
        name: "g_Time",
        value: .staticExact(.init(
            valueKind: "fixture",
            componentBitPatterns: [Double(99).bitPattern],
            authoredBindingKeys: ["value"]
        ))
    )
}

private func uniformDeclarationConflictDeclarations()
    -> [Template.UniformDeclaration] {
    [
        .init(
            name: "alpha",
            value: .staticExact(.init(
                valueKind: "fixture-alias",
                componentBitPatterns: [Double(0.8).bitPattern],
                authoredBindingKeys: ["value"]
            ))
        ),
        .init(
            name: "u_Alpha",
            value: .staticExact(.init(
                valueKind: "fixture-field",
                componentBitPatterns: [Double(0.4).bitPattern],
                authoredBindingKeys: ["value"]
            ))
        ),
    ]
}

private func catalog(
    for graph: Graph,
    passNodes: Set<Int> = [],
    nonOverwriteNodes: Set<Int> = [],
    internalDefaultNodes: Set<Int> = [],
    samplerSchemaInvalidNodes: Set<Int> = [],
    frontendInvalidNodes: Set<Int> = [],
    uniformSchemaInvalidNodes: Set<Int> = [],
    dynamicUniformNodes: Set<Int> = [],
    staticUniformMissingDefaultNodes: Set<Int> = [],
    uniformDeclarationConflictNodes: Set<Int> = [],
    hostUniformDeclarationConflictNodes: Set<Int> = [],
    omittedNodes: Set<Int> = [],
    demandIssueNodes: Set<Int> = [],
    implicitFramebufferNodes: Set<Int> = [],
    historicalFramebufferNodes: Set<Int> = [],
    scalarProducerNodes: Set<Int> = [],
    scalarProducerUnprovenNodes: Set<Int> = [],
    scalarConsumerNodes: [Int: String] = [:],
    repeatProbeNodes: Set<Int> = [],
    pixelTransformsByNode: [Int: Int] = [:],
    namedProvidersByNode: [Int: SceneNamedTextureReference] = [:],
    colorBlendNodes: Set<Int> = []
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
                samplerSchemaInvalid:
                    samplerSchemaInvalidNodes.contains(node.nodeIndex),
                overwrite: !nonOverwriteNodes.contains(node.nodeIndex),
                frontendInvalid: frontendInvalidNodes.contains(node.nodeIndex),
                uniformSchemaInvalid:
                    uniformSchemaInvalidNodes.contains(node.nodeIndex),
                dynamicUniform: dynamicUniformNodes.contains(node.nodeIndex),
                staticUniformMissingDefault:
                    staticUniformMissingDefaultNodes.contains(node.nodeIndex),
                uniformDeclarationConflict:
                    uniformDeclarationConflictNodes.contains(node.nodeIndex),
                hostUniformDeclarationConflict:
                    hostUniformDeclarationConflictNodes.contains(node.nodeIndex),
                scalarProducer: scalarProducerNodes.contains(node.nodeIndex),
                scalarProducerUnproven:
                    scalarProducerUnprovenNodes.contains(node.nodeIndex),
                scalarConsumer: scalarConsumerNodes[node.nodeIndex],
                repeatProbe: repeatProbeNodes.contains(node.nodeIndex),
                pixelTransform: pixelTransformsByNode[node.nodeIndex],
                namedProvider: namedProvidersByNode[node.nodeIndex],
                colorBlendMaskPath: colorBlendNodes.contains(node.nodeIndex)
                    ? colorBlendMaskPath : nil
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

private func requireMaterialFunctionPlan(_ graph: Graph) -> Plan {
    switch Plan.make(
        executionPlan: executionPlan(for: graph),
        graph: graph,
        inputWidth: extent.width,
        inputHeight: extent.height,
        materialFunctionTargets: [first]
    ) {
    case let .success(value): value
    case let .failure(failure):
        fatalError("material function plan failed: \(failure.rawValue)")
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
    addressMode: Plan.UVAddressMode = .clampToEdge,
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
        addressMode: addressMode,
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
    bgra: [UInt8] = [0, 0, 255, 255],
    pixelsBGRA: [UInt8]? = nil
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
    let pixels = pixelsBGRA ?? (0 ..< width * height).flatMap { _ in bgra }
    precondition(pixels.count == width * height * 4)
    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: pixels,
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
    timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
    textureEntries: [
        SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
    ] = [:]
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
            entries: textureEntries
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

private enum ColorBlendMaskFixtureStatus: Equatable {
    case ready
    case pending
    case unavailable
    case wrongPurpose
    case wrongContent
    case samplingUnresolved
    case generationMismatch
    case requestIdentityMismatch
}

private func colorBlendMaskStatus(
    _ kind: ColorBlendMaskFixtureStatus,
    device: MTLDevice,
    generation: UInt64
) -> SceneFrameTextureLookupStatus {
    if kind == .pending { return .pending }
    if kind == .unavailable { return .unavailable }

    let purpose: SceneTextureLoadPurpose = kind == .wrongPurpose ? .noise : .mask
    let content: SceneTextureContent = kind == .wrongContent
        ? .color(.resolved(.straightAlpha)) : .data
    let candidateGeneration = generation
    let contentGeneration = kind == .generationMismatch
        ? generation + 1 : generation
    let requestIdentity: SceneFrameTextureIdentity = kind == .requestIdentityMismatch
        ? .asset(.init(
            path: SceneVFSAssetPath("textures/other-mask.tex")!,
            purpose: .mask
        ))
        : .asset(colorBlendMaskIdentity)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r8Unorm,
        width: 8,
        height: 4,
        mipmapped: true
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let texture = device.makeTexture(descriptor: descriptor)!
    for level in 0 ..< texture.mipmapLevelCount {
        let width = max(1, texture.width >> level)
        let height = max(1, texture.height >> level)
        let mappedWidth = max(1, width / 2)
        let bytes = (0 ..< width * height).map { index in
            index % width < mappedWidth ? UInt8(255) : UInt8(0)
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: level,
            withBytes: bytes,
            bytesPerRow: width
        )
    }
    let physicalSize = CGSize(width: texture.width, height: texture.height)
    let mappedSize = CGSize(width: 4, height: 4)
    let publication = SceneTextureProviderPublication(
        requestIdentity: requestIdentity,
        candidate: .init(
            texture: texture,
            identity: .provider(.video(
                layerID: layerID,
                lifecycleEpoch: generation
            )),
            generation: .provider(contentGeneration: candidateGeneration),
            purpose: purpose,
            content: content,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: .init(
                origin: .zero,
                xAxis: SIMD2(0.5, 0),
                yAxis: SIMD2(0, 1)
            ),
            sampling: kind == .samplingUnresolved
                ? .init(texFlags: 8) : .linearClamp,
            authoredFormat: .r8
        ),
        contentGeneration: contentGeneration
    )
    let resource = SceneFrameTextureResource(
        publication: publication,
        resourceGeneration: generation
    )
    switch kind {
    case .ready, .samplingUnresolved, .requestIdentityMismatch:
        return .ready(resource)
    case .wrongPurpose, .wrongContent, .generationMismatch:
        return .incomplete(.publication(
            publication,
            resourceGeneration: generation
        ))
    case .pending, .unavailable:
        fatalError("handled before publication construction")
    }
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

private func isPremultiplied(_ pixel: [UInt8]) -> Bool {
    guard pixel.count == 4 else { return false }
    let alpha = Int(pixel[3])
    return Int(pixel[0]) <= alpha + 1
        && Int(pixel[1]) <= alpha + 1
        && Int(pixel[2]) <= alpha + 1
        && (alpha != 0 || pixel[0 ... 2].allSatisfy { $0 == 0 })
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

private func materialFunctionGraph() -> Graph {
    let nodes = [
        material(0, ordinal: 0, target: output, read: first),
        material(1, ordinal: 1, target: first, read: input),
    ]
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effect,
            definitionPath: "effects/executor/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: [rawTarget(first, unique: true)],
        nodes: nodes,
        finalOutput: output,
        blockers: [.init(
            effect: effect,
            definitionPassIndex: nil,
            reason: .unsupportedFunctions,
            detail: "explicit function registry"
        )]
    )
}

private func materialFunctionRegistry() -> SceneJSONValue {
    .object([
        "reset": .object([
            "action": .string("clear"),
            "fbos": .array([.string(first.name!), .string(first.name!)]),
        ]),
    ])
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
    var wrongRequestIdentityRejected = false
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

    var result = HistoryScenarioResult()
    let previous = transition.transition.nextState
    if let original = transition.persistentResources[first] {
        var forgedResources = transition.persistentResources
        forgedResources[first] = .init(
            publication: original.publication.publication(for: .graph(second)),
            resourceGeneration: original.resourceGeneration
        )
        result.wrongRequestIdentityRejected = executor.resources(
            matching: previous.logicalMapping,
            from: forgedResources
        ) == nil
    }
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

private struct MaterialFunctionScenarioResult {
    var capabilityClaimed = false
    var setupFailure = "none"
    var noCallFailure = "setup"
    var invokedPixel = [UInt8]()
    var invocationIntentCount = 0
    var staleFailure = "setup"
    var unknownEffectFailure = "setup"
    var unknownFunctionFailure = "setup"
    var encodeFailure = "setup"
    var failedEncodePreservedPixel = [UInt8]()
}

private func runMaterialFunctionScenario(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline
) -> MaterialFunctionScenarioResult {
    let raw = materialFunctionGraph()
    let chain = admittedGraph(raw)
    let registry = materialFunctionRegistry()
    let capabilities = capabilities(
        chain,
        catalog: catalog(for: raw),
        functionsByEffect: [effect: registry]
    )
    guard let claim = capabilities.claim(chain),
          let executor = Executor(device: device, capabilities: capabilities),
          let capability = capabilities.resolve(claim.token),
          capability.admittedProducts.first?.clearFunctions
            .function(named: "reset")?.targets == [first, first],
          let firstBuffer = queue.makeCommandBuffer() else { return .init() }
    var result = MaterialFunctionScenarioResult()
    result.capabilityClaimed = true
    let functionLease = makeLease(
        requireMaterialFunctionPlan(capability.admittedProducts[0].graph),
        device: device
    )
    let normalLease = makeLease(
        requirePlan(capability.admittedProducts[0].graph),
        device: device
    )
    let firstPreparation = executor.prepare(
        token: claim.token,
        leases: [functionLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(80),
        sceneBackgroundResource: nil,
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        dedicatedInputs: .init(),
        commandBuffer: firstBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        materialFunctionInvocations: [
            .init(effect: effect, functionName: "reset", frameEpoch: 80)
        ],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(firstPrepared) = firstPreparation else {
        result.setupFailure = failureCode(firstPreparation)
        return result
    }
    guard let firstStage = firstPrepared.stages.first,
          executor.encode(firstPrepared, commandBuffer: firstBuffer) else {
        result.setupFailure = "first-encode"
        return result
    }
    firstBuffer.commit()
    firstBuffer.waitUntilCompleted()
    guard firstBuffer.status == .completed, firstBuffer.error == nil else {
        result.setupFailure = "first-gpu-\(firstBuffer.status.rawValue)"
        return result
    }

    let previousStates = [effect: firstStage.transition.nextState]
    let previousResources = [effect: firstStage.persistentResources]
    guard let controlBuffer = queue.makeCommandBuffer() else { return result }
    let controlPreparation = executor.prepare(
        token: claim.token,
        leases: [normalLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(81),
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        dedicatedInputs: .init(),
        commandBuffer: controlBuffer,
        previousStates: previousStates,
        previousGraphResources: previousResources,
        effectGeneration: 1,
        resetGeneration: 1
    )
    result.noCallFailure = failureCode(controlPreparation)
    result.setupFailure = "ready"

    func prepareFailure(
        frameIndex: UInt64,
        request: SceneGraphMaterialFunctionInvocationRequest
    ) -> String {
        guard let buffer = queue.makeCommandBuffer() else { return "buffer" }
        return failureCode(executor.prepare(
            token: claim.token,
            leases: [functionLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(frameIndex),
            sourceTexture: makeSource(device, width: 2, height: 2),
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: buffer,
            previousStates: previousStates,
            previousGraphResources: previousResources,
            materialFunctionInvocations: [request],
            effectGeneration: 1,
            resetGeneration: 1
        ))
    }
    result.staleFailure = prepareFailure(
        frameIndex: 82,
        request: .init(effect: effect, functionName: "reset", frameEpoch: 81)
    )
    result.unknownEffectFailure = prepareFailure(
        frameIndex: 82,
        request: .init(
            effect: .init(
                layerID: layerID,
                effectIndex: 9,
                descriptorID: "unknown"
            ),
            functionName: "reset",
            frameEpoch: 82
        )
    )
    result.unknownFunctionFailure = prepareFailure(
        frameIndex: 82,
        request: .init(effect: effect, functionName: "missing", frameEpoch: 82)
    )

    let requests = [
        SceneGraphMaterialFunctionInvocationRequest(
            effect: effect,
            functionName: "reset",
            frameEpoch: 83
        ),
        SceneGraphMaterialFunctionInvocationRequest(
            effect: effect,
            functionName: "reset",
            frameEpoch: 83
        ),
    ]
    guard let failedBuffer = queue.makeCommandBuffer() else { return result }
    let failedPreparation = executor.prepare(
        token: claim.token,
        leases: [functionLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(83),
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        dedicatedInputs: .init(),
        commandBuffer: failedBuffer,
        previousStates: previousStates,
        previousGraphResources: previousResources,
        materialFunctionInvocations: requests,
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(failedPrepared) = failedPreparation else { return result }
    let failedEncode = executor.encodeResult(
        failedPrepared,
        commandBuffer: failedBuffer,
        functionClearObserver: { _, _, targetOrdinal, _ in targetOrdinal == 0 }
    )
    if case let .failure(failure) = failedEncode {
        result.encodeFailure = failure.rawValue
    }
    if let persistentTexture = firstStage.persistentResources[first]?
            .publication.texture,
       let preservationBuffer = queue.makeCommandBuffer(),
       let preservationReadback = appendReadback(
           persistentTexture,
           commandBuffer: preservationBuffer
       ) {
        preservationBuffer.commit()
        preservationBuffer.waitUntilCompleted()
        guard preservationBuffer.status == .completed,
              preservationBuffer.error == nil else { return result }
        result.failedEncodePreservedPixel = preservationReadback.firstPixel
    }

    let successfulRequests = requests.map {
        SceneGraphMaterialFunctionInvocationRequest(
            effect: $0.effect,
            functionName: $0.functionName,
            frameEpoch: 84
        )
    }
    guard let invokedBuffer = queue.makeCommandBuffer() else { return result }
    let invokedPreparation = executor.prepare(
        token: claim.token,
        leases: [functionLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(84),
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        dedicatedInputs: .init(),
        commandBuffer: invokedBuffer,
        previousStates: previousStates,
        previousGraphResources: previousResources,
        materialFunctionInvocations: successfulRequests,
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(invokedPrepared) = invokedPreparation,
          let invokedStage = invokedPrepared.stages.first else { return result }
    result.invocationIntentCount = invokedStage.transition.transaction.intents.filter {
        guard case let .initialize(_, _, reason) = $0,
              case .materialFunctionClear = reason else { return false }
        return true
    }.count
    guard executor.encode(invokedPrepared, commandBuffer: invokedBuffer),
          let invokedReadback = appendReadback(
              invokedPrepared.finalTexture,
              commandBuffer: invokedBuffer
          ) else { return result }
    invokedBuffer.commit()
    invokedBuffer.waitUntilCompleted()
    guard invokedBuffer.status == .completed, invokedBuffer.error == nil else {
        return result
    }
    result.invokedPixel = invokedReadback.firstPixel
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

private func launchEnvelopeFailureCode(
    _ result: Result<[UInt8], SceneResolvedMaterialVariantCache.LaunchEnvelopeFailure>
) -> String {
    switch result {
    case .success: return "success"
    case .failure(.capacity): return "capacity"
    case let .failure(.material(failure)):
        return "\(failure.phase.rawValue):\(failure.code.rawValue):\(failure.boundedDetails.joined(separator: ","))"
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
    namedProvider: SceneNamedTextureReference? = nil,
    dependencyBinding: SceneDependencyRenderPlan.Binding? = nil,
    functionsByEffect: [Graph.EffectKey: SceneJSONValue] = [:],
    assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:],
    assetFormatFacts: [String: Int] = [:]
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
    var consumer = SceneRenderDescriptor.Layer(
            id: graph.layerID,
            effects: graph.effects.map {
                .init(
                    id: $0.key.descriptorID,
                    file: $0.definitionPath,
                    visible: true,
                    passes: instancePasses[$0.key] ?? []
                )
            }
        )
    var layers: [SceneRenderDescriptor.Layer] = [consumer]
    if let namedProvider, let dependencyBinding {
        consumer.dependencyLayerIDs = [dependencyBinding.providerLayerID]
        consumer.namedReferences = [.init(
            consumerLayerID: graph.layerID,
            providerLayerID: namedProvider.providerLayerID,
            slot: dependencyBinding.slot,
            variant: namedProvider.variant
        )]
        consumer.namedBindings = [dependencyBinding]
        layers = [
            .init(id: dependencyBinding.providerLayerID, effects: []),
            consumer,
        ]
    }
    let descriptor = SceneRenderDescriptor(
        layers: layers,
        materialPasses: materialPasses,
        effectDefinitions: graph.effects.map {
            .init(
                relativePath: $0.definitionPath,
                functions: functionsByEffect[$0.key]
            )
        }
    )
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [graph]
    )
    return .init(
        admissionCandidates: candidates,
        materialCatalog: catalog,
        dynamicProducers: dynamicProducers,
        assetFormatFacts: assetFormatFacts,
        assetStates: assetStates
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

private struct CrossLayerRejectedPreparation {
    let failureCode: String
    let previousCurrentPreserved: Bool
    let safeSuffixCompleted: Bool
}

private func rejectedCrossLayerPreparation(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline,
    admittedGraph: AdmittedLayerGraph,
    capabilities: Capabilities,
    dependency: SceneDependencyEffectInput?
) -> CrossLayerRejectedPreparation {
    guard let claim = capabilities.claim(admittedGraph),
          let capability = capabilities.resolve(claim.token, for: admittedGraph),
          let leases = makeChainedLeases(capability, device: device, generation: 61),
          let firstStep = capability.pairPlan.effects.first,
          let executor = Executor(device: device, capabilities: capabilities),
          let command = queue.makeCommandBuffer() else {
        return .init(
            failureCode: "setup",
            previousCurrentPreserved: false,
            safeSuffixCompleted: false
        )
    }
    let previousCurrent = executor.pairTexture(
        lease: leases[0],
        member: firstStep.inputMember
    )
    guard fill(
        previousCurrent,
        color: MTLClearColorMake(0, 0, 1, 1),
        queue: queue
    ) else {
        return .init(
            failureCode: "fill",
            previousCurrentPreserved: false,
            safeSuffixCompleted: false
        )
    }
    let preparation = executor.prepare(
        token: claim.token,
        leases: leases,
        historyRehydrateCopiesByEffect: [:],
        frame: frame(60),
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        dedicatedInputs: .init(dependencyEffect: dependency),
        commandBuffer: command,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case .failure = preparation,
          let readback = appendReadback(previousCurrent, commandBuffer: command) else {
        return .init(
            failureCode: failureCode(preparation),
            previousCurrentPreserved: false,
            safeSuffixCompleted: false
        )
    }
    command.commit()
    command.waitUntilCompleted()
    let completed = command.status == .completed && command.error == nil
    return .init(
        failureCode: failureCode(preparation),
        previousCurrentPreserved: completed
            && readback.firstPixel == [255, 0, 0, 255],
        safeSuffixCompleted: completed
    )
}

@main
private enum Harness {
    static func main() throws {
        // This Metal harness owns GraphExecutor scheduling/readback assertions,
        // not the signed generic compiler bundle. Exercise the registered local
        // rollback explicitly instead of relying on an implicit bounded fallback
        // after a migrated generic-only profile cannot compile in this process.
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let source = makeSource(device)
        let sourcePipeline = makeSourcePipeline(device)
        let materialFunction = runMaterialFunctionScenario(
            device: device,
            queue: queue,
            sourcePipeline: sourcePipeline
        )

        let crossLayerGraph = graph(
            targets: [],
            nodes: [material(0, ordinal: 0, target: output, read: input)]
        )
        let crossLayerChain = admittedGraph(crossLayerGraph)
        let namedReference = SceneNamedTextureReference(
            providerLayerID: 879,
            variant: .primary
        )
        let externalBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: layerID,
            providerLayerID: namedReference.providerLayerID,
            slot: .init(
                effectID: effect.descriptorID,
                passIndex: 0,
                slotIndex: 1
            ),
            blendMode: 0,
            kind: .resolvedMaterial
        )
        let crossLayerCapabilities = capabilities(
            crossLayerChain,
            catalog: catalog(
                for: crossLayerGraph,
                namedProvidersByNode: [0: namedReference]
            ),
            namedProvider: namedReference,
            dependencyBinding: externalBinding
        )
        let crossLayerClaim = crossLayerCapabilities.claim(crossLayerChain)
        let crossLayerCapability = crossLayerClaim.flatMap {
            crossLayerCapabilities.resolve($0.token, for: crossLayerChain)
        }
        var crossLayerPrepared = false
        var crossLayerEncoded = false
        var crossLayerGPUCompleted = false
        var crossLayerProviderChangesPixels = false
        var crossLayerPixel: [UInt8] = []
        var crossLayerFailure = "setup"
        let providerTexture = makeSource(
            device,
            width: 2,
            height: 2,
            usage: [.shaderRead, .renderTarget],
            bgra: [0, 255, 0, 255]
        )
        let providerResource = SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: namedReference,
            frameEpoch: 60,
            texture: providerTexture
        )
        if let claim = crossLayerClaim,
           let capability = crossLayerCapability,
           let resource = providerResource,
           let leases = makeChainedLeases(capability, device: device, generation: 60),
           let executor = Executor(device: device, capabilities: crossLayerCapabilities),
           let command = queue.makeCommandBuffer() {
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(60),
                sourceTexture: makeSource(device, width: 2, height: 2),
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(dependencyEffect: .init(
                    frameEpoch: 60,
                    namedReference: namedReference,
                    reservedMaterialResource: resource
                )),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 1,
                resetGeneration: 1
            )
            crossLayerFailure = failureCode(preparation)
            if case let .success(prepared) = preparation,
               prepared.stages.count == 1,
               prepared.stages[0].programCacheKeys.count == 1,
               !prepared.stages[0].programCacheKeys[0].contains("passthrough") {
                crossLayerPrepared = true
                crossLayerEncoded = executor.encode(prepared, commandBuffer: command)
                if crossLayerEncoded,
                   let readback = appendReadback(
                    prepared.finalTexture,
                    commandBuffer: command
                   ) {
                    command.commit()
                    command.waitUntilCompleted()
                    crossLayerGPUCompleted = command.status == .completed
                        && command.error == nil
                    crossLayerPixel = readback.firstPixel
                    crossLayerProviderChangesPixels = crossLayerGPUCompleted
                        && matches(crossLayerPixel, [0, 128, 128, 255])
                        && !matches(crossLayerPixel, [0, 0, 255, 255])
                        && !matches(crossLayerPixel, [255, 255, 255, 255])
                }
            }
        }

        let missingProvider = rejectedCrossLayerPreparation(
            device: device,
            queue: queue,
            sourcePipeline: sourcePipeline,
            admittedGraph: crossLayerChain,
            capabilities: crossLayerCapabilities,
            dependency: nil
        )
        let wrongNamedReference = SceneNamedTextureReference(
            providerLayerID: namedReference.providerLayerID + 1,
            variant: .primary
        )
        let wrongProviderTexture = makeSource(
            device,
            width: 2,
            height: 2,
            usage: [.shaderRead, .renderTarget],
            bgra: [255, 0, 0, 255]
        )
        let wrongProviderResource = SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: wrongNamedReference,
            frameEpoch: 60,
            texture: wrongProviderTexture
        )
        let wrongProvider = rejectedCrossLayerPreparation(
            device: device,
            queue: queue,
            sourcePipeline: sourcePipeline,
            admittedGraph: crossLayerChain,
            capabilities: crossLayerCapabilities,
            dependency: .init(
                frameEpoch: 60,
                namedReference: wrongNamedReference,
                reservedMaterialResource: wrongProviderResource
            )
        )
        let secondaryReference = SceneNamedTextureReference(
            providerLayerID: namedReference.providerLayerID,
            variant: .secondary
        )
        let secondaryProvider = rejectedCrossLayerPreparation(
            device: device,
            queue: queue,
            sourcePipeline: sourcePipeline,
            admittedGraph: crossLayerChain,
            capabilities: crossLayerCapabilities,
            dependency: .init(
                frameEpoch: 60,
                namedReference: secondaryReference,
                reservedMaterialResource:
                    SceneFrameTextureResource.reservedNamedLayerTarget(
                        reference: secondaryReference,
                        frameEpoch: 60,
                        texture: providerTexture
                    )
            )
        )
        let staleResource = SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: namedReference,
            frameEpoch: 59,
            texture: providerTexture
        )
        let staleProvider = rejectedCrossLayerPreparation(
            device: device,
            queue: queue,
            sourcePipeline: sourcePipeline,
            admittedGraph: crossLayerChain,
            capabilities: crossLayerCapabilities,
            dependency: .init(
                frameEpoch: 59,
                namedReference: namedReference,
                reservedMaterialResource: staleResource
            )
        )
        func mismatchedOwnershipClaim(
            effectID: String,
            passIndex: Int,
            slotIndex: Int
        ) -> Bool {
            let binding = SceneDependencyRenderPlan.Binding(
                consumerLayerID: layerID,
                providerLayerID: namedReference.providerLayerID,
                slot: .init(
                    effectID: effectID,
                    passIndex: passIndex,
                    slotIndex: slotIndex
                ),
                blendMode: 0,
                kind: .resolvedMaterial
            )
            return capabilities(
                crossLayerChain,
                catalog: catalog(
                    for: crossLayerGraph,
                    namedProvidersByNode: [0: namedReference]
                ),
                namedProvider: namedReference,
                dependencyBinding: binding
            ).claim(crossLayerChain) != nil
        }
        let secondaryCapabilities = capabilities(
            crossLayerChain,
            catalog: catalog(
                for: crossLayerGraph,
                namedProvidersByNode: [0: secondaryReference]
            ),
            namedProvider: secondaryReference,
            dependencyBinding: externalBinding
        )

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
        let samplerSchemaPixelCapabilities = capabilities(
            pixelChain,
            catalog: catalog(
                for: pixelGraph,
                samplerSchemaInvalidNodes: [1]
            )
        )
        let samplerSchemaPixelClaim = samplerSchemaPixelCapabilities.claim(pixelChain)
        let samplerSchemaPixelCapability = samplerSchemaPixelClaim.flatMap {
            samplerSchemaPixelCapabilities.resolve($0.token, for: pixelChain)
        }
        let declarationConflictPixelCapabilities = capabilities(
            pixelChain,
            catalog: catalog(
                for: pixelGraph,
                uniformDeclarationConflictNodes: [1]
            )
        )
        let declarationConflictPixelClaim =
            declarationConflictPixelCapabilities.claim(pixelChain)
        let declarationConflictPixelCapability =
            declarationConflictPixelClaim.flatMap {
                declarationConflictPixelCapabilities.resolve($0.token, for: pixelChain)
            }
        let hostConflictPixelCapabilities = capabilities(
            pixelChain,
            catalog: catalog(
                for: pixelGraph,
                hostUniformDeclarationConflictNodes: [1]
            )
        )
        let hostConflictPixelClaim = hostConflictPixelCapabilities.claim(pixelChain)
        let hostConflictPixelCapability = hostConflictPixelClaim.flatMap {
            hostConflictPixelCapabilities.resolve($0.token, for: pixelChain)
        }
        let colorBlendCapabilities = capabilities(
            pixelChain,
            catalog: catalog(
                for: pixelGraph,
                colorBlendNodes: [1]
            ),
            assetStates: [colorBlendMaskIdentity: .ready(.data)],
            assetFormatFacts: [
                colorBlendMaskIdentity.reportToken:
                    SceneShaderTextureFormat.r8.macroValue,
            ]
        )
        let colorBlendClaim = colorBlendCapabilities.claim(pixelChain)
        let colorBlendCapability = colorBlendClaim.flatMap {
            colorBlendCapabilities.resolve($0.token, for: pixelChain)
        }
        let colorBlendMaterial = colorBlendCapability?.material(
            effect: chainedSecondEffect,
            nodeIndex: 1
        )
        let colorBlendSnapshot = colorBlendMaterial?.variants
            .launchEnvelopeCapabilitySnapshot()
        let colorBlendProfiles = colorBlendSnapshot?.variants.map {
            $0.routeDecision.profile
        } ?? []
        let colorBlendOptionalMaskProof = colorBlendMaterial?.variants
            .provesEffectLocalOptionalColorBlendTextureFailure(slot: 1) == true
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

        func executeVisualFailurePassthrough(
            claim: Capabilities.ClaimedLayer?,
            capability: Capabilities.LayerCapability?,
            capabilities: Capabilities,
            generation: UInt64,
            reason: String,
            textureEntries: [
                SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
            ] = [:]
        ) -> (
            prepared: Bool,
            encoded: Bool,
            gpuCompleted: Bool,
            continued: Bool,
            failureCode: String
        ) {
            guard let claim, let capability,
                  let leases = makeChainedLeases(
                      capability,
                      device: device,
                      generation: generation
                  ), let executor = Executor(
                      device: device,
                      capabilities: capabilities
                  ), let command = queue.makeCommandBuffer() else {
                return (false, false, false, false, "setup")
            }
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(
                    generation,
                    textureEntries: textureEntries
                ),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: generation,
                resetGeneration: generation
            )
            let preparationFailureCode = failureCode(preparation)
            guard case let .success(prepared) = preparation,
                  prepared.stages.count == 3,
                  prepared.stages[1].programCacheKeys == [
                      "visual-failure-passthrough:" + reason
                  ], prepared.stages[1].effectLocalFailureReasonCode == reason,
                  prepared.stages[0].programCacheKeys.allSatisfy({
                      !$0.hasPrefix("visual-failure-passthrough:")
                  }), prepared.stages[2].programCacheKeys.allSatisfy({
                      !$0.hasPrefix("visual-failure-passthrough:")
                  }), prepared.finalResource.publication.requestIdentity
                    == .graph(chainedFinalOutput) else {
                return (false, false, false, false, preparationFailureCode)
            }
            var observedStageIndices: [Int] = []
            var stageReadbacks: [Readback] = []
            let encoded = executor.encode(
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
            guard encoded,
                  let finalReadback = appendReadback(
                      prepared.finalTexture,
                      commandBuffer: command
                  ) else {
                return (true, encoded, false, false, preparationFailureCode)
            }
            command.commit()
            command.waitUntilCompleted()
            let expectedPixels: [[UInt8]] = [
                [255, 0, 0, 255],
                [255, 0, 0, 255],
                [0, 255, 0, 255],
            ]
            let continued = observedStageIndices == [0, 1, 2]
                && stageReadbacks.count == 3
                && zip(stageReadbacks, expectedPixels).allSatisfy {
                    matches($0.firstPixel, $1) && matches($0.lastPixel, $1)
                }
                && matches(finalReadback.firstPixel, expectedPixels[2])
                && matches(finalReadback.lastPixel, expectedPixels[2])
            return (
                true,
                encoded,
                command.status == .completed && command.error == nil,
                continued,
                preparationFailureCode
            )
        }

        let dynamicUniformFailure = executeVisualFailurePassthrough(
            claim: dynamicPixelClaim,
            capability: dynamicPixelCapability,
            capabilities: dynamicPixelCapabilities,
            generation: 5,
            reason: "material-finalizer-dynamic-uniform-binding"
        )

        let staticUniformFailure = executeVisualFailurePassthrough(
            claim: staticPixelClaim,
            capability: staticPixelCapability,
            capabilities: staticPixelCapabilities,
            generation: 7,
            reason: "material-finalizer-static-uniform-binding"
        )

        let samplerSchemaFailure = executeVisualFailurePassthrough(
            claim: samplerSchemaPixelClaim,
            capability: samplerSchemaPixelCapability,
            capabilities: samplerSchemaPixelCapabilities,
            generation: 8,
            reason: "material-variant-envelope-sampler-schema"
        )

        let hostConflictFailure = executeVisualFailurePassthrough(
            claim: hostConflictPixelClaim,
            capability: hostConflictPixelCapability,
            capabilities: hostConflictPixelCapabilities,
            generation: 9,
            reason: "material-finalizer-host-uniform-declaration-conflict"
        )
        let declarationConflictFailure = executeVisualFailurePassthrough(
            claim: declarationConflictPixelClaim,
            capability: declarationConflictPixelCapability,
            capabilities: declarationConflictPixelCapabilities,
            generation: 11,
            reason: "material-finalizer-uniform-declaration-conflict"
        )

        func colorBlendEntries(
            _ kind: ColorBlendMaskFixtureStatus,
            generation: UInt64
        ) -> [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] {
            [
                .asset(colorBlendMaskIdentity): colorBlendMaskStatus(
                    kind,
                    device: device,
                    generation: generation
                ),
            ]
        }

        let colorBlendPendingFailure = executeVisualFailurePassthrough(
            claim: colorBlendClaim,
            capability: colorBlendCapability,
            capabilities: colorBlendCapabilities,
            generation: 12,
            reason: "material-finalizer-optional-texture-unavailable",
            textureEntries: colorBlendEntries(.pending, generation: 12)
        )
        let colorBlendUnavailableFailure = executeVisualFailurePassthrough(
            claim: colorBlendClaim,
            capability: colorBlendCapability,
            capabilities: colorBlendCapabilities,
            generation: 13,
            reason: "material-finalizer-optional-texture-unavailable",
            textureEntries: colorBlendEntries(.unavailable, generation: 13)
        )
        let colorBlendWrongPurposeFailure = executeVisualFailurePassthrough(
            claim: colorBlendClaim,
            capability: colorBlendCapability,
            capabilities: colorBlendCapabilities,
            generation: 14,
            reason: "material-finalizer-optional-texture-purpose-mismatch",
            textureEntries: colorBlendEntries(.wrongPurpose, generation: 14)
        )
        let colorBlendWrongContentFailure = executeVisualFailurePassthrough(
            claim: colorBlendClaim,
            capability: colorBlendCapability,
            capabilities: colorBlendCapabilities,
            generation: 15,
            reason: "material-finalizer-optional-texture-content-mismatch",
            textureEntries: colorBlendEntries(.wrongContent, generation: 15)
        )
        let colorBlendSamplingFailure = executeVisualFailurePassthrough(
            claim: colorBlendClaim,
            capability: colorBlendCapability,
            capabilities: colorBlendCapabilities,
            generation: 16,
            reason: "material-finalizer-optional-texture-sampling-unresolved",
            textureEntries: colorBlendEntries(.samplingUnresolved, generation: 16)
        )

        func executeColorBlendReady(
            generation: UInt64,
            sourceTexture: MTLTexture,
            expectedPixels: [[UInt8]]?
        ) -> (
            prepared: Bool,
            encoded: Bool,
            gpuCompleted: Bool,
            visible: Bool,
            premultiplied: Bool
        ) {
            guard let claim = colorBlendClaim,
                  let capability = colorBlendCapability,
                  let leases = makeChainedLeases(
                    capability,
                    device: device,
                    generation: generation
                  ), let executor = Executor(
                    device: device,
                    capabilities: colorBlendCapabilities
                  ), let command = queue.makeCommandBuffer() else {
                return (false, false, false, false, false)
            }
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(
                    generation,
                    textureEntries: colorBlendEntries(.ready, generation: generation)
                ),
                sourceTexture: sourceTexture,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: generation,
                resetGeneration: generation
            )
            guard case let .success(prepared) = preparation,
                  prepared.stages.count == 3,
                  prepared.stages[1].effectLocalFailureReasonCode == nil,
                  prepared.stages.allSatisfy({ stage in
                      stage.programCacheKeys.allSatisfy {
                          !$0.hasPrefix("visual-failure-passthrough:")
                      }
                  }), prepared.finalResource.publication.requestIdentity
                    == .graph(chainedFinalOutput) else {
                return (false, false, false, false, false)
            }
            var observedStageIndices: [Int] = []
            var stageReadbacks: [Readback] = []
            let encoded = executor.encode(
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
            guard encoded,
                  let finalReadback = appendReadback(
                    prepared.finalTexture,
                    commandBuffer: command
                  ) else { return (true, encoded, false, false, false) }
            command.commit()
            command.waitUntilCompleted()
            let visible = observedStageIndices == [0, 1, 2]
                && stageReadbacks.count == 3
                && (expectedPixels.map { expected in
                    expected.count == 3
                        && zip(stageReadbacks, expected).allSatisfy {
                            matches($0.firstPixel, $1)
                                && matches($0.lastPixel, $1)
                        }
                        && matches(finalReadback.firstPixel, expected[2])
                        && matches(finalReadback.lastPixel, expected[2])
                } ?? true)
            let allReadbacks = stageReadbacks + [finalReadback]
            let premultiplied = allReadbacks.allSatisfy { readback in
                isPremultiplied(readback.firstPixel)
                    && isPremultiplied(readback.lastPixel)
            }
            return (
                true,
                encoded,
                command.status == .completed && command.error == nil,
                visible,
                premultiplied
            )
        }
        let colorBlendReady = executeColorBlendReady(
            generation: 19,
            sourceTexture: source,
            expectedPixels: [
                [255, 0, 0, 255],
                [0, 0, 255, 255],
                [255, 0, 0, 255],
            ]
        )
        let premultipliedSource = makeSource(
            device,
            width: 2,
            height: 2,
            pixelsBGRA: [
                0, 0, 0, 0,
                8, 16, 48, 64,
                16, 32, 96, 128,
                0, 0, 0, 0,
            ]
        )
        let colorBlendPremultiplied = executeColorBlendReady(
            generation: 20,
            sourceTexture: premultipliedSource,
            expectedPixels: nil
        )

        func colorBlendIntegrityFailureRemainsHard(
            _ kind: ColorBlendMaskFixtureStatus,
            generation: UInt64
        ) -> Bool {
            guard let claim = colorBlendClaim,
                  let capability = colorBlendCapability,
                  let leases = makeChainedLeases(
                    capability,
                    device: device,
                    generation: generation
                  ), let executor = Executor(
                    device: device,
                    capabilities: colorBlendCapabilities
                  ), let command = queue.makeCommandBuffer() else {
                return false
            }
            let preparation = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(
                    generation,
                    textureEntries: colorBlendEntries(kind, generation: generation)
                ),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: generation,
                resetGeneration: generation
            )
            guard case let .failure(.materialFinalizerRejected(
                stageIndex,
                effect,
                nodeIndex,
                materialOrdinal,
                failure
            )) = preparation else { return false }
            return stageIndex == 1
                && effect == chainedSecondEffect
                && nodeIndex == 1
                && materialOrdinal == 0
                && failure.phase == .texture
                && failure.code == .textureMetadataIncomplete
                && failure.slot == 1
                && failure.effectLocalVisualFallback == nil
                && command.status == .notEnqueued
        }
        let colorBlendGenerationMismatchRemainsHard =
            colorBlendIntegrityFailureRemainsHard(
                .generationMismatch,
                generation: 17
            )
        let colorBlendRequestIdentityMismatchRemainsHard =
            colorBlendIntegrityFailureRemainsHard(
                .requestIdentityMismatch,
                generation: 18
            )

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
        let commandVisualFailureGraph = graph(
            targets: [rawTarget(first), rawTarget(second)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                command(1, kind: .copy, source: first, target: second),
                material(2, ordinal: 1, target: output, read: second),
            ]
        )
        let commandVisualFailureChain = admittedGraph(commandVisualFailureGraph)
        let commandVisualFailureCapabilities = capabilities(
            commandVisualFailureChain,
            catalog: catalog(
                for: commandVisualFailureGraph,
                uniformSchemaInvalidNodes: [0]
            )
        )
        let commandDynamicTarget = dynamicUniformTarget(
            commandVisualFailureGraph.nodes[2]
        )
        let commandDynamicDefinition = SceneDynamicTargetDefinition(
            target: commandDynamicTarget,
            valueType: .scalar,
            authoredValue: .scalar(1)
        )
        let commandDynamicCapabilities = capabilities(
            commandVisualFailureChain,
            catalog: catalog(
                for: commandVisualFailureGraph,
                dynamicUniformNodes: [2]
            ),
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [commandDynamicTarget],
                sceneScriptTargets: []
            )
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
        let samplerSchemaMultiNodeCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(
                for: ordinaryGraph,
                samplerSchemaInvalidNodes: [0]
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
        let dynamicMultiTarget = dynamicUniformTarget(ordinaryGraph.nodes[1])
        let dynamicMultiCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(for: ordinaryGraph, dynamicUniformNodes: [1]),
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
        let declarationConflictMultiNodeCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(
                for: ordinaryGraph,
                uniformDeclarationConflictNodes: [0]
            )
        )
        let hostConflictMultiNodeCapabilities = capabilities(
            ordinaryChain,
            catalog: catalog(
                for: ordinaryGraph,
                hostUniformDeclarationConflictNodes: [0]
            )
        )
        func uniformMultiNodeFailure(
            _ capabilities: Capabilities,
            generation: UInt64
        ) -> String {
            guard let claim = capabilities.claim(ordinaryChain),
                  let executor = Executor(device: device, capabilities: capabilities),
                  let command = queue.makeCommandBuffer() else { return "not-claimed" }
            return failureCode(executor.prepare(
                token: claim.token,
                leases: [makeLease(
                    ordinaryPlan,
                    device: device,
                    generation: generation
                )],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(generation),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: generation,
                resetGeneration: generation
            ))
        }
        let dynamicUniformMultiNodeFailure = uniformMultiNodeFailure(
            dynamicMultiCapabilities,
            generation: 6
        )
        let dynamicUniformMultiNodeUsesWholeEffectPassthrough =
            dynamicUniformMultiNodeFailure == "success"
        let staticUniformMultiNodeFailure = uniformMultiNodeFailure(
            staticUniformMultiNodeCapabilities,
            generation: 8
        )
        let staticUniformMultiNodeUsesWholeEffectPassthrough =
            staticUniformMultiNodeFailure == "success"
        let hostConflictMultiNodeFailure = uniformMultiNodeFailure(
            hostConflictMultiNodeCapabilities,
            generation: 10
        )
        let hostConflictMultiNodeUsesWholeEffectPassthrough =
            hostConflictMultiNodeFailure == "success"
        let declarationConflictMultiNodeFailure = uniformMultiNodeFailure(
            declarationConflictMultiNodeCapabilities,
            generation: 12
        )
        let declarationConflictMultiNodeUsesWholeEffectPassthrough =
            declarationConflictMultiNodeFailure == "success"

        let dynamicMultiDefinition = SceneDynamicTargetDefinition(
            target: dynamicMultiTarget,
            valueType: .scalar,
            authoredValue: .scalar(1)
        )
        var fboVisualFailurePrepared = false
        var fboVisualFailureEncoded = false
        var fboVisualFailureGPUCompleted = false
        var fboVisualFailurePreservedPreviousCurrent = false
        var fboVisualFailureDiscardedUncommittedTargetState = false
        var fboVisualFailureRecoveredNextFrame = false
        if let claim = dynamicMultiCapabilities.claim(ordinaryChain),
           let capability = dynamicMultiCapabilities.resolve(
               claim.token,
               for: ordinaryChain
           ), let executor = Executor(
               device: device,
               capabilities: dynamicMultiCapabilities
           ), let firstCommand = queue.makeCommandBuffer() {
            let firstLease = makeLease(
                ordinaryPlan,
                device: device,
                generation: 30
            )
            let firstPreparation = executor.prepare(
                token: claim.token,
                leases: [firstLease],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(30),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: firstCommand,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 30,
                resetGeneration: 30
            )
            if case let .success(prepared) = firstPreparation,
               let stage = prepared.stages.first,
               stage.effectLocalFailureReasonCode
                    == "material-finalizer-dynamic-uniform-binding",
               stage.programCacheKeys == [
                   "visual-failure-passthrough:"
                       + "material-finalizer-dynamic-uniform-binding"
               ] {
                fboVisualFailurePrepared = true
                fboVisualFailureDiscardedUncommittedTargetState =
                    stage.transition.transaction.intents.isEmpty
                    && stage.transition.transaction.mappingBefore.isEmpty
                    && stage.transition.transaction.mappingAfter.isEmpty
                    && stage.transition.nextState.logicalMapping.isEmpty
                    && stage.transition.nextState.historyClosureIdentities.isEmpty
                    && stage.frameResources.isEmpty
                    && stage.persistentResources.isEmpty
                fboVisualFailureEncoded = executor.encode(
                    prepared,
                    commandBuffer: firstCommand
                )
                let readback = fboVisualFailureEncoded
                    ? appendReadback(
                        prepared.finalTexture,
                        commandBuffer: firstCommand
                    ) : nil
                firstCommand.commit()
                firstCommand.waitUntilCompleted()
                fboVisualFailureGPUCompleted = firstCommand.status == .completed
                    && firstCommand.error == nil
                fboVisualFailurePreservedPreviousCurrent = readback.map {
                    matches($0.firstPixel, [0, 0, 255, 255])
                        && matches($0.lastPixel, [0, 0, 255, 255])
                } ?? false

                if let recoveryCommand = queue.makeCommandBuffer() {
                    let recovery = executor.prepare(
                        token: claim.token,
                        leases: [makeLease(
                            ordinaryPlan,
                            device: device,
                            generation: 31
                        )],
                        historyRehydrateCopiesByEffect: [:],
                        frame: frame(
                            31,
                            dynamicDefinitions: [dynamicMultiDefinition],
                            timelineValues: [dynamicMultiTarget: .scalar(1)]
                        ),
                        sourceTexture: source,
                        sourceUniforms: .neutral(),
                        sourcePipeline: sourcePipeline,
                        dedicatedInputs: .init(),
                        commandBuffer: recoveryCommand,
                        previousStates: [effect: stage.transition.nextState],
                        previousGraphResources: [effect: [:]],
                        effectGeneration: 30,
                        resetGeneration: 30
                    )
                    if case let .success(recovered) = recovery,
                       let recoveredStage = recovered.stages.first {
                        fboVisualFailureRecoveredNextFrame =
                            recoveredStage.effectLocalFailureReasonCode == nil
                            && recoveredStage.programCacheKeys.count == 2
                            && !recoveredStage.transition.transaction.mappingAfter.isEmpty
                            && executor.encode(
                                recovered,
                                commandBuffer: recoveryCommand
                            )
                        recoveryCommand.commit()
                        recoveryCommand.waitUntilCompleted()
                        fboVisualFailureRecoveredNextFrame =
                            fboVisualFailureRecoveredNextFrame
                            && recoveryCommand.status == .completed
                            && recoveryCommand.error == nil
                    }
                }
            }
        }

        var commandVisualFailurePrepared = false
        var commandVisualFailureEncoded = false
        var commandVisualFailureGPUCompleted = false
        var commandVisualFailurePreservedPreviousCurrent = false
        var commandVisualFailureDiscardedPreparedPrefix = false
        var commandVisualFailureRecoveredNextFrame = false
        if let claim = commandDynamicCapabilities.claim(commandVisualFailureChain),
           let executor = Executor(
               device: device,
               capabilities: commandDynamicCapabilities
           ), let firstCommand = queue.makeCommandBuffer() {
            let plan = requirePlan(commandVisualFailureGraph)
            let preparation = executor.prepare(
                token: claim.token,
                leases: [makeLease(plan, device: device, generation: 32)],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(32),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: firstCommand,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 32,
                resetGeneration: 32
            )
            if case let .success(prepared) = preparation,
               let stage = prepared.stages.first,
               stage.effectLocalFailureReasonCode
                    == "material-finalizer-dynamic-uniform-binding",
               stage.programCacheKeys == [
                   "visual-failure-passthrough:"
                       + "material-finalizer-dynamic-uniform-binding"
               ] {
                commandVisualFailurePrepared = true
                commandVisualFailureDiscardedPreparedPrefix =
                    stage.transition.transaction.intents.isEmpty
                    && stage.transition.transaction.mappingBefore.isEmpty
                    && stage.transition.transaction.mappingAfter.isEmpty
                    && stage.transition.nextState.logicalMapping.isEmpty
                    && stage.frameResources.isEmpty
                    && stage.persistentResources.isEmpty
                commandVisualFailureEncoded = executor.encode(
                    prepared,
                    commandBuffer: firstCommand
                )
                let readback = commandVisualFailureEncoded
                    ? appendReadback(
                        prepared.finalTexture,
                        commandBuffer: firstCommand
                    ) : nil
                firstCommand.commit()
                firstCommand.waitUntilCompleted()
                commandVisualFailureGPUCompleted =
                    firstCommand.status == .completed && firstCommand.error == nil
                commandVisualFailurePreservedPreviousCurrent = readback.map {
                    matches($0.firstPixel, [0, 0, 255, 255])
                        && matches($0.lastPixel, [0, 0, 255, 255])
                } ?? false

                if let recoveryCommand = queue.makeCommandBuffer() {
                    let recovery = executor.prepare(
                        token: claim.token,
                        leases: [makeLease(
                            plan,
                            device: device,
                            generation: 33
                        )],
                        historyRehydrateCopiesByEffect: [:],
                        frame: frame(
                            33,
                            dynamicDefinitions: [commandDynamicDefinition],
                            timelineValues: [commandDynamicTarget: .scalar(1)]
                        ),
                        sourceTexture: source,
                        sourceUniforms: .neutral(),
                        sourcePipeline: sourcePipeline,
                        dedicatedInputs: .init(),
                        commandBuffer: recoveryCommand,
                        previousStates: [effect: stage.transition.nextState],
                        previousGraphResources: [effect: [:]],
                        effectGeneration: 32,
                        resetGeneration: 32
                    )
                    if case let .success(recovered) = recovery,
                       let recoveredStage = recovered.stages.first {
                        commandVisualFailureRecoveredNextFrame =
                            recoveredStage.effectLocalFailureReasonCode == nil
                            && recoveredStage.programCacheKeys.count == 2
                            && intentKinds(recovered) == [
                                "material", "copy", "material",
                            ]
                            && executor.encode(
                                recovered,
                                commandBuffer: recoveryCommand
                            )
                        recoveryCommand.commit()
                        recoveryCommand.waitUntilCompleted()
                        commandVisualFailureRecoveredNextFrame =
                            commandVisualFailureRecoveredNextFrame
                            && recoveryCommand.status == .completed
                            && recoveryCommand.error == nil
                    }
                }
            }
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
            unprovenProducer: Bool = false,
            expectedCode: String = "r8-scalar-graph-unproven"
        ) -> Bool {
            let chain = admittedGraph(candidateGraph)
            let candidateCapabilities = capabilities(
                chain,
                catalog: catalog(
                    for: candidateGraph,
                    scalarProducerUnprovenNodes: unprovenProducer ? [0] : [],
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
        let scalarConditionalWriterGraph = scalarConsumerGraph()
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
        let rgbaRepeatGraph = graph(
            targets: [rawTarget(first, uvs: .string("repeat"))],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )

        func addressProbe(
            _ graph: Graph,
            scalar: Bool,
            expectedSampling: SceneTextureSampling,
            generation: UInt64
        ) -> (
            executed: Bool,
            publicationMatches: Bool,
            first: [UInt8],
            last: [UInt8]
        ) {
            let chain = admittedGraph(graph)
            let capabilitySet = capabilities(
                chain,
                catalog: catalog(
                    for: graph,
                    scalarConsumerNodes: scalar ? [1: "red"] : [:],
                    repeatProbeNodes: [1]
                )
            )
            guard let claim = capabilitySet.claim(chain),
                  let executor = Executor(
                      device: device,
                      capabilities: capabilitySet
                  ), let command = queue.makeCommandBuffer() else {
                return (false, false, [], [])
            }
            let lease = makeLease(
                requirePlan(graph),
                device: device,
                generation: generation
            )
            let pattern = makeSource(
                device,
                width: 2,
                height: 2,
                pixelsBGRA: [
                    0, 0, 64, 255,
                    0, 0, 128, 255,
                    0, 0, 192, 255,
                    0, 0, 255, 255,
                ]
            )
            let preparation = executor.prepare(
                token: claim.token,
                leases: [lease],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(generation),
                sourceTexture: pattern,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: generation,
                resetGeneration: generation
            )
            guard case let .success(prepared) = preparation,
                  let stage = prepared.stages.first,
                  let publication = stage.frameResources[first] else {
                return (false, false, [], [])
            }
            let publicationMatches = stage.programCacheKeys.count == 2
                && publication.publication.requestIdentity == .graph(first)
                && publication.publication.candidate.sampling
                    == expectedSampling
                && publication.publication.candidate.sampling.rawFlags == nil
                && (scalar
                    ? publication.publication.candidate.content
                        == .scalarRedUnorm
                    : publication.publication.candidate.content
                        != .scalarRedUnorm)
            let encoded = executor.encode(prepared, commandBuffer: command)
            guard let readback = appendReadback(
                prepared.finalTexture,
                commandBuffer: command
            ) else { return (false, publicationMatches, [], []) }
            command.commit()
            command.waitUntilCompleted()
            return (
                encoded && command.status == .completed && command.error == nil,
                publicationMatches,
                readback.firstPixel,
                readback.lastPixel
            )
        }

        let rgbaClampProbe = addressProbe(
            ordinaryGraph,
            scalar: false,
            expectedSampling: .linearClamp,
            generation: 81
        )
        let rgbaRepeatProbe = addressProbe(
            rgbaRepeatGraph,
            scalar: false,
            expectedSampling: .linearRepeat,
            generation: 82
        )
        let scalarClampProbe = addressProbe(
            scalarGraph,
            scalar: true,
            expectedSampling: .linearClamp,
            generation: 83
        )
        let scalarRepeatProbe = addressProbe(
            scalarRepeatGraph,
            scalar: true,
            expectedSampling: .linearRepeat,
            generation: 84
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
        let genericComposeGraph = graph(
            targets: [],
            nodes: [
                material(
                    0,
                    ordinal: 0,
                    target: output,
                    read: input,
                    compose: .bool(true)
                ),
                material(1, ordinal: 1, target: output, read: input),
            ]
        )
        let genericComposeChain = admittedGraph(genericComposeGraph)
        let genericComposeCapabilities = capabilities(
            genericComposeChain,
            catalog: catalog(
                for: genericComposeGraph,
                pixelTransformsByNode: [0: 1]
            )
        )
        guard let genericComposeClaim = genericComposeCapabilities.claim(
                  genericComposeChain
              ),
              let genericComposeCapability = genericComposeCapabilities.resolve(
                  genericComposeClaim.token,
                  for: genericComposeChain
              ),
              let genericComposeExecutor = Executor(
                  device: device,
                  capabilities: genericComposeCapabilities
              ),
              let genericComposeLease = makeChainedLeases(
                  genericComposeCapability,
                  device: device
              )?.first else {
            fatalError(
                "generic compose setup failed: "
                    + genericComposeCapabilities.reportLines.joined(separator: " | ")
            )
        }
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
        let nonzeroClearGraph = graph(
            targets: [rawTarget(first, clear: .string("1 0 0 0"))],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let uniqueVisualFailureGraph = graph(
            targets: [rawTarget(first, unique: true)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let readBeforeWriteVisualFailureGraph = graph(
            targets: [rawTarget(first), rawTarget(second)],
            nodes: [
                material(0, ordinal: 0, target: first, read: second),
                material(1, ordinal: 1, target: second, read: input),
                material(2, ordinal: 2, target: output, read: first),
            ]
        )
        let unusedTargetVisualFailureGraph = graph(
            targets: [rawTarget(first), rawTarget(second)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: second, read: input),
                material(2, ordinal: 2, target: output, read: first),
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
        let nonzeroClearCapabilities = capabilities(
            admittedGraph(nonzeroClearGraph),
            catalog: catalog(for: nonzeroClearGraph)
        )
        let clearVisualFailureCapabilities = capabilities(
            admittedGraph(nonzeroClearGraph),
            catalog: catalog(
                for: nonzeroClearGraph,
                uniformSchemaInvalidNodes: [0]
            )
        )
        let uniqueVisualFailureCapabilities = capabilities(
            admittedGraph(uniqueVisualFailureGraph),
            catalog: catalog(
                for: uniqueVisualFailureGraph,
                uniformSchemaInvalidNodes: [0]
            )
        )
        let readBeforeWriteVisualFailureCapabilities = capabilities(
            admittedGraph(readBeforeWriteVisualFailureGraph),
            catalog: catalog(
                for: readBeforeWriteVisualFailureGraph,
                uniformSchemaInvalidNodes: [0]
            )
        )
        let unusedTargetVisualFailureCapabilities = capabilities(
            admittedGraph(unusedTargetVisualFailureGraph),
            catalog: catalog(
                for: unusedTargetVisualFailureGraph,
                uniformSchemaInvalidNodes: [0]
            )
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

        guard let genericComposeBuffer = queue.makeCommandBuffer() else {
            fatalError("generic compose buffer unavailable")
        }
        let genericComposePreparation = genericComposeExecutor.prepare(
            token: genericComposeClaim.token,
            leases: [genericComposeLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(3),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            dedicatedInputs: .init(),
            commandBuffer: genericComposeBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        let genericComposeAppended: Bool
        var genericComposePublicationContract = false
        var genericComposeReadback: Readback?
        var genericComposeProgramKeys: [String] = []
        if case let .success(value) = genericComposePreparation {
            let stage = value.stages[0]
            genericComposeProgramKeys = stage.programCacheKeys
            let firstPairNode = stage.pairStep.nodes[0]
            let secondPairNode = stage.pairStep.nodes[1]
            genericComposePublicationContract = value.stages.count == 1
                && stage.programCacheKeys.count == 2
                && stage.programCacheKeys.allSatisfy {
                    !$0.hasPrefix("dedicated:")
                }
                && stage.persistentResources.isEmpty
                && intentKinds(value) == ["material", "material"]
                && genericComposeLease.table.plan.logicalTargets.isEmpty
                && genericComposeLease.table.inputOutputAliased
                && genericComposeLease.table.inputTexture
                    === genericComposeLease.table.outputTexture
                && genericComposeLease.table.fullFramePair.first
                    !== genericComposeLease.table.fullFramePair.second
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
                    === genericComposeLease.table.outputTexture
                && value.finalResource.publication.isSameAtom(
                    as: stage.effectOutputResource.publication
                )
            genericComposeAppended = genericComposeExecutor.encode(
                value,
                commandBuffer: genericComposeBuffer
            )
                && stage.pairStep.composeTransitionCount == 1
                && stage.pairStep.inputMember == .zero
                && stage.pairStep.outputMember == .zero
                && value.finalTexture
                    === genericComposeLease.table.fullFramePair.first
            genericComposeReadback = appendReadback(
                value.finalTexture,
                commandBuffer: genericComposeBuffer
            )
        } else {
            genericComposeAppended = false
        }
        genericComposeBuffer.commit()
        genericComposeBuffer.waitUntilCompleted()
        let genericComposeEncoded = genericComposeAppended
            && genericComposeBuffer.status == .completed
            && genericComposeBuffer.error == nil
        let genericComposePixelsPreserved = genericComposeReadback.map {
            matches($0.firstPixel, [255, 0, 0, 255])
                && matches($0.lastPixel, [255, 0, 0, 255])
        } ?? false

        func executeGenericComposeFailure(
            preparedKey: String?,
            generation: UInt64
        ) -> (prepared: Bool, encoded: Bool, gpu: Bool, restored: Bool) {
            guard let preparedKey,
                  let lease = makeChainedLeases(
                      genericComposeCapability,
                      device: device,
                      generation: generation
                  )?.first,
                  let executor = Executor(
                      device: device,
                      capabilities: genericComposeCapabilities
                  ), let command = queue.makeCommandBuffer() else {
                return (false, false, false, false)
            }
            executor.materialEncoder.installTestingPreparationFailure(
                .libraryCompilationRejected(diagnostic: "compose-fixture"),
                preparedKey: preparedKey
            )
            let preparation = executor.prepare(
                token: genericComposeClaim.token,
                leases: [lease],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(generation),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: generation,
                resetGeneration: generation
            )
            let reason = "material-pass-preparation-library-compilation"
            guard case let .success(prepared) = preparation,
                  prepared.stages.count == 1,
                  prepared.stages[0].programCacheKeys == [
                      "visual-failure-passthrough:" + reason
                  ],
                  prepared.stages[0].effectLocalFailureReasonCode == reason,
                  prepared.stages[0].effectOutputResource.publication.texture
                      === lease.table.fullFramePair.first,
                  prepared.finalResource.publication.isSameAtom(
                      as: prepared.stages[0].effectOutputResource.publication
                  ) else { return (false, false, false, false) }
            let encoded = executor.encode(prepared, commandBuffer: command)
            guard encoded,
                  let readback = appendReadback(
                      prepared.finalTexture,
                      commandBuffer: command
                  ) else { return (true, encoded, false, false) }
            command.commit()
            command.waitUntilCompleted()
            let gpu = command.status == .completed && command.error == nil
            let restored = matches(readback.firstPixel, [0, 0, 255, 255])
                && matches(readback.lastPixel, [0, 0, 255, 255])
            return (true, encoded, gpu, restored)
        }

        let genericComposeFirstFailure = executeGenericComposeFailure(
            preparedKey: genericComposeProgramKeys.first,
            generation: 23
        )
        let genericComposeSecondFailure = executeGenericComposeFailure(
            preparedKey: genericComposeProgramKeys.last,
            generation: 24
        )

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
        guard case let .success(boundedCache) =
                SceneResolvedMaterialVariantCache.launchValidated(
            template: cacheTemplate,
            maximumVariantCount: 1
        ) else { fatalError("bounded cache rejected") }
        let boundedLaunch = boundedCache.precompileLaunchEnvelope(
            implicitFramebufferIdentity: input
        )
        let boundedCountsAfterLaunch = boundedCache.counters
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
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                implicitFramebufferIdentity: input
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
        let unplannedVariant = boundedCache.resolve(
            absentVariantFrame.finalizationInput(
                template: cacheTemplate,
                renderSize: CGSize(width: extent.width, height: extent.height),
                modelViewProjection: Executor.fullTargetMVP(firstTexture),
                layerModelMatrix: matrix_identity_float4x4,
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                implicitFramebufferIdentity: input
            )
        )
        let unplannedVariantRejectedWithoutCompilation: Bool = {
            guard case .success = boundedLaunch,
                  case .success = readyVariant,
                  case let .failure(failure) = unplannedVariant else {
                return false
            }
            return failure.phase == .invariant
                && failure.code == .variantSelectionKeyInvariant
                && boundedCache.counters == boundedCountsAfterLaunch
                && boundedCache.counters.capacityRejectionCount == 0
        }()

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
        guard case let .success(failingVariantCache) =
                SceneResolvedMaterialVariantCache.launchValidated(
            template: failingTemplate,
            maximumVariantCount: 1
        ) else { fatalError("failing cache rejected") }
        let firstFailedVariant = failingVariantCache.precompileLaunchEnvelope(
            implicitFramebufferIdentity: input
        )
        let failedCountsAfterFirst = failingVariantCache.counters
        let secondFailedVariant = failingVariantCache.precompileLaunchEnvelope(
            implicitFramebufferIdentity: input
        )
        let failedCountsAfterSecond = failingVariantCache.counters
        let failedVariantRejectionIsCached: Bool = {
            guard case let .failure(.material(firstFailure)) = firstFailedVariant,
                  case let .failure(.material(secondFailure)) = secondFailedVariant else {
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
        let mixedVisualFailureTarget = dynamicUniformTarget(mixedGraph.nodes[4])
        let mixedVisualFailureCapabilities = capabilities(
            mixedChain,
            catalog: catalog(
                for: mixedGraph,
                dynamicUniformNodes: [4]
            ),
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [mixedVisualFailureTarget],
                sceneScriptTargets: []
            )
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
        var mixedVisualFailureRollsBackWholeEffect = false
        if let claim = mixedVisualFailureCapabilities.claim(mixedChain),
           let executor = Executor(
               device: device,
               capabilities: mixedVisualFailureCapabilities
           ), let command = queue.makeCommandBuffer() {
            let preparation = executor.prepare(
                token: claim.token,
                leases: [makeLease(
                    requirePlan(mixedGraph),
                    device: device,
                    generation: 34
                )],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(34),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 34,
                resetGeneration: 34
            )
            if case let .success(prepared) = preparation,
               let stage = prepared.stages.first,
               stage.effectLocalFailureReasonCode
                    == "material-finalizer-dynamic-uniform-binding",
               stage.programCacheKeys == [
                   "visual-failure-passthrough:"
                       + "material-finalizer-dynamic-uniform-binding"
               ],
               stage.transition.transaction.intents.isEmpty,
               stage.transition.transaction.mappingBefore.isEmpty,
               stage.transition.transaction.mappingAfter.isEmpty,
               stage.transition.nextState.logicalMapping.isEmpty,
               stage.frameResources.isEmpty,
               stage.persistentResources.isEmpty,
               executor.encode(prepared, commandBuffer: command),
               let readback = appendReadback(
                   prepared.finalTexture,
                   commandBuffer: command
               ) {
                command.commit()
                command.waitUntilCompleted()
                mixedVisualFailureRollsBackWholeEffect =
                    command.status == .completed
                    && command.error == nil
                    && matches(readback.firstPixel, [0, 0, 255, 255])
                    && matches(readback.lastPixel, [0, 0, 255, 255])
            }
        }

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
        let swapMismatchChain = admittedGraph(swapMismatchGraph)
        let swapMismatchCapabilities = capabilities(
            swapMismatchChain,
            catalog: catalog(for: swapMismatchGraph)
        )
        let swapMismatchRejectedBeforeFrame = swapMismatchCapabilities.claim(
            swapMismatchChain
        ) == nil && swapMismatchCapabilities.reportLines.contains {
            $0.contains("rejection: swap-target-descriptor-incompatible count=1")
        }

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
            "crossLayerExactOwnershipClaimed": {
                guard let capability = crossLayerCapability,
                      case let .externalPrimary(binding) =
                        capability.dependencyOwnership else { return false }
                return binding == externalBinding
            }(),
            "crossLayerPreparedUnifiedProgram": crossLayerFailure == "success"
                && crossLayerPrepared,
            "crossLayerEncodedAndGPUCompleted": crossLayerEncoded
                && crossLayerGPUCompleted,
            "crossLayerProviderPixelsReachOutputWithoutWhiteFallback":
                crossLayerProviderChangesPixels,
            "crossLayerMissingProviderRejectedAtomically":
                missingProvider.failureCode != "success"
                    && missingProvider.previousCurrentPreserved
                    && missingProvider.safeSuffixCompleted,
            "crossLayerWrongProviderRejectedAtomically":
                wrongProvider.failureCode != "success"
                    && wrongProvider.previousCurrentPreserved
                    && wrongProvider.safeSuffixCompleted,
            "crossLayerSecondaryRejectedAtomically":
                secondaryProvider.failureCode
                    == Executor.Failure.graphPublicationRejected.rawValue
                    && secondaryProvider.previousCurrentPreserved
                    && secondaryProvider.safeSuffixCompleted,
            "crossLayerStaleEpochRejectedAtomically":
                staleProvider.failureCode
                    == Executor.Failure.graphPublicationRejected.rawValue
                    && staleProvider.previousCurrentPreserved
                    && staleProvider.safeSuffixCompleted,
            "crossLayerWrongEffectOwnershipRejectedBeforeFrame":
                !mismatchedOwnershipClaim(
                    effectID: effect.descriptorID + "-wrong",
                    passIndex: 0,
                    slotIndex: 1
                ),
            "crossLayerWrongPassOwnershipRejectedBeforeFrame":
                !mismatchedOwnershipClaim(
                    effectID: effect.descriptorID,
                    passIndex: 1,
                    slotIndex: 1
                ),
            "crossLayerWrongSlotOwnershipRejectedBeforeFrame":
                !mismatchedOwnershipClaim(
                    effectID: effect.descriptorID,
                    passIndex: 0,
                    slotIndex: 0
                ),
            "crossLayerSecondaryCannotClaim":
                secondaryCapabilities.claim(crossLayerChain) == nil,
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
                            "rejection: material-variant-envelope-invariant count=1"
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
            "rgbaClampProbeExecutes": rgbaClampProbe.executed,
            "rgbaClampPublicationIsTyped": rgbaClampProbe.publicationMatches,
            "rgbaClampProbeClampsOutOfRangeUV": matches(
                rgbaClampProbe.first,
                [0, 0, 255, 255]
            ) && matches(rgbaClampProbe.last, [0, 0, 255, 255]),
            "rgbaRepeatProbeExecutes": rgbaRepeatProbe.executed,
            "rgbaRepeatPublicationIsTyped": rgbaRepeatProbe.publicationMatches,
            "rgbaRepeatProbeWrapsOutOfRangeUV": matches(
                rgbaRepeatProbe.first,
                [0, 0, 64, 255]
            ) && matches(rgbaRepeatProbe.last, [0, 0, 255, 255]),
            "nonzeroClearAdmittedBeforeFrame": nonzeroClearCapabilities.claim(
                admittedGraph(nonzeroClearGraph)
            ) != nil,
            "authoredClearVisualFailureRemainsHardRejected":
                clearVisualFailureCapabilities.claim(
                    admittedGraph(nonzeroClearGraph)
                ) == nil,
            "uniqueTargetVisualFailureRemainsHardRejected":
                uniqueVisualFailureCapabilities.claim(
                    admittedGraph(uniqueVisualFailureGraph)
                ) == nil,
            "readBeforeWriteHistoryVisualFailureRemainsHardRejected":
                readBeforeWriteVisualFailureCapabilities.claim(
                    admittedGraph(readBeforeWriteVisualFailureGraph)
                ) == nil,
            "unusedTargetVisualFailureRemainsHardRejected":
                unusedTargetVisualFailureCapabilities.claim(
                    admittedGraph(unusedTargetVisualFailureGraph)
                ) == nil,
            "commandGraphLaunchVisualFailureCanClaimWholeEffectPassthrough":
                commandVisualFailureCapabilities.claim(
                    admittedGraph(commandVisualFailureGraph)
                ) != nil,
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
            "scalarConditionalWriterUsesWholeEffectPassthrough": {
                let chain = admittedGraph(scalarConditionalWriterGraph)
                let values = capabilities(
                    chain,
                    catalog: catalog(
                        for: scalarConditionalWriterGraph,
                        scalarProducerUnprovenNodes: [0],
                        scalarConsumerNodes: [1: "red"]
                    )
                )
                guard let claim = values.claim(chain),
                      let capability = values.resolve(claim.token, for: chain)
                else { return false }
                return capability.stages.first?.visualFailureReasonCode
                    == "material-variant-envelope-color-contract"
            }(),
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
            "scalarClampProbeExecutes": scalarClampProbe.executed,
            "scalarClampPublicationIsTyped": scalarClampProbe.publicationMatches,
            "scalarClampProbeClampsOutOfRangeUV": matches(
                scalarClampProbe.first,
                [0, 0, 255, 255]
            ) && matches(scalarClampProbe.last, [0, 0, 255, 255]),
            "scalarRepeatProbeExecutes": scalarRepeatProbe.executed,
            "scalarRepeatPublicationIsTyped": scalarRepeatProbe.publicationMatches,
            "scalarRepeatProbeWrapsOutOfRangeUV": matches(
                scalarRepeatProbe.first,
                [0, 0, 64, 255]
            ) && matches(scalarRepeatProbe.last, [0, 0, 255, 255]),
            "orderedStagesPreparedTogether": chainedStagesPrepared,
            "orderedStagesEncodedTogether": chainedStagesEncoded,
            "orderedStagesGPUCompleted": chainedStagesGPUCompleted,
            "orderedStagesPreservePriorPixelContribution":
                chainedStagePixelsPreserved,
            "dynamicUniformValidFramePreparesProgram":
                dynamicUniformValidFramePrepares,
            "dynamicUniformFailurePassthroughPrepared":
                dynamicUniformFailure.prepared,
            "dynamicUniformFailurePassthroughEncoded":
                dynamicUniformFailure.encoded,
            "dynamicUniformFailurePassthroughGPUCompleted":
                dynamicUniformFailure.gpuCompleted,
            "dynamicUniformFailurePreservesPreviousAndContinuesSuffix":
                dynamicUniformFailure.continued,
            "staticUniformFailurePassthroughPrepared":
                staticUniformFailure.prepared,
            "staticUniformFailurePassthroughEncoded":
                staticUniformFailure.encoded,
            "staticUniformFailurePassthroughGPUCompleted":
                staticUniformFailure.gpuCompleted,
            "staticUniformFailurePreservesPreviousAndContinuesSuffix":
                staticUniformFailure.continued,
            "samplerSchemaFailurePassthroughPrepared":
                samplerSchemaFailure.prepared,
            "samplerSchemaFailurePassthroughEncoded":
                samplerSchemaFailure.encoded,
            "samplerSchemaFailurePassthroughGPUCompleted":
                samplerSchemaFailure.gpuCompleted,
            "samplerSchemaFailurePreservesPreviousAndContinuesSuffix":
                samplerSchemaFailure.continued,
            "hostConflictFailurePassthroughPrepared":
                hostConflictFailure.prepared,
            "hostConflictFailurePassthroughEncoded":
                hostConflictFailure.encoded,
            "hostConflictFailurePassthroughGPUCompleted":
                hostConflictFailure.gpuCompleted,
            "hostConflictFailurePreservesPreviousAndContinuesSuffix":
                hostConflictFailure.continued,
            "declarationConflictFailurePassthroughPrepared":
                declarationConflictFailure.prepared,
            "declarationConflictFailurePassthroughEncoded":
                declarationConflictFailure.encoded,
            "declarationConflictFailurePassthroughGPUCompleted":
                declarationConflictFailure.gpuCompleted,
            "declarationConflictFailurePreservesPreviousAndContinuesSuffix":
                declarationConflictFailure.continued,
            "colorBlendMaskPendingPassthroughPrepared":
                colorBlendPendingFailure.prepared,
            "colorBlendReadyPrepared": colorBlendReady.prepared,
            "colorBlendReadyEncoded": colorBlendReady.encoded,
            "colorBlendReadyGPUCompleted": colorBlendReady.gpuCompleted,
            "colorBlendReadyChangesPixelsAndPublishesFinal":
                colorBlendReady.visible,
            "colorBlendReadyPreservesPremultipliedBoundary":
                colorBlendReady.premultiplied,
            "colorBlendTransparentAndPartialAlphaStayPremultiplied":
                colorBlendPremultiplied.prepared
                    && colorBlendPremultiplied.encoded
                    && colorBlendPremultiplied.gpuCompleted
                    && colorBlendPremultiplied.visible
                    && colorBlendPremultiplied.premultiplied,
            "colorBlendOptionalMaskLaunchEnvelopeProved":
                colorBlendOptionalMaskProof
                    && colorBlendSnapshot?.variants.count == 2
                    && colorBlendSnapshot?.allEntriesReady == true
                    && Set(colorBlendProfiles) == [
                        SceneGenericShaderCapabilityProfile
                            .sourceProvenGraphInputColorBlend.rawValue,
                    ],
            "colorBlendMaskPendingPassthroughEncoded":
                colorBlendPendingFailure.encoded,
            "colorBlendMaskPendingGPUCompleted":
                colorBlendPendingFailure.gpuCompleted,
            "colorBlendMaskPendingPreservesPreviousAndContinuesSuffix":
                colorBlendPendingFailure.continued,
            "colorBlendMaskUnavailableIsEffectLocal":
                colorBlendUnavailableFailure.prepared
                    && colorBlendUnavailableFailure.encoded
                    && colorBlendUnavailableFailure.gpuCompleted
                    && colorBlendUnavailableFailure.continued,
            "colorBlendMaskWrongPurposeIsEffectLocal":
                colorBlendWrongPurposeFailure.prepared
                    && colorBlendWrongPurposeFailure.encoded
                    && colorBlendWrongPurposeFailure.gpuCompleted
                    && colorBlendWrongPurposeFailure.continued,
            "colorBlendMaskWrongContentIsEffectLocal":
                colorBlendWrongContentFailure.prepared
                    && colorBlendWrongContentFailure.encoded
                    && colorBlendWrongContentFailure.gpuCompleted
                    && colorBlendWrongContentFailure.continued,
            "colorBlendMaskSamplingFailureIsEffectLocal":
                colorBlendSamplingFailure.prepared
                    && colorBlendSamplingFailure.encoded
                    && colorBlendSamplingFailure.gpuCompleted
                    && colorBlendSamplingFailure.continued,
            "colorBlendMaskGenerationMismatchRemainsHard":
                colorBlendGenerationMismatchRemainsHard,
            "colorBlendMaskRequestIdentityMismatchRemainsHard":
                colorBlendRequestIdentityMismatchRemainsHard,
            "dynamicUniformMultiNodeUsesWholeEffectPassthrough":
                dynamicUniformMultiNodeUsesWholeEffectPassthrough,
            "staticUniformMultiNodeUsesWholeEffectPassthrough":
                staticUniformMultiNodeUsesWholeEffectPassthrough,
            "hostConflictMultiNodeUsesWholeEffectPassthrough":
                hostConflictMultiNodeUsesWholeEffectPassthrough,
            "declarationConflictMultiNodeUsesWholeEffectPassthrough":
                declarationConflictMultiNodeUsesWholeEffectPassthrough,
            "fboVisualFailurePassthroughPrepared": fboVisualFailurePrepared,
            "fboVisualFailurePassthroughEncoded": fboVisualFailureEncoded,
            "fboVisualFailurePassthroughGPUCompleted":
                fboVisualFailureGPUCompleted,
            "fboVisualFailurePreservesPreviousCurrent":
                fboVisualFailurePreservedPreviousCurrent,
            "fboVisualFailureDiscardsUncommittedTargetState":
                fboVisualFailureDiscardedUncommittedTargetState,
            "fboVisualFailureRecoversOnNextFrame":
                fboVisualFailureRecoveredNextFrame,
            "commandVisualFailurePassthroughPrepared":
                commandVisualFailurePrepared,
            "commandVisualFailurePassthroughEncoded":
                commandVisualFailureEncoded,
            "commandVisualFailurePassthroughGPUCompleted":
                commandVisualFailureGPUCompleted,
            "commandVisualFailurePreservesPreviousCurrent":
                commandVisualFailurePreservedPreviousCurrent,
            "commandVisualFailureDiscardsPreparedMaterialAndCopyPrefix":
                commandVisualFailureDiscardedPreparedPrefix,
            "commandVisualFailureRecoversOnNextFrame":
                commandVisualFailureRecoveredNextFrame,
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
            "visualUniformSchemaMultiNodeUsesWholeEffectPassthrough": {
                guard let claim = uniformSchemaMultiNodeCapabilities.claim(
                          ordinaryChain
                      ), let capability = uniformSchemaMultiNodeCapabilities.resolve(
                          claim.token,
                          for: ordinaryChain
                      ) else { return false }
                return capability.stages.first?.visualFailureReasonCode
                    == "material-variant-envelope-uniform-schema"
            }(),
            "visualSamplerSchemaMultiNodeUsesWholeEffectPassthrough": {
                guard let claim = samplerSchemaMultiNodeCapabilities.claim(
                          ordinaryChain
                      ), let capability = samplerSchemaMultiNodeCapabilities.resolve(
                          claim.token,
                          for: ordinaryChain
                      ) else { return false }
                return capability.stages.first?.visualFailureReasonCode
                    == "material-variant-envelope-sampler-schema"
            }(),
            "rendererFailurePassthroughPrepared":
                rendererFailurePassthroughPrepared,
            "rendererFailurePassthroughEncoded":
                rendererFailurePassthroughEncoded,
            "rendererFailurePassthroughGPUCompleted":
                rendererFailurePassthroughGPUCompleted,
            "rendererFailurePreservesPreviousAndContinuesSuffix":
                rendererFailurePreservesPreviousAndContinuesSuffix,
            "genericComposeProgramsRotateAndReturnTerminalZero":
                failureCode(genericComposePreparation) == "success"
                    && genericComposePublicationContract
                    && genericComposeEncoded
                    && genericComposePixelsPreserved,
            "genericComposeFirstProgramFailureRestoresPreviousCurrent":
                genericComposeFirstFailure.prepared
                    && genericComposeFirstFailure.encoded
                    && genericComposeFirstFailure.gpu
                    && genericComposeFirstFailure.restored,
            "genericComposeSecondProgramFailureDiscardsPreparedPrefix":
                genericComposeSecondFailure.prepared
                    && genericComposeSecondFailure.encoded
                    && genericComposeSecondFailure.gpu
                    && genericComposeSecondFailure.restored,
            "secondFramePreviousStateAndResourcesPrepared": failureCode(secondFrame)
                == "success",
            "secondFrameReusesShaderAndFrontendVariant":
                compilerCountsAfterFirst.shader > 0
                    && compilerCountsAfterFirst.frontend > 0
                    && compilerCountsAfterSecond.shader
                        == compilerCountsAfterFirst.shader
                    && compilerCountsAfterSecond.frontend
                        == compilerCountsAfterFirst.frontend,
            "frameSelectionRejectsUnplannedVariantWithoutCompilation":
                unplannedVariantRejectedWithoutCompilation,
            "independentLaunchVariantRejectionIsCached":
                failedVariantRejectionIsCached,
            "frontendInvalidUsesWholeEffectPassthrough": {
                guard let claim = failingCapabilities.claim(ordinaryChain),
                      let capability = failingCapabilities.resolve(
                          claim.token,
                          for: ordinaryChain
                      ) else { return false }
                return capability.stages.first?.visualFailureReasonCode
                    == "material-variant-envelope-frontend"
            }(),
            "copyAndSwapPrepared": failureCode(mixedPreparation) == "success"
                && mixedKinds.contains("copy")
                && mixedKinds.contains("swap")
                && mixedPublicationChain,
            "unseenMixedCopySwapVisualFailureRollsBackWholeEffect":
                mixedVisualFailureRollsBackWholeEffect,
            "freshCopyTargetPreparedAndEncoded":
                failureCode(freshCopyPreparation) == "success"
                    && freshCopyPreparedAndEncoded,
            "freshCopyPublicationMatchesTargetVersion":
                freshCopyPublicationMatches,
            "copyExtentMismatchRejectedBeforeFrame": failureCode(copyMismatch)
                == Executor.Failure.invalidClaim.rawValue,
            "swapDescriptorMismatchRejectedBeforeFrame":
                swapMismatchRejectedBeforeFrame,
            "freshSameDescriptorLeaseWithoutCopiesRejectsHistory":
                sameDescriptorHistory.noCopiesBehavior,
            "graphResourceKeyRequestIdentityMismatchRejected":
                sameDescriptorHistory.wrongRequestIdentityRejected,
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
            "materialFunctionCapabilityClaimed":
                materialFunction.capabilityClaimed,
            "materialFunctionNoCallRejectsUninitializedHistory":
                materialFunction.noCallFailure == "state-rejected",
            "materialFunctionClearVisible":
                matches(materialFunction.invokedPixel, [0, 0, 0, 0]),
            "materialFunctionDuplicateOrderPreserved":
                materialFunction.invocationIntentCount == 4,
            "materialFunctionStaleRejected":
                materialFunction.staleFailure
                    == "function-invocation-stale-frame",
            "materialFunctionUnknownEffectRejected":
                materialFunction.unknownEffectFailure
                    == "function-invocation-unknown-effect",
            "materialFunctionUnknownNameRejected":
                materialFunction.unknownFunctionFailure
                    == "function-invocation-unknown-function",
            "materialFunctionEncodeFailureTyped":
                materialFunction.encodeFailure
                    == "function-clear-encode-rejected",
            "materialFunctionFailedEncodeHasTypedNoGPUCommit":
                materialFunction.encodeFailure
                    == "function-clear-encode-rejected",
        ]
        let payload: [String: Any] = [
            "metalAvailable": true,
            "results": results,
            "failureCodes": [
                "crossLayer": crossLayerFailure,
                "crossLayerMissing": missingProvider.failureCode,
                "crossLayerWrongProvider": wrongProvider.failureCode,
                "crossLayerSecondary": secondaryProvider.failureCode,
                "crossLayerStale": staleProvider.failureCode,
                "late": failureCode(latePreparation),
                "copyMismatch": failureCode(copyMismatch),
                "swapMismatch": swapMismatchRejectedBeforeFrame
                    ? "swap-target-descriptor-incompatible" : "unexpected-admission",
                "firstFailedVariant": launchEnvelopeFailureCode(firstFailedVariant),
                "secondFailedVariant": launchEnvelopeFailureCode(secondFailedVariant),
            ],
            "composeDiagnostics": [
                "genericFailure": failureCode(genericComposePreparation),
                "genericPublication": String(genericComposePublicationContract),
                "genericEncoded": String(genericComposeEncoded),
                "genericPixels": String(genericComposePixelsPreserved),
                "genericFirstFailureRestored": String(
                    genericComposeFirstFailure.restored
                ),
                "genericSecondFailureRestored": String(
                    genericComposeSecondFailure.restored
                ),
            ],
            "materialFunctionSetupFailure": materialFunction.setupFailure,
            "materialFunctionDiagnostics": [
                "invocationIntentCount": materialFunction.invocationIntentCount,
                "invokedPixel": materialFunction.invokedPixel,
                "failedEncodePreservedPixel":
                    materialFunction.failedEncodePreservedPixel,
            ],
            "mixedKinds": mixedKinds,
            "crossLayerPixel": crossLayerPixel,
            "crossLayerReport": crossLayerCapabilities.reportLines,
            "encodedPixel": encodedRead.firstPixel,
            "encodedLastPixel": encodedRead.lastPixel,
            "addressProbePixels": [
                "rgbaClamp": [rgbaClampProbe.first, rgbaClampProbe.last],
                "rgbaRepeat": [rgbaRepeatProbe.first, rgbaRepeatProbe.last],
                "scalarClamp": [scalarClampProbe.first, scalarClampProbe.last],
                "scalarRepeat": [scalarRepeatProbe.first, scalarRepeatProbe.last],
            ],
            "pixelChainCanClaim": pixelCapabilities.claim(pixelChain) != nil,
            "pixelChainReport": pixelCapabilities.reportLines,
            "colorBlendCanClaim": colorBlendClaim != nil,
            "colorBlendCapabilityResolved": colorBlendCapability != nil,
            "colorBlendOptionalMaskProof": colorBlendOptionalMaskProof,
            "colorBlendProfiles": colorBlendProfiles,
            "colorBlendVariantCount": colorBlendSnapshot?.variants.count ?? -1,
            "colorBlendAllEntriesReady":
                colorBlendSnapshot?.allEntriesReady == true,
            "colorBlendLeasesAvailable": colorBlendCapability.flatMap {
                makeChainedLeases($0, device: device, generation: 91)
            } != nil,
            "colorBlendReport": colorBlendCapabilities.reportLines,
            "colorBlendPendingPreparation": colorBlendPendingFailure.failureCode,
            "colorBlendWrongPurposePreparation":
                colorBlendWrongPurposeFailure.failureCode,
            "pixelChainFailure": pixelChainFailure,
            "visualFailureObservedPixels": visualFailureObservedPixels,
            "dynamicUniformMultiNodeFailure": dynamicUniformMultiNodeFailure,
            "dynamicUniformMultiNodeReport": dynamicMultiCapabilities.reportLines,
            "staticUniformMultiNodeFailure": staticUniformMultiNodeFailure,
            "staticUniformMultiNodeReport":
                staticUniformMultiNodeCapabilities.reportLines,
            "hostConflictMultiNodeFailure": hostConflictMultiNodeFailure,
            "hostConflictMultiNodeReport":
                hostConflictMultiNodeCapabilities.reportLines,
            "declarationConflictMultiNodeFailure":
                declarationConflictMultiNodeFailure,
            "declarationConflictMultiNodeReport":
                declarationConflictMultiNodeCapabilities.reportLines,
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
    def test_production_executor_preflights_and_executes_atomic_graph(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)

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
