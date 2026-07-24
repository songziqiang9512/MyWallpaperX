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
    private(set) var simulationTime = 0.0

    private let definition: SceneParticleDefinition
    private let instanceOverride: SceneParticleInstanceOverride?
    private var emitters: [EmitterState]
    private var random: SceneParticleRandomGenerator
    private var accumulator = 0.0
    private var nextParticleID: UInt64 = 0

    nonisolated init(
        definition: SceneParticleDefinition,
        instanceOverride: SceneParticleInstanceOverride? = nil,
        seed: UInt64 = 0,
        fixedTimeStep: Double = 1.0 / 60.0
    ) {
        self.definition = definition
        self.instanceOverride = instanceOverride
        self.fixedTimeStep = fixedTimeStep.isFinite && fixedTimeStep > 0 ? fixedTimeStep : 1.0 / 60.0
        maximumParticleCount = min(max(definition.maximumCount ?? 1, 0), 20_000)
        diagnostics = SceneParticleSimulationMath.diagnostics(definition, instanceOverride)
        emitters = Array(repeating: EmitterState(), count: definition.emitters.count)
        random = SceneParticleRandomGenerator(state: seed)
        warmUp(duration: max(0, definition.startTime ?? 0))
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

    private nonisolated mutating func warmUp(duration: Double) {
        guard duration > 0 else { return }
        let count = min(max(Int(ceil(duration / fixedTimeStep)), 1), 240)
        let stepDuration = duration / Double(count)
        for _ in 0..<count { step(by: stepDuration) }
    }

    private nonisolated mutating func step(by duration: Double) {
        for index in definition.emitters.indices { emit(index: index, duration: duration) }
        for index in particles.indices { updateParticle(at: index, duration: duration) }
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
        for _ in 0..<count { if let particle = makeParticle(emitter) { particles.append(particle) } }
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
            case .turbulentVelocity, .unsupported:
                break
            }
        }
    }

    private nonisolated func applyInstanceOverride(to particle: inout SceneParticleState) {
        guard let value = instanceOverride else { return }
        particle.lifetime *= overrideScalar(value.lifetime)
        particle.alpha *= overrideScalar(value.alpha)
        particle.size *= overrideScalar(value.size)
        particle.velocity *= overrideScalar(value.speed)
        if let color = overrideVector(value.color) {
            let normalized = color / 255
            particle.color = normalized * normalized
        } else if let color = overrideVector(value.normalizedColor) {
            particle.color = color * color
        }
        particle.color *= overrideScalar(value.brightness)
    }

    private nonisolated mutating func updateParticle(at index: Int, duration: Double) {
        particles[index].alpha = particles[index].initialAlpha
        particles[index].size = particles[index].initialSize
        particles[index].color = particles[index].initialColor
        particles[index].age += duration
        let life = min(max(particles[index].age / max(particles[index].lifetime, 1e-12), 0), 1)
        for (operatorIndex, value) in definition.operators.enumerated() {
            apply(value, index: index, operatorIndex: operatorIndex, life: life, duration: duration)
        }
    }

    private nonisolated mutating func apply(
        _ value: SceneParticleOperator,
        index: Int,
        operatorIndex: Int,
        life: Double,
        duration: Double
    ) {
        switch value.kind {
        case .movement:
            let gravity = SceneParticleSimulationMath.vector(value.gravity, fallback: .zero)
            let acceleration = gravity - particles[index].velocity * max(0, value.drag ?? 0)
            particles[index].velocity += acceleration * duration
            particles[index].position += particles[index].velocity * duration
        case .angularMovement:
            let force = SceneParticleSimulationMath.vector(value.force, fallback: .zero)
            let acceleration = force - particles[index].angularVelocity * max(0, value.drag ?? 0)
            particles[index].angularVelocity += acceleration * duration
            particles[index].rotation += particles[index].angularVelocity * duration
        case .alphaFade:
            let fadeIn = max(0, value.fadeInTime ?? 0.5)
            let fadeOut = min(max(value.fadeOutTime ?? 0.5, 0), 1)
            if life <= fadeIn { particles[index].alpha *= Self.change(life, 0, fadeIn, 0, 1) }
            if life > fadeOut { particles[index].alpha *= Self.change(life, fadeOut, 1, 1, 0) }
        case .alphaChange:
            particles[index].alpha *= changeFactor(value, life: life, fallback: (1, 0))
        case .sizeChange:
            particles[index].size *= changeFactor(value, life: life, fallback: (1, 0))
        case .colorChange:
            let start = SceneParticleSimulationMath.vector(value.startValue, fallback: SIMD3(repeating: 1))
            let end = SceneParticleSimulationMath.vector(value.endValue, fallback: .zero)
            let amount = SceneParticleSimulationMath.changeAmount(life, value.startTime, value.endTime)
            particles[index].color *= start + (end - start) * amount
        case .oscillateAlpha:
            let factor = oscillationFactor(value, index, operatorIndex)
            particles[index].alpha *= 1 + (factor - 1) * oscillationBlend(value, life)
        case .oscillateSize:
            let factor = oscillationFactor(value, index, operatorIndex, sizeDefaults: true)
            particles[index].size *= 1 + (factor - 1) * oscillationBlend(value, life)
        case .oscillatePosition:
            let mask = SceneParticleSimulationMath.vector(value.mask, fallback: SIMD3(1, 1, 0))
            for component in 0..<3 where abs(mask[component]) > 1e-6 {
                let frequency = oscillationRandom(value.frequencyMinimum ?? 0, value.frequencyMaximum ?? 5, index, operatorIndex, component)
                let scale = oscillationRandom(
                    SceneParticleSimulationMath.vector(value.scaleMinimum, fallback: .zero)[component],
                    SceneParticleSimulationMath.vector(value.scaleMaximum, fallback: SIMD3(repeating: 1))[component],
                    index, operatorIndex, component + 3
                )
                let phase = oscillationRandom(value.phaseMinimum ?? 0, value.phaseMaximum ?? 2 * .pi, index, operatorIndex, component + 6)
                particles[index].position[component] -= scale * frequency
                    * sin(frequency * particles[index].age + phase) * duration
                    * oscillationBlend(value, life)
            }
        case .controlPointAttract, .turbulence, .vortex, .unsupported:
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

    private nonisolated func oscillationRandom(
        _ first: Double, _ second: Double, _ index: Int, _ operatorIndex: Int, _ salt: Int
    ) -> Double {
        var state = particles[index].id &* 0x9E3779B97F4A7C15
        state ^= UInt64(operatorIndex &* 31 &+ salt) &* 0xBF58476D1CE4E5B9
        var generator = SceneParticleRandomGenerator(state: state)
        return generator.value(first, second)
    }

    private nonisolated mutating func randomScalar(
        _ value: SceneParticleInitializer, defaults: (Double, Double)
    ) -> Double {
        random.value(
            SceneParticleSimulationMath.scalar(value.minimum, fallback: defaults.0),
            SceneParticleSimulationMath.scalar(value.maximum, fallback: defaults.1)
        )
    }

    private nonisolated mutating func randomVector(
        _ value: SceneParticleInitializer,
        defaults: (SIMD3<Double>, SIMD3<Double>)
    ) -> SIMD3<Double> {
        let minimum = SceneParticleSimulationMath.vector(value.minimum, fallback: defaults.0)
        let maximum = SceneParticleSimulationMath.vector(value.maximum, fallback: defaults.1)
        return SIMD3(random.value(minimum.x, maximum.x), random.value(minimum.y, maximum.y), random.value(minimum.z, maximum.z))
    }

    private nonisolated mutating func randomColor(
        _ value: SceneParticleInitializer,
        defaults: (SIMD3<Double>, SIMD3<Double>)
    ) -> SIMD3<Double> {
        let minimum = SceneParticleSimulationMath.vector(value.minimum, fallback: defaults.0)
        let maximum = SceneParticleSimulationMath.vector(value.maximum, fallback: defaults.1)
        return minimum + (maximum - minimum) * random.unit()
    }

    private nonisolated mutating func randomSphereOffset(_ emitter: SceneParticleEmitter) -> SIMD3<Double> {
        let directions = SceneParticleSimulationMath.vector(emitter.directions, fallback: SIMD3(1, 1, 0))
        var unit = SIMD3<Double>.zero
        var foundDirection = false
        for _ in 0..<8 {
            unit = SIMD3(random.value(-1, 1), random.value(-1, 1), random.value(-1, 1))
            for component in 0..<3 where abs(directions[component]) <= 1e-6 { unit[component] = 0 }
            let length = SceneParticleSimulationMath.length(unit)
            if length > 1e-6, length <= 1 {
                unit /= length
                foundDirection = true
                break
            }
        }
        if !foundDirection { unit = SIMD3(1, 0, 0) }
        let dimensions = max((0..<3).filter { abs(directions[$0]) > 1e-6 }.count, 1)
        let minimum = max(0, SceneParticleSimulationMath.scalar(emitter.distanceMinimum, fallback: 0))
        let maximum = max(minimum, SceneParticleSimulationMath.scalar(emitter.distanceMaximum, fallback: 256))
        let radius = pow(random.value(pow(minimum, Double(dimensions)), pow(maximum, Double(dimensions))), 1 / Double(dimensions))
        var absoluteDirections = directions
        for component in 0..<3 { absoluteDirections[component] = abs(absoluteDirections[component]) }
        var result = unit * absoluteDirections * radius
        let sign = SceneParticleSimulationMath.vector(emitter.sign, fallback: .zero)
        for component in 0..<3 where abs(sign[component]) > 1e-6 {
            result[component] = abs(result[component]) * (sign[component] < 0 ? -1 : 1)
        }
        return result
    }

    private nonisolated mutating func randomBoxOffset(_ emitter: SceneParticleEmitter) -> SIMD3<Double> {
        let minimum = SceneParticleSimulationMath.vector(emitter.distanceMinimum, fallback: .zero)
        let maximum = SceneParticleSimulationMath.vector(emitter.distanceMaximum, fallback: SIMD3(repeating: 256))
        let direction = SceneParticleSimulationMath.vector(emitter.directions, fallback: SIMD3(1, 1, 0))
        return SIMD3(random.value(minimum.x, maximum.x), random.value(minimum.y, maximum.y), random.value(minimum.z, maximum.z)) * direction
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

    private nonisolated func overrideScalar(_ value: SceneParticleBoundValue?) -> Double {
        let result = SceneParticleSimulationMath.scalar(value?.value, fallback: 1)
        return result.isFinite ? result : 1
    }

    private nonisolated func overrideVector(_ value: SceneParticleBoundValue?) -> SIMD3<Double>? {
        guard value?.value != nil else { return nil }
        return SceneParticleSimulationMath.vector(value?.value, fallback: .zero)
    }

    private nonisolated static func change(
        _ value: Double, _ start: Double, _ end: Double, _ first: Double, _ second: Double
    ) -> Double {
        first + (second - first) * SceneParticleSimulationMath.changeAmount(value, start, end)
    }
}
