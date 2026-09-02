#!/usr/bin/env python3

"""Shared two-read RGB blend plus saturated-alpha-union color boundary."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
GLSLANG = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"
SPIRV_CROSS = (
    REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools/spirv-cross"
)

REAL_FRAGMENT = r"""
#version 450
layout(location = 0) in vec2 v_TexCoord;
layout(set = 0, binding = 0) uniform sampler2D g_Texture0;
layout(set = 0, binding = 1) uniform sampler2D g_Texture1;
layout(set = 0, binding = 8) uniform MWXUniforms {
    float g_ReflectionAlpha;
} mwxUniforms;
layout(location = 0) out vec4 mwxFragColor;
vec3 ApplyBlending(const int mode, vec3 A, vec3 B, float opacity) {
    return A + B * opacity;
}
void main() {
    vec4 albedo = texture(g_Texture0, v_TexCoord);
    float mask = texture(g_Texture1, v_TexCoord).r;
    vec2 reflectedCoord = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y);
    vec4 reflected = texture(g_Texture0, reflectedCoord);
    mwxFragColor.rgb = ApplyBlending(
        31, albedo.rgb, reflected.rgb, mask * mwxUniforms.g_ReflectionAlpha
    );
    mwxFragColor.a = min(
        1.0, albedo.a + reflected.a * mask * mwxUniforms.g_ReflectionAlpha
    );
}
"""
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let transfer: String
    let sourceSlot: Int?
    let maskSlot: Int?
    let blendMode: Int?
    let artifactKind: String?
    let directLowered: Bool
    let unpremultipliedColorSamples: Int
    let maskStayedScalar: Bool
    let premultipliedTerminal: Bool
    let noMaskAccepted: Bool
    let modeNineAccepted: Bool
    let renamedAccepted: Bool
    let wrongReflectedSlotRejected: Bool
    let swappedBlendRejected: Bool
    let alphaReplacementRejected: Bool
    let mismatchedFactorRejected: Bool
    let hiddenSampleRejected: Bool
    let wrongCompilerSlotRejected: Bool
    let compilerAlphaReplacementRejected: Bool
    let compilerFactorDriftRejected: Bool
    let hiddenCompilerSampleRejected: Bool
}

private let helper = """
vec3 ApplyBlending(const int mode, in vec3 A, in vec3 B, in float opacity) {
    return A + B * opacity;
    return mix(A, B, opacity);
}
"""

private let source = """
varying vec2 v_TexCoord;
varying vec2 v_Perspective;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_ReflectionAlpha;
""" + helper + """
void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
    float mask = texSample2D(g_Texture1, v_TexCoord.xy).r;
    vec2 reflectedCoord;
    reflectedCoord = v_Perspective;
    reflectedCoord.y = 1.0 - reflectedCoord.y;
    mask *= step(abs(reflectedCoord.x - 0.5), 0.5);
    mask *= step(abs(reflectedCoord.y - 0.5), 0.5);
    vec4 reflected = texSample2D(g_Texture0, reflectedCoord);
    gl_FragColor.rgb = ApplyBlending(
        31, albedo.rgb, reflected.rgb, mask * g_ReflectionAlpha
    );
    gl_FragColor.a = min(
        1.0, albedo.a + reflected.a * mask * g_ReflectionAlpha
    );
}
"""

private let msl = """
#include <metal_stdlib>
using namespace metal;
struct FragmentOut { float4 mwxFragColor [[color(0)]]; };
fragment FragmentOut mwxGenericFragment(
    texture2d<float> g_Texture0 [[texture(0)]],
    texture2d<float> g_Texture1 [[texture(1)]],
    sampler s [[sampler(0)]]) {
    FragmentOut out = {};
    float4 albedo = g_Texture0.sample(s, float2(0.2, 0.3));
    float mask = g_Texture1.sample(s, float2(0.4, 0.5)).x;
    float2 reflectedCoord = float2(0.8, 0.7);
    float4 reflected = g_Texture0.sample(s, reflectedCoord);
    float g_ReflectionAlpha = 0.75;
    out.mwxFragColor.xyz = ApplyBlending(31, albedo.xyz, reflected.xyz, mask * g_ReflectionAlpha);
    out.mwxFragColor.w = fast::min(1.0, albedo.w + reflected.w * (mask * g_ReflectionAlpha));
    return out;
}
"""

private func fact(_ value: String) ->
    SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer.Fact?
{
    SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer
        .analyze(fragmentSource: value)
}

private func transfer(_ value: String) -> String {
    switch SceneAuthoredShaderColorTransferAnalyzer.analyze(
        fragmentSource: value
    ) {
    case let .straightAlpha(slot): return "straight:\(slot)"
    default: return "unresolved"
    }
}

private func lowered(_ compiler: String, authored: String = source) -> (
    msl: String,
    transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
)? {
    return try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
        msl: compiler,
        authoredSource: authored,
        expectedColorTransfer: nil
    )
}

@main
private struct Harness {
    static func main() throws {
        if CommandLine.arguments.count == 3,
           CommandLine.arguments[1] == "validate" {
            let compiler = try String(
                contentsOfFile: CommandLine.arguments[2], encoding: .utf8
            )
            FileHandle.standardOutput.write(
                Data(String(lowered(compiler) != nil).utf8)
            )
            return
        }
        let proven = fact(source)
        let result = lowered(msl)
        let direct = proven.flatMap {
            SceneGenericShaderSameSlotColorBlendAlphaUnionLowering
                .lower(msl, fact: $0)
        }
        let noMask = source.replacingOccurrences(
            of: "float mask = texSample2D(g_Texture1, v_TexCoord.xy).r;",
            with: "float mask = 1.0;"
        )
        let renamed = source
            .replacingOccurrences(of: "albedo", with: "foundation")
            .replacingOccurrences(of: "reflected", with: "echo")
            .replacingOccurrences(of: "mask", with: "coverage")
        let modeNine = source
            .replacingOccurrences(
                of: "return A + B * opacity;",
                with: "return mix(A, min(A + B, vec3(1.0)), opacity);"
            )
            .replacingOccurrences(
                of: "31, albedo.rgb, reflected.rgb",
                with: "9, albedo.rgb, reflected.rgb"
            )
        let output = Output(
            transfer: transfer(source),
            sourceSlot: proven?.sourceSlot,
            maskSlot: proven?.maskSlot,
            blendMode: proven?.blendMode,
            artifactKind: result?.transfer.kind,
            directLowered: direct != nil,
            unpremultipliedColorSamples: (result?.msl.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count ?? 1) - 1,
            maskStayedScalar: result?.msl.contains(
                "float mask = g_Texture1.sample(s, float2(0.4, 0.5)).x;"
            ) == true,
            premultipliedTerminal: result?.msl.contains(
                "out.mwxFragColor = mwxGenericPremultiply(out.mwxFragColor);"
            ) == true,
            noMaskAccepted: fact(noMask)?.maskSlot == nil,
            modeNineAccepted: fact(modeNine)?.blendMode == 9,
            renamedAccepted: fact(renamed)?.sourceSlot == 0,
            wrongReflectedSlotRejected: fact(source.replacingOccurrences(
                of: "vec4 reflected = texSample2D(g_Texture0, reflectedCoord);",
                with: "vec4 reflected = texSample2D(g_Texture2, reflectedCoord);"
            )) == nil,
            swappedBlendRejected: fact(source.replacingOccurrences(
                of: "31, albedo.rgb, reflected.rgb, mask * g_ReflectionAlpha",
                with: "31, reflected.rgb, albedo.rgb, mask * g_ReflectionAlpha"
            )) == nil,
            alphaReplacementRejected: fact(source.replacingOccurrences(
                of: "albedo.a + reflected.a * mask * g_ReflectionAlpha",
                with: "reflected.a * mask * g_ReflectionAlpha"
            )) == nil,
            mismatchedFactorRejected: fact(source.replacingOccurrences(
                of: "reflected.a * mask * g_ReflectionAlpha",
                with: "reflected.a * g_ReflectionAlpha * g_ReflectionAlpha"
            )) == nil,
            hiddenSampleRejected: fact(source.replacingOccurrences(
                of: "    vec4 reflected =",
                with: "    vec4 hidden = texSample2D(g_Texture0, v_TexCoord.xy);\n    vec4 reflected ="
            )) == nil,
            wrongCompilerSlotRejected: lowered(msl.replacingOccurrences(
                of: "float4 reflected = g_Texture0.sample",
                with: "float4 reflected = g_Texture2.sample"
            )) == nil,
            compilerAlphaReplacementRejected: lowered(msl.replacingOccurrences(
                of: "albedo.w + reflected.w * (mask * g_ReflectionAlpha)",
                with: "reflected.w * (mask * g_ReflectionAlpha)"
            )) == nil,
            compilerFactorDriftRejected: lowered(msl.replacingOccurrences(
                of: "reflected.w * (mask * g_ReflectionAlpha)",
                with: "reflected.w * g_ReflectionAlpha"
            )) == nil,
            hiddenCompilerSampleRejected: lowered(msl.replacingOccurrences(
                of: "    float4 reflected =",
                with: "    float4 hidden = g_Texture0.sample(s, float2(0.1));\n    float4 reflected ="
            )) == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneSameSlotColorBlendAlphaUnionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory()
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        binary = root / "same-slot-color-blend-alpha-union"
        harness.write_text(HARNESS, encoding="utf-8")
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        linked = subprocess.run(
            [
                swiftc,
                "-module-cache-path",
                os.environ.get(
                    "MWX_SWIFT_MODULE_CACHE",
                    str(Path(tempfile.gettempdir()) / "mwx-swift-module-cache"),
                ),
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(binary),
            ],
            check=True,
            cwd=REPOSITORY_ROOT,
        )
        cls.result = json.loads(
            subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            ).stdout
        )
        (root / "reflection.frag").write_text(REAL_FRAGMENT, encoding="utf-8")
        fragment_spv = root / "reflection.spv"
        fragment_msl = root / "reflection.metal"
        compiled = subprocess.run(
            [
                str(GLSLANG), "-V", "--auto-map-bindings",
                "--auto-map-locations", "-S", "frag", "-e", "main",
                "-o", str(fragment_spv), str(root / "reflection.frag"),
            ],
            cwd=root,
            capture_output=True,
            text=True,
        )
        if compiled.returncode != 0:
            raise RuntimeError(compiled.stdout + compiled.stderr)
        subprocess.run(
            [
                str(SPIRV_CROSS), str(fragment_spv), "--msl",
                "--msl-version", "20000", "--msl-decoration-binding",
                "--rename-entry-point", "main", "mwxGenericFragment",
                "frag", "--output", str(fragment_msl),
            ],
            check=True,
            cwd=root,
            capture_output=True,
            text=True,
        )
        real = subprocess.run(
            [str(binary), "validate", str(fragment_msl)],
            check=True,
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        cls.real_compiler_accepted = real.stdout == "true"
        cls.real_compiler_msl = fragment_msl.read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_source_and_compiler_share_one_color_boundary(self) -> None:
        self.assertEqual(self.result["transfer"], "straight:0")
        self.assertEqual(self.result["sourceSlot"], 0)
        self.assertEqual(self.result["maskSlot"], 1)
        self.assertEqual(self.result["blendMode"], 31)
        self.assertEqual(self.result["artifactKind"], "straight-alpha")
        self.assertTrue(self.result["directLowered"])
        self.assertEqual(self.result["unpremultipliedColorSamples"], 2)
        self.assertTrue(self.result["maskStayedScalar"])
        self.assertTrue(self.result["premultipliedTerminal"])

    def test_unseen_spelling_and_negative_drift(self) -> None:
        self.assertTrue(self.result["noMaskAccepted"])
        self.assertTrue(self.result["modeNineAccepted"])
        self.assertTrue(self.result["renamedAccepted"])
        for key in (
            "wrongReflectedSlotRejected",
            "swappedBlendRejected",
            "alphaReplacementRejected",
            "mismatchedFactorRejected",
            "hiddenSampleRejected",
            "wrongCompilerSlotRejected",
            "compilerAlphaReplacementRejected",
            "compilerFactorDriftRejected",
            "hiddenCompilerSampleRejected",
        ):
            self.assertTrue(self.result[key], key)

    def test_real_compiler_shape_uses_the_same_boundary(self) -> None:
        self.assertTrue(
            self.real_compiler_accepted,
            self.real_compiler_msl,
        )


if __name__ == "__main__":
    unittest.main()
