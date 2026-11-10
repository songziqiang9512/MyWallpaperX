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

    private struct Light {
        var centerAndRadius: SIMD4<Float>
        var radianceAndExponent: SIMD4<Float>
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

    @discardableResult
    func draw(
        lights: [SceneLightSnapshot.Point],
        camera: Camera,
        depth: MTLTexture,
        encoder: MTLRenderCommandEncoder
    ) -> Bool {
        let packed: [Light] = lights.compactMap { light in
            guard let volume = light.volume else { return nil }
            let power = Double(light.intensity) * Double(volume.density) * 0.05
            let radiance = SIMD3<Float>(SIMD3<Double>(light.color) * power)
            guard radiance.x.isFinite, radiance.y.isFinite, radiance.z.isFinite else { return nil }
            return Light(centerAndRadius: SIMD4(light.position, light.radius),
                         radianceAndExponent: SIMD4(radiance, volume.exponent))
        }
        guard !packed.isEmpty else { return false }
        var camera = camera
        var count = UInt32(packed.count)
        encoder.setRenderPipelineState(state)
        encoder.setCullMode(.none)
        encoder.setFragmentBytes(packed, length: packed.count * MemoryLayout<Light>.stride, index: 0)
        encoder.setFragmentBytes(&camera, length: MemoryLayout<Camera>.stride, index: 1)
        encoder.setFragmentBytes(&count, length: MemoryLayout<UInt32>.stride, index: 2)
        encoder.setFragmentTexture(depth, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
#if DEBUG
        SceneGPUStageTimestampHook.drew(encoder)
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
        ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: false)
#endif
        return true
    }
}
