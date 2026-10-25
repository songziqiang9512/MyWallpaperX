// Shared self-authored Program derivation inputs and builders.
import Foundation
import Metal
import simd

typealias Program = SceneResolvedMaterialProgram
typealias Template = SceneResolvedMaterialTemplate
typealias Graph = SceneAuthoredEffectRenderPlan

let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

let passthroughFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Gain;
void main() {
    float uniformProbe = g_Gain;
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
}
"""

let proceduralOpaqueFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
void main() {
    gl_FragColor = vec4(v_TexCoord, 0.0, 1.0);
}
"""

let straightAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Gain;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb, color.a * g_Gain);
}
"""

let scanlineUniformRGBMixFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Gain;
uniform vec3 g_Tint;
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    float weight = saturate(g_Gain);
    vec3 mixed = mix(source.rgb, g_Tint, weight);
    gl_FragColor = vec4(mixed, source.a);
}
"""

let maskedAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_Gain;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    float mask = texSample2D(g_Texture1, v_TexCoord).r;
    color.a *= mask * g_Gain;
    gl_FragColor = color;
}
"""

let opaqueAlphaPreservingFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Gain;
void main() {
    vec4 sampled = texSample2D(g_Texture0, v_TexCoord);
    vec4 color = sampled;
    color.rgb *= g_Gain;
    gl_FragColor = saturate(color);
}
"""

let wholeColorFilterFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_Gain;
vec4 Filter(vec2 uv, float mask) {
    vec4 center = texSample2D(g_Texture0, uv);
    vec4 left = texSample2D(g_Texture0, uv - vec2(0.1));
    vec4 right = texSample2D(g_Texture0, uv + vec2(0.1));
    vec4 average = (left + right) / 2;
    vec4 filtered = (1 + mask) * center - mask * average;
    return filtered;
}
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    float mask = texSample2D(g_Texture1, v_TexCoord).r;
    if (mask > 0.1) source = Filter(v_TexCoord, mask);
    gl_FragColor = source;
}
"""

func prepared(
    revision: String,
    fragment: String = passthroughFragment,
    frontendSchemaVersion: Int = SceneShaderVariantEnvironment.frontendSchemaVersion
) -> SceneShaderPreparedProgram {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        source: String
    ) -> SceneShaderPreparedSource {
        SceneShaderPreparedSource(
            frontendSchemaVersion: frontendSchemaVersion,
            sourceDialect: .wallpaperEngineGLSLLike,
            backend: .mwxMetal,
            stage: kind,
            rootRelativePath: "\(revision)/\(kind.rawValue).shader",
            source: source,
            sourceMap: [],
            activeAnnotations: [],
            activeDeclarations: [],
            dependencies: [],
            dependencySHA256: "dependency-\(revision)-\(kind.rawValue)",
            variantSHA256: "variant-\(revision)-\(kind.rawValue)",
            preparedSHA256: "prepared-\(revision)-\(kind.rawValue)"
        )
    }
    return .init(
        vertex: stage(.vertex, source: vertexSource),
        fragment: stage(.fragment, source: fragment),
        colorContract: .unresolvedAuthoredPass,
        cacheKey: "cache-\(revision)"
    )
}

func graphIdentity(
    _ kind: Graph.TextureKind = .framebuffer,
    marker: Int = 1
) -> Graph.TextureIdentity {
    let effect = Graph.EffectKey(
        layerID: marker,
        effectIndex: marker,
        descriptorID: "descriptor-\(marker)"
    )
    return .init(
        kind: kind,
        layerID: marker,
        effect: kind == .layerSource ? nil : effect,
        name: kind == .framebuffer ? "framebuffer-\(marker)" : nil
    )
}

func graphRole(
    effectInput: Template.GraphTextureRole = .layerSource
) -> Template.GraphRole {
    .init(
        effectInput: effectInput,
        effectOutput: .effectOutput,
        nodeTarget: .framebuffer,
        bindings: [.init(slot: 0, texture: .framebuffer)]
    )
}

func makeTexture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: 2,
        height: 2,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    return device.makeTexture(descriptor: descriptor)!
}

func textureSlot(
    device: MTLDevice,
    slot: Int = 0,
    marker: Int = 1,
    expectedPurpose: SceneTextureLoadPurpose = .premultipliedColor,
    publishedPurpose: SceneTextureLoadPurpose = .premultipliedColor,
    content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
    graphKind: Graph.TextureKind = .framebuffer,
    reference: Template.TextureReference? = nil,
    registryIdentityOverride: SceneFrameTextureIdentity? = nil,
    diagnosticProvenance: Program.TextureSelectionProvenance = .authored(.explicitBinding),
    contentGeneration: UInt64 = 1
) -> Program.TextureSlot {
    let texture = makeTexture(device)
    let resolvedReference = reference
        ?? .graph(graphIdentity(graphKind, marker: marker))
    let registryIdentity: SceneFrameTextureIdentity
    switch resolvedReference {
    case let .asset(path):
        registryIdentity = .asset(.init(path: path, purpose: expectedPurpose))
    case let .userProperty(request):
        registryIdentity = .materialUserProperty(.init(
            propertyKey: request.key,
            purpose: expectedPurpose
        )!)
    case let .provider(request):
        switch request {
        case let .system(name):
            registryIdentity = .system(.init(
                name: name,
                purpose: expectedPurpose
            ))
        case let .namedLayerTarget(reference):
            registryIdentity = .namedLayerTarget(reference)
        case let .sceneBackground(consumerLayerID):
            registryIdentity = .sceneBackground(consumerLayerID)
        case .sceneEnvironment:
            fatalError("scene environment requires the real producer fixture")
        }
    case let .graph(identity):
        registryIdentity = .graph(identity)
    }
    let resolvedRegistryIdentity = registryIdentityOverride ?? registryIdentity
    let publication = SceneTextureProviderPublication(
        requestIdentity: resolvedRegistryIdentity,
        candidate: .init(
            texture: texture,
            identity: .provider(.video(layerID: marker, lifecycleEpoch: 1)),
            generation: .provider(contentGeneration: contentGeneration),
            purpose: publishedPurpose,
            content: content,
            physicalSize: CGSize(width: 2, height: 2),
            mappedSize: CGSize(width: 2, height: 2),
            uvTransform: .identity,
            sampling: .directImageFallback
        ),
        contentGeneration: contentGeneration
    )
    return .init(
        index: slot,
        reference: resolvedReference,
        registryIdentity: resolvedRegistryIdentity,
        diagnosticSelectionProvenance: diagnosticProvenance,
        expectedPurpose: expectedPurpose,
        resource: .init(
            publication: publication,
            resourceGeneration: UInt64(marker)
        )
    )
}

func data<T>(_ value: T) -> Data {
    var copy = value
    return withUnsafeBytes(of: &copy) { Data($0) }
}

func resolvedUniforms(
    _ prepared: SceneShaderPreparedProgram,
    gain: Float,
    dynamic: (
        Template.DynamicUniformSource,
        SceneDynamicSource,
        [Template.DynamicUniformScriptAttachment]
    )? = nil
) -> [Program.ResolvedUniform] {
    let frontend = SceneAuthoredShaderFrontend.compile(
        vertexSource: prepared.vertex.source,
        fragmentSource: prepared.fragment.source
    ).program!
    return frontend.uniformLayout.fields.map { field in
        switch field.name {
        case "g_Gain", "u_RenamedGain":
            if let dynamic {
                return .init(
                    field: field,
                    source: .dynamic(
                        declared: dynamic.0,
                        target: .effectConstant(
                            layerID: 1,
                            effectIndex: 2,
                            passIndex: 3,
                            name: field.name
                        ),
                        resolvedSource: dynamic.1,
                        scriptAttachments: dynamic.2
                    ),
                    encodedValue: data(gain)
                )
            }
            return .init(
                field: field,
                source: .staticValue,
                encodedValue: data(gain)
            )
        case "g_Tint":
            return .init(
                field: field,
                source: .staticValue,
                encodedValue: data(SIMD3<Float>(1, 0, 0.5))
            )
        default:
            guard let host = SceneResolvedMaterialHostUniformSchema.resolve(
                field,
                activeTextureSlots: Set(frontend.textureBindings.map(\.slot))
            ) else { fatalError("unexpected field \(field.name)") }
            let value: Data
            switch host {
            case .renderSize:
                value = data(SIMD2<Float>(1920, 1080))
            case .vertexCoordinates01:
                value = data(SIMD4<Float>(0, 1, 1, 1))
            case .vertexCoordinates23:
                value = data(SIMD4<Float>(0, 0, 1, 0))
            default:
                fatalError("unexpected host field \(field.name)")
            }
            return .init(field: field, source: .host(host), encodedValue: value)
        }
    }
}

func state(
    synonym: Bool = false,
    blending: String = "normal"
) -> SceneMaterialRenderState {
    SceneMaterialRenderState.compile(
        blending: synonym ? "  \(blending.uppercased())  " : blending,
        depthTest: synonym ? " DISABLED " : "disabled",
        depthWrite: synonym ? "Disabled" : "disabled",
        cullMode: synonym ? " NoCull " : "nocull",
        alphaWriting: nil
    )!
}

func slots(_ values: Program.TextureSlot...) -> [Program.TextureSlot?] {
    var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    for value in values { result[value.index] = value }
    return result
}

func replacingSampling(
    _ slot: Program.TextureSlot,
    with sampling: SceneTextureSampling
) -> Program.TextureSlot {
    let publication = slot.resource.publication
    let candidate = publication.candidate
    let replacement = SceneTextureCandidate(
        texture: candidate.texture,
        identity: candidate.identity,
        generation: candidate.generation,
        purpose: candidate.purpose,
        content: candidate.content,
        physicalSize: candidate.physicalSize,
        mappedSize: candidate.mappedSize,
        uvTransform: candidate.uvTransform,
        sampling: sampling
    )
    return .init(
        index: slot.index,
        reference: slot.reference,
        registryIdentity: slot.registryIdentity,
        diagnosticSelectionProvenance: slot.diagnosticSelectionProvenance,
        expectedPurpose: slot.expectedPurpose,
        resource: .init(
            publication: .init(
                requestIdentity: publication.requestIdentity,
                candidate: replacement,
                contentGeneration: publication.contentGeneration
            ),
            resourceGeneration: slot.resource.resourceGeneration
        )
    )
}

func assemble(
    prepared shader: SceneShaderPreparedProgram,
    textureSlots: [Program.TextureSlot?],
    gain: Float = 0.25,
    renderState: SceneMaterialRenderState = state(),
    role: Template.GraphRole = graphRole(),
    reverseUniforms: Bool = false,
    dynamic: (
        Template.DynamicUniformSource,
        SceneDynamicSource,
        [Template.DynamicUniformScriptAttachment]
    )? = nil,
    outputStorage: Program.OutputStorage = .color
) -> Program? {
    var uniforms = resolvedUniforms(
        shader,
        gain: gain,
        dynamic: dynamic
    )
    if reverseUniforms { uniforms.reverse() }
    return Program.assemble(.init(
        preparedShader: shader,
        textureSlots: textureSlots,
        resolvedUniforms: uniforms,
        renderState: renderState,
        graphRole: role,
        outputStorage: outputStorage
    ))
}

func hasStraightAlphaBoundary(_ program: Program?) -> Bool {
    guard let program,
          case .straightAlpha(0) = program.semanticIdentity.shader.colorTransfer else {
        return false
    }
    guard case let .color(contract) = program.semanticIdentity.outputContract else {
        return false
    }
    return contract.fragmentOutput == .premultipliedAlpha
}

func hasStraightAlphaPreservingBoundary(_ program: Program?) -> Bool {
    guard let program,
          case .straightAlphaPreserving(0) =
            program.semanticIdentity.shader.colorTransfer else {
        return false
    }
    guard case let .color(contract) = program.semanticIdentity.outputContract else {
        return false
    }
    return contract.fragmentOutput == .premultipliedAlpha
}

func hasStraightAlphaUNormBoundary(_ program: Program?) -> Bool {
    guard let program,
          case .straightAlphaUNorm(0) =
            program.semanticIdentity.shader.colorTransfer else {
        return false
    }
    guard case let .color(contract) = program.semanticIdentity.outputContract else {
        return false
    }
    return contract.fragmentOutput == .premultipliedAlpha
}

func colorIdentity(_ program: Program?) -> Program.ColorContractIdentity? {
    guard let program,
          case let .color(contract) = program.semanticIdentity.outputContract else {
        return nil
    }
    return contract
}
