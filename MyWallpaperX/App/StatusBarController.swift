import AppKit
import Combine

/// Owns the menu-bar surface, not playback. Only an open panel subscribes to
/// product state; the existing two-second system sampler remains the one clock.
final class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let wallpaperManager = WallpaperManager.shared
    private var iconRefreshTimer: DispatchSourceTimer?
    private var displayedIconLabel: String?
    private var displayedIconAppearance: NSAppearance.Name?
    private var cancellables = Set<AnyCancellable>()
    private var refreshScheduled = false
    private var observing = false
    private var presentation: StatusBarPanelPresentation?
    private var favoriteInFlight = false

    private lazy var panelController: StatusBarPanelViewController = {
        let controller = StatusBarPanelViewController()
        controller.onAction = { [weak self] in self?.perform($0) }
        controller.onDismiss = { [weak self] in self?.popover.performClose(nil) }
        return controller
    }()

    private lazy var popover: NSPopover = {
        let result = NSPopover()
        result.behavior = .transient
        result.animates = true
        result.contentViewController = panelController
        result.delegate = self
        return result
    }()

    override init() {
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.toolTip = "MyWallpaperX · 壁纸控制"
        item.button?.setAccessibilityLabel("MyWallpaperX 壁纸控制")
        SystemMonitor.shared.refreshRuntimeStats()
        updateStatusBarIcon()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            SystemMonitor.shared.refreshRuntimeStats(includeNetwork: self.observing)
            self.updateStatusBarIcon()
            if self.observing {
                self.refreshApplicationStats()
                self.refreshPanel()
            }
        }
        timer.resume()
        iconRefreshTimer = timer
    }

    deinit {
        iconRefreshTimer?.cancel()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        let usage = SystemMonitor.shared.stats.gpuUsage
        let hasUpdate = AppUpdateController.shared.availableUpdateVersion != nil
        let metric = usage.map { String(format: "%d%%", Int(($0 * 100).rounded())) } ?? "—"
        let label = hasUpdate ? "↑ " + metric : metric
        let appearance = button.effectiveAppearance.name
        guard displayedIconLabel != label || displayedIconAppearance != appearance else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: max(size.width + 2, 28), height: 18), flipped: false) { rect in
            (label as NSString).draw(at: NSPoint(x: (rect.width - size.width) / 2,
                                                y: (rect.height - size.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = hasUpdate ? "MyWallpaperX · 有可用更新，请从应用菜单检查更新" : "MyWallpaperX · 壁纸控制"
        displayedIconLabel = label
        displayedIconAppearance = appearance
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem?.button else { return }
        panelController.panel.prepareForPresentation()
        startObserving()
        SystemMonitor.shared.refreshRuntimeStats(includeNetwork: true)
        refreshApplicationStats()
        refreshPanel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        // objectWillChange precedes mutation, including transaction finalize.
        // Coalesce and read only on the next main turn, after commit completes.
        wallpaperManager.objectWillChange.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        wallpaperManager.thumbnailReadyPublisher.receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                guard let self, self.observing else { return }
                self.panelController.thumbnailBecameReady(at: path)
            }.store(in: &cancellables)
        SteamWorkshopService.shared.$downloads.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        SteamWorkshopService.shared.$previewReloadToken.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        SteamWorkshopService.shared.$launchPendingRecordID.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        PlaybackCommandMultiplexer.shared.pauseSnapshots.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        if let workspace = MyWallpaperXApplication.libraryWorkspace {
            workspace.catalog.$catalog.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
            workspace.playbackChanges.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
            workspace.collections?.objectWillChange.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        }
        for name in [Notification.Name.playbackMuteStateDidChange,
                     .sceneWallpaperLaunchStateDidChange, .wallpaperSwitchDidFail,
                     WallpaperEngine.playbackReadyNotification, WallpaperEngine.webPlaybackReadyNotification,
                     WallpaperEngine.playbackFailedNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        }
    }

    private func scheduleRefresh() {
        guard observing, !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            if self.observing { self.refreshPanel() }
        }
    }

    private func capturePresentation() -> StatusBarPanelPresentation {
        let workspace = MyWallpaperXApplication.libraryWorkspace
        var state: StatusBarPanelPresentation
        if wallpaperManager.playbackSwitch.committed != nil {
            state = .capture(manager: wallpaperManager, service: .shared)
        } else {
            let reference = workspace?.restoration.rememberedReference
            let item: WallpaperContentItem?
            if let reference, let catalog = workspace?.catalog.catalog {
                let values: [WallpaperContentItem]
                switch reference.provider {
                case .videoLibrary: values = catalog.videos
                case .staticImageLibrary: values = catalog.images
                case .steamWorkshop, .pixabay, .wallhaven, .pixiv: values = catalog.downloads
                }
                // A standby title is already-published metadata. Resolution and
                // source readiness remain on deliberate replay / favorite actions.
                item = values.first { $0.reference == reference }
            } else { item = nil }
            state = .capture(manager: wallpaperManager, service: .shared,
                             rememberedReference: reference, rememberedContent: item)
        }
        if let reference = state.favoriteReference, let workspace,
           let canonical = try? WallpaperLibraryQuery.canonicalReferences([reference], relationships: workspace.relationships)[reference] {
            state.favoriteReference = canonical
            state.isFavorite = workspace.relationships.favorites.contains { $0.reference == canonical }
            state.canFavorite = workspace.presentation.canEditCollections && !favoriteInFlight
        }
        return state
    }

    private func refreshApplicationStats() {
        SystemMonitor.shared.refreshApplicationStats(processIdentifiers:
            [ProcessInfo.processInfo.processIdentifier] + DaemonPlaybackProcessRegistry.shared.liveProcessIdentifiers)
    }

    private func refreshPanel() {
        let state = capturePresentation()
        presentation = state
        panelController.apply(state, refreshToken: SteamWorkshopService.shared.previewReloadToken)
        panelController.panel.applyMetrics(SystemMonitor.shared.stats)
        let availableHeight = statusItem?.button?.window?.screen.map { $0.visibleFrame.height - 40 } ?? state.preferredHeight
        let size = NSSize(width: StatusBarPanelPresentation.preferredWidth,
                          height: min(state.preferredHeight, max(360 * StatusBarPanelPresentation.scale, availableHeight)))
        if popover.contentSize != size { popover.contentSize = size }
    }

    func popoverDidClose(_ notification: Notification) {
        observing = false
        SystemMonitor.shared.endNetworkSampling()
        SystemMonitor.shared.refreshApplicationStats(processIdentifiers: [])
        cancellables.removeAll()
        panelController.releasePreview()
        presentation = nil
    }

    private func perform(_ action: StatusBarPanelViewController.Action) {
        switch action {
        case .settings:
            closeThen { SettingsWindowController.shared.showWindow() }
        case .openMain:
            closeThen { MainWindowCoordinator.activateMainWindow() }
        case .previous: CrossRuntimeWallpaperNavigator.navigate(.previous)
        case .next: CrossRuntimeWallpaperNavigator.navigate(.next)
        case .playback: togglePlayback()
        case .mode: cyclePlaybackMode()
        case .favorite: toggleFavorite()
        case .quit: quitApp()
        case .mute:
            PlaybackCommandMultiplexer.shared.dispatch(.setMuted(!PlaybackMuteState.shared.isMuted))
        case let .volume(value):
            wallpaperManager.updateVolume(value)
            if PlaybackMuteState.shared.isMuted != (value == 0) {
                PlaybackCommandMultiplexer.shared.dispatch(.setMuted(value == 0))
            }
        case .properties:
            let current = capturePresentation()
            guard case let .workshop(record) = presentation?.content,
                  current.content == presentation?.content else { scheduleRefresh(); return }
            closeThen { Self.openProperties(record) }
        }
        scheduleRefresh()
    }

    private func toggleFavorite() {
        let state = capturePresentation()
        guard state.canFavorite, let reference = state.favoriteReference,
              let workspace = MyWallpaperXApplication.libraryWorkspace, let collections = workspace.collections else { return }
        do {
            let item = try workspace.content(for: reference)
            let enabled = !state.isFavorite
            // One admitted write at a time prevents rapid clicks from queuing
            // the same stale target value. Collections remains the only truth.
            favoriteInFlight = true
            scheduleRefresh()
            Task { @MainActor [weak self] in
                defer { self?.favoriteInFlight = false; self?.scheduleRefresh() }
                do {
                    try await collections.perform(.setFavorite(item.organizationItem, enabled, Date()),
                        undoName: enabled ? "特别喜爱" : "取消特别喜爱")
                } catch { workspace.presentation.report(error) }
            }
        } catch { workspace.presentation.report(error) }
    }

    private func closeThen(_ action: @escaping () -> Void) {
        popover.performClose(nil)
        DispatchQueue.main.async {
            // Only deliberate window/chooser actions activate the app. Merely
            // opening the status item must not steal focus from another app.
            NSApp.activate(ignoringOtherApps: true)
            action()
        }
    }

    private func togglePlayback() {
        let state = capturePresentation()
        guard state.canTogglePlayback else { return }
        if state.isStandby {
            if MyWallpaperXApplication.libraryWorkspace?.restoration.resumeLastSelection(onFailure: { [weak self] in
                self?.closeThen { MainWindowCoordinator.activateMainWindow() }
            }) != true {
                closeThen { MainWindowCoordinator.activateMainWindow() }
            }
        } else {
            let commands = PlaybackCommandMultiplexer.shared
            commands.dispatch(commands.isUserPaused ? .resume : .pause)
            wallpaperManager.isPlaying = commands.isAnyEnginePlaying
        }
    }

    private static func openProperties(_ record: SteamWorkshopDownloadRecord) {
        if record.contentType == .scene {
            SteamWorkshopSceneInspectionController.requestPropertyEditor(for: record)
        } else if record.contentType == .web {
            let editor = SteamWorkshopWebPropertyEditorView(record: record)
            if editor.presentsOnlyMessage, let message = editor.emptyStateMessage {
                SteamWorkshopPropertyPanelController.shared.showMessage(title: "Web 属性调节", subtitle: record.title, message: message)
            } else {
                SteamWorkshopPropertyPanelController.shared.show(title: "Web 属性调节", subtitle: record.title, content: editor)
            }
        }
    }

    private func cyclePlaybackMode() {
        guard capturePresentation().content != .none else { return }
        switch wallpaperManager.playbackMode() {
        case .loop: wallpaperManager.setSequentialPlaybackEnabled(true)
        case .sequential: wallpaperManager.setRandomPlaybackEnabled(true)
        case .random: wallpaperManager.setLoopPlaybackEnabled(true)
        }
    }





    @objc private func quitApp() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        // A no-window alert runs synchronously. Holding the main dispatch
        // queue here would block the async flush after terminateLater.
        let alert = makeAppAlert(title: "确定要退出吗？", message: "壁纸将停止播放。", buttons: ["退出", "取消"])
        presentAppAlert(alert, in: appModalHostWindow()) { response in
            if response == .alertFirstButtonReturn { NSApp.terminate(nil) }
        }
    }
}
