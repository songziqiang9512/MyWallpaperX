#!/usr/bin/env python3

"""Atomic R3 Program derivation and cache-identity boundaries."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment+HostFacts.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderBoundedLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderRuntimeLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStaticLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderDeadBindingAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderTextureChannelAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderBuiltInVectorConversion.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVectorConversion.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFunctionSemantics.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVaryingArrayEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter+Translation.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer+Syntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightRGBAlphaFactorAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer+Scalar.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderConditionalAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixGraphAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderWholeVectorAffineParser.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightWholeColorFilterAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightWholeColorFilterAnalyzer+Syntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderOpaqueInputAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderOverlayAlphaBlendAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightBlendOutputAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderIndependentAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPremultipliedOutputAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
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
]


SUPPORT = r'''
import Foundation
import Metal

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable

    var requiresVolumeTexture: Bool { self == .lookupTable }
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material
        case instance
        case userTexture
        case explicitBinding
    }
}

nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored
    case userProperty
    case timeline
    case sceneScript
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

private let passthroughFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Gain;
void main() {
    float uniformProbe = g_Gain;
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
}
"""

private let proceduralOpaqueFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
void main() {
    gl_FragColor = vec4(v_TexCoord, 0.0, 1.0);
}
"""

private let straightAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform float g_Gain;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb, color.a * g_Gain);
}
"""

private let maskedAlphaFragment = """
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

private let opaqueAlphaPreservingFragment = """
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

private let wholeColorFilterFragment = """
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

private func prepared(
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

private func graphIdentity(
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

private func graphRole(
    effectInput: Template.GraphTextureRole = .layerSource
) -> Template.GraphRole {
    .init(
        effectInput: effectInput,
        effectOutput: .effectOutput,
        nodeTarget: .framebuffer,
        bindings: [.init(slot: 0, texture: .framebuffer)]
    )
}

private func makeTexture(_ device: MTLDevice) -> MTLTexture {
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

private func textureSlot(
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
    case let .provider(.system(name)):
        registryIdentity = .system(name)
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

private func data<T>(_ value: T) -> Data {
    var copy = value
    return withUnsafeBytes(of: &copy) { Data($0) }
}

private func resolvedUniforms(
    _ prepared: SceneShaderPreparedProgram,
    gain: Float,
    dynamic: (
        Template.DynamicUniformSource,
        SceneDynamicSource,
        [Template.DynamicUniformControlAttachment]
    )? = nil
) -> [Program.ResolvedUniform] {
    let frontend = SceneAuthoredShaderFrontend.compile(
        vertexSource: prepared.vertex.source,
        fragmentSource: prepared.fragment.source
    ).program!
    return frontend.uniformLayout.fields.map { field in
        switch field.name {
        case "g_Gain":
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
                        controlAttachments: dynamic.2
                    ),
                    encodedValue: data(gain)
                )
            }
            return .init(
                field: field,
                source: .staticValue,
                encodedValue: data(gain)
            )
        case "mwxRenderSize":
            return .init(
                field: field,
                source: .host(.renderSize),
                encodedValue: data(SIMD2<Float>(1920, 1080))
            )
        default:
            fatalError("unexpected field \(field.name)")
        }
    }
}

private func state(
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

private func slots(_ values: Program.TextureSlot...) -> [Program.TextureSlot?] {
    var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    for value in values { result[value.index] = value }
    return result
}

private func replacingSampling(
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

private func assemble(
    prepared shader: SceneShaderPreparedProgram,
    textureSlots: [Program.TextureSlot?],
    gain: Float = 0.25,
    renderState: SceneMaterialRenderState = state(),
    role: Template.GraphRole = graphRole(),
    reverseUniforms: Bool = false,
    dynamic: (
        Template.DynamicUniformSource,
        SceneDynamicSource,
        [Template.DynamicUniformControlAttachment]
    )? = nil
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
        graphRole: role
    ))
}

private func hasStraightAlphaBoundary(_ program: Program?) -> Bool {
    guard let program,
          case .straightAlpha(0) = program.semanticIdentity.shader.colorTransfer else {
        return false
    }
    return program.semanticIdentity.colorContract.fragmentOutput == .premultipliedAlpha
}

private func hasStraightAlphaPreservingBoundary(_ program: Program?) -> Bool {
    guard let program,
          case .straightAlphaPreserving(0) =
            program.semanticIdentity.shader.colorTransfer else {
        return false
    }
    return program.semanticIdentity.colorContract.fragmentOutput
        == .premultipliedAlpha
}

private func hasStraightAlphaUNormBoundary(_ program: Program?) -> Bool {
    guard let program,
          case .straightAlphaUNorm(0) =
            program.semanticIdentity.shader.colorTransfer else {
        return false
    }
    return program.semanticIdentity.colorContract.fragmentOutput
        == .premultipliedAlpha
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let firstPrepared = prepared(revision: "revision-a")
        let firstSlot = textureSlot(device: device)
        let baseline = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot)
        )!
        let proceduralOpaque = assemble(
            prepared: prepared(
                revision: "procedural-opaque",
                fragment: proceduralOpaqueFragment
            ),
            textureSlots: slots()
        )

        let synonymState = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            renderState: state(synonym: true)
        )!
        let changedUniform = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            gain: 0.75
        )!
        let changedRevision = assemble(
            prepared: prepared(revision: "revision-b"),
            textureSlots: slots(firstSlot)
        )!
        let changedGraphRole = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            role: graphRole(effectInput: .effectOutput)
        )!
        let inactiveGraphBinding = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [
                    .init(slot: 0, texture: .framebuffer),
                    .init(slot: 1, texture: .layerSource),
                ]
            )
        )!
        let changedInstance = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(device: device, marker: 99))
        )!

        let missingSlot = assemble(
            prepared: firstPrepared,
            textureSlots: slots()
        ) == nil
        let wrongPurpose = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                expectedPurpose: .straightAlbedo
            ))
        ) == nil
        let mismatchedRegistryIdentity = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                registryIdentityOverride: .system("wrong-provider")
            ))
        ) == nil
        let mismatchedExactGraphIdentity = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                registryIdentityOverride: .graph(graphIdentity(marker: 99))
            ))
        ) == nil
        let reversedUniforms = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            reverseUniforms: true
        ) == nil
        let mismatchedDynamicSource = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            dynamic: (.timeline, .userProperty, [])
        ) == nil
        let authoredFallback = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            dynamic: (.timeline, .authored, [])
        )
        let changedSelectionProvenance = Program.TextureSlot(
            index: firstSlot.index,
            reference: firstSlot.reference,
            registryIdentity: firstSlot.registryIdentity,
            diagnosticSelectionProvenance: .shaderDefault,
            expectedPurpose: firstSlot.expectedPurpose,
            resource: firstSlot.resource
        )
        let provenanceVariant = assemble(
            prepared: firstPrepared,
            textureSlots: slots(changedSelectionProvenance)
        )!
        let authoredClampVariant = assemble(
            prepared: firstPrepared,
            textureSlots: slots(replacingSampling(
                firstSlot,
                with: .init(texFlags: 2)
            ))
        )!
        let unsupportedState = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            renderState: state(blending: "translucent")
        ) == nil
        let mismatchedGraphBinding = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [.init(slot: 0, texture: .layerSource)]
            )
        ) == nil
        let invalidGraphBindingSlot = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [.init(slot: 8, texture: .framebuffer)]
            )
        ) == nil
        let unresolvedPublication = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .color(.unresolved)
            ))
        ) == nil
        let arithmeticPrepared = prepared(
            revision: "unresolved-transfer",
            fragment: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            uniform float g_Gain;
            void main() {
                gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * g_Gain;
            }
            """
        )
        let unresolvedTransfer = assemble(
            prepared: arithmeticPrepared,
            textureSlots: slots(firstSlot)
        ) == nil
        let staleFrontendSchema = assemble(
            prepared: prepared(
                revision: "stale-frontend-schema",
                frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion - 1
            ),
            textureSlots: slots(firstSlot)
        ) == nil

        let straightPrepared = prepared(
            revision: "straight-alpha-boundary",
            fragment: straightAlphaFragment
        )
        let straightPremultiplied = assemble(
            prepared: straightPrepared,
            textureSlots: slots(firstSlot)
        )
        let straightOpaque = assemble(
            prepared: straightPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .color(.resolved(.opaque))
            ))
        )
        let straightInputRejected = assemble(
            prepared: straightPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .color(.resolved(.straightAlpha))
            ))
        ) == nil
        let straightDataRejected = assemble(
            prepared: straightPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .data
            ))
        ) == nil

        let maskedPrepared = prepared(
            revision: "masked-alpha-boundary",
            fragment: maskedAlphaFragment
        )
        let maskSlot = textureSlot(
            device: device,
            slot: 1,
            marker: 41,
            expectedPurpose: .mask,
            publishedPurpose: .mask,
            content: .data,
            reference: .asset(SceneVFSAssetPath("assets/mask.tex")!)
        )
        let maskedDataAccepted = assemble(
            prepared: maskedPrepared,
            textureSlots: slots(firstSlot, maskSlot)
        )
        let maskedColorRejected = assemble(
            prepared: maskedPrepared,
            textureSlots: slots(firstSlot, textureSlot(
                device: device,
                slot: 1,
                marker: 42,
                expectedPurpose: .straightAlbedo,
                publishedPurpose: .straightAlbedo,
                content: .color(.resolved(.straightAlpha)),
                reference: .asset(SceneVFSAssetPath("assets/second-color.tex")!)
            ))
        ) == nil

        let opaqueAlphaPrepared = prepared(
            revision: "opaque-alpha-preserving",
            fragment: opaqueAlphaPreservingFragment
        )
        let opaqueAlphaAccepted = assemble(
            prepared: opaqueAlphaPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .color(.resolved(.opaque))
            ))
        )
        let opaqueAlphaPremultipliedAccepted = assemble(
            prepared: opaqueAlphaPrepared,
            textureSlots: slots(firstSlot)
        )

        let wholeFilterPrepared = prepared(
            revision: "whole-color-unorm-filter",
            fragment: wholeColorFilterFragment
        )
        let wholeFilterAccepted = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                marker: 44,
                graphKind: .layerSource
            ), maskSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .effectOutput,
                bindings: [.init(slot: 0, texture: .layerSource)]
            )
        )
        let wholeFilterColorAuxiliaryRejected = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                marker: 45,
                graphKind: .layerSource
            ), textureSlot(
                device: device,
                slot: 1,
                marker: 43,
                expectedPurpose: .straightAlbedo,
                publishedPurpose: .straightAlbedo,
                content: .color(.resolved(.straightAlpha)),
                reference: .asset(SceneVFSAssetPath("assets/filter-color.tex")!)
            )),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .effectOutput,
                bindings: [.init(slot: 0, texture: .layerSource)]
            )
        ) == nil
        let wholeFilterEffectOutputRejected = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(firstSlot, maskSlot),
            role: graphRole(effectInput: .effectOutput)
        ) == nil
        let wholeFilterFramebufferRejected = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(firstSlot, maskSlot),
            role: graphRole(effectInput: .layerSource)
        ) == nil

        let twoSlotPrepared = prepared(
            revision: "two-color-inputs",
            fragment: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            uniform sampler2D g_Texture1;
            uniform float g_Gain;
            void main() {
                gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
            }
            """
        )
        let secondSlot = textureSlot(
            device: device,
            slot: 1,
            marker: 2,
            expectedPurpose: .straightAlbedo,
            publishedPurpose: .straightAlbedo,
            content: .color(.resolved(.straightAlpha))
        )
        let nonGraphWithGraphBinding = assemble(
            prepared: twoSlotPrepared,
            textureSlots: slots(firstSlot, textureSlot(
                device: device,
                slot: 1,
                marker: 3,
                reference: .asset(SceneVFSAssetPath("assets/color.tex")!)
            )),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [
                    .init(slot: 0, texture: .framebuffer),
                    .init(slot: 1, texture: .layerSource),
                ]
            )
        ) == nil
        let ambiguousFramebufferRepresentation = assemble(
            prepared: twoSlotPrepared,
            textureSlots: slots(firstSlot, secondSlot)
        ) == nil
        let signalSlot = textureSlot(
            device: device,
            content: .color(.resolved(.independentAlphaSignal))
        )
        let compositingProjection = SceneResolvedMaterialProgramDerivation.resolveColor(
            transfer: .independentAlphaSignalCompositing(
                signalSlot: 0,
                colorSlot: 1
            ),
            textureSlots: slots(signalSlot, textureSlot(
                device: device,
                slot: 1,
                marker: 2
            ))
        )

        let padding = Array(baseline.uniformBytes[4 ..< 8])
        let results: [String: Bool] = [
            "metalAvailable": true,
            "baselineAssembled": baseline.textureSlots.count == 8,
            "uniformPaddingZeroed": baseline.uniformBytes.count == 16
                && padding.allSatisfy { $0 == 0 },
            "rawStateSynonymSemantic": baseline.semanticIdentity
                == synonymState.semanticIdentity,
            "rawStateExcludedFromExact": baseline.exactIdentity
                == synonymState.exactIdentity,
            "uniformValueSemanticStable": baseline.semanticIdentity
                == changedUniform.semanticIdentity,
            "uniformValueChangesExact": baseline.exactIdentity
                != changedUniform.exactIdentity,
            "revisionTypedIRSemanticStable": baseline.semanticIdentity
                == changedRevision.semanticIdentity,
            "revisionChangesExact": baseline.exactIdentity
                != changedRevision.exactIdentity,
            "graphRoleChangesSemantic": baseline.semanticIdentity
                != changedGraphRole.semanticIdentity,
            "inactiveGraphBindingExcluded": baseline.semanticIdentity
                == inactiveGraphBinding.semanticIdentity,
            "instanceIdentitySemanticStable": baseline.semanticIdentity
                == changedInstance.semanticIdentity,
            "instanceIdentityChangesExact": baseline.exactIdentity
                != changedInstance.exactIdentity,
            "missingSlotRejected": missingSlot,
            "wrongPurposeRejected": wrongPurpose,
            "mismatchedRegistryIdentityRejected": mismatchedRegistryIdentity,
            "mismatchedExactGraphIdentityRejected": mismatchedExactGraphIdentity,
            "uniformOrderRejected": reversedUniforms,
            "dynamicSourceMismatchRejected": mismatchedDynamicSource,
            "authoredFallbackAccepted": authoredFallback?.exactIdentity.dynamicUniforms
                == [.init(
                    target: .effectConstant(
                        layerID: 1,
                        effectIndex: 2,
                        passIndex: 3,
                        name: "g_Gain"
                    ),
                    declaredSource: .timeline,
                    resolvedSource: .authored,
                    controlAttachments: []
                )],
            "selectionProvenanceDiagnosticOnly": baseline.semanticIdentity
                    == provenanceVariant.semanticIdentity
                && baseline.exactIdentity == provenanceVariant.exactIdentity,
            "rawSamplerFlagsExactOnly": baseline.semanticIdentity
                    == authoredClampVariant.semanticIdentity
                && baseline.exactIdentity != authoredClampVariant.exactIdentity,
            "proceduralOpaqueWithoutSampledInputAccepted":
                proceduralOpaque?.textureSlots.allSatisfy({ $0 == nil }) == true
                && proceduralOpaque?.semanticIdentity.graphRole.bindings.isEmpty == true
                && proceduralOpaque?.semanticIdentity.colorContract.framebufferInput
                    == .opaque
                && proceduralOpaque?.semanticIdentity.colorContract.fragmentOutput
                    == .opaque,
            "unsupportedStateRejected": unsupportedState,
            "mismatchedGraphBindingRejected": mismatchedGraphBinding,
            "invalidGraphBindingSlotRejected": invalidGraphBindingSlot,
            "nonGraphWithGraphBindingRejected": nonGraphWithGraphBinding,
            "unresolvedPublicationRejected": unresolvedPublication,
            "unresolvedTransferRejected": unresolvedTransfer,
            "staleFrontendSchemaRejected": staleFrontendSchema,
            "straightPremultipliedAccepted": hasStraightAlphaBoundary(
                straightPremultiplied
            ),
            "straightOpaqueAccepted": hasStraightAlphaBoundary(straightOpaque),
            "straightInputRejected": straightInputRejected,
            "straightDataRejected": straightDataRejected,
            "maskedDataAccepted": hasStraightAlphaBoundary(maskedDataAccepted),
            "maskedColorRejected": maskedColorRejected,
            "opaqueAlphaAccepted": hasStraightAlphaPreservingBoundary(
                opaqueAlphaAccepted
            ),
            "opaqueAlphaPremultipliedAccepted":
                hasStraightAlphaPreservingBoundary(opaqueAlphaPremultipliedAccepted),
            "wholeFilterAccepted": hasStraightAlphaUNormBoundary(
                wholeFilterAccepted
            ),
            "wholeFilterColorAuxiliaryRejected":
                wholeFilterColorAuxiliaryRejected,
            "wholeFilterEffectOutputRejected": wholeFilterEffectOutputRejected,
            "wholeFilterFramebufferRejected": wholeFilterFramebufferRejected,
            "ambiguousFramebufferRepresentationRejected":
                ambiguousFramebufferRepresentation,
            "independentSignalCompositeAccepted":
                compositingProjection?.framebufferInput == .premultipliedAlpha
                && compositingProjection?.fragmentOutput == .premultipliedAlpha,
            "metalKeyDerived": baseline.metalCompileStateKey(
                attachmentPixelFormat: .bgra8Unorm,
                sampleCount: 1,
                device: device
            ) != nil,
            "invalidMetalKeyRejected": baseline.metalCompileStateKey(
                attachmentPixelFormat: .invalid,
                sampleCount: 0,
                device: device
            ) == nil,
        ]
        let encoded = try JSONEncoder().encode(results)
        FileHandle.standardOutput.write(encoded)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialProgramDerivationTests(unittest.TestCase):
    def test_program_is_derived_atomically_and_identities_are_bounded(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-program-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "resolved-material-program-test"
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
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        if not result["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [name for name, passed in result.items() if not passed],
            [],
            result,
        )


if __name__ == "__main__":
    unittest.main()
