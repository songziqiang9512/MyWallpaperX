import Foundation

/// Borrowed for one author cadence. Every mutation is executed by an existing
/// surface simulator; this value only retains checkpoints until owner admission.
nonisolated final class SceneParticlePlaybackTransaction {
    struct Instance {
        let surfaceID: UInt32
        let layerID: Int
        let simulator: SceneParticleSimulator
    }
    struct CommandIdentity: Hashable {
        let epoch: UInt64
        let ordinal: UInt32
        init(_ transition: SceneParticlePlaybackTransition) {
            epoch = transition.callbackEpoch; ordinal = transition.ordinal
        }
    }
    private struct Context {
        let values: [SceneParticleSimulator.EmissionContext]
        let bytes: Int
        let owner: UInt
    }
    private var baseRevisions: [UInt64] = []
    private let surfaceIDs: Set<UInt32>
    private var instances: [Instance] = []
    private let instancesProvider: () -> [Instance]
    private let metadataBytes: Int
    private var metadataReserved = false
    private let charge: (UInt64, Int) throws -> Void
    private let release: (Int) -> Void
    private let isCurrent: () -> Bool
    private let totalLiveCount: () throws -> Int
    private var contexts: [CommandIdentity: Context] = [:]
    private var candidates: [Int: SceneParticleSimulator.PlaybackCandidate] = [:]
    private var callbackEpoch: UInt64?
    private var callbackOrdinal: UInt32?
    private var finalPrepared = false

    init(instances: @autoclosure @escaping () -> [Instance], metadataBytes: Int = 8192, surfaceIDs: Set<UInt32>, charge: @escaping (UInt64, Int) throws -> Void,
         release: @escaping (Int) -> Void, isCurrent: @escaping () -> Bool,
         totalLiveCount: @escaping () throws -> Int) {
        self.instancesProvider = instances; self.metadataBytes = metadataBytes
        self.surfaceIDs = surfaceIDs
        self.charge = charge; self.release = release
        self.isCurrent = isCurrent; self.totalLiveCount = totalLiveCount
    }
    deinit { discard() }

    private func prepareMetadata() throws {
        guard !metadataReserved else { return }
        try charge(UInt64((metadataBytes + 63) / 64), metadataBytes)
        metadataReserved = true
        instances = instancesProvider()
        baseRevisions = instances.map { $0.simulator.playback.revision }
    }
    private func chargeTraversal() throws {
        try charge(UInt64(4 * instances.count + surfaceIDs.count + 1), 0)
    }
    private func identitiesAreCurrent() -> Bool {
        isCurrent() && instances.indices.allSatisfy { instances[$0].simulator.playback.revision == baseRevisions[$0] }
    }
    func discard() {
        discardCandidates()
        for context in contexts.values { release(context.bytes) }
        contexts.removeAll()
        callbackEpoch = nil; callbackOrdinal = nil
        instances.removeAll(); baseRevisions.removeAll()
        if metadataReserved { release(metadataBytes); metadataReserved = false }
    }
    func callbackBoundary(owner: UInt, discardOwner: Bool) {
        discardCandidates()
        callbackEpoch = nil; callbackOrdinal = nil
        if discardOwner {
            let keys = contexts.keys.filter { contexts[$0]?.owner == owner }
            for key in keys { if let value = contexts.removeValue(forKey: key) { release(value.bytes) } }
        }
    }

    private func discardCandidates() {
        for candidate in candidates.values { release(candidate.reservedBytes) }
        candidates.removeAll()
        finalPrepared = false
    }

    /// Prefix belongs to this callback only; earlier callbacks retain their
    /// captured inputs but never leak speculative live state into this query.
    func preview(
        owner: UInt, prefix: [SceneParticlePlaybackTransition],
        context: (Instance) throws -> SceneParticleSimulator.EmissionContext
    ) throws -> SceneParticlePlaybackObservation {
        try prepareMetadata(); try chargeTraversal()
        guard identitiesAreCurrent() else { throw SceneParticleEmissionFailure.staleIdentity }
        guard let command = prefix.last, command.action == .emit else { throw SceneParticleEmissionFailure.unavailable }
        if callbackEpoch != command.callbackEpoch {
            discardCandidates(); callbackOrdinal = nil; callbackEpoch = command.callbackEpoch
        }
        let key = CommandIdentity(command)
        let indices = instances.indices.filter { instances[$0].layerID == command.layerID }
        guard !indices.isEmpty, Set(indices.map { instances[$0].surfaceID }) == surfaceIDs else { throw SceneParticleEmissionFailure.unavailable }
        // Context storage is bounded by the actual participating instances.
        // The producer reserves its context construction before building values.
        let bytes = indices.reduce(MemoryLayout<Context>.stride + 1024) {
            $0 + instances[$1].simulator.emissionContextReservationBytes
        }
        try charge(UInt64((bytes + 63) / 64), bytes)
        do {
            let values = try indices.map { try context(instances[$0]) }
            guard values.reduce(MemoryLayout<Context>.stride + 128, { $0 + $1.storageBytes }) <= bytes else {
                throw SceneParticleEmissionFailure.budgetExceeded
            }
            contexts[key] = .init(values: values, bytes: bytes, owner: owner)
        } catch { release(bytes); throw error }
        let previous = candidates
        // Retaining previous candidate buffers can force a COW. apply reserves
        // the entire replacement before touching any simulator.
        do {
            for item in prefix where callbackOrdinal == nil || item.ordinal > callbackOrdinal! {
                let replaced = candidates
                try apply(item)
                for (index, old) in replaced where instances[index].layerID == item.layerID
                    && previous[index]?.state.playback.revision != old.state.playback.revision {
                    release(old.reservedBytes)
                }
            }
            callbackOrdinal = command.ordinal
            let observations = indices.compactMap { index -> SceneParticlePlaybackObservation? in
                guard let candidate = candidates[index] else { return nil }
                let sim = instances[index].simulator
                let current = sim.frameSnapshot(); defer { sim.restoreFrame(current) }
                sim.restoreFrame(candidate.state)
                return sim.playbackObservation
            }
            guard observations.count == indices.count, let first = observations.first else {
                throw SceneParticleEmissionFailure.unavailable
            }
            for (index, old) in previous where candidates[index]?.state.playback.revision != old.state.playback.revision {
                release(old.reservedBytes)
            }
            return .init(liveAny: observations.contains(where: \.liveAny),
                         emissionPending: observations.contains(where: \.emissionPending),
                         rearmHasWork: observations.contains(where: \.rearmHasWork),
                         intent: first.intent, revision: first.revision)
        } catch {
            for (index, value) in candidates {
                if previous[index]?.state.playback.revision != value.state.playback.revision {
                    release(value.reservedBytes)
                }
            }
            candidates = previous
            if let failed = contexts.removeValue(forKey: key) { release(failed.bytes) }
            throw error
        }
    }

    /// Returns the earliest failing command, so fixed-point admission removes
    /// its actual owner and rebuilds survivors rather than rejecting peers.
    func prepare(_ transitions: [SceneParticlePlaybackTransition]) -> SceneParticlePlaybackTransition? {
        discardCandidates(); callbackEpoch = nil; callbackOrdinal = nil
        guard !transitions.isEmpty else { finalPrepared = true; return nil }
        do { try prepareMetadata(); try chargeTraversal() } catch { return transitions.first }
        guard identitiesAreCurrent() else { return transitions.first }
        for transition in transitions {
            do {
                let previous = candidates
                try apply(transition)
                for (index, old) in previous where instances[index].layerID == transition.layerID {
                    release(old.reservedBytes)
                }
            } catch { discardCandidates(); return transition }
        }
        finalPrepared = true
        return nil
    }

    private func apply(_ transition: SceneParticlePlaybackTransition) throws {
        try chargeTraversal()
        guard identitiesAreCurrent() else { throw SceneParticleEmissionFailure.staleIdentity }
        let indices = instances.indices.filter { instances[$0].layerID == transition.layerID }
        guard !indices.isEmpty, Set(indices.map { instances[$0].surfaceID }) == surfaceIDs else { throw SceneParticleEmissionFailure.unavailable }
        let context = contexts[CommandIdentity(transition)]
        if transition.action == .emit, context?.values.count != indices.count {
            throw SceneParticleEmissionFailure.unavailable
        }
        var next: [Int: SceneParticleSimulator.PlaybackCandidate] = [:]
        do {
            for (offset, index) in indices.enumerated() {
                let sim = instances[index].simulator
                let baseRevision = candidates[index]?.state.playback.revision ?? sim.playback.revision
                guard baseRevision < UInt64.max else { throw SceneParticleEmissionFailure.staleIdentity }
                var local = transition; local = .init(layerID: local.layerID, action: local.action,
                    revision: baseRevision + 1, count: local.count,
                    callbackEpoch: local.callbackEpoch, ordinal: local.ordinal)
                next[index] = try sim.preparePlaybackCandidate(starting: candidates[index]?.state,
                    commands: [(local, context?.values[offset])], charge: charge, release: release)
            }
            let baseline = try totalLiveCount()
            var live = baseline
            for (index, instance) in instances.enumerated() {
                if let candidate = next[index] ?? candidates[index] {
                    live += candidate.state.particles.count - instance.simulator.particles.count
                }
            }
            guard (0...65_536).contains(live) else { throw SceneParticleEmissionFailure.budgetExceeded }
            candidates.merge(next) { _, new in new }
        } catch {
            for candidate in next.values { release(candidate.reservedBytes) }
            throw error
        }
    }

    /// All candidate storage is already reserved. No allocator, initializer or
    /// failable surface check may run after the first simulator is installed.
    func install() {
        assert(finalPrepared && identitiesAreCurrent())
        for (index, candidate) in candidates {
            instances[index].simulator.restoreFrame(candidate.state)
        }
        discardCandidates()
    }
}
