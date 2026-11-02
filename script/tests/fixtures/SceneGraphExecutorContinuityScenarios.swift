private func runSelfMixedCurrentScenario(device: MTLDevice, queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline, status: SystemProviderFixtureStatus) -> [String: Bool] {
    let full = chainedGraph()
    let graph = Graph(layerID: layerID, effects: Array(full.effects.prefix(2)), renderTargets: [],
        nodes: Array(full.nodes.prefix(2)), finalOutput: chainedSecondOutput, blockers: [])
    let selfReference = SceneNamedTextureReference(providerLayerID: layerID, variant: .primary)
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
    for node in graph.nodes {
        let effect = graph.effects.first { $0.key == node.effect }!
        let original = node.nodeIndex == 0 ? template(for: node) : template(for: node,
            userPropertyProvider: "selfOverride", systemProviderLowerReference: .provider(.namedLayerTarget(selfReference)),
            explicitPreviousSampler: true)
        let value = Template.validated(textureSlots: original.textureSlots, combos: original.combos,
            uniformDeclarations: original.uniformDeclarations, renderState: original.renderState,
            graphRole: original.graphRole, effectContext: .init(key: effect.key, input: effect.input),
            shaderContract: original.shaderContract, diagnosticProvenance: original.diagnosticProvenance)!
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(value, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))
    }
    let owner = SceneDependencyRenderPlan.Reference(consumerLayerID: layerID, providerLayerID: layerID,
        slot: .init(effectID: chainedSecondEffect.descriptorID, passIndex: 0, slotIndex: 1), variant: .primary)
    let chain = orderedLayerGraph(graph)
    let capabilities = capabilities(chain, catalog: .init(entries: entries, resourceDemandIssues: []),
        secondarySelfUnavailableReference: owner)
    var result = ["prepared": false, "program": false, "gpuCompleted": false, "pixels": false,
        "selectedFact": false, "selectedVariantPurpose": false, "sourceAtom": false,
        "visiblePixelsUnchanged": false]
    guard let claim = capabilities.claim(chain), let capability = capabilities.resolve(claim.token, for: chain),
          let leases = makeChainedLeases(capability, device: device),
          let executor = Executor(device: device, capabilities: capabilities), let command = queue.makeCommandBuffer()
    else { return result }
    let userIdentity = SceneFrameTextureIdentity.materialUserProperty(SceneUserPropertyTextureIdentity(
        propertyKey: "selfOverride", purpose: .preservedChannels)!)
    let lookup: SceneFrameTextureLookupStatus
    if status == .ready {
        let candidate = SceneTextureCandidate(texture: makeSource(device, bgra: [0, 0, 255, 255]),
            identity: .provider(.mediaThumbnailCurrent), generation: .provider(contentGeneration: 1),
            purpose: .preservedChannels, content: .data, physicalSize: CGSize(width: 1, height: 1),
            mappedSize: CGSize(width: 1, height: 1), uvTransform: .identity, sampling: .linearClamp)
        lookup = .ready(.init(publication: .init(requestIdentity: userIdentity, candidate: candidate,
            contentGeneration: 1), resourceGeneration: 1))
    } else { lookup = systemProviderStatus(status, device: device, generation: 1) }
    let preparation = executor.prepare(token: claim.token, leases: leases,
        historyRehydrateCopiesByEffect: [:], frame: frame(1, textureEntries: [userIdentity: lookup]),
        sourceTexture: makeSource(device, bgra: [255, 0, 0, 255]), sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline, frameInputs: .init(), commandBuffer: command,
        previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1)
    guard case let .success(prepared) = preparation else {
        FileHandle.standardError.write(Data("self-mixed-\(status):\(failureCode(preparation))\n".utf8)); return result
    }
    result["prepared"] = true
    result["program"] = prepared.stages[1].effectLocalFailureReasonCode == nil
        && prepared.stages[1].programCacheKeys.count == 1
    if let material = capability.material(for: graph.nodes[1]),
       let overlaid = frame(1, textureEntries: [userIdentity: lookup]).overlayingGraphResources([
           chainedFirstOutput: prepared.stages[0].effectOutputResource
       ]), case let .success(program) = SceneResolvedMaterialProgramFinalizer.finalize(
           overlaid.finalizationInput(layerID: layerID,
               renderSize: CGSize(width: extent.width, height: extent.height),
               modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
               effectOutputModelViewProjection: matrix_identity_float4x4,
               effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
               implicitFramebufferIdentity: chainedFirstOutput), variantCache: material.variants
       ), let slot = program.textureSlots[1] {
        let ready = status == .ready
        result["selectedFact"] = ready ? slot.graphInputSourceFact == nil
            : slot.graphInputSourceFact?.inputIdentity == chainedFirstOutput
                && slot.graphInputSourceFact?.selectionProvenance == slot.diagnosticSelectionProvenance
                && program.semanticIdentity.graphRole.bindings.contains(.init(slot: 1, texture: .effectOutput))
        result["selectedVariantPurpose"] = slot.expectedPurpose == (ready ? .preservedChannels : .straightAlbedo)
        result["sourceAtom"] = ready ? slot.registryIdentity == userIdentity
            : slot.resource.publication.isSameAtom(as: prepared.stages[0].effectOutputResource.publication)
                && slot.resource.resourceGeneration == prepared.stages[0].effectOutputResource.resourceGeneration
    }
    guard executor.encode(prepared, commandBuffer: command),
          let read = appendReadback(prepared.finalTexture, commandBuffer: command) else { return result }
    let visible = makeSource(device, width: extent.width, height: extent.height,
        usage: [.renderTarget, .shaderRead], bgra: [0, 0, 0, 0])
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = visible
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = .init(red: 0, green: 0, blue: 0, alpha: 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass),
          let compositor = makeProductionSourcePipeline(device) else { return result }
    compositor.bind(encoder: encoder)
    var uniforms = SceneLayerFragmentUniforms.neutral()
    uniforms.sourceSampling.y = prepared.finalResource.publication.candidate.content
        == .color(.resolved(.straightAlpha)) ? 1 : 0
    compositor.drawLayer(texture: prepared.finalTexture,
        mvp: simd_float4x4(diagonal: SIMD4(2, 2, 1, 1)), uniforms: uniforms, encoder: encoder)
    encoder.endEncoding()
    guard let visibleRead = appendReadback(visible, commandBuffer: command) else { return result }
    command.commit(); command.waitUntilCompleted()
    result["gpuCompleted"] = command.status == .completed && command.error == nil
    let expected: [UInt8] = status == .ready ? [0, 128, 128, 128] : [0, 255, 0, 128]
    result["pixels"] = matches(read.firstPixel, expected) && matches(read.lastPixel, expected)
    let expectedVisible: [UInt8] = status == .ready ? [0, 64, 64, 128] : [0, 128, 0, 128]
    result["visiblePixelsUnchanged"] = matches(visibleRead.firstPixel, expectedVisible)
        && matches(visibleRead.lastPixel, expectedVisible)
    return result
}

private func runSelfCompositeCurrentScenario(
    device: MTLDevice, queue: MTLCommandQueue, sourcePipeline: SceneImageLayerPipeline,
    stageCount: Int, variant: SceneNamedTextureReference.Variant, usesDefault: Bool
) -> [String: Bool] {
    let selfReference = SceneNamedTextureReference(providerLayerID: layerID, variant: variant)
    let token = "_rt_imageLayerComposite_\(layerID)_\(variant == .primary ? "a" : "b")"
    let colors = ["0.0, 1.0, 0.0", "1.0, 0.0, 0.0", "1.0, 1.0, 0.0"]
    let expected: [[UInt8]] = [[0, 255, 0, 255], [0, 0, 255, 255], [0, 255, 255, 255]]
    var effects: [Graph.Effect] = [], nodes: [Graph.Node] = []
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
    var current = input
    for index in 0 ..< stageCount {
        let key = Graph.EffectKey(layerID: layerID, effectIndex: index, descriptorID: "self-current-\(index)")
        let output = Graph.TextureIdentity(kind: .effectOutput, layerID: layerID, effect: key, name: nil)
        let probe = index == stageCount - 1
        let original = material(index, ordinal: 0, target: output, read: current, owner: key)
        let node = Graph.Node(nodeIndex: index, effect: key, definitionPassIndex: 0,
            materialOrdinal: 0, instancePassIndex: 0, kind: .material,
            materialPath: original.materialPath, materialPassID: original.materialPassID,
            target: output, bindings: probe ? [] : original.bindings,
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil)
        let shader = shaderContract(nodeIndex: index, pass: false,
            renderTargetDefault: probe && usesDefault ? token : nil,
            pixelTransform: 0, scalarConsumer: "whole",
            constantColor: probe ? nil : colors[index])
        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        if !probe || !usesDefault {
            slots[0] = .init(index: 0, candidates: [.init(
                reference: probe ? .provider(.namedLayerTarget(selfReference)) : .graph(current),
                provenance: probe ? .instance : .explicitBinding)])
        }
        let value = Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
            renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
            graphRole: .init(effectInput: index == 0 ? .layerSource : .effectOutput,
                effectOutput: .effectOutput, nodeTarget: .effectOutput,
                bindings: probe ? [] : [.init(slot: 0, texture: index == 0 ? .layerSource : .effectOutput)]),
            effectContext: .init(key: key, input: current), shaderContract: shader,
            diagnosticProvenance: .init(nodeIndex: index, authoredShaderPath: shader.identity,
                contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        entries[.init(effect: key, nodeIndex: index)] = .template(value, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))
        effects.append(.init(key: key, definitionPath: "effects/self-current-\(index).json",
            input: current, output: output, nodeIndices: [index]))
        nodes.append(node)
        current = output
    }
    let graph = Graph(layerID: layerID, effects: effects, renderTargets: [], nodes: nodes,
        finalOutput: current, blockers: [])
    let chain = orderedLayerGraph(graph)
    let ownership = SceneDependencyRenderPlan.Reference(consumerLayerID: layerID, providerLayerID: layerID,
        slot: .init(effectID: effects.last!.key.descriptorID, passIndex: 0, slotIndex: 0), variant: variant)
    let capabilities = capabilities(chain, catalog: .init(entries: entries, resourceDemandIssues: []),
        secondarySelfUnavailableReference: usesDefault ? nil : ownership)
    var result = ["prepared": false, "gpuCompleted": false, "latestOutput": false,
        "onePair": false, "noResourceCopy": false, "currentPublication": false, "secondFrame": false]
    guard let claim = capabilities.claim(chain), let capability = capabilities.resolve(claim.token, for: chain),
          let leases = makeChainedLeases(capability, device: device),
          let executor = Executor(device: device, capabilities: capabilities) else { return result }
    result["onePair"] = Set(leases.flatMap { $0.texturesByToken.values.map(ObjectIdentifier.init) }).count == 2
    var previousStates: [Graph.EffectKey: Executor.State] = [:]
    var previousResources: [Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]] = [:]
    for frameIndex in 1 ... 2 {
        guard let command = queue.makeCommandBuffer() else { return result }
        let preparation = executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: frame(UInt64(frameIndex)),
            sourceTexture: makeSource(device, bgra: [255, 0, 0, 255]), sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline, frameInputs: .init(), commandBuffer: command,
            previousStates: previousStates, previousGraphResources: previousResources,
            effectGeneration: 1, resetGeneration: 1)
        guard case let .success(prepared) = preparation else {
            FileHandle.standardError.write(Data("self-current-\(stageCount)-\(token)-default\(usesDefault):\(failureCode(preparation))\n".utf8))
            return result
        }
        result["prepared"] = prepared.stages.count == stageCount
        result["noResourceCopy"] = prepared.stages.allSatisfy { $0.historyRehydrateCopyCount == 0
            && $0.transition.transaction.intents.allSatisfy { if case .copy = $0 { return false }; return true } }
        let final = prepared.stages.last!, prior = prepared.stages[stageCount - 2]
        if let material = capability.material(for: nodes.last!),
           let overlaid = frame(UInt64(frameIndex)).overlayingGraphResources([
               effects.last!.input: prior.effectOutputResource
           ]), case let .success(program) = SceneResolvedMaterialProgramFinalizer.finalize(
               overlaid.finalizationInput(layerID: layerID,
                   renderSize: CGSize(width: extent.width, height: extent.height),
                   modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
                   effectOutputModelViewProjection: matrix_identity_float4x4,
                   effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                   implicitFramebufferIdentity: effects.last!.input), variantCache: material.variants
           ), let slot = program.textureSlots[0] {
            result["currentPublication"] = slot.reference == .graph(effects.last!.input)
                && slot.resource.publication.isSameAtom(as: prior.effectOutputResource.publication)
                && slot.resource.resourceGeneration == prior.effectOutputResource.resourceGeneration
                && final.pairStep.inputMember != final.pairStep.outputMember
        }
        guard executor.encode(prepared, commandBuffer: command),
              let read = appendReadback(prepared.finalTexture, commandBuffer: command) else { return result }
        command.commit(); command.waitUntilCompleted()
        result["gpuCompleted"] = command.status == .completed && command.error == nil
        result["latestOutput"] = matches(read.firstPixel, expected[stageCount - 2])
            && matches(read.lastPixel, expected[stageCount - 2])
        if !result["gpuCompleted"]! || !result["latestOutput"]! { return result }
        previousStates = Dictionary(uniqueKeysWithValues: prepared.stages.map { ($0.effect, $0.transition.nextState) })
        previousResources = Dictionary(uniqueKeysWithValues: prepared.stages.map { ($0.effect, $0.persistentResources) })
        if frameIndex == 2 { result["secondFrame"] = true }
    }
    return result
}

private func runStraightColorContinuityScenario(
    device: MTLDevice, queue: MTLCommandQueue, colorProbe: String? = nil
) -> [String: Any] {
    let full = chainedGraph()
    let graph = Graph(layerID: layerID, effects: Array(full.effects.prefix(2)), renderTargets: [],
        nodes: Array(full.nodes.prefix(2)), finalOutput: chainedSecondOutput, blockers: [])
    let generated = """
    varying vec2 v_TexCoord;
    uniform float g_Time;
    void main() {
        vec3 authoredColor = vec3(0.8, 0.4, 0.2);
        gl_FragColor = vec4(authoredColor, g_Time);
    }
    """
    let replaceCoverage: String
    if let colorProbe {
        let declaration = colorProbe == "rg" ? "vec2 channels" : "float channel"
        let rgb = colorProbe == "rg" ? "channels.r, channels.g, channels.r" : "channel, channel, channel"
        replaceCoverage = """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"material":"previous"}
        void main() {
            \(declaration) = texSample2D(g_Texture0, v_TexCoord).\(colorProbe);
            gl_FragColor = vec4(\(rgb), 1.0);
        }
        """
    } else { replaceCoverage = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0; // {"material":"previous"}
    void main() {
        vec4 color = texSample2D(g_Texture0, v_TexCoord);
        color.a = 0.5;
        gl_FragColor = color;
    }
    """ }
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
    for node in graph.nodes {
        let original = template(for: node)
        let effect = graph.effects.first { $0.key == node.effect }!
        let shader = shaderContract(nodeIndex: node.nodeIndex, pass: false,
            fragmentOverride: node.nodeIndex == 0 ? generated : replaceCoverage)
        let value = Template.validated(textureSlots: original.textureSlots, combos: original.combos,
            uniformDeclarations: [], renderState: original.renderState, graphRole: original.graphRole,
            effectContext: .init(key: effect.key, input: effect.input), shaderContract: shader,
            diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: shader.identity,
                contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(value, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))
    }
    let chain = orderedLayerGraph(graph)
    let capabilities = capabilities(chain, catalog: .init(entries: entries, resourceDemandIssues: []))
    guard let claim = capabilities.claim(chain), let capability = capabilities.resolve(claim.token, for: chain),
          let leases = makeChainedLeases(capability, device: device),
          let consumer = capability.material(for: graph.nodes[1]),
          let executor = Executor(device: device, capabilities: capabilities),
          let sourcePipeline = makeProductionSourcePipeline(device) else {
        return ["failure": "setup", "reports": capabilities.reportLines]
    }
    var rows: [[String: Any]] = [], firstProducerKey: String?, firstConsumerKey: String?
    var firstFrontendCount = 0, firstLibraryCount = 0
    var previousStates: [Graph.EffectKey: Executor.State] = [:]
    var previousResources: [Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]] = [:]
    // The fourth frame deliberately replaces the generated stage with its
    // true PMA base-source fallback; the consumer must update only its mask.
    for (offset, alpha) in [Float(0), 0.5, 1, 0.5].enumerated() {
        let frameIndex = UInt64(offset + 1), fallback = offset == 3
        if fallback, let key = firstProducerKey {
            executor.materialEncoder.installTestingPreparationFailure(
                .libraryCompilationRejected(diagnostic: "owned continuity fallback"), preparedKey: key)
        }
        let snapshot = frame(frameIndex, sceneTime: alpha)
        let command = queue.makeCommandBuffer()!
        let preparation = executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: snapshot,
            sourceTexture: makeSource(device, bgra: [26, 51, 102, 128]),
            sourceUniforms: .neutral(), sourcePipeline: sourcePipeline, frameInputs: .init(),
            commandBuffer: command, previousStates: previousStates,
            previousGraphResources: previousResources, effectGeneration: 1, resetGeneration: 1)
        guard case let .success(prepared) = preparation, prepared.stages.count == 2 else {
            return ["failure": failureCode(preparation), "frames": rows]
        }
        let prior = prepared.stages[0], final = prepared.stages[1]
        guard let overlaid = snapshot.overlayingGraphResources([chainedFirstOutput: prior.effectOutputResource]),
              case let .success(program) = SceneResolvedMaterialProgramFinalizer.finalize(
                overlaid.finalizationInput(layerID: layerID,
                    renderSize: CGSize(width: extent.width, height: extent.height),
                    modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
                    effectOutputModelViewProjection: matrix_identity_float4x4,
                    effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                    implicitFramebufferIdentity: chainedFirstOutput), variantCache: consumer.variants),
              let maskUniform = zip(program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms).first(where: {
                $0.0.field.name == "mwxPremultipliedColorInputMask"
              }), maskUniform.1.encodedValue.count == 4 else {
            return ["failure": "consumer-mask-finalization", "frames": rows]
        }
        let mask = maskUniform.1.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var readbacks: [Readback] = []
        guard executor.encode(prepared, commandBuffer: command, stageBoundaryObserver: { _, stage, buffer in
            guard let read = appendReadback(stage.effectOutputResource.publication.texture,
                commandBuffer: buffer) else { return false }
            readbacks.append(read); return true
        }), readbacks.count == 2 else { return ["failure": "encode", "frames": rows] }
        command.commit(); command.waitUntilCompleted()
        if offset == 0 {
            firstProducerKey = prior.programCacheKeys.first
            firstConsumerKey = final.programCacheKeys.first
            firstFrontendCount = consumer.variants.counters.frontendCompilationCount
            firstLibraryCount = executor.materialEncoder.metalLibraryCompilationAttemptCount
        }
        let expectedPrior: [UInt8] = fallback ? [26, 51, 102, 128]
            : [51, 102, 204, UInt8((alpha * 255).rounded())]
        let expectedFinal: [UInt8] = switch colorProbe {
        case "r": [204, 204, 204, 255]
        case "g": [102, 102, 102, 255]
        case "rg": [204, 102, 204, 255]
        default: [51, 102, 204, 128]
        }
        let expectedOutput: SceneShaderColorRepresentation = colorProbe == nil ? .straightAlpha : .opaque
        rows.append(["alpha": alpha, "fallback": fallback,
            "completed": command.status == .completed && command.error == nil,
            "producerColorRetained": matches(readbacks[0].firstPixel, expectedPrior)
                && matches(readbacks[0].lastPixel, expectedPrior),
            "consumerColorRetained": matches(readbacks[1].firstPixel, expectedFinal)
                && matches(readbacks[1].lastPixel, expectedFinal),
            "actualInputRepresentation": prior.effectOutputResource.publication.candidate.content
                == .color(.resolved(fallback ? .premultipliedAlpha : .straightAlpha)),
            "actualOutputContract": prepared.finalResource.publication.candidate.content
                == .color(.resolved(expectedOutput))
                && prepared.finalResource.publication.candidate.purpose
                    == (colorProbe == nil ? .straightAlbedo : .premultipliedColor),
            "maskMatchesActualInput": mask == (fallback ? 1 : 0),
            "sameConsumerProgram": firstConsumerKey == final.programCacheKeys.first,
            "noVariantRecompile": firstFrontendCount == consumer.variants.counters.frontendCompilationCount
                && firstLibraryCount == executor.materialEncoder.metalLibraryCompilationAttemptCount,
            "localFailureStayedLocal": fallback
                ? prior.effectLocalFailureReasonCode == "material-pass-preparation-library-compilation"
                    && final.effectLocalFailureReasonCode == nil
                : prior.effectLocalFailureReasonCode == nil && final.effectLocalFailureReasonCode == nil,
            "terminalReplayUsesOffscreen": prepared.terminalMaterialReplay == nil,
            "producerPixel": readbacks[0].firstPixel, "consumerPixel": readbacks[1].firstPixel,
            "mask": mask])
        previousStates = Dictionary(uniqueKeysWithValues: prepared.stages.map { ($0.effect, $0.transition.nextState) })
        previousResources = Dictionary(uniqueKeysWithValues: prepared.stages.map { ($0.effect, $0.persistentResources) })
    }
    return ["frames": rows, "oneWorkingPair": Set(leases.flatMap {
        $0.texturesByToken.values.map(ObjectIdentifier.init)
    }).count == 2]
}

private func runRawSignalPassthroughGraphScenario(
    device: MTLDevice, queue: MTLCommandQueue
) -> [String: Any] {
    let signalFirst = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID,
        effect: chainedFirstEffect, name: "raw-signal-first")
    let signalSecond = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID,
        effect: chainedSecondEffect, name: "raw-signal-second")
    let nodes = [
        material(0, ordinal: 0, target: signalFirst, read: input, owner: chainedFirstEffect),
        material(1, ordinal: 1, target: chainedFirstOutput, read: signalFirst, owner: chainedFirstEffect),
        material(2, ordinal: 0, target: signalSecond, read: chainedFirstOutput, owner: chainedSecondEffect),
        material(3, ordinal: 1, target: chainedSecondOutput, read: signalSecond, owner: chainedSecondEffect),
    ]
    let value = Graph(layerID: layerID, effects: [
        .init(key: chainedFirstEffect, definitionPath: "effects/raw-signal-first/effect.json",
            input: input, output: chainedFirstOutput, nodeIndices: [0, 1]),
        .init(key: chainedSecondEffect, definitionPath: "effects/raw-signal-second/effect.json",
            input: chainedFirstOutput, output: chainedSecondOutput, nodeIndices: [2, 3]),
    ], renderTargets: [rawTarget(signalFirst), rawTarget(signalSecond)], nodes: nodes,
        finalOutput: chainedSecondOutput, blockers: [])
    let producerSource = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() {
        vec4 carrier = texSample2D(g_Texture0, v_TexCoord);
        carrier.rgb *= carrier.a;
        carrier.a = 1.0;
        gl_FragColor = carrier;
        gl_FragColor.a *= 0.25;
    }
    """
    let passthroughSource = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
    """
    // Independent signals remain forbidden at final composition. This existing
    // source-independent material closes the graph while readbacks inspect
    // both raw passes, including the one in the preceding effect.
    let terminalSource = """
    varying vec2 v_TexCoord;
    void main() { gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0); }
    """
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
    for node in nodes {
        let original = template(for: node)
        let owner = value.effects.first { $0.key == node.effect }!
        let contract = shaderContract(nodeIndex: node.nodeIndex, pass: false,
            fragmentOverride: node.nodeIndex == 0 ? producerSource
                : node.nodeIndex == 3 ? terminalSource : passthroughSource)
        let template = Template.validated(textureSlots: original.textureSlots, combos: original.combos,
            uniformDeclarations: [], renderState: original.renderState, graphRole: original.graphRole,
            effectContext: .init(key: owner.key, input: owner.input), shaderContract: contract,
            diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: contract.identity,
                contractIdentity: contract.identity, contractCanonicalSHA256: contract.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(template, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: template))
    }
    let chain = orderedLayerGraph(value)
    let owners = capabilities(chain, catalog: .init(entries: entries, resourceDemandIssues: []))
    guard let claim = owners.claim(chain), let capability = owners.resolve(claim.token, for: chain),
          let leases = makeChainedLeases(capability, device: device),
          let rawFirst = capability.material(for: nodes[1]), let rawSecond = capability.material(for: nodes[2]),
          let executor = Executor(device: device, capabilities: owners),
          let sourcePipeline = makeProductionSourcePipeline(device) else {
        return ["failure": "raw-signal-admission", "reports": owners.reportLines]
    }
    var rows: [[String: Any]] = [], producerKey: String?, rawKey: String?
    var compilationCount = 0, libraryCount = 0
    var previousStates: [Graph.EffectKey: Executor.State] = [:]
    var previousResources: [Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]] = [:]
    for index in UInt64(1)...2 {
        let fallback = index == 2
        if fallback, let key = producerKey {
            executor.materialEncoder.installTestingPreparationFailure(
                .libraryCompilationRejected(diagnostic: "owned raw-signal producer fallback"), preparedKey: key)
        }
        let snapshot = frame(index), command = queue.makeCommandBuffer()!
        let preparation = executor.prepare(token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
            frame: snapshot, sourceTexture: makeSource(device, bgra: [26, 51, 102, 128]),
            sourceUniforms: .neutral(), sourcePipeline: sourcePipeline, frameInputs: .init(), commandBuffer: command,
            previousStates: previousStates, previousGraphResources: previousResources,
            effectGeneration: 1, resetGeneration: 1)
        guard case let .success(prepared) = preparation, prepared.stages.count == 2,
              let rawResource = prepared.stages[1].frameResources[signalSecond],
              let overlaid = snapshot.overlayingGraphResources([
                chainedFirstOutput: prepared.stages[0].effectOutputResource
              ]), case let .success(program) = SceneResolvedMaterialProgramFinalizer.finalize(
                overlaid.finalizationInput(layerID: layerID,
                    renderSize: CGSize(width: extent.width, height: extent.height),
                    modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
                    effectOutputModelViewProjection: matrix_identity_float4x4,
                    effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                    implicitFramebufferIdentity: chainedFirstOutput), variantCache: rawSecond.variants) else {
            return ["failure": failureCode(preparation), "frames": rows,
                "firstNominal": String(describing: rawFirst.variants.launchEnvelopeOutputContent),
                "secondNominal": String(describing: rawSecond.variants.launchEnvelopeOutputContent),
                "secondVariants": rawSecond.variants.launchEnvelopeCapabilitySnapshot().variants.map {
                    "content=\(String(describing: $0.preparedOutputContent)) boundary=\(String(describing: $0.frontendProgram.colorBoundary))"
                }]
        }
        var effects: [Readback] = []
        guard executor.encode(prepared, commandBuffer: command, stageBoundaryObserver: { _, stage, command in
            guard let read = appendReadback(stage.effectOutputResource.publication.texture,
                commandBuffer: command) else { return false }
            effects.append(read); return true
        }), effects.count == 2, let rawRead = appendReadback(rawResource.publication.texture,
            commandBuffer: command) else { return ["failure": "raw-signal-encode", "frames": rows] }
        let producerRead = prepared.stages[0].frameResources[signalFirst].flatMap {
            appendReadback($0.publication.texture, commandBuffer: command)
        }
        command.commit(); command.waitUntilCompleted()
        if index == 1 {
            producerKey = prepared.stages[0].programCacheKeys.first
            rawKey = prepared.stages[1].programCacheKeys.first
            compilationCount = rawSecond.variants.counters.frontendCompilationCount
            libraryCount = executor.materialEncoder.metalLibraryCompilationAttemptCount
        }
        let expectedInput: [UInt8] = fallback ? [26, 51, 102, 128] : [26, 51, 102, 64]
        let expectedRaw: [UInt8] = fallback ? [52, 102, 203, 128] : expectedInput
        let actualInput = SceneTextureContent.color(.resolved(fallback ? .premultipliedAlpha : .independentAlphaSignal))
        let actualOutput = SceneTextureContent.color(.resolved(fallback ? .straightAlpha : .independentAlphaSignal))
        let mask = zip(program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms).first { $0.0.field.name == "mwxPremultipliedColorInputMask" }
            .map { $0.1.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        rows.append([
            "completed": command.status == .completed && command.error == nil,
            "dynamicPassthroughAcrossEffects": [rawFirst, rawSecond].allSatisfy { material in
                let variants = material.variants.launchEnvelopeCapabilitySnapshot().variants
                return !variants.isEmpty && variants.allSatisfy {
                    $0.frontendProgram.colorBoundary?.signalPassthroughSlot == 0
                        && $0.frontendProgram.colorBoundary?.colorInputSlots == [0]
                }
            },
            "exactPassthroughBoundary": program.frontendProgram.colorBoundary?.signalPassthroughSlot == 0
                && program.frontendProgram.colorTransfer == .passthrough(textureSlot: 0)
                && mask == (fallback ? 1 : 256),
            "actualPublication": prepared.stages[0].effectOutputResource.publication.candidate.content == actualInput
                && rawResource.publication.candidate.content == actualOutput,
            "firstRawPassPixels": matches(effects[0].firstPixel, expectedInput) && matches(effects[0].lastPixel, expectedInput),
            "secondRawPassPixels": matches(rawRead.firstPixel, expectedRaw) && matches(rawRead.lastPixel, expectedRaw),
            "producerPixels": fallback ? producerRead == nil : producerRead.map {
                matches($0.firstPixel, expectedInput) && matches($0.lastPixel, expectedInput)
            } == true,
            "samePreparedRawPass": rawKey == prepared.stages[1].programCacheKeys.first,
            "noRepresentationRecompile": compilationCount == rawSecond.variants.counters.frontendCompilationCount
                && libraryCount == executor.materialEncoder.metalLibraryCompilationAttemptCount,
            "localFailureStayedLocal": fallback
                ? prepared.stages[0].effectLocalFailureReasonCode == "material-pass-preparation-library-compilation"
                    && prepared.stages[1].effectLocalFailureReasonCode == nil
                : prepared.stages.allSatisfy { $0.effectLocalFailureReasonCode == nil },
            "terminalIsOpaque": prepared.finalResource.publication.candidate.content == .color(.resolved(.opaque))
                && matches(effects[1].firstPixel, [191, 128, 64, 255]),
            "fallback": fallback, "rawPixel": rawRead.firstPixel,
        ])
        previousStates = Dictionary(uniqueKeysWithValues: prepared.stages.map { ($0.effect, $0.transition.nextState) })
        previousResources = Dictionary(uniqueKeysWithValues: prepared.stages.map { ($0.effect, $0.persistentResources) })
    }
    return ["frames": rows]
}
