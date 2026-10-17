import Foundation

/// CPU proof/transport fixture. No shader algorithm or GPU oracle lives here.
private struct OutputCase {
    let name: String
    let body: String
    var helpers = ""
    var compile = false

    var source: String {
        "uniform float u;\n\(helpers)\nvoid main() {\n\(body)\n}"
    }
}

private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
void main() { gl_Position = vec4(a_Position, 1.0); }
"""

private let outputCases: [OutputCase] = [
    .init(name: "old-whole", body: "gl_FragColor = vec4(0.25);", compile: true),
    .init(name: "old-component-add", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy += vec2(0.5);", compile: true),
    .init(name: "mix", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = mix(gl_FragColor.xy, vec2(0.0), 0.5);", compile: true),
    .init(name: "renamed-equivalent", body: "vec2 changed = vec2(0.0); float weight = 0.5; gl_FragColor = vec4(0.25); gl_FragColor.rg = mix((gl_FragColor.rg), changed, weight);", compile: true),
    .init(name: "conditional-mutation", body: "gl_FragColor = vec4(0.25); if (u > 0.0) { gl_FragColor.xy += gl_FragColor.yx * 0.5; }", compile: true),
    .init(name: "repeated-read-swizzle", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = gl_FragColor.xx + gl_FragColor.yy;", compile: true),
    .init(name: "constructor-read", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = vec2(sin(gl_FragColor.x), cos(gl_FragColor.y));", compile: true),
    // Existing no-output-read math is intentionally not narrowed by this change.
    .init(name: "old-unrelated-call", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = Unknown(vec2(0.0));"),
    .init(name: "preinit-read", body: "vec2 value = gl_FragColor.xy; gl_FragColor = vec4(value, 0.0, 1.0);"),
    .init(name: "initializer-read", body: "gl_FragColor = vec4(gl_FragColor.xy, 0.0, 1.0);"),
    .init(name: "initializer-nested-write", body: "gl_FragColor = vec4((gl_FragColor.xy = vec2(0.5)), 0.0, 1.0);"),
    .init(name: "conditional-init", body: "if (u > 0.0) { gl_FragColor = vec4(0.25); } gl_FragColor.xy += gl_FragColor.xy;"),
    .init(name: "no-whole-init", body: "gl_FragColor.xy = vec2(0.5);"),
    .init(name: "multiple-whole-init", body: "gl_FragColor = vec4(0.25); gl_FragColor = vec4(0.5);"),
    .init(name: "early-return", body: "if (u > 0.0) return; gl_FragColor = vec4(0.25); gl_FragColor.xy += gl_FragColor.xy;"),
    .init(name: "discard", body: "gl_FragColor = vec4(0.25); if (u > 0.0) discard; gl_FragColor.xy += gl_FragColor.xy;"),
    .init(name: "blue-read", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = gl_FragColor.zw;"),
    .init(name: "whole-read", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = vec2(gl_FragColor);"),
    .init(name: "read-escapes-mutation", body: "gl_FragColor = vec4(0.25); vec2 value = gl_FragColor.xy; gl_FragColor.xy = value;"),
    .init(name: "unknown-call", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = Unknown(gl_FragColor.xy);"),
    .init(name: "pure-helper-not-opened", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = Forward(gl_FragColor.yx);", helpers: "vec2 Scale(in vec2 value) { return value * 0.5; } vec2 Forward(vec2 renamed) { return Scale(renamed); }"),
    .init(name: "helper-unknown-call", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = Forward(gl_FragColor.xy);", helpers: "vec2 Forward(vec2 value) { return Unknown(value); }"),
    .init(name: "unknown-nested-argument", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = mix(gl_FragColor.xy, Unknown(vec2(0.0)), 0.5);"),
    .init(name: "unexpanded-blending", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = ApplyBlending(gl_FragColor.xy);"),
    .init(name: "out-parameter", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = Write(gl_FragColor.xy);", helpers: "vec2 Write(out vec2 value) { value = vec2(0.5); return value; }"),
    .init(name: "inout-parameter", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = Mutate(gl_FragColor.xy);", helpers: "vec2 Mutate(inout vec2 value) { value *= 0.5; return value; }"),
    .init(name: "nested-increment", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = vec2(++gl_FragColor.x);"),
    .init(name: "nested-assignment", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = (gl_FragColor.xy = vec2(0.5));"),
    .init(name: "nested-other-assignment", body: "float value = 1.0; gl_FragColor = vec4(0.25); gl_FragColor.xy = mix(gl_FragColor.xy, vec2(value = 0.0), 0.5);"),
    .init(name: "duplicate-lvalue", body: "gl_FragColor = vec4(0.25); gl_FragColor.xx = gl_FragColor.xy;"),
    .init(name: "mixed-swizzle", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = gl_FragColor.xr;"),
    .init(name: "shadowed-builtin", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = mix(gl_FragColor.xy, vec2(0.0), 0.5);", helpers: "float sideEffect; vec2 mix(vec2 a, vec2 b, float t) { sideEffect = t; return a + b; }"),
    .init(name: "pure-shadowed-builtin", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = mix(gl_FragColor.xy, vec2(0.0), 0.5);", helpers: "vec2 mix(vec2 a, vec2 b, float t) { return a + b * t; }"),
    .init(name: "ambiguous-helper", body: "gl_FragColor = vec4(0.25); gl_FragColor.xy = Pick(gl_FragColor.xy);", helpers: "vec2 Pick(vec2 v) { return v; } float Pick(float v) { return v; }")
]

private func facts(_ source: String, compile: Bool = false) -> [String: Any] {
    let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
        lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: .fragment),
        stage: .fragment
    )
    var result: [String: Any] = [
        "syntaxDiagnostics": syntax.diagnostics.count,
        "sourceFact": SceneAuthoredShaderFragmentOutputAnalyzer.analyze(source: source).rawValue
    ]
    if let unit = syntax.unit {
        result["unitFact"] = SceneAuthoredShaderFragmentOutputAnalyzer.analyze(unit).rawValue
    }
    if compile {
        let compiled = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: source)
        result["boundedDiagnostics"] = compiled.diagnostics.map { String(describing: $0) }
        result["boundedFact"] = compiled.program?.fragmentOutputChannelUse.rawValue ?? "no-program"
    }
    return result
}

private func legacyColorPolicies() -> [String: Bool] {
    // Observe the unchanged shared color utility defaults on the same syntax
    // unit; this is not a claim about an unexpanded helper's numeric safety.
    func accepts(_ name: String, helper: String) -> Bool {
        let source = "\(helper) void main() { vec2 value = \(name)(vec2(0.5)); }"
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: .fragment), stage: .fragment)
        guard let unit = syntax.unit, syntax.diagnostics.isEmpty,
              let main = unit.functions.first(where: { $0.name == "main" }),
              let call = main.bodyRange.first(where: { unit.tokens[$0].text == name }) else { return false }
        return SceneAuthoredShaderColorTransferAnalyzer.helperCallsArePureAndUnsampled(
            fragment: unit, expressionRanges: [call..<main.bodyRange.upperBound])
    }
    return ["authoredReadOnlyHelper": accepts("Pure", helper: "vec2 Pure(vec2 v) { return v * 0.5; }"),
            "legacyUnexpandedBlending": accepts("ApplyBlending", helper: "")]
}

private struct ActualVariantInput: Decodable {
    let contract: SceneShaderContract
    let materialCombos: [String: Int]
}

private func actualVariant(_ path: String) throws -> [[String: Any]] {
    let input = try JSONDecoder().decode(ActualVariantInput.self,
        from: Data(contentsOf: URL(fileURLWithPath: path)))
    guard let graph = input.contract.sourceGraph,
          let stage = input.contract.stages.first(where: { $0.kind == .fragment }) else {
        throw NSError(domain: "fixture-missing-source-graph", code: 1)
    }
    return try [false, true].map { collision in
        let environment = try SceneShaderVariantResolver.resolve(
            stage: .fragment, stages: input.contract.stages,
            compatibilityTarget: .windowsDX11ShaderModel4,
            explicitCombos: input.materialCombos, inactiveComboProviders: ["DYE"],
            textureReadiness: [0: true, 1: true, 2: false, 3: collision, 4: false]
        ).get()
        let prepared = try SceneShaderPreprocessor().preprocess(
            rootRelativePath: stage.relativePath, graph: graph, environment: environment
        ).get()
        return ["collisionTexturePresent": collision, "facts": facts(prepared.source),
                "sourceSHA256": SceneShaderStableDigest.hash(Data(prepared.source.utf8))]
    }
}

@main
private enum FragmentOutputProbe {
    static func main() throws {
        // The production frontend enables disk IO by Bundle ID. Check the
        // actual Foundation directory before *any* compile can touch it.
        let expectedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        guard !expectedHome.isEmpty, Bundle.main.bundleIdentifier == "com.songziqiang.MyWallpaperX",
              cache.standardizedFileURL.path.hasPrefix(expectedHome + "/") else {
            throw NSError(domain: "fixture-cache-isolation-unavailable", code: 1)
        }
        let mode = CommandLine.arguments.dropFirst().first ?? "facts"
        var output: [String: Any] = ["cacheDirectory": cache.path]
        if mode == "cache" {
            var programs: [String: Any] = [:]
            let before = SceneAuthoredShaderFrontend.completedCacheSnapshot.completedEntries
            for name in ["old-whole", "mix"] {
                let value = outputCases.first(where: { $0.name == name })!
                let first = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: value.source)
                let second = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: value.source)
                guard let a = first.program, let b = second.program else {
                    throw NSError(domain: "fixture-no-program", code: 1)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                let bytes = try encoder.encode(a)
                guard bytes == (try encoder.encode(b)) else { throw NSError(domain: "fixture-memory-drift", code: 1) }
                programs[name] = try JSONSerialization.jsonObject(with: bytes)
            }
            output["programs"] = programs
            output["completedBefore"] = before
            output["completedAfter"] = SceneAuthoredShaderFrontend.completedCacheSnapshot.completedEntries
        } else if mode == "actual-variant" {
            output["variants"] = try actualVariant(CommandLine.arguments[2])
        } else {
            output["legacyColorPolicies"] = legacyColorPolicies()
            output["cases"] = Dictionary(uniqueKeysWithValues: outputCases.map {
                ($0.name, facts($0.source, compile: $0.compile))
            })
        }
        let bytes = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        FileHandle.standardOutput.write(bytes)
    }
}
