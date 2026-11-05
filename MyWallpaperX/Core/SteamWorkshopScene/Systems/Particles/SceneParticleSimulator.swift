import Foundation

/// One mutable simulator owns one persistent authored particle-system instance.
///
/// Keep this as reference identity: layer and child runtime containers are value
/// records that are frequently traversed or copied while retaining the same live
/// system. Making the simulator itself a value copied its particle buffers through
/// those records and forced Array COW checks throughout every operator hot path.
nonisolated final class SceneParticleSimulator: @unchecked Sendable {

    private(set) var playback = SceneParticlePlaybackSnapshot()
    let playbackHasWork: Bool?

    let fixedTimeStep: Double
    let maximumParticleCount: Int
#if DEBUG
    private(set) var diagnostics: [SceneParticleSimulationDiagnostic]
    var componentObservation: SceneParticleComponentObservationState?
#endif
    var particles: [SceneParticleState] = []
    /// Birth-state samples whose complete authored lifetime fell inside the
    /// current display callback. They remain lifecycle-dead and event-visible;
    /// Sprite assembly alone may render the sample once before the next advance.
    private var transientRenderBirths: [SceneParticleState] = []
    private(set) var birthEvents: [SceneParticleState] = []
    private(set) var deathEvents: [SceneParticleState] = []
    private(set) var simulationTime = 0.0
    let definition: SceneParticleDefinition
    let instanceOverride: SceneParticleInstanceOverride?
    var activeInstanceOverride: SceneParticleInstanceOverride?
    private let maximumEmissionDuration: Double?
    /// Read completion from the same emitter state that schedules births.
    /// This also survives frame rollback without a second child deadline.
    var hasFinishedEmission: Bool {
        for index in emitters.indices where !emitters[index].hasFinishedEmission(
            plan: emitterSpawnPlans[index], maximumEmissionDuration: maximumEmissionDuration
        ) { return false }
        return true
    }

    private let layerImageEmissionMap: SceneParticleLayerImageEmissionMap?
    private let worldSpaceFrame: SceneParticleWorldSpaceFrame?
    let rootWorldTranslation: SceneParticleRootWorldTranslationPlan?
    private let hasWorldSpaceMovement: Bool
    /// Immutable operator admission and turbulence data prepared with the definition.
    /// Dynamic audio and speed values are still read on every frame.
    let operatorAudioExecutionAdmission: [Bool]
    /// Launch-stable operator normalization and declaration plans.  Keep all
    /// frame-varying inputs (audio, overrides, particle age/position) live in
    /// the execution helpers.
    let operatorExecutionPlans: [SceneParticleOperatorExecutionPlan]
    let needsWorldControlPointFrame: Bool
    var controlPointFrame: SceneParticleControlPointFrame?
    let maintainsVortexRadius: Bool
    /// Launch-stable control-point identity lookup. Dynamic pointer and
    /// SceneScript values still arrive through `dynamicControlPoints`; only
    /// the authored identity metadata is indexed once for the particle hot
    /// path.
    let controlPointsByID: [Int: SceneParticleControlPoint]
    /// The definition-wide identity/uniqueness gate is immutable. Retain its
    /// result beside the lookup so invalid authored control-point catalogs
    /// fail closed without rescanning for every emitted particle.
    let controlPointSourcesAreValid: Bool
    /// Launch-stable scalar/vector/color initializer projections. Turbulence,
    /// event color and control-point values stay frame-local in their consumers.
    let initializerExecutionPlans: [SceneParticleInitializerExecutionPlan]
    /// Launch-stable emitter vectors, ranges and admission results. Dynamic
    /// control-point/instance values and random state remain frame-local.
    private let emitterSpawnPlans: [SceneParticleEmitterSpawnPlan]
    /// Only these operators own per-particle oscillation cache entries. Keeping
    /// the indices prepared avoids scanning every operator for each death.
    private let positionOscillationOperatorIndices: [Int]
    let turbulencePlans: [SceneParticleTurbulencePlan?]
    let simulationSeed: UInt64
    private var emitters: [SceneParticleEmitterState]
    var random: SceneParticleRandomGenerator
    private var accumulator = 0.0
    private var nextParticleID: UInt64 = 0
    private(set) var explicitBirthEventStart: Int?
    let explicitInitializerWork: UInt64?
    var normalizedLives: [Double] = []
    var dynamicControlPoints: [Int: SIMD3<Double>] = [:]
    /// The frame gravity conversion and world-space birth directions run
    /// through for the current advance: the caller's per-frame resolution of
    /// the layer's live world transform, falling back to the launch frame.
    var activeWorldSpaceFrame: SceneParticleWorldSpaceFrame?
    var dynamicControlPointAngles: [Int: SIMD3<Double>] = [:]
    var audioInput = SceneParticleAudioInput.silent
#if DEBUG
    /// Sticky per-system identities suppress repeated telemetry after the first
    /// non-silent evaluation. Both this set and its pending events participate
    /// in the existing particle frame transaction, so rejected frames cannot
    /// publish or consume execution evidence.
    var observedNonSilentAudioComponents:
        Set<SceneParticleAudioComponentIdentity> = []
    var pendingAudioEvaluationObservations:
        [SceneParticleAudioEvaluationObservation] = []
#endif
    var eventColorContext: SceneParticleEventColorContext
    private var stepSnapshotRecorder: SceneParticleStepSnapshotRecorder?
    var controlPointConstraintHistory: [SceneParticleControlPointConstraintHistory]
    var positionOscillationCache: [SceneParticleOscillationCacheKey: SceneParticlePositionOscillation] = [:]

    nonisolated init(
        definition: SceneParticleDefinition,
        instanceOverride: SceneParticleInstanceOverride? = nil,
        initialDynamicInstanceOverride: SceneParticleInstanceOverride? = nil,
        initialDynamicControlPoints: [Int: SIMD3<Double>] = [:],
        initialDynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        initialPlayback: SceneParticlePlaybackSnapshot = .init(),
        seed: UInt64 = 0,
        fixedTimeStep: Double = 1.0 / 60.0,
        particleBudget: Int? = nil,
        prewarmStepBudget: Int = 240,
        maximumEmissionDuration: Double? = nil,
        layerImageEmissionMap: SceneParticleLayerImageEmissionMap? = nil,
        worldSpaceFrame: SceneParticleWorldSpaceFrame? = nil,
        rootWorldTranslation: SceneParticleRootWorldTranslationPlan? = nil,
        controlPointForceEnvironment: SceneParticleControlPointForceEnvironment = .unavailable,
        controlPointFrame: SceneParticleControlPointFrame? = nil,
        initialControlPointParticleSpace: SceneParticleControlPointParticleSpace? = nil,
        stepSnapshotPolicy: SceneParticleStepSnapshotPolicy? = nil,
        eventColorContext: SceneParticleEventColorContext = .unavailable
    ) {
        self.playback = initialPlayback
        self.playbackHasWork = definition.preparedPlaybackWork(
            instanceOverride: instanceOverride, hasLayerImageMap: layerImageEmissionMap != nil
        )
        self.definition = definition
        self.instanceOverride = instanceOverride
        self.activeInstanceOverride = initialDynamicInstanceOverride ?? instanceOverride
        self.dynamicControlPoints = initialDynamicControlPoints
        self.dynamicControlPointAngles = initialDynamicControlPointAngles
        self.maximumEmissionDuration = maximumEmissionDuration
        self.layerImageEmissionMap = layerImageEmissionMap
        self.worldSpaceFrame = worldSpaceFrame
        self.rootWorldTranslation = rootWorldTranslation
        self.eventColorContext = eventColorContext
        self.hasWorldSpaceMovement = definition.operators.contains(
            where: \.isWorldSpaceMovement
        )
        operatorAudioExecutionAdmission = definition.operators.map {
            !$0.audioResponse.isEnabled || $0.hasBoundedAudioResponse
        }
        operatorExecutionPlans = definition.operators.map {
            SceneParticleOperatorExecutionPlan(
                $0,
                definition: definition, controlPointForceEnvironment: controlPointForceEnvironment
            )
        }
        self.controlPointFrame = controlPointFrame
        maintainsVortexRadius = operatorExecutionPlans.contains { $0.vortex?.maintainsRadius == true }
        var controlPointsByID: [Int: SceneParticleControlPoint] = [:]
        var controlPointIdentities: Set<Int> = []
        var controlPointSourcesAreValid = true
        for point in definition.controlPoints {
            guard let id = point.id, (0 ... 7).contains(id),
                  controlPointIdentities.insert(id).inserted else {
                controlPointSourcesAreValid = false
                continue
            }
            controlPointsByID[id] = point
        }
        self.controlPointsByID = controlPointsByID
        self.controlPointSourcesAreValid = controlPointSourcesAreValid
        initializerExecutionPlans = definition.initializers.map {
            SceneParticleInitializerExecutionPlan($0, definition: definition)
        }
        explicitInitializerWork = Self.explicitInitializerWork(
            definition: definition, plans: initializerExecutionPlans)
        var pointConsumers = definition.emitters.compactMap { definition.emitterControlPointSource(for: $0) }
        for plan in initializerExecutionPlans {
            if let between = plan.positionBetweenControlPoints {
                pointConsumers.append(contentsOf: [between.controlPointStart, between.controlPointEnd])
            }
        }
        var needsConstraintHistory = false
        for (index, plan) in operatorExecutionPlans.enumerated() {
            if let maintain = plan.maintainControlPointDistance {
                pointConsumers.append(contentsOf: [maintain.start, maintain.end])
                needsConstraintHistory = true
            }
            if case let .controlPointRadius(radius?) = definition.operators[index].kind {
                pointConsumers.append(radius.controlPoint)
                needsConstraintHistory = true
            }
        }
        needsWorldControlPointFrame = operatorExecutionPlans.contains { $0.controlPointForce?.sourceSpace == .world }
            || pointConsumers.contains { (controlPointsByID[$0]?.rawFlags ?? 0) & 2 != 0 }
        controlPointConstraintHistory = needsConstraintHistory
            ? Array(repeating: .unavailable, count: definition.operators.count) : []
        emitterSpawnPlans = definition.emitters.map(SceneParticleEmitterSpawnPlan.init)
        positionOscillationOperatorIndices = definition.operators.indices.filter {
            definition.operators[$0].kind == .oscillatePosition
        }
        turbulencePlans = definition.operators.map(SceneParticleTurbulencePlan.init)
        self.stepSnapshotRecorder = stepSnapshotPolicy.map(
            SceneParticleStepSnapshotRecorder.init(policy:)
        )
        self.simulationSeed = seed
        self.fixedTimeStep = fixedTimeStep.isFinite && fixedTimeStep > 0 ? fixedTimeStep : 1.0 / 60.0
        let authoredMaximum = min(max(definition.maximumCount ?? 1, 0), 20_000)
        maximumParticleCount = min(authoredMaximum, max(particleBudget ?? authoredMaximum, 0))
#if DEBUG
        componentObservation = definition.componentObservationSources.map {
            SceneParticleComponentObservationState(sources: $0)
        }
        componentObservation?.origin = "prewarm"
        diagnostics = SceneParticleSimulationMath.diagnostics(
            definition, instanceOverride, eventColorContext: eventColorContext,
            controlPointForceEnvironment: controlPointForceEnvironment
        )
#endif
        emitters = definition.emitters.indices.map {
            SceneParticleEmitterState(seed: seed, emitterIndex: $0)
        }
        random = SceneParticleRandomGenerator(state: seed)
        // The init-time warm-up runs the same emit/apply path as advance;
        // prewarmed world-space systems convert through the launch frame.
        activeWorldSpaceFrame = worldSpaceFrame
        warmUp(duration: definition.startTime ?? 0, stepBudget: prewarmStepBudget,
               historyCapacity: stepSnapshotPolicy?.maximumSnapshots ?? 0,
               controlPointParticleSpace: initialControlPointParticleSpace)
#if DEBUG
        componentObservation?.origin = "live"
#endif
        birthEvents.removeAll(keepingCapacity: true)
        deathEvents.removeAll(keepingCapacity: true)
    }

    func applyPlaybackTransition(_ transition: SceneParticlePlaybackTransition) {
        guard transition.revision > playback.revision else { return }
        switch transition.action {
        case .play:
            if playback.intent == .stopped || hasFinishedEmission {
                for index in emitters.indices { emitters[index].rearm() }
            }
            playback.intent = .playing
        case .emit: break // Birth is installed only from the validated candidate.
        case .pause: playback.intent = .paused
        case .stop:
            playback.intent = .stopped
            for index in emitters.indices { emitters[index].rearm() }
            discardPopulationForPlayback()
        }
        playback.revision = transition.revision
    }

    /// Completed emitters and author pause/stop intent survive visibility changes.
    func restartPopulationForVisibility() {
        for index in emitters.indices where playback.intent == .playing && !emitters[index].hasFinishedEmission(
            plan: emitterSpawnPlans[index], maximumEmissionDuration: maximumEmissionDuration
        ) { emitters[index].rearm() }
        discardPopulationForPlayback()
    }

    nonisolated func advance(
        by duration: Double,
        dynamicControlPoints: [Int: SIMD3<Double>] = [:],
        dynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        dynamicInstanceOverride: SceneParticleInstanceOverride? = nil,
        audioInput: SceneParticleAudioInput = .silent,
        worldSpaceFrameOverride: SceneParticleWorldSpaceFrame? = nil,
        controlPointFrame: SceneParticleControlPointFrame? = nil,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace? = nil,
        allowsEmission: Bool = true
    ) {
        let intent = playback.intent
        if !allowsEmission { playback.intent = .paused }
        defer { playback.intent = intent }
        transientRenderBirths.removeAll(keepingCapacity: true)
        self.dynamicControlPoints = dynamicControlPoints
        self.dynamicControlPointAngles = dynamicControlPointAngles
        activeInstanceOverride = dynamicInstanceOverride ?? instanceOverride
        self.audioInput = audioInput
        activeWorldSpaceFrame = worldSpaceFrameOverride ?? worldSpaceFrame
        self.controlPointFrame = controlPointFrame
        guard duration.isFinite, duration > 0 else { return }
        let birthEventStart = explicitBirthEventStart ?? birthEvents.count
        explicitBirthEventStart = nil
        let deathEventStart = deathEvents.count
        for index in emitters.indices { emitters[index].beginFrame() }
        accumulator += duration
        while accumulator + 1e-12 >= fixedTimeStep {
            step(by: fixedTimeStep, controlPointParticleSpace: controlPointParticleSpace)
            accumulator -= fixedTimeStep
        }
        if accumulator < 0 { accumulator = 0 }
        publishTransientRenderBirths(
            birthEventStart: birthEventStart,
            deathEventStart: deathEventStart
        )
    }

    /// Returns the authored-order Sprite sample set for the current display
    /// callback. The common path returns the persistent array through COW;
    /// allocation and sorting occur only when a particle was born and died
    /// entirely between two display callbacks.
    nonisolated func renderParticlesForCurrentAdvance() -> [SceneParticleState] {
        guard !transientRenderBirths.isEmpty else { return particles }
        var result = particles
        result.reserveCapacity(particles.count + transientRenderBirths.count)
        result.append(contentsOf: transientRenderBirths)
        result.sort { $0.id < $1.id }
        return result
    }

    /// Current-callback diagnostic used by lifecycle/performance validation.
    /// Zero means the ordinary persistent render path stayed active.
    nonisolated var transientRenderSampleCount: Int {
        transientRenderBirths.count
    }

    nonisolated func consumeBirthEvents() -> [SceneParticleState] {
        defer { birthEvents.removeAll(keepingCapacity: true); explicitBirthEventStart = nil }
        return birthEvents
    }

    nonisolated func consumeDeathEvents() -> [SceneParticleState] {
        defer { deathEvents.removeAll(keepingCapacity: true) }
        return deathEvents
    }

    nonisolated func consumeStepSnapshots() -> [SceneParticleStepSnapshot] {
        stepSnapshotRecorder?.consume(particles: particles) ?? []
    }

    /// Captures mutable simulation state before a frame is admitted. The
    /// runtime keeps immutable definition/operator data shared; only the
    /// frame-varying state is copied and can be restored on host rejection.
    nonisolated func frameSnapshot() -> FrameSnapshot {
        var snapshot = FrameSnapshot(
            playback: playback,
            particles: particles,
            transientRenderBirths: transientRenderBirths,
            birthEvents: birthEvents,
            deathEvents: deathEvents,
            simulationTime: simulationTime,
            activeInstanceOverride: activeInstanceOverride,
            activeWorldSpaceFrame: activeWorldSpaceFrame,
            controlPointFrame: controlPointFrame,
            explicitBirthEventStart: explicitBirthEventStart,
            emitters: emitters,
            random: random,
            accumulator: accumulator,
            nextParticleID: nextParticleID,
            normalizedLives: normalizedLives,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            audioInput: audioInput,
            eventColorContext: eventColorContext,
            stepSnapshotRecorder: stepSnapshotRecorder,
            positionOscillationCache: positionOscillationCache,
            controlPointConstraintHistory: controlPointConstraintHistory
        )
#if DEBUG
        snapshot.diagnostics = diagnostics
        snapshot.observedNonSilentAudioComponents = observedNonSilentAudioComponents
        snapshot.pendingAudioEvaluationObservations = pendingAudioEvaluationObservations
        snapshot.componentObservation = componentObservation
#endif
        return snapshot
    }

    nonisolated func restoreFrame(_ snapshot: FrameSnapshot) {
        playback = snapshot.playback
        particles = snapshot.particles
        transientRenderBirths = snapshot.transientRenderBirths
        birthEvents = snapshot.birthEvents
        deathEvents = snapshot.deathEvents
        simulationTime = snapshot.simulationTime
        activeInstanceOverride = snapshot.activeInstanceOverride
        activeWorldSpaceFrame = snapshot.activeWorldSpaceFrame
        controlPointFrame = snapshot.controlPointFrame
        explicitBirthEventStart = snapshot.explicitBirthEventStart
        emitters = snapshot.emitters
        random = snapshot.random
        accumulator = snapshot.accumulator
        nextParticleID = snapshot.nextParticleID
        normalizedLives = snapshot.normalizedLives
        dynamicControlPoints = snapshot.dynamicControlPoints
        dynamicControlPointAngles = snapshot.dynamicControlPointAngles
        audioInput = snapshot.audioInput
#if DEBUG
        diagnostics = snapshot.diagnostics
        observedNonSilentAudioComponents = snapshot.observedNonSilentAudioComponents
        pendingAudioEvaluationObservations = snapshot.pendingAudioEvaluationObservations
        componentObservation = snapshot.componentObservation
#endif
        eventColorContext = snapshot.eventColorContext
        stepSnapshotRecorder = snapshot.stepSnapshotRecorder
        positionOscillationCache = snapshot.positionOscillationCache
        controlPointConstraintHistory = snapshot.controlPointConstraintHistory
    }

    private nonisolated func publishTransientRenderBirths(
        birthEventStart: Int,
        deathEventStart: Int
    ) {
        guard birthEventStart < birthEvents.count,
              deathEventStart < deathEvents.count
        else { return }
        let birthRange = birthEventStart ..< birthEvents.count
        for death in deathEvents[deathEventStart...] {
            guard let birth = birthEvent(in: birthRange, matching: death.id) else {
                continue
            }
            transientRenderBirths.append(birth)
        }
    }

    /// Birth identities are globally monotonic, so the current-callback suffix
    /// is ordered even when deaths from multiple fixed steps are not. Binary
    /// search keeps the no-intersection steady-state path allocation-free; the
    /// transient array only grows after a real same-callback match.
    private nonisolated func birthEvent(
        in range: Range<Int>,
        matching identity: UInt64
    ) -> SceneParticleState? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let candidate = birthEvents[middle]
            if candidate.id < identity {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < range.upperBound, birthEvents[lower].id == identity else {
            return nil
        }
        return birthEvents[lower]
    }

    nonisolated func updateFollowEventColor(_ color: SIMD3<Double>) {
        guard case .follow = eventColorContext else { return }
        eventColorContext = .follow(color)
    }

    private nonisolated func warmUp(
        duration: Double, stepBudget: Int, historyCapacity: Int,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace?
    ) {
        guard duration != 0 else { return }
        let requestedSteps = (duration / fixedTimeStep).rounded(.up)
        guard duration.isFinite, duration > 0, requestedSteps.isFinite,
              requestedSteps < Double(Int.max) else {
#if DEBUG
            diagnostics.append(.init(kind: .prewarmInvalidDuration, componentName: nil))
#endif
            return
        }
        // Frame-created children keep 240 steps. Root extensions charge actual
        // births/live work after each whole step, so at most one step spills
        // past the work budget; history remains conservatively weighted.
        let count = min(Int(requestedSteps), min(max(stepBudget, 0), 3_600))
        var initializerCost = 0.0
        var operatorCost = 0.0
        var boidsCount = 0.0
        if count > 240 {
            for value in definition.initializers {
                initializerCost += 32 + Double(value.boundedPositionOffset?.octaves ?? 0) * 24
            }
            for value in definition.operators {
                operatorCost += 32
                if case .boids = value.kind { boidsCount += 1 }
            }
        }
        var workRemaining = 4_000_000.0
        var completedSteps = 0
        var remaining = duration
        for _ in 0..<count {
            if completedSteps >= 240 && workRemaining <= 0 { break }
            for index in emitters.indices { emitters[index].beginFrame() }
            let slice = min(fixedTimeStep, remaining)
            guard slice > 0 else { break }
            let previousID = nextParticleID
            let previousTime = simulationTime
            step(by: slice, controlPointParticleSpace: controlPointParticleSpace)
            completedSteps += 1
            if completedSteps > 240 {
                // IDs include failed births that reached initialization; lives
                // still contains the actual pre-death-compaction population.
                let births = Double(nextParticleID - previousID)
                let live = simulationTime != previousTime ? Double(normalizedLives.count) : 0
                let work = Double(definition.emitters.count + definition.operators.count)
                    + births * initializerCost
                    + live * (32 + operatorCost + Double(historyCapacity))
                    + boidsCount * live * live
                workRemaining -= max(1, work)
            }
            // These events have never been replayed to children after warmup.
            // Drain per step so a long, short-lived emitter cannot retain its
            // entire prehistory. The bounded trail recorder remains intact.
            birthEvents.removeAll(keepingCapacity: true)
            deathEvents.removeAll(keepingCapacity: true)
            remaining -= slice
        }
#if DEBUG
        if completedSteps < Int(requestedSteps) {
            diagnostics.append(.init(
                kind: .prewarmBudgetExceeded,
                componentName: "requested=\(duration),simulated=\(simulationTime),steps=\(completedSteps)"
            ))
        }
#endif
    }

    private nonisolated func step(
        by frameDuration: Double,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace?
    ) {
        // Rate scales the entire simulation step once. Keep the wall-time step
        // budget unchanged instead of multiplying integration work by the rate.
        let duration = frameDuration * max(0, overrideScalar(activeInstanceOverride?.rate))
        guard duration != 0 else { return }
        guard duration.isFinite, Float(simulationTime + duration).isFinite else {
#if DEBUG
            let diagnostic = SceneParticleSimulationDiagnostic(
                kind: .invalidSimulationTime, componentName: "rate"
            )
            if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
#endif
            return
        }
        let existingParticleIDUpperBound = nextParticleID
        if playback.intent == .playing {
            for index in definition.emitters.indices { emit(index: index, duration: duration) }
        }
        normalizedLives.removeAll(keepingCapacity: true)
        normalizedLives.reserveCapacity(particles.count)
        for index in particles.indices {
            particles[index].alpha = particles[index].initialAlpha
            particles[index].size = particles[index].initialSize
            particles[index].color = particles[index].initialColor
            particles[index].age += duration
            normalizedLives.append(min(max(
                particles[index].age / max(particles[index].lifetime, 1e-12), 0
            ), 1))
        }
        for (operatorIndex, value) in definition.operators.enumerated() {
            apply(value, operatorIndex: operatorIndex, duration: duration,
                  existingParticleIDUpperBound: existingParticleIDUpperBound,
                  controlPointParticleSpace: controlPointParticleSpace)
        }
        // Collect deaths and compact the live prefix in one pass. The previous
        // two-pass sequence walked every particle once for events and again for
        // removal, which is a measurable cost for authored systems with tens of
        // thousands of particles. Preserve authored order while keeping the
        // event payload and oscillation-cache cleanup identical.
        var liveCount = 0
        for readIndex in particles.indices {
            let particle = particles[readIndex]
            if particle.age + 1e-12 >= particle.lifetime {
                deathEvents.append(particle)
                for operatorIndex in positionOscillationOperatorIndices {
                    positionOscillationCache.removeValue(forKey: .init(
                        particleID: particle.id, operatorIndex: operatorIndex
                    ))
                }
                continue
            }
            if liveCount != readIndex {
                particles[liveCount] = particle
            }
            liveCount += 1
        }
        if liveCount < particles.count {
            particles.removeLast(particles.count - liveCount)
        }
        simulationTime += duration
        stepSnapshotRecorder?.record(duration: duration, particles: particles)
    }

    private nonisolated func emit(index: Int, duration: Double) {
        let emitter = definition.emitters[index]
#if DEBUG
        componentObservation?.record("emitter", index, "attempted", reason: "natural-emission-dispatch", time: simulationTime)
#endif
        if case .unsupported = emitter.kind {
#if DEBUG
            componentObservation?.record("emitter", index, "unsupported", reason: "unknown-emitter-kind", time: simulationTime)
#endif
            return
        }
        let spawnPlan = emitterSpawnPlans[index]
        guard let emitterFrame = definition.emitterControlPointFrame(
            for: emitter, instanceOverride: activeInstanceOverride,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            controlPointsByID: controlPointsByID,
            controlPointSourcesAreValid: controlPointSourcesAreValid,
            preparedOrigin: spawnPlan.origin, controlPointFrame: controlPointFrame
        ) else {
#if DEBUG
            componentObservation?.record("emitter", index, "unavailable", reason: "control-point-frame-unavailable", time: simulationTime)
#endif
            return
        }
        guard let audioScale = emissionAudioScale(
            for: spawnPlan, emitterIndex: index
        ) else {
#if DEBUG
            componentObservation?.record("emitter", index, "unavailable", reason: "audio-response-plan-unavailable", time: simulationTime)
#endif
            return
        }
        // A scaled step may span many random windows. Reject before advancing
        // this emitter's schedule or RNG; at most 1024 full windows plus the
        // currently partial window can be visited by an accepted step.
        if case let .supported(periodic) = spawnPlan.periodicEmissionAdmission,
           duration > min(periodic.minimumDuration, periodic.minimumDelay) * 1024 {
#if DEBUG
            let diagnostic = SceneParticleSimulationDiagnostic(
                kind: .invalidEmitterState, componentName: "periodic-budget:\(index)"
            )
            if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
            componentObservation?.record("emitter", index, "rejected", reason: "periodic-window-budget", time: simulationTime)
#endif
            return
        }
        let countScale = effectiveCountOverride
        let count: Int
        switch emitters[index].scheduledEmissionCount(
            plan: spawnPlan, stepDuration: duration,
            maximumEmissionDuration: maximumEmissionDuration,
            countScale: countScale, audioScale: audioScale,
            maximumCount: maximumParticleCount
        ) {
        case .inactive:
#if DEBUG
            componentObservation?.record("emitter", index, "unknown", reason: "schedule-inactive-or-unavailable", time: simulationTime)
#endif
            return
        case .invalidAccumulator:
#if DEBUG
            let diagnostic = SceneParticleSimulationDiagnostic(
                kind: .invalidEmitterState, componentName: "emission:\(index)"
            )
            if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
            componentObservation?.record("emitter", index, "rejected", reason: "nonfinite-emission-accumulator", time: simulationTime)
#endif
            return
        case let .count(requested):
            count = min(requested, maximumParticleCount - particles.count)
        }
#if DEBUG
        componentObservation?.record("emitter", index, "evaluated", reason: "scheduled-count-evaluated", time: simulationTime)
        if count == 0 { componentObservation?.record("emitter", index, "not-triggered", reason: "zero-admitted-count", time: simulationTime) }
#endif
        for _ in 0..<count {
            if let particle = makeParticle(
                emitter, spawnPlan: spawnPlan, frame: emitterFrame
            ) {
                appendBirth(particle)
#if DEBUG
                componentObservation?.record("emitter", index, "accepted-birth", reason: "natural-birth-appended", time: simulationTime, particleID: particle.id)
#endif
            } else {
#if DEBUG
                componentObservation?.record("emitter", index, "rejected", reason: "birth-construction-rejected", time: simulationTime)
#endif
            }
        }
    }

    func appendBirth(_ particle: SceneParticleState) {
        particles.append(particle)
        birthEvents.append(particle)
    }

    func emitExplicitly(count: Int, context: EmissionContext,
                        chargeWork: (UInt64) throws -> Void) throws {
#if DEBUG
        let observationOrigin = componentObservation?.origin
        componentObservation?.origin = "explicit"
        defer { if let observationOrigin { componentObservation?.origin = observationOrigin } }
        componentObservation?.record("emitter", 0, "attempted", reason: "explicit-emission-command", time: simulationTime)
#endif
        guard (0...1024).contains(count), playbackHasWork != nil,
              let initializerWork = explicitInitializerWork else { throw SceneParticleEmissionFailure.unavailable }
        guard count <= maximumParticleCount - particles.count else { throw SceneParticleEmissionFailure.budgetExceeded }
        guard UInt64(count) <= UInt64.max - nextParticleID else { throw SceneParticleEmissionFailure.staleIdentity }
        guard count > 0 else { return }
        dynamicControlPoints = context.controlPoints
        dynamicControlPointAngles = context.controlPointAngles
        activeInstanceOverride = context.instanceOverride ?? instanceOverride
        audioInput = context.audio
        activeWorldSpaceFrame = context.worldFrame ?? worldSpaceFrame
        controlPointFrame = context.controlPointFrame
        guard let emitter = definition.emitters.first,
              let frame = definition.emitterControlPointFrame(
                for: emitter, instanceOverride: activeInstanceOverride,
                dynamicControlPoints: dynamicControlPoints,
                dynamicControlPointAngles: dynamicControlPointAngles,
                controlPointsByID: controlPointsByID,
                controlPointSourcesAreValid: controlPointSourcesAreValid,
                preparedOrigin: emitterSpawnPlans[0].origin, controlPointFrame: controlPointFrame) else {
            throw SceneParticleEmissionFailure.unavailable
        }
        if explicitBirthEventStart == nil { explicitBirthEventStart = birthEvents.count }
        for _ in 0..<count {
            try chargeWork(1 + 8 + initializerWork)
            guard let particle = makeParticle(emitter, spawnPlan: emitterSpawnPlans[0], frame: frame, strict: true) else {
                throw SceneParticleEmissionFailure.unavailable
            }
            appendBirth(particle)
#if DEBUG
            componentObservation?.record("emitter", 0, "accepted-birth", reason: "explicit-birth-appended", time: simulationTime, particleID: particle.id)
#endif
        }
    }

    private nonisolated func makeParticle(
        _ emitter: SceneParticleEmitter,
        spawnPlan: SceneParticleEmitterSpawnPlan,
        frame: SceneParticleEmitterControlPointFrame, strict: Bool = false
    ) -> SceneParticleState? {
        guard spawnPlan.hasBoundedDirectionsAndSign,
              let speedMinimum = spawnPlan.speedMinimum,
              let speedMaximum = spawnPlan.speedMaximum else { return nil }
        var velocity = SIMD3<Double>.zero
        let relative: SIMD3<Double>
        switch emitter.kind {
        case .sphereRandom:
            relative = randomSphereOffset(spawnPlan)
        case .boxRandom:
            relative = randomBoxOffset(spawnPlan)
        case .layerImage:
            guard let point = layerImageEmissionMap?.sample(using: &random) else { return nil }
            relative = point
        case .unsupported:
            return nil
        }
        let position = frame.position(for: relative)
        let speed = random.value(speedMinimum, speedMaximum)
        let length = SceneParticleSimulationMath.length(relative)
        if speed != 0, length > 1e-12 { velocity += relative / length * speed }

        var particle = SceneParticleState(
            id: nextParticleID, position: position, velocity: velocity,
            color: SIMD3(repeating: 1), alpha: 1, size: 20,
            rotation: .zero, angularVelocity: .zero, age: 0, lifetime: 1,
            initialColor: SIMD3(repeating: 1), initialAlpha: 1, initialSize: 20
        )
        nextParticleID &+= 1
        guard applyInitializers(to: &particle, strict: strict,
                                emitterControlPointOrigin: frame.controlPointOrigin) else { return nil }
        particle.velocity = frame.direction(for: particle.velocity)
        applyInstanceOverride(to: &particle)
        if hasWorldSpaceMovement, let activeWorldSpaceFrame {
            particle.velocity = activeWorldSpaceFrame.localDirection(particle.velocity)
        }
        if rootWorldTranslation != nil, let activeWorldSpaceFrame {
            particle.position += activeWorldSpaceFrame.birthPositionOffset
        }
        particle.initialColor = particle.color
        particle.initialAlpha = particle.alpha
        particle.initialSize = particle.size
        return particle.lifetime > 0 && acceptsBirthResult(particle) ? particle : nil
    }

    /// Validate the multiplied birth state before retaining it or narrowing to
    /// the Float GPU ABI. A bad new particle must not poison existing peers.
    private nonisolated func acceptsBirthResult(_ particle: SceneParticleState) -> Bool {
        if Float(particle.lifetime).isFinite && Float(particle.size).isFinite
            && Float(particle.alpha).isFinite
            && SceneParticleSimulationMath.isGPUFinite(particle.color)
            && SceneParticleSimulationMath.isGPUFinite(particle.position)
            && SceneParticleSimulationMath.isGPUFinite(particle.velocity)
            && SceneParticleSimulationMath.isGPUFinite(particle.rotation)
            && SceneParticleSimulationMath.isGPUFinite(particle.angularVelocity) {
            return true
        }
#if DEBUG
        let diagnostic = SceneParticleSimulationDiagnostic(
            kind: .invalidEmitterState, componentName: "particle-initialization"
        )
        if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
#endif
        return false
    }

    /// Reject only this particle's unsafe operator result, before either half
    /// of the integration is committed or narrowed to the GPU's Float ABI.
    nonisolated func acceptsMotionResult(
        _ velocity: SIMD3<Double>, _ position: SIMD3<Double>, component: String
    ) -> Bool {
        if SceneParticleSimulationMath.isGPUFinite(velocity)
            && SceneParticleSimulationMath.isGPUFinite(position) {
            return true
        }
#if DEBUG
        let diagnostic = SceneParticleSimulationDiagnostic(
            kind: .invalidOperatorState, componentName: component
        )
        if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
        if let index = componentObservation?.activeOperatorIndex {
            componentObservation?.record("operator", index, "rejected", reason: "nonfinite-motion-result", time: simulationTime)
        }
#endif
        return false
    }

}
