#!/usr/bin/env python3

"""R4 atomic material Program preflight, pipeline cache and Metal encoding gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment+HostFacts.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    *scene_swift_sources("authored_shader_frontend_implementation"),
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialHostUniformSchema.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramIdentity.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramIdentity+ExactTexture.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+Derivation.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+ColorDerivation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialAttachmentKind.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialAttachmentStorage.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder+Failure.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder.swift",
]


SUPPORT = r'''
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
    case namedLayerTarget(String)
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(String)
}
'''


HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

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

private func fragment(
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

private let straightAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture3;
uniform float g_Gain;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb, color.a * g_Gain);
}
"""

private let straightRGBFactoredAlphaFragment = """
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

private let scanlineUniformRGBMixFragment = """
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

private let straightRGBScalarAlphaFragment = """
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

private let maskedAlphaFragment = """
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

private let overlayAlphaBlendFragment = """
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

private let wholeColorFilterFragment = """
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

private let boundedFlowFragment = """
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

private let boundedShimmerFragment = """
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

private func prepared(
    marker: String,
    fragmentSource: String
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
        vertex: stage(.vertex, source: vertexSource),
        fragment: stage(.fragment, source: fragmentSource),
        colorContract: .unresolvedAuthoredPass,
        cacheKey: "cache-\(marker)"
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

private func graphIdentity(
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

private func texture(
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

private func target(
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

private func slot(
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

private func slots(_ values: Program.TextureSlot...) -> [Program.TextureSlot?] {
    var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    for value in values { result[value.index] = value }
    return result
}

private func bytes<T>(_ value: T) -> Data {
    var copy = value
    return withUnsafeBytes(of: &copy) { Data($0) }
}

private func uniforms(
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

private func program(
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
    slot0GraphKind: Graph.TextureKind = .framebuffer
) -> Program? {
    let shader = prepared(
        marker: "program-\(marker)",
        fragmentSource: fragmentSource ?? fragment(
            outputSlot: outputSlot,
            uniformName: uniformName,
            unresolved: unresolved
        )
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
        )
    ))
}

private func pixels(_ texture: MTLTexture) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
    texture.getBytes(
        &result,
        bytesPerRow: texture.width * 4,
        from: MTLRegionMake2D(0, 0, texture.width, texture.height),
        mipmapLevel: 0
    )
    return result
}

private func scalarPixels(_ texture: MTLTexture) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: texture.width * texture.height)
    texture.getBytes(
        &result,
        bytesPerRow: texture.width,
        from: MTLRegionMake2D(0, 0, texture.width, texture.height),
        mipmapLevel: 0
    )
    return result
}

private func pixel(_ values: [UInt8], at index: Int) -> [UInt8]? {
    let start = index * 4
    guard start >= 0, start + 4 <= values.count else { return nil }
    return Array(values[start ..< start + 4])
}

private func render(
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

private func fract(_ value: Float) -> Float {
    value - floor(value)
}

private func clamp01(_ value: Float) -> Float {
    min(1, max(0, value))
}

private func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
    let unit = clamp01((value - low) / (high - low))
    return unit * unit * (3 - 2 * unit)
}

private func addressedIndex(_ index: Int, count: Int, repeats: Bool) -> Int {
    guard repeats else { return min(count - 1, max(0, index)) }
    let remainder = index % count
    return remainder >= 0 ? remainder : remainder + count
}

private func quantized(_ values: [SIMD4<Float>]) -> [UInt8] {
    values.flatMap { value in
        (0 ..< 4).map { component in
            UInt8((clamp01(value[component]) * 255).rounded())
        }
    }
}

private func closePixels(
    _ actual: [UInt8],
    _ expected: [UInt8],
    tolerance: Int = 2
) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy {
        abs(Int($0.0) - Int($0.1)) <= tolerance
    }
}

private func linearAxis(
    coordinate: Float,
    count: Int,
    repeats: Bool
) -> (lower: Int, upper: Int, weight: Float) {
    let position = coordinate * Float(count) - 0.5
    let rawLower = Int(floor(position))
    return (
        addressedIndex(rawLower, count: count, repeats: repeats),
        addressedIndex(rawLower + 1, count: count, repeats: repeats),
        position - floor(position)
    )
}

private func nearestAxis(
    coordinate: Float,
    count: Int,
    repeats: Bool
) -> Int {
    addressedIndex(
        Int(floor(coordinate * Float(count))),
        count: count,
        repeats: repeats
    )
}

private func sampleColor2D(
    _ source: [UInt8],
    width: Int,
    height: Int,
    coordinate: SIMD2<Float>,
    linear: Bool
) -> SIMD4<Float> {
    func value(x: Int, y: Int) -> SIMD4<Float> {
        let bytes = pixel(source, at: y * width + x)!
        return SIMD4<Float>(
            Float(bytes[0]) / 255,
            Float(bytes[1]) / 255,
            Float(bytes[2]) / 255,
            Float(bytes[3]) / 255
        )
    }
    guard linear else {
        return value(
            x: nearestAxis(coordinate: coordinate.x, count: width, repeats: false),
            y: nearestAxis(coordinate: coordinate.y, count: height, repeats: false)
        )
    }
    let x = linearAxis(coordinate: coordinate.x, count: width, repeats: false)
    let y = linearAxis(coordinate: coordinate.y, count: height, repeats: false)
    let top = value(x: x.lower, y: y.lower)
        + x.weight * (value(x: x.upper, y: y.lower) - value(x: x.lower, y: y.lower))
    let bottom = value(x: x.lower, y: y.upper)
        + x.weight * (value(x: x.upper, y: y.upper) - value(x: x.lower, y: y.upper))
    return top + y.weight * (bottom - top)
}

private func sampleRG8(
    _ source: [UInt8],
    width: Int,
    height: Int,
    coordinate: SIMD2<Float>
) -> SIMD2<Float> {
    func value(x: Int, y: Int) -> SIMD2<Float> {
        let start = (y * width + x) * 2
        return SIMD2(
            Float(source[start]) / 255,
            Float(source[start + 1]) / 255
        )
    }
    let x = linearAxis(coordinate: coordinate.x, count: width, repeats: false)
    let y = linearAxis(coordinate: coordinate.y, count: height, repeats: false)
    let top = value(x: x.lower, y: y.lower)
        + x.weight * (value(x: x.upper, y: y.lower) - value(x: x.lower, y: y.lower))
    let bottom = value(x: x.lower, y: y.upper)
        + x.weight * (value(x: x.upper, y: y.upper) - value(x: x.lower, y: y.upper))
    return top + y.weight * (bottom - top)
}

private func sampleR8(
    _ source: [UInt8],
    width: Int,
    height: Int,
    coordinate: SIMD2<Float>,
    repeats: Bool
) -> Float {
    func value(x: Int, y: Int) -> Float {
        Float(source[y * width + x]) / 255
    }
    let x = linearAxis(coordinate: coordinate.x, count: width, repeats: repeats)
    let y = linearAxis(coordinate: coordinate.y, count: height, repeats: repeats)
    let top = value(x: x.lower, y: y.lower)
        + x.weight * (value(x: x.upper, y: y.lower) - value(x: x.lower, y: y.lower))
    let bottom = value(x: x.lower, y: y.upper)
        + x.weight * (value(x: x.upper, y: y.upper) - value(x: x.lower, y: y.upper))
    return top + y.weight * (bottom - top)
}

private func flowOracle2D(
    source: [UInt8],
    width: Int,
    height: Int,
    flow: [UInt8],
    flowWidth: Int,
    flowHeight: Int,
    phase: [UInt8],
    phaseWidth: Int,
    phaseHeight: Int,
    time: Float,
    rate: Float,
    magnitude: Float,
    feather: Float,
    phaseTiling: Float,
    linearSource: Bool = true,
    saturatesFlowAmount: Bool = false
) -> [UInt8] {
    let clock = time * rate
    let cycle = SIMD4<Float>(
        fract(clock),
        fract(clock + 0.5),
        fract(clock + 0.25),
        fract(clock + 0.75)
    )
    let signed = cycle - SIMD4<Float>(repeating: 0.5)
    let firstBlend = smoothstep(
        0.5 - feather,
        0.5 + feather,
        2 * abs(cycle.x - 0.5)
    )
    let secondBlend = smoothstep(
        0.5 - feather,
        0.5 + feather,
        2 * abs(cycle.z - 0.5)
    )
    var result: [SIMD4<Float>] = []
    result.reserveCapacity(width * height)
    for y in 0 ..< height {
        for x in 0 ..< width {
            let coordinate = SIMD2<Float>(
                (Float(x) + 0.5) / Float(width),
                (Float(y) + 0.5) / Float(height)
            )
            let rawFlow = sampleRG8(
                flow,
                width: flowWidth,
                height: flowHeight,
                coordinate: coordinate
            )
            let vector = 2 * (rawFlow - SIMD2<Float>(repeating: 0.498))
            let offset = 0.1 * magnitude * vector
            let base = sampleColor2D(
                source,
                width: width,
                height: height,
                coordinate: coordinate,
                linear: linearSource
            )
            func shifted(_ amount: Float) -> SIMD4<Float> {
                sampleColor2D(
                    source,
                    width: width,
                    height: height,
                    coordinate: coordinate + offset * amount,
                    linear: linearSource
                )
            }
            let firstStart = shifted(signed.x)
            let first = firstStart
                + firstBlend * (shifted(signed.y) - firstStart)
            let secondStart = shifted(signed.z)
            let second = secondStart
                + secondBlend * (shifted(signed.w) - secondStart)
            let phaseValue = sampleR8(
                phase,
                width: phaseWidth,
                height: phaseHeight,
                coordinate: coordinate * phaseTiling,
                repeats: true
            )
            let selector = smoothstep(0.2, 0.8, phaseValue)
            let displaced = first + selector * (second - first)
            let rawAmount = simd_length(vector)
            let flowAmount = saturatesFlowAmount ? min(1, rawAmount) : rawAmount
            result.append(base + flowAmount * (displaced - base))
        }
    }
    return quantized(result)
}

private func excessCentroid(
    _ values: [UInt8],
    width: Int,
    height: Int,
    channel: Int,
    baseline: UInt8
) -> SIMD2<Float>? {
    var weighted = SIMD2<Float>(repeating: 0)
    var total: Float = 0
    for y in 0 ..< height {
        for x in 0 ..< width {
            let value = values[(y * width + x) * 4 + channel]
            let weight = Float(max(0, Int(value) - Int(baseline)))
            weighted += weight * SIMD2(Float(x), Float(y))
            total += weight
        }
    }
    return total > 0 ? weighted / total : nil
}

private func positiveDeltaCentroid(
    output: [UInt8],
    baseline: [UInt8],
    width: Int,
    height: Int
) -> SIMD2<Float>? {
    guard output.count == baseline.count else { return nil }
    var weighted = SIMD2<Float>(repeating: 0)
    var total: Float = 0
    for y in 0 ..< height {
        for x in 0 ..< width {
            let start = (y * width + x) * 4
            let weight = Float((0 ..< 3).reduce(0) { partial, component in
                partial + max(
                    0,
                    Int(output[start + component]) - Int(baseline[start + component])
                )
            })
            weighted += weight * SIMD2(Float(x), Float(y))
            total += weight
        }
    }
    return total > 0 ? weighted / total : nil
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

        // Four distinct quadrants keep a vertically mirrored pass from
        // satisfying a set-of-colors assertion.
        let color: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 0, 255,
        ]
        let authoredTexture = texture(device: device, fill: color)
        let whiteMask = texture(
            device: device,
            fill: [UInt8](repeating: 255, count: 16)
        )
        let baseline = program(
            device: device,
            marker: 1,
            outputSlot: 3,
            slot0Texture: authoredTexture,
            slot3Texture: whiteMask
        )!
        let rgbaTarget = target(device: device)
        let first = encoder.prepare(program: baseline, target: rgbaTarget)
        let attemptsAfterFirst = encoder.pipelineCompilationAttemptCount
        let second = encoder.prepare(program: baseline, target: rgbaTarget)
        let pipelineCacheReused = second != nil
            && encoder.pipelineCompilationAttemptCount == attemptsAfterFirst

        let changedSampling = program(
            device: device,
            marker: 2,
            outputSlot: 3,
            slot3Sampling: .init(texFlags: 3)
        )!
        let samplingVariant = encoder.prepare(
            program: changedSampling,
            target: rgbaTarget
        )
        let cacheReusedAcrossResources = encoder.pipelineCompilationAttemptCount == 1

        var encoded = false
        var gpuCompleted = false
        var outputMatches = false
        var committedBufferRejected = false
        if let first, let command = queue.makeCommandBuffer() {
            encoded = encoder.encode(first, commandBuffer: command)
            command.commit()
            command.waitUntilCompleted()
            gpuCompleted = command.status == .completed && command.error == nil
            committedBufferRejected = !encoder.encode(
                first,
                commandBuffer: command
            )
            outputMatches = pixels(rgbaTarget) == color
        }

        let bgraTarget = target(device: device, format: .bgra8Unorm)
        let bgraPrepared = encoder.prepare(program: baseline, target: bgraTarget)
        let separateFormatPipeline = bgraPrepared != nil
            && encoder.pipelineCompilationAttemptCount == 2

        let straight = program(
            device: device,
            marker: 3,
            outputSlot: 0,
            slot0Content: .color(.resolved(.straightAlpha)),
            slot0Purpose: .straightAlbedo
        )!
        let attemptsBeforeColorGate = encoder.pipelineCompilationAttemptCount
        let straightRejected = encoder.prepare(
            program: straight,
            target: rgbaTarget
        ) == nil && encoder.pipelineCompilationAttemptCount == attemptsBeforeColorGate
        let unresolvedRejectedUpstream = program(
            device: device,
            marker: 4,
            outputSlot: 0,
            unresolved: true
        ) == nil

        let aliasTexture = target(device: device)
        let aliasProgram = program(
            device: device,
            marker: 5,
            outputSlot: 0,
            slot0Texture: aliasTexture
        )!
        let aliasRejected = encoder.prepare(
            program: aliasProgram,
            target: aliasTexture
        ) == nil

        let shortGraphTexture = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [32, 64, 96, 128]
        )
        let shortGraph = program(
            device: device,
            marker: 6,
            outputSlot: 0,
            slot0Texture: shortGraphTexture
        )!
        let crossExtentTarget = target(device: device)
        let crossExtentPrepared = encoder.prepare(
            program: shortGraph,
            target: crossExtentTarget
        )
        var crossExtentEncoded = false
        var crossExtentGPUCompleted = false
        var crossExtentOutputMatches = false
        if let crossExtentPrepared, let command = queue.makeCommandBuffer() {
            crossExtentEncoded = encoder.encode(
                crossExtentPrepared,
                commandBuffer: command
            )
            command.commit()
            command.waitUntilCompleted()
            crossExtentGPUCompleted = command.status == .completed
                && command.error == nil
            let output = pixels(crossExtentTarget)
            crossExtentOutputMatches = stride(from: 0, to: 16, by: 4)
                .allSatisfy { Array(output[$0 ..< $0 + 4]) == [32, 64, 96, 128] }
        }

        let premultipliedPixel = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [64, 32, 16, 128]
        )
        let straightCases: [(Float, [UInt8])] = [
            (0.0, [0, 0, 0, 0]),
            (0.5, [32, 16, 8, 64]),
            (1.0, [64, 32, 16, 128]),
        ]
        var straightBoundaryPrepared = true
        var straightBoundaryGPUCompleted = true
        var straightBoundaryPixelsMatch = true
        var straightBoundaryPremultiplied = true
        for (index, testCase) in straightCases.enumerated() {
            let straightProgram = program(
                device: device,
                marker: 20 + index,
                outputSlot: 0,
                slot0Texture: premultipliedPixel,
                slot3Content: .data,
                slot3Purpose: .mask,
                fragmentSource: straightAlphaFragment,
                gain: testCase.0
            )!
            let output = target(device: device, width: 1, height: 1)
            guard let prepared = encoder.prepare(program: straightProgram, target: output),
                  prepared.fragmentOutput == .premultipliedAlpha,
                  let command = queue.makeCommandBuffer() else {
                straightBoundaryPrepared = false
                continue
            }
            guard encoder.encode(prepared, commandBuffer: command) else {
                straightBoundaryPrepared = false
                continue
            }
            command.commit()
            command.waitUntilCompleted()
            straightBoundaryGPUCompleted = straightBoundaryGPUCompleted
                && command.status == .completed
                && command.error == nil
            let actual = pixels(output)
            straightBoundaryPixelsMatch = straightBoundaryPixelsMatch
                && zip(actual, testCase.1).allSatisfy {
                    abs(Int($0.0) - Int($0.1)) <= 1
                }
            straightBoundaryPremultiplied = straightBoundaryPremultiplied
                && actual[0] <= actual[3]
                && actual[1] <= actual[3]
                && actual[2] <= actual[3]
        }

        let factoredAlphaProgram = program(
            device: device,
            marker: 29,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            fragmentSource: straightRGBFactoredAlphaFragment,
            gain: 0.5
        )
        let factoredAlphaResult = render(
            factoredAlphaProgram,
            encoder: encoder,
            queue: queue,
            target: target(device: device, width: 1, height: 1)
        )
        let factoredAlphaPixelsMatch = closePixels(
            factoredAlphaResult.pixels,
            [32, 16, 8, 64]
        )

        let scanlineUniforms = [
            "g_Weight": bytes(Float(0.5)),
            "g_Tint": bytes(SIMD3<Float>(1, 0, 0)),
        ]
        let scanlineProgram = program(
            device: device,
            marker: 31,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            fragmentSource: scanlineUniformRGBMixFragment,
            uniformValues: scanlineUniforms,
            slot0GraphKind: .layerSource
        )
        let scanlineResult = render(
            scanlineProgram,
            encoder: encoder,
            queue: queue,
            target: target(device: device, width: 1, height: 1)
        )
        // Stored source [64, 32, 16, 128] represents straight
        // [0.5, 0.25, 0.125, 0.5]. A 50% mix with straight red produces
        // [0.75, 0.125, 0.0625] before the final premultiply.
        let scanlinePixelsMatch = closePixels(
            scanlineResult.pixels,
            [96, 16, 8, 128]
        )

        let scanlineIdentityProgram = program(
            device: device,
            marker: 32,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            fragmentSource: scanlineUniformRGBMixFragment,
            uniformValues: [
                "g_Weight": bytes(Float(0)),
                "g_Tint": bytes(SIMD3<Float>(0, 1, 0)),
            ],
            slot0GraphKind: .layerSource
        )
        let scanlineIdentityResult = render(
            scanlineIdentityProgram,
            encoder: encoder,
            queue: queue,
            target: target(device: device, width: 1, height: 1)
        )
        let scanlineIdentityMatches = closePixels(
            scanlineIdentityResult.pixels,
            [64, 32, 16, 128]
        )

        let scalarNoise = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [128, 0, 0, 255]
        )
        let scalarNoiseSlot = slot(
            device: device,
            index: 1,
            texture: scalarNoise,
            content: .data,
            purpose: .noise,
            sampling: .init(texFlags: 3),
            marker: 29
        )
        let scalarAlphaUniforms = [
            "g_Time": bytes(Float(0)),
            "g_Amount": bytes(Float(1)),
            "g_NoiseAmount": bytes(Float(0.5)),
            "g_Power": bytes(Float(1)),
        ]
        let scalarAlphaProgram = program(
            device: device,
            marker: 28,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            slot3Texture: texture(
                device: device, width: 1, height: 1, fill: [0, 0, 0, 255]
            ),
            slot3Content: .data,
            slot3Purpose: .mask,
            fragmentSource: straightRGBScalarAlphaFragment,
            additionalSlots: [scalarNoiseSlot],
            uniformValues: scalarAlphaUniforms
        )
        let scalarAlphaResult = render(
            scalarAlphaProgram,
            encoder: encoder,
            queue: queue,
            target: target(device: device, width: 1, height: 1)
        )
        let scalarAlphaPixelsMatch = closePixels(
            scalarAlphaResult.pixels,
            [48, 24, 12, 96]
        )
        let scalarNoiseColorSlot = slot(
            device: device,
            index: 1,
            texture: scalarNoise,
            content: .color(.resolved(.premultipliedAlpha)),
            purpose: .premultipliedColor,
            sampling: .init(texFlags: 3),
            marker: 30
        )
        let scalarAlphaColorAuxiliaryRejected = program(
            device: device,
            marker: 27,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            slot3Texture: texture(
                device: device, width: 1, height: 1, fill: [0, 0, 0, 255]
            ),
            slot3Content: .data,
            slot3Purpose: .mask,
            fragmentSource: straightRGBScalarAlphaFragment,
            additionalSlots: [scalarNoiseColorSlot],
            uniformValues: scalarAlphaUniforms
        ) == nil

        let maskPixel = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [128, 0, 0, 255]
        )
        let maskedProgram = program(
            device: device,
            marker: 30,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            slot3Texture: maskPixel,
            slot3Content: .data,
            slot3Purpose: .mask,
            fragmentSource: maskedAlphaFragment,
            gain: 0.5
        )
        let secondColorRejected = program(
            device: device,
            marker: 31,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            slot3Texture: maskPixel,
            slot3Content: .color(.resolved(.straightAlpha)),
            slot3Purpose: .straightAlbedo,
            fragmentSource: maskedAlphaFragment,
            gain: 0.5
        ) == nil
        var maskedBoundaryPrepared = false
        var maskedBoundaryGPUCompleted = false
        var maskedBoundaryPixelsMatch = false
        let maskedTarget = target(device: device, width: 1, height: 1)
        if let maskedProgram,
           let prepared = encoder.prepare(program: maskedProgram, target: maskedTarget),
           let command = queue.makeCommandBuffer() {
            maskedBoundaryPrepared = prepared.fragmentOutput == .premultipliedAlpha
            if encoder.encode(prepared, commandBuffer: command) {
                command.commit()
                command.waitUntilCompleted()
                maskedBoundaryGPUCompleted = command.status == .completed
                    && command.error == nil
                maskedBoundaryPixelsMatch = zip(
                    pixels(maskedTarget), [UInt8(16), 8, 4, 32]
                ).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 1 }
            }
        }

        let overlayBase = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [128, 0, 0, 128]
        )
        let overlayData = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [0, 255, 0, 64]
        )
        let overlayDataSlot = slot(
            device: device,
            index: 1,
            texture: overlayData,
            content: .data,
            purpose: .preservedChannels,
            sampling: .directImageFallback,
            marker: 41
        )
        let overlayProgram = program(
            device: device,
            marker: 40,
            outputSlot: 0,
            slot0Texture: overlayBase,
            fragmentSource: overlayAlphaBlendFragment,
            additionalSlots: [overlayDataSlot],
            uniformValues: [
                "g_Multiply": bytes(Float(0.5)),
                "g_AlphaMultiply": bytes(Float(0.5)),
            ]
        )
        let overlayColorSlot = slot(
            device: device,
            index: 1,
            texture: overlayData,
            content: .color(.resolved(.premultipliedAlpha)),
            purpose: .premultipliedColor,
            sampling: .directImageFallback,
            marker: 42
        )
        let overlayColorRejected = program(
            device: device,
            marker: 43,
            outputSlot: 0,
            slot0Texture: overlayBase,
            fragmentSource: overlayAlphaBlendFragment,
            additionalSlots: [overlayColorSlot],
            uniformValues: [
                "g_Multiply": bytes(Float(0.5)),
                "g_AlphaMultiply": bytes(Float(0.5)),
            ]
        ) == nil
        let overlayResult = render(
            overlayProgram,
            encoder: encoder,
            queue: queue,
            target: target(device: device, width: 1, height: 1)
        )
        let overlayBoundaryPixelsMatch = closePixels(
            overlayResult.pixels,
            [28, 4, 0, 32]
        )

        let filterInputBytes: [UInt8] = [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 128, 64, 32, 128, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ]
        let filterInput = texture(
            device: device,
            width: 3,
            height: 3,
            fill: filterInputBytes
        )
        let whiteFilterMask = texture(
            device: device,
            width: 3,
            height: 3,
            fill: [UInt8](repeating: 255, count: 36)
        )
        let whiteFilterMaskSlot = slot(
            device: device,
            index: 1,
            texture: whiteFilterMask,
            content: .data,
            purpose: .mask,
            sampling: .init(texFlags: 3),
            marker: 51
        )
        let wholeFilterProgram = program(
            device: device,
            marker: 50,
            outputSlot: 0,
            slot0Texture: filterInput,
            fragmentSource: wholeColorFilterFragment,
            additionalSlots: [whiteFilterMaskSlot],
            uniformValues: [
                "g_TexelSize": bytes(SIMD2<Float>(repeating: 1.0 / 3.0)),
                "g_Strength": bytes(Float(1)),
            ],
            slot0Sampling: .init(texFlags: 3),
            slot0GraphKind: .layerSource
        )
        let wholeFilterResult = render(
            wholeFilterProgram,
            encoder: encoder,
            queue: queue,
            target: target(device: device, width: 3, height: 3)
        )
        var wholeFilterExpected = [UInt8](repeating: 0, count: 36)
        wholeFilterExpected.replaceSubrange(
            16 ..< 20,
            with: [UInt8(224), 196, 98, 224]
        )
        let wholeFilterPixelsMatch = closePixels(
            wholeFilterResult.pixels,
            wholeFilterExpected,
            tolerance: 1
        )

        let blackFilterMask = texture(
            device: device,
            width: 3,
            height: 3,
            fill: [UInt8](repeating: 0, count: 36)
        )
        let blackFilterMaskSlot = slot(
            device: device,
            index: 1,
            texture: blackFilterMask,
            content: .data,
            purpose: .mask,
            sampling: .init(texFlags: 3),
            marker: 53
        )
        let wholeFilterBlackMaskProgram = program(
            device: device,
            marker: 52,
            outputSlot: 0,
            slot0Texture: filterInput,
            fragmentSource: wholeColorFilterFragment,
            additionalSlots: [blackFilterMaskSlot],
            uniformValues: [
                "g_TexelSize": bytes(SIMD2<Float>(repeating: 1.0 / 3.0)),
                "g_Strength": bytes(Float(1)),
            ],
            slot0Sampling: .init(texFlags: 3),
            slot0GraphKind: .layerSource
        )
        let wholeFilterBlackMaskResult = render(
            wholeFilterBlackMaskProgram,
            encoder: encoder,
            queue: queue,
            target: target(device: device, width: 3, height: 3)
        )
        let wholeFilterBlackMaskIdentity = closePixels(
            wholeFilterBlackMaskResult.pixels,
            filterInputBytes,
            tolerance: 1
        )

        let flowRate: Float = 0.33
        let flowMagnitude: Float = 0.45
        let flowFeather: Float = 0.159
        let phaseTiling: Float = 2
        let flow2DWidth = 48
        let flow2DHeight = 36
        var flow2DSourceBytes: [UInt8] = []
        flow2DSourceBytes.reserveCapacity(flow2DWidth * flow2DHeight * 4)
        for y in 0 ..< flow2DHeight {
            for x in 0 ..< flow2DWidth {
                let primary = max(
                    0,
                    140 - 18 * abs(x - 27) - 22 * abs(y - 17)
                )
                let tail = max(
                    0,
                    72 - 20 * abs(x - 20) - 24 * abs(y - 22)
                )
                let alpha = 96 + (7 * x + 11 * y) % 160
                let red = min(240, 20 + primary + tail / 2)
                let green = min(220, 12 + primary / 3 + tail)
                let blue = min(180, 8 + primary / 5 + tail / 2)
                flow2DSourceBytes.append(contentsOf: [
                    UInt8(red * alpha / 255),
                    UInt8(green * alpha / 255),
                    UInt8(blue * alpha / 255),
                    UInt8(alpha),
                ])
            }
        }
        let flow2DSource = texture(
            device: device,
            width: flow2DWidth,
            height: flow2DHeight,
            fill: flow2DSourceBytes
        )
        let flow2DRaw = Array(
            repeating: [UInt8(255), UInt8(224)],
            count: flow2DWidth * flow2DHeight
        ).flatMap { $0 }
        let flow2DMap = texture(
            device: device,
            format: .rg8Unorm,
            width: flow2DWidth,
            height: flow2DHeight,
            fill: flow2DRaw
        )
        let flow2DPhaseWidth = 2
        let flow2DPhaseHeight = 2
        let flow2DPhaseBytes = [UInt8](repeating: 0, count: 4)
        let flow2DPhase = texture(
            device: device,
            format: .r8Unorm,
            width: flow2DPhaseWidth,
            height: flow2DPhaseHeight,
            fill: flow2DPhaseBytes
        )
        let flow2DSlot = slot(
            device: device,
            index: 1,
            texture: flow2DMap,
            content: .data,
            purpose: .flow,
            sampling: .init(texFlags: 2),
            marker: 60
        )
        let flow2DPhaseSlot = slot(
            device: device,
            index: 2,
            texture: flow2DPhase,
            content: .data,
            purpose: .phase,
            sampling: .init(texFlags: 0),
            marker: 61
        )
        func flow2DProgram(marker: Int, time: Float) -> Program? {
            program(
                device: device,
                marker: marker,
                outputSlot: 0,
                slot0Texture: flow2DSource,
                fragmentSource: boundedFlowFragment,
                additionalSlots: [flow2DSlot, flow2DPhaseSlot],
                uniformValues: [
                    "g_Time": bytes(time),
                    "g_Rate": bytes(flowRate),
                    "g_Magnitude": bytes(flowMagnitude),
                    "g_Feather": bytes(flowFeather),
                    "g_PhaseTiling": bytes(phaseTiling),
                ],
                slot0Sampling: .init(texFlags: 2)
            )
        }
        let flow2DClock: Float = 0.16
        let flow2DTime = flow2DClock / flowRate
        let flow2DOtherTime: Float = 0.39 / flowRate
        let flow2DAtTime = render(
            flow2DProgram(marker: 62, time: flow2DTime),
            encoder: encoder,
            queue: queue,
            target: target(
                device: device,
                width: flow2DWidth,
                height: flow2DHeight
            )
        )
        let flow2DAtOtherTime = render(
            flow2DProgram(marker: 63, time: flow2DOtherTime),
            encoder: encoder,
            queue: queue,
            target: target(
                device: device,
                width: flow2DWidth,
                height: flow2DHeight
            )
        )
        let expectedFlow2D = flowOracle2D(
            source: flow2DSourceBytes,
            width: flow2DWidth,
            height: flow2DHeight,
            flow: flow2DRaw,
            flowWidth: flow2DWidth,
            flowHeight: flow2DHeight,
            phase: flow2DPhaseBytes,
            phaseWidth: flow2DPhaseWidth,
            phaseHeight: flow2DPhaseHeight,
            time: flow2DTime,
            rate: flowRate,
            magnitude: flowMagnitude,
            feather: flowFeather,
            phaseTiling: phaseTiling
        )
        let expectedOtherFlow2D = flowOracle2D(
            source: flow2DSourceBytes,
            width: flow2DWidth,
            height: flow2DHeight,
            flow: flow2DRaw,
            flowWidth: flow2DWidth,
            flowHeight: flow2DHeight,
            phase: flow2DPhaseBytes,
            phaseWidth: flow2DPhaseWidth,
            phaseHeight: flow2DPhaseHeight,
            time: flow2DOtherTime,
            rate: flowRate,
            magnitude: flowMagnitude,
            feather: flowFeather,
            phaseTiling: phaseTiling
        )
        let saturatedFlow2D = flowOracle2D(
            source: flow2DSourceBytes,
            width: flow2DWidth,
            height: flow2DHeight,
            flow: flow2DRaw,
            flowWidth: flow2DWidth,
            flowHeight: flow2DHeight,
            phase: flow2DPhaseBytes,
            phaseWidth: flow2DPhaseWidth,
            phaseHeight: flow2DPhaseHeight,
            time: flow2DTime,
            rate: flowRate,
            magnitude: flowMagnitude,
            feather: flowFeather,
            phaseTiling: phaseTiling,
            saturatesFlowAmount: true
        )
        let flow2DVector = 2 * (
            SIMD2<Float>(1, Float(224) / 255)
                - SIMD2<Float>(repeating: 0.498)
        )
        // At clock 0.16 the blend selects the +0.16 cycle. The shader samples
        // source UV in +F, so the visible authored feature must move toward -F.
        let flow2DSampleOffset = 0.1 * flowMagnitude * flow2DClock * flow2DVector
        let flow2DSourceCentroid = excessCentroid(
            flow2DSourceBytes,
            width: flow2DWidth,
            height: flow2DHeight,
            channel: 0,
            baseline: 20
        )
        let flow2DOutputCentroid = excessCentroid(
            flow2DAtTime.pixels,
            width: flow2DWidth,
            height: flow2DHeight,
            channel: 0,
            baseline: 20
        )
        let flow2DVisibleShift = if let source = flow2DSourceCentroid,
                                    let output = flow2DOutputCentroid {
            output - source
        } else {
            SIMD2<Float>(repeating: 0)
        }
        let flow2DMatchesOracle = closePixels(
            flow2DAtTime.pixels,
            expectedFlow2D
        ) && closePixels(flow2DAtOtherTime.pixels, expectedOtherFlow2D)
        let flow2DRejectsWrongOracle = !closePixels(
            flow2DAtTime.pixels,
            saturatedFlow2D
        )
        let flow2DTimeChanges = flow2DAtTime.pixels != flow2DAtOtherTime.pixels
        let flow2DAlphaMoves = stride(
            from: 3, to: flow2DSourceBytes.count, by: 4
        ).contains { flow2DAtTime.pixels[$0] != flow2DSourceBytes[$0] }
        let flow2DDirection = flow2DVector.x > 0 && flow2DVector.y > 0
            && simd_length(flow2DVector) > 1
            && flow2DSampleOffset.x > 0 && flow2DSampleOffset.y > 0
            && flow2DVisibleShift.x < -0.05
            && flow2DVisibleShift.y < -0.05
        let boundedFlow2DPixels = flow2DMatchesOracle
            && flow2DRejectsWrongOracle
            && flow2DTimeChanges
            && flow2DAlphaMoves
            && flow2DDirection

        let shimmerSpeed: Float = 0.18
        let shimmerAmount: Float = 1.51
        let shimmerDirection: Float = 0.13290171
        let shimmerGranularity: Float = 1
        let shimmerDelay: Float = 1.04
        let shimmerColor = SIMD3<Float>(repeating: 1)
        let shimmer2DWidth = 64
        let shimmer2DHeight = 64
        let shimmer2DSourcePixel = [UInt8(48), 36, 24, 160]
        let shimmer2DSourceBytes = Array(
            repeating: shimmer2DSourcePixel,
            count: shimmer2DWidth * shimmer2DHeight
        ).flatMap { $0 }
        let shimmer2DSource = texture(
            device: device,
            width: shimmer2DWidth,
            height: shimmer2DHeight,
            fill: shimmer2DSourceBytes
        )
        var shimmer2DMaskBytes: [UInt8] = []
        shimmer2DMaskBytes.reserveCapacity(shimmer2DWidth * shimmer2DHeight)
        for y in 0 ..< shimmer2DHeight {
            for x in 0 ..< shimmer2DWidth {
                let dx = (Float(x) - 31) / 25
                let dy = (Float(y) - 30) / 23
                let radial = max(0, 1 - dx * dx - dy * dy)
                let horizontalSkew = 0.88 + 0.12 * Float(x) / 63
                let cutCorner: Float = x < 25 && y < 27 ? 0.78 : 1
                shimmer2DMaskBytes.append(UInt8(
                    (255 * radial * horizontalSkew * cutCorner).rounded()
                ))
            }
        }
        let shimmer2DMask = texture(
            device: device,
            format: .r8Unorm,
            width: shimmer2DWidth,
            height: shimmer2DHeight,
            fill: shimmer2DMaskBytes
        )
        let shimmer2DZeroMask = texture(
            device: device,
            format: .r8Unorm,
            width: shimmer2DWidth,
            height: shimmer2DHeight,
            fill: [UInt8](repeating: 0, count: shimmer2DWidth * shimmer2DHeight)
        )
        let shimmer2DGradientWidth = 64
        let shimmer2DGradientHeight = 8
        var shimmer2DGradientBytes: [UInt8] = []
        shimmer2DGradientBytes.reserveCapacity(
            shimmer2DGradientWidth * shimmer2DGradientHeight * 4
        )
        for y in 0 ..< shimmer2DGradientHeight {
            for x in 0 ..< shimmer2DGradientWidth {
                let u = (Float(x) + 0.5) / Float(shimmer2DGradientWidth)
                let peak: Float = 0.35
                let distance = u < peak
                    ? (peak - u) / 0.055
                    : (u - peak) / 0.09
                let band = max(0, 1 - distance)
                let rowScale = 0.86
                    + 0.14 * Float(y) / Float(shimmer2DGradientHeight - 1)
                shimmer2DGradientBytes.append(contentsOf: [
                    UInt8((255 * band * rowScale).rounded()),
                    UInt8((220 * band * rowScale).rounded()),
                    UInt8((180 * band * rowScale).rounded()),
                    255,
                ])
            }
        }
        let shimmer2DGradient = texture(
            device: device,
            width: shimmer2DGradientWidth,
            height: shimmer2DGradientHeight,
            fill: shimmer2DGradientBytes
        )
        let shimmer2DMaskSlot = slot(
            device: device,
            index: 1,
            texture: shimmer2DMask,
            content: .data,
            purpose: .mask,
            sampling: .init(texFlags: 2),
            marker: 70
        )
        let shimmer2DZeroMaskSlot = slot(
            device: device,
            index: 1,
            texture: shimmer2DZeroMask,
            content: .data,
            purpose: .mask,
            sampling: .init(texFlags: 2),
            marker: 73
        )
        func shimmer2DProgram(
            marker: Int,
            time: Float,
            maskSlot: Program.TextureSlot
        ) -> Program? {
            program(
                device: device,
                marker: marker,
                outputSlot: 0,
                slot0Texture: shimmer2DSource,
                slot3Texture: shimmer2DGradient,
                slot3Content: .data,
                slot3Purpose: .preservedChannels,
                slot3Sampling: .init(texFlags: 2),
                fragmentSource: boundedShimmerFragment,
                additionalSlots: [maskSlot],
                uniformValues: [
                    "g_Time": bytes(time),
                    "g_Speed": bytes(shimmerSpeed),
                    "g_Amount": bytes(shimmerAmount),
                    "g_Direction": bytes(shimmerDirection),
                    "g_Granularity": bytes(shimmerGranularity),
                    "g_Delay": bytes(shimmerDelay),
                    "g_Color": bytes(shimmerColor),
                ],
                slot0Sampling: .init(texFlags: 2)
            )
        }
        let shimmer2DFirstTime: Float = 4
        let shimmer2DSecondTime: Float = 4.4
        let shimmer2DFirst = render(
            shimmer2DProgram(
                marker: 71,
                time: shimmer2DFirstTime,
                maskSlot: shimmer2DMaskSlot
            ),
            encoder: encoder,
            queue: queue,
            target: target(
                device: device,
                width: shimmer2DWidth,
                height: shimmer2DHeight
            )
        )
        let shimmer2DSecond = render(
            shimmer2DProgram(
                marker: 72,
                time: shimmer2DSecondTime,
                maskSlot: shimmer2DMaskSlot
            ),
            encoder: encoder,
            queue: queue,
            target: target(
                device: device,
                width: shimmer2DWidth,
                height: shimmer2DHeight
            )
        )
        let shimmer2DZeroMaskOutput = render(
            shimmer2DProgram(
                marker: 73,
                time: shimmer2DFirstTime,
                maskSlot: shimmer2DZeroMaskSlot
            ),
            encoder: encoder,
            queue: queue,
            target: target(
                device: device,
                width: shimmer2DWidth,
                height: shimmer2DHeight
            )
        )
        let shimmer2DFirstCentroid = positiveDeltaCentroid(
            output: shimmer2DFirst.pixels,
            baseline: shimmer2DSourceBytes,
            width: shimmer2DWidth,
            height: shimmer2DHeight
        )
        let shimmer2DSecondCentroid = positiveDeltaCentroid(
            output: shimmer2DSecond.pixels,
            baseline: shimmer2DSourceBytes,
            width: shimmer2DWidth,
            height: shimmer2DHeight
        )
        let shimmer2DCentroidShift = if let first = shimmer2DFirstCentroid,
                                        let second = shimmer2DSecondCentroid {
            second - first
        } else {
            SIMD2<Float>(repeating: 0)
        }
        let shimmer2DAlphaPreserved = stride(
            from: 3,
            to: shimmer2DSourceBytes.count,
            by: 4
        ).allSatisfy {
            shimmer2DFirst.pixels[$0] == shimmer2DSourceBytes[$0]
                && shimmer2DSecond.pixels[$0] == shimmer2DSourceBytes[$0]
        }
        let shimmer2DMaskAsymmetric = shimmer2DMaskBytes[20 * shimmer2DWidth + 20]
            != shimmer2DMaskBytes[20 * shimmer2DWidth + 43]
        let shimmer2DGradientAsymmetric = shimmer2DGradientBytes[
            (shimmer2DGradientWidth / 3) * 4
        ] != shimmer2DGradientBytes[
            ((shimmer2DGradientHeight - 1) * shimmer2DGradientWidth
                + shimmer2DGradientWidth / 3) * 4
        ]
        // The fullscreen wrapper maps increasing texture v to increasing
        // readback rows. For the current +v convention the authored linear
        // band therefore moves mostly down and slightly left as time advances.
        let boundedShimmer2DCentroid = shimmer2DMaskAsymmetric
            && shimmer2DGradientAsymmetric
            && shimmer2DFirst.pixels != shimmer2DSourceBytes
            && shimmer2DSecond.pixels != shimmer2DSourceBytes
            && shimmer2DFirst.pixels != shimmer2DSecond.pixels
            && shimmer2DAlphaPreserved
            && shimmer2DZeroMaskOutput.pixels == shimmer2DSourceBytes
            && shimmer2DCentroidShift.x < -0.05
            && shimmer2DCentroidShift.y > 0.25
            && shimmer2DCentroidShift.y > 3 * abs(shimmer2DCentroidShift.x)

        let r8Target = target(device: device, format: .r8Unorm)
        let formatRejected = encoder.prepare(
            program: baseline,
            target: r8Target
        ) == nil
        let explicitScalarPreparation = encoder.prepareResult(
            program: baseline,
            target: r8Target,
            attachmentStorage: .scalarRedUnorm
        )
        var scalarProducerEncoded = false
        var scalarProducerCompleted = false
        var scalarProducerRedStorage = false
        if case let .success(prepared) = explicitScalarPreparation,
           let command = queue.makeCommandBuffer() {
            scalarProducerEncoded = encoder.encode(prepared, commandBuffer: command)
            command.commit()
            command.waitUntilCompleted()
            scalarProducerCompleted = command.status == .completed
                && command.error == nil
            scalarProducerRedStorage = scalarPixels(r8Target) == [255, 0, 0, 255]
        }
        let scalarConsumerFragment = """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            float scalar = texSample2D(g_Texture0, v_TexCoord).r;
            gl_FragColor = vec4(scalar, scalar, scalar, 1.0);
        }
        """
        let scalarConsumer = program(
            device: device,
            marker: 74,
            outputSlot: 0,
            slot0Texture: r8Target,
            slot0Content: .scalarRedUnorm,
            slot0Purpose: .preservedChannels,
            fragmentSource: scalarConsumerFragment
        )
        let scalarOutput = target(device: device)
        let scalarRoundTrip = render(
            scalarConsumer,
            encoder: encoder,
            queue: queue,
            target: scalarOutput
        )
        let scalarRoundTripExpected: [UInt8] = [
            255, 255, 255, 255,
            0, 0, 0, 255,
            0, 0, 0, 255,
            255, 255, 255, 255,
        ]
        let scalarWholeVectorRejectedUpstream = program(
            device: device,
            marker: 75,
            outputSlot: 0,
            slot0Texture: r8Target,
            slot0Content: .scalarRedUnorm,
            slot0Purpose: .preservedChannels,
            fragmentSource: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            void main() {
                gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
            }
            """
        ) == nil
        let scalarGreenRejectedUpstream = program(
            device: device,
            marker: 76,
            outputSlot: 0,
            slot0Texture: r8Target,
            slot0Content: .scalarRedUnorm,
            slot0Purpose: .preservedChannels,
            fragmentSource: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            void main() {
                float scalar = texSample2D(g_Texture0, v_TexCoord).g;
                gl_FragColor = vec4(scalar, scalar, scalar, 1.0);
            }
            """
        ) == nil
        let scalarAliasRejectedUpstream = program(
            device: device,
            marker: 77,
            outputSlot: 0,
            slot0Texture: r8Target,
            slot0Content: .scalarRedUnorm,
            slot0Purpose: .preservedChannels,
            fragmentSource: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            void main() {
                vec4 sampleValue = texSample2D(g_Texture0, v_TexCoord);
                float scalar = sampleValue.r;
                gl_FragColor = vec4(scalar, scalar, scalar, 1.0);
            }
            """
        ) == nil
        let scalarIntoColorTargetRejected: Bool
        if case .failure(.targetRejected) = encoder.prepareResult(
            program: baseline,
            target: rgbaTarget,
            attachmentStorage: .scalarRedUnorm
        ) {
            scalarIntoColorTargetRejected = true
        } else {
            scalarIntoColorTargetRejected = false
        }
        let readOnlyTarget = target(device: device, usage: .shaderRead)
        let missingRenderTargetRejected = encoder.prepare(
            program: baseline,
            target: readOnlyTarget
        ) == nil
        let writeOnlyTarget = target(device: device, usage: .renderTarget)
        let missingShaderReadRejected = encoder.prepare(
            program: baseline,
            target: writeOnlyTarget
        ) == nil

        let noReadTexture = texture(device: device, usage: .renderTarget)
        let inputUsageRejectedUpstream = program(
            device: device,
            marker: 7,
            outputSlot: 0,
            slot0Texture: noReadTexture
        ) == nil
        let malformedUniformRejectedUpstream = program(
            device: device,
            marker: 8,
            outputSlot: 0,
            malformedUniform: true
        ) == nil

        let invalidMetal = program(
            device: device,
            marker: 9,
            outputSlot: 0,
            uniformName: "operator"
        )!
        let attemptsBeforeFailure = encoder.pipelineCompilationAttemptCount
        let firstFailure = encoder.prepare(
            program: invalidMetal,
            target: rgbaTarget
        ) == nil
        let attemptsAfterFailure = encoder.pipelineCompilationAttemptCount
        let secondFailure = encoder.prepare(
            program: invalidMetal,
            target: rgbaTarget
        ) == nil
        let failureNegativeCached = firstFailure
            && secondFailure
            && attemptsAfterFailure == attemptsBeforeFailure + 1
            && encoder.pipelineCompilationAttemptCount == attemptsAfterFailure
            && encoder.failedPipelineCount == 1

        let preparedBeforeReset = second
        encoder.reset()
        let resetClearedCache = encoder.cachedPipelineCount == 0
            && encoder.pipelineCompilationAttemptCount == 0
            && encoder.failedPipelineCount == 0
        var stalePreparedRejected = false
        if let preparedBeforeReset, let staleCommand = queue.makeCommandBuffer() {
            stalePreparedRejected = !encoder.encode(
                preparedBeforeReset,
                commandBuffer: staleCommand
            )
        }
        let preparedAfterReset = encoder.prepare(
            program: baseline,
            target: rgbaTarget
        )

        var crossDeviceExercised = false
        var crossDeviceRejected = true
        if let other = MTLCopyAllDevices().first(where: {
            $0.registryID != device.registryID
        }) {
            crossDeviceExercised = true
            let otherTarget = target(device: other)
            crossDeviceRejected = encoder.prepare(
                program: baseline,
                target: otherTarget
            ) == nil
        }

        let results: [String: Bool] = [
            "metalAvailable": true,
            "prepared": first != nil,
            "pipelineCompiledOnce": attemptsAfterFirst == 1,
            "pipelineCacheReused": pipelineCacheReused,
            "cacheReusedAcrossResources": cacheReusedAcrossResources,
            "authoredSlotsPreserved": first?.bindingSlots == [0, 3],
            "typedSamplersPreserved": first?.bindingSamplings
                == [.directImageFallback, .init(texFlags: 1)],
            "uniformLayoutPreserved": first?.uniformByteCount
                == baseline.frontendProgram.uniformLayout.byteSize,
            "baselineOutputPremultiplied": first?.fragmentOutput
                == .premultipliedAlpha,
            "premultipliedOutputPublished": crossExtentPrepared?.fragmentOutput
                == .premultipliedAlpha,
            "commandsEncoded": encoded,
            "gpuCompleted": gpuCompleted,
            "committedCommandBufferRejected": committedBufferRejected,
            "outputMatches": outputMatches,
            "rgbaAndBgraSupported": separateFormatPipeline,
            "straightOutputRejectedBeforeCompile": straightRejected,
            "unresolvedOutputRejectedUpstream": unresolvedRejectedUpstream,
            "inputTargetAliasRejected": aliasRejected,
            "crossExtentGraphPrepared": crossExtentPrepared != nil,
            "crossExtentGraphEncoded": crossExtentEncoded,
            "crossExtentGraphGPUCompleted": crossExtentGPUCompleted,
            "crossExtentGraphOutputMatches": crossExtentOutputMatches,
            "straightBoundaryPrepared": straightBoundaryPrepared,
            "straightBoundaryGPUCompleted": straightBoundaryGPUCompleted,
            "straightBoundaryPixelsMatch": straightBoundaryPixelsMatch,
            "straightBoundaryPremultiplied": straightBoundaryPremultiplied,
            "factoredAlphaPrepared": factoredAlphaResult.prepared,
            "factoredAlphaEncoded": factoredAlphaResult.encoded,
            "factoredAlphaGPUCompleted": factoredAlphaResult.completed,
            "factoredAlphaPixelsMatch": factoredAlphaPixelsMatch,
            "scanlineUniformRGBMixPrepared": scanlineResult.prepared
                && scanlineIdentityResult.prepared,
            "scanlineUniformRGBMixEncoded": scanlineResult.encoded
                && scanlineIdentityResult.encoded,
            "scanlineUniformRGBMixGPUCompleted": scanlineResult.completed
                && scanlineIdentityResult.completed,
            "scanlineUniformRGBMixPixelsMatch": scanlinePixelsMatch,
            "scanlineUniformRGBMixWeightZeroIdentity": scanlineIdentityMatches,
            "scalarAlphaPrepared": scalarAlphaResult.prepared,
            "scalarAlphaEncoded": scalarAlphaResult.encoded,
            "scalarAlphaGPUCompleted": scalarAlphaResult.completed,
            "scalarAlphaPixelsMatch": scalarAlphaPixelsMatch,
            "scalarAlphaColorAuxiliaryRejected": scalarAlphaColorAuxiliaryRejected,
            "maskedBoundaryPrepared": maskedBoundaryPrepared,
            "maskedBoundaryGPUCompleted": maskedBoundaryGPUCompleted,
            "maskedBoundaryPixelsMatch": maskedBoundaryPixelsMatch,
            "secondColorRejected": secondColorRejected,
            "overlayBoundaryPrepared": overlayResult.prepared,
            "overlayBoundaryEncoded": overlayResult.encoded,
            "overlayBoundaryGPUCompleted": overlayResult.completed,
            "overlayBoundaryPixelsMatch": overlayBoundaryPixelsMatch,
            "wholeFilterPrepared": wholeFilterResult.prepared,
            "wholeFilterEncoded": wholeFilterResult.encoded,
            "wholeFilterGPUCompleted": wholeFilterResult.completed,
            "wholeFilterPixelsMatch": wholeFilterPixelsMatch,
            "wholeFilterBlackMaskPrepared": wholeFilterBlackMaskResult.prepared,
            "wholeFilterBlackMaskEncoded": wholeFilterBlackMaskResult.encoded,
            "wholeFilterBlackMaskGPUCompleted": wholeFilterBlackMaskResult.completed,
            "wholeFilterBlackMaskIdentity": wholeFilterBlackMaskIdentity,
            "overlayColorRejectedUpstream": overlayColorRejected,
            "boundedFlow2DPrepared": flow2DAtTime.prepared
                && flow2DAtOtherTime.prepared,
            "boundedFlow2DEncoded": flow2DAtTime.encoded
                && flow2DAtOtherTime.encoded,
            "boundedFlow2DGPUCompleted": flow2DAtTime.completed
                && flow2DAtOtherTime.completed,
            "boundedFlow2DMatchesLinearUnclampedOracle": flow2DMatchesOracle,
            "boundedFlow2DRejectsSaturatedAmount": flow2DRejectsWrongOracle,
            "boundedFlow2DChangesAtNonPeriodTime": flow2DTimeChanges,
            "boundedFlow2DDisplacesAlpha": flow2DAlphaMoves,
            "boundedFlow2DSamplesPlusFAndMovesVisibleMinusF": flow2DDirection,
            "boundedFlow2DPixelsMatch": boundedFlow2DPixels,
            "boundedShimmer2DPrepared": shimmer2DFirst.prepared
                && shimmer2DSecond.prepared && shimmer2DZeroMaskOutput.prepared,
            "boundedShimmer2DEncoded": shimmer2DFirst.encoded
                && shimmer2DSecond.encoded && shimmer2DZeroMaskOutput.encoded,
            "boundedShimmer2DGPUCompleted": shimmer2DFirst.completed
                && shimmer2DSecond.completed && shimmer2DZeroMaskOutput.completed,
            "boundedShimmer2DZeroMaskIdentity": shimmer2DZeroMaskOutput.pixels
                == shimmer2DSourceBytes,
            "boundedShimmer2DDownLeftCentroid": boundedShimmer2DCentroid,
            "targetFormatRejected": formatRejected,
            "scalarProducerPreparedExplicitly": {
                if case let .success(prepared) = explicitScalarPreparation {
                    return prepared.storedContent == .scalarRedUnorm
                }
                return false
            }(),
            "scalarProducerEncoded": scalarProducerEncoded,
            "scalarProducerGPUCompleted": scalarProducerCompleted,
            "scalarProducerStoresOnlyRed": scalarProducerRedStorage,
            "scalarRedConsumerPrepared": scalarRoundTrip.prepared,
            "scalarRedConsumerEncoded": scalarRoundTrip.encoded,
            "scalarRedConsumerGPUCompleted": scalarRoundTrip.completed,
            "scalarRedRoundTripMatches": scalarRoundTrip.pixels
                == scalarRoundTripExpected,
            "scalarWholeVectorRejectedUpstream": scalarWholeVectorRejectedUpstream,
            "scalarGreenRejectedUpstream": scalarGreenRejectedUpstream,
            "scalarAliasRejectedUpstream": scalarAliasRejectedUpstream,
            "scalarIntoColorTargetRejected": scalarIntoColorTargetRejected,
            "missingRenderTargetRejected": missingRenderTargetRejected,
            "missingShaderReadRejected": missingShaderReadRejected,
            "inputUsageRejectedUpstream": inputUsageRejectedUpstream,
            "uniformMismatchRejectedUpstream": malformedUniformRejectedUpstream,
            "pipelineFailureNegativeCached": failureNegativeCached,
            "resetClearsCache": resetClearedCache,
            "resetInvalidatesPreparedPass": stalePreparedRejected,
            "prepareAfterReset": preparedAfterReset != nil,
            "crossDeviceRejectedWhenAvailable": crossDeviceRejected,
        ]
        let payload: [String: Any] = [
            "results": results,
            "crossDeviceExercised": crossDeviceExercised,
            "flow2DVector": [flow2DVector.x, flow2DVector.y],
            "flow2DSampleOffset": [flow2DSampleOffset.x, flow2DSampleOffset.y],
            "flow2DVisibleShift": [flow2DVisibleShift.x, flow2DVisibleShift.y],
            "shimmer2DCentroidShift": [
                shimmer2DCentroidShift.x,
                shimmer2DCentroidShift.y,
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialPassEncoderTests(unittest.TestCase):
    def test_program_is_prepared_and_encoded_atomically(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-pass-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "resolved-material-pass-test"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    str(support),
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-framework",
                    "CoreGraphics",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        results = payload["results"]
        if not results["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [name for name, passed in results.items() if not passed],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
