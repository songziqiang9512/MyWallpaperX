import AppKit
import Combine
import QuartzCore

extension WallpaperManager {
    /// Shell supplies a captured page/source value; changing the UI later does
    /// not change this accepted selection's source or original product ticket.
    @discardableResult
    func requestLibraryPlayback(reference: WallpaperReference, from snapshot: WallpaperPlaybackSequence.Snapshot,
                                cause: WallpaperPlaybackCause = .userSelection) -> PlaybackSwitchTicket? {
        guard libraryPlaybackDispatcher != nil,
              let proposal = libraryPlaybackSequence.proposeSelection(reference, from: snapshot, cause: cause) else { return nil }
        return dispatchLibraryPlayback(proposal)
    }

    /// Existing source entry points request an explicit single/download source.
    /// Absence/unavailability is a refusal, never a different library fallback.
    @discardableResult
    func requestLibraryPlayback(reference: WallpaperReference, source: WallpaperPlaybackSequence.Source? = nil,
                                cause: WallpaperPlaybackCause = .userSelection) -> PlaybackSwitchTicket? {
        let requestedSource = source ?? .single(reference)
        if case .single(let requested) = requestedSource, requested != reference { return nil }
        guard let snapshot = libraryPlaybackSnapshotProvider?(reference, requestedSource, cause) else { return nil }
        let target: WallpaperReference
        if case .single = requestedSource, case .single(let canonical) = snapshot.source {
            // The injected provider resolves aliases through the relationship
            // authority. A page must never substitute its first item here.
            target = canonical
        } else {
            guard snapshot.source == requestedSource else { return nil }
            target = reference
        }
        return requestLibraryPlayback(reference: target, from: snapshot, cause: cause)
    }

    @discardableResult
    func dispatchLibraryPlayback(_ proposal: WallpaperPlaybackSequence.Proposal,
                                 prepare: ((WallpaperPlaybackSequence.Pending) -> Bool)? = nil) -> PlaybackSwitchTicket? {
        guard proposal.rotationGeneration == libraryPlaybackSequence.rotationGeneration,
              let runtime = proposal.entry.runtime, let dispatch = prepare ?? libraryPlaybackDispatcher else { return nil }
        // Retire the old Video-only clock as soon as this new source is accepted.
        stopAutoSwitchTimer()
        libraryRotationDeadline.freezeForPreparation(now: CACurrentMediaTime())
        let epoch = beginPlaybackIntent(runtime: runtime)
        guard let ticket = playbackSwitch.pending?.selection.ticket, ticket.epoch == epoch else { return nil }
        guard libraryPlaybackSequence.stage(proposal, ticket: ticket), let pending = libraryPlaybackSequence.pending else {
            libraryRotationDeadline.preparationFailed(now: CACurrentMediaTime())
            switchFailed(ticket, reason: "播放来源已变化，已保留原壁纸")
            return nil
        }
        guard dispatch(pending) else {
            switchFailed(ticket, reason: "壁纸当前不可用，已保留原壁纸")
            return nil
        }
        return ticket
    }

    func acceptsLibraryPlayback(_ pending: WallpaperPlaybackSequence.Pending) -> Bool {
        playbackSwitch.pending?.selection.ticket == pending.ticket && libraryPlaybackSequence.pending == pending
    }

    func handleLibraryPlaybackPause(_ isPaused: Bool) {
        libraryRotationDeadline.setPause(effective: isPaused, now: CACurrentMediaTime())
        if libraryPlaybackSequence.committed != nil || libraryPlaybackSequence.pending != nil {
            rescheduleLibraryRotationTimer()
        }
        if let selection = playbackSwitch.committed {
            isPlaying = selection.ticket.runtime != .systemStill && !isPaused
        }
    }

    enum RuntimeSwitchSelection {
        case video(VideoWallpaper)
        case web(String?)
        case scene(String?)
        case systemStill(URL)
    }

    func configureRuntimeSwitching() {
        guard !runtimeSwitchingConfigured else { return }
        runtimeSwitchingConfigured = true
        let engine = WallpaperEngine.shared
        engine.videoEndDeliveryAdmission = { [weak self] in
            self?.admitsDeferredVideoEnd() ?? false
        }
        engine.switchPrepared = { [weak self] ticket, endpoint in self?.switchPrepared(ticket, endpoint: endpoint) }
        engine.switchVisible = { [weak self] ticket, id in self?.switchVisible(ticket, executionID: id) }
        engine.switchFailed = { [weak self] ticket, reason in self?.switchFailed(ticket, reason: reason) }
        engine.switchLost = { [weak self] ticket, reason in self?.switchLost(ticket, reason: reason) }
        let scene = SceneDaemonClient.shared
        scene.stopPlaybackRequested = { [weak self] in self?.stopCurrentPlayback() }
        scene.switchPrepared = { [weak self] ticket, endpoint in self?.switchPrepared(ticket, endpoint: endpoint) }
        scene.switchVisible = { [weak self] ticket, id in self?.switchVisible(ticket, executionID: id) }
        scene.switchFailed = { [weak self] ticket, reason in self?.switchFailed(ticket, reason: reason) }
        scene.switchLost = { [weak self] ticket, reason in self?.switchLost(ticket, reason: reason) }
        seedEngineProjectionFromPersistedSettings()
    }

    func admitImportedVideoPlayback(reference: WallpaperReference,
                                   libraryPending: WallpaperPlaybackSequence.Pending? = nil) -> ImportedVideoPlaybackAdmission? {
        guard let libraryPending else {
            // Trusted imported-video publishers may request admission before a
            // catalog projection exists. Their explicit video request has a
            // single-item source, and still uses propose/begin/stage once.
            guard let snapshot = try? WallpaperPlaybackSequence.Snapshot(source: .single(reference), revision: 0,
                entries: [.init(reference: reference, runtime: .video, isPlayable: true)]),
                let proposal = libraryPlaybackSequence.proposeSelection(reference, from: snapshot) else { return nil }
            var result: ImportedVideoPlaybackAdmission?
            _ = dispatchLibraryPlayback(proposal, prepare: { [weak self] pending in
                result = self?.admitImportedVideoPlayback(reference: reference, libraryPending: pending)
                return result != nil
            })
            return result
        }
        guard libraryPending.ticket.runtime == .video, acceptsLibraryPlayback(libraryPending) else { return nil }
        let ticket = libraryPending.ticket
        pendingWallpaper = nil
        stopAutoSwitchTimer()
        // beginPlaybackIntent revokes the old gate before this claim. The new
        // token belongs to the same ticket throughout asynchronous import work.
        return ImportedVideoPlaybackAdmission(ticket: ticket,
            autoplayToken: ImportedVideoAutoplayGate.shared.claim(), reference: reference, libraryPending: libraryPending)
    }

    func acceptsImportedVideoPlayback(_ admission: ImportedVideoPlaybackAdmission) -> Bool {
        admission.ticket.runtime == .video
            && playbackSwitch.pending?.selection.ticket == admission.ticket
            && ImportedVideoAutoplayGate.shared.isCurrent(admission.autoplayToken)
            && (admission.libraryPending.map(acceptsLibraryPlayback) ?? true)
    }

    func failImportedVideoPlayback(_ admission: ImportedVideoPlaybackAdmission, reason: String) {
        // A late import failure cannot cancel a newer selection.
        guard playbackSwitch.pending?.selection.ticket == admission.ticket else { return }
        switchFailed(admission.ticket, reason: reason)
    }

    func prepareVideoSwitch(_ wallpaper: VideoWallpaper, admission: ImportedVideoPlaybackAdmission? = nil,
                            libraryPending: WallpaperPlaybackSequence.Pending? = nil) {
        let ticket: PlaybackSwitchTicket
        if let admission {
            guard acceptsImportedVideoPlayback(admission) else { return }
            ticket = admission.ticket
        } else if let libraryPending {
            guard libraryPending.ticket.runtime == .video, acceptsLibraryPlayback(libraryPending) else { return }
            ticket = libraryPending.ticket
        } else { return }
        switchSelections[ticket.id] = .video(wallpaper)
        WallpaperEngine.shared.prepareVideoSwitch(wallpaper, ticket: ticket,
            multiDisplayEnabled: settings.multiDisplayEnabled,
            videoFillMode: settings.videoFillMode.ipcValue,
            shouldLoopCurrentItem: shouldLoopCurrentItemInEngine())
    }

    func admitsDeferredVideoEnd() -> Bool {
        playbackSwitch.pending == nil && playbackSwitch.activity == nil
            && playbackSwitch.cancellations.isEmpty && playbackSwitch.retirements.isEmpty
            && playbackSwitch.committed?.ticket.runtime == .video
    }

    func setWebWallpaper(requestID: UUID, entryURL: URL, rootURL: URL,
                         propertiesJSON: String?, recordID: String?, language: String,
                         runtimeProfile: WallpaperEngine.WebRuntimeProfile,
                         resourceLifetime: PlaybackResourceLifetime?, intentEpoch: UInt64?,
                         resourceGrants: [WebWallpaperResourceGrant] = [],
                         allowedNetworkHosts: Set<String> = [],
                         libraryPending: WallpaperPlaybackSequence.Pending? = nil) {
        if let libraryPending {
            guard libraryPending.ticket.runtime == .web, acceptsLibraryPlayback(libraryPending),
                  intentEpoch == libraryPending.ticket.epoch else { return }
        } else { return }
        guard let ticket = playbackSwitch.pending?.selection.ticket else { return }
        switchSelections[ticket.id] = .web(recordID)
        WallpaperEngine.shared.prepareWebSwitch(ticket: ticket, requestID: requestID,
            entryURL: entryURL, rootURL: rootURL, propertiesJSON: propertiesJSON,
            recordID: recordID, language: language, runtimeProfile: runtimeProfile,
            multiDisplayEnabled: settings.multiDisplayEnabled, resourceLifetime: resourceLifetime,
            resourceGrants: resourceGrants, allowedNetworkHosts: allowedNetworkHosts)
    }

    /// Resolving a Workshop request releases its empty-host reservation in a
    /// defer. A claimed execution may still be preparing and has no committed
    /// Web ID yet; that cleanup must not cancel the transferred selection.
    func hasTransferredWebPreparation(epoch: UInt64) -> Bool {
        guard let ticket = playbackSwitch.pending?.selection.ticket,
              ticket.epoch == epoch, ticket.runtime == .web else { return true }
        if case .web = switchSelections[ticket.id] { return true }
        return false
    }

    func claimScenePlaybackIntent(recordID: String, newSelection: Bool,
                                  libraryPending: WallpaperPlaybackSequence.Pending? = nil) -> PlaybackSwitchTicket? {
        if let libraryPending {
            guard libraryPending.ticket.runtime == .scene, acceptsLibraryPlayback(libraryPending) else { return nil }
            switchSelections[libraryPending.ticket.id] = .scene(recordID)
            return libraryPending.ticket
        }
        guard !newSelection else { return nil }
        let selection = playbackSwitch.pending?.selection ?? playbackSwitch.committed
        guard let ticket = selection?.ticket, ticket.runtime == .scene,
              case let .scene(currentID) = switchSelections[ticket.id],
              currentID?.utf8.elementsEqual(recordID.utf8) == true else { return nil }
        libraryRotationDeadline.freezeForPreparation(now: CACurrentMediaTime())
        stopAutoSwitchTimer()
        return ticket
    }

    func setSceneWallpaper(_ request: ScenePlaybackLoadRequest, resourceLifetime: PlaybackResourceLifetime?,
                           intentEpoch: UInt64? = nil, libraryPending: WallpaperPlaybackSequence.Pending? = nil) {
        let ticket: PlaybackSwitchTicket
        if let libraryPending {
            guard libraryPending.ticket.runtime == .scene, acceptsLibraryPlayback(libraryPending),
                  intentEpoch == libraryPending.ticket.epoch else { return }
            ticket = libraryPending.ticket
        } else if let intentEpoch {
            let selection = playbackSwitch.pending?.selection ?? playbackSwitch.committed
            guard let current = selection?.ticket, current.runtime == .scene, current.epoch == intentEpoch else { return }
            ticket = current
        } else { return }
        switchSelections[ticket.id] = .scene(request.recordID)
        SceneDaemonClient.shared.prepareSwitch(request, ticket: ticket, resourceLifetime: resourceLifetime)
    }

    func setStaticWallpaper(_ url: URL, libraryPending: WallpaperPlaybackSequence.Pending) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            switchFailed(libraryPending.ticket, reason: "图片文件已不可用，已保留原壁纸")
            return
        }
        guard libraryPending.ticket.runtime == .systemStill, acceptsLibraryPlayback(libraryPending) else { return }
        let ticket = libraryPending.ticket
        switchSelections[ticket.id] = .systemStill(url)
        let id = UUID()
        let endpoint = PlaybackSwitchEndpoint(id: id, activate: { [weak self] in
            guard let self, self.playbackSwitch.pending?.selection.ticket == ticket else { return }
            let workspace = NSWorkspace.shared
            let screens = NSScreen.screens
            let previous = screens.map { ($0, workspace.desktopImageURL(for: $0), workspace.desktopImageOptions(for: $0) ?? [:]) }
            var applied: [Int] = []
            var failures: [String] = []
            for (index, screen) in screens.enumerated() {
                do { try workspace.setDesktopImageURL(url, for: screen, options: [:]); applied.append(index) }
                catch { failures.append(error.localizedDescription) }
            }
            guard !screens.isEmpty, failures.isEmpty else {
                for index in applied {
                    let (screen, oldURL, options) = previous[index]
                    guard let oldURL else { failures.append("无法恢复原系统壁纸"); continue }
                    do { try workspace.setDesktopImageURL(oldURL, for: screen, options: options) }
                    catch { failures.append("恢复失败：\(error.localizedDescription)") }
                }
                self.switchFailed(ticket, reason: "设置系统壁纸失败：\(failures.joined(separator: "；"))")
                return
            }
            self.switchVisible(ticket, executionID: id)
        }, finalize: {}, cancel: { $0() }, setOutputActive: { _, done in done(true) }, retire: { _, done in done() })
        switchPrepared(ticket, endpoint: endpoint)
    }

    func switchPrepared(_ ticket: PlaybackSwitchTicket, endpoint: PlaybackSwitchEndpoint) {
        switchEndpoints[endpoint.id] = endpoint
        runSwitchEffects(playbackSwitch.prepared(ticket, executionID: endpoint.id))
    }

    func switchVisible(_ ticket: PlaybackSwitchTicket, executionID: UUID) {
        let effects = playbackSwitch.visible(ticket, executionID: executionID)
        runSwitchEffects(effects)
    }

    func switchFailed(_ ticket: PlaybackSwitchTicket, reason: String) {
        runSwitchEffects(playbackSwitch.failed(ticket, reason: reason))
    }

    func switchLost(_ ticket: PlaybackSwitchTicket, reason: String) {
        runSwitchEffects(playbackSwitch.lost(ticket, reason: reason))
    }

    func scheduleSwitchDeadline(_ ticket: PlaybackSwitchTicket) {
        switchDeadline?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.switchFailed(ticket, reason: "壁纸准备或显示超时，已保留原壁纸") }
        switchDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 40, execute: work)
    }

    func runSwitchEffects(_ effects: [PlaybackSwitchTransaction.Effect]) {
        switchEffectQueue.append(contentsOf: effects.map { (effect: $0, originEpoch: playbackIntentEpoch) })
        guard !drainingSwitchEffects else { return }
        drainingSwitchEffects = true
        defer {
            drainingSwitchEffects = false
            WallpaperEngine.shared.replayDeferredVideoEndIfNeeded()
        }
        while !switchEffectQueue.isEmpty {
            let queued = switchEffectQueue.removeFirst()
            let effect = queued.effect
            switch effect {
            case let .cancel(barrier, selection):
                let done = { [weak self] in
                    guard let self else { return }
                    if let id = selection.executionID { self.switchEndpoints.removeValue(forKey: id) }
                    let effects = self.playbackSwitch.cancelled(barrier)
                    self.pruneSwitchSelection(selection.ticket)
                    self.runSwitchEffects(effects)
                    self.finishSwitchSettlementObservers(selection.ticket)
                }
                if let id = selection.executionID, let endpoint = switchEndpoints[id] { endpoint.cancel(done) }
                else if selection.ticket.runtime == .scene { SceneDaemonClient.shared.cancelSwitch(ticket: selection.ticket, completion: done) }
                else if selection.ticket.runtime == .video || selection.ticket.runtime == .web {
                    WallpaperEngine.shared.cancelSwitch(ticket: selection.ticket, completion: done)
                } else { done() }
            case let .output(operation):
                guard let endpoint = switchEndpoints[operation.executionID] else {
                    runSwitchEffects(playbackSwitch.activityCompleted(operation, succeeded: false)); continue
                }
                endpoint.setOutputActive(operation.active) { [weak self] success in
                    guard let self else { return }
                    self.runSwitchEffects(self.playbackSwitch.activityCompleted(operation, succeeded: success))
                }
            case let .activate(selection):
                guard let id = selection.executionID, let endpoint = switchEndpoints[id] else {
                    switchFailed(selection.ticket, reason: "播放端点已失效"); continue
                }
                endpoint.activate()
            case let .commit(selection, recovery): commitSwitch(selection, recovery: recovery)
            case let .finalize(selection):
                if let id = selection.executionID, let endpoint = switchEndpoints[id] {
                    endpoint.finalize()
                    // commit 的 @Published 投影早于异步旧端退休；网格、详情
                    // 还读取引擎的执行事实。finalize 同步采纳这些事实后再
                    // 统一通知现有观察者，不能让它们停在上一张的播放状态。
                    objectWillChange.send()
                }
            case let .retire(barrier, selection):
                let done = { [weak self] in
                    guard let self else { return }
                    if let id = selection.executionID { self.switchEndpoints.removeValue(forKey: id) }
                    self.pruneSwitchSelection(selection.ticket)
                    self.runSwitchEffects(self.playbackSwitch.retired(barrier))
                    self.finishSwitchSettlementObservers(selection.ticket)
                    // Stop / 输出丢失没有后继 finalize；实际退出清空执行
                    // 事实后，也要让现有 UI 观察者撤掉最后一张播放标记。
                    // 已有后继提交时，交给其 finalize 发布完整投影。
                    if self.playbackSwitch.committed == nil { self.objectWillChange.send() }
                }
                if let id = selection.executionID, let endpoint = switchEndpoints[id] { endpoint.retire(nil, done) }
                else { done() }
            case let .handoff(barrier, old, replacement):
                let done = { [weak self] in
                    guard let self else { return }
                    if let id = old.executionID { self.switchEndpoints.removeValue(forKey: id) }
                    self.pruneSwitchSelection(old.ticket)
                    self.runSwitchEffects(self.playbackSwitch.retired(barrier))
                    self.finishSwitchSettlementObservers(old.ticket)
                }
                if let id = old.executionID, let endpoint = switchEndpoints[id] {
                    // Commit projections may reenter before this effect runs.
                    // Still retire the old output, but retain its empty helper
                    // only for the current successor or a newer Scene intent.
                    let mayRetain = playbackSwitch.epoch == replacement.ticket.epoch || requestedRuntime == .scene
                    endpoint.retire(mayRetain ? replacement.ticket : nil, done)
                }
                else { done() }
            case let .failed(ticket, reason):
#if DEBUG
                NSLog("MWX playback switch %@ failed: %@", ticket.id.uuidString, reason)
#endif
                // Cancel/retire effects above always settle their transaction.
                // Their callbacks may have synchronously accepted a new ticket;
                // the old failure then owns no current UI/deadline mirrors.
                // Use the enqueue provenance, not ticket.epoch: a native recovery
                // legitimately reuses an older committed ticket after a failed intent.
                guard playbackIntentEpoch == queued.originEpoch else { continue }
                switchDeadline?.cancel()
                pendingWallpaper = nil
                NotificationCenter.default.post(name: .wallpaperSwitchDidFail, object: nil,
                    userInfo: ["message": reason, "runtime": ticket.runtime.rawValue])
                guard playbackIntentEpoch == queued.originEpoch else { continue }
                if libraryPlaybackSequence.pending?.ticket == ticket {
                    let failedPending = libraryPlaybackSequence.pending
                    let lostWithoutOutput = failedPending?.proposal.cause == .failureRecovery
                        && playbackSwitch.committed == nil
                    let retry = libraryPlaybackSequence.retryAfterFailure(ticket, chooseIndex: { Int.random(in: 0..<$0) })
                    if let retry { _ = dispatchLibraryPlayback(retry) }
                    else {
                        libraryRotationDeadline.preparationFailed(now: CACurrentMediaTime())
                        if lostWithoutOutput { stopCurrentPlayback() }
                        else { refreshAutoSwitchTimerIfNeeded() }
                        if let failedPending, playbackIntentEpoch == queued.originEpoch {
                            libraryPlaybackFailed?(failedPending)
                        }
                        guard playbackIntentEpoch == queued.originEpoch else { continue }
                    }
                } else if libraryPlaybackSequence.committed != nil {
                    libraryRotationDeadline.preparationFailed(now: CACurrentMediaTime())
                    refreshAutoSwitchTimerIfNeeded()
                }
                WallpaperEngine.shared.replayDeferredVideoEndIfNeeded()
            case let .lost(ticket, reason):
                let hasSource = libraryPlaybackSequence.committed?.ticket == ticket
                if playbackSwitch.pending == nil { switchDeadline?.cancel() }
                pendingSystemWallpaperSyncWorkItem?.cancel()
                currentWallpaper = nil
                lastWorkshopPlaybackRecordID = nil
                isPlaying = false
                stopAutoSwitchTimer()
                persistCurrentWallpaperSnapshot()
#if DEBUG
                NSLog("MWX playback output lost %@: %@", ticket.id.uuidString, reason)
#endif
                NotificationCenter.default.post(name: .wallpaperSwitchDidFail, object: nil,
                    userInfo: ["message": reason, "runtime": ticket.runtime.rawValue])
                guard playbackIntentEpoch == queued.originEpoch, playbackSwitch.pending == nil else { continue }
                if hasSource, !advanceLibraryPlayback(cause: .failureRecovery) { stopCurrentPlayback() }
            }
        }
    }

    private func commitSwitch(_ selection: PlaybackSwitchTransaction.Selection, recovery: Bool) {
#if DEBUG
        NSLog("MWX playback committed runtime=%@ ticket=%@ execution=%@ recovery=%d",
              selection.ticket.runtime.rawValue, selection.ticket.id.uuidString,
              selection.executionID?.uuidString ?? "none", recovery)
#endif
        guard let value = switchSelections[selection.ticket.id] else { return }
        let libraryCommit = libraryPlaybackSequence.commit(selection.ticket, recovery: recovery)
        if let libraryCommit, libraryCommit.cause == .userSelection, case let .video(wallpaper) = value {
            // Retain the initial-index merge protection, after real success.
            recordInitialIndexUserSelection(wallpaper)
        }
        switchDeadline?.cancel()
        pendingSystemWallpaperSyncWorkItem?.cancel()
        if !recovery {
            pendingWallpaper = nil
            switch value {
            case let .video(wallpaper):
                currentWallpaper = wallpaper; activeWallpaperRuntime = .video; lastWorkshopPlaybackRecordID = nil
                updateCurrentWallpaperIndex(for: wallpaper.id)
            case let .web(recordID):
                currentWallpaper = nil; activeWallpaperRuntime = .web; lastWorkshopPlaybackRecordID = recordID
            case let .scene(recordID):
                currentWallpaper = nil; activeWallpaperRuntime = .scene; lastWorkshopPlaybackRecordID = recordID
            case .systemStill:
                currentWallpaper = nil; activeWallpaperRuntime = .systemStill; lastWorkshopPlaybackRecordID = nil
            }
            persistCurrentWallpaperSnapshot()
            postWallpaperRuntimeWillSwitch(to: selection.ticket.runtime, recordID: lastWorkshopPlaybackRecordID)
        }
        isPlaying = selection.ticket.runtime != .systemStill && !PlaybackCommandMultiplexer.shared.isPlaybackPaused
        if let libraryCommit {
            if !libraryCommit.isRecovery && libraryCommit.cause != .settingsReload {
                libraryRotationDeadline.commitSuccess(now: CACurrentMediaTime(), interval: libraryRotationInterval,
                    eligible: libraryRotationEligible)
            } else { libraryRotationDeadline.preparationFailed(now: CACurrentMediaTime()) }
            libraryPlaybackCommitted?(libraryCommit)
            guard playbackSwitch.committed?.ticket == selection.ticket else { return }
            refreshAutoSwitchTimerIfNeeded()
        } else { stopAutoSwitchTimer() }
        switch value {
        case let .video(wallpaper): if settings.syncSystemWallpaper { syncSystemWallpaper(with: wallpaper) }
        case let .web(recordID): if let recordID { scheduleRuntimeFrameSystemWallpaperSync(kind: .web, recordID: recordID) }
        case let .scene(recordID): if let recordID { scheduleRuntimeFrameSystemWallpaperSync(kind: .scene, recordID: recordID) }
        case .systemStill: break
        }
    }

    /// Download removal waits for the original cancel/retire acknowledgements,
    /// not a daemon-wide stop that could erase a newer Scene preparation.
    func prepareSceneDownloadRemoval(recordID: String, completion: @escaping (Bool) -> Void) {
        let committed = playbackSwitch.committed
        let pending = playbackSwitch.pending?.selection
        let removesCommitted = sceneSelection(committed, matches: recordID)
        let removesPending = sceneSelection(pending, matches: recordID)
        if removesCommitted, let pending, !removesPending, pending.ticket != committed?.ticket {
            // Its lease still protects the standby output during this handoff.
            // Retrying after B settles is safer than stopping B to delete A.
            completion(false)
            return
        }
        let tickets = Set([removesCommitted ? committed?.ticket : nil,
                           removesPending ? pending?.ticket : nil].compactMap { $0 })
        // Called only while the Scene owner reports a live intent. An unknown
        // product ticket cannot authorize deleting that owner's live resource.
        guard !tickets.isEmpty else { completion(false); return }
        var remaining = tickets
        for ticket in tickets {
            switchSettlementObservers[ticket, default: []].append { [weak self] in
                guard let self else { completion(false); return }
                remaining.remove(ticket)
                if remaining.isEmpty {
                    completion(!self.sceneSelection(self.playbackSwitch.committed, matches: recordID)
                        && !self.sceneSelection(self.playbackSwitch.pending?.selection, matches: recordID))
                }
            }
        }
        if removesCommitted { stopCurrentPlayback() }
        else if let pending, removesPending {
            // An explicit removal is not a failed automatic candidate/replay.
            // Revoke its sequence attempt before the original failed effects.
            _ = libraryPlaybackSequence.cancel(pending.ticket)
            switchFailed(pending.ticket, reason: "已取消正在删除的 Scene 壁纸准备")
        }
        for ticket in tickets { finishSwitchSettlementObservers(ticket) }
    }

    private func sceneSelection(_ selection: PlaybackSwitchTransaction.Selection?, matches recordID: String) -> Bool {
        guard let selection, case .scene(let id) = switchSelections[selection.ticket.id], let id else { return false }
        return id.utf8.elementsEqual(recordID.utf8)
    }

    private func finishSwitchSettlementObservers(_ ticket: PlaybackSwitchTicket) {
        guard playbackSwitch.committed?.ticket != ticket, playbackSwitch.pending?.selection.ticket != ticket,
              !playbackSwitch.cancellations.values.contains(where: { $0.ticket == ticket }),
              !playbackSwitch.retirements.values.contains(where: { $0.ticket == ticket }) else { return }
        let observers = switchSettlementObservers.removeValue(forKey: ticket) ?? []
        observers.forEach { $0() }
    }

    private func pruneSwitchSelection(_ ticket: PlaybackSwitchTicket) {
        guard playbackSwitch.committed?.ticket != ticket, playbackSwitch.pending?.selection.ticket != ticket,
              !playbackSwitch.cancellations.values.contains(where: { $0.ticket == ticket }) else { return }
        switchSelections.removeValue(forKey: ticket.id)
    }
}

extension Notification.Name {
    static let wallpaperSwitchDidFail = Notification.Name("WallpaperSwitchDidFail")
}

#if DEBUG
extension WallpaperManager {
    /// Explicit diagnostic resources need not be published in a user's catalog.
    /// They still enter the original product transaction through one fixed source.
    @discardableResult
    func requestDiagnosticPlayback(reference: WallpaperReference, runtime: WallpaperRuntimeKind,
                                   cause: WallpaperPlaybackCause = .userSelection,
                                   prepare: @escaping (WallpaperPlaybackSequence.Pending) -> Bool) -> PlaybackSwitchTicket? {
        guard let snapshot = try? WallpaperPlaybackSequence.Snapshot(source: .single(reference), revision: 0,
            entries: [.init(reference: reference, runtime: runtime, isPlayable: true)]),
            let proposal = libraryPlaybackSequence.proposeSelection(reference, from: snapshot, cause: cause) else { return nil }
        return dispatchLibraryPlayback(proposal, prepare: prepare)
    }

    @discardableResult
    func requestDiagnosticVideo(_ wallpaper: VideoWallpaper) -> PlaybackSwitchTicket? {
        requestDiagnosticPlayback(reference: .init(provider: .videoLibrary, sourceID: wallpaper.id), runtime: .video) { [weak self] pending in
            guard let self else { return false }
            self.setAsWallpaper(wallpaper, libraryPending: pending)
            return true
        }
    }
}
#endif
