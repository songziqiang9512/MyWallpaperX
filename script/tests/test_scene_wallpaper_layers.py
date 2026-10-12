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


class SceneWallpaperLayersTests(unittest.TestCase):
    def test_solid_runtime_fixture_metrics_and_optional_gates(self) -> None:
        preview_log = """Scene preview texture load report
solidLayerCount: 3
layer 13 "Backdrop": OK procedural solid tint=(1.00000, 1.00000, 1.00000)
layer 311 "Accent": OK procedural solid tint=(0.20000, 0.40000, 0.60000)
"""
        metrics = benchmark.solid_runtime_metrics(preview_log)
        self.assertTrue(metrics["has_count_evidence"])
        self.assertEqual(metrics["loaded"], 2)
        self.assertEqual(metrics["candidates"], 3)
        self.assertEqual(metrics["loaded_ratio"], 2 / 3)
        self.assertEqual(metrics["loaded_layer_ids"], [13, 311])
        self.assertEqual(
            benchmark.solid_runtime_failures({
                "expected_solid_candidates": 3,
                "required_solid_loaded_layer_ids": [13, 311],
            }, metrics),
            [],
        )
        self.assertEqual(
            benchmark.solid_runtime_failures({
                "expected_solid_candidates": 4,
                "required_solid_loaded_layer_ids": [551],
            }, metrics),
            [
                "solid layer candidate count mismatch",
                "solid layer 551 should be loaded",
            ],
        )
        self.assertEqual(
            benchmark.solid_runtime_failures(
                {"expected_solid_candidates": 0},
                benchmark.solid_runtime_metrics("loaded: 2 / 2\n"),
            ),
            ["solid layer count evidence missing"],
        )

    def test_puppet_animation_runtime_metrics_and_exact_gates(self) -> None:
        preview_log = """Scene preview texture load report
layer 21 "Body": OK 1920x1080 puppet world geometry OK MDLV0023 mode=layered ids=275,280,282 clips=3 verts=100 tris=50
layer 44 "Arm": OK 512x512 puppet world geometry OK MDLV0023 mode=layered ids=271,356 clips=2 verts=80 tris=40
layer 157 "Tail": OK 1024x1024 puppet world geometry OK MDLV0023 mode=single-absolute ids=174 clips=1 verts=262 tris=463
"""
        metrics = benchmark.puppet_animation_runtime_metrics(preview_log)
        self.assertEqual(metrics["layer_ids"], [21, 44, 157])
        self.assertEqual(metrics["layered_layer_ids"], [21, 44])
        self.assertEqual(metrics["clip_count"], 6)
        self.assertEqual(metrics["entries"][0], {
            "layer_id": 21,
            "mode": "layered",
            "animation_ids": [275, 280, 282],
            "clip_count": 3,
        })
        sample = {
            "expected_puppet_animation_layer_ids": [157, 44, 21],
            "expected_puppet_layered_layer_ids": [44, 21],
            "expected_puppet_animation_clip_count": 6,
        }
        self.assertEqual(
            benchmark.puppet_animation_runtime_failures(sample, metrics),
            [],
        )
        self.assertEqual(
            benchmark.puppet_animation_runtime_failures(
                {
                    "expected_puppet_animation_layer_ids": [21, 157],
                    "expected_puppet_layered_layer_ids": [21],
                    "expected_puppet_animation_clip_count": 5,
                },
                metrics,
            ),
            [
                "puppet animation layer IDs mismatch",
                "puppet layered layer IDs mismatch",
                "puppet animation clip count mismatch",
            ],
        )

    def test_startup_budget_requires_valid_timing_and_rejects_slow_ready(self) -> None:
        expected = {"maximum_startup_ready_ms": 5000}
        self.assertEqual(benchmark.startup_runtime_failures(expected, 5000), [])
        self.assertEqual(benchmark.startup_runtime_failures(expected, 5001),
                         ["startup ready elapsed exceeds maximum"])
        self.assertEqual(benchmark.startup_runtime_failures({}, 25000), [])
        for invalid in (None, -1, float("nan"), float("inf")):
            self.assertTrue(benchmark.startup_runtime_failures(expected, invalid))
        for invalid in (0, -1, True, "fast", float("nan"), float("inf")):
            self.assertEqual(benchmark.startup_runtime_failures(
                {"maximum_startup_ready_ms": invalid}, 100), ["invalid startup ready budget"])

    def test_particle_nonempty_evidence_is_separate_from_resource_loading(self) -> None:
        legacy = benchmark.particle_runtime_metrics("particle loaded: 2 / 2\n")
        self.assertIsNone(legacy["committed_nonempty_layer_ids"])
        expectation = {"required_particle_committed_nonempty_layer_ids": [200]}
        self.assertIn("particle committed nonempty evidence missing",
                      benchmark.particle_runtime_failures(expectation, legacy))
        preview = ("particle loaded: 2 / 2\nparticle sticky loaded: 2 / 2\n"
                   "particle current nonempty: layers=[200]\n"
                   "particle committed nonempty: layers=[]\n")
        pending = benchmark.particle_runtime_metrics(preview)
        self.assertEqual(pending["current_nonempty_layer_ids"], [200])
        self.assertEqual(pending["committed_nonempty_layer_ids"], [])
        self.assertIn("particle layer 200 should produce a committed nonempty batch",
                      benchmark.particle_runtime_failures(expectation, pending))
        dormant = benchmark.particle_runtime_metrics(preview +
            "particle current nonempty: layers=[]\nparticle committed nonempty: layers=[200]\n")
        self.assertEqual(dormant["current_nonempty_layer_ids"], [])
        self.assertEqual(dormant["committed_nonempty_layer_ids"], [200])
        self.assertEqual(benchmark.particle_runtime_failures(expectation, dormant), [])
        self.assertTrue(benchmark.particle_runtime_failures(
            {"required_particle_committed_nonempty_layer_ids": [201]}, dormant))

    def test_particle_completeness_requires_current_load_evidence_without_sample_overrides(self) -> None:
        cases = [
            ("", ["particle load evidence missing"]),
            ("particle runtime: pipeline unavailable\n", ["particle load evidence missing"]),
            ("particle loaded: 0 / 1\n", ["particle loading incomplete"]),
            ("particle loaded: 3 / 4\n", ["particle loading incomplete"]),
            ("particle loaded: 0 / 0\n", []),
            ("particle loaded: 1 / 1\nparticle initial live: 0\n"
             "particle committed nonempty: layers=[]\n", []),
            ("particle authored: 2\nparticle visible: 1\n"
             "particle skipped hidden: 1\nparticle skipped transparent: 1\n"
             "particle loaded: 0 / 0\n", []),
            ("particle loaded: 1 / 1\nparticle loaded: 0 / 1\n"
             "particle sticky loaded: 1 / 1\n", ["particle loading incomplete"]),
            ("particle loaded: 0 / 1\nparticle loaded: 1 / 1\n", []),
        ]
        for preview, expected in cases:
            with self.subTest(preview=preview):
                metrics = benchmark.particle_runtime_metrics(preview)
                self.assertEqual(benchmark.particle_runtime_failures({}, metrics), expected)
                self.assertEqual(benchmark.particle_runtime_failures(
                    {"minimum_particle_loaded": 0}, metrics), expected)

    def test_particle_runtime_fixture_metrics_and_optional_gates(self) -> None:
        preview_log = """Scene preview texture load report
loaded: 20 / 24
text loaded: 10 / 10
particle loaded: 3 / 4
particle refract loaded: 2
particle initial live: 96
particle authored: 5
particle visible: 3
particle layer 200 "Snow": OK 64x64 blend=additive initial=32 perspective=false
particle layer 201 "Bird": OK 64x64 blend=translucent initial=64 perspective=true
particle skipped hidden: 2
particle skipped transparent: 1
"""
        metrics = benchmark.particle_runtime_metrics(preview_log)
        self.assertTrue(metrics["has_load_evidence"])
        self.assertTrue(metrics["has_initial_live_evidence"])
        self.assertEqual(metrics["loaded"], 3)
        self.assertEqual(metrics["candidates"], 4)
        self.assertEqual(metrics["loaded_ratio"], 0.75)
        self.assertTrue(metrics["has_refract_evidence"])
        self.assertEqual(metrics["refract_loaded"], 2)
        self.assertEqual(metrics["initial_live"], 96)
        self.assertEqual(metrics["authored"], 5)
        self.assertEqual(metrics["visible"], 3)
        self.assertEqual(metrics["skipped_hidden"], 2)
        self.assertEqual(metrics["skipped_transparent"], 1)
        self.assertTrue(metrics["has_transparent_evidence"])
        self.assertEqual(metrics["loaded_layer_ids"], [200, 201])
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "minimum_particle_loaded": 3,
                "expected_particle_candidates": 4,
                "minimum_particle_initial_live": 96,
                "expected_particle_authored": 5,
                "expected_particle_visible": 3,
                "expected_particle_skipped_hidden": 2,
                "expected_particle_skipped_transparent": 1,
                "expected_particle_refract_loaded": 2,
                "required_particle_loaded_layer_ids": [200, 201],
            }, metrics),
            ["particle loading incomplete"],
        )
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "minimum_particle_loaded": 4,
                "expected_particle_candidates": 5,
                "minimum_particle_initial_live": 97,
                "expected_particle_authored": 4,
                "expected_particle_visible": 4,
                "expected_particle_skipped_hidden": 1,
                "expected_particle_refract_loaded": 3,
                "required_particle_loaded_layer_ids": [202],
            }, metrics),
            [
                "particle loading incomplete",
                "particle loaded count below minimum",
                "particle candidate count mismatch",
                "particle initial live count below minimum",
                "particle authored count mismatch",
                "particle visible count mismatch",
                "particle skipped_hidden count mismatch",
                "particle layer 202 should be loaded",
                "particle refract loaded count mismatch",
            ],
        )

    def test_audio_scaled_value_evidence_joins_typed_targets_and_live_batches(self) -> None:
        preview = (
            "scene audio scaled value: schema=bounded-audio-scaled-value-v1 "
            "bindings=3 rejectedParticleLayerIDs=[1991, 85705] "
            "rejectedScaleLayerIDs=[9002] resolution=16\n"
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "scene-audio-scaled-value-evidence.json"
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "frameIndex": 420,
                "audioGeneration": 7,
                "audioWasSilent": True,
                "bindings": [
                    {"layerID": 31057, "target": "particle.rate",
                     "effectiveValue": [1.6],
                     "liveParticleCount": 502},
                    {"layerID": 1314, "target": "layer.scale",
                     "effectiveValue": [0.8, 0.8, 0.8],
                     "liveParticleCount": None},
                    {"layerID": 5944, "target": "particle.rate",
                     "effectiveValue": [0.8],
                     "liveParticleCount": 239},
                ],
            }), encoding="utf-8")
            metrics = benchmark.audio_scaled_value_evidence_metrics(preview, path)
        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["expected_binding_count"], 3)
        self.assertEqual(metrics["rejected_particle_layer_ids"], [1991, 85705])
        self.assertEqual(metrics["rejected_scale_layer_ids"], [9002])
        self.assertEqual(metrics["frame_index"], 420)
        self.assertTrue(metrics["audio_was_silent"])
        self.assertEqual(
            metrics["bindings"],
            [
                {"layer_id": 1314, "target": "layer.scale",
                 "effective_value": [0.8, 0.8, 0.8],
                 "live_particle_count": None},
                {"layer_id": 5944, "target": "particle.rate",
                 "effective_value": [0.8],
                 "live_particle_count": 239},
                {"layer_id": 31057, "target": "particle.rate",
                 "effective_value": [1.6],
                 "live_particle_count": 502},
            ],
        )
        self.assertEqual(metrics["failures"], [])

        missing = benchmark.audio_scaled_value_evidence_metrics(
            preview, Path("/definitely/missing/audio-scaled-value.json")
        )
        self.assertEqual(
            missing["failures"], ["audio scaled value evidence missing"]
        )


if __name__ == "__main__":
    unittest.main()
