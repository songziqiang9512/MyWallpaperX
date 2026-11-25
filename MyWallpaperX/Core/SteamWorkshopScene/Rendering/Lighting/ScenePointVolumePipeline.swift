import Foundation
import Metal
import simd

final class ScenePointVolumePipeline {
    struct Camera {
        let originAndNear: SIMD4<Float>
        let forwardAndFar: SIMD4<Float>
        let horizontal: SIMD4<Float>
        let vertical: SIMD4<Float>

        init(origin: SIMD3<Float>, near: Float, forward: SIMD3<Float>, far: Float,
             horizontal: SIMD3<Float>, vertical: SIMD3<Float>) {
            originAndNear = SIMD4(origin, near)
            forwardAndFar = SIMD4(forward, far)
            self.horizontal = SIMD4(horizontal, 0)
            self.vertical = SIMD4(vertical, 0)
        }
    }

    fileprivate struct Light {
        var centerAndRadius: SIMD4<Float>
        var radianceAndExponent: SIMD4<Float>
    }

    struct PreparedDraw {
        fileprivate let lights: [Light]
        fileprivate let camera: Camera
        let scissor: MTLScissorRect?
    }

    private struct ScreenProjection {
        let origin: SIMD3<Double>
        let right: SIMD3<Double>
        let up: SIMD3<Double>
        let forward: SIMD3<Double>
        let depthScale: Double
        let near: Double
        let far: Double
        let rayMagnitude: Double

        init?(_ camera: Camera) {
            origin = Self.xyz(camera.originAndNear)
            let horizontal = Self.xyz(camera.horizontal)
            let vertical = Self.xyz(camera.vertical)
            let front = Self.xyz(camera.forwardAndFar)
            // Reciprocal basis of the actual Metal ray F + ndc.x * H + ndc.y * V.
            let rightNormal = simd_cross(vertical, front)
            let determinant = simd_dot(horizontal, rightNormal)
            guard determinant.isFinite, determinant != 0 else { return nil }
            right = rightNormal / determinant
            up = simd_cross(front, horizontal) / determinant
            let depthAxis = simd_cross(horizontal, vertical) / determinant
            forward = depthAxis
            depthScale = simd_length(depthAxis)
            near = Double(camera.originAndNear.w)
            far = Double(camera.forwardAndFar.w)
            rayMagnitude = max(Self.magnitude(origin),
                near * (simd_length(horizontal) + simd_length(vertical) + simd_length(front)))
        }

        func bounds(of light: Light, in frame: SIMD4<Int>) -> SIMD4<Int>? {
            let center = Self.xyz(light.centerAndRadius)
            let delta = center - origin
            // The shader constructs the near point and subtracts the center in Float.
            let radius = Double(light.centerAndRadius.w)
                + max(rayMagnitude, Self.magnitude(center)) * (16 * Double(Float.ulpOfOne))
            let z = simd_dot(delta, forward)
            let depthRadius = radius * depthScale
            if z + depthRadius < near || z - depthRadius > far { return nil }
            guard z - depthRadius > near else { return frame }

            let radiusSquared = radius * radius
            let a = (z - depthRadius) * (z + depthRadius)
            func slopes(_ axis: SIMD3<Double>) -> SIMD2<Double> {
                let u = simd_dot(delta, axis)
                let b = u * z - radiusSquared * simd_dot(axis, forward)
                let c = u * u - radiusSquared * simd_dot(axis, axis)
                let root = sqrt(b * b - a * c)
                return SIMD2((b - root) / a, (b + root) / a)
            }
            let x = slopes(right)
            let y = slopes(up)
            guard x.x.isFinite, x.y.isFinite, y.x.isFinite, y.y.isFinite else { return frame }
            let halfWidth = Double(frame.z) * 0.5
            let halfHeight = Double(frame.w) * 0.5
            // Outward rounding with one guard pixel, in Metal's Y-down viewport.
            func clamp(_ pixel: Double, limit: Int) -> Int {
                Int(max(0, min(Double(limit), pixel)))
            }
            let left = clamp(floor((1 + x.x) * halfWidth) - 1, limit: frame.z)
            let right = clamp(ceil((1 + x.y) * halfWidth) + 1, limit: frame.z)
            let top = clamp(floor((1 - y.y) * halfHeight) - 1, limit: frame.w)
            let bottom = clamp(ceil((1 - y.x) * halfHeight) + 1, limit: frame.w)
            return left < right && top < bottom ? SIMD4(left, top, right, bottom) : nil
        }

        private static func xyz(_ value: SIMD4<Float>) -> SIMD3<Double> {
            SIMD3(Double(value.x), Double(value.y), Double(value.z))
        }

        private static func magnitude(_ value: SIMD3<Double>) -> Double {
            max(abs(value.x), abs(value.y), abs(value.z))
        }
    }

    private let state: MTLRenderPipelineState

    init?(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "scenePointVolumeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "scenePointVolumeFragment")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = pixelFormat
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .zero
        color.destinationAlphaBlendFactor = .one
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.state = state
    }

    func prepare(
        lights: [SceneLightSnapshot.Point],
        camera: Camera,
        viewport: (width: Int, height: Int),
        clipsScreenCoverage: Bool = true
    ) -> PreparedDraw? {
        let frame = SIMD4(0, 0, viewport.width, viewport.height)
        let projection = clipsScreenCoverage ? ScreenProjection(camera) : nil
        var bounds = SIMD4(frame.z, frame.w, 0, 0)
        let packed: [Light] = lights.compactMap { light in
            guard let volume = light.volume else { return nil }
            let power = Double(light.intensity) * Double(volume.density) * 0.05
            let radiance = SIMD3<Float>(SIMD3<Double>(light.color) * power)
            guard radiance.x.isFinite, radiance.y.isFinite, radiance.z.isFinite else { return nil }
            let packed = Light(centerAndRadius: SIMD4(light.position, light.radius),
                         radianceAndExponent: SIMD4(radiance, volume.exponent))
            if let projection, bounds != frame, let rect = projection.bounds(of: packed, in: frame) {
                bounds = SIMD4(min(bounds.x, rect.x), min(bounds.y, rect.y),
                               max(bounds.z, rect.z), max(bounds.w, rect.w))
            }
            return packed
        }
        guard !packed.isEmpty else { return nil }
        if projection == nil || bounds == frame { return .init(lights: packed, camera: camera, scissor: nil) }
        guard bounds.x < bounds.z, bounds.y < bounds.w else { return nil }
        let scissor = MTLScissorRect(x: bounds.x, y: bounds.y,
                                    width: bounds.z - bounds.x, height: bounds.w - bounds.y)
        return .init(lights: packed, camera: camera, scissor: scissor)
    }

    func draw(_ prepared: PreparedDraw, depth: MTLTexture, encoder: MTLRenderCommandEncoder) {
        var camera = prepared.camera
        var count = UInt32(prepared.lights.count)
        encoder.setRenderPipelineState(state)
        encoder.setCullMode(.none)
        if let scissor = prepared.scissor { encoder.setScissorRect(scissor) }
        encoder.setFragmentBytes(prepared.lights, length: prepared.lights.count * MemoryLayout<Light>.stride, index: 0)
        encoder.setFragmentBytes(&camera, length: MemoryLayout<Camera>.stride, index: 1)
        encoder.setFragmentBytes(&count, length: MemoryLayout<UInt32>.stride, index: 2)
        encoder.setFragmentTexture(depth, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
#if DEBUG
        SceneGPUStageTimestampHook.drew(encoder)
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
        ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: false)
#endif
    }
}
