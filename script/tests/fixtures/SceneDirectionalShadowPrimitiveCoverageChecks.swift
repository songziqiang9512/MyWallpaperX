import Foundation
import Metal
import simd

@main enum SceneDirectionalShadowPrimitiveCoverageChecks {
    struct Input: Decodable {
        let name: String
        let positions: [[Double]]
        let indices: [UInt32]
        let materialPath: String
        let worldShift: [Float]?
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        guard device.supportsShaderBarycentricCoordinates else {
            print("{\"supportsBarycentric\":false}")
            return
        }
        let inputs = try JSONDecoder().decode([Input].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let pipeline = SceneStaticModelPipeline(device: device, colorPixelFormat: .rgba16Float)!
        let albedoDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false)
        albedoDescriptor.storageMode = .shared
        albedoDescriptor.usage = .shaderRead
        let albedo = device.makeTexture(descriptor: albedoDescriptor)!
        var white: [Float] = [1, 1, 1, 1]
        white.withUnsafeMutableBytes {
            albedo.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 16)
        }
        var material = SceneStaticModelMaterial(color: SIMD3(repeating: 1), opacity: 1,
            receivesLighting: true, textureAlphaIsOpacity: false, textureAlphaIsTintMask: false,
            emissiveColor: .zero, emissiveBrightness: 1, brightness: 1,
            usesHDRBrightness: false, viewTint: nil)
        material.cullMode = .none
        var rows: [[String: Any]] = []
        for input in inputs {
            let vertices = input.positions.map { p in
                SceneMdlStaticModel.Vertex(
                    position: SIMD3(Float(p[0] / 8 - 1), Float(1 - p[1] / 8), Float(p[2])),
                    normal: SIMD3(0, 0, 1), tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(0.5, 0.5))
            }
            let base = SceneStaticModelFixture.model(vertices: vertices, indices: input.indices)
            let model = SceneMdlStaticModel(version: base.version, headerFormat: base.headerFormat,
                vertexFormat: base.vertexFormat, vertexStride: base.vertexStride,
                indexElementSize: base.indexElementSize, materialPath: input.materialPath,
                bounds: base.bounds, vertices: base.vertices, indices: base.indices)
            let mesh = pipeline.makeMesh(model: model)!
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: 16, height: 16, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            let map = device.makeTexture(descriptor: descriptor)!
            map.label = input.materialPath
            let commandBuffer = queue.makeCommandBuffer()!
            commandBuffer.label = input.name
            let pass = MTLRenderPassDescriptor()
            pass.depthAttachment.texture = map
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .store
            pass.depthAttachment.clearDepth = 1
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
            var world = matrix_identity_float4x4
            var clip = matrix_identity_float4x4
            if let shift = input.worldShift {
                world.columns.3 = SIMD4(shift[0], shift[1], shift[2], 1)
                clip.columns.3 = SIMD4(-shift[0], -shift[1], -shift[2], 1)
            }
            let projection = SceneDirectionalShadowProjection(
                worldToClip: clip, depthBias: 8 * Float.ulpOfOne)
            let encoded = pipeline.drawShadow(mesh: mesh, texture: albedo,
                textureFrame: .identity, sampling: SceneTextureSampling(texFlags: 3),
                modelMatrix: world, projection: .directional(projection), face: 0,
                viewport: MTLViewport(originX: 0, originY: 0, width: 16, height: 16,
                    znear: 0, zfar: 1), layerAlpha: 1, material: material, encoder: encoder)
            encoder.endEncoding()
            let buffer = device.makeBuffer(length: 256 * 16, options: .storageModeShared)!
            let blit = commandBuffer.makeBlitCommandEncoder()!
            blit.copy(from: map, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: 16, height: 16, depth: 1), to: buffer,
                destinationOffset: 0, destinationBytesPerRow: 256,
                destinationBytesPerImage: 256 * 16)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            let values = buffer.contents().bindMemory(to: Float.self, capacity: 64 * 16)
            var depths: [Float] = []
            for y in 0..<16 {
                for x in 0..<16 { depths.append(values[y * 64 + x]) }
            }
            rows.append(["name": input.name, "materialPath": model.materialPath,
                "encoded": encoded,
                "completed": commandBuffer.status == .completed && commandBuffer.error == nil,
                "depth": depths])
        }
        let result: [String: Any] = ["device": device.name,
            "supportsBarycentric": true, "rows": rows]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
