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


class SceneWallpaperPerformanceTests(unittest.TestCase):
    def test_performance_metrics_parse_v7_evidence_and_normalize_surfaces(self) -> None:
        log = (
            "MWX DEBUG SCENE: phase=performance targetFPS=60 warmupSeconds=30 "
            "elapsed=6.833 callbacks=410 "
            "submitted=410 completed=409 failed=0 submittedFPS=60.004 "
            "completedFPS=59.857 presented=408 presentStreams=1 presentIntervals=407 "
            "presentP50MS=16.667 presentP95MS=16.700 presentP99MS=20.000 "
            "presentMaxMS=34.000 presentOver1_5Budget=1 "
            "callbackP50MS=16.666 callbackP95MS=16.698 "
            "callbackMaxMS=17.171 callbackOver16=199 callbackOver33=0 "
            "discontinuities=1 droppedMS=750.000 maxRawFrameMS=1000.000 "
            "drawableMissed=0 drawableWaitP95MS=0.013 drawableWaitMaxMS=0.034 "
            "preEncodeP95MS=7.671 preEncodeMaxMS=7.868 mainFrameP95MS=8.097 "
            "mainFrameMaxMS=8.311 cpuP50MS=0.348 cpuP95MS=0.380 "
            "cpuMaxMS=0.578 cpuOver16=0 cpuOver33=0 gpuSamples=409 "
            "gpuP50MS=2.279 gpuP95MS=3.886 gpuMaxMS=4.752 "
            "gpuOver16=0 gpuOver33=0\n"
            "MWX DEBUG SCENE: phase=performance-stages "
            "layer-loop=p50:4.000ms p95:5.500ms n:407 "
            "prologue=p50:1.000ms p95:1.500ms n:407\n"
            "MWX DEBUG SCENE: phase=performance-resources samples=8 "
            "processSamples=8 processFootprintSampledPeakBytes=134217728 "
            "processCPUTimeMS=2387.500 processCPUTimeStatus=available "
            "gpuAllocatedSampledPeakBytes=67108864 "
            "renderTargetPoolSampledPeakBytes=33554432"
        )
        metrics = benchmark.performance_metrics(log, surface_count=1)
        self.assertTrue(metrics["available"])
        self.assertEqual(metrics["target_fps"], 60)
        self.assertEqual(metrics["measurement_warmup_seconds"], 30)
        self.assertFalse(metrics["steady_state_eligible"])
        self.assertEqual(
            metrics["steady_state_ineligible_reasons"],
            ["measurement elapsed is below 60 seconds"],
        )
        self.assertEqual(metrics["driver_callbacks"], 410)
        self.assertAlmostEqual(metrics["driver_fps"], 410 / 6.833)
        self.assertEqual(metrics["completed_frames"], 409)
        self.assertEqual(metrics["callback_over_16_67_ms"], 199)
        self.assertEqual(metrics["discontinuity_count"], 1)
        self.assertEqual(metrics["dropped_frame_time_ms"], 750)
        self.assertEqual(metrics["maximum_raw_frame_time_ms"], 1000)
        self.assertAlmostEqual(metrics["completed_fps_per_surface"], 59.857)
        self.assertAlmostEqual(metrics["actual_present_p99_ms"], 20)
        self.assertAlmostEqual(
            metrics["actual_present_over_1_5_budget_ratio"],
            1 / 407,
        )
        self.assertAlmostEqual(metrics["pre_encode_p95_ms"], 7.671)
        self.assertAlmostEqual(metrics["gpu_frame_p95_ms"], 3.886)
        self.assertEqual(
            metrics["cpu_stages"]["highest_p95"],
            {"name": "layer-loop", "milliseconds": 5.5},
        )
        self.assertEqual(
            metrics["cpu_stages"]["stages"]["prologue"],
            {"p50_ms": 1.0, "p95_ms": 1.5, "sample_count": 407},
        )
        self.assertEqual(
            metrics["resources"]["process_footprint_sampled_peak_bytes"],
            134_217_728,
        )
        self.assertAlmostEqual(metrics["resources"]["process_cpu_time_ms"], 2387.5)
        self.assertEqual(
            metrics["resources"]["gpu_allocated_sampled_peak_bytes"],
            67_108_864,
        )
        two_surface_log = log.replace(
            "presented=408 presentStreams=1 presentIntervals=407",
            "presented=408 presentStreams=2 presentIntervals=406",
            1,
        )
        two_surface = benchmark.performance_metrics(two_surface_log, surface_count=2)
        self.assertAlmostEqual(two_surface["completed_fps_per_surface"], 29.9285)
        self.assertEqual(benchmark.performance_failures(metrics), [])

    def test_performance_gpu_census_is_optional_but_strict_when_present(self) -> None:
        census_line = (
            "phase=performance-gpu frames=60 mainPassRenders=180 "
            "depthRenders=12 offscreenRenders=240 resolvedMaterialRenders=96 "
            "graphResourceSourceCaptures=72 graphResourceInitializations=48 "
            "offscreenEffectCaptures=24 textureCopyPasses=40 "
            "framebufferCaptures=6 framebufferCaptureBytes=49766400 "
            "graphOutputPublicationCopies=4 textureCopyBytes=82944000 "
            "unmeasuredCopyPasses=0"
        )
        # 旧日志没有普查行：保持可解析，不因新增观测让既有证据失效。
        self.assertIsNone(benchmark.performance_gpu_census_metrics(""))
        census = benchmark.performance_gpu_census_metrics(census_line)
        self.assertTrue(census["available"])
        self.assertEqual(census["frames"], 60)
        self.assertEqual(census["main_pass_render_passes"], 180)
        self.assertEqual(census["depth_render_passes"], 12)
        self.assertEqual(census["offscreen_render_passes"], 240)
        self.assertEqual(census["resolved_material_render_passes"], 96)
        self.assertEqual(census["graph_resource_source_captures"], 72)
        self.assertEqual(census["graph_resource_initializations"], 48)
        self.assertEqual(census["offscreen_effect_captures"], 24)
        self.assertEqual(census["texture_copy_passes"], 40)
        self.assertEqual(census["framebuffer_captures"], 6)
        self.assertEqual(census["framebuffer_capture_bytes"], 49_766_400)
        self.assertEqual(census["graph_output_publication_copies"], 4)
        self.assertEqual(census["texture_copy_bytes"], 82_944_000)
        self.assertEqual(census["unmeasured_copy_passes"], 0)
        self.assertAlmostEqual(
            census["per_frame"]["main_pass_render_passes"], 3.0
        )
        self.assertAlmostEqual(census["per_frame"]["framebuffer_captures"], 0.1)
        self.assertNotIn("frames", census["per_frame"])
        # 行存在但缺字段、重复、零帧或内部矛盾时，性能证据必须整体失败。
        missing = census_line.replace(" depthRenders=12", "", 1)
        self.assertIn(
            "missing performance gpu census fields",
            benchmark.performance_gpu_census_metrics(missing)["error"],
        )
        duplicate = census_line.replace("frames=60", "frames=60 frames=60", 1)
        self.assertIn(
            "duplicate performance gpu census field",
            benchmark.performance_gpu_census_metrics(duplicate)["error"],
        )
        zero_frames = census_line.replace("frames=60", "frames=0", 1)
        self.assertIn(
            "frames must be positive",
            benchmark.performance_gpu_census_metrics(zero_frames)["error"],
        )
        inconsistent = census_line.replace("depthRenders=12", "depthRenders=999", 1)
        self.assertIn(
            "exceeds",
            benchmark.performance_gpu_census_metrics(inconsistent)["error"],
        )
        # 四个 offscreen 类别必须恰好分割 offscreen 总数，否则说明有编码点漏分类。
        unpartitioned = census_line.replace(
            "offscreenEffectCaptures=24", "offscreenEffectCaptures=23", 1
        )
        self.assertIn(
            "do not partition offscreen renders",
            benchmark.performance_gpu_census_metrics(unpartitioned)["error"],
        )
        self.assertIn(
            "expected one performance gpu census event",
            benchmark.performance_gpu_census_metrics(
                census_line + "\n" + census_line
            )["error"],
        )
        # 普查行不能被当成 phase=performance 或 stage 事件。
        metrics = benchmark.performance_metrics(census_line, 1)
        self.assertIn("expected one performance event", metrics["error"])
        valid_log = (
            "phase=performance targetFPS=60 warmupSeconds=30 elapsed=1 "
            "callbacks=60 submitted=60 "
            "completed=60 failed=0 submittedFPS=60 completedFPS=60 presented=60 "
            "presentStreams=1 presentIntervals=59 presentP50MS=16 presentP95MS=17 "
            "presentP99MS=18 presentMaxMS=20 presentOver1_5Budget=0 "
            "callbackP50MS=16 callbackP95MS=17 callbackMaxMS=18 callbackOver16=1 "
            "callbackOver33=0 discontinuities=0 droppedMS=0 maxRawFrameMS=18 "
            "drawableMissed=0 drawableWaitP95MS=0 drawableWaitMaxMS=0 "
            "preEncodeP95MS=1 preEncodeMaxMS=1 mainFrameP95MS=2 mainFrameMaxMS=2 "
            "cpuP50MS=1 cpuP95MS=1 cpuMaxMS=1 cpuOver16=0 cpuOver33=0 "
            "gpuSamples=60 gpuP50MS=1 gpuP95MS=1 gpuMaxMS=1 gpuOver16=0 gpuOver33=0\n"
            "phase=performance-stages layer-loop=p50:1ms p95:2ms n:60\n"
            "phase=performance-resources samples=2 processSamples=2 "
            "processFootprintSampledPeakBytes=100 processCPUTimeMS=200 "
            "processCPUTimeStatus=available "
            "gpuAllocatedSampledPeakBytes=300 renderTargetPoolSampledPeakBytes=400"
        )
        without_census = benchmark.performance_metrics(valid_log, 1)
        self.assertTrue(without_census["available"])
        self.assertNotIn("gpu_census", without_census)
        with_census = benchmark.performance_metrics(
            valid_log + "\n" + census_line, 1
        )
        self.assertTrue(with_census["available"])
        self.assertEqual(
            with_census["gpu_census"]["graph_output_publication_copies"], 4
        )
        broken_census = benchmark.performance_metrics(
            valid_log + "\n" + zero_frames, 1
        )
        self.assertFalse(broken_census["available"])
        self.assertIn("performance gpu census unavailable", broken_census["error"])

    def test_performance_metrics_fail_closed_on_missing_or_malformed_evidence(self) -> None:
        self.assertIn(
            "expected one performance event",
            benchmark.performance_metrics("", 1)["error"],
        )
        duplicate = (
            "phase=performance elapsed=1 elapsed=2\n"
        )
        self.assertIn("duplicate performance field", benchmark.performance_metrics(duplicate, 1)["error"])
        missing = "phase=performance elapsed=1 callbacks=60"
        self.assertIn("missing performance fields", benchmark.performance_metrics(missing, 1)["error"])
        valid_log = (
            "phase=performance targetFPS=60 warmupSeconds=30 elapsed=1 "
            "callbacks=60 submitted=60 "
            "completed=60 failed=0 submittedFPS=60 completedFPS=60 presented=60 "
            "presentStreams=1 presentIntervals=59 presentP50MS=16 presentP95MS=17 "
            "presentP99MS=18 presentMaxMS=20 presentOver1_5Budget=0 "
            "callbackP50MS=16 callbackP95MS=17 callbackMaxMS=18 callbackOver16=1 "
            "callbackOver33=0 discontinuities=0 droppedMS=0 maxRawFrameMS=18 "
            "drawableMissed=0 drawableWaitP95MS=0 drawableWaitMaxMS=0 "
            "preEncodeP95MS=1 preEncodeMaxMS=1 mainFrameP95MS=2 mainFrameMaxMS=2 "
            "cpuP50MS=1 cpuP95MS=1 cpuMaxMS=1 cpuOver16=0 cpuOver33=0 "
            "gpuSamples=60 gpuP50MS=1 gpuP95MS=1 gpuMaxMS=1 gpuOver16=0 gpuOver33=0\n"
            "phase=performance-stages layer-loop=p50:1ms p95:2ms n:60\n"
            "phase=performance-resources samples=2 processSamples=2 "
            "processFootprintSampledPeakBytes=100 processCPUTimeMS=200 "
            "processCPUTimeStatus=available "
            "gpuAllocatedSampledPeakBytes=300 renderTargetPoolSampledPeakBytes=400"
        )
        invalid_target = valid_log.replace("targetFPS=60", "targetFPS=45", 1)
        self.assertIn(
            "target FPS must be 30 or 60",
            benchmark.performance_metrics(invalid_target, 1)["error"],
        )
        missing_stream = valid_log.replace("presentStreams=1", "presentStreams=0", 1)
        self.assertIn(
            "stream count does not match surfaces",
            benchmark.performance_metrics(missing_stream, 1)["error"],
        )
        missing_intervals = valid_log.replace("presentIntervals=59", "presentIntervals=0", 1)
        self.assertIn(
            "interval identity mismatch",
            benchmark.performance_metrics(missing_intervals, 1)["error"],
        )
        missing_stages = valid_log.split("\nphase=performance-stages", 1)[0]
        self.assertIn(
            "expected one performance stages event",
            benchmark.performance_metrics(missing_stages, 1)["error"],
        )
        per_call_stages = "phase=performance-stages layer-loop=p50:1ms p95:2ms n:60\n"
        frame_stages = (
            "phase=performance-stages-frames "
            "admit-executor-prepare=p50:2.000ms p95:2.500ms n:60\n"
        )
        # 没有 frames 行时该视图缺席，旧日志保持可解析。
        self.assertIsNone(
            benchmark.performance_frame_stage_metrics(per_call_stages)
        )
        frames_metrics = benchmark.performance_frame_stage_metrics(
            per_call_stages + frame_stages
        )
        self.assertIsNotNone(frames_metrics)
        self.assertTrue(frames_metrics["available"])
        self.assertEqual(
            sorted(frames_metrics["stages"]), ["admit-executor-prepare"]
        )
        # frames 行绝不能被当成第二个 per-call 事件，否则整项性能证据会失效。
        both = benchmark.performance_stage_metrics(per_call_stages + frame_stages)
        self.assertTrue(both["available"])
        self.assertEqual(sorted(both["stages"]), ["layer-loop"])
        # 只有 frames 行时仍必须判定缺少 per-call 阶段事件。
        only_frames = benchmark.performance_stage_metrics(frame_stages)
        self.assertFalse(only_frames["available"])
        self.assertIn(
            "expected one performance stages event", only_frames["error"]
        )
        duplicate_stage = valid_log.replace(
            "layer-loop=p50:1ms p95:2ms n:60",
            "layer-loop=p50:1ms p95:2ms n:60 "
            "layer-loop=p50:1ms p95:2ms n:60",
            1,
        )
        self.assertIn(
            "duplicate performance stage",
            benchmark.performance_metrics(duplicate_stage, 1)["error"],
        )
        malformed_stage = valid_log.replace(
            "layer-loop=p50:1ms p95:2ms n:60",
            "layer-loop=p50:1ms p95:2ms n:60 trailing-token",
            1,
        )
        self.assertIn(
            "invalid performance stage token",
            benchmark.performance_metrics(malformed_stage, 1)["error"],
        )
        inverted_stage = valid_log.replace("p50:1ms p95:2ms", "p50:2ms p95:1ms", 1)
        self.assertIn(
            "invalid performance stage p95",
            benchmark.performance_metrics(inverted_stage, 1)["error"],
        )
        empty_stage = valid_log.replace("n:60", "n:0", 1)
        self.assertIn(
            "invalid performance stage sample count",
            benchmark.performance_metrics(empty_stage, 1)["error"],
        )
        missing_resources = valid_log.split("\nphase=performance-resources", 1)[0]
        self.assertIn(
            "expected one performance resources event",
            benchmark.performance_metrics(missing_resources, 1)["error"],
        )
        duplicate_resource = valid_log.replace(
            "samples=2 processSamples=2",
            "samples=2 samples=2 processSamples=2",
            1,
        )
        self.assertIn(
            "duplicate performance resource field",
            benchmark.performance_metrics(duplicate_resource, 1)["error"],
        )
        insufficient_resources = valid_log.replace("samples=2", "samples=1", 1)
        self.assertIn(
            "at least two samples",
            benchmark.performance_metrics(insufficient_resources, 1)["error"],
        )
        mismatched_resources = valid_log.replace("processSamples=2", "processSamples=1", 1)
        self.assertIn(
            "process sample identity mismatch",
            benchmark.performance_metrics(mismatched_resources, 1)["error"],
        )
        negative_resource = valid_log.replace("processCPUTimeMS=200", "processCPUTimeMS=-1", 1)
        self.assertIn(
            "invalid performance resource field",
            benchmark.performance_metrics(negative_resource, 1)["error"],
        )
        unavailable_cpu = valid_log.replace(
            "processCPUTimeMS=200 processCPUTimeStatus=available",
            "processCPUTimeMS=unavailable processCPUTimeStatus=tick-counter-regressed",
            1,
        )
        self.assertIn(
            "process CPU time unavailable: tick-counter-regressed",
            benchmark.performance_metrics(unavailable_cpu, 1)["error"],
        )
        unknown_cpu_status = valid_log.replace(
            "processCPUTimeStatus=available",
            "processCPUTimeStatus=unknown",
            1,
        )
        self.assertIn(
            "invalid process CPU time status",
            benchmark.performance_metrics(unknown_cpu_status, 1)["error"],
        )
        sparse_resources = valid_log.replace("elapsed=1", "elapsed=60", 1)
        self.assertIn(
            "sample density is below one hertz",
            benchmark.performance_metrics(sparse_resources, 1)["error"],
        )

        steady_state = (
            valid_log.replace("elapsed=1", "elapsed=60", 1)
            .replace("samples=2 processSamples=2", "samples=60 processSamples=60", 1)
        )
        self.assertTrue(
            benchmark.performance_metrics(steady_state, 1)["steady_state_eligible"]
        )

    def test_performance_summary_preserves_worst_sample_identity(self) -> None:
        results = [
            {
                "id": "fast",
                "runtime": {
                    "startup_ready_ms": 800.0,
                    "performance": {
                        "available": True,
                        "driver_fps": 60.0,
                        "actual_present_p99_ms": 17.0,
                        "steady_state_eligible": True,
                    },
                },
            },
            {
                "id": "slow",
                "runtime": {
                    "startup_ready_ms": 1800.0,
                    "performance": {
                        "available": True,
                        "driver_fps": 48.0,
                        "actual_present_p99_ms": 29.0,
                        "steady_state_eligible": False,
                    },
                },
            },
            {"id": "missing", "runtime": {"performance": {"available": False}}},
        ]
        summary = benchmark.summarize_performance(results)
        self.assertEqual(summary["available_count"], 2)
        self.assertEqual(summary["unavailable_count"], 1)
        self.assertEqual(summary["steady_state_eligible_count"], 1)
        self.assertEqual(summary["steady_state_eligible_ids"], ["fast"])
        self.assertEqual(summary["lowest_driver_fps"], {"id": "slow", "fps": 48.0})
        self.assertEqual(
            summary["slowest_startup_ready_ms"],
            {"id": "slow", "milliseconds": 1800.0},
        )
        self.assertEqual(
            summary["highest_actual_present_p99_ms"],
            {"id": "slow", "milliseconds": 29.0},
        )

    def test_benchmark_duration_is_finite_and_supports_steady_state_runs(self) -> None:
        self.assertEqual(benchmark.bounded_duration("0"), 7)
        self.assertEqual(benchmark.bounded_duration("65"), 65)
        self.assertEqual(benchmark.bounded_duration("1800"), 1800)
        for invalid in ("nan", "inf", "3600.1", "invalid"):
            with self.assertRaises(benchmark.argparse.ArgumentTypeError):
                benchmark.bounded_duration(invalid)

    def test_performance_profile_argument_is_explicit_and_bounded(self) -> None:
        for frames_per_second in (30, 60):
            command = ["MyWallpaperX"]
            benchmark.append_performance_profile_argument(
                command,
                frames_per_second,
            )
            self.assertEqual(command, [
                "MyWallpaperX",
                "--mwx-debug-scene-performance-fps",
                str(frames_per_second),
            ])
        with self.assertRaisesRegex(ValueError, "30 or 60 FPS"):
            benchmark.append_performance_profile_argument([], 45)

    def test_performance_warmup_argument_is_explicit_and_bounded(self) -> None:
        command = ["MyWallpaperX"]
        benchmark.append_performance_warmup_argument(command, 30)
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-performance-warmup",
            "30",
        ])
        unchanged = ["MyWallpaperX"]
        benchmark.append_performance_warmup_argument(unchanged, None)
        self.assertEqual(unchanged, ["MyWallpaperX"])
        for invalid in (-1, float("nan"), float("inf")):
            with self.assertRaisesRegex(ValueError, "finite and nonnegative"):
                benchmark.append_performance_warmup_argument([], invalid)

    def test_performance_profile_is_explicit_and_defaults_to_standard(self) -> None:
        old_argv = sys.argv
        try:
            sys.argv = [
                "scene_wallpaper_benchmark.py",
                "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples",
                "--output-dir", "/tmp/results",
            ]
            default_args = benchmark.parse_args()
            sys.argv.extend([
                "--performance-fps", "30",
                "--performance-warmup", "30",
            ])
            efficient_args = benchmark.parse_args()
        finally:
            sys.argv = old_argv
        self.assertEqual(default_args.performance_fps, 60)
        self.assertIsNone(default_args.performance_warmup)
        self.assertEqual(efficient_args.performance_fps, 30)
        self.assertEqual(efficient_args.performance_warmup, 30)


if __name__ == "__main__":
    unittest.main()
