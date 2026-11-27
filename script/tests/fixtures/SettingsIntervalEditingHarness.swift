import AppKit
import Combine

enum TimeUnit: String, CaseIterable { case seconds = "秒", minutes = "分钟" }
struct WallpaperSettings {
    var loopPlayback = true, randomPlayback = false, sequentialPlayback = false, autoSwitchEnabled = false
    var randomInterval = 30
    var timeUnit = TimeUnit.seconds
    var volume = 50.0, playbackRate = 1.0
    var playbackRateEnabled = false
}
@MainActor final class PlaybackMuteState {
    static let shared = PlaybackMuteState()
    let isMuted = false
}
struct PersonalSettingsExportSummary {}
struct PersonalSettingsImportSummary {}
enum PersonalSettingsError: Error { case recoveryRequired(String) }
enum SceneMediaSourcePreference { static let isEnabled = false }
@MainActor struct NSScreen {
    static var screens: [Self] = []
    let maximumPotentialExtendedDynamicRangeColorComponentValue: Double
}
extension Notification.Name {
    static let playbackMuteStateDidChange = Self("fixture.mute")
    static let wallpaperManagerLoginItemSyncFailed = Self("fixture.login-item")
    static let sceneDaemonAnimationCadenceDidChange = Self("fixture.cadence")
    static let sceneDaemonPreparedQualityDidChange = Self("fixture.preparation-quality")
    static let sceneDaemonRasterSamplesDidChange = Self("fixture.raster-samples")
}

@MainActor final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()
    private(set) var requests: [Int] = []

    func applyQualityPreference(_ preference: PlaybackQualityPreference) {
        preference.write(to: .standard)
        requests.append(preference.animationFrameRate.rawValue)
    }
}

@MainActor final class SceneDaemonClient {
    struct ActiveAnimationCadence {
        let requestedFPS: AnimationFrameRate
        let effectiveFPS: Double
    }
    static let shared = SceneDaemonClient()
    var configuredAnimationCadenceLimit: Double = 60
    var activeAnimationCadence: ActiveAnimationCadence?
    var activePreparedRenderQuality: SceneRenderQuality?
    var activeRasterDisplayStatuses: [SceneRasterDisplayStatus] = []
    var multiDisplayEnabled = true
    // ACTUAL_CONFIGURED_WALLPAPER_SCREENS
}

// ACTUAL_FRAME_RATE_SLIDER

@MainActor final class AppKitSettingsContainerView: NSView, NSTextFieldDelegate {
    let dependency: AppSettingsPanelDependency
    var isUpdatingUI = false
    var cancellables = Set<AnyCancellable>()
    var muteStateObserver: NSObjectProtocol?, loginItemSyncFailureObserver: NSObjectProtocol?
    let sceneMediaInfoSwitch = NSSwitch()
    let sceneQualityPresetPopup = NSPopUpButton(), sceneAntiAliasingPopup = NSPopUpButton()
    let sceneRasterSamplesLabel = NSTextField(labelWithString: "")
    let scenePostProcessingPopup = NSPopUpButton(), sceneTextureQualityPopup = NSPopUpButton()
    let sceneShadowsPopup = NSPopUpButton(), sceneVolumeLightingPopup = NSPopUpButton()
    // ACTUAL_SHADOW_LABEL
    lazy var shadowRow = makeSettingRow(title: "Scene Shadows", iconSystemName: "shadow",
        subtitle: "Some effect changes require reloading the wallpaper", trailing: sceneShadowsPopup, readout: sceneShadowUseLabel)
    let sceneReflectionsSwitch = NSSwitch(), webFrameRatePopup = NSPopUpButton()
    let reapplySceneQualityButton = NSButton(title: "Reapply Current Scene", target: nil, action: nil)
    let qualitySection = SettingsGroupView(title: nil)
    let loopSwitch = NSSwitch(), randomSwitch = NSSwitch(), sequentialSwitch = NSSwitch(), autoSwitchSwitch = NSSwitch()
    let intervalField = NSTextField(frame: .init(x: 20, y: 70, width: 160, height: 28))
    let sceneFPSField = NSTextField(frame: .init(x: 198, y: 70, width: 40, height: 28))
    let sceneFPSEffectiveLabel = NSTextField(labelWithString: "")
    let sceneFPSControl = SceneFrameRateSlider(value: 60, minValue: 10, maxValue: 120, target: nil, action: nil)
    let timeUnitPopup = NSPopUpButton()
    let volumeSlider = NSSlider(), volumeValueLabel = NSTextField(), muteSwitch = NSSwitch()
    let playbackRateSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 2, target: nil, action: nil)
    let playbackRateValueLabel = NSTextField(), playbackRateSwitch = NSSwitch()
    var intervalRowView: NSView? = NSView(), autoSwitchRowView: NSView? = NSView()
    let nextField = NSTextField(frame: .init(x: 20, y: 20, width: 160, height: 28))
    init(_ dependency: AppSettingsPanelDependency) {
        self.dependency = dependency
        super.init(frame: .init(x: 0, y: 0, width: 360, height: 160))
        let qualityRetryRow = NSView()
        qualityRetryRow.addSubview(reapplySceneQualityButton)
        qualitySection.addRow(qualityRetryRow)
        intervalField.delegate = self
        sceneFPSField.delegate = self
        sceneFPSControl.frame = .init(x: 188, y: 20, width: 148, height: 28)
        sceneFPSControl.isContinuous = true
        sceneFPSControl.target = self
        sceneFPSControl.action = #selector(handleSceneFrameRateSlider(_:))
        playbackRateSlider.target = self
        playbackRateSlider.action = #selector(handlePlaybackRateChange)
        playbackRateSwitch.target = self
        playbackRateSwitch.action = #selector(handlePlaybackRateSwitchToggle)
        addSubview(intervalField); addSubview(nextField)
        addSubview(sceneFPSField); addSubview(sceneFPSControl)
        commitSceneFrameRate(nil)
        scenePostProcessingPopup.autoenablesItems = false
        for mode in [ScenePostProcessingMode.disabled, .enabled, .ultra, .ultraDisplayHDR] {
            scenePostProcessingPopup.addItem(withTitle: mode.rawValue)
            scenePostProcessingPopup.lastItem?.representedObject = mode.rawValue
        }
        for mode in SceneAntiAliasingMode.allCases {
            sceneAntiAliasingPopup.addItem(withTitle: mode.rawValue)
            sceneAntiAliasingPopup.lastItem?.representedObject = mode.rawValue
        }
        for mode in SceneTextureQuality.allCases {
            sceneTextureQualityPopup.addItem(withTitle: mode.rawValue)
            sceneTextureQualityPopup.lastItem?.representedObject = mode.rawValue
        }
        for tier in [SceneVolumeLightingQuality.disabled, .enabled, .ultra] {
            sceneVolumeLightingPopup.addItem(withTitle: tier.rawValue)
            sceneVolumeLightingPopup.lastItem?.representedObject = tier.rawValue
        }
        webFrameRatePopup.addItems(withTitles: ["Display", "Follow"])
        sceneQualityPresetPopup.autoenablesItems = false
        sceneQualityPresetPopup.addItem(withTitle: "Custom")
        sceneQualityPresetPopup.lastItem?.isEnabled = false
        for preset in SceneQualityPreset.allCases {
            sceneQualityPresetPopup.addItem(withTitle: preset.rawValue)
            sceneQualityPresetPopup.lastItem?.representedObject = preset.rawValue
        }
        for shadow in [SceneShadowQuality.disabled, .low, .medium, .high, .adaptive] {
            sceneShadowsPopup.addItem(withTitle: shadow.rawValue)
            sceneShadowsPopup.lastItem?.representedObject = shadow.rawValue
        }
        for control in [sceneQualityPresetPopup, sceneAntiAliasingPopup, sceneTextureQualityPopup,
                        sceneVolumeLightingPopup, scenePostProcessingPopup, sceneShadowsPopup] {
            control.target = self
            control.action = #selector(handleQualityChange(_:))
        }
        for unit in TimeUnit.allCases {
            timeUnitPopup.addItem(withTitle: unit.rawValue)
            timeUnitPopup.lastItem?.representedObject = unit
        }
        observeManager(); refreshFromState()
    }
    required init?(coder: NSCoder) { nil }
    deinit {
        if let muteStateObserver { NotificationCenter.default.removeObserver(muteStateObserver) }
        if let loginItemSyncFailureObserver { NotificationCenter.default.removeObserver(loginItemSyncFailureObserver) }
    }
    func layoutVisibilitySignature() -> [Bool] { [] }
    func scheduleDocumentFrameUpdate() {}
    func presentLoginItemSyncFailure(_ note: Notification) {}
    // ACTUAL_INTERVAL_REFRESH
    // ACTUAL_SETTINGS_OBSERVER
    // ACTUAL_SCENE_POST_PROCESSING_MENU
    // ACTUAL_SCENE_REAPPLY_TITLE
    // ACTUAL_RENDER_READOUTS
    // ACTUAL_RASTER_SAMPLE_READOUT
    // ACTUAL_RENDER_READOUT_TITLE
    // ACTUAL_RENDER_READOUT_DISPLAY
    // ACTUAL_SHADOW_USE_DESCRIPTION
    // ACTUAL_VOLUME_USE_DESCRIPTION
    // ACTUAL_TEXTURE_USE_DESCRIPTION
    // ACTUAL_EFFECT_READOUT
    // ACTUAL_SETTINGS_ROW
    // ACTUAL_LEADING_ROW_CONTENT
    // ACTUAL_ROW_ICON
    // ACTUAL_SANITIZED_ROW_IDENTIFIER
    // ACTUAL_RESTORE_QUALITY_CONTROLS
    // ACTUAL_REFRESH_SCENE_QUALITY_PRESET
    // ACTUAL_QUALITY_ACTION
    // ACTUAL_RESTORE_DEFAULT_QUALITY_ACTION
    // ACTUAL_SAVE_EDITED_QUALITY
    // ACTUAL_FRAME_RATE_LABELS
    // ACTUAL_REFRESH_FRAME_RATE_READOUT
    // ACTUAL_FRAME_RATE_READOUT
    // ACTUAL_FRAME_RATE_COMMIT
    // ACTUAL_FRAME_RATE_ACTION
    // ACTUAL_INTERVAL_COMMIT
    // ACTUAL_TIME_UNIT_SELECTION
    // ACTUAL_PLAYBACK_RATE_ACTION
    // ACTUAL_PLAYBACK_RATE_LABEL
    // ACTUAL_PLAYBACK_RATE_SWITCH
}

@main struct SettingsIntervalEditingHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var settings = WallpaperSettings()
        settings.loopPlayback = false; settings.sequentialPlayback = true; settings.autoSwitchEnabled = true
        var timerRefreshes = 0
        var coldEdits: [SceneRenderQuality] = []
        var actions = AppSettingsActions()
        actions.refreshAutoSwitchTimerIfNeeded = { timerRefreshes += 1 }
        actions.reapplyEditedSceneQuality = { coldEdits.append(PlaybackQualityPreference.current.scene.preparationQuality) }
        let dependency = AppSettingsPanelDependency(settings: settings, actions: actions)
        let view = AppKitSettingsContainerView(dependency)
        let window = NSWindow(contentRect: .init(x: 14000, y: 14000, width: 360, height: 160),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        window.initialFirstResponder = view.nextField
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.04)) }
        func diagnose(_ phase: String) {
            let editor = view.intervalField.currentEditor() as? NSTextView
            let values = "Interval \(phase): editor=\(editor.map { String(describing: ObjectIdentifier($0)) } ?? "nil") "
                + "draft=\(editor?.string ?? "nil") field=\(view.intervalField.stringValue) interval=\(dependency.settings.randomInterval) "
                + "timers=\(timerRefreshes) enabled=\(view.intervalField.isEnabled) updating=\(view.isUpdatingUI) "
                + "first=\(String(describing: window.firstResponder))\n"
            FileHandle.standardError.write(Data(values.utf8))
        }
        func draft(_ text: String, in field: NSTextField? = nil) throws -> NSTextView {
            let field = field ?? view.intervalField
            field.selectText(nil)
            guard let editor = field.currentEditor() as? NSTextView, editor.isFieldEditor,
                  window.firstResponder === editor, window.fieldEditor(false, for: field) === editor else {
                throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "native field editor did not attach"])
            }
            editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            editor.setSelectedRange(NSRange(location: min(1, text.utf16.count), length: 0))
            return editor
        }
        var checks: [String: Bool] = [:]
        let editor = try draft("417"), caret = (view.intervalField.currentEditor() as! NSTextView).selectedRange()
        diagnose("initial-draft")
        NotificationCenter.default.post(name: .playbackMuteStateDidChange, object: nil)
        diagnose("mute")
        checks["mute-publication-preserves-native-editor-draft-and-caret-without-committing"] = view.intervalField.currentEditor() === editor
            && editor.string == "417" && editor.selectedRange() == caret && dependency.settings.randomInterval == 30 && timerRefreshes == 0
        dependency.objectWillChange.send(); pump()
        diagnose("global")
        checks["unrelated-global-publication-preserves-the-same-field-editor-and-unsubmitted-draft"] = view.intervalField.currentEditor() === editor
            && editor.string == "417" && editor.selectedRange() == caret && dependency.settings.randomInterval == 30 && timerRefreshes == 0
        window.makeFirstResponder(view.nextField); pump()
        diagnose("focus-loss")
        checks["native-focus-loss-commits-interval-once-through-the-original-delegate"] = dependency.settings.randomInterval == 417
            && view.intervalField.currentEditor() == nil && view.intervalField.stringValue == "417" && timerRefreshes == 1
        _ = try draft("0")
        window.makeFirstResponder(view.nextField); pump()
        diagnose("normalized")
        checks["native-focus-loss-keeps-the-existing-positive-interval-normalization"] = dependency.settings.randomInterval == 1
            && view.intervalField.stringValue == "1" && timerRefreshes == 2
        _ = try draft("987")
        dependency.settings.loopPlayback = true; dependency.settings.sequentialPlayback = false
        dependency.settings.autoSwitchEnabled = false; pump()
        window.makeFirstResponder(view.nextField); pump()
        diagnose("disabled")
        checks["disabled-mode-aborts-native-editing-without-committing-the-old-draft"] = !view.intervalField.isEnabled
            && view.intervalField.currentEditor() == nil && view.intervalField.stringValue == "1"
            && dependency.settings.randomInterval == 1 && timerRefreshes == 2
        dependency.settings = settings; pump()
        _ = try draft("654")
        dependency.settings = WallpaperSettings(); pump()
        window.makeFirstResponder(view.nextField); pump()
        diagnose("reset")
        checks["external-fresh-install-reset-keeps-defaults-and-revokes-the-unsubmitted-editor"] = !view.intervalField.isEnabled
            && view.intervalField.currentEditor() == nil && view.intervalField.stringValue == "30"
            && dependency.settings.randomInterval == 30 && dependency.settings.loopPlayback && timerRefreshes == 2
        let requests = PlaybackCommandMultiplexer.shared
        _ = try draft(" 97 ", in: view.sceneFPSField)
        checks["frame-rate-native-edit-only-previews-until-focus-loss"] = requests.requests.isEmpty
        window.makeFirstResponder(view.nextField); pump()
        checks["frame-rate-keeps-request-and-shows-lower-active-cap"] = requests.requests == [97]
            && view.sceneFPSField.stringValue == "97" && view.sceneFPSControl.integerValue == 97
            && !view.sceneFPSEffectiveLabel.isHidden && view.sceneFPSEffectiveLabel.stringValue.contains("60")
        let cadence = SceneDaemonClient.shared
        let rateDraft = try draft("91", in: view.sceneFPSField)
        cadence.activeAnimationCadence = .init(requestedFPS: .init(rawValue: 97)!, effectiveFPS: 59.94)
        NotificationCenter.default.post(name: .sceneDaemonAnimationCadenceDidChange, object: cadence)
        pump()
        let displayRate = 59.94.formatted(.number.precision(.fractionLength(0...2)))
        checks["frame-rate-confirmed-fractional-readout-does-not-replace-field-draft"] =
            view.sceneFPSField.currentEditor() === rateDraft && rateDraft.string == "91"
                && view.sceneFPSEffectiveLabel.stringValue.contains(displayRate) && requests.requests == [97]
        rateDraft.insertText("97", replacementRange: NSRange(location: 0, length: rateDraft.string.utf16.count))
        window.makeFirstResponder(view.nextField); pump()
        for invalid in ["121", "9", "25.5", "", "97"] {
            _ = try draft(invalid, in: view.sceneFPSField)
            window.makeFirstResponder(view.nextField); pump()
            checks["frame-rate-does-not-send-invalid-or-unchanged-\(invalid)"] = requests.requests == [97]
                && view.sceneFPSField.stringValue == "97"
        }
        let slider = view.sceneFPSControl
        let arrow = String(NSEvent.SpecialKey.leftArrow.unicodeScalar)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: arrow,
            charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 123)!
        slider.keyDown(with: event)
        checks["frame-rate-native-arrow-applies-one-fps-step"] = requests.requests == [97, 96]
            && view.sceneFPSField.stringValue == "96" && slider.integerValue == 96
        func sliderMouseEvent(_ type: NSEvent.EventType, _ fraction: CGFloat) -> NSEvent {
            let location = slider.convert(NSPoint(x: slider.bounds.width * fraction, y: slider.bounds.midY), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        NSApp.postEvent(sliderMouseEvent(.leftMouseDown, 0.78), atStart: false)
        NSApp.postEvent(sliderMouseEvent(.leftMouseDragged, 0.48), atStart: false)
        NSApp.postEvent(sliderMouseEvent(.leftMouseDragged, 0.41), atStart: false)
        NSApp.postEvent(sliderMouseEvent(.leftMouseUp, 0.41), atStart: false)
        if let down = NSApp.nextEvent(matching: .leftMouseDown, until: Date().addingTimeInterval(0.5),
                                      inMode: .default, dequeue: true) {
            NSApp.sendEvent(down)
        }
        let dragObservation = "Drag requests=\(requests.requests) slider=\(slider.integerValue) effectiveHidden=\(view.sceneFPSEffectiveLabel.isHidden)\n"
        FileHandle.standardError.write(Data(dragObservation.utf8))
        checks["frame-rate-native-drag-sends-only-one-request-on-release"] = requests.requests.count == 3
            && slider.integerValue == requests.requests.last && (50...60).contains(slider.integerValue)
            && view.sceneFPSEffectiveLabel.isHidden
        view.refreshQualityControls()
        checks["manual-frame-rate-shows-custom"] = view.sceneQualityPresetPopup.indexOfSelectedItem == 0
        _ = try draft("88", in: view.sceneFPSField)
        view.sceneQualityPresetPopup.selectItem(at: view.sceneQualityPresetPopup.indexOfItem(withRepresentedObject: "medium"))
        _ = view.sceneQualityPresetPopup.sendAction(view.sceneQualityPresetPopup.action, to: view)
        window.makeFirstResponder(view.nextField); pump()
        checks["native-preset-replaces-unsubmitted-draft-and-refreshes-rows-in-one-write"] =
            requests.requests.count == 4 && requests.requests.last == 15
            && view.sceneFPSField.stringValue == "15"
            && view.sceneShadowsPopup.selectedItem?.representedObject as? String == "medium"
            && view.scenePostProcessingPopup.selectedItem?.representedObject as? String == "enabled"
            && view.sceneReflectionsSwitch.state == .on
        view.sceneAntiAliasingPopup.selectItem(at: view.sceneAntiAliasingPopup.indexOfItem(withRepresentedObject: "msaa4"))
        _ = view.sceneAntiAliasingPopup.sendAction(view.sceneAntiAliasingPopup.action, to: view)
        checks["native-aa-setting-persists-and-leaves-derived-preset"] =
            requests.requests.count == 5 && PlaybackQualityPreference.current.scene.antiAliasing == .msaa4
            && view.sceneQualityPresetPopup.indexOfSelectedItem == 0 && view.sceneFPSField.stringValue == "15"
        _ = try draft("88", in: view.sceneFPSField)
        let restore = NSButton()
        _ = restore.sendAction(NSSelectorFromString("restoreDefaultQuality"), to: view)
        window.makeFirstResponder(view.nextField); pump()
        checks["native-restore-quality-replaces-unsubmitted-draft-with-compatible-defaults"] =
            requests.requests.count == 6 && requests.requests.last == 60
            && PlaybackQualityPreference.current == .defaults
            && view.sceneQualityPresetPopup.indexOfSelectedItem == 0 && view.sceneFPSField.stringValue == "60"
            && view.sceneVolumeLightingPopup.selectedItem?.representedObject as? String == "enabled"
        checks["native-cold-preset-field-and-reset-apply-once-after-saving"] = coldEdits.count == 3
            && coldEdits[0].postProcessing == .enabled && coldEdits[0].shadows == .medium
            && coldEdits[1].antiAliasing == .msaa4 && coldEdits[2] == PlaybackQualityPreference.defaults.scene.preparationQuality
        view.sceneTextureQualityPopup.selectItem(at: view.sceneTextureQualityPopup.indexOfItem(withRepresentedObject: "auto"))
        _ = view.sceneTextureQualityPopup.sendAction(view.sceneTextureQualityPopup.action, to: view)
        view.refreshQualityControls()
        checks["native-texture-auto-keeps-original-rate-and-saved-choice"] =
            requests.requests.count == 7 && requests.requests.last == 60
            && PlaybackQualityPreference.current.scene.textures == .automatic
            && view.sceneTextureQualityPopup.selectedItem?.representedObject as? String == "auto"
        view.sceneQualityPresetPopup.selectItem(at: view.sceneQualityPresetPopup.indexOfItem(withRepresentedObject: "ultra"))
        _ = view.sceneQualityPresetPopup.sendAction(view.sceneQualityPresetPopup.action, to: view)
        checks["native-ultra-preset-selects-ultra-volume"] = requests.requests.count == 8
            && PlaybackQualityPreference.current.scene.volumeLighting == .ultra
            && view.sceneFPSField.stringValue == "30"
            && view.sceneVolumeLightingPopup.selectedItem?.representedObject as? String == "ultra"
        let volumePopup = view.sceneVolumeLightingPopup
        volumePopup.selectItem(at: volumePopup.indexOfItem(withRepresentedObject: "enabled"))
        _ = volumePopup.sendAction(volumePopup.action, to: view)
        checks["native-high-volume-preserves-rate-and-makes-ultra-preset-custom"] =
            requests.requests.count == 9 && requests.requests.last == 30
            && PlaybackQualityPreference.current.scene.volumeLighting == .enabled
            && view.sceneQualityPresetPopup.indexOfSelectedItem == 0
        volumePopup.selectItem(at: volumePopup.indexOfItem(withRepresentedObject: "ultra"))
        _ = volumePopup.sendAction(volumePopup.action, to: view)
        checks["native-ultra-volume-restores-derived-ultra-preset"] = requests.requests.count == 10
            && PlaybackQualityPreference.current.scene.volumeLighting == .ultra
            && view.sceneQualityPresetPopup.selectedItem?.representedObject as? String == "ultra"
        let post = view.scenePostProcessingPopup
        let hdrIndex = post.indexOfItem(withRepresentedObject: ScenePostProcessingMode.ultraDisplayHDR.rawValue)
        let hdrItem = post.item(at: hdrIndex)!
        let ordinaryUltraIndex = post.indexOfItem(withRepresentedObject: ScenePostProcessingMode.ultra.rawValue)
        var hdr = PlaybackQualityPreference.current
        hdr.scene.postProcessing = .ultraDisplayHDR
        hdr.write(to: .standard)
        NSScreen.screens = [.init(maximumPotentialExtendedDynamicRangeColorComponentValue: 1)]
        view.refreshQualityControls()
        checks["native-sdr-menu-keeps-the-saved-hdr-item-selected-but-disabled"] = post.selectedItem == hdrItem
            && !hdrItem.isHidden && !hdrItem.isEnabled && hdrItem.title.contains("Unavailable")
            && view.sceneQualityPresetPopup.indexOfSelectedItem == 0
            && PlaybackQualityPreference.current == hdr && requests.requests.count == 10

        let displayClient = SceneDaemonClient.shared
        displayClient.multiDisplayEnabled = false
        NSScreen.screens.append(.init(maximumPotentialExtendedDynamicRangeColorComponentValue: 3))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        pump()
        checks["native-nontarget-hdr-screen-does-not-enable-display-hdr"] = post.selectedItem == hdrItem
            && !hdrItem.isHidden && !hdrItem.isEnabled && PlaybackQualityPreference.current == hdr

        NSScreen.screens.swapAt(0, 1)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        pump()
        checks["native-single-hdr-wallpaper-target-restores-the-saved-item"] = post.selectedItem == hdrItem
            && hdrItem.isEnabled && PlaybackQualityPreference.current == hdr

        NSScreen.screens.swapAt(0, 1)
        displayClient.multiDisplayEnabled = true
        view.refreshQualityControls()
        checks["native-configured-hdr-screen-restores-the-same-selectable-hdr-item"] = post.selectedItem == hdrItem
            && !hdrItem.isHidden && hdrItem.isEnabled && hdrItem.title == "Ultra (Display HDR)"
            && PlaybackQualityPreference.current == hdr && requests.requests.count == 10

        NSScreen.screens.removeLast()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        pump()
        post.selectItem(at: ordinaryUltraIndex)
        _ = post.sendAction(post.action, to: view)
        checks["native-explicit-ordinary-ultra-clears-display-hdr-and-hides-the-unavailable-item"] =
            post.indexOfSelectedItem == ordinaryUltraIndex && hdrItem.isHidden && !hdrItem.isEnabled
            && PlaybackQualityPreference.current.scene.postProcessing == .ultra
            && view.sceneQualityPresetPopup.selectedItem?.representedObject as? String == "ultra"
            && requests.requests.count == 11
        hdr.write(to: .standard)
        view.refreshQualityControls()
        _ = NSApp.sendAction(NSSelectorFromString("restoreDefaultQuality"), to: view, from: nil)
        checks["native-default-reset-clears-saved-hdr-under-sdr-capability"] =
            PlaybackQualityPreference.current == .defaults && post.indexOfSelectedItem == ordinaryUltraIndex
            && hdrItem.isHidden && !hdrItem.isEnabled && requests.requests.count == 12

        let button = view.reapplySceneQualityButton
        let standardTitle = button.title
        let daemon = SceneDaemonClient.shared
        let editsBeforeHotControls = coldEdits.count
        daemon.activePreparedRenderQuality = PlaybackQualityPreference.current.scene.preparationQuality
        NSScreen.screens.append(.init(maximumPotentialExtendedDynamicRangeColorComponentValue: 3))
        view.refreshQualityControls()
        post.selectItem(at: hdrIndex)
        _ = post.sendAction(post.action, to: view)
        view.commitSceneFrameRate(AnimationFrameRate(rawValue: 25))
        checks["native-hot-hdr-and-fps-do-not-show-a-pending-cold-quality-title"] =
            button.title == standardTitle && button.isHiddenOrHasHiddenAncestor && coldEdits.count == editsBeforeHotControls
            && PlaybackQualityPreference.current.scene.postProcessing == .ultraDisplayHDR
            && PlaybackQualityPreference.current.animationFrameRate.rawValue == 25
        let shadows = view.sceneShadowsPopup
        shadows.selectItem(at: shadows.indexOfItem(withRepresentedObject: SceneShadowQuality.low.rawValue))
        _ = shadows.sendAction(shadows.action, to: view)
        checks["native-saved-shadow-shows-the-pending-cold-quality-title"] =
            button.title != standardTitle && !button.isHiddenOrHasHiddenAncestor && PlaybackQualityPreference.current.scene.shadows == .low
            && coldEdits.count == editsBeforeHotControls + 1 && coldEdits.last?.shadows == .low
        _ = shadows.sendAction(shadows.action, to: view)
        checks["native-unchanged-cold-selection-does-not-apply-again"] = coldEdits.count == editsBeforeHotControls + 1
        daemon.activePreparedRenderQuality = PlaybackQualityPreference.current.scene.preparationQuality
        NotificationCenter.default.post(name: .sceneDaemonPreparedQualityDidChange, object: daemon)
        pump()
        checks["native-presented-quality-notification-clears-the-pending-title"] =
            button.title == standardTitle && button.isHiddenOrHasHiddenAncestor

        let selectedMSAA = view.sceneAntiAliasingPopup.indexOfSelectedItem
        let storedMSAA = PlaybackQualityPreference.current.scene.antiAliasing
        let savesBeforeRasterStatus = requests.requests.count
        let realDisplays = Set(AppKit.NSScreen.screens.compactMap {
            ($0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.uint32Value
        })
        let testDisplays = Array((101...200).lazy.map(UInt32.init).filter { !realDisplays.contains($0) }.prefix(3))
        daemon.activeRasterDisplayStatuses = [
            .init(displayID: testDisplays[0], samples: 1, fallback: .compatiblePathUnavailable),
            .init(displayID: testDisplays[1], samples: 4),
            .init(displayID: testDisplays[2], samples: nil),
        ]
        NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
        pump()
        checks["native-raster-readout-shows-active-counts-without-changing-the-request"] =
            !view.sceneRasterSamplesLabel.isHidden && view.sceneRasterSamplesLabel.stringValue.contains("1× / 4×")
            && view.sceneAntiAliasingPopup.indexOfSelectedItem == selectedMSAA
            && PlaybackQualityPreference.current.scene.antiAliasing == storedMSAA
            && requests.requests.count == savesBeforeRasterStatus
        let firstDisplays = view.sceneRasterSamplesLabel.toolTip ?? ""
        checks["native-raster-displays-show-identity-unknown-and-fallback"] =
            firstDisplays.contains("Display \(testDisplays[0].formatted()): 1× – Single-sample render path")
            && firstDisplays.contains("Display \(testDisplays[1].formatted()): 4×")
            && firstDisplays.contains("Display \(testDisplays[2].formatted()): Awaiting render result")
        daemon.activeRasterDisplayStatuses = [
            .init(displayID: testDisplays[0], samples: 4),
            .init(displayID: testDisplays[1], samples: 1, fallback: .preparationFailed),
        ]
        NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
        pump()
        let swapped = view.sceneRasterSamplesLabel.toolTip ?? ""
        checks["native-raster-screens-update-even-when-overall-counts-match"] =
            swapped.contains("Display \(testDisplays[0].formatted()): 4×")
            && swapped.contains("Display \(testDisplays[1].formatted()): 1× – MSAA preparation failed")
        daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 1, fallback: .deviceUnsupported)]
        var previous = PlaybackQualityPreference.current.scene
        previous.antiAliasing = storedMSAA == .msaa4 ? .msaa2 : .msaa4
        daemon.activePreparedRenderQuality = previous
        NotificationCenter.default.post(name: .sceneDaemonPreparedQualityDidChange, object: daemon)
        pump()
        checks["native-raster-fallback-maps-to-the-previous-active-quality"] =
            view.sceneRasterSamplesLabel.stringValue.contains("Previous setting in use: 1×")
            && (view.sceneRasterSamplesLabel.toolTip ?? "").contains("Device limit for requested MSAA")
            && view.sceneAntiAliasingPopup.indexOfSelectedItem == selectedMSAA
            && requests.requests.count == savesBeforeRasterStatus
        daemon.activeRasterDisplayStatuses = []
        NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
        pump()
        checks["native-raster-readout-clears-on-empty-active-state"] = view.sceneRasterSamplesLabel.isHidden

        shadows.selectItem(at: shadows.indexOfItem(withRepresentedObject: SceneShadowQuality.adaptive.rawValue))
        _ = shadows.sendAction(shadows.action, to: view)
        daemon.activePreparedRenderQuality = PlaybackQualityPreference.current.scene.preparationQuality
        let savesBeforeShadowStatus = requests.requests.count
        let shadowLabel = view.sceneShadowUseLabel
        let extent = "\(2048.formatted()) × \(2048.formatted())"
        let smallerExtent = "\(1024.formatted()) × \(1024.formatted())"
        let usedMaps: SceneShadowUse = .active([
            .init(family: .directional, face: 2048, limit: .receiverExtent),
            .init(family: .point, face: 1024, limit: .lightFamily),
            .init(family: .spot, face: nil),
        ])
        daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 1, shadow: usedMaps)]
        NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
        pump()
        let confirmed = shadowLabel.stringValue
        checks["native-shadow-readout-shows-confirmed-maps-with-per-light-reasons"] =
            !shadowLabel.isHidden && confirmed.contains("Directional: \(extent) – Receiver target size limit")
            && confirmed.contains("Point (each face): \(smallerExtent) – Light type limit")
            && confirmed.contains("Spotlight: Unavailable")
            && PlaybackQualityPreference.current.scene.shadows == .adaptive
            && requests.requests.count == savesBeforeShadowStatus
        let shadowRow = view.shadowRow
        shadowRow.frame = NSRect(x: 0, y: 0, width: 460, height: 130)
        shadowRow.layoutSubtreeIfNeeded()
        let readoutFrame = shadowRow.convert(shadowLabel.bounds, from: shadowLabel)
        let popupFrame = shadowRow.convert(shadows.bounds, from: shadows)
        checks["native-shadow-readout-wraps-without-covering-the-popup"] =
            shadowRow.bounds.contains(readoutFrame) && readoutFrame.height > 16 && readoutFrame.maxX < popupFrame.minX

        daemon.activeRasterDisplayStatuses = [
            .init(displayID: testDisplays[0], samples: 1, shadow: usedMaps),
            .init(displayID: testDisplays[1], samples: 1, shadow: .noReceiver),
            .init(displayID: testDisplays[2], samples: nil),
        ]
        NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
        pump()
        let shadowScreens = shadowLabel.toolTip ?? ""
        checks["native-shadow-readout-distinguishes-display-results"] =
            shadowLabel.stringValue == "Varies by display"
            && shadowScreens.contains("Display \(testDisplays[0].formatted()): Directional: \(extent)")
            && shadowScreens.contains("Display \(testDisplays[1].formatted()): No applicable shadows")
            && shadowScreens.contains("Display \(testDisplays[2].formatted()): Awaiting render result")

        let inactiveShadows: [(SceneShadowUse, String)] = [
            (.noReceiver, "No applicable shadows"), (.unavailable, "Shadow maps unavailable"),
        ]
        for (use, title) in inactiveShadows {
            daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 1, shadow: use)]
            NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
            pump()
            checks["native-shadow-readout-\(title)"] = shadowLabel.stringValue == title
        }

        daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 1,
            shadow: .active([.init(family: .directional, face: 1024, limit: .reduced)]))]
        NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
        pump()
        let reduced = "Directional: \(smallerExtent) – Reduced resolution"
        checks["native-shadow-readout-shows-reduced-resolution"] = shadowLabel.stringValue == reduced

        shadows.selectItem(at: shadows.indexOfItem(withRepresentedObject: SceneShadowQuality.disabled.rawValue))
        _ = shadows.sendAction(shadows.action, to: view)
        checks["native-shadow-edit-retains-the-actual-previous-result"] =
            shadowLabel.stringValue == "Previous setting in use: \(reduced)"
            && PlaybackQualityPreference.current.scene.shadows == .disabled
            && requests.requests.count == savesBeforeShadowStatus + 1

        daemon.activePreparedRenderQuality = PlaybackQualityPreference.current.scene.preparationQuality
        daemon.activeRasterDisplayStatuses = []
        NotificationCenter.default.post(name: .sceneDaemonPreparedQualityDidChange, object: daemon)
        pump()
        checks["native-shadow-readout-awaits-the-new-output"] =
            !shadowLabel.isHidden && shadowLabel.toolTip == nil && shadowLabel.stringValue == "Awaiting render result"
        daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 1, shadow: .disabled)]
        NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
        pump()
        checks["native-shadow-readout-shows-confirmed-disabled"] = shadowLabel.stringValue == "Disabled"

        daemon.activeRasterDisplayStatuses = []
        daemon.activePreparedRenderQuality = nil
        NotificationCenter.default.post(name: .sceneDaemonRasterSamplesDidChange, object: daemon)
        pump()
        checks["native-shadow-readout-clears-on-stop"] = shadowLabel.isHidden && shadowLabel.toolTip == nil

        let postLabel = view.scenePostProcessingUseLabel
        daemon.activePreparedRenderQuality = .init(postProcessing: .ultra)
        let standardUse = ScenePostProcessingUse(hdrWorkingSpace: false, bloom: .standard, display: .sdr)
        daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 1, postProcessing: standardUse)]
        view.refreshSceneRenderReadouts(.init(postProcessing: .ultraDisplayHDR))
        checks["native-post-sdr-acknowledges-equivalent-hot-request"] = !postLabel.isHidden
            && postLabel.stringValue == "SDR working space · Standard Bloom · Scene has no HDR output"
        view.refreshSceneRenderReadouts(.init(postProcessing: .disabled))
        checks["native-post-cold-edit-preserves-previous-result"] =
            postLabel.stringValue == "Previous setting in use: SDR working space · Standard Bloom · SDR output"

        daemon.activeRasterDisplayStatuses = [
            .init(displayID: testDisplays[0], samples: 1, postProcessing: .init(
                hdrWorkingSpace: true, bloom: .hdr, display: .edr)),
            .init(displayID: testDisplays[1], samples: 1, postProcessing: .init(
                hdrWorkingSpace: true, bloom: .hdr, display: .targetUnavailable))
        ]
        view.refreshSceneRenderReadouts(.init(postProcessing: .ultraDisplayHDR))
        checks["native-post-displays-separate-output-limits"] = postLabel.stringValue == "Varies by display"
            && postLabel.toolTip?.contains("HDR display output") == true
            && postLabel.toolTip?.contains("display has no HDR support") == true
        daemon.activePreparedRenderQuality = nil
        daemon.activeRasterDisplayStatuses = []
        view.refreshSceneRenderReadouts()
        checks["native-post-clears-on-stop"] = postLabel.isHidden && postLabel.toolTip == nil

        daemon.activePreparedRenderQuality = .init(volumeLighting: .ultra)
        let volumeLabel = view.sceneVolumeUseLabel
        let volumes: [(SceneVolumeUse, String)] = [
            (.disabled, "Disabled"),
            (.rendered(.init()), "No volumetric lighting drawn"),
            (.rendered(.init(spot: true)), "Spotlight cone"),
            (.rendered(.init(point: .analytic)), "Analytic point volume"),
            (.rendered(.init(point: .fourPoint)), "Four-point volume (reduced order)"),
            (.rendered(.init(point: .sixPoint, spot: true)), "Six-point volume / Spotlight cone"),
            (.rendered(.init(point: .unavailable, spot: true)), "Point volume unavailable / Spotlight cone"),
        ]
        for (use, title) in volumes {
            daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 4, volume: use)]
            view.refreshSceneRenderReadouts(.init(volumeLighting: .ultra))
            checks["native-rendered-volume-\(title)"] = volumeLabel.stringValue == title && !volumeLabel.isHidden
        }
        volumePopup.selectItem(at: volumePopup.indexOfItem(withRepresentedObject: SceneVolumeLightingQuality.disabled.rawValue))
        _ = volumePopup.sendAction(volumePopup.action, to: view)
        checks["native-volume-pending-keeps-the-actual-previous-result"] =
            PlaybackQualityPreference.current.scene.volumeLighting == .disabled
            && volumeLabel.stringValue == "Previous setting in use: Point volume unavailable / Spotlight cone"
        daemon.activePreparedRenderQuality = nil
        daemon.activeRasterDisplayStatuses = []
        view.refreshSceneRenderReadouts()
        checks["native-volume-readout-clears-on-stop"] = volumeLabel.isHidden && volumeLabel.toolTip == nil

        let textureLabel = view.sceneTextureUseLabel
        daemon.activePreparedRenderQuality = .init(textures: .full)
        daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 1, textures: .init())]
        view.refreshSceneRenderReadouts(.init(textures: .full))
        checks["native-texture-observed-empty-is-distinct-from-waiting"] =
            !textureLabel.isHidden && textureLabel.stringValue == "No ordinary texture observed"

        let texturePopup = view.sceneTextureQualityPopup
        texturePopup.selectItem(at: texturePopup.indexOfItem(withRepresentedObject: SceneTextureQuality.performance.rawValue))
        _ = texturePopup.sendAction(texturePopup.action, to: view)
        checks["native-texture-edit-keeps-previous-actual-receipt"] =
            textureLabel.stringValue == "Previous setting in use: No ordinary texture observed"
            && PlaybackQualityPreference.current.scene.textures == .performance

        daemon.activePreparedRenderQuality = .init(textures: .performance)
        daemon.activeRasterDisplayStatuses = [.init(displayID: testDisplays[0], samples: 1)]
        view.refreshSceneRenderReadouts()
        checks["native-texture-new-request-awaits-its-own-receipt"] =
            textureLabel.stringValue == "Awaiting render result"
        let smaller: SceneTextureUse.Binding = .init(width: 1632, height: 1105, baseMip: 2, mipCount: 2, reason: .authoredMip)
        let original: SceneTextureUse.Binding = .init(width: 4448, height: 1824, baseMip: 0, mipCount: 1, reason: .preservedPixels)
        daemon.activeRasterDisplayStatuses = [
            .init(displayID: testDisplays[0], samples: 1, textures: .init(reduced: smaller, retained: original)),
            .init(displayID: testDisplays[1], samples: nil),
        ]
        view.refreshSceneRenderReadouts()
        let textureTip = textureLabel.toolTip ?? ""
        checks["native-texture-readout-uses-per-display-actual-mip-tail-and-reason"] =
            textureLabel.stringValue == "Varies by display"
            && textureTip.contains("\(1632.formatted()) × \(1105.formatted()) · Base mip 2 · Mip levels 2 – Smaller authored mip")
            && textureTip.contains("\(4448.formatted()) × \(1824.formatted()) · Base mip 0 · Mip levels 1 – Original sampling kept")
            && textureTip.contains("Display \(testDisplays[1].formatted()): Awaiting render result")
        daemon.activePreparedRenderQuality = nil
        daemon.activeRasterDisplayStatuses = []
        view.refreshSceneRenderReadouts()
        checks["native-texture-readout-clears-on-stop"] = textureLabel.isHidden && textureLabel.toolTip == nil

        let locale = UserDefaults.standard.string(forKey: "AppleLocale")
        let separator = locale == "de_DE" ? "," : "."
        checks["playback-rate-process-uses-requested-region"] =
            Locale.current.identifier == locale && Locale.current.decimalSeparator == separator
        let rateSlider = view.playbackRateSlider
        let rateLabel = view.playbackRateValueLabel
        dependency.settings.playbackRateEnabled = true
        let expectedReads = [(0.25, "0.25"), (1, "1"), (1.25, "1.25"), (1.35, "1.35"), (1.95, "1.95"), (2, "2")]
        for (value, decimal) in expectedReads {
            dependency.settings.playbackRate = value
            view.refreshFromState()
            let expected = decimal.replacingOccurrences(of: ".", with: separator) + "×"
            checks["playback-rate-native-readback-\(decimal)"] = rateLabel.stringValue == expected
                && rateSlider.doubleValue == value && dependency.settings.playbackRate == value
        }
        dependency.settings.playbackRate = 1.237
        view.refreshFromState()
        checks["playback-rate-rounds-only-readout-for-an-existing-non-slider-value"] =
            rateLabel.stringValue == "1\(separator)24×" && rateSlider.doubleValue == 1.237
            && dependency.settings.playbackRate == 1.237
        rateSlider.doubleValue = 1.24
        let submitted = rateSlider.sendAction(rateSlider.action, to: rateSlider.target)
        checks["playback-rate-native-drag-saves-and-displays-the-same-step"] = submitted
            && rateLabel.stringValue == "1\(separator)25×" && dependency.settings.playbackRate == 1.25
        view.playbackRateSwitch.state = .off
        _ = view.playbackRateSwitch.sendAction(view.playbackRateSwitch.action, to: view.playbackRateSwitch.target)
        checks["playback-rate-native-disable-keeps-existing-reset-and-hidden-controls"] =
            !dependency.settings.playbackRateEnabled && dependency.settings.playbackRate == 1
            && rateSlider.isHidden && rateLabel.isHidden
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
