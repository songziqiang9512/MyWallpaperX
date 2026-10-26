import AppKit

@MainActor enum MainWindowCoordinator {
    static var host: NSWindow?
    static func mainWindow() -> NSWindow? { host }
}
@MainActor private final class FormServiceLeaf {
    var apiKey = "original-key"
    var resets = 0
    func resetLoadedState() { resets += 1 }
}
@MainActor private final class OnlineLibraryBrowserView: NSView {
    let service = FormServiceLeaf()
    var searches = 0, refreshes = 0
    func triggerInitialSearchIfNeeded() { searches += 1 }
    func syncContent(force: Bool) { precondition(force); refreshes += 1 }
    // ACTUAL_API_KEY_PRESENTATION
}

@main enum WallpaperFormFieldHarness {
    @MainActor static func descendants<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
        ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { descendants($0, type) }
    }
    @MainActor static func wait(_ message: String, diagnostic: (() -> Void)? = nil, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard condition() else {
            diagnostic?()
            throw NSError(domain: "FormNativeFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    @MainActor static func post(_ text: String, keyCode: UInt16, in window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: keyCode)!
        if keyCode == 36 || keyCode == 53 {
            // In this synthetic fixture postEvent did not reach the stock
            // alert's shortcut action while its secure editor owned input.
            // Exercise the public native entry; Tab uses the application queue.
            precondition(window.performKeyEquivalent(with: event), "native alert did not handle its public Return/Escape equivalent")
        } else {
            NSApp.postEvent(event, atStart: false)
        }
    }
    @MainActor static func responderKind(_ window: NSWindow, field: NSTextField) -> String {
        guard let responder = window.firstResponder else { return "none" }
        if responder === field || responder === field.currentEditor() { return "native-input" }
        if let button = responder as? NSButton { return "button:" + button.title }
        return String(describing: type(of: responder))
    }
    @MainActor static func traceStock(_ phase: String, alert: NSAlert, field: NSTextField,
                                      host: NSWindow, responses: [NSApplication.ModalResponse]) {
        func number(_ window: NSWindow?) -> Int { window?.windowNumber ?? 0 }
        let buttons = alert.buttons.enumerated().map { index, button in
            let facts: [String] = [
                "index=\(index)", "title=\(button.title)", "key=\(Array(button.keyEquivalent.utf16))", "modifiers=\(button.keyEquivalentModifierMask.rawValue)",
                "enabled=\(button.isEnabled)", "highlighted=\(button.isHighlighted)", "state=\(button.state.rawValue)",
                "action=\(String(describing: button.action))", "target=\(String(describing: button.target.map { type(of: $0) }))"
            ]
            return facts.joined(separator: ",")
        }
        let pressed = responses.map { response -> String in
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            return alert.buttons.indices.contains(index) ? alert.buttons[index].title : "response:\(response.rawValue)"
        }
        let facts: [String] = [
            "phase=\(phase)", "active=\(NSApp.isActive)", "key=\(number(NSApp.keyWindow))", "main=\(number(NSApp.mainWindow))",
            "modal=\(number(NSApp.modalWindow))", "alert=\(number(alert.window))", "visible=\(alert.window.isVisible)",
            "alertKey=\(alert.window.isKeyWindow)", "sheetParent=\(number(alert.window.sheetParent))",
            "host=\(number(host))", "hostKey=\(host.isKeyWindow)", "attached=\(number(host.attachedSheet))",
            "firstResponder=\(responderKind(alert.window, field: field))", "hasEditor=\(field.currentEditor() != nil)",
            "markedText=\((field.currentEditor() as? NSTextView)?.hasMarkedText() == true)",
            "responses=\(responses.map(\.rawValue))", "actualPressedByResponse=\(pressed)", "buttons=\(buttons)"
        ]
        FileHandle.standardError.write(Data(("FormStock " + facts.joined(separator: " ") + "\n").utf8))
    }
    @MainActor static func traceStockKey(_ event: NSEvent, alert: NSAlert, field: NSTextField) {
        let facts: [String] = [
            "code=\(event.keyCode)", "characters=\(Array((event.charactersIgnoringModifiers ?? "").utf16))",
            "window=\(event.windowNumber)", "belongsToAlert=\(event.window === alert.window)",
            "currentEventCode=\(String(describing: NSApp.currentEvent?.keyCode))", "alertKey=\(alert.window.isKeyWindow)",
            "firstResponder=\(responderKind(alert.window, field: field))", "active=\(NSApp.isActive)"
        ]
        FileHandle.standardError.write(Data(("FormStockDeliveredKey " + facts.joined(separator: " ") + "\n").utf8))
    }
    @MainActor static func main() {
        initializeNativeAppHarness()
        Task { @MainActor in
            do { try await run() } catch { fatalError("Native form fixture: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        var checks: [String: Bool] = [:]
        let host = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 600, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let view = OnlineLibraryBrowserView()
        host.contentView = view
        host.isReleasedWhenClosed = false
        MainWindowCoordinator.host = host
        NSApp.activate(); host.makeKeyAndOrderFront(nil)
        defer { host.close(); MainWindowCoordinator.host = nil }
        try await wait("real host never became active/key") { host.isKeyWindow && NSApp.isActive }

        // Stock NSAlert supplies the native Tab baseline for the same secure
        // input and button order; no full-keyboard-access preference is changed.
        let stockField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let stock = NSAlert()
        stock.messageText = "原生输入对照"
        stock.addButton(withTitle: "Save")
        stock.addButton(withTitle: "Cancel")
        stock.accessoryView = stockField
        stock.window.initialFirstResponder = stockField
        var stockResponses: [NSApplication.ModalResponse] = []
        let stockPanel = stock.window
        stock.beginSheetModal(for: host) {
            stockResponses.append($0)
            traceStock("response-callback", alert: stock, field: stockField, host: host, responses: stockResponses)
        }
        try await wait("stock secure editor did not acquire input") { stockPanel.isKeyWindow && stockField.currentEditor() != nil }
        let stockKeyObserver = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 48 || event.keyCode == 53 { traceStockKey(event, alert: stock, field: stockField) }
            }
            return event
        }
        defer { if let stockKeyObserver { NSEvent.removeMonitor(stockKeyObserver) } }
        traceStock("before-Tab", alert: stock, field: stockField, host: host, responses: stockResponses)
        post("\t", keyCode: 48, in: stockPanel)
        try await Task.sleep(for: .milliseconds(100))
        let stockTab = responderKind(stockPanel, field: stockField)
        traceStock("after-Tab-before-Escape", alert: stock, field: stockField, host: host, responses: stockResponses)
        post("\u{1b}", keyCode: 53, in: stockPanel)
        traceStock("Escape-dispatched", alert: stock, field: stockField, host: host, responses: stockResponses)
        try await wait("stock alert did not cancel", diagnostic: {
            traceStock("cancel-deadline-failed", alert: stock, field: stockField, host: host, responses: stockResponses)
        }) { stockResponses == [.alertSecondButtonReturn] && !stockPanel.isVisible && host.isKeyWindow }
        traceStock("cancel-settled", alert: stock, field: stockField, host: host, responses: stockResponses)
        checks["stock-native-secure-input-and-cancel-are-a-live-baseline"] = stockTab != "none" && host.attachedSheet == nil

        let action = NSButton(title: "编辑 API Key", target: view, action: NSSelectorFromString("presentAPIKeyEditFromAction"))
        action.performClick(nil)
        try await wait("original API-key dialog did not attach") { host.attachedSheet?.isKeyWindow == true }
        let panel = host.attachedSheet!
        let field = descendants(panel.contentView!, NSSecureTextField.self).first!
        try await wait("wrapped API-key editor was not the original initial responder") { field.currentEditor() != nil }
        let buttonKeys = descendants(panel.contentView!, NSButton.self).map {
            "\($0.title):key=\(Array($0.keyEquivalent.utf16)):modifiers=\($0.keyEquivalentModifierMask.rawValue)"
        }
        FileHandle.standardError.write(Data("FormWrapped buttons=\(buttonKeys) markedText=\((field.currentEditor() as? NSTextView)?.hasMarkedText() == true)\n".utf8))
        let editor = field.currentEditor() as! NSTextView
        checks["original-api-key-dialog-keeps-native-secure-initial-input-and-one-shared-surface"] = field is WallpaperFormSecureField
            && field.superview is WallpaperFormFieldSurface && !field.isBordered && !field.isBezeled && !field.drawsBackground
            && panel.firstResponder === editor && panel.initialFirstResponder === field && editor.isFieldEditor
            && abs((field.superview?.bounds.width ?? 0) - 280) <= 0.5 && field.superview?.bounds.height == 24
        editor.insertText("unsaved-fixture-key", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        post("\t", keyCode: 48, in: panel)
        try await Task.sleep(for: .milliseconds(100))
        checks["wrapped-secure-input-preserves-stock-native-Tab-domain"] = responderKind(panel, field: field) == stockTab
        post("\u{1b}", keyCode: 53, in: panel)
        try await wait("API-key cancel did not settle") { host.attachedSheet == nil && !panel.isVisible && host.isKeyWindow }
        checks["native-typed-api-key-cancel-does-not-save-or-trigger-search"] = view.service.apiKey == "original-key"
            && view.service.resets == 0 && view.searches == 0 && view.refreshes == 0

        action.performClick(nil)
        try await wait("second original API-key dialog did not attach") { host.attachedSheet?.isKeyWindow == true }
        let savePanel = host.attachedSheet!
        let saveField = descendants(savePanel.contentView!, NSSecureTextField.self).first!
        try await wait("second API-key dialog did not restore native initial input") { saveField.currentEditor() != nil }
        let saveEditor = saveField.currentEditor() as! NSTextView
        saveEditor.insertText("  committed-fixture-key  ", replacementRange: NSRange(location: 0, length: saveEditor.string.utf16.count))
        post("\r", keyCode: 36, in: savePanel)
        try await wait("native Return did not settle the original API-key response") { host.attachedSheet == nil && !savePanel.isVisible }
        checks["native-input-Return-saves-trimmed-api-key-and-refreshes-once"] = view.service.apiKey == "committed-fixture-key"
            && view.service.resets == 1 && view.searches == 1 && view.refreshes == 1
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
