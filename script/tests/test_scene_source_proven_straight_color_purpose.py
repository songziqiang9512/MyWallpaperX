#!/usr/bin/env python3

"""Strict source-derived straight-color sampler purpose admission."""

from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import time
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASE = runpy.run_path(
    str(REPOSITORY_ROOT / "script/tests/test_scene_sampler_default_purpose.py")
)
SWIFT_SOURCES = BASE["SWIFT_SOURCES"]
SUPPORT = BASE["SUPPORT"]


HARNESS = r'''
import Foundation

private typealias Schema = SceneResolvedMaterialShaderSchema
private let customPath = SceneVFSAssetPath("fixtures/unseen/color")!
private let registeredNormalPath = SceneVFSAssetPath("effects/waterripplenormal")!

private let vertexSource = """
attribute vec3 a_Position;
void main() {
    gl_Position = vec4(a_Position, 1.0);
}
"""

private func contract(
    _ fragment: String,
    vertex: String = vertexSource
) -> SceneShaderContract {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        _ path: String,
        _ source: String
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
    let stages = [
        stage(.vertex, "fixture/color.vert", vertex),
        stage(.fragment, "fixture/color.frag", fragment),
    ]
    let digest = SceneShaderStableDigest.hash(Data((vertex + fragment).utf8))
    return .init(
        identity: "fixture/source-proven-straight-color",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: digest,
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "fixture/color.vert"),
                .init(label: "fragment", virtualPath: "fixture/color.frag"),
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
            dependencySHA256: digest
        )
    )
}

private func fragment(
    metadata: String = "",
    body: String,
    samplerName: String = "g_Texture3"
) -> String {
    """
    uniform sampler2D \(samplerName); \(metadata)
    void main() {
        \(body)
    }
    """
}

private func preparedSampler(
    _ source: String,
    vertex: String = vertexSource,
    samplerName: String = "g_Texture3"
) -> Schema.Sampler? {
    let shader = contract(source, vertex: vertex)
    guard case let .accepted(prepared) =
        SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader,
            combos: [:],
            textureReadiness: Dictionary(
                uniqueKeysWithValues: (0..<8).map { ($0, true) }
            )
        ) else { return nil }
    let slot = Int(samplerName.dropFirst("g_Texture".count))!
    return try? Schema.activeSamplers(prepared)[slot]
}

private func token(
    _ sampler: Schema.Sampler?,
    path: SceneVFSAssetPath = customPath
) -> String {
    guard let sampler else { return "missing" }
    let source = sampler.sourceProvenPurpose?.reportToken ?? "nil"
    let purpose = sampler.purpose(for: .asset(path))?.reportToken ?? "nil"
    return "\(sampler.channelUse.rawValue)/\(source)/\(purpose)"
}

private func proof(
    _ source: String,
    vertex: String = vertexSource
) -> Bool {
    SceneAuthoredShaderTextureChannelAnalyzer.provesStraightColorUse(
        samplerName: "g_Texture3",
        vertexSource: vertex,
        fragmentSource: source
    )
}

private func colorGraph(_ suffix: String = "color.rgb *= gain;", extra: String = "",
                        leaf: String = "g_Texture3", metadata: String = "") -> String {
    """
    uniform sampler2D g_Texture3; \(metadata)
    uniform sampler2D g_Texture5;
    uniform float gain;
    void main() {
        vec4 color = texSample2D(g_Texture3, vec2(0.2));
        color = mix(color, texture2D(\(leaf), vec2(0.8)), 0.5);
        \(suffix)
        \(extra)
        gl_FragColor = color;
    }
    """
}

private func colorGraphResults() -> [String: Any] {
    let source = colorGraph()
    let typed = preparedSampler(source)
    let slots = SceneAuthoredShaderColorMixGraphAnalyzer.straightColorInputSlots(
        vertexSource: vertexSource, fragmentSource: colorGraph(leaf: "g_Texture5")
    ).sorted()
    let rejected = [
        "alphaWrite": colorGraph("color.a *= gain;"),
        "vectorScale": colorGraph("color.rgb *= vec3(gain);"),
        "conditional": colorGraph("if (gain > 0.0) color.rgb *= gain;"),
        "carrierDataRead": colorGraph(extra: "float extracted = color.r;"),
        "extraSample": colorGraph(extra: "float extracted = texSample2D(g_Texture3, vec2(0.4)).r;"),
        "alphaDataRead": colorGraph(extra: "float extracted = color.a;"),
        "wholeMutation": colorGraph(extra: "color *= gain;"),
        "doubleRGBMutation": colorGraph(extra: "color.xyz *= gain;"),
        "helperEscape": colorGraph(extra: "mutate(color);")
            + "void mutate(inout vec4 value) { value.a = 0.0; }",
        "nestedLeafSample": colorGraph().replacingOccurrences(
            of: "vec2(0.2)", with: "texSample2D(g_Texture3, vec2(0.1)).xy"
        ),
    ]
    return [
        "singleSlot": token(typed),
        "multipleSlots": slots,
        "transferUnchanged": SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source) == .unresolved,
        "rejected": rejected.mapValues {
            SceneAuthoredShaderColorMixGraphAnalyzer.straightColorInputSlots(
                vertexSource: vertexSource, fragmentSource: $0
            ).isEmpty
        },
        "metadataPreserved": [
            "noise": token(preparedSampler(colorGraph(metadata: #"// {"material":"noise"}"#))),
            "hidden": token(preparedSampler(colorGraph(metadata: #"// {"hidden":true}"#))),
            "mode": token(preparedSampler(colorGraph(metadata: #"// {"mode":"opacitymask"}"#))),
            "conflict": token(preparedSampler(colorGraph(metadata: #"// {"default":"util/noise"}"#))),
        ],
        "vertexUseRejected": SceneAuthoredShaderColorMixGraphAnalyzer.straightColorInputSlots(
            vertexSource: """
                uniform sampler2D g_Texture3;
                void main() { gl_Position = texSample2D(g_Texture3, vec2(0.0)); }
                """,
            fragmentSource: source
        ).isEmpty,
    ]
}

private func graphPurposeResults() -> [String: String] {
    let identity = SceneAuthoredEffectRenderPlan.TextureIdentity(
        kind: .effectOutput, layerID: 167, effect: nil, name: "own-color-ingress")
    let slot = SceneResolvedMaterialTemplate.TextureSlot(index: 3, candidates: [
        .init(reference: .graph(identity), provenance: .explicitBinding),
    ])
    let color = preparedSampler(colorGraph())!
    func fact(_ sampler: Schema.Sampler) -> String {
        SceneResolvedMaterialTextureSlotPurpose.fact(in: slot,
            candidateOrdinal: 0, sampler: sampler)?.purpose.reportToken ?? "nil"
    }
    func sampler(_ mode: Schema.TextureMode,
                 _ purpose: SceneTextureLoadPurpose?) -> Schema.Sampler {
        .init(name: "g_Texture3", slot: 3, mode: mode, materialKey: nil,
            isHidden: true, defaultTexture: nil, readinessCombo: nil,
            channelUse: .wholeVector, sourceProvenPurpose: purpose)
    }
    return [
        "sourceColorPurpose": color.sourceProvenPurpose?.reportToken ?? "nil",
        "sourceColorFact": fact(color),
        "nominalUnprovenColor": fact(sampler(.regular, nil)),
        "preservedConflict": fact(sampler(.regular, .preservedChannels)),
        "mask": fact(sampler(.opacityMask, .mask)),
        "explicitMaskConflictsWithColor": fact(sampler(.opacityMask, .straightAlbedo)),
    ]
}

private func syntaxReuseResults() throws -> [String: Any] {
    let source = fragment(body: """
        vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
        gl_FragColor = vec4(color, 1.0);
        """)
    guard case let .accepted(prepared) = SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: contract(source), combos: [:], textureReadiness: [3: true]
    ) else { throw NSError(domain: "reuse-fixture", code: 1) }
    func projection(vertex: String? = nil, fragment: String? = nil) throws -> String {
        token(try Schema.activeSamplers(
            prepared, activeNames: ["g_Texture3"],
            analysisVertexSource: vertex, analysisFragmentSource: fragment
        )[3])
    }
    let scalar = fragment(body: """
        float signal = texSample2D(g_Texture3, vec2(0.2)).r;
        gl_FragColor = vec4(signal);
        """)
    let loops = fragment(body: """
        vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
        while (color.x > 0.0) { color *= 0.5; }
        gl_FragColor = vec4(color, 1.0);
        """)
    let overrides = try [projection(), projection(fragment: scalar), projection()]
    let many = (0..<8).map { "uniform sampler2D g_Texture\($0);" }.joined(separator: "\n")
        + "\nvoid main() {\n"
        + (0..<8).map {
            "vec3 color\($0) = texSample2D(g_Texture\($0), vec2(0.2)).rgb;"
        }.joined(separator: "\n")
        + "\ngl_FragColor = vec4("
        + (0..<8).map { "color\($0)" }.joined(separator: " + ") + ", 1.0);\n}"
    guard case let .accepted(manyPrepared) = SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: contract(many), combos: [:], textureReadiness: [:]
    ) else { throw NSError(domain: "reuse-fixture", code: 2) }
    let manySamplers = try Schema.activeSamplers(
        manyPrepared, activeNames: Set((0..<8).map { "g_Texture\($0)" })
    )
    let invalidSources = [
        ("void main( {", source), (vertexSource, "void main( {"), (vertexSource, loops),
    ]
    let invalid = try invalidSources.map { vertex, fragment in
        let result = try Schema.activeSamplers(
            prepared, activeNames: ["g_Texture3"],
            analysisVertexSource: vertex, analysisFragmentSource: fragment
        )
        return token(result[3])
    }
    let empty = try Schema.activeSamplers(prepared, activeNames: [])
    return ["successiveOverrides": overrides, "invalid": invalid,
            "multiple": (0..<8).map { token(manySamplers[$0]) }, "emptyCount": empty.count]
}

private func alphaRGBSource(three: Bool = false, helper: Bool = false) -> String {
    let join = helper ? "JoinRGB(0, canvas.rgb, picture.rgb, amount)"
        : "mix(canvas.rgb, picture.rgb, amount)"
    let helperSource = helper ? """
        vec3 JoinRGB(int style, vec3 lower, vec3 upper, float coverage) {
            return mix(lower, upper, coverage);
        }
        """ : ""
    return """
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    \(three ? "uniform sampler2D g_Texture3;" : "")
    uniform float gain;
    \(helperSource)
    void main() {
        vec4 canvas = texSample2D(g_Texture0, vec2(0.2));
        vec4 picture = texSample2D(g_Texture1, vec2(0.8));
        \(three ? "vec4 behind = texSample2D(g_Texture3, vec2(0.2)); canvas.rgb = mix(behind.rgb, canvas.rgb, canvas.a);" : "")
        float amount = picture.a * gain;
        canvas.rgb = \(join);
        gl_FragColor = canvas;
    }
    """
}

private func alphaRGBPurposeResults() -> [String: Any] {
    typealias Template = SceneResolvedMaterialTemplate
    func samplers(_ source: String, vertex: String = vertexSource) -> [Int: Schema.Sampler] {
        guard case let .accepted(prepared) = SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: contract(source, vertex: vertex), combos: [:],
            textureReadiness: Dictionary(uniqueKeysWithValues: (0..<8).map { ($0, true) })
        ) else { return [:] }
        return (try? Schema.activeSamplers(prepared)) ?? [:]
    }
    func fact(_ sampler: Schema.Sampler?, _ reference: Template.TextureReference,
              lower: Template.TextureReference? = nil) -> String {
        guard let sampler else { return "missing" }
        var candidates: [Template.TextureCandidate] = lower.map {
            [.init(reference: $0, provenance: .material)]
        } ?? []
        candidates.append(.init(reference: reference, provenance: .userTexture))
        return SceneResolvedMaterialTextureSlotPurpose.fact(in: .init(
            index: sampler.slot, candidates: candidates),
            candidateOrdinal: candidates.count - 1, sampler: sampler)?.purpose.reportToken ?? "nil"
    }
    let asset = Template.TextureReference.asset(customPath)
    let renamedAsset = Template.TextureReference.asset(SceneVFSAssetPath("other/renamed-colors.png")!)
    let user = Template.TextureReference.userProperty(.init(key: "_1"))
    let renamedUser = Template.TextureReference.userProperty(.init(key: "_anotherImage"))
    let graph = Template.TextureReference.graph(.init(kind: .effectOutput,
        layerID: 901, effect: nil, name: "independent-input"))
    let named = Template.TextureReference.provider(.namedLayerTarget(
        .init(providerLayerID: 902, variant: .primary)))
    let two = alphaRGBSource()
    let three = alphaRGBSource(three: true)
    let renamed = alphaRGBSource(three: true, helper: true)
        .replacingOccurrences(of: "canvas", with: "retained")
        .replacingOccurrences(of: "picture", with: "replacement")
        .replacingOccurrences(of: "behind", with: "background")
        .replacingOccurrences(of: "amount", with: "coverage")
        .replacingOccurrences(of: "JoinRGB", with: "RenamedJoin")
        .replacingOccurrences(of: "g_Texture0", with: "g_Texture4")
        .replacingOccurrences(of: "g_Texture1", with: "g_Texture6")
        .replacingOccurrences(of: "g_Texture3", with: "g_Texture7")
    let variants = ["two": two, "three": three,
        "helper": alphaRGBSource(three: true, helper: true),
        "lerp": three.replacingOccurrences(of: "mix(", with: "lerp("),
        "renamed": renamed]
    let positive = variants.mapValues { source -> [String: Any] in
        let typed = samplers(source)
        let slots = typed.keys.sorted()
        return ["slots": slots,
            "sourcePurposes": slots.map { typed[$0]?.sourceProvenPurpose?.reportToken ?? "nil" },
            "assets": slots.map { fact(typed[$0], asset) },
            "users": slots.map { fact(typed[$0], user) },
            "renamedAssets": slots.map { fact(typed[$0], renamedAsset) },
            "renamedUsers": slots.map { fact(typed[$0], renamedUser) },
            "transfer": SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source)
                == .straightAlphaPreserving(textureSlot: source == renamed ? 4 : 0)]
    }
    let base = samplers(three)[1]
    let metadata = ["mask": #"// {"mode":"opacitymask"}"#,
        "normal": #"// {"material":"normal"}"#,
        "noiseDefault": #"// {"default":"util/noise"}"#,
        "internalDefault": #"// {"default":"_rt_unproven"}"#]
    let declared = metadata.mapValues { annotation -> [String] in
        let typed = samplers(three.replacingOccurrences(of: "uniform sampler2D g_Texture1;",
            with: "uniform sampler2D g_Texture1; " + annotation))[1]
        return [typed?.sourceProvenPurpose?.reportToken ?? "nil", fact(typed, asset), fact(typed, user)]
    }
    let rejected = [
        "rgbAsWeight": two.replacingOccurrences(of: "picture.a * gain", with: "picture.r * gain"),
        "extraRGBRead": two.replacingOccurrences(of: "gl_FragColor = canvas;",
            with: "vec3 leaked = picture.rgb; gl_FragColor = canvas;"),
        "extraAlphaRead": two.replacingOccurrences(of: "gl_FragColor = canvas;",
            with: "float leaked = picture.a; gl_FragColor = canvas;"),
        "extraSample": two.replacingOccurrences(of: "gl_FragColor = canvas;",
            with: "vec4 leaked = texSample2D(g_Texture1, vec2(0.4)); gl_FragColor = canvas;"),
    ].mapValues { source -> [String] in
        let typed = samplers(source)[1]
        return [typed?.sourceProvenPurpose?.reportToken ?? "nil", fact(typed, asset), fact(typed, user)]
    }
    let sampledVertex = """
        uniform sampler2D g_Texture1;
        void main() { gl_Position = texSample2D(g_Texture1, vec2(0.2)); }
        """
    return ["positive": positive, "declared": declared, "rejected": rejected,
        "vertexUse": fact(samplers(two, vertex: sampledVertex)[1], asset),
        "roles": ["graph": fact(base, graph), "named": fact(base, named),
            "environment": fact(base, .provider(.sceneEnvironment)),
            "backgroundNotStraight": fact(base, .provider(.sceneBackground(consumerLayerID: 901))),
            "registeredNormalConflict": fact(base, .asset(registeredNormalPath)),
            "lowerRegisteredConflict": fact(base, user, lower: .asset(registeredNormalPath)),
            "lowerUnknownColor": fact(base, user, lower: renamedAsset)]]
}

@main
private enum Main {
    static func main() throws {
        let direct = fragment(
            metadata: #"// {"material":"griadient"}"#,
            body: """
            vec3 color = texSample2D(g_Texture3, vec2(0.2, 0.8)).rgb;
            gl_FragColor = vec4(color, 1.0);
            """
        )
        let xyz = fragment(
            metadata: #"// {"material":"editorGradient"}"#,
            body: """
            vec3 first = texture2D(g_Texture3, vec2(0.2)).xyz;
            vec3 second = texSample2D(g_Texture3, vec2(0.8)).rgb;
            gl_FragColor = vec4(first + second, 1.0);
            """
        )
        let results: [String: Any] = [
            "alphaRGBPurpose": alphaRGBPurposeResults(),
            "syntaxReuse": try syntaxReuseResults(),
            "graphPurpose": graphPurposeResults(),
            "colorGraph": colorGraphResults(),
            "positive": [
                "typoKey": token(preparedSampler(direct)),
                "renamedKey": token(preparedSampler(xyz)),
                "pathIndependent": token(
                    preparedSampler(direct), path: registeredNormalPath
                ),
                "knownAlbedo": token(preparedSampler(fragment(
                    metadata: #"// {"material":"albedo"}"#,
                    body: """
                    vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
                    gl_FragColor = vec4(color, 1.0);
                    """
                ))),
            ],
            "negative": [
                "whole": token(preparedSampler(fragment(body: """
                    vec4 color = texSample2D(g_Texture3, vec2(0.2));
                    gl_FragColor = color;
                    """))),
                "scalar": token(preparedSampler(fragment(body: """
                    float value = texSample2D(g_Texture3, vec2(0.2)).r;
                    gl_FragColor = vec4(value);
                    """))),
                "alpha": token(preparedSampler(fragment(body: """
                    float value = texSample2D(g_Texture3, vec2(0.2)).a;
                    gl_FragColor = vec4(value);
                    """))),
                "mixed": token(preparedSampler(fragment(body: """
                    vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
                    float value = texSample2D(g_Texture3, vec2(0.8)).r;
                    gl_FragColor = vec4(color * value, 1.0);
                    """))),
                "arithmetic": token(preparedSampler(fragment(body: """
                    vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb * 2.0;
                    gl_FragColor = vec4(color, 1.0);
                    """))),
                "hidden": token(preparedSampler(fragment(
                    metadata: #"// {"hidden":true}"#,
                    body: """
                    vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
                    gl_FragColor = vec4(color, 1.0);
                    """
                ))),
                "mode": token(preparedSampler(fragment(
                    metadata: #"// {"mode":"opacitymask"}"#,
                    body: """
                    vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
                    gl_FragColor = vec4(color, 1.0);
                    """
                ))),
                "noiseMaterial": token(preparedSampler(fragment(
                    metadata: #"// {"material":"noise"}"#,
                    body: """
                    vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
                    gl_FragColor = vec4(color, 1.0);
                    """
                ))),
                "defaultConflict": token(preparedSampler(fragment(
                    metadata: #"// {"default":"util/noise"}"#,
                    body: """
                    vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
                    gl_FragColor = vec4(color, 1.0);
                    """
                ))),
                "internalDefault": token(preparedSampler(fragment(
                    metadata: #"// {"default":"_rt_internal"}"#,
                    body: """
                    vec3 color = texSample2D(g_Texture3, vec2(0.2)).rgb;
                    gl_FragColor = vec4(color, 1.0);
                    """
                ))),
                "vertexUse": proof(
                    direct,
                    vertex: """
                    uniform sampler2D g_Texture3;
                    attribute vec3 a_Position;
                    void main() {
                        gl_Position = vec4(
                            texSample2D(g_Texture3, vec2(0.2)).xyz, 1.0
                        );
                    }
                    """
                ),
                "helperUse": proof(fragment(
                    body: """
                    vec3 helper() {
                        return texSample2D(g_Texture3, vec2(0.2)).rgb;
                    }
                    void main() {
                        gl_FragColor = vec4(helper(), 1.0);
                    }
                    """
                )),
                "aliasUse": proof(fragment(body: """
                    sampler2D alias = g_Texture3;
                    vec3 color = texSample2D(alias, vec2(0.2)).rgb;
                    gl_FragColor = vec4(color, 1.0);
                    """)),
                "nestedSample": proof(fragment(body: """
                    vec3 color = texSample2D(
                        g_Texture3,
                        texSample2D(g_Texture3, vec2(0.2)).rgb.xy
                    ).rgb;
                    gl_FragColor = vec4(color, 1.0);
                    """)),
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: results,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneSourceProvenStraightColorPurposeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-source-proven-straight-color-purpose-"
        )
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "source-proven-straight-color-purpose-test"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        cls.source_manifest = {}
        frozen_sources = []
        for source in SWIFT_SOURCES:
            relative = source.relative_to(REPOSITORY_ROOT)
            payload = source.read_bytes()
            frozen = root / "sources" / relative
            frozen.parent.mkdir(parents=True, exist_ok=True)
            frozen.write_bytes(payload)
            frozen_sources.append(frozen)
            cls.source_manifest[str(relative)] = hashlib.sha256(payload).hexdigest()
        cls.source_manifest["Support.swift"] = hashlib.sha256(SUPPORT.encode()).hexdigest()
        cls.source_manifest["Harness.swift"] = hashlib.sha256(HARNESS.encode()).hexdigest()
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        started = time.monotonic()
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-Onone",
                "-whole-module-optimization", "-num-threads", "2", "-parse-as-library",
                str(support), *(str(path) for path in frozen_sources), str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO", "-module-cache-path",
                str(root / "module-cache"), "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            timeout=180,
        )
        cls.compile_seconds = time.monotonic() - started
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        started = time.monotonic()
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            timeout=30,
        )
        cls.execute_seconds = time.monotonic() - started
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_unknown_editor_keys_are_source_typed(self) -> None:
        self.assertEqual(
            self.result["positive"],
            {
                "knownAlbedo": "unproven/nil/straight-albedo",
                "pathIndependent": "unproven/straight-albedo/nil",
                "renamedKey": "unproven/straight-albedo/straight-albedo",
                "typoKey": "unproven/straight-albedo/straight-albedo",
            },
            self.result,
        )

    def test_alpha_preserving_rgb_graph_projects_exact_asset_and_user_purposes(self) -> None:
        result = self.result["alphaRGBPurpose"]
        for name, value in result["positive"].items():
            with self.subTest(variant=name):
                slots = [4, 6, 7] if name == "renamed" else [0, 1] if name == "two" else [0, 1, 3]
                self.assertEqual(value["slots"], slots)
                for field in ["sourcePurposes", "assets", "users", "renamedAssets", "renamedUsers"]:
                    self.assertEqual(value[field], ["straight-albedo"] * len(slots), (name, field))
                self.assertTrue(value["transfer"])

    def test_alpha_rgb_graph_keeps_rt_roles_and_refuses_conflicting_or_extra_uses(self) -> None:
        result = self.result["alphaRGBPurpose"]
        self.assertEqual(result["roles"], {
            "graph": "premultiplied-color", "named": "premultiplied-color",
            "environment": "premultiplied-color", "backgroundNotStraight": "nil",
            "registeredNormalConflict": "nil", "lowerRegisteredConflict": "nil",
            "lowerUnknownColor": "straight-albedo",
        })
        self.assertEqual(result["declared"], {
            "mask": ["nil", "mask", "mask"], "normal": ["nil", "normal", "normal"],
            "noiseDefault": ["nil", "noise", "nil"], "internalDefault": ["nil", "nil", "nil"],
        })
        for name, value in result["rejected"].items():
            with self.subTest(rejected=name):
                self.assertEqual(value, ["nil", "nil", "nil"])
        self.assertEqual(result["vertexUse"], "nil")

    def test_conflicts_and_indirect_uses_stay_closed(self) -> None:
        self.assertEqual(
            self.result["negative"],
            {
                "aliasUse": False,
                "arithmetic": "unproven/nil/nil",
                "defaultConflict": "unproven/nil/noise",
                "helperUse": False,
                "hidden": "unproven/nil/nil",
                "internalDefault": "unproven/nil/nil",
                "mixed": "unproven/nil/nil",
                "mode": "unproven/nil/mask",
                "nestedSample": False,
                "noiseMaterial": "unproven/nil/noise",
                "scalar": "redOnly/nil/nil",
                "alpha": "alphaOnly/nil/nil",
                "vertexUse": False,
                "whole": "wholeVector/nil/nil",
            },
            self.result,
        )

    def test_complete_vector_color_graph_gets_purpose_without_output_reclassification(self) -> None:
        graph = self.result["colorGraph"]
        self.assertEqual(graph["singleSlot"], "wholeVector/straight-albedo/straight-albedo")
        self.assertEqual(graph["multipleSlots"], [3, 5])
        self.assertTrue(graph["transferUnchanged"])

    def test_color_graph_rejects_data_alpha_control_flow_and_escaped_uses(self) -> None:
        graph = self.result["colorGraph"]
        for name, rejected in graph["rejected"].items():
            with self.subTest(case=name):
                self.assertTrue(rejected)
        self.assertTrue(graph["vertexUseRejected"])
        self.assertEqual(graph["metadataPreserved"], {
            "noise": "wholeVector/nil/noise", "hidden": "wholeVector/nil/nil",
            "mode": "wholeVector/nil/mask", "conflict": "wholeVector/nil/noise",
        })

    def test_graph_source_color_keeps_publication_purpose_and_adjacent_roles(self) -> None:
        self.assertEqual(self.result["graphPurpose"], {
            "sourceColorPurpose": "straight-albedo",
            "sourceColorFact": "premultiplied-color",
            "nominalUnprovenColor": "premultiplied-color",
            "preservedConflict": "nil",
            "mask": "mask",
            "explicitMaskConflictsWithColor": "nil",
        })

    def test_same_call_syntax_projection_keeps_overrides_failure_and_slot_isolation(self) -> None:
        self.assertEqual(self.result["syntaxReuse"], {
            "successiveOverrides": [
                "unproven/straight-albedo/straight-albedo",
                "redOnly/nil/nil",
                "unproven/straight-albedo/straight-albedo",
            ],
            "invalid": ["unproven/nil/nil"] * 3,
            "multiple": ["unproven/straight-albedo/straight-albedo"] * 8,
            "emptyCount": 0,
        })


if __name__ == "__main__":
    unittest.main()
