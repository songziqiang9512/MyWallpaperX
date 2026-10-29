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
        payload = json.loads(result.stdout)
        payload["modeLogs"] = [line for line in result.stderr.splitlines()
                               if "phase=evidence-mode" in line]
        return payload

    def assert_pointer_sequence(self, payload: dict, *, stationary: bool = False,
                                click: bool = False, drag: bool = False,
                                from_launch: bool = False) -> None:
        events = payload["events"]
        names = [row["event"] for row in events
                 if not row["event"].startswith("turn-after-")
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

    def assert_after_deadline(self, payload: dict, *, pointer: bool = True) -> None:
        events = payload["events"]
        after = [row for row in events if row["event"] == "capture:after"]
        self.assertEqual(len(after), 1, events)
        # Real DispatchQueue timings may run late; a small timer tolerance
        # cannot hide the former ~2s pointer capture against delay4/5.
        deadline = payload["scheduleTime"] + payload["afterDelay"]
        self.assertGreaterEqual(after[0]["time"], deadline - 0.01, payload)
        if pointer:
            hover_index = next(i for i, row in enumerate(events)
                               if row["event"] == "capture:hover")
            exit_event = next(row for row in events[hover_index + 1:]
                              if row["event"] == "pointer:outside")
            self.assertGreaterEqual(after[0]["time"] - exit_event["time"], 0.195, payload)

    def test_hover_after_respects_requested_observation_deadline(self) -> None:
        payload = self.run_schedule(extra=("--mwx-debug-scene-after-snapshot-delay", "4"))
        self.assert_pointer_sequence(payload)
        self.assert_after_deadline(payload)

    def test_trajectory_after_respects_requested_observation_deadline(self) -> None:
        payload = self.run_schedule(extra=(
            "--mwx-debug-scene-after-snapshot-delay", "5",
            "--mwx-debug-scene-pointer-trajectory-json", "[[0.25,-0.5],[-0.6,0.5]]",
        ))
        events = payload["events"]
        self.assertEqual([row["event"] for row in events if row["event"].startswith("capture:")],
                         ["capture:before", "capture:pointer-trajectory-00",
                          "capture:pointer-trajectory-01", "capture:hover", "capture:after"])
        hover = next(row for row in events if row["event"] == "capture:hover")
        self.assertTrue(hover["inside"])
        for actual, expected in zip(hover["point"], [-0.6, 0.5]):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assert_after_deadline(payload)

    def test_closing_after_hover_prevents_capture_at_later_deadline(self) -> None:
        payload = self.run_schedule("close-after-hover", extra=(
            "--mwx-debug-scene-after-snapshot-delay", "4",
        ))
        names = [row["event"] for row in payload["events"]]
        self.assertIn("capture:hover", names)
        self.assertEqual(names[-1], "closed")
        self.assertNotIn("capture:after", names)
        self.assertLess(payload["events"][-1]["time"], payload["scheduleTime"] + 4)

    def test_late_interactions_preserve_exit_settle_after_deadline_passes(self) -> None:
        for flags in [
            ("--mwx-debug-scene-pointer-trajectory-json", "[[0.25,-0.5],[-0.6,0.5]]"),
            ("--mwx-debug-scene-cursor-drag-to-json", '{"x":0.75,"y":0.25}'),
        ]:
            with self.subTest(interaction=flags[0]):
                payload = self.run_schedule(extra=(
                    "--mwx-debug-scene-after-snapshot-delay", "1.1", *flags,
                ))
                self.assert_after_deadline(payload)
                hover = next(row for row in payload["events"] if row["event"] == "capture:hover")
                self.assertGreater(hover["time"], payload["scheduleTime"] + 1.1)

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
                                           "--mwx-debug-scene-hover-pointer-from-launch",
                                           "--mwx-debug-scene-after-snapshot-delay", "4"))
        self.assert_pointer_sequence(payload, stationary=True, from_launch=True)
        self.assertEqual(payload["suspendedEvents"][1]["point"], [0.25, -0.5])
        self.assert_after_deadline(payload)

    def test_drag_captures_held_destination_before_release_and_exit(self) -> None:
        payload = self.run_schedule(extra=(
            "--mwx-debug-scene-cursor-drag-to-json", '{"x":0.75,"y":0.25}',
            "--mwx-debug-scene-after-snapshot-delay", "4",
        ))
        self.assert_pointer_sequence(payload, drag=True)
        self.assert_after_deadline(payload)

    def test_default_drag_preserves_single_round_delays_and_snapshot_reasons(self) -> None:
        payload = self.run_schedule("legacy-drag-full", extra=(
            "--mwx-debug-scene-cursor-drag-to-json", '{"x":0.75,"y":0.25}',
        ))
        events = payload["events"]
        self.assertEqual([row["event"] for row in events if row["event"].startswith("capture:")],
                         ["capture:before", "capture:drag-held", "capture:hover", "capture:after",
                          "capture:spring-after"])
        down = [row for row in events if row["event"] == "pointer:down"]
        release = next(row for row in events if row["event"] == "pointer:up" and row["time"] > down[1]["time"])
        self.assertEqual(len(down), 2)
        for elapsed in [down[1]["time"] - down[0]["time"], release["time"] - down[1]["time"]]:
            self.assertGreaterEqual(elapsed, 0.25)
            self.assertLess(elapsed, 0.75)
        spring = next(row for row in events if row["event"] == "capture:spring-after")
        self.assertGreaterEqual(spring["time"] - release["time"], 5.95)
        self.assertIsNone(payload["dragTiming"])
        self.assert_after_deadline(payload)

    def test_three_explicit_drags_hold_across_runloop_turns_and_use_unique_captures(self) -> None:
        timing = {"count": 3, "pressSeconds": 0.32, "heldSeconds": 0.4, "betweenSeconds": 0.32}
        payload = self.run_schedule(extra=("--mwx-debug-scene-cursor-drag-to-json", '{"x":0.75,"y":0.25}',
            "--mwx-debug-scene-cursor-drag-timing-json", json.dumps(timing)))
        events = payload["events"]
        captures = [row["event"] for row in events if row["event"].startswith("capture:")]
        self.assertEqual(captures, ["capture:before"] + [f"capture:drag-{i:02d}-{phase}"
            for i in range(1, 4) for phase in ("held", "released")])
        self.assertEqual(len(captures), len(set(captures)))
        down = [row for row in events if row["event"] == "pointer:down"]
        self.assertEqual(len(down), 6)
        previous_release = None
        for i in range(3):
            press, move = down[i * 2:i * 2 + 2]
            release = next(row for row in events if row["event"] == "pointer:up" and row["time"] > move["time"])
            held = next(row for row in events if row["event"] == f"capture:drag-{i + 1:02d}-held")
            released = next(row for row in events if row["event"] == f"capture:drag-{i + 1:02d}-released")
            self.assertEqual(press["point"], [0.25, -0.5])
            self.assertEqual(move["point"], [0.75, 0.25])
            self.assertGreaterEqual(move["time"] - press["time"], timing["pressSeconds"] - 0.02)
            self.assertGreaterEqual(release["time"] - move["time"], timing["heldSeconds"] - 0.02)
            self.assertLess(move["time"], held["time"])
            self.assertLess(held["time"], release["time"])
            self.assertGreaterEqual(released["time"] - release["time"], 0.26)
            for marker, start, end in [("turn-after-press", press, move), ("turn-after-drag", move, release)]:
                self.assertTrue(any(row["event"] == marker and start["time"] <= row["time"] < end["time"] for row in events))
            if previous_release is not None:
                self.assertGreaterEqual(press["time"] - previous_release["time"], timing["betweenSeconds"] + 0.26)
            previous_release = release
        self.assertEqual(events[-1]["event"], "pointer:outside")
        self.assertIsNone(payload["dragTimingFailure"])

    def test_explicit_drag_callbacks_stop_when_closing_mid_hold(self) -> None:
        payload = self.run_schedule("close-during-drag", extra=(
            "--mwx-debug-scene-cursor-drag-to-json", '{"x":0.75,"y":0.25}',
            "--mwx-debug-scene-cursor-drag-timing-json",
            '{"count":3,"pressSeconds":0.4,"heldSeconds":0.4,"betweenSeconds":0.3}',
        ))
        self.assertEqual(payload["events"][-1]["event"], "closed")
        self.assertEqual(sum(row["event"] == "pointer:down" for row in payload["events"]), 2)

    def test_explicit_drag_timing_rejects_invalid_numbers_shapes_and_combinations(self) -> None:
        timing = {"count": 3, "pressSeconds": 1, "heldSeconds": 2, "betweenSeconds": 6}
        base = ("--mwx-debug-scene-duration", "30", "--mwx-debug-scene-cursor-drag-to-json", '{"x":0.75,"y":0.25}')
        flag = "--mwx-debug-scene-cursor-drag-timing-json"
        valid = self.run_schedule("arguments", extra=base + (flag, json.dumps(timing)))
        self.assertIsNone(valid["dragTimingFailure"])
        self.assertEqual(valid["dragTiming"], timing)
        invalids = [[], {**timing, "unknown": 1}, {k: v for k, v in timing.items() if k != "heldSeconds"}]
        for key in timing:
            invalids.extend([{**timing, key: value} for value in [True, "1", None, float("inf")]])
        invalids.extend({**timing, key: value} for key, values in [
            ("count", [0, 9, 1.5]), ("pressSeconds", [0.279, 5.01]),
            ("heldSeconds", [0.279, 5.01]), ("betweenSeconds", [0.279, 10.01]),
        ] for value in values)
        for value in invalids:
            with self.subTest(value=value):
                result = self.run_schedule("arguments", extra=base + (flag, json.dumps(value)))
                self.assertEqual(result["dragTimingFailure"], "invalid-pointer-drag-timing")
        for conflict in [("--mwx-debug-scene-primary-click",), ("--mwx-debug-scene-primary-double-click",),
                         ("--mwx-debug-scene-primary-click-subframe",),
                         ("--mwx-debug-scene-pointer-trajectory-json", "[[0,0],[1,1]]")]:
            result = self.run_schedule("arguments", extra=base + (flag, json.dumps(timing)) + conflict)
            self.assertEqual(result["dragTimingFailure"], "ambiguous-pointer-drag-timing")
        for hover, drag in [(False, '{"x":0,"y":0}'), (True, '{"x":true,"y":0}'),
                            (True, '{"x":2,"y":0}'), (True, "broken")]:
            result = self.run_schedule("arguments", pointer=hover, extra=(
                "--mwx-debug-scene-duration", "30", "--mwx-debug-scene-cursor-drag-to-json", drag,
                flag, json.dumps(timing)))
            self.assertEqual(result["dragTimingFailure"], "ambiguous-pointer-drag-timing")
        missing_drag = self.run_schedule("arguments", extra=("--mwx-debug-scene-duration", "30", flag, json.dumps(timing)))
        self.assertEqual(missing_drag["dragTimingFailure"], "ambiguous-pointer-drag-timing")
        exceeded = self.run_schedule("arguments", extra=base + (flag, json.dumps({**timing, "count": 8})))
        self.assertEqual(exceeded["dragTimingFailure"], "pointer-drag-timing-exceeds-duration")
        rejected = self.run_schedule(pointer=False, extra=(flag, json.dumps(timing)))
        self.assertEqual(rejected["events"], [])

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
        self.assert_after_deadline(positive, pointer=False)
        self.assertIn("capture:series-0001", names)
        self.assertEqual(positive["previewLog"], "fixture-launch-evidence\nfixture-report\n")
        closed = self.run_schedule("close-before-capture", pointer=False, extra=flags)
        self.assertEqual([row["event"] for row in closed["events"]], ["launch", "launch-complete", "ready"])

    def test_log_only_keeps_one_after_report_without_captures_or_surface_lookups(self) -> None:
        for pointer in (False, True):
            with self.subTest(pointer=pointer):
                payload = self.run_schedule(pointer=pointer, extra=(
                    "--mwx-debug-scene-log-only",
                    "--mwx-debug-scene-periodic-snapshot-interval", "0.08",
                ))
                self.assertTrue(payload["logOnly"])
                self.assertEqual(payload["duration"], 4)
                self.assertEqual(len(payload["modeLogs"]), 1)
                self.assertIn("pointer=declared" if pointer else "pointer=outside",
                              payload["modeLogs"][0])
                events = payload["events"]
                reports = [row for row in events if row["event"] == "particle-report"]
                self.assertEqual(len(reports), 1, events)
                self.assertGreaterEqual(reports[0]["time"],
                                        payload["scheduleTime"] + payload["afterDelay"] - 0.01)
                self.assertFalse(any(row["event"].startswith("capture:") for row in events))
                self.assertEqual(payload["snapshotLookups"], 0)
                self.assertEqual(payload["previewLog"], "fixture-launch-evidence\nfixture-report\n")
                if pointer:
                    self.assertGreater(sum(row["event"] == "pointer:up" for row in events), 0)

    def test_log_only_closing_suppresses_the_after_report(self) -> None:
        payload = self.run_schedule("close-before-capture", pointer=False, extra=(
            "--mwx-debug-scene-log-only", "--mwx-debug-scene-duration", "3",
        ))
        self.assertEqual([row["event"] for row in payload["events"]],
                         ["pointer:outside", "launch", "launch-complete", "ready"])
        self.assertEqual(payload["snapshotLookups"], 0)
        self.assertEqual(payload["previewLog"], "fixture-launch-evidence\n")

    def test_log_only_fixes_undeclared_pointer_outside_without_changing_visual_input(self) -> None:
        for log_only in (False, True):
            with self.subTest(log_only=log_only):
                flags = ("--mwx-debug-scene-after-snapshot-delay", "1.1")
                if log_only:
                    flags += ("--mwx-debug-scene-log-only",)
                payload = self.run_schedule("physical-pointer-inside", pointer=False, extra=flags)
                launch = next(row for row in payload["events"] if row["event"] == "launch")
                self.assertEqual(launch["inside"], not log_only)
                self.assertEqual(launch["point"], [0, 0] if log_only else [0.75, 0.5])
                self.assertEqual([row["event"] for row in payload["suspendedEvents"]],
                                 ["pointer:outside", "launch"] if log_only else ["launch"])
                self.assertEqual(len(payload["modeLogs"]), int(log_only))

    def test_log_only_duration_bounds_preserve_visual_defaults_and_delayed_representatives(self) -> None:
        for flags, expected in [
            ((), 10), (("--mwx-debug-scene-duration", "3"), 7),
            (("--mwx-debug-scene-duration", "nan"), 10),
            (("--mwx-debug-scene-log-only",), 4),
            *((
                ("--mwx-debug-scene-log-only", "--mwx-debug-scene-duration", raw), duration
            ) for raw, duration in [("0", 3), ("3", 3), ("4", 4), ("5", 5),
                                    ("30", 30), ("4000", 3600), ("nan", 4), ("inf", 4)]),
        ]:
            with self.subTest(flags=flags):
                payload = self.run_schedule("arguments", pointer=False, extra=flags)
                self.assertEqual(payload["duration"], expected)
                self.assertEqual(payload["afterDelay"], min(3, expected - 0.5))

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
