import Foundation

@MainActor
extension SceneDaemonClient {
    struct PendingShortcutUpdate {
        let update: ScenePlaybackShortcutUpdate
        let requestID: UUID
        let generation: UInt64
        let completion: @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void
    }

    @discardableResult
    func applyUserShortcutUpdate(
        _ update: ScenePlaybackShortcutUpdate,
        completion: @escaping @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void
    ) -> Bool {
        guard !shortcutUpdateAdmissionClosed, !textureUpdateAdmissionClosed else { completion(.superseded); return true }
        guard update.configuration.isValid, update.configuration.revision > 0,
              hasIntent(for: update.recordID) else { return false }
        guard pendingIntent == nil, activeIntent?.recordID == update.recordID,
              let requestID = activeRequestID, endpointReady, transport?.isRunning == true else {
            completion(.unavailable)
            return true
        }
        let revision = update.configuration.revision
        let latest = max(activeIntent?.userShortcuts.revision ?? 0,
            latestShortcutCommand?.recordID == update.recordID ? latestShortcutCommand!.revision : 0)
        guard revision > latest else { completion(.superseded); return true }
        // Full immutable configurations replace each other. Never merge an old
        // completion into a newer assignment, or replay an OS action over IPC.
        latestShortcutCommand = (update.recordID, revision)
        finishPendingShortcutUpdates(.superseded, closeAdmission: false)
        guard latestShortcutCommand?.recordID == update.recordID,
              latestShortcutCommand?.revision == revision,
              activeRequestID == requestID, pendingIntent == nil else {
            completion(.superseded)
            return true
        }
        pendingShortcutUpdates[revision] = .init(update: update, requestID: requestID,
            generation: sessionGeneration, completion: completion)
        send(["v": SceneDaemonProtocol.version, "cmd": "setUserShortcuts",
            "configuration": SceneDaemonProtocol.shortcutObject(update.configuration),
            "recordID": update.recordID, "requestID": requestID.uuidString])
        return true
    }

    func handleShortcutUpdateResult(_ payload: [String: Any]) {
        guard let revision = Self.unsignedInteger(payload["revision"]),
              let pending = pendingShortcutUpdates[revision],
              pending.generation == sessionGeneration,
              payload["recordID"] as? String == pending.update.recordID,
              payload["requestID"] as? String == pending.requestID.uuidString,
              let accepted = payload["accepted"] as? Bool else { return }
        pendingShortcutUpdates.removeValue(forKey: revision)
        guard activeRequestID == pending.requestID,
              activeIntent?.recordID == pending.update.recordID, pendingIntent == nil else {
            pending.completion(.superseded)
            return
        }
        if accepted {
            activeIntent?.userShortcuts = pending.update.configuration
            pending.completion(.applied)
        } else { pending.completion(.failed("Scene shortcut configuration was rejected")) }
    }

    func finishPendingShortcutUpdates(
        _ outcome: ScenePlaybackShortcutUpdateOutcome, closeAdmission: Bool = true
    ) {
        let admissionWasClosed = shortcutUpdateAdmissionClosed
        shortcutUpdateAdmissionClosed = admissionWasClosed || closeAdmission
        defer { shortcutUpdateAdmissionClosed = admissionWasClosed }
        let pending = Array(pendingShortcutUpdates.values)
        pendingShortcutUpdates.removeAll(keepingCapacity: true)
        pending.forEach { $0.completion(outcome) }
    }
}
