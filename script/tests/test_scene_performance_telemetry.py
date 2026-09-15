#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneFramePerformanceTelemetry.swift"
)
HOST_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
)
HOST_FRAME_DRIVER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+FrameDriver.swift"
)
VIEW_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
)
RENDERER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
)
COUNTER_HUB_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift"
)
DAEMON_RUNTIME_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift"
)
RENDER_COMMAND_SOURCES = [
    REPOSITORY_ROOT / path
    for path in [
        "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneSpotLightPipeline.swift",
        "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift",
        "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift",
        "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLayerColorBlendPipeline.swift",
        "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneMetalPipeline.swift",
        "MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetMeshGeometry.swift",
        "MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetPlaybackState.swift",
        "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneStaticModelPipeline.swift",
    ]
]
DEBUG_RUNNER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner.swift"
PERFORMANCE_RUNNER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner+Performance.swift"
)

HARNESS = r'''
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw NSError(domain: "TelemetryHarness", code: 1)
        }
        let telemetry = SceneFramePerformanceTelemetry()
        telemetry.beginStage("stale-stage")
        telemetry.reset(at: 10, targetFPS: 30)
        telemetry.endStage("stale-stage")
        telemetry.recordDriverCallback(at: 10)
        telemetry.recordDriverCallback(at: 10.02)
        telemetry.recordDriverCallback(at: 10.04)
        telemetry.recordFrameDelta(raw: 0.5, dropped: 0.25)
        telemetry.recordFrameDelta(raw: 0.02, dropped: 0)
        telemetry.recordCPUFrame(duration: 0.010)
        telemetry.recordCPUFrame(duration: 0.020)
        telemetry.recordPreparation(drawableWait: 0.003, preEncode: 0.007)
        telemetry.recordMainFrame(duration: 0.030)
        telemetry.recordSubmitted(on: commandBuffer)
        telemetry.recordPresented(at: 10.100, streamID: 1)
        telemetry.recordPresented(at: 10.116, streamID: 1)
        telemetry.recordPresented(at: 10.156, streamID: 1)
        telemetry.recordPresented(at: 10.200, streamID: 2)
        telemetry.recordPresented(at: 10.260, streamID: 2)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let value = telemetry.snapshot(at: 11)
        let payload: [String: Any] = [
            "elapsed": value.elapsed,
            "callbacks": value.driverCallbacks,
            "submitted": value.submitted,
            "completed": value.completed,
            "failed": value.failed,
            "submittedFPS": value.submittedFPS,
            "completedFPS": value.completedFPS,
            "presented": value.presented,
            "presentStreams": value.presentationStreamCount,
            "presentIntervals": value.presentationIntervalCount,
            "presentP50": value.presentationIntervalP50,
            "presentP95": value.presentationIntervalP95,
            "presentP99": value.presentationIntervalP99,
            "presentMax": value.presentationIntervalMax,
            "presentOver1_5Budget": value.presentationOverOneAndHalfBudget,
            "stages": telemetry.stageSummary().count,
            "callbackP95": value.callbackIntervalP95,
            "callbackOver16": value.callbackOverBudget,
            "discontinuities": value.discontinuityCount,
            "droppedFrameTime": value.droppedFrameTime,
            "maximumRawFrameTime": value.maximumRawFrameTime,
            "cpuP95": value.cpuFrameP95,
            "cpuOver16": value.cpuOverBudget,
            "cpuOver33": value.cpuOverDoubleBudget,
            "drawableWaitP95": value.drawableWaitP95,
            "preEncodeP95": value.preEncodeP95,
            "mainFrameP95": value.mainFrameP95,
            "gpuSamples": value.gpuSampleCount,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

COUNTER_HARNESS = r'''
import Foundation

@main
enum CounterHarness {
    static func main() throws {
        let hub = ScenePerformanceCounterHub()
        hub.bump(.pipelineStateBinds)
        hub.recordDraw(usesGeometry: false)
        hub.recordDraw(usesGeometry: true)
        hub.bump(.fallbackBranches)
        hub.set(.gpuAllocatedBytes, 123_456)
        hub.set(.renderTargetPoolBytes, 65_432)
        let snapshot = hub.snapshot()
        let payload: [String: UInt64] = [
            "slots": UInt64(snapshot.count),
            "drawCalls": snapshot[.drawCalls] ?? 0,
            "pipelineStateBinds": snapshot[.pipelineStateBinds] ?? 0,
            "geometryDrawCalls": snapshot[.geometryDrawCalls] ?? 0,
            "fallbackBranches": snapshot[.fallbackBranches] ?? 0,
            "gpuAllocatedBytes": snapshot[.gpuAllocatedBytes] ?? 0,
            "renderTargetPoolBytes": snapshot[.renderTargetPoolBytes] ?? 0,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class ScenePerformanceTelemetryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-performance-telemetry-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-performance-telemetry"
        compilation = subprocess.run(
            [
                "swiftc",
                str(SOURCE),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_counts_throughput_and_frame_budgets(self) -> None:
        self.assertEqual(self.result["elapsed"], 1)
        self.assertEqual(self.result["callbacks"], 3)
        self.assertEqual(self.result["submitted"], 1)
        self.assertEqual(self.result["completed"], 1)
        self.assertEqual(self.result["failed"], 0)
        self.assertEqual(self.result["submittedFPS"], 1)
        self.assertEqual(self.result["completedFPS"], 1)
        self.assertEqual(self.result["presented"], 5)
        self.assertEqual(self.result["presentStreams"], 2)
        self.assertEqual(self.result["presentIntervals"], 3)
        self.assertAlmostEqual(self.result["presentP50"], 0.04)
        self.assertAlmostEqual(self.result["presentP95"], 0.06)
        self.assertAlmostEqual(self.result["presentP99"], 0.06)
        self.assertAlmostEqual(self.result["presentMax"], 0.06)
        self.assertEqual(self.result["presentOver1_5Budget"], 1)
        self.assertEqual(self.result["stages"], 0)
        self.assertAlmostEqual(self.result["callbackP95"], 0.02)
        self.assertEqual(self.result["callbackOver16"], 2)
        self.assertEqual(self.result["discontinuities"], 1)
        self.assertEqual(self.result["droppedFrameTime"], 0.25)
        self.assertEqual(self.result["maximumRawFrameTime"], 0.5)
        self.assertAlmostEqual(self.result["cpuP95"], 0.02)
        self.assertEqual(self.result["cpuOver16"], 1)
        self.assertEqual(self.result["cpuOver33"], 0)
        self.assertEqual(self.result["drawableWaitP95"], 0.003)
        self.assertEqual(self.result["preEncodeP95"], 0.007)
        self.assertEqual(self.result["mainFrameP95"], 0.03)
        self.assertGreaterEqual(self.result["gpuSamples"], 0)

    def test_runtime_wires_measurement_outside_snapshot_capture(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        renderer = RENDERER_SOURCE.read_text(encoding="utf-8")
        runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        performance_runner = PERFORMANCE_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("debugEvidence.recordDriverCallback()", frame_driver)
        self.assertIn("debugEvidence.recordFrameDelta", frame_driver)
        self.assertIn("performanceTelemetry?.recordPreparation", view)
        self.assertIn("performanceTelemetry?.recordCPUFrame", renderer)
        self.assertIn("performanceTelemetry?.recordSubmitted", renderer)
        self.assertIn("schedulePerformanceMeasurement(", runner)
        self.assertIn("duration: requestedDuration", runner)
        self.assertIn("min(max(duration, 7), 3_600)", runner)
        self.assertIn("afterSnapshotDelay: requestedAfterSnapshotDelay", runner)
        self.assertIn("applyRequestedPerformanceProfile()", runner)
        self.assertIn("PlaybackPerformanceProfile(rawValue: framesPerSecond)", performance_runner)
        self.assertIn("runtimeHost.applyPerformanceProfile(profile)", performance_runner)
        self.assertIn("runtimeHost.performanceProfile.maxFPS", performance_runner)
        self.assertIn("reset(\n                targetFPS: targetFPS", performance_runner)
        self.assertIn("performanceTelemetry?.recordWillPresent", view)
        self.assertIn("drawable.addPresentedHandler", SOURCE.read_text(encoding="utf-8"))
        self.assertIn("presentedDrawable.presentedTime", SOURCE.read_text(encoding="utf-8"))
        self.assertIn("phase=performance", performance_runner)
        self.assertIn("targetFPS=%d", performance_runner)
        self.assertIn("discontinuities=%d", performance_runner)
        self.assertIn("droppedMS=%.3f", performance_runner)
        self.assertIn("debugEvidence.reset(", performance_runner)


class ScenePerformanceCounterHubTests(unittest.TestCase):
    def test_fixed_slots_support_counters_and_resource_gauges(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-counter-hub-") as directory:
            root = Path(directory)
            harness = root / "CounterHarness.swift"
            binary = root / "scene-counter-hub"
            harness.write_text(COUNTER_HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc",
                    str(COUNTER_HUB_SOURCE),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
            result = json.loads(completed.stdout)
        self.assertEqual(result["slots"], 21)
        self.assertEqual(result["drawCalls"], 2)
        self.assertEqual(result["pipelineStateBinds"], 1)
        self.assertEqual(result["geometryDrawCalls"], 1)
        self.assertEqual(result["fallbackBranches"], 1)
        self.assertEqual(result["gpuAllocatedBytes"], 123_456)
        self.assertEqual(result["renderTargetPoolBytes"], 65_432)

    def test_render_commands_record_every_pipeline_bind_and_draw(self) -> None:
        source = "\n".join(
            path.read_text(encoding="utf-8") for path in RENDER_COMMAND_SOURCES
        )
        self.assertEqual(
            source.count("encoder.setRenderPipelineState("),
            source.count(".bump(.pipelineStateBinds)"),
        )
        self.assertEqual(
            source.count("encoder.drawPrimitives(")
            + source.count("encoder.drawIndexedPrimitives("),
            source.count(".recordDraw(usesGeometry:"),
        )

    def test_resource_gauges_are_sampled_at_one_hertz_outside_frame_driver(self) -> None:
        runtime = DAEMON_RUNTIME_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("self.host.refreshPerformanceResourceGauges()", runtime)
        self.assertIn("repeating: 1", runtime)
        self.assertNotIn("refreshPerformanceResourceGauges", frame_driver)


if __name__ == "__main__":
    unittest.main()
