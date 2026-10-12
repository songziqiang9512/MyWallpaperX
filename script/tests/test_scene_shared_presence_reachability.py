#!/usr/bin/env python3
"""Self-authored launch hypotheses preserve shared presence consensus."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_sampler_default_purpose import REPOSITORY_ROOT, SCENE_ROOT, SUPPORT, SWIFT_SOURCES


HARNESS = r'''
import Foundation
import Metal

private typealias Template = SceneResolvedMaterialTemplate

private func contract(_ identity: String, _ fragment: String, varyingName: String = "uv") -> SceneShaderContract {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 \(varyingName);
    void main() { \(varyingName) = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
    """
    func stage(_ kind: SceneShaderContract.StageKind, _ source: String) -> SceneShaderContract.Stage {
        let path = "self-authored/\(identity).\(kind == .vertex ? "vert" : "frag")"
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
        return .init(kind: kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes, annotations: parsed.annotations,
            declarations: parsed.declarations)
    }
    let stages = [stage(.vertex, vertex), stage(.fragment, fragment)]
    let digest = SceneShaderStableDigest.hash(Data((vertex + fragment).utf8))
    return .init(identity: identity, sourceKind: .authoredSource, stages: stages,
        diagnostics: [], canonicalSHA256: digest, sourceGraph: .init(
            roots: stages.map { .init(label: $0.kind.rawValue, virtualPath: $0.relativePath) },
            nodes: stages.map { .init(virtualPath: $0.relativePath, provenance: .loose,
                source: $0.source, rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count) },
            edges: [], diagnostics: [], dependencySHA256: digest))
}

private func template(_ shader: SceneShaderContract,
    references: [Int: Template.TextureReference], combos: [String: Int] = [:],
    bindings: [Template.GraphBindingRole] = []) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    for (slot, reference) in references {
        slots[slot] = .init(index: slot, candidates: [
            .init(reference: reference, provenance: .explicitBinding)])
    }
    return Template.validated(textureSlots: slots,
        combos: combos.map { .init(name: $0.key, value: $0.value) }, uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(blending: "normal",
            depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .effectOutput, bindings: bindings), shaderContract: shader,
        diagnosticProvenance: .init(nodeIndex: 37, authoredShaderPath: shader.identity,
            contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [], uniformSources: []))!
}

private func fragment(combo: String, material: String, reversed: Bool = false,
    expression: String? = nil, guarded: Bool = true, extra: String = "") -> String {
    let declarations = [
        "uniform sampler2D g_Texture1; // {\"material\":\"\(material)A\",\"mode\":\"rgbmask\",\"combo\":\"\(combo)\"}",
        "uniform sampler2D g_Texture2; // {\"combo\":\"\(combo)\",\"mode\":\"rgbmask\",\"material\":\"\(material)B\"}",
    ]
    let open = guarded ? "#if \(expression ?? combo)" : ""
    let close = guarded ? "#endif" : ""
    return """
    varying vec2 uv;
    \(extra)
    \((reversed ? declarations.reversed().map { $0 } : declarations).joined(separator: "\n"))
    void main() {
        vec4 color = vec4(0.0, 0.0, 0.0, 1.0);
    \(open)
        color.rgb = (texSample2D(g_Texture1, uv).rgb + texSample2D(g_Texture2, uv).rgb) * 0.5;
    \(close)
        gl_FragColor = color;
    }
    """
}

private func preparation(_ shader: SceneShaderContract, readiness: [Int: Bool],
    combos: [String: Int] = [:]) -> String {
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: shader, combos: combos, textureReadiness: readiness) {
    case .accepted: return "accepted"
    case let .rejected(failure): return failure.details.joined(separator: ":")
    case .notApplicable: return "not-applicable"
    }
}

private func render(_ program: SceneAuthoredShaderProgram) throws -> [[Int]]? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let library = try device.makeLibrary(source: program.metalSource, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: program.vertexFunctionName)
    descriptor.fragmentFunction = library.makeFunction(name: program.fragmentFunctionName)
    descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
    let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    func texture(_ color: [UInt8]?, target: Bool = false) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = target ? [.shaderRead, .renderTarget] : .shaderRead
        let value = device.makeTexture(descriptor: descriptor)!
        if let color {
            let bytes = Array(repeating: color, count: 4).flatMap { $0 }
            value.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                withBytes: bytes, bytesPerRow: 8)
        }
        return value
    }
    let target = texture(nil, target: true)
    let attachment = MTLRenderPassDescriptor()
    attachment.colorAttachments[0].texture = target
    attachment.colorAttachments[0].loadAction = .clear
    attachment.colorAttachments[0].storeAction = .store
    let commands = device.makeCommandQueue()!.makeCommandBuffer()!
    let encoder = commands.makeRenderCommandEncoder(descriptor: attachment)!
    encoder.setRenderPipelineState(pipeline)
    let uniformBytes = Array<UInt8>(repeating: 0, count: max(16, program.uniformLayout.byteSize))
    encoder.setVertexBytes(uniformBytes, length: uniformBytes.count, index: program.uniformBufferIndex)
    encoder.setFragmentBytes(uniformBytes, length: uniformBytes.count, index: program.uniformBufferIndex)
    let sampler = device.makeSamplerState(descriptor: MTLSamplerDescriptor())!
    var resources: [MTLTexture] = []
    for binding in program.textureBindings {
        let value = texture(binding.slot == 1 ? [200, 0, 0, 255] : [0, 0, 100, 255])
        resources.append(value)
        encoder.setVertexTexture(value, index: binding.slot)
        encoder.setFragmentTexture(value, index: binding.slot)
        encoder.setVertexSamplerState(sampler, index: binding.slot)
        encoder.setFragmentSamplerState(sampler, index: binding.slot)
    }
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()
    guard commands.status == .completed else {
        throw commands.error ?? NSError(domain: "self-authored-gpu", code: 1)
    }
    var bytes = [UInt8](repeating: 0, count: 16)
    target.getBytes(&bytes, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
    return stride(from: 0, to: bytes.count, by: 4).map { offset in
        bytes[offset ..< offset + 4].map(Int.init)
    }
}

private func facts(_ value: Template, absentSlots: Set<Int> = []) -> [String: Any] {
    var facts: [String: Any] = [
        "masks": SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(value).map(Int.init),
    ]
    do {
        let reachable = try SceneResolvedMaterialShaderSchema.reachableSamplers(
            value, implicitFramebufferIdentity: nil)
        facts["reachable"] = reachable.keys.sorted()
        facts["materialKeys"] = reachable.keys.sorted().map {
            reachable[$0]!.first!.materialKey ?? "<none>"
        }
    } catch { facts["reachabilityFailure"] = String(describing: error) }
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: value, maximumVariantCount: 16) else {
        facts["launch"] = "validation-failed"; return facts
    }
    let states = Dictionary(uniqueKeysWithValues: value.textureSlots.compactMap { slot
        -> (SceneAssetTextureIdentity, SceneAssetTextureLaunchState)? in
        guard let slot, case let .asset(path)? = slot.candidates.last?.reference else { return nil }
        return (.init(path: path, purpose: .preservedChannels),
            absentSlots.contains(slot.index) ? .absent : .ready(.data))
    })
    switch cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil, assetStates: states) {
    case .success:
        facts["launch"] = "accepted"
        facts["activeSlots"] = cache.launchEnvelopeActiveTextureSlots?.sorted()
        let variants = cache.launchEnvelopeCapabilitySnapshot().variants
        facts["variantMasks"] = variants.map { Int($0.readinessMask) }.sorted()
        if let ready = variants.first(where: { $0.readinessMask == 6 }) {
            do { facts["gpuPixels"] = try render(ready.frontendProgram) }
            catch { facts["gpuFailure"] = String(describing: error) }
        }
    case .failure(.capacity): facts["launch"] = "capacity"
    case let .failure(.material(failure)):
        facts["launch"] = ([failure.code.rawValue] + failure.boundedDetails).joined(separator: ":")
    }
    return facts
}

@main private struct Harness {
    static func main() throws {
        let paths = [1: SceneVFSAssetPath("self-authored/amber")!,
                     2: SceneVFSAssetPath("self-authored/cobalt")!]
        let references = paths.mapValues { Template.TextureReference.asset($0) }
        let shader = contract("consensus", fragment(combo: "PRESENT", material: "input"))
        let selfGated = contract("self-gated", fragment(combo: "PRESENT", material: "input")
            .replacingOccurrences(of: "uniform sampler2D g_Texture1;",
                with: "#if PRESENT\nuniform sampler2D g_Texture1;")
            .replacingOccurrences(of: "void main()", with: "#endif\nvoid main()"))
        let renamed = contract("other-owner", fragment(combo: "READY_PAIR", material: "paint",
            reversed: true, expression: "defined(READY_PAIR) && (READY_PAIR == 1)")
            .replacingOccurrences(of: "uv", with: "coordinate"), varyingName: "coordinate")
        let defaultConflict = contract("default-conflict", fragment(combo: "PRESENT", material: "input",
            extra: #"// [COMBO] {"combo":"PRESENT","default":2}"#))
        let independent = contract("independent", fragment(combo: "FIRST", material: "input")
            .replacingOccurrences(of: #""combo":"FIRST","mode""#, with: #""combo":"SECOND","mode""#))
        let conditional = contract("conditional", """
        // [COMBO] {"combo":"CHOOSE","default":1}
        #if CHOOSE
        uniform sampler2D g_Texture1; // {"combo":"PRESENT","mode":"rgbmask","material":"one"}
        #else
        uniform sampler2D g_Texture2; // {"combo":"PRESENT","mode":"rgbmask","material":"two"}
        #endif
        void main() { gl_FragColor = vec4(1.0); }
        """)
        let required = contract("requirements", """
        // [COMBO] {"combo":"CHOOSE","default":1}
        uniform sampler2D g_Texture1; // {"combo":"PRESENT","require":{"CHOOSE":1},"mode":"rgbmask"}
        uniform sampler2D g_Texture2; // {"combo":"PRESENT","require":{"CHOOSE":0},"mode":"rgbmask"}
        void main() { gl_FragColor = vec4(1.0); }
        """)
        var renamedReferences = references
        renamedReferences[1] = .asset(SceneVFSAssetPath("renamed/source-red")!)
        renamedReferences[2] = .asset(SceneVFSAssetPath("renamed/source-blue")!)
        var results: [String: Any] = [
            "consensus": facts(template(shader, references: references)),
            "actualAssetMixed": facts(template(shader, references: references), absentSlots: [2]),
            "selfGated": facts(template(selfGated, references: references)),
            "renamed": facts(template(renamed, references: renamedReferences)),
            "unguarded": facts(template(contract("unguarded",
                fragment(combo: "PRESENT", material: "input", guarded: false)), references: references)),
            "actualReady": preparation(shader, readiness: [1: true, 2: true]),
            "actualAbsent": preparation(shader, readiness: [1: false, 2: false]),
            "actualMixed": preparation(shader, readiness: [1: true, 2: false]),
            "missingReadiness": preparation(shader, readiness: [1: true]),
            "defaultConflict": facts(template(defaultConflict, references: references)),
            "explicitConflict": facts(template(shader, references: references, combos: ["PRESENT": 2])),
            "independentMasks": SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
                template(independent, references: references)).map(Int.init),
            "conditionalMasks": SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
                template(conditional, references: references)).map(Int.init),
            "requirementMasks": SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
                template(required, references: references)).map(Int.init),
            "conditionalMixed": preparation(conditional, readiness: [1: true, 2: false]),
            "requirementMixed": preparation(required, readiness: [1: true, 2: false]),
        ]
        let malformed = contract("malformed", fragment(combo: "PRESENT", material: "input")
            .replacingOccurrences(of: #""combo":"PRESENT""#, with: #""combo":17"#))
        results["malformed"] = facts(template(malformed, references: references))
        results["malformedPreparation"] = preparation(malformed, readiness: [1: true, 2: true])
        var providerReferences = references
        providerReferences[1] = .provider(.sceneEnvironment)
        results["providerMasks"] = SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
            template(shader, references: providerReferences)).map(Int.init)
        var graphReferences = references
        graphReferences[1] = .graph(.init(kind: .layerSource, layerID: 11, effect: nil, name: nil))
        results["graphMasks"] = SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
            template(shader, references: graphReferences)).map(Int.init)
        let alias = contract("framebuffer-alias", fragment(combo: "PRESENT", material: "input")
            .replacingOccurrences(of: #""material":"inputA""#, with: #""material":"framebuffer""#))
        results["aliasMasks"] = SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
            template(alias, references: references)).map(Int.init)
        results["graphBindingMasks"] = SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
            template(shader, references: references,
                bindings: [.init(slot: 1, texture: .framebuffer)])).map(Int.init)
        results["propertyMasks"] = SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
            template(shader, references: [1: .userProperty(.init(key: "paint-one")),
                2: .userProperty(.init(key: "paint-two"))])).map(Int.init)
        results["missingCandidateMasks"] = SceneResolvedMaterialShaderSchema.launchAvailabilityMasks(
            template(shader, references: [1: references[1]!])).map(Int.init)
        print(String(data: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]),
            encoding: .utf8)!)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSharedPresenceReachabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-shared-presence-")
        root = Path(cls.temporary_directory.name)
        support, harness, binary = root / "Support.swift", root / "Harness.swift", root / "test"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(root / "shader-cache")
        environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
        compilation = subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", str(support),
            *(str(path) for path in SWIFT_SOURCES),
            str(SCENE_ROOT / "Resources/Providers/SceneStockNoiseTextureStore.swift"), str(harness),
            "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
            "-module-cache-path", str(root / "module-cache"), "-o", str(binary)],
            cwd=REPOSITORY_ROOT, env=environment, capture_output=True, text=True)
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary)], cwd=REPOSITORY_ROOT,
            env=environment, capture_output=True, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if output := os.environ.get("MWX_SHARED_PRESENCE_FACTS"):
            Path(output).write_text(json.dumps(cls.result, indent=2) + "\n", encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_consensus_hypotheses_preserve_resource_demand_and_launch(self) -> None:
        for name in ("consensus", "renamed", "unguarded", "selfGated"):
            with self.subTest(name=name):
                facts = self.result[name]
                self.assertEqual(facts["masks"], [0, 6], facts)
                self.assertEqual(facts.get("reachable"), [1, 2], facts)
                self.assertEqual(facts["launch"], "accepted", facts)
                self.assertEqual(facts["activeSlots"], [1, 2], facts)
                self.assertEqual(facts["variantMasks"], [6] if name == "unguarded" else [0, 6], facts)

    def test_actual_readiness_and_authored_errors_remain_rejected(self) -> None:
        self.assertEqual(self.result["actualReady"], "accepted")
        self.assertEqual(self.result["actualAbsent"], "accepted")
        self.assertEqual(self.result["actualMixed"], "conflicting-texture-readiness:PRESENT")
        self.assertIn("shaderPreparationFailed:shader-preprocessor:shader-variant-invalid:conflicting-texture-readiness:PRESENT",
            self.result["actualAssetMixed"]["launch"])
        self.assertEqual(self.result["missingReadiness"], "texture-readiness-unavailable:PRESENT")
        self.assertIn("conflicting-texture-readiness", self.result["defaultConflict"]["launch"])
        self.assertIn("explicit-texture-readiness-conflict", self.result["explicitConflict"]["launch"])
        self.assertNotEqual(self.result["malformed"]["launch"], "accepted")
        self.assertIn("invalid-annotation", self.result["malformedPreparation"])

    def test_independent_inactive_and_unproven_source_slots_are_not_constrained(self) -> None:
        for name in ("independentMasks", "conditionalMasks", "requirementMasks", "providerMasks",
                     "graphMasks", "aliasMasks", "graphBindingMasks"):
            self.assertEqual(self.result[name], [0, 2, 4, 6], name)
        self.assertEqual(self.result["missingCandidateMasks"], [0, 2])
        self.assertEqual(self.result["propertyMasks"], [0, 6])
        self.assertEqual(self.result["conditionalMixed"], "accepted")
        self.assertEqual(self.result["requirementMixed"], "accepted")

    def test_self_authored_ready_variant_executes_both_resource_slots_on_gpu(self) -> None:
        for name in ("consensus", "renamed", "unguarded", "selfGated"):
            facts = self.result[name]
            if "gpuPixels" not in facts and "gpuFailure" not in facts and facts["launch"] == "accepted":
                self.skipTest("Metal is unavailable")
            self.assertNotIn("gpuFailure", facts, facts)
            self.assertEqual(len(facts.get("gpuPixels", [])), 4, facts)
            for pixel in facts["gpuPixels"]:
                self.assertLessEqual(abs(pixel[0] - 100), 1, facts)
                self.assertEqual(pixel[1], 0, facts)
                self.assertLessEqual(abs(pixel[2] - 50), 1, facts)
                self.assertEqual(pixel[3], 255, facts)


if __name__ == "__main__":
    unittest.main()
