#!/usr/bin/env python3

"""Fail-closed color-transfer proofs from the emitted shader syntax unit."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderBoundedLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStaticLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVaryingArrayEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderOpaqueInputAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderIndependentAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
]


HARNESS = r'''
import Foundation

private func fragment(_ body: String) -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    uniform float g_ScalarWeight;
    vec3 ApplyBlending(int mode, vec3 base, vec3 blend, float opacity) {
        return mix(base, blend, opacity);
    }
    void main() {
        \(body)
    }
    """
}

private func program(_ body: String) -> SceneAuthoredShaderProgram? {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() {
        v_TexCoord = a_TexCoord;
        gl_Position = vec4(a_Position, 1.0);
    }
    """
    return SceneAuthoredShaderFrontend.compile(
        vertexSource: vertex,
        fragmentSource: fragment(body)
    ).program
}

private func transfer(_ body: String) -> String {
    let result = program(body)?.colorTransfer ?? .unresolved
    switch result {
    case .opaque: return "opaque"
    case .unresolved: return "unresolved"
    case .passthrough(let slot): return "slot:\(slot)"
    case .straightAlphaPreserving(let slot):
        return "straight-preserving-slot:\(slot)"
    case .straightAlpha(let slot): return "straight-slot:\(slot)"
    case .independentAlphaSignal(let slot): return "signal-slot:\(slot)"
    case .independentAlphaSignalPreserving(let slot):
        return "signal-preserving-slot:\(slot)"
    case .independentAlphaSignalCompositing(let signal, let color):
        return "signal-composite:\(signal):\(color)"
    }
}

private func metal(_ body: String) -> String {
    program(body)?.metalSource ?? ""
}

@main
enum Harness {
    static func main() throws {
        let result: [String: String] = [
            "directTexture0": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
            ),
            "directTexture1": transfer(
                "gl_FragColor = texSample2D(g_Texture1, v_TexCoord * 0.5);"
            ),
            "directTexture2D": transfer(
                "gl_FragColor = texture2D(g_Texture0, v_TexCoord);"
            ),
            "opaque": transfer(
                "vec3 total = vec3(0.2); gl_FragColor = vec4(total, 1.0);"
            ),
            "closedControlFlowOpaque": transfer(
                "vec3 total = vec3(0.2); " +
                "for (int index = 0; index < 2; index++) { " +
                "if (index > 0) { total += vec3(0.1); } " +
                "} gl_FragColor = vec4(total, 1.0);"
            ),
            "closedConditionalPassthrough": transfer(
                "float scale = 1.0; " +
                "if (v_TexCoord.x > 0.5) { scale = 0.5; } " +
                "gl_FragColor = texSample2D(g_Texture1, v_TexCoord);"
            ),
            "straightAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = 0.5; " +
                "gl_FragColor = vec4(color.rgb, color.a * mask);"
            ),
            "closedControlFlowStraightAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = 1.0; " +
                "for (int index = 0; index < 2; index++) { " +
                "if (index > 0) { mask *= 0.5; } } " +
                "gl_FragColor = vec4(color.rgb, color.a * mask);"
            ),
            "modifiedStraightLocal": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "color.a *= 0.5; gl_FragColor = vec4(color.rgb, color.a);"
            ),
            "mutatedLocalOutput": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float delta = dot(color.rgb, vec3(1.0)); " +
                "color.a *= delta; gl_FragColor = color;"
            ),
            "sameSlotScalarMix": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "gl_FragColor = mix(texSample2D(g_Texture0, " +
                "v_TexCoord * 0.5), gl_FragColor, mask);"
            ),
            "sameSlotUniformMix": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); " +
                "gl_FragColor = mix(gl_FragColor, texSample2D(g_Texture0, " +
                "v_TexCoord * 0.5), g_ScalarWeight);"
            ),
            "opaqueInputRGBTransform": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; color.rgb = vec3(0.25); " +
                "gl_FragColor = saturate(color);"
            ),
            "alphaPreservingMetal": metal(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; color.rgb = vec3(0.25); " +
                "gl_FragColor = saturate(color);"
            ),
            "opaqueInputAlphaWrite": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; color.a *= 0.5; " +
                "gl_FragColor = saturate(color);"
            ),
            "opaqueInputWholeWrite": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; color = vec4(1.0); " +
                "gl_FragColor = saturate(color);"
            ),
            "independentSignal": transfer(
                "vec4 sample = texSample2D(g_Texture0, v_TexCoord); " +
                "sample.rgb *= sample.a; sample.a = 1.0; " +
                "gl_FragColor = sample * 0.5; gl_FragColor.a *= 0.25;"
            ),
            "independentSignalPreserving": transfer(
                "vec4 total = vec4(0.0); " +
                "vec4 sample = texSample2D(g_Texture0, v_TexCoord); " +
                "total += sample * 0.5; total.rgb *= vec3(0.5); " +
                "gl_FragColor = total;"
            ),
            "independentSignalComposite": transfer(
                "vec4 rays = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = texSample2D(g_Texture1, v_TexCoord); " +
                "color.rgb = ApplyBlending(9, color.rgb, rays.rgb, rays.a); " +
                "color.a += rays.a; gl_FragColor = color;"
            ),
            "invalidIndependentSignal": transfer(
                "vec4 sample = texSample2D(g_Texture0, v_TexCoord); " +
                "sample.rgb *= 0.5; sample.a = 1.0; " +
                "gl_FragColor = sample * 0.5;"
            ),
            "differentSlotMix": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = 0.5; gl_FragColor = mix(gl_FragColor, " +
                "texSample2D(g_Texture1, v_TexCoord), mask);"
            ),
            "vectorWeightMix": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 mask = vec4(0.5); gl_FragColor = mix(gl_FragColor, " +
                "texSample2D(g_Texture0, v_TexCoord), mask);"
            ),
            "straightRGBMath": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "gl_FragColor = vec4(color.rgb * 0.5, color.a * 0.5);"
            ),
            "mixedSampleAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 other = texSample2D(g_Texture1, v_TexCoord); " +
                "gl_FragColor = vec4(color.rgb, color.a * other.a);"
            ),
            "sampledMaskAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "gl_FragColor = vec4(color.rgb, color.a * mask);"
            ),
            "arithmetic": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * 0.5;"
            ),
            "localAlpha": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); c.a = 0.5; gl_FragColor = c;"
            ),
            "conditionalLocalAlpha": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); " +
                "if (v_TexCoord.x > 0.5) { c.a *= 0.5; } gl_FragColor = c;"
            ),
            "localRGBWrite": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); " +
                "c.rgb *= 0.5; c.a *= 0.5; gl_FragColor = c;"
            ),
            "multipleLocalAlphaWrites": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); " +
                "c.a *= 0.5; c.a += 0.1; gl_FragColor = c;"
            ),
            "wholeLocalWrite": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); " +
                "c = vec4(1.0); c.a *= 0.5; gl_FragColor = c;"
            ),
            "multipleWrites": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); gl_FragColor = vec4(1.0);"
            ),
            "componentWrite": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); gl_FragColor.a = 1.0;"
            ),
            "conditionalOpaque": transfer(
                "if (v_TexCoord.x > 0.5) gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "loopControlledOpaque": transfer(
                "for (int index = 0; index < 2; index++) " +
                "gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "earlyReturn": transfer(
                "if (v_TexCoord.x < 0.0) return; gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "discardedBranch": transfer(
                "if (v_TexCoord.x < 0.0) discard; gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "straightMetal": metal(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "gl_FragColor = vec4(color.rgb, color.a * 0.5);"
            ),
            "passthroughMetal": metal(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
            ),
            "opaqueMetal": metal(
                "gl_FragColor = vec4(0.2, 0.3, 0.4, 1.0);"
            ),
            "independentSignalMetal": metal(
                "vec4 sample = texSample2D(g_Texture0, v_TexCoord); " +
                "sample.rgb *= sample.a; sample.a = 1.0; " +
                "gl_FragColor = sample * 0.5;"
            ),
            "independentCompositeMetal": metal(
                "vec4 rays = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = texSample2D(g_Texture1, v_TexCoord); " +
                "color.rgb = ApplyBlending(9, color.rgb, rays.rgb, rays.a); " +
                "color.a += rays.a; gl_FragColor = color;"
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneShaderColorContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-shader-color-transfer-"
        )
        temporary = Path(cls.temporary_directory.name)
        harness = temporary / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = temporary / "shader-color-transfer"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness), "-o", str(binary),
            ],
            capture_output=True,
            text=True,
            env=environment,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True, env=environment
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_direct_sample_proves_only_the_sampled_slot(self) -> None:
        self.assertEqual(self.result["directTexture0"], "slot:0")
        self.assertEqual(self.result["directTexture1"], "slot:1")
        self.assertEqual(self.result["directTexture2D"], "slot:0")

    def test_literal_one_alpha_proves_only_opaque_output(self) -> None:
        self.assertEqual(self.result["opaque"], "opaque")

    def test_closed_control_flow_does_not_hide_root_output(self) -> None:
        self.assertEqual(self.result["closedControlFlowOpaque"], "opaque")
        self.assertEqual(self.result["closedConditionalPassthrough"], "slot:1")

    def test_straight_alpha_boundary_is_proven_from_a_single_source(self) -> None:
        self.assertEqual(self.result["straightAlpha"], "straight-slot:0")
        self.assertEqual(
            self.result["closedControlFlowStraightAlpha"], "straight-slot:0"
        )
        self.assertEqual(self.result["localAlpha"], "straight-slot:0")
        self.assertEqual(self.result["mutatedLocalOutput"], "straight-slot:0")

    def test_same_slot_scalar_mix_preserves_one_color_source(self) -> None:
        self.assertEqual(self.result["sameSlotScalarMix"], "slot:0")
        self.assertEqual(self.result["sameSlotUniformMix"], "slot:0")

    def test_rgb_only_local_flow_uses_a_straight_color_boundary(self) -> None:
        self.assertEqual(
            self.result["opaqueInputRGBTransform"], "straight-preserving-slot:0"
        )
        source = self.result["alphaPreservingMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_independent_alpha_signal_is_bounded_and_composed_explicitly(self) -> None:
        self.assertEqual(self.result["independentSignal"], "signal-slot:0")
        self.assertEqual(
            self.result["independentSignalPreserving"],
            "signal-preserving-slot:0",
        )
        self.assertEqual(
            self.result["independentSignalComposite"], "signal-composite:0:1"
        )
        self.assertEqual(
            self.result["invalidIndependentSignal"],
            "signal-preserving-slot:0",
        )

        producer = self.result["independentSignalMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", producer)
        self.assertNotIn("return mwxPremultiply(mwxFragColor);", producer)
        composite = self.result["independentCompositeMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture1.sample", composite)
        self.assertIn("return mwxPremultiply(mwxFragColor);", composite)

    def test_straight_alpha_boundary_is_emitted_only_for_proven_programs(self) -> None:
        source = self.result["straightMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        for key in ("passthroughMetal", "opaqueMetal"):
            self.assertNotIn("mwxUnpremultiply", self.result[key], key)
            self.assertNotIn("mwxPremultiply", self.result[key], key)

    def test_alpha_math_and_non_linear_writes_remain_unproven(self) -> None:
        for key in (
            "localRGBWrite",
            "multipleLocalAlphaWrites",
            "wholeLocalWrite",
        ):
            self.assertEqual(self.result[key], "signal-preserving-slot:0", key)
        for key in (
            "arithmetic",
            "modifiedStraightLocal",
            "straightRGBMath",
            "mixedSampleAlpha",
            "sampledMaskAlpha",
            "conditionalLocalAlpha",
            "multipleWrites",
            "componentWrite",
            "conditionalOpaque",
            "loopControlledOpaque",
            "earlyReturn",
            "discardedBranch",
            "differentSlotMix",
            "vectorWeightMix",
            "opaqueInputAlphaWrite",
            "opaqueInputWholeWrite",
        ):
            self.assertEqual(self.result[key], "unresolved", key)


if __name__ == "__main__":
    unittest.main()
