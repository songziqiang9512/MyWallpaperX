#!/usr/bin/env python3
"""Effect draw alpha through the existing material preparation/Metal harnesses."""

from __future__ import annotations

import json
import shutil
import unittest

from script.tests import test_scene_resolved_material_graph_executor as graph_fixture
from script.tests import test_scene_resolved_material_program_finalizer as finalizer_fixture


def runtime_frame_support() -> str:
    """Use the real typed input/copy implementation within the existing graph fixture."""
    source = (finalizer_fixture.SCENE_ROOT / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift").read_text()
    frame = source.split("    struct FrameInputs {", 1)[1].split("\n    enum FramePreparationResult", 1)[0]
    support = graph_fixture.SUPPORT
    start = support.index("final class SceneResolvedMaterialRuntimeBridge {")
    end = support.index("\nstruct SceneDependencyEffectInput", start)
    replacement = "struct SceneAudioSpectrumSnapshot { static let silent = Self() }\n"
    replacement += "final class SceneResolvedMaterialRuntimeBridge {\n    struct FrameInputs {" + frame + "\n}\n"
    replacement += r'''
extension SceneResolvedMaterialRuntimeBridge.FrameInputs {
    init(dependencyEffects: [SceneDependencyEffectInput] = [],
        dependencyUnavailability: DependencyUnavailability? = nil,
        dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        pointerIsInside: Bool = true, effectDrawAlpha: Float = 1) {
        self.init(dynamicValues: dynamicValues, cursorUV: .zero, previousCursorUV: .zero,
            pointerIsInside: pointerIsInside, previousPointerIsInside: pointerIsInside,
            pointerMovement: 0, primaryButtonIsDown: false,
            layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            effectDrawAlpha: effectDrawAlpha, frameTime: 1 / 60, time: 0,
            audioSpectrum: .silent, dependencyEffects: dependencyEffects,
            dependencyUnavailability: dependencyUnavailability)
    }
}
'''
    return support[:start] + replacement + support[end:]


CPU_HARNESS = finalizer_fixture.HARNESS.split("@main\nprivate enum Harness", 1)[0] + r'''
private enum Harness {
    static func float(_ data: Data, at offset: Int) -> Float {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
    }
}

private func alphaShader() -> SceneShaderContract {
    contract(revision: "self-owned-draw-alpha", vertexSourceOverride: """
        attribute vec3 a_Position;
        uniform mat4 g_ModelViewProjectionMatrix;
        void main() { gl_Position = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0); }
        """, fragmentSourceOverride: """
        uniform float g_Alpha; // {"material":"g_Alpha","default":0.75}
        void main() { gl_FragColor = vec4(g_Alpha, g_Alpha, g_Alpha, 1.0); }
        """)
}

private func preparedDrawAlpha(effect: Bool,
    type: SceneAuthoredShaderValueType = .float, arrayCount: Int? = nil,
    declarations: [Template.UniformDeclaration] = []) throws -> SceneResolvedMaterialPreparedUniformBinding {
    let context: Template.EffectContext? = effect ? .init(
        key: .init(layerID: 42, effectIndex: 0, descriptorID: "self-owned-alpha"),
        input: graphTexture()) : nil
    let material = template(alphaShader(), includePrimaryCandidate: false,
        uniformDeclarations: declarations, effectContext: context)
    let field = SceneAuthoredShaderUniformLayout.Field(name: "g_Alpha", type: type,
        arrayCount: arrayCount, offset: 0)
    return try SceneResolvedMaterialProgramFinalizer.prepareUniformBindings(
        template: material, fields: [field], activeUniforms: ["g_Alpha": .init(
            name: "g_Alpha", materialKeys: ["g_Alpha"],
            defaultValue: staticValue([0.75]), authoredRange: nil)],
        activeTextureSlots: [], neutralTextureResolution: nil)[0]
}

private func rejection(_ body: () throws -> SceneResolvedMaterialPreparedUniformBinding) -> String {
    do { _ = try body(); return "accepted" }
    catch let failure as SceneResolvedMaterialFailure { return failure.code.rawValue }
    catch { return "unexpected" }
}

private func assembly(effect: Bool, source: Program.ResolvedUniform.Source,
    alpha: Float = 0.25) -> Program? {
    guard let shader = prepared(alphaShader()),
          let frontend = SceneAuthoredShaderFrontend.compile(vertexSource: shader.vertex.source,
            fragmentSource: shader.fragment.source).program else { return nil }
    let slots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    var values: [Program.ResolvedUniform] = []
    for field in frontend.uniformLayout.fields {
        if field.authoredName == "g_Alpha" {
            guard let encoded = SceneResolvedMaterialUniformEncoder.encode(
                staticValue([Double(alpha)]), as: field.type) else { return nil }
            values.append(.init(field: field, source: source, encodedValue: encoded))
        } else {
            guard let host = SceneResolvedMaterialHostUniformSchema.resolve(field,
                activeTextureSlots: [], hasEffectContext: effect),
                let encoded = SceneResolvedMaterialUniformEncoder.encodeHost(host,
                    type: field.type, inputs: uniformInputs(), slots: slots) else { return nil }
            values.append(.init(field: field, source: .host(host), encodedValue: encoded))
        }
    }
    return Program.assemble(.init(preparedShader: shader,
        textureSlots: slots, resolvedUniforms: values,
        renderState: state(), graphRole: template(alphaShader(), includePrimaryCandidate: false).graphRole,
        hasEffectContext: effect))
}

private func variantAliasScope(effect: Bool) -> String {
    let shader = contract(revision: "self-owned-draw-alpha-alias", fragmentSourceOverride: """
        uniform float g_Alpha; // {"material":"gain","default":0.75}
        uniform float gain; // {"default":1}
        void main() { gl_FragColor = vec4(g_Alpha, gain, 0.0, 1.0); }
        """)
    let context: Template.EffectContext? = effect ? .init(
        key: .init(layerID: fixtureLayerID, effectIndex: 0, descriptorID: "self-owned-alpha"),
        input: graphTexture()) : nil
    let material = template(shader, includePrimaryCandidate: false, effectContext: context)
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: material, maximumVariantCount: 4) else { return "launch-failed" }
    switch cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil) {
    case .success:
        let variants = cache.launchEnvelopeCapabilitySnapshot().variants
        guard let bindings = variants.first?.preparedUniformBindings,
              let alpha = bindings.first(where: { $0.field.authoredName == "g_Alpha" }),
              let gain = bindings.first(where: { $0.field.authoredName == "gain" }),
              case .host(.effectDrawAlpha) = alpha.source,
              case .staticValue = gain.source else { return "wrong-ownership" }
        return "effect-host-and-authored-gain"
    case let .failure(.material(error)): return error.code.rawValue
    case .failure(.capacity): return "capacity"
    }
}

@main private enum EffectDrawAlphaPreparationHarness {
    static func main() throws {
        let effect = try preparedDrawAlpha(effect: true)
        let source = try preparedDrawAlpha(effect: false)
        let effectIsHost: Bool
        if case .host(.effectDrawAlpha) = effect.source { effectIsHost = true } else { effectIsHost = false }
        let sourceIsStatic: Bool
        if case .staticValue = source.source { sourceIsStatic = true } else { sourceIsStatic = false }
        let declared = staticDeclaration("g_Alpha", components: [0.125])
        let sourceDeclared = try preparedDrawAlpha(effect: false, declarations: [declared])
        let target = SceneDynamicTarget.effectConstant(layerID: fixtureLayerID,
            effectIndex: 0, passIndex: 0, name: "g_Alpha")
        let dynamic = Template.UniformDeclaration(name: "g_Alpha", value: .dynamic(.init(
            target: target, valueContributors: [.timeline], scriptAttachments: [],
            authoredFallback: staticValue([0.3]), authoredBindingKeys: ["value"])))
        let sourceDynamic = try preparedDrawAlpha(effect: false, declarations: [dynamic])
        var sourceStaticOwned = false, sourceDynamicOwned = false
        if case .staticValue = sourceDeclared.source { sourceStaticOwned = true }
        if case .dynamic = sourceDynamic.source { sourceDynamicOwned = true }
        let first = assembly(effect: true, source: .host(.effectDrawAlpha))
        let second = assembly(effect: true, source: .host(.effectDrawAlpha), alpha: 0.5)
        let replay = first?.terminalReplay(unitModelViewProjection: matrix_identity_float4x4)
        let inputs = SceneAuthoredShaderUniformInputs(frameIndex: 1, renderSize: CGSize(width: 2, height: 2),
            screenSize: CGSize(width: 2, height: 2), modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            effectDrawAlpha: .nan, sceneTime: 0, dayTime: 0, frameTime: 1 / 60,
            pointerCurrentNDC: .zero, pointerPreviousNDC: .zero, texturePhysicalSizes: [:])
        let copied = SceneResolvedMaterialRuntimeBridge.FrameInputs(effectDrawAlpha: 0.25)
            .withDependencyEffects([])
        let output: [String: Any] = [
            "effectIsHost": effectIsHost, "sourceIsStatic": sourceIsStatic,
            "sourceStaticOwned": sourceStaticOwned, "sourceDynamicOwned": sourceDynamicOwned,
            "effectStaticConflict": rejection { try preparedDrawAlpha(effect: true, declarations: [declared]) },
            "effectDynamicConflict": rejection { try preparedDrawAlpha(effect: true, declarations: [dynamic]) },
            "wrongScalar": rejection { try preparedDrawAlpha(effect: true, type: .int) },
            "wrongVector": rejection { try preparedDrawAlpha(effect: true, type: .float2) },
            "array": rejection { try preparedDrawAlpha(effect: true, arrayCount: 2) },
            "hostAssembly": first != nil,
            "sourceHostRejected": assembly(effect: false, source: .host(.effectDrawAlpha)) == nil,
            "effectStaticRejected": assembly(effect: true, source: .staticValue) == nil,
            "sourceStaticAssembly": assembly(effect: false, source: .staticValue) != nil,
            "wrongHostRejected": assembly(effect: true, source: .host(.time)) == nil,
            "identityStable": first != nil && second != nil && first!.semanticIdentity == second!.semanticIdentity,
            "exactBytesChanged": first != nil && second != nil && first!.exactIdentity != second!.exactIdentity,
            "terminalAlphaPreserved": replay != nil && replay!.resolvedUniforms.contains {
                if case .host(.effectDrawAlpha) = $0.source {
                    return Harness.float($0.encodedValue, at: 0) == 0.25
                }
                return false
            },
            "nonFiniteRejected": SceneResolvedMaterialUniformEncoder.encodeHost(.effectDrawAlpha,
                type: .float, inputs: inputs, slots: Array(repeating: nil, count: 8)) == nil,
            "copiedAlpha": copied.effectDrawAlpha,
            "effectAliasVariant": variantAliasScope(effect: true),
            "sourceAliasVariant": variantAliasScope(effect: false),
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
            encoding: .utf8)!)
    }
}
'''


METAL_HARNESS = graph_fixture.HARNESS.split("@main\nprivate enum Harness", 1)[0] + r'''
private func drawAlphaFrames(device: MTLDevice, queue: MTLCommandQueue) -> [String: Any] {
    let provider = SceneNamedTextureReference(providerLayerID: 879, variant: .primary)
    let node = material(0, ordinal: 0, target: output, read: input)
    let value = graph(targets: [], nodes: [node])
    let base = template(for: node, namedProvider: provider)
    let shader = shaderContract(nodeIndex: 0, pass: false, fragmentOverride: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture1;
        uniform float g_Alpha;
        void main() {
            vec4 provider = texSample2D(g_Texture1, v_TexCoord);
            gl_FragColor = vec4(g_Alpha, provider.a, provider.r, 1.0);
        }
        """)
    let materialTemplate = Template.validated(textureSlots: base.textureSlots, combos: [],
        uniformDeclarations: [], renderState: base.renderState, graphRole: base.graphRole,
        effectContext: .init(key: effect, input: input), shaderContract: shader,
        diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: shader.identity,
            contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [], uniformSources: []))!
    let materials = SceneResolvedMaterialRuntimeCatalog(entries: [
        .init(effect: effect, nodeIndex: 0): .template(materialTemplate)
    ], resourceDemandIssues: [])
    let dependency = SceneDependencyRenderPlan.Binding(consumerLayerID: layerID,
        providerLayerID: provider.providerLayerID,
        slot: .init(effectID: effect.descriptorID, passIndex: 0, slotIndex: 1),
        blendMode: 0, kind: .resolvedMaterial)
    let chain = admittedGraph(value)
    let facts = capabilities(chain, catalog: materials, namedProvider: provider,
        dependencyBinding: dependency)
    guard let claim = facts.claim(chain), let capability = facts.resolve(claim.token, for: chain),
          let leases = makeChainedLeases(capability, device: device),
          let selected = capability.material(for: node),
          let executor = Executor(device: device, capabilities: facts) else {
        return ["failure": "setup", "reports": facts.reportLines]
    }
    let sourcePipeline = makeSourcePipeline(device)
    let providerTexture = makeSource(device, width: 2, height: 2,
        usage: [.renderTarget, .shaderRead], bgra: [77, 179, 51, 191])
    var rows: [[String: Any]] = []
    var states: [Graph.EffectKey: Executor.State] = [:]
    var resources: [Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]] = [:]
    var key: String?, frontendCount = 0, libraryCount = 0
    for (offset, alpha) in [Float(0.25), 0.5, 1].enumerated() {
        let index = UInt64(offset + 1)
        let snapshot = frame(index)
        guard let providerResource = SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: provider, frameEpoch: index, texture: providerTexture,
            content: .color(.resolved(.straightAlpha))) else { return ["failure": "provider"] }
        let inputFrame = SceneResolvedMaterialRuntimeBridge.FrameInputs(effectDrawAlpha: alpha)
            .withDependencyEffects([.init(consumerLayerID: layerID,
                providerLayerID: provider.providerLayerID, slot: dependency.slot,
                frameEpoch: index, texture: providerTexture,
                content: providerResource.publication.candidate.content,
                namedReference: provider, reservedMaterialResource: providerResource)])
        var sourceUniforms = SceneLayerFragmentUniforms.neutral()
        sourceUniforms.alpha = 0.625
        let command = queue.makeCommandBuffer()!
        let result = executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: snapshot,
            sourceTexture: makeSource(device, width: 2, height: 2, bgra: [26, 51, 102, 128]),
            sourceUniforms: sourceUniforms, sourcePipeline: sourcePipeline, frameInputs: inputFrame,
            commandBuffer: command, previousStates: states, previousGraphResources: resources,
            effectGeneration: 1, resetGeneration: 1)
        guard case let .success(prepared) = result, prepared.stages.count == 1,
              executor.encode(prepared, commandBuffer: command),
              let read = appendReadback(prepared.finalResource.publication.texture,
                commandBuffer: command) else {
            return ["failure": failureCode(result), "frames": rows]
        }
        command.commit(); command.waitUntilCompleted()
        let stage = prepared.stages[0]
        if offset == 0 {
            key = stage.programCacheKeys.first
            frontendCount = selected.variants.counters.frontendCompilationCount
            libraryCount = executor.materialEncoder.metalLibraryCompilationAttemptCount
        }
        let expected: [UInt8] = [51, 191, UInt8((alpha * 255).rounded()), 255]
        rows.append(["alpha": alpha, "pixel": read.firstPixel, "expected": expected,
            "gpuCompleted": command.status == .completed && command.error == nil,
            "consumerProviderIndependent": matches(read.firstPixel, expected)
                && matches(read.lastPixel, expected),
            "copyPreservedAlpha": inputFrame.effectDrawAlpha == alpha,
            "samePreparedProgram": key != nil && key == stage.programCacheKeys.first,
            "noRecompile": frontendCount == selected.variants.counters.frontendCompilationCount
                && libraryCount == executor.materialEncoder.metalLibraryCompilationAttemptCount,
            "noLocalFallback": stage.effectLocalFailureReasonCode == nil,
            "opaqueOutput": prepared.finalResource.publication.candidate.content == .color(.resolved(.opaque))])
        states = [stage.effect: stage.transition.nextState]
        resources = [stage.effect: stage.persistentResources]
    }
    return ["frames": rows]
}

@main private enum EffectDrawAlphaMetalHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"skip\":\"Metal unavailable\"}"); return
        }
        let result = drawAlphaFrames(device: device, queue: queue)
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
            encoding: .utf8)!)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneEffectDrawAlphaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        compiled, completed = graph_fixture.compile_harness(
            runtime_frame_support(), CPU_HARNESS,
            additional_sources=[
                finalizer_fixture.SCENE_ROOT / "Compilation/ShaderContract/SceneShaderContractLoader.swift",
                finalizer_fixture.SCENE_ROOT / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift",
            ],
        )
        if compiled.returncode != 0 or completed is None or completed.returncode != 0:
            raise AssertionError(compiled.stderr + (completed.stderr + completed.stdout if completed else ""))
        cls.result = json.loads(completed.stdout)
        print("CPU " + completed.stdout.strip())

    def test_effect_scope_takes_host_alpha_and_source_keeps_authored_default(self) -> None:
        result = self.result
        self.assertTrue(result["sourceIsStatic"], result)
        self.assertTrue(result["effectIsHost"], result)

    def test_source_static_dynamic_and_effect_conflicts(self) -> None:
        for key in ("sourceStaticOwned", "sourceDynamicOwned"):
            self.assertTrue(self.result[key], self.result)
        for key in ("effectStaticConflict", "effectDynamicConflict"):
            self.assertEqual(self.result[key], "hostUniformDeclarationConflict", self.result)

    def test_effect_requires_nonarray_float(self) -> None:
        for key in ("wrongScalar", "wrongVector", "array"):
            self.assertEqual(self.result[key], "staticUniformBindingInvalid", self.result)

    def test_variant_schema_filter_shares_effect_scope(self) -> None:
        self.assertEqual(self.result["effectAliasVariant"], "effect-host-and-authored-gain", self.result)
        self.assertEqual(self.result["sourceAliasVariant"], "uniformBindingInvalid", self.result)

    def test_program_identity_rechecks_scope(self) -> None:
        for key in ("hostAssembly", "sourceHostRejected", "effectStaticRejected", "sourceStaticAssembly",
                    "wrongHostRejected", "identityStable", "exactBytesChanged", "terminalAlphaPreserved"):
            self.assertTrue(self.result[key], self.result)

    def test_nonfinite_rejection_and_dependency_copy(self) -> None:
        self.assertTrue(self.result["nonFiniteRejected"], self.result)
        self.assertEqual(self.result["copiedAlpha"], 0.25, self.result)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneEffectDrawAlphaMetalTests(unittest.TestCase):
    def test_actual_graph_consumer_alpha_is_independent_across_frames(self) -> None:
        compiled, completed = graph_fixture.compile_harness(runtime_frame_support(), METAL_HARNESS)
        self.assertEqual(compiled.returncode, 0, compiled.stderr)
        self.assertIsNotNone(completed)
        self.assertEqual(completed.returncode, 0, completed.stderr or completed.stdout)
        result = json.loads(completed.stdout)
        print("Metal " + completed.stdout.strip())
        if "skip" in result:
            self.skipTest(result["skip"])
        self.assertNotIn("failure", result, result)
        self.assertEqual(len(result["frames"]), 3, result)
        for row in result["frames"]:
            for key in ("gpuCompleted", "consumerProviderIndependent", "copyPreservedAlpha",
                        "samePreparedProgram", "noRecompile", "noLocalFallback", "opaqueOutput"):
                self.assertTrue(row[key], result)


if __name__ == "__main__":
    unittest.main()
