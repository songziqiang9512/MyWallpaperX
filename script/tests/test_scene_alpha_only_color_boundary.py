#!/usr/bin/env python3
"""Direct sampled alpha stays scalar through the ordinary color boundary."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_graph_source_color_purpose as color_fixture
from script.tests import test_scene_resolved_material_graph_executor as fixture
from script.tests.scene_compiler_fixture import compiler_bundle, fixture_sources
from script.tests.scene_harness_io import separate_graph_debug_output


ROOT = Path(__file__).resolve().parents[2]
SOURCES = fixture.CONTRACT_FIXTURE["SWIFT_SOURCES"]

HARNESS = r'''
private typealias AlphaDerivation = SceneResolvedMaterialProgramDerivation

private struct AlphaCase {
    let name: String
    let slot: Int
    let path: String
    let vertex: String
    let fragment: String
    let alphaOnly: Bool
}

private func alphaCase(_ name: String, slot: Int = 0, path: String = "own/scalar",
    body: String, vertex: String = vertexSource, helper: String = "",
    alphaOnly: Bool = true) -> AlphaCase {
    .init(name: name, slot: slot, path: path, vertex: vertex, fragment: """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture\(slot);
    \(helper)
    void main() { \(body) }
    """, alphaOnly: alphaOnly)
}

private func alphaCases() -> [AlphaCase] {
    [
        alphaCase("direct-a", body: """
            float density = texSample2D(g_Texture0, v_TexCoord).a;
            gl_FragColor = vec4(vec3(density), 1.0);
            """),
        alphaCase("renamed-w", slot: 3, path: "fixtures/relocated/unseen-paint", body: """
            float ink = texture2D(g_Texture3, (v_TexCoord)).w;
            gl_FragColor = vec4(ink, ink, ink, 1.0);
            """),
        alphaCase("two-equivalent-lookups", body: """
            float amount = 0.5 * (texture2D(g_Texture0, v_TexCoord).a
                + texSample2D(g_Texture0, (v_TexCoord)).w);
            gl_FragColor = vec4(vec3(amount), 1.0);
            """),
        alphaCase("rgb", body: """
            vec3 pigment = texSample2D(g_Texture0, v_TexCoord).rgb;
            gl_FragColor = vec4(pigment, 1.0);
            """, alphaOnly: false),
        alphaCase("whole-vector", body: """
            vec4 pigment = texSample2D(g_Texture0, v_TexCoord);
            gl_FragColor = vec4(pigment.rgb, 1.0);
            """, alphaOnly: false),
        alphaCase("mixed-rgb-alpha", body: """
            float density = texSample2D(g_Texture0, v_TexCoord).a;
            vec3 pigment = texSample2D(g_Texture0, v_TexCoord).rgb;
            gl_FragColor = vec4(pigment * density, 1.0);
            """, alphaOnly: false),
        alphaCase("vector-alias-then-alpha", body: """
            vec4 raw = texSample2D(g_Texture0, v_TexCoord);
            float density = raw.a;
            gl_FragColor = vec4(vec3(density), 1.0);
            """, alphaOnly: false),
        alphaCase("sampler-helper-escape", body: """
            float density = extractAlpha(g_Texture0, v_TexCoord);
            gl_FragColor = vec4(vec3(density), 1.0);
            """, helper: """
            float extractAlpha(sampler2D source, vec2 point) {
                return texSample2D(source, point).a;
            }
            """, alphaOnly: false),
        alphaCase("vertex-read", body: """
            float density = texSample2D(g_Texture0, v_TexCoord).a;
            gl_FragColor = vec4(vec3(density), 1.0);
            """, vertex: """
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            void main() {
                v_TexCoord = a_TexCoord;
                float displacement = texSample2D(g_Texture0, a_TexCoord).a;
                gl_Position = vec4(a_Position.xy + vec2(displacement), 0.0, 1.0);
            }
            """, alphaOnly: false),
    ]
}

private func boundary(_ alpha: [Int], colors: [Int] = []) throws -> SceneShaderColorBoundary {
    let bytes = try JSONSerialization.data(withJSONObject: [
        "colorInputSlots": colors, "alphaInputSlots": alpha,
        "outputRepresentation": "opaque",
    ])
    return try JSONDecoder().decode(SceneShaderColorBoundary.self, from: bytes)
}

private func boundaryJSON(_ value: SceneShaderColorBoundary?) throws -> [String: Any] {
    guard let value else { return [:] }
    return try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
}

private func alphaContract(_ value: AlphaCase) -> SceneShaderContract {
    let sourceStages: [(SceneShaderContract.StageKind, String)] = [
        (.vertex, value.vertex), (.fragment, value.fragment),
    ]
    let stages: [SceneShaderContract.Stage] = sourceStages
        .map { kind, source in
            let path = value.path + (kind == .vertex ? ".vert" : ".frag")
            let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
            return .init(kind: kind, relativePath: path, source: source,
                rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
                includes: parsed.includes, annotations: parsed.annotations, declarations: parsed.declarations)
        }
    let digest = SceneShaderStableDigest.hash(stages)
    return .init(identity: value.path, sourceKind: .authoredSource, stages: stages, diagnostics: [],
        canonicalSHA256: digest, sourceGraph: .init(roots: stages.map {
            .init(label: $0.kind == .vertex ? "vertex" : "fragment", virtualPath: $0.relativePath)
        }, nodes: stages.map {
            .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
                rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
        }, edges: [], diagnostics: [], dependencySHA256: digest))
}

private func alphaTemplate(_ value: AlphaCase, identity: Graph.TextureIdentity) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[value.slot] = .init(index: value.slot, candidates: [
        .init(reference: .graph(identity), provenance: .explicitBinding),
    ])
    let shader = alphaContract(value)
    return Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
            depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
        graphRole: .init(effectInput: .framebuffer, effectOutput: .effectOutput,
            nodeTarget: .effectOutput, bindings: [.init(slot: value.slot, texture: .framebuffer)]),
        shaderContract: shader, diagnosticProvenance: .init(nodeIndex: 0,
            authoredShaderPath: value.path, contractIdentity: value.path,
            contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [], uniformSources: []))!
}

private func runAlphaMaterial(_ value: AlphaCase, name: String, content: SceneTextureContent,
    device: MTLDevice, queue: MTLCommandQueue,
    purpose: SceneTextureLoadPurpose = .premultipliedColor,
    pixelFormat: MTLPixelFormat = .bgra8Unorm,
    sourceFormat: SceneShaderTextureFormat = .rgba8888) throws -> [String: Any] {
    let effect = Graph.EffectKey(layerID: 919, effectIndex: 0, descriptorID: "own-alpha-slot")
    let identity = Graph.TextureIdentity(kind: .framebuffer, layerID: 919,
        effect: effect, name: value.path)
    let template = alphaTemplate(value, identity: identity)
    var row: [String: Any] = ["case": value.name, "representation": name, "slot": value.slot]
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: template, maximumVariantCount: 8) else {
        row["launch"] = "cache-unavailable"; return row
    }
    row["launch"] = launchEnvelopeFailureCode(cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: identity, outputIsRGBA8Unorm: true,
        graphTextureFormatFacts: [identity: sourceFormat], graphTextureContentFacts: [identity: content]))
    let snapshot = cache.launchEnvelopeCapabilitySnapshot()
    row["allEntriesReady"] = snapshot.allEntriesReady
    row["boundaries"] = try snapshot.variants.map { try boundaryJSON($0.frontendProgram.colorBoundary) }
    row["channelUses"] = snapshot.variants.flatMap { $0.frontendProgram.textureBindings.map(\.channelUse.rawValue) }
    let inputPurpose: SceneTextureLoadPurpose = content == .color(.resolved(.straightAlpha))
        ? .straightAlbedo : purpose
    let resource = graphAtom(device, identity: identity, purpose: inputPurpose, content: content,
        pixelFormat: pixelFormat)
    if content == .color(.resolved(.opaque)) {
        let pixels: [UInt8] = [32, 64, 128, 255, 32, 64, 128, 255,
                              32, 64, 128, 255, 32, 64, 128, 255]
        resource.publication.texture.replace(region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0, withBytes: pixels, bytesPerRow: 8)
    }
    row["inputComplete"] = resource.isCompleteGraphResource
    let input = inputFor(template, entries: [.graph(identity): .ready(resource)], graphInput: identity)
    switch SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: cache) {
    case let .failure(failure): row["finalization"] = diagnostic(failure)
    case let .success(program):
        row["finalization"] = "success"
        row["outputContract"] = String(describing: program.outputContract)
        if case let .color(contract) = program.outputContract {
            row["opaqueOutput"] = contract.fragmentOutput == .resolved(.opaque)
        }
        row["sameInputAtom"] = program.textureSlots[value.slot]?.resource.publication.isSameAtom(as: resource.publication) ?? false
        row["inputMask"] = program.resolvedUniforms.first {
            $0.field.name == SceneShaderColorBoundary.uniformName
        }.map { $0.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } } ?? 0
        guard let encoder = SceneResolvedMaterialPassEncoder(device: device),
              let command = queue.makeCommandBuffer() else { return row }
        let target = makeSource(device, width: 2, height: 2, usage: [.renderTarget, .shaderRead])
        guard let pass = encoder.prepare(program: program, target: target),
              encoder.encode(pass, commandBuffer: command),
              let readback = appendReadback(target, commandBuffer: command) else { return row }
        command.commit(); command.waitUntilCompleted()
        row["gpuCompleted"] = command.status == .completed && command.error == nil
        row["pixelsBGRA"] = readback.allTexels
    }
    return row
}

private func compilerProof(_ value: AlphaCase, bundle: Bundle, cache: URL) throws -> [String: Any] {
    let contract = try boundary([value.slot])
    let plain = SceneAuthoredShaderFrontend.compile(vertexSource: value.vertex, fragmentSource: value.fragment)
    let bounded = SceneAuthoredShaderFrontend.compile(vertexSource: value.vertex,
        fragmentSource: value.fragment, colorBoundary: contract)
    let expectedTransfer = plain.program?.colorTransfer ?? .opaque
    let expectedOutput = plain.program?.fragmentOutputChannelUse ?? .redDefined
    let key = SceneResolvedMaterialGenericShaderRequest.key(vertexSource: value.vertex,
        fragmentSource: value.fragment, outputSemantics: .color, expectedColorTransfer: nil,
        premultipliedColorInputSlots: [], colorBoundary: contract)
    var row: [String: Any] = ["name": value.name, "slot": value.slot, "expectedAlphaOnly": value.alphaOnly,
        "sourceChannelUse": SceneAuthoredShaderTextureChannelAnalyzer.analyze(samplerName: "g_Texture\(value.slot)",
            vertexSource: value.vertex, fragmentSource: value.fragment).rawValue,
        "boundedAccepted": bounded.program != nil,
        "boundedDiagnostics": bounded.diagnostics.map { String(describing: $0.code) },
        "boundedChannels": bounded.program?.textureBindings.map(\.channelUse.rawValue) ?? []]
    switch SceneGenericShaderCompiler.compile(requestKey: key, vertexSource: value.vertex,
        fragmentSource: value.fragment, colorBoundary: contract, cacheRoot: cache, bundle: bundle) {
    case let .failure(failure):
        row["genericAccepted"] = false; row["genericFailure"] = String(describing: failure)
    case let .success(url):
        let artifactBytes = try Data(contentsOf: url)
        let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self,
            from: artifactBytes)
        let program = artifact.makeProgram(expectedKey: key, expectedColorBoundary: contract,
            expectedColorTransfer: expectedTransfer, expectedFragmentOutputChannelUse: expectedOutput)
        row["genericAccepted"] = program != nil
        row["genericChannels"] = program?.textureBindings.map(\.channelUse.rawValue) ?? []
        row["genericBoundary"] = try boundaryJSON(program?.colorBoundary)
        if value.alphaOnly {
            var rejected: [String: Bool] = [:]
            for replacement in ["redOnly", "wholeVector", "unproven"] {
                var object = try JSONSerialization.jsonObject(with: artifactBytes) as! [String: Any]
                var body = object["program"] as! [String: Any]
                var bindings = body["textureBindings"] as! [[String: Any]]
                let index = bindings.firstIndex { ($0["slot"] as? Int) == value.slot }!
                bindings[index]["channelUse"] = replacement
                body["textureBindings"] = bindings; object["program"] = body
                let changed = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self,
                    from: JSONSerialization.data(withJSONObject: object))
                rejected[replacement] = changed.makeProgram(expectedKey: key,
                    expectedColorBoundary: contract, expectedColorTransfer: expectedTransfer,
                    expectedFragmentOutputChannelUse: expectedOutput) == nil
            }
            row["forgedChannelsRejected"] = rejected
        }
    }
    return row
}

private func boundaryAndFactProof() throws -> [String: Any] {
    let contract = try boundary([0])
    let old = try JSONDecoder().decode(SceneShaderColorBoundary.self,
        from: Data(#"{"colorInputSlots":[2],"outputRepresentation":"opaque"}"#.utf8))
    let color = SceneShaderColorBoundary(colorInputSlots: [0], outputRepresentation: .opaque)
    let contents: [(String, SceneTextureContent?)] = [
        ("independent", .color(.resolved(.independentAlphaSignal))),
        ("premultiplied", .color(.resolved(.premultipliedAlpha))),
        ("straight", .color(.resolved(.straightAlpha))), ("opaque", .color(.resolved(.opaque))),
        ("rgba-data", .data), ("unknown", .color(.unresolved)),
        ("R8", .scalarRedUnorm), ("RG8", .redGreenUnorm),
        ("R16F", .scalarRedFloat16), ("RG16F", .redGreenFloat16), ("missing", nil),
    ]
    let facts = contents.map { name, content -> [String: Any] in
        var values = Array<AlphaDerivation.ColorTextureFact?>(repeating: nil, count: 8)
        values[0] = content.map { .init(isGraphReference: true, isFramebufferInput: true, content: $0) }
        return ["name": name, "accepted": AlphaDerivation.resolveColor(transfer: .opaque,
            textureFacts: values, colorBoundary: contract) != nil]
    }
    func requestKey(_ value: SceneShaderColorBoundary) -> String {
        SceneResolvedMaterialGenericShaderRequest.key(vertexSource: vertexSource, fragmentSource: "same-source",
            outputSemantics: .color, expectedColorTransfer: nil, premultipliedColorInputSlots: [],
            colorBoundary: value)
    }
    return ["oldBoundary": try boundaryJSON(old), "alphaBoundary": try boundaryJSON(contract),
        "oldValid": old.isValid, "alphaValid": contract.isValid,
        "overlapInvalid": !(try boundary([0], colors: [0])).isValid,
        "duplicateInvalid": !(try boundary([0, 0])).isValid,
        "outOfRangeInvalid": !(try boundary([8])).isValid,
        "negativeInvalid": !(try boundary([-1])).isValid,
        "cacheKeySeparatesRoles": contract.cacheKey != color.cacheKey,
        "requestKeySeparatesRoles": requestKey(contract) != requestKey(color),
        "cacheKeySeparatesAlphaSlots": contract.cacheKey != (try boundary([3])).cacheKey,
        "facts": facts]
}

@main private enum AlphaOnlyHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard CommandLine.arguments.count == 3, let bundle = Bundle(path: CommandLine.arguments[1]),
              let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw NSError(domain: "alpha-only-fixture-environment", code: 1) }
        let cache = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let cases = alphaCases()
        let contents: [(String, SceneTextureContent)] = [
            ("independent", .color(.resolved(.independentAlphaSignal))),
            ("premultiplied", .color(.resolved(.premultipliedAlpha))),
            ("straight", .color(.resolved(.straightAlpha))), ("opaque", .color(.resolved(.opaque))),
        ]
        var material: [[String: Any]] = []
        for value in cases.prefix(3) {
            for (name, content) in contents {
                material.append(try runAlphaMaterial(value, name: name, content: content, device: device, queue: queue))
            }
        }
        for value in cases.dropFirst(3).prefix(4) {
            material.append(try runAlphaMaterial(value, name: "independent",
                content: .color(.resolved(.independentAlphaSignal)), device: device, queue: queue))
        }
        // Existing whole-vector expansion supplies Metal's default alpha.
        // Direct-alpha R/RG sampling was rejected by the old resolver.
        let typedDataCase = cases.first { $0.name == "vector-alias-then-alpha" }!
        let typedData = [
            try runAlphaMaterial(typedDataCase, name: "R8", content: .scalarRedUnorm,
                device: device, queue: queue, purpose: .preservedChannels,
                pixelFormat: .r8Unorm, sourceFormat: .r8),
            try runAlphaMaterial(typedDataCase, name: "RG8", content: .redGreenUnorm,
                device: device, queue: queue, purpose: .preservedChannels,
                pixelFormat: .rg8Unorm, sourceFormat: .rg88),
        ]
        let result: [String: Any] = ["material": material, "typedData": typedData,
            "compilers": try cases.map { try compilerProof($0, bundle: bundle, cache: cache) },
            "boundary": try boundaryAndFactProof()]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
'''


def source_files() -> list[Path]:
    """An optional exported source root keeps the pre-fix red gate immutable."""
    snapshot = os.environ.get("MWX_SCENE_ALPHA_ONLY_SOURCE_SNAPSHOT")
    return [Path(snapshot) / p.relative_to(ROOT) for p in SOURCES] if snapshot else list(SOURCES)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneAlphaOnlyColorBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-alpha-only-boundary-") as directory:
            root = Path(directory)
            bundle = compiler_bundle(root)
            sources = fixture_sources(root, bundle, source_files())
            prefix, marker, _ = fixture.HARNESS.partition("@main\nprivate enum Harness")
            helpers, helper_marker, _ = color_fixture.HARNESS.partition("private func traceMaterial")
            if not marker or not helper_marker:
                raise RuntimeError("existing graph fixture helper boundary unavailable")
            support, harness, binary = root / "Support.swift", root / "Harness.swift", root / "probe"
            support.write_text(fixture.SUPPORT, encoding="utf-8")
            harness.write_text(prefix + helpers + HARNESS, encoding="utf-8")
            inputs = [*sources, support, harness]
            before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
            environment = os.environ.copy()
            for name in ("CLANG_MODULE_CACHE_PATH", "SWIFT_MODULECACHE_PATH",
                         "MWX_SCENE_GENERIC_SHADER_CACHE", "MWX_SCENE_PIPELINE_BINARY_ARCHIVE"):
                environment[name] = str(root / name.lower())
            command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                "-whole-module-optimization", "-Onone",
                *fixture.CONTRACT_FIXTURE["GRAPH_SWIFT_FLAGS"], str(support), *map(str, sources),
                str(harness), "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO", "-framework", "Security",
                "-module-cache-path", str(root / "module-cache"), "-o", str(binary)]
            compilation = subprocess.run(command, cwd=ROOT, env=environment,
                capture_output=True, text=True, timeout=240)
            completed = None
            if not compilation.returncode:
                completed = separate_graph_debug_output(subprocess.run(
                    [str(binary), str(bundle), str(root / "artifacts")], cwd=root, env=environment,
                    capture_output=True, text=True, timeout=120))
            after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
            evidence = os.environ.get("MWX_SCENE_ALPHA_ONLY_EVIDENCE_DIR")
            if evidence:
                target = Path(evidence); target.mkdir(parents=True, exist_ok=True)
                (target / "compile.stdout").write_text(compilation.stdout)
                (target / "compile.stderr").write_text(compilation.stderr)
                (target / "receipt.json").write_text(json.dumps({
                    "command": command, "sourceSnapshot": os.environ.get("MWX_SCENE_ALPHA_ONLY_SOURCE_SNAPSHOT"),
                    "sourcesBefore": before, "sourcesAfter": after,
                    "compileExitCode": compilation.returncode,
                    "harnessExitCode": completed.returncode if completed else None,
                }, indent=2) + "\n")
                if completed:
                    (target / "result.json").write_text(completed.stdout)
                    (target / "harness.stderr").write_text(completed.stderr)
            if before != after:
                raise RuntimeError("Alpha boundary gate inputs changed during compilation/execution")
            if compilation.returncode:
                raise RuntimeError(compilation.stderr)
            if completed is None or completed.returncode:
                raise RuntimeError(completed.stderr if completed else "alpha fixture did not run")
            cls.result = json.loads(completed.stdout)

    def test_alpha_only_signal_reaches_variant_finalizer_and_gpu(self) -> None:
        rows = self.result["material"][:12]
        self.assertEqual(len(rows), 12)
        for row in rows:
            with self.subTest(case=row["case"], representation=row["representation"]):
                self.assertEqual(row["launch"], "success", row)
                self.assertTrue(row["allEntriesReady"], row)
                self.assertTrue(row["inputComplete"], row)
                self.assertEqual(row["finalization"], "success", row)
                self.assertTrue(row["sameInputAtom"], row)
                self.assertTrue(row["opaqueOutput"], row)
                self.assertTrue(row["gpuCompleted"], row)
                self.assertEqual(row["inputMask"], 0, row)
                self.assertEqual(row["channelUses"], ["alphaOnly"], row)
                for boundary in row["boundaries"]:
                    self.assertEqual(boundary.get("alphaInputSlots"), [row["slot"]], row)
                    self.assertEqual(boundary["colorInputSlots"], [], row)
                    self.assertEqual(boundary["outputRepresentation"], "opaque", row)
                expected = [[255, 255, 255, 255]] * 4 if row["representation"] == "opaque" else [
                    [0, 0, 0, 255], [128, 128, 128, 255],
                    [255, 255, 255, 255], [0, 0, 0, 255],
                ]
                self.assertEqual(sorted(row["pixelsBGRA"]), sorted(expected), row)

    def test_rgb_and_vector_uses_do_not_gain_alpha_exemption(self) -> None:
        rows = self.result["material"][12:]
        self.assertEqual(len(rows), 4)
        for row in rows:
            with self.subTest(case=row["case"]):
                self.assertFalse(row.get("gpuCompleted", False), row)
                self.assertNotEqual(row["finalization"], "success", row)
                for boundary in row["boundaries"]:
                    self.assertEqual(boundary.get("alphaInputSlots", []), [], row)

    def test_existing_typed_r_rg_default_alpha_does_not_gain_a_new_gate(self) -> None:
        rows = self.result["typedData"]
        self.assertEqual(len(rows), 2)
        for row in rows:
            with self.subTest(content=row["representation"]):
                self.assertEqual(row["launch"], "success", row)
                self.assertEqual(row["finalization"], "success", row)
                self.assertTrue(row["inputComplete"], row)
                self.assertTrue(row["sameInputAtom"], row)
                self.assertTrue(row["gpuCompleted"], row)
                self.assertEqual(row["inputMask"], 0, row)
                self.assertEqual(row["channelUses"], ["wholeVector"], row)
                self.assertEqual(row["pixelsBGRA"], [[255, 255, 255, 255]] * 4, row)
                for boundary in row["boundaries"]:
                    self.assertEqual(boundary.get("alphaInputSlots", []), [], row)

    def test_both_compilers_require_direct_fragment_alpha_source_proof(self) -> None:
        for row in self.result["compilers"]:
            with self.subTest(case=row["name"]):
                expected = row["expectedAlphaOnly"]
                self.assertEqual(row["sourceChannelUse"] == "alphaOnly", expected, row)
                self.assertEqual(row["boundedAccepted"], expected, row)
                self.assertEqual(row["genericAccepted"], expected, row)
                if expected:
                    self.assertEqual(row["boundedChannels"], ["alphaOnly"], row)
                    self.assertEqual(row["genericChannels"], ["alphaOnly"], row)
                    self.assertEqual(row["genericBoundary"].get("alphaInputSlots"), [row["slot"]], row)
                    self.assertEqual(row["forgedChannelsRejected"], {
                        "redOnly": True, "wholeVector": True, "unproven": True,
                    }, row)

    def test_alpha_requires_an_actual_stored_resolved_component(self) -> None:
        accepted = {"independent", "premultiplied", "straight", "opaque", "rgba-data"}
        facts = self.result["boundary"]["facts"]
        self.assertEqual(len(facts), 11)
        for row in facts:
            with self.subTest(content=row["name"]):
                self.assertEqual(row["accepted"], row["name"] in accepted, row)

    def test_boundary_roles_are_disjoint_and_part_of_cache_identity(self) -> None:
        value = self.result["boundary"]
        for name in ("alphaValid", "overlapInvalid", "duplicateInvalid", "outOfRangeInvalid",
                     "negativeInvalid", "cacheKeySeparatesRoles", "requestKeySeparatesRoles",
                     "cacheKeySeparatesAlphaSlots"):
            with self.subTest(check=name):
                self.assertTrue(value[name], value)

    def test_older_boundary_codable_defaults_to_no_alpha_slots(self) -> None:
        value = self.result["boundary"]
        self.assertTrue(value["oldValid"], value)
        self.assertEqual(value["oldBoundary"].get("alphaInputSlots"), [], value)
        self.assertEqual(value["oldBoundary"]["colorInputSlots"], [2], value)


if __name__ == "__main__":
    unittest.main()
