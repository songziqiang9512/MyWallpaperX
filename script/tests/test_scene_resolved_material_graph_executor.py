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
SWIFT_SOURCES = [
    *PUBLICATION_FIXTURE["SWIFT_SOURCES"],
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder.swift",
    RESOURCE_ENCODER_SOURCE,
    SCENE_ROOT / "RenderGraph/SceneOffscreenResolutionPolicy.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphConditionAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphAdmissionCompiler.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityTemplateAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+EnvelopeDiagnostics.swift",
    EXECUTOR_SOURCE,
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Preparation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+DedicatedPreparation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Validation.swift",
]


SUPPORT = PUBLICATION_FIXTURE["SUPPORT"] + r'''

import simd

struct SceneEffectExactRuntimeSubject: Hashable {
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let family: String
}

struct SceneEffectDefinition {
    let relativePath: String
    let functions: SceneJSONValue?
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
        let utilityLayer: Any? = nil
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

    let references: [Reference]
    let namedReferenceConsumerLayerIDs: Set<Int>

    init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>
    ) {
        _ = descriptor
        _ = visibleLayerIDs
        references = []
        namedReferenceConsumerLayerIDs = []
    }
}

struct SceneEffectStageProgram {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let inputRole: SceneAuthoredEffectInputRole
    let stageGraph: SceneAuthoredEffectRenderPlan
    let executionPlan: SceneAuthoredEffectExecutionPlan
}

struct SceneAuthoredEffectExecutionChain {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let stagePrograms: [SceneEffectStageProgram]

    var executionStages: [SceneAuthoredEffectExecutionPlan] {
        stagePrograms.map(\.executionPlan)
    }
}

final class SceneResolvedMaterialRuntimeBridge {
    struct DedicatedFrameInputs { let time: Float = 0 }
}

enum SceneAuthoredEffectChainRenderer {
    struct PreparedStage {}
    enum StagePreparation {
        case ready(PreparedStage)
        case rejected(reason: String)
    }

    static func prepareStage(
        _ stage: SceneAuthoredEffectExecutionPlan,
        sourceTexture: MTLTexture,
        targets: SceneGraphRenderTargetTable,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float
    ) -> StagePreparation { .rejected(reason: "fixture-stage-unavailable") }

    static func encodePreparedStage(
        _ stage: PreparedStage,
        commandBuffer: MTLCommandBuffer
    ) -> Bool { false }
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
        _ chain: SceneAuthoredEffectExecutionChain
    ) -> ClaimedLayer? {
        claim(layerID: chain.layerID)
    }

    func resolve(
        _ token: Token,
        for chain: SceneAuthoredEffectExecutionChain
    ) -> ChainCapability? {
        guard let capability = resolve(token),
              capability.layerID == chain.layerID else { return nil }
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
        shakeMaskTexture: MTLTexture?,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        dependencyTexture: MTLTexture? = nil,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        encoder: MTLRenderCommandEncoder
    ) {
        _ = shakeMaskTexture
        _ = waterMaskTexture
        _ = foliageMaskTexture
        _ = auxMaskTexture
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
    frontendInvalid: Bool = false
) -> String {
    let annotation = pass ? "// [PASS] shadow shadowcasterdemo\n" : ""
    let sampler = internalDefault
        ? #"uniform sampler2D g_Texture0; // {"default":"_rt_history"}"#
        : "uniform sampler2D g_Texture0;"
    let varying = frontendInvalid
        ? "varying vec3 v_TexCoord;"
        : "varying vec2 v_TexCoord;"
    let expression = frontendInvalid
        ? "gl_FragColor = texSample2D(g_Texture0, v_TexCoord.xy);"
        : "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
    return annotation + """
    \(varying)
    \(sampler)
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
    conditions: SceneJSONValue? = nil
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: effect,
        definitionPassIndex: nodeIndex,
        materialOrdinal: ordinal,
        instancePassIndex: ordinal,
        kind: .material,
        materialPath: "materials/executor.json",
        materialPassID: "executor#\(ordinal)",
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

private func executionPlan(for graph: Graph) -> SceneAuthoredEffectExecutionPlan {
    .init(
        layerID: graph.layerID,
        materialNodeCount: graph.nodes.filter { $0.kind == .material }.count,
        logicalRenderTargetCount: graph.renderTargets.count,
        inputRole: .layerSource,
        cursorRipple: nil
    )
}

private func chain(_ graph: Graph) -> SceneAuthoredEffectExecutionChain {
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
    implicitFramebuffer: Bool = false,
    implicitFramebufferAnnotation: Bool = true
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
    let fragment = implicitFramebuffer ? (implicitFramebufferAnnotation ? """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
    uniform vec4 g_Texture0Resolution;
    void main() {
        gl_FragColor = vec4(g_Texture0Resolution.xy * 0.0, 0.0, 1.0);
    }
    """ : """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() {
        gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
    }
    """ ) : fragmentSource(
        pass: pass,
        internalDefault: internalDefault,
        frontendInvalid: frontendInvalid
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
    for node: Graph.Node
) -> Template {
    guard let target = node.target, node.bindings.isEmpty else {
        fatalError("implicit framebuffer fixture is incomplete")
    }
    let contract = shaderContract(
        nodeIndex: node.nodeIndex,
        pass: false,
        implicitFramebuffer: true,
        implicitFramebufferAnnotation: false
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
    frontendInvalid: Bool = false
) -> Template {
    guard let target = node.target,
          let inputBinding = node.bindings.first,
          let slot = inputBinding.slot else {
        fatalError("material fixture is incomplete")
    }
    let contract = shaderContract(
        nodeIndex: node.nodeIndex,
        pass: pass,
        internalDefault: internalDefault,
        frontendInvalid: frontendInvalid
    )
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[slot] = .init(index: slot, candidates: [
        .init(
            reference: .graph(inputBinding.texture),
            provenance: .explicitBinding
        ),
    ])
    return Template.validated(
        textureSlots: slots,
        combos: [],
        uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(
            blending: overwrite ? "normal" : "translucent",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )!,
        graphRole: .init(
            effectInput: role(input),
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

private func catalog(
    for graph: Graph,
    passNodes: Set<Int> = [],
    nonOverwriteNodes: Set<Int> = [],
    internalDefaultNodes: Set<Int> = [],
    frontendInvalidNodes: Set<Int> = [],
    omittedNodes: Set<Int> = [],
    demandIssueNodes: Set<Int> = [],
    implicitFramebufferNodes: Set<Int> = []
) -> SceneResolvedMaterialRuntimeCatalog {
    var entries: [
        SceneResolvedMaterialRuntimeCatalog.Key:
            SceneResolvedMaterialRuntimeCatalog.Entry
    ] = [:]
    for node in graph.nodes where node.kind == .material {
        guard !omittedNodes.contains(node.nodeIndex) else { continue }
        let value = implicitFramebufferNodes.contains(node.nodeIndex)
            ? implicitFramebufferTemplate(for: node)
            : template(
                for: node,
                pass: passNodes.contains(node.nodeIndex),
                internalDefault: internalDefaultNodes.contains(node.nodeIndex),
                overwrite: !nonOverwriteNodes.contains(node.nodeIndex),
                frontendInvalid: frontendInvalidNodes.contains(node.nodeIndex)
            )
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(value)
    }
    let issues = Set(demandIssueNodes.map {
        SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue(
            key: .init(effect: effect, nodeIndex: $0)
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
    usage: MTLTextureUsage = .shaderRead
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
    let red = [UInt8](
        repeating: 0,
        count: width * height * 4
    ).enumerated().map { index, _ -> UInt8 in
        switch index % 4 {
        case 2, 3: 255
        default: 0
        }
    }
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
    height: Int = extent.height
) -> SceneResolvedMaterialFrameSnapshot {
    let result = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: .init(
            frameEpoch: index,
            frameIndex: index,
            entries: [:]
        ),
        dynamicSnapshot: .empty(frameIndex: index),
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
    transition: Executor.PreparedTransition,
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
    let chain = chain(graph)
    let capabilities = capabilities(chain, catalog: catalog(for: graph))
    guard let claim = capabilities.claim(chain),
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
          let transition = firstPrepared.transitions.first else {
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

    let acceptedPreparation: Result<Executor.PreparedChain, Executor.Failure>
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
          let acceptedTransition = accepted.transitions.first else {
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
    _ result: Result<Executor.PreparedChain, Executor.Failure>
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
    _ chain: Executor.PreparedChain
) -> [String] {
    chain.transitions.flatMap { value in
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
    _ chain: SceneAuthoredEffectExecutionChain,
    catalog: SceneResolvedMaterialRuntimeCatalog
) -> Capabilities {
    let graph = chain.renderGraph
    let materialNodes = graph.nodes.filter { $0.kind == .material }
        .sorted { ($0.materialOrdinal ?? -1) < ($1.materialOrdinal ?? -1) }
    let instancePasses = materialNodes.map {
        SceneRenderDescriptor.PassDescriptor(
            passIndex: $0.instancePassIndex!,
            combos: [:]
        )
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
                    passes: instancePasses
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
        authoredPlans: [graph]
    )
    return .init(
        admissionCandidates: candidates,
        materialCatalog: catalog
    )
}

private func compilerCounts(
    _ capability: Capabilities.ChainCapability
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

        let ordinaryGraph = graph(
            targets: [rawTarget(first)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
        let ordinaryChain = chain(ordinaryGraph)
        let ordinaryCatalog = catalog(for: ordinaryGraph)
        let ordinaryCapabilities = capabilities(
            ordinaryChain,
            catalog: ordinaryCatalog
        )
        let ordinaryClaim = ordinaryCapabilities.claim(ordinaryChain)!
        let ordinaryExecutor = Executor(
            device: device,
            capabilities: ordinaryCapabilities
        )!
        let ordinaryPlan = requirePlan(ordinaryGraph)
        let ordinaryLease = makeLease(ordinaryPlan, device: device)

        let implicitFramebufferGraph = graph(
            targets: [],
            nodes: [
                implicitFramebufferMaterial(0, ordinal: 0, target: output),
            ]
        )
        let implicitFramebufferChain = chain(implicitFramebufferGraph)
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
        let admittedComposeChain = chain(admittedComposeGraph)
        let admittedComposeCapabilities = capabilities(
            admittedComposeChain,
            catalog: catalog(for: admittedComposeGraph)
        )
        let admittedComposeClaim = admittedComposeCapabilities.claim(
            admittedComposeChain
        )!
        let admittedComposeExecutor = Executor(
            device: device,
            capabilities: admittedComposeCapabilities
        )!
        let admittedComposeLease = makeLease(
            requireR4Plan(admittedComposeGraph),
            device: device
        )
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
            chain(repeatTargetGraph),
            catalog: catalog(for: repeatTargetGraph)
        )
        let nonzeroClearCapabilities = capabilities(
            chain(nonzeroClearGraph),
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
        if case let .success(value) = composePreparation {
            composeAppended = admittedComposeExecutor.encode(
                value,
                commandBuffer: composeBuffer
            )
                && value.transitions[0].pairStep.composeTransitionCount == 1
                && value.transitions[0].pairStep.inputMember == .zero
                && value.transitions[0].pairStep.outputMember == .zero
                && value.finalTexture
                    === admittedComposeLease.table.fullFramePair.first
        } else {
            composeAppended = false
        }
        composeBuffer.commit()
        composeBuffer.waitUntilCompleted()
        let composeEncoded = composeAppended
            && composeBuffer.status == .completed && composeBuffer.error == nil

        guard let secondFrameBuffer = queue.makeCommandBuffer() else {
            fatalError("second frame buffer unavailable")
        }
        let firstTransition = prepared.transitions[0]
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
        var readyResources = prepared.transitions[0].frameResources
        readyResources[input] = prepared.transitions[0].effectOutputResource
            .rewrappedForGraphIdentity(input)!
        let readyVariantFrame = frame(3).overlayingGraphResources(readyResources)!
        let readyVariant = boundedCache.resolve(
            readyVariantFrame.finalizationInput(
                template: cacheTemplate,
                renderSize: CGSize(width: extent.width, height: extent.height),
                modelViewProjection: Executor.fullTargetMVP(firstTexture)
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
                modelViewProjection: Executor.fullTargetMVP(firstTexture)
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
            modelViewProjection: Executor.fullTargetMVP(firstTexture)
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
        let mixedChain = chain(mixedGraph)
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
        let freshCopyChain = chain(freshCopyGraph)
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
           let transition = value.transitions.first,
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
        let copyMismatchChain = chain(copyMismatchGraph)
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
        let swapMismatchChain = chain(swapMismatchGraph)
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
            let transition = value.transitions[0]
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
            "foreignCatalogTokenRejected": lateCapabilities.resolve(
                ordinaryClaim.token
            ) == nil,
            "conditionRejected": capabilities(
                chain(conditionGraph), catalog: catalog(for: conditionGraph)
            ).claim(chain(conditionGraph)) == nil,
            "composeRejected": capabilities(
                chain(composeGraph), catalog: catalog(for: composeGraph)
            ).claim(chain(composeGraph)) == nil,
            "inactiveComposeAccepted": {
                let value = chain(inactiveComposeGraph)
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
            "missingTemplateRejected": missingCapabilities.claim(ordinaryChain) == nil,
            "nonOverwriteRejectedBeforeFrame": nonOverwriteCapabilities.claim(
                ordinaryChain
            ) == nil,
            "resourceDemandIssueRejectedBeforeFrame":
                demandIssueCapabilities.claim(ordinaryChain) == nil,
            "internalDefaultRejectedBeforeFrame":
                internalDefaultCapabilities.claim(ordinaryChain) == nil,
            "repeatTargetRejectedBeforeFrame": repeatTargetCapabilities.claim(
                chain(repeatTargetGraph)
            ) == nil,
            "nonzeroClearRejectedBeforeFrame": nonzeroClearCapabilities.claim(
                chain(nonzeroClearGraph)
            ) == nil,
            "oversizedNodeGraphRejectedBeforeGPU": capabilities(
                chain(oversizedNodeGraph), catalog: catalog(for: oversizedNodeGraph)
            ).claim(chain(oversizedNodeGraph)) == nil,
            "oversizedLogicalGraphRejectedBeforeGPU": capabilities(
                chain(oversizedLogicalGraph), catalog: catalog(for: oversizedLogicalGraph)
            ).claim(chain(oversizedLogicalGraph)) == nil,
            "prepareHasNoEncodingSideEffect": prepareHasNoEncodingSideEffect,
            "unreadableSourceCaptureRejectedDuringPreflight":
                failureCode(unreadableCapturePreparation)
                    == Executor.Failure.captureRejected.rawValue,
            "staticClaimRejectionHasNoPartialWrite":
                staticClaimRejectionHasNoPartialWrite,
            "twoMaterialPublicationFinalized": prepared.transitions.count == 1
                && prepared.transitions[0].programCacheKeys.count == 2
                && prepared.transitions[0].frameResources[first] != nil
                && prepared.transitions[0].effectOutputResource.publication
                    .requestIdentity == .graph(output),
            "encodedOutputReadable": encodedOutputReadable,
            "sourceCaptureRendersAcrossFullTarget":
                sourceCaptureCoversFullTarget,
            "ordinaryComposeRotatesWithinEffectAndReturnsTerminalZero":
                failureCode(composePreparation) == "success" && composeEncoded,
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
            "mixedKinds": mixedKinds,
            "encodedPixel": encodedRead.firstPixel,
            "encodedLastPixel": encodedRead.lastPixel,
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
        preparation = (
            SCENE_ROOT
            / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Preparation.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            '"dedicated:\\(SceneShaderStableDigest.hash(program.stageGraph))"',
            preparation,
        )
        self.assertIn("programKeys.append(", preparation)
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
