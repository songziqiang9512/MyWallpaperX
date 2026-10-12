import Foundation
import Metal
import simd

// Prepared inputs only. The renderer, projection, capture, pass and shader are
// production code. The reference supplies the same quad as custom geometry,
// which deliberately retains the original full-background capture contract.
struct SceneRenderDescriptor {
    struct Layer { let id: Int; let colorBlendMode: Int? }
}
struct SceneGeometryProduct {
    typealias AuxiliaryRetainer = (@escaping () -> Void) -> Void
    typealias ColorBlendBinder = (MTLRenderCommandEncoder, MTLTexture, simd_float4x4) -> Void
    let prepare: ((MTLCommandBuffer, SIMD2<Int>, simd_float4x4, AuxiliaryRetainer) -> Void)? = nil
    let encode: (MTLRenderCommandEncoder, MTLTexture, MTLTexture?, simd_float4x4,
                 SceneLayerFragmentUniforms, ColorBlendBinder?) -> Bool
}
final class SceneGraphRenderTargetResidencyPin { func release() { fatalError("unused pin") } }

@main enum BlendCaptureProbe {
    struct Vector { let name: String; let mvp: simd_float4x4; let fallback: Bool }
    struct Frame { let pixels: [UInt8]; let copies: UInt64; let bytes: UInt64; let capacity: Int }
    static let quad = [
        SceneQuadVertex(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        SceneQuadVertex(position: SIMD2(0.5, -0.5), texcoord: SIMD2(1, 1)),
        SceneQuadVertex(position: SIMD2(-0.5, 0.5), texcoord: SIMD2(0, 0)),
        SceneQuadVertex(position: SIMD2(0.5, 0.5), texcoord: SIMD2(1, 0))]

    static func transformed(_ sx: Float, _ sy: Float, _ tx: Float, _ ty: Float,
                            angle: Float = 0) -> simd_float4x4 {
        let c = cos(angle), s = sin(angle)
        return simd_float4x4(columns: (SIMD4(c * sx, s * sx, 0, 0),
            SIMD4(-s * sy, c * sy, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(tx, ty, 0.4, 1)))
    }

    static func vectors() -> [Vector] {
        var result: [Vector] = []
        func add(_ name: String, _ mvp: simd_float4x4, fallback: Bool = false) {
            result.append(Vector(name: name, mvp: mvp, fallback: fallback))
        }
        add("fractional", transformed(0.63, 0.71, -0.19, 0.23))
        add("rotated", transformed(0.77, 0.43, 0.37, -0.21, angle: 0.73))
        add("negative-scale", transformed(-0.63, 0.71, 0.19, 0.23))
        add("y-flip", transformed(0.63, -0.71, -0.19, -0.23))
        add("clipped-left", transformed(1.1, 0.83, -0.89, 0.11, angle: 0.29))
        add("clipped-corner", transformed(0.93, 0.91, 0.92, 0.82, angle: 0.49))
        add("full-viewport", transformed(3, 3, 0, 0))
        var cursor = transformed(0.81, 0.61, 0, 0)
        cursor.columns.3.x += 0.29; cursor.columns.3.y -= 0.17
        add("final-cursor-mvp", cursor)
        var perspective = transformed(0.73, 0.87, -0.21, 0.24)
        perspective.columns.0.w = 0.33; perspective.columns.1.w = -0.27
        add("perspective", perspective)
        // Equivalent construction, with unrelated variable/resource identities.
        let renamedBasis = transformed(0.63, 0.71, 0, 0)
        var renamedOffset = matrix_identity_float4x4
        renamedOffset.columns.3 = SIMD4(-0.19, 0.23, 0, 1)
        add("renamed-equivalent-matrix", renamedOffset * renamedBasis)
        // Float viewport intersections can lose the outside half of an
        // enormous but finite quad through cancellation. Real rasterization
        // still needs the entire visible strip's current background.
        add("giant-positive-x", transformed(1e30, 0.5, 0, 0))
        add("giant-negative-x", transformed(-1e30, 0.5, 0.37, 0.13))
        add("giant-positive-y", transformed(0.5, 1e30, 0, 0))
        add("giant-negative-y", transformed(0.5, -1e30, -0.19, -0.23))
        add("wide-finite-neighbor", transformed(8, 0.5, -0.11, 0.17))
        add("tall-finite-neighbor", transformed(-0.5, 8, 0.13, -0.19))
        add("large-positive-boundary", transformed(1e7, 0.5, 0.17, 0.31))
        add("large-negative-boundary", transformed(-3e7, 0.5, -0.13, -0.19))
        var near = transformed(0.83, 0.79, 0.05, -0.09)
        near.columns.0.z = 1.4; near.columns.3.z = 0.1
        add("near-plane-crossing", near, fallback: true)
        var far = near; far.columns.3.z = 1.1
        add("far-plane-crossing", far, fallback: true)
        var unsafeW = transformed(0.41, 0.57, 0.13, -0.07)
        unsafeW.columns.3.w = 0.000_000_5
        add("unproven-w", unsafeW, fallback: true)
        var invalid = transformed(0.5, 0.5, 0, 0)
        invalid.columns.0.x = .infinity
        add("nonfinite", invalid, fallback: true)
        add("empty-offscreen", transformed(0.5, 0.5, 4, 4), fallback: true)
        return result
    }

    static func target(_ d: MTLDevice, width: Int, height: Int, format: MTLPixelFormat,
                       seed: Int) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
            width: width, height: height, mipmapped: false)
        desc.storageMode = .shared; desc.usage = [.renderTarget, .shaderRead]
        let texture = d.makeTexture(descriptor: desc)!
        texture.label = "background-\(seed)-\(width)-\(height)"
        if format == .bgra8Unorm {
            let data = (0..<(width * height)).flatMap { i -> [UInt8] in
                [UInt8((i * 37 + seed * 13) % 251), UInt8((i * 11 + seed * 31) % 241),
                 UInt8((i * 7 + seed * 17) % 239), UInt8(127 + (i + seed) % 129)]
            }
            data.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        } else {
            let data = (0..<(width * height)).flatMap { i -> [Float16] in
                [Float16(Float((i * 37 + seed * 13) % 251) / 97),
                 Float16(Float((i * 11 + seed * 31) % 241) / 103),
                 Float16(Float((i * 7 + seed * 17) % 239) / 109),
                 Float16(Float(127 + (i + seed) % 129) / 255)]
            }
            data.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 8) }
        }
        return texture
    }

    static func source(_ d: MTLDevice, alpha: Float, seed: Int) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
            width: 7, height: 5, mipmapped: false)
        desc.storageMode = .shared; desc.usage = .shaderRead
        let texture = d.makeTexture(descriptor: desc)!
        texture.label = "renamed-source-\(seed)"
        let data = (0..<35).flatMap { i -> [Float16] in
            [Float16(Float((i + seed) % 7) / 8), Float16(Float((i * 3 + seed) % 11) / 12),
             Float16(Float((i * 5 + seed) % 13) / 14), Float16(alpha)] }
        data.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, 7, 5),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 7 * 8) }
        return texture
    }

    static func pixels(_ target: MTLTexture) -> [UInt8] {
        let stride = target.pixelFormat == .rgba16Float ? 8 : 4
        var data = [UInt8](repeating: 0, count: target.width * target.height * stride)
        data.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: target.width * stride,
            from: MTLRegionMake2D(0, 0, target.width, target.height), mipmapLevel: 0) }
        return data
    }

    static func customQuad() -> SceneGeometryProduct {
        SceneGeometryProduct { encoder, texture, _, mvp, _, bind in
            guard let bind else { return false }
            var vertices = quad
            encoder.setVertexBytes(&vertices, length: vertices.count * MemoryLayout<SceneQuadVertex>.stride, index: 0)
            bind(encoder, texture, mvp)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            return true
        }
    }

    static func render(_ queue: MTLCommandQueue, target: MTLTexture, source: MTLTexture,
                       image: SceneImageLayerPipeline, blend: SceneLayerColorBlendPipeline,
                       matrices: [simd_float4x4], modes: [Int], full: Bool, seed: Int) -> Frame {
        let counters = ScenePerformanceCounterHub.shared.snapshot()
        let command = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: command, target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: false)
        let uniforms = SceneLayerFragmentUniforms(time: 0, alpha: 0,
            dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: SIMD2(0.8, 0.2),
            sourceSampling: SIMD2(0, 1), tint: SIMD4(repeating: 1),
            textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
        for index in matrices.indices {
            precondition(SceneLayerColorBlendRenderer.draw(texture: source, mvp: matrices[index],
                uniforms: uniforms, dependencyTexture: nil,
                layer: .init(id: seed + index, colorBlendMode: modes[index]), pipeline: image,
                colorBlendPipeline: blend, geometryProduct: full ? customQuad() : nil, mainPass: pass))
        }
        precondition(pass.finishEnsuringClear()); command.commit(); command.waitUntilCompleted()
        precondition(command.status == .completed && command.error == nil)
        let after = ScenePerformanceCounterHub.shared.snapshot()
        return Frame(pixels: pixels(target), copies: (after[.framebufferCaptures] ?? 0) - (counters[.framebufferCaptures] ?? 0),
            bytes: (after[.framebufferCaptureBytes] ?? 0) - (counters[.framebufferCaptureBytes] ?? 0),
            capacity: blend.renderTargetResidentByteCost)
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}"); return
        }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let fog = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        var rows: [[String: Any]] = []
        for format in [MTLPixelFormat.bgra8Unorm, .rgba16Float] {
            let image = SceneImageLayerPipeline(device: device, pixelFormat: format, library: library)!
            let state = SceneLayerColorBlendPipelineState(device: device, pixelFormat: format, fogShaderSource: fog)!
            let localized = SceneLayerColorBlendPipeline(device: device, state: state)
            let reference = SceneLayerColorBlendPipeline(device: device, state: state)
            for (index, vector) in vectors().enumerated() {
                for mode in 1...19 {
                    let seed = 61 + index * 101 + mode
                    let layer = source(device, alpha: mode == 5 || mode == 10 ? 0 : 0.625, seed: seed)
                    let a = target(device, width: 67, height: 43, format: format, seed: seed)
                    let b = target(device, width: 67, height: 43, format: format, seed: seed)
                    let original = pixels(a)
                    let roi = render(queue, target: a, source: layer, image: image, blend: localized,
                        matrices: [vector.mvp], modes: [mode], full: false, seed: seed)
                    let full = render(queue, target: b, source: layer, image: image, blend: reference,
                        matrices: [vector.mvp], modes: [mode], full: true, seed: seed)
                    let region = SceneLayerSourcePassthroughPlan.projectedGeometry(for: vector.mvp)?
                        .pixelRegion(width: a.width, height: a.height)
                        ?? MTLRegionMake2D(0, 0, a.width, a.height)
                    rows.append(["name": vector.name, "mode": mode, "hdr": format == .rgba16Float,
                        "equal": roi.pixels == full.pixels, "changed": roi.pixels != original,
                        "referenceChanged": full.pixels != original,
                        "region": [region.origin.x, region.origin.y, region.size.width, region.size.height],
                        "copies": roi.copies, "bytes": roi.bytes, "fullBytes": full.bytes,
                        "referenceFullCapture": full.bytes == UInt64(full.capacity) * full.copies,
                        "capacityEqual": roi.capacity == full.capacity, "fallback": vector.fallback])
                }
            }
            // One owner across consecutive blends, a changed next-frame
            // background and a resized target. Each read sees fresh content.
            for (frame, dimensions) in [(67, 43), (67, 43), (79, 51)].enumerated() {
                let seed = 911 + frame * 137
                let layer = source(device, alpha: 0.625, seed: seed)
                let a = target(device, width: dimensions.0, height: dimensions.1, format: format, seed: seed)
                let b = target(device, width: dimensions.0, height: dimensions.1, format: format, seed: seed)
                let moves = [transformed(0.67, 0.71, -0.29 + Float(frame) * 0.19, 0.31),
                             transformed(0.53, -0.77, 0.23, -0.17 - Float(frame) * 0.11, angle: 0.43)]
                let roi = render(queue, target: a, source: layer, image: image, blend: localized,
                    matrices: moves, modes: [7, 12], full: false, seed: seed)
                let full = render(queue, target: b, source: layer, image: image, blend: reference,
                    matrices: moves, modes: [7, 12], full: true, seed: seed)
                rows.append(["name": "consecutive-frame-\(frame)", "mode": 7, "hdr": format == .rgba16Float,
                    "equal": roi.pixels == full.pixels, "copies": roi.copies, "bytes": roi.bytes,
                    "fullBytes": full.bytes, "capacityEqual": roi.capacity == full.capacity, "fallback": false])
            }
            // Ordinary source-over has no background consumer.
            let a = target(device, width: 19, height: 17, format: format, seed: 997)
            let layer = source(device, alpha: 0.625, seed: 997)
            let plain = render(queue, target: a, source: layer, image: image, blend: localized,
                matrices: [transformed(0.7, 0.9, 0, 0)], modes: [0], full: false, seed: 997)
            rows.append(["name": "source-over", "hdr": format == .rgba16Float,
                "copies": plain.copies, "bytes": plain.bytes])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": rows]), as: UTF8.self))
    }
}
