#!/usr/bin/env python3
"""Executable boundary for historical combined RGB-alpha Pulse owners."""

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
HISTORICAL_RGB_ALPHA_RESULTS = r'''            "legacyMaskedStaticRGBAlpha":
                legacyContracts.map {
                    compileOutcome(
                        $0,
                        combos: rgbAlpha,
                        maskPath: "materials/pulse-mask.png"
                    )
                },
            "legacyBoundRGBAlpha": legacyContracts.map {
                compileOutcome(
                    $0,
                    bindings: [.phase: "pulsePhase"],
                    combos: rgbAlpha
                )
            },
            "legacyMaskedBoundRGBAlpha": legacyContracts.map {
                compileOutcome(
                    $0,
                    bindings: [.phase: "pulsePhase"],
                    combos: rgbAlpha,
                    maskPath: "materials/pulse-mask.png"
                )
            },
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ScenePulseHistoricalRGBAlphaOwnerBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.base_tests = BASE["ScenePulseDirectUserPropertyOwnerAdmissionTests"]
        cls.base_globals = cls.base_tests.setUpClass.__func__.__globals__
        cls.original_harness = cls.base_globals["HARNESS"]
        patched_harness = cls.original_harness.replace(
            RESULT_MARKER,
            HISTORICAL_RGB_ALPHA_RESULTS + RESULT_MARKER,
            1,
        )
        if patched_harness == cls.original_harness:
            raise RuntimeError("Pulse historical RGB-alpha marker is missing")
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

    def test_all_static_terminal_clamps_revoke_with_or_without_mask(
        self,
    ) -> None:
        revoked = "revoked:static-rgb-alpha-owner-revoked-to-material-program"
        expected = [revoked] * 3
        self.assertEqual(self.result["legacyStaticRGBAlpha"], expected)
        self.assertEqual(self.result["legacyMaskedStaticRGBAlpha"], expected)

    def test_live_saturate_and_cast3_revoke_while_literal_zero_stays_incumbent(
        self,
    ) -> None:
        revoked = (
            "revoked:typed-user-property-rgb-alpha-"
            "owner-revoked-to-material-program"
        )
        expected = [revoked, revoked, "incumbent"]
        self.assertEqual(self.result["legacyBoundRGBAlpha"], expected)
        self.assertEqual(self.result["legacyMaskedBoundRGBAlpha"], expected)


if __name__ == "__main__":
    unittest.main()
