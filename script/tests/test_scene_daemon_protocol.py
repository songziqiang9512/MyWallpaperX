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
SHUTDOWN = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift"
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
            "v": 2, "cmd": "loadScene", "rootURL": "/private/tmp/scene",
            "profile": 30, "recordID": "fixture",
            "propertyOverrides": ["enabled": true, "rate": 1.5, "label": "ok"],
            "userPropertyTextures": [
                "cover": ["path": "/private/tmp/cover.png", "bookmark": "AQID"]
            ]
        ])
        let loadValid: Bool
        if case let .success(.loadScene(root, values, textures, _, profile, recordID, requiredKeys, requestID)) = load {
            loadValid = root.path == "/private/tmp/scene"
                && profile == .efficient && recordID == "fixture" && requiredKeys.isEmpty && requestID == nil
                && values["enabled"] == .bool(true)
                && values["rate"] == .number(1.5)
                && values["label"] == .string("ok")
                && textures["cover"]?.url.path == "/private/tmp/cover.png"
                && textures["cover"]?.bookmarkData == Data([1, 2, 3])
        } else { loadValid = false }
        let shortcuts = ScenePlaybackShortcutConfiguration(revision: 9, references: [
            "open_file": .init(kind: .file, url: URL(fileURLWithPath: "/private/tmp/action.command"),
                bookmarkData: Data([3, 1, 4, 1, 5])),
            "open_page": .init(kind: .webURL, url: URL(string: "https://example.org/action?q=scene")!,
                bookmarkData: nil),
        ])
        let shortcutObject = SceneDaemonProtocol.shortcutObject(shortcuts)
        let shortcutRequestID = UUID()
        let shortcutLoadValid: Bool
        if case let .success(.loadScene(_, _, _, decoded, _, recordID, _, requestID)) = decode([
            "v": 2, "cmd": "loadScene", "rootURL": "/private/tmp/scene", "profile": 60,
            "recordID": "fixture", "requestID": shortcutRequestID.uuidString,
            "userShortcuts": shortcutObject,
        ]) {
            shortcutLoadValid = decoded == shortcuts && recordID == "fixture" && requestID == shortcutRequestID
        } else { shortcutLoadValid = false }
        let shortcutUpdate: [String: Any] = [
            "v": 2, "cmd": "setUserShortcuts", "configuration": shortcutObject,
            "recordID": "fixture", "requestID": shortcutRequestID.uuidString,
        ]
        let shortcutUpdateValid: Bool
        if case let .success(.setUserShortcuts(update, requestID)) = decode(shortcutUpdate) {
            shortcutUpdateValid = update.configuration == shortcuts && update.recordID == "fixture"
                && requestID == shortcutRequestID
        } else { shortcutUpdateValid = false }
        let invalidShortcuts = [
            ScenePlaybackShortcutConfiguration(revision: 9, references: [
                "open": .init(kind: .webURL, url: URL(string: "javascript:alert(1)")!, bookmarkData: nil),
            ]),
            ScenePlaybackShortcutConfiguration(revision: 9, references: [
                "open": .init(kind: .file, url: URL(fileURLWithPath: "/private/tmp/action.command"), bookmarkData: nil),
            ]),
        ]
        let invalidShortcutConfigurationRejected = invalidShortcuts.allSatisfy { configuration in
            var update = shortcutUpdate
            update["configuration"] = SceneDaemonProtocol.shortcutObject(configuration)
            guard case .failure(.invalidPayload("setUserShortcuts")) = decode(update) else { return false }
            if case .failure(.invalidPayload("loadScene")) = decode([
                "v": 2, "cmd": "loadScene", "rootURL": "/private/tmp/scene", "profile": 60,
                "userShortcuts": SceneDaemonProtocol.shortcutObject(configuration),
            ]) { return true }
            return false
        }
        var zeroShortcutRevision = shortcutUpdate
        zeroShortcutRevision["configuration"] = SceneDaemonProtocol.shortcutObject(.empty)
        let zeroShortcutRevisionRejected: Bool
        if case .failure(.invalidPayload("setUserShortcuts")) = decode(zeroShortcutRevision) {
            zeroShortcutRevisionRejected = true
        } else { zeroShortcutRevisionRejected = false }
        let invalidShortcutIdentityRejected = ["recordID", "requestID"].allSatisfy { key in
            var update = shortcutUpdate
            update[key] = key == "recordID" ? "" : "bad-uuid"
            if case .failure(.invalidPayload("setUserShortcuts")) = decode(update) { return true }
            return false
        }
        var legacyShortcutUpdate = shortcutUpdate
        legacyShortcutUpdate["v"] = 1
        let legacyShortcutVersionRejected: Bool
        if case .failure(.unsupportedVersion(1)) = decode(legacyShortcutUpdate) {
            legacyShortcutVersionRejected = true
        } else { legacyShortcutVersionRejected = false }
        let explicitID = UUID()
        let explicitRequestValid: Bool
        if case let .success(.loadScene(_, _, _, _, _, _, _, requestID)) = decode([
            "v": 2, "cmd": "loadScene", "rootURL": "/private/tmp/scene", "profile": 30,
            "requestID": explicitID.uuidString
        ]) { explicitRequestValid = requestID == explicitID } else { explicitRequestValid = false }
        let invalidRequestRejected = ["bad-uuid" as Any, 7, NSNull()].allSatisfy { value in
            if case .failure(.invalidPayload("loadScene")) = decode([
                "v": 2, "cmd": "loadScene", "rootURL": "/private/tmp/scene", "profile": 30,
                "requestID": value
            ]) { return true }
            return false
        }
        let propertyValid: Bool
        if case let .success(.setProperty(values, revision, recordID)) = decode([
            "v": 2, "cmd": "setProperty", "revision": 7,
            "recordID": "fixture", "values": ["rate": 2.0]
        ]) {
            propertyValid = revision == 7 && recordID == "fixture"
                && values["rate"] == .number(2)
        } else { propertyValid = false }
        let versionRejected = [1, 3].allSatisfy { version in
            if case .failure(.unsupportedVersion(version)) = decode(["v": version, "cmd": "pause"]) {
                return true
            }
            return false
        }
        let unsupportedRejected: Bool
        if case .failure(.unsupportedCommand("switchNext")) = decode([
            "v": 2, "cmd": "switchNext"
        ]) { unsupportedRejected = true } else { unsupportedRejected = false }
        let zeroRevisionRejected: Bool
        if case .failure(.invalidPayload("setProperty")) = decode([
            "v": 2, "cmd": "setProperty", "revision": 0,
            "recordID": "fixture", "values": ["rate": 2]
        ]) { zeroRevisionRejected = true } else { zeroRevisionRejected = false }
        let booleanVersionRejected: Bool
        if case .failure(.malformedEnvelope) = decode(["v": true, "cmd": "pause"]) {
            booleanVersionRejected = true
        } else { booleanVersionRejected = false }
        let numericMuteRejected: Bool
        if case .failure(.invalidPayload("setMuted")) = decode([
            "v": 2, "cmd": "setMuted", "muted": 1
        ]) { numericMuteRejected = true } else { numericMuteRejected = false }
        let spectrumToggleRetired: Bool
        if case .failure(.unsupportedCommand("setSpectrumEnabled")) = decode([
            "v": 2, "cmd": "setSpectrumEnabled", "enabled": true
        ]) { spectrumToggleRetired = true } else { spectrumToggleRetired = false }
        let numericSpectrumToggleRetired: Bool
        if case .failure(.unsupportedCommand("setSpectrumEnabled")) = decode([
            "v": 2, "cmd": "setSpectrumEnabled", "enabled": 1
        ]) { numericSpectrumToggleRetired = true } else {
            numericSpectrumToggleRetired = false
        }
        let captureFrameEmptyRejected: Bool
        if case .failure(.invalidPayload("captureFrame")) = decode([
            "v": 2, "cmd": "captureFrame", "requestID": ""
        ]) { captureFrameEmptyRejected = true } else {
            captureFrameEmptyRejected = false
        }
        let volumeValid: Bool
        if case let .success(.setVolume(volume)) = decode([
            "v": 2, "cmd": "setVolume", "volume": 0.375
        ]) {
            volumeValid = abs(Double(volume) - 0.375) < 0.0001
        } else { volumeValid = false }
        let volumeOutOfRangeRejected: Bool
        if case .failure(.invalidPayload("setVolume")) = decode([
            "v": 2, "cmd": "setVolume", "volume": 1.01
        ]) { volumeOutOfRangeRejected = true } else {
            volumeOutOfRangeRejected = false
        }
        let cancelValid: Bool
        if case .success(.cancelLaunch(recordID: "fixture")) = decode([
            "v": 2, "cmd": "cancelLaunch", "recordID": "fixture"
        ]) { cancelValid = true } else { cancelValid = false }
        let candidateID = UUID()
        let candidateControlsValid = ["commitCandidate", "finalizeCandidate", "cancelCandidate"].allSatisfy { command in
            switch decode(["v": 2, "cmd": command, "requestID": candidateID.uuidString]) {
            case let .success(.commitCandidate(requestID)): return command == "commitCandidate" && requestID == candidateID
            case let .success(.finalizeCandidate(requestID)): return command == "finalizeCandidate" && requestID == candidateID
            case let .success(.cancelCandidate(requestID, operationID)):
                return command == "cancelCandidate" && requestID == candidateID && operationID == nil
            default: return false
            }
        }
        let malformedCandidateControlsRejected = ["commitCandidate", "finalizeCandidate", "cancelCandidate"].allSatisfy { command in
            ["" as Any, "bad", 1, NSNull()].allSatisfy { value in
                if case .failure(.invalidPayload(command)) = decode(["v": 2, "cmd": command, "requestID": value]) { return true }
                return false
            }
        }
        let operationID = UUID()
        let cancelReceiptValid: Bool
        if case .success(.cancelCandidate(requestID: candidateID, operationID: operationID)) = decode([
            "v": 2, "cmd": "cancelCandidate", "requestID": candidateID.uuidString,
            "operationID": operationID.uuidString
        ]) { cancelReceiptValid = true } else { cancelReceiptValid = false }
        let outputActivityValid: Bool
        if case .success(.setOutputActive(requestID: candidateID, operationID: operationID, active: false)) = decode([
            "v": 2, "cmd": "setOutputActive", "requestID": candidateID.uuidString,
            "operationID": operationID.uuidString, "active": false
        ]) { outputActivityValid = true } else { outputActivityValid = false }
        let malformedOutputActivityRejected = ["" as Any, "bad", 1, NSNull()].allSatisfy { value in
            if case .failure(.invalidPayload("setOutputActive")) = decode([
                "v": 2, "cmd": "setOutputActive", "requestID": candidateID.uuidString,
                "operationID": value, "active": false
            ]) { return true }
            return false
        }
        let numericOutputActivityRejected: Bool
        if case .failure(.invalidPayload("setOutputActive")) = decode([
            "v": 2, "cmd": "setOutputActive", "requestID": candidateID.uuidString,
            "operationID": operationID.uuidString, "active": 1
        ]) { numericOutputActivityRejected = true } else { numericOutputActivityRejected = false }
        let displayValid: Bool
        if case let .success(.setDisplayConfiguration(screens)) = decode([
            "v": 2, "cmd": "setDisplayConfiguration", "screens": [[
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
            "v": 2, "cmd": "setDisplayConfiguration", "screens": [
                ["id": 7, "frame": ["x": 0, "y": 0, "width": 10, "height": 10], "scale": 1],
                ["id": 7, "frame": ["x": 10, "y": 0, "width": 10, "height": 10], "scale": 1]
            ]
        ]) { duplicateDisplayRejected = true } else { duplicateDisplayRejected = false }
        let badBookmarkRejected: Bool
        if case .failure(.invalidPayload("loadScene")) = decode([
            "v": 2, "cmd": "loadScene", "rootURL": "/private/tmp/scene",
            "profile": 60, "propertyOverrides": [:],
            "userPropertyTextures": ["cover": ["path": "/tmp/a", "bookmark": "%%"]]
        ]) { badBookmarkRejected = true } else { badBookmarkRejected = false }
        let bands16 = Array(repeating: 0.25, count: 16)
        let bands32 = Array(repeating: 0.5, count: 32)
        let bands64 = Array(repeating: 0.75, count: 64)
        let audioValid: Bool
        if case let .success(.publishAudioSpectrum(frame)) = decode([
            "v": 2, "cmd": "publishAudioSpectrum",
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
            "v": 2, "cmd": "publishAudioSpectrum",
            "left": Array(bands16.dropLast()), "right": bands16,
            "left32": bands32, "right32": bands32,
            "left64": bands64, "right64": bands64,
            "scopeEpoch": 9, "includesDaemonProcessOutput": true,
        ]) { audioWrongShapeRejected = true } else { audioWrongShapeRejected = false }
        let audioBooleanBandRejected: Bool
        let booleanBands: [Any] = [true] + bands16.dropFirst().map { $0 as Any }
        if case .failure(.invalidPayload("publishAudioSpectrum")) = decode([
            "v": 2, "cmd": "publishAudioSpectrum",
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
        let mediaDemand = SceneSystemMediaDemand(token: UUID(), requests: [UUID()])
        let mediaScope = SceneDaemonMediaScope(demand: mediaDemand, transportGeneration: 3)
        var emptyMedia = SystemMediaSnapshot.empty
        emptyMedia.epoch = 1; emptyMedia.revision = 1
        let mediaFrame = SceneDaemonMediaSnapshotFrame(scope: mediaScope, snapshot: emptyMedia, artwork: nil)
        let mediaData = try SceneDaemonMediaWire.encode("publishSystemMedia", mediaFrame)
        let mediaCommandValid: Bool
        if case let .success(.publishSystemMedia(decoded)) = SceneDaemonProtocol.decodeCommand(mediaData) {
            mediaCommandValid = decoded == mediaFrame
        } else { mediaCommandValid = false }
        let mediaChunk = SceneDaemonMediaArtworkChunk(scope: mediaScope, transferID: UUID(), index: 0, bytes: Data([1, 2]))
        let mediaChunkValid: Bool
        if case let .success(.publishSystemMediaArtwork(decoded)) = SceneDaemonProtocol.decodeCommand(
            try SceneDaemonMediaWire.encode("publishSystemMediaArtwork", mediaChunk)
        ) { mediaChunkValid = decoded == mediaChunk } else { mediaChunkValid = false }
        let largeMediaChunk = SceneDaemonMediaArtworkChunk(scope: mediaScope, transferID: UUID(), index: 0,
            bytes: Data(repeating: 1, count: SceneDaemonMediaWire.maximumChunkBytes + 1))
        let oversizeMediaChunkRejected: Bool
        if case .failure(.invalidPayload("publishSystemMediaArtwork")) = SceneDaemonProtocol.decodeCommand(
            try SceneDaemonMediaWire.encode("publishSystemMediaArtwork", largeMediaChunk)
        ) { oversizeMediaChunkRejected = true } else { oversizeMediaChunkRejected = false }
        let negativeMediaChunk = SceneDaemonMediaArtworkChunk(scope: mediaScope, transferID: UUID(), index: -1, bytes: Data([1]))
        let negativeMediaIndexRejected: Bool
        if case .failure(.invalidPayload("publishSystemMediaArtwork")) = SceneDaemonProtocol.decodeCommand(
            try SceneDaemonMediaWire.encode("publishSystemMediaArtwork", negativeMediaChunk)
        ) { negativeMediaIndexRejected = true } else { negativeMediaIndexRejected = false }
        let mediaWrongTypeRejected: Bool
        if case .failure(.invalidPayload("publishSystemMedia")) = decode([
            "v": 2, "cmd": "publishSystemMedia", "frame": ["scope": true]
        ]) { mediaWrongTypeRejected = true } else { mediaWrongTypeRejected = false }
        let payload = [
            "mediaCommandValid": mediaCommandValid,
            "mediaChunkValid": mediaChunkValid,
            "oversizeMediaChunkRejected": oversizeMediaChunkRejected,
            "negativeMediaIndexRejected": negativeMediaIndexRejected,
            "mediaWrongTypeRejected": mediaWrongTypeRejected,
            "loadValid": loadValid,
            "shortcutLoadValid": shortcutLoadValid,
            "shortcutUpdateValid": shortcutUpdateValid,
            "invalidShortcutConfigurationRejected": invalidShortcutConfigurationRejected,
            "zeroShortcutRevisionRejected": zeroShortcutRevisionRejected,
            "invalidShortcutIdentityRejected": invalidShortcutIdentityRejected,
            "legacyShortcutVersionRejected": legacyShortcutVersionRejected,
            "explicitRequestValid": explicitRequestValid,
            "invalidRequestRejected": invalidRequestRejected,
            "propertyValid": propertyValid,
            "versionRejected": versionRejected,
            "unsupportedRejected": unsupportedRejected,
            "zeroRevisionRejected": zeroRevisionRejected,
            "booleanVersionRejected": booleanVersionRejected,
            "numericMuteRejected": numericMuteRejected,
            "spectrumToggleRetired": spectrumToggleRetired,
            "numericSpectrumToggleRetired": numericSpectrumToggleRetired,
            "captureFrameEmptyRejected": captureFrameEmptyRejected,
            "volumeValid": volumeValid,
            "volumeOutOfRangeRejected": volumeOutOfRangeRejected,
            "cancelValid": cancelValid,
            "candidateControlsValid": candidateControlsValid,
            "cancelReceiptValid": cancelReceiptValid,
            "outputActivityValid": outputActivityValid,
            "malformedOutputActivityRejected": malformedOutputActivityRejected,
            "numericOutputActivityRejected": numericOutputActivityRejected,
            "malformedCandidateControlsRejected": malformedCandidateControlsRejected,
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
                    str(PROPERTY), str(ROOT / "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift"),
                    str(COMMAND), str(PROFILE), str(SCREEN), str(AUDIO),
                    str(ROOT / "MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSnapshotStore.swift"),
                    str(ROOT / "MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSnapshot.swift"),
                    str(SCENE / "Systems/Media/SceneMediaThumbnailInbox.swift"),
                    str(SCENE / "Runtime/IPC/SceneDaemonMediaProtocol.swift"),
                    str(PROTOCOL),
                    str(SCENE / "Runtime/IPC/SceneDaemonProtocol+UserShortcuts.swift"),
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
            for name, passed in json.loads(completed.stdout).items():
                with self.subTest(behavior=name):
                    self.assertTrue(passed)


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
