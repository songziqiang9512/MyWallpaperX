#!/usr/bin/env python3

"""Contract gate for the QuickJS-NG SceneScript typed owners."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    from .scene_vector_vm_test_support import C_SOURCES, QUICKJS, ROOT, VM
except ImportError:
    from scene_vector_vm_test_support import C_SOURCES, QUICKJS, ROOT, VM


FIXTURES = ROOT / "script/tests/fixtures"
FIXTURE_SOURCES = [
    FIXTURES / "SceneLayerPerspectiveQuickJSCases.c",
    FIXTURES / "SceneScriptQuickJSMain.c",
    FIXTURES / "SceneScriptQuickJSRuntimeSupport.c",
    FIXTURES / "SceneScriptQuickJSLayerSupport.c",
    FIXTURES / "SceneScriptQuickJSRuntimeCases.c",
    FIXTURES / "SceneScriptQuickJSValueCases.c",
    FIXTURES / "SceneScriptQuickJSLayerReadCases.c",
    FIXTURES / "SceneScriptQuickJSAnimationCases.c",
    FIXTURES / "SceneScriptQuickJSEventCases.c",
    FIXTURES / "SceneScriptQuickJSJobTimerCases.c",
    FIXTURES / "SceneScriptQuickJSLayerMutationCases.c",
    FIXTURES / "SceneScriptQuickJSLayerTopologyCases.c",
    FIXTURES / "SceneScriptQuickJSStorageCases.c",
]


class SceneScriptQuickJSTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the QuickJS contract gate")
        cls._temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-quickjs-"
        )
        root = Path(cls._temporary_directory.name)
        binary = root / "harness"
        command = [
            clang,
            "-std=c11",
            "-O0",
            "-I",
            str(VM),
            "-I",
            str(QUICKJS),
            *map(str, C_SOURCES),
            *map(str, FIXTURE_SOURCES),
            "-lm",
            "-o",
            str(binary),
        ]
        compilation = subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True
        )
        if compilation.returncode != 0:
            cls._temporary_directory.cleanup()
            raise AssertionError(
                "QuickJS contract harness did not compile:\n"
                + compilation.stdout
                + compilation.stderr
            )
        cls._binary = binary

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def test_real_ecmascript_owner_contract(self) -> None:
        completed = subprocess.run(
            [str(self._binary)], cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )
        if completed.stdout:
            print(completed.stdout, end="")


if __name__ == "__main__":
    unittest.main()
