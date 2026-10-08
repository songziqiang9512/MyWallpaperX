import CoreGraphics
import Foundation
import Metal

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor, straightAlbedo, preservedChannels, mask, noise
    case flow, phase, normal, depth, lookupTable
    var requiresVolumeTexture: Bool { self == .lookupTable }
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material, instance, userTexture, explicitBinding
    }
}

nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored, userProperty, timeline, sceneScript
}

nonisolated struct SceneSystemProviderTextureIdentity: Hashable {
    let name: String
    let purpose: SceneTextureLoadPurpose
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case sceneBackground(Int)
    case sceneEnvironment
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(SceneSystemProviderTextureIdentity)
}

private typealias Program = SceneResolvedMaterialProgram
private typealias Template = SceneResolvedMaterialTemplate
private typealias Graph = SceneAuthoredEffectRenderPlan

private let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private func fragment(alphaTail: String) -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    vec3 ApplyBlending(
        const int mode,
        in vec3 base,
        in vec3 blend,
        in float opacity
    ) {
        return mix(base, blend, opacity);
    }
    void main() {
        vec4 signal = texSample2D(g_Texture0, v_TexCoord);
        signal.rgb *= vec3(1.0);
        vec4 previous = texSample2D(g_Texture1, v_TexCoord);
        signal.rgb = ApplyBlending(
            31, previous.rgb, signal.rgb, signal.a
        );
        signal.a = \(alphaTail);
        gl_FragColor = signal;
    }
    """
}

private func colorCarrierFragment(
    alphaTail: String,
    extraColorRead: Bool = false
) -> String {
    let extra = extraColorRead
        ? "canvas.rgb += texSample2D(g_Texture1, v_TexCoord).rgb * 0.0;"
        : ""
    return """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    vec3 ApplyBlending(
        const int mode,
        in vec3 base,
        in vec3 blend,
        in float opacity
    ) {
        return mix(base, blend, opacity);
    }
    void main() {
        vec4 impulse = texSample2D(g_Texture0, v_TexCoord);
        vec4 canvas = texSample2D(g_Texture1, v_TexCoord);
        canvas.rgb = ApplyBlending(
            31, canvas.rgb, impulse.rgb, impulse.a
        );
        canvas.a = \(alphaTail);
        \(extra)
        gl_FragColor = canvas;
    }
    """
}

private func prepared(fragmentSource: String) -> SceneShaderPreparedProgram {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        source: String
    ) -> SceneShaderPreparedSource {
        .init(
            frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion,
            sourceDialect: .wallpaperEngineGLSLLike,
            backend: .mwxMetal,
            stage: kind,
            rootRelativePath: "signal-composite/\(kind.rawValue).shader",
            source: source,
            sourceMap: [],
            activeAnnotations: [],
            activeDeclarations: [],
            dependencies: [],
            dependencySHA256: "signal-composite-dependency-\(kind.rawValue)",
            variantSHA256: "signal-composite-variant-\(kind.rawValue)",
            preparedSHA256: "signal-composite-prepared-\(kind.rawValue)"
        )
    }
    return .init(
        vertex: stage(.vertex, source: vertexSource),
        fragment: stage(.fragment, source: fragmentSource),
        colorContract: .unresolvedAuthoredPass,
        cacheKey: "signal-composite-cache"
    )
}

private func state() -> SceneMaterialRenderState {
    SceneMaterialRenderState.compile(
        blending: "normal",
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: nil
    )!
}

private func graphIdentity(_ marker: Int) -> Graph.TextureIdentity {
    let effect = Graph.EffectKey(
        layerID: 1,
        effectIndex: 0,
        descriptorID: "signal-composite-effect"
    )
    return .init(
        kind: .framebuffer,
        layerID: 1,
        effect: effect,
        name: "signal-composite-\(marker)"
    )
}

private func texture(
    device: MTLDevice,
    usage: MTLTextureUsage,
    fill: [UInt8]? = nil
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: 2,
        height: 2,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = usage
    let result = device.makeTexture(descriptor: descriptor)!
    if let fill {
        result.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: fill,
            bytesPerRow: 8
        )
    }
    return result
}

private func slot(
    index: Int,
    texture: MTLTexture,
    content: SceneTextureContent,
    marker: Int
) -> Program.TextureSlot {
    let identity = graphIdentity(marker)
    let generation = UInt64(marker)
    let registry = SceneFrameTextureIdentity.graph(identity)
    let publication = SceneTextureProviderPublication(
        requestIdentity: registry,
        candidate: .init(
            texture: texture,
            identity: .provider(.graph(
                allocationGeneration: generation,
                physicalToken: "signal-composite-\(marker)"
            )),
            generation: .provider(contentGeneration: generation),
            purpose: .premultipliedColor,
            content: content,
            physicalSize: CGSize(width: 2, height: 2),
            mappedSize: CGSize(width: 2, height: 2),
            uvTransform: .identity,
            sampling: .directImageFallback
        ),
        contentGeneration: generation
    )
    return .init(
        index: index,
        reference: .graph(identity),
        registryIdentity: registry,
        diagnosticSelectionProvenance: .authored(.explicitBinding),
        expectedPurpose: .premultipliedColor,
        resource: .init(
            publication: publication,
            resourceGeneration: generation
        )
    )
}

private func bytes<T>(_ value: T) -> Data {
    var copy = value
    return withUnsafeBytes(of: &copy) { Data($0) }
}

private func uniforms(
    shader: SceneShaderPreparedProgram
) -> [Program.ResolvedUniform] {
    let frontend = SceneAuthoredShaderFrontend.compile(
        vertexSource: shader.vertex.source,
        fragmentSource: shader.fragment.source
    ).program!
    let activeTextureSlots = Set(frontend.textureBindings.map(\.slot))
    return frontend.uniformLayout.fields.map { field in
        let value: Data
        if field.name == "mwxRenderSize" {
            value = bytes(SIMD2<Float>(2, 2))
        } else {
            value = bytes(Float(0))
        }
        let source = SceneResolvedMaterialHostUniformSchema.resolve(
            field,
            activeTextureSlots: activeTextureSlots
        ).map(Program.ResolvedUniform.Source.host) ?? .staticValue
        return .init(field: field, source: source, encodedValue: value)
    }
}

private func program(
    fragmentSource: String,
    signal: Program.TextureSlot,
    previous: Program.TextureSlot
) -> Program? {
    let shader = prepared(fragmentSource: fragmentSource)
    var textureSlots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    textureSlots[0] = signal
    textureSlots[1] = previous
    return Program.assemble(.init(
        preparedShader: shader,
        textureSlots: textureSlots,
        resolvedUniforms: uniforms(shader: shader),
        renderState: state(),
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: [
                .init(slot: 0, texture: .framebuffer),
                .init(slot: 1, texture: .framebuffer),
            ]
        ),
        outputStorage: .color
    ))
}

private func pixels(_ texture: MTLTexture) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: 16)
    texture.getBytes(
        &result,
        bytesPerRow: 8,
        from: MTLRegionMake2D(0, 0, 2, 2),
        mipmapLevel: 0
    )
    return result
}

private func close(
    _ actual: [UInt8],
    _ expected: [UInt8],
    tolerance: Int = 2
) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy {
        abs(Int($0.0) - Int($0.1)) <= tolerance
    }
}

private struct ExecutionResult {
    let encoded: Bool
    let completed: Bool
    let pixels: [UInt8]
}

private func execute(
    _ program: Program?,
    device: MTLDevice,
    queue: MTLCommandQueue,
    encoder: SceneResolvedMaterialPassEncoder
) -> ExecutionResult {
    let target = texture(
        device: device,
        usage: [.renderTarget, .shaderRead]
    )
    var encoded = false
    var completed = false
    if let program,
       let prepared = encoder.prepare(program: program, target: target),
       let command = queue.makeCommandBuffer() {
        encoded = encoder.encode(prepared, commandBuffer: command)
        command.commit()
        command.waitUntilCompleted()
        completed = command.status == .completed && command.error == nil
    }
    return .init(
        encoded: encoded,
        completed: completed,
        pixels: pixels(target)
    )
}

private struct BoundaryInput {
    let name: String
    let textures: [Int: [Double]]
    let expected: [Double]
}

private struct BoundaryFixture {
    let name: String
    let source: String
    let graphSlots: Set<Int>
    let activeSlots: Set<Int>
    let inputs: [BoundaryInput]
}

private func boundaryFixtures() -> [BoundaryFixture] {
    let preserving = """
    uniform sampler2D g_Texture0;
    varying vec2 v_TexCoord;
    void main() {
        vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
        albedo.rgb *= 0.25;
        gl_FragColor = albedo;
    }
    """
    let compositing = """
    uniform sampler2D g_Texture6;
    uniform sampler2D g_Texture2;
    varying vec2 v_TexCoord;
    vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {
        return base + blend * opacity;
    }
    void main() {
        vec4 impulse = texSample2D(g_Texture6, v_TexCoord);
        vec4 canvas = texSample2D(g_Texture2, v_TexCoord);
        canvas.rgb = ApplyBlending(7, canvas.rgb, impulse.rgb, impulse.a);
        canvas.a = saturate(canvas.a + impulse.a);
        gl_FragColor = canvas;
    }
    """
    let authorUNorm = """
    uniform sampler2D g_Texture0;
    uniform float g_ScalarWeight;
    varying vec2 v_TexCoord;
    void main() {
        vec4 sampled = texSample2D(g_Texture0, v_TexCoord);
        vec4 color = sampled;
        float pulse = 0.0;
        pulse = g_ScalarWeight;
        color.a *= pulse;
        gl_FragColor = saturate(color);
    }
    """
    return [
        .init(name: "preserving", source: preserving, graphSlots: [0], activeSlots: [0], inputs: [
            .init(name: "hdrOpaque", textures: [0: [2, 0.5, 0.25, 1]],
                  expected: [0.5, 0.125, 0.0625, 1]),
            .init(name: "hdrHalf", textures: [0: [1, 0.25, 0.125, 0.5]],
                  expected: [0.25, 0.0625, 0.03125, 0.5]),
            .init(name: "sdrOpaque", textures: [0: [0.8, 0.4, 0.2, 1]],
                  expected: [0.2, 0.1, 0.05, 1]),
            .init(name: "sdrHalf", textures: [0: [0.4, 0.2, 0.1, 0.5]],
                  expected: [0.1, 0.05, 0.025, 0.5]),
            .init(name: "zeroAlpha", textures: [0: [2, 0.5, 0.25, 0]],
                  expected: [0, 0, 0, 0]),
        ]),
        .init(name: "compositing", source: compositing, graphSlots: [6], activeSlots: [6, 2], inputs: [
            .init(name: "hdrOpaque", textures: [2: [0.75, 0.5, 0.25, 1], 6: [1, 0.5, 0.25, 0.5]],
                  expected: [1.25, 0.75, 0.375, 1]),
            .init(name: "hdrCoverage", textures: [2: [0.1875, 0.125, 0.0625, 0.25], 6: [1, 0.5, 0.25, 0.5]],
                  expected: [0.9375, 0.5625, 0.28125, 0.75]),
            .init(name: "sdr", textures: [2: [0.25, 0.125, 0.0625, 1], 6: [0.5, 0.25, 0.125, 0.5]],
                  expected: [0.5, 0.25, 0.125, 1]),
            .init(name: "zeroAlpha", textures: [2: [2, 0.5, 0.25, 0], 6: [1, 0.5, 0.25, 0]],
                  expected: [0, 0, 0, 0]),
        ]),
        .init(name: "authorUNorm", source: authorUNorm, graphSlots: [0], activeSlots: [0], inputs: [
            .init(name: "hdrOpaque", textures: [0: [2, 0.5, 0.25, 1]],
                  expected: [1, 0.5, 0.25, 1]),
            .init(name: "hdrHalf", textures: [0: [1, 0.25, 0.125, 0.5]],
                  expected: [0.5, 0.25, 0.125, 0.5]),
            .init(name: "sdr", textures: [0: [0.8, 0.4, 0.2, 1]],
                  expected: [0.8, 0.4, 0.2, 1]),
            .init(name: "zeroAlpha", textures: [0: [2, 0.5, 0.25, 0]],
                  expected: [0, 0, 0, 0]),
        ]),
    ]
}

private func renderBoundary(
    _ program: SceneAuthoredShaderProgram,
    inputs: [BoundaryInput], device: MTLDevice, queue: MTLCommandQueue
) throws -> [String: [[String: Any]]] {
    // Execute the accepted Program unchanged. A float target with blending
    // disabled measures its PMA boundary before the downstream compositor.
    let library = try device.makeLibrary(source: program.metalSource, options: nil)
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = library.makeFunction(name: program.vertexFunctionName)
    pipelineDescriptor.fragmentFunction = library.makeFunction(name: program.fragmentFunctionName)
    pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
    let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.shaderRead, .renderTarget]
    let sources = Dictionary(uniqueKeysWithValues: program.textureBindings.map {
        ($0.slot, device.makeTexture(descriptor: descriptor)!)
    })
    let target = device.makeTexture(descriptor: descriptor)!
    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.minFilter = .nearest
    samplerDescriptor.magFilter = .nearest
    samplerDescriptor.sAddressMode = .clampToEdge
    samplerDescriptor.tAddressMode = .clampToEdge
    let sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
    var uniforms = Data(count: max(program.uniformLayout.byteSize, 16))
    for field in program.uniformLayout.fields {
        let value: Data
        switch field.authoredName {
        case "mwxRenderSize": value = bytes(SIMD2<Float>(1, 1))
        case "g_ScalarWeight": value = bytes(Float(1))
        default:
            throw NSError(domain: "unbound-boundary-ABI-\(field.authoredName)", code: 1)
        }
        uniforms.replaceSubrange(field.offset..<field.offset + value.count, with: value)
    }
    var results: [String: [[String: Any]]] = [:]
    for input in inputs {
        for binding in program.textureBindings {
            let pixel = input.textures[binding.slot]!.map { Float16($0) }
            pixel.withUnsafeBytes {
                sources[binding.slot]!.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: 8)
            }
        }
        var frames: [[String: Any]] = []
        for _ in 0..<2 {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            encoder.setRenderPipelineState(pipeline)
            uniforms.withUnsafeBytes {
                encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: program.uniformBufferIndex)
                encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: program.uniformBufferIndex)
            }
            for binding in program.textureBindings {
                encoder.setVertexTexture(sources[binding.slot], index: binding.slot)
                encoder.setFragmentTexture(sources[binding.slot], index: binding.slot)
                encoder.setVertexSamplerState(sampler, index: binding.slot)
                encoder.setFragmentSamplerState(sampler, index: binding.slot)
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            var pixel = [UInt16](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes {
                target.getBytes($0.baseAddress!, bytesPerRow: 8,
                    from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
            }
            frames.append([
                "output": pixel.map { Double(Float16(bitPattern: $0)) },
                "bits": pixel.map(Int.init), "expected": input.expected,
                "completion": command.status == .completed && command.error == nil
                    ? "completed" : "failed",
            ])
        }
        results[input.name] = frames
    }
    return results
}

private func runBoundaries(device: MTLDevice, queue: MTLCommandQueue) throws -> [String: Any] {
    var results: [String: Any] = [:]
    for fixture in boundaryFixtures() {
        var accepted: (program: SceneAuthoredShaderProgram, pmaSlots: Set<Int>,
                       key: String, route: SceneGenericShaderRouteDecision)?
        // The existing ordinary generic route rejects this scalar-alpha UNorm
        // shape. Its bounded control checks author saturation, without claiming
        // an accepted generic artifact or injecting a fabricated source fact.
        if fixture.name != "authorUNorm" {
            let resolution = SceneResolvedMaterialGenericShaderArtifactCache.resolve(
                vertexSource: vertexSource, fragmentSource: fixture.source,
                graphTextureSlots: fixture.graphSlots, graphInputTextureSlots: fixture.activeSlots,
                activeTextureSlots: fixture.activeSlots,
                hasOnlyGraphInputSampler: true, outputIsRGBA8Unorm: false)
            guard case let .accepted(program, pmaSlots, key, route) = resolution else {
                throw NSError(domain: "boundary-artifact-rejected-\(fixture.name)", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: String(describing: resolution)])
            }
            accepted = (program, pmaSlots, key, route)
        }
        let boundedOutput = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertexSource, fragmentSource: fixture.source,
            provenColorTransfer: accepted?.program.colorTransfer,
            premultipliedColorInputSlots: accepted?.pmaSlots ?? [])
        guard let bounded = boundedOutput.program else {
            throw NSError(domain: "boundary-bounded-rejected-\(fixture.name)", code: 1)
        }
        var result: [String: Any] = [
            "boundedBackend": bounded.backend.rawValue,
            "transfer": String(describing: bounded.colorTransfer),
            "vertexSource": vertexSource, "fragmentSource": fixture.source,
            "inputFormat": "rgba16Float", "outputFormat": "rgba16Float",
            "inputs": fixture.inputs.map { input in
                ["name": input.name, "textures": Dictionary(uniqueKeysWithValues:
                    input.textures.map { (String($0.key), $0.value) }),
                 "expected": input.expected] as [String: Any]
            },
            "boundedProgram": try JSONSerialization.jsonObject(with: JSONEncoder().encode(bounded)),
            "bounded": try renderBoundary(bounded, inputs: fixture.inputs, device: device, queue: queue),
        ]
        if let accepted {
            result["requestKey"] = accepted.key
            result["routeProfile"] = accepted.route.profile
            result["routeState"] = accepted.route.state
            result["backend"] = accepted.program.backend.rawValue
            result["premultipliedColorInputSlots"] = accepted.pmaSlots.sorted()
            result["acceptedProgram"] = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(accepted.program))
            result["metalSHA256"] = SceneGenericShaderProgramArtifact.sha256(
                Data(accepted.program.metalSource.utf8))
            result["generic"] = try renderBoundary(accepted.program,
                inputs: fixture.inputs, device: device, queue: queue)
        }
        results[fixture.name] = result
    }
    return results
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let encoder = SceneResolvedMaterialPassEncoder(device: device) else {
            print("{\"metalAvailable\":false}")
            return
        }
        let signalPixel: [UInt8] = [204, 51, 26, 128]
        let previousPixel: [UInt8] = [26, 51, 76, 255]
        let canvasPixel: [UInt8] = [26, 51, 76, 128]
        let signalBytes = Array(repeating: signalPixel, count: 4).flatMap { $0 }
        let previousBytes = Array(repeating: previousPixel, count: 4).flatMap { $0 }
        let canvasBytes = Array(repeating: canvasPixel, count: 4).flatMap { $0 }
        let signal = slot(
            index: 0,
            texture: texture(device: device, usage: .shaderRead, fill: signalBytes),
            content: .color(.resolved(.independentAlphaSignal)),
            marker: 1
        )
        let previous = slot(
            index: 1,
            texture: texture(device: device, usage: .shaderRead, fill: previousBytes),
            content: .color(.resolved(.opaque)),
            marker: 2
        )
        let canvas = slot(
            index: 1,
            texture: texture(device: device, usage: .shaderRead, fill: canvasBytes),
            content: .color(.resolved(.premultipliedAlpha)),
            marker: 3
        )

        let signalCarrierSource = fragment(
            alphaTail: "saturate(previous.a + signal.a)"
        )
        let signalCarrierFrontend = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertexSource,
            fragmentSource: signalCarrierSource
        )
        let signalCarrier = program(
            fragmentSource: signalCarrierSource,
            signal: signal,
            previous: previous
        )
        let signalCarrierBadAlpha = program(
            fragmentSource: fragment(alphaTail: "saturate(signal.a)"),
            signal: signal,
            previous: previous
        )

        let colorCarrierSource = colorCarrierFragment(
            alphaTail: "saturate(canvas.a + impulse.a)"
        )
        let colorCarrierFrontend = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertexSource,
            fragmentSource: colorCarrierSource
        )
        let colorCarrier = program(
            fragmentSource: colorCarrierSource,
            signal: signal,
            previous: canvas
        )
        let colorCarrierBadAlpha = program(
            fragmentSource: colorCarrierFragment(
                alphaTail: "saturate(canvas.a)"
            ),
            signal: signal,
            previous: canvas
        )
        let colorCarrierExtraRead = program(
            fragmentSource: colorCarrierFragment(
                alphaTail: "saturate(canvas.a + impulse.a)",
                extraColorRead: true
            ),
            signal: signal,
            previous: canvas
        )

        let signalCarrierExecution = execute(
            signalCarrier,
            device: device,
            queue: queue,
            encoder: encoder
        )
        let colorCarrierExecution = execute(
            colorCarrier,
            device: device,
            queue: queue,
            encoder: encoder
        )
        let expectedPixel: [UInt8] = [115, 51, 51, 255]
        let expected = Array(repeating: expectedPixel, count: 4).flatMap { $0 }
        let colorCarrierExpectedPixel: [UInt8] = [128, 76, 88, 255]
        let colorCarrierExpected = Array(
            repeating: colorCarrierExpectedPixel,
            count: 4
        ).flatMap { $0 }
        var result: [String: Any] = [
            "metalAvailable": true,
            "positiveAssembled": signalCarrier != nil,
            "negativeRejected": signalCarrierBadAlpha == nil,
            "encoded": signalCarrierExecution.encoded,
            "completed": signalCarrierExecution.completed,
            "pixelsMatch": close(signalCarrierExecution.pixels, expected),
            "pixels": signalCarrierExecution.pixels,
            "frontendDiagnostics":
                signalCarrierFrontend.diagnostics.map(\.code.rawValue),
            "frontendTransfer": signalCarrierFrontend.program.map {
                String(describing: $0.colorTransfer)
            } ?? "missing",
            "signalCarrierFrontendAccepted":
                signalCarrierFrontend.diagnostics.isEmpty
                    && signalCarrierFrontend.program?.backend == .boundedSwift
                    && signalCarrierFrontend.program?.colorTransfer
                        == .independentAlphaSignalCompositing(
                            signalSlot: 0,
                            colorSlot: 1
                        ),
            "colorCarrierFrontendAccepted":
                colorCarrierFrontend.diagnostics.isEmpty
                    && colorCarrierFrontend.program?.backend == .boundedSwift
                    && colorCarrierFrontend.program?.colorTransfer
                        == .independentAlphaSignalCompositing(
                            signalSlot: 0,
                            colorSlot: 1
                        ),
            "colorCarrierAssembled": colorCarrier != nil,
            "colorCarrierBadAlphaRejected": colorCarrierBadAlpha == nil,
            "colorCarrierExtraReadRejected": colorCarrierExtraRead == nil,
            "colorCarrierEncoded": colorCarrierExecution.encoded,
            "colorCarrierCompleted": colorCarrierExecution.completed,
            "colorCarrierPixelsMatch": close(
                colorCarrierExecution.pixels,
                colorCarrierExpected
            ),
            "colorCarrierPixels": colorCarrierExecution.pixels,
        ]
        result["boundaries"] = try runBoundaries(device: device, queue: queue)
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
