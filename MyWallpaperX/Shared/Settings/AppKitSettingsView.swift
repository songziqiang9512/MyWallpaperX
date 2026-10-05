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
    case playbackModes
    case audio
    case system
    case hotkeys
    case efficiency
    case display
    case maintenance

}

final class AppKitSettingsContainerView: NSView {
    private enum LayoutSeed {
        static let initialDocumentWidth: CGFloat = 760
        static let initialDocumentHeight: CGFloat = 1200
    }

    final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            translatesAutoresizingMaskIntoConstraints = false
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
    // 这里记录三条昂贵路径（热键菜单重建、SMAppService 同步查询、fittingSize 整树求解）
    // 的相关输入，值未变时跳过对应工作。
    var lastHotkeyInputsSignature: [String] = []
    private var lastStartOnBootSetting: Bool?
    private var lastKnownStartOnBootSystemEnabled: Bool?
    private var scrollToTopObserver: NSObjectProtocol?
    private var muteStateObserver: NSObjectProtocol?
    private var loginItemSyncFailureObserver: NSObjectProtocol?
    private var windowBecameKeyObserver: NSObjectProtocol?
    var visibleSections: Set<AppSettingsSection>
    private let topContentInset: CGFloat
    private let scrollView = NSScrollView()
    let contentContainer = FlippedDocumentView()

    let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let playbackModesSection = SettingsGroupView(title: "播放模式")
    let audioSection = SettingsGroupView(title: "音频与速率")
    let systemSection = SettingsGroupView(title: "系统行为")
    let hotkeysSection = SettingsGroupView(title: "快捷键")
    let efficiencySection = SettingsGroupView(title: "节能与暂停")
    let displaySection = SettingsGroupView(title: "显示设置")
    let maintenanceSection = SettingsGroupView(title: nil)

    let loopSwitch = NSSwitch()
    let randomSwitch = NSSwitch()
    let sequentialSwitch = NSSwitch()
    let autoSwitchSwitch = NSSwitch()
    let intervalField = NSTextField()
    let timeUnitPopup = NSPopUpButton()
    var intervalRowView: NSView?
    var autoSwitchRowView: NSView?
    let volumeSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    let volumeValueLabel = NSTextField(labelWithString: "50%")
    let muteSwitch = NSSwitch()

    let playbackRateSlider = NSSlider(value: 1.0, minValue: 0.0, maxValue: 2.0, target: nil, action: nil)
    let playbackRateValueLabel = NSTextField(labelWithString: "1.0x")
    let playbackRateSwitch = NSSwitch()
    var playbackRateRowView: NSView?

    let startOnBootSwitch = NSSwitch()
    let restorePlaybackOnLaunchSwitch = NSSwitch()
    let syncSystemWallpaperSwitch = NSSwitch()
    let sceneHDRDisplaySwitch = NSSwitch()
    let sceneMediaSourcePopup = NSPopUpButton()
    let sceneMediaAuthorizationButton = NSButton(title: "授权读取", target: nil, action: nil)
    let systemAudioSpectrumSwitch = NSSwitch()
    let systemAudioSpectrumStylePopup = NSPopUpButton()
    let systemAudioSpectrumSensitivityPopup = NSPopUpButton()
    let systemAudioSpectrumBarCountPopup = NSPopUpButton()
    let systemAudioSpectrumColorWell = NSColorWell()
    let systemAudioSpectrumOffsetXSlider = NSSlider(value: 0, minValue: -30, maxValue: 30, target: nil, action: nil)
    let systemAudioSpectrumOffsetYSlider = NSSlider(value: 0, minValue: -20, maxValue: 20, target: nil, action: nil)
    let systemAudioSpectrumOffsetXValueLabel = NSTextField(labelWithString: "0%")
    let systemAudioSpectrumOffsetYValueLabel = NSTextField(labelWithString: "0%")
    let systemAudioSpectrumPeakCapsSwitch = NSSwitch()
    var systemAudioSpectrumOptionsContainer: NSView?
    let systemHotkeysSwitch = NSSwitch()
    let hotkeyRowsStack = NSStackView()
    var hotkeyRowsContainer: NSView?
    var systemAudioSpectrumRowView: NSView?
    var hotkeyEnableSwitches: [SystemHotkeyAction: NSSwitch] = [:]
    var hotkeyPopups: [SystemHotkeyAction: NSPopUpButton] = [:]

    let pauseOtherAppFocusedSwitch = NSSwitch()
    let pauseOtherAppFullscreenSwitch = NSSwitch()
    let pauseWhenUnpluggedSwitch = NSSwitch()
    let pauseWhenIdleSwitch = NSSwitch()
    let idleTimeoutPopup = NSPopUpButton()
    var idleTimeoutRowView: NSView?

    /// Scene 引擎性能预算档（60=standard 全量，30=efficient 减频减容量）。
    let sceneMaxFPSSegmented = NSSegmentedControl(
        labels: ["30 FPS", "60 FPS"], trackingMode: .selectOne, target: nil,
        action: nil
    )

    let multiDisplaySwitch = NSSwitch()
    let fillModeFitButton = NSButton(radioButtonWithTitle: VideoFillMode.aspectFit.rawValue, target: nil, action: nil)
    let fillModeFillButton = NSButton(radioButtonWithTitle: VideoFillMode.aspectFill.rawValue, target: nil, action: nil)

    let clearCacheButton = NSButton(title: "清除缓存", target: nil, action: nil)
    let resetSettingsButton = NSButton(title: "重置默认", target: nil, action: nil)
    let exportProfileButton = NSButton(title: "导出设置", target: nil, action: nil)
    let importProfileButton = NSButton(title: "导入设置", target: nil, action: nil)

    init(
        dependency: AppSettingsPanelDependency,
        visibleSections: Set<AppSettingsSection>,
        topContentInset: CGFloat
    ) {
        self.dependency = dependency
        self.visibleSections = visibleSections
        self.topContentInset = topContentInset
        super.init(frame: .zero)
        setupLayout()
        setupSections()
        primeInitialDocumentFrame()
        applyNativeControlSizes()
        bindEvents()
        observeManager()
        observePanelActivation()
        observeScrollToTopRequests()
        applyVisibleSections()
        refreshFromState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let scrollToTopObserver {
            NotificationCenter.default.removeObserver(scrollToTopObserver)
        }
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

        sceneHDRDisplaySwitch.state = SceneHDRDisplayPreference.isEnabled ? .on : .off
        let mediaSource = SceneMediaSourcePreference.current
        sceneMediaSourcePopup.selectItem(withTag: mediaSource == .systemNowPlaying ? 2 : (mediaSource == .appleMusic ? 1 : 0))
        sceneMediaAuthorizationButton.isEnabled = mediaSource == .appleMusic
        let settings = dependency.settings
        let visibilityBefore = layoutVisibilitySignature()

        loopSwitch.state = settings.loopPlayback ? .on : .off
        randomSwitch.state = settings.randomPlayback ? .on : .off
        sequentialSwitch.state = settings.sequentialPlayback ? .on : .off

        let autoSwitchAvailable = settings.randomPlayback || settings.sequentialPlayback
        autoSwitchSwitch.state = settings.autoSwitchEnabled ? .on : .off
        autoSwitchSwitch.isEnabled = autoSwitchAvailable
        // 循环播放模式下隐藏自动切换整行（含间隔时间），其他模式下显示。
        autoSwitchRowView?.isHidden = !autoSwitchAvailable
        intervalRowView?.isHidden = !(settings.autoSwitchEnabled && autoSwitchAvailable)
        intervalField.isEnabled = autoSwitchAvailable && settings.autoSwitchEnabled
        timeUnitPopup.isEnabled = autoSwitchAvailable && settings.autoSwitchEnabled
        intervalField.stringValue = "\(max(1, settings.randomInterval))"
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
        playbackRateValueLabel.stringValue = String(format: "%.2gx", clampedRate)
        // 开关关闭时隐藏滑块和数值标签，只保留开关本身。
        playbackRateSlider.isHidden = !settings.playbackRateEnabled
        playbackRateValueLabel.isHidden = !settings.playbackRateEnabled

        // 登录项开关以系统真值对账：注册失败或用户在系统设置里移除后，
        // 面板显示实际状态而不是 settings 里的乐观值。
        // SMAppService 查询是同步系统调用，只在开机自启设置变化、首次回填，
        // 或面板（重新）成为 key 作废缓存后执行（observePanelActivation）；
        // 同一 key 周期内的无关刷新沿用缓存，期间系统侧登录项变化延迟到
        // 下次成为 key 时才对账——这是差分刷新的明确取舍。
        if #available(macOS 13.0, *) {
            if settings.startOnBoot != lastStartOnBootSetting || lastKnownStartOnBootSystemEnabled == nil {
                lastStartOnBootSetting = settings.startOnBoot
                lastKnownStartOnBootSystemEnabled = (SMAppService.mainApp.status == .enabled)
            }
            startOnBootSwitch.state = (lastKnownStartOnBootSystemEnabled ?? false) ? .on : .off
        } else {
            startOnBootSwitch.state = settings.startOnBoot ? .on : .off
        }
        restorePlaybackOnLaunchSwitch.state = settings.restorePlaybackOnLaunch ? .on : .off
        syncSystemWallpaperSwitch.state = settings.syncSystemWallpaper ? .on : .off
        systemAudioSpectrumSwitch.state = settings.systemAudioSpectrumEnabled ? .on : .off
        systemAudioSpectrumOptionsContainer?.isHidden = !settings.systemAudioSpectrumEnabled
        systemAudioSpectrumStylePopup.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumSensitivityPopup.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumBarCountPopup.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumColorWell.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumOffsetXSlider.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumOffsetYSlider.isEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumPeakCapsSwitch.isEnabled = settings.systemAudioSpectrumEnabled
        selectSystemAudioSpectrumStyle(settings.systemAudioSpectrumStyle)
        selectSystemAudioSpectrumSensitivity(settings.systemAudioSpectrumSensitivity)
        selectSystemAudioSpectrumBarCount(settings.systemAudioSpectrumBarCount)
        systemAudioSpectrumColorWell.color = color(fromHex: settings.systemAudioSpectrumColorHex) ?? .white
        systemAudioSpectrumOffsetXSlider.doubleValue = settings.systemAudioSpectrumOffsetX * 100
        systemAudioSpectrumOffsetYSlider.doubleValue = settings.systemAudioSpectrumOffsetY * 100
        systemAudioSpectrumOffsetXValueLabel.stringValue = "\(Int(round(settings.systemAudioSpectrumOffsetX * 100)))%"
        systemAudioSpectrumOffsetYValueLabel.stringValue = "\(Int(round(settings.systemAudioSpectrumOffsetY * 100)))%"
        systemAudioSpectrumPeakCapsSwitch.state = settings.systemAudioSpectrumPeakCapsEnabled ? .on : .off
        systemHotkeysSwitch.state = settings.systemHotkeysEnabled ? .on : .off
        hotkeyRowsContainer?.isHidden = !settings.systemHotkeysEnabled

        pauseOtherAppFocusedSwitch.state = settings.pauseWhenOtherAppFocused ? .on : .off
        pauseOtherAppFullscreenSwitch.state = settings.pauseWhenOtherAppFullscreen ? .on : .off
        pauseWhenUnpluggedSwitch.state = settings.pauseWhenUnplugged ? .on : .off
        pauseWhenIdleSwitch.state = settings.pauseWhenIdle ? .on : .off
        sceneMaxFPSSegmented.selectedSegment =
            PlaybackPerformanceProfile.current == .efficient ? 0 : 1
        idleTimeoutRowView?.isHidden = !settings.pauseWhenIdle
        selectIdleTimeout(settings.idleTimeoutMinutes)

        multiDisplaySwitch.state = settings.multiDisplayEnabled ? .on : .off
        selectFillMode(settings.videoFillMode)

        refreshHotkeyRowsIfInputsChanged()
        applyVisibleSections()
        // fittingSize 对整棵内容树求解 document 高度，只在可见性行/分区实际变化时重算。
        if layoutVisibilitySignature() != visibilityBefore {
            refreshSectionChromeAndLayout()
        }
    }

    /// 影响文档高度求解的可见性快照：分区显隐 + 各整行/嵌入容器显隐，
    /// 以及播放速率行内会改变行高的滑块/数值标签。
    private func layoutVisibilitySignature() -> [Bool?] {
        [
            playbackModesSection.isHidden,
            audioSection.isHidden,
            systemSection.isHidden,
            hotkeysSection.isHidden,
            efficiencySection.isHidden,
            displaySection.isHidden,
            maintenanceSection.isHidden,
            autoSwitchRowView?.isHidden,
            intervalRowView?.isHidden,
            playbackRateSlider.isHidden,
            playbackRateValueLabel.isHidden,
            systemAudioSpectrumOptionsContainer?.isHidden,
            hotkeyRowsContainer?.isHidden,
            idleTimeoutRowView?.isHidden
        ]
    }

    func updateVisibleSections(_ visibleSections: Set<AppSettingsSection>) {
        guard self.visibleSections != visibleSections else { return }
        self.visibleSections = visibleSections
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyVisibleSections()
            self.refreshSectionChromeAndLayout()
        }
    }

    private func setupLayout() {
        // 设置页内容使用滚动承载，让内容可以自然穿入顶部材质过渡区。
        wantsLayer = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        // 给 documentView 一个非零初始尺寸，避免内部行在宽度为 0 的中间态下提前解约束。
        contentContainer.frame = NSRect(
            x: 0,
            y: 0,
            width: max(bounds.width, LayoutSeed.initialDocumentWidth),
            height: max(bounds.height, LayoutSeed.initialDocumentHeight)
        )
        scrollView.documentView = contentContainer
        addSubview(scrollView)
        contentContainer.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: topContentInset),
            contentStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor, constant: -18)
        ])
    }

    override func layout() {
        super.layout()
        scheduleDocumentFrameUpdate()
    }

    private func primeInitialDocumentFrame() {
        let seededWidth = max(bounds.width, LayoutSeed.initialDocumentWidth)
        let seededHeight = max(
            contentStack.fittingSize.height + topContentInset + 18,
            LayoutSeed.initialDocumentHeight
        )
        contentContainer.frame = NSRect(x: 0, y: 0, width: seededWidth, height: seededHeight)
    }

    func updateDocumentFrame() {
        let viewportSize = scrollView.contentSize
        guard viewportSize.width > 0 else { return }

        let fittingHeight = contentStack.fittingSize.height + topContentInset + 18
        let targetHeight = max(viewportSize.height, fittingHeight)
        let targetFrame = NSRect(x: 0, y: 0, width: viewportSize.width, height: targetHeight)

        if contentContainer.frame.integral != targetFrame.integral {
            contentContainer.frame = targetFrame
        }
    }

    private func observeScrollToTopRequests() {
        scrollToTopObserver = NotificationCenter.default.addObserver(
            forName: .appKitRequestScrollToTopForCurrentSelection,
            object: nil,
            queue: .main
        ) { _ in
            // 设置页改为固定高度后，不再处理滚动复位。
        }
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
        sceneHDRDisplaySwitch.target = self
        sceneHDRDisplaySwitch.action = #selector(handleSceneHDRDisplayChange)
        sceneMediaSourcePopup.target = self
        sceneMediaSourcePopup.action = #selector(handleSceneMediaSourceChange)
        sceneMediaAuthorizationButton.target = self
        sceneMediaAuthorizationButton.action = #selector(handleSceneMediaAuthorization)
        systemAudioSpectrumSwitch.target = self
        systemAudioSpectrumSwitch.action = #selector(handleSystemAudioSpectrumToggle)
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
        systemHotkeysSwitch.target = self
        systemHotkeysSwitch.action = #selector(handleSystemHotkeysToggle)

        for action in SystemHotkeyAction.allCases {
            hotkeyEnableSwitches[action]?.target = self
            hotkeyEnableSwitches[action]?.action = #selector(handleHotkeyEnableToggle(_:))
            hotkeyEnableSwitches[action]?.tag = hotkeyTag(for: action)

            hotkeyPopups[action]?.target = self
            hotkeyPopups[action]?.action = #selector(handleHotkeyPopupChange(_:))
            hotkeyPopups[action]?.tag = hotkeyTag(for: action)
        }

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
        sceneMaxFPSSegmented.target = self
        sceneMaxFPSSegmented.action = #selector(handleSceneMaxFPSChange)

        multiDisplaySwitch.target = self
        multiDisplaySwitch.action = #selector(handleMultiDisplayToggle)
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
        let verb = operation == "unregister" ? "取消注册" : "注册"
        var message = "开机自动启动\(verb)未生效，开关已恢复为系统实际状态。"
        if let failureDetail, !failureDetail.isEmpty {
            message += "\n原因：\(failureDetail)"
        }
        let alert = makeAppAlert(
            title: "开机自启设置失败",
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
        PlaybackCommandMultiplexer.shared.dispatch(.setMuted(clampedVolume == 0))
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
        // 以 1x 为中点，步长 0.05，限制在 0.25x 到 2.0x。
        let snapped = (playbackRateSlider.doubleValue * 20).rounded() / 20
        let clamped = max(0.25, min(2.0, snapped))
        playbackRateValueLabel.stringValue = String(format: "%.2gx", clamped)
        // 投影经 manager 的 sink 差分（playbackRate 组）单点下发。
        dependency.settings.playbackRate = clamped
    }

    @objc private func handlePlaybackRateSwitchToggle() {
        guard !isUpdatingUI else { return }
        let enabled = playbackRateSwitch.state == .on
        dependency.settings.playbackRateEnabled = enabled
        playbackRateSlider.isHidden = !enabled
        playbackRateValueLabel.isHidden = !enabled
        // 关闭时把速率重置为正常速度，避免关掉开关后引擎还在以异常速率播放。
        if !enabled {
            dependency.settings.playbackRate = 1.0
        }
    }

    @objc private func handleSceneHDRDisplayChange() {
        SceneHDRDisplayPreference.setEnabled(sceneHDRDisplaySwitch.state == .on)
    }

    @objc private func handleSceneMediaSourceChange() {
        guard !isUpdatingUI else { return }
        let source: SceneMediaSourcePreference = switch sceneMediaSourcePopup.selectedTag() {
        case 1: .appleMusic
        case 2: .systemNowPlaying
        default: .disabled
        }
        SceneMediaSourcePreference.set(source)
        sceneMediaAuthorizationButton.isEnabled = source == .appleMusic
    }

    @objc private func handleSceneMediaAuthorization() {
        guard SceneMediaSourcePreference.current == .appleMusic else { return }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            .first(where: { !$0.isTerminated })?.processIdentifier else {
            showSceneMediaNotice("请先打开 Apple Music，再点击授权读取。")
            return
        }
        sceneMediaAuthorizationButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SceneMusicPlayerSource.requestAuthorization(pid: pid)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sceneMediaAuthorizationButton.isEnabled = SceneMediaSourcePreference.current == .appleMusic
                SceneMediaSourcePreference.notifyChange()
                switch result {
                case .authorized: break
                case .denied, .consentRequired:
                    self.showSceneMediaNotice("未获读取许可。可在系统设置的「隐私与安全性 → 自动化」中允许 MyWallpaperX 访问音乐。")
                case .unavailable:
                    self.showSceneMediaNotice("暂时无法读取播放器，请确认 Apple Music 正在运行后重试。")
                }
            }
        }
    }

    private func showSceneMediaNotice(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "歌曲信息读取"
        alert.informativeText = message
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
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

    @objc private func handleSystemAudioSpectrumStyleChange() {
        guard !isUpdatingUI else { return }
        guard let style = systemAudioSpectrumStylePopup.selectedItem?.representedObject as? SystemAudioSpectrumStyle else { return }
        dependency.settings.systemAudioSpectrumStyle = style
    }

    @objc private func handleSystemAudioSpectrumSensitivityChange() {
        guard !isUpdatingUI else { return }
        guard let sensitivity = systemAudioSpectrumSensitivityPopup.selectedItem?.representedObject as? SystemAudioSpectrumSensitivity else { return }
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

    @objc private func handleSystemHotkeysToggle() {
        guard !isUpdatingUI else { return }
        dependency.settings.systemHotkeysEnabled = (systemHotkeysSwitch.state == .on)
    }

    private func selectSystemAudioSpectrumStyle(_ style: SystemAudioSpectrumStyle) {
        if let item = systemAudioSpectrumStylePopup.itemArray.first(where: { ($0.representedObject as? SystemAudioSpectrumStyle) == style }) {
            systemAudioSpectrumStylePopup.select(item)
        }
    }

    private func selectSystemAudioSpectrumSensitivity(_ sensitivity: SystemAudioSpectrumSensitivity) {
        if let item = systemAudioSpectrumSensitivityPopup.itemArray.first(where: { ($0.representedObject as? SystemAudioSpectrumSensitivity) == sensitivity }) {
            systemAudioSpectrumSensitivityPopup.select(item)
        }
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

    @objc private func handleSceneMaxFPSChange() {
        guard !isUpdatingUI else { return }
        let profile = PlaybackPerformanceProfile(
            rawValue: sceneMaxFPSSegmented.selectedSegment == 0 ? 30 : 60
        ) ?? .standard
        PlaybackPerformanceProfile.save(profile)
        // 经命令层下发（M0.7）：引擎端热切换帧节奏与预算，不重启壁纸。
        PlaybackCommandMultiplexer.shared.dispatch(
            .setPerformanceProfile(maxFPS: profile.maxFPS)
        )
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

    @objc private func handleClearCache() {
        let hostWindow = preferredHostWindow()
        let alert = makeAppAlert(
            title: "清空缓存",
            message: "将删除视频库和图片库的所有缩略图与视频静帧缓存，并清空在线图库的缩略图缓存，同时重置 Steam 创意工坊的列表/详情缓存与当前浏览状态；不会删除已导入的视频、图片和已下载的工坊文件，也不会清除当前设置。",
            buttons: ["清空", "取消"]
        )
        presentAppAlert(alert, in: hostWindow) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.dependency.actions.clearAllCaches()
            let result = makeAppAlert(
                title: "缓存已清空",
                message: "下次浏览视频库、图片库、在线图库或 Steam 创意工坊时会重新生成缓存。"
            )
            presentAppAlert(result, in: hostWindow)
        }
    }

    @objc func handleExportProfile() {
        let panel = NSSavePanel()
        panel.title = "导出个人设置"
        panel.nameFieldStringValue = "MyWallpaperX-Profile.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.isExtensionHidden = false

        presentSavePanel(panel) { [weak self] targetURL in
            guard let self, let targetURL else { return }
            do {
                let summary = try self.dependency.actions.exportPersonalSettings(targetURL)
                let done = makeAppAlert(
                    title: "导出完成",
                    message: "已导出 \(summary.wallpaperCount) 条壁纸配置，\(summary.tagCount) 个标签。"
                )
                presentAppAlert(done, in: self.preferredHostWindow())
            } catch {
                let failed = makeAppAlert(
                    title: "导出失败",
                    message: error.localizedDescription
                )
                presentAppAlert(failed, in: self.preferredHostWindow())
            }
        }
    }

    @objc func handleImportProfile() {
        let panel = NSOpenPanel()
        panel.title = "导入个人设置"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        presentOpenPanel(panel) { [weak self] sourceURL in
            guard let self, let sourceURL else { return }
            let hostWindow = self.preferredHostWindow()
            let confirm = makeAppAlert(
                title: "导入个人设置",
                message: "将恢复设置项、标签和收藏信息；同路径项目会覆盖为导入配置，缺失文件会保留并提示检查路径。",
                buttons: ["导入", "取消"]
            )
            presentAppAlert(confirm, in: hostWindow) { [weak self] confirmResponse in
                guard let self, confirmResponse == .alertFirstButtonReturn else { return }
                do {
                    let summary = try self.dependency.actions.importPersonalSettings(sourceURL)
                    let done = makeAppAlert(
                        title: "导入完成",
                        message: """
                        更新项目：\(summary.mergedWallpaperCount) 个
                        新增项目：\(summary.createdWallpaperCount) 个
                        标签总数：\(summary.tagCount) 个
                        缺失路径：\(summary.missingPathCount) 个
                        """
                    )
                    presentAppAlert(done, in: hostWindow)
                } catch {
                    let failed = makeAppAlert(
                        title: "导入失败",
                        message: error.localizedDescription
                    )
                    presentAppAlert(failed, in: hostWindow)
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
            title: "重置设置",
            message: "将清空视频库和图片库的所有壁纸、标签和最近使用，并恢复所有设置为初次安装状态。此操作不可撤销，确定要继续吗？",
            buttons: ["确定", "取消"]
        )
        presentAppAlert(alert, in: hostWindow) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
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
        // 间隔输入框只在结束编辑时写回，避免每个按键都触发计时器重建。
        guard !isUpdatingUI else { return }
        guard let textField = notification.object as? NSTextField, textField == intervalField else { return }
        let parsed = Int(textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? dependency.settings.randomInterval
        dependency.settings.randomInterval = max(1, parsed)
        dependency.actions.refreshAutoSwitchTimerIfNeeded()
    }
}
