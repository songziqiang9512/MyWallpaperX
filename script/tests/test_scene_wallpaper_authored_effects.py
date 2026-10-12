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


class SceneWallpaperAuthoredEffectsTests(unittest.TestCase):
    def test_authored_workshop_shadow_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWorkshopShadowCount: 1\n"
        count = benchmark.authored_effect_graph_workshop_shadow_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_workshop_shadow_count": 1},
                workshop_shadow_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Workshop Shadow count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_workshop_shadow_count": 0},
                workshop_shadow_count=count,
            ),
        )

    def test_authored_procedural_noise_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphProceduralNoiseCount: 3\n"
        count = benchmark.authored_effect_graph_procedural_noise_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_procedural_noise_count": 3},
                procedural_noise_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Procedural Noise count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_procedural_noise_count": 0},
                procedural_noise_count=count,
            ),
        )

    def test_authored_film_grain_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphFilmGrainCount: 1\n"
        count = benchmark.authored_effect_graph_film_grain_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_film_grain_count": 1},
                film_grain_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Film Grain count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_film_grain_count": 0},
                film_grain_count=count,
            ),
        )

    def test_authored_light_shafts_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphLightShaftsCount: 2\n"
        count = benchmark.authored_effect_graph_light_shafts_count(preview)
        self.assertEqual(count, 2)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_light_shafts_count": 2},
                light_shafts_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Light Shafts count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_light_shafts_count": 0},
                light_shafts_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_light_shafts_count(""))

    def test_authored_shake_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphShakeCount: 3\n"
        count = benchmark.authored_effect_graph_shake_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_shake_count": 3},
                shake_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Shake count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_shake_count": 0},
                shake_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_shake_count(""))

    def test_authored_water_flow_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWaterFlowCount: 2\n"
        count = benchmark.authored_effect_graph_water_flow_count(preview)
        self.assertEqual(count, 2)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_flow_count": 2},
                None,
                water_flow_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Flow count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_flow_count": 0},
                None,
                water_flow_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_water_flow_count(""))

    def test_authored_water_waves_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWaterWavesCount: 4\n"
        count = benchmark.authored_effect_graph_water_waves_count(preview)
        self.assertEqual(count, 4)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_waves_count": 4},
                None,
                water_waves_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Waves count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_waves_count": 0},
                None,
                water_waves_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_water_waves_count(""))

    def test_authored_water_caustics_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWaterCausticsCount: 4\n"
        count = benchmark.authored_effect_graph_water_caustics_count(preview)
        self.assertEqual(count, 4)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_caustics_count": 4},
                None,
                water_caustics_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Caustics count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_caustics_count": 0},
                None,
                water_caustics_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_water_caustics_count(""))

    def test_authored_cursor_ripple_count_is_an_exact_gate(self) -> None:
        preview = (
            "authoredEffectGraphCursorRippleCount: 3\n"
            "authoredEffectGraphCursorRippleIsolatedCount: 0\n"
            "authoredEffectGraphCursorRippleOmittedEffects: \n"
        )
        count = benchmark.authored_effect_graph_cursor_ripple_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_cursor_ripple_isolated_count(preview),
            0,
        )
        self.assertEqual(
            benchmark.authored_effect_graph_cursor_ripple_omitted_effects(preview),
            [],
        )
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_cursor_ripple_count": 3,
                    "expected_authored_effect_graph_cursor_ripple_isolated_count": 0,
                    "expected_authored_effect_graph_cursor_ripple_omitted_effects": [],
                },
                None,
                cursor_ripple_count=count,
                cursor_ripple_isolated_count=0,
                cursor_ripple_omitted_effects=[],
            ),
            [],
        )
        self.assertIn(
            "Cursor Ripple count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_cursor_ripple_count": 0},
                None,
                cursor_ripple_count=count,
            )[0],
        )
        self.assertIn(
            "isolated Cursor Ripple count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_cursor_ripple_isolated_count": 1},
                None,
                cursor_ripple_isolated_count=0,
            )[0],
        )
        self.assertIn(
            "Cursor Ripple omissions mismatch",
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_cursor_ripple_omitted_effects": [
                        "layer=1,omitted=effects/blend/effect.json"
                    ]
                },
                None,
                cursor_ripple_omitted_effects=[],
            )[0],
        )
        self.assertIsNone(benchmark.authored_effect_graph_cursor_ripple_count(""))
        self.assertIsNone(
            benchmark.authored_effect_graph_cursor_ripple_isolated_count("")
        )
        self.assertIsNone(
            benchmark.authored_effect_graph_cursor_ripple_omitted_effects("")
        )

    def test_interactive_effect_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphFoliageSwayCount: 3\n"
            "authoredEffectGraphWaterRippleCount: 2\n"
            "authoredEffectGraphIrisInlineSuffixCount: 0\n"
        )
        self.assertEqual(
            benchmark.authored_effect_graph_foliage_sway_count(preview), 3
        )
        self.assertEqual(
            benchmark.authored_effect_graph_water_ripple_count(preview), 2
        )
        self.assertEqual(
            benchmark.authored_effect_graph_iris_inline_suffix_count(preview), 0
        )
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_foliage_sway_count": 3,
                    "expected_authored_effect_graph_water_ripple_count": 2,
                    "expected_authored_effect_graph_iris_inline_suffix_count": 0,
                },
                None,
                foliage_sway_count=3,
                water_ripple_count=2,
                iris_inline_suffix_count=0,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            {
                "expected_authored_effect_graph_foliage_sway_count": 0,
                "expected_authored_effect_graph_water_ripple_count": 0,
                "expected_authored_effect_graph_iris_inline_suffix_count": 1,
            },
            None,
            foliage_sway_count=3,
            water_ripple_count=2,
            iris_inline_suffix_count=0,
        )
        self.assertIn("authored effect graph Foliage Sway count mismatch", failures)
        self.assertIn("authored effect graph Water Ripple count mismatch", failures)
        self.assertIn(
            "authored effect graph Iris inline suffix count mismatch", failures
        )
        self.assertIsNone(benchmark.authored_effect_graph_foliage_sway_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_water_ripple_count(""))
        self.assertIsNone(
            benchmark.authored_effect_graph_iris_inline_suffix_count("")
        )

    def test_authored_clipping_mask_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphClippingMaskCount: 7\n"
        count = benchmark.authored_effect_graph_clipping_mask_count(preview)
        self.assertEqual(count, 7)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_clipping_mask_count": 7},
                None,
                clipping_mask_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Clipping Mask count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_clipping_mask_count": 0},
                None,
                clipping_mask_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_clipping_mask_count(""))

    def test_authored_blend_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphBlendCount: 1\n"
        count = benchmark.authored_effect_graph_blend_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_blend_count": 1},
                None,
                blend_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Blend count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_blend_count": 0},
                None,
                blend_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_blend_count(""))

    def test_authored_transform_contract_is_an_exact_gate(self) -> None:
        diagnostics = [
            "layer=65,effect=2,pass=0,constant=scale,"
            "reason=unsupported-dynamic-binding-static-fallback",
            "layer=161,effect=2,pass=0,constant=scale,"
            "reason=unsupported-dynamic-binding-static-fallback",
        ]
        preview = (
            "authoredEffectGraphTransformCount: 2\n"
            "authoredEffectGraphTransformStaticFallbackCount: 2\n"
            "authoredEffectGraphTransformStaticFallbackDiagnostics: "
            + ";".join(diagnostics)
            + "\n"
        )
        count = benchmark.authored_effect_graph_transform_count(preview)
        fallback_count = (
            benchmark.authored_effect_graph_transform_static_fallback_count(preview)
        )
        parsed_diagnostics = (
            benchmark.authored_effect_graph_transform_static_fallback_diagnostics(
                preview
            )
        )
        self.assertEqual(count, 2)
        self.assertEqual(fallback_count, 2)
        self.assertEqual(parsed_diagnostics, diagnostics)
        sample = {
            "expected_authored_effect_graph_transform_count": 2,
            "expected_authored_effect_graph_transform_static_fallback_count": 2,
            "expected_authored_effect_graph_transform_static_fallback_diagnostics": (
                diagnostics
            ),
        }
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                sample,
                None,
                transform_count=count,
                transform_static_fallback_count=fallback_count,
                transform_static_fallback_diagnostics=parsed_diagnostics,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            sample,
            None,
            transform_count=1,
            transform_static_fallback_count=1,
            transform_static_fallback_diagnostics=None,
        )
        self.assertIn(
            "authored effect graph Transform count mismatch",
            failures,
        )
        self.assertIn(
            "authored effect graph Transform static fallback count mismatch",
            failures,
        )
        self.assertIn(
            "authored effect graph Transform static fallback diagnostics mismatch",
            failures,
        )
        self.assertIsNone(benchmark.authored_effect_graph_transform_count(""))
        self.assertIsNone(
            benchmark.authored_effect_graph_transform_static_fallback_count("")
        )
        self.assertIsNone(
            benchmark.authored_effect_graph_transform_static_fallback_diagnostics("")
        )
        self.assertEqual(
            benchmark.authored_effect_graph_transform_static_fallback_diagnostics(
                "authoredEffectGraphTransformStaticFallbackDiagnostics: \n"
            ),
            [],
        )

    def test_full_matrix_generator_preserves_exact_authored_backend_counts(self) -> None:
        evidence = {
            metric: 0 for metric in matrix_generator.RUNTIME_EVIDENCE_METRICS
        }
        evidence.update({
            "shader_contract_aggregate_sha256": "a" * 64,
            "effect_graph_sha256": "b" * 64,
            "stock_opacity_single_effect_candidate_layer_ids": [],
        })
        runtime: defaultdict[str, object] = defaultdict(int)
        runtime["runtime_evidence"] = evidence
        expected_counts = {
            "authored_effect_graph_color_key_count": 1,
            "authored_effect_graph_procedural_noise_count": 3,
            "authored_effect_graph_film_grain_count": 4,
            "authored_effect_graph_light_shafts_count": 5,
            "authored_effect_graph_blend_count": 6,
            "authored_effect_graph_tint_count": 7,
            "authored_effect_graph_pulse_count": 8,
            "authored_effect_graph_godrays_count": 9,
            "authored_effect_graph_transform_count": 10,
            "authored_effect_graph_transform_static_fallback_count": 2,
            "authored_effect_graph_transform_static_fallback_diagnostics": [
                "fixture"
            ],
            "authored_effect_graph_authored_shader_count": 11,
            "authored_effect_graph_scroll_count": 12,
            "authored_effect_graph_iris_inline_suffix_count": 0,
        }
        runtime.update(expected_counts)
        sample = matrix_generator.matrix_sample(
            {
                "id": "fixture",
                "title": "Fixture",
                "package_file": "scene.pkg",
                "hashes": {"project_sha256": "c" * 64, "package_sha256": "d" * 64},
                "runtime": runtime,
            },
            {"capabilities": ["fixture"]},
        )
        for metric, expected in expected_counts.items():
            self.assertEqual(sample[f"expected_{metric}"], expected)

    def test_tracked_full_matrix_retires_legacy_effect_counts_only_with_owner_transfer(self) -> None:
        matrix = json.loads(
            (SCRIPT_DIR / "scene_wallpaper_full_sample_matrix.json").read_text(
                encoding="utf-8"
            )
        )
        samples = matrix["samples"]
        self.assertEqual(len(samples), 45)
        owner_transfer_keys = {
            "expected_authored_effect_graph_opacity_count",
            "expected_authored_effect_graph_opacity_layer_ids",
            "expected_authored_effect_graph_color_key_count",
            "expected_authored_effect_graph_workshop_shadow_count",
            "expected_authored_effect_graph_procedural_noise_count",
            "expected_authored_effect_graph_film_grain_count",
            "expected_authored_effect_graph_transform_count",
            "expected_authored_effect_graph_transform_static_fallback_count",
            "expected_authored_effect_graph_transform_static_fallback_diagnostics",
            "expected_authored_effect_graph_light_shafts_count",
            "expected_authored_effect_graph_shake_count",
            "expected_authored_effect_graph_water_flow_count",
            "expected_authored_effect_graph_water_waves_count",
            "expected_authored_effect_graph_blend_count",
            "expected_authored_effect_graph_authored_shader_count",
            "expected_authored_effect_graph_foliage_sway_count",
            "expected_authored_effect_graph_water_ripple_count",
        }
        all_legacy_keys = {
            expectation.matrix_key
            for expectation in benchmark.AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        }
        for sample in samples:
            with self.subTest(sample_id=sample["id"]):
                present = owner_transfer_keys.intersection(sample)
                self.assertIn(len(present), (0, len(owner_transfer_keys)))
                if not present:
                    self.assertFalse(all_legacy_keys.intersection(sample))
                    replacement = sample.get(
                        "expected_resolved_material_graph_succeeded_layer_ids"
                    )
                    self.assertIsInstance(replacement, list)
                    self.assertTrue(replacement)

    def test_authored_shader_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphAuthoredShaderCount: 1\n"
        count = benchmark.authored_effect_graph_authored_shader_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_authored_shader_count": 1},
                None,
                authored_shader_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph authored shader count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_authored_shader_count": 0},
                None,
                authored_shader_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_authored_shader_count(""))

    def test_scroll_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphScrollCount: 30\n"
        count = benchmark.authored_effect_graph_scroll_count(preview)
        self.assertEqual(count, 30)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_scroll_count": 30},
                None,
                scroll_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Scroll count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_scroll_count": 0},
                None,
                scroll_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_scroll_count(""))

    def test_authored_tint_pulse_and_godrays_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphTintCount: 24\n"
            "authoredEffectGraphPulseCount: 1\n"
            "authoredEffectGraphGodraysCount: 12\n"
        )
        tint_count = benchmark.authored_effect_graph_tint_count(preview)
        pulse_count = benchmark.authored_effect_graph_pulse_count(preview)
        godrays_count = benchmark.authored_effect_graph_godrays_count(preview)
        self.assertEqual(tint_count, 24)
        self.assertEqual(pulse_count, 1)
        self.assertEqual(godrays_count, 12)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_tint_count": 24,
                    "expected_authored_effect_graph_pulse_count": 1,
                    "expected_authored_effect_graph_godrays_count": 12,
                },
                None,
                tint_count=tint_count,
                pulse_count=pulse_count,
                godrays_count=godrays_count,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            {
                "expected_authored_effect_graph_tint_count": 0,
                "expected_authored_effect_graph_pulse_count": 0,
                "expected_authored_effect_graph_godrays_count": 0,
            },
            None,
            tint_count=tint_count,
            pulse_count=pulse_count,
            godrays_count=godrays_count,
        )
        self.assertIn("authored effect graph Tint count mismatch", failures)
        self.assertIn("authored effect graph Pulse count mismatch", failures)
        self.assertIn("authored effect graph Godrays count mismatch", failures)
        self.assertIsNone(benchmark.authored_effect_graph_tint_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_pulse_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_godrays_count(""))


if __name__ == "__main__":
    unittest.main()
