#!/usr/bin/env python3
"""Source capture to authored alpha expansion through the existing graph harness."""
import json
import shutil
import unittest

from script.tests.test_scene_resolved_material_graph_executor import HARNESS_SUPPORT_SOURCE, SUPPORT, compile_lit_harness


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSourceColorGraphTests(unittest.TestCase):
    def test_text_rt_capture_retains_projected_prefix_rgb_and_glyph_alpha(self) -> None:
        harness = HARNESS_SUPPORT_SOURCE + r'''
private func sourceColorCatalog(_ graph: Graph) -> SceneResolvedMaterialRuntimeCatalog {
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
    for node in graph.nodes where node.kind == .material {
        let original = node.bindings.isEmpty
            ? implicitFramebufferTemplate(for: node) : template(for: node, pass: true)
        let transform = node.target == chainedFirstOutput
            ? "retainedCarrier.rgb = vec3(1.0) - retainedCarrier.rgb;"
            : node.target == output ? "retainedCarrier.rgb += vec3(0.1); retainedCarrier.a = 0.5;" : ""
        let contract = shaderContract(nodeIndex: node.nodeIndex, pass: true, fragmentOverride: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            void main() { vec4 retainedCarrier = texSample2D(g_Texture0, v_TexCoord);
                \(transform) gl_FragColor = retainedCarrier; }
            """)
        let value = Template.validated(textureSlots: original.textureSlots, combos: [],
            uniformDeclarations: [], renderState: original.renderState, graphRole: original.graphRole,
            effectContext: .init(key: node.effect, input: graph.effects.first { $0.key == node.effect }!.input),
            shaderContract: contract, diagnosticProvenance: .init(nodeIndex: node.nodeIndex,
                authoredShaderPath: contract.identity, contractIdentity: contract.identity,
                contractCanonicalSHA256: contract.canonicalSHA256, textureSources: [], uniformSources: []))!
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(value, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))
    }
    return .init(entries: entries, resourceDemandIssues: [])
}

private func sourceColorPipeline(_ device: MTLDevice, format: MTLPixelFormat) throws -> SceneImageLayerPipeline {
    let library = device.makeDefaultLibrary()!, constants = MTLFunctionConstantValues()
    var additive = false
    constants.setConstantValue(&additive, type: .bool, index: 0)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "sceneImageLayerVert")
    descriptor.fragmentFunction = try library.makeFunction(name: "sceneImageLayerFrag", constantValues: constants)
    let color = descriptor.colorAttachments[0]!
    color.pixelFormat = format; color.isBlendingEnabled = true
    color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
    color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    return .init(pixelFormat: format, state: try device.makeRenderPipelineState(descriptor: descriptor))
}

@main private enum TextSourceColorHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let pipeline = makeProductionSourcePipeline(device) else {
            print("{\"metalAvailable\":false}"); return
        }
        var results: [String: Bool] = [:], diagnostics: [[String: Any]] = []
        let value = graph(targets: [rawTarget(first)], nodes: [
            implicitFramebufferMaterial(0, ordinal: 0, target: first),
            material(1, ordinal: 1, target: output, read: first)])
        let renamed = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID, effect: effect,
            name: "unseen-authored-color-carrier")
        let renamedGraph = graph(targets: [rawTarget(renamed)], nodes: [
            material(0, ordinal: 0, target: renamed, read: input),
            material(1, ordinal: 1, target: output, read: renamed)])
        let direct = graph(targets: [], nodes: [material(0, ordinal: 0, target: output, read: input)])
        let unusedRT = graph(targets: [rawTarget(first)], nodes: direct.nodes)
        let copyFirst = graph(targets: [rawTarget(first)], nodes: [
            command(0, kind: .copy, source: input, target: first),
            material(1, ordinal: 0, target: output, read: first)])
        let overwrittenRT = graph(targets: [rawTarget(first)], nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: first, read: input),
            material(2, ordinal: 2, target: output, read: first)])
        let laterRT = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID,
            effect: chainedSecondEffect, name: "later-effect-only")
        let prior = Graph(layerID: layerID, effects: [
            .init(key: chainedFirstEffect, definitionPath: "effects/prior/effect.json", input: input,
                  output: chainedFirstOutput, nodeIndices: [0]),
            .init(key: chainedSecondEffect, definitionPath: "effects/later/effect.json", input: chainedFirstOutput,
                  output: chainedSecondOutput, nodeIndices: [1, 2])], renderTargets: [rawTarget(laterRT)], nodes: [
            material(0, ordinal: 0, target: chainedFirstOutput, read: input, owner: chainedFirstEffect),
            material(1, ordinal: 0, target: laterRT, read: chainedFirstOutput, owner: chainedSecondEffect),
            material(2, ordinal: 1, target: chainedSecondOutput, read: laterRT, owner: chainedSecondEffect)],
            finalOutput: chainedSecondOutput, blockers: [])
        let visibility = SceneDynamicTarget.effectVisibility(layerID: layerID, effectIndex: effect.effectIndex)
        let dynamicProducers = Capabilities.DynamicProducerCatalog(userProperties: [
            .init(propertyKey: "unseen-first-stage-active", target: visibility, valueType: .bool)],
            authoredFallbackTargets: [visibility], timelineTargets: [], sceneScriptTargets: [])
        let qualification: [(String, Graph, String, Bool, Bool)] = [
            ("implicitMissingAlias", value, "text", false, true), ("renamedRT", renamedGraph, "text", false, true),
            ("ordinaryImage", value, "image", false, false), ("direct", direct, "text", false, false),
            ("unusedRT", unusedRT, "text", false, false), ("copyFirst", copyFirst, "text", false, false),
            ("overwrittenRT", overwrittenRT, "text", false, false),
            ("priorEffect", prior, "text", false, false), ("dynamicFirst", value, "text", true, true)]
        for (name, graphValue, kind, dynamic, expected) in qualification {
            let chain = graphValue.effects.count > 1 ? orderedLayerGraph(graphValue) : admittedGraph(graphValue)
            debugLastCandidateFailureCode = ""
            let owners = capabilities(chain, catalog: sourceColorCatalog(graphValue),
                dynamicProducers: dynamic ? dynamicProducers : .empty, contentKind: kind)
            let capability = owners.claim(chain).flatMap { owners.resolve($0.token, for: chain) }
            if name == "copyFirst" {
                results["copyFirst-rejected-by-existing-pair-plan"] = capability == nil
                    && debugLastCandidateFailureCode == "pair-plan-invalid-node-shape"
                diagnostics.append(["case": "copyFirst", "admissionFailure": debugLastCandidateFailureCode])
            } else {
                results["qualified-" + name] = capability != nil
                    && (capability!.sceneBackgroundRequirement?.capturesTextSourcePrefixRGB == true) == expected
            }
            if name == "implicitMissingAlias", let capability {
                let variants = capability.material(for: graphValue.nodes[0])!.variants.launchEnvelopeCapabilitySnapshot().variants
                results["qualified-" + name] = results["qualified-" + name] == true && !variants.isEmpty
                    && variants.allSatisfy { $0.graphInputSourceSlotFacts[0]?.provenance == .implicitMissingAlias }
            }
        }
        let chain = admittedGraph(value)
        let parentedOwners = capabilities(chain, catalog: sourceColorCatalog(value), contentKind: "text", parentID: layerID - 1)
        let parented = parentedOwners.claim(chain).flatMap { parentedOwners.resolve($0.token, for: chain) }
        results["parented-text-keeps-original-source"] = parented != nil && parented!.sceneBackgroundRequirement == nil
        let owners = capabilities(chain, catalog: sourceColorCatalog(value), contentKind: "text")
        guard let claim = owners.claim(chain), let capability = owners.resolve(claim.token, for: chain),
              let executor = Executor(device: device, capabilities: owners) else {
            print("{\"metalAvailable\":true,\"failure\":\"text-source-admission\"}"); return
        }
        let prefixBytes: [UInt8] = [120,80,40,0, 120,80,40,0, 60,20,160,255, 60,20,160,255]
        let prefix = makeSource(device, width: 4, height: 2, usage: [.renderTarget, .shaderRead],
            pixelsBGRA: prefixBytes + prefixBytes)
        let full = simd_float4x4(diagonal: SIMD4<Float>(2,2,1,1))
        var shifted = matrix_identity_float4x4
        shifted.columns.3.x = 0.5
        // Hand-calculated BGRA: two distinct prefix colors; prefix alpha differs
        // while glyph coverage alone determines the captured alpha.
        let samples: [(UInt8, [UInt8], [UInt8], [UInt8], [UInt8], [UInt8])] = [
            (0, [0,0,0,0], [120,80,40,0], [60,20,160,0], [81,69,57,255], [51,39,117,255]),
            (128, [40,20,60,128], [100,60,80,128], [70,30,140,128], [71,59,77,255], [56,44,107,255]),
            (255, [80,40,120,255], [80,40,120,255], [80,40,120,255], [61,49,97,255], [61,49,97,255])]
        var generation: UInt64 = 100
        for (alpha, glyph, left, right, terminalLeft, terminalRight) in samples {
            for projected in [false, true] {
                generation += 1
                let lease = makeLease(requirePlan(value), device: device)
                let command = queue.makeCommandBuffer()!
                let background = SceneFrameTextureResource.sameFrameSceneBackground(
                    consumerLayerID: layerID, frameEpoch: generation, texture: prefix)!
                let preparation = executor.prepare(token: claim.token, leases: [lease],
                    historyRehydrateCopiesByEffect: [:], frame: frame(generation), sceneBackgroundResource: background,
                    sourceTexture: makeSource(device, bgra: glyph), sourceUniforms: .neutral(), sourcePipeline: pipeline,
                    frameInputs: .init(effectOutputModelViewProjection: full,
                        terminalReplayModelViewProjection: projected ? shifted : nil),
                    commandBuffer: command, previousStates: [:], previousGraphResources: [:],
                    effectGeneration: 1, resetGeneration: 1)
                let captured = executor.pairTexture(lease: lease, member: capability.pairPlan.baseCaptureMember)
                guard case let .success(prepared) = preparation,
                      executor.encode(prepared, commandBuffer: command),
                      let captureRead = appendReadback(captured, commandBuffer: command),
                      let effectRead = appendReadback(prepared.finalTexture, commandBuffer: command) else {
                    print("{\"metalAvailable\":true,\"failure\":\"text-source-prepare-or-encode\"}"); return
                }
                let target = makeSource(device, width: 2, height: 2, usage: [.renderTarget, .shaderRead], bgra: [16,32,48,255])
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .load; pass.colorAttachments[0].storeAction = .store
                let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
                var uniforms = SceneLayerFragmentUniforms.neutral(); uniforms.sourceSampling.y = 1
                pipeline.bind(encoder: encoder)
                pipeline.drawLayer(texture: prepared.finalTexture, mvp: full, uniforms: uniforms, encoder: encoder)
                encoder.endEncoding()
                let terminalRead = appendReadback(target, commandBuffer: command)!
                let prefixRead = appendReadback(prefix, commandBuffer: command)!
                command.commit(); command.waitUntilCompleted()
                let key = "pixels-a\(alpha)-projected\(projected)"
                let expectedCapture = projected ? [right,right,right,right] : [left,right,left,right]
                let expectedTerminal = projected ? [terminalRight,terminalRight,terminalRight,terminalRight]
                    : [terminalLeft,terminalRight,terminalLeft,terminalRight]
                let expectedEffect = expectedCapture.map { Array($0.prefix(3)).map { $0 + 26 } + [128] }
                results[key] = command.status == .completed && command.error == nil
                    && captured !== prepared.finalTexture
                    && capability.pairPlan.effects.flatMap(\.nodes).allSatisfy {
                        $0.fullFrameWriteMember != capability.pairPlan.baseCaptureMember
                    }
                    && zip(captureRead.allTexels, expectedCapture).allSatisfy { matches($0.0, $0.1) }
                    && zip(effectRead.allTexels, expectedEffect).allSatisfy { matches($0.0, $0.1) }
                    && zip(terminalRead.allTexels, expectedTerminal).allSatisfy { matches($0.0, $0.1) }
                    && prefixRead.allTexels.flatMap { $0 } == prefixBytes + prefixBytes
                    && prepared.finalResource.publication.candidate.content == .color(.resolved(.straightAlpha))
                    && prepared.stages.allSatisfy { $0.effectLocalFailureReasonCode == nil }
                diagnostics.append(["case": key, "capture": captureRead.allTexels,
                    "effect": effectRead.allTexels, "terminal": terminalRead.allTexels, "expectedCapture": expectedCapture])
            }
        }
        // A preceding effect owns its output; a later RT cannot recapture the
        // original glyph or inject the scene prefix before that earlier effect.
        do {
            generation += 1
            let chain = orderedLayerGraph(prior)
            let owners = capabilities(chain, catalog: sourceColorCatalog(prior), contentKind: "text")
            let claim = owners.claim(chain)!, capability = owners.resolve(claim.token, for: chain)!
            let executor = Executor(device: device, capabilities: owners)!
            let leases = makeChainedLeases(capability, device: device)!
            let command = queue.makeCommandBuffer()!
            let preparation = executor.prepare(token: claim.token, leases: leases,
                historyRehydrateCopiesByEffect: [:], frame: frame(generation),
                sourceTexture: makeSource(device, bgra: [40,20,60,128]), sourceUniforms: .neutral(), sourcePipeline: pipeline,
                frameInputs: .init(), commandBuffer: command,
                previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1)
            guard case let .success(prepared) = preparation, executor.encode(prepared, commandBuffer: command),
                  let read = appendReadback(prepared.finalTexture, commandBuffer: command) else {
                print("{\"metalAvailable\":true,\"failure\":\"isolated-neighbor-prepare\"}"); return
            }
            command.commit(); command.waitUntilCompleted()
            results["prior-effect-output-retained"] = command.status == .completed
                && read.allTexels.allSatisfy { matches($0, [175,215,135,128]) }
                && prepared.stages.allSatisfy { $0.effectLocalFailureReasonCode == nil }
        }
        let failures: [(String, SceneResolvedMaterialPassEncoder.PreparationFailure?)] = [
            ("inactive", nil), ("library", .libraryCompilationRejected(diagnostic: "owned first-RT failure")),
            ("pipeline", .pipelineCompilationRejected(diagnostic: "owned first-RT failure"))]
        for suffix in [false, true] {
            let firstEffect = suffix ? chainedFirstEffect : effect
            let firstOutput = suffix ? chainedFirstOutput : output
            let rt = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID, effect: firstEffect,
                name: "unseen-first-RT-failure")
            var nodes = [material(0, ordinal: 0, target: rt, read: input, owner: firstEffect),
                material(1, ordinal: 1, target: firstOutput, read: rt, owner: firstEffect)]
            var effects = [Graph.Effect(key: firstEffect, definitionPath: "effects/failure-entry/effect.json",
                input: input, output: firstOutput, nodeIndices: [0,1])]
            if suffix {
                nodes.append(material(2, ordinal: 0, target: chainedSecondOutput, read: firstOutput, owner: chainedSecondEffect))
                effects.append(.init(key: chainedSecondEffect, definitionPath: "effects/failure-suffix/effect.json",
                    input: firstOutput, output: chainedSecondOutput, nodeIndices: [2]))
            }
            let graphValue = Graph(layerID: layerID, effects: effects, renderTargets: [rawTarget(rt)],
                nodes: nodes, finalOutput: suffix ? chainedSecondOutput : firstOutput, blockers: [])
            let chain = suffix ? orderedLayerGraph(graphValue) : admittedGraph(graphValue)
            for (mode, injected) in failures {
                generation += 1
                let owners = capabilities(chain, catalog: catalog(for: graphValue,
                    scalarConsumerNodes: [0: "whole", 1: "whole", 2: "whole"]),
                    dynamicProducers: mode == "inactive" ? dynamicProducers : .empty, contentKind: "text")
                let claim = owners.claim(chain)!, capability = owners.resolve(claim.token, for: chain)!
                let executor = Executor(device: device, capabilities: owners)!
                if let injected {
                    let key = capability.material(for: nodes[0])!.variants.launchEnvelopeCapabilitySnapshot()
                        .variants.first!.preparedShader.cacheKey
                    executor.materialEncoder.installTestingPreparationFailure(injected, preparedKey: key)
                }
                let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: generation, generation: generation,
                    definitions: [.init(target: visibility, valueType: .bool, authoredValue: .bool(true))],
                    userValues: [visibility: .bool(mode != "inactive")]).snapshot
                let blackPrefix = makeSource(device, width: 2, height: 2, usage: [.renderTarget, .shaderRead], bgra: [0,0,0,255])
                let background = SceneFrameTextureResource.sameFrameSceneBackground(
                    consumerLayerID: layerID, frameEpoch: generation, texture: blackPrefix)!
                let leases = makeChainedLeases(capability, device: device)!, command = queue.makeCommandBuffer()!
                let preparation = executor.prepare(token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
                    frame: frame(generation), sceneBackgroundResource: background,
                    sourceTexture: makeSource(device, bgra: [128,128,128,128]), sourceUniforms: .neutral(), sourcePipeline: pipeline,
                    frameInputs: .init(dynamicValues: dynamic, effectOutputModelViewProjection: full),
                    commandBuffer: command, previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1)
                var entryRead: Readback?
                guard case let .success(prepared) = preparation else {
                    print(String(decoding: try JSONSerialization.data(withJSONObject: ["metalAvailable": true,
                        "failure": "first-RT-passthrough-prepare", "mode": mode, "hasSuffix": suffix,
                        "phase": "prepare", "failureCode": failureCode(preparation)], options: [.sortedKeys]), as: UTF8.self)); return
                }
                let encoded = executor.encode(prepared, commandBuffer: command, stageBoundaryObserver: { index, stage, buffer in
                    if index == 0 { entryRead = appendReadback(stage.effectOutputResource.publication.texture, commandBuffer: buffer) }
                    return true
                })
                guard encoded, let entryRead, let finalRead = appendReadback(prepared.finalTexture, commandBuffer: command) else {
                    print(String(decoding: try JSONSerialization.data(withJSONObject: ["metalAvailable": true,
                        "failure": "first-RT-passthrough-prepare", "mode": mode, "hasSuffix": suffix,
                        "phase": encoded ? "readback" : "encode", "failureCode": failureCode(preparation)], options: [.sortedKeys]), as: UTF8.self)); return
                }
                let finalStraight = prepared.finalResource.publication.candidate.content == .color(.resolved(.straightAlpha))
                let target = makeSource(device, width: 2, height: 2, usage: [.renderTarget, .shaderRead], bgra: [0,0,0,255])
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .load; pass.colorAttachments[0].storeAction = .store
                let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
                var uniforms = SceneLayerFragmentUniforms.neutral(); uniforms.sourceSampling.y = finalStraight ? 1 : 0
                pipeline.bind(encoder: encoder)
                pipeline.drawLayer(texture: prepared.finalTexture, mvp: full, uniforms: uniforms, encoder: encoder)
                encoder.endEncoding()
                let terminalRead = appendReadback(target, commandBuffer: command)!
                command.commit(); command.waitUntilCompleted()
                let firstStage = prepared.stages[0], key = "first-RT-\(mode)-suffix\(suffix)"
                results[key] = command.status == .completed && command.error == nil
                    && capability.sceneBackgroundRequirement?.capturesTextSourcePrefixRGB == true
                    && firstStage.effectOutputResource.publication.candidate.content == .color(.resolved(.premultipliedAlpha))
                    && entryRead.allTexels.allSatisfy { matches($0, [128,128,128,128]) }
                    && finalStraight == suffix
                    && finalRead.allTexels.allSatisfy { matches($0, suffix ? [255,255,255,128] : [128,128,128,128]) }
                    && terminalRead.allTexels.allSatisfy { matches($0, [128,128,128,255]) }
                    && (mode == "inactive"
                        ? firstStage.effectLocalActivationBypassReasonCode == "effect-activation-visibility-disabled"
                        : firstStage.effectLocalFailureReasonCode == "material-pass-preparation-" + injected!.code)
                    && (!suffix || prepared.stages[1].effectLocalFailureReasonCode == nil)
                diagnostics.append(["case": key, "entry": entryRead.allTexels, "final": finalRead.allTexels,
                    "terminal": terminalRead.allTexels, "finalStraight": finalStraight])
            }
        }
        let resourceEncoder = SceneGraphResourcePassEncoder(commandQueue: queue)
        let floatPipeline = try sourceColorPipeline(device, format: .rgba16Float)
        func floatTexture(_ texels: [[Float]], width: Int) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: width, height: texels.count / width, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
            let texture = device.makeTexture(descriptor: descriptor)!
            let bytes = texels.flatMap { $0 }.map { Float16($0).bitPattern }
            texture.replace(region: .init(origin: .init(), size: .init(width: width, height: texels.count / width, depth: 1)),
                mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 8)
            return texture
        }
        let hdrPrefix = floatTexture([[2,0.4,0.2,0], [2,0.4,0.2,0], [0.25,1.5,3,1], [0.25,1.5,3,1]], width: 4)
        let hdrSamples: [(Float, [Float], [[Float]])] = [
            (0, [0,0,0,0], [[2,0.4,0.2,0], [0.25,1.5,3,0]]),
            (0.5, [0.3,0.1,0.2,0.5], [[1.3,0.3,0.3,0.5], [0.425,0.85,1.7,0.5]])]
        for (alpha, glyph, expected) in hdrSamples {
            let target = floatTexture([[0,0,0,0], [0,0,0,0]], width: 2)
            let prepared = resourceEncoder.prepareSourceCapture(source: floatTexture([glyph], width: 1),
                target: target, uniforms: .neutral(), pipeline: floatPipeline, prefix: (hdrPrefix, full))!
            let command = queue.makeCommandBuffer()!
            let encoded = resourceEncoder.encode(prepared, commandBuffer: command)
            command.commit(); command.waitUntilCompleted()
            var bytes = [UInt16](repeating: 0, count: 8)
            target.getBytes(&bytes, bytesPerRow: 16, from: .init(origin: .init(), size: .init(width: 2, height: 1, depth: 1)), mipmapLevel: 0)
            let actual = bytes.map { Float(Float16(bitPattern: $0)) }
            results["hdr-prefix-a\(alpha)"] = encoded && command.status == .completed
                && prepared.preservesStraightSourceColor
                && zip(actual, expected.flatMap { $0 }).allSatisfy { abs($0.0 - $0.1) < 0.005 }
            diagnostics.append(["case": "hdr-prefix-a\(alpha)", "actual": actual, "expected": expected])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["metalAvailable": true, "results": results, "diagnostics": diagnostics], options: [.sortedKeys]), as: UTF8.self))
    }
}
'''
        compilation, completed = compile_lit_harness(SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertNotIn("failure", payload, payload)
        self.assertEqual(len(payload["results"]), 25)
        self.assertEqual([name for name, passed in payload["results"].items() if not passed], [], payload)

    def test_actual_source_capture_alpha_override_and_terminal_composition(self) -> None:
        harness = HARNESS_SUPPORT_SOURCE + r'''
@main private enum SourceCaptureContinuityHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let capturePipeline = makeProductionSourcePipeline(device),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "sceneImageLayerVert") else {
            print("{\"metalAvailable\":false}"); return
        }
        let value = graph(targets: [], nodes: [material(0, ordinal: 0, target: output, read: input)])
        let original = template(for: value.nodes[0])
        let contract = shaderContract(nodeIndex: 0, pass: false, fragmentOverride: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            vec4 color = texSample2D(g_Texture0, v_TexCoord);
            color.a = 0.5;
            gl_FragColor = color;
        }
        """)
        let sourceTemplate = Template.validated(textureSlots: original.textureSlots, combos: [],
            uniformDeclarations: [], renderState: original.renderState, graphRole: original.graphRole,
            effectContext: .init(key: effect, input: input), shaderContract: contract,
            diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: contract.identity,
                contractIdentity: contract.identity, contractCanonicalSHA256: contract.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        let chain = admittedGraph(value)
        let owners = capabilities(chain, catalog: .init(entries: [
            .init(effect: effect, nodeIndex: 0): .template(sourceTemplate, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: sourceTemplate))
        ], resourceDemandIssues: []))
        guard let claim = owners.claim(chain), let capability = owners.resolve(claim.token, for: chain),
              let material = capability.material(for: value.nodes[0]),
              let executor = Executor(device: device, capabilities: owners) else {
            print("{\"failure\":\"source-capture-admission\",\"metalAvailable\":true}"); return
        }
        let lease = makeLease(requirePlan(value), device: device)
        let preparedKey = material.variants.launchEnvelopeCapabilitySnapshot().variants.first!.preparedShader.cacheKey
        let tint = SIMD3<Float>(0.5, 0.25, 0.75)
        let authoredBGRA: [UInt8] = [51, 102, 204, 255]
        let background: [UInt8] = [32, 64, 96, 51]
        var rows: [[String: Any]] = [], index: UInt64 = 0, key: String?
        var frontendCount = 0, libraryCount = 0
        func byte(_ value: Float) -> UInt8 { UInt8(clamping: Int((value * 255).rounded())) }
        for straight in [false, true] {
            for alphaByte: UInt8 in [0, 128, 255] {
                for opacity: Float in [0, 0.4, 1] {
                    index += 1
                    let sourceAlpha = Float(alphaByte) / 255
                    var sourceBGRA = authoredBGRA
                    sourceBGRA[3] = alphaByte
                    if !straight { for channel in 0..<3 {
                        sourceBGRA[channel] = byte(Float(authoredBGRA[channel]) / 255 * sourceAlpha)
                    } }
                    var uniforms = SceneLayerFragmentUniforms.neutral()
                    uniforms.sourceSampling.y = straight ? 1 : 0
                    uniforms.alpha = opacity; uniforms.tint = SIMD4(tint, 1)
                    let source = makeSource(device, bgra: sourceBGRA)
                    let snapshot = frame(index)
                    // The existing local-failure passthrough publishes the
                    // actual base atom. The stage's FBO map is post-rotation
                    // and intentionally does not expose the original capture.
                    executor.materialEncoder.installTestingPreparationFailure(
                        .libraryCompilationRejected(diagnostic: "owned source capture observation"), preparedKey: preparedKey)
                    let captureCommand = queue.makeCommandBuffer()!
                    let capturePreparation = executor.prepare(token: claim.token, leases: [lease],
                        historyRehydrateCopiesByEffect: [:], frame: snapshot, sourceTexture: source,
                        sourceUniforms: uniforms, sourcePipeline: capturePipeline, frameInputs: .init(),
                        commandBuffer: captureCommand, previousStates: [:], previousGraphResources: [:],
                        effectGeneration: 1, resetGeneration: 1)
                    guard case let .success(captured) = capturePreparation,
                          let base = captured.finalResource.rewrappedForGraphIdentity(input),
                          executor.encode(captured, commandBuffer: captureCommand),
                          let baseRead = appendReadback(captured.finalTexture, commandBuffer: captureCommand) else {
                        print(String(decoding: try JSONSerialization.data(withJSONObject:
                            ["metalAvailable": true, "failure": "capture-observation-" + failureCode(capturePreparation)],
                            options: [.sortedKeys]), as: UTF8.self)); return
                    }
                    captureCommand.commit(); captureCommand.waitUntilCompleted()
                    executor.materialEncoder.testingPreparationFailuresByPreparedKey.removeValue(forKey: preparedKey)
                    let command = queue.makeCommandBuffer()!
                    let preparation = executor.prepare(token: claim.token, leases: [lease],
                        historyRehydrateCopiesByEffect: [:], frame: snapshot, sourceTexture: source,
                        sourceUniforms: uniforms, sourcePipeline: capturePipeline, frameInputs: .init(),
                        commandBuffer: command, previousStates: [:], previousGraphResources: [:],
                        effectGeneration: 1, resetGeneration: 1)
                    guard case let .success(prepared) = preparation,
                          let overlaid = snapshot.overlayingGraphResources([input: base]),
                          case let .success(program) = SceneResolvedMaterialProgramFinalizer.finalize(
                            overlaid.finalizationInput(layerID: layerID,
                                renderSize: CGSize(width: extent.width, height: extent.height),
                                modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
                                effectOutputModelViewProjection: matrix_identity_float4x4,
                                effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                                implicitFramebufferIdentity: input), variantCache: material.variants),
                          executor.encode(prepared, commandBuffer: command),
                          let effectRead = appendReadback(prepared.finalTexture, commandBuffer: command) else {
                        print(String(decoding: try JSONSerialization.data(withJSONObject:
                            ["metalAvailable": true, "failure": failureCode(preparation)], options: [.sortedKeys]), as: UTF8.self)); return
                    }
                    var expectedBase = [UInt8](repeating: 0, count: 4)
                    let bgraTint = [tint.z, tint.y, tint.x]
                    for channel in 0..<3 {
                        expectedBase[channel] = byte(Float(sourceBGRA[channel]) / 255 * bgraTint[channel] * (straight ? 1 : opacity))
                    }
                    expectedBase[3] = byte(sourceAlpha * opacity)
                    let expectedEffect: [UInt8] = (0..<3).map { channel in
                        straight ? expectedBase[channel] : expectedBase[3] == 0 ? 0
                            : byte(Float(expectedBase[channel]) / Float(expectedBase[3]))
                    } + [128]
                    var composedReads: [(Bool, Readback)] = []
                    for additive in [false, true] {
                        let constants = MTLFunctionConstantValues()
                        var weightsSourceAlpha = additive
                        constants.setConstantValue(&weightsSourceAlpha, type: .bool, index: 0)
                        let descriptor = MTLRenderPipelineDescriptor()
                        descriptor.vertexFunction = vertex
                        descriptor.fragmentFunction = try library.makeFunction(name: "sceneImageLayerFrag", constantValues: constants)
                        let color = descriptor.colorAttachments[0]!
                        color.pixelFormat = .bgra8Unorm; color.isBlendingEnabled = true
                        color.sourceRGBBlendFactor = .one
                        color.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
                        color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                        let pipeline = SceneImageLayerPipeline(state: try device.makeRenderPipelineState(descriptor: descriptor))
                        let target = makeSource(device, usage: [.renderTarget, .shaderRead], bgra: background)
                        let pass = MTLRenderPassDescriptor()
                        pass.colorAttachments[0].texture = target
                        pass.colorAttachments[0].loadAction = .load; pass.colorAttachments[0].storeAction = .store
                        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
                        var finalUniforms = SceneLayerFragmentUniforms.neutral()
                        finalUniforms.sourceSampling.y = 1; finalUniforms.alpha = 0.6
                        pipeline.bind(encoder: encoder)
                        pipeline.drawLayer(texture: prepared.finalTexture, mvp: simd_float4x4(diagonal: SIMD4(2, 2, 1, 1)),
                            uniforms: finalUniforms, encoder: encoder)
                        encoder.endEncoding()
                        composedReads.append((additive, appendReadback(target, commandBuffer: command)!))
                    }
                    command.commit(); command.waitUntilCompleted()
                    if index == 1 { key = prepared.stages[0].programCacheKeys.first
                        frontendCount = material.variants.counters.frontendCompilationCount
                        libraryCount = executor.materialEncoder.metalLibraryCompilationAttemptCount }
                    let mask = zip(program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms).first { $0.0.field.name == "mwxPremultipliedColorInputMask" }
                        .map { $0.1.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
                    for (additive, read) in composedReads {
                        let effectAlpha: Float = 128 / 255, finalAlpha = effectAlpha * 0.6
                        var expectedComposite = (0..<3).map { channel in byte(
                            Float(expectedEffect[channel]) / 255 * finalAlpha * (additive ? effectAlpha : 1)
                                + Float(background[channel]) / 255 * (additive ? 1 : 1 - finalAlpha)) }
                        expectedComposite.append(byte(finalAlpha + Float(background[3]) / 255 * (1 - finalAlpha)))
                        rows.append(["straight": straight, "sourceAlpha": alphaByte, "sourceOpacity": opacity, "additive": additive,
                            "completed": command.status == .completed && command.error == nil,
                            "captureCompleted": captureCommand.status == .completed && captureCommand.error == nil
                                && captured.stages[0].effectLocalFailureReasonCode == "material-pass-preparation-library-compilation",
                            "capturePixels": matches(baseRead.firstPixel, expectedBase) && matches(baseRead.lastPixel, expectedBase),
                            "capturePublication": base.publication.candidate.content == .color(.resolved(straight ? .straightAlpha : .premultipliedAlpha))
                                && base.publication.candidate.purpose == (straight ? .straightAlbedo : .premultipliedColor),
                            "effectPixels": matches(effectRead.firstPixel, expectedEffect) && matches(effectRead.lastPixel, expectedEffect),
                            "effectPublication": prepared.finalResource.publication.candidate.content == .color(.resolved(.straightAlpha)),
                            "terminalPixels": matches(read.firstPixel, expectedComposite) && matches(read.lastPixel, expectedComposite),
                            "mask": mask ?? 999, "actualInputMask": mask == (straight ? 0 : 1),
                            "samePreparedProgram": key == prepared.stages[0].programCacheKeys.first,
                            "noRepresentationRecompile": frontendCount == material.variants.counters.frontendCompilationCount
                                && libraryCount == executor.materialEncoder.metalLibraryCompilationAttemptCount,
                            "noVisualFallback": prepared.stages[0].effectLocalFailureReasonCode == nil,
                            "basePixel": baseRead.firstPixel, "effectPixel": effectRead.firstPixel, "terminalPixel": read.firstPixel,
                            "expectedBase": expectedBase, "expectedEffect": expectedEffect, "expectedTerminal": expectedComposite])
                    }
                }
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["metalAvailable": true, "cases": rows], options: [.sortedKeys]), as: UTF8.self))
    }
}
'''
        compilation, completed = compile_lit_harness(SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertNotIn("failure", payload, payload)
        self.assertEqual(len(payload["cases"]), 36)
        for case in payload["cases"]:
            for name, passed in case.items():
                if isinstance(passed, bool) and name not in {"straight", "additive"}:
                    self.assertTrue(passed, (name, case))


if __name__ == "__main__":
    unittest.main()
