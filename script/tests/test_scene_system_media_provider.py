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

@MainActor enum SceneMediaSourcePreference: String {
    case disabled, appleMusic, systemNowPlaying
    static var current = Self.appleMusic
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
    enum State: Sendable { case playing; var inboxValue: Int { 1 } }
    struct Snapshot: Sendable {
        var artworkPalette: SceneMediaArtworkPalette? = testPalette(1)
        let identity: String; let title: String; let artist = "Artist"; let album = "Album"
        let state = State.playing; let position = 5.0; let duration = 100.0
        let artworkData: Data? = Data([1, 2, 3])
    }
    enum AuthorizationStatus: Sendable { case authorized, denied }
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
    nonisolated enum Failure: Equatable, Sendable { case heartbeatTimeout, helperUnavailable }
    nonisolated enum Result: Sendable { case snapshot(Snapshot), noSession, unavailable(Failure) }
    static var latest: SceneSystemMediaSource?
    static var starts = 0
    var callback: (@MainActor @Sendable (Result) -> Void)?
    func start(_ receive: @escaping @MainActor @Sendable (Result) -> Void) { callback = receive; Self.latest = self; Self.starts += 1 }
    func stop() { callback = nil }
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
        switch CommandLine.arguments[1] {
        case "lifecycle":
            provider.acquire(first)
            wait { inbox.latest().properties?.title == "Track A" }
            provider.acquire(second)
            precondition(control.counts().0 == 1)
            precondition(inbox.latest().primaryColor == testPalette(1).primaryColor)
            provider.release(first)
            precondition(inbox.latest().properties?.title == "Track A")
            provider.release(second)
            let empty = inbox.latest()
            precondition(empty.current == nil && empty.properties?.title == "" && empty.playbackState == 0)
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
            provider.release(first)
            control.update { $0.authorization = .authorized }
            provider.acquire(second)
            wait { inbox.latest().properties?.title == "Track A" }
            NSRunningApplication.pid = nil
            wait { inbox.latest().properties?.title == "" }
            provider.release(second)
        case "system":
            SceneMediaSourcePreference.current = .systemNowPlaying
            provider.acquire(first)
            let source = SceneSystemMediaSource.latest!
            let oldCallback = source.callback!
            let red = Data([1]), blue = Data([2])
            source.callback?(.snapshot(.init(source: "Player A", identity: "one", title: "First", artworkChanged: true, artworkData: red, artworkPalette: testPalette(1))))
            precondition(inbox.latest().current == red && inbox.latest().properties?.title == "First")
            source.callback?(.snapshot(.init(source: "Player A", identity: "one", title: "First", artworkChanged: false, artworkData: nil)))
            precondition(inbox.latest().current == red, "same-track update lost cached cover")
            precondition(inbox.latest().primaryColor == testPalette(1).primaryColor, "same-track update lost palette")
            source.callback?(.snapshot(.init(source: "Player B", identity: "one", title: "Second", artworkChanged: true, artworkData: nil)))
            precondition(inbox.latest().current == nil && inbox.latest().properties?.title == "Second")
            precondition(inbox.latest().primaryColor == .zero, "new source inherited old palette")
            source.callback?(.snapshot(.init(source: "Player B", identity: "one", title: "Second", artworkChanged: true, artworkData: blue, artworkPalette: testPalette(0))))
            precondition(inbox.latest().current == blue, "late current-track cover failed")
            precondition(inbox.latest().primaryColor == testPalette(0).primaryColor)
            let paletteGeneration = inbox.latest().generation
            source.callback?(.snapshot(.init(source: "Player B", identity: "one", title: "Second", artworkChanged: false, artworkData: nil)))
            precondition(inbox.latest().generation == paletteGeneration, "metadata-only poll retriggered cover")
            source.callback?(.unavailable(.heartbeatTimeout))
            precondition(inbox.latest().current == nil && inbox.latest().properties?.title == "")
            precondition(inbox.latest().primaryColor == .zero && inbox.latest().textColor == .zero)
            wait(4) { SceneSystemMediaSource.starts == 2 }
            oldCallback(.snapshot(.init(source: "Player A", identity: "one", title: "Stale retry", artworkChanged: true, artworkData: red)))
            precondition(inbox.latest().properties?.title == "", "retired transport published after retry")
            source.callback?(.snapshot(.init(source: "Player B", identity: "one", title: "Recovered", artworkChanged: true, artworkData: blue)))
            precondition(inbox.latest().properties?.title == "Recovered")
            provider.release(first)
            precondition(source.callback == nil)
            provider.acquire(second)
            oldCallback(.snapshot(.init(source: "Player A", identity: "one", title: "Stale", artworkChanged: true, artworkData: red)))
            precondition(inbox.latest().properties?.title == "", "retired source published into replacement")
            source.callback?(.snapshot(.init(source: "Player B", identity: "two", title: "New", artworkChanged: true, artworkData: blue)))
            provider.release(second)
            precondition(inbox.latest().current == nil && inbox.latest().properties?.title == "")
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
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PASS ' + name, result.stdout)

    def test_last_demand_retires_polling_and_clears_all_channels(self):
        self.check_case('lifecycle')

    def test_retired_inflight_response_cannot_publish_into_new_demand(self):
        self.check_case('stale')

    def test_denied_permission_is_latched_and_player_exit_clears(self):
        self.check_case('permission')

    def test_session_publication_has_no_mixed_channels_and_rejects_atomically(self):
        self.check_case('atomic')

    def test_system_source_cover_identity_failure_and_retirement(self):
        self.check_case("system")
