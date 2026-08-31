#!/usr/bin/env python3
"""Strict identity-free proof for compositor-lowerable texture tint shaders."""

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
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = scene_swift_sources("authored_shader_frontend_core")

HARNESS = r'''
import Foundation

private struct Output: Codable {
    let preparedCastAccepted: Bool
    let unseenSlot: Int?
    let offsetUVRejected: Bool
    let extraSampleRejected: Bool
    let alphaReplacementRejected: Bool
}

@main
private enum Harness {
    static func main() throws {
        let vertex = """
        uniform mat4 g_ModelViewProjectionMatrix;
        uniform float g_Time;
        uniform float g_ScrollX;
        uniform float g_ScrollY;
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
            vec2 scroll = vec2(g_ScrollX, g_ScrollY);
            scroll = sign(scroll) * pow(vec2(g_ScrollX, g_ScrollY), CAST2(2.0));
            v_TexCoord = a_TexCoord + g_Time * scroll;
        }
        """
        let fragment = """
        uniform sampler2D g_Texture0;
        uniform float g_Brightness;
        uniform float g_UserAlpha;
        uniform float g_Power;
        uniform vec3 g_TintColor;
        varying vec2 v_TexCoord;
        void main() {
            vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
            albedo.rgb *= g_Brightness * g_TintColor;
            albedo.a *= g_UserAlpha;
            albedo.rgb = pow(albedo.rgb, CAST3(g_Power));
            gl_FragColor = albedo;
        }
        """
        let prepared = SceneAuthoredShaderNeutralTextureTintAnalyzer.analyze(
            vertexSource: vertex, fragmentSource: fragment
        )
        let unseen = SceneAuthoredShaderNeutralTextureTintAnalyzer.analyze(
            vertexSource: vertex,
            fragmentSource: fragment.replacingOccurrences(
                of: "g_Texture0", with: "g_Texture6"
            )
        )
        let offsetUV = SceneAuthoredShaderNeutralTextureTintAnalyzer.analyze(
            vertexSource: vertex.replacingOccurrences(
                of: "g_Time * scroll", with: "g_Time * scroll + vec2(0.1)"
            ),
            fragmentSource: fragment
        )
        let extraSample = SceneAuthoredShaderNeutralTextureTintAnalyzer.analyze(
            vertexSource: vertex,
            fragmentSource: fragment.replacingOccurrences(
                of: "gl_FragColor = albedo;",
                with: "albedo += texSample2D(g_Texture0, v_TexCoord.xy);\n    gl_FragColor = albedo;"
            )
        )
        let alphaReplacement = SceneAuthoredShaderNeutralTextureTintAnalyzer.analyze(
            vertexSource: vertex,
            fragmentSource: fragment.replacingOccurrences(
                of: "albedo.a *= g_UserAlpha;", with: "albedo.a = 1.0;"
            )
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(Output(
            preparedCastAccepted: prepared != nil,
            unseenSlot: unseen?.textureSlot,
            offsetUVRejected: offsetUV == nil,
            extraSampleRejected: extraSample == nil,
            alphaReplacementRejected: alphaReplacement == nil
        )))
    }
}
'''


class SceneAuthoredShaderNeutralTextureTintTests(unittest.TestCase):
    def test_only_exact_neutral_texture_tint_is_lowered(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="mwx-neutral-texture-tint-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "neutral-texture-tint"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(
                subprocess.run(
                    [str(binary)],
                    cwd=REPOSITORY_ROOT,
                    env=environment,
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout
            )
            self.assertTrue(result["preparedCastAccepted"])
            self.assertEqual(result["unseenSlot"], 6)
            self.assertTrue(result["offsetUVRejected"])
            self.assertTrue(result["extraSampleRejected"])
            self.assertTrue(result["alphaReplacementRejected"])


if __name__ == "__main__":
    unittest.main()
