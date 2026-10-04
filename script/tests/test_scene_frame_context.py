#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneFrameContext.swift"
POINTER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneSurfacePointerState.swift"
)
DYNAMIC_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift"
)
AUDIO_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift"
)
HOST_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
HOST_FRAME_DRIVER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
)
HOST_FRAME_DRIVER_LIFECYCLE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriverLifecycle.swift"
)
HOST_POINTER_EVENTS_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+PointerEvents.swift"
)
HOST_VIDEO_PROVIDERS_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+VideoProviders.swift"
)
HOST_LAUNCH_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
)
PREPARED_DEVICE_RESOURCES_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift"
)
EFFECT_HANDLE_BRIDGE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptEffectHandleBridge.swift"
)
PLAYBACK_CONTROL_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+PlaybackControl.swift"
)
WALLPAPER_ENGINE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine.swift"
)
SCENE_DAEMON_CLIENT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift"
)
LIVE_CONSUMERS_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift"
)
VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
MEDIA_THUMBNAIL_COORDINATOR_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMediaThumbnailCoordinator.swift"
)
VIEW_FRAME_CONTEXT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView+FrameContext.swift"
)
VIEW_CURSOR_INTERACTION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView+SceneScriptCursorInteraction.swift"
)
PREPFLIGHT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
)
SCALAR_RUNTIME_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarRuntime.swift"
)
LOCAL_STORAGE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLocalStorage.swift"
)
CURSOR_PROGRAM_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptCursorProgram.swift"
)
PARTICLE_PLAYBACK_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift"
)
RENDERER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
)
RENDERER_INITIALIZATION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Initialization.swift"
)
COMPOSITOR_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor.swift"
)
PIPELINE_REPOSITORY_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneImageEffectPipelineRepository.swift"
)
COORDINATOR_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/App/MainWindowCoordinator+PlaybackRouting.swift"
)
DEBUG_RUNNER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift"
DEBUG_ARGUMENTS_RUNNER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Arguments.swift"
)
DEBUG_SCENE_SWITCH_RUNNER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+SceneSwitch.swift"
)
DEBUG_PAUSE_RESUME_RUNNER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+PauseResume.swift"
)

HARNESS = r'''
import Foundation

// UI/GPU surfaces only; camera selection and frame/input projection below
// compile the production implementations.
struct SceneGraphExecutionResetReason { let label: String }
enum InvalidationEvents { static var values: [String] = [] }
struct FrameTestCompositor {
    var shouldDeferResolvedMaterialFrame = false
    func invalidateResolvedMaterialRuntime(reason: SceneGraphExecutionResetReason) {
        InvalidationEvents.values.append("compositor:\(reason.label)")
    }
}
struct FrameTestPool { func reset() { InvalidationEvents.values.append("pool-reset") } }
struct FrameTestCamera {
    var orthoWidth: Float? = 1920
    var orthoHeight: Float? = 1080
    var parallaxEnabled = true
    var parallaxMouseInfluence: Float = 0.5
}
struct FrameTestDescriptor { var camera = FrameTestCamera() }
struct FrameTestRenderer {
    var imageCompositor = FrameTestCompositor()
    var renderDescriptor = FrameTestDescriptor()
}
struct FrameTestMetalLayer { var drawableSize = CGSize(width: 3024, height: 1964) }
struct SceneMetalView {
    enum RenderInvalidation { case surface, mediaPublication }
    var onRenderInvalidated: ((RenderInvalidation) -> Void)?
    var renderer = FrameTestRenderer()
    var metalLayer = FrameTestMetalLayer()
    var offscreenTexturePool = FrameTestPool()
    var pointerState = SceneSurfacePointerState(
        current: .zero, previous: .zero, isInside: true, isPrimaryButtonDown: false
    )
}

@main
enum Harness {
    static func main() throws {
        var invalidatedView = SceneMetalView()
        invalidatedView.onRenderInvalidated = { _ in InvalidationEvents.values.append("callback") }
        invalidatedView.invalidateResolvedMaterialRuntime(reason: .init(label: "executor"))
        let withCallback = InvalidationEvents.values
        InvalidationEvents.values = []
        invalidatedView.onRenderInvalidated = nil
        invalidatedView.invalidateResolvedMaterialRuntime(reason: .init(label: "surface"))
        let withoutCallback = InvalidationEvents.values
        var clock = SceneClock(hostTime: 10)
        let first = clock.advance(
            hostTime: 10.25,
            wallDate: Date(timeIntervalSince1970: 1_000)
        )
        let second = clock.advance(
            hostTime: 10.5,
            wallDate: Date(timeIntervalSince1970: 1_001)
        )
        let clockState = clock.snapshot()
        let failedAttempt = clock.advance(
            hostTime: 10.75,
            wallDate: Date(timeIntervalSince1970: 1_001.25)
        )
        clock.restore(clockState)
        let retriedAttempt = clock.advance(
            hostTime: 10.75,
            wallDate: Date(timeIntervalSince1970: 1_001.25)
        )
        clock.restore(clockState)
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
            cameraParallaxMouseInfluence: 0.5,
            materialFunctionMutations: [
                .init(layerID: 17, effectIndex: 2, functionName: "clearHistory")
            ],
            audioSpectrum: .silent
        )
        func makeInput(_ snapshot: SceneDynamicSnapshot, authoredEnabled: Bool = true) -> SIMD2<Float> {
            var view = SceneMetalView()
            view.renderer.renderDescriptor.camera.parallaxEnabled = authoredEnabled
            let frame = view.makeFrameContext(
                timing: second, dynamicValues: snapshot,
                parallax: SIMD2(0.8, -0.4), audioSpectrum: .silent
            )
            return SceneAuthoredShaderFrameInputs(frameContext: frame).parallaxPositionNDC
        }
        func snapshot(enabled: Bool, influence: Double) -> SceneDynamicSnapshot {
            SceneDynamicSnapshotResolver().resolve(
                frameIndex: second.frameIndex, generation: 4,
                definitions: [
                    .init(target: .camera(.parallaxEnabled), valueType: .bool, authoredValue: .bool(true)),
                    .init(target: .camera(.parallaxMouseInfluence), valueType: .scalar, authoredValue: .scalar(0.5))
                ],
                sceneScriptValues: [
                    .camera(.parallaxEnabled): .bool(enabled),
                    .camera(.parallaxMouseInfluence): .scalar(influence)
                ]
            ).snapshot
        }
        let cameraSelection = [
            makeInput(context.dynamicValues),
            makeInput(snapshot(enabled: true, influence: 0.25)),
            makeInput(snapshot(enabled: false, influence: 2)),
            makeInput(context.dynamicValues, authoredEnabled: false),
            makeInput(snapshot(enabled: true, influence: 0.25), authoredEnabled: false),
        ]
        let shaderInputs = SceneAuthoredShaderFrameInputs(frameContext: context)
        let parallaxVariants = [Float(0), 1, 2, -1].map { influence in
            SceneAuthoredShaderFrameInputs(frameContext: SceneFrameContext(
                timing: second,
                dynamicValues: context.dynamicValues,
                canvasSize: context.canvasSize,
                screenSize: context.screenSize,
                pointer: context.pointer,
                cameraParallaxPosition: context.cameraParallaxPosition,
                cameraParallaxMouseInfluence: influence,
                audioSpectrum: .silent
            )).parallaxPositionNDC
        }
        var pointerState = SceneSurfacePointerState(
            current: SIMD2(0.25, 0.5),
            previous: SIMD2(-0.75, 0.5),
            sceneScriptCurrent: SIMD2(0.25, 0.5),
            isInside: true,
            isPrimaryButtonDown: false,
            sceneScriptPrimaryButtonIsDown: false
        )
        let pointerInputChanged = pointerState.apply(.init(
            current: SIMD2(0.75, -0.5),
            isInside: true,
            isPrimaryButtonDown: true
        ))
        let payload: [String: Any] = [
            "invalidationWithCallback": withCallback,
            "invalidationWithoutCallback": withoutCallback,
            "cameraSelection": cameraSelection.map { [$0.x, $0.y] },
            "shaderParallax": [shaderInputs.parallaxPositionNDC.x, shaderInputs.parallaxPositionNDC.y],
            "shaderPointer": [shaderInputs.pointerCurrentNDC.x, shaderInputs.pointerCurrentNDC.y],
            "layerParallax": [context.cameraParallaxPosition.x, context.cameraParallaxPosition.y],
            "parallaxVariants": parallaxVariants.map { [$0.x, $0.y] },
            "first": timing(first),
            "second": timing(second),
            "failedAttempt": timing(failedAttempt),
            "retriedAttempt": timing(retriedAttempt),
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
            "pointerInput": [
                "changed": pointerInputChanged,
                "current": [pointerState.current.x, pointerState.current.y],
                "previous": [pointerState.previous.x, pointerState.previous.y],
                "scriptCurrent": [
                    pointerState.sceneScriptCurrent.x,
                    pointerState.sceneScriptCurrent.y,
                ],
                "inside": pointerState.isInside,
                "primaryDown": pointerState.isPrimaryButtonDown,
                "scriptPrimaryDown": pointerState.sceneScriptPrimaryButtonIsDown,
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


# Host all-surface rollback source checks retired with D10.
# Actual presentation/VM behavior: test_scene_frame_presentation_integration.
# GPU source ownership: test_scene_surface_submission and the FIFO harness below.
class SceneFrameContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-frame-context-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
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
                str(VIEW_FRAME_CONTEXT_SOURCE),
                str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot+Camera.swift"),
                str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift"),
                str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Bindings/SceneAuthoredShaderFrameInputs+FrameContext.swift"),
                str(harness),
                "-module-cache-path", str(directory / "module-cache"),
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

    def test_invalidation_notifies_after_compositor_and_pool_reset(self) -> None:
        self.assertEqual(self.result["invalidationWithCallback"],
                         ["compositor:executor", "pool-reset", "callback"])
        self.assertEqual(self.result["invalidationWithoutCallback"],
                         ["compositor:surface", "pool-reset"])

    def test_production_camera_input_selects_dynamic_override_and_disabled_center(self) -> None:
        expected = [[0.4, -0.2], [0.2, -0.1], [0, 0], [0, 0], [0.2, -0.1]]
        for actual, target in zip(self.result["cameraSelection"], expected):
            for component, value in zip(actual, target):
                self.assertAlmostEqual(component, value)

    def test_shader_parallax_weights_mouse_without_changing_layer_or_pointer_input(self) -> None:
        for actual, expected in zip(self.result["shaderParallax"], [0.05, 0.1]):
            self.assertAlmostEqual(actual, expected)
        self.assertEqual(self.result["shaderPointer"], [0.5, -0.25])
        for actual, expected in zip(self.result["layerParallax"], [0.1, 0.2]):
            self.assertAlmostEqual(actual, expected)
        for actual, expected in zip(self.result["parallaxVariants"], [[0, 0], [0.1, 0.2], [0.2, 0.4], [-0.1, -0.2]]):
            for component, target in zip(actual, expected):
                self.assertAlmostEqual(component, target)

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

    def test_clock_snapshot_restore_does_not_consume_failed_attempt(self) -> None:
        failed = self.result["failedAttempt"]
        retried = self.result["retriedAttempt"]
        self.assertEqual(failed["frameIndex"], 2)
        self.assertEqual(retried["frameIndex"], 2)
        self.assertEqual(retried["hostTime"], failed["hostTime"])
        self.assertEqual(retried["sceneTime"], failed["sceneTime"])
        self.assertEqual(retried["rawFrameTime"], failed["rawFrameTime"])
        self.assertEqual(retried["simulationFrameTime"], failed["simulationFrameTime"])

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

    def test_pointer_producer_input_cannot_overwrite_submitted_frame_history(self) -> None:
        self.assertEqual(self.result["pointerInput"], {
            "changed": True,
            "current": [0.75, -0.5],
            "previous": [-0.75, 0.5],
            "scriptCurrent": [0.75, -0.5],
            "inside": True,
            "primaryDown": True,
            "scriptPrimaryDown": True,
        })

    def test_view_publishes_camera_parallax_from_the_typed_snapshot(self) -> None:
        source = VIEW_FRAME_CONTEXT_SOURCE.read_text(encoding="utf-8")
        make_context = swift_body(source, "func makeFrameContext(")
        self.assertIn("pointer: pointerState", make_context)
        self.assertIn("dynamicValues.cameraPropertyProjection()", make_context)
        self.assertIn("property.parallaxEnabled ?? camera.parallaxEnabled", make_context)
        self.assertIn("cameraParallaxPosition: parallaxEnabled ? parallax : .zero", make_context)

    def test_scenescript_material_mutation_stays_on_existing_frame_and_graph_chain(self) -> None:
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        view_frame_context = VIEW_FRAME_CONTEXT_SOURCE.read_text(encoding="utf-8")
        preflight = PREPFLIGHT_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "coordinatedSceneScript.ownerEffects", frame_driver
        )
        self.assertIn(
            "admittedOwnerEffects.flatMap(", frame_driver
        )
        self.assertIn(
            "materialFunctionMutations: materialFunctionMutations", frame_driver
        )
        self.assertNotIn(
            "coordinatedSceneScript.materialFunctionMutations,", frame_driver
        )
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
            "let materialFunctionMutationsByLayerID = Dictionary(\n            grouping: frameContext.materialFunctionMutations",
            preflight,
        )
        self.assertIn(
            "(materialFunctionMutationsByLayerID[layer.id] ?? [])",
            preflight,
        )
        self.assertIn("frameEpoch: textureRegistry.frameEpoch", preflight)
        self.assertIn("effectIndex: mutation.effectIndex", preflight)
        self.assertIn("functionName: mutation.functionName", preflight)
        # Callback material publication is exercised by test_scene_scalar_cursor.
        self.assertIn("invalid-effect-index-\\(mutation.effectIndex)", preflight)

    def test_material_mutation_failure_remains_typed_and_local(self) -> None:
        scalar_runtime = SCALAR_RUNTIME_SOURCE.read_text(encoding="utf-8")
        effect_bridge = EFFECT_HANDLE_BRIDGE_SOURCE.read_text(encoding="utf-8")
        preflight = PREPFLIGHT_SOURCE.read_text(encoding="utf-8")
        self.assertIn("case .mutationOverflow: \"mutation-overflow\"", scalar_runtime)
        self.assertIn("guard !functionName.isEmpty", effect_bridge)
        # Every plan yields its preparation request in the same walk; the
        # typed-local failure for material mutations is the invocation check.
        self.assertIn(
            'invocationFailure = "function-invocation-unknown-effect"', preflight
        )
        self.assertIn("SceneGraphMaterialFunctionInvocationRequest", preflight)







    def test_dynamic_snapshot_fault_is_debug_only_and_isolated_runner_owned(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        arguments_runner = DEBUG_ARGUMENTS_RUNNER_SOURCE.read_text(
            encoding="utf-8"
        )
        launch = swift_body(runner, "private static func launchScene(")

        self.assertIn("var debugDropDynamicValuesFrameIndex: UInt64?", host)
        self.assertIn("func setDebugDropDynamicValuesFrameIndex(", host)
        self.assertIn("guard Self.usesDebugEvidenceWindow else { return false }", host)
        self.assertIn("#if DEBUG", host[:host.index("var debugDropDynamicValuesFrameIndex")])
        self.assertIn(
            'after: "--mwx-debug-scene-drop-dynamic-values-frame"',
            arguments_runner,
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
        live_consumers = LIVE_CONSUMERS_SOURCE.read_text(encoding="utf-8")
        coordinator = COORDINATOR_SOURCE.read_text(encoding="utf-8")
        debug_runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let runtimeInput: SceneRuntimeInput", host)
        self.assertIn("let effectAdmissionCatalog: SceneEffectAdmissionCatalog", host)
        self.assertIn("shaderContracts: runtimeInput.shaderContracts", host)
        self.assertIn(
            "program: runtimeInput.propertyBindingProgram", live_consumers
        )
        self.assertIn(
            "effectiveValues: runtimeInput.effectivePropertyValues", live_consumers
        )
        self.assertIn("liveState: Self.makeLivePropertyState(", host)
        self.assertIn("rootURL: request.rootURL", coordinator)
        self.assertIn("rootURL: rootURL", debug_runner)
        self.assertNotIn("interpretationFileURL", coordinator)

    def test_live_property_state_merges_scalar_and_string_event_consumers(self) -> None:
        live_consumers = LIVE_CONSUMERS_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "sceneScriptScalarProgram.liveUserPropertyConsumerTargetsByKey",
            live_consumers,
        )
        self.assertIn(
            "sceneScriptStringProgram.liveUserPropertyConsumerTargetsByKey",
            live_consumers,
        )
        self.assertIn("result[key, default: []].formUnion(targets)", live_consumers)
        self.assertIn(
            "scriptUserPropertyConsumerTargetsByKey:\n"
            "                scriptUserPropertyConsumerTargetsByKey",
            live_consumers,
        )


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
        layer_color = ".layer(layerID: layer.id, field: .color)"
        image_case = derivation[
            derivation.index('case "image":') : derivation.index('case "text":')
        ]
        self.assertIn("if layer.supportsDirectLayerColorConsumer", image_case)
        self.assertIn("visibleLayerIDs.contains(layer.id)", image_case)
        self.assertIn(layer_color, image_case)
        solid_case = derivation[
            derivation.index('case "solid":') : derivation.index(
                'case "particle":'
            )
        ]
        self.assertIn(layer_color, solid_case)
        self.assertIn('case "particle"', derivation)
        self.assertIn(".particle(layerID: layer.id, field: $0)", derivation)
        self.assertIn("visibleLayerIDs.contains(layer.id)", derivation)
        self.assertIn(".text(layerID: layer.id, field: .content)", derivation)
        self.assertIn(".text(layerID: layer.id, field: .pointSize)", derivation)
        self.assertIn(".text(layerID: layer.id, field: .color)", derivation)


    def test_each_frame_reads_the_latest_live_state_values(self) -> None:
        host = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        render_start = host.index("private func renderFrame()")
        render = host[render_start:]
        self.assertIn("userValues: launchContext.liveState.userValues", render)
        self.assertNotIn("userDynamicValues", host)



if __name__ == "__main__":
    unittest.main()
