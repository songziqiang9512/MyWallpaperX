
import AppKit
import Foundation
@main enum Harness {
    @MainActor static func main() throws {
        func ticket(_ kind: WallpaperRuntimeKind) -> PlaybackSwitchTicket { .init(epoch: 1, id: UUID(), runtime: kind) }
        func evidence(display: UInt32, window: UInt32 = 10, pid: Int32) -> PlaybackSurfaceVisibility.Evidence {
            let rect = PlaybackSurfaceVisibility.Rect(CGRect(x: 0, y: 0, width: 200, height: 100))
            return .init(displayID: display, windowID: window, expectedPID: pid, expectedLevel: 2,
                displayExists: true, localFrame: rect, screenFrame: rect, displayFrame: rect,
                localLevel: 2, localAlpha: 1, visible: true, miniaturized: false, onActiveSpace: true,
                serverPID: pid, serverFrame: rect, serverLevel: 2, serverAlpha: 1, onscreen: true)
        }
        func videoEvent(_ type: String, _ execution: WallpaperEngine.VideoSwitchExecution,
                        _ session: WallpaperEngine.DisplayDaemonSession, prepared: Bool = true,
                        requestID: Int? = nil, videoPath: String? = nil) -> DaemonEvent {
            var event = DaemonEvent(type: type, displayID: session.displayID,
                requestID: requestID ?? execution.requests[session.displayID], message: nil, videoPath: videoPath, contentKind: "video")
            event.cohortID = execution.id; event.activationID = execution.activationID
            event.preparationGeneration = prepared ? 1 : nil
            event.visibility = [evidence(display: session.displayID, pid: session.process.processIdentifier)]
            return event
        }
        do {
            let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("prepared-path-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let a = root.appendingPathComponent("a.mp4"), b = root.appendingPathComponent("b.mp4")
            let alias = root.appendingPathComponent("alias.mp4")
            try Data([1]).write(to: a); try Data([2]).write(to: b)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
            let owner = WallpaperEngine()
            var endpoint: PlaybackSwitchEndpoint?, visible = false
            owner.switchPrepared = { _, value in endpoint = value }
            owner.switchVisible = { _, _ in visible = true }
            owner.prepareVideoSwitch(.init(path: alias.path), ticket: ticket(.video), multiDisplayEnabled: true,
                videoFillMode: "fill", shouldLoopCurrentItem: false)
            let execution = owner.videoCandidate!, sessions = execution.sessions.values.sorted { $0.displayID < $1.displayID }
            let first = sessions[0]
            precondition(owner.normalizedPathCalls == 1)
            let capturedPath = a.resolvingSymlinksInPath().standardizedFileURL.path
            precondition(execution.path == capturedPath)
            try FileManager.default.removeItem(at: alias)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: b)
            func consume(_ event: DaemonEvent, _ session: WallpaperEngine.DisplayDaemonSession) throws {
                owner.consumeDaemonEvents(from: try DaemonNewlineJSON.encode(event), for: session)
            }
            var rejected = videoEvent("prepared", execution, first)
            rejected.cohortID = UUID(); try consume(rejected, first)
            rejected = videoEvent("prepared", execution, first, requestID: first.nextRequestID + 100)
            try consume(rejected, first)
            rejected = videoEvent("prepared", execution, first)
            rejected.preparationGeneration = nil; try consume(rejected, first)
            let otherSession = WallpaperEngine.DisplayDaemonSession(displayID: first.displayID,
                transport: .init(executableURL: URL(fileURLWithPath: "/unused"), arguments: []))
            try consume(videoEvent("prepared", execution, first), otherSession)
            let otherDisplay = owner.ensureSession(for: 999)!
            try consume(videoEvent("prepared", execution, otherDisplay), otherDisplay)
            execution.cancelling = true
            try consume(videoEvent("prepared", execution, first), first)
            execution.cancelling = false
            precondition(execution.generations.isEmpty && endpoint == nil,
                "foreign cohort/request/session/display or cancelled preparation was adopted")
            for (index, session) in sessions.enumerated() {
                let event = videoEvent("prepared", execution, session,
                    videoPath: index == 0 ? nil : "/unrelated-diagnostic-path")
                try consume(event, session)
            }
            precondition(endpoint != nil && owner.normalizedPathCalls == 1 && execution.path == capturedPath,
                "prepared payload path caused IO, rejected readiness or replaced the execution authority")
            endpoint!.activate()
            var wrongGeneration = videoEvent("ready", execution, first)
            wrongGeneration.preparationGeneration = 2
            try consume(wrongGeneration, first)
            precondition(execution.visibleDisplays.isEmpty && !visible)
            for session in sessions {
                try consume(videoEvent("ready", execution, session), session)
            }
            precondition(visible && execution.path == capturedPath && owner.normalizedPathCalls == 1)
            endpoint!.finalize()
            precondition(owner.currentContentPath == capturedPath)
        }
        let engine = WallpaperEngine()
        engine.playbackPaused = true
        var videoEndpoints: [UUID: PlaybackSwitchEndpoint] = [:], videoVisible: [UUID] = []
        engine.switchPrepared = { _, endpoint in videoEndpoints[endpoint.id] = endpoint }
        engine.switchVisible = { _, id in videoVisible.append(id) }
        engine.switchFailed = { _, _ in }
        func prepareVideo(_ path: String) -> WallpaperEngine.VideoSwitchExecution {
            engine.prepareVideoSwitch(.init(path: path), ticket: ticket(.video), multiDisplayEnabled: true,
                videoFillMode: "fill", shouldLoopCurrentItem: false)
            return engine.videoCandidate!
        }
        func preparedVideo(_ execution: WallpaperEngine.VideoSwitchExecution) {
            for session in execution.sessions.values {
                engine.consumeDaemonEvents(from: try! DaemonNewlineJSON.encode(videoEvent("prepared", execution, session)), for: session)
            }
        }
        func visibleVideo(_ execution: WallpaperEngine.VideoSwitchExecution) {
            for session in execution.sessions.values {
                engine.consumeDaemonEvents(from: try! DaemonNewlineJSON.encode(videoEvent("ready", execution, session)), for: session)
            }
        }
        let a = prepareVideo("/A")
        for session in a.sessions.values {
            let fields = Set(Mirror(reflecting: session).children.compactMap(\.label))
            precondition(fields.contains("nextRequestID") && fields.contains("latestFinalizedPlayRequestID"))
            precondition(!fields.contains("latestPreparedPlayRequestID") && !fields.contains("latestCommittedPlayRequestID"))
            let diagnostics: Set<String> = ["launched", "latestRequestedPlayRequestID", "latestAcceptedPlayRequestID", "latestReadyPlayRequestID"]
#if DEBUG
            precondition(diagnostics.isSubset(of: fields))
            precondition(session.latestRequestedPlayRequestID == a.requests[session.displayID]
                && session.latestAcceptedPlayRequestID == nil && session.latestReadyPlayRequestID == nil && !session.launched)
#else
            precondition(diagnostics.isDisjoint(with: fields), "Release retained diagnostic session storage")
#endif
            let requests = a.requests
            let sent = session.transport.sent.count
            let launched = DaemonEvent(type: "launched", displayID: session.displayID,
                requestID: nil, message: nil, videoPath: nil, contentKind: nil)
            let staleAccepted = DaemonEvent(type: "accepted", displayID: session.displayID,
                requestID: session.nextRequestID + 1, message: nil, videoPath: a.path, contentKind: "video")
            engine.consumeDaemonEvents(from: try DaemonNewlineJSON.encode(launched)
                + DaemonNewlineJSON.encode(staleAccepted), for: session)
#if DEBUG
            precondition(session.launched && session.latestAcceptedPlayRequestID == nil)
#endif
            engine.consumeDaemonEvents(from: try DaemonNewlineJSON.encode(videoEvent("accepted", a, session)), for: session)
#if DEBUG
            precondition(session.latestAcceptedPlayRequestID == a.requests[session.displayID])
#endif
            precondition(a.requests == requests && a.generations.isEmpty && a.visibleDisplays.isEmpty
                && engine.videoCandidate === a && videoEndpoints.isEmpty && videoVisible.isEmpty
                && session.transport.sent.count == sent, "diagnostic events changed real playback state")
        }
        preparedVideo(a)
        for session in a.sessions.values {
            let command = try JSONDecoder().decode(DaemonCommand.self, from: Data(session.transport.sent.last!.dropLast()))
            precondition(command.action == "pause", "new Video request lost current user pause")
        }
        precondition(videoEndpoints.count == 1 && !a.activated && engine.currentContentPath == nil)
        let endpointA = videoEndpoints[a.id]!
        endpointA.activate(); visibleVideo(a)
#if DEBUG
        precondition(a.sessions.values.allSatisfy { $0.latestReadyPlayRequestID == a.requests[$0.displayID] })
#endif
        precondition(videoVisible == [a.id] && engine.currentContentPath == nil)
        endpointA.finalize(); precondition(engine.currentContentPath == "/A")
        let b = prepareVideo("/B"); preparedVideo(b)
        precondition(engine.currentContentPath == "/A", "preparation overwrote committed Video facts")
        let endpointB = videoEndpoints[b.id]!
        endpointB.activate(); visibleVideo(b)
        let queuedVideoTicket = ticket(.video)
        engine.prepareVideoSwitch(.init(path: "/queued"), ticket: queuedVideoTicket,
            multiDisplayEnabled: true, videoFillMode: "fill", shouldLoopCurrentItem: false)
        precondition(engine.videoCandidate === b && engine.deferredVideoPreparation?.ticket == queuedVideoTicket && !b.cancelling)
        var queueCancelled = false
        engine.cancelSwitch(ticket: queuedVideoTicket) { queueCancelled = true }
        precondition(queueCancelled && engine.deferredVideoPreparation == nil && engine.videoCandidate === b)
        var sameTypeRetired = false
        endpointA.retire(nil) { sameTypeRetired = true }
        precondition(sameTypeRetired)
        endpointB.finalize()
        precondition(engine.currentContentPath == "/B")
        precondition(engine.displaySessions.count == 2 && engine.displaySessions.values.allSatisfy { !$0.transport.stopRequested },
            "old same-kind retire stopped the successor's shared helper")
        let c = prepareVideo("/C"); var cancelled = false
        engine.cancelSwitch(ticket: c.ticket) { cancelled = true }
        precondition(!cancelled)
        let d = prepareVideo("/D")
        for session in c.sessions.values {
            engine.consumeDaemonEvents(from: try DaemonNewlineJSON.encode(videoEvent("cancelled", c, session, prepared: false)), for: session)
        }
        precondition(cancelled && engine.videoCandidate === d && engine.currentContentPath == "/B")
        visibleVideo(c); precondition(engine.currentContentPath == "/B")
        var videoActivity: Bool? = nil
        endpointB.setOutputActive(false) { videoActivity = $0 }
        for session in b.sessions.values {
            let command = try JSONDecoder().decode(DaemonCommand.self, from: Data(session.transport.sent.last!.dropLast()))
            var ack = videoEvent("outputActivityChanged", b, session)
            ack.activityID = command.activityID; ack.outputActive = false
            engine.consumeDaemonEvents(from: try DaemonNewlineJSON.encode(ack), for: session)
        }
        precondition(videoActivity == true && engine.playbackPaused)

        func prepareEarlyVideo(_ owner: WallpaperEngine, _ path: String) -> WallpaperEngine.VideoSwitchExecution {
            owner.prepareVideoSwitch(.init(path: path), ticket: ticket(.video), multiDisplayEnabled: false,
                videoFillMode: "fill", shouldLoopCurrentItem: false)
            return owner.videoCandidate!
        }
        let failedEngine = WallpaperEngine()
        failedEngine.displayIDs = [1]
        let failed = prepareEarlyVideo(failedEngine, "/failed")
        let failedSession = failed.sessions[1]!
        var failures = 0
        failedEngine.switchFailed = { candidate, message in
            precondition(candidate == failed.ticket && message == "cannot decode")
            failures += 1
        }
        var failure = DaemonEvent(type: "failed", displayID: 1,
            requestID: failed.requests[1], message: "cannot decode", videoPath: failed.path, contentKind: "video")
        failure.cohortID = UUID()
        failedEngine.consumeDaemonEvents(from: try DaemonNewlineJSON.encode(failure), for: failedSession)
        precondition(failures == 0 && !failed.cancelling, "unowned failure changed current playback")
        failure.cohortID = failed.id
        failedEngine.consumeDaemonEvents(from: try DaemonNewlineJSON.encode(failure), for: failedSession)
        precondition(failures == 1 && failed.cancelling)
        failedEngine.consumeDaemonEvents(from: try DaemonNewlineJSON.encode(
            videoEvent("cancelled", failed, failedSession, prepared: false)), for: failedSession)
        precondition(failedEngine.videoCandidate == nil && failedSession.transport.stopRequested)
        failedSession.transport.end()

        let orphanEngine = WallpaperEngine()
        orphanEngine.displayIDs = [1]
        let orphan = prepareEarlyVideo(orphanEngine, "/orphan")
        let orphanSession = orphan.sessions[1]!
        var orphanCancelled = false
        orphanEngine.cancelSwitch(ticket: orphan.ticket) { orphanCancelled = true }
        precondition(!orphanCancelled && !orphanSession.transport.stopRequested)
        orphanEngine.videoDidCancel(videoEvent("cancelled", orphan, orphanSession, prepared: false), session: orphanSession)
        precondition(orphanCancelled && orphanEngine.displaySessions.isEmpty && orphanSession.transport.stopRequested,
            "cancelled first candidate left an ownerless helper in the display table")
        precondition(orphanSession.process.isRunning, "cancellation ACK was mistaken for physical exit")
        orphanSession.transport.end()
        precondition(orphanEngine.displaySessions.isEmpty && orphanEngine.videoCandidate == nil)

        let retainedEngine = WallpaperEngine()
        retainedEngine.displayIDs = [1]
        var retainedEndpoint: PlaybackSwitchEndpoint?
        retainedEngine.switchPrepared = { _, endpoint in retainedEndpoint = endpoint }
        let retainedA = prepareEarlyVideo(retainedEngine, "/retained-A")
        let retainedSession = retainedA.sessions[1]!
        retainedEngine.videoDidPrepare(videoEvent("prepared", retainedA, retainedSession), session: retainedSession)
        retainedEndpoint!.activate()
        retainedEngine.videoDidBecomeVisible(videoEvent("ready", retainedA, retainedSession), session: retainedSession)
        retainedEndpoint!.finalize()
        let cancelledB = prepareEarlyVideo(retainedEngine, "/cancelled-B")
        retainedEngine.cancelSwitch(ticket: cancelledB.ticket) {}
        retainedEngine.videoDidCancel(videoEvent("cancelled", cancelledB, retainedSession, prepared: false), session: retainedSession)
        precondition(retainedEngine.activeVideoExecution === retainedA
            && retainedEngine.displaySessions[1] === retainedSession && !retainedSession.transport.stopRequested,
            "cancelling B stopped the helper still owned by committed A")

        let successorEngine = WallpaperEngine()
        successorEngine.displayIDs = [1]
        let obsoleteB = prepareEarlyVideo(successorEngine, "/obsolete-B")
        successorEngine.cancelSwitch(ticket: obsoleteB.ticket) {}
        let successorC = prepareEarlyVideo(successorEngine, "/successor-C")
        let successorSession = successorC.sessions[1]!
        successorEngine.videoDidCancel(videoEvent("cancelled", obsoleteB, successorSession, prepared: false), session: successorSession)
        precondition(successorEngine.videoCandidate === successorC
            && successorEngine.displaySessions[1] === successorSession && !successorSession.transport.stopRequested,
            "late B cancellation stopped the helper now owned by C")

        let adapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        var webEndpoints: [UUID: PlaybackSwitchEndpoint] = [:], webVisible: [UUID] = []
        var audioDemands: [Bool] = []
        adapter.eventHandler = { event in
            if case let .audioSpectrumDemandChanged(demand, _) = event { audioDemands.append(demand) }
        }
        adapter.switchPrepared = { _, endpoint in webEndpoints[endpoint.id] = endpoint }
        adapter.switchVisible = { _, id in webVisible.append(id) }
        func prepareWeb(_ name: String) -> WebDaemonHostAdapter.Session {
            let request = WallpaperEngine.WebWallpaperLaunchRequest(id: UUID(), entryURL: URL(fileURLWithPath: "/" + name),
                rootURL: URL(fileURLWithPath: "/"), propertiesJSON: "{}", source: .steamWorkshop,
                recordID: name, language: "zh", runtimeProfile: .standard, multiDisplayEnabled: false,
                allowedNetworkHosts: ["prepared-author.example"])
            adapter.prepareSwitch(ticket: ticket(.web), request: request,
                runtimeState: .init(paused: false, volume: 0.8, playbackRate: 1, spectrumLevels: nil))
            let session = adapter.candidate!
            adapter.receive(.hello, from: session)
            let launch = try! JSONDecoder().decode(WebDaemonEnvelope<WebDaemonCommand>.self, from: session.transport.sent[0])
            guard case let .launch(input) = launch.payload else { fatalError("expected launch command") }
            precondition(input.allowedNetworkHosts == ["prepared-author.example"]
                && session.executionRequest.allowedNetworkHosts == request.allowedNetworkHosts,
                "hello uses the prepared request hosts without a descriptor resolver")
            return session
        }
        func preparedWeb(_ session: WebDaemonHostAdapter.Session) {
            adapter.receive(.host(.ready(requestID: session.request.id)), from: session)
            precondition(webEndpoints[session.executionID] == nil, "host ready authorized a product switch")
            adapter.receive(.preparationCohort(.init(generation: 1, surfaces: [
                .init(displayID: 1, surfaceID: UUID(), navigationGeneration: 1, windowID: 10)
            ])), from: session)
        }
        func visibleWeb(_ session: WebDaemonHostAdapter.Session) {
            adapter.receive(.activationConfirmed(session.activationIdentity!, [evidence(display: 1, pid: session.transport.process.processIdentifier)]), from: session)
        }
        let abandoned = prepareWeb("abandoned")
        adapter.receive(.host(.audioSpectrumDemandChanged(true, requestID: abandoned.request.id)), from: abandoned)
        precondition(adapter.audioSpectrumRequested && audioDemands.last == true)
        adapter.cancelSwitch(ticket: abandoned.ticket) {}
        precondition(adapter.active == nil && adapter.candidate == nil
            && !adapter.audioSpectrumRequested && audioDemands.last == false,
            "last uncommitted Web cancellation retained shared audio capture")
        abandoned.transport.end()

        let wa = prepareWeb("WA"); preparedWeb(wa)
#if DEBUG
        let measuresStartup = ProcessInfo.processInfo.arguments.contains("--mwx-debug-web-startup-report")
        precondition((wa.startupTiming != nil) == measuresStartup)
        precondition(wa.transport.arguments.contains("--mwx-debug-web-startup-timing") == measuresStartup)
        precondition(wa.startupTiming?.preparedCohortAcceptedAt != nil || !measuresStartup)
        precondition(wa.startupTiming?.launchEnqueuedAt != nil || !measuresStartup)
        precondition(wa.startupTiming?.activationSentAt == nil)
#endif
        adapter.receive(.host(.audioSpectrumDemandChanged(true, requestID: wa.request.id)), from: wa)
        let webA = webEndpoints[wa.executionID]!
        precondition(adapter.active == nil)
        webA.activate()
#if DEBUG
        let sentAt = wa.startupTiming?.activationSentAt
        precondition((sentAt != nil) == measuresStartup)
        webA.activate()
        precondition(wa.startupTiming?.activationSentAt == sentAt, "duplicate activation rewrote its event time")
        func startupObservationData(_ timing: WebDaemonStartupTimingObservation, requestID: UUID) throws -> Data {
            let observation = WebDaemonHostObservation(phase: "ready", currentRequest: 1,
                loopbacks: 0, monitors: 0, observers: 0, pointerTimer: 0, surfaces: 1,
                watchTimer: 0, watchers: 0, startupTiming: timing)
            return try DaemonNewlineJSON.encode(WebDaemonEnvelope(
                requestID: requestID, payload: WebDaemonEvent.observation(observation)))
        }
        let identity = wa.activationIdentity!
        let surfaceIdentity = wa.preparedCohort!.surfaces.first!
        let observedSurface = WebDaemonStartupSurfaceTimingObservation(displayID: surfaceIdentity.displayID,
            creationStartedAt: 2.5, surfaceID: surfaceIdentity.surfaceID,
            navigationGeneration: surfaceIdentity.navigationGeneration,
            creationCompletedAt: 3, loadIssuedAt: 3.5, readyObservedAt: 4, readySource: "didFinish")
        precondition(observedSurface.matching(surfaceIdentity) != nil)
        precondition(observedSurface.matching(.init(displayID: surfaceIdentity.displayID,
            surfaceID: UUID(), navigationGeneration: surfaceIdentity.navigationGeneration, windowID: 10)) == nil,
            "replaced surface inherited old preparation telemetry")
        precondition(observedSurface.matching(.init(displayID: surfaceIdentity.displayID,
            surfaceID: surfaceIdentity.surfaceID, navigationGeneration: surfaceIdentity.navigationGeneration + 1, windowID: 10)) == nil,
            "replacement document inherited old load/ready telemetry")
        let wrongActivation = WebDaemonStartupTimingObservation(
            identity: .init(generation: identity.generation, activationID: UUID()), activateReceivedAt: 1)
        adapter.consume(try startupObservationData(wrongActivation, requestID: wa.request.id), from: wa)
        precondition(wa.matchingChildStartupTiming == nil, "stale activation telemetry became matching evidence")
        var preparation = WebDaemonPreparationTimingObservation(launchReceivedAt: 2,
            generation: identity.generation, surfaces: wa.preparedCohort!.surfaces,
            hostReadyAt: 4, snapshotRequestedAt: 5, snapshotCompletedAt: 7,
            policyWaitStartedAt: 7.5, policyAcceptedAt: 8,
            surfaceTimings: [observedSurface])
        let producerTiming = WebDaemonStartupTimingObservation(identity: identity, activateReceivedAt: 10,
            nativePolicyAcceptedAt: 30, visibilityFirstConfirmedAt: 20,
            firstVisibilityRetryAt: 15, firstVisibilityRetryReason: "window-not-onscreen",
            preparation: preparation)
        preparation.snapshotCompletedAt = 999
        adapter.consume(try startupObservationData(producerTiming, requestID: wa.request.id), from: wa)
        precondition(!wa.visibilityConfirmed && webVisible.isEmpty, "diagnostics authorized a product switch")
        if measuresStartup {
            precondition(wa.matchingChildStartupTiming?.activateReceivedAt == 10
                && wa.matchingChildStartupTiming?.nativePolicyAcceptedAt == 30
                && wa.matchingChildStartupTiming?.visibilityFirstConfirmedAt == 20
                && wa.matchingChildStartupTiming?.firstVisibilityRetryAt == 15
                && wa.matchingChildStartupTiming?.firstVisibilityRetryReason == "window-not-onscreen",
                "IPC replaced producer times with receive time or forced media/visibility order")
            let transported = wa.matchingChildStartupTiming!.preparation!
            precondition(transported.generation == identity.generation
                && transported.surfaces == wa.preparedCohort!.surfaces
                && transported.launchReceivedAt == 2 && transported.snapshotCompletedAt == 7
                && transported.policyWaitStartedAt == 7.5 && transported.policyAcceptedAt == 8
                && transported.surfaceTimings.first?.loadIssuedAt == 3.5
                && transported.surfaceTimings.first?.readySource == "didFinish",
                "preparation snapshot lost cohort, producer time or ready semantics in transport")
        } else { precondition(wa.matchingChildStartupTiming == nil) }
        // Execute the actual initial-load, recovery and page-navigation writers.
        let producer = DedicatedWebWallpaperHostPlaceholderAdapter()
        producer.currentRequest = wa.request
        let producerSurface = DedicatedWebWallpaperHostPlaceholderAdapter.HostSurface(screenID: 1, webView: WKWebView())
        producer.surfaces[1] = producerSurface
        func seedCreation() {
            producer.debugStartupSurfaceTimings?[1] = .init(displayID: 1, creationStartedAt: 1,
                surfaceID: producerSurface.id, creationCompletedAt: 2)
        }
        seedCreation()
        producer.loadTrackedNavigation(on: producerSurface, request: wa.request,
            localEntryURL: wa.request.entryURL, stopCurrent: false) { precondition($0) }
        let firstNavigationGeneration = producer.navigationOwnershipByScreen[1]!.generation
        let firstIdentity = WebDaemonSurfaceIdentity(displayID: 1, surfaceID: producerSurface.id,
            navigationGeneration: firstNavigationGeneration, windowID: 10)
        precondition(producer.debugStartupSurfaceTimings?[1]?.loadIssuedAt != nil
            && producer.debugStartupSurfaceTimings?[1]?.matching(firstIdentity) != nil)
        precondition(producer.reloadTrackedNavigation(on: producerSurface, requestID: wa.request.id))
        precondition(producer.debugStartupSurfaceTimings?[1] == nil,
            "WebContent recovery retained initial document preparation times")
        seedCreation()
        producer.loadTrackedNavigation(on: producerSurface, request: wa.request,
            localEntryURL: wa.request.entryURL, stopCurrent: false) { precondition($0) }
        producer.readyScreenIDs.insert(1)
        precondition(producer.screenIDForStartedNavigation(WKNavigation(), webView: producerSurface.webView) == 1)
        precondition(producer.debugStartupSurfaceTimings?[1] == nil,
            "page navigation retained initial document preparation times")
        let invalidTelemetryAdapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        invalidTelemetryAdapter.prepareSwitch(ticket: ticket(.web), request: wa.executionRequest, runtimeState: wa.state)
        let invalidTelemetrySession = invalidTelemetryAdapter.candidate!
        invalidTelemetryAdapter.consume(try startupObservationData(producerTiming, requestID: UUID()),
            from: invalidTelemetrySession)
        precondition(invalidTelemetrySession.observation == nil && invalidTelemetryAdapter.candidate == nil,
            "wrong request telemetry bypassed normal protocol rejection")
#endif
        visibleWeb(wa)
        precondition(webVisible == [wa.executionID] && adapter.active == nil)
        webA.finalize(); precondition(adapter.active === wa)
        let wb = prepareWeb("WB"); var earlyCancelled = false
        adapter.cancelSwitch(ticket: wb.ticket) { earlyCancelled = true }
        precondition(!earlyCancelled && wb.transport.stopRequested && adapter.active === wa)
        wb.transport.end(); precondition(earlyCancelled && adapter.active === wa)
        let wc = prepareWeb("WC"); preparedWeb(wc)
        let webC = webEndpoints[wc.executionID]!
        webC.activate(); var webCancelled = false
        webC.cancel { webCancelled = true }
        adapter.receive(.activationCancelled(.init(generation: 1, activationID: UUID())), from: wc)
        precondition(!webCancelled)
        adapter.receive(.activationCancelled(wc.activationIdentity!), from: wc)
        precondition(webCancelled && adapter.active === wa)
        let wd = prepareWeb("WD"); preparedWeb(wd)
        adapter.receive(.host(.audioSpectrumDemandChanged(true, requestID: wd.request.id)), from: wd)
        let webD = webEndpoints[wd.executionID]!
        webD.activate(); visibleWeb(wd)
        let queuedWebTicket = ticket(.web)
        adapter.prepareSwitch(ticket: queuedWebTicket, request: wd.executionRequest, runtimeState: wd.state)
        precondition(adapter.candidate === wd && !wd.isCancelling && adapter.deferredPreparation?.ticket == queuedWebTicket)
        var webQueueCancelled = false
        adapter.cancelSwitch(ticket: queuedWebTicket) { webQueueCancelled = true }
        precondition(webQueueCancelled && adapter.deferredPreparation == nil && adapter.candidate === wd)
        precondition(adapter.active === wa && !wa.transport.stopRequested)
        var webRetired = false
        webA.retire(nil) { webRetired = true }
        precondition(!webRetired && wa.transport.stopRequested && adapter.candidate === wd && !wd.transport.stopRequested)
        wa.transport.end(); precondition(webRetired)
        precondition(adapter.audioSpectrumRequested && audioDemands.last == true,
            "retiring old Web withdrew the successor's live audio demand")
        webD.finalize(); precondition(adapter.active === wd)
        var outputDone: Bool? = nil
        webD.setOutputActive(false) { outputDone = $0 }
        let activity = wd.outputActivityCompletions.keys.first!
        adapter.receive(.outputActivityChanged(activity, false), from: wd)
        precondition(outputDone == true && wd.state.volume == 0.8 && !wd.state.paused)
        outputDone = nil
        webD.setOutputActive(false) { outputDone = $0 }
        let deadline = Date().addingTimeInterval(2.2)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        precondition(wd.transport.stopRequested && outputDone == nil, "ACK timeout completed before actual exit")
        wd.transport.end(); precondition(outputDone == true)

        // A committed renderer can die while another page is preparing. Its
        // recovery input must survive that candidate and restart the same ticket
        // after cancellation; retiring the old endpoint revokes that recovery.
        let recoveryAdapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        let originalTicket = ticket(.web)
        let dead = WebDaemonHostAdapter.Session(request: wa.executionRequest, state: wa.state,
            transport: .init(executableURL: URL(fileURLWithPath: "/unused"), arguments: []),
            recoveryAttempt: 0, ticket: originalTicket)
        dead.committedAt = ProcessInfo.processInfo.systemUptime
        let selectedResource = WebWallpaperResourceGrant(kind: .file, url: URL(fileURLWithPath: "/external/selected.mp3"))
        dead.resourceGrants = [selectedResource]
        let propertyEngine = WallpaperEngine()
        propertyEngine.dedicatedWebHostAdapter = recoveryAdapter
        propertyEngine.currentPlaybackContentKind = .web
        propertyEngine.currentWebRequestID = dead.request.id
        propertyEngine.currentWebPropertiesJSON = "{}"
        recoveryAdapter.active = dead
        recoveryAdapter.prepareSwitch(ticket: ticket(.web), request: wd.executionRequest, runtimeState: wd.state)
        let preparing = recoveryAdapter.candidate!
        dead.transport.end(); recoveryAdapter.didExit(dead)
        precondition(recoveryAdapter.pendingRecovery?.session === dead && recoveryAdapter.candidate === preparing)
        precondition(propertyEngine.currentWebResourceGrants == [selectedResource], "committed recovery input lost its authority snapshot")
        let unrelatedProperties = preparing.propertiesJSON
        let unrelatedGrants = preparing.resourceGrants
        propertyEngine.updateCurrentWebWallpaperProperties("{\"image\":{\"value\":\"\"}}", resourceGrants: [], resourcesChanged: true)
        precondition(dead.resourceGrants.isEmpty && dead.resourceRevision == 1 && dead.propertyRevision == 1,
            "clear during didExit/pendingRecovery was discarded")
        precondition(preparing.propertiesJSON == unrelatedProperties && preparing.resourceGrants == unrelatedGrants,
            "committed clear modified a new user selection")
        var failedCandidateCancelled = false
        recoveryAdapter.cancelSwitch(ticket: preparing.ticket) { failedCandidateCancelled = true }
        preparing.transport.end(); precondition(failedCandidateCancelled)
        let recoveryDeadline = Date().addingTimeInterval(0.35)
        while Date() < recoveryDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        let restarted = recoveryAdapter.candidate!
        precondition(restarted.ticket == originalTicket && restarted.executionID != dead.executionID)
        precondition(restarted.executionRequest.allowedNetworkHosts == dead.executionRequest.allowedNetworkHosts,
            "recovery preserves the same author host snapshot")
        precondition(restarted.resourceGrants.isEmpty && restarted.resourceRevision == 1,
            "recovery resurrected an external grant cleared during its wait")
        propertyEngine.updateCurrentWebWallpaperProperties("{\"image\":{\"value\":\"Default\"}}", resourceGrants: [], resourcesChanged: true)
        precondition(restarted.resourceRevision == 2 && restarted.propertyRevision == 2,
            "reset while the committed request's recovery candidate prepared was discarded")
        recoveryAdapter.handle(.applyProperties(.init(requestID: dead.request.id, revision: 3, resourceRevision: 0,
            propertiesJSON: "{}", resourceGrants: [selectedResource])))
        precondition(restarted.resourceGrants.isEmpty && restarted.resourceRevision == 2,
            "stale recovery update expanded current authority")
        precondition(recoveryAdapter.propertyUpdateSession(for: preparing.request.id) == nil,
            "old uncommitted selection became a committed update target")
        var deadRetired = false
        recoveryAdapter.retireEndpoint(dead) { deadRetired = true }
        precondition(deadRetired && recoveryAdapter.pendingRecovery == nil && recoveryAdapter.candidate == nil
            && restarted.transport.stopRequested, "retired committed endpoint resurrected its recovery")

        // Delay all child processing after B.activate. A display toggle must
        // retain B's endpoint cancellation barrier while C becomes prepared.
        let toggleAdapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        var transaction = PlaybackSwitchTransaction()
        var toggleEndpoints: [UUID: PlaybackSwitchEndpoint] = [:]
        var executeEffects: (([PlaybackSwitchTransaction.Effect]) -> Void)!
        executeEffects = { effects in
            for effect in effects {
                switch effect {
                case let .activate(selection):
                    toggleEndpoints[selection.executionID!]?.activate()
                case let .output(operation):
                    toggleEndpoints[operation.executionID]?.setOutputActive(operation.active) { succeeded in
                        executeEffects(transaction.activityCompleted(operation, succeeded: succeeded))
                    }
                case let .finalize(selection):
                    toggleEndpoints[selection.executionID!]?.finalize()
                case let .cancel(barrier, selection):
                    let finish = { executeEffects(transaction.cancelled(barrier)) }
                    if let id = selection.executionID, let endpoint = toggleEndpoints[id] {
                        endpoint.cancel(finish)
                    } else {
                        toggleAdapter.cancelSwitch(ticket: selection.ticket, completion: finish)
                    }
                default: break
                }
            }
        }
        toggleAdapter.switchPrepared = { ticket, endpoint in
            toggleEndpoints[endpoint.id] = endpoint
            executeEffects(transaction.prepared(ticket, executionID: endpoint.id))
        }
        toggleAdapter.switchVisible = { ticket, executionID in
            executeEffects(transaction.visible(ticket, executionID: executionID))
        }
        func feedPrepared(_ adapter: WebDaemonHostAdapter, _ session: WebDaemonHostAdapter.Session) {
            adapter.receive(.hello, from: session)
            adapter.receive(.preparationCohort(.init(generation: 1, surfaces: [
                .init(displayID: 1, surfaceID: UUID(), navigationGeneration: 1, windowID: 10)
            ])), from: session)
        }
        let (committedTicket, committedEffects) = transaction.begin(.web)
        executeEffects(committedEffects)
        toggleAdapter.prepareSwitch(ticket: committedTicket, request: wa.executionRequest, runtimeState: wa.state)
        let committedA = toggleAdapter.candidate!
        feedPrepared(toggleAdapter, committedA)
        toggleAdapter.receive(.activationConfirmed(committedA.activationIdentity!,
            [evidence(display: 1, pid: committedA.transport.process.processIdentifier)]), from: committedA)
        precondition(toggleAdapter.active === committedA && transaction.committed?.ticket == committedTicket)
        let (toggleTicket, initialEffects) = transaction.begin(.web)
        executeEffects(initialEffects)
        toggleAdapter.prepareSwitch(ticket: toggleTicket, request: wb.executionRequest, runtimeState: wb.state)
        let oldToggle = toggleAdapter.candidate!
        feedPrepared(toggleAdapter, oldToggle)
        precondition(!oldToggle.activationSent)
#if DEBUG
        precondition(oldToggle.startupTiming?.activationSentAt == nil,
            "prepared telemetry skipped the old output barrier")
#endif
        let deactivateA = committedA.outputActivityCompletions.first!
        precondition(!deactivateA.value.desired)
        toggleAdapter.receive(.outputActivityChanged(deactivateA.key, false), from: committedA)
        precondition(oldToggle.activationSent)
#if DEBUG
        precondition((oldToggle.startupTiming?.activationSentAt != nil) == measuresStartup)
#endif
        let oldExecutionID = oldToggle.executionID, oldActivation = oldToggle.activationIdentity!
        toggleAdapter.updateDisplayConfiguration(multiDisplayEnabled: true)
        precondition(oldToggle.executionID == oldExecutionID && oldToggle.activationIdentity == oldActivation
            && oldToggle.isRetiring && oldToggle.transport.stopRequested,
            "display update replaced the endpoint identity before revoking the original process")
        let (cTicket, cEffects) = transaction.begin(.web)
        executeEffects(cEffects)
        toggleAdapter.prepareSwitch(ticket: cTicket, request: wd.executionRequest, runtimeState: wd.state)
        let nextC = toggleAdapter.candidate!
        feedPrepared(toggleAdapter, nextC)
        precondition(!transaction.cancellations.isEmpty && !nextC.activationSent,
            "C activated before delayed B acknowledged cancellation or exited")
        let delayedB = WebDaemonEvent.activationConfirmed(oldActivation,
            [evidence(display: 1, pid: oldToggle.transport.process.processIdentifier)])
        toggleAdapter.consume(try DaemonNewlineJSON.encode(WebDaemonEnvelope(
            requestID: oldToggle.request.id, payload: delayedB)), from: oldToggle)
        precondition(!transaction.cancellations.isEmpty && !nextC.activationSent)
        oldToggle.transport.end()
        precondition(transaction.cancellations.isEmpty && nextC.activationSent
            && toggleAdapter.candidate === nextC && toggleAdapter.displayRebuildSource == nil,
            "old display rebuild stole C after its cancellation barrier completed")

        // With no superseding intent, the same ticket is rebuilt only after
        // old physical exit, with the latest display and pause/volume policy.
        let rebuildAdapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        let rebuildTicket = ticket(.web)
        rebuildAdapter.switchPrepared = { _, _ in }
        rebuildAdapter.prepareSwitch(ticket: rebuildTicket, request: wa.executionRequest, runtimeState: wa.state)
        let beforeRebuild = rebuildAdapter.candidate!
        feedPrepared(rebuildAdapter, beforeRebuild)
        rebuildAdapter.updateDisplayConfiguration(multiDisplayEnabled: true)
        precondition(rebuildAdapter.candidate == nil && rebuildAdapter.displayRebuildSource === beforeRebuild)
        rebuildAdapter.handle(.pause); rebuildAdapter.handle(.setVolume(0.3))
        beforeRebuild.transport.end()
        let afterRebuild = rebuildAdapter.candidate!
        precondition(afterRebuild.ticket == rebuildTicket && afterRebuild.executionID != beforeRebuild.executionID
            && afterRebuild.multiDisplayEnabled && afterRebuild.state.paused && afterRebuild.state.volume == 0.3)
        precondition(afterRebuild.executionRequest.allowedNetworkHosts == beforeRebuild.executionRequest.allowedNetworkHosts,
            "display-cohort rebuilding preserves prepared author hosts")

        let optional = WebDaemonHostAdapter(spectrumDelivery: .init())
        var mayPrewarm = true
        optional.mayPrepareIdleProcess = { mayPrewarm }
        optional.scheduleIdlePreparation()
        let scheduled = optional.idlePreparationWorkItem!
        optional.active = wa
        mayPrewarm = false
        scheduled.perform()
        precondition(optional.preparedProcess == nil,
            "optional timer must consult current Scene retention at actual admission")
        optional.prepareIdleProcess()
        precondition(optional.preparedProcess == nil)
        let explicitRequest = UUID()
        optional.prepareProcess(requestID: explicitRequest)
        let claimed = optional.preparedProcess!
        precondition(claimed.requestID == explicitRequest && !claimed.isIdle,
            "Scene optional-prewarm predicate cannot block a real Web request")
        optional.cancelIdlePreparation()
        precondition(optional.preparedProcess === claimed && !claimed.transport.stopRequested,
            "non-Web intent cleanup cannot cancel an already claimed real request")
        optional.cancelPreparedProcess(requestID: explicitRequest)
        claimed.transport.end()
        mayPrewarm = true
        optional.prepareIdleProcess()
        let unused = optional.preparedProcess!
        optional.scheduleIdlePreparation()
        optional.cancelIdlePreparation()
        precondition(optional.preparedProcess == nil && optional.idlePreparationWorkItem == nil
            && unused.transport.stopRequested && optional.retiringPrepared[ObjectIdentifier(unused)] === unused)
        unused.transport.end()
        precondition(optional.retiringPrepared.isEmpty)
        optional.active = nil

        print("playback-switch-endpoints-pass")
    }
}
