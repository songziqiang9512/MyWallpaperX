import Foundation

nonisolated struct SceneParticleSimulator: Sendable {
    private struct EmitterState: Sendable {
        var elapsed = 0.0
        var remainder = 0.0
        var emittedInstantaneous = false
    }

    let fixedTimeStep: Double
    let maximumParticleCount: Int
    let diagnostics: [SceneParticleSimulationDiagnostic]
    private(set) var particles: [SceneParticleState] = []
    private(set) var birthEvents: [SceneParticleState] = []
    private(set) var deathEvents: [SceneParticleState] = []
    private(set) var simulationTime = 0.0

    private let definition: SceneParticleDefinition
    let instanceOverride: SceneParticleInstanceOverride?
    private let emissionDeadline: Double?
    private let worldSpaceFrame: SceneParticleWorldSpaceFrame?
    private let hasWorldSpaceMovement: Bool
    let simulationSeed: UInt64
    private var emitters: [EmitterState]
    var random: SceneParticleRandomGenerator
    private var accumulator = 0.0
    private var nextParticleID: UInt64 = 0
    private var normalizedLives: [Double] = []
    var positionOscillationCache: [SceneParticleOscillationCacheKey: SceneParticlePositionOscillation] = [:]

    nonisolated init(
        definition: SceneParticleDefinition,
        instanceOverride: SceneParticleInstanceOverride? = nil,
        seed: UInt64 = 0,
        fixedTimeStep: Double = 1.0 / 60.0,
        particleBudget: Int? = nil,
        emissionDeadline: Double? = nil,
        worldSpaceFrame: SceneParticleWorldSpaceFrame? = nil
    ) {
        self.definition = definition
        self.instanceOverride = instanceOverride
        self.emissionDeadline = emissionDeadline
        self.worldSpaceFrame = worldSpaceFrame
        self.hasWorldSpaceMovement = definition.operators.contains(
            where: \.isWorldSpaceMovement
        )
        self.simulationSeed = seed
        self.fixedTimeStep = fixedTimeStep.isFinite && fixedTimeStep > 0 ? fixedTimeStep : 1.0 / 60.0
        let authoredMaximum = min(max(definition.maximumCount ?? 1, 0), 20_000)
        maximumParticleCount = min(authoredMaximum, max(particleBudget ?? authoredMaximum, 0))
        diagnostics = SceneParticleSimulationMath.diagnostics(definition, instanceOverride)
        emitters = Array(repeating: EmitterState(), count: definition.emitters.count)
        random = SceneParticleRandomGenerator(state: seed)
        warmUp(duration: max(0, definition.startTime ?? 0))
        birthEvents.removeAll(keepingCapacity: true)
        deathEvents.removeAll(keepingCapacity: true)
    }

    nonisolated mutating func advance(by duration: Double) {
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
    }

    private nonisolated mutating func emit(index: Int, duration: Double) {
        let emitter = definition.emitters[index]
        if case .unsupported = emitter.kind { return }
        let rateScale = max(0, overrideScalar(instanceOverride?.rate))
        emitters[index].elapsed += duration * rateScale
        if let limit = emitter.duration, limit > 0, emitters[index].elapsed > limit + 1e-12 { return }

        var count = 0
        if !emitters[index].emittedInstantaneous, (emitter.instantaneousCount ?? 0) > 0 {
            count = max(0, emitter.instantaneousCount ?? 0)
            emitters[index].emittedInstantaneous = true
        } else {
            // Event-child rate emission ends at the bounded window; bursts already fired.
            if let deadline = emissionDeadline, simulationTime + 1e-12 >= deadline { return }
            let authoredRate = emitter.rate ?? 5
            let scaledRate = (authoredRate.isFinite ? authoredRate : 0)
                * max(0, overrideScalar(instanceOverride?.count)) * rateScale
            let rate = scaledRate.isFinite ? max(0, scaledRate) : 0
            emitters[index].remainder += rate * duration
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
        var position = emitterOrigin(emitter)
        var velocity = SIMD3<Double>.zero
        let relative: SIMD3<Double>
        switch emitter.kind {
        case .sphereRandom:
            relative = randomSphereOffset(emitter)
        case .boxRandom:
            relative = randomBoxOffset(emitter)
        case .unsupported:
            return nil
        }
        position += relative
        let speed = random.value(emitter.speedMinimum ?? 0, emitter.speedMaximum ?? 0)
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
        applyInstanceOverride(to: &particle)
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
                particle.velocity += SceneParticleSimulationMath.turbulentVelocity(initializer.turbulentVelocity, particle.position, simulationTime, &random)
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
                let factor = oscillationFactor(value, index, operatorIndex)
                particles[index].alpha *= 1 + (factor - 1)
                    * oscillationBlend(value, normalizedLives[index])
            }
        case .oscillateSize:
            for index in particles.indices {
                let factor = oscillationFactor(value, index, operatorIndex, sizeDefaults: true)
                particles[index].size *= 1 + (factor - 1)
                    * oscillationBlend(value, normalizedLives[index])
            }
        case .oscillatePosition:
            let mask = SceneParticleSimulationMath.vector(value.mask, fallback: SIMD3(1, 1, 0))
            for index in particles.indices {
                let blend = oscillationBlend(value, normalizedLives[index])
                let oscillation = positionOscillation(
                    value, particleIndex: index, operatorIndex: operatorIndex, mask: mask
                )
                for component in 0..<3 where abs(mask[component]) > 1e-6 {
                    let frequency = oscillation.frequency[component]
                    particles[index].position[component] -= oscillation.scale[component]
                        * frequency
                        * sin(frequency * particles[index].age + oscillation.phase[component])
                        * duration * blend
                }
            }
        case .turbulence:
            guard !value.audioResponse.isEnabled else { break }
            let scale = SceneParticleSimulationMath.scalar(value.scale, fallback: 0.005)
            let timeScale = value.timeScale ?? 0.01
            let mask = SceneParticleSimulationMath.vector(value.mask, fallback: SIMD3(1, 1, 0))
            let rawMinimumSpeed = value.speedMinimum ?? 500
            let rawMaximumSpeed = value.speedMaximum ?? 1_000
            guard scale.isFinite, timeScale.isFinite,
                  rawMinimumSpeed.isFinite, rawMaximumSpeed.isFinite else { break }
            let minimumSpeed = max(rawMinimumSpeed, 0)
            let maximumSpeed = max(rawMaximumSpeed, minimumSpeed)
            let speedOverride = overrideScalar(instanceOverride?.speed)
            for index in particles.indices {
                let phase = turbulenceRandom(
                    value.phaseMinimum ?? 0, value.phaseMaximum ?? 0,
                    index, operatorIndex, 0
                )
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
                    * oscillationBlend(value, normalizedLives[index])
                SceneParticleSimulationMath.addFinite(delta, to: &particles[index].velocity)
            }
        case .controlPointAttract, .vortex, .unsupported:
            break
        }
    }

    private nonisolated func changeFactor(
        _ value: SceneParticleOperator,
        life: Double,
        fallback: (Double, Double)
    ) -> Double {
        let start = SceneParticleSimulationMath.scalar(value.startValue, fallback: fallback.0)
        let end = SceneParticleSimulationMath.scalar(value.endValue, fallback: fallback.1)
        return start + (end - start) * SceneParticleSimulationMath.changeAmount(
            life, value.startTime, value.endTime
        )
    }

    private nonisolated func oscillationFactor(
        _ value: SceneParticleOperator,
        _ index: Int,
        _ operatorIndex: Int,
        sizeDefaults: Bool = false
    ) -> Double {
        let minimum = SceneParticleSimulationMath.scalar(value.scaleMinimum, fallback: sizeDefaults ? 0.8 : 0)
        let maximum = SceneParticleSimulationMath.scalar(value.scaleMaximum, fallback: sizeDefaults ? 1.2 : 1)
        let frequency = oscillationRandom(value.frequencyMinimum ?? 0, value.frequencyMaximum ?? 10, index, operatorIndex, 0)
        let phase = oscillationRandom(value.phaseMinimum ?? 0, value.phaseMaximum ?? 2 * .pi, index, operatorIndex, 1)
        let wave = (cos(frequency * particles[index].age + phase) + 1) * 0.5
        return minimum + (maximum - minimum) * wave
    }

    private nonisolated func oscillationBlend(
        _ value: SceneParticleOperator,
        _ life: Double
    ) -> Double {
        var result = 1.0
        if value.blendInStart != nil || value.blendInEnd != nil {
            result *= SceneParticleSimulationMath.changeAmount(
                life, value.blendInStart ?? 0, value.blendInEnd ?? 0
            )
        }
        if value.blendOutStart != nil || value.blendOutEnd != nil {
            result *= 1 - SceneParticleSimulationMath.changeAmount(
                life, value.blendOutStart ?? 1, value.blendOutEnd ?? 1
            )
        }
        return result
    }

    nonisolated func oscillationRandom(
        _ first: Double, _ second: Double, _ index: Int, _ operatorIndex: Int, _ salt: Int
    ) -> Double {
        var state = particles[index].id &* 0x9E3779B97F4A7C15
        state ^= UInt64(operatorIndex &* 31 &+ salt) &* 0xBF58476D1CE4E5B9
        var generator = SceneParticleRandomGenerator(state: state)
        return generator.value(first, second)
    }

    private nonisolated func emitterOrigin(_ emitter: SceneParticleEmitter) -> SIMD3<Double> {
        var result = SceneParticleSimulationMath.vector(emitter.origin, fallback: .zero)
        guard let source = emitter.controlPoint, source >= 0 else { return result }
        let point = definition.controlPoints.indices.contains(source)
            ? definition.controlPoints[source]
            : definition.controlPoints.first(where: { $0.id == source })
        if let point {
            result += SceneParticleSimulationMath.vector(point.offset, fallback: .zero)
        }
        if let override = instanceOverride?.controlPoints[source] {
            result += SceneParticleSimulationMath.vector(override.value, fallback: .zero)
        }
        return result
    }

}
