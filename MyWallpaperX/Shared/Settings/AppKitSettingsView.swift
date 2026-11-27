//
//  AppKitSettingsView.swift
//  MyWallpaperX
//

import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers
import Foundation

enum AppSettingsSection: String, CaseIterable {
    case playback, quality, display, system, hotkeys, efficiency, maintenance, about
}

final class AppKitSettingsContainerView: NSView {
    final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            // document 的尺寸由 updateDocumentFrame 写入；让该 frame 约束内容栈，
            // 否则栈会停在自然宽度，留下不对称的左右空白。
            translatesAutoresizingMaskIntoConstraints = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }
    }

    let dependency: AppSettingsPanelDependency
    private var cancellables = Set<AnyCancellable>()
    var isUpdatingUI = false
    var isDocumentFrameUpdateScheduled = false
    // refreshFromState 的差分快照：滑块拖动等高频 settings 写入会反复触发全量回填，
    // 这里记录三条昂贵路径（热键菜单状态、SMAppService 同步查询、fittingSize 整树求解）
    // 的相关输入，值未变时跳过对应工作。
    var lastHotkeyInputsSignature: [FunctionKeyShortcut] = []
    private var lastStartOnBootSetting: Bool?
    private var lastKnownStartOnBootSystemEnabled: Bool?
    private var muteStateObserver: NSObjectProtocol?
    private var loginItemSyncFailureObserver: NSObjectProtocol?
    private var windowBecameKeyObserver: NSObjectProtocol?
    private(set) var visibleSection: AppSettingsSection
    private let scrollView = NSScrollView()
    let contentContainer = FlippedDocumentView()

    let forms = Dictionary(uniqueKeysWithValues: AppSettingsSection.allCases.map { ($0, SettingsFormView()) })
    var onFormHeightChanged: (() -> Void)?
    private var activeForm: SettingsFormView { forms[visibleSection]! }

    static func checkbox() -> NSButton {
        NSButton(checkboxWithTitle: "", target: nil, action: nil)
    }

    let loopSwitch = AppKitSettingsContainerView.checkbox()
    let randomSwitch = AppKitSettingsContainerView.checkbox()
    let sequentialSwitch = AppKitSettingsContainerView.checkbox()
    let autoSwitchSwitch = AppKitSettingsContainerView.checkbox()
    let intervalField = NSTextField()
    let timeUnitPopup = NSPopUpButton()
    var intervalRowView: NSView?
    var autoSwitchRow: NSGridRow?
    let volumeSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    let volumeValueLabel = NSTextField(labelWithString: "50%")
    let muteSwitch = AppKitSettingsContainerView.checkbox()

    let playbackRateSlider = NSSlider(value: 1.0, minValue: 0.25, maxValue: 2.0, target: nil, action: nil)
    let playbackRateValueLabel = NSTextField(labelWithString: "")
    let playbackRateSwitch = AppKitSettingsContainerView.checkbox()
    var playbackRateControls: NSView?

    let startOnBootSwitch = AppKitSettingsContainerView.checkbox()
    let restorePlaybackOnLaunchSwitch = AppKitSettingsContainerView.checkbox()
    let syncSystemWallpaperSwitch = AppKitSettingsContainerView.checkbox()
    let sceneQualityPresetPopup = NSPopUpButton()
    let sceneAntiAliasingPopup = NSPopUpButton()
    let sceneRasterSamplesLabel = NSTextField(labelWithString: "")
    let scenePostProcessingPopup = NSPopUpButton()
    let scenePostProcessingUseLabel = AppKitSettingsContainerView.makeSceneEffectReadout()
    let sceneTextureQualityPopup = NSPopUpButton()
    let sceneTextureUseLabel = AppKitSettingsContainerView.makeSceneEffectReadout()
    let sceneShadowsPopup = NSPopUpButton()
    let sceneShadowUseLabel = AppKitSettingsContainerView.makeSceneEffectReadout()
    let sceneVolumeLightingPopup = NSPopUpButton()
    let sceneVolumeUseLabel = AppKitSettingsContainerView.makeSceneEffectReadout()

    let sceneReflectionsSwitch = NSSwitch()
    let sceneReflectionUseLabel = AppKitSettingsContainerView.makeSceneEffectReadout()
    let webFrameRatePopup = NSPopUpButton()
    let reapplySceneQualityButton = NSButton(title: String(localized: "Reapply Current Scene"), target: nil, action: nil)
    var reapplySceneQualityRow: NSGridRow?
    let resetQualityButton = NSButton(title: String(localized: "Restore Default Quality"), target: nil, action: nil)
    let sceneMediaInfoSwitch = AppKitSettingsContainerView.checkbox()
    private var sceneMediaAuthorizationCheckID = UUID()
    let systemAudioSpectrumSwitch = AppKitSettingsContainerView.checkbox()
    let systemAudioSpectrumStylePopup = NSPopUpButton()
    let webAudioListeningSwitch = AppKitSettingsContainerView.checkbox()
    let sceneAudioListeningSwitch = AppKitSettingsContainerView.checkbox()
    let systemAudioSpectrumSensitivityPopup = NSPopUpButton()
    let systemAudioSpectrumBarCountPopup = NSPopUpButton()
    let systemAudioSpectrumColorWell = NSColorWell()
    let systemAudioSpectrumOffsetXSlider = NSSlider(value: 0, minValue: -30, maxValue: 30, target: nil, action: nil)
    let systemAudioSpectrumOffsetYSlider = NSSlider(value: 0, minValue: -20, maxValue: 20, target: nil, action: nil)
    let systemAudioSpectrumOffsetXValueLabel = NSTextField(labelWithString: "0%")
    let systemAudioSpectrumOffsetYValueLabel = NSTextField(labelWithString: "0%")
    let systemAudioSpectrumPeakCapsSwitch = AppKitSettingsContainerView.checkbox()
    var systemAudioSpectrumOptionsContainer: NSView?
    var hotkeyPopups: [SystemHotkeyAction: NSPopUpButton] = [:]

    let pauseOtherAppFocusedSwitch = AppKitSettingsContainerView.checkbox()
    let pauseOtherAppFullscreenSwitch = AppKitSettingsContainerView.checkbox()
    let pauseWhenUnpluggedSwitch = AppKitSettingsContainerView.checkbox()
    let pauseWhenIdleSwitch = AppKitSettingsContainerView.checkbox()
    let idleTimeoutPopup = NSPopUpButton()
    var idleTimeoutRowView: NSView?

    let sceneFPSControl = SceneFrameRateSlider(
        value: Double(AnimationFrameRate.standard.rawValue), minValue: Double(AnimationFrameRate.minimum),
        maxValue: Double(AnimationFrameRate.maximum), target: nil, action: nil
    )
    let sceneFPSField = NSTextField(string: "")
    let sceneFPSEffectiveLabel = NSTextField(labelWithString: "")

    let keepDockIconSwitch = AppKitSettingsContainerView.checkbox()
    let multiDisplaySwitch = AppKitSettingsContainerView.checkbox()
    let libraryBackgroundPopup = NSPopUpButton()
    let libraryCardClickPopup = NSPopUpButton()
    let fillModeFitButton = NSButton(radioButtonWithTitle: String(localized: "Fit"), target: nil, action: nil)
    let fillModeFillButton = NSButton(radioButtonWithTitle: String(localized: "Fill Screen"), target: nil, action: nil)

    var automaticUpdateChecksButton: NSButton?
    var automaticUpdateDownloadsButton: NSButton?

    let clearCacheButton = NSButton(title: String(localized: "Clear Cache"), target: nil, action: nil)
    let resetSettingsButton = NSButton(title: String(localized: "Reset App"), target: nil, action: nil)
    let exportProfileButton = NSButton(title: String(localized: "Export Settings"), target: nil, action: nil)
    let importProfileButton = NSButton(title: String(localized: "Import Settings"), target: nil, action: nil)

    init(
        dependency: AppSettingsPanelDependency,
        visibleSection: AppSettingsSection
    ) {
        self.dependency = dependency
        self.visibleSection = visibleSection
        super.init(frame: .zero)
        setupLayout()
        setupSections()
        bindEvents()
        observeManager()
        observePanelActivation()
        attachActiveForm()
        refreshFromState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let muteStateObserver {
            NotificationCenter.default.removeObserver(muteStateObserver)
        }
        if let loginItemSyncFailureObserver {
            NotificationCenter.default.removeObserver(loginItemSyncFailureObserver)
        }
        if let windowBecameKeyObserver {
            NotificationCenter.default.removeObserver(windowBecameKeyObserver)
        }
    }

    func refreshFromState() {
        // 这是设置页的单一回填入口：所有控件状态都从 manager 快照回填，避免局部控件自己保留旧态。
        isUpdatingUI = true
        defer { isUpdatingUI = false }

        sceneMediaInfoSwitch.state = SceneMediaSourcePreference.isEnabled ? .on : .off
        let settings = dependency.settings
        let visibilityBefore = layoutVisibilitySignature()

        loopSwitch.state = settings.loopPlayback ? .on : .off
        randomSwitch.state = settings.randomPlayback ? .on : .off
        sequentialSwitch.state = settings.sequentialPlayback ? .on : .off

        let autoSwitchAvailable = settings.randomPlayback || settings.sequentialPlayback
        autoSwitchSwitch.state = settings.autoSwitchEnabled ? .on : .off
        autoSwitchSwitch.isEnabled = autoSwitchAvailable
        // 循环播放模式下隐藏自动切换整行（含间隔时间），其他模式下显示。
        autoSwitchRow?.isHidden = !autoSwitchAvailable
        intervalRowView?.isHidden = !(settings.autoSwitchEnabled && autoSwitchAvailable)
        intervalField.isEnabled = autoSwitchAvailable && settings.autoSwitchEnabled
        timeUnitPopup.isEnabled = autoSwitchAvailable && settings.autoSwitchEnabled
        if !intervalField.isEnabled, intervalField.currentEditor() != nil { _ = intervalField.abortEditing() }
        if intervalField.currentEditor() == nil {
            intervalField.stringValue = "\(max(1, settings.randomInterval))"
        }
        selectTimeUnit(settings.timeUnit)

        let clampedVolume = Int(max(0, min(100, round(settings.volume))))
        // 静音是独立门（不改 settings.volume）；滑块/标签显示有效音量，
        // 与"滑到 0=静音、拖离 0=解除"的既有对称行为在视觉上闭合。
        let isMuted = PlaybackMuteState.shared.isMuted
        volumeSlider.doubleValue = isMuted ? 0 : Double(clampedVolume)
        volumeValueLabel.stringValue = isMuted ? "0%" : "\(clampedVolume)%"
        muteSwitch.state = isMuted ? .on : .off

        let clampedRate = max(0.25, min(2.0, settings.playbackRate))
        playbackRateSwitch.state = settings.playbackRateEnabled ? .on : .off
        playbackRateSlider.doubleValue = clampedRate
        playbackRateValueLabel.stringValue = playbackRateLabel(clampedRate)
        // 开关关闭时隐藏滑块和数值标签，只保留开关本身。
        playbackRateControls?.isHidden = !settings.playbackRateEnabled

        // 登录项开关以系统真值对账：注册失败或用户在系统设置里移除后，
        // 面板显示实际状态而不是 settings 里的乐观值。
        // SMAppService 查询是同步系统调用，只在开机自启设置变化、首次回填，
        // 或面板（重新）成为 key 作废缓存后执行（observePanelActivation）；
        // 同一 key 周期内的无关刷新沿用缓存，期间系统侧登录项变化延迟到
        // 下次成为 key 时才对账——这是差分刷新的明确取舍。
        if settings.startOnBoot != lastStartOnBootSetting || lastKnownStartOnBootSystemEnabled == nil {
            lastStartOnBootSetting = settings.startOnBoot
            lastKnownStartOnBootSystemEnabled = (SMAppService.mainApp.status == .enabled)
        }
        startOnBootSwitch.state = (lastKnownStartOnBootSystemEnabled ?? false) ? .on : .off
        restorePlaybackOnLaunchSwitch.state = settings.restorePlaybackOnLaunch ? .on : .off
        syncSystemWallpaperSwitch.state = settings.syncSystemWallpaper ? .on : .off
        webAudioListeningSwitch.state = settings.webWallpaperAudioListening ? .on : .off
        sceneAudioListeningSwitch.state = settings.sceneWallpaperAudioListening ? .on : .off
        keepDockIconSwitch.state = settings.keepDockIconVisible ? .on : .off
        systemAudioSpectrumStylePopup.selectItem(
            at: SystemAudioSpectrumStyle.allCases.firstIndex(of: settings.systemAudioSpectrumStyle)!
        )
        systemAudioSpectrumSwitch.state = settings.systemAudioSpectrumEnabled ? .on : .off
        systemAudioSpectrumOptionsContainer?.isHidden = !settings.systemAudioSpectrumEnabled
        systemAudioSpectrumStylePopup.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumSensitivityPopup.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumBarCountPopup.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumColorWell.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumOffsetXSlider.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumOffsetYSlider.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumPeakCapsSwitch.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumSensitivityPopup.selectItem(
            at: SystemAudioSpectrumSensitivity.allCases.firstIndex(of: settings.systemAudioSpectrumSensitivity)!
        )
        selectSystemAudioSpectrumBarCount(settings.systemAudioSpectrumBarCount)
        systemAudioSpectrumColorWell.color = color(fromHex: settings.systemAudioSpectrumColorHex) ?? .white
        systemAudioSpectrumOffsetXSlider.doubleValue = settings.systemAudioSpectrumOffsetX * 100
        systemAudioSpectrumOffsetYSlider.doubleValue = settings.systemAudioSpectrumOffsetY * 100
        systemAudioSpectrumOffsetXValueLabel.stringValue = "\(Int(round(settings.systemAudioSpectrumOffsetX * 100)))%"
        systemAudioSpectrumOffsetYValueLabel.stringValue = "\(Int(round(settings.systemAudioSpectrumOffsetY * 100)))%"
        systemAudioSpectrumPeakCapsSwitch.state = settings.systemAudioSpectrumPeakCapsEnabled ? .on : .off

        pauseOtherAppFocusedSwitch.state = settings.pauseWhenOtherAppFocused ? .on : .off
        pauseOtherAppFullscreenSwitch.state = settings.pauseWhenOtherAppFullscreen ? .on : .off
        pauseWhenUnpluggedSwitch.state = settings.pauseWhenUnplugged ? .on : .off
        pauseWhenIdleSwitch.state = settings.pauseWhenIdle ? .on : .off
        refreshQualityControls()
        idleTimeoutRowView?.isHidden = !settings.pauseWhenIdle
        selectIdleTimeout(settings.idleTimeoutMinutes)

        multiDisplaySwitch.state = settings.multiDisplayEnabled ? .on : .off
        selectFillMode(settings.videoFillMode)
        libraryBackgroundPopup.selectItem(withTag: LibraryBackgroundStyle.allCases.firstIndex(of: settings.libraryBackgroundStyle) ?? 0)
        libraryCardClickPopup.selectItem(withTag: LibraryCardClickAction.allCases.firstIndex(of: settings.libraryCardClickAction) ?? 0)

        refreshHotkeyRowsIfInputsChanged()
        if layoutVisibilitySignature() != visibilityBefore {
            scheduleDocumentFrameUpdate()
            onFormHeightChanged?()
        }
    }

    private func layoutVisibilitySignature() -> [Bool?] {
        switch visibleSection {
        case .playback: [autoSwitchRow?.isHidden, intervalRowView?.isHidden, playbackRateControls?.isHidden]
        case .system: [systemAudioSpectrumOptionsContainer?.isHidden]
        case .efficiency: [idleTimeoutRowView?.isHidden]
        default: []
        }
    }

    func showSection(_ section: AppSettingsSection) {
        guard visibleSection != section else { return }
        activeForm.removeFromSuperview()
        visibleSection = section
        attachActiveForm()
        if section == .about { refreshUpdaterControls() }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func attachActiveForm() {
        let form = activeForm
        contentContainer.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: SettingsPanelLayout.pageInset),
            form.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: SettingsPanelLayout.pageInset),
            form.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -SettingsPanelLayout.pageInset)
        ])
    }

    private func setupLayout() {
        wantsLayer = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        contentContainer.frame.size.width = SettingsPanelLayout.pageWidth
        scrollView.documentView = contentContainer
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func layout() {
        super.layout()
        scheduleDocumentFrameUpdate()
    }

    func preferredFormHeight(at width: CGFloat) -> CGFloat {
        if contentContainer.frame.width != width { contentContainer.frame.size.width = width }
        contentContainer.layoutSubtreeIfNeeded()
        return activeForm.fittingSize.height + SettingsPanelLayout.pageInset + SettingsPanelLayout.bottomInset
    }

    func updateDocumentFrame() {
        let viewportSize = scrollView.contentSize
        guard viewportSize.width > 0 else { return }

        let targetHeight = max(viewportSize.height, preferredFormHeight(at: viewportSize.width))
        if contentContainer.frame.height != targetHeight { contentContainer.frame.size.height = targetHeight }
    }

    private func bindEvents() {
        // 所有 target/action 在这里集中绑定，避免控件在别处被悄悄改动后难以排查。
        loopSwitch.target = self
        loopSwitch.action = #selector(handleLoopToggle)
        randomSwitch.target = self
        randomSwitch.action = #selector(handleRandomToggle)
        sequentialSwitch.target = self
        sequentialSwitch.action = #selector(handleSequentialToggle)
        autoSwitchSwitch.target = self
        autoSwitchSwitch.action = #selector(handleAutoSwitchToggle)
        timeUnitPopup.target = self
        timeUnitPopup.action = #selector(handleTimeUnitChange)
        volumeSlider.target = self
        volumeSlider.action = #selector(handleVolumeChange)
        muteSwitch.target = self
        muteSwitch.action = #selector(handleMuteToggle)

        playbackRateSlider.target = self
        playbackRateSlider.action = #selector(handlePlaybackRateChange)
        playbackRateSwitch.target = self
        playbackRateSwitch.action = #selector(handlePlaybackRateSwitchToggle)

        startOnBootSwitch.target = self
        startOnBootSwitch.action = #selector(handleStartOnBootToggle)
        restorePlaybackOnLaunchSwitch.target = self
        restorePlaybackOnLaunchSwitch.action = #selector(handleRestorePlaybackOnLaunchToggle)
        syncSystemWallpaperSwitch.target = self
        syncSystemWallpaperSwitch.action = #selector(handleSyncSystemWallpaperToggle)
        sceneMediaInfoSwitch.target = self
        sceneMediaInfoSwitch.action = #selector(handleSceneMediaInfoToggle)
        systemAudioSpectrumSwitch.target = self
        systemAudioSpectrumSwitch.action = #selector(handleSystemAudioSpectrumToggle)
        webAudioListeningSwitch.target = self
        webAudioListeningSwitch.action = #selector(handleEngineAudioListeningChange(_:))
        sceneAudioListeningSwitch.target = self
        sceneAudioListeningSwitch.action = #selector(handleEngineAudioListeningChange(_:))
        systemAudioSpectrumStylePopup.target = self
        systemAudioSpectrumStylePopup.action = #selector(handleSystemAudioSpectrumStyleChange)
        systemAudioSpectrumSensitivityPopup.target = self
        systemAudioSpectrumSensitivityPopup.action = #selector(handleSystemAudioSpectrumSensitivityChange)
        systemAudioSpectrumBarCountPopup.target = self
        systemAudioSpectrumBarCountPopup.action = #selector(handleSystemAudioSpectrumBarCountChange)
        systemAudioSpectrumColorWell.target = self
        systemAudioSpectrumColorWell.action = #selector(handleSystemAudioSpectrumColorChange)
        systemAudioSpectrumOffsetXSlider.target = self
        systemAudioSpectrumOffsetXSlider.action = #selector(handleSystemAudioSpectrumOffsetChange)
        systemAudioSpectrumOffsetYSlider.target = self
        systemAudioSpectrumOffsetYSlider.action = #selector(handleSystemAudioSpectrumOffsetChange)
        systemAudioSpectrumPeakCapsSwitch.target = self
        systemAudioSpectrumPeakCapsSwitch.action = #selector(handleSystemAudioSpectrumPeakCapsToggle)

        pauseOtherAppFocusedSwitch.target = self
        pauseOtherAppFocusedSwitch.action = #selector(handlePerformanceToggle)
        pauseOtherAppFullscreenSwitch.target = self
        pauseOtherAppFullscreenSwitch.action = #selector(handlePerformanceToggle)
        pauseWhenUnpluggedSwitch.target = self
        pauseWhenUnpluggedSwitch.action = #selector(handlePerformanceToggle)
        pauseWhenIdleSwitch.target = self
        pauseWhenIdleSwitch.action = #selector(handlePerformanceToggle)
        idleTimeoutPopup.target = self
        idleTimeoutPopup.action = #selector(handleIdleTimeoutChange)

        keepDockIconSwitch.target = self
        keepDockIconSwitch.action = #selector(handleKeepDockIconToggle)
        multiDisplaySwitch.target = self
        multiDisplaySwitch.action = #selector(handleMultiDisplayToggle)
        libraryBackgroundPopup.target = self
        libraryBackgroundPopup.action = #selector(handleLibraryBackgroundChange)
        libraryCardClickPopup.target = self
        libraryCardClickPopup.action = #selector(handleLibraryCardClickChange)
        fillModeFitButton.target = self
        fillModeFitButton.action = #selector(handleFillModeChange(_:))
        fillModeFillButton.target = self
        fillModeFillButton.action = #selector(handleFillModeChange(_:))

        clearCacheButton.target = self
        clearCacheButton.action = #selector(handleClearCache)
        exportProfileButton.target = self
        exportProfileButton.action = #selector(handleExportProfile)
        importProfileButton.target = self
        importProfileButton.action = #selector(handleImportProfile)
        resetSettingsButton.target = self
        resetSettingsButton.action = #selector(handleResetSettings)
    }

    private func observeManager() {
        // 设置页只订阅 manager 的最终快照，不自己维护派生状态。
        dependency.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFromState()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshScenePostProcessingMenu(PlaybackQualityPreference.current.scene.postProcessing) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .sceneDaemonAnimationCadenceDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSceneFrameRateReadout() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .sceneDaemonRasterSamplesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSceneRenderReadouts() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .sceneDaemonPreparedQualityDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let requested = PlaybackQualityPreference.current.scene
                self?.refreshSceneQualityReapplyTitle(requested)
                self?.refreshSceneRenderReadouts(requested)
            }
            .store(in: &cancellables)
        // 静音可能来自开关/热键/状态栏三种入口；volume>0 时静音不产生
        // settings 写入，必须靠静音通知驱动回填（滑块显示 0/开关状态）。
        muteStateObserver = NotificationCenter.default.addObserver(
            forName: .playbackMuteStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isUpdatingUI else { return }
            self.refreshFromState()
        }
        // F18：SMAppService 注册/注销失败由 WallpaperManager.updateLoginItemStatus()
        // 发出 .wallpaperManagerLoginItemSyncFailed；开关已随系统真值回滚，
        // 这里是声明的"错误回传 UI"订阅端，把失败原因呈现给用户。
        loginItemSyncFailureObserver = NotificationCenter.default.addObserver(
            forName: .wallpaperManagerLoginItemSyncFailed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.presentLoginItemSyncFailure(notification)
        }
    }

    /// F17×F18 对账闭环：面板（重新）成为 key（首次打开、从系统设置切回）
    /// 时作废 SMAppService 同步查询缓存并立即重查，覆盖"面板打开期间用户
    /// 在系统设置增删登录项"的对账场景。
    private func observePanelActivation() {
        windowBecameKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let window = notification.object as? NSWindow,
                  window === self.window else { return }
            self.lastStartOnBootSetting = nil
            self.lastKnownStartOnBootSystemEnabled = nil
            guard !self.isUpdatingUI else { return }
            self.refreshFromState()
        }
    }

    /// 登录项注册/注销失败的用户可见呈现：开关已随系统真值弹回，
    /// 这里解释原因，消除"静默弹回、无失败原因"。
    private func presentLoginItemSyncFailure(_ notification: Notification) {
        let operation = notification.userInfo?["operation"] as? String
        let failureDetail = (notification.userInfo?["error"] as? NSError)?.localizedDescription
        let verb = operation == "unregister" ? String(localized: "Unregister") : String(localized: "Register")
        var message = String(localized: "Launch at login: \(verb) didn’t take effect; the switch now reflects the actual system state.")
        if let failureDetail, !failureDetail.isEmpty {
            message += String(localized: "\nReason: \(failureDetail)")
        }
        let alert = makeAppAlert(
            title: String(localized: "Couldn’t Update Launch at Login"),
            message: message,
            style: .warning
        )
        presentAppAlert(alert, in: preferredHostWindow())
    }

    @objc private func handleLoopToggle() {
        guard !isUpdatingUI else { return }
        dependency.actions.setLoopPlaybackEnabled(loopSwitch.state == .on)
    }

    @objc private func handleRandomToggle() {
        guard !isUpdatingUI else { return }
        dependency.actions.setRandomPlaybackEnabled(randomSwitch.state == .on)
    }

    @objc private func handleSequentialToggle() {
        guard !isUpdatingUI else { return }
        dependency.actions.setSequentialPlaybackEnabled(sequentialSwitch.state == .on)
    }

    @objc private func handleAutoSwitchToggle() {
        guard !isUpdatingUI else { return }
        let enabled = autoSwitchSwitch.state == .on
        dependency.settings.autoSwitchEnabled = enabled
        // loop 语义（自动切换开启=循环当前项等 timer 到期）由 manager 的
        // 差分投影统一下发，视图不再直呼引擎。
        if enabled {
            dependency.actions.startAutoSwitchTimer()
        } else {
            dependency.actions.stopAutoSwitchTimer()
        }
    }

    @objc private func handleTimeUnitChange() {
        guard !isUpdatingUI else { return }
        guard let unit = timeUnitPopup.selectedItem?.representedObject as? TimeUnit else { return }
        dependency.settings.timeUnit = unit
        dependency.actions.refreshAutoSwitchTimerIfNeeded()
    }

    @objc private func handleVolumeChange() {
        guard !isUpdatingUI else { return }
        let clampedVolume = Int(max(0, min(100, round(volumeSlider.doubleValue))))
        volumeValueLabel.stringValue = "\(clampedVolume)%"
        dependency.actions.updateVolume(Double(clampedVolume))
        // 音量与静音是两个公共意图：滑杆只更新主音量，0 边界再同步静音。
        if PlaybackMuteState.shared.isMuted != (clampedVolume == 0) {
            PlaybackCommandMultiplexer.shared.dispatch(.setMuted(clampedVolume == 0))
        }
    }

    @objc private func handleMuteToggle() {
        guard !isUpdatingUI else { return }
        // 经命令层广播（M0.2）：video=音量归零/恢复；scene=Sound 层 0 增益。
        PlaybackCommandMultiplexer.shared.dispatch(
            .setMuted(muteSwitch.state == .on)
        )
    }

    @objc private func handlePlaybackRateChange() {
        guard !isUpdatingUI else { return }
        // 与滑杆范围一致，步长 0.05，限制在 0.25x 到 2.0x。
        let snapped = (playbackRateSlider.doubleValue * 20).rounded() / 20
        let clamped = max(0.25, min(2.0, snapped))
        playbackRateValueLabel.stringValue = playbackRateLabel(clamped)
        // 投影经 manager 的 sink 差分（playbackRate 组）单点下发。
        dependency.settings.playbackRate = clamped
    }

    private func playbackRateLabel(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    @objc private func handlePlaybackRateSwitchToggle() {
        guard !isUpdatingUI else { return }
        let enabled = playbackRateSwitch.state == .on
        dependency.settings.playbackRateEnabled = enabled
        playbackRateControls?.isHidden = !enabled
        // 关闭时把速率重置为正常速度，避免关掉开关后引擎还在以异常速率播放。
        if !enabled {
            dependency.settings.playbackRate = 1.0
        }
    }

    @objc private func handleSceneMediaInfoToggle() {
        guard !isUpdatingUI else { return }
        let enabled = sceneMediaInfoSwitch.state == .on
        SceneMediaSourcePreference.setEnabled(enabled)
        let checkID = UUID()
        sceneMediaAuthorizationCheckID = checkID
        guard enabled, let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            .first(where: { !$0.isTerminated })?.processIdentifier else { return }
        // The producer owns first-time consent. This user action only checks
        // whether a previous refusal needs a System Settings recovery path.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard case .denied = SystemMusicPlayerSource.silentAuthorization(pid: pid) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sceneMediaAuthorizationCheckID == checkID,
                      SceneMediaSourcePreference.isEnabled, let window = self.window, window.isVisible else { return }
                let alert = makeAppAlert(title: String(localized: "Allow Access to Apple Music"),
                    message: String(localized: "Allow access to Music in “Privacy & Security → Automation.” After granting access, turn “Wallpaper Song Info” back on."),
                    buttons: [String(localized: "Open System Settings"), String(localized: "Later")])
                presentAppAlert(alert, in: window) { response in
                    guard response == .alertFirstButtonReturn else { return }
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            }
        }
    }

    @objc private func handleStartOnBootToggle() {
        guard !isUpdatingUI else { return }
        dependency.settings.startOnBoot = (startOnBootSwitch.state == .on)
        dependency.actions.updateLoginItemStatus()
    }

    @objc private func handleRestorePlaybackOnLaunchToggle() {
        guard !isUpdatingUI else { return }
        // 只在下一次启动时被消费，无需任何引擎投影。
        dependency.settings.restorePlaybackOnLaunch = (restorePlaybackOnLaunchSwitch.state == .on)
    }

    @objc private func handleSyncSystemWallpaperToggle() {
        guard !isUpdatingUI else { return }
        dependency.actions.setSyncSystemWallpaperEnabled(syncSystemWallpaperSwitch.state == .on)
    }

    @objc private func handleSystemAudioSpectrumToggle() {
        guard !isUpdatingUI else { return }
        // 投影经 manager 的 sink 差分（频谱 8 字段组）单点下发。
        dependency.settings.systemAudioSpectrumEnabled = (systemAudioSpectrumSwitch.state == .on)
    }

    @objc private func handleKeepDockIconToggle() {
        dependency.settings.keepDockIconVisible = keepDockIconSwitch.state == .on
    }

    @objc private func handleEngineAudioListeningChange(_ sender: NSButton) {
        if sender === webAudioListeningSwitch {
            dependency.settings.webWallpaperAudioListening = sender.state == .on
        } else {
            dependency.settings.sceneWallpaperAudioListening = sender.state == .on
        }
    }

    @objc private func handleSystemAudioSpectrumStyleChange() {
        guard let style = systemAudioSpectrumStylePopup.selectedItem?.representedObject as? SystemAudioSpectrumStyle else { return }
        dependency.settings.systemAudioSpectrumStyle = style
    }

    @objc private func handleSystemAudioSpectrumSensitivityChange() {
        guard !isUpdatingUI,
              let sensitivity = systemAudioSpectrumSensitivityPopup.selectedItem?.representedObject as? SystemAudioSpectrumSensitivity
        else { return }
        dependency.settings.systemAudioSpectrumSensitivity = sensitivity
    }

    @objc private func handleSystemAudioSpectrumBarCountChange() {
        guard !isUpdatingUI else { return }
        guard let barCount = systemAudioSpectrumBarCountPopup.selectedItem?.representedObject as? Int else { return }
        dependency.settings.systemAudioSpectrumBarCount = barCount
    }

    @objc private func handleSystemAudioSpectrumColorChange() {
        guard !isUpdatingUI else { return }
        dependency.settings.systemAudioSpectrumColorHex = hexString(from: systemAudioSpectrumColorWell.color)
    }

    @objc private func handleSystemAudioSpectrumOffsetChange() {
        guard !isUpdatingUI else { return }
        dependency.settings.systemAudioSpectrumOffsetX = systemAudioSpectrumOffsetXSlider.doubleValue / 100
        dependency.settings.systemAudioSpectrumOffsetY = systemAudioSpectrumOffsetYSlider.doubleValue / 100
        systemAudioSpectrumOffsetXValueLabel.stringValue = "\(Int(round(systemAudioSpectrumOffsetXSlider.doubleValue)))%"
        systemAudioSpectrumOffsetYValueLabel.stringValue = "\(Int(round(systemAudioSpectrumOffsetYSlider.doubleValue)))%"
    }

    @objc private func handleSystemAudioSpectrumPeakCapsToggle() {
        guard !isUpdatingUI else { return }
        dependency.settings.systemAudioSpectrumPeakCapsEnabled = (systemAudioSpectrumPeakCapsSwitch.state == .on)
    }

    private func selectSystemAudioSpectrumBarCount(_ barCount: Int) {
        if let item = systemAudioSpectrumBarCountPopup.itemArray.first(where: { ($0.representedObject as? Int) == barCount }) {
            systemAudioSpectrumBarCountPopup.select(item)
        }
    }

    func color(fromHex hex: String) -> NSColor? {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&value) else { return nil }
        return NSColor(
            calibratedRed: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }

    private func hexString(from color: NSColor) -> String {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    @objc private func handlePerformanceToggle() {
        guard !isUpdatingUI else { return }
        dependency.settings.pauseWhenOtherAppFocused = (pauseOtherAppFocusedSwitch.state == .on)
        dependency.settings.pauseWhenOtherAppFullscreen = (pauseOtherAppFullscreenSwitch.state == .on)
        dependency.settings.pauseWhenUnplugged = (pauseWhenUnpluggedSwitch.state == .on)
        dependency.settings.pauseWhenIdle = (pauseWhenIdleSwitch.state == .on)
        dependency.actions.applyEngineSettings(false)
    }

    @objc private func handleIdleTimeoutChange() {
        guard !isUpdatingUI else { return }
        guard let value = idleTimeoutPopup.selectedItem?.representedObject as? Int else { return }
        dependency.settings.idleTimeoutMinutes = value
        dependency.actions.applyEngineSettings(false)
    }

    @objc private func handleMultiDisplayToggle() {
        guard !isUpdatingUI else { return }
        dependency.settings.multiDisplayEnabled = (multiDisplaySwitch.state == .on)
        dependency.actions.applyEngineSettings(true)
    }

    @objc private func handleFillModeChange(_ sender: NSButton) {
        guard !isUpdatingUI else { return }
        let mode: VideoFillMode = (sender == fillModeFitButton) ? .aspectFit : .aspectFill
        selectFillMode(mode)
        // 填充模式经 manager 的 sink 差分（videoFillMode 组）投影引擎
        // （setFillMode 内部同步镜像，屏参变化/崩溃恢复不回跳）。
        dependency.settings.videoFillMode = mode
    }

    @objc private func handleLibraryBackgroundChange() {
        guard !isUpdatingUI, let style = libraryBackgroundPopup.selectedItem?.representedObject as? LibraryBackgroundStyle else { return }
        dependency.settings.libraryBackgroundStyle = style
    }

    @objc private func handleLibraryCardClickChange() {
        guard !isUpdatingUI, let action = libraryCardClickPopup.selectedItem?.representedObject as? LibraryCardClickAction else { return }
        dependency.settings.libraryCardClickAction = action
    }

    @objc private func handleClearCache() {
        let hostWindow = preferredHostWindow()
        let alert = makeAppAlert(
            title: String(localized: "Clear Cache"),
            message: String(localized: "This clears thumbnail, video still, online browsing, and original preview caches, and resets Workshop browsing state. Media, downloads, and settings are kept."),
            buttons: [String(localized: "Clear"), String(localized: "Cancel")]
        )
        presentAppAlert(alert, in: hostWindow) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let title = self.clearCacheButton.title
            self.clearCacheButton.isEnabled = false
            self.clearCacheButton.title = String(localized: "Cleaning Up…")
            Task { @MainActor in
                defer {
                    self.clearCacheButton.isEnabled = true
                    self.clearCacheButton.title = title
                }
                await self.dependency.actions.clearAllCaches()
                guard hostWindow?.isVisible != false else { return }
                let result = makeAppAlert(title: String(localized: "Cache cleared"), message: String(localized: "It will be regenerated on demand the next time you browse."))
                presentAppAlert(result, in: hostWindow)
            }
        }
    }

    @objc func handleExportProfile() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Personal Settings")
        panel.nameFieldStringValue = "MyWallpaperX-Profile.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.isExtensionHidden = false

        presentSavePanel(panel) { [weak self] targetURL in
            guard let self, let targetURL else { return }
            let hostWindow = self.preferredHostWindow()
            self.exportProfileButton.isEnabled = false
            self.importProfileButton.isEnabled = false
            Task { @MainActor in
                defer { self.exportProfileButton.isEnabled = true; self.importProfileButton.isEnabled = true }
                do {
                    let summary = try await self.dependency.actions.exportPersonalSettings(targetURL)
                    guard let hostWindow, hostWindow.isVisible else { return }
                    let done = makeAppAlert(title: String(localized: "Export Complete"),
                        message: String(localized: "Exported \(summary.wallpaperCount) wallpaper configurations and \(summary.tagCount) playlists."))
                    presentAppAlert(done, in: hostWindow)
                } catch {
                    guard let hostWindow, hostWindow.isVisible else { return }
                    let failed = makeAppAlert(title: String(localized: "Export Failed"), message: error.localizedDescription)
                    presentAppAlert(failed, in: hostWindow)
                }
            }
        }
    }

    @objc func handleImportProfile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Personal Settings")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        presentOpenPanel(panel) { [weak self] sourceURL in
            guard let self, let sourceURL else { return }
            let hostWindow = self.preferredHostWindow()
            let confirm = makeAppAlert(
                title: String(localized: "Import Personal Settings"),
                message: String(localized: "Settings, playlists, and favorites will be merged. Playlists with matching UUIDs update their details and gain members. Missing files keep their references and won’t be downloaded or played."),
                buttons: [String(localized: "Import"), String(localized: "Cancel")]
            )
            presentAppAlert(confirm, in: hostWindow) { [weak self] confirmResponse in
                guard let self, confirmResponse == .alertFirstButtonReturn else { return }
                self.exportProfileButton.isEnabled = false
                self.importProfileButton.isEnabled = false
                Task { @MainActor in
                    defer {
                        self.exportProfileButton.isEnabled = true
                        self.importProfileButton.isEnabled = true
                        self.refreshFromState()
                    }
                    do {
                        let summary = try await self.dependency.actions.importPersonalSettings(sourceURL)
                        guard let hostWindow, hostWindow.isVisible else { return }
                        let done = makeAppAlert(
                            title: String(localized: "Import Complete"),
                            message: String(localized: "Updated \(summary.mergedWallpaperCount) wallpapers and added \(summary.createdWallpaperCount); imported \(summary.tagCount) playlists.\n\(summary.missingPathCount) missing paths kept their references."))
                        presentAppAlert(done, in: hostWindow)
                    } catch {
                        guard let hostWindow, hostWindow.isVisible else { return }
                        let failed = makeAppAlert(title: String(localized: "Import Incomplete"), message: error.localizedDescription)
                        presentAppAlert(failed, in: hostWindow)
                    }
                }
            }
        }
    }

    private func preferredHostWindow() -> NSWindow? {
        if let window, window.isVisible {
            return window
        }
        return appModalHostWindow()
    }

    private func presentSavePanel(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) {
        // 优先 sheet，只有窗口不在前台时才回退到 modal，减少导入导出对主界面的打断。
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            let hostWindow = self.preferredHostWindow()
            NSApp.activate(ignoringOtherApps: true)

            if let hostWindow, hostWindow.isVisible {
                panel.beginSheetModal(for: hostWindow) { response in
                    panel.orderOut(nil)
                    completion(response == .OK ? panel.url : nil)
                }
                return
            }

            let response = panel.runModal()
            completion(response == .OK ? panel.url : nil)
        }
    }

    private func presentOpenPanel(_ panel: NSOpenPanel, completion: @escaping (URL?) -> Void) {
        // 导入面板与导出面板共用同一展示策略，保证行为和系统面板一致。
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            let hostWindow = self.preferredHostWindow()
            NSApp.activate(ignoringOtherApps: true)

            if let hostWindow, hostWindow.isVisible {
                panel.beginSheetModal(for: hostWindow) { response in
                    panel.orderOut(nil)
                    completion(response == .OK ? panel.url : nil)
                }
                return
            }

            let response = panel.runModal()
            completion(response == .OK ? panel.urls.first : nil)
        }
    }

    @objc private func handleResetSettings() {
        let hostWindow = preferredHostWindow()
        let alert = makeAppAlert(
            title: String(localized: "Reset App"),
            message: String(localized: "This clears the app’s library records, favorites, playlists, recents, and saved screen saver content, and restores default settings. Original media and downloaded files on disk are kept. This can’t be undone."),
            buttons: [String(localized: "Cancel"), String(localized: "Reset")]
        )
        presentAppAlert(alert, in: hostWindow) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            self.dependency.actions.resetToFreshInstallState()
        }
    }

    private func selectTimeUnit(_ unit: TimeUnit) {
        if let index = timeUnitPopup.itemArray.firstIndex(where: { ($0.representedObject as? TimeUnit) == unit }) {
            timeUnitPopup.selectItem(at: index)
        }
    }

    private func selectIdleTimeout(_ minutes: Int) {
        if let index = idleTimeoutPopup.itemArray.firstIndex(where: { ($0.representedObject as? Int) == minutes }) {
            idleTimeoutPopup.selectItem(at: index)
        } else {
            idleTimeoutPopup.selectItem(at: 0)
        }
    }

    private func selectFillMode(_ mode: VideoFillMode) {
        fillModeFitButton.state = (mode == .aspectFit) ? .on : .off
        fillModeFillButton.state = (mode == .aspectFill) ? .on : .off
    }
}

extension AppKitSettingsContainerView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        guard !isUpdatingUI, let textField = notification.object as? NSTextField else { return }
        let input = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if textField === sceneFPSField {
            let value = Int(input).flatMap(AnimationFrameRate.init(rawValue:))
            commitSceneFrameRate(value)
            return
        }
        guard textField === intervalField else { return }
        let parsed = Int(input) ?? dependency.settings.randomInterval
        dependency.settings.randomInterval = max(1, parsed)
        dependency.actions.refreshAutoSwitchTimerIfNeeded()
    }
}
