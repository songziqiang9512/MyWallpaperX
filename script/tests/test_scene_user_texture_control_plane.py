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
                    "private func handlePropertyUpdateResult(",
                ])
            scalar = method_body(CLIENT.read_text(), "private func applyPropertyValues(")
            handlers += "\n" + scalar.replace("private func", "func", 1)
            probe = work / "Probe.swift"
            probe.write_text((ROOT / "script/tests/fixtures/SceneUserTextureControlChecks.swift").read_text()
                + "\n@MainActor extension SceneDaemonClient {\n" + handlers + "\n}\n")
            sources = [
                SCENE / "Systems/Properties/SceneUserProperty.swift",
                ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift",
                ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift",
                SCENE / "Runtime/Frame/SceneScreenTopology.swift",
                SCENE / "Systems/Media/SceneAudioSpectrum.swift",
                SCENE / "Runtime/IPC/SceneDaemonProtocol.swift", TEXTURES, probe,
            ]
            result = subprocess.run(["swiftc", *map(str, sources), "-enable-upcoming-feature", "MemberImportVisibility", "-module-cache-path", str(work / "cache"),
                "-o", str(work / "control")], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(work / "control")], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            checks = json.loads(result.stdout)
            self.assertGreaterEqual(len(checks), 19)
            for name, passed in checks.items():
                with self.subTest(behavior=name):
                    self.assertTrue(passed)

    def test_stop_switch_and_transport_death_finish_pending_waiters(self):
        source = CLIENT.read_text()
        self.assertIn('finishPendingTextureUpdates(.failed("Scene playback stopped"))',
            method_body(source, "func stop(postsLaunchState:"))
        self.assertIn("finishPendingTextureUpdates(.superseded)",
            method_body(source, "func requestLaunch("))
        self.assertIn('finishPendingTextureUpdates(.failed("Scene daemon disconnected"))', EVENTS.read_text())

    def test_daemon_owns_only_request_scopes_until_ack(self):
        source = (SCENE / "Runtime/IPC/SceneDaemonRuntime.swift").read_text()
        body = source[source.index("case let .setUserTextures(update):"):
            source.index("case let .cancelLaunch(recordID):")]
        self.assertLess(body.index("startAccessingSecurityScopedResource"), body.index("host.applyUserTextureUpdate"))
        self.assertGreater(body.index("stopAccessingSecurityScopedResource"), body.index("host.applyUserTextureUpdate"))
        self.assertLess(body.index("stopAccessingSecurityScopedResource"), body.index("self?.emit(response)"))


if __name__ == "__main__":
    unittest.main()
