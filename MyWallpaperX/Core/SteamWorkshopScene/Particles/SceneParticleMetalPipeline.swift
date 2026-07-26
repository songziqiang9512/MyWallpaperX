import Foundation
import Metal
import simd

final class SceneParticleMetalInstanceBuffer: @unchecked Sendable {
    private struct Slot {
        var buffer: MTLBuffer
        var capacity: Int
        var isInFlight: Bool
    }

    private let lock = NSLock()
    private var slots: [Slot] = []
    private var currentSlotIndex: Int?
    private var currentCount = 0

    var buffer: MTLBuffer? {
        withLock {
            currentSlotIndex.map { slots[$0].buffer }
        }
    }

    var count: Int {
        withLock { currentCount }
    }

    func update(device: MTLDevice, instances: [SceneParticleGPUInstance]) -> Bool {
        withLock {
            currentCount = instances.count
            guard !instances.isEmpty else {
                currentSlotIndex = nil
                return true
            }

            guard let slotIndex = prepareSlot(device: device, requiredCount: instances.count) else {
                currentCount = 0
                currentSlotIndex = nil
                return false
            }
            currentSlotIndex = slotIndex
            let requiredLength = instances.count * MemoryLayout<SceneParticleGPUInstance>.stride
            instances.withUnsafeBufferPointer { values in
                guard let source = values.baseAddress else { return }
                slots[slotIndex].buffer.contents().copyMemory(
                    from: source,
                    byteCount: requiredLength
                )
            }
            return true
        }
    }

    @discardableResult
    func markSubmitted(on commandBuffer: MTLCommandBuffer) -> Bool {
        let submittedSlot: Int? = withLock {
            guard let currentSlotIndex else { return nil }
            slots[currentSlotIndex].isInFlight = true
            self.currentSlotIndex = nil
            return currentSlotIndex
        }
        guard let submittedSlot else { return false }
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.releaseSlot(at: submittedSlot)
        }
        return true
    }

    fileprivate func currentDrawState() -> (buffer: MTLBuffer, count: Int)? {
        withLock {
            guard currentCount > 0, let currentSlotIndex else { return nil }
            return (slots[currentSlotIndex].buffer, currentCount)
        }
    }

    private func prepareSlot(device: MTLDevice, requiredCount: Int) -> Int? {
        let slotIndex = currentSlotIndex
            ?? slots.indices.first(where: {
                !slots[$0].isInFlight && slots[$0].capacity >= requiredCount
            })
            ?? slots.indices.first(where: { !slots[$0].isInFlight })

        if let slotIndex {
            guard slots[slotIndex].capacity < requiredCount else { return slotIndex }
            let capacity = max(requiredCount, max(slots[slotIndex].capacity * 2, 64))
            guard let buffer = makeBuffer(device: device, capacity: capacity, slotIndex: slotIndex) else {
                return nil
            }
            slots[slotIndex] = Slot(buffer: buffer, capacity: capacity, isInFlight: false)
            return slotIndex
        }

        let capacity = max(requiredCount, max(slots.map(\.capacity).max() ?? 0, 64))
        let newIndex = slots.count
        guard let buffer = makeBuffer(device: device, capacity: capacity, slotIndex: newIndex) else {
            return nil
        }
        slots.append(Slot(buffer: buffer, capacity: capacity, isInFlight: false))
        return newIndex
    }

    private func makeBuffer(
        device: MTLDevice,
        capacity: Int,
        slotIndex: Int
    ) -> MTLBuffer? {
        let length = capacity * MemoryLayout<SceneParticleGPUInstance>.stride
        let buffer = device.makeBuffer(length: length, options: .storageModeShared)
        buffer?.label = "Scene particle instances slot \(slotIndex)"
        return buffer
    }

    private func releaseSlot(at index: Int) {
        withLock {
            guard slots.indices.contains(index) else { return }
            slots[index].isInFlight = false
        }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private struct SceneParticleQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
}

private let sceneParticleShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct QuadVertex { float2 position; float2 texcoord; };
struct ParticleInstance {
    float4 positionAndSize;
    float4 rotationAndAlpha;
    float4 colorAndFrameMix;
    float4 frame0A;
    float4 frame0B;
    float4 frame1A;
    float4 frame1B;
    float4 velocityAndTrail;
};
struct LayerUniforms {
    float4x4 viewProjection;
    float4x4 layerModel;
    float4 basisRight;
    float4 basisUp;
};
struct Varyings {
    float4 position [[position]];
    float2 uv0;
    float2 uv1;
    float4 tint;
    float frameBlend;
};

float3 rotateXYZ(float3 value, float3 radians) {
    float3 c = cos(radians), s = sin(radians);
    value = float3(value.x, c.x * value.y - s.x * value.z,
                   s.x * value.y + c.x * value.z);
    value = float3(c.y * value.x + s.y * value.z, value.y,
                   -s.y * value.x + c.y * value.z);
    return float3(c.z * value.x - s.z * value.y,
                  s.z * value.x + c.z * value.y, value.z);
}

vertex Varyings sceneParticleVert(
    uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
    constant QuadVertex *quad [[buffer(0)]],
    device const ParticleInstance *instances [[buffer(1)]],
    constant LayerUniforms &uniforms [[buffer(2)]]) {
    QuadVertex quadVertex = quad[vertexID];
    ParticleInstance particle = instances[instanceID];
    float4 center = uniforms.layerModel * float4(particle.positionAndSize.xyz, 1.0);
    float3 local;
    if (particle.velocityAndTrail.w >= 0.0) {
        float3 worldVelocity = (uniforms.layerModel
            * float4(particle.velocityAndTrail.xyz, 0.0)).xyz;
        float4 projectedStart = uniforms.viewProjection * center;
        float4 projectedEnd = uniforms.viewProjection
            * float4(center.xyz + worldVelocity * 0.001, 1.0);
        float2 velocity = projectedEnd.xy / max(abs(projectedEnd.w), 0.00001)
            - projectedStart.xy / max(abs(projectedStart.w), 0.00001);
        float speed = length(velocity);
        float2 direction = speed > 0.00001 ? velocity / speed : float2(1.0, 0.0);
        float2 perpendicular = float2(-direction.y, direction.x);
        float2 aligned = direction * quadVertex.position.x
            * particle.positionAndSize.w * particle.velocityAndTrail.w
            + perpendicular * quadVertex.position.y * particle.positionAndSize.w;
        local = float3(aligned, 0.0);
    } else {
        local = rotateXYZ(
            float3(quadVertex.position * particle.positionAndSize.w, 0.0),
            particle.rotationAndAlpha.xyz);
    }
    float3 normal = normalize(cross(uniforms.basisRight.xyz, uniforms.basisUp.xyz));
    float2 layerScale = float2(length(uniforms.layerModel[0].xyz),
                               length(uniforms.layerModel[1].xyz));
    float3 offset = uniforms.basisRight.xyz * local.x * layerScale.x
                  + uniforms.basisUp.xyz * local.y * layerScale.y
                  + normal * local.z;
    Varyings out;
    out.position = uniforms.viewProjection * float4(center.xyz + offset, 1.0);
    out.uv0 = particle.frame0A.xy + quadVertex.texcoord.x * particle.frame0A.zw
            + quadVertex.texcoord.y * particle.frame0B.xy;
    out.uv1 = particle.frame1A.xy + quadVertex.texcoord.x * particle.frame1A.zw
            + quadVertex.texcoord.y * particle.frame1B.xy;
    float alpha = saturate(particle.rotationAndAlpha.w);
    out.tint = float4(max(particle.colorAndFrameMix.xyz, 0.0) * alpha, alpha);
    out.frameBlend = saturate(particle.colorAndFrameMix.w);
    return out;
}

fragment float4 sceneParticleFrag(
    Varyings in [[stage_in]],
    texture2d<float> texture [[texture(0)]]) {
    constexpr sampler sampler2d(filter::linear, address::clamp_to_edge);
    float4 first = texture.sample(sampler2d, in.uv0);
    float4 second = texture.sample(sampler2d, in.uv1);
    return mix(first, second, in.frameBlend) * in.tint;
}
"""

struct SceneParticleMetalPipeline {
    struct BlendConfiguration {
        let sourceRGB: MTLBlendFactor
        let destinationRGB: MTLBlendFactor
        let sourceAlpha: MTLBlendFactor
        let destinationAlpha: MTLBlendFactor
    }

    private let translucentState: MTLRenderPipelineState
    private let additiveState: MTLRenderPipelineState

    private static let unitQuad: [SceneParticleQuadVertex] = [
        .init(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        .init(position: SIMD2( 0.5, -0.5), texcoord: SIMD2(1, 1)),
        .init(position: SIMD2(-0.5,  0.5), texcoord: SIMD2(0, 0)),
        .init(position: SIMD2( 0.5,  0.5), texcoord: SIMD2(1, 0))
    ]

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let library = try? device.makeLibrary(source: sceneParticleShaderSource, options: nil),
              let vertex = library.makeFunction(name: "sceneParticleVert"),
              let fragment = library.makeFunction(name: "sceneParticleFrag"),
              let translucent = Self.makeState(
                  device: device,
                  vertex: vertex,
                  fragment: fragment,
                  pixelFormat: pixelFormat,
                  blendMode: .translucent
              ),
              let additive = Self.makeState(
                  device: device,
                  vertex: vertex,
                  fragment: fragment,
                  pixelFormat: pixelFormat,
                  blendMode: .additive
              ) else { return nil }
        translucentState = translucent
        additiveState = additive
    }

    static func blendConfiguration(
        for mode: SceneParticlePipelineBlendMode
    ) -> BlendConfiguration {
        BlendConfiguration(
            sourceRGB: mode == .additive ? .sourceAlpha : .one,
            destinationRGB: mode == .additive ? .one : .oneMinusSourceAlpha,
            sourceAlpha: .one,
            destinationAlpha: .oneMinusSourceAlpha
        )
    }

    func draw(
        texture: MTLTexture,
        instances: SceneParticleMetalInstanceBuffer,
        uniforms: SceneParticleLayerUniforms,
        blendMode: SceneParticlePipelineBlendMode,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let drawState = instances.currentDrawState() else { return }
        encoder.setRenderPipelineState(
            blendMode == .additive ? additiveState : translucentState
        )
        var quad = Self.unitQuad
        encoder.setVertexBytes(
            &quad,
            length: quad.count * MemoryLayout<SceneParticleQuadVertex>.stride,
            index: 0
        )
        encoder.setVertexBuffer(drawState.buffer, offset: 0, index: 1)
        var uniformCopy = uniforms
        encoder.setVertexBytes(
            &uniformCopy,
            length: MemoryLayout<SceneParticleLayerUniforms>.stride,
            index: 2
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: Self.unitQuad.count,
            instanceCount: drawState.count
        )
    }

    private static func makeState(
        device: MTLDevice,
        vertex: MTLFunction,
        fragment: MTLFunction,
        pixelFormat: MTLPixelFormat,
        blendMode: SceneParticlePipelineBlendMode
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        let blend = blendConfiguration(for: blendMode)
        attachment.sourceRGBBlendFactor = blend.sourceRGB
        attachment.destinationRGBBlendFactor = blend.destinationRGB
        attachment.sourceAlphaBlendFactor = blend.sourceAlpha
        attachment.destinationAlphaBlendFactor = blend.destinationAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}
