#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFramePerformanceTelemetry.swift"
)
HOST_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift"
)
HOST_FRAME_DRIVER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
)
VIEW_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift"
)
RENDERER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalRenderer.swift"
)
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
        telemetry.reset(at: 10)
        telemetry.recordDriverCallback(at: 10)
        telemetry.recordDriverCallback(at: 10.02)
        telemetry.recordDriverCallback(at: 10.04)
        telemetry.recordCPUFrame(duration: 0.010)
        telemetry.recordCPUFrame(duration: 0.020)
        telemetry.recordPreparation(drawableWait: 0.003, preEncode: 0.007)
        telemetry.recordMainFrame(duration: 0.030)
        telemetry.recordSubmitted(on: commandBuffer)
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
            "callbackP95": value.callbackIntervalP95,
            "callbackOver16": value.callbackOverBudget,
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
        self.assertAlmostEqual(self.result["callbackP95"], 0.02)
        self.assertEqual(self.result["callbackOver16"], 2)
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
        self.assertIn("performanceTelemetry?.recordPreparation", view)
        self.assertIn("performanceTelemetry?.recordCPUFrame", renderer)
        self.assertIn("performanceTelemetry?.recordSubmitted", renderer)
        self.assertIn("schedulePerformanceMeasurement(", runner)
        self.assertIn("duration: requestedDuration", runner)
        self.assertIn("afterSnapshotDelay: requestedAfterSnapshotDelay", runner)
        self.assertIn("phase=performance", performance_runner)
        self.assertIn("debugEvidence.reset()", performance_runner)


if __name__ == "__main__":
    unittest.main()
