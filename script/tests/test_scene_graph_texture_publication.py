#!/usr/bin/env python3

"""Generation-scoped graph publications and immutable snapshot overlays."""

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
    SCENE_ROOT / "RenderGraph/SceneShaderMacroExpansion.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+Schema.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+DisabledCombo.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderPreprocessor+Directive.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderPreprocessor.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Clear.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
    SCENE_ROOT / "RenderGraph/SceneLayerFullFramePairPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphExecutionState.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphExecutionState+Validation.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphExecutionState+Identity.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetTable.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetTable+Mapped.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetLease.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetLease+Publication.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderBoundedLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStaticLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderDeadBindingAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVectorConversion.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVaryingArrayEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixGraphAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderOpaqueInputAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderIndependentAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrameInputs.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPreparation.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPreparation+Support.swift",
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
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+Derivation.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+ColorDerivation.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialUniformEncoder.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialShaderSchema.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialShaderSchema+SamplerPurpose.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialShaderSchema+Reachability.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant+LaunchEnvelope.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Diagnostics.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialTextureResolver+Launch.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramFinalizer.swift",
]


SUPPORT = r'''
import Foundation
import Metal

nonisolated enum SceneEffectStageCompilerBackend { case authoredShader }

nonisolated struct SceneEffectStageCompilerFailure {
    enum Phase: String { case shaderPreprocessor = "shader-preprocessor"; case invariant }
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
        case material, instance, userTexture, explicitBinding
    }
}

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneOpacityExecutionPlan {}

struct SceneAuthoredEffectExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let cursorRipple: SceneCursorRippleExecutionPlan?
    let opacity: SceneOpacityExecutionPlan? = nil

    var yieldsToResolvedMaterialProgram: Bool { opacity != nil }
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

struct SceneGraphCommandRuntime {
    init?(
        plan: SceneGraphRenderTargetPlan,
        texturesByIdentity: [
            SceneAuthoredEffectRenderPlan.TextureIdentity: MTLTexture
        ]
    ) {
        _ = plan
        _ = texturesByIdentity
    }
}

final class SceneOffscreenTexturePool {
    struct Pair {}
}
'''


HARNESS = r'''
import Foundation
import Metal
import simd

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Plan = SceneGraphRenderTargetPlan
private typealias State = SceneGraphExecutionState
private typealias Template = SceneResolvedMaterialTemplate

private let layerID = 42
private let effect = Graph.EffectKey(
    layerID: layerID, effectIndex: 0, descriptorID: "fixture-effect"
)
private let input = Graph.TextureIdentity(
    kind: .layerSource, layerID: layerID, effect: nil, name: nil
)
private let output = Graph.TextureIdentity(
    kind: .effectOutput, layerID: layerID, effect: effect, name: nil
)
private let first = Graph.TextureIdentity(
    kind: .framebuffer, layerID: layerID, effect: effect, name: "first"
)
private let second = Graph.TextureIdentity(
    kind: .framebuffer, layerID: layerID, effect: effect, name: "second"
)
private let extent = Plan.PixelExtent(width: 2, height: 2)

private func logical(_ identity: Graph.TextureIdentity) -> Plan.LogicalTarget {
    .init(
        identity: identity,
        extent: extent,
        format: .rgbaBackbuffer,
        isUnique: false,
        lifetime: .init(
            firstWriteNodeIndex: 0,
            lastWriteNodeIndex: 3,
            firstReadNodeIndex: 1,
            lastReadNodeIndex: 3
        ),
        initialClear: nil
    )
}

private func targetPlan() -> Plan {
    .testingPlan(
        layerID: layerID,
        input: input,
        output: output,
        inputExtent: extent,
        logicalTargets: [logical(first), logical(second)]
    )
}

private func makeLease(_ device: MTLDevice) -> SceneGraphRenderTargetLease {
    let table: SceneGraphRenderTargetTable
    switch SceneGraphRenderTargetTable.make(
        plan: targetPlan(), device: device, byteBudget: 1_024
    ) {
    case .success(let value): table = value
    case .failure(let failure):
        fatalError("table failed: \(failure.rawValue)")
    }
    var ordinal = 0
    switch SceneGraphRenderTargetLease.make(
        table: table,
        generation: 7,
        tokenForTexture: { _ in
            defer { ordinal += 1 }
            return .init(rawValue: "physical-\(ordinal)")
        }
    ) {
    case .success(let value): return value
    case .failure(let failure):
        fatalError("lease failed: \(failure.rawValue)")
    }
}

private func require(
    _ result: Result<SceneFrameTextureResource, SceneGraphRenderTargetLease.PublicationFailure>
) -> SceneFrameTextureResource {
    switch result {
    case .success(let value): return value
    case .failure(let failure): fatalError("publication failed: \(failure.rawValue)")
    }
}

private func failure(
    _ result: Result<SceneFrameTextureResource, SceneGraphRenderTargetLease.PublicationFailure>
) -> String {
    switch result {
    case .success: return "success"
    case .failure(let value): return value.rawValue
    }
}

private let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private let fragmentSource = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
void main() {
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
}
"""

private func shaderContract() -> SceneShaderContract {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        path: String,
        source: String
    ) -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(
            source, stageRelativePath: path
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
        stage(.vertex, path: "fixture/root.vert", source: vertexSource),
        stage(.fragment, path: "fixture/root.frag", source: fragmentSource),
    ]
    let sourceGraph = SceneShaderSourceGraph(
        roots: [
            .init(label: "vertex", virtualPath: "fixture/root.vert"),
            .init(label: "fragment", virtualPath: "fixture/root.frag"),
        ],
        nodes: stages.map {
            .init(
                virtualPath: $0.relativePath,
                provenance: .package,
                source: $0.source,
                rawSHA256: $0.rawSHA256,
                byteCount: $0.source.utf8.count
            )
        },
        edges: [],
        diagnostics: [],
        dependencySHA256: "fixture-dependency"
    )
    return .init(
        identity: "fixture/shader",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-contract",
        sourceGraph: sourceGraph
    )
}

private func template() -> Template {
    let contract = shaderContract()
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[0] = .init(index: 0, candidates: [
        .init(reference: .graph(input), provenance: .explicitBinding),
    ])
    return Template.validated(
        textureSlots: slots,
        combos: [],
        uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )!,
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: [.init(slot: 0, texture: .layerSource)]
        ),
        shaderContract: contract,
        diagnosticProvenance: .init(
            nodeIndex: 0,
            authoredShaderPath: contract.identity,
            contractIdentity: contract.identity,
            contractCanonicalSHA256: contract.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
}

private func resolveProgram(
    snapshot: SceneFrameTextureRegistrySnapshot
) -> Result<SceneResolvedMaterialProgram, SceneResolvedMaterialFailure> {
    let frame = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot,
        dynamicSnapshot: .empty(frameIndex: snapshot.frameIndex),
        frameInputs: .init(
            frameIndex: snapshot.frameIndex,
            screenSize: CGSize(width: 2, height: 2),
            sceneTime: 0,
            dayTime: 0,
            frameTime: 1 / 60,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero
        )
    )
    guard case .success(let value) = frame else {
        fatalError("frame snapshot failed")
    }
    return SceneResolvedMaterialProgramFinalizer.finalize(
        value.finalizationInput(
            template: template(),
            renderSize: CGSize(width: 2, height: 2),
            modelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4
        )
    )
}

private func makeWrongTexture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 2,
        height: 2,
        mipmapped: false
    )
    descriptor.usage = .shaderRead
    return device.makeTexture(descriptor: descriptor)!
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let lease = makeLease(device)
        let aliasMapping: [Graph.TextureIdentity: MTLTexture] = [
            input: lease.table.inputTexture,
            first: lease.table.texture(for: first)!,
            second: lease.table.texture(for: second)!,
            output: lease.table.inputTexture,
        ]
        guard case .success(let aliasTable) = SceneGraphRenderTargetTable.makeMapped(
            plan: lease.table.plan,
            device: device,
            texturesByIdentity: aliasMapping,
            fullFramePair: .init(
                first: lease.table.inputTexture,
                second: lease.table.outputTexture
            ),
            expectsInputOutputAlias: true
        ) else { fatalError("alias table failed") }
        let aliasTokens = Dictionary(uniqueKeysWithValues:
            aliasTable.orderedPhysicalTextures.enumerated().map {
                (ObjectIdentifier($0.element), State.PhysicalToken(
                    rawValue: "alias-physical-\($0.offset)"
                ))
            }
        )
        guard case .success(let aliasLease) = SceneGraphRenderTargetLease.make(
            table: aliasTable,
            generation: 8,
            tokenForTexture: { aliasTokens[ObjectIdentifier($0)] }
        ), let aliasOutput = aliasLease.allocation.resources[output],
        let aliasInput = aliasLease.allocation.resources[input] else {
            fatalError("alias lease failed")
        }
        let aliasOutputResource = require(aliasLease.fullFrameResource(
            for: output,
            member: .zero,
            contentGeneration: 12,
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        let aliasRotatedInputResource = require(aliasLease.fullFrameResource(
            for: input,
            member: .one,
            contentGeneration: 13,
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        let aliasedEndpointPublication = aliasInput.token == aliasOutput.token
            && aliasLease.fullFramePair.first != aliasLease.fullFramePair.second
            && aliasOutputResource.publication.candidate.texture
                === aliasTable.inputTexture
            && aliasRotatedInputResource.publication.candidate.texture
                === aliasTable.fullFramePair.second
        var nonIdempotentOrdinal = 0
        guard case .success(let resolvedOnceLease) = SceneGraphRenderTargetLease.make(
            table: aliasTable,
            generation: 9,
            tokenForTexture: { _ in
                defer { nonIdempotentOrdinal += 1 }
                return .init(rawValue: "resolved-once-\(nonIdempotentOrdinal)")
            }
        ), let resolvedOnceInput = resolvedOnceLease.allocation.resources[input],
        let resolvedOnceOutput = resolvedOnceLease.allocation.resources[output] else {
            fatalError("non-idempotent token provider failed")
        }
        let nonIdempotentProviderResolvedOnce = nonIdempotentOrdinal
                == aliasTable.residentTextureCount
            && resolvedOnceInput.token == resolvedOnceOutput.token
            && resolvedOnceLease.fullFramePair.first == resolvedOnceInput.token
        let firstPhysical = lease.allocation.resources[first]!.versioned(10)
        let secondPhysical = lease.allocation.resources[second]!.versioned(11)
        let firstResource = require(lease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let secondResource = require(lease.graphResource(
            for: second,
            versionedResource: secondPhysical,
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        let swappedFirst = require(lease.graphResource(
            for: first,
            versionedResource: secondPhysical,
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        guard let baseInput = firstResource.rewrappedForGraphIdentity(input),
              let swappedInput = swappedFirst.rewrappedForGraphIdentity(input) else {
            fatalError("graph rewrap failed")
        }

        let swapPreservesPhysicalAtom =
            swappedFirst.publication.requestIdentity == .graph(first)
            && secondResource.publication.requestIdentity == .graph(second)
            && swappedFirst.publication.candidate.texture
                === secondResource.publication.candidate.texture
            && swappedFirst.publication.candidate.identity
                == secondResource.publication.candidate.identity
            && swappedFirst.publication.candidate.generation
                == secondResource.publication.candidate.generation
            && swappedFirst.publication.contentGeneration
                == secondResource.publication.contentGeneration
            && swappedFirst.resourceGeneration == secondResource.resourceGeneration

        let physicalIdentityCorrect: Bool
        switch secondResource.publication.candidate.identity {
        case let .provider(.graph(generation, token)):
            physicalIdentityCorrect = generation == lease.generation
                && token == secondPhysical.token.rawValue
        default:
            physicalIdentityCorrect = false
        }

        let base = SceneFrameTextureRegistrySnapshot(
            frameEpoch: 3,
            frameIndex: 9,
            entries: [
                .graph(input): .ready(baseInput),
                .graph(first): .absent,
            ]
        )
        guard let overlaid = base.overlayingGraphResources([
            input: swappedInput,
            first: swappedFirst,
        ]) else { fatalError("valid overlay failed") }
        let immutableOverlay = base.resource(for: .graph(input))?
                .publication.candidate.texture === firstResource.publication.candidate.texture
            && overlaid.resource(for: .graph(input))?
                .publication.candidate.texture === secondResource.publication.candidate.texture
            && overlaid.frameEpoch == base.frameEpoch
            && overlaid.frameIndex == base.frameIndex

        let programResolvedOverlay: Bool
        switch resolveProgram(snapshot: overlaid) {
        case .failure:
            programResolvedOverlay = false
        case .success(let program):
            let slot = program.textureSlots[0]
            programResolvedOverlay = slot?.registryIdentity == .graph(input)
                && slot?.resource.publication.candidate.texture
                    === secondResource.publication.candidate.texture
                && slot?.resource.publication.candidate.identity
                    == secondResource.publication.candidate.identity
                && slot?.resource.resourceGeneration
                    == secondPhysical.contentGeneration
                && slot?.resource.publication.contentGeneration
                    == secondPhysical.contentGeneration
        }

        let straightFailure = failure(lease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .resolved(.straightAlpha)
        ))
        let unresolvedFailure = failure(lease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .unresolved
        ))
        let zeroGenerationFailure = failure(lease.graphResource(
            for: first,
            versionedResource: .init(
                token: firstPhysical.token,
                descriptor: firstPhysical.descriptor,
                contentGeneration: 0
            ),
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let unknownTokenFailure = failure(lease.graphResource(
            for: first,
            versionedResource: .init(
                token: .init(rawValue: "unknown-physical"),
                descriptor: firstPhysical.descriptor,
                contentGeneration: 1
            ),
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let wrongDescriptorFailure = failure(lease.graphResource(
            for: first,
            versionedResource: .init(
                token: secondPhysical.token,
                descriptor: .init(
                    extent: .init(width: 3, height: 2),
                    format: .rgbaBackbuffer,
                    isUnique: false,
                    initialClear: nil
                ),
                contentGeneration: 1
            ),
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let pairTokenFailure = failure(lease.graphResource(
            for: first,
            versionedResource: .init(
                token: lease.fullFramePair.first,
                descriptor: firstPhysical.descriptor,
                contentGeneration: 1
            ),
            fragmentColorRepresentation: .resolved(.opaque)
        ))

        var aliasedResources = lease.allocation.resources
        aliasedResources[second] = lease.allocation.resources[first]
        let staticAliasLease = SceneGraphRenderTargetLease(
            table: lease.table,
            allocation: .init(
                generation: lease.generation,
                resources: aliasedResources
            ),
            texturesByToken: lease.texturesByToken,
            fullFramePair: lease.fullFramePair
        )
        let staticAliasFailure = failure(staticAliasLease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .resolved(.opaque)
        ))

        var wrongTextures = lease.texturesByToken
        wrongTextures[firstPhysical.token] = makeWrongTexture(device)
        let corruptLease = SceneGraphRenderTargetLease(
            table: lease.table,
            allocation: lease.allocation,
            texturesByToken: wrongTextures
        )
        let wrongTextureFailure = failure(corruptLease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let endpointViaFramebufferFailure = failure(aliasLease.graphResource(
            for: output,
            versionedResource: aliasOutput.versioned(12),
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        let invalidFullFrameIdentityFailure = failure(aliasLease.fullFrameResource(
            for: first,
            member: .zero,
            contentGeneration: 1,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let zeroFullFrameGenerationFailure = failure(aliasLease.fullFrameResource(
            for: input,
            member: .zero,
            contentGeneration: 0,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let swappedPairLease = SceneGraphRenderTargetLease(
            table: aliasLease.table,
            allocation: aliasLease.allocation,
            texturesByToken: aliasLease.texturesByToken,
            fullFramePair: .init(
                first: aliasLease.fullFramePair.second,
                second: aliasLease.fullFramePair.first
            )
        )
        let wrongPairMemberFailure = failure(swappedPairLease.fullFrameResource(
            for: input,
            member: .zero,
            contentGeneration: 1,
            fragmentColorRepresentation: .resolved(.opaque)
        ))

        let incomplete = SceneFrameTextureResource(
            publication: .init(
                requestIdentity: swappedFirst.publication.requestIdentity,
                candidate: swappedFirst.publication.candidate,
                contentGeneration: swappedFirst.publication.contentGeneration + 1
            ),
            resourceGeneration: swappedFirst.resourceGeneration
        )
        let incompleteOverlayRejected = base.overlayingGraphResources([
            first: incomplete,
        ]) == nil
            && base.resource(for: .graph(input))?.publication.candidate.texture
                === firstResource.publication.candidate.texture
        let wrongRequestOverlayRejected = base.overlayingGraphResources([
            first: secondResource,
        ]) == nil
        let invalidGraphIdentity = Graph.TextureIdentity(
            kind: .framebuffer,
            layerID: layerID,
            effect: nil,
            name: nil
        )
        let invalidGraphRewrapRejected =
            secondResource.rewrappedForGraphIdentity(invalidGraphIdentity) == nil

        let output: [String: Any] = [
            "metalAvailable": true,
            "positive": [
                "opaquePublication": firstResource.isCompleteGraphResource,
                "premultipliedPublication": secondResource.isCompleteGraphResource,
                "physicalIdentity": physicalIdentityCorrect,
                "swapPreservesPhysicalAtom": swapPreservesPhysicalAtom,
                "immutableOverlay": immutableOverlay,
                "programResolvedOverlay": programResolvedOverlay,
                "aliasedEndpointPublication": aliasedEndpointPublication,
                "nonIdempotentProviderResolvedOnce": nonIdempotentProviderResolvedOnce,
            ],
            "failures": [
                "straight": straightFailure,
                "unresolved": unresolvedFailure,
                "zeroGeneration": zeroGenerationFailure,
                "unknownToken": unknownTokenFailure,
                "wrongDescriptor": wrongDescriptorFailure,
                "pairToken": pairTokenFailure,
                "staticAlias": staticAliasFailure,
                "wrongTexture": wrongTextureFailure,
                "endpointViaFramebuffer": endpointViaFramebufferFailure,
                "invalidFullFrameIdentity": invalidFullFrameIdentityFailure,
                "zeroFullFrameGeneration": zeroFullFrameGenerationFailure,
                "wrongPairMember": wrongPairMemberFailure,
                "incompleteOverlay": incompleteOverlayRejected ? "rejected" : "accepted",
                "wrongRequestOverlay": wrongRequestOverlayRejected ? "rejected" : "accepted",
                "invalidGraphRewrap": invalidGraphRewrapRejected ? "rejected" : "accepted",
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: output,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneGraphTexturePublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-graph-texture-publication-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "graph-texture-publication-test"
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
                "-D",
                "SCENE_GRAPH_TESTING",
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

    def test_graph_publication_and_program_overlay(self) -> None:
        self.assertEqual(
            [name for name, passed in self.result["positive"].items() if not passed],
            [],
            self.result,
        )

    def test_invalid_graph_atoms_fail_closed(self) -> None:
        self.assertEqual(
            self.result["failures"],
            {
                "straight": "colorRepresentationUnresolved",
                "unresolved": "colorRepresentationUnresolved",
                "zeroGeneration": "invalidGeneration",
                "unknownToken": "unknownPhysicalToken",
                "wrongDescriptor": "descriptorMismatch",
                "pairToken": "unknownPhysicalToken",
                "staticAlias": "physicalAlias",
                "wrongTexture": "textureMismatch",
                "endpointViaFramebuffer": "invalidLogicalIdentity",
                "invalidFullFrameIdentity": "invalidLogicalIdentity",
                "zeroFullFrameGeneration": "invalidGeneration",
                "wrongPairMember": "pairMemberMismatch",
                "incompleteOverlay": "rejected",
                "wrongRequestOverlay": "rejected",
                "invalidGraphRewrap": "rejected",
            },
        )


if __name__ == "__main__":
    unittest.main()
