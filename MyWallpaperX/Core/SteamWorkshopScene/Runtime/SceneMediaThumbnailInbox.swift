import Foundation
import os.lock

/// Producer-agnostic media artwork ingress. Encoded artwork and any official
/// event-derived secondary color share one generation; playback has an
/// independent generation because it can change without replacing artwork.
final class SceneMediaThumbnailInbox: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let current: Data?
        let secondaryColor: SIMD3<Double>?
        let generation: UInt64
        let playbackState: Int?
        let playbackGeneration: UInt64

        static let empty = Snapshot(
            current: nil,
            secondaryColor: nil,
            generation: 0,
            playbackState: nil,
            playbackGeneration: 0
        )
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
    func publish(
        _ encodedImage: Data,
        secondaryColor: SIMD3<Double>? = nil
    ) -> Bool {
        guard !encodedImage.isEmpty,
              encodedImage.count <= Self.maximumEncodedByteCount,
              secondaryColor.map(Self.isNormalizedColor) != false else {
            return false
        }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.current != encodedImage
                || snapshot.secondaryColor != secondaryColor else { return true }
        snapshot = Snapshot(
            current: encodedImage,
            secondaryColor: secondaryColor,
            generation: snapshot.generation &+ 1,
            playbackState: snapshot.playbackState,
            playbackGeneration: snapshot.playbackGeneration
        )
        return true
    }

    @discardableResult
    func publishPlaybackState(_ state: Int) -> Bool {
        guard (0...2).contains(state) else { return false }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.playbackState != state else { return true }
        snapshot = Snapshot(
            current: snapshot.current,
            secondaryColor: snapshot.secondaryColor,
            generation: snapshot.generation,
            playbackState: state,
            playbackGeneration: snapshot.playbackGeneration &+ 1
        )
        return true
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.current != nil else { return }
        snapshot = Snapshot(
            current: nil,
            secondaryColor: .zero,
            generation: snapshot.generation &+ 1,
            playbackState: snapshot.playbackState,
            playbackGeneration: snapshot.playbackGeneration
        )
    }

    nonisolated private static func isNormalizedColor(
        _ value: SIMD3<Double>
    ) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
            && (0...1).contains(value.x)
            && (0...1).contains(value.y)
            && (0...1).contains(value.z)
    }
}
