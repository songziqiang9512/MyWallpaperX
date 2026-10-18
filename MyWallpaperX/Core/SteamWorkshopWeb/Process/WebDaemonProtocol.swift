import Foundation

nonisolated enum WebDaemonProtocol {
    static let version = 1
    static let flag = "--mwx-web-daemon"
    static let maximumFrameBytes = 8 * 1_024 * 1_024
}

nonisolated struct WebDaemonEnvelope<Payload: Codable>: Codable {
    let version: Int
    let requestID: UUID
    let payload: Payload

    init(requestID: UUID, payload: Payload) {
        version = WebDaemonProtocol.version
        self.requestID = requestID
        self.payload = payload
    }
}

/// Ownership tokens stay in the parent; only immutable execution input crosses IPC.
nonisolated struct WebDaemonLaunch: Codable {
    let entryURL: URL
    let rootURL: URL
    let propertiesJSON: String?
    let source: WallpaperEngine.WebWallpaperLaunchSource
    let recordID: String?
    let language: String
    let profile: WallpaperEngine.WebRuntimeProfile
    let multiDisplayEnabled: Bool
    let allowedNetworkHosts: Set<String>
    let state: WallpaperEngine.WebWallpaperRuntimeState

    init(_ request: WallpaperEngine.WebWallpaperLaunchRequest,
         state: WallpaperEngine.WebWallpaperRuntimeState, hosts: Set<String>) {
        entryURL = request.entryURL; rootURL = request.rootURL
        propertiesJSON = request.propertiesJSON; source = request.source
        recordID = request.recordID; language = request.language
        profile = request.runtimeProfile; multiDisplayEnabled = request.multiDisplayEnabled
        allowedNetworkHosts = hosts; self.state = state
    }

    func request(id: UUID) -> WallpaperEngine.WebWallpaperLaunchRequest {
        .init(id: id, entryURL: entryURL, rootURL: rootURL,
              propertiesJSON: propertiesJSON, source: source, recordID: recordID,
              language: language, runtimeProfile: profile, multiDisplayEnabled: multiDisplayEnabled)
    }
}

nonisolated enum WebDaemonCommand: Codable {
    case launch(WebDaemonLaunch)
    case runtime(WallpaperEngine.WebWallpaperRuntimeCommand)
    case displays(Bool)
    case media(WebDaemonMediaSnapshot)
#if DEBUG
    case inspect
    case debugMeasureContinuity
    case debugExerciseFailure
#endif
    case captureFrame(UUID)
    case commit(UInt64)
    case activate(WebDaemonActivationRequest)
    case finalize(WebDaemonActivationIdentity)
    case cancelActivation(WebDaemonActivationIdentity)
    case setOutputActivity(Bool, UUID)
    case shutdown

    var isLatestValue: Bool {
        if case .runtime(.pushAudioSpectrum) = self { return true }
        return false
    }
}

nonisolated enum WebDaemonEvent: Codable {
    case hello
#if DEBUG
    case observation(WebDaemonHostObservation)
    case debugNavigationChecks([String: Bool])
    case debugContinuityStarted
    case debugContinuity([String: Double])
#endif
    case host(WallpaperEngine.WebWallpaperHostEvent)
    case capturedFrame(UUID, Data?)
    case prepared(UInt64)
    case committed(UInt64)
    case preparationCohort(WebDaemonPreparedCohort)
    case activationConfirmed(WebDaemonActivationIdentity, [PlaybackSurfaceVisibility.Evidence])
    case activationDeferred(WebDaemonActivationIdentity, String)
    case activationFailed(WebDaemonActivationIdentity, String)
    case activationCancelled(WebDaemonActivationIdentity)
    case outputActivityChanged(UUID, Bool)
    case mediaDemand(Bool?)
    case mediaReplayRequested
    case usage([UUID])
#if DEBUG
    case diagnostics([WebDaemonDiagnostic])
#endif
    case error(String)
}

#if DEBUG
nonisolated struct WebDaemonDiagnostic: Codable {
    let type: String
    let severity: String
    let message: String
    let screenID: UInt32?
    let url: String?
}
#endif

nonisolated struct WebDaemonMediaArtworkKey: Codable, Equatable {
    let epoch: UInt64
    let source: String?
    let session: String?
    let sessionGeneration: UInt64
    let artworkGeneration: UInt64
    let enabled: Bool
    let hasThumbnail: Bool

    init(_ snapshot: SystemMediaSnapshot) {
        epoch = snapshot.epoch; source = snapshot.sourceID; session = snapshot.sessionID
        sessionGeneration = snapshot.sessionGeneration
        artworkGeneration = snapshot.media.generation
        enabled = snapshot.enabled; hasThumbnail = snapshot.webThumbnail != nil
    }
}

/// Web never receives Scene's up-to-16 MiB original artwork. An ordered metadata
/// delta may reuse only the exact previously delivered artwork identity.
nonisolated struct WebDaemonMediaSnapshot: Codable {
    let artworkKey: WebDaemonMediaArtworkKey
    let retainsArtwork: Bool
    private let snapshot: SystemMediaSnapshot

    init(_ full: SystemMediaSnapshot, previous: WebDaemonMediaArtworkKey?) {
        artworkKey = .init(full)
        retainsArtwork = previous == artworkKey
        var web = full
        web.media.current = nil
        if retainsArtwork { web.webThumbnail = nil }
        snapshot = web
    }

    func resolve(previous: SystemMediaSnapshot?) -> SystemMediaSnapshot? {
        guard retainsArtwork else { return snapshot }
        guard let previous, WebDaemonMediaArtworkKey(previous) == artworkKey else { return nil }
        var complete = snapshot
        complete.webThumbnail = previous.webThumbnail
        return complete
    }
}

#if DEBUG
nonisolated struct WebDaemonHostObservation: Codable {
    let phase: String
    let currentRequest: Int
    let loopbacks: Int
    let monitors: Int
    let observers: Int
    let pointerTimer: Int
    let surfaces: Int
    let watchTimer: Int
    let watchers: Int
}
#endif

nonisolated struct WebDaemonSurfaceIdentity: Codable, Equatable, Sendable {
    let displayID: UInt32
    let surfaceID: UUID
    let navigationGeneration: UInt64
    let windowID: UInt32
}

nonisolated struct WebDaemonPreparedCohort: Codable, Equatable, Sendable {
    let generation: UInt64
    let surfaces: [WebDaemonSurfaceIdentity]
}

nonisolated struct WebDaemonActivationIdentity: Codable, Equatable, Sendable {
    let generation: UInt64
    let activationID: UUID
}

nonisolated struct WebDaemonActivationRequest: Codable, Equatable, Sendable {
    let identity: WebDaemonActivationIdentity
    let surfaces: [WebDaemonSurfaceIdentity]
}
