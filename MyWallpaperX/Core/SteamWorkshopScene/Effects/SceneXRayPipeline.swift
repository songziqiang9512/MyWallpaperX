import Metal
import simd

private struct SceneXRayUniforms {
    let cursorUV: SIMD2<Float>
    let size: Float
    let multiply: Float
    let blendUVScale: SIMD2<Float>
    let opacityUVScale: SIMD2<Float>
    let sourceAspect: Float
    let hasOpacityMask: UInt32
}

private let sceneXRayShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float2 cursorUV;
    float size;
    float multiply;
    float2 blendUVScale;
    float2 opacityUVScale;
    float sourceAspect;
    uint hasOpacityMask;
};

vertex Varyings sceneXRayVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    constexpr float2 uvs[] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    Varyings out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 sceneXRayFragment(
    Varyings in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> blendTexture [[texture(1)]],
    texture2d<float> haloTexture [[texture(2)]],
    texture2d<float> opacityMask [[texture(3)]],
    constant Uniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float2 uv = clamp(in.uv, 0.0, 1.0);
    float4 color = source.sample(linearSampler, uv);
    float4 blendColor = blendTexture.sample(
        linearSampler,
        clamp(uv * uniforms.blendUVScale, 0.0, 1.0)
    );

    float2 haloUV = (uv - uniforms.cursorUV)
        * float2(1.0, 1.0 / max(uniforms.sourceAspect, 0.0001))
        / max(uniforms.size, 0.001) + 0.5;
    float2 haloSample = haloTexture.sample(
        linearSampler,
        clamp(haloUV, 0.0, 1.0)
    ).ra;
    float halo = haloSample.x * haloSample.y;
    float blend = blendColor.a * uniforms.multiply * halo;
    if (uniforms.hasOpacityMask != 0u) {
        blend *= opacityMask.sample(
            linearSampler,
            clamp(uv * uniforms.opacityUVScale, 0.0, 1.0)
        ).r;
    }
    color.rgb = mix(color.rgb, blendColor.rgb, blend);
    return color;
}
"""

struct SceneXRayPipeline {
    private let state: MTLRenderPipelineState
    private let haloTexture: MTLTexture

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let library = try? device.makeLibrary(
            source: sceneXRayShaderSource,
            options: nil
        ),
              let vertex = library.makeFunction(name: "sceneXRayVertex"),
              let fragment = library.makeFunction(name: "sceneXRayFragment") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor),
              let haloTexture = Self.makeCalibratedHaloTexture(device: device) else {
            return nil
        }
        self.state = state
        self.haloTexture = haloTexture
    }

    func encode(
        source: MTLTexture,
        resources: SceneXRayEffectTextures,
        target: MTLTexture,
        plan: SceneXRayRuntimePlan,
        cursorUV: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard source !== target,
              source.width > 0,
              source.height > 0 else {
            return false
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(resources.blend, index: 1)
        encoder.setFragmentTexture(resources.halo ?? haloTexture, index: 2)
        encoder.setFragmentTexture(resources.opacityMask ?? resources.blend, index: 3)
        var uniforms = SceneXRayUniforms(
            cursorUV: cursorUV,
            size: plan.size,
            multiply: plan.multiply,
            blendUVScale: plan.blendUVScale,
            opacityUVScale: plan.opacityUVScale,
            sourceAspect: Float(source.width) / Float(source.height),
            hasOpacityMask: resources.opacityMask == nil ? 0 : 1
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneXRayUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private static func makeCalibratedHaloTexture(device: MTLDevice) -> MTLTexture? {
        let dimension = 128
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: dimension,
            height: dimension,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        var pixels = [UInt8](repeating: 255, count: dimension * dimension * 4)
        let center = Float(dimension - 1) * 0.5
        for y in 0..<dimension {
            for x in 0..<dimension {
                let radius = hypotf(Float(x) - center, Float(y) - center) / center
                let alpha = calibratedAlpha(radius: radius)
                pixels[(y * dimension + x) * 4 + 3] = UInt8(
                    min(max(alpha, 0), 1) * 255
                )
            }
        }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, dimension, dimension),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: dimension * 4
            )
        }
        texture.label = "Scene X-Ray calibrated particle/halo_6 approximation"
        return texture
    }

    private static func calibratedAlpha(radius: Float) -> Float {
        let stops: [(Float, Float)] = [
            (0.50, 1.000),
            (0.625, 0.969),
            (0.750, 0.588),
            (0.875, 0.114),
            (1.000, 0.000),
        ]
        if radius <= stops[0].0 { return stops[0].1 }
        for index in 1..<stops.count where radius <= stops[index].0 {
            let lower = stops[index - 1]
            let upper = stops[index]
            let t = (radius - lower.0) / (upper.0 - lower.0)
            let smooth = t * t * (3 - 2 * t)
            return lower.1 + (upper.1 - lower.1) * smooth
        }
        return 0
    }
}
