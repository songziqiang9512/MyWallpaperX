#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPO_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPO_ROOT / "script"))

from script.tests.test_scene_shader_scalar_vector_builtin_canonicalization import (
    SWIFT_SOURCES as CANONICALIZER_SWIFT_SOURCES,
)


SWIFT_SOURCES = list(CANONICALIZER_SWIFT_SOURCES)



HARNESS = r"""
import Foundation
import Metal

private struct HarnessOutput: Codable {
    let diagnosticCodes: [String]
    let schemaSamplerSlots: [Int]?
    let staticLoopWork: Int?
    let textureSlots: [Int]?
    let textureChannelUses: [String]?
    let uniformNames: [String]?
    let offscreenWidth: Int?
    let offscreenHeight: Int?
    let metalSource: String?
    let metalError: String?
}

@main
private struct AuthoredShaderFrontendHarness {
    static func main() throws {
        let vertexSource = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        let fragmentSource = try String(
            contentsOfFile: CommandLine.arguments[2],
            encoding: .utf8
        )
        var vertexLoopBounds: [String: Int] = [:]
        var fragmentLoopBounds: [String: Int] = [:]
        for argument in CommandLine.arguments.dropFirst(3) {
            let prefixes = [
                ("--vertex-loop-bound=", true),
                ("--fragment-loop-bound=", false),
            ]
            for (prefix, isVertex) in prefixes where argument.hasPrefix(prefix) {
                let payload = argument.dropFirst(prefix.count).split(
                    separator: "=",
                    maxSplits: 1
                )
                guard payload.count == 2, let maximum = Int(payload[1]) else { continue }
                if isVertex {
                    vertexLoopBounds[String(payload[0])] = maximum
                } else {
                    fragmentLoopBounds[String(payload[0])] = maximum
                }
            }
        }
        let compilerSources = CommandLine.arguments.dropFirst(3).contains("--canonicalize")
            ? SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: vertexSource, fragment: fragmentSource
            )
            : SceneAuthoredShaderBackendCanonicalizer.Pair(
                vertex: vertexSource, fragment: fragmentSource
            )
        let output = SceneAuthoredShaderFrontend.compile(
            vertexSource: compilerSources.vertex,
            fragmentSource: compilerSources.fragment,
            runtimeLoopBounds: .init(
                vertex: vertexLoopBounds,
                fragment: fragmentLoopBounds
            )
        )
        let schemaSamplerSlots = SceneAuthoredShaderDeadBindingAnalyzer
            .activeSamplerNamesForSchema(
                vertexSource: vertexSource,
                fragmentSource: fragmentSource
            )?
            .compactMap { name -> Int? in
                guard name.hasPrefix("g_Texture") else { return nil }
                return Int(name.dropFirst("g_Texture".count))
            }
            .sorted()
        var metalError: String?
        if let program = output.program,
           !CommandLine.arguments.dropFirst(3).contains("--skip-metal") {
            do {
                guard let device = MTLCreateSystemDefaultDevice() else {
                    throw NSError(
                        domain: "AuthoredShaderFrontendHarness",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"]
                    )
                }
                _ = try device.makeLibrary(source: program.metalSource, options: nil)
            } catch {
                metalError = String(describing: error)
            }
        }
        let encoded = try JSONEncoder().encode(HarnessOutput(
            diagnosticCodes: output.diagnostics.map { $0.code.rawValue },
            schemaSamplerSlots: schemaSamplerSlots,
            staticLoopWork: output.program?.staticLoopWork,
            textureSlots: output.program?.textureBindings.map(\.slot),
            textureChannelUses: output.program?.textureBindings.map {
                $0.channelUse.rawValue
            },
            uniformNames: output.program?.uniformLayout.fields.map(\.name),
            offscreenWidth: output.program?.offscreenSize(
                viewportSize: CGSize(width: 3840, height: 2160)
            ).map { Int($0.width) },
            offscreenHeight: output.program?.offscreenSize(
                viewportSize: CGSize(width: 3840, height: 2160)
            ).map { Int($0.height) },
            metalSource: output.program?.metalSource,
            metalError: metalError
        ))
        FileHandle.standardOutput.write(encoded)
    }
}
"""

VERTEX_SOURCE = """
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
"""

VEC4_COORDINATE_VERTEX_SOURCE = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_Coordinates;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_Coordinates = vec4(a_TexCoord, 0.0, 1.0);
}
"""


class AuthoredShaderFrontendHarness:
    def evaluate(self, metal_source, kernel, count):
        binary = self.binary.parent / 'expression-probe'
        if not binary.exists():
            compiled = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(Path(__file__).with_name('fixtures') /
                'SceneShaderExpressionProbe.swift'), '-o', str(binary)],
                capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'expression.metal'
            source.write_text(metal_source + '\n' + kernel)
            result = subprocess.run([str(binary), str(source), str(count)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "AuthoredShaderFrontendHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "authored-shader-frontend-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(build_root / "clang-module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(build_root / "swift-module-cache")
        subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPO_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.build_directory.cleanup()

    def compile(self, vertex_source, fragment_source, *, metal=True, loop_bounds=None,
                canonicalize=False):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            vertex = root / "fixture.vert"
            fragment = root / "fixture.frag"
            vertex.write_text(textwrap.dedent(vertex_source), encoding="utf-8")
            fragment.write_text(textwrap.dedent(fragment_source), encoding="utf-8")
            command = [str(self.binary), str(vertex), str(fragment)]
            if canonicalize:
                command.append("--canonicalize")
            for stage, bounds in sorted((loop_bounds or {}).items()):
                for name, maximum in sorted(bounds.items()):
                    command.append(f"--{stage}-loop-bound={name}={maximum}")
            if not metal:
                command.append("--skip-metal")
            completed = subprocess.run(
                command,
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        return json.loads(completed.stdout)
