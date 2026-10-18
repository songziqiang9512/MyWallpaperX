import AppKit
import Foundation

/// The main App is the single system-song producer for Scene and Web.
/// Platform reads never run on the frame queue or launch another application.
@MainActor
final class SystemMediaService {
    static let shared = SystemMediaService()

    private enum ActiveSource { case none, appleMusic, system }
    private enum MusicSelection: Equatable {
        case fallback
        case selected(String)
    }

    private let inbox: SystemMediaSnapshotStore
    private let queue = DispatchQueue(label: "com.mywallpaperx.scene-player-media", qos: .utility)
    private struct Subscription {
        let lease = UUID()
        let needsMedia: Bool
        let receive: (SystemMediaSnapshot) -> Void
    }
    private var subscriptions: [UUID: Subscription] = [:]
    private var consumers: Set<UUID> {
        Set(subscriptions.compactMap { $0.value.needsMedia ? $0.key : nil })
    }
    private(set) var currentSnapshot: SystemMediaSnapshot
    private var webThumbnail: String?
    private var preparedArtworkGeneration: UInt64?
    private var sessionGeneration: UInt64 = 0
    private var timer: Timer?
    private var preferenceObserver: NSObjectProtocol?
    private var activeSource = ActiveSource.none
    private var epoch: UInt64 = 0
    private var selectionGeneration: UInt64 = 0
    private var inFlight = false
    private var targetPID: pid_t?
    private var authorizationChecked = false
    private var authorized = false
    private var musicSnapshot: SystemMusicPlayerSource.Snapshot?
    private var lastStatus: String?
    private var hasPublished = false
    private let systemSource = SystemMediaSource()
    private var systemSession: SystemMediaSource.Snapshot?
    private var systemArtworkData: Data?
    private var systemArtworkPalette: SystemMediaArtworkPalette?
    private var usesMusicFallback = false
    private var systemRetryDelay: TimeInterval = 2
    private var systemRestartDeadline: Date?

    private var musicSelection: MusicSelection? {
        if usesMusicFallback { return .fallback }
        guard let systemSession, systemSession.source == "com.apple.Music" else { return nil }
        return .selected(systemSession.identity)
    }

    init(inbox: SystemMediaSnapshotStore = SystemMediaSnapshotStore()) {
        self.inbox = inbox
        currentSnapshot = .empty
        currentSnapshot.enabled = SceneMediaSourcePreference.isEnabled
        currentSnapshot.media = inbox.latest()
    }

    func subscribe(_ consumer: UUID, needsMedia: Bool = true,
                   receive: @escaping (SystemMediaSnapshot) -> Void) {
        let hadDemand = !consumers.isEmpty
        let firstSubscription = subscriptions.isEmpty
        subscriptions[consumer] = Subscription(needsMedia: needsMedia, receive: receive)
        if preferenceObserver == nil {
            preferenceObserver = DistributedNotificationCenter.default().addObserver(
                forName: SceneMediaSourcePreference.changed, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadSource() }
            }
        }
        if firstSubscription || hadDemand != !consumers.isEmpty {
            reloadSource()
        } else {
            // Status-only and late listeners do not restart a live provider.
            receive(currentSnapshot)
        }
    }

    func unsubscribe(_ consumer: UUID) {
        let hadDemand = !consumers.isEmpty
        guard subscriptions.removeValue(forKey: consumer) != nil else { return }
        if hadDemand != !consumers.isEmpty { reloadSource() }
        guard subscriptions.isEmpty else { return }
        if let preferenceObserver {
            DistributedNotificationCenter.default().removeObserver(preferenceObserver)
        }
        preferenceObserver = nil
    }

    private func reloadSource() {
        SceneMediaSourcePreference.refresh()
        invalidateSource()
        timer?.invalidate()
        timer = nil
        publishSnapshot(force: true)
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
        preparedArtworkGeneration = nil
        webThumbnail = nil
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

    private func scheduleSystemRestart(after failure: SystemMediaSource.Failure) {
        // helperUnavailable is a live observer's temporary unknown selection;
        // missingResource cannot recover mid-run. Only retired transports retry.
        guard failure != .helperUnavailable, failure != .missingResource else { return }
        systemRestartDeadline = Date().addingTimeInterval(systemRetryDelay)
        systemRetryDelay = min(30, systemRetryDelay * 2)
    }

    private func clearPublishedSession() {
        guard hasPublished else { return }
        if inbox.clearMediaSession() {
            hasPublished = false
            publishSnapshot()
        }
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
        let isCurrent: @MainActor @Sendable () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.epoch == requestEpoch && !self.consumers.isEmpty
                && SceneMediaSourcePreference.isEnabled && self.targetPID == pid
                && Self.runningMusicPID() == pid && self.musicSelection == selection
                && self.selectionGeneration == requestSelectionGeneration
        }
        let finish: @MainActor @Sendable (
            SystemMusicPlayerSource.AuthorizationStatus, SystemMusicPlayerSource.ReadResult?, Bool
        ) -> Void = { [weak self] authorization, result, requestedConsent in
            guard let self else { return }
            self.inFlight = false
            guard isCurrent() else { return }
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
                // A failed consent attempt must not reopen a system prompt
                // on every timer tick. A preference/PID change can retry.
                if requestedConsent {
                    self.authorizationChecked = true
                    self.authorized = false
                }
                self.clearMusicSupplement()
                self.report("authorization-\(authorization)")
                return
            }
            // A system prompt can outlive the scene or user preference.
            // Re-enter through current-demand guards before starting a read.
            guard let result else { self.poll(); return }
            self.consume(result)
        }
        queue.async { [weak self] in
            let authorization = SystemMusicPlayerSource.silentAuthorization(pid: pid)
            DispatchQueue.main.async {
                // Preflight can block while demand, player or selection changes.
                // Admit both consent and reads on the current request only.
                guard let self, isCurrent() else {
                    finish(authorization, nil, false)
                    return
                }
                switch authorization {
                case .consentRequired:
                    self.queue.async {
                        let consent = SystemMusicPlayerSource.requestAuthorization(pid: pid)
                        DispatchQueue.main.async { finish(consent, nil, true) }
                    }
                case .authorized:
                    self.queue.async {
                        let result = SystemMusicPlayerSource.read(
                            pid: pid, cachedArtworkIdentity: cached?.artworkData == nil ? nil : cached?.identity,
                            cachedArtworkData: cached?.artworkData, cachedArtworkPalette: cached?.artworkPalette
                        )
                        DispatchQueue.main.async { finish(authorization, result, false) }
                    }
                default: finish(authorization, nil, false)
                }
            }
        }
    }

    private func clearMusicSupplement() {
        musicSnapshot = nil
        if let systemSession { publishSystemSession(systemSession) }
        else { clearPublishedSession() }
    }

    private func consume(_ result: SystemMusicPlayerSource.ReadResult) {
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
                publishSnapshot()
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
#if DEBUG
        NSLog("MWX shared media source: source=%@ status=%@", source, status)
#endif
    }

    private func publishSystemSession(_ value: SystemMediaSource.Snapshot) {
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
            publishSnapshot()
            report(value.artworkFailure == nil ? "published" : "published-without-artwork")
        } else {
            clearPublishedSession()
            report("invalid-session")
        }
    }

    private func consumeSystem(_ result: SystemMediaSource.Result) {
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

    private func publishSnapshot(force: Bool = false) {
        let media = inbox.latest()
        let sourceID: String?
        let sessionID: String?
        if hasPublished, activeSource == .system {
            sourceID = systemSession?.source
            sessionID = systemSession?.identity
        } else if hasPublished, activeSource == .appleMusic {
            sourceID = "com.apple.Music"
            sessionID = musicSnapshot?.identity
        } else {
            sourceID = nil
            sessionID = nil
        }
        if currentSnapshot.sourceID != sourceID || currentSnapshot.sessionID != sessionID {
            sessionGeneration &+= 1
        }
        if preparedArtworkGeneration != media.generation {
            preparedArtworkGeneration = media.generation
            webThumbnail = nil
            if let artwork = media.current {
                let requestEpoch = epoch
                let generation = media.generation
                queue.async { [weak self] in
                    let thumbnail = SystemMediaWebArtwork.dataURL(from: artwork)
                    DispatchQueue.main.async {
                        guard let self, self.epoch == requestEpoch,
                              self.inbox.latest().generation == generation,
                              !self.consumers.isEmpty else { return }
                        self.webThumbnail = thumbnail
                        self.publishSnapshot()
                    }
                }
            }
        }
        var next = SystemMediaSnapshot(
            enabled: SceneMediaSourcePreference.isEnabled, epoch: epoch,
            revision: currentSnapshot.revision, sourceID: sourceID,
            sessionID: sessionID, sessionGeneration: sessionGeneration,
            media: media, webThumbnail: webThumbnail
        )
        guard force || next != currentSnapshot else { return }
        next.revision &+= 1
        currentSnapshot = next
        // A callback may retire or replace another subscription synchronously.
        for (id, subscription) in Array(subscriptions) {
            guard subscriptions[id]?.lease == subscription.lease else { continue }
            subscription.receive(next)
        }
    }
}
