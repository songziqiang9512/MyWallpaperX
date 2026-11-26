import Foundation

extension SceneParticleSimulator {
    nonisolated var effectiveCountOverride: Double {
        definition.flags.disablesCountOverrides ? 1 : max(0, overrideScalar(activeInstanceOverride?.count))
    }

    nonisolated var effectiveSpeedOverride: Double {
        definition.flags.disablesSpeedOverrides ? 1 : overrideScalar(activeInstanceOverride?.speed)
    }

    nonisolated var effectiveSizeOverride: Double {
        definition.flags.disablesSizeOverrides ? 1 : overrideScalar(activeInstanceOverride?.size)
    }

    nonisolated func applyInstanceOverride(to particle: inout SceneParticleState) {
        guard let value = activeInstanceOverride else { return }
        let flags = definition.flags
        if !flags.disablesLifetimeOverrides {
            particle.lifetime *= overrideScalar(value.lifetime)
        }
        particle.alpha *= overrideScalar(value.alpha)
        particle.size *= effectiveSizeOverride
        let speed = effectiveSpeedOverride
        particle.velocity *= speed
        particle.angularVelocity *= speed
        if !flags.disablesColorOverrides, let brightness = value.brightness {
            particle.color *= overrideScalar(brightness)
        }
    }

    nonisolated func overrideScalar(_ value: SceneParticleBoundValue?) -> Double {
        let result = SceneParticleSimulationMath.scalar(value?.value, fallback: 1)
        return result.isFinite ? result : 1
    }

    nonisolated func prepareBirthColor() {
        guard !definition.flags.disablesColorOverrides else { return }
        let tint = instanceTint()
        let seedsFromTint = authoredColorInitializers.isEmpty || instanceOverride?.usesLegacyColorTransfer == true
        birthColorSeed = (seedsFromTint ? tint : nil) ?? SIMD3(repeating: 1)
        if let tint, let authoredColorReference {
            let hsv = SceneParticleSimulationMath.rgbToHSV(tint)
            let offset = hsv - authoredColorReference
            for (index, source) in authoredColorInitializers {
                initializerExecutionPlans[index] = source.tinted(to: hsv, rgbOffset: offset)
            }
        } else {
            for (index, source) in authoredColorInitializers {
                initializerExecutionPlans[index] = source.authored
            }
        }
    }

    private nonisolated func instanceTint() -> SIMD3<Double>? {
        let color: SIMD3<Double>
        if let raw = activeInstanceOverride?.color?.value {
            color = SceneParticleSimulationMath.vector(raw, fallback: .zero) / 255
        } else if let normalized = activeInstanceOverride?.normalizedColor?.value {
            color = SceneParticleSimulationMath.vector(normalized, fallback: .zero)
        } else {
            return nil
        }
        guard color.x >= 0, color.y >= 0, color.z >= 0,
              SceneParticleSimulationMath.isGPUFinite(color) else { return nil }
        return color
    }
}

nonisolated enum SceneParticleColorInitializerSource: Sendable {
    case rgb(SceneParticleRandomColorPlan, minimumHSV: SIMD3<Double>, maximumHSV: SIMD3<Double>)
    case hsv(SceneParticleHSVColorPlan)
    case list([SIMD3<Double>], reference: SIMD3<Double>, offsets: [SIMD3<Double>])

    init?(_ plan: SceneParticleInitializerExecutionPlan) {
        switch plan {
        case let .color(plan):
            self = .rgb(plan, minimumHSV: SceneParticleSimulationMath.rgbToHSV(plan.minimum),
                        maximumHSV: SceneParticleSimulationMath.rgbToHSV(plan.maximum))
        case let .hsvColor(plan?):
            self = .hsv(plan)
        case let .colorList(colors?):
            let hues = colors.map(SceneParticleSimulationMath.rgbToHSV)
            let reference = hues[0]
            self = .list(colors, reference: reference, offsets: hues.map { $0 - reference })
        default:
            return nil
        }
    }

    var colorReference: SIMD3<Double> {
        switch self {
        case let .rgb(plan, _, _):
            SceneParticleSimulationMath.rgbToHSV((plan.minimum + plan.maximum) / 2)
        case let .hsv(plan):
            plan.colorReference
        case let .list(_, reference, _):
            reference
        }
    }

    var authored: SceneParticleInitializerExecutionPlan {
        switch self {
        case let .rgb(plan, _, _): .color(plan)
        case let .hsv(plan): .hsvColor(plan)
        case let .list(colors, _, _): .colorList(colors)
        }
    }

    func tinted(to hsv: SIMD3<Double>, rgbOffset: SIMD3<Double>) -> SceneParticleInitializerExecutionPlan {
        func resolve(_ color: SIMD3<Double>) -> SIMD3<Double> {
            return SceneParticleSimulationMath.hsvToRGB(
                hue: color.x - floor(color.x),
                saturation: min(max(color.y, 0), 1), value: min(max(color.z, 0), 1)
            )
        }
        switch self {
        case let .rgb(authored, minimumHSV, maximumHSV):
            var projected = authored
            projected.minimum = resolve(minimumHSV + rgbOffset)
            projected.maximum = resolve(maximumHSV + rgbOffset)
            return .color(projected)
        case let .hsv(plan):
            return .hsvColor(plan.tinted(to: hsv))
        case let .list(_, _, offsets):
            return .colorList(offsets.map { resolve(hsv + $0) })
        }
    }
}

extension SceneParticleSimulationMath {
    nonisolated static func rgbToHSV(_ color: SIMD3<Double>) -> SIMD3<Double> {
        let value = max(color.x, color.y, color.z)
        let chroma = value - min(color.x, color.y, color.z)
        guard chroma > 0 else { return SIMD3(0, 0, value) }
        let sector: Double
        if value == color.x {
            sector = (color.y - color.z) / chroma
        } else if value == color.y {
            sector = 2 + (color.z - color.x) / chroma
        } else {
            sector = 4 + (color.x - color.y) / chroma
        }
        let hue = sector / 6
        return SIMD3(hue - floor(hue), value > 0 ? chroma / value : 0, value)
    }
}
