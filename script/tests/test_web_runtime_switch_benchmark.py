#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from web_runtime_switch_benchmark import (
    apply_process_outcome,
    score_log,
    validate_bundled_video_archive,
    write_reports,
)


SAMPLE_ID = "1509243786"
DEFAULTS_SUITE = "com.songziqiang.MyWallpaperX.Debug.runtime-switch-test"
VIDEO1_PID = 101
VIDEO2_PID = 202
RECOVERED_PID = 303


def action(name: str, elapsed_ms: int) -> str:
    return f"MWX DEBUG RUNTIME SWITCH: action={name} elapsedMs={elapsed_ms}"


def checkpoint(name: str, state: dict) -> str:
    payload = json.dumps(state, separators=(",", ":"), sort_keys=True)
    return f"MWX DEBUG RUNTIME SWITCH: checkpoint={name} state={payload}"


def diag(event_type: str, message: str, record: str = SAMPLE_ID) -> str:
    return (
        f"MWX WEB DIAG record={record} screen=1 severity=info "
        f"type={event_type} url=- message={message}"
    )


def web_state(
    phase: str = "idle", surfaces: int = 0, current_request: int = 0
) -> dict:
    return {
        "currentRequest": current_request,
        "loopbacks": 0,
        "monitors": 0,
        "observers": 0,
        "phase": phase,
        "pointerTimer": 0,
        "surfaces": surfaces,
        "watchTimer": 0,
        "watchers": 0,
    }


def session(pid: int, accepted=None, ready=None) -> dict:
    return {
        "accepted": accepted,
        "display": 1,
        "launched": accepted is not None,
        "pid": pid,
        "ready": ready,
        "requested": 1,
        "running": True,
    }


def state(
    *,
    crash_count: int = 0,
    kind: str = "-",
    path: str = "-",
    playing: bool = False,
    sessions: list | None = None,
    web: dict | None = None,
    playback_failures: int = 0,
    recovered_alive: list | None = None,
    recovered_pids: list | None = None,
    stale_failure_injected: bool = False,
    stale_handler_captured: bool = False,
    video1_alive: list | None = None,
    video1_pids: list | None = None,
    video2_alive: list | None = None,
    video2_pids: list | None = None,
) -> dict:
    return {
        "crashCount": crash_count,
        "elapsedMs": 0,
        "kind": kind,
        "path": path,
        "playbackFailures": playback_failures,
        "playing": playing,
        "recoveredAlive": recovered_alive or [],
        "recoveredPids": recovered_pids or [],
        "sessions": sessions or [],
        "staleFailureInjected": stale_failure_injected,
        "staleHandlerCaptured": stale_handler_captured,
        "video1Alive": video1_alive or [],
        "video1Pids": video1_pids or [],
        "video2Alive": video2_alive or [],
        "video2Pids": video2_pids or [],
        "web": web or web_state(),
    }


def passing_lines() -> list[str]:
    video1 = state(
        kind="video",
        path="Video1.mp4",
        playing=True,
        sessions=[session(VIDEO1_PID)],
        video1_alive=[VIDEO1_PID],
        video1_pids=[VIDEO1_PID],
        stale_handler_captured=True,
    )
    web = state(
        kind="web",
        path="index.html",
        playing=True,
        web=web_state("launching", surfaces=1, current_request=1),
        video1_alive=[VIDEO1_PID],
        video1_pids=[VIDEO1_PID],
        stale_handler_captured=True,
    )
    requested = state(
        kind="video",
        path="Video2.mp4",
        playing=True,
        sessions=[session(VIDEO2_PID)],
        video1_pids=[VIDEO1_PID],
        video2_alive=[VIDEO2_PID],
        video2_pids=[VIDEO2_PID],
        stale_handler_captured=True,
    )
    stable = copy.deepcopy(requested)
    stable["sessions"] = [session(VIDEO2_PID, accepted=1, ready=1)]
    stable["staleFailureInjected"] = True
    stale_filtered = copy.deepcopy(requested)
    stale_filtered["staleFailureInjected"] = True
    recovered = state(
        kind="video",
        path="Video2.mp4",
        playing=True,
        sessions=[session(RECOVERED_PID, accepted=1, ready=1)],
        recovered_alive=[RECOVERED_PID],
        recovered_pids=[RECOVERED_PID],
        stale_failure_injected=True,
        stale_handler_captured=True,
        video1_pids=[VIDEO1_PID],
        video2_pids=[VIDEO2_PID],
    )
    stopped = state(
        crash_count=2,
        recovered_pids=[RECOVERED_PID],
        stale_failure_injected=True,
        stale_handler_captured=True,
        video1_pids=[VIDEO1_PID],
        video2_pids=[VIDEO2_PID],
    )
    return [
        f"MWX DEBUG DEFAULTS: suite={DEFAULTS_SUITE}",
        action("preflight", 0),
        checkpoint("preflight", state()),
        action("video1", 0),
        checkpoint("video1-requested", video1),
        action("web", 35),
        diag("runtime.profile", "profile=standard origin=customScheme dataStore=workshopPersistent"),
        checkpoint("web-requested", web),
        action("video2", 105),
        diag("lifecycle.teardown", "surfaces=0 loopbacks=0 watchers=0 monitors=0 pointerTimer=0"),
        diag("lifecycle.stop", "phase=idle surfaces=0 loopbacks=0 observers=0"),
        checkpoint("video2-requested", requested),
        action("inject-stale-failure", 106),
        checkpoint("stale-event-filtered", stale_filtered),
        diag("lifecycle.surface.released", "screen=1", record="-"),
        checkpoint("video2-stable", stable),
        action("crash-video2", 3100),
        checkpoint("video2-recovered", recovered),
        action("crash-video2-delayed", 6100),
        checkpoint(
            "recovery-pending",
            state(
                crash_count=2,
                kind="video",
                path="Video2.mp4",
                recovered_pids=[RECOVERED_PID],
                stale_failure_injected=True,
                stale_handler_captured=True,
                video1_pids=[VIDEO1_PID],
                video2_pids=[VIDEO2_PID],
            ),
        ),
        action("stop", 6500),
        checkpoint("stopped", stopped),
        checkpoint("post-stop", stopped),
        action("completed", 10100),
    ]


def score(lines: list[str]) -> dict:
    return score_log("\n".join(lines), SAMPLE_ID, DEFAULTS_SUITE)


def replace_checkpoint(lines: list[str], name: str, mutate) -> list[str]:
    updated = list(lines)
    prefix = f"MWX DEBUG RUNTIME SWITCH: checkpoint={name} state="
    index = next(i for i, line in enumerate(updated) if line.startswith(prefix))
    payload = json.loads(updated[index][len(prefix):])
    mutate(payload)
    updated[index] = checkpoint(name, payload)
    return updated


class WebRuntimeSwitchBenchmarkTests(unittest.TestCase):
    def test_bundled_video_preflight_requires_the_fixed_archive(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-runtime-switch-videos-") as directory:
            resources = Path(directory)
            with zipfile.ZipFile(resources / "Videos.zip", "w") as archive:
                for index in range(1, 6):
                    archive.writestr(f"Video{index}.mp4", b"video")
            validate_bundled_video_archive(resources)

            with zipfile.ZipFile(resources / "Videos.zip", "w") as archive:
                archive.writestr("Video1.mp4", b"video")
            with self.assertRaisesRegex(ValueError, "entries are invalid"):
                validate_bundled_video_archive(resources)

    def test_passing_timeline(self) -> None:
        result = score(passing_lines())
        self.assertTrue(result["passed"], result["failures"])
        self.assertTrue(result["switch_passed"])
        self.assertTrue(result["ownership_passed"])
        self.assertTrue(result["cleanup_passed"])
        self.assertEqual(result["switch_interval_ms"], 105)
        self.assertEqual(result["video1_pids"], [VIDEO1_PID])
        self.assertEqual(result["video2_pids"], [VIDEO2_PID])
        self.assertEqual(result["recovered_pids"], [RECOVERED_PID])

    def test_rejects_missing_defaults_suite(self) -> None:
        result = score(passing_lines()[1:])
        self.assertFalse(result["passed"])
        self.assertIsNone(result["debug_defaults_suite"])

    def test_rejects_slow_switch_that_misses_race_window(self) -> None:
        lines = [
            line.replace("action=video2 elapsedMs=105", "action=video2 elapsedMs=300")
            for line in passing_lines()
        ]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertEqual(result["switch_interval_ms"], 300)

    def test_rejects_video2_that_leaves_web_active(self) -> None:
        lines = replace_checkpoint(
            passing_lines(),
            "video2-stable",
            lambda payload: payload.update(
                kind="web",
                path="index.html",
                sessions=[],
                web=web_state("ready", surfaces=1, current_request=1),
            ),
        )
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("Video2 stable state" in failure for failure in result["failures"]))

    def test_rejects_video2_without_ready_acknowledgement(self) -> None:
        lines = replace_checkpoint(
            passing_lines(),
            "video2-stable",
            lambda payload: payload["sessions"][0].update(ready=None),
        )
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("accept, and ready" in failure for failure in result["failures"]))

    def test_rejects_reused_or_live_video1_pid(self) -> None:
        def mutate(payload: dict) -> None:
            payload["sessions"][0]["pid"] = VIDEO1_PID
            payload["video1Alive"] = [VIDEO1_PID]
            payload["video2Alive"] = [VIDEO1_PID]
            payload["video2Pids"] = [VIDEO1_PID]

        lines = replace_checkpoint(passing_lines(), "video2-stable", mutate)
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("Video1 daemon PID" in failure for failure in result["failures"]))

    def test_rejects_missing_web_lifecycle_stop(self) -> None:
        lines = [line for line in passing_lines() if "type=lifecycle.stop " not in line]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("did not stop Web" in failure for failure in result["failures"]))

    def test_rejects_retained_web_surface(self) -> None:
        lines = [
            line.replace("type=lifecycle.surface.released", "type=lifecycle.surface.retained")
            for line in passing_lines()
        ]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertEqual(result["retained_surface_count"], 1)

    def test_rejects_web_ready_after_video2_intent(self) -> None:
        lines = passing_lines()
        index = lines.index(checkpoint("video2-stable", json.loads(
            next(line.split(" state=", 1)[1] for line in lines if "checkpoint=video2-stable " in line)
        )))
        lines.insert(index, diag("host.ready", "ready"))
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("stale Web host" in failure for failure in result["failures"]))

    def test_rejects_final_daemon_or_web_residue(self) -> None:
        def mutate(payload: dict) -> None:
            payload["sessions"] = [session(VIDEO2_PID, accepted=1, ready=1)]
            payload["video2Alive"] = [VIDEO2_PID]
            payload["web"] = web_state("idle", surfaces=1)

        result = score(replace_checkpoint(passing_lines(), "stopped", mutate))
        self.assertFalse(result["passed"])
        self.assertTrue(result["switch_passed"])
        self.assertFalse(result["cleanup_passed"])
        self.assertTrue(any("stopped" in failure for failure in result["failures"]))

    def test_rejects_stale_reader_failure_notification(self) -> None:
        lines = replace_checkpoint(
            passing_lines(),
            "stale-event-filtered",
            lambda payload: payload.update(playbackFailures=1),
        )
        result = score(lines)
        self.assertFalse(result["ownership_passed"])
        self.assertTrue(
            any("stale Video1 output" in failure for failure in result["ownership_failures"])
        )

    def test_rejects_recovery_that_reuses_terminated_pid(self) -> None:
        def mutate(payload: dict) -> None:
            payload["sessions"][0]["pid"] = VIDEO2_PID
            payload["recoveredAlive"] = [VIDEO2_PID]
            payload["recoveredPids"] = [VIDEO2_PID]

        result = score(
            replace_checkpoint(passing_lines(), "video2-recovered", mutate)
        )
        self.assertFalse(result["ownership_passed"])
        self.assertTrue(
            any("new daemon PID" in failure for failure in result["ownership_failures"])
        )

    def test_rejects_recovered_daemon_without_ready_acknowledgement(self) -> None:
        result = score(
            replace_checkpoint(
                passing_lines(),
                "video2-recovered",
                lambda payload: payload["sessions"][0].update(ready=None),
            )
        )
        self.assertFalse(result["ownership_passed"])
        self.assertTrue(
            any("recovered Video2 daemon" in failure for failure in result["ownership_failures"])
        )

    def test_rejects_delayed_post_stop_revival(self) -> None:
        def mutate(payload: dict) -> None:
            payload.update(kind="video", path="Video2.mp4", playing=True)
            payload["sessions"] = [session(404, accepted=1, ready=1)]
            payload["recoveredAlive"] = [404]

        result = score(replace_checkpoint(passing_lines(), "post-stop", mutate))
        self.assertFalse(result["cleanup_passed"])
        self.assertTrue(
            any("post-stop" in failure for failure in result["cleanup_failures"])
        )

    def test_rejects_missing_nonzero_backoff_window(self) -> None:
        result = score(
            replace_checkpoint(
                passing_lines(),
                "recovery-pending",
                lambda payload: payload.update(crashCount=1),
            )
        )
        self.assertFalse(result["ownership_passed"])
        self.assertTrue(
            any("nonzero-backoff" in failure for failure in result["ownership_failures"])
        )

    def test_report_writer_accepts_complete_score(self) -> None:
        report = score(passing_lines())
        report.update(
            requested_scope="full",
            scope_passed=True,
            log_path="/tmp/runtime-switch-test.log",
        )
        with tempfile.TemporaryDirectory() as directory:
            json_path, markdown_path = write_reports(Path(directory), report)
            self.assertTrue(json_path.is_file())
            self.assertIn("Ownership gate: PASS", markdown_path.read_text())

    def test_rejects_empty_checkpoint_states(self) -> None:
        lines = [
            line.split(" state=", 1)[0] + " state={}"
            if "MWX DEBUG RUNTIME SWITCH: checkpoint=" in line
            else line
            for line in passing_lines()
        ]
        result = score(lines)
        self.assertFalse(result["switch_passed"])
        self.assertTrue(
            any("invalid or missing" in failure for failure in result["switch_failures"])
        )

    def test_rejects_app_exit_before_deadline(self) -> None:
        result = score(passing_lines())
        apply_process_outcome(result, launch_error=None, process_survived_duration=False)
        self.assertFalse(result["passed"])
        self.assertFalse(result["switch_passed"])
        self.assertTrue(
            any("exited before" in failure for failure in result["switch_failures"])
        )

    def test_rejects_action_order_change(self) -> None:
        lines = passing_lines()
        web_index = next(i for i, line in enumerate(lines) if "action=web " in line)
        video2_index = next(i for i, line in enumerate(lines) if "action=video2 " in line)
        lines[web_index], lines[video2_index] = lines[video2_index], lines[web_index]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertNotEqual(result["observed_actions"], result["expected_actions"])


if __name__ == "__main__":
    unittest.main()
