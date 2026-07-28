import Metal
import simd

private let sceneWorkshopSimpleAudioBarsShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct SimpleAudioBarsVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct SimpleAudioBarsUniforms {
    float3 color;
    int barCount;
    int bandCount;
    float spacing;
    float lowerBound;
    float upperBound;
    float opacity;
    uint clipLow;
    uint clipHigh;
};

vertex SimpleAudioBarsVaryings sceneWorkshopSimpleAudioBarsVert(
    uint vertexID [[vertex_id]]
) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    SimpleAudioBarsVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneWorkshopSimpleAudioBarsFrag(
    SimpleAudioBarsVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant float *left [[buffer(0)]],
    constant float *right [[buffer(1)]],
    constant SimpleAudioBarsUniforms &u [[buffer(2)]]
) {
    float horizontal = clamp(input.texcoord.x, 0.0, 0.999999);
    float barCoordinate = horizontal * float(u.barCount);
    float slotDistance = abs(fract(barCoordinate) * 2.0 - 1.0);
    if (slotDistance > 1.0 - u.spacing) {
        return float4(0.0);
    }

    float frequency = floor(barCoordinate)
        / float(u.barCount) * float(u.bandCount);
    float wrappedFrequency = fmod(frequency, float(u.bandCount));
    int firstIndex = clamp(int(floor(wrappedFrequency)), 0, u.bandCount - 1);
    int secondIndex = (firstIndex + 1) % u.bandCount;
    float firstLevel = (left[firstIndex] + right[firstIndex]) * 0.5;
    float secondLevel = (left[secondIndex] + right[secondIndex]) * 0.5;
    float level = clamp(
        mix(firstLevel, secondLevel, smoothstep(0.0, 1.0, fract(frequency))),
        0.0,
        1.0
    );
    if (level <= 0.0) {
        return float4(0.0);
    }

    float barHeight = mix(u.lowerBound, u.upperBound, level);
    float heightFromBottom = 1.0 - input.texcoord.y;
    float visibleLowerEdge = u.clipLow != 0 ? u.lowerBound : 0.0;
    float visibleUpperEdge = u.clipHigh != 0 ? u.upperBound : 1.0;
    bool visible = heightFromBottom >= visibleLowerEdge
        && heightFromBottom <= min(barHeight, visibleUpperEdge);
    float alpha = visible ? u.opacity : 0.0;
    return float4(u.color * alpha, alpha);
}
"""

struct SceneWorkshopSimpleAudioBarsPipeline {
    typealias Parameters = SceneWorkshopAudioBarsExecutionPlan.SimpleParameters

    private struct Uniforms {
        var color: SIMD3<Float>
        var barCount: Int32
        var bandCount: Int32
        var spacing: Float
        var lowerBound: Float
        var upperBound: Float
        var opacity: Float
        var clipLow: UInt32
        var clipHigh: UInt32
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneWorkshopSimpleAudioBarsShaderSource,
                  options: nil
              ),
              let vertex = library.makeFunction(
                  name: "sceneWorkshopSimpleAudioBarsVert"
              ),
              let fragment = library.makeFunction(
                  name: "sceneWorkshopSimpleAudioBarsFrag"
              ) else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(
            descriptor: descriptor
        ) else {
            return nil
        }
        self.state = state
        deviceRegistryID = device.registryID
    }

    func encode(
        source: MTLTexture,
        target: MTLTexture,
        parameters: Parameters,
        color: SIMD3<Float>,
        spectrum: SceneAudioSpectrumSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let bands = bands(
            for: parameters.profile.resolution,
            spectrum: spectrum
        ),
        valid(parameters: parameters, color: color),
        valid(source: source, target: target, commandBuffer: commandBuffer) else {
            return false
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return false
        }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        bands.left.withUnsafeBytes { bytes in
            encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        bands.right.withUnsafeBytes { bytes in
            encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 1)
        }
        var uniforms = Uniforms(
            color: color,
            barCount: Int32(parameters.barCount),
            bandCount: Int32(parameters.profile.resolution),
            spacing: parameters.barSpacing,
            lowerBound: parameters.lowerBound,
            upperBound: parameters.upperBound,
            opacity: parameters.opacity,
            clipLow: parameters.profile.clipsLow ? 1 : 0,
            clipHigh: parameters.profile.clipsHigh ? 1 : 0
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

    private func bands(
        for resolution: Int,
        spectrum: SceneAudioSpectrumSnapshot
    ) -> (left: [Float], right: [Float])? {
        switch resolution {
        case SceneAudioSpectrumSnapshot.mediumBandCount:
            guard spectrum.left32.count == resolution,
                  spectrum.right32.count == resolution else {
                return nil
            }
            return (spectrum.left32, spectrum.right32)
        case SceneAudioSpectrumSnapshot.extendedBandCount:
            guard spectrum.left64.count == resolution,
                  spectrum.right64.count == resolution else {
                return nil
            }
            return (spectrum.left64, spectrum.right64)
        default:
            return nil
        }
    }

    private func valid(parameters: Parameters, color: SIMD3<Float>) -> Bool {
        (1 ... 200).contains(parameters.barCount)
            && parameters.barSpacing.isFinite
            && (0 ... 1).contains(parameters.barSpacing)
            && parameters.lowerBound.isFinite
            && parameters.upperBound.isFinite
            && 0 <= parameters.lowerBound
            && parameters.lowerBound < parameters.upperBound
            && parameters.upperBound <= 1
            && parameters.opacity.isFinite
            && (0 ... 1).contains(parameters.opacity)
            && color.x.isFinite && color.y.isFinite && color.z.isFinite
            && (0 ... 1).contains(color.x)
            && (0 ... 1).contains(color.y)
            && (0 ... 1).contains(color.z)
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
