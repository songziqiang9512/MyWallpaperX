#!/usr/bin/env python3

import subprocess
import tempfile
import unittest
from pathlib import Path
from script.tests.test_steam_library_interactions import method


REPO_ROOT = Path(__file__).resolve().parents[2]
GATE_SOURCES = [
    REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackResourceLifetime.swift",
    REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/ImportedVideoAutoplayGate.swift",
    REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperRuntimeSwitch.swift",
]


class ImportedVideoAutoplayGateTests(unittest.TestCase):
    def test_preparation_revoke_and_failed_intent_restore(self) -> None:
        manager = (REPO_ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift").read_text()
        support = r'''
        import Foundation
        final class SceneDaemonClient {
            static let shared = SceneDaemonClient()
            var cancellation: (() -> Void)?
            func cancelPreparationForRuntimeSwitch() { cancellation?() }
        }
        final class WallpaperEngine {
            static let shared = WallpaperEngine()
            func replayDeferredVideoEndIfNeeded() {}
        }
        final class WallpaperManager {
            var playbackIntentEpochCounter = PlaybackIntentEpoch()
            var requestedRuntime: WallpaperRuntimeKind? = .video
            var pendingWallpaper: Int? = 1
            var activeWallpaperRuntime = WallpaperRuntimeKind.video
            var timerRunning = true
            var wallpapers = [1]
            var effectiveCurrentWallpaper: Int? = 1
            struct Settings { var autoSwitchEnabled = true }
            var settings = Settings()
            func isSwitchingPlaybackMode() -> Bool { true }
            func stopAutoSwitchTimer() { timerRunning = false }
            func refreshAutoSwitchTimerIfNeeded() { timerRunning = true }
            // METHODS
        }
        @main enum Check {
            static func main() {
                let manager = WallpaperManager()
                manager.pendingWallpaper = nil
                let oldAutoplay = ImportedVideoAutoplayGate.shared.claim()
                var cancelledAfterNewIdentity = false
                SceneDaemonClient.shared.cancellation = {
                    cancelledAfterNewIdentity = manager.requestedRuntime == .web
                        && manager.playbackIntentEpochCounter.value == 1
                }
                precondition(manager.shouldRunAutoSwitchTimer())
                let epoch = manager.beginPlaybackIntent(runtime: .web)
                precondition(!manager.shouldRunAutoSwitchTimer(), "settings must not restart the old timer during Web preparation")
                precondition(epoch == 1 && cancelledAfterNewIdentity)
                precondition(!ImportedVideoAutoplayGate.shared.isCurrent(oldAutoplay))
                precondition(manager.pendingWallpaper == nil && !manager.timerRunning)
                manager.restoreCommittedPlaybackIntent() // Web validation failed.
                precondition(manager.requestedRuntime == .video && manager.timerRunning)
                precondition(manager.shouldRunAutoSwitchTimer())
                manager.pendingWallpaper = 2
                precondition(!manager.shouldRunAutoSwitchTimer(), "pending Video must keep its own selection")
                manager.pendingWallpaper = nil
                precondition(manager.playbackIntentEpochCounter.value == epoch)
                manager.activeWallpaperRuntime = .scene
                manager.restoreCommittedPlaybackIntent()
                precondition(manager.requestedRuntime == .scene && !manager.timerRunning)
                print("preparation-intent-restore-pass")
            }
        }
        '''
        methods = "\n".join(method(manager, signature) for signature in [
            "func beginPlaybackIntent(runtime: WallpaperRuntimeKind? = nil) -> UInt64",
            "func restoreCommittedPlaybackIntent()",
        ])
        methods += "\n" + method((REPO_ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift").read_text(), "func shouldRunAutoSwitchTimer()")
        with tempfile.TemporaryDirectory(prefix="mwx-preparation-intent-") as directory:
            source = Path(directory) / "Harness.swift"
            binary = Path(directory) / "harness"
            source.write_text(support.replace("// METHODS", methods))
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                *(str(p) for p in GATE_SOURCES),
                str(REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackIntentEpoch.swift"),
                str(source), "-o", str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("preparation-intent-restore-pass", result.stdout)

    def test_termination_revokes_delayed_web_completion_before_cleanup(self) -> None:
        manager = (REPO_ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift").read_text()
        service = (REPO_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift").read_text()
        web = (REPO_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPlayback.swift").read_text()
        delegate = (REPO_ROOT / "MyWallpaperX/App/AppDelegate.swift").read_text()
        guards = web[web.index("                guard launchGeneration == self.webLaunchIntentGeneration"):
                     web.index("                guard let playbackContext else")]
        harness = r'''
        import Foundation
        final class SceneDaemonClient {
            static let shared = SceneDaemonClient()
            func cancelPreparationForRuntimeSwitch() {}
        }
        final class WallpaperManager {
            static let shared = WallpaperManager()
            var playbackIntentEpochCounter = PlaybackIntentEpoch()
            var playbackIntentEpoch: UInt64 { playbackIntentEpochCounter.value }
            var requestedRuntime: WallpaperRuntimeKind? = .video
            var pendingWallpaper: Int? = 1
            func stopAutoSwitchTimer() {}
            func flushPersistentState() { precondition(requestedRuntime == nil) }
            // MANAGER
        }
        final class WallpaperEngine {
            static let shared = WallpaperEngine()
            var epoch: UInt64 = 0
            var cleanups = 0
            func adoptIntentEpoch(_ value: UInt64) { epoch = value }
            func cleanup() { cleanups += 1 }
        }
        struct Preparation { var isCurrent: () -> Bool }
        struct Record { let id = "fixture" }
        final class SteamWorkshopService {
            static let shared = SteamWorkshopService()
            var webLaunchIntentGeneration: UInt64 = 0
            var cancelWebProcessPreparation: (() -> Void)?
            var launches = 0
            func clearLaunchPending(matching: String) {}
            // SERVICE
            func complete(_ launchGeneration: UInt64, _ processPreparation: Preparation?) {
                let record = Record()
                // GUARDS
                launches += 1
            }
        }
        final class AppDelegate {
            var didPrepareProductTermination = false
            var pendingInitialWindowOpen: DispatchWorkItem?
            var statusBarController: Int?
            // DELEGATE
        }
        @main enum Check {
            @MainActor static func main() async {
                let manager = WallpaperManager.shared
                let service = SteamWorkshopService.shared
                var epoch = manager.beginPlaybackIntent(runtime: .web)
                var generation = service.advanceWebLaunchIntentGeneration()
                service.complete(generation, .init(isCurrent: { manager.playbackIntentEpoch == epoch }))
                precondition(service.launches == 1, "current completion should launch normally")
                epoch = manager.beginPlaybackIntent(runtime: .web)
                generation = service.advanceWebLaunchIntentGeneration()
                let pendingEpoch = epoch, pendingGeneration = generation
                let preparation = Preparation(isCurrent: { manager.playbackIntentEpoch == pendingEpoch })
                var cancellations = 0
                service.cancelWebProcessPreparation = {
                    precondition(manager.playbackIntentEpoch != pendingEpoch,
                        "cancel restored an intent during termination")
                    cancellations += 1
                }
                let ticket = ImportedVideoAutoplayGate.shared.claim()
                let deferred = Task { @MainActor in
                    await Task.yield()
                    service.complete(pendingGeneration, preparation)
                }
                let delegate = AppDelegate()
                delegate.prepareProductTermination()
                await deferred.value
                precondition(service.launches == 1 && cancellations == 1,
                    "delayed Web completion escaped termination")
                precondition(!ImportedVideoAutoplayGate.shared.isCurrent(ticket))
                precondition(WallpaperEngine.shared.epoch == manager.playbackIntentEpoch)
                delegate.prepareProductTermination()
                precondition(WallpaperEngine.shared.cleanups == 1 && cancellations == 1,
                    "termination must remain idempotent")
                print("termination-revoke-pass")
            }
        }
        '''
        harness = harness.replace("// MANAGER", method(manager, "func beginPlaybackIntent(runtime: WallpaperRuntimeKind? = nil) -> UInt64"))
        harness = harness.replace("// SERVICE", method(service, "func advanceWebLaunchIntentGeneration() -> UInt64"))
        harness = harness.replace("// GUARDS", guards)
        harness = harness.replace("// DELEGATE", method(delegate, "private func prepareProductTermination()").replace("private func", "func", 1))
        with tempfile.TemporaryDirectory(prefix="mwx-termination-revoke-") as directory:
            source, binary = Path(directory) / "Harness.swift", Path(directory) / "harness"
            source.write_text(harness)
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, GATE_SOURCES),
                str(REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackIntentEpoch.swift"),
                str(source), "-o", str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("termination-revoke-pass", result.stdout)

    def test_video_ready_rearms_timer_after_candidate_commits(self) -> None:
        events = (REPO_ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackEvents.swift").read_text()
        harness = r'''
        import Foundation
        import Combine
        enum Kind { case video, web, scene }
        final class PlaybackPolicyController {
            static let shared = PlaybackPolicyController()
            func refresh() {}
        }
        struct Wallpaper { let path: String }
        final class WallpaperEngine {
            static let playbackFailedNotification = Notification.Name("failed")
            static let playbackEndedNotification = Notification.Name("ended")
            static let playbackReadyNotification = Notification.Name("ready")
            static let shared = WallpaperEngine()
            var replays = 0
            func replayDeferredVideoEndIfNeeded() { replays += 1 }
            struct Active { let id = UUID(); let path: String }
            var videoEndState: (playbackID: UUID, delivered: Bool)?
            var prepared = 0
            var activeVideoPlayback: Active? = .init(path: "/new-video")
            var currentPlaybackContentKind: Kind = .video
            var pendingWebRetirementOnVideoReady = false
            var runtimeCommitAdmission: ((Kind) -> Bool)? = { _ in true }
            func reuse() {
                let incomingNormalizedPath = "/new-video"
                let isSameWallpaperRequest = true, isConfigurationUnchanged = true
                let noObsoleteDisplaySessions = true, targetSessionsReady = true
                // REUSE
                prepared += 1
            }
        }
        final class WallpaperManager {
            var requestedRuntime: Kind? = .video
            var activeWallpaperRuntime: Kind = .web
            var currentWallpaper: Wallpaper?
            var pendingWallpaper: Wallpaper? = .init(path: "/new-video")
            var lastWorkshopPlaybackRecordID: String? = "old-web"
            var timerRunning = false
            var resets = 0
            func normalizedPath(_ path: String) -> String { path }
            func handleEnginePlaybackFailure(_ notification: Notification) {}
            func handlePlaybackEnded(forPath: String) {}
            func refreshAutoSwitchTimerIfNeeded(forceRestart: Bool) {
                precondition(forceRestart && requestedRuntime == .video
                    && activeWallpaperRuntime == .video && pendingWallpaper == nil)
                resets += 1; timerRunning = true
            }
            // OBSERVE
        }
        let manager = WallpaperManager()
        var cancellables = Set<AnyCancellable>()
        manager.observePlaybackEvents(storeIn: &cancellables)
        NotificationCenter.default.post(name: WallpaperEngine.playbackReadyNotification,
            object: nil, userInfo: ["videoPath": "/old-video"])
        precondition(!manager.timerRunning && manager.resets == 0)
        NotificationCenter.default.post(name: WallpaperEngine.playbackReadyNotification,
            object: nil, userInfo: ["videoPath": "/new-video"])
        precondition(manager.timerRunning && manager.resets == 1
            && manager.currentWallpaper?.path == "/new-video"
            && WallpaperEngine.shared.replays == 1)
        NotificationCenter.default.post(name: WallpaperEngine.playbackReadyNotification,
            object: nil, userInfo: ["videoPath": "/new-video"])
        precondition(manager.resets == 1, "duplicate ready restarted timer again")
        manager.pendingWallpaper = .init(path: "/new-video")
        manager.timerRunning = false
        let engine = WallpaperEngine()
        engine.runtimeCommitAdmission = { _ in false }
        engine.reuse()
        precondition(!manager.timerRunning && manager.pendingWallpaper != nil)
        engine.runtimeCommitAdmission = { _ in true }
        engine.reuse()
        precondition(manager.timerRunning && manager.pendingWallpaper == nil && manager.resets == 2
            && WallpaperEngine.shared.replays == 2,
            "same finalized Video reuse did not settle selection and rearm the timer")
        manager.pendingWallpaper = .init(path: "/new-video")
        engine.videoEndState = (engine.activeVideoPlayback!.id, true)
        engine.reuse()
        precondition(engine.prepared == 1 && manager.pendingWallpaper != nil,
            "ended Video must prepare a new playback rather than reuse an EOF slot")
        engine.videoEndState = (engine.activeVideoPlayback!.id, false)
        engine.reuse()
        precondition(engine.prepared == 2, "an explicit same-Video choice must replace its deferred terminal")
        print("video-ready-timer-pass")
        '''
        harness = harness.replace("// OBSERVE", method(events, "func observePlaybackEvents(storeIn cancellables: inout Set<AnyCancellable>)"))
        from script.tests.test_web_compat_parity import source_block
        engine = (REPO_ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine.swift").read_text()
        harness = harness.replace("// REUSE", source_block(engine, "        if currentPlaybackContentKind == .video\n            && !pendingWebRetirementOnVideoReady"))
        with tempfile.TemporaryDirectory(prefix="mwx-ready-timer-") as directory:
            source, binary = Path(directory) / "main.swift", Path(directory) / "harness"
            source.write_text(harness)
            compiled = subprocess.run(["xcrun", "swiftc", str(source), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("video-ready-timer-pass", result.stdout)

    def test_latest_runtime_intent_controls_autoplay(self) -> None:
        program = """
        import Foundation

        let gate = ImportedVideoAutoplayGate.shared
        final class TestLifetime: PlaybackResourceLifetime {}

        let firstRequest = gate.claim()
        let latestRequest = gate.claim()
        precondition(!gate.isCurrent(firstRequest))
        precondition(gate.isCurrent(latestRequest))

        // A delayed import cannot replace the latest explicit playback intent.
        precondition(!gate.isCurrent(firstRequest))

        let staleAfterNewIntent = gate.claim()
        gate.invalidate() // Accepted product intent revokes before preparation.
        precondition(!gate.isCurrent(staleAfterNewIntent))
        // A previous output can finish its handoff after a newer import was
        // selected. Visible-output retirement must not revoke that new ticket.
        let pendingAfterEarlierHandoff = gate.claim()
        postWallpaperRuntimeWillSwitch(to: .web)
        precondition(gate.isCurrent(pendingAfterEarlierHandoff))

        let replacedSameItem = gate.claim()
        let currentSameItem = gate.claim()
        precondition(!gate.isCurrent(replacedSameItem))
        precondition(gate.isCurrent(currentSameItem))

        var decodedRequest: ImportedVideoPlaybackRequest?
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("AutoplayGateTest"), object: nil, queue: nil
        ) { notification in
            decodedRequest = ImportedVideoPlaybackRequest(notification: notification)
        }
        let lifetime = TestLifetime()
        ImportedVideoPlaybackRequest(
            localURL: URL(fileURLWithPath: "/tmp/latest.mp4"),
            autoplayToken: currentSameItem,
            resourceLifetime: lifetime
        ).post(name: Notification.Name("AutoplayGateTest"))
        NotificationCenter.default.removeObserver(observer)
        precondition(decodedRequest?.localURL.path == "/tmp/latest.mp4")
        precondition(decodedRequest?.autoplayToken == currentSameItem)
        precondition(decodedRequest?.resourceLifetime === lifetime)

        print("imported-video-autoplay-gate-pass")
        """
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            main_source = directory_path / "main.swift"
            executable = directory_path / "gate-test"
            main_source.write_text(program, encoding="utf-8")
            subprocess.run(
                [
                    "/usr/bin/xcrun",
                    "swiftc",
                    *(str(source) for source in GATE_SOURCES),
                    str(main_source),
                    "-o",
                    str(executable),
                ],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.stdout.strip(), "imported-video-autoplay-gate-pass")


if __name__ == "__main__":
    unittest.main()
