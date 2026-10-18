"""Run the real generic compiler with development evidence enabled by argv.

The two configurations use signed glslang/spirv-cross helpers and the existing
frontend/compiler/Program source closure. This checks artifact publication and
Program admission, not GPU execution or whole-App Release packaging.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_generic_shader_float_array_index import SWIFT_SOURCES
from script.tests.test_scene_generic_shader_texture_transform_compiler import compiler_bundle


ROOT = Path(__file__).resolve().parents[2]
FLAG = "--mwx-debug-scene-evidence-dir"
KEY = "a" * 64
HARNESS = r'''
import Foundation

@main private enum Check {
    static func main() throws {
        guard CommandLine.arguments.count >= 3,
              let bundle = Bundle(path: CommandLine.arguments[1]) else {
            throw NSError(domain: "compiler-fixture", code: 1)
        }
        let cache = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let vertex = """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            gl_Position = vec4(a_Position, 1.0);
            v_TexCoord = a_TexCoord;
        }
        """
        let fragment = """
        uniform sampler2D g_Texture0;
        varying vec2 v_TexCoord;
        void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
        """
        let key = String(repeating: "a", count: 64)
        let url: URL
        switch SceneGenericShaderCompiler.compile(
            requestKey: key, vertexSource: vertex, fragmentSource: fragment,
            cacheRoot: cache, bundle: bundle
        ) {
        case let .success(value): url = value
        case let .failure(failure):
            throw NSError(domain: "real-generic-compiler", code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(describing: failure)])
        }
        let data = try Data(contentsOf: url)
        let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self, from: data)
        guard let contract = SceneAuthoredShaderFrontend.compile(
                vertexSource: vertex, fragmentSource: fragment).program,
              let program = artifact.makeProgram(
                expectedKey: key, expectedColorTransfer: contract.colorTransfer,
                expectedFragmentOutputChannelUse: contract.fragmentOutputChannelUse),
              !program.metalSource.isEmpty else {
            throw NSError(domain: "real-program-admission", code: 3)
        }
        let output: [String: Any] = [
            "artifactPath": url.path,
            "artifactSHA256": SceneGenericShaderProgramArtifact.sha256(data),
            "metalSHA256": artifact.program.metalSourceSHA256,
            "programAdmitted": true,
        ]
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]))
    }
}
'''


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SceneCompilerReleaseEvidenceTests(unittest.TestCase):
    def test_release_ignores_evidence_flag_and_debug_exports_same_program(self):
        parent = os.environ.get("MWX_RELEASE_COMPILER_TEST_ROOT")
        evidence_setting = os.environ.get("MWX_RELEASE_COMPILER_EVIDENCE")
        evidence = Path(evidence_setting) if evidence_setting else None
        if evidence:
            evidence.mkdir(parents=True, exist_ok=False)
        report = {
            "scope": "real compiler helpers and Program admission; no GPU or whole-App packaging acceptance",
            "configurations": {},
        }
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-evidence-", dir=parent) as raw:
            temporary = Path(raw)
            harness = temporary / "Harness.swift"
            harness.write_text(HARNESS)
            before = {str(path.relative_to(ROOT)): sha256(path) for path in SWIFT_SOURCES}
            frozen = []
            for path in SWIFT_SOURCES:
                destination = temporary / "source" / path.relative_to(ROOT)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
                frozen.append(destination)
            report["sourceHashes"] = before
            report["harnessSHA256"] = sha256(harness)
            bundle = compiler_bundle(temporary)
            report["signedHelperHashes"] = {
                str(path.relative_to(bundle)): sha256(path)
                for path in bundle.rglob("*") if path.is_file()
            }
            environment = os.environ.copy()
            environment.update(
                TMPDIR=str(temporary / "tmp"),
                CLANG_MODULE_CACHE_PATH=str(temporary / "clang-cache"),
                SWIFT_MODULECACHE_PATH=str(temporary / "swift-cache"),
            )
            (temporary / "tmp").mkdir()
            artifacts = {}
            try:
                for name, flags in [("release", []), ("debug", ["-D", "DEBUG"])]:
                    binary = temporary / name
                    command = [
                        "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-O",
                        *flags, *map(str, frozen), str(harness), "-framework", "Security",
                        "-module-cache-path", str(temporary / "modules"), "-o", str(binary),
                    ]
                    compiled = subprocess.run(command, cwd=temporary, env=environment,
                                              capture_output=True, text=True, timeout=240)
                    state = {"command": command, "compileExit": compiled.returncode}
                    report["configurations"][name] = state
                    if evidence:
                        (evidence / f"{name}-compile.log").write_text(compiled.stdout + compiled.stderr)
                    self.assertEqual(compiled.returncode, 0, compiled.stderr)
                    state["binarySHA256"] = sha256(binary)
                    state["binaryContainsEvidenceFlag"] = FLAG.encode() in binary.read_bytes()
                    self.assertEqual(state["binaryContainsEvidenceFlag"], name == "debug")
                    exports = temporary / f"{name}-exports"
                    exports.mkdir()
                    sentinel = exports / "sentinel.txt"
                    sentinel.write_text("existing evidence directory remains untouched in Release")
                    sentinel_hash = sha256(sentinel)
                    command = [str(binary), str(bundle), str(temporary / f"{name}-cache"), FLAG, str(exports)]
                    run = subprocess.run(command, cwd=temporary, env=environment,
                                         capture_output=True, text=True, timeout=45)
                    state.update(runCommand=command, runExit=run.returncode)
                    if evidence:
                        (evidence / f"{name}-run.log").write_text(run.stdout + "\n" + run.stderr)
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    result = json.loads(run.stdout)
                    self.assertTrue(result["programAdmitted"])
                    artifact_path = Path(result["artifactPath"])
                    artifacts[name] = json.loads(artifact_path.read_bytes())
                    state["result"] = result
                    exported = sorted(path.name for path in exports.iterdir() if path != sentinel)
                    state["exportedFiles"] = exported
                    self.assertEqual(sha256(sentinel), sentinel_hash)
                    expected = sorted(f"{KEY}.{suffix}" for suffix in [
                        "vertex.normalized.glsl", "fragment.normalized.glsl", "vertex.metal", "fragment.metal"
                    ]) if name == "debug" else []
                    self.assertEqual(exported, expected)
                    for exported_path in exports.iterdir():
                        self.assertGreater(exported_path.stat().st_size, 0)
                    if evidence:
                        shutil.copy2(artifact_path, evidence / f"{name}-artifact.json")
                        if name == "debug":
                            shutil.copytree(exports, evidence / "debug-exports")
                self.assertEqual(artifacts["release"], artifacts["debug"],
                                 "debug evidence changed the compiler artifact or Program")
                report["completeArtifactsEqual"] = True
                report["sourceHashesUnchanged"] = before == {
                    str(path.relative_to(ROOT)): sha256(path) for path in SWIFT_SOURCES
                }
                self.assertTrue(report["sourceHashesUnchanged"], "live source closure changed during the gate")
                report["passed"] = True
            finally:
                if evidence:
                    (evidence / "identity.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    unittest.main()
