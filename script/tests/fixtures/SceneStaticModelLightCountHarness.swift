import Foundation
import Metal
import simd

/// The test fragment reports the uniforms uploaded by the real draw path.
@main enum StaticModelLightCountHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let pipeline = SceneStaticModelPipeline(device: device, colorPixelFormat: .rgba16Float)!
        let positions: [SIMD3<Float>] = [SIMD3(-1, -1, 0.5), SIMD3(3, -1, 0.5), SIMD3(-1, 3, 0.5)]
        let mesh = pipeline.makeMesh(vertices: positions.map {
            .init(position: $0, normal: SIMD3(0, 0, 1), tangent: SIMD4(1, 0, 0, 1), uv: .zero)
        }, indices: [0, 1, 2])!
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 8, height: 8, mipmapped: false)
        colorDescriptor.storageMode = .shared
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        let target = device.makeTexture(descriptor: colorDescriptor)!
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: 8, height: 8, mipmapped: false)
        depthDescriptor.storageMode = .private
        depthDescriptor.usage = .renderTarget
        let depth = device.makeTexture(descriptor: depthDescriptor)!
        var material = SceneStaticModelMaterial(
            color: SIMD3(repeating: 1), opacity: 1, receivesLighting: true,
            textureAlphaIsOpacity: false, textureAlphaIsTintMask: false,
            emissiveColor: .zero, emissiveBrightness: 0, brightness: 1,
            usesHDRBrightness: false, viewTint: nil)
        material.cullMode = .none
        var counts: [[Int]] = []
        for count in 0...4 {
            let points = (0..<count).map { index in
                SceneLightSnapshot.Point(position: SIMD3(Float(index), 0, 1),
                    color: SIMD3(repeating: 1), intensity: 1, radius: 10)
            } + [SceneLightSnapshot.Point(illuminatesStaticModels: false,
                position: SIMD3(0, 0, 1), color: SIMD3(repeating: 1), intensity: 1, radius: 10)]
            let lighting = SceneLightSnapshot(ambient: .zero, ambientNormalYSpaceSign: 1,
                directional: [], point: points, spot: [], overflowCount: 0)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .dontCare
            pass.depthAttachment.clearDepth = 0
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            precondition(pipeline.draw(mesh: mesh, texture: target, colorTextureIsPremultiplied: false,
                emissiveMask: nil, emissiveMaskTextureFrame: nil, emissiveMaskSampling: nil,
                modelMatrix: matrix_identity_float4x4, viewProjection: matrix_identity_float4x4,
                cameraPosition: SIMD3(0, 0, 1), textureFrame: .identity,
                sampling: .directImageFallback, layerAlpha: 1, material: material,
                lighting: lighting, writesDepth: false, encoder: encoder))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            precondition(command.status == .completed && command.error == nil)
            var pixel = [Float16](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes {
                target.getBytes($0.baseAddress!, bytesPerRow: 8,
                    from: MTLRegionMake2D(4, 4, 1, 1), mipmapLevel: 0)
            }
            precondition(pixel[3] == 1)
            counts.append(pixel.prefix(3).map { Int($0) })
        }
        let data = try JSONSerialization.data(withJSONObject: ["counts": counts], options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
