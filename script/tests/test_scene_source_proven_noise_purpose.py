#!/usr/bin/env python3

"""Source-proven stock scalar-noise purpose stays structural and fail-closed."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
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

private func contract(
    samplerName: String = "g_Texture2",
    defaultPath: String = "util/clouds_256",
    material: String = "albedo",
    declarations: String = "",
    body: String
) -> SceneShaderContract {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() {
        v_TexCoord = a_TexCoord;
        gl_Position = vec4(a_Position, 1.0);
    }
    """
    let fragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D \(samplerName); // {"material":"\(material)","default":"\(defaultPath)"}
    \(declarations)
    void main() {
        \(body)
    }
    """
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
        stage(.vertex, "fixture/noise.vert", vertex),
        stage(.fragment, "fixture/noise.frag", fragment),
    ]
    let dependency = SceneShaderStableDigest.hash(Data((vertex + fragment).utf8))
    return .init(
        identity: "fixture/source-proven-noise",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: dependency,
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "fixture/noise.vert"),
                .init(label: "fragment", virtualPath: "fixture/noise.frag"),
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
            dependencySHA256: dependency
        )
    )
}

private func slot(_ samplerName: String) -> Int {
    Int(samplerName.dropFirst("g_Texture".count))!
}

private func activeSampler(
    samplerName: String = "g_Texture2",
    defaultPath: String = "util/clouds_256",
    material: String = "albedo",
    declarations: String = "",
    body: String
) -> Schema.Sampler? {
    let shader = contract(
        samplerName: samplerName,
        defaultPath: defaultPath,
        material: material,
        declarations: declarations,
        body: body
    )
    let samplerSlot = slot(samplerName)
    guard case let .accepted(prepared) =
        SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader,
            combos: [:],
            textureReadiness: [samplerSlot: true]
        ) else { return nil }
    return try? Schema.activeSamplers(prepared)[samplerSlot]
}

private func bootstrapSampler(
    body: String = "gl_FragColor = vec4(texSample2D(g_Texture2, v_TexCoord).r);"
) -> Schema.Sampler {
    let shader = contract(
        body: body
    )
    let template = SceneResolvedMaterialTemplate.validated(
        textureSlots: Array(repeating: nil, count: 8),
        combos: [],
        uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )!,
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: []
        ),
        shaderContract: shader,
        diagnosticProvenance: .init(
            nodeIndex: 0,
            authoredShaderPath: shader.identity,
            contractIdentity: shader.identity,
            contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
    return try! Schema.unconditionalSamplers(template)[2]!
}

private func token(
    _ sampler: Schema.Sampler?,
    path: String = "util/clouds_256"
) -> String {
    guard let sampler,
          let asset = SceneVFSAssetPath(path) else { return "missing" }
    let purpose = sampler.purpose(for: .asset(asset))?.reportToken ?? "nil"
    return "\(sampler.channelUse.rawValue)/\(purpose)"
}

@main
private enum Main {
    static func main() throws {
        let directBody = """
        float firstSignal = texSample2D(g_Texture2, v_TexCoord).r;
        float secondSignal = texture2D(g_Texture2, v_TexCoord * 0.5).x;
        gl_FragColor = vec4(firstSignal * secondSignal);
        """
        let renamedBody = """
        float coarse = texture2D(g_Texture5, v_TexCoord).x;
        float fine = texSample2D(g_Texture5, v_TexCoord * 2.0).r;
        gl_FragColor = vec4(coarse * fine);
        """
        let wholeBody = """
        vec4 signal = texSample2D(g_Texture2, v_TexCoord);
        gl_FragColor = signal;
        """
        let mixedBody = """
        vec2 signal = texSample2D(g_Texture2, v_TexCoord).rg;
        gl_FragColor = vec4(signal, 0.0, 1.0);
        """
        let greenBody = """
        float signal = texSample2D(g_Texture2, v_TexCoord).g;
        gl_FragColor = vec4(signal);
        """
        let invalid = SceneAuthoredShaderTextureChannelAnalyzer.analyze(
            samplerName: "g_Texture2",
            vertexSource: "void main() { gl_Position = vec4(0.0); }",
            fragmentSource: "void main( { texSample2D(g_Texture2, vec2(0.0)).r; }"
        )
        let lodBody = """
        float firstSignal = texSample2DLod(g_Texture2, (v_TexCoord * 0.5), g_Mip).r;
        float secondSignal = texture2DLod(g_Texture2, v_TexCoord * 2.0, 1.0).x;
        gl_FragColor = vec4(firstSignal * secondSignal);
        """
        let lodRenamed = lodBody
            .replacingOccurrences(of: "g_Texture2", with: "g_Texture5")
            .replacingOccurrences(of: "firstSignal", with: "coarseField")
            .replacingOccurrences(of: "secondSignal", with: "fineField")
        var lod: [String: String] = [
            "direct": token(activeSampler(declarations: "uniform float g_Mip;", body: lodBody)),
            "renamed": token(activeSampler(samplerName: "g_Texture5", defaultPath: "util/perlin_256",
                declarations: "uniform float g_Mip;", body: lodRenamed), path: "util/perlin_256"),
            "bootstrap": token(bootstrapSampler(body: lodBody.replacingOccurrences(of: "g_Mip", with: "0.0"))),
            "adjacentPath": token(activeSampler(declarations: "uniform float g_Mip;", body: lodBody), path: "util/clouds_257"),
            "otherRegisteredRole": token(activeSampler(declarations: "uniform float g_Mip;", body: lodBody), path: "effects/waterripplenormal"),
        ]
        for sample in ["texSample2DLod", "texture2DLod"] {
            let call = "\(sample)(g_Texture2, v_TexCoord, 0.0)"
            for (name, body) in [
                ("whole", "gl_FragColor = \(call);"),
                ("alias", "vec4 value = \(call); gl_FragColor = vec4(value.r);"),
                ("rgb", "vec3 value = \(call).rgb; gl_FragColor = vec4(value, 1.0);"),
                ("green", "gl_FragColor = vec4(\(call).g);"),
                ("redGreen", "gl_FragColor = vec4(\(call).rg, 0.0, 1.0);"),
                ("alpha", "gl_FragColor = vec4(\(call).a);"),
                ("mixed", "float value = \(call).r + \(call).b; gl_FragColor = vec4(value);"),
                ("missingLevel", "gl_FragColor = vec4(\(sample)(g_Texture2, v_TexCoord).r);"),
                ("extraArgument", "gl_FragColor = vec4(\(sample)(g_Texture2, v_TexCoord, 0.0, 1.0).r);"),
                ("indirectSampler", "gl_FragColor = vec4(\(sample)((g_Texture2), v_TexCoord, 0.0).r);"),
            ] {
                lod[sample + ":" + name] = token(activeSampler(body: body))
            }
            lod[sample + ":authoredHelper"] = token(activeSampler(
                declarations: "vec4 \(sample)(sampler2D source, vec2 uv, float mip) { return vec4(uv, mip, 1.0); }",
                body: "gl_FragColor = vec4(\(call).r);"
            ))
        }
        var ordinaryBias: [String: String] = [:]
        for sample in ["texSample2D", "texture2D"] {
            let call = "\(sample)(g_Texture2, v_TexCoord, 0.5)"
            for (name, body) in [
                ("red", "gl_FragColor = vec4(\(call).r);"),
                ("green", "gl_FragColor = vec4(\(call).g);"),
                ("whole", "gl_FragColor = \(call);"),
                ("alpha", "gl_FragColor = vec4(\(call).a);"),
            ] {
                ordinaryBias[sample + ":" + name] = token(activeSampler(body: body))
            }
        }
        let results: [String: Any] = [
            "lod": lod,
            "ordinaryBias": ordinaryBias,
            "positive": [
                "direct": token(activeSampler(body: directBody)),
                "renamed": token(activeSampler(
                    samplerName: "g_Texture5",
                    body: renamedBody
                )),
                "bootstrap": token(bootstrapSampler()),
            ],
            "negative": [
                "wholeVector": token(activeSampler(body: wholeBody)),
                "mixedChannel": token(activeSampler(body: mixedBody)),
                "greenChannel": token(activeSampler(body: greenBody)),
                "adjacentPath": token(
                    activeSampler(body: directBody),
                    path: "util/clouds_257"
                ),
                "otherRegisteredRole": token(
                    activeSampler(body: directBody),
                    path: "effects/waterripplenormal"
                ),
                "invalidSource": invalid.rawValue,
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


class SceneSourceProvenNoisePurposeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-source-proven-noise-purpose-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "source-proven-noise-purpose-test"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support), *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO", "-module-cache-path",
                str(root / "module-cache"), "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_direct_red_stock_noise_is_source_proven(self) -> None:
        self.assertEqual(
            self.result["positive"],
            {
                "direct": "redOnly/noise",
                "renamed": "redOnly/noise",
                "bootstrap": "redOnly/noise",
            },
            self.result,
        )

    def test_ambiguous_or_different_inputs_do_not_gain_noise_role(self) -> None:
        self.assertEqual(
            self.result["negative"],
            {
                "wholeVector": "wholeVector/nil",
                "mixedChannel": "redGreenOnly/nil",
                "greenChannel": "greenOnly/nil",
                "adjacentPath": "redOnly/straight-albedo",
                "otherRegisteredRole": "redOnly/nil",
                "invalidSource": "unproven",
            },
            self.result,
        )

    def test_lod_projection_shares_noise_role_without_tightening_ordinary_samples(self) -> None:
        expected = {
            "direct": "redOnly/noise",
            "renamed": "redOnly/noise",
            "bootstrap": "redOnly/noise",
            "adjacentPath": "redOnly/straight-albedo",
            "otherRegisteredRole": "redOnly/nil",
        }
        for sample in ("texSample2DLod", "texture2DLod"):
            expected.update({sample + ":" + name: token for name, token in {
                "whole": "wholeVector/nil", "alias": "wholeVector/nil",
                "rgb": "unproven/nil", "green": "greenOnly/nil",
                "redGreen": "redGreenOnly/nil", "alpha": "alphaOnly/nil",
                "mixed": "unproven/nil", "missingLevel": "unproven/nil",
                "extraArgument": "unproven/nil", "indirectSampler": "unproven/nil",
                "authoredHelper": "unproven/nil",
            }.items()})
        self.assertEqual(self.result["lod"], expected, self.result)
        self.assertEqual(self.result["ordinaryBias"], {
            sample + ":" + name: token
            for sample in ("texSample2D", "texture2D")
            for name, token in {
                "red": "redOnly/noise", "green": "greenOnly/nil",
                "whole": "wholeVector/nil", "alpha": "unproven/nil",
            }.items()
        }, self.result)


if __name__ == "__main__":
    unittest.main()
