private func densityTemplate(
    _ node: Graph.Node, renamed: Bool = false, legacyVertex: Bool = false,
    colorKind: String? = nil, provider: SceneNamedTextureReference? = nil
) -> Template {
    let base = template(for: node)
    // Reuse the graph fixture's existing mix helper and the separately tested
    // zero-base associated-output grammar; do not emulate outer blending.
    let blendSource = fragmentSource(pass: false, colorBlend: true)
    let helperStart = blendSource.range(of: "vec3 ApplyBlending(")!.lowerBound
    let helperEnd = blendSource.range(of: "void main()")!.lowerBound
    let helper = String(blendSource[helperStart..<helperEnd])
    let fragment = if colorKind == "straight" { """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture1;
        void main() { gl_FragColor = texSample2D(g_Texture1, v_TexCoord); }
        """ } else if colorKind == "pma" { """
        \(helper)
        void main() {
            float weight = 128.0 / 255.0;
            vec3 tint = vec3(204.0 / 255.0, 102.0 / 255.0, 51.0 / 255.0);
            vec4 color = vec4(0.0);
            color.rgb = ApplyBlending(31, color.rgb, tint, weight);
            color.a = max(color.a, weight);
            gl_FragColor = color;
        }
        """ } else if colorKind == "opaque" { """
        void main() { gl_FragColor = vec4(102.0 / 255.0, 51.0 / 255.0, 26.0 / 255.0, 1.0); }
        """ } else { """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        uniform vec4 g_Texture0Resolution;
        void main() {
            vec4 sourceColor = texSample2D(g_Texture0, v_TexCoord);
            sourceColor.rgb *= vec3(step(0.5, fract(v_TexCoord.x * 64.0)),
                g_Texture0Resolution.x * 0.1, g_Texture0Resolution.y * 0.1);
            gl_FragColor = sourceColor;
        }
        """ }
    let original = shaderContract(nodeIndex: node.nodeIndex, pass: false, fragmentOverride: fragment)
    let stages = original.stages.map { stage -> SceneShaderContract.Stage in
        var source = stage.source
        if legacyVertex && stage.kind == .vertex {
            source = source.replacingOccurrences(
                of: "gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);",
                with: "gl_Position = vec4(a_Position, 1.0);")
        }
        if renamed {
            source = source.replacingOccurrences(of: "v_TexCoord", with: "v_FrozenUV")
                .replacingOccurrences(of: "sourceColor", with: "capturedSample")
                .replacingOccurrences(of: "v_FrozenUV.x * 64.0",
                    with: "(v_FrozenUV.x * 16.0) * 4.0")
        }
        let path = renamed ? "renamed/background.\(stage.kind.rawValue)" : stage.relativePath
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
        return .init(kind: stage.kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
            annotations: parsed.annotations, declarations: parsed.declarations)
    }
    let sourceGraph = SceneShaderSourceGraph(roots: stages.map {
        .init(label: $0.kind.rawValue, virtualPath: $0.relativePath)
    }, nodes: stages.map {
        .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
            rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
    }, edges: [], diagnostics: [], dependencySHA256: SceneShaderStableDigest.hash(stages))
    let shader = SceneShaderContract(identity: renamed ? "renamed/background" : original.identity,
        sourceKind: original.sourceKind, stages: stages, diagnostics: [],
        canonicalSHA256: SceneShaderStableDigest.hash(stages), sourceGraph: sourceGraph)
    var slots = base.textureSlots
    if let provider {
        slots[1] = .init(index: 1, candidates: [.init(
            reference: .provider(.namedLayerTarget(provider)), provenance: .instance)])
    }
    return Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
        renderState: base.renderState, graphRole: base.graphRole, shaderContract: shader,
        diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: shader.identity,
            contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [], uniformSources: []))!
}

private func effectColorMipEligibility() -> [String: Bool] {
    let sourceGraph = graph(targets: [], nodes: [implicitFramebufferMaterial(0, ordinal: 0, target: output)])
    let admitted = admittedGraph(sourceGraph), node = sourceGraph.nodes[0]
    let path = SceneVFSAssetPath("textures/absent-color.tex")!
    let identity = SceneAssetTextureIdentity(path: path, purpose: .straightAlbedo)
    let shader = shaderContract(nodeIndex: 0, pass: false, fragmentOverride: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        uniform sampler2D g_Texture1; // {"material":"albedo","default":"_rt_imageLayerComposite_\(layerID)_a"}
        void main() {
            gl_FragColor = mix(texSample2D(g_Texture0, v_TexCoord), texSample2D(g_Texture1, v_TexCoord), 0.5);
        }
        """)
    let base = implicitFramebufferTemplate(for: node)
    var results: [String: Bool] = [:]
    for usesAbsentCandidate in [false, true] {
        let arm = usesAbsentCandidate ? "asset-with-graph-default" : "only-graph-default"
        var slots = base.textureSlots
        if usesAbsentCandidate {
            slots[1] = .init(index: 1, candidates: [.init(reference: .asset(path), provenance: .instance)])
        }
        let value = Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
            renderState: base.renderState, graphRole: base.graphRole, shaderContract: shader,
            diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: shader.identity,
                contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        let catalog = SceneResolvedMaterialRuntimeCatalog(entries: [.init(effect: node.effect, nodeIndex: 0):
            .template(value, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))],
            resourceDemandIssues: [])
        let caps = capabilities(admitted, catalog: catalog, assetStates: usesAbsentCandidate ? [identity: .absent] : [:])
        guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
              let material = capability.material(for: node) else {
            results[arm] = false
            continue
        }
        let envelope = material.variants.launchEnvelopeCapabilitySnapshot()
        results[arm] = capability.sourceRoute == .capturedLayerTexture
            && capability.supportsPlacementSpaceTerminalReplay && envelope.allEntriesReady
            && !envelope.variants.isEmpty && envelope.variants.allSatisfy { variant in
                guard Set(variant.frontendProgram.textureBindings.map(\.slot)) == [0, 1],
                      case let .reference(source)? = variant.textureSelectionFacts.defaults[1] else { return false }
                return source.reference == .graph(input)
            } && capability.capturesOrdinaryLayerColor() != usesAbsentCandidate
    }
    return results
}

private func chainedEffectColorMipEligibility(device: MTLDevice, queue: MTLCommandQueue) -> [String: [String: Bool]] {
    let chain = terminalChain(2)
    let sourceGraph = Graph(layerID: chain.layerID, effects: chain.effects, renderTargets: [],
        nodes: chain.effects.enumerated().map { index, stage in
            dormantGraphInputMaterial(index, owner: stage.key, target: stage.output)
        }, finalOutput: chain.finalOutput, blockers: [])
    let admitted = orderedLayerGraph(sourceGraph)
    let path = SceneVFSAssetPath("textures/absent-tail-color.tex")!
    let identity = SceneAssetTextureIdentity(path: path, purpose: .straightAlbedo)
    let pipeline = makeSourcePipeline(device)
    let source = makeSource(device, width: 10, height: 10, bgra: [32, 64, 128, 255])
    var results: [String: [String: Bool]] = [:]
    for usesAbsentCandidate in [false, true] {
        let arm = usesAbsentCandidate ? "mixed-tail" : "color-chain"
        let entries = Dictionary(uniqueKeysWithValues: zip(sourceGraph.effects, sourceGraph.nodes).map { stage, node in
            let isTail = stage.key == chain.effects.last?.key
            let shader = shaderContract(nodeIndex: node.nodeIndex, pass: false, fragmentOverride: """
                varying vec2 v_TexCoord;
                uniform sampler2D g_Texture0;
                \(isTail ? "uniform sampler2D g_Texture1; // {\"material\":\"albedo\",\"default\":\"_rt_imageLayerComposite_\(layerID)_a\"}" : "")
                void main() {
                    vec4 color = texSample2D(g_Texture0, v_TexCoord);
                    \(isTail ? "color = mix(color, texSample2D(g_Texture1, v_TexCoord), 0.5);" : "")
                    color.rgb = color.rgb.\(isTail ? "bgr" : "gbr");
                    gl_FragColor = color;
                }
                """)
            var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
            if isTail && usesAbsentCandidate {
                slots[1] = .init(index: 1, candidates: [.init(reference: .asset(path), provenance: .instance)])
            }
            let base = implicitFramebufferTemplate(for: node)
            let value = Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
                renderState: base.renderState, graphRole: .init(effectInput: role(stage.input),
                    effectOutput: role(stage.output), nodeTarget: role(stage.output), bindings: []),
                effectContext: .init(key: stage.key, input: stage.input), shaderContract: shader,
                diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: shader.identity,
                    contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                    textureSources: [], uniformSources: []))!
            return (SceneResolvedMaterialRuntimeCatalog.Key(effect: stage.key, nodeIndex: node.nodeIndex),
                SceneResolvedMaterialRuntimeCatalog.Entry.template(value,
                    textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value)))
        })
        let caps = capabilities(admitted, catalog: .init(entries: entries, resourceDemandIssues: []),
            assetStates: usesAbsentCandidate ? [identity: .absent] : [:])
        guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
              let tail = capability.material(for: sourceGraph.nodes[1]),
              let executor = Executor(device: device, capabilities: caps),
              let leases = makeChainedLeases(capability, device: device),
              let command = queue.makeCommandBuffer() else {
            results[arm] = ["admitted": false]
            continue
        }
        let envelope = tail.variants.launchEnvelopeCapabilitySnapshot()
        var facts = [
            "placement": capability.supportsPlacementSpaceTerminalReplay,
            "tailReadsPriorOutput": envelope.inputIdentity == chain.effects[0].output && envelope.allEntriesReady
                && !envelope.variants.isEmpty && envelope.variants.allSatisfy { variant in
                    guard Set(variant.frontendProgram.textureBindings.map(\.slot)) == [0, 1],
                          case let .reference(source)? = variant.textureSelectionFacts.defaults[1] else { return false }
                    return source.reference == .graph(chain.effects[0].output)
                },
            "eligible": capability.capturesOrdinaryLayerColor() != usesAbsentCandidate,
        ]
        let textureEntries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] =
            usesAbsentCandidate ? [.asset(identity): .absent] : [:]
        let preparation = executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: frame(1, textureEntries: textureEntries),
            sourceTexture: source, sourceUniforms: .neutral(), sourcePipeline: pipeline,
            frameInputs: .init(), commandBuffer: command, previousStates: [:], previousGraphResources: [:],
            effectGeneration: 1, resetGeneration: 1)
        facts["bothStagesRendered"] = false
        if case let .success(prepared) = preparation, prepared.stages.count == 2,
           prepared.stages.allSatisfy({ $0.effectLocalFailureReasonCode == nil
               && $0.effectLocalActivationBypassReasonCode == nil }),
           executor.encode(prepared, commandBuffer: command),
           let readback = appendReadback(prepared.finalTexture, commandBuffer: command) {
            command.commit(); command.waitUntilCompleted()
            facts["bothStagesRendered"] = command.status == .completed && command.error == nil
                && matches(readback.firstPixel, [64, 32, 128, 255])
        }
        results[arm] = facts
    }
    return results
}

private func multipassEffectColorMipEligibility(device: MTLDevice, queue: MTLCommandQueue) -> [String: [String: Bool]] {
    let scratch = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID, effect: effect, name: "local-color")
    let pipeline = makeSourcePipeline(device)
    let source = makeSource(device, width: 10, height: 10, bgra: [32, 64, 128, 255])
    var results: [String: [String: Bool]] = [:]
    for arm in ["local-color", "overwritten-color", "resolution-only"] {
        let overwritesColor = arm == "overwritten-color"
        var nodes = [material(0, ordinal: 0, target: scratch, read: input)]
        if overwritesColor {
            nodes.append(material(1, ordinal: 1, target: scratch, read: input))
        }
        nodes.append(material(nodes.count, ordinal: nodes.count, target: output, read: scratch))
        let admitted = admittedGraph(graph(targets: [rawTarget(scratch, width: 8, height: 4)], nodes: nodes))
        let entries = Dictionary(uniqueKeysWithValues: nodes.map { node in
            let base = template(for: node)
            let fragment = if overwritesColor && node.nodeIndex == 1 {
                """
                    void main() { gl_FragColor = vec4(16.0 / 255.0, 96.0 / 255.0, 224.0 / 255.0, 1.0); }
                    """
            } else if arm == "resolution-only" && node.target == output {
                """
                    uniform sampler2D g_Texture0;
                    uniform vec4 g_Texture0Resolution;
                    void main() { gl_FragColor = vec4(g_Texture0Resolution.xy * 0.05, 0.25, 1.0); }
                    """
            } else {
                fragmentSource(pass: false, pixelTransform: 1)
            }
            let shader = shaderContract(nodeIndex: node.nodeIndex, pass: false, fragmentOverride: fragment)
            let value = Template.validated(textureSlots: base.textureSlots, combos: [], uniformDeclarations: [],
                renderState: base.renderState, graphRole: base.graphRole, shaderContract: shader,
                diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: shader.identity,
                    contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                    textureSources: [], uniformSources: []))!
            return (SceneResolvedMaterialRuntimeCatalog.Key(effect: node.effect, nodeIndex: node.nodeIndex),
                SceneResolvedMaterialRuntimeCatalog.Entry.template(value,
                    textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value)))
        })
        let caps = capabilities(admitted, catalog: .init(entries: entries, resourceDemandIssues: []))
        guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
              let executor = Executor(device: device, capabilities: caps),
              let leases = makeChainedLeases(capability, device: device),
              let command = queue.makeCommandBuffer() else {
            results[arm] = ["admitted": false]
            continue
        }
        var facts = ["eligible": capability.capturesOrdinaryLayerColor(), "rendered": false]
        let preparation = executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: frame(1), sourceTexture: source,
            sourceUniforms: .neutral(), sourcePipeline: pipeline, frameInputs: .init(),
            commandBuffer: command, previousStates: [:], previousGraphResources: [:],
            effectGeneration: 1, resetGeneration: 1)
        if case let .success(prepared) = preparation,
           intentKinds(prepared) == Array(repeating: "material", count: nodes.count),
           executor.encode(prepared, commandBuffer: command),
           let readback = appendReadback(prepared.finalTexture, commandBuffer: command) {
            command.commit(); command.waitUntilCompleted()
            let expected: [UInt8] = switch arm {
            case "overwritten-color": [16, 224, 96, 255]
            case "resolution-only": [64, 51, 102, 255]
            default: [64, 128, 32, 255]
            }
            facts["rendered"] = command.status == .completed && command.error == nil
                && matches(readback.firstPixel, expected)
        }
        results[arm] = facts
    }
    return results
}

private func independentDataEffectColorMipEligibility(
    device: MTLDevice, queue: MTLCommandQueue
) -> [String: [String: Bool]] {
    let scratch = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID, effect: effect, name: "local-color")
    let pipeline = makeSourcePipeline(device)
    let source = makeSource(device, width: extent.width, height: extent.height, bgra: [32, 64, 128, 255])
    var results: [String: [String: Bool]] = [:]
    for arm in ["independent", "renamed", "reads-color", "reads-derived", "data-only-output"] {
        let data = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID, effect: effect,
            name: arm == "renamed" ? "aux-field" : "local-data")
        let readsDerived = arm == "reads-derived"
        let readsColor = arm == "reads-color" || readsDerived
        let dataOnlyOutput = arm == "data-only-output"
        let nodes = [
            material(0, ordinal: 0, target: scratch, read: input),
            material(1, ordinal: 1, target: data, read: scratch),
            material(2, ordinal: 2, target: output, read: readsColor ? input : scratch,
                additionalBindings: [binding(data, slot: 1)]),
        ]
        let layerGraph = graph(targets: [rawTarget(scratch), rawTarget(data, format: "rg88")], nodes: nodes)
        let admitted = admittedGraph(layerGraph)
        let entries = Dictionary(uniqueKeysWithValues: nodes.map { node in
            let base = template(for: node)
            let fragment = switch node.nodeIndex {
            case 0 where readsDerived:
                """
                uniform sampler2D g_Texture0;
                uniform vec4 g_Texture0Resolution;
                void main() { gl_FragColor = vec4(g_Texture0Resolution.xy * 0.05, 0.25, 1.0); }
                """
            case 0 where readsColor:
                """
                varying vec2 v_TexCoord;
                uniform sampler2D g_Texture0;
                void main() {
                    vec4 sampled = texSample2D(g_Texture0, v_TexCoord);
                    gl_FragColor = vec4(sampled.rgb, 1.0);
                }
                """
            case 0:
                """
                varying vec2 v_TexCoord;
                uniform sampler2D g_Texture0;
                void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
                """
            case 1:
                """
                varying vec2 v_TexCoord;
                uniform sampler2D g_Texture0;
                void main() {
                    vec2 signal = \(readsColor ? "texSample2D(g_Texture0, v_TexCoord).rg" :
                                       arm == "renamed" ? "vec2(0.125 + 0.125, 0.5)" : "vec2(0.25, 0.5)");
                    gl_FragColor = vec4(signal, 0.0, 1.0);
                }
                """
            default:
                """
                varying vec2 v_TexCoord;
                uniform sampler2D g_Texture0;
                uniform sampler2D g_Texture1;
                void main() {
                    vec2 field = texSample2D(g_Texture1, v_TexCoord).rg;
                    float color = \(dataOnlyOutput ? "0.75" : "texSample2D(g_Texture0, v_TexCoord).r");
                    gl_FragColor = vec4(color, field, 1.0);
                }
                """
            }
            let shader = shaderContract(nodeIndex: node.nodeIndex, pass: false, fragmentOverride: fragment)
            let value = Template.validated(textureSlots: base.textureSlots, combos: [], uniformDeclarations: [],
                renderState: base.renderState, graphRole: base.graphRole, shaderContract: shader,
                diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: shader.identity,
                    contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                    textureSources: [], uniformSources: []))!
            return (SceneResolvedMaterialRuntimeCatalog.Key(effect: node.effect, nodeIndex: node.nodeIndex),
                SceneResolvedMaterialRuntimeCatalog.Entry.template(value,
                    textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value)))
        })
        let caps = capabilities(admitted, catalog: .init(entries: entries, resourceDemandIssues: []))
        guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
              let executor = Executor(device: device, capabilities: caps),
              let command = queue.makeCommandBuffer() else {
            results[arm] = ["admitted": false]
            continue
        }
        let lease = makeLease(requirePlan(layerGraph), device: device)
        var facts = ["eligible": capability.capturesOrdinaryLayerColor(), "rendered": false]
        let preparation = executor.prepare(token: claim.token, leases: [lease],
            historyRehydrateCopiesByEffect: [:], frame: frame(1), sourceTexture: source,
            sourceUniforms: .neutral(), sourcePipeline: pipeline, frameInputs: .init(),
            commandBuffer: command, previousStates: [:], previousGraphResources: [:],
            effectGeneration: 1, resetGeneration: 1)
        if case let .success(prepared) = preparation,
           let target = lease.texture(for: data), executor.encode(prepared, commandBuffer: command),
           let dataReadback = appendRedGreenReadback(target, commandBuffer: command),
           let readback = appendReadback(prepared.finalTexture, commandBuffer: command) {
            command.commit(); command.waitUntilCompleted()
            let expectedData: [UInt8] = switch arm {
            case "reads-derived": [128, 128]
            case "reads-color": [128, 64]
            default: [64, 128]
            }
            let expected: [UInt8] = [expectedData[1], expectedData[0], dataOnlyOutput ? 191 : 128, 255]
            facts["rendered"] = command.status == .completed && command.error == nil
                && matches(readback.firstPixel, expected)
                && zip(dataReadback.first, expectedData).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
            if facts["rendered"] != true {
                FileHandle.standardError.write(Data(
                    "Independent data fixture \(arm): status=\(command.status), data=\(dataReadback.first), output=\(readback.firstPixel)\n".utf8
                ))
            }
        } else {
            FileHandle.standardError.write(Data(
                "Independent data fixture \(arm): prepare=\(failureCode(preparation))\n".utf8
            ))
        }
        results[arm] = facts
    }
    return results
}

private func densityCase(
    device: MTLDevice, queue: MTLCommandQueue, renamed: Bool,
    blendMode: Int = 0, colorKind: String? = nil
) throws -> [String: Any] {
    // The same maintained bare-Swift bounded frontend as overflowCase; the
    // production finalizer and Metal pass encoder still produce every Program.
    let prior = getenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES").map { String(cString: $0) }
    setenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", "ordinary-shader=disable-generic", 1)
    defer {
        if let prior { setenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", prior, 1) }
        else { unsetenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES") }
    }
    let densityGraph = terminalChain(1)
    let admitted = orderedLayerGraph(densityGraph), node = densityGraph.nodes[0]
    let reference = SceneNamedTextureReference(providerLayerID: 879, variant: .primary)
    let dependency = SceneDependencyRenderPlan.Binding(consumerLayerID: layerID, providerLayerID: 879,
        slot: .init(effectID: node.effect.descriptorID, passIndex: 0, slotIndex: 1),
        blendMode: 0, kind: .resolvedMaterial)
    func densityCatalog(_ legacy: Bool = false, controls: Bool = true) -> SceneResolvedMaterialRuntimeCatalog {
        let value = densityTemplate(node, renamed: renamed, legacyVertex: legacy,
                colorKind: controls ? colorKind : nil,
                provider: controls && colorKind == "straight" ? reference : nil)
        return .init(entries: [.init(effect: node.effect, nodeIndex: node.nodeIndex):
            .template(value, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))],
            resourceDemandIssues: [])
    }
    let caps = capabilities(admitted, catalog: densityCatalog(),
        namedProvider: colorKind == "straight" ? reference : nil,
        dependencyBinding: colorKind == "straight" ? dependency : nil,
        terminalReplayBlendMode: blendMode)
    guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
          let executor = Executor(device: device, capabilities: caps),
          let leases = makeChainedLeases(capability, device: device) else {
        return ["failure": "density-setup", "reports": caps.reportLines]
    }
    func sizing(
        sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute = .capturedLayerTexture,
        dependency: SceneResolvedMaterialDependencyOwnership = .none,
        provider: Bool = false
    ) -> Bool {
        let candidate = SceneResolvedMaterialAdmittedLayer(layerID: capability.layerID,
            products: capability.admittedProducts, pairPlan: capability.pairPlan,
            dependencyOwnership: dependency, sourceRoute: sourceRoute,
            isVisibleExecutionRoot: capability.isVisibleExecutionRoot,
            isGraphOutputProvider: provider,
            terminalReplayBlendMode: capability.terminalReplayBlendMode)
        let result = Capabilities.LayerCapability.simpleColorChainCapabilities(admitted: candidate,
            stages: capability.stages, materials: capability.materials,
            dependencyOwnership: dependency, sceneBackgroundRequirement: capability.sceneBackgroundRequirement)
        return result.intermediates || result.terminal
    }
    let complexGraph = graph(targets: [rawTarget(first)], nodes: [
        material(0, ordinal: 0, target: first, read: input),
        material(1, ordinal: 1, target: output, read: first)])
    let complexAdmitted = admittedGraph(complexGraph)
    let complexCaps = capabilities(complexAdmitted, catalog: catalog(for: complexGraph))
    let complexCapability = complexCaps.claim(complexAdmitted).flatMap { complexCaps.resolve($0.token) }
    let legacyCaps = capabilities(admitted, catalog: densityCatalog(true, controls: false))
    let legacyCapability = legacyCaps.claim(admitted).flatMap { legacyCaps.resolve($0.token) }
    let mainCaps = capabilities(admitted, catalog: densityCatalog(controls: false), capturedMainTarget: true)
    let mainCapability = mainCaps.claim(admitted).flatMap { mainCaps.resolve($0.token) }
    let pixels: [UInt8] = (0..<100).flatMap { index -> [UInt8] in
        let x = index % 10, y = index / 10
        if colorKind != nil { return [26, 51, 102, 128] }
        return [UInt8(32 + (x >= 5 ? 32 : 0) + (y >= 5 ? 64 : 0)),
            UInt8(48 + (x >= 5 ? 64 : 0) + (y >= 5 ? 96 : 0)), 255, 255]
    }
    let source = makeSource(device, width: 10, height: 10, pixelsBGRA: pixels)
    let provider = makeSource(device, width: 10, height: 10,
        usage: [.shaderRead, .renderTarget], bgra: [51, 102, 204, 128])
    let providerResource = SceneFrameTextureResource.reservedNamedLayerTarget(reference: reference,
        frameEpoch: 1, texture: provider, content: .color(.resolved(.straightAlpha)))!
    let dependencies: [SceneDependencyEffectInput] = colorKind == "straight" ? [.init(
        consumerLayerID: layerID, providerLayerID: reference.providerLayerID, slot: dependency.slot,
        frameEpoch: 1, texture: provider, content: .color(.resolved(.straightAlpha)),
        namedReference: reference, reservedMaterialResource: providerResource)] : []
    let replayTarget = makeSource(device, width: 256, height: 64, usage: [.renderTarget])
    let graphTarget = makeSource(device, width: 256, height: 64, usage: [.renderTarget])
    let pipeline = makeSourcePipeline(device), command = queue.makeCommandBuffer()!
    let wrongMode = executor.prepare(token: claim.token, leases: leases,
        historyRehydrateCopiesByEffect: [:], frame: frame(1), sourceTexture: source,
        sourceUniforms: .neutral(), sourcePipeline: pipeline, terminalReplayTarget: replayTarget,
        terminalReplayBlendMode: blendMode == 31 ? 0 : 31,
        frameInputs: .init(dependencyEffects: dependencies), commandBuffer: queue.makeCommandBuffer()!,
        previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1)
    let wrongModeRejected: Bool
    if case .failure(.invalidClaim) = wrongMode { wrongModeRejected = true }
    else { wrongModeRejected = false }
    let prepared = try executor.prepare(token: claim.token, leases: leases,
        historyRehydrateCopiesByEffect: [:], frame: frame(1), sourceTexture: source,
        sourceUniforms: .neutral(), sourcePipeline: pipeline, terminalReplayTarget: replayTarget,
        terminalReplayBlendMode: blendMode, frameInputs: .init(dependencyEffects: dependencies),
        commandBuffer: command, previousStates: [:], previousGraphResources: [:],
        effectGeneration: 1, resetGeneration: 1).get()
    let graphEncoded = executor.encode(prepared, commandBuffer: command)
    let controlledColor = blendMode == 31 || colorKind != nil
    let background: [UInt8] = controlledColor ? [32, 24, 16, 96] : [255, 0, 0, 255]
    let clear = MTLClearColor(red: Double(background[2]) / 255,
        green: Double(background[1]) / 255, blue: Double(background[0]) / 255,
        alpha: Double(background[3]) / 255)
    let graphMain = SceneMainPassEncoder(commandBuffer: command, target: graphTarget,
        clearColor: clear, clearEnabled: true)
    let graphDraw = graphMain.encodePreparedDraw { _, _ in
        { encoder in
            pipeline.bind(encoder: encoder)
            pipeline.drawLayer(texture: prepared.finalTexture, mvp: matrix_identity_float4x4,
                uniforms: .neutral(), encoder: encoder)
        }
    }
    let graphFinished = graphMain.finishEnsuringClear()
    let replayMain = SceneMainPassEncoder(commandBuffer: command, target: replayTarget,
        clearColor: clear, clearEnabled: true)
    let replayDraw = executor.encodeTerminalReplay(prepared, mainPass: replayMain, commandBuffer: command)
    let replayFinished = replayMain.finishEnsuringClear()
    guard let graphRead = appendReadback(graphTarget, commandBuffer: command),
          let replayRead = appendReadback(replayTarget, commandBuffer: command),
          let sourceRead = appendReadback(source, commandBuffer: command) else {
        return ["failure": "density-readback"]
    }
    command.commit(); command.waitUntilCompleted()
    func transitions(_ read: Readback) -> Int {
        let row = (64..<192).map { read.pixel(x: $0, y: 32)[2] > 127 }
        return zip(row, row.dropFirst()).filter { $0 != $1 }.count
    }
    let probes = [(80, 20), (176, 20), (80, 44), (176, 44)]
    let graphProbes = probes.map { graphRead.pixel(x: $0.0, y: $0.1) }
    let replayProbes = probes.map { replayRead.pixel(x: $0.0, y: $0.1) }
    let frozenBackground = zip(graphProbes, replayProbes).allSatisfy { old, new in
        abs(Int(old[0]) + (blendMode == 31 ? Int(background[0]) : 0) - Int(new[0])) <= 1
            && Int(old[1]) + (blendMode == 31 ? Int(background[1]) : 0) == Int(new[1])
            && new[3] == (blendMode == 31 ? background[3] : old[3])
    }
    let expectedRepresentation: SceneShaderColorRepresentation? = switch colorKind {
    case "pma": .premultipliedAlpha
    case "straight": .straightAlpha
    case "opaque": .opaque
    default: nil
    }
    // Independent byte arithmetic for these fixed colors, not a blend helper:
    // background RGBA16/24/32/96 + PMA102/51/26 or straight204/102/51 at128/255.
    let expected: [UInt8] = blendMode == 31 ? [58, 75, 118, 96]
        : colorKind == "opaque" ? [26, 51, 102, 255] : [42, 63, 110, 176]
    let replay = prepared.terminalMaterialReplay
    let sampledInputMatches: Bool
    if colorKind == "opaque" || colorKind == "pma" {
        sampledInputMatches = replay?.sampledTextures.isEmpty == true
    } else {
        sampledInputMatches = replay?.sampledTextures.first
            === (colorKind == "straight" ? provider : leases[0].table.inputTexture)
    }
    let straightOutput = replay?.fragmentOutput == .straightAlpha
    let expectedRole: SceneResolvedMaterialProgram.PassRole = blendMode == 31
            ? (straightOutput ? .terminalStraightAdditive : .terminalAdditive)
            : (straightOutput ? .terminalStraightSourceOver : .terminalSourceOver)
    let roleMatches = replay?.role.terminalReplayBlendMode == blendMode && replay?.role == expectedRole
    return ["graphTransitions": transitions(graphRead), "terminalTransitions": transitions(replayRead),
        "capabilityReports": caps.reportLines,
        "graphProbes": graphProbes, "terminalProbes": replayProbes,
        "centerPixel": replayRead.pixel(x: 96, y: 32), "expectedColor": expected,
        "actualRole": replay?.role.rawValue ?? "missing", "blendMode": blendMode,
        "readbackExtent": [replayRead.width, replayRead.height], "readbackBytesPerRow": replayRead.bytesPerRow,
        "results": ["capturedLayerRoute": capability.sourceRoute == .capturedLayerTexture,
            "layerSourceSizingAndTerminal": capability.supportsTerminalMaterialReplay
                && capability.supportsSourceSizedSolidEffects,
            "admittedAndEncodedModeMatch": capability.terminalReplayBlendMode == blendMode && roleMatches,
            "wrongModeRejected": wrongModeRejected,
            "actualRepresentation": expectedRepresentation.map {
                prepared.finalResource.publication.candidate.content == .color(.resolved($0))
                    && replay?.fragmentOutput == $0
            } ?? true,
            "colorArithmeticAndAlpha": colorKind == nil
                || matches(replayRead.pixel(x: 96, y: 32), expected),
            "capturedMainRemainsGraphOnly": mainCapability?.sourceRoute == .capturedMainTargetTexture
                && mainCapability?.supportsTerminalMaterialReplay == false
                && mainCapability?.supportsSourceSizedSolidEffects == false,
            "capturedMainDependencyRejected": !sizing(sourceRoute: .capturedMainTargetTexture,
                dependency: .externalPrimary(dependency)),
            "providerRejected": !sizing(provider: true),
            "complexGraphNotASetupFailure": complexCapability != nil,
            "complexGraphRejected": complexCapability?.supportsTerminalMaterialReplay == false
                && complexCapability?.supportsSourceSizedSolidEffects == false,
            "legacyVertexNotASetupFailure": legacyCapability != nil,
            "legacyVertexRejected": legacyCapability?.supportsTerminalMaterialReplay == false
                && legacyCapability?.supportsSourceSizedSolidEffects == false,
            "allDrawsEncoded": graphEncoded && graphDraw && graphFinished && replayDraw && replayFinished,
            "gpuCompleted": command.status == .completed && command.error == nil,
            "sourcePixelsUnchanged": sourceRead.allPixels == (0..<10).map {
                Array(pixels[($0 * 40)..<(($0 + 1) * 40)]) },
            "sourceExtentRetained": prepared.stages.allSatisfy {
                $0.inputWidth == 10 && $0.inputHeight == 10
            } && prepared.finalTexture.width == 10 && prepared.finalTexture.height == 10,
            "sameFrozenSampledInput": sampledInputMatches,
            "validReadbackStride": replayRead.bytesPerRow >= replayRead.width * 4
                && replayRead.bytesPerRow % 256 == 0 && graphRead.bytesPerRow == replayRead.bytesPerRow,
            "backgroundUVAndResolutionRetained": colorKind != nil || (frozenBackground
                && Set(replayProbes.map { $0[1] }).count == 4),
            "terminalDensityRestored": colorKind != nil || (transitions(replayRead) >= 120
                && (1...20).contains(transitions(graphRead))),
            "outsideBackgroundPreserved": matches(replayRead.pixel(x: 10, y: 32), background)]]
}
