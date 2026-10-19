import Foundation
import Metal
import simd

// Independent flat-fragment hardware oracle: it selects no alpha threshold and
// shares no particle vertex/tint/sample implementation with the production draw.
private let particleCoverageReferenceSource = """
#include <metal_stdlib>
using namespace metal;
vertex float4 coverageReferenceVertex(uint index [[vertex_id]]) {
    const float2 corners[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
    return float4(corners[index],0.5,1);
}
fragment float4 coverageReferenceFragment(constant float4 &color [[buffer(0)]]) {
    return color;
}
"""

enum SceneParticleCoverageRenderingHarness {
    private static let side = 16
    private static let textureRGB = SIMD3<Float>(240, 80, 32) / 255
    private static let particleRGB = SIMD3<Float>(0.5, 0.75, 1.25)
    private static let overbright: Float = 1.2
    private static let pairs: [(UInt8, Float)] = [
        (0, 1), (255, 0), (64, 1), (128, 1),
        (192, 1), (255, 1), (255, 0.52), (128, 0.5)
    ]

    static func run() throws -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let coveragePipeline = SceneParticleMetalPipeline(
                device: device, requiresAlphaToCoverage: true),
              let ordinaryPipeline = SceneParticleMetalPipeline(device: device)
        else { throw failure("device-or-pipeline") }
        let library = try device.makeLibrary(source: particleCoverageReferenceSource, options: nil)
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = false
        guard let disabledDepth = device.makeDepthStencilState(descriptor: depthDescriptor)
        else { throw failure("disabled-depth-state") }
        var coverage: [[String: Any]] = []
        var ordinary: [[String: Any]] = []
        var missing: [[String: Any]] = []
        for depth in [false, true] {
            let coverageReference = try referenceState(
                device: device, library: library, mode: .alphaToCoverage, depth: depth)
            for (textureAlpha, particleAlpha) in pairs {
                coverage.append(try draw(
                    device: device, queue: queue, pipeline: coveragePipeline,
                    reference: coverageReference, disabledDepth: disabledDepth,
                    textureAlpha: textureAlpha, particleAlpha: particleAlpha,
                    mode: .alphaToCoverage, depth: depth))
            }
            for mode in [SceneParticlePipelineBlendMode.translucent, .additive] {
                let reference = try referenceState(
                    device: device, library: library, mode: mode, depth: depth)
                ordinary.append(try draw(
                    device: device, queue: queue, pipeline: coveragePipeline,
                    reference: reference, disabledDepth: disabledDepth,
                    textureAlpha: 192, particleAlpha: 0.52, mode: mode, depth: depth))
                if mode == .translucent {
                    missing.append(try draw(
                        device: device, queue: queue, pipeline: ordinaryPipeline,
                        reference: reference, disabledDepth: disabledDepth,
                        textureAlpha: 192, particleAlpha: 0.52, mode: mode,
                        depth: depth, attemptsUnpreparedCoverage: true))
                }
            }
        }
        return ["device": device.name, "sampleCount": 1,
                "coverage": coverage, "ordinary": ordinary, "missing": missing]
    }

    private static func referenceState(
        device: MTLDevice, library: MTLLibrary,
        mode: SceneParticlePipelineBlendMode, depth: Bool
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "coverageReferenceVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "coverageReferenceFragment")
        descriptor.rasterSampleCount = 1
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        if depth { descriptor.depthAttachmentPixelFormat = .depth32Float }
        let color = descriptor.colorAttachments[0]!
        switch mode {
        case .alphaToCoverage:
            descriptor.isAlphaToCoverageEnabled = true
            descriptor.isAlphaToOneEnabled = true
        case .translucent, .additive:
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = mode == .additive ? .one : .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func sourceTexture(device: MTLDevice, alpha: UInt8) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor)
        else { throw failure("source-texture") }
        let bytes: [UInt8] = [240, 80, 32, alpha]
        bytes.withUnsafeBytes {
            texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: 4)
        }
        return texture
    }

    private static func target(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        guard let texture = device.makeTexture(descriptor: descriptor)
        else { throw failure("color-target") }
        return texture
    }

    private static func readInterior(_ texture: MTLTexture) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: side * 4,
                from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        }
        // The oversized Sprite and oracle triangle both cover this frozen
        // interior. Direct getBytes uses the actual tightly packed row stride.
        return (4..<12).flatMap { y in (4..<12).flatMap { x -> [Int] in
            let index = (y * side + x) * 4
            return [Int(bytes[index + 2]), Int(bytes[index + 1]),
                    Int(bytes[index]), Int(bytes[index + 3])]
        } }
    }

    private static func draw(
        device: MTLDevice, queue: MTLCommandQueue,
        pipeline: SceneParticleMetalPipeline, reference: MTLRenderPipelineState,
        disabledDepth: MTLDepthStencilState, textureAlpha: UInt8, particleAlpha: Float,
        mode: SceneParticlePipelineBlendMode, depth: Bool,
        attemptsUnpreparedCoverage: Bool = false
    ) throws -> [String: Any] {
        let actual = try target(device: device)
        let expected = try target(device: device)
        var depthTexture: MTLTexture?
        if depth {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: side, height: side, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = .renderTarget
            guard let texture = device.makeTexture(descriptor: descriptor)
            else { throw failure("depth-target") }
            depthTexture = texture
        }
        guard let command = queue.makeCommandBuffer() else { throw failure("command-buffer") }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [.init(
            position: SIMD3(0, 0, 0.5), size: 8, rotation: .zero,
            color: particleRGB, alpha: particleAlpha)])
        else { throw failure("instance-buffer") }
        let texture = try sourceTexture(device: device, alpha: textureAlpha)
        var encoded = false
        var unpreparedCoverageEncoded = false
        for (output, isReference) in [(actual, false), (expected, true)] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(
                16.0 / 255, 24.0 / 255, 40.0 / 255, 102.0 / 255)
            if depth {
                pass.depthAttachment.texture = depthTexture
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.storeAction = .dontCare
                pass.depthAttachment.clearDepth = 1
            }
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass)
            else { throw failure("render-encoder") }
            if isReference {
                let alpha = Float(textureAlpha) / 255 * particleAlpha
                let rgb = textureRGB * particleRGB * overbright
                var color = mode == .alphaToCoverage
                    ? SIMD4<Float>(rgb, alpha) : SIMD4<Float>(rgb * alpha, alpha)
                encoder.setRenderPipelineState(reference)
                if depth { encoder.setDepthStencilState(disabledDepth) }
                encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            } else {
                let uniforms = SceneParticleLayerUniforms(
                    viewProjection: SceneMatrix.identity(), layerModel: SceneMatrix.identity(),
                    basis: .init(right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0)),
                    viewportSize: SIMD2(repeating: Float(side)))
                if attemptsUnpreparedCoverage {
                    unpreparedCoverageEncoded = pipeline.draw(
                        texture: texture, instances: instances, uniforms: uniforms,
                        renderState: .init(blendMode: .alphaToCoverage, cullMode: .none,
                                           overbright: overbright),
                        colorSampling: .directImageFallback, usesDepthAttachment: depth,
                        encoder: encoder)
                }
                encoded = pipeline.draw(
                    texture: texture, instances: instances, uniforms: uniforms,
                    renderState: .init(blendMode: mode, cullMode: .none, overbright: overbright),
                    colorSampling: .directImageFallback, usesDepthAttachment: depth,
                    encoder: encoder)
            }
            encoder.endEncoding()
        }
        guard instances.markSubmitted(on: command),
              SceneParticleOffscreenReadbackHarness.commitAndWait(command)
        else { throw command.error ?? failure("gpu-completion") }
        let pixels = readInterior(actual)
        let oracle = readInterior(expected)
        return ["mode": mode.rawValue, "textureAlpha": Int(textureAlpha),
                "particleAlpha": particleAlpha, "depth": depth,
                "encoded": encoded, "completed": command.status == .completed,
                "unpreparedCoverageAttempted": attemptsUnpreparedCoverage,
                "unpreparedCoverageEncoded": unpreparedCoverageEncoded,
                "actual": pixels, "reference": oracle,
                "maximumByteError": zip(pixels, oracle).map { abs($0 - $1) }.max() ?? 255]
    }

    private static func failure(_ stage: String) -> NSError {
        NSError(domain: "SceneParticleCoverageRenderingHarness.\(stage)", code: 1)
    }
}
