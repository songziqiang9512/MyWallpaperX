// Self-authored attributes and transparent RTT probes; no official RGB claim.
import CoreGraphics
import Foundation
import Metal
import simd

private let unit: [SIMD2<Float>] = [.init(0, 0), .init(1, 0), .init(1, 1), .init(0, 1)]
private let extended: [SIMD2<Float>] = [
    .init(-0.25, -0.35), .init(1.25, -0.35), .init(1.25, 1.15), .init(-0.25, 1.15),
]
private let nonrectangular: [SIMD2<Float>] = [
    .init(-0.25, -0.2), .init(1.3, -0.35), .init(1.15, 1.2), .init(0.05, 0.95),
]
private let logicalHeight: Float = 100

private func failure(_ label: String, _ details: String = "") -> NSError {
    NSError(domain: "direct-draw-vertex-attributes", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(label): \(details)"])
}

private func capture(_ points: [SIMD2<Float>]) -> simd_float4x4 {
    let xs = points.map { logicalHeight * ($0.x - 0.5) }
    let ys = points.map { logicalHeight * (0.5 - $0.y) }
    let lo = SIMD2(xs.min()!, ys.min()!), hi = SIMD2(xs.max()!, ys.max()!)
    let extent = hi - lo
    return simd_float4x4(columns: (
        .init(2 / extent.x, 0, 0, 0), .init(0, 2 / extent.y, 0, 0),
        .init(0, 0, 1, 0), .init(-(hi.x + lo.x) / extent.x,
                                -(hi.y + lo.y) / extent.y, 0, 1)))
}

private func inputs(
    points: [SIMD2<Float>]?, size: Int, projection: simd_float4x4,
    logicalSize: Bool = true
) -> SceneAuthoredShaderUniformInputs {
#if MWX_DIRECT_DRAW_LEGACY_HOST
    return .init(frameIndex: 1, renderSize: .init(width: size, height: size),
        screenSize: .init(width: 1600, height: 900), modelViewProjection: projection,
        layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        sceneTime: 0, dayTime: 0, frameTime: 1 / 60,
        pointerCurrentNDC: .zero, pointerPreviousNDC: .zero)
#else
    // The default case deliberately omits both new arguments, exercising the
    // real initializer defaults rather than supplying a duplicate unit quad.
    if points == nil && !logicalSize {
        return .init(frameIndex: 1, renderSize: .init(width: size, height: size),
            screenSize: .init(width: 1600, height: 900), modelViewProjection: projection,
            layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            sceneTime: 0, dayTime: 0, frameTime: 1 / 60,
            pointerCurrentNDC: .zero, pointerPreviousNDC: .zero)
    }
    let p = points ?? unit
    return .init(frameIndex: 1, renderSize: .init(width: size, height: size),
        screenSize: .init(width: 1600, height: 900), modelViewProjection: projection,
        layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        sceneTime: 0, dayTime: 0, frameTime: 1 / 60,
        pointerCurrentNDC: .zero, pointerPreviousNDC: .zero,
        vertexCoordinates: .init(p0: p[0], p1: p[1], p2: p[2], p3: p[3]),
        vertexInputSize: logicalSize ? .init(width: CGFloat(logicalHeight),
                                           height: CGFloat(logicalHeight)) : nil)
#endif
}

private func host(_ name: String, type: SceneAuthoredShaderValueType,
                  inputs: SceneAuthoredShaderUniformInputs) -> Data? {
    let field = SceneAuthoredShaderUniformLayout.Field(name: name, type: type, offset: 0)
    guard let source = SceneResolvedMaterialUniformEncoder.hostUniform(
        field, activeTextureSlots: [], hasEffectContext: false) else { return nil }
    return SceneResolvedMaterialUniformEncoder.encodeHost(
        source, type: type, inputs: inputs, slots: Array(repeating: nil, count: 8))
}

private func floats(_ data: Data?) -> Any {
    guard let data else { return NSNull() }
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

private func storedOutputProbe() -> [String: Bool] {
    typealias Storage = SceneResolvedMaterialAttachmentStorage
    typealias Contract = SceneResolvedMaterialProgram.OutputContract
    func stored(_ contract: Contract, _ attachment: SceneResolvedMaterialAttachmentKind,
                partial: Bool = true) -> Storage.StoredOutput? {
#if MWX_DIRECT_DRAW_LEGACY_HOST
        return Storage.storedOutput(contract, attachmentStorage: attachment)
#else
        return Storage.storedOutput(contract, attachmentStorage: attachment,
                                    partialCoverage: partial)
#endif
    }
    func color(_ representation: SceneShaderColorRepresentation) -> Contract {
        .color(.init(framebufferInput: .resolved(.premultipliedAlpha),
                     fragmentOutput: .resolved(representation)))
    }
    let opaque = stored(color(.opaque), .color)
    return [
        "opaquePartialIsPMA": opaque?.colorRepresentation == .premultipliedAlpha
            && opaque?.content == .color(.resolved(.premultipliedAlpha)),
        "opaqueFullIsOpaque": stored(color(.opaque), .color, partial: false)?
            .colorRepresentation == .opaque,
        "straightUnchanged": stored(color(.straightAlpha), .color)?
            .colorRepresentation == .straightAlpha,
        "pmaUnchanged": stored(color(.premultipliedAlpha), .color)?
            .colorRepresentation == .premultipliedAlpha,
        "independentAlphaRejected": stored(color(.independentAlphaSignal), .color) == nil,
        "rgbaDataRejected": stored(.preservedRGBAUnorm, .preservedRGBAUnorm) == nil,
        "scalarDataRejected": stored(.scalarRedUnorm, .scalarRedUnorm) == nil,
        "vectorDataRejected": stored(.redGreenFloat16, .redGreenFloat16) == nil,
    ]
}

private func hostProbe() -> [String: Any] {
    let ordinary = inputs(points: nil, size: 96, projection: matrix_identity_float4x4,
                          logicalSize: false)
    let authored = inputs(points: nonrectangular, size: 48,
                          projection: matrix_identity_float4x4)
    return [
        "default01": floats(host("mwxVertexCoordinates01", type: .float4, inputs: ordinary)),
        "default23": floats(host("mwxVertexCoordinates23", type: .float4, inputs: ordinary)),
        "authored01": floats(host("mwxVertexCoordinates01", type: .float4, inputs: authored)),
        "authored23": floats(host("mwxVertexCoordinates23", type: .float4, inputs: authored)),
        "logicalSize": floats(host("mwxRenderSize", type: .float2, inputs: authored)),
        "ordinarySize": floats(host("mwxRenderSize", type: .float2, inputs: ordinary)),
        "wrongTypeRejected": host("mwxVertexCoordinates01", type: .float3,
                                  inputs: ordinary) == nil,
        "partialCoverageStorage": storedOutputProbe(),
    ]
}

private struct Sources {
    let vertex: String
    let fragment: String
}

private func sources(mode: String, renamed: Bool) -> Sources {
    let uv = renamed ? "chartCoordinate" : "v_TexCoord"
    let position = renamed ? "localWitness" : "v_Position"
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    uniform mat4 g_ModelViewProjectionMatrix;
    varying vec2 \(uv);
    varying vec2 \(position);
    void main() {
        \(uv) = \(renamed ? "a_TexCoord.xy + vec2(0.0)" : "a_TexCoord");
        \(position) = \(renamed ? "1.0 * a_Position.xy" : "a_Position.xy");
        gl_Position = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0);
    }
    """
    let expression: String
    switch mode {
    case "uv": expression = "vec4(\(uv), 0.25, 1.0)"
    case "position": expression = "vec4(\(position), 0.25, 1.0)"
    default: expression = "vec4(0.21875, 0.225, 0.25, 1.0)"
    }
    return .init(vertex: vertex, fragment: """
    varying vec2 \(uv);
    varying vec2 \(position);
    void main() { gl_FragColor = \(expression); }
    """)
}

private func compiled(
    _ sources: Sources, generic: Bool, bundle: Bundle, cache: URL
) throws -> SceneAuthoredShaderProgram {
    let output = SceneAuthoredShaderFrontend.compile(
        vertexSource: sources.vertex, fragmentSource: sources.fragment)
    guard let bounded = output.program else {
        throw failure("bounded-compile", String(describing: output.diagnostics))
    }
    guard generic else { return bounded }
    let key = SceneResolvedMaterialGenericShaderRequest.key(
        vertexSource: sources.vertex, fragmentSource: sources.fragment,
        outputSemantics: .color, expectedColorTransfer: nil, premultipliedColorInputSlots: [])
    let artifactURL: URL
    switch SceneGenericShaderCompiler.compile(requestKey: key, vertexSource: sources.vertex,
        fragmentSource: sources.fragment, cacheRoot: cache, bundle: bundle) {
    case let .success(url): artifactURL = url
    case let .failure(reason): throw failure("generic-compile", String(describing: reason))
    }
    let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self,
        from: Data(contentsOf: artifactURL))
    guard let program = artifact.makeProgram(expectedKey: key,
        expectedColorTransfer: bounded.colorTransfer,
        expectedFragmentOutputChannelUse: bounded.fragmentOutputChannelUse) else {
        throw failure("generic-artifact-admission")
    }
    return program
}

private func uniformData(_ program: SceneAuthoredShaderProgram,
                         inputs: SceneAuthoredShaderUniformInputs) throws -> Data {
    var data = Data(count: max(16, program.uniformLayout.byteSize))
    for field in program.uniformLayout.fields {
        guard let source = SceneResolvedMaterialUniformEncoder.hostUniform(
            field, activeTextureSlots: [], hasEffectContext: false),
              let value = SceneResolvedMaterialUniformEncoder.encodeHost(
            source, type: field.type, inputs: inputs, slots: Array(repeating: nil, count: 8)),
              value.count <= field.storageByteSize else {
            throw failure("host-binding", field.authoredName)
        }
        data.replaceSubrange(field.offset..<(field.offset + value.count), with: value)
    }
    return data
}

private func render(
    device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState,
    program: SceneAuthoredShaderProgram, points: [SIMD2<Float>]?, bounds: [SIMD2<Float>],
    size: Int
) throws -> [String: Any] {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba32Float, width: size, height: size, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    guard let texture = device.makeTexture(descriptor: descriptor),
          let command = queue.makeCommandBuffer() else { throw failure("allocation") }
    let frame = inputs(points: points, size: size, projection: capture(bounds))
    let bytes = try uniformData(program, inputs: frame)
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass),
          let buffer = bytes.withUnsafeBytes({ device.makeBuffer(
            bytes: $0.baseAddress!, length: $0.count) }) else { throw failure("encoder") }
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBuffer(buffer, offset: 0, index: program.uniformBufferIndex)
    encoder.setFragmentBuffer(buffer, offset: 0, index: program.uniformBufferIndex)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed && command.error == nil else {
        throw failure("GPU-completion", String(describing: command.error))
    }
    let lo = SIMD2(bounds.map(\.x).min()!, bounds.map(\.y).min()!)
    let hi = SIMD2(bounds.map(\.x).max()!, bounds.map(\.y).max()!)
    var probes: [String: Any] = [:]
    for (name, uv) in [("interior", SIMD2<Float>(0.5, 0.5)),
                       ("outsideUnit", SIMD2<Float>(0.7, -0.15)),
                       ("aabbMinusPolygon", SIMD2<Float>(-0.15, 0.95))] {
        let normalized = (uv - lo) / (hi - lo)
        guard normalized.x >= 0, normalized.x < 1,
              normalized.y >= 0, normalized.y < 1 else { continue }
        let x = Int(normalized.x * Float(size)), y = Int(normalized.y * Float(size))
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 16,
            from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0) }
        let actualUV = lo + (SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                            / Float(size)) * (hi - lo)
        probes[name] = ["pixel": pixel, "actualUV": [actualUV.x, actualUV.y],
                        "textureXY": [x, y]]
    }
    return ["completed": true, "physicalSize": size, "logicalHeight": logicalHeight,
            "encodedInputSize": floats(host("mwxRenderSize", type: .float2, inputs: frame)),
            "probes": probes]
}

@main private enum Main {
    static func main() throws {
        let cpu = hostProbe()
        guard !CommandLine.arguments.contains("--cpu-only"),
              let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else {
            print(String(data: try JSONSerialization.data(withJSONObject:
                ["cpu": cpu, "metalAvailable": false]), encoding: .utf8)!)
            return
        }
        guard CommandLine.arguments.count >= 3,
              let bundle = Bundle(path: CommandLine.arguments[1]) else {
            throw failure("compiler-bundle")
        }
        let cache = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var results: [[String: Any]] = []
        for generic in [false, true] {
            for renamed in [false, true] {
                for mode in ["constant", "uv", "position"] {
                    let pair = sources(mode: mode, renamed: renamed)
                    let program = try compiled(pair, generic: generic, bundle: bundle, cache: cache)
                    let library = try device.makeLibrary(source: program.metalSource, options: nil)
                    let descriptor = MTLRenderPipelineDescriptor()
                    descriptor.vertexFunction = library.makeFunction(name: program.vertexFunctionName)
                    descriptor.fragmentFunction = library.makeFunction(name: program.fragmentFunctionName)
                    descriptor.colorAttachments[0].pixelFormat = .rgba32Float
                    let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                    for (name, q) in [("U", unit), ("E", extended), ("N", nonrectangular)] {
                        for size in [96, 48] {
                            var result = try render(device: device, queue: queue, pipeline: pipeline,
                                program: program, points: q, bounds: q, size: size)
                            result["domain"] = name
                            result["backend"] = program.backend.rawValue
                            result["mode"] = mode
                            result["renamed"] = renamed
                            results.append(result)
                        }
                    }
                    var negative = try render(device: device, queue: queue, pipeline: pipeline,
                        program: program, points: nil, bounds: extended, size: 96)
                    negative["domain"] = "default-unit-in-E-capture"
                    negative["backend"] = program.backend.rawValue
                    negative["mode"] = mode
                    negative["renamed"] = renamed
                    results.append(negative)
                }
            }
        }
        print(String(data: try JSONSerialization.data(withJSONObject:
            ["cpu": cpu, "metalAvailable": true, "frames": results],
            options: [.sortedKeys]), encoding: .utf8)!)
    }
}
