#!/usr/bin/env python3

"""Bounded LightingV1 zero-source module preparation and identity gates."""

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
TEST_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
sys.path.insert(0, str(TEST_ROOT))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402
from test_scene_resolved_material_program_derivation import (  # noqa: E402
    SUPPORT as PROGRAM_SUPPORT,
    SWIFT_SOURCES as PROGRAM_SOURCES,
)


SUPPORT = PROGRAM_SUPPORT + r'''

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
        case shaderModuleResolutionRejected = "shader-module-resolution-rejected"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded = "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
    }
}
'''


def unique_sources(paths: list[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            result.append(path)
    return result


SWIFT_SOURCES = unique_sources(
    [*PROGRAM_SOURCES, *scene_swift_sources("authored_shader_preparation_implementation")]
)


HARNESS = r'''
import Foundation
import Metal

private struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private struct HarnessOutput: Codable {
    let checks: [String]
    let fragmentPreparedSHA256: String
    let fragmentModuleDependencySHA256: String
    let programCacheKey: String
}

private func expect(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String
) throws {
    guard try condition() else { throw HarnessFailure(description: message) }
}

private func binding(
    _ name: String,
    _ definition: SceneShaderMacroDefinition
) -> SceneShaderMacroBinding {
    .init(name: name, definition: definition)
}

private func node(
    _ path: String,
    _ source: String
) -> SceneShaderSourceGraph.Node {
    .init(
        virtualPath: path,
        provenance: .loose,
        source: source,
        rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
        byteCount: source.utf8.count
    )
}

private func graph(
    roots: [String],
    sources: [String: String],
    edges: [SceneShaderSourceGraph.Edge] = []
) -> SceneShaderSourceGraph {
    let nodes = sources.keys.sorted().map { node($0, sources[$0]!) }
    return .init(
        roots: roots.enumerated().map {
            .init(label: "stage-\($0.offset)", virtualPath: $0.element)
        },
        nodes: nodes,
        edges: edges,
        diagnostics: [],
        dependencySHA256: SceneShaderSourceGraph.dependencySHA256(
            nodes: nodes,
            edges: edges
        )
    )
}

private func includeEdge(
    parent: String,
    line: Int,
    request: String,
    child: String
) -> SceneShaderSourceGraph.Edge {
    .init(
        parentVirtualPath: parent,
        line: line,
        request: request,
        candidates: [],
        outcome: .resolved(virtualPath: child)
    )
}

private func environment(
    stage: SceneShaderContract.StageKind,
    bindings: [SceneShaderMacroBinding] = []
) throws -> SceneShaderVariantEnvironment {
    try SceneShaderVariantEnvironment(stage: stage, combos: bindings)
}

private func preprocess(
    root: String = "shaders/main.frag",
    source: String,
    stage: SceneShaderContract.StageKind = .fragment,
    bindings: [SceneShaderMacroBinding] = [],
    extraSources: [String: String] = [:],
    edges: [SceneShaderSourceGraph.Edge] = []
) throws -> SceneShaderPreparedSource {
    var sources = extraSources
    sources[root] = source
    let result = SceneShaderPreprocessor().preprocess(
        rootRelativePath: root,
        graph: graph(roots: [root], sources: sources, edges: edges),
        environment: try environment(stage: stage, bindings: bindings)
    )
    switch result {
    case let .success(prepared): return prepared
    case let .failure(failure):
        throw HarnessFailure(description: "Unexpected preprocessing failure: \(failure)")
    }
}

private func diagnostic(
    source: String,
    bindings: [SceneShaderMacroBinding] = []
) throws -> SceneShaderPreprocessor.DiagnosticCode {
    let root = "shaders/main.frag"
    let result = SceneShaderPreprocessor().preprocess(
        rootRelativePath: root,
        graph: graph(roots: [root], sources: [root: source]),
        environment: try environment(stage: .fragment, bindings: bindings)
    )
    switch result {
    case .success:
        throw HarnessFailure(description: "Expected preprocessing rejection.")
    case let .failure(failure):
        guard failure.diagnostics.count == 1,
              let code = failure.diagnostics.first?.code else {
            throw HarnessFailure(description: "Expected one typed diagnostic.")
        }
        return code
    }
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
        rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
        includes: parsed.includes,
        annotations: parsed.annotations,
        declarations: parsed.declarations
    )
}

private func contract(
    fragment: String,
    extraSources: [String: String] = [:],
    edges: [SceneShaderSourceGraph.Edge] = []
) -> SceneShaderContract {
    let vertexPath = "shaders/main.vert"
    let fragmentPath = "shaders/main.frag"
    let vertex = "void main() { gl_Position = vec4(0.0); }"
    var sources = extraSources
    sources[vertexPath] = vertex
    sources[fragmentPath] = fragment
    return .init(
        identity: "fixture/module",
        sourceKind: .authoredSource,
        stages: [
            stage(.vertex, path: vertexPath, source: vertex),
            stage(.fragment, path: fragmentPath, source: fragment),
        ],
        diagnostics: [],
        canonicalSHA256: "fixture-module-canonical",
        sourceGraph: graph(
            roots: [vertexPath, fragmentPath],
            sources: sources,
            edges: edges
        )
    )
}

private func prepareProgram(
    fragment: String,
    combos: [String: Int] = [:],
    extraSources: [String: String] = [:],
    edges: [SceneShaderSourceGraph.Edge] = []
) throws -> SceneShaderPreparedProgram {
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: contract(
            fragment: fragment,
            extraSources: extraSources,
            edges: edges
        ),
        combos: combos
    ) {
    case let .accepted(program): return program
    case let .rejected(failure):
        throw HarnessFailure(description: "Unexpected preparation failure: \(failure)")
    case .notApplicable:
        throw HarnessFailure(description: "Unexpected non-applicable preparation.")
    }
}

private func outerFailure(
    fragment: String,
    combos: [String: Int] = [:]
) throws -> SceneAuthoredShaderPreparationFailure {
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: contract(fragment: fragment),
        combos: combos
    ) {
    case .accepted:
        throw HarnessFailure(description: "Rejected module produced a prepared Program.")
    case let .rejected(failure): return failure
    case .notApplicable:
        throw HarnessFailure(description: "Module rejection became non-applicable.")
    }
}

private func expectedPreparedDigest(
    _ source: SceneShaderPreparedSource
) -> String {
    SceneShaderStableDigest.hash(SceneShaderPreprocessor.PreparedDigestPayload(
        frontendSchemaVersion: source.frontendSchemaVersion,
        sourceDialect: source.sourceDialect,
        backend: source.backend,
        stage: source.stage,
        rootRelativePath: source.rootRelativePath,
        source: source.source,
        sourceMap: source.sourceMap,
        activeAnnotations: source.activeAnnotations,
        activeDeclarations: source.activeDeclarations,
        dependencySHA256: source.dependencySHA256,
        moduleDependencies: source.moduleDependencies,
        moduleDependencySHA256: source.moduleDependencySHA256,
        variantSHA256: source.variantSHA256
    ))
}

@main
private enum HarnessMain {
    static func main() throws {
        var checks: [String] = []
        func checked(_ name: String, _ body: () throws -> Void) rethrows {
            try body()
            checks.append(name)
        }

        let zero = binding("LIGHTING", .defined(.integer(0)))
        let one = binding("LIGHTING", .defined(.integer(1)))

        try checked("typed-grammar") {
            guard case .require("LightingV1") = SceneShaderDirective.parse(
                "#require LightingV1"
            ) else { throw HarnessFailure(description: "Exact require was not typed.") }
            guard case .malformedRequire = SceneShaderDirective.parse("#require") else {
                throw HarnessFailure(description: "Missing operand was not typed syntax failure.")
            }
            guard case .malformedRequire = SceneShaderDirective.parse(
                "#require LightingV1 extra"
            ) else { throw HarnessFailure(description: "Extra token was not typed syntax failure.") }
            guard case .malformedRequire = SceneShaderDirective.parse(
                "#require 1LightingV1"
            ) else { throw HarnessFailure(description: "Invalid identifier was not typed syntax failure.") }
        }

        let direct = try preprocess(
            source: "#require LightingV1\nvoid main() {}",
            bindings: [zero]
        )
        try checked("active-zero-provenance") {
            try expect(direct.moduleDependencies.count == 1, "Expected one module resolution.")
            let dependency = direct.moduleDependencies[0]
            try expect(dependency.module == .lightingV1, "Wrong module identity.")
            try expect(dependency.stage == .fragment, "Wrong module stage.")
            try expect(dependency.sourcePath == "shaders/main.frag", "Wrong source path.")
            try expect(dependency.sourceLine == 1, "Wrong source line.")
            try expect(dependency.directiveOrdinal == 1, "Wrong directive ordinal.")
            try expect(dependency.outcome == .zeroSourceContribution, "Wrong outcome.")
            try expect(!dependency.macroEnvironmentSHA256.isEmpty, "Missing macro digest.")
            try expect(direct.source == "void main() {}", "Module emitted source or a stub.")
            try expect(direct.sourceMap.map(\.sourceLine) == [2], "Module fabricated source-map lines.")
            try expect(direct.dependencies.count == 1, "File dependency schema changed.")
            try expect(direct.preparedSHA256 == expectedPreparedDigest(direct), "Prepared digest omitted module provenance.")
        }

        try checked("typed-failures") {
            try expect(try diagnostic(source: "#require") == .moduleDirectiveSyntax, "Missing syntax code.")
            try expect(try diagnostic(source: "#require LightingV1 extra") == .moduleDirectiveSyntax, "Extra syntax code.")
            try expect(try diagnostic(source: "#require 1LightingV1") == .moduleDirectiveSyntax, "Invalid identifier syntax code.")
            try expect(try diagnostic(source: "#require UnknownV1") == .moduleUnknown, "Unknown module code.")
            try expect(try diagnostic(source: "#require lightingv1") == .moduleCaseMismatch, "Case mismatch code.")
            try expect(try diagnostic(source: "#require LightingV1", bindings: [one]) == .moduleLightingNonzero, "Nonzero code.")
            try expect(try diagnostic(source: "#require LightingV1") == .moduleLightingMacroMissing, "Missing macro code.")
            try expect(try diagnostic(source: "#define LIGHTING 0.0\n#require LightingV1") == .moduleLightingMacroNoninteger, "Noninteger code.")
            try expect(try diagnostic(source: "#define LIGHTING(x) (x)\n#require LightingV1") == .moduleLightingMacroNoninteger, "Function macro code.")
        }

        try checked("inactive-syntax-only") {
            let inactive = try preprocess(
                source: "#if 0\n#require UnknownV1\n#endif\nvoid main() {}"
            )
            try expect(inactive.moduleDependencies.isEmpty, "Inactive require resolved a module.")
            try expect(
                try diagnostic(source: "#if 0\n#require LightingV1 extra\n#endif")
                    == .moduleDirectiveSyntax,
                "Inactive malformed require did not reject syntax."
            )
        }

        try checked("directive-position-macro-state") {
            let before = try preprocess(
                source: "#define LIGHTING 0\n#require LightingV1\nvoid main() {}"
            )
            try expect(before.moduleDependencies.count == 1, "Before-define did not resolve.")
            try expect(
                try diagnostic(source: "#require LightingV1\n#define LIGHTING 0")
                    == .moduleLightingMacroMissing,
                "After-define changed directive-position state."
            )
            try expect(
                try diagnostic(
                    source: "#define LIGHTING 1\n#require LightingV1",
                    bindings: [zero]
                ) == .conflictingMacro,
                "Existing conflict boundary moved into module history."
            )
        }

        try checked("order-independent-macro-digest") {
            let sourceA = """
            #define ZED 2
            #define ALPHA 3
            #define FOO(x) (x)
            #define BAR(y) (y)
            #define LIGHTING 0
            #require LightingV1
            void main() {}
            """
            let sourceB = """
            #define ALPHA 3
            #define ZED 2
            #define BAR(y) (y)
            #define FOO(x) (x)
            #define LIGHTING 0
            #require LightingV1
            void main() {}
            """
            let sourceChanged = """
            #define ALPHA 4
            #define ZED 2
            #define BAR(y) (y)
            #define FOO(x) (x)
            #define LIGHTING 0
            #require LightingV1
            void main() {}
            """
            let digestA = try preprocess(source: sourceA)
                .moduleDependencies[0].macroEnvironmentSHA256
            let digestB = try preprocess(source: sourceB)
                .moduleDependencies[0].macroEnvironmentSHA256
            let changedDigest = try preprocess(source: sourceChanged)
                .moduleDependencies[0].macroEnvironmentSHA256
            try expect(digestA == digestB, "Macro digest depended on dictionary/source order.")
            try expect(digestA != changedDigest, "Macro digest ignored a visible value change.")
        }

        try checked("include-identity-and-ordinal") {
            let root = """
            #define LIGHTING 0
            #if 0
            #require IgnoredV1
            #endif
            #include "lighting.inc"
            void main() {}
            """
            let child = "#require LightingV1\nfloat includedValue = 1.0;"
            let prepared = try preprocess(
                source: root,
                extraSources: ["shaders/lighting.inc": child],
                edges: [includeEdge(
                    parent: "shaders/main.frag",
                    line: 5,
                    request: "lighting.inc",
                    child: "shaders/lighting.inc"
                )]
            )
            let dependency = prepared.moduleDependencies[0]
            try expect(dependency.sourcePath == "shaders/lighting.inc", "Include identity lost.")
            try expect(dependency.sourceLine == 1, "Include line lost.")
            try expect(dependency.directiveOrdinal == 2, "Inactive authored ordinal was lost.")
            try expect(prepared.dependencies.count == 2, "Real include dependency was not preserved.")
        }

        try checked("stage-isolation") {
            let vertex = try preprocess(
                root: "shaders/main.vert",
                source: "#require LightingV1\nvoid main() {}",
                stage: .vertex,
                bindings: [zero]
            )
            try expect(vertex.moduleDependencies[0].stage == .vertex, "Vertex stage leaked.")
            try expect(vertex.moduleDependencies[0].directiveOrdinal == 1, "Vertex ordinal leaked.")
            try expect(direct.moduleDependencies[0].stage == .fragment, "Fragment stage leaked.")
            try expect(direct.moduleDependencies[0].directiveOrdinal == 1, "Fragment ordinal leaked.")
        }

        let defaultSource = """
        // [COMBO] {"combo":"LIGHTING","default":0,"options":[0,1]}
        #require LightingV1
        void main() { gl_FragColor = vec4(1.0); }
        """
        let program = try prepareProgram(fragment: defaultSource)
        let comboProgram = try prepareProgram(
            fragment: "#require LightingV1\nvoid main() { gl_FragColor = vec4(1.0); }",
            combos: ["LIGHTING": 0]
        )
        try checked("authored-default-zero-and-cache") {
            try expect(program.vertex.moduleDependencies.isEmpty, "Vertex gained fragment module.")
            try expect(program.fragment.moduleDependencies.count == 1, "Default zero did not resolve.")
            try expect(comboProgram.fragment.moduleDependencies.count == 1, "Combo zero did not resolve.")
            try expect(!program.cacheKey.isEmpty, "Prepared Program cache key is empty.")
            let exact = SceneResolvedMaterialProgramIdentity.prepared(program)
            try expect(
                exact.fragmentModuleDependency == program.fragment.moduleDependencySHA256,
                "Program exact identity omitted fragment module dependency."
            )
            try expect(
                exact.vertexModuleDependency == program.vertex.moduleDependencySHA256,
                "Program exact identity omitted empty vertex module dependency."
            )
            try expect(exact.cacheKey == program.cacheKey, "Program cache key identity diverged.")
        }

        try checked("outer-module-rejections") {
            let cases: [(String, [String: Int], SceneShaderPreprocessor.DiagnosticCode)] = [
                ("#require", [:], .moduleDirectiveSyntax),
                ("#require LightingV1 extra", [:], .moduleDirectiveSyntax),
                ("#require 1LightingV1", [:], .moduleDirectiveSyntax),
                ("#require UnknownV1", [:], .moduleUnknown),
                ("#require lightingv1", [:], .moduleCaseMismatch),
                ("#require LightingV1", ["LIGHTING": 1], .moduleLightingNonzero),
                ("#require LightingV1", [:], .moduleLightingMacroMissing),
                ("#define LIGHTING 0.0\n#require LightingV1", [:], .moduleLightingMacroNoninteger),
                ("#define LIGHTING(x) (x)\n#require LightingV1", [:], .moduleLightingMacroNoninteger),
            ]
            for (source, combos, expected) in cases {
                let failure = try outerFailure(fragment: source, combos: combos)
                try expect(
                    failure.code == .shaderModuleResolutionRejected,
                    "Module rejection folded into a generic directive failure."
                )
                try expect(failure.details.first == expected.rawValue, "Typed outer detail was lost.")
            }
        }

        let movedSource = """
        // [COMBO] {"combo":"LIGHTING","default":0,"options":[0,1]}

        #require LightingV1
        void main() { gl_FragColor = vec4(1.0); }
        """
        let movedProgram = try prepareProgram(fragment: movedSource)
        try checked("prepared-cache-exact-identity-propagation") {
            try expect(
                program.fragment.moduleDependencies[0].sourceLine == 2,
                "Baseline authored source line is wrong."
            )
            try expect(
                movedProgram.fragment.moduleDependencies[0].sourceLine == 3,
                "Moved authored source line is wrong."
            )
            try expect(
                program.fragment.moduleDependencySHA256
                    != movedProgram.fragment.moduleDependencySHA256,
                "Module provenance did not enter its typed digest."
            )
            try expect(
                program.fragment.preparedSHA256 != movedProgram.fragment.preparedSHA256,
                "Module provenance did not enter prepared identity."
            )
            try expect(program.cacheKey != movedProgram.cacheKey, "Prepared cache identity collided.")
            let exactA = SceneResolvedMaterialProgramIdentity.prepared(program)
            let exactB = SceneResolvedMaterialProgramIdentity.prepared(movedProgram)
            try expect(exactA != exactB, "Program exact identity collided.")
        }

        let output = HarnessOutput(
            checks: checks,
            fragmentPreparedSHA256: program.fragment.preparedSHA256,
            fragmentModuleDependencySHA256: program.fragment.moduleDependencySHA256,
            programCacheKey: program.cacheKey
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneShaderModuleResolutionTests(unittest.TestCase):
    def test_lighting_v1_zero_source_resolution_and_identity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-shader-module-resolution-") as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "shader-module-resolution-test"
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
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertEqual(len(result["checks"]), 11, result)
        self.assertEqual(len(result["fragmentPreparedSHA256"]), 64, result)
        self.assertEqual(len(result["fragmentModuleDependencySHA256"]), 64, result)
        self.assertEqual(len(result["programCacheKey"]), 64, result)


if __name__ == "__main__":
    unittest.main()
