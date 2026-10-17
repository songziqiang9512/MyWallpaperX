#!/usr/bin/env python3
"""Numeric output definition facts and their real frontend cache transport.

This CPU-only gate uses the canonical, already-compilable frontend and
preprocessor carriers. It never creates a Metal device or executes an App.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import unittest

from script.tests import test_scene_shader_color_contract as color
from script.tests import test_scene_shader_preprocessor as preprocessor


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_name("fixtures") / "SceneShaderFragmentOutputHarness.swift"
SWIFT_SOURCES = list(dict.fromkeys([*color.SWIFT_SOURCES, *preprocessor.SWIFT_SOURCES]))
POSITIVE = {
    "old-whole", "old-component-add", "mix", "renamed-equivalent",
    "conditional-mutation", "repeated-read-swizzle", "constructor-read",
    "old-unrelated-call",
}
COMPILED = POSITIVE - {"old-unrelated-call"}
NEGATIVE = {
    "preinit-read", "initializer-read", "initializer-nested-write",
    "conditional-init", "no-whole-init", "multiple-whole-init", "early-return",
    "discard", "blue-read", "whole-read", "read-escapes-mutation", "unknown-call",
    "unexpanded-blending", "out-parameter", "inout-parameter", "nested-increment",
    "nested-assignment", "duplicate-lvalue", "mixed-swizzle", "shadowed-builtin",
    "ambiguous-helper", "pure-helper-not-opened", "helper-unknown-call",
    "unknown-nested-argument", "nested-other-assignment", "pure-shadowed-builtin",
}


def identity(path: Path) -> dict:
    data = path.read_bytes()
    return {"path": str(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


class SceneShaderFragmentOutputTests(unittest.TestCase):
    @classmethod
    def record(cls, name: str, value) -> None:
        if cls.proof:
            data = value if isinstance(value, bytes) else (json.dumps(value, indent=2) + "\n").encode()
            (cls.proof / name).write_bytes(data)

    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.proof = Path(os.environ["MWX_FRAGMENT_OUTPUT_PROOF"]) if os.environ.get("MWX_FRAGMENT_OUTPUT_PROOF") else None
        if cls.proof:
            cls.proof.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-fragment-output-")
        cls.work = Path(cls.temporary.name)
        cls.app = cls.work / "Probe.app"
        cls.binary = cls.app / "Contents/MacOS/probe"
        cls.binary.parent.mkdir(parents=True)
        (cls.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.songziqiang.MyWallpaperX",
            "CFBundleExecutable": "probe", "CFBundlePackageType": "APPL",
        }))
        cls.inputs = [*SWIFT_SOURCES, FIXTURE, Path(__file__),
                      Path(color.__file__), Path(preprocessor.__file__),
                      ROOT / "script/scene_swift_source_sets.py"]
        cls.before = [identity(path) for path in cls.inputs]
        cls.record("inputs-before.json", cls.before)
        cls.environment = {**os.environ, "CLANG_MODULE_CACHE_PATH": str(cls.work / "clang-cache"),
                           "SWIFT_MODULECACHE_PATH": str(cls.work / "swift-cache")}
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                   *map(str, SWIFT_SOURCES), str(FIXTURE),
                   "-module-cache-path", str(cls.work / "module-cache"), "-o", str(cls.binary)]
        cls.record("compile-command.json", command)
        started = time.monotonic()
        try:
            compiled = subprocess.run(command, cwd=ROOT, env=cls.environment,
                                      capture_output=True, timeout=180)
            cls.record("compile.stdout", compiled.stdout)
            cls.record("compile.stderr", compiled.stderr)
            cls.record("compile-result.json", {"exit": compiled.returncode, "seconds": time.monotonic() - started})
            if compiled.returncode:
                raise AssertionError(compiled.stderr.decode(errors="replace"))
        except BaseException:
            cls.finish_inputs()
            cls.temporary.cleanup()
            raise

    @classmethod
    def finish_inputs(cls) -> None:
        after = [identity(path) for path in cls.inputs]
        cls.record("inputs-after.json", after)
        drift = [a["path"] for a, b in zip(cls.before, after) if a != b]
        cls.record("source-drift.json", drift)
        if drift:
            raise AssertionError(f"production/fixture input drift: {drift}")

    @classmethod
    def tearDownClass(cls) -> None:
        try:
            cls.finish_inputs()
        finally:
            cls.temporary.cleanup()
            cls.record("retirement.json", {"temporaryRemoved": not cls.work.exists(), "GPUInvocations": 0})

    def run_probe(self, mode: str, home: Path, *arguments: str) -> dict:
        home.mkdir(exist_ok=True)
        environment = {**self.environment, "HOME": str(home), "CFFIXED_USER_HOME": str(home)}
        command = ["/usr/bin/env", str(self.binary), mode, *arguments]
        completed = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, timeout=30)
        label = f"{home.name}-{mode}"
        self.record(f"{label}-command.json", command)
        self.record(f"{label}.json", completed.stdout)
        self.record(f"{label}.stderr", completed.stderr)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        output = json.loads(completed.stdout)
        self.assertTrue(output["cacheDirectory"].startswith(str(home) + "/"), output)
        return output

    def test_initialized_output_reads_and_unsafe_escapes(self) -> None:
        payload = self.run_probe("facts", self.work / "semantic-home")
        self.assertEqual(payload["legacyColorPolicies"],
                         {"authoredReadOnlyHelper": True, "legacyUnexpandedBlending": True})
        output = payload["cases"]
        self.assertEqual(set(output), POSITIVE | NEGATIVE)
        for name, fact in output.items():
            with self.subTest(case=name):
                expected = "redDefined" if name in POSITIVE else "unproven"
                self.assertEqual(fact["sourceFact"], expected, fact)
                if name == "discard":
                    # The existing syntax owner rejects discard before this
                    # proof is entered; it must still fail closed end to end.
                    self.assertGreater(fact["syntaxDiagnostics"], 0, fact)
                    self.assertNotIn("unitFact", fact)
                    continue
                self.assertEqual(fact["syntaxDiagnostics"], 0, fact)
                self.assertEqual(fact["unitFact"], expected, fact)
                if name in COMPILED:
                    self.assertEqual(fact["boundedDiagnostics"], [], fact)
                    self.assertEqual(fact["boundedFact"], expected, fact)
        # Task-local actual prepared input is optional; no corpus source is a
        # permanent dependency of this public semantic gate.
        actual = os.environ.get("MWX_FRAGMENT_OUTPUT_ACTUAL_INPUT")
        if actual:
            variants = self.run_probe("actual-variant", self.work / "actual-home", actual)["variants"]
            self.assertEqual([v["collisionTexturePresent"] for v in variants], [False, True])
            for variant in variants:
                self.assertEqual(variant["facts"]["sourceFact"], "redDefined", variant)
                self.assertEqual(variant["facts"]["unitFact"], "redDefined", variant)

    def test_frontend_cold_warm_processes_preserve_complete_program(self) -> None:
        home = self.work / "cache-home"
        cold = self.run_probe("cache", home)
        files = sorted(home.rglob("*.json"))
        self.assertEqual(len(files), 2)
        published = {str(path): (path.read_bytes(), path.stat().st_mtime_ns) for path in files}
        warm = self.run_probe("cache", home)
        self.assertEqual(cold, warm)  # Every serialized Program field, not only the new fact.
        self.assertEqual(cold["completedBefore"], 0)
        self.assertEqual(cold["completedAfter"], 2)
        self.assertEqual({str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in home.rglob("*.json")}, published)
        for program in cold["programs"].values():
            self.assertEqual(program["fragmentOutputChannelUse"], "redDefined")
        self.record("cache-file-identities.json", [identity(path) for path in files])


if __name__ == "__main__":
    unittest.main()
