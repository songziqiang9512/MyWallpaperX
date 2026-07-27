import Metal
import simd

private let sceneWorkshopAudioBarsShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct AudioBarsVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct AudioBarsUniforms {
    float2 resolution;
    int shape;
    int _padding;
};

vertex AudioBarsVaryings sceneWorkshopAudioBarsVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    AudioBarsVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

float sceneAudioBarsMod(float x, float y) {
    return x - y * floor(x / y);
}

float sceneAudioBarsRoundedBoxSDF(
    float2 position,
    float3 authoredSize,
    float correctingFactor
) {
    float3 size = authoredSize * 0.5;
    size.x *= correctingFactor;
    position.y -= size.y + size.z;
    size.y -= size.z;
    float radius = min(size.x, size.y);
    position.x *= correctingFactor;
    return length(max(abs(position) - size.xy + radius, 0.0)) - radius;
}

fragment float4 sceneWorkshopAudioBarsFrag(
    AudioBarsVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant float *left [[buffer(0)]],
    constant float *right [[buffer(1)]],
    constant AudioBarsUniforms &u [[buffer(2)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr float pi = 3.14159265359;
    constexpr float twoPi = 6.28318530718;
    constexpr float barCount = 32.0;
    constexpr float barSpacing = 0.45;
    constexpr float segmentCount = 24.0;
    constexpr float segmentSpacing = 0.26;
    constexpr float volumeFactor = 0.75;
    constexpr float2 barColor = float2(1.0, 0.0);

    float2 uv = input.texcoord;
    float2 circleCoord = (uv - 0.5) * 2.0;
    float angle = sceneAudioBarsMod((atan2(circleCoord.y, circleCoord.x) + pi) / twoPi, 1.0);
    float radial = length(circleCoord);
    if (u.shape == 4) {
        radial = 1.0 - radial;
    }

    float barDist = abs(fract(angle * barCount) * 2.0 - 1.0);
    float frequency = floor(angle * barCount) / barCount * 64.0;
    float firstFrequency = sceneAudioBarsMod(frequency, 64.0);
    float secondFrequency = sceneAudioBarsMod(firstFrequency + 1.0, 64.0);
    int firstIndex = clamp(int(firstFrequency), 0, 63);
    int secondIndex = clamp(int(secondFrequency), 0, 63);
    float interpolation = smoothstep(0.0, 1.0, fract(frequency));
    float firstVolume = (left[firstIndex] + right[firstIndex]) * 0.5;
    float secondVolume = (left[secondIndex] + right[secondIndex]) * 0.5;
    float volume = mix(firstVolume, secondVolume, interpolation) * volumeFactor;

    float correctingFactor = u.resolution.x / u.resolution.y;
    float barWidth = (1.0 - barSpacing) / barCount;
    float antiAliasFactor = 15.0 / min(u.resolution.x, u.resolution.y);
    float smoothnessStart = -0.05 * antiAliasFactor;
    float segmentHeight = 1.0 / segmentCount;
    float segmentOffset = segmentHeight;
    float barHeight = mix(0.0, 1.0, volume);
    barHeight -= sceneAudioBarsMod(barHeight + segmentOffset, segmentHeight)
        + segmentOffset;

    float lowerBound = 0.0;
    float upperBound = segmentHeight * (1.0 - segmentSpacing)
        * step(lowerBound, 1.0 - radial);
    float2 center = float2(
        barDist / barCount * 0.5,
        sceneAudioBarsMod(1.0 - radial, segmentHeight)
            - (segmentHeight - upperBound) * 0.5
    );
    float3 size = float3(barWidth, upperBound, lowerBound)
        * step(1.0 - radial, barHeight);
    float distance = sceneAudioBarsRoundedBoxSDF(center, size, correctingFactor);
    float bar = 1.0 - smoothstep(smoothnessStart, 0.0, distance);
    bar *= float(angle > 0.0 && angle < 1.0);

    float4 scene = source.sample(linearClamp, uv);
    float3 authoredColor = float3(barColor.x, barColor.y, 1.0);
    float3 sceneStraight = scene.a > 1e-6
        ? clamp(scene.rgb / scene.a, 0.0, 1.0)
        : float3(0.0);
    float3 base = mix(authoredColor, sceneStraight, scene.a);
    float3 finalColor = mix(base, authoredColor, bar);
    return float4(finalColor * bar, bar);
}
"""

struct SceneWorkshopAudioBarsPipeline {
    private struct Uniforms {
        var resolution: SIMD2<Float>
        var shape: Int32
        var padding: Int32 = 0
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneWorkshopAudioBarsShaderSource,
                  options: nil
              ),
              let vertex = library.makeFunction(name: "sceneWorkshopAudioBarsVert"),
              let fragment = library.makeFunction(name: "sceneWorkshopAudioBarsFrag") else {
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
        shape: Int,
        spectrum: SceneAudioSpectrumSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard (shape == 4 || shape == 5),
              spectrum.left64.count == SceneAudioSpectrumSnapshot.extendedBandCount,
              spectrum.right64.count == SceneAudioSpectrumSnapshot.extendedBandCount,
              valid(source: source, target: target, commandBuffer: commandBuffer) else {
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
        spectrum.left64.withUnsafeBytes { bytes in
            encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        spectrum.right64.withUnsafeBytes { bytes in
            encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 1)
        }
        var uniforms = Uniforms(
            resolution: SIMD2(Float(target.width), Float(target.height)),
            shape: Int32(shape)
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 2
        )
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
