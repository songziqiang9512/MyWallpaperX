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

private let dataControlled = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform vec3 u_color;
uniform float u_opacity;
varying vec2 v_TexCoord;
vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {
    return mix(base, (blend), opacity);
}
void main() {
    vec4 externalData = texSample2D(g_Texture1, vec2(v_TexCoord.x, 0.5));
    float bar = (externalData.x + externalData.y + externalData.z + externalData.w) * 0.25;
    vec3 finalColor = u_color;
    vec4 scene = texSample2D(g_Texture0, v_TexCoord);
    finalColor = ApplyBlending(
        0, mix(finalColor.rgb, scene.rgb, scene.a), finalColor.rgb, bar * u_opacity
    );
    float alpha = bar * u_opacity;
    gl_FragColor = vec4(finalColor, alpha);
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

private let procedural = """
uniform sampler2D g_Texture0;
uniform vec3 u_color;
uniform float u_strength;
varying vec2 v_TexCoord;
const int STEPS = 200;
float coverage(vec2 uv) {
    float value = 0.0;
    for (int i = 0; i < STEPS; i++) { value += uv.x * 0.1; }
    return value;
}
void paint(vec3 tint, float weight, inout vec3 rgb, inout float a) {
    if (weight < 0.01) return;
    rgb = mix(rgb, tint, weight);
    a = max(a, weight);
}
void main() {
    vec4 base = texSample2D(g_Texture0, v_TexCoord);
    vec3 color = base.rgb;
    float alpha = base.a;
    if (u_strength > 0.0) {
        color = vec3(0.0);
        alpha = 0.0;
        paint(u_color, coverage(v_TexCoord) + coverage(v_TexCoord), color, alpha);
        paint(u_color, u_strength, color, alpha);
    }
    gl_FragColor = vec4(color, alpha);
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

private func auxiliaryDataSlots(_ source: String) -> [Int] {
    SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
        .analyzeSourceCarried(fragmentSource: source)?
        .auxiliaryDataSlots.sorted() ?? []
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
        let dataControlledMSL = compiled(dataControlled) ?? ""
        let additive = aliased.replacingOccurrences(
            of: "return mix(base, (blend), opacity);",
            with: "return base + blend * opacity;\n    return mix(base, (blend), opacity);"
        ).replacingOccurrences(of: "0, mix(color.rgb", with: "31, mix(color.rgb")
        let badAdditive = additive.replacingOccurrences(
            of: "return base + blend * opacity;", with: "return base * blend * opacity;"
        )
        let replacement = additive.replacingOccurrences(
            of: "float alpha = max(source.a, u_amount);", with: "float alpha = u_amount;"
        )
        let unrelatedAlpha = additive.replacingOccurrences(
            of: "float alpha = max(source.a, u_amount);", with: "float alpha = source.r;"
        )
        let unknownMode = additive.replacingOccurrences(
            of: "31, mix(color.rgb", with: "999, mix(color.rgb"
        )
        let result: [String: Any] = [
            "proceduralTransfer": transfer(procedural),
            "proceduralDiagnostics": SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: procedural).diagnostics.map { $0.code.rawValue },
            "proceduralPremultiplies": compiled(procedural)?.contains(
                "return mwxPremultiply(mwxFragColor);"
            ) == true,
            "proceduralUnpremultiplies": compiled(procedural)?.contains(
                "mwxUnpremultiply(mwxTexture0.sample"
            ) == true,
            "proceduralNegativeCases": [
                procedural.replacingOccurrences(of: "rgb = mix(rgb, tint, weight);", with: "rgb = mix(rgb, tint, weight) * a;"),
                procedural.replacingOccurrences(of: "a = max(a, weight);", with: "a = rgb.r;"),
                procedural.replacingOccurrences(of: "paint(u_color, u_strength, color, alpha);", with: "paint(base.rgb, u_strength, color, alpha);"),
                procedural.replacingOccurrences(of: "color = vec3(0.0);", with: "color *= alpha;"),
                procedural.replacingOccurrences(of: "STEPS = 200", with: "STEPS = 1000"),
                procedural.replacingOccurrences(of: "rgb = mix(rgb, tint, weight);", with: "vec3 alias = rgb; rgb = mix(alias, tint, weight);"),
            ].allSatisfy {
                SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                    .analyzeSourceCarried(fragmentSource: $0) == nil
            },
            "additiveTransfer": transfer(additive),
            "replacementTransfer": transfer(replacement),
            "unrelatedAlphaRejected": SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                .analyzeSourceCarried(fragmentSource: unrelatedAlpha) == nil,
            "badAdditiveRejected": SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                .analyzeSourceCarried(fragmentSource: badAdditive) == nil,
            "unknownModeRejected": SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                .analyzeSourceCarried(fragmentSource: unknownMode) == nil,
            "preservedTransfer": transfer(preservedCarrier),
            "separatedTransfer": transfer(separated),
            "aliasedTransfer": transfer(aliased),
            "dataControlledTransfer": transfer(dataControlled),
            "dataControlledAuxiliarySlots": auxiliaryDataSlots(dataControlled),
            "dataControlledPremultiplies": dataControlledMSL.contains(
                "return mwxPremultiply(mwxFragColor);"
            ),
            "dataControlledUnpremultipliesColor": dataControlledMSL.contains(
                "mwxUnpremultiply(mwxTexture0.sample"
            ),
            "dataControlledPreservesData": !dataControlledMSL.contains(
                "mwxUnpremultiply(mwxTexture1.sample"
            ),
            "wholeVectorDataRejected": SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                .analyzeSourceCarried(
                    fragmentSource: dataControlled.replacingOccurrences(
                        of: "(externalData.x + externalData.y + externalData.z + externalData.w) * 0.25",
                        with: "dot(externalData, vec4(0.25))"
                    )
                ) == nil,
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

    def test_bounded_procedural_helper_preserves_source_color_boundary(self) -> None:
        self.assertEqual(self.result["proceduralTransfer"], "straight-alpha-0", self.result)
        self.assertTrue(self.result["proceduralPremultiplies"])
        self.assertTrue(self.result["proceduralUnpremultiplies"])
        self.assertTrue(self.result["proceduralNegativeCases"])

    def test_premultiplication_alpha_mutation_and_second_source_fail_closed(self) -> None:
        self.assertTrue(self.result["premultipliedRejected"])
        self.assertTrue(self.result["carrierAlphaWriteRejected"])
        self.assertTrue(self.result["secondSourceRejected"])

    def test_uniform_seeded_rgb_reuses_validated_additive_helper(self) -> None:
        self.assertEqual(self.result["additiveTransfer"], "straight-alpha-0")
        self.assertEqual(self.result["replacementTransfer"], "straight-alpha-0")
        self.assertTrue(self.result["unrelatedAlphaRejected"])
        self.assertTrue(self.result["badAdditiveRejected"])
        self.assertTrue(self.result["unknownModeRejected"])

    def test_uniform_seeded_rgb_keeps_auxiliary_rgba_as_data(self) -> None:
        self.assertEqual(
            self.result["dataControlledTransfer"], "straight-alpha-0", self.result
        )
        self.assertEqual(self.result["dataControlledAuxiliarySlots"], [1])
        self.assertTrue(self.result["dataControlledPremultiplies"])
        self.assertTrue(self.result["dataControlledUnpremultipliesColor"])
        self.assertTrue(self.result["dataControlledPreservesData"])
        self.assertTrue(self.result["wholeVectorDataRejected"])


if __name__ == "__main__":
    unittest.main()
