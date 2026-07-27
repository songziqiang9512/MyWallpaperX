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
LIVE_CONSUMERS_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+LiveConsumers.swift"
)
VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift"
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
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        self.assertIn("private var frameTimer: Timer?", host)
        self.assertIn("private final class Surface", host)
        self.assertIn(
            "var evaluationTransaction = SceneSurfaceEvaluationTransaction()", host
        )
        self.assertIn("let timing = sceneClock.advance", host)
        render_position = host.index("private func renderFrame()")
        broadcast_position = host.index("for surface in surfaces.values", render_position)
        snapshot_position = host.index(
            "surface.evaluationTransaction.evaluate", broadcast_position
        )
        self.assertLess(broadcast_position, snapshot_position)
        self.assertNotIn(
            "SceneDynamicSnapshot.empty(frameIndex: timing.frameIndex)", host
        )
        # 调用可能跨行（频谱等 host-shared 输入随参数增长），只锁语义不锁排版。
        self.assertIn("surface.metalView.renderFrame(", host)
        self.assertIn("dynamicValues: dynamicValues", host)
        self.assertIn("dynamicValues: SceneDynamicSnapshot", view)
        self.assertIn("dynamicValues: dynamicValues", view)
        self.assertNotIn("displayTimer", view)
        self.assertNotIn("renderStartTime", view)

    def test_launch_callers_forward_the_complete_interpretation_file(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        coordinator = COORDINATOR_SOURCE.read_text(encoding="utf-8")
        debug_runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("interpretationFile: SceneInterpretationFile", host)
        self.assertIn("let authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog", host)
        self.assertIn("shaderContracts: interpretationFile.shaderContracts", host)
        self.assertIn(
            "program: interpretationFile.propertyBindingProgram", host
        )
        self.assertIn("effectiveValues: interpretationFile.effectivePropertyValues", host)
        self.assertIn("interpretationFile: file", coordinator)
        self.assertIn("interpretationFile: model.interpretationFile", debug_runner)

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
        host = HOST_SOURCE.read_text(encoding="utf-8")
        render_start = host.index("private func renderFrame()")
        render = host[render_start:]
        self.assertIn("userValues: launchContext.liveState.userValues", render)
        self.assertNotIn("userDynamicValues", host)


if __name__ == "__main__":
    unittest.main()
