#!/usr/bin/env python3
"""Executable Pulse audio plus direct-tint alpha-owner partition."""

from __future__ import annotations

from pathlib import Path
import runpy


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = runpy.run_path(
    str(
        REPOSITORY_ROOT
        / "script/tests/test_scene_pulse_direct_user_property_owner_admission.py"
    )
)
_Base = FIXTURE["ScenePulseDirectUserPropertyOwnerAdmissionTests"]

RESULT_MARKER = "        let result: [String: Any] = [\n"
RESULT_INJECTION = r'''            "audioTintColor": (1 ... 3).map { channel in
                compileOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    combos: ["AUDIOPROCESSING": channel, "PULSECOLOR": 1]
                )
            },
            "audioTintRGBAlphaLow": (1 ... 3).map { channel in
                compileOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    combos: [
                        "AUDIOPROCESSING": channel,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                )
            },
            "audioTintRGBAlphaHigh": (1 ... 3).map { channel in
                compileOutcome(
                    contracts,
                    bindings: [.tintHigh: "pulseTintHigh"],
                    combos: [
                        "AUDIOPROCESSING": channel,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                )
            },
            "audioTintRGBAlphaDual": (1 ... 3).map { channel in
                compileOutcome(
                    contracts,
                    bindings: [
                        .tintLow: "pulseTintLow",
                        .tintHigh: "pulseTintHigh",
                    ],
                    combos: [
                        "AUDIOPROCESSING": channel,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                )
            },
            "audioTintRejected": [
                compileOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ],
                    maskPath: "materials/pulse-mask.png"
                ),
                compileOutcome(
                    contracts,
                    bindings: [.speed: "pulseSpeed"],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                ),
                compileOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 0,
                        "PULSEALPHA": 1,
                    ]
                ),
                compileOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    producers: [
                        producer(.tintLow, propertyKey: "pulseTintLow"),
                        producer(.tintLow, propertyKey: "competingTint"),
                    ],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                ),
                compileOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    fallbackOverrides: [.tintLow: [2, 0, 0]],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                ),
                compileOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    producers: [producer(
                        .tintLow,
                        propertyKey: "pulseTintLow",
                        valueType: .vector2
                    )],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                ),
                compileOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    producers: [],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                ),
            ],
            "legacyAudioTintRGBAlpha": legacyContracts.map {
                compileOutcome(
                    $0,
                    bindings: [.tintLow: "pulseTintLow"],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                )
            },
'''
base_harness = FIXTURE["HARNESS"]
if base_harness.count(RESULT_MARKER) != 1:
    raise RuntimeError("Pulse owner harness result marker drifted")
_Base.setUpClass.__func__.__globals__["HARNESS"] = base_harness.replace(
    RESULT_MARKER,
    RESULT_MARKER + RESULT_INJECTION,
    1,
)


class ScenePulseAudioDirectTintAlphaOwnerAdmissionTests(_Base):
    def test_audio_tint_alpha_binding_partition(self) -> None:
        alpha = (
            "revoked:audio-typed-user-property-rgb-alpha-"
            "owner-revoked-to-material-program"
        )
        self.assertEqual(self.result["audioTintColor"], ["incumbent"] * 3)
        for key in (
            "audioTintRGBAlphaLow",
            "audioTintRGBAlphaHigh",
            "audioTintRGBAlphaDual",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], [alpha] * 3)
        # The out-of-range authored fallback is rejected before owner selection;
        # every other near miss retains the incumbent dedicated plan.
        self.assertEqual(
            self.result["audioTintRejected"],
            ["incumbent"] * 4 + ["revoked:"] + ["incumbent"] * 2,
        )
        # Legacy profiles reject audio during planning; none can acquire the
        # new shared-owner revocation reason.
        self.assertEqual(self.result["legacyAudioTintRGBAlpha"], ["revoked:"] * 3)


del _Base


if __name__ == "__main__":
    import unittest

    unittest.main()
