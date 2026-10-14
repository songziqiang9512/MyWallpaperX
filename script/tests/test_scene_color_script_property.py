#!/usr/bin/env python3
"""Color input admission through the real parser, live state, and QuickJS owner."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from script.tests import scene_vector_vm_test_support as vm
from script.tests.test_scene_property_live_update_state import SOURCE_ROOT, SWIFT_SOURCES

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "script/tests/fixtures/SceneColorScriptPropertyChecks.swift"
EXTRA_SOURCES = (*SWIFT_SOURCES,
                 SOURCE_ROOT / "Systems/Properties/SceneUserPropertyDefinitionParser.swift")
INPUTS = list(dict.fromkeys([
    Path(__file__), FIXTURE, Path(vm.__file__), *vm.SWIFT_SOURCES, *EXTRA_SOURCES,
    *vm.C_SOURCES, *sorted(vm.VM.glob("*.h")), *sorted(vm.QUICKJS.glob("*.h")),
]))


class SceneColorScriptPropertyTests(unittest.TestCase):
    def test_color_admission_preserves_actual_vm_slot_types_and_atomic_rejection(self) -> None:
        if shutil.which("swiftc") is None or shutil.which("clang") is None:
            self.skipTest("Swift and Clang are required")
        before = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in INPUTS}
        commands = []
        real_run = subprocess.run

        def recorded_run(command, **kwargs):
            result = real_run(command, **kwargs)
            commands.append({"command": list(map(str, command)), "returncode": result.returncode,
                             "stdout": result.stdout, "stderr": result.stderr})
            return result

        with tempfile.TemporaryDirectory(prefix="mwx-color-script-property-") as temporary:
            with patch.object(vm.subprocess, "run", side_effect=recorded_run):
                binary = vm.compile_vector_harness(
                    Path(temporary), FIXTURE.read_text(), "color-script-property",
                    extra_swift_sources=EXTRA_SOURCES)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stderr)
            facts = json.loads(run.stdout)
        after = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in INPUTS}
        if proof := os.environ.get("MWX_SCENE_PROPERTY_PROOF"):
            directory = Path(proof)
            directory.mkdir(parents=True, exist_ok=True)
            (directory / "inputs.json").write_text(json.dumps(
                {"before": before, "after": after, "commands": commands}, indent=2) + "\n")
            (directory / "facts.json").write_text(json.dumps(facts, indent=2) + "\n")
            (directory / "runtime.log").write_text(run.stdout + run.stderr)
        self.assertEqual(before, after, "source input changed while focused gate ran")
        self.assertTrue(facts)
        self.assertEqual([name for name, passed in facts.items() if passed is not True], [])


if __name__ == "__main__":
    unittest.main()
