#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPO_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderDirective.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderMacroExpansion.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment+HostFacts.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderPreprocessor+Directive.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderPreprocessor.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+TextureFormat.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+Schema.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+SchemaSeed.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+DisabledCombo.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
]

HARNESS = r'''
import Foundation

private struct HarnessOutput: Codable {
    let checks: [String]
    let failure: String?
}

private struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw HarnessFailure(description: message) }
}

private func fixtureURL(_ root: URL, _ relativePath: String) -> URL {
    relativePath.split(separator: "/").reduce(root) {
        $0.appendingPathComponent(String($1))
    }
}

private func createRoot(_ root: URL) throws {
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
}

private func write(_ source: String, to root: URL, _ relativePath: String) throws {
    let url = fixtureURL(root, relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try source.write(to: url, atomically: true, encoding: .utf8)
}

private func resourceView(
    loose: URL,
    package: URL? = nil,
    stock: URL? = nil
) -> SceneResourceView {
    SceneResourceView(
        projectRootURL: loose,
        packageRootURL: package,
        stockAssetsRootURL: stock
    )
}

private func graph(
    _ rootPath: String,
    view: SceneResourceView,
    limits: SceneShaderSourceGraphBuilder.Limits = .init()
) -> SceneShaderSourceGraph {
    SceneShaderSourceGraphBuilder(limits: limits).build(
        roots: [.init(label: "fragment", virtualPath: rootPath)],
        resourceView: view
    )
}

private func environment(
    _ bindings: [SceneShaderMacroBinding] = []
) throws -> SceneShaderVariantEnvironment {
    try SceneShaderVariantEnvironment(
        stage: .fragment,
        combos: bindings
    )
}

private func prepared(
    rootPath: String,
    graph: SceneShaderSourceGraph,
    environment: SceneShaderVariantEnvironment,
    limits: SceneShaderPreprocessor.Limits = .default
) throws -> SceneShaderPreparedSource {
    switch SceneShaderPreprocessor().preprocess(
        rootRelativePath: rootPath,
        graph: graph,
        environment: environment,
        limits: limits
    ) {
    case let .success(source):
        return source
    case let .failure(failure):
        throw HarnessFailure(
            description: "Expected prepared source, got diagnostics: \(failure.diagnostics)"
        )
    }
}

private func expectFailure(
    rootPath: String,
    graph: SceneShaderSourceGraph,
    environment: SceneShaderVariantEnvironment,
    code: SceneShaderPreprocessor.DiagnosticCode,
    limits: SceneShaderPreprocessor.Limits = .default
) throws {
    switch SceneShaderPreprocessor().preprocess(
        rootRelativePath: rootPath,
        graph: graph,
        environment: environment,
        limits: limits
    ) {
    case .success:
        throw HarnessFailure(description: "Expected preprocessor failure \(code.rawValue).")
    case let .failure(failure):
        try expect(
            failure.diagnostics.map(\.code) == [code],
            "Expected \(code.rawValue), got \(failure.diagnostics.map(\.code))."
        )
    }
}

private func resolvedFile(
    _ resolution: SceneShaderSourceResolver.Resolution,
    _ context: String
) throws -> SceneShaderSourceResolver.ResolvedFile {
    guard case let .resolved(file) = resolution else {
        throw HarnessFailure(description: "Expected resolved shader for \(context).")
    }
    return file
}

private func edge(
    _ graph: SceneShaderSourceGraph,
    parent: String,
    line: Int
) throws -> SceneShaderSourceGraph.Edge {
    guard let edge = graph.edge(parentVirtualPath: parent, line: line) else {
        throw HarnessFailure(description: "Missing graph edge at \(parent):\(line).")
    }
    return edge
}

private func comboName(_ annotation: SceneShaderContract.Annotation) -> String? {
    guard case let .object(object) = annotation.value else { return nil }
    return object["combo"]?.stringValue
}

private func definitionDescriptions(
    _ environment: SceneShaderVariantEnvironment
) -> [String: String] {
    Dictionary(uniqueKeysWithValues: environment.combos.map { binding in
        let value: String
        switch binding.definition {
        case .undefined:
            value = "undefined"
        case .defined(.bare):
            value = "bare"
        case let .defined(.integer(integer)):
            value = "integer:\(integer)"
        case let .defined(.floatingLiteral(literal)):
            value = "floating:\(literal)"
        case let .defined(.tokenSequence(tokens)):
            value = "tokens:\(tokens)"
        }
        return (binding.name, value)
    })
}

private func makeStage(_ source: String) -> SceneShaderContract.Stage {
    let path = "shaders/variants/main.frag"
    let parsed = SceneShaderContractSourceParser().parse(
        source,
        stageRelativePath: path
    )
    return .init(
        kind: .fragment,
        relativePath: path,
        source: source,
        rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
        includes: parsed.includes,
        annotations: parsed.annotations,
        declarations: parsed.declarations
    )
}

private func resolvedVariant(
    stages: [SceneShaderContract.Stage],
    explicit: [String: Int],
    readiness: [Int: Bool] = [:]
) throws -> SceneShaderVariantEnvironment {
    switch SceneShaderVariantResolver.resolve(
        stage: .fragment,
        stages: stages,
        explicitCombos: explicit,
        textureReadiness: readiness
    ) {
    case let .success(environment):
        return environment
    case let .failure(failure):
        throw HarnessFailure(description: "Expected variant, got \(failure).")
    }
}

private func runResourceGraphFixtures(at base: URL) throws -> [String] {
    let packageRoot = base.appendingPathComponent("package", isDirectory: true)
    let looseRoot = base.appendingPathComponent("loose", isDirectory: true)
    let stockRoot = base.appendingPathComponent("stock", isDirectory: true)
    try createRoot(packageRoot)
    try createRoot(looseRoot)
    try createRoot(stockRoot)

    try write("PACKAGE_WIN", to: packageRoot, "shaders/package_wins.frag")
    try write("LOOSE_DECOY", to: looseRoot, "shaders/package_wins.frag")
    try write("STOCK_DECOY", to: stockRoot, "shaders/package_wins.frag")
    try write("LOOSE_WIN", to: looseRoot, "shaders/loose_wins.frag")
    try write("STOCK_DECOY", to: stockRoot, "shaders/loose_wins.frag")
    try write("STOCK_WIN", to: stockRoot, "shaders/stock_only.frag")

    let view = resourceView(loose: looseRoot, package: packageRoot, stock: stockRoot)
    let resolver = SceneShaderSourceResolver()
    let packageWinner = try resolvedFile(
        resolver.resolve(
            virtualPath: "shaders/package_wins.frag",
            resourceView: view,
            maximumBytes: 1_024
        ),
        "package precedence"
    )
    let looseWinner = try resolvedFile(
        resolver.resolve(
            virtualPath: "shaders/loose_wins.frag",
            resourceView: view,
            maximumBytes: 1_024
        ),
        "loose precedence"
    )
    let stockWinner = try resolvedFile(
        resolver.resolve(
            virtualPath: "shaders/stock_only.frag",
            resourceView: view,
            maximumBytes: 1_024
        ),
        "stock precedence"
    )
    try expect(
        packageWinner.provenance == .package && packageWinner.source == "PACKAGE_WIN",
        "Package source did not win the shared virtual path."
    )
    try expect(
        looseWinner.provenance == .loose && looseWinner.source == "LOOSE_WIN",
        "Loose source did not win when package source was absent."
    )
    try expect(
        stockWinner.provenance == .stock && stockWinner.source == "STOCK_WIN",
        "Stock source did not provide the final fallback."
    )
    let packageGraph = graph("shaders/package_wins.frag", view: view)
    guard let packageEdge = packageGraph.edges.first(where: {
        $0.parentVirtualPath == nil
    }) else {
        throw HarnessFailure(description: "Package graph lost its root edge.")
    }
    try expect(
        packageEdge.outcome == .resolved(virtualPath: "shaders/package_wins.frag"),
        "Shadow evidence changed first-root selection."
    )
    try expect(
        packageEdge.candidates.map(\.provenance) == [.package, .loose, .stock],
        "Root candidate provenance or project-policy order was lost."
    )
    try expect(
        packageEdge.candidates.allSatisfy {
            if case .resolved = $0.outcome { return true }
            return false
        },
        "Resolved root candidate outcomes were not retained."
    )
    let shadowDiagnostics = packageGraph.diagnostics.filter {
        $0.code == .shadowedRootContentConflict
    }
    try expect(
        shadowDiagnostics.count == 1
            && shadowDiagnostics[0].candidateVirtualPath == "shaders/package_wins.frag",
        "Different shadow content did not produce stable audit evidence."
    )
    let packagePrepared = try prepared(
        rootPath: "shaders/package_wins.frag",
        graph: packageGraph,
        environment: environment()
    )
    try expect(
        packagePrepared.source == "PACKAGE_WIN",
        "A non-fatal shadow diagnostic changed selected shader bytes."
    )

    let looseGraph = graph("shaders/loose_wins.frag", view: view)
    guard let looseEdge = looseGraph.edges.first(where: {
        $0.parentVirtualPath == nil
    }) else {
        throw HarnessFailure(description: "Loose graph lost its root edge.")
    }
    try expect(
        looseEdge.candidates.map(\.provenance) == [.package, .loose, .stock]
            && {
                if case .failed(.missing) = looseEdge.candidates[0].outcome { return true }
                return false
            }(),
        "Missing higher-priority root evidence was not retained."
    )

    try write("IDENTICAL_BODY", to: packageRoot, "shaders/identical.frag")
    try write("IDENTICAL_BODY", to: looseRoot, "shaders/identical.frag")
    try write("IDENTICAL_BODY", to: stockRoot, "shaders/identical.frag")
    let identicalView = resourceView(
        loose: looseRoot,
        package: packageRoot,
        stock: stockRoot
    )
    let identicalGraph = graph("shaders/identical.frag", view: identicalView)
    guard let identicalEdge = identicalGraph.edges.first(where: {
        $0.parentVirtualPath == nil
    }) else {
        throw HarnessFailure(description: "Identical graph lost its root edge.")
    }
    let identicalHashes = Set(identicalEdge.candidates.compactMap { candidate -> String? in
        guard case let .resolved(hash) = candidate.outcome else { return nil }
        return hash
    })
    try expect(
        identicalEdge.candidates.count == 3
            && identicalHashes.count == 1
            && identicalGraph.node(at: "shaders/identical.frag")?.provenance == .package
            && !identicalGraph.diagnostics.contains {
                $0.code == .shadowedRootContentConflict
            },
        "Byte-identical roots were not safely merged under project precedence."
    )
    try expect(
        identicalGraph.dependencySHA256
            == graph("shaders/identical.frag", view: identicalView).dependencySHA256,
        "Root candidate evidence was not deterministic."
    )
    var checks = ["precedence", "shadow_evidence"]

    try write(
        """
        #include "relative.glsl"
        #include "root.glsl"
        #include "same.glsl"
        ROOT_BODY
        """,
        to: looseRoot,
        "shaders/effects/graph.frag"
    )
    try write("RELATIVE_BODY", to: looseRoot, "shaders/effects/relative.glsl")
    try write("ROOT_INCLUDE_BODY", to: looseRoot, "shaders/root.glsl")
    try write("SAME_BODY", to: looseRoot, "shaders/effects/same.glsl")
    try write("SAME_BODY", to: looseRoot, "shaders/same.glsl")
    let includeView = resourceView(loose: looseRoot, package: packageRoot, stock: stockRoot)
    let includeGraph = graph("shaders/effects/graph.frag", view: includeView)
    let relativeEdge = try edge(
        includeGraph,
        parent: "shaders/effects/graph.frag",
        line: 1
    )
    let rootEdge = try edge(
        includeGraph,
        parent: "shaders/effects/graph.frag",
        line: 2
    )
    let sameEdge = try edge(
        includeGraph,
        parent: "shaders/effects/graph.frag",
        line: 3
    )
    try expect(
        relativeEdge.outcome == .resolved(
            virtualPath: "shaders/effects/relative.glsl"
        ),
        "Source-relative include did not resolve first."
    )
    try expect(
        rootEdge.outcome == .resolved(virtualPath: "shaders/root.glsl"),
        "Shader-root include fallback did not resolve."
    )
    try expect(
        sameEdge.outcome == .resolved(virtualPath: "shaders/effects/same.glsl"),
        "Identical dual include candidates did not resolve deterministically."
    )
    try expect(sameEdge.candidates.count == 6, "Dual candidate evidence was lost.")
    try expect(
        sameEdge.candidates.filter {
            if case .resolved = $0.outcome { return true }
            return false
        }.count == 2,
        "Identical dual candidates were not both recorded as resolved."
    )
    let includePrepared = try prepared(
        rootPath: "shaders/effects/graph.frag",
        graph: includeGraph,
        environment: environment()
    )
    try expect(
        includePrepared.source.contains("RELATIVE_BODY")
            && includePrepared.source.contains("ROOT_INCLUDE_BODY")
            && includePrepared.source.contains("SAME_BODY"),
        "Resolved include sources were not composed into prepared output."
    )
    checks.append("include_resolution")

    try write(
        "#include \"ambiguous.glsl\"",
        to: looseRoot,
        "shaders/effects/ambiguous.frag"
    )
    try write("SOURCE_CANDIDATE", to: looseRoot, "shaders/effects/ambiguous.glsl")
    try write("ROOT_CANDIDATE", to: looseRoot, "shaders/ambiguous.glsl")
    let ambiguousView = resourceView(loose: looseRoot, package: packageRoot, stock: stockRoot)
    let ambiguousGraph = graph("shaders/effects/ambiguous.frag", view: ambiguousView)
    let ambiguousEdge = try edge(
        ambiguousGraph,
        parent: "shaders/effects/ambiguous.frag",
        line: 1
    )
    guard case let .ambiguous(paths) = ambiguousEdge.outcome else {
        throw HarnessFailure(description: "Different dual candidates did not fail ambiguous.")
    }
    try expect(paths.count == 2, "Ambiguous include did not retain both paths.")
    try expectFailure(
        rootPath: "shaders/effects/ambiguous.frag",
        graph: ambiguousGraph,
        environment: environment(),
        code: .ambiguousInclude
    )
    checks.append("ambiguity")

    try write(
        "#include \"../../../outside.glsl\"",
        to: looseRoot,
        "shaders/effects/invalid_path.frag"
    )
    let outside = base.appendingPathComponent("outside.glsl")
    try "ESCAPED".write(to: outside, atomically: true, encoding: .utf8)
    let symlink = fixtureURL(looseRoot, "shaders/effects/escape.glsl")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
    try write(
        "#include \"escape.glsl\"",
        to: looseRoot,
        "shaders/effects/symlink.frag"
    )
    let securityView = resourceView(loose: looseRoot, package: packageRoot, stock: stockRoot)
    let invalidGraph = graph("shaders/effects/invalid_path.frag", view: securityView)
    let symlinkGraph = graph("shaders/effects/symlink.frag", view: securityView)
    try expect(
        invalidGraph.diagnostics.map(\.code).contains(.invalidPath),
        "Escaping include did not produce invalid-path graph evidence."
    )
    try expect(
        symlinkGraph.diagnostics.map(\.code).contains(.symlinkEscape),
        "Escaping symlink did not produce symlink-escape graph evidence."
    )
    try expectFailure(
        rootPath: "shaders/effects/invalid_path.frag",
        graph: invalidGraph,
        environment: environment(),
        code: .rejectedInclude
    )
    try expectFailure(
        rootPath: "shaders/effects/symlink.frag",
        graph: symlinkGraph,
        environment: environment(),
        code: .rejectedInclude
    )
    checks.append("path_security")

    try write(
        "#include \"budget_child.glsl\"",
        to: looseRoot,
        "shaders/effects/budget.frag"
    )
    try write("CHILD", to: looseRoot, "shaders/effects/budget_child.glsl")
    let budgetView = resourceView(loose: looseRoot, package: packageRoot, stock: stockRoot)
    let budgetGraph = graph(
        "shaders/effects/budget.frag",
        view: budgetView,
        limits: .init(maximumNodes: 1)
    )
    try expect(
        budgetGraph.diagnostics.map(\.code).contains(.graphBudgetExceeded),
        "Graph node budget did not fail closed."
    )
    try expectFailure(
        rootPath: "shaders/effects/budget.frag",
        graph: budgetGraph,
        environment: environment(),
        code: .budgetExceeded
    )
    checks.append("graph_budget")
    return checks
}

private func runPreprocessorFixtures(at base: URL) throws -> [String] {
    let looseRoot = base.appendingPathComponent("loose", isDirectory: true)
    try createRoot(looseRoot)
    try write(
        """
        #define OUTER 2
        #if defined(OUTER) && OUTER >= 2 && OUTER <= 2 && OUTER != 3 && OUTER > 1 && OUTER < 3 && OUTER == 2
        #include "active.glsl"
        #if 0
        #include "inactive_missing.glsl"
        #else
        #include "fallback.glsl"
        #endif
        #else
        BAD_OUTER
        #endif
        #ifdef OUTER
        ACTIVE_IFDEF
        #else
        BAD_IFDEF
        #endif
        #undef OUTER
        #ifndef OUTER
        ACTIVE_IFNDEF
        #else
        BAD_IFNDEF
        #endif
        #if UNKNOWN == 0
        UNKNOWN_IS_ZERO
        #endif
        #if 0
        BAD_ELIF_FIRST
        #elif 2 > 1
        ACTIVE_ELIF
        #elif VERSION >= 2
        BAD_ELIF_SHORT_CIRCUIT
        #else
        BAD_ELIF_ELSE
        #endif
        """,
        to: looseRoot,
        "shaders/logic/main.frag"
    )
    try write(
        """
        ACTIVE_INCLUDE
        #if 1
        #include "deep.glsl"
        #endif
        """,
        to: looseRoot,
        "shaders/logic/active.glsl"
    )
    try write("DEEP_INCLUDE", to: looseRoot, "shaders/logic/deep.glsl")
    try write("FALLBACK_INCLUDE", to: looseRoot, "shaders/logic/fallback.glsl")
    var view = resourceView(loose: looseRoot)
    let conditionalGraph = graph("shaders/logic/main.frag", view: view)
    try expect(
        conditionalGraph.diagnostics.map(\.code).contains(.missing),
        "Inactive missing include was not retained in graph evidence."
    )
    let conditionalPrepared = try prepared(
        rootPath: "shaders/logic/main.frag",
        graph: conditionalGraph,
        environment: environment()
    )
    for expected in [
        "ACTIVE_INCLUDE", "DEEP_INCLUDE", "FALLBACK_INCLUDE",
        "ACTIVE_IFDEF", "ACTIVE_IFNDEF", "UNKNOWN_IS_ZERO", "ACTIVE_ELIF",
    ] {
        try expect(
            conditionalPrepared.source.contains(expected),
            "Conditional output omitted \(expected)."
        )
    }
    for rejected in [
        "BAD_OUTER", "BAD_IFDEF", "BAD_IFNDEF", "BAD_ELIF_FIRST",
        "BAD_ELIF_SHORT_CIRCUIT", "BAD_ELIF_ELSE",
    ] {
        try expect(
            !conditionalPrepared.source.contains(rejected),
            "Inactive conditional output retained \(rejected)."
        )
    }
    try expect(
        conditionalPrepared.dependencies.map(\.relativePath) == [
            "shaders/logic/active.glsl",
            "shaders/logic/deep.glsl",
            "shaders/logic/fallback.glsl",
            "shaders/logic/main.frag",
        ],
        "Only active nested include dependencies should be prepared."
    )
    var checks = ["conditional_includes"]

    try write(
        """
        #define DOUBLE(value) ((value) + (value))
        #define APPLY(value, function) function(value)
        #define SUM(left, right) ((left) + (right))
        #define ALIAS SUM
        #define OFFSET (1 + 2)
        #define ZERO() 0
        #define TEMP(value) value
        #ifdef TEMP
        float functionDefined = 1;
        #endif
        #undef TEMP
        #ifndef TEMP
        float functionUndefined = 1;
        #endif
        float doubled = DOUBLE(3);
        float applied = APPLY(4, DOUBLE);
        float aliased = ALIAS(vec2(1, 2).x, 5);
        float zero = ZERO();
        float offset = OFFSET;
        float reference = DOUBLE;
        const char* label = "DOUBLE(9)"; // APPLY(8, DOUBLE)
        """,
        to: looseRoot,
        "shaders/macros/functions.frag"
    )
    view = resourceView(loose: looseRoot)
    let functionPrepared = try prepared(
        rootPath: "shaders/macros/functions.frag",
        graph: graph("shaders/macros/functions.frag", view: view),
        environment: environment()
    )
    for expected in [
        "float doubled = ((3) + (3));",
        "float applied = ((4) + (4));",
        "float aliased = ((vec2(1, 2).x) + (5));",
        "float zero = 0;",
        "float offset = (1 + 2);",
        "float functionDefined = 1;",
        "float functionUndefined = 1;",
        "float reference = DOUBLE;",
        "\"DOUBLE(9)\"; // APPLY(8, DOUBLE)",
    ] {
        try expect(
            functionPrepared.source.contains(expected),
            "Bounded function-like macro expansion omitted \(expected): \(functionPrepared.source)"
        )
    }
    checks.append("function_macros")

    try write(
        "#if 1\nFIRST\n#endif\n\n#endif\n\n#if 1\nSECOND\n#endif",
        to: looseRoot,
        "shaders/logic/redundant_top_level_endif.frag"
    )
    view = resourceView(loose: looseRoot)
    let redundantEndif = try prepared(
        rootPath: "shaders/logic/redundant_top_level_endif.frag",
        graph: graph("shaders/logic/redundant_top_level_endif.frag", view: view),
        environment: environment()
    )
    try expect(
        redundantEndif.source.contains("FIRST")
            && redundantEndif.source.contains("SECOND")
            && !redundantEndif.source.contains("#endif"),
        "The bounded duplicated top-level #endif shape was not normalized."
    )
    checks.append("redundant_top_level_endif")

    let failureSources: [(String, String, SceneShaderPreprocessor.DiagnosticCode)] = [
        ("unmatched_elif", "#elif 1\nVALUE", .unmatchedElif),
        ("elif_after_else", "#if 0\n#else\n#elif 1\nVALUE\n#endif", .elifAfterElse),
        ("empty_elif", "#if 0\n#elif\nVALUE\n#endif", .malformedDirective),
        ("function_variadic", "#define F(...) 1\nVALUE", .functionLikeMacro),
        ("function_paste", "#define F(x) x ## x\nVALUE", .functionLikeMacro),
        ("function_stringize", "#define F(x) #x\nVALUE", .functionLikeMacro),
        ("function_quoted", "#define F(x) \"x\"\nVALUE", .functionLikeMacro),
        ("function_duplicate", "#define F(x, x) x\nVALUE", .functionLikeMacro),
        ("function_recursive", "#define F(x) F(x)\nF(1)", .functionLikeMacro),
        ("function_arity", "#define F(x) x\nF(1, 2)", .functionLikeMacro),
        ("function_empty_argument", "#define F(x) x\nF()", .functionLikeMacro),
        ("function_invocation", "#define F(x) x\nF(1", .functionLikeMacro),
        ("function_redefinition", "#define F(x) x\n#define F(x) (x + 1)", .conflictingMacro),
        ("function_kind_change", "#define F(x) x\n#define F 1", .conflictingMacro),
        ("object_kind_change", "#define F 1\n#define F(x) x", .conflictingMacro),
        ("function_parameter_budget", "#define F(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q) a", .budgetExceeded),
        ("object_quoted", "#define VALUE \"quoted\"\nVALUE", .malformedDirective),
        ("object_unbalanced", "#define VALUE (1 + 2\nVALUE", .malformedDirective),
        ("unknown", "#pragma once\nVALUE", .unknownDirective),
        ("joined_name", "#if0\nBAD\n#endif", .unknownDirective),
        ("unmatched_else", "#else\nVALUE", .unmatchedElse),
        ("duplicate_else", "#if 0\n#else\n#else\n#endif", .duplicateElse),
        ("unmatched_endif", "#endif", .unmatchedEndif),
        ("trailing_redundant_endif", "#if 1\nVALUE\n#endif\n#endif", .unmatchedEndif),
        ("code_separated_redundant_endif", "#if 1\nA\n#endif\n#endif\nVALUE\n#if 1\nB\n#endif", .unmatchedEndif),
        ("repeated_redundant_endif", "#if 1\nA\n#endif\n#endif\n#if 1\nB\n#endif\n#endif\n#if 1\nC\n#endif", .unmatchedEndif),
        ("unterminated", "#if 1\nVALUE", .unterminatedConditional),
    ]
    for (name, source, _) in failureSources {
        try write(source, to: looseRoot, "shaders/failures/\(name).frag")
    }
    view = resourceView(loose: looseRoot)
    for (name, _, code) in failureSources {
        let path = "shaders/failures/\(name).frag"
        try expectFailure(
            rootPath: path,
            graph: graph(path, view: view),
            environment: environment(),
            code: code
        )
    }
    checks.append("directive_failures")

    let directiveAnnotationSources = [
        "#define AUX 1 // [COMBO] {\"combo\":\"MODE\",\"default\":1}\nSAFE",
        "#include \"absent.glsl\" // [COMBO] {\"combo\":\"MODE\",\"default\":1}\nSAFE",
        "#if 1 // [COMBO] {\"combo\":\"MODE\",\"default\":1}\nSAFE\n#endif",
    ]
    for (index, source) in directiveAnnotationSources.enumerated() {
        let path = "shaders/failures/directive_annotation_\(index).frag"
        try write(source, to: looseRoot, path)
    }
    view = resourceView(loose: looseRoot)
    for index in directiveAnnotationSources.indices {
        let path = "shaders/failures/directive_annotation_\(index).frag"
        try expectFailure(
            rootPath: path,
            graph: graph(path, view: view),
            environment: environment(),
            code: .unsupportedAnnotationPlacement
        )
    }
    try write(
        "#if 0\n#define AUX 1 // [COMBO] {\"combo\":\"MODE\",\"default\":1}\n#endif\nSAFE",
        to: looseRoot,
        "shaders/logic/inactive_directive_annotation.frag"
    )
    view = resourceView(loose: looseRoot)
    let inactiveDirectiveAnnotation = try prepared(
        rootPath: "shaders/logic/inactive_directive_annotation.frag",
        graph: graph("shaders/logic/inactive_directive_annotation.frag", view: view),
        environment: environment()
    )
    try expect(
        inactiveDirectiveAnnotation.source == "SAFE"
            && inactiveDirectiveAnnotation.activeAnnotations.isEmpty,
        "An inactive directive-line annotation polluted the active schema."
    )
    checks.append("directive_annotation_placement")

    try write(
        "#include \"absent.glsl\"",
        to: looseRoot,
        "shaders/failures/missing.frag"
    )
    try write(
        "#include \"cycle_b.glsl\"",
        to: looseRoot,
        "shaders/failures/cycle_a.frag"
    )
    try write(
        "#include \"cycle_a.frag\"",
        to: looseRoot,
        "shaders/failures/cycle_b.glsl"
    )
    view = resourceView(loose: looseRoot)
    try expectFailure(
        rootPath: "shaders/failures/missing.frag",
        graph: graph("shaders/failures/missing.frag", view: view),
        environment: environment(),
        code: .missingInclude
    )
    try expectFailure(
        rootPath: "shaders/failures/cycle_a.frag",
        graph: graph("shaders/failures/cycle_a.frag", view: view),
        environment: environment(),
        code: .includeCycle
    )
    checks.append("missing_cycle")

    try write(
        "#define SCALE 1.25\nfloat value = SCALE; // SCALE",
        to: looseRoot,
        "shaders/macros/floating.frag"
    )
    try write(
        "#define SCALE 1.25\n#if SCALE\nVALUE\n#endif",
        to: looseRoot,
        "shaders/macros/floating_condition.frag"
    )
    view = resourceView(loose: looseRoot)
    let floatingPrepared = try prepared(
        rootPath: "shaders/macros/floating.frag",
        graph: graph("shaders/macros/floating.frag", view: view),
        environment: environment()
    )
    try expect(
        floatingPrepared.source == "float value = 1.25; // SCALE",
        "Floating macro did not expand only in code."
    )
    try expectFailure(
        rootPath: "shaders/macros/floating_condition.frag",
        graph: graph("shaders/macros/floating_condition.frag", view: view),
        environment: environment(),
        code: .invalidExpression
    )
    checks.append("floating_macro")

    try write(
        """
        const char* label = "MODE VERSION";
        /* MODE
        VERSION */
        int character = 'M';
        int selected = MODE;
        """,
        to: looseRoot,
        "shaders/macros/lexical.frag"
    )
    view = resourceView(loose: looseRoot)
    let lexicalPrepared = try prepared(
        rootPath: "shaders/macros/lexical.frag",
        graph: graph("shaders/macros/lexical.frag", view: view),
        environment: environment([.init(
            name: "MODE",
            definition: .defined(.integer(7))
        )])
    )
    try expect(
        lexicalPrepared.source.contains("\"MODE VERSION\"")
            && lexicalPrepared.source.contains("/* MODE\nVERSION */")
            && lexicalPrepared.source.contains("int character = 'M';")
            && lexicalPrepared.source.contains("int selected = 7;"),
        "Macro expansion changed a string/comment or missed executable code."
    )
    checks.append("token_lexing")

    try write(
        """
        /*
        uniform float u_Bad; // [COMBO] {broken
        uniform float u_Hidden; // [COMBO] {"combo":"HIDDEN","default":1}
        */
        const char* label = "// [COMBO] {broken";
        uniform float u_Visible; // [COMBO] {"combo":"VISIBLE","default":1}
        """,
        to: looseRoot,
        "shaders/metadata/block_comments.frag"
    )
    view = resourceView(loose: looseRoot)
    let blockMetadata = try prepared(
        rootPath: "shaders/metadata/block_comments.frag",
        graph: graph("shaders/metadata/block_comments.frag", view: view),
        environment: environment()
    )
    try expect(
        blockMetadata.activeAnnotations.compactMap { comboName($0.annotation) }
            == ["VISIBLE"]
            && blockMetadata.activeDeclarations.map(\.declaration.name) == ["u_Visible"],
        "Block comments or string contents leaked into active shader metadata."
    )

    try write(
        "#if 1\n#include \"open.inc\"\n#endif\nSAFE_PARENT",
        to: looseRoot,
        "shaders/comments/include_root.frag"
    )
    try write("/*", to: looseRoot, "shaders/comments/open.inc")
    view = resourceView(loose: looseRoot)
    try expectFailure(
        rootPath: "shaders/comments/include_root.frag",
        graph: graph("shaders/comments/include_root.frag", view: view),
        environment: environment(),
        code: .unterminatedBlockComment
    )
    checks.append("comment_boundaries")

    try write(
        "#if 0 == 2 < 3\nBAD_PRECEDENCE\n#else\nGOOD_PRECEDENCE\n#endif",
        to: looseRoot,
        "shaders/logic/precedence.frag"
    )
    view = resourceView(loose: looseRoot)
    let precedencePrepared = try prepared(
        rootPath: "shaders/logic/precedence.frag",
        graph: graph("shaders/logic/precedence.frag", view: view),
        environment: environment()
    )
    try expect(
        precedencePrepared.source == "GOOD_PRECEDENCE",
        "Equality and relational operators used the wrong precedence."
    )
    checks.append("expression_precedence")

    try write("ONE\nTWO", to: looseRoot, "shaders/budget/output.frag")
    view = resourceView(loose: looseRoot)
    try expectFailure(
        rootPath: "shaders/budget/output.frag",
        graph: graph("shaders/budget/output.frag", view: view),
        environment: environment(),
        code: .budgetExceeded,
        limits: .init(
            maximumIncludeDepth: 32,
            maximumDependencies: 256,
            maximumInputBytes: 1_024,
            maximumOutputBytes: 1_024,
            maximumOutputLines: 1,
            maximumExpressionTokens: 512,
            maximumFunctionMacroParameters: 16,
            maximumMacroExpansionDepth: 32,
            maximumMacroExpansionTokens: 16_384,
            maximumMacroExpansionBytes: 1_024 * 1_024
        )
    )
    try write(
        "#define DUP(value) value value\nDUP(1)",
        to: looseRoot,
        "shaders/budget/macro_tokens.frag"
    )
    view = resourceView(loose: looseRoot)
    try expectFailure(
        rootPath: "shaders/budget/macro_tokens.frag",
        graph: graph("shaders/budget/macro_tokens.frag", view: view),
        environment: environment(),
        code: .budgetExceeded,
        limits: .init(
            maximumIncludeDepth: 32,
            maximumDependencies: 256,
            maximumInputBytes: 1_024,
            maximumOutputBytes: 1_024,
            maximumOutputLines: 100,
            maximumExpressionTokens: 512,
            maximumFunctionMacroParameters: 16,
            maximumMacroExpansionDepth: 32,
            maximumMacroExpansionTokens: 4,
            maximumMacroExpansionBytes: 1_024
        )
    )
    try write(
        "#define A B\n#define B C\n#define C 1\nA",
        to: looseRoot,
        "shaders/budget/macro_depth.frag"
    )
    view = resourceView(loose: looseRoot)
    try expectFailure(
        rootPath: "shaders/budget/macro_depth.frag",
        graph: graph("shaders/budget/macro_depth.frag", view: view),
        environment: environment(),
        code: .budgetExceeded,
        limits: .init(
            maximumIncludeDepth: 32,
            maximumDependencies: 256,
            maximumInputBytes: 1_024,
            maximumOutputBytes: 1_024,
            maximumOutputLines: 100,
            maximumExpressionTokens: 512,
            maximumFunctionMacroParameters: 16,
            maximumMacroExpansionDepth: 2,
            maximumMacroExpansionTokens: 16_384,
            maximumMacroExpansionBytes: 1_024
        )
    )
    try write(
        "#define BIG 123456789\nBIG",
        to: looseRoot,
        "shaders/budget/macro_bytes.frag"
    )
    view = resourceView(loose: looseRoot)
    try expectFailure(
        rootPath: "shaders/budget/macro_bytes.frag",
        graph: graph("shaders/budget/macro_bytes.frag", view: view),
        environment: environment(),
        code: .budgetExceeded,
        limits: .init(
            maximumIncludeDepth: 32,
            maximumDependencies: 256,
            maximumInputBytes: 1_024,
            maximumOutputBytes: 1_024,
            maximumOutputLines: 100,
            maximumExpressionTokens: 512,
            maximumFunctionMacroParameters: 16,
            maximumMacroExpansionDepth: 32,
            maximumMacroExpansionTokens: 16_384,
            maximumMacroExpansionBytes: 10
        )
    )
    checks.append("preprocessor_budget")

    try write(
        """
        #define ENABLE 1
        #if ENABLE
        uniform sampler2D g_Texture2; // [COMBO] {"combo":"HAS_TEX","default":1,"options":[0,1]}
        #include "active_decl.glsl"
        #else
        uniform float u_Inactive; // [COMBO] {"combo":"INACTIVE","default":1}
        #endif
        """,
        to: looseRoot,
        "shaders/metadata/main.frag"
    )
    try write(
        "uniform float u_Level; // [COMBO] {\"combo\":\"LEVEL\",\"default\":2,\"options\":[1,2]}",
        to: looseRoot,
        "shaders/metadata/active_decl.glsl"
    )
    view = resourceView(loose: looseRoot)
    let metadata = try prepared(
        rootPath: "shaders/metadata/main.frag",
        graph: graph("shaders/metadata/main.frag", view: view),
        environment: environment()
    )
    try expect(
        metadata.activeDeclarations.map(\.declaration.name) == ["g_Texture2", "u_Level"],
        "Active declarations did not follow conditional composition."
    )
    try expect(
        metadata.activeAnnotations.compactMap { comboName($0.annotation) }
            == ["HAS_TEX", "LEVEL"],
        "Active annotations did not follow conditional composition."
    )
    try expect(metadata.sourceMap.count == 2, "Source map output line count is incorrect.")
    try expect(
        metadata.sourceMap[0].outputLine == 1
            && metadata.sourceMap[0].sourcePath == "shaders/metadata/main.frag"
            && metadata.sourceMap[0].sourceLine == 3,
        "Root source map entry is incorrect."
    )
    try expect(
        metadata.sourceMap[1].outputLine == 2
            && metadata.sourceMap[1].sourcePath == "shaders/metadata/active_decl.glsl"
            && metadata.sourceMap[1].sourceLine == 1,
        "Included source map entry is incorrect."
    )
    checks.append("source_metadata")
    return checks
}

private func runVariantAndDigestFixtures(at base: URL) throws -> [String] {
    let variantStage = makeStage(
        """
        uniform float u_Base; // [COMBO] {"combo":"BASE","default":1,"options":[0,1]}
        uniform float u_Dependent; // [COMBO] {"combo":"DEPENDENT","default":2,"options":[2,3],"require":{"BASE":1}}
        uniform sampler2D g_Texture2; // {"combo":"HAS_TEXTURE","default":"textures/mask"}
        """
    )
    let ready = try resolvedVariant(
        stages: [variantStage],
        explicit: [:],
        readiness: [2: true]
    )
    let readyDefinitions = definitionDescriptions(ready)
    try expect(readyDefinitions["BASE"] == "integer:1", "Default combo was not applied.")
    try expect(
        readyDefinitions["DEPENDENT"] == "integer:2",
        "Required combo default was not enabled."
    )
    try expect(
        readyDefinitions["HAS_TEXTURE"] == "integer:1",
        "Ready sampler slot did not enable its combo."
    )
    let notReady = try resolvedVariant(
        stages: [variantStage],
        explicit: [:],
        readiness: [2: false]
    )
    try expect(
        definitionDescriptions(notReady)["HAS_TEXTURE"] == "undefined",
        "Unready sampler slot did not fail closed."
    )
    let disabledRequirement = try resolvedVariant(
        stages: [variantStage],
        explicit: ["BASE": 0],
        readiness: [2: false]
    )
    let disabledDefinitions = definitionDescriptions(disabledRequirement)
    try expect(
        disabledDefinitions["BASE"] == "integer:0",
        "Explicit zero was not preserved as a defined macro."
    )
    try expect(
        disabledDefinitions["DEPENDENT"] == "undefined",
        "Unsatisfied requirement did not leave its combo undefined."
    )
    switch SceneShaderVariantResolver.resolve(
        stage: .fragment,
        stages: [variantStage],
        explicitCombos: ["BASE": 7],
        textureReadiness: [2: false]
    ) {
    case .success:
        throw HarnessFailure(description: "Out-of-options combo unexpectedly resolved.")
    case let .failure(failure):
        try expect(
            failure.code == .invalidOption && failure.combo == "BASE",
            "Out-of-options combo returned the wrong failure."
        )
    }
    var checks = ["variant_resolution"]

    let caseStage = makeStage(
        """
        uniform float u_Upper; // [COMBO] {"combo":"MODE","options":[4]}
        uniform float u_Lower; // [COMBO] {"combo":"mode","options":[2]}
        """
    )
    let caseSensitive = try resolvedVariant(
        stages: [caseStage],
        explicit: ["MODE": 4, "mode": 2]
    )
    let caseDefinitions = definitionDescriptions(caseSensitive)
    try expect(
        caseDefinitions == ["MODE": "integer:4", "mode": "integer:2"],
        "Case-distinct authored combo names collapsed."
    )
    try expect(
        disabledDefinitions["BASE"] != disabledDefinitions["DEPENDENT"],
        "Undefined and explicit zero macro states collapsed together."
    )
    checks.append("macro_identity")

    let inactiveComboSource = """
        int selectedMode = BLENDMODE;
        #if BLENDMODE
        int conditionalMode = 1;
        #else
        int conditionalMode = 0;
        #endif
        #ifdef BLENDMODE
        int incorrectlyDefined = 1;
        #endif
        // [COMBO] {"combo":"BLENDMODE","default":31,"require":{"DIRECTDRAW":0}}
        """
    let inactiveComboStage = makeStage(inactiveComboSource)
    let inactiveComboEnvironment = try resolvedVariant(
        stages: [inactiveComboStage],
        explicit: ["DIRECTDRAW": 1]
    )
    let inactiveComboRoot = base.appendingPathComponent(
        "inactive_combo",
        isDirectory: true
    )
    try createRoot(inactiveComboRoot)
    try write(
        inactiveComboSource,
        to: inactiveComboRoot,
        "shaders/variants/main.frag"
    )
    let inactivePrepared = try prepared(
        rootPath: "shaders/variants/main.frag",
        graph: graph(
            "shaders/variants/main.frag",
            view: resourceView(loose: inactiveComboRoot)
        ),
        environment: inactiveComboEnvironment
    )
    try expect(
        definitionDescriptions(inactiveComboEnvironment)["BLENDMODE"] == "undefined",
        "Inactive authored combo lost its undefined variant identity."
    )
    try expect(
        inactivePrepared.source.contains("int selectedMode = 0;")
            && inactivePrepared.source.contains("int conditionalMode = 0;")
            && !inactivePrepared.source.contains("incorrectlyDefined"),
        "Inactive authored combo did not use bounded code-only zero semantics."
    )
    checks.append("undefined_combo_code_zero")

    let originalRoot = base.appendingPathComponent("digest_original", isDirectory: true)
    let changedRoot = base.appendingPathComponent("digest_changed", isDirectory: true)
    try createRoot(originalRoot)
    try createRoot(changedRoot)
    let rootSource = "#include \"dep.glsl\"\nint selected = MODE + AUX;"
    try write(rootSource, to: originalRoot, "shaders/digest/main.frag")
    try write("float dependencyValue = 1.0;", to: originalRoot, "shaders/digest/dep.glsl")
    try write(rootSource, to: changedRoot, "shaders/digest/main.frag")
    try write("float dependencyValue = 2.0;", to: changedRoot, "shaders/digest/dep.glsl")

    let originalViewA = resourceView(loose: originalRoot)
    let originalViewB = resourceView(loose: originalRoot)
    let changedView = resourceView(loose: changedRoot)
    let originalGraphA = graph("shaders/digest/main.frag", view: originalViewA)
    let originalGraphB = graph("shaders/digest/main.frag", view: originalViewB)
    let changedGraph = graph("shaders/digest/main.frag", view: changedView)
    let orderedEnvironment = try environment([
        .init(name: "AUX", definition: .defined(.integer(3))),
        .init(name: "MODE", definition: .defined(.integer(1))),
    ])
    let reversedEnvironment = try environment([
        .init(name: "MODE", definition: .defined(.integer(1))),
        .init(name: "AUX", definition: .defined(.integer(3))),
    ])
    let changedEnvironment = try environment([
        .init(name: "AUX", definition: .defined(.integer(3))),
        .init(name: "MODE", definition: .defined(.integer(2))),
    ])
    let originalPreparedA = try prepared(
        rootPath: "shaders/digest/main.frag",
        graph: originalGraphA,
        environment: orderedEnvironment
    )
    let originalPreparedB = try prepared(
        rootPath: "shaders/digest/main.frag",
        graph: originalGraphB,
        environment: reversedEnvironment
    )
    let variantChanged = try prepared(
        rootPath: "shaders/digest/main.frag",
        graph: originalGraphA,
        environment: changedEnvironment
    )
    let dependencyChanged = try prepared(
        rootPath: "shaders/digest/main.frag",
        graph: changedGraph,
        environment: orderedEnvironment
    )

    try expect(
        originalGraphA.dependencySHA256 == originalGraphB.dependencySHA256,
        "Equivalent graph builds produced different dependency digests."
    )
    try expect(
        orderedEnvironment.variantSHA256 == reversedEnvironment.variantSHA256,
        "Equivalent macro order produced different variant digests."
    )
    try expect(
        originalPreparedA.dependencySHA256 == originalPreparedB.dependencySHA256
            && originalPreparedA.variantSHA256 == originalPreparedB.variantSHA256
            && originalPreparedA.preparedSHA256 == originalPreparedB.preparedSHA256,
        "Equivalent preparation inputs produced different digests."
    )
    try expect(
        variantChanged.dependencySHA256 == originalPreparedA.dependencySHA256
            && variantChanged.variantSHA256 != originalPreparedA.variantSHA256
            && variantChanged.preparedSHA256 != originalPreparedA.preparedSHA256,
        "Variant-only change was not isolated from dependency identity."
    )
    try expect(
        changedGraph.dependencySHA256 != originalGraphA.dependencySHA256
            && dependencyChanged.dependencySHA256 != originalPreparedA.dependencySHA256
            && dependencyChanged.variantSHA256 == originalPreparedA.variantSHA256
            && dependencyChanged.preparedSHA256 != originalPreparedA.preparedSHA256,
        "Dependency-only change was not isolated from variant identity."
    )
    try expect(
        originalPreparedA.source.contains("int selected = 1 + 3;")
            && variantChanged.source.contains("int selected = 2 + 3;"),
        "Variant macro change did not alter only the prepared source."
    )
    checks.append("digest_isolation")
    return checks
}

@main
private struct SceneShaderPreprocessorHarness {
    static func main() {
        let mode = CommandLine.arguments.dropFirst().first ?? ""
        let basePath = CommandLine.arguments.dropFirst(2).first ?? ""
        let base = URL(fileURLWithPath: basePath, isDirectory: true)
        do {
            let checks: [String]
            switch mode {
            case "resource-graph":
                checks = try runResourceGraphFixtures(at: base)
            case "preprocessor":
                checks = try runPreprocessorFixtures(at: base)
            case "variant-digests":
                checks = try runVariantAndDigestFixtures(at: base)
            default:
                throw HarnessFailure(description: "Unknown harness mode: \(mode)")
            }
            emit(HarnessOutput(checks: checks, failure: nil))
        } catch {
            emit(HarnessOutput(checks: [], failure: String(describing: error)))
        }
    }

    private static func emit(_ output: HarnessOutput) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(output) else { return }
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneShaderPreprocessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "SceneShaderPreprocessorHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "scene-shader-preprocessor-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(
            build_root / "clang-module-cache"
        )
        environment["SWIFT_MODULECACHE_PATH"] = str(
            build_root / "swift-module-cache"
        )
        subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPO_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.build_directory.cleanup()

    def run_mode(self, mode):
        with tempfile.TemporaryDirectory() as temporary_directory:
            completed = subprocess.run(
                [str(self.binary), mode, temporary_directory],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        output = json.loads(completed.stdout)
        self.assertIsNone(output.get("failure"), output.get("failure"))
        return output["checks"]

    def test_resource_precedence_include_resolution_and_graph_boundaries(self):
        self.assertEqual(
            self.run_mode("resource-graph"),
            [
                "precedence",
                "shadow_evidence",
                "include_resolution",
                "ambiguity",
                "path_security",
                "graph_budget",
            ],
        )

    def test_preprocessor_conditionals_failures_budgets_and_metadata(self):
        self.assertEqual(
            self.run_mode("preprocessor"),
            [
                "conditional_includes",
                "function_macros",
                "redundant_top_level_endif",
                "directive_failures",
                "directive_annotation_placement",
                "missing_cycle",
                "floating_macro",
                "token_lexing",
                "comment_boundaries",
                "expression_precedence",
                "preprocessor_budget",
                "source_metadata",
            ],
        )

    def test_variant_resolution_and_digest_isolation(self):
        self.assertEqual(
            self.run_mode("variant-digests"),
            [
                "variant_resolution",
                "macro_identity",
                "undefined_combo_code_zero",
                "digest_isolation",
            ],
        )


if __name__ == "__main__":
    unittest.main()
