import Foundation
import Metal

/// Samples native texture formats before reading RGBA bytes. A blit alone
/// cannot convert block-compressed texture storage into a pixel value.
final class SceneTextureSamplingReadback {
    enum Failure: Error { case functionUnavailable, allocation, completion }

    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let queue: MTLCommandQueue

    init(device: MTLDevice) throws {
        let library = try device.makeLibrary(source: """
            #include <metal_stdlib>
            using namespace metal;
            kernel void source_sample(texture2d<float> source [[texture(0)]],
                texture2d<float, access::write> target [[texture(1)]],
                constant float4& value [[buffer(0)]]) {
                constexpr sampler nearest(filter::nearest, mip_filter::nearest, address::clamp_to_edge);
                constexpr sampler linear(filter::linear, mip_filter::nearest, address::clamp_to_edge);
                float4 sampled = value.w == 0
                    ? source.sample(nearest, value.xy, level(value.z))
                    : source.sample(linear, value.xy, level(value.z));
                target.write(sampled, uint2(0));
            }
            """, options: nil)
        guard let function = library.makeFunction(name: "source_sample") else {
            throw Failure.functionUnavailable
        }
        pipeline = try device.makeComputePipelineState(function: function)
        guard let queue = device.makeCommandQueue() else { throw Failure.allocation }
        self.device = device
        self.queue = queue
    }

    func sample(
        _ texture: MTLTexture,
        uv: SIMD2<Float>,
        mip: Float = 0,
        linear: Bool = false
    ) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let target = device.makeTexture(descriptor: descriptor),
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw Failure.allocation
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(target, index: 1)
        var values = SIMD4<Float>(uv.x, uv.y, mip, linear ? 1 : 0)
        encoder.setBytes(&values, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.dispatchThreads(.init(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: .init(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw Failure.completion }
        var bytes = [UInt8](repeating: 0, count: 4)
        target.getBytes(&bytes, bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        return bytes
    }

    func pixel(_ texture: MTLTexture, level: Int = 0, x: Int = 0, y: Int = 0) throws -> [UInt8] {
        let width = max(1, texture.width >> level)
        let height = max(1, texture.height >> level)
        return try sample(texture,
            uv: SIMD2((Float(x) + 0.5) / Float(width), (Float(y) + 0.5) / Float(height)),
            mip: Float(level))
    }
}
