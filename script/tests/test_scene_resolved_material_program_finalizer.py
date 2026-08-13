#!/usr/bin/env python3

"""End-to-end R3 finalization from authored contract to immutable Program."""

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


SHADER_PREPARATION_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPreparation.swift"
)
SHADER_PREPARATION_SUPPORT_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPreparation+Support.swift"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderMalformedMetadataAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment+HostFacts.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderDirective.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderMacroExpansion.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+TextureFormat.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+Schema.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+SchemaSeed.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+DisabledCombo.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderPreprocessor+Directive.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderPreprocessor.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    *scene_swift_sources("authored_shader_frontend_implementation"),
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrameInputs.swift",
    SHADER_PREPARATION_SOURCE,
    SHADER_PREPARATION_SUPPORT_SOURCE,
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneStockTextureSemanticRegistry.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SCENE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Resources/SceneFrameTextureRegistry.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialHostUniformSchema.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramIdentity.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramIdentity+ExactTexture.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+Derivation.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+ColorDerivation.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialUniformEncoder.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialShaderSchema.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialRuntimeLoopBoundResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialShaderSchema+SamplerPurpose.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialShaderSchema+Reachability.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant+CapturedMainTarget.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant+LaunchEnvelope.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Diagnostics.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureSelection.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureResolver+GraphSelection.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureResolver+Launch.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureResolver+LaunchSelection.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureResolver+LaunchColor.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramFinalizer.swift",
]


SUPPORT = r'''
import Foundation

nonisolated enum SceneEffectStageCompilerBackend {
    case authoredShader
}

nonisolated struct SceneEffectStageCompilerFailure {
    enum Phase: String {
        case shaderPreprocessor = "shader-preprocessor"
        case invariant
    }

    enum Code: String {
        case shaderStageMissing = "shader-stage-missing"
        case shaderSourceGraphMissing = "shader-source-graph-missing"
        case shaderSourceIdentityMismatch = "shader-source-identity-mismatch"
        case shaderVariantInvalid = "shader-variant-invalid"
        case shaderIncludeMissing = "shader-include-missing"
        case shaderIncludeAmbiguous = "shader-include-ambiguous"
        case shaderIncludeCycle = "shader-include-cycle"
        case shaderDirectiveUnsupported = "shader-directive-unsupported"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded = "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
    }

    let backend: SceneEffectStageCompilerBackend
    let phase: Phase
    let code: Code
    let details: [String]
}

nonisolated enum SceneEffectStageBackendCompileResult<Value> {
    case notApplicable
    case rejected(SceneEffectStageCompilerFailure)
    case accepted(Value)
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material
        case instance
        case userTexture
        case explicitBinding
    }
}
'''


HARNESS = r'''
import Foundation
import Metal
import simd

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Program = SceneResolvedMaterialProgram
private typealias Template = SceneResolvedMaterialTemplate

private let fixtureLayerID = 42
private let effectProjectionInverse = simd_float4x4(diagonal: SIMD4(2, 3, 4, 5))
private let layerModelMatrix = simd_float4x4(diagonal: SIMD4(6, 7, 8, 9))

private func vertexSource(
    samplerMetadata: String?,
    deadMaskCoordinates: Bool = false,
    stageLocalUniforms: Bool = false
) -> String {
    let sampler = samplerMetadata.map {
        "uniform sampler2D g_Texture0; // \($0)"
    } ?? ""
    let varyingType = deadMaskCoordinates ? "vec4" : "vec2"
    let resolution = deadMaskCoordinates
        ? "uniform vec4 g_Texture1Resolution;"
        : ""
    let maskCoordinates = deadMaskCoordinates
        ? """
        v_TexCoord.zw = vec2(
            v_TexCoord.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
            v_TexCoord.y * g_Texture1Resolution.w / g_Texture1Resolution.y
        );
        """
        : ""
    let stageLocalUniform = stageLocalUniforms
        ? #"uniform float g_Gain; // {"material":"vertexGain","default":2}"#
        : ""
    let stageLocalProbe = stageLocalUniforms ? "float vertexProbe = g_Gain;" : ""
    return """
    #if 1
    uniform mat4 g_EffectTextureProjectionMatrix;
    uniform mat4 g_EffectTextureProjectionMatrixInverse;
    uniform mat4 g_LayerModelMatrix;
    uniform vec2 g_ParallaxPosition;
    #endif
    #endif
    #if 1
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying \(varyingType) v_TexCoord;
    \(sampler)
    \(resolution)
    \(stageLocalUniform)
    void main() {
        \(stageLocalProbe)
        mat4 forwardProjectionProbe = g_EffectTextureProjectionMatrix;
        mat4 layerModelProbe = g_LayerModelMatrix;
        vec2 parallaxProbe = g_ParallaxPosition;
        v_TexCoord.xy = a_TexCoord;
        \(maskCoordinates)
        gl_Position = mul(
            vec4(a_Position, 1.0),
            g_EffectTextureProjectionMatrixInverse
        );
    }
    #endif
    """
}

private func fragmentSource(
    samplerMetadata: String?,
    uniformMetadata: String?,
    secondSamplerMetadata: String?,
    conditionalSecondSampler: Bool,
    arithmetic: Bool = false,
    audioSpectrum: Bool = false,
    maskedAlpha: Bool = false,
    overlayAlphaBlend: Bool = false,
    optionalMask: Bool = false,
    stageLocalUniforms: Bool = false,
    runtimeLoop: Bool = false,
    runtimeLoopEditorHints: Bool = false
) -> String {
    let annotation = samplerMetadata.map { " // \($0)" } ?? ""
    let uniformAnnotation = uniformMetadata.map { " // \($0)" } ?? ""
    let secondSampler = secondSamplerMetadata.map { metadata in
        let declaration = "uniform sampler2D g_Texture1; // \(metadata)"
        return conditionalSecondSampler
            ? "#if EXTRA == 1\n\(declaration)\n#endif"
            : declaration
    } ?? ""
    let combo = conditionalSecondSampler
        ? #"// [COMBO] {"combo":"EXTRA","default":1}"#
        : ""
    let output: String
    if overlayAlphaBlend {
        output = """
        vec4 base = texSample2D(g_Texture0, v_TexCoord);
        vec4 overlay = texSample2D(g_Texture1, v_TexCoord);
        float weight = g_Multiply * overlay.a;
        base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight);
        base.a = overlay.a * g_AlphaMultiply;
        gl_FragColor = base;
        """
    } else if maskedAlpha {
        let mask = optionalMask
            ? """
            #if MASK
            float mask = texSample2D(g_Texture1, v_TexCoord.zw).r;
            #else
            float mask = 1.0;
            #endif
            """
            : "float mask = texSample2D(g_Texture1, v_TexCoord).r;"
        output = """
        vec4 color = texSample2D(g_Texture0, v_TexCoord.xy);
        \(mask)
        color.a *= mask * g_UserAlpha;
        gl_FragColor = color;
        """
    } else {
        let expression = arithmetic
            ? "texSample2D(g_Texture0, v_TexCoord) * 0.5"
            : "texSample2D(g_Texture0, v_TexCoord)"
        if secondSamplerMetadata != nil {
            output = """
            vec4 color = \(expression);
            float auxiliary = texSample2D(g_Texture1, v_TexCoord).r;
            color.a *= auxiliary;
            gl_FragColor = color;
            """
        } else {
            output = "gl_FragColor = \(expression);"
        }
    }
    let alphaUniform = maskedAlpha
        ? "uniform float g_UserAlpha; // {\"material\":\"alpha\",\"default\":1.0}"
        : ""
    let overlayUniforms = overlayAlphaBlend
        ? """
        uniform float g_Multiply; // {"material":"multiply","default":0.5}
        uniform float g_AlphaMultiply; // {"material":"alpha","default":0.5}
        """
        : ""
    let overlayHelper = overlayAlphaBlend
        ? """
        vec3 ApplyBlending(
            const int mode,
            in vec3 base,
            in vec3 blend,
            in float opacity
        ) {
            return mix(base, (blend), opacity);
        }
        """
        : ""
    let audioUniforms = audioSpectrum
        ? """
        uniform float g_AudioSpectrum16Left[16];
        uniform float g_AudioSpectrum32Right[32];
        uniform float g_AudioSpectrum64Left[64];
        uniform float g_AudioSpectrum64Right[64];
        """
        : ""
    let audioProbe = audioSpectrum
        ? "float audioProbe = g_AudioSpectrum16Left[3] + g_AudioSpectrum32Right[5] + g_AudioSpectrum64Left[7] + g_AudioSpectrum64Right[9];"
        : ""
    let stageLocalUniform = stageLocalUniforms
        ? #"uniform float g_Gain; // {"material":"fragmentGain","default":3}"#
        : ""
    let stageLocalProbe = stageLocalUniforms ? "float fragmentProbe = g_Gain;" : ""
    let runtimeLoopMetadata = runtimeLoopEditorHints
        ? #"{"material":"Fractals","int":true,"default":5,"range":[1,10]}"#
        : #"{"material":"Fractals"}"#
    let runtimeLoopUniform = runtimeLoop
        ? "uniform float u_fractals; // \(runtimeLoopMetadata)" : ""
    let runtimeLoopProbe = runtimeLoop
        ? """
        float runtimeProbe = 0.0;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                runtimeProbe += float(x + y);
            }
        }
        for (int octave = 1; octave <= int(u_fractals); octave++) {
            runtimeProbe += float(octave);
        }
        """
        : ""
    return """
    varying \(optionalMask ? "vec4" : "vec2") v_TexCoord;
    \(combo)
    uniform sampler2D g_Texture0;\(annotation)
    \(secondSampler)
    \(audioUniforms)
    uniform vec3 u_Tint;\(uniformAnnotation)
    \(alphaUniform)
    \(overlayUniforms)
    uniform float g_Time; // {"default":99}
    \(stageLocalUniform)
    \(runtimeLoopUniform)
    \(overlayHelper)
    void main() {
        \(stageLocalProbe)
        \(runtimeLoopProbe)
        \(audioProbe)
        vec3 tintProbe = u_Tint;
        float timeProbe = g_Time;
        \(output)
    }
    """
}

private func contract(
    revision: String,
    samplerMetadata: String? = nil,
    vertexSamplerMetadata: String? = nil,
    uniformMetadata: String? = #"{"material":"Tint","default":"1 0.5 0.25"}"#,
    secondSamplerMetadata: String? = nil,
    conditionalSecondSampler: Bool = false,
    arithmetic: Bool = false,
    audioSpectrum: Bool = false,
    maskedAlpha: Bool = false,
    overlayAlphaBlend: Bool = false,
    optionalMask: Bool = false,
    deadMaskCoordinates: Bool = false,
    stageLocalUniforms: Bool = false,
    runtimeLoop: Bool = false,
    runtimeLoopEditorHints: Bool = false,
    includeSourceGraph: Bool = true
) -> SceneShaderContract {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        path: String,
        source: String
    ) -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(
            source,
            stageRelativePath: path
        )
        return .init(
            kind: kind,
            relativePath: path,
            source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes,
            annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let stages = [
        stage(
            .vertex,
            path: "\(revision)/root.vert",
            source: vertexSource(
                samplerMetadata: vertexSamplerMetadata,
                deadMaskCoordinates: deadMaskCoordinates,
                stageLocalUniforms: stageLocalUniforms
            )
        ),
        stage(
            .fragment,
            path: "\(revision)/root.frag",
            source: fragmentSource(
                samplerMetadata: samplerMetadata,
                uniformMetadata: uniformMetadata,
                secondSamplerMetadata: secondSamplerMetadata,
                conditionalSecondSampler: conditionalSecondSampler,
                arithmetic: arithmetic,
                audioSpectrum: audioSpectrum,
                maskedAlpha: maskedAlpha,
                overlayAlphaBlend: overlayAlphaBlend,
                optionalMask: optionalMask,
                stageLocalUniforms: stageLocalUniforms,
                runtimeLoop: runtimeLoop,
                runtimeLoopEditorHints: runtimeLoopEditorHints
            )
        ),
    ]
    let sourceGraph = SceneShaderSourceGraph(
        roots: [
            .init(label: "vertex", virtualPath: "\(revision)/root.vert"),
            .init(label: "fragment", virtualPath: "\(revision)/root.frag"),
        ],
        nodes: stages.map { stage in
            .init(
                virtualPath: stage.relativePath,
                provenance: .package,
                source: stage.source,
                rawSHA256: stage.rawSHA256,
                byteCount: stage.source.utf8.count
            )
        },
        edges: [],
        diagnostics: [],
        dependencySHA256: "fixture-dependency-\(revision)"
    )
    return .init(
        identity: "fixture/\(revision)",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-contract-\(revision)",
        sourceGraph: includeSourceGraph ? sourceGraph : nil
    )
}

private func graphTexture() -> Graph.TextureIdentity {
    .init(kind: .layerSource, layerID: fixtureLayerID, effect: nil, name: nil)
}

private func state(blending: String = "normal") -> SceneMaterialRenderState {
    SceneMaterialRenderState.compile(
        blending: blending,
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: nil
    )!
}

private func candidates(_ count: Int) -> [Template.TextureCandidate] {
    (0 ..< count).map { index in
        .init(
            reference: index == count - 1
                ? .graph(graphTexture())
                : .asset(SceneVFSAssetPath("textures/overridden-\(index).tex")!),
            provenance: index == count - 1 ? .explicitBinding : .instance
        )
    }
}

private func staticValue(_ components: [Double]) -> Template.StaticUniformValue {
    .init(
        valueKind: "fixture",
        componentBitPatterns: components.map(\.bitPattern),
        authoredBindingKeys: []
    )
}

private func staticDeclaration(
    _ name: String,
    components: [Double]
) -> Template.UniformDeclaration {
    .init(name: name, value: .staticExact(staticValue(components)))
}

private func dynamicDeclaration(
    _ valueContributors: [Template.DynamicUniformSource],
    controls: [Template.DynamicUniformControlAttachment] = []
) -> Template.UniformDeclaration {
    .init(
        name: "Tint",
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: "Tint"
            ),
            valueContributors: valueContributors,
            controlAttachments: controls,
            authoredFallback: staticValue([1, 0.5, 0.25]),
            authoredBindingKeys: ["animation", "script", "value"]
        ))
    )
}

private func dynamicAlphaDeclaration(
    _ valueContributors: [Template.DynamicUniformSource]
) -> Template.UniformDeclaration {
    .init(
        name: "alpha",
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: "alpha"
            ),
            valueContributors: valueContributors,
            controlAttachments: [],
            authoredFallback: staticValue([1]),
            authoredBindingKeys: ["value"]
        ))
    )
}

private func dynamicScalarDeclaration(_ name: String) -> Template.UniformDeclaration {
    .init(
        name: name,
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: name
            ),
            valueContributors: [.timeline],
            controlAttachments: [],
            authoredFallback: staticValue([5]),
            authoredBindingKeys: ["value"]
        ))
    )
}

private func template(
    _ shader: SceneShaderContract,
    slot: Int = 0,
    candidateCount: Int = 1,
    includePrimaryCandidate: Bool = true,
    secondReference: Template.TextureReference? = nil,
    secondCandidates: [Template.TextureCandidate]? = nil,
    uniformDeclarations: [Template.UniformDeclaration] = [],
    renderState: SceneMaterialRenderState = state()
) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    if includePrimaryCandidate {
        slots[slot] = .init(index: slot, candidates: candidates(candidateCount))
    }
    if let secondCandidates {
        slots[1] = .init(index: 1, candidates: secondCandidates)
    } else if let secondReference {
        slots[1] = .init(index: 1, candidates: [
            .init(reference: secondReference, provenance: .instance),
        ])
    }
    return Template.validated(
        textureSlots: slots,
        combos: [],
        uniformDeclarations: uniformDeclarations,
        renderState: renderState,
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: includePrimaryCandidate
                ? [.init(slot: slot, texture: .layerSource)] : []
        ),
        shaderContract: shader,
        diagnosticProvenance: .init(
            nodeIndex: 0,
            authoredShaderPath: shader.identity,
            contractIdentity: shader.identity,
            contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
}

private func texture(_ device: MTLDevice) -> MTLTexture {
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

private func publication(
    _ device: MTLDevice,
    requestIdentity: SceneFrameTextureIdentity,
    purpose: SceneTextureLoadPurpose = .premultipliedColor,
    content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
    candidateGeneration: UInt64 = 1,
    contentGeneration: UInt64 = 1,
    sampling: SceneTextureSampling = .directImageFallback
) -> SceneTextureProviderPublication {
    .init(
        requestIdentity: requestIdentity,
        candidate: .init(
            texture: texture(device),
            identity: .provider(.video(layerID: fixtureLayerID, lifecycleEpoch: 1)),
            generation: .provider(contentGeneration: candidateGeneration),
            purpose: purpose,
            content: content,
            physicalSize: CGSize(width: 2, height: 2),
            mappedSize: CGSize(width: 2, height: 2),
            uvTransform: .identity,
            sampling: sampling
        ),
        contentGeneration: contentGeneration
    )
}

private enum SnapshotKind {
    case ready
    case absent
    case missing
    case pending
    case unavailable
    case incomplete
    case purposeMismatch
    case unresolvedColor
    case data
    case unsupportedSampler
}

private func snapshot(
    _ device: MTLDevice,
    kind: SnapshotKind = .ready,
    frameIndex: UInt64 = 1,
    additionalEntries: [
        SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
    ] = [:]
) -> SceneFrameTextureRegistrySnapshot {
    let identity = SceneFrameTextureIdentity.graph(graphTexture())
    let status: SceneFrameTextureLookupStatus?
    switch kind {
    case .ready:
        status = .ready(.init(
            publication: publication(device, requestIdentity: identity),
            resourceGeneration: 1
        ))
    case .absent:
        status = .absent
    case .missing:
        status = nil
    case .pending:
        status = .pending
    case .unavailable:
        status = .unavailable
    case .incomplete:
        status = .incomplete(.publication(
            publication(
                device,
                requestIdentity: identity,
                candidateGeneration: 1,
                contentGeneration: 2
            ),
            resourceGeneration: 1
        ))
    case .purposeMismatch:
        status = .ready(.init(
            publication: publication(
                device,
                requestIdentity: identity,
                purpose: .straightAlbedo,
                content: .color(.resolved(.straightAlpha))
            ),
            resourceGeneration: 1
        ))
    case .unresolvedColor:
        status = .incomplete(.publication(
            publication(
                device,
                requestIdentity: identity,
                content: .color(.unresolved)
            ),
            resourceGeneration: 1
        ))
    case .data:
        status = .ready(.init(
            publication: publication(
                device,
                requestIdentity: identity,
                purpose: .noise,
                content: .data
            ),
            resourceGeneration: 1
        ))
    case .unsupportedSampler:
        status = .ready(.init(
            publication: publication(
                device,
                requestIdentity: identity,
                sampling: .init(texFlags: 8)
            ),
            resourceGeneration: 1
        ))
    }
    var entries = additionalEntries
    if let status { entries[identity] = status }
    return .init(
        frameEpoch: 1,
        frameIndex: frameIndex,
        entries: entries
    )
}

private func readyStatus(
    _ device: MTLDevice,
    identity: SceneFrameTextureIdentity,
    purpose: SceneTextureLoadPurpose,
    content: SceneTextureContent
) -> SceneFrameTextureLookupStatus {
    .ready(.init(
        publication: publication(
            device,
            requestIdentity: identity,
            purpose: purpose,
            content: content,
            candidateGeneration: 7,
            contentGeneration: 7
        ),
        resourceGeneration: 7
    ))
}

private func uniformInputs() -> SceneAuthoredShaderUniformInputs {
    .init(
        frameIndex: 1,
        renderSize: CGSize(width: 640, height: 360),
        screenSize: CGSize(width: 1920, height: 1080),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectTextureProjectionMatrix: effectProjectionInverse.inverse,
        effectTextureProjectionMatrixInverse: effectProjectionInverse,
        sceneTime: 2,
        dayTime: 0.5,
        frameTime: 1 / 60,
        pointerCurrentNDC: SIMD2(0.25, -0.5),
        pointerPreviousNDC: SIMD2.zero,
        parallaxPositionNDC: SIMD2(0.5, -0.25),
        texturePhysicalSizes: [0: CGSize(width: 2, height: 2)]
    )
}

private func frameInputs(
    frameIndex: UInt64,
    audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent
) -> SceneAuthoredShaderFrameInputs {
    .init(
        frameIndex: frameIndex,
        screenSize: CGSize(width: 1920, height: 1080),
        sceneTime: 2,
        dayTime: 0.5,
        frameTime: 1 / 60,
        pointerCurrentNDC: SIMD2(0.25, -0.5),
        pointerPreviousNDC: .zero,
        parallaxPositionNDC: SIMD2(0.5, -0.25),
        audioSpectrum: audioSpectrum
    )
}

private func dynamicSnapshot(
    frameIndex: UInt64,
    source: SceneDynamicSource?
) -> SceneDynamicSnapshot {
    let tintTarget = SceneDynamicTarget.effectConstant(
        layerID: fixtureLayerID,
        effectIndex: 0,
        passIndex: 0,
        name: "Tint"
    )
    let alphaTarget = SceneDynamicTarget.effectConstant(
        layerID: fixtureLayerID,
        effectIndex: 0,
        passIndex: 0,
        name: "alpha"
    )
    let tintValue = SceneDynamicValue.vector3(1, 0.5, 0.25)
    let alphaValue = SceneDynamicValue.scalar(0.25)
    var user: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var timeline: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var script: [SceneDynamicTarget: SceneDynamicValue] = [:]
    switch source {
    case .userProperty:
        user[tintTarget] = tintValue
        user[alphaTarget] = alphaValue
    case .timeline:
        timeline[tintTarget] = tintValue
        timeline[alphaTarget] = alphaValue
    case .sceneScript:
        script[tintTarget] = tintValue
        script[alphaTarget] = alphaValue
    case .authored, nil: break
    }
    return SceneDynamicSnapshotResolver().resolve(
        frameIndex: frameIndex,
        generation: 1,
        definitions: [
            .init(
                target: tintTarget,
                valueType: .vector3,
                authoredValue: tintValue
            ),
            .init(
                target: alphaTarget,
                valueType: .scalar,
                authoredValue: .scalar(1)
            ),
        ],
        userValues: user,
        timelineValues: timeline,
        sceneScriptValues: script
    ).snapshot
}

private func finalize(
    shader: SceneShaderContract,
    device: MTLDevice,
    slot: Int = 0,
    candidateCount: Int = 1,
    includePrimaryCandidate: Bool = true,
    secondReference: Template.TextureReference? = nil,
    secondCandidates: [Template.TextureCandidate]? = nil,
    additionalEntries: [
        SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
    ] = [:],
    uniformDeclarations: [Template.UniformDeclaration] = [],
    snapshotKind: SnapshotKind = .ready,
    textureFrameIndex: UInt64 = 1,
    dynamicFrameIndex: UInt64 = 1,
    frameInputIndex: UInt64 = 1,
    dynamicSource: SceneDynamicSource? = nil,
    renderState: SceneMaterialRenderState = state(),
    implicitFramebufferIdentity: Graph.TextureIdentity? = nil,
    audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent,
    variantCache: SceneResolvedMaterialVariantCache? = nil
) -> Result<Program, SceneResolvedMaterialFailure> {
    let frame = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(
            device,
            kind: snapshotKind,
            frameIndex: textureFrameIndex,
            additionalEntries: additionalEntries
        ),
        dynamicSnapshot: dynamicSnapshot(
            frameIndex: dynamicFrameIndex,
            source: dynamicSource
        ),
        frameInputs: frameInputs(
            frameIndex: frameInputIndex,
            audioSpectrum: audioSpectrum
        )
    )
    switch frame {
    case let .failure(failure):
        return .failure(failure)
    case let .success(frame):
        let input = frame.finalizationInput(
            template: template(
                shader,
                slot: slot,
                candidateCount: candidateCount,
                includePrimaryCandidate: includePrimaryCandidate,
                secondReference: secondReference,
                secondCandidates: secondCandidates,
                uniformDeclarations: uniformDeclarations,
                renderState: renderState
            ),
            renderSize: CGSize(width: 640, height: 360),
            modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: layerModelMatrix,
            effectTextureProjectionMatrixInverse: effectProjectionInverse,
            implicitFramebufferIdentity: implicitFramebufferIdentity
        )
        if let variantCache {
            return SceneResolvedMaterialProgramFinalizer.finalize(
                input,
                variantCache: variantCache
            )
        }
        return SceneResolvedMaterialProgramFinalizer.finalize(input)
    }
}

private func crossTemplateRuntimeLoopCacheToken(_ device: MTLDevice) -> String {
    let shader = contract(revision: "runtime-loop-cache-identity", runtimeLoop: true)
    let admitted = template(
        shader,
        uniformDeclarations: [staticDeclaration("Fractals", components: [5])]
    )
    let mismatched = template(
        shader,
        uniformDeclarations: [staticDeclaration("Fractals", components: [257])]
    )
    guard let cache = SceneResolvedMaterialVariantCache(
        template: admitted,
        maximumVariantCount: 8
    ), case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(device, kind: .ready, frameIndex: 1),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return "setup-failed" }
    let input = frame.finalizationInput(
        template: mismatched,
        renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectTextureProjectionMatrixInverse: effectProjectionInverse,
        implicitFramebufferIdentity: nil
    )
    return failureToken(
        SceneResolvedMaterialProgramFinalizer.finalize(
            input,
            variantCache: cache
        )
    )
}

private func failureToken(
    _ result: Result<Program, SceneResolvedMaterialFailure>
) -> String {
    switch result {
    case .success:
        return "success"
    case let .failure(failure):
        return "\(failure.phase.rawValue)/\(failure.code.rawValue)"
    }
}

private func samplerPurposeToken(
    _ metadata: String?,
    vertexMetadata: String? = nil,
    assetReference: Bool = false,
    assetPath: String = "textures/fixture.tex"
) -> String {
    let shader = contract(
        revision: "sampler-schema",
        samplerMetadata: metadata,
        vertexSamplerMetadata: vertexMetadata
    )
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true]
            ) else { return "preparation-failed" }
    do {
        guard let sampler = try SceneResolvedMaterialShaderSchema
            .activeSamplers(prepared)[0] else { return "missing" }
        let reference: Template.TextureReference = assetReference
            ? .asset(SceneVFSAssetPath(assetPath)!)
            : .graph(graphTexture())
        return sampler.purpose(for: reference)?.reportToken ?? "unproven"
    } catch {
        return "schema-invalid"
    }
}

private func samplerReadinessSchemaToken(_ metadata: String) -> String {
    let shader = contract(
        revision: "sampler-readiness-schema",
        samplerMetadata: metadata
    )
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true]
            ) else { return "preparation-failed" }
    do {
        guard let sampler = try SceneResolvedMaterialShaderSchema
            .activeSamplers(prepared)[0] else { return "missing" }
        let defaultToken: String = switch sampler.defaultTexture {
        case .asset: "asset"
        case .internalTarget: "internal"
        case nil: "none"
        }
        return "\(sampler.readinessCombo ?? "none")|\(defaultToken)"
    } catch {
        return "schema-invalid"
    }
}

private func implicitFramebufferProjectionToken(
    defaultAssetPath: String
) -> String {
    let shader = contract(
        revision: "implicit-stock-default-\(defaultAssetPath.replacingOccurrences(of: "/", with: "-"))",
        secondSamplerMetadata: "{\"default\":\"\(defaultAssetPath)\"}"
    )
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true, 1: true]
            ) else { return "preparation-failed" }
    do {
        let samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
        return SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: template(shader, includePrimaryCandidate: false),
            samplers: samplers
        ).sorted().map(String.init).joined(separator: ",")
    } catch {
        return "schema-invalid"
    }
}

private func implicitFramebufferCandidateProjectionToken(
    assetPath: String
) -> String {
    let shader = contract(revision: "implicit-stock-candidate")
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true, 1: true]
            ) else { return "preparation-failed" }
    do {
        let samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
        return SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: template(
                shader,
                includePrimaryCandidate: false,
                secondReference: .asset(SceneVFSAssetPath(assetPath)!)
            ),
            samplers: samplers
        ).sorted().map(String.init).joined(separator: ",")
    } catch {
        return "schema-invalid"
    }
}

private func reachableConditionalPurposeToken() -> String {
    let shader = contract(
        revision: "conditional-sampler-schema",
        samplerMetadata: #"{"material":"framebuffer"}"#,
        secondSamplerMetadata:
            #"{"material":"albedo","default":"textures/conditional.tex"}"#,
        conditionalSecondSampler: true
    )
    var conditionalTemplate = template(
        shader,
        secondReference: .asset(
            SceneVFSAssetPath("textures/conditional.tex")!
        )
    )
    conditionalTemplate = Template.validated(
        textureSlots: conditionalTemplate.textureSlots,
        combos: [.init(name: "EXTRA", value: 1)],
        uniformDeclarations: conditionalTemplate.uniformDeclarations,
        renderState: conditionalTemplate.renderState,
        graphRole: conditionalTemplate.graphRole,
        shaderContract: conditionalTemplate.shaderContract,
        diagnosticProvenance: conditionalTemplate.diagnosticProvenance
    )!
    do {
        guard let sampler = try SceneResolvedMaterialShaderSchema.reachableSamplers(
            conditionalTemplate,
            implicitFramebufferIdentity: graphTexture()
        )[1]?.first else { return "missing" }
        let reference = Template.TextureReference.asset(
            SceneVFSAssetPath("textures/conditional.tex")!
        )
        return sampler.purpose(for: reference)?.reportToken ?? "unproven"
    } catch {
        return "schema-invalid"
    }
}

private func positiveDiagnostic(_ shader: SceneShaderContract) -> String {
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: shader,
        combos: [:],
        textureReadiness: [0: true]
    ) {
    case let .accepted(prepared):
        let compiled = SceneAuthoredShaderFrontend.compile(
            vertexSource: prepared.vertex.source,
            fragmentSource: prepared.fragment.source
        )
        guard let frontend = compiled.program else {
            return "frontend=" + compiled.diagnostics.map { $0.code.rawValue }.joined(separator: ",")
        }
        let schema: String
        do {
            schema = "\(try SceneResolvedMaterialShaderSchema.activeSamplers(prepared))"
        } catch {
            schema = "error:\(error)"
        }
        return "slots=\(frontend.textureBindings.map(\.slot))"
            + ",fields=\(frontend.uniformLayout.fields.map { "\($0.name):\($0.type.rawValue):\($0.offset)" })"
            + ",bytes=\(frontend.uniformLayout.byteSize)"
            + ",transfer=\(frontend.colorTransfer)"
            + ",annotations=\(prepared.all.flatMap(\.activeAnnotations).count)"
            + ",schema=\(schema)"
    case let .rejected(failure):
        return "preparation=\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.details)"
    case .notApplicable:
        return "preparation=not-applicable"
    }
}

private func missingSourceGraphDiagnostic() -> String {
    let shader = contract(
        revision: "missing-source-graph",
        includeSourceGraph: false
    )
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: shader,
        combos: [:]
    ) {
    case .accepted:
        return "accepted"
    case let .rejected(failure):
        return "\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.details.count)"
    case .notApplicable:
        return "not-applicable"
    }
}

@main
private enum Harness {
    static func float(_ data: Data, at offset: Int) -> Float {
        data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: Float.self)
        }
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}")
            return
        }

        let revisionA = finalize(
            shader: contract(revision: "revision-a"),
            device: device
        )
        let revisionB = finalize(
            shader: contract(revision: "revision-b"),
            device: device
        )
        guard case let .success(programA) = revisionA,
              case let .success(programB) = revisionB else {
            fatalError(
                "positive finalization failed: \(failureToken(revisionA)), "
                    + "\(failureToken(revisionB)); \(positiveDiagnostic(contract(revision: "debug")))"
            )
        }

        let audioInputs = SceneAuthoredShaderAudioSpectrumInputs(
            left16: (0 ..< 16).map { Float($0 + 1) },
            right16: Array(repeating: 0, count: 16),
            left32: Array(repeating: 0, count: 32),
            right32: (0 ..< 32).map { Float(100 + $0) },
            left64: (0 ..< 64).map { Float(200 + $0) },
            right64: (0 ..< 64).map { Float(300 + $0) }
        )
        let audioProgramResult = finalize(
            shader: contract(revision: "audio-spectrum", audioSpectrum: true),
            device: device,
            audioSpectrum: audioInputs
        )
        let audioSpectrumEncoded: Bool = {
            guard case let .success(program) = audioProgramResult else {
                return false
            }
            guard let left16 = program.frontendProgram.uniformLayout.fields.first(
                where: { $0.name == "g_AudioSpectrum16Left" }
            ), let right32 = program.frontendProgram.uniformLayout.fields.first(
                where: { $0.name == "g_AudioSpectrum32Right" }
            ), let left64 = program.frontendProgram.uniformLayout.fields.first(
                where: { $0.name == "g_AudioSpectrum64Left" }
            ), let right64 = program.frontendProgram.uniformLayout.fields.first(
                where: { $0.name == "g_AudioSpectrum64Right" }
            ) else {
                return false
            }
            return left16.arrayCount == 16
                && right32.arrayCount == 32
                && left64.arrayCount == 64
                && right64.arrayCount == 64
                && float(program.uniformBytes, at: left16.offset + 3 * 4) == 4
                && float(program.uniformBytes, at: right32.offset + 5 * 4) == 105
                && float(program.uniformBytes, at: left64.offset + 7 * 4) == 207
                && float(program.uniformBytes, at: right64.offset + 9 * 4) == 309
        }()
        let stageLocalProgram = finalize(
            shader: contract(
                revision: "stage-local-uniforms",
                stageLocalUniforms: true
            ),
            device: device
        )
        let stageLocalUniformsEncoded: Bool = {
            guard case let .success(program) = stageLocalProgram,
                  let vertex = program.frontendProgram.uniformLayout.fields.first(
                      where: { $0.name == "mwxV_g_Gain" }
                  ),
                  let fragment = program.frontendProgram.uniformLayout.fields.first(
                      where: { $0.name == "mwxF_g_Gain" }
                  ) else {
                return false
            }
            return vertex.authoredName == "g_Gain"
                && fragment.authoredName == "g_Gain"
                && vertex.stage == .vertex
                && fragment.stage == .fragment
                && float(program.uniformBytes, at: vertex.offset) == 2
                && float(program.uniformBytes, at: fragment.offset) == 3
        }()
        let runtimeLoopProgram = finalize(
            shader: contract(
                revision: "runtime-loop-static-producer",
                runtimeLoop: true
            ),
            device: device,
            uniformDeclarations: [
                staticDeclaration("Fractals", components: [5]),
            ]
        )
        let runtimeLoopStaticProducerAccepted: Bool = {
            guard case let .success(program) = runtimeLoopProgram,
                  let field = program.frontendProgram.uniformLayout.fields.first(
                      where: { $0.name == "u_fractals" }
                  ) else { return false }
            let compactSource = program.frontendProgram.metalSource.replacingOccurrences(
                of: " ",
                with: ""
            )
            return program.frontendProgram.staticLoopWork == 17
                && float(program.uniformBytes, at: field.offset) == 5
                && compactSource.contains("int(mwxUniforms.u_fractals)")
                && !compactSource.contains("clamp(mwxUniforms.u_fractals")
        }()

        let implicitFramebufferProgram = finalize(
            shader: contract(
                revision: "implicit-framebuffer",
                samplerMetadata: #"{"material":"framebuffer"}"#
            ),
            device: device,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture()
        )
        let caseInsensitiveFramebufferProgram = finalize(
            shader: contract(
                revision: "implicit-framebuffer-case",
                samplerMetadata: #"{"material":"Framebuffer"}"#
            ),
            device: device,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture()
        )
        let historicalFramebufferProgram = finalize(
            shader: contract(
                revision: "historical-framebuffer-material-alias",
                samplerMetadata:
                    #"{"material":"ui_editor_properties_framebuffer","hidden":true}"#
            ),
            device: device,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture()
        )
        let previousAliasProgram = finalize(
            shader: contract(
                revision: "material-previous",
                samplerMetadata: #"{"material":"previous"}"#
            ),
            device: device,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture()
        )
        let explicitFramebufferProgram = finalize(
            shader: contract(
                revision: "explicit-before-implicit",
                samplerMetadata: #"{"material":"framebuffer"}"#
            ),
            device: device,
            implicitFramebufferIdentity: graphTexture()
        )
        let implicitFramebufferTyped: Bool = {
            guard case let .success(program) = implicitFramebufferProgram,
                  let slot = program.textureSlots[0],
                  case let .graph(identity) = slot.reference else { return false }
            return identity == graphTexture()
                && slot.diagnosticSelectionProvenance == .implicitFramebuffer
        }()
        let previousAliasTyped: Bool = {
            guard case let .success(program) = previousAliasProgram,
                  let slot = program.textureSlots[0],
                  case let .graph(identity) = slot.reference else { return false }
            return identity == graphTexture()
                && slot.diagnosticSelectionProvenance == .materialGraphInputAlias
        }()
        let historicalFramebufferTyped: Bool = {
            guard case let .success(program) = historicalFramebufferProgram,
                  let slot = program.textureSlots[0],
                  case let .graph(identity) = slot.reference else { return false }
            return identity == graphTexture()
                && slot.diagnosticSelectionProvenance == .implicitFramebuffer
                && slot.expectedPurpose == .premultipliedColor
        }()
        let stockNoisePath = SceneVFSAssetPath("util/noise")!
        let stockNoiseIdentity = SceneAssetTextureIdentity(
            path: stockNoisePath,
            purpose: .noise
        )
        let stockDefaultProgram = finalize(
            shader: contract(
                revision: "stock-default-program",
                secondSamplerMetadata: #"{"default":"util/noise"}"#
            ),
            device: device,
            includePrimaryCandidate: false,
            additionalEntries: [
                .asset(stockNoiseIdentity): readyStatus(
                    device,
                    identity: .asset(stockNoiseIdentity),
                    purpose: .noise,
                    content: .data
                ),
            ],
            implicitFramebufferIdentity: graphTexture()
        )
        let stockDefaultProgramPreservesSnapshotAtoms: Bool = {
            guard case let .success(program) = stockDefaultProgram,
                  let source = program.textureSlots[0],
                  let noise = program.textureSlots[1],
                  case let .graph(sourceReference) = source.reference,
                  case let .asset(noiseReference) = noise.reference,
                  case let .provider(sourceGeneration) =
                      source.resource.publication.candidate.generation,
                  case let .provider(noiseGeneration) =
                      noise.resource.publication.candidate.generation,
                  case .color(.resolved(.premultipliedAlpha)) =
                      source.resource.publication.candidate.content,
                  case .data = noise.resource.publication.candidate.content else {
                return false
            }
            let sourceCandidate = source.resource.publication.candidate
            let noiseCandidate = noise.resource.publication.candidate
            return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
                && sourceReference == graphTexture()
                && noiseReference == stockNoisePath
                && source.registryIdentity == .graph(graphTexture())
                && noise.registryIdentity == .asset(stockNoiseIdentity)
                && source.diagnosticSelectionProvenance == .implicitFramebuffer
                && noise.diagnosticSelectionProvenance == .shaderDefault
                && source.expectedPurpose == .premultipliedColor
                && noise.expectedPurpose == .noise
                && source.resource.resourceGeneration == 1
                && noise.resource.resourceGeneration == 7
                && source.resource.publication.contentGeneration == 1
                && noise.resource.publication.contentGeneration == 7
                && sourceGeneration == 1
                && noiseGeneration == 7
                && sourceCandidate.physicalSize == CGSize(width: 2, height: 2)
                && sourceCandidate.mappedSize == CGSize(width: 2, height: 2)
                && noiseCandidate.physicalSize == CGSize(width: 2, height: 2)
                && noiseCandidate.mappedSize == CGSize(width: 2, height: 2)
                && sourceCandidate.sampling == .directImageFallback
                && noiseCandidate.sampling == .directImageFallback
                && sourceCandidate.sampling.rawFlags == nil
                && noiseCandidate.sampling.rawFlags == nil
                && sourceCandidate.texture !== noiseCandidate.texture
        }()
        let explicitFramebufferPreserved: Bool = {
            guard case let .success(program) = explicitFramebufferProgram,
                  let slot = program.textureSlots[0] else { return false }
            return slot.diagnosticSelectionProvenance
                == .authored(.explicitBinding)
        }()
        let implicitDefaultPath = SceneVFSAssetPath(
            "textures/implicit-default.tex"
        )!
        let shaderDefaultBeforeImplicit = finalize(
            shader: contract(
                revision: "shader-default-before-implicit",
                samplerMetadata:
                    #"{"material":"framebuffer","mode":"opacitymask","default":"textures/implicit-default.tex"}"#
            ),
            device: device,
            includePrimaryCandidate: false,
            additionalEntries: [
                .asset(.init(
                    path: implicitDefaultPath,
                    purpose: .mask
                )): readyStatus(
                    device,
                    identity: .asset(.init(
                        path: implicitDefaultPath,
                        purpose: .mask
                    )),
                    purpose: .mask,
                    content: .data
                ),
            ],
            implicitFramebufferIdentity: graphTexture()
        )
        let shaderDefaultPreserved: Bool = {
            guard case let .failure(failure) = shaderDefaultBeforeImplicit else {
                return false
            }
            return failure.phase == .color
                && failure.code == .colorContractUnproven
        }()

        let tintField = programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "u_Tint"
        }!
        let tintRange = tintField.offset ..< tintField.offset + tintField.type.byteSize
        let tintDefaultCorrect = programA.uniformBytes.subdata(in: tintRange)
            == SceneResolvedMaterialUniformEncoder.encodeComponents(
                [1, 0.5, 0.25],
                as: tintField.type
            )!
        let timeField = programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "g_Time"
        }!
        let timeRange = timeField.offset ..< timeField.offset + timeField.type.byteSize
        let hostDefaultIgnored = programA.uniformBytes.subdata(in: timeRange)
            == SceneResolvedMaterialUniformEncoder.encodeComponents(
                [2],
                as: timeField.type
            )!
        let explicitTint = finalize(
            shader: contract(revision: "explicit-tint"),
            device: device,
            uniformDeclarations: [staticDeclaration("Tint", components: [0.2, 0.4, 0.6])]
        )
        let explicitOverrideCorrect: Bool
        if case let .success(program) = explicitTint,
           let field = program.frontendProgram.uniformLayout.fields.first(where: {
               $0.name == "u_Tint"
           }) {
            let range = field.offset ..< field.offset + field.type.byteSize
            explicitOverrideCorrect = program.uniformBytes.subdata(in: range)
                == SceneResolvedMaterialUniformEncoder.encodeComponents(
                    [0.2, 0.4, 0.6],
                    as: field.type
                )!
        } else {
            explicitOverrideCorrect = false
        }
        let maskMetadata = #"{"mode":"opacitymask"}"#
        let assetPath = SceneVFSAssetPath("textures/fixture-mask.tex")!
        let assetProgram = finalize(
            shader: contract(
                revision: "asset-reference",
                secondSamplerMetadata: maskMetadata
            ),
            device: device,
            secondReference: .asset(assetPath),
            additionalEntries: [
                .asset(.init(path: assetPath, purpose: .mask)):
                    readyStatus(
                        device,
                        identity: .asset(.init(path: assetPath, purpose: .mask)),
                        purpose: .mask,
                        content: .data
                    ),
            ]
        )
        let maskedPath = SceneVFSAssetPath("textures/masked-alpha.tex")!
        let maskedIdentity = SceneFrameTextureIdentity.asset(.init(
            path: maskedPath,
            purpose: .mask
        ))
        let maskedShader = contract(
            revision: "masked-alpha",
            secondSamplerMetadata: maskMetadata,
            maskedAlpha: true
        )
        let maskedProgram = finalize(
            shader: maskedShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [
                maskedIdentity: readyStatus(
                    device,
                    identity: maskedIdentity,
                    purpose: .mask,
                    content: .data
                ),
            ],
            uniformDeclarations: [dynamicAlphaDeclaration([
                .userProperty("opacity")
            ])],
            dynamicSource: .userProperty,
            implicitFramebufferIdentity: graphTexture()
        )
        let maskedDynamicAlphaEncoded: Bool = {
            guard case let .success(program) = maskedProgram,
                  let field = program.frontendProgram.uniformLayout.fields.first(
                    where: { $0.name == "g_UserAlpha" }
                  ),
                  let maskSlot = program.textureSlots[1],
                  case .data = maskSlot.resource.publication.candidate.content,
                  case .straightAlpha(0) = program.semanticIdentity.shader.colorTransfer
            else { return false }
            return float(program.uniformBytes, at: field.offset) == 0.25
                && program.semanticIdentity.colorContract.fragmentOutput
                    == .premultipliedAlpha
        }()
        let sceneScriptAlphaProgram = finalize(
            shader: maskedShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [
                maskedIdentity: readyStatus(
                    device,
                    identity: maskedIdentity,
                    purpose: .mask,
                    content: .data
                ),
            ],
            uniformDeclarations: [dynamicAlphaDeclaration([.sceneScript])],
            dynamicSource: .sceneScript,
            implicitFramebufferIdentity: graphTexture()
        )
        let sceneScriptDynamicAlphaEncoded: Bool = {
            guard case let .success(program) = sceneScriptAlphaProgram,
                  let field = program.frontendProgram.uniformLayout.fields.first(
                    where: { $0.name == "g_UserAlpha" }
                  )
            else { return false }
            return float(program.uniformBytes, at: field.offset) == 0.25
        }()
        let overlayPath = SceneVFSAssetPath("textures/overlay-data.tex")!
        let overlayIdentity = SceneFrameTextureIdentity.asset(.init(
            path: overlayPath,
            purpose: .preservedChannels
        ))
        let overlayShader = contract(
            revision: "overlay-alpha-blend",
            secondSamplerMetadata: #"{"mode":"rgbmask"}"#,
            overlayAlphaBlend: true
        )
        let overlayProgram = finalize(
            shader: overlayShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(overlayPath),
            additionalEntries: [
                overlayIdentity: readyStatus(
                    device,
                    identity: overlayIdentity,
                    purpose: .preservedChannels,
                    content: .data
                ),
            ],
            implicitFramebufferIdentity: graphTexture()
        )
        let overlayDataTyped: Bool = {
            guard case let .success(program) = overlayProgram,
                  let overlay = program.textureSlots[1],
                  overlay.expectedPurpose == .preservedChannels,
                  overlay.resource.publication.candidate.purpose
                    == .preservedChannels,
                  case .data = overlay.resource.publication.candidate.content,
                  case .straightAlpha(0) =
                    program.semanticIdentity.shader.colorTransfer else {
                return false
            }
            return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
                && program.semanticIdentity.colorContract.fragmentOutput
                    == .premultipliedAlpha
        }()
        let overlayColorAuxiliary = finalize(
            shader: overlayShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(overlayPath),
            additionalEntries: [
                overlayIdentity: readyStatus(
                    device,
                    identity: overlayIdentity,
                    purpose: .preservedChannels,
                    content: .color(.resolved(.premultipliedAlpha))
                ),
            ],
            implicitFramebufferIdentity: graphTexture()
        )
        let optionalDefaultPath = SceneVFSAssetPath(
            "textures/optional-default-mask.tex"
        )!
        let optionalDefaultIdentity = SceneFrameTextureIdentity.asset(.init(
            path: optionalDefaultPath,
            purpose: .mask
        ))
        let optionalDefaultEntry = readyStatus(
            device,
            identity: optionalDefaultIdentity,
            purpose: .mask,
            content: .data
        )
        let optionalMaskShader = contract(
            revision: "optional-mask-with-default",
            secondSamplerMetadata:
                #"{"mode":"opacitymask","combo":"MASK","default":"textures/optional-default-mask.tex"}"#,
            maskedAlpha: true,
            optionalMask: true,
            deadMaskCoordinates: true
        )
        let optionalMaskProgram = finalize(
            shader: optionalMaskShader,
            device: device,
            includePrimaryCandidate: false,
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let optionalMaskWithoutResourceAccepted: Bool = {
            guard case let .success(program) = optionalMaskProgram else {
                return false
            }
            return program.frontendProgram.textureBindings.map(\.slot) == [0]
                && program.textureSlots[0] != nil
                && program.textureSlots[1] == nil
                && !program.frontendProgram.uniformLayout.fields.contains {
                    $0.name == "g_Texture1Resolution"
                }
        }()
        let optionalMaskWithResource = finalize(
            shader: optionalMaskShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [
                optionalDefaultIdentity: optionalDefaultEntry,
                maskedIdentity: readyStatus(
                    device,
                    identity: maskedIdentity,
                    purpose: .mask,
                    content: .data
                ),
            ],
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let optionalMaskWithResourceAccepted: Bool = {
            guard case let .success(program) = optionalMaskWithResource,
                  let mask = program.textureSlots[1],
                  case let .asset(reference) = mask.reference,
                  reference == maskedPath,
                  mask.diagnosticSelectionProvenance == .authored(.instance),
                  mask.expectedPurpose == .mask,
                  case .data = mask.resource.publication.candidate.content else {
                return false
            }
            return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
                && program.frontendProgram.uniformLayout.fields.contains {
                    $0.name == "g_Texture1Resolution"
                }
        }()
        let optionalMaskPending = finalize(
            shader: optionalMaskShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [
                optionalDefaultIdentity: optionalDefaultEntry,
                maskedIdentity: .pending,
            ],
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let optionalMaskWrongPurpose = finalize(
            shader: optionalMaskShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [
                optionalDefaultIdentity: optionalDefaultEntry,
                maskedIdentity: readyStatus(
                    device,
                    identity: maskedIdentity,
                    purpose: .straightAlbedo,
                    content: .color(.resolved(.straightAlpha))
                ),
            ],
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let activeDefaultMaskShader = contract(
            revision: "active-default-mask-with-presence-combo",
            secondSamplerMetadata:
                #"{"mode":"opacitymask","combo":"MASK","default":"textures/optional-default-mask.tex"}"#,
            maskedAlpha: true
        )
        let activeDefaultUniforms = [
            staticDeclaration("alpha", components: [0.5]),
        ]
        let activeDefaultTemplate = template(
            activeDefaultMaskShader,
            includePrimaryCandidate: false,
            uniformDeclarations: activeDefaultUniforms
        )
        guard let activeDefaultMaskCache = SceneResolvedMaterialVariantCache(
            template: activeDefaultTemplate,
            maximumVariantCount: 8
        ) else {
            fatalError("active default fixture cache rejected")
        }
        let activeDefaultLaunch = activeDefaultMaskCache.precompileLaunchEnvelope(
            implicitFramebufferIdentity: graphTexture(),
            assetStates: [
                SceneAssetTextureIdentity(
                    path: optionalDefaultPath,
                    purpose: .mask
                ): .ready(.data),
            ]
        )
        let activeDefaultLaunchMasks: [UInt8]? = switch activeDefaultLaunch {
        case let .success(masks): masks
        case .failure: nil
        }
        let activeDefaultMaskProgram = finalize(
            shader: activeDefaultMaskShader,
            device: device,
            includePrimaryCandidate: false,
            additionalEntries: [
                optionalDefaultIdentity: optionalDefaultEntry,
            ],
            uniformDeclarations: activeDefaultUniforms,
            implicitFramebufferIdentity: graphTexture(),
            variantCache: activeDefaultMaskCache
        )
        let activeDefaultMaskAccepted: Bool = {
            guard case let .success(program) = activeDefaultMaskProgram,
                  let mask = program.textureSlots[1],
                  case let .asset(reference) = mask.reference,
                  reference == optionalDefaultPath,
                  mask.diagnosticSelectionProvenance == .shaderDefault,
                  mask.expectedPurpose == .mask,
                  case .data = mask.resource.publication.candidate.content else {
                return false
            }
            return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
                && program.semanticIdentity.colorContract.fragmentOutput
                    == .premultipliedAlpha
        }()
        let activeDefaultMaskMissing = finalize(
            shader: activeDefaultMaskShader,
            device: device,
            includePrimaryCandidate: false,
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let optionalUntypedMask = finalize(
            shader: contract(
                revision: "optional-mask-with-untyped-resource",
                secondSamplerMetadata: #"{"combo":"MASK"}"#,
                maskedAlpha: true,
                optionalMask: true,
                deadMaskCoordinates: true
            ),
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [
                maskedIdentity: readyStatus(
                    device,
                    identity: maskedIdentity,
                    purpose: .mask,
                    content: .data
                ),
            ],
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let maskedMissing = finalize(
            shader: maskedShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let maskedPending = finalize(
            shader: maskedShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [maskedIdentity: .pending],
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let maskedWrongPurpose = finalize(
            shader: maskedShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [
                maskedIdentity: readyStatus(
                    device,
                    identity: maskedIdentity,
                    purpose: .straightAlbedo,
                    content: .color(.resolved(.straightAlpha))
                ),
            ],
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let maskedColorAuxiliary = finalize(
            shader: maskedShader,
            device: device,
            includePrimaryCandidate: false,
            secondReference: .asset(maskedPath),
            additionalEntries: [
                maskedIdentity: readyStatus(
                    device,
                    identity: maskedIdentity,
                    purpose: .mask,
                    content: .color(.resolved(.straightAlpha))
                ),
            ],
            uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
            implicitFramebufferIdentity: graphTexture()
        )
        let propertyRequest = Template.UserPropertyRequest(key: "fixtureMask")
        let propertyIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: propertyRequest.key,
            purpose: .mask
        )!
        let propertyProgram = finalize(
            shader: contract(
                revision: "property-reference",
                secondSamplerMetadata: maskMetadata
            ),
            device: device,
            secondReference: .userProperty(propertyRequest),
            additionalEntries: [
                .materialUserProperty(propertyIdentity):
                    readyStatus(
                        device,
                        identity: .materialUserProperty(propertyIdentity),
                        purpose: .mask,
                        content: .data
                    ),
            ]
        )
        let providerProgram = finalize(
            shader: contract(
                revision: "provider-reference",
                secondSamplerMetadata: maskMetadata
            ),
            device: device,
            secondReference: .provider(.system("fixture-mask-provider")),
            additionalEntries: [
                .system("fixture-mask-provider"):
                    readyStatus(
                        device,
                        identity: .system("fixture-mask-provider"),
                        purpose: .mask,
                        content: .data
                    ),
            ]
        )
        let fallbackAssetPath = SceneVFSAssetPath("textures/fallback-mask.tex")!
        let fallbackProperty = Template.UserPropertyRequest(key: "optionalMask")
        let fallbackPropertyIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: fallbackProperty.key,
            purpose: .mask
        )!
        let providerUnavailableDoesNotFallback = finalize(
            shader: contract(
                revision: "provider-unavailable-fallback",
                secondSamplerMetadata: maskMetadata
            ),
            device: device,
            secondCandidates: [
                .init(reference: .asset(fallbackAssetPath), provenance: .instance),
                .init(reference: .userProperty(fallbackProperty), provenance: .userTexture),
            ],
            additionalEntries: [
                .asset(.init(path: fallbackAssetPath, purpose: .mask)):
                    readyStatus(
                        device,
                        identity: .asset(.init(
                            path: fallbackAssetPath,
                            purpose: .mask
                        )),
                        purpose: .mask,
                        content: .data
                    ),
                .materialUserProperty(fallbackPropertyIdentity): .unavailable,
            ]
        )
        let providerAbsentFallback = finalize(
            shader: contract(
                revision: "provider-absent-fallback",
                secondSamplerMetadata: maskMetadata
            ),
            device: device,
            secondCandidates: [
                .init(reference: .asset(fallbackAssetPath), provenance: .instance),
                .init(reference: .userProperty(fallbackProperty), provenance: .userTexture),
            ],
            additionalEntries: [
                .asset(.init(path: fallbackAssetPath, purpose: .mask)):
                    readyStatus(
                        device,
                        identity: .asset(.init(
                            path: fallbackAssetPath,
                            purpose: .mask
                        )),
                        purpose: .mask,
                        content: .data
                    ),
                .materialUserProperty(fallbackPropertyIdentity): .absent,
            ]
        )
        let providerMissingDoesNotFallback = finalize(
            shader: contract(
                revision: "provider-missing-no-fallback",
                secondSamplerMetadata: maskMetadata
            ),
            device: device,
            secondCandidates: [
                .init(reference: .asset(fallbackAssetPath), provenance: .instance),
                .init(reference: .userProperty(fallbackProperty), provenance: .userTexture),
            ],
            additionalEntries: [
                .asset(.init(path: fallbackAssetPath, purpose: .mask)):
                    readyStatus(
                        device,
                        identity: .asset(.init(
                            path: fallbackAssetPath,
                            purpose: .mask
                        )),
                        purpose: .mask,
                        content: .data
                    ),
            ]
        )
        let providerPendingDoesNotFallback = finalize(
            shader: contract(
                revision: "provider-pending-no-fallback",
                secondSamplerMetadata: maskMetadata
            ),
            device: device,
            secondCandidates: [
                .init(reference: .asset(fallbackAssetPath), provenance: .instance),
                .init(reference: .userProperty(fallbackProperty), provenance: .userTexture),
            ],
            additionalEntries: [
                .asset(.init(path: fallbackAssetPath, purpose: .mask)):
                    readyStatus(
                        device,
                        identity: .asset(.init(
                            path: fallbackAssetPath,
                            purpose: .mask
                        )),
                        purpose: .mask,
                        content: .data
                    ),
                .materialUserProperty(fallbackPropertyIdentity): .pending,
            ]
        )
        let shaderDefaultAfterUnavailableProvider = finalize(
            shader: contract(
                revision: "provider-unavailable-shader-default",
                secondSamplerMetadata:
                    #"{"mode":"opacitymask","default":"textures/default-mask.tex"}"#
            ),
            device: device,
            secondCandidates: [
                .init(reference: .userProperty(fallbackProperty), provenance: .userTexture),
            ],
            additionalEntries: [
                .asset(.init(
                    path: SceneVFSAssetPath("textures/default-mask.tex")!,
                    purpose: .mask
                )): readyStatus(
                    device,
                    identity: .asset(.init(
                        path: SceneVFSAssetPath("textures/default-mask.tex")!,
                        purpose: .mask
                    )),
                    purpose: .mask,
                    content: .data
                ),
                .materialUserProperty(fallbackPropertyIdentity): .unavailable,
            ]
        )
        let shaderDefaultAfterAbsentProvider = finalize(
            shader: contract(
                revision: "provider-absent-shader-default",
                secondSamplerMetadata:
                    #"{"mode":"opacitymask","default":"textures/default-mask.tex"}"#
            ),
            device: device,
            secondCandidates: [
                .init(reference: .userProperty(fallbackProperty), provenance: .userTexture),
            ],
            additionalEntries: [
                .asset(.init(
                    path: SceneVFSAssetPath("textures/default-mask.tex")!,
                    purpose: .mask
                )): readyStatus(
                    device,
                    identity: .asset(.init(
                        path: SceneVFSAssetPath("textures/default-mask.tex")!,
                        purpose: .mask
                    )),
                    purpose: .mask,
                    content: .data
                ),
                .materialUserProperty(fallbackPropertyIdentity): .absent,
            ]
        )

        let renderSizeField = programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "mwxRenderSize"
        }!
        let expectedRenderSize = SceneResolvedMaterialUniformEncoder.encodeHost(
            .renderSize,
            type: renderSizeField.type,
            inputs: uniformInputs(),
            slots: programA.textureSlots
        )!
        let encodedRange = renderSizeField.offset
            ..< renderSizeField.offset + renderSizeField.type.byteSize
        let uniformLayoutCorrect = programA.uniformBytes.count
                == programA.frontendProgram.uniformLayout.byteSize
            && !programA.uniformBytes.isEmpty
            && programA.uniformBytes.subdata(in: encodedRange) == expectedRenderSize
        let effectProjectionField = programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "g_EffectTextureProjectionMatrixInverse"
        }!
        let effectProjectionEncoded = [0, 5, 10, 15].enumerated().allSatisfy {
            index, component in
            float(programA.uniformBytes, at: effectProjectionField.offset + component * 4)
                == Float(index + 2)
        }
        let layerModelField = programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "g_LayerModelMatrix"
        }!
        let layerModelEncoded = [0, 5, 10, 15].enumerated().allSatisfy {
            index, component in
            float(programA.uniformBytes, at: layerModelField.offset + component * 4)
                == Float(index + 6)
        }
        let forwardProjectionField = programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "g_EffectTextureProjectionMatrix"
        }!
        let expectedForwardDiagonal: [Float] = [0.5, 1.0 / 3.0, 0.25, 0.2]
        let forwardProjectionEncoded = [0, 5, 10, 15].enumerated().allSatisfy {
            index, component in
            abs(float(
                programA.uniformBytes,
                at: forwardProjectionField.offset + component * 4
            ) - expectedForwardDiagonal[index]) < 0.000_001
        }
        let parallaxField = programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "g_ParallaxPosition"
        }!
        let parallaxPositionEncoded =
            float(programA.uniformBytes, at: parallaxField.offset) == 0.75
            && float(programA.uniformBytes, at: parallaxField.offset + 4) == 0.625

        let failures: [String: String] = [
            "nonFramebufferDoesNotInject": failureToken(finalize(
                shader: contract(
                    revision: "non-framebuffer-no-injection",
                    samplerMetadata: #"{"material":"source"}"#
                ),
                device: device,
                includePrimaryCandidate: false,
                implicitFramebufferIdentity: graphTexture()
            )),
            "framebufferWithoutIdentity": failureToken(finalize(
                shader: contract(
                    revision: "framebuffer-without-identity",
                    samplerMetadata: #"{"material":"framebuffer"}"#
                ),
                device: device,
                includePrimaryCandidate: false
            )),
            "previousWithoutIdentity": failureToken(finalize(
                shader: contract(
                    revision: "previous-without-identity",
                    samplerMetadata: #"{"material":"previous"}"#
                ),
                device: device,
                includePrimaryCandidate: false
            )),
            "historicalFramebufferWithoutHidden": failureToken(finalize(
                shader: contract(
                    revision: "historical-framebuffer-without-hidden",
                    samplerMetadata:
                        #"{"material":"ui_editor_properties_framebuffer"}"#
                ),
                device: device,
                includePrimaryCandidate: false,
                implicitFramebufferIdentity: graphTexture()
            )),
            "historicalFramebufferLabelOnly": failureToken(finalize(
                shader: contract(
                    revision: "historical-framebuffer-label-only",
                    samplerMetadata:
                        #"{"material":"source","label":"ui_editor_properties_framebuffer","hidden":true}"#
                ),
                device: device,
                includePrimaryCandidate: false,
                implicitFramebufferIdentity: graphTexture()
            )),
            "unknownEditorMaterialAlias": failureToken(finalize(
                shader: contract(
                    revision: "unknown-editor-material-alias",
                    samplerMetadata:
                        #"{"material":"ui_editor_properties_source","hidden":true}"#
                ),
                device: device,
                includePrimaryCandidate: false,
                implicitFramebufferIdentity: graphTexture()
            )),
            "regularGraphSampler": failureToken(finalize(
                shader: contract(revision: "regular-graph-sampler"),
                device: device
            )),
            "customPurposeIgnored": failureToken(finalize(
                shader: contract(
                    revision: "custom-purpose",
                    samplerMetadata: #"{"purpose":"mask"}"#
                ),
                device: device
            )),
            "unknownMode": failureToken(finalize(
                shader: contract(
                    revision: "unknown-mode",
                    samplerMetadata: #"{"mode":"mystery"}"#
                ),
                device: device
            )),
            "authoredOverridesShaderDefault": failureToken(finalize(
                shader: contract(
                    revision: "authored-overrides-default",
                    samplerMetadata: #"{"default":"textures/fallback.tex"}"#
                ),
                device: device
            )),
            "authoredFailureDoesNotUseShaderDefault": failureToken(finalize(
                shader: contract(
                    revision: "authored-failure-no-default",
                    samplerMetadata: #"{"default":"textures/fallback.tex"}"#
                ),
                device: device,
                snapshotKind: .unavailable
            )),
            "missingUniformDefault": failureToken(finalize(
                shader: contract(
                    revision: "missing-uniform-default",
                    uniformMetadata: nil
                ),
                device: device
            )),
            "malformedUniformDefault": failureToken(finalize(
                shader: contract(
                    revision: "malformed-uniform-default",
                    uniformMetadata: #"{"material":"Tint","default":"1 nope 0"}"#
                ),
                device: device
            )),
            "knownTimelineScriptControl": failureToken(finalize(
                shader: contract(revision: "timeline-script-control"),
                device: device,
                uniformDeclarations: [dynamicDeclaration(
                    [.timeline],
                    controls: [.mediaThumbnailAnimationRestart]
                )],
                dynamicSource: .timeline
            )),
            "unknownTimelineScriptControl": failureToken(finalize(
                shader: contract(revision: "unknown-timeline-script-control"),
                device: device,
                uniformDeclarations: [dynamicDeclaration(
                    [.timeline],
                    controls: [.unprovenSceneScript]
                )],
                dynamicSource: .timeline
            )),
            "authoredDynamicFallback": failureToken(finalize(
                shader: contract(revision: "authored-dynamic-fallback"),
                device: device,
                uniformDeclarations: [dynamicDeclaration([.timeline])],
                dynamicSource: .authored
            )),
            "dynamicSourceMismatch": failureToken(finalize(
                shader: contract(revision: "dynamic-source-mismatch"),
                device: device,
                uniformDeclarations: [dynamicDeclaration([.timeline])],
                dynamicSource: .userProperty
            )),
            "multipleValueContributors": failureToken(finalize(
                shader: contract(revision: "multiple-value-contributors"),
                device: device,
                uniformDeclarations: [dynamicDeclaration([
                    .userProperty("first"), .userProperty("second"),
                ])]
            )),
            "runtimeLoopMetadataOnly": failureToken(finalize(
                shader: contract(
                    revision: "runtime-loop-metadata-only",
                    runtimeLoop: true,
                    runtimeLoopEditorHints: true
                ),
                device: device
            )),
            "runtimeLoopDynamicProducer": failureToken(finalize(
                shader: contract(
                    revision: "runtime-loop-dynamic-producer",
                    runtimeLoop: true
                ),
                device: device,
                uniformDeclarations: [dynamicScalarDeclaration("Fractals")]
            )),
            "runtimeLoopOverBudget": failureToken(finalize(
                shader: contract(
                    revision: "runtime-loop-over-budget",
                    runtimeLoop: true
                ),
                device: device,
                uniformDeclarations: [
                    staticDeclaration("Fractals", components: [257]),
                ]
            )),
            "runtimeLoopCrossTemplateCache":
                crossTemplateRuntimeLoopCacheToken(device),
            "multipleCandidates": failureToken(finalize(
                shader: contract(revision: "multiple-candidates"),
                device: device,
                candidateCount: 2
            )),
            "providerUnavailableDoesNotUseEarlierCandidate": failureToken(
                providerUnavailableDoesNotFallback
            ),
            "providerAbsentUsesEarlierCandidate": failureToken(providerAbsentFallback),
            "providerMissingDoesNotUseEarlierCandidate": failureToken(
                providerMissingDoesNotFallback
            ),
            "providerPendingDoesNotUseEarlierCandidate": failureToken(
                providerPendingDoesNotFallback
            ),
            "providerUnavailableDoesNotUseShaderDefault": failureToken(
                shaderDefaultAfterUnavailableProvider
            ),
            "providerAbsentUsesShaderDefault": failureToken(
                shaderDefaultAfterAbsentProvider
            ),
            "missingGraphIdentity": failureToken(finalize(
                shader: contract(revision: "missing-graph-identity"),
                device: device,
                snapshotKind: .missing
            )),
            "textureDynamicFrameMismatch": failureToken(finalize(
                shader: contract(revision: "texture-dynamic-frame-mismatch"),
                device: device,
                textureFrameIndex: 2
            )),
            "dynamicInputsFrameMismatch": failureToken(finalize(
                shader: contract(revision: "dynamic-inputs-frame-mismatch"),
                device: device,
                frameInputIndex: 2
            )),
            "pending": failureToken(finalize(
                shader: contract(revision: "pending"),
                device: device,
                snapshotKind: .pending
            )),
            "unavailable": failureToken(finalize(
                shader: contract(revision: "unavailable"),
                device: device,
                snapshotKind: .unavailable
            )),
            "incompletePublication": failureToken(finalize(
                shader: contract(revision: "incomplete-publication"),
                device: device,
                snapshotKind: .incomplete
            )),
            "purposeMismatch": failureToken(finalize(
                shader: contract(revision: "purpose-mismatch"),
                device: device,
                snapshotKind: .purposeMismatch
            )),
            "unsupportedSampler": failureToken(finalize(
                shader: contract(revision: "unsupported-sampler"),
                device: device,
                snapshotKind: .unsupportedSampler
            )),
            "slotSchemaMismatch": failureToken(finalize(
                shader: contract(revision: "slot-schema-mismatch"),
                device: device,
                slot: 1
            )),
            "unsupportedState": failureToken(finalize(
                shader: contract(revision: "unsupported-state"),
                device: device,
                renderState: state(blending: "translucent")
            )),
            "unresolvedPublication": failureToken(finalize(
                shader: contract(revision: "unresolved-publication"),
                device: device,
                snapshotKind: .unresolvedColor
            )),
            "dataGraphInput": failureToken(finalize(
                shader: contract(revision: "data-input"),
                device: device,
                snapshotKind: .data
            )),
            "arithmeticOutput": failureToken(finalize(
                shader: contract(revision: "arithmetic-output", arithmetic: true),
                device: device
            )),
            "maskedMissing": failureToken(maskedMissing),
            "maskedPending": failureToken(maskedPending),
            "maskedWrongPurpose": failureToken(maskedWrongPurpose),
            "maskedColorAuxiliary": failureToken(maskedColorAuxiliary),
            "overlayColorAuxiliary": failureToken(overlayColorAuxiliary),
            "optionalUntypedMask": failureToken(optionalUntypedMask),
            "optionalMaskPendingDoesNotUseDefault": failureToken(
                optionalMaskPending
            ),
            "optionalMaskWrongPurposeDoesNotUseDefault": failureToken(
                optionalMaskWrongPurpose
            ),
            "activeDefaultMaskMissing": failureToken(activeDefaultMaskMissing),
        ]

        let result: [String: Any] = [
            "metalAvailable": true,
            "activeDefaultCache": [
                "launchMasks": activeDefaultLaunchMasks?.map(Int.init) ?? [-1],
                "failure": failureToken(activeDefaultMaskProgram),
                "cached": activeDefaultMaskCache.counters.cachedVariantCount,
                "prepared": activeDefaultMaskCache.counters.shaderPreparationCount,
                "frontend": activeDefaultMaskCache.counters.frontendCompilationCount,
                "capacity": activeDefaultMaskCache.counters.capacityRejectionCount,
            ],
            "positive": [
                "fixedEightSlots": programA.textureSlots.count == 8
                    && programA.textureSlots[0] != nil
                    && programA.textureSlots.dropFirst().allSatisfy { $0 == nil },
                "uniformLayoutCorrect": uniformLayoutCorrect,
                "effectProjectionInverseEncoded": effectProjectionEncoded,
                "layerModelMatrixEncoded": layerModelEncoded,
                "effectProjectionEncoded": forwardProjectionEncoded,
                "parallaxPositionEncoded": parallaxPositionEncoded,
                "shaderUniformDefault": tintDefaultCorrect,
                "hostIgnoresShaderDefault": hostDefaultIgnored,
                "explicitUniformOverridesDefault": explicitOverrideCorrect,
                "stageLocalUniformsEncoded": stageLocalUniformsEncoded,
                "assetReferenceTyped": failureToken(assetProgram) == "success",
                "userReferenceTyped": failureToken(propertyProgram) == "success",
                "providerReferenceTyped": failureToken(providerProgram) == "success",
                "maskedDynamicAlphaEncoded": maskedDynamicAlphaEncoded,
                "sceneScriptDynamicAlphaEncoded": sceneScriptDynamicAlphaEncoded,
                "overlayDataTyped": overlayDataTyped,
                "optionalMaskWithoutResourceAccepted":
                    optionalMaskWithoutResourceAccepted,
                "optionalMaskWithResourceAccepted":
                    optionalMaskWithResourceAccepted,
                "activeDefaultMaskAccepted": activeDefaultMaskAccepted,
                "implicitFramebufferTyped": implicitFramebufferTyped,
                "previousMaterialAliasTyped": previousAliasTyped,
                "historicalFramebufferMaterialAliasTyped":
                    historicalFramebufferTyped,
                "stockDefaultProgramPreservesSnapshotAtoms":
                    stockDefaultProgramPreservesSnapshotAtoms,
                "implicitFramebufferMaterialKeyCaseInsensitive":
                    failureToken(caseInsensitiveFramebufferProgram) == "success",
                "explicitFramebufferCandidatePreserved":
                    explicitFramebufferPreserved,
                "shaderDefaultPreservedBeforeImplicitFramebuffer":
                    shaderDefaultPreserved,
                "realPreparationObserved": !programA.preparedShader.cacheKey.isEmpty
                    && !programA.preparedShader.vertex.dependencies.isEmpty
                    && !programA.preparedShader.fragment.dependencies.isEmpty,
                "frontendObserved": programA.frontendProgram.textureBindings.map(\.slot) == [0],
                "audioSpectrumArraysEncoded": audioSpectrumEncoded,
                "runtimeLoopStaticProducerAccepted":
                    runtimeLoopStaticProducerAccepted,
            ],
            "identity": [
                "semanticStable": programA.semanticIdentity == programB.semanticIdentity,
                "exactRevisionSensitive": programA.exactIdentity != programB.exactIdentity,
            ],
            "samplerSchema": [
                "regularGraph": samplerPurposeToken(nil),
                "regularAsset": samplerPurposeToken(nil, assetReference: true),
                "albedoAsset": samplerPurposeToken(
                    #"{"material":"albedo"}"#,
                    assetReference: true
                ),
                "noiseAsset": samplerPurposeToken(
                    #"{"material":"noise"}"#,
                    assetReference: true
                ),
                "normalAsset": samplerPurposeToken(
                    #"{"material":"normal"}"#,
                    assetReference: true
                ),
                "normalAssetCaseInsensitive": samplerPurposeToken(
                    #"{"material":"Normal"}"#,
                    assetReference: true
                ),
                "registeredStockNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/noise"
                ),
                "registeredStockWaterFlowPhase": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "effects/waterflowphase"
                ),
                "registeredStockShimmerGradient": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "gradient/gradient_ferro_fluid"
                ),
                "registeredStockLightShaftsGradient": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "gradient/gradient_iridescent"
                ),
                "registeredStockFireGradient": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "gradient/gradient_fire"
                ),
                "registeredStockFireGradientConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "gradient/gradient_fire"
                ),
                "unregisteredGradient": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "gradient/unknown"
                ),
                "registeredStockCloudNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/clouds_256"
                ),
                "registeredStockPurposeConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "util/noise"
                ),
                "unknownMaterialAsset": samplerPurposeToken(
                    #"{"material":"unknown"}"#,
                    assetReference: true
                ),
                "conflictingMaterial": samplerPurposeToken(
                    #"{"material":"normal"}"#,
                    vertexMetadata: #"{"material":"noise"}"#,
                    assetReference: true
                ),
                "reachableConditionalAlbedo": reachableConditionalPurposeToken(),
                "customPurposeIgnored": samplerPurposeToken(#"{"purpose":"mask"}"#),
                "opacityMask": samplerPurposeToken(#"{"mode":"opacitymask"}"#),
                "rgbMask": samplerPurposeToken(#"{"mode":"rgbmask"}"#),
                "flowMask": samplerPurposeToken(#"{"mode":"flowmask"}"#),
                "normal": samplerPurposeToken(#"{"mode":"normal"}"#),
                "depth": samplerPurposeToken(#"{"mode":"depth"}"#),
                "depthR8": samplerPurposeToken(
                    #"{"mode":"depth","format":"r8"}"#
                ),
                "depthWrongFormat": samplerPurposeToken(
                    #"{"mode":"depth","format":"rgba8"}"#
                ),
                "normalFormat": samplerPurposeToken(#"{"format":"normalmap"}"#),
                "genericFormat": samplerPurposeToken(#"{"format":"rgba8"}"#),
                "unknownMode": samplerPurposeToken(#"{"mode":"mystery"}"#),
            ],
            "samplerSchemaOrigin": [
                "unmarkedReadiness": samplerReadinessSchemaToken(
                    #"{"mode":"opacitymask","combo":"MASK","default":"textures/mask.tex"}"#
                ),
                "authoredMarker": samplerReadinessSchemaToken(
                    #"[COMBO] {"combo":"AUTHORED","default":1}"#
                ),
            ],
            "implicitFramebufferSchema": [
                "registeredStockDefault": implicitFramebufferProjectionToken(
                    defaultAssetPath: "util/noise"
                ),
                "registeredAuthoredCandidate":
                    implicitFramebufferCandidateProjectionToken(
                        assetPath: "effects/waterflowphase"
                    ),
                "unknownDefault": implicitFramebufferProjectionToken(
                    defaultAssetPath: "textures/unknown-default.tex"
                ),
            ],
            "shaderPreparationBoundary": [
                "missingSourceGraph": missingSourceGraphDiagnostic(),
            ],
            "failures": failures,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialProgramFinalizerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-finalizer-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "resolved-material-finalizer-test"
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
                "-framework",
                "ImageIO",
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
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_real_preparation_frontend_uniforms_and_derivation_produce_program(self) -> None:
        self.assertEqual(
            [name for name, passed in self.result["positive"].items() if not passed],
            [],
            self.result,
        )
        self.assertEqual(
            self.result["activeDefaultCache"],
            {
                "launchMasks": [1],
                "failure": "success",
                "cached": 1,
                "prepared": 1,
                "frontend": 1,
                "capacity": 0,
            },
            self.result,
        )

    def test_shader_preparation_requires_typed_source_graph(self) -> None:
        self.assertEqual(
            self.result["shaderPreparationBoundary"]["missingSourceGraph"],
            "shader-preprocessor/shader-source-graph-missing/0",
        )
        product_sources = {
            path: path.read_text(encoding="utf-8")
            for path in SCENE_ROOT.rglob("*.swift")
        }
        for retired_token in (
            "fallbackGraph(",
            ".legacyContract",
            "case legacyContract",
        ):
            offenders = [
                str(path.relative_to(REPOSITORY_ROOT))
                for path, source in product_sources.items()
                if retired_token in source
            ]
            self.assertEqual(offenders, [], retired_token)

    def test_semantic_and_exact_identity_boundaries(self) -> None:
        self.assertEqual(
            [name for name, passed in self.result["identity"].items() if not passed],
            [],
            self.result,
        )

    def test_purpose_selection_and_binding_fail_closed(self) -> None:
        expected = {
            "nonFramebufferDoesNotInject": "texture/textureBindingInvalid",
            "framebufferWithoutIdentity": "texture/textureBindingInvalid",
            "previousWithoutIdentity": "texture/textureBindingInvalid",
            "historicalFramebufferWithoutHidden":
                "texture/textureBindingInvalid",
            "historicalFramebufferLabelOnly": "texture/textureBindingInvalid",
            "unknownEditorMaterialAlias": "texture/textureBindingInvalid",
            "regularGraphSampler": "success",
            "customPurposeIgnored": "success",
            "unknownMode": "texture/activeSamplerSchemaInvalid",
            "multipleCandidates": "success",
            "providerUnavailableDoesNotUseEarlierCandidate": (
                "texture/resourceSnapshotUnresolved"
            ),
            "providerAbsentUsesEarlierCandidate": "success",
            "providerMissingDoesNotUseEarlierCandidate": (
                "texture/resourceSnapshotUnresolved"
            ),
            "providerPendingDoesNotUseEarlierCandidate": (
                "texture/resourceSnapshotUnresolved"
            ),
            "providerUnavailableDoesNotUseShaderDefault": (
                "texture/resourceSnapshotUnresolved"
            ),
            "providerAbsentUsesShaderDefault": "success",
            "slotSchemaMismatch": "texture/texturePurposeUnproven",
            "optionalUntypedMask": "texture/texturePurposeUnproven",
            "authoredOverridesShaderDefault": "success",
            "authoredFailureDoesNotUseShaderDefault": (
                "texture/resourceSnapshotUnresolved"
            ),
            "optionalMaskPendingDoesNotUseDefault": (
                "texture/resourceSnapshotUnresolved"
            ),
            "optionalMaskWrongPurposeDoesNotUseDefault": (
                "texture/textureMetadataIncomplete"
            ),
            "activeDefaultMaskMissing": "texture/resourceSnapshotUnresolved",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )

    def test_official_sampler_modes_are_typed_without_custom_purpose(self) -> None:
        self.assertEqual(
            self.result["samplerSchema"],
            {
                "regularGraph": "premultiplied-color",
                "regularAsset": "unproven",
                "albedoAsset": "straight-albedo",
                "noiseAsset": "noise",
                "normalAsset": "normal",
                "normalAssetCaseInsensitive": "normal",
                "registeredStockNoise": "noise",
                "registeredStockWaterFlowPhase": "phase",
                "registeredStockShimmerGradient": "preserved-channels",
                "registeredStockLightShaftsGradient": "preserved-channels",
                "registeredStockFireGradient": "preserved-channels",
                "registeredStockFireGradientConflict": "unproven",
                "unregisteredGradient": "unproven",
                "registeredStockCloudNoise": "noise",
                "registeredStockPurposeConflict": "unproven",
                "unknownMaterialAsset": "unproven",
                "conflictingMaterial": "schema-invalid",
                "reachableConditionalAlbedo": "straight-albedo",
                "customPurposeIgnored": "premultiplied-color",
                "opacityMask": "mask",
                "rgbMask": "preserved-channels",
                "flowMask": "flow",
                "normal": "schema-invalid",
                "depth": "depth",
                "depthR8": "depth",
                "depthWrongFormat": "schema-invalid",
                "normalFormat": "schema-invalid",
                "genericFormat": "schema-invalid",
                "unknownMode": "schema-invalid",
            },
        )

    def test_registered_stock_default_unblocks_only_typed_implicit_input(self) -> None:
        self.assertEqual(
            self.result["implicitFramebufferSchema"],
            {
                "registeredStockDefault": "0",
                "registeredAuthoredCandidate": "0",
                "unknownDefault": "",
            },
        )

    def test_only_unmarked_sampler_combo_becomes_readiness_schema(self) -> None:
        self.assertEqual(
            self.result["samplerSchemaOrigin"],
            {
                "unmarkedReadiness": "MASK|asset",
                "authoredMarker": "none|none",
            },
        )

    def test_snapshot_identity_and_metadata_states_remain_distinct(self) -> None:
        expected = {
            "missingGraphIdentity": "texture/resourceSnapshotUnresolved",
            "pending": "texture/resourceSnapshotUnresolved",
            "unavailable": "texture/resourceSnapshotUnresolved",
            "incompletePublication": "texture/textureMetadataIncomplete",
            "purposeMismatch": "texture/textureMetadataIncomplete",
            "unresolvedPublication": "texture/textureMetadataIncomplete",
            "unsupportedSampler": "texture/textureMetadataIncomplete",
            "textureDynamicFrameMismatch": "invariant/frameSnapshotMismatch",
            "dynamicInputsFrameMismatch": "invariant/frameSnapshotMismatch",
            "maskedMissing": "texture/resourceSnapshotUnresolved",
            "maskedPending": "texture/resourceSnapshotUnresolved",
            "maskedWrongPurpose": "texture/textureMetadataIncomplete",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )

    def test_shader_defaults_and_dynamic_contributors_are_fail_closed(self) -> None:
        expected = {
            "missingUniformDefault": "uniform/uniformBindingInvalid",
            "malformedUniformDefault": "uniform/uniformBindingInvalid",
            "knownTimelineScriptControl": "success",
            "unknownTimelineScriptControl": "uniform/uniformControlUnproven",
            "authoredDynamicFallback": "success",
            "dynamicSourceMismatch": "uniform/uniformBindingInvalid",
            "multipleValueContributors": "uniform/uniformContributorPolicyUnproven",
            "runtimeLoopMetadataOnly": "preparation/activeSamplerSchemaInvalid",
            "runtimeLoopDynamicProducer": "preparation/activeSamplerSchemaInvalid",
            "runtimeLoopOverBudget": "preparation/activeSamplerSchemaInvalid",
            "runtimeLoopCrossTemplateCache": "invariant/identityInvariant",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )

    def test_render_state_and_color_contracts_fail_closed(self) -> None:
        expected = {
            "unsupportedState": "state/renderStateInvalid",
            "dataGraphInput": "texture/textureMetadataIncomplete",
            "arithmeticOutput": "color/colorContractUnproven",
            "maskedColorAuxiliary": "texture/textureMetadataIncomplete",
            "overlayColorAuxiliary": "texture/textureMetadataIncomplete",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )


if __name__ == "__main__":
    unittest.main()
