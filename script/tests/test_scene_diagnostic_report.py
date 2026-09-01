#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_diagnostic_report as diagnostic


def resolved_execution(
    layer_id: int,
    *,
    compositor: bool = True,
    next_frame: bool = True,
    local_fallback_reason: str | None = None,
) -> dict[str, object]:
    compositor_ids = [layer_id] if compositor else []
    next_frame_ids = [layer_id] if next_frame else []
    local_fallbacks = []
    if local_fallback_reason is not None:
        local_fallbacks.append({
            "layer_id": layer_id,
            "reason": local_fallback_reason,
        })
    return {
        "has_evidence": True,
        "capability": {
            "has_evidence": True,
            "accepted_layer_ids": [layer_id],
        },
        "executor": {
            "has_evidence": True,
            "failure_count": 0,
            "local_fallbacks": local_fallbacks,
        },
        "graph_observations": {
            "has_evidence": True,
            "successful_gpu_completed_layer_ids": [layer_id],
            "compositor_consumed_layer_ids": compositor_ids,
            "next_frame_layer_ids": next_frame_ids,
        },
        "layer_routes": {
            "has_evidence": True,
            "accepted_layer_ids": [layer_id],
            "missing_layer_ids": [],
            "missing_gpu_completed_layer_ids": [],
            "missing_compositor_consumed_layer_ids": (
                [] if compositor else [layer_id]
            ),
            "missing_next_frame_layer_ids": (
                [] if next_frame else [layer_id]
            ),
        },
        "validation_failures": [],
    }


def sample(
    sample_id: str,
    *,
    layer_id: int = 1,
    passed: bool = True,
    failures: list[str] | None = None,
    timed_out: bool = False,
    exit_code: int | None = 0,
    resolved: dict[str, object] | None = None,
    admission_records: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    return {
        "id": sample_id,
        "title": f"Fixture {sample_id}",
        "passed": passed,
        "failures": failures or [],
        "timed_out": timed_out,
        "exit_code": exit_code,
        "hashes": {"package": "sample-specific-hash"},
        "runtime_sample": f"/private/tmp/{sample_id}/scene.pkg",
        "evidence": {
            "ready_non_black": True,
            "after_non_black": True,
            "flat_border_ratio": {"ready": 0.1, "after": 0.1},
            "preview_visual": {
                "status": "available",
                "metrics": {"spatial_color_similarity": 0.99},
            },
        },
        "runtime": {
            "surfaces": 1,
            "texture_candidates": 1,
            "loaded_textures": 1,
            "text_candidates": 0,
            "loaded_textures_text": 0,
            "solid_candidates": 0,
            "loaded_solid_layers": 0,
            "particle_candidates": 0,
            "loaded_particle_layers": 0,
            "skipped_unsupported_composite_count": 0,
            "performance": {"frames_completed": 2},
            "effect_stage_admission": {
                "has_evidence": admission_records is not None,
                "records": admission_records or [],
                "validation_failures": [],
            },
            "effect_execution": {
                "has_evidence": True,
                "cpu_invocations": [],
                "route_operations": [],
                "frames": [{"frame_id": 1, "status": "completed"}],
                "validation_failures": [],
            },
            "resolved_material_graph_execution": (
                resolved if resolved is not None
                else resolved_execution(layer_id)
            ),
            "named_target_capture_failed_layer_ids": [],
            "named_target_binding_failed_layer_ids": [],
            "visible_graph_output_publication_failed_layer_ids": [],
            "named_graph_output_publication_failed_layer_ids": [],
        },
    }


def report(*samples: dict[str, object]) -> dict[str, object]:
    return {
        "schema_version": 1,
        "matrix": "synthetic-matrix.json",
        "samples": list(samples),
    }


class SceneDiagnosticReportTests(unittest.TestCase):
    def test_process_crash_and_timeout_are_the_first_breakpoint(self) -> None:
        timeout = sample("timeout", timed_out=True, exit_code=-15)
        crash = sample("crash", exit_code=-11)

        result = diagnostic.normalize_reports([report(timeout, crash)])
        by_id = {item["sampleId"]: item for item in result["samples"]}

        self.assertEqual(
            by_id["timeout"]["firstBreakpoint"]["reasonCode"],
            "process-timeout",
        )
        self.assertEqual(
            by_id["crash"]["firstBreakpoint"]["reasonCode"],
            "process-exit-nonzero",
        )
        self.assertEqual(by_id["timeout"]["basicDisplayStatus"], "blocked")

    def test_missing_terminal_compositor_precedes_missing_next_frame(self) -> None:
        blocked = sample(
            "no-compositor",
            layer_id=7,
            resolved=resolved_execution(7, compositor=False, next_frame=False),
        )

        result = diagnostic.normalize_reports([report(blocked)])
        observation = result["samples"][0]

        self.assertEqual(
            observation["firstBreakpoint"]["reasonCode"],
            "terminal-compositor-missing",
        )
        self.assertEqual(
            observation["secondaryEvents"][0]["reasonCode"],
            "next-frame-missing",
        )
        self.assertEqual(observation["basicDisplayStatus"], "blocked")

    def test_incomplete_drawable_census_is_a_pre_effect_cohort_lead(self) -> None:
        missing = sample(
            "missing-base",
            layer_id=7,
            admission_records=[{
                "layer_id": 7,
                "effect_index": 0,
                "activity": "active",
                "admission": "not-admitted",
                "coverage": "rejected-unsupported",
                "profile": "authored-shader",
                "reason": "shader-unsupported",
            }],
        )
        missing["runtime"]["texture_candidates"] = 3
        missing["runtime"]["loaded_textures"] = 2

        result = diagnostic.normalize_reports([report(missing)])
        observation = result["samples"][0]

        self.assertEqual(
            observation["firstBreakpoint"]["reasonCode"],
            "base-image-texture-load-incomplete",
        )
        self.assertEqual(
            observation["secondaryEvents"][0]["reasonCode"],
            "shader-unsupported",
        )
        self.assertEqual(observation["basicDisplayStatus"], "degraded")

    def test_flat_output_diverging_from_preview_is_a_terminal_blocker(self) -> None:
        flat = sample("flat-output")
        flat["evidence"]["flat_border_ratio"] = {
            "ready": 1.0,
            "after": 1.0,
        }
        flat["evidence"]["preview_visual"]["metrics"][
            "spatial_color_similarity"
        ] = 0.2

        result = diagnostic.normalize_reports([report(flat)])
        observation = result["samples"][0]

        self.assertEqual(
            observation["firstBreakpoint"]["reasonCode"],
            "terminal-output-flat-preview-divergence",
        )
        self.assertEqual(observation["basicDisplayStatus"], "blocked")
        self.assertEqual(
            observation["evidenceSummary"]["afterFlatBorderRatio"], 1.0
        )

    def test_each_drawable_family_reports_an_incomplete_load(self) -> None:
        missing = sample("missing-drawables")
        missing["runtime"].update({
            "text_candidates": 2,
            "loaded_textures_text": 1,
            "solid_candidates": 2,
            "loaded_solid_layers": 1,
            "particle_candidates": 2,
            "loaded_particle_layers": 1,
            "skipped_unsupported_composite_count": 1,
        })

        result = diagnostic.normalize_reports([report(missing)])
        reasons = {
            result["samples"][0]["firstBreakpoint"]["reasonCode"],
            *(
                event["reasonCode"]
                for event in result["samples"][0]["secondaryEvents"]
            ),
        }

        self.assertEqual(reasons, {
            "text-texture-load-incomplete",
            "solid-texture-load-incomplete",
            "particle-layer-load-incomplete",
            "authored-composite-skipped-unsupported",
        })

    def test_effect_local_fallback_clusters_without_sample_or_layer_identity(self) -> None:
        fixtures = []
        for sample_id, layer_id in (("fallback-a", 4), ("fallback-b", 91)):
            fixtures.append(sample(
                sample_id,
                layer_id=layer_id,
                admission_records=[{
                    "layer_id": layer_id,
                    "effect_index": 2,
                    "descriptor_id": f"{sample_id}#effect#2",
                    "definition_path": f"effects/{sample_id}/effect.json",
                    "activity": "active",
                    "admission": "admitted-fallback",
                    "coverage": "complete",
                    "backend": "resolved-material",
                    "profile": "authored-shader",
                    "reason": "shader-compile-failed",
                }],
            ))

        result = diagnostic.normalize_reports([report(*fixtures)])
        clusters = [
            cluster for cluster in result["clusters"]
            if cluster["key"]["reasonCode"] == "shader-compile-failed"
        ]

        self.assertEqual(len(clusters), 1)
        cluster = clusters[0]
        self.assertEqual(cluster["affectedSampleCount"], 2)
        self.assertEqual(cluster["affectedUnitCount"], 2)
        self.assertNotIn("fallback-a", json.dumps(cluster["key"]))
        self.assertNotIn("4", json.dumps(cluster["key"]))
        self.assertNotIn("effect.json", json.dumps(cluster["key"]))
        self.assertNotIn("sample-specific-hash", json.dumps(cluster["key"]))
        self.assertEqual(
            cluster["fallbackTerminalCompositor"]["preservedCount"], 2
        )
        for observation in result["samples"]:
            self.assertTrue(
                observation["firstBreakpoint"][
                    "fallbackPreservedTerminalCompositor"
                ]
            )
            self.assertEqual(observation["basicDisplayStatus"], "degraded")

    def test_encoded_layer_source_passthrough_is_explicit_degraded_output(self) -> None:
        fixture = sample("source-passthrough", layer_id=42)
        fixture["runtime"]["effect_execution"]["route_operations"] = [{
            "frame_id": 0,
            "layer_id": 42,
            "operation": "degraded-layer-source-passthrough",
            "outcome": "encoded",
            "reason": None,
        }]

        result = diagnostic.normalize_reports([report(fixture)])
        event = result["samples"][0]["firstBreakpoint"]

        self.assertEqual(result["samples"][0]["basicDisplayStatus"], "degraded")
        self.assertEqual(
            event["reasonCode"], "degraded-layer-source-passthrough"
        )
        self.assertTrue(event["fallbackPreservedTerminalCompositor"])

    def test_scene_script_failures_cluster_by_typed_target_not_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixtures = []
            for sample_id, layer_id in (("script-a", 214), ("script-b", 991)):
                app_log = Path(directory) / f"{sample_id}.log"
                app_log.write_text(
                    "MWX SceneScript VM: target=layer(layerID: "
                    f"{layer_id}, field: MyWallpaperX.SceneDynamicLayerField.origin) "
                    "failure=badReturn(\"non-finite Vec3 output\") "
                    "code=bad-return fallback=current-frame-lower-priority\n",
                    encoding="utf-8",
                )
                fixture = sample(sample_id, layer_id=layer_id)
                fixture["evidence"]["app_log"] = str(app_log)
                fixtures.append(fixture)

            result = diagnostic.normalize_reports([report(*fixtures)])

        clusters = [
            cluster for cluster in result["clusters"]
            if cluster["key"]["reasonCode"] == "scene-script-bad-return"
        ]
        self.assertEqual(len(clusters), 1)
        self.assertEqual(clusters[0]["affectedSampleCount"], 2)
        self.assertEqual(
            clusters[0]["key"]["capabilityProfileOrAuthoredShape"],
            "target:layer:origin",
        )
        self.assertNotIn("214", json.dumps(clusters[0]["key"]))
        self.assertEqual(
            result["samples"][0]["firstBreakpoint"]["stage"],
            "script-execution",
        )

    def test_scene_script_exception_classes_remain_separate_contracts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixtures = []
            for sample_id, failure in (
                ("missing-layer", "RangeError: getLayer target does not exist"),
                ("missing-value", "TypeError: cannot read property x of undefined"),
            ):
                app_log = Path(directory) / f"{sample_id}.log"
                app_log.write_text(
                    "MWX SceneScript VM: target=layer(layerID: 7, field: "
                    "MyWallpaperX.SceneDynamicLayerField.origin) "
                    f'failure=exception("{failure}") code=exception '
                    "fallback=current-frame-lower-priority\n",
                    encoding="utf-8",
                )
                fixture = sample(sample_id, layer_id=7)
                fixture["evidence"]["app_log"] = str(app_log)
                fixtures.append(fixture)

            result = diagnostic.normalize_reports([report(*fixtures)])

        reasons = {
            cluster["key"]["reasonCode"]
            for cluster in result["clusters"]
            if cluster["key"]["stage"] == "script-execution"
        }
        self.assertEqual(reasons, {
            "scene-script-exception-range-error",
            "scene-script-exception-type-error",
        })

    def test_unadmitted_effects_cluster_by_family_without_path_identity(self) -> None:
        fixtures = []
        for sample_id, layer_id, path in (
            ("xray-a", 4, "effects/xray/effect.json"),
            ("xray-b", 91, "EFFECTS\\XRAY\\effect.json"),
            ("blend", 22, "effects/blend/effect.json"),
        ):
            fixtures.append(sample(
                sample_id,
                layer_id=layer_id,
                admission_records=[{
                    "layer_id": layer_id,
                    "effect_index": 0,
                    "descriptor_id": f"{sample_id}#effect#0",
                    "definition_path": path,
                    "activity": "active",
                    "admission": "not-admitted",
                    "coverage": "rejected-capability",
                    "backend": "-",
                    "profile": "-",
                    "reason": "unified-capability-unavailable",
                }],
            ))

        result = diagnostic.normalize_reports([report(*fixtures)])
        clusters = [
            cluster for cluster in result["clusters"]
            if cluster["key"]["reasonCode"] == "unified-capability-unavailable"
        ]

        self.assertEqual(len(clusters), 2)
        by_shape = {
            cluster["key"]["capabilityProfileOrAuthoredShape"]: cluster
            for cluster in clusters
        }
        self.assertEqual(
            by_shape["backend:effect-family:xray"]["affectedSampleCount"], 2
        )
        self.assertEqual(
            by_shape["backend:effect-family:blend"]["affectedSampleCount"], 1
        )
        self.assertNotIn("effect.json", json.dumps(clusters))

    def test_same_stage_clusters_rank_largest_shared_cohort_first(self) -> None:
        fixtures = []
        for sample_id, layer_id, path in (
            ("xray-a", 4, "effects/xray/effect.json"),
            ("xray-b", 91, "effects/xray/effect.json"),
            ("blend", 22, "effects/blend/effect.json"),
        ):
            fixtures.append(sample(
                sample_id,
                layer_id=layer_id,
                admission_records=[{
                    "layer_id": layer_id,
                    "effect_index": 0,
                    "definition_path": path,
                    "activity": "active",
                    "admission": "not-admitted",
                    "coverage": "rejected-capability",
                    "reason": "unified-capability-unavailable",
                }],
            ))

        result = diagnostic.normalize_reports([report(*fixtures)])
        clusters = [
            cluster for cluster in result["clusters"]
            if cluster["key"]["stage"] == "effect-admission"
        ]

        self.assertEqual(clusters[0]["affectedSampleCount"], 2)
        self.assertEqual(
            clusters[0]["key"]["capabilityProfileOrAuthoredShape"],
            "backend:effect-family:xray",
        )
        self.assertEqual(clusters[1]["affectedSampleCount"], 1)

    def test_matrix_only_stale_failure_is_not_a_basic_display_event(self) -> None:
        stale = sample(
            "matrix-stale",
            passed=False,
            failures=[
                "effect count below minimum",
                "stale matrix expectation",
            ],
        )

        result = diagnostic.normalize_reports([report(stale)])
        observation = result["samples"][0]

        self.assertIsNone(observation["firstBreakpoint"])
        self.assertEqual(observation["secondaryEvents"], [])
        self.assertEqual(
            observation["basicDisplayStatus"],
            "terminal-chain-complete",
        )
        self.assertEqual(observation["benchmarkResultIgnored"]["failureCount"], 2)

    def test_named_target_failure_uses_typed_owner_and_stage(self) -> None:
        fixture = sample("named-target", layer_id=12)
        fixture["runtime"]["named_target_binding_failed_layer_ids"] = [12]

        result = diagnostic.normalize_reports([report(fixture)])
        event = result["samples"][0]["firstBreakpoint"]

        self.assertEqual(event["stage"], "named-target-binding")
        self.assertEqual(event["owner"], "LayerDependencies")
        self.assertEqual(event["reasonCode"], "named-target-binding-failed")
        self.assertEqual(event["unit"]["layerId"], 12)

    def test_healthy_sample_has_no_diagnostic_and_no_visual_correctness_claim(self) -> None:
        result = diagnostic.normalize_reports([report(sample("healthy"))])

        self.assertEqual(result["samples"][0]["firstBreakpoint"], None)
        self.assertEqual(result["clusters"], [])
        self.assertEqual(
            result["claimBoundary"],
            "runtime-and-output-diagnostics-only-not-visual-correctness",
        )

    def test_cli_emits_stable_sorted_json(self) -> None:
        payload = report(sample("healthy"))
        with tempfile.TemporaryDirectory() as directory:
            report_path = Path(directory) / "report.json"
            report_path.write_text(json.dumps(payload), encoding="utf-8")
            command = [
                sys.executable,
                str(SCRIPT_DIR / "scene_diagnostic_report.py"),
                str(report_path),
            ]
            first = subprocess.run(command, capture_output=True, text=True)
            second = subprocess.run(command, capture_output=True, text=True)

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        parsed = json.loads(first.stdout)
        self.assertEqual(parsed["sampleCount"], 1)
        self.assertTrue(first.stdout.endswith("\n"))


if __name__ == "__main__":
    unittest.main()
