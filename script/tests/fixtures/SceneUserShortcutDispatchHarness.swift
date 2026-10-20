import Foundation
typealias SceneScriptUserShortcutDispatch = @Sendable (ScenePlaybackShortcutGesture, String) -> Int32

struct ShortcutContext {
    var userShortcuts: ScenePlaybackShortcutConfiguration = .empty
    var userShortcutKeys: Set<String> = ["renamedAction", "unbound"]
}
final class SceneDesktopWallpaperSession {
    var userShortcutInput = SceneUserShortcutInputState()
    var userShortcutURLs: [String: URL] = [:]
    var userShortcutScopedKeys: Set<String> = []
    var launchContext: ShortcutContext? = .init()
    var launchRequestID: UUID? = UUID()
    var activeRecordID: String? = "record"
    var isVisible = true
    var isOutputActive = true
    var drainStarted = false
    var userShortcutOpener: (URL) -> Bool = { _ in fatalError("test must inject opener") }
}
final class SceneDesktopWallpaperHost { var activeSession: SceneDesktopWallpaperSession? }

@main enum Harness {
    static func main() throws {
        let session = SceneDesktopWallpaperSession()
        var calls: [URL] = []
        var nativeResult = true
        session.userShortcutOpener = { calls.append($0); return nativeResult }
        let reference = ScenePlaybackShortcutReference(kind: .webURL,
            url: URL(string: "https://example.invalid/benign")!, bookmarkData: nil)
        let configuration = ScenePlaybackShortcutConfiguration(revision: 1,
            references: ["renamedAction": reference])
        precondition(session.applyUserShortcutConfiguration(configuration))
        func click() -> ScenePlaybackShortcutGesture {
            let id = session.userShortcutInput.receiveNativeButtonEvent(down: true, up: false)!
            _ = session.userShortcutInput.receiveNativeButtonEvent(down: false, up: true)
            return .init(requestID: session.launchRequestID!,
                configurationRevision: session.launchContext!.userShortcuts.revision, gestureID: id)
        }
        let orphaned = ScenePlaybackShortcutConfiguration(revision: 2,
            references: ["deleted": reference, "renamedAction": reference])
        precondition(session.applyUserShortcutConfiguration(orphaned))
        precondition(session.userShortcutURLs["deleted"] == nil)
        precondition(session.userShortcutURLs["renamedAction"] != nil)
        precondition(session.applyUserShortcutConfiguration(.init(revision: 3,
            references: ["deleted": reference, "renamedAction": reference])))
        let first = click()
        let dispatch: SceneScriptUserShortcutDispatch = session.userShortcutDispatch(frameIndex: 1)
        let optionalDispatch: SceneScriptUserShortcutDispatch? = .some(dispatch)
        precondition(optionalDispatch?(first, "renamedAction") == 1)
        precondition(calls.count == 1, "native open must finish before the synchronous callback returns")
        precondition(optionalDispatch?(first, "renamedAction") == -1)
        precondition(session.dispatchUserShortcut(first, key: "renamedAction", frameIndex: 2) == -1)
        precondition(calls.count == 1)
        let sameFrame = click()
        precondition(session.dispatchUserShortcut(sameFrame, key: "renamedAction", frameIndex: 1) == -1)
        precondition(session.dispatchUserShortcut(sameFrame, key: "renamedAction", frameIndex: 3) == -1)
        let missing = click()
        precondition(session.dispatchUserShortcut(missing, key: "unknown", frameIndex: 4) == 0)
        precondition(session.dispatchUserShortcut(missing, key: "renamedAction", frameIndex: 5) == -1)
        nativeResult = false
        let failed = click()
        precondition(session.dispatchUserShortcut(failed, key: "renamedAction", frameIndex: 6) == 0)
        precondition(session.dispatchUserShortcut(failed, key: "renamedAction", frameIndex: 7) == -1)
        precondition(calls.count == 2)
        nativeResult = true
        let stale = click()
        precondition(session.applyUserShortcutConfiguration(.init(revision: 4, references: configuration.references)))
        precondition(session.dispatchUserShortcut(stale, key: "renamedAction", frameIndex: 8) == 0)
        precondition(!session.applyUserShortcutConfiguration(configuration))
        let retired = click()
        session.userShortcutInput.revoke()
        precondition(session.dispatchUserShortcut(retired, key: "renamedAction", frameIndex: 9) == 0)
        let hidden = click()
        session.isVisible = false
        precondition(session.dispatchUserShortcut(hidden, key: "renamedAction", frameIndex: 10) == 0)
        session.userShortcutInput.revoke()
        session.isVisible = true
        let wrong = click()
        let foreign = ScenePlaybackShortcutGesture(requestID: UUID(), configurationRevision: 4,
            gestureID: wrong.gestureID)
        precondition(session.dispatchUserShortcut(foreign, key: "renamedAction", frameIndex: 11) == 0)
        let host = SceneDesktopWallpaperHost(); host.activeSession = session
        precondition(!host.applyUserShortcutUpdate(.init(configuration: .init(revision: 5, references: [:]),
            recordID: "other"), requestID: session.launchRequestID!))
        precondition(host.applyUserShortcutUpdate(.init(configuration: .init(revision: 5, references: [:]),
            recordID: "record"), requestID: session.launchRequestID!))
        precondition(session.userShortcutURLs.isEmpty)
        let resetClick = click()
        precondition(session.dispatchUserShortcut(resetClick, key: "renamedAction", frameIndex: 12) == 0)
        precondition(calls.count == 2)
        for value in ["file:///tmp/no", "javascript:alert(1)", "https://user:pass@example.com", "custom:command"] {
            precondition(!ScenePlaybackShortcutReference(kind: .webURL,
                url: URL(string: value)!, bookmarkData: nil).isValid)
        }
        precondition(!ScenePlaybackShortcutReference(kind: .file,
            url: URL(fileURLWithPath: "/tmp/no"), bookmarkData: nil).isValid)
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(ScenePlaybackShortcutConfiguration.self, from: data)
        precondition(decoded == configuration)
        let level = -100
        precondition(PlaybackDesktopInputAdmission.allowsDesktopWindow(ownerPID: 42,
            ownerBundleIdentifier: "com.apple.finder", ownerName: "Finder", layer: level,
            currentPID: 99, desktopIconLevel: level))
        for (pid, bundle, name, layer) in [(42, "com.apple.finder", "Finder", 0),
            (42, "test.editor", "Editor", level), (99, "com.apple.finder", "Finder", level),
            (42, "", "", level)] {
            precondition(!PlaybackDesktopInputAdmission.allowsDesktopWindow(ownerPID: Int32(pid),
                ownerBundleIdentifier: bundle, ownerName: name, layer: layer,
                currentPID: 99, desktopIconLevel: level))
        }
        print("shortcut-dispatch-pass native-calls=2")
    }
}
