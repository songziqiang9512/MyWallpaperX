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

from script.tests.scene_wallpaper_benchmark_test_support import (
    static_effect_disposition,
    shader_stage,
    runtime_evidence,
    effect_runtime_disposition_preview,
    effect_cpu_event,
    effect_route_event,
    effect_execution_log,
    graph_execution_observation,
    resolved_graph_exact_evidence,
    resolved_graph_passthrough_evidence,
    resolved_graph_effect_local_failure_evidence,
    resolved_graph_effect_recovery_evidence,
    resolved_graph_effect_recovery_log,
    resolved_graph_visual_failure_log,
)


class SceneWallpaperPropertyUpdatesTests(unittest.TestCase):
    def test_resize_sequence_argument_is_forwarded_atomically(self) -> None:
        command = ["MyWallpaperX"]
        benchmark.append_resize_sequence_argument(
            command,
            "1.5:0.6,3.5:1.0",
        )
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-resize-sequence",
            "1.5:0.6,3.5:1.0",
        ])

        unchanged = ["MyWallpaperX"]
        benchmark.append_resize_sequence_argument(unchanged, None)
        self.assertEqual(unchanged, ["MyWallpaperX"])

    def test_live_property_arguments_and_strict_identity_gate(self) -> None:
        command = ["MyWallpaperX"]
        benchmark.append_property_arguments(
            command,
            {"initial": 0.7},
            {"newproperty11": 0},
        )
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-properties-json",
            '{"initial":0.7}',
            "--mwx-debug-scene-live-properties-json",
            '{"newproperty11":0}',
        ])
        accepted = benchmark.live_property_update_metrics(
            "phase=live-property-update accepted=true surfacesBefore=1 surfacesAfter=1 "
            "windowsBefore=42 windowsAfter=42 keys=newproperty11"
        )
        replaced = benchmark.live_property_update_metrics(
            "phase=live-property-update accepted=true surfacesBefore=1 surfacesAfter=1 "
            "windowsBefore=42 windowsAfter=43 keys=newproperty11"
        )
        rejected = benchmark.live_property_update_metrics(
            "phase=live-property-update accepted=false surfacesBefore=1 surfacesAfter=1 "
            "windowsBefore=42 windowsAfter=42 keys=newproperty11"
        )
        requested = {"newproperty11": 0}
        self.assertEqual(benchmark.live_property_update_failures(requested, accepted), [])
        self.assertIn(
            "live property update replaced Scene windows",
            benchmark.live_property_update_failures(requested, replaced),
        )
        self.assertIn(
            "live property update rejected",
            benchmark.live_property_update_failures(requested, rejected),
        )
        self.assertIn(
            "live property update evidence missing",
            benchmark.live_property_update_failures(requested, None),
        )

    def test_deferred_property_transition_requires_one_terminal_per_generation(
        self,
    ) -> None:
        metrics = benchmark.deferred_property_transition_metrics("\n".join([
            "MWX deferred property transition: "
            "schema=deferred-property-transition-v1 generation=1 "
            "layers=25 state=pending",
            "MWX deferred base image: schema=deferred-base-image-v2 "
            "sceneGeneration=7 requestGeneration=1 layer=25 status=ready",
            "MWX deferred property transition: "
            "schema=deferred-property-transition-v1 generation=1 "
            "layers=25 state=committed",
        ]))
        self.assertTrue(metrics["contract_succeeded"])
        self.assertEqual(metrics["pending_generations"], [1])
        self.assertEqual(metrics["committed_generations"], [1])
        self.assertEqual(metrics["terminal_generations"], [1])
        self.assertEqual(metrics["resource_outcomes"][0]["layer_id"], 25)

        superseded = benchmark.deferred_property_transition_metrics("\n".join([
            "MWX deferred property transition: "
            "schema=deferred-property-transition-v1 generation=1 "
            "layers=95 state=pending",
            "MWX deferred property transition: "
            "schema=deferred-property-transition-v1 generation=1 "
            "layers=95 state=superseded",
            "MWX deferred property transition: "
            "schema=deferred-property-transition-v1 generation=2 "
            "layers=25 state=pending",
            "MWX deferred property transition: "
            "schema=deferred-property-transition-v1 generation=2 "
            "layers=25 state=committed",
        ]))
        self.assertTrue(superseded["contract_succeeded"])
        self.assertEqual(superseded["terminal_generations"], [1, 2])

        incomplete = benchmark.deferred_property_transition_metrics(
            "MWX deferred property transition: "
            "schema=deferred-property-transition-v1 generation=3 "
            "layers=29 state=pending"
        )
        self.assertFalse(incomplete["contract_succeeded"])
        self.assertIn(
            "deferred property generation missing unique terminal state",
            incomplete["validation_failures"],
        )

    def test_user_texture_overrides_stay_inside_isolated_sample(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-user-texture-") as directory:
            runtime_sample = Path(directory)
            (runtime_sample / "custom.png").write_bytes(b"fixture")
            command = ["MyWallpaperX"]
            failures: list[str] = []
            benchmark.append_texture_override_argument(
                command,
                {"customCover": "custom.png"},
                runtime_sample,
                failures,
            )
            self.assertEqual(failures, [])
            self.assertEqual(command[:2], [
                "MyWallpaperX",
                "--mwx-debug-scene-textures-json",
            ])
            self.assertEqual(
                json.loads(command[2]),
                {"customCover": "custom.png"},
            )
            for extension in ("mp4", "mov", "m4v"):
                name = "renamed-media." + extension
                (runtime_sample / name).write_bytes(b"argument-parser-fixture-not-ready-media")
                media_command: list[str] = []
                media_failures: list[str] = []
                benchmark.append_texture_override_argument(
                    media_command, {"anotherProperty": name}, runtime_sample, media_failures
                )
                self.assertEqual(media_failures, [])
                self.assertEqual(json.loads(media_command[-1]), {"anotherProperty": name})
            (runtime_sample / "unsupported.webm").write_bytes(b"fixture")
            for invalid in (
                {"customCover": "../custom.png"},
                {"customCover": "missing.png"},
                {"customCover": "custom.tex"},
                {"customCover": "unsupported.webm"},
                {"\n": "custom.png"},
                ["custom.png"],
            ):
                invalid_failures: list[str] = []
                benchmark.append_texture_override_argument(
                    [], invalid, runtime_sample, invalid_failures
                )
                self.assertEqual(
                    invalid_failures,
                    ["invalid isolated user texture overrides"],
                )

    def test_dynamic_values_fault_argument_is_explicit_and_frame_bounded(self) -> None:
        command = ["MyWallpaperX"]
        benchmark.append_dynamic_values_fault_argument(command, 42)
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-drop-dynamic-values-frame",
            "42",
        ])

        unchanged = ["MyWallpaperX"]
        benchmark.append_dynamic_values_fault_argument(unchanged, None)
        self.assertEqual(unchanged, ["MyWallpaperX"])

        self.assertEqual(benchmark.positive_uint64("1"), 1)
        self.assertEqual(benchmark.positive_uint64(str((1 << 64) - 1)), (1 << 64) - 1)
        for invalid in ("0", "-1", str(1 << 64), "1.5"):
            with self.assertRaises(benchmark.argparse.ArgumentTypeError):
                benchmark.positive_uint64(invalid)

    def test_media_properties_arguments_are_atomic_and_bounded(self) -> None:
        command = ["MyWallpaperX"]
        failures: list[str] = []
        benchmark.append_media_properties_arguments(
            command,
            "春日歌",
            "Fixture Artist 🎵",
            failures,
        )
        self.assertEqual(failures, [])
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-media-title",
            "春日歌",
            "--mwx-debug-scene-media-artist",
            "Fixture Artist 🎵",
        ])

        empty_command = ["MyWallpaperX"]
        empty_failures: list[str] = []
        benchmark.append_media_properties_arguments(
            empty_command,
            "",
            "",
            empty_failures,
        )
        self.assertEqual(empty_failures, [])
        self.assertEqual(empty_command[-4:], [
            "--mwx-debug-scene-media-title",
            "",
            "--mwx-debug-scene-media-artist",
            "",
        ])

        exact_limit_command = ["MyWallpaperX"]
        exact_limit_failures: list[str] = []
        benchmark.append_media_properties_arguments(
            exact_limit_command,
            "a" * (4 * 1_024),
            "artist",
            exact_limit_failures,
        )
        self.assertEqual(exact_limit_failures, [])
        self.assertEqual(len(exact_limit_command), 5)

        invalid_pairs = (
            ("title", None, "media properties require title and artist together"),
            (None, "artist", "media properties require title and artist together"),
            (7, "artist", "invalid media properties"),
            ("title\nline", "artist", "invalid media properties"),
            ("界" * 1_366, "artist", "invalid media properties"),
            ("\ud800", "artist", "invalid media properties"),
        )
        for title, artist, expected_failure in invalid_pairs:
            invalid_command = ["MyWallpaperX"]
            invalid_failures: list[str] = []
            benchmark.append_media_properties_arguments(
                invalid_command,
                title,
                artist,
                invalid_failures,
            )
            self.assertEqual(invalid_failures, [expected_failure])
            self.assertEqual(invalid_command, ["MyWallpaperX"])

    def test_media_thumbnail_sequence_stays_inside_isolated_sample(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-media-thumbnail-sequence-") as directory:
            runtime_sample = Path(directory)
            (runtime_sample / "next.png").write_bytes(b"fixture")
            command = ["MyWallpaperX"]
            failures: list[str] = []
            benchmark.append_media_thumbnail_sequence_argument(
                command,
                [
                    {"path": "next.png", "delay": 1.5},
                    {"clear": True, "delay": 3.0},
                ],
                runtime_sample,
                failures,
            )
            self.assertEqual(failures, [])
            self.assertEqual(command[:2], [
                "MyWallpaperX",
                "--mwx-debug-scene-media-thumbnail-sequence-json",
            ])
            self.assertEqual(
                json.loads(command[2]),
                [
                    {"path": "next.png", "delay": 1.5},
                    {"clear": True, "delay": 3.0},
                ],
            )
            for invalid in (
                [{"path": "../next.png", "delay": 1.5}],
                [{"path": "next.png", "delay": 0}],
                [{"path": "next.png", "delay": True}],
                [{"path": "missing.png", "delay": 1.5}],
                [{"clear": False, "delay": 1.5}],
                [{"clear": True, "path": "next.png", "delay": 1.5}],
            ):
                invalid_failures: list[str] = []
                benchmark.append_media_thumbnail_sequence_argument(
                    [], invalid, runtime_sample, invalid_failures
                )
                self.assertEqual(
                    invalid_failures,
                    ["invalid isolated media thumbnail sequence"],
                )

    def test_media_thumbnail_store_metrics_preserve_pending_and_clear_state(self) -> None:
        log = """
MWX media thumbnail store: phase=ready generation=1 hasCurrent=true
MWX media thumbnail store: phase=pending-last-ready requestedGeneration=2 readyGeneration=1 hasColor=true hasPreserved=true
MWX media thumbnail store: phase=ready generation=2 hasColor=true hasPreserved=true
MWX DEBUG SCENE: phase=media-thumbnail-cleared
MWX media thumbnail store: phase=pending-last-ready requestedGeneration=3 readyGeneration=2 hasColor=true hasPreserved=true
MWX media thumbnail store: phase=ready generation=3 hasColor=false hasPreserved=false
"""
        self.assertEqual(
            benchmark.media_thumbnail_store_metrics(log),
            {
                "pending_last_ready": [
                    {
                        "requested_generation": 2,
                        "ready_generation": 1,
                        "has_current": True,
                        "has_color": True,
                        "has_preserved": True,
                    },
                    {
                        "requested_generation": 3,
                        "ready_generation": 2,
                        "has_current": True,
                        "has_color": True,
                        "has_preserved": True,
                    },
                ],
                "ready_states": [
                    {
                        "generation": 1,
                        "has_current": True,
                    },
                    {
                        "generation": 2,
                        "has_current": True,
                        "has_color": True,
                        "has_preserved": True,
                    },
                    {
                        "generation": 3,
                        "has_current": False,
                        "has_color": False,
                        "has_preserved": False,
                    },
                ],
                "clear_count": 1,
            },
        )

    def test_live_property_output_requires_a_visible_post_update_change(self) -> None:
        sample = {"minimum_live_changed_ratio": 0.01}
        self.assertEqual(
            benchmark.live_property_output_failures(sample, {"changed_ratio": 0.02}),
            [],
        )
        self.assertEqual(
            benchmark.live_property_output_failures(sample, {"changed_ratio": 0.001}),
            ["live property output evidence below minimum"],
        )
        self.assertEqual(
            benchmark.live_property_output_failures(sample, None),
            ["live property output evidence below minimum"],
        )

    def test_debug_runner_updates_the_existing_host_record(self) -> None:
        source = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        arguments_source = DEBUG_ARGUMENTS_RUNNER_SOURCE.read_text(
            encoding="utf-8"
        )
        self.assertIn('private static let debugRecordID = "debug-scene-playback"', source)
        self.assertIn(
            "--mwx-debug-scene-live-properties-json", arguments_source
        )
        self.assertIn("recordID: debugRecordID", source)
        self.assertIn("phase=live-property-update", source)


if __name__ == "__main__":
    unittest.main()
