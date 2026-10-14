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


class SceneWallpaperLifecycleTests(unittest.TestCase):
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

    def test_failed_and_passing_runtime_are_removed_without_keep_flag(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-retention-") as directory:
            runtime_root = Path(directory) / "runtime"
            app_root = runtime_root / "runtime-app-fixture"
            runtime_binary = (
                app_root / "MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
            )
            runtime_binary.parent.mkdir(parents=True)
            runtime_binary.write_bytes(b"binary")
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
            app_identity = {
                "runtime_root_path": str(app_root),
                "runtime_bundle_path": str(app_root / "MyWallpaperX.app"),
                "runtime_executable_path": str(runtime_binary),
                "runtime_retained": True,
            }

            benchmark.apply_runtime_retention(
                runtime_root,
                app_identity,
                results,
                keep_runtime=False,
            )

            self.assertFalse((runtime_root / "runtime-samples/1").exists())
            self.assertFalse((runtime_root / "runtime-homes/1").exists())
            self.assertFalse((runtime_root / "runtime-samples/2").exists())
            self.assertFalse((runtime_root / "runtime-homes/2").exists())
            self.assertFalse(results[0]["runtime_retained"])
            self.assertFalse(results[1]["runtime_retained"])
            self.assertFalse(app_identity["runtime_retained"])
            self.assertFalse(runtime_root.exists())

    def test_keep_flag_retains_failed_and_passing_runtime(self) -> None:
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
                keep_runtime=True,
            )

            self.assertTrue((runtime_root / "runtime-samples/1").is_dir())
            self.assertTrue((runtime_root / "runtime-homes/1").is_dir())
            self.assertTrue((runtime_root / "runtime-samples/2").is_dir())
            self.assertTrue((runtime_root / "runtime-homes/2").is_dir())
            self.assertTrue(results[0]["runtime_retained"])
            self.assertTrue(results[1]["runtime_retained"])
            self.assertTrue(app_identity["runtime_retained"])

    def test_runtime_cleanup_retries_read_only_directories(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-retention-") as directory:
            runtime_root = Path(directory) / "runtime"
            runtime_sample = runtime_root / "runtime-samples/1"
            runtime_home = runtime_root / "runtime-homes/1"
            runtime_binary = (
                runtime_root
                / "runtime-app-fixture/MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
            )
            read_only = runtime_sample / "shaders"
            read_only.mkdir(parents=True)
            (read_only / "author-source.frag").write_text("void main() {}")
            read_only.chmod(0o500)
            runtime_home.mkdir(parents=True)
            runtime_binary.parent.mkdir(parents=True)
            runtime_binary.write_bytes(b"binary")
            result = {
                "id": "1",
                "passed": False,
                "runtime_sample": str(runtime_sample),
                "runtime_home": str(runtime_home),
                "runtime_retained": True,
            }
            app_identity = {
                "runtime_root_path": str(runtime_root / "runtime-app-fixture"),
                "runtime_bundle_path": str(
                    runtime_root / "runtime-app-fixture/MyWallpaperX.app"
                ),
                "runtime_executable_path": str(runtime_binary),
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
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyDefinitionParser.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneCompatibilityContext.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Shared/WorkshopPropertyDisplayResolver.swift"),
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


if __name__ == "__main__":
    unittest.main()
