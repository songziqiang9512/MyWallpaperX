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
RUNTIME_CATALOG_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialRuntimeCatalog.swift"
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
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift",
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
        var utilityLayer: String? = nil
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var parentID: Int? = nil
        var visible: Bool? = true
        var namedReferenceConsumer = false
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
    let namedReferenceConsumerLayerIDs: Set<Int>

    init(descriptor: SceneRenderDescriptor, visibleLayerIDs: Set<Int>) {
        namedReferenceConsumerLayerIDs = Set(descriptor.layers.compactMap {
            visibleLayerIDs.contains($0.id) && $0.namedReferenceConsumer
                ? $0.id : nil
        })
    }
}

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneAuthoredEffectExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let cursorRipple: SceneCursorRippleExecutionPlan?
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

struct SceneResolvedMaterialFailure: Error {}

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
        enum Kind: String { case invariant }
        case invariant

        var kind: Kind { .invariant }
    }

    init?(
        template: SceneResolvedMaterialTemplate,
        maximumVariantCount: Int
    ) {
        _ = template
        guard (1 ... 256).contains(maximumVariantCount) else { return nil }
    }

    func precompileLaunchEnvelope(
        implicitFramebufferIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity?
    ) -> Result<[UInt8], LaunchEnvelopeFailure> {
        _ = implicitFramebufferIdentity
        return .success([1])
    }
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
    condition: SceneJSONValue? = nil
) -> Graph.RenderTarget {
    .init(
        texture: identity,
        extent: .init(width: nil, height: nil, fit: nil, scale: nil),
        format: "rgba_backbuffer",
        declaredUnique: false,
        clear: nil,
        uvs: nil,
        conditions: condition
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

private func descriptor(
    ambiguousDefinition: Bool = false,
    withFunctions: Bool = false,
    contentKind: String = "image",
    utilityLayer: String? = nil,
    dependencyLayerIDs: [Int] = [],
    authoredDependencies: [Int] = [],
    parentVisible: Bool? = nil,
    namedReferenceConsumer: Bool = false
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
            utilityLayer: utilityLayer,
            dependencyLayerIDs: dependencyLayerIDs,
            authoredDependencies: authoredDependencies,
            parentID: parentID,
            visible: true,
            namedReferenceConsumer: namedReferenceConsumer
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
    uniformsByNode: [Int: [Template.UniformDeclaration]] = [:]
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
    return .init(entries: entries, resourceDemandIssues: [])
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
                $0.contains("schema=r4-layer-route-v1")
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
                "utilityOwner": admissionRejects(
                    descriptor(utilityLayer: "composition"),
                    raw: raw,
                    reason: "execution-route-utility-owner"
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
                    descriptor(namedReferenceConsumer: true),
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

struct SceneEffectExactRuntimeSubject: Hashable {
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let family: String
}

struct SceneGraphAdmissionProduct {
    let graph: SceneAuthoredEffectRenderPlan
}

struct SceneLayerFullFramePairPlan {}

struct SceneResolvedMaterialAdmittedLayer {
    let layerID: Int
    let products: [SceneGraphAdmissionProduct]
    let pairPlan: SceneLayerFullFramePairPlan
}

enum SceneResolvedMaterialExecutionCapabilityAdmission {
    struct Failure: Error { let code: String }

    struct Candidate {
        let layerID: Int
        let result: Result<SceneResolvedMaterialAdmittedLayer, Failure>
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
    colorUnproven: Bool = false
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
    if colorUnproven {
        output = "vec4 color = texSample2D(\(firstName), v_TexCoord);"
            + " color.rgb *= 0.5; gl_FragColor = color;"
    } else if secondMetadata == nil {
        output = "gl_FragColor = texSample2D(\(firstName), v_TexCoord);"
    } else if conditionalSecond {
        output = """
        #if EXTRA
        gl_FragColor = texSample2D(\(firstName), v_TexCoord);
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
    colorUnproven: Bool = false
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
        colorUnproven: colorUnproven
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
    maximumVariants: Int = 16
) -> Catalog {
    catalog(
        graph: graph,
        templates: [graph.nodes[0].nodeIndex: template],
        maximumVariants: maximumVariants
    )
}

private func catalog(
    graph: Graph,
    templates: [Int: Template],
    maximumVariants: Int = 16
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
        pairPlan: .init()
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
                secondMetadata: #"{"material":"framebuffer"}"#,
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


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialExecutionCapabilityTests(unittest.TestCase):
    def test_launch_uses_one_admitted_batch_for_templates_demands_and_claims(
        self,
    ) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        runtime_catalog = RUNTIME_CATALOG_SOURCE.read_text(encoding="utf-8")
        admission = ADMISSION_SOURCE.read_text(encoding="utf-8")
        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8")

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
        self.assertIn(
            "runtimeInput.propertyBindingProgram.definitions",
            launch,
        )
        self.assertIn("timelineProgram.bindings", launch)
        self.assertIn("model.sceneDocument.scriptBindings", launch)
        self.assertIn("case let .effectVisibility", launch)
        self.assertNotIn("case let .effectConstant", launch)
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
            '["image", "solid", "text"].contains(layer.contentKind)',
            "case .none = layer.utilityLayer",
            "layer.dependencyLayerIDs.isEmpty",
            "layer.authoredDependencies.isEmpty",
            "!namedReferenceConsumerLayerIDs.contains(layer.id)",
            "specializedLayerIDs.contains(layer.id)",
        ):
            self.assertIn(contract, admission)
        self.assertIn(
            "specializedLayerIDs: Set(\n"
            "                    sceneScriptAudioBarsProgram.plans.map(\\.layerID)",
            launch,
        )
        self.assertIn("case let .success(materials):", capability)
        self.assertIn("runtimeDispositionOwnership(", capability)
        self.assertIn("runtimeDispositionOwnerships", capability)
        self.assertIn("Set(keys) == Set(expected)", capability)
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
                "schema=r4-layer-route-v1 layer=880 status=accepted"
            ],
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
                "unknownScript": True,
                "multipleProducer": True,
                "missingProducer": True,
                "unverifiedSceneScript": True,
                "routeUnavailable": True,
                "hiddenParent": True,
                "unsupportedContent": True,
                "utilityOwner": True,
                "legacyDependency": True,
                "authoredDependency": True,
                "namedReference": True,
                "specializedOwner": True,
            },
        )

    def test_launch_precompiles_the_static_texture_readiness_envelope(
        self,
    ) -> None:
        source_names = {path.name for path in ENVELOPE_SWIFT_SOURCES}
        self.assertTrue(
            {
                "SceneResolvedMaterialProgram.swift",
                "SceneResolvedMaterialShaderSchema.swift",
                "SceneResolvedMaterialExecutionCapabilityVariant.swift",
                "SceneResolvedMaterialTextureResolver.swift",
                "SceneAuthoredShaderColorTransferAnalyzer.swift",
                "SceneAuthoredShaderFrontend.swift",
                "SceneAuthoredShaderExecutionPlanner+Preparation.swift",
                "SceneShaderContract.swift",
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
