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

@MainActor private final class NativeAlertTransitionProbe: NSObject {
    weak var host: NSWindow?
    weak var draft: NSWindow?
    weak var alert: NSWindow?
    private var phases: [String] = []

    init(host: NSWindow, draft: NSWindow) {
        self.host = host; self.draft = draft
        super.init()
        for name in [NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(sheetPhase(_:)), name: name, object: draft)
        }
    }
    func stop() { NotificationCenter.default.removeObserver(self) }
    @objc private func sheetPhase(_ note: Notification) {
        phases.append(note.name.rawValue)
        trace(note.name.rawValue)
    }
    func trace(_ phase: String) {
        func number(_ window: NSWindow?) -> String { window.map { String($0.windowNumber) } ?? "nil" }
        func state(_ window: NSWindow?) -> String {
            guard let window else { return "nil" }
            return "\(number(window))(visible=\(window.isVisible),key=\(window.isKeyWindow),sheet=\(window.isSheet),parent=\(number(window.parent)),sheetParent=\(number(window.sheetParent)),attached=\(number(window.attachedSheet)),permits=\(WallpaperLibrarySheetPresentation.permitsInput(in: window)))"
        }
        let value = "NativeAlertTransition phase=\(phase) phases=\(phases) active=\(NSApp.isActive) key=\(number(NSApp.keyWindow)) main=\(number(NSApp.mainWindow)) modal=\(number(NSApp.modalWindow)) host=\(state(host)) draft=\(state(draft)) alert=\(state(alert))\n"
        FileHandle.standardError.write(Data(value.utf8))
    }
}

@main enum AppModalPresentationHarness {
    @MainActor static func wait(_ reason: String, diagnostic: (() -> Void)? = nil, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        guard condition() else {
            diagnostic?()
            throw NSError(domain: "AppModalFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }
    @MainActor static func escape(in window: NSWindow) async throws {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53)!
        NSApp.postEvent(event, atStart: false)
        try await Task.sleep(for: .milliseconds(40))
    }
    @MainActor static func pressReturn(in window: NSWindow) async throws {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36)!
        NSApp.postEvent(event, atStart: false)
        try await Task.sleep(for: .milliseconds(40))
    }
    @MainActor static func traceKeys(_ alert: NSAlert, responses: [NSApplication.ModalResponse], phase: String) {
        let buttons = alert.buttons.map { "\($0.title):keys=\(Array($0.keyEquivalent.utf16)),enabled=\($0.isEnabled)" }.joined(separator: ";")
        let defaultIsFirst = alert.window.defaultButtonCell === alert.buttons.first?.cell
        FileHandle.standardError.write(Data("NativeAlertKeys phase=\(phase) defaultIsFirst=\(defaultIsFirst) key=\(alert.window.isKeyWindow) responses=\(responses) buttons=\(buttons)\n".utf8))
    }
    @MainActor static func accessibleHelpAction(in window: NSWindow) -> NSAccessibilityProtocol? {
        var visited: Set<ObjectIdentifier> = []
        var candidates: [NSAccessibilityProtocol] = []
        func visit(_ node: Any, path: String) {
            guard visited.insert(ObjectIdentifier(node as AnyObject)).inserted else { return }
            let element = node as? NSAccessibilityProtocol
            let button = node as? NSButton
            let role = element?.accessibilityRole()
            let texts = [element?.accessibilityLabel(), element?.accessibilityTitle(), element?.accessibilityHelp()].compactMap { $0 }
            let helpNames = ["帮助", "帮助按钮", "help", "help button"]
            let semanticHelp = role == .button && texts.contains { helpNames.contains($0.lowercased()) }
            let children = element?.accessibilityChildren() ?? []
            let description = "NativeAlertAX path=\(path) role=\(role?.rawValue ?? "nil") label=\(String(describing: element?.accessibilityLabel()).prefix(180)) title=\(String(describing: element?.accessibilityTitle()).prefix(180)) help=\(String(describing: element?.accessibilityHelp()).prefix(180)) bezel=\(String(describing: button?.bezelStyle.rawValue)) children=\(children.count) candidate=\(semanticHelp || button?.bezelStyle == .helpButton)\n"
            FileHandle.standardError.write(Data(description.utf8))
            if let element, semanticHelp || button?.bezelStyle == .helpButton { candidates.append(element) }
            for (index, child) in children.enumerated() { visit(child, path: "\(path).\(index)") }
        }
        // NSAlert owns its internal views. Observe only the public AX trees;
        // its content root can expose controls omitted by the window's tree.
        visit(window, path: "window")
        if let content = window.contentView { visit(content, path: "content") }
        FileHandle.standardError.write(Data("NativeAlertAX helpCandidates=\(candidates.count)\n".utf8))
        return candidates.count == 1 ? candidates[0] : nil
    }
    @MainActor static func click(_ button: NSButton) async throws {
        let window = button.window!
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        try await click(in: window, at: point)
    }
    @MainActor static func click(in window: NSWindow, at point: NSPoint) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(40))
    }
    @MainActor static func main() {
        initializeNativeAppHarness()
        Task { @MainActor in
            do { try await run() } catch {
                FileHandle.standardError.write(Data("App modal fixture failed: \(error)\n".utf8))
                exit(1)
            }
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
        host.center()
        host.makeKeyAndOrderFront(nil); NSApp.activate()
        defer { host.orderOut(nil); host.close(); MainWindowCoordinator.host = nil }
        try await wait("main host not key", diagnostic: {
            let screens = NSScreen.screens.map { "\($0.frame)/\($0.visibleFrame)" }
            let state = "NativeAlertHost active=\(NSApp.isActive) key=\(String(describing: NSApp.keyWindow)) "
                + "visible=\(host.isVisible) frame=\(host.frame) screens=\(screens)\n"
            FileHandle.standardError.write(Data(state.utf8))
        }) { host.isKeyWindow && NSApp.isActive }
        var checks: [String: Bool] = [:]
        let draft = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        draft.isReleasedWhenClosed = false
        draft.contentView = WallpaperPanelSurface()
        precondition(WallpaperLibrarySheetPresentation.present(draft, in: host))
        try await wait("real draft sheet not key") { draft.isKeyWindow }
        var draftResponses: [NSApplication.ModalResponse] = []
        let draftAlert = makeAppAlert(title: "上层草稿确认", buttons: ["继续", "取消"])
        let transition = NativeAlertTransitionProbe(host: host, draft: draft)
        defer { transition.stop() }
        let draftAlertPanel = presentAppAlert(draftAlert, in: host) {
            draftResponses.append($0)
            transition.trace("native-response-callback")
        }
        transition.alert = draftAlertPanel
        try await wait("explicit main host did not route its alert to the current sheet") { draft.attachedSheet === draftAlertPanel && draftAlertPanel.isVisible }
        checks["explicit-main-host-alert-follows-the-real-modal-sheet-and-keeps-background-input-blocked"] = host.attachedSheet === draft
            && draft.sheetParent === host && draftAlertPanel.sheetParent === draft && draftAlertPanel === draftAlert.window
            && !WallpaperLibrarySheetPresentation.permitsInput(in: host) && !WallpaperLibrarySheetPresentation.permitsInput(in: draft)
        try await escape(in: draftAlertPanel)
        transition.trace("after-Escape-turn")
        // The native response is not an assertion that its sheet animation and
        // key-window handoff have ended. Retire the draft only after those real
        // relations settle; keep the same bounded wait and no focus retries.
        try await wait("child draft alert did not finish", diagnostic: { transition.trace("failed-native-settlement") }) {
            draftResponses.count == 1 && draft.attachedSheet == nil && draftAlertPanel.sheetParent == nil
                && !draftAlertPanel.isVisible && draft.isKeyWindow
                && WallpaperLibrarySheetPresentation.permitsInput(in: draft)
        }
        transition.trace("before-draft-close")
        WallpaperLibrarySheetPresentation.dismiss(draft)
        transition.trace("after-draft-close")
        checks["modal-sheet-alert-cancel-keeps-one-original-response-and-leaves-no-floating-descendants"] = draftResponses == [.alertSecondButtonReturn]
            && !draft.isVisible && !draftAlertPanel.isVisible && draft.sheetParent == nil && WallpaperLibrarySheetPresentation.permitsInput(in: host)
        host.makeKeyAndOrderFront(nil)
        transition.trace("after-original-host-order")
        try await wait("main host did not resume after child alert", diagnostic: { transition.trace("failed-host-resume") }) { host.isKeyWindow }

        let shortRemoval = makeAppAlert(title: "移出资料库 1 项？",
            message: "移除资料库项目及最近使用记录，源文件和其他列表保留。勾选会删除源文件，无法撤销。",
            style: .warning, buttons: ["移除", "取消"])
        shortRemoval.showsSuppressionButton = true
        let removalCheckbox = shortRemoval.suppressionButton!
        removalCheckbox.title = "删除磁盘的源文件"
        removalCheckbox.state = .off
        removalCheckbox.sizeToFit()
        removalCheckbox.alignment = .left
        var shortResponses: [NSApplication.ModalResponse] = []
        let shortPanel = presentAppAlert(shortRemoval, in: host) { shortResponses.append($0) }
        try await wait("short removal confirmation not key") { shortPanel.isKeyWindow }
        let checkboxFrame = removalCheckbox.convert(removalCheckbox.bounds, to: shortPanel.contentView)
        var labels = shortPanel.contentView!.subviews, bodyFrame: NSRect?
        while let candidate = labels.popLast() {
            labels.append(contentsOf: candidate.subviews)
            if let text = candidate as? NSTextField, text.stringValue == shortRemoval.informativeText {
                bodyFrame = text.convert(text.bounds, to: shortPanel.contentView)
            }
        }
        checks["short-native-confirmation-shows-app-icon-and-left-aligned-default-off-source-option"] = shortRemoval.icon === NSApp.applicationIconImage
            && shortRemoval.icon.size.width > 0 && removalCheckbox.alignment == .left && removalCheckbox.state == .off
            && shortPanel.contentView!.bounds.contains(checkboxFrame) && shortRemoval.accessoryView == nil
            && bodyFrame.map { abs(checkboxFrame.minX - $0.minX) <= 2 } == true && shortPanel.frame.width < 352
            && shortRemoval.buttons.map(\.title) == ["移除", "取消"]
            && shortRemoval.informativeText.components(separatedBy: "。").filter { !$0.isEmpty }.count == 2
        try await escape(in: shortPanel)
        try await wait("short removal cancellation did not settle") { shortResponses == [.alertSecondButtonReturn] && host.attachedSheet == nil }
        checks["short-native-confirmation-cancellation-does-not-toggle-source-option"] = removalCheckbox.state == .off

        let checkbox = NSButton(checkboxWithTitle: "同时删除源文件", target: nil, action: nil)
        checkbox.state = .off
        checkbox.sizeToFit()
        let longMessage = Array(repeating: "完整失败说明与可复制明细，原始文件未被伪装成已恢复。", count: 32).joined(separator: "\n")
        let alert = makeAppAlert(title: "删除所选项目？", message: longMessage, style: .warning,
            buttons: ["删除", "取消", "其他操作"], accessoryView: checkbox)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "仅本测试的原有 suppression 能力"
        let help = AlertHelpLeaf(); alert.delegate = help; alert.showsHelp = true
        var responses: [NSApplication.ModalResponse] = []
        let panel = presentAppAlert(alert, in: host) { responses.append($0) }
        try await wait("system alert not key") { panel.isKeyWindow && host.attachedSheet === panel }
        checks["presentation-uses-the-original-system-alert-window-without-a-replacement-panel"] = panel === alert.window
            && ObjectIdentifier(type(of: panel)) == ObjectIdentifier(type(of: NSAlert().window))
        checks["native-alert-retains-full-title-message-style-and-original-accessory"] = alert.messageText == "删除所选项目？"
            && alert.informativeText == longMessage && alert.alertStyle == .warning && alert.accessoryView === checkbox
        checks["original-accessory-default-off-suppression-and-help-contracts-remain-native"] = checkbox.window === panel
            && checkbox.state == .off && !checkbox.isHidden && checkbox.bounds.width > 0 && checkbox.bounds.height > 0
            && alert.suppressionButton?.window === panel
            && alert.showsSuppressionButton && alert.showsHelp && alert.delegate === help
        guard let helpButton = accessibleHelpAction(in: panel) else {
            throw NSError(domain: "AppModalFixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "System help button is absent from the public accessibility tree"])
        }
        let helpFrame = helpButton.accessibilityFrame()
        try await click(in: panel, at: panel.convertPoint(fromScreen: NSPoint(x: helpFrame.midX, y: helpFrame.midY)))
        try await wait("native help action did not reach its original delegate") { help.calls == 1 }
        checks["original-help-delegate-receives-one-real-native-mouse-action"] = helpFrame.width > 0 && helpFrame.height > 0
            && help.calls == 1 && responses.isEmpty
        checkbox.performClick(nil)
        alert.buttons[2].performClick(nil)
        try await wait("alert response did not settle") { host.attachedSheet == nil && responses.count == 1 }
        try await Task.sleep(for: .milliseconds(40))
        checks["original-response-index-accessory-state-and-exact-once-completion-survive-native-layout"] = responses == [.alertThirdButtonReturn]
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
        try await escape(in: child)
        try await wait("nested cancel did not settle") { editor.attachedSheet == nil && nestedResponses.count == 1 }
        checks["nested-escape-cancels-once-without-dismissing-the-editor-parent"] = nestedResponses == [.alertSecondButtonReturn]
            && editor.isVisible && host.attachedSheet === editor
        host.endSheet(editor); editor.orderOut(nil)
        try await wait("parent sheet did not end") { host.attachedSheet == nil }

        let parentAlert = makeAppAlert(title: "父确认", buttons: ["保留", "删除样本"])
        var parentResponses: [NSApplication.ModalResponse] = []
        let parentPanel = presentAppAlert(parentAlert, in: host) { parentResponses.append($0) }
        try await wait("parent alert did not become key") { parentPanel.isKeyWindow && host.attachedSheet === parentPanel }
        let childAlert = makeAppAlert(title: "子确认", buttons: ["继续子操作", "取消"])
        var childResponses: [NSApplication.ModalResponse] = []
        let childPanel = presentAppAlert(childAlert, in: host) { childResponses.append($0) }
        try await wait("child alert did not become the real top sheet") { childPanel.isKeyWindow && parentPanel.attachedSheet === childPanel }
        try await click(parentAlert.buttons[0])
        checks["native-child-sheet-blocks-background-parent-mouse-input"] = parentResponses.isEmpty && childResponses.isEmpty
            && parentPanel.isVisible && childPanel.isVisible && host.attachedSheet === parentPanel
            && parentPanel.attachedSheet === childPanel && !WallpaperLibrarySheetPresentation.permitsInput(in: parentPanel)
        try await escape(in: childPanel)
        try await wait("child cancellation did not settle") { childResponses.count == 1 && !childPanel.isVisible }
        checks["child-cancel-keeps-the-native-parent-awaiting-its-own-response"] = parentResponses.isEmpty
            && parentPanel.isVisible && host.attachedSheet === parentPanel && parentPanel.attachedSheet == nil
            && childResponses == [.alertSecondButtonReturn]
        try await click(parentAlert.buttons[0])
        try await wait("parent did not accept its own response after child cancellation") { parentResponses.count == 1 && !parentPanel.isVisible }
        checks["native-parent-responds-exactly-once-after-the-child-finishes"] = parentResponses == [.alertFirstButtonReturn]
            && childResponses == [.alertSecondButtonReturn] && host.attachedSheet == nil

        let escapeLayouts: [(String, [String], Int)] = [
            ("web-keep-or-delete", ["保留", "删除样本"], 0),
            ("web-cancel-or-download", ["取消", "下载依赖项"], 0),
            ("third-position-cancel", ["保存", "其他操作", "取消"], 2),
            ("explicit-third-button-escape", ["继续", "其他操作", "返回原处"], 2),
            ("settings-open-or-later", ["打开系统设置", "稍后"], 1)
        ]
        for (label, titles, cancelIndex) in escapeLayouts {
            let ordered = makeAppAlert(title: label, buttons: titles)
            if label == "explicit-third-button-escape" { ordered.buttons[2].keyEquivalent = "\u{1b}" }
            var orderedResponses: [NSApplication.ModalResponse] = [], sourceEffects = 0
            let orderedPanel = presentAppAlert(ordered, in: host) { response in
                orderedResponses.append(response)
                if label.hasPrefix("web-"), response == .alertSecondButtonReturn { sourceEffects += 1 }
            }
            try await wait("ordered cancellation alert did not become key") { orderedPanel.isKeyWindow }
            checks[label + "-keeps-original-default-or-explicit-cancel-native-key-equivalent"] = cancelIndex == 0
                ? ordered.buttons[0].keyEquivalent == "\r"
                : ordered.buttons[cancelIndex].keyEquivalent == "\u{1b}"
                    && ordered.buttons.enumerated().filter { $0.element.keyEquivalent == "\u{1b}" }.map(\.offset) == [cancelIndex]
            try await escape(in: orderedPanel)
            try await wait("ordered cancellation did not settle", diagnostic: { traceKeys(ordered, responses: orderedResponses, phase: label) }) { orderedResponses.count == 1 && host.attachedSheet == nil }
            let expected = NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + cancelIndex)
            checks[label + "-Escape-never-admits-the-other-source-action"] = orderedResponses == [expected]
                && sourceEffects == 0 && !orderedPanel.isVisible && orderedPanel.sheetParent == nil
        }
        for titles in [["保留", "删除样本"], ["取消", "下载依赖项"]] {
            let defaultAlert = makeAppAlert(title: "默认安全操作", buttons: titles)
            var defaultResponses: [NSApplication.ModalResponse] = [], sourceEffects = 0
            let defaultPanel = presentAppAlert(defaultAlert, in: host) { response in
                defaultResponses.append(response)
                if response == .alertSecondButtonReturn { sourceEffects += 1 }
            }
            try await wait("native default action did not become key") { defaultPanel.isKeyWindow }
            try await pressReturn(in: defaultPanel)
            try await wait("Return stopped invoking the first safe native response", diagnostic: { traceKeys(defaultAlert, responses: defaultResponses, phase: "Return") }) { defaultResponses.count == 1 && host.attachedSheet == nil }
            checks["native-Return-keeps-first-\(titles[0])-response-without-admitting-second-source-action"] = defaultResponses == [.alertFirstButtonReturn]
                && sourceEffects == 0 && !defaultPanel.isVisible
        }

        let settings = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 500, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false; settings.makeKeyAndOrderFront(nil)
        var settingsResponses: [NSApplication.ModalResponse] = []
        let settingsAlert = makeAppAlert(title: "设置反馈")
        let settingsPanel = presentAppAlert(settingsAlert, in: settings) { settingsResponses.append($0) }
        try await wait("settings feedback attached to the wrong host") { settingsPanel.isKeyWindow }
        checks["settings-feedback-retains-the-explicit-settings-host"] = settingsPanel.sheetParent === settings && host.attachedSheet == nil
        try await escape(in: settingsPanel)
        try await wait("single-button native cancellation did not settle") { settingsResponses.count == 1 && !settingsPanel.isVisible }
        checks["native-single-button-cancel-keeps-original-response-and-exact-once-completion"] = settingsResponses == [.alertFirstButtonReturn]
            && settings.attachedSheet == nil && settingsPanel.sheetParent == nil
        settings.orderOut(nil); settings.close()

        let field = NSTextField(string: "原附件值")
        let external = makeAppAlert(title: "可由来源取消", buttons: ["保存", "取消"], accessoryView: field)
        var externalResponses: [NSApplication.ModalResponse] = []
        let externalPanel = presentAppAlert(external, in: host) { externalResponses.append($0) }
        try await wait("external cancellation sheet not key") { externalPanel.isKeyWindow }
        field.stringValue = "取消前附件值"
        host.endSheet(externalPanel, returnCode: .cancel); externalPanel.orderOut(nil)
        try await wait("external endSheet did not finish") { externalResponses.count == 1 && host.attachedSheet == nil }
        checks["source-owned-external-end-sheet-preserves-cancel-and-original-accessory"] = externalResponses == [.cancel]
            && field.stringValue == "取消前附件值" && !externalPanel.isVisible

        let closingHost = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 500, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        closingHost.isReleasedWhenClosed = false; closingHost.makeKeyAndOrderFront(nil)
        var closingResponses: [NSApplication.ModalResponse] = []
        let closingPanel = presentAppAlert(makeAppAlert(title: "父窗口关闭", buttons: ["保留", "删除样本"]), in: closingHost) { closingResponses.append($0) }
        try await wait("closing-host sheet never displayed") { closingPanel.isKeyWindow }
        closingHost.close()
        try await wait("parent close left feedback or its callback alive") { closingResponses.count == 1 && !closingPanel.isVisible }
        checks["parent-window-close-cancels-native-feedback-once-without-a-floating-panel"] = closingResponses == [.cancel]
            && closingHost.attachedSheet == nil

        let startup = makeAppAlert(title: "启动失败", buttons: ["好"])
        let observation = ModalObservation()
        let startupClick = Timer(timeInterval: 0.01, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard let modal = NSApp.modalWindow else { preconditionFailure("app-modal session never entered") }
                observation.wasVisible = modal === startup.window && modal.isVisible
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: modal.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                    isARepeat: false, keyCode: 53)!
                NSApp.postEvent(event, atStart: false)
            }
        }
        RunLoop.main.add(startupClick, forMode: .modalPanel)
        let startupResponse = runAppAlert(startup)
        startupClick.invalidate()
        checks["no-host-startup-feedback-remains-blocking-native-app-modal-with-original-response"] = observation.wasVisible
            && startupResponse == .alertFirstButtonReturn && NSApp.modalWindow == nil
        let noCompletion = makeAppAlert(title: "无回调反馈")
        let noCompletionObservation = ModalObservation()
        let noCompletionClick = Timer(timeInterval: 0.01, repeats: false) { _ in
            MainActor.assumeIsolated {
                noCompletionObservation.wasVisible = NSApp.modalWindow === noCompletion.window && noCompletion.window.isVisible
                noCompletion.buttons[0].performClick(nil)
            }
        }
        RunLoop.main.add(noCompletionClick, forMode: .modalPanel)
        let noCompletionPanel = presentAppAlert(noCompletion)
        noCompletionClick.invalidate()
        checks["no-completion-feedback-still-runs-the-native-app-modal-session"] = noCompletionPanel === noCompletion.window
            && noCompletionObservation.wasVisible && !noCompletionPanel.isVisible && NSApp.modalWindow == nil
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
