"""Execute the shared production policy, event observer and command routing."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
CONTROL = ROOT / "MyWallpaperX/Core/PlaybackControl"
HARNESS = r'''
import AppKit
var simulatedSpaces: [[String: Any]] = [["Current Space": ["type": 4]]]
func CGSMainConnectionID() -> UInt32 { 0 }
func CGSCopyManagedDisplaySpaces(_ connection: UInt32) -> CFArray { simulatedSpaces as CFArray }
struct WallpaperSettings: Codable {
    var volume: Double = 50
    var pauseWhenOtherAppFocused = false
    var pauseWhenOtherAppFullscreen = false
    var pauseWhenUnplugged = false
    var pauseWhenIdle = false
    var idleTimeoutMinutes = 1
}
final class WallpaperManager {
    var settings = WallpaperSettings()
    var wallpapers: [String] = []
    var previousAudibleVolume: Double = 0
    let settingsKey = "fixture"
    var stored: Data?
    func loadCodableValue<T: Decodable>(forKey: String) -> T? {
        stored.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    func saveCodableValue<T: Encodable>(_ value: T, forKey: String) {
        stored = try! JSONEncoder().encode(value)
    }
    // SETTINGS_METHODS
}
final class Handler: PlaybackEngineControlling {
    let engineKind: PlaybackEngineKind
    var paused = false
    var calls = 0
    init(_ kind: PlaybackEngineKind) { engineKind = kind }
    var isPlaying: Bool { !paused }
    func handle(_ command: WallpaperEngineCommand) -> Bool {
        guard case let .setPlaybackPaused(value) = command else { return false }
        paused = value; calls += 1; return true
    }
}
@main enum Harness {
    static func main() {
        // Every combination of four switches and four system conditions.
        for flags in 0..<16 {
            var settings = WallpaperSettings()
            settings.pauseWhenOtherAppFocused = flags & 1 != 0
            settings.pauseWhenOtherAppFullscreen = flags & 2 != 0
            settings.pauseWhenUnplugged = flags & 4 != 0
            settings.pauseWhenIdle = flags & 8 != 0
            let policy = PlaybackPolicyController.Settings(settings)
            for conditions in 0..<16 {
                let actual = policy.requiresPause(
                    otherAppFocused: conditions & 1 != 0,
                    otherAppFullscreen: conditions & 2 != 0,
                    onBattery: conditions & 4 != 0,
                    idleSeconds: conditions & 8 != 0 ? 60 : 59.9)
                precondition(actual == (flags & conditions != 0))
            }
        }
        var idle = WallpaperSettings()
        idle.pauseWhenIdle = true
        idle.idleTimeoutMinutes = 0
        let policy = PlaybackPolicyController.Settings(idle)
        for invalid in [Double.nan, Double.infinity, -1] {
            precondition(!policy.requiresPause(otherAppFocused: false,
                otherAppFullscreen: false, onBattery: false, idleSeconds: invalid))
        }
        precondition(policy.idleTimeout == 60)

        let mux = PlaybackCommandMultiplexer.shared
        let video = Handler(.video), web = Handler(.web), scene = Handler(.scene)
        let handlers = [video, web, scene]
        for handler in handlers { mux.register(handler) }
        func expect(_ paused: Bool) {
            precondition(mux.isPlaybackPaused == paused)
            precondition(handlers.allSatisfy { $0.paused == paused })
        }
        let observer = PlaybackPolicyController.shared
        observer.updateSettings(WallpaperSettings())
        expect(false)
        // Actual persistence methods with an empty Video library and a fullscreen Space.
        let manager = WallpaperManager()
        manager.stored = try! JSONEncoder().encode(WallpaperSettings())
        manager.loadSettings()
        expect(false)
        manager.settings.pauseWhenOtherAppFullscreen = true
        manager.saveSettings()
        expect(true)
        manager.settings.pauseWhenOtherAppFullscreen = false
        manager.loadSettings()
        expect(true) // Loaded persisted ON takes precedence over the in-memory default.
        manager.settings.pauseWhenOtherAppFullscreen = false
        manager.saveSettings()
        expect(false)
        precondition(manager.wallpapers.isEmpty)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        expect(true)
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        expect(true) // Display sleep must still hold the gate.
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        expect(false)
        mux.dispatch(.pause)
        observer.setInterruption(.screenLock, active: true)
        observer.setInterruption(.screenLock, active: false)
        observer.refresh()
        expect(true) // Policy restoration must preserve manual pause.
        mux.dispatch(.resume, to: .scene)
        expect(false)
        observer.setInterruption(.screenLock, active: true)
        mux.dispatch(.resume)
        expect(true) // A manual resume cannot override a system interruption.
        let replacement = Handler(.web)
        mux.register(replacement)
        precondition(replacement.paused, "New handlers inherit effective pause")
        mux.register(web)
        observer.setInterruption(.screenLock, active: false)
        expect(false)
        let calls = handlers.map(\.calls)
        observer.refresh(); observer.refresh()
        precondition(handlers.map(\.calls) == calls, "No redundant policy commands")
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        expect(false) // All toggles off, including after external activation events.
        print("policy-pass: 256 combinations, interruption overlap, manual intent, replay")
    }
}
'''


class PlaybackPolicyTests(unittest.TestCase):
    def test_shared_policy_and_system_notifications(self):
        with tempfile.TemporaryDirectory(prefix="mwx-playback-policy-") as directory:
            path = Path(directory)
            harness = path / "Harness.swift"
            persistence = (ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift").read_text()
            harness.write_text(HARNESS.replace("// SETTINGS_METHODS", "\n".join([
                method(persistence, "func loadSettings("), method(persistence, "func saveSettings("),
            ])))
            binary = path / "harness"
            sources = [
                ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
                *[CONTROL / name for name in ["WallpaperEngineCommand.swift",
                    "PlaybackEngineControlling.swift", "PlaybackCommandMultiplexer.swift",
                    "PlaybackPolicyController.swift"]],
            ]
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                *map(str, sources), str(harness), "-o", str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("policy-pass", result.stdout)


if __name__ == "__main__":
    unittest.main()
