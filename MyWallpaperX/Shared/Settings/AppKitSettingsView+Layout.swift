import AppKit

extension AppKitSettingsContainerView {
    func setupSections() {
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

    func applyVisibleSections() {
        playbackModesSection.isHidden = !visibleSections.contains(.playbackModes)
        audioSection.isHidden = !visibleSections.contains(.audio)
        systemSection.isHidden = !visibleSections.contains(.system)
        hotkeysSection.isHidden = !visibleSections.contains(.hotkeys)
        efficiencySection.isHidden = !visibleSections.contains(.efficiency)
        displaySection.isHidden = !visibleSections.contains(.display)

        let showsMaintenance = visibleSections.contains(.maintenance)
        maintenanceSection.isHidden = !showsMaintenance
    }

    func refreshSectionChromeAndLayout() {
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

    func scheduleDocumentFrameUpdate() {
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

    func applyNativeControlSizes() {
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

}
