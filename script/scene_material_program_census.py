#!/usr/bin/env python3
"""Reproducible R3 Scene material Template/Program census.

The runtime report supplies production parser facts. The Swift probe rebuilds
the authored graph with the current planner, reloads shader contracts through
the current VFS/source-graph loader, then resolves and compiles every material
node through the shared R3 Template boundary. Program finalization is reported
separately and remains not-attempted when immutable runtime snapshots are not
present in the evidence input.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
from typing import Any, Iterable, Sequence

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = Path(__file__).resolve()
SCRIPT_DIRECTORY = SCRIPT_PATH.parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from scene_real_test_fixture_config import load_fixture_config
from scene_swift_source_sets import (
    scene_swift_source_relpaths,
    scene_swift_source_relpaths_by_basename,
)


DEFAULT_FIXTURE = SCRIPT_PATH.with_name("scene_real_test_fixture.json")
DEFAULT_MATRIX = SCRIPT_PATH.with_name("scene_wallpaper_full_sample_matrix.json")
DEFAULT_STOCK_ROOT = (
    REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
)
REAL_WORKSHOP_ROOT = (Path.home() / "Movies/MyWallpaperX/创意工坊").resolve()

AUTHORED_SHADER_PREPARATION_SOURCES = scene_swift_source_relpaths(
    "authored_shader_preparation_implementation"
)
AUTHORED_EFFECT_PLANNING_SOURCES = scene_swift_source_relpaths_by_basename(
    "authored_effect_planning_support"
)

CURRENT_SOURCE_PATHS = (
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneJSONValue.swift"],
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneEffectTextureInput.swift",
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneEffectDefinition.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneAuthoredEffectRenderPlan.swift"],
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlanner.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlanner+Resolution.swift",
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneAuthoredMaterialResolver.swift"],
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneMaterialRenderState.swift",
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderSourceGraph.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderLegacyAnnotationJSON.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderContract.swift"],
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderFrontend/SceneAuthoredShaderFrontendModel.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderFrontend/SceneAuthoredShaderTextureTransformABI.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderFrontend/SceneAuthoredShaderLexer.swift",
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderSourceGraphBuilder.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderSourceResolver.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneResourceView.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneResourceIndex.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderContractLoader.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES[
        "SceneShaderContractLoader+SourceGraph.swift"
    ],
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureSampling.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureUVTransform.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureCandidate.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneNamedTextureReference.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureSlotBinding.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureProviderPublication.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneFrameTextureRegistry.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/SceneResolvedMaterialProgram.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/SceneResolvedMaterialProgramIdentity.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/SceneResolvedMaterialEffectIngress.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/SceneResolvedMaterialScriptBindingClassifier.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/SceneResolvedMaterialTemplateCompiler.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift",
    *AUTHORED_SHADER_PREPARATION_SOURCES,
)


HARNESS_SOURCE = r'''
import CryptoKit
import Foundation

// This census only needs the compile-input collection shape; typed producer
// identity is exercised by the product/runtime capability tests.
struct SceneDynamicUserPropertyProducer: Hashable {}

// The production descriptor is intentionally decoded into the smallest exact
// view consumed by the current planner/resolver. This keeps the census linked
// to the real implementation without pulling unrelated runtime executors into
// the standalone probe.
struct SceneDocument {}

enum SceneShaderUserValueKind: String, Decodable {
    case null, boolean, number, string, array, object
}

extension SceneDocument {
    struct ShaderValue: Decodable {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let userValueKind: SceneShaderUserValueKind?
        let components: [Double]?
        let timeline: SceneJSONValue?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]
    }
}

struct SceneRenderDescriptor: Decodable {
    struct EffectDescriptor: Decodable {
        struct PassDescriptor: Decodable {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer: Decodable {
        let id: Int
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor: Decodable {
        let id: String
        let materialPath: String
        let materialRawSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let entryPath: String
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
    let shaderReferences: [String]
}

// Template compilation uses these production concepts, while Program
// finalization is deliberately unavailable without immutable frame snapshots.
enum SceneDynamicTarget: Hashable {
    case effectConstant(
        layerID: Int, effectIndex: Int, passIndex: Int, name: String
    )
}

enum SceneDynamicSource: Hashable {
    case authored, userProperty, timeline, sceneScript
}

enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor, straightAlbedo, preservedChannels
    case mask, noise, flow, phase, normal, depth, lookupTable

    var requiresVolumeTexture: Bool { self == .lookupTable }
}

enum SceneResolvedMaterialProgramDerivation {
    static func derive(
        _ input: SceneResolvedMaterialProgram.AssemblyInput
    ) -> SceneResolvedMaterialProgram.Derived? {
        nil
    }

    static func deriveCompiled(
        _ input: SceneResolvedMaterialProgram.AssemblyInput,
        frontend: SceneAuthoredShaderProgram
    ) -> SceneResolvedMaterialProgram.Derived? {
        nil
    }

    static func uniqueAndValid(
        _ layout: SceneAuthoredShaderUniformLayout
    ) -> Bool {
        guard layout.byteSize >= 0,
              layout.byteSize <= 4_096,
              layout.byteSize.isMultiple(of: 16),
              Set(layout.fields.map(\.name)).count == layout.fields.count else {
            return false
        }
        var end = 0
        for field in layout.fields {
            guard !field.name.isEmpty,
                  field.offset >= end,
                  field.offset.isMultiple(of: field.type.alignment),
                  field.arrayCount.map({ (1 ... 64).contains($0) }) ?? true,
                  field.offset <= layout.byteSize - field.storageByteSize else {
                return false
            }
            end = field.offset + field.storageByteSize
        }
        return end <= layout.byteSize
    }
}

private struct InputManifest: Decodable {
    struct Sample: Decodable {
        let sampleID: String
        let projectRoot: String
        let projectPath: String
        let packagePath: String
        let packageRoot: String
        let runtimeEvidencePath: String
        let projectSHA256: String
        let packageSHA256: String
        let runtimeEvidenceSHA256: String
        let runtimeInputSHA256: String
        let runtimeSnapshotState: String
    }
    let samples: [Sample]
}

private struct EvidenceEnvelope: Decodable {
    struct RuntimeInput: Decodable {
        let renderDescriptor: SceneRenderDescriptor
        let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
        let shaderContracts: [SceneShaderContract]
    }
    let schemaVersion: Int
    let sourceEntryPath: String
    let runtimeInput: RuntimeInput
}

private struct SampleKey: Codable, Hashable {
    let sampleID: String
    let projectSHA256: String
    let packageSHA256: String
    let runtimeInputSHA256: String
}

private struct GraphKey: Codable, Hashable {
    let sampleID: String
    let layerID: Int
}

private struct EffectKey: Codable, Hashable {
    let sampleID: String
    let layerID: Int
    let effectIndex: Int
    let descriptorID: String
}

private struct NodeKey: Codable, Hashable {
    let sampleID: String
    let layerID: Int
    let nodeIndex: Int
}

private struct GraphRecord: Codable {
    let key: GraphKey
    let effectCount: Int
    let nodeCount: Int
    let materialNodeCount: Int
    let copyNodeCount: Int
    let swapNodeCount: Int
    let unknownNodeCount: Int
    let renderTargetCount: Int
    let blockerCount: Int
}

private struct EffectRecord: Codable {
    let key: EffectKey
    let nodeCount: Int
}

private struct SlotRecord: Codable {
    struct Candidate: Codable {
        let provenance: String
        let referenceKind: String
        let chainLabel: String
    }
    let index: Int
    let candidates: [Candidate]
}

private struct OutcomeRecord: Codable {
    let status: String
    let phase: String?
    let code: String?
    let details: [String]
}

private struct ActiveSamplerRecord: Codable {
    let slot: Int
    let annotationFields: [String]
    let modeValues: [String]
    let materialValues: [String]
    let defaultValueKinds: [String]
    let formatValues: [String]
    let purposeValues: [String]
}

private struct PreparationRecord: Codable {
    let outcome: OutcomeRecord
    let activeSamplerSlots: [Int]
    let activeSamplers: [ActiveSamplerRecord]
    let samplerAnnotationFields: [String]
    let colorContractResolved: Bool?
}

private struct StateRecord: Codable {
    let blending: String
    let depthTest: String
    let depthWrite: String
    let cullMode: String
    let alphaWriting: String
}

private struct MultiContributorUniformRecord: Codable {
    let name: String
    let contributorKinds: [String]
    let bindingKeys: [String]
    let componentCount: Int?
    let hasTimeline: Bool
    let timelineMode: String?
    let timelineStartsPaused: Bool?
    let timelineIsRelative: Bool?
    let timelineLaneKeyframeCounts: [Int]
    let hasScriptSource: Bool
    let scriptShape: String
}

private struct NodeRecord: Codable {
    let key: NodeKey
    let effectKey: EffectKey
    let kind: String
    let definitionPassIndex: Int
    let materialPassID: String?
    let descriptorMaterialPassIndex: Int?
    let materialRawSHA256: String?
    let shaderIdentity: String?
    let contractCanonicalSHA256: String?
    let resolution: OutcomeRecord
    let resolvedFixedSlotCount: Int?
    let resolvedSlots: [SlotRecord]
    let template: OutcomeRecord
    let fixedSlotCount: Int?
    let slots: [SlotRecord]
    let state: StateRecord?
    let multiContributorUniforms: [MultiContributorUniformRecord]
    let preparation: PreparationRecord
    let program: OutcomeRecord
}

private struct ContractRecord: Codable {
    let identity: String
    let canonicalSHA256: String
    let sourceGraphDependencySHA256: String?
    let diagnostics: [String]
}

private struct SampleRecord: Codable {
    let key: SampleKey
    let descriptorEffectsActive: Int
    let descriptorEffectsInactive: Int
    let authoredPlanCount: Int
    let materialFilePassCount: Int
    let contractProjectionValidated: Bool
    let contracts: [ContractRecord]
    let graphs: [GraphRecord]
    let effects: [EffectRecord]
    let nodes: [NodeRecord]
}

private struct CorpusOutput: Codable {
    let schemaVersion: Int
    let implementation: String
    let samples: [SampleRecord]
}

private enum HarnessError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidInput(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "expected <input-manifest> <stock-assets-root>"
        case .invalidInput(let message):
            return message
        }
    }
}

@main
private enum MaterialProgramCensusHarness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw HarnessError.invalidArguments
        }
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let stockRoot = URL(
            fileURLWithPath: CommandLine.arguments[2], isDirectory: true
        ).standardizedFileURL
        let manifest = try JSONDecoder().decode(
            InputManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        var records: [SampleRecord] = []
        var preparationCache: [String: PreparationRecord] = [:]
        for sample in manifest.samples.sorted(by: { $0.sampleID < $1.sampleID }) {
            records.append(try sampleRecord(
                sample,
                stockRoot: stockRoot,
                preparationCache: &preparationCache
            ))
        }
        let output = CorpusOutput(
            schemaVersion: 2,
            implementation: "r3-worktree",
            samples: records
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(output))
    }

    private static func sampleRecord(
        _ sample: InputManifest.Sample,
        stockRoot: URL,
        preparationCache: inout [String: PreparationRecord]
    ) throws -> SampleRecord {
        guard sample.runtimeSnapshotState == "unavailable" else {
            throw HarnessError.invalidInput(
                "sample \(sample.sampleID) has an unsupported runtime snapshot state"
            )
        }
        let projectData = try Data(contentsOf: URL(fileURLWithPath: sample.projectPath))
        let packageData = try Data(contentsOf: URL(fileURLWithPath: sample.packagePath))
        let evidenceData = try Data(
            contentsOf: URL(fileURLWithPath: sample.runtimeEvidencePath)
        )
        guard sha256(projectData) == sample.projectSHA256,
              sha256(packageData) == sample.packageSHA256,
              sha256(evidenceData) == sample.runtimeEvidenceSHA256 else {
            throw HarnessError.invalidInput(
                "sample \(sample.sampleID) input identity changed"
            )
        }
        let envelope = try JSONDecoder().decode(EvidenceEnvelope.self, from: evidenceData)
        guard envelope.schemaVersion == 1,
              envelope.sourceEntryPath == envelope.runtimeInput.renderDescriptor.entryPath else {
            throw HarnessError.invalidInput(
                "sample \(sample.sampleID) evidence envelope identity is invalid"
            )
        }
        let descriptor = envelope.runtimeInput.renderDescriptor
        let planned = SceneAuthoredEffectRenderPlanner.plans(for: descriptor)
        guard try canonicalData(planned)
                == canonicalData(envelope.runtimeInput.authoredEffectRenderPlans) else {
            throw HarnessError.invalidInput(
                "sample \(sample.sampleID) current authored graph differs from runtime evidence"
            )
        }
        let view = SceneResourceView(
            projectRootURL: URL(fileURLWithPath: sample.projectRoot, isDirectory: true),
            packageRootURL: URL(fileURLWithPath: sample.packageRoot, isDirectory: true),
            stockAssetsRootURL: stockRoot
        )
        try validateMaterialResources(
            descriptor.materialPasses,
            resourceView: view,
            sampleID: sample.sampleID
        )
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: descriptor.shaderReferences,
            resourceView: view
        )
        let projectionValidated = try validateContractProjection(
            current: contracts,
            runtime: envelope.runtimeInput.shaderContracts,
            sampleID: sample.sampleID
        )
        let contractsByIdentity = Dictionary(
            grouping: contracts,
            by: { normalizedShaderIdentity($0.identity) }
        )

        var graphRecords: [GraphRecord] = []
        var effectRecords: [EffectRecord] = []
        var nodeRecords: [NodeRecord] = []
        for graph in planned {
            graphRecords.append(graphRecord(graph, sampleID: sample.sampleID))
            effectRecords.append(contentsOf: graph.effects.map {
                EffectRecord(
                    key: effectKey($0.key, sampleID: sample.sampleID),
                    nodeCount: $0.nodeIndices.count
                )
            })
            for node in graph.nodes {
                nodeRecords.append(nodeRecord(
                    node,
                    graph: graph,
                    descriptor: descriptor,
                    contractsByIdentity: contractsByIdentity,
                    sampleID: sample.sampleID,
                    preparationCache: &preparationCache
                ))
            }
        }
        graphRecords.sort { ($0.key.sampleID, $0.key.layerID)
            < ($1.key.sampleID, $1.key.layerID) }
        effectRecords.sort {
            ($0.key.sampleID, $0.key.layerID, $0.key.effectIndex, $0.key.descriptorID)
                < ($1.key.sampleID, $1.key.layerID, $1.key.effectIndex, $1.key.descriptorID)
        }
        nodeRecords.sort {
            ($0.key.sampleID, $0.key.layerID, $0.key.nodeIndex)
                < ($1.key.sampleID, $1.key.layerID, $1.key.nodeIndex)
        }
        guard Set(graphRecords.map(\.key)).count == graphRecords.count,
              Set(effectRecords.map(\.key)).count == effectRecords.count,
              Set(nodeRecords.map(\.key)).count == nodeRecords.count else {
            throw HarnessError.invalidInput(
                "sample \(sample.sampleID) contains duplicate scoped graph keys"
            )
        }
        let active = descriptor.layers.flatMap(\.effects).filter { $0.visible != false }.count
        let inactive = descriptor.layers.flatMap(\.effects).filter { $0.visible == false }.count
        return .init(
            key: .init(
                sampleID: sample.sampleID,
                projectSHA256: sample.projectSHA256,
                packageSHA256: sample.packageSHA256,
                runtimeInputSHA256: sample.runtimeInputSHA256
            ),
            descriptorEffectsActive: active,
            descriptorEffectsInactive: inactive,
            authoredPlanCount: planned.count,
            materialFilePassCount: descriptor.materialPasses.count,
            contractProjectionValidated: projectionValidated,
            contracts: contracts.map {
                .init(
                    identity: $0.identity,
                    canonicalSHA256: $0.canonicalSHA256,
                    sourceGraphDependencySHA256: $0.sourceGraph?.dependencySHA256,
                    diagnostics: $0.diagnostics.map { $0.code.rawValue }
                )
            }.sorted { ($0.identity, $0.canonicalSHA256)
                < ($1.identity, $1.canonicalSHA256) },
            graphs: graphRecords,
            effects: effectRecords,
            nodes: nodeRecords
        )
    }

    private static func graphRecord(
        _ graph: Graph,
        sampleID: String
    ) -> GraphRecord {
        .init(
            key: .init(sampleID: sampleID, layerID: graph.layerID),
            effectCount: graph.effects.count,
            nodeCount: graph.nodes.count,
            materialNodeCount: graph.nodes.filter { $0.kind == .material }.count,
            copyNodeCount: graph.nodes.filter { $0.kind == .copy }.count,
            swapNodeCount: graph.nodes.filter { $0.kind == .swap }.count,
            unknownNodeCount: graph.nodes.filter { $0.kind == .unknownCommand }.count,
            renderTargetCount: graph.renderTargets.count,
            blockerCount: graph.blockers.count
        )
    }

    private static func nodeRecord(
        _ node: Graph.Node,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        contractsByIdentity: [String: [SceneShaderContract]],
        sampleID: String,
        preparationCache: inout [String: PreparationRecord]
    ) -> NodeRecord {
        let key = NodeKey(
            sampleID: sampleID,
            layerID: graph.layerID,
            nodeIndex: node.nodeIndex
        )
        let scopedEffect = effectKey(node.effect, sampleID: sampleID)
        let program = OutcomeRecord(
            status: "notAttempted",
            phase: "runtime-snapshot",
            code: "runtime-snapshot-unavailable",
            details: []
        )
        guard node.kind == .material else {
            let unavailable = OutcomeRecord(
                status: "notApplicable", phase: "graph",
                code: "non-material-node", details: []
            )
            return .init(
                key: key,
                effectKey: scopedEffect,
                kind: node.kind.rawValue,
                definitionPassIndex: node.definitionPassIndex,
                materialPassID: node.materialPassID,
                descriptorMaterialPassIndex: nil,
                materialRawSHA256: nil,
                shaderIdentity: nil,
                contractCanonicalSHA256: nil,
                resolution: unavailable,
                resolvedFixedSlotCount: nil,
                resolvedSlots: [],
                template: unavailable,
                fixedSlotCount: nil,
                slots: [],
                state: nil,
                multiContributorUniforms: [],
                preparation: .init(
                    outcome: unavailable,
                    activeSamplerSlots: [],
                    activeSamplers: [],
                    samplerAnnotationFields: [],
                    colorContractResolved: nil
                ),
                program: program
            )
        }

        // The join authority is materialPassID. definitionPassIndex describes
        // the effect graph and is never used to choose a material-file pass.
        let descriptorMatches = descriptor.materialPasses.filter {
            $0.id == node.materialPassID
        }
        let descriptorPassIndex = descriptorMatches.count == 1
            ? descriptorMatches[0].passIndex
            : nil
        let materialRawSHA256 = descriptorMatches.count == 1
            ? descriptorMatches[0].materialRawSHA256
            : nil
        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node,
            graph: graph,
            descriptor: descriptor
        )
        guard resolution.isResolved, let material = resolution.node else {
            let rejected = OutcomeRecord(
                status: "rejected",
                phase: "material",
                code: "material-resolution-failed",
                details: resolution.issues.prefix(8).map { String($0.prefix(160)) }
            )
            return .init(
                key: key,
                effectKey: scopedEffect,
                kind: node.kind.rawValue,
                definitionPassIndex: node.definitionPassIndex,
                materialPassID: node.materialPassID,
                descriptorMaterialPassIndex: descriptorPassIndex,
                materialRawSHA256: materialRawSHA256,
                shaderIdentity: nil,
                contractCanonicalSHA256: nil,
                resolution: rejected,
                resolvedFixedSlotCount: nil,
                resolvedSlots: [],
                template: rejected,
                fixedSlotCount: nil,
                slots: [],
                state: nil,
                multiContributorUniforms: [],
                preparation: .init(
                    outcome: rejected,
                    activeSamplerSlots: [],
                    activeSamplers: [],
                    samplerAnnotationFields: [],
                    colorContractResolved: nil
                ),
                program: program
            )
        }
        let acceptedResolution = OutcomeRecord(
            status: "accepted", phase: nil, code: nil, details: []
        )
        let multiContributorUniforms = multiContributorUniformRecords(material)
        let matches = contractsByIdentity[normalizedShaderIdentity(material.shaderPath)] ?? []
        guard matches.count == 1, let contract = matches.first else {
            let rejected = OutcomeRecord(
                status: "rejected",
                phase: "shaderContract",
                code: matches.isEmpty
                    ? "shader-contract-missing"
                    : "shader-contract-ambiguous",
                details: []
            )
            return .init(
                key: key,
                effectKey: scopedEffect,
                kind: node.kind.rawValue,
                definitionPassIndex: node.definitionPassIndex,
                materialPassID: node.materialPassID,
                descriptorMaterialPassIndex: descriptorPassIndex,
                materialRawSHA256: materialRawSHA256,
                shaderIdentity: material.shaderPath,
                contractCanonicalSHA256: nil,
                resolution: acceptedResolution,
                resolvedFixedSlotCount: material.textureSlots.count,
                resolvedSlots: resolvedSlotRecords(material),
                template: rejected,
                fixedSlotCount: nil,
                slots: [],
                state: nil,
                multiContributorUniforms: multiContributorUniforms,
                preparation: .init(
                    outcome: rejected,
                    activeSamplerSlots: [],
                    activeSamplers: [],
                    samplerAnnotationFields: [],
                    colorContractResolved: nil
                ),
                program: program
            )
        }

        let templateResult = SceneResolvedMaterialTemplateCompiler.compile(
            material: material,
            graph: graph,
            shaderContract: contract
        )
        let templateOutcome: OutcomeRecord
        var fixedSlotCount: Int?
        var slots: [SlotRecord] = []
        var state: StateRecord?
        switch templateResult {
        case .success(let template):
            templateOutcome = .init(
                status: "accepted", phase: nil, code: nil, details: []
            )
            fixedSlotCount = template.textureSlots.count
            slots = template.textureSlots.compactMap { slot in
                slot.map { slot in
                    SlotRecord(
                        index: slot.index,
                        candidates: slot.candidates.map { candidate in
                            candidateRecord(candidate)
                        }
                    )
                }
            }
            state = .init(
                blending: template.renderState.blending.rawValue,
                depthTest: template.renderState.depthTest.rawValue,
                depthWrite: template.renderState.depthWrite.rawValue,
                cullMode: template.renderState.cullMode.rawValue,
                alphaWriting: template.renderState.alphaWriting.rawValue
            )
        case .failure(let failure):
            templateOutcome = failureOutcome(failure)
            fixedSlotCount = nil
        }

        // R2 bootstrap is a static material-file fact only. Instance, graph,
        // provider, and user-property candidates are not immutable readiness.
        let materialFileSlots = descriptorMatches[0].textureSlots
        let readiness = Dictionary(uniqueKeysWithValues: materialFileSlots.indices.compactMap {
            materialFileSlots[$0] == nil ? nil : ($0, true)
        })
        let preparationKey = preparationIdentity(
            contract: contract,
            combos: material.combos,
            readiness: readiness
        )
        let preparation: PreparationRecord
        if let cached = preparationCache[preparationKey] {
            preparation = cached
        } else {
            preparation = preparationRecord(
                contract: contract,
                combos: material.combos,
                readiness: readiness
            )
            preparationCache[preparationKey] = preparation
        }
        return .init(
            key: key,
            effectKey: scopedEffect,
            kind: node.kind.rawValue,
            definitionPassIndex: node.definitionPassIndex,
            materialPassID: node.materialPassID,
            descriptorMaterialPassIndex: descriptorPassIndex,
            materialRawSHA256: materialRawSHA256,
            shaderIdentity: material.shaderPath,
            contractCanonicalSHA256: contract.canonicalSHA256,
            resolution: acceptedResolution,
            resolvedFixedSlotCount: material.textureSlots.count,
            resolvedSlots: resolvedSlotRecords(material),
            template: templateOutcome,
            fixedSlotCount: fixedSlotCount,
            slots: slots,
            state: state,
            multiContributorUniforms: multiContributorUniforms,
            preparation: preparation,
            program: program
        )
    }

    private static func resolvedSlotRecords(
        _ material: SceneResolvedMaterialNode
    ) -> [SlotRecord] {
        material.textureSlots.compactMap { slot in
            slot.map { slot in
                SlotRecord(
                    index: slot.index,
                    candidates: slot.candidates.map { candidate in
                        resolvedCandidateRecord(candidate)
                    }
                )
            }
        }
    }

    private static func resolvedCandidateRecord(
        _ candidate: SceneResolvedMaterialNode.TextureCandidate
    ) -> SlotRecord.Candidate {
        let referenceKind: String
        let chainLabel: String
        switch candidate.source {
        case .asset:
            referenceKind = "asset"
            chainLabel = candidate.provenance == .material
                ? "material"
                : candidate.provenance == .instance ? "instance" : "asset"
        case .userTexture(let input):
            switch input.kind {
            case .path:
                referenceKind = "asset"
                chainLabel = "userPath"
            case .property:
                referenceKind = "userProperty"
                chainLabel = "user"
            case .system:
                referenceKind = "systemProvider"
                chainLabel = "system"
            case .unknown:
                referenceKind = "unknown"
                chainLabel = "unknown"
            }
        case .graph:
            referenceKind = "graph"
            chainLabel = "graph"
        }
        return .init(
            provenance: candidate.provenance.rawValue,
            referenceKind: referenceKind,
            chainLabel: chainLabel
        )
    }

    private static func candidateRecord(
        _ candidate: SceneResolvedMaterialTemplate.TextureCandidate
    ) -> SlotRecord.Candidate {
        let referenceKind: String
        let chainLabel: String
        switch candidate.reference {
        case .asset:
            referenceKind = "asset"
            chainLabel = candidate.provenance == .material
                ? "material"
                : candidate.provenance == .instance ? "instance" : "asset"
        case .userProperty:
            referenceKind = "userProperty"
            chainLabel = "user"
        case .provider:
            referenceKind = "systemProvider"
            chainLabel = "system"
        case .graph:
            referenceKind = "graph"
            chainLabel = "graph"
        }
        return .init(
            provenance: candidate.provenance.rawValue,
            referenceKind: referenceKind,
            chainLabel: chainLabel
        )
    }

    private static func multiContributorUniformRecords(
        _ material: SceneResolvedMaterialNode
    ) -> [MultiContributorUniformRecord] {
        let names = Set(material.constants.keys)
            .union(material.userShaderValues.keys).sorted()
        return names.compactMap { name in
            let value = material.constants[name]
            var contributorKinds: [String] = []
            if value?.userBinding != nil {
                contributorKinds.append("authored-user-property")
            }
            if value?.timeline != nil { contributorKinds.append("timeline") }
            if value?.scriptSource?.isEmpty == false {
                contributorKinds.append("scene-script")
            }
            if material.userShaderValues[name] != nil {
                contributorKinds.append("material-user-property")
            }
            guard contributorKinds.count > 1 else { return nil }
            let shape = timelineShape(value?.timeline)
            let script = value?.scriptSource
            return .init(
                name: name,
                contributorKinds: contributorKinds,
                bindingKeys: value?.bindingKeys.sorted() ?? [],
                componentCount: value?.components?.count,
                hasTimeline: value?.timeline != nil,
                timelineMode: shape.mode,
                timelineStartsPaused: shape.startsPaused,
                timelineIsRelative: shape.isRelative,
                timelineLaneKeyframeCounts: shape.laneKeyframeCounts,
                hasScriptSource: script?.isEmpty == false,
                scriptShape: validMediaEventScript(script)
                    ? "media-thumbnail-event-control"
                    : script == nil ? "absent" : "other"
            )
        }
    }

    private static func timelineShape(
        _ value: SceneJSONValue?
    ) -> (
        mode: String?, startsPaused: Bool?, isRelative: Bool?,
        laneKeyframeCounts: [Int]
    ) {
        guard case let .object(root) = value else {
            return (nil, nil, nil, [])
        }
        let isRelative = root["isRelative"]?.boolValue
        var laneCounts: [Int] = []
        if let rawLanes = root["lanes"], case let .array(lanes) = rawLanes {
            laneCounts = lanes.map { lane in
                guard case let .array(keyframes) = lane else { return -1 }
                return keyframes.count
            }
        }
        guard let rawOptions = root["options"],
              case let .object(options) = rawOptions else {
            return (nil, nil, isRelative, laneCounts)
        }
        return (
            options["mode"]?.stringValue,
            options["startsPaused"]?.boolValue,
            isRelative,
            laneCounts
        )
    }

    private static func validMediaEventScript(_ source: String?) -> Bool {
        guard let source else { return false }
        let compact = source
            .replacingOccurrences(
                of: #"/\*[\s\S]*?\*/"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"//[^\n\r]*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: "",
                options: .regularExpression
            )
        let pattern = #"exportfunctionmediaThumbnailChanged\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{if\(\1\.hasThumbnail\)\{(?:var|let|const)([A-Za-z_$][A-Za-z0-9_$]*)=thisObject\.getAnimation\(\);\2\.stop\(\);\2\.play\(\);?\}\}"#
        return compact.range(of: pattern, options: .regularExpression) != nil
    }

    private static func preparationRecord(
        contract: SceneShaderContract,
        combos: [String: Int],
        readiness: [Int: Bool]
    ) -> PreparationRecord {
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: contract,
            combos: combos,
            textureReadiness: readiness
        ) {
        case .notApplicable:
            return .init(
                outcome: .init(
                    status: "notApplicable", phase: nil, code: nil, details: []
                ),
                activeSamplerSlots: [],
                activeSamplers: [],
                samplerAnnotationFields: [],
                colorContractResolved: nil
            )
        case .rejected(let failure):
            return .init(
                outcome: .init(
                    status: "rejected",
                    phase: failure.phase.rawValue,
                    code: failure.code.rawValue,
                    details: failure.details.prefix(8).map { String($0.prefix(160)) }
                ),
                activeSamplerSlots: [],
                activeSamplers: [],
                samplerAnnotationFields: [],
                colorContractResolved: nil
            )
        case .accepted(let prepared):
            let metadata = samplerMetadata(prepared)
            return .init(
                outcome: .init(
                    status: "accepted", phase: nil, code: nil, details: []
                ),
                activeSamplerSlots: metadata.slots,
                activeSamplers: metadata.samplers,
                samplerAnnotationFields: metadata.fields,
                colorContractResolved: prepared.colorContract.isResolved
            )
        }
    }

    private static func samplerMetadata(
        _ prepared: SceneShaderPreparedProgram
    ) -> (
        slots: [Int], samplers: [ActiveSamplerRecord], fields: [String]
    ) {
        var declarations: [Int: [SceneShaderActiveDeclaration]] = [:]
        for active in prepared.all.flatMap(\.activeDeclarations) {
            guard active.declaration.kind == .uniform,
                  active.declaration.type.caseInsensitiveCompare("sampler2D") == .orderedSame,
                  active.declaration.name.hasPrefix("g_Texture"),
                  let slot = Int(active.declaration.name.dropFirst("g_Texture".count)),
                  (0 ... 7).contains(slot) else { continue }
            declarations[slot, default: []].append(active)
        }
        var fields: [String] = []
        var samplers: [ActiveSamplerRecord] = []
        for slot in declarations.keys.sorted() {
            var purposeValues: [String] = []
            var slotFields: [String] = []
            var modeValues: [String] = []
            var materialValues: [String] = []
            var defaultValueKinds: [String] = []
            var formatValues: [String] = []
            for declaration in declarations[slot] ?? [] {
                for annotation in prepared.all.flatMap(\.activeAnnotations)
                where annotation.sourcePath == declaration.sourcePath
                    && annotation.annotation.line == declaration.declaration.line {
                    guard case let .object(object) = annotation.annotation.variantValue else {
                        continue
                    }
                    let objectFields = object.keys.sorted()
                    fields.append(contentsOf: objectFields)
                    slotFields.append(contentsOf: objectFields)
                    if let value = safeAnnotationToken(object["mode"]) {
                        modeValues.append(value)
                    }
                    if let value = safeAnnotationToken(object["material"]) {
                        materialValues.append(value)
                    }
                    if let value = object["default"] {
                        defaultValueKinds.append(jsonValueKind(value))
                    }
                    if let value = safeAnnotationToken(object["format"]) {
                        formatValues.append(value)
                    }
                    if let value = object["purpose"]?.stringValue {
                        purposeValues.append(safeToken(value))
                    }
                }
            }
            samplers.append(.init(
                slot: slot,
                annotationFields: Array(Set(slotFields)).sorted(),
                modeValues: Array(Set(modeValues)).sorted(),
                materialValues: Array(Set(materialValues)).sorted(),
                defaultValueKinds: Array(Set(defaultValueKinds)).sorted(),
                formatValues: Array(Set(formatValues)).sorted(),
                purposeValues: Array(Set(purposeValues)).sorted()
            ))
        }
        return (declarations.keys.sorted(), samplers, fields.sorted())
    }

    private static func safeAnnotationToken(
        _ value: SceneShaderAnnotationValue?
    ) -> String? {
        guard let value = value?.stringValue else { return nil }
        return safeToken(value)
    }

    private static func safeToken(_ value: String) -> String {
        guard !value.isEmpty else { return "<empty>" }
        let allowed = value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "_.-")
            ).contains($0)
        }
        return allowed && value.count <= 64 ? value : "<non-token-string>"
    }

    private static func jsonValueKind(
        _ value: SceneShaderAnnotationValue
    ) -> String {
        switch value {
        case .null: "null"
        case .bool: "bool"
        case .integer: "integer"
        case .number: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    private static func failureOutcome(
        _ failure: SceneResolvedMaterialFailure
    ) -> OutcomeRecord {
        .init(
            status: "rejected",
            phase: failure.phase.rawValue,
            code: failure.code.rawValue,
            details: failure.boundedDetails
        )
    }

    private static func effectKey(
        _ key: Graph.EffectKey,
        sampleID: String
    ) -> EffectKey {
        .init(
            sampleID: sampleID,
            layerID: key.layerID,
            effectIndex: key.effectIndex,
            descriptorID: key.descriptorID
        )
    }

    private static func validateMaterialResources(
        _ passes: [SceneRenderDescriptor.MaterialPassDescriptor],
        resourceView: SceneResourceView,
        sampleID: String
    ) throws {
        var checked: [String: String] = [:]
        for pass in passes {
            if let prior = checked[pass.materialPath] {
                guard prior == pass.materialRawSHA256 else {
                    throw HarnessError.invalidInput(
                        "sample \(sampleID) material revision is ambiguous"
                    )
                }
                continue
            }
            guard let resource = resourceView.resource(relativePath: pass.materialPath),
                  let data = try? Data(contentsOf: resource.url),
                  sha256(data).caseInsensitiveCompare(pass.materialRawSHA256)
                    == .orderedSame else {
                throw HarnessError.invalidInput(
                    "sample \(sampleID) material resource identity differs"
                )
            }
            checked[pass.materialPath] = pass.materialRawSHA256
        }
    }

    private static func validateContractProjection(
        current: [SceneShaderContract],
        runtime: [SceneShaderContract],
        sampleID: String
    ) throws -> Bool {
        guard !runtime.isEmpty else { return false }
        let currentProjection = current.map(contractProjection).sorted()
        let runtimeProjection = runtime.map(contractProjection).sorted()
        guard currentProjection == runtimeProjection else {
            throw HarnessError.invalidInput(
                "sample \(sampleID) current shader projection differs from runtime evidence"
            )
        }
        return true
    }

    private static func contractProjection(_ contract: SceneShaderContract) -> String {
        let stages = contract.stages.map {
            "\($0.kind.rawValue):\($0.relativePath):\($0.rawSHA256)"
        }.sorted().joined(separator: "|")
        let diagnostics = contract.diagnostics.map { $0.code.rawValue }
            .sorted().joined(separator: ",")
        return "\(contract.identity)#\(contract.sourceKind.rawValue)"
            + "#\(contract.canonicalSHA256)#\(stages)#\(diagnostics)"
    }

    private static func preparationIdentity(
        contract: SceneShaderContract,
        combos: [String: Int],
        readiness: [Int: Bool]
    ) -> String {
        let combo = combos.keys.sorted().map { "\($0)=\(combos[$0]!)" }
            .joined(separator: ",")
        let ready = (0 ..< 8).map { readiness[$0] == true ? "1" : "0" }.joined()
        return "\(contract.identity.utf8.count)#\(contract.identity)"
            + "#\(contract.canonicalSHA256)"
            + "#\(contract.sourceGraph?.dependencySHA256 ?? "<none>")"
            + "#\(combo)#\(ready)"
    }

    private static func normalizedShaderIdentity(_ value: String) -> String {
        var identity = value.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [".vert", ".frag", ".json"]
        where identity.lowercased().hasSuffix(suffix) {
            identity.removeLast(suffix.count)
            break
        }
        return identity.lowercased()
    }

    private static func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
'''


class CensusError(RuntimeError):
    """A fail-closed corpus, build, or publication contract violation."""


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: Any, *, pretty: bool = False) -> bytes:
    if pretty:
        text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)
    else:
        text = json.dumps(
            value,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
        )
    return (text + "\n").encode("utf-8")


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def portable_path(path: Path, fixture_directory: Path | None = None) -> str:
    resolved = path.expanduser().resolve()
    if is_relative_to(resolved, REPOSITORY_ROOT):
        return resolved.relative_to(REPOSITORY_ROOT).as_posix()
    if fixture_directory is not None:
        fixture_root = fixture_directory.expanduser().resolve()
        if is_relative_to(resolved, fixture_root):
            return f"<fixture-root>/{resolved.relative_to(fixture_root).as_posix()}"
    return f"<external>/{resolved.name}"


def require_safe_input_root(path: Path, label: str) -> Path:
    resolved = path.expanduser().resolve(strict=True)
    if (
        resolved == REAL_WORKSHOP_ROOT
        or is_relative_to(resolved, REAL_WORKSHOP_ROOT)
        or is_relative_to(REAL_WORKSHOP_ROOT, resolved)
    ):
        raise CensusError(f"{label} must not resolve to the real Workshop tree")
    if not resolved.is_dir():
        raise CensusError(f"{label} is not a directory: {resolved}")
    return resolved


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CensusError(f"cannot load {label} {path}: {error}") from error
    if not isinstance(value, dict):
        raise CensusError(f"{label} must be a JSON object: {path}")
    return value


def resolve_configured_path(raw: Any, label: str) -> Path:
    if not isinstance(raw, str) or not raw.strip():
        raise CensusError(f"{label} must be a non-empty path")
    path = Path(raw).expanduser()
    return path.resolve() if path.is_absolute() else (REPOSITORY_ROOT / path).resolve()


def package_path(sample_root: Path, project: dict[str, Any]) -> Path:
    entry = project.get("file")
    entry_name = (
        Path(entry.strip().replace("\\", "/")).name
        if isinstance(entry, str) and entry.strip()
        else "scene.json"
    )
    derived = str(Path(entry_name).with_suffix(".pkg"))
    names = [derived] if derived == "scene.pkg" else [derived, "scene.pkg"]
    for name in names:
        candidate = sample_root / name
        if candidate.is_file():
            return candidate.resolve()
    raise CensusError(f"sample {sample_root.name} has no package for {entry_name}")


def unique_cache_root(runtime_homes: Path, sample_id: str) -> Path:
    parent = runtime_homes / sample_id / "Library/Caches/MyWallpaperX/SteamWorkshopScene"
    roots = sorted(path.resolve() for path in parent.iterdir() if path.is_dir()) \
        if parent.is_dir() else []
    if len(roots) != 1:
        raise CensusError(
            f"sample {sample_id} expected one extraction root, found {len(roots)}"
        )
    return roots[0]


def runtime_input_sha256(evidence: dict[str, Any]) -> str:
    runtime_input = evidence.get("runtimeInput")
    if not isinstance(runtime_input, dict):
        raise CensusError("runtime evidence has no runtimeInput object")
    return sha256_bytes(canonical_json_bytes(runtime_input)[:-1])


def runtime_snapshot_state(runtime_input: dict[str, Any]) -> str:
    required = {
        "textureSnapshot",
        "graphTextureIdentities",
        "dynamicSnapshot",
        "uniformInputs",
    }
    present = required.intersection(runtime_input)
    if not present:
        return "unavailable"
    if present != required:
        raise CensusError(
            "runtime evidence contains a partial immutable Program snapshot: "
            + ", ".join(sorted(present))
        )
    raise CensusError(
        "runtime evidence contains Program snapshots that this R3 census must not ignore"
    )


def validate_inputs(
    fixture_path: Path,
    matrix_path: Path,
    runtime_report_path: Path,
    stock_root: Path,
    output_path: Path,
) -> dict[str, Any]:
    fixture_path = fixture_path.expanduser().resolve(strict=True)
    matrix_path = matrix_path.expanduser().resolve(strict=True)
    runtime_report_path = runtime_report_path.expanduser().resolve(strict=True)
    try:
        fixture = load_fixture_config(fixture_path, REPOSITORY_ROOT)
    except ValueError as error:
        raise CensusError(str(error)) from error
    matrix = load_json_object(matrix_path, "matrix")
    runtime_report = load_json_object(runtime_report_path, "runtime report")
    if matrix.get("schema_version") != 1 or not isinstance(matrix.get("samples"), list):
        raise CensusError("matrix schema_version must be 1 with a samples array")
    if runtime_report.get("schema_version") != 2 \
            or not isinstance(runtime_report.get("samples"), list):
        raise CensusError("runtime report schema_version must be 2 with a samples array")
    if runtime_report.get("matrix") != matrix.get("name"):
        raise CensusError("runtime report matrix identity does not match matrix name")

    sample_root = require_safe_input_root(
        resolve_configured_path(fixture.get("sample_root"), "fixture sample_root"),
        "sample_root",
    )
    runtime_homes = require_safe_input_root(
        resolve_configured_path(fixture.get("runtime_homes"), "fixture runtime_homes"),
        "runtime_homes",
    )
    stock_root = require_safe_input_root(stock_root, "stock_root")
    if sample_root == runtime_homes:
        raise CensusError("sample_root and runtime_homes must be distinct")
    if not (stock_root / "shaders").is_dir():
        raise CensusError("stock_root must contain shaders/")

    output = output_path.expanduser().resolve()
    for root, label in (
        (sample_root, "sample_root"),
        (runtime_homes, "runtime_homes"),
        (stock_root, "stock_root"),
    ):
        if is_relative_to(output, root):
            raise CensusError(f"output must not be inside {label}")
    if output == REAL_WORKSHOP_ROOT or is_relative_to(output, REAL_WORKSHOP_ROOT):
        raise CensusError("output must not be inside the real Workshop tree")

    matrix_samples: dict[str, dict[str, Any]] = {}
    for entry in matrix["samples"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            raise CensusError("matrix samples must have string ids")
        sample_id = entry["id"]
        if not sample_id.isdigit() or sample_id in matrix_samples:
            raise CensusError(f"matrix sample id is invalid or duplicated: {sample_id}")
        matrix_samples[sample_id] = entry
    report_samples: dict[str, dict[str, Any]] = {}
    for entry in runtime_report["samples"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            raise CensusError("runtime report samples must have string ids")
        sample_id = entry["id"]
        if sample_id in report_samples:
            raise CensusError(f"runtime report sample is duplicated: {sample_id}")
        report_samples[sample_id] = entry
    expected_ids = sorted(matrix_samples)
    sample_ids = sorted(
        path.name for path in sample_root.iterdir()
        if path.is_dir() and path.name.isdigit()
    )
    runtime_ids = sorted(
        path.name for path in runtime_homes.iterdir()
        if path.is_dir() and path.name.isdigit()
    )
    if sample_ids != expected_ids:
        raise CensusError("sample_root numeric directory set does not match matrix")
    if runtime_ids != expected_ids:
        raise CensusError("runtime_homes numeric directory set does not match matrix")
    if sorted(report_samples) != expected_ids:
        raise CensusError("runtime report sample set does not match matrix")

    report_root = runtime_report_path.parent.resolve()
    seen_evidence: set[Path] = set()
    samples: list[dict[str, Any]] = []
    for sample_id in expected_ids:
        sample_directory = (sample_root / sample_id).resolve()
        project_path = sample_directory / "project.json"
        project = load_json_object(project_path, f"sample {sample_id} project")
        package = package_path(sample_directory, project)
        expected = matrix_samples[sample_id]
        report_sample = report_samples[sample_id]
        report_hashes = report_sample.get("hashes")
        if not isinstance(report_hashes, dict):
            raise CensusError(f"runtime report sample {sample_id} has no hashes")
        project_sha = sha256_file(project_path)
        package_sha = sha256_file(package)
        for label, actual, matrix_value, report_value in (
            (
                "project",
                project_sha,
                expected.get("project_sha256"),
                report_hashes.get("project_sha256"),
            ),
            (
                "package",
                package_sha,
                expected.get("package_sha256"),
                report_hashes.get("package_sha256"),
            ),
        ):
            if actual != matrix_value or actual != report_value:
                raise CensusError(
                    f"sample {sample_id} {label} identity differs across sample/matrix/report"
                )
        evidence_section = report_sample.get("evidence")
        raw_evidence = (
            evidence_section.get("runtime_evidence")
            if isinstance(evidence_section, dict) else None
        )
        if not isinstance(raw_evidence, str) or not raw_evidence:
            raise CensusError(f"runtime report sample {sample_id} has no runtime evidence")
        evidence_path = Path(raw_evidence).expanduser()
        if not evidence_path.is_absolute():
            evidence_path = report_root / evidence_path
        evidence_path = evidence_path.resolve(strict=True)
        if not is_relative_to(evidence_path, report_root):
            raise CensusError(
                f"runtime evidence for sample {sample_id} escapes the report root"
            )
        if evidence_path.parent.name != sample_id or evidence_path.name \
                != "scene-runtime-evidence.json":
            raise CensusError(
                f"runtime evidence path is not scoped to sample {sample_id}"
            )
        if evidence_path in seen_evidence:
            raise CensusError("runtime report reuses one evidence file for multiple samples")
        seen_evidence.add(evidence_path)
        evidence = load_json_object(evidence_path, f"sample {sample_id} runtime evidence")
        if evidence.get("schemaVersion") != 1:
            raise CensusError(f"sample {sample_id} runtime evidence schema is invalid")
        runtime_input = evidence.get("runtimeInput")
        if not isinstance(runtime_input, dict):
            raise CensusError(f"sample {sample_id} runtimeInput is missing")
        descriptor = runtime_input.get("renderDescriptor")
        if not isinstance(descriptor, dict) \
                or descriptor.get("entryPath") != evidence.get("sourceEntryPath"):
            raise CensusError(f"sample {sample_id} runtime input entry identity is invalid")
        samples.append({
            "sampleID": sample_id,
            "projectRoot": str(sample_directory),
            "projectPath": str(project_path.resolve()),
            "packagePath": str(package),
            "packageRoot": str(unique_cache_root(runtime_homes, sample_id)),
            "runtimeEvidencePath": str(evidence_path),
            "projectSHA256": project_sha,
            "packageSHA256": package_sha,
            "runtimeEvidenceSHA256": sha256_file(evidence_path),
            "runtimeInputSHA256": runtime_input_sha256(evidence),
            "runtimeSnapshotState": runtime_snapshot_state(runtime_input),
        })

    return {
        "fixture_path": fixture_path,
        "fixture_sha256": sha256_file(fixture_path),
        "fixture": fixture,
        "matrix_path": matrix_path,
        "matrix_sha256": sha256_file(matrix_path),
        "matrix": matrix,
        "runtime_report_path": runtime_report_path,
        "runtime_report_sha256": sha256_file(runtime_report_path),
        "runtime_report": runtime_report,
        "sample_root": sample_root,
        "runtime_homes": runtime_homes,
        "stock_root": stock_root,
        "samples": samples,
    }


def source_manifest(paths: Sequence[str]) -> dict[str, Any]:
    records = []
    for relative in paths:
        path = REPOSITORY_ROOT / relative
        if not path.is_file():
            raise CensusError(f"source file is missing: {relative}")
        records.append({
            "path": relative,
            "sha256": sha256_file(path),
            "bytes": path.stat().st_size,
        })
    return {
        "algorithm": "sha256(canonical-json(source-path,sha256,bytes)-v1)",
        "files": records,
        "aggregate_sha256": sha256_bytes(canonical_json_bytes(records)),
    }


def validate_stable_inputs(
    inputs: dict[str, Any],
    expected_sources: dict[str, Any],
) -> None:
    for label in ("fixture", "matrix", "runtime_report"):
        if sha256_file(inputs[f"{label}_path"]) != inputs[f"{label}_sha256"]:
            raise CensusError(f"{label} changed while the R3 census was running")
    for sample in inputs["samples"]:
        for label, path_key, digest_key in (
            ("project", "projectPath", "projectSHA256"),
            ("package", "packagePath", "packageSHA256"),
            ("runtime evidence", "runtimeEvidencePath", "runtimeEvidenceSHA256"),
        ):
            if sha256_file(Path(sample[path_key])) != sample[digest_key]:
                raise CensusError(
                    f"sample {sample['sampleID']} {label} changed during the R3 census"
                )
    if source_manifest(CURRENT_SOURCE_PATHS) != expected_sources:
        raise CensusError("current production sources changed during the R3 census")


def tool_output(arguments: Sequence[str]) -> str:
    completed = subprocess.run(
        list(arguments),
        cwd=REPOSITORY_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise CensusError(f"tool command failed: {' '.join(arguments)}")
    return completed.stdout.strip()


def compile_harness(
    harness_path: Path,
    binary_path: Path,
    module_cache: Path,
) -> None:
    module_cache.mkdir(parents=True)
    command = [
        "xcrun",
        "--sdk",
        "macosx",
        "swiftc",
        "-parse-as-library",
        "-module-cache-path",
        str(module_cache),
        *(str(REPOSITORY_ROOT / path) for path in CURRENT_SOURCE_PATHS),
        str(harness_path),
        "-o",
        str(binary_path),
    ]
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(module_cache / "clang")
    environment["SWIFT_MODULECACHE_PATH"] = str(module_cache / "swift")
    completed = subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise CensusError("R3 Swift census compile failed:\n" + completed.stderr.strip())


def run_harness(binary: Path, manifest: Path, stock_root: Path) -> bytes:
    completed = subprocess.run(
        [str(binary), str(manifest), str(stock_root)],
        cwd=REPOSITORY_ROOT,
        check=False,
        capture_output=True,
    )
    if completed.returncode != 0:
        raise CensusError(
            "R3 Swift census run failed:\n"
            + completed.stderr.decode("utf-8", "replace").strip()
        )
    return completed.stdout


def walk_json(value: Any) -> Iterable[tuple[str | None, Any]]:
    stack: list[tuple[str | None, Any]] = [(None, value)]
    while stack:
        key, current = stack.pop()
        yield key, current
        if isinstance(current, dict):
            stack.extend((str(child_key), child) for child_key, child in current.items())
        elif isinstance(current, list):
            stack.extend((None, child) for child in current)


def validate_corpus_output(
    payload: bytes,
    sample_ids: Sequence[str],
    forbidden_temporary_root: Path,
) -> dict[str, Any]:
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as error:
        raise CensusError(f"R3 harness output is not JSON: {error}") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 2 \
            or value.get("implementation") != "r3-worktree":
        raise CensusError("R3 harness output identity is invalid")
    samples = value.get("samples")
    if not isinstance(samples, list) or [
        sample.get("key", {}).get("sampleID") for sample in samples
    ] != list(sample_ids):
        raise CensusError("R3 harness sample set/order does not match matrix")
    forbidden_keys = {
        "source",
        "shaderSource",
        "preparedSource",
        "metalSource",
        "materialJSON",
        "materialPayload",
        "objectIdentifier",
        "textureObjectIdentifier",
    }
    forbidden_roots = {
        str(REPOSITORY_ROOT.resolve()),
        str(forbidden_temporary_root.resolve()),
        str(Path.home().resolve()),
    }
    for key, item in walk_json(value):
        if key in forbidden_keys:
            raise CensusError(f"R3 harness output contains forbidden payload key: {key}")
        if isinstance(item, str):
            if item.startswith("file://") or any(root in item for root in forbidden_roots):
                raise CensusError("R3 harness output leaked an absolute input path")

    graph_keys: list[tuple[str, int]] = []
    effect_keys: list[tuple[str, int, int, str]] = []
    node_keys: list[tuple[str, int, int]] = []
    for sample in samples:
        for graph in sample.get("graphs", []):
            key = graph.get("key", {})
            graph_keys.append((str(key.get("sampleID")), int(key.get("layerID"))))
        for effect in sample.get("effects", []):
            key = effect.get("key", {})
            effect_keys.append((
                str(key.get("sampleID")),
                int(key.get("layerID")),
                int(key.get("effectIndex")),
                str(key.get("descriptorID")),
            ))
        for node in sample.get("nodes", []):
            key = node.get("key", {})
            node_keys.append((
                str(key.get("sampleID")),
                int(key.get("layerID")),
                int(key.get("nodeIndex")),
            ))
            fixed_count = node.get("fixedSlotCount")
            if node.get("template", {}).get("status") == "accepted" \
                    and fixed_count != 8:
                raise CensusError("accepted Template did not preserve exactly eight slots")
            if node.get("resolution", {}).get("status") == "accepted" \
                    and node.get("resolvedFixedSlotCount") != 8:
                raise CensusError("resolved material did not preserve exactly eight slots")
            resolved_indices = [
                int(slot.get("index", -1)) for slot in node.get("resolvedSlots", [])
            ]
            if len(resolved_indices) != len(set(resolved_indices)) or any(
                not 0 <= index < 8 for index in resolved_indices
            ):
                raise CensusError("resolved material slots are not sparse g_Texture0...7")
            for slot in node.get("slots", []):
                if not 0 <= int(slot.get("index", -1)) < 8:
                    raise CensusError("Template contains a slot outside g_Texture0...7")
    for label, keys in (
        ("graph", graph_keys),
        ("effect", effect_keys),
        ("node", node_keys),
    ):
        if len(keys) != len(set(keys)):
            raise CensusError(f"R3 harness contains duplicate {label} keys")
    return value


def outcome_counts(nodes: Sequence[dict[str, Any]], field: str) -> dict[str, int]:
    return dict(sorted(Counter(
        str(outcome_for(node, field).get("status")) for node in nodes
    ).items()))


def outcome_for(node: dict[str, Any], field: str) -> dict[str, Any]:
    value = node.get(field, {})
    if field == "preparation" and isinstance(value, dict):
        value = value.get("outcome", {})
    return value if isinstance(value, dict) else {}


def failure_distribution(
    nodes: Sequence[dict[str, Any]],
    field: str,
) -> list[dict[str, Any]]:
    counts: Counter[tuple[str, str]] = Counter()
    for node in nodes:
        outcome = outcome_for(node, field)
        if outcome.get("status") != "rejected":
            continue
        counts[(
            str(outcome.get("phase") or "<none>"),
            str(outcome.get("code") or "<none>"),
        )] += 1
    return [
        {"phase": phase, "code": code, "count": count}
        for (phase, code), count in sorted(counts.items())
    ]


def counter_rows(
    counts: Counter[tuple[str, ...]],
    names: Sequence[str],
) -> list[dict[str, Any]]:
    return [
        {**dict(zip(names, values)), "count": count}
        for values, count in sorted(counts.items())
    ]


def sampler_semantic_evidence(
    sampler: dict[str, Any],
    candidate_kind: str,
) -> str:
    """Classify only public sampler modes or an exact graph color boundary."""
    modes = {str(value).lower() for value in sampler.get("modeValues", [])}
    formats = {str(value).lower() for value in sampler.get("formatValues", [])}
    supported_modes = {"opacitymask", "rgbmask", "flowmask"}
    if modes - supported_modes or formats or len(modes) > 1:
        return "unproven"
    mode = next(iter(modes), None)
    if mode is not None:
        return f"mode:{mode}"
    if candidate_kind == "graph":
        return "graph-color-boundary"
    return "unproven"


def build_summary(corpus: dict[str, Any]) -> dict[str, Any]:
    samples = corpus["samples"]
    graphs = [graph for sample in samples for graph in sample["graphs"]]
    effects = [effect for sample in samples for effect in sample["effects"]]
    nodes = [node for sample in samples for node in sample["nodes"]]
    contracts = [contract for sample in samples for contract in sample["contracts"]]
    resolved_slots = [
        slot for node in nodes
        if node["resolution"]["status"] == "accepted"
        for slot in node["resolvedSlots"]
    ]
    resolved_candidates = [
        candidate for slot in resolved_slots for candidate in slot["candidates"]
    ]
    resolved_multi_slots = [
        slot for slot in resolved_slots if len(slot["candidates"]) > 1
    ]
    resolved_multi_nodes = {
        (node["key"]["sampleID"], node["key"]["layerID"], node["key"]["nodeIndex"])
        for node in nodes
        if any(len(slot["candidates"]) > 1 for slot in node["resolvedSlots"])
    }
    resolved_chains = Counter(
        "->".join(candidate["chainLabel"] for candidate in slot["candidates"])
        for slot in resolved_slots
    )
    resolved_final_sources = Counter(
        slot["candidates"][-1]["chainLabel"] for slot in resolved_slots
    )
    resolved_candidate_sources = Counter(
        f"{candidate['referenceKind']}/{candidate['provenance']}"
        for candidate in resolved_candidates
    )
    template_slots = [
        slot for node in nodes
        if node["template"]["status"] == "accepted"
        for slot in node["slots"]
    ]
    template_candidates = [
        candidate for slot in template_slots for candidate in slot["candidates"]
    ]
    template_multi_slots = [
        slot for slot in template_slots if len(slot["candidates"]) > 1
    ]
    template_multi_nodes = {
        (node["key"]["sampleID"], node["key"]["layerID"], node["key"]["nodeIndex"])
        for node in nodes
        if any(len(slot["candidates"]) > 1 for slot in node["slots"])
    }
    template_chains = Counter(
        "->".join(candidate["chainLabel"] for candidate in slot["candidates"])
        for slot in template_slots
    )
    template_final_sources = Counter(
        slot["candidates"][-1]["chainLabel"] for slot in template_slots
    )
    template_candidate_sources = Counter(
        f"{candidate['referenceKind']}/{candidate['provenance']}"
        for candidate in template_candidates
    )
    states = Counter(
        "/".join([
            node["state"]["blending"],
            node["state"]["depthTest"],
            node["state"]["depthWrite"],
            node["state"]["cullMode"],
            node["state"]["alphaWriting"],
        ])
        for node in nodes if node.get("state") is not None
    )
    multi_contributor_uniforms = [
        (node, uniform)
        for node in nodes
        for uniform in node.get("multiContributorUniforms", [])
    ]
    contributor_names = Counter(
        uniform["name"] for _, uniform in multi_contributor_uniforms
    )
    contributor_sequences = Counter(
        "+".join(uniform["contributorKinds"])
        for _, uniform in multi_contributor_uniforms
    )
    contributor_binding_keys = Counter(
        "+".join(uniform["bindingKeys"]) or "<none>"
        for _, uniform in multi_contributor_uniforms
    )
    contributor_timeline_shapes = Counter(
        "/".join([
            str(uniform.get("timelineMode") or "<none>"),
            "paused" if uniform.get("timelineStartsPaused") is True else "running",
            "relative" if uniform.get("timelineIsRelative") is True else "absolute",
            "lanes=" + ",".join(map(str, uniform["timelineLaneKeyframeCounts"])),
        ])
        for _, uniform in multi_contributor_uniforms
    )
    contributor_scripts = Counter(
        uniform["scriptShape"] for _, uniform in multi_contributor_uniforms
    )
    contributor_revision_counts = Counter(
        (
            str(node.get("materialRawSHA256")),
            str(node.get("shaderIdentity")),
            str(node.get("contractCanonicalSHA256")),
        )
        for node, _ in multi_contributor_uniforms
    )
    sampler_slots: Counter[str] = Counter()
    annotation_fields: Counter[str] = Counter()
    color_resolved = 0
    color_unresolved = 0
    sampler_profiles: Counter[tuple[str, ...]] = Counter()
    sampler_field_sets: Counter[tuple[str, ...]] = Counter()
    mode_candidate_kinds: Counter[tuple[str, ...]] = Counter()
    mode_values: Counter[str] = Counter()
    format_values: Counter[str] = Counter()
    semantic_evidence: Counter[str] = Counter()
    semantic_candidate_kinds: Counter[tuple[str, ...]] = Counter()
    purpose_candidate_kinds: Counter[tuple[str, ...]] = Counter()
    sampler_candidate_kinds: Counter[str] = Counter()
    for node in nodes:
        preparation = node["preparation"]
        for slot in preparation["activeSamplerSlots"]:
            sampler_slots[str(slot)] += 1
        annotation_fields.update(preparation["samplerAnnotationFields"])
        if preparation.get("colorContractResolved") is True:
            color_resolved += 1
        elif preparation.get("colorContractResolved") is False:
            color_unresolved += 1
        if outcome_for(node, "preparation").get("status") != "accepted":
            continue
        resolved_by_slot = {
            int(slot["index"]): slot for slot in node.get("resolvedSlots", [])
        }
        for sampler in preparation.get("activeSamplers", []):
            resolved_slot = resolved_by_slot.get(int(sampler["slot"]))
            if resolved_slot is None or not resolved_slot.get("candidates"):
                candidate_kind = "absent"
            else:
                reference_kind = resolved_slot["candidates"][-1]["referenceKind"]
                candidate_kind = {
                    "asset": "asset",
                    "graph": "graph",
                    "systemProvider": "system",
                    "userProperty": "user",
                }.get(reference_kind, "unknown")
            sampler_candidate_kinds[candidate_kind] += 1
            selected_fields = tuple(
                field for field in ("mode", "material", "default", "format")
                if field in sampler["annotationFields"]
            )
            sampler_field_sets[selected_fields or ("<none>",)] += 1
            mode = "+".join(sampler["modeValues"]) or "<none>"
            material_value = "+".join(sampler["materialValues"]) or "<none>"
            default_kind = "+".join(sampler["defaultValueKinds"]) or "<none>"
            format_value = "+".join(sampler["formatValues"]) or "<none>"
            sampler_profiles[(
                candidate_kind, mode, material_value, default_kind, format_value,
            )] += 1
            mode_candidate_kinds[(mode, candidate_kind)] += 1
            mode_values.update(value.lower() for value in sampler["modeValues"])
            format_values.update(value.lower() for value in sampler["formatValues"])
            evidence = sampler_semantic_evidence(sampler, candidate_kind)
            semantic_evidence[evidence] += 1
            semantic_candidate_kinds[(evidence, candidate_kind)] += 1
            if "purpose" in sampler["annotationFields"]:
                purpose = "+".join(sampler["purposeValues"]) or "<invalid-or-non-string>"
                purpose_candidate_kinds[(purpose, candidate_kind)] += 1

    descriptor_active = sum(sample["descriptorEffectsActive"] for sample in samples)
    descriptor_inactive = sum(sample["descriptorEffectsInactive"] for sample in samples)
    material_nodes = sum(graph["materialNodeCount"] for graph in graphs)
    program_counts = outcome_counts(nodes, "program")
    return {
        "sample_count": len(samples),
        "descriptor_effects": {
            "total": descriptor_active + descriptor_inactive,
            "active": descriptor_active,
            "inactive": descriptor_inactive,
        },
        "authored_plan_count": sum(sample["authoredPlanCount"] for sample in samples),
        "graph_effect_count": sum(graph["effectCount"] for graph in graphs),
        "graph_node_count": sum(graph["nodeCount"] for graph in graphs),
        "graph_node_kinds": {
            "material": material_nodes,
            "copy": sum(graph["copyNodeCount"] for graph in graphs),
            "swap": sum(graph["swapNodeCount"] for graph in graphs),
            "unknown": sum(graph["unknownNodeCount"] for graph in graphs),
        },
        "graph_blocker_count": sum(graph["blockerCount"] for graph in graphs),
        "render_target_count": sum(graph["renderTargetCount"] for graph in graphs),
        "sample_scoped_contract_count": len(contracts),
        "material_file_pass_count": sum(
            sample["materialFilePassCount"] for sample in samples
        ),
        "normalized_shader_identity_count": len({
            contract["identity"].replace("\\", "/").lower()
            for contract in contracts
        }),
        "identity_canonical_revision_count": len({
            (
                contract["identity"].replace("\\", "/").lower(),
                contract["canonicalSHA256"],
            )
            for contract in contracts
        }),
        "runtime_contract_projection": {
            "validated_samples": sum(
                sample["contractProjectionValidated"] for sample in samples
            ),
            "unavailable_samples": sum(
                not sample["contractProjectionValidated"] for sample in samples
            ),
        },
        "keys": {
            "graph": len(graphs),
            "effect": len(effects),
            "node": len(nodes),
        },
        "resolved_material": {
            "override_facts": {
                "selected_override_slot_count": len(resolved_slots),
                "slots_with_lower_precedence_provenance_count": len(
                    resolved_multi_slots
                ),
                "nodes_with_lower_precedence_provenance_count": len(
                    resolved_multi_nodes
                ),
                "provenance_entry_count": len(resolved_candidates),
                "lower_precedence_provenance_entry_count": (
                    len(resolved_candidates) - len(resolved_slots)
                ),
                "precedence": "low-to-high-last-candidate-selected",
                "earlier_entries_are_load_fallbacks": False,
            },
            "provenance_source_counts": dict(
                sorted(resolved_candidate_sources.items())
            ),
            "precedence_chain_counts": dict(sorted(resolved_chains.items())),
            "selected_source_counts": dict(sorted(resolved_final_sources.items())),
            "multi_contributor_uniforms": {
                "count": len(multi_contributor_uniforms),
                "node_count": len({
                    (
                        node["key"]["sampleID"], node["key"]["layerID"],
                        node["key"]["nodeIndex"],
                    )
                    for node, _ in multi_contributor_uniforms
                }),
                "name_counts": dict(sorted(contributor_names.items())),
                "contributor_sequence_counts": dict(
                    sorted(contributor_sequences.items())
                ),
                "binding_key_set_counts": dict(
                    sorted(contributor_binding_keys.items())
                ),
                "timeline_shape_counts": dict(
                    sorted(contributor_timeline_shapes.items())
                ),
                "script_shape_counts": dict(sorted(contributor_scripts.items())),
                "material_contract_revision_count": len(
                    contributor_revision_counts
                ),
                "material_contract_revisions": [
                    {
                        "material_raw_sha256": material,
                        "shader_identity": shader,
                        "contract_canonical_sha256": revision,
                        "count": count,
                    }
                    for (material, shader, revision), count
                    in sorted(contributor_revision_counts.items())
                ],
            },
        },
        "template": {
            "outcomes": outcome_counts(nodes, "template"),
            "failure_phase_code": failure_distribution(nodes, "template"),
            "fixed_slot_count": 8,
            "occupied_slot_count": len(template_slots),
            "candidate_count": len(template_candidates),
            "multi_candidate_slot_count": len(template_multi_slots),
            "multi_candidate_node_count": len(template_multi_nodes),
            "candidate_source_counts": dict(sorted(template_candidate_sources.items())),
            "candidate_chain_counts": dict(sorted(template_chains.items())),
            "final_source_counts": dict(sorted(template_final_sources.items())),
            "state_counts": dict(sorted(states.items())),
        },
        "r2_variant_bootstrap": {
            "outcomes": outcome_counts(nodes, "preparation"),
            "failure_phase_code": failure_distribution(nodes, "preparation"),
            "active_sampler_slot_count": sum(sampler_slots.values()),
            "active_sampler_slot_counts": dict(sorted(sampler_slots.items())),
            "sampler_annotation_field_counts": dict(sorted(annotation_fields.items())),
            "active_sampler_final_candidate_kind_counts": dict(
                sorted(sampler_candidate_kinds.items())
            ),
            "active_sampler_selected_field_set_counts": {
                "+".join(fields): count
                for fields, count in sorted(sampler_field_sets.items())
            },
            "active_sampler_profile_counts": counter_rows(
                sampler_profiles,
                ("candidate_kind", "mode", "material", "default_kind", "format"),
            ),
            "mode_candidate_kind_counts": counter_rows(
                mode_candidate_kinds, ("mode", "candidate_kind")
            ),
            "mode_value_counts": dict(sorted(mode_values.items())),
            "format_value_counts": dict(sorted(format_values.items())),
            "public_mode_counts": {
                mode: mode_values.get(mode, 0)
                for mode in ("opacitymask", "rgbmask", "flowmask")
            },
            "observed_unsupported_mode_counts": {
                mode: mode_values.get(mode, 0)
                for mode in ("normal", "depth")
            },
            "observed_unsupported_format_counts": {
                "normalmap": format_values.get("normalmap", 0)
            },
            "semantic_evidence_counts": dict(sorted(semantic_evidence.items())),
            "semantic_evidence_candidate_kind_counts": counter_rows(
                semantic_candidate_kinds, ("evidence", "candidate_kind")
            ),
            "semantic_proven_sampler_count": (
                sum(semantic_evidence.values()) - semantic_evidence.get("unproven", 0)
            ),
            "semantic_unproven_sampler_count": semantic_evidence.get("unproven", 0),
            "authored_purpose_field_count": sum(purpose_candidate_kinds.values()),
            "authored_purpose_candidate_kind_counts": counter_rows(
                purpose_candidate_kinds, ("purpose", "candidate_kind")
            ),
            "authored_purpose_policy": (
                "observed-only; purpose is not an authored admission field and is "
                "never used by this census to prove sampler semantics"
            ),
            "resolved_color_contract_count": color_resolved,
            "unresolved_color_contract_count": color_unresolved,
            "evidence_boundary": (
                "only non-null descriptor material-file texture slots seed R2 "
                "variant selection; instance, graph, provider, and user candidates "
                "are not treated as immutable resource readiness"
            ),
        },
        "program": {
            "outcomes": program_counts,
            "attempted_count": len(nodes) - program_counts.get("notAttempted", 0),
            "reason_counts": {
                "runtime-snapshot-unavailable": program_counts.get("notAttempted", 0)
            },
        },
        "program_blockers": {
            "texture-purpose-unproven": semantic_evidence.get("unproven", 0),
            "color-contract-unproven": color_unresolved,
            "uniform-contributor-policy-unproven": len(
                multi_contributor_uniforms
            ),
            "runtime-snapshot-unavailable": program_counts.get("notAttempted", 0),
        },
    }


def validate_conservation(summary: dict[str, Any]) -> None:
    if summary["descriptor_effects"]["active"] != summary["graph_effect_count"]:
        raise CensusError("active descriptor effects do not conserve into graph effects")
    if summary["authored_plan_count"] != summary["keys"]["graph"]:
        raise CensusError("authored plan count does not conserve into GraphKey records")
    if summary["graph_effect_count"] != summary["keys"]["effect"]:
        raise CensusError("graph effect count does not conserve into EffectKey records")
    if summary["graph_node_count"] != summary["keys"]["node"]:
        raise CensusError("graph node count does not conserve into NodeKey records")
    if sum(summary["graph_node_kinds"].values()) != summary["graph_node_count"]:
        raise CensusError("graph node kind conservation failed")
    if sum(summary["template"]["outcomes"].values()) != summary["graph_node_count"]:
        raise CensusError("Template outcome conservation failed")
    if sum(summary["r2_variant_bootstrap"]["outcomes"].values()) \
            != summary["graph_node_count"]:
        raise CensusError("R2 bootstrap outcome conservation failed")
    r2 = summary["r2_variant_bootstrap"]
    if sum(r2["active_sampler_final_candidate_kind_counts"].values()) \
            != r2["active_sampler_slot_count"]:
        raise CensusError("R2 active sampler candidate-kind conservation failed")
    if sum(r2["active_sampler_selected_field_set_counts"].values()) \
            != r2["active_sampler_slot_count"]:
        raise CensusError("R2 active sampler annotation-profile conservation failed")
    if sum(r2["semantic_evidence_counts"].values()) \
            != r2["active_sampler_slot_count"]:
        raise CensusError("R2 sampler semantic-evidence conservation failed")
    if sum(summary["program"]["outcomes"].values()) != summary["graph_node_count"]:
        raise CensusError("Program outcome conservation failed")
    if summary["program"]["attempted_count"] != 0:
        raise CensusError("Program was attempted without an immutable runtime snapshot")


def build_report(
    args: argparse.Namespace,
    inputs: dict[str, Any],
    corpus: dict[str, Any],
    first_bytes: bytes,
    second_bytes: bytes,
    swift_version: str,
    sdk_version: str,
    current_sources: dict[str, Any],
) -> dict[str, Any]:
    summary = build_summary(corpus)
    validate_conservation(summary)
    fixture_directory = inputs["fixture_path"].parent
    command = [
        "python3",
        "script/scene_material_program_census.py",
        "--fixture",
        portable_path(inputs["fixture_path"], fixture_directory),
        "--matrix",
        portable_path(inputs["matrix_path"], fixture_directory),
        "--runtime-report",
        portable_path(inputs["runtime_report_path"], fixture_directory),
        "--stock-root",
        portable_path(inputs["stock_root"], fixture_directory),
        "--output",
        "<output>",
    ]
    sample_inputs = [{
        "key": {
            "sample_id": sample["sampleID"],
            "project_sha256": sample["projectSHA256"],
            "package_sha256": sample["packageSHA256"],
            "runtime_input_sha256": sample["runtimeInputSHA256"],
        },
        "runtime_evidence_sha256": sample["runtimeEvidenceSHA256"],
        "runtime_snapshot_state": sample["runtimeSnapshotState"],
    } for sample in inputs["samples"]]
    return {
        "schema_version": 2,
        "kind": "scene-material-program-census",
        "generator": {
            "path": "script/scene_material_program_census.py",
            "sha256": sha256_file(SCRIPT_PATH),
            "harness_sha256": sha256_bytes(HARNESS_SOURCE.encode("utf-8")),
            "canonical_json_contract": "sorted-keys-indented-utf8-v1",
            "command": command,
        },
        "toolchain": {
            "python_version": platform.python_version(),
            "swift_version": swift_version,
            "macos_sdk_version": sdk_version,
        },
        "inputs": {
            "fixture": {
                "path": portable_path(inputs["fixture_path"], fixture_directory),
                "sha256": inputs["fixture_sha256"],
            },
            "matrix": {
                "path": portable_path(inputs["matrix_path"], fixture_directory),
                "sha256": inputs["matrix_sha256"],
                "name": inputs["matrix"].get("name"),
                "sample_count": len(inputs["samples"]),
            },
            "runtime_report": {
                "path": portable_path(inputs["runtime_report_path"], fixture_directory),
                "sha256": inputs["runtime_report_sha256"],
                "declared_matrix_sha256": inputs["runtime_report"].get("matrix_sha256"),
                "sample_count": len(inputs["runtime_report"]["samples"]),
            },
            "sample_root": portable_path(inputs["sample_root"], fixture_directory),
            "runtime_homes": portable_path(inputs["runtime_homes"], fixture_directory),
            "stock_root": portable_path(inputs["stock_root"], fixture_directory),
            "samples": sample_inputs,
            "current_sources": current_sources,
        },
        "method": {
            "sample_key": (
                "sample-id + separate project/package/runtime-input SHA-256 identities"
            ),
            "graph_key": "sample-id + layer-id",
            "effect_key": "sample-id + layer-id + effect-index + descriptor-id",
            "node_key": "sample-id + layer-id + node-index",
            "graph_authority": (
                "current SceneAuthoredEffectRenderPlanner output byte-compared after "
                "decoding the production runtime graph"
            ),
            "material_join": (
                "node.materialPassID -> descriptor material identity -> material passIndex; "
                "definitionPassIndex is never a material lookup key"
            ),
            "template": (
                "SceneAuthoredMaterialResolver -> "
                "SceneResolvedMaterialTemplateCompiler with fixed sparse 8 slots"
            ),
            "texture_override": (
                "resolver candidates are low-to-high provenance; an earlier authored "
                "candidate is considered only when the selected user/provider override "
                "is explicitly absent, never when it is missing, pending, unavailable, "
                "invalid, or semantically unproven"
            ),
            "uniform_contributors": (
                "all resolved materials are scanned for losslessly preserved dynamic "
                "contributors; multi-contributor facts are not Template failures"
            ),
            "sampler_semantics": (
                "official public mode evidence covers opacitymask/rgbmask/flowmask; "
                "a regular selected graph input is a graph-color-boundary. Generic "
                "normal/depth/format and authored purpose fields remain observation-only "
                "and fail closed without a separately verified stock contract"
            ),
            "shader_contract": (
                "current SceneShaderContractLoader with package/loose/stock VFS and "
                "current source graph"
            ),
            "program": (
                "notAttempted(runtime-snapshot-unavailable); no empty or synthetic "
                "texture/dynamic snapshot is manufactured"
            ),
            "evidence_boundaries": [
                "static Template and R2 preparation census only; no Metal compile or GPU execution",
                "Program PASS is impossible without one immutable resource and dynamic snapshot",
                "matrix/runtime success and non-black captures do not establish visual parity",
                "no official payload, shader source, material JSON, absolute path, or object identity is published",
            ],
        },
        "determinism": {
            "runs": 2,
            "byte_equal": first_bytes == second_bytes,
            "raw_sha256": [sha256_bytes(first_bytes), sha256_bytes(second_bytes)],
        },
        "summary": summary,
        "results": corpus,
        "validation": {
            "failures": [],
            "conservation": {
                "samples": summary["sample_count"],
                "graphs": summary["keys"]["graph"],
                "effects": summary["keys"]["effect"],
                "nodes": summary["keys"]["node"],
                "current_repeat_byte_equal": first_bytes == second_bytes,
            },
        },
    }


def publish_atomic(path: Path, payload: bytes) -> str:
    path = path.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_bytes() == payload:
            return "unchanged"
        raise CensusError(f"refusing to overwrite different evidence: {path}")
    temporary_path: Path | None = None
    try:
        descriptor, name = tempfile.mkstemp(
            prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
        )
        temporary_path = Path(name)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
        directory_descriptor = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
        return "written"
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, default=DEFAULT_FIXTURE)
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    parser.add_argument("--runtime-report", required=True, type=Path)
    parser.add_argument("--stock-root", type=Path, default=DEFAULT_STOCK_ROOT)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def run(args: argparse.Namespace) -> tuple[Path, dict[str, Any], str]:
    inputs = validate_inputs(
        args.fixture,
        args.matrix,
        args.runtime_report,
        args.stock_root,
        args.output,
    )
    swift_version = tool_output(["xcrun", "--sdk", "macosx", "swiftc", "--version"])
    sdk_version = tool_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"])
    current_sources = source_manifest(CURRENT_SOURCE_PATHS)
    with tempfile.TemporaryDirectory(prefix="scene-material-program-census-") as temporary:
        temporary_root = Path(temporary)
        harness_path = temporary_root / "SceneMaterialProgramCensusHarness.swift"
        harness_path.write_text(HARNESS_SOURCE, encoding="utf-8")
        manifest_path = temporary_root / "input-manifest.json"
        manifest_path.write_bytes(canonical_json_bytes({"samples": inputs["samples"]}))
        binary = temporary_root / "material-program-census"
        compile_harness(
            harness_path,
            binary,
            temporary_root / "module-cache",
        )
        first_bytes = run_harness(binary, manifest_path, inputs["stock_root"])
        second_bytes = run_harness(binary, manifest_path, inputs["stock_root"])
        if first_bytes != second_bytes:
            raise CensusError("R3 census repeated output is not byte-identical")
        sample_ids = [sample["sampleID"] for sample in inputs["samples"]]
        corpus = validate_corpus_output(
            first_bytes,
            sample_ids,
            temporary_root,
        )
        validate_stable_inputs(inputs, current_sources)
        report = build_report(
            args,
            inputs,
            corpus,
            first_bytes,
            second_bytes,
            swift_version,
            sdk_version,
            current_sources,
        )
        report_bytes = canonical_json_bytes(report, pretty=True)

    output = args.output.expanduser().resolve()
    publication = publish_atomic(output, report_bytes)
    return output, report, publication


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        output, report, publication = run(args)
    except CensusError as error:
        print(f"Scene material Program census failed: {error}", file=sys.stderr)
        return 1
    summary = report["summary"]
    print(
        "Scene material Program census PASS: "
        f"{output} ({publication}) "
        f"samples={summary['sample_count']} "
        f"nodes={summary['graph_node_count']} "
        f"templates={summary['template']['outcomes']} "
        f"programs={summary['program']['outcomes']} "
        f"sha256={sha256_file(output)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
