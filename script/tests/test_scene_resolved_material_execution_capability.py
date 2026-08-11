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
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityVariant.swift"
)
SHADER_REACHABILITY_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/SceneResolvedMaterialShaderSchema+Reachability.swift"
)
DEPENDENCY_OWNERSHIP_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift"
)
RUNTIME_CATALOG_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialRuntimeCatalog.swift"
)
EFFECT_BACKEND_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan+Backend.swift"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphConditionAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphAdmissionCompiler.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Clear.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
    SCENE_ROOT / "RenderGraph/SceneLayerFullFramePairPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneOffscreenResolutionPolicy.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift",
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
    SCENE_ROOT / "RenderGraph/SceneOffscreenResolutionPolicy.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift",
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
]


SUPPORT = r'''
import Foundation

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
    let executionPlan: SceneAuthoredEffectExecutionPlan
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

    let references: [Reference]
    let namedReferenceConsumerLayerIDs: Set<Int>

    init(descriptor: SceneRenderDescriptor, visibleLayerIDs: Set<Int>) {
        references = descriptor.layers.flatMap(\.namedReferences)
        namedReferenceConsumerLayerIDs = Set(references.compactMap {
            visibleLayerIDs.contains($0.consumerLayerID) ? $0.consumerLayerID : nil
        })
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

struct SceneOpacityExecutionPlan {}

struct SceneAuthoredEffectExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let cursorRipple: SceneCursorRippleExecutionPlan?
    let opacity: SceneOpacityExecutionPlan?
    var yieldsToResolvedMaterialProgram = false
    var supportsUnifiedLogicalTargetStage = false
    var supportsUnifiedFullFrameComposeStage = false
    var supportsUtilityCapture = true
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

    enum TextureReference {
        case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
        case asset(String)
        case internalTarget(String)
    }

    struct TextureCandidate {
        let reference: TextureReference
    }

    struct TextureSlot {
        let candidates: [TextureCandidate]
    }

    enum DynamicUniformSource: Hashable {
        case userProperty(String)
        case timeline
        case sceneScript
    }

    enum DynamicUniformControlAttachment: Hashable {
        case mediaThumbnailAnimationRestart
        case unprovenSceneScript
    }

    struct DynamicUniform {
        let target: SceneDynamicTarget
        let valueContributors: [DynamicUniformSource]
        let controlAttachments: [DynamicUniformControlAttachment]
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
    }

    func precompileLaunchEnvelope(
        implicitFramebufferIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity?
    ) -> Result<[UInt8], LaunchEnvelopeFailure> {
        _ = implicitFramebufferIdentity
        return .success([1])
    }

    var supportsTransparentDirectDraw: Bool { true }
    var hasAudioSpectrumConsumer: Bool { audioSpectrumConsumer }
}
'''


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Catalog = SceneResolvedMaterialExecutionCapabilityCatalog
private typealias Template = SceneResolvedMaterialTemplate

private let layerID = 880

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

private func logicalTargetDescriptor() -> SceneRenderDescriptor {
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
            )]
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
            passCondition: condition(conditionName, 0)
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
                target(scratch, condition: condition(conditionName, 0)),
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
            target(scratch, condition: condition(conditionName, 0)),
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
    tint: Bool = false,
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
            yieldsToResolvedMaterialProgram: opacity || tint,
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
    namedReferences: [SceneDependencyRenderPlan.Reference] = []
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
    var layers: [SceneRenderDescriptor.Layer] = [.init(
            id: layerID,
            effects: [
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
                .init(
                    id: secondKey.descriptorID,
                    file: "effects/second/effect.json",
                    visible: true,
                    passes: [.init(passIndex: 0, combos: ["MODE": 1])]
                ),
            ],
            contentKind: contentKind,
            utilityLayer: utilityLayer.flatMap(SceneUtilityLayer.Kind.init)
                .map(SceneUtilityLayer.init),
            childLayerIDs: childLayerIDs,
            dependencyLayerIDs: dependencyLayerIDs,
            authoredDependencies: authoredDependencies,
            parentID: parentID,
            visible: true,
            namedReferences: namedReferences
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
    uniforms: [Template.UniformDeclaration] = []
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
    demandIssueNodes: Set<Int> = []
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
                uniforms: uniformsByNode[node.nodeIndex] ?? []
            )
        )
    }
    let demandIssues = Set(graph.nodes.compactMap { node in
        demandIssueNodes.contains(node.nodeIndex)
            ? SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue(
                key: .init(effect: node.effect, nodeIndex: node.nodeIndex)
            )
            : nil
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
    dynamicProducers: Catalog.DynamicProducerCatalog = .empty
) -> Catalog {
    let candidates = admissionCandidates
        ?? SceneResolvedMaterialExecutionCapabilityAdmission.compile(
            descriptor: value,
            authoredPlans: graphs
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
    allowDedicated: Bool
) -> Catalog {
    let program = dedicatedProgram(
        graph: graph,
        effectIndex: 0,
        inputRole: .layerSource,
        fullFrameComposeStage: true
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
    specializedLayerIDs: Set<Int> = [],
    reason: String
) -> Bool {
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [raw],
        specializedLayerIDs: specializedLayerIDs
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
    controls: [Template.DynamicUniformControlAttachment] = []
) -> Template.UniformDeclaration {
    .init(
        name: "strength",
        value: .dynamic(.init(
            target: dynamicTarget(),
            valueContributors: contributors,
            controlAttachments: controls
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
        let specializedCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: desc,
                authoredPlans: [raw],
                specializedLayerIDs: [layerID]
            )
        let routeUnavailableCatalog = catalog(
            descriptor: desc,
            graphs: [raw],
            materials: materialCatalog(graph: raw, omitNode: 1),
            admissionCandidates: specializedCandidates
        )
        let utilityCatalog = catalog(
            descriptor: descriptor(
                contentKind: "composition",
                utilityLayer: "composition"
            ),
            graphs: [raw],
            materials: materialCatalog(
                graph: raw,
                omitNode: 1,
                uniformsByNode: Dictionary(
                    uniqueKeysWithValues: [0, 2, 3, 4].map { index in
                        (index, [
                            .init(
                                name: "g_AudioSpectrum16Left",
                                value: .staticExact
                            ),
                        ])
                    }
                )
            )
        )
        let utilityRoute = utilityCatalog.claim(layerID: layerID)
            .flatMap { utilityCatalog.resolve($0.token)?.sourceRoute }
        let nonAudioUtilityCatalog = catalog(
            descriptor: descriptor(
                contentKind: "composition",
                utilityLayer: "composition"
            ),
            graphs: [raw],
            materials: materialCatalog(graph: raw, omitNode: 1)
        )
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
                omitNode: 1,
                uniformsByNode: [0: [
                    .init(name: "g_AudioSpectrum16Left", value: .staticExact),
                ]]
            ),
            dedicatedStageFamilies: [secondKey: "opacity"],
            dedicatedLeafKeys: [secondKey]
        )
        let utilityAdapterCapability = utilityAdapterCatalog.claim(layerID: layerID)
            .flatMap { utilityAdapterCatalog.resolve($0.token) }
        let unsupportedUtilityAdapterCandidates =
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
        let unsupportedUtilityAdapterCatalog = Catalog(
            admissionCandidates: unsupportedUtilityAdapterCandidates,
            materialCatalog: materialCatalog(
                graph: utilityPairGraph,
                omitNode: 1,
                uniformsByNode: [0: [
                    .init(name: "g_AudioSpectrum16Left", value: .staticExact),
                ]]
            ),
            dedicatedStageFamilies: [secondKey: "opacity"],
            dedicatedLeafKeys: [secondKey]
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
                    controls: [.unprovenSceneScript]
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
                    controls: [.unprovenSceneScript]
                )]]
            ),
            admissionCandidates: admissionCandidates
        )
        let pairGraph = pairOnlyGraph()
        let pairDescriptor = pairOnlyDescriptor()
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
        let resolvedBeforeTintCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: pairDescriptor,
                authoredPlans: [pairGraph],
                dedicatedStagePrograms: [dedicatedProgram(
                    graph: pairGraph,
                    effectIndex: 1,
                    inputRole: .priorEffectOutput,
                    tint: true
                )]
            )
        let resolvedBeforeTintCatalog = Catalog(
            admissionCandidates: resolvedBeforeTintCandidates,
            materialCatalog: materialCatalog(graph: pairGraph),
            dedicatedStageFamilies: [secondKey: "tint"],
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
            allowDedicated: true
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
                $0.contains("schema=r4-layer-route-v2")
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
                "functionInvocation": reportHas(
                    functionCatalog,
                    "function-invocation-unavailable"
                ),
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
                    "dynamic-uniform-unavailable"
                ),
                "multipleProducer": reportHas(
                    multipleProducerCatalog,
                    "dynamic-uniform-unavailable"
                ),
                "missingProducer": reportHas(
                    missingProducerCatalog,
                    "dynamic-uniform-unavailable"
                ),
                "unverifiedSceneScript": reportHas(
                    unverifiedSceneScriptCatalog,
                    "dynamic-uniform-unavailable"
                ),
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
                "tintYieldsToResolvedProgram":
                    resolvedBeforeTintCatalog.claim(layerID: layerID) != nil
                    && !reportHas(
                        resolvedBeforeTintCatalog,
                        "dedicated-leaf-unsupported"
                    ),
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
                "userPropertyLiveTarget":
                    validUserPropertyCatalog.liveConsumerTargets
                    == Set([dynamicTarget()]),
                "routeUnavailable": reportHas(
                    routeUnavailableCatalog,
                    "execution-route-specialized-owner"
                ) && routeUnavailableCatalog.claim(layerID: layerID) == nil
                    && routeUnavailableCatalog.reportLines.first?.contains(
                        "candidates=1 accepted=0 rejected=1"
                    ) == true,
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
                "utilityNonAudioRejected": reportHas(
                    nonAudioUtilityCatalog,
                    "utility-source-program-unsupported"
                ) && nonAudioUtilityCatalog.claim(layerID: layerID) == nil,
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
                "utilityAdapterRejectsUnsupportedCapture": reportHas(
                    unsupportedUtilityAdapterCatalog,
                    "dedicated-leaf-unsupported"
                ) && unsupportedUtilityAdapterCatalog.claim(layerID: layerID) == nil,
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
                "specializedOwner": admissionRejects(
                    desc,
                    raw: raw,
                    specializedLayerIDs: [layerID],
                    reason: "execution-route-specialized-owner"
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

enum SceneResolvedMaterialDependencyOwnership: Equatable {
    case none
    case graphInternal(referenceCount: Int)

    var reportKind: String {
        switch self {
        case .none: "none"
        case .graphInternal: "graph-internal"
        }
    }

    var referenceCount: Int {
        switch self {
        case .none: 0
        case let .graphInternal(referenceCount): referenceCount
        }
    }
}

struct SceneOpacityExecutionPlan {}

struct SceneAuthoredEffectExecutionPlan {
    let logicalRenderTargetCount: Int
    let opacity: SceneOpacityExecutionPlan?
    var yieldsToResolvedMaterialProgram = false
    var supportsUnifiedLogicalTargetStage = false
    var supportsUnifiedFullFrameComposeStage = false
    var supportsUtilityCapture = true
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

struct SceneEffectStageProgram {
    typealias ExecutionPlan = SceneAuthoredEffectExecutionPlan

    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let stageGraph: SceneAuthoredEffectRenderPlan
    let executionPlan: ExecutionPlan
}

struct SceneEffectExactRuntimeSubject: Hashable {
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let family: String
}

struct SceneGraphAdmissionProduct {
    let graph: SceneAuthoredEffectRenderPlan
}

struct SceneLayerFullFramePairPlan {
    struct EffectStep {
        let effect: SceneAuthoredEffectRenderPlan.EffectKey
        let composeTransitionCount: Int
        let fullFrameOutputWriteCount: Int
        let inputMember: Int
        let outputMember: Int
    }

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
        let dedicatedStagePrograms: [SceneEffectStageProgram] = []
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

    struct ResourceDemandIssue: Hashable { let key: Key }

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
    comboMetadata: String? = nil,
    firstMetadata: String? = nil,
    secondMetadata: String? = nil,
    conditionalSecond: Bool = false,
    frontendInvalid: Bool = false,
    invalidSamplerSlot: Bool = false,
    colorUnproven: Bool = false,
    samplesSecond: Bool = true,
    observesSecond: Bool = false,
    maskedAlpha: Bool = false,
    transparentDirectDraw: Bool = false,
    audioDirectDraw: Bool = false
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
    let output: String
    if audioDirectDraw {
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
        output = "vec4 color = texSample2D(\(firstName), v_TexCoord);"
            + " float mask = texSample2D(g_Texture1, v_TexCoord).r;"
            + " color.a *= mask * 0.5; gl_FragColor = color;"
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
    \(comboAnnotation)
    varying \(varyingType) v_TexCoord;
    uniform sampler2D \(firstName);\(firstAnnotation)
    \(audioDirectDraw ? "uniform float g_AudioSpectrum16Left[16];" : "")
    \(secondDeclaration)
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
    samplesSecond: Bool = true,
    observesSecond: Bool = false,
    maskedAlpha: Bool = false,
    transparentDirectDraw: Bool = false,
    audioDirectDraw: Bool = false
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
        samplesSecond: samplesSecond,
        observesSecond: observesSecond,
        maskedAlpha: maskedAlpha,
        transparentDirectDraw: transparentDirectDraw,
        audioDirectDraw: audioDirectDraw
    )
    let stages = [
        stage(.vertex, path: "\(revision)/root.vert", source: vertexSource),
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

private func graph(
    withPrimaryBinding: Bool,
    materialCount: Int = 1
) -> Graph {
    let bindings: [Graph.Binding] = withPrimaryBinding ? [
        .init(
            slot: 0,
            authoredName: "previous",
            texture: source(),
            conditions: nil
        ),
    ] : []
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
            target: output(),
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
            input: source(),
            output: output(),
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: [],
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

private func materialTemplate(
    graph: Graph,
    nodeIndex: Int = 0,
    shader: SceneShaderContract,
    slots: [Template.TextureSlot?],
    combos: [Template.Combo] = []
) -> Template {
    let node = graph.nodes[nodeIndex]
    return Template.validated(
        textureSlots: slots,
        combos: combos,
        uniformDeclarations: [],
        renderState: state(),
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: node.bindings.map {
                .init(slot: $0.slot!, texture: .layerSource)
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
    second: Template.TextureCandidate? = nil
) -> [Template.TextureSlot?] {
    var result = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    if let primary {
        result[0] = .init(index: 0, candidates: [primary])
    }
    if let second {
        result[1] = .init(index: 1, candidates: [second])
    }
    return result
}

private func catalog(
    graph: Graph,
    template: Template,
    maximumVariants: Int = 16,
    sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute = .capturedLayerTexture
) -> Catalog {
    catalog(
        graph: graph,
        templates: [graph.nodes[0].nodeIndex: template],
        maximumVariants: maximumVariants,
        sourceRoute: sourceRoute
    )
}

private func catalog(
    graph: Graph,
    templates: [Int: Template],
    maximumVariants: Int = 16,
    sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute = .capturedLayerTexture
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
        pairPlan: .init(),
        dependencyOwnership: .none,
        sourceRoute: sourceRoute
    )
    return .init(
        admissionCandidates: [.init(
            layerID: layerID,
            result: .success(admitted)
        )],
        materialCatalog: .init(
            entries: entries,
            resourceDemandIssues: []
        ),
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

@main
private enum EnvelopeHarness {
    static func main() throws {
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
        let colorFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("color-failure", colorUnproven: true),
                slots: slots(primary: graphCandidate())
            )
        )
        let purposeFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract("purpose-failure", secondMetadata: "{}"),
                slots: slots(
                    primary: graphCandidate(),
                    second: assetCandidate("textures/unproven.tex")
                )
            )
        )
        let defaultPurposeFailure = catalog(
            graph: boundGraph,
            template: materialTemplate(
                graph: boundGraph,
                shader: contract(
                    "default-purpose-failure",
                    secondMetadata: #"{"default":"textures/default.tex"}"#
                ),
                slots: slots(primary: graphCandidate())
            )
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
            )
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
            )
        )
        let maskMetadata = #"{"mode":"opacitymask","combo":"MASK"}"#
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
            )
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
            maximumVariants: 2
        )
        let capacityFailure = catalog(
            graph: boundGraph,
            template: twoVariantTemplate,
            maximumVariants: 1
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
            "shaderFailure": rejection(shaderFailure),
            "frontendFailure": rejection(frontendFailure),
            "samplerSchemaFailure": rejection(samplerSchemaFailure),
            "colorFailure": rejection(colorFailure),
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
            "implicitNegative": rejection(implicitNegative),
            "providerPositiveClaim": providerPositive.claim(layerID: layerID) != nil,
            "providerPositiveCounters": counters(
                providerPositive,
                graph: unboundGraph
            ),
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
        shaderContract: SceneShaderContract
    ) -> Result<Template, SceneResolvedMaterialFailure> {
        _ = material
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

private func fragmentSource(defaultPath: String) -> String {
    """
    // [COMBO] {"combo":"MODE","default":1,"options":{"Gradient":1,"RGB":2}}
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0; // {"material":"framebuffer"}
    uniform sampler2D g_Texture2; // {"default":"\(defaultPath)","require":{"MODE":1}}
    void main() {
    #if MODE == 1
        gl_FragColor = texSample2D(g_Texture2, v_TexCoord);
    #else
        gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
    #endif
    }
    """
}

private func contract(defaultPath: String) -> SceneShaderContract {
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
            source: fragmentSource(defaultPath: defaultPath)
        ),
    ]
    return .init(
        identity: "fixture/catalog-demand",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-catalog-demand-\(defaultPath)",
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
            dependencySHA256: "fixture-catalog-demand-dependency-\(defaultPath)"
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

        let positivePath = SceneVFSAssetPath("gradient/gradient_fire")!
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
            purpose: .preservedChannels
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
        yield_start = source.index(
            "    nonisolated var yieldsToResolvedMaterialProgram: Bool"
        )
        leaf_body = source[leaf_start:yield_start]
        yield_end = source.index("\n    var gaussianBlur:", yield_start)
        yield_body = source[yield_start:yield_end]
        logical_start = source.index(
            "    nonisolated var supportsUnifiedLogicalTargetStage: Bool"
        )
        logical_end = source.index("\n    var gaussianBlur:", logical_start)
        logical_body = source[logical_start:logical_end]

        for backend_name in (
            ".blend", ".filmGrain", ".waterFlow", ".waterWaves",
            ".waterCaustics", ".foliageSway", ".waterRipple",
            ".depthParallax", ".xRay", ".pulse",
        ):
            self.assertIn(backend_name, leaf_body)
        for backend_name in (
            ".blend", ".filmGrain", ".waterFlow", ".foliageSway",
            ".depthParallax",
        ):
            self.assertIn(backend_name, yield_body)
        for backend_name in (".proceduralNoise", ".lightShafts"):
            self.assertNotIn(backend_name, leaf_body)
        self.assertNotIn(".spin", source)
        self.assertIn(".workshopAudioBars", leaf_body)
        self.assertNotIn(".workshopAudioBars", yield_body)
        self.assertIn(".fisheyeZeroDistortion", leaf_body)
        self.assertIn("case filmGrain(SceneFilmGrainExecutionPlan)", source)
        self.assertIn("case .preciseGaussian:", logical_body)
        self.assertIn("case .standardBlur:", logical_body)
        self.assertIn("case .localContrast:", logical_body)
        self.assertIn("case .godrays(let plan):", logical_body)
        self.assertIn("plan.direction == nil", logical_body)
        self.assertIn("!plan.legacyGaussianWeights", logical_body)
        self.assertIn("case .shine:", logical_body)
        self.assertNotIn("case .cursorRipple:", logical_body)

        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertIn("Self.compileProgramFirstStages(", capability)
        program_first = CAPABILITY_PROGRAM_FIRST_SOURCE.read_text(encoding="utf-8")
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
            "admitted.sourceRoute != .capturedMainTargetTexture",
            program_first,
        )
        self.assertIn(
            "pairLeaf\n                            "
            "&& program.executionPlan.supportsUtilityCapture",
            program_first,
        )

    def test_runtime_variant_resolution_starts_from_launch_envelope_seed(
        self,
    ) -> None:
        variant_cache = VARIANT_CACHE_SOURCE.read_text(encoding="utf-8")
        reachability = SHADER_REACHABILITY_SOURCE.read_text(encoding="utf-8")
        resolve_start = variant_cache.index("    func resolve(")
        resolve_end = variant_cache.index(
            "    private func reachableSamplersLocked(", resolve_start
        )
        resolve_body = variant_cache[resolve_start:resolve_end]

        self.assertIn("var activeSamplers = seedSamplers", resolve_body)
        self.assertIn(".variantKey(", resolve_body)
        self.assertNotIn("cachedBootstrapSamplers", variant_cache)
        self.assertNotIn("prepareShaderStages", resolve_body)
        self.assertNotIn(".bootstrapSamplers(", resolve_body)
        self.assertIn("static func bootstrapSamplers(", reachability)

    def test_launch_uses_one_admitted_batch_for_templates_demands_and_claims(
        self,
    ) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        runtime_catalog = RUNTIME_CATALOG_SOURCE.read_text(encoding="utf-8")
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
        raw_visibility_census = (
            "model.sceneDocument.userPropertyResolution.bindingReport.bindings"
        )
        executable_visibility_census = (
            "runtimeInput.propertyBindingProgram.definitions"
        )
        compact_launch = "".join(launch.split())
        self.assertIn(raw_visibility_census, compact_launch)
        self.assertIn(executable_visibility_census, compact_launch)
        self.assertLess(
            compact_launch.index(raw_visibility_census),
            compact_launch.index(executable_visibility_census),
        )
        raw_visibility_owner_source = compact_launch[
            compact_launch.index(raw_visibility_census) : compact_launch.index(
                executable_visibility_census
            )
        ]
        self.assertIn("caselet.effectVisibility", raw_visibility_owner_source)
        self.assertIn("binding.target", raw_visibility_owner_source)
        self.assertIn(
            "rawRebuildEffectVisibilityOwners.insert",
            raw_visibility_owner_source,
        )
        self.assertNotIn(
            "dynamicEffectVisibilityOwners.insert",
            raw_visibility_owner_source,
        )
        self.assertNotIn("effects/xray", raw_visibility_owner_source.lower())
        full_frame_keys = "letdedicatedFullFrameComposeStageKeys="
        full_frame_layers = "letdedicatedFullFrameComposeLayerIDs="
        scoped_raw_merge = "dynamicEffectVisibilityOwners.formUnion("
        self.assertIn(full_frame_keys, compact_launch)
        self.assertIn(full_frame_layers, compact_launch)
        self.assertIn(scoped_raw_merge, compact_launch)
        self.assertLess(
            compact_launch.index(full_frame_keys),
            compact_launch.index(full_frame_layers),
        )
        self.assertLess(
            compact_launch.index(full_frame_layers),
            compact_launch.index(scoped_raw_merge),
        )
        scoped_raw_source = compact_launch[
            compact_launch.index(scoped_raw_merge) : compact_launch.index(
                "letresolvedMaterialAdmissionCandidates="
            )
        ]
        self.assertIn(
            "rawRebuildEffectVisibilityOwners.filter",
            scoped_raw_source,
        )
        self.assertIn(
            "dedicatedFullFrameComposeLayerIDs.contains($0.layerID)",
            scoped_raw_source,
        )
        executable_visibility_source = compact_launch[
            compact_launch.index(executable_visibility_census) : compact_launch.index(
                "forbindingintimelineProgram.bindings"
            )
        ]
        timeline_visibility_source = compact_launch[
            compact_launch.index("forbindingintimelineProgram.bindings") :
            compact_launch.index("forbindinginmodel.sceneDocument.scriptBindings")
        ]
        script_visibility_source = compact_launch[
            compact_launch.index("forbindinginmodel.sceneDocument.scriptBindings") :
            compact_launch.index("letdedicatedStageLeaves=")
        ]
        for global_visibility_source in (
            executable_visibility_source,
            timeline_visibility_source,
            script_visibility_source,
        ):
            self.assertIn(
                "dynamicEffectVisibilityOwners.insert",
                global_visibility_source,
            )
            self.assertNotIn(
                "rawRebuildEffectVisibilityOwners.insert",
                global_visibility_source,
            )
        admission_visibility_source = compact_launch[
            compact_launch.index("letresolvedMaterialAdmissionCandidates=") :
            compact_launch.index(
                "letresolvedMaterialCatalog=SceneResolvedMaterialRuntimeCatalog("
            )
        ]
        self.assertIn(
            "dynamicEffectVisibilityOwners:dynamicEffectVisibilityOwners",
            admission_visibility_source,
        )
        self.assertIn("timelineProgram.bindings", launch)
        self.assertIn("let timeOfDayEffectScriptCandidates =", launch)
        self.assertIn(
            "sceneScriptTargets: timeOfDayEffectScriptCandidateTargets",
            launch,
        )
        self.assertIn(
            "resolvedMaterialExecutionCapabilities.sceneScriptConsumerTargets",
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
        self.assertEqual(
            launch.count("SceneScriptAudioBarsCompiler.compile("),
            1,
        )
        self.assertIn(
            "sceneScriptAudioBarsProgram: sceneScriptAudioBarsProgram",
            launch,
        )
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
            "specializedLayerIDs.contains(layer.id)",
        ):
            self.assertIn(contract, admission)
        self.assertIn(
            "sourceRoute == .capturedMainTargetTexture",
            capability,
        )
        self.assertIn(
            "variants.hasAudioSpectrumConsumer",
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
        self.assertIn(
            "specializedLayerIDs: Set(\n"
            "                    sceneScriptAudioBarsProgram.plans.map(\\.layerID)",
            launch,
        )
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
        self.assertIn("r4-executable-material-v1", runtime_catalog)

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
        self.assertIn("schema=r4-layer-capability-v2", payload["report"])
        self.assertIn("candidates=1 accepted=1 rejected=0", payload["report"])
        self.assertEqual(
            payload["acceptedRouteLines"],
            [
                "resolved material execution capability: "
                "schema=r4-layer-route-v2 layer=880 status=accepted "
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
                    "schema=r4-layer-route-v2 layer=880 status=accepted "
                    "dependency=graph-internal dependencyReferences=1"
                ),
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
                "missingProducer": True,
                "unverifiedSceneScript": True,
                "dedicatedBeforeResolvedAccepted": True,
                "alternatingMixedOrderAccepted": True,
                "alternatingMixedOrderContract": True,
                "resolvedBeforeDedicated": True,
                "emptyDedicatedLeafAllowlist": True,
                "fallbackDedicatedLeaf": True,
                "emptyDedicatedLeafDoesNotUseDedicated": True,
                "tintYieldsToResolvedProgram": True,
                "logicalTargetStageAccepted": True,
                "logicalTargetStageRequiresAllowlist": True,
                "logicalTargetStageRejectsHistory": True,
                "fullFrameComposeStageAccepted": True,
                "fullFrameComposeStageContract": True,
                "fullFrameComposeStageRequiresAllowlist": True,
                "fullFrameComposeStageRejectsCapturedMain": True,
                "fullFrameComposeStageRejectsHistory": True,
                "fullFrameComposeStageRejectsMissingCompose": True,
                "fullFrameComposeStageRejectsExtraNode": True,
                "userPropertyLiveTarget": True,
                "routeUnavailable": True,
                "hiddenParent": True,
                "unsupportedContent": True,
                "utilityCapture": True,
                "utilityNonAudioRejected": True,
                "utilityAdapterAccepted": True,
                "utilityAdapterContract": True,
                "utilityAdapterRejectsUnsupportedCapture": True,
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
                "specializedOwner": True,
            },
            payload,
        )

    def test_catalog_preloads_unconditional_seed_defaults_without_promoting_reachability(
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
                "purpose": "preserved-channels",
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
                "SceneResolvedMaterialExecutionCapabilityVariant.swift",
                "SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift",
                "SceneResolvedMaterialTextureResolver.swift",
                "SceneAuthoredShaderColorTransferAnalyzer.swift",
                "SceneAuthoredShaderConditionalAlphaAnalyzer.swift",
                "SceneAuthoredShaderPremultipliedOutputAnalyzer.swift",
                "SceneAuthoredShaderSameSlotMixAnalyzer.swift",
                "SceneAuthoredShaderSameSlotMixGraphAnalyzer.swift",
                "SceneAuthoredShaderOpaqueInputAlphaAnalyzer.swift",
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
        self.assertIn(
            "material-variant-envelope-color-contract",
            payload["colorFailure"],
        )
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
        self.assertTrue(payload["maskedPositiveClaim"], payload)
        self.assertEqual(payload["maskedPositiveFailure"], "")
        self.assertEqual(
            payload["maskedPositiveCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
        )
        for key in ("maskedMissingConflict", "maskedPresentConflict"):
            self.assertIn(
                "material-variant-envelope-shader-preparation",
                payload[key],
                payload,
            )
        self.assertTrue(payload["implicitPositiveClaim"])
        self.assertEqual(
            payload["implicitPositiveCounters"],
            {"cached": 1, "prepared": 1, "frontend": 1, "capacity": 0},
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
