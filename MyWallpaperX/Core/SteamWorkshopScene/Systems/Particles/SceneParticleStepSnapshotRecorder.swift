import Foundation

nonisolated struct SceneParticleStepSnapshotPolicy: Hashable, Sendable {
    let interval: TimeInterval
    let maximumSnapshots: Int

    nonisolated init?(interval: TimeInterval, maximumSnapshots: Int) {
        guard interval.isFinite, interval > 0, maximumSnapshots > 1 else {
            return nil
        }
        self.interval = interval
        self.maximumSnapshots = maximumSnapshots
    }
}

nonisolated struct SceneParticleStepParticle: Equatable, Sendable {
    let id: UInt64
    let position: SIMD3<Float>
    let size: Float
    let color: SIMD3<Float>
    let alpha: Float

    nonisolated init(_ state: SceneParticleState) {
        id = state.id
        position = SIMD3(
            Float(state.position.x),
            Float(state.position.y),
            Float(state.position.z)
        )
        size = Float(state.size)
        color = SIMD3(
            Float(state.color.x),
            Float(state.color.y),
            Float(state.color.z)
        )
        alpha = Float(state.alpha)
    }
}

nonisolated struct SceneParticleStepSnapshot: Equatable, Sendable {
    let duration: TimeInterval
    let particles: [SceneParticleStepParticle]
}

nonisolated struct SceneParticleStepSnapshotRecorder: Sendable {
    private struct Stream: Sendable {
        let policy: SceneParticleStepSnapshotPolicy
        var snapshots: [SceneParticleStepSnapshot] = []
        var pendingDuration: TimeInterval = 0
    }

    private var streams: [Stream]

    nonisolated init(policies: [SceneParticleStepSnapshotPolicy]) {
        var seen: Set<SceneParticleStepSnapshotPolicy> = []
        streams = policies.filter { seen.insert($0).inserted }.map { Stream(policy: $0) }
    }

    var emissionStorageBytes: Int {
        128 + streams.capacity * MemoryLayout<Stream>.stride
            + streams.reduce(0) { result, stream in
                result + stream.snapshots.capacity * MemoryLayout<SceneParticleStepSnapshot>.stride
                    + stream.snapshots.reduce(0) {
                        $0 + $1.particles.capacity * MemoryLayout<SceneParticleStepParticle>.stride
                    }
            }
    }

    nonisolated mutating func clear() {
        for index in streams.indices {
            streams[index].snapshots.removeAll(keepingCapacity: true)
            streams[index].pendingDuration = 0
        }
    }

    nonisolated mutating func record(
        duration: TimeInterval,
        particles: [SceneParticleState]
    ) {
        guard duration.isFinite, duration > 0 else { return }
        recordSamples(duration: duration, particles: particles, includesPartial: false)
    }

    nonisolated mutating func consume(
        particles: [SceneParticleState]
    ) -> [SceneParticleStepSnapshotPolicy: [SceneParticleStepSnapshot]] {
        // Only materialize samples retained by a history, or the final
        // partial interval requested by the consumer. Intermediate simulation
        // steps have no snapshot consumer and need no particle conversion.
        recordSamples(duration: 0, particles: particles, includesPartial: true)
        var result: [SceneParticleStepSnapshotPolicy: [SceneParticleStepSnapshot]] = [:]
        for index in streams.indices where !streams[index].snapshots.isEmpty {
            result[streams[index].policy] = streams[index].snapshots
            streams[index].snapshots.removeAll(keepingCapacity: true)
        }
        return result
    }

    private nonisolated mutating func recordSamples(
        duration: TimeInterval,
        particles: [SceneParticleState],
        includesPartial: Bool
    ) {
        var convertedParticles: [SceneParticleStepParticle]?
        for index in streams.indices {
            streams[index].pendingDuration += duration
            let pendingDuration = streams[index].pendingDuration
            let policy = streams[index].policy
            guard pendingDuration > 0,
                  includesPartial || pendingDuration + 1e-12 >= policy.interval else { continue }
            // Due policies retain the same immutable particle array.
            let sample = convertedParticles ?? particles.map(SceneParticleStepParticle.init)
            convertedParticles = sample
            streams[index].snapshots.append(.init(duration: pendingDuration, particles: sample))
            streams[index].pendingDuration = 0
            let overflow = streams[index].snapshots.count - policy.maximumSnapshots
            if overflow > 0 {
                streams[index].snapshots.removeFirst(overflow)
            }
        }
    }
}
