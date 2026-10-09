import AppKit
import Foundation

/// One process-local publisher shared by prepared Scene sessions and displays.
/// Platform reads never run on the frame queue or launch another application.
@MainActor
final class SceneSystemMediaProvider {
    static let shared = SceneSystemMediaProvider()

    private enum ActiveSource { case none, appleMusic, system }
    private enum MusicSelection: Equatable {
        case fallback
        case selected(String)
    }

    private let inbox: SceneMediaThumbnailInbox
    private let queue = DispatchQueue(label: "com.mywallpaperx.scene-player-media", qos: .utility)
    private var consumers = Set<UUID>()
    private var timer: Timer?
    private var preferenceObserver: NSObjectProtocol?
    private var activeSource = ActiveSource.none
    private var epoch: UInt64 = 0
    private var selectionGeneration: UInt64 = 0
    private var inFlight = false
    private var targetPID: pid_t?
    private var authorizationChecked = false
    private var authorized = false
    private var musicSnapshot: SceneMusicPlayerSource.Snapshot?
    private var lastStatus: String?
    private var hasPublished = false
    private let systemSource = SceneSystemMediaSource()
    private var systemSession: SceneSystemMediaSource.Snapshot?
    private var systemArtworkData: Data?
    private var systemArtworkPalette: SceneMediaArtworkPalette?
    private var usesMusicFallback = false
    private var systemRetryDelay: TimeInterval = 2
    private var systemRestartDeadline: Date?

    private var musicSelection: MusicSelection? {
        if usesMusicFallback { return .fallback }
        guard let systemSession, systemSession.source == "com.apple.Music" else { return nil }
        return .selected(systemSession.identity)
    }

    init(inbox: SceneMediaThumbnailInbox = .shared) {
        self.inbox = inbox
    }

    func acquire(_ consumer: UUID) {
        guard consumers.insert(consumer).inserted, consumers.count == 1 else { return }
        preferenceObserver = DistributedNotificationCenter.default().addObserver(
            forName: SceneMediaSourcePreference.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSource() }
        }
        reloadSource()
    }

    func release(_ consumer: UUID) {
        guard consumers.remove(consumer) != nil, consumers.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        if let preferenceObserver {
            DistributedNotificationCenter.default().removeObserver(preferenceObserver)
        }
        preferenceObserver = nil
        invalidateSource()
    }

    private func reloadSource() {
        SceneMediaSourcePreference.refresh()
        invalidateSource()
        timer?.invalidate()
        timer = nil
        guard !consumers.isEmpty, SceneMediaSourcePreference.isEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.25
        startSystemSource()
        poll()
    }

    private func invalidateSource() {
        epoch &+= 1
        systemSource.stop()
        targetPID = nil
        authorizationChecked = false
        authorized = false
        musicSnapshot = nil
        systemSession = nil
        systemArtworkData = nil
        systemArtworkPalette = nil
        usesMusicFallback = false
        systemRetryDelay = 2
        systemRestartDeadline = nil
        clearPublishedSession()
        activeSource = .none
    }

    private func startSystemSource() {
        epoch &+= 1
        let requestEpoch = epoch
        systemSource.start { [weak self] result in
            guard let self, self.epoch == requestEpoch, !self.consumers.isEmpty else { return }
            self.consumeSystem(result)
        }
    }

    private func scheduleSystemRestart(after failure: SceneSystemMediaSource.Failure) {
        // helperUnavailable is a live observer's temporary unknown selection;
        // missingResource cannot recover mid-run. Only retired transports retry.
        guard failure != .helperUnavailable, failure != .missingResource else { return }
        systemRestartDeadline = Date().addingTimeInterval(systemRetryDelay)
        systemRetryDelay = min(30, systemRetryDelay * 2)
    }

    private func clearPublishedSession() {
        guard hasPublished else { return }
        if inbox.clearMediaSession() { hasPublished = false }
    }

    private static func runningMusicPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            .first(where: { !$0.isTerminated })?.processIdentifier
    }

    private func poll() {
        guard !consumers.isEmpty, SceneMediaSourcePreference.isEnabled else { return }
        if let deadline = systemRestartDeadline, Date() >= deadline {
            systemRestartDeadline = nil
            startSystemSource()
        }
        let pid = Self.runningMusicPID()
        if pid != targetPID {
            selectionGeneration &+= 1
            targetPID = pid
            authorizationChecked = false
            authorized = false
            musicSnapshot = nil
            if let systemSession { publishSystemSession(systemSession) }
            else if activeSource == .appleMusic { clearPublishedSession() }
        }
        guard let selection = musicSelection, let pid, !inFlight else { return }
        guard !authorizationChecked || authorized else { return }
        let cached = musicSnapshot
        let requestSelectionGeneration = selectionGeneration
        let requestEpoch = epoch
        inFlight = true
        queue.async { [weak self] in
            let authorization = SceneMusicPlayerSource.silentAuthorization(pid: pid)
            let result: SceneMusicPlayerSource.ReadResult?
            if case .authorized = authorization {
                result = SceneMusicPlayerSource.read(
                    pid: pid, cachedArtworkIdentity: cached?.artworkData == nil ? nil : cached?.identity,
                    cachedArtworkData: cached?.artworkData, cachedArtworkPalette: cached?.artworkPalette
                )
            } else {
                result = nil
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard self.epoch == requestEpoch, !self.consumers.isEmpty,
                      self.targetPID == pid, Self.runningMusicPID() == pid,
                      self.musicSelection == selection,
                      self.selectionGeneration == requestSelectionGeneration else { return }
                switch authorization {
                case .authorized:
                    self.authorizationChecked = true
                    self.authorized = true
                case .denied, .consentRequired:
                    self.authorizationChecked = true
                    self.authorized = false
                    self.clearMusicSupplement()
                    self.report("authorization-\(authorization)")
                    return
                case .unavailable:
                    self.clearMusicSupplement()
                    self.report("authorization-\(authorization)")
                    return
                }
                guard let result else { return }
                self.consume(result)
            }
        }
    }

    private func clearMusicSupplement() {
        musicSnapshot = nil
        if let systemSession { publishSystemSession(systemSession) }
        else { clearPublishedSession() }
    }

    private func consume(_ result: SceneMusicPlayerSource.ReadResult) {
        switch result {
        case let .snapshot(value):
            musicSnapshot = value
            if let systemSession {
                publishSystemSession(systemSession)
                return
            }
            let accepted = inbox.publishMediaSession(
                artwork: value.artworkData,
                properties: .init(title: value.title, artist: value.artist, subTitle: "",
                                  albumTitle: value.album, albumArtist: value.albumArtist, genres: "", contentType: "music"),
                playbackState: value.state.inboxValue,
                timeline: .init(position: value.position, duration: value.duration),
                primaryColor: value.artworkPalette?.primaryColor, secondaryColor: value.artworkPalette?.secondaryColor,
                tertiaryColor: value.artworkPalette?.tertiaryColor, textColor: value.artworkPalette?.textColor,
                highContrastColor: value.artworkPalette?.highContrastColor
            )
            if accepted {
                activeSource = .appleMusic
                hasPublished = true
                report("published")
            } else {
                clearMusicSupplement()
                report("apple-invalid-session")
            }
        case .noSession:
            clearMusicSupplement()
            report("apple-no-session")
        case let .failure(failure):
            clearMusicSupplement()
            report("apple-unavailable-\(failure)")
        }
    }

    private func report(_ status: String) {
        guard lastStatus != status else { return }
        lastStatus = status
        let source: String
        switch activeSource {
        case .appleMusic: source = "apple-music"
        case .system: source = "system"
        case .none: source = "none"
        }
        NSLog("MWX Scene media source: source=%@ status=%@", source, status)
    }

    private func publishSystemSession(_ value: SceneSystemMediaSource.Snapshot) {
        // The two APIs have unrelated opaque track IDs. Supplement metadata only
        // when its nonempty title, artist and album agree; never substitute the
        // system's track, transport state or cover using this comparison.
        let supplement = musicSnapshot.flatMap { music in
            value.source == "com.apple.Music" && !music.title.isEmpty
                && value.title == music.title && value.artist == music.artist && value.album == music.album ? music : nil
        }
        let accepted = inbox.publishMediaSession(
            artwork: systemArtworkData,
            properties: .init(title: value.title ?? "", artist: value.artist ?? "", subTitle: "",
                              albumTitle: value.album ?? "", albumArtist: supplement?.albumArtist ?? "",
                              genres: "", contentType: supplement == nil ? "" : "music"),
            playbackState: value.playbackState ?? 0,
            timeline: .init(position: value.position ?? 0, duration: value.duration ?? 0),
            primaryColor: systemArtworkPalette?.primaryColor, secondaryColor: systemArtworkPalette?.secondaryColor,
            tertiaryColor: systemArtworkPalette?.tertiaryColor, textColor: systemArtworkPalette?.textColor,
            highContrastColor: systemArtworkPalette?.highContrastColor
        )
        activeSource = .system
        if accepted {
            hasPublished = true
            report(value.artworkFailure == nil ? "published" : "published-without-artwork")
        } else {
            clearPublishedSession()
            report("invalid-session")
        }
    }

    private func consumeSystem(_ result: SceneSystemMediaSource.Result) {
        let oldSelection = musicSelection
        switch result {
        case let .snapshot(value):
            let sameTrack = systemSession?.source == value.source && systemSession?.identity == value.identity
            if !sameTrack { musicSnapshot = nil }
            systemArtworkData = value.artworkChanged ? value.artworkData : (sameTrack ? systemArtworkData : nil)
            systemArtworkPalette = value.artworkChanged ? value.artworkPalette : (sameTrack ? systemArtworkPalette : nil)
            systemSession = value
            usesMusicFallback = false
            systemRetryDelay = 2
            publishSystemSession(value)
        case .noSession, .unavailable:
            systemSession = nil
            systemArtworkData = nil
            systemArtworkPalette = nil
            musicSnapshot = nil
            clearPublishedSession()
            activeSource = .system
            usesMusicFallback = false
            if case let .unavailable(failure) = result {
                // An unknown system selection is not permission to show an old
                // Music track. Public fallback is only for builds without the
                // system backend, not transient query or transport failures.
                usesMusicFallback = failure == .missingResource
                report("unavailable-\(failure)")
                scheduleSystemRestart(after: failure)
            } else {
                systemRetryDelay = 2
                report("no-session")
            }
        }
        if musicSelection != oldSelection {
            selectionGeneration &+= 1
            poll()
        }
    }
}
