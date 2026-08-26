#!/usr/bin/env python3
"""Reproducible R1/R2 Scene shader preparation corpus census.

This is a planner-level, read-only corpus probe. It compiles the same embedded
Swift harness once against an archived baseline and once against the current
working-tree sources, runs the current binary twice, and publishes one
deterministic report only after all input, conservation, and repeatability
checks pass.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
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
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
)
REAL_WORKSHOP_ROOT = (
    Path.home() / "Movies/MyWallpaperX/创意工坊"
).resolve()

BASELINE_SOURCE_PATHS = (
    "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneJSONValue.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneEffectStageCompileModel.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredMaterialResolver.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneMaterialRenderState.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneShaderContract.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneShaderContractLoader.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderLexer.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderSyntax.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderMetalSource.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderFrontend.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderExecutionPlan.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderUniformBinder.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredScrollShaderProfile.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderExecutionPlanner.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShaderExecutionPlanner+Bindings.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceView.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceIndex.swift",
)

AUTHORED_SHADER_FRONTEND_SOURCES = scene_swift_source_relpaths(
    "authored_shader_frontend_implementation"
)
AUTHORED_SHADER_PREPARATION_SOURCES = scene_swift_source_relpaths(
    "authored_shader_preparation_implementation"
)
AUTHORED_EFFECT_PLANNING_SOURCES = scene_swift_source_relpaths_by_basename(
    "authored_effect_planning_support"
)

CURRENT_SOURCE_PATHS = (
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneJSONValue.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneAuthoredEffectRenderPlan.swift"],
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift",
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneAuthoredMaterialResolver.swift"],
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneMaterialRenderState.swift",
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderSourceGraph.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderLegacyAnnotationJSON.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderContract.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderSourceGraphBuilder.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderSourceResolver.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneResourceView.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneResourceIndex.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES["SceneShaderContractLoader.swift"],
    AUTHORED_EFFECT_PLANNING_SOURCES[
        "SceneShaderContractLoader+SourceGraph.swift"
    ],
    *AUTHORED_SHADER_FRONTEND_SOURCES,
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureSampling.swift",
    *AUTHORED_SHADER_PREPARATION_SOURCES,
)


HARNESS_SOURCE = r'''
import CryptoKit
import Foundation

// This census only needs the compile-input collection shape; value resolution
// remains exercised by the product/runtime capability tests.
enum SceneDynamicTarget: Hashable {
    case effectVisibility(layerID: Int, effectIndex: Int)
}

enum SceneDynamicValueType: Hashable {
    case bool, scalar, vector2, vector3, vector4, string
}

struct SceneDynamicUserPropertyProducer: Hashable {
    let propertyKey: String
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType?
}

struct SceneDocument {
    struct ShaderValue {
        let userBinding: String?
        let components: [Double]?
        let timeline: String?
        let timelineDiagnostics: [String]
    }
}

struct SceneEffectTextureInput {
    let name: String
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        let sizeWH: [Float]?
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
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

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

private struct SampleRecord: Codable {
    let sampleID: String
    let materialPasses: Int
    let shaderReferences: Int
}

private struct StageRecord: Codable {
    let kind: String
    let relativePath: String
    let rawSHA256: String
    let includes: Int
    let annotations: Int
    let declarations: Int
}

#if R2_CURRENT
private struct SourceGraphNodeRecord: Codable {
    let virtualPath: String
    let provenance: String
    let rawSHA256: String
    let byteCount: Int
}
#endif

private struct ContractRecord: Codable {
    let sampleID: String
    let identity: String
    let sourceKind: String
    let stages: [StageRecord]
    let diagnostics: [String]
    let canonicalSHA256: String
    let sourceGraphDependencySHA256: String?
    let sourceGraphDiagnostics: [String]?
    let stageRootProvenances: [String]?
    let graphNodeProvenances: [String]?
#if R2_CURRENT
    let sourceGraphNodes: [SourceGraphNodeRecord]?
#endif
}

private struct PassRecord: Codable {
    let sampleID: String
    let materialPath: String
    let materialFileSHA256: String
    let materialPassIndex: Int
    let materialPassCanonicalSHA256: String
    let shaderIdentity: String
    let gpuAdmission: String
    let gpuFailurePhase: String?
    let gpuFailureCode: String?
    let gpuFailureDetails: [String]
    let preparation: String
    let preparationFailurePhase: String?
    let preparationFailureCode: String?
    let preparationFailureDetails: [String]
    let preparationCacheKey: String?
    let preparationVertexSHA256: String?
    let preparationFragmentSHA256: String?
    let preparationVertexDependencySHA256: String?
    let preparationFragmentDependencySHA256: String?
    let preparationVertexVariantSHA256: String?
    let preparationFragmentVariantSHA256: String?
    let preparationColorResolved: Bool?
}

private struct CorpusOutput: Codable {
    let implementation: String
    let samples: [SampleRecord]
    let contracts: [ContractRecord]
    let passes: [PassRecord]
}

private struct MaterialPass {
    let sampleID: String
    let projectRoot: URL
    let packageRoot: URL
    let materialPath: String
    let materialFileSHA256: String
    let passIndex: Int
    let passCanonicalSHA256: String
    let shaderIdentity: String
    let textureSlots: [String?]
    let userTextureInputs: [SceneEffectTextureInput?]
    let combos: [String: Int]
    let constants: [String: SceneDocument.ShaderValue]
    let userShaderValues: [String: String]
    let blending: String?
    let depthTest: String?
    let depthWrite: String?
    let cullMode: String?
    let alphaWriting: String?
}

private struct Outcome {
    let status: String
    let phase: String?
    let code: String?
    let details: [String]
}

#if R2_CURRENT
private struct PreparationOutcome {
    let outcome: Outcome
    let program: SceneShaderPreparedProgram?
}
#endif

private enum HarnessError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidCorpus(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "expected <sample-root> <runtime-homes-root> <stock-assets-root>"
        case .invalidCorpus(let message):
            return message
        }
    }
}

@main
private enum CorpusHarness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let layerID = 1

    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw HarnessError.invalidArguments
        }
        let sampleRoot = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        ).standardizedFileURL
        let runtimeHomes = URL(
            fileURLWithPath: CommandLine.arguments[2],
            isDirectory: true
        ).standardizedFileURL
        let stockRoot = URL(
            fileURLWithPath: CommandLine.arguments[3],
            isDirectory: true
        ).standardizedFileURL

        let sampleIDs = try directoryNames(sampleRoot).filter {
            !$0.isEmpty && $0.allSatisfy(\.isNumber)
        }.sorted()
        var sampleRecords: [SampleRecord] = []
        var contractRecords: [ContractRecord] = []
        var passRecords: [PassRecord] = []

        for sampleID in sampleIDs {
            let projectRoot = sampleRoot.appendingPathComponent(
                sampleID,
                isDirectory: true
            )
            let packageRoot = try packageRoot(
                sampleID: sampleID,
                runtimeHomes: runtimeHomes
            )
            let materialPasses = try loadMaterialPasses(
                sampleID: sampleID,
                projectRoot: projectRoot,
                packageRoot: packageRoot
            )
            let shaderReferences = Array(Set(
                materialPasses.map(\.shaderIdentity)
            )).sorted()
            let resourceView = SceneResourceView(
                projectRootURL: projectRoot,
                packageRootURL: packageRoot,
                stockAssetsRootURL: stockRoot
            )
            var contracts: [String: SceneShaderContract] = [:]
            for reference in shaderReferences {
                let loaded = loadContracts(
                    reference: reference,
                    resourceView: resourceView
                )
                guard loaded.count == 1, let contract = loaded.first else {
                    throw HarnessError.invalidCorpus(
                        "sample \(sampleID) shader \(reference) produced \(loaded.count) contracts"
                    )
                }
                contracts[reference] = contract
                contractRecords.append(contractRecord(
                    sampleID: sampleID,
                    contract: contract
                ))
            }

            for material in materialPasses {
                guard let contract = contracts[material.shaderIdentity] else {
                    throw HarnessError.invalidCorpus(
                        "sample \(sampleID) shader contract is missing for \(material.shaderIdentity)"
                    )
                }
                passRecords.append(passRecord(
                    material: material,
                    contract: contract
                ))
            }
            sampleRecords.append(.init(
                sampleID: sampleID,
                materialPasses: materialPasses.count,
                shaderReferences: shaderReferences.count
            ))
        }

        contractRecords.sort {
            ($0.sampleID, $0.identity) < ($1.sampleID, $1.identity)
        }
        passRecords.sort {
            ($0.sampleID, $0.materialPath, $0.materialPassIndex)
                < ($1.sampleID, $1.materialPath, $1.materialPassIndex)
        }
#if R2_CURRENT
        let implementation = "r2-worktree"
#else
        let implementation = "r1-baseline"
#endif
        let output = CorpusOutput(
            implementation: implementation,
            samples: sampleRecords,
            contracts: contractRecords,
            passes: passRecords
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(output))
    }

    private static func packageRoot(
        sampleID: String,
        runtimeHomes: URL
    ) throws -> URL {
        let parent = runtimeHomes
            .appendingPathComponent(sampleID, isDirectory: true)
            .appendingPathComponent(
                "Library/Caches/MyWallpaperX/SteamWorkshopScene",
                isDirectory: true
            )
        let roots = try directoryNames(parent).map {
            parent.appendingPathComponent($0, isDirectory: true)
        }
        guard roots.count == 1, let root = roots.first else {
            throw HarnessError.invalidCorpus(
                "sample \(sampleID) expected one extraction root, found \(roots.count)"
            )
        }
        return root
    }

    private static func directoryNames(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map(\.lastPathComponent)
    }

    private static func loadMaterialPasses(
        sampleID: String,
        projectRoot: URL,
        packageRoot: URL
    ) throws -> [MaterialPass] {
        let materialRoot = packageRoot.appendingPathComponent(
            "materials",
            isDirectory: true
        )
        guard let enumerator = FileManager.default.enumerator(
            at: materialRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw HarnessError.invalidCorpus(
                "sample \(sampleID) material root cannot be enumerated"
            )
        }
        var urls: [URL] = []
        for case let url as URL in enumerator
        where url.pathExtension.localizedLowercase == "json" {
            urls.append(url)
        }
        urls.sort { $0.path < $1.path }

        var result: [MaterialPass] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let passes = root["passes"] as? [[String: Any]] else {
                throw HarnessError.invalidCorpus(
                    "sample \(sampleID) has invalid material \(url.lastPathComponent)"
                )
            }
            let materialPath = relativePath(url, under: packageRoot)
            for (passIndex, pass) in passes.enumerated() {
                guard let shader = normalizedPath(pass["shader"] as? String) else {
                    continue
                }
                let canonical = try JSONSerialization.data(
                    withJSONObject: pass,
                    options: [.sortedKeys]
                )
                result.append(MaterialPass(
                    sampleID: sampleID,
                    projectRoot: projectRoot,
                    packageRoot: packageRoot,
                    materialPath: materialPath,
                    materialFileSHA256: sha256(data),
                    passIndex: passIndex,
                    passCanonicalSHA256: sha256(canonical),
                    shaderIdentity: normalizeShaderIdentity(shader),
                    textureSlots: textureSlots(pass["textures"]),
                    userTextureInputs: userTextureInputs(pass["usertextures"]),
                    combos: pass["combos"] as? [String: Int] ?? [:],
                    constants: shaderValues(pass["constantshadervalues"]),
                    userShaderValues: pass["usershadervalues"] as? [String: String] ?? [:],
                    blending: pass["blending"] as? String,
                    depthTest: renderState(pass, "depthtest", "depthtesting"),
                    depthWrite: renderState(pass, "depthwrite", "depthwriting"),
                    cullMode: renderState(pass, "cullmode", "culling"),
                    alphaWriting: pass["alphawriting"] as? String
                ))
            }
        }
        return result
    }

    private static func loadContracts(
        reference: String,
        resourceView: SceneResourceView
    ) -> [SceneShaderContract] {
#if R2_CURRENT
        SceneShaderContractLoader().load(
            shaderReferences: [reference],
            resourceView: resourceView
        )
#else
        SceneShaderContractLoader().load(
            shaderReferences: [reference],
            rootURL: sourceRootURL(
                reference: reference,
                resourceView: resourceView
            )
        )
#endif
    }

    private static func sourceRootURL(
        reference: String,
        resourceView: SceneResourceView
    ) -> URL {
        let identity = normalizeShaderIdentity(reference)
        for suffix in [".vert", ".frag"] {
            if let resource = resourceView.resource(
                relativePath: "shaders/" + identity + suffix
            ), let root = resourceView.rootURL(containing: resource.url) {
                return root
            }
        }
        return resourceView.primaryRootURL
    }

    private static func contractRecord(
        sampleID: String,
        contract: SceneShaderContract
    ) -> ContractRecord {
        let stages = contract.stages.map {
            StageRecord(
                kind: $0.kind.rawValue,
                relativePath: $0.relativePath,
                rawSHA256: $0.rawSHA256,
                includes: $0.includes.count,
                annotations: $0.annotations.count,
                declarations: $0.declarations.count
            )
        }
#if R2_CURRENT
        let graph = contract.sourceGraph
        let roots = graph.map { graph in
            contract.stages.compactMap {
                graph.node(at: $0.relativePath)?.provenance.rawValue
            }.sorted()
        }
        let nodeProvenances = graph.map {
            Array(Set($0.nodes.map { $0.provenance.rawValue })).sorted()
        }
        let nodes = graph.map {
            $0.nodes.map {
                SourceGraphNodeRecord(
                    virtualPath: $0.virtualPath,
                    provenance: $0.provenance.rawValue,
                    rawSHA256: $0.rawSHA256,
                    byteCount: $0.byteCount
                )
            }.sorted { $0.virtualPath < $1.virtualPath }
        }
        return ContractRecord(
            sampleID: sampleID,
            identity: contract.identity,
            sourceKind: contract.sourceKind.rawValue,
            stages: stages,
            diagnostics: contract.diagnostics.map { $0.code.rawValue },
            canonicalSHA256: contract.canonicalSHA256,
            sourceGraphDependencySHA256: graph?.dependencySHA256,
            sourceGraphDiagnostics: graph?.diagnostics.map { $0.code.rawValue }.sorted(),
            stageRootProvenances: roots,
            graphNodeProvenances: nodeProvenances,
            sourceGraphNodes: nodes
        )
#else
        return ContractRecord(
            sampleID: sampleID,
            identity: contract.identity,
            sourceKind: contract.sourceKind.rawValue,
            stages: stages,
            diagnostics: contract.diagnostics.map { $0.code.rawValue },
            canonicalSHA256: contract.canonicalSHA256,
            sourceGraphDependencySHA256: nil,
            sourceGraphDiagnostics: nil,
            stageRootProvenances: nil,
            graphNodeProvenances: nil
        )
#endif
    }

    private static func passRecord(
        material: MaterialPass,
        contract: SceneShaderContract
    ) -> PassRecord {
        let graph = graph(material)
        let descriptor = descriptor(material)
        let gpu = compileOutcome(
            graph: graph,
            descriptor: descriptor,
            contract: contract
        )
#if R2_CURRENT
        let prepared = preparationOutcome(
            graph: graph,
            descriptor: descriptor,
            contract: contract
        )
        let program = prepared.program
        return PassRecord(
            sampleID: material.sampleID,
            materialPath: material.materialPath,
            materialFileSHA256: material.materialFileSHA256,
            materialPassIndex: material.passIndex,
            materialPassCanonicalSHA256: material.passCanonicalSHA256,
            shaderIdentity: material.shaderIdentity,
            gpuAdmission: gpu.status,
            gpuFailurePhase: gpu.phase,
            gpuFailureCode: gpu.code,
            gpuFailureDetails: gpu.details,
            preparation: prepared.outcome.status,
            preparationFailurePhase: prepared.outcome.phase,
            preparationFailureCode: prepared.outcome.code,
            preparationFailureDetails: prepared.outcome.details,
            preparationCacheKey: program?.cacheKey,
            preparationVertexSHA256: program?.vertex.preparedSHA256,
            preparationFragmentSHA256: program?.fragment.preparedSHA256,
            preparationVertexDependencySHA256: program?.vertex.dependencySHA256,
            preparationFragmentDependencySHA256: program?.fragment.dependencySHA256,
            preparationVertexVariantSHA256: program?.vertex.variantSHA256,
            preparationFragmentVariantSHA256: program?.fragment.variantSHA256,
            preparationColorResolved: program?.colorContract.isResolved
        )
#else
        return PassRecord(
            sampleID: material.sampleID,
            materialPath: material.materialPath,
            materialFileSHA256: material.materialFileSHA256,
            materialPassIndex: material.passIndex,
            materialPassCanonicalSHA256: material.passCanonicalSHA256,
            shaderIdentity: material.shaderIdentity,
            gpuAdmission: gpu.status,
            gpuFailurePhase: gpu.phase,
            gpuFailureCode: gpu.code,
            gpuFailureDetails: gpu.details,
            preparation: "unavailable",
            preparationFailurePhase: nil,
            preparationFailureCode: nil,
            preparationFailureDetails: [],
            preparationCacheKey: nil,
            preparationVertexSHA256: nil,
            preparationFragmentSHA256: nil,
            preparationVertexDependencySHA256: nil,
            preparationFragmentDependencySHA256: nil,
            preparationVertexVariantSHA256: nil,
            preparationFragmentVariantSHA256: nil,
            preparationColorResolved: nil
        )
#endif
    }

    private static func compileOutcome(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        contract: SceneShaderContract
    ) -> Outcome {
#if R2_CURRENT
        .init(
            status: "removed",
            phase: nil,
            code: nil,
            details: []
        )
#else
        outcome(SceneAuthoredShaderExecutionPlanner.compile(.init(
            stageGraph: graph,
            inputRole: .layerSource,
            descriptor: descriptor,
            shaderContracts: [contract]
        )))
#endif
    }

#if R2_CURRENT
    private static func preparationOutcome(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        contract: SceneShaderContract
    ) -> PreparationOutcome {
        guard let node = graph.nodes.first else {
            return .init(
                outcome: .init(
                    status: "rejected",
                    phase: "invariant",
                    code: "material-node-missing",
                    details: []
                ),
                program: nil
            )
        }
        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node,
            graph: graph,
            descriptor: descriptor
        )
        guard resolution.isResolved, let material = resolution.node else {
            return .init(
                outcome: .init(
                    status: "rejected",
                    phase: "material",
                    code: "material-resolution-failed",
                    details: resolution.issues
                ),
                program: nil
            )
        }
        let result = SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: contract,
            combos: material.combos,
            textureReadiness: [:]
        )
        switch result {
        case .notApplicable:
            return .init(
                outcome: .init(
                    status: "not-applicable",
                    phase: nil,
                    code: nil,
                    details: []
                ),
                program: nil
            )
        case .rejected(let failure):
            return .init(outcome: failureOutcome(failure), program: nil)
        case .accepted(let program):
            return .init(
                outcome: .init(
                    status: "accepted",
                    phase: nil,
                    code: nil,
                    details: []
                ),
                program: program
            )
        }
    }
#endif

    private static func outcome<Value>(
        _ result: SceneEffectStageBackendCompileResult<Value>
    ) -> Outcome {
        switch result {
        case .notApplicable:
            return .init(
                status: "not-applicable",
                phase: nil,
                code: nil,
                details: []
            )
        case .rejected(let failure):
            return failureOutcome(failure)
        case .accepted:
            return .init(
                status: "accepted",
                phase: nil,
                code: nil,
                details: []
            )
        }
    }

    private static func failureOutcome(
        _ failure: SceneEffectStageCompilerFailure
    ) -> Outcome {
        .init(
            status: "rejected",
            phase: failure.phase.rawValue,
            code: failure.code.rawValue,
            details: failure.details
        )
    }

#if R2_CURRENT
    private static func failureOutcome(
        _ failure: SceneAuthoredShaderPreparationFailure
    ) -> Outcome {
        .init(
            status: "rejected",
            phase: failure.phase.rawValue,
            code: failure.code.rawValue,
            details: failure.details
        )
    }
#endif

    private static func graph(_ material: MaterialPass) -> Graph {
        let descriptorID = "census:\(material.materialPath)#\(material.passIndex)"
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: descriptorID
        )
        let input = Graph.TextureIdentity(
            kind: .layerSource,
            layerID: layerID,
            effect: nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: layerID,
            effect: key,
            name: nil
        )
        return Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/census/effect.json",
                input: input,
                output: output,
                nodeIndices: [0]
            )],
            renderTargets: [],
            nodes: [.init(
                nodeIndex: 0,
                effect: key,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: .material,
                materialPath: material.materialPath,
                materialPassID: "\(material.materialPath)#\(material.passIndex)",
                target: output,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )],
            finalOutput: output,
            blockers: []
        )
    }

    private static func descriptor(
        _ material: MaterialPass
    ) -> SceneRenderDescriptor {
        let descriptorID = "census:\(material.materialPath)#\(material.passIndex)"
        let instance = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:]
        )
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: descriptorID,
            visible: true,
            passes: [instance]
        )
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(material.materialPath)#\(material.passIndex)",
            materialPath: material.materialPath,
            shaderPath: material.shaderIdentity,
            textureSlots: material.textureSlots,
            userTextureInputs: material.userTextureInputs,
            combos: material.combos,
            constantShaderValues: material.constants,
            userShaderValues: material.userShaderValues,
            blending: material.blending,
            depthTest: material.depthTest,
            depthWrite: material.depthWrite,
            cullMode: material.cullMode,
            alphaWriting: material.alphaWriting
        )
        return .init(
            layers: [.init(
                id: layerID,
                contentKind: "solid",
                sizeWH: [128, 128],
                effects: [effect]
            )],
            materialPasses: [pass]
        )
    }

    private static func textureSlots(_ value: Any?) -> [String?] {
        (value as? [Any] ?? []).map {
            normalizedPath($0 as? String)
        }
    }

    private static func userTextureInputs(
        _ value: Any?
    ) -> [SceneEffectTextureInput?] {
        (value as? [Any] ?? []).map { raw in
            if raw is NSNull { return nil }
            if let string = raw as? String {
                let normalized = string.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).replacingOccurrences(of: "\\", with: "/")
                return normalized.isEmpty ? nil : .init(name: normalized)
            }
            return .init(name: String(describing: raw))
        }
    }

    private static func shaderValues(
        _ value: Any?
    ) -> [String: SceneDocument.ShaderValue] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return dictionary.reduce(
            into: [String: SceneDocument.ShaderValue]()
        ) { result, pair in
            result[pair.key] = shaderValue(pair.value)
        }
    }

    private static func shaderValue(
        _ value: Any
    ) -> SceneDocument.ShaderValue {
        if let double = value as? Double {
            return .init(
                userBinding: nil,
                components: [double],
                timeline: nil,
                timelineDiagnostics: []
            )
        }
        if let integer = value as? Int {
            return .init(
                userBinding: nil,
                components: [Double(integer)],
                timeline: nil,
                timelineDiagnostics: []
            )
        }
        if let string = value as? String {
            let components = numericComponents(string)
            return .init(
                userBinding: nil,
                components: components.isEmpty ? nil : components,
                timeline: nil,
                timelineDiagnostics: []
            )
        }
        if let keyed = value as? [String: Any] {
            let raw = (keyed["value"] as? String) ?? "\(keyed)"
            let components = numericComponents(raw)
            return .init(
                userBinding: keyed["user"] as? String,
                components: components.isEmpty ? nil : components,
                timeline: nil,
                timelineDiagnostics: []
            )
        }
        return .init(
            userBinding: nil,
            components: nil,
            timeline: nil,
            timelineDiagnostics: []
        )
    }

    private static func numericComponents(_ value: String) -> [Double] {
        value.split {
            $0 == " " || $0 == "," || $0 == "\t"
        }.compactMap { Double($0) }
    }

    private static func renderState(
        _ pass: [String: Any],
        _ canonical: String,
        _ compatibility: String
    ) -> String? {
        (pass[canonical] as? String) ?? (pass[compatibility] as? String)
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizeShaderIdentity(_ value: String) -> String {
        var identity = value.replacingOccurrences(of: "\\", with: "/")
        for suffix in [".vert", ".frag", ".json"]
        where identity.localizedLowercase.hasSuffix(suffix) {
            identity.removeLast(suffix.count)
            break
        }
        return identity
    }

    private static func relativePath(_ url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return String(path.dropFirst(rootPath.count + 1))
            .replacingOccurrences(of: "\\", with: "/")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }
}
'''


class CensusError(RuntimeError):
    """A fail-closed corpus, build, or report contract violation."""


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
        text = json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
        )
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
            relative = resolved.relative_to(fixture_root).as_posix()
            return f"<fixture-root>/{relative}"
    return f"<external>/{resolved.name}"


def require_safe_input_root(path: Path, label: str) -> Path:
    resolved = path.expanduser().resolve(strict=True)
    if (
        resolved == REAL_WORKSHOP_ROOT
        or is_relative_to(resolved, REAL_WORKSHOP_ROOT)
        or is_relative_to(REAL_WORKSHOP_ROOT, resolved)
    ):
        raise CensusError(f"{label} must not resolve to the real Workshop tree: {resolved}")
    if not resolved.is_dir():
        raise CensusError(f"{label} is not a directory: {resolved}")
    return resolved


def resolve_configured_path(raw: Any, fixture_path: Path, key: str) -> Path:
    if not isinstance(raw, str) or not raw.strip():
        raise CensusError(f"fixture {key} must be a non-empty path")
    configured = Path(raw).expanduser()
    return (
        configured.resolve()
        if configured.is_absolute()
        else (REPOSITORY_ROOT / configured).resolve()
    )


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CensusError(f"cannot load {label} {path}: {error}") from error
    if not isinstance(value, dict):
        raise CensusError(f"{label} must be a JSON object: {path}")
    return value


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
            return candidate
    raise CensusError(f"sample {sample_root.name} has no package for {entry_name}")


def unique_cache_root(runtime_homes: Path, sample_id: str) -> Path:
    parent = (
        runtime_homes
        / sample_id
        / "Library/Caches/MyWallpaperX/SteamWorkshopScene"
    )
    roots = sorted(path.resolve() for path in parent.iterdir() if path.is_dir()) \
        if parent.is_dir() else []
    if len(roots) != 1:
        raise CensusError(
            f"sample {sample_id} expected one extraction root, found {len(roots)}"
        )
    return roots[0]


def relevant_tree_manifest(root: Path) -> dict[str, Any]:
    selected: list[Path] = []
    for relative_root in ("materials", "shaders"):
        directory = root / relative_root
        if directory.is_dir():
            selected.extend(path for path in directory.rglob("*") if path.is_file())
    records = []
    total_bytes = 0
    for path in sorted(selected, key=lambda item: item.relative_to(root).as_posix()):
        size = path.stat().st_size
        total_bytes += size
        records.append({
            "path": path.relative_to(root).as_posix(),
            "sha256": sha256_file(path),
            "bytes": size,
        })
    return {
        "algorithm": "sha256(canonical-json(file-path,sha256,bytes)-v1)",
        "file_count": len(records),
        "byte_count": total_bytes,
        "sha256": sha256_bytes(canonical_json_bytes(records)),
    }


def source_manifest(root: Path, paths: Sequence[str]) -> dict[str, Any]:
    records = []
    for relative in paths:
        path = root / relative
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
        "fingerprint_sha256": sha256_bytes(canonical_json_bytes(records)),
    }


def validate_inputs(
    fixture_path: Path,
    matrix_path: Path,
    stock_root: Path,
    output_path: Path,
) -> dict[str, Any]:
    fixture_path = fixture_path.expanduser().resolve(strict=True)
    matrix_path = matrix_path.expanduser().resolve(strict=True)
    try:
        fixture = load_fixture_config(fixture_path, REPOSITORY_ROOT)
    except ValueError as error:
        raise CensusError(str(error)) from error
    matrix = load_json_object(matrix_path, "matrix")
    if matrix.get("schema_version") != 1 or not isinstance(matrix.get("samples"), list):
        raise CensusError("matrix schema_version must be 1 with a samples array")

    sample_root = require_safe_input_root(
        resolve_configured_path(fixture.get("sample_root"), fixture_path, "sample_root"),
        "sample_root",
    )
    runtime_homes = require_safe_input_root(
        resolve_configured_path(
            fixture.get("runtime_homes"), fixture_path, "runtime_homes"
        ),
        "runtime_homes",
    )
    stock_root = require_safe_input_root(stock_root, "stock_root")
    if sample_root == runtime_homes:
        raise CensusError("sample_root and runtime_homes must be distinct")
    if not (stock_root / "shaders").is_dir():
        raise CensusError(f"stock_root must contain shaders/: {stock_root}")

    output_resolved = output_path.expanduser().resolve()
    for input_root, label in (
        (sample_root, "sample_root"),
        (runtime_homes, "runtime_homes"),
        (stock_root, "stock_root"),
    ):
        if is_relative_to(output_resolved, input_root):
            raise CensusError(f"output must not be inside {label}")
    if (
        output_resolved == REAL_WORKSHOP_ROOT
        or is_relative_to(output_resolved, REAL_WORKSHOP_ROOT)
    ):
        raise CensusError("output must not be inside the real Workshop tree")

    matrix_samples: dict[str, dict[str, Any]] = {}
    for entry in matrix["samples"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            raise CensusError("matrix samples must have string ids")
        sample_id = entry["id"]
        if not sample_id.isdigit() or sample_id in matrix_samples:
            raise CensusError(f"matrix sample id is invalid or duplicated: {sample_id}")
        matrix_samples[sample_id] = entry
    sample_ids = sorted(
        path.name
        for path in sample_root.iterdir()
        if path.is_dir() and path.name.isdigit()
    )
    runtime_ids = sorted(
        path.name
        for path in runtime_homes.iterdir()
        if path.is_dir() and path.name.isdigit()
    )
    expected_ids = sorted(matrix_samples)
    if sample_ids != expected_ids:
        raise CensusError("sample_root numeric directory set does not match matrix")
    if runtime_ids != expected_ids:
        raise CensusError("runtime_homes numeric directory set does not match matrix")

    report_path = resolve_configured_path(fixture.get("report"), fixture_path, "report")
    report = load_json_object(report_path, "fixture report")
    report_ids = sorted(
        str(item.get("id"))
        for item in report.get("samples", [])
        if isinstance(item, dict) and item.get("id") is not None
    )
    if report_ids != expected_ids:
        raise CensusError("fixture report sample set does not match matrix")

    samples = []
    fixture_directory = fixture_path.parent
    for sample_id in expected_ids:
        sample_directory = sample_root / sample_id
        project_path = sample_directory / "project.json"
        project = load_json_object(project_path, f"sample {sample_id} project")
        package = package_path(sample_directory, project)
        expected = matrix_samples[sample_id]
        project_sha = sha256_file(project_path)
        package_sha = sha256_file(package)
        if project_sha != expected.get("project_sha256"):
            raise CensusError(f"sample {sample_id} project SHA-256 does not match matrix")
        if package_sha != expected.get("package_sha256"):
            raise CensusError(f"sample {sample_id} package SHA-256 does not match matrix")
        cache_root = unique_cache_root(runtime_homes, sample_id)
        samples.append({
            "id": sample_id,
            "project_sha256": project_sha,
            "package_sha256": package_sha,
            "cache_root": portable_path(cache_root, fixture_directory),
            "package_relevant_tree": relevant_tree_manifest(cache_root),
            "loose_relevant_tree": relevant_tree_manifest(sample_directory),
        })

    return {
        "fixture_path": fixture_path,
        "fixture": fixture,
        "matrix_path": matrix_path,
        "matrix": matrix,
        "sample_root": sample_root,
        "runtime_homes": runtime_homes,
        "stock_root": stock_root,
        "report_path": report_path,
        "samples": samples,
    }


def resolve_commit(reference: str) -> str:
    if not reference.strip():
        raise CensusError("--baseline-ref must be non-empty")
    completed = subprocess.run(
        ["git", "rev-parse", "--verify", f"{reference}^{{commit}}"],
        cwd=REPOSITORY_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise CensusError(f"baseline ref is not a commit: {reference}")
    return completed.stdout.strip()


def archive_baseline(commit: str, destination: Path) -> None:
    completed = subprocess.run(
        ["git", "archive", "--format=tar", commit, *BASELINE_SOURCE_PATHS],
        cwd=REPOSITORY_ROOT,
        check=False,
        capture_output=True,
    )
    if completed.returncode != 0:
        raise CensusError(
            "git archive failed: "
            + completed.stderr.decode("utf-8", "replace").strip()
        )
    with tarfile.open(fileobj=io.BytesIO(completed.stdout), mode="r:") as archive:
        destination_resolved = destination.resolve()
        for member in archive.getmembers():
            target = (destination / member.name).resolve()
            if not is_relative_to(target, destination_resolved):
                raise CensusError("baseline archive contains an escaping path")
        archive.extractall(destination, filter="data")


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
    *,
    source_root: Path,
    source_paths: Sequence[str],
    harness_path: Path,
    binary_path: Path,
    module_cache: Path,
    current: bool,
) -> None:
    module_cache.mkdir(parents=True)
    command = [
        "xcrun",
        "--sdk",
        "macosx",
        "swiftc",
        "-parse-as-library",
    ]
    if current:
        command += ["-D", "R2_CURRENT"]
    command += [
        "-module-cache-path",
        str(module_cache),
        *(str(source_root / path) for path in source_paths),
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
        raise CensusError(
            ("current" if current else "baseline")
            + " Swift census compile failed:\n"
            + completed.stderr.strip()
        )


def run_harness(
    binary: Path,
    sample_root: Path,
    runtime_homes: Path,
    stock_root: Path,
) -> bytes:
    completed = subprocess.run(
        [str(binary), str(sample_root), str(runtime_homes), str(stock_root)],
        cwd=REPOSITORY_ROOT,
        check=False,
        capture_output=True,
    )
    if completed.returncode != 0:
        raise CensusError(
            "Swift census run failed:\n"
            + completed.stderr.decode("utf-8", "replace").strip()
        )
    return completed.stdout


def validate_corpus_output(
    payload: bytes,
    *,
    implementation: str,
    sample_ids: Sequence[str],
    forbidden_temporary_root: Path,
) -> dict[str, Any]:
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as error:
        raise CensusError(f"{implementation} output is not JSON: {error}") from error
    if not isinstance(value, dict) or value.get("implementation") != implementation:
        raise CensusError(f"{implementation} output implementation is invalid")
    samples = value.get("samples")
    contracts = value.get("contracts")
    passes = value.get("passes")
    if not all(isinstance(item, list) for item in (samples, contracts, passes)):
        raise CensusError(f"{implementation} output arrays are missing")
    if [sample.get("sampleID") for sample in samples] != list(sample_ids):
        raise CensusError(f"{implementation} sample set/order does not match matrix")

    pass_identities = [
        (
            item.get("sampleID"),
            item.get("materialPath"),
            item.get("materialPassIndex"),
        )
        for item in passes
    ]
    contract_identities = [
        (item.get("sampleID"), item.get("identity")) for item in contracts
    ]
    if len(pass_identities) != len(set(pass_identities)):
        raise CensusError(f"{implementation} pass identities are duplicated")
    if len(contract_identities) != len(set(contract_identities)):
        raise CensusError(f"{implementation} contract identities are duplicated")
    if sum(int(sample.get("materialPasses", -1)) for sample in samples) != len(passes):
        raise CensusError(f"{implementation} material pass conservation failed")
    if sum(int(sample.get("shaderReferences", -1)) for sample in samples) != len(contracts):
        raise CensusError(f"{implementation} contract conservation failed")
    valid_gpu = (
        {"removed"}
        if implementation == "r2-worktree"
        else {"accepted", "rejected", "not-applicable"}
    )
    if any(item.get("gpuAdmission") not in valid_gpu for item in passes):
        raise CensusError(f"{implementation} contains an invalid GPU status")
    expected_preparation = (
        {"accepted", "rejected", "not-applicable"}
        if implementation == "r2-worktree"
        else {"unavailable"}
    )
    if any(item.get("preparation") not in expected_preparation for item in passes):
        raise CensusError(f"{implementation} contains an invalid preparation status")

    temporary = str(forbidden_temporary_root.resolve())
    if temporary.encode("utf-8") in payload:
        raise CensusError(f"{implementation} output leaked a temporary path")
    forbidden_payload_keys = {
        "source",
        "shaderSource",
        "preparedSource",
        "materialJSON",
        "materialPayload",
    }
    stack: list[Any] = [value]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            forbidden = forbidden_payload_keys.intersection(current)
            if forbidden:
                raise CensusError(
                    f"{implementation} output contains source/material payload keys: "
                    + ", ".join(sorted(forbidden))
                )
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)
    return value


def status_counts(passes: Sequence[dict[str, Any]], field: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for item in passes:
        value = str(item.get(field))
        counts[value] = counts.get(value, 0) + 1
    return dict(sorted(counts.items()))


def failure_distribution(
    passes: Sequence[dict[str, Any]],
    *,
    prefix: str,
) -> dict[str, Any]:
    phase_code: dict[tuple[str, str], int] = {}
    exact: dict[tuple[str, str, tuple[str, ...]], int] = {}
    detail_tokens: dict[str, int] = {}
    status_field = "gpuAdmission" if prefix == "gpu" else "preparation"
    for item in passes:
        if item.get(status_field) != "rejected":
            continue
        phase = str(item.get(f"{prefix}FailurePhase") or "<none>")
        code = str(item.get(f"{prefix}FailureCode") or "<none>")
        details = tuple(str(value) for value in item.get(f"{prefix}FailureDetails", []))
        phase_code[(phase, code)] = phase_code.get((phase, code), 0) + 1
        exact[(phase, code, details)] = exact.get((phase, code, details), 0) + 1
        for detail in details:
            detail_tokens[detail] = detail_tokens.get(detail, 0) + 1
    return {
        "phase_code": [
            {"phase": phase, "code": code, "count": count}
            for (phase, code), count in sorted(phase_code.items())
        ],
        "exact": [
            {
                "phase": phase,
                "code": code,
                "details": list(details),
                "count": count,
            }
            for (phase, code, details), count in sorted(exact.items())
        ],
        "detail_tokens": [
            {"detail": detail, "count": count}
            for detail, count in sorted(detail_tokens.items())
        ],
    }


def pass_identity(item: dict[str, Any]) -> str:
    return (
        f"{item['sampleID']} / {item['materialPath']}"
        f"#{item['materialPassIndex']} / {item['shaderIdentity']}"
    )


def contract_key(item: dict[str, Any]) -> str:
    return f"{item['sampleID']} / {item['identity']}"


def raw_contract_projection(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "sampleID": item.get("sampleID"),
        "identity": item.get("identity"),
        "sourceKind": item.get("sourceKind"),
        "stages": item.get("stages"),
        "diagnostics": item.get("diagnostics"),
    }


def compare_outputs(
    baseline: dict[str, Any],
    current: dict[str, Any],
) -> dict[str, Any]:
    baseline_contracts = {contract_key(item): item for item in baseline["contracts"]}
    current_contracts = {contract_key(item): item for item in current["contracts"]}
    all_contracts = sorted(set(baseline_contracts) | set(current_contracts))
    raw_differences = []
    canonical_differences = []
    for key in all_contracts:
        left = baseline_contracts.get(key)
        right = current_contracts.get(key)
        if left is None or right is None or raw_contract_projection(left) != raw_contract_projection(right):
            raw_differences.append(key)
        if left is None or right is None or left.get("canonicalSHA256") != right.get("canonicalSHA256"):
            canonical_differences.append(key)

    baseline_accepted = {
        pass_identity(item)
        for item in baseline["passes"]
        if item.get("gpuAdmission") == "accepted"
    }
    current_accepted = {
        pass_identity(item)
        for item in current["passes"]
        if item.get("gpuAdmission") == "accepted"
    }
    return {
        "raw_projection_diff": {
            "count": len(raw_differences),
            "contracts": raw_differences,
        },
        "canonical_diff": {
            "count": len(canonical_differences),
            "contracts": canonical_differences,
        },
        "baseline_accepted": sorted(baseline_accepted),
        "current_accepted": sorted(current_accepted),
        "newly_accepted": sorted(current_accepted - baseline_accepted),
        "lost_accepted": sorted(baseline_accepted - current_accepted),
    }


def source_graph_summary(contracts: Sequence[dict[str, Any]]) -> dict[str, Any]:
    node_provenance: dict[str, int] = {}
    graph_categories: dict[str, int] = {}
    stage_root_provenance: dict[str, int] = {}
    diagnostics = 0
    graph_contract_count = 0
    for contract in contracts:
        if contract.get("sourceGraphDependencySHA256") is None:
            continue
        graph_contract_count += 1
        nodes = contract.get("sourceGraphNodes") or []
        provenances = sorted({str(node.get("provenance")) for node in nodes})
        category = "+".join(provenances) if provenances else "none"
        graph_categories[category] = graph_categories.get(category, 0) + 1
        for node in nodes:
            provenance = str(node.get("provenance"))
            node_provenance[provenance] = node_provenance.get(provenance, 0) + 1
        for provenance in contract.get("stageRootProvenances") or []:
            value = str(provenance)
            stage_root_provenance[value] = stage_root_provenance.get(value, 0) + 1
        diagnostics += len(contract.get("sourceGraphDiagnostics") or [])
    return {
        "contract_count": len(contracts),
        "graph_contract_count": graph_contract_count,
        "contracts_without_graph": len(contracts) - graph_contract_count,
        "diagnostic_count": diagnostics,
        "node_provenance_counts": dict(sorted(node_provenance.items())),
        "graph_category_counts": dict(sorted(graph_categories.items())),
        "stage_root_provenance_counts": dict(sorted(stage_root_provenance.items())),
    }


def build_report(
    *,
    args: argparse.Namespace,
    inputs: dict[str, Any],
    baseline_commit: str,
    baseline_manifest: dict[str, Any],
    current_manifest: dict[str, Any],
    baseline_bytes: bytes,
    current_first_bytes: bytes,
    current_second_bytes: bytes,
    baseline: dict[str, Any],
    current: dict[str, Any],
    swift_version: str,
    sdk_version: str,
) -> dict[str, Any]:
    comparison = compare_outputs(baseline, current)
    if comparison["newly_accepted"]:
        raise CensusError("removed authored-shader owner still accepts current passes")
    if any(item.get("gpuAdmission") != "removed" for item in current["passes"]):
        raise CensusError("current census did not retire the authored-shader GPU owner")
    if comparison["raw_projection_diff"]["count"]:
        raise CensusError("legacy raw shader projection changed")
    if comparison["canonical_diff"]["count"]:
        raise CensusError("legacy canonical shader projection changed")

    baseline_passes = baseline["passes"]
    current_passes = current["passes"]
    if len(baseline_passes) != len(current_passes):
        raise CensusError("baseline/current material pass counts differ")
    fixture_directory = inputs["fixture_path"].parent
    normalized_command = [
        "python3",
        "script/scene_shader_preparation_census.py",
        "--fixture",
        portable_path(inputs["fixture_path"], fixture_directory),
        "--matrix",
        portable_path(inputs["matrix_path"], fixture_directory),
        "--stock-root",
        portable_path(inputs["stock_root"], fixture_directory),
        "--baseline-ref",
        args.baseline_ref,
        "--output",
        "<output>",
    ]
    return {
        "schema_version": 1,
        "kind": "scene-shader-preparation-census",
        "generator": {
            "path": "script/scene_shader_preparation_census.py",
            "sha256": sha256_file(SCRIPT_PATH),
            "harness_sha256": sha256_bytes(HARNESS_SOURCE.encode("utf-8")),
            "canonical_json_contract": "sorted-keys-indented-utf8-v1",
            "command": normalized_command,
        },
        "toolchain": {
            "python_version": platform.python_version(),
            "swift_version": swift_version,
            "macos_sdk_version": sdk_version,
        },
        "inputs": {
            "fixture": {
                "path": portable_path(inputs["fixture_path"], fixture_directory),
                "sha256": sha256_file(inputs["fixture_path"]),
                "schema_version": inputs["fixture"]["schema_version"],
                "reference_report_path": portable_path(
                    inputs["report_path"], fixture_directory
                ),
                "reference_report_sha256": sha256_file(inputs["report_path"]),
            },
            "matrix": {
                "path": portable_path(inputs["matrix_path"], fixture_directory),
                "sha256": sha256_file(inputs["matrix_path"]),
                "schema_version": inputs["matrix"]["schema_version"],
                "name": inputs["matrix"].get("name"),
                "sample_count": len(inputs["samples"]),
            },
            "sample_root": portable_path(inputs["sample_root"], fixture_directory),
            "runtime_homes": portable_path(inputs["runtime_homes"], fixture_directory),
            "stock_root": {
                "path": portable_path(inputs["stock_root"], fixture_directory),
                "shader_tree": relevant_tree_manifest(inputs["stock_root"]),
            },
            "samples": inputs["samples"],
            "baseline_sources": {
                "implementation_kind": "git-archive",
                "requested_ref": args.baseline_ref,
                "commit": baseline_commit,
                **baseline_manifest,
            },
            "current_sources": {
                "implementation_kind": "worktree-snapshot",
                "base_commit": resolve_commit("HEAD"),
                **current_manifest,
            },
        },
        "method": {
            "corpus_unit": "material-pass",
            "material_glob": "materials/**/*.json",
            "resource_precedence": ["package", "loose", "stock"],
            "legacy_projection": "vertex-first-same-root-v1",
            "graph_projection": "synthetic-single-material-stage-v1",
            "baseline_gpu_admission": "SceneAuthoredShaderExecutionPlanner.compile",
            "current_gpu_admission": "removed; resolved-material runtime evidence is authoritative",
            "preparation": "resolve-material-then-SceneAuthoredShaderPreparation.prepareShaderStages-empty-readiness",
            "evidence_boundaries": [
                "planner-level only; no App, Metal runtime, benchmark, or visual execution",
                "real material and shader resources are evaluated in a synthetic single-stage graph",
                "current removed status proves old planner revocation, not resolved-material GPU admission",
                "preparation accepted is not GPU admission, execution, or visual support",
                "empty texture readiness intentionally classifies unresolved provider dependencies",
            ],
        },
        "determinism": {
            "baseline": {
                "runs": 1,
                "raw_sha256": [sha256_bytes(baseline_bytes)],
            },
            "current": {
                "runs": 2,
                "byte_equal": current_first_bytes == current_second_bytes,
                "raw_sha256": [
                    sha256_bytes(current_first_bytes),
                    sha256_bytes(current_second_bytes),
                ],
            },
        },
        "summary": {
            "sample_count": len(current["samples"]),
            "contract_count": len(current["contracts"]),
            "material_pass_count": len(current_passes),
            "gpu_admission": {
                "baseline": status_counts(baseline_passes, "gpuAdmission"),
                "current": status_counts(current_passes, "gpuAdmission"),
            },
            "preparation": status_counts(current_passes, "preparation"),
            "source_graph": source_graph_summary(current["contracts"]),
        },
        "comparison": comparison,
        "failure_distributions": {
            "baseline_gpu": failure_distribution(baseline_passes, prefix="gpu"),
            "current_gpu": failure_distribution(current_passes, prefix="gpu"),
            "current_preparation": failure_distribution(
                current_passes,
                prefix="preparation",
            ),
        },
        "results": {
            "baseline": baseline,
            "current": current,
        },
        "validation": {
            "failures": [],
            "conservation": {
                "baseline_passes": len(baseline_passes),
                "current_passes": len(current_passes),
                "baseline_contracts": len(baseline["contracts"]),
                "current_contracts": len(current["contracts"]),
                "current_repeat_byte_equal": current_first_bytes == current_second_bytes,
            },
        },
    }


def publish_atomic(path: Path, payload: bytes) -> str:
    path = path.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        existing = path.read_bytes()
        if existing == payload:
            return "unchanged"
        raise CensusError(f"refusing to overwrite different evidence: {path}")
    temporary_path: Path | None = None
    try:
        descriptor, name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=path.parent,
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
    parser.add_argument("--stock-root", type=Path, default=DEFAULT_STOCK_ROOT)
    parser.add_argument("--baseline-ref", required=True)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def run(args: argparse.Namespace) -> tuple[Path, dict[str, Any], str]:
    inputs = validate_inputs(
        args.fixture,
        args.matrix,
        args.stock_root,
        args.output,
    )
    baseline_commit = resolve_commit(args.baseline_ref)
    current_manifest = source_manifest(REPOSITORY_ROOT, CURRENT_SOURCE_PATHS)
    swift_version = tool_output(["xcrun", "--sdk", "macosx", "swiftc", "--version"])
    sdk_version = tool_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"])

    with tempfile.TemporaryDirectory(prefix="scene-shader-preparation-census-") as temporary:
        temporary_root = Path(temporary)
        baseline_root = temporary_root / "baseline"
        baseline_root.mkdir()
        archive_baseline(baseline_commit, baseline_root)
        baseline_manifest = source_manifest(baseline_root, BASELINE_SOURCE_PATHS)

        harness_path = temporary_root / "SceneShaderPreparationCensusHarness.swift"
        harness_path.write_text(HARNESS_SOURCE, encoding="utf-8")
        stock_copy = temporary_root / "stock"
        shutil.copytree(inputs["stock_root"] / "shaders", stock_copy / "shaders")
        baseline_binary = temporary_root / "baseline-census"
        current_binary = temporary_root / "current-census"
        compile_harness(
            source_root=baseline_root,
            source_paths=BASELINE_SOURCE_PATHS,
            harness_path=harness_path,
            binary_path=baseline_binary,
            module_cache=temporary_root / "module-cache-baseline",
            current=False,
        )
        compile_harness(
            source_root=REPOSITORY_ROOT,
            source_paths=CURRENT_SOURCE_PATHS,
            harness_path=harness_path,
            binary_path=current_binary,
            module_cache=temporary_root / "module-cache-current",
            current=True,
        )
        baseline_bytes = run_harness(
            baseline_binary,
            inputs["sample_root"],
            inputs["runtime_homes"],
            stock_copy,
        )
        current_first_bytes = run_harness(
            current_binary,
            inputs["sample_root"],
            inputs["runtime_homes"],
            stock_copy,
        )
        current_second_bytes = run_harness(
            current_binary,
            inputs["sample_root"],
            inputs["runtime_homes"],
            stock_copy,
        )
        if current_first_bytes != current_second_bytes:
            raise CensusError("current census repeated output is not byte-identical")
        sample_ids = [sample["id"] for sample in inputs["samples"]]
        baseline = validate_corpus_output(
            baseline_bytes,
            implementation="r1-baseline",
            sample_ids=sample_ids,
            forbidden_temporary_root=temporary_root,
        )
        current = validate_corpus_output(
            current_first_bytes,
            implementation="r2-worktree",
            sample_ids=sample_ids,
            forbidden_temporary_root=temporary_root,
        )
        report = build_report(
            args=args,
            inputs=inputs,
            baseline_commit=baseline_commit,
            baseline_manifest=baseline_manifest,
            current_manifest=current_manifest,
            baseline_bytes=baseline_bytes,
            current_first_bytes=current_first_bytes,
            current_second_bytes=current_second_bytes,
            baseline=baseline,
            current=current,
            swift_version=swift_version,
            sdk_version=sdk_version,
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
        print(f"Scene shader preparation census failed: {error}", file=sys.stderr)
        return 1
    summary = report["summary"]
    print(
        "Scene shader preparation census PASS: "
        f"{output} ({publication}) "
        f"samples={summary['sample_count']} "
        f"contracts={summary['contract_count']} "
        f"passes={summary['material_pass_count']} "
        f"sha256={sha256_file(output)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
