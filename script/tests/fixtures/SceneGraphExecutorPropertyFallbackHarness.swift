// Prepared property inputs use the production compiler, catalog and executor.
@main private enum PropertyFallbackHarness {
    static func property(_ key: String, kind: SceneUserPropertyKind,
                         value: SceneUserPropertyValue) -> SceneUserPropertyDefinition {
        .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue,
            order: 0, index: nil, minimumValue: nil, maximumValue: nil,
            stepValue: nil, allowsFractionalValues: true, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: value, options: [])
    }

    static func inputs(name: String, key: String, pass: Int, live: Bool, startupCombo: Bool = false)
        -> ScenePropertyBindingCompilation {
        var passes = Array(repeating: [String: Any](), count: pass + 1)
        passes[pass] = ["constantshadervalues": [name: [
            "user": live ? "palette" : key, "value": "0.2 0.4 0.6"]]]
        if startupCombo { passes[pass]["combos"] = ["USE_GATE": ["user": key, "value": 0]] }
        let root: [String: Any] = ["objects": [["id": layerID, "effects": [
            ["id": 501, "file": "effects/own/value.json", "passes": passes,
             "visible": ["user": key, "value": true]],
            ["id": 502, "file": "effects/own/peer.json",
             "visible": ["user": key, "value": true]],
        ]]]]
        return ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(root: root),
            catalog: .init(definitions: [property(key, kind: .bool, value: .bool(true)),
                property("palette", kind: .color, value: .string("0.8 0.2 0.4"))]))
    }

    static func valueTemplate(node: Graph.Node, graphInput: Graph.TextureIdentity,
                              key: String, name: String, uniform: String,
                              target: SceneDynamicTarget, variant: String) -> Template {
        let abi = variant == "abi" ? "vec4" : "vec3"
        let contract = shaderContract(nodeIndex: node.nodeIndex, pass: false,
            fragmentOverride: """
            varying vec2 v_TexCoord;
            uniform \(abi) \(uniform); // {"material":"\(name)","default":"0 0 1\(variant == "abi" ? " 1" : "")"}
            void main() { gl_FragColor = vec4(\(uniform).rgb, 1.0); }
            """)
        let bits = (variant == "bits" ? [0.3, 0.4, 0.6] : [0.2, 0.4, 0.6]).map(\.bitPattern)
        let keys = variant == "wrapper" ? ["script", "user", "value"] : ["user", "value"]
        let contributors: [Template.DynamicUniformSource] = variant == "multiContributor"
            ? [.userProperty(key), .timeline] : variant == "timelineMissing" ? [.timeline] : [.userProperty(key)]
        let declaration = Template.UniformDeclaration(name: name, value: .dynamic(.init(
            target: target, valueContributors: contributors,
            scriptAttachments: variant == "script" ? [.unproven] : [],
            authoredFallback: .init(valueKind: "binding", componentBitPatterns: bits,
                authoredBindingKeys: keys), authoredBindingKeys: keys)))
        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        slots[0] = .init(index: 0, candidates: [.init(reference: .graph(graphInput),
            provenance: .explicitBinding)])
        return Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [declaration],
            renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
            graphRole: .init(effectInput: role(graphInput), effectOutput: .effectOutput,
                nodeTarget: .effectOutput, bindings: [.init(slot: 0, texture: role(graphInput))]),
            effectContext: .init(key: node.effect, input: graphInput), shaderContract: contract,
            diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: contract.identity,
                contractIdentity: contract.identity, contractCanonicalSHA256: contract.canonicalSHA256,
                textureSources: [], uniformSources: []))!
    }

    static func run(_ variant: String, device: MTLDevice, queue: MTLCommandQueue,
                    sourcePipeline: SceneImageLayerPipeline) throws -> [String: Any] {
        let renamed = variant == "renamed", live = variant == "liveColor" || variant == "liveColorChanged"
        let name = renamed ? "Moved pigment" : "Tint", uniform = renamed ? "u_Unseen" : "u_Tint"
        let key = renamed ? "moved-toggle" : "shared-toggle", pass = renamed ? 3 : 0
        let propertyKey = live ? "palette" : key
        let firstOwner = Graph.EffectKey(layerID: layerID, effectIndex: 0,
            descriptorID: renamed ? "moved-value" : "own-value")
        let peerOwner = Graph.EffectKey(layerID: layerID, effectIndex: 1,
            descriptorID: renamed ? "moved-peer" : "own-peer")
        let firstOutput = Graph.TextureIdentity(kind: .effectOutput, layerID: layerID, effect: firstOwner, name: nil)
        let peerOutput = Graph.TextureIdentity(kind: .effectOutput, layerID: layerID, effect: peerOwner, name: nil)
        let target = SceneDynamicTarget.effectConstant(layerID: layerID, effectIndex: 0, passIndex: pass, name: name)
        let firstVisibility = SceneDynamicTarget.effectVisibility(layerID: layerID, effectIndex: 0)
        let peerVisibility = SceneDynamicTarget.effectVisibility(layerID: layerID, effectIndex: 1)
        let node = Graph.Node(nodeIndex: 0, effect: firstOwner, definitionPassIndex: 0,
            materialOrdinal: 0, instancePassIndex: pass, kind: .material,
            materialPath: renamed ? "materials/moved/value.json" : "materials/own/value.json",
            materialPassID: "own-value#0", target: firstOutput, bindings: [binding(input)],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil)
        let peerNode = material(1, ordinal: 0, target: peerOutput, read: firstOutput, owner: peerOwner)
        let graph = Graph(layerID: layerID, effects: [
            .init(key: firstOwner, definitionPath: renamed ? "effects/moved/value.json" : "effects/own/value.json",
                input: input, output: firstOutput, nodeIndices: [0]),
            .init(key: peerOwner, definitionPath: "effects/own/peer.json",
                input: firstOutput, output: peerOutput, nodeIndices: [1]),
        ], renderTargets: [], nodes: [node, peerNode], finalOutput: peerOutput, blockers: [])
        let admitted = orderedLayerGraph(graph)
        let compilation = inputs(name: name, key: key, pass: pass, live: live)
        let colorDefinition = compilation.program.definitions.first { $0.target == target }!
        var definitions = compilation.program.definitions
        var producers = Set(compilation.program.instructions.map {
            SceneDynamicUserPropertyProducer(propertyKey: $0.propertyKey, target: $0.target, valueType: $0.valueType)
        })
        if variant == "writerKey" || variant == "writerMultiple" {
            producers.insert(.init(propertyKey: "another-key", target: target, valueType: .vector3))
        }
        if variant == "writerType" || variant == "writerMultiple" {
            producers.insert(.init(propertyKey: key, target: target,
                valueType: variant == "writerType" ? .bool : .vector3))
        }
        var fallbackTargets = Set(definitions.map(\.target))
        if variant == "noFallbackDefinition" {
            fallbackTargets.remove(target)
            definitions.removeAll { $0.target == target }
        } else if variant == "snapshotMissing" {
            definitions.removeAll { $0.target == target }
        } else if variant == "snapshotType" {
            definitions = definitions.filter { $0.target != target }
                + [.init(target: target, valueType: .bool, authoredValue: .bool(true))]
        }
        let declaredTarget = variant == "declarationTarget"
            ? SceneDynamicTarget.effectConstant(layerID: layerID, effectIndex: 0, passIndex: pass + 1, name: name) : target
        let value = valueTemplate(node: node, graphInput: input, key: propertyKey, name: name,
            uniform: uniform, target: declaredTarget, variant: variant)
        let peerContract = shaderContract(nodeIndex: 1, pass: false, constantColor: "0.0, 1.0, 0.0")
        var peerSlots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        peerSlots[0] = .init(index: 0, candidates: [.init(reference: .graph(firstOutput), provenance: .explicitBinding)])
        let peer = Template.validated(textureSlots: peerSlots, combos: [],
            uniformDeclarations: [], renderState: value.renderState,
            graphRole: .init(effectInput: .effectOutput, effectOutput: .effectOutput,
                nodeTarget: .effectOutput, bindings: [.init(slot: 0, texture: .effectOutput)]),
            effectContext: .init(key: peerOwner, input: firstOutput), shaderContract: peerContract,
            diagnosticProvenance: .init(nodeIndex: 1, authoredShaderPath: peerContract.identity,
                contractIdentity: peerContract.identity, contractCanonicalSHA256: peerContract.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        let catalog = SceneResolvedMaterialRuntimeCatalog(entries: [
            .init(effect: firstOwner, nodeIndex: 0): .template(value,
                textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value)),
            .init(effect: peerOwner, nodeIndex: 1): .template(peer,
                textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: peer)),
        ])
        let producerCatalog = Capabilities.DynamicProducerCatalog(userProperties: producers,
            authoredFallbackTargets: fallbackTargets,
            timelineDefinitions: variant == "multiContributor" ? [colorDefinition] : [], sceneScriptTargets: [])
        let caps = capabilities(admitted, catalog: catalog, dynamicProducers: producerCatalog)
        var row: [String: Any] = ["case": variant,
            "colorInstructions": compilation.program.instructions.filter { $0.target == target }.count,
            "sameKeyOtherProducers": producers.filter { $0.propertyKey == key && $0.target != target }.count,
            "rebuildKeys": compilation.program.rebuildRequiredPropertyKeys,
            "target": String(describing: target), "catalogReports": caps.reportLines]
        if variant == "multiContributor" || variant == "script" {
            row["directUniformReason"] = Capabilities.dynamicUniformExecutionRejection(
                value, node: node, producers: producerCatalog)?.code ?? "accepted"
        }
        if variant == "fallback" {
            let withCombo = inputs(name: name, key: key, pass: pass, live: false, startupCombo: true).program
            row["comboRebuildKeys"] = withCombo.rebuildRequiredPropertyKeys
            row["comboBoolProducerCount"] = withCombo.instructions.filter {
                $0.propertyKey == key && $0.valueType == .bool
            }.count
            row["comboColorInstructions"] = withCombo.instructions.filter { $0.target == target }.count
            row["comboHasAuthoredDefinition"] = withCombo.definitions.contains { $0 == colorDefinition }
        }
        guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token) else {
            row["capability"] = "rejected"
            return row
        }
        switch capability.stages[0].execution {
        case .resolved: row["capability"] = "resolved"
        case let .visualFailurePassthrough(reason): row["capability"] = "visual-failure"; row["coldReason"] = reason
        case let .initiallyInactivePassthrough(reason): row["capability"] = "inactive"; row["coldReason"] = reason
        }
        row["peerHasBoolPolicy"] = capability.stages[1].execution.activationPolicy?.effectVisibilityTarget == peerVisibility
        row["firstHasBoolPolicy"] = capability.stages[0].execution.activationPolicy?.effectVisibilityTarget == firstVisibility
        let evaluation = compilation.program.evaluate(effectiveValues: [key: .bool(variant != "inactive"),
            "palette": .string(variant == "liveColorChanged" ? "0.4 0.6 0.8" : "0.8 0.2 0.4")])
        let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: definitions, userValues: evaluation.userValues,
            timelineValues: variant == "source" ? [target: .vector3(0.9, 0.8, 0.7)] : [:]).snapshot
        row["snapshotSource"] = snapshot[target]?.source.rawValue ?? "missing"
        let frameSnapshot = try SceneResolvedMaterialFrameSnapshot.validated(
            textureSnapshot: .init(frameEpoch: 1, frameIndex: 1, entries: [:]), dynamicSnapshot: snapshot,
            frameInputs: .init(frameIndex: 1, screenSize: CGSize(width: 2, height: 2), sceneTime: 0,
                dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero)).get()
        if let material = capability.material(effect: firstOwner, nodeIndex: 0) {
            let bound = material.bindFrame(frameSnapshot.finalizationInput(layerID: layerID,
                renderSize: CGSize(width: 2, height: 2), modelViewProjection: matrix_identity_float4x4,
                layerModelMatrix: matrix_identity_float4x4, effectOutputModelViewProjection: matrix_identity_float4x4,
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4, implicitFramebufferIdentity: input))
            switch bound {
            case let .success(program):
                row["frameBinding"] = "success"
                if let pair = zip(program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms)
                    .first(where: { $0.0.field.name == uniform }) {
                    row["uniformSource"] = pair.1.resolvedSource?.rawValue ?? "static"
                    row["uniformValues"] = pair.1.encodedValue.withUnsafeBytes { bytes in
                        stride(from: 0, to: bytes.count, by: 4).map { Double(bytes.loadUnaligned(fromByteOffset: $0, as: Float.self)) }
                    }
                }
            case let .failure(failure): row["frameBinding"] = "\(failure.phase.rawValue)/\(failure.code.rawValue)"
            }
        } else { row["frameBinding"] = "not-entered" }
        guard let leases = makeChainedLeases(capability, device: device, generation: 1),
              let executor = Executor(device: device, capabilities: caps), let command = queue.makeCommandBuffer() else {
            row["executionFailure"] = "setup"; return row
        }
        let prepared = executor.prepare(token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
            frame: frameSnapshot, sourceTexture: makeSource(device, bgra: [56, 40, 24, 255]),
            sourceUniforms: .neutral(), sourcePipeline: sourcePipeline, frameInputs: .init(dynamicValues: snapshot),
            commandBuffer: command, previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1)
        guard case let .success(graph) = prepared else {
            row["executionFailure"] = failureCode(prepared); return row
        }
        row["stageFailures"] = graph.stages.map { $0.effectLocalFailureReasonCode ?? "" }
        row["activationBypasses"] = graph.stages.map { $0.effectLocalActivationBypassReasonCode ?? "" }
        var reads: [Readback] = []
        guard executor.encode(graph, commandBuffer: command, stageBoundaryObserver: { _, stage, buffer in
            guard let read = appendReadback(stage.effectOutputResource.publication.texture,
                commandBuffer: buffer) else { return false }
            reads.append(read); return true
        }) else { row["executionFailure"] = "encode"; return row }
        command.commit(); command.waitUntilCompleted()
        row["completed"] = command.status == .completed && command.error == nil
        row["pixelsRGBA"] = reads.map { read -> [UInt8] in
            let b = read.firstPixel; return [b[2], b[1], b[0], b[3]]
        }
        row["allPixelsUniform"] = reads.allSatisfy { read in read.allTexels.allSatisfy { $0 == read.firstPixel } }
        return row
    }

    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}"); return
        }
        let sourcePipeline = makeSourcePipeline(device)
        let cases = ["fallback", "renamed", "inactive", "liveColor", "liveColorChanged",
            "writerKey", "writerType", "writerMultiple", "noFallbackDefinition", "wrapper", "multiContributor",
            "script", "timelineMissing", "declarationTarget", "snapshotMissing", "source", "abi", "bits", "snapshotType"]
        let rows = try cases.map { try run($0, device: device, queue: queue, sourcePipeline: sourcePipeline) }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["metalAvailable": true, "rows": rows], options: [.sortedKeys]), as: UTF8.self))
    }
}
