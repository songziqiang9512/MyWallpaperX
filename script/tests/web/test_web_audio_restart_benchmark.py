#!/usr/bin/env python3

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SCRIPT_DIR))

from web_audio_restart_benchmark import (
    is_same_or_descendant,
    real_workshop_root,
    score_log,
)


SAMPLE_ID = "1509243786"
DEFAULTS_SUITE = "com.songziqiang.MyWallpaperX.Debug.audio-restart-test"


def passing_fixture() -> str:
    return "\n".join(
        [
            f"MWX DEBUG DEFAULTS: suite={DEFAULTS_SUITE}",
            f"MWX WEB DIAG record={SAMPLE_ID} screen=1 severity=info type=host.ready url=- message=ready",
            "MWX AUDIO CAPTURE: listeners installed",
            "MWX AUDIO CAPTURE: started generation=1 sampleRate=48000 channels=2",
            "MWX AUDIO CAPTURE: data generation=1 peak=0.1000",
            "MWX DEBUG AUDIO RESTART: action=burst-1",
            "MWX AUDIO CAPTURE: invalidated reason=debug generation=1",
            "MWX DEBUG AUDIO RESTART: action=burst-2",
            "MWX AUDIO CAPTURE: invalidated reason=debug generation=1",
            "MWX DEBUG AUDIO RESTART: action=burst-3",
            "MWX AUDIO CAPTURE: invalidated reason=debug generation=1",
            "MWX AUDIO CAPTURE: restarting reason=debug generation=1",
            "MWX AUDIO CAPTURE: listeners removed",
            "MWX AUDIO CAPTURE: stopped",
            "MWX AUDIO CAPTURE: listeners installed",
            "MWX AUDIO CAPTURE: started generation=2 sampleRate=48000 channels=2",
            "MWX AUDIO CAPTURE: data generation=2 peak=0.1000",
            "MWX DEBUG AUDIO RESTART: action=single",
            "MWX AUDIO CAPTURE: invalidated reason=debug generation=2",
            "MWX AUDIO CAPTURE: restarting reason=debug generation=2",
            "MWX AUDIO CAPTURE: listeners removed",
            "MWX AUDIO CAPTURE: stopped",
            "MWX AUDIO CAPTURE: listeners installed",
            "MWX AUDIO CAPTURE: started generation=3 sampleRate=48000 channels=2",
            "MWX AUDIO CAPTURE: data generation=3 peak=0.1000",
            "MWX DEBUG AUDIO RESTART: action=stop",
            f"MWX WEB DIAG record={SAMPLE_ID} screen=- severity=info type=lifecycle.stop url=- message=phase=idle surfaces=0 loopbacks=0 observers=0",
            "MWX AUDIO CAPTURE: listeners removed",
            "MWX AUDIO CAPTURE: stopped",
            f"MWX WEB DIAG record={SAMPLE_ID} screen=1 severity=info type=lifecycle.surface.released url=- message=screen=1",
            "MWX DEBUG AUDIO RESTART: action=completed",
        ]
    )


class WebAudioRestartBenchmarkTests(unittest.TestCase):
    def test_passing_restart_timeline(self) -> None:
        result = score_log(passing_fixture(), SAMPLE_ID, DEFAULTS_SUITE)
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["audio_restart_count"], 2)
        self.assertEqual(result["debug_defaults_suite"], DEFAULTS_SUITE)

    def test_rejects_missing_defaults_isolation_confirmation(self) -> None:
        fixture = passing_fixture().replace(f"MWX DEBUG DEFAULTS: suite={DEFAULTS_SUITE}\n", "")
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertIsNone(result["debug_defaults_suite"])

    def test_measurement_ignores_events_before_host_ready(self) -> None:
        prefix = "\n".join(
            [
                "MWX DEBUG AUDIO RESTART: action=single",
                "MWX AUDIO CAPTURE: restarting reason=debug generation=0",
                "MWX AUDIO CAPTURE: listeners installed",
                "MWX AUDIO CAPTURE: started generation=0 sampleRate=48000 channels=2",
                "MWX AUDIO CAPTURE: data generation=0 peak=0.1000",
                "MWX AUDIO CAPTURE: listeners removed",
                "MWX AUDIO CAPTURE: stopped",
            ]
        )
        result = score_log(prefix + "\n" + passing_fixture(), SAMPLE_ID, DEFAULTS_SUITE)
        self.assertTrue(result["passed"], result["failures"])

    def test_rejects_uncoalesced_burst(self) -> None:
        fixture = passing_fixture().replace(
            "MWX DEBUG AUDIO RESTART: action=burst-3",
            "MWX AUDIO CAPTURE: restarting reason=debug generation=1\n"
            "MWX DEBUG AUDIO RESTART: action=burst-3",
        )
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertEqual(result["audio_restart_count"], 3)

    def test_rejects_restart_before_burst_finishes(self) -> None:
        fixture = passing_fixture().replace(
            "MWX DEBUG AUDIO RESTART: action=burst-3\n"
            "MWX AUDIO CAPTURE: invalidated reason=debug generation=1\n"
            "MWX AUDIO CAPTURE: restarting reason=debug generation=1",
            "MWX AUDIO CAPTURE: restarting reason=debug generation=1\n"
            "MWX DEBUG AUDIO RESTART: action=burst-3\n"
            "MWX AUDIO CAPTURE: invalidated reason=debug generation=1",
        )
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertFalse(result["capture_timeline_valid"])

    def test_rejects_missing_cycle_data(self) -> None:
        fixture = passing_fixture().replace(
            "MWX AUDIO CAPTURE: data generation=3 peak=0.1000\n",
            "",
        )
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertEqual(result["audio_data_count"], 2)

    def test_rejects_capture_health_errors(self) -> None:
        markers = [
            "MWX AUDIO CAPTURE: failed fixture",
            "MWX AUDIO CAPTURE: retry scheduled attempt=1 delay=1.0",
            "MWX AUDIO CAPTURE: listener removal failed target=tap status=-1",
        ]
        for marker in markers:
            with self.subTest(marker=marker):
                fixture = passing_fixture().replace(
                    "MWX DEBUG AUDIO RESTART: action=completed",
                    marker + "\nMWX DEBUG AUDIO RESTART: action=completed",
                )
                self.assertFalse(score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)["passed"])

    def test_rejects_health_error_before_host_ready(self) -> None:
        fixture = "MWX AUDIO CAPTURE: failed pre-ready\n" + passing_fixture()
        self.assertFalse(score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)["passed"])

    def test_rejects_nonzero_stop_and_retained_surface(self) -> None:
        fixture = passing_fixture().replace("surfaces=0", "surfaces=1").replace(
            "lifecycle.surface.released",
            "lifecycle.surface.retained",
        )
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertFalse(result["final_stop_zero"])
        self.assertEqual(result["retained_surface_count"], 1)

    def test_identifies_real_workshop_descendants(self) -> None:
        root = real_workshop_root()
        self.assertTrue(is_same_or_descendant(root / "Web", root))
        self.assertFalse(is_same_or_descendant(root.parent / "isolated-workshop", root))


if __name__ == "__main__":
    unittest.main()
