import Foundation

/// One immutable session publication. Store channel generations describe field
/// changes; epoch/sessionGeneration reject asynchronous source and track ABA.
nonisolated struct SystemMediaSnapshot: Codable, Equatable, Sendable {
    var enabled: Bool
    var epoch: UInt64
    var revision: UInt64
    var sourceID: String?
    var sessionID: String?
    var sessionGeneration: UInt64
    var media: SystemMediaSnapshotStore.Snapshot
    var webThumbnail: String?

    static let empty = SystemMediaSnapshot(
        enabled: false, epoch: 0, revision: 0, sourceID: nil, sessionID: nil,
        sessionGeneration: 0, media: .empty, webThumbnail: nil
    )
}
