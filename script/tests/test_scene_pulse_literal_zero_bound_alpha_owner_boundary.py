#!/usr/bin/env python3
"""Executable boundary for historical literal-zero Pulse alpha bindings."""

from __future__ import annotations

from pathlib import Path
import runpy
import shutil
import unittest


BASE = runpy.run_path(
    str(Path(__file__).with_name(
        "test_scene_pulse_direct_user_property_owner_admission.py"
    ))
)
RESULT_MARKER = '''            "rgbAlphaProfile": SceneGenericShaderCapabilityProfile
'''
BOUND_ALPHA_RESULTS = r'''            "legacyBoundAlphaOnly": legacyContracts.map {
                compileOutcome(
                    $0,
                    bindings: [.phase: "pulsePhase"],
                    combos: alphaOnly
                )
            },
            "legacyMaskedBoundAlphaOnly": legacyContracts.map {
                compileOutcome(
                    $0,
                    bindings: [.phase: "pulsePhase"],
                    combos: alphaOnly,
                    maskPath: "materials/pulse-mask.png"
                )
            },
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ScenePulseLiteralZeroBoundAlphaOwnerBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.base_tests = BASE["ScenePulseDirectUserPropertyOwnerAdmissionTests"]
        cls.base_globals = cls.base_tests.setUpClass.__func__.__globals__
        cls.original_harness = cls.base_globals["HARNESS"]
        patched_harness = cls.original_harness.replace(
            RESULT_MARKER,
            BOUND_ALPHA_RESULTS + RESULT_MARKER,
            1,
        )
        if patched_harness == cls.original_harness:
            raise RuntimeError("Pulse owner result insertion marker is missing")
        cls.base_globals["HARNESS"] = patched_harness
        try:
            cls.base_tests.setUpClass()
        except Exception:
            cls.base_globals["HARNESS"] = cls.original_harness
            raise
        cls.result = cls.base_tests.result

    @classmethod
    def tearDownClass(cls) -> None:
        try:
            cls.base_tests.tearDownClass()
        finally:
            cls.base_globals["HARNESS"] = cls.original_harness

    def test_literal_zero_dynamic_alpha_uses_the_shared_program(self) -> None:
        revoked = (
            "revoked:typed-user-property-alpha-only-"
            "owner-revoked-to-material-program"
        )
        expected = [revoked] * 3
        self.assertEqual(self.result["legacyBoundAlphaOnly"], expected)
        self.assertEqual(self.result["legacyMaskedBoundAlphaOnly"], expected)


if __name__ == "__main__":
    unittest.main()
