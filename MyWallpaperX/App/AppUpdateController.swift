//
//  AppUpdateController.swift
//  MyWallpaperX
//

import AppKit
import Sparkle

@MainActor
final class AppUpdateController: NSObject, SPUStandardUserDriverDelegate, NSMenuItemValidation {
    static let shared = AppUpdateController()

    private(set) var availableUpdateVersion: String?

    private lazy var updaterController: SPUStandardUpdaterController = {
        #if DEBUG
        let startsUpdater = false
        #else
        let startsUpdater = true
        #endif
        return SPUStandardUpdaterController(startingUpdater: startsUpdater,
            updaterDelegate: nil, userDriverDelegate: self)
    }()

    private override init() {
        super.init()
        _ = updaterController
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableUpdateVersion = state.userInitiated ? nil : update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableUpdateVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableUpdateVersion = nil
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title = availableUpdateVersion.map { "发现新版本 \($0)…" } ?? "检查更新…"
        #if DEBUG
        return true
        #else
        return updaterController.updater.canCheckForUpdates
        #endif
    }

    @objc func checkForUpdates(_ sender: Any?) {
        #if DEBUG
        let alert = makeAppAlert(
            title: "调试构建不执行自动更新",
            message: "自动更新只在 GitHub 发布的签名版本中启用。",
            buttons: ["好"]
        )
        presentAppAlert(alert, in: appModalHostWindow())
        #else
        updaterController.checkForUpdates(sender)
        #endif
    }
}
