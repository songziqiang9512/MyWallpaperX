#!/usr/bin/env python3

"""Native VM regression for the particle-instance layer journal boundary."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

if __package__:
    from .scene_vector_vm_test_support import C_SOURCES, ROOT, VM, QUICKJS
else:
    from scene_vector_vm_test_support import C_SOURCES, ROOT, VM, QUICKJS


@unittest.skipUnless(shutil.which("clang"), "clang is required")
class SceneParticleInstanceHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._temporary = tempfile.TemporaryDirectory(prefix="mwx-particle-instance-host-")
        cls.binary = Path(cls._temporary.name) / "harness"
        harness = ROOT / "script/tests/fixtures/SceneParticleInstanceHostHarness.c"
        result = subprocess.run(
            [shutil.which("clang"), "-std=c11", "-O0", "-I", str(VM), "-I", str(QUICKJS),
             *map(str, C_SOURCES), str(harness), "-lm", "-o", str(cls.binary)],
            cwd=ROOT, capture_output=True, text=True, timeout=120,
        )
        if result.returncode != 0:
            cls._temporary.cleanup()
            raise AssertionError(result.stdout + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls._temporary.cleanup()

    def run_case(self, name):
        result = subprocess.run([str(self.binary), name], cwd=ROOT,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_identity_overlay_and_distinct_layer_alpha(self):
        self.run_case("access")

    def test_finite_number_and_unsupported_surfaces(self):
        self.run_case("invalid")

    def test_throw_discard_generation_and_owner_baseline(self):
        self.run_case("rollback")

    def test_commit_rollback_reuse_and_cached_destroyed_instance(self):
        self.run_case("snapshot")

    def test_exact_budget_and_caught_overflow_reject_partial_export(self):
        self.run_case("budget")

    def test_native_emit_hook_reads_each_call_prefix(self):
        self.run_case("prefix")


if __name__ == "__main__":
    unittest.main()
