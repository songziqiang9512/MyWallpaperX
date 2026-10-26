import Foundation
import Metal

/// Actual bounded and external-compiler Metal pixels share one input fixture.
enum SceneGenericShaderTypedInputGPUCases {
    static func run(
        bounded: SceneAuthoredShaderProgram,
        generic: SceneGenericShaderProgramArtifact.Program,
        signalPassthrough: Bool = false
    ) throws -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            return ["metalAvailable": false]
        }
        func texture(_ value: [Float]) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: 1, height: 1, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .renderTarget]
            let result = device.makeTexture(descriptor: descriptor)!
            var bytes = value.map(Float16.init)
            bytes.withUnsafeMutableBytes { result.replace(region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
            return result
        }
        var cases: [[String: Any]] = []
        for isGeneric in [false, true] {
            let source = isGeneric ? generic.metalSource : bounded.metalSource
            let library = try device.makeLibrary(source: source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name:
                isGeneric ? generic.vertexFunctionName : bounded.vertexFunctionName)
            descriptor.fragmentFunction = library.makeFunction(name:
                isGeneric ? generic.fragmentFunctionName : bounded.fragmentFunctionName)
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            if isGeneric {
                let vertex = MTLVertexDescriptor()
                vertex.attributes[0].format = .float3
                vertex.attributes[0].offset = 0
                vertex.attributes[0].bufferIndex = 16
                vertex.attributes[1].format = .float2
                vertex.attributes[1].offset = 12
                vertex.attributes[1].bufferIndex = 16
                vertex.layouts[16].stride = 20
                descriptor.vertexDescriptor = vertex
            }
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let uniformIndex = isGeneric ? generic.uniformBufferIndex : bounded.uniformBufferIndex
            let byteSize = isGeneric ? generic.uniformLayout.byteSize : bounded.uniformLayout.byteSize
            let maskOffset = isGeneric
                ? generic.uniformLayout.fields.first(where: { $0.name == SceneShaderColorBoundary.uniformName })!.offset
                : bounded.uniformLayout.fields.first(where: { $0.name == SceneShaderColorBoundary.uniformName })!.offset
            let probes: [(UInt32, [Float], [Float])] = signalPassthrough ? [
                (0, [2, 0.6, 0.25, 0.5], [2, 0.6, 0.25, 0.5]),
                (1, [1, 0.3, 0.125, 0.5], [2, 0.6, 0.25, 0.5]),
                (0, [2, 0.6, 0.25, 0], [2, 0.6, 0.25, 0]),
                (1, [0, 0, 0, 0], [0, 0, 0, 0]),
                (256, [2, 0.6, 0.25, 2.5], [2, 0.6, 0.25, 2.5]),
                (256, [2, 0.6, 0.25, -0.25], [2, 0.6, 0.25, -0.25]),
                (512, [2, 0.6, 0.25, 2.5], [2, 0.6, 0.25, 1]),
            ] : [
                (UInt32(2), [Float(2), 0.6, 0.25, 0.5], [Float(1), 0.3, 0.125, 0.5]),
                (UInt32(3), [Float(1), 0.3, 0.125, 0.5], [Float(1), 0.3, 0.125, 0.5]),
                (UInt32(2), [Float(2), 0.6, 0.25, 0], [Float(1), 0.3, 0.125, 0.5]),
                (UInt32(3), [Float(0), 0, 0, 0], [Float(0), 0, 0, 0.5])
            ]
            // Reuse each pipeline while switching only typed frame bytes.
            for (mask, value, authoredExpected) in probes {
                let pmaOutput = bounded.colorBoundary?.outputRepresentation == .premultipliedAlpha
                let expected = signalPassthrough && pmaOutput && mask != 256
                    ? [authoredExpected[0] * authoredExpected[3], authoredExpected[1] * authoredExpected[3],
                       authoredExpected[2] * authoredExpected[3], authoredExpected[3]] : authoredExpected
                let input = texture(value)
                let data = texture([0.5, 0, 0, 0.25])
                let output = texture([0, 0, 0, 0])
                var bytes = [UInt8](repeating: 0, count: byteSize)
                withUnsafeBytes(of: mask) { bytes.replaceSubrange(maskOffset..<(maskOffset + 4), with: $0) }
                for (name, value) in [
                    ("mwxVertexCoordinates01", SIMD4<Float>(0, 1, 1, 1)),
                    ("mwxVertexCoordinates23", SIMD4<Float>(0, 0, 1, 0))
                ] where !isGeneric {
                    let offset = bounded.uniformLayout.fields.first { $0.name == name }!.offset
                    withUnsafeBytes(of: value) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
                }
                let command = queue.makeCommandBuffer()!
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = output
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
                encoder.setRenderPipelineState(pipeline)
                bytes.withUnsafeBytes {
                    encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: uniformIndex)
                    encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: uniformIndex)
                }
                var positions: [Float] = [-1, -1, 0, 0.5, 0.5, 1, -1, 0, 0.5, 0.5,
                                         -1, 1, 0, 0.5, 0.5, 1, 1, 0, 0.5, 0.5]
                if isGeneric { encoder.setVertexBytes(&positions, length: positions.count * 4, index: 16) }
                let sampler = device.makeSamplerState(descriptor: MTLSamplerDescriptor())!
                for (slot, sourceTexture) in [input, data].enumerated() {
                    encoder.setVertexTexture(sourceTexture, index: slot)
                    encoder.setVertexSamplerState(sampler, index: slot)
                    encoder.setFragmentTexture(sourceTexture, index: slot)
                    encoder.setFragmentSamplerState(sampler, index: slot)
                }
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                var pixel = [Float16](repeating: 0, count: 4)
                pixel.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 8,
                    from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0) }
                cases.append(["generic": isGeneric, "mask": mask, "uniformIndex": uniformIndex,
                    "completed": command.status == .completed, "actual": pixel.map(Float.init),
                    "expected": expected])
            }
        }
        return ["metalAvailable": true, "cases": cases]
    }
}
