import AppKit
import Darwin
import Foundation
import QuartzCore
import WebKit

/// The only product process that constructs a Web host. No Shell, library,
/// shared audio capture or system-media producer is initialized in this entry.
@MainActor
final class WebDaemonRuntime: NSObject, NSApplicationDelegate {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(WebDaemonProtocol.flag) }
    let host = DedicatedWebWallpaperHostPlaceholderAdapter()
    let requestID: UUID
    private let inbox = WebDaemonMailbox<WebDaemonCommand>()
    private let outbox = WebDaemonMailbox<Data>()
    private let outputQueue = DispatchQueue(label: "com.mywallpaperx.web-daemon-output")
#if DEBUG
    private var diagnosticObserver: NSObjectProtocol?
    private var pendingDiagnostics: [WebDaemonDiagnostic] = []
    private var diagnosticFlushScheduled = false
    private let startupTimingEnabled: Bool
    private var startupTiming: WebDaemonStartupTimingObservation?
    private var preparationTiming: WebDaemonPreparationTimingObservation?
    private var preparedStartupTiming: WebDaemonPreparationTimingObservation?
    private var pendingHostReadyObservedAt: TimeInterval?
#endif
    private var mediaReplayPending = false
    private var desiredVolume: Float = 0
    private var preparationGeneration: UInt64 = 0
    private var didPrepare = false
    private var committed = false
    private var finalized = false
    private var preparedSurfaces: [WebDaemonSurfaceIdentity] = []
    private var preparationSnapshotReady = false
    private var activation: WebDaemonActivationRequest?
    private var activationMediaReady = false
    private var mediaConfirmationRevision: UInt64 = 0
    private var activityID: UUID?
    private var pendingCancellation: WebDaemonActivationIdentity?
    private var activationDeadline: DispatchWorkItem?
    private var activationPoll: DispatchWorkItem?
    private var stopping = false
#if DEBUG
    var debugFailureCount = 0
    var debugPauseTransitions = 0
    var debugSpectrumFrames = 0
    var debugNonSilentSpectrumFrames = 0
    var debugContinuityInFlight = false
#endif
    init?(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let index = arguments.firstIndex(of: WebDaemonProtocol.flag),
              arguments.indices.contains(index + 1),
              let id = UUID(uuidString: arguments[index + 1]) else { return nil }
        requestID = id
#if DEBUG
        startupTimingEnabled = arguments.contains("--mwx-debug-web-startup-timing")
#endif
        super.init()
    }

    func configure() {
        signal(SIGPIPE, SIG_IGN)
        // Like the Video renderer, a desktop-only host must never activate.
        // Accessory launches can take focus even before a WebView exists.
#if DEBUG
        let usesEvidenceWindow = ProcessInfo.processInfo.arguments.contains("--mwx-debug-web-evidence-dir")
        NSApp.setActivationPolicy(usesEvidenceWindow ? .accessory : .prohibited)
#else
        NSApp.setActivationPolicy(.prohibited)
#endif
        NSApp.delegate = self
        DaemonParentLifetime.shared.setShutdownHandler { [weak self] in
            MainActor.assumeIsolated { self?.shutdown() }
        }
        host.defersPresentation = true
        host.outputActivityAllowed = false
        host.presentationInvalidationHandler = { [weak self] in
            guard let self, !self.finalized, !self.stopping else { return }
            if let activation = self.activation {
                self.failActivation(activation.identity, reason: "web-presentation-invalidated")
            }
            self.preparationGeneration &+= 1
            self.didPrepare = false
            self.preparationSnapshotReady = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.host.phase == .ready else { return }
                self.preparePresentation()
            }
        }
        host.systemMediaDemandHandler = { [weak self] needsMedia, _ in
            self?.mediaReplayPending = false
            self?.emit(.mediaDemand(needsMedia))
        }
        host.eventHandler = { [weak self] event in self?.handleHostEvent(event) }
#if DEBUG
        if startupTimingEnabled { host.debugStartupSurfaceTimings = [:] }
        diagnosticObserver = NotificationCenter.default.addObserver(
            forName: WebRuntimeDiagnosticsStore.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      let event = WebRuntimeDiagnosticsStore.shared.recentEvents(recordID: self.host.currentRequest?.recordID, limit: 1).last else { return }
                self.pendingDiagnostics.append(.init(type: event.type, severity: event.severity.rawValue,
                    message: event.message, screenID: event.screenID, url: event.url))
                if self.pendingDiagnostics.count > 500 { self.pendingDiagnostics.removeFirst() }
                guard !self.diagnosticFlushScheduled else { return }
                self.diagnosticFlushScheduled = true
                DispatchQueue.main.async { [weak self] in self?.flushDiagnostics() }
            }
        }
#endif
        let inbox = inbox
        let expected = requestID
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var frames = DaemonNewlineFrameBuffer()
            WebDaemonPipeReader.read(from: .standardInput) { chunk in
                for frame in frames.append(chunk) {
                    guard frame.count <= WebDaemonProtocol.maximumFrameBytes,
                          let value = try? JSONDecoder().decode(WebDaemonEnvelope<WebDaemonCommand>.self, from: frame),
                          value.version == WebDaemonProtocol.version, value.requestID == expected,
                          inbox.submit(value.payload, byteCount: frame.count, latest: value.payload.isLatestValue, schedule: {
                              RunLoop.main.perform(inModes: [.common]) { [weak self] in
                                  MainActor.assumeIsolated { self?.drainInbox() }
                              }
                          }) else {
                        return false
                    }
                }
                return frames.pendingByteCount <= WebDaemonProtocol.maximumFrameBytes
            }
            DaemonParentLifetime.shared.requestShutdown()
        }
        emit(.hello)
    }

    private func drainInbox() {
        // The pipe reader has already decoded and validated this immutable
        // command. Consume that value instead of parsing its JSON again on main.
        while !stopping, let command = inbox.take() {
            switch command {
            case let .launch(input):
                guard host.currentRequest == nil, input.entryURL.isFileURL, input.rootURL.isFileURL else {
                    emit(.error("invalid-launch")); shutdown(); return
                }
#if DEBUG
                if startupTimingEnabled {
                    preparationTiming = .init(launchReceivedAt: ProcessInfo.processInfo.systemUptime)
                }
#endif
                desiredVolume = input.state.volume
                let mutedState = WallpaperEngine.WebWallpaperRuntimeState(paused: input.state.paused,
                    volume: 0, playbackRate: input.state.playbackRate, spectrumLevels: input.state.spectrumLevels)
                host.launch(input.request(id: requestID), runtimeState: mutedState)
            case let .runtime(command):
#if DEBUG
                if case .pause = command, !host.paused { debugPauseTransitions += 1 }
                if case .resume = command, host.paused { debugPauseTransitions += 1 }
                if case let .pushAudioSpectrum(levels) = command {
                    debugSpectrumFrames += 1
                    if levels.contains(where: { $0 > 0.001 }) { debugNonSilentSpectrumFrames += 1 }
                }
#endif
                if case let .setVolume(volume) = command {
                    desiredVolume = volume
                    if !committed { continue }
                }
                host.handle(command)
                switch command {
                case .pause, .resume:
                    mediaConfirmationRevision &+= 1
                    if activation != nil { confirmActivationMedia() }
                    else if preparationSnapshotReady && !committed { confirmPreparationMedia() }
                    if let identity = pendingCancellation { confirmCancellation(identity) }
                    if let id = activityID { confirmOutputActivity(host.outputActivityAllowed, id: id) }
                default: break
                }
            case let .displays(enabled): host.updateDisplayConfiguration(multiDisplayEnabled: enabled)
            case let .media(value):
                guard host.systemMediaSubscriptionNeedsContent != nil else { continue }
                if let snapshot = value.resolve(previous: host.currentSystemMediaSnapshot) {
                    mediaReplayPending = false
                    host.receiveSystemMediaSnapshot(snapshot)
                } else if !mediaReplayPending {
                    mediaReplayPending = true
                    emit(.mediaReplayRequested)
                }
#if DEBUG
            case .inspect: emitObservation()
            case .debugMeasureContinuity: measureDebugContinuity()
            case .debugExerciseFailure: exerciseDebugFailure()
#endif
            case let .captureFrame(id): captureFrame(id)
            case let .commit(generation):
                activate(.init(identity: .init(generation: generation, activationID: UUID()), surfaces: preparedSurfaces))
            case let .activate(request): activate(request)
            case let .finalize(identity): finalizeActivation(identity)
            case let .cancelActivation(identity): cancelActivation(identity)
            case let .setOutputActivity(active, id): setOutputActivity(active, id: id)
            case .shutdown: shutdown()
            }
        }
    }

    private func handleHostEvent(_ event: WallpaperEngine.WebWallpaperHostEvent) {
        guard !stopping else { return }
#if DEBUG
        if case .failed = event { debugFailureCount += 1 }
#endif
        switch event {
        case .ready:
            if committed { emitUsage();
#if DEBUG
                emitObservation()
#endif
                return }
#if DEBUG
            if startupTimingEnabled { pendingHostReadyObservedAt = ProcessInfo.processInfo.systemUptime }
#endif
            preparePresentation()
        default:
#if DEBUG
            flushDiagnostics()
#endif
            emit(.host(event))
        }
    }

    private func preparePresentation() {
        guard host.phase == .ready, !host.surfaces.isEmpty, activation == nil, !committed else { return }
        preparationGeneration &+= 1
        let generation = preparationGeneration
        didPrepare = false
        preparationSnapshotReady = false
        preparedSurfaces = host.presentationSurfaceIdentities
#if DEBUG
        preparedStartupTiming = nil
        preparationTiming?.hostReadyAt = pendingHostReadyObservedAt
        pendingHostReadyObservedAt = nil
        preparationTiming?.generation = generation
        preparationTiming?.surfaces = preparedSurfaces
        preparationTiming?.snapshotRequestedAt = ProcessInfo.processInfo.systemUptime
        preparationTiming?.snapshotCompletedAt = nil
        preparationTiming?.policyWaitStartedAt = nil
        preparationTiming?.policyAcceptedAt = nil
        preparationTiming?.surfaceTimings = []
#endif
        let surfaces = Array(host.surfaces.values)
        var remaining = surfaces.count
        var failed = false
        for surface in surfaces {
            let configuration = WKSnapshotConfiguration()
            let bounds = surface.webView.bounds
            configuration.rect = NSRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            configuration.afterScreenUpdates = true
            surface.webView.takeSnapshot(with: configuration) { [weak self] image, error in
                guard let self, !self.stopping, !self.committed,
                      self.preparationGeneration == generation,
                      self.host.presentationSurfaceIdentities == self.preparedSurfaces else { return }
                failed = failed || error != nil || image == nil
                remaining -= 1
                guard remaining == 0 else { return }
                if failed { self.emit(.error("web-presentation-preparation-failed")); return }
                self.preparationSnapshotReady = true
#if DEBUG
                self.preparationTiming?.snapshotCompletedAt = ProcessInfo.processInfo.systemUptime
#endif
                self.host.setOutputActivity(false) { _ in }
                self.confirmPreparationMedia()
            }
        }
    }

    private func confirmPreparationMedia() {
        let generation = preparationGeneration
#if DEBUG
        preparationTiming?.policyWaitStartedAt = ProcessInfo.processInfo.systemUptime
#endif
        host.awaitNativeMediaPolicy { [weak self] accepted in
            guard let self, accepted, !self.stopping, !self.committed, self.activation == nil,
                  self.preparationGeneration == generation, self.preparationSnapshotReady,
                  self.host.presentationSurfaceIdentities == self.preparedSurfaces else { return }
            guard !self.didPrepare else { return }
            self.didPrepare = true
#if DEBUG
            self.preparationTiming?.policyAcceptedAt = ProcessInfo.processInfo.systemUptime
            self.preparationTiming?.surfaceTimings = self.preparedSurfaces.compactMap {
                self.host.debugStartupSurfaceTimings?[$0.displayID]?.matching($0)
            }
            self.preparedStartupTiming = self.preparationTiming
#endif
            self.emitUsage()
#if DEBUG
            self.emitObservation()
#endif
            self.emit(.preparationCohort(.init(generation: generation, surfaces: self.preparedSurfaces)))
        }
    }

    private func activate(_ request: WebDaemonActivationRequest) {
        guard didPrepare, preparationGeneration == request.identity.generation,
              request.surfaces == preparedSurfaces,
              request.surfaces == host.presentationSurfaceIdentities,
              !committed, host.phase == .ready, activation == nil else {
            emit(.activationFailed(request.identity, "web-activation-identity-mismatch")); return
        }
#if DEBUG
        if startupTimingEnabled {
            startupTiming = .init(identity: request.identity,
                activateReceivedAt: ProcessInfo.processInfo.systemUptime)
            if preparedStartupTiming?.generation == request.identity.generation {
                startupTiming?.preparation = preparedStartupTiming
            }
        }
#endif
        pendingCancellation = nil
        activityID = nil
        activation = request
        activationMediaReady = false
        finalized = false
        host.defersPresentation = false
        host.usesActivationWindowLevel = true
        host.reassertSurfaceVisibilityAndRuntimeState(orderFront: true)
        host.handle(.setVolume(desiredVolume))
        host.setOutputActivity(true) { _ in }
        CATransaction.flush()
        let identity = request.identity
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.activation?.identity == identity, !self.committed else { return }
            self.failActivation(identity, reason: "web-activation-timeout")
        }
        activationDeadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        confirmActivationMedia()
        checkActivationVisibility(identity)
    }

    private func confirmActivationMedia() {
        guard let identity = activation?.identity, !committed else { return }
        mediaConfirmationRevision &+= 1
        let revision = mediaConfirmationRevision
        activationMediaReady = false
#if DEBUG
        // A superseding pause/resume requires its own current-policy ACK.
        startupTiming?.nativePolicyAcceptedAt = nil
#endif
        host.awaitNativeMediaPolicy { [weak self] accepted in
            guard let self, accepted, !self.stopping, self.activation?.identity == identity,
                  self.mediaConfirmationRevision == revision,
                  self.host.presentationSurfaceIdentities == self.preparedSurfaces else { return }
#if DEBUG
            self.startupTiming?.nativePolicyAcceptedAt = ProcessInfo.processInfo.systemUptime
#endif
            self.activationMediaReady = true
            self.checkActivationVisibility(identity)
        }
    }

    private func checkActivationVisibility(_ identity: WebDaemonActivationIdentity) {
        guard !stopping, !committed, activation?.identity == identity else { return }
        activationPoll?.cancel(); activationPoll = nil
        guard preparationGeneration == identity.generation,
              host.presentationSurfaceIdentities == preparedSurfaces, host.phase == .ready else {
            failActivation(identity, reason: "web-activation-cohort-changed"); return
        }
        let evidence = host.surfaces.values.sorted { $0.screenID < $1.screenID }.map {
            PlaybackSurfaceVisibility.observe(window: $0.window, displayID: $0.screenID,
                                               expectedLevel: host.surfaceWindowLevel.rawValue)
        }
#if DEBUG
        if startupTiming?.identity == identity {
            if startupTiming?.visibilityFirstConfirmedAt == nil,
               evidence.allSatisfy({ PlaybackSurfaceVisibility.evaluate($0) == .confirmed }) {
                startupTiming?.visibilityFirstConfirmedAt = ProcessInfo.processInfo.systemUptime
            }
            if startupTiming?.firstVisibilityRetryReason == nil {
                for value in evidence {
                    if case let .retry(reason) = PlaybackSurfaceVisibility.evaluate(value) {
                        startupTiming?.firstVisibilityRetryAt = ProcessInfo.processInfo.systemUptime
                        startupTiming?.firstVisibilityRetryReason = reason
                        break
                    }
                }
            }
        }
#endif
        if evidence.contains(where: { PlaybackSurfaceVisibility.evaluate($0) == .deferredOffSpace }) {
            failActivation(identity, reason: "inactive-space", deferred: true); return
        }
        if host.outputActivityAllowed && activationMediaReady && evidence.allSatisfy({ PlaybackSurfaceVisibility.evaluate($0) == .confirmed }) {
            committed = true
            activationDeadline?.cancel(); activationDeadline = nil
#if DEBUG
            emitObservation()
#endif
            emit(.activationConfirmed(identity, evidence))
            return
        }
        let poll = DispatchWorkItem { [weak self] in self?.checkActivationVisibility(identity) }
        activationPoll = poll
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }

    private func finalizeActivation(_ identity: WebDaemonActivationIdentity) {
        guard committed, activation?.identity == identity, !finalized else { return }
        finalized = true
        host.usesActivationWindowLevel = false
        host.reassertSurfaceVisibilityAndRuntimeState(orderFront: false)
        CATransaction.flush()
    }

    private func stopActivationWork() {
        activationDeadline?.cancel(); activationDeadline = nil
        activationPoll?.cancel(); activationPoll = nil
        mediaConfirmationRevision &+= 1
        activationMediaReady = false
    }

    private func failActivation(_ identity: WebDaemonActivationIdentity, reason: String, deferred: Bool = false) {
        guard activation?.identity == identity else { return }
        stopActivationWork()
        activation = nil; committed = false
        host.defersPresentation = true
        host.usesActivationWindowLevel = false
        host.setOutputActivity(false) { _ in }
        host.reassertSurfaceVisibilityAndRuntimeState(orderFront: false)
        if deferred { emit(.activationDeferred(identity, reason)) }
        else { emit(.activationFailed(identity, reason)); emit(.error(reason)) }
    }

    private func cancelActivation(_ identity: WebDaemonActivationIdentity) {
        guard preparationGeneration == identity.generation, !finalized,
              activation == nil || activation?.identity == identity else { return }
        stopActivationWork()
        activation = nil; committed = false
        didPrepare = false; preparationSnapshotReady = false
        host.defersPresentation = true
        host.usesActivationWindowLevel = false
        for surface in host.surfaces.values { surface.window.orderOut(nil) }
        pendingCancellation = identity
        activityID = nil
        host.setOutputActivity(false) { _ in }
        confirmCancellation(identity)
    }

    private func confirmCancellation(_ identity: WebDaemonActivationIdentity) {
        host.awaitNativeMediaPolicy { [weak self] accepted in
            guard let self, accepted, !self.stopping,
                  self.pendingCancellation == identity,
                  self.preparationGeneration == identity.generation, self.activation == nil else { return }
            self.pendingCancellation = nil
            self.emit(.activationCancelled(identity))
        }
    }

    private func setOutputActivity(_ active: Bool, id: UUID) {
        // A staged candidate can only acquire activity through activate().
        guard !active || committed || activation != nil else { return }
        activityID = id
        if !active { activationMediaReady = false }
        host.setOutputActivity(active) { _ in }
        confirmOutputActivity(active, id: id)
    }

    private func confirmOutputActivity(_ active: Bool, id: UUID) {
        host.awaitNativeMediaPolicy { [weak self] accepted in
            guard let self, accepted, !self.stopping, self.activityID == id,
                  self.host.outputActivityAllowed == active else { return }
            self.activityID = nil
            self.emit(.outputActivityChanged(id, active))
        }
    }

    private func captureFrame(_ id: UUID) {
        WallpaperRuntimeFrameCapture.captureWallpaperWindowCGImage { [weak self] image in
            guard let self, !self.stopping else { return }
            guard let image else { self.emit(.capturedFrame(id, nil)); return }
            DispatchQueue.global(qos: .utility).async {
                let representation = NSBitmapImageRep(cgImage: image)
                let data = representation.representation(using: .jpeg,
                    properties: [.compressionFactor: 0.85])
                DispatchQueue.main.async {
                    guard !self.stopping else { return }
                    self.emit(.capturedFrame(id, data.flatMap { $0.count <= 4 * 1_024 * 1_024 ? $0 : nil }))
                }
            }
        }
    }

#if DEBUG
    private func emitObservation() {
        emit(.observation(.init(phase: host.phase.rawValue,
            currentRequest: host.currentRequest == nil ? 0 : 1,
            loopbacks: host.loopbackServers.count,
            monitors: (host.localMouseMonitor == nil ? 0 : 1) + (host.globalMouseMonitor == nil ? 0 : 1),
            observers: host.lifecycleObservers.count,
            pointerTimer: host.pointerPollingTimer == nil ? 0 : 1,
            surfaces: host.surfaces.count,
            watchTimer: host.directoryWatchTimer == nil ? 0 : 1,
            watchers: host.directoryWatchersByDirectory.count, startupTiming: startupTiming)))
    }
#endif
#if DEBUG
    private func flushDiagnostics() {
        diagnosticFlushScheduled = false
        guard !pendingDiagnostics.isEmpty else { return }
        let events = pendingDiagnostics
        pendingDiagnostics.removeAll(keepingCapacity: true)
        emit(.diagnostics(events))
    }
#endif
    private func emitUsage() { emit(.usage(Array(host.inUsePersistentDataStoreIdentifiers))) }

    func emit(_ event: WebDaemonEvent) {
        guard let data = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(requestID: requestID, payload: event)),
              outbox.submit(data, byteCount: data.count, latest: false, schedule: { [weak self] in
                  guard let self else { return }
                  let outbox = self.outbox
                  self.outputQueue.async {
                      while let next = outbox.take() {
                          do { try FileHandle.standardOutput.write(contentsOf: next) }
                          catch { DispatchQueue.main.async { self.shutdown() }; return }
                      }
                  }
              }) else { shutdown(); return }
    }

    private func shutdown() {
        DaemonParentLifetime.shared.requestShutdown()
        guard !stopping else { return }
        stopping = true
        stopActivationWork()
        inbox.close()
        host.handle(.stop)
#if DEBUG
        if let diagnosticObserver { NotificationCenter.default.removeObserver(diagnosticObserver) }
#endif
        outbox.close()
        NSApp.terminate(nil)
    }
}
