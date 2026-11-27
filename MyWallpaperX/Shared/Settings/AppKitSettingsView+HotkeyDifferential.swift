//
//  AppKitSettingsView+HotkeyDifferential.swift
//  MyWallpaperX
//

import AppKit

extension AppKitSettingsContainerView {
    func refreshHotkeyRowsIfInputsChanged() {
        let actions = SystemHotkeyAction.allCases
        let settings = dependency.settings
        let assignments = actions.map { settings[keyPath: $0.settingsKeyPath] }
        guard assignments != lastHotkeyInputsSignature else { return }
        lastHotkeyInputsSignature = assignments

        let choices = FunctionKeyShortcut.allCases
        for (action, selected) in zip(actions, assignments) {
            guard let popup = hotkeyPopups[action] else { continue }
            for (item, choice) in zip(popup.itemArray, choices) {
                item.isEnabled = choice == .none || choice == selected || !assignments.contains(choice)
            }
            popup.selectItem(at: choices.firstIndex(of: selected)!)
        }
    }

    @objc func handleHotkeyPopupChange(_ sender: NSPopUpButton) {
        guard !isUpdatingUI,
              let action = hotkeyPopups.first(where: { $0.value === sender })?.key,
              let item = sender.selectedItem,
              item.isEnabled,
              let shortcut = item.representedObject as? FunctionKeyShortcut
        else { return }
        dependency.settings[keyPath: action.settingsKeyPath] = shortcut
        refreshFromState()
    }
}
