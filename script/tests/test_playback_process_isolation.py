"""Real pipe delivery while AppKit main is blocked; product codecs and mailbox."""
import shutil
import importlib.util
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from script.tests.test_web_compat_parity import source_block

ROOT = Path(__file__).resolve().parents[2]

HARNESS = r'''
import Foundation

@main enum Harness {
    static func expect(_ value: Bool, _ reason: String) {
        precondition(value, reason)
    }

    static func main() throws {
        let id = UUID()
        let request = WallpaperEngine.WebWallpaperLaunchRequest(id: id,
            entryURL: URL(fileURLWithPath: "/fixture/index.html"),
            rootURL: URL(fileURLWithPath: "/fixture"), propertiesJSON: "{\"value\":1}",
            source: .steamWorkshop, recordID: "fixture", language: "en-us",
            runtimeProfile: .standard, multiDisplayEnabled: true)
        let state = WallpaperEngine.WebWallpaperRuntimeState(paused: true,
            volume: 0.6, playbackRate: 1.25, spectrumLevels: nil)
        let data = try DaemonNewlineJSON.encode(WebDaemonEnvelope(requestID: id,
            payload: WebDaemonCommand.launch(.init(request, state: state, hosts: ["example.com"]))))
        let decoded = try JSONDecoder().decode(WebDaemonEnvelope<WebDaemonCommand>.self, from: data)
        guard case let .launch(launch) = decoded.payload else { fatalError("launch roundtrip") }
        expect(decoded.requestID == id && decoded.version == 1, "envelope identity")
        expect(launch.request(id: id).propertiesJSON == request.propertiesJSON
            && launch.state.paused && launch.state.playbackRate == 1.25, "immutable launch roundtrip")
        expect(launch.request(id: id).resourceLifetime == nil, "leases stay in parent")

        var song = SystemMediaSnapshot.empty
        song.enabled = true; song.epoch = 1; song.sessionID = "track"; song.sessionGeneration = 1
        song.media.current = Data(repeating: 1, count: 16 * 1_024 * 1_024)
        song.webThumbnail = "data:image/png;base64," + String(repeating: "A", count: 100_000)
        let fullMedia = WebDaemonMediaSnapshot(song, previous: nil)
        let encodedMedia = try JSONEncoder().encode(fullMedia)
        expect(encodedMedia.count < 150_000, "Web must not transport Scene original artwork")
        let resolvedMedia = fullMedia.resolve(previous: nil)!
        expect(resolvedMedia.media.current == nil && resolvedMedia.webThumbnail == song.webThumbnail, "Web projection preserves only its own cover")
        let metadata = WebDaemonMediaSnapshot(song, previous: fullMedia.artworkKey)
        let encodedMetadata = try JSONEncoder().encode(metadata)
        expect(encodedMetadata.count < 2_000, "timeline updates must not reencode the cover")
        expect(metadata.resolve(previous: resolvedMedia)?.webThumbnail == song.webThumbnail, "metadata retains same-identity art")
        var otherTrack = song; otherTrack.sessionGeneration = 2
        expect(metadata.resolve(previous: otherTrack) == nil, "old-track art must not survive ABA")
        expect(metadata.resolve(previous: nil) == nil, "missing complete snapshot requires replay")
        song.webThumbnail = nil
        let clear = WebDaemonMediaSnapshot(song, previous: fullMedia.artworkKey)
        expect(clear.resolve(previous: resolvedMedia)?.webThumbnail == nil, "cover deletion remains an explicit clear")

        let pipe = Pipe()
        let readOne = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            WebDaemonPipeReader.read(from: pipe.fileHandleForReading) { chunk in
                expect(chunk == Data("small-launch".utf8), "fragmented pipe input")
                readOne.signal()
                return false
            }
        }
        try pipe.fileHandleForWriting.write(contentsOf: Data("small-launch".utf8))
        let consumedWhileOpen = readOne.wait(timeout: .now() + 1) == .success
        try pipe.fileHandleForWriting.close()
        expect(consumedWhileOpen, "small controls must not wait for EOF or a full read buffer")

        let mailbox = WebDaemonMailbox()
        var wakes = 0
        for (text, latest) in [("one", true), ("two", true), ("pause", false), ("three", true), ("four", true)] {
            expect(mailbox.submit(Data(text.utf8), latest: latest, schedule: { wakes += 1 }), "mailbox admission")
        }
        var controls: [String] = []
        while let item = mailbox.take() { controls.append(String(decoding: item, as: UTF8.self)) }
        expect(controls == ["two", "pause", "four"] && wakes == 1, "control is a latest-value barrier")
        expect(!mailbox.submit(Data(count: WebDaemonProtocol.maximumFrameBytes + 1), latest: false, schedule: {}), "oversize denied")
        mailbox.close()
        expect(!mailbox.submit(Data(), latest: true, schedule: {}), "closed mailbox rejects late work")

        let path = CommandLine.arguments[1]
        let transport = DaemonProcessTransport(executableURL: URL(fileURLWithPath: "/usr/bin/tee"), arguments: [path])
        try transport.start()
        defer { transport.terminate() }
        let delivery = PlaybackSpectrumDelivery()
        let demand = SceneAudioSpectrumCaptureDemand(requiresSpectrum: true,
            includesCurrentProcessOutput: false, scopeEpoch: 7)
        var route = SceneAudioSpectrumCaptureRoutingState()
        route.update(route: .daemon(demand, generation: 10))
        delivery.configure(overlay: true, web: true, barCount: 28, routing: route,
            scene: .init(generation: 10, demand: demand, transport: transport))
        delivery.setWebTargets([.init(requestID: id, transport: transport)])
        delivery.setVideoTargets([transport])
        let frame = SceneAudioSpectrumRoutedFrame(left: Array(repeating: 0.5, count: 16),
            right: Array(repeating: 0.5, count: 16), left32: Array(repeating: 0.5, count: 32),
            right32: Array(repeating: 0.5, count: 32), left64: Array(repeating: 0.5, count: 64),
            right64: Array(repeating: 0.5, count: 64), captureToken: .init(
                scopeEpoch: route.scopeEpoch, includesCurrentProcessOutput: false))
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            // Separate packets by a control so every engine's payload must reach
            // the real pipe; coalescing uses one latest slot per control segment.
            for _ in 0..<10 {
                delivery.publishOverlay([0.5, 0.6])
                transport.sendRequired(Data("{}\n".utf8))
                delivery.publishWeb(Array(repeating: 0.4, count: 128))
                transport.sendRequired(Data("{}\n".utf8))
                delivery.publishScene(frame)
                Thread.sleep(forTimeInterval: 0.01)
            }
            finished.signal()
        }
        // Deliberately do not pump the main run loop: parent output callbacks
        // cannot execute here. Capture-to-child publication must still progress.
        Thread.sleep(forTimeInterval: 0.4)
        expect(finished.wait(timeout: .now()) == .success, "worker independent of parent main")
        let lines = try String(contentsOfFile: path, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        expect(lines.contains { $0.contains("setSpectrumLevels") }, "video received during main stall")
        expect(lines.contains { $0.contains("pushAudioSpectrum") }, "web received during main stall")
        expect(lines.contains { $0.contains("publishAudioSpectrum") }, "scene received during main stall")

        // A new daemon reuses its local scope 7. The capture epoch must still
        // reject the old tap's frame (ABA/generation counterexample).
        route.update(route: .daemon(demand, generation: 11))
        delivery.configure(overlay: false, web: false, barCount: 28, routing: route,
            scene: .init(generation: 11, demand: demand, transport: transport))
        Thread.sleep(forTimeInterval: 0.1)
        let pausedLines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        let pausedPackets = pausedLines.compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        let videoSilence = pausedPackets.last { $0["action"] as? String == "setSpectrumLevels" }
        expect((videoSilence?["spectrumLevels"] as? [Double]) == Array(repeating: 0, count: 28),
            "pause must clear the old Video endpoint")
        let pausedWeb = pausedLines.compactMap {
            try? JSONDecoder().decode(WebDaemonEnvelope<WebDaemonCommand>.self, from: Data($0.utf8))
        }
        guard case let .runtime(.pushAudioSpectrum(pausedSilence)) = pausedWeb.last?.payload else {
            fatalError("pause must deliver a final Web packet")
        }
        expect(pausedSilence == Array(repeating: 0, count: 128), "pause clears Web replay in child")
        let before = pausedLines.count
        delivery.publishScene(frame)
        delivery.publishWeb(Array(repeating: 0.9, count: 128))
        delivery.publishOverlay([0.9])
        Thread.sleep(forTimeInterval: 0.1)
        let after = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").count
        expect(before == after, "revoked routes cannot publish into replacements")
        // Exercise the sole production Web delivery owner. It preserves
        // every complete snapshot, stereo/spikes, silence and malformed reset.
        delivery.configure(overlay: false, web: true, barCount: 28, routing: route, scene: nil)
        let stereo = Array(repeating: Float(0.2), count: 64) + Array(repeating: Float(1.5), count: 64)
        for index in 0..<120 {
            let levels = index.isMultiple(of: 2) ? stereo : Array(repeating: Float(0.8), count: 128)
            expect(delivery.publishWeb(levels), "valid frame admitted with video overlay off")
            expect(delivery.currentWebLevels == levels, "no second response curve or cadence gate")
        }
        expect(!delivery.publishWeb(Array(repeating: 0.4, count: 127)), "wrong count rejected")
        expect(delivery.currentWebLevels.isEmpty, "wrong count clears replay")
        var invalid = stereo; invalid[7] = .nan
        expect(!delivery.publishWeb(invalid), "nonfinite rejected")
        expect(delivery.currentWebLevels.isEmpty, "nonfinite clears replay")
        transport.sendRequired(Data("{}\n".utf8))
        Thread.sleep(forTimeInterval: 0.1)
        let frames = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        let delivered = frames.compactMap { try? JSONDecoder().decode(WebDaemonEnvelope<WebDaemonCommand>.self, from: Data($0.utf8)) }
        guard case let .runtime(.pushAudioSpectrum(silence)) = delivered.last?.payload else { fatalError("missing Web output") }
        expect(silence.count == 128 && silence.allSatisfy { $0 == 0 }, "malformed capture publishes typed silence")
        expect(delivery.publishWeb(Array(repeating: 0, count: 128)), "silence admitted")
        expect(delivery.currentWebLevels.allSatisfy { $0 == 0 }, "silence retained")
        delivery.configure(overlay: false, web: false, barCount: 28, routing: route, scene: nil)
        expect(!delivery.publishWeb(stereo) && delivery.currentWebLevels.isEmpty, "late disabled callbacks cannot seed the next consumer")
        print("playback-process-isolation-pass")
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class PlaybackProcessIsolationTests(unittest.TestCase):
    def test_packaged_roles_are_background_before_runtime_configuration(self):
        project = json.loads(subprocess.check_output([
            "plutil", "-convert", "json", "-o", "-", str(ROOT / "MyWallpaperX.xcodeproj/project.pbxproj")
        ], text=True))["objects"]
        target = next(value for value in project.values()
                      if value.get("isa") == "PBXNativeTarget" and value.get("name") == "MyWallpaperX")
        configs = [project[key] for key in project[target["buildConfigurationList"]]["buildConfigurations"]]
        self.assertEqual({config["name"] for config in configs}, {"Debug", "Release"})
        with tempfile.TemporaryDirectory(prefix="mwx-packaged-launch-role-") as tmp:
            directory = Path(tmp)
            swift = directory / "Probe.swift"
            swift.write_text("import AppKit\nlet app = NSApplication.shared\nprint(app.activationPolicy().rawValue)\n")
            probe = directory / "probe"
            compile_result = subprocess.run(["xcrun", "swiftc", str(swift), "-o", str(probe)],
                text=True, capture_output=True, timeout=120)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            for config in configs:
                app = directory / (config["name"] + ".app")
                executable = app / "Contents/MacOS/Probe"
                executable.parent.mkdir(parents=True)
                shutil.copy2(probe, executable)
                is_agent = config["buildSettings"].get("INFOPLIST_KEY_LSUIElement") in ("YES", "1", True)
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": "com.mywallpaperx.tests.launch-role." + config["name"].lower(),
                    "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL", "LSUIElement": is_agent,
                }))
                result = subprocess.run([str(executable)], text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                # This precedes configure(), so hiding the Dock later cannot pass.
                self.assertEqual(result.stdout.strip(), "1", config["name"] + ": ordinary App registration")

    def test_web_renderer_launch_policy_keeps_desktop_window_visible_without_activation(self):
        source = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonRuntime.swift").read_text()
        configure = source.split("    func configure() {", 1)[1].split("        NSApp.delegate = self", 1)[0]
        harness = r'''
import AppKit
import Darwin
import Foundation
final class HostWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
let app = NSApplication.shared
CONFIGURE
func expect(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
var activated = false
var window: NSWindow?
let activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
    object: app, queue: .main) { _ in activated = true }
let launchObserver = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification,
    object: app, queue: .main) { _ in
    // Real Web surfaces arrive through IPC after AppKit has launched.
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        window = HostWindow(contentRect: NSRect(x: 0, y: 0, width: 2, height: 2),
            styleMask: .borderless, backing: .buffered, defer: false)
        window!.backgroundColor = .clear
        window!.isOpaque = false
        window!.ignoresMouseEvents = true
        window!.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window!.orderFrontRegardless()
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            let permitsActivation = CommandLine.arguments.contains("--expect-evidence")
            expect(window!.isVisible, "desktop surface must remain visible")
            expect(app.activationPolicy() == (permitsActivation ? .accessory : .prohibited), "renderer policy")
            if !permitsActivation {
                expect(!activated && !app.isActive, "renderer stole foreground activation")
            }
            print("renderer-focus-pass")
            app.terminate(nil)
        }
    }
}
app.run()
'''.replace("CONFIGURE", configure)
        with tempfile.TemporaryDirectory(prefix="mwx-renderer-focus-") as tmp:
            directory = Path(tmp)
            swift = directory / "Focus.swift"
            swift.write_text(harness)
            app = directory / "Focus.app"
            executable = app / "Contents/MacOS/Focus"
            executable.parent.mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.mywallpaperx.tests.renderer-focus",
                "CFBundleExecutable": "Focus", "CFBundlePackageType": "APPL", "LSUIElement": False,
            }))
            for debug in [True, False]:
                compile_result = subprocess.run(["xcrun", "swiftc", *(["-D", "DEBUG"] if debug else []),
                    str(swift), "-o", str(executable)], text=True, capture_output=True, timeout=120)
                self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
                cases = [[], ["--mwx-debug-web-evidence-dir"]]
                for arguments in cases:
                    if debug and arguments:
                        arguments += ["--expect-evidence"]
                    result = subprocess.run([str(executable), *arguments], text=True,
                        capture_output=True, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("renderer-focus-pass", result.stdout)

    def test_native_gate_does_not_promote_missing_preconditions_to_pass(self):
        spec = importlib.util.spec_from_file_location("isolation_benchmark", ROOT / "script/playback_process_isolation_benchmark.py")
        module = importlib.util.module_from_spec(spec)
        with patch.object(sys, "path", [str(ROOT / "script"), *sys.path]):
            spec.loader.exec_module(module)
        report = {"checks": {"first": True, "second": True}, "notCovered": {},
                  "outcome": "passed", "passed": True}
        self.assertEqual(module.native_outcome(report, 2), "passed")
        incomplete = {"checks": {"first": True}, "notCovered": {"second": "idle process not created"},
                      "outcome": "incomplete", "passed": False}
        self.assertEqual(module.native_outcome(incomplete, 2), "incomplete")
        for invalid in [
            {**incomplete, "passed": True},
            {**report, "checks": {"first": True}},
            {**report, "checks": {"first": True, "second": 1}},
            {**incomplete, "checks": {"first": False}},
            {**incomplete, "notCovered": {"first": "duplicate"}},
        ]:
            self.assertEqual(module.native_outcome(invalid, 2), "failed")

    def test_capture_follows_live_video_targets_and_retains_web_scene_demand(self):
        source = (ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+SystemAudioSpectrum.swift").read_text()
        lifecycle = (ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+DaemonSessionLifecycle.swift").read_text()
        methods = source_block(source, "func refreshSystemAudioSpectrumCapture()") + "\n" + source_block(lifecycle, "func refreshVideoSpectrumTargets()")
        support = r'''
import Foundation
final class PlaybackCommandMultiplexer { static let shared = PlaybackCommandMultiplexer(); var isPlaybackPaused = false }
final class SceneDaemonClient { static let shared = SceneDaemonClient(); var spectrumDeliveryTarget: Int? }
final class Recorder {
    var overlay = false, web = false, scene = false
    func setConsumers(overlayEnabled: Bool, webEnabled: Bool, sceneEnabled: Bool,
                      includeCurrentProcessAudio: Bool, sceneCaptureScopeEpoch: UInt64) {
        overlay = overlayEnabled; web = webEnabled; scene = sceneEnabled
    }
}
final class Delivery {
    var targets: [Int] = []
    func setVideoTargets(_ value: [Int]) { targets = value }
    func configure(overlay: Bool, web: Bool, barCount: Int,
                   routing: SceneAudioSpectrumCaptureRoutingState, scene: Int?) {}
}
final class WallpaperEngine {
    final class ProcessState { var isRunning = true }
    final class Session { let process = ProcessState(); let transport = 1 }
    var displaySessions: [Int: Session] = [:]
    var currentSystemAudioSpectrumEnabled = true, currentWebAudioSpectrumRequested = false
    var currentWebRequestID: UUID?
    var currentSystemAudioSpectrumBarCount = 28
    var sceneDaemonAudioSpectrumDemand = SceneAudioSpectrumCaptureDemand.none
    var sceneDaemonAudioSpectrumGeneration: UInt64?
    var sceneAudioSpectrumCaptureRouting = SceneAudioSpectrumCaptureRoutingState()
    let spectrumDelivery = Delivery(), systemAudioSpectrumService = Recorder()
'''
        harness = r'''
}
@main enum Harness {
    static func main() {
        let e = WallpaperEngine(), output = e.systemAudioSpectrumService
        e.refreshSystemAudioSpectrumCapture()
        precondition(!output.overlay && !output.web && !output.scene, "enabled setting alone must not capture")
        let session = WallpaperEngine.Session(); e.displaySessions[1] = session
        e.refreshVideoSpectrumTargets()
        precondition(output.overlay && e.spectrumDelivery.targets == [1], "new Video target starts overlay capture")
        session.process.isRunning = false; e.refreshVideoSpectrumTargets()
        precondition(!output.overlay, "dead Video target must not retain capture")
        session.process.isRunning = true
        e.currentWebAudioSpectrumRequested = true
        e.refreshVideoSpectrumTargets()
        precondition(e.currentWebRequestID == nil && output.overlay && output.web,
            "preparing Web demand must not wait for product adoption")
        e.currentWebRequestID = UUID()
        e.displaySessions.removeAll(); e.refreshVideoSpectrumTargets()
        precondition(!output.overlay && output.web, "Video retirement must retain Web demand")
        e.currentWebAudioSpectrumRequested = false
        e.sceneDaemonAudioSpectrumDemand = .init(requiresSpectrum: true,
            includesCurrentProcessOutput: false, scopeEpoch: 7)
        e.sceneDaemonAudioSpectrumGeneration = 1
        e.refreshVideoSpectrumTargets()
        precondition(!output.overlay && output.scene, "Scene independent demand remains active")
        e.displaySessions[1] = session; e.currentSystemAudioSpectrumEnabled = false
        e.refreshVideoSpectrumTargets()
        precondition(!output.overlay && output.scene, "Video setting must not disable Scene")
        PlaybackCommandMultiplexer.shared.isPlaybackPaused = true
        e.refreshVideoSpectrumTargets()
        precondition(!output.overlay && !output.web && !output.scene, "shared pause releases every consumer")
        print("capture-target-demand-pass")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-capture-target-demand-") as tmp:
            directory = Path(tmp); swift = directory / "Harness.swift"; binary = directory / "harness"
            swift.write_text(support + methods + harness)
            compile_result = subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift"),
                str(swift), "-o", str(binary)], text=True, capture_output=True, timeout=60)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("capture-target-demand-pass", result.stdout)

    def test_protocol_mailbox_and_background_delivery(self):
        with tempfile.TemporaryDirectory(prefix="mwx-process-isolation-") as tmp:
            directory = Path(tmp)
            types = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift").read_text()
            prefix = "import Foundation\nclass WallpaperEngine {}\nfinal class PlaybackResourceLifetime {}\n"
            # The endpoint's real value declarations, without constructing WKWebView.
            (directory / "Types.swift").write_text(prefix + source_block(types, "extension WallpaperEngine"))
            (directory / "Harness.swift").write_text(HARNESS)
            sources = [
                "MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift",
                "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift",
                "MyWallpaperX/Core/Playback/PlaybackSpectrumDelivery.swift",
                "MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSnapshot.swift",
                "MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSnapshotStore.swift",
                "MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonProtocol.swift",
                "MyWallpaperX/Core/PlaybackControl/PlaybackSurfaceVisibility.swift",
                "MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonIO.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift",
            ]
            binary = directory / "harness"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *[str(ROOT / p) for p in sources],
                str(directory / "Types.swift"), str(directory / "Harness.swift"), "-o", str(binary)],
                text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary), str(directory / "pipe.jsonl")],
                text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("playback-process-isolation-pass", result.stdout)
