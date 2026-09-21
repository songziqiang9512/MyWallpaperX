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
PROTOCOL = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol.swift"
RUNTIME = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift"
PRESENTATION = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneFramePresentation.swift"
SHUTDOWN = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Shutdown.swift"
HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
LAUNCH = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
VIEW = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
RENDERER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
APPLICATION = ROOT / "MyWallpaperX/App/MyWallpaperXApplication.swift"
PROPERTY = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift"
PROFILE = ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift"
COMMAND = ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift"
SCREEN = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneScreenTopology.swift"
AUDIO = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift"


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
            "propertyOverrides": ["enabled": true, "rate": 1.5, "label": "ok"],
            "userPropertyTextures": [
                "cover": ["path": "/private/tmp/cover.png", "bookmark": "AQID"]
            ]
        ])
        let loadValid: Bool
        if case let .success(.loadScene(root, values, textures, profile, recordID)) = load {
            loadValid = root.path == "/private/tmp/scene"
                && profile == .efficient && recordID == "fixture"
                && values["enabled"] == .bool(true)
                && values["rate"] == .number(1.5)
                && values["label"] == .string("ok")
                && textures["cover"]?.url.path == "/private/tmp/cover.png"
                && textures["cover"]?.bookmarkData == Data([1, 2, 3])
        } else { loadValid = false }
        let propertyValid: Bool
        if case let .success(.setProperty(values, revision, recordID)) = decode([
            "v": 1, "cmd": "setProperty", "revision": 7,
            "recordID": "fixture", "values": ["rate": 2.0]
        ]) {
            propertyValid = revision == 7 && recordID == "fixture"
                && values["rate"] == .number(2)
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
            "recordID": "fixture", "values": ["rate": 2]
        ]) { zeroRevisionRejected = true } else { zeroRevisionRejected = false }
        let booleanVersionRejected: Bool
        if case .failure(.malformedEnvelope) = decode(["v": true, "cmd": "pause"]) {
            booleanVersionRejected = true
        } else { booleanVersionRejected = false }
        let numericMuteRejected: Bool
        if case .failure(.invalidPayload("setMuted")) = decode([
            "v": 1, "cmd": "setMuted", "muted": 1
        ]) { numericMuteRejected = true } else { numericMuteRejected = false }
        let volumeValid: Bool
        if case let .success(.setVolume(volume)) = decode([
            "v": 1, "cmd": "setVolume", "volume": 0.375
        ]) {
            volumeValid = abs(Double(volume) - 0.375) < 0.0001
        } else { volumeValid = false }
        let volumeOutOfRangeRejected: Bool
        if case .failure(.invalidPayload("setVolume")) = decode([
            "v": 1, "cmd": "setVolume", "volume": 1.01
        ]) { volumeOutOfRangeRejected = true } else {
            volumeOutOfRangeRejected = false
        }
        let cancelValid: Bool
        if case .success(.cancelLaunch(recordID: "fixture")) = decode([
            "v": 1, "cmd": "cancelLaunch", "recordID": "fixture"
        ]) { cancelValid = true } else { cancelValid = false }
        let displayValid: Bool
        if case let .success(.setDisplayConfiguration(screens)) = decode([
            "v": 1, "cmd": "setDisplayConfiguration", "screens": [[
                "id": 7, "frame": [
                    "x": -1920, "y": 0, "width": 1920, "height": 1080
                ], "scale": 2
            ]]
        ]) {
            displayValid = screens == [SceneScreenTopology(
                displayID: 7,
                frame: .init(x: -1920, y: 0, width: 1920, height: 1080),
                backingScaleFactor: 2
            )]
        } else { displayValid = false }
        let duplicateDisplayRejected: Bool
        if case .failure(.invalidPayload("setDisplayConfiguration")) = decode([
            "v": 1, "cmd": "setDisplayConfiguration", "screens": [
                ["id": 7, "frame": ["x": 0, "y": 0, "width": 10, "height": 10], "scale": 1],
                ["id": 7, "frame": ["x": 10, "y": 0, "width": 10, "height": 10], "scale": 1]
            ]
        ]) { duplicateDisplayRejected = true } else { duplicateDisplayRejected = false }
        let badBookmarkRejected: Bool
        if case .failure(.invalidPayload("loadScene")) = decode([
            "v": 1, "cmd": "loadScene", "rootURL": "/private/tmp/scene",
            "profile": 60, "propertyOverrides": [:],
            "userPropertyTextures": ["cover": ["path": "/tmp/a", "bookmark": "%%"]]
        ]) { badBookmarkRejected = true } else { badBookmarkRejected = false }
        let bands16 = Array(repeating: 0.25, count: 16)
        let bands32 = Array(repeating: 0.5, count: 32)
        let bands64 = Array(repeating: 0.75, count: 64)
        let audioValid: Bool
        if case let .success(.publishAudioSpectrum(frame)) = decode([
            "v": 1, "cmd": "publishAudioSpectrum",
            "left": bands16, "right": bands16,
            "left32": bands32, "right32": bands32,
            "left64": bands64, "right64": bands64,
            "scopeEpoch": 9, "includesDaemonProcessOutput": true,
        ]) {
            audioValid = frame.left == bands16.map(Float.init)
                && frame.left32 == bands32.map(Float.init)
                && frame.left64 == bands64.map(Float.init)
                && frame.captureToken == SceneAudioSpectrumCaptureToken(
                    scopeEpoch: 9,
                    includesCurrentProcessOutput: true
                )
        } else { audioValid = false }
        let audioWrongShapeRejected: Bool
        if case .failure(.invalidPayload("publishAudioSpectrum")) = decode([
            "v": 1, "cmd": "publishAudioSpectrum",
            "left": Array(bands16.dropLast()), "right": bands16,
            "left32": bands32, "right32": bands32,
            "left64": bands64, "right64": bands64,
            "scopeEpoch": 9, "includesDaemonProcessOutput": true,
        ]) { audioWrongShapeRejected = true } else { audioWrongShapeRejected = false }
        let audioBooleanBandRejected: Bool
        let booleanBands: [Any] = [true] + bands16.dropFirst().map { $0 as Any }
        if case .failure(.invalidPayload("publishAudioSpectrum")) = decode([
            "v": 1, "cmd": "publishAudioSpectrum",
            "left": booleanBands, "right": bands16,
            "left32": bands32, "right32": bands32,
            "left64": bands64, "right64": bands64,
            "scopeEpoch": 9, "includesDaemonProcessOutput": true,
        ]) { audioBooleanBandRejected = true } else { audioBooleanBandRejected = false }
        let activeAdmission = SceneDaemonEventAdmission(
            sessionGeneration: 7,
            hasActiveTransport: true,
            generationIsRetiring: false,
            terminationIsExpected: false
        )
        let noTransportAdmission = SceneDaemonEventAdmission(
            sessionGeneration: 7,
            hasActiveTransport: false,
            generationIsRetiring: false,
            terminationIsExpected: false
        )
        let retiringAdmission = SceneDaemonEventAdmission(
            sessionGeneration: 7,
            hasActiveTransport: true,
            generationIsRetiring: true,
            terminationIsExpected: true
        )
        let eventAdmissionValid = activeAdmission.accepts(generation: 7)
            && !activeAdmission.accepts(generation: 6)
            && !noTransportAdmission.accepts(generation: 7)
            && !retiringAdmission.accepts(generation: 7)
        let profileBudgetsValid =
            PlaybackPerformanceProfile.standard.sceneTextureDecodeCacheByteBudget
                == 1_024 * 1_024 * 1_024
            && PlaybackPerformanceProfile.efficient.sceneTextureDecodeCacheByteBudget
                == 512 * 1_024 * 1_024
        let payload = [
            "loadValid": loadValid,
            "propertyValid": propertyValid,
            "versionRejected": versionRejected,
            "unsupportedRejected": unsupportedRejected,
            "zeroRevisionRejected": zeroRevisionRejected,
            "booleanVersionRejected": booleanVersionRejected,
            "numericMuteRejected": numericMuteRejected,
            "volumeValid": volumeValid,
            "volumeOutOfRangeRejected": volumeOutOfRangeRejected,
            "cancelValid": cancelValid,
            "displayValid": displayValid,
            "duplicateDisplayRejected": duplicateDisplayRejected,
            "badBookmarkRejected": badBookmarkRejected,
            "audioValid": audioValid,
            "audioWrongShapeRejected": audioWrongShapeRejected,
            "audioBooleanBandRejected": audioBooleanBandRejected,
            "eventAdmissionValid": eventAdmissionValid,
            "profileBudgetsValid": profileBudgetsValid,
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
                    str(PROPERTY), str(COMMAND), str(PROFILE), str(SCREEN), str(AUDIO),
                    str(PROTOCOL),
                    str(harness),
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

    def test_performance_profile_updates_shared_texture_decode_budget(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        method = function_body(host, "func applyPerformanceProfile(")
        self.assertIn("performanceProfile = profile", method)
        self.assertIn("textureDecodeCacheBudget.updateMaximumBytes", method)
        self.assertIn("profile.sceneTextureDecodeCacheByteBudget", method)

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

    def test_daemon_mode_skips_main_ui_and_reports_property_results(self) -> None:
        application = APPLICATION.read_text(encoding="utf-8")
        main = function_body(application, "static func main()")
        branch = main[: main.index("let delegate = AppDelegate()")]
        self.assertIn("SceneDaemonRuntime.isRequested", branch)
        self.assertIn("runtime.configure()", branch)
        self.assertIn("return", branch)
        self.assertNotIn("MainWindowCoordinator.configure", branch)
        runtime = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("failure.code", runtime)
        self.assertIn('"event": "propertyUpdateResult"', runtime)
        self.assertIn('"accepted": accepted', runtime)
        self.assertIn("sendLatestStats", runtime)
        self.assertIn("case let .setDisplayConfiguration(topology)", runtime)
        self.assertIn("host.applyDisplayConfiguration(topology)", runtime)


if __name__ == "__main__":
    unittest.main()
