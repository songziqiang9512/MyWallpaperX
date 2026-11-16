import Foundation
import Metal
import simd

struct FilterUniforms {
    var transform: simd_float4x4 = matrix_identity_float4x4
    var positionRadius = SIMD4<Float>(0, 0, 0, 2)
    var parameters = SIMD4<Float>(1, 0, 0, 0)
    var identity = SIMD4<UInt32>(0, 0, 1, 0)
}

@main enum SceneShadowFilterChecks {
    static func main() throws {
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: "default.metallib"))
        let pipeline = try device.makeComputePipelineState(
            function: library.makeFunction(name: "shadowFilterProbe")!)
        let uniforms = [FilterUniforms(), FilterUniforms(), FilterUniforms()]
        let uniformBuffer = device.makeBuffer(bytes: uniforms,
            length: MemoryLayout<FilterUniforms>.stride * uniforms.count)!
        var rows: [[String: Any]] = []
        for item in input {
            let size = item["size"] as! Int
            let depths = (item["depths"] as! [Double]).map(Float.init)
            let points = (item["points"] as! [[Double]]).map {
                SIMD4<Float>(Float($0[0]), Float($0[1]), 0, 0)
            }
            let pointBuffer = device.makeBuffer(bytes: points,
                length: MemoryLayout<SIMD4<Float>>.stride * points.count)!
            let commandBuffer = queue.makeCommandBuffer()!
            func makeMap(width: Int, height: Int) -> MTLTexture {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                    width: width, height: height, mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = .shaderRead
                let texture = device.makeTexture(descriptor: descriptor)!
                let stride = (width * MemoryLayout<Float>.stride + 255) & ~255
                let upload = device.makeBuffer(length: stride * height, options: .storageModeShared)!
                for y in 0..<height {
                    for x in 0..<width {
                        upload.contents().advanced(by: y * stride + x * MemoryLayout<Float>.stride)
                            .storeBytes(of: depths[(y % size) * size + x % size], as: Float.self)
                    }
                }
                let blit = commandBuffer.makeBlitCommandEncoder()!
                blit.copy(from: upload, sourceOffset: 0, sourceBytesPerRow: stride,
                    sourceBytesPerImage: stride * height,
                    sourceSize: .init(width: width, height: height, depth: 1), to: texture,
                    destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
                blit.endEncoding()
                return texture
            }
            let depth = makeMap(width: size, height: size)
            let atlas = makeMap(width: size * 3, height: size * 2)
            let output = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * points.count,
                options: .storageModeShared)!
            let encoder = commandBuffer.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(pointBuffer, offset: 0, index: 0)
            encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setBuffer(output, offset: 0, index: 2)
            encoder.setTexture(depth, index: 0)
            encoder.setTexture(atlas, index: 1)
            encoder.dispatchThreads(.init(width: points.count, height: 1, depth: 1),
                threadsPerThreadgroup: .init(width: 1, height: 1, depth: 1))
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: points.count)
            rows.append(["pattern": item["name"]!, "size": size,
                "completed": commandBuffer.status == .completed && commandBuffer.error == nil,
                "values": (0..<points.count).map {
                    [pointer[$0].x, pointer[$0].y, pointer[$0].z, pointer[$0].w]
                }])
        }
        print(String(data: try JSONSerialization.data(withJSONObject: ["rows": rows]), encoding: .utf8)!)
    }
}
