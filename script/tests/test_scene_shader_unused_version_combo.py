#!/usr/bin/env python3
"""Unused client-version metadata keeps identity without becoming a host fact."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(ROOT / "script"))
from scene_swift_source_sets import scene_swift_sources  # noqa: E402

SWIFT_SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Compilation/ShaderContract/SceneShaderSourceGraph.swift",
    SCENE / "Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    SCENE / "Compilation/ShaderContract/SceneShaderContract.swift",
    SCENE / "Resources/Textures/SceneTextureSampling.swift",
    *scene_swift_sources("authored_shader_preparation_implementation"),
]
HARNESS = r'''
import Foundation

private struct CheckFailure: Error, CustomStringConvertible { let description: String }
private func expect(_ condition: @autoclosure () -> Bool, _ label: String) throws {
    if !condition() { throw CheckFailure(description: label) }
}
private func node(_ path: String, _ source: String) -> SceneShaderSourceGraph.Node {
    .init(virtualPath: path, provenance: .loose, source: source,
          rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), byteCount: source.utf8.count)
}
private func graph(_ roots: [(String, String)], _ includes: [String: String] = [:]) -> SceneShaderSourceGraph {
    let nodes = roots.map { node($0.0, $0.1) } + includes.sorted { $0.key < $1.key }.map { node($0.key, $0.value) }
    var edges: [SceneShaderSourceGraph.Edge] = []
    for parent in nodes {
        let directory = parent.virtualPath.split(separator: "/").dropLast().joined(separator: "/")
        for include in SceneShaderContractSourceParser().parse(parent.source,
                stageRelativePath: parent.virtualPath).includes {
            let path = directory.isEmpty ? include.relativePath : directory + "/" + include.relativePath
            let child = nodes.first { $0.virtualPath == path }
            edges.append(.init(parentVirtualPath: parent.virtualPath, line: include.line,
                request: include.relativePath, candidates: child.map { [.init(virtualPath: path,
                    provenance: .loose, outcome: .resolved(rawSHA256: $0.rawSHA256))] } ?? [],
                outcome: child == nil ? .missing : .resolved(virtualPath: path)))
        }
    }
    return .init(roots: roots.enumerated().map {
        .init(label: $0.offset == 0 ? "vertex" : "fragment", virtualPath: $0.element.0)
    }, nodes: nodes, edges: edges, diagnostics: [], dependencySHA256: SceneShaderStableDigest.hash(nodes))
}
private func environment(_ bindings: [SceneShaderMacroBinding]) throws -> SceneShaderVariantEnvironment {
    try .init(stage: .fragment, combos: bindings)
}
private func binding(_ name: String, _ value: Int64) -> SceneShaderMacroBinding {
    .init(name: name, definition: .defined(.integer(value)))
}
private func preprocess(_ source: String, _ environment: SceneShaderVariantEnvironment,
                        includes: [String: String] = [:])
    -> Result<SceneShaderPreparedSource, SceneShaderPreprocessor.Failure> {
    SceneShaderPreprocessor().preprocess(rootRelativePath: "shaders/main.frag",
        graph: graph([("shaders/main.frag", source)], includes), environment: environment)
}
private func prepared(_ source: String, _ environment: SceneShaderVariantEnvironment,
                      includes: [String: String] = [:]) throws -> SceneShaderPreparedSource {
    try preprocess(source, environment, includes: includes).get()
}
private func denied(_ source: String, _ environment: SceneShaderVariantEnvironment,
                    includes: [String: String] = [:], hostRead: Bool = true) throws {
    switch preprocess(source, environment, includes: includes) {
    case .success: throw CheckFailure(description: "unverified host read admitted")
    case let .failure(failure):
        try expect(!failure.diagnostics.isEmpty, "missing rejection diagnostic")
        if hostRead {
            try expect(failure.diagnostics.contains { $0.code == .unresolvedEnvironmentDefine },
                "host read rejected by an unrelated diagnostic: \(failure.diagnostics)")
        }
    }
}
private func contract(_ fragment: String, includes: [String: String] = [:]) -> SceneShaderContract {
    let sources: [(SceneShaderContract.StageKind, String, String)] = [
        (.vertex, "shaders/main.vert", "void main(){gl_Position=vec4(0.0,0.0,0.0,1.0);}"),
        (.fragment, "shaders/main.frag", fragment)
    ]
    let stages: [SceneShaderContract.Stage] = sources.map { kind, path, source in
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
        return .init(kind: kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
            annotations: parsed.annotations, declarations: parsed.declarations)
    }
    return .init(identity: "own-unused-version", sourceKind: .authoredSource, stages: stages,
        diagnostics: [], canonicalSHA256: SceneShaderStableDigest.hash(stages),
        sourceGraph: graph(sources.map { ($0.1, $0.2) }, includes))
}
private func program(_ contract: SceneShaderContract, _ combos: [String: Int]) throws -> SceneShaderPreparedProgram {
    switch SceneAuthoredShaderPreparation.prepareShaderStages(contract: contract, combos: combos) {
    case let .accepted(value): return value
    case let .rejected(failure): throw CheckFailure(description: "program rejected: \(failure)")
    case .notApplicable: throw CheckFailure(description: "program not applicable")
    }
}

@main private struct Harness {
    static func main() throws {
        var checks: [String] = [], failures: [String] = []
        func check(_ name: String, _ body: () throws -> Void) {
            do { try body(); checks.append(name) }
            catch { failures.append(name + ": " + String(describing: error)) }
        }
        check("identity-without-macro-selection") {
            let a = try environment([binding("VERSION", 12), binding("SHADERVERSION", 24)])
            let b = try environment([binding("VERSION", 99), binding("SHADERVERSION", -3)])
            let empty = try environment([])
            try expect(a.combos.count == 2 && a.comboResolutions.count == 2, "metadata was dropped")
            try expect(a.variantSHA256 != b.variantSHA256 && a.variantSHA256 != empty.variantSHA256,
                       "version metadata lost environment identity")
            for name in ["VERSION", "SHADERVERSION"] {
                try expect(a.selectedMacroDefinitions()[name] == nil && a.initialMacroTable()[name] == nil,
                           "unverified host value became a macro fact")
            }
            let source = "float ownConstant = 0.25;"
            let first = try prepared(source, a), second = try prepared(source, b)
            try expect(first.source == second.source && first.source == source, "unused metadata rewrote source")
            try expect(first.preparedSHA256 != second.preparedSHA256, "prepared identity collapsed")
        }
        check("case-sensitive-ordinary-combos") {
            let env = try environment([binding("VERSION", 100), binding("version", 3), binding("Version", 5)])
            try expect(env.initialMacroTable()["version"] == .integer(3)
                && env.initialMacroTable()["Version"] == .integer(5), "ordinary case-sensitive combos lost")
            let result = try prepared("#if version == 3 && Version == 5\nCASE_OK\n#else\nBAD\n#endif", env)
            try expect(result.source == "CASE_OK", "ordinary lowercase selection changed")
        }
        check("inactive-branches-and-includes") {
            let env = try environment([binding("VERSION", 77), binding("SHADERVERSION", 88)])
            let source = """
            #if 0
            #if VERSION
            UNREACHED
            #endif
            #include "missing.inc"
            float hidden = SHADERVERSION;
            #endif
            #if 1
            ACTIVE
            #elif VERSION
            UNREACHED_ELIF
            #endif
            """
            let value = try prepared(source, env)
            try expect(value.source == "ACTIVE", "inactive host read changed active source")
            try expect(value.dependencies.count == 1, "inactive include was demanded")
        }
        check("comments-strings-and-include-path") {
            let env = try environment([binding("VERSION", 9), binding("SHADERVERSION", 10)])
            let source = """
            // VERSION SHADERVERSION
            /* VERSION */
            const char *ownLabel = "VERSION SHADERVERSION";
            #include "VERSION.inc"
            """
            let value = try prepared(source, env, includes: ["shaders/VERSION.inc": "INCLUDED_MARKER"])
            try expect(value.source.contains("\"VERSION SHADERVERSION\"")
                && value.source.contains("INCLUDED_MARKER"), "non-reading text or include name rejected")
        }
        for host in ["VERSION", "SHADERVERSION"] {
            let env = try environment([binding(host, 500)])
            let cases: [(String, String)] = [
                ("ordinary", "float ownValue = \(host);"),
                ("if", "#if \(host)\nREAD\n#endif"),
                ("ifdef", "#ifdef \(host)\nREAD\n#endif"),
                ("ifndef", "#ifndef \(host)\nREAD\n#endif"),
                ("elif", "#if 0\nDEAD\n#elif \(host)\nREAD\n#endif"),
                ("alias", "#define OWN_ALIAS \(host)\nfloat ownValue = OWN_ALIAS;"),
                ("function-macro", "#define OWN_READ(x) ((x)+\(host))\nfloat ownValue = OWN_READ(2);"),
                ("function-argument", "#define OWN_PASS(x) (x)\nfloat ownValue = OWN_PASS(\(host));"),
                ("source-define", "#define \(host) 1\nfloat ownValue=1;"),
                ("source-undef", "#undef \(host)\nfloat ownValue=1;")
            ]
            for (kind, source) in cases { check(host + "/" + kind) { try denied(source, env) } }
            check(host + "/active-include") {
                try denied("#include \"active.inc\"", env,
                    includes: ["shaders/active.inc": "float nested = \(host);"])
            }
            check(host + "/macro-include") { try denied("#include \(host)", env, hostRead: false) }
            check(host + "/undefined-still-unverified") {
                let undefined = try environment([.init(name: host, definition: .undefined)])
                try expect(undefined.selectedMacroDefinitions()[host] == nil, "undefined became a verified fact")
                try denied("#ifdef \(host)\nREAD\n#endif", undefined)
            }
            check(host + "/runtime-require") {
                let source = "uniform sampler2D g_Texture1; // {\"combo\":\"OWN_MASK\",\"require\":{\"\(host)\":1}}"
                let stage = contract(source).stages[1]
                switch SceneShaderVariantResolver.resolve(stage: .fragment, stages: [stage],
                    explicitCombos: [host: 3], textureReadiness: [1: true]) {
                case .success: throw CheckFailure(description: "unverified host runtime requirement admitted")
                case let .failure(failure): try expect(failure.code == .invalidEnvironment, "wrong runtime failure")
                }
            }
        }
        for name in ["HLSL", "GLSL", "PLATFORM_WINDOWS", "TEX0FORMAT", "THICKFORMAT"] {
            check("unchanged-environment-guard/" + name) {
                do {
                    _ = try environment([binding(name, 1)])
                    throw CheckFailure(description: "unverified non-version environment admitted")
                } catch let failure as SceneShaderVariantFailure {
                    try expect(failure.code == .unsupportedEnvironmentDefine, "wrong guard failure")
                }
            }
        }
        check("authored-environment-defines-still-rejected") {
            for name in ["VERSION", "SHADERVERSION", "ordinaryUserMacro"] {
                do {
                    _ = try SceneShaderVariantEnvironment(stage: .fragment,
                        environmentDefines: [binding(name, 7)])
                    throw CheckFailure(description: "author environment override admitted")
                } catch let failure as SceneShaderVariantFailure {
                    try expect(failure.code == .unsupportedEnvironmentDefine, "wrong override failure")
                }
            }
        }
        for (combo, field, include) in [("OWN_MODE", "ownTint", "own.inc"),
                                         ("RENAMED_MODE", "renamedTint", "renamed.inc")] {
            check("prepared-program-resolved-combos/" + combo) {
                let shader = contract("#include \"\(include)\"\nvoid main(){gl_FragColor=vec4(\(field));}",
                    includes: ["shaders/" + include: "#if \(combo) == 7\nfloat \(field)=0.25;\n#endif"])
                let inputs = ["VERSION": 450, "SHADERVERSION": 12, "version": 2, combo: 7]
                let a = try program(shader, inputs)
                var changed = inputs; changed["VERSION"] = -5; changed["SHADERVERSION"] = 999
                let b = try program(shader, changed)
                try expect(a.vertex.source == b.vertex.source && a.fragment.source == b.fragment.source,
                           "unused metadata changed prepared Program source")
                try expect(a.cacheKey != b.cacheKey, "prepared Program identity collapsed")
                let resolved = SceneAuthoredShaderPreparation.resolvedIntegerCombos(
                    contract: shader, prepared: a, combos: inputs)
                try expect(resolved == ["version": 2, combo: 7],
                    "resolved integer facts leaked client version or lost ordinary combo: \(String(describing: resolved))")
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["checks": checks, "failures": failures],
                                              options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneShaderUnusedVersionComboTests(unittest.TestCase):
    def test_real_preparation_and_host_fact_boundaries(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        evidence = os.environ.get("MWX_UNUSED_VERSION_TEST_EVIDENCE")
        output = Path(evidence) if evidence else None
        if output:
            output.mkdir(parents=True, exist_ok=True)
        inputs = [*SWIFT_SOURCES, Path(__file__).resolve(),
                  ROOT / "script/scene_swift_source_sets.json"]
        freeze = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        if output:
            (output / "input-freeze.json").write_text(json.dumps(freeze, indent=2) + "\n")
        started = time.monotonic()
        compiled = completed = None
        temporary_path = None
        try:
            with tempfile.TemporaryDirectory(prefix="mwx-unused-version-combo-") as temporary:
                work = Path(temporary)
                temporary_path = work
                harness, binary = work / "Harness.swift", work / "harness"
                harness.write_text(HARNESS, encoding="utf-8")
                environment = os.environ.copy()
                environment["CLANG_MODULE_CACHE_PATH"] = str(work / "clang-module-cache")
                environment["SWIFT_MODULECACHE_PATH"] = str(work / "swift-module-cache")
                environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(work / "shader-cache")
                compiled = subprocess.run([swiftc, "-warnings-as-errors", "-parse-as-library",
                    *(str(p) for p in SWIFT_SOURCES), str(harness), "-o", str(binary)],
                    cwd=ROOT, env=environment, capture_output=True, text=True, check=False)
                if output:
                    (output / "compile.log").write_text(compiled.stdout + compiled.stderr)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                completed = subprocess.run([str(binary)], cwd=ROOT, env=environment,
                    capture_output=True, text=True, check=False)
                if output:
                    (output / "harness.log").write_text(completed.stdout + completed.stderr)
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
                facts = json.loads(completed.stdout)
                self.assertEqual(facts["failures"], [], facts["failures"])
                self.assertEqual(len(facts["checks"]), 40, facts["checks"])
        finally:
            drift = [str(p.relative_to(ROOT)) for p in inputs
                     if hashlib.sha256(p.read_bytes()).hexdigest() != freeze[str(p.relative_to(ROOT))]]
            if output:
                receipt = {"elapsedSeconds": time.monotonic() - started,
                    "compileExitCode": compiled.returncode if compiled else None,
                    "harnessExitCode": completed.returncode if completed else None,
                    "inputCount": len(freeze), "inputDrift": drift,
                    "temporaryDirectoryRemoved": temporary_path is not None and not temporary_path.exists(),
                    "moduleCacheRemoved": temporary_path is not None and not temporary_path.exists()}
                (output / "execution.json").write_text(json.dumps(receipt, indent=2) + "\n")
            self.assertEqual(drift, [], drift)


if __name__ == "__main__":
    unittest.main()
