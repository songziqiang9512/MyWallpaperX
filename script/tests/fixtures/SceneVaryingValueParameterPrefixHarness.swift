import Foundation
import Metal

private struct SourcePair: Decodable {
    let vertex: String
    let fragment: String
}

private struct ActualContract: Decodable {
    let contract: SceneShaderContract
    let materialCombos: [String: Int]
    let compatibilityTarget: SceneShaderCompatibilityTarget?
    let textureReadiness: [Int: Bool]?
    let inactiveComboProviders: Set<String>?
}

private struct PixelInput: Decodable {
    let vertexMSL: String
    let fragmentMSL: String
    let vertexFunction: String
    let fragmentFunction: String
}

private struct UniformBufferInput: Decodable {
    let index: Int
    let values: [Float]
}

private struct UniformDrawInput: Decodable {
    let vertexBuffers: [UniformBufferInput]
    let fragmentBuffers: [UniformBufferInput]
}

private struct UniformSequenceInput: Decodable {
    let program: PixelInput
    let draws: [UniformDrawInput]
}

@main
private enum VaryingValueParameterPrefixHarness {
    private static func analyze(_ source: SourcePair) -> [String: Any] {
        let pair = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: source.vertex, fragment: source.fragment
        )
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: pair.vertex, fragmentSource: pair.fragment
        )
        let runtimeVertex = SceneGenericShaderRuntimeConstantNormalizer.rewrite(
            pair.vertex, stage: .vertex
        )
        let runtimeFragment = SceneGenericShaderRuntimeConstantNormalizer.rewrite(
            pair.fragment, stage: .fragment
        )
        var result: [String: Any] = [
            "canonicalVertex": pair.vertex,
            "canonicalFragment": pair.fragment,
            "boundedDiagnosticCodes": bounded.diagnostics.map { $0.code.rawValue },
            "runtimeConstantVertex": runtimeVertex,
            "runtimeConstantFragment": runtimeFragment,
            "runtimeConstantIdempotent": runtimeVertex == SceneGenericShaderRuntimeConstantNormalizer.rewrite(
                runtimeVertex, stage: .vertex
            ) && runtimeFragment == SceneGenericShaderRuntimeConstantNormalizer.rewrite(
                runtimeFragment, stage: .fragment
            ),
            "idempotent": pair == SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: pair.vertex, fragment: pair.fragment
            )
        ]
        if let program = bounded.program {
            result["boundedMSL"] = program.metalSource
            result["boundedVertexFunction"] = program.vertexFunctionName
            result["boundedFragmentFunction"] = program.fragmentFunctionName
            result["boundedUniformBufferIndex"] = program.uniformBufferIndex
            result["boundedUniformByteSize"] = program.uniformLayout.byteSize
            result["boundedUniformFields"] = program.uniformLayout.fields.map { field in
                ["name": field.authoredName, "type": field.type.rawValue,
                 "offset": field.offset] as [String: Any]
            }
        }
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: pair.vertex, fragmentSource: pair.fragment,
            maximumStageSourceBytes: 128 * 1_024
        ) {
        case let .success(normalized):
            result["normalizedVertex"] = normalized.vertex
            result["normalizedFragment"] = normalized.fragment
        case let .failure(failure):
            result["normalizerFailure"] = String(describing: failure)
        }
        return result
    }

    private static func actual(_ path: String) throws -> [String: Any] {
        let input = try JSONDecoder().decode(ActualContract.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard let graph = input.contract.sourceGraph else {
            throw NSError(domain: "missing-actual-source-graph", code: 1)
        }
        let target = input.compatibilityTarget ?? .unprofiledMetal
        var prepared: [String: String] = [:]
        for kind in [SceneShaderContract.StageKind.vertex, .fragment] {
            guard let stage = input.contract.stages.first(where: { $0.kind == kind }) else {
                throw NSError(domain: "missing-actual-stage", code: 1)
            }
            let environment = try SceneShaderVariantResolver.resolve(
                stage: kind, stages: input.contract.stages,
                compatibilityTarget: target, explicitCombos: input.materialCombos,
                inactiveComboProviders: input.inactiveComboProviders ?? [],
                textureReadiness: input.textureReadiness ?? [:]
            ).get()
            let value = try SceneShaderPreprocessor().preprocess(
                rootRelativePath: stage.relativePath, graph: graph, environment: environment
            ).get()
            prepared[kind.rawValue] = value.source
        }
        guard let vertex = prepared["vertex"], let fragment = prepared["fragment"] else {
            throw NSError(domain: "missing-prepared-pair", code: 1)
        }
        var result = analyze(.init(vertex: vertex, fragment: fragment))
        result["preprocessedVertex"] = vertex
        result["preprocessedFragment"] = fragment
        result["compatibilityTarget"] = target.rawValue
        result["stage"] = "actual-contract-variant-preprocessor-before-shared-proof"
        return result
    }

    private static func render(
        _ input: PixelInput, draws: [UniformDrawInput]? = nil
    ) throws -> [[Float]] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw NSError(domain: "metal-unavailable", code: 1)
        }
        let vertex = try device.makeLibrary(source: input.vertexMSL, options: nil)
        let fragment = try device.makeLibrary(source: input.fragmentMSL, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex.makeFunction(name: input.vertexFunction)
        descriptor.fragmentFunction = fragment.makeFunction(name: input.fragmentFunction)
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 2, height: 2, mipmapped: false
        )
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = .renderTarget
        let draws = draws ?? [.init(vertexBuffers: [], fragmentBuffers: [])]
        guard (1...8).contains(draws.count) else {
            throw NSError(domain: "uniform-draw-limit", code: 1)
        }
        var result: [[Float]] = []
        for draw in draws {
            guard let texture = device.makeTexture(descriptor: textureDescriptor),
                  let command = queue.makeCommandBuffer() else {
                throw NSError(domain: "metal-allocation", code: 1)
            }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                throw NSError(domain: "metal-encoder", code: 1)
            }
            encoder.setRenderPipelineState(pipeline)
            var resolution = SIMD2<Float>(2, 2)
            for index in [0, 8] {
                encoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: index)
                encoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: index)
            }
            for (buffers, vertexStage) in [(draw.vertexBuffers, true), (draw.fragmentBuffers, false)] {
                for buffer in buffers {
                    guard (0..<31).contains(buffer.index), (1...1_024).contains(buffer.values.count),
                          buffer.values.allSatisfy({ $0.isFinite }) else {
                        throw NSError(domain: "uniform-buffer-input", code: 1)
                    }
                    buffer.values.withUnsafeBytes {
                        if vertexStage {
                            encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: buffer.index)
                        } else {
                            encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: buffer.index)
                        }
                    }
                }
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else {
                throw NSError(domain: "metal-command-failed", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: String(describing: command.error)])
            }
            var pixels = [Float](repeating: 0, count: 16)
            pixels.withUnsafeMutableBytes {
                texture.getBytes($0.baseAddress!, bytesPerRow: 32,
                                 from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
            }
            result.append(pixels)
        }
        return result
    }

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "expected-mode-and-json", code: 1)
        }
        let path = CommandLine.arguments[2]
        let result: Any
        switch CommandLine.arguments[1] {
        case "--actual-contract": result = try actual(path)
        case "--analyze":
            let input = try JSONDecoder().decode(SourcePair.self,
                from: Data(contentsOf: URL(fileURLWithPath: path)))
            result = analyze(input)
        case "--render":
            let input = try JSONDecoder().decode(PixelInput.self,
                from: Data(contentsOf: URL(fileURLWithPath: path)))
            result = try render(input)[0]
        case "--render-uniform-sequence":
            let input = try JSONDecoder().decode(UniformSequenceInput.self,
                from: Data(contentsOf: URL(fileURLWithPath: path)))
            result = try render(input.program, draws: input.draws)
        default: throw NSError(domain: "unknown-mode", code: 1)
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
