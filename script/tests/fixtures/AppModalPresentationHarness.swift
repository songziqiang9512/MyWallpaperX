import AppKit

@MainActor enum MainWindowCoordinator {
    static var host: NSWindow?
    static func mainWindow() -> NSWindow? { host }
}
@MainActor private final class AlertHelpLeaf: NSObject, NSAlertDelegate {
    var calls = 0
    func alertShowHelp(_ alert: NSAlert) -> Bool { calls += 1; return true }
}
@MainActor private final class ModalObservation { var wasVisible = false }

@MainActor private final class AlertCloseObservation: NSObject {
    private weak var host: NSWindow?
    private weak var panel: NSWindow?
    private var notifications: [String] = []

    init(host: NSWindow, panel: NSWindow) {
        self.host = host; self.panel = panel
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(willClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }

    func stop() { NotificationCenter.default.removeObserver(self) }

    @objc private func willClose(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        if window === host { notifications.append("host") }
        else if window === panel { notifications.append("panel") }
        else { return }
        write("willClose=\(notifications.last!)")
    }

    func trace(_ phase: String, responses: [NSApplication.ModalResponse]) {
        let closeButton = panel?.standardWindowButton(.closeButton)
        let delegate = panel?.delegate
        let delegateName = delegate.map { String(describing: type(of: $0)) } ?? "nil"
        let values = [
            "phase=\(phase)", "responses=\(responses.map(\.rawValue))", "willClose=\(notifications)",
            "host=\(describe(host))", "panel=\(describe(panel))",
            "host.attached=\(number(host?.attachedSheet))", "host.parent=\(number(host?.sheetParent))",
            "panel.attached=\(number(panel?.attachedSheet))", "panel.parent=\(number(panel?.sheetParent))",
            "panel.delegate=\(delegateName)",
            "panel.shouldCloseSelector=\(delegate?.responds(to: NSSelectorFromString("windowShouldClose:")) == true)",
            "panel.style=\(panel?.styleMask.rawValue ?? 0)",
            "closeButton.enabled=\(String(describing: closeButton?.isEnabled))",
            "closeButton.hidden=\(String(describing: closeButton?.isHidden))",
            "closeButton.window=\(number(closeButton?.window))",
            "app.modal=\(number(NSApp.modalWindow))", "app.key=\(number(NSApp.keyWindow))"
        ]
        write(values.joined(separator: " "))
    }

    private func number(_ window: NSWindow?) -> String { window.map { String($0.windowNumber) } ?? "nil" }
    private func describe(_ window: NSWindow?) -> String {
        guard let window else { return "nil" }
        return "\(window.windowNumber)(visible=\(window.isVisible),sheet=\(window.isSheet),key=\(window.isKeyWindow))"
    }
    private func write(_ value: String) {
        FileHandle.standardError.write(Data(("AppModalClose \(value)\n").utf8))
    }
}

@main enum AppModalPresentationHarness {
    @MainActor static func descendants<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
        ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { descendants($0, type) }
    }
    @MainActor static func wait(_ reason: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        guard condition() else { throw NSError(domain: "AppModalFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
    }
    @MainActor static func main() {
        initializeNativeAppHarness()
        Task { @MainActor in
            do { try await run() } catch { fatalError("App modal fixture: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        let host = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 650),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        MainWindowCoordinator.host = host
        host.makeKeyAndOrderFront(nil); NSApp.activate()
        defer { host.orderOut(nil); host.close(); MainWindowCoordinator.host = nil }
        try await wait("main host not key") { host.isKeyWindow && NSApp.isActive }
        var checks: [String: Bool] = [:]
        let draft = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        draft.isReleasedWhenClosed = false
        draft.contentView = WallpaperLibrarySheetSurface()
        precondition(WallpaperLibrarySheetPresentation.present(draft, in: host))
        try await wait("real child draft not key") { draft.isKeyWindow }
        var draftResponses: [NSApplication.ModalResponse] = []
        let draftAlert = makeAppAlert(title: "上层草稿确认", buttons: ["继续", "取消"])
        let draftAlertPanel = presentAppAlert(draftAlert, in: host) { draftResponses.append($0) }
        try await wait("explicit main host did not route its alert to the current child") { draft.attachedSheet === draftAlertPanel && draftAlertPanel.isVisible }
        checks["explicit-main-host-alert-follows-the-real-child-modal-and-keeps-background-input-blocked"] = host.attachedSheet == nil
            && draft.parent === host && draftAlertPanel.sheetParent === draft
            && !WallpaperLibrarySheetPresentation.permitsInput(in: host) && !WallpaperLibrarySheetPresentation.permitsInput(in: draft)
        draftAlert.buttons[1].performClick(nil)
        try await wait("child draft alert did not finish") { draftResponses.count == 1 && draft.attachedSheet == nil }
        WallpaperLibrarySheetPresentation.dismiss(draft)
        checks["child-modal-alert-cancel-keeps-one-original-response-and-leaves-no-floating-descendants"] = draftResponses == [.alertSecondButtonReturn]
            && !draft.isVisible && !draftAlertPanel.isVisible && draft.parent == nil && WallpaperLibrarySheetPresentation.permitsInput(in: host)
        host.makeKeyAndOrderFront(nil)
        try await wait("main host did not resume after child alert") { host.isKeyWindow }
        let checkbox = NSButton(checkboxWithTitle: "同时删除源文件", target: nil, action: nil)
        checkbox.state = .off
        let longMessage = Array(repeating: "完整失败说明与可复制明细，原始文件未被伪装成已恢复。", count: 32).joined(separator: "\n")
        let alert = makeAppAlert(title: "删除所选项目？", message: longMessage, style: .warning,
            buttons: ["删除", "取消", "其他操作"], accessoryView: checkbox)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "仅本测试的原有 suppression 能力"
        let help = AlertHelpLeaf(); alert.delegate = help; alert.showsHelp = true
        var responses: [NSApplication.ModalResponse] = []
        let panel = presentAppAlert(alert, in: host) { responses.append($0) }
        try await wait("real centered alert not key") { panel.isKeyWindow && host.attachedSheet === panel }
        panel.contentView?.layoutSubtreeIfNeeded()
        let content = panel.contentView!
        let label = descendants(content, NSTextField.self).first { $0.stringValue == alert.messageText }!
        let icon = descendants(content, NSImageView.self).first!
        let iconFrame = icon.convert(icon.bounds, to: content)
        let checkboxFrame = checkbox.convert(checkbox.bounds, to: content)
        checks["real-alert-icon-title-and-checkbox-share-one-content-axis"] = abs(iconFrame.midX - content.bounds.midX) <= 0.5
            && abs(checkboxFrame.midX - content.bounds.midX) <= 0.5 && label.alignment == .center
            && label.font?.pointSize == 17 && abs(iconFrame.width - 48) <= 0.5 && abs(iconFrame.height - 48) <= 0.5
        let message = descendants(content, NSTextView.self).first { $0.string == longMessage }!
        checks["full-long-message-remains-readable-copyable-and-bounded-in-native-scroll"] = message.isSelectable && !message.isEditable
            && message.enclosingScrollView!.frame.height <= 160.5 && message.frame.height > message.enclosingScrollView!.frame.height
        checks["original-accessory-default-off-suppression-and-help-controls-remain-real"] = !checkbox.isHidden && checkbox.state == .off
            && alert.suppressionButton?.window === panel && panel.defaultButtonCell === alert.buttons[0].cell
        descendants(content, NSButton.self).first { $0.bezelStyle == .helpButton }!.performClick(nil)
        checks["original-alert-help-delegate-keeps-its-one-call-contract"] = help.calls == 1 && responses.isEmpty
        checkbox.performClick(nil)
        alert.buttons[2].performClick(nil); alert.buttons[2].performClick(nil)
        try await wait("alert response did not settle") { host.attachedSheet == nil && responses.count == 1 }
        checks["original-response-index-accessory-state-and-exact-once-completion-survive-custom-layout"] = responses == [.alertThirdButtonReturn]
            && checkbox.state == .on && !panel.isVisible

        let editor = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        editor.isReleasedWhenClosed = false
        host.beginSheet(editor, completionHandler: { _ in })
        try await wait("parent native sheet not key") { editor.isKeyWindow }
        var nestedResponses: [NSApplication.ModalResponse] = []
        let nested = makeAppAlert(title: "嵌套确认", buttons: ["继续", "取消"])
        let child = presentAppAlert(nested, in: host) { nestedResponses.append($0) }
        try await wait("nested confirmation not on the top sheet") { editor.attachedSheet === child && child.isKeyWindow }
        checks["feedback-resolves-the-existing-top-sheet-instead-of-queueing-on-main"] = child.sheetParent === editor
            && host.attachedSheet === editor && appModalHostWindow() === child
        child.cancelOperation(nil)
        try await wait("nested cancel did not settle") { editor.attachedSheet == nil && nestedResponses.count == 1 }
        checks["nested-escape-cancels-once-without-dismissing-the-editor-parent"] = nestedResponses == [.alertSecondButtonReturn]
            && editor.isVisible && host.attachedSheet === editor
        host.endSheet(editor); editor.orderOut(nil)
        try await wait("parent sheet did not end") { host.attachedSheet == nil }

        for cancelParent in [false, true] {
            let label = cancelParent ? "held-parent-cancel" : "held-parent-button"
            let parentAlert = makeAppAlert(title: "父确认", buttons: ["继续", "取消"])
            var parentResponses: [NSApplication.ModalResponse] = []
            let parentPanel = presentAppAlert(parentAlert, in: host) { parentResponses.append($0) }
            try await wait("centered parent alert did not become key") { parentPanel.isKeyWindow && host.attachedSheet === parentPanel }
            let childAlert = makeAppAlert(title: "子确认", buttons: ["继续子操作", "取消"])
            var childResponses: [NSApplication.ModalResponse] = []
            let childPanel = presentAppAlert(childAlert, in: host) { childResponses.append($0) }
            try await wait("centered child alert did not become the real top sheet") {
                childPanel.isKeyWindow && parentPanel.attachedSheet === childPanel && childPanel.sheetParent === parentPanel
            }
            if cancelParent { parentPanel.cancelOperation(nil) }
            else { parentAlert.buttons[0].performClick(nil) }
            try await Task.sleep(for: .milliseconds(25))
            checks[label + "-cannot-end-a-centered-parent-while-its-centered-child-owns-input"] = parentResponses.isEmpty && childResponses.isEmpty
                && parentPanel.isVisible && childPanel.isVisible && host.attachedSheet === parentPanel
                && parentPanel.attachedSheet === childPanel && childPanel.sheetParent === parentPanel
            childPanel.cancelOperation(nil)
            try await wait("centered child cancellation did not settle") { childResponses.count == 1 && !childPanel.isVisible }
            let parentStillAwaitingResponse = parentResponses.isEmpty && parentPanel.isVisible
                && host.attachedSheet === parentPanel && parentPanel.attachedSheet == nil
            checks[label + "-child-cancel-keeps-the-centered-parent-awaiting-its-own-response"] = parentStillAwaitingResponse
                && childResponses == [.alertSecondButtonReturn]
            if parentStillAwaitingResponse {
                parentAlert.buttons[0].performClick(nil)
                try await wait("centered parent did not accept its own response after child cancellation") {
                    parentResponses.count == 1 && !parentPanel.isVisible && host.attachedSheet == nil
                }
            }
            parentAlert.buttons[0].performClick(nil); parentPanel.cancelOperation(nil)
            try await Task.sleep(for: .milliseconds(25))
            checks[label + "-parent-responds-exactly-once-after-the-child-finishes"] = parentStillAwaitingResponse
                && parentResponses == [.alertFirstButtonReturn] && childResponses == [.alertSecondButtonReturn]
                && host.attachedSheet == nil && !parentPanel.isVisible && !childPanel.isVisible
        }

        let escapeLayouts: [(String, [String], Bool, NSApplication.ModalResponse)] = [
            ("web-keep-or-delete", ["保留", "删除样本"], false, .cancel),
            ("web-cancel-or-download", ["取消", "下载依赖项"], false, .alertFirstButtonReturn),
            ("third-position-cancel", ["保存", "其他操作", "取消"], false, .alertThirdButtonReturn),
            ("explicit-third-button-escape", ["继续", "其他操作", "返回原处"], true, .alertThirdButtonReturn)
        ]
        for (label, titles, explicitEscape, expected) in escapeLayouts {
            let ordered = makeAppAlert(title: label, buttons: titles)
            let nativeKeys = ordered.buttons.map(\.keyEquivalent)
            if explicitEscape { ordered.buttons[2].keyEquivalent = "\u{1b}" }
            let inputKeys = ordered.buttons.map(\.keyEquivalent)
            // These expected business responses are independent constants.
            // Native English Cancel installs Esc; this App's Chinese cancel
            // intent must not be mistaken for native automatic key assignment.
            var orderedResponses: [NSApplication.ModalResponse] = [], sourceEffects = 0
            let orderedPanel = presentAppAlert(ordered, in: host) { response in
                orderedResponses.append(response)
                // The two real Web consumers perform deletion/download only
                // for the second response. Cancellation must never admit them.
                if label.hasPrefix("web-"), response == .alertSecondButtonReturn { sourceEffects += 1 }
            }
            try await wait("ordered cancellation alert did not become key") { orderedPanel.isKeyWindow }
            let diagnostic: [String: Any] = ["case": label,
                "nativeKeyUTF16": nativeKeys.map { $0.utf16.map(Int.init) },
                "inputKeyUTF16": inputKeys.map { $0.utf16.map(Int.init) },
                "presentedKeyUTF16": ordered.buttons.map { $0.keyEquivalent.utf16.map(Int.init) },
                "expectedCancellation": expected.rawValue]
            FileHandle.standardError.write(Data(("CenteredAlertEscape " + String(decoding:
                try JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]), as: UTF8.self) + "\n").utf8))
            checks[label + "-preserves-the-callers-native-and-explicit-button-key-equivalents"] = ordered.buttons.map(\.keyEquivalent) == inputKeys
            orderedPanel.cancelOperation(nil)
            try await wait("ordered cancellation did not settle") { orderedResponses.count == 1 && host.attachedSheet == nil }
            orderedPanel.cancelOperation(nil)
            try await Task.sleep(for: .milliseconds(25))
            checks[label + "-cancel-keeps-the-original-Escape-response-without-admitting-other-source-actions"] = orderedResponses == [expected]
                && sourceEffects == 0 && !orderedPanel.isVisible && orderedPanel.sheetParent == nil
        }

        let settings = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 500, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false; settings.makeKeyAndOrderFront(nil)
        var settingsResponses: [NSApplication.ModalResponse] = []
        let settingsAlert = makeAppAlert(title: "设置反馈")
        let settingsPanel = presentAppAlert(settingsAlert, in: settings) { settingsResponses.append($0) }
        let settingsClose = AlertCloseObservation(host: settings, panel: settingsPanel)
        defer { settingsClose.stop() }
        try await wait("settings feedback attached to the wrong host") { settingsPanel.isKeyWindow }
        checks["settings-feedback-retains-the-explicit-settings-host"] = settingsPanel.sheetParent === settings && host.attachedSheet == nil
        settingsClose.trace("before-panel-performClose", responses: settingsResponses)
        settingsPanel.performClose(nil)
        settingsClose.trace("after-panel-performClose", responses: settingsResponses)
        try await Task.sleep(for: .milliseconds(25))
        checks["native-sheet-without-a-close-button-keeps-performClose-as-a-noop"] = settingsPanel.standardWindowButton(.closeButton) == nil
            && settingsResponses.isEmpty && settingsPanel.isVisible && settingsPanel.isSheet
            && settings.attachedSheet === settingsPanel && settingsPanel.sheetParent === settings
        settingsClose.trace("before-panel-native-cancel", responses: settingsResponses)
        settingsPanel.cancelOperation(nil)
        settingsClose.trace("after-panel-native-cancel", responses: settingsResponses)
        do { try await wait("settings native sheet cancel did not settle") { settingsResponses.count == 1 } }
        catch { settingsClose.trace("failed-panel-native-cancel-wait", responses: settingsResponses); throw error }
        settingsClose.trace("settled-panel-native-cancel", responses: settingsResponses)
        checks["native-sheet-cancel-retains-single-button-response-and-exact-once-completion"] = settingsResponses == [.alertFirstButtonReturn]
            && settings.attachedSheet == nil && settingsPanel.sheetParent == nil && !settingsPanel.isVisible
        settingsClose.trace("before-settings-host-close", responses: settingsResponses)
        settings.orderOut(nil); settings.close()
        settingsClose.trace("after-settings-host-close", responses: settingsResponses)

        let field = NSTextField(string: "原附件值")
        let external = makeAppAlert(title: "可由来源取消", buttons: ["保存", "取消"], accessoryView: field)
        var externalResponses: [NSApplication.ModalResponse] = []
        weak var releasedOwner: AppCenteredAlertPresentation?
        var externalPanel: NSWindow!
        do {
            let owner = AppCenteredAlertPresentation(alert: external) { externalResponses.append($0) }
            releasedOwner = owner
            externalPanel = owner.window
            owner.beginSheet(in: host)
        }
        try await wait("external cancellation sheet not key") { externalPanel.isKeyWindow }
        field.stringValue = "取消前附件值"
        host.endSheet(externalPanel, returnCode: .cancel); externalPanel.orderOut(nil)
        try await wait("external endSheet did not finish/release its presentation") { externalResponses.count == 1 && releasedOwner == nil }
        checks["source-owned-external-end-sheet-preserves-cancel-accessory-and-releases-the-presenter"] = externalResponses == [.cancel]
            && field.stringValue == "取消前附件值" && !externalPanel.isVisible
        let closingHost = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 500, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        closingHost.isReleasedWhenClosed = false; closingHost.makeKeyAndOrderFront(nil)
        var closingResponses: [NSApplication.ModalResponse] = []
        let closingPanel = presentAppAlert(makeAppAlert(title: "父窗口关闭", buttons: ["继续", "取消"]), in: closingHost) { closingResponses.append($0) }
        let parentClose = AlertCloseObservation(host: closingHost, panel: closingPanel)
        defer { parentClose.stop() }
        try await wait("closing-host sheet never displayed") { closingPanel.isKeyWindow }
        parentClose.trace("before-host-close-with-sheet", responses: closingResponses)
        closingHost.close()
        parentClose.trace("after-host-close-with-sheet", responses: closingResponses)
        do { try await wait("parent close left feedback or its callback alive") { closingResponses.count == 1 && !closingPanel.isVisible } }
        catch { parentClose.trace("failed-host-close-wait", responses: closingResponses); throw error }
        parentClose.trace("settled-host-close-with-sheet", responses: closingResponses)
        checks["parent-window-close-cancels-native-feedback-once-without-a-floating-panel"] = closingResponses == [.cancel]
            && closingHost.attachedSheet == nil

        let startup = makeAppAlert(title: "启动失败", buttons: ["好"])
        let observation = ModalObservation()
        let startupClick = Timer(timeInterval: 0.01, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard let modal = NSApp.modalWindow else { preconditionFailure("app-modal session never entered") }
                observation.wasVisible = modal.isVisible
                startup.buttons[0].performClick(nil)
            }
        }
        RunLoop.main.add(startupClick, forMode: .modalPanel)
        let startupResponse = runAppAlert(startup)
        startupClick.invalidate()
        checks["no-host-startup-feedback-remains-blocking-app-modal-with-original-response"] = observation.wasVisible
            && startupResponse == .alertFirstButtonReturn && NSApp.modalWindow == nil
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
