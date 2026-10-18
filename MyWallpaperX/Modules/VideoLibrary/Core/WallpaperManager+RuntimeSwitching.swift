import AppKit

extension WallpaperManager {
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
        restorePlaybackState()
        restorePersistedSystemAudioSpectrumIfNeeded()
    }

    func prepareVideoSwitch(_ wallpaper: VideoWallpaper) {
        _ = beginPlaybackIntent(runtime: .video)
        guard let ticket = playbackSwitch.pending?.selection.ticket else { return }
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
                         resourceLifetime: PlaybackResourceLifetime?, intentEpoch: UInt64?) {
        if let intentEpoch {
            guard playbackIntentEpoch == intentEpoch, requestedRuntime == .web,
                  playbackSwitch.pending != nil else { return }
        } else { _ = beginPlaybackIntent(runtime: .web) }
        guard let ticket = playbackSwitch.pending?.selection.ticket else { return }
        switchSelections[ticket.id] = .web(recordID)
        WallpaperEngine.shared.prepareWebSwitch(ticket: ticket, requestID: requestID,
            entryURL: entryURL, rootURL: rootURL, propertiesJSON: propertiesJSON,
            recordID: recordID, language: language, runtimeProfile: runtimeProfile,
            multiDisplayEnabled: settings.multiDisplayEnabled, resourceLifetime: resourceLifetime)
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

    func claimScenePlaybackIntent(recordID: String, newSelection: Bool) -> PlaybackSwitchTicket? {
        if newSelection {
            _ = beginPlaybackIntent(runtime: .scene)
            guard let ticket = playbackSwitch.pending?.selection.ticket else { return nil }
            switchSelections[ticket.id] = .scene(recordID)
            return ticket
        }
        let selection = playbackSwitch.pending?.selection ?? playbackSwitch.committed
        guard let ticket = selection?.ticket, ticket.runtime == .scene,
              case let .scene(currentID) = switchSelections[ticket.id], currentID == recordID else { return nil }
        return ticket
    }

    func setSceneWallpaper(_ request: ScenePlaybackLoadRequest, resourceLifetime: PlaybackResourceLifetime?, intentEpoch: UInt64? = nil) {
        let ticket: PlaybackSwitchTicket
        if let intentEpoch {
            let selection = playbackSwitch.pending?.selection ?? playbackSwitch.committed
            guard let current = selection?.ticket, current.runtime == .scene, current.epoch == intentEpoch else { return }
            ticket = current
        } else {
            _ = beginPlaybackIntent(runtime: .scene)
            guard let current = playbackSwitch.pending?.selection.ticket else { return }
            ticket = current
        }
        switchSelections[ticket.id] = .scene(request.recordID)
        SceneDaemonClient.shared.prepareSwitch(request, ticket: ticket, resourceLifetime: resourceLifetime)
    }

    func setStaticWallpaper(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        _ = beginPlaybackIntent(runtime: .systemStill)
        guard let ticket = playbackSwitch.pending?.selection.ticket else { return }
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
        }, finalize: {}, cancel: { $0() }, setOutputActive: { _, done in done(true) }, retire: { $0() })
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
        switchEffectQueue.append(contentsOf: effects)
        guard !drainingSwitchEffects else { return }
        drainingSwitchEffects = true
        defer {
            drainingSwitchEffects = false
            WallpaperEngine.shared.replayDeferredVideoEndIfNeeded()
        }
        while !switchEffectQueue.isEmpty {
            let effect = switchEffectQueue.removeFirst()
            switch effect {
            case let .cancel(barrier, selection):
                let done = { [weak self] in
                    guard let self else { return }
                    if let id = selection.executionID { self.switchEndpoints.removeValue(forKey: id) }
                    let effects = self.playbackSwitch.cancelled(barrier)
                    self.pruneSwitchSelection(selection.ticket)
                    self.runSwitchEffects(effects)
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
                if let id = selection.executionID { switchEndpoints[id]?.finalize() }
            case let .retire(barrier, selection):
                let done = { [weak self] in
                    guard let self else { return }
                    if let id = selection.executionID { self.switchEndpoints.removeValue(forKey: id) }
                    self.pruneSwitchSelection(selection.ticket)
                    self.runSwitchEffects(self.playbackSwitch.retired(barrier))
                }
                if let id = selection.executionID, let endpoint = switchEndpoints[id] { endpoint.retire(done) }
                else { done() }
            case let .handoff(barrier, old, _):
                let done = { [weak self] in
                    guard let self else { return }
                    if let id = old.executionID { self.switchEndpoints.removeValue(forKey: id) }
                    self.pruneSwitchSelection(old.ticket)
                    self.runSwitchEffects(self.playbackSwitch.retired(barrier))
                }
                if let id = old.executionID, let endpoint = switchEndpoints[id] { endpoint.retire(done) }
                else { done() }
            case let .failed(ticket, reason):
                switchDeadline?.cancel()
                pendingWallpaper = nil
#if DEBUG
                NSLog("MWX playback switch %@ failed: %@", ticket.id.uuidString, reason)
#endif
                NotificationCenter.default.post(name: .wallpaperSwitchDidFail, object: nil,
                    userInfo: ["message": reason, "runtime": ticket.runtime.rawValue])
                if activeWallpaperRuntime == .video { refreshAutoSwitchTimerIfNeeded() }
                WallpaperEngine.shared.replayDeferredVideoEndIfNeeded()
            case let .lost(ticket, reason):
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
        switchDeadline?.cancel()
        pendingSystemWallpaperSyncWorkItem?.cancel()
        if !recovery {
            pendingWallpaper = nil
            switch value {
            case let .video(wallpaper):
                currentWallpaper = wallpaper; activeWallpaperRuntime = .video; lastWorkshopPlaybackRecordID = nil
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
        if activeWallpaperRuntime == .video { refreshAutoSwitchTimerIfNeeded(forceRestart: !recovery) }
        else { stopAutoSwitchTimer() }
        switch value {
        case let .video(wallpaper): if settings.syncSystemWallpaper { syncSystemWallpaper(with: wallpaper) }
        case let .web(recordID): if let recordID { scheduleRuntimeFrameSystemWallpaperSync(kind: .web, recordID: recordID) }
        case let .scene(recordID): if let recordID { scheduleRuntimeFrameSystemWallpaperSync(kind: .scene, recordID: recordID) }
        case .systemStill: break
        }
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
