import AppKit
import Combine

// Authentication and persistence are leaves. The full original controller,
// views, native child/modal lifetime and event delivery are production code.
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
    static var isRestoreAuthorized: Bool { false }
    static func load() -> Payload? { nil }
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
        passwordStarts += 1; phase = .authenticating; return true
    }
    func restore(refreshToken: String, accountName: String, expectedSteamId: String) async throws -> Bool {
        restoreStarts += 1; return false
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
        checks["original-login-controller-owns-one-key-child-with-shared-clear-glass"] = panel.parent === host && host.attachedSheet == nil
            && !panel.isSheet && !panel.isOpaque && panel.backgroundColor == .clear
            && !panel.isMovable && !panel.isMovableByWindowBackground
            && descendants(view, NSGlassEffectView.self).count == 1 && panel.contentView is WallpaperLibrarySheetSurface
        let blockedBefore = probe.values
        try await probe.deliver()
        checks["steam-login-blocks-native-queue-main-click-drag-and-key-without-a-gray-sheet"] = nativePositive
            && probe.values == blockedBefore && panel.isKeyWindow && !WallpaperLibrarySheetPresentation.permitsInput(in: host)
        controller.show(auth: auth)
        checks["repeated-login-presentation-keeps-the-same-panel-and-authentication-attempt"] = controller.window === panel
            && host.childWindows?.count == 1 && auth.qrStarts == 1
        view.zoomQRButton.performClick(nil)
        try await wait("original enlarged QR did not become a native child") { panel.childWindows?.first?.isKeyWindow == true }
        let enlarged = panel.childWindows!.first!
        let startsBeforeNested = auth.qrStarts, cancelsBeforeNested = auth.cancellations
        NSApp.sendAction(view.refreshQRButton.action!, to: view.refreshQRButton.target, from: view.refreshQRButton)
        NSApp.sendAction(view.cancelButton.action!, to: view.cancelButton.target, from: view.cancelButton)
        panel.performClose(nil)
        checks["enlarged-qr-is-a-legal-top-child-and-revokes-held-login-controls"] = enlarged.parent === panel && enlarged.isVisible
            && panel.isVisible && auth.qrStarts == startsBeforeNested && auth.cancellations == cancelsBeforeNested
            && !WallpaperLibrarySheetPresentation.permitsInput(in: panel) && WallpaperLibrarySheetPresentation.permitsInput(in: enlarged)
        enlarged.cancelOperation(nil)
        try await wait("QR cancel did not restore login input") { enlarged.parent == nil && !enlarged.isVisible && panel.isKeyWindow }
        checks["closing-enlarged-qr-keeps-the-original-auth-attempt-and-releases-only-its-child"] = auth.qrStarts == startsBeforeNested
            && auth.cancellations == cancelsBeforeNested && WallpaperLibrarySheetPresentation.permitsInput(in: panel)
        var responses: [NSApplication.ModalResponse] = []
        let alert = makeAppAlert(title: "当前登录确认", buttons: ["继续", "取消"])
        let alertWindow = presentAppAlert(alert, in: host) { responses.append($0) }
        try await wait("login confirmation did not attach above the real panel") { panel.attachedSheet === alertWindow && alertWindow.isVisible }
        NSApp.sendAction(view.refreshQRButton.action!, to: view.refreshQRButton.target, from: view.refreshQRButton)
        checks["nested-login-alert-stays-above-the-child-and-blocks-held-auth-controls"] = auth.qrStarts == startsBeforeNested
            && !WallpaperLibrarySheetPresentation.permitsInput(in: panel) && panel.parent === host
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
        try await wait("login Escape did not close and detach") { !panel.isVisible && panel.parent == nil }
        NSApp.sendAction(view.refreshQRButton.action!, to: view.refreshQRButton.target, from: view.refreshQRButton)
        checks["login-cancel-clears-secrets-cancels-once-and-rejects-held-closed-controls"] = auth.cancellations == beforeCancel + 1
            && auth.qrStarts == startsBeforeNested && view.usernameField.stringValue.isEmpty && view.passwordField.stringValue.isEmpty
        host.makeKeyAndOrderFront(nil)
        try await wait("main input did not resume after login") { host.isKeyWindow }
        let restoredBefore = probe.values
        try await probe.deliver()
        checks["login-close-removes-the-local-monitor-and-restores-native-queue-main-click-drag-and-key"] = WallpaperModalInputProbe.hasOneDelivery(restoredBefore, probe.values)
        auth.phase = .online(steamId: "fixture-account", accountName: "Fixture")
        try await Task.sleep(for: .milliseconds(40))
        checks["late-auth-publication-cannot-reopen-the-closed-login"] = controller.window === panel && !panel.isVisible && panel.parent == nil
        auth.phase = .idle
        controller.show(auth: auth)
        try await wait("second original login never opened") { controller.window !== panel && controller.window?.isVisible == true }
        let closing = controller.window!, beforeHostClose = auth.cancellations
        host.close()
        try await wait("main close left a login floating") { !closing.isVisible && closing.parent == nil }
        checks["main-close-retires-the-owned-login-and-authentication-once"] = auth.cancellations == beforeHostClose + 1
            && !closing.isVisible && closing.childWindows?.isEmpty != false
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
