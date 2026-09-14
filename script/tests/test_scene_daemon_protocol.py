"""M5.2 Scene daemon protocol and lifecycle boundary gates."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_wallpaper_async_launch import function_body


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PROTOCOL = SCENE / "Runtime/SceneDaemonProtocol.swift"
RUNTIME = SCENE / "Runtime/SceneDaemonRuntime.swift"
PRESENTATION = SCENE / "Runtime/SceneFramePresentation.swift"
SHUTDOWN = SCENE / "Runtime/SceneDesktopWallpaperHost+Shutdown.swift"
HOST = SCENE / "Runtime/SceneDesktopWallpaperHost.swift"
LAUNCH = SCENE / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
VIEW = SCENE / "Rendering/SceneMetalView.swift"
RENDERER = SCENE / "Rendering/SceneMetalRenderer.swift"
APPLICATION = ROOT / "MyWallpaperX/App/MyWallpaperXApplication.swift"
PROPERTY = SCENE / "Properties/SceneUserProperty.swift"
PROFILE = ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift"


HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
        func decode(_ object: [String: Any]) -> Result<SceneDaemonCommand, SceneDaemonProtocolFailure> {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return SceneDaemonProtocol.decodeCommand(data)
        }
        let load = decode([
            "v": 1, "cmd": "loadScene", "rootURL": "/private/tmp/scene",
            "profile": 30, "recordID": "fixture",
            "propertyOverrides": ["enabled": true, "rate": 1.5, "label": "ok"]
        ])
        let loadValid: Bool
        if case let .success(.loadScene(root, values, profile, recordID)) = load {
            loadValid = root.path == "/private/tmp/scene"
                && profile == .efficient && recordID == "fixture"
                && values["enabled"] == .bool(true)
                && values["rate"] == .number(1.5)
                && values["label"] == .string("ok")
        } else { loadValid = false }
        let propertyValid: Bool
        if case let .success(.setProperty(values, revision)) = decode([
            "v": 1, "cmd": "setProperty", "revision": 7,
            "values": ["rate": 2.0]
        ]) {
            propertyValid = revision == 7 && values["rate"] == .number(2)
        } else { propertyValid = false }
        let versionRejected: Bool
        if case .failure(.unsupportedVersion(2)) = decode(["v": 2, "cmd": "pause"]) {
            versionRejected = true
        } else { versionRejected = false }
        let unsupportedRejected: Bool
        if case .failure(.unsupportedCommand("switchNext")) = decode([
            "v": 1, "cmd": "switchNext"
        ]) { unsupportedRejected = true } else { unsupportedRejected = false }
        let zeroRevisionRejected: Bool
        if case .failure(.invalidPayload("setProperty")) = decode([
            "v": 1, "cmd": "setProperty", "revision": 0,
            "values": ["rate": 2]
        ]) { zeroRevisionRejected = true } else { zeroRevisionRejected = false }
        let booleanVersionRejected: Bool
        if case .failure(.malformedEnvelope) = decode(["v": true, "cmd": "pause"]) {
            booleanVersionRejected = true
        } else { booleanVersionRejected = false }
        let numericMuteRejected: Bool
        if case .failure(.invalidPayload("setMuted")) = decode([
            "v": 1, "cmd": "setMuted", "muted": 1
        ]) { numericMuteRejected = true } else { numericMuteRejected = false }
        let payload = [
            "loadValid": loadValid,
            "propertyValid": propertyValid,
            "versionRejected": versionRejected,
            "unsupportedRejected": unsupportedRejected,
            "zeroRevisionRejected": zeroRevisionRejected,
            "booleanVersionRejected": booleanVersionRejected,
            "numericMuteRejected": numericMuteRejected,
        ]
        print(String(data: try JSONEncoder().encode(payload), encoding: .utf8)!)
    }
}
'''


class SceneDaemonProtocolTests(unittest.TestCase):
    def test_production_decoder_preserves_types_and_rejects_bad_envelopes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-daemon-protocol-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compiled = subprocess.run(
                [
                    "xcrun", "swiftc", "-parse-as-library",
                    str(PROPERTY), str(PROFILE), str(PROTOCOL), str(harness),
                    "-o", str(binary),
                ],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(binary)], capture_output=True, text=True, timeout=10
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(all(json.loads(completed.stdout).values()))

    def test_first_frame_is_request_bound_actual_drawable_presentation(self) -> None:
        launch = LAUNCH.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        view = VIEW.read_text(encoding="utf-8")
        renderer = RENDERER.read_text(encoding="utf-8")
        presentation = PRESENTATION.read_text(encoding="utf-8")
        runtime = RUNTIME.read_text(encoding="utf-8")
        request = function_body(launch, "func requestLaunch(")
        render = function_body(renderer, "func renderFrame(")
        self.assertIn("requestID: requestID", request)
        self.assertIn("firstFramePresentationRegistration: .init(", request)
        self.assertIn("firstFramePresentationRegistration", host)
        self.assertIn("firstFramePresentationRegistration = nil", view)
        self.assertIn("drawable.addPresentedHandler", presentation)
        self.assertIn("DispatchQueue.main.async", presentation)
        self.assertIn("ProcessInfo.processInfo.systemUptime", presentation)
        self.assertLess(
            render.index("onDrawableWillPresent?(drawable)"),
            render.index("commandBuffer.present(drawable)"),
        )
        self.assertIn("presentation.requestID == self.currentRequestID", runtime)
        self.assertNotIn("launchPhaseSnapshot()[.firstVisibleFrame]", runtime)

    def test_shutdown_stops_then_drains_every_existing_surface_queue(self) -> None:
        shutdown = SHUTDOWN.read_text(encoding="utf-8")
        method = function_body(shutdown, "func stopAndDrainGPU(")
        self.assertLess(method.index("commandQueues ="), method.index("stop()"))
        self.assertIn("queue.makeCommandBuffer()", method)
        self.assertLess(method.index("buffer.commit()"), method.index("waitUntilCompleted()"))
        self.assertIn("barriers.count == commandQueues.count", method)
        self.assertIn("$0.status == .completed && $0.error == nil", method)
        runtime = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("stopAndDrainGPU", runtime)
        self.assertIn('"gpuDrained": drained', runtime)
        self.assertIn("writer.sendCritical(data)", runtime)

    def test_daemon_mode_skips_main_ui_and_reports_rejections(self) -> None:
        application = APPLICATION.read_text(encoding="utf-8")
        main = function_body(application, "static func main()")
        branch = main[: main.index("let delegate = AppDelegate()")]
        self.assertIn("SceneDaemonRuntime.isRequested", branch)
        self.assertIn("runtime.configure()", branch)
        self.assertIn("return", branch)
        self.assertNotIn("MainWindowCoordinator.configure", branch)
        runtime = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("failure.code", runtime)
        self.assertIn('code: "command-rejected"', runtime)
        self.assertIn("sendLatestStats", runtime)


if __name__ == "__main__":
    unittest.main()
