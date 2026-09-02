#!/usr/bin/env python3

"""Generated auxiliary RGB keeps one shared straight-color boundary."""

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
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
]


REAL_FRAGMENT = r"""
#version 450
layout(location = 0) in vec2 v_TexCoord;
layout(set = 0, binding = 0) uniform sampler2D g_Texture0;
layout(set = 0, binding = 1) uniform sampler2D g_Texture1;
layout(set = 0, binding = 8) uniform MWXUniforms {
    float g_Multiply;
    float g_Compensation;
} mwxUniforms;
layout(location = 0) out vec4 mwxFragColor;
vec3 ApplyBlending(const int mode, vec3 base, vec3 replacement, float amount) {
    return mix(base, replacement, amount);
}
float blendAmount(float multiply, float alpha) {
    return multiply + mwxUniforms.g_Compensation * (1.0 - alpha);
}
void main() {
    vec4 carrier = texture(g_Texture0, v_TexCoord);
    carrier = clamp(carrier, 0.0, 1.0);
    float blue = carrier.b * 15.0;
    vec2 first = vec2(fract(floor(blue) * 0.25) + carrier.r * 0.2,
                      floor(blue * 0.25) * 0.25 + carrier.g * 0.2);
    vec2 second = first + vec2(0.25, 0.0);
    mwxFragColor = vec4(
        ApplyBlending(
            0,
            carrier.rgb,
            mix(textureLod(g_Texture1, first, 0.0).rgb,
                textureLod(g_Texture1, second, 0.0).rgb,
                fract(blue)),
            blendAmount(mwxUniforms.g_Multiply, carrier.a)
        ),
        carrier.a
    );
}
"""


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let transfer: String
    let sourceSlot: Int?
    let auxiliarySlots: [Int]
    let rgbCounts: [Int: Int]
    let artifactKind: String?
    let sourceUnpremultiplied: Int
    let auxiliaryUnpremultiplied: Int
    let outputPremultiplied: Bool
    let renamedAccepted: Bool
    let alternateBlendModeAccepted: Bool
    let mutableBlendInputRejected: Bool
    let splitAuxiliaryRejected: Bool
    let auxiliaryAlphaRejected: Bool
    let outputAlphaRejected: Bool
    let carrierAlphaWriteRejected: Bool
    let hiddenSampleRejected: Bool
    let compilerProjectionRejected: Bool
    let compilerAlphaRejected: Bool
    let compilerHiddenSampleRejected: Bool
}

private let helper = """
vec3 ApplyBlending(const int mode, in vec3 base, in vec3 replacement, in float amount) {
    return mix(base, replacement, amount);
}
float weightedAmount(float authored, float alpha) {
    return authored + 0.25 * (1.0 - alpha);
}
"""

private let source = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform sampler2D g_Texture2;
uniform float u_Amount;
varying vec2 v_TexCoord;
""" + helper + """
void main() {
    vec4 carrier = texSample2D(g_Texture0, v_TexCoord);
    carrier = saturate(carrier);
    float selector = carrier.b * 15.0;
    vec2 first = vec2(carrier.r, carrier.g);
    vec2 second = first + vec2(0.25, 0.0);
    gl_FragColor = vec4(
        ApplyBlending(
            0,
            carrier.rgb,
            mix(
                texSample2DLod(g_Texture1, first, 0).rgb,
                texSample2DLod(g_Texture1, second, 0).rgb,
                frac(selector)
            ),
            weightedAmount(u_Amount, carrier.a)
        ),
        carrier.a
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
    float4 carrier = g_Texture0.sample(s, float2(0.2, 0.3));
    carrier = fast::clamp(carrier, float4(0.0), float4(1.0));
    float selector = carrier.z * 15.0;
    float3 generated = mix(
        g_Texture1.sample(s, float2(0.1), level(0.0)).xyz,
        g_Texture1.sample(s, float2(0.2), level(0.0)).xyz,
        fract(selector)
    );
    float3 finalRGB = ApplyBlending(0, carrier.xyz, generated, 0.75);
    out.mwxFragColor = float4(finalRGB, carrier.w);
    return out;
}
"""

private func fact(_ value: String) -> SceneAuthoredShaderTypedDataRGBFilterFact? {
    SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(fragmentSource: value)
}

private func transfer(_ value: String) -> String {
    switch SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: value) {
    case let .straightAlphaPreserving(slot): return "straight:\(slot)"
    default: return "unresolved"
    }
}

private func lowered(_ compiler: String, authored: String = source) -> (
    msl: String,
    transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
)? {
    try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
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
        let renamed = source
            .replacingOccurrences(of: "carrier", with: "foundation")
            .replacingOccurrences(of: "selector", with: "choice")
            .replacingOccurrences(of: "first", with: "entry")
            .replacingOccurrences(of: "second", with: "exit")
        let output = Output(
            transfer: transfer(source),
            sourceSlot: proven?.sourceSlot,
            auxiliarySlots: Array(proven?.auxiliarySlots ?? []).sorted(),
            rgbCounts: proven?.rgbDataSampleCallCounts ?? [:],
            artifactKind: result?.transfer.kind,
            sourceUnpremultiplied: (result?.msl.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count ?? 1) - 1,
            auxiliaryUnpremultiplied: (result?.msl.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture1.sample("
            ).count ?? 1) - 1,
            outputPremultiplied: result?.msl.contains(
                "out.mwxFragColor = mwxGenericPremultiply(float4(finalRGB, carrier.w));"
            ) == true,
            renamedAccepted: fact(renamed)?.sourceSlot == 0,
            alternateBlendModeAccepted: fact(source.replacingOccurrences(
                of: "            0,\n            carrier.rgb,",
                with: "            28,\n            carrier.rgb,"
            ))?.sourceSlot == 0,
            mutableBlendInputRejected: fact(source.replacingOccurrences(
                of: "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 replacement, in float amount)",
                with: "vec3 ApplyBlending(const int mode, inout vec3 base, in vec3 replacement, in float amount)"
            )) == nil,
            splitAuxiliaryRejected: fact(source.replacingOccurrences(
                of: "texSample2DLod(g_Texture1, second, 0).rgb",
                with: "texSample2DLod(g_Texture2, second, 0).rgb"
            )) == nil,
            auxiliaryAlphaRejected: fact(source.replacingOccurrences(
                of: "texSample2DLod(g_Texture1, first, 0).rgb",
                with: "texSample2DLod(g_Texture1, first, 0).aaa"
            )) == nil,
            outputAlphaRejected: fact(source.replacingOccurrences(
                of: "        carrier.a\n    );",
                with: "        1.0\n    );"
            )) == nil,
            carrierAlphaWriteRejected: fact(source.replacingOccurrences(
                of: "    float selector =",
                with: "    carrier.a = 0.5;\n    float selector ="
            )) == nil,
            hiddenSampleRejected: fact(source.replacingOccurrences(
                of: "    gl_FragColor =",
                with: "    vec4 hidden = texSample2D(g_Texture2, v_TexCoord);\n    gl_FragColor ="
            )) == nil,
            compilerProjectionRejected: lowered(msl.replacingOccurrences(
                of: "level(0.0)).xyz",
                with: "level(0.0)).xy"
            )) == nil,
            compilerAlphaRejected: lowered(msl.replacingOccurrences(
                of: "float4(finalRGB, carrier.w)",
                with: "float4(finalRGB, 1.0)"
            )) == nil,
            compilerHiddenSampleRejected: lowered(msl.replacingOccurrences(
                of: "    float3 generated =",
                with: "    float4 hidden = g_Texture2.sample(s, float2(0.4));\n    float3 generated ="
            )) == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneGeneratedAuxiliaryRGBPreservedAlphaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory()
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        binary = root / "generated-auxiliary-rgb-preserved-alpha"
        harness.write_text(HARNESS, encoding="utf-8")
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        subprocess.run(
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

        (root / "generated.frag").write_text(REAL_FRAGMENT, encoding="utf-8")
        fragment_spv = root / "generated.spv"
        fragment_msl = root / "generated.metal"
        compiled = subprocess.run(
            [
                str(GLSLANG), "-V", "--auto-map-bindings",
                "--auto-map-locations", "-S", "frag", "-e", "main",
                "-o", str(fragment_spv), str(root / "generated.frag"),
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

    def test_source_and_artifact_share_one_color_boundary(self) -> None:
        self.assertEqual(self.result["transfer"], "straight:0")
        self.assertEqual(self.result["sourceSlot"], 0)
        self.assertEqual(self.result["auxiliarySlots"], [1])
        self.assertEqual(self.result["rgbCounts"], {"1": 2})
        self.assertEqual(self.result["artifactKind"], "straight-alpha-preserving")
        self.assertEqual(self.result["sourceUnpremultiplied"], 1)
        self.assertEqual(self.result["auxiliaryUnpremultiplied"], 0)
        self.assertTrue(self.result["outputPremultiplied"])

    def test_unseen_spelling_and_negative_drift(self) -> None:
        self.assertTrue(self.result["renamedAccepted"])
        self.assertTrue(self.result["alternateBlendModeAccepted"])
        for key, value in self.result.items():
            if key.endswith("Rejected"):
                self.assertTrue(value, key)

    def test_real_compiler_shape_uses_the_same_boundary(self) -> None:
        self.assertTrue(self.real_compiler_accepted, self.real_compiler_msl)


if __name__ == "__main__":
    unittest.main()
