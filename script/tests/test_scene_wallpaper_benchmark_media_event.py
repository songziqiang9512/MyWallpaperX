#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_wallpaper_benchmark as benchmark


MEDIA_TARGET = (
    'effectConstant(layerID: 1089, effectIndex: 0, passIndex: 0, name: "color")'
)
MEDIA_COMPLETION_LINE = (
    "MWX SceneScript VM: target=effectConstant(layerID: 1089, "
    "effectIndex: 0, passIndex: 0, name: \"color\") "
    "event=mediaThumbnailChanged generation=2 hasThumbnail=true "
    "primary=0.1,0.2,0.3 secondary=0.2,0.3,0.4 "
    "tertiary=0.3,0.4,0.5 text=0.4,0.5,0.6 "
    "highContrast=0.5,0.6,0.7 output=vector3(0.2, 0.3, 1.0) "
    "mutations=0 route=generic-only fallback=none"
)
MEDIA_CALLBACK_EXPECTATION = {
    "layer_id": 1089,
    "effect_index": 0,
    "pass_index": 0,
    "constant": "color",
    "generation": 2,
    "has_thumbnail": True,
    "primary_color": [0.1, 0.2, 0.3],
    "secondary_color": [0.2, 0.3, 0.4],
    "tertiary_color": [0.3, 0.4, 0.5],
    "text_color": [0.4, 0.5, 0.6],
    "high_contrast_color": [0.5, 0.6, 0.7],
    "route": "generic-only",
}


def vector_media_startup_line(
    *,
    route: str = "generic-only",
    reason: str = "active",
    targets: list[str] | None = None,
    active_bindings: int | None = None,
) -> str:
    target_list = [MEDIA_TARGET] if targets is None else targets
    active_count = (
        (0 if route == "disable-generic" else len(target_list))
        if active_bindings is None else active_bindings
    )
    return (
        "scene media thumbnail colors: schema=quickjs-ng-thumbnail-colors-v1 "
        f"bindings={len(target_list)} activeBindings={active_count} route={route} "
        "fallback=current-frame-lower-priority "
        f"reason={reason} profile=scenescript-vector-media-thumbnail "
        "input=typed-inbox liveProvider=unavailable targets="
        + json.dumps(target_list, separators=(",", ":"))
    )


class SceneWallpaperBenchmarkMediaEventTests(unittest.TestCase):
    def test_generic_five_color_completion_is_reported(self) -> None:
        metrics = benchmark.media_color_transition_metrics(MEDIA_COMPLETION_LINE)
        self.assertEqual(metrics, [{
            "layer_id": 1089,
            "effect_index": 0,
            "pass_index": 0,
            "constant": "color",
            "generation": 2,
            "has_thumbnail": True,
            "primary_color": [0.1, 0.2, 0.3],
            "secondary_color": [0.2, 0.3, 0.4],
            "tertiary_color": [0.3, 0.4, 0.5],
            "text_color": [0.4, 0.5, 0.6],
            "high_contrast_color": [0.5, 0.6, 0.7],
            "output_type": "vector3",
            "output": [0.2, 0.3, 1.0],
            "mutations": 0,
            "fallback": "none",
            "route": "generic-only",
        }])

        malformed = benchmark.media_color_transition_metrics(
            "MWX SceneScript VM: target=effectConstant(layerID: 1089, "
            "effectIndex: 0, passIndex: 0, name: \"color\") "
            "event=mediaThumbnailChanged generation=2 hasThumbnail=true "
            "primary=0.1,0.2,0.3 secondary=0.2,0.3,0.4 "
            "tertiary=0.3,0.4,0.5 text=0.4,0.5,0.6 "
            "highContrast=0.5,0.6,0.7 output=vector3(bad, 0.3, 1.0) "
            "mutations=0 route=generic-only fallback=none"
        )
        self.assertEqual(malformed, [])

    def test_startup_route_is_structured_for_the_report(self) -> None:
        metrics = benchmark.scene_script_vector_media_startup_metrics(
            vector_media_startup_line()
        )
        self.assertEqual(metrics, {
            "observation_count": 1,
            "malformed_observation_count": 0,
            "schema": "quickjs-ng-thumbnail-colors-v1",
            "bindings": 1,
            "active_bindings": 1,
            "route": "generic-only",
            "fallback": "current-frame-lower-priority",
            "reason": "active",
            "profile": "scenescript-vector-media-thumbnail",
            "input": "typed-inbox",
            "live_provider": "unavailable",
            "targets": [MEDIA_TARGET],
        })

        malformed = benchmark.scene_script_vector_media_startup_metrics(
            vector_media_startup_line()[:-2]
        )
        self.assertEqual(malformed["observation_count"], 1)
        self.assertEqual(malformed["malformed_observation_count"], 1)
        self.assertIsNone(malformed["route"])
        self.assertEqual(malformed["targets"], [])

    def test_exact_callback_and_startup_expectations_pass(self) -> None:
        completions = benchmark.media_color_transition_metrics(MEDIA_COMPLETION_LINE)
        startup = benchmark.scene_script_vector_media_startup_metrics(
            vector_media_startup_line()
        )
        sample = {
            "expected_media_color_callback_count": 1,
            "expected_media_color_callbacks": [MEDIA_CALLBACK_EXPECTATION],
            "expected_scene_script_vector_media_startup": {
                "bindings": 1,
                "active_bindings": 1,
                "route": "generic-only",
                "reason": "active",
                "targets": [MEDIA_TARGET],
            },
        }
        self.assertEqual(
            benchmark.media_event_expectation_failures(
                sample,
                completions,
                startup,
            ),
            [],
        )

    def test_disable_route_rejects_any_media_owner_output(self) -> None:
        completions: list[dict[str, object]] = []
        startup = benchmark.scene_script_vector_media_startup_metrics(
            vector_media_startup_line(
                route="disable-generic",
                reason="route-disabled",
            )
        )
        sample = {
            "expected_media_color_callback_count": 0,
            "expected_media_color_callbacks": [],
            "expected_media_owner_output_count": 0,
            "expected_scene_script_vector_media_startup": {
                "active_bindings": 0,
                "route": "disable-generic",
                "reason": "route-disabled",
                "targets": [MEDIA_TARGET],
            },
        }
        leaked_output = {
            "layer_id": 1089,
            "effect_index": 0,
            "pass_index": 0,
            "constant": "color",
            "type": "vector3",
            "input": "vector3(1, 1, 1)",
            "output": "vector3(1, 1, 1)",
            "route": "generic-only",
        }
        owner_outputs = benchmark.media_owner_output_metrics(
            [leaked_output], startup
        )
        self.assertEqual(owner_outputs, [leaked_output])
        self.assertEqual(
            benchmark.media_event_expectation_failures(
                sample,
                completions,
                startup,
                owner_outputs,
            ),
            ["media owner output count mismatch"],
        )
        self.assertEqual(
            benchmark.media_event_expectation_failures(
                sample,
                completions,
                startup,
                [],
            ),
            [],
        )

    def test_callback_expectations_reject_each_contract_mismatch(self) -> None:
        completions = benchmark.media_color_transition_metrics(MEDIA_COMPLETION_LINE)
        startup = benchmark.scene_script_vector_media_startup_metrics("")
        mismatches = {
            "layer_id": 1090,
            "effect_index": 1,
            "pass_index": 1,
            "constant": "other",
            "generation": 3,
            "has_thumbnail": False,
            "route": "disable-generic",
            "primary_color": [0.9, 0.2, 0.3],
            "secondary_color": [0.9, 0.3, 0.4],
            "tertiary_color": [0.9, 0.4, 0.5],
            "text_color": [0.9, 0.5, 0.6],
            "high_contrast_color": [0.9, 0.6, 0.7],
        }
        for field, wrong_value in mismatches.items():
            with self.subTest(field=field):
                expected = copy.deepcopy(MEDIA_CALLBACK_EXPECTATION)
                expected[field] = wrong_value
                failures = benchmark.media_event_expectation_failures(
                    {"expected_media_color_callbacks": [expected]},
                    completions,
                    startup,
                )
                self.assertEqual(failures, ["media color callbacks mismatch"])

        self.assertEqual(
            benchmark.media_event_expectation_failures(
                {"expected_media_color_callback_count": 0},
                completions,
                startup,
            ),
            ["media color callback count mismatch"],
        )

    def test_startup_expectation_rejects_route_reason_and_targets(self) -> None:
        startup = benchmark.scene_script_vector_media_startup_metrics(
            vector_media_startup_line()
        )
        mismatches = {
            "active_bindings": 0,
            "route": "disable-generic",
            "reason": "route-disabled",
            "targets": [MEDIA_TARGET + "-other"],
        }
        for field, wrong_value in mismatches.items():
            with self.subTest(field=field):
                expected = {
                    "route": "generic-only",
                    "reason": "active",
                    "targets": [MEDIA_TARGET],
                }
                expected[field] = wrong_value
                failures = benchmark.media_event_expectation_failures(
                    {"expected_scene_script_vector_media_startup": expected},
                    [],
                    startup,
                )
                self.assertEqual(
                    failures,
                    [f"SceneScript vector media startup {field} mismatch"],
                )

    def test_missing_expectations_remain_backward_compatible(self) -> None:
        missing_startup = benchmark.scene_script_vector_media_startup_metrics("")
        self.assertEqual(
            benchmark.media_event_expectation_failures(
                {},
                benchmark.media_color_transition_metrics(MEDIA_COMPLETION_LINE),
                missing_startup,
            ),
            [],
        )

    def test_thumbnail_argument_stays_inside_isolated_sample(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-media-thumbnail-argument-"
        ) as directory:
            runtime_sample = Path(directory)
            (runtime_sample / "cover.png").write_bytes(b"fixture")
            command = ["MyWallpaperX"]
            failures: list[str] = []

            benchmark.append_media_thumbnail_argument(
                command,
                "cover.png",
                runtime_sample,
                failures,
            )

            self.assertEqual(failures, [])
            self.assertEqual(command, [
                "MyWallpaperX",
                "--mwx-debug-scene-media-thumbnail",
                "cover.png",
            ])

            event_command = ["MyWallpaperX"]
            event_failures: list[str] = []
            benchmark.append_media_thumbnail_argument(
                event_command,
                "cover.png",
                runtime_sample,
                event_failures,
                primary_color=[1, 0.25, 0],
                secondary_color=[0.125, 0.5, 1],
                tertiary_color=[0.2, 0.4, 0.6],
                text_color=[0.3, 0.5, 0.7],
                high_contrast_color=[0.4, 0.6, 0.8],
                playback_state=1,
            )
            self.assertEqual(event_failures, [])
            self.assertEqual(event_command, [
                "MyWallpaperX",
                "--mwx-debug-scene-media-thumbnail",
                "cover.png",
                "--mwx-debug-scene-media-primary-color-json",
                "[1.0,0.25,0.0]",
                "--mwx-debug-scene-media-secondary-color-json",
                "[0.125,0.5,1.0]",
                "--mwx-debug-scene-media-tertiary-color-json",
                "[0.2,0.4,0.6]",
                "--mwx-debug-scene-media-text-color-json",
                "[0.3,0.5,0.7]",
                "--mwx-debug-scene-media-high-contrast-color-json",
                "[0.4,0.6,0.8]",
                "--mwx-debug-scene-media-playback-state",
                "1",
            ])

            for invalid in (
                "../cover.png",
                "/tmp/cover.png",
                str(runtime_sample / "cover.png"),
                "cover.webp",
                "missing.png",
            ):
                invalid_failures: list[str] = []
                invalid_command = ["MyWallpaperX"]
                benchmark.append_media_thumbnail_argument(
                    invalid_command,
                    invalid,
                    runtime_sample,
                    invalid_failures,
                    secondary_color=[0.1, 0.2, 0.3],
                    playback_state=1,
                )
                self.assertEqual(
                    invalid_failures,
                    ["invalid isolated media thumbnail path"],
                )
                self.assertEqual(invalid_command, ["MyWallpaperX"])

            missing_path_failures: list[str] = []
            benchmark.append_media_thumbnail_argument(
                [],
                None,
                runtime_sample,
                missing_path_failures,
                high_contrast_color=[0.1, 0.2, 0.3],
            )
            self.assertEqual(
                missing_path_failures,
                ["media thumbnail event requires isolated media thumbnail path"],
            )

            for invalid_color in (
                "0.1 0.2 0.3",
                [0.1, 0.2],
                [0.1, 0.2, 0.3, 0.4],
                [True, 0.2, 0.3],
                [-0.1, 0.2, 0.3],
                [0.1, 1.1, 0.3],
                [0.1, float("nan"), 0.3],
                [0.1, float("inf"), 0.3],
            ):
                invalid_command = ["MyWallpaperX"]
                invalid_failures = []
                benchmark.append_media_thumbnail_argument(
                    invalid_command,
                    "cover.png",
                    runtime_sample,
                    invalid_failures,
                    secondary_color=invalid_color,
                    playback_state=1,
                )
                self.assertEqual(
                    invalid_failures,
                    ["invalid media thumbnail secondary color"],
                )
                self.assertEqual(invalid_command, ["MyWallpaperX"])

            for invalid_state in (-1, 3, 1.0, True, "1"):
                invalid_command = ["MyWallpaperX"]
                invalid_failures = []
                benchmark.append_media_thumbnail_argument(
                    invalid_command,
                    "cover.png",
                    runtime_sample,
                    invalid_failures,
                    secondary_color=[0.1, 0.2, 0.3],
                    playback_state=invalid_state,
                )
                self.assertEqual(
                    invalid_failures,
                    ["invalid media thumbnail playback state"],
                )
                self.assertEqual(invalid_command, ["MyWallpaperX"])


if __name__ == "__main__":
    unittest.main()
