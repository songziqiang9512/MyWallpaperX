#!/usr/bin/env python3

"""Completed CPU shader cache ownership and single-flight behavior.

build_probe() also prepares the original-owner footprint probe for an external
sampler. Run the returned binary with --footprint 256 524288 16; each JSON line
(ready, loaded, revisited) waits for one stdin line before proceeding. Use fresh
independent processes for baseline/candidate. The payload is synthetic MSL,
not compiler/GPU work; retainedWeightBytes is not RSS or physical footprint.
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

from script.tests.test_scene_generic_shader_program_artifact import (
    REPOSITORY_ROOT,
    SCENE_ROOT,
    SWIFT_SOURCES as ARTIFACT_SOURCES,
    scene_swift_sources,
)


HARNESS = Path(__file__).with_name("fixtures") / "SceneShaderCompletedCacheHarness.swift"
SWIFT_SOURCES = list(dict.fromkeys([
    *ARTIFACT_SOURCES,
    *scene_swift_sources("authored_shader_preparation_implementation"),
    SCENE_ROOT / "Resources/Textures/SceneTextureSampling.swift",
]))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_probe(directory: Path, *, baseline_evidence: Path | None = None) -> Path:
    """Build using canonical inputs, or the preserved pre-change owner sources.

    baseline_evidence is old-behavior-sol from this task's source freeze. Only
    its first compile-input region is used; the extra preparation inspection
    source and old Python test after that region are not baseline dependencies.
    Every frozen source is verified before compilation. Artifacts stay in the
    caller's directory so the root can sample both processes after this returns.
    """
    directory.mkdir(parents=True, exist_ok=True)
    if baseline_evidence is None:
        sources = SWIFT_SOURCES
        flags = []
    else:
        manifest = json.loads((baseline_evidence / "old-source-manifest.json").read_text())
        sources = []
        for entry in manifest["inputs"]:
            if entry["path"].endswith(".py"):
                break
            source = baseline_evidence / "source" / entry["path"]
            if sha256(source) != entry["sha256"]:
                raise AssertionError(f"baseline source drift: {entry['path']}")
            sources.append(source)
        flags = ["-D", "CACHE_RETENTION_BASELINE"]
    harness = directory / HARNESS.name
    shutil.copyfile(HARNESS, harness)
    inputs = [*sources, harness]
    before = [{"path": str(path), "sha256": sha256(path)} for path in inputs]
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
    environment["SWIFT_MODULECACHE_PATH"] = str(directory / "swift-cache")
    binary = directory / "shader-completed-cache-probe"
    command = [shutil.which("swiftc") or "swiftc", "-parse-as-library", *flags,
        *(str(path) for path in inputs), "-framework", "Security", "-o", str(binary)]
    result = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
        capture_output=True, text=True)
    after = [{"path": str(path), "sha256": sha256(path)} for path in inputs]
    (directory / "build-manifest.json").write_text(json.dumps({
        "implementation": "candidate" if baseline_evidence is None else "frozen-baseline",
        "command": command, "returncode": result.returncode,
        "stdout": result.stdout, "stderr": result.stderr,
        "inputsBefore": before, "inputsAfter": after, "inputDrift": before != after,
    }, ensure_ascii=False, indent=2) + "\n")
    if result.returncode != 0:
        raise AssertionError(result.stderr)
    if before != after:
        raise AssertionError("fixture inputs changed while compiling")
    return binary


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is unavailable")
class SceneShaderCompletedCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-completed-cache-")
        cls.binary = build_probe(Path(cls.directory.name))

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def output(self, mode: str) -> dict:
        completed = subprocess.run([str(self.binary), mode], cwd=REPOSITORY_ROOT,
            check=True, capture_output=True, text=True)
        return json.loads(completed.stdout)

    def test_repaired_compiler_failure_retries_through_both_original_owners(self):
        output = self.output("--retention")["composedRepair"]
        self.assertFalse(output["firstAccepted"])
        self.assertFalse(output["firstOuterCacheHit"])
        self.assertFalse(output["repairedOuterCacheHit"])
        self.assertTrue(output["repairedAccepted"], output)
        self.assertEqual(output["compilerOperations"], 2, output)

    def test_distinct_payload_reuse_and_overbudget_joined_callers(self):
        output = self.output("--retention")
        for name in ["smallDistinct", "largeDistinct"]:
            with self.subTest(payload=name):
                value = output[name]
                self.assertEqual(value["operations"], value["distinctInputs"], value)
                self.assertEqual(value["revisitHits"], value["distinctInputs"], value)
        for name in ["largeAcceptedConcurrent", "uncachedConcurrent"]:
            value = output[name]
            self.assertTrue(value["ownerReady"] and value["allStarted"]
                and value["allJoined"] and value["completed"], value)
            self.assertEqual(value["retainedBytes"], 0, value)
            self.assertEqual(value["retainedEntries"], 0, value)
            self.assertEqual(value["operations"], 1, value)
        accepted = output["largeAcceptedConcurrent"]
        self.assertEqual(accepted["acceptedResults"], accepted["callers"], accepted)

    def test_compiler_failed_flight_is_shared_but_later_request_retries(self):
        value = self.output("--retention")["compilerFailedConcurrent"]
        self.assertTrue(value["ownerReady"] and value["allJoined"] and value["completed"], value)
        self.assertEqual(value["sharedOperations"], 1, value)
        self.assertEqual(value["failureResults"], value["callers"], value)
        self.assertTrue(value["failureNotRetained"], value)
        self.assertTrue(value["repairSucceeded"], value)
        self.assertEqual(value["operationsAfterRepair"], 2, value)
        self.assertEqual(value["repairSource"], "spawn", value)

    def test_byte_lru_active_value_and_all_variable_typed_cost_fields(self):
        output = self.output("--bounds")
        for name, value in output.items():
            with self.subTest(behavior=name):
                self.assertIs(value, True, output)
        trim = self.output("--trim-hash")
        self.assertTrue(trim["correctLRU"], trim)
        self.assertEqual(trim["completedEntries"], 4, trim)
        self.assertEqual(trim["retainedBytes"], 4, trim)
        self.assertLessEqual(trim["trimHashCalls"], trim["hashCallLimit"], trim)

    def test_footprint_probe_has_explicit_sampling_phases_and_reuse(self):
        # Tiny protocol smoke check; this does not measure memory or performance.
        completed = subprocess.run([str(self.binary), "--footprint", "2", "16", "2"],
            input="continue\ncontinue\ncontinue\n", cwd=REPOSITORY_ROOT,
            check=True, capture_output=True, text=True)
        phases = [json.loads(line) for line in completed.stdout.splitlines()]
        self.assertEqual([item["phase"] for item in phases], ["ready", "loaded", "revisited"])
        self.assertEqual({item["pid"] for item in phases}, {phases[0]["pid"]})
        self.assertEqual([item["operations"] for item in phases], [0, 2, 2])
        self.assertEqual(phases[-1]["revisitHits"], 2)


if __name__ == "__main__":
    unittest.main()
