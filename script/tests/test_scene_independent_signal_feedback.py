#!/usr/bin/env python3

"""Production GraphExecutor gate for typed independent-RGBA feedback."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import unittest


EXECUTOR_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_executor.py"
)
EXECUTOR_FIXTURE = runpy.run_path(str(EXECUTOR_GATE))
compile_harness = EXECUTOR_FIXTURE["compile_harness"]
SUPPORT = EXECUTOR_FIXTURE["SUPPORT"] + r'''
// This leaf shell keeps the current optional geometry input absent. The
// feedback fixture never declares or consumes g_EffectModelMatrix.
extension SceneResolvedMaterialRuntimeBridge.FrameInputs {
    var effectUnitModelMatrix: simd_float4x4? { nil }
}
'''
HARNESS_PREFIX = EXECUTOR_FIXTURE["HARNESS"].split("@main", 1)[0]
CONTRACT_ROOT = Path(__file__).resolve().parents[2] / (
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract"
)
CONTRACT_SOURCES = [
    CONTRACT_ROOT / "SceneShaderContractLoader.swift",
    CONTRACT_ROOT / "SceneBuiltinShaderIdentity.swift",
]


HARNESS = HARNESS_PREFIX + r'''
private func signalContract(
    nodeIndex: Int,
    fragmentSource: String,
    vertex: String = vertexSource
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
    let prefix = "fixture/independent-feedback-\(nodeIndex)"
    let stages = [
        stage(.vertex, path: "\(prefix).vert", source: vertex),
        stage(.fragment, path: "\(prefix).frag", source: fragmentSource),
    ]
    // Analysis caches trust the same immutable content identity as the loader.
    // Positive and negative sources must never share a fabricated digest.
    let canonicalSHA256 = SceneShaderContractLoader.canonicalHash(
        identity: prefix,
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: []
    )!
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
        dependencySHA256: canonicalSHA256
    )
    return .init(
        identity: prefix,
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: canonicalSHA256,
        sourceGraph: sourceGraph
    )
}

private let signalUpdateSource = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
vec4 injectSignal(vec4 current, float amount) {
    return min(current + vec4(amount), vec4(1.0));
}
vec4 shapeSignal(vec4 current) {
    float amount = saturate(0.5);
    return injectSignal(current, amount);
}
void main() {
    vec4 signal = texSample2D(g_Texture0, v_TexCoord);
    gl_FragColor = signal;
    gl_FragColor = shapeSignal(gl_FragColor);
}
"""

private func signalCompositeSource(
    validAlphaTail: Bool = true, auxiliary: Bool = false
) -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    \(auxiliary ? "uniform sampler2D g_Texture2;" : "")
    vec3 ApplyBlending(
        const int mode,
        in vec3 base,
        in vec3 blend,
        in float opacity
    ) {
        return mix(base, blend, opacity);
    }
    void main() {
        vec4 signal = texSample2D(g_Texture0, v_TexCoord);
        signal.rgb *= \(auxiliary
            ? "texSample2D(g_Texture2, v_TexCoord).rgb" : "vec3(1.0)");
        vec4 previous = texSample2D(g_Texture1, v_TexCoord);
        signal.rgb = ApplyBlending(
            31, previous.rgb, signal.rgb, signal.a
        );
        signal.a = \(validAlphaTail
            ? "saturate(previous.a + signal.a)"
            : "saturate(signal.a)");
        gl_FragColor = signal;
    }
    """
}

private func signalTemplate(
    for node: Graph.Node,
    fragmentSource: String,
    vertex: String = vertexSource
) -> Template {
    guard let target = node.target else {
        fatalError("independent feedback material target missing")
    }
    let contract = signalContract(
        nodeIndex: node.nodeIndex,
        fragmentSource: fragmentSource, vertex: vertex
    )
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    for value in node.bindings {
        guard let slot = value.slot,
              slots.indices.contains(slot),
              slots[slot] == nil else {
            fatalError("independent feedback binding invalid")
        }
        slots[slot] = .init(index: slot, candidates: [
            .init(reference: .graph(value.texture), provenance: .explicitBinding),
        ])
    }
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
            nodeTarget: role(target),
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

private func signalFeedbackGraph(
    clear: SceneJSONValue? = .string("0 0 0 0"),
    commandKind: Graph.NodeKind = .swap,
    extraPairReader: Bool = false
) -> Graph {
    var nodes = [
        Graph.Node(
            nodeIndex: 0,
            effect: effect,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/independent-feedback-update.json",
            materialPassID: "independent-feedback-update#0",
            target: second,
            bindings: [binding(first, slot: 0)],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        ),
        Graph.Node(
            nodeIndex: 1,
            effect: effect,
            definitionPassIndex: 1,
            materialOrdinal: 1,
            instancePassIndex: 1,
            kind: .material,
            materialPath: "materials/independent-feedback-composite.json",
            materialPassID: "independent-feedback-composite#0",
            target: output,
            bindings: [
                binding(second, slot: 0),
                binding(input, slot: 1, authoredName: "previous"),
            ],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        ),
        command(2, kind: commandKind, source: first, target: second),
    ]
    if extraPairReader {
        nodes.insert(
            material(2, ordinal: 2, target: output, read: first),
            at: 2
        )
        nodes[3] = command(3, kind: commandKind, source: first, target: second)
    }
    return graph(
        targets: [
            rawTarget(first, unique: true, clear: clear),
            rawTarget(second, unique: true, clear: clear),
        ],
        nodes: nodes
    )
}

private func auxiliaryIdentity(slot: Int) -> Graph.TextureIdentity {
    .init(kind: .framebuffer, layerID: layerID, effect: effect,
        name: slot == 2 ? "direction-field" : "relocated-field")
}

private enum AuxiliaryRead { case alpha, red, rgb, whole, vertex }

private func auxiliarySource(slot: Int, read: AuxiliaryRead) -> String {
    let expression: String
    switch read {
    case .alpha: expression = "vec4(vec3(sampleValue), 1.0)"
    case .red: expression = "vec4(vec3(sampleValue), 1.0)"
    case .rgb: expression = "vec4(sampleValue, 1.0)"
    case .whole: expression = "sampleValue"
    case .vertex: expression = "vec4(1.0)"
    }
    if read == .vertex {
        return "varying vec2 v_TexCoord; void main(){gl_FragColor=\(expression);}"
    }
    let component: String
    switch read {
    case .alpha: component = slot == 2 ? ".a" : ".w"
    case .red: component = ".r"
    case .rgb: component = ".rgb"
    case .whole, .vertex: component = ""
    }
    let type = read == .whole ? "vec4" : read == .rgb ? "vec3" : "float"
    return """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture\(slot);
    void main(){
        \(type) sampleValue=\(slot == 2 ? "texSample2D" : "texture2D")(
            g_Texture\(slot),v_TexCoord)\(component);
        gl_FragColor=\(expression);
    }
    """
}

private func alphaReaderGraph(
    slot: Int = 2, historyRead: Bool = false, beforeUpdate: Bool = false,
    afterTerminal: Bool = false, afterSwap: Bool = false,
    conditional: Bool = false, duplicatePairBinding: Bool = false,
    extraWriter: Bool = false, secondTerminal: Bool = false
) -> Graph {
    let auxiliary = auxiliaryIdentity(slot: slot)
    let updateIndex = beforeUpdate ? 1 : 0
    let readerIndex = beforeUpdate ? 0 : afterTerminal ? 3 : afterSwap ? 4 : 1
    let swapIndex = afterTerminal || extraWriter || secondTerminal ? 4 : 3
    var nodes = [
        material(updateIndex, ordinal: 0, target: second, read: first),
        material(readerIndex, ordinal: 1, target: auxiliary,
            read: historyRead ? first : second,
            conditions: conditional ? .bool(true) : nil),
        material(2, ordinal: 2, target: output, read: second,
            additionalBindings: [binding(input, slot: 1), binding(auxiliary, slot: 2)]),
        command(swapIndex, kind: .swap, source: first, target: second),
    ]
    let reader = nodes[1]
    nodes[1] = .init(nodeIndex: reader.nodeIndex, effect: reader.effect,
        definitionPassIndex: reader.definitionPassIndex, materialOrdinal: reader.materialOrdinal,
        instancePassIndex: reader.instancePassIndex, kind: .material,
        materialPath: "materials/alpha-reader-\(slot).json",
        materialPassID: "alpha-reader-\(slot)#0", target: auxiliary,
        bindings: [binding(historyRead ? first : second, slot: slot)]
            + (duplicatePairBinding ? [binding(second, slot: 7)] : []),
        commandSource: nil, commandTarget: nil, compose: nil,
        conditions: reader.conditions)
    if extraWriter { nodes.append(material(3, ordinal: 3, target: second, read: first)) }
    if secondTerminal {
        nodes.append(material(3, ordinal: 3, target: output, read: second,
            additionalBindings: [binding(input, slot: 1), binding(auxiliary, slot: 2)]))
    }
    return graph(targets: [rawTarget(first, unique: true, clear: .string("0 0 0 0")),
        rawTarget(second, unique: true, clear: .string("0 0 0 0")), rawTarget(auxiliary)],
        nodes: nodes.sorted { $0.nodeIndex < $1.nodeIndex })
}

private func signalCatalog(
    for graph: Graph,
    validComposite: Bool = true, auxiliaryRead: AuxiliaryRead = .alpha
) -> SceneResolvedMaterialRuntimeCatalog {
    let entries = Dictionary(uniqueKeysWithValues: graph.nodes.compactMap {
        node -> (SceneResolvedMaterialRuntimeCatalog.Key,
                 SceneResolvedMaterialRuntimeCatalog.Entry)? in
        guard node.kind == .material else { return nil }
        let fragment: String
        var vertex = vertexSource
        if node.target == second {
            fragment = signalUpdateSource
        } else if node.target == output,
                  node.bindings.contains(where: { $0.texture == input }) {
            fragment = signalCompositeSource(validAlphaTail: validComposite,
                auxiliary: node.bindings.contains(where: { $0.slot == 2 }))
        } else if let slot = node.bindings.first?.slot,
                  node.target == auxiliaryIdentity(slot: slot) {
            fragment = auxiliarySource(slot: slot, read: auxiliaryRead)
            if auxiliaryRead == .vertex {
                vertex = vertexSource.replacingOccurrences(of: "void main() {", with:
                    "uniform sampler2D g_Texture\(slot);\nvoid main() {")
                    .replacingOccurrences(of: "vec4(a_Position, 1.0)", with:
                        "vec4(a_Position.xy, texSample2D(g_Texture\(slot),a_TexCoord).a, 1.0)")
            }
        } else {
            return (
                .init(effect: node.effect, nodeIndex: node.nodeIndex),
                .template(template(for: node))
            )
        }
        return (
            .init(effect: node.effect, nodeIndex: node.nodeIndex),
            .template(signalTemplate(for: node, fragmentSource: fragment, vertex: vertex))
        )
    })
    return .init(entries: entries)
}

private func prepareSignalGraph(
    _ graph: Graph,
    catalog: SceneResolvedMaterialRuntimeCatalog,
    device: MTLDevice,
    queue: MTLCommandQueue,
    generation: UInt64,
    previousState: Executor.State? = nil,
    previousResources: [Graph.TextureIdentity: SceneFrameTextureResource] = [:]
) -> (
    executor: Executor,
    token: Capabilities.Token,
    lease: SceneGraphRenderTargetLease,
    buffer: MTLCommandBuffer,
    prepared: Executor.PreparedGraph
)? {
    let chain = admittedGraph(graph)
    let values = capabilities(chain, catalog: catalog)
    guard let claim = values.claim(chain),
          let capability = values.resolve(claim.token),
          capability.graphFramebufferColorRepresentations[first]
            == .independentAlphaSignal,
          capability.graphFramebufferColorRepresentations[second]
            == .independentAlphaSignal,
          let executor = Executor(device: device, capabilities: values),
          let buffer = queue.makeCommandBuffer() else { return nil }
    let lease = makeLease(
        requirePlan(graph),
        device: device,
        generation: generation
    )
    let prepared = executor.prepare(
        token: claim.token,
        leases: [lease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(generation),
        sourceTexture: makeSource(device),
        sourceUniforms: .neutral(),
        sourcePipeline: makeSourcePipeline(device),
        frameInputs: .init(),
        commandBuffer: buffer,
        previousStates: previousState.map { [effect: $0] } ?? [:],
        previousGraphResources: previousState == nil
            ? [:] : [effect: previousResources],
        effectGeneration: 71,
        resetGeneration: 71
    )
    guard case let .success(value) = prepared else { return nil }
    return (executor, claim.token, lease, buffer, value)
}

private func runAlphaFeedback(
    device: MTLDevice, queue: MTLCommandQueue, slot: Int
) -> (results: [String: Bool], pixels: [String: [UInt8]]) {
    let graph = alphaReaderGraph(slot: slot)
    let catalog = signalCatalog(for: graph)
    var results: [String: Bool] = [:]
    var pixels: [String: [UInt8]] = [:]
    guard let firstRun = prepareSignalGraph(graph, catalog: catalog,
        device: device, queue: queue, generation: 81),
        firstRun.executor.encode(firstRun.prepared, commandBuffer: firstRun.buffer),
        let readback = appendReadback(firstRun.prepared.finalTexture,
            commandBuffer: firstRun.buffer) else {
        return (["firstPreparationAndEncoding": false], pixels)
    }
    firstRun.buffer.commit()
    firstRun.buffer.waitUntilCompleted()
    let stage = firstRun.prepared.stages[0]
    pixels["first"] = readback.firstPixel
    results["firstCompletedAndVisible"] = firstRun.buffer.status == .completed
        && firstRun.buffer.error == nil
        && matches(readback.firstPixel, [32, 32, 159, 255])
        && matches(readback.lastPixel, [32, 32, 159, 255])
    results["firstInitializationAndThreeMaterials"] = intentKinds(firstRun.prepared) == [
        "initialize", "initialize", "material", "material", "material", "swap",
    ]
    results["actualPublicationsRemainSignalAndOpaque"] =
        stage.persistentResources[first]?.publication.candidate.content
            == .color(.resolved(.independentAlphaSignal))
        && stage.persistentResources[second]?.publication.candidate.content
            == .color(.resolved(.independentAlphaSignal))
        && stage.frameResources[auxiliaryIdentity(slot: slot)]?.publication.candidate.content
            == .color(.resolved(.opaque))
    guard let nextBuffer = queue.makeCommandBuffer() else {
        results["nextCommandBuffer"] = false
        return (results, pixels)
    }
    let preparation = firstRun.executor.prepare(token: firstRun.token,
        leases: [firstRun.lease], historyRehydrateCopiesByEffect: [:], frame: frame(82),
        sourceTexture: makeSource(device), sourceUniforms: .neutral(),
        sourcePipeline: makeSourcePipeline(device), frameInputs: .init(),
        commandBuffer: nextBuffer, previousStates: [effect: stage.transition.nextState],
        previousGraphResources: [effect: stage.persistentResources],
        effectGeneration: 71, resetGeneration: 71)
    guard case let .success(next) = preparation,
        firstRun.executor.encode(next, commandBuffer: nextBuffer),
        let nextReadback = appendReadback(next.finalTexture, commandBuffer: nextBuffer)
    else {
        results["nextPreparationAndEncoding"] = false
        return (results, pixels)
    }
    nextBuffer.commit()
    nextBuffer.waitUntilCompleted()
    pixels["next"] = nextReadback.firstPixel
    results["nextCompletedAndReusesHistory"] = nextBuffer.status == .completed
        && nextBuffer.error == nil
        && intentKinds(next) == ["material", "material", "material", "swap"]
        && matches(nextReadback.firstPixel, [255, 255, 255, 255])
        && matches(nextReadback.lastPixel, [255, 255, 255, 255])
    return (results, pixels)
}

private func alphaFeedbackQualifications(
    observations: inout [String: String]
) -> [String: Bool] {
    var results: [String: Bool] = [:]
    func resolve(_ graph: Graph) -> Capabilities.LayerCapability? {
        let chain = admittedGraph(graph)
        let values = capabilities(chain, catalog: signalCatalog(for: graph))
        return values.claim(chain).flatMap { values.resolve($0.token) }
    }
    let baselineGraph = alphaReaderGraph()
    guard let baseline = resolve(baselineGraph),
        let update = baseline.material(for: baselineGraph.nodes[0]),
        let reader = baseline.material(for: baselineGraph.nodes[1]),
        let terminal = baseline.material(for: baselineGraph.nodes[2]) else {
        return ["alphaReaderPreparedFixtureAvailable": false]
    }
    func readyMaterials(_ graph: Graph) -> [Capabilities.MaterialKey: Capabilities.MaterialCapability] {
        Dictionary(uniqueKeysWithValues: graph.nodes.filter { $0.kind == .material }.map { node in
            let prototype = node.target == second ? update : node.target == output ? terminal : reader
            let key = Capabilities.MaterialKey(effect: node.effect, nodeIndex: node.nodeIndex)
            return (key, .init(key: key, template: prototype.template, variants: prototype.variants,
                attachmentStorage: prototype.attachmentStorage, targetFormat: prototype.targetFormat))
        })
    }
    func rejects(_ graph: Graph,
        materials: [Capabilities.MaterialKey: Capabilities.MaterialCapability]) -> Bool {
        materials.count == graph.nodes.filter { $0.kind == .material }.count
            && materials.values.allSatisfy {
                let snapshot = $0.variants.launchEnvelopeCapabilitySnapshot()
                return snapshot.allEntriesReady && !snapshot.variants.isEmpty
            }
            && Capabilities.independentAlphaSignalTargetRepresentations(graph,
                materials: materials).isEmpty
    }
    for slot in [2, 5] {
        let graph = alphaReaderGraph(slot: slot)
        let capability = resolve(graph)
        results["alphaReaderTyped-\(slot)"] =
            capability?.graphFramebufferColorRepresentations[first] == .independentAlphaSignal
            && capability?.graphFramebufferColorRepresentations[second] == .independentAlphaSignal
        let node = graph.nodes.first { $0.target == auxiliaryIdentity(slot: slot) }!
        let material = capability?.material(for: node)
        let variants = material?.variants.launchEnvelopeCapabilitySnapshot()
        results["alphaReaderPreparedOpaqueAndAlphaOnly-\(slot)"] =
            variants?.allEntriesReady == true && variants?.variants.isEmpty == false
            && variants!.variants.allSatisfy {
                $0.frontendProgram.colorTransfer == .opaque
                    && $0.frontendProgram.textureBindings.map(\.slot) == [slot]
                    && $0.frontendProgram.textureBindings[0].channelUse == .alphaOnly
                    && $0.frontendProgram.colorBoundary?.alphaInputSlots == [slot]
            }
        if let capability, let material,
            case let .success(emptyCache) = SceneResolvedMaterialVariantCache.launchValidated(
                template: material.template, maximumVariantCount: 8) {
            var missing = capability.materials
            let key = material.key
            missing.removeValue(forKey: key)
            results["alphaReaderMissingPreparedMaterialRejected-\(slot)"] =
                Capabilities.independentAlphaSignalTargetRepresentations(graph, materials: missing).isEmpty
            missing[key] = .init(key: key, template: material.template, variants: emptyCache,
                attachmentStorage: material.attachmentStorage, targetFormat: material.targetFormat)
            results["alphaReaderEmptyVariantEnvelopeRejected-\(slot)"] =
                Capabilities.independentAlphaSignalTargetRepresentations(graph, materials: missing).isEmpty
        } else { results["alphaReaderMissingPreparedProofFixture-\(slot)"] = false }
    }
    for (name, graph) in [
        ("history", alphaReaderGraph(historyRead: true)),
        ("preupdate", alphaReaderGraph(beforeUpdate: true)),
        ("postterminal", alphaReaderGraph(afterTerminal: true)),
        ("postswap", alphaReaderGraph(afterSwap: true)),
        ("conditional", alphaReaderGraph(conditional: true)),
        ("duplicate-pair-binding", alphaReaderGraph(duplicatePairBinding: true)),
        ("extra-writer", alphaReaderGraph(extraWriter: true)),
        ("second-terminal", alphaReaderGraph(secondTerminal: true)),
    ] {
        // Programs are already ready. Rekey each program by its actual role,
        // so missing/misplaced material cannot impersonate topology rejection.
        results["alphaReaderReject-" + name] = rejects(graph, materials: readyMaterials(graph))
    }
    for (name, read, content, expectedChannel) in [
        ("red", AuxiliaryRead.red, SceneTextureContent.data,
            SceneAuthoredShaderProgram.TextureBinding.ChannelUse.redOnly),
        ("rgb", .rgb, .color(.resolved(.premultipliedAlpha)), .unproven),
        ("whole", .whole, .color(.resolved(.premultipliedAlpha)), .wholeVector),
        ("vertex", .vertex, .color(.resolved(.premultipliedAlpha)), .unproven),
    ] {
        let graph = baselineGraph
        let node = graph.nodes[1]
        let catalog = signalCatalog(for: graph, auxiliaryRead: read)
        guard case let .template(template)? = catalog.entry(for: node),
            case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
                template: template, maximumVariantCount: 8) else {
            results["alphaReaderReject-" + name] = false
            continue
        }
        let launch = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: input,
            outputIsRGBA8Unorm: true, graphTextureContentFacts: [second: content])
        let snapshot = cache.launchEnvelopeCapabilitySnapshot()
        let prepared = {
            guard case .success = launch, snapshot.allEntriesReady,
                !snapshot.variants.isEmpty else { return false }
            return snapshot.variants.allSatisfy {
                $0.frontendProgram.textureBindings.map(\.slot) == [2]
                    && $0.frontendProgram.textureBindings[0].channelUse == expectedChannel
                    && $0.activeSamplers[2] != nil
                    && $0.frontendProgram.colorBoundary?.alphaInputSlots.contains(2) != true
            }
        }()
        observations["channel-" + name] = "ready=\(prepared),variants=\(snapshot.variants.count),"
            + "channels=\(snapshot.variants.flatMap { $0.frontendProgram.textureBindings.map { $0.channelUse.rawValue } }),"
            + "alphaSlots=\(snapshot.variants.map { $0.frontendProgram.colorBoundary?.alphaInputSlots ?? [] })"
        var materials = readyMaterials(graph)
        materials[reader.key] = .init(key: reader.key, template: template, variants: cache,
            attachmentStorage: reader.attachmentStorage, targetFormat: reader.targetFormat)
        results["alphaReaderReject-" + name] = prepared && rejects(graph, materials: materials)
    }
    results["alphaReaderPositiveAfterNegative"] =
        Capabilities.independentAlphaSignalTargetRepresentations(baselineGraph,
            materials: baseline.materials)[first] == .independentAlphaSignal
    return results
}

@main
private enum Harness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        var observations: [String: String] = [:]
        var results = alphaFeedbackQualifications(observations: &observations)
        var observedPixels: [String: [UInt8]] = [:]
        let graph = signalFeedbackGraph()
        let catalog = signalCatalog(for: graph)

        if let firstRun = prepareSignalGraph(
            graph,
            catalog: catalog,
            device: device,
            queue: queue,
            generation: 71
        ), firstRun.executor.encode(
            firstRun.prepared,
            commandBuffer: firstRun.buffer
        ), let readback = appendReadback(
            firstRun.prepared.finalTexture,
            commandBuffer: firstRun.buffer
        ) {
            firstRun.buffer.commit()
            firstRun.buffer.waitUntilCompleted()
            let stage = firstRun.prepared.stages[0]
            observedPixels["first"] = readback.firstPixel
            results["firstFrameGPUCompleted"] =
                firstRun.buffer.status == .completed && firstRun.buffer.error == nil
            results["firstFrameVisible"] =
                matches(readback.firstPixel, [64, 64, 191, 255])
                && matches(readback.lastPixel, [64, 64, 191, 255])
            results["typedSignalPublishedAndSwapped"] =
                stage.persistentResources[first]?.publication.candidate.content
                    == .color(.resolved(.independentAlphaSignal))
                && stage.persistentResources[second]?.publication.candidate.content
                    == .color(.resolved(.independentAlphaSignal))
                && intentKinds(firstRun.prepared) == [
                    "initialize", "initialize", "material", "material", "swap",
                ]

            if let nextBuffer = queue.makeCommandBuffer() {
                let nextPreparation = firstRun.executor.prepare(
                    token: firstRun.token,
                    leases: [firstRun.lease],
                    historyRehydrateCopiesByEffect: [:],
                    frame: frame(72),
                    sourceTexture: makeSource(device),
                    sourceUniforms: .neutral(),
                    sourcePipeline: makeSourcePipeline(device),
                    frameInputs: .init(),
                    commandBuffer: nextBuffer,
                    previousStates: [effect: stage.transition.nextState],
                    previousGraphResources: [
                        effect: stage.persistentResources,
                    ],
                    effectGeneration: 71,
                    resetGeneration: 71
                )
                if case let .success(nextPrepared) = nextPreparation,
                   firstRun.executor.encode(
                       nextPrepared,
                       commandBuffer: nextBuffer
                   ), let nextReadback = appendReadback(
                       nextPrepared.finalTexture,
                       commandBuffer: nextBuffer
                   ) {
                    nextBuffer.commit()
                    nextBuffer.waitUntilCompleted()
                    observedPixels["next"] = nextReadback.firstPixel
                    results["nextFrameGPUCompleted"] =
                        nextBuffer.status == .completed && nextBuffer.error == nil
                    results["nextFrameReusesSignalHistory"] =
                        intentKinds(nextPrepared) == [
                            "material", "material", "swap",
                        ]
                        && matches(
                            nextReadback.firstPixel,
                            [255, 255, 255, 255]
                        )
                        && matches(
                            nextReadback.lastPixel,
                            [255, 255, 255, 255]
                        )
                }
            }
        }

        func notTyped(
            _ graph: Graph,
            validComposite: Bool = true
        ) -> Bool {
            let chain = admittedGraph(graph)
            let values = capabilities(
                chain,
                catalog: signalCatalog(
                    for: graph,
                    validComposite: validComposite
                )
            )
            guard let claim = values.claim(chain),
                  let capability = values.resolve(claim.token) else { return true }
            return capability.graphFramebufferColorRepresentations[first] == nil
                && capability.graphFramebufferColorRepresentations[second] == nil
        }
        results["nonzeroClearDoesNotAcquireSignalType"] = notTyped(
            signalFeedbackGraph(clear: .string("0.1 0 0 0"))
        )
        results["copyDoesNotAcquireSignalType"] = notTyped(
            signalFeedbackGraph(commandKind: .copy)
        )
        results["extraReaderDoesNotAcquireSignalType"] = notTyped(
            signalFeedbackGraph(extraPairReader: true)
        )
        results["wrongCompositeDoesNotAcquireSignalType"] = notTyped(
            signalFeedbackGraph(),
            validComposite: false
        )
        let validSourceIdentity = signalContract(
            nodeIndex: 1, fragmentSource: signalCompositeSource()
        ).canonicalSHA256
        results["sourceIdentitySeparatesPositiveAndNegative"] =
            validSourceIdentity != signalContract(
                nodeIndex: 1,
                fragmentSource: signalCompositeSource(validAlphaTail: false)
            ).canonicalSHA256
        results["sourceIdentityStableForRepeatedContent"] =
            validSourceIdentity == signalContract(
                nodeIndex: 1, fragmentSource: signalCompositeSource()
            ).canonicalSHA256
        // Revisit the positive input after the negative one in the same cache
        // lifetime: neither analysis result may poison the other direction.
        results["positiveRemainsTypedAfterNegative"] = !notTyped(
            signalFeedbackGraph()
        )

        for slot in [2, 5] {
            let value = runAlphaFeedback(device: device, queue: queue, slot: slot)
            for (name, passed) in value.results { results["alphaGPU-\(slot)-" + name] = passed }
            for (name, pixel) in value.pixels { observedPixels["alphaGPU-\(slot)-" + name] = pixel }
        }

        let payload: [String: Any] = [
            "metalAvailable": true,
            "observedPixels": observedPixels,
            "observations": observations,
            "results": results,
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
class SceneIndependentSignalFeedbackTests(unittest.TestCase):
    def test_feedback_executes_and_unsafe_shapes_stay_untyped(self) -> None:
        compilation, completed = compile_harness(
            SUPPORT, HARNESS, additional_sources=CONTRACT_SOURCES
        )
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        evidence = os.environ.get("MWX_SIGNAL_FEEDBACK_EVIDENCE")
        if evidence:
            destination = Path(evidence)
            destination.mkdir(parents=True, exist_ok=True)
            (destination / "result.json").write_text(json.dumps(payload, indent=2) + "\n")
            (destination / "compile.log").write_text(compilation.stdout + compilation.stderr)
            (destination / "run.stderr").write_text(completed.stderr)
            (destination / "test-sha256.txt").write_text(
                hashlib.sha256(Path(__file__).read_bytes()).hexdigest() + "\n")
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
