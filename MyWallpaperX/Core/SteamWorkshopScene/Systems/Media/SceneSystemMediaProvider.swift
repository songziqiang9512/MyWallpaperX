import AppKit
import Foundation

/// One process-local publisher shared by prepared Scene sessions and displays.
/// Platform reads never run on the frame queue or launch another application.
@MainActor
final class SceneSystemMediaProvider {
    static let shared = SceneSystemMediaProvider()

    /// The concrete transport engaged for an enabled preference. Apple Music
    /// serves while its target runs and is authorized; the system observer
    /// covers every other moment (and player) while its helper ships.
    private enum ActiveSource {
        case none
        case appleMusic
        case system
    }

    private let inbox: SceneMediaThumbnailInbox
    private let queue = DispatchQueue(label: "com.mywallpaperx.scene-player-media", qos: .utility)
    private var consumers = Set<UUID>()
    private var timer: Timer?
    private var preferenceObserver: NSObjectProtocol?
    private var activeSource = ActiveSource.none
    private var epoch: UInt64 = 0
    private var inFlight = false
    private var targetPID: pid_t?
    private var authorizationChecked = false
    private var authorized = false
    private var cachedArtworkIdentity: String?
    private var cachedArtworkData: Data?
    private var cachedArtworkPalette: SceneMediaArtworkPalette?
    private var lastStatus: String?
    private var hasPublished = false
    private let systemSource = SceneSystemMediaSource()
    private var cachedSystemSource: String?
    private var systemRetryDelay: TimeInterval = 2
    private var systemRestartDeadline: Date?

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
        activeSource = .none
    }

    private func reloadSource() {
        SceneMediaSourcePreference.refresh()
        invalidateSource()
        activeSource = .none
        timer?.invalidate()
        timer = nil
        guard !consumers.isEmpty, SceneMediaSourcePreference.isEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.25
        poll()
    }

    private func invalidateSource() {
        epoch &+= 1
        systemSource.stop()
        targetPID = nil
        authorizationChecked = false
        authorized = false
        cachedArtworkIdentity = nil
        cachedArtworkData = nil
        cachedArtworkPalette = nil
        cachedSystemSource = nil
        systemRetryDelay = 2
        systemRestartDeadline = nil
        clearPublishedSession()
    }

    private func startSystemSource() {
        epoch &+= 1
        let requestEpoch = epoch
        systemSource.start { [weak self] result in
            guard let self, self.epoch == requestEpoch, !self.consumers.isEmpty,
                  self.activeSource == .system else { return }
            self.consumeSystem(result)
        }
    }

    private func scheduleSystemRestart(after failure: SceneSystemMediaSource.Failure) {
        // A live helper reports temporary unavailable snapshots during track
        // transitions and a missing helper library cannot come back mid-run;
        // only a transport that plausibly returns is retried. The next poll
        // consumes the deadline, so restarts stay on the low polling cadence
        // with a 2 to 30 second capped backoff.
        guard failure != .helperUnavailable, failure != .missingResource else { return }
        systemRestartDeadline = Date().addingTimeInterval(systemRetryDelay)
        systemRetryDelay = min(30, systemRetryDelay * 2)
    }

    /// Apple Music cannot serve the session right now (target not running or
    /// not authorized); the system observer takes over while enabled. The
    /// Apple authorization latch survives this transition so a denied read
    /// does not restart its authorization check on every poll.
    private func engageSystemFallback() {
        if activeSource == .system {
            if let deadline = systemRestartDeadline, Date() >= deadline {
                systemRestartDeadline = nil
                startSystemSource()
            }
            return
        }
        epoch &+= 1
        cachedSystemSource = nil
        cachedArtworkIdentity = nil
        cachedArtworkData = nil
        cachedArtworkPalette = nil
        systemRestartDeadline = nil
        clearPublishedSession()
        activeSource = .system
        startSystemSource()
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
        let pid = Self.runningMusicPID()
        if pid != targetPID {
            // The Apple target changed or vanished. Retire Apple-side state
            // only: an engaged system transport and its published session
            // are not the Apple path's to tear down, and its live callbacks
            // stay fenced by the untouched epoch.
            if activeSource != .system {
                epoch &+= 1
                clearPublishedSession()
                cachedArtworkIdentity = nil
                cachedArtworkData = nil
                cachedArtworkPalette = nil
            }
            targetPID = pid
            authorizationChecked = false
            authorized = false
        }
        guard let pid else { engageSystemFallback(); return }
        guard !inFlight else { return }
        let checkAuthorization = !authorizationChecked
        guard checkAuthorization || authorized else { engageSystemFallback(); return }
        let artworkIdentity = cachedArtworkData == nil ? nil : cachedArtworkIdentity
        let artwork = cachedArtworkData
        let artworkPalette = cachedArtworkPalette
        let requestEpoch = epoch
        inFlight = true
        queue.async { [weak self] in
            let authorization = SceneMusicPlayerSource.silentAuthorization(pid: pid)
            let result: SceneMusicPlayerSource.ReadResult?
            if case .authorized = authorization {
                result = SceneMusicPlayerSource.read(
                    pid: pid, cachedArtworkIdentity: artworkIdentity, cachedArtworkData: artwork,
                    cachedArtworkPalette: artworkPalette
                )
            } else {
                result = nil
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard self.epoch == requestEpoch, !self.consumers.isEmpty,
                      self.targetPID == pid, Self.runningMusicPID() == pid else { return }
                switch authorization {
                case .authorized:
                    if self.activeSource != .appleMusic {
                        // A confirmed Apple session takes over: stop the
                        // system transport, retire its publication and fence
                        // its callbacks before Apple publishes.
                        self.invalidateSource()
                        self.activeSource = .appleMusic
                        self.targetPID = pid
                        self.authorizationChecked = true
                        self.authorized = true
                    }
                case .denied, .consentRequired:
                    self.authorizationChecked = true
                    self.authorized = false
                    if self.activeSource != .system { self.clearPublishedSession() }
                    self.report("authorization-\(authorization)")
                    self.engageSystemFallback()
                    return
                case .unavailable:
                    // Transient (for example the target still launching): do
                    // not latch, so the next poll re-probes while the system
                    // observer covers the session.
                    if self.activeSource != .system { self.clearPublishedSession() }
                    self.report("authorization-\(authorization)")
                    self.engageSystemFallback()
                    return
                }
                guard let result else { return }
                self.consume(result)
            }
        }
    }

    private func consume(_ result: SceneMusicPlayerSource.ReadResult) {
        switch result {
        case let .snapshot(value):
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
                hasPublished = true
                cachedArtworkIdentity = value.identity
                cachedArtworkData = value.artworkData
                cachedArtworkPalette = value.artworkPalette
                report("published")
            } else {
                clearPublishedSession()
                report("invalid-session")
            }
        case .noSession:
            clearPublishedSession()
            cachedArtworkIdentity = nil
            cachedArtworkData = nil
            cachedArtworkPalette = nil
            report("no-session")
        case let .failure(failure):
            clearPublishedSession()
            cachedArtworkIdentity = nil
            cachedArtworkData = nil
            cachedArtworkPalette = nil
            report("unavailable-\(failure)")
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

    private func consumeSystem(_ result: SceneSystemMediaSource.Result) {
        switch result {
        case let .snapshot(value):
            let sameTrack = cachedSystemSource == value.source && cachedArtworkIdentity == value.identity
            // The cache belongs to this exact selected source and track. The
            // wire decoder also checks identity, but it does not own this data.
            let artwork = value.artworkChanged ? value.artworkData : (sameTrack ? cachedArtworkData : nil)
            let palette = value.artworkChanged ? value.artworkPalette : (sameTrack ? cachedArtworkPalette : nil)
            let accepted = inbox.publishMediaSession(
                artwork: artwork,
                properties: .init(title: value.title ?? "", artist: value.artist ?? "", subTitle: "",
                                  albumTitle: value.album ?? "", albumArtist: "", genres: "", contentType: ""),
                playbackState: value.playbackState ?? 0,
                timeline: .init(position: value.position ?? 0, duration: value.duration ?? 0),
                primaryColor: palette?.primaryColor, secondaryColor: palette?.secondaryColor,
                tertiaryColor: palette?.tertiaryColor, textColor: palette?.textColor,
                highContrastColor: palette?.highContrastColor
            )
            if accepted {
                hasPublished = true
                systemRetryDelay = 2
                cachedSystemSource = value.source
                cachedArtworkIdentity = value.identity
                cachedArtworkData = artwork
                cachedArtworkPalette = palette
                report(value.artworkFailure == nil ? "published" : "published-without-artwork")
            } else {
                clearPublishedSession()
                cachedArtworkData = nil
                cachedArtworkPalette = nil
                report("invalid-session")
            }
        case .noSession:
            systemRetryDelay = 2
            clearPublishedSession()
            cachedArtworkIdentity = nil
            cachedArtworkData = nil
            cachedArtworkPalette = nil
            cachedSystemSource = nil
            report("no-session")
        case let .unavailable(failure):
            clearPublishedSession()
            cachedArtworkIdentity = nil
            cachedArtworkData = nil
            cachedArtworkPalette = nil
            cachedSystemSource = nil
            report("unavailable-\(failure)")
            scheduleSystemRestart(after: failure)
        }
    }
}
