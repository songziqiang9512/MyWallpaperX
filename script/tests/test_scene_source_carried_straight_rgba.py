#!/usr/bin/env python3

"""Source-carried separated RGBA crosses the shared color boundary once."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = scene_swift_sources("authored_shader_frontend_core") + (
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteAuthority.swift",
)


HARNESS = r'''
import Foundation

private let vertex = """
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
"""

private let preservedCarrier = """
uniform sampler2D g_Texture0;
uniform float u_strength;
varying vec2 v_TexCoord;
void main() {
    vec4 carrier = texSample2D(g_Texture0, v_TexCoord);
    vec3 filtered = carrier.rgb + vec3(u_strength);
    carrier.rgb = mix(carrier.rgb, filtered, u_strength);
    gl_FragColor = carrier;
}
"""

private let separated = """
uniform sampler2D g_Texture0;
uniform vec3 u_color;
uniform vec3 u_background_color;
uniform float u_background;
varying vec2 v_TexCoord;
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    vec3 gradient = mix(u_color, u_background_color, v_TexCoord.x);
    vec3 color = gradient;
    float alpha = source.a;
    if (source.a == 0.0) {
        color = u_background_color;
        alpha = u_background;
    }
    gl_FragColor = vec4(color, alpha);
}
"""

private let aliased = """
uniform sampler2D g_Texture0;
uniform vec3 u_color;
uniform float u_amount;
varying vec2 v_TexCoord;
vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {
    return mix(base, (blend), opacity);
}
void main() {
    vec3 color = u_color;
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    color = ApplyBlending(
        0, mix(color.rgb, source.rgb, source.a), color.rgb, u_amount
    );
    float alpha = max(source.a, u_amount);
    gl_FragColor = vec4(color, alpha);
}
"""

private let pulseModeEight = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform sampler2D g_Texture2;
uniform vec3 u_low;
uniform vec3 u_high;
varying vec2 v_TexCoord;
vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {
    return mix(base, vec3(
        blend.r == 1.0 ? blend.r : min(base.r / (1.0 - blend.r), 1.0),
        blend.g == 1.0 ? blend.g : min(base.g / (1.0 - blend.g), 1.0),
        blend.b == 1.0 ? blend.b : min(base.b / (1.0 - blend.b), 1.0)
    ), opacity);
    return mix(base, (blend), opacity);
}
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    vec4 color = source;
    float pulse = texSample2D(g_Texture1, v_TexCoord).r;
    color.rgb = ApplyBlending(8, color.rgb * u_low, color.rgb * u_high, pulse);
    color.a *= pulse;
    float mask = texSample2D(g_Texture2, v_TexCoord).r;
    color = mix(source, color, mask);
    gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);
}
"""

private let scalarDistance = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    float l = v_TexCoord.x - 0.5;
    float p = distance(0.0, l);
    gl_FragColor = vec4(source.rgb * p, source.a);
}
"""

private func transfer(_ source: String) -> String {
    switch SceneAuthoredShaderColorTransferAnalyzer.analyze(
        fragmentSource: source
    ) {
    case let .straightAlpha(slot): "straight-alpha-\(slot)"
    case let .straightAlphaPreserving(slot): "straight-preserving-\(slot)"
    default: "other"
    }
}

private func compiled(_ source: String) -> String? {
    SceneAuthoredShaderFrontend.compile(
        vertexSource: vertex,
        fragmentSource: source
    ).program?.metalSource
}

@main
private enum Harness {
    static func main() throws {
        let premultiplied = separated.replacingOccurrences(
            of: "gl_FragColor = vec4(color, alpha);",
            with: "color *= alpha;\n    gl_FragColor = vec4(color, alpha);"
        )
        let carrierAlphaWrite = preservedCarrier.replacingOccurrences(
            of: "carrier.rgb = mix(carrier.rgb, filtered, u_strength);",
            with: "carrier.rgb = mix(carrier.rgb, filtered, u_strength);\n    carrier.a *= u_strength;"
        )
        let secondSource = separated.replacingOccurrences(
            of: "uniform sampler2D g_Texture0;",
            with: "uniform sampler2D g_Texture0;\nuniform sampler2D g_Texture1;"
        ).replacingOccurrences(
            of: "float alpha = source.a;",
            with: "vec4 other = texSample2D(g_Texture1, v_TexCoord);\n    float alpha = other.a;"
        )
        let preservingProfile =
            SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputStageUniformStraightAlphaPreserving
        let distanceMSL = compiled(scalarDistance) ?? ""
        let result: [String: Any] = [
            "preservedTransfer": transfer(preservedCarrier),
            "separatedTransfer": transfer(separated),
            "aliasedTransfer": transfer(aliased),
            "pulseModeEightTransfer": transfer(pulseModeEight),
            "preservedPremultiplies": compiled(preservedCarrier)?.contains(
                "return mwxPremultiply(mwxFragColor);"
            ) == true,
            "preservedUnpremultiplies": compiled(preservedCarrier)?.contains(
                "mwxUnpremultiply(mwxTexture0.sample"
            ) == true,
            "separatedPremultiplies": compiled(separated)?.contains(
                "return mwxPremultiply(mwxFragColor);"
            ) == true,
            "premultipliedRejected": SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                .analyzeSourceCarried(fragmentSource: premultiplied) == nil,
            "carrierAlphaWriteRejected": SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                .analyzeSourceCarried(fragmentSource: carrierAlphaWrite) == nil,
            "secondSourceRejected": SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                .analyzeSourceCarried(fragmentSource: secondSource) == nil,
            "scalarDistanceLowered": distanceMSL.contains("abs((0.0) - (l))"),
            "scalarDistanceNotEmitted": !distanceMSL.contains("distance ( 0.0 , l )"),
            "preservingProfileFallback": preservingProfile
                .permitsBoundedFrontendAfterArtifactFailure(
                    routeState: preservingProfile.defaultRouteState
                ),
            "preservingProfileFallbackOutcome": preservingProfile
                .artifactFallbackOutcome(
                    routeState: preservingProfile.defaultRouteState
                ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneSourceCarriedStraightRGBATests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-source-carried-straight-rgba-"
        )
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "source-carried-straight-rgba-test"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                "swiftc",
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Security",
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)
        executed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if executed.returncode != 0:
            raise AssertionError(executed.stderr)
        cls.result = json.loads(executed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_three_authored_structures_share_one_straight_boundary(self) -> None:
        self.assertEqual(self.result["preservedTransfer"], "straight-preserving-0")
        self.assertEqual(self.result["separatedTransfer"], "straight-alpha-0")
        self.assertEqual(self.result["aliasedTransfer"], "straight-alpha-0")
        self.assertEqual(
            self.result["pulseModeEightTransfer"], "straight-alpha-0"
        )
        self.assertTrue(self.result["preservedPremultiplies"])
        self.assertTrue(self.result["preservedUnpremultiplies"])
        self.assertTrue(self.result["separatedPremultiplies"])
        self.assertTrue(self.result["scalarDistanceLowered"])
        self.assertTrue(self.result["scalarDistanceNotEmitted"])
        self.assertTrue(self.result["preservingProfileFallback"])
        self.assertEqual(
            self.result["preservingProfileFallbackOutcome"],
            "shared-backend-fallback",
        )

    def test_premultiplication_alpha_mutation_and_second_source_fail_closed(self) -> None:
        self.assertTrue(self.result["premultipliedRejected"])
        self.assertTrue(self.result["carrierAlphaWriteRejected"])
        self.assertTrue(self.result["secondSourceRejected"])


if __name__ == "__main__":
    unittest.main()
