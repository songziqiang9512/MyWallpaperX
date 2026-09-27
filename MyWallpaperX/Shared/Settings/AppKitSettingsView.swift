//
//  AppKitSettingsView.swift
//  MyWallpaperX
//

import AppKit
import Combine
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

    private let dependency: AppSettingsPanelDependency
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingUI = false
    var isDocumentFrameUpdateScheduled = false
    private var scrollToTopObserver: NSObjectProtocol?
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
    let syncSystemWallpaperSwitch = NSSwitch()
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
    }

    func refreshFromState() {
        // 这是设置页的单一回填入口：所有控件状态都从 manager 快照回填，避免局部控件自己保留旧态。
        isUpdatingUI = true
        defer { isUpdatingUI = false }

        let settings = dependency.settings

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
        volumeSlider.doubleValue = Double(clampedVolume)
        volumeValueLabel.stringValue = "\(clampedVolume)%"
        muteSwitch.state = PlaybackMuteState.shared.isMuted ? .on : .off

        let clampedRate = max(0.25, min(2.0, settings.playbackRate))
        playbackRateSwitch.state = settings.playbackRateEnabled ? .on : .off
        playbackRateSlider.doubleValue = clampedRate
        playbackRateValueLabel.stringValue = String(format: "%.2gx", clampedRate)
        // 开关关闭时隐藏滑块和数值标签，只保留开关本身。
        playbackRateSlider.isHidden = !settings.playbackRateEnabled
        playbackRateValueLabel.isHidden = !settings.playbackRateEnabled

        startOnBootSwitch.state = settings.startOnBoot ? .on : .off
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

        refreshHotkeyRows()
        applyVisibleSections()
        refreshSectionChromeAndLayout()
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
        syncSystemWallpaperSwitch.target = self
        syncSystemWallpaperSwitch.action = #selector(handleSyncSystemWallpaperToggle)
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
        if enabled {
            // 开启：从 0 重建 timer，通知引擎当前视频切换为循环模式（等 timer 到期再切换）。
            dependency.actions.startAutoSwitchTimer()
            WallpaperEngine.shared.setLoopCurrentItem(true)
        } else {
            // 关闭：销毁 timer，通知引擎停止循环当前视频，视频播完后自然切下一张。
            dependency.actions.stopAutoSwitchTimer()
            WallpaperEngine.shared.setLoopCurrentItem(false)
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
        dependency.settings.playbackRate = clamped
        dependency.actions.applyPlaybackRateToEngine()
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

    @objc private func handleStartOnBootToggle() {
        guard !isUpdatingUI else { return }
        dependency.settings.startOnBoot = (startOnBootSwitch.state == .on)
        dependency.actions.updateLoginItemStatus()
    }

    @objc private func handleSyncSystemWallpaperToggle() {
        guard !isUpdatingUI else { return }
        dependency.actions.setSyncSystemWallpaperEnabled(syncSystemWallpaperSwitch.state == .on)
    }

    @objc private func handleSystemAudioSpectrumToggle() {
        guard !isUpdatingUI else { return }
        dependency.settings.systemAudioSpectrumEnabled = (systemAudioSpectrumSwitch.state == .on)
        dependency.actions.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumStyleChange() {
        guard !isUpdatingUI else { return }
        guard let style = systemAudioSpectrumStylePopup.selectedItem?.representedObject as? SystemAudioSpectrumStyle else { return }
        dependency.settings.systemAudioSpectrumStyle = style
        dependency.actions.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumSensitivityChange() {
        guard !isUpdatingUI else { return }
        guard let sensitivity = systemAudioSpectrumSensitivityPopup.selectedItem?.representedObject as? SystemAudioSpectrumSensitivity else { return }
        dependency.settings.systemAudioSpectrumSensitivity = sensitivity
        dependency.actions.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumBarCountChange() {
        guard !isUpdatingUI else { return }
        guard let barCount = systemAudioSpectrumBarCountPopup.selectedItem?.representedObject as? Int else { return }
        dependency.settings.systemAudioSpectrumBarCount = barCount
        dependency.actions.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumColorChange() {
        guard !isUpdatingUI else { return }
        dependency.settings.systemAudioSpectrumColorHex = hexString(from: systemAudioSpectrumColorWell.color)
        dependency.actions.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumOffsetChange() {
        guard !isUpdatingUI else { return }
        dependency.settings.systemAudioSpectrumOffsetX = systemAudioSpectrumOffsetXSlider.doubleValue / 100
        dependency.settings.systemAudioSpectrumOffsetY = systemAudioSpectrumOffsetYSlider.doubleValue / 100
        systemAudioSpectrumOffsetXValueLabel.stringValue = "\(Int(round(systemAudioSpectrumOffsetXSlider.doubleValue)))%"
        systemAudioSpectrumOffsetYValueLabel.stringValue = "\(Int(round(systemAudioSpectrumOffsetYSlider.doubleValue)))%"
        dependency.actions.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumPeakCapsToggle() {
        guard !isUpdatingUI else { return }
        dependency.settings.systemAudioSpectrumPeakCapsEnabled = (systemAudioSpectrumPeakCapsSwitch.state == .on)
        dependency.actions.applySystemAudioSpectrumToEngine()
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

    @objc private func handleHotkeyEnableToggle(_ sender: NSSwitch) {
        guard !isUpdatingUI else { return }
        guard let action = hotkeyAction(from: sender.tag) else { return }

        if sender.state == .on {
            if assignedShortcut(for: action) == .none {
                let available = firstAvailableShortcut(for: action)
                if available != .none {
                    setAssignedShortcut(available, for: action)
                }
            }
        } else {
            setAssignedShortcut(.none, for: action)
        }
        refreshFromState()
    }

    @objc private func handleHotkeyPopupChange(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        guard let action = hotkeyAction(from: sender.tag) else { return }
        guard let shortcut = sender.selectedItem?.representedObject as? FunctionKeyShortcut else { return }
        if isShortcutAvailable(shortcut, for: action) {
            setAssignedShortcut(shortcut, for: action)
        }
        refreshFromState()
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
        dependency.settings.videoFillMode = mode
        // 填充模式只需通知引擎更新 gravity + 播放动画，不重建播放链路。
        WallpaperEngine.shared.setFillMode(mode.ipcValue)
    }

    @objc private func handleClearCache() {
        let hostWindow = preferredHostWindow()
        let alert = makeAppAlert(
            title: "清空缓存",
            message: "将删除视频库的所有缩略图和静帧缓存，并重置 Steam 创意工坊的列表/详情缓存与当前浏览状态；不会删除已导入的视频、图片和已下载的工坊文件，也不会清除当前设置。",
            buttons: ["清空", "取消"]
        )
        presentAppAlert(alert, in: hostWindow) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.dependency.actions.clearAllCaches()
            let result = makeAppAlert(
                title: "缓存已清空",
                message: "下次浏览视频库、图片库或 Steam 创意工坊时会重新生成缓存。"
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

    private func assignedShortcut(for action: SystemHotkeyAction) -> FunctionKeyShortcut {
        // 快捷键状态源只读写 settings，popup 不直接保存自己的状态。
        switch action {
        case .previous:
            return dependency.settings.previousWallpaperHotkey
        case .next:
            return dependency.settings.nextWallpaperHotkey
        case .playPause:
            return dependency.settings.togglePlaybackHotkey
        case .muteToggle:
            return dependency.settings.toggleMuteHotkey
        }
    }

    private func setAssignedShortcut(_ shortcut: FunctionKeyShortcut, for action: SystemHotkeyAction) {
        // 统一通过 settings 写回，避免每个热键 row 各自维护一份绑定结果。
        switch action {
        case .previous:
            dependency.settings.previousWallpaperHotkey = shortcut
        case .next:
            dependency.settings.nextWallpaperHotkey = shortcut
        case .playPause:
            dependency.settings.togglePlaybackHotkey = shortcut
        case .muteToggle:
            dependency.settings.toggleMuteHotkey = shortcut
        }
    }

    private func usedShortcuts(excluding action: SystemHotkeyAction) -> Set<FunctionKeyShortcut> {
        Set(
            SystemHotkeyAction.allCases
                .filter { $0 != action }
                .map { assignedShortcut(for: $0) }
                .filter { $0 != .none }
        )
    }

    private func isShortcutAvailable(_ shortcut: FunctionKeyShortcut, for action: SystemHotkeyAction) -> Bool {
        shortcut == .none || shortcut == assignedShortcut(for: action) || !usedShortcuts(excluding: action).contains(shortcut)
    }

    private func firstAvailableShortcut(for action: SystemHotkeyAction) -> FunctionKeyShortcut {
        FunctionKeyShortcut.allCases.first(where: { $0 != .none && isShortcutAvailable($0, for: action) }) ?? .none
    }

    private func refreshHotkeyRows() {
        // 热键行刷新时同时处理启用开关和下拉可用性，保持“一个动作一行”一致。
        let masterEnabled = dependency.settings.systemHotkeysEnabled
        for action in SystemHotkeyAction.allCases {
            guard let toggle = hotkeyEnableSwitches[action],
                  let popup = hotkeyPopups[action] else {
                continue
            }
            let shortcut = assignedShortcut(for: action)
            let enabled = shortcut != .none
            toggle.state = enabled ? .on : .off
            popup.isEnabled = masterEnabled && enabled
            reloadHotkeyPopup(popup, for: action, selected: shortcut)
        }
    }

    private func reloadHotkeyPopup(_ popup: NSPopUpButton, for action: SystemHotkeyAction, selected: FunctionKeyShortcut) {
        // 这里要重新构建整份菜单，因为禁用项和当前选项会随其它快捷键变化而变化。
        popup.removeAllItems()
        for shortcut in FunctionKeyShortcut.allCases {
            popup.addItem(withTitle: shortcut.displayName)
            popup.lastItem?.representedObject = shortcut
            popup.lastItem?.isEnabled = isShortcutAvailable(shortcut, for: action)
        }
        if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? FunctionKeyShortcut) == selected }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
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

    private func hotkeyTag(for action: SystemHotkeyAction) -> Int {
        switch action {
        case .previous: return 1
        case .next: return 2
        case .playPause: return 3
        case .muteToggle: return 4
        }
    }

    private func hotkeyAction(from tag: Int) -> SystemHotkeyAction? {
        switch tag {
        case 1: return .previous
        case 2: return .next
        case 3: return .playPause
        case 4: return .muteToggle
        default: return nil
        }
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
