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
    private(set) var diagnostics: [SceneParticleSimulationDiagnostic]
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
    private let hasWorldSpaceMovement: Bool
    /// Immutable operator admission and turbulence data prepared with the definition.
    /// Dynamic audio and speed values are still read on every frame.
    private let operatorAudioExecutionAdmission: [Bool]
    /// Launch-stable operator normalization and declaration plans.  Keep all
    /// frame-varying inputs (audio, overrides, particle age/position) live in
    /// the execution helpers.
    private let operatorExecutionPlans: [SceneParticleOperatorExecutionPlan]
    private let maintainsVortexRadius: Bool
    /// Launch-stable control-point identity lookup. Dynamic pointer and
    /// SceneScript values still arrive through `dynamicControlPoints`; only
    /// the authored identity metadata is indexed once for the particle hot
    /// path.
    let controlPointsByID: [Int: SceneParticleControlPoint]
    /// The definition-wide identity/uniqueness gate is immutable. Retain its
    /// result beside the lookup so invalid authored control-point catalogs
    /// fail closed without rescanning for every emitted particle.
    let controlPointSourcesAreValid: Bool
    /// Position-around-control-point admission depends only on authored
    /// topology. Keep the accepted plan aligned with the initializer array so
    /// each emitted particle does not repeat the same definition-wide scans.
    let positionAroundControlPointPlans:
        [SceneParticlePositionAroundControlPointPlan?]
    /// Launch-stable scalar/vector/color initializer projections. Turbulence,
    /// event color and control-point values stay frame-local in their consumers.
    let initializerExecutionPlans: [SceneParticleInitializerExecutionPlan]
    /// Launch-stable emitter vectors, ranges and admission results. Dynamic
    /// control-point/instance values and random state remain frame-local.
    private let emitterSpawnPlans: [SceneParticleEmitterSpawnPlan]
    /// Only these operators own per-particle oscillation cache entries. Keeping
    /// the indices prepared avoids scanning every operator for each death.
    private let positionOscillationOperatorIndices: [Int]
    private let turbulencePlans: [SceneParticleTurbulencePlan?]
    let simulationSeed: UInt64
    private var emitters: [SceneParticleEmitterState]
    var random: SceneParticleRandomGenerator
    private var accumulator = 0.0
    private var nextParticleID: UInt64 = 0
    private(set) var explicitBirthEventStart: Int?
    let explicitInitializerWork: UInt64?
    private var normalizedLives: [Double] = []
    var dynamicControlPoints: [Int: SIMD3<Double>] = [:]
    /// The frame gravity conversion and world-space birth directions run
    /// through for the current advance: the caller's per-frame resolution of
    /// the layer's live world transform, falling back to the launch frame.
    var activeWorldSpaceFrame: SceneParticleWorldSpaceFrame?
    var dynamicControlPointAngles: [Int: SIMD3<Double>] = [:]
    var audioInput = SceneParticleAudioInput.silent
    /// Sticky per-system identities suppress repeated telemetry after the first
    /// non-silent evaluation. Both this set and its pending events participate
    /// in the existing particle frame transaction, so rejected frames cannot
    /// publish or consume execution evidence.
    private var observedNonSilentAudioComponents:
        Set<SceneParticleAudioComponentIdentity> = []
    private var pendingAudioEvaluationObservations:
        [SceneParticleAudioEvaluationObservation] = []
    var eventColorContext: SceneParticleEventColorContext
    private var stepSnapshotRecorder: SceneParticleStepSnapshotRecorder?
    var positionOscillationCache: [SceneParticleOscillationCacheKey: SceneParticlePositionOscillation] = [:]

    nonisolated init(
        definition: SceneParticleDefinition,
        instanceOverride: SceneParticleInstanceOverride? = nil,
        initialDynamicInstanceOverride: SceneParticleInstanceOverride? = nil,
        initialPlayback: SceneParticlePlaybackSnapshot = .init(),
        seed: UInt64 = 0,
        fixedTimeStep: Double = 1.0 / 60.0,
        particleBudget: Int? = nil,
        prewarmStepBudget: Int = 240,
        maximumEmissionDuration: Double? = nil,
        layerImageEmissionMap: SceneParticleLayerImageEmissionMap? = nil,
        worldSpaceFrame: SceneParticleWorldSpaceFrame? = nil,
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
        self.maximumEmissionDuration = maximumEmissionDuration
        self.layerImageEmissionMap = layerImageEmissionMap
        self.worldSpaceFrame = worldSpaceFrame
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
                definition: definition
            )
        }
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
        self.positionAroundControlPointPlans = definition.initializers.map { initializer in
            guard case .positionAroundControlPoint = initializer.kind,
                  definition.supportsBoundedPositionAroundControlPoint(initializer)
            else { return nil }
            return initializer.positionAroundControlPointPlan
        }
        initializerExecutionPlans = definition.initializers.map(
            SceneParticleInitializerExecutionPlan.init
        )
        explicitInitializerWork = Self.explicitInitializerWork(
            definition: definition, plans: initializerExecutionPlans,
            controlPointPlans: positionAroundControlPointPlans)
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
        diagnostics = SceneParticleSimulationMath.diagnostics(
            definition, instanceOverride, eventColorContext: eventColorContext
        )
        emitters = definition.emitters.indices.map {
            SceneParticleEmitterState(seed: seed, emitterIndex: $0)
        }
        random = SceneParticleRandomGenerator(state: seed)
        // The init-time warm-up runs the same emit/apply path as advance;
        // prewarmed world-space systems convert through the launch frame.
        activeWorldSpaceFrame = worldSpaceFrame
        warmUp(duration: definition.startTime ?? 0, stepBudget: prewarmStepBudget,
               historyCapacity: stepSnapshotPolicy?.maximumSnapshots ?? 0)
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
        guard duration.isFinite, duration > 0 else { return }
        let birthEventStart = explicitBirthEventStart ?? birthEvents.count
        explicitBirthEventStart = nil
        let deathEventStart = deathEvents.count
        for index in emitters.indices { emitters[index].beginFrame() }
        accumulator += duration
        while accumulator + 1e-12 >= fixedTimeStep {
            step(by: fixedTimeStep)
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

    nonisolated func evaluateAudioResponse(
        _ plan: SceneParticleAudioResponsePlan,
        componentKind: SceneParticleAudioComponentKind,
        componentIndex: Int
    ) -> Double {
        let identity = SceneParticleAudioComponentIdentity(
            kind: componentKind,
            index: componentIndex
        )
        guard audioInput.generation > 0,
              !observedNonSilentAudioComponents.contains(identity) else {
            return plan.evaluate(audioInput)
        }
        let evaluation = plan.evaluateForExecutionObservation(audioInput)
        guard evaluation.selectedNonZeroInputCount > 0 else {
            return evaluation.response
        }
        observedNonSilentAudioComponents.insert(identity)
        pendingAudioEvaluationObservations.append(.init(
            componentKind: componentKind,
            componentIndex: componentIndex,
            generation: audioInput.generation,
            channel: plan.channel.rawValue,
            frequencyStart: plan.frequencies.lowerBound,
            frequencyEnd: plan.frequencies.upperBound,
            selectedNonZeroInputCount: evaluation.selectedNonZeroInputCount
        ))
        return evaluation.response
    }

    nonisolated func consumeAudioEvaluationObservations()
        -> [SceneParticleAudioEvaluationObservation] {
        defer { pendingAudioEvaluationObservations.removeAll(keepingCapacity: true) }
        return pendingAudioEvaluationObservations
    }

    /// Child runtimes reuse one prepared template across short-lived simulator
    /// instances. Suppress component identities already observed by that
    /// template before advancing a new instance, so playback-level dedup does
    /// not leave recurring band scans and pending allocations in the hot path.
    nonisolated func suppressAudioEvaluationObservations(
        for identities: Set<SceneParticleAudioComponentIdentity>
    ) {
        guard !identities.isEmpty,
              !identities.isSubset(of: observedNonSilentAudioComponents) else {
            return
        }
        observedNonSilentAudioComponents.formUnion(identities)
        if !pendingAudioEvaluationObservations.isEmpty {
            pendingAudioEvaluationObservations.removeAll {
                identities.contains(.init(
                    kind: $0.componentKind,
                    index: $0.componentIndex
                ))
            }
        }
    }

    /// Captures mutable simulation state before a frame is admitted. The
    /// runtime keeps immutable definition/operator data shared; only the
    /// frame-varying state is copied and can be restored on host rejection.
    nonisolated func frameSnapshot() -> FrameSnapshot {
        FrameSnapshot(
            playback: playback,
            particles: particles,
            diagnostics: diagnostics,
            transientRenderBirths: transientRenderBirths,
            birthEvents: birthEvents,
            deathEvents: deathEvents,
            simulationTime: simulationTime,
            activeInstanceOverride: activeInstanceOverride,
            activeWorldSpaceFrame: activeWorldSpaceFrame,
            explicitBirthEventStart: explicitBirthEventStart,
            emitters: emitters,
            random: random,
            accumulator: accumulator,
            nextParticleID: nextParticleID,
            normalizedLives: normalizedLives,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            audioInput: audioInput,
            observedNonSilentAudioComponents: observedNonSilentAudioComponents,
            pendingAudioEvaluationObservations: pendingAudioEvaluationObservations,
            eventColorContext: eventColorContext,
            stepSnapshotRecorder: stepSnapshotRecorder,
            positionOscillationCache: positionOscillationCache
        )
    }

    nonisolated func restoreFrame(_ snapshot: FrameSnapshot) {
        playback = snapshot.playback
        particles = snapshot.particles
        diagnostics = snapshot.diagnostics
        transientRenderBirths = snapshot.transientRenderBirths
        birthEvents = snapshot.birthEvents
        deathEvents = snapshot.deathEvents
        simulationTime = snapshot.simulationTime
        activeInstanceOverride = snapshot.activeInstanceOverride
        activeWorldSpaceFrame = snapshot.activeWorldSpaceFrame
        explicitBirthEventStart = snapshot.explicitBirthEventStart
        emitters = snapshot.emitters
        random = snapshot.random
        accumulator = snapshot.accumulator
        nextParticleID = snapshot.nextParticleID
        normalizedLives = snapshot.normalizedLives
        dynamicControlPoints = snapshot.dynamicControlPoints
        dynamicControlPointAngles = snapshot.dynamicControlPointAngles
        audioInput = snapshot.audioInput
        observedNonSilentAudioComponents = snapshot.observedNonSilentAudioComponents
        pendingAudioEvaluationObservations = snapshot.pendingAudioEvaluationObservations
        eventColorContext = snapshot.eventColorContext
        stepSnapshotRecorder = snapshot.stepSnapshotRecorder
        positionOscillationCache = snapshot.positionOscillationCache
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

    private nonisolated func warmUp(duration: Double, stepBudget: Int, historyCapacity: Int) {
        guard duration != 0 else { return }
        let requestedSteps = (duration / fixedTimeStep).rounded(.up)
        guard duration.isFinite, duration > 0, requestedSteps.isFinite,
              requestedSteps < Double(Int.max) else {
            diagnostics.append(.init(kind: .prewarmInvalidDuration, componentName: nil))
            return
        }
        // Preserve the existing 240-step envelope for frame-created children.
        // Only root preparation requests more. The extension is deterministic,
        // capped at 3,600 steps and four million weighted work units; this is a
        // project admission policy, not a wall-clock or official fidelity bound.
        var limit = min(max(stepBudget, 0), 240)
        if stepBudget > 240, requestedSteps > 240 {
            let capacity = Double(maximumParticleCount)
            let initializerCost = definition.initializers.reduce(0.0) { cost, value in
                cost + 32 + Double(value.boundedPositionOffset?.octaves ?? 0) * 24
            }
            let operatorCost = definition.operators.reduce(0.0) { cost, value in
                if case .boids = value.kind { return cost + 32 + capacity }
                return cost + 32
            }
            // A retained RopeTrail snapshot can convert and shift the bounded
            // history on every step. Account for it without dropping that history.
            let historyCost = Double(historyCapacity)
            let workPerStep = max(1, Double(definition.emitters.count)
                + Double(definition.operators.count)
                + capacity * (32 + initializerCost + operatorCost + historyCost))
            let extraSteps = Int(min(3_360, (4_000_000 / workPerStep).rounded(.down)))
            limit = min(stepBudget, 240 + extraSteps)
        }
        let count = min(Int(requestedSteps), limit)
        var remaining = duration
        for _ in 0..<count {
            for index in emitters.indices { emitters[index].beginFrame() }
            let slice = min(fixedTimeStep, remaining)
            guard slice > 0 else { break }
            step(by: slice)
            // These events have never been replayed to children after warmup.
            // Drain per step so a long, short-lived emitter cannot retain its
            // entire prehistory. The bounded trail recorder remains intact.
            birthEvents.removeAll(keepingCapacity: true)
            deathEvents.removeAll(keepingCapacity: true)
            remaining -= slice
        }
        if Int(requestedSteps) > limit {
            diagnostics.append(.init(
                kind: .prewarmBudgetExceeded,
                componentName: "requested=\(duration),simulated=\(simulationTime),steps=\(count)"
            ))
        }
    }

    private nonisolated func step(by frameDuration: Double) {
        // Rate scales the entire simulation step once. Keep the wall-time step
        // budget unchanged instead of multiplying integration work by the rate.
        let duration = frameDuration * max(0, overrideScalar(activeInstanceOverride?.rate))
        guard duration != 0 else { return }
        guard duration.isFinite, Float(simulationTime + duration).isFinite else {
            let diagnostic = SceneParticleSimulationDiagnostic(
                kind: .invalidSimulationTime, componentName: "rate"
            )
            if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
            return
        }
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
            apply(value, operatorIndex: operatorIndex, duration: duration)
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
        if case .unsupported = emitter.kind { return }
        let spawnPlan = emitterSpawnPlans[index]
        guard let emitterFrame = definition.emitterControlPointFrame(
            for: emitter, instanceOverride: activeInstanceOverride,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            controlPointsByID: controlPointsByID,
            controlPointSourcesAreValid: controlPointSourcesAreValid,
            preparedOrigin: spawnPlan.origin
        ) else { return }
        guard let audioScale = emissionAudioScale(
            for: spawnPlan, emitterIndex: index
        ) else { return }
        // A scaled step may span many random windows. Reject before advancing
        // this emitter's schedule or RNG; at most 1024 full windows plus the
        // currently partial window can be visited by an accepted step.
        if case let .supported(periodic) = spawnPlan.periodicEmissionAdmission,
           duration > min(periodic.minimumDuration, periodic.minimumDelay) * 1024 {
            let diagnostic = SceneParticleSimulationDiagnostic(
                kind: .invalidEmitterState, componentName: "periodic-budget:\(index)"
            )
            if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
            return
        }
        guard let activeDuration = emitters[index].scheduledActiveDuration(
            plan: spawnPlan, stepDuration: duration,
            maximumEmissionDuration: maximumEmissionDuration
        ) else { return }

        var count = 0
        if !emitters[index].emittedInstantaneous, (spawnPlan.instantaneousCount ?? 0) > 0 {
            count = max(0, spawnPlan.instantaneousCount ?? 0)
            emitters[index].emittedInstantaneous = true
        } else {
            let authoredRate = spawnPlan.rate ?? 5
            let countScale = definition.flags.disablesCountOverrides
                ? 1
                : max(0, overrideScalar(activeInstanceOverride?.count))
            let scaledRate = (authoredRate.isFinite ? authoredRate : 0)
                * countScale * audioScale
            let rate = scaledRate.isFinite ? max(0, scaledRate) : 0
            let accumulated = emitters[index].remainder + rate * activeDuration
            guard accumulated.isFinite else {
                let diagnostic = SceneParticleSimulationDiagnostic(
                    kind: .invalidEmitterState, componentName: "emission:\(index)"
                )
                if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
                return
            }
            let integral = floor(accumulated + 1e-12)
            emitters[index].remainder = max(0, accumulated - integral)
            count = Int(min(integral, Double(maximumParticleCount)))
            count = emitters[index].boundedRateEmissionCount(
                count, limitsToOnePerFrame: spawnPlan.limitsToOnePerFrame
            )
        }
        count = min(count, maximumParticleCount - particles.count)
        for _ in 0..<count {
            if let particle = makeParticle(
                emitter, spawnPlan: spawnPlan, frame: emitterFrame
            ) {
                appendBirth(particle)
            }
        }
    }

    func appendBirth(_ particle: SceneParticleState) {
        particles.append(particle)
        birthEvents.append(particle)
    }

    func emitExplicitly(count: Int, context: EmissionContext,
                        chargeWork: (UInt64) throws -> Void) throws {
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
        guard let emitter = definition.emitters.first,
              let frame = definition.emitterControlPointFrame(
                for: emitter, instanceOverride: activeInstanceOverride,
                dynamicControlPoints: dynamicControlPoints,
                dynamicControlPointAngles: dynamicControlPointAngles,
                controlPointsByID: controlPointsByID,
                controlPointSourcesAreValid: controlPointSourcesAreValid,
                preparedOrigin: emitterSpawnPlans[0].origin) else {
            throw SceneParticleEmissionFailure.unavailable
        }
        if explicitBirthEventStart == nil { explicitBirthEventStart = birthEvents.count }
        for _ in 0..<count {
            try chargeWork(1 + 8 + initializerWork)
            guard let particle = makeParticle(emitter, spawnPlan: emitterSpawnPlans[0], frame: frame, strict: true) else {
                throw SceneParticleEmissionFailure.unavailable
            }
            appendBirth(particle)
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
        guard applyInitializers(to: &particle, strict: strict) else { return nil }
        particle.velocity = frame.direction(for: particle.velocity)
        applyInstanceOverride(to: &particle)
        if hasWorldSpaceMovement, let activeWorldSpaceFrame {
            particle.velocity = activeWorldSpaceFrame.localDirection(particle.velocity)
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
        let diagnostic = SceneParticleSimulationDiagnostic(
            kind: .invalidEmitterState, componentName: "particle-initialization"
        )
        if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
        return false
    }

    /// Reject only this particle's unsafe operator result, before either half
    /// of the integration is committed or narrowed to the GPU's Float ABI.
    private nonisolated func acceptsMotionResult(
        _ velocity: SIMD3<Double>, _ position: SIMD3<Double>, component: String
    ) -> Bool {
        if SceneParticleSimulationMath.isGPUFinite(velocity)
            && SceneParticleSimulationMath.isGPUFinite(position) {
            return true
        }
        let diagnostic = SceneParticleSimulationDiagnostic(
            kind: .invalidOperatorState, componentName: component
        )
        if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
        return false
    }

    private nonisolated func apply(
        _ value: SceneParticleOperator,
        operatorIndex: Int,
        duration: Double
    ) {
        guard operatorAudioExecutionAdmission[operatorIndex] else { return }
        switch value.kind {
        case .movement:
            guard let plan = operatorExecutionPlans[operatorIndex].movement else {
                break
            }
            let gravity = plan.gravity(through: activeWorldSpaceFrame)
                * effectiveSpeedOverride
            let radiusIsActive = maintainsVortexRadius && vortexOriginIsActive
            for index in particles.indices {
                if !radiusIsActive { particles[index].vortexRadius = nil }
                let acceleration = gravity - particles[index].velocity * plan.drag
                let integrated = particles[index].velocity + acceleration * duration
                let (position, velocity) = vortexMovement(
                    particle: particles[index], velocity: integrated, duration: duration
                )
                guard acceptsMotionResult(velocity, position, component: "movement") else {
                    continue
                }
                particles[index].velocity = velocity
                particles[index].position = position
            }
        case .angularMovement:
            guard let plan = operatorExecutionPlans[operatorIndex].angularMovement else {
                break
            }
            for index in particles.indices {
                let acceleration = plan.force - particles[index].angularVelocity * plan.drag
                let velocity = particles[index].angularVelocity + acceleration * duration
                let position = particles[index].rotation + velocity * duration
                guard acceptsMotionResult(velocity, position, component: "angularmovement") else {
                    continue
                }
                particles[index].angularVelocity = velocity
                particles[index].rotation = position
            }
        case .alphaFade:
            let executionPlan = operatorExecutionPlans[operatorIndex]
            guard let fadePlan = executionPlan.alphaFade else { break }
            for index in particles.indices {
                let life = normalizedLives[index]
                if life <= fadePlan.fadeIn {
                    particles[index].alpha *= SceneParticleSimulationMath.changeAmount(
                        life, 0, fadePlan.fadeIn
                    )
                }
                if life > fadePlan.fadeOut {
                    particles[index].alpha *= 1 - SceneParticleSimulationMath.changeAmount(
                        life, fadePlan.fadeOut, 1
                    )
                }
            }
        case .alphaChange:
            guard let plan = operatorExecutionPlans[operatorIndex].scalarChange else {
                break
            }
            for index in particles.indices {
                particles[index].alpha *= plan.value(at: normalizedLives[index])
            }
        case .sizeChange:
            guard let plan = operatorExecutionPlans[operatorIndex].scalarChange else {
                break
            }
            for index in particles.indices {
                particles[index].size *= plan.value(at: normalizedLives[index])
            }
        case .colorChange:
            guard let plan = operatorExecutionPlans[operatorIndex].colorChange else {
                break
            }
            for index in particles.indices {
                particles[index].color *= plan.value(at: normalizedLives[index])
            }
        case .oscillateAlpha:
            let executionPlan = operatorExecutionPlans[operatorIndex]
            guard let oscillationPlan = executionPlan.scalarOscillation else {
                break
            }
            let blend = executionPlan.blend
            for index in particles.indices {
                let factor = oscillationFactor(
                    oscillationPlan,
                    index,
                    operatorIndex,
                    age: particles[index].age
                )
                particles[index].alpha *= 1 + (factor - 1)
                    * operatorBlend(blend, normalizedLives[index])
            }
        case .oscillateSize:
            let executionPlan = operatorExecutionPlans[operatorIndex]
            guard let oscillationPlan = executionPlan.scalarOscillation else {
                break
            }
            let blend = executionPlan.blend
            for index in particles.indices {
                let factor = oscillationFactor(
                    oscillationPlan,
                    index,
                    operatorIndex,
                    age: particles[index].age,
                )
                particles[index].size *= 1 + (factor - 1)
                    * operatorBlend(blend, normalizedLives[index])
            }
        case .oscillatePosition:
            let executionPlan = operatorExecutionPlans[operatorIndex]
            guard let oscillationPlan = executionPlan.positionOscillation else {
                break
            }
            let mask = executionPlan.positionMask
            let blend = executionPlan.blend
            for index in particles.indices {
                let oscillation = positionOscillation(
                    oscillationPlan,
                    particleIndex: index,
                    operatorIndex: operatorIndex,
                    mask: mask
                )
                let delta = positionOscillationDelta(
                    oscillation,
                    blend: blend,
                    mask: mask,
                    age: particles[index].age,
                    lifetime: particles[index].lifetime,
                    duration: duration
                )
                SceneParticleSimulationMath.addFinite(
                    delta, to: &particles[index].position
                )
            }
        case .turbulence:
            guard let plan = turbulencePlans[operatorIndex] else { break }
            let speedOverride = effectiveSpeedOverride
            let phaseAudioFactor = plan.audioResponse.map {
                1 + evaluateAudioResponse(
                    $0, componentKind: .operator, componentIndex: operatorIndex
                )
            } ?? 1
            for index in particles.indices {
                let phase = turbulenceRandom(
                    plan.phaseMinimum, plan.phaseMaximum,
                    index, operatorIndex, 0
                ) * phaseAudioFactor
                let speed = turbulenceRandom(
                    plan.minimumSpeed, plan.maximumSpeed, index, operatorIndex, 1
                ) * speedOverride
                let direction = SceneParticleSimulationMath.turbulenceDirection(
                    position: particles[index].position,
                    time: simulationTime,
                    phase: phase,
                    scale: plan.scale,
                    timeScale: plan.timeScale,
                    mask: plan.mask
                )
                let delta = direction * speed * duration
                    * plan.blendAmount(normalizedLives[index])
                SceneParticleSimulationMath.addFinite(delta, to: &particles[index].velocity)
            }
        case .controlPointAttract:
            applyControlPointForce(
                plan: operatorExecutionPlans[operatorIndex].controlPointForce,
                duration: duration,
                normalizedLives: normalizedLives,
                blend: operatorExecutionPlans[operatorIndex].blend
            )
        case .boids:
            applyBoids(
                plan: operatorExecutionPlans[operatorIndex].boids,
                duration: duration
            )
        case .vortex:
            let audioScale = operatorExecutionPlans[operatorIndex].audioResponse.map {
                evaluateAudioResponse(
                    $0, componentKind: .operator, componentIndex: operatorIndex
                )
            }
            applyVortex(
                plan: operatorExecutionPlans[operatorIndex].vortex,
                duration: duration,
                audioScale: audioScale
            )
        case .capVelocity:
            applyCapVelocity(
                plan: operatorExecutionPlans[operatorIndex].capVelocity,
                blendPlan: operatorExecutionPlans[operatorIndex].blend
            )
        case .remapValue:
            if let plan = operatorExecutionPlans[operatorIndex].scalarSpeedRemap {
                for index in particles.indices {
                    guard let multiplier = SceneParticleSimulationMath.scalarSpeedRemapMultiplier(
                        plan, normalizedLife: normalizedLives[index],
                        particleID: particles[index].id, simulationSeed: simulationSeed
                    ) else { continue }
                    let velocity = particles[index].velocity * multiplier
                    guard acceptsMotionResult(velocity, particles[index].position,
                        component: "remapvalue-speed") else { continue }
                    particles[index].velocity = velocity
                }
                break
            }
            guard let plan = operatorExecutionPlans[operatorIndex].velocityRemap else {
                break
            }
            for index in particles.indices {
                guard let amount = SceneParticleSimulationMath.remapNoiseAmount(
                    position: particles[index].position,
                    time: simulationTime,
                    particleID: particles[index].id,
                    simulationSeed: simulationSeed,
                    inputScale: plan.inputScale
                ) else { continue }
                particles[index].velocity = plan.minimum
                    + (plan.maximum - plan.minimum) * amount
            }
        case .reduceMovement:
            applyReduceMovement(
                plan: operatorExecutionPlans[operatorIndex].reduceMovement,
                duration: duration
            )
        case .collisionPlane:
            applyCollisionPlane(
                plan: operatorExecutionPlans[operatorIndex].collisionPlane
            )
        case let .inheritEventColor(declaration):
            guard declaration.isBoundedSetColor,
                  let color = eventColorContext.operatorColor else { break }
            for index in particles.indices { particles[index].color = color }
        case .unsupported:
            break
        }
    }

}
