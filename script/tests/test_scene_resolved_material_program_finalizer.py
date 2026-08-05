#!/usr/bin/env python3

"""End-to-end R3 finalization from authored contract to immutable Program."""

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
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderDirective.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+Schema.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderPreprocessor.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderUniformBinder.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlanner+Preparation.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SCENE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Resources/SceneFrameTextureRegistry.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramIdentity.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+Derivation.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialUniformEncoder.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialShaderSchema.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureResolver.swift",
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

nonisolated enum SceneAuthoredShaderExecutionPlanner {
    static let compilerBackend = SceneEffectStageCompilerBackend.authoredShader

    static func compilerFailure(
        phase: SceneEffectStageCompilerFailure.Phase,
        code: SceneEffectStageCompilerFailure.Code,
        details: [String] = []
    ) -> SceneEffectStageCompilerFailure {
        .init(backend: compilerBackend, phase: phase, code: code, details: details)
    }
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

private let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private func fragmentSource(
    samplerMetadata: String?,
    uniformMetadata: String?,
    secondSamplerMetadata: String?,
    arithmetic: Bool = false
) -> String {
    let annotation = samplerMetadata.map { " // \($0)" } ?? ""
    let uniformAnnotation = uniformMetadata.map { " // \($0)" } ?? ""
    let secondSampler = secondSamplerMetadata.map {
        "uniform sampler2D g_Texture1; // \($0)"
    } ?? ""
    let output = arithmetic
        ? "texSample2D(g_Texture0, v_TexCoord) * 0.5"
        : "texSample2D(g_Texture0, v_TexCoord)"
    return """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;\(annotation)
    \(secondSampler)
    uniform vec3 u_Tint;\(uniformAnnotation)
    uniform float g_Time; // {"default":99}
    void main() {
        gl_FragColor = \(output);
    }
    """
}

private func contract(
    revision: String,
    samplerMetadata: String? = nil,
    uniformMetadata: String? = #"{"material":"Tint","default":"1 0.5 0.25"}"#,
    secondSamplerMetadata: String? = nil,
    arithmetic: Bool = false
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
        stage(.vertex, path: "\(revision)/root.vert", source: vertexSource),
        stage(
            .fragment,
            path: "\(revision)/root.frag",
            source: fragmentSource(
                samplerMetadata: samplerMetadata,
                uniformMetadata: uniformMetadata,
                secondSamplerMetadata: secondSamplerMetadata,
                arithmetic: arithmetic
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
        sourceGraph: sourceGraph
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
        sceneTime: 2,
        dayTime: 0.5,
        frameTime: 1 / 60,
        pointerCurrentNDC: SIMD2(0.25, -0.5),
        pointerPreviousNDC: SIMD2.zero,
        texturePhysicalSizes: [0: CGSize(width: 2, height: 2)]
    )
}

private func frameInputs(frameIndex: UInt64) -> SceneAuthoredShaderFrameInputs {
    .init(
        frameIndex: frameIndex,
        screenSize: CGSize(width: 1920, height: 1080),
        sceneTime: 2,
        dayTime: 0.5,
        frameTime: 1 / 60,
        pointerCurrentNDC: SIMD2(0.25, -0.5),
        pointerPreviousNDC: .zero
    )
}

private func dynamicSnapshot(
    frameIndex: UInt64,
    source: SceneDynamicSource?
) -> SceneDynamicSnapshot {
    let target = SceneDynamicTarget.effectConstant(
        layerID: fixtureLayerID,
        effectIndex: 0,
        passIndex: 0,
        name: "Tint"
    )
    let value = SceneDynamicValue.vector3(1, 0.5, 0.25)
    var user: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var timeline: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var script: [SceneDynamicTarget: SceneDynamicValue] = [:]
    switch source {
    case .userProperty: user[target] = value
    case .timeline: timeline[target] = value
    case .sceneScript: script[target] = value
    case .authored, nil: break
    }
    return SceneDynamicSnapshotResolver().resolve(
        frameIndex: frameIndex,
        generation: 1,
        definitions: [.init(
            target: target,
            valueType: .vector3,
            authoredValue: value
        )],
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
    implicitFramebufferIdentity: Graph.TextureIdentity? = nil
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
        frameInputs: frameInputs(frameIndex: frameInputIndex)
    )
    switch frame {
    case let .failure(failure):
        return .failure(failure)
    case let .success(frame):
        return SceneResolvedMaterialProgramFinalizer.finalize(
            frame.finalizationInput(
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
                implicitFramebufferIdentity: implicitFramebufferIdentity
            )
        )
    }
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
    assetReference: Bool = false
) -> String {
    let shader = contract(revision: "sampler-schema", samplerMetadata: metadata)
    guard case let .accepted(prepared) =
            SceneAuthoredShaderExecutionPlanner.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true]
            ) else { return "preparation-failed" }
    do {
        guard let sampler = try SceneResolvedMaterialShaderSchema
            .activeSamplers(prepared)[0] else { return "missing" }
        let reference: Template.TextureReference = assetReference
            ? .asset(SceneVFSAssetPath("textures/fixture.tex")!)
            : .graph(graphTexture())
        return sampler.purpose(for: reference)?.reportToken ?? "unproven"
    } catch {
        return "schema-invalid"
    }
}

private func positiveDiagnostic(_ shader: SceneShaderContract) -> String {
    switch SceneAuthoredShaderExecutionPlanner.prepareShaderStages(
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

@main
private enum Harness {
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
        ]

        let result: [String: Any] = [
            "metalAvailable": true,
            "positive": [
                "fixedEightSlots": programA.textureSlots.count == 8
                    && programA.textureSlots[0] != nil
                    && programA.textureSlots.dropFirst().allSatisfy { $0 == nil },
                "uniformLayoutCorrect": uniformLayoutCorrect,
                "shaderUniformDefault": tintDefaultCorrect,
                "hostIgnoresShaderDefault": hostDefaultIgnored,
                "explicitUniformOverridesDefault": explicitOverrideCorrect,
                "assetReferenceTyped": failureToken(assetProgram) == "success",
                "userReferenceTyped": failureToken(propertyProgram) == "success",
                "providerReferenceTyped": failureToken(providerProgram) == "success",
                "implicitFramebufferTyped": implicitFramebufferTyped,
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
            ],
            "identity": [
                "semanticStable": programA.semanticIdentity == programB.semanticIdentity,
                "exactRevisionSensitive": programA.exactIdentity != programB.exactIdentity,
            ],
            "samplerSchema": [
                "regularGraph": samplerPurposeToken(nil),
                "regularAsset": samplerPurposeToken(nil, assetReference: true),
                "customPurposeIgnored": samplerPurposeToken(#"{"purpose":"mask"}"#),
                "opacityMask": samplerPurposeToken(#"{"mode":"opacitymask"}"#),
                "rgbMask": samplerPurposeToken(#"{"mode":"rgbmask"}"#),
                "flowMask": samplerPurposeToken(#"{"mode":"flowmask"}"#),
                "normal": samplerPurposeToken(#"{"mode":"normal"}"#),
                "depth": samplerPurposeToken(#"{"mode":"depth"}"#),
                "normalFormat": samplerPurposeToken(#"{"format":"normalmap"}"#),
                "genericFormat": samplerPurposeToken(#"{"format":"rgba8"}"#),
                "unknownMode": samplerPurposeToken(#"{"mode":"mystery"}"#),
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
            "authoredOverridesShaderDefault": "success",
            "authoredFailureDoesNotUseShaderDefault": (
                "texture/resourceSnapshotUnresolved"
            ),
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
                "customPurposeIgnored": "premultiplied-color",
                "opacityMask": "mask",
                "rgbMask": "preserved-channels",
                "flowMask": "flow",
                "normal": "schema-invalid",
                "depth": "schema-invalid",
                "normalFormat": "schema-invalid",
                "genericFormat": "schema-invalid",
                "unknownMode": "schema-invalid",
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
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )


if __name__ == "__main__":
    unittest.main()
