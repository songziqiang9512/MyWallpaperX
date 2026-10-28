#!/usr/bin/env python3

"""Public QuickJS layer-reference, receiver, permission and lifecycle checks."""

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


class SceneQuickJSLayerReferenceIdentityTest(unittest.TestCase):
    def test_native_references_keep_referent_and_executing_permissions(self) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the QuickJS reference gate")
        fixture = ROOT / "script/tests/fixtures/SceneLayerReferenceQuickJSCases.c"
        with tempfile.TemporaryDirectory(prefix="mwx-layer-reference-") as temporary:
            binary = Path(temporary) / "layer-reference"
            handles = VM / "SceneQuickJSLayerHandleHost.c"
            handles_object = Path(temporary) / "layer-handles.o"
            staged = subprocess.run(
                [clang, "-std=c11", "-O0", "-I", str(VM), "-I", str(QUICKJS),
                 "-Dcalloc=layer_reference_calloc", "-c", str(handles), "-o", str(handles_object)],
                cwd=ROOT, capture_output=True, text=True,
            )
            self.assertEqual(staged.returncode, 0, staged.stdout + staged.stderr)
            compilation = subprocess.run(
                [clang, "-std=c11", "-O0", "-I", str(VM), "-I", str(QUICKJS),
                 *map(str, (path for path in C_SOURCES if path != handles)),
                 str(handles_object), str(fixture), "-lm", "-o", str(binary)],
                cwd=ROOT, capture_output=True, text=True,
            )
            self.assertEqual(compilation.returncode, 0,
                             compilation.stdout + compilation.stderr)
            execution = subprocess.run([str(binary)], cwd=ROOT,
                                       capture_output=True, text=True)
            self.assertEqual(execution.returncode, 0,
                             execution.stdout + execution.stderr)
            if execution.stdout:
                print(execution.stdout, end="")


if __name__ == "__main__":
    unittest.main()
