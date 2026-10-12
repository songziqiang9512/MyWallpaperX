#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
DEBUG_RUNNER_SOURCE = (
    SCRIPT_DIR.parent / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift"
)
DEBUG_ARGUMENTS_RUNNER_SOURCE = (
    SCRIPT_DIR.parent
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Arguments.swift"
)

import scene_wallpaper_benchmark as benchmark
import scene_preview_visual_evidence as visual
import generate_scene_full_matrix as matrix_generator
from script.tests.scene_wallpaper_graph_output_test_support import (
    assert_named_graph_output_publication_has_one_terminal_owner,
    assert_named_provider_terminal,
    assert_visible_provider_requires_compositor_consumption,
    assert_visible_publication_execution_metrics,
    assert_utility_capture_respects_dormant_graph_members,
)


class SceneDebugEvidenceScheduleTests(unittest.TestCase):
    """Execute production DEBUG extensions against a suspended host and capture sink."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-debug-evidence-schedule-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = SCRIPT_DIR.parent
        temporary = Path(cls.temporary.name)
        cls.binary = temporary / "schedule-harness"
        sources = [
            DEBUG_RUNNER_SOURCE.parent / f"DebugScenePlaybackRunner+{part}.swift"
            for part in ("EvidenceSchedule", "PointerDrag", "Arguments")
        ]
        sources.extend([
            root / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
            SCRIPT_DIR / "tests/fixtures/SceneDebugPointerScheduleHarness.swift",
        ])
        result = subprocess.run(
            ["swiftc", "-D", "DEBUG", "-parse-as-library", *map(str, sources),
             "-module-cache-path", str(temporary / "module-cache"), "-o", str(cls.binary)],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode:
            raise AssertionError(f"actual DEBUG extensions failed to compile:\n{result.stderr}")

    def run_schedule(self, scenario: str = "success", *, pointer: bool = True,
                     extra: tuple[str, ...] = ()) -> dict:
        args = [str(self.binary), scenario]
        if pointer:
            args.extend(["--mwx-debug-scene-hover-pointer-json", '{"x":0.25,"y":-0.5}'])
        args.extend(extra)
        environment = dict(os.environ)
        environment.pop("MYWALLPAPERX_SCENE_DEBUG_POINTER_SECOND", None)
        result = subprocess.run(args, capture_output=True, text=True, check=True,
                                timeout=15, env=environment)
        return json.loads(result.stdout)

    def assert_pointer_sequence(self, payload: dict, *, stationary: bool = False,
                                click: bool = False, drag: bool = False,
                                from_launch: bool = False) -> None:
        events = payload["events"]
        names = [row["event"] for row in events
                 if row["event"] != "turn-after-press"
                 and not row["event"].startswith("capture:series-")]
        expected = ["pointer:up" if from_launch else "pointer:outside", "launch",
                    "launch-complete", "ready", "pointer:outside", "capture:before",
                    "pointer:up"]
        if not stationary:
            expected.append("pointer:up")
        if drag:
            expected.extend(["pointer:down", "pointer:down", "capture:drag-held", "pointer:up"])
        elif click:
            expected.extend(["pointer:down", "pointer:up"])
        expected.extend(["capture:hover", "pointer:outside", "capture:after"])
        self.assertEqual(names, expected)
        self.assertEqual(payload["model"], 91)
        launch = next(row for row in events if row["event"] == "launch")
        self.assertEqual(launch["inside"], from_launch)
        self.assertEqual(launch["record"], "fixture-record")
        before = next(row for row in events if row["event"] == "capture:before")
        after = next(row for row in events if row["event"] == "capture:after")
        hover = next(row for row in events if row["event"] == "capture:hover")
        self.assertFalse(before["inside"])
        self.assertFalse(after["inside"])
        self.assertTrue(hover["inside"])
        self.assertEqual(hover["point"], [0.75, 0.25] if drag else [0.25, -0.5])
        self.assertTrue(all(row["kind"] == "required" for row in events
                            if row["event"].startswith("capture:")
                            and not row["event"].startswith("capture:series-")))

    def test_awaited_launch_precedes_hover_and_periodic_captures(self) -> None:
        payload = self.run_schedule(extra=("--mwx-debug-scene-periodic-snapshot-interval", "0.08"))
        self.assert_pointer_sequence(payload)
        self.assertEqual([row["event"] for row in payload["suspendedEvents"]],
                         ["pointer:outside", "launch"])
        periodic = [row for row in payload["events"] if row.get("kind") == "periodic"]
        self.assertGreaterEqual(len(periodic), 2)
        self.assertEqual([row["event"] for row in periodic],
                         [f"capture:series-{index:04d}" for index in range(len(periodic))])

    def test_stationary_from_launch_preserves_the_declared_first_point(self) -> None:
        payload = self.run_schedule(extra=("--mwx-debug-scene-hover-pointer-stationary-entry",
                                           "--mwx-debug-scene-hover-pointer-from-launch"))
        self.assert_pointer_sequence(payload, stationary=True, from_launch=True)
        self.assertEqual(payload["suspendedEvents"][1]["point"], [0.25, -0.5])

    def test_drag_captures_held_destination_before_release_and_exit(self) -> None:
        self.assert_pointer_sequence(self.run_schedule(extra=(
            "--mwx-debug-scene-cursor-drag-to-json", '{"x":0.75,"y":0.25}'
        )), drag=True)

    def test_click_release_is_delayed_but_subframe_release_precedes_next_turn(self) -> None:
        for subframe in (False, True):
            with self.subTest(subframe=subframe):
                flags = ("--mwx-debug-scene-primary-click",)
                if subframe:
                    flags += ("--mwx-debug-scene-primary-click-subframe",)
                payload = self.run_schedule(extra=flags)
                self.assert_pointer_sequence(payload, click=True)
                names = [row["event"] for row in payload["events"]]
                press = names.index("pointer:down")
                release = names.index("pointer:up", press)
                turn = names.index("turn-after-press")
                self.assertEqual(release < turn, subframe)

    def test_launch_failure_cancellation_and_closing_never_schedule_captures(self) -> None:
        for scenario in ("launch-failure", "launch-cancelled", "close-during-launch", "already-closing"):
            with self.subTest(scenario=scenario):
                payload = self.run_schedule(scenario)
                names = [row["event"] for row in payload["events"]]
                self.assertFalse(any(name.startswith("capture:") for name in names))
                self.assertNotIn("ready", names)
                if scenario.startswith("launch-"):
                    self.assertEqual(payload["error"], "cancelled" if scenario.endswith("cancelled") else "failed")
                else:
                    self.assertIsNone(payload["model"])
                if scenario == "already-closing":
                    self.assertNotIn("launch", names)

    def test_regular_and_periodic_callbacks_obey_closing(self) -> None:
        flags = ("--mwx-debug-scene-after-snapshot-delay", "1.1",
                 "--mwx-debug-scene-periodic-snapshot-interval", "0.08")
        positive = self.run_schedule(pointer=False, extra=flags)
        names = [row["event"] for row in positive["events"]]
        self.assertEqual(names[:5], ["launch", "launch-complete", "ready", "capture:ready", "capture:after"])
        self.assertIn("capture:series-0001", names)
        closed = self.run_schedule("close-before-capture", pointer=False, extra=flags)
        self.assertEqual([row["event"] for row in closed["events"]], ["launch", "launch-complete", "ready"])

    def test_fault_injected_early_schedule_is_rejected_by_the_same_event_oracle(self) -> None:
        payload = self.run_schedule("fault-early-capture")
        self.assertIn("capture:before", [row["event"] for row in payload["suspendedEvents"]])
        with self.assertRaises(AssertionError):
            self.assert_pointer_sequence(payload)

    def test_arguments_reject_invalid_pointer_and_periodic_interval(self) -> None:
        invalid = self.run_schedule("arguments", pointer=False, extra=(
            "--mwx-debug-scene-hover-pointer-json", '{"x":2,"y":0}',
            "--mwx-debug-scene-periodic-snapshot-interval", "0.079",
            "--mwx-debug-scene-after-snapshot-delay", "nan",
        ))
        self.assertIsNone(invalid["hover"])
        self.assertIsNone(invalid["periodicInterval"])
        self.assertEqual(invalid["afterDelay"], 3)
        bounded = self.run_schedule("arguments", extra=(
            "--mwx-debug-scene-duration", "7", "--mwx-debug-scene-after-snapshot-delay", "100",
            "--mwx-debug-scene-periodic-snapshot-interval", "100",
        ))
        self.assertEqual(bounded["hover"], [0.25, -0.5])
        self.assertEqual(bounded["afterDelay"], 6.5)
        self.assertEqual(bounded["periodicInterval"], 10)


if __name__ == "__main__":
    unittest.main()
