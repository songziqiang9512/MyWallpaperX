"""M5.4 product Scene control-plane wiring gates."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


def client_source() -> str:
    runtime = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime"
    return "\n".join(
        (runtime / name).read_text(encoding="utf-8")
        for name in ["SceneDaemonClient.swift", "SceneDaemonClient+Events.swift"]
    )


class SceneDaemonClientWiringTests(unittest.TestCase):
    def test_product_callers_do_not_reach_in_process_scene_host(self) -> None:
        product_callers = [
            "MyWallpaperX/App/AppDelegate.swift",
            "MyWallpaperX/App/MainWindowCoordinator.swift",
            "MyWallpaperX/App/MyWallpaperXApplication.swift",
            "MyWallpaperX/App/StatusBarController.swift",
            "MyWallpaperX/Core/Playback/WallpaperEngine.swift",
            "MyWallpaperX/Core/Playback/WallpaperEngine+PlaybackControl.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift",
            "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopSceneInspectionController.swift",
        ]
        for relative_path in product_callers:
            with self.subTest(path=relative_path):
                source = (ROOT / relative_path).read_text(encoding="utf-8")
                self.assertNotIn("SceneDesktopWallpaperHost", source)

    def test_daemon_runtime_explicitly_owns_the_only_product_host(self) -> None:
        runtime_path = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDaemonRuntime.swift"
        )
        host_path = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift"
        )
        runtime = runtime_path.read_text(encoding="utf-8")
        host = host_path.read_text(encoding="utf-8")
        self.assertIn("private let host = SceneDesktopWallpaperHost()", runtime)
        self.assertNotIn("SceneDesktopWallpaperHost.shared", runtime)
        self.assertNotIn("static let shared = SceneDesktopWallpaperHost()", host)

    def test_direct_host_evidence_uses_a_debug_owned_instance(self) -> None:
        runner = (
            ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner+HostOwnership.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("#if DEBUG", runner)
        self.assertIn("static let runtimeHost = SceneDesktopWallpaperHost()", runner)
        self.assertIn("static func stop()", runner)
        self.assertNotIn("SceneDesktopWallpaperHost.shared", runner)

    def test_control_plane_carries_typed_values_identity_and_texture_bookmark(self) -> None:
        command = (
            ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift"
        ).read_text(encoding="utf-8")
        client = client_source()
        self.assertIn("[String: SceneUserPropertyValue]", command)
        self.assertIn("bookmarkData: Data?", command)
        self.assertIn("recordID: String", command)
        self.assertIn('"revision": revision', client)
        self.assertIn('"recordID": recordID', client)
        self.assertIn("bookmarkData.base64EncodedString()", client)

    def test_daemon_resolves_and_host_scopes_external_texture_bookmarks(self) -> None:
        runtime = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDaemonRuntime.swift"
        ).read_text(encoding="utf-8")
        host = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("resolvingBookmarkData: bookmarkData", runtime)
        self.assertIn("options: [.withSecurityScope]", runtime)
        self.assertIn("options: []", runtime)
        self.assertIn("launchContext.userPropertyTextureURLs.values.filter", host)
        self.assertIn("startAccessingSecurityScopedResource()", host)
        self.assertIn("stopAccessingSecurityScopedResource()", host)

    def test_scene_events_are_request_filtered_before_ui_projection(self) -> None:
        client = client_source()
        self.assertIn("guard pendingRequestID == requestID else { return }", client)
        self.assertIn("requestID == activeRequestID", client)
        self.assertIn("restartBackoff.reset()", client)
        self.assertIn("maximumRestartAttempts", client)
        self.assertIn('case "propertyUpdateResult"', client)
        self.assertIn("requestLaunch(request)", client)

    def test_pending_clear_requires_matching_record_identity(self) -> None:
        service = (
            ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPlayback.swift"
        ).read_text(encoding="utf-8")
        terminal = service[service.index("func installLaunchPendingObservers") :]
        self.assertIn("clearLaunchPending(matching: recordID)", terminal)
        self.assertNotIn("self.clearLaunchPending()", terminal)
        self.assertNotIn("self?.clearLaunchPending()", terminal)


if __name__ == "__main__":
    unittest.main()
