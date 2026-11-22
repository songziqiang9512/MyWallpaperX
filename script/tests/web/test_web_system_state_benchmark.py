#!/usr/bin/env python3

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SCRIPT_DIR))

from web_system_state_benchmark import is_same_or_descendant, real_workshop_root, score_log


SAMPLE_ID = "1509243786"
DEFAULTS_SUITE = "com.songziqiang.MyWallpaperX.Debug.system-state-test"


def passing_fixture() -> str:
    return "\n".join(
        [
            f"MWX DEBUG DEFAULTS: suite={DEFAULTS_SUITE}",
            f"MWX WEB DIAG record={SAMPLE_ID} screen=1 severity=info type=host.ready url=- message=ready",
            "MWX AUDIO CAPTURE: started generation=1 sampleRate=48000 channels=2",
            "MWX AUDIO CAPTURE: data generation=1 peak=0.1000",
            "MWX DEBUG SYSTEM STATE: action=system-sleep",
            "MWX AUDIO CAPTURE: stopped",
            "MWX DEBUG SYSTEM STATE: action=display-sleep",
            "MWX DEBUG SYSTEM STATE: action=system-wake",
            "MWX DEBUG SYSTEM STATE: action=display-wake",
            "MWX AUDIO CAPTURE: started generation=2 sampleRate=48000 channels=2",
            "MWX AUDIO CAPTURE: data generation=2 peak=0.1000",
            "MWX DEBUG SYSTEM STATE: action=screen-lock",
            "MWX AUDIO CAPTURE: stopped",
            "MWX DEBUG SYSTEM STATE: action=screen-unlock",
            "MWX AUDIO CAPTURE: started generation=3 sampleRate=48000 channels=2",
            "MWX AUDIO CAPTURE: data generation=3 peak=0.1000",
            "MWX DEBUG SYSTEM STATE: action=stop",
            "MWX AUDIO CAPTURE: stopped",
            f"MWX WEB DIAG record={SAMPLE_ID} screen=1 severity=info type=lifecycle.surface.released url=- message=screen=1",
            f"MWX WEB DIAG record={SAMPLE_ID} screen=- severity=info type=lifecycle.stop url=- message=phase=idle surfaces=0 loopbacks=0 observers=0",
            "MWX DEBUG SYSTEM STATE: action=completed",
        ]
    )


class WebSystemStateBenchmarkTests(unittest.TestCase):
    def test_passing_timeline(self) -> None:
        result = score_log(passing_fixture(), SAMPLE_ID, DEFAULTS_SUITE)
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["debug_defaults_suite"], DEFAULTS_SUITE)

    def test_rejects_missing_defaults_isolation_confirmation(self) -> None:
        fixture = passing_fixture().replace(f"MWX DEBUG DEFAULTS: suite={DEFAULTS_SUITE}\n", "")
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertIsNone(result["debug_defaults_suite"])

    def test_rejects_restart_before_final_wake(self) -> None:
        fixture = passing_fixture().replace(
            "MWX DEBUG SYSTEM STATE: action=display-wake\nMWX AUDIO CAPTURE: started generation=2",
            "MWX AUDIO CAPTURE: started generation=2\nMWX DEBUG SYSTEM STATE: action=display-wake",
        )
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertFalse(result["capture_timeline_valid"])

    def test_rejects_missing_audio_data(self) -> None:
        fixture = passing_fixture().replace(
            "MWX AUDIO CAPTURE: data generation=3 peak=0.1000\n",
            "",
        )
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertEqual(result["audio_data_count"], 2)

    def test_rejects_retry_and_retained_surface(self) -> None:
        fixture = passing_fixture().replace(
            "lifecycle.surface.released",
            "lifecycle.surface.retained",
        )
        fixture += "\nMWX AUDIO CAPTURE: retry scheduled attempt=1 delay=1.0"
        result = score_log(fixture, SAMPLE_ID, DEFAULTS_SUITE)
        self.assertFalse(result["passed"])
        self.assertEqual(result["capture_retry_count"], 1)
        self.assertEqual(result["retained_surface_count"], 1)

    def test_identifies_real_workshop_descendants(self) -> None:
        root = real_workshop_root()
        self.assertTrue(is_same_or_descendant(root / "Web", root))
        self.assertFalse(is_same_or_descendant(root.parent / "isolated-workshop", root))


if __name__ == "__main__":
    unittest.main()
