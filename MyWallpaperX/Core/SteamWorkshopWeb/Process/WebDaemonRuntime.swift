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
    private let inbox = WebDaemonMailbox()
    private let outbox = WebDaemonMailbox()
    private let outputQueue = DispatchQueue(label: "com.mywallpaperx.web-daemon-output")
    private var diagnosticObserver: NSObjectProtocol?
    private var pendingDiagnostics: [WebDaemonDiagnostic] = []
    private var diagnosticFlushScheduled = false
    private var mediaReplayPending = false
    private var desiredVolume: Float = 0
    private var preparationGeneration: UInt64 = 0
    private var didPrepare = false
    private var committed = false
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
        host.defersPresentation = true
        host.presentationInvalidationHandler = { [weak self] in
            guard let self, !self.committed, !self.stopping else { return }
            self.preparationGeneration &+= 1
            self.didPrepare = false
            if self.host.phase == .ready { self.preparePresentation() }
        }
        host.systemMediaDemandHandler = { [weak self] needsMedia, _ in
            self?.mediaReplayPending = false
            self?.emit(.mediaDemand(needsMedia))
        }
        host.eventHandler = { [weak self] event in self?.handleHostEvent(event) }
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
        let inbox = inbox
        let expected = requestID
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var frames = DaemonNewlineFrameBuffer()
            WebDaemonPipeReader.read(from: .standardInput) { chunk in
                for frame in frames.append(chunk) {
                    guard frame.count <= WebDaemonProtocol.maximumFrameBytes,
                          let value = try? JSONDecoder().decode(WebDaemonEnvelope<WebDaemonCommand>.self, from: frame),
                          value.version == WebDaemonProtocol.version, value.requestID == expected,
                          inbox.submit(frame, latest: value.payload.isLatestValue, schedule: {
                              RunLoop.main.perform(inModes: [.common]) { [weak self] in
                                  MainActor.assumeIsolated { self?.drainInbox() }
                              }
                          }) else {
                        return false
                    }
                }
                return frames.pendingByteCount <= WebDaemonProtocol.maximumFrameBytes
            }
            DispatchQueue.main.async { self?.shutdown() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                Darwin.kill(Darwin.getpid(), SIGTERM)
            }
        }
        emit(.hello)
    }

    private func drainInbox() {
        while !stopping, let data = inbox.take(),
              let value = try? JSONDecoder().decode(WebDaemonEnvelope<WebDaemonCommand>.self, from: data) {
            switch value.payload {
            case let .launch(input):
                guard host.currentRequest == nil, input.entryURL.isFileURL, input.rootURL.isFileURL else {
                    emit(.error("invalid-launch")); shutdown(); return
                }
                desiredVolume = input.state.volume
                host.allowedNetworkBridgeHostsResolver = { _ in input.allowedNetworkHosts }
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
            case .inspect: emitObservation()
#if DEBUG
            case .debugMeasureContinuity: measureDebugContinuity()
            case .debugExerciseFailure: exerciseDebugFailure()
#endif
            case let .captureFrame(id): captureFrame(id)
            case let .commit(generation): commit(generation: generation)
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
            if committed { emitUsage(); emitObservation(); return }
            preparePresentation()
        default: flushDiagnostics(); emit(.host(event))
        }
    }

    private func preparePresentation() {
        guard host.phase == .ready, !host.surfaces.isEmpty else { return }
        preparationGeneration &+= 1
        let generation = preparationGeneration
        didPrepare = false
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
                      self.host.surfaces[surface.screenID]?.webView === surface.webView else { return }
                failed = failed || error != nil || image == nil
                remaining -= 1
                guard remaining == 0 else { return }
                if failed { self.emit(.error("web-presentation-preparation-failed")) }
                else { self.didPrepare = true; self.emitUsage(); self.emitObservation(); self.emit(.prepared(generation)) }
            }
        }
    }

    private func commit(generation: UInt64) {
        guard didPrepare, preparationGeneration == generation, !committed, host.phase == .ready else { return }
        committed = true
        host.defersPresentation = false
        host.reassertSurfaceVisibilityAndRuntimeState(orderFront: true)
        host.handle(.setVolume(desiredVolume))
        CATransaction.flush()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopping else { return }
            self.emitObservation()
            self.emit(.committed(generation))
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

    private func emitObservation() {
        emit(.observation(.init(phase: host.phase.rawValue,
            currentRequest: host.currentRequest == nil ? 0 : 1,
            loopbacks: host.loopbackServers.count,
            monitors: (host.localMouseMonitor == nil ? 0 : 1) + (host.globalMouseMonitor == nil ? 0 : 1),
            observers: host.lifecycleObservers.count,
            pointerTimer: host.pointerPollingTimer == nil ? 0 : 1,
            surfaces: host.surfaces.count,
            watchTimer: host.directoryWatchTimer == nil ? 0 : 1,
            watchers: host.directoryWatchersByProperty.count)))
    }

    private func flushDiagnostics() {
        diagnosticFlushScheduled = false
        guard !pendingDiagnostics.isEmpty else { return }
        let events = pendingDiagnostics
        pendingDiagnostics.removeAll(keepingCapacity: true)
        emit(.diagnostics(events))
    }

    private func emitUsage() { emit(.usage(Array(host.inUsePersistentDataStoreIdentifiers))) }

    func emit(_ event: WebDaemonEvent) {
        guard let data = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(requestID: requestID, payload: event)),
              outbox.submit(data, latest: false, schedule: { [weak self] in
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
        guard !stopping else { return }
        stopping = true
        inbox.close()
        host.handle(.stop)
        if let diagnosticObserver { NotificationCenter.default.removeObserver(diagnosticObserver) }
        outbox.close()
        NSApp.terminate(nil)
    }
}
