
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
private var debugLastCandidateFailureCode = ""
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
private let systemProviderName = "$mediaThumbnail"
private let systemProviderIdentity = SceneSystemProviderTextureIdentity(
    name: systemProviderName,
    purpose: .preservedChannels
)
private let systemProviderFallbackPath = SceneVFSAssetPath(
    "textures/unseen-system-provider-fallback.tex"
)!
private let systemProviderFallbackIdentity = SceneAssetTextureIdentity(
    path: systemProviderFallbackPath,
    purpose: .preservedChannels
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
    systemProviderMix: Bool = false,
    mixedSystemNamedBlend: Bool = false,
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
    let samplers = crossLayerMix || systemProviderMix
        ? primarySampler + (systemProviderMix
            ? mixedSystemNamedBlend
                ? "\nuniform sampler2D g_Texture1; // {\"mode\":\"rgbmask\",\"default\":\"util/white\"}"
                : "\nuniform sampler2D g_Texture1; // {\"mode\":\"rgbmask\"}"
            : "\nuniform sampler2D g_Texture1;")
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
    let blendHelper = mixedSystemNamedBlend ? """
    uniform float g_Multiply; // {"material":"multiply","default":0.5}
    uniform float g_AlphaMultiply; // {"material":"alpha","default":0.5}
    vec3 ApplyBlending(
        const int mode,
        in vec3 base,
        in vec3 blend,
        in float opacity
    ) {
        return mix(base, blend, opacity);
    }
    """ : ""
    let expression = if mixedSystemNamedBlend {
        "vec4 color = texSample2D(g_Texture0, v_TexCoord);"
            + " vec4 overlay = texSample2D(g_Texture1, v_TexCoord);"
            + " float weight = g_Multiply * overlay.a;"
            + " color.rgb = ApplyBlending(0, color.rgb, overlay.rgb, weight);"
            + " color.a = overlay.a * g_AlphaMultiply; gl_FragColor = color;"
    } else if systemProviderMix {
        "vec4 color = texSample2D(g_Texture0, v_TexCoord);"
            + " float auxiliary = texSample2D(g_Texture1, v_TexCoord).r;"
            + " color.rgb *= auxiliary; gl_FragColor = color;"
    } else if crossLayerMix {
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
        "vec4 color = texSample2D(g_Texture0, v_TexCoord);"
            + " color.rgb *= g_Time; gl_FragColor = color;"
    } else if scalarProducerUnproven {
        "if (v_TexCoord.x > 0.5) gl_FragColor = vec4(0.25);"
    } else if scalarProducer {
        "float signal = 0.5 * 0.5;"
            + " gl_FragColor = vec4(signal, signal * 2.0, 0.75, 0.0);"
    } else if scalarConsumer == "red" {
        "float scalar = texSample2D(g_Texture0, \(sampleCoordinate)).r;"
            + " gl_FragColor = vec4(scalar, 0.0, 0.0, 1.0);"
    } else if scalarConsumer == "rg" {
        "vec2 pair = texSample2D(g_Texture0, \(sampleCoordinate)).rg;"
            + " gl_FragColor = vec4(pair, 0.0, 1.0);"
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
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord.yz);"
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
    \(blendHelper)
    void main() {
        \(expression)
    }
    """
}

private func binding(
    _ identity: Graph.TextureIdentity,
    slot: Int = 0,
    authoredName: String? = nil,
    conditions: SceneJSONValue? = nil
) -> Graph.Binding {
    return .init(
        slot: slot,
        authoredName: authoredName ?? identity.name ?? "previous",
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
    additionalBindings: [Graph.Binding] = [],
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
        bindings: [binding(read)] + additionalBindings,
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

private func dormantGraphInputMaterial(
    _ nodeIndex: Int,
    owner: Graph.EffectKey,
    target: Graph.TextureIdentity
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: owner,
        definitionPassIndex: 0,
        materialOrdinal: 0,
        instancePassIndex: 0,
        kind: .material,
        materialPath: "materials/dormant-graph-input-\(nodeIndex).json",
        materialPassID: "dormant-graph-input-\(nodeIndex)#0",
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

private func dormantGraphInputChainGraph() -> Graph {
    let nodes = [
        dormantGraphInputMaterial(
            0,
            owner: chainedFirstEffect,
            target: chainedFirstOutput
        ),
        dormantGraphInputMaterial(
            1,
            owner: chainedSecondEffect,
            target: chainedSecondOutput
        ),
    ]
    return .init(
        layerID: layerID,
        effects: [
            .init(
                key: chainedFirstEffect,
                definitionPath: "effects/dormant-first/effect.json",
                input: input,
                output: chainedFirstOutput,
                nodeIndices: [0]
            ),
            .init(
                key: chainedSecondEffect,
                definitionPath: "effects/dormant-second/effect.json",
                input: chainedFirstOutput,
                output: chainedSecondOutput,
                nodeIndices: [1]
            ),
        ],
        renderTargets: [],
        nodes: nodes,
        finalOutput: chainedSecondOutput,
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
        inputRole: inputRole
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
    precondition(graph.effects.count >= 2)
    let stages = graph.effects.enumerated().map { index, effect in
        let stageGraph = Graph(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: graph.renderTargets.filter { $0.texture.effect == effect.key },
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
