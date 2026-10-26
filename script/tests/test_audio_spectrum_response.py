from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class AudioSpectrumResponseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        compiler = shutil.which("swiftc")
        if not compiler:
            raise unittest.SkipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-audio-response-") as directory:
            binary = Path(directory) / "response"
            subprocess.run([
                compiler, "-O", "-module-cache-path", str(Path(directory) / "modules"),
                str(ROOT / "MyWallpaperX/Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift"),
                str(ROOT / "MyWallpaperX/Core/Playback/SystemAudioCaptureBuffer.swift"),
                str(ROOT / "script/tests/fixtures/SystemAudioSpectrumTestCapture.swift"),
                str(ROOT / "MyWallpaperX/Core/Playback/SystemAudioCaptureDeviceFactory.swift"),
                str(ROOT / "script/tests/fixtures/SystemAudioSpectrumResponseHarness.swift"),
                "-o", str(binary),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            cls.result = json.loads(result.stdout)

    def test_tone_and_listening_levels_keep_fixed_decibel_response(self) -> None:
        self.assertTrue(0.7 < self.result["toneHeight"] < 0.9)
        levels = self.result["volumeSteps"]
        self.assertTrue(all(0 < a < b < 0.96 for a, b in zip(levels, levels[1:])))
        self.assertGreater(levels[2] - levels[0], 0.45)

    def test_weak_bands_receive_visible_dynamic_range_without_peak_competition(self) -> None:
        levels = self.result["displayRange"]
        self.assertGreater(levels[3], 0.3)  # -60dB amplitude remains visible
        self.assertGreater(levels[4], 0.6)  # -40dB amplitude
        self.assertTrue(all(a < b for a, b in zip(levels[1:6], levels[2:7])))
        self.assertTrue(all(0 <= value <= 0.96 for value in levels))
        self.assertEqual(levels[0], 0)
        self.assertEqual(levels[-1], 0)  # non-positive amplitude remains silent
        self.assertTrue(self.result["rawNonFiniteFinite"])
        self.assertTrue(self.result["extremePCMFinite"])
        self.assertLess(self.result["independentBassDelta"], 0.002)
        self.assertLess(self.result["independentTrebleDelta"], 0.002)
        self.assertGreater(self.result["lowResponseDelta"], 0.2)

    def test_projection_keeps_scale_and_canonical_height_semantics(self) -> None:
        self.assertTrue(self.result["coarseMatchesCanonical"])
        self.assertLess(self.result["projectionMeanError"], 1e-6)
        for value in self.result["projectionConstant"]:
            self.assertAlmostEqual(value, 0.6, places=6)

    def test_final_height_envelope_uses_time_not_callback_count(self) -> None:
        for a, b in zip(self.result["envelope30"], self.result["envelope60"]):
            self.assertAlmostEqual(a, b, delta=1e-5)
        # 140ms final-height release has the same decay at different levels.
        fractions = self.result["releaseFractions"]
        self.assertAlmostEqual(fractions[0], fractions[2], delta=1e-5)
        self.assertAlmostEqual(fractions[1], fractions[3], delta=1e-5)
        self.assertTrue(0.20 < fractions[0] < 0.28)
        self.assertTrue(0.04 < fractions[1] < 0.08)
        self.assertTrue(self.result["silenceClears"])

    def test_stale_time_and_format_cannot_replace_current_state(self) -> None:
        self.assertTrue(self.result["staleUnchanged"])
        self.assertTrue(self.result["staleStateUnchanged"])

    def test_fractional_format_boundary_rebuilds_window(self) -> None:
        self.assertEqual(self.result["fractionalWindowCounts"], [4096, 4097])
        self.assertTrue(self.result["fractionalRateResetMatchesFresh"])
        self.assertTrue(self.result["finiteRates"])

    def test_capture_quantum_supports_analysis_cadence(self) -> None:
        self.assertEqual(self.result["captureFrames"], [512, 512, 1024, 2048, 1024, 256])

    def test_reused_fft_storage_preserves_padding_channels_and_published_values(self) -> None:
        self.assertEqual(self.result["scratchReuse"], {
            "matchesFresh": True, "rightStaysSilent": True, "publishedStaysImmutable": True,
        })

    def test_tones_retain_frequency_identity(self) -> None:
        for actual, expected in zip(self.result["observedPeakIndices"], [2, 10, 21, 32, 46, 58]):
            self.assertLessEqual(abs(actual - expected), 2)
