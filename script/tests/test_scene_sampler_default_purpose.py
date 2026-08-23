#!/usr/bin/env python3

"""Typed sampler-default purpose inheritance through immutable Program identity."""

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
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneStockTextureSemanticRegistry.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SCENE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Resources/SceneFrameTextureRegistry.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "Resources/SceneTexturePathResolver.swift",
    SCENE_ROOT / "Resources/SceneMaterialAssetTextureCatalog.swift",
    *scene_swift_sources("resolved_material_frame_finalization"),
]


SUPPORT = r'''
import Foundation

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
        case shaderModuleResolutionRejected = "shader-module-resolution-rejected"
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
    case notApplicable, rejected(SceneEffectStageCompilerFailure), accepted(Value)
}
nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable { case material, instance, userTexture, explicitBinding }
}
nonisolated struct SceneRenderDescriptor {
    struct Layer { let imagePath: String? }
    struct ModelMaterialLink { let modelPath: String; let materialPath: String }
    struct MaterialPass { let materialPath: String; let texturePaths: [String] }
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPass]

    init(
        modelMaterialLinks: [ModelMaterialLink] = [],
        materialPasses: [MaterialPass] = []
    ) {
        self.modelMaterialLinks = modelMaterialLinks
        self.materialPasses = materialPasses
    }
}
'''


HARNESS = r'''
import Foundation
import Metal
import simd

private typealias Program = SceneResolvedMaterialProgram
private typealias Template = SceneResolvedMaterialTemplate
private let overridePath = SceneVFSAssetPath("fixtures/unseen/static-authored")!
private let animatedPath = SceneVFSAssetPath("particle/fog/fog2")!
private let preservedDefault = SceneVFSAssetPath("gradient/gradient_fire")!
private let preservedDefault2 = SceneVFSAssetPath("gradient/gradient_iridescent")!
private let noiseDefault = SceneVFSAssetPath("util/noise")!

private func contract(
    default path: String,
    active: Bool = true,
    samplerSlot: Int = 0
) -> SceneShaderContract {
    let combo = active ? "" : #"// [COMBO] {"combo":"ACTIVE","default":0}"#
    let guardOpen = active ? "" : "#if ACTIVE"
    let guardClose = active ? "" : "#endif"
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() { v_TexCoord = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
    """
    let fragment = """
    varying vec2 v_TexCoord;
    \(combo)
    \(guardOpen)
    uniform sampler2D g_Texture\(samplerSlot); // {"default":"\(path)"}
    \(guardClose)
    void main() {
        vec4 outputColor = vec4(1.0);
    \(guardOpen)
        outputColor.rgb = texSample2D(g_Texture\(samplerSlot), v_TexCoord).rgb;
    \(guardClose)
        gl_FragColor = outputColor;
    }
    """
    func stage(_ kind: SceneShaderContract.StageKind, _ path: String, _ source: String)
        -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
        return .init(
            kind: kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes, annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let stages = [
        stage(.vertex, "fixture/root.vert", vertex),
        stage(.fragment, "fixture/root.frag", fragment),
    ]
    let dependency = SceneShaderStableDigest.hash(Data((vertex + fragment).utf8))
    return .init(
        identity: "fixture/sampler-default-purpose",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: dependency,
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "fixture/root.vert"),
                .init(label: "fragment", virtualPath: "fixture/root.frag"),
            ],
            nodes: stages.map {
                .init(
                    virtualPath: $0.relativePath, provenance: .package,
                    source: $0.source, rawSHA256: $0.rawSHA256,
                    byteCount: $0.source.utf8.count
                )
            },
            edges: [], diagnostics: [], dependencySHA256: dependency
        )
    )
}

private func template(
    _ shader: SceneShaderContract,
    candidatePath: SceneVFSAssetPath = overridePath,
    slot: Int = 0
) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[slot] = .init(index: slot, candidates: [
        .init(reference: .asset(candidatePath), provenance: .explicitBinding),
    ])
    return Template.validated(
        textureSlots: slots, combos: [], uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(
            blending: "normal", depthTest: "disabled", depthWrite: "disabled",
            cullMode: "nocull", alphaWriting: nil
        )!,
        graphRole: .init(
            effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .effectOutput, bindings: []
        ),
        shaderContract: shader,
        diagnosticProvenance: .init(
            nodeIndex: 17, authoredShaderPath: shader.identity,
            contractIdentity: shader.identity,
            contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [], uniformSources: []
        )
    )!
}

private func texture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    return device.makeTexture(descriptor: descriptor)!
}

private func ready(
    _ device: MTLDevice,
    request: SceneFrameTextureIdentity,
    purpose: SceneTextureLoadPurpose,
    requestOverride: SceneFrameTextureIdentity? = nil,
    candidatePurpose: SceneTextureLoadPurpose? = nil,
    generationMismatch: Bool = false,
    textureOverride: MTLTexture? = nil
) -> SceneFrameTextureLookupStatus {
    let revision = SceneTextureFileRevision(
        fileSystemID: 1, fileID: 2, statusChangedAtSeconds: 3,
        statusChangedAtNanoseconds: 4
    )
    let candidate = SceneTextureCandidate(
        texture: textureOverride ?? texture(device),
        identity: .file(path: overridePath.value),
        generation: generationMismatch
            ? .provider(contentGeneration: 1)
            : .file(byteCount: 16, modifiedAtBits: 5, revision: revision),
        purpose: candidatePurpose ?? purpose, content: .data,
        physicalSize: CGSize(width: 2, height: 2),
        mappedSize: CGSize(width: 2, height: 2), uvTransform: .identity,
        sampling: .directImageFallback
    )
    return .ready(.init(
        publication: .init(
            requestIdentity: requestOverride ?? request,
            candidate: candidate, contentGeneration: 1
        ),
        resourceGeneration: 1
    ))
}

private func sampler(
    _ shader: SceneShaderContract,
    slot: Int = 0
) -> SceneResolvedMaterialShaderSchema.Sampler? {
    guard case let .accepted(prepared) =
        SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader, combos: [:], textureReadiness: [slot: true]
        ) else { return nil }
    return try? SceneResolvedMaterialShaderSchema.activeSamplers(prepared)[slot]
}

private func input(
    _ template: Template,
    entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus]
) -> SceneResolvedMaterialFinalizationInput? {
    let dynamic = SceneDynamicSnapshotResolver().resolve(
        frameIndex: 1, generation: 1, definitions: [], userValues: [:],
        timelineValues: [:], sceneScriptValues: [:]
    ).snapshot
    let frameInputs = SceneAuthoredShaderFrameInputs(
        frameIndex: 1, screenSize: CGSize(width: 2, height: 2), sceneTime: 0,
        dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero,
        pointerPreviousNDC: .zero, pointerPrimaryButtonDown: false,
        parallaxPositionNDC: .zero, audioSpectrum: .silent
    )
    guard case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: .init(frameEpoch: 1, frameIndex: 1, entries: entries),
        dynamicSnapshot: dynamic, frameInputs: frameInputs
    ) else { return nil }
    return frame.finalizationInput(
        template: template, renderSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4
    )
}

private func cache(
    _ template: Template,
    purpose: SceneTextureLoadPurpose,
    path: SceneVFSAssetPath = overridePath
)
    -> SceneResolvedMaterialVariantCache? {
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: template, maximumVariantCount: 8
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: nil,
        assetStates: [.init(path: path, purpose: purpose): .ready(.data)]
    ) else { return nil }
    return cache
}

private func launchFailure(_ template: Template) -> String {
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: template, maximumVariantCount: 8
    ) else { return "launch-validation-failed" }
    switch cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: nil, assetStates: [:]
    ) {
    case .success: return "success"
    case .failure(.capacity): return "capacity"
    case let .failure(.material(failure)):
        return "\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.slot ?? -1)"
    }
}

private func finalize(
    _ template: Template,
    cache: SceneResolvedMaterialVariantCache,
    entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus]
) -> Result<Program, SceneResolvedMaterialFailure>? {
    guard let input = input(template, entries: entries) else { return nil }
    return SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: cache)
}

private func program(
    _ device: MTLDevice, defaultPath: SceneVFSAssetPath,
    purpose: SceneTextureLoadPurpose, sharedTexture: MTLTexture
) -> Program? {
    let value = template(contract(default: defaultPath.value))
    let identity = SceneAssetTextureIdentity(path: overridePath, purpose: purpose)
    guard let cache = cache(value, purpose: purpose) else {
        FileHandle.standardError.write(Data("cache-failed:\(defaultPath.value)\n".utf8))
        return nil
    }
    let result = finalize(
        value, cache: cache,
        entries: [.asset(identity): ready(
            device, request: .asset(identity), purpose: purpose,
            textureOverride: sharedTexture
        )]
    )
    guard case let .success(program)? = result else {
        FileHandle.standardError.write(Data(
            "finalize-failed:\(defaultPath.value):\(failureToken(result))\n".utf8
        ))
        return nil
    }
    return program
}

private func failureToken(
    _ result: Result<Program, SceneResolvedMaterialFailure>?
) -> String {
    guard case let .failure(failure)? = result else { return "not-failure" }
    return "\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.slot ?? -1)"
}

private func launchToken(
    template: Template,
    sampler: SceneResolvedMaterialShaderSchema.Sampler,
    states: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
    slot: Int = 0,
    expectedPath: SceneVFSAssetPath = overridePath
) -> String {
    do {
        switch try SceneResolvedMaterialTextureResolver.launchAuthoredReference(
            template: template, sampler: sampler, slot: slot, assetStates: states
        ) {
        case let .selected(reference, _):
            return reference == .asset(expectedPath) ? "selected" : "selected-other"
        case .none: return "none"
        case .deferred: return "deferred"
        }
    } catch let failure as SceneResolvedMaterialFailure {
        return "\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.slot ?? -1)"
    } catch {
        return "unexpected-error"
    }
}

private func productChain(
    device: MTLDevice,
    resourceRoot: URL,
    stockRoot: URL
) -> [String: Any] {
    let shader = contract(default: preservedDefault.value)
    let activeSampler = sampler(shader)!
    let animatedShader = contract(
        default: preservedDefault.value, samplerSlot: 3
    )
    let animatedSampler = sampler(animatedShader, slot: 3)!
    let staticTemplate = template(shader)
    let animatedTemplate = template(
        animatedShader, candidatePath: animatedPath, slot: 3
    )
    let staticIdentity = SceneAssetTextureIdentity(
        path: overridePath,
        purpose: activeSampler.purpose(for: .asset(overridePath))!
    )
    let animatedIdentity = SceneAssetTextureIdentity(
        path: animatedPath,
        purpose: animatedSampler.purpose(for: .asset(animatedPath))!
    )
    let defaultIdentity = SceneAssetTextureIdentity(
        path: preservedDefault, purpose: .preservedChannels
    )
    let catalog = SceneMaterialAssetTextureCatalog(
        demands: [staticIdentity, animatedIdentity, defaultIdentity],
        resourceView: SceneResourceView(
            projectRootURL: resourceRoot, packageRootURL: nil,
            stockAssetsRootURL: stockRoot
        ),
        descriptor: SceneRenderDescriptor(), device: device
    )
    let provider = catalog.makeFrameProvider()
    let frameStates = provider.states(sceneTime: 0)
    let laterStates = provider.states(sceneTime: 0.02)
    guard case let .ready(staticPublication)? = frameStates[staticIdentity],
          case let .ready(animatedPublication)? = frameStates[animatedIdentity],
          case let .ready(laterAnimatedPublication)? = laterStates[animatedIdentity],
          case .ready? = frameStates[defaultIdentity] else {
        return ["catalogStates": false]
    }
    let finalized = cache(staticTemplate, purpose: .preservedChannels).flatMap { cache in
        finalize(
            staticTemplate, cache: cache,
            entries: [.asset(staticIdentity): .ready(.init(
                publication: staticPublication, resourceGeneration: 1
            ))]
        )
    }
    let programIdentity: Bool = if case let .success(program)? = finalized {
        program.textureSlots[0]?.reference == .asset(overridePath)
            && program.textureSlots[0]?.expectedPurpose == .preservedChannels
            && program.exactIdentity.textureSlots[0]?.reference == .asset(overridePath)
            && program.exactIdentity.textureSlots[0]?.purpose == .preservedChannels
    } else { false }
    let animatedCache = cache(
        animatedTemplate,
        purpose: animatedIdentity.purpose,
        path: animatedPath
    )
    func animatedProgram(
        _ publication: SceneTextureProviderPublication
    ) -> (Program?, String) {
        guard let animatedCache else { return (nil, "cache") }
        let result = finalize(
            animatedTemplate,
            cache: animatedCache,
            entries: [.asset(animatedIdentity): .ready(.init(
                publication: publication,
                resourceGeneration: publication.contentGeneration
            ))]
        )
        guard case let .success(program)? = result else {
            return (nil, failureToken(result))
        }
        return (program, "not-failure")
    }
    let (animatedFrame0, animatedFailure) = animatedProgram(animatedPublication)
    let (animatedLater, _) = animatedProgram(laterAnimatedPublication)
    return [
        "catalogStates": frameStates.count == 3,
        "staticPublication": staticPublication.isComplete
            && staticPublication.requestIdentity == .asset(staticIdentity)
            && staticPublication.candidate.purpose == .preservedChannels
            && staticPublication.candidate.content == .data,
        "staticSelection": launchToken(
            template: staticTemplate, sampler: activeSampler,
            states: catalog.launchStates
        ) == "selected",
        "staticProgramIdentity": programIdentity,
        "animatedPublication": animatedPublication.isComplete
            && animatedPublication.requestIdentity == .asset(animatedIdentity)
            && animatedPublication.candidate.purpose == animatedIdentity.purpose,
        "animatedSelection": launchToken(
            template: animatedTemplate, sampler: animatedSampler,
            states: catalog.launchStates, slot: 3, expectedPath: animatedPath
        ) == "selected",
        "animatedProgramIdentity": animatedFrame0?.textureSlots[3]?
                .registryIdentity == .asset(animatedIdentity)
            && animatedFrame0?.exactIdentity.textureSlots[3]?.uvBitPatterns
                == [
                    animatedPublication.candidate.uvTransform.origin.x.bitPattern,
                    animatedPublication.candidate.uvTransform.origin.y.bitPattern,
                    animatedPublication.candidate.uvTransform.xAxis.x.bitPattern,
                    animatedPublication.candidate.uvTransform.xAxis.y.bitPattern,
                    animatedPublication.candidate.uvTransform.yAxis.x.bitPattern,
                    animatedPublication.candidate.uvTransform.yAxis.y.bitPattern,
                ]
            && animatedFrame0?.semanticIdentity
                == animatedLater?.semanticIdentity
            && animatedFrame0?.exactIdentity != animatedLater?.exactIdentity
            && animatedFrame0?.uniformBytes != animatedLater?.uniformBytes,
        "animatedFailure": animatedFailure,
    ]
}

@main
private enum Main {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print(#"{"metalAvailable":false}"#); return
        }
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "fixture", code: 2)
        }
        let resourceRoot = URL(
            fileURLWithPath: CommandLine.arguments[1], isDirectory: true
        )
        let stockRoot = URL(
            fileURLWithPath: CommandLine.arguments[2], isDirectory: true
        )
        let sharedTexture = texture(device)
        let preserved = program(
            device, defaultPath: preservedDefault,
            purpose: .preservedChannels, sharedTexture: sharedTexture
        )
        let preserved2 = program(
            device, defaultPath: preservedDefault2,
            purpose: .preservedChannels, sharedTexture: sharedTexture
        )
        let noise = program(
            device, defaultPath: noiseDefault,
            purpose: .noise, sharedTexture: sharedTexture
        )
        guard let preserved, let preserved2, let noise,
              let preservedSlot = preserved.textureSlots[0],
              let preservedExact = preserved.exactIdentity.textureSlots[0],
              let preserved2Exact = preserved2.exactIdentity.textureSlots[0],
              let noiseExact = noise.exactIdentity.textureSlots[0] else {
            throw NSError(
                domain: "fixture", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "programs=\(preserved != nil),\(preserved2 != nil),\(noise != nil)"]
            )
        }

        let conflictShader = contract(default: preservedDefault.value)
        let conflictSampler = sampler(conflictShader)!
        let conflictReference = Template.TextureReference.asset(noiseDefault)
        let conflictTemplate = template(conflictShader)
        var conflictSlots = conflictTemplate.textureSlots
        conflictSlots[0] = .init(index: 0, candidates: [
            .init(reference: conflictReference, provenance: .explicitBinding),
        ])
        let conflictLaunchTemplate = Template.validated(
            textureSlots: conflictSlots, combos: conflictTemplate.combos,
            uniformDeclarations: conflictTemplate.uniformDeclarations,
            renderState: conflictTemplate.renderState,
            graphRole: conflictTemplate.graphRole,
            shaderContract: conflictTemplate.shaderContract,
            diagnosticProvenance: conflictTemplate.diagnosticProvenance
        )!
        let untypedShader = contract(default: "fixtures/untyped-default")
        let untypedSampler = sampler(untypedShader)!
        let internalSampler = sampler(contract(default: "_rt_fixture"))!
        let inactiveShader = contract(default: preservedDefault.value, active: false)
        let inactiveTemplate = template(inactiveShader)
        let inactivePrepared = SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: inactiveShader, combos: [:], textureReadiness: [0: true]
        )
        let inactiveActiveCount: Int = if case let .accepted(prepared) = inactivePrepared {
            try SceneResolvedMaterialShaderSchema.activeSamplers(prepared).count
        } else { -1 }
        let inactiveReachable = try SceneResolvedMaterialShaderSchema.reachableSamplers(
            inactiveTemplate, implicitFramebufferIdentity: nil
        )[0]?.count ?? 0

        let positiveTemplate = template(contract(default: preservedDefault.value))
        let positiveCache = cache(positiveTemplate, purpose: .preservedChannels)!
        let candidateIdentity = SceneAssetTextureIdentity(
            path: overridePath, purpose: .preservedChannels
        )
        let defaultIdentity = SceneAssetTextureIdentity(
            path: preservedDefault, purpose: .preservedChannels
        )
        let defaultReady = ready(
            device, request: .asset(defaultIdentity), purpose: .preservedChannels
        )
        func failure(_ status: SceneFrameTextureLookupStatus?) -> String {
            var entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [
                .asset(defaultIdentity): defaultReady,
            ]
            if let status { entries[.asset(candidateIdentity)] = status }
            return failureToken(finalize(
                positiveTemplate, cache: positiveCache, entries: entries
            ))
        }
        let wrongRequest = SceneFrameTextureIdentity.asset(.init(
            path: preservedDefault, purpose: .preservedChannels
        ))
        let results: [String: Any] = [
            "metalAvailable": true,
            "positive": [
                "reference": preservedExact.reference == .asset(overridePath),
                "slotReference": preservedSlot.reference == .asset(overridePath),
                "slotPurpose": preservedSlot.expectedPurpose == .preservedChannels,
                "registryIdentity": preservedSlot.registryIdentity
                    == .asset(candidateIdentity),
                "demandIdentity": SceneAssetTextureIdentity(
                    path: overridePath,
                    purpose: sampler(contract(default: preservedDefault.value))!
                        .purpose(for: .asset(overridePath))!
                ) == candidateIdentity,
                "semanticPurpose": preserved.semanticIdentity.textureSlots[0]?.purpose
                    == .preservedChannels,
                "exactPurpose": preservedExact.purpose == .preservedChannels,
                "selectionAuthored": preservedSlot.diagnosticSelectionProvenance
                    == .authored(.explicitBinding),
            ],
            "identity": [
                "sameRoleSameTexture": preservedExact == preserved2Exact,
                "defaultChangeChangesProgram": preserved.exactIdentity
                    != preserved2.exactIdentity,
                "roleChangeChangesTexture": preservedExact != noiseExact,
                "roleChangeChangesSemantic": preserved.semanticIdentity
                    != noise.semanticIdentity,
            ],
            "purposeBoundaries": [
                "conflict": conflictSampler.purpose(for: conflictReference) == nil,
                "conflictTypedReject": launchFailure(conflictLaunchTemplate),
                "untyped": untypedSampler.purpose(for: .asset(overridePath)) == nil,
                "untypedTypedReject": launchFailure(template(untypedShader)),
                "internal": internalSampler.purpose(for: .asset(overridePath)) == nil,
                "inactiveActiveCount": inactiveActiveCount,
                "inactiveReachableCount": inactiveReachable,
            ],
            "noFallback": [
                "pending": failure(.pending),
                "missing": failure(nil),
                "unavailable": failure(.unavailable),
                "wrongPurpose": failure(ready(
                    device, request: .asset(candidateIdentity),
                    purpose: .preservedChannels, candidatePurpose: .noise
                )),
                "wrongPublication": failure(ready(
                    device, request: .asset(candidateIdentity),
                    purpose: .preservedChannels, requestOverride: wrongRequest
                )),
                "wrongGeneration": failure(ready(
                    device, request: .asset(candidateIdentity),
                    purpose: .preservedChannels, generationMismatch: true
                )),
            ],
            "productChain": productChain(
                device: device, resourceRoot: resourceRoot, stockRoot: stockRoot
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSamplerDefaultPurposeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-sampler-default-purpose-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "sampler-default-purpose-test"
        resources = root / "resources"
        static_texture = resources / "fixtures/unseen/static-authored.png"
        animated_texture = resources / "particle/fog/fog2.tex"
        static_texture.parent.mkdir(parents=True)
        animated_texture.parent.mkdir(parents=True)
        shutil.copyfile(
            REPOSITORY_ROOT / (
                "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/"
                "materials/editor/testusertexture.png"
            ),
            static_texture,
        )
        shutil.copyfile(
            REPOSITORY_ROOT / (
                "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/"
                "materials/particle/fog/fog2.tex"
            ),
            animated_texture,
        )
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support), *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO", "-module-cache-path",
                str(root / "module-cache"), "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT, env=environment, capture_output=True, text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [
                str(binary), str(resources),
                str(REPOSITORY_ROOT / (
                    "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
                )),
            ],
            cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_inherited_purpose_reaches_selection_and_program_identity(self) -> None:
        self.assertEqual(
            [key for key, value in self.result["positive"].items() if not value],
            [], self.result,
        )
        self.assertEqual(
            [key for key, value in self.result["identity"].items() if not value],
            [], self.result,
        )

    def test_conflict_untyped_internal_and_inactive_stay_unproven(self) -> None:
        self.assertEqual(
            self.result["purposeBoundaries"],
            {
                "conflict": True, "untyped": True, "internal": True,
                "conflictTypedReject": "texture/textureBindingInvalid/0",
                "untypedTypedReject": "texture/texturePurposeUnproven/0",
                "inactiveActiveCount": 0, "inactiveReachableCount": 0,
            },
            self.result,
        )

    def test_unready_or_invalid_candidate_never_falls_back_to_default(self) -> None:
        self.assertEqual(
            self.result["noFallback"],
            {
                "pending": "texture/resourceSnapshotUnresolved/0",
                "missing": "texture/resourceSnapshotUnresolved/0",
                "unavailable": "texture/resourceSnapshotUnresolved/0",
                "wrongPurpose": "texture/textureMetadataIncomplete/0",
                "wrongPublication": "texture/textureMetadataIncomplete/0",
                "wrongGeneration": "texture/textureMetadataIncomplete/0",
            },
            self.result,
        )

    def test_product_asset_catalog_preserves_inherited_role_and_readiness(self) -> None:
        self.assertEqual(
            self.result["productChain"],
            {
                "catalogStates": True,
                "staticPublication": True,
                "staticSelection": True,
                "staticProgramIdentity": True,
                "animatedPublication": True,
                "animatedSelection": True,
                "animatedProgramIdentity": True,
                "animatedFailure": "not-failure",
            },
            self.result,
        )


if __name__ == "__main__":
    unittest.main()
