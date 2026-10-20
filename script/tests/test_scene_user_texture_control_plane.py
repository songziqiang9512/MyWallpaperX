"""CPU behavior gates for user texture acknowledgement and Client replay."""

from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_routing import method_body

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
CLIENT = SCENE / "Runtime/IPC/SceneDaemonClient.swift"
EVENTS = SCENE / "Runtime/IPC/SceneDaemonClient+Events.swift"
TEXTURES = SCENE / "Runtime/IPC/SceneDaemonClient+UserTextures.swift"


class SceneUserTextureControlPlaneTests(unittest.TestCase):
    def test_native_protocol_client_ack_generation_and_first_present(self):
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-texture-control-") as directory:
            work = Path(directory)
            events = EVENTS.read_text()
            handlers = "\n".join(method_body(events, signature).replace("private func", "func", 1)
                .replace("private static func", "static func", 1) for signature in [
                    "private func handleLaunchState(", "private func handleFirstFrame(",
                    "static func unsignedInteger(", "private static func double(",
                    "private func handlePropertyUpdateResult(", "func handleTermination(",
                ])
            scalar = method_body(CLIENT.read_text(), "private func applyPropertyValues(")
            handlers += "\n" + scalar.replace("private func", "func", 1)
            handlers += "\n" + method_body(CLIENT.read_text(), "func stop(postsLaunchState:")
            handlers += "\n" + method_body(CLIENT.read_text(), "func requestLaunch(")
            handlers += "\n" + method_body(CLIENT.read_text(), "func startLaunch(")
            handlers += "\n" + method_body((EVENTS.parent / "SceneDaemonClient+SwitchEndpoint.swift").read_text(), "func commitPresentedScene(")
            handlers += "\n" + method_body(CLIENT.read_text(), "func cancelPreparationForRuntimeSwitch(")
            probe = work / "Probe.swift"
            probe.write_text((ROOT / "script/tests/fixtures/SceneUserTextureControlChecks.swift").read_text()
                + "\n@MainActor extension SceneDaemonClient {\n" + handlers + "\n}\n")
            sources = [
                SCENE / "Systems/Properties/SceneUserProperty.swift",
                ROOT / "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift",
                ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift",
                ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift",
                SCENE / "Runtime/Frame/SceneScreenTopology.swift",
                SCENE / "Systems/Media/SceneAudioSpectrum.swift",
                ROOT / "MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSnapshotStore.swift",
                ROOT / "MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSnapshot.swift",
                SCENE / "Systems/Media/SceneMediaThumbnailInbox.swift",
                SCENE / "Runtime/IPC/SceneDaemonMediaProtocol.swift",
                SCENE / "Runtime/IPC/SceneDaemonProtocol.swift",
                SCENE / "Runtime/IPC/SceneDaemonProtocol+UserShortcuts.swift", TEXTURES, probe,
            ]
            result = subprocess.run(["swiftc", "-D", "DEBUG", *map(str, sources), "-enable-upcoming-feature", "MemberImportVisibility", "-module-cache-path", str(work / "cache"),
                "-o", str(work / "control")], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(work / "control")], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            checks = json.loads(result.stdout)
            self.assertGreaterEqual(len(checks), 19)
            self.assertTrue({"explicit_stop_supersedes_before_transport_exit", "stop_exit_is_expected_and_silent",
                "cancelled_launch_supersedes", "failed_launch_remains_failure", "transport_death_finishes_failed",
                "stop_chain_callbacks_complete", "stop_chain_pending_empty", "stop_chain_no_retired_send",
                "switch_chain_callbacks_complete", "switch_chain_pending_empty", "switch_chain_no_retired_send",
                "termination_chain_callbacks_complete", "termination_chain_pending_empty", "termination_chain_no_retired_send",
                "nested_drain_keeps_admission_closed", "normal_phase_retry_after_drain"}.issubset(checks))
            for name, passed in checks.items():
                with self.subTest(behavior=name):
                    self.assertTrue(passed)

    def test_daemon_owns_only_request_scopes_until_ack(self):
        source = (SCENE / "Runtime/IPC/SceneDaemonRuntime.swift").read_text()
        body = source[source.index("case let .setUserTextures(update):"):
            source.index("case let .cancelLaunch(recordID):")]
        self.assertLess(body.index("startAccessingSecurityScopedResource"), body.index("host.applyUserTextureUpdate"))
        self.assertGreater(body.index("stopAccessingSecurityScopedResource"), body.index("host.applyUserTextureUpdate"))
        self.assertLess(body.index("stopAccessingSecurityScopedResource"), body.index("self?.emit(response)"))


if __name__ == "__main__":
    unittest.main()
