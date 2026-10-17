import Foundation

// Leaves replace only the platform service and actual pipe. The subscription,
// generation checks, asynchronous preparation, ACK pump and receiver are real.
@MainActor final class SystemMediaService {
    static let shared = SystemMediaService()
    var snapshot = SystemMediaSnapshot.empty
    var currentSnapshot: SystemMediaSnapshot { snapshot }
    var subscriptions: [UUID: (SystemMediaSnapshot) -> Void] = [:]
    var mediaDemands: [UUID: Bool] = [:]
    var subscribeCount = 0
    var unsubscribeCount = 0
    func subscribe(_ id: UUID, needsMedia: Bool = true,
                   receive: @escaping (SystemMediaSnapshot) -> Void) {
        subscribeCount += 1
        subscriptions[id] = receive
        mediaDemands[id] = needsMedia
        receive(snapshot)
    }
    func unsubscribe(_ id: UUID) {
        if subscriptions.removeValue(forKey: id) != nil { unsubscribeCount += 1 }
        mediaDemands.removeValue(forKey: id)
    }
    func publish(_ value: SystemMediaSnapshot) {
        snapshot = value
        for receive in Array(subscriptions.values) { receive(value) }
    }
}
@MainActor final class SceneDaemonClient {
    final class Transport {
        var sent: [Data] = []
        var terminated = false
        func send(_ data: Data) -> Bool { sent.append(data); return true }
        func terminate() { terminated = true }
    }
    var endpointReady = true
    var sessionGeneration: UInt64 = 1
    var transport: Transport? = Transport()
    var activeRequestID: UUID? = UUID()
    var pendingRequestID: UUID?
    var expectedTerminationGenerations: Set<UInt64> = []
    var retiringTransports: [UInt64: Transport] = [:]
    let systemMedia = SceneDaemonMediaClientState()
    var failures: [String] = []
    func publishFailure(code: String, message: String) { failures.append(code) }
}

@main enum SceneSystemMediaIPCChecks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        let request = UUID()
        let demand = SceneSystemMediaDemand(token: UUID(), requests: [request])
        let scope = SceneDaemonMediaScope(demand: demand, transportGeneration: 1)
        let bytes = Data(repeating: 42, count: SceneDaemonMediaWire.maximumChunkBytes + 19)
        let descriptor = SceneDaemonMediaArtwork(transferID: UUID(), byteCount: bytes.count,
            sha256: SceneDaemonMediaWire.digest(bytes))
        func snapshot(_ revision: UInt64, _ track: String = "A", art: Data? = nil,
                      epoch: UInt64 = 1, sessionGeneration: UInt64 = 1) -> SystemMediaSnapshot {
            .init(enabled: true, epoch: epoch, revision: revision, sourceID: "player",
                sessionID: track, sessionGeneration: sessionGeneration,
                media: .init(current: art, primaryColor: .init(0.2, 0.3, 0.4), secondaryColor: nil,
                    generation: sessionGeneration, playbackState: 1, playbackGeneration: 1,
                    properties: .init(title: track, artist: "artist", subTitle: "", albumTitle: "album",
                        albumArtist: "", genres: "", contentType: ""), propertiesGeneration: revision,
                    timeline: .init(position: Double(revision), duration: 120), timelineGeneration: revision),
                webThumbnail: nil)
        }
        func frame(_ value: SystemMediaSnapshot, artwork: SceneDaemonMediaArtwork? = nil,
                   scope suppliedScope: SceneDaemonMediaScope? = nil) -> SceneDaemonMediaSnapshotFrame {
            .init(scope: suppliedScope ?? scope, snapshot: value, artwork: artwork)
        }
        var receiver = SceneDaemonMediaReceiver()
        receiver.setDemand(demand)
        let first = receiver.receive(frame(snapshot(1), artwork: descriptor))
        checks["metadata_publishes_without_waiting_for_art"] = first.acknowledgement.accepted
            && first.publication?.properties?.title == "A" && first.publication?.current == nil
        let chunk0 = SceneDaemonMediaArtworkChunk(scope: scope, transferID: descriptor.transferID,
            index: 0, bytes: bytes.prefix(SceneDaemonMediaWire.maximumChunkBytes))
        let part = receiver.receive(chunk0)
        checks["partial_art_not_published"] = part.acknowledgement.accepted && part.publication == nil
        checks["duplicate_chunk_rejected"] = !receiver.receive(chunk0).acknowledgement.accepted
        let promoted = SceneSystemMediaDemand(token: UUID(), requests: [request], generation: 2)
        let promotedScope = SceneDaemonMediaScope(demand: promoted, transportGeneration: 1)
        var partialPromotion = receiver
        partialPromotion.setDemand(promoted)
        let partialReplay = partialPromotion.receive(frame(snapshot(2), artwork: descriptor, scope: promotedScope))
        checks["scope_change_restarts_partial_image_at_zero"] = partialReplay.acknowledgement.nextArtworkIndex == 0
            && partialReplay.publication?.current == nil
        checks["old_scope_piece_cannot_join_new_assembly"] = !partialPromotion.receive(chunk0).acknowledgement.accepted
        checks["metadata_during_assembly_is_independent"] = receiver.receive(
            frame(snapshot(2), artwork: descriptor)).publication?.timeline?.position == 2
        let chunk1 = SceneDaemonMediaArtworkChunk(scope: scope, transferID: descriptor.transferID,
            index: 1, bytes: bytes.suffix(19))
        let finished = receiver.receive(chunk1)
        checks["complete_digest_verified_art_published_once"] = finished.acknowledgement.accepted
            && finished.publication?.current == bytes && finished.publication?.timeline?.position == 2
        checks["same_art_metadata_retains_original_quality"] = receiver.receive(
            frame(snapshot(3), artwork: descriptor)).publication?.current == bytes
        var completedPromotion = receiver
        completedPromotion.setDemand(promoted)
        let completedReplay = completedPromotion.receive(frame(snapshot(3), artwork: descriptor, scope: promotedScope))
        checks["same_confirmed_art_survives_new_scene_demand"] = completedReplay.acknowledgement.accepted
            && completedReplay.acknowledgement.nextArtworkIndex == nil && completedReplay.publication?.current == bytes
        checks["stale_revision_rejected"] = !receiver.receive(
            frame(snapshot(2), artwork: descriptor)).acknowledgement.accepted
        checks["stale_epoch_rejected"] = !receiver.receive(
            frame(snapshot(99, epoch: 0))).acknowledgement.accepted
        let wrongScope = SceneDaemonMediaScope(
            demand: .init(token: UUID(), requests: [request]), transportGeneration: 1)
        checks["old_demand_token_rejected"] = !receiver.receive(
            frame(snapshot(4), scope: wrongScope)).acknowledgement.accepted
        let wrongTransport = SceneDaemonMediaScope(demand: demand, transportGeneration: 2)
        checks["wrong_transport_generation_rejected"] = !receiver.receive(
            frame(snapshot(4), scope: wrongTransport)).acknowledgement.accepted
        let b = receiver.receive(frame(snapshot(4, "B", sessionGeneration: 2)))
        checks["track_switch_clears_old_art_immediately"] = b.publication?.properties?.title == "B"
            && b.publication?.current == nil
        checks["late_old_track_chunk_rejected"] = !receiver.receive(chunk1).acknowledgement.accepted
        let huge = SceneDaemonMediaArtwork(transferID: UUID(),
            byteCount: SceneDaemonMediaWire.maximumArtworkBytes + 1, sha256: descriptor.sha256)
        let oversized = receiver.receive(frame(snapshot(5, "B", sessionGeneration: 2), artwork: huge))
        checks["oversize_art_does_not_block_metadata"] = oversized.acknowledgement.accepted
            && oversized.publication?.properties?.title == "B" && oversized.publication?.current == nil
        checks["stale_session_generation_rejected"] = !receiver.receive(
            frame(snapshot(6, "A", sessionGeneration: 1))).acknowledgement.accepted
        let corrupt = SceneDaemonMediaArtwork(transferID: UUID(), byteCount: 2,
            sha256: SceneDaemonMediaWire.digest(Data([1, 2])))
        _ = receiver.receive(frame(snapshot(6, "B", sessionGeneration: 2), artwork: corrupt))
        let corruptResult = receiver.receive(.init(scope: scope, transferID: corrupt.transferID,
            index: 0, bytes: Data([3, 4])))
        checks["bad_digest_drops_only_art"] = !corruptResult.acknowledgement.accepted
            && corruptResult.publication == nil
        var clear = SystemMediaSnapshot.empty
        clear.epoch = 2; clear.revision = 6
        let cleared = receiver.receive(frame(clear))
        checks["disabled_snapshot_clears_channels"] = cleared.acknowledgement.accepted
            && cleared.publication?.properties == nil && cleared.publication?.current == nil
        receiver.setDemand(.init(token: UUID(), requests: []))
        checks["no_demand_rejects_late_metadata"] = !receiver.receive(frame(snapshot(9))).acknowledgement.accepted
        let local = SystemMediaSnapshotStore()
        _ = local.replaceSystemSnapshot(finished.publication!)
        let localGeneration = local.latest().generation
        _ = local.replaceSystemSnapshot(cleared.publication!)
        checks["local_generation_does_not_follow_remote_reset"] = local.latest().generation > localGeneration
            && local.latest().current == nil

        // The declared product limit is accepted at original quality, without
        // raising the pipe's control budget or publishing intermediate images.
        let maximumImage = Data(repeating: 77, count: SceneDaemonMediaWire.maximumArtworkBytes)
        let maximumDescriptor = SceneDaemonMediaArtwork(transferID: UUID(), byteCount: maximumImage.count,
            sha256: SceneDaemonMediaWire.digest(maximumImage))
        var maximumReceiver = SceneDaemonMediaReceiver()
        maximumReceiver.setDemand(demand)
        _ = maximumReceiver.receive(frame(snapshot(1), artwork: maximumDescriptor))
        var allChunksAccepted = true
        var intermediatePublished = false
        var maximumResult: SystemMediaSnapshotStore.Snapshot?
        for offset in stride(from: 0, to: maximumImage.count, by: SceneDaemonMediaWire.maximumChunkBytes) {
            let end = min(maximumImage.count, offset + SceneDaemonMediaWire.maximumChunkBytes)
            let result = maximumReceiver.receive(.init(scope: scope, transferID: maximumDescriptor.transferID,
                index: offset / SceneDaemonMediaWire.maximumChunkBytes,
                bytes: maximumImage.subdata(in: offset ..< end)))
            allChunksAccepted = allChunksAccepted && result.acknowledgement.accepted
            if end < maximumImage.count { intermediatePublished = intermediatePublished || result.publication != nil }
            maximumResult = result.publication
        }
        checks["full_16mib_original_image_supported"] = allChunksAccepted && maximumResult?.current == maximumImage
        checks["full_image_has_only_one_publication"] = !intermediatePublished

        let registry = SceneSystemMediaDemandRegistry()
        let lifecycleA = UUID(), lifecycleB = UUID(), requestB = UUID()
        registry.acquire(lifecycleA, requestID: request)
        let registryA = registry.demand
        registry.acquire(lifecycleA, requestID: request)
        checks["duplicate_lifecycle_demand_is_idempotent"] = registry.demand == registryA
        registry.acquire(lifecycleB, requestID: requestB)
        checks["promoted_overlap_preserves_both_request_identities"] = registry.demand.requests == [request, requestB]
        registry.release(lifecycleA)
        checks["retiring_old_session_keeps_new_media_demand"] = registry.demand.requests == [requestB]
        let beforeLastRelease = registry.demand
        registry.release(lifecycleB)
        checks["last_release_revokes_demand_identity"] = !registry.demand.requiresMedia
            && registry.demand.token != beforeLastRelease.token
            && registry.demand.generation > beforeLastRelease.generation

        func payload<T: Encodable>(_ body: T) throws -> [String: Any] {
            ["frame": try JSONSerialization.jsonObject(with: JSONEncoder().encode(body))]
        }
        func spin(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        }
        func decoded<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            return SceneDaemonMediaWire.decode(type, payload: object,
                maximumBytes: SceneDaemonMediaWire.maximumChunkBytes * 2)!
        }
        func acknowledge(_ client: SceneDaemonClient, _ ack: SceneDaemonMediaAcknowledgement) throws {
            client.handleSystemMediaAcknowledgement(try payload(ack), generation: client.sessionGeneration)
        }
        let client = SceneDaemonClient()
        client.activeRequestID = request
        SystemMediaService.shared.snapshot = snapshot(10, art: bytes)
        try client.handleSystemMediaDemand(payload(demand), generation: 1)
        try client.handleSystemMediaDemand(payload(demand), generation: 1)
        spin { client.transport!.sent.count == 1 }
        checks["single_subscription_for_same_demand"] = SystemMediaService.shared.subscribeCount == 1
        checks["one_metadata_in_flight"] = client.transport!.sent.count == 1 && client.systemMedia.awaiting != nil
        let sentFrame = try decoded(SceneDaemonMediaSnapshotFrame.self, client.transport!.sent[0])
        checks["wire_metadata_excludes_full_art"] = sentFrame.snapshot.media.current == nil
            && sentFrame.artwork?.byteCount == bytes.count
        var daemon = SceneDaemonMediaReceiver()
        daemon.setDemand(demand)
        try acknowledge(client, daemon.receive(sentFrame).acknowledgement)
        spin { client.transport!.sent.count == 2 }
        let sentChunk = try decoded(SceneDaemonMediaArtworkChunk.self, client.transport!.sent[1])
        checks["one_bounded_chunk_in_flight"] = sentChunk.bytes.count == SceneDaemonMediaWire.maximumChunkBytes
            && client.transport!.sent.count == 2
        SystemMediaService.shared.publish(snapshot(11, "B", art: Data([7, 8]), sessionGeneration: 2))
        SystemMediaService.shared.publish(snapshot(12, "C", art: Data([9, 10]), sessionGeneration: 3))
        spin { client.systemMedia.preparing == nil }
        try acknowledge(client, daemon.receive(sentChunk).acknowledgement)
        spin { client.transport!.sent.count == 3 }
        let newest = try decoded(SceneDaemonMediaSnapshotFrame.self, client.transport!.sent[2])
        checks["latest_snapshot_precedes_old_art_suffix"] = newest.snapshot.sessionID == "C"
            && newest.snapshot.revision == 12
        try acknowledge(client, daemon.receive(newest).acknowledgement)
        spin { client.transport!.sent.count == 4 }
        let newestChunk = try decoded(SceneDaemonMediaArtworkChunk.self, client.transport!.sent[3])
        checks["new_track_restarts_art_identity"] = newestChunk.index == 0
            && newestChunk.transferID != sentChunk.transferID && newestChunk.bytes == Data([9, 10])
        var off = clear; off.revision = 13
        SystemMediaService.shared.publish(off)
        spin { client.systemMedia.preparing == nil }
        try acknowledge(client, daemon.receive(newestChunk).acknowledgement)
        spin { client.transport!.sent.count == 5 }
        let offFrame = try decoded(SceneDaemonMediaSnapshotFrame.self, client.transport!.sent[4])
        checks["disable_preempts_more_art"] = !offFrame.snapshot.enabled && offFrame.artwork == nil
        try acknowledge(client, daemon.receive(offFrame).acknowledgement)
        let count = client.transport!.sent.count
        client.revokeSystemMediaDemand(generation: 1)
        try acknowledge(client, daemon.receive(newestChunk).acknowledgement)
        spin { client.systemMedia.preparing == nil }
        checks["teardown_revokes_subscription_and_late_ack"] = SystemMediaService.shared.subscriptions.isEmpty
            && client.transport!.sent.count == count && client.systemMedia.scope == nil
        SystemMediaService.shared.snapshot = snapshot(14, art: bytes)
        let nextDemand = SceneSystemMediaDemand(token: UUID(), requests: [request], generation: 2)
        try client.handleSystemMediaDemand(payload(nextDemand), generation: 1)
        spin { client.transport!.sent.count == count + 1 }
        let replay = try decoded(SceneDaemonMediaSnapshotFrame.self, client.transport!.sent.last!)
        checks["new_demand_replays_full_art_descriptor"] = replay.scope.demand == nextDemand
            && replay.artwork != nil && replay.artwork?.transferID != sentFrame.artwork?.transferID
        try client.handleSystemMediaDemand(payload(demand), generation: 1)
        checks["late_demand_aba_cannot_replace_current_token"] = client.systemMedia.scope?.demand == nextDemand
        let unsubscribesBeforePromotion = SystemMediaService.shared.unsubscribeCount
        let promotedDemand = SceneSystemMediaDemand(token: UUID(), requests: [request], generation: 3)
        try client.handleSystemMediaDemand(payload(promotedDemand), generation: 1)
        checks["media_to_media_promotion_keeps_collection_lease"] = SystemMediaService.shared.unsubscribeCount
            == unsubscribesBeforePromotion && SystemMediaService.shared.subscriptions.count == 1
        client.revokeSystemMediaDemand(generation: 1)
        try client.handleSystemMediaDemand(payload(nextDemand), generation: 0)
        checks["old_generation_cannot_resubscribe"] = SystemMediaService.shared.subscriptions.isEmpty
        checks["no_protocol_failure_on_normal_flow"] = client.failures.isEmpty

        let recoveryClient = SceneDaemonClient()
        recoveryClient.activeRequestID = request
        SystemMediaService.shared.snapshot = snapshot(20)
        try recoveryClient.handleSystemMediaDemand(payload(demand), generation: 1)
        spin { recoveryClient.transport!.sent.count == 1 }
        var recoveryReceiver = SceneDaemonMediaReceiver()
        recoveryReceiver.setDemand(demand)
        let healthy = try decoded(SceneDaemonMediaSnapshotFrame.self, recoveryClient.transport!.sent[0])
        let healthyResult = recoveryReceiver.receive(healthy)
        let recoveryInbox = SystemMediaSnapshotStore()
        _ = recoveryInbox.replaceSystemSnapshot(healthyResult.publication!)
        try acknowledge(recoveryClient, healthyResult.acknowledgement)
        SystemMediaService.shared.publish(snapshot(21))
        spin { recoveryClient.transport!.sent.count == 2 }
        let lostAckFrame = try decoded(SceneDaemonMediaSnapshotFrame.self, recoveryClient.transport!.sent[1])
        _ = recoveryReceiver.receive(lostAckFrame)
        recoveryClient.systemMedia.timeout?.perform()
        let failureClear = try decoded(SceneDaemonMediaControl.self, recoveryClient.transport!.sent[2])
        let didClear = recoveryReceiver.control(failureClear)
        if didClear { recoveryInbox.clearMediaSession() }
        checks["ack_timeout_sends_typed_clear_without_killing_scene"] = failureClear.operation == .clear
            && didClear && recoveryInbox.latest().properties?.title == ""
            && !recoveryClient.transport!.terminated
        checks["failed_channel_keeps_status_observation_only"] = recoveryClient.systemMedia.unavailable
            && SystemMediaService.shared.mediaDemands[recoveryClient.systemMedia.subscriptionID] == false
            && recoveryClient.systemMedia.heartbeat == nil
        checks["timeout_has_one_bounded_retry"] = recoveryClient.systemMedia.retryBudget == 0
            && recoveryClient.systemMedia.retry != nil
        recoveryClient.systemMedia.retry?.perform()
        spin { recoveryClient.transport!.sent.count == 4 }
        let replayAfterClear = try decoded(SceneDaemonMediaSnapshotFrame.self, recoveryClient.transport!.sent[3])
        checks["cleared_channel_can_replay_same_confirmed_snapshot"] = recoveryReceiver.receive(
            replayAfterClear).acknowledgement.accepted
        recoveryClient.systemMedia.timeout?.perform()
        checks["retry_exhaustion_does_not_schedule_forever"] = recoveryClient.systemMedia.unavailable
            && recoveryClient.systemMedia.retry == nil && recoveryClient.systemMedia.retryBudget == 0
        var switchedOff = clear; switchedOff.revision = 22
        SystemMediaService.shared.publish(switchedOff)
        checks["disabled_preference_arms_manual_recovery"] = recoveryClient.systemMedia.sawDisabled
        SystemMediaService.shared.publish(snapshot(23))
        spin { recoveryClient.transport!.sent.count == 6 }
        let recovered = try decoded(SceneDaemonMediaSnapshotFrame.self, recoveryClient.transport!.sent[5])
        let recoveredResult = recoveryReceiver.receive(recovered)
        try acknowledge(recoveryClient, recoveredResult.acknowledgement)
        checks["off_on_recovers_without_wallpaper_reload"] = !recoveryClient.systemMedia.unavailable
            && recoveredResult.acknowledgement.accepted
            && recoveryClient.systemMedia.heartbeat != nil
            && recoveryClient.activeRequestID == request && !recoveryClient.transport!.terminated
        let renew = SceneDaemonMediaControl(scope: scope, operation: .renewLease,
            epoch: recovered.snapshot.epoch, revision: recovered.snapshot.revision)
        checks["confirmed_paused_session_can_renew_lease"] = recoveryReceiver.control(renew)
        recoveryReceiver.expireLease()
        recoveryInbox.clearMediaSession()
        checks["expired_receiver_refuses_stale_renewal"] = !recoveryReceiver.control(renew)
            && recoveryInbox.latest().properties?.title == ""
        recoveryClient.revokeSystemMediaDemand(generation: 1)

        let stableClient = SceneDaemonClient()
        stableClient.activeRequestID = request
        let stableBytes = Data([1, 2, 3])
        SystemMediaService.shared.snapshot = snapshot(30, art: stableBytes)
        try stableClient.handleSystemMediaDemand(payload(demand), generation: 1)
        spin { stableClient.transport!.sent.count == 1 }
        var stableReceiver = SceneDaemonMediaReceiver()
        stableReceiver.setDemand(demand)
        let stableFrame = try decoded(SceneDaemonMediaSnapshotFrame.self, stableClient.transport!.sent[0])
        try acknowledge(stableClient, stableReceiver.receive(stableFrame).acknowledgement)
        spin { stableClient.transport!.sent.count == 2 }
        let stableChunk = try decoded(SceneDaemonMediaArtworkChunk.self, stableClient.transport!.sent[1])
        try acknowledge(stableClient, stableReceiver.receive(stableChunk).acknowledgement)
        let beforeStablePromotion = SystemMediaService.shared.unsubscribeCount
        stableReceiver.setDemand(promoted)
        try stableClient.handleSystemMediaDemand(payload(promoted), generation: 1)
        spin { stableClient.transport!.sent.count == 3 }
        let promotedFrame = try decoded(SceneDaemonMediaSnapshotFrame.self, stableClient.transport!.sent[2])
        let promotedResult = stableReceiver.receive(promotedFrame)
        try acknowledge(stableClient, promotedResult.acknowledgement)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        checks["same_music_scene_promotion_does_not_retransmit_image"] = stableClient.transport!.sent.count == 3
            && promotedFrame.artwork == stableFrame.artwork
            && promotedResult.publication?.current == stableBytes
            && SystemMediaService.shared.unsubscribeCount == beforeStablePromotion
        stableReceiver.expireLease()
        let stableRenew = SceneDaemonMediaControl(scope: promotedScope, operation: .renewLease,
            epoch: promotedFrame.snapshot.epoch, revision: promotedFrame.snapshot.revision)
        checks["expired_current_scope_requests_replay"] = !stableReceiver.control(stableRenew)
            && stableReceiver.requiresReplay(after: stableRenew)
        let oldRenew = SceneDaemonMediaControl(scope: scope, operation: .renewLease,
            epoch: promotedFrame.snapshot.epoch, revision: promotedFrame.snapshot.revision)
        checks["expired_old_scope_cannot_request_replay"] = !stableReceiver.control(oldRenew)
            && !stableReceiver.requiresReplay(after: oldRenew)
        let staleVersionRenew = SceneDaemonMediaControl(scope: promotedScope, operation: .renewLease,
            epoch: promotedFrame.snapshot.epoch, revision: promotedFrame.snapshot.revision - 1)
        checks["expired_old_revision_cannot_request_replay"] = !stableReceiver.control(staleVersionRenew)
            && !stableReceiver.requiresReplay(after: staleVersionRenew)
        try stableClient.handleSystemMediaReplayRequest(payload(promotedScope), generation: 1)
        try stableClient.handleSystemMediaReplayRequest(payload(promotedScope), generation: 1)
        spin { stableClient.transport!.sent.count == 4 }
        let leaseReplay = try decoded(SceneDaemonMediaSnapshotFrame.self, stableClient.transport!.sent[3])
        let leaseReplayResult = stableReceiver.receive(leaseReplay)
        checks["receiver_requests_missing_art_even_when_sender_cached_it"] = leaseReplayResult.acknowledgement.nextArtworkIndex == 0
            && leaseReplayResult.publication?.current == nil
        try acknowledge(stableClient, leaseReplayResult.acknowledgement)
        spin { stableClient.transport!.sent.count == 5 }
        let leaseChunk = try decoded(SceneDaemonMediaArtworkChunk.self, stableClient.transport!.sent[4])
        let leaseChunkResult = stableReceiver.receive(leaseChunk)
        checks["metadata_replay_restores_expired_art_once"] = leaseChunk.index == 0
            && leaseChunkResult.publication?.current == stableBytes
            && stableClient.transport!.sent.count == 5
        try acknowledge(stableClient, leaseChunkResult.acknowledgement)
        try stableClient.handleSystemMediaReplayRequest(payload(scope), generation: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        checks["stale_replay_event_cannot_restart_current_art"] = stableClient.transport!.sent.count == 5
        stableClient.revokeSystemMediaDemand(generation: 1)
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
