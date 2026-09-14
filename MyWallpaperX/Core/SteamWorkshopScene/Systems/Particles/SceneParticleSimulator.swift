import Foundation

/// One mutable simulator owns one persistent authored particle-system instance.
///
/// Keep this as reference identity: layer and child runtime containers are value
/// records that are frequently traversed or copied while retaining the same live
/// system. Making the simulator itself a value copied its particle buffers through
/// those records and forced Array COW checks throughout every operator hot path.
nonisolated final class SceneParticleSimulator: @unchecked Sendable {
    struct FrameSnapshot {
        let particles: [SceneParticleState]
        let birthEvents: [SceneParticleState]
        let deathEvents: [SceneParticleState]
        let simulationTime: Double
        let activeInstanceOverride: SceneParticleInstanceOverride?
        let emitters: [SceneParticleEmitterState]
        let random: SceneParticleRandomGenerator
        let accumulator: Double
        let nextParticleID: UInt64
        let normalizedLives: [Double]
        let dynamicControlPoints: [Int: SIMD3<Double>]
        let dynamicControlPointAngles: [Int: SIMD3<Double>]
        let audioInput: SceneParticleAudioInput
        let eventColorContext: SceneParticleEventColorContext
        let stepSnapshotRecorder: SceneParticleStepSnapshotRecorder?
        let positionOscillationCache: [SceneParticleOscillationCacheKey: SceneParticlePositionOscillation]
    }

    let fixedTimeStep: Double
    let maximumParticleCount: Int
    let diagnostics: [SceneParticleSimulationDiagnostic]
    var particles: [SceneParticleState] = []
    private(set) var birthEvents: [SceneParticleState] = []
    private(set) var deathEvents: [SceneParticleState] = []
    private(set) var simulationTime = 0.0
    let definition: SceneParticleDefinition
    let instanceOverride: SceneParticleInstanceOverride?
    var activeInstanceOverride: SceneParticleInstanceOverride?
    private let emissionDeadline: Double?
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
    private var normalizedLives: [Double] = []
    var dynamicControlPoints: [Int: SIMD3<Double>] = [:]
    var dynamicControlPointAngles: [Int: SIMD3<Double>] = [:]
    var audioInput = SceneParticleAudioInput.silent
    var eventColorContext: SceneParticleEventColorContext
    private var stepSnapshotRecorder: SceneParticleStepSnapshotRecorder?
    var positionOscillationCache: [SceneParticleOscillationCacheKey: SceneParticlePositionOscillation] = [:]

    nonisolated init(
        definition: SceneParticleDefinition,
        instanceOverride: SceneParticleInstanceOverride? = nil,
        initialDynamicInstanceOverride: SceneParticleInstanceOverride? = nil,
        seed: UInt64 = 0,
        fixedTimeStep: Double = 1.0 / 60.0,
        particleBudget: Int? = nil,
        emissionDeadline: Double? = nil,
        layerImageEmissionMap: SceneParticleLayerImageEmissionMap? = nil,
        worldSpaceFrame: SceneParticleWorldSpaceFrame? = nil,
        stepSnapshotPolicy: SceneParticleStepSnapshotPolicy? = nil,
        eventColorContext: SceneParticleEventColorContext = .unavailable
    ) {
        self.definition = definition
        self.instanceOverride = instanceOverride
        self.activeInstanceOverride = initialDynamicInstanceOverride ?? instanceOverride
        self.emissionDeadline = emissionDeadline
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
                definition: definition,
                worldSpaceFrame: worldSpaceFrame
            )
        }
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
        warmUp(duration: max(0, definition.startTime ?? 0))
        birthEvents.removeAll(keepingCapacity: true)
        deathEvents.removeAll(keepingCapacity: true)
    }

    nonisolated func advance(
        by duration: Double,
        dynamicControlPoints: [Int: SIMD3<Double>] = [:],
        dynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        dynamicInstanceOverride: SceneParticleInstanceOverride? = nil,
        audioInput: SceneParticleAudioInput = .silent
    ) {
        self.dynamicControlPoints = dynamicControlPoints
        self.dynamicControlPointAngles = dynamicControlPointAngles
        activeInstanceOverride = dynamicInstanceOverride ?? instanceOverride
        self.audioInput = audioInput
        guard duration.isFinite, duration > 0 else { return }
        for index in emitters.indices { emitters[index].beginFrame() }
        accumulator += duration
        while accumulator + 1e-12 >= fixedTimeStep {
            step(by: fixedTimeStep)
            accumulator -= fixedTimeStep
        }
        if accumulator < 0 { accumulator = 0 }
    }

    nonisolated func consumeBirthEvents() -> [SceneParticleState] {
        defer { birthEvents.removeAll(keepingCapacity: true) }
        return birthEvents
    }

    nonisolated func consumeDeathEvents() -> [SceneParticleState] {
        defer { deathEvents.removeAll(keepingCapacity: true) }
        return deathEvents
    }

    nonisolated func consumeStepSnapshots() -> [SceneParticleStepSnapshot] {
        stepSnapshotRecorder?.consume() ?? []
    }

    /// Captures mutable simulation state before a frame is admitted. The
    /// runtime keeps immutable definition/operator data shared; only the
    /// frame-varying state is copied and can be restored on host rejection.
    nonisolated func frameSnapshot() -> FrameSnapshot {
        FrameSnapshot(
            particles: particles,
            birthEvents: birthEvents,
            deathEvents: deathEvents,
            simulationTime: simulationTime,
            activeInstanceOverride: activeInstanceOverride,
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
            positionOscillationCache: positionOscillationCache
        )
    }

    nonisolated func restoreFrame(_ snapshot: FrameSnapshot) {
        particles = snapshot.particles
        birthEvents = snapshot.birthEvents
        deathEvents = snapshot.deathEvents
        simulationTime = snapshot.simulationTime
        activeInstanceOverride = snapshot.activeInstanceOverride
        emitters = snapshot.emitters
        random = snapshot.random
        accumulator = snapshot.accumulator
        nextParticleID = snapshot.nextParticleID
        normalizedLives = snapshot.normalizedLives
        dynamicControlPoints = snapshot.dynamicControlPoints
        dynamicControlPointAngles = snapshot.dynamicControlPointAngles
        audioInput = snapshot.audioInput
        eventColorContext = snapshot.eventColorContext
        stepSnapshotRecorder = snapshot.stepSnapshotRecorder
        positionOscillationCache = snapshot.positionOscillationCache
    }

    nonisolated func updateFollowEventColor(_ color: SIMD3<Double>) {
        guard case .follow = eventColorContext else { return }
        eventColorContext = .follow(color)
    }

    private nonisolated func warmUp(duration: Double) {
        guard duration > 0 else { return }
        let count = min(max(Int(ceil(duration / fixedTimeStep)), 1), 240)
        let stepDuration = duration / Double(count)
        for _ in 0..<count {
            for index in emitters.indices { emitters[index].beginFrame() }
            step(by: stepDuration)
        }
    }

    private nonisolated func step(by duration: Double) {
        for index in definition.emitters.indices { emit(index: index, duration: duration) }
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
        guard let audioScale = emissionAudioScale(for: spawnPlan) else { return }
        if spawnPlan.usesRandomPeriodicEmission,
           activeInstanceOverride?.rate != nil || activeInstanceOverride?.count != nil { return }
        let rateScale = max(0, overrideScalar(activeInstanceOverride?.rate))
        guard let activeDuration = emitters[index].scheduledActiveDuration(
            plan: spawnPlan, stepDuration: duration, rateScale: rateScale
        ) else { return }

        var count = 0
        if !emitters[index].emittedInstantaneous, (spawnPlan.instantaneousCount ?? 0) > 0 {
            count = max(0, spawnPlan.instantaneousCount ?? 0)
            emitters[index].emittedInstantaneous = true
        } else {
            // Event-child rate emission ends at the bounded window; bursts already fired.
            if let deadline = emissionDeadline, simulationTime + 1e-12 >= deadline { return }
            let authoredRate = spawnPlan.rate ?? 5
            let countScale = definition.flags.disablesCountOverrides
                ? 1
                : max(0, overrideScalar(activeInstanceOverride?.count))
            let scaledRate = (authoredRate.isFinite ? authoredRate : 0)
                * countScale * rateScale * audioScale
            let rate = scaledRate.isFinite ? max(0, scaledRate) : 0
            emitters[index].remainder += rate * activeDuration
            let integral = floor(emitters[index].remainder + 1e-12)
            emitters[index].remainder -= integral
            count = Int(min(integral, Double(maximumParticleCount)))
            count = emitters[index].boundedRateEmissionCount(
                count, limitsToOnePerFrame: spawnPlan.limitsToOnePerFrame
            )
        }
        count = min(count, maximumParticleCount - particles.count)
        for _ in 0..<count {
            if let particle = makeParticle(emitter, spawnPlan: spawnPlan) {
                particles.append(particle)
                birthEvents.append(particle)
            }
        }
    }

    private nonisolated func makeParticle(
        _ emitter: SceneParticleEmitter,
        spawnPlan: SceneParticleEmitterSpawnPlan
    ) -> SceneParticleState? {
        guard let frame = definition.emitterControlPointFrame(
            for: emitter, instanceOverride: activeInstanceOverride,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            controlPointsByID: controlPointsByID,
            controlPointSourcesAreValid: controlPointSourcesAreValid,
            preparedOrigin: spawnPlan.origin
        ), spawnPlan.hasBoundedDirectionsAndSign,
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
        applyInitializers(to: &particle)
        particle.velocity = frame.direction(for: particle.velocity)
        applyInstanceOverride(to: &particle, flags: definition.flags)
        if hasWorldSpaceMovement, let worldSpaceFrame {
            particle.velocity = worldSpaceFrame.localDirection(particle.velocity)
        }
        particle.initialColor = particle.color
        particle.initialAlpha = particle.alpha
        particle.initialSize = particle.size
        return particle.lifetime > 0 ? particle : nil
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
            for index in particles.indices {
                let acceleration = plan.gravity - particles[index].velocity * plan.drag
                particles[index].velocity += acceleration * duration
                particles[index].position += particles[index].velocity * duration
            }
        case .angularMovement:
            guard let plan = operatorExecutionPlans[operatorIndex].angularMovement else {
                break
            }
            for index in particles.indices {
                let acceleration = plan.force - particles[index].angularVelocity * plan.drag
                particles[index].angularVelocity += acceleration * duration
                particles[index].rotation += particles[index].angularVelocity * duration
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
            let speedOverride = overrideScalar(activeInstanceOverride?.speed)
            let phaseAudioFactor = plan.audioResponse.map {
                1 + $0.evaluate(audioInput)
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
            applyVortex(
                plan: operatorExecutionPlans[operatorIndex].vortex,
                duration: duration,
                audioResponsePlan: operatorExecutionPlans[operatorIndex].audioResponse
            )
        case .capVelocity:
            applyCapVelocity(
                plan: operatorExecutionPlans[operatorIndex].capVelocity,
                blendPlan: operatorExecutionPlans[operatorIndex].blend
            )
        case .remapValue:
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
