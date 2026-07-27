import Metal

private let sceneWorkshopShiftHueShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct ShiftHueVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex ShiftHueVaryings sceneWorkshopShiftHueVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    ShiftHueVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

float3 sceneRGBToHSV(float3 rgb) {
    float4 p = rgb.g < rgb.b
        ? float4(rgb.b, rgb.g, -1.0, 2.0 / 3.0)
        : float4(rgb.g, rgb.b, 0.0, -1.0 / 3.0);
    float4 q = rgb.r < p.x
        ? float4(p.x, p.y, p.w, rgb.r)
        : float4(rgb.r, p.y, p.z, p.x);
    float chroma = q.x - min(q.w, q.y);
    float hue = abs((q.w - q.y) / (6.0 * chroma + 1e-10) + q.z);
    return float3(hue, chroma / (q.x + 1e-10), q.x);
}

float3 sceneHSVToRGB(float3 hsv) {
    const float4 k = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), hsv.y);
}

fragment float4 sceneWorkshopShiftHueFrag(
    ShiftHueVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant float2 &timeAndSpeed [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 albedo = source.sample(linearClamp, input.texcoord);
    float3 hsv = sceneRGBToHSV(albedo.rgb);
    hsv.x = fract(hsv.x + timeAndSpeed.x * timeAndSpeed.y);
    albedo.rgb = sceneHSVToRGB(hsv);
    return albedo;
}
"""

struct SceneWorkshopShiftHuePipeline {
    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneWorkshopShiftHueShaderSource,
                  options: nil
              ),
              let vertex = library.makeFunction(name: "sceneWorkshopShiftHueVert"),
              let fragment = library.makeFunction(name: "sceneWorkshopShiftHueFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.state = state
        deviceRegistryID = device.registryID
    }

    func encode(
        source: MTLTexture,
        target: MTLTexture,
        speed: Float,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard speed.isFinite, (0...1).contains(speed), time.isFinite else {
            return false
        }
        return encodeValues(
            source: source,
            target: target,
            timeAndSpeed: SIMD2(time, speed),
            commandBuffer: commandBuffer
        )
    }

    func encodeHueOffset(
        source: MTLTexture,
        target: MTLTexture,
        offset: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard offset.isFinite, (0...2).contains(offset) else { return false }
        return encodeValues(
            source: source,
            target: target,
            timeAndSpeed: SIMD2(1, offset),
            commandBuffer: commandBuffer
        )
    }

    private func encodeValues(
        source: MTLTexture,
        target: MTLTexture,
        timeAndSpeed: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(source: source, target: target, commandBuffer: commandBuffer) else {
            return false
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        var values = timeAndSpeed
        encoder.setFragmentBytes(&values, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        source.textureType == .type2D && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm && target.pixelFormat == .bgra8Unorm
            && source.width > 0 && source.width == target.width
            && source.height > 0 && source.height == target.height
            && source.mipmapLevelCount == 1 && target.mipmapLevelCount == 1
            && source.sampleCount == 1 && target.sampleCount == 1
            && source.usage.contains(.shaderRead) && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID
    }
}
