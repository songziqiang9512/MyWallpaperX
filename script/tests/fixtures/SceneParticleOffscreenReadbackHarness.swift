import Foundation
import Dispatch
import Metal
import simd

// Shared particle draw/readback and command completion for offscreen fixtures.
// It publishes pixels; camera policy and assertion oracles belong to callers.
enum SceneParticleOffscreenReadbackHarness {
    /// Draws one full-alpha particle with the given texture and returns the
    /// blended BGRA center pixel, exercising the real sampler and swizzle.
    static func centerPixel(
        texture: MTLTexture,
        cullMode: SceneParticlePipelineCullMode = .none,
        reversesWinding: Bool = false,
        currentFrame: SceneParticleFrameTransform = .identity,
        nextFrame: SceneParticleFrameTransform? = nil,
        frameMix: Float = 0,
        particleAlpha: Float = 1,
        blendMode: SceneParticlePipelineBlendMode = .translucent,
        background: Float = 0,
        overbright: Float = 1,
        uniforms: SceneParticleLayerUniforms? = nil,
        particleSize: Float = 2, outputSize: Int = 8, sampleY: Int? = nil
    ) -> [Int] {
        let size = outputSize
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [SceneParticleGPUInstance(
            position: .zero, size: particleSize, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: particleAlpha,
            currentFrame: currentFrame, nextFrame: nextFrame, frameMix: frameMix
        )]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(Double(background), Double(background), Double(background), 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        var drawUniforms = uniforms ?? SceneParticleLayerUniforms(
            viewProjection: SceneMatrix.identity(), layerModel: SceneMatrix.identity(),
            basis: SceneParticleOrientationBasis(
                right: SIMD3(reversesWinding ? -1 : 1, 0, 0), up: SIMD3(0, 1, 0)))
        if uniforms != nil && reversesWinding {
            drawUniforms.basisRight = -drawUniforms.basisRight
            drawUniforms.spriteRight = -drawUniforms.spriteRight
        }
        guard pipeline.draw(
            texture: texture,
            instances: instances,
            uniforms: drawUniforms,
            renderState: SceneParticlePipelineRenderState(blendMode: blendMode, cullMode: cullMode, overbright: overbright),
            colorSampling: .directImageFallback,
            encoder: encoder
        ) else { return [] }
        encoder.endEncoding()
        instances.markSubmitted(on: command)
        guard commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, sampleY ?? size / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    static func instance(x: Float, z: Float = 0, size: Float = 1) -> SceneParticleGPUInstance {
        SceneParticleGPUInstance(
            position: SIMD3(x, 0, z), size: size, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1
        )
    }

    static func commitAndWait(_ command: MTLCommandBuffer) -> Bool {
        let completion = DispatchSemaphore(value: 0)
        command.addCompletedHandler { _ in completion.signal() }
        command.commit()
        return completion.wait(timeout: .now() + 5) == .success && command.status == .completed
    }
}
