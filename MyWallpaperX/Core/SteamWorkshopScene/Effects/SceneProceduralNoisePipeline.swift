import Metal
import simd

private let sceneProceduralNoiseShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct NoiseVaryings {
    float4 position [[position]];
    float2 uv;
};

struct NoiseUniforms {
    float2 scale;
    float2 offset;
    float2 magnitude;
    float2 thresholds;
    float4 colorsMin;
    float4 colorsMax;
    float4 params0; // opacity, exponent, fractal scale, fractal influence
    float4 params1; // gradient, seed, animation speed, scroll direction
    float4 params2; // scroll speed, threshold offset, shift amount, time
    uint variant;
    uint fractals;
    uint2 padding;
};

vertex NoiseVaryings proceduralNoiseVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    return NoiseVaryings { float4(positions[vertexID], 0.0, 1.0), texcoords[vertexID] };
}

float4 noiseHash44(float4 value) {
    value = fract(value * float4(0.1031, 0.1030, 0.0973, 444.129));
    value += dot(value, value.wzxy + 19.19);
    return fract((value.xxyz + value.yzzw) * value.zywx);
}

float2 noiseHash23(float3 value) {
    value = fract(value * float3(0.1031, 0.1030, 437.195));
    value += dot(value, value.yzx + 19.19);
    return fract((value.xx + value.yz) * value.zy);
}

float noiseInterpolate(float4 odd, float4 even, float3 amount) {
    odd = mix(odd, even, amount.x);
    even.xy = mix(odd.xz, odd.yw, amount.y);
    return mix(even.x, even.y, amount.z);
}

float4 noisePerlin(float3 uv, float seed) {
    float3 low = floor(uv);
    float3 high = ceil(uv);
    float3 fraction = uv - low;
    float3 faded = fraction * fraction * fraction
        * (fraction * (fraction * 6.0 - 15.0) + 10.0);
    float4 tiled = float4(low.xy, high.xy);
    const float2 sub = float2(1.0, 0.0);
    float4 color;
    for (uint index = 0; index < 4; ++index) {
        float channel = float(index);
        float4 odd;
        float4 even;
        odd.x = dot(noiseHash44(float4(tiled.xy, low.z, seed) + channel).xyz - 0.5, fraction);
        even.x = dot(noiseHash44(float4(tiled.zy, low.z, seed) + channel).xyz - 0.5, fraction - sub.xyy);
        odd.y = dot(noiseHash44(float4(tiled.xw, low.z, seed) + channel).xyz - 0.5, fraction - sub.yxy);
        even.y = dot(noiseHash44(float4(tiled.zw, low.z, seed) + channel).xyz - 0.5, fraction - sub.xxy);
        odd.z = dot(noiseHash44(float4(tiled.xy, high.z, seed) + channel).xyz - 0.5, fraction - sub.yyx);
        even.z = dot(noiseHash44(float4(tiled.zy, high.z, seed) + channel).xyz - 0.5, fraction - sub.xyx);
        odd.w = dot(noiseHash44(float4(tiled.xw, high.z, seed) + channel).xyz - 0.5, fraction - sub.yxx);
        even.w = dot(noiseHash44(float4(tiled.zw, high.z, seed) + channel).xyz - 0.5, fraction - sub.xxx);
        color[index] = noiseInterpolate(odd, even, faded);
    }
    return color;
}

float4 noiseSimplex(float3 uv, float seed) {
    const float2 coefficients = float2(1.0 / 6.0, 1.0 / 3.0);
    float3 cell = floor(uv + dot(uv, coefficients.yyy));
    float3 x = uv - cell + dot(cell, coefficients.xxx);
    float3 order = step(x.yzx, x);
    float3 i1 = order * (1.0 - order.zxy);
    float3 i2 = 1.0 - order.zxy * (1.0 - order);
    float3 x1 = x - i1 + coefficients.x;
    float3 x2 = x - i2 + coefficients.y;
    float3 x3 = x - 0.5;
    float4 weight = max(0.6 - float4(
        dot(x, x), dot(x1, x1), dot(x2, x2), dot(x3, x3)
    ), 0.0);
    weight *= weight;
    weight *= weight;
    float4 coordinates[4] = {
        float4(cell, seed), float4(cell + i1, seed),
        float4(cell + i2, seed), float4(cell + 1.0, seed)
    };
    float4 color;
    for (uint index = 0; index < 4; ++index) {
        float channel = float(index);
        float4 distance;
        distance.x = dot(noiseHash44(coordinates[0] + channel).xyz - 0.5, x);
        distance.y = dot(noiseHash44(coordinates[1] + channel).xyz - 0.5, x1);
        distance.z = dot(noiseHash44(coordinates[2] + channel).xyz - 0.5, x2);
        distance.w = dot(noiseHash44(coordinates[3] + channel).xyz - 0.5, x3);
        color[index] = dot(distance * weight, 40.0);
    }
    return color;
}

float2 noiseCurl(
    float2 uv, float speed, float2 scale, uint fractals,
    float fractalScale, float fractalInfluence
) {
    float2 epsilon = float2(0.0, scale.y);
    float2 value = 0.0;
    float influence = 0.5;
    float frequency = 1.0;
    for (uint index = 0; index < 5; ++index) {
        if (index >= fractals) { break; }
        float4 sampleValue = noiseSimplex(float3((uv + epsilon) * frequency, speed), frequency);
        value += influence * float2(
            sampleValue.x - sampleValue.y,
            -(sampleValue.z - sampleValue.w)
        );
        frequency *= fractalScale;
        scale *= fractalScale;
        speed += speed;
        influence *= fractalInfluence;
    }
    return value;
}

float2 noiseWorleyMix(
    float3 uv, float2 magnitude, float2 ratio, float seed
) {
    float2 cell = floor(uv.xy);
    float2 fraction = fract(uv.xy);
    float4 values = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 neighbor = float2(float(x), float(y));
            float2 position = (cell + neighbor) * ratio;
            float2 point = noiseHash23(float3(position, seed));
            point = sin(uv.z + M_PI_2_F * point) * magnitude + 0.5;
            point = neighbor + point - fraction;
            float distance = saturate(length(point));
            values.w = (1.0 - distance) + values.w * distance;
            values.xy = mix(point + values.w, values.xy, distance);
        }
    }
    return values.xy - 0.5;
}

fragment float4 proceduralNoiseFragment(
    NoiseVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant NoiseUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 albedo = source.sample(linearClamp, input.uv);
    float2 aspect = float2(1.0, float(source.get_height()) / float(source.get_width()));
    float2 transformScale = max(1e-6, uniforms.scale * 10.0 * aspect);
    float2 scroll = float2(
        sin(-uniforms.params1.w), cos(uniforms.params1.w)
    ) * uniforms.params2.w * uniforms.params2.x * 10.0;
    float2 transformedOffset = (uniforms.offset + scroll) * aspect * transformScale;
    float2 coordinate = input.uv * transformScale + transformedOffset;
    float animateScale = uniforms.variant == 2 ? 4.0 : 1.0;
    float animate = uniforms.params2.w * uniforms.params1.z * animateScale + uniforms.params1.y;

    if (uniforms.variant == 0) {
        float influence = 0.5;
        float4 value = 0.0;
        float2 period = transformScale;
        for (uint index = 1; index <= 5; ++index) {
            if (index > uniforms.fractals) { break; }
            value += noisePerlin(float3(coordinate, animate), float(index)) * influence;
            influence *= uniforms.params0.w;
            coordinate *= uniforms.params0.z;
            period *= uniforms.params0.z;
        }
        float4 noise = max(0.0, value / (1.0 - influence) * 2.0 + 0.5);
        noise = max(0.0, (pow(noise, uniforms.params0.y) - uniforms.thresholds.x)
            / (uniforms.thresholds.y - uniforms.thresholds.x)) + uniforms.params2.y;
        noise = saturate((noise - 0.5) / max(1e-6, uniforms.params1.x) + 0.5);
        float3 color = noise.rgb * (uniforms.colorsMax.rgb - uniforms.colorsMin.rgb)
            + uniforms.colorsMin.rgb;
        return float4(mix(albedo.rgb, color, uniforms.params0.x), albedo.a);
    }

    float2 displacement = 0.0;
    if (uniforms.variant == 1) {
        displacement = noiseCurl(
            coordinate, animate, transformScale, uniforms.fractals,
            uniforms.params0.z, uniforms.params0.w
        ) * uniforms.magnitude * 0.15 * transformScale;
    } else {
        float influence = 0.5;
        float2 value = 0.0;
        float2 period = transformScale;
        for (uint index = 1; index <= 5; ++index) {
            if (index > uniforms.fractals) { break; }
            value += noiseWorleyMix(
                float3(coordinate, animate), uniforms.magnitude * 0.5,
                aspect, float(index)
            ) * influence;
            influence *= uniforms.params0.w;
            coordinate *= uniforms.params0.z;
            period *= uniforms.params0.z;
        }
        displacement = value * 2.0;
    }
    float displacementLength = length(displacement);
    float scaledMagnitude = mix(
        uniforms.thresholds.x, uniforms.thresholds.y,
        pow(displacementLength, uniforms.params0.y)
    ) + uniforms.params2.y;
    scaledMagnitude = (scaledMagnitude - 0.5) * max(1e-6, uniforms.params1.x) + 0.5;
    displacement = displacement / max(1e-6, displacementLength) * scaledMagnitude;
    if (uniforms.variant == 1) {
        displacement /= transformScale;
    } else {
        displacement *= uniforms.params2.z / transformScale;
    }
    float4 warped = source.sample(linearClamp, input.uv + displacement);
    return float4(mix(albedo.rgb, warped.rgb, uniforms.params0.x), albedo.a);
}
"""

struct SceneProceduralNoisePipeline {
    struct Uniforms {
        var scale: SIMD2<Float>
        var offset: SIMD2<Float>
        var magnitude: SIMD2<Float>
        var thresholds: SIMD2<Float>
        var colorsMin: SIMD4<Float>
        var colorsMax: SIMD4<Float>
        var params0: SIMD4<Float>
        var params1: SIMD4<Float>
        var params2: SIMD4<Float>
        var variant: UInt32
        var fractals: UInt32
        var padding: SIMD2<UInt32> = .zero
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneProceduralNoiseShaderSource, options: nil
              ),
              let vertex = library.makeFunction(name: "proceduralNoiseVertex"),
              let fragment = library.makeFunction(name: "proceduralNoiseFragment") else {
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
        uniforms: Uniforms,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(source: source, target: target, uniforms: uniforms, commandBuffer: commandBuffer)
        else { return false }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        var uniforms = uniforms
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        target: MTLTexture,
        uniforms: Uniforms,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let finite = [uniforms.scale.x, uniforms.scale.y, uniforms.offset.x, uniforms.offset.y,
                      uniforms.magnitude.x, uniforms.magnitude.y, uniforms.thresholds.x,
                      uniforms.thresholds.y, uniforms.params0.x, uniforms.params0.y,
                      uniforms.params0.z, uniforms.params0.w, uniforms.params1.x,
                      uniforms.params1.y, uniforms.params1.z, uniforms.params1.w,
                      uniforms.params2.x, uniforms.params2.y, uniforms.params2.z,
                      uniforms.params2.w].allSatisfy(\.isFinite)
        return source.textureType == .type2D && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm && target.pixelFormat == .bgra8Unorm
            && source.width > 0 && source.width == target.width
            && source.height > 0 && source.height == target.height
            && source.mipmapLevelCount == 1 && target.mipmapLevelCount == 1
            && source.sampleCount == 1 && target.sampleCount == 1
            && source.usage.contains(.shaderRead) && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && uniforms.scale.x > 0 && uniforms.scale.y > 0
            && uniforms.thresholds.y > uniforms.thresholds.x
            && uniforms.variant <= 2 && (1...5).contains(uniforms.fractals) && finite
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID
    }
}
