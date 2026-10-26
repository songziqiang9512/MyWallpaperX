#!/usr/bin/env python3
"""Same-preparation normalization reuse with real compiler configuration and helpers."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

from script.tests.scene_compiler_fixture import compiler_bundle, fixture_sources
from script.tests.test_scene_generic_shader_program_artifact import REPOSITORY_ROOT, SWIFT_SOURCES


CHECKS = REPOSITORY_ROOT / "script/tests/fixtures/SceneGenericShaderPreparedNormalizationChecks.swift"


def source_hashes(paths: list[Path]) -> dict[str, str]:
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def fixture_environment(root: Path) -> dict[str, str]:
    environment = {name: value for name, value in os.environ.items()
                   if not name.startswith("MWX_SCENE_GENERIC_SHADER_")}
    home = root / "home"
    home.mkdir(parents=True, exist_ok=True)
    environment.update(HOME=str(home), CFFIXED_USER_HOME=str(home),
                       CLANG_MODULE_CACHE_PATH=str(root / "clang-module-cache"),
                       SWIFT_MODULECACHE_PATH=str(root / "swift-module-cache"))
    return environment


class SceneGenericShaderPreparedNormalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        evidence = os.environ.get("MWX_SHADER_NORMALIZATION_EVIDENCE")
        if evidence:
            Path(evidence).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="mwx-prepared-normalization-", dir=evidence))
        cls.keep = bool(evidence)
        cls.bundle = compiler_bundle(cls.root)
        cls.bundles = [cls.bundle]
        for label, limit in (("low", 1_024), ("high", 1_024 * 1_024)):
            copy = cls.root / f"{label}.bundle"
            shutil.copytree(cls.bundle, copy)
            manifest_path = copy / "Contents/Resources/SceneShaderCompilerLicenses.bundle/Contents/Resources/product-manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["limits"]["maximumStageSourceBytes"] = limit
            manifest_path.write_text(json.dumps(manifest))
            cls.bundles.append(copy)
        missing = cls.root / "missing.bundle"
        (missing / "Contents").mkdir(parents=True)
        (missing / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.mywallpaperx.prepared-normalization-missing",
            "CFBundlePackageType": "BNDL", "CFBundleVersion": "1",
        }))
        cls.bundles.append(missing)
        sources = fixture_sources(cls.root, cls.bundle,
                                  list(dict.fromkeys(path.resolve() for path in [*SWIFT_SOURCES, CHECKS])))
        identity = cls.root / "SceneShaderCacheIdentity.json"
        identity.write_text(json.dumps({
            "schemaVersion": 1, "semantics": "a" * 64, "toolchain": "b" * 64,
        }))
        cls.inputs = [*sources, identity,
                      *(path for bundle in cls.bundles for path in bundle.rglob("*") if path.is_file())]
        cls.before = source_hashes(cls.inputs)
        cls.binary = cls.root / "prepared-normalization"
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-O",
                   *map(str, sources), "-framework", "Security", "-module-cache-path",
                   str(cls.root / "module-cache"), "-o", str(cls.binary)]
        compiled = subprocess.run(command, cwd=REPOSITORY_ROOT, env=fixture_environment(cls.root),
                                  capture_output=True, text=True, timeout=300)
        (cls.root / "compile.json").write_text(json.dumps({
            "command": command, "returncode": compiled.returncode,
            "stdout": compiled.stdout, "stderr": compiled.stderr,
            "inputSHA256": cls.before,
        }, indent=2))
        if compiled.returncode:
            cls.keep = True
            raise AssertionError(f"Prepared normalization compilation failed; evidence {cls.root}\n{compiled.stderr}")

    @classmethod
    def tearDownClass(cls) -> None:
        if not cls.keep:
            shutil.rmtree(cls.root)

    def run_harness(self, mode: str) -> dict:
        root = self.root / mode
        root.mkdir()
        cache = root / "cache"
        cache.mkdir()
        environment = fixture_environment(root)
        environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(cache)
        command = [str(self.binary), mode, str(root), *map(str, self.bundles)]
        result = subprocess.run(command, cwd=root, env=environment,
                                capture_output=True, text=True, timeout=180)
        after = source_hashes(self.inputs)
        (root / "result.json").write_text(json.dumps({
            "command": command, "returncode": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr,
            "inputSHA256Before": self.before, "inputSHA256After": after,
        }, indent=2))
        if result.returncode or after != self.before:
            self.__class__.keep = True
            self.fail(f"Prepared normalization {mode} failed; evidence {root}\n{result.stderr}")
        return json.loads(result.stdout)

    def test_same_pair_preserves_actual_artifact_program_and_analysis_cache(self) -> None:
        report = self.run_harness("equivalence")
        self.assertEqual(len(report["rows"]), 3)
        self.assertTrue(all(not row["warmHasPair"] for row in report["rows"]))
        self.assertEqual(report["rows"][2]["audioArrays"],
                         ["g_AudioSpectrum16Left", "g_AudioSpectrum16Right"])

    def test_compiler_owns_configuration_raw_and_normalized_budgets(self) -> None:
        report = self.run_harness("budgets")
        self.assertEqual(report["rawFailures"], ["sourceTooLarge", "sourceTooLarge"])
        self.assertTrue(report["bundleFirst"])
        self.assertTrue(report["outputBudget"])
        self.assertGreater(report["largeRawBytes"], 512 * 1_024)
        self.assertTrue(report["largeCompiled"])
        self.assertTrue(report["routeFailureRetriedByCompiler"])


if __name__ == "__main__":
    unittest.main()
