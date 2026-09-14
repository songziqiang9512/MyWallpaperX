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

    private final class FlippedDocumentView: NSView {
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

    private let wallpaperManager: WallpaperManager
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingUI = false
    private var isDocumentFrameUpdateScheduled = false
    private var scrollToTopObserver: NSObjectProtocol?
    private var visibleSections: Set<AppSettingsSection>
    private let topContentInset: CGFloat
    private let scrollView = NSScrollView()
    private let contentContainer = FlippedDocumentView()

    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let playbackModesSection = SettingsGroupView(title: "播放模式")
    private let audioSection = SettingsGroupView(title: "音频与速率")
    private let systemSection = SettingsGroupView(title: "系统行为")
    private let hotkeysSection = SettingsGroupView(title: "快捷键")
    private let efficiencySection = SettingsGroupView(title: "节能与暂停")
    private let displaySection = SettingsGroupView(title: "显示设置")
    private let maintenanceSection = SettingsGroupView(title: nil)

    private let loopSwitch = NSSwitch()
    private let randomSwitch = NSSwitch()
    private let sequentialSwitch = NSSwitch()
    private let autoSwitchSwitch = NSSwitch()
    private let intervalField = NSTextField()
    private let timeUnitPopup = NSPopUpButton()
    private var intervalRowView: NSView?
    private var autoSwitchRowView: NSView?
    private let volumeSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let volumeValueLabel = NSTextField(labelWithString: "50%")
    private let muteSwitch = NSSwitch()

    private let playbackRateSlider = NSSlider(value: 1.0, minValue: 0.0, maxValue: 2.0, target: nil, action: nil)
    private let playbackRateValueLabel = NSTextField(labelWithString: "1.0x")
    private let playbackRateSwitch = NSSwitch()
    private var playbackRateRowView: NSView?

    private let startOnBootSwitch = NSSwitch()
    private let syncSystemWallpaperSwitch = NSSwitch()
    private let systemAudioSpectrumSwitch = NSSwitch()
    private let systemAudioSpectrumStylePopup = NSPopUpButton()
    private let systemAudioSpectrumSensitivityPopup = NSPopUpButton()
    private let systemAudioSpectrumBarCountPopup = NSPopUpButton()
    private let systemAudioSpectrumColorWell = NSColorWell()
    private let systemAudioSpectrumOffsetXSlider = NSSlider(value: 0, minValue: -30, maxValue: 30, target: nil, action: nil)
    private let systemAudioSpectrumOffsetYSlider = NSSlider(value: 0, minValue: -20, maxValue: 20, target: nil, action: nil)
    private let systemAudioSpectrumOffsetXValueLabel = NSTextField(labelWithString: "0%")
    private let systemAudioSpectrumOffsetYValueLabel = NSTextField(labelWithString: "0%")
    private let systemAudioSpectrumPeakCapsSwitch = NSSwitch()
    private var systemAudioSpectrumOptionsContainer: NSView?
    private let systemHotkeysSwitch = NSSwitch()
    private let hotkeyRowsStack = NSStackView()
    private var hotkeyRowsContainer: NSView?
    private var systemAudioSpectrumRowView: NSView?
    private var hotkeyEnableSwitches: [SystemHotkeyAction: NSSwitch] = [:]
    private var hotkeyPopups: [SystemHotkeyAction: NSPopUpButton] = [:]

    private let pauseOtherAppFocusedSwitch = NSSwitch()
    private let pauseOtherAppFullscreenSwitch = NSSwitch()
    private let pauseWhenUnpluggedSwitch = NSSwitch()
    private let pauseWhenIdleSwitch = NSSwitch()
    private let idleTimeoutPopup = NSPopUpButton()
    private var idleTimeoutRowView: NSView?

    /// Scene 引擎性能预算档（60=standard 全量，30=efficient 减频减容量）。
    private let sceneMaxFPSSegmented = NSSegmentedControl(
        labels: ["30 FPS", "60 FPS"], trackingMode: .selectOne, target: nil,
        action: nil
    )

    private let multiDisplaySwitch = NSSwitch()
    private let fillModeFitButton = NSButton(radioButtonWithTitle: VideoFillMode.aspectFit.rawValue, target: nil, action: nil)
    private let fillModeFillButton = NSButton(radioButtonWithTitle: VideoFillMode.aspectFill.rawValue, target: nil, action: nil)

    private let clearCacheButton = NSButton(title: "清除缓存", target: nil, action: nil)
    private let resetSettingsButton = NSButton(title: "重置默认", target: nil, action: nil)
    private let exportProfileButton = NSButton(title: "导出设置", target: nil, action: nil)
    private let importProfileButton = NSButton(title: "导入设置", target: nil, action: nil)

    init(
        wallpaperManager: WallpaperManager,
        visibleSections: Set<AppSettingsSection>,
        topContentInset: CGFloat
    ) {
        self.wallpaperManager = wallpaperManager
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

        let settings = wallpaperManager.settings

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

    private func updateDocumentFrame() {
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

    private func setupSections() {
        // 分组顺序固定：播放、系统、节能、显示、维护；由左侧导航决定当前显示哪些块。
        setupPlaybackSection()
        setupSystemSection()
        setupEfficiencySection()
        setupDisplaySection()
        setupMaintenanceSection()

        addSection(playbackModesSection)
        addSection(audioSection)
        addSection(systemSection)
        addSection(hotkeysSection)
        addSection(efficiencySection)
        addSection(displaySection)
        addSection(maintenanceSection)
    }

    private func applyVisibleSections() {
        playbackModesSection.isHidden = !visibleSections.contains(.playbackModes)
        audioSection.isHidden = !visibleSections.contains(.audio)
        systemSection.isHidden = !visibleSections.contains(.system)
        hotkeysSection.isHidden = !visibleSections.contains(.hotkeys)
        efficiencySection.isHidden = !visibleSections.contains(.efficiency)
        displaySection.isHidden = !visibleSections.contains(.display)

        let showsMaintenance = visibleSections.contains(.maintenance)
        maintenanceSection.isHidden = !showsMaintenance
    }

    private func refreshSectionChromeAndLayout() {
        let sections = [
            playbackModesSection,
            audioSection,
            systemSection,
            hotkeysSection,
            efficiencySection,
            displaySection,
            maintenanceSection
        ]
        sections.forEach { $0.refreshSeparators() }

        needsLayout = true
        contentContainer.needsLayout = true
        contentStack.needsLayout = true
        scheduleDocumentFrameUpdate()
    }

    private func scheduleDocumentFrameUpdate() {
        guard !isDocumentFrameUpdateScheduled else { return }
        isDocumentFrameUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isDocumentFrameUpdateScheduled = false
            self.updateDocumentFrame()
        }
    }

    private func addSection(_ section: NSView) {
        contentStack.addArrangedSubview(section)
        section.translatesAutoresizingMaskIntoConstraints = false
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func setupPlaybackSection() {
        // 播放控制区只放与播放状态相关的可逆配置，避免和系统集成配置混在一起。
        playbackModesSection.addRow(makeSettingRow(title: "循环播放", iconSystemName: "repeat", trailing: loopSwitch))
        playbackModesSection.addRow(makeSettingRow(title: "顺序播放", iconSystemName: "list.number", trailing: sequentialSwitch))
        playbackModesSection.addRow(makeSettingRow(title: "随机播放", iconSystemName: "shuffle", trailing: randomSwitch))
        let autoSwitchRow = makeSettingRow(title: "自动切换", iconSystemName: "arrow.triangle.2.circlepath", trailing: autoSwitchSwitch)
        autoSwitchRowView = autoSwitchRow
        playbackModesSection.addRow(autoSwitchRow)

        intervalField.alignment = .right
        intervalField.translatesAutoresizingMaskIntoConstraints = false
        intervalField.delegate = self
        intervalField.widthAnchor.constraint(equalToConstant: 46).isActive = true

        timeUnitPopup.translatesAutoresizingMaskIntoConstraints = false
        for unit in TimeUnit.allCases {
            timeUnitPopup.addItem(withTitle: unit.rawValue)
            timeUnitPopup.lastItem?.representedObject = unit
        }

        let intervalControls = NSStackView(views: [intervalField, timeUnitPopup])
        intervalControls.orientation = .horizontal
        intervalControls.alignment = .centerY
        intervalControls.spacing = 8

        intervalRowView = makeSettingRow(title: "-  间隔时间", iconSystemName: "timer", trailing: intervalControls)
        if let intervalRowView {
            playbackModesSection.addRow(intervalRowView)
        }

        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        volumeValueLabel.alignment = .right
        volumeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        volumeValueLabel.translatesAutoresizingMaskIntoConstraints = false
        volumeValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let volumeControls = NSStackView(views: [volumeValueLabel, volumeSlider, muteSwitch])
        volumeControls.orientation = .horizontal
        volumeControls.alignment = .centerY
        volumeControls.spacing = 8
        audioSection.addRow(makeSettingRow(title: "静音", iconSystemName: "speaker.slash", trailing: volumeControls))

        // 播放速率行：开关控制滑块显隐，1x 保持在滑杆中点。
        playbackRateSwitch.toolTip = "启用后可调整播放速率"
        playbackRateSlider.translatesAutoresizingMaskIntoConstraints = false
        playbackRateSlider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        playbackRateSlider.numberOfTickMarks = 0
        playbackRateSlider.allowsTickMarkValuesOnly = false
        playbackRateValueLabel.alignment = .right
        playbackRateValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        playbackRateValueLabel.translatesAutoresizingMaskIntoConstraints = false
        playbackRateValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let rateControls = NSStackView(views: [playbackRateValueLabel, playbackRateSlider, playbackRateSwitch])
        rateControls.orientation = .horizontal
        rateControls.alignment = .centerY
        rateControls.spacing = 8
        let rateRow = makeSettingRow(title: "播放速率", iconSystemName: "speedometer", trailing: rateControls)
        playbackRateRowView = rateRow
        audioSection.addRow(rateRow)
    }

    private func setupSystemSection() {
        // 系统集成区只放会影响全局快捷键、同步壁纸和开机行为的配置。
        startOnBootSwitch.toolTip = "开机时自动启动应用并恢复上次的壁纸设置"
        syncSystemWallpaperSwitch.toolTip = "每次切换壁纸时同步更新系统壁纸"
        systemAudioSpectrumSwitch.toolTip = "实验功能：采集系统音频并在桌面底部显示频谱条"
        systemHotkeysSwitch.toolTip = "允许使用全局 F1-F12 快捷键控制壁纸"

        systemSection.addRow(makeSettingRow(title: "开机自启动", iconSystemName: "power", trailing: startOnBootSwitch))
        systemSection.addRow(makeSettingRow(title: "同步系统壁纸", iconSystemName: "photo.on.rectangle", trailing: syncSystemWallpaperSwitch))
        let systemAudioSpectrumRow = makeSettingRow(
            title: "系统音频频谱",
            iconSystemName: "chart.bar.xaxis",
            subtitle: "实验功能：会增加GPU负载",
            trailing: systemAudioSpectrumSwitch
        )
        systemAudioSpectrumRow.identifier = NSUserInterfaceItemIdentifier("settings.row.system-audio-spectrum")
        systemAudioSpectrumRowView = systemAudioSpectrumRow
        systemSection.addRow(systemAudioSpectrumRow)
        for style in SystemAudioSpectrumStyle.allCases {
            systemAudioSpectrumStylePopup.addItem(withTitle: style.displayName)
            systemAudioSpectrumStylePopup.lastItem?.representedObject = style
        }
        for sensitivity in SystemAudioSpectrumSensitivity.allCases {
            systemAudioSpectrumSensitivityPopup.addItem(withTitle: sensitivity.displayName)
            systemAudioSpectrumSensitivityPopup.lastItem?.representedObject = sensitivity
        }
        for barCount in [16, 20, 28, 36, 48] {
            systemAudioSpectrumBarCountPopup.addItem(withTitle: "\(barCount) 根")
            systemAudioSpectrumBarCountPopup.lastItem?.representedObject = barCount
        }
        systemAudioSpectrumColorWell.supportsAlpha = false
        systemAudioSpectrumColorWell.color = .white
        systemAudioSpectrumOffsetXSlider.translatesAutoresizingMaskIntoConstraints = false
        systemAudioSpectrumOffsetXSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        systemAudioSpectrumOffsetYSlider.translatesAutoresizingMaskIntoConstraints = false
        systemAudioSpectrumOffsetYSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        for label in [systemAudioSpectrumOffsetXValueLabel, systemAudioSpectrumOffsetYValueLabel] {
            label.alignment = .right
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let spectrumStyleRow = makeSettingRow(
            title: "-  动态风格",
            iconSystemName: "waveform.path.ecg",
            trailing: systemAudioSpectrumStylePopup
        )
        let spectrumSensitivityRow = makeSettingRow(
            title: "-  灵敏度",
            iconSystemName: "slider.horizontal.3",
            trailing: systemAudioSpectrumSensitivityPopup
        )
        let spectrumBarCountRow = makeSettingRow(
            title: "-  频柱数量",
            iconSystemName: "square.split.2x1",
            trailing: systemAudioSpectrumBarCountPopup
        )
        let spectrumColorRow = makeSettingRow(
            title: "-  颜色",
            iconSystemName: "paintpalette",
            trailing: systemAudioSpectrumColorWell
        )
        let offsetXControls = NSStackView(views: [systemAudioSpectrumOffsetXValueLabel, systemAudioSpectrumOffsetXSlider])
        offsetXControls.orientation = .horizontal
        offsetXControls.alignment = .centerY
        offsetXControls.spacing = 8
        let offsetYControls = NSStackView(views: [systemAudioSpectrumOffsetYValueLabel, systemAudioSpectrumOffsetYSlider])
        offsetYControls.orientation = .horizontal
        offsetYControls.alignment = .centerY
        offsetYControls.spacing = 8
        let spectrumOffsetXRow = makeSettingRow(
            title: "-  X 位置",
            iconSystemName: "arrow.left.and.right",
            trailing: offsetXControls
        )
        let spectrumOffsetYRow = makeSettingRow(
            title: "-  Y 位置",
            iconSystemName: "arrow.up.and.down",
            trailing: offsetYControls
        )
        let spectrumPeakCapsRow = makeSettingRow(
            title: "-  显示峰值帽",
            iconSystemName: "rectangle.topthird.inset.filled",
            trailing: systemAudioSpectrumPeakCapsSwitch
        )
        let spectrumOptionsStack = NSStackView(views: [
            spectrumStyleRow,
            makeInlineSeparator(horizontalInset: 14),
            spectrumSensitivityRow,
            makeInlineSeparator(horizontalInset: 14),
            spectrumBarCountRow,
            makeInlineSeparator(horizontalInset: 14),
            spectrumColorRow,
            makeInlineSeparator(horizontalInset: 14),
            spectrumOffsetXRow,
            makeInlineSeparator(horizontalInset: 14),
            spectrumOffsetYRow,
            makeInlineSeparator(horizontalInset: 14),
            spectrumPeakCapsRow
        ])
        spectrumOptionsStack.orientation = .vertical
        spectrumOptionsStack.alignment = .leading
        spectrumOptionsStack.distribution = .fill
        spectrumOptionsStack.spacing = 0
        spectrumOptionsStack.translatesAutoresizingMaskIntoConstraints = false
        systemAudioSpectrumOptionsContainer = makeEmbeddedRow(content: spectrumOptionsStack)
        if let systemAudioSpectrumOptionsContainer {
            systemAudioSpectrumOptionsContainer.identifier = NSUserInterfaceItemIdentifier("settings.row.system-audio-spectrum.options")
            spectrumOptionsStack.identifier = NSUserInterfaceItemIdentifier("settings.stack.system-audio-spectrum.options")
            systemSection.addRow(systemAudioSpectrumOptionsContainer)
        }
        hotkeysSection.addRow(makeSettingRow(title: "响应系统快捷键", iconSystemName: "keyboard", trailing: systemHotkeysSwitch))

        hotkeyRowsStack.orientation = .vertical
        hotkeyRowsStack.alignment = .leading
        hotkeyRowsStack.distribution = .fill
        hotkeyRowsStack.spacing = 0
        hotkeyRowsStack.translatesAutoresizingMaskIntoConstraints = false

        for action in SystemHotkeyAction.allCases {
            let toggle = NSSwitch()
            let popup = NSPopUpButton()

            let controls = NSStackView(views: [popup, toggle])
            controls.orientation = .horizontal
            controls.alignment = .centerY
            controls.spacing = 8

            if !hotkeyRowsStack.arrangedSubviews.isEmpty {
                let separator = makeInlineSeparator(horizontalInset: 14)
                hotkeyRowsStack.addArrangedSubview(separator)
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.widthAnchor.constraint(equalTo: hotkeyRowsStack.widthAnchor).isActive = true
            }

            let row = makeSettingRow(title: action.displayName, iconSystemName: "command", trailing: controls)
            hotkeyRowsStack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: hotkeyRowsStack.widthAnchor).isActive = true

            hotkeyEnableSwitches[action] = toggle
            hotkeyPopups[action] = popup
        }

        hotkeyRowsContainer = makeEmbeddedRow(content: hotkeyRowsStack)
        if let hotkeyRowsContainer {
            hotkeysSection.addRow(hotkeyRowsContainer)
        }
    }

    private func setupEfficiencySection() {
        // 性能区的开关会直接影响引擎暂停状态，改动后必须同步到 WallpaperEngine。
        pauseOtherAppFullscreenSwitch.toolTip = "当其他应用进入全屏并占据主要桌面空间时暂停壁纸播放"
        pauseWhenUnpluggedSwitch.toolTip = "使用电池时暂停壁纸播放以节省电量"
        pauseWhenIdleSwitch.toolTip = "当电脑长时间不活跃时暂停壁纸播放"

        efficiencySection.addRow(makeSettingRow(title: "其他应用焦点时暂停", iconSystemName: "app.badge", trailing: pauseOtherAppFocusedSwitch))
        efficiencySection.addRow(makeSettingRow(title: "其他应用全屏时暂停", iconSystemName: "arrow.up.left.and.arrow.down.right", trailing: pauseOtherAppFullscreenSwitch))
        efficiencySection.addRow(makeSettingRow(title: "未连接电源时暂停播放", iconSystemName: "battery.25", trailing: pauseWhenUnpluggedSwitch))
        efficiencySection.addRow(makeSettingRow(title: "电脑不活跃时暂停播放", iconSystemName: "moon.zzz", trailing: pauseWhenIdleSwitch))
        efficiencySection.addRow(makeSettingRow(title: "最高帧率（Scene 引擎）", iconSystemName: "gauge.with.needle", subtitle: "60 全量预算；30 节能预算", trailing: sceneMaxFPSSegmented))

        for value in [5, 10, 15, 20, 30, 60] {
            idleTimeoutPopup.addItem(withTitle: "\(value)分钟")
            idleTimeoutPopup.lastItem?.representedObject = value
        }
        idleTimeoutRowView = makeSettingRow(title: "-  不活跃时间", iconSystemName: "clock", trailing: idleTimeoutPopup)
        if let idleTimeoutRowView {
            efficiencySection.addRow(idleTimeoutRowView)
        }
    }

    private func setupDisplaySection() {
        // 显示区只处理屏幕适配和画面比例，不混入播放策略。
        multiDisplaySwitch.toolTip = "在所有显示器上显示视频壁纸"
        displaySection.addRow(makeSettingRow(title: "多屏适配", iconSystemName: "rectangle.on.rectangle", trailing: multiDisplaySwitch))

        let fillModeControls = NSStackView(views: [fillModeFitButton, fillModeFillButton])
        fillModeControls.orientation = .horizontal
        fillModeControls.alignment = .centerY
        fillModeControls.spacing = 16
        displaySection.addRow(makeSettingRow(title: "视频填充模式", iconSystemName: "aspectratio", trailing: fillModeControls))
    }

    private func setupMaintenanceSection() {
        // 维护区只承载导入导出、清缓存和恢复默认这类高风险动作，和普通设置分开。
        configureMaintenanceActionButton(exportProfileButton)
        exportProfileButton.target = self
        exportProfileButton.action = #selector(handleExportProfile)

        configureMaintenanceActionButton(importProfileButton)
        importProfileButton.target = self
        importProfileButton.action = #selector(handleImportProfile)

        configureMaintenanceActionButton(clearCacheButton)
        configureMaintenanceActionButton(resetSettingsButton, tint: .systemRed)

        maintenanceSection.addRow(makeMaintenanceActionRow(button: exportProfileButton, iconSystemName: "square.and.arrow.up"))
        maintenanceSection.addRow(makeMaintenanceActionRow(button: importProfileButton, iconSystemName: "square.and.arrow.down"))
        maintenanceSection.addRow(makeMaintenanceActionRow(button: clearCacheButton, iconSystemName: "trash"))
        maintenanceSection.addRow(makeMaintenanceActionRow(button: resetSettingsButton, iconSystemName: "arrow.counterclockwise"))
    }

    private func applyNativeControlSizes() {
        // 控件尺寸统一收口，避免每个控件自己定义大小导致页面观感失衡。
        let switches: [NSSwitch] = [
            loopSwitch,
            randomSwitch,
            sequentialSwitch,
            autoSwitchSwitch,
            muteSwitch,
            playbackRateSwitch,
            startOnBootSwitch,
            syncSystemWallpaperSwitch,
            systemAudioSpectrumSwitch,
            systemHotkeysSwitch,
            pauseOtherAppFocusedSwitch,
            pauseOtherAppFullscreenSwitch,
            pauseWhenUnpluggedSwitch,
            pauseWhenIdleSwitch,
            multiDisplaySwitch
        ]
        switches.forEach { $0.controlSize = .mini }
        hotkeyEnableSwitches.values.forEach { $0.controlSize = .mini }

        let popups: [NSPopUpButton] = [timeUnitPopup, idleTimeoutPopup] + hotkeyPopups.values
            + [systemAudioSpectrumStylePopup, systemAudioSpectrumSensitivityPopup, systemAudioSpectrumBarCountPopup]
        popups.forEach { $0.controlSize = .small }

        intervalField.controlSize = .small
        volumeSlider.controlSize = .small
        playbackRateSlider.controlSize = .small
        exportProfileButton.controlSize = .regular
        importProfileButton.controlSize = .regular
        clearCacheButton.controlSize = .regular
        resetSettingsButton.controlSize = .regular
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
        wallpaperManager.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFromState()
            }
            .store(in: &cancellables)
    }

    private func makeSettingRow(title: String, iconSystemName: String? = nil, subtitle: String? = nil, trailing: NSView, leadingInset: CGFloat = 0) -> NSView {
        // 标题在左、控件在右，中间留伸缩空白，保持系统设置类页面的稳定对齐。
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let textContentView: NSView
        if let subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            let textStack = NSStackView(views: [titleLabel, subtitleLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.distribution = .gravityAreas
            textStack.spacing = 2
            textContentView = textStack
        } else {
            textContentView = titleLabel
        }

        let leadingView = makeLeadingRowContent(iconSystemName: iconSystemName, content: textContentView)

        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rowStack = NSStackView(views: [leadingView, spacer, trailing])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.distribution = .fill
        rowStack.spacing = 6
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.identifier = NSUserInterfaceItemIdentifier("settings.row.\(sanitizedIdentifierComponent(from: title))")
        container.addSubview(rowStack)
        let topInset: CGFloat = 9
        let bottomInset: CGFloat = 9
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14 + leadingInset),
            rowStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            rowStack.topAnchor.constraint(equalTo: container.topAnchor, constant: topInset),
            rowStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottomInset)
        ])
        return container
    }

    private func configureMaintenanceActionButton(_ button: NSButton, tint: NSColor? = nil) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = tint
        button.image = nil
        button.font = .systemFont(ofSize: 13, weight: .regular)
        button.alignment = .left
        button.setButtonType(.momentaryPushIn)
        let foregroundColor = tint ?? .labelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: foregroundColor
        ]
        button.attributedTitle = NSAttributedString(string: button.title, attributes: attributes)
        button.contentTintColor = nil
    }

    private func makeMaintenanceActionRow(button: NSButton, iconSystemName: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = makeRowIconView(systemName: iconSystemName, tintColor: button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor ?? .secondaryLabelColor)
        button.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            button.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    private func makeLeadingRowContent(iconSystemName: String?, content: NSView) -> NSView {
        guard let iconSystemName else { return content }

        let iconView = makeRowIconView(systemName: iconSystemName, tintColor: .secondaryLabelColor)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.identifier = NSUserInterfaceItemIdentifier("settings.leading.\(iconSystemName)")
        iconView.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)
        container.addSubview(content)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            iconView.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    private func makeRowIconView(systemName: String, tintColor: NSColor) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.identifier = NSUserInterfaceItemIdentifier("settings.icon.\(systemName)")

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        if let image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) {
            image.isTemplate = true
            imageView.image = image
        }
        imageView.contentTintColor = tintColor
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 14),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
            imageView.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            imageView.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])

        return container
    }

    private func sanitizedIdentifierComponent(from title: String) -> String {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-  ", with: "")
            .replacingOccurrences(of: " ", with: "-")
        return normalized.isEmpty ? "untitled" : normalized
    }

    private func makeEmbeddedRow(content: NSView, centered: Bool = false) -> NSView {
        // 嵌入式行只包裹二级控件，不再重复加装饰容器，避免视觉层级失真。
        let row: NSStackView
        if centered {
            row = NSStackView(views: [NSView(), content, NSView()])
        } else {
            row = NSStackView(views: [content])
            content.translatesAutoresizingMaskIntoConstraints = false
            content.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        }

        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        return row
    }

    private func makeCenteredControlRow(content: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private func makeMaintenanceControlRow(content: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private func makeInlineSeparator(horizontalInset: CGFloat) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }

    @objc private func handleLoopToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.setLoopPlaybackEnabled(loopSwitch.state == .on)
    }

    @objc private func handleRandomToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.setRandomPlaybackEnabled(randomSwitch.state == .on)
    }

    @objc private func handleSequentialToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.setSequentialPlaybackEnabled(sequentialSwitch.state == .on)
    }

    @objc private func handleAutoSwitchToggle() {
        guard !isUpdatingUI else { return }
        let enabled = autoSwitchSwitch.state == .on
        wallpaperManager.settings.autoSwitchEnabled = enabled
        if enabled {
            // 开启：从 0 重建 timer，通知引擎当前视频切换为循环模式（等 timer 到期再切换）。
            wallpaperManager.startAutoSwitchTimer()
            WallpaperEngine.shared.setLoopCurrentItem(true)
        } else {
            // 关闭：销毁 timer，通知引擎停止循环当前视频，视频播完后自然切下一张。
            wallpaperManager.stopAutoSwitchTimer()
            WallpaperEngine.shared.setLoopCurrentItem(false)
        }
    }

    @objc private func handleTimeUnitChange() {
        guard !isUpdatingUI else { return }
        guard let unit = timeUnitPopup.selectedItem?.representedObject as? TimeUnit else { return }
        wallpaperManager.settings.timeUnit = unit
        wallpaperManager.refreshAutoSwitchTimerIfNeeded()
    }

    @objc private func handleVolumeChange() {
        guard !isUpdatingUI else { return }
        let clampedVolume = Int(max(0, min(100, round(volumeSlider.doubleValue))))
        volumeValueLabel.stringValue = "\(clampedVolume)%"
        wallpaperManager.updateVolume(Double(clampedVolume))
        // M0.2 闭环：音量滑杆跨越 0 边界时同步公共静音意图
        // （0 → 公共静音；>0 且公共静音 → 解除），Scene/Video 双端跟随。
        PlaybackMuteState.shared.setMuted(clampedVolume == 0)
        PlaybackCommandMultiplexer.shared.dispatch(
            .setMuted(clampedVolume == 0)
        )
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
        wallpaperManager.settings.playbackRate = clamped
        wallpaperManager.applyPlaybackRateToEngine()
    }

    @objc private func handlePlaybackRateSwitchToggle() {
        guard !isUpdatingUI else { return }
        let enabled = playbackRateSwitch.state == .on
        wallpaperManager.settings.playbackRateEnabled = enabled
        playbackRateSlider.isHidden = !enabled
        playbackRateValueLabel.isHidden = !enabled
        // 关闭时把速率重置为正常速度，避免关掉开关后引擎还在以异常速率播放。
        if !enabled {
            wallpaperManager.settings.playbackRate = 1.0
        }
    }

    @objc private func handleStartOnBootToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.startOnBoot = (startOnBootSwitch.state == .on)
        wallpaperManager.updateLoginItemStatus()
    }

    @objc private func handleSyncSystemWallpaperToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.setSyncSystemWallpaperEnabled(syncSystemWallpaperSwitch.state == .on)
    }

    @objc private func handleSystemAudioSpectrumToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.systemAudioSpectrumEnabled = (systemAudioSpectrumSwitch.state == .on)
        wallpaperManager.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumStyleChange() {
        guard !isUpdatingUI else { return }
        guard let style = systemAudioSpectrumStylePopup.selectedItem?.representedObject as? SystemAudioSpectrumStyle else { return }
        wallpaperManager.settings.systemAudioSpectrumStyle = style
        wallpaperManager.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumSensitivityChange() {
        guard !isUpdatingUI else { return }
        guard let sensitivity = systemAudioSpectrumSensitivityPopup.selectedItem?.representedObject as? SystemAudioSpectrumSensitivity else { return }
        wallpaperManager.settings.systemAudioSpectrumSensitivity = sensitivity
        wallpaperManager.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumBarCountChange() {
        guard !isUpdatingUI else { return }
        guard let barCount = systemAudioSpectrumBarCountPopup.selectedItem?.representedObject as? Int else { return }
        wallpaperManager.settings.systemAudioSpectrumBarCount = barCount
        wallpaperManager.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumColorChange() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.systemAudioSpectrumColorHex = hexString(from: systemAudioSpectrumColorWell.color)
        wallpaperManager.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumOffsetChange() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.systemAudioSpectrumOffsetX = systemAudioSpectrumOffsetXSlider.doubleValue / 100
        wallpaperManager.settings.systemAudioSpectrumOffsetY = systemAudioSpectrumOffsetYSlider.doubleValue / 100
        systemAudioSpectrumOffsetXValueLabel.stringValue = "\(Int(round(systemAudioSpectrumOffsetXSlider.doubleValue)))%"
        systemAudioSpectrumOffsetYValueLabel.stringValue = "\(Int(round(systemAudioSpectrumOffsetYSlider.doubleValue)))%"
        wallpaperManager.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemAudioSpectrumPeakCapsToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.systemAudioSpectrumPeakCapsEnabled = (systemAudioSpectrumPeakCapsSwitch.state == .on)
        wallpaperManager.applySystemAudioSpectrumToEngine()
    }

    @objc private func handleSystemHotkeysToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.systemHotkeysEnabled = (systemHotkeysSwitch.state == .on)
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

    private func color(fromHex hex: String) -> NSColor? {
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
        wallpaperManager.settings.pauseWhenOtherAppFocused = (pauseOtherAppFocusedSwitch.state == .on)
        wallpaperManager.settings.pauseWhenOtherAppFullscreen = (pauseOtherAppFullscreenSwitch.state == .on)
        wallpaperManager.settings.pauseWhenUnplugged = (pauseWhenUnpluggedSwitch.state == .on)
        wallpaperManager.settings.pauseWhenIdle = (pauseWhenIdleSwitch.state == .on)
        wallpaperManager.applyEngineSettings()
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
        wallpaperManager.settings.idleTimeoutMinutes = value
        wallpaperManager.applyEngineSettings()
    }

    @objc private func handleMultiDisplayToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.multiDisplayEnabled = (multiDisplaySwitch.state == .on)
        wallpaperManager.applyEngineSettings(reloadWallpaper: true)
    }

    @objc private func handleFillModeChange(_ sender: NSButton) {
        guard !isUpdatingUI else { return }
        let mode: VideoFillMode = (sender == fillModeFitButton) ? .aspectFit : .aspectFill
        selectFillMode(mode)
        wallpaperManager.settings.videoFillMode = mode
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
            self.wallpaperManager.clearAllCaches()
            SteamWorkshopService.shared.clearAllCachedState()
            let result = makeAppAlert(
                title: "缓存已清空",
                message: "下次浏览视频库、图片库或 Steam 创意工坊时会重新生成缓存。"
            )
            presentAppAlert(result, in: hostWindow)
        }
    }

    @objc private func handleExportProfile() {
        let panel = NSSavePanel()
        panel.title = "导出个人设置"
        panel.nameFieldStringValue = "MyWallpaperX-Profile.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.isExtensionHidden = false

        presentSavePanel(panel) { [weak self] targetURL in
            guard let self, let targetURL else { return }
            do {
                let summary = try self.wallpaperManager.exportPersonalSettings(to: targetURL)
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

    @objc private func handleImportProfile() {
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
                    let summary = try self.wallpaperManager.importPersonalSettings(from: sourceURL)
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
            self.wallpaperManager.resetToFreshInstallState()
        }
    }

    private func assignedShortcut(for action: SystemHotkeyAction) -> FunctionKeyShortcut {
        // 快捷键状态源只读写 settings，popup 不直接保存自己的状态。
        switch action {
        case .previous:
            return wallpaperManager.settings.previousWallpaperHotkey
        case .next:
            return wallpaperManager.settings.nextWallpaperHotkey
        case .playPause:
            return wallpaperManager.settings.togglePlaybackHotkey
        case .muteToggle:
            return wallpaperManager.settings.toggleMuteHotkey
        }
    }

    private func setAssignedShortcut(_ shortcut: FunctionKeyShortcut, for action: SystemHotkeyAction) {
        // 统一通过 settings 写回，避免每个热键 row 各自维护一份绑定结果。
        switch action {
        case .previous:
            wallpaperManager.settings.previousWallpaperHotkey = shortcut
        case .next:
            wallpaperManager.settings.nextWallpaperHotkey = shortcut
        case .playPause:
            wallpaperManager.settings.togglePlaybackHotkey = shortcut
        case .muteToggle:
            wallpaperManager.settings.toggleMuteHotkey = shortcut
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
        let masterEnabled = wallpaperManager.settings.systemHotkeysEnabled
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
        let parsed = Int(textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? wallpaperManager.settings.randomInterval
        wallpaperManager.settings.randomInterval = max(1, parsed)
        wallpaperManager.refreshAutoSwitchTimerIfNeeded()
    }
}
