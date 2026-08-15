#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import time
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROCESS_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/"
    "SceneGenericShaderCompilerProcess.swift"
)

HARNESS = r"""
import Foundation

private struct Output: Encodable {
    let status: String
    let failure: String?
    let stdout: String?
}

@main
private struct CompilerProcessHarness {
    static func main() throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let timeout = Int(CommandLine.arguments[2])!
        let diagnostics = Int(CommandLine.arguments[3])!
        let resident = Int(CommandLine.arguments[4])!
        let arguments = Array(CommandLine.arguments.dropFirst(5))
        let output: Output
        switch SceneGenericShaderCompilerProcess.run(
            executable: executable,
            arguments: arguments,
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutMilliseconds: timeout,
            maximumDiagnosticBytes: diagnostics,
            maximumResidentBytes: resident
        ) {
        case let .success(result):
            output = .init(
                status: "passed",
                failure: nil,
                stdout: String(decoding: result.stdout, as: UTF8.self)
            )
        case let .failure(failure):
            output = .init(
                status: "failed",
                failure: String(describing: failure),
                stdout: nil
            )
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
"""


class SceneGenericShaderCompilerProcessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        root = Path(cls.build_directory.name)
        harness = root / "CompilerProcessHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "compiler-process-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-module-cache")
        subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                str(PROCESS_SOURCE),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.build_directory.cleanup()

    def run_process(
        self,
        executable: str,
        *arguments: str,
        timeout: int = 1_000,
        diagnostics: int = 1_024,
        resident: int = 512 * 1_024 * 1_024,
    ) -> tuple[dict, float]:
        started = time.monotonic()
        completed = subprocess.run(
            [
                str(self.binary), executable, str(timeout), str(diagnostics),
                str(resident), *arguments,
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout), time.monotonic() - started

    def test_success_and_nonzero_exit_are_distinct(self):
        passed, _ = self.run_process("/usr/bin/printf", "worker-ok")
        self.assertEqual(passed, {
            "status": "passed", "stdout": "worker-ok"
        })
        rejected, _ = self.run_process("/usr/bin/false")
        self.assertEqual(rejected["status"], "failed")
        self.assertIn("rejected(exitCode: 1)", rejected["failure"])

    def test_timeout_kills_the_exact_helper(self):
        output, elapsed = self.run_process(
            "/bin/sleep", "2", timeout=100
        )
        self.assertEqual(output["failure"], "timeout")
        self.assertLess(elapsed, 1.0)

    def test_uncaught_signal_is_not_reported_as_an_exit_code(self):
        output, _ = self.run_process(
            "/bin/sh", "-c", "kill -9 $$"
        )
        self.assertEqual(output["status"], "failed")
        self.assertEqual(output["failure"], "signaled(signal: 9)")

    def test_diagnostic_budget_stops_unbounded_output(self):
        output, _ = self.run_process(
            "/usr/bin/yes", timeout=2_000, diagnostics=128
        )
        self.assertEqual(output["failure"], "diagnosticBudget")

    def test_resident_budget_stops_the_helper(self):
        python = "/usr/bin/python3"
        if not Path(python).is_file():
            self.skipTest("system python3 is unavailable")
        output, elapsed = self.run_process(
            python,
            "-c",
            textwrap.dedent("""
                import time
                value = bytearray(96 * 1024 * 1024)
                time.sleep(2)
            """),
            timeout=2_000,
            resident=32 * 1_024 * 1_024,
        )
        self.assertEqual(output["failure"], "residentBudget")
        self.assertLess(elapsed, 1.5)


if __name__ == "__main__":
    unittest.main()
