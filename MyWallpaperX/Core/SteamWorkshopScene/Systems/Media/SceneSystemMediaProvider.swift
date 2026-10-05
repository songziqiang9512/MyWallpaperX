import AppKit
import Foundation

/// One process-local publisher shared by prepared Scene sessions and displays.
/// Platform reads never run on the frame queue or launch another application.
@MainActor
final class SceneSystemMediaProvider {
    static let shared = SceneSystemMediaProvider()

    private let inbox: SceneMediaThumbnailInbox
    private let queue = DispatchQueue(label: "com.mywallpaperx.scene-player-media", qos: .utility)
    private var consumers = Set<UUID>()
    private var timer: Timer?
    private var preferenceObserver: NSObjectProtocol?
    private var selectedSource = SceneMediaSourcePreference.disabled
    private var epoch: UInt64 = 0
    private var inFlight = false
    private var targetPID: pid_t?
    private var authorizationChecked = false
    private var authorized = false
    private var cachedArtworkIdentity: String?
    private var cachedArtworkData: Data?
    private var lastStatus: String?
    private var hasPublished = false
    private let systemSource = SceneSystemMediaSource()
    private var cachedSystemSource: String?
    private var systemRetryDelay: TimeInterval = 2

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
        selectedSource = .disabled
    }

    private func reloadSource() {
        SceneMediaSourcePreference.refresh()
        invalidateSource()
        selectedSource = SceneMediaSourcePreference.current
        timer?.invalidate()
        timer = nil
        guard !consumers.isEmpty, selectedSource != .disabled else { return }
        if selectedSource == .systemNowPlaying {
            startSystemSource()
            return
        }
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
        cachedSystemSource = nil
        systemRetryDelay = 2
        clearPublishedSession()
    }

    private func startSystemSource() {
        epoch &+= 1
        let requestEpoch = epoch
        systemSource.start { [weak self] result in
            guard let self, self.epoch == requestEpoch, !self.consumers.isEmpty,
                  self.selectedSource == .systemNowPlaying else { return }
            self.consumeSystem(result)
        }
    }

    private func retrySystemSource(after failure: SceneSystemMediaSource.Failure) {
        // A live helper can report a temporary unavailable snapshot during a
        // track transition. Only terminal transport failures need a new process.
        guard failure != .helperUnavailable, timer == nil else { return }
        let requestEpoch = epoch
        let delay = systemRetryDelay
        systemRetryDelay = min(30, delay * 2)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.epoch == requestEpoch, !self.consumers.isEmpty,
                      self.selectedSource == .systemNowPlaying else { return }
                self.timer = nil
                self.startSystemSource()
            }
        }
        timer?.tolerance = min(1, delay / 4)
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
        guard !consumers.isEmpty, selectedSource == .appleMusic else { return }
        let pid = Self.runningMusicPID()
        if pid != targetPID {
            invalidateSource()
            targetPID = pid
        }
        guard let pid else { report("not-running"); return }
        guard !inFlight else { return }
        let requestEpoch = epoch
        let checkAuthorization = !authorizationChecked
        guard checkAuthorization || authorized else { return }
        let artworkIdentity = cachedArtworkData == nil ? nil : cachedArtworkIdentity
        let artwork = cachedArtworkData
        inFlight = true
        queue.async { [weak self] in
            let authorization = SceneMusicPlayerSource.silentAuthorization(pid: pid)
            let result: SceneMusicPlayerSource.ReadResult?
            if case .authorized = authorization {
                result = SceneMusicPlayerSource.read(
                    pid: pid, cachedArtworkIdentity: artworkIdentity, cachedArtworkData: artwork
                )
            } else {
                result = nil
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard self.epoch == requestEpoch, !self.consumers.isEmpty,
                      self.targetPID == pid, Self.runningMusicPID() == pid else { return }
                self.authorizationChecked = true
                if case .authorized = authorization {
                    self.authorized = true
                } else {
                    self.authorized = false
                    self.clearPublishedSession()
                    self.report("authorization-\(authorization)")
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
                                  albumTitle: value.album, albumArtist: "", genres: "", contentType: "music"),
                playbackState: value.state.inboxValue,
                timeline: .init(position: value.position, duration: value.duration)
            )
            if accepted {
                hasPublished = true
                cachedArtworkIdentity = value.identity
                cachedArtworkData = value.artworkData
                report("published")
            } else {
                clearPublishedSession()
                report("invalid-session")
            }
        case .noSession:
            clearPublishedSession()
            cachedArtworkIdentity = nil
            cachedArtworkData = nil
            report("no-session")
        case let .failure(failure):
            clearPublishedSession()
            cachedArtworkIdentity = nil
            cachedArtworkData = nil
            report("unavailable-\(failure)")
        }
    }

    private func report(_ status: String) {
        guard lastStatus != status else { return }
        lastStatus = status
        NSLog("MWX Scene media source: source=%@ status=%@", selectedSource.rawValue, status)
    }

    private func consumeSystem(_ result: SceneSystemMediaSource.Result) {
        switch result {
        case let .snapshot(value):
            let sameTrack = cachedSystemSource == value.source && cachedArtworkIdentity == value.identity
            // The cache belongs to this exact selected source and track. The
            // wire decoder also checks identity, but it does not own this data.
            let artwork = value.artworkChanged ? value.artworkData : (sameTrack ? cachedArtworkData : nil)
            let accepted = inbox.publishMediaSession(
                artwork: artwork,
                properties: .init(title: value.title ?? "", artist: value.artist ?? "", subTitle: "",
                                  albumTitle: value.album ?? "", albumArtist: "", genres: "", contentType: ""),
                playbackState: value.playbackState ?? 0,
                timeline: .init(position: value.position ?? 0, duration: value.duration ?? 0)
            )
            if accepted {
                hasPublished = true
                systemRetryDelay = 2
                cachedSystemSource = value.source
                cachedArtworkIdentity = value.identity
                cachedArtworkData = artwork
                report(value.artworkFailure == nil ? "published" : "published-without-artwork")
            } else {
                clearPublishedSession()
                cachedArtworkData = nil
                report("invalid-session")
            }
        case .noSession:
            systemRetryDelay = 2
            clearPublishedSession()
            cachedArtworkIdentity = nil
            cachedArtworkData = nil
            cachedSystemSource = nil
            report("no-session")
        case let .unavailable(failure):
            clearPublishedSession()
            cachedArtworkIdentity = nil
            cachedArtworkData = nil
            cachedSystemSource = nil
            report("unavailable-\(failure)")
            retrySystemSource(after: failure)
        }
    }
}
