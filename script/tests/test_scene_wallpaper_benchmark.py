#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
DEBUG_RUNNER_SOURCE = (
    SCRIPT_DIR.parent / "MyWallpaperX/App/DebugScenePlaybackRunner.swift"
)
FULL_SAMPLE_MATRIX_PATH = SCRIPT_DIR / "scene_wallpaper_full_sample_matrix.json"

import scene_wallpaper_benchmark as benchmark
import scene_preview_visual_evidence as visual


def shader_stage(identity: str, kind: str, source: str) -> dict[str, object]:
    suffix = "vert" if kind == "vertex" else "frag"
    return {
        "kind": kind,
        "relativePath": f"shaders/{identity}.{suffix}",
        "source": source,
        "rawSHA256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "includes": [],
        "annotations": [],
        "declarations": [],
    }


def runtime_evidence(runtime_input: dict[str, object]) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "sourceEntryPath": "scene.json",
        "runtimeInput": runtime_input,
    }


class SceneWallpaperBenchmarkTests(unittest.TestCase):
    def test_project_preview_path_stays_inside_isolated_sample(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-path-") as directory:
            root = Path(directory)
            preview = root / "preview.png"
            visual._write_rgb_png(preview, 1, 1, [bytes((8, 16, 32))])
            (root / "project.json").write_text(
                json.dumps({"preview": "preview.png"}),
                encoding="utf-8",
            )
            self.assertEqual(visual.project_preview_path(root), (preview.resolve(), None))

            (root / "project.json").write_text(
                json.dumps({"preview": "../outside.png"}),
                encoding="utf-8",
            )
            resolved, error = visual.project_preview_path(root)
            self.assertIsNone(resolved)
            self.assertIn("escapes", error)

    def test_directional_visual_metrics_center_crop_capture(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-metrics-") as directory:
            root = Path(directory)
            preview = root / "preview.png"
            capture = root / "capture.png"
            blue = bytes((24, 72, 180))
            red = bytes((220, 24, 24))
            visual._write_rgb_png(preview, 2, 2, [blue * 2, blue * 2])
            visual._write_rgb_png(
                capture,
                4,
                2,
                [red + blue * 2 + red, red + blue * 2 + red],
            )

            metrics = visual.directional_visual_metrics(preview, capture)

            self.assertEqual(
                metrics["capture_center_crop"],
                {"x": 1, "y": 0, "width": 2, "height": 2},
            )
            self.assertEqual(metrics["spatial_color_similarity"], 1.0)
            self.assertEqual(metrics["spatial_luminance_similarity"], 1.0)
            self.assertEqual(metrics["preview_mean_rgb"], metrics["capture_mean_rgb"])

    def test_preview_visual_evidence_is_advisory_and_writes_montage(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-evidence-") as directory:
            root = Path(directory)
            sample = root / "sample"
            result = root / "result"
            sample.mkdir()
            result.mkdir()
            preview = sample / "preview.png"
            capture = result / "scene-after-window.png"
            pixels = [bytes((32, 64, 96)) * 2, bytes((96, 64, 32)) * 2]
            visual._write_rgb_png(preview, 2, 2, pixels)
            visual._write_rgb_png(capture, 2, 2, pixels)
            (sample / "project.json").write_text(
                json.dumps({"preview": "preview.png"}),
                encoding="utf-8",
            )

            evidence = visual.collect_preview_visual_evidence(sample, capture, result)

            self.assertEqual(evidence["status"], "available")
            self.assertTrue(evidence["advisory"])
            self.assertFalse(evidence["gating"])
            self.assertFalse(evidence["cross_sample_ranking"])
            self.assertIsNone(evidence["absolute_threshold"])
            self.assertEqual(evidence["metrics"]["spatial_color_similarity"], 1.0)
            self.assertTrue(Path(evidence["reference_png"]).is_file())
            self.assertTrue(Path(evidence["comparison_montage"]).is_file())
            self.assertTrue(
                benchmark.png_has_non_black_pixel(Path(evidence["comparison_montage"]))
            )

    def test_missing_preview_visual_evidence_never_becomes_a_gate(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-missing-") as directory:
            root = Path(directory)
            sample = root / "sample"
            result = root / "result"
            sample.mkdir()
            result.mkdir()
            capture = result / "scene-after-window.png"
            visual._write_rgb_png(capture, 1, 1, [bytes((12, 34, 56))])
            (sample / "project.json").write_text("{}", encoding="utf-8")

            evidence = visual.collect_preview_visual_evidence(sample, capture, result)

            self.assertEqual(evidence["status"], "unavailable")
            self.assertTrue(evidence["advisory"])
            self.assertFalse(evidence["gating"])
            self.assertIn("not declared", evidence["reason"])

    def test_preview_visual_summary_reports_coverage_without_threshold(self) -> None:
        results = [
            {
                "evidence": {
                    "preview_visual": {
                        "status": "available",
                        "metrics": {"spatial_color_similarity": 0.8},
                    }
                }
            },
            {"evidence": {"preview_visual": {"status": "unavailable"}}},
        ]

        self.assertEqual(
            visual.summarize_preview_visual_evidence(results),
            {
                "advisory": True,
                "gating": False,
                "comparison_scope": "same-sample-change-only",
                "cross_sample_ranking": False,
                "absolute_threshold": None,
                "available_count": 1,
                "unavailable_count": 1,
            },
        )

    def test_full_sample_matrix_pins_the_current_45_sample_snapshot(self) -> None:
        matrix = benchmark.load_matrix(FULL_SAMPLE_MATRIX_PATH)
        samples = {sample["id"]: sample for sample in matrix["samples"]}
        self.assertEqual(matrix["name"], "scene-current-full-baseline-2026-07-24")
        self.assertEqual(len(samples), 45)
        self.assertTrue({
            "1553008362",
            "1937925563",
            "2067939514",
            "2974757317",
            "3747492842",
            "3768903841",
            "3770462923",
        }.issubset(samples))
        self.assertNotIn("3770500543", samples)
        for sample in samples.values():
            self.assertEqual(sample["expected_runtime_evidence_schema"], 1)
            self.assertRegex(sample["project_sha256"], r"^[0-9a-f]{64}$")
            self.assertRegex(sample["package_sha256"], r"^[0-9a-f]{64}$")
            self.assertRegex(
                sample["expected_effect_graph_sha256"],
                r"^[0-9a-f]{64}$",
            )
        self.assertEqual(
            samples["2974757317"]["expected_utility_named_binding_planned"],
            0,
        )
        self.assertEqual(
            samples["2974757317"]["expected_utility_named_target_gaps"],
            3,
        )
        positive_shake = samples["2802243144"]
        self.assertEqual(
            positive_shake["expected_authored_effect_graph_succeeded_layer_ids"],
            [41, 64, 115],
        )
        self.assertEqual(
            positive_shake["expected_authored_effect_graph_legacy_blur_blocked_layer_ids"],
            [],
        )
        self.assertEqual(positive_shake["expected_authored_effect_graph_shake_count"], 3)
        self.assertEqual(positive_shake["expected_authored_effect_graph_chain_count"], 3)
        self.assertEqual(positive_shake["expected_authored_effect_graph_stage_count"], 6)
        self.assertEqual(positive_shake["expected_route_only_effect_count"], 1)
        self.assertTrue(positive_shake["requires_motion"])
        self.assertGreater(positive_shake["minimum_changed_ratio"], 0)
        negative_shake = samples["2134765860"]
        self.assertEqual(negative_shake["expected_authored_effect_graph_shake_count"], 0)
        self.assertEqual(
            negative_shake["expected_authored_effect_graph_succeeded_layer_ids"],
            [],
        )
        self.assertEqual(
            samples["2470144420"]["required_particle_loaded_layer_ids"],
            [106, 128],
        )
        self.assertEqual(
            sorted(samples["3769688830"]["required_particle_loaded_layer_ids"]),
            [354, 761, 1214, 1427],
        )

    def test_load_matrix_accepts_version_one_samples(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({"schema_version": 1, "name": "fixture", "samples": [{"id": "1"}]}),
                encoding="utf-8",
            )
            self.assertEqual(benchmark.load_matrix(path)["samples"][0]["id"], "1")

    def test_load_matrix_rejects_unknown_schema(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({"schema_version": 2, "samples": []}),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                benchmark.load_matrix(path)

    def test_select_matrix_samples_reuses_tracked_matrix_for_targeted_runs(self) -> None:
        matrix = {
            "schema_version": 1,
            "name": "fixture",
            "samples": [{"id": "1"}, {"id": "2"}, {"id": "3"}],
        }
        selected = benchmark.select_matrix_samples(matrix, ["3", "1"])
        self.assertEqual([sample["id"] for sample in selected["samples"]], ["1", "3"])
        self.assertEqual(len(matrix["samples"]), 3)
        with self.assertRaisesRegex(ValueError, "9"):
            benchmark.select_matrix_samples(matrix, ["9"])

    def test_hover_pointer_contract_accepts_only_finite_normalized_pairs(self) -> None:
        self.assertEqual(
            benchmark.hover_pointer_normalized(
                {"hover_pointer_normalized": [0.1, -0.25]}
            ),
            (0.1, -0.25),
        )
        self.assertIsNone(benchmark.hover_pointer_normalized({}))
        for value in ([0], [0, 0, 0], [2, 0], [0, float("nan")], ["0", 0]):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.hover_pointer_normalized(
                        {"hover_pointer_normalized": value}
                    )

    def test_debug_runner_sequences_before_hover_and_after_frames(self) -> None:
        source = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("--mwx-debug-scene-hover-pointer-json", source)
        self.assertIn("--mwx-debug-scene-after-snapshot-delay", source)
        before = source.index('requestSnapshot(reason: "before"')
        hover_state = source.index("setPointer(hoverPointer)", before)
        hover = source.index('requestSnapshot(reason: "hover"', hover_state)
        outside = source.index("setPointerOutside()", hover)
        after = source.index('requestSnapshot(reason: "after"', outside)
        self.assertLess(before, hover_state)
        self.assertLess(hover_state, hover)
        self.assertLess(hover, outside)
        self.assertLess(outside, after)

    def test_default_matrix_pins_solid_layer_semantics(self) -> None:
        # 固定门 2026-07-26 重建为当前真实目录中的 13 个代表样本。
        matrix = benchmark.load_matrix(SCRIPT_DIR / "scene_wallpaper_sample_matrix.json")
        samples = {sample["id"]: sample for sample in matrix["samples"]}
        expected = {
            "2131872317": (0, 0, 0),
            "2802243144": (0, 0, 0),
            "2902406982": (9, 6, 1),
            "2938612768": (11, 9, 2),
            "2998757800": (0, 0, 0),
            "3088601835": (0, 0, 0),
            "3122339805": (84, 73, 57),
            "3742133044": (0, 0, 0),
            "3747492842": (2, 1, 2),
            "3750813609": (1, 1, 1),
            "3757555836": (0, 0, 0),
            "3768903841": (6, 1, 3),
            "3769688830": (1, 0, 1),
        }
        self.assertEqual(set(samples), set(expected))
        for sample_id, (solid_count, authored_color_count, effective_count) in expected.items():
            sample = samples[sample_id]
            self.assertEqual(sample["expected_runtime_evidence_schema"], 1)
            self.assertEqual(sample["expected_solid_layer_count"], solid_count)
            self.assertEqual(
                sample["expected_authored_solid_color_layer_count"],
                authored_color_count,
            )
            self.assertEqual(sample["expected_solid_candidates"], solid_count)
            if solid_count:
                self.assertEqual(
                    sample["expected_effective_visible_solid_layer_count"],
                    effective_count,
                )

    def test_default_matrix_pins_shader_contracts(self) -> None:
        matrix = benchmark.load_matrix(SCRIPT_DIR / "scene_wallpaper_sample_matrix.json")
        self.assertEqual(len(matrix["samples"]), 13)
        # (authored, builtin, stage, diagnostic)。统一 stock namespace 后，
        # 3088601835/3122339805 此前缺失的 shader stage 已恢复，诊断归零。
        expected = {
            "2131872317": (5, 2, 10, 0),
            "2802243144": (3, 2, 6, 0),
            "2902406982": (17, 3, 34, 0),
            "2938612768": (18, 3, 36, 0),
            "2998757800": (4, 2, 8, 0),
            "3088601835": (11, 1, 22, 0),
            "3122339805": (3, 1, 6, 0),
            "3742133044": (3, 2, 6, 0),
            "3747492842": (14, 2, 28, 0),
            "3750813609": (7, 2, 14, 0),
            "3757555836": (4, 2, 8, 0),
            "3768903841": (7, 2, 14, 2),
            "3769688830": (16, 3, 32, 0),
        }
        self.assertEqual({s["id"] for s in matrix["samples"]}, set(expected))
        for sample in matrix["samples"]:
            authored, builtin, stage, diagnostics = expected[sample["id"]]
            self.assertEqual(sample["expected_runtime_evidence_schema"], 1)
            self.assertEqual(sample["expected_shader_contract_authored_count"], authored)
            self.assertEqual(sample["expected_shader_contract_builtin_count"], builtin)
            self.assertEqual(sample["expected_shader_contract_count"], authored + builtin)
            self.assertEqual(sample["expected_shader_contract_stage_count"], stage)
            self.assertEqual(sample["expected_shader_contract_diagnostic_count"], diagnostics)
            self.assertRegex(
                sample["expected_shader_contract_aggregate_sha256"],
                r"^[0-9a-f]{64}$",
            )

    def test_copy_sample_requires_project_and_package(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-copy-") as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "project.json").write_text("{}", encoding="utf-8")
            with self.assertRaises(FileNotFoundError):
                benchmark.copy_sample(source, root / "missing")

            (source / "scene.pkg").write_bytes(b"PKGV")
            destination = root / "copied"
            benchmark.copy_sample(source, destination)
            self.assertEqual((destination / "scene.pkg").read_bytes(), b"PKGV")

    def test_passing_runtime_is_removed_without_keep_flag(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-retention-") as directory:
            root = Path(directory)
            runtime_root = root / "runtime"
            runtime_sample = runtime_root / "runtime-samples/1"
            runtime_home = runtime_root / "runtime-homes/1"
            runtime_binary = (
                runtime_root
                / "runtime-app-fixture/MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
            )
            for path in (runtime_sample, runtime_home, runtime_binary.parent):
                path.mkdir(parents=True, exist_ok=True)
            runtime_binary.write_bytes(b"binary")
            app_identity = {
                "runtime_root_path": str(runtime_root / "runtime-app-fixture"),
                "runtime_bundle_path": str(
                    runtime_root / "runtime-app-fixture/MyWallpaperX.app"
                ),
                "runtime_executable_path": str(runtime_binary),
                "runtime_retained": True,
            }
            result = {
                "id": "1",
                "passed": True,
                "runtime_sample": str(runtime_sample),
                "runtime_home": str(runtime_home),
                "runtime_retained": True,
            }

            benchmark.apply_runtime_retention(
                runtime_root,
                app_identity,
                [result],
                keep_runtime=False,
            )

            self.assertFalse(runtime_root.exists())
            self.assertFalse(result["runtime_retained"])
            self.assertIsNone(result["runtime_sample"])
            self.assertIsNone(result["runtime_home"])
            self.assertFalse(app_identity["runtime_retained"])

    def test_failed_runtime_is_retained_while_passing_sample_is_removed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-retention-") as directory:
            runtime_root = Path(directory) / "runtime"
            app_root = runtime_root / "runtime-app-fixture"
            app_root.mkdir(parents=True)
            results = []
            for sample_id, passed in (("1", True), ("2", False)):
                runtime_sample = runtime_root / "runtime-samples" / sample_id
                runtime_home = runtime_root / "runtime-homes" / sample_id
                runtime_sample.mkdir(parents=True)
                runtime_home.mkdir(parents=True)
                results.append({
                    "id": sample_id,
                    "passed": passed,
                    "runtime_sample": str(runtime_sample),
                    "runtime_home": str(runtime_home),
                    "runtime_retained": True,
                })
            app_identity = {"runtime_retained": True}

            benchmark.apply_runtime_retention(
                runtime_root,
                app_identity,
                results,
                keep_runtime=False,
            )

            self.assertFalse((runtime_root / "runtime-samples/1").exists())
            self.assertFalse((runtime_root / "runtime-homes/1").exists())
            self.assertTrue((runtime_root / "runtime-samples/2").is_dir())
            self.assertTrue((runtime_root / "runtime-homes/2").is_dir())
            self.assertFalse(results[0]["runtime_retained"])
            self.assertTrue(results[1]["runtime_retained"])
            self.assertTrue(app_identity["runtime_retained"])

    def test_default_matrix_pins_utility_capture_layers(self) -> None:
        matrix = benchmark.load_matrix(SCRIPT_DIR / "scene_wallpaper_sample_matrix.json")
        sample = next(item for item in matrix["samples"] if item["id"] == "2902406982")
        self.assertEqual(sample["expected_utility_capture_planned"], 2)
        self.assertEqual(sample["expected_utility_named_target_planned"], 6)
        self.assertEqual(sample["expected_utility_named_binding_planned"], 7)
        self.assertEqual(sample["expected_utility_named_target_gaps"], 0)
        self.assertEqual(sample["required_utility_dispositions"]["410"], "capture")
        self.assertEqual(sample["required_utility_capture_succeeded_layer_ids"], [410, 530])
        self.assertEqual(
            sample["required_named_target_capture_succeeded_layer_ids"],
            [84, 91, 125, 253, 271, 291],
        )
        self.assertEqual(
            sample["required_named_target_binding_succeeded_layer_ids"],
            [70, 182, 217, 245, 265, 285, 791],
        )
        media_sample = next(item for item in matrix["samples"] if item["id"] == "2938612768")
        self.assertEqual(media_sample["expected_utility_named_target_planned"], 2)
        self.assertEqual(media_sample["expected_utility_named_binding_planned"], 2)
        self.assertEqual(media_sample["expected_utility_named_target_gaps"], 1)
        self.assertEqual(
            media_sample["required_named_target_capture_succeeded_layer_ids"],
            [141, 1340],
        )
        self.assertEqual(
            media_sample["required_named_target_binding_succeeded_layer_ids"],
            [299, 322],
        )
        self.assertEqual(media_sample["expected_image_blend_planned"], 5)
        self.assertEqual(
            media_sample["required_image_blend_succeeded_layer_ids"],
            [239, 657, 775, 875, 1509],
        )

    def test_default_matrix_pins_procedural_particle_layers(self) -> None:
        matrix = benchmark.load_matrix(SCRIPT_DIR / "scene_wallpaper_sample_matrix.json")
        samples = {sample["id"]: sample for sample in matrix["samples"]}
        # 2026-07-26 固定门重建后，除 3122339805（无粒子）外 12 个样本都
        # 锁定实际加载的粒子 layer ID 集合。
        expected = {
            "2131872317": [8929, 10203, 10440, 3180, 529, 832, 1375, 37, 2530],
            "2802243144": [20, 25],
            "2902406982": [262],
            "2938612768": [173],
            "2998757800": [260, 211, 172, 187, 199, 181, 193, 205, 38618],
            "3088601835": [534, 558, 569, 513, 550, 564, 572, 576, 579, 587, 592, 595, 598, 606, 922, 927, 1152, 1156, 1159],
            "3742133044": [196],
            "3747492842": [269],
            "3750813609": [121, 200, 90, 504, 511, 516, 498],
            "3757555836": [81, 219, 88, 222, 91, 225, 98],
            "3768903841": [306, 309, 312, 264, 271],
            "3769688830": [354, 1214, 1427, 761],
        }
        for sample_id, layer_ids in expected.items():
            sample = samples[sample_id]
            self.assertEqual(sample["minimum_particle_loaded"], len(layer_ids))
            self.assertEqual(sample["required_particle_loaded_layer_ids"], layer_ids)
        self.assertEqual(samples["3122339805"]["required_particle_loaded_layer_ids"], [])

    def test_default_matrix_pins_authored_effect_graph_execution(self) -> None:
        matrix = benchmark.load_matrix(SCRIPT_DIR / "scene_wallpaper_sample_matrix.json")
        samples = {sample["id"]: sample for sample in matrix["samples"]}
        # v29 基线下 2902406982 的 strict succeeded 从 v25 的 7 层扩到 35 层；
        # 稳定核心子集由 required_authored_effect_graph_succeeded_layer_ids 锁定。
        self.assertEqual(
            samples["2902406982"]["required_authored_effect_graph_succeeded_layer_ids"],
            [167, 177, 365, 372, 530, 647, 664],
        )
        self.assertEqual(
            len(samples["2902406982"]["expected_authored_effect_graph_succeeded_layer_ids"]),
            35,
        )
        self.assertEqual(
            samples["2902406982"]["expected_authored_effect_graph_local_contrast_count"],
            2,
        )
        self.assertEqual(
            samples["2902406982"]["expected_authored_effect_graph_opacity_count"],
            4,
        )
        self.assertEqual(
            samples["2902406982"]["expected_authored_effect_graph_opacity_layer_ids"],
            [365, 372, 647, 664],
        )
        self.assertEqual(
            samples["2902406982"][
                "expected_stock_opacity_single_effect_candidate_layer_ids"
            ],
            [365, 372, 647, 664],
        )
        self.assertEqual(samples["2902406982"]["expected_route_only_effect_count"], 31)
        self.assertEqual(
            samples["2902406982"]["minimum_authored_opacity_runtime_count"],
            4,
        )
        self.assertEqual(
            samples["2902406982"]["live_property_overrides"],
            {"brcontraststrength": 3.0, "newproperty50": 0.2},
        )
        self.assertGreater(samples["2902406982"]["minimum_live_changed_ratio"], 0)
        self.assertEqual(
            samples["2938612768"]["expected_authored_effect_graph_succeeded_layer_ids"],
            [],
        )
        self.assertEqual(
            samples["2938612768"]["expected_authored_effect_graph_local_contrast_count"],
            0,
        )
        self.assertEqual(
            samples["2938612768"]["expected_authored_effect_graph_opacity_count"],
            0,
        )
        self.assertEqual(
            samples["2938612768"]["expected_authored_effect_graph_opacity_layer_ids"],
            [],
        )
        self.assertEqual(
            samples["2938612768"][
                "expected_stock_opacity_single_effect_candidate_layer_ids"
            ],
            [165, 454, 626, 629, 924],
        )
        self.assertEqual(samples["2938612768"]["expected_route_only_effect_count"], 18)
        for sample_id in ("2902406982", "2938612768"):
            self.assertEqual(
                samples[sample_id]["minimum_legacy_waterwaves_runtime_count"], 0
            )
            self.assertEqual(
                samples[sample_id]["maximum_legacy_waterwaves_runtime_count"], 0
            )
        expected_chain_metrics = {
            # legacy 指纹批次（2026-07-27）：waterripple/pulse/waterwaves/shake 多指纹
            # 白名单让 2131872317 五层整链（19 stage / 4 chain）。
            "2131872317": (4, 19),
            "2802243144": (3, 6),
            "2902406982": (0, 35),
            "2938612768": (0, 0),
            "2998757800": (4, 18),
            "3088601835": (0, 0),
            "3122339805": (0, 11),
            "3742133044": (0, 0),
            "3747492842": (0, 1),
            "3750813609": (0, 0),
            "3757555836": (1, 5),
            "3768903841": (1, 10),
            "3769688830": (2, 8),
        }
        for sample_id, (chain_count, stage_count) in expected_chain_metrics.items():
            self.assertEqual(
                samples[sample_id]["expected_authored_effect_graph_chain_count"],
                chain_count,
            )
            self.assertEqual(
                samples[sample_id]["expected_authored_effect_graph_stage_count"],
                stage_count,
            )
        self.assertEqual(
            samples["3768903841"]["expected_authored_effect_graph_water_waves_count"],
            4,
        )
        self.assertEqual(
            samples["2998757800"]["expected_authored_effect_graph_shake_count"],
            16,
        )
        self.assertEqual(
            sum(
                sample.get("expected_authored_effect_graph_stage_count", 0)
                for sample in samples.values()
            ),
            # legacy 指纹批次后 2131872317 由 0 stage 升到 19；
            # Tint 遮罩欠账落地后 3122339805 由 3 stage 升到 11。
            # Stock Spin 解锁 3769688830 的四级链后再增加 4 stage。
            113,
        )
        self.assertEqual(
            sum(
                sample.get("expected_authored_effect_graph_chain_count", 0)
                for sample in samples.values()
            ),
            15,
        )
        self.assertEqual(
            sum(sample["expected_route_only_effect_count"] for sample in samples.values()),
            67,
        )
        self.assertEqual(
            sum(
                sample.get("expected_authored_effect_graph_opacity_count", 0)
                for sample in samples.values()
            ),
            4,
        )
        self.assertEqual(
            sum(
                len(sample.get(
                    "expected_authored_effect_graph_legacy_blur_blocked_layer_ids",
                    [],
                ))
                for sample in samples.values()
            ),
            1,
        )

    def test_entry_basename_package_is_preferred_and_copied(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-copy-variant-") as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "project.json").write_text(
                json.dumps({"type": "scene", "file": "nested\\gifscene.json"}),
                encoding="utf-8",
            )
            (source / "gifscene.pkg").write_bytes(b"NAMED")
            (source / "scene.pkg").write_bytes(b"FALLBACK")

            self.assertEqual(benchmark.scene_package_path(source), source / "gifscene.pkg")
            destination = root / "copied"
            benchmark.copy_sample(source, destination)
            self.assertEqual((destination / "gifscene.pkg").read_bytes(), b"NAMED")

    def test_custom_entry_falls_back_to_scene_package(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-copy-fallback-") as directory:
            source = Path(directory)
            (source / "project.json").write_text(
                json.dumps({"type": "scene", "file": "gifscene.json"}),
                encoding="utf-8",
            )
            (source / "scene.pkg").write_bytes(b"FALLBACK")
            self.assertEqual(benchmark.scene_package_path(source), source / "scene.pkg")

    def test_swift_project_loader_resolves_entry_package_and_fallback(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-scene-project-loader-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-project-loader"
            harness.write_text(
                """
                import Foundation

                @main
                enum Harness {
                    static func main() throws {
                        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                        let project = try SceneProjectLoader().load(from: root)
                        print(project.packageURL?.lastPathComponent ?? "nil")
                    }
                }
                """,
                encoding="utf-8",
            )
            subprocess.run(
                [
                    swiftc,
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneUserProperty.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneUserPropertyDefinitionParser.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift"),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            sample = root / "sample"
            sample.mkdir()
            (sample / "project.json").write_text(
                json.dumps({"type": "scene", "file": "gifscene.json"}),
                encoding="utf-8",
            )
            (sample / "gifscene.pkg").write_bytes(b"NAMED")
            (sample / "scene.pkg").write_bytes(b"FALLBACK")
            named = subprocess.run(
                [str(binary), str(sample)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(named.stdout.strip(), "gifscene.pkg")

            (sample / "gifscene.pkg").unlink()
            fallback = subprocess.run(
                [str(binary), str(sample)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(fallback.stdout.strip(), "scene.pkg")

    def test_runtime_evidence_metrics_preserve_slots_and_combos(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            shader_contracts = [{
                "identity": "effects/zeta",
                "sourceKind": "authoredSource",
                "stages": [
                    shader_stage("effects/zeta", "vertex", "zeta vertex"),
                    shader_stage("effects/zeta", "fragment", "zeta fragment"),
                ],
                "diagnostics": [],
                "canonicalSHA256": "b" * 64,
            }, {
                "identity": "genericimage4",
                "sourceKind": "hostBuiltin",
                "stages": [],
                "diagnostics": [],
                "canonicalSHA256": "c" * 64,
            }, {
                "identity": "effects/alpha",
                "sourceKind": "authoredSource",
                "stages": [
                    shader_stage("effects/alpha", "vertex", "alpha vertex"),
                    shader_stage("effects/alpha", "fragment", "alpha fragment"),
                ],
                "diagnostics": [{
                    "code": "malformedAnnotation",
                    "message": "bad annotation",
                    "relativePath": "shaders/effects/alpha.frag",
                    "line": 2,
                }],
                "canonicalSHA256": "a" * 64,
            }]
            effect_graphs = [{
                "effects": [{"key": "one"}, {"key": "two"}],
                "renderTargets": [{"name": "one"}, {"name": "two"}],
                "nodes": [
                    {"kind": "material"},
                    {"kind": "copy"},
                    {"kind": "swap"},
                ],
                "blockers": [{"reason": "unsupportedCondition"}],
            }, {
                "layerID": 9,
                "effects": [{
                    "key": "three",
                    "definitionPath": "Effects\\Opacity\\Effect.json",
                }],
                "renderTargets": [],
                "nodes": [{"kind": "material"}],
                "blockers": [],
            }]
            path.write_text(
                json.dumps(runtime_evidence({
                    "shaderContracts": shader_contracts,
                    "authoredEffectRenderPlans": effect_graphs,
                    "renderDescriptor": {
                        "materialPasses": [{
                            "textureSlots": [None, None, "phase.tex"],
                            "combos": {"VERSION": 2, "MODE": 0},
                        }],
                        "effectDefinitions": [{
                            "passes": [
                                {"materialPath": "materials/effects/test.json"},
                                {"command": "copy"},
                                {"command": "swap"},
                            ],
                            "framebuffers": [{"name": "one"}, {"name": "two"}],
                        }],
                        "effectDefinitionDiagnostics": [{"code": "unknownFields"}],
                        "builtInReferenceCount": 4,
                        "missingResources": ["one", "two"],
                        "layers": [{
                            "id": 1,
                            "visible": False,
                            "parentID": None,
                            "effects": [],
                        }, {
                            "effects": [{"file": "effects/test.json", "passes": [{
                                "textureSlots": [None, "normal.tex"],
                                "combos": {"REPEAT": 1},
                            }]}],
                            "id": 7,
                            "visible": True,
                            "parentID": 1,
                            "text": "property gate",
                            "contentKind": "solid",
                            "parallaxDepthXY": [2, 0],
                            "disablesParallaxPropagation": True,
                        }, {
                            "id": 8,
                            "visible": True,
                            "parentID": None,
                            "contentKind": "solid",
                            "colorRGB": [0.2, 0.4, 0.6],
                            "effects": [],
                        }, {
                            "id": 9,
                            "visible": True,
                            "parentID": 8,
                            "contentKind": "solid",
                            "effects": [],
                        }],
                    },
                })),
                encoding="utf-8",
            )
            metrics = benchmark.runtime_evidence_metrics(path)
            self.assertEqual(metrics["schema_version"], 1)
            self.assertEqual(metrics["shader_contract_count"], 3)
            self.assertEqual(metrics["shader_contract_authored_count"], 2)
            self.assertEqual(metrics["shader_contract_builtin_count"], 1)
            self.assertEqual(metrics["shader_contract_stage_count"], 4)
            self.assertEqual(metrics["shader_contract_diagnostic_count"], 1)
            self.assertEqual(
                metrics["shader_contract_aggregate_sha256"],
                "33c1609a3d79a75fef6e568b233d01a0b94ab6233d6137cc828418dfa74a9f4c",
            )
            self.assertEqual(metrics["effect_texture_slot_count"], 2)
            self.assertEqual(metrics["effect_texture_slot_hole_count"], 1)
            self.assertEqual(metrics["effect_combo_entry_count"], 1)
            self.assertEqual(metrics["material_texture_slot_count"], 3)
            self.assertEqual(metrics["material_texture_slot_hole_count"], 2)
            self.assertEqual(metrics["material_combo_entry_count"], 2)
            self.assertEqual(metrics["effect_definition_count"], 1)
            self.assertEqual(metrics["effect_definition_pass_count"], 3)
            self.assertEqual(metrics["effect_definition_material_pass_count"], 1)
            self.assertEqual(metrics["effect_definition_fbo_count"], 2)
            self.assertEqual(metrics["effect_definition_copy_command_count"], 1)
            self.assertEqual(metrics["effect_definition_swap_command_count"], 1)
            self.assertEqual(metrics["effect_definition_diagnostic_count"], 1)
            self.assertEqual(metrics["effect_graph_layer_count"], 2)
            self.assertEqual(metrics["effect_graph_effect_count"], 3)
            self.assertEqual(metrics["effect_graph_node_count"], 4)
            self.assertEqual(metrics["effect_graph_material_node_count"], 2)
            self.assertEqual(metrics["effect_graph_copy_node_count"], 1)
            self.assertEqual(metrics["effect_graph_swap_node_count"], 1)
            self.assertEqual(metrics["effect_graph_render_target_count"], 2)
            self.assertEqual(metrics["effect_graph_blocker_count"], 1)
            self.assertEqual(
                metrics["effect_graph_blocker_reasons"],
                {"unsupportedCondition": 1},
            )
            self.assertEqual(metrics["effect_graph_unblocked_layer_count"], 1)
            self.assertEqual(
                metrics["effect_graph_sha256"],
                hashlib.sha256(json.dumps(
                    effect_graphs,
                    ensure_ascii=True,
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")).hexdigest(),
            )
            self.assertEqual(metrics["visible_layer_count"], 3)
            self.assertEqual(metrics["visible_layer_ids"], [7, 8, 9])
            self.assertEqual(metrics["root_layer_count"], 2)
            self.assertEqual(metrics["child_edge_count"], 2)
            self.assertEqual(metrics["parent_layer_count"], 2)
            self.assertEqual(metrics["max_hierarchy_depth"], 1)
            self.assertEqual(metrics["effective_visible_layer_count"], 2)
            self.assertEqual(metrics["effective_visible_layer_ids"], [8, 9])
            self.assertEqual(
                metrics["stock_opacity_single_effect_candidate_layer_ids"],
                [9],
            )
            self.assertEqual(metrics["solid_layer_count"], 3)
            self.assertEqual(metrics["solid_layer_ids"], [7, 8, 9])
            self.assertEqual(metrics["authored_solid_color_layer_count"], 1)
            self.assertEqual(metrics["authored_solid_color_layer_ids"], [8])
            self.assertEqual(metrics["effective_visible_solid_layer_count"], 2)
            self.assertEqual(metrics["effective_visible_solid_layer_ids"], [8, 9])
            self.assertEqual(metrics["authored_parallax_layer_count"], 1)
            self.assertEqual(metrics["authored_parallax_layer_ids"], [7])
            self.assertEqual(metrics["parallax_propagation_block_count"], 1)
            self.assertEqual(metrics["text_values"], ["property gate"])
            self.assertEqual(metrics["effect_files"], ["effects/test.json"])
            self.assertEqual(metrics["built_in_reference_count"], 4)
            self.assertEqual(metrics["missing_resource_count"], 2)
            self.assertIsNone(metrics["error"])

    def test_runtime_evidence_metrics_reject_invalid_slot_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            path.write_text(json.dumps(runtime_evidence({
                "shaderContracts": [],
                "renderDescriptor": {
                    "layers": [{"effects": [{"passes": [{"textureSlots": "bad", "combos": {}}]}]}],
                    "materialPasses": [],
                },
            })), encoding="utf-8")
            metrics = benchmark.runtime_evidence_metrics(path)
            self.assertIsNone(metrics["schema_version"])
            self.assertIn("invalid shape", metrics["error"])

    def test_shader_contract_aggregate_is_independent_of_contract_order(self) -> None:
        contracts = [{
            "identity": "effects/zeta",
            "sourceKind": "authoredSource",
            "stages": [
                shader_stage("effects/zeta", "vertex", "zeta vertex"),
                shader_stage("effects/zeta", "fragment", "zeta fragment"),
            ],
            "diagnostics": [],
            "canonicalSHA256": "b" * 64,
        }, {
            "identity": "genericimage4",
            "sourceKind": "hostBuiltin",
            "stages": [],
            "diagnostics": [],
            "canonicalSHA256": "c" * 64,
        }]
        forward = benchmark.shader_contract_metrics(contracts)
        reverse = benchmark.shader_contract_metrics(list(reversed(contracts)))
        self.assertEqual(
            forward["shader_contract_aggregate_sha256"],
            reverse["shader_contract_aggregate_sha256"],
        )

    def test_runtime_evidence_metrics_reject_missing_or_malformed_shader_contracts(self) -> None:
        valid_contract = {
            "identity": "effects/example",
            "sourceKind": "authoredSource",
            "stages": [
                shader_stage("effects/example", "vertex", "example vertex"),
                shader_stage("effects/example", "fragment", "example fragment"),
            ],
            "diagnostics": [],
            "canonicalSHA256": "a" * 64,
        }
        malformed_contract_sets = {
            "missing": None,
            "not-an-array": {},
            "non-object-contract": ["bad"],
            "missing-identity": [{
                key: value for key, value in valid_contract.items() if key != "identity"
            }],
            "unknown-source-kind": [{**valid_contract, "sourceKind": "generated"}],
            "stages-not-an-array": [{**valid_contract, "stages": {}}],
            "stage-not-an-object": [{**valid_contract, "stages": ["bad"]}],
            "stage-missing-fields": [{**valid_contract, "stages": [{}]}],
            "stage-hash-mismatch": [{
                **valid_contract,
                "stages": [{**valid_contract["stages"][0], "source": "changed"}],
            }],
            "diagnostics-not-an-array": [{**valid_contract, "diagnostics": {}}],
            "diagnostic-not-an-object": [{**valid_contract, "diagnostics": ["bad"]}],
            "diagnostic-missing-fields": [{**valid_contract, "diagnostics": [{}]}],
            "empty-canonical-sha": [{**valid_contract, "canonicalSHA256": ""}],
            "malformed-canonical-sha": [{**valid_contract, "canonicalSHA256": "A" * 64}],
            "duplicate-identity": [valid_contract, valid_contract],
            "builtin-with-stage": [{
                **valid_contract,
                "identity": "genericimage2",
                "sourceKind": "hostBuiltin",
                "stages": [shader_stage("genericimage2", "vertex", "bad")],
            }],
        }
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            for case, contracts in malformed_contract_sets.items():
                with self.subTest(case=case):
                    payload = {
                        "renderDescriptor": {"layers": [], "materialPasses": []},
                    }
                    if case != "missing":
                        payload["shaderContracts"] = contracts
                    path.write_text(
                        json.dumps(runtime_evidence(payload)), encoding="utf-8"
                    )
                    metrics = benchmark.runtime_evidence_metrics(path)
                    self.assertIsNone(metrics["schema_version"])
                    self.assertIsNone(metrics["shader_contract_aggregate_sha256"])
                    self.assertTrue(metrics["error"])

    def test_runtime_log_patterns_capture_ready_and_release(self) -> None:
        ready = benchmark.READY_RE.search(
            "MWX DEBUG SCENE: phase=ready root=/tmp/sample layers=35 "
            "imageLayers=24 effects=29 surfaces=1 windows=42 previewLog=/tmp/log "
            "runtimeEvidence=/tmp/evidence/scene-runtime-evidence.json"
        )
        evidence = benchmark.RUNTIME_EVIDENCE_RE.search(
            "MWX DEBUG SCENE: phase=ready root=/tmp/sample layers=35 "
            "imageLayers=24 effects=29 surfaces=1 windows=42 previewLog=/tmp/log "
            "runtimeEvidence=/tmp/evidence/scene-runtime-evidence.json"
        )
        stopped = benchmark.STOPPED_RE.search(
            "MWX DEBUG SCENE: phase=stopped surfacesBefore=1 surfacesAfter=0"
        )
        live = benchmark.live_property_update_metrics(
            "MWX DEBUG SCENE: phase=live-property-update accepted=true "
            "surfacesBefore=1 surfacesAfter=1 windowsBefore=42 windowsAfter=42 "
            "keys=newproperty11"
        )
        loaded = benchmark.LOADED_RE.search("loaded: 20 / 24")
        text_loaded = benchmark.TEXT_LOADED_RE.search("text loaded: 10 / 10")
        particle_loaded = benchmark.PARTICLE_LOADED_RE.search("particle loaded: 3 / 4")
        particle_live = benchmark.PARTICLE_INITIAL_LIVE_RE.search("particle initial live: 96")
        camera = benchmark.CAMERA_RE.search(
            "camera: projection=cover parallax=false amount=8e-2 delay=0.25 mouseInfluence=-1.0"
        )
        self.assertEqual(ready.group("images"), "24")
        self.assertEqual(
            evidence.group("path"),
            "/tmp/evidence/scene-runtime-evidence.json",
        )
        self.assertEqual(stopped.group("after"), "0")
        self.assertEqual(live, {
            "accepted": True,
            "surfaces_before": 1,
            "surfaces_after": 1,
            "windows_before": [42],
            "windows_after": [42],
            "keys": ["newproperty11"],
        })
        self.assertEqual(loaded.group("loaded"), "20")
        self.assertEqual(text_loaded.group("loaded"), "10")
        self.assertEqual(particle_loaded.group("loaded"), "3")
        self.assertEqual(particle_loaded.group("total"), "4")
        self.assertEqual(particle_live.group("live"), "96")
        self.assertEqual(camera.group("projection"), "cover")
        self.assertEqual(camera.group("parallax"), "false")
        self.assertEqual(float(camera.group("amount")), 0.08)
        self.assertEqual(float(camera.group("delay")), 0.25)
        self.assertEqual(float(camera.group("influence")), -1.0)

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
        self.assertIn('private static let debugRecordID = "debug-scene-playback"', source)
        self.assertIn("--mwx-debug-scene-live-properties-json", source)
        self.assertIn("recordID: debugRecordID", source)
        self.assertIn("phase=live-property-update", source)

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

    def test_particle_runtime_fixture_metrics_and_optional_gates(self) -> None:
        preview_log = """Scene preview texture load report
loaded: 20 / 24
text loaded: 10 / 10
particle loaded: 3 / 4
particle initial live: 96
particle authored: 5
particle visible: 3
particle layer 200 "Snow": OK 64x64 blend=additive initial=32 perspective=false
particle layer 201 "Bird": OK 64x64 blend=translucent initial=64 perspective=true
particle skipped hidden: 2
"""
        metrics = benchmark.particle_runtime_metrics(preview_log)
        self.assertTrue(metrics["has_load_evidence"])
        self.assertTrue(metrics["has_initial_live_evidence"])
        self.assertEqual(metrics["loaded"], 3)
        self.assertEqual(metrics["candidates"], 4)
        self.assertEqual(metrics["loaded_ratio"], 0.75)
        self.assertEqual(metrics["initial_live"], 96)
        self.assertEqual(metrics["authored"], 5)
        self.assertEqual(metrics["visible"], 3)
        self.assertEqual(metrics["skipped_hidden"], 2)
        self.assertEqual(metrics["loaded_layer_ids"], [200, 201])
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "minimum_particle_loaded": 3,
                "expected_particle_candidates": 4,
                "minimum_particle_initial_live": 96,
                "expected_particle_authored": 5,
                "expected_particle_visible": 3,
                "expected_particle_skipped_hidden": 2,
                "required_particle_loaded_layer_ids": [200, 201],
            }, metrics),
            [],
        )
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "minimum_particle_loaded": 4,
                "expected_particle_candidates": 5,
                "minimum_particle_initial_live": 97,
                "expected_particle_authored": 4,
                "expected_particle_visible": 4,
                "expected_particle_skipped_hidden": 1,
                "required_particle_loaded_layer_ids": [202],
            }, metrics),
            [
                "particle loaded count below minimum",
                "particle candidate count mismatch",
                "particle initial live count below minimum",
                "particle authored count mismatch",
                "particle visible count mismatch",
                "particle skipped_hidden count mismatch",
                "particle layer 202 should be loaded",
            ],
        )

    def test_utility_runtime_fixture_preserves_distinct_dispositions(self) -> None:
        preview_log = """Scene preview texture load report
utilityLayerCount: 3
utilityCapturePlannedCount: 1
utilityDependencyEdgeCount: 0
utilityNamedConsumerCount: 0
utilityNamedTargetPlannedCount: 0
utilityNamedBindingPlannedCount: 0
utilityNamedTargetGapCount: 0
utility layer 187: capture kind=project
utility layer 96: unsupportedEffects kind=composition
utility layer 763: skippedHidden kind=composition
"""
        metrics = benchmark.utility_runtime_metrics(preview_log)
        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["candidates"], 3)
        self.assertEqual(metrics["capture_planned"], 1)
        self.assertEqual(metrics["named_consumers"], 0)
        self.assertEqual(metrics["named_target_planned"], 0)
        self.assertEqual(metrics["named_binding_planned"], 0)
        self.assertEqual(
            benchmark.utility_runtime_failures({
                "expected_utility_candidates": 3,
                "expected_utility_capture_planned": 1,
                "expected_utility_dependency_edges": 0,
                "expected_utility_named_consumers": 0,
                "expected_utility_named_target_planned": 0,
                "expected_utility_named_binding_planned": 0,
                "expected_utility_named_target_gaps": 0,
                "required_utility_dispositions": {
                    "187": "capture",
                    "96": "unsupportedEffects",
                    "763": "skippedHidden",
                },
            }, metrics),
            [],
        )
        self.assertEqual(
            benchmark.utility_runtime_failures({
                "expected_utility_capture_planned": 2,
                "required_utility_dispositions": {"96": "capture"},
            }, metrics),
            [
                "utility capture_planned mismatch",
                "utility layer 96 disposition should be capture",
            ],
        )

    def test_utility_capture_execution_prefers_eventual_success(self) -> None:
        metrics = benchmark.utility_capture_execution_metrics(
            "phase=utility-capture layer=530 status=failed\n"
            "phase=utility-capture layer=530 status=succeeded\n"
            "phase=utility-capture layer=410 status=failed\n"
        )
        self.assertEqual(metrics["succeeded_layer_ids"], [530])
        self.assertEqual(metrics["failed_layer_ids"], [410])

    def test_authored_effect_graph_execution_is_a_strict_layer_gate(self) -> None:
        metrics = benchmark.authored_effect_graph_execution_metrics(
            "phase=authored-effect-graph layer=68 status=failed\n"
            "phase=authored-effect-graph layer=68 status=succeeded\n"
            "phase=authored-effect-graph layer=76 status=succeeded\n"
        )
        self.assertEqual(metrics["succeeded_layer_ids"], [68, 76])
        self.assertEqual(metrics["failed_layer_ids"], [])
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_succeeded_layer_ids": [68, 76]},
                metrics,
                [],
                None,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph succeeded layer IDs mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_succeeded_layer_ids": [68]},
                metrics,
                [],
                None,
            ),
        )

    def test_authored_effect_graph_legacy_blur_block_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphLegacyBlurBlockedLayerIDs: 20,36\n"
        blocked = benchmark.authored_effect_graph_legacy_blur_blocked_layer_ids(preview)
        self.assertEqual(blocked, [20, 36])
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_legacy_blur_blocked_layer_ids": [20, 36]},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                blocked,
                None,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph legacy blur blocked layer IDs mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_legacy_blur_blocked_layer_ids": [20]},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                blocked,
                None,
            ),
        )

    def test_authored_local_contrast_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphLocalContrastCount: 2\n"
        count = benchmark.authored_effect_graph_local_contrast_count(preview)
        self.assertEqual(count, 2)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_local_contrast_count": 2},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Local Contrast count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_local_contrast_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                count,
            ),
        )

    def test_authored_workshop_shadow_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWorkshopShadowCount: 1\n"
        count = benchmark.authored_effect_graph_workshop_shadow_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_workshop_shadow_count": 1},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                workshop_shadow_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Workshop Shadow count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_workshop_shadow_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                workshop_shadow_count=count,
            ),
        )

    def test_authored_spin_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphSpinCount: 1\n"
        count = benchmark.authored_effect_graph_spin_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_spin_count": 1},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                spin_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Spin count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_spin_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                spin_count=count,
            ),
        )

    def test_authored_shake_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphShakeCount: 3\n"
        count = benchmark.authored_effect_graph_shake_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_shake_count": 3},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                shake_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Shake count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_shake_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
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
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_flow_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Flow count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_flow_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
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
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_waves_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Waves count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_waves_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_waves_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_water_waves_count(""))

    def test_authored_opacity_and_route_only_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphOpacityCount: 4\n"
            "authoredEffectGraphColorKeyCount: 2\n"
            "authoredEffectGraphWorkshopShiftHueCount: 3\n"
            "authoredEffectGraphWorkshopAudioBarsCount: 2\n"
            "authoredEffectGraphWorkshopGradientCount: 2\n"
            "authoredEffectGraphWorkshopAudioHueShiftCount: 4\n"
            "layer 365: effect runtime opacity-authored; 1 declared pass(es)\n"
            "layer 372: effect runtime opacity-authored; 1 declared pass(es)\n"
            "layer 647: effect runtime opacity-authored; 1 declared pass(es)\n"
            "layer 664: effect runtime opacity-authored; 1 declared pass(es)\n"
            "layer 702: offscreen route-only\n"
            "layer 159: offscreen route-only\n"
            "layer 462: offscreen route-only\n"
        )
        opacity_count = benchmark.authored_effect_graph_opacity_count(preview)
        color_key_count = benchmark.authored_effect_graph_color_key_count(preview)
        shift_hue_count = benchmark.authored_effect_graph_workshop_shift_hue_count(preview)
        audio_bars_count = benchmark.authored_effect_graph_workshop_audio_bars_count(preview)
        gradient_count = benchmark.authored_effect_graph_workshop_gradient_count(preview)
        audio_hue_count = benchmark.authored_effect_graph_workshop_audio_hue_shift_count(preview)
        opacity_layers = benchmark.authored_effect_graph_opacity_layer_ids(preview)
        route_only_count = preview.count("offscreen route-only")
        self.assertEqual(opacity_count, 4)
        self.assertEqual(color_key_count, 2)
        self.assertEqual(shift_hue_count, 3)
        self.assertEqual(audio_bars_count, 2)
        self.assertEqual(gradient_count, 2)
        self.assertEqual(audio_hue_count, 4)
        self.assertEqual(opacity_layers, [365, 372, 647, 664])
        self.assertEqual(route_only_count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_opacity_count": 4,
                    "expected_authored_effect_graph_opacity_layer_ids":
                        [365, 372, 647, 664],
                    "expected_route_only_effect_count": 3,
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                opacity_count=opacity_count,
                route_only_effect_count=route_only_count,
                opacity_layer_ids=opacity_layers,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            {
                "expected_authored_effect_graph_opacity_count": 0,
                "expected_authored_effect_graph_opacity_layer_ids": [],
                "expected_route_only_effect_count": 18,
            },
            {"succeeded_layer_ids": [], "failed_layer_ids": []},
            [],
            None,
            opacity_count=opacity_count,
            route_only_effect_count=route_only_count,
            opacity_layer_ids=opacity_layers,
        )
        self.assertIn("authored effect graph Opacity count mismatch", failures)
        self.assertIn("authored effect graph Opacity layer IDs mismatch", failures)
        self.assertIn("offscreen route-only effect count mismatch", failures)
        self.assertIsNone(benchmark.authored_effect_graph_opacity_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_color_key_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_workshop_shift_hue_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_workshop_audio_bars_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_workshop_gradient_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_workshop_audio_hue_shift_count(""))
        self.assertEqual(benchmark.authored_effect_graph_opacity_layer_ids(""), [])

    def test_authored_effect_chain_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphChainCount: 1\n"
            "authoredEffectGraphStageCount: 4\n"
        )
        metrics = benchmark.authored_effect_graph_chain_metrics(preview)
        self.assertEqual(metrics, {"chain_count": 1, "stage_count": 4})
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_chain_count": 1,
                    "expected_authored_effect_graph_stage_count": 4,
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                metrics,
            ),
            [],
        )
        self.assertEqual(
            benchmark.authored_effect_graph_chain_metrics(""),
            {"chain_count": None, "stage_count": None},
        )
        self.assertIn(
            "authored effect graph chain count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_chain_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                metrics,
            ),
        )

    def test_image_blend_runtime_pins_planned_and_completed_consumers(self) -> None:
        metrics = benchmark.image_blend_runtime_metrics(
            "imageBlendPlannedCount: 1\n",
            "phase=image-blend layer=1509 status=succeeded\n",
        )
        self.assertEqual(metrics["planned"], 1)
        self.assertEqual(metrics["succeeded_layer_ids"], [1509])
        self.assertEqual(
            benchmark.image_blend_runtime_failures(
                {
                    "expected_image_blend_planned": 1,
                    "required_image_blend_succeeded_layer_ids": [1509],
                },
                metrics,
            ),
            [],
        )

        named_metrics = benchmark.named_target_capture_execution_metrics(
            "phase=named-target-capture layer=125 status=failed\n"
            "phase=named-target-capture layer=125 status=succeeded\n"
            "phase=named-target-capture layer=84 status=failed\n"
        )
        self.assertEqual(named_metrics["succeeded_layer_ids"], [125])
        self.assertEqual(named_metrics["failed_layer_ids"], [84])

        binding_metrics = benchmark.named_target_binding_execution_metrics(
            "phase=named-target-binding layer=70 status=failed\n"
            "phase=named-target-binding layer=70 status=succeeded\n"
            "phase=named-target-binding layer=182 status=failed\n"
        )
        self.assertEqual(binding_metrics["succeeded_layer_ids"], [70])
        self.assertEqual(binding_metrics["failed_layer_ids"], [182])
        self.assertEqual(
            benchmark.named_target_binding_failures(
                {"required_named_target_binding_succeeded_layer_ids": [70, 182]},
                2,
                binding_metrics,
            ),
            [
                "named target binding execution below planned count",
                "named target consumer 182 binding should succeed",
            ],
        )

        missing = benchmark.particle_runtime_metrics("loaded: 20 / 24\n")
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "expected_particle_candidates": 0,
                "minimum_particle_initial_live": 0,
            }, missing),
            [
                "particle load evidence missing",
                "particle initial live evidence missing",
            ],
        )


if __name__ == "__main__":
    unittest.main()
