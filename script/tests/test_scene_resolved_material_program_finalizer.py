#!/usr/bin/env python3

"""End-to-end R3 finalization from authored contract to immutable Program."""

from __future__ import annotations

import hashlib
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
STOCK_MATERIAL_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/materials"
)
VISUAL_PASSTHROUGH_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
)
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


FINALIZER_SOURCE = next(
    source
    for source in scene_swift_sources("resolved_material_frame_finalization")
    if source.name == "SceneResolvedMaterialProgramFinalizer.swift"
)
VARIANT_CACHE_SOURCE = next(
    source
    for source in scene_swift_sources("resolved_material_frame_finalization")
    if source.name == "SceneResolvedMaterialExecutionCapabilityVariant.swift"
)


SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    *scene_swift_sources("authored_shader_frontend_implementation"),
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrameInputs.swift",
    *scene_swift_sources("authored_shader_preparation_implementation"),
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
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
    *scene_swift_sources("resolved_material_frame_finalization"),
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
        case shaderDirectiveUnsupported = "shader-directive-unsupported", shaderModuleResolutionRejected = "shader-module-resolution-rejected"
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
    uniform mat4 g_ModelViewProjectionMatrixInverse;
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
        mat4 modelViewProjectionInverseProbe = g_ModelViewProjectionMatrixInverse;
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
    directRedInput: Bool = false,
    stageLocalUniforms: Bool = false,
    runtimeLoop: Bool = false,
    runtimeLoopEditorHints: Bool = false,
    pointerState: Bool = false,
    semanticProbes: Bool = true,
    scalarSplatScale: Bool = false,
    colorBlend: Bool = false,
    legacyMaskOverride: Bool = false
) -> String {
    if colorBlend {
        let maskMutation = legacyMaskOverride ? "=" : "*="
        return """
        // [COMBO] {"material":"ui_editor_properties_blend_mode","combo":"BLENDMODE","type":"imageblending","default":30}
        varying vec4 v_TexCoord;
        uniform sampler2D g_Texture0; // {"hidden":true}
        uniform sampler2D g_Texture1; // {"mode":"opacitymask","combo":"MASK"}
        uniform float g_BlendAlpha; // {"material":"alpha","default":1}
        uniform vec3 g_TintColor; // {"material":"color","type":"color","default":"1 0 0"}
        vec3 ApplyBlending(
            const int mode,
            in vec3 base,
            in vec3 blend,
            in float opacity
        ) {
            return mix(base, blend, opacity);
        }
        void main() {
            vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
            float mask = g_BlendAlpha;
        #if MASK
            mask \(maskMutation) texSample2D(g_Texture1, v_TexCoord.zw).r;
        #endif
            albedo.rgb = ApplyBlending(BLENDMODE, albedo.rgb, g_TintColor, mask);
        #if BLENDMODE == 0
            albedo.a = 1.0;
        #endif
            gl_FragColor = albedo;
        }
        """
    }
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
    } else if directRedInput {
        output = """
        float scalar = texSample2D(g_Texture0, v_TexCoord).r;
        gl_FragColor = vec4(scalar);
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
    let scalarSplatUniform = scalarSplatScale
        ? #"uniform vec2 u_Scale; // {"material":"scale","default":"1 1"}"#
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
    let metadataProbes = semanticProbes
        ? "vec3 tintProbe = u_Tint;\nfloat timeProbe = g_Time;"
        : ""
    let scalarSplatProbe = scalarSplatScale ? "vec2 scaleProbe = u_Scale;" : ""
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
    let pointerStateUniform = pointerState ? "uniform vec4 g_PointerState;" : ""
    let pointerStateProbe = pointerState ? "vec4 pointerState = g_PointerState;" : ""
    return """
    varying \(optionalMask ? "vec4" : "vec2") v_TexCoord;
    \(combo)
    uniform sampler2D g_Texture0;\(annotation)
    \(secondSampler)
    \(pointerStateUniform)
    \(audioUniforms)
    uniform vec3 u_Tint;\(uniformAnnotation)
    \(alphaUniform)
    \(scalarSplatUniform)
    \(overlayUniforms)
    uniform float g_Time; // {"default":99}
    \(stageLocalUniform)
    \(runtimeLoopUniform)
    \(overlayHelper)
    void main() {
        \(stageLocalProbe)
        \(runtimeLoopProbe)
        \(pointerStateProbe)
        \(audioProbe)
        \(metadataProbes)
        \(scalarSplatProbe)
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
    directRedInput: Bool = false,
    deadMaskCoordinates: Bool = false,
    stageLocalUniforms: Bool = false,
    runtimeLoop: Bool = false,
    runtimeLoopEditorHints: Bool = false,
    pointerState: Bool = false,
    semanticProbes: Bool = true,
    scalarSplatScale: Bool = false,
    colorBlend: Bool = false,
    legacyMaskOverride: Bool = false,
    includeSourceGraph: Bool = true,
    vertexSourceOverride: String? = nil,
    fragmentSourceOverride: String? = nil
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
            source: vertexSourceOverride ?? vertexSource(
                samplerMetadata: vertexSamplerMetadata,
                deadMaskCoordinates: deadMaskCoordinates || colorBlend,
                stageLocalUniforms: stageLocalUniforms
            )
        ),
        stage(
            .fragment,
            path: "\(revision)/root.frag",
            source: fragmentSourceOverride ?? fragmentSource(
                samplerMetadata: samplerMetadata,
                uniformMetadata: uniformMetadata,
                secondSamplerMetadata: secondSamplerMetadata,
                conditionalSecondSampler: conditionalSecondSampler,
                arithmetic: arithmetic,
                audioSpectrum: audioSpectrum,
                maskedAlpha: maskedAlpha,
                overlayAlphaBlend: overlayAlphaBlend,
                optionalMask: optionalMask,
                directRedInput: directRedInput,
                stageLocalUniforms: stageLocalUniforms,
                runtimeLoop: runtimeLoop,
                runtimeLoopEditorHints: runtimeLoopEditorHints,
                pointerState: pointerState,
                semanticProbes: semanticProbes,
                scalarSplatScale: scalarSplatScale,
                colorBlend: colorBlend,
                legacyMaskOverride: legacyMaskOverride
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

private func framebufferTexture() -> Graph.TextureIdentity {
    .init(
        kind: .framebuffer,
        layerID: fixtureLayerID,
        effect: .init(
            layerID: fixtureLayerID,
            effectIndex: 0,
            descriptorID: "fixture-scalar-producer"
        ),
        name: nil
    )
}

private func effectOutputTexture(_ descriptorID: String) -> Graph.TextureIdentity {
    .init(
        kind: .effectOutput,
        layerID: fixtureLayerID,
        effect: .init(
            layerID: fixtureLayerID,
            effectIndex: descriptorID == "fixture-prior" ? 0 : 1,
            descriptorID: descriptorID
        ),
        name: nil
    )
}

private func namedFramebufferTexture() -> Graph.TextureIdentity {
    .init(
        kind: .framebuffer,
        layerID: fixtureLayerID,
        effect: .init(
            layerID: fixtureLayerID,
            effectIndex: 1,
            descriptorID: "fixture-current"
        ),
        name: "fixture-history-target"
    )
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

private func candidates(
    _ count: Int,
    primaryReference: Template.TextureReference = .graph(graphTexture())
) -> [Template.TextureCandidate] {
    (0 ..< count).map { index in
        .init(
            reference: index == count - 1
                ? primaryReference
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
    attachments: [Template.DynamicUniformScriptAttachment] = []
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
            scriptAttachments: attachments,
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
            scriptAttachments: [],
            authoredFallback: staticValue([1]),
            authoredBindingKeys: ["value"]
        ))
    )
}

private func dynamicScaleDeclaration(
    fallback: [Double] = [0.6],
    contributors: [Template.DynamicUniformSource] = [
        .userProperty("unseenScaleProperty"),
    ],
    bindingKeys: [String] = ["user", "value"]
) -> Template.UniformDeclaration {
    .init(
        name: "scale",
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: "scale"
            ),
            valueContributors: contributors,
            scriptAttachments: [],
            authoredFallback: .init(
                valueKind: "binding",
                componentBitPatterns: fallback.map(\.bitPattern),
                authoredBindingKeys: bindingKeys
            ),
            authoredBindingKeys: bindingKeys
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
            scriptAttachments: [],
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
    primaryReference: Template.TextureReference = .graph(graphTexture()),
    effectInputGraphTextureRole: Template.GraphTextureRole = .layerSource,
    primaryGraphTextureRole: Template.GraphTextureRole = .layerSource,
    graphBindingsOverride: [Template.GraphBindingRole]? = nil,
    secondReference: Template.TextureReference? = nil,
    secondCandidates: [Template.TextureCandidate]? = nil,
    comboValues: [String: Int] = [:],
    uniformDeclarations: [Template.UniformDeclaration] = [],
    renderState: SceneMaterialRenderState = state(),
    textureSlotsOverride: [Template.TextureSlot?]? = nil,
    effectContext: Template.EffectContext? = nil
) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    if includePrimaryCandidate {
        slots[slot] = .init(
            index: slot,
            candidates: candidates(
                candidateCount,
                primaryReference: primaryReference
            )
        )
    }
    if let secondCandidates {
        slots[1] = .init(index: 1, candidates: secondCandidates)
    } else if let secondReference {
        slots[1] = .init(index: 1, candidates: [
            .init(reference: secondReference, provenance: .instance),
        ])
    }
    if let textureSlotsOverride {
        slots = textureSlotsOverride
    }
    return Template.validated(
        textureSlots: slots,
        combos: comboValues.map { .init(name: $0.key, value: $0.value) },
        uniformDeclarations: uniformDeclarations,
        renderState: renderState,
        graphRole: .init(
            effectInput: effectInputGraphTextureRole,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: graphBindingsOverride ?? (includePrimaryCandidate
                ? [.init(slot: slot, texture: primaryGraphTextureRole)] : [])
        ),
        effectContext: effectContext,
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

private func texture(
    _ device: MTLDevice,
    pixelFormat: MTLPixelFormat = .rgba8Unorm,
    size: CGSize = CGSize(width: 2, height: 2)
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat,
        width: Int(size.width),
        height: Int(size.height),
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
    sampling: SceneTextureSampling = .directImageFallback,
    pixelFormat: MTLPixelFormat = .rgba8Unorm,
    authoredFormat: SceneShaderTextureFormat? = nil,
    physicalSize: CGSize = CGSize(width: 2, height: 2),
    mappedSize: CGSize = CGSize(width: 2, height: 2),
    uvTransform: SceneTextureUVTransform = .identity,
    candidateIdentity: SceneTextureResourceIdentity = .provider(.video(
        layerID: fixtureLayerID,
        lifecycleEpoch: 1
    ))
) -> SceneTextureProviderPublication {
    .init(
        requestIdentity: requestIdentity,
        candidate: .init(
            texture: texture(
                device,
                pixelFormat: pixelFormat,
                size: physicalSize
            ),
            identity: candidateIdentity,
            generation: .provider(contentGeneration: candidateGeneration),
            purpose: purpose,
            content: content,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: uvTransform,
            sampling: sampling,
            authoredFormat: authoredFormat
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
    content: SceneTextureContent,
    physicalSize: CGSize = CGSize(width: 2, height: 2),
    mappedSize: CGSize = CGSize(width: 2, height: 2),
    uvTransform: SceneTextureUVTransform = .identity
) -> SceneFrameTextureLookupStatus {
    .ready(.init(
        publication: publication(
            device,
            requestIdentity: identity,
            purpose: purpose,
            content: content,
            candidateGeneration: 7,
            contentGeneration: 7,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: uvTransform
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
    primaryButtonIsDown: Bool = false,
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
        pointerPrimaryButtonDown: primaryButtonIsDown,
        parallaxPositionNDC: SIMD2(0.5, -0.25),
        audioSpectrum: audioSpectrum
    )
}

private func dynamicSnapshot(
    frameIndex: UInt64,
    source: SceneDynamicSource?,
    tintValue: SceneDynamicValue = .vector3(1, 0.5, 0.25),
    authoredTintValue: SceneDynamicValue = .vector3(1, 0.5, 0.25),
    scaleValue: SceneDynamicValue = .scalar(0.6),
    authoredScaleValue: SceneDynamicValue = .scalar(1)
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
    let scaleTarget = SceneDynamicTarget.effectConstant(
        layerID: fixtureLayerID,
        effectIndex: 0,
        passIndex: 0,
        name: "scale"
    )
    let alphaValue = SceneDynamicValue.scalar(0.25)
    var user: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var timeline: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var script: [SceneDynamicTarget: SceneDynamicValue] = [:]
    switch source {
    case .userProperty:
        user[tintTarget] = tintValue
        user[alphaTarget] = alphaValue
        user[scaleTarget] = scaleValue
    case .timeline:
        timeline[tintTarget] = tintValue
        timeline[alphaTarget] = alphaValue
        timeline[scaleTarget] = scaleValue
    case .sceneScript:
        script[tintTarget] = tintValue
        script[alphaTarget] = alphaValue
        script[scaleTarget] = scaleValue
    case .authored, nil: break
    }
    return SceneDynamicSnapshotResolver().resolve(
        frameIndex: frameIndex,
        generation: 1,
        definitions: [
            .init(
                target: tintTarget,
                valueType: authoredTintValue.valueType,
                authoredValue: authoredTintValue
            ),
            .init(
                target: alphaTarget,
                valueType: .scalar,
                authoredValue: .scalar(1)
            ),
            .init(
                target: scaleTarget,
                valueType: authoredScaleValue.valueType,
                authoredValue: authoredScaleValue
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
    primaryReference: Template.TextureReference = .graph(graphTexture()),
    primaryGraphTextureRole: Template.GraphTextureRole = .layerSource,
    graphBindingsOverride: [Template.GraphBindingRole]? = nil,
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
    primaryButtonIsDown: Bool = false,
    dynamicSource: SceneDynamicSource? = nil,
    dynamicTintValue: SceneDynamicValue = .vector3(1, 0.5, 0.25),
    authoredTintValue: SceneDynamicValue = .vector3(1, 0.5, 0.25),
    dynamicScaleValue: SceneDynamicValue = .scalar(0.6),
    authoredScaleValue: SceneDynamicValue = .scalar(1),
    renderState: SceneMaterialRenderState = state(),
    resolvedLayerModelMatrix: simd_float4x4 = layerModelMatrix,
    implicitFramebufferIdentity: Graph.TextureIdentity? = nil,
    audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent,
    variantCache: SceneResolvedMaterialVariantCache? = nil,
    outputStorage: Program.OutputStorage = .color,
    graphTextureFormatFacts: [
        Graph.TextureIdentity: SceneShaderTextureFormat
    ] = [:],
    textureSlotsOverride: [Template.TextureSlot?]? = nil,
    effectContext: Template.EffectContext? = nil
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
            source: dynamicSource,
            tintValue: dynamicTintValue,
            authoredTintValue: authoredTintValue,
            scaleValue: dynamicScaleValue,
            authoredScaleValue: authoredScaleValue
        ),
        frameInputs: frameInputs(
            frameIndex: frameInputIndex,
            primaryButtonIsDown: primaryButtonIsDown,
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
                primaryReference: primaryReference,
                primaryGraphTextureRole: primaryGraphTextureRole,
                graphBindingsOverride: graphBindingsOverride,
                secondReference: secondReference,
                secondCandidates: secondCandidates,
                uniformDeclarations: uniformDeclarations,
                renderState: renderState,
                textureSlotsOverride: textureSlotsOverride,
                effectContext: effectContext
            ),
            renderSize: CGSize(width: 640, height: 360),
            modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: resolvedLayerModelMatrix,
            effectTextureProjectionMatrixInverse: effectProjectionInverse,
            implicitFramebufferIdentity: implicitFramebufferIdentity
        )
        let cache: SceneResolvedMaterialVariantCache
        if let variantCache {
            cache = variantCache
        } else {
            switch SceneResolvedMaterialVariantCache.launchValidated(
                template: input.template,
                maximumVariantCount: 16
            ) {
            case let .success(value): cache = value
            case let .failure(failure): return .failure(failure)
            }
            let assetStatePairs: [(
                SceneAssetTextureIdentity, SceneAssetTextureLaunchState
            )] = input.textureSnapshot.entries.compactMap { identity, status in
                    guard case let .asset(assetIdentity) = identity else { return nil }
                    _ = status
                    let content: SceneTextureContent = switch assetIdentity.purpose {
                    case .premultipliedColor:
                        .color(.resolved(.premultipliedAlpha))
                    case .straightAlbedo:
                        .color(.resolved(.straightAlpha))
                    case .preservedChannels, .mask, .noise, .flow, .phase,
                         .normal, .depth, .lookupTable:
                        .data
                    }
                    return (assetIdentity, .ready(content))
                }
            let assetStates = Dictionary(uniqueKeysWithValues: assetStatePairs)
            switch cache.precompileLaunchEnvelope(
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                outputStorage: outputStorage,
                graphTextureFormatFacts: graphTextureFormatFacts,
                assetStates: assetStates
            ) {
            case .success: break
            case .failure(.capacity):
                return .failure(.init(
                    phase: .preparation,
                    code: .shaderPreparationFailed,
                    details: ["variant-cache-capacity"]
                ))
            case let .failure(.material(failure)):
                return .failure(failure)
            }
        }
        return SceneResolvedMaterialProgramFinalizer.finalize(
            input,
            variantCache: cache,
            outputStorage: outputStorage
        )
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
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
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

private func reachabilityIdentityMismatchToken(_ device: MTLDevice) -> String {
    let shader = contract(revision: "reachability-identity-mismatch")
    let admitted = template(shader)
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 8
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: graphTexture()
    ), case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(device),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return "setup-failed" }
    let input = frame.finalizationInput(
        template: admitted,
        renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectTextureProjectionMatrixInverse: effectProjectionInverse,
        implicitFramebufferIdentity: framebufferTexture()
    )
    return failureToken(
        SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: cache)
    )
}

private func variantSelectionKeyMismatchTokens(
    _ device: MTLDevice
) -> [String: String] {
    let path = SceneVFSAssetPath("textures/variant-key-mismatch.tex")!
    let reference = Template.TextureReference.asset(path)
    let identity = SceneAssetTextureIdentity(
        path: path,
        purpose: .straightAlbedo
    )
    let shader = contract(
        revision: "variant-key-mismatch",
        samplerMetadata: #"{"material":"albedo","formatcombo":true}"#
    )
    let admitted = template(shader, primaryReference: reference)
    let runtimePublication = publication(
        device,
        requestIdentity: .asset(identity),
        purpose: .straightAlbedo,
        content: .color(.resolved(.straightAlpha)),
        authoredFormat: .dxt1
    )
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 8,
        assetFormatFacts: [identity.reportToken: SceneShaderTextureFormat.rgba8888.macroValue]
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: nil,
        assetStates: [identity: .ready(runtimePublication.candidate.content)]
    ), case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(
            device,
            kind: .missing,
            additionalEntries: [
                .asset(identity): .ready(.init(
                    publication: runtimePublication,
                    resourceGeneration: 1
                )),
            ]
        ),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return ["failure": "setup-failed", "details": "setup-failed"] }
    let input = frame.finalizationInput(
        template: admitted,
        renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectTextureProjectionMatrixInverse: effectProjectionInverse
    )
    let result = SceneResolvedMaterialProgramFinalizer.finalize(
        input,
        variantCache: cache
    )
    let details: String = switch result {
    case .success: "success"
    case let .failure(failure): failure.boundedDetails.joined(separator: ",")
    }
    return ["failure": failureToken(result), "details": details]
}

private func resolverInvariantTokens(_ device: MTLDevice) -> [String: String] {
    let shader = contract(revision: "resolver-invariant-codes")
    let admitted = template(shader)
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 8
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: nil
    ), case let .success(readyFrame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(device),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return ["setup": "failed"] }
    let readyInput = readyFrame.finalizationInput(
        template: admitted,
        renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectTextureProjectionMatrixInverse: effectProjectionInverse
    )
    guard case let .success(selection) = cache.resolveSelection(readyInput),
          case let .success(absentFrame) = SceneResolvedMaterialFrameSnapshot.validated(
              textureSnapshot: snapshot(device, kind: .absent),
              dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
              frameInputs: frameInputs(frameIndex: 1)
          ) else { return ["setup": "failed"] }
    let absentInput = absentFrame.finalizationInput(
        template: admitted,
        renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectTextureProjectionMatrixInverse: effectProjectionInverse
    )

    func token(_ body: () throws -> Void) -> String {
        do {
            try body()
            return "success"
        } catch let failure as SceneResolvedMaterialFailure {
            return "\(failure.phase.rawValue)/\(failure.code.rawValue)"
        } catch {
            return "untyped"
        }
    }

    return [
        "readiness": token {
            _ = try SceneResolvedMaterialTextureResolver.resolve(
                absentInput,
                variant: selection.variant,
                reachableSamplers: selection.reachableSamplers
            )
        },
        "variantKey": token {
            _ = try SceneResolvedMaterialTextureResolver.variantKey(
                readyInput,
                samplers: selection.variant.activeSamplers,
                reachableSamplers: selection.reachableSamplers,
                formatSlots: [8],
                allowPresenceIndependentDefaults: true
            )
        },
    ]
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

private func unreachableGraphCandidateToken(_ device: MTLDevice) -> String {
    let inactive = framebufferTexture()
    return failureToken(finalize(
        shader: contract(revision: "unreachable-graph-candidate"),
        device: device,
        secondReference: .graph(inactive),
        additionalEntries: [
            .graph(inactive): readyStatus(
                device,
                identity: .graph(inactive),
                purpose: .premultipliedColor,
                content: .color(.resolved(.premultipliedAlpha))
            ),
        ]
    ))
}

private func samplerPurposeToken(
    _ metadata: String?,
    vertexMetadata: String? = nil,
    assetReference: Bool = false,
    namedTargetReference: Bool = false,
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
        let reference: Template.TextureReference
        if namedTargetReference {
            reference = .provider(.namedLayerTarget(.init(
                providerLayerID: 42,
                variant: .primary
            )))
        } else if assetReference {
            reference = .asset(SceneVFSAssetPath(assetPath)!)
        } else {
            reference = .graph(graphTexture())
        }
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

private func selfGatedReadinessSeedTokens() -> [String: String] {
    let annotation =
        #"{"material":"mask","mode":"opacitymask","combo":"MASK","default":"util/white"}"#

    func token(
        _ label: String,
        conditionalSource: String,
        readiness: Bool
    ) -> String {
        let shader = contract(
            revision: "self-gated-readiness-\(label)",
            vertexSourceOverride: "void main() { gl_Position = vec4(0.0); }",
            fragmentSourceOverride: """
            \(conditionalSource)
            void main() {
                vec4 color = vec4(1.0);
            #if MASK == 1
                color *= texSample2D(g_Texture1, vec2(0.5));
            #endif
                gl_FragColor = color;
            }
            """
        )
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader,
            combos: [:],
            textureReadiness: [1: readiness]
        ) {
        case let .accepted(prepared):
            guard let samplers = try? SceneResolvedMaterialShaderSchema
                .activeSamplers(prepared) else { return "schema-invalid" }
            return "accepted:" + samplers.keys.sorted().map(String.init)
                .joined(separator: ",")
        case let .rejected(failure):
            return "\(failure.phase.rawValue)/\(failure.code.rawValue):"
                + failure.details.joined(separator: ",")
        case .notApplicable:
            return "not-applicable"
        }
    }

    let exact = """
    #if MASK == 1
    uniform sampler2D g_Texture1; // \(annotation)
    #endif
    """
    let nonUnitGuard = """
    #if MASK > 0
    uniform sampler2D g_Texture1; // \(annotation)
    #endif
    """
    let branched = """
    #if MASK == 1
    uniform sampler2D g_Texture1; // \(annotation)
    #else
    float inactiveBranchProbe = 0.0;
    #endif
    """
    let nested = """
    #if MASK == 1
    #if MASK == 1
    uniform sampler2D g_Texture1; // \(annotation)
    #endif
    #endif
    """
    return [
        "ready": token("ready", conditionalSource: exact, readiness: true),
        "unready": token("unready", conditionalSource: exact, readiness: false),
        "nonUnitGuard": token(
            "non-unit-guard",
            conditionalSource: nonUnitGuard,
            readiness: true
        ),
        "elseBranch": token(
            "else-branch",
            conditionalSource: branched,
            readiness: true
        ),
        "nestedGuard": token(
            "nested-guard",
            conditionalSource: nested,
            readiness: true
        ),
    ]
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

private func implicitFramebufferGraphCandidateProjectionToken() -> String {
    let shader = contract(revision: "implicit-graph-candidate")
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
                secondReference: .graph(graphTexture())
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

private func attenuationEligibilityTokens() -> [String: Bool] {
    let maskMetadata = #"{"mode":"opacitymask","combo":"MASK"}"#
    let maskPath = SceneVFSAssetPath("textures/eligibility-mask.tex")!
    let shader = contract(
        revision: "eligibility-mask",
        secondSamplerMetadata: maskMetadata,
        maskedAlpha: true,
        optionalMask: true,
        semanticProbes: false
    )
    let fixtureTemplate = template(
        shader,
        includePrimaryCandidate: false,
        secondReference: .asset(maskPath)
    )

    func prepared(
        _ readiness: [Int: Bool]
    ) -> (SceneShaderPreparedProgram, [Int: SceneResolvedMaterialShaderSchema.Sampler])? {
        guard case let .accepted(value) =
                SceneAuthoredShaderPreparation.prepareShaderStages(
                    contract: shader,
                    combos: [:],
                    textureReadiness: readiness
                ),
              let activeNames = SceneAuthoredShaderDeadBindingAnalyzer
                .activeSamplerNames(
                    vertexSource: value.vertex.source,
                    fragmentSource: value.fragment.source
                ),
              let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(
                  value,
                  activeNames: activeNames
              ) else { return nil }
        return (value, samplers)
    }

    func proven(
        _ preparedValue: SceneShaderPreparedProgram,
        _ samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        _ materialTemplate: Template = fixtureTemplate,
        inputIdentity: Graph.TextureIdentity = graphTexture()
    ) -> Bool {
        guard let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer.analyze(
            fragmentSource: preparedValue.fragment.source
        ) else { return false }
        return SceneResolvedMaterialAlphaAttenuationEligibility.validated(
            fact: fact,
            samplers: samplers,
            template: materialTemplate,
            implicitFramebufferIdentity: inputIdentity
        )
    }

    let maskOff = prepared([0: true, 1: false]).map {
        proven($0.0, $0.1)
    } ?? false
    let maskOn = prepared([0: true, 1: true]).map {
        proven($0.0, $0.1)
    } ?? false

    let wrongSamplerMode: Bool = {
        let wrongShader = contract(
            revision: "eligibility-wrong-mode",
            secondSamplerMetadata: #"{"mode":"rgbmask"}"#,
            maskedAlpha: true,
            semanticProbes: false
        )
        let wrongTemplate = template(
            wrongShader,
            includePrimaryCandidate: false,
            secondReference: .asset(maskPath)
        )
        guard case let .accepted(value) =
                SceneAuthoredShaderPreparation.prepareShaderStages(
                    contract: wrongShader,
                    combos: [:],
                    textureReadiness: [0: true, 1: true]
                ),
              let activeNames = SceneAuthoredShaderDeadBindingAnalyzer
                .activeSamplerNames(
                    vertexSource: value.vertex.source,
                    fragmentSource: value.fragment.source
                ),
              let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(
                  value,
                  activeNames: activeNames
              ),
              let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer.analyze(
                  fragmentSource: value.fragment.source
              ) else { return true }
        return !SceneResolvedMaterialAlphaAttenuationEligibility.validated(
            fact: fact,
            samplers: samplers,
            template: wrongTemplate,
            implicitFramebufferIdentity: graphTexture()
        )
    }()

    let auxiliaryGraphInputRejected: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let graphAuxiliaryTemplate = template(
            shader,
            includePrimaryCandidate: false,
            graphBindingsOverride: [.init(slot: 1, texture: .layerSource)],
            secondReference: .asset(maskPath)
        )
        return !proven(value.0, value.1, graphAuxiliaryTemplate)
    }()

    let extraActiveSamplerRejected: Bool = {
        guard let value = prepared([0: true, 1: true]),
              let auxiliary = value.1[1] else { return false }
        var samplers = value.1
        samplers[2] = .init(
            name: "g_Texture2",
            slot: 2,
            mode: auxiliary.mode,
            materialKey: auxiliary.materialKey,
            isHidden: auxiliary.isHidden,
            defaultTexture: auxiliary.defaultTexture,
            readinessCombo: auxiliary.readinessCombo
        )
        return !proven(value.0, samplers)
    }()

    let priorEffectOutputAccepted: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let prior = effectOutputTexture("fixture-prior")
        let priorTemplate = template(
            shader,
            includePrimaryCandidate: true,
            primaryReference: .graph(prior),
            effectInputGraphTextureRole: .effectOutput,
            primaryGraphTextureRole: .effectOutput,
            secondReference: .asset(maskPath)
        )
        return proven(
            value.0,
            value.1,
            priorTemplate,
            inputIdentity: prior
        )
    }()

    let internalFramebufferRejected: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let internalTemplate = template(
            shader,
            primaryReference: .graph(namedFramebufferTexture()),
            primaryGraphTextureRole: .framebuffer,
            secondReference: .asset(maskPath)
        )
        return !proven(value.0, value.1, internalTemplate)
    }()

    let differentEffectOutputRejected: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let prior = effectOutputTexture("fixture-prior")
        let different = effectOutputTexture("fixture-other")
        let differentTemplate = template(
            shader,
            primaryReference: .graph(different),
            effectInputGraphTextureRole: .effectOutput,
            primaryGraphTextureRole: .effectOutput,
            secondReference: .asset(maskPath)
        )
        return !proven(
            value.0,
            value.1,
            differentTemplate,
            inputIdentity: prior
        )
    }()

    let fallbackCandidateRejected: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let fallbackTemplate = template(
            shader,
            candidateCount: 2,
            secondReference: .asset(maskPath)
        )
        return !proven(value.0, value.1, fallbackTemplate)
    }()

    return [
        "maskOffPreparedVariant": maskOff,
        "maskOnPreparedVariant": maskOn,
        "wrongSamplerModeRejected": wrongSamplerMode,
        "auxiliaryGraphInputRejected": auxiliaryGraphInputRejected,
        "extraActiveSamplerRejected": extraActiveSamplerRejected,
        "priorEffectOutputAccepted": priorEffectOutputAccepted,
        "internalFramebufferRejected": internalFramebufferRejected,
        "differentEffectOutputRejected": differentEffectOutputRejected,
        "fallbackCandidateRejected": fallbackCandidateRejected,
    ]
}

private func colorBlendEligibilityTokens() -> [String: Bool] {
    let maskPath = SceneVFSAssetPath("textures/color-blend-mask.tex")!

    struct Prepared {
        let program: SceneShaderPreparedProgram
        let samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        let shader: SceneShaderContract
        let combos: [String: Int]
    }

    func prepared(
        blendMode: Int,
        mask: Bool,
        legacyMaskOverride: Bool = false
    ) -> Prepared? {
        let shader = contract(
            revision: "color-blend-\(blendMode)-\(mask)-\(legacyMaskOverride)",
            semanticProbes: false,
            colorBlend: true,
            legacyMaskOverride: legacyMaskOverride
        )
        // MASK is a readiness-derived combo; passing it explicitly would
        // conflict with the active sampler schema when the mask is absent.
        let combos = ["BLENDMODE": blendMode]
        let program: SceneShaderPreparedProgram
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader,
            combos: combos,
            textureReadiness: [0: true, 1: mask]
        ) {
        case let .accepted(value):
            program = value
        case let .rejected(failure):
            fatalError(
                "COLOR-BLEND-PREPARATION=\(blendMode)/\(mask)/"
                    + "\(failure.phase.rawValue)/\(failure.code.rawValue)/"
                    + "\(failure.details)"
            )
        case .notApplicable:
            fatalError("COLOR-BLEND-PREPARATION-NOT-APPLICABLE=\(blendMode)/\(mask)")
        }
        guard let activeNames = SceneAuthoredShaderDeadBindingAnalyzer
                .activeSamplerNames(
                    vertexSource: program.vertex.source,
                    fragmentSource: program.fragment.source
                ) else {
            fatalError("COLOR-BLEND-ACTIVE-NAMES=\(blendMode)/\(mask)")
        }
        let samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        do {
            samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(
                program,
                activeNames: activeNames
            )
        } catch {
            fatalError(
                "COLOR-BLEND-SAMPLERS=\(blendMode)/\(mask)/\(activeNames)/\(error)"
            )
        }
        return .init(
            program: program,
            samplers: samplers,
            shader: shader,
            combos: combos
        )
    }

    func materialTemplate(
        _ value: Prepared,
        input: Graph.TextureIdentity = graphTexture(),
        inputRole: Template.GraphTextureRole = .layerSource,
        auxiliaryReference: Template.TextureReference? = nil,
        auxiliaryGraphBinding: Bool = false,
        candidateCount: Int = 1
    ) -> Template {
        template(
            value.shader,
            candidateCount: candidateCount,
            includePrimaryCandidate: true,
            primaryReference: .graph(input),
            effectInputGraphTextureRole: inputRole,
            primaryGraphTextureRole: inputRole,
            graphBindingsOverride: auxiliaryGraphBinding
                ? [
                    .init(slot: 0, texture: inputRole),
                    .init(slot: 1, texture: inputRole),
                ]
                : [.init(slot: 0, texture: inputRole)],
            secondReference: auxiliaryReference,
            comboValues: value.combos
        )
    }

    func proven(
        _ value: Prepared,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]? = nil,
        templateValue: Template? = nil,
        input: Graph.TextureIdentity = graphTexture()
    ) -> Bool {
        SceneResolvedMaterialColorBlendEligibility.sourceSlot(
            fragmentSource: value.program.fragment.source,
            colorTransfer: SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: value.program.fragment.source
            ),
            samplers: samplers ?? value.samplers,
            template: templateValue ?? materialTemplate(
                value,
                auxiliaryReference: value.samplers[1].map { _ in .asset(maskPath) }
            ),
            implicitFramebufferIdentity: input
        ) == 0
    }

    let unmasked = prepared(blendMode: 30, mask: false)
    let stockMasked = prepared(blendMode: 12, mask: true)
    let legacyMasked = prepared(
        blendMode: 18,
        mask: true,
        legacyMaskOverride: true
    )
    let opaque = prepared(blendMode: 0, mask: false)

    let wrongSamplerModeRejected: Bool = {
        guard let value = stockMasked, let auxiliary = value.samplers[1] else {
            return false
        }
        var samplers = value.samplers
        samplers[1] = .init(
            name: auxiliary.name,
            slot: auxiliary.slot,
            mode: .regular,
            materialKey: auxiliary.materialKey,
            isHidden: auxiliary.isHidden,
            defaultTexture: auxiliary.defaultTexture,
            readinessCombo: auxiliary.readinessCombo
        )
        return !proven(value, samplers: samplers)
    }()

    let auxiliaryGraphInputRejected: Bool = {
        guard let value = stockMasked else { return false }
        return !proven(
            value,
            templateValue: materialTemplate(
                value,
                auxiliaryReference: .asset(maskPath),
                auxiliaryGraphBinding: true
            )
        )
    }()

    let extraActiveSamplerRejected: Bool = {
        guard let value = stockMasked, let auxiliary = value.samplers[1] else {
            return false
        }
        var samplers = value.samplers
        samplers[2] = .init(
            name: "g_Texture2",
            slot: 2,
            mode: auxiliary.mode,
            materialKey: auxiliary.materialKey,
            isHidden: auxiliary.isHidden,
            defaultTexture: auxiliary.defaultTexture,
            readinessCombo: auxiliary.readinessCombo
        )
        return !proven(value, samplers: samplers)
    }()

    let priorEffectOutputAccepted: Bool = {
        guard let value = stockMasked else { return false }
        let prior = effectOutputTexture("fixture-prior")
        return proven(
            value,
            templateValue: materialTemplate(
                value,
                input: prior,
                inputRole: .effectOutput,
                auxiliaryReference: .asset(maskPath)
            ),
            input: prior
        )
    }()

    let internalFramebufferRejected: Bool = {
        guard let value = stockMasked else { return false }
        let internalTarget = namedFramebufferTexture()
        return !proven(
            value,
            templateValue: materialTemplate(
                value,
                input: internalTarget,
                inputRole: .framebuffer,
                auxiliaryReference: .asset(maskPath)
            ),
            input: internalTarget
        )
    }()

    let differentEffectOutputRejected: Bool = {
        guard let value = stockMasked else { return false }
        let prior = effectOutputTexture("fixture-prior")
        let different = effectOutputTexture("fixture-other")
        return !proven(
            value,
            templateValue: materialTemplate(
                value,
                input: different,
                inputRole: .effectOutput,
                auxiliaryReference: .asset(maskPath)
            ),
            input: prior
        )
    }()

    let fallbackCandidateRejected: Bool = {
        guard let value = stockMasked else { return false }
        return !proven(
            value,
            templateValue: materialTemplate(
                value,
                auxiliaryReference: .asset(maskPath),
                candidateCount: 2
            )
        )
    }()

    return [
        "unmaskedSourceFact": unmasked.map {
            SceneAuthoredShaderGraphInputColorBlendAnalyzer.analyze(
                fragmentSource: $0.program.fragment.source
            ) != nil
        } ?? false,
        "unmaskedTransferProven": unmasked.map {
            if case .straightAlphaPreserving(textureSlot: 0) =
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: $0.program.fragment.source
                ) { return true }
            return false
        } ?? false,
        "unmaskedSamplerSetExact": unmasked.map {
            Set($0.samplers.keys) == [0]
        } ?? false,
        "modeZeroSourceFact": opaque.map {
            SceneAuthoredShaderGraphInputColorBlendAnalyzer.analyze(
                fragmentSource: $0.program.fragment.source
            ) != nil
        } ?? false,
        "modeZeroTransferProven": opaque.map {
            SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: $0.program.fragment.source
            ) == .opaque
        } ?? false,
        "modeZeroSamplerSetExact": opaque.map {
            Set($0.samplers.keys) == [0]
        } ?? false,
        "unmaskedPreparedVariant": unmasked.map { proven($0) } ?? false,
        "stockMaskMultiplyPreparedVariant": stockMasked.map { proven($0) } ?? false,
        "legacyMaskOverridePreparedVariant": legacyMasked.map { proven($0) } ?? false,
        "modeZeroOpaquePreparedVariant": opaque.map { proven($0) } ?? false,
        "wrongSamplerModeRejected": wrongSamplerModeRejected,
        "auxiliaryGraphInputRejected": auxiliaryGraphInputRejected,
        "extraActiveSamplerRejected": extraActiveSamplerRejected,
        "priorEffectOutputAccepted": priorEffectOutputAccepted,
        "internalFramebufferRejected": internalFramebufferRejected,
        "differentEffectOutputRejected": differentEffectOutputRejected,
        "fallbackCandidateRejected": fallbackCandidateRejected,
    ]
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

private func neutralTextureResolutionSources(
    resolutionSlot: Int,
    coordinateSlot: Int,
    varying: String
) -> (vertex: String, fragment: String) {
    (
        """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec4 \(varying);
        uniform vec4 g_Texture\(resolutionSlot)Resolution;
        void main() {
            \(varying).xy = a_TexCoord;
            \(varying).zw = vec2(
                ((\(varying).x * g_Texture\(resolutionSlot)Resolution.z)
                    / (g_Texture\(resolutionSlot)Resolution.x)),
                ((\(varying).y * g_Texture\(resolutionSlot)Resolution.w)
                    / (g_Texture\(resolutionSlot)Resolution.y))
            );
            gl_Position = vec4(a_Position, 1.0);
        }
        """,
        """
        varying vec4 \(varying);
        uniform sampler2D g_Texture0; // {"material":"framebuffer"}
        uniform sampler2D g_Texture\(coordinateSlot); // {"mode":"opacitymask"}
        void main() {
            vec4 current = texSample2D(g_Texture0, \(varying).xy);
            float mask = texSample2D(
                g_Texture\(coordinateSlot),
                (\(varying).zw)
            ).r;
            gl_FragColor = vec4(current.rgb, current.a * mask);
        }
        """
    )
}

private func neutralTextureResolutionResult(
    _ device: MTLDevice,
    resolutionSlot: Int = 1,
    coordinateSlot: Int = 2,
    varying: String = "coordinateCarrier",
    physicalSize: CGSize = CGSize(width: 2, height: 2),
    mappedSize: CGSize = CGSize(width: 2, height: 2),
    uvTransform: SceneTextureUVTransform = .identity,
    includeResolutionCandidate: Bool = false,
    vertexSourceOverride: String? = nil,
    fragmentSourceOverride: String? = nil,
    coordinateStatusOverride: SceneFrameTextureLookupStatus? = nil
) -> Result<Program, SceneResolvedMaterialFailure> {
    let maskPath = SceneVFSAssetPath(
        "textures/neutral-resolution-mask-\(coordinateSlot).tex"
    )!
    let maskIdentity = SceneFrameTextureIdentity.asset(.init(
        path: maskPath,
        purpose: .mask
    ))
    let sources = neutralTextureResolutionSources(
        resolutionSlot: resolutionSlot,
        coordinateSlot: coordinateSlot,
        varying: varying
    )
    let shader = contract(
        revision: "neutral-texture-resolution-\(resolutionSlot)-\(coordinateSlot)",
        uniformMetadata: nil,
        semanticProbes: false,
        vertexSourceOverride: vertexSourceOverride ?? sources.vertex,
        fragmentSourceOverride: fragmentSourceOverride ?? sources.fragment
    )
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[coordinateSlot] = .init(index: coordinateSlot, candidates: [
        .init(reference: .asset(maskPath), provenance: .material),
    ])
    let coordinateStatus = coordinateStatusOverride ?? readyStatus(
            device,
            identity: maskIdentity,
            purpose: .mask,
            content: .data,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: uvTransform
        )
    var entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [
        maskIdentity: coordinateStatus,
    ]
    if includeResolutionCandidate {
        let path = SceneVFSAssetPath(
            "textures/unexpected-resolution-slot-\(resolutionSlot).tex"
        )!
        let identity = SceneFrameTextureIdentity.asset(.init(
            path: path,
            purpose: .mask
        ))
        slots[resolutionSlot] = .init(index: resolutionSlot, candidates: [
            .init(reference: .asset(path), provenance: .material),
        ])
        entries[identity] = readyStatus(
            device,
            identity: identity,
            purpose: .mask,
            content: .data
        )
    }
    return finalize(
        shader: shader,
        device: device,
        includePrimaryCandidate: false,
        additionalEntries: entries,
        implicitFramebufferIdentity: graphTexture(),
        outputStorage: .preservedRGBAUnorm,
        textureSlotsOverride: slots
    )
}

private func neutralTextureResolutionToken(_ device: MTLDevice) -> String {
    let result = neutralTextureResolutionResult(device)
    guard case let .success(program) = result else {
        if case let .failure(failure) = result {
            return failureToken(result) + "/" + failure.boundedDetails.joined(separator: ",")
        }
        return failureToken(result)
    }
    guard program.textureSlots[1] == nil else { return "slot1-bound" }
    guard let maskSlot = program.textureSlots[2] else { return "slot2-missing" }
    guard
          maskSlot.resource.publication.candidate.axisAlignedMappedUVScale(
              expectedPurpose: .mask
          ) == SIMD2<Float>(1, 1)
    else { return "slot2-mapping" }
    guard let uniform = program.resolvedUniforms.first(where: {
              $0.field.name == "g_Texture1Resolution"
          }) else { return "uniform-missing" }
    guard case let .neutralMissingTextureResolution(fact) = uniform.source
    else { return "uniform-source" }
    guard
          fact.resolutionSlot == 1,
          fact.coordinateTextureSlot == 2,
          fact.varyingName == "coordinateCarrier",
          fact.sourceComponents == "xy",
          fact.targetComponents == "zw",
          uniform.encodedValue.count == 16,
          (0 ..< 4).allSatisfy({
              Harness.float(uniform.encodedValue, at: $0 * 4) == 1
          }),
          program.semanticIdentity.activeUniforms.contains(where: {
              guard $0.fieldName == "g_Texture1Resolution",
                    case .neutralMissingTextureResolution(fact) = $0.source
              else { return false }
              return fact.resolutionSlot == 1 && fact.coordinateTextureSlot == 2
          })
    else { return "uniform-fact-or-bytes" }
    return program.exactIdentity.textureSlots[2]?.physicalExtent == [2, 2]
        && program.exactIdentity.textureSlots[2]?.mappedExtent == [2, 2]
        && program.exactIdentity.uniformBytes == program.uniformBytes
        ? "success" : "exact-identity"
}

private func neutralTextureResolutionUnseenToken(_ device: MTLDevice) -> String {
    let result = neutralTextureResolutionResult(
        device,
        resolutionSlot: 3,
        coordinateSlot: 5,
        varying: "unseenCoordinates",
        physicalSize: CGSize(width: 64, height: 32),
        mappedSize: CGSize(width: 64, height: 32)
    )
    guard case let .success(program) = result,
          program.textureSlots[3] == nil,
          let slot = program.textureSlots[5],
          slot.resource.publication.candidate.axisAlignedMappedUVScale(
              expectedPurpose: .mask
          ) == SIMD2<Float>(1, 1),
          program.exactIdentity.textureSlots[5]?.physicalExtent == [64, 32],
          program.exactIdentity.textureSlots[5]?.mappedExtent == [64, 32],
          let uniform = program.resolvedUniforms.first(where: {
              $0.field.name == "g_Texture3Resolution"
          }),
          case let .neutralMissingTextureResolution(fact) = uniform.source,
          fact.resolutionSlot == 3,
          fact.coordinateTextureSlot == 5,
          fact.varyingName == "unseenCoordinates"
    else { return failureToken(result) }
    return "success"
}

private func neutralTextureResolutionAnalyzerCases() -> [String: Bool] {
    let sources = neutralTextureResolutionSources(
        resolutionSlot: 1,
        coordinateSlot: 2,
        varying: "coordinateCarrier"
    )
    func fact(_ vertex: String, _ fragment: String = "")
        -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
            vertexSource: vertex,
            fragmentSource: fragment.isEmpty ? sources.fragment : fragment,
            activeSamplerSlots: [0, 2]
        )
    }
    let resolution = "g_Texture1Resolution"
    let varying = "coordinateCarrier"
    let realVertex = """
    uniform mat4 g_ModelViewProjectionMatrix;
    uniform vec4 g_Texture1Resolution;
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec4 v_TexCoord;
    void main() {
        gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
        v_TexCoord.xy = a_TexCoord;
        v_TexCoord.zw = vec2(
            v_TexCoord.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
            v_TexCoord.y * g_Texture1Resolution.w / g_Texture1Resolution.y
        );
    }
    """
    let realFragment = """
    varying vec4 v_TexCoord;
    uniform sampler2D g_Texture0; // {"hidden":true}
    uniform sampler2D g_Texture2; // {"combo":"OPACITYMASK","mode":"opacitymask"}
    void main() {
        vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        float opactiyMask = 1.0 - texSample2D(g_Texture2, v_TexCoord.zw).r;
        gl_FragColor = albedo * opactiyMask;
    }
    """
    let realConditionalFragment = """
    varying vec4 v_TexCoord;
    uniform sampler2D g_Texture0; // {"hidden":true}
    uniform sampler2D g_Texture1; // {"mode":"opacitymask","combo":"MASK"}
    uniform sampler2D g_Texture2; // {"mode":"opacitymask","combo":"OPACITYMASK","default":"util/white"}
    void main() {
        vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        #if MASK
        float mask = texSample2D(g_Texture1, v_TexCoord.zw).r;
        #else
        float mask = 0.5;
        #endif
        #if OPACITYMASK
        float opactiyMask = 1.0 - texSample2D(g_Texture2, v_TexCoord.zw).r;
        #else
        float opactiyMask = 1.0;
        #endif
        gl_FragColor = albedo * mask * opactiyMask;
    }
    """
    let realPrepared: (
        current: Bool, missing: Bool, coordinate: Bool, count: Bool, analyzed: Bool
    ) = {
        let shader = contract(
            revision: "neutral-texture-resolution-real-prepared",
            uniformMetadata: nil,
            semanticProbes: false,
            vertexSourceOverride: realVertex,
            fragmentSourceOverride: realConditionalFragment
        )
        guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                inactiveComboProviders: ["MASK"],
                textureReadiness: [0: true, 1: false, 2: true]
            ) else { return (false, false, false, false, false) }
        let sources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: prepared.vertex.source,
            fragment: prepared.fragment.source
        )
        guard let activeNames = SceneAuthoredShaderDeadBindingAnalyzer
            .activeSamplerNames(
                vertexSource: sources.vertex,
                fragmentSource: sources.fragment
            ) else { return (false, false, false, false, false) }
        let activeSlots = Set(activeNames.compactMap { name -> Int? in
            guard name.hasPrefix("g_Texture") else { return nil }
            return Int(name.dropFirst("g_Texture".count))
        })
        let analyzed = SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
            vertexSource: sources.vertex,
            fragmentSource: sources.fragment,
            activeSamplerSlots: activeSlots
        ) != nil
        return (
            activeSlots.contains(0),
            !activeSlots.contains(1),
            activeSlots.contains(2),
            activeSlots.count == 2,
            analyzed
        )
    }()
    return [
        "exact": fact(sources.vertex) != nil,
        "realActiveCurrentAndMask": SceneAuthoredShaderNeutralTextureResolutionAnalyzer
            .analyze(
                vertexSource: realVertex,
                fragmentSource: realFragment,
                activeSamplerSlots: [0, 2]
            ) != nil,
        "realPreparedCurrentActive": realPrepared.current,
        "realPreparedResolutionInactive": realPrepared.missing,
        "realPreparedCoordinateActive": realPrepared.coordinate,
        "realPreparedActiveSamplerCount": realPrepared.count,
        "realPreparedCombo": realPrepared.analyzed,
        "activeResolutionSlot": SceneAuthoredShaderNeutralTextureResolutionAnalyzer
            .analyze(
                vertexSource: sources.vertex,
                fragmentSource: sources.fragment,
                activeSamplerSlots: [0, 1, 2]
            ) == nil,
        "glPosition": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).zw = vec2",
            with: "gl_Position.zw = vec2"
        )) == nil,
        "wrongComponent": fact(sources.vertex.replacingOccurrences(
            of: "\(resolution).z",
            with: "\(resolution).y"
        )) == nil,
        "functionUse": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).x * \(resolution).z",
            with: "abs(\(varying).x) * \(resolution).z"
        )) == nil,
        "array": fact(sources.vertex.replacingOccurrences(
            of: "uniform vec4 \(resolution);",
            with: "uniform vec4 \(resolution)[1];"
        )) == nil,
        "transform": fact(sources.vertex.replacingOccurrences(
            of: "/ (\(resolution).x))",
            with: "/ (\(resolution).x) + 0.25)"
        )) == nil,
        "singleSided": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).y * \(resolution).w",
            with: "\(varying).y"
        )) == nil,
        "crossComponent": fact(sources.vertex.replacingOccurrences(
            of: "\(resolution).w",
            with: "\(resolution).z"
        )) == nil,
        "swappedSource": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).x * \(resolution).z",
            with: "\(varying).y * \(resolution).z"
        )) == nil,
        "extraResolutionUse": fact(sources.vertex.replacingOccurrences(
            of: "gl_Position =",
            with: "float texelOrMip = \(resolution).x; gl_Position ="
        )) == nil,
        "multipleSource": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).xy = a_TexCoord;",
            with: "\(varying).xy = a_TexCoord; \(varying).xy = a_TexCoord;"
        )) == nil,
        "multipleConsumer": fact(
            sources.vertex,
            sources.fragment.replacingOccurrences(
                of: "gl_FragColor =",
                with: "float duplicate = texSample2D(g_Texture2, \(varying).zw).r; gl_FragColor ="
            )
        ) == nil,
        "targetLiveUse": fact(
            sources.vertex,
            sources.fragment.replacingOccurrences(
                of: "gl_FragColor =",
                with: "float live = \(varying).z; gl_FragColor ="
            )
        ) == nil,
        "wrongUniformType": fact(sources.vertex.replacingOccurrences(
            of: "uniform vec4 \(resolution);",
            with: "uniform vec3 \(resolution);"
        )) == nil,
        "wrongUniformName": fact(sources.vertex.replacingOccurrences(
            of: resolution,
            with: "u_MissingResolution"
        )) == nil,
        "missingAssignment": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).zw = vec2",
            with: "vec2 discarded = vec2"
        )) == nil,
    ]
}

private func neutralTextureResolutionFinalizerFailures(
    _ device: MTLDevice
) -> [String: String] {
    let sources = neutralTextureResolutionSources(
        resolutionSlot: 1,
        coordinateSlot: 2,
        varying: "coordinateCarrier"
    )
    let nonIdentityMapped = SceneTextureUVTransform(
        origin: .zero,
        xAxis: SIMD2(0.5, 0),
        yAxis: SIMD2(0, 1)
    )
    let nonIdentityUV = SceneTextureUVTransform(
        origin: SIMD2(0.1, 0),
        xAxis: SIMD2(0.8, 0),
        yAxis: SIMD2(0, 1)
    )
    let maskPath = SceneVFSAssetPath("textures/neutral-resolution-mask-2.tex")!
    let maskIdentity = SceneFrameTextureIdentity.asset(.init(
        path: maskPath,
        purpose: .mask
    ))
    let wrongPurpose = SceneFrameTextureLookupStatus.ready(.init(
        publication: publication(
            device,
            requestIdentity: maskIdentity,
            purpose: .straightAlbedo,
            content: .color(.resolved(.straightAlpha)),
            candidateGeneration: 7,
            contentGeneration: 7
        ),
        resourceGeneration: 7
    ))
    return [
        "resolutionCandidate": failureToken(neutralTextureResolutionResult(
            device,
            includeResolutionCandidate: true
        )),
        "mappedNotIdentity": failureToken(neutralTextureResolutionResult(
            device,
            physicalSize: CGSize(width: 64, height: 32),
            mappedSize: CGSize(width: 32, height: 32),
            uvTransform: nonIdentityMapped
        )),
        "uvNotIdentity": failureToken(neutralTextureResolutionResult(
            device,
            physicalSize: CGSize(width: 64, height: 32),
            mappedSize: CGSize(width: 64, height: 32),
            uvTransform: nonIdentityUV
        )),
        "coordinatePending": failureToken(neutralTextureResolutionResult(
            device,
            coordinateStatusOverride: .pending
        )),
        "coordinateWrongPurpose": failureToken(neutralTextureResolutionResult(
            device,
            coordinateStatusOverride: wrongPurpose
        )),
        "wrongComponent": failureToken(neutralTextureResolutionResult(
            device,
            vertexSourceOverride: sources.vertex.replacingOccurrences(
                of: "g_Texture1Resolution.z",
                with: "g_Texture1Resolution.y"
            )
        )),
        "targetLiveUse": failureToken(neutralTextureResolutionResult(
            device,
            fragmentSourceOverride: sources.fragment.replacingOccurrences(
                of: "gl_FragColor =",
                with: "float live = coordinateCarrier.z; gl_FragColor ="
            )
        )),
        "resolutionSamplerActive": failureToken(neutralTextureResolutionResult(
            device,
            fragmentSourceOverride: sources.fragment.replacingOccurrences(
                of: "void main() {",
                with: "uniform sampler2D g_Texture1; // {\"mode\":\"opacitymask\",\"default\":\"textures/default.tex\"}\nvoid main() {"
            )
        )),
    ]
}

private func dormantGraphInputFactTokens(
    _ device: MTLDevice
) -> [String: String] {
    func shader(_ slot: Int, revision: String) -> SceneShaderContract {
        contract(
            revision: revision,
            uniformMetadata: nil,
            semanticProbes: false,
            fragmentSourceOverride: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture\(slot); // {"material":"Arbitrary \(revision)","label":"Random label \(slot)","hidden":true}
            void main() {
                gl_FragColor = texSample2D(
                    g_Texture\(slot),
                    v_TexCoord.xy
                );
            }
            """
        )
    }
    let effect = Graph.EffectKey(
        layerID: fixtureLayerID,
        effectIndex: 0,
        descriptorID: "fixture-dormant-arbitrary"
    )
    let context = Template.EffectContext(key: effect, input: graphTexture())
    func result(_ slot: Int) -> Result<Program, SceneResolvedMaterialFailure> {
        finalize(
            shader: shader(slot, revision: "dormant-slot-\(slot)"),
            device: device,
            slot: slot,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture(),
            effectContext: context
        )
    }
    func token(
        _ result: Result<Program, SceneResolvedMaterialFailure>,
        slot expectedSlot: Int
    ) -> String {
        guard case let .success(program) = result else {
            return failureToken(result)
        }
        guard
              let slot = program.textureSlots[expectedSlot],
              case let .graph(reference) = slot.reference,
              let fact = slot.graphInputSourceFact,
              fact.slot == expectedSlot,
              fact.inputIdentity == graphTexture(),
              fact.provenance == .dormantUnresolvedMaterialAlias,
              slot.diagnosticSelectionProvenance
                == .dormantUnresolvedMaterialGraphInput,
              program.semanticIdentity.textureSlots[expectedSlot]?
                .graphInputSource == fact,
              program.exactIdentity.textureSlots[expectedSlot]?
                .graphInputSource == fact else { return "fact-missing" }
        return reference == graphTexture()
            && program.frontendProgram.textureBindings.map(\.slot)
                == [expectedSlot]
            ? "proven" : "identity-mismatch"
    }
    return [
        "arbitraryHiddenKeySlot0": token(result(0), slot: 0),
        "unseenArbitraryHiddenKeySlot3": token(result(3), slot: 3),
    ]
}

private func admittedEffectIngressTokens(
    _ device: MTLDevice
) -> [String: String] {
    func identity(
        kind: Graph.TextureKind,
        layerID: Int = fixtureLayerID,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }
    let owner = Graph.EffectKey(
        layerID: fixtureLayerID,
        effectIndex: 7,
        descriptorID: "fixture-active-after-disabled"
    )
    func token(
        _ input: Graph.TextureIdentity,
        contextInput: Graph.TextureIdentity? = nil,
        revision: String
    ) -> String {
        let resolvedContextInput = contextInput ?? input
        let snapshotIdentity = SceneFrameTextureIdentity.graph(input)
        return failureToken(finalize(
            shader: contract(
                revision: revision,
                samplerMetadata: #"{"material":"framebuffer","hidden":true}"#,
                uniformMetadata: nil,
                semanticProbes: false
            ),
            device: device,
            includePrimaryCandidate: false,
            additionalEntries: [
                snapshotIdentity: .ready(.init(
                    publication: publication(
                        device,
                        requestIdentity: snapshotIdentity,
                        candidateIdentity: .provider(.graph(
                            allocationGeneration: 9,
                            physicalToken: "fixture-admitted-ingress"
                        ))
                    ),
                    resourceGeneration: 9
                )),
            ],
            implicitFramebufferIdentity: input,
            effectContext: .init(key: owner, input: resolvedContextInput)
        ))
    }
    let prior = Graph.EffectKey(
        layerID: fixtureLayerID,
        effectIndex: 2,
        descriptorID: "fixture-prior-active"
    )
    return [
        "layerSourceAfterDisabledRawEffects": token(
            identity(kind: .layerSource),
            revision: "active-ingress-layer-source-gap"
        ),
        "priorActiveOutputWithRawOrdinalGap": token(
            identity(kind: .effectOutput, effect: prior),
            revision: "active-ingress-effect-output-gap"
        ),
        "contextIdentityMismatch": token(
            identity(kind: .effectOutput, effect: prior),
            contextInput: identity(kind: .layerSource),
            revision: "active-ingress-context-mismatch"
        ),
        "wrongLayer": token(
            identity(kind: .layerSource, layerID: fixtureLayerID + 1),
            revision: "active-ingress-wrong-layer"
        ),
        "namedLayerSource": token(
            identity(kind: .layerSource, name: "forged"),
            revision: "active-ingress-named-layer-source"
        ),
        "selfOutput": token(
            identity(kind: .effectOutput, effect: owner),
            revision: "active-ingress-self-output"
        ),
    ]
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
        let resolverInvariants = resolverInvariantTokens(device)
        let variantSelectionKeyMismatch = variantSelectionKeyMismatchTokens(device)
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
        let pointerStateProgram = finalize(
            shader: contract(
                revision: "pointer-state-host-uniform",
                pointerState: true
            ),
            device: device,
            primaryButtonIsDown: true
        )
        let pointerStateEncoded: Bool = {
            guard case let .success(program) = pointerStateProgram,
                  let field = program.frontendProgram.uniformLayout.fields.first(
                      where: { $0.name == "g_PointerState" }
                  ) else { return false }
            return field.type == .float4
                && float(program.uniformBytes, at: field.offset) == 0
                && float(program.uniformBytes, at: field.offset + 4) == 0
                && float(program.uniformBytes, at: field.offset + 8) == 1
                && float(program.uniformBytes, at: field.offset + 12) == 0
        }()
        let admittedEffectIngress = admittedEffectIngressTokens(device)

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
        let scalarRedConsumerProgram = finalize(
            shader: contract(
                revision: "scalar-red-consumer",
                directRedInput: true
            ),
            device: device,
            primaryReference: .graph(framebufferTexture()),
            primaryGraphTextureRole: .framebuffer,
            additionalEntries: [
                .graph(framebufferTexture()): .ready(.init(
                    publication: publication(
                        device,
                        requestIdentity: .graph(framebufferTexture()),
                        purpose: .preservedChannels,
                        content: .scalarRedUnorm,
                        sampling: .linearRepeat,
                        pixelFormat: .r8Unorm,
                        candidateIdentity: .provider(.graph(
                            allocationGeneration: 1,
                            physicalToken: "fixture-scalar-target"
                        ))
                    ),
                    resourceGeneration: 1
                )),
            ],
            outputStorage: .scalarRedUnorm,
            graphTextureFormatFacts: [framebufferTexture(): .r8]
        )
        let scalarRedForgedTEXFormat = finalize(
            shader: contract(
                revision: "scalar-red-forged-tex-format",
                directRedInput: true
            ),
            device: device,
            primaryReference: .graph(framebufferTexture()),
            primaryGraphTextureRole: .framebuffer,
            additionalEntries: [
                .graph(framebufferTexture()): .ready(.init(
                    publication: publication(
                        device,
                        requestIdentity: .graph(framebufferTexture()),
                        purpose: .preservedChannels,
                        content: .scalarRedUnorm,
                        sampling: .linearRepeat,
                        pixelFormat: .r8Unorm,
                        authoredFormat: .r8,
                        candidateIdentity: .provider(.graph(
                            allocationGeneration: 1,
                            physicalToken: "fixture-scalar-target-forged-tex-format"
                        ))
                    ),
                    resourceGeneration: 1
                )),
            ],
            outputStorage: .scalarRedUnorm,
            graphTextureFormatFacts: [framebufferTexture(): .r8]
        )
        let scalarRedWrongFormat = finalize(
            shader: contract(
                revision: "scalar-red-wrong-format",
                directRedInput: true
            ),
            device: device,
            primaryReference: .graph(framebufferTexture()),
            primaryGraphTextureRole: .framebuffer,
            additionalEntries: [
                .graph(framebufferTexture()): .ready(.init(
                    publication: publication(
                        device,
                        requestIdentity: .graph(framebufferTexture()),
                        purpose: .preservedChannels,
                        content: .scalarRedUnorm,
                        sampling: .linearRepeat,
                        pixelFormat: .r8Unorm,
                        authoredFormat: .rgba8888,
                        candidateIdentity: .provider(.graph(
                            allocationGeneration: 1,
                            physicalToken: "fixture-scalar-target-wrong-format"
                        ))
                    ),
                    resourceGeneration: 1
                )),
            ],
            outputStorage: .scalarRedUnorm,
            graphTextureFormatFacts: [framebufferTexture(): .r8]
        )
        let scalarRedConsumerIdentity: Bool = {
            guard case let .success(program) = scalarRedConsumerProgram,
                  let slot = program.textureSlots[0],
                  slot.expectedPurpose == .preservedChannels,
                  slot.resource.publication.candidate.content == .scalarRedUnorm,
                  slot.resource.publication.candidate.authoredFormat == nil,
                  slot.resource.publication.candidate.sampling == .linearRepeat,
                  program.frontendProgram.textureBindings.first?.channelUse == .redOnly,
                  case .scalarRedUnorm = program.outputContract else {
                return false
            }
            return true
        }()
        let rgbaDataConsumerProgram = finalize(
            shader: contract(revision: "rgba-data-consumer"),
            device: device,
            primaryReference: .graph(framebufferTexture()),
            primaryGraphTextureRole: .framebuffer,
            additionalEntries: [
                .graph(framebufferTexture()): .ready(.init(
                    publication: publication(
                        device,
                        requestIdentity: .graph(framebufferTexture()),
                        purpose: .preservedChannels,
                        content: .data,
                        sampling: .linearRepeat,
                        pixelFormat: .rgba8Unorm,
                        candidateIdentity: .provider(.graph(
                            allocationGeneration: 1,
                            physicalToken: "fixture-rgba-data-target"
                        ))
                    ),
                    resourceGeneration: 1
                )),
            ],
            outputStorage: .preservedRGBAUnorm
        )
        let rgbaDataConsumerIdentity: Bool = {
            guard case let .success(program) = rgbaDataConsumerProgram,
                  let slot = program.textureSlots[0],
                  slot.expectedPurpose == .preservedChannels,
                  slot.resource.publication.candidate.content == .data,
                  slot.resource.publication.candidate.authoredFormat == nil,
                  slot.resource.publication.candidate.sampling == .linearRepeat,
                  case .preservedRGBAUnorm = program.outputContract else {
                return false
            }
            return true
        }()
        let graphRoleIdentityFailure = finalize(
            shader: contract(
                revision: "graph-role-identity-invariant",
                samplerMetadata: #"{"material":"framebuffer"}"#
            ),
            device: device,
            includePrimaryCandidate: false,
            graphBindingsOverride: [.init(slot: 0, texture: .effectOutput)],
            implicitFramebufferIdentity: graphTexture()
        )
        let programAssemblyIdentityFailure = finalize(
            shader: contract(revision: "program-assembly-identity-invariant"),
            device: device,
            primaryGraphTextureRole: .effectOutput
        )
        let implicitFramebufferTyped: Bool = {
            guard case let .success(program) = implicitFramebufferProgram,
                  let slot = program.textureSlots[0],
                  case let .graph(identity) = slot.reference else { return false }
            return identity == graphTexture()
                && slot.diagnosticSelectionProvenance
                    == .implicitFramebuffer
                && slot.graphInputSourceFact?.provenance
                    == .explicitMaterialAlias
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
                && slot.diagnosticSelectionProvenance
                    == .implicitFramebuffer
                && slot.graphInputSourceFact?.provenance
                    == .explicitMaterialAlias
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
                && source.diagnosticSelectionProvenance
                    == .implicitFramebuffer
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
            guard case let .color(contract) =
                    program.semanticIdentity.outputContract else { return false }
            return float(program.uniformBytes, at: field.offset) == 0.25
                && contract.fragmentOutput == .premultipliedAlpha
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
        let timelineVectorA = finalize(
            shader: contract(revision: "timeline-vector-shared"),
            device: device,
            uniformDeclarations: [dynamicDeclaration([.timeline])],
            textureFrameIndex: 5,
            dynamicFrameIndex: 5,
            frameInputIndex: 5,
            dynamicSource: .timeline,
            dynamicTintValue: .vector3(0.1, 0.2, 0.3)
        )
        let timelineVectorB = finalize(
            shader: contract(revision: "timeline-vector-shared"),
            device: device,
            uniformDeclarations: [dynamicDeclaration([.timeline])],
            textureFrameIndex: 6,
            dynamicFrameIndex: 6,
            frameInputIndex: 6,
            dynamicSource: .timeline,
            dynamicTintValue: .vector3(0.7, 0.6, 0.5)
        )
        let timelineVectorTypeMismatch = finalize(
            shader: contract(revision: "timeline-vector-type-mismatch"),
            device: device,
            uniformDeclarations: [dynamicDeclaration([.timeline])],
            dynamicSource: .timeline,
            dynamicTintValue: .vector2(0.1, 0.2),
            authoredTintValue: .vector2(1, 0.5)
        )
        let timelineVectorUpdatesProgramWithoutTopologyChange: Bool = {
            guard case let .success(first) = timelineVectorA,
                  case let .success(second) = timelineVectorB,
                  let field = first.frontendProgram.uniformLayout.fields.first(
                      where: { $0.name == "u_Tint" }
                  ) else { return false }
            let range = field.offset ..< field.offset + field.type.byteSize
            return first.semanticIdentity == second.semanticIdentity
                && first.preparedShader.cacheKey == second.preparedShader.cacheKey
                && first.uniformBytes.subdata(in: range)
                    != second.uniformBytes.subdata(in: range)
        }()
        let scalarSplatShader = contract(
            revision: "user-property-scalar-float2-splat",
            semanticProbes: false,
            scalarSplatScale: true
        )
        let scalarSplatProgram = finalize(
            shader: scalarSplatShader,
            device: device,
            uniformDeclarations: [dynamicScaleDeclaration()],
            dynamicSource: .userProperty,
            dynamicScaleValue: .scalar(0.6)
        )
        let scalarSplatAuthoredProgram = finalize(
            shader: scalarSplatShader,
            device: device,
            uniformDeclarations: [dynamicScaleDeclaration()],
            dynamicSource: nil,
            authoredScaleValue: .scalar(0.6)
        )
        let userPropertyScalarFloat2SplatEncoded: Bool = {
            guard case let .success(program) = scalarSplatProgram,
                  case let .success(authored) = scalarSplatAuthoredProgram,
                  let field = program.frontendProgram.uniformLayout.fields.first(
                      where: { $0.name == "u_Scale" }
                  ) else { return false }
            return field.type == .float2
                && float(program.uniformBytes, at: field.offset) == 0.6
                && float(program.uniformBytes, at: field.offset + 4) == 0.6
                && float(authored.uniformBytes, at: field.offset) == 0.6
                && float(authored.uniformBytes, at: field.offset + 4) == 0.6
        }()
        let unequalScalarSplatFallback = finalize(
            shader: contract(
                revision: "user-property-scalar-float2-unequal",
                semanticProbes: false,
                scalarSplatScale: true
            ),
            device: device,
            uniformDeclarations: [dynamicScaleDeclaration(fallback: [1, 0.5])],
            dynamicSource: .userProperty
        )
        let nonUserScalarSplatContributor = finalize(
            shader: contract(
                revision: "timeline-scalar-float2-rejected",
                semanticProbes: false,
                scalarSplatScale: true
            ),
            device: device,
            uniformDeclarations: [dynamicScaleDeclaration(
                contributors: [.timeline]
            )],
            dynamicSource: .timeline
        )
        let extraKeyScalarSplat = finalize(
            shader: contract(
                revision: "user-property-scalar-float2-extra-key",
                semanticProbes: false,
                scalarSplatScale: true
            ),
            device: device,
            uniformDeclarations: [dynamicScaleDeclaration(
                bindingKeys: ["extra", "user", "value"]
            )],
            dynamicSource: .userProperty
        )
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
            guard case let .color(contract) =
                    program.semanticIdentity.outputContract else { return false }
            return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
                && contract.fragmentOutput == .premultipliedAlpha
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
        guard case let .success(activeDefaultMaskCache) =
                SceneResolvedMaterialVariantCache.launchValidated(
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
            guard case let .color(contract) =
                    program.semanticIdentity.outputContract else { return false }
            return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
                && contract.fragmentOutput == .premultipliedAlpha
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
        let modelViewProjectionInverseField =
            programA.frontendProgram.uniformLayout.fields.first {
                $0.name == "g_ModelViewProjectionMatrixInverse"
            }!
        let modelViewProjectionInverseEncoded = [0, 5, 10, 15].allSatisfy {
            float(
                programA.uniformBytes,
                at: modelViewProjectionInverseField.offset + $0 * 4
            ) == 1
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
            "exactWhitespaceUniformBindingKey": failureToken(finalize(
                shader: contract(
                    revision: "exact-whitespace-uniform-binding-key",
                    uniformMetadata:
                        #"{"material":"Anti-alias blurring ","default":"1 0.5 0.25"}"#
                ),
                device: device,
                uniformDeclarations: [
                    staticDeclaration(
                        "Anti-alias blurring ",
                        components: [0.2, 0.3, 0.4]
                    ),
                ]
            )),
            "malformedStaticDeclaration": failureToken(finalize(
                shader: contract(revision: "malformed-static-declaration"),
                device: device,
                uniformDeclarations: [
                    staticDeclaration("Tint", components: [1]),
                ]
            )),
            "uniformDeclarationConflict": failureToken(finalize(
                shader: contract(revision: "uniform-declaration-conflict"),
                device: device,
                uniformDeclarations: [
                    staticDeclaration("Tint", components: [1, 0, 0]),
                    staticDeclaration("u_Tint", components: [0, 1, 0]),
                ]
            )),
            "hostUniformDeclarationConflict": failureToken(finalize(
                shader: contract(revision: "host-uniform-declaration-conflict"),
                device: device,
                uniformDeclarations: [
                    staticDeclaration("g_Time", components: [99]),
                ]
            )),
            "hostUniformBindingInvalid": failureToken(finalize(
                shader: contract(revision: "host-uniform-binding-invalid"),
                device: device,
                resolvedLayerModelMatrix: simd_float4x4(
                    diagonal: SIMD4(.nan, 1, 1, 1)
                )
            )),
            "knownTimelineScriptControl": failureToken(finalize(
                shader: contract(revision: "timeline-script-control"),
                device: device,
                uniformDeclarations: [dynamicDeclaration(
                    [.timeline],
                    attachments: [.mediaThumbnailAnimationRestart]
                )],
                dynamicSource: .timeline
            )),
            "unknownTimelineScriptAttachment": failureToken(finalize(
                shader: contract(revision: "unknown-timeline-script-attachment"),
                device: device,
                uniformDeclarations: [dynamicDeclaration(
                    [.timeline],
                    attachments: [.unproven]
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
            "runtimeLoopNegativeExact": failureToken(finalize(
                shader: contract(revision: "runtime-loop-negative", runtimeLoop: true),
                device: device,
                uniformDeclarations: [staticDeclaration("Fractals", components: [-1])]
            )),
            "runtimeLoopNonIntegralExact": failureToken(finalize(
                shader: contract(revision: "runtime-loop-non-integral", runtimeLoop: true),
                device: device,
                uniformDeclarations: [staticDeclaration("Fractals", components: [5.5])]
            )),
            "runtimeLoopNonFiniteExact": failureToken(finalize(
                shader: contract(revision: "runtime-loop-non-finite", runtimeLoop: true),
                device: device,
                uniformDeclarations: [staticDeclaration("Fractals", components: [.nan])]
            )),
            "runtimeLoopMultipleProducer": failureToken(finalize(
                shader: contract(revision: "runtime-loop-multiple", runtimeLoop: true),
                device: device,
                uniformDeclarations: [
                    staticDeclaration("Fractals", components: [5]),
                    staticDeclaration("u_fractals", components: [5]),
                ]
            )),
            "runtimeLoopCrossTemplateCache":
                crossTemplateRuntimeLoopCacheToken(device),
            "variantSelectionReachabilityIdentity":
                reachabilityIdentityMismatchToken(device),
            "variantSelectionKey":
                variantSelectionKeyMismatch["failure"] ?? "missing",
            "variantSelectionKeyDetails":
                variantSelectionKeyMismatch["details"] ?? "missing",
            "terminalGraphOverrideUnavailable":
                resolverInvariants["readiness"] ?? "missing",
            "textureVariantKeyIdentityInvariant":
                resolverInvariants["variantKey"] ?? "missing",
            "multipleCandidates": failureToken(finalize(
                shader: contract(revision: "multiple-candidates"),
                device: device,
                candidateCount: 2
            )),
            "unreachableGraphCandidate": unreachableGraphCandidateToken(device),
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
            "arithmeticScalarOutput": failureToken(finalize(
                shader: contract(revision: "arithmetic-scalar-output", arithmetic: true),
                device: device,
                outputStorage: .scalarRedUnorm
            )),
            "scalarRedConsumer": failureToken(scalarRedConsumerProgram),
            "rgbaDataConsumer": failureToken(rgbaDataConsumerProgram),
            "scalarRedForgedTEXFormat": failureToken(scalarRedForgedTEXFormat),
            "scalarRedWrongFormat": failureToken(scalarRedWrongFormat),
            "graphRoleIdentityInvariant": failureToken(graphRoleIdentityFailure),
            "programAssemblyIdentityInvariant": failureToken(
                programAssemblyIdentityFailure
            ),
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
            "timelineVectorTypeMismatch": failureToken(timelineVectorTypeMismatch),
            "unequalScalarSplatFallback": failureToken(
                unequalScalarSplatFallback
            ),
            "nonUserScalarSplatContributor": failureToken(
                nonUserScalarSplatContributor
            ),
            "extraKeyScalarSplat": failureToken(extraKeyScalarSplat),
        ]

        let attenuationEligibility = attenuationEligibilityTokens()
        let colorBlendEligibility = colorBlendEligibilityTokens()
        let neutralTextureResolution = neutralTextureResolutionToken(device)
        let neutralTextureResolutionUnseen =
            neutralTextureResolutionUnseenToken(device)
        let neutralTextureResolutionAnalyzer =
            neutralTextureResolutionAnalyzerCases()
        let neutralTextureResolutionFailures =
            neutralTextureResolutionFinalizerFailures(device)
        let dormantGraphInputFacts = dormantGraphInputFactTokens(device)
        let result: [String: Any] = [
            "metalAvailable": true,
            "attenuationEligibilityCases": attenuationEligibility,
            "colorBlendEligibilityCases": colorBlendEligibility,
            "activeDefaultCache": [
                "launchMasks": activeDefaultLaunchMasks?.map(Int.init) ?? [-1],
                "failure": failureToken(activeDefaultMaskProgram),
                "cached": activeDefaultMaskCache.counters.cachedVariantCount,
                "prepared": activeDefaultMaskCache.counters.shaderPreparationCount,
                "frontend": activeDefaultMaskCache.counters.frontendCompilationCount,
                "capacity": activeDefaultMaskCache.counters.capacityRejectionCount,
            ],
            "positive": [
                "neutralTextureResolution": neutralTextureResolution == "success",
                "neutralTextureResolutionUnseen":
                    neutralTextureResolutionUnseen == "success",
                "neutralTextureResolutionAnalyzer":
                    neutralTextureResolutionAnalyzer.values.allSatisfy { $0 },
                "attenuationEligibility": attenuationEligibility.values.allSatisfy { $0 },
                "colorBlendEligibility": colorBlendEligibility.values.allSatisfy { $0 },
                "fixedEightSlots": programA.textureSlots.count == 8
                    && programA.textureSlots[0] != nil
                    && programA.textureSlots.dropFirst().allSatisfy { $0 == nil },
                "uniformLayoutCorrect": uniformLayoutCorrect,
                "modelViewProjectionInverseEncoded":
                    modelViewProjectionInverseEncoded,
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
                "timelineVectorUpdatesProgramWithoutTopologyChange":
                    timelineVectorUpdatesProgramWithoutTopologyChange,
                "userPropertyScalarFloat2SplatEncoded":
                    userPropertyScalarFloat2SplatEncoded,
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
                "pointerStatePrimaryButtonEncoded": pointerStateEncoded,
            ],
            "identity": [
                "semanticStable": programA.semanticIdentity == programB.semanticIdentity,
                "exactRevisionSensitive": programA.exactIdentity != programB.exactIdentity,
                "scalarFramebufferDirectRedConsumer": scalarRedConsumerIdentity,
                "rgbaFramebufferDataConsumer": rgbaDataConsumerIdentity,
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
                "registeredStockWaterRippleNormal": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "effects/waterripplenormal"
                ),
                "registeredStockWaterRippleNormalConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "effects/waterripplenormal"
                ),
                "neighboringWaterRippleNormalUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "effects/waterripplenormal_extra"
                ),
                "customWaterRippleNormalUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "custom/waterripplenormal"
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
                "registeredStockPerlinNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/perlin_256"
                ),
                "registeredStockVoronoiNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "pattern/voronoi"
                ),
                "registeredStockLocalVoronoiNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "pattern/voronoi_local"
                ),
                "registeredStockUniformNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/uniform_256"
                ),
                "registeredStockPerlinPurposeConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "util/perlin_256"
                ),
                "registeredStockVoronoiPurposeConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "pattern/voronoi"
                ),
                "neighboringCustomPerlinUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "custom/perlin_256"
                ),
                "neighboringPerlin512Unproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/perlin_512"
                ),
                "neighboringPerlinSuffixUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/perlin_256_extra"
                ),
                "neighboringVoronoiSuffixUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "pattern/voronoi_extra"
                ),
                "neighboringLocalVoronoiSuffixUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "pattern/voronoi_local_extra"
                ),
                "neighboringUniformSuffixUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/uniform_256_extra"
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
                "rgbMaskNamedTarget": samplerPurposeToken(
                    #"{"mode":"rgbmask"}"#,
                    namedTargetReference: true
                ),
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
                "unprovenAuthoredCandidate":
                    implicitFramebufferCandidateProjectionToken(
                        assetPath: "custom/unproven-auxiliary"
                    ),
                "graphAuthoredCandidate":
                    implicitFramebufferGraphCandidateProjectionToken(),
                "unknownDefault": implicitFramebufferProjectionToken(
                    defaultAssetPath: "textures/unknown-default.tex"
                ),
            ],
            "shaderPreparationBoundary": [
                "missingSourceGraph": missingSourceGraphDiagnostic(),
                "selfGatedReadiness": selfGatedReadinessSeedTokens(),
            ],
            "neutralTextureResolution": neutralTextureResolution,
            "neutralTextureResolutionUnseen": neutralTextureResolutionUnseen,
            "neutralTextureResolutionAnalyzer": neutralTextureResolutionAnalyzer,
            "neutralTextureResolutionFailures": neutralTextureResolutionFailures,
            "dormantGraphInputFacts": dormantGraphInputFacts,
            "admittedEffectIngress": admittedEffectIngress,
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
        # This standalone harness owns Finalizer/resource provenance and has no
        # signed compiler bundle. Exercise the explicit bounded rollback; the
        # generic owner and its failure boundary have separate product gates.
        environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
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

    def test_neutral_missing_texture_resolution_is_structural_and_fail_closed(
        self,
    ) -> None:
        self.assertEqual(
            [
                name
                for name, passed in self.result[
                    "neutralTextureResolutionAnalyzer"
                ].items()
                if not passed
            ],
            [],
            self.result["neutralTextureResolutionAnalyzer"],
        )
        self.assertEqual(
            self.result["neutralTextureResolutionFailures"],
            {
                "resolutionCandidate": "uniform/staticUniformBindingInvalid",
                "mappedNotIdentity": "uniform/staticUniformBindingInvalid",
                "uvNotIdentity": "uniform/staticUniformBindingInvalid",
                "coordinatePending": "texture/resourceSnapshotUnresolved",
                "coordinateWrongPurpose": "texture/textureMetadataIncomplete",
                "wrongComponent": "uniform/staticUniformBindingInvalid",
                "targetLiveUse": "uniform/staticUniformBindingInvalid",
                "resolutionSamplerActive": "texture/textureBindingInvalid",
            },
        )

    def test_alpha_attenuation_eligibility_cross_checks_schema_and_graph_identity(
        self,
    ) -> None:
        self.assertEqual(
            self.result["attenuationEligibilityCases"],
            {
                "maskOffPreparedVariant": True,
                "maskOnPreparedVariant": True,
                "wrongSamplerModeRejected": True,
                "auxiliaryGraphInputRejected": True,
                "extraActiveSamplerRejected": True,
                "priorEffectOutputAccepted": True,
                "internalFramebufferRejected": True,
                "differentEffectOutputRejected": True,
                "fallbackCandidateRejected": True,
            },
            self.result,
        )

    def test_color_blend_eligibility_uses_prepared_source_schema_and_graph_identity(
        self,
    ) -> None:
        self.assertEqual(
            self.result["colorBlendEligibilityCases"],
            {
                "unmaskedSourceFact": True,
                "unmaskedTransferProven": True,
                "unmaskedSamplerSetExact": True,
                "modeZeroSourceFact": True,
                "modeZeroTransferProven": True,
                "modeZeroSamplerSetExact": True,
                "unmaskedPreparedVariant": True,
                "stockMaskMultiplyPreparedVariant": True,
                "legacyMaskOverridePreparedVariant": True,
                "modeZeroOpaquePreparedVariant": True,
                "wrongSamplerModeRejected": True,
                "auxiliaryGraphInputRejected": True,
                "extraActiveSamplerRejected": True,
                "priorEffectOutputAccepted": True,
                "internalFramebufferRejected": True,
                "differentEffectOutputRejected": True,
                "fallbackCandidateRejected": True,
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

    def test_dormant_unresolved_material_alias_is_a_typed_graph_input_fact(
        self,
    ) -> None:
        self.assertEqual(
            self.result["dormantGraphInputFacts"],
            {
                "arbitraryHiddenKeySlot0": "proven",
                "unseenArbitraryHiddenKeySlot3": "proven",
            },
            self.result,
        )

    def test_graph_input_alias_uses_the_validated_active_effect_ingress(self) -> None:
        self.assertEqual(
            self.result["admittedEffectIngress"],
            {
                "layerSourceAfterDisabledRawEffects": "success",
                "priorActiveOutputWithRawOrdinalGap": "success",
                "contextIdentityMismatch": "texture/textureReferenceInvalid",
                "wrongLayer": "texture/textureReferenceInvalid",
                "namedLayerSource": "texture/textureReferenceInvalid",
                "selfOutput": "texture/textureReferenceInvalid",
            },
            self.result,
        )

    def test_purpose_selection_and_binding_fail_closed(self) -> None:
        expected = {
            "nonFramebufferDoesNotInject": "texture/textureBindingInvalid",
            "framebufferWithoutIdentity": "texture/textureReferenceInvalid",
            "previousWithoutIdentity": "texture/textureReferenceInvalid",
            "historicalFramebufferWithoutHidden":
                "texture/textureBindingInvalid",
            "historicalFramebufferLabelOnly": "texture/textureBindingInvalid",
            "unknownEditorMaterialAlias": "texture/textureBindingInvalid",
            "regularGraphSampler": "success",
            "customPurposeIgnored": "success",
            "unknownMode": "texture/authoredSamplerSchemaInvalid",
            "multipleCandidates": "success",
            "unreachableGraphCandidate": "success",
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
            "slotSchemaMismatch": "texture/textureBindingInvalid",
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
            "activeDefaultMaskMissing": "texture/textureBindingInvalid",
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
                "registeredStockWaterRippleNormal": "normal",
                "registeredStockWaterRippleNormalConflict": "unproven",
                "neighboringWaterRippleNormalUnproven": "unproven",
                "customWaterRippleNormalUnproven": "unproven",
                "registeredStockShimmerGradient": "preserved-channels",
                "registeredStockLightShaftsGradient": "preserved-channels",
                "registeredStockFireGradient": "preserved-channels",
                "registeredStockFireGradientConflict": "unproven",
                "unregisteredGradient": "unproven",
                "registeredStockCloudNoise": "noise",
                "registeredStockPerlinNoise": "noise",
                "registeredStockVoronoiNoise": "noise",
                "registeredStockLocalVoronoiNoise": "noise",
                "registeredStockUniformNoise": "noise",
                "registeredStockPerlinPurposeConflict": "unproven",
                "registeredStockVoronoiPurposeConflict": "unproven",
                "neighboringCustomPerlinUnproven": "unproven",
                "neighboringPerlin512Unproven": "unproven",
                "neighboringPerlinSuffixUnproven": "unproven",
                "neighboringVoronoiSuffixUnproven": "unproven",
                "neighboringLocalVoronoiSuffixUnproven": "unproven",
                "neighboringUniformSuffixUnproven": "unproven",
                "registeredStockPurposeConflict": "unproven",
                "unknownMaterialAsset": "unproven",
                "conflictingMaterial": "schema-invalid",
                "reachableConditionalAlbedo": "straight-albedo",
                "customPurposeIgnored": "premultiplied-color",
                "opacityMask": "mask",
                "rgbMask": "preserved-channels",
                "rgbMaskNamedTarget": "premultiplied-color",
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

    def test_stock_perlin_semantic_fact_is_bound_to_fixed_resource_hashes(
        self,
    ) -> None:
        expected = {
            "util/perlin_256.tex": (
                "3a9e76025b07080babb4097c08a01ff9fcbae56ad4c122f6b070aaaae94bdd11"
            ),
            "util/perlin_256.tex-json": (
                "2f9cfef09edf3ecff1b6a6d9773cf55a1b12c2fa194a525bbe2c58cf1d70c315"
            ),
        }
        actual = {
            relative: hashlib.sha256(
                (STOCK_MATERIAL_ROOT / relative).read_bytes()
            ).hexdigest()
            for relative in expected
        }
        self.assertEqual(actual, expected)

    def test_stock_caustics_data_semantics_are_bound_to_fixed_resource_hashes(
        self,
    ) -> None:
        expected = {
            "pattern/voronoi.tex": (
                "0c05190a0c05250fb90414cbcc63cceb87e07e7eb6e2eebd368fa93867327885"
            ),
            "pattern/voronoi.tex-json": (
                "2f9cfef09edf3ecff1b6a6d9773cf55a1b12c2fa194a525bbe2c58cf1d70c315"
            ),
            "pattern/voronoi_local.tex": (
                "67a99eda6e1200b89450b4324111efa8969e745490c887a80d9fd29054d2e1e7"
            ),
            "pattern/voronoi_local.tex-json": (
                "2f9cfef09edf3ecff1b6a6d9773cf55a1b12c2fa194a525bbe2c58cf1d70c315"
            ),
            "util/uniform_256.tex": (
                "0717c990a2b2c8e333df2650237825a1b61dc6f6f3a981c67250d1fbed7b333e"
            ),
            "util/uniform_256.tex-json": (
                "2f9cfef09edf3ecff1b6a6d9773cf55a1b12c2fa194a525bbe2c58cf1d70c315"
            ),
        }
        actual = {
            relative: hashlib.sha256(
                (STOCK_MATERIAL_ROOT / relative).read_bytes()
            ).hexdigest()
            for relative in expected
        }
        self.assertEqual(actual, expected)

    def test_registered_stock_default_unblocks_only_typed_implicit_input(self) -> None:
        self.assertEqual(
            self.result["implicitFramebufferSchema"],
            {
                "registeredStockDefault": "0",
                "registeredAuthoredCandidate": "0",
                "unprovenAuthoredCandidate": "0",
                "graphAuthoredCandidate": "",
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

    def test_only_exact_single_branch_sampler_may_seed_its_readiness_combo(
        self,
    ) -> None:
        ambiguous = (
            "shader-preprocessor/shader-variant-invalid:"
            "active-schema-ambiguous"
        )
        self.assertEqual(
            self.result["shaderPreparationBoundary"]["selfGatedReadiness"],
            {
                "ready": "accepted:1",
                "unready": "accepted:",
                "nonUnitGuard": ambiguous,
                "elseBranch": ambiguous,
                "nestedGuard": ambiguous,
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
            "maskedMissing": "texture/textureBindingInvalid",
            "maskedPending": "texture/resourceSnapshotUnresolved",
            "maskedWrongPurpose": "texture/textureMetadataIncomplete",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )

    def test_shader_defaults_and_dynamic_contributors_are_fail_closed(self) -> None:
        expected = {
            "missingUniformDefault": "uniform/staticUniformBindingInvalid",
            "malformedUniformDefault": "uniform/uniformBindingInvalid",
            "exactWhitespaceUniformBindingKey": "success",
            "malformedStaticDeclaration": "uniform/staticUniformBindingInvalid",
            "uniformDeclarationConflict": "uniform/uniformDeclarationConflict",
            "hostUniformDeclarationConflict":
                "uniform/hostUniformDeclarationConflict",
            "hostUniformBindingInvalid": "uniform/hostUniformBindingInvalid",
            "knownTimelineScriptControl": "success",
            "unknownTimelineScriptAttachment": "uniform/uniformScriptAttachmentUnproven",
            "authoredDynamicFallback": "success",
            "dynamicSourceMismatch": "uniform/dynamicUniformBindingInvalid",
            "timelineVectorTypeMismatch": "uniform/dynamicUniformBindingInvalid",
            "unequalScalarSplatFallback":
                "uniform/dynamicUniformBindingInvalid",
            "nonUserScalarSplatContributor":
                "uniform/dynamicUniformBindingInvalid",
            "extraKeyScalarSplat": "uniform/dynamicUniformBindingInvalid",
            "multipleValueContributors": "uniform/uniformContributorPolicyUnproven",
            "runtimeLoopMetadataOnly": "frontend/shaderFrontendFailed",
            "runtimeLoopDynamicProducer": "frontend/shaderFrontendFailed",
            "runtimeLoopOverBudget": "frontend/shaderFrontendFailed",
            "runtimeLoopNegativeExact": "frontend/shaderFrontendFailed",
            "runtimeLoopNonIntegralExact": "frontend/shaderFrontendFailed",
            "runtimeLoopNonFiniteExact": "frontend/shaderFrontendFailed",
            "runtimeLoopMultipleProducer": "frontend/shaderFrontendFailed",
            "runtimeLoopCrossTemplateCache": (
                "invariant/variantSelectionTemplateIdentityInvariant"
            ),
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )

    def test_only_local_declaration_conflicts_are_visual_passthroughs(self) -> None:
        finalizer_text = FINALIZER_SOURCE.read_text(encoding="utf-8")
        visual_text = VISUAL_PASSTHROUGH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            ".hostUniformBindingInvalid",
            finalizer_text,
        )
        self.assertIn(".activeUniformSchemaMissing", finalizer_text)
        for reason in (
            '"material-finalizer-host-uniform-declaration-conflict"',
            '"material-finalizer-uniform-declaration-conflict"',
        ):
            self.assertIn(reason, visual_text)
        self.assertNotIn(
            "material-finalizer-host-uniform-binding",
            visual_text,
        )
        self.assertNotIn("material-finalizer-active-uniform-schema", visual_text)
        self.assertNotIn("material-variant-envelope-invariant", visual_text)

    def test_frame_selection_consumes_only_precompiled_sampler_reachability(self) -> None:
        variant_text = VARIANT_CACHE_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn(
            "SceneResolvedMaterialShaderSchema.reachableSamplers(",
            variant_text,
        )
        self.assertNotIn("reachable-sampler-schema", variant_text)

    def test_finalizer_and_variant_selection_invariants_remain_typed(self) -> None:
        expected = {
            "variantSelectionReachabilityIdentity": (
                "invariant/variantSelectionReachabilityIdentityInvariant"
            ),
            "variantSelectionKey": "invariant/variantSelectionKeyInvariant",
            "terminalGraphOverrideUnavailable": (
                "texture/resourceSnapshotUnresolved"
            ),
            "textureVariantKeyIdentityInvariant": (
                "invariant/textureVariantKeyIdentityInvariant"
            ),
            "graphRoleIdentityInvariant": "invariant/graphRoleIdentityInvariant",
            "programAssemblyIdentityInvariant": (
                "invariant/programAssemblyIdentityInvariant"
            ),
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )
        self.assertEqual(
            self.result["failures"]["variantSelectionKeyDetails"],
            "admitted-1,resolved-1,matches-0,key-e1-r1-a1-fs0-0-7",
        )
        finalizer_text = FINALIZER_SOURCE.read_text(encoding="utf-8")
        variant_text = VARIANT_CACHE_SOURCE.read_text(encoding="utf-8")
        self.assertIn(".finalizerUnexpectedFailure", finalizer_text)
        self.assertIn(".variantSelectionUnexpectedFailure", variant_text)

    def test_render_state_and_color_contracts_fail_closed(self) -> None:
        expected = {
            "unsupportedState": "state/renderStateInvalid",
            "dataGraphInput": "texture/textureMetadataIncomplete",
            "arithmeticOutput": "color/colorContractUnproven",
            "arithmeticScalarOutput": "success",
            "scalarRedConsumer": "success",
            "scalarRedForgedTEXFormat": "texture/textureMetadataIncomplete",
            "scalarRedWrongFormat": "texture/textureMetadataIncomplete",
            "maskedColorAuxiliary": "texture/textureMetadataIncomplete",
            "overlayColorAuxiliary": "texture/textureMetadataIncomplete",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )


if __name__ == "__main__":
    unittest.main()
