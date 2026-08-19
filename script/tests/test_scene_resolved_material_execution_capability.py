#!/usr/bin/env python3

"""Raw-graph admission gate for the R4 layer capability catalog."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
LAUNCH_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
RENDERER_SOURCE = SCENE_ROOT / "Rendering/SceneMetalRenderer.swift"
ADMISSION_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityAdmission.swift"
)
CAPABILITY_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift"
)
CAPABILITY_STAGES_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift"
)
CAPABILITY_PROGRAM_FIRST_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
VARIANT_CACHE_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialExecutionCapabilityVariant.swift"
)
VARIANT_COMPILATION_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift"
)
GENERIC_SHADER_CACHE_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderArtifactCache.swift"
)
DEPENDENCY_OWNERSHIP_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift"
)
RUNTIME_CATALOG_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialRuntimeCatalog.swift"
)
RUNTIME_CATALOG_REPORT_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialRuntimeCatalog+Report.swift"
)
EFFECT_BACKEND_SOURCE = (
    SCENE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageExecutionPlan+Backend.swift"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneGraphConditionAdmission.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneGraphAdmissionCompiler.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneLayerFullFramePairPlan.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenResolutionPolicy.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialAttachmentKind.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Material.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift",
    CAPABILITY_PROGRAM_FIRST_SOURCE,
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityTemplateAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+EnvelopeDiagnostics.swift",
]

PROGRAM_FINALIZER_TEST_SOURCE = (
    REPOSITORY_ROOT
    / "script/tests/test_scene_resolved_material_program_finalizer.py"
)
PROGRAM_FINALIZER_FIXTURE = runpy.run_path(
    str(PROGRAM_FINALIZER_TEST_SOURCE)
)
ENVELOPE_SWIFT_SOURCES = [
    *PROGRAM_FINALIZER_FIXTURE["SWIFT_SOURCES"],
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialAttachmentKind.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenResolutionPolicy.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Material.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift",
    CAPABILITY_PROGRAM_FIRST_SOURCE,
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityTemplateAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+EnvelopeDiagnostics.swift",
]
CATALOG_DEMAND_SWIFT_SOURCES = [
    *PROGRAM_FINALIZER_FIXTURE["SWIFT_SOURCES"],
    RUNTIME_CATALOG_SOURCE,
    RUNTIME_CATALOG_REPORT_SOURCE,
]


SUPPORT = r'''
import Foundation

enum SceneShaderTextureFormat { case r8 }

struct SceneAssetTextureIdentity: Hashable {}
enum SceneTextureContent: Hashable {}
enum SceneAssetTextureLaunchState: Hashable {
    case ready(SceneTextureContent)
    case absent
    case pending
    case unavailable
}

struct SceneEffectDefinition {
    let relativePath: String
    let functions: SceneJSONValue?
}

struct SceneEffectExactRuntimeSubject: Hashable {
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let family: String
}

struct SceneEffectStageProgram {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let stageGraph: SceneAuthoredEffectRenderPlan
    let executionPlan: SceneEffectStageExecutionPlan
    var inputRole: SceneAuthoredEffectInputRole { executionPlan.inputRole }
}

struct SceneUtilityLayer {
    enum Kind: String { case composition, project, fullscreen }
    let kind: Kind
}

struct SceneRenderDescriptor {
    struct PassDescriptor {
        let passIndex: Int
        let combos: [String: Int]
    }

    struct EffectDescriptor {
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
        var contentKind = "image"
        var utilityLayer: SceneUtilityLayer? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var parentID: Int? = nil
        var visible: Bool? = true
        var namedReferences: [SceneDependencyRenderPlan.Reference] = []
        var namedBindings: [SceneDependencyRenderPlan.Binding] = []
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let combos: [String: Int]
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map {
            ($0.id, $0)
        })
        return Set(descriptor.layers.compactMap { layer in
            var current: SceneRenderDescriptor.Layer? = layer
            var visited = Set<Int>()
            while let candidate = current {
                guard candidate.visible != false,
                      visited.insert(candidate.id).inserted else { return nil }
                current = candidate.parentID.flatMap { byID[$0] }
            }
            return layer.id
        })
    }
}

struct SceneDependencyRenderPlan {
    struct Reference: Hashable {
        enum Variant: Hashable { case primary, secondary, unspecified }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: Variant
    }

    struct Binding: Hashable {
        enum Kind: Hashable {
            case resolvedMaterial
            case proceduralNoiseLayer
            case imageLayerBlend
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
        }
    }

    let references: [Reference]
    let namedReferenceConsumerLayerIDs: Set<Int>
    let bindingsByConsumerLayerID: [Int: Binding]

    init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int> = []
    ) {
        references = descriptor.layers.flatMap(\.namedReferences)
        namedReferenceConsumerLayerIDs = Set(references.compactMap {
            visibleLayerIDs.contains($0.consumerLayerID) ? $0.consumerLayerID : nil
        })
        var bindings: [Int: Binding] = [:]
        for layer in descriptor.layers where visibleLayerIDs.contains(layer.id) {
            guard layer.utilityLayer == nil
                    || executableUtilityConsumerLayerIDs.contains(layer.id) else {
                continue
            }
            let matches = layer.namedBindings.filter {
                $0.consumerLayerID == layer.id
            }
            if matches.count == 1 {
                bindings[layer.id] = matches[0]
            }
        }
        bindingsByConsumerLayerID = bindings
    }
}

struct SceneEffectPassSlot: Hashable {
    let effectID: String
    let passIndex: Int
    let slotIndex: Int
}

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}
struct SceneDepthParallaxExecutionPlan {}
struct SceneXRayExecutionPlan {}

struct SceneOpacityExecutionPlan {}
struct SceneProceduralNoiseExecutionPlan {
    enum Variant { case colorPerlinRGB, worleyColorV1 }

    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let variant: Variant
    let dependencyProviderLayerID: Int?
    let dependencySlotIndex: Int?
}
struct SceneBlendExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let dependencyProviderLayerID: Int?
}
struct HarnessDedicatedAudioExecutionPlan { let audio: Bool? }

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let cursorRipple: SceneCursorRippleExecutionPlan?
    let opacity: SceneOpacityExecutionPlan?
    var depthParallax: SceneDepthParallaxExecutionPlan? = nil
    var xRay: SceneXRayExecutionPlan? = nil
    var proceduralNoise: SceneProceduralNoiseExecutionPlan? = nil
    var blend: SceneBlendExecutionPlan? = nil
    var supportsUnifiedLogicalTargetStage = false
    var supportsUnifiedHistoryTargetStage = false
    var supportsUnifiedFullFrameComposeStage = false
    var supportsUtilityCapture = true
    var shake: HarnessDedicatedAudioExecutionPlan? { nil }
    var pulse: HarnessDedicatedAudioExecutionPlan? { nil }
    var workshopAudioBars: SceneOpacityExecutionPlan? { nil }
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

enum SceneGraphExecutionState {
    static let maximumNodeCount = 1_024
    static let maximumLogicalBindingCount = 256
}

enum SceneDynamicTarget: Hashable {
    case effectConstant(
        layerID: Int,
        effectIndex: Int,
        passIndex: Int,
        name: String
    )
}

indirect enum SceneShaderAnnotationValue {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([SceneShaderAnnotationValue])
    case object([String: SceneShaderAnnotationValue])
}

struct SceneNamedTextureReference {
    enum Variant { case primary, secondary, unspecified }
    let providerLayerID: Int
    let variant: Variant
}

struct SceneResolvedMaterialTemplate {
    enum GraphTextureRole: String, Hashable {
        case layerSource
        case effectOutput
        case framebuffer
        case unresolved
    }

    struct GraphBindingRole: Hashable {
        let slot: Int
        let texture: GraphTextureRole
    }

    struct GraphRole: Hashable {
        let effectInput: GraphTextureRole
        let effectOutput: GraphTextureRole
        let nodeTarget: GraphTextureRole
        let bindings: [GraphBindingRole]
    }

    struct DiagnosticProvenance {
        let nodeIndex: Int
    }

    enum KnownProviderRequest {
        case system(String)
        case namedLayerTarget(SceneNamedTextureReference), sceneBackground(consumerLayerID: Int)
    }

    enum TextureReference {
        case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
        case asset(String)
        case provider(KnownProviderRequest)
        case internalTarget(String)
    }

    struct TextureCandidate {
        let reference: TextureReference
    }

    struct TextureSlot {
        let index: Int
        let candidates: [TextureCandidate]

        init(index: Int = 0, candidates: [TextureCandidate]) {
            self.index = index
            self.candidates = candidates
        }
    }

    enum DynamicUniformSource: Hashable {
        case userProperty(String)
        case timeline
        case sceneScript
    }

    enum DynamicUniformScriptAttachment: Hashable {
        case mediaThumbnailAnimationRestart
        case unproven
    }

    struct StaticUniformValue {}

    struct DynamicUniform {
        let target: SceneDynamicTarget
        let valueContributors: [DynamicUniformSource]
        let scriptAttachments: [DynamicUniformScriptAttachment]
        let authoredFallback: StaticUniformValue?
    }

    enum UniformValue {
        case staticExact
        case dynamic(DynamicUniform)
    }

    struct UniformDeclaration {
        let name: String
        let value: UniformValue
    }

    struct RenderState {
        let overwrite: Bool

        func matchesFullscreenOverwrite(alphaWriting: AlphaWriting) -> Bool {
            _ = alphaWriting
            return overwrite
        }
    }

    enum AlphaWriting { case unspecified }

    struct Annotation {
        let marker: String?
        let variantValue: SceneShaderAnnotationValue
    }

    struct ShaderStage {
        let annotations: [Annotation]
    }

    struct ShaderContract {
        let stages: [ShaderStage]
    }

    let diagnosticProvenance: DiagnosticProvenance
    let graphRole: GraphRole
    let textureSlots: [TextureSlot?]
    let uniformDeclarations: [UniformDeclaration]
    let renderState: RenderState
    let shaderContract: ShaderContract
}

enum SceneResolvedMaterialShaderSchema {
    struct Sampler {
        let defaultTexture: SceneResolvedMaterialTemplate.TextureReference?
    }

    static func unconditionalSamplers(
        _ template: SceneResolvedMaterialTemplate
    ) throws -> [Int: Sampler] {
        _ = template
        return [:]
    }
}

struct SceneResolvedMaterialFailure: Error {
    let boundedDetails: [String] = []
}

struct SceneResolvedMaterialRuntimeCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct Key: Hashable {
        let effect: Graph.EffectKey
        let nodeIndex: Int
    }

    enum Entry {
        case template(SceneResolvedMaterialTemplate)
        case failure(SceneResolvedMaterialFailure)
    }

    struct ResourceDemandIssue: Hashable {
        let key: Key
        let slot: Int
    }

    let entries: [Key: Entry]
    let resourceDemandIssues: Set<ResourceDemandIssue>

    func entry(for node: Graph.Node) -> Entry? {
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)]
    }

    func admittedEntry(
        for node: Graph.Node,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Entry? {
        _ = graph
        _ = descriptor
        return entry(for: node)
    }
}

final class SceneResolvedMaterialVariantCache {
    enum OutputStorage { case color, scalarRedUnorm }

    enum LaunchEnvelopeFailure: Error {
        enum Kind: String { case capacity, invariant }
        case capacity
        case material(SceneResolvedMaterialFailure)

        var kind: Kind {
            switch self {
            case .capacity: .capacity
            case .material: .invariant
            }
        }
    }

    private let audioSpectrumConsumer: Bool
    private let capturedMainTargetTextureSupport: Bool

    init?(
        template: SceneResolvedMaterialTemplate,
        maximumVariantCount: Int,
        assetFormatFacts: [String: Int] = [:]
    ) {
        _ = assetFormatFacts
        guard (1 ... 256).contains(maximumVariantCount) else { return nil }
        audioSpectrumConsumer = template.uniformDeclarations.contains {
            $0.name.hasPrefix("g_AudioSpectrum")
        }
        capturedMainTargetTextureSupport =
            template.graphRole.effectInput == .layerSource
                && template.graphRole.bindings.count == 1
                && template.graphRole.bindings[0].texture == .layerSource
    }

    static func launchValidated(
        template: SceneResolvedMaterialTemplate,
        maximumVariantCount: Int,
        assetFormatFacts: [String: Int] = [:]
    ) -> Result<SceneResolvedMaterialVariantCache, SceneResolvedMaterialFailure> {
        guard let cache = SceneResolvedMaterialVariantCache(
            template: template,
            maximumVariantCount: maximumVariantCount,
            assetFormatFacts: assetFormatFacts
        ) else { return .failure(.init()) }
        return .success(cache)
    }

    func precompileLaunchEnvelope(
        implicitFramebufferIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity?,
        outputStorage: OutputStorage = .color,
        graphTextureFormatFacts: [
            SceneAuthoredEffectRenderPlan.TextureIdentity: SceneShaderTextureFormat
        ] = [:],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:]
    ) -> Result<[UInt8], LaunchEnvelopeFailure> {
        _ = implicitFramebufferIdentity
        _ = outputStorage
        _ = graphTextureFormatFacts
        _ = assetStates
        return .success([1])
    }

    var supportsTransparentDirectDraw: Bool { true }
    var launchEnvelopeActiveTextureSlots: Set<Int>? { [0] }
    var hasAudioSpectrumConsumer: Bool { audioSpectrumConsumer }
    var supportsCapturedMainTargetTexture: Bool {
        capturedMainTargetTextureSupport
    }
    var requiresInvertibleEffectTextureProjection: Bool { false }
    func provesRedOnlyConsumer(slot: Int) -> Bool {
        _ = slot
        return false
    }
}
'''


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Catalog = SceneResolvedMaterialExecutionCapabilityCatalog
private typealias Template = SceneResolvedMaterialTemplate

private let layerID = 880
private let providerLayerID = 879

private func key(_ index: Int, _ id: String) -> Graph.EffectKey {
    .init(layerID: layerID, effectIndex: index, descriptorID: id)
}

private let firstKey = key(0, "first-active")
private let secondKey = key(2, "second-active")
private let thirdKey = key(3, "third-active")
private let fourthKey = key(4, "fourth-active")

private func source() -> Graph.TextureIdentity {
    SceneAuthoredEffectInputValidator.layerSource(layerID: layerID)
}

private func output(_ key: Graph.EffectKey) -> Graph.TextureIdentity {
    .init(kind: .effectOutput, layerID: layerID, effect: key, name: nil)
}

private func framebuffer(
    _ key: Graph.EffectKey,
    _ name: String
) -> Graph.TextureIdentity {
    .init(kind: .framebuffer, layerID: layerID, effect: key, name: name)
}

private func target(
    _ identity: Graph.TextureIdentity,
    condition: SceneJSONValue? = nil,
    unique: Bool = false
) -> Graph.RenderTarget {
    .init(
        texture: identity,
        extent: .init(width: nil, height: nil, fit: nil, scale: nil),
        format: "rgba_backbuffer",
        declaredUnique: unique,
        clear: nil,
        uvs: nil,
        conditions: condition
    )
}

private func logicalTargetGraph(unique: Bool = false) -> Graph {
    let graphInput = source()
    let intermediate = framebuffer(firstKey, "precise-intermediate")
    let graphOutput = output(firstKey)
    let horizontal = material(
        index: 0,
        ordinal: 0,
        effect: firstKey,
        target: intermediate,
        input: graphInput
    )
    let vertical = material(
        index: 1,
        ordinal: 1,
        effect: firstKey,
        target: graphOutput,
        input: intermediate
    )
    return .init(
        layerID: layerID,
        effects: [.init(
            key: firstKey,
            definitionPath: "effects/blurprecise/effect.json",
            input: graphInput,
            output: graphOutput,
            nodeIndices: [0, 1]
        )],
        renderTargets: [target(intermediate, unique: unique)],
        nodes: [horizontal, vertical],
        finalOutput: graphOutput,
        blockers: []
    )
}

private func logicalTargetDescriptor(
    capturedMain: Bool = false
) -> SceneRenderDescriptor {
    .init(
        layers: [.init(
            id: layerID,
            effects: [.init(
                id: firstKey.descriptorID,
                file: "effects/blurprecise/effect.json",
                visible: true,
                passes: [
                    .init(passIndex: 0, combos: [:]),
                    .init(passIndex: 1, combos: [:]),
                ]
            )],
            contentKind: capturedMain ? "composition" : "image",
            utilityLayer: capturedMain ? .init(kind: .composition) : nil
        )],
        materialPasses: [
            .init(id: "m0", materialPath: "materials/m0.json", combos: [:]),
            .init(id: "m1", materialPath: "materials/m1.json", combos: [:]),
        ],
        effectDefinitions: [.init(
            relativePath: "effects/blurprecise/effect.json",
            functions: nil
        )]
    )
}

private func fullFrameComposeGraph(
    compose: SceneJSONValue? = .bool(true),
    includeHistory: Bool = false,
    includeThirdNode: Bool = false
) -> Graph {
    let graphInput = source()
    let graphOutput = output(firstKey)
    let history = framebuffer(firstKey, "compose-history")
    func node(
        _ index: Int,
        compose: SceneJSONValue?,
        bindings: [Graph.Binding] = []
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: firstKey,
            definitionPassIndex: index,
            materialOrdinal: index,
            instancePassIndex: index,
            kind: .material,
            materialPath: "materials/m\(index).json",
            materialPassID: "m\(index)",
            target: graphOutput,
            bindings: bindings,
            commandSource: nil,
            commandTarget: nil,
            compose: compose,
            conditions: nil
        )
    }
    var nodes = [
        node(0, compose: compose),
        node(1, compose: nil, bindings: includeHistory ? [binding(history)] : []),
    ]
    if includeThirdNode {
        nodes.append(node(2, compose: nil))
    }
    return .init(
        layerID: layerID,
        effects: [.init(
            key: firstKey,
            definitionPath: "effects/blurprecise/effect.json",
            input: graphInput,
            output: graphOutput,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: includeHistory ? [target(history, unique: true)] : [],
        nodes: nodes,
        finalOutput: graphOutput,
        blockers: []
    )
}

private func fullFrameComposeDescriptor(
    capturedMain: Bool = false,
    passCount: Int = 2
) -> SceneRenderDescriptor {
    .init(
        layers: [.init(
            id: layerID,
            effects: [.init(
                id: firstKey.descriptorID,
                file: "effects/blurprecise/effect.json",
                visible: true,
                passes: (0 ..< passCount).map {
                    .init(passIndex: $0, combos: [:])
                }
            )],
            contentKind: capturedMain ? "composition" : "image",
            utilityLayer: capturedMain ? .init(kind: .composition) : nil
        )],
        materialPasses: (0 ..< passCount).map {
            .init(id: "m\($0)", materialPath: "materials/m\($0).json", combos: [:])
        },
        effectDefinitions: [.init(
            relativePath: "effects/blurprecise/effect.json",
            functions: nil
        )]
    )
}

private func condition(_ name: String, _ value: Double) -> SceneJSONValue {
    .array([.object([name: .number(value)])])
}

private func binding(_ identity: Graph.TextureIdentity) -> Graph.Binding {
    .init(
        slot: 0,
        authoredName: identity.name ?? "previous",
        texture: identity,
        conditions: nil
    )
}

private func namedReference(
    effectID: String = "second-active",
    providerLayerID: Int = layerID,
    passIndex: Int = 0,
    slotIndex: Int = 0,
    variant: SceneDependencyRenderPlan.Reference.Variant = .primary
) -> SceneDependencyRenderPlan.Reference {
    .init(
        consumerLayerID: layerID,
        providerLayerID: providerLayerID,
        slot: .init(
            effectID: effectID,
            passIndex: passIndex,
            slotIndex: slotIndex
        ),
        variant: variant
    )
}

private func dependencyBinding(
    effectID: String = "first-active",
    providerLayerID: Int,
    passIndex: Int = 0,
    slotIndex: Int = 1,
    referenceSlots: [SceneEffectPassSlot]? = nil,
    blendMode: Int = 0,
    kind: SceneDependencyRenderPlan.Binding.Kind = .resolvedMaterial
) -> SceneDependencyRenderPlan.Binding {
    .init(
        consumerLayerID: layerID,
        providerLayerID: providerLayerID,
        slot: .init(
            effectID: effectID,
            passIndex: passIndex,
            slotIndex: slotIndex
        ),
        referenceSlots: referenceSlots,
        blendMode: blendMode,
        kind: kind
    )
}

private func material(
    index: Int,
    ordinal: Int,
    effect: Graph.EffectKey,
    target: Graph.TextureIdentity,
    input: Graph.TextureIdentity,
    compose: SceneJSONValue? = nil,
    passCondition: SceneJSONValue? = nil
) -> Graph.Node {
    .init(
        nodeIndex: index,
        effect: effect,
        definitionPassIndex: ordinal,
        materialOrdinal: ordinal,
        instancePassIndex: ordinal,
        kind: .material,
        materialPath: "materials/m\(index).json",
        materialPassID: "m\(index)",
        target: target,
        bindings: [binding(input)],
        commandSource: nil,
        commandTarget: nil,
        compose: compose,
        conditions: passCondition
    )
}

private func blocker(
    _ key: Graph.EffectKey,
    _ reason: Graph.BlockerReason
) -> Graph.Blocker {
    .init(
        effect: key,
        definitionPassIndex: nil,
        reason: reason,
        detail: reason.rawValue
    )
}

private func rawGraph(
    discontinuous: Bool = false,
    unresolvedCondition: Bool = false,
    omitSecond: Bool = false,
    includeFunctionBlocker: Bool = false
) -> Graph {
    let firstInput = source()
    let firstOutput = output(firstKey)
    let history = framebuffer(firstKey, "history")
    let scratch = framebuffer(firstKey, "scratch")
    let conditionName = unresolvedCondition ? "UNKNOWN" : "MODE"
    let conditionValue = unresolvedCondition ? 1.0 : 0.0
    let firstNodes = [
        material(
            index: 0,
            ordinal: 0,
            effect: firstKey,
            target: history,
            input: firstInput
        ),
        material(
            index: 1,
            ordinal: 1,
            effect: firstKey,
            target: scratch,
            input: firstInput,
            passCondition: condition(conditionName, conditionValue)
        ),
        material(
            index: 2,
            ordinal: 2,
            effect: firstKey,
            target: firstOutput,
            input: firstInput,
            compose: .bool(true)
        ),
        material(
            index: 3,
            ordinal: 3,
            effect: firstKey,
            target: firstOutput,
            input: firstInput
        ),
    ]
    let firstEffect = Graph.Effect(
        key: firstKey,
        definitionPath: "effects/first/effect.json",
        input: firstInput,
        output: firstOutput,
        nodeIndices: firstNodes.map(\.nodeIndex)
    )
    guard !omitSecond else {
        return .init(
            layerID: layerID,
            effects: [firstEffect],
            renderTargets: [
                target(history),
                target(scratch, condition: condition(conditionName, conditionValue)),
            ],
            nodes: firstNodes,
            finalOutput: firstOutput,
            blockers: [
                blocker(firstKey, .unsupportedCondition),
                blocker(firstKey, .unsupportedCompose),
                blocker(firstKey, .multipleEffectOutputs),
            ] + (includeFunctionBlocker ? [
                blocker(firstKey, .unsupportedFunctions),
            ] : [])
        )
    }
    let secondInput = discontinuous ? source() : firstOutput
    let secondOutput = output(secondKey)
    let secondNode = material(
        index: 4,
        ordinal: 0,
        effect: secondKey,
        target: secondOutput,
        input: secondInput
    )
    return .init(
        layerID: layerID,
        effects: [
            firstEffect,
            .init(
                key: secondKey,
                definitionPath: "effects/second/effect.json",
                input: secondInput,
                output: secondOutput,
                nodeIndices: [secondNode.nodeIndex]
            ),
        ],
        renderTargets: [
            target(history),
            target(scratch, condition: condition(conditionName, conditionValue)),
        ],
        nodes: firstNodes + [secondNode],
        finalOutput: secondOutput,
        blockers: [
            blocker(firstKey, .unsupportedCondition),
            blocker(firstKey, .unsupportedCompose),
            blocker(firstKey, .multipleEffectOutputs),
        ] + (includeFunctionBlocker ? [
            blocker(firstKey, .unsupportedFunctions),
        ] : [])
    )
}

private func pairOnlyGraph() -> Graph {
    let firstInput = source()
    let firstOutput = output(firstKey)
    let secondOutput = output(secondKey)
    let firstNode = material(
        index: 0,
        ordinal: 0,
        effect: firstKey,
        target: firstOutput,
        input: firstInput
    )
    let secondNode = material(
        index: 1,
        ordinal: 0,
        effect: secondKey,
        target: secondOutput,
        input: firstOutput
    )
    return .init(
        layerID: layerID,
        effects: [
            .init(
                key: firstKey,
                definitionPath: "effects/first/effect.json",
                input: firstInput,
                output: firstOutput,
                nodeIndices: [firstNode.nodeIndex]
            ),
            .init(
                key: secondKey,
                definitionPath: "effects/second/effect.json",
                input: firstOutput,
                output: secondOutput,
                nodeIndices: [secondNode.nodeIndex]
            ),
        ],
        renderTargets: [],
        nodes: [firstNode, secondNode],
        finalOutput: secondOutput,
        blockers: []
    )
}

private func pairOnlyDescriptor() -> SceneRenderDescriptor {
    .init(
        layers: [.init(
            id: layerID,
            effects: [
                .init(
                    id: firstKey.descriptorID,
                    file: "effects/first/effect.json",
                    visible: true,
                    passes: [.init(passIndex: 0, combos: [:])]
                ),
                .init(
                    id: "hidden-middle",
                    file: "effects/hidden/effect.json",
                    visible: false,
                    passes: []
                ),
                .init(
                    id: secondKey.descriptorID,
                    file: "effects/second/effect.json",
                    visible: true,
                    passes: [.init(passIndex: 0, combos: [:])]
                ),
            ]
        )],
        materialPasses: [
            .init(id: "m0", materialPath: "materials/m0.json", combos: [:]),
            .init(id: "m1", materialPath: "materials/m1.json", combos: [:]),
        ],
        effectDefinitions: [
            .init(relativePath: "effects/first/effect.json", functions: nil),
            .init(relativePath: "effects/second/effect.json", functions: nil),
        ]
    )
}

private func externalResolvedMaterialGraph(includeOpacity: Bool = false) -> Graph {
    let pair = pairOnlyGraph()
    guard !includeOpacity else { return pair }
    let effect = pair.effects[0]
    let node = pair.nodes[0]
    return .init(
        layerID: layerID,
        effects: [effect],
        renderTargets: [],
        nodes: [node],
        finalOutput: effect.output,
        blockers: []
    )
}

private func externalProceduralGraph() -> Graph {
    let base = externalResolvedMaterialGraph()
    let effect = base.effects[0]
    return .init(
        layerID: base.layerID,
        effects: [.init(
            key: effect.key,
            definitionPath: "effects/workshop/2924967132/procedural_noise/effect.json",
            input: effect.input,
            output: effect.output,
            nodeIndices: effect.nodeIndices
        )],
        renderTargets: base.renderTargets,
        nodes: base.nodes,
        finalOutput: base.finalOutput,
        blockers: base.blockers
    )
}

private func externalResolvedMaterialDescriptor(
    utilityConsumer: Bool = false,
    includeOpacity: Bool = false,
    dependencyLayerIDs: [Int] = [providerLayerID],
    authoredDependencies: [Int] = [],
    references: [SceneDependencyRenderPlan.Reference]? = nil,
    bindings: [SceneDependencyRenderPlan.Binding]? = nil
) -> SceneRenderDescriptor {
    var effects: [SceneRenderDescriptor.EffectDescriptor] = [
        .init(
            id: firstKey.descriptorID,
            file: "effects/first/effect.json",
            visible: true,
            passes: [.init(passIndex: 0, combos: [:])]
        ),
    ]
    if includeOpacity {
        effects.append(.init(
            id: "hidden-middle",
            file: "effects/hidden/effect.json",
            visible: false,
            passes: []
        ))
        effects.append(.init(
            id: secondKey.descriptorID,
            file: "effects/second/effect.json",
            visible: true,
            passes: [.init(passIndex: 0, combos: [:])]
        ))
    }
    return .init(
        layers: [
            .init(
                id: providerLayerID,
                effects: [],
                contentKind: "composition",
                utilityLayer: .init(kind: .composition)
            ),
            .init(
                id: layerID,
                effects: effects,
                contentKind: utilityConsumer ? "composition" : "image",
                utilityLayer: utilityConsumer
                    ? .init(kind: .composition) : nil,
                dependencyLayerIDs: dependencyLayerIDs,
                authoredDependencies: authoredDependencies,
                namedReferences: references ?? [namedReference(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    slotIndex: 1
                )],
                namedBindings: bindings ?? [dependencyBinding(
                    providerLayerID: providerLayerID,
                    referenceSlots: (references ?? [namedReference(
                        effectID: firstKey.descriptorID,
                        providerLayerID: providerLayerID,
                        slotIndex: 1
                    )]).map(\.slot)
                )]
            ),
        ],
        materialPasses: [
            .init(id: "m0", materialPath: "materials/m0.json", combos: [:]),
            .init(id: "m1", materialPath: "materials/m1.json", combos: [:]),
        ],
        effectDefinitions: [
            .init(relativePath: "effects/first/effect.json", functions: nil),
            .init(relativePath: "effects/second/effect.json", functions: nil),
        ]
    )
}

private func externalResolvedMaterialCatalog(
    descriptor: SceneRenderDescriptor,
    graph: Graph,
    programAvailable: Bool = true
) -> Catalog {
    var programs: [SceneEffectStageProgram] = []
    var families: [Graph.EffectKey: String] = [:]
    var leafKeys: Set<Graph.EffectKey> = []
    if graph.effects.count == 2 {
        programs.append(dedicatedProgram(
            graph: graph,
            effectIndex: 1,
            inputRole: .priorEffectOutput,
            opacity: true,
            supportsUtilityCapture: true
        ))
        families[secondKey] = "opacity"
        leafKeys.insert(secondKey)
    }
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [graph],
        dedicatedStagePrograms: programs
    )
    return Catalog(
        admissionCandidates: candidates,
        materialCatalog: materialCatalog(
            graph: graph,
            omitNode: programAvailable ? nil : 0,
            namedProviderByNode: [0: providerLayerID]
        ),
        dedicatedStageFamilies: families,
        dedicatedLeafKeys: leafKeys
    )
}

private func externalProceduralDescriptor(
    dependencyLayerIDs: [Int] = [providerLayerID],
    authoredDependencies: [Int] = [],
    references: [SceneDependencyRenderPlan.Reference]? = nil,
    bindings: [SceneDependencyRenderPlan.Binding]? = nil
) -> SceneRenderDescriptor {
    .init(
        layers: [
            .init(
                id: providerLayerID,
                effects: [],
                contentKind: "solid",
                visible: false
            ),
            .init(
                id: layerID,
                effects: [.init(
                    id: firstKey.descriptorID,
                    file: "effects/workshop/2924967132/procedural_noise/effect.json",
                    visible: true,
                    passes: [.init(passIndex: 0, combos: [:])]
                )],
                contentKind: "composition",
                utilityLayer: .init(kind: .composition),
                dependencyLayerIDs: dependencyLayerIDs,
                authoredDependencies: authoredDependencies,
                namedReferences: references ?? [namedReference(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    slotIndex: 3
                )],
                namedBindings: bindings ?? [dependencyBinding(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    slotIndex: 3,
                    kind: .proceduralNoiseLayer
                )]
            ),
        ],
        materialPasses: [
            .init(id: "m0", materialPath: "materials/m0.json", combos: [:]),
        ],
        effectDefinitions: [
            .init(
                relativePath: "effects/workshop/2924967132/procedural_noise/effect.json",
                functions: nil
            ),
        ]
    )
}

private func proceduralProgram(
    graph: Graph,
    provider: Int? = providerLayerID,
    variant: SceneProceduralNoiseExecutionPlan.Variant = .worleyColorV1,
    slotIndex: Int? = 3,
    inputRole: SceneAuthoredEffectInputRole = .layerSource,
    supportsUtilityCapture: Bool = true
) -> SceneEffectStageProgram {
    let effect = graph.effects[0]
    let stageGraph = Graph(
        layerID: layerID,
        effects: [effect],
        renderTargets: [],
        nodes: graph.nodes.filter { $0.effect == effect.key },
        finalOutput: effect.output,
        blockers: []
    )
    return dedicatedProgram(
        graph: graph,
        effectIndex: 0,
        inputRole: inputRole,
        proceduralNoise: .init(
            layerID: layerID,
            effectKey: effect.key,
            renderGraph: stageGraph,
            variant: variant,
            dependencyProviderLayerID: provider,
            dependencySlotIndex: slotIndex
        ),
        supportsUtilityCapture: supportsUtilityCapture
    )
}

private func externalProceduralCatalog(
    descriptor: SceneRenderDescriptor,
    graph: Graph,
    program: SceneEffectStageProgram? = nil,
    allowDedicated: Bool = true
) -> Catalog {
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [graph],
        dedicatedStagePrograms: [program ?? proceduralProgram(graph: graph)]
    )
    return Catalog(
        admissionCandidates: candidates,
        materialCatalog: materialCatalog(graph: graph, omitNode: 0),
        dedicatedStageFamilies: [firstKey: "procedural-noise"],
        dedicatedLeafKeys: allowDedicated ? [firstKey] : []
    )
}

private func alternatingPairGraph() -> Graph {
    let keys = [firstKey, secondKey, thirdKey, fourthKey]
    var current = source()
    var nodes: [Graph.Node] = []
    var effects: [Graph.Effect] = []
    for (index, effectKey) in keys.enumerated() {
        let next = output(effectKey)
        let node = material(
            index: index,
            ordinal: 0,
            effect: effectKey,
            target: next,
            input: current
        )
        nodes.append(node)
        effects.append(.init(
            key: effectKey,
            definitionPath: "effects/alternating-\(index)/effect.json",
            input: current,
            output: next,
            nodeIndices: [node.nodeIndex]
        ))
        current = next
    }
    return .init(
        layerID: layerID,
        effects: effects,
        renderTargets: [],
        nodes: nodes,
        finalOutput: current,
        blockers: []
    )
}

private func alternatingPairDescriptor() -> SceneRenderDescriptor {
    let keys = [firstKey, secondKey, thirdKey, fourthKey]
    var effects = keys.enumerated().map { index, effectKey in
        SceneRenderDescriptor.EffectDescriptor(
            id: effectKey.descriptorID,
            file: "effects/alternating-\(index)/effect.json",
            visible: true,
            passes: [.init(passIndex: 0, combos: [:])]
        )
    }
    effects.insert(.init(
        id: "hidden-middle",
        file: "effects/hidden/effect.json",
        visible: false,
        passes: []
    ), at: 1)
    return .init(
        layers: [.init(
            id: layerID,
            effects: effects
        )],
        materialPasses: keys.indices.map {
            .init(
                id: "m\($0)",
                materialPath: "materials/m\($0).json",
                combos: [:]
            )
        },
        effectDefinitions: keys.indices.map {
            .init(
                relativePath: "effects/alternating-\($0)/effect.json",
                functions: nil
            )
        }
    )
}

private func dedicatedProgram(
    graph: Graph,
    effectIndex: Int,
    inputRole: SceneAuthoredEffectInputRole,
    opacity: Bool = false,
    proceduralNoise: SceneProceduralNoiseExecutionPlan? = nil,
    logicalTargetStage: Bool = false,
    fullFrameComposeStage: Bool = false,
    supportsUtilityCapture: Bool = false
) -> SceneEffectStageProgram {
    let effect = graph.effects[effectIndex]
    let nodes = graph.nodes.filter { $0.effect == effect.key }
    let stageGraph = Graph(
        layerID: layerID,
        effects: [effect],
        renderTargets: graph.renderTargets.filter { $0.texture.effect == effect.key },
        nodes: nodes,
        finalOutput: effect.output,
        blockers: []
    )
    return .init(
        effectKey: effect.key,
        stageGraph: stageGraph,
        executionPlan: .init(
            layerID: layerID,
            materialNodeCount: nodes.count,
            logicalRenderTargetCount: logicalTargetStage
                ? stageGraph.renderTargets.count : 0,
            inputRole: inputRole,
            cursorRipple: nil,
            opacity: opacity ? .init() : nil,
            proceduralNoise: proceduralNoise,
            supportsUnifiedLogicalTargetStage: logicalTargetStage,
            supportsUnifiedFullFrameComposeStage: fullFrameComposeStage,
            supportsUtilityCapture: supportsUtilityCapture
        )
    )
}

private func descriptor(
    ambiguousDefinition: Bool = false,
    withFunctions: Bool = false,
    contentKind: String = "image",
    utilityLayer: String? = nil,
    childLayerIDs: [Int] = [],
    dependencyLayerIDs: [Int] = [],
    authoredDependencies: [Int] = [],
    parentVisible: Bool? = nil,
    namedReferences: [SceneDependencyRenderPlan.Reference] = [],
    namedBindings: [SceneDependencyRenderPlan.Binding] = [],
    singleEffect: Bool = false
) -> SceneRenderDescriptor {
    let firstPasses = (0 ..< 4).map {
        SceneRenderDescriptor.PassDescriptor(
            passIndex: $0,
            combos: ["MODE": 1]
        )
    }
    let functions: SceneJSONValue? = withFunctions ? .object([
        "reset": .object([
            "action": .string("clear"),
            "fbos": .array([.string("history")]),
        ]),
    ]) : nil
    var definitions = [
        SceneEffectDefinition(
            relativePath: "effects/first/effect.json",
            functions: functions
        ),
        SceneEffectDefinition(
            relativePath: "effects/second/effect.json",
            functions: nil
        ),
    ]
    if ambiguousDefinition {
        definitions.append(.init(
            relativePath: "EFFECTS\\FIRST\\EFFECT.JSON",
            functions: functions
        ))
    }
    let parentID = parentVisible == nil ? nil : layerID + 1
    var effects: [SceneRenderDescriptor.EffectDescriptor] = [
        .init(
            id: firstKey.descriptorID,
            file: "effects/first/effect.json",
            visible: true,
            passes: firstPasses
        ),
        .init(
            id: "hidden-middle",
            file: "effects/hidden/effect.json",
            visible: false,
            passes: []
        ),
    ]
    if !singleEffect {
        effects.append(.init(
            id: secondKey.descriptorID,
            file: "effects/second/effect.json",
            visible: true,
            passes: [.init(passIndex: 0, combos: ["MODE": 1])]
        ))
    }
    var layers: [SceneRenderDescriptor.Layer] = [.init(
            id: layerID,
            effects: effects,
            contentKind: contentKind,
            utilityLayer: utilityLayer.flatMap(SceneUtilityLayer.Kind.init)
                .map(SceneUtilityLayer.init),
            childLayerIDs: childLayerIDs,
            dependencyLayerIDs: dependencyLayerIDs,
            authoredDependencies: authoredDependencies,
            parentID: parentID,
            visible: true,
            namedReferences: namedReferences,
            namedBindings: namedBindings
        )]
    if let parentVisible {
        layers.append(.init(
            id: layerID + 1,
            effects: [],
            visible: parentVisible
        ))
    }
    return .init(
        layers: layers,
        materialPasses: (0 ... 4).map {
            .init(
                id: "m\($0)",
                materialPath: "materials/m\($0).json",
                combos: ["MODE": 1]
            )
        },
        effectDefinitions: definitions
    )
}

private func role(
    _ identity: Graph.TextureIdentity
) -> Template.GraphTextureRole {
    Template.GraphTextureRole(rawValue: identity.kind.rawValue)!
}

private func template(
    node: Graph.Node,
    effect: Graph.Effect,
    overwrite: Bool = true,
    uniforms: [Template.UniformDeclaration] = [],
    namedProviderLayerID: Int? = nil
) -> Template {
    let roles = node.bindings.map {
        Template.GraphBindingRole(slot: $0.slot!, texture: role($0.texture))
    }
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    for binding in node.bindings {
        slots[binding.slot!] = .init(candidates: [
            .init(reference: .graph(binding.texture)),
        ])
    }
    if let namedProviderLayerID {
        slots[1] = .init(index: 1, candidates: [
            .init(reference: .provider(.namedLayerTarget(.init(
                providerLayerID: namedProviderLayerID,
                variant: .primary
            )))),
        ])
    }
    return .init(
        diagnosticProvenance: .init(nodeIndex: node.nodeIndex),
        graphRole: .init(
            effectInput: role(effect.input),
            effectOutput: role(effect.output),
            nodeTarget: role(node.target!),
            bindings: roles
        ),
        textureSlots: slots,
        uniformDeclarations: uniforms,
        renderState: .init(overwrite: overwrite),
        shaderContract: .init(stages: [
            .init(annotations: []),
            .init(annotations: []),
        ])
    )
}

private func materialCatalog(
    graph: Graph,
    omitNode: Int? = nil,
    uniformsByNode: [Int: [Template.UniformDeclaration]] = [:],
    namedProviderByNode: [Int: Int] = [:],
    demandIssueNodes: Set<Int> = [],
    demandIssueSlotsByNode: [Int: Set<Int>] = [:]
) -> SceneResolvedMaterialRuntimeCatalog {
    var entries: [
        SceneResolvedMaterialRuntimeCatalog.Key:
            SceneResolvedMaterialRuntimeCatalog.Entry
    ] = [:]
    let effects = Dictionary(uniqueKeysWithValues: graph.effects.map { ($0.key, $0) })
    for node in graph.nodes where node.kind == .material && node.nodeIndex != omitNode {
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(
            template(
                node: node,
                effect: effects[node.effect]!,
                uniforms: uniformsByNode[node.nodeIndex] ?? [],
                namedProviderLayerID: namedProviderByNode[node.nodeIndex]
            )
        )
    }
    let demandIssues = Set(graph.nodes.flatMap { node in
        let slots = demandIssueSlotsByNode[node.nodeIndex]
            ?? (demandIssueNodes.contains(node.nodeIndex) ? [0] : [])
        return slots.map { slot in
            SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue(
                key: .init(effect: node.effect, nodeIndex: node.nodeIndex),
                slot: slot
            )
        }
    })
    return .init(entries: entries, resourceDemandIssues: demandIssues)
}

private func catalog(
    descriptor value: SceneRenderDescriptor,
    graphs: [Graph],
    materials: SceneResolvedMaterialRuntimeCatalog,
    admissionCandidates: [
        SceneResolvedMaterialExecutionCapabilityAdmission.Candidate
    ]? = nil,
    conditionSchemaEvidence: [
        Graph.EffectKey: SceneGraphConditionSchemaEvidence
    ] = [:],
    dynamicProducers: Catalog.DynamicProducerCatalog = .empty
) -> Catalog {
    let candidates = admissionCandidates
        ?? SceneResolvedMaterialExecutionCapabilityAdmission.compile(
            descriptor: value,
            authoredPlans: graphs,
            conditionSchemaEvidence: conditionSchemaEvidence
        )
    return .init(
        admissionCandidates: candidates,
        materialCatalog: materials,
        dynamicProducers: dynamicProducers
    )
}

private func fullFrameComposeCatalog(
    graph: Graph,
    descriptor: SceneRenderDescriptor,
    allowDedicated: Bool,
    supportsUtilityCapture: Bool = false
) -> Catalog {
    let program = dedicatedProgram(
        graph: graph,
        effectIndex: 0,
        inputRole: .layerSource,
        fullFrameComposeStage: true,
        supportsUtilityCapture: supportsUtilityCapture
    )
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [graph],
        dedicatedStagePrograms: [program]
    )
    return .init(
        admissionCandidates: candidates,
        materialCatalog: materialCatalog(
            graph: graph,
            demandIssueNodes: Set(graph.nodes.map(\.nodeIndex))
        ),
        dedicatedStageFamilies: [firstKey: "precise-gaussian"],
        dedicatedFullFrameComposeStageKeys: allowDedicated ? [firstKey] : []
    )
}

private func reportHas(_ catalog: Catalog, _ code: String) -> Bool {
    catalog.reportLines.contains { $0.contains("rejection: \(code) count=1") }
}

private func admissionRejects(
    _ descriptor: SceneRenderDescriptor,
    raw: Graph,
    reason: String
) -> Bool {
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [raw]
    )
    guard let candidate = candidates.first(where: { $0.layerID == layerID }) else {
        return false
    }
    guard case let .failure(failure) = candidate.result else { return false }
    return failure.code == reason
}

private func dynamicTarget() -> SceneDynamicTarget {
    .effectConstant(
        layerID: layerID,
        effectIndex: firstKey.effectIndex,
        passIndex: 0,
        name: "strength"
    )
}

private func dynamicUniform(
    contributors: [Template.DynamicUniformSource],
    attachments: [Template.DynamicUniformScriptAttachment] = [],
    hasAuthoredFallback: Bool = true
) -> Template.UniformDeclaration {
    .init(
        name: "strength",
        value: .dynamic(.init(
            target: dynamicTarget(),
            valueContributors: contributors,
            scriptAttachments: attachments,
            authoredFallback: hasAuthoredFallback ? .init() : nil
        ))
    )
}

private func rejectsOversizedLayerBeforePlanning() -> Bool {
    let effectCount =
        SceneResolvedMaterialExecutionCapabilityAdmission.maximumEffectsPerLayer + 1
    let descriptors = (0 ..< effectCount).map { index in
        SceneRenderDescriptor.EffectDescriptor(
            id: "capacity-\(index)",
            file: "effects/capacity-\(index)/effect.json",
            visible: true,
            passes: []
        )
    }
    let effects = descriptors.enumerated().map { index, descriptor in
        let effectKey = key(index, descriptor.id)
        return Graph.Effect(
            key: effectKey,
            definitionPath: descriptor.file,
            input: source(),
            output: output(effectKey),
            nodeIndices: []
        )
    }
    let graph = Graph(
        layerID: layerID,
        effects: effects,
        renderTargets: [],
        nodes: [],
        finalOutput: effects.last!.output,
        blockers: []
    )
    let descriptor = SceneRenderDescriptor(
        layers: [.init(id: layerID, effects: descriptors)],
        materialPasses: [],
        effectDefinitions: []
    )
    guard let candidate =
        SceneResolvedMaterialExecutionCapabilityAdmission.compile(
            descriptor: descriptor,
            authoredPlans: [graph]
        ).first else { return false }
    switch candidate.result {
    case .success:
        return false
    case let .failure(failure):
        return failure.code == "layer-capacity"
    }
}

@main
private enum Harness {
    static func main() throws {
        let raw = rawGraph()
        let desc = descriptor()
        let admissionCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: desc,
                authoredPlans: [raw]
            )
        let success = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(graph: raw, omitNode: 1),
            admissionCandidates: admissionCandidates
        )
        let graphInternalDescriptor = descriptor(
            dependencyLayerIDs: [layerID],
            namedReferences: [namedReference()]
        )
        let graphInternalCatalog = catalog(
            descriptor: graphInternalDescriptor,
            graphs: [raw],
            materials: materialCatalog(graph: raw, omitNode: 1)
        )
        let resolvedMaterialGraph = externalResolvedMaterialGraph()
        let externalResolvedMaterial = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(),
            graph: resolvedMaterialGraph
        )
        let externalResolvedMaterialCapability = externalResolvedMaterial
            .claim(layerID: layerID)
            .flatMap { externalResolvedMaterial.resolve($0.token) }
        let utilityExternalResolvedMaterial = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(utilityConsumer: true),
            graph: resolvedMaterialGraph
        )
        let utilityExternalResolvedMaterialCapability = utilityExternalResolvedMaterial
            .claim(layerID: layerID)
            .flatMap { utilityExternalResolvedMaterial.resolve($0.token) }
        let resolvedMaterialOpacityGraph = externalResolvedMaterialGraph(
            includeOpacity: true
        )
        let utilityResolvedMaterialOpacity = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(
                utilityConsumer: true,
                includeOpacity: true
            ),
            graph: resolvedMaterialOpacityGraph
        )
        let utilityResolvedMaterialOpacityCapability = utilityResolvedMaterialOpacity
            .claim(layerID: layerID)
            .flatMap { utilityResolvedMaterialOpacity.resolve($0.token) }
        let secondaryExternalResolvedMaterial = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(references: [namedReference(
                effectID: firstKey.descriptorID,
                providerLayerID: providerLayerID,
                slotIndex: 1,
                variant: .secondary
            )]),
            graph: resolvedMaterialGraph
        )
        let wrongSlotExternalResolvedMaterial = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(references: [namedReference(
                effectID: firstKey.descriptorID,
                providerLayerID: providerLayerID,
                slotIndex: 0
            )]),
            graph: resolvedMaterialGraph
        )
        let wrongDependencyIDExternalResolvedMaterial =
            externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(
                dependencyLayerIDs: [providerLayerID + 1]
            ),
            graph: resolvedMaterialGraph
        )
        let authoredDependencyExternalResolvedMaterial =
            externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(
                authoredDependencies: [1]
            ),
            graph: resolvedMaterialGraph
        )
        let extraReferenceExternalResolvedMaterial = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(references: [
                namedReference(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    slotIndex: 1
                ),
                namedReference(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    passIndex: 1,
                    slotIndex: 1
                ),
            ]),
            graph: resolvedMaterialGraph
        )
        let proceduralExternalResolvedMaterial = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(bindings: [dependencyBinding(
                providerLayerID: providerLayerID,
                kind: .proceduralNoiseLayer
            )]),
            graph: resolvedMaterialGraph
        )
        let resolvedMaterialWithoutOwnership = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(
                dependencyLayerIDs: [],
                references: [],
                bindings: []
            ),
            graph: resolvedMaterialGraph
        )
        let resolvedMaterialWithoutProgram = externalResolvedMaterialCatalog(
            descriptor: externalResolvedMaterialDescriptor(),
            graph: resolvedMaterialGraph,
            programAvailable: false
        )
        let proceduralGraph = externalProceduralGraph()
        let externalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(),
            graph: proceduralGraph
        )
        let externalProceduralCapability = externalProcedural
            .claim(layerID: layerID)
            .flatMap { externalProcedural.resolve($0.token) }
        let modernExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(),
            graph: proceduralGraph,
            program: proceduralProgram(
                graph: proceduralGraph,
                variant: .colorPerlinRGB
            )
        )
        let wrongProviderExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(),
            graph: proceduralGraph,
            program: proceduralProgram(
                graph: proceduralGraph,
                provider: providerLayerID + 1
            )
        )
        let secondaryExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(references: [namedReference(
                effectID: firstKey.descriptorID,
                providerLayerID: providerLayerID,
                slotIndex: 3,
                variant: .secondary
            )]),
            graph: proceduralGraph
        )
        let wrongEffectProceduralReference = namedReference(
            effectID: "wrong-effect",
            providerLayerID: providerLayerID,
            slotIndex: 3
        )
        let wrongEffectExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(
                references: [wrongEffectProceduralReference],
                bindings: [dependencyBinding(
                    effectID: "wrong-effect",
                    providerLayerID: providerLayerID,
                    slotIndex: 3,
                    kind: .proceduralNoiseLayer
                )]
            ),
            graph: proceduralGraph
        )
        let wrongPassProceduralReference = namedReference(
            effectID: firstKey.descriptorID,
            providerLayerID: providerLayerID,
            passIndex: 1,
            slotIndex: 3
        )
        let wrongPassExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(
                references: [wrongPassProceduralReference],
                bindings: [dependencyBinding(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    passIndex: 1,
                    slotIndex: 3,
                    kind: .proceduralNoiseLayer
                )]
            ),
            graph: proceduralGraph
        )
        let wrongSlotProceduralReference = namedReference(
            effectID: firstKey.descriptorID,
            providerLayerID: providerLayerID,
            slotIndex: 2
        )
        let wrongSlotExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(
                references: [wrongSlotProceduralReference],
                bindings: [dependencyBinding(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    slotIndex: 2,
                    kind: .proceduralNoiseLayer
                )]
            ),
            graph: proceduralGraph
        )
        let wrongBlendExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(bindings: [dependencyBinding(
                effectID: firstKey.descriptorID,
                providerLayerID: providerLayerID,
                slotIndex: 3,
                blendMode: 5,
                kind: .proceduralNoiseLayer
            )]),
            graph: proceduralGraph
        )
        let missingExternalProceduralOwnership = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(
                dependencyLayerIDs: [],
                references: [],
                bindings: []
            ),
            graph: proceduralGraph
        )
        let extraReferenceExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(references: [
                namedReference(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    slotIndex: 3
                ),
                namedReference(
                    effectID: firstKey.descriptorID,
                    providerLayerID: providerLayerID,
                    passIndex: 1,
                    slotIndex: 3
                ),
            ]),
            graph: proceduralGraph
        )
        let extraProviderExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(
                dependencyLayerIDs: [providerLayerID, providerLayerID + 1]
            ),
            graph: proceduralGraph
        )
        let providerlessExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(),
            graph: proceduralGraph,
            program: proceduralProgram(graph: proceduralGraph, provider: nil)
        )
        let wrongInputExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(),
            graph: proceduralGraph,
            program: proceduralProgram(
                graph: proceduralGraph,
                inputRole: .priorEffectOutput
            )
        )
        let unsupportedCaptureExternalProcedural = externalProceduralCatalog(
            descriptor: externalProceduralDescriptor(),
            graph: proceduralGraph,
            program: proceduralProgram(
                graph: proceduralGraph,
                supportsUtilityCapture: false
            )
        )
        let externalOwnershipMatches: Bool
        if let externalResolvedMaterialCapability,
           case let .externalPrimary(binding) =
            externalResolvedMaterialCapability.dependencyOwnership {
            externalOwnershipMatches = binding.consumerLayerID == layerID
                && binding.providerLayerID == providerLayerID
                && binding.slot == .init(
                    effectID: firstKey.descriptorID,
                    passIndex: 0,
                    slotIndex: 1
                )
                && binding.blendMode == 0
                && binding.kind == .resolvedMaterial
        } else {
            externalOwnershipMatches = false
        }
        let claim = success.claim(layerID: layerID)!
        let capability = success.resolve(claim.token)!
        let secondCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(graph: raw, omitNode: 1),
            admissionCandidates: admissionCandidates
        )
        let expectedDispositionSubjects = capability.admittedProducts.flatMap {
            $0.graph.effects.map {
                SceneEffectExactRuntimeSubject(
                    key: $0.key,
                    family: "resolved-material"
                )
            }
        }
        let dispositionOwnership = success.runtimeDispositionOwnership(
            token: claim.token,
            subjects: expectedDispositionSubjects
        )
        let foreignClaim = secondCatalog.claim(layerID: layerID)!
        let projectUtilityGraph = rawGraph(omitSecond: true)
        let projectUtilityCatalog = catalog(
            descriptor: descriptor(
                contentKind: "project",
                utilityLayer: "project",
                singleEffect: true
            ),
            graphs: [projectUtilityGraph],
            materials: materialCatalog(graph: projectUtilityGraph, omitNode: 1)
        )
        let utilityRoute = projectUtilityCatalog.claim(layerID: layerID)
            .flatMap { projectUtilityCatalog.resolve($0.token)?.sourceRoute }
        let utilityPairGraph = pairOnlyGraph()
        let utilityPairDescriptor = descriptor(
            contentKind: "composition",
            utilityLayer: "composition"
        )
        let utilityAdapterCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: utilityPairDescriptor,
                authoredPlans: [utilityPairGraph],
                dedicatedStagePrograms: [dedicatedProgram(
                    graph: utilityPairGraph,
                    effectIndex: 1,
                    inputRole: .priorEffectOutput,
                    opacity: true,
                    supportsUtilityCapture: true
                )]
            )
        let utilityAdapterCatalog = Catalog(
            admissionCandidates: utilityAdapterCandidates,
            materialCatalog: materialCatalog(
                graph: utilityPairGraph,
                omitNode: 1
            ),
            dedicatedStageFamilies: [secondKey: "opacity"],
            dedicatedLeafKeys: [secondKey]
        )
        let utilityAdapterCapability = utilityAdapterCatalog.claim(layerID: layerID)
            .flatMap { utilityAdapterCatalog.resolve($0.token) }
        let downstreamUtilityAdapterCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: utilityPairDescriptor,
                authoredPlans: [utilityPairGraph],
                dedicatedStagePrograms: [dedicatedProgram(
                    graph: utilityPairGraph,
                    effectIndex: 1,
                    inputRole: .priorEffectOutput,
                    opacity: true
                )]
            )
        let downstreamUtilityAdapterCatalog = Catalog(
            admissionCandidates: downstreamUtilityAdapterCandidates,
            materialCatalog: materialCatalog(
                graph: utilityPairGraph,
                omitNode: 1
            ),
            dedicatedStageFamilies: [secondKey: "opacity"],
            dedicatedLeafKeys: [secondKey]
        )
        let resolvedUtilityChainCatalog = catalog(
            descriptor: utilityPairDescriptor,
            graphs: [utilityPairGraph],
            materials: materialCatalog(graph: utilityPairGraph)
        )
        let omitted = rawGraph(omitSecond: true)
        let omittedCatalog = catalog(
            descriptor: desc,
            graphs: [omitted],
            materials: materialCatalog(graph: omitted)
        )
        let discontinuous = rawGraph(discontinuous: true)
        let discontinuousCatalog = catalog(
            descriptor: desc,
            graphs: [discontinuous],
            materials: materialCatalog(graph: discontinuous)
        )
        let duplicateCatalog = catalog(
            descriptor: desc,
            graphs: [raw, raw],
            materials: materialCatalog(graph: raw)
        )
        let ambiguousCatalog = catalog(
            descriptor: descriptor(ambiguousDefinition: true),
            graphs: [raw],
            materials: materialCatalog(graph: raw)
        )
        let unresolved = rawGraph(unresolvedCondition: true)
        let unresolvedCatalog = catalog(
            descriptor: desc,
            graphs: [unresolved],
            materials: materialCatalog(graph: unresolved)
        )
        let implicitZeroCatalog = catalog(
            descriptor: desc,
            graphs: [unresolved],
            materials: materialCatalog(graph: unresolved),
            conditionSchemaEvidence: [firstKey: .init(
                keysProvenZeroWhenMissing: ["UNKNOWN"]
            )]
        )
        let implicitZeroCapability = implicitZeroCatalog
            .claim(layerID: layerID)
            .flatMap { implicitZeroCatalog.resolve($0.token) }
        let implicitZeroProduct = implicitZeroCapability?.admittedProducts.first
        let missingTemplateCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(graph: raw, omitNode: 3)
        )
        let functionRaw = rawGraph(includeFunctionBlocker: true)
        let functionCatalog = catalog(
            descriptor: descriptor(withFunctions: true),
            graphs: [functionRaw],
            materials: materialCatalog(graph: functionRaw)
        )
        let dynamicCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: desc,
                authoredPlans: [raw],
                dynamicEffectVisibilityOwners: [
                    .init(layerID: layerID, effectIndex: 0),
                ]
            )
        let dynamicCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(graph: raw, omitNode: 1),
            admissionCandidates: dynamicCandidates
        )
        let validTimelineCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: [0: [dynamicUniform(contributors: [.timeline])]]
            ),
            admissionCandidates: admissionCandidates,
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let validUserPropertyCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.userProperty("strength-property")]
                )]]
            ),
            admissionCandidates: admissionCandidates,
            dynamicProducers: .init(
                userProperties: [.init(
                    propertyKey: "strength-property",
                    target: dynamicTarget()
                )],
                timelineTargets: [],
                sceneScriptTargets: []
            )
        )
        let validSceneScriptCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: [0: [dynamicUniform(contributors: [.sceneScript])]]
            ),
            admissionCandidates: admissionCandidates,
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [],
                sceneScriptTargets: [dynamicTarget()]
            )
        )
        let unknownScriptCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline],
                    attachments: [.unproven]
                )]]
            ),
            admissionCandidates: admissionCandidates,
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let multipleProducerCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline, .userProperty("strength-property")]
                )]]
            ),
            admissionCandidates: admissionCandidates,
            dynamicProducers: .init(
                userProperties: [.init(
                    propertyKey: "strength-property",
                    target: dynamicTarget()
                )],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let multipleProducerMissingCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline, .userProperty("missing-property")]
                )]]
            ),
            admissionCandidates: admissionCandidates,
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let missingProducerCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.userProperty("missing-property")]
                )]]
            ),
            admissionCandidates: admissionCandidates
        )
        let unverifiedSceneScriptCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [],
                    attachments: [.unproven]
                )]]
            ),
            admissionCandidates: admissionCandidates
        )
        let pairGraph = pairOnlyGraph()
        let pairDescriptor = pairOnlyDescriptor()
        let pairMultipleProducerCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline, .userProperty("strength-property")]
                )]]
            ),
            dynamicProducers: .init(
                userProperties: [.init(
                    propertyKey: "strength-property",
                    target: dynamicTarget()
                )],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let pairMultipleProducerCapability = pairMultipleProducerCatalog
            .claim(layerID: layerID)
            .flatMap { pairMultipleProducerCatalog.resolve($0.token) }
        let pairMultipleProducerMissingCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline, .userProperty("missing-property")]
                )]]
            ),
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let pairMultipleProducerMissingCapability = pairMultipleProducerMissingCatalog
            .claim(layerID: layerID)
            .flatMap { pairMultipleProducerMissingCatalog.resolve($0.token) }
        let pairMultipleProducerAllMissingCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline, .userProperty("missing-property")]
                )]]
            )
        )
        let pairMultipleProducerAllMissingCapability = pairMultipleProducerAllMissingCatalog
            .claim(layerID: layerID)
            .flatMap { pairMultipleProducerAllMissingCatalog.resolve($0.token) }
        let pairMultipleProducerMismatchedCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline, .userProperty("strength-property")]
                )]]
            ),
            dynamicProducers: .init(
                userProperties: [.init(
                    propertyKey: "strength-property",
                    target: .effectConstant(
                        layerID: layerID,
                        effectIndex: firstKey.effectIndex,
                        passIndex: 0,
                        name: "other-strength"
                    )
                )],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let pairMultipleProducerAttachmentCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline, .userProperty("strength-property")],
                    attachments: [.unproven]
                )]]
            ),
            dynamicProducers: .init(
                userProperties: [.init(
                    propertyKey: "strength-property",
                    target: dynamicTarget()
                )],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let pairUnprovenScriptCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline],
                    attachments: [.unproven]
                )]]
            ),
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let pairUnprovenScriptCapability = pairUnprovenScriptCatalog
            .claim(layerID: layerID)
            .flatMap { pairUnprovenScriptCatalog.resolve($0.token) }
        let pairScriptOnlyCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [],
                    attachments: [.unproven]
                )]]
            )
        )
        let pairScriptOnlyCapability = pairScriptOnlyCatalog
            .claim(layerID: layerID)
            .flatMap { pairScriptOnlyCatalog.resolve($0.token) }
        let pairScriptOnlyNoFallbackCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [],
                    attachments: [.unproven],
                    hasAuthoredFallback: false
                )]]
            )
        )
        let pairKnownAttachmentWithoutValueCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [],
                    attachments: [.mediaThumbnailAnimationRestart]
                )]]
            )
        )
        let pairDuplicateScriptOnlyAttachmentCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [],
                    attachments: [.unproven, .unproven]
                )]]
            )
        )
        let pairUnprovenScriptMissingProducerCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline],
                    attachments: [.unproven]
                )]]
            )
        )
        let pairMissingProducerCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.userProperty("missing-property")]
                )]]
            )
        )
        let pairMissingProducerCapability = pairMissingProducerCatalog
            .claim(layerID: layerID)
            .flatMap { pairMissingProducerCatalog.resolve($0.token) }
        let pairMismatchedProducerCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.userProperty("strength-property")]
                )]]
            ),
            dynamicProducers: .init(
                userProperties: [.init(
                    propertyKey: "strength-property",
                    target: .effectConstant(
                        layerID: layerID,
                        effectIndex: firstKey.effectIndex,
                        passIndex: 0,
                        name: "other-strength"
                    )
                )],
                timelineTargets: [],
                sceneScriptTargets: []
            )
        )
        let pairDuplicateAttachmentCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.timeline],
                    attachments: [.unproven, .unproven]
                )]]
            ),
            dynamicProducers: .init(
                userProperties: [],
                timelineTargets: [dynamicTarget()],
                sceneScriptTargets: []
            )
        )
        let pairKnownControlWrongContributorCatalog = catalog(
            descriptor: pairDescriptor,
            graphs: [pairGraph],
            materials: materialCatalog(
                graph: pairGraph,
                uniformsByNode: [0: [dynamicUniform(
                    contributors: [.userProperty("strength-property")],
                    attachments: [.mediaThumbnailAnimationRestart]
                )]]
            ),
            dynamicProducers: .init(
                userProperties: [.init(
                    propertyKey: "strength-property",
                    target: dynamicTarget()
                )],
                timelineTargets: [],
                sceneScriptTargets: []
            )
        )
        let inactiveDemandIssueCatalog = Catalog(
            admissionCandidates:
                SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                    descriptor: pairDescriptor,
                    authoredPlans: [pairGraph]
                ),
            materialCatalog: materialCatalog(
                graph: pairGraph,
                demandIssueSlotsByNode: [0: [2]]
            )
        )
        let dedicatedBeforeResolvedCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: pairDescriptor,
                authoredPlans: [pairGraph],
                dedicatedStagePrograms: [dedicatedProgram(
                    graph: pairGraph,
                    effectIndex: 0,
                    inputRole: .layerSource
                )]
            )
        let dedicatedBeforeResolvedCatalog = Catalog(
            admissionCandidates: dedicatedBeforeResolvedCandidates,
            materialCatalog: materialCatalog(graph: pairGraph),
            dedicatedStageFamilies: [firstKey: "fixture-dedicated"],
            dedicatedLeafKeys: [firstKey]
        )
        let alternatingGraph = alternatingPairGraph()
        let alternatingCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: alternatingPairDescriptor(),
                authoredPlans: [alternatingGraph],
                dedicatedStagePrograms: [
                    dedicatedProgram(
                        graph: alternatingGraph,
                        effectIndex: 0,
                        inputRole: .layerSource
                    ),
                    dedicatedProgram(
                        graph: alternatingGraph,
                        effectIndex: 2,
                        inputRole: .priorEffectOutput
                    ),
                ]
            )
        let alternatingCatalog = Catalog(
            admissionCandidates: alternatingCandidates,
            materialCatalog: materialCatalog(
                graph: alternatingGraph,
                demandIssueNodes: [0, 2]
            ),
            dedicatedStageFamilies: [
                firstKey: "fixture-dedicated",
                thirdKey: "fixture-dedicated",
            ],
            dedicatedLeafKeys: [firstKey, thirdKey]
        )
        let alternatingCapability = alternatingCatalog.claim(layerID: layerID)
            .flatMap { alternatingCatalog.resolve($0.token) }
        let resolvedBeforeDedicatedCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: pairDescriptor,
                authoredPlans: [pairGraph],
                dedicatedStagePrograms: [dedicatedProgram(
                    graph: pairGraph,
                    effectIndex: 1,
                    inputRole: .priorEffectOutput,
                    opacity: true
                )]
            )
        let resolvedBeforeDedicatedCatalog = Catalog(
            admissionCandidates: resolvedBeforeDedicatedCandidates,
            materialCatalog: materialCatalog(graph: pairGraph, omitNode: 1),
            dedicatedStageFamilies: [secondKey: "fixture-dedicated"],
            dedicatedLeafKeys: [secondKey]
        )
        let emptyDedicatedLeafCatalog = Catalog(
            admissionCandidates: resolvedBeforeDedicatedCandidates,
            materialCatalog: materialCatalog(graph: pairGraph),
            dedicatedStageFamilies: [secondKey: "fixture-dedicated"],
            dedicatedLeafKeys: []
        )
        let fallbackDedicatedLeafCatalog = Catalog(
            admissionCandidates: resolvedBeforeDedicatedCandidates,
            materialCatalog: materialCatalog(graph: pairGraph, omitNode: 1),
            dedicatedStageFamilies: [secondKey: "fixture-dedicated"],
            dedicatedLeafKeys: []
        )
        let programFirstCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: pairDescriptor,
                authoredPlans: [pairGraph],
                dedicatedStagePrograms: [dedicatedProgram(
                    graph: pairGraph,
                    effectIndex: 1,
                    inputRole: .priorEffectOutput
                )]
            )
        let programFirstCatalog = Catalog(
            admissionCandidates: programFirstCandidates,
            materialCatalog: materialCatalog(graph: pairGraph),
            dedicatedStageFamilies: [secondKey: "fixture-program-fallback"],
            dedicatedLeafKeys: []
        )
        let logicalGraph = logicalTargetGraph()
        let logicalProgram = dedicatedProgram(
            graph: logicalGraph,
            effectIndex: 0,
            inputRole: .layerSource,
            logicalTargetStage: true
        )
        let logicalCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: logicalTargetDescriptor(),
                authoredPlans: [logicalGraph],
                dedicatedStagePrograms: [logicalProgram]
            )
        let logicalCatalog = Catalog(
            admissionCandidates: logicalCandidates,
            materialCatalog: materialCatalog(
                graph: logicalGraph,
                demandIssueNodes: [0, 1]
            ),
            dedicatedStageFamilies: [firstKey: "precise-gaussian"],
            dedicatedGraphStageKeys: [firstKey]
        )
        let logicalWithoutAllowlist = Catalog(
            admissionCandidates: logicalCandidates,
            materialCatalog: materialCatalog(
                graph: logicalGraph,
                demandIssueNodes: [0, 1]
            ),
            dedicatedStageFamilies: [firstKey: "precise-gaussian"]
        )
        let capturedMainLogicalDescriptor = logicalTargetDescriptor(
            capturedMain: true
        )
        let capturedMainLogicalCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: capturedMainLogicalDescriptor,
                authoredPlans: [logicalGraph],
                dedicatedStagePrograms: [dedicatedProgram(
                    graph: logicalGraph,
                    effectIndex: 0,
                    inputRole: .layerSource,
                    logicalTargetStage: true,
                    supportsUtilityCapture: true
                )]
            )
        let capturedMainLogicalCatalog = Catalog(
            admissionCandidates: capturedMainLogicalCandidates,
            materialCatalog: materialCatalog(
                graph: logicalGraph,
                demandIssueNodes: [0, 1]
            ),
            dedicatedStageFamilies: [firstKey: "precise-gaussian"],
            dedicatedGraphStageKeys: [firstKey]
        )
        let capturedMainLogicalWithoutSupportCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: capturedMainLogicalDescriptor,
                authoredPlans: [logicalGraph],
                dedicatedStagePrograms: [logicalProgram]
            )
        let capturedMainLogicalWithoutSupportCatalog = Catalog(
            admissionCandidates: capturedMainLogicalWithoutSupportCandidates,
            materialCatalog: materialCatalog(
                graph: logicalGraph,
                demandIssueNodes: [0, 1]
            ),
            dedicatedStageFamilies: [firstKey: "precise-gaussian"],
            dedicatedGraphStageKeys: [firstKey]
        )
        let capturedMainLogicalCapability = capturedMainLogicalCatalog
            .claim(layerID: layerID)
            .flatMap { capturedMainLogicalCatalog.resolve($0.token) }
        let uniqueLogicalGraph = logicalTargetGraph(unique: true)
        let uniqueLogicalCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: logicalTargetDescriptor(),
                authoredPlans: [uniqueLogicalGraph],
                dedicatedStagePrograms: [dedicatedProgram(
                    graph: uniqueLogicalGraph,
                    effectIndex: 0,
                    inputRole: .layerSource,
                    logicalTargetStage: true
                )]
            )
        let uniqueLogicalCatalog = Catalog(
            admissionCandidates: uniqueLogicalCandidates,
            materialCatalog: materialCatalog(
                graph: uniqueLogicalGraph,
                demandIssueNodes: [0, 1]
            ),
            dedicatedStageFamilies: [firstKey: "precise-gaussian"],
            dedicatedGraphStageKeys: [firstKey]
        )
        let composeGraph = fullFrameComposeGraph()
        let composeDescriptor = fullFrameComposeDescriptor()
        let admittedComposeCatalog = fullFrameComposeCatalog(
            graph: composeGraph,
            descriptor: composeDescriptor,
            allowDedicated: true
        )
        let fullFrameComposeWithoutAllowlist = fullFrameComposeCatalog(
            graph: composeGraph,
            descriptor: composeDescriptor,
            allowDedicated: false
        )
        let capturedMainComposeCatalog = fullFrameComposeCatalog(
            graph: composeGraph,
            descriptor: fullFrameComposeDescriptor(capturedMain: true),
            allowDedicated: true,
            supportsUtilityCapture: true
        )
        let historyComposeGraph = fullFrameComposeGraph(includeHistory: true)
        let historyComposeCatalog = fullFrameComposeCatalog(
            graph: historyComposeGraph,
            descriptor: fullFrameComposeDescriptor(),
            allowDedicated: true
        )
        let missingComposeGraph = fullFrameComposeGraph(compose: nil)
        let missingComposeCatalog = fullFrameComposeCatalog(
            graph: missingComposeGraph,
            descriptor: fullFrameComposeDescriptor(),
            allowDedicated: true
        )
        let extraNodeComposeGraph = fullFrameComposeGraph(includeThirdNode: true)
        let extraNodeComposeCatalog = fullFrameComposeCatalog(
            graph: extraNodeComposeGraph,
            descriptor: fullFrameComposeDescriptor(passCount: 3),
            allowDedicated: true
        )
        let fullFrameComposeCapability = admittedComposeCatalog
            .claim(layerID: layerID)
            .flatMap { admittedComposeCatalog.resolve($0.token) }
        let fullFrameComposeStep = fullFrameComposeCapability?.pairPlan.effects.first

        let firstProduct = capability.admittedProducts[0]
        let result: [String: Any] = [
            "claim": claim.layerID == layerID
                && success.claim(layerID: layerID + 1) == nil,
            "token": success.resolve(claim.token) === capability
                && secondCatalog.resolve(claim.token) == nil,
            "dispositionOwnership": [
                "valid": dispositionOwnership?.subjects.map(\.key)
                    == expectedDispositionSubjects.map(\.key),
                "automatic": success.runtimeDispositionOwnerships.count == 1
                    && success.runtimeDispositionOwnerships[0].layerID == layerID,
                "duplicateRejected": success.runtimeDispositionOwnership(
                    token: claim.token,
                    subjects: expectedDispositionSubjects
                        + [expectedDispositionSubjects[0]]
                ) == nil,
                "subjectMismatchRejected": success.runtimeDispositionOwnership(
                    token: claim.token,
                    subjects: Array(expectedDispositionSubjects.dropLast())
                ) == nil,
                "familyMismatchRejected": success.runtimeDispositionOwnership(
                    token: claim.token,
                    subjects: expectedDispositionSubjects.map {
                        .init(key: $0.key, family: "legacy-owner")
                    }
                ) == nil,
                "foreignTokenRejected": success.runtimeDispositionOwnership(
                    token: foreignClaim.token,
                    subjects: expectedDispositionSubjects
                ) == nil,
            ],
            "products": capability.admittedProducts.count,
            "effectIndices": capability.pairPlan.effects.map {
                $0.effect.effectIndex
            },
            "pairTransitions": capability.pairPlan.transitionCount,
            "pairBase": capability.pairPlan.baseCaptureMember.rawValue,
            "pairTerminal": capability.pairPlan.terminalMember.rawValue,
            "prunedNodes": firstProduct.graph.nodes.map(\.nodeIndex),
            "prunedTargets": firstProduct.graph.renderTargets.compactMap {
                $0.texture.name
            },
            "composeNodes": firstProduct.composeTransitions.nodeIndices,
            "conditionFalseMaterialExcluded": capability.material(
                effect: firstKey,
                nodeIndex: 1
            ) == nil,
            "implicitZeroCondition": [
                "claimed": implicitZeroCapability != nil,
                "keys": implicitZeroProduct?.conditionSnapshot.implicitZeroKeys ?? [],
                "nodes": implicitZeroProduct?.graph.nodes.map(\.nodeIndex) ?? [],
                "targets": implicitZeroProduct?.graph.renderTargets.compactMap {
                    $0.texture.name
                } ?? [],
            ],
            "materials": capability.materials.count,
            "fullFrameExtentPolicy": [
                "maximumDimensionClass": capability.fullFrameExtentPolicy
                    .maximumDimensionClass.rawValue,
                "requiresExactInputExtent": capability.fullFrameExtentPolicy
                    .requiresExactInputExtent,
            ],
            "dependencyOwnership": [
                "none": capability.dependencyOwnership.reportKind,
                "graphInternal": graphInternalCatalog.claim(layerID: layerID) != nil,
                "graphInternalReport": graphInternalCatalog.reportLines.first(where: {
                    $0.contains("status=accepted")
                }) ?? "",
                "externalPrimary": externalOwnershipMatches,
                "externalPrimaryReport": externalResolvedMaterial.reportLines.first(where: {
                    $0.contains("status=accepted")
                }) ?? "",
                "externalUtilityRoute": utilityExternalResolvedMaterialCapability?
                    .sourceRoute == .capturedMainTargetTexture,
                "externalUtilityStages": utilityResolvedMaterialOpacityCapability?
                    .stages.count == 2,
                "externalProcedural": externalProceduralCapability.map {
                    capability in
                    guard case let .externalPrimary(binding) =
                            capability.dependencyOwnership else { return false }
                    return binding.consumerLayerID == layerID
                        && binding.providerLayerID == providerLayerID
                        && binding.slot == .init(
                            effectID: firstKey.descriptorID,
                            passIndex: 0,
                            slotIndex: 3
                        )
                        && binding.blendMode == 0
                        && binding.kind == .proceduralNoiseLayer
                        && capability.sourceRoute == .capturedMainTargetTexture
                        && capability.stages.count == 1
                } ?? false,
            ],
            "capacity": [
                "effects": SceneResolvedMaterialExecutionCapabilityAdmission
                    .maximumEffectsPerLayer,
                "nodes": SceneResolvedMaterialExecutionCapabilityAdmission
                    .maximumNodesPerLayer,
                "targets": SceneResolvedMaterialExecutionCapabilityAdmission
                    .maximumRenderTargetsPerLayer,
                "rejectsOversized": rejectsOversizedLayerBeforePlanning(),
            ],
            "report": success.reportLines.first ?? "",
            "acceptedRouteLines": success.reportLines.filter {
                $0.contains("schema=layer-graph-route-v1")
            },
            "rejections": [
                "omitted": reportHas(
                    omittedCatalog,
                    "active-effect-conservation"
                ),
                "discontinuous": reportHas(
                    discontinuousCatalog,
                    "effect-input-continuity"
                ),
                "duplicate": reportHas(duplicateCatalog, "raw-graph-count"),
                "ambiguousDefinition": reportHas(
                    ambiguousCatalog,
                    "effect-definition-count"
                ),
                "unresolvedCondition": reportHas(
                    unresolvedCatalog,
                    "graph-admission-unresolvedConditionProvider"
                ),
                "missingTemplate": reportHas(
                    missingTemplateCatalog,
                    "material-template-unsupported"
                ),
                "functionInvocation": functionCatalog.claim(layerID: layerID)
                    .flatMap { functionCatalog.resolve($0.token) }?
                    .admittedProducts.first?.clearFunctions
                    .function(named: "reset")?.targets.map(\.name)
                    == ["history"],
                "dynamicVisibility": reportHas(
                    dynamicCatalog,
                    "dynamic-effect-visibility"
                ),
                "validTimeline": validTimelineCatalog.claim(layerID: layerID) != nil,
                "validSceneScript": validSceneScriptCatalog.claim(layerID: layerID) != nil
                    && validSceneScriptCatalog.sceneScriptConsumerTargets
                        == Set([dynamicTarget()]),
                "unknownScript": reportHas(
                    unknownScriptCatalog,
                    "material-dynamic-uniform-script-attachment-unproven"
                ) && unknownScriptCatalog.claim(layerID: layerID) == nil,
                "multipleProducer": reportHas(
                    multipleProducerCatalog,
                    "material-dynamic-uniform-contributor-policy"
                ),
                "multipleProducerNonLeafRemainsRejected":
                    multipleProducerCatalog.claim(layerID: layerID) == nil,
                "multipleProducerPairLeafPassthrough":
                    pairMultipleProducerCapability?.stages.first?
                        .visualFailureReasonCode
                        == "material-dynamic-uniform-contributor-policy",
                "multipleProducerPairLeafCounted":
                    pairMultipleProducerCatalog.reportLines.contains {
                        $0 == "resolved material execution capability fallback:"
                            + " state=prefer-generic"
                            + " outcome=effect-local-passthrough"
                            + " reason=material-dynamic-uniform-contributor-policy"
                            + " count=1"
                    },
                "multipleProducerMissingNonLeafRemainsRejected": reportHas(
                    multipleProducerMissingCatalog,
                    "material-dynamic-uniform-contributor-producer-unavailable"
                ) && multipleProducerMissingCatalog.claim(layerID: layerID) == nil,
                "multipleProducerMissingPairLeafPassthrough":
                    pairMultipleProducerMissingCapability?.stages.first?
                        .visualFailureReasonCode
                        == "material-dynamic-uniform-contributor-producer-unavailable",
                "multipleProducerMissingPairLeafCounted":
                    pairMultipleProducerMissingCatalog.reportLines.contains {
                        $0 == "resolved material execution capability fallback:"
                            + " state=prefer-generic"
                            + " outcome=effect-local-passthrough"
                            + " reason=material-dynamic-uniform-contributor-producer-unavailable"
                            + " count=1"
                    },
                "multipleProducerAllMissingPairLeafPassthrough":
                    pairMultipleProducerAllMissingCapability?.stages.first?
                        .visualFailureReasonCode
                        == "material-dynamic-uniform-contributor-producer-unavailable",
                "multipleProducerMismatchedRemainsHard": reportHas(
                    pairMultipleProducerMismatchedCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairMultipleProducerMismatchedCatalog.claim(layerID: layerID) == nil,
                "multipleProducerAttachmentRemainsHard": reportHas(
                    pairMultipleProducerAttachmentCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairMultipleProducerAttachmentCatalog.claim(layerID: layerID) == nil,
                "unprovenScriptPairLeafPassthrough":
                    pairUnprovenScriptCapability?.stages.first?
                        .visualFailureReasonCode
                        == "material-dynamic-uniform-script-attachment-unproven",
                "unprovenScriptPairLeafCounted":
                    pairUnprovenScriptCatalog.reportLines.contains {
                        $0 == "resolved material execution capability fallback:"
                            + " state=prefer-generic"
                            + " outcome=effect-local-passthrough"
                            + " reason=material-dynamic-uniform-script-attachment-unproven"
                            + " count=1"
                    },
                "scriptOnlyPairLeafPassthrough":
                    pairScriptOnlyCapability?.stages.first?
                        .visualFailureReasonCode
                        == "material-dynamic-uniform-script-attachment-unproven",
                "scriptOnlyPairLeafCounted":
                    pairScriptOnlyCatalog.reportLines.contains {
                        $0 == "resolved material execution capability fallback:"
                            + " state=prefer-generic"
                            + " outcome=effect-local-passthrough"
                            + " reason=material-dynamic-uniform-script-attachment-unproven"
                            + " count=1"
                    },
                "scriptOnlyNoFallbackRemainsHard": reportHas(
                    pairScriptOnlyNoFallbackCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairScriptOnlyNoFallbackCatalog.claim(layerID: layerID) == nil,
                "knownAttachmentWithoutValueRemainsHard": reportHas(
                    pairKnownAttachmentWithoutValueCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairKnownAttachmentWithoutValueCatalog.claim(layerID: layerID) == nil,
                "duplicateScriptOnlyAttachmentRemainsHard": reportHas(
                    pairDuplicateScriptOnlyAttachmentCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairDuplicateScriptOnlyAttachmentCatalog.claim(layerID: layerID) == nil,
                "unprovenScriptMissingProducerRemainsHard": reportHas(
                    pairUnprovenScriptMissingProducerCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairUnprovenScriptMissingProducerCatalog.claim(layerID: layerID) == nil,
                "missingProducerPairLeafPassthrough":
                    pairMissingProducerCapability?.stages.first?
                        .visualFailureReasonCode
                        == "material-dynamic-uniform-producer-unavailable",
                "missingProducerPairLeafCounted":
                    pairMissingProducerCatalog.reportLines.contains {
                        $0 == "resolved material execution capability fallback:"
                            + " state=prefer-generic"
                            + " outcome=effect-local-passthrough"
                            + " reason=material-dynamic-uniform-producer-unavailable"
                            + " count=1"
                    },
                "mismatchedProducerRemainsHard": reportHas(
                    pairMismatchedProducerCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairMismatchedProducerCatalog.claim(layerID: layerID) == nil,
                "duplicateAttachmentRemainsHard": reportHas(
                    pairDuplicateAttachmentCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairDuplicateAttachmentCatalog.claim(layerID: layerID) == nil,
                "knownControlWrongContributorRemainsHard": reportHas(
                    pairKnownControlWrongContributorCatalog,
                    "dynamic-uniform-unavailable"
                ) && pairKnownControlWrongContributorCatalog.claim(layerID: layerID) == nil,
                "missingProducer": reportHas(
                    missingProducerCatalog,
                    "material-dynamic-uniform-producer-unavailable"
                ) && missingProducerCatalog.claim(layerID: layerID) == nil,
                "unverifiedSceneScript": reportHas(
                    unverifiedSceneScriptCatalog,
                    "material-dynamic-uniform-script-attachment-unproven"
                ) && unverifiedSceneScriptCatalog.claim(layerID: layerID) == nil,
                "dedicatedBeforeResolvedAccepted":
                    dedicatedBeforeResolvedCatalog.claim(layerID: layerID) != nil,
                "alternatingMixedOrderAccepted": alternatingCapability != nil,
                "alternatingMixedOrderContract": alternatingCapability.map { capability in
                    let keys = capability.stages.compactMap(\.subject).map(\.key)
                    let families = capability.stages.compactMap(\.subject).map(\.family)
                    let steps = capability.pairPlan.effects
                    let continuous = zip(steps.dropLast(), steps.dropFirst())
                        .allSatisfy { previous, next in
                            previous.outputIdentity == next.inputIdentity
                                && previous.outputMember == next.inputMember
                        }
                    return keys == [firstKey, secondKey, thirdKey, fourthKey]
                        && families == [
                            "fixture-dedicated",
                            "resolved-material",
                            "fixture-dedicated",
                            "resolved-material",
                        ]
                        && steps.map(\.effect) == keys
                        && continuous
                        && capability.pairPlan.terminalOutputIdentity
                            == output(fourthKey)
                        && capability.pairPlan.terminalMember == .zero
                } ?? true,
                "resolvedBeforeDedicated":
                    resolvedBeforeDedicatedCatalog.claim(layerID: layerID) != nil,
                "emptyDedicatedLeafAllowlist":
                    emptyDedicatedLeafCatalog.claim(layerID: layerID) != nil,
                "fallbackDedicatedLeaf": reportHas(
                    fallbackDedicatedLeafCatalog,
                    "dedicated-leaf-unsupported"
                ) && fallbackDedicatedLeafCatalog.claim(layerID: layerID) == nil,
                "emptyDedicatedLeafDoesNotUseDedicated": !reportHas(
                    emptyDedicatedLeafCatalog,
                    "dedicated-leaf-unsupported"
                ),
                "programFirstPrefersResolvedStage":
                    programFirstCatalog.claim(layerID: layerID) != nil
                    && !reportHas(
                        programFirstCatalog,
                        "dedicated-leaf-unsupported"
                    ),
                "inactiveResourceDemandDoesNotRevokeProgram":
                    inactiveDemandIssueCatalog.claim(layerID: layerID) != nil,
                "logicalTargetStageAccepted":
                    logicalCatalog.claim(layerID: layerID) != nil,
                "logicalTargetStageRequiresAllowlist": reportHas(
                    logicalWithoutAllowlist,
                    "dedicated-leaf-unsupported"
                ) && logicalWithoutAllowlist.claim(layerID: layerID) == nil,
                "logicalTargetStageRejectsHistory": reportHas(
                    uniqueLogicalCatalog,
                    "dedicated-leaf-unsupported"
                ) && uniqueLogicalCatalog.claim(layerID: layerID) == nil,
                "logicalTargetStageAcceptsCapturedMain":
                    capturedMainLogicalCapability?.sourceRoute
                        == .capturedMainTargetTexture
                    && capturedMainLogicalCapability?.stages.count == 1
                    && capturedMainLogicalCapability?.materials.isEmpty == true,
                "logicalTargetStageCapturedMainRequiresUtilitySupport": reportHas(
                    capturedMainLogicalWithoutSupportCatalog,
                    "dedicated-leaf-unsupported"
                ) && capturedMainLogicalWithoutSupportCatalog.claim(
                    layerID: layerID
                ) == nil,
                "fullFrameComposeStageAccepted":
                    fullFrameComposeCapability != nil,
                "fullFrameComposeStageContract":
                    fullFrameComposeCapability?.stages.count == 1
                    && fullFrameComposeCapability?.materials.isEmpty == true
                    && fullFrameComposeStep?.nodes.count == 2
                    && fullFrameComposeStep?.composeTransitionCount == 1
                    && fullFrameComposeStep?.fullFrameOutputWriteCount == 2
                    && fullFrameComposeStep?.inputMember
                        == fullFrameComposeStep?.outputMember,
                "fullFrameComposeStageRequiresAllowlist": reportHas(
                    fullFrameComposeWithoutAllowlist,
                    "dedicated-leaf-unsupported"
                ) && fullFrameComposeWithoutAllowlist.claim(layerID: layerID) == nil,
                "fullFrameComposeStageRejectsCapturedMain": reportHas(
                    capturedMainComposeCatalog,
                    "dedicated-leaf-unsupported"
                ) && capturedMainComposeCatalog.claim(layerID: layerID) == nil,
                "fullFrameComposeStageRejectsHistory":
                    historyComposeCatalog.claim(layerID: layerID) == nil,
                "fullFrameComposeStageRejectsMissingCompose":
                    missingComposeCatalog.claim(layerID: layerID) == nil,
                "fullFrameComposeStageRejectsExtraNode":
                    extraNodeComposeCatalog.claim(layerID: layerID) == nil,
                "externalResolvedMaterialAccepted":
                    externalResolvedMaterialCapability?.stages.count == 1,
                "externalResolvedMaterialRejectsSecondary": reportHas(
                    secondaryExternalResolvedMaterial,
                    "execution-route-dependency-owner"
                ),
                "externalResolvedMaterialRejectsWrongSlot": reportHas(
                    wrongSlotExternalResolvedMaterial,
                    "execution-route-dependency-owner"
                ),
                "externalResolvedMaterialRejectsWrongDependencyID": reportHas(
                    wrongDependencyIDExternalResolvedMaterial,
                    "execution-route-dependency-owner"
                ),
                "externalResolvedMaterialRejectsAuthoredDependency": reportHas(
                    authoredDependencyExternalResolvedMaterial,
                    "execution-route-dependency-owner"
                ),
                "externalResolvedMaterialAcceptsMultipleReferences":
                    !reportHas(
                        extraReferenceExternalResolvedMaterial,
                        "execution-route-dependency-owner"
                    ),
                "externalResolvedMaterialRejectsProceduralBinding": reportHas(
                    proceduralExternalResolvedMaterial,
                    "execution-route-dependency-owner"
                ),
                "resolvedMaterialRejectsMissingExternalOwnership": reportHas(
                    resolvedMaterialWithoutOwnership,
                    "execution-stage-conservation"
                ),
                "externalResolvedMaterialDoesNotFallback": reportHas(
                    resolvedMaterialWithoutProgram,
                    "material-template-unsupported"
                ),
                "externalProceduralAccepted":
                    externalProceduralCapability?.stages.count == 1,
                "externalProceduralRejectsModern": reportHas(
                    modernExternalProcedural,
                    "execution-stage-conservation"
                ),
                "externalProceduralRejectsWrongProvider": reportHas(
                    wrongProviderExternalProcedural,
                    "execution-stage-conservation"
                ),
                "externalProceduralRejectsSecondary": reportHas(
                    secondaryExternalProcedural,
                    "execution-route-dependency-owner"
                ),
                "externalProceduralRejectsWrongEffect": reportHas(
                    wrongEffectExternalProcedural,
                    "execution-stage-conservation"
                ),
                "externalProceduralRejectsWrongPass": reportHas(
                    wrongPassExternalProcedural,
                    "execution-route-dependency-owner"
                ),
                "externalProceduralRejectsWrongSlot": reportHas(
                    wrongSlotExternalProcedural,
                    "execution-route-dependency-owner"
                ),
                "externalProceduralRejectsWrongBlend": reportHas(
                    wrongBlendExternalProcedural,
                    "execution-route-dependency-owner"
                ),
                "externalProceduralRejectsMissingOwnership": reportHas(
                    missingExternalProceduralOwnership,
                    "execution-stage-conservation"
                ),
                "externalProceduralRejectsExtraReference": reportHas(
                    extraReferenceExternalProcedural,
                    "execution-route-dependency-owner"
                ),
                "externalProceduralRejectsExtraProvider": reportHas(
                    extraProviderExternalProcedural,
                    "execution-route-dependency-owner"
                ),
                "externalProceduralRejectsMissingProviderPlan": reportHas(
                    providerlessExternalProcedural,
                    "execution-stage-conservation"
                ),
                "externalProceduralRejectsWrongInput": reportHas(
                    wrongInputExternalProcedural,
                    "execution-stage-conservation"
                ),
                "externalProceduralRequiresUtilitySupport": reportHas(
                    unsupportedCaptureExternalProcedural,
                    "dedicated-leaf-unsupported"
                ),
                "userPropertyLiveTarget":
                    validUserPropertyCatalog.liveConsumerTargets
                    == Set([dynamicTarget()]),
                "hiddenParent": admissionRejects(
                    descriptor(parentVisible: false),
                    raw: raw,
                    reason: "execution-route-layer-hidden"
                ),
                "unsupportedContent": admissionRejects(
                    descriptor(contentKind: "particle"),
                    raw: raw,
                    reason: "execution-route-content-kind"
                ),
                "utilityCapture": utilityRoute == .capturedMainTargetTexture,
                "projectUtilityNonAudioAccepted":
                    projectUtilityCatalog.claim(layerID: layerID) != nil,
                "utilityAdapterAccepted":
                    utilityAdapterCapability != nil,
                "utilityAdapterContract": utilityAdapterCapability.map { capability in
                    let subjects = capability.stages.compactMap(\.subject)
                    return capability.sourceRoute == .capturedMainTargetTexture
                        && subjects.map(\.key) == [firstKey, secondKey]
                        && subjects.map(\.family) == ["resolved-material", "opacity"]
                        && capability.stages.count == 2
                        && capability.materials.keys.allSatisfy {
                            $0.effect == firstKey
                        }
                } ?? false,
                "downstreamUtilityAdapterAcceptedWithoutSourceCapture":
                    downstreamUtilityAdapterCatalog.claim(layerID: layerID) != nil,
                "resolvedUtilityChainAccepted":
                    resolvedUtilityChainCatalog.claim(layerID: layerID).flatMap {
                        resolvedUtilityChainCatalog.resolve($0.token)
                    }?.stages.count == 2,
                "utilityKindMismatch": admissionRejects(
                    descriptor(utilityLayer: "composition"),
                    raw: raw,
                    reason: "execution-route-utility-shape"
                ),
                "utilityChildren": admissionRejects(
                    descriptor(
                        contentKind: "composition",
                        utilityLayer: "composition",
                        childLayerIDs: [42]
                    ),
                    raw: raw,
                    reason: "execution-route-utility-shape"
                ),
                "legacyDependency": admissionRejects(
                    descriptor(dependencyLayerIDs: [42]),
                    raw: raw,
                    reason: "execution-route-dependency-owner"
                ),
                "authoredDependency": admissionRejects(
                    descriptor(authoredDependencies: [42]),
                    raw: raw,
                    reason: "execution-route-dependency-owner"
                ),
                "namedReference": admissionRejects(
                    descriptor(namedReferences: [namedReference()]),
                    raw: raw,
                    reason: "execution-route-dependency-owner"
                ),
                "selfReferenceMissingPrior": admissionRejects(
                    descriptor(
                        dependencyLayerIDs: [layerID],
                        namedReferences: [namedReference(effectID: firstKey.descriptorID)]
                    ),
                    raw: raw,
                    reason: "execution-route-dependency-owner"
                ),
                "selfReferenceSecondary": admissionRejects(
                    descriptor(
                        dependencyLayerIDs: [layerID],
                        namedReferences: [namedReference(variant: .secondary)]
                    ),
                    raw: raw,
                    reason: "execution-route-dependency-owner"
                ),
                "selfReferenceWrongSlot": admissionRejects(
                    descriptor(
                        dependencyLayerIDs: [layerID],
                        namedReferences: [namedReference(slotIndex: 1)]
                    ),
                    raw: raw,
                    reason: "execution-route-dependency-owner"
                ),
                "selfReferenceExternalExtra": admissionRejects(
                    descriptor(
                        dependencyLayerIDs: [layerID],
                        namedReferences: [
                            namedReference(),
                            namedReference(providerLayerID: 42, slotIndex: 1),
                        ]
                    ),
                    raw: raw,
                    reason: "execution-route-dependency-owner"
                ),
                "selfReferenceAuthoredExtra": admissionRejects(
                    descriptor(
                        dependencyLayerIDs: [layerID],
                        authoredDependencies: [layerID],
                        namedReferences: [namedReference()]
                    ),
                    raw: raw,
                    reason: "execution-route-dependency-owner"
                ),
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


ENVELOPE_SUPPORT = PROGRAM_FINALIZER_FIXTURE["SUPPORT"] + r'''

enum SceneDependencyRenderPlan {
    struct Binding: Hashable {
        enum Kind: Hashable {
            case resolvedMaterial, proceduralNoiseLayer, imageLayerBlend
        }
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
        }
    }
}

enum SceneResolvedMaterialDependencyOwnership: Equatable {
    case none
    case graphInternal(referenceCount: Int)
    case externalPrimary(SceneDependencyRenderPlan.Binding)

    var reportKind: String {
        switch self {
        case .none: "none"
        case .graphInternal: "graph-internal"
        case .externalPrimary: "external-primary"
        }
    }

    var referenceCount: Int {
        switch self {
        case .none: 0
        case let .graphInternal(referenceCount): referenceCount
        case let .externalPrimary(binding): binding.referenceSlots.count
        }
    }
}

struct SceneOpacityExecutionPlan {}
struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}
struct SceneDepthParallaxExecutionPlan {}
struct SceneXRayExecutionPlan {}
struct SceneProceduralNoiseExecutionPlan {
    enum Variant { case colorPerlinRGB, worleyColorV1 }
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let variant: Variant
    let dependencyProviderLayerID: Int?
    let dependencySlotIndex: Int?
}
struct SceneBlendExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let dependencyProviderLayerID: Int?
}
struct HarnessDedicatedAudioExecutionPlan { let audio: Bool? }

struct SceneEffectStageExecutionPlan {
    let logicalRenderTargetCount: Int
    let opacity: SceneOpacityExecutionPlan?
    var layerID: Int { 0 }
    var materialNodeCount: Int { 0 }
    var cursorRipple: SceneCursorRippleExecutionPlan? = nil
    var depthParallax: SceneDepthParallaxExecutionPlan? = nil
    var xRay: SceneXRayExecutionPlan? = nil
    var inputRole: SceneAuthoredEffectInputRole { .layerSource }
    var proceduralNoise: SceneProceduralNoiseExecutionPlan? { nil }
    var blend: SceneBlendExecutionPlan? { nil }
    var supportsUnifiedLogicalTargetStage = false
    var supportsUnifiedHistoryTargetStage = false
    var supportsUnifiedFullFrameComposeStage = false
    var supportsUtilityCapture = true
    var shake: HarnessDedicatedAudioExecutionPlan? { nil }
    var pulse: HarnessDedicatedAudioExecutionPlan? { nil }
    var workshopAudioBars: SceneOpacityExecutionPlan? { nil }
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

struct SceneEffectStageProgram {
    typealias ExecutionPlan = SceneEffectStageExecutionPlan

    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let stageGraph: SceneAuthoredEffectRenderPlan
    let executionPlan: ExecutionPlan
    var inputRole: SceneAuthoredEffectInputRole { executionPlan.inputRole }
}

struct SceneEffectExactRuntimeSubject: Hashable {
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let family: String
}

struct SceneGraphAdmissionProduct {
    let graph: SceneAuthoredEffectRenderPlan
    let clearFunctions = SceneGraphClearFunctionRegistry()
}

struct SceneGraphClearFunctionRegistry {
    let functions: [Int] = []
}

struct SceneLayerFullFramePairPlan {
    struct EffectStep {
        let effect: SceneAuthoredEffectRenderPlan.EffectKey
        let composeTransitionCount: Int
        let fullFrameOutputWriteCount: Int
        let inputMember: Int
        let outputMember: Int
    }

    let baseCaptureIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
    let effects: [EffectStep] = []
}

struct SceneResolvedMaterialAdmittedLayer {
    enum SourceRoute: Equatable {
        case capturedLayerTexture
        case capturedMainTargetTexture
        case transparentDirectDraw
    }

    let layerID: Int
    let products: [SceneGraphAdmissionProduct]
    let pairPlan: SceneLayerFullFramePairPlan
    let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
    let sourceRoute: SourceRoute
}

enum SceneResolvedMaterialExecutionCapabilityAdmission {
    struct Failure: Error { let code: String }

    struct Candidate {
        let layerID: Int
        let result: Result<SceneResolvedMaterialAdmittedLayer, Failure>
        let dedicatedStagePrograms: [SceneEffectStageProgram]

        init(
            layerID: Int,
            result: Result<SceneResolvedMaterialAdmittedLayer, Failure>,
            dedicatedStagePrograms: [SceneEffectStageProgram] = []
        ) {
            self.layerID = layerID
            self.result = result
            self.dedicatedStagePrograms = dedicatedStagePrograms
        }
    }
}

struct SceneResolvedMaterialRuntimeCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct Key: Hashable {
        let effect: Graph.EffectKey
        let nodeIndex: Int
    }

    enum Entry {
        case template(SceneResolvedMaterialTemplate)
        case failure(SceneResolvedMaterialFailure)
    }

    struct ResourceDemandIssue: Hashable {
        let key: Key
        let slot: Int
    }

    let entries: [Key: Entry]
    let resourceDemandIssues: Set<ResourceDemandIssue>

    func entry(for node: Graph.Node) -> Entry? {
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)]
    }
}
'''


ENVELOPE_HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Catalog = SceneResolvedMaterialExecutionCapabilityCatalog
private typealias Template = SceneResolvedMaterialTemplate

private let layerID = 981
private let effectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "envelope"
)
private let previousEffectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: -1,
    descriptorID: "previous-envelope"
)

private func vertexSource(
    matrixUniform: String? = nil,
    usesMatrixUniform: Bool = true
) -> String {
    let declaration = matrixUniform.map { "uniform mat4 \($0);" } ?? ""
    let position = (usesMatrixUniform ? matrixUniform : nil).map {
        "mul(vec4(a_Position, 1.0), \($0))"
    } ?? "vec4(a_Position, 1.0)"
    return """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    \(declaration)
    void main() {
        v_TexCoord = a_TexCoord;
        gl_Position = \(position);
    }
    """
}

private func fragmentSource(
    comboMetadata: String? = nil,
    firstMetadata: String? = nil,
    secondMetadata: String? = nil,
    conditionalSecond: Bool = false,
    frontendInvalid: Bool = false,
    invalidSamplerSlot: Bool = false,
    colorUnproven: Bool = false,
    alphaReplacement: Bool = false,
    sourceAlphaFactor: Bool = false,
    scalarAlphaAuxiliaries: Bool = false,
    wholeColorFilter: Bool = false,
    samplesSecond: Bool = true,
    observesSecond: Bool = false,
    maskedAlpha: Bool = false,
    unconditionalMaskedAlpha: Bool = false,
    transparentDirectDraw: Bool = false,
    audioDirectDraw: Bool = false,
    opaqueSecondGraph: Bool = false,
    independentAlphaSignal: Bool = false,
    variantMixedSource: Bool = false,
    activePass: Bool = false
) -> String {
    let comboAnnotation = comboMetadata.map { "// \($0)" } ?? ""
    let varyingType = frontendInvalid ? "vec3" : "vec2"
    let firstName = invalidSamplerSlot ? "g_Texture8" : "g_Texture0"
    let firstAnnotation = firstMetadata.map { " // \($0)" } ?? ""
    let rawSecondDeclaration = secondMetadata.map {
        "uniform sampler2D g_Texture1; // \($0)"
    } ?? ""
    let secondDeclaration = conditionalSecond
        ? "#if EXTRA\n\(rawSecondDeclaration)\n#endif"
        : rawSecondDeclaration
    let passAnnotation = activePass
        ? "// [PASS] 1 fixtures/unsupported-pass.frag"
        : ""
    let scalarDeclarations = scalarAlphaAuxiliaries ? """
    uniform sampler2D g_Texture1; // {"default":"util/noise"}
    uniform sampler2D g_Texture3; // {"mode":"opacitymask"}
    """ : ""
    let output: String
    let helper: String
    if wholeColorFilter {
        helper = """
        vec4 TestFilter(vec2 uv, float mask) {
            vec4 center = texSample2D(g_Texture0, uv);
            vec4 neighbor = texSample2D(g_Texture0, uv + vec2(0.25));
            vec4 lowpass = (center + neighbor) / 2.0;
            vec4 filtered = (1.0 + mask) * center - mask * lowpass;
            return filtered;
        }
        """
    } else {
        helper = ""
    }
    if variantMixedSource {
        output = """
        #if EXTRA
        vec4 source = texSample2D(\(firstName), v_TexCoord);
        float auxiliary = texSample2D(g_Texture1, v_TexCoord).r;
        gl_FragColor = vec4(source.rgb * auxiliary, 1.0);
        #else
        gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0);
        #endif
        """
    } else if independentAlphaSignal {
        output = """
        vec4 sample = texSample2D(\(firstName), v_TexCoord);
        sample.rgb *= sample.a;
        sample.a = 1.0;
        gl_FragColor = sample * 0.5;
        gl_FragColor.a *= 0.25;
        """
    } else if opaqueSecondGraph {
        output = """
        vec4 source = texSample2D(\(firstName), v_TexCoord);
        float second = texSample2D(g_Texture1, v_TexCoord).r;
        gl_FragColor = vec4(source.rgb * second, 1.0);
        """
    } else if audioDirectDraw {
        output = """
        float amplitude = g_AudioSpectrum16Left[0];
        gl_FragColor = vec4(amplitude, amplitude, amplitude, 1.0);
        """
    } else if transparentDirectDraw {
        output = """
        #if DIRECTDRAW
        gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0);
        #else
        gl_FragColor = texSample2D(\(firstName), v_TexCoord);
        #endif
        """
    } else if maskedAlpha {
        let mask = unconditionalMaskedAlpha ? """
        float mask = texSample2D(g_Texture1, v_TexCoord).r;
        color.a *= mask * 0.5;
        """ : """
        #if MASK
        float mask = texSample2D(g_Texture1, v_TexCoord).r;
        color.a *= mask * 0.5;
        #endif
        """
        output = """
        vec4 color = texSample2D(\(firstName), v_TexCoord);
        \(mask)
        gl_FragColor = color;
        """
    } else if alphaReplacement {
        output = "vec4 source = texSample2D(\(firstName), v_TexCoord);"
            + " float alpha = 0.5;"
            + " gl_FragColor = vec4(source.rgb, alpha);"
    } else if scalarAlphaAuxiliaries {
        output = """
        vec4 sampled = texSample2D(g_Texture0, v_TexCoord);
        vec4 color = sampled;
        float pulse = 0.0;
        float phase = texSample2D(g_Texture3, v_TexCoord).r * 6.0;
        pulse = smoothstep(0.0, 1.0, sin(phase) * 0.5 + 0.5);
        float noise = texSample2D(g_Texture1, v_TexCoord).r * 0.5;
        pulse += noise;
        pulse = pow(pulse, 1.0);
        color.a *= pulse;
        gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);
        """
    } else if sourceAlphaFactor {
        output = "vec4 source = texSample2D(\(firstName), v_TexCoord);"
            + " float coverage = 0.5; float alpha = source.a * coverage;"
            + " gl_FragColor = vec4(source.rgb, alpha);"
    } else if wholeColorFilter {
        output = "vec4 source = texSample2D(g_Texture0, v_TexCoord);"
            + " float mask = texSample2D(g_Texture1, v_TexCoord).r;"
            + " if (mask > 0.1) source = TestFilter(v_TexCoord, mask);"
            + " gl_FragColor = source;"
    } else if colorUnproven {
        output = "gl_FragColor = texSample2D(\(firstName), v_TexCoord) * 0.5;"
    } else if observesSecond {
        output = "float observed = texSample2D(g_Texture1, v_TexCoord).r;"
            + " gl_FragColor = texSample2D(\(firstName), v_TexCoord);"
    } else if secondMetadata == nil || !samplesSecond {
        output = "gl_FragColor = texSample2D(\(firstName), v_TexCoord);"
    } else if conditionalSecond {
        output = """
        #if EXTRA
        vec4 color = texSample2D(\(firstName), v_TexCoord);
        float auxiliary = texSample2D(g_Texture1, v_TexCoord).r;
        color.a *= auxiliary;
        gl_FragColor = color;
        #else
        gl_FragColor = texSample2D(\(firstName), v_TexCoord);
        #endif
        """
    } else {
        output = "gl_FragColor = texSample2D(\(firstName), v_TexCoord)"
            + " * texSample2D(g_Texture1, v_TexCoord);"
    }
    return """
    \(passAnnotation)
    \(comboAnnotation)
    varying \(varyingType) v_TexCoord;
    uniform sampler2D \(firstName);\(firstAnnotation)
    \(audioDirectDraw ? "uniform float g_AudioSpectrum16Left[16];" : "")
    \(secondDeclaration)
    \(scalarDeclarations)
    \(helper)
    void main() {
        \(output)
    }
    """
}

private func contract(
    _ revision: String,
    comboMetadata: String? = nil,
    firstMetadata: String? = nil,
    secondMetadata: String? = nil,
    conditionalSecond: Bool = false,
    frontendInvalid: Bool = false,
    invalidSamplerSlot: Bool = false,
    colorUnproven: Bool = false,
    alphaReplacement: Bool = false,
    sourceAlphaFactor: Bool = false,
    scalarAlphaAuxiliaries: Bool = false,
    wholeColorFilter: Bool = false,
    samplesSecond: Bool = true,
    observesSecond: Bool = false,
    maskedAlpha: Bool = false,
    unconditionalMaskedAlpha: Bool = false,
    transparentDirectDraw: Bool = false,
    audioDirectDraw: Bool = false,
    opaqueSecondGraph: Bool = false,
    independentAlphaSignal: Bool = false,
    variantMixedSource: Bool = false,
    activePass: Bool = false,
    vertexMatrixUniform: String? = nil,
    usesVertexMatrixUniform: Bool = true
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
    let fragment = fragmentSource(
        comboMetadata: comboMetadata,
        firstMetadata: firstMetadata,
        secondMetadata: secondMetadata,
        conditionalSecond: conditionalSecond,
        frontendInvalid: frontendInvalid,
        invalidSamplerSlot: invalidSamplerSlot,
        colorUnproven: colorUnproven,
        alphaReplacement: alphaReplacement,
        sourceAlphaFactor: sourceAlphaFactor,
        scalarAlphaAuxiliaries: scalarAlphaAuxiliaries,
        wholeColorFilter: wholeColorFilter,
        samplesSecond: samplesSecond,
        observesSecond: observesSecond,
        maskedAlpha: maskedAlpha,
        unconditionalMaskedAlpha: unconditionalMaskedAlpha,
        transparentDirectDraw: transparentDirectDraw,
        audioDirectDraw: audioDirectDraw,
        opaqueSecondGraph: opaqueSecondGraph,
        independentAlphaSignal: independentAlphaSignal,
        variantMixedSource: variantMixedSource,
        activePass: activePass
    )
    let stages = [
        stage(
            .vertex,
            path: "\(revision)/root.vert",
            source: vertexSource(
                matrixUniform: vertexMatrixUniform,
                usesMatrixUniform: usesVertexMatrixUniform
            )
        ),
        stage(.fragment, path: "\(revision)/root.frag", source: fragment),
    ]
    return .init(
        identity: "fixture/\(revision)",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-contract-\(revision)",
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "\(revision)/root.vert"),
                .init(label: "fragment", virtualPath: "\(revision)/root.frag"),
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
            dependencySHA256: "fixture-dependency-\(revision)"
        )
    )
}

private func fixtureSampler(
    slot: Int,
    name: String? = nil
) -> SceneResolvedMaterialShaderSchema.Sampler {
    .init(
        name: name ?? "g_Texture\(slot)",
        slot: slot,
        mode: .regular,
        materialKey: nil,
        isHidden: false,
        defaultTexture: nil,
        readinessCombo: nil
    )
}

private func fixtureBinding(
    slot: Int,
    name: String? = nil
) -> SceneAuthoredShaderProgram.TextureBinding {
    .init(
        name: name ?? "g_Texture\(slot)",
        slot: slot,
        channelUse: .unproven
    )
}

private func materialFailureToken(_ failure: SceneResolvedMaterialFailure) -> String {
    ([
        failure.phase.rawValue,
        failure.code.rawValue,
        failure.slot.map(String.init) ?? "none",
    ] + failure.boundedDetails).joined(separator: ":")
}

private func samplerBindingToken(
    samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
    bindings: [SceneAuthoredShaderProgram.TextureBinding]
) -> String {
    do {
        try SceneResolvedMaterialVariantCache.validateSamplerBindings(
            samplers,
            bindings: bindings
        )
        return "success"
    } catch let failure as SceneResolvedMaterialFailure {
        return materialFailureToken(failure)
    } catch {
        return "unexpected"
    }
}

private func samplerVariantSchemaToken(
    _ schemas: [(
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        bindings: [SceneAuthoredShaderProgram.TextureBinding]
    )]
) -> String {
    SceneResolvedMaterialVariantCache.samplerVariantSchemaFailure(schemas)
        .map(materialFailureToken) ?? "success"
}

private func launchEnvelopeToken(
    template: Template,
    implicitFramebufferIdentity: Graph.TextureIdentity?
) -> String {
    let cache: SceneResolvedMaterialVariantCache
    switch SceneResolvedMaterialVariantCache.launchValidated(
        template: template,
        maximumVariantCount: 16
    ) {
    case let .success(value): cache = value
    case let .failure(failure): return materialFailureToken(failure)
    }
    switch cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: implicitFramebufferIdentity
    ) {
    case .success: return "success"
    case .failure(.capacity): return "capacity"
    case let .failure(.material(failure)): return materialFailureToken(failure)
    }
}

private func source() -> Graph.TextureIdentity {
    .init(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
}

private func output() -> Graph.TextureIdentity {
    .init(
        kind: .effectOutput,
        layerID: layerID,
        effect: effectKey,
        name: nil
    )
}

private func previousOutput() -> Graph.TextureIdentity {
    .init(
        kind: .effectOutput,
        layerID: layerID,
        effect: previousEffectKey,
        name: nil
    )
}

private func graph(
    withPrimaryBinding: Bool,
    withSecondGraphBinding: Bool = false,
    materialCount: Int = 1,
    input: Graph.TextureIdentity? = nil,
    nodeTarget: Graph.TextureIdentity? = nil
) -> Graph {
    let graphInput = input ?? source()
    let target = nodeTarget ?? output()
    var bindings: [Graph.Binding] = withPrimaryBinding ? [
        .init(
            slot: 0,
            authoredName: "previous",
            texture: graphInput,
            conditions: nil
        ),
    ] : []
    if withSecondGraphBinding {
        bindings.append(.init(
            slot: 1,
            authoredName: "second-previous",
            texture: graphInput,
            conditions: nil
        ))
    }
    let nodes = (0 ..< materialCount).map { index in
        Graph.Node(
            nodeIndex: index,
            effect: effectKey,
            definitionPassIndex: index,
            materialOrdinal: index,
            instancePassIndex: index,
            kind: .material,
            materialPath: "materials/envelope-\(index).json",
            materialPassID: "envelope-\(index)",
            target: target,
            bindings: bindings,
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effectKey,
            definitionPath: "effects/envelope/effect.json",
            input: graphInput,
            output: output(),
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: target.kind == .framebuffer ? [
            .init(
                texture: target,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba8888",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            ),
        ] : [],
        nodes: nodes,
        finalOutput: output(),
        blockers: []
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

private func graphCandidate() -> Template.TextureCandidate {
    .init(reference: .graph(source()), provenance: .explicitBinding)
}

private func assetCandidate(_ path: String) -> Template.TextureCandidate {
    .init(
        reference: .asset(SceneVFSAssetPath(path)!),
        provenance: .instance
    )
}

private func userPropertyCandidate(_ key: String) -> Template.TextureCandidate {
    .init(reference: .userProperty(.init(key: key)), provenance: .instance)
}

private func namedTargetCandidate(
    providerLayerID: Int,
    variant: SceneNamedTextureReference.Variant = .primary
) -> Template.TextureCandidate {
    .init(
        reference: .provider(.namedLayerTarget(.init(
            providerLayerID: providerLayerID,
            variant: variant
        ))),
        provenance: .instance
    )
}

private func systemCandidate(_ name: String) -> Template.TextureCandidate {
    .init(reference: .provider(.system(name)), provenance: .instance)
}

private func materialTemplate(
    graph: Graph,
    nodeIndex: Int = 0,
    shader: SceneShaderContract,
    slots: [Template.TextureSlot?],
    combos: [Template.Combo] = [],
    nodeTarget: Template.GraphTextureRole = .effectOutput
) -> Template {
    let node = graph.nodes[nodeIndex]
    let inputRole: Template.GraphTextureRole = switch graph.effects[0].input.kind {
    case .layerSource: .layerSource
    case .effectOutput: .effectOutput
    case .framebuffer: .framebuffer
    case .unresolved: .layerSource
    }
    return Template.validated(
        textureSlots: slots,
        combos: combos,
        uniformDeclarations: [],
        renderState: state(),
        graphRole: .init(
            effectInput: inputRole,
            effectOutput: .effectOutput,
            nodeTarget: nodeTarget,
            bindings: node.bindings.map {
                .init(slot: $0.slot!, texture: inputRole)
            }
        ),
        shaderContract: shader,
        diagnosticProvenance: .init(
            nodeIndex: node.nodeIndex,
            authoredShaderPath: shader.identity,
            contractIdentity: shader.identity,
            contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
}

private func slots(
    primary: Template.TextureCandidate? = nil,
    second: Template.TextureCandidate? = nil,
    fourth: Template.TextureCandidate? = nil
) -> [Template.TextureSlot?] {
    var result = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    if let primary {
        result[0] = .init(index: 0, candidates: [primary])
    }
    if let second {
        result[1] = .init(index: 1, candidates: [second])
    }
    if let fourth {
        result[3] = .init(index: 3, candidates: [fourth])
    }
    return result
}

private func secondCandidates(
    _ candidates: [Template.TextureCandidate]
) -> [Template.TextureSlot?] {
    var result = slots(primary: graphCandidate())
    result[1] = .init(index: 1, candidates: candidates)
    return result
}

private func catalog(
    graph: Graph,
    template: Template,
    maximumVariants: Int = 16,
    sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute = .capturedLayerTexture,
    dependencyOwnership: SceneResolvedMaterialDependencyOwnership = .none,
    assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:],
    demandIssueSlots: Set<Int> = []
) -> Catalog {
    catalog(
        graph: graph,
        templates: [graph.nodes[0].nodeIndex: template],
        maximumVariants: maximumVariants,
        sourceRoute: sourceRoute,
        dependencyOwnership: dependencyOwnership,
        assetStates: assetStates,
        demandIssueSlots: demandIssueSlots
    )
}

private func catalog(
    graph: Graph,
    templates: [Int: Template],
    maximumVariants: Int = 16,
    sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute = .capturedLayerTexture,
    dependencyOwnership: SceneResolvedMaterialDependencyOwnership = .none,
    assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:],
    demandIssueSlots: Set<Int> = []
) -> Catalog {
    let entries = Dictionary(uniqueKeysWithValues: templates.map { nodeIndex, template in
        (
            SceneResolvedMaterialRuntimeCatalog.Key(
                effect: effectKey,
                nodeIndex: nodeIndex
            ),
            SceneResolvedMaterialRuntimeCatalog.Entry.template(template)
        )
    })
    let admitted = SceneResolvedMaterialAdmittedLayer(
        layerID: layerID,
        products: [.init(graph: graph)],
        pairPlan: .init(baseCaptureIdentity: graph.effects[0].input),
        dependencyOwnership: dependencyOwnership,
        sourceRoute: sourceRoute
    )
    return .init(
        admissionCandidates: [.init(
            layerID: layerID,
            result: .success(admitted)
        )],
        materialCatalog: .init(
            entries: entries,
            resourceDemandIssues: Set(templates.keys.flatMap { nodeIndex in
                demandIssueSlots.map { slot in
                    SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue(
                        key: .init(effect: effectKey, nodeIndex: nodeIndex),
                        slot: slot
                    )
                }
            })
        ),
        assetStates: assetStates,
        maximumVariantsPerMaterial: maximumVariants
    )
}

private func rejection(_ catalog: Catalog) -> String {
    catalog.reportLines.first(where: { $0.contains("rejection:") }) ?? ""
}

private func summary(_ catalog: Catalog) -> String {
    catalog.reportLines.first ?? ""
}

private func acceptedRouteCount(_ catalog: Catalog) -> Int {
    catalog.reportLines.filter { $0.contains("status=accepted") }.count
}

private func requiresInvertibleEffectTextureProjection(
    _ catalog: Catalog
) -> Bool? {
    guard let claim = catalog.claim(layerID: layerID),
          let capability = catalog.resolve(claim.token) else { return nil }
    return capability.requiresInvertibleEffectTextureProjection
}

private func dedicatedCatalog(
    graph: Graph,
    pointerSensitive: Bool
) -> Catalog {
    let admitted = SceneResolvedMaterialAdmittedLayer(
        layerID: layerID,
        products: [.init(graph: graph)],
        pairPlan: .init(baseCaptureIdentity: graph.effects[0].input),
        dependencyOwnership: .none,
        sourceRoute: .capturedLayerTexture
    )
    let program = SceneEffectStageProgram(
        effectKey: effectKey,
        stageGraph: graph,
        executionPlan: .init(
            logicalRenderTargetCount: 0,
            opacity: pointerSensitive ? nil : .init(),
            cursorRipple: pointerSensitive
                ? .init(effectKey: effectKey) : nil
        )
    )
    return .init(
        admissionCandidates: [.init(
            layerID: layerID,
            result: .success(admitted),
            dedicatedStagePrograms: [program]
        )],
        materialCatalog: .init(entries: [:], resourceDemandIssues: []),
        dedicatedStageFamilies: [effectKey: "fixture-dedicated"],
        dedicatedLeafKeys: [effectKey]
    )
}

private func counters(_ catalog: Catalog, graph: Graph) -> [String: Int] {
    guard let claim = catalog.claim(layerID: layerID),
          let capability = catalog.resolve(claim.token),
          let material = capability.material(for: graph.nodes[0]) else { return [:] }
    let value = material.variants.counters
    return [
        "cached": value.cachedVariantCount,
        "prepared": value.shaderPreparationCount,
        "frontend": value.frontendCompilationCount,
        "capacity": value.capacityRejectionCount,
    ]
}

private func compiledChannelUseCount(
    _ catalog: Catalog,
    graph: Graph,
    slot: Int
) -> Int {
    guard let claim = catalog.claim(layerID: layerID),
          let capability = catalog.resolve(claim.token),
          let material = capability.material(for: graph.nodes[0]) else { return -1 }
    return material.variants.compiledChannelUses(for: slot)?.count ?? -1
}

@main
private enum EnvelopeHarness {
    static func main() throws {
        // This harness validates bounded envelope/capacity behavior without the
        // signed generic compiler bundle. Use the registered rollback instead
        // of depending on compiler failure to restore a migrated old owner.
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        let boundGraph = graph(withPrimaryBinding: true)
        let unboundGraph = graph(withPrimaryBinding: false)

        let positive = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("positive"),
                slots: slots(primary: graphCandidate())
            )
        )
        let modelViewProjectionOnly = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "model-view-projection-only",
                    vertexMatrixUniform: "g_ModelViewProjectionMatrix"
                ),
                slots: slots(primary: graphCandidate())
            )
        )
        let effectProjectionForward = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "effect-projection-forward",
                    vertexMatrixUniform: "g_EffectTextureProjectionMatrix"
                ),
                slots: slots(primary: graphCandidate())
            )
        )
        let unusedEffectProjectionDeclaration = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "effect-projection-unused",
                    vertexMatrixUniform: "g_EffectTextureProjectionMatrix",
                    usesVertexMatrixUniform: false
                ),
                slots: slots(primary: graphCandidate())
            )
        )
        let effectProjectionInverse = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "effect-projection-inverse",
                    vertexMatrixUniform:
                        "g_EffectTextureProjectionMatrixInverse"
                ),
                slots: slots(primary: graphCandidate())
            )
        )
        let ordinaryDedicatedProjectionRequirement = dedicatedCatalog(
            graph: boundGraph,
            pointerSensitive: false
        )
        let pointerDedicatedProjectionRequirement = dedicatedCatalog(
            graph: boundGraph,
            pointerSensitive: true
        )
        guard case let .success(uncompiledProjectionCache) =
                SceneResolvedMaterialVariantCache.launchValidated(
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("projection-uncompiled"),
                slots: slots(primary: graphCandidate())
            ),
            maximumVariantCount: 16
        ) else { fatalError("projection cache rejected") }
        let uncompiledProjectionRequirement = uncompiledProjectionCache
            .requiresInvertibleEffectTextureProjection
        let shaderFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "shader-failure",
                    firstMetadata: #"{"combo":"SOURCE_READY"}"#
                ),
                slots: slots(primary: graphCandidate()),
                combos: [.init(name: "SOURCE_READY", value: 0)]
            )
        )
        let frontendFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("frontend-failure", frontendInvalid: true),
                slots: slots(primary: graphCandidate())
            )
        )
        let samplerSchemaFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("schema-failure", invalidSamplerSlot: true),
                slots: slots(primary: graphCandidate())
            )
        )
        let internalSamplerTemplate = materialTemplate(
            graph: boundGraph,
            shader: contract(
                "internal-sampler-target",
                firstMetadata: #"{"default":"_rt_fixture"}"#
            ),
            slots: slots(primary: graphCandidate())
        )
        let internalSamplerTarget = catalog(
            graph: boundGraph,
            template: internalSamplerTemplate
        )
        let activePassTemplate = materialTemplate(
            graph: boundGraph,
            shader: contract("active-pass", activePass: true),
            slots: slots(primary: graphCandidate())
        )
        let activePass = catalog(
            graph: boundGraph,
            template: activePassTemplate
        )
        let colorFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("color-failure", colorUnproven: true),
                slots: slots(primary: graphCandidate())
            )
        )
        let typedColorFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "typed-color-failure",
                    alphaReplacement: true
                ),
                slots: slots(primary: graphCandidate())
            )
        )
        let wholeFilterShader = contract(
            "whole-color-filter",
            secondMetadata:
                #"{"mode":"opacitymask","default":"textures/white-mask.tex"}"#,
            wholeColorFilter: true
        )
        let wholeFilterAssetStates: [
            SceneAssetTextureIdentity: SceneAssetTextureLaunchState
        ] = [
            .init(
                path: SceneVFSAssetPath("textures/white-mask.tex")!,
                purpose: .mask
            ): .ready(.data),
        ]
        let wholeFilterPositive = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: wholeFilterShader,
                slots: slots()
            ),
            assetStates: wholeFilterAssetStates
        )
        let wholeFilterInternalTarget = Graph.TextureIdentity(
            kind: .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "internal"
        )
        let wholeFilterInternalGraph = graph(
            withPrimaryBinding: false,
            nodeTarget: wholeFilterInternalTarget
        )
        let wholeFilterInternalTargetFailure = catalog(
            graph: wholeFilterInternalGraph,
            template: materialTemplate(
                graph: wholeFilterInternalGraph,
                shader: wholeFilterShader,
                slots: slots()
            ),
            assetStates: wholeFilterAssetStates
        )
        let sourceAlphaFactorPositive = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "source-alpha-factor-positive",
                    sourceAlphaFactor: true
                ),
                slots: slots(primary: graphCandidate())
            )
        )
        let scalarAlphaNoise = SceneVFSAssetPath("util/noise")!
        let scalarAlphaMask = SceneVFSAssetPath("textures/pulse-mask.tex")!
        let scalarAlphaAuxiliaryPositive = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "scalar-alpha-auxiliary-positive",
                    scalarAlphaAuxiliaries: true
                ),
                slots: slots(
                    fourth: assetCandidate(scalarAlphaMask.value)
                )
            ),
            assetStates: [
                .init(path: scalarAlphaNoise, purpose: .noise): .ready(.data),
                .init(path: scalarAlphaMask, purpose: .mask): .ready(.data),
            ]
        )
        let effectOutputGraph = graph(
            withPrimaryBinding: true,
            input: previousOutput()
        )
        let effectOutputTypedColorDeferred = catalog(
            graph: effectOutputGraph,
            template: materialTemplate(
                graph: effectOutputGraph,
                shader: contract(
                    "effect-output-typed-color-deferred",
                    alphaReplacement: true
                ),
                slots: slots(primary: .init(
                    reference: .graph(previousOutput()),
                    provenance: .explicitBinding
                ))
            )
        )
        let purposeFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "purpose-failure",
                    secondMetadata: "{}",
                    observesSecond: true
                ),
                slots: slots(
                    primary: graphCandidate(),
                    second: assetCandidate("textures/unproven.tex")
                )
            ),
            demandIssueSlots: [1]
        )
        let defaultPurposeFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "default-purpose-failure",
                    secondMetadata: #"{"default":"textures/default.tex"}"#,
                    observesSecond: true
                ),
                slots: slots(primary: graphCandidate())
            ),
            demandIssueSlots: [1]
        )
        let staticAssetDefaultPositive = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "static-asset-default-positive",
                    secondMetadata:
                        #"{"mode":"flowmask","default":"textures/default-flow.tex"}"#,
                    observesSecond: true
                ),
                slots: slots(primary: graphCandidate())
            ),
            assetStates: [
                .init(
                    path: SceneVFSAssetPath("textures/default-flow.tex")!,
                    purpose: .flow
                ): .ready(.data),
            ]
        )
        let authoredAssetPositive = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "authored-asset-positive",
                    secondMetadata: #"{"material":"normal"}"#,
                    observesSecond: true
                ),
                slots: slots(
                    primary: graphCandidate(),
                    second: assetCandidate("textures/normal.tex")
                )
            ),
            assetStates: [
                .init(
                    path: SceneVFSAssetPath("textures/normal.tex")!,
                    purpose: .normal
                ): .ready(.data),
            ]
        )
        let lowAsset = assetCandidate("textures/low-flow.tex")
        let highAsset = assetCandidate("textures/high-flow.tex")
        let precedenceTemplate = materialTemplate(
            graph: boundGraph,
            shader: contract(
                "authored-asset-precedence",
                secondMetadata: #"{"mode":"flowmask"}"#,
                observesSecond: true
            ),
            slots: secondCandidates([lowAsset, highAsset])
        )
        let highAbsentUsesLow = catalog(
            graph: boundGraph,
            template: precedenceTemplate,
            assetStates: [
                .init(path: SceneVFSAssetPath("textures/low-flow.tex")!,
                      purpose: .flow): .ready(.data),
                .init(path: SceneVFSAssetPath("textures/high-flow.tex")!,
                      purpose: .flow): .absent,
            ]
        )
        let highUnavailableBlocksLow = catalog(
            graph: boundGraph,
            template: precedenceTemplate,
            assetStates: [
                .init(path: SceneVFSAssetPath("textures/low-flow.tex")!,
                      purpose: .flow): .ready(.data),
                .init(path: SceneVFSAssetPath("textures/high-flow.tex")!,
                      purpose: .flow): .unavailable,
            ]
        )
        let maskMetadata = #"{"mode":"opacitymask","combo":"MASK","default":"textures/default-mask.tex"}"#
        let maskedDefaultAbsent = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "masked-default-absent",
                    secondMetadata: maskMetadata,
                    maskedAlpha: true
                ),
                slots: slots()
            )
        )
        let maskedUnconditionalWithoutBinding = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "masked-unconditional-without-binding",
                    secondMetadata: maskMetadata,
                    maskedAlpha: true,
                    unconditionalMaskedAlpha: true
                ),
                slots: slots(primary: graphCandidate())
            ),
            assetStates: [
                .init(
                    path: SceneVFSAssetPath("textures/default-mask.tex")!,
                    purpose: .mask
                ): .ready(.data),
            ]
        )
        let maskedFormatDefault = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "masked-format-default",
                    secondMetadata:
                        #"{"mode":"opacitymask","combo":"MASK","default":"textures/default-mask.tex","formatcombo":true}"#,
                    maskedAlpha: true,
                    unconditionalMaskedAlpha: true
                ),
                slots: slots(primary: graphCandidate())
            )
        )
        let maskedPositive = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "masked-positive",
                    secondMetadata: maskMetadata,
                    maskedAlpha: true
                ),
                slots: slots(second: assetCandidate("textures/mask.tex"))
            ),
            assetStates: [
                .init(
                    path: SceneVFSAssetPath("textures/mask.tex")!,
                    purpose: .mask
                ): .ready(.data),
            ]
        )
        let maskedMissingConflict = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "masked-missing-conflict",
                    secondMetadata: maskMetadata,
                    maskedAlpha: true
                ),
                slots: slots(),
                combos: [.init(name: "MASK", value: 1)]
            )
        )
        let maskedPresentConflict = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "masked-present-conflict",
                    secondMetadata: maskMetadata,
                    maskedAlpha: true
                ),
                slots: slots(second: assetCandidate("textures/mask.tex")),
                combos: [.init(name: "MASK", value: 0)]
            )
        )
        let implicitPositive = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "implicit-positive",
                    firstMetadata: #"{"material":"Framebuffer"}"#
                ),
                slots: slots()
            )
        )
        let historicalImplicitPositive = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "historical-implicit-positive",
                    firstMetadata:
                        #"{"material":"ui_editor_properties_framebuffer","hidden":true}"#
                ),
                slots: slots()
            )
        )
        let historicalImplicitWithoutHidden = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "historical-implicit-without-hidden",
                    firstMetadata:
                        #"{"material":"ui_editor_properties_framebuffer"}"#
                ),
                slots: slots()
            )
        )
        let implicitNegative = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                // A second sampler makes the historical source ambiguous;
                // it must remain fail-closed without an explicit binding.
                shader: contract("implicit-negative", secondMetadata: "{}"),
                slots: slots()
            )
        )
        let providerPositive = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "provider-positive",
                    firstMetadata: #"{"mode":"flowmask"}"#
                ),
                slots: slots(primary: .init(
                    reference: .provider(.system("audio-spectrum")),
                    provenance: .instance
                ))
            )
        )
        let externalBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: layerID,
            providerLayerID: 42,
            slot: .init(
                effectID: effectKey.descriptorID,
                passIndex: 0,
                slotIndex: 1
            ),
            blendMode: 0,
            kind: .resolvedMaterial
        )
        let crossLayerTemplate = materialTemplate(
            graph: boundGraph,
            shader: contract(
                "cross-layer-provider",
                secondMetadata: "{}",
                observesSecond: true
            ),
            slots: secondCandidates([
                assetCandidate("util/white"),
                namedTargetCandidate(providerLayerID: 42),
            ])
        )
        let crossLayerPositive = catalog(
            graph: boundGraph,
            template: crossLayerTemplate,
            dependencyOwnership: .externalPrimary(externalBinding)
        )
        let crossLayerTwoMaterialGraph = graph(
            withPrimaryBinding: true,
            materialCount: 2
        )
        let crossLayerShadowedProvenance = catalog(
            graph: crossLayerTwoMaterialGraph,
            templates: [
                0: materialTemplate(
                    graph: crossLayerTwoMaterialGraph,
                    nodeIndex: 0,
                    shader: contract(
                        "cross-layer-selected",
                        secondMetadata: "{}",
                        observesSecond: true
                    ),
                    slots: secondCandidates([
                        namedTargetCandidate(providerLayerID: 42),
                    ])
                ),
                1: materialTemplate(
                    graph: crossLayerTwoMaterialGraph,
                    nodeIndex: 1,
                    shader: contract(
                        "cross-layer-shadowed",
                        secondMetadata: #"{"mode":"flowmask"}"#,
                        observesSecond: true
                    ),
                    slots: secondCandidates([
                        namedTargetCandidate(providerLayerID: 42),
                        systemCandidate("audio-spectrum"),
                    ])
                ),
            ],
            dependencyOwnership: .externalPrimary(externalBinding)
        )
        let crossLayerWrongProvider = catalog(
            graph: boundGraph,
            template: crossLayerTemplate,
            dependencyOwnership: .externalPrimary(.init(
                consumerLayerID: layerID,
                providerLayerID: 43,
                slot: externalBinding.slot,
                blendMode: 0,
                kind: .resolvedMaterial
            ))
        )
        let crossLayerSecondary = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "cross-layer-secondary",
                    secondMetadata: "{}",
                    observesSecond: true
                ),
                slots: secondCandidates([
                    namedTargetCandidate(providerLayerID: 42, variant: .secondary),
                ])
            ),
            dependencyOwnership: .externalPrimary(externalBinding)
        )
        let crossLayerAmbiguous = catalog(
            graph: crossLayerTwoMaterialGraph,
            templates: [
                0: materialTemplate(
                    graph: crossLayerTwoMaterialGraph,
                    nodeIndex: 0,
                    shader: contract(
                        "cross-layer-ambiguous-first",
                        secondMetadata: "{}",
                        observesSecond: true
                    ),
                    slots: secondCandidates([
                        namedTargetCandidate(providerLayerID: 41),
                    ])
                ),
                1: materialTemplate(
                    graph: crossLayerTwoMaterialGraph,
                    nodeIndex: 1,
                    shader: contract(
                        "cross-layer-ambiguous-second",
                        secondMetadata: "{}",
                        observesSecond: true
                    ),
                    slots: secondCandidates([
                        namedTargetCandidate(providerLayerID: 42),
                    ])
                ),
            ],
            dependencyOwnership: .externalPrimary(externalBinding)
        )
        let directDrawPositive = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "direct-draw-positive",
                    transparentDirectDraw: true
                ),
                slots: slots(),
                combos: [.init(name: "DIRECTDRAW", value: 1)]
            ),
            sourceRoute: .transparentDirectDraw
        )
        let audioDirectDrawPositive = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "audio-direct-draw-positive",
                    audioDirectDraw: true
                ),
                slots: slots(),
                combos: [.init(name: "DIRECTDRAW", value: 1)]
            ),
            sourceRoute: .transparentDirectDraw
        )
        let directDrawSourceDependent = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("direct-draw-source-dependent"),
                slots: slots(primary: graphCandidate()),
                combos: [.init(name: "DIRECTDRAW", value: 1)]
            ),
            sourceRoute: .transparentDirectDraw
        )
        let capturedMainPositiveTemplate = materialTemplate(
            graph: unboundGraph,
            shader: contract(
                "captured-main-positive",
                firstMetadata: #"{"material":"framebuffer"}"#
            ),
            slots: slots()
        )
        let capturedMainPositive = catalog(
            graph: unboundGraph,
            template: capturedMainPositiveTemplate,
            sourceRoute: .capturedMainTargetTexture
        )
        let capturedMainImplicitTemplate = materialTemplate(
            graph: unboundGraph,
            shader: contract("captured-main-implicit"),
            slots: slots()
        )
        let capturedMainImplicit = catalog(
            graph: unboundGraph,
            template: capturedMainImplicitTemplate,
            sourceRoute: .capturedMainTargetTexture
        )
        let capturedMainImplicitCompetingSource = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract("captured-main-implicit-competing-source"),
                slots: slots(primary: userPropertyCandidate("capture-source"))
            ),
            sourceRoute: .capturedMainTargetTexture
        )
        let capturedMainCompetingSource = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "captured-main-competing-source",
                    firstMetadata: #"{"material":"framebuffer"}"#
                ),
                slots: slots(primary: userPropertyCandidate("capture-source"))
            ),
            sourceRoute: .capturedMainTargetTexture
        )
        let capturedMainWrongMode = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "captured-main-wrong-mode",
                    firstMetadata:
                        #"{"material":"framebuffer","mode":"depth"}"#
                ),
                slots: slots()
            ),
            sourceRoute: .capturedMainTargetTexture
        )
        let capturedMainDefaultSource = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "captured-main-default-source",
                    firstMetadata:
                        #"{"material":"framebuffer","default":"util/noise"}"#
                ),
                slots: slots()
            ),
            sourceRoute: .capturedMainTargetTexture,
            assetStates: [
                .init(
                    path: SceneVFSAssetPath("util/noise")!,
                    purpose: .noise
                ): .absent,
            ]
        )
        let capturedMainNoGraphInput = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "captured-main-no-graph-input",
                    transparentDirectDraw: true
                ),
                slots: slots(),
                combos: [.init(name: "DIRECTDRAW", value: 1)]
            ),
            sourceRoute: .capturedMainTargetTexture
        )
        let capturedMainWrongSource = catalog(
            graph: effectOutputGraph,
            template: materialTemplate(
                graph: effectOutputGraph,
                shader: contract("captured-main-wrong-source"),
                slots: slots(primary: .init(
                    reference: .graph(previousOutput()),
                    provenance: .explicitBinding
                ))
            ),
            sourceRoute: .capturedMainTargetTexture
        )
        let capturedMainUnresolvedColor = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "captured-main-unresolved-color",
                    colorUnproven: true
                ),
                slots: slots(primary: graphCandidate())
            ),
            sourceRoute: .capturedMainTargetTexture
        )
        let capturedMainIndependentAlphaSignal = catalog(
            graph: unboundGraph,
            template: materialTemplate(
                graph: unboundGraph,
                shader: contract(
                    "captured-main-independent-alpha-signal",
                    firstMetadata: #"{"material":"framebuffer"}"#,
                    independentAlphaSignal: true
                ),
                slots: slots()
            ),
            sourceRoute: .capturedMainTargetTexture
        )
        let secondGraphSourceGraph = graph(
            withPrimaryBinding: true,
            withSecondGraphBinding: true
        )
        let capturedMainSecondGraphSource = catalog(
            graph: secondGraphSourceGraph,
            template: materialTemplate(
                graph: secondGraphSourceGraph,
                shader: contract(
                    "captured-main-second-graph-source",
                    firstMetadata: #"{"material":"framebuffer"}"#,
                    secondMetadata: #"{"material":"framebuffer"}"#,
                    opaqueSecondGraph: true
                ),
                slots: slots(
                    primary: graphCandidate(),
                    second: graphCandidate()
                )
            ),
            sourceRoute: .capturedMainTargetTexture
        )
        let variantMixedTemplate = materialTemplate(
            graph: unboundGraph,
            shader: contract(
                "captured-main-variant-mixed",
                firstMetadata: #"{"material":"framebuffer"}"#,
                secondMetadata: #"{"mode":"flowmask","combo":"EXTRA"}"#,
                variantMixedSource: true
            ),
            slots: slots(second: userPropertyCandidate("optional-flow"))
        )
        let capturedMainVariantMixed = catalog(
            graph: unboundGraph,
            template: variantMixedTemplate,
            sourceRoute: .capturedMainTargetTexture
        )
        guard case let .success(variantMixedCache) =
                SceneResolvedMaterialVariantCache.launchValidated(
            template: variantMixedTemplate,
            maximumVariantCount: 16
        ) else { fatalError("variant mixed cache rejected") }
        let variantMixedEnvelopePrepared: Bool
        let variantMixedEnvelopeFailure: String
        switch variantMixedCache.precompileLaunchEnvelope(
            implicitFramebufferIdentity: source()
        ) {
        case .success:
            variantMixedEnvelopePrepared = true
            variantMixedEnvelopeFailure = ""
        case let .failure(failure):
            variantMixedEnvelopePrepared = false
            switch failure {
            case .capacity:
                variantMixedEnvelopeFailure = "capacity"
            case let .material(material):
                variantMixedEnvelopeFailure = ([
                    material.phase.rawValue,
                    material.code.rawValue,
                ] + material.boundedDetails).joined(separator: ":")
            }
        }
        let capacityOnePositive = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("capacity-one-positive"),
                slots: slots(primary: graphCandidate())
            ),
            maximumVariants: 1
        )
        let twoVariantTemplate = materialTemplate(
            graph: boundGraph,
            shader: contract(
                "capacity-two",
                comboMetadata: #"[COMBO] {"combo":"EXTRA","default":1}"#,
                secondMetadata:
                    #"{"mode":"flowmask","default":"textures/capacity-flow.tex"}"#,
                conditionalSecond: true
            ),
            slots: slots(primary: graphCandidate()),
            combos: [.init(name: "EXTRA", value: 1)]
        )
        let capacityTwoPositive = catalog(
            graph: boundGraph,
            template: twoVariantTemplate,
            maximumVariants: 2,
            assetStates: [
                .init(
                    path: SceneVFSAssetPath("textures/capacity-flow.tex")!,
                    purpose: .flow
                ): .ready(.data),
            ]
        )
        let capacityFailure = catalog(
            graph: boundGraph,
            template: twoVariantTemplate,
            maximumVariants: 1,
            assetStates: [
                .init(
                    path: SceneVFSAssetPath("textures/capacity-flow.tex")!,
                    purpose: .flow
                ): .ready(.data),
            ]
        )
        let partialGraph = graph(
            withPrimaryBinding: true,
            materialCount: 2
        )
        let partialFailure = catalog(
            graph: partialGraph,
            templates: [
                0: materialTemplate(
                    graph: partialGraph,
                    nodeIndex: 0,
                    shader: contract("partial-positive"),
                    slots: slots(primary: graphCandidate())
                ),
                1: materialTemplate(
                    graph: partialGraph,
                    nodeIndex: 1,
                    shader: contract(
                        "partial-failure",
                        firstMetadata: #"{"combo":"SOURCE_READY"}"#
                    ),
                    slots: slots(primary: graphCandidate()),
                    combos: [.init(name: "SOURCE_READY", value: 0)]
                ),
            ]
        )

        let result: [String: Any] = [
            "positiveClaim": positive.claim(layerID: layerID) != nil,
            "positiveCounters": counters(positive, graph: boundGraph),
            "effectProjectionRequirements": [
                "resolvedWithoutMatrix":
                    requiresInvertibleEffectTextureProjection(positive) == false,
                "modelViewProjectionOnly":
                    requiresInvertibleEffectTextureProjection(
                        modelViewProjectionOnly
                    ) == false,
                "effectProjectionForward":
                    requiresInvertibleEffectTextureProjection(
                        effectProjectionForward
                    ) == true,
                "unusedEffectProjectionDeclaration":
                    requiresInvertibleEffectTextureProjection(
                        unusedEffectProjectionDeclaration
                    ) == false,
                "effectProjectionInverse":
                    requiresInvertibleEffectTextureProjection(
                        effectProjectionInverse
                    ) == true,
                "ordinaryDedicated": requiresInvertibleEffectTextureProjection(
                    ordinaryDedicatedProjectionRequirement
                ) == false,
                "pointerDedicated": requiresInvertibleEffectTextureProjection(
                    pointerDedicatedProjectionRequirement
                ) == true,
                "uncompiledResolvedCacheFailsClosed":
                    uncompiledProjectionRequirement,
            ],
            "shaderFailure": rejection(shaderFailure),
            "frontendFailure": rejection(frontendFailure),
            "samplerSchemaFailure": rejection(samplerSchemaFailure),
            "samplerBindingProvenance": [
                "positive": samplerBindingToken(
                    samplers: [0: fixtureSampler(slot: 0)],
                    bindings: [fixtureBinding(slot: 0)]
                ),
                "order": samplerBindingToken(
                    samplers: [
                        0: fixtureSampler(slot: 0),
                        1: fixtureSampler(slot: 1),
                    ],
                    bindings: [fixtureBinding(slot: 1), fixtureBinding(slot: 0)]
                ),
                "duplicate": samplerBindingToken(
                    samplers: [0: fixtureSampler(slot: 0)],
                    bindings: [fixtureBinding(slot: 0), fixtureBinding(slot: 0)]
                ),
                "identity": samplerBindingToken(
                    samplers: [0: fixtureSampler(slot: 0)],
                    bindings: [fixtureBinding(slot: 0, name: "g_Texture1")]
                ),
                "variantPositive": samplerVariantSchemaToken([
                    (
                        [0: fixtureSampler(slot: 0)],
                        [fixtureBinding(slot: 0)]
                    ),
                    (
                        [0: fixtureSampler(slot: 0)],
                        [fixtureBinding(slot: 0)]
                    ),
                ]),
                "variantDivergence": samplerVariantSchemaToken([
                    (
                        [0: fixtureSampler(slot: 0)],
                        [fixtureBinding(slot: 0)]
                    ),
                    (
                        [1: fixtureSampler(slot: 1)],
                        [fixtureBinding(slot: 1)]
                    ),
                ]),
            ],
            "internalSamplerTargetClaim":
                internalSamplerTarget.claim(layerID: layerID) != nil,
            "internalSamplerTargetFailure": rejection(internalSamplerTarget),
            "internalSamplerTargetToken": launchEnvelopeToken(
                template: internalSamplerTemplate,
                implicitFramebufferIdentity: source()
            ),
            "activePassClaim": activePass.claim(layerID: layerID) != nil,
            "activePassFailure": rejection(activePass),
            "activePassToken": launchEnvelopeToken(
                template: activePassTemplate,
                implicitFramebufferIdentity: source()
            ),
            "colorFailure": rejection(colorFailure),
            "typedColorFailure": rejection(typedColorFailure),
            "wholeFilterClaim": wholeFilterPositive.claim(
                layerID: layerID
            ) != nil,
            "wholeFilterFailure": rejection(wholeFilterPositive),
            "wholeFilterInternalTargetClaim":
                wholeFilterInternalTargetFailure.claim(layerID: layerID) != nil,
            "wholeFilterInternalTargetFailure": rejection(
                wholeFilterInternalTargetFailure
            ),
            "sourceAlphaFactorClaim":
                sourceAlphaFactorPositive.claim(layerID: layerID) != nil,
            "sourceAlphaFactorFailure": rejection(sourceAlphaFactorPositive),
            "scalarAlphaAuxiliaryClaim":
                scalarAlphaAuxiliaryPositive.claim(layerID: layerID) != nil,
            "scalarAlphaAuxiliaryFailure": rejection(
                scalarAlphaAuxiliaryPositive
            ),
            "scalarAlphaAuxiliaryCounters": counters(
                scalarAlphaAuxiliaryPositive,
                graph: unboundGraph
            ),
            "effectOutputTypedColorDeferredClaim":
                effectOutputTypedColorDeferred.claim(layerID: layerID) != nil,
            "effectOutputTypedColorDeferredFailure": rejection(
                effectOutputTypedColorDeferred
            ),
            "purposeFailure": rejection(purposeFailure),
            "defaultPurposeFailure": rejection(defaultPurposeFailure),
            "staticAssetDefaultClaim": staticAssetDefaultPositive.claim(
                layerID: layerID
            ) != nil,
            "staticAssetDefaultFailure": rejection(staticAssetDefaultPositive),
            "staticAssetDefaultCounters": counters(
                staticAssetDefaultPositive,
                graph: boundGraph
            ),
            "authoredAssetClaim": authoredAssetPositive.claim(
                layerID: layerID
            ) != nil,
            "authoredAssetFailure": rejection(authoredAssetPositive),
            "authoredAssetCounters": counters(
                authoredAssetPositive,
                graph: boundGraph
            ),
            "highAbsentUsesLowClaim": highAbsentUsesLow.claim(
                layerID: layerID
            ) != nil,
            "highAbsentUsesLowFailure": rejection(highAbsentUsesLow),
            "highUnavailableBlocksLowClaim": highUnavailableBlocksLow.claim(
                layerID: layerID
            ) != nil,
            "highUnavailableBlocksLowFailure": rejection(
                highUnavailableBlocksLow
            ),
            "maskedDefaultAbsentClaim": maskedDefaultAbsent.claim(
                layerID: layerID
            ) != nil,
            "maskedDefaultAbsentFailure": rejection(maskedDefaultAbsent),
            "maskedDefaultAbsentCounters": counters(
                maskedDefaultAbsent,
                graph: unboundGraph
            ),
            "maskedDefaultAbsentChannelUses": compiledChannelUseCount(
                maskedDefaultAbsent,
                graph: unboundGraph,
                slot: 1
            ),
            "maskedUnconditionalWithoutBindingClaim":
                maskedUnconditionalWithoutBinding.claim(layerID: layerID) != nil,
            "maskedUnconditionalWithoutBindingFailure": rejection(
                maskedUnconditionalWithoutBinding
            ),
            "maskedUnconditionalWithoutBindingCounters": counters(
                maskedUnconditionalWithoutBinding,
                graph: boundGraph
            ),
            "maskedUnconditionalWithoutBindingChannelUses":
                compiledChannelUseCount(
                    maskedUnconditionalWithoutBinding,
                    graph: boundGraph,
                    slot: 1
                ),
            "maskedFormatDefaultClaim":
                maskedFormatDefault.claim(layerID: layerID) != nil,
            "maskedFormatDefaultFailure": rejection(maskedFormatDefault),
            "maskedPositiveClaim": maskedPositive.claim(layerID: layerID) != nil,
            "maskedPositiveFailure": rejection(maskedPositive),
            "maskedPositiveCounters": counters(maskedPositive, graph: unboundGraph),
            "maskedMissingConflict": rejection(maskedMissingConflict),
            "maskedPresentConflict": rejection(maskedPresentConflict),
            "implicitPositiveClaim": implicitPositive.claim(layerID: layerID) != nil,
            "implicitPositiveCounters": counters(
                implicitPositive,
                graph: unboundGraph
            ),
            "historicalImplicitPositiveClaim":
                historicalImplicitPositive.claim(layerID: layerID) != nil,
            "historicalImplicitPositiveCounters": counters(
                historicalImplicitPositive,
                graph: unboundGraph
            ),
            "historicalImplicitWithoutHidden": rejection(
                historicalImplicitWithoutHidden
            ),
            "implicitNegative": rejection(implicitNegative),
            "providerPositiveClaim": providerPositive.claim(layerID: layerID) != nil,
            "providerPositiveCounters": counters(
                providerPositive,
                graph: unboundGraph
            ),
            "crossLayerPositiveClaim": crossLayerPositive.claim(
                layerID: layerID
            ) != nil,
            "crossLayerPositiveFailure": rejection(crossLayerPositive),
            "crossLayerShadowedProvenanceClaim": crossLayerShadowedProvenance.claim(
                layerID: layerID
            ) != nil,
            "crossLayerShadowedProvenanceFailure": rejection(
                crossLayerShadowedProvenance
            ),
            "crossLayerWrongProvider": rejection(crossLayerWrongProvider),
            "crossLayerSecondary": rejection(crossLayerSecondary),
            "crossLayerAmbiguous": rejection(crossLayerAmbiguous),
            "directDrawPositiveClaim": directDrawPositive.claim(
                layerID: layerID
            ) != nil,
            "directDrawPositiveFailure": rejection(directDrawPositive),
            "directDrawPositiveCounters": counters(
                directDrawPositive,
                graph: unboundGraph
            ),
            "audioDirectDrawClaim": audioDirectDrawPositive.claim(
                layerID: layerID
            ) != nil,
            "audioSpectrumConsumer":
                audioDirectDrawPositive.hasAudioSpectrumConsumer,
            "directDrawSourceDependentClaim": directDrawSourceDependent.claim(
                layerID: layerID
            ) != nil,
            "directDrawSourceDependent": rejection(directDrawSourceDependent),
            "capturedMainPositiveClaim": capturedMainPositive.claim(
                layerID: layerID
            ) != nil,
            "capturedMainPositiveBindingsEmpty":
                capturedMainPositiveTemplate.graphRole.bindings.isEmpty,
            "capturedMainPositiveFailure": rejection(capturedMainPositive),
            "capturedMainImplicitClaim": capturedMainImplicit.claim(
                layerID: layerID
            ) != nil,
            "capturedMainImplicitBindingsEmpty":
                capturedMainImplicitTemplate.graphRole.bindings.isEmpty,
            "capturedMainImplicitFailure": rejection(capturedMainImplicit),
            "capturedMainImplicitCounters": counters(
                capturedMainImplicit,
                graph: unboundGraph
            ),
            "capturedMainImplicitCompetingSourceClaim":
                capturedMainImplicitCompetingSource.claim(layerID: layerID) != nil,
            "capturedMainImplicitCompetingSourceFailure": rejection(
                capturedMainImplicitCompetingSource
            ),
            "capturedMainCompetingSourceClaim":
                capturedMainCompetingSource.claim(layerID: layerID) != nil,
            "capturedMainCompetingSourceFailure": rejection(
                capturedMainCompetingSource
            ),
            "capturedMainWrongModeClaim": capturedMainWrongMode.claim(
                layerID: layerID
            ) != nil,
            "capturedMainWrongModeFailure": rejection(capturedMainWrongMode),
            "capturedMainDefaultSourceClaim": capturedMainDefaultSource.claim(
                layerID: layerID
            ) != nil,
            "capturedMainDefaultSourceFailure": rejection(
                capturedMainDefaultSource
            ),
            "capturedMainNoGraphInputClaim": capturedMainNoGraphInput.claim(
                layerID: layerID
            ) != nil,
            "capturedMainNoGraphInputFailure": rejection(
                capturedMainNoGraphInput
            ),
            "capturedMainWrongSourceClaim": capturedMainWrongSource.claim(
                layerID: layerID
            ) != nil,
            "capturedMainWrongSourceFailure": rejection(capturedMainWrongSource),
            "capturedMainUnresolvedColorClaim": capturedMainUnresolvedColor.claim(
                layerID: layerID
            ) != nil,
            "capturedMainUnresolvedColorFailure": rejection(
                capturedMainUnresolvedColor
            ),
            "capturedMainIndependentAlphaSignalClaim":
                capturedMainIndependentAlphaSignal.claim(layerID: layerID) != nil,
            "capturedMainIndependentAlphaSignalFailure": rejection(
                capturedMainIndependentAlphaSignal
            ),
            "capturedMainSecondGraphSourceClaim":
                capturedMainSecondGraphSource.claim(layerID: layerID) != nil,
            "capturedMainSecondGraphSourceFailure": rejection(
                capturedMainSecondGraphSource
            ),
            "capturedMainVariantMixedClaim": capturedMainVariantMixed.claim(
                layerID: layerID
            ) != nil,
            "capturedMainVariantMixedFailure": rejection(capturedMainVariantMixed),
            "capturedMainVariantMixedEnvelopePrepared":
                variantMixedEnvelopePrepared,
            "capturedMainVariantMixedEnvelopeFailure":
                variantMixedEnvelopeFailure,
            "capturedMainVariantMixedSupportsCapture":
                variantMixedCache.supportsCapturedMainTargetTexture,
            "capturedMainVariantMixedCounters": [
                "cached": variantMixedCache.counters.cachedVariantCount,
                "prepared": variantMixedCache.counters.shaderPreparationCount,
                "frontend": variantMixedCache.counters.frontendCompilationCount,
                "capacity": variantMixedCache.counters.capacityRejectionCount,
            ],
            "capacityOneClaim": capacityOnePositive.claim(layerID: layerID) != nil,
            "capacityOneCounters": counters(
                capacityOnePositive,
                graph: boundGraph
            ),
            "capacityTwoClaim": capacityTwoPositive.claim(
                layerID: layerID
            ) != nil,
            "capacityTwoCounters": counters(
                capacityTwoPositive,
                graph: boundGraph
            ),
            "capacityTwoFailure": rejection(capacityTwoPositive),
            "capacityFailureClaim": capacityFailure.claim(
                layerID: layerID
            ) != nil,
            "capacityFailure": rejection(capacityFailure),
            "redOnlyChannelEnvelope": [
                "allRed": SceneResolvedMaterialVariantCache
                    .channelEnvelopeIsRedOnly([.redOnly, .redOnly]),
                "mixed": SceneResolvedMaterialVariantCache
                    .channelEnvelopeIsRedOnly([.redOnly, .unproven]),
                "empty": SceneResolvedMaterialVariantCache
                    .channelEnvelopeIsRedOnly([]),
            ],
            "partialClaim": partialFailure.claim(layerID: layerID) != nil,
            "partialFailure": rejection(partialFailure),
            "partialSummary": summary(partialFailure),
            "partialAcceptedRoutes": acceptedRouteCount(partialFailure),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


CATALOG_DEMAND_SUPPORT = PROGRAM_FINALIZER_FIXTURE["SUPPORT"] + r'''

nonisolated struct SceneRenderDescriptor {}

nonisolated struct SceneAuthoredMaterialResolution {
    let node: SceneResolvedMaterialNode?
    let issues: [String]
}

nonisolated enum SceneAuthoredMaterialResolver {
    static func resolve(
        node: SceneAuthoredEffectRenderPlan.Node,
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor
    ) -> SceneAuthoredMaterialResolution {
        _ = node
        _ = graph
        _ = descriptor
        return .init(node: .init(), issues: [])
    }
}

nonisolated extension SceneResolvedMaterialNode {
    var shaderPath: String { "fixture/catalog-demand" }
}

nonisolated enum SceneResolvedMaterialTemplateCompiler {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    static func compile(
        material: SceneResolvedMaterialNode,
        graph: Graph,
        shaderContract: SceneShaderContract,
        provenSceneScriptValueTargets: Set<SceneDynamicTarget> = []
    ) -> Result<Template, SceneResolvedMaterialFailure> {
        _ = material
        _ = provenSceneScriptValueTargets
        guard let node = graph.nodes.first,
              let effect = graph.effects.first,
              let state = SceneMaterialRenderState.compile(
                  blending: "normal",
                  depthTest: "disabled",
                  depthWrite: "disabled",
                  cullMode: "nocull",
                  alphaWriting: nil
              ) else {
            return .failure(.init(
                phase: .invariant,
                code: .identityInvariant
            ))
        }
        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        slots[0] = .init(index: 0, candidates: [
            .init(
                reference: .graph(effect.input),
                provenance: .explicitBinding
            ),
        ])
        guard let template = Template.validated(
            textureSlots: slots,
            combos: [.init(name: "MODE", value: 2)],
            uniformDeclarations: [],
            renderState: state,
            graphRole: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .effectOutput,
                bindings: [.init(slot: 0, texture: .layerSource)]
            ),
            shaderContract: shaderContract,
            diagnosticProvenance: .init(
                nodeIndex: node.nodeIndex,
                authoredShaderPath: shaderContract.identity,
                contractIdentity: shaderContract.identity,
                contractCanonicalSHA256: shaderContract.canonicalSHA256,
                textureSources: [],
                uniformSources: []
            )
        ) else {
            return .failure(.init(
                phase: .invariant,
                code: .identityInvariant
            ))
        }
        return .success(template)
    }
}

nonisolated struct SceneResolvedMaterialAdmissionProduct {
    let graph: SceneAuthoredEffectRenderPlan
}

nonisolated struct SceneResolvedMaterialAdmittedLayer {
    let products: [SceneResolvedMaterialAdmissionProduct]
}

nonisolated enum SceneResolvedMaterialExecutionCapabilityAdmission {
    struct Candidate {
        let result: Result<
            SceneResolvedMaterialAdmittedLayer,
            SceneResolvedMaterialFailure
        >
    }
}
'''


CATALOG_DEMAND_HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Template = SceneResolvedMaterialTemplate

private let layerID = 982
private let effectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "catalog-demand"
)

private func source() -> Graph.TextureIdentity {
    .init(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
}

private func output() -> Graph.TextureIdentity {
    .init(
        kind: .effectOutput,
        layerID: layerID,
        effect: effectKey,
        name: nil
    )
}

private func graph() -> Graph {
    let node = Graph.Node(
        nodeIndex: 0,
        effect: effectKey,
        definitionPassIndex: 0,
        materialOrdinal: 0,
        instancePassIndex: 0,
        kind: .material,
        materialPath: "materials/catalog-demand.json",
        materialPassID: "catalog-demand",
        target: output(),
        bindings: [.init(
            slot: 0,
            authoredName: "previous",
            texture: source(),
            conditions: nil
        )],
        commandSource: nil,
        commandTarget: nil,
        compose: nil,
        conditions: nil
    )
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effectKey,
            definitionPath: "effects/catalog-demand/effect.json",
            input: source(),
            output: output(),
            nodeIndices: [node.nodeIndex]
        )],
        renderTargets: [],
        nodes: [node],
        finalOutput: output(),
        blockers: []
    )
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

private func fragmentSource(
    defaultPath: String,
    readinessCombo: String? = nil,
    conditionalReadinessUse: Bool = true,
    graphInputAlias: Bool = false,
    formatCombo: Bool = false
) -> String {
    let samplerMetadata: String
    if graphInputAlias {
        guard let readinessCombo else {
            fatalError("graph-input alias fixture requires a presence combo")
        }
        samplerMetadata =
            #"{"material":"framebuffer","default":"\#(defaultPath)","combo":"\#(readinessCombo)"}"#
    } else {
        samplerMetadata = readinessCombo.map { combo in
            "{\"mode\":\"rgbmask\",\"default\":\"\(defaultPath)\","
                + "\"combo\":\"\(combo)\""
                + (formatCombo ? ",\"formatcombo\":true}" : "}")
        } ?? #"{"default":"\#(defaultPath)","require":{"MODE":1}}"#
    }
    let output = readinessCombo.map { combo in
        conditionalReadinessUse ? """
        #if \(combo)
            gl_FragColor = texSample2D(g_Texture2, v_TexCoord);
        #else
            gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
        #endif
        """ : "gl_FragColor = texSample2D(g_Texture2, v_TexCoord);"
    } ?? """
    #if MODE == 1
        gl_FragColor = texSample2D(g_Texture2, v_TexCoord);
    #else
        gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
    #endif
    """
    return """
    // [COMBO] {"combo":"MODE","default":1,"options":{"Gradient":1,"RGB":2}}
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0; // {"material":"framebuffer"}
    uniform sampler2D g_Texture2; // \(samplerMetadata)
    void main() {
        \(output)
    }
    """
}

private func contract(
    defaultPath: String,
    readinessCombo: String? = nil,
    conditionalReadinessUse: Bool = true,
    graphInputAlias: Bool = false,
    formatCombo: Bool = false
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
        stage(.vertex, path: "catalog/root.vert", source: vertexSource),
        stage(
            .fragment,
            path: "catalog/root.frag",
            source: fragmentSource(
                defaultPath: defaultPath,
                readinessCombo: readinessCombo,
                conditionalReadinessUse: conditionalReadinessUse,
                graphInputAlias: graphInputAlias,
                formatCombo: formatCombo
            )
        ),
    ]
    return .init(
        identity: "fixture/catalog-demand",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-catalog-demand-\(defaultPath)-\(readinessCombo ?? "none")",
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "catalog/root.vert"),
                .init(label: "fragment", virtualPath: "catalog/root.frag"),
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
            dependencySHA256:
                "fixture-catalog-demand-dependency-\(defaultPath)-\(readinessCombo ?? "none")"
        )
    )
}

private func catalog(
    graph: Graph,
    contract: SceneShaderContract
) -> SceneResolvedMaterialRuntimeCatalog {
    .init(
        descriptor: .init(),
        admissionCandidates: [.init(result: .success(.init(
            products: [.init(graph: graph)]
        )))],
        shaderContracts: [contract]
    )
}

private func template(
    catalog: SceneResolvedMaterialRuntimeCatalog,
    graph: Graph
) -> Template {
    guard case let .template(template)? = catalog.entry(for: graph.nodes[0]) else {
        fatalError("catalog did not compile fixture template")
    }
    return template
}

private func hasPurposeIssue(
    _ catalog: SceneResolvedMaterialRuntimeCatalog,
    path: SceneVFSAssetPath
) -> Bool {
    catalog.resourceDemandIssues.contains { issue in
        guard issue.slot == 2,
              issue.code == .purposeUnproven,
              case let .asset(issuePath) = issue.reference else { return false }
        return issuePath == path
    }
}

@main
private enum Main {
    static func main() throws {
        let fixtureGraph = graph()

        let positivePath = SceneVFSAssetPath("util/perlin_256")!
        let positiveCatalog = catalog(
            graph: fixtureGraph,
            contract: contract(defaultPath: positivePath.value)
        )
        let positiveTemplate = template(
            catalog: positiveCatalog,
            graph: fixtureGraph
        )
        let positiveSeed = try SceneResolvedMaterialShaderSchema
            .unconditionalSamplers(positiveTemplate)
        let positiveReachable = try SceneResolvedMaterialShaderSchema
            .reachableSamplers(
                positiveTemplate,
                implicitFramebufferIdentity: source()
            )
        let positiveReference = Template.TextureReference.asset(positivePath)
        let typedIdentity = SceneAssetTextureIdentity(
            path: positivePath,
            purpose: .noise
        )
        let optionalPath = SceneVFSAssetPath("gradient/gradient_fire")!
        let optionalTypedIdentity = SceneAssetTextureIdentity(
            path: optionalPath,
            purpose: .preservedChannels
        )

        let optionalCatalog = catalog(
            graph: fixtureGraph,
            contract: contract(
                defaultPath: optionalPath.value,
                readinessCombo: "HAS_TEXTURE"
            )
        )
        let optionalTemplate = template(
            catalog: optionalCatalog,
            graph: fixtureGraph
        )
        let optionalSeed = try SceneResolvedMaterialShaderSchema
            .unconditionalSamplers(optionalTemplate)
        let optionalReachable = try SceneResolvedMaterialShaderSchema
            .reachableSamplers(
                optionalTemplate,
                implicitFramebufferIdentity: source()
            )

        let activeOptionalCatalog = catalog(
            graph: fixtureGraph,
            contract: contract(
                defaultPath: optionalPath.value,
                readinessCombo: "HAS_TEXTURE",
                conditionalReadinessUse: false
            )
        )
        let activeOptionalTemplate = template(
            catalog: activeOptionalCatalog,
            graph: fixtureGraph
        )
        let activeOptionalReachable = try SceneResolvedMaterialShaderSchema
            .reachableSamplers(
                activeOptionalTemplate,
                implicitFramebufferIdentity: source()
            )

        let graphAliasDefaultPath = SceneVFSAssetPath(
            "fixtures/catalog-demand-graph-alias-default"
        )!
        let graphAliasCatalog = catalog(
            graph: fixtureGraph,
            contract: contract(
                defaultPath: graphAliasDefaultPath.value,
                readinessCombo: "HAS_TEXTURE",
                conditionalReadinessUse: false,
                graphInputAlias: true
            )
        )
        let graphAliasTemplate = template(
            catalog: graphAliasCatalog,
            graph: fixtureGraph
        )
        let graphAliasReachable = try SceneResolvedMaterialShaderSchema
            .reachableSamplers(
                graphAliasTemplate,
                implicitFramebufferIdentity: source()
            )

        let formatDefaultCatalog = catalog(
            graph: fixtureGraph,
            contract: contract(
                defaultPath: optionalPath.value,
                readinessCombo: "HAS_TEXTURE",
                conditionalReadinessUse: false,
                formatCombo: true
            )
        )
        let formatDefaultTemplate = template(
            catalog: formatDefaultCatalog,
            graph: fixtureGraph
        )
        let formatDefaultReachable = try SceneResolvedMaterialShaderSchema
            .reachableSamplers(
                formatDefaultTemplate,
                implicitFramebufferIdentity: source()
            )

        let unknownPath = SceneVFSAssetPath(
            "fixtures/catalog-demand-unproven"
        )!
        let negativeCatalog = catalog(
            graph: fixtureGraph,
            contract: contract(defaultPath: unknownPath.value)
        )
        let negativeTemplate = template(
            catalog: negativeCatalog,
            graph: fixtureGraph
        )
        let negativeSeed = try SceneResolvedMaterialShaderSchema
            .unconditionalSamplers(negativeTemplate)
        let negativeReachable = try SceneResolvedMaterialShaderSchema
            .reachableSamplers(
                negativeTemplate,
                implicitFramebufferIdentity: source()
            )

        let result: [String: Any] = [
            "positive": [
                "unconditionalSeedHasSlot2": positiveSeed[2] != nil,
                "reachableHasSlot2": !(positiveReachable[2]?.isEmpty ?? true),
                "purpose": positiveSeed[2]?
                    .purpose(for: positiveReference)?.reportToken ?? "unproven",
                "hasTypedDemand": positiveCatalog.assetDemands.contains(
                    typedIdentity
                ),
                "issueCount": positiveCatalog.resourceDemandIssues.count,
            ],
            "negative": [
                "unconditionalSeedHasSlot2": negativeSeed[2] != nil,
                "reachableHasSlot2": !(negativeReachable[2]?.isEmpty ?? true),
                "demandCount": negativeCatalog.assetDemands.count,
                "hasPurposeIssue": hasPurposeIssue(
                    negativeCatalog,
                    path: unknownPath
                ),
            ],
            "optionalDefault": [
                "unconditionalSeedHasSlot2": optionalSeed[2] != nil,
                "readinessCombo": optionalSeed[2]?.readinessCombo ?? "missing",
                "reachableHasSlot2": !(optionalReachable[2]?.isEmpty ?? true),
                "demandCount": optionalCatalog.assetDemands.count,
                "issueCount": optionalCatalog.resourceDemandIssues.count,
                "hasPurposeIssue": hasPurposeIssue(
                    optionalCatalog,
                    path: optionalPath
                ),
            ],
            "activeOptionalDefault": [
                "reachableHasSlot2":
                    !(activeOptionalReachable[2]?.isEmpty ?? true),
                "hasTypedDemand": activeOptionalCatalog.assetDemands.contains(
                    optionalTypedIdentity
                ),
                "issueCount": activeOptionalCatalog.resourceDemandIssues.count,
            ],
            "graphAliasDefault": [
                "reachableHasSlot2":
                    !(graphAliasReachable[2]?.isEmpty ?? true),
                "demandCount": graphAliasCatalog.assetDemands.count,
                "issueCount": graphAliasCatalog.resourceDemandIssues.count,
                "hasPurposeIssue": hasPurposeIssue(
                    graphAliasCatalog,
                    path: graphAliasDefaultPath
                ),
            ],
            "formatDefault": [
                "reachableHasSlot2":
                    !(formatDefaultReachable[2]?.isEmpty ?? true),
                "demandCount": formatDefaultCatalog.assetDemands.count,
                "issueCount": formatDefaultCatalog.resourceDemandIssues.count,
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialExecutionCapabilityTests(unittest.TestCase):
    def test_authored_material_families_use_program_first_pair_adapters(self) -> None:
        source = EFFECT_BACKEND_SOURCE.read_text(encoding="utf-8")
        leaf_start = source.index("        var supportsUnifiedPairLeaf: Bool")
        logical_start = source.index(
            "    nonisolated var supportsUnifiedLogicalTargetStage: Bool"
        )
        leaf_body = source[leaf_start:logical_start]
        logical_end = source.index("\n    var gaussianBlur:", logical_start)
        logical_body = source[logical_start:logical_end]

        for backend_name in (
            ".blend", ".filmGrain", ".waterFlow", ".waterWaves",
            ".waterCaustics", ".waterRipple",
            ".depthParallax", ".xRay", ".pulse",
        ):
            self.assertIn(backend_name, leaf_body)
        self.assertNotIn("yieldsToResolvedMaterialProgram", source)
        self.assertNotIn(".lightShafts", leaf_body)
        self.assertIn("case .proceduralNoise(let plan):", leaf_body)
        for contract in (
            "plan.variant == .worleyColorV1",
            "plan.dependencyProviderLayerID != nil",
            "plan.dependencySlotIndex == 3",
        ):
            self.assertIn(contract, leaf_body)
        self.assertNotIn(".spin", source)
        self.assertIn(".workshopAudioBars", leaf_body)
        self.assertNotIn("fisheyeZeroDistortion", leaf_body)
        self.assertIn("case filmGrain(SceneFilmGrainExecutionPlan)", source)
        self.assertIn("case .preciseGaussian:", logical_body)
        self.assertIn("case .standardBlur:", logical_body)
        self.assertIn("case .localContrast:", logical_body)
        self.assertIn("case .godrays(let plan):", logical_body)
        logical_compact = "".join(logical_body.split())
        self.assertIn(
            "return(plan.direction==nil&&!plan.usesDirectionalGaussianKernel)"
            "||(plan.direction?.isFinite==true&&plan.usesDirectionalGaussianKernel)",
            logical_compact,
        )
        self.assertIn("case .shine:", logical_body)
        self.assertNotIn("case .cursorRipple:", logical_body)

        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertIn("Self.compileProgramFirstStages(", capability)
        stages = CAPABILITY_STAGES_SOURCE.read_text(encoding="utf-8")
        program_first = CAPABILITY_PROGRAM_FIRST_SOURCE.read_text(encoding="utf-8")
        for product_source in (stages, program_first):
            self.assertNotIn("yieldsToResolvedMaterialProgram", product_source)
        for empty_argument in (
            "dedicatedStagePrograms: []",
            "dedicatedStageFamilies: [:]",
            "dedicatedLeafKeys: []",
        ):
            self.assertNotIn(empty_argument, program_first)
        for removed_parameter in (
            "dedicatedStagePrograms:",
            "dedicatedStageFamilies:",
            "dedicatedLeafKeys:",
        ):
            self.assertNotIn(removed_parameter, stages)
        self.assertLess(
            program_first.index("let programResult = compileStages("),
            program_first.index("case let .failure(programFailure):"),
        )
        self.assertIn("dedicatedLeafKeys.contains(effect.key)", program_first)
        self.assertIn("dedicatedGraphStageKeys.contains(effect.key)", program_first)
        self.assertIn("supportsUnifiedLogicalTargetStage", program_first)
        self.assertIn(
            "dedicatedFullFrameComposeStageKeys.contains(effect.key)",
            program_first,
        )
        self.assertIn("supportsUnifiedFullFrameComposeStage", program_first)
        self.assertIn("product.graph.nodes.count == 2", program_first)
        self.assertIn("product.graph.renderTargets.isEmpty", program_first)
        self.assertIn("pairStep?.composeTransitionCount == 1", program_first)
        self.assertIn("pairStep?.fullFrameOutputWriteCount == 2", program_first)
        self.assertIn(
            "effect.input == admitted.pairPlan.baseCaptureIdentity",
            program_first,
        )
        self.assertIn("sourceRoute: stageSourceRoute", program_first)
        captured_route_start = program_first.index(
            "let sourceRouteExecutable ="
        )
        captured_route_end = program_first.index(
            "guard pairLeaf || logicalTargetStage || fullFrameComposeStage,",
            captured_route_start,
        )
        captured_route_guard = program_first[
            captured_route_start:captured_route_end
        ]
        captured_route_compact = "".join(captured_route_guard.split())
        self.assertIn(
            "stageSourceRoute!=.capturedMainTargetTexture"
            "||((pairLeaf||logicalTargetStage)"
            "&&program.executionPlan.supportsUtilityCapture)",
            captured_route_compact,
        )
        self.assertNotIn("fullFrameComposeStage", captured_route_guard)
        self.assertIn(
            "dynamicTargetsExecutable,\n                      sourceRouteExecutable else",
            program_first[captured_route_end:],
        )

    def test_frame_variant_resolution_consumes_only_the_launch_envelope(
        self,
    ) -> None:
        variant_cache = VARIANT_CACHE_SOURCE.read_text(encoding="utf-8")
        resolve_start = variant_cache.index("    func resolveSelection(")
        resolve_end = variant_cache.index(
            "    private func entry(", resolve_start
        )
        resolve_body = variant_cache[resolve_start:resolve_end]

        self.assertIn("guard hasCachedReachability", resolve_body)
        self.assertIn("for key in cachedLaunchEnvelopeKeys", resolve_body)
        self.assertIn(
            "guard case let .ready(variant)? = entries[key]",
            resolve_body,
        )
        self.assertNotIn("for (key, entry) in entries", resolve_body)
        self.assertIn(".variantKey(", resolve_body)
        self.assertNotIn("var activeSamplers = seedSamplers", resolve_body)
        self.assertNotIn("entry(for:", resolve_body)
        self.assertNotIn("prepareShaderStages", resolve_body)
        self.assertNotIn(
            "SceneResolvedMaterialShaderSchema.reachableSamplers(",
            variant_cache,
        )
        self.assertNotIn("reachable-sampler-schema", variant_cache)
        self.assertNotIn("reachableSamplersLocked", variant_cache)
        self.assertNotIn(
            "material-variant-envelope-invariant",
            CAPABILITY_PROGRAM_FIRST_SOURCE.read_text(encoding="utf-8"),
        )

    def test_generic_artifact_is_the_first_and_only_frontend_owner_on_hit(
        self,
    ) -> None:
        source = VARIANT_COMPILATION_SOURCE.read_text(encoding="utf-8")
        resolve_start = source.index(
            "let artifactResolution = "
            "SceneResolvedMaterialGenericShaderArtifactCache.resolve("
        )
        switch_start = source.index("switch artifactResolution", resolve_start)
        accepted_start = source.index("case let .accepted", switch_start)
        unavailable_start = source.index("case let .unavailable", accepted_start)
        switch_end = source.index("        guard\n", unavailable_start)
        accepted = source[accepted_start:unavailable_start]
        unavailable = source[unavailable_start:switch_end]

        self.assertLess(resolve_start, switch_start)
        self.assertNotIn("onBoundedFrontendCompilation()", accepted)
        self.assertNotIn("SceneAuthoredShaderFrontend.compile(", accepted)
        self.assertIn("guard permitsBoundedFrontend else", unavailable)
        revoked = unavailable[:unavailable.index("onBoundedFrontendCompilation()")]
        self.assertIn("bounded-frontend-owner-revoked", revoked)
        self.assertNotIn("SceneAuthoredShaderFrontend.compile(", revoked)
        self.assertIn("onBoundedFrontendCompilation()", unavailable)
        self.assertIn("SceneAuthoredShaderFrontend.compile(", unavailable)
        self.assertLess(
            unavailable.index("onBoundedFrontendCompilation()"),
            unavailable.index("SceneAuthoredShaderFrontend.compile("),
        )

    def test_generic_owner_profiles_use_active_graph_binding_facts(self) -> None:
        compilation = VARIANT_COMPILATION_SOURCE.read_text(encoding="utf-8")
        variant_cache = VARIANT_CACHE_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "graphTextureFormatFacts: [Graph.TextureIdentity: "
            "SceneShaderTextureFormat]",
            compilation,
        )
        self.assertIn("activeSamplerNames", compilation)
        self.assertIn("sourceActiveSamplers", compilation)
        self.assertIn("activeGraphTextureIdentities", compilation)
        self.assertIn("$0.value.kind == .framebuffer", compilation)
        self.assertIn("graphTextureSlots: graphTextureSlots", compilation)
        self.assertIn("template.graphRole.bindings", compilation)
        self.assertIn("implicitFramebufferIdentity != nil", compilation)
        self.assertIn("implicitFramebufferSlots", compilation)
        self.assertIn("usesGraphInputMaterialAlias", compilation)
        self.assertIn(
            "graphInputTextureSlots: graphInputTextureSlots",
            compilation,
        )
        self.assertIn("graphR8TextureSlots", compilation)
        self.assertIn("r8TextureSlots: graphR8TextureSlots", compilation)
        stages = (
            SCENE_ROOT
            / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift"
        ).read_text(encoding="utf-8")
        program_first = (
            SCENE_ROOT
            / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("bounded-frontend-owner-revoked", stages)
        generic_cache = GENERIC_SHADER_CACHE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("state != .observeOnly", generic_cache)
        self.assertIn('rejection("material-generic-owner-revoked")', stages)
        self.assertIn(
            'programFailure.code == "material-generic-owner-revoked"',
            program_first,
        )
        self.assertIn(
            '"material-generic-owner-revoked",',
            program_first,
        )
        self.assertIn(
            "visualFailureMayPassthrough(\n"
            "                           programFailure,",
            program_first,
        )
        owner_revoked_branch = program_first[
            program_first.index(
                'if programFailure.code == "material-generic-owner-revoked"'
            ):
            program_first.index(
                "guard product.clearFunctions.functions.isEmpty else",
                program_first.index(
                    'if programFailure.code == "material-generic-owner-revoked"'
                )
            )
        ]
        self.assertIn("product.clearFunctions.functions.isEmpty", owner_revoked_branch)
        self.assertIn("dependencyOwnership: admitted.dependencyOwnership", owner_revoked_branch)
        self.assertIn("return .failure(programFailure)", owner_revoked_branch)
        self.assertNotIn(
            "r8TextureSlots: Set(variantKey.resolvedTextureFormats",
            compilation,
        )
        self.assertIn("cachedGraphTextureFormatFacts", variant_cache)
        self.assertIn("launch-graph-texture-formats-changed", variant_cache)

    def test_launch_uses_one_admitted_batch_for_templates_demands_and_claims(
        self,
    ) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        renderer = RENDERER_SOURCE.read_text(encoding="utf-8")
        runtime_catalog = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (RUNTIME_CATALOG_SOURCE, RUNTIME_CATALOG_REPORT_SOURCE)
        )
        admission = ADMISSION_SOURCE.read_text(encoding="utf-8")
        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8") \
            + CAPABILITY_STAGES_SOURCE.read_text(encoding="utf-8")
        dependency_ownership = DEPENDENCY_OWNERSHIP_SOURCE.read_text(
            encoding="utf-8"
        )

        compile_call = (
            "SceneResolvedMaterialExecutionCapabilityAdmission.compile("
        )
        candidate_name = "resolvedMaterialAdmissionCandidates"
        self.assertEqual(launch.count(compile_call), 1)
        self.assertLess(
            launch.index(compile_call),
            launch.index(
                "let resolvedMaterialCatalog = SceneResolvedMaterialRuntimeCatalog("
            ),
        )
        self.assertGreaterEqual(launch.count(candidate_name), 3)
        self.assertIn(
            "admissionCandidates: resolvedMaterialAdmissionCandidates",
            launch,
        )
        self.assertIn(
            "demands: resolvedMaterialCatalog.assetDemands",
            launch,
        )
        self.assertIn("let timelineProgram =", launch)
        self.assertEqual(
            launch.count("SceneTimelineTargetCompiler.compile("),
            1,
        )
        compact_launch = "".join(launch.split())
        visibility_owner_source = compact_launch[
            compact_launch.index("typealiasVisibilityOwner=") :
            compact_launch.index("letdedicatedStageLeaves=")
        ]
        self.assertIn(
            "varframeDrivenEffectVisibilityOwners=Set<VisibilityOwner>()",
            visibility_owner_source,
        )
        self.assertNotIn(
            "userPropertyResolution.bindingReport",
            visibility_owner_source,
        )
        self.assertNotIn(
            "propertyBindingProgram.definitions",
            visibility_owner_source,
        )
        self.assertNotIn("rawRebuildEffectVisibilityOwners", launch)
        timeline_visibility_source = compact_launch[
            compact_launch.index("forbindingintimelineProgram.bindings") :
            compact_launch.index("forbindinginmodel.sceneDocument.scriptBindings")
        ]
        script_visibility_source = compact_launch[
            compact_launch.index("forbindinginmodel.sceneDocument.scriptBindings") :
            compact_launch.index("letdedicatedStageLeaves=")
        ]
        for global_visibility_source in (
            timeline_visibility_source,
            script_visibility_source,
        ):
            self.assertIn(
                "frameDrivenEffectVisibilityOwners.insert",
                global_visibility_source,
            )
            self.assertNotIn(
                "effects/xray",
                global_visibility_source,
            )
        self.assertIn(
            'binding.targetKey=="visible"',
            script_visibility_source,
        )
        self.assertNotIn("effectPath", script_visibility_source)
        admission_visibility_source = compact_launch[
            compact_launch.index("letresolvedMaterialAdmissionCandidates=") :
            compact_launch.index(
                "letresolvedMaterialCatalog=SceneResolvedMaterialRuntimeCatalog("
            )
        ]
        self.assertIn(
            "dynamicEffectVisibilityOwners:frameDrivenEffectVisibilityOwners",
            admission_visibility_source,
        )
        self.assertIn("timelineProgram.bindings", launch)
        self.assertIn("let timeOfDayEffectScriptCandidates =", launch)
        self.assertIn(
            "SceneMediaPlaybackPlaceholderFadeProgramCompiler.compile(",
            launch,
        )
        self.assertIn(
            "provenSceneScriptValueTargets: provenSceneScriptValueTargets",
            launch,
        )
        self.assertIn(
            "sceneScriptTargets: provenSceneScriptValueTargets",
            launch,
        )
        self.assertIn(
            "resolvedMaterialExecutionCapabilities.sceneScriptConsumerTargets",
            launch,
        )
        self.assertIn(
            "timeOfDayEffectScriptCandidateTargets.isDisjoint(",
            launch,
        )
        self.assertIn(
            "mediaPlaybackPlaceholderFadeCandidates.bindings.filter",
            launch,
        )
        self.assertLess(
            launch.index("let timeOfDayEffectScriptCandidates ="),
            launch.index("SceneResolvedMaterialExecutionCapabilityCatalog("),
        )
        self.assertLess(
            launch.index("SceneResolvedMaterialExecutionCapabilityCatalog("),
            launch.index("let timeOfDayEffectScriptProgram ="),
        )
        self.assertIn("model.sceneDocument.scriptBindings", launch)
        self.assertIn("case let .effectVisibility", launch)
        visibility_owner_source = launch[:launch.index("let dedicatedStageLeaves =")]
        self.assertNotIn("case let .effectConstant", visibility_owner_source)
        self.assertIn('binding.targetKey == "visible"', launch)
        self.assertNotIn("SceneScriptAudioBarsCompiler.compile(", launch)
        self.assertNotIn("sceneScriptAudioBarsProgram", launch)
        self.assertNotIn("specializedLayerIDs:", launch)
        self.assertNotIn("sceneScriptAudioBars", renderer)
        self.assertNotIn("renderSceneScriptAudioBars", renderer)
        product_source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(SCENE_ROOT.rglob("*.swift"))
        )
        self.assertNotIn("SceneScriptAudioBars", product_source)
        self.assertNotIn("sceneScriptAudioBars", product_source)
        self.assertNotIn("executableLayerIDs", launch)
        self.assertNotIn("executableLayerIDs", capability)
        self.assertNotIn("SceneEffectRuntimeDispositionCatalog(", launch)
        self.assertNotIn("resolvedMaterialExactEffectSubjects", launch)
        self.assertNotIn("executionEvidenceSubjects:", launch)
        for contract in (
            "SceneLayerVisibility.visibleLayerIDs(in: descriptor)",
            'case "image", "solid", "text":',
            'case "quad":',
            ".transparentDirectDraw",
            "if let utility = layer.utilityLayer",
            ".capturedMainTargetTexture",
            "layer.childLayerIDs.isEmpty",
            "SceneResolvedMaterialDependencyOwnershipCompiler",
            "guard let dependencyOwnership else",
        ):
            self.assertIn(contract, admission)
        self.assertNotIn("specializedLayerIDs", admission)
        self.assertNotIn("execution-route-specialized-owner", admission)
        self.assertIn(
            "sourceRoute == .capturedMainTargetTexture",
            capability,
        )
        self.assertIn(
            "variants.supportsCapturedMainTargetTexture",
            capability,
        )
        self.assertNotIn(
            "!variants.hasAudioSpectrumConsumer",
            capability,
        )
        for contract in (
            "layer.dependencyLayerIDs == [layer.id]",
            "layer.authoredDependencies.isEmpty",
            "$0.consumerLayerID == layer.id",
            "$0.providerLayerID == layer.id",
            "$0.variant == .primary",
            "binding.authoredName == \"previous\"",
            "binding.texture == effect.input",
        ):
            self.assertIn(contract, dependency_ownership)
        self.assertNotIn("sampleID", dependency_ownership)
        self.assertIn("case let .success(compiled):", capability)
        self.assertIn("stages: compiled.stages", capability)
        self.assertIn("runtimeDispositionOwnership(", capability)
        self.assertIn("runtimeDispositionOwnerships", capability)
        self.assertIn(
            "Set(keys) == Set(expected.map(\\.key))",
            capability,
        )
        self.assertNotIn("sampleID", capability)

        self.assertIn("admissionCandidates: [AdmissionCandidate]", runtime_catalog)
        self.assertIn("for candidate in admissionCandidates", runtime_catalog)
        self.assertIn(
            "guard case let .success(admitted) = candidate.result",
            runtime_catalog,
        )
        self.assertIn("for product in admitted.products", runtime_catalog)
        self.assertIn("for node in product.graph.nodes", runtime_catalog)
        self.assertNotIn("func admittedEntry(", runtime_catalog)
        self.assertIn("executable-material-v1", runtime_catalog)

    def test_raw_graph_admission_pair_and_token_contract(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-capability-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "resolved-material-capability-test"
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
        self.assertTrue(payload["claim"])
        self.assertTrue(payload["token"])
        self.assertEqual(
            payload["dispositionOwnership"],
            {
                "valid": True,
                "automatic": True,
                "duplicateRejected": True,
                "subjectMismatchRejected": True,
                "familyMismatchRejected": True,
                "foreignTokenRejected": True,
            },
        )
        self.assertEqual(payload["products"], 2)
        self.assertEqual(payload["effectIndices"], [0, 2])
        self.assertEqual(payload["pairTransitions"], 3)
        self.assertEqual(payload["pairBase"], 1)
        self.assertEqual(payload["pairTerminal"], 0)
        self.assertEqual(payload["prunedNodes"], [0, 2, 3])
        self.assertEqual(payload["prunedTargets"], ["history"])
        self.assertEqual(payload["composeNodes"], [2])
        self.assertTrue(payload["conditionFalseMaterialExcluded"])
        self.assertEqual(
            payload["implicitZeroCondition"],
            {
                "claimed": True,
                "keys": ["UNKNOWN"],
                "nodes": [0, 2, 3],
                "targets": ["history"],
            },
        )
        self.assertEqual(payload["materials"], 4)
        self.assertEqual(
            payload["fullFrameExtentPolicy"],
            {
                "maximumDimensionClass": "standard",
                "requiresExactInputExtent": False,
            },
        )
        self.assertEqual(
            payload["capacity"],
            {
                "effects": 512,
                "nodes": 65_536,
                "targets": 65_536,
                "rejectsOversized": True,
            },
        )
        self.assertIn("schema=layer-graph-capability-v1", payload["report"])
        self.assertIn("candidates=1 accepted=1 rejected=0", payload["report"])
        self.assertEqual(
            payload["acceptedRouteLines"],
            [
                "resolved material execution capability: "
                "schema=layer-graph-route-v1 layer=880 status=accepted "
                "dependency=none dependencyReferences=0"
            ],
        )
        self.assertEqual(
            payload["dependencyOwnership"],
            {
                "none": "none",
                "graphInternal": True,
                "graphInternalReport": (
                    "resolved material execution capability: "
                    "schema=layer-graph-route-v1 layer=880 status=accepted "
                    "dependency=graph-internal dependencyReferences=1"
                ),
                "externalPrimary": True,
                "externalPrimaryReport": (
                    "resolved material execution capability: "
                    "schema=layer-graph-route-v1 layer=880 status=accepted "
                    "dependency=external-primary dependencyReferences=1"
                ),
                "externalUtilityRoute": True,
                "externalUtilityStages": True,
                "externalProcedural": True,
            },
        )
        self.assertEqual(
            payload["rejections"],
            {
                "omitted": True,
                "discontinuous": True,
                "duplicate": True,
                "ambiguousDefinition": True,
                "unresolvedCondition": True,
                "missingTemplate": True,
                "functionInvocation": True,
                "dynamicVisibility": True,
                "validTimeline": True,
                "validSceneScript": True,
                "unknownScript": True,
                "multipleProducer": True,
                "multipleProducerNonLeafRemainsRejected": True,
                "multipleProducerPairLeafPassthrough": True,
                "multipleProducerPairLeafCounted": True,
                "multipleProducerMissingNonLeafRemainsRejected": True,
                "multipleProducerMissingPairLeafPassthrough": True,
                "multipleProducerMissingPairLeafCounted": True,
                "multipleProducerAllMissingPairLeafPassthrough": True,
                "multipleProducerMismatchedRemainsHard": True,
                "multipleProducerAttachmentRemainsHard": True,
                "unprovenScriptPairLeafPassthrough": True,
                "unprovenScriptPairLeafCounted": True,
                "scriptOnlyPairLeafPassthrough": True,
                "scriptOnlyPairLeafCounted": True,
                "scriptOnlyNoFallbackRemainsHard": True,
                "knownAttachmentWithoutValueRemainsHard": True,
                "duplicateScriptOnlyAttachmentRemainsHard": True,
                "unprovenScriptMissingProducerRemainsHard": True,
                "missingProducerPairLeafPassthrough": True,
                "missingProducerPairLeafCounted": True,
                "mismatchedProducerRemainsHard": True,
                "duplicateAttachmentRemainsHard": True,
                "knownControlWrongContributorRemainsHard": True,
                "missingProducer": True,
                "unverifiedSceneScript": True,
                "dedicatedBeforeResolvedAccepted": True,
                "alternatingMixedOrderAccepted": True,
                "alternatingMixedOrderContract": True,
                "resolvedBeforeDedicated": True,
                "emptyDedicatedLeafAllowlist": True,
                "fallbackDedicatedLeaf": True,
                "emptyDedicatedLeafDoesNotUseDedicated": True,
                "programFirstPrefersResolvedStage": True,
                "inactiveResourceDemandDoesNotRevokeProgram": True,
                "logicalTargetStageAccepted": True,
                "logicalTargetStageRequiresAllowlist": True,
                "logicalTargetStageRejectsHistory": True,
                "logicalTargetStageAcceptsCapturedMain": True,
                "logicalTargetStageCapturedMainRequiresUtilitySupport": True,
                "fullFrameComposeStageAccepted": True,
                "fullFrameComposeStageContract": True,
                "fullFrameComposeStageRequiresAllowlist": True,
                "fullFrameComposeStageRejectsCapturedMain": True,
                "fullFrameComposeStageRejectsHistory": True,
                "fullFrameComposeStageRejectsMissingCompose": True,
                "fullFrameComposeStageRejectsExtraNode": True,
                "externalResolvedMaterialAccepted": True,
                "externalResolvedMaterialRejectsSecondary": True,
                "externalResolvedMaterialRejectsWrongSlot": True,
                "externalResolvedMaterialRejectsWrongDependencyID": True,
                "externalResolvedMaterialRejectsAuthoredDependency": True,
                "externalResolvedMaterialAcceptsMultipleReferences": True,
                "externalResolvedMaterialRejectsProceduralBinding": True,
                "resolvedMaterialRejectsMissingExternalOwnership": True,
                "externalResolvedMaterialDoesNotFallback": True,
                "externalProceduralAccepted": True,
                "externalProceduralRejectsModern": True,
                "externalProceduralRejectsWrongProvider": True,
                "externalProceduralRejectsSecondary": True,
                "externalProceduralRejectsWrongEffect": True,
                "externalProceduralRejectsWrongPass": True,
                "externalProceduralRejectsWrongSlot": True,
                "externalProceduralRejectsWrongBlend": True,
                "externalProceduralRejectsMissingOwnership": True,
                "externalProceduralRejectsExtraReference": True,
                "externalProceduralRejectsExtraProvider": True,
                "externalProceduralRejectsMissingProviderPlan": True,
                "externalProceduralRejectsWrongInput": True,
                "externalProceduralRequiresUtilitySupport": True,
                "userPropertyLiveTarget": True,
                "hiddenParent": True,
                "unsupportedContent": True,
                "utilityCapture": True,
                "projectUtilityNonAudioAccepted": True,
                "utilityAdapterAccepted": True,
                "utilityAdapterContract": True,
                "downstreamUtilityAdapterAcceptedWithoutSourceCapture": True,
                "resolvedUtilityChainAccepted": True,
                "utilityKindMismatch": True,
                "utilityChildren": True,
                "legacyDependency": True,
                "authoredDependency": True,
                "namedReference": True,
                "selfReferenceMissingPrior": True,
                "selfReferenceSecondary": True,
                "selfReferenceWrongSlot": True,
                "selfReferenceExternalExtra": True,
                "selfReferenceAuthoredExtra": True,
            },
            payload,
        )

    def test_catalog_demands_only_defaults_retained_by_active_variants(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-catalog-demand-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "CatalogDemandHarness.swift"
            binary = root / "resolved-material-catalog-demand-test"
            support.write_text(CATALOG_DEMAND_SUPPORT, encoding="utf-8")
            harness.write_text(CATALOG_DEMAND_HARNESS, encoding="utf-8")
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
                    *(str(path) for path in CATALOG_DEMAND_SWIFT_SOURCES),
                    str(harness),
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
        self.assertEqual(
            payload["positive"],
            {
                "unconditionalSeedHasSlot2": True,
                "reachableHasSlot2": False,
                "purpose": "noise",
                "hasTypedDemand": True,
                "issueCount": 0,
            },
            payload,
        )
        self.assertEqual(
            payload["negative"],
            {
                "unconditionalSeedHasSlot2": True,
                "reachableHasSlot2": False,
                "demandCount": 0,
                "hasPurposeIssue": True,
            },
            payload,
        )
        self.assertEqual(
            payload["optionalDefault"],
            {
                "unconditionalSeedHasSlot2": True,
                "readinessCombo": "HAS_TEXTURE",
                "reachableHasSlot2": False,
                "demandCount": 0,
                "issueCount": 0,
                "hasPurposeIssue": False,
            },
            payload,
        )
        self.assertEqual(
            payload["activeOptionalDefault"],
            {
                "reachableHasSlot2": True,
                "hasTypedDemand": True,
                "issueCount": 0,
            },
            payload,
        )
        self.assertEqual(
            payload["graphAliasDefault"],
            {
                "reachableHasSlot2": True,
                "demandCount": 0,
                "issueCount": 0,
                "hasPurposeIssue": False,
            },
            payload,
        )
        self.assertEqual(
            payload["formatDefault"],
            {
                "reachableHasSlot2": True,
                "demandCount": 0,
                "issueCount": 0,
            },
            payload,
        )

    def test_launch_precompiles_the_static_texture_readiness_envelope(
        self,
    ) -> None:
        source_names = {path.name for path in ENVELOPE_SWIFT_SOURCES}
        self.assertTrue(
            {
                "SceneResolvedMaterialProgram.swift",
                "SceneResolvedMaterialShaderSchema.swift",
                "SceneResolvedMaterialShaderSchema+SamplerPurpose.swift",
                "SceneStockTextureSemanticRegistry.swift",
                "SceneAuthoredShaderUniformRGBMixAnalyzer.swift",
                "SceneAuthoredShaderUniformRGBMixAnalyzer+Scalar.swift",
                "SceneResolvedMaterialExecutionCapabilityVariant.swift",
                "SceneResolvedMaterialExecutionCapabilityVariant+CapturedMainTarget.swift",
                "SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift",
                "SceneResolvedMaterialTextureResolver.swift",
                "SceneResolvedMaterialTextureSelection.swift",
                "SceneResolvedMaterialTextureResolver+LaunchSelection.swift",
                "SceneResolvedMaterialTextureResolver+LaunchColor.swift",
                "SceneAuthoredShaderColorTransferAnalyzer.swift",
                "SceneAuthoredShaderColorTransferAnalyzer+Syntax.swift",
                "SceneAuthoredShaderStraightRGBAlphaFactorAnalyzer.swift",
                "SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer.swift",
                "SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer+Scalar.swift",
                "SceneAuthoredShaderConditionalAlphaAnalyzer.swift",
                "SceneAuthoredShaderPremultipliedOutputAnalyzer.swift",
                "SceneAuthoredShaderSameSlotMixAnalyzer.swift",
                "SceneAuthoredShaderColorMixGraphAnalyzer.swift",
                "SceneAuthoredShaderWholeVectorAffineParser.swift",
                "SceneAuthoredShaderStraightWholeColorFilterAnalyzer.swift",
                "SceneAuthoredShaderStraightWholeColorFilterAnalyzer+Syntax.swift",
                "SceneAuthoredShaderOpaqueInputAlphaAnalyzer.swift",
                "SceneAuthoredShaderOverlayAlphaBlendAnalyzer.swift",
                "SceneAuthoredShaderStraightBlendOutputAnalyzer.swift",
                "SceneAuthoredShaderFrontend.swift",
                "SceneAuthoredShaderPreparation.swift",
                "SceneAuthoredShaderPreparation+Support.swift",
                "SceneShaderContract.swift",
                "SceneShaderMalformedMetadataAdmission.swift",
                "SceneShaderPreprocessor.swift",
            }.issubset(source_names)
        )
        self.assertNotIn(
            "struct SceneResolvedMaterialTemplate",
            ENVELOPE_SUPPORT,
        )
        self.assertNotIn(
            "final class SceneResolvedMaterialVariantCache",
            ENVELOPE_SUPPORT,
        )
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-envelope-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "EnvelopeHarness.swift"
            binary = root / "resolved-material-envelope-test"
            support.write_text(ENVELOPE_SUPPORT, encoding="utf-8")
            harness.write_text(ENVELOPE_HARNESS, encoding="utf-8")
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
                    *(str(path) for path in ENVELOPE_SWIFT_SOURCES),
                    str(harness),
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
        self.assertTrue(payload["positiveClaim"])
        self.assertEqual(
            payload["positiveCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
            payload,
        )
        self.assertEqual(
            payload["effectProjectionRequirements"],
            {
                "resolvedWithoutMatrix": True,
                "modelViewProjectionOnly": True,
                "effectProjectionForward": True,
                "unusedEffectProjectionDeclaration": True,
                "effectProjectionInverse": True,
                "ordinaryDedicated": True,
                "pointerDedicated": True,
                "uncompiledResolvedCacheFailsClosed": True,
            },
            payload,
        )
        self.assertIn(
            "material-variant-envelope-shader-preparation",
            payload["shaderFailure"],
        )
        self.assertIn(
            "material-variant-envelope-frontend",
            payload["frontendFailure"],
        )
        self.assertIn(
            "material-variant-envelope-sampler-schema",
            payload["samplerSchemaFailure"],
        )
        self.assertEqual(
            payload["samplerBindingProvenance"],
            {
                "positive": "success",
                "order": "invariant:samplerBindingOrderInvalid:none:1:0",
                "duplicate": "invariant:samplerBindingDuplicateSlot:0",
                "identity": (
                    "invariant:samplerBindingIdentityMismatch:0:"
                    "sampler-name-or-slot:g_Texture1:g_Texture0"
                ),
                "variantPositive": "success",
                "variantDivergence": (
                    "preparation:samplerVariantSchemaDivergence:none:"
                    "texture-format-schema-divergence"
                ),
            },
            payload,
        )
        self.assertFalse(payload["internalSamplerTargetClaim"], payload)
        self.assertIn(
            "material-variant-envelope-invariant",
            payload["internalSamplerTargetFailure"],
            payload,
        )
        self.assertEqual(
            payload["internalSamplerTargetToken"],
            "preparation:samplerInternalTargetUnsupported:0:_rt_fixture",
            payload,
        )
        self.assertFalse(payload["activePassClaim"], payload)
        self.assertIn(
            "material-variant-envelope-invariant",
            payload["activePassFailure"],
            payload,
        )
        self.assertEqual(
            payload["activePassToken"],
            "preparation:activePassUnsupported:none:active-pass",
            payload,
        )
        self.assertIn(
            "material-variant-envelope-color-contract",
            payload["colorFailure"],
        )
        self.assertIn(
            "material-variant-envelope-color-contract",
            payload["typedColorFailure"],
            payload,
        )
        self.assertTrue(payload["wholeFilterClaim"], payload)
        self.assertEqual(payload["wholeFilterFailure"], "", payload)
        self.assertFalse(payload["wholeFilterInternalTargetClaim"], payload)
        self.assertIn(
            "material-template-unsupported",
            payload["wholeFilterInternalTargetFailure"],
            payload,
        )
        self.assertTrue(payload["sourceAlphaFactorClaim"], payload)
        self.assertEqual(payload["sourceAlphaFactorFailure"], "", payload)
        self.assertTrue(payload["scalarAlphaAuxiliaryClaim"], payload)
        self.assertEqual(payload["scalarAlphaAuxiliaryFailure"], "", payload)
        self.assertEqual(
            payload["scalarAlphaAuxiliaryCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
            payload,
        )
        self.assertTrue(payload["effectOutputTypedColorDeferredClaim"], payload)
        self.assertEqual(payload["effectOutputTypedColorDeferredFailure"], "", payload)
        self.assertIn(
            "material-variant-envelope-texture-purpose",
            payload["purposeFailure"],
        )
        self.assertIn(
            "material-variant-envelope-texture-purpose",
            payload["defaultPurposeFailure"],
        )
        self.assertTrue(payload["staticAssetDefaultClaim"], payload)
        self.assertEqual(payload["staticAssetDefaultFailure"], "")
        self.assertEqual(
            payload["staticAssetDefaultCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
        )
        self.assertTrue(payload["authoredAssetClaim"], payload)
        self.assertEqual(payload["authoredAssetFailure"], "")
        self.assertEqual(
            payload["authoredAssetCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
        )
        self.assertTrue(payload["highAbsentUsesLowClaim"], payload)
        self.assertEqual(payload["highAbsentUsesLowFailure"], "", payload)
        self.assertFalse(payload["highUnavailableBlocksLowClaim"], payload)
        self.assertIn(
            "material-variant-envelope-texture-binding",
            payload["highUnavailableBlocksLowFailure"],
            payload,
        )
        self.assertTrue(payload["maskedDefaultAbsentClaim"], payload)
        self.assertEqual(payload["maskedDefaultAbsentFailure"], "")
        self.assertEqual(
            payload["maskedDefaultAbsentCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
            payload,
        )
        self.assertEqual(payload["maskedDefaultAbsentChannelUses"], 0, payload)
        self.assertTrue(payload["maskedUnconditionalWithoutBindingClaim"], payload)
        self.assertEqual(payload["maskedUnconditionalWithoutBindingFailure"], "")
        self.assertEqual(
            payload["maskedUnconditionalWithoutBindingCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
            payload,
        )
        self.assertEqual(
            payload["maskedUnconditionalWithoutBindingChannelUses"], 1, payload
        )
        self.assertFalse(payload["maskedFormatDefaultClaim"], payload)
        self.assertIn(
            "material-variant-envelope-shader-preparation",
            payload["maskedFormatDefaultFailure"],
            payload,
        )
        self.assertTrue(payload["maskedPositiveClaim"], payload)
        self.assertEqual(payload["maskedPositiveFailure"], "")
        self.assertEqual(
            payload["maskedPositiveCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
            payload,
        )
        for key in ("maskedMissingConflict", "maskedPresentConflict"):
            self.assertIn(
                (
                    "material-variant-envelope-shader-preparation"
                    if key == "maskedMissingConflict"
                    else "material-variant-envelope-texture-binding"
                ),
                payload[key],
                payload,
            )
        self.assertTrue(payload["implicitPositiveClaim"])
        self.assertEqual(
            payload["implicitPositiveCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
        )
        self.assertTrue(payload["historicalImplicitPositiveClaim"], payload)
        self.assertEqual(
            payload["historicalImplicitPositiveCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
        )
        self.assertIn(
            "material-variant-envelope-texture-binding",
            payload["historicalImplicitWithoutHidden"],
        )
        self.assertIn(
            "material-variant-envelope-texture-binding",
            payload["implicitNegative"],
        )
        self.assertTrue(payload["providerPositiveClaim"])
        self.assertEqual(
            payload["providerPositiveCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
        )
        self.assertTrue(payload["crossLayerPositiveClaim"], payload)
        self.assertEqual(payload["crossLayerPositiveFailure"], "", payload)
        self.assertTrue(payload["crossLayerShadowedProvenanceClaim"], payload)
        self.assertEqual(payload["crossLayerShadowedProvenanceFailure"], "", payload)
        for key in (
            "crossLayerWrongProvider",
            "crossLayerSecondary",
            "crossLayerAmbiguous",
        ):
            self.assertIn("execution-stage-conservation", payload[key], payload)
        self.assertTrue(payload["directDrawPositiveClaim"], payload)
        self.assertEqual(payload["directDrawPositiveFailure"], "")
        self.assertEqual(
            payload["directDrawPositiveCounters"],
            {"cached": 2, "prepared": 2, "frontend": 2, "capacity": 0},
        )
        self.assertTrue(payload["audioDirectDrawClaim"], payload)
        self.assertTrue(payload["audioSpectrumConsumer"], payload)
        self.assertFalse(payload["directDrawSourceDependentClaim"])
        self.assertIn(
            "direct-draw-source-dependent",
            payload["directDrawSourceDependent"],
        )
        self.assertTrue(payload["capturedMainPositiveClaim"], payload)
        self.assertTrue(payload["capturedMainPositiveBindingsEmpty"], payload)
        self.assertEqual(payload["capturedMainPositiveFailure"], "", payload)
        self.assertTrue(payload["capturedMainImplicitClaim"], payload)
        self.assertTrue(payload["capturedMainImplicitBindingsEmpty"], payload)
        self.assertEqual(payload["capturedMainImplicitFailure"], "", payload)
        self.assertEqual(
            payload["capturedMainImplicitCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
        )
        for claim_key, failure_key in (
            (
                "capturedMainImplicitCompetingSourceClaim",
                "capturedMainImplicitCompetingSourceFailure",
            ),
            (
                "capturedMainCompetingSourceClaim",
                "capturedMainCompetingSourceFailure",
            ),
            (
                "capturedMainWrongModeClaim",
                "capturedMainWrongModeFailure",
            ),
            (
                "capturedMainDefaultSourceClaim",
                "capturedMainDefaultSourceFailure",
            ),
            (
                "capturedMainNoGraphInputClaim",
                "capturedMainNoGraphInputFailure",
            ),
            (
                "capturedMainWrongSourceClaim",
                "capturedMainWrongSourceFailure",
            ),
            (
                "capturedMainSecondGraphSourceClaim",
                "capturedMainSecondGraphSourceFailure",
            ),
            (
                "capturedMainIndependentAlphaSignalClaim",
                "capturedMainIndependentAlphaSignalFailure",
            ),
            (
                "capturedMainVariantMixedClaim",
                "capturedMainVariantMixedFailure",
            ),
        ):
            self.assertFalse(payload[claim_key], payload)
            self.assertIn(
                "utility-source-program-unsupported",
                payload[failure_key],
                payload,
            )
        self.assertFalse(payload["capturedMainUnresolvedColorClaim"], payload)
        self.assertIn(
            "material-variant-envelope-color-contract",
            payload["capturedMainUnresolvedColorFailure"],
            payload,
        )
        self.assertTrue(
            payload["capturedMainVariantMixedEnvelopePrepared"],
            payload,
        )
        self.assertEqual(
            payload["capturedMainVariantMixedEnvelopeFailure"],
            "",
            payload,
        )
        self.assertFalse(
            payload["capturedMainVariantMixedSupportsCapture"],
            payload,
        )
        self.assertEqual(
            payload["capturedMainVariantMixedCounters"],
            {"cached": 3, "prepared": 3, "frontend": 3, "capacity": 0},
            payload,
        )
        self.assertTrue(payload["capacityOneClaim"])
        self.assertEqual(
            payload["capacityOneCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
        )
        self.assertTrue(
            payload["capacityTwoClaim"],
            payload["capacityTwoFailure"],
        )
        self.assertEqual(
            payload["capacityTwoCounters"],
            {"cached": 2, "prepared": 2, "frontend": 2, "capacity": 0},
        )
        self.assertFalse(payload["capacityFailureClaim"])
        self.assertIn(
            "material-variant-envelope-capacity",
            payload["capacityFailure"],
        )
        self.assertEqual(
            payload["redOnlyChannelEnvelope"],
            {"allRed": True, "mixed": False, "empty": False},
            payload,
        )
        self.assertFalse(payload["partialClaim"])
        self.assertIn(
            "material-variant-envelope-shader-preparation",
            payload["partialFailure"],
        )
        self.assertIn(
            "candidates=1 accepted=0 rejected=1",
            payload["partialSummary"],
        )
        self.assertEqual(payload["partialAcceptedRoutes"], 0)


if __name__ == "__main__":
    unittest.main()
