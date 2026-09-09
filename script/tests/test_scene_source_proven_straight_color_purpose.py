#!/usr/bin/env python3

"""Strict source-derived straight-color sampler purpose admission."""

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
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "source-proven-straight-color-purpose-test"
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
                "alpha": "unproven/nil/nil",
                "vertexUse": False,
                "whole": "wholeVector/nil/nil",
            },
            self.result,
        )


if __name__ == "__main__":
    unittest.main()
