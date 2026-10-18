import Foundation

/// Hashing may overlap a transport replacement. A cancelled old demand must
/// not leave an unbounded train of artwork jobs on the utility queue.
nonisolated private final class SceneDaemonMediaPreparationQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mywallpaperx.scene-media-ipc", qos: .utility)
    private let lock = NSLock()
    private var pending: (@Sendable () -> Void)?
    private var scheduled = false

    func submit(_ work: @Sendable @escaping () -> Void) {
        lock.lock()
        pending = work
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if shouldSchedule { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let work = pending else {
                scheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            work()
        }
    }
}

@MainActor
final class SceneDaemonMediaClientState {
    nonisolated struct Prepared: Sendable {
        let frame: SceneDaemonMediaSnapshotFrame
        let bytes: Data?
    }
    nonisolated struct Transfer: Sendable {
        let artwork: SceneDaemonMediaArtwork
        let bytes: Data
        var offset = 0
        var index = 0
    }
    let subscriptionID = UUID()
    fileprivate let preparationQueue = SceneDaemonMediaPreparationQueue()
    var scope: SceneDaemonMediaScope?
    var lastDemand: SceneDaemonMediaScope?
    var pending: SystemMediaSnapshot?
    var prepared: Prepared?
    var cached: Prepared?
    var preparing: UUID?
    var transfer: Transfer?
    var completed: SceneDaemonMediaArtwork?
    var awaiting: SceneDaemonMediaAcknowledgement?
    var timeout: DispatchWorkItem?
    var retry: DispatchWorkItem?
    var retryBudget = 1
    var heartbeat: Timer?
    var leaseVersion: (epoch: UInt64, revision: UInt64)?
    var sawDisabled = false
    var unavailable = false
}

@MainActor
extension SceneDaemonClient {
    func handleSystemMediaDemand(_ payload: [String: Any], generation: UInt64) {
        guard endpointReady, generation == sessionGeneration, transport != nil,
              !expectedTerminationGenerations.contains(generation),
              retiringTransports[generation] == nil,
              let demand = SceneDaemonMediaWire.decode(
                SceneSystemMediaDemand.self, payload: payload,
                maximumBytes: SceneDaemonMediaWire.maximumMetadataBytes
              ) else { return }
        let knownRequests = Set([activeRequestID, pendingRequestID].compactMap { $0 })
        guard demand.requests.isSubset(of: knownRequests) else { return }
        let scope = SceneDaemonMediaScope(demand: demand, transportGeneration: generation)
        if let last = systemMedia.lastDemand, last.transportGeneration == generation {
            guard demand.generation > last.demand.generation || scope == last else { return }
        }
        systemMedia.lastDemand = scope
        guard systemMedia.scope != scope else { return }
        if demand.requiresMedia, systemMedia.scope?.transportGeneration == generation,
           !systemMedia.unavailable {
            // Rebind the transport identity without dropping the service lease.
            // A media -> media Scene promotion must not stop shared collection,
            // discard its selected session, or retry authorization.
            resetSystemMediaPipeline(preservingArtwork: true)
        } else if let previous = systemMedia.scope {
            revokeSystemMediaDemand(generation: previous.transportGeneration)
        }
        guard demand.requiresMedia else { return }
        systemMedia.scope = scope
        systemMedia.unavailable = false
        systemMedia.retryBudget = 1
        subscribeSystemMedia(scope: scope, needsMedia: true)
    }

    private func subscribeSystemMedia(scope: SceneDaemonMediaScope, needsMedia: Bool) {
        SystemMediaService.shared.subscribe(systemMedia.subscriptionID, needsMedia: needsMedia) { [weak self] snapshot in
            guard let self, self.systemMedia.scope == scope else { return }
            if self.systemMedia.unavailable {
                if !snapshot.enabled { self.systemMedia.sawDisabled = true }
                else if self.systemMedia.sawDisabled {
                    self.systemMedia.retryBudget = 1
                    self.rebuildSystemMedia(scope: scope)
                }
                return
            }
            self.systemMedia.pending = snapshot
            self.prepareSystemMediaIfNeeded()
        }
    }

    func revokeSystemMediaDemand(generation: UInt64) {
        guard systemMedia.scope?.transportGeneration == generation else { return }
        SystemMediaService.shared.unsubscribe(systemMedia.subscriptionID)
        resetSystemMediaPipeline()
    }

    private func resetSystemMediaPipeline(preservingArtwork: Bool = false) {
        let cached = preservingArtwork ? systemMedia.cached : nil
        let completed = preservingArtwork ? systemMedia.completed : nil
        systemMedia.timeout?.cancel()
        systemMedia.timeout = nil
        systemMedia.retry?.cancel()
        systemMedia.retry = nil
        systemMedia.heartbeat?.invalidate()
        systemMedia.heartbeat = nil
        systemMedia.leaseVersion = nil
        systemMedia.sawDisabled = false
        systemMedia.scope = nil
        systemMedia.pending = nil
        systemMedia.prepared = nil
        systemMedia.cached = cached
        systemMedia.preparing = nil
        systemMedia.transfer = nil
        systemMedia.completed = completed
        systemMedia.awaiting = nil
        systemMedia.unavailable = false
    }

    private func prepareSystemMediaIfNeeded() {
        guard !systemMedia.unavailable, systemMedia.preparing == nil,
              let scope = systemMedia.scope, let pending = systemMedia.pending else { return }
        systemMedia.pending = nil
        let preparationID = UUID()
        systemMedia.preparing = preparationID
        let cached = systemMedia.cached
        systemMedia.preparationQueue.submit { [weak self] in
            let bytes = pending.enabled ? pending.media.current : nil
            let sameArtwork = cached.map {
                $0.frame.snapshot.epoch == pending.epoch
                    && $0.frame.snapshot.sourceID == pending.sourceID
                    && $0.frame.snapshot.sessionID == pending.sessionID
                    && $0.frame.snapshot.sessionGeneration == pending.sessionGeneration
                    && $0.frame.snapshot.media.generation == pending.media.generation
            } ?? false
            let artwork: SceneDaemonMediaArtwork?
            if sameArtwork { artwork = cached?.frame.artwork }
            else if let bytes, !bytes.isEmpty, bytes.count <= SceneDaemonMediaWire.maximumArtworkBytes {
                artwork = .init(transferID: UUID(), byteCount: bytes.count,
                    sha256: SceneDaemonMediaWire.digest(bytes))
            } else { artwork = nil }
            var metadata = pending
            metadata.media.current = nil
            metadata.webThumbnail = nil
            let prepared = SceneDaemonMediaClientState.Prepared(
                frame: .init(scope: scope, snapshot: metadata, artwork: artwork),
                bytes: artwork == nil ? nil : bytes
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.systemMedia.scope == scope,
                      self.systemMedia.preparing == preparationID else { return }
                self.systemMedia.preparing = nil
                self.systemMedia.cached = prepared
                // If a newer full snapshot arrived during hashing, prepare it
                // first. No stale metadata or artwork enters the transport.
                if self.systemMedia.pending != nil { self.prepareSystemMediaIfNeeded() }
                else {
                    self.systemMedia.prepared = prepared
                    self.pumpSystemMedia()
                }
            }
        }
    }

    private func pumpSystemMedia() {
        guard !systemMedia.unavailable, endpointReady,
              let scope = systemMedia.scope,
              scope.transportGeneration == sessionGeneration,
              systemMedia.awaiting == nil else { return }
        if systemMedia.pending != nil || systemMedia.preparing != nil {
            prepareSystemMediaIfNeeded()
            return
        }
        do {
            let data: Data
            let acknowledgement: SceneDaemonMediaAcknowledgement
            if let prepared = systemMedia.prepared {
                systemMedia.prepared = nil
                let frame = prepared.frame
                if systemMedia.transfer?.artwork != frame.artwork { systemMedia.transfer = nil }
                if let artwork = frame.artwork, let bytes = prepared.bytes,
                   systemMedia.completed != artwork, systemMedia.transfer == nil {
                    systemMedia.transfer = .init(artwork: artwork, bytes: bytes)
                }
                if frame.artwork == nil { systemMedia.completed = nil }
                data = try SceneDaemonMediaWire.encode("publishSystemMedia", frame)
                acknowledgement = .init(scope: scope, kind: .snapshot,
                    epoch: frame.snapshot.epoch, revision: frame.snapshot.revision,
                    transferID: frame.artwork?.transferID, index: nil, accepted: true)
            } else if var transfer = systemMedia.transfer {
                let end = min(transfer.offset + SceneDaemonMediaWire.maximumChunkBytes, transfer.bytes.count)
                let chunk = SceneDaemonMediaArtworkChunk(scope: scope,
                    transferID: transfer.artwork.transferID, index: transfer.index,
                    bytes: transfer.bytes.subdata(in: transfer.offset ..< end))
                data = try SceneDaemonMediaWire.encode("publishSystemMediaArtwork", chunk)
                acknowledgement = .init(scope: scope, kind: .artwork,
                    epoch: 0, revision: 0, transferID: chunk.transferID,
                    index: chunk.index, accepted: true)
                transfer.offset = end
                transfer.index += 1
                systemMedia.transfer = transfer
            } else { return }
            systemMedia.awaiting = acknowledgement
            guard transport?.send(data) == true else {
                failSystemMediaTransportAdmission()
                return
            }
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.systemMedia.scope == scope,
                      self.systemMedia.awaiting == acknowledgement else { return }
                self.disableSystemMediaTransport(reason: "Scene media acknowledgement timed out", permitsRetry: true)
            }
            systemMedia.timeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        } catch {
            disableSystemMediaTransport(reason: "Scene media encoding failed: \(error)", permitsRetry: false)
        }
    }

    func handleSystemMediaAcknowledgement(_ payload: [String: Any], generation: UInt64) {
        guard generation == sessionGeneration,
              let ack = SceneDaemonMediaWire.decode(SceneDaemonMediaAcknowledgement.self,
                payload: payload, maximumBytes: SceneDaemonMediaWire.maximumMetadataBytes),
              let awaiting = systemMedia.awaiting,
              ack.scope == systemMedia.scope, ack.scope == awaiting.scope,
              ack.kind == awaiting.kind, ack.transferID == awaiting.transferID,
              ack.index == awaiting.index,
              (ack.kind == .artwork || (ack.epoch == awaiting.epoch && ack.revision == awaiting.revision)) else { return }
        systemMedia.timeout?.cancel()
        systemMedia.timeout = nil
        systemMedia.awaiting = nil
        if !ack.accepted {
            // A rejected image is optional. Keep metadata updates live, while
            // dropping just this transfer; source changes can try fresh art.
            if ack.kind == .artwork {
                systemMedia.completed = systemMedia.transfer?.artwork
                systemMedia.transfer = nil
            } else {
                disableSystemMediaTransport(reason: "Scene rejected media metadata", permitsRetry: true)
                return
            }
        } else if ack.kind == .snapshot {
            reconcileSystemMediaArtwork(ack)
            systemMedia.leaseVersion = (ack.epoch, ack.revision)
            startSystemMediaHeartbeat(scope: ack.scope)
        } else if ack.kind == .artwork, let transfer = systemMedia.transfer,
                  transfer.offset == transfer.bytes.count {
            systemMedia.completed = transfer.artwork
            systemMedia.transfer = nil
        }
        // Yield between chunks so playback controls get a main-run-loop turn.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated { self?.pumpSystemMedia() }
        }
    }

    func handleSystemMediaReplayRequest(_ payload: [String: Any], generation: UInt64) {
        guard generation == sessionGeneration, !systemMedia.unavailable,
              systemMedia.awaiting == nil, systemMedia.pending == nil,
              systemMedia.preparing == nil, systemMedia.prepared == nil,
              let scope = SceneDaemonMediaWire.decode(SceneDaemonMediaScope.self,
                payload: payload, maximumBytes: SceneDaemonMediaWire.maximumMetadataBytes),
              scope == systemMedia.scope else { return }
        systemMedia.pending = SystemMediaService.shared.currentSnapshot
        prepareSystemMediaIfNeeded()
    }

    private func reconcileSystemMediaArtwork(_ ack: SceneDaemonMediaAcknowledgement) {
        let candidate: (SceneDaemonMediaArtwork, Data)?
        if let transfer = systemMedia.transfer, transfer.artwork.transferID == ack.transferID {
            candidate = (transfer.artwork, transfer.bytes)
        } else if let cached = systemMedia.cached, let artwork = cached.frame.artwork,
                  let bytes = cached.bytes, artwork.transferID == ack.transferID {
            candidate = (artwork, bytes)
        } else { candidate = nil }
        guard let (artwork, bytes) = candidate else { return }
        if let index = ack.nextArtworkIndex, index >= 0,
           index <= (bytes.count - 1) / SceneDaemonMediaWire.maximumChunkBytes {
            let offset = index * SceneDaemonMediaWire.maximumChunkBytes
            systemMedia.completed = nil
            systemMedia.transfer = .init(artwork: artwork, bytes: bytes, offset: offset, index: index)
        } else {
            systemMedia.completed = artwork
            systemMedia.transfer = nil
        }
    }

    private func startSystemMediaHeartbeat(scope: SceneDaemonMediaScope) {
        guard systemMedia.heartbeat == nil else { return }
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.systemMedia.scope == scope,
                      !self.systemMedia.unavailable, let version = self.systemMedia.leaseVersion else { return }
                self.sendSystemMediaControl(.init(scope: scope, operation: .renewLease,
                    epoch: version.epoch, revision: version.revision))
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        systemMedia.heartbeat = timer
    }

    @discardableResult
    private func sendSystemMediaControl(_ control: SceneDaemonMediaControl) -> Bool {
        do {
            let data = try SceneDaemonMediaWire.encode("controlSystemMedia", control)
            guard transport?.send(data) == true else {
                failSystemMediaTransportAdmission()
                return false
            }
            return true
        } catch {
            publishFailure(code: "system-media-unavailable", message: "Scene media control encoding failed: \(error)")
            return false
        }
    }

    private func failSystemMediaTransportAdmission() {
        transport?.terminate()
        if let scope = systemMedia.scope { revokeSystemMediaDemand(generation: scope.transportGeneration) }
        publishFailure(code: "system-media-unavailable", message: "Scene media command was not admitted")
    }

    private func rebuildSystemMedia(scope: SceneDaemonMediaScope) {
        guard systemMedia.scope == scope, systemMedia.unavailable else { return }
        resetSystemMediaPipeline()
        systemMedia.scope = scope
        subscribeSystemMedia(scope: scope, needsMedia: true)
    }

    private func disableSystemMediaTransport(reason: String, permitsRetry: Bool) {
        guard let scope = systemMedia.scope else { return }
        systemMedia.unavailable = true
        systemMedia.timeout?.cancel()
        systemMedia.timeout = nil
        systemMedia.heartbeat?.invalidate()
        systemMedia.heartbeat = nil
        systemMedia.leaseVersion = nil
        systemMedia.awaiting = nil
        systemMedia.pending = nil
        systemMedia.prepared = nil
        systemMedia.cached = nil
        systemMedia.preparing = nil
        systemMedia.transfer = nil
        systemMedia.completed = nil
        publishFailure(code: "system-media-unavailable", message: reason)
        guard sendSystemMediaControl(.init(scope: scope, operation: .clear, epoch: 0, revision: 0)) else { return }
        // Keep only the setting observation: turning the feature off and back
        // on can recover this optional channel without reloading the wallpaper.
        subscribeSystemMedia(scope: scope, needsMedia: false)
        if permitsRetry, systemMedia.retryBudget > 0 {
            systemMedia.retryBudget -= 1
            let retry = DispatchWorkItem { [weak self] in self?.rebuildSystemMedia(scope: scope) }
            systemMedia.retry = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: retry)
        }
    }
}
