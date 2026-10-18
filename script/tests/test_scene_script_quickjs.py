#!/usr/bin/env python3

"""Contract gate for the QuickJS-NG SceneScript typed owners."""

from __future__ import annotations

import json
import os
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
    FIXTURES / "SceneScriptQuickJSLegacyCaptureCases.c",
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
            *(["-fsanitize=address", "-fno-omit-frame-pointer"]
              if os.environ.get("MWX_SCENE_QUICKJS_ASAN") == "1" else []),
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
        if completed.stdout:
            print(completed.stdout, end="")
        prefix = "MWX_FONT_PATH_CONTRACT "
        font_results = [
            json.loads(line[len(prefix):])
            for line in completed.stdout.splitlines()
            if line.startswith(prefix)
        ]
        self.assertEqual(len(font_results), 1, completed.stdout + completed.stderr)
        self.assertEqual(
            font_results[0],
            {
                "positive": 1,
                "renamed": 1,
                "sameValueNoMutation": 1,
                "invalidInputs": 1,
                "unicodeBytes": 1024,
                "rollback": 1,
            },
            completed.stdout + completed.stderr,
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )
        pressure_prefix = "MWX_TIMER_ALLOCATION_PRESSURE "
        pressure = [json.loads(line[len(pressure_prefix):])
                    for line in completed.stdout.splitlines()
                    if line.startswith(pressure_prefix)]
        self.assertEqual(len(pressure), 1, completed.stdout + completed.stderr)
        for key in ("anchorFailures", "postAnchorFailures", "successes", "existingTimerPreserved"):
            self.assertGreater(pressure[0][key], 0, pressure)

    def test_legacy_capture_allocation_and_gc(self) -> None:
        root = Path(self._temporary_directory.name)
        main = root / "legacy-main.c"
        main.write_text(
            "int mwx_test_legacy_capture_cases(void);\n"
            "int main(void) { return mwx_test_legacy_capture_cases() != 0; }\n",
            encoding="utf-8",
        )
        binary = root / "legacy-gc-harness"
        compilation = subprocess.run(
            [
                shutil.which("clang"), "-std=c11", "-O1",
                "-DFORCE_GC_AT_MALLOC", "-I", str(VM), "-I", str(QUICKJS),
                *map(str, C_SOURCES),
                str(FIXTURES / "SceneScriptQuickJSLegacyCaptureCases.c"),
                str(main), "-lm", "-o", str(binary),
            ],
            cwd=ROOT, capture_output=True, text=True,
        )
        self.assertEqual(
            compilation.returncode, 0, compilation.stdout + compilation.stderr
        )
        completed = subprocess.run(
            [str(binary)], cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(
            completed.returncode, 0, completed.stdout + completed.stderr
        )
        if completed.stdout:
            print(completed.stdout, end="")


if __name__ == "__main__":
    unittest.main()
