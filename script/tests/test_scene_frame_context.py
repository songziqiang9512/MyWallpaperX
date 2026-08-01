#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift"
POINTER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneSurfacePointerState.swift"
)
DYNAMIC_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift"
)
AUDIO_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneAudioSpectrum.swift"
)
HOST_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift"
HOST_FRAME_DRIVER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
)
HOST_TIME_OF_DAY_REPORT_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime"
    / "SceneDesktopWallpaperHost+TimeOfDayEffectScriptReport.swift"
)
HOST_VIDEO_PROVIDERS_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime"
    / "SceneDesktopWallpaperHost+VideoProviders.swift"
)
HOST_LAUNCH_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+Launch.swift"
)
PLAYBACK_CONTROL_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+PlaybackControl.swift"
)
WALLPAPER_ENGINE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine.swift"
)
LIVE_CONSUMERS_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+LiveConsumers.swift"
)
VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift"
RENDERER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalRenderer.swift"
)
COMPOSITOR_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneImageLayerCompositor.swift"
)
PIPELINE_REPOSITORY_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering"
    / "SceneImageEffectPipelineRepository.swift"
)
COORDINATOR_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/App/MainWindowCoordinator.swift"
DEBUG_RUNNER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner.swift"

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        var clock = SceneClock(hostTime: 10)
        let first = clock.advance(
            hostTime: 10.25,
            wallDate: Date(timeIntervalSince1970: 1_000)
        )
        let second = clock.advance(
            hostTime: 10.5,
            wallDate: Date(timeIntervalSince1970: 1_001)
        )
        let backwards = clock.advance(
            hostTime: 9,
            wallDate: Date(timeIntervalSince1970: 1_002)
        )
        clock.reset(hostTime: 20)
        let reset = clock.advance(
            hostTime: 20,
            wallDate: Date(timeIntervalSince1970: 2_000)
        )
        let context = SceneFrameContext(
            timing: second,
            dynamicValues: .empty(frameIndex: second.frameIndex, generation: 4),
            canvasSize: CGSize(width: 1920, height: 1080),
            screenSize: CGSize(width: 3024, height: 1964),
            pointer: .init(
                current: SIMD2(0.5, -0.25),
                previous: SIMD2(0.25, -0.5),
                isInside: true,
                isPrimaryButtonDown: false
            ),
            cameraParallaxPosition: SIMD2(0.1, 0.2),
            audioSpectrum: .silent
        )
        let payload: [String: Any] = [
            "first": timing(first),
            "second": timing(second),
            "backwards": timing(backwards),
            "reset": timing(reset),
            "context": [
                "frameIndex": context.frameIndex,
                "sceneTime": context.sceneTime,
                "dynamicFrameIndex": context.dynamicValues.frameIndex,
                "dynamicGeneration": context.dynamicValues.generation,
                "dynamicCount": context.dynamicValues.count,
                "pointerCurrent": [context.pointerCurrent.x, context.pointerCurrent.y],
                "pointerPrevious": [context.pointerPrevious.x, context.pointerPrevious.y],
                "canvas": [context.canvasSize.width, context.canvasSize.height],
                "screen": [context.screenSize.width, context.screenSize.height],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func timing(_ value: SceneFrameTiming) -> [String: Any] {
        [
            "frameIndex": value.frameIndex,
            "hostTime": value.hostTime,
            "sceneTime": value.sceneTime,
            "frameTime": value.frameTime,
            "wallTime": value.wallDate.timeIntervalSince1970,
        ]
    }
}
'''

PAUSE_HARNESS = r'''
import Foundation

@main
enum PauseHarness {
    static func main() throws {
        var clock = SceneClock(hostTime: 10)
        _ = clock.advance(
            hostTime: 10.25,
            wallDate: Date(timeIntervalSince1970: 1_000)
        )
        let beforePause = clock.advance(
            hostTime: 10.5,
            wallDate: Date(timeIntervalSince1970: 1_001)
        )

        clock.pause(hostTime: 10.5)
        let pausedState = clock.isPaused
        let pausedFirst = clock.advance(
            hostTime: 20,
            wallDate: Date(timeIntervalSince1970: 2_000)
        )
        let pausedSecond = clock.advance(
            hostTime: 30,
            wallDate: Date(timeIntervalSince1970: 3_000)
        )

        clock.resume(hostTime: 30)
        let resumedFirst = clock.advance(
            hostTime: 30,
            wallDate: Date(timeIntervalSince1970: 3_001)
        )
        let resumedSecond = clock.advance(
            hostTime: 30.25,
            wallDate: Date(timeIntervalSince1970: 3_002)
        )

        clock.pause(hostTime: 31)
        clock.reset(hostTime: 100)
        let pausedAfterReset = clock.isPaused
        let resetFirst = clock.advance(
            hostTime: 100,
            wallDate: Date(timeIntervalSince1970: 4_000)
        )
        let resetSecond = clock.advance(
            hostTime: 100.25,
            wallDate: Date(timeIntervalSince1970: 4_001)
        )

        let payload: [String: Any] = [
            "beforePause": timing(beforePause),
            "pausedState": pausedState,
            "pausedFirst": timing(pausedFirst),
            "pausedSecond": timing(pausedSecond),
            "resumedFirst": timing(resumedFirst),
            "resumedSecond": timing(resumedSecond),
            "pausedAfterReset": pausedAfterReset,
            "resetFirst": timing(resetFirst),
            "resetSecond": timing(resetSecond),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func timing(_ value: SceneFrameTiming) -> [String: Any] {
        [
            "frameIndex": value.frameIndex,
            "sceneTime": value.sceneTime,
            "frameTime": value.frameTime,
        ]
    }
}
'''


def swift_body(source: str, signature: str) -> str:
    signature_start = source.index(signature)
    body_start = source.index("{", signature_start)
    depth = 0
    for position in range(body_start, len(source)):
        character = source[position]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[body_start + 1:position]
    raise AssertionError(f"unterminated Swift body: {signature}")


class SceneFrameContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-frame-context-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-frame-context"
        compilation = subprocess.run(
            [
                "swiftc",
                str(DYNAMIC_SOURCE),
                str(AUDIO_SOURCE),
                str(POINTER_SOURCE),
                str(SOURCE),
                str(harness),
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

    def test_clock_is_monotonic_and_uses_one_wall_date_per_frame(self) -> None:
        self.assertEqual(self.result["first"], {
            "frameIndex": 0, "frameTime": 0, "hostTime": 10.25,
            "sceneTime": 0.25, "wallTime": 1000,
        })
        self.assertEqual(self.result["second"]["frameIndex"], 1)
        self.assertEqual(self.result["second"]["frameTime"], 0.25)
        self.assertEqual(self.result["backwards"]["hostTime"], 10.5)
        self.assertEqual(self.result["backwards"]["frameTime"], 0)

    def test_reset_starts_a_new_generation(self) -> None:
        self.assertEqual(self.result["reset"], {
            "frameIndex": 0, "frameTime": 0, "hostTime": 20,
            "sceneTime": 0, "wallTime": 2000,
        })

    def test_clock_pause_freezes_scene_time_and_resume_drops_the_gap(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-clock-pause-") as path:
            directory = Path(path)
            harness = directory / "PauseHarness.swift"
            harness.write_text(PAUSE_HARNESS, encoding="utf-8")
            binary = directory / "scene-clock-pause"
            compilation = subprocess.run(
                [
                    "swiftc",
                    str(DYNAMIC_SOURCE),
                    str(AUDIO_SOURCE),
                    str(POINTER_SOURCE),
                    str(SOURCE),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                compilation.returncode,
                0,
                f"SceneClock pause contract does not compile:\n{compilation.stderr}",
            )
            completed = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
            result = json.loads(completed.stdout)

        before_pause = result["beforePause"]
        paused_first = result["pausedFirst"]
        paused_second = result["pausedSecond"]
        resumed_first = result["resumedFirst"]
        resumed_second = result["resumedSecond"]
        self.assertTrue(result["pausedState"])
        self.assertEqual(paused_first["sceneTime"], before_pause["sceneTime"])
        self.assertEqual(paused_second["sceneTime"], before_pause["sceneTime"])
        self.assertEqual(paused_first["frameTime"], 0)
        self.assertEqual(paused_second["frameTime"], 0)
        self.assertEqual(paused_first["frameIndex"], paused_second["frameIndex"])
        self.assertEqual(resumed_first["sceneTime"], before_pause["sceneTime"])
        self.assertEqual(resumed_first["frameTime"], 0)
        self.assertAlmostEqual(
            resumed_second["sceneTime"], before_pause["sceneTime"] + 0.25
        )
        self.assertEqual(resumed_second["frameTime"], 0.25)
        self.assertEqual(
            resumed_second["frameIndex"], resumed_first["frameIndex"] + 1
        )

        self.assertFalse(result["pausedAfterReset"])
        self.assertEqual(result["resetFirst"], {
            "frameIndex": 0, "frameTime": 0, "sceneTime": 0,
        })
        self.assertEqual(result["resetSecond"], {
            "frameIndex": 1, "frameTime": 0.25, "sceneTime": 0.25,
        })

    def test_context_keeps_per_surface_inputs_with_shared_timing(self) -> None:
        self.assertEqual(self.result["context"]["frameIndex"], 1)
        self.assertEqual(self.result["context"]["dynamicFrameIndex"], 1)
        self.assertEqual(self.result["context"]["dynamicGeneration"], 4)
        self.assertEqual(self.result["context"]["dynamicCount"], 0)
        self.assertEqual(self.result["context"]["pointerCurrent"], [0.5, -0.25])
        self.assertEqual(self.result["context"]["pointerPrevious"], [0.25, -0.5])
        self.assertEqual(self.result["context"]["canvas"], [1920, 1080])
        self.assertEqual(self.result["context"]["screen"], [3024, 1964])

    def test_host_owns_the_only_scene_frame_timer_and_per_surface_snapshots(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        self.assertIn("var frameTimer: Timer?", host)
        self.assertIn("final class Surface", host)
        self.assertIn(
            "var evaluationTransaction = SceneSurfaceEvaluationTransaction()", host
        )
        self.assertIn("let timing = sceneClock.advance", frame_driver)
        render_position = frame_driver.index("private func renderFrame()")
        broadcast_position = frame_driver.index("for surface in surfaces.values", render_position)
        snapshot_position = frame_driver.index(
            "surface.evaluationTransaction.evaluate", broadcast_position
        )
        self.assertLess(broadcast_position, snapshot_position)
        self.assertNotIn(
            "SceneDynamicSnapshot.empty(frameIndex: timing.frameIndex)", frame_driver
        )
        # 调用可能跨行（频谱等 host-shared 输入随参数增长），只锁语义不锁排版。
        self.assertIn("surface.metalView.renderFrame(", frame_driver)
        self.assertIn("dynamicValues: dynamicValues", frame_driver)
        self.assertIn("dynamicValues: SceneDynamicSnapshot", view)
        self.assertIn("dynamicValues: dynamicValues", view)
        self.assertNotIn("displayTimer", view)
        self.assertNotIn("renderStartTime", view)

    def test_debug_wall_date_override_is_bounded_to_evidence_runs(self) -> None:
        report = HOST_TIME_OF_DAY_REPORT_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        override = swift_body(report, "static let debugWallDateOverride: Date?")
        self.assertIn("usesDebugEvidenceWindow", override)
        self.assertIn("MYWALLPAPERX_SCENE_DEBUG_WALL_DATE", override)
        self.assertIn("ISO8601DateFormatter().date", override)
        self.assertIn(
            "#if DEBUG", report[:report.index("static let debugWallDateOverride")]
        )
        self.assertIn("Self.debugWallDateOverride ?? Date()", frame_driver)
        self.assertEqual(frame_driver.count("sceneClock.advance("), 1)
        self.assertIn("wallDate: wallDate", frame_driver)

    def test_host_pause_state_controls_clock_and_frame_driver(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        video_providers = HOST_VIDEO_PROVIDERS_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("var isPlaybackActive: Bool", host)
        playback_active = swift_body(host, "var isPlaybackActive: Bool")
        self.assertIn("launchContext != nil", playback_active)
        self.assertIn("sceneClock.isPaused", playback_active)

        pause_control = swift_body(
            video_providers, "func setPlaybackPaused(_ paused: Bool)"
        )
        self.assertIn("sceneClock.pause(hostTime:", pause_control)
        self.assertIn("sceneClock.resume(hostTime:", pause_control)
        self.assertIn("frameTimer?.invalidate()", pause_control)
        self.assertIn("frameTimer = nil", pause_control)
        self.assertIn("startFrameDriver()", pause_control)

        start_driver = swift_body(frame_driver, "func startFrameDriver()")
        paused_guard_positions = [
            start_driver.find(candidate)
            for candidate in (
                "guard !sceneClock.isPaused",
                "if sceneClock.isPaused",
            )
            if candidate in start_driver
        ]
        self.assertTrue(
            paused_guard_positions,
            "startFrameDriver must reject a paused Scene before creating a Timer",
        )
        self.assertLess(
            min(paused_guard_positions),
            start_driver.index("Timer(timeInterval:"),
        )

        rebuild = swift_body(
            host, "private func rebuildSurfaces(resetClock: Bool = false) -> Bool"
        )
        self.assertIn("startFrameDriver()", rebuild)
        self.assertNotIn("setPlaybackPaused(false)", rebuild)
        self.assertNotIn("sceneClock.resume(hostTime:", rebuild)

    def test_global_playback_control_delegates_active_scene_state(self) -> None:
        playback_control = PLAYBACK_CONTROL_SOURCE.read_text(encoding="utf-8")
        engine = WALLPAPER_ENGINE_SOURCE.read_text(encoding="utf-8")
        combined = engine + playback_control
        self.assertIn("var isPlaybackPaused: Bool", combined)
        paused_getter = swift_body(combined, "var isPlaybackPaused: Bool")
        self.assertIn("playbackPaused", paused_getter)

        pause = swift_body(playback_control, "public func pauseAllPlayers()")
        resume = swift_body(playback_control, "public func resumeAllPlayers()")
        self.assertIn(
            "SceneDesktopWallpaperHost.shared.setPlaybackPaused(true)", pause
        )
        self.assertIn(
            "SceneDesktopWallpaperHost.shared.setPlaybackPaused(false)", resume
        )

        is_playing = swift_body(engine, "public func isPlaying()")
        self.assertIn("SceneDesktopWallpaperHost.shared", is_playing)
        self.assertIn("activeRecordID", is_playing)
        self.assertIn("isPlaybackActive", is_playing)

    def test_launch_callers_forward_raw_root_and_host_owns_runtime_input(self) -> None:
        host = HOST_LAUNCH_SOURCE.read_text(encoding="utf-8")
        coordinator = COORDINATOR_SOURCE.read_text(encoding="utf-8")
        debug_runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let runtimeInput: SceneRuntimeInput", host)
        self.assertIn("let authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog", host)
        self.assertIn("shaderContracts: runtimeInput.shaderContracts", host)
        self.assertIn(
            "program: runtimeInput.propertyBindingProgram", host
        )
        self.assertIn("effectiveValues: runtimeInput.effectivePropertyValues", host)
        self.assertIn("rootURL: request.rootURL", coordinator)
        self.assertIn("rootURL: rootURL", debug_runner)
        self.assertNotIn("interpretationFileURL", coordinator)

    def test_launch_owns_and_reuses_the_lazy_effect_pipeline_repository(self) -> None:
        launch = HOST_LAUNCH_SOURCE.read_text(encoding="utf-8")
        host = HOST_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        renderer = RENDERER_SOURCE.read_text(encoding="utf-8")
        compositor = COMPOSITOR_SOURCE.read_text(encoding="utf-8")
        repository = PIPELINE_REPOSITORY_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "let pipelineRepository: SceneImageEffectPipelineRepository", launch
        )
        self.assertIn(
            "pipelineRepository: SceneImageEffectPipelineRepository(device: device)",
            launch,
        )
        rebuild = host.split("private func rebuildSurfaces(", maxsplit=1)[1]
        self.assertIn(
            "pipelineRepository: launchContext.pipelineRepository", rebuild
        )
        self.assertIn(
            "pipelineRepository: SceneImageEffectPipelineRepository", view
        )
        self.assertIn(
            "pipelineRepository: SceneImageEffectPipelineRepository", renderer
        )
        self.assertNotIn("MTLCreateSystemDefaultDevice()", renderer)
        self.assertIn(
            "SceneImageLayerCompositor(\n            pipelineRepository:",
            renderer,
        )
        self.assertNotIn("SceneGaussianBlurPipeline(device:", compositor)
        self.assertNotIn("SceneBloomPipeline(device:", compositor)
        self.assertIn("final class ScenePipelineSlot<Value>", repository)
        self.assertIn("case resolved(Value?)", repository)

    def test_host_derives_only_renderer_backed_live_consumers(self) -> None:
        derivation = LIVE_CONSUMERS_SOURCE.read_text(encoding="utf-8")
        self.assertIn("static func activeLiveConsumerTargets(", derivation)
        self.assertIn(
            "into: authoredEffectCatalog.liveConsumerTargets",
            derivation,
        )
        self.assertIn('case "image":', derivation)
        self.assertIn('case "text":', derivation)
        self.assertIn('case "solid":', derivation)
        self.assertIn(
            'case "composition", "project", "fullscreen":', derivation
        )
        self.assertIn(
            "utilityPlans[layer.id]?.shouldCapture == true", derivation
        )
        self.assertIn(
            "targets.insert(.layer(layerID: layer.id, field: .alpha))", derivation
        )
        solid_color = ".layer(layerID: layer.id, field: .color)"
        self.assertEqual(derivation.count(solid_color), 1)
        color_position = derivation.index(solid_color)
        self.assertGreater(color_position, derivation.index('case "solid":'))
        self.assertLess(
            color_position,
            derivation.index('case "composition", "project", "fullscreen":'),
        )
        self.assertNotIn('case "particle"', derivation)
        self.assertIn("visibleLayerIDs.contains(layer.id)", derivation)
        self.assertIn(".text(layerID: layer.id, field: .content)", derivation)
        self.assertIn(".text(layerID: layer.id, field: .pointSize)", derivation)
        self.assertIn(".text(layerID: layer.id, field: .color)", derivation)

    def test_live_property_apis_update_state_without_rebuilding_surfaces(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        single_start = host.index("func applyUserPropertyValue(")
        bulk_start = host.index("func applyUserPropertyValues(", single_start)
        stop_start = host.index("func stop()", bulk_start)
        single = host[single_start:bulk_start]
        bulk = host[bulk_start:stop_start]
        self.assertIn("applyUserPropertyValues(", single)
        self.assertIn("guard var context = launchContext", bulk)
        self.assertIn("context.recordID == recordID", bulk)
        self.assertIn("context.liveState.apply(", bulk)
        self.assertIn("launchContext = context", bulk)
        self.assertNotIn("rebuildSurfaces", single + bulk)
        self.assertNotIn("teardownSurfaces", single + bulk)

    def test_each_frame_reads_the_latest_live_state_values(self) -> None:
        host = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        render_start = host.index("private func renderFrame()")
        render = host[render_start:]
        self.assertIn("userValues: launchContext.liveState.userValues", render)
        self.assertNotIn("userDynamicValues", host)

    def test_screen_notifications_are_debounced_and_skip_unchanged_topology(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        observer = host.split(
            "NSApplication.didChangeScreenParametersNotification", maxsplit=1
        )[1]
        observer = observer.split(
            "NSWorkspace.activeSpaceDidChangeNotification", maxsplit=1
        )[0]
        self.assertIn("scheduleScreenConfigurationReconciliation()", observer)
        reconciliation = host.split(
            "private func scheduleScreenConfigurationReconciliation()", maxsplit=1
        )[1]
        reconciliation = reconciliation.split(
            "private func reassertSurfaceVisibility()", maxsplit=1
        )[0]
        self.assertIn("screenReconciliationWorkItem?.cancel()", reconciliation)
        self.assertIn("asyncAfter(deadline: .now() + 0.2", reconciliation)
        self.assertIn("currentTopology != self.screenTopology", reconciliation)
        self.assertIn("self.reassertSurfaceVisibility()", reconciliation)
        self.assertIn("self.rebuildSurfaces()", reconciliation)


if __name__ == "__main__":
    unittest.main()
