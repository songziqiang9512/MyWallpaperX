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
        let rateInput = NSStackView(views: [sceneFPSField, sceneFPSControl])
        rateInput.spacing = 8
        let sceneFPSControls = NSStackView(views: [rateInput, sceneFPSEffectiveLabel])
        sceneFPSControls.orientation = .vertical
        sceneFPSControls.alignment = .trailing
        sceneQualityPresetPopup.autoenablesItems = false
        sceneQualityPresetPopup.addItem(withTitle: String(localized: "Custom"))
        sceneQualityPresetPopup.lastItem?.isEnabled = false
        for preset in SceneQualityPreset.allCases {
            let title = switch preset {
            case .low: String(localized: "Low")
            case .medium: String(localized: "Medium")
            case .high: String(localized: "High")
            case .ultra: String(localized: "Ultra")
            }
            sceneQualityPresetPopup.addItem(withTitle: title)
            sceneQualityPresetPopup.lastItem?.representedObject = preset.rawValue
        }
        sceneQualityPresetPopup.setAccessibilityLabel(String(localized: "Scene Quality Preset"))
        qualitySection.addRow(makeSettingRow(title: String(localized: "Scene Quality Preset"),
            iconSystemName: "slider.horizontal.3", trailing: sceneQualityPresetPopup))

        sceneFPSControls.spacing = 2
        sceneFPSField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sceneFPSField.alignment = .right
        sceneFPSField.delegate = self
        sceneFPSField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        sceneFPSField.setAccessibilityLabel(String(localized: "Animation Frame Rate"))
        sceneFPSEffectiveLabel.font = .systemFont(ofSize: 11)
        sceneFPSEffectiveLabel.textColor = .secondaryLabelColor
        sceneFPSControl.isContinuous = true
        sceneFPSControl.target = self
        sceneFPSControl.action = #selector(handleSceneFrameRateSlider(_:))
        sceneFPSControl.widthAnchor.constraint(equalToConstant: 120).isActive = true
        sceneFPSControl.setAccessibilityLabel(String(localized: "Animation Frame Rate"))
        qualitySection.addRow(makeSettingRow(
            title: String(localized: "Animation Frame Rate"), iconSystemName: "gauge.with.needle",
            subtitle: String(localized: "Sets the frame rate cap for Scene wallpapers"), trailing: sceneFPSControls))
        for mode in SceneAntiAliasingMode.allCases {
            let title = switch mode {
            case .none: String(localized: "None")
            case .msaa2: String(localized: "MSAA ×2")
            case .msaa4: String(localized: "MSAA ×4")
            }
            sceneAntiAliasingPopup.addItem(withTitle: title)
            sceneAntiAliasingPopup.lastItem?.representedObject = mode.rawValue
        }
        sceneAntiAliasingPopup.setAccessibilityLabel(String(localized: "Scene Anti-Aliasing"))
        sceneRasterSamplesLabel.font = .systemFont(ofSize: 11)
        sceneRasterSamplesLabel.textColor = .secondaryLabelColor
        let antiAliasingControls = NSStackView(views: [sceneAntiAliasingPopup, sceneRasterSamplesLabel])
        antiAliasingControls.orientation = .vertical
        antiAliasingControls.alignment = .trailing
        antiAliasingControls.spacing = 2
        qualitySection.addRow(makeSettingRow(title: String(localized: "Scene Anti-Aliasing"),
            iconSystemName: "viewfinder",
            subtitle: String(localized: "Uses multisampling where the Scene supports it", table: "SceneQuality"), trailing: antiAliasingControls))

        let modes: [(ScenePostProcessingMode, String)] = [
            (.disabled, String(localized: "Disabled")),
            (.enabled, String(localized: "Enabled")),
            (.ultra, String(localized: "Ultra")),
            (.ultraDisplayHDR, String(localized: "Ultra (Display HDR)")),
        ]
        scenePostProcessingPopup.autoenablesItems = false
        for (mode, title) in modes {
            scenePostProcessingPopup.addItem(withTitle: title)
            scenePostProcessingPopup.lastItem?.representedObject = mode.rawValue
        }
        qualitySection.addRow(makeSettingRow(title: String(localized: "Scene Post-Processing"), iconSystemName: "sun.max",
            subtitle: String(localized: "Some effect changes require reloading the wallpaper"), trailing: scenePostProcessingPopup))
        for mode in SceneTextureQuality.allCases {
            let title = switch mode {
            case .automatic: String(localized: "Automatic")
            case .full: String(localized: "High Quality")
            case .performance: String(localized: "High Performance")
            }
            sceneTextureQualityPopup.addItem(withTitle: title)
            sceneTextureQualityPopup.lastItem?.representedObject = mode.rawValue
        }
        qualitySection.addRow(makeSettingRow(title: String(localized: "Texture Resolution"), iconSystemName: "square.stack.3d.up",
            subtitle: String(localized: "Some effect changes require reloading the wallpaper"), trailing: sceneTextureQualityPopup))
        let shadowTiers: [(SceneShadowQuality, String)] = [
            (.disabled, String(localized: "Disabled")),
            (.low, String(localized: "Low")),
            (.medium, String(localized: "Medium")),
            (.high, String(localized: "High")),
            (.adaptive, String(localized: "Ultra")),
        ]
        for (tier, title) in shadowTiers {
            sceneShadowsPopup.addItem(withTitle: title)
            sceneShadowsPopup.lastItem?.representedObject = tier.rawValue
        }
        sceneShadowsPopup.setAccessibilityLabel(String(localized: "Scene Shadows"))
        qualitySection.addRow(makeSettingRow(title: String(localized: "Scene Shadows"), iconSystemName: "shadow",
            subtitle: String(localized: "Some effect changes require reloading the wallpaper"),
            trailing: sceneShadowsPopup, readout: sceneShadowUseLabel))
        let volumeTiers: [(SceneVolumeLightingQuality, String)] = [
            (.disabled, String(localized: "Disabled")),
            (.enabled, String(localized: "High")),
            (.ultra, String(localized: "Ultra")),
        ]
        for (tier, title) in volumeTiers {
            sceneVolumeLightingPopup.addItem(withTitle: title)
            sceneVolumeLightingPopup.lastItem?.representedObject = tier.rawValue
        }
        qualitySection.addRow(makeSettingRow(title: String(localized: "Volumetric Lighting"), iconSystemName: "light.max",
            subtitle: String(localized: "Some effect changes require reloading the wallpaper"), trailing: sceneVolumeLightingPopup))
        qualitySection.addRow(makeSettingRow(title: String(localized: "Scene Reflections"), iconSystemName: "sparkle",
            subtitle: String(localized: "Some effect changes require reloading the wallpaper"), trailing: sceneReflectionsSwitch))
        configureMaintenanceActionButton(reapplySceneQualityButton)
        reapplySceneQualityButton.identifier = NSUserInterfaceItemIdentifier("settings.scene.reapply-quality")
        reapplySceneQualityButton.isEnabled = false
        reapplySceneQualityButton.target = self
        reapplySceneQualityButton.action = #selector(reapplySceneQuality)
        qualitySection.addRow(makeMaintenanceActionRow(button: reapplySceneQualityButton, iconSystemName: "arrow.clockwise"))
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
        let controls: [NSControl] = [sceneQualityPresetPopup, sceneAntiAliasingPopup, scenePostProcessingPopup, sceneTextureQualityPopup,
                                     sceneShadowsPopup, sceneVolumeLightingPopup, sceneReflectionsSwitch, webFrameRatePopup]
        for control in controls {
            control.target = self
            control.action = #selector(handleQualityChange(_:))
        }
        configureMaintenanceActionButton(resetQualityButton)
        resetQualityButton.target = self
        resetQualityButton.action = #selector(restoreDefaultQuality)
        qualitySection.addRow(makeMaintenanceActionRow(button: resetQualityButton, iconSystemName: "arrow.counterclockwise"))
    }

    func refreshQualityControls() {
        let quality = PlaybackQualityPreference.current
        refreshSceneQualityPreset(quality)
        if !sceneFPSControl.isTracking, sceneFPSField.currentEditor() == nil {
            let request = quality.animationFrameRate.rawValue
            sceneFPSControl.integerValue = request
            updateSceneFrameRateLabels(request)
        }
        webFrameRatePopup.selectItem(at: quality.webFrameRateMode == .display ? 0 : 1)
        sceneAntiAliasingPopup.selectItem(at: sceneAntiAliasingPopup.indexOfItem(withRepresentedObject: quality.scene.antiAliasing.rawValue))
        refreshSceneRenderReadouts(quality.scene)
        refreshScenePostProcessingMenu(quality.scene.postProcessing)
        sceneTextureQualityPopup.selectItem(at: sceneTextureQualityPopup.indexOfItem(withRepresentedObject: quality.scene.textures.rawValue))
        sceneShadowsPopup.selectItem(at: sceneShadowsPopup.indexOfItem(withRepresentedObject: quality.scene.shadows.rawValue))
        sceneVolumeLightingPopup.selectItem(at: sceneVolumeLightingPopup.indexOfItem(
            withRepresentedObject: quality.scene.volumeLighting.rawValue))
        sceneReflectionsSwitch.state = quality.scene.reflections == .enabled ? .on : .off
        refreshSceneQualityReapplyTitle(quality.scene)
    }

    private func refreshSceneQualityPreset(_ quality: PlaybackQualityPreference) {
        let index = SceneQualityPreset.matching(quality).map {
            sceneQualityPresetPopup.indexOfItem(withRepresentedObject: $0.rawValue)
        } ?? 0
        sceneQualityPresetPopup.selectItem(at: index)
    }

    func refreshSceneRenderReadouts(_ requested: SceneRenderQuality = PlaybackQualityPreference.current.scene) {
        let daemon = SceneDaemonClient.shared
        let displays = daemon.activeRasterDisplayStatuses
        let prepared = daemon.activePreparedRenderQuality
        let screens = displays.isEmpty ? [] : AppKit.NSScreen.screens
        let names = displays.map { sceneRenderReadoutDisplayName($0.displayID, screens: screens) }
        let waiting = String(localized: "Awaiting render result", table: "SceneQuality")
        refreshSceneRasterSampleReadout(displays, names: names, waiting: waiting,
            pending: prepared.map { $0.antiAliasing != requested.antiAliasing } ?? false)
        let details = displays.map { $0.shadow.map(shadowUseDescription) ?? waiting }
        let summary = Set(details).count > 1 ? String(localized: "Varies by display", table: "SceneQuality") : details.first ?? waiting
        let previous = prepared.map { $0.shadows != requested.shadows } == true && displays.contains { $0.shadow != nil }
        let title = previous ? sceneRenderReadoutTitle(summary, previous: true) : summary
        let hidden = displays.isEmpty && prepared == nil
        if hidden != sceneShadowUseLabel.isHidden || title != sceneShadowUseLabel.stringValue { scheduleDocumentFrameUpdate() }
        sceneShadowUseLabel.isHidden = hidden
        sceneShadowUseLabel.stringValue = title
        sceneShadowUseLabel.toolTip = displays.isEmpty ? nil : zip(names, details).map { name, detail in
            "\(name): \(detail)"
        }.joined(separator: "\n")
    }

    private func refreshSceneRasterSampleReadout(_ displays: [SceneRasterDisplayStatus], names: [String],
                                                waiting: String, pending: Bool) {
        sceneRasterSamplesLabel.isHidden = displays.isEmpty
        sceneRasterSamplesLabel.toolTip = nil
        guard !displays.isEmpty else { return }

        let counts = Set(displays.compactMap(\.samples)).sorted()
        let values = counts.map { "\($0.formatted())×" }
        let awaitingResult = displays.contains { $0.samples == nil }
        let summary = (values + (awaitingResult ? [waiting] : [])).joined(separator: " / ")
        sceneRasterSamplesLabel.stringValue = values.isEmpty ? waiting : sceneRenderReadoutTitle(summary, previous: pending)

        let details = zip(displays, names).map { display, name in
            let detail = display.samples.map { "\($0.formatted())×" } ?? waiting
            let reason: String? = switch display.fallback {
            case .deviceUnsupported: String(localized: "Device limit for requested MSAA", table: "SceneQuality")
            case .compatiblePathUnavailable: String(localized: "Single-sample render path", table: "SceneQuality")
            case .preparationFailed: String(localized: "MSAA preparation failed", table: "SceneQuality")
            case nil: nil
            }
            let value = [detail, reason].compactMap { $0 }.joined(separator: " – ")
            return (reason, "\(name): \(value)")
        }
        if !pending {
            if displays.count == 1, let reason = details[0].0 {
                sceneRasterSamplesLabel.stringValue += " – \(reason)"
            } else if details.contains(where: { $0.0 != nil }) {
                sceneRasterSamplesLabel.stringValue += " – " + String(localized: "Fallback on some displays", table: "SceneQuality")
            }
        }
        sceneRasterSamplesLabel.toolTip = details.map { $0.1 }.joined(separator: "\n")
    }

    private func sceneRenderReadoutTitle(_ summary: String, previous: Bool) -> String {
        previous ? String(localized: "Previous setting in use: \(summary)", table: "SceneQuality")
                 : String(localized: "In use: \(summary)", table: "SceneQuality")
    }

    private func sceneRenderReadoutDisplayName(_ id: UInt32, screens: [AppKit.NSScreen]) -> String {
        screens.first { ($0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.uint32Value == id }?
            .localizedName ?? String(localized: "Display \(id.formatted())", table: "SceneQuality")
    }

    private func shadowUseDescription(_ use: SceneShadowUse) -> String {
        switch use {
        case .disabled: return String(localized: "Disabled")
        case .noReceiver: return String(localized: "No applicable shadows", table: "SceneQuality")
        case .unavailable: return String(localized: "Shadow maps unavailable", table: "SceneQuality")
        case .active(let maps): return maps.map { map in
            let light = switch map.family {
            case .directional: String(localized: "Directional", table: "SceneQuality")
            case .point: String(localized: "Point (each face)", table: "SceneQuality")
            case .spot: String(localized: "Spotlight", table: "SceneQuality")
            }
            let size = map.face.map { "\($0.formatted()) × \($0.formatted())" }
            let reason: String? = switch map.limit {
            case .receiverExtent: String(localized: "Receiver target size limit", table: "SceneQuality")
            case .lightFamily: String(localized: "Light type limit", table: "SceneQuality")
            case .reduced: String(localized: "Reduced resolution", table: "SceneQuality")
            case nil: nil
            }
            let detail = size ?? String(localized: "Unavailable", table: "SceneQuality")
            return ["\(light): \(detail)", reason].compactMap { $0 }.joined(separator: " – ")
        }.joined(separator: " / ")
        }
    }

    private func updateSceneFrameRateLabels(_ requested: Int) {
        sceneFPSField.stringValue = String(requested)
        updateSceneFrameRateReadout(requested)
    }

    func refreshSceneFrameRateReadout() {
        guard !sceneFPSControl.isTracking else { return }
        updateSceneFrameRateReadout(PlaybackQualityPreference.current.animationFrameRate.rawValue)
    }

    private func updateSceneFrameRateReadout(_ requested: Int) {
        let daemon = SceneDaemonClient.shared
        let active = daemon.activeAnimationCadence
        let confirmed = active?.requestedFPS.rawValue == requested ? active?.effectiveFPS : nil
        let effective = confirmed ?? min(Double(requested), daemon.configuredAnimationCadenceLimit)
        sceneFPSEffectiveLabel.isHidden = effective == Double(requested)
        guard !sceneFPSEffectiveLabel.isHidden else { return }
        let fps = effective.formatted(.number.precision(.fractionLength(0...2)))
        sceneFPSEffectiveLabel.stringValue = confirmed != nil
            ? String(localized: "Current: \(fps) FPS")
            : String(localized: "Display limit: \(fps) FPS")
    }

    func commitSceneFrameRate(_ selection: AnimationFrameRate?) {
        var quality = PlaybackQualityPreference.current
        let request = selection ?? quality.animationFrameRate
        sceneFPSControl.integerValue = request.rawValue
        updateSceneFrameRateLabels(request.rawValue)
        guard request != quality.animationFrameRate else { return }
        quality.animationFrameRate = request
        PlaybackCommandMultiplexer.shared.applyQualityPreference(quality)
        refreshSceneQualityPreset(quality)
    }

    func refreshSceneQualityReapplyTitle(_ requested: SceneRenderQuality) {
        let pending = SceneDaemonClient.shared.activePreparedRenderQuality
            .map { $0 != requested.preparationQuality } ?? false
        let title = pending ? String(localized: "Reapply Current Scene (Pending Changes)")
                            : String(localized: "Reapply Current Scene")
        let button = reapplySceneQualityButton
        if let row = button.superview, row.isHidden == pending {
            row.isHidden = !pending
            qualitySection.refreshSeparators()
        }
        guard button.title != title else { return }
        let style = button.attributedTitle.attributes(at: 0, effectiveRange: nil)
        button.attributedTitle = NSAttributedString(string: title, attributes: style)
    }

    @objc private func handleSceneFrameRateSlider(_ sender: SceneFrameRateSlider) {
        guard !isUpdatingUI else { return }
        let fps = Int(sender.doubleValue.rounded())
        if sender.isTracking {
            updateSceneFrameRateLabels(fps)
        } else {
            commitSceneFrameRate(AnimationFrameRate(rawValue: fps))
        }
    }

    @objc private func handleQualityChange(_ sender: NSControl) {
        guard !isUpdatingUI else { return }
        var quality = PlaybackQualityPreference.current
        let previousPreparation = quality.scene.preparationQuality
        if sender === sceneQualityPresetPopup {
            guard let rawValue = sceneQualityPresetPopup.selectedItem?.representedObject as? String,
                  let preset = SceneQualityPreset(rawValue: rawValue) else { return }
            sceneFPSField.abortEditing()
            preset.apply(to: &quality)
            saveEditedQuality(quality, previousPreparation: previousPreparation)
            refreshQualityControls()
            return
        }
        if sender === webFrameRatePopup {
            quality.webFrameRateMode = webFrameRatePopup.indexOfSelectedItem == 1 ? .followAnimationFrameRate : .display
        } else if sender === sceneReflectionsSwitch {
            quality.scene.reflections = sceneReflectionsSwitch.state == .on ? .enabled : .disabled
        } else if let mode = (sender as? NSPopUpButton)?.selectedItem?.representedObject as? String {
            if sender === sceneAntiAliasingPopup, let selected = SceneAntiAliasingMode(rawValue: mode) {
                quality.scene.antiAliasing = selected
            } else if sender === sceneTextureQualityPopup, let selected = SceneTextureQuality(rawValue: mode) {
                quality.scene.textures = selected
            } else if sender === sceneShadowsPopup, let selected = SceneShadowQuality(rawValue: mode) {
                quality.scene.shadows = selected
            } else if sender === sceneVolumeLightingPopup, let selected = SceneVolumeLightingQuality(rawValue: mode) {
                quality.scene.volumeLighting = selected
            } else if sender === scenePostProcessingPopup, let selected = ScenePostProcessingMode(rawValue: mode) {
                quality.scene.postProcessing = selected
                refreshScenePostProcessingMenu(selected)
            }
        }
        saveEditedQuality(quality, previousPreparation: previousPreparation)
        refreshSceneQualityPreset(quality)
        refreshSceneQualityReapplyTitle(quality.scene)
        if sender === sceneAntiAliasingPopup || sender === sceneShadowsPopup { refreshSceneRenderReadouts(quality.scene) }
    }

    @objc private func reapplySceneQuality() {
        dependency.actions.reapplySceneQuality()
    }

    @objc private func restoreDefaultQuality() {
        sceneFPSField.abortEditing()
        saveEditedQuality(.defaults, previousPreparation: PlaybackQualityPreference.current.scene.preparationQuality)
        refreshQualityControls()
    }

    private func saveEditedQuality(_ quality: PlaybackQualityPreference, previousPreparation: SceneRenderQuality) {
        PlaybackCommandMultiplexer.shared.applyQualityPreference(quality)
        if previousPreparation != quality.scene.preparationQuality {
            dependency.actions.reapplyEditedSceneQuality()
        }
    }

    func refreshScenePostProcessingMenu(_ mode: ScenePostProcessingMode) {
        let displayHDRAvailable = SceneDaemonClient.shared.configuredWallpaperScreens.contains {
            $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
        }
        let displayHDR = scenePostProcessingPopup.indexOfItem(withRepresentedObject: ScenePostProcessingMode.ultraDisplayHDR.rawValue)
        let item = scenePostProcessingPopup.item(at: displayHDR)
        item?.isHidden = !displayHDRAvailable && !mode.requestsDisplayHDR
        item?.isEnabled = displayHDRAvailable
        item?.title = displayHDRAvailable ? String(localized: "Ultra (Display HDR)")
                                         : String(localized: "Ultra (Display HDR Unavailable)")
        scenePostProcessingPopup.selectItem(at: scenePostProcessingPopup.indexOfItem(withRepresentedObject: mode.rawValue))
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
            sceneMediaInfoSwitch,
            systemAudioSpectrumSwitch,
            systemHotkeysSwitch,
            pauseOtherAppFocusedSwitch,
            pauseOtherAppFullscreenSwitch,
            pauseWhenUnpluggedSwitch,
            pauseWhenIdleSwitch,
            sceneReflectionsSwitch,
            multiDisplaySwitch
        ]
        switches.forEach { $0.controlSize = .mini }
        hotkeyEnableSwitches.values.forEach { $0.controlSize = .mini }

        let popups: [NSPopUpButton] = [timeUnitPopup, idleTimeoutPopup, libraryBackgroundPopup, libraryCardClickPopup, webFrameRatePopup, scenePostProcessingPopup] + hotkeyPopups.values
            + [sceneQualityPresetPopup, sceneAntiAliasingPopup, sceneShadowsPopup, sceneVolumeLightingPopup, sceneTextureQualityPopup, systemAudioSpectrumBarCountPopup]
        popups.forEach { $0.controlSize = .small }

        intervalField.controlSize = .small
        sceneFPSField.controlSize = .small
        sceneFPSControl.controlSize = .small
        volumeSlider.controlSize = .small
        playbackRateSlider.controlSize = .small
        exportProfileButton.controlSize = .regular
        importProfileButton.controlSize = .regular
        clearCacheButton.controlSize = .regular
        resetSettingsButton.controlSize = .regular
    }


    private func makeSettingRow(title: String, iconSystemName: String? = nil, subtitle: String? = nil,
                                trailing: NSView, leadingInset: CGFloat = 0, readout: NSTextField? = nil) -> NSView {
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
            if let readout { textStack.addArrangedSubview(readout) }
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

final class SceneFrameRateSlider: NSSlider {
    private(set) var isTracking = false

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        super.mouseDown(with: event)
        isTracking = false
        sendAction(action, to: target)
    }

    override func keyDown(with event: NSEvent) {
        let step: Int
        switch event.specialKey {
        case .leftArrow, .downArrow: step = -1
        case .rightArrow, .upArrow: step = 1
        default:
            super.keyDown(with: event)
            return
        }
        let value = Int(doubleValue.rounded())
        let next = min(max(value + step, Int(minValue)), Int(maxValue))
        guard next != value else { return }
        integerValue = next
        sendAction(action, to: target)
    }
}
