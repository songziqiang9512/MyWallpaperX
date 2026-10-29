import AppKit
import Combine

// Authentication and persistence are leaves. The full original controller,
// views, native sheet/subsheet lifetime and event delivery are production code.
@MainActor enum MainWindowCoordinator { static func mainWindow() -> NSWindow? { NSApp.mainWindow } }
@MainActor enum SteamAccountSession {
    enum AuthPhase: Equatable {
        case idle, connecting, authenticating, awaitingDeviceConfirmation, cancelled
        case qrChallenge(url: String), awaitingDeviceCode(previousCodeWasIncorrect: Bool)
        case awaitingEmailCode(emailDomain: String?, previousCodeWasIncorrect: Bool)
        case online(steamId: String, accountName: String?), failed(code: String, message: String)
    }
}
@MainActor enum SteamWorkshopTokenStore {
    struct Payload { let refreshToken: String, accountName: String, steamId: String }
    enum TokenSaveResult { case notAttempted, saved, failed }
    static let rememberPreferenceKey = "Fixture.rememberSteam"
    static var isRestoreAuthorized = false
    static var savedSession: Payload?
    static var sessionReads = 0
    static func load() -> Payload? { sessionReads += 1; return savedSession }
}
@MainActor enum SteamServiceClient { enum RequestError: Error { case helperError(String, String) } }
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    var statusMessage = ""
}
@MainActor final class SteamAuthRoute {
    @Published var phase = SteamAccountSession.AuthPhase.idle
    var isOnline = false, expired = false, accountName: String? = nil
    var tokenSaveResult = SteamWorkshopTokenStore.TokenSaveResult.notAttempted
    var qrStarts = 0, passwordStarts = 0, restoreStarts = 0, cancellations = 0, submittedCodes = 0
    func cancelPendingAuthentication() { cancellations += 1 }
    func loginQR() async throws -> Bool {
        qrStarts += 1; phase = .qrChallenge(url: "https://example.invalid/owned-current-challenge"); return true
    }
    func loginPassword(username: String, password: String) async throws -> Bool {
        passwordStarts += 1; isOnline = false; tokenSaveResult = .notAttempted
        phase = .authenticating; return true
    }
    func restore(refreshToken: String, accountName: String, expectedSteamId: String) async throws -> Bool {
        restoreStarts += 1; phase = .connecting; return false
    }
    func submit(code: String) async { submittedCodes += 1 }
}

@main enum SteamLoginModalHarness {
    @MainActor static func wait(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard condition() else { throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, type) }
    }
    @MainActor static func main() {
        initializeNativeAppHarness()
        Task { @MainActor in
            do { try await run() } catch { fatalError("Steam login native fixture: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        let controller = SteamLoginPanelController.shared, auth = SteamAuthRoute()
        var checks: [String: Bool] = [:]
        controller.show(auth: auth)
        checks["missing-main-host-never-starts-auth-or-opens-a-nonmodal-login"] = controller.window == nil && auth.qrStarts == 0 && auth.cancellations == 0
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        host.identifier = .init("MainWindow"); host.isReleasedWhenClosed = false; host.center()
        NSApp.activate(); host.makeKeyAndOrderFront(nil)
        defer { controller.window?.close(); host.close() }
        try await wait("login host not active/key") { host.isKeyWindow && NSApp.isActive }
        let probe = WallpaperModalInputProbe.install(in: host), beforeInput = [0, 0, 0]
        try await probe.deliver()
        let nativePositive = WallpaperModalInputProbe.hasOneDelivery(beforeInput, probe.values)
        controller.show(auth: auth)
        try await wait("original login panel or QR challenge did not appear") {
            controller.window?.isKeyWindow == true && auth.qrStarts == 1
                && (controller.window?.contentView as? SteamLoginPanelView)?.qrImageView.image != nil
        }
        let panel = controller.window!, view = panel.contentView as! SteamLoginPanelView
        checks["original-login-controller-owns-one-key-native-sheet-with-shared-clear-glass"] = panel.sheetParent === host && host.attachedSheet === panel
            && panel.isSheet && !panel.isOpaque && panel.backgroundColor == .clear
            && !panel.isMovable && !panel.isMovableByWindowBackground
            && descendants(view, NSGlassEffectView.self).count == 1 && panel.contentView is WallpaperPanelSurface
        let blockedBefore = probe.values
        try await probe.deliver()
        checks["steam-login-native-sheet-blocks-main-click-drag-and-key-with-system-backdrop"] = nativePositive
            && probe.values == blockedBefore && panel.isKeyWindow && !WallpaperLibrarySheetPresentation.permitsInput(in: host)
        controller.show(auth: auth)
        checks["repeated-login-presentation-keeps-the-same-panel-and-authentication-attempt"] = controller.window === panel
            && host.sheets.count == 1 && host.attachedSheet === panel && auth.qrStarts == 1
        view.zoomQRButton.performClick(nil)
        try await wait("original enlarged QR did not become a native subsheet") { panel.attachedSheet?.isKeyWindow == true }
        let enlarged = panel.attachedSheet!
        let startsBeforeNested = auth.qrStarts, cancelsBeforeNested = auth.cancellations
        NSApp.sendAction(view.refreshQRButton.action!, to: view.refreshQRButton.target, from: view.refreshQRButton)
        NSApp.sendAction(view.cancelButton.action!, to: view.cancelButton.target, from: view.cancelButton)
        panel.performClose(nil)
        checks["enlarged-qr-is-a-legal-top-subsheet-and-revokes-held-login-controls"] = enlarged.sheetParent === panel && panel.attachedSheet === enlarged && enlarged.isSheet && enlarged.isVisible
            && panel.isVisible && auth.qrStarts == startsBeforeNested && auth.cancellations == cancelsBeforeNested
            && !WallpaperLibrarySheetPresentation.permitsInput(in: panel) && WallpaperLibrarySheetPresentation.permitsInput(in: enlarged)
        enlarged.cancelOperation(nil)
        try await wait("QR cancel did not restore login input") { enlarged.sheetParent == nil && !enlarged.isVisible && panel.isKeyWindow }
        checks["closing-enlarged-qr-keeps-the-original-auth-attempt-and-releases-only-its-subsheet"] = auth.qrStarts == startsBeforeNested
            && auth.cancellations == cancelsBeforeNested && WallpaperLibrarySheetPresentation.permitsInput(in: panel)
        var responses: [NSApplication.ModalResponse] = []
        let alert = makeAppAlert(title: "当前登录确认", buttons: ["继续", "取消"])
        let alertWindow = presentAppAlert(alert, in: host) { responses.append($0) }
        try await wait("login confirmation did not attach above the real panel") { panel.attachedSheet === alertWindow && alertWindow.isVisible }
        NSApp.sendAction(view.refreshQRButton.action!, to: view.refreshQRButton.target, from: view.refreshQRButton)
        checks["nested-login-alert-stays-above-the-sheet-and-blocks-held-auth-controls"] = auth.qrStarts == startsBeforeNested
            && !WallpaperLibrarySheetPresentation.permitsInput(in: panel) && panel.sheetParent === host
        alert.buttons[1].performClick(nil)
        try await wait("login confirmation cancel did not settle") { responses.count == 1 && panel.attachedSheet == nil }
        checks["nested-login-confirmation-keeps-the-original-response-once"] = responses == [.alertSecondButtonReturn] && panel.isVisible
        let authBeforeFocus = auth.cancellations
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false; other.makeKeyAndOrderFront(nil)
        try await wait("unrelated window did not become key") { other.isKeyWindow }
        checks["ordinary-focus-change-does-not-cancel-the-admitted-login-or-disable-unrelated-window-input"] = auth.cancellations == authBeforeFocus
            && WallpaperLibrarySheetPresentation.permitsInput(in: other) && panel.isVisible
        other.close(); panel.makeKeyAndOrderFront(nil)
        let beforeCancel = auth.cancellations
        panel.cancelOperation(nil)
        try await wait("login Escape did not close and detach") { !panel.isVisible && panel.sheetParent == nil }
        NSApp.sendAction(view.refreshQRButton.action!, to: view.refreshQRButton.target, from: view.refreshQRButton)
        checks["login-cancel-clears-secrets-cancels-once-and-rejects-held-closed-controls"] = auth.cancellations == beforeCancel + 1
            && auth.qrStarts == startsBeforeNested && view.usernameField.stringValue.isEmpty && view.passwordField.stringValue.isEmpty
        host.makeKeyAndOrderFront(nil)
        try await wait("main input did not resume after login") { host.isKeyWindow }
        let restoredBefore = probe.values
        try await probe.deliver()
        checks["login-close-ends-native-modality-and-restores-main-click-drag-and-key"] = WallpaperModalInputProbe.hasOneDelivery(restoredBefore, probe.values)
        auth.phase = .online(steamId: "fixture-account", accountName: "Fixture")
        try await Task.sleep(for: .milliseconds(40))
        checks["late-auth-publication-cannot-reopen-the-closed-login"] = controller.window === panel && !panel.isVisible && panel.sheetParent == nil

        auth.isOnline = true; auth.accountName = "Fixture"; auth.tokenSaveResult = .saved
        let qrBeforeSwitch = auth.qrStarts, passwordBeforeSwitch = auth.passwordStarts
        controller.show(auth: auth)
        let switching = controller.window!, switchingView = switching.contentView as! SteamLoginPanelView
        try await Task.sleep(for: .milliseconds(80))
        checks["already-online-switch-account-keeps-the-password-page-without-replaying-old-success"] = switching.isVisible
            && switching.sheetParent === host && switchingView.modeSegment.selectedSegment == 1
            && !switchingView.loginButton.isHidden && !switchingView.usernameField.isHiddenOrHasHiddenAncestor
            && switchingView.doneButton.isHidden && auth.qrStarts == qrBeforeSwitch && auth.passwordStarts == passwordBeforeSwitch
        switchingView.usernameField.stringValue = "new-account"
        switchingView.passwordField.stringValue = "fixture-password"
        switchingView.loginButton.performClick(nil)
        try await wait("switch-account password did not begin a new authentication") { auth.passwordStarts == passwordBeforeSwitch + 1 }
        auth.phase = .awaitingDeviceCode(previousCodeWasIncorrect: false)
        try await wait("new authentication did not present its Guard input") { !switchingView.codeField.isHiddenOrHasHiddenAncestor }
        switchingView.codeField.stringValue = "123456"
        switchingView.guardSubmitButton.performClick(nil)
        try await wait("new Guard code was not submitted") { auth.submittedCodes == 1 }
        checks["switch-account-new-guard-transition-and-submission-remain-live"] = switching.isVisible
            && switchingView.statusLabel.stringValue == "正在提交验证码…" && auth.qrStarts == qrBeforeSwitch
        auth.isOnline = true; auth.accountName = "New Fixture"; auth.tokenSaveResult = .saved
        auth.phase = .online(steamId: "new-fixture-account", accountName: "New Fixture")
        try await wait("a new successful authentication did not close the switch-account panel") { !switching.isVisible && switching.sheetParent == nil }
        checks["switch-account-new-authentication-success-still-closes-the-panel"] = !switching.isVisible
            && auth.passwordStarts == passwordBeforeSwitch + 1

        auth.tokenSaveResult = .failed
        controller.show(auth: auth)
        let previousSaveFailure = controller.window!, failedView = previousSaveFailure.contentView as! SteamLoginPanelView
        try await Task.sleep(for: .milliseconds(80))
        checks["already-online-previous-token-save-failure-does-not-replace-the-new-password-page"] = previousSaveFailure.isVisible
            && !failedView.loginButton.isHidden && failedView.doneButton.isHidden
            && failedView.modeSegment.selectedSegment == 1 && auth.qrStarts == qrBeforeSwitch
        failedView.usernameField.stringValue = "another-account"
        failedView.passwordField.stringValue = "fixture-password"
        failedView.loginButton.performClick(nil)
        try await wait("authentication after an old save failure did not begin") { auth.passwordStarts == passwordBeforeSwitch + 2 }
        auth.isOnline = true; auth.tokenSaveResult = .failed
        auth.phase = .online(steamId: "unsaved-fixture-account", accountName: "Unsaved Fixture")
        try await wait("new token-save failure did not retain its completion feedback") { !failedView.doneButton.isHidden }
        checks["new-authentication-token-save-failure-still-requires-explicit-completion"] = previousSaveFailure.isVisible
            && failedView.loginButton.isHidden && failedView.statusLabel.stringValue == "本次会话可正常使用。"
        failedView.doneButton.performClick(nil)
        try await wait("explicit completion did not close the successful unsaved session") { !previousSaveFailure.isVisible }

        auth.isOnline = false; auth.tokenSaveResult = .notAttempted
        auth.phase = .failed(code: "network", message: "fixture disconnected")
        SteamWorkshopTokenStore.isRestoreAuthorized = true
        SteamWorkshopTokenStore.savedSession = .init(refreshToken: "fixture-token", accountName: "Fixture", steamId: "fixture-account")
        UserDefaults.standard.set(true, forKey: SteamWorkshopTokenStore.rememberPreferenceKey)
        let restoresBefore = auth.restoreStarts, readsBeforeRestore = SteamWorkshopTokenStore.sessionReads
        controller.show(auth: auth)
        let restoring = controller.window!
        try await wait("restorable session did not use its original restore action") { auth.restoreStarts == restoresBefore + 1 }
        let restoreView = restoring.contentView as! SteamLoginPanelView
        auth.phase = .awaitingDeviceConfirmation
        try await wait("restore did not retain the new device-confirmation transition") {
            restoreView.statusLabel.stringValue == "请在 Steam 手机应用中确认本次登录"
        }
        checks["silent-restore-new-guard-transition-remains-visible"] = restoring.isVisible
            && restoreView.loginButton.isHidden && restoreView.codeField.isHiddenOrHasHiddenAncestor
        auth.isOnline = true; auth.phase = .online(steamId: "fixture-account", accountName: "Fixture")
        try await wait("restored session success did not close the original panel") { !restoring.isVisible && restoring.sheetParent == nil }
        let restoreStartedOnce = auth.restoreStarts == restoresBefore + 1
        let restoreReadOnce = SteamWorkshopTokenStore.sessionReads == readsBeforeRestore + 1
        let restoreKeptQRCount = auth.qrStarts == qrBeforeSwitch
        let restoreClosed = !restoring.isVisible && restoring.sheetParent == nil
        let restoredStatus = SteamWorkshopService.shared.statusMessage
        FileHandle.standardError.write(Data(("steam-restore-success-diagnostic startedOnce=\(restoreStartedOnce) readOnce=\(restoreReadOnce) qrCountUnchanged=\(restoreKeptQRCount) closed=\(restoreClosed) status=\(restoredStatus.debugDescription)\n").utf8))
        checks["silent-restore-success-retains-original-completion-and-status-feedback"] = restoreStartedOnce
            && restoreReadOnce && restoreKeptQRCount && restoreClosed && restoredStatus == "已恢复 Steam 登录。"

        auth.isOnline = false; auth.phase = .failed(code: "network", message: "old disconnected attempt")
        let beforeFailedRestore = auth.restoreStarts
        controller.show(auth: auth)
        let networkFailure = controller.window!, networkFailureView = networkFailure.contentView as! SteamLoginPanelView
        try await wait("network-failure restore did not begin") { auth.restoreStarts == beforeFailedRestore + 1 }
        auth.phase = .failed(code: "network", message: "new restore network failure")
        let retainedSessionMessage = "暂时无法恢复上次登录（网络原因）；已保留登录信息，可扫码登录或稍后重试。"
        try await wait("new restore network failure did not use its retained-session feedback") {
            networkFailureView.statusLabel.stringValue == retainedSessionMessage
        }
        FileHandle.standardError.write(Data(("steam-restore-network-failure-diagnostic started=\(auth.restoreStarts) expected=\(beforeFailedRestore + 1) visible=\(networkFailure.isVisible) owned=\(networkFailure.sheetParent === host) status=\(networkFailureView.statusLabel.stringValue.debugDescription)\n").utf8))
        checks["silent-restore-new-network-failure-keeps-panel-and-reports-retained-session"] = networkFailure.isVisible
            && networkFailure.sheetParent === host && auth.restoreStarts == beforeFailedRestore + 1
            && SteamWorkshopTokenStore.savedSession != nil && auth.qrStarts == qrBeforeSwitch
            && networkFailureView.statusLabel.stringValue == retainedSessionMessage
        networkFailureView.cancelButton.performClick(nil)
        try await wait("failed restore did not close on explicit cancel") { !networkFailure.isVisible }

        auth.phase = .failed(code: "network", message: "old disconnected attempt")
        let beforeExpiredRestore = auth.restoreStarts
        controller.show(auth: auth)
        let expiredRestore = controller.window!, expiredView = expiredRestore.contentView as! SteamLoginPanelView
        try await wait("expired-session restore did not begin") { auth.restoreStarts == beforeExpiredRestore + 1 }
        auth.expired = true
        auth.phase = .failed(code: "authExpired", message: "new restore credential rejection")
        try await wait("new restore credential rejection did not show the original expired-session feedback") {
            expiredView.statusLabel.stringValue == "保存的登录已失效，请重新扫码登录。"
        }
        FileHandle.standardError.write(Data(("steam-restore-expired-failure-diagnostic started=\(auth.restoreStarts) expected=\(beforeExpiredRestore + 1) visible=\(expiredRestore.isVisible) owned=\(expiredRestore.sheetParent === host) status=\(expiredView.statusLabel.stringValue.debugDescription)\n").utf8))
        checks["silent-restore-new-credential-failure-keeps-panel-and-requires-new-login"] = expiredRestore.isVisible
            && expiredRestore.sheetParent === host && auth.restoreStarts == beforeExpiredRestore + 1
            && expiredView.statusLabel.stringValue == "保存的登录已失效，请重新扫码登录。"
        expiredView.cancelButton.performClick(nil)
        try await wait("expired restore did not close on explicit cancel") { !expiredRestore.isVisible }
        SteamWorkshopTokenStore.savedSession = nil; SteamWorkshopTokenStore.isRestoreAuthorized = false
        UserDefaults.standard.removeObject(forKey: SteamWorkshopTokenStore.rememberPreferenceKey)
        auth.isOnline = false; auth.expired = false; auth.tokenSaveResult = .notAttempted
        auth.phase = .idle
        controller.show(auth: auth)
        try await wait("second original login never opened") { controller.window !== panel && controller.window?.isVisible == true }
        let closing = controller.window!, beforeHostClose = auth.cancellations
        host.close()
        try await wait("main close left a login floating") { !closing.isVisible && closing.sheetParent == nil }
        checks["main-close-retires-the-owned-login-and-authentication-once"] = auth.cancellations == beforeHostClose + 1
            && !closing.isVisible && closing.attachedSheet == nil && closing.sheets.isEmpty
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
