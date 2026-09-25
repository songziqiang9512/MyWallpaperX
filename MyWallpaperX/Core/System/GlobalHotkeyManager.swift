//
//  GlobalHotkeyManager.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import Carbon

final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    /// E2d: 热键动作由 App 装配注入——Core 不再直呼 Modules 的选择权威。
    var systemHotkeyActionHandler: (@MainActor (SystemHotkeyAction) -> Void)?

    private struct RegisteredHotkey {
        let id: UInt32
        let action: SystemHotkeyAction
        let ref: EventHotKeyRef
    }

    private var registeredHotkeys: [RegisteredHotkey] = []
    private var eventHandlerRef: EventHandlerRef?
    private let hotkeySignature: OSType = 0x4D575858 // MWXX

    private init() {
        installEventHandlerIfNeeded()
    }

    func update(with settings: WallpaperSettings) {
        unregisterAll()

        guard settings.systemHotkeysEnabled else { return }

        let bindings: [(SystemHotkeyAction, FunctionKeyShortcut)] = [
            (.previous, settings.previousWallpaperHotkey),
            (.next, settings.nextWallpaperHotkey),
            (.playPause, settings.togglePlaybackHotkey),
            (.muteToggle, settings.toggleMuteHotkey)
        ]

        for (index, binding) in bindings.enumerated() {
            registerHotkey(binding.1, action: binding.0, id: UInt32(index + 1))
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      let action = GlobalHotkeyManager.shared.action(for: hotKeyID.id) else {
                    return noErr
                }

                DispatchQueue.main.async {
                    GlobalHotkeyManager.shared.systemHotkeyActionHandler?(action)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func registerHotkey(_ shortcut: FunctionKeyShortcut, action: SystemHotkeyAction, id: UInt32) {
        guard shortcut != .none,
              let keyCode = keyCode(for: shortcut) else {
            return
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), 0, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, let hotKeyRef else { return }

        registeredHotkeys.append(RegisteredHotkey(id: id, action: action, ref: hotKeyRef))
    }

    private func unregisterAll() {
        for hotkey in registeredHotkeys {
            UnregisterEventHotKey(hotkey.ref)
        }
        registeredHotkeys.removeAll()
    }

    private func action(for id: UInt32) -> SystemHotkeyAction? {
        registeredHotkeys.first(where: { $0.id == id })?.action
    }

    private func keyCode(for shortcut: FunctionKeyShortcut) -> Int? {
        switch shortcut {
        case .none: return nil
        case .f1: return kVK_F1
        case .f2: return kVK_F2
        case .f3: return kVK_F3
        case .f4: return kVK_F4
        case .f5: return kVK_F5
        case .f6: return kVK_F6
        case .f7: return kVK_F7
        case .f8: return kVK_F8
        case .f9: return kVK_F9
        case .f10: return kVK_F10
        case .f11: return kVK_F11
        case .f12: return kVK_F12
        }
    }
}
