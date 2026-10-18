#!/usr/bin/env python3
"""Actual graph-content identity, consumer invalidation, and cross-process reuse."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_scene_persistent_cache_behavior import HARNESS, SUPPORT, SWIFT_SOURCES


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "script/tests/fixtures/SceneShaderDependencyCacheChecks.swift"


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneShaderDependencyCacheIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-dependency-cache-")
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / "dependency-cache-probe"
        support = cls.work / "Support.swift"
        harness = cls.work / "Harness.swift"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(
            HARNESS.split("@main\nprivate enum ProbeEntrypoint", 1)[0]
            + FIXTURE.read_text(encoding="utf-8"), encoding="utf-8"
        )
        (cls.work / "SceneShaderCacheIdentity.json").write_text(
            json.dumps({"schemaVersion": 1, "semantics": "a" * 64,
                        "toolchain": "b" * 64}), encoding="utf-8"
        )
        sources = list(dict.fromkeys(str(path) for path in SWIFT_SOURCES))
        command = [
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            str(support), *sources, str(harness), "-framework", "Metal",
            "-framework", "CoreGraphics", "-module-cache-path",
            str(cls.work / "module-cache"), "-o", str(cls.binary),
        ]
        cls.environment = {**os.environ,
            "CLANG_MODULE_CACHE_PATH": str(cls.work / "clang-cache"),
            "SWIFT_MODULECACHE_PATH": str(cls.work / "swift-cache")}
        compiled = subprocess.run(command, cwd=ROOT, env=cls.environment,
            capture_output=True, text=True)
        if compiled.returncode:
            cls.temporary.cleanup()
            raise AssertionError(compiled.stdout + compiled.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def probe(self, mode: str, root: Path) -> list[str]:
        root.mkdir(exist_ok=True)
        completed = subprocess.run(
            ["/usr/bin/env", str(self.binary), mode], cwd=ROOT,
            env={**self.environment, "MWX_SCENE_GENERIC_SHADER_CACHE": str(root)},
            capture_output=True, text=True, timeout=45,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        facts = json.loads(completed.stdout)
        self.assertIsNone(facts.get("failure"))
        self.assertTrue(facts["checks"])
        return facts["checks"]

    def test_actual_graph_content_and_decoding_define_identity(self) -> None:
        checks = self.probe("identity", self.work / "identity")
        self.assertIn("self-reported-hashes-cannot-hide-source-change", checks)
        self.assertIn("injected-derived-digest-ignored", checks)
        self.assertIn("in-process-demand-key-covers-dependencies", checks)

    def test_include_change_reaches_variant_consumer(self) -> None:
        checks = self.probe("consumer", self.work / "consumer")
        self.assertIn("unchanged-consumer-reuses-canonical-sources", checks)
        self.assertIn("new-include-cannot-be-overwritten-by-old-canonical-source", checks)

    def test_cold_publish_and_fresh_process_warm_hit_preserve_files(self) -> None:
        root = self.work / "cross-process"
        self.probe("cold-write", root)
        before = {str(path.relative_to(root)): (path.read_bytes(), path.stat().st_mtime_ns)
                  for path in root.rglob("*.json")}
        self.assertEqual(len(before), 4)
        checks = self.probe("warm-read", root)
        after = {str(path.relative_to(root)): (path.read_bytes(), path.stat().st_mtime_ns)
                 for path in root.rglob("*.json")}
        self.assertEqual(before, after)
        self.assertIn("variant-records-remain-distinct", checks)
        self.assertIn("demand-records-remain-distinct", checks)


if __name__ == "__main__":
    unittest.main()
