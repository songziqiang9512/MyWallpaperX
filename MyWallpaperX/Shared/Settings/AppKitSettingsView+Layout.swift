import AppKit

extension AppKitSettingsContainerView {
    func setupSections() {
        setupPlaybackSection(forms[.playback]!)
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

        sceneHDRDisplaySwitch.title = String(localized: "Scene HDR")
        sceneMediaInfoSwitch.title = String(localized: "Wallpaper Song Info")
        sceneMediaInfoSwitch.toolTip = String(localized: "Shows the current track and artwork on Scene wallpapers. macOS asks for permission the first time Apple Music is read. If you denied it, allow it in System Settings > Privacy & Security > Automation and turn this on again.")
        let audioListening = String(localized: "Listen to System Audio")
        webAudioListeningSwitch.title = audioListening
        sceneAudioListeningSwitch.title = audioListening
        form.addGroup(String(localized: "Web Wallpaper"), controls: [webAudioListeningSwitch])
        form.addGroup(String(localized: "Scene"), controls: [
            sceneAudioListeningSwitch, sceneHDRDisplaySwitch,
            SettingsFormView.detail(String(localized: "Requires wallpaper support; very high power draw, enable with care"),
                                    indent: SettingsPanelLayout.checkboxTextInset)
        ])
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

        form.addDivider()
        sceneMaxFPSSegmented.setAccessibilityLabel(String(localized: "Scene Frame Rate Cap"))
        form.addGroup(String(localized: "Scene Frame Rate"), controls: [
            sceneMaxFPSSegmented, SettingsFormView.detail(String(localized: "30 fps is recommended for everyday use to save power"))
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
