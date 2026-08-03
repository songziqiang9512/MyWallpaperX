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
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
]


HARNESS = r'''
import Foundation

private func fragment(_ body: String) -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    void main() {
        \(body)
    }
    """
}

private func transfer(_ body: String) -> String {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() {
        v_TexCoord = a_TexCoord;
        gl_Position = vec4(a_Position, 1.0);
    }
    """
    let result = SceneAuthoredShaderFrontend.compile(
        vertexSource: vertex,
        fragmentSource: fragment(body)
    ).program?.colorTransfer ?? .unresolved
    switch result {
    case .opaque: return "opaque"
    case .unresolved: return "unresolved"
    case .passthrough(let slot): return "slot:\(slot)"
    }
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
            "arithmetic": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * 0.5;"
            ),
            "localAlpha": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); c.a = 0.5; gl_FragColor = c;"
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
            "earlyReturn": transfer(
                "if (v_TexCoord.x < 0.0) return; gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "discardedBranch": transfer(
                "if (v_TexCoord.x < 0.0) discard; gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
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

    def test_alpha_math_and_non_linear_writes_remain_unproven(self) -> None:
        for key in (
            "arithmetic",
            "localAlpha",
            "multipleWrites",
            "componentWrite",
            "conditionalOpaque",
            "earlyReturn",
            "discardedBranch",
        ):
            self.assertEqual(self.result[key], "unresolved", key)


if __name__ == "__main__":
    unittest.main()
