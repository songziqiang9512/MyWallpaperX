"""Execute the production publisher and inbox with a controlled platform edge."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / 'MyWallpaperX/Core/Playback/SystemMedia'
SOURCE_PATHS = [MEDIA / name for name in (
    'SystemMediaArtworkPalette.swift', 'SystemMediaSnapshotStore.swift',
    'SystemMediaSnapshot.swift', 'SystemMediaWebArtwork.swift', 'SystemMediaService.swift')]
SOURCE_PATHS.append(ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMediaThumbnailInbox.swift')
CONFIGURATIONS = (('debug', ('-D', 'DEBUG')), ('release', ('-O',)))
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
nonisolated enum SystemMusicPlayerSource {
    enum State: Int, Sendable { case stopped = 0, playing = 1, paused = 2; var inboxValue: Int { rawValue } }
    struct Snapshot: Sendable {
        var artworkPalette: SystemMediaArtworkPalette? = testPalette(1)
        let identity: String; let title: String; let artist = "Artist"; let album = "Album"
        var albumArtist = "Album Artist"
        var state = State.playing; let position = 5.0; let duration = 100.0
        var artworkData: Data? = Data([1, 2, 3])
    }
    enum AuthorizationStatus: Sendable {
        case authorized, denied, consentRequired
        case unavailable(SystemMediaSource.Failure)
    }
    enum ReadResult: Sendable { case snapshot(Snapshot), noSession, failure(String) }
    static let control = Control()
    static func silentAuthorization(pid: pid_t) -> AuthorizationStatus {
        control.lock.lock()
        control.authorizations += 1
        let result = control.authorization, blocker = control.preflightBlocker
        control.lock.unlock()
        if let blocker { precondition(blocker.wait(timeout: .now() + 5) == .success) }
        return result
    }
    static func requestAuthorization(pid: pid_t) -> AuthorizationStatus {
        control.lock.lock()
        control.requests += 1
        let result = control.requestResult, blocker = control.requestBlocker
        control.lock.unlock()
        if let blocker { precondition(blocker.wait(timeout: .now() + 5) == .success) }
        switch result {
        case .unavailable: break // A failed request leaves the system grant unchanged.
        default: control.update { $0.authorization = result }
        }
        return result
    }
    static func read(pid: pid_t, cachedArtworkIdentity: String?, cachedArtworkData: Data?,
                     cachedArtworkPalette: SystemMediaArtworkPalette?) -> ReadResult {
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
        var reads = 0, authorizations = 0, requests = 0
        var authorization = AuthorizationStatus.authorized
        var requestResult = AuthorizationStatus.authorized
        var preflightBlocker: DispatchSemaphore?
        var requestBlocker: DispatchSemaphore?
        var result = ReadResult.snapshot(.init(identity: "A", title: "Track A"))
        var blocker: DispatchSemaphore?
        var entered = false
        func update(_ body: (Control) -> Void) { lock.lock(); defer { lock.unlock() }; body(self) }
        func counts() -> (Int, Int, Bool, Int) { lock.lock(); defer { lock.unlock() }; return (reads, authorizations, entered, requests) }
    }
}
@MainActor final class SystemMediaSource {
    nonisolated struct Snapshot: Sendable {
        let source: String, identity: String, title: String?
        var artist: String? = "Artist", album: String? = "Album"
        var playbackState: Int? = 1
        var position: Double? = 5, duration: Double? = 100
        var artworkIdentifier: String? = "art"
        let artworkChanged: Bool, artworkData: Data?
        var artworkFailure: String? = nil
        var artworkPalette: SystemMediaArtworkPalette? = nil
    }
    nonisolated enum Failure: Equatable, Sendable { case missingResource, heartbeatTimeout, helperUnavailable }
    nonisolated enum Result: Sendable { case snapshot(Snapshot), noSession, unavailable(Failure) }
    static var latest: SystemMediaSource?
    static var starts = 0
    static var stops = 0
    static var initial: Result? = .unavailable(.missingResource)
    var callback: (@MainActor @Sendable (Result) -> Void)?
    func start(_ receive: @escaping @MainActor @Sendable (Result) -> Void) {
        guard callback == nil else { return }
        callback = receive; Self.latest = self; Self.starts += 1
        if let initial = Self.initial { deliver(initial) }
    }
    func stop() { if callback != nil { Self.stops += 1 }; callback = nil }
    /// A terminal unavailable result retires the transport, mirroring the
    /// production session teardown that lets a later start succeed.
    func deliver(_ result: Result) {
        guard let current = callback else { return }
        if case let .unavailable(failure) = result, failure != .helperUnavailable { callback = nil }
        current(result)
    }
}
nonisolated func testPalette(_ red: Double) -> SystemMediaArtworkPalette {
    .init(primaryColor: .init(red, 0, 1 - red), secondaryColor: .init(0, 1, 0),
          tertiaryColor: .init(1, 1, 0), textColor: .init(1, 1, 1), highContrastColor: .init(0, 0, 0))
}
nonisolated final class WebArtworkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var blocker: DispatchSemaphore?
    func setBlocker(_ value: DispatchSemaphore?) {
        lock.lock(); blocker = value; lock.unlock()
    }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func prepare(_ data: Data) -> String? {
        lock.lock()
        count += 1
        let call = count, held = blocker
        lock.unlock()
        if let held { precondition(held.wait(timeout: .now() + 5) == .success) }
        return "converted-\(call)-\(data.first ?? 0)"
    }
}
@main struct Main {
    @MainActor static func wait(_ seconds: Double = 3, until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        precondition(condition(), "condition timed out")
    }
    @MainActor static func main() {
        let inbox = SceneMediaThumbnailInbox(), control = SystemMusicPlayerSource.control
        let name = CommandLine.arguments[1]
        let artworkProbe = WebArtworkProbe()
        let provider = name.hasPrefix("web-artwork-demand")
            ? SystemMediaService(inbox: inbox, prepareWebArtwork: { artworkProbe.prepare($0) })
            : SystemMediaService(inbox: inbox)
        let fields = Set(Mirror(reflecting: provider).children.compactMap(\.label))
#if DEBUG
        precondition(fields.contains("lastStatus"), "Debug must retain source status observation")
#else
        precondition(!fields.contains("lastStatus"), "Release must not retain source status observation")
#endif
        let first = UUID(), second = UUID()
        if !["lifecycle", "stale", "permission", "fallback-invalid", "atomic"].contains(name) {
            SystemMediaSource.initial = nil
        }
        switch name {
        case "web-artwork-demand", "web-artwork-demand-queued":
            var received: [SystemMediaSnapshot] = []
            provider.subscribe(first) { received.append($0) } // Scene-only consumer.
            let source = SystemMediaSource.latest!
            func track(_ identity: String, byte: UInt8) {
                source.deliver(.snapshot(.init(source: "other", identity: identity, title: identity,
                    artworkChanged: true, artworkData: Data([byte]), artworkPalette: testPalette(0.4))))
            }
            track("A", byte: 1)
            let scene = provider.currentSnapshot
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            precondition(artworkProbe.calls == 0 && scene.webThumbnail == nil,
                         "Scene-only demand must never prepare Web artwork")
            let starts = SystemMediaSource.starts, stops = SystemMediaSource.stops
            let statusOnly = UUID()
            provider.subscribe(statusOnly, needsMedia: false, needsWebArtwork: true) { _ in }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            precondition(artworkProbe.calls == 0 && provider.currentSnapshot == scene,
                         "a status-only subscription cannot acquire Web artwork")
            provider.unsubscribe(statusOnly)
            if name == "web-artwork-demand-queued" {
                let held = DispatchSemaphore(value: 0)
                artworkProbe.setBlocker(held)
                provider.subscribe(second, needsWebArtwork: true) { _ in }
                wait { artworkProbe.calls == 1 }
                track("B", byte: 2) // Queued behind A's image preparation.
                provider.unsubscribe(second)
                held.signal()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
                precondition(artworkProbe.calls == 1 && provider.currentSnapshot.webThumbnail == nil,
                             "revoking Web must skip queued conversion and reject in-flight output")
                precondition(provider.currentSnapshot.media.current == Data([2]))
            } else {
                provider.subscribe(second, needsWebArtwork: true) { _ in }
                wait { provider.currentSnapshot.webThumbnail == "converted-1-1" }
                precondition(provider.currentSnapshot.media == scene.media && provider.currentSnapshot.epoch == scene.epoch)
                provider.subscribe(second, needsWebArtwork: true) { _ in }
                let third = UUID()
                provider.subscribe(third, needsWebArtwork: true) { _ in }
                precondition(artworkProbe.calls == 1, "continuous Web demand reuses current prepared artwork")
                provider.unsubscribe(second); provider.unsubscribe(third)
                precondition(provider.currentSnapshot.webThumbnail == nil && provider.currentSnapshot.media == scene.media)
                let held = DispatchSemaphore(value: 0)
                artworkProbe.setBlocker(held)
                var thumbnails: [String] = []
                provider.subscribe(second, needsWebArtwork: true) { if let value = $0.webThumbnail { thumbnails.append(value) } }
                wait { artworkProbe.calls == 2 }
                provider.unsubscribe(second)
                provider.subscribe(second, needsWebArtwork: true) { if let value = $0.webThumbnail { thumbnails.append(value) } }
                artworkProbe.setBlocker(nil)
                held.signal()
                wait { provider.currentSnapshot.webThumbnail == "converted-3-1" }
                precondition(!thumbnails.contains("converted-2-1"), "old Web demand cannot publish to a replacement lease")
                track("B", byte: 2)
                wait { provider.currentSnapshot.webThumbnail == "converted-4-2" }
                track("A", byte: 1)
                wait { provider.currentSnapshot.webThumbnail == "converted-5-1" }
                source.deliver(.noSession)
                precondition(provider.currentSnapshot.webThumbnail == nil && provider.currentSnapshot.media.current == nil)
                provider.unsubscribe(second)
            }
            precondition(provider.currentSnapshot.epoch == scene.epoch,
                         "Web artwork leases cannot advance the shared media epoch")
            precondition(SystemMediaSource.starts == starts && SystemMediaSource.stops == stops,
                         "Web artwork changes cannot restart the source while Scene keeps demand")
            precondition(received.allSatisfy { $0.sourceID != nil || $0.media.current == nil })
            provider.unsubscribe(first)
        case "status-only":
            var status: [SystemMediaSnapshot] = []
            SceneMediaSourcePreference.isEnabled = false
            provider.subscribe(first, needsMedia: false) { status.append($0) }
            precondition(status.count == 1 && !status.last!.enabled)
            precondition(SystemMediaSource.starts == 0 && control.counts().0 == 0)
            provider.unsubscribe(first)
            SceneMediaSourcePreference.isEnabled = true
            provider.subscribe(first, needsMedia: false) { status.append($0) }
            precondition(status.count == 2 && status.last!.enabled,
                         "late status-only demand must read changed preference")
            precondition(SystemMediaSource.starts == 0)
            provider.subscribe(second) { _ in }
            precondition(SystemMediaSource.starts == 1)
            provider.unsubscribe(second)
            precondition(SystemMediaSource.latest?.callback == nil)
            precondition(status.last!.media.current == nil)
            provider.unsubscribe(first)
        case "publication":
            var received: [SystemMediaSnapshot] = []
            provider.subscribe(first) { received.append($0) }
            let source = SystemMediaSource.latest!
            func track(_ identity: String) {
                source.deliver(.snapshot(.init(source: "other", identity: identity, title: identity,
                    artworkChanged: true, artworkData: nil)))
            }
            track("A")
            let a = received.last!
            provider.subscribe(second) { snapshot in
                precondition(snapshot == provider.currentSnapshot)
            }
            precondition(SystemMediaSource.starts == 1)
            track("B"); track("A")
            let again = received.last!
            precondition(again.sessionGeneration > a.sessionGeneration && again.revision > a.revision)
            precondition(again.media.properties?.title == "A")
            precondition(try! JSONDecoder().decode(SystemMediaSnapshot.self,
                from: JSONEncoder().encode(again)) == again)
            source.deliver(.noSession)
            precondition(received.last!.sourceID == nil && received.last!.media.properties?.title == "")
            provider.unsubscribe(first); provider.unsubscribe(second)
        case "web-artwork":
            let image = NSImage(size: NSSize(width: 900, height: 600))
            image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 900, height: 600).fill(); image.unlockFocus()
            let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            let url = SystemMediaWebArtwork.dataURL(from: data)!
            precondition(url.hasPrefix("data:image/png;base64,"))
            let png = Data(base64Encoded: String(url.dropFirst("data:image/png;base64,".count)))!
            let bitmap = NSBitmapImageRep(data: png)!
            precondition(bitmap.pixelsWide == 512 && bitmap.pixelsHigh <= 512)
            precondition(png.count <= 1_024 * 1_024)
            precondition(SystemMediaWebArtwork.dataURL(from: Data()) == nil)
            precondition(SystemMediaWebArtwork.dataURL(from: Data(repeating: 0, count: 16*1_024*1_024+1)) == nil)
            let before = inbox.latest()
            var invalid = before; invalid.current = Data()
            precondition(!inbox.replaceSystemSnapshot(invalid) && inbox.latest() == before)
            precondition(inbox.publishMediaProperties(title: "A", artist: "A"))
            let firstGeneration = inbox.latest().propertiesGeneration
            precondition(inbox.replaceSystemSnapshot(.empty))
            precondition(inbox.latest().properties == nil && inbox.latest().propertiesGeneration > firstGeneration)
        case "lifecycle":
            provider.subscribe(first) { _ in }
            wait { inbox.latest().properties?.title == "Track A" }
            provider.subscribe(second) { _ in }
            precondition(control.counts().0 == 1)
            precondition(inbox.latest().primaryColor == testPalette(1).primaryColor)
            precondition(inbox.latest().properties?.albumArtist == "Album Artist")
            control.update {
                $0.result = .snapshot(.init(identity: "A", title: "Track A", albumArtist: ""))
            }
            wait { inbox.latest().properties?.albumArtist == "" }
            precondition(inbox.latest().properties?.artist == "Artist",
                         "missing album artist must preserve the independently supplied artist")
            provider.unsubscribe(first)
            precondition(inbox.latest().properties?.title == "Track A")
            provider.unsubscribe(second)
            let empty = inbox.latest()
            precondition(empty.current == nil && empty.properties?.title == "" && empty.properties?.albumArtist == "" && empty.playbackState == 0)
            precondition(empty.timeline?.position == 0 && empty.timeline?.duration == 0)
            let count = control.counts().0
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
            precondition(control.counts().0 == count, "last release must stop polling")
        case "stale":
            let held = DispatchSemaphore(value: 0)
            control.update { $0.blocker = held }
            provider.subscribe(first) { _ in }
            wait { control.counts().2 }
            provider.unsubscribe(first)
            control.update { $0.result = .snapshot(.init(identity: "B", title: "Track B")); $0.blocker = nil }
            provider.subscribe(second) { _ in }
            held.signal()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            precondition(inbox.latest().properties == nil, "retired request leaked into new demand")
            wait { inbox.latest().properties?.title == "Track B" }
            provider.unsubscribe(second)
        case "permission":
            control.update { $0.authorization = .denied }
            provider.subscribe(first) { _ in }
            wait { control.counts().1 == 1 }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
            precondition(control.counts().0 == 0 && control.counts().1 == 1 && control.counts().3 == 0)
            precondition(SystemMediaSource.starts == 1,
                         "denied latch must not respawn the system transport per poll")
            SceneMediaSourcePreference.isEnabled = false
            DistributedNotificationCenter.default().postNotificationName(SceneMediaSourcePreference.changed,
                object: nil, userInfo: nil, deliverImmediately: true)
            wait { SystemMediaSource.latest?.callback == nil }
            control.update { $0.authorization = .authorized }
            SceneMediaSourcePreference.isEnabled = true
            DistributedNotificationCenter.default().postNotificationName(SceneMediaSourcePreference.changed,
                object: nil, userInfo: nil, deliverImmediately: true)
            wait { inbox.latest().properties?.title == "Track A" }
            NSRunningApplication.pid = nil
            wait { inbox.latest().properties?.title == "" }
            provider.unsubscribe(first)
        case "consent", "consent-denied", "consent-unresolved", "consent-unavailable", "consent-deferred", "consent-stale", "consent-disabled", "consent-disable-pending":
            control.update {
                $0.authorization = .consentRequired
                if name == "consent-denied" { $0.requestResult = .denied }
                if name == "consent-unresolved" { $0.requestResult = .consentRequired }
                if name == "consent-unavailable" { $0.requestResult = .unavailable(.helperUnavailable) }
            }
            if name == "consent-disabled" {
                SceneMediaSourcePreference.isEnabled = false
                provider.subscribe(first) { _ in }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                precondition(control.counts().1 == 0 && control.counts().3 == 0)
                precondition(SystemMediaSource.starts == 0)
                provider.unsubscribe(first)
                break
            }
            let held = DispatchSemaphore(value: 0)
            if name == "consent-stale" || name == "consent-disable-pending" {
                control.update { $0.requestBlocker = held }
            }
            if name == "consent-deferred" { NSRunningApplication.pid = nil }
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
            source.deliver(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Track A",
                artworkChanged: true, artworkData: Data([9]))))
            if name == "consent-deferred" {
                precondition(control.counts().1 == 0 && control.counts().3 == 0,
                             "not-running Music must not incur a probe or prompt")
                NSRunningApplication.pid = 42
            }
            wait { control.counts().3 == 1 }
            if name == "consent-stale" || name == "consent-disable-pending" {
                // Consent completes after demand is retired: do not even start
                // a read with the newly granted permission, or publish its data.
                if name == "consent-disable-pending" {
                    SceneMediaSourcePreference.isEnabled = false
                    DistributedNotificationCenter.default().postNotificationName(SceneMediaSourcePreference.changed,
                        object: nil, userInfo: nil, deliverImmediately: true)
                    wait { source.callback == nil }
                } else { provider.unsubscribe(first) }
                held.signal()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                precondition(control.counts().0 == 0)
                precondition(inbox.latest().properties?.title == "" && inbox.latest().current == nil)
                provider.unsubscribe(first)
                break
            }
            if name == "consent" || name == "consent-deferred" {
                wait { inbox.latest().properties?.albumArtist == "Album Artist" }
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
            precondition(control.counts().3 == 1, "one demand repeatedly prompted for consent")
            if name == "consent-denied" || name == "consent-unresolved" || name == "consent-unavailable" {
                precondition(control.counts().0 == 0, "ungranted consent allowed public reads")
                precondition(control.counts().1 == 1, "failed consent kept probing every tick")
                precondition(inbox.latest().properties?.title == "Track A" && inbox.latest().current == Data([9]),
                             "permission failure cleared the independently valid system session")
            }
            provider.unsubscribe(first)
        case "preflight-retire", "preflight-disable", "preflight-disable-before-notification", "preflight-selection",
             "authorized-preflight-retire", "authorized-preflight-disable", "authorized-preflight-selection":
            let held = DispatchSemaphore(value: 0)
            control.update {
                $0.authorization = name.hasPrefix("authorized-") ? .authorized : .consentRequired
                $0.preflightBlocker = held
            }
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
            source.deliver(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Track A",
                artworkChanged: true, artworkData: Data([9]))))
            wait { control.counts().1 == 1 }
            let operation = name.replacingOccurrences(of: "authorized-", with: "")
            switch operation {
            case "preflight-retire": provider.unsubscribe(first)
            case "preflight-disable", "preflight-disable-before-notification":
                SceneMediaSourcePreference.isEnabled = false
                if operation == "preflight-disable" {
                    DistributedNotificationCenter.default().postNotificationName(SceneMediaSourcePreference.changed,
                        object: nil, userInfo: nil, deliverImmediately: true)
                    wait { source.callback == nil }
                }
            default:
                source.deliver(.snapshot(.init(source: "other.player", identity: "B", title: "Selected B",
                    artworkChanged: true, artworkData: Data([8]))))
            }
            held.signal()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            precondition(control.counts().3 == 0, "retired preflight still requested consent")
            precondition(control.counts().0 == 0, "retired preflight started a read")
            if operation == "preflight-selection" {
                precondition(inbox.latest().properties?.title == "Selected B" && inbox.latest().current == Data([8]))
            }
            provider.unsubscribe(first)
        case "system":
            // The system observer owns selection even when Music is running.
            NSRunningApplication.pid = nil
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
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
            wait(6) { SystemMediaSource.starts == 2 }
            oldCallback(.snapshot(.init(source: "Player A", identity: "one", title: "Stale retry", artworkChanged: true, artworkData: red)))
            precondition(inbox.latest().properties?.title == "", "retired transport published after retry")
            source.deliver(.snapshot(.init(source: "Player B", identity: "one", title: "Recovered", artworkChanged: true, artworkData: blue)))
            precondition(inbox.latest().properties?.title == "Recovered")
            provider.unsubscribe(first)
            precondition(source.callback == nil)
            provider.subscribe(second) { _ in }
            oldCallback(.snapshot(.init(source: "Player A", identity: "one", title: "Stale", artworkChanged: true, artworkData: red)))
            precondition(inbox.latest().properties?.title == "", "retired source published into replacement")
            source.deliver(.snapshot(.init(source: "Player B", identity: "two", title: "New", artworkChanged: true, artworkData: blue)))
            provider.unsubscribe(second)
            precondition(inbox.latest().current == nil && inbox.latest().properties?.title == "")
        case "selected-other-player":
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
            source.deliver(.snapshot(.init(source: "other.player", identity: "B", title: "Selected B",
                artworkChanged: true, artworkData: Data([9]))))
            let selected = inbox.latest()
            for state in [SystemMusicPlayerSource.State.paused, .stopped, .playing] {
                control.update { $0.result = .snapshot(.init(identity: "A", title: "Old Music", state: state)) }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
                precondition(inbox.latest() == selected, "Music stole selected player")
                precondition(source.callback != nil, "source selection observation stopped")
            }
            precondition(control.counts().0 == 0 && control.counts().1 == 0 && control.counts().3 == 0,
                         "unselected player must not incur public reads or authorization probes")
            provider.unsubscribe(first)
        case "unknown-selection":
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.1))
            precondition(control.counts().0 == 0, "pending selection enabled Music fallback")
            source.deliver(.noSession)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.1))
            source.deliver(.unavailable(.helperUnavailable))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.1))
            precondition(control.counts().0 == 0, "empty or unknown selection enabled Music fallback")
            precondition(source.callback != nil, "temporary unknown stopped the live observer")
            source.deliver(.unavailable(.heartbeatTimeout))
            wait(6) { SystemMediaSource.starts == 2 }
            precondition(control.counts().0 == 0, "transport retry enabled Music fallback")
            provider.unsubscribe(first)
        case "supplement":
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
            let value = SystemMediaSource.Snapshot(source: "com.apple.Music", identity: "system-A", title: "Track A",
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
            provider.unsubscribe(first)
        case "supplement-no-session", "supplement-failure":
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
            source.deliver(.snapshot(.init(source: "com.apple.Music", identity: "system-A", title: "Track A",
                artworkChanged: true, artworkData: Data([9]))))
            wait { inbox.latest().properties?.albumArtist == "Album Artist" }
            control.update { $0.result = name == "supplement-no-session" ? .noSession : .failure("timeout") }
            wait { inbox.latest().properties?.albumArtist == "" }
            precondition(inbox.latest().properties?.title == "Track A" && inbox.latest().current == Data([9]))
            precondition(source.callback != nil && SystemMediaSource.starts == 1)
            provider.unsubscribe(first)
        case "selection-aba", "selection-new-key":
            let held = DispatchSemaphore(value: 0)
            control.update { $0.blocker = held }
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
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
            provider.unsubscribe(first)
        case "disable":
            let held = DispatchSemaphore(value: 0)
            control.update { $0.blocker = held }
            provider.subscribe(first) { _ in }
            let source = SystemMediaSource.latest!
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
            provider.unsubscribe(first)
        case "fallback-invalid":
            provider.subscribe(first) { _ in }
            wait { inbox.latest().properties?.title == "Track A" }
            control.update { $0.result = .snapshot(.init(identity: "bad", title: "Bad", artworkData: Data())) }
            wait { inbox.latest().properties?.title == "" }
            control.update { $0.result = .snapshot(.init(identity: "B", title: "Track B", state: .paused)) }
            wait { inbox.latest().properties?.title == "Track B" }
            precondition(inbox.latest().playbackState == 2)
            control.update { $0.result = .noSession }
            wait { inbox.latest().properties?.title == "" }
            provider.unsubscribe(first)
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

class SystemMediaServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('swiftc'):
            raise unittest.SkipTest('swiftc unavailable')
        evidence = os.environ.get('MWX_SYSTEM_MEDIA_PROVIDER_EVIDENCE')
        if evidence:
            Path(evidence).mkdir(parents=True, exist_ok=True)
        root = Path(tempfile.mkdtemp(prefix='mwx-system-media-provider-', dir=evidence))
        cls.root = root
        if not evidence:
            cls.addClassCleanup(shutil.rmtree, root)
        harness = root / 'Harness.swift'
        harness.write_text(HARNESS)
        cls.before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in [Path(__file__), *SOURCE_PATHS, harness]}
        (root / 'source-identity.json').write_text(json.dumps(cls.before, indent=2))
        cls.binaries = {}
        env = os.environ.copy()
        env['CLANG_MODULE_CACHE_PATH'] = str(root / 'clang-cache')
        for name, flags in CONFIGURATIONS:
            binary = root / ('provider-' + name)
            command = ['swiftc', '-swift-version', '6', '-default-isolation', 'MainActor', *flags,
                '-module-cache-path', str(root / ('swift-cache-' + name)),
                *map(str, SOURCE_PATHS), str(harness), '-o', str(binary)]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
            (root / ('compile-' + name + '.json')).write_text(json.dumps({
                'command': command, 'returncode': result.returncode,
                'stdout': result.stdout, 'stderr': result.stderr}, indent=2))
            if result.returncode:
                raise AssertionError(f'{name} compile failed: {root}\n{result.stderr}')
            cls.binaries[name] = binary

    def check_case(self, name):
        outputs = []
        for configuration, binary in self.binaries.items():
            with self.subTest(configuration=configuration, mode=name):
                result = subprocess.run([str(binary), name], capture_output=True, text=True, timeout=18)
                (self.root / f'{configuration}-{name}.json').write_text(json.dumps({
                    'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}, indent=2))
                outputs.append(result.stdout)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('PASS ' + name, result.stdout)
                if configuration == 'debug' and name in ('publication', 'supplement-failure'):
                    self.assertIn('MWX shared media source:', result.stderr)
        self.assertEqual(len(outputs), len(CONFIGURATIONS))
        self.assertEqual(outputs[0], outputs[1])
        self.assertEqual({path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
                          for path in self.before}, self.before, 'source changed during validation')

    def test_status_only_demand_and_late_preference(self):
        self.check_case('status-only')

    def test_snapshot_fanout_identity_and_codable_round_trip(self):
        self.check_case('publication')

    def test_web_artwork_preparation_and_store_validation(self):
        self.check_case('web-artwork')

    def test_web_artwork_follows_consumers_without_restarting_scene_media(self):
        self.check_case('web-artwork-demand')
        self.check_case('web-artwork-demand-queued')

    def test_paused_music_cannot_steal_selected_other_player(self):
        self.check_case('selected-other-player')

    def test_last_demand_retires_polling_and_clears_all_channels(self):
        self.check_case('lifecycle')

    def test_retired_inflight_response_cannot_publish_into_new_demand(self):
        self.check_case('stale')

    def test_denied_permission_recovers_after_system_grant_and_switch_cycle(self):
        self.check_case('permission')

    def test_first_selected_music_demand_requests_consent_once_then_reads(self):
        self.check_case('consent')

    def test_new_denial_stops_public_reads_without_reprompting(self):
        self.check_case('consent-denied')

    def test_unresolved_consent_is_latched_without_reprompting(self):
        self.check_case('consent-unresolved')

    def test_failed_consent_attempt_waits_for_explicit_retry(self):
        self.check_case('consent-unavailable')

    def test_opted_in_demand_waits_for_music_to_run_before_requesting_consent(self):
        self.check_case('consent-deferred')

    def test_retired_demand_cannot_read_after_late_consent(self):
        self.check_case('consent-stale')

    def test_disabled_demand_cannot_read_after_late_consent(self):
        self.check_case('consent-disable-pending')

    def test_retired_demand_cannot_prompt_after_late_preflight(self):
        self.check_case('preflight-retire')

    def test_disabled_demand_cannot_prompt_after_late_preflight(self):
        self.check_case('preflight-disable')

    def test_disabled_preference_blocks_prompt_before_notification_delivery(self):
        self.check_case('preflight-disable-before-notification')

    def test_new_selected_player_cannot_inherit_a_music_consent_prompt(self):
        self.check_case('preflight-selection')

    def test_retired_demand_cannot_read_after_authorized_preflight(self):
        self.check_case('authorized-preflight-retire')

    def test_disabled_demand_cannot_read_after_authorized_preflight(self):
        self.check_case('authorized-preflight-disable')

    def test_new_selected_player_cannot_inherit_an_authorized_music_read(self):
        self.check_case('authorized-preflight-selection')

    def test_disabled_song_info_cannot_probe_or_request_consent(self):
        self.check_case('consent-disabled')

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
