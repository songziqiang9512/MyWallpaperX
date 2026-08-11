import Foundation
import os.lock

/// Producer-agnostic media artwork ingress. The platform integration publishes
/// encoded PNG/JPEG bytes atomically; every Scene surface observes the same
/// current artwork and generation.
final class SceneMediaThumbnailInbox: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let current: Data?
        let generation: UInt64

        static let empty = Snapshot(current: nil, generation: 0)
    }

    static let shared = SceneMediaThumbnailInbox()
    nonisolated static let maximumEncodedByteCount = 16 * 1_024 * 1_024

    private var lock = os_unfair_lock_s()
    private var snapshot = Snapshot.empty

    init() {}

    func latest() -> Snapshot {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return snapshot
    }

    @discardableResult
    func publish(_ encodedImage: Data) -> Bool {
        guard !encodedImage.isEmpty,
              encodedImage.count <= Self.maximumEncodedByteCount else {
            return false
        }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.current != encodedImage else { return true }
        snapshot = Snapshot(
            current: encodedImage,
            generation: snapshot.generation &+ 1
        )
        return true
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.current != nil else { return }
        snapshot = Snapshot(
            current: nil,
            generation: snapshot.generation &+ 1
        )
    }
}
