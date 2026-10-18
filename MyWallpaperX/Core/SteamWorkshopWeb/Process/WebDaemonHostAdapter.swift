import AppKit
import Darwin
import Foundation

/// Main-App control endpoint. The active and preparing renderer are the only
/// Web processes; every WKWebView and desktop window lives beyond this boundary.
final class WebDaemonHostAdapter: WallpaperEngine.WebWallpaperHostAdapter {
    var eventHandler: ((WallpaperEngine.WebWallpaperHostEvent) -> Void)?
    var switchPrepared: ((PlaybackSwitchTicket, PlaybackSwitchEndpoint) -> Void)?
    var switchVisible: ((PlaybackSwitchTicket, UUID) -> Void)?
    var switchFailed: ((PlaybackSwitchTicket, String) -> Void)?
    var switchLost: ((PlaybackSwitchTicket, String) -> Void)?
    var allowedNetworkBridgeHostsResolver: ((String) -> Set<String>)?

    final class Session {
        let ticket: PlaybackSwitchTicket
        let executionID = UUID()
        var preparedCohort: WebDaemonPreparedCohort?
        var minimumPreparationGeneration: UInt64 = 1
        var activationIdentity: WebDaemonActivationIdentity?
        var didObserveExit = false
        var isCancelling = false
        var shouldRecoverOnExit = false
        var visibilityConfirmed = false
        var activationSent = false
        var cancelCompletions: [() -> Void] = []
        var retirementCompletions: [() -> Void] = []
        var outputActivityAwaitingExit: Set<UUID> = []
        var outputActivityCompletions: [UUID: (desired: Bool, completion: (Bool) -> Void)] = [:]
        let request: WallpaperEngine.WebWallpaperLaunchRequest
        let transport: DaemonProcessTransport
        let mediaConsumer = UUID()
        var state: WallpaperEngine.WebWallpaperRuntimeState
        var propertiesJSON: String?
        var multiDisplayEnabled: Bool
        var frames = DaemonNewlineFrameBuffer()
        var usage: Set<UUID> = []
        var hello = false
        var preparationGeneration: UInt64?
        var mediaNeedsContent: Bool?
        var lastMediaArtworkKey: WebDaemonMediaArtworkKey?
        var audioDemand = false
        var observation: WebDaemonHostObservation?
        var isRetiring = false
        var timeout: DispatchWorkItem?
        var captures: [UUID: (NSImage?) -> Void] = [:]
        var committedAt: TimeInterval?
        let recoveryAttempt: Int
#if DEBUG
        let startedAt = ProcessInfo.processInfo.systemUptime
#endif

        init(request: WallpaperEngine.WebWallpaperLaunchRequest,
             state: WallpaperEngine.WebWallpaperRuntimeState,
             transport: DaemonProcessTransport, recoveryAttempt: Int, ticket: PlaybackSwitchTicket) {
            self.ticket = ticket
            self.request = request; self.state = state; self.transport = transport
            propertiesJSON = request.propertiesJSON
            multiDisplayEnabled = request.multiDisplayEnabled
            self.recoveryAttempt = recoveryAttempt
        }

        var executionRequest: WallpaperEngine.WebWallpaperLaunchRequest {
            .init(id: request.id, entryURL: request.entryURL, rootURL: request.rootURL,
                  propertiesJSON: propertiesJSON, source: request.source,
                  recordID: request.recordID, language: request.language,
                  runtimeProfile: request.runtimeProfile, multiDisplayEnabled: multiDisplayEnabled,
                  resourceLifetime: request.resourceLifetime)
        }
    }

    let spectrumDelivery: PlaybackSpectrumDelivery

    init(spectrumDelivery: PlaybackSpectrumDelivery) {
        self.spectrumDelivery = spectrumDelivery
        memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        memoryPressure.setEventHandler { [weak self] in
            guard let self else { return }
            self.memoryPressureAllowsPreparation = self.memoryPressure.data.contains(.normal)
            if !self.memoryPressureAllowsPreparation { self.cancelIdlePreparation() }
        }
        memoryPressure.resume()
    }

    deinit {
        memoryPressure.cancel(); idlePreparationWorkItem?.cancel(); recoveryWorkItem?.cancel()
        for prepared in [preparedProcess].compactMap({ $0 }) + Array(retiringPrepared.values) {
            prepared.timeout?.cancel()
            prepared.transport.requestGracefulStop()
        }
        for session in [active, candidate].compactMap({ $0 }) + Array(standby.values) + Array(cancelling.values) + Array(retiring.values) {
            session.transport.requestGracefulStop()
        }
    }

    func updateSpectrumTargets() {
        spectrumDelivery.setWebTargets(([active, candidate].compactMap { $0 } + Array(standby.values)).compactMap { session in
            guard session.hello, !session.isRetiring, !session.isCancelling else { return nil }
            return .init(requestID: session.request.id, transport: session.transport)
        })
    }

    var active: Session?
    var candidate: Session?
    var deferredPreparation: DeferredWebSwitchPreparation?
    // A changed target cohort keeps its original endpoint alive until exact
    // physical exit, then rebuilds this still-current ticket in a new session.
    var displayRebuildSource: Session?
    var pendingRecovery: (session: Session, attempt: Int)?
    var recoveryWorkItem: DispatchWorkItem?
    var standby: [ObjectIdentifier: Session] = [:]
    var cancelling: [ObjectIdentifier: Session] = [:]
    final class PreparedProcess {
        let requestID: UUID
        let transport: DaemonProcessTransport
        var frames = DaemonNewlineFrameBuffer()
        var hello = false
        var isIdle: Bool
        var timeout: DispatchWorkItem?
        init(requestID: UUID, transport: DaemonProcessTransport, isIdle: Bool) {
            self.requestID = requestID; self.transport = transport; self.isIdle = isIdle
        }
    }
    var preparedProcess: PreparedProcess?
    var retiringPrepared: [ObjectIdentifier: PreparedProcess] = [:]
    // Keep immutable version leases until the actual child has exited.
    var retiring: [ObjectIdentifier: Session] = [:]
    var lastAudioDemand = false
    var lastAudioDemandRequestID: UUID?
    var recoveryGeneration: UInt64 = 0
    let memoryPressure: DispatchSourceMemoryPressure
    var memoryPressureAllowsPreparation = true
    var idlePreparationWorkItem: DispatchWorkItem?

    /// This UUID becomes the next content request's original identity, never
    /// a rewritten identity on a process that has already loaded author content.
    var availablePreparedRequestID: UUID? {
        guard let preparedProcess, preparedProcess.isIdle,
              preparedProcess.transport.isRunning else { return nil }
        return preparedProcess.requestID
    }

    func prepareIdleProcess() {
        guard memoryPressureAllowsPreparation, candidate == nil, preparedProcess == nil else { return }
        startPreparedProcess(requestID: UUID(), isIdle: true)
    }

    func scheduleIdlePreparation() {
        idlePreparationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.idlePreparationWorkItem = nil
            guard self.active != nil else { return }
            self.prepareIdleProcess()
        }
        idlePreparationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func cancelIdlePreparation() {
        idlePreparationWorkItem?.cancel(); idlePreparationWorkItem = nil
        if preparedProcess?.isIdle == true { discardPreparedProcess() }
    }

    /// Overlap AppKit initialization with the existing async project analysis.
    /// A completed empty prewarm can be adopted before or after hello.
    func prepareProcess(requestID: UUID) {
        cancelPreparation(preservingPreparedRequestID: requestID)
        if let preparedProcess, preparedProcess.requestID == requestID,
           preparedProcess.transport.isRunning {
            preparedProcess.isIdle = false
            armPreparationTimeout(preparedProcess, after: 15)
            return
        }
        discardPreparedProcess()
        startPreparedProcess(requestID: requestID, isIdle: false)
    }

    func startPreparedProcess(requestID: UUID, isIdle: Bool) {
        guard let transport = makeTransport(requestID: requestID) else { return }
        let prepared = PreparedProcess(requestID: requestID, transport: transport, isIdle: isIdle)
        preparedProcess = prepared
        transport.onOutput = { [weak self, weak prepared] data in
            guard let self, let prepared, self.preparedProcess === prepared else { return }
            for frame in prepared.frames.append(data) {
                guard frame.count <= WebDaemonProtocol.maximumFrameBytes,
                      let envelope = try? JSONDecoder().decode(WebDaemonEnvelope<WebDaemonEvent>.self, from: frame),
                      envelope.version == WebDaemonProtocol.version, envelope.requestID == requestID,
                      case .hello = envelope.payload, !prepared.hello else {
                    self.cancelPreparedProcess(requestID: requestID); return
                }
                prepared.hello = true
            }
            if prepared.frames.pendingByteCount > WebDaemonProtocol.maximumFrameBytes {
                self.cancelPreparedProcess(requestID: requestID)
            }
        }
        transport.onTermination = { [weak self, weak prepared] _ in
            guard let self, let prepared else { return }
            prepared.timeout?.cancel()
            if self.preparedProcess === prepared { self.preparedProcess = nil }
            self.retiringPrepared.removeValue(forKey: ObjectIdentifier(prepared))
            prepared.transport.closeIO()
        }
        armPreparationTimeout(prepared, after: isIdle ? 30 : 15)
        do { try transport.start() }
        catch { cancelPreparedProcess(requestID: requestID) }
    }

    func armPreparationTimeout(_ prepared: PreparedProcess, after seconds: TimeInterval) {
        prepared.timeout?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak prepared] in
            guard let self, let prepared, self.preparedProcess === prepared else { return }
            self.discardPreparedProcess()
        }
        prepared.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    func cancelPreparedProcess(requestID: UUID) {
        guard preparedProcess?.requestID == requestID else { return }
        discardPreparedProcess()
    }

    func discardPreparedProcess() {
        let prepared = preparedProcess
        preparedProcess = nil
        guard let prepared else { return }
        prepared.timeout?.cancel()
        if prepared.transport.isRunning {
            retiringPrepared[ObjectIdentifier(prepared)] = prepared
        }
        let data = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(
            requestID: prepared.requestID, payload: WebDaemonCommand.shutdown))
        prepared.transport.requestGracefulStop(data, gracePeriod: 1)
    }

    var observation: WebDaemonHostObservation? { (candidate ?? active)?.observation }
    var liveProcessIdentifiers: [Int32] {
        let playback = liveSessions.filter { $0.transport.isRunning }.map { $0.transport.process.processIdentifier }
        let prepared = [preparedProcess].compactMap { $0 } + Array(retiringPrepared.values)
        return playback + prepared.filter { $0.transport.isRunning }.map { $0.transport.process.processIdentifier }
    }
#if DEBUG
    var debugContinuityHandler: (([String: Double]?) -> Void)?
    var debugContinuityStartedHandler: (() -> Void)?
    var debugPreparedProcessReady: Bool { preparedProcess?.hello == true }
    var debugActiveProcessIdentifier: Int32? { active?.transport.process.processIdentifier }
    var debugPreparationFacts: String {
        "memoryAllowed=\(memoryPressureAllowsPreparation) prepared=\(String(describing: preparedProcess?.requestID)) idle=\(String(describing: preparedProcess?.isIdle)) candidate=\(String(describing: candidate?.request.id)) active=\(String(describing: active?.request.id)) pids=\(liveProcessIdentifiers)"
    }
    func debugMeasureContinuity() {
        if let active { send(.debugMeasureContinuity, to: active) }
    }
    func debugTerminateActiveProcess() {
        if let active { kill(active.transport.process.processIdentifier, SIGKILL) }
    }
    var debugNavigationChecksHandler: (([String: Bool]) -> Void)?
    func debugExerciseFailure() {
        if let active { send(.debugExerciseFailure, to: active) }
    }
#endif

    var hasLivePlayback: Bool { !liveSessions.isEmpty }
    var hasPendingRequest: Bool { candidate != nil || displayRebuildSource != nil || preparedProcess?.isIdle == false }
    var activeRequest: WallpaperEngine.WebWallpaperLaunchRequest? { active?.executionRequest }
    var activeRecordIDs: Set<String> {
        Set(liveSessions.compactMap { $0.request.recordID })
    }
    var inUsePersistentDataStoreIdentifiers: Set<UUID> {
        liveSessions.reduce(into: Set<UUID>()) { $0.formUnion($1.usage) }
    }
    var liveSessions: [Session] {
        var seen: Set<ObjectIdentifier> = []
        return ([active, candidate].compactMap { $0 } + Array(standby.values)
            + Array(cancelling.values) + Array(retiring.values))
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    func launch(_ request: WallpaperEngine.WebWallpaperLaunchRequest,
                runtimeState: WallpaperEngine.WebWallpaperRuntimeState) {
        prepareSwitch(ticket: .init(epoch: 0, id: UUID(), runtime: .web),
            request: request, runtimeState: runtimeState)
    }

    func prepareSwitch(ticket: PlaybackSwitchTicket,
                       request: WallpaperEngine.WebWallpaperLaunchRequest,
                       runtimeState: WallpaperEngine.WebWallpaperRuntimeState) {
        if let candidate, candidate.ticket.epoch > ticket.epoch { return }
        if let active, active.ticket.epoch > ticket.epoch { return }
        displayRebuildSource = nil
        recoveryGeneration &+= 1
        launch(request, state: runtimeState, recoveryAttempt: 0, ticket: ticket)
    }

    func launch(_ request: WallpaperEngine.WebWallpaperLaunchRequest,
                state: WallpaperEngine.WebWallpaperRuntimeState, recoveryAttempt: Int,
                ticket: PlaybackSwitchTicket) {
        if let candidate, candidate.visibilityConfirmed, !candidate.isCancelling {
            deferredPreparation = .init(request: request, state: state,
                recoveryAttempt: recoveryAttempt, ticket: ticket)
            return
        }
        idlePreparationWorkItem?.cancel(); idlePreparationWorkItem = nil
        if let candidate { cancelSession(candidate, completion: {}) }
        candidate = nil
        let prepared = preparedProcess
        let reusable = prepared?.requestID == request.id && prepared?.transport.isRunning == true
        if reusable { preparedProcess = nil; prepared?.timeout?.cancel() }
        else { discardPreparedProcess() }
        guard let transport = reusable ? prepared?.transport : makeTransport(requestID: request.id) else {
            switchFailed?(ticket, "Web 宿主可执行文件不可用")
            eventHandler?(.failed(message: "Web 宿主可执行文件不可用", requestID: request.id)); return
        }
        let session = Session(request: request, state: state, transport: transport,
            recoveryAttempt: recoveryAttempt, ticket: ticket)
        if reusable, let prepared { session.frames = prepared.frames }
        candidate = session
        transport.onOutput = { [weak self, weak session] data in
            guard let self, let session else { return }
            self.consume(data, from: session)
        }
        transport.onTermination = { [weak self, weak session] _ in
            guard let self, let session else { return }
            self.didExit(session)
        }
        armSessionTimeout(session, after: 45, message: "Web 壁纸准备超时，保留原壁纸")
        publishAudioDemand(force: true)
        if reusable {
            if prepared?.hello == true { receive(.hello, from: session) }
        } else {
            do { try transport.start() }
            catch { fail(session, message: error.localizedDescription) }
        }
    }

    func makeTransport(requestID: UUID) -> DaemonProcessTransport? {
        guard DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses,
              let executable = Bundle.main.executableURL else { return nil }
        var arguments = [WebDaemonProtocol.flag, requestID.uuidString]
#if DEBUG
        let inherited = ProcessInfo.processInfo.arguments
        for flag in ["--mwx-debug-web-evidence-dir", "--mwx-debug-web-interaction"] {
            if let index = inherited.firstIndex(of: flag), inherited.indices.contains(index + 1) {
                arguments += [flag, inherited[index + 1]]
            }
        }
#endif
        let transport = DaemonProcessTransport(executableURL: executable, arguments: arguments,
                                               playbackRenderer: true)
        transport.onError = { text in NSLog("MWX WEB HOST: %@", String(text.prefix(2000))) }
        return transport
    }

    func cancelPreparation(preservingPreparedRequestID: UUID? = nil) {
        recoveryGeneration &+= 1
        idlePreparationWorkItem?.cancel(); idlePreparationWorkItem = nil
        if preparedProcess?.requestID != preservingPreparedRequestID { discardPreparedProcess() }
        if deferredPreparation?.request.id != preservingPreparedRequestID { deferredPreparation = nil }
        if displayRebuildSource?.request.id != preservingPreparedRequestID { displayRebuildSource = nil }
        if let candidate, !candidate.visibilityConfirmed { cancelSession(candidate, completion: {}) }
        publishAudioDemand(force: true)
    }

    func captureSurfaceFrame(completion: @escaping (NSImage?) -> Void) {
        guard let session = active else { completion(nil); return }
        let id = UUID()
        session.captures[id] = completion
        send(.captureFrame(id), to: session)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak session] in
            session?.captures.removeValue(forKey: id)?(nil)
        }
    }

    func updateDisplayConfiguration(multiDisplayEnabled: Bool) {
        displayRebuildSource?.multiDisplayEnabled = multiDisplayEnabled
        if let candidate, candidate.multiDisplayEnabled != multiDisplayEnabled {
            candidate.multiDisplayEnabled = multiDisplayEnabled
            rebuildCandidateSession(candidate)
        }
        for session in [active, candidate].compactMap({ $0 }) + Array(standby.values) {
            session.multiDisplayEnabled = multiDisplayEnabled
            if session.hello { send(.displays(multiDisplayEnabled), to: session) }
        }
    }

    func handle(_ command: WallpaperEngine.WebWallpaperRuntimeCommand) {
        if case .stop = command {
            recoveryGeneration &+= 1
            idlePreparationWorkItem?.cancel(); idlePreparationWorkItem = nil
            discardPreparedProcess()
            deferredPreparation = nil
            displayRebuildSource = nil
            pendingRecovery = nil; recoveryWorkItem?.cancel(); recoveryWorkItem = nil
            let id = candidate?.request.id ?? active?.request.id
            for session in liveSessions { retire(session) }
            candidate = nil; active = nil; standby.removeAll(); cancelling.removeAll()
            updateSpectrumTargets()
            lastAudioDemand = false
            if let id { eventHandler?(.stopped(requestID: id)) }
            return
        }
        var policySessions = [active, candidate].compactMap { $0 } + Array(standby.values)
        if let displayRebuildSource { policySessions.append(displayRebuildSource) }
        for session in policySessions {
            switch command {
            case .pause:
                session.state = .init(paused: true, volume: session.state.volume,
                    playbackRate: session.state.playbackRate, spectrumLevels: session.state.spectrumLevels)
            case let .resume(rate):
                session.state = .init(paused: false, volume: session.state.volume,
                    playbackRate: rate, spectrumLevels: session.state.spectrumLevels)
            case let .setVolume(volume):
                session.state = .init(paused: session.state.paused, volume: volume,
                    playbackRate: session.state.playbackRate, spectrumLevels: session.state.spectrumLevels)
            case let .setPlaybackRate(rate):
                session.state = .init(paused: session.state.paused, volume: session.state.volume,
                    playbackRate: rate, spectrumLevels: session.state.spectrumLevels)
            case let .pushAudioSpectrum(levels):
                session.state = .init(paused: session.state.paused, volume: session.state.volume,
                    playbackRate: session.state.playbackRate, spectrumLevels: levels)
            case let .applyProperties(json):
                guard active === session else { continue }
                session.propertiesJSON = json
            case .stop: break
            }
            if session.hello { send(.runtime(command), to: session) }
        }
    }

    func consume(_ data: Data, from session: Session) {
        guard !session.isRetiring,
              active === session || candidate === session || standby[ObjectIdentifier(session)] != nil
                || cancelling[ObjectIdentifier(session)] != nil else { return }
        for frame in session.frames.append(data) {
            guard frame.count <= WebDaemonProtocol.maximumFrameBytes,
                  let envelope = try? JSONDecoder().decode(WebDaemonEnvelope<WebDaemonEvent>.self, from: frame),
                  envelope.version == WebDaemonProtocol.version,
                  envelope.requestID == session.request.id else {
                fail(session, message: "Web 宿主返回了无效协议数据"); return
            }
            receive(envelope.payload, from: session)
        }
        if session.frames.pendingByteCount > WebDaemonProtocol.maximumFrameBytes {
            fail(session, message: "Web 宿主协议数据超出限制")
        }
    }

    func receive(_ event: WebDaemonEvent, from session: Session) {
        switch event {
        case let .observation(value): session.observation = value
#if DEBUG
        case let .debugNavigationChecks(checks): debugNavigationChecksHandler?(checks)
        case .debugContinuityStarted: debugContinuityStartedHandler?()
        case let .debugContinuity(stats): debugContinuityHandler?(stats)
#endif
        case .hello:
#if DEBUG
            NSLog("MWX WEB STARTUP request=%@ stage=process elapsedMs=%.1f", session.request.id.uuidString,
                  (ProcessInfo.processInfo.systemUptime - session.startedAt) * 1_000)
#endif
            guard !session.hello else { fail(session, message: "Web 宿主重复握手"); return }
            session.hello = true
            let hosts = session.request.recordID.flatMap { allowedNetworkBridgeHostsResolver?($0) } ?? []
            send(.launch(.init(session.executionRequest, state: session.state, hosts: hosts)), to: session)
            updateSpectrumTargets()
        case let .host(event):
            switch event {
            case let .failed(message, _): fail(session, message: message)
            case let .audioSpectrumDemandChanged(active, _):
                session.audioDemand = active; publishAudioDemand()
            case .accepted:
                if candidate === session { eventHandler?(event) }
            case .ready, .stopped: break
            }
        case let .capturedFrame(id, data):
            session.captures.removeValue(forKey: id)?(data.flatMap(NSImage.init(data:)))
        case .prepared, .committed:
            break // Legacy observations cannot authorize an activation.
        case let .preparationCohort(cohort): receivePreparedCohort(cohort, from: session)
        case let .activationConfirmed(identity, evidence):
            guard candidate === session, !session.isCancelling, !session.visibilityConfirmed,
                  session.activationIdentity == identity,
                  let cohort = session.preparedCohort,
                  evidence.count == cohort.surfaces.count, !evidence.isEmpty,
                  Set(evidence.map(\.displayID)).count == evidence.count,
                  evidence.allSatisfy({ value in
                      value.expectedPID == session.transport.process.processIdentifier
                        && cohort.surfaces.contains { $0.displayID == value.displayID && $0.windowID == value.windowID }
                        && PlaybackSurfaceVisibility.evaluate(value) == .confirmed
                  }) else { return }
            session.visibilityConfirmed = true
            session.timeout?.cancel(); session.timeout = nil
            if let switchVisible { switchVisible(session.ticket, session.executionID) }
            else { finalizeSession(session, identity: identity) }
        case let .activationDeferred(identity, _):
            guard session.activationIdentity == identity else { return }
        case let .activationFailed(identity, message):
            guard session.activationIdentity == identity else { return }
            fail(session, message: message)
        case let .activationCancelled(identity):
            guard session.isCancelling, !session.isRetiring,
                  session.activationIdentity == identity else { return }
            finishSessionCancellation(session)
            retire(session)
        case let .outputActivityChanged(id, actual):
            guard !session.outputActivityAwaitingExit.contains(id),
                  let pending = session.outputActivityCompletions.removeValue(forKey: id) else { return }
            pending.completion(actual == pending.desired)
        case let .usage(ids): session.usage = Set(ids)
        case .mediaReplayRequested:
            guard session.mediaNeedsContent != nil else { return }
            session.lastMediaArtworkKey = nil
            sendMedia(SystemMediaService.shared.currentSnapshot, to: session)
        case let .mediaDemand(needsMedia):
            session.mediaNeedsContent = needsMedia
            session.lastMediaArtworkKey = nil
            guard let needsMedia else {
                SystemMediaService.shared.unsubscribe(session.mediaConsumer); return
            }
            SystemMediaService.shared.subscribe(session.mediaConsumer, needsMedia: needsMedia) { [weak self, weak session] snapshot in
                guard let self, let session, !session.isRetiring,
                      self.active === session || self.candidate === session else { return }
                self.sendMedia(snapshot, to: session)
            }
        case let .diagnostics(values):
            for value in values {
                WebRuntimeDiagnosticsStore.shared.record(type: value.type,
                    severity: .init(rawValue: value.severity) ?? .warning, message: value.message,
                    recordID: session.request.recordID, screenID: value.screenID, url: value.url)
            }
        case let .error(message): fail(session, message: message)
        }
    }

    func sendMedia(_ snapshot: SystemMediaSnapshot, to session: Session) {
        let web = WebDaemonMediaSnapshot(snapshot, previous: session.lastMediaArtworkKey)
        session.lastMediaArtworkKey = web.artworkKey
        send(.media(web), to: session)
    }

    var audioSpectrumRequested: Bool {
        [active, candidate].compactMap { $0 }.contains {
            $0.audioDemand && !$0.isRetiring && !$0.isCancelling && $0.transport.isRunning
        }
    }

    func publishAudioDemand(force: Bool = false) {
        updateSpectrumTargets()
        let demanded = audioSpectrumRequested
        guard force || demanded != lastAudioDemand,
              let requestID = candidate?.request.id ?? active?.request.id ?? lastAudioDemandRequestID else { return }
        lastAudioDemand = demanded
        // Removing the last uncommitted candidate must still withdraw its
        // aggregate demand; no committed session will emit stopped for it.
        lastAudioDemandRequestID = demanded ? requestID : nil
        eventHandler?(.audioSpectrumDemandChanged(demanded, requestID: requestID))
    }

    func send(_ command: WebDaemonCommand, to session: Session) {
        guard !session.isRetiring else { return }
        guard let data = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(requestID: session.request.id, payload: command)),
              data.count <= WebDaemonProtocol.maximumFrameBytes else {
            fail(session, message: "Web 宿主命令编码失败或超出限制"); return
        }
        let sent = command.isLatestValue ? session.transport.sendLatest(data) : session.transport.sendRequired(data)
        if !sent { fail(session, message: "Web 宿主命令通道不可用") }
    }

    func fail(_ session: Session, message: String) {
        guard !session.isRetiring, !session.isCancelling else { return }
        let requestID = session.request.id
        if active === session {
            session.shouldRecoverOnExit = true
            switchFailed?(session.ticket, message)
            retire(session)
            return
        }
        if candidate === session { candidate = nil }
        if active === session { active = nil }
        if session.recoveryAttempt > 0 || session.visibilityConfirmed {
            eventHandler?(.stopped(requestID: session.request.id))
            switchLost?(session.ticket, message)
        } else { switchFailed?(session.ticket, message) }
        cancelSession(session, completion: {})
        eventHandler?(.failed(message: message, requestID: requestID))
        publishAudioDemand(force: true)
        runDeferredPreparationIfPossible()
    }

    func retire(_ session: Session) {
        guard !session.didObserveExit else { return }
        // Establish physical retention before consulting Process.isRunning or
        // withdrawing logical references; the exit callback may already be queued.
        retiring[ObjectIdentifier(session)] = session
        guard !session.isRetiring else {
            if !session.transport.isRunning { didExit(session) }
            return
        }
        session.timeout?.cancel(); session.timeout = nil
        let captures = session.captures.values
        session.captures.removeAll()
        captures.forEach { $0(nil) }
        SystemMediaService.shared.unsubscribe(session.mediaConsumer)
        session.isRetiring = true
        updateSpectrumTargets()
        if !session.transport.isRunning { didExit(session); return }
        standby.removeValue(forKey: ObjectIdentifier(session))
        cancelling.removeValue(forKey: ObjectIdentifier(session))
        let data = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(
            requestID: session.request.id, payload: WebDaemonCommand.shutdown))
        session.transport.requestGracefulStop(data, gracePeriod: 1)
    }

    func didExit(_ session: Session) {
        guard !session.didObserveExit else { return }
        session.didObserveExit = true
        session.timeout?.cancel()
        SystemMediaService.shared.unsubscribe(session.mediaConsumer)
        session.transport.closeIO()
        if session.isRetiring, !session.shouldRecoverOnExit, session.committedAt != nil {
            eventHandler?(.stopped(requestID: session.request.id))
        }
        finishSessionCancellation(session)
        let retirements = session.retirementCompletions
        session.retirementCompletions.removeAll()
        retirements.forEach { $0() }
        let outputCallbacks = session.outputActivityCompletions.values
        session.outputActivityCompletions.removeAll()
        outputCallbacks.forEach { $0.completion(!$0.desired) }
        standby.removeValue(forKey: ObjectIdentifier(session))
        cancelling.removeValue(forKey: ObjectIdentifier(session))
        retiring.removeValue(forKey: ObjectIdentifier(session))
        if session.isRetiring && !session.shouldRecoverOnExit { return }
        if candidate === session { fail(session, message: "Web 壁纸准备进程意外退出"); return }
        guard active === session else { return }
        active = nil
        updateSpectrumTargets()
        let attempt = session.committedAt.map {
            ProcessInfo.processInfo.systemUptime - $0 >= 15 ? 0 : session.recoveryAttempt
        } ?? session.recoveryAttempt
        guard attempt < 2 else {
            eventHandler?(.stopped(requestID: session.request.id))
            switchLost?(session.ticket, "Web 宿主反复退出")
            eventHandler?(.failed(message: "Web 宿主反复退出", requestID: session.request.id))
            return
        }
        pendingRecovery = (session, attempt + 1)
        schedulePendingRecoveryIfPossible()
    }
}
