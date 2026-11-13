private enum RuntimeHistoryFixture {
    static let owners = [chainedFirstEffect, chainedSecondEffect]
    static let outputs = [chainedFirstOutput, chainedSecondOutput]
    static let histories = owners.map {
        Graph.TextureIdentity(kind: .framebuffer, layerID: layerID, effect: $0, name: "trail")
    }
    static let scratches = owners.map {
        Graph.TextureIdentity(kind: .framebuffer, layerID: layerID, effect: $0, name: "update")
    }
    static let visibility = SceneDynamicTarget.effectVisibility(layerID: layerID, effectIndex: 1)

    static func node(
        _ index: Int, owner: Graph.EffectKey, ordinal: Int?,
        source: Graph.TextureIdentity, target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(nodeIndex: index, effect: owner, definitionPassIndex: index,
            materialOrdinal: ordinal, instancePassIndex: ordinal,
            kind: ordinal == nil ? .copy : .material,
            materialPath: ordinal.map { "materials/runtime-history-\(index)-\($0).json" },
            materialPassID: ordinal.map { "runtime-history-\(index)#\($0)" }, target: ordinal == nil ? nil : target,
            bindings: ordinal == nil ? [] : [.init(slot: 0, authoredName: "state", texture: source, conditions: nil)],
            commandSource: ordinal == nil ? source : nil, commandTarget: ordinal == nil ? target : nil,
            compose: nil, conditions: nil)
    }

    static func graph() -> Graph {
        var effects: [Graph.Effect] = []
        var nodes: [Graph.Node] = []
        for index in owners.indices {
            let start = index * 3
            nodes += [
                node(start, owner: owners[index], ordinal: 0, source: histories[index], target: scratches[index]),
                node(start + 1, owner: owners[index], ordinal: nil, source: scratches[index], target: histories[index]),
                node(start + 2, owner: owners[index], ordinal: 1, source: histories[index], target: outputs[index]),
            ]
            effects.append(.init(key: owners[index], definitionPath: "effects/runtime-history-\(index)/effect.json",
                input: index == 0 ? input : outputs[index - 1], output: outputs[index],
                nodeIndices: [start, start + 1, start + 2]))
        }
        nodes.append(node(6, owner: chainedThirdEffect, ordinal: 0,
            source: chainedSecondOutput, target: chainedFinalOutput))
        effects.append(.init(key: chainedThirdEffect, definitionPath: "effects/runtime-suffix/effect.json",
            input: chainedSecondOutput, output: chainedFinalOutput, nodeIndices: [6]))
        return .init(layerID: layerID, effects: effects,
            renderTargets: histories.map { rawTarget($0, unique: true) } + scratches.map { rawTarget($0) },
            nodes: nodes, finalOutput: chainedFinalOutput, blockers: [])
    }

    static func catalog(_ graph: Graph) -> SceneResolvedMaterialRuntimeCatalog {
        var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
        for node in graph.nodes where node.kind == .material {
            let effect = graph.effects.first { $0.key == node.effect }!
            let body: String
            switch node.nodeIndex {
            case 0, 3:
                body = "gl_FragColor = vec4(texSample2D(g_Texture0, v_TexCoord.xy).r * 0.5 + 0.25, 0.0, 0.0, 1.0);"
            case 2:
                body = "gl_FragColor = vec4(0.0, 0.0, texSample2D(g_Texture0, v_TexCoord.xy).r, 1.0);"
            case 5:
                body = "gl_FragColor = texSample2D(g_Texture0, v_TexCoord.xy) * vec4(g_LightAmbientColor, 1.0);"
            default:
                body = "vec4 color = texSample2D(g_Texture0, v_TexCoord.xy); gl_FragColor = vec4(color.bgr, color.a);"
            }
            let contract = shaderContract(nodeIndex: node.nodeIndex, pass: false, fragmentOverride: """
                varying vec2 v_TexCoord;
                uniform sampler2D g_Texture0;
                \(node.nodeIndex == 5 ? "uniform vec3 g_LightAmbientColor;" : "")
                void main() { \(body) }
                """)
            var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
            slots[0] = .init(index: 0, candidates: [.init(reference: .graph(node.bindings[0].texture), provenance: .explicitBinding)])
            let template = Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
                renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
                    depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
                graphRole: .init(effectInput: role(effect.input), effectOutput: role(effect.output),
                    nodeTarget: role(node.target!), bindings: [.init(slot: 0, texture: role(node.bindings[0].texture))]),
                effectContext: .init(key: effect.key, input: effect.input),
                shaderContract: contract, diagnosticProvenance: .init(nodeIndex: node.nodeIndex,
                    authoredShaderPath: contract.identity, contractIdentity: contract.identity,
                    contractCanonicalSHA256: contract.canonicalSHA256, textureSources: [], uniformSources: []))!
            entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(template,
                textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: template))
        }
        return .init(entries: entries)
    }

    static func leases(_ capability: Capabilities.LayerCapability, device: MTLDevice, generation: UInt64) -> [SceneGraphRenderTargetLease] {
        makeChainedLeases(capability, device: device, generation: generation)!.enumerated().map { index, lease in
            var ordinal = 0
            let result = SceneGraphRenderTargetLease.make(table: lease.table, generation: generation,
                tokenForTexture: { _ in
                    defer { ordinal += 1 }
                    return .init(rawValue: "runtime-history-\(generation)-\(index)-\(ordinal)")
                }, fullFramePairGeneration: generation,
                tokenForPairTexture: { object in
                    .init(rawValue: "runtime-pair-\(generation)-\(object === lease.table.fullFramePair.first ? 0 : 1)")
                })
            guard case let .success(value) = result else { fatalError("runtime lease") }
            return value
        }
    }
}

@main
private enum RuntimeHistoryHarness {
    struct ResultFrame {
        let graph: Executor.PreparedGraph
        let leases: [SceneGraphRenderTargetLease]
        let stagePixels: [[UInt8]]
        let historyPixels: [[UInt8]?]
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError(label) }
    }

    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", "ordinary-shader=disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let fixture = RuntimeHistoryFixture.self
        let graph = fixture.graph()
        let chain = orderedLayerGraph(graph)
        let capabilities = capabilities(chain, catalog: fixture.catalog(graph), dynamicProducers: .init(
            userProperties: [.init(propertyKey: "visible", target: fixture.visibility, valueType: .bool)],
            authoredFallbackTargets: [fixture.visibility], timelineTargets: [], sceneScriptTargets: []))
        guard let claim = capabilities.claim(chain), let capability = capabilities.resolve(claim.token, for: chain),
              let executor = Executor(device: device, capabilities: capabilities) else {
            fatalError("runtime setup: \(capabilities.reportLines.joined(separator: " | "))")
        }
        let stageReasons = capability.stages.map { $0.execution.visualFailureReasonCode ?? "resolved" }
        expect(stageReasons == ["resolved", "resolved", "resolved"], "resolved stages: \(stageReasons)")
        expect(capability.stages[1].execution.activationPolicy != nil, "activation policy")
        let source = makeSource(device)
        let pipeline = makeSourcePipeline(device)

        func run(_ index: UInt64, previous: ResultFrame? = nil, ambientAvailable: Bool = true,
                 visible: Bool = true, reset: UInt64 = 1) -> ResultFrame {
            let leases = fixture.leases(capability, device: device, generation: index)
            var copies: [Graph.EffectKey: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]] = [:]
            if let previous {
                for stage in 0 ..< 2 {
                    copies[fixture.owners[stage]] = historyCopies(transition: previous.graph.stages[stage],
                        sourceLease: previous.leases[stage], targetLease: leases[stage])!
                }
            }
            let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: index, generation: index,
                definitions: [.init(target: fixture.visibility, valueType: .bool, authoredValue: .bool(true))],
                userValues: [fixture.visibility: .bool(visible)]).snapshot
            let snapshot = SceneResolvedMaterialFrameSnapshot.validated(
                textureSnapshot: .init(frameEpoch: index, frameIndex: index, entries: [:]), dynamicSnapshot: dynamic,
                frameInputs: .init(frameIndex: index, screenSize: CGSize(width: extent.width, height: extent.height),
                    sceneTime: Float(index), dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero,
                    lighting: .init(positions: nil, colorsPremultiplied: nil,
                        ambient: ambientAvailable ? .init(repeating: 1) : nil, worldFromRenderWorld: nil)))
            guard case let .success(frame) = snapshot else { fatalError("runtime frame") }
            let command = queue.makeCommandBuffer()!
            let preparation = executor.prepare(token: claim.token, leases: leases, historyRehydrateCopiesByEffect: copies,
                frame: frame, sourceTexture: source, sourceUniforms: .neutral(), sourcePipeline: pipeline,
                frameInputs: .init(dynamicValues: dynamic), commandBuffer: command,
                previousStates: Dictionary(uniqueKeysWithValues: previous?.graph.stages.map { ($0.effect, $0.transition.nextState) } ?? []),
                previousGraphResources: Dictionary(uniqueKeysWithValues: previous?.graph.stages.map { ($0.effect, $0.persistentResources) } ?? []),
                effectGeneration: 1, resetGeneration: reset)
            guard case let .success(prepared) = preparation else { fatalError("runtime prepare: \(failureCode(preparation))") }
            var stageReads: [Readback] = []
            expect(executor.encode(prepared, commandBuffer: command, stageBoundaryObserver: { _, stage, buffer in
                guard let read = appendReadback(stage.effectOutputResource.publication.texture, commandBuffer: buffer) else { return false }
                stageReads.append(read)
                return true
            }), "runtime encode")
            let historyReads = fixture.histories.enumerated().map { stage, identity in
                prepared.stages[stage].persistentResources[identity].flatMap {
                    appendReadback($0.publication.texture, commandBuffer: command)
                }
            }
            command.commit()
            command.waitUntilCompleted()
            expect(command.status == .completed && command.error == nil, "runtime GPU completion")
            return .init(graph: prepared, leases: leases, stagePixels: stageReads.map(\.firstPixel),
                historyPixels: historyReads.map { $0?.firstPixel })
        }

        let first = run(100)
        expect(first.graph.stages.prefix(2).allSatisfy { $0.historyRehydrateCopyCount == 0 }, "first seed copy count")
        expect(first.historyPixels.prefix(2).allSatisfy { $0.map { matches($0, [0, 0, 64, 255]) } == true }, "nontransparent first histories")
        let split = run(101, previous: first)
        expect(split.graph.stages.prefix(2).allSatisfy { $0.historyRehydrateCopyCount == 0 }, "successful split has no seed copy")
        expect(split.historyPixels.prefix(2).allSatisfy { $0.map { matches($0, [0, 0, 96, 255]) } == true }, "established histories accumulate")
        let failed = run(102, previous: split, ambientAvailable: false)
        let failedStage = failed.graph.stages[1]
        expect(failedStage.effectLocalFailureReasonCode == "material-finalizer-host-input-unavailable", "runtime uniform fallback")
        expect(failedStage.transition.transaction.intents.isEmpty && failedStage.historyRehydrateCopyCount == 1,
            "failed stage discards authored material and copy, then seeds once")
        expect(failed.graph.stages[0].historyRehydrateCopyCount == 0, "healthy prefix still splits")
        expect(matches(failed.historyPixels[0]!, [0, 0, 112, 255]), "healthy prefix authored copy executes")
        expect(matches(failed.historyPixels[1]!, [0, 0, 96, 255]), "failed history keeps old pixels")
        expect(matches(failed.stagePixels[1], [112, 0, 0, 255]) && matches(failed.stagePixels[2], [0, 0, 112, 255]),
            "failed effect preserves healthy prefix and suffix")
        let old = split.graph.stages[1]
        expect(failedStage.transition.nextState.lastContentGeneration == old.transition.nextState.lastContentGeneration,
            "failed effect keeps committed generation")
        let failedHistory = failedStage.persistentResources[fixture.histories[1]]!
        expect(failedHistory.publication.texture !== old.persistentResources[fixture.histories[1]]!.publication.texture,
            "fallback history belongs to fresh lease")
        expect(failed.graph.historyTokensByEffect[fixture.owners[1]] == Set([failedStage.transition.nextState.logicalMapping[fixture.histories[1]]!.token]),
            "history retention token follows fresh fallback lease")
        let repeated = run(103, previous: failed, ambientAvailable: false)
        expect(matches(repeated.historyPixels[1]!, [0, 0, 96, 255]) && repeated.graph.stages[1].historyRehydrateCopyCount == 1,
            "repeated runtime failure retains history")
        let recovered = run(104, previous: repeated)
        expect(recovered.graph.stages.prefix(2).allSatisfy { $0.historyRehydrateCopyCount == 0 }, "recovery returns to split")
        expect(matches(recovered.historyPixels[1]!, [0, 0, 112, 255]) && matches(recovered.stagePixels[2], [112, 0, 0, 255]),
            "recovery continues old accumulation")

        let inactive = run(105, previous: recovered, visible: false)
        expect(inactive.graph.stages[1].effectLocalFailureReasonCode == nil
            && inactive.graph.stages[1].effectLocalActivationBypassReasonCode != nil
            && inactive.graph.stages[1].historyRehydrateCopyCount == 1,
            "inactive activation keeps seed path")
        expect(matches(inactive.historyPixels[1]!, [0, 0, 112, 255]), "inactive activation preserves history")
        let active = run(106, previous: inactive)
        expect(active.graph.stages[1].historyRehydrateCopyCount == 0
            && matches(active.historyPixels[1]!, [0, 0, 120, 255]), "reactivation resumes accumulation")

        let firstFailed = run(110, ambientAvailable: false)
        expect(firstFailed.historyPixels[1] == nil && firstFailed.graph.stages[1].historyRehydrateCopyCount == 0,
            "first runtime failure invents no history")
        let firstRecovery = run(111, previous: firstFailed)
        expect(matches(firstRecovery.historyPixels[1]!, [0, 0, 64, 255]), "first failure recovery starts transparent")
        let resetFailed = run(112, previous: active, ambientAvailable: false, reset: 2)
        expect(resetFailed.historyPixels[1] == nil && resetFailed.graph.stages[1].historyRehydrateCopyCount == 0,
            "reset failure does not seed invalidated history")
        let resetRecovery = run(113, previous: resetFailed, reset: 2)
        expect(matches(resetRecovery.historyPixels[1]!, [0, 0, 64, 255]), "reset recovery starts transparent")
        print("{\"metalAvailable\":true,\"runtimeHistoryFallback\":true,\"healthyStageCopyAndSuffix\":true,\"repeatedFailure\":true,\"activation\":true,\"firstFrame\":true,\"reset\":true}")
    }
}
