#!/usr/bin/env python3

"""Source-proven phase/normal auxiliaries enter typed material slots."""

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
private let customPath = SceneVFSAssetPath("fixtures/unseen/auxiliary")!

private func contract(_ fragment: String) -> SceneShaderContract {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec4 v_TexCoord;
    void main() {
        v_TexCoord = a_TexCoord.xyxy;
        gl_Position = vec4(a_Position, 1.0);
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
        stage(.vertex, "fixture/auxiliary.vert", vertex),
        stage(.fragment, "fixture/auxiliary.frag", fragment),
    ]
    let digest = SceneShaderStableDigest.hash(Data((vertex + fragment).utf8))
    return .init(
        identity: "fixture/source-proven-auxiliary",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: digest,
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "fixture/auxiliary.vert"),
                .init(label: "fragment", virtualPath: "fixture/auxiliary.frag"),
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

private func activeSamplers(_ fragment: String) -> [Int: Schema.Sampler] {
    guard case let .accepted(prepared) =
        SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: contract(fragment),
            combos: [:],
            textureReadiness: Dictionary(
                uniqueKeysWithValues: (0..<8).map { ($0, true) }
            )
        ) else { return [:] }
    return (try? Schema.activeSamplers(prepared)) ?? [:]
}

private func token(_ sampler: Schema.Sampler?) -> String {
    guard let sampler else { return "missing" }
    let source = sampler.sourceProvenPurpose?.reportToken ?? "nil"
    let resolved = sampler.purpose(for: .asset(customPath))?.reportToken ?? "nil"
    return "\(sampler.channelUse.rawValue)/\(source)/\(resolved)"
}

private func phaseFragment(
    slot: Int = 2,
    metadata: String = "",
    projection: String = "r",
    thresholds: String = "0.2, 0.8",
    extraUse: String = ""
) -> String {
    """
    varying vec4 v_TexCoord;
    uniform sampler2D g_Texture0; // {"hidden":true}
    uniform sampler2D g_Texture1; // {"mode":"flowmask"}
    uniform sampler2D g_Texture\(slot); \(metadata)
    void main() {
        float selector = texSample2D(
            g_Texture\(slot), v_TexCoord.xy * 2.0
        ).\(projection);
        \(extraUse)
        vec4 base = texSample2D(g_Texture0, v_TexCoord.xy);
        vec4 shifted = texSample2D(g_Texture0, v_TexCoord.zw);
        gl_FragColor = mix(
            base, shifted, smoothstep(\(thresholds), selector)
        );
    }
    """
}

private func normalFragment(
    slot: Int = 3,
    metadata: String = "",
    projection: String = "xyz",
    scale: String = "2",
    thirdSample: String = "",
    normalUse: String = "normal.xy"
) -> String {
    """
    varying vec4 v_TexCoord;
    uniform sampler2D g_Texture0; // {"hidden":true}
    uniform sampler2D g_Texture\(slot); \(metadata)
    void main() {
        vec3 firstVector = texSample2D(
            g_Texture\(slot), v_TexCoord.xy
        ).\(projection) * \(scale) - 1;
        vec3 secondVector = texture2D(
            g_Texture\(slot), v_TexCoord.zw
        ).\(projection) * \(scale) - 1;
        \(thirdSample)
        vec3 normal = normalize(vec3(
            firstVector.xy + secondVector.xy, firstVector.z
        ));
        vec2 coordinate = v_TexCoord.xy + \(normalUse) * 0.1;
        gl_FragColor = texSample2D(g_Texture0, coordinate);
    }
    """
}

private func dataChannelFragment(
    slot: Int = 2,
    metadata: String = "",
    projection: String = "ra",
    extraUse: String = "",
    weightPreparation: String = "",
    weightFactor: String = "1.0",
    weightSite: String = "mixWeight"
) -> String {
    let terminal: String
    switch weightSite {
    case "mixWeight":
        terminal = """
        vec4 base = texSample2D(g_Texture0, v_TexCoord.xy);
        gl_FragColor = mix(base, vec4(1.0), blend);
        """
    case "colorOperand":
        terminal = """
        vec4 base = texSample2D(g_Texture0, v_TexCoord.xy);
        gl_FragColor = mix(vec4(blendSample.x), base, blend);
        """
    case "outputAlpha":
        terminal = """
        vec4 base = texSample2D(g_Texture0, v_TexCoord.xy);
        gl_FragColor = vec4(base.rgb, blendSample.g);
        """
    default:
        terminal = weightSite
    }
    return """
    varying vec4 v_TexCoord;
    uniform sampler2D g_Texture0; // {"hidden":true}
    uniform sampler2D g_Texture\(slot); \(metadata)
    void main() {
        vec2 blendSample = texSample2D(
            g_Texture\(slot), v_TexCoord.xy
        ).\(projection);
        \(weightPreparation)
        float blend = saturate(blendSample.x * blendSample.y * \(weightFactor));
        \(extraUse)
        \(terminal)
    }
    """
}

@main
private enum Main {
    static func main() throws {
        let phase = activeSamplers(phaseFragment())
        let renamedPhase = activeSamplers(phaseFragment(slot: 5))
        let normal = activeSamplers(normalFragment())
        let renamedNormal = activeSamplers(normalFragment(slot: 6))

        let results: [String: Any] = [
            "positive": [
                "phase": token(phase[2]),
                "renamedPhase": token(renamedPhase[5]),
                "normal": token(normal[3]),
                "renamedNormal": token(renamedNormal[6]),
                "dataChannel": token(activeSamplers(dataChannelFragment())[2]),
                "renamedDataChannel": token(activeSamplers(
                    dataChannelFragment(slot: 7)
                )[7]),
                "dataChannelUninitializedLocal": token(activeSamplers(
                    dataChannelFragment(extraUse: "float scratch;")
                )[2]),
                "dataChannelIndependentScalarWeight": token(activeSamplers(
                    dataChannelFragment(
                        weightPreparation: """
                            float radius = distance(v_TexCoord.xy, vec2(0.5));
                            float edge = 1.0 - smoothstep(0.2, 0.5, radius);
                        """,
                        weightFactor: "edge"
                    )
                )[2]),
                "dataChannelWithDefault": token(activeSamplers(dataChannelFragment(
                    metadata: #"// {"default":"particle/halo_6"}"#
                ))[2]),
                "dataChannelWithUnregisteredDefault": token(activeSamplers(
                    dataChannelFragment(
                        metadata: #"// {"default":"pattern/unknown_art"}"#
                    )
                )[2]),
            ],
            "negative": [
                "phaseGreen": token(activeSamplers(
                    phaseFragment(projection: "g")
                )[2]),
                "phaseDynamicThreshold": token(activeSamplers(
                    phaseFragment(thresholds: "v_TexCoord.x, 0.8")
                )[2]),
                "phaseExtraUse": token(activeSamplers(phaseFragment(
                    extraUse: "float copied = selector;"
                ))[2]),
                "phaseMode": token(activeSamplers(phaseFragment(
                    metadata: #"// {"mode":"opacitymask"}"#
                ))[2]),
                "phaseMaterial": token(activeSamplers(phaseFragment(
                    metadata: #"// {"material":"albedo"}"#
                ))[2]),
                "phaseHidden": token(activeSamplers(phaseFragment(
                    metadata: #"// {"hidden":true}"#
                ))[2]),
                "normalProjection": token(activeSamplers(normalFragment(
                    projection: "xy"
                ))[3]),
                "normalDecode": token(activeSamplers(normalFragment(
                    scale: "1.5"
                ))[3]),
                "normalThirdSample": token(activeSamplers(normalFragment(
                    thirdSample: "vec3 thirdVector = texSample2D(g_Texture3, v_TexCoord.xy * 2.0).xyz * 2 - 1;"
                ))[3]),
                "normalOtherUse": token(activeSamplers(normalFragment(
                    normalUse: "normal.z"
                ))[3]),
                "dataChannelWholeVector": token(activeSamplers(
                    dataChannelFragment(projection: "r")
                )[2]),
                "dataChannelColorOperand": token(activeSamplers(
                    dataChannelFragment(weightSite: "colorOperand")
                )[2]),
                "dataChannelOutputAlpha": token(activeSamplers(
                    dataChannelFragment(weightSite: "outputAlpha")
                )[2]),
                "dataChannelBareUse": token(activeSamplers(dataChannelFragment(
                    extraUse: "vec2 vecUse = blendSample;"
                ))[2]),
                "dataChannelColorCall": token(activeSamplers(dataChannelFragment(
                    weightSite: "gl_FragColor = abs(vec4(blendSample.x));"
                ))[2]),
                "dataChannelNestedUnknownWeight": token(activeSamplers(
                    dataChannelFragment(weightSite: """
                        vec4 base = texSample2D(g_Texture0, v_TexCoord.xy);
                        gl_FragColor = mix(base, vec4(1.0), pow(blendSample.x, 2.2));
                    """)
                )[2]),
                "dataChannelAssignedScalarEscape": token(activeSamplers(
                    dataChannelFragment(
                        extraUse: "edge = blendSample.x;",
                        weightPreparation: "float edge = 0.5;",
                        weightFactor: "edge"
                    )
                )[2]),
                "dataChannelCallNamedLikeLocal": token(activeSamplers(
                    dataChannelFragment(
                        weightPreparation: "float pow = pow(blendSample.x, 2.2);",
                        weightFactor: "pow"
                    )
                )[2]),
                "dataChannelShadowedScalarEscape": token(activeSamplers(
                    dataChannelFragment(
                        extraUse: "{ float edge = blendSample.x; }",
                        weightPreparation: "float edge = 0.5;",
                        weightFactor: "edge"
                    )
                )[2]),
                "dataChannelConflictDefault": token(activeSamplers(
                    dataChannelFragment(
                        metadata: #"// {"default":"util/noise"}"#
                    )
                )[2]),
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


class SceneSourceProvenAuxiliaryTexturePurposeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-source-proven-auxiliary-purpose-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "source-proven-auxiliary-purpose-test"
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

    def test_phase_and_normal_dataflows_publish_typed_purpose(self) -> None:
        self.assertEqual(
            self.result["positive"],
            {
                "phase": "redOnly/phase/phase",
                "renamedPhase": "redOnly/phase/phase",
                "normal": "unproven/normal/normal",
                "renamedNormal": "unproven/normal/normal",
                # The juguangdeng dataflow: `.ra` channels become scalar
                # weights and only weight the terminal mix.
                "dataChannel": "unproven/preserved-channels/preserved-channels",
                "renamedDataChannel":
                    "unproven/preserved-channels/preserved-channels",
                "dataChannelUninitializedLocal":
                    "unproven/preserved-channels/preserved-channels",
                "dataChannelIndependentScalarWeight":
                    "unproven/preserved-channels/preserved-channels",
                # A typed stock default keeps registry authority only when it
                # conflicts; unregistered and halo defaults accept the proof.
                "dataChannelWithDefault":
                    "unproven/preserved-channels/preserved-channels",
                "dataChannelWithUnregisteredDefault":
                    "unproven/preserved-channels/preserved-channels",
            },
            self.result,
        )

    def test_ambiguous_or_conflicting_dataflows_remain_unproven(self) -> None:
        self.assertEqual(
            self.result["negative"],
            {
                "phaseGreen": "greenOnly/nil/nil",
                "phaseDynamicThreshold": "redOnly/nil/nil",
                "phaseExtraUse": "redOnly/nil/nil",
                "phaseMode": "redOnly/nil/mask",
                "phaseMaterial": "redOnly/nil/straight-albedo",
                "phaseHidden": "redOnly/nil/nil",
                "normalProjection": "redGreenOnly/nil/nil",
                "normalDecode": "unproven/nil/nil",
                "normalThirdSample": "unproven/nil/nil",
                "normalOtherUse": "unproven/nil/nil",
                # A single-channel projection is a plain scalar read, not a
                # strict channel subset; the data proof does not fire.
                "dataChannelWholeVector": "redOnly/nil/nil",
                # The sampled channels feeding either mixed color operand, or
                # the output alpha, escape the weight-only shape.
                "dataChannelColorOperand": "unproven/nil/nil",
                "dataChannelOutputAlpha": "unproven/nil/nil",
                # A second float initializer joined the closure but the bare
                # vector use of the sample variable escapes component reads.
                "dataChannelBareUse": "unproven/nil/nil",
                "dataChannelColorCall": "unproven/nil/nil",
                "dataChannelNestedUnknownWeight": "unproven/nil/nil",
                "dataChannelAssignedScalarEscape": "unproven/nil/nil",
                "dataChannelCallNamedLikeLocal": "unproven/nil/nil",
                "dataChannelShadowedScalarEscape": "unproven/nil/nil",
                # The stock registry's noise semantics win over the proof.
                "dataChannelConflictDefault": "unproven/nil/noise",
            },
            self.result,
        )


if __name__ == "__main__":
    unittest.main()
