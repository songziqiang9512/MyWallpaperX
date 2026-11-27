import AppKit

extension AppKitSettingsContainerView {
    func setupSections() {
        setupPlaybackSection(forms[.playback]!)
        setupQualitySection(forms[.quality]!)
        setupDisplaySection(forms[.display]!)
        setupSystemSection(forms[.system]!)
        setupHotkeysSection(forms[.hotkeys]!)
        setupEfficiencySection(forms[.efficiency]!)
        setupMaintenanceSection(forms[.maintenance]!)
        setupAboutSection(forms[.about]!)
    }

    func scheduleDocumentFrameUpdate() {
        guard !isDocumentFrameUpdateScheduled else { return }
        isDocumentFrameUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isDocumentFrameUpdateScheduled = false
            self.updateDocumentFrame()
        }
    }

    private func setupPlaybackSection(_ form: SettingsFormView) {
        loopSwitch.title = String(localized: "Loop")
        sequentialSwitch.title = String(localized: "Play in Order")
        randomSwitch.title = String(localized: "Shuffle")
        form.addGroup(String(localized: "Playback Modes"), controls: [loopSwitch, sequentialSwitch, randomSwitch])

        intervalField.alignment = .right
        intervalField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        intervalField.delegate = self
        intervalField.widthAnchor.constraint(equalToConstant: 46).isActive = true
        for unit in TimeUnit.allCases {
            timeUnitPopup.addItem(withTitle: unit.rawValue)
            timeUnitPopup.lastItem?.representedObject = unit
        }

        let intervalLabel = NSTextField(labelWithString: String(localized: "Interval"))
        intervalField.setAccessibilityLabel(intervalLabel.stringValue)
        let interval = SettingsFormView.controls(
            [intervalLabel, intervalField, timeUnitPopup], horizontal: true, indent: SettingsPanelLayout.subordinateInset
        )
        intervalRowView = interval
        autoSwitchSwitch.title = String(localized: "Auto Switch")
        autoSwitchRow = form.addGroup(String(localized: "Wallpaper Rotation"), controls: [autoSwitchSwitch, interval])

        form.addDivider()
        muteSwitch.title = String(localized: "Mute")
        volumeSlider.setAccessibilityLabel(String(localized: "Volume"))
        styleSlider(volumeSlider, valueLabel: volumeValueLabel, width: 200)
        let volume = SettingsFormView.controls([volumeSlider, volumeValueLabel, muteSwitch], horizontal: true)
        form.addGroup(String(localized: "Volume"), controls: [volume])

        playbackRateSwitch.title = String(localized: "Adjust Playback Speed")
        playbackRateSlider.setAccessibilityLabel(String(localized: "Playback Speed"))
        styleSlider(playbackRateSlider, valueLabel: playbackRateValueLabel, width: 160)
        let rate = SettingsFormView.controls(
            [playbackRateSlider, playbackRateValueLabel], horizontal: true, indent: SettingsPanelLayout.subordinateInset
        )
        playbackRateControls = rate
        form.addGroup(String(localized: "Speed"), controls: [playbackRateSwitch, rate])
    }

    private func setupSystemSection(_ form: SettingsFormView) {
        startOnBootSwitch.title = String(localized: "Launch at Login")
        restorePlaybackOnLaunchSwitch.title = String(localized: "Resume Playback at Launch")
        restorePlaybackOnLaunchSwitch.toolTip = String(localized: "Restore the last wallpaper (Video, Web or Scene) at launch. When off, no wallpaper plays at launch. Static image wallpapers are kept by the system and are not affected.")
        form.addGroup(String(localized: "Startup"), controls: [startOnBootSwitch, restorePlaybackOnLaunchSwitch])

        syncSystemWallpaperSwitch.title = String(localized: "Sync System Wallpaper")
        syncSystemWallpaperSwitch.toolTip = String(localized: "Also update the system wallpaper when the wallpaper changes: a still frame for Video, and one frame captured after the launch transition for Web and Scene. Static image wallpapers are always applied directly.")
        form.addGroup(String(localized: "Desktop"), controls: [syncSystemWallpaperSwitch])

        form.addDivider()
        systemAudioSpectrumSwitch.title = String(localized: "Audio Spectrum")
        for barCount in [16, 20, 28, 36, 48] {
            systemAudioSpectrumBarCountPopup.addItem(withTitle: String(localized: "\(barCount) bars"))
            systemAudioSpectrumBarCountPopup.lastItem?.representedObject = barCount
        }
        systemAudioSpectrumColorWell.supportsAlpha = false

        let spectrum = SettingsFormView(rowSpacing: SettingsPanelLayout.controlSpacing)
        let sensitivity = String(localized: "Sensitivity")
        systemAudioSpectrumSensitivityPopup.setAccessibilityLabel(sensitivity)
        for choice in SystemAudioSpectrumSensitivity.allCases {
            systemAudioSpectrumSensitivityPopup.addItem(withTitle: choice.displayName)
            systemAudioSpectrumSensitivityPopup.lastItem?.representedObject = choice
        }
        let response = String(localized: "Spectrum Response")
        systemAudioSpectrumStylePopup.setAccessibilityLabel(response)
        for choice in SystemAudioSpectrumStyle.allCases {
            systemAudioSpectrumStylePopup.addItem(withTitle: choice.displayName)
            systemAudioSpectrumStylePopup.lastItem?.representedObject = choice
        }
        spectrum.addGroup(response, controls: [systemAudioSpectrumStylePopup])
        spectrum.addGroup(sensitivity, controls: [systemAudioSpectrumSensitivityPopup])
        spectrum.addGroup(String(localized: "Bar Count"), controls: [systemAudioSpectrumBarCountPopup])
        spectrum.addGroup(String(localized: "Color"), controls: [systemAudioSpectrumColorWell])
        for (title, slider, valueLabel) in [
            (String(localized: "X Position"), systemAudioSpectrumOffsetXSlider, systemAudioSpectrumOffsetXValueLabel),
            (String(localized: "Y Position"), systemAudioSpectrumOffsetYSlider, systemAudioSpectrumOffsetYValueLabel)
        ] {
            slider.setAccessibilityLabel(title)
            styleSlider(slider, valueLabel: valueLabel, width: 160)
            spectrum.addGroup(title, controls: [SettingsFormView.controls([slider, valueLabel], horizontal: true)])
        }
        systemAudioSpectrumPeakCapsSwitch.title = String(localized: "Show Peak Caps")
        let spectrumOptions = SettingsFormView.controls(
            [spectrum, systemAudioSpectrumPeakCapsSwitch], indent: SettingsPanelLayout.subordinateInset
        )
        systemAudioSpectrumOptionsContainer = spectrumOptions
        form.addGroup(String(localized: "Video"), controls: [
            systemAudioSpectrumSwitch,
            SettingsFormView.detail(String(localized: "A visual effect that applies only to Video wallpapers"),
                                    indent: SettingsPanelLayout.checkboxTextInset),
            spectrumOptions
        ])

        sceneMediaInfoSwitch.title = String(localized: "Wallpaper Song Info")
        sceneMediaInfoSwitch.toolTip = String(localized: "Shows the current track and artwork on Scene wallpapers. macOS asks for permission the first time Apple Music is read. If you denied it, allow it in System Settings > Privacy & Security > Automation and turn this on again.")
        let audioListening = String(localized: "Listen to System Audio")
        webAudioListeningSwitch.title = audioListening
        sceneAudioListeningSwitch.title = audioListening
        form.addGroup(String(localized: "Web Wallpaper"), controls: [webAudioListeningSwitch])
        form.addGroup(String(localized: "Scene"), controls: [sceneAudioListeningSwitch])
        form.addGroup(String(localized: "Wallpaper"), controls: [
            sceneMediaInfoSwitch,
            SettingsFormView.detail(String(localized: "Show the current track and artwork on supported Scene and Web wallpapers"),
                                    indent: SettingsPanelLayout.checkboxTextInset)
        ])
    }

    private func setupHotkeysSection(_ form: SettingsFormView) {
        for action in SystemHotkeyAction.allCases {
            let popup = NSPopUpButton()
            popup.autoenablesItems = false
            popup.setAccessibilityLabel(action.displayName)
            popup.target = self
            popup.action = #selector(handleHotkeyPopupChange(_:))
            for shortcut in FunctionKeyShortcut.allCases {
                popup.addItem(withTitle: shortcut.displayName)
                popup.lastItem?.representedObject = shortcut
            }
            form.addGroup(action.displayName, controls: [popup])
            hotkeyPopups[action] = popup
        }
    }

    private func setupEfficiencySection(_ form: SettingsFormView) {
        pauseOtherAppFocusedSwitch.title = String(localized: "Pause When Another App Is Focused")
        pauseOtherAppFocusedSwitch.toolTip = String(localized: "Pause the wallpaper while another app is in front (excluding Finder on the desktop and this app)")
        pauseOtherAppFullscreenSwitch.title = String(localized: "Pause When Another App Is Full Screen")
        pauseOtherAppFullscreenSwitch.toolTip = String(localized: "Pause the wallpaper when another app enters full screen and covers the main desktop")
        pauseWhenUnpluggedSwitch.title = String(localized: "Pause When on Battery")
        pauseWhenIdleSwitch.title = String(localized: "Pause When Idle")

        for value in [5, 10, 15, 20, 30, 60] {
            idleTimeoutPopup.addItem(withTitle: String(localized: "\(value) min"))
            idleTimeoutPopup.lastItem?.representedObject = value
        }
        let idleLabel = NSTextField(labelWithString: String(localized: "Idle Time"))
        idleTimeoutPopup.setAccessibilityLabel(idleLabel.stringValue)
        let timeout = SettingsFormView.controls(
            [idleLabel, idleTimeoutPopup], horizontal: true, indent: SettingsPanelLayout.subordinateInset
        )
        idleTimeoutRowView = timeout
        form.addGroup(String(localized: "Pause"), controls: [
            pauseOtherAppFocusedSwitch, pauseOtherAppFullscreenSwitch, pauseWhenUnpluggedSwitch, pauseWhenIdleSwitch, timeout
        ])

    }

    private func setupDisplaySection(_ form: SettingsFormView) {
        for (index, style) in LibraryBackgroundStyle.allCases.enumerated() {
            libraryBackgroundPopup.addItem(withTitle: style.title)
            libraryBackgroundPopup.lastItem?.tag = index
            libraryBackgroundPopup.lastItem?.representedObject = style
        }
        libraryBackgroundPopup.setAccessibilityLabel(String(localized: "App Theme"))
        form.addGroup(String(localized: "App Theme"), controls: [libraryBackgroundPopup])

        for (index, action) in LibraryCardClickAction.allCases.enumerated() {
            libraryCardClickPopup.addItem(withTitle: action.title)
            libraryCardClickPopup.lastItem?.tag = index
            libraryCardClickPopup.lastItem?.representedObject = action
        }
        libraryCardClickPopup.setAccessibilityLabel(String(localized: "Card Click Action"))
        form.addGroup(String(localized: "Card Click Action"), controls: [libraryCardClickPopup])

        keepDockIconSwitch.title = String(localized: "Keep Dock Icon When the Main Window Is Closed")
        form.addGroup("Dock", controls: [keepDockIconSwitch])

        form.addDivider()
        multiDisplaySwitch.title = String(localized: "Show Wallpaper on All Displays")
        multiDisplaySwitch.toolTip = String(localized: "Show the wallpaper on all displays (Video, Web and Scene)")
        form.addGroup(String(localized: "Wallpaper"), controls: [multiDisplaySwitch])
        form.addGroup(String(localized: "Wallpaper Fill Mode"), controls: [fillModeFitButton, fillModeFillButton])

        form.addDivider()
        let screenSaver = NSButton(title: String(localized: "Configure"), target: self, action: #selector(openScreenSaverSettings))
        screenSaver.bezelStyle = .rounded
        form.addGroup(String(localized: "Lock Screen & Screen Saver"), controls: [
            screenSaver, SettingsFormView.detail(String(localized: "Play local videos muted on loop as the system screen saver"))
        ])
    }

    private func setupMaintenanceSection(_ form: SettingsFormView) {
        exportProfileButton.target = self
        exportProfileButton.action = #selector(handleExportProfile)
        importProfileButton.target = self
        importProfileButton.action = #selector(handleImportProfile)

        let transfer = SettingsFormView.controls([importProfileButton, exportProfileButton], horizontal: true)
        form.addGroup(String(localized: "Personal Settings"), controls: [transfer])
        form.addGroup(String(localized: "Cache"), controls: [clearCacheButton])
        form.addDivider()
        form.addGroup(String(localized: "Reset"), controls: [resetSettingsButton])
    }

    private func setupAboutSection(_ form: SettingsFormView) {
        let github = NSButton(title: "GitHub", target: self, action: #selector(openProjectWebsite))
        github.toolTip = String(localized: "View the project, report issues, or star it on GitHub")
        form.addGroup("MyWallpaperX", controls: [
            SettingsFormView.detail(String(localized: "Simple by intention, pure by design.\nA native wallpaper manager built for macOS.")), github
        ])
        form.addDivider()
        let update = NSButton(title: String(localized: "Check for Updates"), target: self, action: #selector(checkForUpdates(_:)))
        var controls = [update]
        if dependency.actions.automaticUpdateChecksEnabled() != nil {
            let checks = NSButton(
                checkboxWithTitle: String(localized: "Automatically Check for Updates"),
                target: self, action: #selector(changeAutomaticUpdateChecks(_:))
            )
            let downloads = NSButton(
                checkboxWithTitle: String(localized: "Automatically Download and Install Updates"),
                target: self, action: #selector(changeAutomaticUpdateDownloads(_:))
            )
            automaticUpdateChecksButton = checks
            automaticUpdateDownloadsButton = downloads
            refreshUpdaterControls()
            controls = [checks, downloads, update]
        }
        form.addGroup(String(localized: "Software Update"), controls: controls)
    }

    private func setupQualitySection(_ form: SettingsFormView) {
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
        form.addGroup(String(localized: "Scene Quality Preset"), controls: [sceneQualityPresetPopup])

        sceneFPSControls.spacing = 2
        sceneFPSField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
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
        form.addGroup(String(localized: "Animation Frame Rate"), controls: [
            sceneFPSControls, SettingsFormView.detail(String(localized: "Sets the frame rate cap for Scene wallpapers"))
        ])
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
        form.addGroup(String(localized: "Scene Anti-Aliasing"), controls: [
            antiAliasingControls,
            SettingsFormView.detail(String(localized: "Uses multisampling where the Scene supports it", table: "SceneQuality"))
        ])

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
        addQualityEffect(String(localized: "Scene Post-Processing"), control: scenePostProcessingPopup,
                         readout: scenePostProcessingUseLabel, to: form)
        for mode in SceneTextureQuality.allCases {
            let title = switch mode {
            case .automatic: String(localized: "Automatic")
            case .full: String(localized: "High Quality")
            case .performance: String(localized: "High Performance")
            }
            sceneTextureQualityPopup.addItem(withTitle: title)
            sceneTextureQualityPopup.lastItem?.representedObject = mode.rawValue
        }
        addQualityEffect(String(localized: "Texture Resolution"), control: sceneTextureQualityPopup,
                         readout: sceneTextureUseLabel, to: form)
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
        addQualityEffect(String(localized: "Scene Shadows"), control: sceneShadowsPopup,
                         readout: sceneShadowUseLabel, to: form)
        let volumeTiers: [(SceneVolumeLightingQuality, String)] = [
            (.disabled, String(localized: "Disabled")),
            (.enabled, String(localized: "High")),
            (.ultra, String(localized: "Ultra")),
        ]
        for (tier, title) in volumeTiers {
            sceneVolumeLightingPopup.addItem(withTitle: title)
            sceneVolumeLightingPopup.lastItem?.representedObject = tier.rawValue
        }
        addQualityEffect(String(localized: "Volumetric Lighting"), control: sceneVolumeLightingPopup,
                         readout: sceneVolumeUseLabel, to: form)
        addQualityEffect(String(localized: "Scene Reflections"), control: sceneReflectionsSwitch,
                         readout: sceneReflectionUseLabel, to: form)
        reapplySceneQualityButton.identifier = NSUserInterfaceItemIdentifier("settings.scene.reapply-quality")
        reapplySceneQualityButton.isEnabled = false
        reapplySceneQualityButton.target = self
        reapplySceneQualityButton.action = #selector(reapplySceneQuality)
        reapplySceneQualityRow = form.addGroup(String(localized: "Scene"), controls: [
            reapplySceneQualityButton,
            SettingsFormView.detail(String(localized: "Some effect changes require reloading the wallpaper"))
        ])
        form.addDivider()
        webFrameRatePopup.addItems(withTitles: [
            String(localized: "Match Display (up to 60 FPS)"),
            String(localized: "Follow Animation Frame Rate"),
        ])
        let webFrameRateTitle = String(localized: "Web Frame Rate Suggestion")
        webFrameRatePopup.setAccessibilityLabel(webFrameRateTitle)
        form.addGroup(webFrameRateTitle, controls: [
            webFrameRatePopup,
            SettingsFormView.detail(String(localized: "Applies when the Web wallpaper uses the suggested frame rate"))
        ])
        form.addGroup(String(localized: "Video Quality"), controls: [
            NSTextField(labelWithString: String(localized: "Original Video"))
        ])
        let controls: [NSControl] = [sceneQualityPresetPopup, sceneAntiAliasingPopup, scenePostProcessingPopup, sceneTextureQualityPopup,
                                     sceneShadowsPopup, sceneVolumeLightingPopup, sceneReflectionsSwitch, webFrameRatePopup]
        for control in controls {
            control.target = self
            control.action = #selector(handleQualityChange(_:))
        }
        resetQualityButton.target = self
        resetQualityButton.action = #selector(restoreDefaultQuality)
        form.addGroup(String(localized: "Wallpaper Quality"), controls: [resetQualityButton])
    }

    private func addQualityEffect(_ title: String, control: NSControl, readout: NSTextField,
                                  to form: SettingsFormView) {
        control.setAccessibilityLabel(title)
        let column = SettingsFormView.controls([control, readout])
        readout.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor,
                                       constant: -SettingsPanelLayout.columnSpacing).isActive = true
        form.addGroup(title, controls: [column])
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
        if let row = reapplySceneQualityRow, row.isHidden == pending {
            row.isHidden = !pending
            if visibleSection == .quality {
                scheduleDocumentFrameUpdate()
                onFormHeightChanged?()
            }
        }
        reapplySceneQualityButton.title = title
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
        if sender === sceneReflectionsSwitch || sender === sceneAntiAliasingPopup || sender === sceneTextureQualityPopup
            || sender === sceneShadowsPopup || sender === sceneVolumeLightingPopup || sender === scenePostProcessingPopup {
            refreshSceneRenderReadouts(quality.scene)
        }
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

    private func styleSlider(_ slider: NSSlider, valueLabel: NSTextField, width: CGFloat) {
        slider.controlSize = .small
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
    }

    @objc private func openScreenSaverSettings() { dependency.actions.openScreenSaverSettings() }
    @objc private func openProjectWebsite() { dependency.actions.openProjectWebsite() }
    @objc private func checkForUpdates(_ sender: NSButton) { dependency.actions.checkForUpdates(sender) }
    func refreshUpdaterControls() {
        guard let checks = automaticUpdateChecksButton,
              let enabled = dependency.actions.automaticUpdateChecksEnabled() else { return }
        checks.state = enabled ? .on : .off
        automaticUpdateDownloadsButton?.isEnabled = enabled
        automaticUpdateDownloadsButton?.state = dependency.actions.automaticUpdateDownloadsEnabled() ? .on : .off
    }

    @objc private func changeAutomaticUpdateDownloads(_ sender: NSButton) {
        dependency.actions.setAutomaticUpdateDownloadsEnabled(sender.state == .on)
    }

    @objc private func changeAutomaticUpdateChecks(_ sender: NSButton) {
        dependency.actions.setAutomaticUpdateChecksEnabled(sender.state == .on)
        refreshUpdaterControls()
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
