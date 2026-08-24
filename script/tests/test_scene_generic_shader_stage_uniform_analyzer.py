#!/usr/bin/env python3

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


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderStageUniformAnalyzer.swift",
]

HARNESS = r'''
import Foundation

private struct Output: Codable {
    let withoutFacts: Bool
    let withFacts: Bool
    let wrongStageFacts: Bool
}

@main
private struct StageUniformAnalyzerHarness {
    static func main() throws {
        let vertex = """
        uniform mat4 g_ModelViewProjectionMatrix;
        uniform float u_vertexScale;
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            gl_Position = mul(vec4(a_Position * u_vertexScale, 1.0), g_ModelViewProjectionMatrix);
            v_TexCoord = a_TexCoord;
        }
        """
        let fragment = """
        uniform float u_fractals;
        varying vec2 v_TexCoord;
        void main() {
            float value = v_TexCoord.x;
            for (int i = 0; i <= int(u_fractals); i++) {
                value += float(i);
            }
            gl_FragColor = vec4(value, value, value, 1.0);
        }
        """
        let withoutFacts = SceneGenericShaderStageUniformAnalyzer.hasScopedBindings(
            vertexSource: vertex,
            fragmentSource: fragment
        )
        let withFacts = SceneGenericShaderStageUniformAnalyzer.hasScopedBindings(
            vertexSource: vertex,
            fragmentSource: fragment,
            runtimeLoopBounds: .init(
                vertex: [:],
                fragment: ["u_fractals": 4]
            )
        )
        let wrongStageFacts = SceneGenericShaderStageUniformAnalyzer.hasScopedBindings(
            vertexSource: vertex,
            fragmentSource: fragment,
            runtimeLoopBounds: .init(
                vertex: ["u_fractals": 4],
                fragment: [:]
            )
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(Output(
            withoutFacts: withoutFacts,
            withFacts: withFacts,
            wrongStageFacts: wrongStageFacts
        )))
    }
}
'''


class SceneGenericShaderStageUniformAnalyzerTests(unittest.TestCase):
    def test_runtime_loop_facts_match_the_frontend_analysis_boundary(self):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="mwx-stage-uniform-analyzer-"
        ) as directory:
            root = Path(directory)
            harness = root / "StageUniformAnalyzerHarness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "stage-uniform-analyzer-harness"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(
                root / "clang-module-cache"
            )
            environment["SWIFT_MODULECACHE_PATH"] = str(
                root / "swift-module-cache"
            )
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
            result = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            output = json.loads(result.stdout)
            self.assertFalse(output["withoutFacts"])
            self.assertTrue(output["withFacts"])
            self.assertFalse(output["wrongStageFacts"])


if __name__ == "__main__":
    unittest.main()
