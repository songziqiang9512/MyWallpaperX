import CryptoKit
import Foundation

/// A fresh token identifies one daemon's exact promoted-session demand. Request
/// IDs tie it to authored launch intent; the token also rejects demand ABA.
nonisolated struct SceneSystemMediaDemand: Codable, Equatable, Sendable {
    let token: UUID
    let requests: Set<UUID>
    let generation: UInt64

    init(token: UUID, requests: Set<UUID>, generation: UInt64 = 1) {
        self.token = token
        self.requests = requests
        self.generation = generation
    }

    var requiresMedia: Bool { !requests.isEmpty }
}

@MainActor
final class SceneSystemMediaDemandRegistry {
    static let shared = SceneSystemMediaDemandRegistry()
    private var consumers: [UUID: UUID] = [:]
    private(set) var demand = SceneSystemMediaDemand(token: UUID(), requests: [], generation: 0)
    var didChange: ((SceneSystemMediaDemand) -> Void)?

    func acquire(_ lifecycleID: UUID, requestID: UUID) {
        guard consumers[lifecycleID] != requestID else { return }
        consumers[lifecycleID] = requestID
        changed()
    }

    func release(_ lifecycleID: UUID) {
        guard consumers.removeValue(forKey: lifecycleID) != nil else { return }
        changed()
    }

    private func changed() {
        demand = .init(token: UUID(), requests: Set(consumers.values), generation: demand.generation + 1)
        if !demand.requiresMedia { SceneMediaThumbnailInbox.shared.clearMediaSession() }
        didChange?(demand)
    }
}

nonisolated struct SceneDaemonMediaScope: Codable, Equatable, Sendable {
    let demand: SceneSystemMediaDemand
    let transportGeneration: UInt64
}

nonisolated struct SceneDaemonMediaArtwork: Codable, Equatable, Sendable {
    let transferID: UUID
    let byteCount: Int
    let sha256: String
}

nonisolated struct SceneDaemonMediaSnapshotFrame: Codable, Equatable, Sendable {
    let scope: SceneDaemonMediaScope
    let snapshot: SystemMediaSnapshot
    let artwork: SceneDaemonMediaArtwork?
}

nonisolated struct SceneDaemonMediaArtworkChunk: Codable, Equatable, Sendable {
    let scope: SceneDaemonMediaScope
    let transferID: UUID
    let index: Int
    let bytes: Data
}

nonisolated struct SceneDaemonMediaControl: Codable, Equatable, Sendable {
    enum Operation: String, Codable { case clear, renewLease }
    let scope: SceneDaemonMediaScope
    let operation: Operation
    let epoch: UInt64
    let revision: UInt64
}

nonisolated struct SceneDaemonMediaAcknowledgement: Codable, Equatable, Sendable {
    enum Kind: String, Codable { case snapshot, artwork }
    let scope: SceneDaemonMediaScope
    let kind: Kind
    let epoch: UInt64
    let revision: UInt64
    let transferID: UUID?
    let index: Int?
    let accepted: Bool
    /// Metadata ACKs request the first still-missing piece. Nil means the
    /// exact image is already present, absent, or locally rejected.
    var nextArtworkIndex: Int? = nil
}

/// This channel deliberately does not raise DaemonKit's 8 MiB control budget.
/// One acknowledged chunk is admitted at a time, leaving ordinary controls
/// ahead of the next chunk. Scene receives its original, bounded artwork bytes.
nonisolated enum SceneDaemonMediaWire {
    static let maximumChunkBytes = 256 * 1_024
    static let maximumMetadataBytes = 128 * 1_024
    static let maximumArtworkBytes = 16 * 1_024 * 1_024

    private struct Envelope<T: Encodable>: Encodable {
        let v = SceneDaemonProtocol.version
        let cmd: String
        let frame: T
    }

    static func encode<T: Encodable>(_ command: String, _ frame: T) throws -> Data {
        var data = try JSONEncoder().encode(Envelope(cmd: command, frame: frame))
        data.append(0x0A)
        return data
    }

    static func decode<T: Decodable>(
        _ type: T.Type, payload: [String: Any], maximumBytes: Int
    ) -> T? {
        guard let object = payload["frame"], JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              data.count <= maximumBytes else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
