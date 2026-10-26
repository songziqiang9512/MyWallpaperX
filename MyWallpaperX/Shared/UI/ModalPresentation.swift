//
//  ModalPresentation.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import AppKit

@MainActor func appModalHostWindow() -> NSWindow? {
    // 反馈 UI 优先挂到当前正在交互的窗口，再回退到主窗口，避免设置页等二级窗口把 sheet 错挂到主窗口上。
    if let keyWindow = NSApp.keyWindow, keyWindow.isVisible {
        return WallpaperLibrarySheetPresentation.topWindow(in: keyWindow)
    }
    if let mainWindow = NSApp.mainWindow, mainWindow.isVisible {
        return WallpaperLibrarySheetPresentation.topWindow(in: mainWindow)
    }
    return MainWindowCoordinator.mainWindow().map { WallpaperLibrarySheetPresentation.topWindow(in: $0) }
}

@MainActor func makeAppAlert(
    title: String,
    message: String = "",
    style: NSAlert.Style = .informational,
    buttons: [String] = ["确定"],
    accessoryView: NSView? = nil
) -> NSAlert {
    // AppKit owns the alert window, material and layout. Callers own the
    // original business decision, response order and accessory controls.
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = title
    alert.informativeText = message
    buttons.forEach { alert.addButton(withTitle: $0) }
    alert.accessoryView = accessoryView
    return alert
}

@discardableResult @MainActor func presentAppAlert(
    _ alert: NSAlert,
    in window: NSWindow? = nil,
    completion: ((NSApplication.ModalResponse) -> Void)? = nil
) -> NSWindow {
    let cancelMonitor = prepareAppAlert(alert)
    if let window {
        let host = WallpaperLibrarySheetPresentation.topWindow(in: window)
        let sheet = alert.window
        // A source window can close while its feedback is open. Cancel the
        // native sheet through its actual host; never leave a floating alert.
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: host, queue: .main
        ) { [weak host, weak sheet] _ in
            MainActor.assumeIsolated {
                guard let host, let sheet, sheet.sheetParent === host else { return }
                WallpaperLibrarySheetPresentation.dismissNestedSheets(in: sheet)
                host.endSheet(sheet, returnCode: .cancel)
                sheet.orderOut(nil)
            }
        }
        alert.beginSheetModal(for: host) { response in
            if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) }
            NotificationCenter.default.removeObserver(closeObserver)
            completion?(response)
        }
    } else {
        let response = alert.runModal()
        if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) }
        completion?(response)
    }
    return alert.window
}

@MainActor func runAppAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
    let cancelMonitor = prepareAppAlert(alert)
    defer { if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) } }
    return alert.runModal()
}

@MainActor private func prepareAppAlert(_ alert: NSAlert) -> Any? {
    alert.icon = NSApp.applicationIconImage
    // NSAlert recognizes English Cancel automatically. Keep explicit Escape
    // keys and give the App's Chinese no-op choices the same public shortcut.
    guard !alert.buttons.contains(where: { $0.keyEquivalent == "\u{1b}" }) else { return nil }
    if let cancel = alert.buttons.first(where: { ["取消", "保留", "稍后"].contains($0.title) })
        ?? (alert.buttons.count == 1 ? alert.buttons.first : nil) {
        if cancel === alert.buttons.first {
            // A native button has one key equivalent. Preserve its original
            // Return and route Escape to that same native action only while
            // this alert is the event's active, unobstructed window.
            let window = alert.window
            return NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window, weak cancel] event in
                guard event.keyCode == 53, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                      let window, event.window === window, window.isKeyWindow, window.attachedSheet == nil else { return event }
                cancel?.performClick(nil)
                return nil
            }
        }
        cancel.keyEquivalent = "\u{1b}"
    }
    return nil
}
