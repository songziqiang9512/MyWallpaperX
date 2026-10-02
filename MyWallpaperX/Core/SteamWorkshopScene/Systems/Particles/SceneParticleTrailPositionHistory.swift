import Foundation

/// Fixed-capacity per-particle position rings backing Sprite Trail direction
/// smoothing. One entry per live particle, maintained in lockstep with
/// `particles`: seeded on emit, moved by the death compaction, and recorded
/// once per fixed step after integration. Because the store only ever changes
/// inside `step`, capturing it beside `particles` in `FrameSnapshot` rolls a
/// rejected frame back as one unit (particle state, rings, and RNG together).
nonisolated struct SceneParticleTrailPositionHistory: Sendable {
    private let capacity: Int
    private var slots: [SIMD3<Double>] = []
    /// Index of the most recently written slot per particle. Seeding fills
    /// every slot with the birth position, so the ring is valid from birth and
    /// the oldest readable slot is a whole-life chord until eight real samples
    /// have accumulated.
    private var heads: [UInt8] = []

    nonisolated init(capacity: Int) {
        self.capacity = max(0, min(capacity, Int(UInt8.max)))
    }

    var isEmpty: Bool { slots.isEmpty }
    var entrySlotCount: Int { capacity }
    /// Conservative COW/growth reservation, before any candidate writes.
    func emissionStorageBytes(adding count: Int) -> Int {
        2 * (max(slots.capacity, slots.count + count * capacity) * MemoryLayout<SIMD3<Double>>.stride
             + max(heads.capacity, heads.count + count) * MemoryLayout<UInt8>.stride) + 128
    }

    /// Appends one ring seeded with the particle's final birth position.
    /// Must be called for every appended particle before the next `record`.
    nonisolated mutating func seed(position: SIMD3<Double>) {
        guard capacity > 0 else { return }
        slots.append(contentsOf: repeatElement(position, count: capacity))
        heads.append(UInt8(capacity - 1))
    }

    /// Mirrors one particle relocation of the death compaction.
    nonisolated mutating func moveEntry(from source: Int, to destination: Int) {
        guard !slots.isEmpty else { return }
        for slot in 0..<capacity {
            slots[destination * capacity + slot] = slots[source * capacity + slot]
        }
        heads[destination] = heads[source]
    }

    /// Drops the rings of compacted (dead) tail particles.
    nonisolated mutating func removeEntries(beyond liveCount: Int) {
        guard !slots.isEmpty else { return }
        let excess = heads.count - liveCount
        guard excess > 0 else { return }
        slots.removeLast(excess * capacity)
        heads.removeLast(excess)
    }

    /// Writes each particle's post-integration position into its ring.
    nonisolated mutating func record(_ particles: [SceneParticleState]) {
        guard !slots.isEmpty else { return }
        for index in particles.indices {
            let head = (Int(heads[index]) + 1) % capacity
            heads[index] = UInt8(head)
            slots[index * capacity + head] = particles[index].position
        }
    }

    /// Position of the oldest retained sample for the entry at `index`.
    nonisolated func oldestPosition(entry index: Int) -> SIMD3<Double> {
        slots[index * capacity + (Int(heads[index]) + 1) % capacity]
    }
}

/// One Sprite Trail orientation sample: the chord from the oldest retained
/// history position to the particle's current position.
nonisolated struct SceneParticleTrailDirectionSample: Sendable {
    let id: UInt64
    let direction: SIMD3<Double>
}
