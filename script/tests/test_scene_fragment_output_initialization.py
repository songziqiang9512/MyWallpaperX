#!/usr/bin/env python3

"""Dominating fragment-output initialization for preserved-channel Programs."""

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
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = list(scene_swift_sources("authored_shader_frontend_core"))


HARNESS = r'''
import Foundation
import Metal

private struct Result: Codable {
    let channelUse: String
    let diagnostics: [String]
    let metalCompiled: Bool
}

private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord = a_TexCoord;
}
"""

private func compile(_ body: String) -> Result {
    let fragment = """
    uniform sampler2D g_Texture0;
    uniform float g_Gain;
    uniform vec2 g_Offset;
    varying vec2 v_TexCoord;
    void main() {
        \(body)
    }
    """
    let output = SceneAuthoredShaderFrontend.compile(
        vertexSource: vertex,
        fragmentSource: fragment
    )
    guard let program = output.program else {
        let lexer = SceneAuthoredShaderLexer.lex(
            source: fragment,
            stage: .fragment
        )
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: lexer,
            stage: .fragment
        )
        let channelUse = syntax.unit.map {
            SceneAuthoredShaderFragmentOutputAnalyzer.analyze($0).rawValue
        } ?? "unproven"
        return .init(
            channelUse: channelUse,
            diagnostics: output.diagnostics.map { $0.code.rawValue },
            metalCompiled: false
        )
    }
    let metalCompiled: Bool
    do {
        guard let device = MTLCreateSystemDefaultDevice() else {
            metalCompiled = false
            return .init(
                channelUse: program.fragmentOutputChannelUse.rawValue,
                diagnostics: [],
                metalCompiled: metalCompiled
            )
        }
        _ = try device.makeLibrary(source: program.metalSource, options: nil)
        metalCompiled = true
    } catch {
        metalCompiled = false
    }
    return .init(
        channelUse: program.fragmentOutputChannelUse.rawValue,
        diagnostics: [],
        metalCompiled: metalCompiled
    )
}

@main
private enum Harness {
    static func main() throws {
        let results = [
            "wholeThenXYCompound": compile("""
                vec4 initial = texSample2D(g_Texture0, v_TexCoord);
                gl_FragColor = initial;
                gl_FragColor.xy += g_Offset;
                """),
            "unseenWholeThenConditionalRG": compile("""
                gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0);
                if (g_Gain > 0.0) { gl_FragColor.r *= g_Gain; }
                gl_FragColor.g = g_Offset.y;
                """),
            "componentBeforeWhole": compile("""
                gl_FragColor.xy += g_Offset;
                gl_FragColor = vec4(0.5);
                """),
            "componentOnly": compile("gl_FragColor.r = g_Gain;"),
            "secondWholeWrite": compile("""
                gl_FragColor = vec4(0.25);
                gl_FragColor = vec4(0.5);
                """),
            "laterReadOutsideMutation": compile("""
                gl_FragColor = vec4(0.25);
                float copy = gl_FragColor.r;
                gl_FragColor.r = copy;
                """),
            "blueMutationOutsideProfile": compile("""
                gl_FragColor = vec4(0.25);
                gl_FragColor.b += g_Gain;
                """),
            "conditionalInitialization": compile("""
                if (g_Gain > 0.0) { gl_FragColor = vec4(0.25); }
                gl_FragColor.r += g_Gain;
                """),
            "earlyReturn": compile("""
                gl_FragColor = vec4(0.25);
                if (g_Gain < 0.0) { return; }
                gl_FragColor.r += g_Gain;
                """),
            "malformedMutationRHS": compile("""
                gl_FragColor = vec4(0.25);
                gl_FragColor.xy += ;
                """),
        ]
        let data = try JSONEncoder().encode(results)
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneFragmentOutputInitializationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-fragment-output-initialization-"
        )
        temporary = Path(cls.temporary_directory.name)
        harness = temporary / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = temporary / "fragment-output-initialization"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        compilation = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.results = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_whole_initialization_dominates_direct_red_green_mutations(self) -> None:
        for key in ("wholeThenXYCompound", "unseenWholeThenConditionalRG"):
            with self.subTest(key=key):
                self.assertEqual(self.results[key]["channelUse"], "redDefined")
                self.assertEqual(self.results[key]["diagnostics"], [])
                self.assertTrue(self.results[key]["metalCompiled"])

    def test_unsupported_or_non_dominating_output_use_remains_unproven(self) -> None:
        for key in (
            "componentBeforeWhole",
            "componentOnly",
            "secondWholeWrite",
            "laterReadOutsideMutation",
            "blueMutationOutsideProfile",
            "conditionalInitialization",
            "earlyReturn",
            "malformedMutationRHS",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.results[key]["channelUse"], "unproven")


if __name__ == "__main__":
    unittest.main()
