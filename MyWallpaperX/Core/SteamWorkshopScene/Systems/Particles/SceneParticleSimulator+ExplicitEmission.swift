import Foundation

extension SceneParticleSimulator {
    var playbackObservation: SceneParticlePlaybackObservation? {
        guard let playbackHasWork else { return nil }
        return .init(liveAny: !particles.isEmpty,
                     emissionPending: playbackHasWork && !hasFinishedEmission,
                     rearmHasWork: playbackHasWork, intent: playback.intent, revision: playback.revision)
    }


    struct FrameSnapshot {
        let playback: SceneParticlePlaybackSnapshot
        let particles: [SceneParticleState]
        let diagnostics: [SceneParticleSimulationDiagnostic]
        let transientRenderBirths: [SceneParticleState]
        let birthEvents: [SceneParticleState]
        let deathEvents: [SceneParticleState]
        let simulationTime: Double
        let activeInstanceOverride: SceneParticleInstanceOverride?
        let activeWorldSpaceFrame: SceneParticleWorldSpaceFrame?
        let explicitBirthEventStart: Int?
        let emitters: [SceneParticleEmitterState]
        let random: SceneParticleRandomGenerator
        let accumulator: Double
        let nextParticleID: UInt64
        let normalizedLives: [Double]
        let dynamicControlPoints: [Int: SIMD3<Double>]
        let dynamicControlPointAngles: [Int: SIMD3<Double>]
        let audioInput: SceneParticleAudioInput
        let observedNonSilentAudioComponents: Set<SceneParticleAudioComponentIdentity>
        let pendingAudioEvaluationObservations: [SceneParticleAudioEvaluationObservation]
        let eventColorContext: SceneParticleEventColorContext
        let stepSnapshotRecorder: SceneParticleStepSnapshotRecorder?
        let positionOscillationCache: [SceneParticleOscillationCacheKey: SceneParticlePositionOscillation]
        let trailPositionHistory: SceneParticleTrailPositionHistory
    }

    struct EmissionContext: Equatable, Sendable {
        var controlPoints: [Int: SIMD3<Double>] = [:]
        var controlPointAngles: [Int: SIMD3<Double>] = [:]
        var instanceOverride: SceneParticleInstanceOverride? = nil
        var audio: SceneParticleAudioInput = .silent
        var worldFrame: SceneParticleWorldSpaceFrame? = nil

        var storageBytes: Int {
            MemoryLayout<Self>.stride + 256
                + (controlPoints.capacity + controlPointAngles.capacity) * 128
                + (audio.left.capacity + audio.right.capacity) * MemoryLayout<Float>.stride
                + (instanceOverride?.controlPoints.count ?? 0) * 256
                + (instanceOverride?.controlPointAngles.count ?? 0) * 256
        }
    }
    var emissionContextReservationBytes: Int {
        4096 + ((instanceOverride?.controlPoints.capacity ?? 0)
                + (instanceOverride?.controlPointAngles.capacity ?? 0)) * 512
    }
    struct PlaybackCandidate {
        let state: FrameSnapshot
        let reservedBytes: Int
    }

    /// Mutates the existing simulator only within this synchronous scope. The
    /// candidate is a transaction value, never another simulator or RNG owner.
    func preparePlaybackCandidate(
        starting: FrameSnapshot? = nil,
        commands: [(SceneParticlePlaybackTransition, EmissionContext?)],
        charge: (UInt64, Int) throws -> Void,
        release: (Int) -> Void
    ) throws -> PlaybackCandidate {
        let committed = frameSnapshot()
        defer { restoreFrame(committed) }
        if let starting { restoreFrame(starting) }
        let additions = commands.reduce(0) { $0 + ($1.0.action == .emit ? $1.0.count : 0) }
        guard additions >= 0, additions <= 64 * 1024 else { throw SceneParticleEmissionFailure.unavailable }
        let bytes = frameSnapshot().emissionStorageBytes(adding: additions, initializers: definition.initializers.count)
        try charge(UInt64((bytes + 63) / 64), bytes)
        do {
            for (command, context) in commands {
                guard command.revision > playback.revision else { continue }
                guard playback.revision < UInt64.max,
                      command.revision == playback.revision + 1 else {
                    throw SceneParticleEmissionFailure.staleIdentity
                }
                try charge(1, 0)
                if command.action == .emit {
                    guard let context else { throw SceneParticleEmissionFailure.unavailable }
                    try emitExplicitly(count: command.count, context: context) { try charge($0, 0) }
                }
                applyPlaybackTransition(command)
            }
            return .init(state: frameSnapshot(), reservedBytes: bytes)
        } catch {
            release(bytes)
            throw error
        }
    }

    /// Prepared once, beside the actual initializer execution plans. Cost is
    /// bounded work, not time: noise octaves and selected audio bins are charged.
    static func explicitInitializerWork(
        definition: SceneParticleDefinition,
        plans: [SceneParticleInitializerExecutionPlan],
        controlPointPlans: [SceneParticlePositionAroundControlPointPlan?]
    ) -> UInt64? {
        var work: UInt64 = 0
        for (index, value) in definition.initializers.enumerated() {
            let plan = plans[index]
            switch value.kind {
            case .unsupported: return nil
            case .hsvColor: guard plan.hsvColor != nil else { return nil }; work += 16
            case .colorList: guard plan.colorList != nil else { return nil }; work += 8
            case .positionOffset:
                guard let offset = plan.positionOffset else { return nil }
                work += UInt64(32 + offset.octaves * 48)
            case .positionAroundControlPoint:
                guard controlPointPlans[index] != nil else { return nil }; work += 32
            case .turbulentVelocity:
                guard let turbulence = plan.turbulentVelocity,
                      !turbulence.audioResponseEnabled || turbulence.audioResponsePlan != nil else { return nil }
                work += 96 + UInt64(turbulence.audioResponsePlan?.frequencies.count ?? 0)
            case .inheritEventColor:
                // The root profile has no parent event producer. Its ordinary
                // fallback still renders; explicit exact-n cannot claim support.
                return nil
            case .lifetime, .size, .alpha:
                work += 8
            case .velocity, .rotation, .angularVelocity:
                work += 8
            case .color:
                work += 8
            }
        }
        return work
    }
}

extension SceneParticleSimulator.FrameSnapshot {
    /// Conservative reservation for both sides of an Array COW/growth and
    /// hash-container buckets. Immutable prepared plans remain shared.
    func emissionStorageBytes(adding count: Int, initializers: Int) -> Int {
        func states(_ values: [SceneParticleState], extra: Int = 0) -> Int {
            2 * max(values.capacity, values.count + extra) * MemoryLayout<SceneParticleState>.stride + 64
        }
        let arrays = states(particles, extra: count) + states(birthEvents, extra: count)
            + states(deathEvents) + states(transientRenderBirths)
            + 2 * normalizedLives.capacity * MemoryLayout<Double>.stride
            + 2 * emitters.capacity * MemoryLayout<SceneParticleEmitterState>.stride
        let buckets = (positionOscillationCache.capacity + dynamicControlPoints.capacity
            + dynamicControlPointAngles.capacity + observedNonSilentAudioComponents.capacity + initializers) * 512
        let notices = 2 * (diagnostics.capacity + diagnostics.count + 8) * 256
            + 2 * (pendingAudioEvaluationObservations.capacity + initializers) * 256
        return MemoryLayout<Self>.stride + 1024 + arrays + buckets + notices
            + trailPositionHistory.emissionStorageBytes(adding: count)
            + (stepSnapshotRecorder?.emissionStorageBytes ?? 0)
    }
}
