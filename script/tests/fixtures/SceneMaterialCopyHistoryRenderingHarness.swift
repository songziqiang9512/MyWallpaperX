import CoreGraphics
import Foundation
import Metal
import simd

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Plan = SceneGraphRenderTargetPlan
private typealias Template = SceneResolvedMaterialTemplate
private typealias Capabilities = SceneResolvedMaterialExecutionCapabilityCatalog

private let layerID = 91
private let effect = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "material-copy-history"
)
private let input = Graph.TextureIdentity(
    kind: .layerSource, layerID: layerID, effect: nil, name: nil
)
private let output = Graph.TextureIdentity(
    kind: .effectOutput, layerID: layerID, effect: effect, name: nil
)
private let history = Graph.TextureIdentity(
    kind: .framebuffer, layerID: layerID, effect: effect, name: "history"
)
private let current = Graph.TextureIdentity(
    kind: .framebuffer, layerID: layerID, effect: effect, name: "current"
)
private let extent = Plan.PixelExtent(width: 4, height: 3)
private let sourcePixels: [UInt8] = [
    0, 0, 255, 255, 0, 255, 0, 255,
    255, 0, 0, 255, 255, 255, 255, 255,
    0, 0, 128, 128, 0, 128, 0, 128,
    128, 0, 0, 128, 64, 96, 128, 128,
    0, 0, 0, 0, 64, 32, 16, 64,
    25, 100, 150, 200, 1, 0, 1, 1,
]

private let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
uniform mat4 g_ModelViewProjectionMatrix;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
}
"""

private func fragmentSource(nodeIndex: Int) -> String {
    if nodeIndex == 0 {
        return """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        uniform sampler2D g_Texture1;
        uniform float g_Amount; // {"material":"rate","default":0.8}
        void main() {
            vec4 source = texSample2D(g_Texture0, v_TexCoord);
            vec4 prior = texSample2D(g_Texture1, v_TexCoord);
            gl_FragColor = mix(prior, source, g_Amount);
        }
        """
    }
    return """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() {
        gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
    }
    """
}

private func binding(
    slot: Int,
    name: String,
    texture: Graph.TextureIdentity
) -> Graph.Binding {
    .init(
        slot: slot,
        authoredName: name,
        texture: texture,
        conditions: nil
    )
}

private func material(
    _ nodeIndex: Int,
    ordinal: Int,
    target: Graph.TextureIdentity,
    bindings: [Graph.Binding]
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: effect,
        definitionPassIndex: nodeIndex,
        materialOrdinal: ordinal,
        instancePassIndex: ordinal,
        kind: .material,
        materialPath: "materials/history-\(nodeIndex).json",
        materialPassID: "history#\(ordinal)",
        target: target,
        bindings: bindings,
        commandSource: nil,
        commandTarget: nil,
        compose: nil,
        conditions: nil
    )
}

private func copyCommand() -> Graph.Node {
    .init(
        nodeIndex: 1,
        effect: effect,
        definitionPassIndex: 1,
        materialOrdinal: nil,
        instancePassIndex: nil,
        kind: .copy,
        materialPath: nil,
        materialPassID: nil,
        target: nil,
        bindings: [],
        commandSource: current,
        commandTarget: history,
        compose: nil,
        conditions: nil
    )
}

private func target(
    _ texture: Graph.TextureIdentity,
    unique: Bool
) -> Graph.RenderTarget {
    .init(
        texture: texture,
        extent: .init(width: nil, height: nil, fit: nil, scale: nil),
        format: "rgba_backbuffer",
        declaredUnique: unique,
        clear: nil,
        uvs: nil,
        conditions: nil
    )
}

private func graph() -> Graph {
    let nodes = [
        material(
            0,
            ordinal: 0,
            target: current,
            bindings: [
                binding(slot: 0, name: "previous", texture: input),
                binding(slot: 1, name: "history", texture: history),
            ]
        ),
        copyCommand(),
        material(
            2,
            ordinal: 1,
            target: output,
            bindings: [binding(slot: 0, name: "current", texture: current)]
        ),
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
        renderTargets: [
            target(history, unique: true),
            target(current, unique: false),
        ],
        nodes: nodes,
        finalOutput: output,
        blockers: []
    )
}

private func shaderContract(for node: Graph.Node) -> SceneShaderContract {
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
    let prefix = "fixture/history-\(node.nodeIndex)"
    let stages = [
        stage(.vertex, path: "\(prefix).vert", source: vertexSource),
        stage(
            .fragment,
            path: "\(prefix).frag",
            source: fragmentSource(nodeIndex: node.nodeIndex)
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
        dependencySHA256: "history-dependency-\(node.nodeIndex)"
    )
    return .init(
        identity: prefix,
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "history-contract-\(node.nodeIndex)",
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

private func template(for node: Graph.Node, mixWeight: Double) -> Template {
    guard let nodeTarget = node.target else {
        fatalError("material target missing")
    }
    let contract = shaderContract(for: node)
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    for authored in node.bindings {
        guard let slot = authored.slot else {
            fatalError("material binding slot missing")
        }
        slots[slot] = .init(index: slot, candidates: [
            .init(
                reference: .graph(authored.texture),
                provenance: .explicitBinding
            ),
        ])
    }
    let uniforms: [Template.UniformDeclaration] = if node.nodeIndex == 0 {
        [.init(
            name: "rate",
            value: .staticExact(.init(
                valueKind: "number",
                componentBitPatterns: [mixWeight.bitPattern],
                authoredBindingKeys: []
            ))
        )]
    } else {
        []
    }
    return Template.validated(
        textureSlots: slots,
        combos: [],
        uniformDeclarations: uniforms,
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
            nodeTarget: role(nodeTarget),
            bindings: node.bindings.map {
                .init(slot: $0.slot!, texture: role($0.texture))
            }
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
    mixWeight: Double
) -> SceneResolvedMaterialRuntimeCatalog {
    let entries = Dictionary(uniqueKeysWithValues: graph.nodes.compactMap {
        node -> (
            SceneResolvedMaterialRuntimeCatalog.Key,
            SceneResolvedMaterialRuntimeCatalog.Entry
        )? in
        guard node.kind == .material else { return nil }
        return (
            .init(effect: node.effect, nodeIndex: node.nodeIndex),
            .template(template(for: node, mixWeight: mixWeight))
        )
    })
    return .init(entries: entries, resourceDemandIssues: [])
}

private func descriptor(for graph: Graph) -> SceneRenderDescriptor {
    .init(
        layers: [.init(
            id: layerID,
            effects: [.init(
                id: effect.descriptorID,
                file: graph.effects[0].definitionPath,
                visible: true,
                passes: graph.nodes.compactMap {
                    guard let pass = $0.instancePassIndex else { return nil }
                    return .init(passIndex: pass, combos: [:])
                }
            )]
        )],
        materialPasses: graph.nodes.compactMap {
            guard let id = $0.materialPassID,
                  let path = $0.materialPath else { return nil }
            return .init(id: id, materialPath: path, combos: [:])
        },
        effectDefinitions: [.init(
            relativePath: graph.effects[0].definitionPath,
            functions: nil
        )]
    )
}

private func admitted(_ graph: Graph) -> AdmittedLayerGraph {
    let executionPlan = SceneEffectStageExecutionPlan(
        layerID: layerID,
        materialNodeCount: 2,
        logicalRenderTargetCount: 2,
        inputRole: .layerSource
    )
    return .init(
        layerID: layerID,
        renderGraph: graph,
        stagePrograms: [.init(
            effectKey: effect,
            inputRole: .layerSource,
            stageGraph: graph,
            executionPlan: executionPlan
        )]
    )
}

private func capabilities(
    graph: Graph,
    admitted: AdmittedLayerGraph,
    mixWeight: Double
) -> Capabilities {
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor(for: graph),
        authoredPlans: [graph]
    )
    return .init(
        admissionCandidates: candidates,
        materialCatalog: catalog(for: graph, mixWeight: mixWeight)
    )
}

private func pairPlan(for graph: Graph) -> SceneLayerFullFramePairPlan {
    switch SceneLayerFullFramePairPlan.make(conditionPrunedGraphs: [graph]) {
    case let .success(value): value
    case let .failure(failure): fatalError("pair plan: \(failure.rawValue)")
    }
}

private func framePlan(
    pool: SceneOffscreenTexturePool,
    graph: Graph,
    executionPlan: SceneEffectStageExecutionPlan,
    commandBuffer: MTLCommandBuffer
) -> ScenePersistentGraphTargetFramePlan {
    guard let allocation = pool.framePlanForPersistentGraphTargets(
        admittedGraphs: [graph],
        targetExecutionPlans: [executionPlan],
        pairPlan: pairPlan(for: graph),
        requestedWidth: extent.width,
        requestedHeight: extent.height,
        sharesFullFramePairWhenHistoryFree: true,
        orderingContext: .init(commandBuffer: commandBuffer)
    ), pool.preflightPersistentGraphTargets([allocation]) == .ready
    else { fatalError("production target preparation failed") }
    return allocation
}

func sourceTexture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: extent.width,
        height: extent.height,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let texture = device.makeTexture(descriptor: descriptor)!
    texture.replace(
        region: MTLRegionMake2D(0, 0, extent.width, extent.height),
        mipmapLevel: 0,
        withBytes: sourcePixels,
        bytesPerRow: extent.width * 4
    )
    return texture
}

func sourcePipeline(_ device: MTLDevice) -> SceneImageLayerPipeline {
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
        texture2d<float> texture [[texture(0)]],
        constant Uniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge,
                            filter::nearest);
        return texture.sample(s, in.texcoord) * uniforms.tint;
    }
    """
    let library = try! device.makeLibrary(source: source, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "fixtureVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "fixtureFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    return .init(state: try! device.makeRenderPipelineState(descriptor: descriptor))
}

private func beginFrame(
    _ coordinator: SceneResolvedMaterialSubmissionCoordinator,
    index: UInt64
) {
    let dynamic = SceneDynamicSnapshotResolver().resolve(
        frameIndex: index,
        generation: index,
        definitions: []
    )
    coordinator.beginFrame(
        textureSnapshot: .init(
            frameEpoch: index,
            frameIndex: index,
            entries: [:]
        ),
        dynamicSnapshot: dynamic.snapshot,
        frameInputs: .init(
            frameIndex: index,
            screenSize: CGSize(width: extent.width, height: extent.height),
            sceneTime: Float(index),
            dayTime: 0,
            frameTime: 1 / 60,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero
        )
    )
}

private struct Readback {
    let buffer: MTLBuffer
    let bytesPerRow: Int

    var pixels: [UInt8] {
        let pointer = buffer.contents().assumingMemoryBound(to: UInt8.self)
        return (0 ..< extent.height).flatMap { row in
            Array(UnsafeBufferPointer(
                start: pointer.advanced(by: row * bytesPerRow),
                count: extent.width * 4
            ))
        }
    }
}

private func appendReadback(
    _ texture: MTLTexture,
    commandBuffer: MTLCommandBuffer
) -> Readback? {
    let bytesPerRow = 256
    guard let buffer = texture.device.makeBuffer(
        length: bytesPerRow * texture.height,
        options: .storageModeShared
    ), let encoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
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
        to: buffer,
        destinationOffset: 0,
        destinationBytesPerRow: bytesPerRow,
        destinationBytesPerImage: bytesPerRow * texture.height
    )
    encoder.endEncoding()
    return .init(buffer: buffer, bytesPerRow: bytesPerRow)
}

private func approximately(
    _ actual: [UInt8],
    _ expected: [UInt8]
) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy {
        abs(Int($0) - Int($1)) <= 2
    }
}

private func expected(scale: Float) -> [UInt8] {
    sourcePixels.map { UInt8((Float($0) * scale).rounded()) }
}

struct CoordinatorFrameResult {
    let currentPixels: [UInt8]
    let historyPixels: [UInt8]
    let outputPixels: [UInt8]
    let completed: Bool
}

struct CoordinatorSequenceResult {
    let frames: [CoordinatorFrameResult]
    let deferredWhileHistoryPending: Bool
}

private struct PendingCoordinatorFrame {
    let commandBuffer: MTLCommandBuffer
    let currentReadback: Readback
    let historyReadback: Readback
    let outputReadback: Readback
}

private func claimedExecution(
    catalog: Capabilities,
    admitted: AdmittedLayerGraph
) -> SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
    guard let claim = catalog.claim(admitted),
          let capability = catalog.resolve(claim.token),
          capability.layerID == layerID,
          capability.effectSubjectsAreConserved else {
        fatalError("coordinator claim unavailable")
    }
    return .init(
        layerID: layerID,
        dependencyOwnership: capability.dependencyOwnership,
        sourceRoute: capability.sourceRoute,
        token: claim.token
    )
}

private func consumePreparedClaim(
    _ claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
    coordinator: SceneResolvedMaterialSubmissionCoordinator
) {
    coordinator.lock.lock()
    defer { coordinator.lock.unlock() }
    guard let identity = coordinator.preparedLedgerByLayerID[claim.layerID],
          var ledger = coordinator.activeByID[identity],
          ledger.capabilityToken == claim.token,
          ledger.phase == .allocationCommitted,
          !ledger.claimConsumed else {
        fatalError("prepared coordinator claim unavailable")
    }
    ledger.claimConsumed = true
    coordinator.activeByID[identity] = ledger
    coordinator.frameClaimed += 1
}

private func submitCoordinatorFrame(
    index: UInt64,
    coordinator: SceneResolvedMaterialSubmissionCoordinator,
    claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
    graph: Graph,
    executionPlan: SceneEffectStageExecutionPlan,
    pool: SceneOffscreenTexturePool,
    source: MTLTexture,
    pipeline: SceneImageLayerPipeline,
    queue: MTLCommandQueue
) -> PendingCoordinatorFrame {
    guard let commandBuffer = queue.makeCommandBuffer() else {
        fatalError("coordinator command buffer unavailable")
    }
    beginFrame(coordinator, index: index)
    let allocation = framePlan(
        pool: pool,
        graph: graph,
        executionPlan: executionPlan,
        commandBuffer: commandBuffer
    )
    let targetPlan = SceneResolvedMaterialFrameTargetPlan(
        token: claim.token,
        allocation: allocation
    )
    let request = SceneResolvedMaterialRuntimeBridge.FramePreparationRequest(
        claim: claim,
        targetPlan: targetPlan,
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: pipeline,
        dedicatedInputs: .init()
    )
    switch coordinator.prepareFrame(
        [request],
        pool: pool,
        commandBuffer: commandBuffer
    ) {
    case .ready:
        break
    case let .rejected(reason):
        fatalError("coordinator frame preparation failed: \(reason)")
    }
    consumePreparedClaim(claim, coordinator: coordinator)

    let texture: MTLTexture
    let ticket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket
    switch coordinator.executeClaimed(
        claim: claim,
        dependencyEffect: nil,
        commandBuffer: commandBuffer
    ) {
    case let .encoded(value, valueTicket):
        texture = value
        ticket = valueTicket
    case let .failed(reason):
        fatalError("coordinator execution failed: \(reason)")
    }
    guard let stage = coordinator.activeByID[ticket.identity]?.prepared.stages.first,
          let currentTexture = stage.frameResources[current]?.publication.texture,
          let historyTexture = stage.frameResources[history]?.publication.texture,
          currentTexture.width == extent.width,
          currentTexture.height == extent.height,
          historyTexture.width == extent.width,
          historyTexture.height == extent.height,
          texture.width == extent.width,
          texture.height == extent.height,
          case .consumed = coordinator.markComposite(
              ticket,
              texture: texture,
              consumed: true
          ), coordinator.sealFrame(on: commandBuffer),
          let currentReadback = appendReadback(
              currentTexture, commandBuffer: commandBuffer
          ), let historyReadback = appendReadback(
              historyTexture, commandBuffer: commandBuffer
          ), let outputReadback = appendReadback(
              texture, commandBuffer: commandBuffer
          ) else {
        fatalError("coordinator publication or compositor failed")
    }
    commandBuffer.commit()
    _ = coordinator.endFrame()
    return .init(
        commandBuffer: commandBuffer,
        currentReadback: currentReadback,
        historyReadback: historyReadback,
        outputReadback: outputReadback
    )
}

private func completeCoordinatorFrame(
    _ pending: PendingCoordinatorFrame,
    coordinator: SceneResolvedMaterialSubmissionCoordinator
) -> CoordinatorFrameResult {
    let commandBuffer = pending.commandBuffer
    commandBuffer.waitUntilCompleted()
    let completed = commandBuffer.status == .completed && commandBuffer.error == nil
    coordinator.completeCommandBuffer(
        identity: ObjectIdentifier(commandBuffer),
        status: completed ? .completed : .failed
    )
    return .init(
        currentPixels: pending.currentReadback.pixels,
        historyPixels: pending.historyReadback.pixels,
        outputPixels: pending.outputReadback.pixels,
        completed: completed
    )
}

func runCoordinatorSequence(
    mixWeight: Double,
    exercisesInFlightBoundary: Bool,
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    pipeline: SceneImageLayerPipeline
) -> CoordinatorSequenceResult {
    let renderGraph = graph()
    let admittedGraph = admitted(renderGraph)
    let catalog = capabilities(
        graph: renderGraph,
        admitted: admittedGraph,
        mixWeight: mixWeight
    )
    let executionPlan = admittedGraph.stagePrograms[0].executionPlan
    let pool = SceneOffscreenTexturePool(
        device: device,
        maxDimension: 64,
        residentByteBudget: 1_048_576
    )
    let coordinator = SceneResolvedMaterialSubmissionCoordinator(
        device: device,
        capabilities: catalog,
        logSink: { _ in }
    )
    let claim = claimedExecution(catalog: catalog, admitted: admittedGraph)
    func submit(_ index: UInt64) -> PendingCoordinatorFrame {
        submitCoordinatorFrame(
            index: index,
            coordinator: coordinator,
            claim: claim,
            graph: renderGraph,
            executionPlan: executionPlan,
            pool: pool,
            source: source,
            pipeline: pipeline,
            queue: queue
        )
    }
    var results: [CoordinatorFrameResult] = []
    var deferredWhileHistoryPending = false
    if exercisesInFlightBoundary {
        let first = submit(0)
        deferredWhileHistoryPending = coordinator.shouldDeferFrame
        results.append(completeCoordinatorFrame(first, coordinator: coordinator))
        results.append(completeCoordinatorFrame(submit(1), coordinator: coordinator))
        results.append(completeCoordinatorFrame(submit(2), coordinator: coordinator))
    } else {
        for index in UInt64(0) ..< 3 {
            results.append(completeCoordinatorFrame(
                submit(index), coordinator: coordinator
            ))
        }
    }
    return .init(
        frames: results,
        deferredWhileHistoryPending: deferredWhileHistoryPending
    )
}

func sequenceMatches(
    _ sequence: CoordinatorSequenceResult,
    scales: [Float]
) -> Bool {
    sequence.frames.count == scales.count
        && zip(sequence.frames, scales).allSatisfy { frame, scale in
            frame.completed
                && approximately(frame.currentPixels, expected(scale: scale))
                && approximately(frame.historyPixels, expected(scale: scale))
                && approximately(frame.outputPixels, expected(scale: scale))
        }
}
