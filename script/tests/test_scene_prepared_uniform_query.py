#!/usr/bin/env python3
"""Prepared numeric binding -> geometry query and real Finalizer, without a device."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_resolved_material_program_finalizer as finalizer

ROOT = finalizer.REPOSITORY_ROOT
SCENE = finalizer.SCENE_ROOT
FIXTURE = Path(__file__).with_name("fixtures") / "ScenePreparedUniformQueryChecks.swift"
SOURCES = list(dict.fromkeys([
    *finalizer.SWIFT_SOURCES,
    *finalizer.SHARED_FIXTURE_SOURCES,
    SCENE / "Rendering/Geometry/SceneMatrix.swift",
    SCENE / "Rendering/Geometry/SceneDirectDrawOutputGeometry.swift",
    FIXTURE,
]))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@unittest.skipUnless(shutil.which("swiftc"), "Swift compiler required")
class ScenePreparedUniformQueryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-prepared-uniform-query-")
        cls.addClassCleanup(cls.temporary.cleanup)
        temporary = Path(cls.temporary.name)
        proof = os.environ.get("MWX_PREPARED_UNIFORM_QUERY_EVIDENCE")
        cls.proof = Path(proof) if proof else None
        if cls.proof:
            cls.proof.mkdir(parents=True, exist_ok=True)
        inputs = list(dict.fromkeys([*SOURCES, Path(__file__), Path(finalizer.__file__),
            ROOT / "script/scene_swift_source_sets.json",
            ROOT / "script/scene_swift_source_sets.py"]))
        before = {str(p.relative_to(ROOT)): digest(p) for p in inputs}
        frozen = temporary / "source"
        mapped = []
        for source in SOURCES:
            target = frozen / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            mapped.append(target)
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-D", "SCENE_GRAPH_TESTING",
            *map(str, mapped), "-framework", "Metal", "-framework", "CoreGraphics",
            "-framework", "ImageIO", "-module-cache-path", str(temporary / "modules"),
            "-o", str(temporary / "prepared-uniform-query")]
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(temporary / "shader-cache")
        environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
        if cls.proof:
            (cls.proof / "input-freeze.json").write_text(json.dumps(before, indent=2) + "\n")
            (cls.proof / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
        compilation = subprocess.run(command, cwd=ROOT, env=environment,
            capture_output=True, text=True, timeout=240)
        if cls.proof:
            (cls.proof / "compile.log").write_text(compilation.stdout + compilation.stderr)
            (cls.proof / "compile.json").write_text(json.dumps({
                "exitCode": compilation.returncode, "sourceCount": len(SOURCES),
                "compiledFromFrozenCopy": True,
            }, indent=2) + "\n")
        if compilation.returncode:
            raise AssertionError(compilation.stderr)
        completed = subprocess.run([str(temporary / "prepared-uniform-query")],
            cwd=temporary, env=environment, capture_output=True, text=True, timeout=60)
        drift = [name for name, value in before.items() if digest(ROOT / name) != value]
        if cls.proof:
            (cls.proof / "stdout.json").write_text(completed.stdout)
            (cls.proof / "stderr.log").write_text(completed.stderr)
            (cls.proof / "execution.json").write_text(json.dumps({
                "exitCode": completed.returncode, "inputCount": len(before),
                "inputDrift": drift, "createsMetalDevice": False,
                "gpuDispatches": 0, "appVMOperations": 0,
            }, indent=2) + "\n")
        if drift:
            raise AssertionError(f"frozen input drift: {drift}")
        if completed.returncode:
            raise AssertionError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)

    def check_group(self, name: str) -> None:
        facts = self.result[name]
        self.assertTrue(facts, name)
        self.assertEqual([key for key, value in facts.items() if value is not True], [], facts)

    def test_prepared_four_points_share_exact_program_bytes_and_geometry(self) -> None:
        self.check_group("fourPoints")

    def test_dynamic_sources_splat_range_and_live_value_preserve_existing_policy(self) -> None:
        self.check_group("dynamic")

    def test_query_and_finalizer_preserve_typed_failure_boundaries(self) -> None:
        self.check_group("failures")

    def test_non_float2_and_frame_identity_keep_their_own_boundaries(self) -> None:
        self.check_group("neighbors")


if __name__ == "__main__":
    unittest.main()
