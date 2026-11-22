#!/usr/bin/env python3

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SCRIPT_DIR))

from web_space_lifecycle_benchmark import score_log


SAMPLE_ID = "1509243786"
DEFAULTS_SUITE = "com.songziqiang.MyWallpaperX.Debug.space-lifecycle-test"


def diag(event_type: str, message: str, record: str = SAMPLE_ID) -> str:
    return (
        f"MWX WEB DIAG record={record} screen=- severity=info "
        f"type={event_type} url=- message={message}"
    )


def action(name: str) -> str:
    return f"MWX DEBUG SPACE LIFECYCLE: action={name}"


def passing_lines() -> list[str]:
    return [
        f"MWX DEBUG DEFAULTS: suite={DEFAULTS_SUITE}",
        diag("host.ready", "ready"),
        action("default-space"),
        action("workspace-space"),
        diag("lifecycle.space.observed", "phase=ready"),
        diag("lifecycle.space.reasserted", "surfaces=1"),
        action("screen-burst"),
        diag("lifecycle.screen.observed", "phase=ready"),
        diag("lifecycle.screen.observed", "phase=ready"),
        diag("lifecycle.screen.observed", "phase=ready"),
        diag("lifecycle.screen.reconciled", "surfaces=1"),
        action("relaunch"),
        diag("host.ready", "ready"),
        action("workspace-space-after-relaunch"),
        diag("lifecycle.space.observed", "phase=ready"),
        diag("lifecycle.space.reasserted", "surfaces=1"),
        action("stop"),
        diag("lifecycle.surface.released", "screen=1"),
        diag("lifecycle.stop", "phase=idle surfaces=0 loopbacks=0 observers=0"),
        action("post-stop-notifications"),
        action("completed"),
    ]


def score(lines: list[str]) -> dict:
    return score_log("\n".join(lines), SAMPLE_ID, DEFAULTS_SUITE)


class WebSpaceLifecycleBenchmarkTests(unittest.TestCase):
    def test_passing_timeline(self) -> None:
        result = score(passing_lines())
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["debug_defaults_suite"], DEFAULTS_SUITE)
        self.assertEqual(result["host_ready_count"], 2)

    def test_rejects_missing_defaults_isolation_confirmation(self) -> None:
        lines = passing_lines()
        lines.pop(0)
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertIsNone(result["debug_defaults_suite"])

    def test_rejects_default_center_callback(self) -> None:
        lines = passing_lines()
        index = lines.index(action("workspace-space"))
        lines[index:index] = [
            diag("lifecycle.space.observed", "phase=ready"),
            diag("lifecycle.space.reasserted", "surfaces=1"),
        ]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(
            any("default NotificationCenter" in failure for failure in result["failures"])
        )

    def test_rejects_uncoalesced_screen_burst(self) -> None:
        lines = passing_lines()
        first = lines.index(diag("lifecycle.screen.reconciled", "surfaces=1"))
        lines.insert(first, diag("lifecycle.screen.reconciled", "surfaces=1"))
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertEqual(result["event_counts"]["lifecycle.screen.reconciled"], 2)

    def test_rejects_missing_screen_callback(self) -> None:
        lines = passing_lines()
        lines.remove(diag("lifecycle.screen.observed", "phase=ready"))
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertEqual(result["event_counts"]["lifecycle.screen.observed"], 2)

    def test_rejects_duplicate_observer_after_relaunch(self) -> None:
        lines = passing_lines()
        index = lines.index(action("stop"))
        lines[index:index] = [
            diag("lifecycle.space.observed", "phase=ready"),
            diag("lifecycle.space.reasserted", "surfaces=1"),
        ]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(
            any("observer reinstall" in failure for failure in result["failures"])
        )

    def test_rejects_callback_after_stop(self) -> None:
        lines = passing_lines()
        index = lines.index(action("completed"))
        lines[index:index] = [
            diag("lifecycle.space.observed", "phase=idle", record="-"),
            diag("lifecycle.screen.observed", "phase=idle", record="-"),
        ]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(
            any("after playback stopped" in failure for failure in result["failures"])
        )

    def test_rejects_nonzero_observer_stop(self) -> None:
        lines = [line.replace("observers=0", "observers=1") for line in passing_lines()]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertFalse(result["final_stop_zero"])

    def test_rejects_action_order_change(self) -> None:
        lines = passing_lines()
        first = lines.index(action("default-space"))
        second = lines.index(action("workspace-space"))
        lines[first], lines[second] = lines[second], lines[first]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertFalse(result["timeline_valid"])

    def test_ignores_lifecycle_events_before_first_ready(self) -> None:
        lines = passing_lines()
        index = lines.index(diag("host.ready", "ready"))
        lines[index:index] = [
            diag("lifecycle.space.observed", "phase=launching"),
            diag("lifecycle.screen.observed", "phase=launching"),
        ]
        result = score(lines)
        self.assertTrue(result["passed"], result["failures"])


if __name__ == "__main__":
    unittest.main()
