import Foundation

/// Particle storage for one simulator. The live population is the suffix after
/// a dead prefix, so removing leading deaths only advances `head`. A bounded
/// compaction folds the prefix back into the allocation once it reaches
/// ``compactionThreshold``; the amortized cost per removed particle stays small
/// while every consumer still observes one contiguous, ordered live range.
nonisolated struct SceneParticleBuffer: RandomAccessCollection, Equatable, Sendable {
    typealias Element = SceneParticleState
    typealias Index = Int

    private static let compactionThreshold = 64

    private var storage: [SceneParticleState] = []
    private var head = 0

    nonisolated init() {}

    nonisolated init(_ values: [SceneParticleState]) {
        storage = values
    }

    @inline(__always) var startIndex: Int { 0 }
    @inline(__always) var endIndex: Int { storage.count - head }
    @inline(__always) subscript(position: Int) -> SceneParticleState {
        get { storage[head + position] }
        set { storage[head + position] = newValue }
    }

    /// Retained allocation in whole particles, including the dead prefix and
    /// free capacity; emission budgeting must reserve for it.
    var capacity: Int { storage.capacity }

    /// Shares the contiguous live range; retained views use Array's COW
    /// isolation when a later simulation step changes the storage.
    var liveParticles: ArraySlice<SceneParticleState> { storage[head...] }

    @inline(__always) nonisolated mutating func append(_ value: SceneParticleState) {
        storage.append(value)
    }

    nonisolated mutating func removeLast(_ count: Int) {
        storage.removeLast(count)
    }

    /// Removes `count` particles from the leading (oldest) side without moving
    /// the survivors unless the dead prefix reaches the compaction threshold.
    nonisolated mutating func removeLeading(_ count: Int) {
        guard count > 0 else { return }
        head += count
        if head >= Self.compactionThreshold {
            compact()
        }
    }

    nonisolated mutating func withUnsafeMutableBufferPointer<R>(
        _ body: (UnsafeMutableBufferPointer<SceneParticleState>) -> R
    ) -> R {
        storage.withUnsafeMutableBufferPointer { full in
            body(UnsafeMutableBufferPointer(rebasing: full[head...]))
        }
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in 0 ..< lhs.count where lhs[index] != rhs[index] {
            return false
        }
        return true
    }

    private nonisolated mutating func compact() {
        guard head > 0 else { return }
        if head == storage.count {
            storage.removeAll(keepingCapacity: true)
        } else {
            storage.removeFirst(head)
        }
        head = 0
    }
}
