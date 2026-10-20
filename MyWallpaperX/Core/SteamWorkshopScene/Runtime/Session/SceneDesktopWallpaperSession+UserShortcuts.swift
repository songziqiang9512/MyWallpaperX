import AppKit
import Foundation
import QuartzCore

/// The pointer owner keeps an irreversible watermark rather than a growing
/// set of completed clicks. Restoring a VM/frame snapshot cannot refund it.
nonisolated struct SceneUserShortcutInputState {
    private(set) var lastIssued: UInt64 = 0
    private var heldGesture: UInt64?
    private var consumedThrough: UInt64 = 0
    private var revokedThrough: UInt64 = 0
    private var consumedFrame: UInt64?

    mutating func receiveNativeButtonEvent(down: Bool, up: Bool) -> UInt64? {
        if down {
            if heldGesture == nil { lastIssued += 1; heldGesture = lastIssued }
            return heldGesture
        }
        if up {
            defer { heldGesture = nil }
            return heldGesture
        }
        return heldGesture
    }

    mutating func revoke() {
        revokedThrough = lastIssued
        heldGesture = nil
    }

    enum Admission { case allowed, duplicate, revoked }

    mutating func consume(_ gesture: UInt64, frame: UInt64) -> Admission {
        guard gesture > revokedThrough, gesture <= lastIssued else { return .revoked }
        guard gesture > consumedThrough else { return .duplicate }
        // A second click rejected by the same-frame budget is spent as well;
        // retrying its retained callback next frame must not open anything.
        consumedThrough = gesture
        guard consumedFrame != frame else { return .duplicate }
        consumedFrame = frame
        return .allowed
    }
}

extension SceneDesktopWallpaperSession {
    /// The native adapter owns its actor boundary; the frame driver supplies
    /// only the existing frame identity, with no second action clock.
    func userShortcutDispatch(frameIndex: UInt64) -> SceneScriptUserShortcutDispatch {
        { [weak self] gesture, key in
            MainActor.assumeIsolated {
                self?.dispatchUserShortcut(gesture, key: key, frameIndex: frameIndex) ?? 0
            }
        }
    }

    func installUserShortcuts(_ configuration: ScenePlaybackShortcutConfiguration) {
        releaseUserShortcutScopes()
        guard configuration.isValid, let context = launchContext else { return }
        for (key, reference) in configuration.references where context.userShortcutKeys.contains(key) {
            switch reference.kind {
            case .webURL:
                userShortcutURLs[key] = reference.url
            case .file:
                guard let bookmark = reference.bookmarkData else { continue }
                var stale = false
                let resolved = (try? URL(resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                    bookmarkDataIsStale: &stale)) ?? (try? URL(resolvingBookmarkData: bookmark,
                    options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale))
                guard let resolved, !stale, resolved.isFileURL else { continue }
                let scoped = resolved.startAccessingSecurityScopedResource()
                guard (try? resolved.checkResourceIsReachable()) == true else {
                    if scoped { resolved.stopAccessingSecurityScopedResource() }
                    continue
                }
                userShortcutURLs[key] = resolved
                if scoped { userShortcutScopedKeys.insert(key) }
            }
        }
    }

    func releaseUserShortcutScopes() {
        userShortcutInput.revoke()
        for key in userShortcutScopedKeys { userShortcutURLs[key]?.stopAccessingSecurityScopedResource() }
        userShortcutScopedKeys.removeAll(keepingCapacity: true)
        userShortcutURLs.removeAll(keepingCapacity: true)
    }

    func applyUserShortcutConfiguration(_ configuration: ScenePlaybackShortcutConfiguration) -> Bool {
        guard let context = launchContext, configuration.isValid,
              configuration.revision > context.userShortcuts.revision else { return false }
        // Main-thread serial publication revokes captured old clicks before
        // this new immutable configuration can become executable.
        installUserShortcuts(configuration)
        launchContext?.userShortcuts = configuration
        return true
    }

    func dispatchUserShortcut(
        _ gesture: ScenePlaybackShortcutGesture, key: String, frameIndex: UInt64
    ) -> Int32 {
        guard isVisible, isOutputActive, !drainStarted,
              launchRequestID == gesture.requestID, let context = launchContext,
              context.userShortcuts.revision == gesture.configurationRevision else { return 0 }
        switch userShortcutInput.consume(gesture.gestureID, frame: frameIndex) {
        case .revoked: return 0
        case .duplicate: return -1
        case .allowed: break
        }
        guard context.userShortcutKeys.contains(key), let url = userShortcutURLs[key] else { return 0 }
        let start = CACurrentMediaTime()
        let opened = userShortcutOpener(url)
#if DEBUG
        NSLog("MWX Scene user-shortcut: key=%@ request=%@ revision=%llu gesture=%llu accepted=%@ dispatchMs=%.3f",
            key, gesture.requestID.uuidString, gesture.configurationRevision, gesture.gestureID,
            opened ? "true" : "false", (CACurrentMediaTime() - start) * 1_000)
#endif
        return opened ? 1 : 0
    }
}

extension SceneDesktopWallpaperHost {
    func applyUserShortcutUpdate(_ update: ScenePlaybackShortcutUpdate, requestID: UUID) -> Bool {
        guard let session = activeSession, session.launchRequestID == requestID,
              session.activeRecordID == update.recordID else { return false }
        return session.applyUserShortcutConfiguration(update.configuration)
    }
}
