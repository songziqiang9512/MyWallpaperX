private func shaderContract(
    nodeIndex: Int,
    pass: Bool,
    internalDefault: Bool = false,
    renderTargetDefault: String? = nil,
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
    dormantUnresolvedMaterialKey: String? = nil,
    scalarProducer: Bool = false,
    scalarProducerUnproven: Bool = false,
    scalarConsumer: String? = nil,
    repeatProbe: Bool = false,
    crossLayerMix: Bool = false,
    systemProviderMix: Bool = false,
    mixedSystemNamedBlend: Bool = false,
    colorBlend: Bool = false,
    constantColor: String? = nil,
    explicitPreviousSampler: Bool = false,
    fragmentOverride: String? = nil
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
    let dormantFragment = dormantUnresolvedMaterialKey.map { materialKey in
        """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"material":"\(materialKey)","label":"Random fixture label","hidden":true}
        void main() {
            \(pixelTransform == nil
                ? "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
                : "vec4 color = texSample2D(g_Texture0, v_TexCoord); color.rgb = color.rgb.gbr; gl_FragColor = color;")
        }
        """
    }
    let targetDefaultFragment = renderTargetDefault.map { token in
        """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"default":"\(token)","hidden":true,"material":"albedo"}
        void main() {
            vec4 color = texSample2D(g_Texture0, v_TexCoord);
            \(pixelTransform == 0 ? "" : "color.rgb = color.rgb.gbr;")
            gl_FragColor = color;
        }
        """
    }
    let literalFragment = constantColor.map { color in
        "varying vec2 v_TexCoord; void main() { gl_FragColor = vec4(\(color), 1.0); }"
    }
    var fragment = fragmentOverride ?? literalFragment ?? targetDefaultFragment ?? dormantFragment ?? (implicitFramebuffer ? (implicitFramebufferAnnotation
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
        systemProviderMix: systemProviderMix,
        mixedSystemNamedBlend: mixedSystemNamedBlend,
        colorBlend: colorBlend
    ))
    if explicitPreviousSampler {
        fragment = fragment.replacingOccurrences(of: "uniform sampler2D g_Texture0;",
            with: #"uniform sampler2D g_Texture0; // {"material":"previous"}"#)
    }
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
        dependencySHA256: SceneShaderStableDigest.hash(stages)
    )
    return .init(
        identity: "fixture/executor-\(nodeIndex)",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        // The analysis cache trusts the producer's source identity. A node
        // number is not a contract digest: the same node is deliberately
        // exercised with different shader behavior throughout this harness.
        canonicalSHA256: SceneShaderStableDigest.hash(stages),
        sourceGraph: sourceGraph
    )
}

private func implicitFramebufferTemplate(
    for node: Graph.Node,
    historicalAlias: Bool = false,
    renderTargetDefault: String? = nil,
    candidateAsset: SceneVFSAssetPath? = nil
) -> Template {
    guard let target = node.target, node.bindings.isEmpty else {
        fatalError("implicit framebuffer fixture is incomplete")
    }
    let contract = shaderContract(
        nodeIndex: node.nodeIndex,
        pass: false,
        renderTargetDefault: renderTargetDefault,
        implicitFramebuffer: true,
        implicitFramebufferAnnotation: historicalAlias,
        historicalFramebufferAlias: historicalAlias
    )
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    if let candidateAsset { slots[0] = .init(index: 0, candidates: [.init(reference: .asset(candidateAsset), provenance: .instance)]) }
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

private func dormantGraphInputTemplate(
    for node: Graph.Node,
    effect: Graph.Effect,
    materialKey: String,
    pixelTransform: Int
) -> Template {
    guard node.effect == effect.key,
          node.bindings.isEmpty,
          let target = node.target else {
        fatalError("dormant graph-input fixture is incomplete")
    }
    let contract = shaderContract(
        nodeIndex: node.nodeIndex,
        pass: true,
        pixelTransform: pixelTransform,
        dormantUnresolvedMaterialKey: materialKey
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
            effectInput: role(effect.input),
            effectOutput: role(effect.output),
            nodeTarget: role(target),
            bindings: []
        ),
        effectContext: .init(key: effect.key, input: effect.input),
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
    systemProvider: String? = nil,
    userPropertyProvider: String? = nil,
    systemProviderHighest: Bool = true,
    systemProviderLowerReference: Template.TextureReference? = nil,
    mixedSystemNamedBlendOverride: Bool? = nil,
    colorBlendMaskPath: SceneVFSAssetPath? = nil,
    explicitPreviousSampler: Bool = false
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
        systemProviderMix: systemProvider != nil || userPropertyProvider != nil,
        mixedSystemNamedBlend: mixedSystemNamedBlendOverride ?? {
            guard let lower = systemProviderLowerReference else {
                return false
            }
            if case .provider(.namedLayerTarget) = lower { return true }
            return false
        }(),
        colorBlend: colorBlendMaskPath != nil,
        explicitPreviousSampler: explicitPreviousSampler
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
    if let systemProvider {
        let hasNamedLowerCandidate: Bool = {
            guard let lower = systemProviderLowerReference else {
                return false
            }
            if case .provider(.namedLayerTarget) = lower { return true }
            return false
        }()
        let lower = Template.TextureCandidate(
                reference: systemProviderLowerReference
                    ?? .asset(systemProviderFallbackPath),
                provenance: .material
            )
        let provider = Template.TextureCandidate(
                reference: .provider(.system(systemProvider)),
                provenance: hasNamedLowerCandidate ? .userTexture : .instance
            )
        slots[1] = .init(
            index: 1,
            candidates: systemProviderHighest
                ? [lower, provider] : [provider, lower]
        )
    }
    if let userPropertyProvider,
       let lower = systemProviderLowerReference {
        slots[1] = .init(index: 1, candidates: [
            .init(reference: lower, provenance: .instance),
            .init(
                reference: .userProperty(.init(key: userPropertyProvider)),
                provenance: .userTexture
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
    dormantGraphInputNodes: Set<Int> = [],
    scalarProducerNodes: Set<Int> = [],
    scalarProducerUnprovenNodes: Set<Int> = [],
    scalarConsumerNodes: [Int: String] = [:],
    repeatProbeNodes: Set<Int> = [],
    pixelTransformsByNode: [Int: Int] = [:],
    namedProvidersByNode: [Int: SceneNamedTextureReference] = [:],
    systemProvidersByNode: [Int: String] = [:],
    userPropertyProvidersByNode: [Int: String] = [:],
    systemProviderBelowAssetNodes: Set<Int> = [],
    systemProviderLowerReferencesByNode:
        [Int: Template.TextureReference] = [:],
    nonMixedSystemNamedNodes: Set<Int> = [],
    colorBlendNodes: Set<Int> = []
) -> SceneResolvedMaterialRuntimeCatalog {
    var entries: [
        SceneResolvedMaterialRuntimeCatalog.Key:
            SceneResolvedMaterialRuntimeCatalog.Entry
    ] = [:]
    for node in graph.nodes where node.kind == .material {
        guard !omittedNodes.contains(node.nodeIndex) else { continue }
        let value = dormantGraphInputNodes.contains(node.nodeIndex)
            ? dormantGraphInputTemplate(
                for: node,
                effect: graph.effects.first(where: {
                    $0.key == node.effect
                })!,
                materialKey: "Arbitrary source \(node.nodeIndex)",
                pixelTransform: pixelTransformsByNode[node.nodeIndex] ?? 1
            )
            : implicitFramebufferNodes.contains(node.nodeIndex)
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
                systemProvider: systemProvidersByNode[node.nodeIndex],
                userPropertyProvider:
                    userPropertyProvidersByNode[node.nodeIndex],
                systemProviderHighest:
                    !systemProviderBelowAssetNodes.contains(node.nodeIndex),
                systemProviderLowerReference:
                    systemProviderLowerReferencesByNode[node.nodeIndex],
                mixedSystemNamedBlendOverride:
                    nonMixedSystemNamedNodes.contains(node.nodeIndex)
                        ? false : nil,
                colorBlendMaskPath: colorBlendNodes.contains(node.nodeIndex)
                    ? colorBlendMaskPath : nil
            )
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(value, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))
    }
    let issues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue> =
        Set(demandIssueNodes.map { nodeIndex in
            let node = graph.nodes.first { $0.nodeIndex == nodeIndex }!
            return SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue(
                key: .init(effect: node.effect, nodeIndex: nodeIndex),
                slot: node.bindings.first?.slot ?? 0
            )
        })
    return .init(entries: entries, resourceDemandIssues: issues)
}
