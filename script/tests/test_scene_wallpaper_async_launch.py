#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCH = (
    ROOT
    / "MyWallpaperX"
    / "Core"
    / "SteamWorkshopScene"
    / "Runtime"
    / "SceneDesktopWallpaperHost+Launch.swift"
)
HOST = (
    ROOT
    / "MyWallpaperX"
    / "Core"
    / "SteamWorkshopScene"
    / "Runtime"
    / "SceneDesktopWallpaperHost.swift"
)
COORDINATOR = ROOT / "MyWallpaperX" / "App" / "MainWindowCoordinator.swift"
DEBUG_RUNNER = ROOT / "MyWallpaperX" / "App" / "DebugScenePlaybackRunner.swift"
INSPECTION = (
    ROOT
    / "MyWallpaperX"
    / "Modules"
    / "SteamWorkshop"
    / "UI"
    / "SteamWorkshopSceneInspectionController.swift"
)
SPOT_LIGHT_RUNTIME = (
    ROOT
    / "MyWallpaperX"
    / "Core"
    / "SteamWorkshopScene"
    / "Rendering"
    / "SceneSpotLightRuntime.swift"
)
PREPARED_DEVICE_RESOURCES = (
    ROOT
    / "MyWallpaperX"
    / "Core"
    / "SteamWorkshopScene"
    / "Runtime"
    / "ScenePreparedDeviceResources.swift"
)


def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening : index + 1]
    raise AssertionError(f"unterminated function: {signature}")


class SceneWallpaperAsyncLaunchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.launch = LAUNCH.read_text(encoding="utf-8")
        cls.host = HOST.read_text(encoding="utf-8")
        cls.coordinator = COORDINATOR.read_text(encoding="utf-8")
        cls.debug_runner = DEBUG_RUNNER.read_text(encoding="utf-8")
        cls.inspection = INSPECTION.read_text(encoding="utf-8")
        cls.spot_light_runtime = SPOT_LIGHT_RUNTIME.read_text(encoding="utf-8")
        cls.prepared_device_resources = PREPARED_DEVICE_RESOURCES.read_text(
            encoding="utf-8"
        )

    def test_product_request_uses_background_preparation_entrypoint(self) -> None:
        observer = function_body(
            self.coordinator,
            "private static func observeSteamWorkshopSceneReadyToRender()",
        )
        self.assertIn("requestLaunch(", observer)
        self.assertNotIn(".launch(\n", observer)
        self.assertLess(observer.index("case .success"), observer.index("postWallpaperRuntimeWillSwitch"))

    def test_main_window_projects_central_launch_state(self) -> None:
        configure = function_body(self.coordinator, "static func configure(")
        observer = function_body(
            self.coordinator,
            "private static func observeSceneWallpaperLaunchState()",
        )
        self.assertIn("observeSceneWallpaperLaunchState()", configure)
        self.assertIn("sceneWallpaperLaunchStateDidChange", observer)
        self.assertIn("SteamWorkshopService.shared.statusMessage", observer)
        self.assertIn("当前壁纸会继续播放", observer)
        self.assertIn("正在等待首帧显示", observer)

    def test_preparation_is_off_main_and_commit_returns_to_main(self) -> None:
        request = function_body(self.launch, "func requestLaunch(")
        self.assertIn("launchPreparationQueue.async", request)
        self.assertIn("Self.prepareLaunch(", request)
        self.assertIn("DispatchQueue.main.async", request)
        self.assertIn("try self.activate(prepared.context)", request)
        self.assertLess(request.index("Self.prepareLaunch("), request.index("try self.activate"))

    def test_newer_request_and_cancel_reject_stale_work(self) -> None:
        request = function_body(self.launch, "func requestLaunch(")
        cancel = function_body(self.launch, "func cancelPendingLaunch(")
        self.assertIn("launchCancellation?.cancel()", request)
        self.assertGreaterEqual(request.count("nextLaunchRequestGeneration == requestGeneration"), 3)
        self.assertIn("nextLaunchRequestGeneration &+= 1", cancel)
        self.assertIn("cancellation?.check()", self.launch)

    def test_progress_uses_truthful_indeterminate_stages(self) -> None:
        prepare = function_body(self.launch, "private static func prepareLaunch(")
        self.assertIn(".preparingModel", prepare)
        self.assertIn("SceneRuntimeModelBuilder().build", prepare)
        self.assertNotIn("SceneDiagnosticsBuilder", prepare)
        self.assertNotIn("model.diagnostics", prepare)
        self.assertIn(".preparingPrograms", prepare)
        self.assertIn(".preparingResources", prepare)
        self.assertNotIn("percent", prepare.lower())

    def test_device_resources_prepare_before_surface_activation(self) -> None:
        prepare = function_body(self.launch, "private static func prepareLaunch(")
        host_rebuild = function_body(self.host, "private func rebuildSurfaces(")
        self.assertIn("ScenePreparedDeviceResourcesTask(", prepare)
        self.assertIn("deviceResourcesPreparation.start()", prepare)
        self.assertIn("deviceResourcesPreparation.value()", prepare)
        self.assertIn("preparedDeviceResources: preparedDeviceResources", prepare)
        self.assertLess(
            prepare.index("deviceResourcesPreparation.start()"),
            prepare.index("SceneTimelineTargetCompiler.compile("),
        )
        self.assertNotIn("SceneImageLayerPipeline(device:", host_rebuild)
        self.assertEqual(
            host_rebuild.count(
                "launchContext.preparedDeviceResources.imageLayerPipeline"
            ),
            1,
        )
        self.assertEqual(
            host_rebuild.count(
                "launchContext.preparedDeviceResources.baseImages"
            ),
            2,
        )

    def test_first_surface_runtime_warmup_overlaps_program_compilation(self) -> None:
        prepare = function_body(self.launch, "private static func prepareLaunch(")
        make_runtime = function_body(
            self.launch, "func makeResolvedMaterialRuntime()"
        )
        self.assertIn("ScenePreparedFirstSurfaceRuntimeTask(", prepare)
        self.assertIn("firstSurfaceRuntimePreparation.start()", prepare)
        self.assertIn("firstSurfaceRuntimePreparation.value()", prepare)
        self.assertLess(
            prepare.index("firstSurfaceRuntimePreparation.start()"),
            prepare.index("SceneScriptQuickJSProgramCandidate.compile("),
        )
        self.assertIn("preparedFirstSurfaceRuntime.take() ?? .init(", make_runtime)
        self.assertIn(
            "final class ScenePreparedFirstSurfaceRuntime",
            self.prepared_device_resources,
        )
        self.assertIn("private let lock = NSLock()", self.prepared_device_resources)
        self.assertIn("runtime = nil", self.prepared_device_resources)

    def test_optional_spot_light_pipeline_is_not_built_without_authored_plans(self) -> None:
        self.assertIn(
            "pipeline: @autoclosure () -> SceneSpotLightPipeline?",
            self.spot_light_runtime,
        )
        self.assertIn(
            "self.pipeline = plansByLayerID.isEmpty ? nil : pipeline()",
            self.spot_light_runtime,
        )

    def test_existing_output_is_not_switched_before_preparation_succeeds(self) -> None:
        request = function_body(self.launch, "func requestLaunch(")
        before_commit = request[: request.index("try self.activate(prepared.context)")]
        self.assertNotIn("teardownSurfaces", before_commit)
        self.assertNotIn("stopPlayback", before_commit)
        self.assertNotIn("postWallpaperRuntimeWillSwitch", before_commit)

    def test_detail_projects_progress_and_user_cancellation(self) -> None:
        self.assertIn("sceneWallpaperLaunchStateDidChange", self.inspection)
        self.assertIn("launchState.isInProgress", self.inspection)
        self.assertIn("当前壁纸会继续播放", self.inspection)
        self.assertIn("cancelPendingLaunch(recordID: record.id)", self.inspection)

    def test_host_stop_cancels_pending_preparation(self) -> None:
        stop = function_body(self.host, "func stop()")
        self.assertIn("cancelPendingLaunch()", stop)

    def test_debug_smoke_exercises_the_async_product_entrypoint(self) -> None:
        self.assertIn("--mwx-debug-scene-async-launch-smoke", self.debug_runner)
        self.assertIn("SceneDesktopWallpaperHost.shared.requestLaunch(", self.debug_runner)
        self.assertIn("phase=async-launch-request-returned", self.debug_runner)
        self.assertIn("phase=async-launch-ready", self.debug_runner)


if __name__ == "__main__":
    unittest.main()
