import AppKit
import Darwin
import Foundation

/// Main-App control endpoint. The active and preparing renderer are the only
/// Web processes; every WKWebView and desktop window lives beyond this boundary.
final class WebDaemonHostAdapter: WallpaperEngine.WebWallpaperHostAdapter {
    var eventHandler: ((WallpaperEngine.WebWallpaperHostEvent) -> Void)?
    var allowedNetworkBridgeHostsResolver: ((String) -> Set<String>)?

    private final class Session {
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
             transport: DaemonProcessTransport, recoveryAttempt: Int) {
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

    private let spectrumDelivery: PlaybackSpectrumDelivery

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
        memoryPressure.cancel(); idlePreparationWorkItem?.cancel()
        preparedProcess?.timeout?.cancel(); preparedProcess?.transport.terminate()
    }

    private func updateSpectrumTargets() {
        spectrumDelivery.setWebTargets([active, candidate].compactMap { session in
            guard let session, session.hello, !session.isRetiring else { return nil }
            return .init(requestID: session.request.id, transport: session.transport)
        })
    }

    private var active: Session?
    private var candidate: Session?
    private final class PreparedProcess {
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
    private var preparedProcess: PreparedProcess?
    // Keep immutable version leases until the actual child has exited.
    private var retiring: [ObjectIdentifier: Session] = [:]
    private var lastAudioDemand = false
    private var recoveryGeneration: UInt64 = 0
    private let memoryPressure: DispatchSourceMemoryPressure
    private var memoryPressureAllowsPreparation = true
    private var idlePreparationWorkItem: DispatchWorkItem?

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

    private func scheduleIdlePreparation() {
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

    private func cancelIdlePreparation() {
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

    private func startPreparedProcess(requestID: UUID, isIdle: Bool) {
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
        transport.onTermination = { [weak self] _ in self?.cancelPreparedProcess(requestID: requestID) }
        armPreparationTimeout(prepared, after: isIdle ? 30 : 15)
        do { try transport.start() }
        catch { cancelPreparedProcess(requestID: requestID) }
    }

    private func armPreparationTimeout(_ prepared: PreparedProcess, after seconds: TimeInterval) {
        prepared.timeout?.cancel()
        let requestID = prepared.requestID
        let timeout = DispatchWorkItem { [weak self] in self?.cancelPreparedProcess(requestID: requestID) }
        prepared.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    func cancelPreparedProcess(requestID: UUID) {
        guard preparedProcess?.requestID == requestID else { return }
        discardPreparedProcess()
    }

    private func discardPreparedProcess() {
        let prepared = preparedProcess
        preparedProcess = nil
        prepared?.timeout?.cancel()
        prepared?.transport.terminate()
    }

    var observation: WebDaemonHostObservation? { (candidate ?? active)?.observation }
    var liveProcessIdentifiers: [Int32] {
        let playback = liveSessions.filter { $0.transport.isRunning }.map { $0.transport.process.processIdentifier }
        if let preparedProcess, preparedProcess.transport.isRunning {
            return playback + [preparedProcess.transport.process.processIdentifier]
        }
        return playback
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

    var hasPendingRequest: Bool { candidate != nil || preparedProcess?.isIdle == false }
    var activeRequest: WallpaperEngine.WebWallpaperLaunchRequest? { active?.executionRequest }
    var activeRecordIDs: Set<String> {
        Set(liveSessions.compactMap { $0.request.recordID })
    }
    var inUsePersistentDataStoreIdentifiers: Set<UUID> {
        liveSessions.reduce(into: Set<UUID>()) { $0.formUnion($1.usage) }
    }
    private var liveSessions: [Session] {
        [active, candidate].compactMap { $0 } + Array(retiring.values)
    }

    func launch(_ request: WallpaperEngine.WebWallpaperLaunchRequest,
                runtimeState: WallpaperEngine.WebWallpaperRuntimeState) {
        recoveryGeneration &+= 1
        launch(request, state: runtimeState, recoveryAttempt: 0)
    }

    private func launch(_ request: WallpaperEngine.WebWallpaperLaunchRequest,
                        state: WallpaperEngine.WebWallpaperRuntimeState, recoveryAttempt: Int) {
        idlePreparationWorkItem?.cancel(); idlePreparationWorkItem = nil
        if let candidate { retire(candidate, gracefully: false) }
        candidate = nil
        let prepared = preparedProcess
        let reusable = prepared?.requestID == request.id && prepared?.transport.isRunning == true
        if reusable {
            preparedProcess = nil
            prepared?.timeout?.cancel()
        } else {
            discardPreparedProcess()
        }
        guard let transport = reusable ? prepared?.transport : makeTransport(requestID: request.id) else {
            eventHandler?(.failed(message: "Web 宿主可执行文件不可用", requestID: request.id)); return
        }
        let session = Session(request: request, state: state, transport: transport, recoveryAttempt: recoveryAttempt)
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
        let timeout = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session, self.candidate === session else { return }
            self.fail(session, message: "Web 壁纸准备超时，保留原壁纸")
        }
        session.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)
        publishAudioDemand(force: true)
        if reusable {
            if prepared?.hello == true { receive(.hello, from: session) }
        } else {
            do { try transport.start() }
            catch { fail(session, message: error.localizedDescription) }
        }
    }

    private func makeTransport(requestID: UUID) -> DaemonProcessTransport? {
        guard let executable = Bundle.main.executableURL else { return nil }
        var arguments = [WebDaemonProtocol.flag, requestID.uuidString]
#if DEBUG
        let inherited = ProcessInfo.processInfo.arguments
        for flag in ["--mwx-debug-web-evidence-dir", "--mwx-debug-web-interaction"] {
            if let index = inherited.firstIndex(of: flag), inherited.indices.contains(index + 1) {
                arguments += [flag, inherited[index + 1]]
            }
        }
#endif
        let transport = DaemonProcessTransport(executableURL: executable, arguments: arguments)
        transport.onError = { text in NSLog("MWX WEB HOST: %@", String(text.prefix(2000))) }
        return transport
    }

    func cancelPreparation(preservingPreparedRequestID: UUID? = nil) {
        recoveryGeneration &+= 1
        idlePreparationWorkItem?.cancel(); idlePreparationWorkItem = nil
        if preparedProcess?.requestID != preservingPreparedRequestID { discardPreparedProcess() }
        if let candidate { retire(candidate, gracefully: false) }
        candidate = nil
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
        for session in [active, candidate].compactMap({ $0 }) {
            session.multiDisplayEnabled = multiDisplayEnabled
            if session.hello { send(.displays(multiDisplayEnabled), to: session) }
        }
    }

    func handle(_ command: WallpaperEngine.WebWallpaperRuntimeCommand) {
        if case .stop = command {
            recoveryGeneration &+= 1
            idlePreparationWorkItem?.cancel(); idlePreparationWorkItem = nil
            discardPreparedProcess()
            let id = candidate?.request.id ?? active?.request.id
            for session in [candidate, active].compactMap({ $0 }) { retire(session) }
            candidate = nil; active = nil
            updateSpectrumTargets()
            lastAudioDemand = false
            if let id { eventHandler?(.stopped(requestID: id)) }
            return
        }
        for session in [active, candidate].compactMap({ $0 }) {
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
                guard candidate == nil || candidate === session else { continue }
                session.propertiesJSON = json
            case .stop: break
            }
            if session.hello { send(.runtime(command), to: session) }
        }
    }

    private func consume(_ data: Data, from session: Session) {
        guard !session.isRetiring, active === session || candidate === session else { return }
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

    private func receive(_ event: WebDaemonEvent, from session: Session) {
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
        case let .prepared(generation):
#if DEBUG
            NSLog("MWX WEB STARTUP request=%@ stage=prepared elapsedMs=%.1f", session.request.id.uuidString,
                  (ProcessInfo.processInfo.systemUptime - session.startedAt) * 1_000)
#endif
            guard candidate === session, generation > (session.preparationGeneration ?? 0) else { return }
            session.preparationGeneration = generation
            send(.commit(generation), to: session)
        case let .committed(generation):
            guard candidate === session else { return }
            guard session.preparationGeneration == generation else {
                fail(session, message: "Web 宿主确认了陈旧的准备代际"); return
            }
            let previous = active
            active = session; candidate = nil
            session.committedAt = ProcessInfo.processInfo.systemUptime
#if DEBUG
            NSLog("MWX WEB STARTUP request=%@ stage=committed elapsedMs=%.1f", session.request.id.uuidString,
                  (ProcessInfo.processInfo.systemUptime - session.startedAt) * 1_000)
#endif
            session.timeout?.cancel(); session.timeout = nil
            if let previous { retire(previous) }
            eventHandler?(.ready(requestID: session.request.id))
            if active === session { scheduleIdlePreparation() }
            publishAudioDemand(force: true)
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

    private func sendMedia(_ snapshot: SystemMediaSnapshot, to session: Session) {
        let web = WebDaemonMediaSnapshot(snapshot, previous: session.lastMediaArtworkKey)
        session.lastMediaArtworkKey = web.artworkKey
        send(.media(web), to: session)
    }

    private func publishAudioDemand(force: Bool = false) {
        updateSpectrumTargets()
        let sessions = [active, candidate].compactMap { $0 }
        let demanded = sessions.contains { $0.audioDemand }
        guard let requestID = candidate?.request.id ?? active?.request.id,
              force || demanded != lastAudioDemand else { return }
        lastAudioDemand = demanded
        eventHandler?(.audioSpectrumDemandChanged(demanded, requestID: requestID))
    }

    private func send(_ command: WebDaemonCommand, to session: Session) {
        guard !session.isRetiring else { return }
        guard let data = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(requestID: session.request.id, payload: command)),
              data.count <= WebDaemonProtocol.maximumFrameBytes else {
            fail(session, message: "Web 宿主命令编码失败或超出限制"); return
        }
        let sent = command.isLatestValue ? session.transport.sendLatest(data) : session.transport.sendRequired(data)
        if !sent { fail(session, message: "Web 宿主命令通道不可用") }
    }

    private func fail(_ session: Session, message: String) {
        guard !session.isRetiring else { return }
        let requestID = session.request.id
        if candidate === session { candidate = nil }
        if active === session { active = nil }
        retire(session)
        eventHandler?(.failed(message: message, requestID: requestID))
        publishAudioDemand(force: true)
    }

    private func retire(_ session: Session, gracefully: Bool = true) {
        guard !session.isRetiring else { return }
        session.timeout?.cancel(); session.timeout = nil
        let captures = session.captures.values
        session.captures.removeAll()
        captures.forEach { $0(nil) }
        SystemMediaService.shared.unsubscribe(session.mediaConsumer)
        session.isRetiring = true
        updateSpectrumTargets()
        if !session.transport.isRunning { session.transport.closeIO(); return }
        retiring[ObjectIdentifier(session)] = session
        if !gracefully { session.transport.terminate(); return }
        if let data = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(requestID: session.request.id, payload: WebDaemonCommand.shutdown)) {
            session.transport.sendRequired(data)
        }
        session.transport.closeInput()
        session.transport.scheduleForcedTermination(after: 1)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            if session.transport.isRunning { kill(session.transport.process.processIdentifier, SIGKILL) }
        }
    }

    private func didExit(_ session: Session) {
        session.timeout?.cancel()
        SystemMediaService.shared.unsubscribe(session.mediaConsumer)
        session.transport.closeIO()
        retiring.removeValue(forKey: ObjectIdentifier(session))
        if session.isRetiring { return }
        if candidate === session { fail(session, message: "Web 壁纸准备进程意外退出"); return }
        guard active === session else { return }
        active = nil
        updateSpectrumTargets()
        let attempt = session.committedAt.map {
            ProcessInfo.processInfo.systemUptime - $0 >= 15 ? 0 : session.recoveryAttempt
        } ?? session.recoveryAttempt
        guard candidate == nil, attempt < 2 else {
            if candidate == nil { eventHandler?(.failed(message: "Web 宿主反复退出", requestID: session.request.id)) }
            return
        }
        let generation = recoveryGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(attempt + 1)) { [weak self] in
            guard let self, self.recoveryGeneration == generation, self.active == nil, self.candidate == nil else { return }
            self.launch(session.executionRequest, state: session.state, recoveryAttempt: attempt + 1)
        }
    }
}
