#!/usr/bin/env python3

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
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = scene_swift_sources(
    "graph_condition_schema_evidence_implementation"
)

HARNESS = r'''
import Foundation

struct SceneRenderDescriptor {
    struct PassDescriptor {
        let passIndex: Int
        let combos: [String: Int]
    }

    struct EffectDescriptor {
        let id: String
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let shaderPath: String?
        let combos: [String: Int]
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

private struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private struct HarnessOutput: Codable {
    let checks: [String]
    let failure: String?
}

private typealias Graph = SceneAuthoredEffectRenderPlan

private let layerID = 71
private let effectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "condition-instance"
)

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw HarnessFailure(description: message) }
}

private func stage(
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
        rawSHA256: "stage-\(path)",
        includes: parsed.includes,
        annotations: parsed.annotations,
        declarations: parsed.declarations
    )
}

private func contract(
    identity: String,
    fragmentSource: String,
    malformed: Bool = false,
    duplicateVertexStage: Bool = false
) -> SceneShaderContract {
    let vertexPath = "\(identity).vert"
    let fragmentPath = "\(identity).frag"
    let stages = [
        stage(.vertex, path: vertexPath, source: "void main() {}"),
        stage(.fragment, path: fragmentPath, source: fragmentSource),
    ] + (duplicateVertexStage
        ? [stage(.vertex, path: "\(identity)-duplicate.vert", source: "void main() {}")]
        : [])
    let nodes = stages.map { value in
        SceneShaderSourceGraph.Node(
            virtualPath: value.relativePath,
            provenance: .loose,
            source: value.source,
            rawSHA256: value.rawSHA256,
            byteCount: value.source.utf8.count
        )
    }
    let graph = SceneShaderSourceGraph(
        roots: [
            .init(label: "vertex", virtualPath: vertexPath),
            .init(label: "fragment", virtualPath: fragmentPath),
        ],
        nodes: nodes,
        edges: [],
        diagnostics: [],
        dependencySHA256: "dependency-\(identity)"
    )
    let diagnostics: [SceneShaderContract.Diagnostic] = malformed
        ? [.init(
            code: .malformedAnnotation,
            message: "fixture malformed annotation",
            relativePath: fragmentPath,
            line: 1
        )]
        : []
    return .init(
        identity: identity,
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: diagnostics,
        canonicalSHA256: "contract-\(identity)",
        sourceGraph: graph
    )
}

private func graph(materialCount: Int) -> Graph {
    let source = Graph.TextureIdentity(
        kind: .layerSource,
        layerID: layerID,
        effect: nil,
        name: nil
    )
    let output = Graph.TextureIdentity(
        kind: .effectOutput,
        layerID: layerID,
        effect: effectKey,
        name: nil
    )
    let nodes = (0 ..< materialCount).map { index in
        Graph.Node(
            nodeIndex: index,
            effect: effectKey,
            definitionPassIndex: index,
            materialOrdinal: index,
            instancePassIndex: index,
            kind: .material,
            materialPath: "materials/\(index).json",
            materialPassID: "material-\(index)",
            target: output,
            bindings: [],
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
            definitionPath: "effects/condition/effect.json",
            input: source,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: [],
        nodes: nodes,
        finalOutput: output,
        blockers: []
    )
}

private enum IdentityMutation {
    case none
    case materialPath
    case shaderPath
}

private func compile(
    _ sources: [String],
    malformed: Set<Int> = [],
    duplicateVertexStage: Set<Int> = [],
    identityMutation: IdentityMutation = .none,
    contractMultiplicity: Int = 1
) -> Set<String> {
    let plan = graph(materialCount: sources.count)
    let materials = sources.indices.map { index in
        SceneRenderDescriptor.MaterialPassDescriptor(
            id: "material-\(index)",
            materialPath: identityMutation == .materialPath && index == 0
                ? "materials/wrong.json" : "materials/\(index).json",
            shaderPath: identityMutation == .shaderPath && index == 0
                ? "shader-wrong" : "shader-\(index)",
            combos: [:]
        )
    }
    let descriptor = SceneRenderDescriptor(
        layers: [.init(
            id: layerID,
            effects: [.init(
                id: effectKey.descriptorID,
                passes: sources.indices.map { .init(passIndex: $0, combos: [:]) }
            )]
        )],
        materialPasses: materials
    )
    let baseContracts = sources.indices.map { index in
        contract(
            identity: "shader-\(index)",
            fragmentSource: sources[index],
            malformed: malformed.contains(index),
            duplicateVertexStage: duplicateVertexStage.contains(index)
        )
    }
    let contracts = contractMultiplicity == 0
        ? []
        : Array(repeating: baseContracts, count: contractMultiplicity).flatMap { $0 }
    return SceneGraphConditionSchemaEvidenceCompiler.compile(
        descriptor: descriptor,
        authoredPlans: [plan],
        shaderContracts: contracts
    )[effectKey]?.keysProvenZeroWhenMissing ?? []
}

private func runFixtures() throws -> [String] {
    let stableZero = #"// [COMBO] {"combo":"LIGHTING","default":0,"options":[0,1]}"#
    try expect(
        compile([stableZero]) == ["LIGHTING"],
        "Stable zero authored combo did not produce evidence."
    )
    let stableZeroThenRequirement = """
    \(stableZero)
    #require LightingV1
    """
    try expect(
        compile([stableZeroThenRequirement]) == ["LIGHTING"],
        "A later independent requirement discarded top-level zero evidence."
    )

    let zeroWithoutOptions = #"// [COMBO] {"combo":"NO_OPTIONS","default":0}"#
    try expect(
        compile([zeroWithoutOptions]) == ["NO_OPTIONS"],
        "A zero default without options did not produce evidence."
    )
    let zeroExcludedByOptions =
        #"// [COMBO] {"combo":"NO_ZERO_OPTION","default":0,"options":[1,2]}"#
    try expect(
        compile([zeroExcludedByOptions]).isEmpty,
        "A schema whose options exclude zero produced evidence."
    )

    let nonzero = #"// [COMBO] {"combo":"LIGHTING","default":1,"options":[0,1]}"#
    try expect(compile([nonzero]).isEmpty, "Nonzero default produced zero evidence.")

    let readiness = #"uniform sampler2D g_Texture0; // {"combo":"LIGHTING","default":"mask"}"#
    try expect(compile([readiness]).isEmpty, "Readiness combo produced zero evidence.")

    let textureFormat = #"uniform sampler2D g_Texture0; // {"formatcombo":true}"#
    try expect(compile([textureFormat]).isEmpty, "Texture format combo produced zero evidence.")

    let disabled = #"// [COMBO_DISABLED] {"combo":"LIGHTING","default":0,"options":[0,1]}"#
    try expect(compile([disabled]).isEmpty, "Disabled combo produced zero evidence.")
    try expect(
        compile([stableZero], malformed: [0]).isEmpty,
        "Malformed contract produced zero evidence."
    )

    let ambiguous = """
    \(stableZeroThenRequirement)
    #if CONDITIONAL
    // [COMBO] {"combo":"LIGHTING","default":1,"options":[0,1]}
    #endif
    """
    try expect(
        compile([ambiguous]).isEmpty,
        "Conditional conflicting default escaped the ambiguity audit."
    )

    let conditionalReadiness = """
    \(stableZeroThenRequirement)
    #if CONDITIONAL
    uniform sampler2D g_Texture0; // {"combo":"LIGHTING","default":"mask"}
    #endif
    """
    try expect(
        compile([conditionalReadiness]).isEmpty,
        "Conditional readiness schema did not invalidate the same key."
    )

    let stableFormat = #"// [COMBO] {"combo":"TEX0FORMAT","default":0}"#
    let conditionalFormat = """
    \(stableFormat)
    #require LightingV1
    #if CONDITIONAL
    uniform sampler2D g_Texture0; // {"formatcombo":true}
    #endif
    """
    try expect(
        compile([conditionalFormat]).isEmpty,
        "Conditional texture-format schema did not invalidate the same key."
    )

    let conditionalDisabled = """
    \(stableZeroThenRequirement)
    #if CONDITIONAL
    // [COMBO_DISABLED] {"combo":"LIGHTING","default":0,"options":[0,1]}
    #endif
    """
    try expect(
        compile([conditionalDisabled]).isEmpty,
        "Conditional disabled schema did not invalidate the same key."
    )

    let branchOnly = """
    #if CONDITIONAL
    // [COMBO] {"combo":"BRANCH_ONLY","default":0}
    #endif
    """
    try expect(
        compile([branchOnly]).isEmpty,
        "A branch-only key was invented as unconditional evidence."
    )

    let overBudget = (0 ... 8).map { index in
        """
        #if C\(index)
        // [COMBO] {"combo":"C\(index)","default":0}
        #endif
        """
    }.joined(separator: "\n")
    try expect(
        compile([overBudget]).isEmpty,
        "More than eight ambiguity candidates did not fail closed."
    )

    try expect(
        compile([stableZero], contractMultiplicity: 0).isEmpty,
        "Missing shader contract produced evidence."
    )
    try expect(
        compile([stableZero], contractMultiplicity: 2).isEmpty,
        "Duplicate shader contract identity produced evidence."
    )
    try expect(
        compile([stableZero], duplicateVertexStage: [0]).isEmpty,
        "Duplicate stage kind produced evidence."
    )

    try expect(
        compile([stableZero, stableZero]) == ["LIGHTING"],
        "Two stable material contracts did not retain shared zero evidence."
    )
    try expect(
        compile([stableZero, nonzero]).isEmpty,
        "Unsafe material declaration did not invalidate effect-wide evidence."
    )

    try expect(
        compile([stableZero], identityMutation: .materialPath).isEmpty,
        "Material path mismatch produced evidence."
    )
    try expect(
        compile([stableZero], identityMutation: .shaderPath).isEmpty,
        "Shader identity mismatch produced evidence."
    )

    return [
        "stable_zero", "stable_zero_then_requirement", "zero_without_options",
        "zero_excluded_by_options", "nonzero", "readiness", "texture_format",
        "disabled", "malformed", "conditional_ambiguity",
        "conditional_readiness", "conditional_format", "conditional_disabled",
        "branch_only", "ambiguity_budget",
        "missing_contract", "duplicate_contract", "duplicate_stage",
        "multi_material_agreement", "unsafe_material_invalidation",
        "material_path_identity", "shader_identity",
    ]
}

@main
private enum Harness {
    static func main() {
        let output: HarnessOutput
        do {
            output = .init(checks: try runFixtures(), failure: nil)
        } catch {
            output = .init(checks: [], failure: String(describing: error))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(output) else { return }
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneGraphConditionSchemaEvidenceTests(unittest.TestCase):
    def test_only_stable_zero_authored_combo_defaults_become_evidence(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory() as temporary_directory:
            build_root = Path(temporary_directory)
            harness = build_root / "SceneGraphConditionSchemaEvidenceHarness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = build_root / "scene-graph-condition-schema-evidence-harness"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(
                build_root / "clang-module-cache"
            )
            environment["SWIFT_MODULECACHE_PATH"] = str(
                build_root / "swift-module-cache"
            )
            compiled = subprocess.run(
                [
                    swiftc,
                    "-warnings-as-errors",
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        output = json.loads(completed.stdout)
        self.assertIsNone(output.get("failure"), output.get("failure"))
        self.assertEqual(len(output["checks"]), 22)


if __name__ == "__main__":
    unittest.main()
