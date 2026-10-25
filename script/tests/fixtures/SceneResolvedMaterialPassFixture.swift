// Shared authored Program, Metal input and readback fixtures for the original pass gate.

import CoreGraphics
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

func fragment(
    outputSlot: Int,
    uniformName: String = "g_Gain",
    unresolved: Bool = false
) -> String {
    let output = if unresolved {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * g_Gain;"
    } else if outputSlot == 3 {
        """
        vec4 color = texSample2D(g_Texture0, v_TexCoord);
        float mask = texSample2D(g_Texture3, v_TexCoord).r;
        color.a *= mask;
        gl_FragColor = color;
        """
    } else {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
    }
    return """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture3;
    uniform float \(uniformName);
    void main() {
        float uniformProbe = \(uniformName);
        \(output)
    }
    """
}

let straightAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture3;
uniform float g_Gain;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb, color.a * g_Gain);
}
"""

let straightRGBFactoredAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Gain;
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    float coverage = g_Gain;
    float alpha = source.a * coverage;
    gl_FragColor = vec4(source.rgb, alpha);
}
"""

let scanlineUniformRGBMixFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Weight;
uniform vec3 g_Tint;
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    float weight = saturate(g_Weight);
    vec3 mixed = mix(source.rgb, g_Tint, weight);
    gl_FragColor = vec4(mixed, source.a);
}
"""

let straightRGBScalarAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform sampler2D g_Texture3;
uniform float g_Time;
uniform float g_Amount;
uniform float g_NoiseAmount;
uniform float g_Power;
void main() {
    vec4 sampled = texSample2D(g_Texture0, v_TexCoord);
    vec4 color = sampled;
    float pulse = 0.0;
    float phase = texSample2D(g_Texture3, v_TexCoord).r * 6.0;
    pulse = smoothstep(
        0.0, 1.0, sin(g_Time + phase) * 0.5 + 0.5
    ) * g_Amount;
    float noise = texSample2D(
        g_Texture1, vec2(g_Time * 0.08, g_Time * 0.03)
    ).r * g_NoiseAmount;
    pulse += noise;
    pulse = pow(pulse, g_Power);
    color.a *= pulse;
    gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);
}
"""

let maskedAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture3;
uniform float g_Gain;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    float mask = texSample2D(g_Texture3, v_TexCoord).r;
    color.a *= mask * g_Gain;
    gl_FragColor = color;
}
"""

let overlayAlphaBlendFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_Multiply;
uniform float g_AlphaMultiply;
vec3 ApplyBlending(
    const int mode,
    in vec3 base,
    in vec3 blend,
    in float opacity
) {
    return mix(base, (blend), opacity);
}
void main() {
    vec4 base = texSample2D(g_Texture0, v_TexCoord);
    vec4 overlay = texSample2D(g_Texture1, v_TexCoord);
    float weight = g_Multiply * overlay.a;
    base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight);
    base.a = overlay.a * g_AlphaMultiply;
    gl_FragColor = base;
}
"""

let associatedOverBlendFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_ScalarWeight;
vec4 Composite(vec4 base, vec4 overlay, float weight) {
    float outputAlpha = base.a * (1.0 - weight) + overlay.a * weight;
    vec4 input = base;
    base.rgb = base.rgb * base.a * (1.0 - weight)
        + overlay.rgb * overlay.a * weight;
    vec3 source = mix(
        overlay.rgb,
        input.rgb,
        step(0.01, input.a) * (1.0 - overlay.a * weight)
    );
    vec3 destination = mix(
        input.rgb,
        overlay.rgb,
        step(0.01, overlay.a * (1.0 - input.a * (1.0 - weight)))
    );
    base.rgb += mix(source, destination, weight) * (1.0 - outputAlpha);
    base.a = outputAlpha;
    return base;
}
void main() {
    vec4 base = texSample2D(g_Texture0, v_TexCoord);
    vec4 overlay = texSample2D(g_Texture1, v_TexCoord);
    float weight = g_ScalarWeight;
    base = Composite(base, overlay, weight);
    gl_FragColor = base;
}
"""

let conditionalShadowFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Border;
uniform float g_Weight;
uniform vec3 g_Shadow;
vec3 ApplyBlending(
    const int mode,
    in vec3 base,
    in vec3 blend,
    in float opacity
) {
    return mix(base, blend, opacity);
}
void main() {
    vec4 base = texSample2D(g_Texture0, v_TexCoord);
    vec4 offset = texSample2D(
        g_Texture0, v_TexCoord + vec2(0.25, 0.0)
    );
    float mask = 1.0;
    if (base.a > g_Border) {
        gl_FragColor = base;
    } else if (offset.a > 0.0) {
        gl_FragColor.rgb = ApplyBlending(
            0, base.rgb, g_Shadow, g_Weight * mask
        );
        gl_FragColor.a = min(
            1.0, base.a + offset.a * g_Weight * mask
        );
    } else {
        gl_FragColor = base;
    }
}
"""

let wholeColorFilterFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform vec2 g_TexelSize;
uniform float g_Strength;
vec4 Sharpen(vec2 uv, float mask) {
    vec4 center = texSample2D(g_Texture0, uv);
    vec4 upperLeft = texSample2D(
        g_Texture0, uv + g_TexelSize * vec2(-1.0, -1.0)
    );
    vec4 upper = texSample2D(
        g_Texture0, uv + g_TexelSize * vec2(0.0, -1.0)
    );
    vec4 upperRight = texSample2D(
        g_Texture0, uv + g_TexelSize * vec2(1.0, -1.0)
    );
    vec4 left = texSample2D(
        g_Texture0, uv + g_TexelSize * vec2(-1.0, 0.0)
    );
    vec4 right = texSample2D(
        g_Texture0, uv + g_TexelSize * vec2(1.0, 0.0)
    );
    vec4 lowerLeft = texSample2D(
        g_Texture0, uv + g_TexelSize * vec2(-1.0, 1.0)
    );
    vec4 lower = texSample2D(
        g_Texture0, uv + g_TexelSize * vec2(0.0, 1.0)
    );
    vec4 lowerRight = texSample2D(
        g_Texture0, uv + g_TexelSize * vec2(1.0, 1.0)
    );
    vec4 lowpass = (
        upperLeft + upperRight + lowerLeft + lowerRight
        + 2.0 * (upper + left + right + lower) + 4.0 * center
    ) / 16.0;
    vec4 filtered = (1.0 + g_Strength * mask) * center
        - g_Strength * mask * lowpass;
    return filtered;
}
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    float mask = texSample2D(g_Texture1, v_TexCoord);
    if (mask > 0.1) source = Sharpen(v_TexCoord, mask);
    gl_FragColor = source;
}
"""

let boundedFlowFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform sampler2D g_Texture2;
uniform float g_Time;
uniform float g_Rate;
uniform float g_Magnitude;
uniform float g_Feather;
uniform float g_PhaseTiling;
void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
    vec2 flow = 2.0 * (
        texSample2D(g_Texture1, v_TexCoord).rg - vec2(0.498)
    );
    float clock = g_Time * g_Rate;
    vec4 cycle = fract(vec4(clock, clock + 0.5, clock + 0.25, clock + 0.75));
    vec4 signedCycle = cycle - vec4(0.5);
    float firstBlend = smoothstep(
        0.5 - g_Feather,
        0.5 + g_Feather,
        2.0 * abs(cycle.x - 0.5)
    );
    float secondBlend = smoothstep(
        0.5 - g_Feather,
        0.5 + g_Feather,
        2.0 * abs(cycle.z - 0.5)
    );
    vec2 offset = 0.1 * g_Magnitude * flow;
    vec4 firstPair = mix(
        texSample2D(g_Texture0, v_TexCoord + offset * signedCycle.x),
        texSample2D(g_Texture0, v_TexCoord + offset * signedCycle.y),
        firstBlend
    );
    vec4 secondPair = mix(
        texSample2D(g_Texture0, v_TexCoord + offset * signedCycle.z),
        texSample2D(g_Texture0, v_TexCoord + offset * signedCycle.w),
        secondBlend
    );
    float phase = smoothstep(
        0.2,
        0.8,
        texSample2D(g_Texture2, v_TexCoord * g_PhaseTiling).r
    );
    vec4 displaced = mix(firstPair, secondPair, phase);
    gl_FragColor = mix(albedo, displaced, length(flow));
}
"""

let boundedShimmerFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform sampler2D g_Texture3;
uniform float g_Time;
uniform float g_Speed;
uniform float g_Amount;
uniform float g_Direction;
uniform float g_Granularity;
uniform float g_Delay;
uniform vec3 g_Color;
void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
    float mask = texSample2D(g_Texture1, v_TexCoord).r;
    float sine = sin(g_Direction);
    float cosine = cos(g_Direction);
    vec2 local = g_Granularity * vec2(
        sine * v_TexCoord.x - cosine * v_TexCoord.y,
        cosine * v_TexCoord.x + sine * v_TexCoord.y
    );
    float coordinate = saturate(
        fract(
            (local.x + g_Speed * g_Time)
                / (g_Granularity * g_Delay)
        ) * g_Granularity * g_Delay
    );
    vec3 gradient = texSample2D(
        g_Texture3,
        fract(vec2(coordinate, local.y))
    ).rgb;
    vec3 effect = albedo.rgb + albedo.rgb * gradient * g_Color;
    albedo.rgb = mix(
        albedo.rgb,
        effect,
        mask * gradient * g_Amount
    );
    gl_FragColor = albedo;
}
"""

func prepared(
    marker: String,
    fragmentSource: String,
    replayVertexSource: String? = nil
) -> SceneShaderPreparedProgram {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        source: String
    ) -> SceneShaderPreparedSource {
        .init(
            frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion,
            sourceDialect: .wallpaperEngineGLSLLike,
            backend: .mwxMetal,
            stage: kind,
            rootRelativePath: "\(marker)/\(kind.rawValue).shader",
            source: source,
            sourceMap: [],
            activeAnnotations: [],
            activeDeclarations: [],
            dependencies: [],
            dependencySHA256: "dependency-\(marker)-\(kind.rawValue)",
            variantSHA256: "variant-\(marker)-\(kind.rawValue)",
            preparedSHA256: "prepared-\(marker)-\(kind.rawValue)"
        )
    }
    return .init(
        vertex: stage(.vertex, source: replayVertexSource ?? vertexSource),
        fragment: stage(.fragment, source: fragmentSource),
        colorContract: .unresolvedAuthoredPass,
        cacheKey: "cache-\(marker)"
    )
}

func state() -> SceneMaterialRenderState {
    SceneMaterialRenderState.compile(
        blending: "normal",
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: nil
    )!
}

func graphIdentity(
    _ marker: Int = 1,
    kind: Graph.TextureKind = .framebuffer
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

func texture(
    device: MTLDevice,
    format: MTLPixelFormat = .rgba8Unorm,
    width: Int = 2,
    height: Int = 2,
    usage: MTLTextureUsage = .shaderRead,
    fill: [UInt8]? = nil
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = usage
    let result = device.makeTexture(descriptor: descriptor)!
    if let fill {
        let bytesPerPixel: Int
        switch format {
        case .r8Unorm: bytesPerPixel = 1
        case .rg8Unorm: bytesPerPixel = 2
        case .rg16Float: bytesPerPixel = 4
        case .rg32Float: bytesPerPixel = 8
        default: bytesPerPixel = 4
        }
        result.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: fill,
            bytesPerRow: width * bytesPerPixel
        )
    }
    return result
}

func target(
    device: MTLDevice,
    format: MTLPixelFormat = .rgba8Unorm,
    width: Int = 2,
    height: Int = 2,
    usage: MTLTextureUsage = [.renderTarget, .shaderRead]
) -> MTLTexture {
    texture(
        device: device,
        format: format,
        width: width,
        height: height,
        usage: usage
    )
}

func slot(
    device: MTLDevice,
    index: Int,
    texture: MTLTexture,
    content: SceneTextureContent,
    purpose: SceneTextureLoadPurpose,
    sampling: SceneTextureSampling,
    marker: Int = 1,
    graphKind: Graph.TextureKind = .framebuffer
) -> Program.TextureSlot {
    let reference: Template.TextureReference
    let registry: SceneFrameTextureIdentity
    if index == 0 {
        let identity = graphIdentity(marker, kind: graphKind)
        reference = .graph(identity)
        registry = .graph(identity)
    } else {
        let path = SceneVFSAssetPath("assets/slot\(index)-\(marker).tex")!
        reference = .asset(path)
        registry = .asset(.init(path: path, purpose: purpose))
    }
    let generation = UInt64(marker)
    let providerIdentity: SceneTextureResourceIdentity = if content == .scalarRedUnorm {
        .provider(.graph(
            allocationGeneration: generation,
            physicalToken: "scalar-red-\(marker)"
        ))
    } else {
        .provider(.video(layerID: marker, lifecycleEpoch: 1))
    }
    let publication = SceneTextureProviderPublication(
        requestIdentity: registry,
        candidate: .init(
            texture: texture,
            identity: providerIdentity,
            generation: .provider(contentGeneration: generation),
            purpose: purpose,
            content: content,
            physicalSize: CGSize(width: texture.width, height: texture.height),
            mappedSize: CGSize(width: texture.width, height: texture.height),
            uvTransform: .identity,
            sampling: sampling
        ),
        contentGeneration: generation
    )
    return .init(
        index: index,
        reference: reference,
        registryIdentity: registry,
        diagnosticSelectionProvenance: .authored(.explicitBinding),
        expectedPurpose: purpose,
        resource: .init(publication: publication, resourceGeneration: generation)
    )
}

func slots(_ values: Program.TextureSlot...) -> [Program.TextureSlot?] {
    var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    for value in values { result[value.index] = value }
    return result
}

func bytes<T>(_ value: T) -> Data {
    var copy = value
    return withUnsafeBytes(of: &copy) { Data($0) }
}

func uniforms(
    shader: SceneShaderPreparedProgram,
    gain: Float = 0.5,
    malformed: Bool = false,
    values: [String: Data] = [:]
) -> [Program.ResolvedUniform] {
    let frontend = SceneAuthoredShaderFrontend.compile(
        vertexSource: shader.vertex.source,
        fragmentSource: shader.fragment.source
    ).program!
    let activeTextureSlots = Set(frontend.textureBindings.map(\.slot))
    return frontend.uniformLayout.fields.map { field in
        let value: Data
        if let explicit = values[field.name] {
            value = explicit
        } else if field.name == "mwxRenderSize" {
            value = bytes(SIMD2<Float>(2, 2))
        } else if field.name == "mwxVertexCoordinates01" {
            value = bytes(SIMD4<Float>(0, 1, 1, 1))
        } else if field.name == "mwxVertexCoordinates23" {
            value = bytes(SIMD4<Float>(0, 0, 1, 0))
        } else if malformed {
            value = bytes(SIMD2<Float>(0.5, 0.5))
        } else {
            value = bytes(gain)
        }
        let source = SceneResolvedMaterialHostUniformSchema.resolve(
            field,
            activeTextureSlots: activeTextureSlots
        ).map(Program.ResolvedUniform.Source.host) ?? .staticValue
        return .init(field: field, source: source, encodedValue: value)
    }
}

func program(
    device: MTLDevice,
    marker: Int,
    outputSlot: Int,
    slot0Texture: MTLTexture? = nil,
    slot0Content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
    slot0Purpose: SceneTextureLoadPurpose = .premultipliedColor,
    slot3Texture: MTLTexture? = nil,
    slot3Content: SceneTextureContent = .data,
    slot3Purpose: SceneTextureLoadPurpose = .mask,
    slot3Sampling: SceneTextureSampling = .init(texFlags: 1),
    uniformName: String = "g_Gain",
    unresolved: Bool = false,
    fragmentSource: String? = nil,
    gain: Float = 0.5,
    malformedUniform: Bool = false,
    additionalSlots: [Program.TextureSlot] = [],
    uniformValues: [String: Data] = [:],
    slot0Sampling: SceneTextureSampling = .directImageFallback,
    slot0GraphKind: Graph.TextureKind = .framebuffer,
    outputStorage: Program.OutputStorage = .color,
    replayVertexSource: String? = nil
) -> Program? {
    let shader = prepared(
        marker: "program-\(marker)",
        fragmentSource: fragmentSource ?? fragment(
            outputSlot: outputSlot,
            uniformName: uniformName,
            unresolved: unresolved
        ),
        replayVertexSource: replayVertexSource
    )
    let first = slot(
        device: device,
        index: 0,
        texture: slot0Texture ?? texture(device: device),
        content: slot0Content,
        purpose: slot0Purpose,
        sampling: slot0Sampling,
        marker: marker,
        graphKind: slot0GraphKind
    )
    let third = slot(
        device: device,
        index: 3,
        texture: slot3Texture ?? texture(device: device),
        content: slot3Content,
        purpose: slot3Purpose,
        sampling: slot3Sampling,
        marker: marker + 100
    )
    let frontend = SceneAuthoredShaderFrontend.compile(
        vertexSource: shader.vertex.source,
        fragmentSource: shader.fragment.source
    ).program!
    let activeSlots = Set(frontend.textureBindings.map(\.slot))
    var candidates = [0: first, 3: third]
    for extra in additionalSlots { candidates[extra.index] = extra }
    var resolvedSlots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    for active in activeSlots {
        guard let candidate = candidates[active] else { return nil }
        resolvedSlots[active] = candidate
    }
    return Program.assemble(.init(
        preparedShader: shader,
        textureSlots: resolvedSlots,
        resolvedUniforms: uniforms(
            shader: shader,
            gain: gain,
            malformed: malformedUniform,
            values: uniformValues
        ),
        renderState: state(),
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: slot0GraphKind == .layerSource
                ? .effectOutput : .framebuffer,
            bindings: activeSlots.contains(0)
                ? [.init(
                    slot: 0,
                    texture: slot0GraphKind == .layerSource
                        ? .layerSource : .framebuffer
                )]
                : []
        ),
        outputStorage: outputStorage
    ))
}

func pixels(_ texture: MTLTexture) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
    texture.getBytes(
        &result,
        bytesPerRow: texture.width * 4,
        from: MTLRegionMake2D(0, 0, texture.width, texture.height),
        mipmapLevel: 0
    )
    return result
}

func channelPixels<T: FixedWidthInteger>(
    _ texture: MTLTexture, as _: T.Type
) -> [T] {
    var result = [T](repeating: 0, count: texture.width * texture.height)
    texture.getBytes(
        &result,
        bytesPerRow: texture.width * MemoryLayout<T>.stride,
        from: MTLRegionMake2D(0, 0, texture.width, texture.height),
        mipmapLevel: 0
    )
    return result
}

func pixel(_ values: [UInt8], at index: Int) -> [UInt8]? {
    let start = index * 4
    guard start >= 0, start + 4 <= values.count else { return nil }
    return Array(values[start ..< start + 4])
}

func render(
    _ program: Program?,
    encoder: SceneResolvedMaterialPassEncoder,
    queue: MTLCommandQueue,
    target: MTLTexture
) -> (prepared: Bool, encoded: Bool, completed: Bool, pixels: [UInt8]) {
    guard let program,
          let prepared = encoder.prepare(program: program, target: target),
          let command = queue.makeCommandBuffer() else {
        return (false, false, false, [])
    }
    let encoded = encoder.encode(prepared, commandBuffer: command)
    command.commit()
    command.waitUntilCompleted()
    return (
        true,
        encoded,
        command.status == .completed && command.error == nil,
        pixels(target)
    )
}

func closePixels(
    _ actual: [UInt8],
    _ expected: [UInt8],
    tolerance: Int = 2
) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy {
        abs(Int($0.0) - Int($0.1)) <= tolerance
    }
}

