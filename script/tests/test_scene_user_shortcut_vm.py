"""Real cursor Program -> Swift synchronous adapter -> QuickJS result scope."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import (
    C_SOURCES, ROOT, SWIFT_SOURCES, VM, compile_vector_harness,
)


class SceneUserShortcutVMTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        fixture = ROOT / "script/tests/fixtures/SceneUserShortcutVMHarness.swift"
        inputs = [*SWIFT_SOURCES, *C_SOURCES, *VM.glob("*.h"), fixture]
        cls.hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-shortcut-vm-")
        try:
            binary = compile_vector_harness(Path(cls.temporary.name), fixture.read_text(), "shortcut-vm")
            result = subprocess.run([str(binary)], cwd=ROOT, capture_output=True,
                                    text=True, timeout=30)
            if result.returncode:
                raise AssertionError(result.stdout + result.stderr)
            cls.report = json.loads(result.stdout)
            print(json.dumps({"shortcutVMSourceSHA256": cls.hashes, "result": cls.report}, sort_keys=True))
        except BaseException:
            cls.temporary.cleanup()
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        try:
            drift = [name for name, before in cls.hashes.items()
                     if hashlib.sha256(Path(name).read_bytes()).hexdigest() != before]
            if drift:
                raise AssertionError(f"VM fixture inputs changed: {drift}")
        finally:
            cls.temporary.cleanup()

    def test_real_native_boolean_and_unchanged_grant_with_renamed_keys(self) -> None:
        for name, expected in (("true", 1), ("false", 0), ("unicode", 1)):
            with self.subTest(name=name):
                actual = self.report[name]
                self.assertEqual(actual["failures"], 0)
                self.assertEqual(actual["origin"], [expected, 2, 3])
                self.assertEqual(actual["calls"], 1)
                self.assertTrue(actual["keyExact"])
                self.assertTrue(actual["grantExact"])

    def test_strict_arguments_missing_authority_and_native_rejection(self) -> None:
        called = {"hostReject", "unknownHostResult", "throwAfterDispatch"}
        for name, actual in self.report["rejected"].items():
            with self.subTest(name=name):
                self.assertEqual(actual["failures"], 1)
                self.assertEqual(actual["calls"], int(name in called))
                self.assertEqual(actual["mutations"], 0)
        for name, actual in self.report["unavailable"].items():
            with self.subTest(unavailable=name):
                self.assertEqual(actual["failures"], 0)
                self.assertEqual(actual["origin"], [0,0,0])
                self.assertEqual(actual["calls"], 0)
                self.assertEqual(actual["hoverFailures"], 0)
                self.assertEqual(actual["hoverOrigin"], [7,0,0])
                self.assertEqual(actual["hoverScale"], [1,1,1])
                self.assertTrue(actual["updateHealthy"])

    def test_only_synchronous_click_down_up_scope_and_original_pending_grant(self) -> None:
        scopes = self.report["scopes"]
        for name in ("cursorEnter", "cursorMove", "cursorLeave"):
            self.assertEqual(scopes[name], {"failures": 0, "calls": 0, "origin": [4,0,0]})
        for name in ("cursorDown", "cursorUp"):
            self.assertEqual(scopes[name], {"failures": 0, "calls": 1,
                                           "origin": [1,0,0], "grantExact": True})
        self.assertEqual(scopes["retainedAfterCursor"], {"calls": 1, "value": True})
        self.assertEqual(scopes["dueTimer"], {"calls": 1, "keys": ["cursor"],
                                              "origin": [1,1,0], "failures": 0})
        self.assertEqual(scopes["laterJob"], {"calls": 1, "keys": ["cursor"],
                                              "origin": [6,0,0], "failures": 0})
        replay = self.report["pendingReplay"]
        self.assertEqual(replay["firstFailures"], 0)
        self.assertEqual(replay["secondFailures"], 1)
        self.assertEqual(replay["dispatchCalls"], 2)
        self.assertTrue(replay["capturedGrantRetained"])
        self.assertEqual(replay["keys"], ["retained-key", "retained-key"])

    def test_shortcut_object_is_not_faked_as_scalar_and_ordinary_values_remain(self) -> None:
        projected = self.report["projection"]
        self.assertNotIn("action", projected)
        self.assertNotIn("renamedAction", projected)
        self.assertEqual(projected["level"], 0.25)
        self.assertIs(projected["enabled"], True)
        self.assertEqual(projected["tint"], {"x": 0.2, "y": 0.4, "z": 0.6})
        self.assertIsNone(self.report["changedShortcutProjection"])


if __name__ == "__main__":
    unittest.main()
