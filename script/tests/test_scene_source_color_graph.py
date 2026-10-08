#!/usr/bin/env python3
"""Source capture to authored alpha expansion through the existing graph harness."""
import json
import shutil
import unittest

from script.tests.test_scene_resolved_material_graph_executor import HARNESS, SUPPORT, compile_lit_harness


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSourceColorGraphTests(unittest.TestCase):
    def test_actual_source_capture_alpha_override_and_terminal_composition(self) -> None:
        harness = HARNESS.split("@main\nprivate enum Harness", 1)[0] + r'''
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
            .init(effect: effect, nodeIndex: 0): .template(sourceTemplate)
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
                            overlaid.finalizationInput(template: material.template, layerID: layerID,
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
                    let mask = program.resolvedUniforms.first { $0.field.name == "mwxPremultipliedColorInputMask" }
                        .map { $0.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
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
