import Foundation
import simd

nonisolated enum SceneCameraShake {
    nonisolated struct Configuration: Equatable, Sendable {
        let amplitude: Float
        let roughness: Float
        let speed: Float
        let projectionHeight: Float
    }

    nonisolated enum Admission: Equatable, Sendable {
        case disabled
        case executable(Configuration)
        case invalid

        nonisolated var reportValue: String {
            switch self {
            case .disabled: "disabled"
            case .executable: "executable"
            case .invalid: "invalid"
            }
        }
    }

    // Wallpaper Engine 2.8.42 editor-authored bounds. The player does not prove
    // an equivalent runtime clamp, so values outside this static contract fail closed.
    nonisolated static let amplitudeRange: ClosedRange<Float> = 0...1
    nonisolated static let roughnessRange: ClosedRange<Float> = 0...2
    nonisolated static let speedRange: ClosedRange<Float> = 0...5

    nonisolated static func admission(
        _ camera: SceneRenderDescriptor.CameraDescriptor
    ) -> Admission {
        let descriptor = camera.shake
        guard let enabled = descriptor.enabled else { return .invalid }
        guard enabled else { return .disabled }
        guard let amplitude = descriptor.amplitude,
              let roughness = descriptor.roughness,
              let speed = descriptor.speed,
              let projectionWidth = camera.orthoWidth,
              let projectionHeight = camera.orthoHeight,
              amplitude.isFinite,
              roughness.isFinite,
              speed.isFinite,
              projectionWidth.isFinite,
              projectionHeight.isFinite,
              projectionWidth > 0,
              projectionHeight > 0,
              amplitudeRange.contains(amplitude),
              roughnessRange.contains(roughness),
              speedRange.contains(speed) else {
            return .invalid
        }
        return .executable(.init(
            amplitude: amplitude,
            roughness: roughness,
            speed: speed,
            projectionHeight: projectionHeight
        ))
    }

    nonisolated static func reportLine(
        _ camera: SceneRenderDescriptor.CameraDescriptor
    ) -> String {
        let descriptor = camera.shake
        return "camera shake: status=\(admission(camera).reportValue)"
            + " enabled=\(descriptor.enabled.map { String($0) } ?? "invalid")"
            + " amplitude=\(descriptor.amplitude.map { String($0) } ?? "invalid")"
            + " roughness=\(descriptor.roughness.map { String($0) } ?? "invalid")"
            + " speed=\(descriptor.speed.map { String($0) } ?? "invalid")"
    }

    /// Returns the authored orthographic camera displacement in Scene canvas units.
    /// The phase is absolute-time based, so pause, reset and future seek share one result.
    nonisolated static func orthographicOffset(
        admission: Admission,
        sceneTime: TimeInterval
    ) -> SIMD2<Float> {
        guard let (configuration, periodic) = periodicVector(
            admission: admission,
            sceneTime: sceneTime
        ) else { return .zero }
        let shaped = radialShape(
            periodic,
            roughness: Double(configuration.roughness)
        )
        let scale = Double(configuration.amplitude)
            * Double(configuration.projectionHeight) * 0.01
        let result = SIMD2<Float>(
            Float(shaped.x * scale),
            Float(shaped.y * scale)
        )
        return result.x.isFinite && result.y.isFinite ? result : .zero
    }

    nonisolated private static func periodicVector(
        admission: Admission,
        sceneTime: TimeInterval
    ) -> (Configuration, SIMD2<Double>)? {
        guard case let .executable(configuration) = admission,
              configuration.amplitude > 0,
              sceneTime.isFinite else { return nil }
        let speed = Double(configuration.speed)
        let phase = sceneTime * speed * speed
        guard phase.isFinite else { return nil }
        return (
            configuration,
            SIMD2(cos(phase), sin(phase * 1.333))
        )
    }

    nonisolated private static func radialShape(
        _ value: SIMD2<Double>,
        roughness: Double
    ) -> SIMD2<Double> {
        value * radialScale(length: simd_length(value), roughness: roughness)
    }

    nonisolated private static func radialScale(
        length: Double,
        roughness: Double
    ) -> Double {
        let exponent = roughness * roughness * roughness
        // The player preserves the raw periodic vector for zero/near-zero
        // roughness and for the identity exponent. These branches also avoid
        // unstable normalization around a zero-length vector.
        guard exponent > 0.001, abs(exponent - 1) > 1e-6 else { return 1 }
        guard length.isFinite, length > 1e-9 else { return 1 }
        let shapedLength = pow(length, exponent)
        guard shapedLength.isFinite else { return 1 }
        return shapedLength / length
    }
}
