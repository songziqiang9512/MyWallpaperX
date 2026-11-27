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

    var automaticUpdateChecksEnabled: Bool? {
        #if DEBUG
        nil
        #else
        updaterController.updater.automaticallyChecksForUpdates
        #endif
    }

    func setAutomaticUpdateChecksEnabled(_ enabled: Bool) {
        #if !DEBUG
        updaterController.updater.automaticallyChecksForUpdates = enabled
        #endif
    }

    var automaticUpdateDownloadsEnabled: Bool {
        #if DEBUG
        false
        #else
        updaterController.updater.automaticallyDownloadsUpdates
        #endif
    }

    func setAutomaticUpdateDownloadsEnabled(_ enabled: Bool) {
        #if !DEBUG
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        #endif
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
        menuItem.title = availableUpdateVersion.map { String(localized: "New Version \($0) Available…") } ?? String(localized: "Check for Updates…")
        #if DEBUG
        return true
        #else
        return updaterController.updater.canCheckForUpdates
        #endif
    }

    @objc func checkForUpdates(_ sender: Any?) {
        #if DEBUG
        let alert = makeAppAlert(
            title: String(localized: "Debug builds don’t run automatic updates"),
            message: String(localized: "Automatic updates are only available in signed builds published on GitHub."),
            buttons: [String(localized: "OK")]
        )
        presentAppAlert(alert, in: appModalHostWindow())
        #else
        updaterController.checkForUpdates(sender)
        #endif
    }
}
