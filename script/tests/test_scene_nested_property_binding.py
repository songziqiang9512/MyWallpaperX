#!/usr/bin/env python3
"""Real parser -> binding Program -> LiveState for nested script inputs."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_update_state import SOURCE_ROOT, SWIFT_SOURCES

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "script/tests/fixtures/SceneNestedPropertyBindingChecks.swift"
SOURCES = [*SWIFT_SOURCES,
           SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
           SOURCE_ROOT / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
           SOURCE_ROOT / "Systems/Script/SceneScriptPropertyInput.swift", FIXTURE]


class SceneNestedPropertyBindingTests(unittest.TestCase):
    def test_nested_script_input_keeps_outer_key_live_and_rejects_neighbors(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        before = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in SOURCES}
        proof = os.environ.get("MWX_SCENE_PROPERTY_PROOF")
        with tempfile.TemporaryDirectory(prefix="mwx-nested-property-binding-") as temporary:
            binary = Path(temporary) / "nested-property-binding"
            command = ["swiftc", *(str(p) for p in SOURCES), "-o", str(binary)]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stderr)
            facts = json.loads(run.stdout)
        after = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in SOURCES}
        if proof:
            directory = Path(proof)
            directory.mkdir(parents=True, exist_ok=True)
            (directory / "inputs.json").write_text(json.dumps(
                {"command": command, "before": before, "after": after}, indent=2) + "\n")
            (directory / "facts.json").write_text(json.dumps(facts, indent=2) + "\n")
            (directory / "compiler.log").write_text(compiled.stdout + compiled.stderr)
        self.assertEqual(before, after, "source input changed while focused gate ran")
        self.assertTrue(facts)
        self.assertEqual([name for name, passed in facts.items() if passed is not True], [])


if __name__ == "__main__":
    unittest.main()
