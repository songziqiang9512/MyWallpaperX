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
        return topAppModalWindow(keyWindow)
    }
    if let mainWindow = NSApp.mainWindow, mainWindow.isVisible {
        return topAppModalWindow(mainWindow)
    }
    return MainWindowCoordinator.mainWindow().map(topAppModalWindow)
}

@MainActor private func topAppModalWindow(_ window: NSWindow) -> NSWindow {
    WallpaperLibrarySheetPresentation.topWindow(in: window)
}

@MainActor func makeAppAlert(
    title: String,
    message: String = "",
    style: NSAlert.Style = .informational,
    buttons: [String] = ["确定"],
    accessoryView: NSView? = nil
) -> NSAlert {
    // 统一工厂方法保证所有警告/确认弹窗都走同一套按钮与样式初始化。
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = title
    alert.informativeText = message
    buttons.forEach { alert.addButton(withTitle: $0) }
    alert.accessoryView = accessoryView
    return alert
}

extension NSAlert {
    @MainActor func applyAppDialogStyle() {
        // Public properties only. Centered geometry belongs to the App-owned
        // presentation, never to private NSAlert fields or internal subviews.
        icon = NSApp.applicationIconImage
    }
}

@discardableResult @MainActor func presentAppAlert(
    _ alert: NSAlert,
    in window: NSWindow? = nil,
    completion: ((NSApplication.ModalResponse) -> Void)? = nil
) -> NSWindow {
    // 先应用统一样式，再决定用 sheet 还是 modal，不把展示策略散到调用方。
    alert.applyAppDialogStyle()

    let presentation = AppCenteredAlertPresentation(alert: alert, completion: completion)
    if let window { presentation.beginSheet(in: topAppModalWindow(window)) }
    else { _ = presentation.runModal() }
    return presentation.window
}

@MainActor func runAppAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
    alert.applyAppDialogStyle()
    return AppCenteredAlertPresentation(alert: alert, completion: nil).runModal()
}
