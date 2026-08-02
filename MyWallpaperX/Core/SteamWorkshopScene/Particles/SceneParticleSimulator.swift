import Foundation

nonisolated struct SceneParticleSimulator: Sendable {
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
    let simulationSeed: UInt64
    private var emitters: [SceneParticleEmitterState]
    var random: SceneParticleRandomGenerator
    private var accumulator = 0.0
    private var nextParticleID: UInt64 = 0
    private var normalizedLives: [Double] = []
    var dynamicControlPoints: [Int: SIMD3<Double>] = [:]
    var audioInput = SceneParticleAudioInput.silent
    private var stepSnapshotRecorder: SceneParticleStepSnapshotRecorder?
    var positionOscillationCache: [SceneParticleOscillationCacheKey: SceneParticlePositionOscillation] = [:]

    nonisolated init(
        definition: SceneParticleDefinition,
        instanceOverride: SceneParticleInstanceOverride? = nil,
        seed: UInt64 = 0,
        fixedTimeStep: Double = 1.0 / 60.0,
        particleBudget: Int? = nil,
        emissionDeadline: Double? = nil,
        layerImageEmissionMap: SceneParticleLayerImageEmissionMap? = nil,
        worldSpaceFrame: SceneParticleWorldSpaceFrame? = nil,
        stepSnapshotPolicy: SceneParticleStepSnapshotPolicy? = nil
    ) {
        self.definition = definition
        self.instanceOverride = instanceOverride
        self.activeInstanceOverride = instanceOverride
        self.emissionDeadline = emissionDeadline
        self.layerImageEmissionMap = layerImageEmissionMap
        self.worldSpaceFrame = worldSpaceFrame
        self.hasWorldSpaceMovement = definition.operators.contains(
            where: \.isWorldSpaceMovement
        )
        self.stepSnapshotRecorder = stepSnapshotPolicy.map(
            SceneParticleStepSnapshotRecorder.init(policy:)
        )
        self.simulationSeed = seed
        self.fixedTimeStep = fixedTimeStep.isFinite && fixedTimeStep > 0 ? fixedTimeStep : 1.0 / 60.0
        let authoredMaximum = min(max(definition.maximumCount ?? 1, 0), 20_000)
        maximumParticleCount = min(authoredMaximum, max(particleBudget ?? authoredMaximum, 0))
        diagnostics = SceneParticleSimulationMath.diagnostics(definition, instanceOverride)
        emitters = definition.emitters.indices.map {
            SceneParticleEmitterState(seed: seed, emitterIndex: $0)
        }
        random = SceneParticleRandomGenerator(state: seed)
        warmUp(duration: max(0, definition.startTime ?? 0))
        birthEvents.removeAll(keepingCapacity: true)
        deathEvents.removeAll(keepingCapacity: true)
    }

    nonisolated mutating func advance(
        by duration: Double,
        dynamicControlPoints: [Int: SIMD3<Double>] = [:],
        dynamicInstanceOverride: SceneParticleInstanceOverride? = nil,
        audioInput: SceneParticleAudioInput = .silent
    ) {
        self.dynamicControlPoints = dynamicControlPoints
        activeInstanceOverride = dynamicInstanceOverride ?? instanceOverride
        self.audioInput = audioInput
        guard duration.isFinite, duration > 0 else { return }
        accumulator += duration
        while accumulator + 1e-12 >= fixedTimeStep {
            step(by: fixedTimeStep)
            accumulator -= fixedTimeStep
        }
        if accumulator < 0 { accumulator = 0 }
    }

    nonisolated mutating func consumeBirthEvents() -> [SceneParticleState] {
        defer { birthEvents.removeAll(keepingCapacity: true) }
        return birthEvents
    }

    nonisolated mutating func consumeDeathEvents() -> [SceneParticleState] {
        defer { deathEvents.removeAll(keepingCapacity: true) }
        return deathEvents
    }

    nonisolated mutating func consumeStepSnapshots() -> [SceneParticleStepSnapshot] {
        stepSnapshotRecorder?.consume() ?? []
    }

    private nonisolated mutating func warmUp(duration: Double) {
        guard duration > 0 else { return }
        let count = min(max(Int(ceil(duration / fixedTimeStep)), 1), 240)
        let stepDuration = duration / Double(count)
        for _ in 0..<count { step(by: stepDuration) }
    }

    private nonisolated mutating func step(by duration: Double) {
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
        for particle in particles where particle.age + 1e-12 >= particle.lifetime {
            deathEvents.append(particle)
            for (operatorIndex, value) in definition.operators.enumerated()
            where value.kind == .oscillatePosition {
                positionOscillationCache.removeValue(forKey: .init(
                    particleID: particle.id, operatorIndex: operatorIndex
                ))
            }
        }
        particles.removeAll { $0.age + 1e-12 >= $0.lifetime }
        simulationTime += duration
        stepSnapshotRecorder?.record(duration: duration, particles: particles)
    }

    private nonisolated mutating func emit(index: Int, duration: Double) {
        let emitter = definition.emitters[index]
        if case .unsupported = emitter.kind { return }
        guard let audioScale = emissionAudioScale(for: emitter) else { return }
        if emitter.usesRandomPeriodicEmission,
           activeInstanceOverride?.rate != nil || activeInstanceOverride?.count != nil { return }
        let rateScale = max(0, overrideScalar(activeInstanceOverride?.rate))
        guard let activeDuration = emitters[index].scheduledActiveDuration(
            for: emitter, stepDuration: duration, rateScale: rateScale
        ) else { return }

        var count = 0
        if !emitters[index].emittedInstantaneous, (emitter.instantaneousCount ?? 0) > 0 {
            count = max(0, emitter.instantaneousCount ?? 0)
            emitters[index].emittedInstantaneous = true
        } else {
            // Event-child rate emission ends at the bounded window; bursts already fired.
            if let deadline = emissionDeadline, simulationTime + 1e-12 >= deadline { return }
            let authoredRate = emitter.rate ?? 5
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
            if emitter.limitsToOnePerFrame { count = min(count, 1) }
        }
        count = min(count, maximumParticleCount - particles.count)
        for _ in 0..<count {
            if let particle = makeParticle(emitter) {
                particles.append(particle)
                birthEvents.append(particle)
            }
        }
    }

    private nonisolated mutating func makeParticle(
        _ emitter: SceneParticleEmitter
    ) -> SceneParticleState? {
        guard let frame = definition.emitterControlPointFrame(
            for: emitter, instanceOverride: activeInstanceOverride,
            dynamicControlPoints: dynamicControlPoints
        ), emitter.hasBoundedDirectionsAndSign else { return nil }
        var velocity = SIMD3<Double>.zero
        let relative: SIMD3<Double>
        switch emitter.kind {
        case .sphereRandom:
            relative = randomSphereOffset(emitter)
        case .boxRandom:
            relative = randomBoxOffset(emitter)
        case .layerImage:
            guard let point = layerImageEmissionMap?.sample(using: &random) else { return nil }
            relative = point
        case .unsupported:
            return nil
        }
        let position = frame.position(for: relative)
        guard let speedRange = emitter.boundedSpeedRange else { return nil }
        let speed = random.value(speedRange.lowerBound, speedRange.upperBound)
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

    private nonisolated mutating func applyInitializers(to particle: inout SceneParticleState) {
        for initializer in definition.initializers {
            switch initializer.kind {
            case .lifetime:
                particle.lifetime = randomScalar(initializer, defaults: (0, 1))
            case .size:
                particle.size = randomScalar(initializer, defaults: (0, 20))
            case .velocity:
                particle.velocity += randomVector(initializer, defaults: (SIMD3(-32, -32, 0), SIMD3(32, 32, 0)))
            case .color:
                particle.color = randomColor(
                    initializer, defaults: (.zero, SIMD3(repeating: 255))
                ) / 255
            case .alpha:
                particle.alpha = randomScalar(initializer, defaults: (0.05, 1))
            case .rotation:
                particle.rotation += randomVector(initializer, defaults: (.zero, SIMD3(0, 0, 2 * .pi)))
            case .angularVelocity:
                particle.angularVelocity += randomVector(
                    initializer, defaults: (SIMD3(0, 0, -5), SIMD3(0, 0, 5))
                )
            case .turbulentVelocity:
                particle.velocity += SceneParticleSimulationMath.turbulentVelocity(
                    initializer.turbulentVelocity, particle.position, simulationTime,
                    &random, audioInput: audioInput
                )
            case .unsupported:
                break
            }
        }
    }

    private nonisolated mutating func apply(
        _ value: SceneParticleOperator,
        operatorIndex: Int,
        duration: Double
    ) {
        guard admitsAudioExecution(value) else { return }
        switch value.kind {
        case .movement:
            let authoredGravity = SceneParticleSimulationMath.vector(
                value.gravity,
                fallback: .zero
            )
            let gravity = value.isWorldSpaceMovement
                ? worldSpaceFrame?.localDirection(authoredGravity) ?? authoredGravity
                : authoredGravity
            let drag = max(0, value.drag ?? 0)
            for index in particles.indices {
                let acceleration = gravity - particles[index].velocity * drag
                particles[index].velocity += acceleration * duration
                particles[index].position += particles[index].velocity * duration
            }
        case .angularMovement:
            let force = SceneParticleSimulationMath.vector(value.force, fallback: .zero)
            let drag = max(0, value.drag ?? 0)
            for index in particles.indices {
                let acceleration = force - particles[index].angularVelocity * drag
                particles[index].angularVelocity += acceleration * duration
                particles[index].rotation += particles[index].angularVelocity * duration
            }
        case .alphaFade:
            let fadeIn = max(0, value.fadeInTime ?? 0.5)
            let fadeOut = min(max(value.fadeOutTime ?? 0.5, 0), 1)
            for index in particles.indices {
                let life = normalizedLives[index]
                if life <= fadeIn { particles[index].alpha *= SceneParticleSimulationMath.changeAmount(life, 0, fadeIn) }
                if life > fadeOut { particles[index].alpha *= 1 - SceneParticleSimulationMath.changeAmount(life, fadeOut, 1) }
            }
        case .alphaChange:
            for index in particles.indices {
                particles[index].alpha *= changeFactor(value, life: normalizedLives[index], fallback: (1, 0))
            }
        case .sizeChange:
            for index in particles.indices {
                particles[index].size *= changeFactor(value, life: normalizedLives[index], fallback: (1, 0))
            }
        case .colorChange:
            let start = SceneParticleSimulationMath.vector(value.startValue, fallback: SIMD3(repeating: 1))
            let end = SceneParticleSimulationMath.vector(value.endValue, fallback: .zero)
            for index in particles.indices {
                let amount = SceneParticleSimulationMath.changeAmount(
                    normalizedLives[index], value.startTime, value.endTime
                )
                particles[index].color *= start + (end - start) * amount
            }
        case .oscillateAlpha:
            for index in particles.indices {
                let factor = oscillationFactor(
                    value,
                    index,
                    operatorIndex,
                    life: normalizedLives[index]
                )
                particles[index].alpha *= 1 + (factor - 1)
                    * operatorBlend(value, normalizedLives[index])
            }
        case .oscillateSize:
            for index in particles.indices {
                let factor = oscillationFactor(
                    value,
                    index,
                    operatorIndex,
                    life: normalizedLives[index],
                    sizeDefaults: true
                )
                particles[index].size *= 1 + (factor - 1)
                    * operatorBlend(value, normalizedLives[index])
            }
        case .oscillatePosition:
            let mask = SceneParticleSimulationMath.vector(value.mask, fallback: SIMD3(1, 1, 0))
            for index in particles.indices {
                let oscillation = positionOscillation(
                    value, particleIndex: index, operatorIndex: operatorIndex, mask: mask
                )
                let delta = positionOscillationDelta(
                    oscillation,
                    value: value,
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
            let scale = SceneParticleSimulationMath.scalar(value.scale, fallback: 0.005)
            let timeScale = value.timeScale ?? 0.01
            let mask = SceneParticleSimulationMath.vector(value.mask, fallback: SIMD3(1, 1, 0))
            let rawMinimumSpeed = value.speedMinimum ?? 500
            let rawMaximumSpeed = value.speedMaximum ?? 1_000
            guard scale.isFinite, timeScale.isFinite,
                  rawMinimumSpeed.isFinite, rawMaximumSpeed.isFinite else { break }
            let minimumSpeed = max(rawMinimumSpeed, 0)
            let maximumSpeed = max(rawMaximumSpeed, minimumSpeed)
            let speedOverride = overrideScalar(activeInstanceOverride?.speed)
            for index in particles.indices {
                let phase = turbulenceRandom(
                    value.phaseMinimum ?? 0, value.phaseMaximum ?? 0,
                    index, operatorIndex, 0
                ) * audioPhaseFactor(value.audioResponse)
                let speed = turbulenceRandom(
                    minimumSpeed, maximumSpeed, index, operatorIndex, 1
                ) * speedOverride
                let direction = SceneParticleSimulationMath.turbulenceDirection(
                    position: particles[index].position,
                    time: simulationTime,
                    phase: phase,
                    scale: scale,
                    timeScale: timeScale,
                    mask: mask
                )
                let delta = direction * speed * duration
                    * operatorBlend(value, normalizedLives[index])
                SceneParticleSimulationMath.addFinite(delta, to: &particles[index].velocity)
            }
        case .controlPointAttract:
            applyControlPointForce(value, duration: duration)
        case .boids:
            applyBoids(value, duration: duration)
        case .vortex:
            applyVortex(value, duration: duration)
        case .capVelocity:
            applyCapVelocity(value)
        case .unsupported:
            break
        }
    }

}
