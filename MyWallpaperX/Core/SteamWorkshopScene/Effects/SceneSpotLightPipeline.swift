import Metal
import simd

private let sceneSpotLightShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct SpotLightVertex {
    float2 position;
    float2 texcoord;
};

struct SpotLightVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct SpotLightUniforms {
    float4 color;
    float innerRatio;
    float density;
    float exponent;
    float volumetricsExponent;
    float intensity;
};

vertex SpotLightVaryings sceneSpotLightVert(
    uint vertexID [[vertex_id]],
    constant SpotLightVertex *vertices [[buffer(0)]],
    constant float4x4 &mvp [[buffer(1)]]
) {
    SpotLightVaryings out;
    out.position = mvp * float4(vertices[vertexID].position, 0.0, 1.0);
    out.texcoord = vertices[vertexID].texcoord;
    return out;
}

fragment float4 sceneSpotLightFrag(
    SpotLightVaryings input [[stage_in]],
    constant SpotLightUniforms &u [[buffer(0)]]
) {
    float along = saturate(input.texcoord.x);
    float across = abs(input.texcoord.y * 2.0 - 1.0);
    float coneCoordinate = across / max(along, 0.0005);
    float cone = 1.0 - smoothstep(u.innerRatio, 1.0, coneCoordinate);
    float originFade = smoothstep(0.0, 0.035, along);
    float reach = pow(
        saturate(1.0 - along),
        max(u.volumetricsExponent * 0.42, 0.1)
    );
    float profile = pow(
        saturate(cone),
        max(u.exponent * 0.38, 0.2)
    ) * originFade * reach;
    float opticalDepth = max(u.density, 0.0) * 0.22 * profile;
    float opacity = saturate(
        (1.0 - exp(-opticalDepth)) * saturate(u.intensity / 100.0)
    );
    float colorBoost = 0.8 + saturate(u.intensity / 100.0) * 0.45;
    float3 color = saturate(u.color.rgb * colorBoost);
    return float4(color * opacity, opacity);
}
"""

final class SceneSpotLightPipeline {
    private struct Uniforms {
        var color: SIMD4<Float>
        var innerRatio: Float
        var density: Float
        var exponent: Float
        var volumetricsExponent: Float
        var intensity: Float
    }

    private let state: MTLRenderPipelineState
    private static let vertices: [SceneQuadVertex] = [
        .init(position: SIMD2(0, -1), texcoord: SIMD2(0, 0)),
        .init(position: SIMD2(1, -1), texcoord: SIMD2(1, 0)),
        .init(position: SIMD2(0, 1), texcoord: SIMD2(0, 1)),
        .init(position: SIMD2(1, 1), texcoord: SIMD2(1, 1)),
    ]

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneSpotLightShaderSource,
                  options: MTLCompileOptions()
              ),
              let vertex = library.makeFunction(name: "sceneSpotLightVert"),
              let fragment = library.makeFunction(name: "sceneSpotLightFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.state = state
    }

    func draw(
        plan: SceneSpotLightPlan,
        worldOrigin: SIMD2<Float>,
        viewProjection: simd_float4x4,
        sceneTime: Double,
        encoder: MTLRenderCommandEncoder
    ) -> Bool {
        guard worldOrigin.x.isFinite,
              worldOrigin.y.isFinite,
              viewProjection.columns.0.allFinite,
              viewProjection.columns.1.allFinite,
              viewProjection.columns.2.allFinite,
              viewProjection.columns.3.allFinite,
              let authoredAngle = plan.authoredAngle(at: sceneTime) else {
            return false
        }
        let outerHalfWidth = plan.radius * tan(plan.outerConeRadians * 0.5)
        let innerHalfWidth = plan.radius * tan(plan.innerConeRadians * 0.5)
        let supportHalfWidth = outerHalfWidth * 1.6
        guard outerHalfWidth.isFinite,
              innerHalfWidth.isFinite,
              supportHalfWidth.isFinite,
              outerHalfWidth > 0,
              innerHalfWidth > 0,
              innerHalfWidth <= outerHalfWidth else {
            return false
        }
        let model = SceneMatrix.translation(SIMD3(worldOrigin.x, worldOrigin.y, 0))
            * SceneMatrix.rotationZ(-authoredAngle)
            * SceneMatrix.scale(SIMD3(plan.radius, supportHalfWidth, 1))
        var vertices = Self.vertices
        var mvp = viewProjection * model
        var uniforms = Uniforms(
            color: SIMD4(plan.color, 1),
            innerRatio: innerHalfWidth / supportHalfWidth,
            density: plan.density,
            exponent: plan.exponent,
            volumetricsExponent: plan.volumetricsExponent,
            intensity: plan.intensity
        )
        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(
            &vertices,
            length: MemoryLayout<SceneQuadVertex>.stride * vertices.count,
            index: 0
        )
        encoder.setVertexBytes(
            &mvp,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
