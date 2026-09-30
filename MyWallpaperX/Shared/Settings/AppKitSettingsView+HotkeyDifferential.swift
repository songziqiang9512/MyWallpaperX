//
//  AppKitSettingsView+HotkeyDifferential.swift
//  MyWallpaperX
//

import AppKit

extension AppKitSettingsContainerView {
    /// refreshFromState 的热键差分入口：下拉菜单整份重灌 52 个菜单项，只在热键相关输入变化时执行；
    /// 菜单项可用性只取决于这 5 项输入。
    func refreshHotkeyRowsIfInputsChanged() {
        let settings = dependency.settings
        let hotkeyInputsSignature = [
            settings.systemHotkeysEnabled ? "1" : "0",
            settings.previousWallpaperHotkey.rawValue,
            settings.nextWallpaperHotkey.rawValue,
            settings.togglePlaybackHotkey.rawValue,
            settings.toggleMuteHotkey.rawValue
        ]
        if hotkeyInputsSignature != lastHotkeyInputsSignature {
            lastHotkeyInputsSignature = hotkeyInputsSignature
            refreshHotkeyRows()
        }
    }

    @objc func handleHotkeyEnableToggle(_ sender: NSSwitch) {
        guard !isUpdatingUI else { return }
        guard let action = hotkeyAction(from: sender.tag) else { return }

        if sender.state == .on {
            if assignedShortcut(for: action) == .none {
                let available = firstAvailableShortcut(for: action)
                if available != .none {
                    setAssignedShortcut(available, for: action)
                }
            }
        } else {
            setAssignedShortcut(.none, for: action)
        }
        refreshFromState()
    }

    @objc func handleHotkeyPopupChange(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        guard let action = hotkeyAction(from: sender.tag) else { return }
        guard let shortcut = sender.selectedItem?.representedObject as? FunctionKeyShortcut else { return }
        if isShortcutAvailable(shortcut, for: action) {
            setAssignedShortcut(shortcut, for: action)
        }
        refreshFromState()
    }

    private func assignedShortcut(for action: SystemHotkeyAction) -> FunctionKeyShortcut {
        // 快捷键状态源只读写 settings，popup 不直接保存自己的状态。
        switch action {
        case .previous:
            return dependency.settings.previousWallpaperHotkey
        case .next:
            return dependency.settings.nextWallpaperHotkey
        case .playPause:
            return dependency.settings.togglePlaybackHotkey
        case .muteToggle:
            return dependency.settings.toggleMuteHotkey
        }
    }

    private func setAssignedShortcut(_ shortcut: FunctionKeyShortcut, for action: SystemHotkeyAction) {
        // 统一通过 settings 写回，避免每个热键 row 各自维护一份绑定结果。
        switch action {
        case .previous:
            dependency.settings.previousWallpaperHotkey = shortcut
        case .next:
            dependency.settings.nextWallpaperHotkey = shortcut
        case .playPause:
            dependency.settings.togglePlaybackHotkey = shortcut
        case .muteToggle:
            dependency.settings.toggleMuteHotkey = shortcut
        }
    }

    private func usedShortcuts(excluding action: SystemHotkeyAction) -> Set<FunctionKeyShortcut> {
        Set(
            SystemHotkeyAction.allCases
                .filter { $0 != action }
                .map { assignedShortcut(for: $0) }
                .filter { $0 != .none }
        )
    }

    private func isShortcutAvailable(_ shortcut: FunctionKeyShortcut, for action: SystemHotkeyAction) -> Bool {
        shortcut == .none || shortcut == assignedShortcut(for: action) || !usedShortcuts(excluding: action).contains(shortcut)
    }

    private func firstAvailableShortcut(for action: SystemHotkeyAction) -> FunctionKeyShortcut {
        FunctionKeyShortcut.allCases.first(where: { $0 != .none && isShortcutAvailable($0, for: action) }) ?? .none
    }

    private func refreshHotkeyRows() {
        // 热键行刷新时同时处理启用开关和下拉可用性，保持“一个动作一行”一致。
        let masterEnabled = dependency.settings.systemHotkeysEnabled
        for action in SystemHotkeyAction.allCases {
            guard let toggle = hotkeyEnableSwitches[action],
                  let popup = hotkeyPopups[action] else {
                continue
            }
            let shortcut = assignedShortcut(for: action)
            let enabled = shortcut != .none
            toggle.state = enabled ? .on : .off
            popup.isEnabled = masterEnabled && enabled
            reloadHotkeyPopup(popup, for: action, selected: shortcut)
        }
    }

    private func reloadHotkeyPopup(_ popup: NSPopUpButton, for action: SystemHotkeyAction, selected: FunctionKeyShortcut) {
        // 这里要重新构建整份菜单，因为禁用项和当前选项会随其它快捷键变化而变化。
        popup.removeAllItems()
        for shortcut in FunctionKeyShortcut.allCases {
            popup.addItem(withTitle: shortcut.displayName)
            popup.lastItem?.representedObject = shortcut
            popup.lastItem?.isEnabled = isShortcutAvailable(shortcut, for: action)
        }
        if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? FunctionKeyShortcut) == selected }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
        }
    }

    func hotkeyTag(for action: SystemHotkeyAction) -> Int {
        switch action {
        case .previous: return 1
        case .next: return 2
        case .playPause: return 3
        case .muteToggle: return 4
        }
    }

    private func hotkeyAction(from tag: Int) -> SystemHotkeyAction? {
        switch tag {
        case 1: return .previous
        case 2: return .next
        case 3: return .playPause
        case 4: return .muteToggle
        default: return nil
        }
    }
}
