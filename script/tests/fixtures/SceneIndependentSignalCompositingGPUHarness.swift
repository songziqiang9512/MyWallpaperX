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

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case sceneBackground(Int)
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(String)
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
        } else if let transform = SceneMaterialTextureTransformABI.component(
            forFieldName: field.name
        ) {
            value = bytes(transform.component.identityValue)
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
        let result: [String: Any] = [
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
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
