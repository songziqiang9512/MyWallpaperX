import AppKit

extension AppKitSettingsContainerView {
    @objc func openScreenSaverSettings() { dependency.actions.openScreenSaverSettings() }

    func setupSections() {
        // 分组顺序固定：播放、系统、节能、显示、维护；由左侧导航决定当前显示哪些块。
        setupPlaybackSection()
        setupSystemSection()
        setupEfficiencySection()
        setupQualitySection()
        setupDisplaySection()
        setupMaintenanceSection()

        addSection(playbackModesSection)
        addSection(audioSection)
        addSection(systemSection)
        addSection(hotkeysSection)
        addSection(efficiencySection)
        addSection(qualitySection)
        addSection(displaySection)
        addSection(maintenanceSection)
    }

    func applyVisibleSections() {
        playbackModesSection.isHidden = !visibleSections.contains(.playbackModes)
        audioSection.isHidden = !visibleSections.contains(.audio)
        systemSection.isHidden = !visibleSections.contains(.system)
        hotkeysSection.isHidden = !visibleSections.contains(.hotkeys)
        efficiencySection.isHidden = !visibleSections.contains(.efficiency)
        qualitySection.isHidden = !visibleSections.contains(.quality)
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
            qualitySection,
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
        playbackModesSection.addRow(makeSettingRow(title: String(localized: "Loop"), iconSystemName: "repeat", trailing: loopSwitch))
        playbackModesSection.addRow(makeSettingRow(title: String(localized: "Play in Order"), iconSystemName: "list.number", trailing: sequentialSwitch))
        playbackModesSection.addRow(makeSettingRow(title: String(localized: "Shuffle"), iconSystemName: "shuffle", trailing: randomSwitch))
        let autoSwitchRow = makeSettingRow(title: String(localized: "Auto Switch"), iconSystemName: "arrow.triangle.2.circlepath", trailing: autoSwitchSwitch)
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

        intervalRowView = makeSettingRow(title: String(localized: "-  Interval"), iconSystemName: "timer", trailing: intervalControls)
        if let intervalRowView {
            playbackModesSection.addRow(intervalRowView)
        }

        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.widthAnchor.constraint(equalToConstant: 230).isActive = true
        volumeValueLabel.alignment = .right
        volumeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        volumeValueLabel.translatesAutoresizingMaskIntoConstraints = false
        volumeValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let volumeControls = NSStackView(views: [volumeValueLabel, volumeSlider, muteSwitch])
        volumeControls.orientation = .horizontal
        volumeControls.alignment = .centerY
        volumeControls.spacing = 8
        audioSection.addRow(makeSettingRow(title: String(localized: "Volume / Mute"), iconSystemName: "speaker.slash", trailing: volumeControls))

        // 播放速率行：开关控制滑块显隐，滑杆覆盖 0.25x 到 2x。
        playbackRateSwitch.toolTip = String(localized: "Enable to adjust playback speed")
        playbackRateSlider.translatesAutoresizingMaskIntoConstraints = false
        playbackRateSlider.widthAnchor.constraint(equalToConstant: 230).isActive = true
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
        let rateRow = makeSettingRow(title: String(localized: "Playback Speed"), iconSystemName: "speedometer", trailing: rateControls)
        audioSection.addRow(rateRow)
    }

    private func setupSystemSection() {
        // 系统集成区只放会影响全局快捷键、同步壁纸和开机行为的配置。
        startOnBootSwitch.toolTip = String(localized: "Launch the app at login")
        restorePlaybackOnLaunchSwitch.toolTip = String(localized: "Restore the last wallpaper (Video, Web or Scene) at launch. When off, no wallpaper plays at launch. Static image wallpapers are kept by the system and are not affected.")
        syncSystemWallpaperSwitch.toolTip = String(localized: "Also update the system wallpaper when the wallpaper changes: a still frame for Video, and one frame captured after the launch transition for Web and Scene. Static image wallpapers are always applied directly.")
        systemAudioSpectrumSwitch.toolTip = String(localized: "Capture system audio and show a spectrum bar at the bottom of the desktop")
        systemHotkeysSwitch.toolTip = String(localized: "Allow global F1–F12 shortcuts to control the wallpaper")

        sceneMediaInfoSwitch.toolTip = String(localized: "Shows the current track and artwork on Scene wallpapers. macOS asks for permission the first time Apple Music is read. If you denied it, allow it in System Settings > Privacy & Security > Automation and turn this on again.")
        systemSection.addRow(makeSettingRow(title: String(localized: "Wallpaper Song Info"), iconSystemName: "music.note",
            subtitle: String(localized: "Show the current track and artwork on supported Scene and Web wallpapers"), trailing: sceneMediaInfoSwitch))

        systemSection.addRow(makeSettingRow(title: String(localized: "Launch at Login"), iconSystemName: "power", trailing: startOnBootSwitch))
        systemSection.addRow(makeSettingRow(title: String(localized: "Resume Playback at Launch"), iconSystemName: "arrow.counterclockwise.circle", trailing: restorePlaybackOnLaunchSwitch))
        systemSection.addRow(makeSettingRow(title: String(localized: "Sync System Wallpaper"), iconSystemName: "photo.on.rectangle", trailing: syncSystemWallpaperSwitch))
        let systemAudioSpectrumRow = makeSettingRow(
            title: String(localized: "Audio Spectrum"),
            iconSystemName: "chart.bar.xaxis",
            subtitle: String(localized: "A visual effect that applies only to Video wallpapers"),
            trailing: systemAudioSpectrumSwitch
        )
        systemAudioSpectrumRow.identifier = NSUserInterfaceItemIdentifier("settings.row.system-audio-spectrum")
        systemSection.addRow(systemAudioSpectrumRow)
        for barCount in [16, 20, 28, 36, 48] {
            systemAudioSpectrumBarCountPopup.addItem(withTitle: String(localized: "\(barCount) bars"))
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

        let spectrumBarCountRow = makeSettingRow(
            title: String(localized: "-  Bar Count"),
            iconSystemName: "square.split.2x1",
            trailing: systemAudioSpectrumBarCountPopup
        )
        let spectrumColorRow = makeSettingRow(
            title: String(localized: "-  Color"),
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
            title: String(localized: "-  X Position"),
            iconSystemName: "arrow.left.and.right",
            trailing: offsetXControls
        )
        let spectrumOffsetYRow = makeSettingRow(
            title: String(localized: "-  Y Position"),
            iconSystemName: "arrow.up.and.down",
            trailing: offsetYControls
        )
        let spectrumPeakCapsRow = makeSettingRow(
            title: String(localized: "-  Show Peak Caps"),
            iconSystemName: "rectangle.topthird.inset.filled",
            trailing: systemAudioSpectrumPeakCapsSwitch
        )
        let spectrumOptionsStack = NSStackView(views: [
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
        // 与 hotkeyRowsStack 同构：子行和内嵌分隔线显式 pin 宽到栈宽，
        // 否则右缘控件不与主行对齐、分隔线塌缩成短划。
        for child in spectrumOptionsStack.arrangedSubviews {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: spectrumOptionsStack.widthAnchor).isActive = true
        }
        systemAudioSpectrumOptionsContainer = makeEmbeddedRow(content: spectrumOptionsStack)
        if let systemAudioSpectrumOptionsContainer {
            systemAudioSpectrumOptionsContainer.identifier = NSUserInterfaceItemIdentifier("settings.row.system-audio-spectrum.options")
            spectrumOptionsStack.identifier = NSUserInterfaceItemIdentifier("settings.stack.system-audio-spectrum.options")
            systemSection.addRow(systemAudioSpectrumOptionsContainer)
        }
        hotkeysSection.addRow(makeSettingRow(title: String(localized: "Playback Shortcuts"), iconSystemName: "keyboard", trailing: systemHotkeysSwitch))

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
        pauseOtherAppFocusedSwitch.toolTip = String(localized: "Pause the wallpaper while another app is in front (excluding Finder on the desktop and this app)")
        pauseOtherAppFullscreenSwitch.toolTip = String(localized: "Pause the wallpaper when another app enters full screen and covers the main desktop")
        pauseWhenUnpluggedSwitch.toolTip = String(localized: "Pause the wallpaper on battery to save power")
        pauseWhenIdleSwitch.toolTip = String(localized: "Pause the wallpaper when the Mac has been idle for a while")

        efficiencySection.addRow(makeSettingRow(title: String(localized: "Pause When Another App Is Focused"), iconSystemName: "app.badge", trailing: pauseOtherAppFocusedSwitch))
        efficiencySection.addRow(makeSettingRow(title: String(localized: "Pause When Another App Is Full Screen"), iconSystemName: "arrow.up.left.and.arrow.down.right", trailing: pauseOtherAppFullscreenSwitch))
        efficiencySection.addRow(makeSettingRow(title: String(localized: "Pause When on Battery"), iconSystemName: "battery.25", trailing: pauseWhenUnpluggedSwitch))
        efficiencySection.addRow(makeSettingRow(title: String(localized: "Pause When Idle"), iconSystemName: "moon.zzz", trailing: pauseWhenIdleSwitch))

        for value in [5, 10, 15, 20, 30, 60] {
            idleTimeoutPopup.addItem(withTitle: String(localized: "\(value) min"))
            idleTimeoutPopup.lastItem?.representedObject = value
        }
        idleTimeoutRowView = makeSettingRow(title: String(localized: "-  Idle Time"), iconSystemName: "clock", trailing: idleTimeoutPopup)
        if let idleTimeoutRowView {
            efficiencySection.addRow(idleTimeoutRowView)
        }
    }

    private func setupDisplaySection() {
        // 显示区处理窗口外观、屏幕适配和画面比例，不混入播放策略。
        for (index, style) in LibraryBackgroundStyle.allCases.enumerated() {
            libraryBackgroundPopup.addItem(withTitle: style.title)
            libraryBackgroundPopup.lastItem?.tag = index
            libraryBackgroundPopup.lastItem?.representedObject = style
        }
        displaySection.addRow(makeSettingRow(title: String(localized: "App Theme"), iconSystemName: "rectangle.on.rectangle",
            trailing: libraryBackgroundPopup))
        for (index, action) in LibraryCardClickAction.allCases.enumerated() {
            libraryCardClickPopup.addItem(withTitle: action.title)
            libraryCardClickPopup.lastItem?.tag = index
            libraryCardClickPopup.lastItem?.representedObject = action
        }
        displaySection.addRow(makeSettingRow(title: String(localized: "Card Click Action"), iconSystemName: "cursorarrow.click",
            trailing: libraryCardClickPopup))
        let screenSaverButton = NSButton(title: String(localized: "Configure"), target: self, action: #selector(openScreenSaverSettings))
        screenSaverButton.bezelStyle = .rounded
        displaySection.addRow(makeSettingRow(title: String(localized: "Lock Screen & Screen Saver"), iconSystemName: "display",
            subtitle: String(localized: "Play local videos muted on loop as the system screen saver"), trailing: screenSaverButton))
        multiDisplaySwitch.toolTip = String(localized: "Show the wallpaper on all displays (Video, Web and Scene)")
        displaySection.addRow(makeSettingRow(title: String(localized: "Multiple Displays"), iconSystemName: "rectangle.on.rectangle", trailing: multiDisplaySwitch))

        let fillModeControls = NSStackView(views: [fillModeFitButton, fillModeFillButton])
        fillModeControls.orientation = .horizontal
        fillModeControls.alignment = .centerY
        fillModeControls.spacing = 16
        displaySection.addRow(makeSettingRow(title: String(localized: "Video Fill Mode"), iconSystemName: "aspectratio", trailing: fillModeControls))
    }

    private func setupMaintenanceSection() {
        // 维护区只承载导入导出、清缓存和重置应用这类高风险动作，和普通设置分开。
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

    private func setupQualitySection() {
        qualitySection.addRow(makeSettingRow(
            title: String(localized: "Animation Frame Rate"), iconSystemName: "gauge.with.needle",
            subtitle: String(localized: "Sets the frame rate cap for Scene wallpapers"), trailing: sceneMaxFPSSegmented))
        qualitySection.addRow(makeSettingRow(title: String(localized: "Scene HDR"), iconSystemName: "sun.max",
            subtitle: String(localized: "Requires wallpaper support; very high power draw, enable with care"), trailing: sceneHDRDisplaySwitch))
        webFrameRatePopup.addItems(withTitles: [
            String(localized: "Match Display (up to 60 FPS)"),
            String(localized: "Follow Animation Frame Rate"),
        ])
        qualitySection.addRow(makeSettingRow(
            title: String(localized: "Web Frame Rate Suggestion"), iconSystemName: "globe",
            subtitle: String(localized: "Applies when the Web wallpaper uses the suggested frame rate"), trailing: webFrameRatePopup))
        qualitySection.addRow(makeSettingRow(
            title: String(localized: "Video Quality"), iconSystemName: "film",
            trailing: NSTextField(labelWithString: String(localized: "Original Video"))))
        configureMaintenanceActionButton(resetQualityButton)
        qualitySection.addRow(makeMaintenanceActionRow(button: resetQualityButton, iconSystemName: "arrow.counterclockwise"))
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
            restorePlaybackOnLaunchSwitch,
            syncSystemWallpaperSwitch,
            sceneHDRDisplaySwitch,
            sceneMediaInfoSwitch,
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

        let popups: [NSPopUpButton] = [timeUnitPopup, idleTimeoutPopup, libraryBackgroundPopup, libraryCardClickPopup, webFrameRatePopup] + hotkeyPopups.values
            + [systemAudioSpectrumBarCountPopup]
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
        titleLabel.toolTip = title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let textContentView: NSView
        if let subtitle {
            let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.maximumNumberOfLines = 3
            subtitleLabel.toolTip = subtitle
            let textStack = NSStackView(views: [titleLabel, subtitleLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.distribution = .gravityAreas
            textStack.spacing = 2
            textStack.widthAnchor.constraint(lessThanOrEqualToConstant: 430).isActive = true
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
