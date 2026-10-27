import AppKit
import Combine
import Foundation

// UI shells and IPC endpoints are controlled leaves. Their actual action
// bodies, volume owners, multiplexer and Video handler are inserted/compiled.
struct WallpaperSettings { var volume: Double = 50 }
struct PersonalSettingsExportSummary {}
struct PersonalSettingsImportSummary {}
enum PersonalSettingsError: Error { case recoveryRequired(String) }
enum PlaybackSurfaceVisibility { struct Evidence: Codable {} }

enum Trace {
    static var video: [Float] = []
    static var web: [Float] = []
    static var scene: [[String: Any]] = []
    static func reset() { video = []; web = []; scene = [] }
    static var sceneVolumes: [Float] { scene.compactMap { $0["volume"] as? Float } }
    static var sceneMutes: [Bool] { scene.compactMap { $0["muted"] as? Bool } }
}

final class WallpaperManager {
    static let shared = WallpaperManager()
    var settings = WallpaperSettings()
    var previousAudibleVolume: Double = 50
    func stopCurrentPlayback() {}
    // ACTUAL_MANAGER_VOLUME_METHODS
}

final class WebDaemonHostAdapter { var hasLivePlayback = true }
enum WebVolumeCommand { case setVolume(Float) }
final class WallpaperEngine {
    static let shared = WallpaperEngine()
    struct Session { struct ProcessLeaf { var isRunning = true }; var process = ProcessLeaf() }
    var currentVolumeNormalized: Float = 0.5
    var dedicatedWebHostAdapter: AnyObject? = WebDaemonHostAdapter()
    var displaySessions = [1: Session()]
    func isPlaying() -> Bool { true }
    func applyPlaybackPaused(_: Bool) {}
    func dispatchWebRuntimeCommand(_ command: WebVolumeCommand) {
        if case let .setVolume(value) = command { Trace.web.append(value) }
    }
    func send(_ command: DaemonCommand, to session: Session) {
        precondition(command.action == "setVolume")
        Trace.video.append(command.volume!)
    }
    // ACTUAL_ENGINE_VOLUME_METHOD
}

enum SceneDaemonProtocol { static let version = 2 }
final class SceneVolumeEndpoint: PlaybackEngineControlling {
    let engineKind: PlaybackEngineKind = .scene
    var endpointReady = true
    var activeIntent: Int? = 1
    var pendingIntent: Int?
    func send(_ value: [String: Any]) { Trace.scene.append(value) }
    func handle(_ command: WallpaperEngineCommand) -> Bool {
        switch command {
        // ACTUAL_SCENE_VOLUME_CASES
        default: return false
        }
    }
}

enum SettingsWindowController {
    static let shared = SettingsWindowControllerLeaf()
    final class SettingsWindowControllerLeaf { func showWindow() {} }
}
enum MainWindowCoordinator { static func activateMainWindow() {} }
enum CrossRuntimeWallpaperNavigator {
    enum Direction { case previous, next }
    static func navigate(_: Direction) {}
}
enum StatusBarPanelViewController {
    // ACTUAL_STATUS_ACTION
}
struct StatusPresentation {
    enum Content: Equatable { case workshop(Int) }
    var content: Content = .workshop(1)
}
final class StatusBarController {
    let wallpaperManager = WallpaperManager.shared
    var presentation: StatusPresentation? = nil
    var refreshes = 0
    func capturePresentation() -> StatusPresentation { .init() }
    func closeThen(_ action: () -> Void) { action() }
    static func openProperties(_: Int) {}
    func togglePlayback() {}
    func cyclePlaybackMode() {}
    func quitApp() {}
    func scheduleRefresh() { refreshes += 1 }
    func send(_ action: StatusBarPanelViewController.Action) { perform(action) }
    // ACTUAL_STATUS_PERFORM
}

final class AppKitSettingsContainerView: NSObject {
    let dependency: AppSettingsPanelDependency
    var isUpdatingUI = false
    let volumeSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    let volumeValueLabel = NSTextField(labelWithString: "50%")
    let muteSwitch = NSSwitch()
    override init() {
        dependency = .init(settings: .init(), actions: .init(updateVolume: { WallpaperManager.shared.updateVolume($0) }))
        super.init()
        volumeSlider.target = self
        volumeSlider.action = #selector(handleVolumeChange)
        muteSwitch.target = self
        muteSwitch.action = #selector(handleMuteToggle)
    }
    func sendVolume(_ value: Double) {
        volumeSlider.doubleValue = value
        precondition(volumeSlider.sendAction(volumeSlider.action!, to: volumeSlider.target))
    }
    func sendMute(_ muted: Bool) {
        muteSwitch.state = muted ? .on : .off
        precondition(muteSwitch.sendAction(muteSwitch.action!, to: muteSwitch.target))
    }
    // ACTUAL_SETTINGS_VOLUME_HANDLER
    // ACTUAL_SETTINGS_MUTE_HANDLER
}

@main enum Checks {
    static func main() throws {
        _ = NSApplication.shared
        let mux = PlaybackCommandMultiplexer.shared
        let video = VideoPlaybackCommandHandler()
        mux.register(video)
        mux.register(video, as: .web)
        mux.register(SceneVolumeEndpoint())
        let manager = WallpaperManager.shared
        let status = StatusBarController()
        let settings = AppKitSettingsContainerView()
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            precondition(condition(), name); checks[name] = true
        }
        func prepare(_ volume: Double, muted: Bool) {
            PlaybackMuteState.shared.setMuted(muted)
            manager.settings.volume = volume
            manager.previousAudibleVolume = volume > 0 ? volume : 50
            Trace.reset()
        }
        let entries: [(String, (Double) -> Void)] = [
            ("status", { status.send(.volume($0)) }),
            ("settings", { settings.sendVolume($0) })
        ]
        for (name, send) in entries {
            prepare(50, muted: false)
            send(60); send(61); send(62)
            check(name + "-continuous-positive-volume-sends-one-volume-per-input-without-mute-intent",
                  Trace.sceneVolumes == [0.6, 0.61, 0.62] && Trace.sceneMutes.isEmpty
                  && Trace.video == [0.6, 0.61, 0.62] && Trace.web == Trace.video
                  && manager.settings.volume == 62 && manager.previousAudibleVolume == 62
                  && !PlaybackMuteState.shared.isMuted)

            Trace.reset(); send(0)
            check(name + "-crossing-zero-keeps-primary-volume-and-one-mute-transition",
                  Trace.sceneVolumes == [0, 0] && Trace.sceneMutes == [true]
                  && Trace.video == [0, 0] && Trace.web == Trace.video
                  && PlaybackMuteState.shared.isMuted && manager.settings.volume == 0
                  && manager.previousAudibleVolume == 62)
            Trace.reset(); send(0)
            check(name + "-repeated-zero-does-not-reissue-mute-or-nested-volume",
                  Trace.sceneVolumes == [0] && Trace.sceneMutes.isEmpty
                  && Trace.video == [0] && Trace.web == Trace.video && PlaybackMuteState.shared.isMuted)

            Trace.reset(); send(24)
            check(name + "-zero-to-positive-unmutes-and-immediately-restores-the-new-volume",
                  Trace.sceneVolumes == [0.24, 0.24] && Trace.sceneMutes == [false]
                  && Trace.video == [0, 0.24] && Trace.web == Trace.video
                  && !PlaybackMuteState.shared.isMuted && manager.settings.volume == 24)
            Trace.reset(); send(25)
            check(name + "-next-positive-input-does-not-repeat-the-unmute-transition",
                  Trace.sceneVolumes == [0.25] && Trace.sceneMutes.isEmpty
                  && Trace.video == [0.25] && Trace.web == Trace.video)

            prepare(70, muted: true); send(40)
            check(name + "-externally-muted-positive-drag-unmutes-without-restoring-an-old-volume",
                  Trace.sceneVolumes == [0.4, 0.4] && Trace.sceneMutes == [false]
                  && Trace.video == [0, 0.4] && Trace.web == Trace.video
                  && manager.settings.volume == 40 && manager.previousAudibleVolume == 40
                  && !PlaybackMuteState.shared.isMuted)
        }

        prepare(50, muted: false); settings.sendVolume(0.49)
        check("settings-zero-boundary-uses-the-displayed-rounded-percentage",
              settings.volumeValueLabel.stringValue == "0%" && manager.settings.volume == 0
              && Trace.sceneMutes == [true] && PlaybackMuteState.shared.isMuted)
        Trace.reset(); settings.sendVolume(0.51)
        check("settings-rounding-back-to-one-percent-unmutes",
              settings.volumeValueLabel.stringValue == "1%" && manager.settings.volume == 1
              && Trace.sceneMutes == [false] && Trace.video == [0, 0.01])
        Trace.reset(); settings.sendVolume(200)
        check("settings-slider-maximum-remains-clamped-to-one-hundred",
              settings.volumeValueLabel.stringValue == "100%" && manager.settings.volume == 100
              && Trace.sceneVolumes == [1] && Trace.sceneMutes.isEmpty)
        Trace.reset(); settings.isUpdatingUI = true; settings.sendVolume(0); settings.isUpdatingUI = false
        check("settings-state-projection-does-not-create-a-user-volume-or-mute-intent",
              Trace.scene.isEmpty && Trace.video.isEmpty && manager.settings.volume == 100
              && settings.volumeValueLabel.stringValue == "100%")

        prepare(40, muted: false); settings.sendMute(true)
        check("explicit-mute-switch-still-mutes-with-the-main-volume-retained",
              Trace.sceneVolumes == [0.4] && Trace.sceneMutes == [true]
              && Trace.video == [0] && manager.settings.volume == 40 && PlaybackMuteState.shared.isMuted)
        Trace.reset(); settings.sendMute(true)
        check("explicit-same-value-mute-intent-is-still-replayed-to-current-endpoints",
              Trace.sceneVolumes == [0.4] && Trace.sceneMutes == [true] && Trace.video == [0])
        Trace.reset(); settings.sendMute(false)
        check("explicit-unmute-restores-the-retained-main-volume",
              Trace.sceneVolumes == [0.4] && Trace.sceneMutes == [false]
              && Trace.video == [0.4] && !PlaybackMuteState.shared.isMuted)
        Trace.reset(); settings.sendMute(false)
        check("explicit-same-value-unmute-intent-is-still-replayed",
              Trace.sceneVolumes == [0.4] && Trace.sceneMutes == [false] && Trace.video == [0.4])
        Trace.reset(); status.send(.mute)
        check("status-explicit-mute-toggle-remains-a-separate-command",
              Trace.sceneMutes == [true] && Trace.video == [0] && PlaybackMuteState.shared.isMuted)
        Trace.reset(); status.send(.mute)
        check("status-explicit-mute-toggle-unmutes-with-retained-volume",
              Trace.sceneMutes == [false] && Trace.video == [0.4] && !PlaybackMuteState.shared.isMuted)
        check("status-original-refresh-still-runs-after-every-deliberate-action", status.refreshes == 10)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
