import Foundation
import Metal
import simd

extension BlendCaptureProbe {
    static func ordinaryMultisample(_ device: MTLDevice, _ queue: MTLCommandQueue,
                                    _ library: MTLLibrary) -> [[String: Any]] {
        let width = 53, height = 41
        let outline = transformed(1.19, 0.89, -0.14, 0.18, angle: 0.47)
        let viewport = transformed(2, 2, 0, 0)
        func coverage(_ mvp: simd_float4x4) -> Bool {
            SceneLayerSourcePassthroughPlan.projectedGeometry(for: mvp)?
                .cutsPixelCoverage(width: width, height: height) == true
        }
        let gridSize = SIMD2(Float(width), Float(height))
        let aligned = transformed(24 / gridSize.x, 20 / gridSize.y, 0, 0)
        let centeredOnPixelBoundaries = transformed(
            aligned.columns.0.x, aligned.columns.1.y, 1 / gridSize.x, 1 / gridSize.y)
        let eligibility = [
            "rotated": coverage(outline),
            "fullViewport": coverage(viewport),
            "integerEdges": coverage(centeredOnPixelBoundaries),
            "fractionalEdges": coverage(aligned),
            "clipped": coverage(transformed(1.2, 1.2, 0.96, 0.14, angle: 0.38)),
            "offscreen": coverage(transformed(0.5, 0.5, 3, 3)),
            "renamedMirroredQuad": coverage(transformed(-1.19, 0.89, -0.14, 0.18, angle: 0.47)),
        ]
        let corners = [SIMD2<Float>(-0.5, -0.5), SIMD2(0.5, -0.5),
                       SIMD2(0.5, 0.5), SIMD2(-0.5, 0.5)].map { point in
            let clip = outline * SIMD4(point.x, point.y, 0, 1)
            return [clip.x, clip.y]
        }
        func texture(width: Int, height: Int, rgba: [UInt8]) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .shaderRead
            let image = device.makeTexture(descriptor: descriptor)!
            rgba.withUnsafeBytes { bytes in
                image.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                              withBytes: bytes.baseAddress!, bytesPerRow: width * 4)
            }
            return image
        }

        let solid = texture(width: 1, height: 1, rgba: [255, 128, 0, 255])
        let mask = texture(width: 13, height: 11, rgba: (0..<143).flatMap { (index: Int) -> [UInt8] in
            let alpha = UInt8(index % 13 + index / 13 > 10 ? 0 : 255)
            return [alpha, 0, 0, alpha]
        })
        let uniforms = SceneLayerFragmentUniforms(time: 0, alpha: 1,
            dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
            sourceSampling: .zero, tint: SIMD4(repeating: 1),
            textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
        return [1, 2, 4].filter { $0 == 1 || device.supportsFamily(.apple1)
            && device.supportsTextureSampleCount($0) }.flatMap { samples -> [[String: Any]] in
            let pipeline = SceneImageLayerPipeline(device: device, library: library,
                rasterSampleCount: samples, preparesMultisampleSeed: false)!
            return [("quad", solid, outline), ("texture-alpha", mask, viewport)].map { kind, source, mvp in
                let output = target(device, width: width, height: height, format: .bgra8Unorm, seed: 17)
                let commandBuffer = queue.makeCommandBuffer()!
                let pass = SceneMainPassEncoder(commandBuffer: commandBuffer, target: output,
                    clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: true)
                let trace = SceneEffectExecutionTelemetry().makeFrame(frameIndex: UInt64(samples),
                    observesComposition: true)
                pass.compositionTrace = trace
                if samples > 1 {
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                        width: width, height: height, mipmapped: false)
                    descriptor.storageMode = .memoryless
                    descriptor.usage = .renderTarget
                    descriptor.textureType = .type2DMultisample
                    descriptor.sampleCount = samples
                    let color = device.makeTexture(descriptor: descriptor)!
                    descriptor.pixelFormat = .depth32Float
                    let depth = device.makeTexture(descriptor: descriptor)!
                    precondition(pass.prepareMultisampling(.init(color: color, depth: depth)!))
                }
                let layer = SceneRenderDescriptor.Layer(id: 792, colorBlendMode: 0,
                    contentKind: kind == "quad" ? "solid" : "image")
                precondition(SceneImageLayerMainPassRenderer.draw(texture: source, mvp: mvp,
                    uniforms: uniforms, dependencyTexture: nil, layer: layer, pipeline: pipeline,
                    colorBlendPipeline: nil, mainPass: pass))
                precondition(pass.finishEnsuringClear())
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                let opens = trace.frozenCompositionObservation()?.rows.filter { $0.kind == "main-raster-open" } ?? []
                return ["kind": kind, "samples": samples, "width": width, "height": height,
                    "clipXY": corners, "resolvedBGRA": Data(pixels(output)).base64EncodedString(),
                    "encoderSamples": pass.submittedRasterSampleCount ?? 0, "opens": opens.count,
                    "colorStore": opens.first?.details?["colorStore"] ?? "",
                    "completed": commandBuffer.status == .completed,
                    "preparesSeed": pipeline.supportsMultisampleColorSeed, "coverage": eligibility]
            }
        }
    }
}
