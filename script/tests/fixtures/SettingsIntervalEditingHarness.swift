import AppKit
import Combine

enum TimeUnit: String, CaseIterable { case seconds = "秒", minutes = "分钟" }
struct WallpaperSettings {
    var loopPlayback = true, randomPlayback = false, sequentialPlayback = false, autoSwitchEnabled = false
    var randomInterval = 30
    var timeUnit = TimeUnit.seconds
}
struct PersonalSettingsExportSummary {}
struct PersonalSettingsImportSummary {}
enum PersonalSettingsError: Error { case recoveryRequired(String) }
enum SceneHDRDisplayPreference { static let isEnabled = false }
enum SceneMediaSourcePreference { static let isEnabled = false }
extension Notification.Name {
    static let playbackMuteStateDidChange = Self("fixture.mute")
    static let wallpaperManagerLoginItemSyncFailed = Self("fixture.login-item")
}

@MainActor final class AppKitSettingsContainerView: NSView, NSTextFieldDelegate {
    let dependency: AppSettingsPanelDependency
    var isUpdatingUI = false
    var cancellables = Set<AnyCancellable>()
    var muteStateObserver: NSObjectProtocol?, loginItemSyncFailureObserver: NSObjectProtocol?
    let sceneHDRDisplaySwitch = NSSwitch(), sceneMediaInfoSwitch = NSSwitch()
    let loopSwitch = NSSwitch(), randomSwitch = NSSwitch(), sequentialSwitch = NSSwitch(), autoSwitchSwitch = NSSwitch()
    let intervalField = NSTextField(frame: .init(x: 20, y: 70, width: 160, height: 28))
    let timeUnitPopup = NSPopUpButton()
    var intervalRowView: NSView? = NSView(), autoSwitchRowView: NSView? = NSView()
    let nextField = NSTextField(frame: .init(x: 20, y: 20, width: 160, height: 28))
    init(_ dependency: AppSettingsPanelDependency) {
        self.dependency = dependency
        super.init(frame: .init(x: 0, y: 0, width: 360, height: 160))
        intervalField.delegate = self
        addSubview(intervalField); addSubview(nextField)
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
    func presentLoginItemSyncFailure(_ note: Notification) {}
    // ACTUAL_INTERVAL_REFRESH
    // ACTUAL_SETTINGS_OBSERVER
    // ACTUAL_INTERVAL_COMMIT
    // ACTUAL_TIME_UNIT_SELECTION
}

@main struct SettingsIntervalEditingHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var settings = WallpaperSettings()
        settings.loopPlayback = false; settings.sequentialPlayback = true; settings.autoSwitchEnabled = true
        var timerRefreshes = 0
        var actions = AppSettingsActions()
        actions.refreshAutoSwitchTimerIfNeeded = { timerRefreshes += 1 }
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
        func draft(_ text: String) throws -> NSTextView {
            view.intervalField.selectText(nil)
            guard let editor = view.intervalField.currentEditor() as? NSTextView, editor.isFieldEditor,
                  window.firstResponder === editor, window.fieldEditor(false, for: view.intervalField) === editor else {
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
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
