import Foundation

enum SceneDaemonProtocol { static let version = 2 }
final class ShortcutTransport { var isRunning = true }
@MainActor final class SceneDaemonClient {
    var pendingShortcutUpdates: [UInt64: PendingShortcutUpdate] = [:]
    var latestShortcutCommand: (recordID: String, revision: UInt64)?
    var shortcutUpdateAdmissionClosed = false
    var textureUpdateAdmissionClosed = false
    var activeIntent: ScenePlaybackLoadRequest? = .init(rootURL: URL(fileURLWithPath: "/tmp/fixture"),
        propertyOverrides: [:], userPropertyTextures: [:], recordID: "record")
    var pendingIntent: ScenePlaybackLoadRequest?
    var activeRequestID: UUID? = UUID()
    var endpointReady = true
    var transport: ShortcutTransport? = .init()
    var sessionGeneration: UInt64 = 1
    var sent: [[String: Any]] = []
    func hasIntent(for record: String) -> Bool { activeIntent?.recordID == record }
    func send(_ payload: [String: Any]) { sent.append(payload) }
    static func unsignedInteger(_ raw: Any?) -> UInt64? { (raw as? NSNumber)?.uint64Value }
}

@main enum Harness {
    @MainActor static func main() {
        let client = SceneDaemonClient()
        let reference = ScenePlaybackShortcutReference(kind: .webURL,
            url: URL(string: "https://example.invalid")!, bookmarkData: nil)
        func update(_ revision: UInt64) -> ScenePlaybackShortcutUpdate {
            .init(configuration: .init(revision: revision, references: ["action": reference]), recordID: "record")
        }
        func ack(_ revision: UInt64, accepted: Bool = true) {
            client.handleShortcutUpdateResult(["revision": revision, "recordID": "record",
                "requestID": client.activeRequestID!.uuidString, "accepted": accepted])
        }
        var outcomes: [String] = []
        precondition(client.applyUserShortcutUpdate(update(1)) { value in
            precondition(value == .superseded)
            outcomes.append("one")
            precondition(client.applyUserShortcutUpdate(update(3)) { value in
                precondition(value == .applied); outcomes.append("three")
            })
        })
        precondition(client.applyUserShortcutUpdate(update(2)) { value in
            precondition(value == .superseded); outcomes.append("two")
        })
        precondition(client.sent.count == 2)
        precondition(Set(client.pendingShortcutUpdates.keys) == [3])
        ack(1)
        precondition(client.activeIntent!.userShortcuts == .empty)
        ack(3); ack(3)
        precondition(client.activeIntent!.userShortcuts.revision == 3)
        precondition(outcomes == ["one", "two", "three"])
        precondition(client.applyUserShortcutUpdate(update(4)) { value in
            precondition(value == .superseded)
            precondition(client.applyUserShortcutUpdate(update(5)) { value in
                precondition(value == .superseded); outcomes.append("drain-reentry")
            })
        })
        client.finishPendingShortcutUpdates(.superseded)
        precondition(client.pendingShortcutUpdates.isEmpty)
        precondition(client.sent.count == 3)
        ack(4)
        precondition(client.activeIntent!.userShortcuts.revision == 3)
        precondition(outcomes.last == "drain-reentry")
        client.textureUpdateAdmissionClosed = true
        precondition(client.applyUserShortcutUpdate(update(6)) { value in precondition(value == .superseded) })
        precondition(client.pendingShortcutUpdates.isEmpty && client.sent.count == 3)
        client.textureUpdateAdmissionClosed = false
        client.pendingIntent = client.activeIntent
        precondition(client.applyUserShortcutUpdate(update(6)) { value in precondition(value == .unavailable) })
        precondition(client.sent.count == 3)
        print("shortcut-control-pass latest-wins no-drain-reentry")
    }
}
