import Foundation

nonisolated struct SceneParticleStepSnapshotPolicy: Equatable, Sendable {
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
    private let policy: SceneParticleStepSnapshotPolicy
    private var snapshots: [SceneParticleStepSnapshot] = []
    private var pendingDuration: TimeInterval = 0
    private var pendingParticles: [SceneParticleStepParticle] = []

    nonisolated init(policy: SceneParticleStepSnapshotPolicy) {
        self.policy = policy
    }

    nonisolated mutating func record(
        duration: TimeInterval,
        particles: [SceneParticleState]
    ) {
        guard duration.isFinite, duration > 0 else { return }
        pendingDuration += duration
        pendingParticles = particles.map(SceneParticleStepParticle.init)
        if pendingDuration + 1e-12 >= policy.interval {
            commitPending()
        }
    }

    nonisolated mutating func consume() -> [SceneParticleStepSnapshot] {
        commitPending()
        defer { snapshots.removeAll(keepingCapacity: true) }
        return snapshots
    }

    private nonisolated mutating func commitPending() {
        guard pendingDuration > 0 else { return }
        snapshots.append(.init(
            duration: pendingDuration,
            particles: pendingParticles
        ))
        pendingDuration = 0
        if snapshots.count > policy.maximumSnapshots {
            snapshots.removeFirst(snapshots.count - policy.maximumSnapshots)
        }
    }
}
