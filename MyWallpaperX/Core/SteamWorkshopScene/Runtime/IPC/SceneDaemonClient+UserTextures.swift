import Foundation

@MainActor
extension SceneDaemonClient {
    struct PendingTextureUpdate {
        let update: ScenePlaybackTextureUpdate
        let generation: UInt64
        let completion: @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
        var waitsForFirstPresent: Bool
        let isLaunchRetry: Bool
        let fallbackBaseIntent: ScenePlaybackLoadRequest?
        var requestID: UUID?
    }

    @discardableResult
    func applyUserTextureUpdate(
        _ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) -> Bool {
        guard update.isValid, hasIntent(for: update.recordID) else { return false }
        guard pendingIntent == nil || pendingIntent?.recordID == update.recordID else {
            completion(.failed("Scene switch in progress"))
            return true
        }
        if pendingTextureUpdates.values.contains(where: {
            $0.fallbackBaseIntent != nil && textureRevisionKey($0.update) == textureRevisionKey(update)
        }) {
            completion(.unavailable)
            return true
        }
        guard activeIntent?.recordID == update.recordID,
              endpointReady, transport?.isRunning == true else {
            completion(.unavailable)
            return true
        }
        guard admitTextureRevision(update, completion: completion) else { return true }
        pendingTextureUpdates[update.revision] = .init(
            update: update, generation: sessionGeneration,
            completion: completion, waitsForFirstPresent: false, isLaunchRetry: false,
            fallbackBaseIntent: nil, requestID: nil
        )
        sendTextureUpdate(update)
        return true
    }

    @discardableResult
    func reloadUserTextureUpdate(
        _ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) -> Bool {
        guard update.isValid, hasIntent(for: update.recordID) else { return false }
        let key = textureRevisionKey(update)
        guard update.revision >= (latestTextureRevisions[key] ?? 0) else {
            completion(.superseded)
            return true
        }
        let priorFallback = pendingTextureUpdates.values.first {
            textureRevisionKey($0.update) == key && $0.fallbackBaseIntent != nil
        }
        guard let base = priorFallback?.fallbackBaseIntent ?? pendingIntent ?? activeIntent,
              base.recordID == update.recordID else { return false }
        let isPendingLaunch = priorFallback == nil && pendingIntent?.recordID == update.recordID
        if !isPendingLaunch {
            // A new choice for a key already preparing a fallback replaces
            // that candidate. Keep the last accepted intent as its base.
            let deferred = pendingTextureUpdates.values.filter {
                $0.waitsForFirstPresent && textureRevisionKey($0.update) != key
            }
            deferred.forEach { pendingTextureUpdates.removeValue(forKey: $0.update.revision) }
            var candidate = applying(update, to: base)
            candidate.requiredUserTextureKeys = update.keys
            let lifetime = activeResourceLifetime
            requestLaunch(candidate)
            pendingResourceLifetime = lifetime
            for pending in deferred {
                latestTextureRevisions[textureRevisionKey(pending.update)] = pending.update.revision
                pendingTextureUpdates[pending.update.revision] = .init(
                    update: pending.update, generation: sessionGeneration,
                    completion: pending.completion, waitsForFirstPresent: true,
                    isLaunchRetry: true, fallbackBaseIntent: nil, requestID: nil
                )
            }
        } else {
            let superseded = pendingTextureUpdates.filter {
                textureRevisionKey($0.value.update) == key
            }.map(\.key)
            for revision in superseded {
                pendingTextureUpdates.removeValue(forKey: revision)?.completion(.superseded)
            }
        }
        latestTextureRevisions[key] = update.revision
        pendingTextureUpdates[update.revision] = .init(
            update: update, generation: sessionGeneration,
            completion: completion, waitsForFirstPresent: true, isLaunchRetry: true,
            fallbackBaseIntent: isPendingLaunch ? nil : base, requestID: pendingRequestID
        )
        return true
    }

    private func admitTextureRevision(
        _ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) -> Bool {
        let key = textureRevisionKey(update)
        guard update.revision > (latestTextureRevisions[key] ?? 0) else {
            completion(.superseded)
            return false
        }
        let superseded = pendingTextureUpdates.filter {
            textureRevisionKey($0.value.update) == key
        }.map(\.key)
        for revision in superseded {
            pendingTextureUpdates.removeValue(forKey: revision)?.completion(.superseded)
        }
        latestTextureRevisions[key] = update.revision
        return true
    }

    private func textureRevisionKey(_ update: ScenePlaybackTextureUpdate) -> String {
        update.recordID + "\u{0}" + (update.keys.first ?? "")
    }

    private func sendTextureUpdate(_ update: ScenePlaybackTextureUpdate) {
        send([
            "v": SceneDaemonProtocol.version, "cmd": "setUserTextures",
            "references": update.references.mapValues { reference in
                var value: [String: Any] = ["path": reference.url.path]
                if let bookmark = reference.bookmarkData {
                    value["bookmark"] = bookmark.base64EncodedString()
                }
                return value
            },
            "resetKeys": update.resetKeys.sorted(),
            "values": update.values.mapValues(\.foundationValue),
            "revision": update.revision, "recordID": update.recordID,
        ])
    }

    func handleTextureUpdateResult(_ payload: [String: Any]) {
        guard let revision = Self.unsignedInteger(payload["revision"]),
              let pending = pendingTextureUpdates[revision],
              pending.generation == sessionGeneration,
              payload["recordID"] as? String == pending.update.recordID,
              !pending.waitsForFirstPresent else { return }
        let outcome: ScenePlaybackTextureUpdateOutcome
        switch payload["outcome"] as? String {
        case "applied": outcome = .applied
        case "superseded": outcome = .superseded
        case "unavailable": outcome = .unavailable
        case "failed": outcome = .failed(payload["message"] as? String ?? "Texture preparation failed")
        default: outcome = .failed("Invalid texture update response")
        }
        pendingTextureUpdates.removeValue(forKey: pending.update.revision)
        if outcome == .applied, let intent = activeIntent,
           intent.recordID == pending.update.recordID,
           latestTextureRevisions[textureRevisionKey(pending.update)] == pending.update.revision {
            activeIntent = applying(pending.update, to: intent)
        }
        pending.completion(outcome == .unavailable && pending.isLaunchRetry
            ? .failed("Scene runtime cannot accept this texture update") : outcome)
    }

    func bindDeferredTextureUpdates(recordID: String?, requestID: UUID) {
        for revision in Array(pendingTextureUpdates.keys) {
            guard var pending = pendingTextureUpdates[revision],
                  pending.waitsForFirstPresent, pending.requestID == nil,
                  pending.generation == sessionGeneration,
                  pending.update.recordID == recordID else { continue }
            pending.requestID = requestID
            pendingTextureUpdates[revision] = pending
        }
    }

    func fallbackReplayIntent(requestID: UUID) -> ScenePlaybackLoadRequest? {
        pendingTextureUpdates.values.first {
            $0.requestID == requestID && $0.fallbackBaseIntent != nil
        }?.fallbackBaseIntent
    }

    func resumeDeferredTextureUpdates(recordID: String?, requestID: UUID) {
        let revisions = pendingTextureUpdates.filter {
            $0.value.waitsForFirstPresent && $0.value.update.recordID == recordID
                && $0.value.generation == sessionGeneration
                && $0.value.requestID == requestID
        }.map(\.key)
        for revision in revisions {
            guard var pending = pendingTextureUpdates[revision] else { continue }
            if pending.fallbackBaseIntent != nil {
                pendingTextureUpdates.removeValue(forKey: revision)
                if let base = pending.fallbackBaseIntent {
                    // Other accepted properties/textures may have changed
                    // since candidate preparation. Commit only this key.
                    let accepted = activeIntent?.recordID == base.recordID ? activeIntent! : base
                    activeIntent = applying(pending.update, to: accepted)
                    activeIntent?.requiredUserTextureKeys = []
                }
                pending.completion(.applied)
            } else {
                pending.waitsForFirstPresent = false
                pendingTextureUpdates[revision] = pending
                sendTextureUpdate(pending.update)
            }
        }
    }

    func finishTextureReload(recordID: String?, outcome: ScenePlaybackTextureUpdateOutcome) {
        let revisions = pendingTextureUpdates.filter {
            $0.value.waitsForFirstPresent && $0.value.update.recordID == recordID
        }.map(\.key)
        for revision in revisions {
            guard let pending = pendingTextureUpdates.removeValue(forKey: revision) else { continue }
            restoreFallbackIntent(pending)
            pending.completion(outcome)
        }
    }

    private func restoreFallbackIntent(_ pending: PendingTextureUpdate) {
        guard let base = pending.fallbackBaseIntent else { return }
        // activeIntent retained the accepted base at .launched. It may
        // already include independently acknowledged edits; keep those.
        if pendingIntent?.recordID == base.recordID {
            pendingIntent = activeIntent?.recordID == base.recordID ? activeIntent : base
        }
    }

    func finishPendingTextureUpdates(_ outcome: ScenePlaybackTextureUpdateOutcome) {
        let pending = Array(pendingTextureUpdates.values)
        pendingTextureUpdates.removeAll(keepingCapacity: true)
        for request in pending {
            restoreFallbackIntent(request)
            request.completion(outcome)
        }
    }

    private func applying(
        _ update: ScenePlaybackTextureUpdate, to intent: ScenePlaybackLoadRequest
    ) -> ScenePlaybackLoadRequest {
        var result = intent
        result.propertyOverrides.merge(update.values) { _, new in new }
        result.userPropertyTextures.merge(update.references) { _, new in new }
        for key in update.resetKeys { result.userPropertyTextures.removeValue(forKey: key) }
        return result
    }
}
