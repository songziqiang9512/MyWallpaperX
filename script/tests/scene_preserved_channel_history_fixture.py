#!/usr/bin/env python3

"""Reusable Swift fixture for the preserved-channel history GPU gate."""

HARNESS_SUPPORT = r'''
import CoreGraphics
import Foundation
import Metal
import simd

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Plan = SceneGraphRenderTargetPlan
private typealias Executor = SceneResolvedMaterialGraphExecutor
private typealias Template = SceneResolvedMaterialTemplate
private typealias Capabilities = SceneResolvedMaterialExecutionCapabilityCatalog

private let layerID = 812
private let effect = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "preserved-history-fixture"
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
private let history = Graph.TextureIdentity(
    kind: .framebuffer,
    layerID: layerID,
    effect: effect,
    name: "state_alpha"
)
private let scratch = Graph.TextureIdentity(
    kind: .framebuffer,
    layerID: layerID,
    effect: effect,
    name: "state_omega"
)
private let extent = Plan.PixelExtent(width: 2, height: 2)

private func binding(_ identity: Graph.TextureIdentity) -> Graph.Binding {
    .init(
        slot: 0,
        authoredName: identity.name ?? "previous",
        texture: identity,
        conditions: nil
    )
}

private func material(
    _ index: Int,
    target: Graph.TextureIdentity,
    read: Graph.TextureIdentity
) -> Graph.Node {
    .init(
        nodeIndex: index,
        effect: effect,
        definitionPassIndex: index,
        materialOrdinal: index,
        instancePassIndex: index,
        kind: .material,
        materialPath: "materials/history-\(index).json",
        materialPassID: "history#\(index)",
        target: target,
        bindings: [binding(read)],
        commandSource: nil,
        commandTarget: nil,
        compose: nil,
        conditions: nil
    )
}

private func command(
    _ index: Int,
    source: Graph.TextureIdentity,
    target: Graph.TextureIdentity
) -> Graph.Node {
    .init(
        nodeIndex: index,
        effect: effect,
        definitionPassIndex: index,
        materialOrdinal: nil,
        instancePassIndex: nil,
        kind: .copy,
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

private func target(
    _ identity: Graph.TextureIdentity,
    format: String,
    unique: Bool,
    clear: SceneJSONValue? = nil
) -> Graph.RenderTarget {
    .init(
        texture: identity,
        extent: .init(width: nil, height: nil, fit: nil, scale: nil),
        format: format,
        declaredUnique: unique,
        clear: clear,
        uvs: nil,
        conditions: nil
    )
}

private func graph(
    format: String,
    clear: SceneJSONValue? = nil,
    readsBeforeWrite: Bool = true
) -> Graph {
    let nodes = readsBeforeWrite ? [
        material(0, target: scratch, read: history),
        material(1, target: history, read: scratch),
        material(2, target: output, read: history),
    ] : [
        material(0, target: history, read: input),
        material(1, target: output, read: history),
    ]
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effect,
            definitionPath: "effects/history/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: readsBeforeWrite ? [
            target(history, format: format, unique: true, clear: clear),
            target(scratch, format: format, unique: false),
        ] : [target(history, format: format, unique: true)],
        nodes: nodes,
        finalOutput: output,
        blockers: []
    )
}

private enum RejectedHistoryBoundary: String, CaseIterable {
    case sameNode = "same-node"
    case command = "command"
    case multipleWriters = "multiple-writers"
}

private func rejectedHistoryGraph(
    format: String,
    boundary: RejectedHistoryBoundary
) -> Graph {
    let nodes: [Graph.Node]
    switch boundary {
    case .sameNode:
        nodes = [
            material(0, target: scratch, read: history),
            material(1, target: history, read: history),
            material(2, target: output, read: scratch),
        ]
    case .command:
        nodes = [
            material(0, target: scratch, read: history),
            material(1, target: history, read: scratch),
            command(2, source: history, target: scratch),
            material(3, target: output, read: history),
        ]
    case .multipleWriters:
        nodes = [
            material(0, target: scratch, read: history),
            material(1, target: history, read: scratch),
            material(2, target: history, read: scratch),
            material(3, target: output, read: history),
        ]
    }
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effect,
            definitionPath: "effects/history/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: [
            target(history, format: format, unique: true),
            target(scratch, format: format, unique: false),
        ],
        nodes: nodes,
        finalOutput: output,
        blockers: []
    )
}

private func admitted(_ graph: Graph) -> AdmittedLayerGraph {
    let execution = SceneEffectStageExecutionPlan(
        layerID: graph.layerID,
        materialNodeCount: graph.nodes.count,
        logicalRenderTargetCount: graph.renderTargets.count,
        inputRole: .layerSource
    )
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
    pair: Bool,
    invalidUniform: Bool = false
) -> String {
    let expression = pair
        ? "vec2 value = texSample2D(g_Texture0, v_TexCoord).rg; "
            + "gl_FragColor = vec4(value, 0.0, 1.0);"
        : "float value = texSample2D(g_Texture0, v_TexCoord).r; "
            + "gl_FragColor = vec4(value, 0.0, 0.0, 1.0);"
    let uniform = invalidUniform
        ? "uniform float g_Invalid; // {\"material\":3}\n" : ""
    let applied = invalidUniform
        ? expression.replacingOccurrences(
            of: "gl_FragColor = ",
            with: "gl_FragColor = g_Invalid * "
        ) : expression
    return """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    \(uniform)void main() { \(applied) }
    """
}

private func shaderContract(
    index: Int,
    pair: Bool,
    invalidUniform: Bool = false
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
    let prefix = "fixture/preserved-history-\(index)"
    let stages = [
        stage(.vertex, path: "\(prefix).vert", source: vertexSource),
        stage(
            .fragment,
            path: "\(prefix).frag",
            source: fragmentSource(
                pair: pair,
                invalidUniform: invalidUniform
            )
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
        dependencySHA256: "preserved-history-dependency-\(index)"
    )
    return .init(
        identity: prefix,
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "preserved-history-contract-\(index)",
        sourceGraph: sourceGraph
    )
}

private func role(
    _ identity: Graph.TextureIdentity
) -> Template.GraphTextureRole {
    switch identity.kind {
    case .layerSource: .layerSource
    case .effectOutput: .effectOutput
    case .framebuffer: .framebuffer
    case .unresolved: fatalError("unresolved fixture identity")
    }
}

private func template(
    for node: Graph.Node,
    pair: Bool,
    invalidUniform: Bool = false
) -> Template {
    let read = node.bindings[0]
    let contract = shaderContract(
        index: node.nodeIndex,
        pair: pair,
        invalidUniform: invalidUniform
    )
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[0] = .init(index: 0, candidates: [
        .init(reference: .graph(read.texture), provenance: .explicitBinding),
    ])
    return Template.validated(
        textureSlots: slots,
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
            nodeTarget: role(node.target!),
            bindings: [.init(slot: 0, texture: role(read.texture))]
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

private func capabilities(
    _ graph: Graph,
    pair: Bool,
    invalidUniformNode: Int? = nil
) -> Capabilities {
    let materialNodes = graph.nodes.filter { $0.kind == .material }
    let entries = Dictionary(uniqueKeysWithValues: materialNodes.map { node in
        (
            SceneResolvedMaterialRuntimeCatalog.Key(
                effect: node.effect,
                nodeIndex: node.nodeIndex
            ),
            SceneResolvedMaterialRuntimeCatalog.Entry.template(
                template(
                    for: node,
                    pair: pair,
                    invalidUniform: node.nodeIndex == invalidUniformNode
                )
            )
        )
    })
    let descriptor = SceneRenderDescriptor(
        layers: [.init(
            id: graph.layerID,
            effects: [.init(
                id: effect.descriptorID,
                file: "effects/history/effect.json",
                visible: true,
                passes: graph.nodes.map {
                    .init(passIndex: $0.nodeIndex, combos: [:])
                }
            )]
        )],
        materialPasses: materialNodes.map {
            .init(
                id: $0.materialPassID!,
                materialPath: $0.materialPath!,
                combos: [:]
            )
        },
        effectDefinitions: [.init(
            relativePath: "effects/history/effect.json",
            functions: nil
        )]
    )
    return .init(
        admissionCandidates:
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: descriptor,
                authoredPlans: [graph]
            ),
        materialCatalog: .init(entries: entries),
        dynamicProducers: .empty,
        assetFormatFacts: [:],
        assetStates: [:]
    )
}

private func plan(_ graph: Graph) -> Plan {
    switch Plan.make(
        graph: graph,
        inputRole: .layerSource,
        inputWidth: extent.width,
        inputHeight: extent.height
    ) {
    case let .success(value): value
    case let .failure(failure): fatalError("plan failed: \(failure.rawValue)")
    }
}

private func lease(
    _ plan: Plan,
    device: MTLDevice,
    generation: UInt64
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
            return .init(rawValue: "history-\(generation)-\(ordinal)")
        }
    ) {
    case let .success(value): return value
    case let .failure(failure): fatalError("lease failed: \(failure.rawValue)")
    }
}

private func sourceTexture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 1,
        height: 1,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let texture = device.makeTexture(descriptor: descriptor)!
    var bytes: [UInt8] = [0, 0, 255, 255]
    texture.replace(
        region: MTLRegionMake2D(0, 0, 1, 1),
        mipmapLevel: 0,
        withBytes: &bytes,
        bytesPerRow: 4
    )
    return texture
}

private func sourcePipeline(_ device: MTLDevice) -> SceneImageLayerPipeline {
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
        return {mvp * float4(vertices[id].position, 0, 1),
                vertices[id].texcoord};
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
    return .init(state: try! device.makeRenderPipelineState(
        descriptor: descriptor
    ))
}

private func frame(_ index: UInt64) -> SceneResolvedMaterialFrameSnapshot {
    let dynamic = SceneDynamicSnapshotResolver().resolve(
        frameIndex: index,
        generation: index,
        definitions: [],
        timelineValues: [:]
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
            screenSize: CGSize(width: 2, height: 2),
            sceneTime: Float(index),
            dayTime: 0,
            frameTime: 1 / 60,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero
        )
    )
    guard case let .success(value) = result else {
        fatalError("frame failed")
    }
    return value
}

private struct Readback {
    let buffer: MTLBuffer
    var pixel: [UInt8] {
        let pointer = buffer.contents().assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: 4))
    }
}

private func readback(
    _ texture: MTLTexture,
    command: MTLCommandBuffer
) -> Readback? {
    guard let buffer = texture.device.makeBuffer(
        length: 256 * texture.height,
        options: .storageModeShared
    ), let encoder = command.makeBlitCommandEncoder() else { return nil }
    encoder.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: .init(x: 0, y: 0, z: 0),
        sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
        to: buffer,
        destinationOffset: 0,
        destinationBytesPerRow: 256,
        destinationBytesPerImage: 256 * texture.height
    )
    encoder.endEncoding()
    return .init(buffer: buffer)
}

private func matches(_ pixel: [UInt8], _ expected: [UInt8]) -> Bool {
    zip(pixel, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
}

private func intents(_ graph: Executor.PreparedGraph) -> [String] {
    graph.stages.flatMap { stage in
        stage.transition.transaction.intents.map { intent in
            switch intent {
            case .initialize: "initialize"
            case .material: "material"
            case .copy: "copy"
            case .swap: "swap"
            }
        }
    }
}

private func failure(
    _ result: Result<Executor.PreparedGraph, Executor.Failure>
) -> String {
    switch result {
    case .success: "success"
    case let .failure(value): value.rawValue
    }
}

private func copies(
    stage: Executor.PreparedStage,
    oldLease: SceneGraphRenderTargetLease,
    newLease: SceneGraphRenderTargetLease
) -> [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]? {
    let state = stage.transition.nextState
    let authored = Dictionary(uniqueKeysWithValues:
        state.authoredResources.map { ($0.value.token, $0.key) }
    )
    return state.logicalMapping.values.compactMap { value in
        guard value.contentGeneration > 0,
              let identity = authored[value.token],
              let source = oldLease.texturesByToken[value.token],
              let target = newLease.framebufferAllocation.resources[identity],
              let texture = newLease.texturesByToken[target.token] else {
            return nil
        }
        return .init(
            sourceToken: value.token,
            sourceTexture: source,
            targetToken: target.token,
            targetTexture: texture
        )
    }
}

private func prepare(
    executor: Executor,
    token: Capabilities.Token,
    lease: SceneGraphRenderTargetLease,
    copies: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy] = [],
    index: UInt64,
    source: MTLTexture,
    pipeline: SceneImageLayerPipeline,
    command: MTLCommandBuffer,
    previous: Executor.PreparedStage? = nil,
    reset: UInt64 = 1
) -> Result<Executor.PreparedGraph, Executor.Failure> {
    executor.prepare(
        token: token,
        leases: [lease],
        historyRehydrateCopiesByEffect: copies.isEmpty ? [:] : [effect: copies],
        frame: frame(index),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: pipeline,
        frameInputs: .init(),
        commandBuffer: command,
        previousStates: previous.map { [effect: $0.transition.nextState] } ?? [:],
        previousGraphResources: previous.map {
            [effect: $0.persistentResources]
        } ?? [:],
        effectGeneration: 1,
        resetGeneration: reset
    )
}

private func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError(label) }
}
'''
