import CryptoKit
import Foundation

/// Single bounded assembly, with metadata publication independent of artwork.
/// All writes still enter the one Scene inbox used by scripts and rendering.
nonisolated struct SceneDaemonMediaReceiver {
    struct Result {
        let acknowledgement: SceneDaemonMediaAcknowledgement
        let publication: SystemMediaSnapshotStore.Snapshot?
    }

    private(set) var demand: SceneSystemMediaDemand?
    private var scope: SceneDaemonMediaScope?
    private var latest: SystemMediaSnapshot?
    private var artwork: SceneDaemonMediaArtwork?
    private var completedArtwork: Data?
    private var pendingArtwork = Data()
    private var nextIndex = 0
    private var hasher = SHA256()
    private var cleared = false
    private var artworkRejected = false

    mutating func setDemand(_ demand: SceneSystemMediaDemand) {
        guard self.demand != demand else { return }
        let preservesSession = self.demand != nil && demand.requiresMedia
        self.demand = demand.requiresMedia ? demand : nil
        scope = nil
        if preservesSession {
            // Keep only a fully committed image. An unfinished old-scope
            // transfer always restarts at piece zero in the new scope.
            pendingArtwork = Data()
            nextIndex = 0
            hasher = SHA256()
            artworkRejected = false
        } else {
            latest = nil
            cleared = false
            resetArtwork(nil)
        }
    }

    mutating func receive(_ frame: SceneDaemonMediaSnapshotFrame) -> Result {
        let accepted = accepts(frame)
        var ack = SceneDaemonMediaAcknowledgement(
            scope: frame.scope, kind: .snapshot, epoch: frame.snapshot.epoch,
            revision: frame.snapshot.revision, transferID: frame.artwork?.transferID,
            index: nil, accepted: accepted
        )
        guard accepted else { return .init(acknowledgement: ack, publication: nil) }
        scope = frame.scope
        let previous = latest
        let sameSession = previous.map {
            $0.epoch == frame.snapshot.epoch
                && $0.sourceID == frame.snapshot.sourceID
                && $0.sessionID == frame.snapshot.sessionID
                && $0.sessionGeneration == frame.snapshot.sessionGeneration
                && $0.media.generation == frame.snapshot.media.generation
        } ?? false
        let nextArtwork = validatedArtwork(frame)
        if !sameSession || artwork != nextArtwork { resetArtwork(nextArtwork) }
        latest = frame.snapshot
        cleared = false
        if nextArtwork != nil, completedArtwork == nil, !artworkRejected {
            ack.nextArtworkIndex = nextIndex
        }
        var publication = frame.snapshot.media
        publication.current = completedArtwork
        return .init(acknowledgement: ack, publication: publication)
    }

    mutating func receive(_ chunk: SceneDaemonMediaArtworkChunk) -> Result {
        var accepted = false
        var publication: SystemMediaSnapshotStore.Snapshot?
        if chunk.scope == scope, chunk.scope.demand == demand,
           let artwork, artwork.transferID == chunk.transferID,
           completedArtwork == nil, chunk.index == nextIndex,
           !chunk.bytes.isEmpty, chunk.bytes.count <= SceneDaemonMediaWire.maximumChunkBytes,
           chunk.bytes.count <= artwork.byteCount - pendingArtwork.count {
            pendingArtwork.append(chunk.bytes)
            hasher.update(data: chunk.bytes)
            nextIndex += 1
            accepted = true
            if pendingArtwork.count == artwork.byteCount {
                let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                if digest == artwork.sha256 {
                    completedArtwork = pendingArtwork
                    publication = latest?.media
                    publication?.current = completedArtwork
                } else {
                    accepted = false
                    artworkRejected = true
                }
                pendingArtwork = Data()
            }
        }
        let ack = SceneDaemonMediaAcknowledgement(
            scope: chunk.scope, kind: .artwork, epoch: latest?.epoch ?? 0,
            revision: latest?.revision ?? 0, transferID: chunk.transferID,
            index: chunk.index, accepted: accepted
        )
        return .init(acknowledgement: ack, publication: publication)
    }

    private func accepts(_ frame: SceneDaemonMediaSnapshotFrame) -> Bool {
        guard frame.scope.demand == demand, frame.scope.transportGeneration > 0,
              scope.map({ $0 == frame.scope }) != false,
              frame.snapshot.media.current == nil, frame.snapshot.webThumbnail == nil,
              frame.snapshot.epoch > 0, frame.snapshot.revision > 0 else { return false }
        if let latest {
            guard frame.snapshot.epoch >= latest.epoch else { return false }
            if frame.snapshot.epoch == latest.epoch {
                guard frame.snapshot.revision > latest.revision
                    || ((cleared || scope == nil) && frame.snapshot == latest) else { return false }
            }
        }
        if let latest, frame.snapshot.epoch == latest.epoch {
            guard frame.snapshot.sessionGeneration >= latest.sessionGeneration else { return false }
            if frame.snapshot.sessionGeneration == latest.sessionGeneration {
                guard frame.snapshot.sourceID == latest.sourceID,
                      frame.snapshot.sessionID == latest.sessionID else { return false }
            }
        }
        return true
    }

    mutating func control(_ control: SceneDaemonMediaControl) -> Bool {
        guard control.scope.demand == demand,
              control.scope.transportGeneration > 0,
              scope.map({ $0 == control.scope }) != false else { return false }
        switch control.operation {
        case .clear:
            resetArtwork(nil)
            cleared = true
            return true
        case .renewLease:
            return !cleared && latest?.epoch == control.epoch && latest?.revision == control.revision
        }
    }

    mutating func expireLease() {
        resetArtwork(nil)
        cleared = true
    }

    func requiresReplay(after control: SceneDaemonMediaControl) -> Bool {
        control.operation == .renewLease && control.scope == scope
            && control.scope.demand == demand && cleared
            && latest?.epoch == control.epoch && latest?.revision == control.revision
    }

    private func validatedArtwork(_ frame: SceneDaemonMediaSnapshotFrame) -> SceneDaemonMediaArtwork? {
        guard let artwork = frame.artwork, frame.snapshot.enabled, frame.snapshot.sessionID != nil,
              artwork.byteCount > 0, artwork.byteCount <= SceneDaemonMediaWire.maximumArtworkBytes,
              artwork.sha256.utf8.count == 64,
              artwork.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return artwork
    }

    private mutating func resetArtwork(_ next: SceneDaemonMediaArtwork?) {
        artwork = next
        completedArtwork = nil
        pendingArtwork = Data()
        if let next { pendingArtwork.reserveCapacity(next.byteCount) }
        nextIndex = 0
        hasher = SHA256()
        artworkRejected = false
    }
}
