import Metal
import simd

private let sceneLayerColorBlendShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct SceneLayerBlendVertex {
    float2 position;
    float2 texcoord;
};

struct SceneLayerBlendVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex SceneLayerBlendVaryings sceneLayerColorBlendVert(
    uint vertexID [[vertex_id]],
    constant SceneLayerBlendVertex *vertices [[buffer(0)]],
    constant float4x4 &mvp [[buffer(1)]]
) {
    SceneLayerBlendVaryings out;
    out.position = mvp * float4(vertices[vertexID].position, 0.0, 1.0);
    out.texcoord = vertices[vertexID].texcoord;
    return out;
}

fragment float4 sceneLayerColorBlendFrag(
    SceneLayerBlendVaryings input [[stage_in]],
    texture2d<float> layerTexture [[texture(0)]],
    texture2d<float> backgroundTexture [[texture(1)]],
    constant int &blendMode [[buffer(0)]]
) {
    constexpr sampler sampler2d(filter::linear, address::clamp_to_edge);
    float4 layer = layerTexture.sample(sampler2d, input.texcoord);
    float4 background = backgroundTexture.read(uint2(input.position.xy));
    float3 straightLayer = layer.a > 0.0 ? layer.rgb / layer.a : float3(0.0);
    return float4(
        sceneApplyBlending(blendMode, background.rgb, straightLayer, layer.a),
        background.a
    );
}
"""

final class SceneLayerColorBlendPipeline {
    private let device: MTLDevice
    private let state: MTLRenderPipelineState
    private var backgroundTexture: MTLTexture?
    private let byteBudget = 64 * 1_024 * 1_024

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(
            source: sceneLayerColorBlendShaderSource,
            options: options
        ), let vertex = library.makeFunction(name: "sceneLayerColorBlendVert"),
           let fragment = library.makeFunction(name: "sceneLayerColorBlendFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.device = device
        self.state = state
    }

    func snapshot(
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard target.textureType == .type2D,
              target.sampleCount == 1,
              target.pixelFormat == .bgra8Unorm,
              let byteCost = byteCost(width: target.width, height: target.height),
              byteCost <= byteBudget,
              let background = background(width: target.width, height: target.height),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }
        encoder.copy(
            from: target,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: target.width, height: target.height, depth: 1),
            to: background,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        return background
    }

    func draw(
        layerTexture: MTLTexture,
        backgroundTexture: MTLTexture,
        blendMode: Int,
        mvp: simd_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        var vertices = Self.unitQuadVertices
        var mvpCopy = mvp
        var mode = Int32(blendMode)
        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<SceneQuadVertex>.stride,
            index: 0
        )
        encoder.setVertexBytes(
            &mvpCopy,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(&mode, length: MemoryLayout<Int32>.size, index: 0)
        encoder.setFragmentTexture(layerTexture, index: 0)
        encoder.setFragmentTexture(backgroundTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func background(width: Int, height: Int) -> MTLTexture? {
        if let backgroundTexture,
           backgroundTexture.width == width,
           backgroundTexture.height == height {
            return backgroundTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Scene layer color blend background \(width)x\(height)"
        backgroundTexture = texture
        return texture
    }

    private func byteCost(width: Int, height: Int) -> Int? {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        return pixelOverflow || byteOverflow ? nil : bytes
    }

    private static let unitQuadVertices: [SceneQuadVertex] = [
        SceneQuadVertex(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        SceneQuadVertex(position: SIMD2( 0.5, -0.5), texcoord: SIMD2(1, 1)),
        SceneQuadVertex(position: SIMD2(-0.5,  0.5), texcoord: SIMD2(0, 0)),
        SceneQuadVertex(position: SIMD2( 0.5,  0.5), texcoord: SIMD2(1, 0)),
    ]
}

enum SceneLayerColorBlendRenderer {
    static func supports(_ blendMode: Int) -> Bool {
        (0 ... SceneBlendModeShaderSource.maximumMode).contains(blendMode)
    }

    static func draw(
        texture: MTLTexture,
        masks: SceneImageLayerMasks,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        dependencyTexture: MTLTexture?,
        layer: SceneRenderDescriptor.Layer,
        pipeline: SceneImageLayerPipeline,
        colorBlendPipeline: SceneLayerColorBlendPipeline,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        let blendMode = layer.colorBlendMode ?? 0
        guard supports(blendMode) else { return false }
        if blendMode == 0 {
            guard let encoder = mainPass.encoder() else { return false }
            pipeline.bind(encoder: encoder)
            pipeline.drawLayer(
                texture: texture,
                shakeMaskTexture: nil,
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: masks.iris ?? masks.opacity,
                dependencyTexture: dependencyTexture,
                mvp: mvp,
                uniforms: uniforms,
                encoder: encoder
            )
            return true
        }

        let captured = mainPass.withReadableTarget { target, commandBuffer in
            colorBlendPipeline.snapshot(target: target, commandBuffer: commandBuffer)
        }
        guard let background = captured ?? nil,
              let encoder = mainPass.encoder() else {
            return false
        }
        colorBlendPipeline.draw(
            layerTexture: texture,
            backgroundTexture: background,
            blendMode: blendMode,
            mvp: mvp,
            encoder: encoder
        )
        return true
    }
}
