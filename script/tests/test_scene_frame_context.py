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
HOST_VIDEO_PROVIDERS_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime"
    / "SceneDesktopWallpaperHost+VideoProviders.swift"
)
HOST_LAUNCH_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+Launch.swift"
)
EFFECT_HANDLE_BRIDGE_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript"
    / "SceneScriptEffectHandleBridge.swift"
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
MEDIA_THUMBNAIL_COORDINATOR_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMediaThumbnailCoordinator.swift"
)
VIEW_FRAME_CONTEXT_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView+FrameContext.swift"
)
PREPFLIGHT_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneResolvedMaterialFramePreflight.swift"
)
SCALAR_PROGRAM_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptScalarProgram.swift"
)
SCALAR_RUNTIME_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptScalarRuntime.swift"
)
PARTICLE_PLAYBACK_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticlePlaybackState.swift"
)
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
DEBUG_SCENE_SWITCH_RUNNER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/DebugScenePlaybackRunner+SceneSwitch.swift"
)
DEBUG_PAUSE_RESUME_RUNNER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/DebugScenePlaybackRunner+PauseResume.swift"
)

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
        let longFrame = clock.advance(
            hostTime: 11.5,
            wallDate: Date(timeIntervalSince1970: 1_001.5)
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
            materialFunctionMutations: [
                .init(layerID: 17, effectIndex: 2, functionName: "clearHistory")
            ],
            audioSpectrum: .silent
        )
        let payload: [String: Any] = [
            "first": timing(first),
            "second": timing(second),
            "longFrame": timing(longFrame),
            "backwards": timing(backwards),
            "reset": timing(reset),
            "context": [
                "frameIndex": context.frameIndex,
                "sceneTime": context.sceneTime,
                "rawFrameTime": context.rawFrameTime,
                "simulationFrameTime": context.simulationFrameTime,
                "droppedFrameTime": context.droppedFrameTime,
                "isDiscontinuous": context.isDiscontinuous,
                "dynamicFrameIndex": context.dynamicValues.frameIndex,
                "dynamicGeneration": context.dynamicValues.generation,
                "dynamicCount": context.dynamicValues.count,
                "pointerCurrent": [context.pointerCurrent.x, context.pointerCurrent.y],
                "pointerPrevious": [context.pointerPrevious.x, context.pointerPrevious.y],
                "canvas": [context.canvasSize.width, context.canvasSize.height],
                "screen": [context.screenSize.width, context.screenSize.height],
                "materialFunctionMutations": context.materialFunctionMutations.map {
                    ["layerID": $0.layerID, "effectIndex": $0.effectIndex, "functionName": $0.functionName]
                },
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
            "rawFrameTime": value.rawFrameTime,
            "simulationFrameTime": value.simulationFrameTime,
            "droppedFrameTime": value.droppedFrameTime,
            "isDiscontinuous": value.isDiscontinuous,
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
            "rawFrameTime": value.rawFrameTime,
            "simulationFrameTime": value.simulationFrameTime,
            "droppedFrameTime": value.droppedFrameTime,
            "isDiscontinuous": value.isDiscontinuous,
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
            "sceneTime": 0.25, "wallTime": 1000, "rawFrameTime": 0,
            "simulationFrameTime": 0, "droppedFrameTime": 0,
            "isDiscontinuous": False,
        })
        self.assertEqual(self.result["second"]["frameIndex"], 1)
        self.assertEqual(self.result["second"]["frameTime"], 0.25)
        self.assertEqual(self.result["second"]["simulationFrameTime"], 0.25)
        self.assertEqual(self.result["backwards"]["hostTime"], 11.5)
        self.assertEqual(self.result["backwards"]["frameTime"], 0)

    def test_clock_preserves_raw_and_bounded_simulation_delta(self) -> None:
        long_frame = self.result["longFrame"]
        self.assertEqual(long_frame["rawFrameTime"], 1)
        self.assertEqual(long_frame["frameTime"], 1)
        self.assertEqual(long_frame["simulationFrameTime"], 0.25)
        self.assertEqual(long_frame["droppedFrameTime"], 0.75)
        self.assertTrue(long_frame["isDiscontinuous"])

    def test_reset_starts_a_new_generation(self) -> None:
        self.assertEqual(self.result["reset"], {
            "frameIndex": 0, "frameTime": 0, "hostTime": 20,
            "sceneTime": 0, "wallTime": 2000, "rawFrameTime": 0,
            "simulationFrameTime": 0, "droppedFrameTime": 0,
            "isDiscontinuous": False,
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
            "rawFrameTime": 0, "simulationFrameTime": 0,
            "droppedFrameTime": 0, "isDiscontinuous": False,
        })
        self.assertEqual(result["resetSecond"], {
            "frameIndex": 1, "frameTime": 0.25, "sceneTime": 0.25,
            "rawFrameTime": 0.25, "simulationFrameTime": 0.25,
            "droppedFrameTime": 0, "isDiscontinuous": False,
        })

    def test_context_keeps_per_surface_inputs_with_shared_timing(self) -> None:
        self.assertEqual(self.result["context"]["frameIndex"], 1)
        self.assertEqual(self.result["context"]["dynamicFrameIndex"], 1)
        self.assertEqual(self.result["context"]["dynamicGeneration"], 4)
        self.assertEqual(self.result["context"]["dynamicCount"], 0)
        self.assertEqual(self.result["context"]["rawFrameTime"], 0.25)
        self.assertEqual(self.result["context"]["simulationFrameTime"], 0.25)
        self.assertEqual(self.result["context"]["droppedFrameTime"], 0)
        self.assertFalse(self.result["context"]["isDiscontinuous"])
        self.assertEqual(self.result["context"]["pointerCurrent"], [0.5, -0.25])
        self.assertEqual(self.result["context"]["pointerPrevious"], [0.25, -0.5])
        self.assertEqual(self.result["context"]["canvas"], [1920, 1080])
        self.assertEqual(self.result["context"]["screen"], [3024, 1964])
        self.assertEqual(
            self.result["context"]["materialFunctionMutations"],
            [{"layerID": 17, "effectIndex": 2, "functionName": "clearHistory"}],
        )

    def test_view_publishes_camera_parallax_only_when_the_camera_enables_it(self) -> None:
        source = VIEW_FRAME_CONTEXT_SOURCE.read_text(encoding="utf-8")
        make_context = swift_body(source, "func makeFrameContext(")
        self.assertIn("pointer: pointerState", make_context)
        self.assertIn(
            "cameraParallaxPosition: camera.parallaxEnabled ? parallax : .zero",
            make_context,
        )

    def test_scenescript_material_mutation_stays_on_existing_frame_and_graph_chain(self) -> None:
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        view_frame_context = VIEW_FRAME_CONTEXT_SOURCE.read_text(encoding="utf-8")
        preflight = PREPFLIGHT_SOURCE.read_text(encoding="utf-8")
        scalar_program = SCALAR_PROGRAM_SOURCE.read_text(encoding="utf-8")
        scalar_runtime = SCALAR_RUNTIME_SOURCE.read_text(encoding="utf-8")

        self.assertIn("sceneScriptResult.materialFunctionMutations", frame_driver)
        self.assertIn(
            "materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []",
            view,
        )
        self.assertIn("materialFunctionMutations: materialFunctionMutations", view)
        self.assertIn(
            "materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []",
            view_frame_context,
        )
        self.assertIn(
            "materialFunctionMutations: [SceneScriptMaterialFunctionMutation]",
            view_frame_context,
        )
        self.assertIn(
            "let materialFunctionInvocations = frameContext.materialFunctionMutations",
            preflight,
        )
        self.assertIn("frameEpoch: textureRegistry.frameEpoch", preflight)
        self.assertIn("effectIndex: mutation.effectIndex", preflight)
        self.assertIn("functionName: mutation.functionName", preflight)
        self.assertIn(
            "materialFunctionMutations.append(contentsOf: callbackMaterialMutations)",
            scalar_program,
        )
        self.assertIn(
            "case let .effectConstant(value, _, _, _), let .layer(value, _),",
            scalar_runtime,
        )
        self.assertIn("let .particle(value, _):", scalar_runtime)
        self.assertIn("mutationOverflow", scalar_runtime)
        self.assertIn("invalid-effect-index-\\(mutation.effectIndex)", preflight)

    def test_material_mutation_failure_remains_typed_and_local(self) -> None:
        scalar_runtime = SCALAR_RUNTIME_SOURCE.read_text(encoding="utf-8")
        effect_bridge = EFFECT_HANDLE_BRIDGE_SOURCE.read_text(encoding="utf-8")
        preflight = PREPFLIGHT_SOURCE.read_text(encoding="utf-8")
        self.assertIn("case .mutationOverflow: \"mutation-overflow\"", scalar_runtime)
        self.assertIn("guard !functionName.isEmpty", effect_bridge)
        self.assertIn('return invalid("plan-count-mismatch")', preflight)
        self.assertIn("SceneGraphMaterialFunctionInvocationRequest", preflight)

    def test_host_owns_the_only_scene_frame_timer_and_per_surface_snapshots(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        particle_playback = PARTICLE_PLAYBACK_SOURCE.read_text(encoding="utf-8")
        self.assertIn("var frameTimer: Timer?", host)
        self.assertIn("final class Surface", host)
        self.assertIn(
            "var evaluationTransaction = SceneSurfaceEvaluationTransaction()", host
        )
        self.assertIn("let advancedTiming = sceneClock.advance", frame_driver)
        self.assertIn("let timing = advancedTiming", frame_driver)
        render_position = frame_driver.index("private func renderFrame()")
        broadcast_position = frame_driver.index("for surface in surfaces.values", render_position)
        media_input_position = frame_driver.index(
            "let mediaInput = SceneMediaThumbnailInbox.shared.latest()", render_position
        )
        playback_event_position = frame_driver.index(
            "SceneScriptMediaPlaybackEventInput(snapshot: mediaInput)", render_position
        )
        properties_event_position = frame_driver.index(
            "SceneScriptMediaPropertiesEventInput(snapshot: mediaInput)", render_position
        )
        string_vm_position = frame_driver.index(
            "launchContext.sceneScriptStringProgram.evaluate(", render_position
        )
        scalar_vm_position = frame_driver.index(
            "launchContext.sceneScriptScalarProgram.evaluate(", render_position
        )
        snapshot_position = frame_driver.index(
            "surface.evaluationTransaction.evaluate", broadcast_position
        )
        self.assertLess(media_input_position, playback_event_position)
        self.assertLess(playback_event_position, properties_event_position)
        self.assertLess(properties_event_position, string_vm_position)
        self.assertLess(string_vm_position, scalar_vm_position)
        self.assertLess(playback_event_position, scalar_vm_position)
        self.assertLess(scalar_vm_position, broadcast_position)
        self.assertLess(broadcast_position, snapshot_position)
        self.assertEqual(
            frame_driver.count("SceneMediaThumbnailInbox.shared.latest()"), 1
        )
        self.assertIn(
            "mediaPlaybackEvent: sceneScriptMediaPlaybackEvent", frame_driver
        )
        self.assertIn(
            "mediaPropertiesEvent: sceneScriptMediaPropertiesEvent", frame_driver
        )
        self.assertIn("mediaInput: mediaInput", frame_driver)
        self.assertIn("frameTime: timing.simulationFrameTime", frame_driver)
        self.assertNotIn("mediaPlaybackPlaceholderFade", frame_driver)
        self.assertNotIn("SceneMediaPlaybackPlaceholderFadeRuntime", host)
        self.assertNotIn(
            "SceneDynamicSnapshot.empty(frameIndex: timing.frameIndex)", frame_driver
        )
        # 调用可能跨行（频谱等 host-shared 输入随参数增长），只锁语义不锁排版。
        self.assertIn("surface.metalView.renderFrame(", frame_driver)
        self.assertIn("dynamicValues: dynamicValues", frame_driver)
        self.assertIn("dynamicValues: SceneDynamicSnapshot", view)
        self.assertIn("dynamicValues: dynamicValues", view)
        self.assertGreaterEqual(view.count("timing.simulationFrameTime"), 1)
        self.assertIn("let cameraFrame = renderer.makeCameraFrame", view)
        self.assertIn("let particleBatches = advanceParticles(", view)
        self.assertGreaterEqual(view.count("cameraFrame: cameraFrame"), 2)
        self.assertNotIn("min(max(frameDelta, 0), 0.25)", particle_playback)
        self.assertNotIn("displayTimer", view)
        self.assertNotIn("renderStartTime", view)

    def test_dynamic_snapshot_fault_is_debug_only_and_isolated_runner_owned(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        launch = swift_body(runner, "private static func launchScene(")

        self.assertIn("var debugDropDynamicValuesFrameIndex: UInt64?", host)
        self.assertIn("func setDebugDropDynamicValuesFrameIndex(", host)
        self.assertIn("guard Self.usesDebugEvidenceWindow else { return false }", host)
        self.assertIn("#if DEBUG", host[:host.index("var debugDropDynamicValuesFrameIndex")])
        self.assertIn(
            'after: "--mwx-debug-scene-drop-dynamic-values-frame"', runner
        )
        isolated_guard = launch.index("guard isIsolatedSampleRoot(rootURL)")
        fault_configuration = launch.index("setDebugDropDynamicValuesFrameIndex")
        self.assertLess(isolated_guard, fault_configuration)
        self.assertIn("let resolvedDynamicValues =", frame_driver)
        self.assertIn("debugDropDynamicValuesFrameIndex == timing.frameIndex", frame_driver)
        self.assertIn("frameIndex: resolvedDynamicValues.frameIndex", frame_driver)
        self.assertIn("generation: resolvedDynamicValues.generation", frame_driver)
        self.assertIn("state=dropped", frame_driver)
        self.assertIn("state=recovered", frame_driver)

    def test_host_broadcasts_one_media_snapshot_to_every_surface(self) -> None:
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        coordinator = MEDIA_THUMBNAIL_COORDINATOR_SOURCE.read_text(
            encoding="utf-8"
        )
        host_render = swift_body(frame_driver, "private func renderFrame()")
        view_render = swift_body(view, "func renderFrame(")
        coordinator_update = swift_body(coordinator, "func update(")

        media_snapshot_declaration = (
            "let mediaInput = SceneMediaThumbnailInbox.shared.latest()"
        )
        self.assertEqual(host_render.count(media_snapshot_declaration), 1)
        self.assertEqual(
            host_render.count("SceneMediaThumbnailInbox.shared.latest()"), 1
        )
        snapshot_position = host_render.index(media_snapshot_declaration)
        color_runtime_position = host_render.index(
            "mediaColorTransitionRuntime.values("
        )
        surface_loop_position = host_render.index("for surface in surfaces.values")
        surface_render_position = host_render.index(
            "surface.metalView.renderFrame(", surface_loop_position
        )
        self.assertLess(snapshot_position, color_runtime_position)
        self.assertLess(color_runtime_position, surface_loop_position)
        self.assertIn(
            "mediaInput: mediaInput",
            host_render[color_runtime_position:surface_loop_position],
        )

        surface_loop = host_render[surface_loop_position:]
        self.assertNotIn(
            "SceneMediaThumbnailInbox.shared.latest()", surface_loop
        )
        self.assertEqual(surface_loop.count("mediaInput: mediaInput"), 1)
        self.assertGreater(
            host_render.index("mediaInput: mediaInput", surface_render_position),
            surface_render_position,
        )

        self.assertIn(
            "mediaInput: SceneMediaThumbnailInbox.Snapshot", view
        )
        self.assertEqual(
            view_render.count(
                "mediaThumbnailCoordinator.update(from: mediaInput)"
            ),
            1,
        )
        self.assertNotIn("SceneMediaThumbnailInbox.shared", view)

        self.assertIn(
            "from input: SceneMediaThumbnailInbox.Snapshot", coordinator
        )
        self.assertEqual(
            coordinator_update.count("textureStore.update(from: input)"), 1
        )
        self.assertNotIn("SceneMediaThumbnailInbox.shared", coordinator)
        self.assertNotIn("func update()", coordinator)

    def test_each_surface_owns_and_advances_its_launch_origin_transition(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        launch = HOST_LAUNCH_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        host_render = swift_body(frame_driver, "private func renderFrame()")

        self.assertIn("launchOriginTransitionProgram", launch)
        self.assertIn(
            "SceneLaunchOriginTransitionProgramCompiler.compile(", launch
        )
        self.assertIn(
            "scriptSourceEvidence: model.sceneDocument.scriptSourceEvidence",
            launch,
        )
        bounded_ownership = launch[
            launch.index("let boundedProducerTargets:"):
            launch.index("let sceneScriptScalarProgram =")
        ]
        self.assertIn(
            '("launch-origin", launchOriginTransitionTargets,',
            bounded_ownership,
        )
        self.assertIn(
            "targets.isDisjoint(with: propertyBindingTargets)",
            bounded_ownership,
        )
        self.assertIn(
            "targets.intersection(timelineTargets)",
            bounded_ownership,
        )
        self.assertIn(".subtracting(allowedTimelineTargets)", bounded_ownership)
        self.assertIn(
            "targets.isDisjoint(with: boundedSceneScriptTargets)",
            bounded_ownership,
        )
        self.assertIn(
            "var launchOriginTransitionRuntime: SceneLaunchOriginTransitionRuntime",
            host,
        )
        self.assertIn(
            "launchOriginTransitionRuntime = .init(\n"
            "                program: launchOriginTransitionProgram",
            host,
        )
        self.assertIn(
            "launchOriginTransitionProgram:\n"
            "                    launchContext.launchOriginTransitionProgram",
            host,
        )
        self.assertIn(
            "launchContext.launchOriginTransitionProgram.definitions",
            host_render,
        )
        runtime_call = "surface.launchOriginTransitionRuntime.values("
        self.assertEqual(host_render.count(runtime_call), 1)
        runtime_position = host_render.index(runtime_call)
        surface_position = host_render.index("for surface in surfaces.values")
        self.assertGreater(runtime_position, surface_position)
        self.assertIn(
            "effectivePropertyValues:\n"
            "                        launchContext.liveState.effectiveValues",
            host_render[runtime_position:],
        )
        surface_loop = host_render[surface_position:]
        self.assertEqual(surface_loop.count(runtime_call), 1)
        self.assertIn("surface.launchOriginTransitionRuntime.currentValues(", surface_loop)
        self.assertIn("launchOriginTransitionValues", surface_loop)
        self.assertIn("commonSceneScriptValues", surface_loop)

    def test_debug_wall_date_override_is_bounded_to_evidence_runs(self) -> None:
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        override = swift_body(
            frame_driver, "static let debugWallDateOverride: Date?"
        )
        self.assertIn("usesDebugEvidenceWindow", override)
        self.assertIn("MYWALLPAPERX_SCENE_DEBUG_WALL_DATE", override)
        self.assertIn("ISO8601DateFormatter().date", override)
        self.assertIn(
            "#if DEBUG",
            frame_driver[:frame_driver.index("static let debugWallDateOverride")],
        )
        self.assertIn("Self.debugWallDateOverride ?? Date()", frame_driver)
        self.assertEqual(frame_driver.count("sceneClock.advance("), 1)
        self.assertIn("wallDate: wallDate", frame_driver)

    def test_time_of_day_is_a_typed_generic_vm_frame_input(self) -> None:
        launch = HOST_LAUNCH_SOURCE.read_text(encoding="utf-8")
        scalar_runtime = SCALAR_RUNTIME_SOURCE.read_text(encoding="utf-8")
        self.assertIn("struct SceneScriptFrameInput", scalar_runtime)
        self.assertIn("timeOfDay = min(max(seconds / 86_400, 0), 1)", scalar_runtime)
        self.assertIn("frameTime = max(timing.simulationFrameTime, 0)", scalar_runtime)
        self.assertIn("runtime = max(timing.sceneTime, 0)", scalar_runtime)
        self.assertNotIn("SceneTimeOfDayEffectScript", launch)

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
            "startFrameDriver must reject a paused Scene before scheduling",
        )
        self.assertLess(
            min(paused_guard_positions),
            start_driver.index("let initialDeadline"),
        )
        self.assertIn("scheduleFrameDriver(", start_driver)
        arm_driver = swift_body(frame_driver, "private func armFrameDriver(")
        self.assertIn("Timer(timeInterval: delay, repeats: false)", arm_driver)

        rebuild = swift_body(
            host, "private func rebuildSurfaces("
        )
        self.assertIn("startFrameDriver()", rebuild)
        self.assertNotIn("setPlaybackPaused(false)", rebuild)
        self.assertNotIn("sceneClock.resume(hostTime:", rebuild)
        self.assertIn("let remainsPaused = sceneClock.isPaused", rebuild)
        self.assertIn("if remainsPaused {", rebuild)
        self.assertIn("sceneClock.pause(hostTime: hostTime)", rebuild)

    def test_busy_history_frame_retries_before_advancing_scene_clock(self) -> None:
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        render = swift_body(frame_driver, "private func renderFrame()")
        schedule = swift_body(
            frame_driver, "private func scheduleFrameDriver("
        )
        self.assertIn("sceneFrameInterval / 8.0", frame_driver)
        self.assertIn("sceneBusyFrameRetryInterval = max(", frame_driver)
        self.assertIn("0.001,", frame_driver)
        self.assertIn("surfaces.values.allSatisfy", render)
        self.assertIn("return .busy", render)
        self.assertLess(
            render.index("surfaces.values.allSatisfy"),
            render.index("sceneClock.advance("),
        )
        self.assertLess(
            render.index("return .busy"),
            render.index("recordDriverCallback()"),
        )
        self.assertIn("case .busy:", schedule)
        self.assertIn(
            "nextDeadline = now + sceneBusyFrameRetryInterval",
            schedule,
        )
        self.assertIn("case .rendered:", schedule)
        self.assertIn("scheduledDeadline + sceneFrameInterval", schedule)

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

    def test_debug_pause_resume_probe_uses_formal_playback_owner(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        probe = DEBUG_PAUSE_RESUME_RUNNER_SOURCE.read_text(encoding="utf-8")

        self.assertIn("let isPlaybackPaused: Bool", host)
        self.assertIn("let isFrameDriverActive: Bool", host)
        snapshot = swift_body(host, "func debugSnapshot() -> DebugSnapshot")
        self.assertIn("isPlaybackPaused: sceneClock.isPaused", snapshot)
        self.assertIn("isFrameDriverActive: frameTimer?.isValid == true", snapshot)
        self.assertIn('"MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER"', probe)
        self.assertIn("WallpaperEngine.shared.pauseAllPlayers()", probe)
        self.assertIn("WallpaperEngine.shared.resumeAllPlayers()", probe)
        self.assertNotIn("setPlaybackPaused(", probe)
        self.assertIn('state=paused accepted=%@', probe)
        self.assertIn('state=resumed accepted=%@', probe)
        self.assertIn('reason: "pause-resume-after"', probe)
        self.assertIn("pauseResumeRequest != nil", runner)
        self.assertIn("runtimeLifecycleProbeCount <= 1", runner)

    def test_debug_scene_switch_accepts_only_isolated_alternate_root(self) -> None:
        runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        probe = DEBUG_SCENE_SWITCH_RUNNER_SOURCE.read_text(encoding="utf-8")

        self.assertIn('"MWX_SCENE_DEBUG_SCENE_SWITCH_ROOT"', probe)
        self.assertIn("isIsolatedSampleRoot(candidate)", probe)
        self.assertIn("usesAlternateRoot: rootURL != currentRootURL", probe)
        self.assertIn("rootURL: request.rootURL", probe)
        self.assertIn("requestedUserPropertyTextureURLs(", probe)
        self.assertIn("model.renderDescriptor.layers.map(\\.id)", probe)
        self.assertIn('mode=%@ root=%@ layerIDs=%@', probe)
        self.assertIn("sceneSwitchRequest != nil", runner)
        self.assertIn("runtimeLifecycleProbeCount <= 1", runner)

    def test_launch_callers_forward_raw_root_and_host_owns_runtime_input(self) -> None:
        host = HOST_LAUNCH_SOURCE.read_text(encoding="utf-8")
        coordinator = COORDINATOR_SOURCE.read_text(encoding="utf-8")
        debug_runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let runtimeInput: SceneRuntimeInput", host)
        self.assertIn("let effectAdmissionCatalog: SceneEffectAdmissionCatalog", host)
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
            "let effectTargets = resolvedMaterialExecutionCapabilities.liveConsumerTargets",
            derivation,
        )
        self.assertIn(
            "resolvedMaterialExecutionCapabilities.liveConsumerTargets",
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
        self.assertIn('case "particle"', derivation)
        self.assertIn(".particle(layerID: layer.id, field: $0)", derivation)
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
