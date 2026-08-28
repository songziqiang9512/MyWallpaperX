#!/usr/bin/env python3

"""Production GraphExecutor gate for typed independent-RGBA feedback."""

from __future__ import annotations

import json
from pathlib import Path
import runpy
import shutil
import unittest


EXECUTOR_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_executor.py"
)
EXECUTOR_FIXTURE = runpy.run_path(str(EXECUTOR_GATE))
compile_harness = EXECUTOR_FIXTURE["compile_harness"]
SUPPORT = EXECUTOR_FIXTURE["SUPPORT"]
HARNESS_PREFIX = EXECUTOR_FIXTURE["HARNESS"].split("@main", 1)[0]


HARNESS = HARNESS_PREFIX + r'''
private func signalContract(
    nodeIndex: Int,
    fragmentSource: String
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
        stage(.vertex, path: "\(prefix).vert", source: vertexSource),
        stage(.fragment, path: "\(prefix).frag", source: fragmentSource),
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
        dependencySHA256: "independent-feedback-dependency-\(nodeIndex)"
    )
    return .init(
        identity: prefix,
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "independent-feedback-contract-\(nodeIndex)",
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

private func signalCompositeSource(validAlphaTail: Bool = true) -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
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
        signal.rgb *= vec3(1.0);
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
    fragmentSource: String
) -> Template {
    guard let target = node.target else {
        fatalError("independent feedback material target missing")
    }
    let contract = signalContract(
        nodeIndex: node.nodeIndex,
        fragmentSource: fragmentSource
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

private func signalCatalog(
    for graph: Graph,
    validComposite: Bool = true
) -> SceneResolvedMaterialRuntimeCatalog {
    let entries = Dictionary(uniqueKeysWithValues: graph.nodes.compactMap {
        node -> (SceneResolvedMaterialRuntimeCatalog.Key,
                 SceneResolvedMaterialRuntimeCatalog.Entry)? in
        guard node.kind == .material else { return nil }
        let fragment: String
        if node.nodeIndex == 0 {
            fragment = signalUpdateSource
        } else if node.nodeIndex == 1 {
            fragment = signalCompositeSource(validAlphaTail: validComposite)
        } else {
            return (
                .init(effect: node.effect, nodeIndex: node.nodeIndex),
                .template(template(for: node))
            )
        }
        return (
            .init(effect: node.effect, nodeIndex: node.nodeIndex),
            .template(signalTemplate(for: node, fragmentSource: fragment))
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

@main
private enum Harness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        var results: [String: Bool] = [:]
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

        let payload: [String: Any] = [
            "metalAvailable": true,
            "observedPixels": observedPixels,
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
