#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_wallpaper_benchmark as benchmark


class SceneWallpaperBenchmarkTests(unittest.TestCase):
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

    def test_default_matrix_pins_solid_layer_semantics(self) -> None:
        matrix = benchmark.load_matrix(SCRIPT_DIR / "scene_wallpaper_sample_matrix.json")
        samples = {sample["id"]: sample for sample in matrix["samples"]}
        expected = {
            "3722933264": (0, 0, 0),
            "3723230275": (1, 0, 1),
            "3723257973": (29, 3, 2),
            "3723344874": (3, 1, 3),
            "3724095562": (0, 0, 0),
            "3724289844": (0, 0, 0),
            "3724553795": (0, 0, 0),
            "3742133044": (0, 0, 0),
            "3750813609": (1, 1, 1),
            "3766387484": (0, 0, 0),
            "2902406982": (9, 6, 1),
            "3765760121": (0, 0, 0),
            "2938612768": (11, 9, 2),
        }
        self.assertEqual(set(samples), set(expected))
        for sample_id, (solid_count, authored_color_count, effective_count) in expected.items():
            sample = samples[sample_id]
            self.assertEqual(sample["expected_interpretation_format"], 14)
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
            [125, 84, 91, 253, 271, 291],
        )
        self.assertEqual(
            sample["required_named_target_binding_succeeded_layer_ids"],
            [70, 791, 182, 217, 245, 265, 285],
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
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/SceneUserProperty.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/SceneUserPropertyDefinitionParser.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/SceneProject.swift"),
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

    def test_interpretation_metrics_preserve_slots_and_combos(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-interpretation-") as directory:
            path = Path(directory) / ".mywallpaperx-scene-interpretation.json"
            path.write_text(
                json.dumps({
                    "formatVersion": 7,
                    "renderDescriptor": {
                        "materialPasses": [{
                            "textureSlots": [None, None, "phase.tex"],
                            "combos": {"VERSION": 2, "MODE": 0},
                        }],
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
                }),
                encoding="utf-8",
            )
            metrics = benchmark.interpretation_metrics(path)
            self.assertEqual(metrics["format_version"], 7)
            self.assertEqual(metrics["effect_texture_slot_count"], 2)
            self.assertEqual(metrics["effect_texture_slot_hole_count"], 1)
            self.assertEqual(metrics["effect_combo_entry_count"], 1)
            self.assertEqual(metrics["material_texture_slot_count"], 3)
            self.assertEqual(metrics["material_texture_slot_hole_count"], 2)
            self.assertEqual(metrics["material_combo_entry_count"], 2)
            self.assertEqual(metrics["visible_layer_count"], 3)
            self.assertEqual(metrics["visible_layer_ids"], [7, 8, 9])
            self.assertEqual(metrics["root_layer_count"], 2)
            self.assertEqual(metrics["child_edge_count"], 2)
            self.assertEqual(metrics["parent_layer_count"], 2)
            self.assertEqual(metrics["max_hierarchy_depth"], 1)
            self.assertEqual(metrics["effective_visible_layer_count"], 2)
            self.assertEqual(metrics["effective_visible_layer_ids"], [8, 9])
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

    def test_interpretation_metrics_reject_invalid_slot_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-interpretation-") as directory:
            path = Path(directory) / ".mywallpaperx-scene-interpretation.json"
            path.write_text(json.dumps({
                "formatVersion": 7,
                "renderDescriptor": {
                    "layers": [{"effects": [{"passes": [{"textureSlots": "bad", "combos": {}}]}]}],
                    "materialPasses": [],
                },
            }), encoding="utf-8")
            metrics = benchmark.interpretation_metrics(path)
            self.assertIsNone(metrics["format_version"])
            self.assertIn("invalid shape", metrics["error"])

    def test_runtime_log_patterns_capture_ready_and_release(self) -> None:
        ready = benchmark.READY_RE.search(
            "MWX DEBUG SCENE: phase=ready root=/tmp/sample layers=35 "
            "imageLayers=24 effects=29 surfaces=1 windows=42 previewLog=/tmp/log "
            "interpretation=/tmp/cache/.mywallpaperx-scene-interpretation.json"
        )
        interpretation = benchmark.INTERPRETATION_RE.search(
            "MWX DEBUG SCENE: phase=ready root=/tmp/sample layers=35 "
            "imageLayers=24 effects=29 surfaces=1 windows=42 previewLog=/tmp/log "
            "interpretation=/tmp/cache/.mywallpaperx-scene-interpretation.json"
        )
        stopped = benchmark.STOPPED_RE.search(
            "MWX DEBUG SCENE: phase=stopped surfacesBefore=1 surfacesAfter=0"
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
            interpretation.group("path"),
            "/tmp/cache/.mywallpaperx-scene-interpretation.json",
        )
        self.assertEqual(stopped.group("after"), "0")
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
