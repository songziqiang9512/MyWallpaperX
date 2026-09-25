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
PROCESS_CPU_TIME_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner+ProcessCPUTime.swift"
)
PARTICLE_PLAYBACK_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView+ParticlePlayback.swift"
)
PREFLIGHT_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
)
SUBMISSION_COORDINATOR_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift"
)
GPU_CENSUS_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift"
)
MAIN_PASS_ENCODER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneMainPassEncoder.swift"
)
GRAPH_RESOURCE_PASS_ENCODER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneGraphResourcePassEncoder.swift"
)
MATERIAL_PASS_ENCODER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift"
)
OFFSCREEN_EFFECT_ENCODER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift"
)
FRAMEBUFFER_SNAPSHOT_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFramebufferSnapshot.swift"
)
DEPENDENCY_FRAME_RUNTIME_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyFrameRuntime.swift"
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
        // Per-frame aggregation: nested-stage runs twice inside the first frame
        // and once inside the second, so the per-frame view holds two samples
        // (the first being the sum of its two calls) while the per-call view
        // holds three. The two existing frame boundaries are reused so the
        // CPU-frame statistics asserted below stay unchanged.
        for _ in 0..<2 {
            telemetry.beginStage("nested-stage")
            Thread.sleep(forTimeInterval: 0.002)
            telemetry.endStage("nested-stage")
        }
        telemetry.beginStage("flat-stage")
        Thread.sleep(forTimeInterval: 0.001)
        telemetry.endStage("flat-stage")
        telemetry.recordCPUFrame(duration: 0.010)
        telemetry.beginStage("nested-stage")
        Thread.sleep(forTimeInterval: 0.001)
        telemetry.endStage("nested-stage")
        telemetry.recordCPUFrame(duration: 0.020)
        telemetry.recordPreparation(drawableWait: 0.003, preEncode: 0.007)
        telemetry.recordMainFrame(duration: 0.030)
        telemetry.recordParticleSubmission(
            [
                .init(layerID: 984, instanceCount: 3, isRefraction: true),
                .init(layerID: 984, instanceCount: 2, isRefraction: false),
                .init(layerID: 12, instanceCount: 1, isRefraction: false),
            ],
            on: commandBuffer
        )
        telemetry.recordSubmitted(on: commandBuffer)
        telemetry.recordPresented(at: 10.100, streamID: 1)
        telemetry.recordPresented(at: 10.116, streamID: 1)
        telemetry.recordPresented(at: 10.156, streamID: 1)
        telemetry.recordPresented(at: 10.200, streamID: 2)
        telemetry.recordPresented(at: 10.260, streamID: 2)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard let staleCommandBuffer = queue.makeCommandBuffer() else {
            throw NSError(domain: "TelemetryHarness", code: 2)
        }
        let staleTelemetry = SceneFramePerformanceTelemetry()
        staleTelemetry.recordParticleSubmission(
            [.init(layerID: 77, instanceCount: 4, isRefraction: true)],
            on: staleCommandBuffer
        )
        staleTelemetry.reset(at: 20, targetFPS: 60)
        staleCommandBuffer.commit()
        staleCommandBuffer.waitUntilCompleted()
        let frameStages = telemetry.frameStageSummary()
        let callStages = telemetry.stageSummary()
        let value = telemetry.snapshot(at: 11)
        let particleLayers = telemetry.particleLayerSnapshot()
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
            "stages": callStages.count,
            "staleStageRecorded": callStages["stale-stage"] != nil,
            "frameNestedCount": frameStages["nested-stage"]?.count ?? -1,
            "frameFlatCount": frameStages["flat-stage"]?.count ?? -1,
            "callNestedCount": callStages["nested-stage"]?.count ?? -1,
            "frameNestedP50MS": (frameStages["nested-stage"]?.p50 ?? 0) * 1_000,
            "frameNestedP95MS": (frameStages["nested-stage"]?.p95 ?? 0) * 1_000,
            "frameFlatP50MS": (frameStages["flat-stage"]?.p50 ?? 0) * 1_000,
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
            "particle984SubmittedFrames": particleLayers[984]?.submittedFrames ?? -1,
            "particle984CompletedFrames": particleLayers[984]?.completedFrames ?? -1,
            "particle984FailedFrames": particleLayers[984]?.failedFrames ?? -1,
            "particle984EncodedBatches": particleLayers[984]?.encodedBatches ?? -1,
            "particle984CompletedBatches": particleLayers[984]?.completedBatches ?? -1,
            "particle984EncodedInstances": particleLayers[984]?.encodedInstances ?? -1,
            "particle984CompletedInstances": particleLayers[984]?.completedInstances ?? -1,
            "particle984RefractionBatches": particleLayers[984]?.refractionBatches ?? -1,
            "particle984CompletedRefractionBatches": particleLayers[984]?.completedRefractionBatches ?? -1,
            "particle12SubmittedFrames": particleLayers[12]?.submittedFrames ?? -1,
            "particle12EncodedBatches": particleLayers[12]?.encodedBatches ?? -1,
            "particle12EncodedInstances": particleLayers[12]?.encodedInstances ?? -1,
            "staleParticleLayerCount": staleTelemetry.particleLayerSnapshot().count,
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
        hub.recordMainPassRender(usesDepth: false)
        hub.recordMainPassRender(usesDepth: true)
        hub.recordOffscreenRender(.resolvedMaterial)
        hub.recordOffscreenRender(.resolvedMaterial)
        hub.recordOffscreenRender(.graphResourceSourceCapture)
        hub.recordOffscreenRender(.graphResourceInitialization)
        hub.recordOffscreenRender(.offscreenEffectCapture)
        hub.recordFramebufferCapture(byteCount: 8_294_400)
        hub.recordGraphOutputPublication(byteCount: 4_147_200)
        hub.recordTextureCopy(byteCount: 2_073_600)
        hub.recordTextureCopy(byteCount: nil)
        let snapshot = hub.snapshot()
        let payload: [String: UInt64] = [
            "slots": UInt64(snapshot.count),
            "drawCalls": snapshot[.drawCalls] ?? 0,
            "pipelineStateBinds": snapshot[.pipelineStateBinds] ?? 0,
            "geometryDrawCalls": snapshot[.geometryDrawCalls] ?? 0,
            "fallbackBranches": snapshot[.fallbackBranches] ?? 0,
            "gpuAllocatedBytes": snapshot[.gpuAllocatedBytes] ?? 0,
            "renderTargetPoolBytes": snapshot[.renderTargetPoolBytes] ?? 0,
            "mainPassRenderPasses": snapshot[.mainPassRenderPasses] ?? 0,
            "depthRenderPasses": snapshot[.depthRenderPasses] ?? 0,
            "offscreenRenderPasses": snapshot[.offscreenRenderPasses] ?? 0,
            "textureCopyPasses": snapshot[.textureCopyPasses] ?? 0,
            "framebufferCaptures": snapshot[.framebufferCaptures] ?? 0,
            "framebufferCaptureBytes": snapshot[.framebufferCaptureBytes] ?? 0,
            "graphOutputPublicationCopies": snapshot[.graphOutputPublicationCopies] ?? 0,
            "textureCopyBytes": snapshot[.textureCopyBytes] ?? 0,
            "unmeasuredCopyPasses": snapshot[.unmeasuredCopyPasses] ?? 0,
            "resolvedMaterialRenderPasses": snapshot[.resolvedMaterialRenderPasses] ?? 0,
            "graphResourceSourceCaptures": snapshot[.graphResourceSourceCaptures] ?? 0,
            "graphResourceInitializations": snapshot[.graphResourceInitializations] ?? 0,
            "offscreenEffectCaptures": snapshot[.offscreenEffectCaptures] ?? 0,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

GPU_CENSUS_HARNESS = r'''
import Foundation
import Metal

@main
enum GPUCensusHarness {
    static func main() throws {
        func texture(
            _ format: MTLPixelFormat,
            width: Int,
            height: Int
        ) -> MTLTexture? {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .renderTarget]
            return device.makeTexture(descriptor: descriptor)
        }

        guard let bgra = texture(.bgra8Unorm, width: 16, height: 8),
              let unknown = texture(.a8Unorm, width: 16, height: 8) else {
            throw NSError(domain: "GPUCensusHarness", code: 1)
        }
        SceneGPUCensus.recordMainPassRender(usesDepth: false)
        SceneGPUCensus.recordMainPassRender(usesDepth: true)
        SceneGPUCensus.recordOffscreenRender(.resolvedMaterial)
        SceneGPUCensus.recordOffscreenRender(.graphResourceInitialization)
        SceneGPUCensus.recordFramebufferCapture(texture: bgra)
        SceneGPUCensus.recordGraphOutputPublication(texture: bgra)
        SceneGPUCensus.recordTextureCopy(texture: bgra)
        SceneGPUCensus.recordTextureCopy(texture: unknown)
        let snapshot = ScenePerformanceCounterHub.shared.snapshot()
        let payload: [String: UInt64] = [
            "mainPassRenderPasses": snapshot[.mainPassRenderPasses] ?? 0,
            "depthRenderPasses": snapshot[.depthRenderPasses] ?? 0,
            "offscreenRenderPasses": snapshot[.offscreenRenderPasses] ?? 0,
            "textureCopyPasses": snapshot[.textureCopyPasses] ?? 0,
            "framebufferCaptures": snapshot[.framebufferCaptures] ?? 0,
            "framebufferCaptureBytes": snapshot[.framebufferCaptureBytes] ?? 0,
            "graphOutputPublicationCopies": snapshot[.graphOutputPublicationCopies] ?? 0,
            "textureCopyBytes": snapshot[.textureCopyBytes] ?? 0,
            "unmeasuredCopyPasses": snapshot[.unmeasuredCopyPasses] ?? 0,
            "resolvedMaterialRenderPasses": snapshot[.resolvedMaterialRenderPasses] ?? 0,
            "graphResourceSourceCaptures": snapshot[.graphResourceSourceCaptures] ?? 0,
            "graphResourceInitializations": snapshot[.graphResourceInitializations] ?? 0,
            "offscreenEffectCaptures": snapshot[.offscreenEffectCaptures] ?? 0,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

PROCESS_CPU_TIME_HARNESS = r'''
import Darwin
import Foundation

@main
enum ProcessCPUTimeHarness {
    static func main() throws {
        let combined: UInt64
        switch DebugSceneProcessCPUTime.combinedMachTicks(
            userMachTicks: 100,
            systemMachTicks: 50
        ) {
        case let .success(value): combined = value
        case let .failure(error): throw error
        }

        let timebase = DebugSceneProcessCPUTime.Timebase(
            numerator: 125,
            denominator: 3
        )
        let elapsedMilliseconds: Double
        switch DebugSceneProcessCPUTime.elapsedMilliseconds(
            firstMachTicks: 1_000,
            latestMachTicks: 1_003,
            timebase: timebase
        ) {
        case let .success(value): elapsedMilliseconds = value
        case let .failure(error): throw error
        }

        func failure<T>(
            _ result: Result<T, DebugSceneProcessCPUTime.Failure>
        ) -> String {
            switch result {
            case .success:
                return "unexpected-success"
            case let .failure(error):
                return error.rawValue
            }
        }

        let payload: [String: Any] = [
            "combined": combined,
            "elapsedMilliseconds": elapsedMilliseconds,
            "sumOverflow": failure(
                DebugSceneProcessCPUTime.combinedMachTicks(
                    userMachTicks: UInt64.max,
                    systemMachTicks: 1
                )
            ),
            "regressed": failure(
                DebugSceneProcessCPUTime.elapsedMilliseconds(
                    firstMachTicks: 2,
                    latestMachTicks: 1,
                    timebase: timebase
                )
            ),
            "timebaseFailure": failure(
                DebugSceneProcessCPUTime.validatedTimebase(
                    status: KERN_FAILURE,
                    numerator: 125,
                    denominator: 3
                )
            ),
            "invalidTimebase": failure(
                DebugSceneProcessCPUTime.validatedTimebase(
                    status: KERN_SUCCESS,
                    numerator: 125,
                    denominator: 0
                )
            ),
            "conversionOverflow": failure(
                DebugSceneProcessCPUTime.elapsedMilliseconds(
                    firstMachTicks: 0,
                    latestMachTicks: UInt64.max,
                    timebase: .init(numerator: UInt32.max, denominator: 1)
                )
            ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
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
        self.assertEqual(self.result["stages"], 2)
        self.assertFalse(self.result["staleStageRecorded"])
        # Per-frame aggregation: nested-stage ran twice in frame one and once in
        # frame two, so the per-frame view has two samples while the per-call
        # view has three, and frame one's total is the sum of its two calls.
        self.assertEqual(self.result["callNestedCount"], 3)
        self.assertEqual(self.result["frameNestedCount"], 2)
        self.assertEqual(self.result["frameFlatCount"], 1)
        self.assertGreaterEqual(self.result["frameNestedP95MS"], 3.0)
        self.assertGreater(self.result["frameNestedP50MS"], 0.5)
        self.assertLessEqual(
            self.result["frameNestedP50MS"], self.result["frameNestedP95MS"]
        )
        self.assertGreaterEqual(self.result["frameFlatP50MS"], 0.5)
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
        self.assertEqual(self.result["particle984SubmittedFrames"], 1)
        self.assertEqual(self.result["particle984CompletedFrames"], 1)
        self.assertEqual(self.result["particle984FailedFrames"], 0)
        self.assertEqual(self.result["particle984EncodedBatches"], 2)
        self.assertEqual(self.result["particle984CompletedBatches"], 2)
        self.assertEqual(self.result["particle984EncodedInstances"], 5)
        self.assertEqual(self.result["particle984CompletedInstances"], 5)
        self.assertEqual(self.result["particle984RefractionBatches"], 1)
        self.assertEqual(self.result["particle984CompletedRefractionBatches"], 1)
        self.assertEqual(self.result["particle12SubmittedFrames"], 1)
        self.assertEqual(self.result["particle12EncodedBatches"], 1)
        self.assertEqual(self.result["particle12EncodedInstances"], 1)
        self.assertEqual(self.result["staleParticleLayerCount"], 0)

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
        self.assertIn("--mwx-debug-scene-performance-warmup", performance_runner)
        self.assertIn("warmupSeconds=%.3f", performance_runner)
        self.assertIn("reset(\n                targetFPS: targetFPS", performance_runner)
        self.assertIn("performanceTelemetry?.recordWillPresent", view)
        self.assertIn("drawable.addPresentedHandler", SOURCE.read_text(encoding="utf-8"))
        self.assertIn("presentedDrawable.presentedTime", SOURCE.read_text(encoding="utf-8"))
        self.assertIn("phase=performance", performance_runner)
        self.assertIn("targetFPS=%d", performance_runner)
        self.assertIn("discontinuities=%d", performance_runner)
        self.assertIn("droppedMS=%.3f", performance_runner)
        self.assertIn("debugEvidence.reset(", performance_runner)
        self.assertIn("phase=performance-resources", performance_runner)
        self.assertIn("proc_pid_rusage(getpid(), RUSAGE_INFO_V4", performance_runner)
        self.assertIn("refreshPerformanceResourceGauges()", performance_runner)
        self.assertIn("DispatchSource.makeTimerSource(queue: .main)", performance_runner)
        self.assertIn("repeating: .seconds(1)", performance_runner)
        self.assertNotIn("scheduleNextSample()", performance_runner)
        self.assertIn("processFootprintSampledPeakBytes=%llu", performance_runner)
        self.assertIn("gpuAllocatedSampledPeakBytes=%llu", performance_runner)
        self.assertIn("processCPUTimeStatus=%@", performance_runner)
        # 嵌套阶段的 per-frame 聚合必须由 runner 单独成行输出，不能覆盖 per-call 行。
        self.assertIn("phase=performance-stages %@", performance_runner)
        self.assertIn("phase=performance-stages-frames %@", performance_runner)
        self.assertIn("frameStageSummary()", performance_runner)
        # GPU 普查行：只报告窗口内的编码操作计数，不含任何阶段时长。
        self.assertIn("phase=performance-gpu frames=%d", performance_runner)
        for field in (
            "mainPassRenders=%llu",
            "depthRenders=%llu",
            "offscreenRenders=%llu",
            "resolvedMaterialRenders=%llu",
            "graphResourceSourceCaptures=%llu",
            "graphResourceInitializations=%llu",
            "offscreenEffectCaptures=%llu",
            "textureCopyPasses=%llu",
            "framebufferCaptures=%llu",
            "framebufferCaptureBytes=%llu",
            "graphOutputPublicationCopies=%llu",
            "textureCopyBytes=%llu",
            "unmeasuredCopyPasses=%llu",
        ):
            self.assertIn(field, performance_runner)
        self.assertIn("gpuCensusBaseline = ScenePerformanceCounterHub.shared.snapshot()", performance_runner)
        self.assertNotIn("ProcessCPUTimeNanoseconds", performance_runner)
        self.assertNotIn("cpuTimeNanoseconds", performance_runner)

    def test_process_cpu_time_converts_mach_ticks_and_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-process-cpu-time-") as directory:
            root = Path(directory)
            harness = root / "ProcessCPUTimeHarness.swift"
            binary = root / "process-cpu-time"
            harness.write_text(PROCESS_CPU_TIME_HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc",
                    "-D",
                    "DEBUG",
                    str(PROCESS_CPU_TIME_SOURCE),
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
        self.assertEqual(result["combined"], 150)
        self.assertAlmostEqual(result["elapsedMilliseconds"], 0.000125)
        self.assertEqual(result["sumOverflow"], "raw-tick-sum-overflow")
        self.assertEqual(result["regressed"], "tick-counter-regressed")
        self.assertEqual(result["timebaseFailure"], "timebase-unavailable")
        self.assertEqual(result["invalidTimebase"], "timebase-invalid")
        self.assertEqual(result["conversionOverflow"], "conversion-overflow")
        helper = PROCESS_CPU_TIME_SOURCE.read_text(encoding="utf-8")
        self.assertIn("mach_timebase_info(&info)", helper)
        self.assertIn("addingReportingOverflow", helper)
        self.assertIn("subtractingReportingOverflow", helper)
        self.assertIn("multipliedReportingOverflow", helper)

    def test_prepass_cost_is_attributed_by_observation_substages(self) -> None:
        """prepass 是复合阶段；子阶段只做归因，且必须保持遥测可选（普通播放无开销）。"""
        renderer = RENDERER_SOURCE.read_text(encoding="utf-8")
        particle = PARTICLE_PLAYBACK_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")

        # 总括阶段仍在，子阶段不替代它。
        self.assertIn('performanceTelemetry?.beginStage("prepass")', renderer)
        self.assertIn('performanceTelemetry?.endStage("prepass")', renderer)

        for label in (
            "prepass-particles",
            "prepass-encoder",
            "prepass-forward-providers",
        ):
            self.assertIn(f'performanceTelemetry?.beginStage("{label}")', renderer)
            self.assertIn(f'performanceTelemetry?.endStage("{label}")', renderer)

        for label in (
            "particle-prepare-frame",
            "particle-pointer-projection",
            "particle-advance",
        ):
            self.assertIn(f'performanceTelemetry?.beginStage("{label}")', particle)
            self.assertIn(f'performanceTelemetry?.endStage("{label}")', particle)

        # 粒子子阶段的遥测必须由渲染路径显式传入，而不是新增第二处时钟/观测。
        self.assertIn("performanceTelemetry: SceneFramePerformanceTelemetry? = nil", particle)
        self.assertIn("[performanceTelemetry] in", view)
        self.assertIn("performanceTelemetry: performanceTelemetry", view)

    def test_admission_cost_is_attributed_by_observation_substages(self) -> None:
        """admit-prepare-frame 是复合阶段；两个子阶段只做归因且必须保持遥测可选。"""
        preflight = PREFLIGHT_SOURCE.read_text(encoding="utf-8")
        coordinator = SUBMISSION_COORDINATOR_SOURCE.read_text(encoding="utf-8")

        # 总括阶段仍在，子阶段不替代它。
        self.assertIn(
            'performanceTelemetry?.beginStage("admit-prepare-frame")', preflight
        )
        self.assertIn(
            'performanceTelemetry?.endStage("admit-prepare-frame")', preflight
        )
        for label in ("admit-install-graph-outputs", "admit-frame-commit"):
            source = (
                preflight if label == "admit-install-graph-outputs" else coordinator
            )
            self.assertIn(f'performanceTelemetry?.beginStage("{label}")', source)
            self.assertIn(f'performanceTelemetry?.endStage("{label}")', source)
        # 两个子阶段都必须用 defer 关闭，避免提前 return 留下未配对区间。
        self.assertIn(
            "defer {\n                    performanceTelemetry?.endStage("
            '"admit-install-graph-outputs")\n                }',
            preflight,
        )
        self.assertIn(
            'defer { performanceTelemetry?.endStage("admit-frame-commit") }',
            coordinator,
        )


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
        self.assertEqual(result["slots"], 34)
        self.assertEqual(result["drawCalls"], 2)
        self.assertEqual(result["pipelineStateBinds"], 1)
        self.assertEqual(result["geometryDrawCalls"], 1)
        self.assertEqual(result["fallbackBranches"], 1)
        self.assertEqual(result["gpuAllocatedBytes"], 123_456)
        self.assertEqual(result["renderTargetPoolBytes"], 65_432)
        # GPU census: main-pass depth renders are a subset of main-pass renders,
        # and every copy contributes to the cumulative byte total.
        self.assertEqual(result["mainPassRenderPasses"], 2)
        self.assertEqual(result["depthRenderPasses"], 1)
        # Offscreen categories partition the offscreen total.
        self.assertEqual(result["offscreenRenderPasses"], 5)
        self.assertEqual(result["resolvedMaterialRenderPasses"], 2)
        self.assertEqual(result["graphResourceSourceCaptures"], 1)
        self.assertEqual(result["graphResourceInitializations"], 1)
        self.assertEqual(result["offscreenEffectCaptures"], 1)
        self.assertEqual(result["framebufferCaptures"], 1)
        self.assertEqual(result["framebufferCaptureBytes"], 8_294_400)
        self.assertEqual(result["graphOutputPublicationCopies"], 1)
        self.assertEqual(result["unmeasuredCopyPasses"], 1)
        self.assertEqual(result["textureCopyPasses"], 4)
        self.assertEqual(
            result["textureCopyBytes"],
            8_294_400 + 4_147_200 + 2_073_600,
        )

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


class SceneGPUCensusTests(unittest.TestCase):
    def test_census_counts_pass_splits_and_copy_bytes(self) -> None:
        """普查只计编码操作：pass 创建与整纹理拷贝的字节量。"""
        with tempfile.TemporaryDirectory(prefix="mwx-scene-gpu-census-") as directory:
            root = Path(directory)
            harness = root / "GPUCensusHarness.swift"
            binary = root / "scene-gpu-census"
            harness.write_text(GPU_CENSUS_HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc",
                    str(COUNTER_HUB_SOURCE),
                    str(GPU_CENSUS_SOURCE),
                    str(harness),
                    "-framework",
                    "Metal",
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
        self.assertEqual(result["mainPassRenderPasses"], 2)
        self.assertEqual(result["depthRenderPasses"], 1)
        self.assertEqual(result["offscreenRenderPasses"], 2)
        self.assertEqual(result["resolvedMaterialRenderPasses"], 1)
        self.assertEqual(result["graphResourceInitializations"], 1)
        self.assertEqual(result["graphResourceSourceCaptures"], 0)
        self.assertEqual(result["offscreenEffectCaptures"], 0)
        # bgra8Unorm 16x8 = 512 bytes per copy; three measured copies plus one
        # copy whose format has no known bytes-per-pixel.
        self.assertEqual(result["textureCopyPasses"], 4)
        self.assertEqual(result["framebufferCaptures"], 1)
        self.assertEqual(result["framebufferCaptureBytes"], 512)
        self.assertEqual(result["graphOutputPublicationCopies"], 1)
        self.assertEqual(result["textureCopyBytes"], 1_536)
        self.assertEqual(result["unmeasuredCopyPasses"], 1)

    def test_every_frame_path_encoder_and_copy_is_counted(self) -> None:
        """每个逐帧 render encoder 与整纹理 blit 都必须恰好计一次。"""
        main_pass = MAIN_PASS_ENCODER_SOURCE.read_text(encoding="utf-8")
        graph_resource = GRAPH_RESOURCE_PASS_ENCODER_SOURCE.read_text(encoding="utf-8")
        material_pass = MATERIAL_PASS_ENCODER_SOURCE.read_text(encoding="utf-8")
        offscreen = OFFSCREEN_EFFECT_ENCODER_SOURCE.read_text(encoding="utf-8")
        snapshot = FRAMEBUFFER_SNAPSHOT_SOURCE.read_text(encoding="utf-8")
        dependency = DEPENDENCY_FRAME_RUNTIME_SOURCE.read_text(encoding="utf-8")

        self.assertEqual(
            main_pass.count("SceneGPUCensus.recordMainPassRender("), 1
        )
        self.assertEqual(main_pass.count("makeRenderCommandEncoder("), 1)
        self.assertEqual(
            graph_resource.count("SceneGPUCensus.recordOffscreenRender("), 2
        )
        self.assertEqual(
            graph_resource.count(".graphResourceSourceCapture"), 1
        )
        self.assertEqual(
            graph_resource.count(".graphResourceInitialization"), 1
        )
        self.assertEqual(
            graph_resource.count("makeRenderCommandEncoder("), 2
        )
        self.assertEqual(
            graph_resource.count("SceneGPUCensus.recordTextureCopy("), 1
        )
        self.assertEqual(
            material_pass.count("SceneGPUCensus.recordOffscreenRender(.resolvedMaterial)"), 1
        )
        self.assertEqual(material_pass.count("makeRenderCommandEncoder("), 1)
        self.assertEqual(
            offscreen.count(
                "SceneGPUCensus.recordOffscreenRender(.offscreenEffectCapture)"
            ),
            1,
        )
        self.assertEqual(offscreen.count("makeRenderCommandEncoder("), 1)
        self.assertEqual(
            snapshot.count("SceneGPUCensus.recordFramebufferCapture("), 1
        )
        # Named graph output has two mutually exclusive encoding owners: the
        # rasterized-color render path and the identity-blit path. Each owner
        # must publish exactly once when selected.
        self.assertEqual(
            dependency.count("SceneGPUCensus.recordGraphOutputPublication("), 2
        )
        census = GPU_CENSUS_SOURCE.read_text(encoding="utf-8")
        hub = COUNTER_HUB_SOURCE.read_text(encoding="utf-8")
        # 字节量未知的格式必须计为 unmeasured，不能猜成 4 字节。
        self.assertIn("unmeasuredCopyPasses", hub)
        self.assertIn("bytesPerPixel", census)
        self.assertIn("return nil", census)


if __name__ == "__main__":
    unittest.main()
