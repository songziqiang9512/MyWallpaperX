"""Execute the production publisher and inbox with a controlled platform edge."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Systems/Media'
HARNESS = r'''
import AppKit
import Foundation

@MainActor enum SceneMediaSourcePreference {
    static var isEnabled = true
    static let changed = Notification.Name("mwx-test-media-source-" + UUID().uuidString)
    static func refresh() {}
}
@MainActor final class NSRunningApplication {
    static var pid: pid_t? = 42
    let processIdentifier: pid_t
    var isTerminated = false
    init(_ pid: pid_t) { processIdentifier = pid }
    static func runningApplications(withBundleIdentifier _: String) -> [NSRunningApplication] {
        pid.map { [NSRunningApplication($0)] } ?? []
    }
}
nonisolated enum SceneMusicPlayerSource {
    enum State: Int, Sendable { case stopped = 0, playing = 1, paused = 2; var inboxValue: Int { rawValue } }
    struct Snapshot: Sendable {
        var artworkPalette: SceneMediaArtworkPalette? = testPalette(1)
        let identity: String; let title: String; let artist = "Artist"; let album = "Album"
        var albumArtist = "Album Artist"
        var state = State.playing; let position = 5.0; let duration = 100.0
        var artworkData: Data? = Data([1, 2, 3])
    }
    enum AuthorizationStatus: Sendable {
        case authorized, denied, consentRequired
        case unavailable(SceneSystemMediaSource.Failure)
    }
    enum ReadResult: Sendable { case snapshot(Snapshot), noSession, failure(String) }
    static let control = Control()
    static func silentAuthorization(pid: pid_t) -> AuthorizationStatus {
        control.lock.lock(); defer { control.lock.unlock() }
        control.authorizations += 1; return control.authorization
    }
    static func read(pid: pid_t, cachedArtworkIdentity: String?, cachedArtworkData: Data?,
                     cachedArtworkPalette: SceneMediaArtworkPalette?) -> ReadResult {
        control.lock.lock()
        control.reads += 1
        let value = control.result, blocker = control.blocker
        control.entered = true
        control.lock.unlock()
        if let blocker { precondition(blocker.wait(timeout: .now() + 5) == .success) }
        return value
    }
    final class Control: @unchecked Sendable {
        let lock = NSLock()
        var reads = 0, authorizations = 0
        var authorization = AuthorizationStatus.authorized
        var result = ReadResult.snapshot(.init(identity: "A", title: "Track A"))
        var blocker: DispatchSemaphore?
        var entered = false
        func update(_ body: (Control) -> Void) { lock.lock(); defer { lock.unlock() }; body(self) }
        func counts() -> (Int, Int, Bool) { lock.lock(); defer { lock.unlock() }; return (reads, authorizations, entered) }
    }
}
@MainActor final class SceneSystemMediaSource {
    nonisolated struct Snapshot: Sendable {
        let source: String, identity: String, title: String?
        var artist: String? = "Artist", album: String? = "Album"
        var playbackState: Int? = 1
        var position: Double? = 5, duration: Double? = 100
        var artworkIdentifier: String? = "art"
        let artworkChanged: Bool, artworkData: Data?
        var artworkFailure: String? = nil
        var artworkPalette: SceneMediaArtworkPalette? = nil
    }
    nonisolated enum Failure: Equatable, Sendable { case missingResource, heartbeatTimeout, helperUnavailable }
    nonisolated enum Result: Sendable { case snapshot(Snapshot), noSession, unavailable(Failure) }
    static var latest: SceneSystemMediaSource?
    static var starts = 0
    static var initial: Result? = .unavailable(.missingResource)
    var callback: (@MainActor @Sendable (Result) -> Void)?
    func start(_ receive: @escaping @MainActor @Sendable (Result) -> Void) {
        guard callback == nil else { return }
        callback = receive; Self.latest = self; Self.starts += 1
        if let initial = Self.initial { deliver(initial) }
    }
    func stop() { callback = nil }
    /// A terminal unavailable result retires the transport, mirroring the
    /// production session teardown that lets a later start succeed.
    func deliver(_ result: Result) {
        guard let current = callback else { return }
        if case let .unavailable(failure) = result, failure != .helperUnavailable { callback = nil }
        current(result)
    }
}
nonisolated func testPalette(_ red: Double) -> SceneMediaArtworkPalette {
    .init(primaryColor: .init(red, 0, 1 - red), secondaryColor: .init(0, 1, 0),
          tertiaryColor: .init(1, 1, 0), textColor: .init(1, 1, 1), highContrastColor: .init(0, 0, 0))
}
@main struct Main {
    @MainActor static func wait(_ seconds: Double = 3, until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        precondition(condition(), "condition timed out")
    }
    @MainActor static func main() {
        let inbox = SceneMediaThumbnailInbox(), control = SceneMusicPlayerSource.control
        let provider = SceneSystemMediaProvider(inbox: inbox)
        let first = UUID(), second = UUID()
        let name = CommandLine.arguments[1]
        if !["lifecycle", "stale", "permission", "fallback-invalid", "atomic"].contains(name) {
            SceneSystemMediaSource.initial = nil
        }
        switch name {
        case "lifecycle":
            provider.acquire(first)
            wait { inbox.latest().properties?.title == "Track A" }
            provider.acquire(second)
            precondition(control.counts().0 == 1)
            precondition(inbox.latest().primaryColor == testPalette(1).primaryColor)
            precondition(inbox.latest().properties?.albumArtist == "Album Artist")
            control.update {
                $0.result = .snapshot(.init(identity: "A", title: "Track A", albumArtist: ""))
            }
            wait { inbox.latest().properties?.albumArtist == "" }
            precondition(inbox.latest().properties?.artist == "Artist",
                         "missing album artist must preserve the independently supplied artist")
            provider.release(first)
            precondition(inbox.latest().properties?.title == "Track A")
            provider.release(second)
            let empty = inbox.latest()
            precondition(empty.current == nil && empty.properties?.title == "" && empty.properties?.albumArtist == "" && empty.playbackState == 0)
            precondition(empty.timeline?.position == 0 && empty.timeline?.duration == 0)
            let count = control.counts().0
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
            precondition(control.counts().0 == count, "last release must stop polling")
        case "stale":
            let held = DispatchSemaphore(value: 0)
            control.update { $0.blocker = held }
            provider.acquire(first)
            wait { control.counts().2 }
            provider.release(first)
            control.update { $0.result = .snapshot(.init(identity: "B", title: "Track B")); $0.blocker = nil }
            provider.acquire(second)
            held.signal()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            precondition(inbox.latest().properties == nil, "retired request leaked into new demand")
            wait { inbox.latest().properties?.title == "Track B" }
            provider.release(second)
        case "permission":
            control.update { $0.authorization = .denied }
            provider.acquire(first)
            wait { control.counts().1 == 1 }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
            precondition(control.counts().0 == 0 && control.counts().1 == 1)
            precondition(SceneSystemMediaSource.starts == 1,
                         "denied latch must not respawn the system transport per poll")
            provider.release(first)
            control.update { $0.authorization = .authorized }
            provider.acquire(second)
            wait { inbox.latest().properties?.title == "Track A" }
            NSRunningApplication.pid = nil
            wait { inbox.latest().properties?.title == "" }
            provider.release(second)
        case "system":
            // The system observer owns selection even when Music is running.
            NSRunningApplication.pid = nil
            provider.acquire(first)
            let source = SceneSystemMediaSource.latest!
            let oldCallback = source.callback!
            let red = Data([1]), blue = Data([2])
            source.deliver(.snapshot(.init(source: "Player A", identity: "one", title: "First", artworkChanged: true, artworkData: red, artworkPalette: testPalette(1))))
            precondition(inbox.latest().current == red && inbox.latest().properties?.title == "First")
            source.deliver(.snapshot(.init(source: "Player A", identity: "one", title: "First", artworkChanged: false, artworkData: nil)))
            precondition(inbox.latest().current == red, "same-track update lost cached cover")
            precondition(inbox.latest().primaryColor == testPalette(1).primaryColor, "same-track update lost palette")
            source.deliver(.snapshot(.init(source: "Player B", identity: "one", title: "Second", artworkChanged: true, artworkData: nil)))
            precondition(inbox.latest().current == nil && inbox.latest().properties?.title == "Second")
            precondition(inbox.latest().primaryColor == .zero, "new source inherited old palette")
            source.deliver(.snapshot(.init(source: "Player B", identity: "one", title: "Second", artworkChanged: true, artworkData: blue, artworkPalette: testPalette(0))))
            precondition(inbox.latest().current == blue, "late current-track cover failed")
            precondition(inbox.latest().primaryColor == testPalette(0).primaryColor)
            let paletteGeneration = inbox.latest().generation
            source.deliver(.snapshot(.init(source: "Player B", identity: "one", title: "Second", artworkChanged: false, artworkData: nil)))
            precondition(inbox.latest().generation == paletteGeneration, "metadata-only poll retriggered cover")
            source.deliver(.unavailable(.heartbeatTimeout))
            precondition(inbox.latest().current == nil && inbox.latest().properties?.title == "")
            precondition(inbox.latest().primaryColor == .zero && inbox.latest().textColor == .zero)
            // The restart deadline is consumed by the 2s poll cadence, so the
            // retry lands on the second poll tick at the earliest.
            wait(6) { SceneSystemMediaSource.starts == 2 }
            oldCallback(.snapshot(.init(source: "Player A", identity: "one", title: "Stale retry", artworkChanged: true, artworkData: red)))
            precondition(inbox.latest().properties?.title == "", "retired transport published after retry")
            source.deliver(.snapshot(.init(source: "Player B", identity: "one", title: "Recovered", artworkChanged: true, artworkData: blue)))
            precondition(inbox.latest().properties?.title == "Recovered")
            provider.release(first)
            precondition(source.callback == nil)
            provider.acquire(second)
            oldCallback(.snapshot(.init(source: "Player A", identity: "one", title: "Stale", artworkChanged: true, artworkData: red)))
            precondition(inbox.latest().properties?.title == "", "retired source published into replacement")
            source.deliver(.snapshot(.init(source: "Player B", identity: "two", title: "New", artworkChanged: true, artworkData: blue)))
            provider.release(second)
            precondition(inbox.latest().current == nil && inbox.latest().properties?.title == "")
        case "selected-other-player":
            provider.acquire(first)
            let source = SceneSystemMediaSource.latest!
            source.deliver(.snapshot(.init(source: "other.player", identity: "B", title: "Selected B",
                artworkChanged: true, artworkData: Data([9]))))
            let selected = inbox.latest()
            for state in [SceneMusicPlayerSource.State.paused, .stopped, .playing] {
                control.update { $0.result = .snapshot(.init(identity: "A", title: "Old Music", state: state)) }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
                precondition(inbox.latest() == selected, "Music stole selected player")
                precondition(source.callback != nil, "source selection observation stopped")
            }
            precondition(control.counts().0 == 0 && control.counts().1 == 0,
                         "unselected player must not incur public reads or authorization probes")
            provider.release(first)
        case "unknown-selection":
            provider.acquire(first)
            let source = SceneSystemMediaSource.latest!
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.1))
            precondition(control.counts().0 == 0, "pending selection enabled Music fallback")
            source.deliver(.noSession)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.1))
            source.deliver(.unavailable(.helperUnavailable))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.1))
            precondition(control.counts().0 == 0, "empty or unknown selection enabled Music fallback")
            precondition(source.callback != nil, "temporary unknown stopped the live observer")
            source.deliver(.unavailable(.heartbeatTimeout))
            wait(6) { SceneSystemMediaSource.starts == 2 }
            precondition(control.counts().0 == 0, "transport retry enabled Music fallback")
            provider.release(first)
        case "supplement":
            provider.acquire(first)
            let source = SceneSystemMediaSource.latest!
            let value = SceneSystemMediaSource.Snapshot(source: "com.apple.Music", identity: "system-A", title: "Track A",
                playbackState: 2, position: 17, artworkChanged: true, artworkData: Data([9]), artworkPalette: testPalette(0))
            source.deliver(.snapshot(value))
            wait { inbox.latest().properties?.albumArtist == "Album Artist" }
            let selected = inbox.latest()
            precondition(selected.current == Data([9]) && selected.primaryColor == testPalette(0).primaryColor,
                         "public API replaced system artwork")
            precondition(selected.playbackState == 2 && selected.timeline?.position == 17,
                         "public playing state replaced selected paused state")
            for _ in 0..<3 {
                source.deliver(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Track A",
                    playbackState: 2, position: 17, artworkChanged: false, artworkData: nil)))
                precondition(inbox.latest() == selected, "system tick cleared accepted supplement or artwork")
            }
            control.update { $0.result = .snapshot(.init(identity: "B", title: "Track B")) }
            wait { inbox.latest().properties?.albumArtist == "" }
            precondition(inbox.latest().properties?.title == "Track A" && inbox.latest().current == Data([9]),
                         "new public track replaced system selection")
            control.update { $0.result = .snapshot(.init(identity: "A", title: "Track A", albumArtist: "")) }
            source.deliver(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Track A",
                playbackState: 2, artworkChanged: true, artworkData: nil)))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.1))
            precondition(inbox.latest().properties?.albumArtist == "" && inbox.latest().current == nil,
                         "public cover substituted for an explicitly missing system cover")
            // Restarting or exiting Music cannot tear down an unrelated system source.
            source.deliver(.snapshot(.init(source: "other.player", identity: "B", title: "Selected B",
                artworkChanged: true, artworkData: Data([8]))))
            NSRunningApplication.pid = nil
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.1))
            precondition(inbox.latest().properties?.title == "Selected B" && source.callback != nil)
            provider.release(first)
        case "supplement-no-session", "supplement-failure":
            provider.acquire(first)
            let source = SceneSystemMediaSource.latest!
            source.deliver(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Track A",
                artworkChanged: true, artworkData: Data([9]))))
            wait { inbox.latest().properties?.albumArtist == "Album Artist" }
            control.update { $0.result = name == "supplement-no-session" ? .noSession : .failure("timeout") }
            wait { inbox.latest().properties?.albumArtist == "" }
            precondition(inbox.latest().properties?.title == "Track A" && inbox.latest().current == Data([9]))
            precondition(source.callback != nil && SceneSystemMediaSource.starts == 1)
            provider.release(first)
        case "selection-aba", "selection-new-key":
            let held = DispatchSemaphore(value: 0)
            control.update { $0.blocker = held }
            provider.acquire(first)
            let source = SceneSystemMediaSource.latest!
            source.deliver(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Track A",
                artworkChanged: true, artworkData: Data([9]))))
            wait { control.counts().2 }
            if name == "selection-aba" {
                source.deliver(.snapshot(.init(source: "other.player", identity: "B", title: "Selected B",
                    artworkChanged: true, artworkData: Data([8]))))
            }
            source.deliver(.snapshot(.init(source: "com.apple.Music", identity: name == "selection-aba" ? "system-A" : "system-C",
                title: "Track A", artworkChanged: true, artworkData: Data([7]))))
            control.update { $0.blocker = nil; $0.result = .snapshot(.init(identity: "fresh", title: "Track A", albumArtist: "Fresh")) }
            held.signal()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            precondition(inbox.latest().properties?.albumArtist == "", "retired selection supplement survived ABA/new key")
            wait { inbox.latest().properties?.albumArtist == "Fresh" }
            precondition(inbox.latest().current == Data([7]))
            provider.release(first)
        case "disable":
            let held = DispatchSemaphore(value: 0)
            control.update { $0.blocker = held }
            provider.acquire(first)
            let source = SceneSystemMediaSource.latest!
            source.deliver(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Track A",
                artworkChanged: true, artworkData: Data([9]))))
            let old = source.callback!
            wait { control.counts().2 }
            SceneMediaSourcePreference.isEnabled = false
            DistributedNotificationCenter.default().postNotificationName(SceneMediaSourcePreference.changed,
                object: nil, userInfo: nil, deliverImmediately: true)
            wait { source.callback == nil }
            held.signal()
            old(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Stale", artworkChanged: true, artworkData: Data([9]))))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            precondition(inbox.latest().properties?.title == "" && inbox.latest().current == nil)
            provider.release(first)
        case "fallback-invalid":
            provider.acquire(first)
            wait { inbox.latest().properties?.title == "Track A" }
            control.update { $0.result = .snapshot(.init(identity: "bad", title: "Bad", artworkData: Data())) }
            wait { inbox.latest().properties?.title == "" }
            control.update { $0.result = .snapshot(.init(identity: "B", title: "Track B", state: .paused)) }
            wait { inbox.latest().properties?.title == "Track B" }
            precondition(inbox.latest().playbackState == 2)
            control.update { $0.result = .noSession }
            wait { inbox.latest().properties?.title == "" }
            provider.release(first)
        case "atomic":
            let a = SceneMediaThumbnailInbox.Snapshot.Properties(title: "A", artist: "A", subTitle: "", albumTitle: "", albumArtist: "", genres: "", contentType: "")
            let b = SceneMediaThumbnailInbox.Snapshot.Properties(title: "B", artist: "B", subTitle: "", albumTitle: "", albumArtist: "", genres: "", contentType: "")
            precondition(inbox.publishMediaSession(artwork: Data([1]), properties: a, playbackState: 1, timeline: .init(position: 1, duration: 10)))
            DispatchQueue.concurrentPerform(iterations: 2000) { index in
                let first = index % 2 == 0
                precondition(inbox.publishMediaSession(artwork: Data([first ? 1 : 2]), properties: first ? a : b,
                    playbackState: first ? 1 : 2, timeline: .init(position: first ? 1 : 2, duration: 10),
                    primaryColor: .init(first ? 1 : 0, 0, 0), secondaryColor: .init(0, first ? 1 : 0, 0),
                    tertiaryColor: .init(0, 0, first ? 1 : 0), textColor: .init(repeating: first ? 1 : 0),
                    highContrastColor: .init(repeating: first ? 0 : 1)))
                let value = inbox.latest(), expected = value.properties?.title == "A" ? 1 : 2
                precondition(value.current == Data([UInt8(expected)]) && value.playbackState == expected && value.timeline?.position == Double(expected))
                precondition(value.primaryColor == .init(expected == 1 ? 1 : 0, 0, 0))
                precondition(value.secondaryColor == .init(0, expected == 1 ? 1 : 0, 0))
                precondition(value.tertiaryColor == .init(0, 0, expected == 1 ? 1 : 0))
                precondition(value.textColor == .init(repeating: expected == 1 ? 1 : 0))
                precondition(value.highContrastColor == .init(repeating: expected == 1 ? 0 : 1))
            }
            let before = inbox.latest()
            precondition(!inbox.publishMediaSession(artwork: Data(), properties: a, playbackState: 1, timeline: .init(position: 1, duration: 10)))
            precondition(inbox.latest() == before)
            precondition(!inbox.publishMediaSession(artwork: Data([1]), properties: a, playbackState: 1,
                timeline: .init(position: 1, duration: 10), primaryColor: .init(.nan, 0, 0)))
            precondition(inbox.latest() == before, "invalid palette partially published")
            precondition(inbox.clearMediaSession())
            let cleared = inbox.latest()
            precondition(cleared.current == nil && cleared.properties?.title == "" && cleared.playbackState == 0 && cleared.timeline?.duration == 0)
            precondition(inbox.clearMediaSession() && inbox.latest() == cleared)
        default: fatalError("unknown case")
        }
        print("PASS " + CommandLine.arguments[1])
    }
}
'''

class SceneSystemMediaProviderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('swiftc'):
            raise unittest.SkipTest('swiftc unavailable')
        cls.temp = tempfile.TemporaryDirectory(prefix='mwx-system-media-provider-')
        cls.addClassCleanup(cls.temp.cleanup)
        root = Path(cls.temp.name)
        harness = root / 'Harness.swift'
        harness.write_text(HARNESS)
        cls.binary = root / 'provider'
        env = os.environ.copy()
        env['CLANG_MODULE_CACHE_PATH'] = str(root / 'clang-cache')
        result = subprocess.run(['swiftc', '-swift-version', '6', '-default-isolation', 'MainActor',
            str(MEDIA / 'SceneMediaArtworkPalette.swift'), str(MEDIA / 'SceneMediaThumbnailInbox.swift'), str(MEDIA / 'SceneSystemMediaProvider.swift'),
            str(harness), '-o', str(cls.binary)], env=env, capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stderr)

    def check_case(self, name):
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True, timeout=18)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PASS ' + name, result.stdout)

    def test_paused_music_cannot_steal_selected_other_player(self):
        self.check_case('selected-other-player')

    def test_last_demand_retires_polling_and_clears_all_channels(self):
        self.check_case('lifecycle')

    def test_retired_inflight_response_cannot_publish_into_new_demand(self):
        self.check_case('stale')

    def test_denied_permission_is_latched_and_player_exit_clears(self):
        self.check_case('permission')

    def test_pending_empty_and_temporarily_unavailable_selection_do_not_guess_music(self):
        self.check_case('unknown-selection')

    def test_selected_music_supplement_preserves_system_pause_cover_and_stable_events(self):
        self.check_case('supplement')

    def test_empty_music_read_preserves_system_session(self):
        self.check_case('supplement-no-session')

    def test_failed_music_read_preserves_system_session(self):
        self.check_case('supplement-failure')

    def test_selection_aba_rejects_old_music_supplement(self):
        self.check_case('selection-aba')

    def test_new_system_key_with_same_metadata_requires_fresh_supplement(self):
        self.check_case('selection-new-key')

    def test_disable_retires_both_inputs(self):
        self.check_case('disable')

    def test_missing_backend_retains_public_fallback_validation_and_pause(self):
        self.check_case('fallback-invalid')

    def test_session_publication_has_no_mixed_channels_and_rejects_atomically(self):
        self.check_case('atomic')

    def test_system_source_cover_identity_failure_and_retirement(self):
        self.check_case("system")
