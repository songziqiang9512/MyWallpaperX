"""Production command dispatch must observe concrete playback state."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ROOT / 'MyWallpaperX/Core/PlaybackControl'
PROPERTY = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift"
HARNESS = r'''
import Foundation
import Combine
final class Handler: PlaybackEngineControlling {
    let engineKind: PlaybackEngineKind
    var isPlaying: Bool
    var volume: Float = 0
    var volumeCommands = 0
    var qualityCommands: [WallpaperEngineCommand] = []
    init(_ kind: PlaybackEngineKind, playing: Bool) {
        engineKind = kind; isPlaying = playing
    }
    func handle(_ command: WallpaperEngineCommand) -> Bool {
        switch command {
        case let .setPlaybackPaused(paused): isPlaying = !paused; return true
        case let .setVolume(value): volume = value; volumeCommands += 1; return true
        case .setWebFrameRateSuggestion, .setAnimationFrameRate, .setSceneRenderQuality:
            qualityCommands.append(command); return true
        default: return false
        }
    }
}
@main enum Harness {
    static func main() {
        let mux = PlaybackCommandMultiplexer()
        let scene = Handler(.scene, playing: true)
        let video = Handler(.video, playing: false)
        precondition(!mux.isAnyEnginePlaying)
        mux.register(scene); mux.register(video)
        precondition(mux.isAnyEnginePlaying, "Playing Scene must make global pause available")
        precondition(mux.dispatch(.pause).values.allSatisfy { $0 })
        precondition(!mux.isAnyEnginePlaying)
        precondition(mux.dispatch(.resume, to: .video))
        precondition(mux.isAnyEnginePlaying && scene.isPlaying)
        let volumeOutcomes = mux.dispatch(.setVolume(37.5))
        precondition(volumeOutcomes[.scene] == true && volumeOutcomes[.video] == true)
        precondition(scene.volume == 37.5 && video.volume == 37.5)
        PlaybackVolumeState.shared.setNormalizedVolume(0.75)
        PlaybackVolumeState.shared.setNormalizedVolume(.nan)
        precondition(abs(PlaybackVolumeState.shared.normalizedVolume - 0.75) < 0.0001)
        PlaybackVolumeState.shared.setNormalizedVolume(.infinity)
        precondition(abs(PlaybackVolumeState.shared.normalizedVolume - 0.75) < 0.0001)
        let suiteName = "mwx-playback-mute-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let persistedMute = PlaybackMuteState(defaults: suite)
        persistedMute.setMuted(false)
        precondition(!persistedMute.isMuted)
        persistedMute.setMuted(true)
        precondition(suite.bool(forKey: PlaybackMuteState.persistenceKey))
        let restoredMute = PlaybackMuteState(defaults: suite)
        precondition(restoredMute.isMuted)
        restoredMute.setMuted(false)
        precondition(!suite.bool(forKey: PlaybackMuteState.persistenceKey))
        suite.removePersistentDomain(forName: suiteName)
        let freshMute = PlaybackMuteState(defaults: suite)
        precondition(!freshMute.isMuted, "absent current mute intent defaults to unmuted")
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SceneMediaSourcePreference.key)
        defaults.set("music", forKey: "sceneMediaPlayerSource")
        precondition(!SceneMediaSourcePreference.isEnabled, "retired source selection cannot enable current media info")
        defaults.set(true, forKey: SceneMediaSourcePreference.key)
        precondition(SceneMediaSourcePreference.isEnabled)
        defaults.set(false, forKey: SceneMediaSourcePreference.key)
        precondition(!SceneMediaSourcePreference.isEnabled)
        // E2c: alias registration — the same handler under .web executes
        // exactly once per broadcast (identity dedup).
        mux.register(video, as: .web)
        suite.set(30, forKey: PlaybackQualityPreference.legacyFrameRateKey)
        var legacyQuality = PlaybackQualityPreference.read(from: suite)
        precondition(legacyQuality.animationFrameRate.rawValue == 30 && legacyQuality.keepsLegacySceneDecodeLimit)
        legacyQuality.webFrameRateMode = .followAnimationFrameRate
        mux.applyQualityPreference(legacyQuality, defaults: suite)
        precondition(scene.qualityCommands.isEmpty && video.qualityCommands == [.setWebFrameRateSuggestion(30)])
        mux.applyQualityPreference(.defaults, defaults: suite)
        mux.applyQualityPreference(.defaults, defaults: suite)
        precondition(scene.qualityCommands == [.setAnimationFrameRate(.standard)])
        precondition(video.qualityCommands == [.setWebFrameRateSuggestion(30), .setWebFrameRateSuggestion(nil)])
        precondition(PlaybackQualityPreference.read(from: suite) == .defaults)
        precondition(suite.integer(forKey: PlaybackQualityPreference.legacyFrameRateKey) == 30)
        suite.set(true, forKey: "sceneHDRDisplayEnabled")
        precondition(PlaybackQualityPreference.read(from: suite).scene.postProcessing == .ultra)
        suite.set(["animationFramesPerSecond": 60, "webFrameRateMode": "display"], forKey: PlaybackQualityPreference.userDefaultsKey)
        precondition(PlaybackQualityPreference.read(from: suite).scene.postProcessing == .ultraDisplayHDR)
        mux.applyQualityPreference(.defaults, defaults: suite)
        precondition(PlaybackQualityPreference.read(from: suite).scene.postProcessing == .ultra)
        precondition(scene.qualityCommands == [.setAnimationFrameRate(.standard), .setSceneRenderQuality(.init())])
        precondition(video.qualityCommands == [.setWebFrameRateSuggestion(30), .setWebFrameRateSuggestion(nil)])
        var quality = PlaybackQualityPreference.defaults
        quality.scene.shadows = .medium
        quality.scene.volumeLighting = .disabled
        quality.scene.reflections = .disabled
        mux.applyQualityPreference(quality, defaults: suite)
        mux.applyQualityPreference(quality, defaults: suite)
        precondition(PlaybackQualityPreference.read(from: suite) == quality)
        precondition(scene.qualityCommands.count == 3 && scene.qualityCommands.last == .setSceneRenderQuality(quality.scene))
        suite.set(["sceneShadowQuality": "future"], forKey: PlaybackQualityPreference.userDefaultsKey)
        precondition(PlaybackQualityPreference.read(from: suite).scene.shadows == .adaptive)
        precondition(PlaybackQualityPreference.read(from: suite).scene.volumeLighting == .enabled)
        precondition(PlaybackQualityPreference.read(from: suite).scene.reflections == .enabled)
        precondition(AnimationFrameRate(rawValue: 9) == nil && AnimationFrameRate(rawValue: 121) == nil)
        precondition(AnimationFrameRate(rawValue: 10) != nil && AnimationFrameRate(rawValue: 120) != nil)
        suite.removeObject(forKey: PlaybackQualityPreference.userDefaultsKey)
        let rate25 = AnimationFrameRate(rawValue: 25)!
        var updated = PlaybackQualityPreference.read(from: suite)
        updated.animationFrameRate = rate25
        mux.applyQualityPreference(updated, defaults: suite)
        precondition(PlaybackQualityPreference.read(from: suite) == updated && updated.keepsLegacySceneDecodeLimit)
        precondition(scene.qualityCommands.last == .setAnimationFrameRate(rate25))
        suite.removePersistentDomain(forName: suiteName)
        video.volume = 0
        let previousVolumeCommands = video.volumeCommands
        let deduped = mux.dispatch(.setVolume(41.5))
        precondition(deduped[.web] == true && deduped[.video] == true)
        precondition(video.volumeCommands == previousVolumeCommands + 1,
                     "aliased handler must not double-execute")
        precondition(abs(video.volume - 41.5) < 0.0001)
        precondition(mux.dispatch(.pause, to: .web), "targeted .web dispatch reaches the aliased handler")
        precondition(!video.isPlaying)
        mux.unregister(.web)
        video.volume = 0
        mux.unregister(.video)
        precondition(!mux.isAnyEnginePlaying)
        precondition(!mux.dispatch(
            .setProperty([:], revision: 1, recordID: "fixture"),
            to: .scene
        ))
        // E2a-1: product intent epoch — begin() strictly increases;
        // adopted() is monotonic (stale product epochs ignored, newer win).
        var counter = PlaybackIntentEpoch()
        precondition(counter.value == 0 && counter.begin() == 1 && counter.begin() == 2)
        precondition(PlaybackIntentEpoch.adopted(mirror: 2, product: 5) == 5)
        precondition(PlaybackIntentEpoch.adopted(mirror: 9, product: 5) == 9)
        precondition(PlaybackIntentEpoch.adopted(mirror: 4, product: 4) == 4)
        var mirror: UInt64 = 0
        mirror = PlaybackIntentEpoch.adopted(mirror: mirror, product: counter.begin())
        mirror &+= 1
        mirror &+= 1
        precondition(mirror == 5)
        mirror = PlaybackIntentEpoch.adopted(mirror: mirror, product: counter.begin())
        precondition(mirror == 5, "stale product epoch must be ignored")
        mirror = PlaybackIntentEpoch.adopted(mirror: mirror, product: counter.begin())
        precondition(mirror == 5, "equal epoch is idempotent")
        mirror = PlaybackIntentEpoch.adopted(mirror: mirror, product: counter.begin())
        precondition(mirror == 6, "newer product epoch must win")
        precondition(counter.value == 6)
        let observed = PlaybackCommandMultiplexer()
        var snapshots: [PlaybackPauseSnapshot] = []
        var gettersMatchDeliveredValue = true
        let subscription = observed.pauseSnapshots.sink { value in
            snapshots.append(value)
            gettersMatchDeliveredValue = gettersMatchDeliveredValue && observed.pauseSnapshot == value
        }
        precondition(snapshots == [.init(revision: 0, isUserPaused: false, isSystemPaused: false)])
        observed.setSystemPaused(true)
        observed.dispatch(.pause)
        precondition(snapshots.map(\.revision) == [0,1,2])
        precondition(snapshots.last!.isUserPaused && snapshots.last!.isSystemPaused && snapshots.last!.isPaused,
            "independent user pause must publish even while system pause keeps effective OR unchanged")
        observed.dispatch(.resume)
        precondition(!snapshots.last!.isUserPaused && snapshots.last!.isSystemPaused && observed.isPlaybackPaused)
        observed.setSystemPaused(false)
        precondition(snapshots.last == .init(revision: 4, isUserPaused: false, isSystemPaused: false))
        observed.setSystemPaused(false)
        observed.dispatch(.resume)
        precondition(snapshots.count == 5 && gettersMatchDeliveredValue, "unchanged bits do not invent revisions")
        var late: PlaybackPauseSnapshot?
        observed.setSystemPaused(true)
        let lateSubscription = observed.pauseSnapshots.sink { late = $0 }
        precondition(late == .init(revision: 5, isUserPaused: false, isSystemPaused: true))
        let newlyRegistered = Handler(.video, playing: true)
        observed.register(newlyRegistered)
        precondition(!newlyRegistered.isPlaying && snapshots.count == 6,
            "register replays effective pause without manufacturing a policy change")
        lateSubscription.cancel(); subscription.cancel()
        for _ in 0..<100 {
            let reentrant = PlaybackCommandMultiplexer()
            let reentrantHandler = Handler(.video, playing: true)
            reentrant.register(reentrantHandler)
            var firstRevisions: [UInt64] = [], secondRevisions: [UInt64] = []
            var matchesAuthority = true
            let first = reentrant.pauseSnapshots.sink { value in
                firstRevisions.append(value.revision)
                matchesAuthority = matchesAuthority && value == reentrant.pauseSnapshot
                if value.revision == 1 { reentrant.dispatch(.resume) }
            }
            let second = reentrant.pauseSnapshots.sink { value in
                secondRevisions.append(value.revision)
                matchesAuthority = matchesAuthority && value == reentrant.pauseSnapshot
                if value.revision == 1 { reentrant.dispatch(.resume) }
            }
            reentrant.dispatch(.pause)
            precondition(firstRevisions == firstRevisions.sorted() && secondRevisions == secondRevisions.sorted(),
                "Synchronous pause reentry must never deliver an older snapshot after the current one")
            precondition(firstRevisions.last == 2 && secondRevisions.last == 2 && matchesAuthority)
            precondition(!reentrant.isUserPaused && !reentrant.isPlaybackPaused && reentrantHandler.isPlaying,
                "The outer command must also deliver the effective current pause to the original handler")
            first.cancel(); second.cancel()
        }
        print("playback-dispatch-pass")
    }
}
'''


class PlaybackCommandMultiplexerTests(unittest.TestCase):
    def test_existential_state_tracks_registered_engine_and_commands(self):
        with tempfile.TemporaryDirectory(prefix='mwx-playback-dispatch-') as directory:
            path = Path(directory)
            home = path / 'home'; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            harness = path / 'Harness.swift'
            harness.write_text(HARNESS)
            binary = path / 'harness'
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(PROPERTY), str(ROOT / "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift"),
                str(ROOT / "MyWallpaperX/Shared/Settings/SceneMediaSourcePreference.swift"),
                *[str(SOURCES / name) for name in ['ScenePlaybackShortcut.swift', 'WallpaperEngineCommand.swift', 'PlaybackEngineControlling.swift', 'PlaybackCommandMultiplexer.swift', 'PlaybackIntentEpoch.swift', 'PlaybackPerformanceProfile.swift']],
                str(harness), '-o', str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], env=environment, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('playback-dispatch-pass', result.stdout)

    def test_product_scene_handler_is_daemon_client(self):
        application = (ROOT / 'MyWallpaperX/App/MyWallpaperXApplication.swift').read_text()
        status_bar = (ROOT / 'MyWallpaperX/App/StatusBarController.swift').read_text()
        client = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift").read_text()
        self.assertIn('register(SceneDaemonClient.shared)', application)
        self.assertNotIn('register(SceneDesktopWallpaperHost.shared)', status_bar)
        self.assertIn('final class SceneDaemonClient: PlaybackEngineControlling', client)
        self.assertFalse(
            (ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+PlaybackControl.swift').exists()
        )
