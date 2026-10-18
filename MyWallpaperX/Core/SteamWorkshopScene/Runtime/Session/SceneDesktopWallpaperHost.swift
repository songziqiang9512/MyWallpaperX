import AppKit
import Foundation
import QuartzCore

/// Owns requests and the single visible-session decision. Playback state lives
/// entirely in SceneDesktopWallpaperSession, including candidate and drain roles.
final class SceneDesktopWallpaperHost {
#if DEBUG
    struct DebugSnapshot {
        let surfaceCount: Int
        let windowNumbers: [Int]
        let isPlaybackPaused: Bool
        let isFrameDriverActive: Bool
    }

#endif
    var nextSceneScriptGeneration: UInt64 = 0
    let launchPreparationQueue = DispatchQueue(
        label: "com.mywallpaperx.scene-launch-preparation",
        qos: .userInitiated
    )
    var pendingLaunchCompletion: (@MainActor (Result<SceneRuntimeModel, Error>) -> Void)?
    var launchCancellation: SceneWallpaperLaunchCancellation?
    var nextLaunchRequestGeneration: UInt64 = 0
    var launchState: SceneWallpaperLaunchState?
    let textureDecodeCacheBudget = SceneTextureDecodeCacheBudget(
        maximumBytes: PlaybackPerformanceProfile.current
            .sceneTextureDecodeCacheByteBudget
    )
    var activeSession: SceneDesktopWallpaperSession?
    var candidateSession: SceneDesktopWallpaperSession?
    var retiringSessions: [ObjectIdentifier: SceneDesktopWallpaperSession] = [:]
    var candidateDeadline: DispatchWorkItem?
    var candidateCompletion: ((Result<Void, Error>) -> Void)?
    /// The daemon requests admission after every candidate GPU surface is ready.
    /// Direct DEBUG hosts leave this nil and preserve their local transaction.
    var candidatePreparedHandler: ((UUID) -> Void)?
    var requestResourcesReleasedHandler: ((UUID) -> Void)?
    var candidatePromotion: (requestID: UUID, promote: () -> Void)?
    var unconfirmedPromotion: (requestID: UUID, previous: SceneDesktopWallpaperSession?)?
    var presentationDeadline: DispatchWorkItem?
    var screenTopology: [SceneScreenTopology] = []
    private(set) var performanceProfile: PlaybackPerformanceProfile = .current
    private var playbackPaused = false
#if DEBUG
    private var debugPointerOverride: SceneSurfacePointerInput?
    private var debugDropDynamicValuesFrameIndex: UInt64?
#endif
    var activeRecordID: String? { activeSession?.activeRecordID }
    var isPlaybackActive: Bool { activeSession?.isPlaybackActive == true }

    func applyPerformanceProfile(_ profile: PlaybackPerformanceProfile) {
        performanceProfile = profile
        textureDecodeCacheBudget.updateMaximumBytes(profile.sceneTextureDecodeCacheByteBudget)
        activeSession?.applyPerformanceProfile(profile)
        candidateSession?.applyPerformanceProfile(profile)
    }

    func applyDisplayConfiguration(_ topology: [SceneScreenTopology]) {
        guard topology != screenTopology else { return }
        screenTopology = topology
        if let promotion = unconfirmedPromotion { cancelCandidate(requestID: promotion.requestID) }
        cancelPendingLaunch()
        activeSession?.applyDisplayConfiguration(topology)
    }

    func setPlaybackPaused(_ paused: Bool) {
        playbackPaused = paused
        activeSession?.setPlaybackPaused(paused)
        candidateSession?.setPlaybackPaused(paused)
    }

    func setMasterVolume(_ volume: Double) {
        activeSession?.soundPlaybackRegistry?.setMasterVolume(volume)
        candidateSession?.soundPlaybackRegistry?.setMasterVolume(volume)
        unconfirmedPromotion?.previous?.soundPlaybackRegistry?.setMasterVolume(volume)
    }

    func setMuted(_ muted: Bool) {
        if let activeSession {
            activeSession.soundPlaybackRegistry?.setMuted(muted || !activeSession.isOutputActive)
        }
        // The candidate has no audible output until promotion.
    }

    /// Handoff activity is independent of user/system pause. Keep the frozen
    /// frame visible while revoking audio, input and media subscription.
    func setOutputActive(_ active: Bool, requestID: UUID) -> Bool {
        let sessions = [activeSession, candidateSession, unconfirmedPromotion?.previous].compactMap { $0 }
        guard let session = sessions.first(where: { $0.launchRequestID == requestID }) else { return false }
        session.setOutputActive(active, playbackPaused: playbackPaused)
        reconcileAudioDemand()
        return true
    }

    func outputWindows(requestID: UUID) -> [NSWindow] {
        let sessions = [activeSession, candidateSession, unconfirmedPromotion?.previous].compactMap { $0 }
            + Array(retiringSessions.values)
        return sessions.filter { $0.launchRequestID == requestID }.flatMap {
            Array($0.surfaces.values) + Array($0.retiringSurfaces.values)
        }.map(\.window)
    }

    @discardableResult
    func applyUserPropertyValues(_ values: [String: SceneUserPropertyValue], changedPropertyKeys: Set<String>, recordID: String?) -> Bool {
        // A prepared context freezes authored properties. A live edit of that
        // record restarts preparation from the client's complete latest intent.
        if !changedPropertyKeys.isEmpty, launchState?.isInProgress == true,
           launchState?.recordID == recordID {
            cancelPendingLaunch(recordID: recordID)
            return false
        }
        return sessionForCommittedPropertyUpdate(recordID: recordID)?.applyUserPropertyValues(
            values, changedPropertyKeys: changedPropertyKeys, recordID: recordID) ?? false
    }

    /// Until real presentation is confirmed, the parent still edits the
    /// previous Scene. A same-record edit invalidates the frozen replacement.
    func sessionForCommittedPropertyUpdate(recordID: String?) -> SceneDesktopWallpaperSession? {
        guard let promotion = unconfirmedPromotion, let previous = promotion.previous,
              previous.activeRecordID == recordID else { return activeSession }
        if activeSession?.activeRecordID == recordID {
            cancelCandidate(requestID: promotion.requestID)
            return activeSession
        }
        return previous
    }

    @discardableResult
    func applyUserPropertyValue(_ value: SceneUserPropertyValue, forPropertyKey key: String, recordID: String?) -> Bool {
        applyUserPropertyValues([key: value], changedPropertyKeys: [key], recordID: recordID)
    }

    func applyUserTextureUpdate(
        _ update: ScenePlaybackTextureUpdate,
        resolvedURLs: [String: URL],
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) {
        guard launchState?.isInProgress != true || launchState?.recordID != update.recordID,
              let session = sessionForCommittedPropertyUpdate(recordID: update.recordID),
              session.activeRecordID == update.recordID else {
            completion(.unavailable)
            return
        }
        session.applyUserTextureUpdate(update, resolvedURLs: resolvedURLs, completion: completion)
    }
#if DEBUG
    func refreshPerformanceResourceGauges() {
        // Sample all roles at the daemon's 1 Hz cadence, never per frame.
        let sessions = [activeSession, candidateSession].compactMap { $0 }
            + Array(retiringSessions.values)
        let surfaces = sessions.flatMap { Array($0.surfaces.values) + Array($0.retiringSurfaces.values) }
        let hub = ScenePerformanceCounterHub.shared
        hub.set(.gpuAllocatedBytes, UInt64(clamping: surfaces.first?.metalView.renderer.device.currentAllocatedSize ?? 0))
        hub.set(.renderTargetPoolBytes, surfaces.reduce(0) { $0 + UInt64(clamping: $1.metalView.renderTargetResidentByteCost) })
        let budget = SceneResourceBudget.shared.snapshot
        hub.set(.sceneResidentBytes, UInt64(budget.residentBytes))
        hub.set(.sceneResourceAdmissionRejections, UInt64(budget.rejectionCount))
    }
#endif
    func stop() {
        rollbackUnconfirmedPromotion()
        cancelPendingLaunch()
        if let activeSession {
            self.activeSession = nil
            retire(activeSession)
        }
        reconcileAudioDemand()
    }

    func configure(_ session: SceneDesktopWallpaperSession) {
        session.applyPerformanceProfile(performanceProfile)
        session.screenTopology = screenTopology
        session.setPlaybackPaused(playbackPaused)
#if DEBUG
        session.debugPointerOverride = debugPointerOverride
        session.debugDropDynamicValuesFrameIndex = debugDropDynamicValuesFrameIndex
#endif
        session.onAudioDemandChanged = { [weak self] in self?.reconcileAudioDemand() }
    }
#if DEBUG
    func debugSnapshot() -> DebugSnapshot {
        activeSession?.debugSnapshot() ?? .init(surfaceCount: 0, windowNumbers: [],
            isPlaybackPaused: playbackPaused, isFrameDriverActive: false)
    }
    func requestDebugSnapshot(windowNumber: Int, reason: String, outputDirectory: URL,
                              kind: SceneDebugFrameCapture.RequestClass = .required) -> SceneDebugFrameCapture.Admission {
        guard let activeSession else {
            SceneDebugFrameCapture.reportRejected(reason: reason, stage: "session-lookup")
            return .rejected("session-lookup")
        }
        return activeSession.requestDebugSnapshot(windowNumber: windowNumber, reason: reason, outputDirectory: outputDirectory, kind: kind)
    }
    func debugParticleLoadReportLines() -> [String] { activeSession?.debugParticleLoadReportLines() ?? [] }
    func setDebugPointerOverride(_ input: SceneSurfacePointerInput?) {
        debugPointerOverride = input
        activeSession?.setDebugPointerOverride(input)
    }
    func debugResizeSurfaces(scale: CGFloat) -> Bool { activeSession?.debugResizeSurfaces(scale: scale) ?? false }
    func debugInvalidateResolvedMaterialRuntimes(reason: SceneGraphExecutionResetReason) -> Bool {
        activeSession?.debugInvalidateResolvedMaterialRuntimes(reason: reason) ?? false
    }
    func setDebugDropDynamicValuesFrameIndex(_ frameIndex: UInt64?) -> Bool {
        guard Self.usesDebugEvidenceWindow else { return false }
        debugDropDynamicValuesFrameIndex = frameIndex
        _ = activeSession?.setDebugDropDynamicValuesFrameIndex(frameIndex)
        return true
    }
#endif
    static var usesDebugEvidenceWindow: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-evidence-dir")
#else
        false
#endif
    }

    /// Execution observations are the heavy evidence instrument: they build a
    /// full `SceneGraphExecutionObservation` and SHA-256 graph mapping per
    /// successful effect every frame. They stay strictly opt-in for the debug
    /// evidence window, and a debug performance-only run may additionally
    /// disable them so staged CPU can be measured without the instrument. The
    /// per-stage performance telemetry does not depend on this switch.
    static var usesExecutionObservationCapture: Bool {
#if DEBUG
        usesDebugEvidenceWindow
            && !ProcessInfo.processInfo.arguments.contains(
                "--mwx-debug-scene-no-execution-observations"
            )
#else
        false
#endif
    }

}
