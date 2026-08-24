// Focused compiler fixture for strict implicit-disabled option admission.
import Foundation

@main
enum SceneShaderImplicitDisabledOptionHarness {
    static func main() throws {
        try acceptsRenamedDirectCondition()
        try acceptsRenamedMultiStageDirectConditions()
        try omissionMatchesExplicitZeroBranch()
        try explicitOneWins()
        try rejectsNonExactForms()
        print("scene_shader_implicit_disabled_option_harness: PASS")
    }

    private static func acceptsRenamedDirectCondition() throws {
        let source = annotationLine(
            combo: "RENAMED_TOGGLE_B",
            extra: #", "material":"Renamed presentation label""#
        ) + directBody("RENAMED_TOGGLE_B")
        let environment = try resolved(source: source)
        let resolution = try comboResolution("RENAMED_TOGGLE_B", in: environment)
        try require(
            resolution.binding.definition == .undefined,
            "omitted renamed option must remain undefined"
        )
        try require(
            resolution.provenance == .annotationImplicitDisabledOption,
            "omitted renamed option must retain typed provenance"
        )
    }

    private static func omissionMatchesExplicitZeroBranch() throws {
        let source = shader(combo: "FEATURE_TOGGLE_A")
        let omitted = try resolved(source: source)
        let explicitZero = try resolved(
            source: source,
            explicitCombos: ["FEATURE_TOGGLE_A": 0]
        )
        let omittedPrepared = try preprocessed(source: source, environment: omitted)
        let explicitZeroPrepared = try preprocessed(
            source: source,
            environment: explicitZero
        )
        try require(
            omittedPrepared.source == explicitZeroPrepared.source,
            "omission and explicit zero must select the same disabled branch"
        )
        let resolution = try comboResolution("FEATURE_TOGGLE_A", in: explicitZero)
        try require(
            resolution.binding.definition == .defined(.integer(0)),
            "explicit zero must stay defined"
        )
        try require(
            resolution.provenance == .explicitResolvedMaterial,
            "explicit zero must keep explicit provenance"
        )
    }

    private static func acceptsRenamedMultiStageDirectConditions() throws {
        let combo = "DUAL_STAGE_TOGGLE_D"
        let vertexPath = "tests/implicit-disabled-option.vert"
        let fragmentPath = "tests/implicit-disabled-option.frag"
        let vertexSource = directBody(combo)
        let fragmentSource = annotationLine(
            combo: combo,
            extra: #", "material":"Multi-stage presentation label""#
        ) + directBody(combo)
        let stages = [
            stage(source: vertexSource, kind: .vertex, path: vertexPath),
            stage(source: fragmentSource, kind: .fragment, path: fragmentPath),
        ]

        for (kind, path, source) in [
            (SceneShaderContract.StageKind.vertex, vertexPath, vertexSource),
            (.fragment, fragmentPath, fragmentSource),
        ] {
            let omitted = try resolved(stage: kind, stages: stages)
            let omittedResolution = try comboResolution(combo, in: omitted)
            try require(
                omittedResolution.binding.definition == .undefined,
                "multi-stage omission must remain undefined"
            )
            try require(
                omittedResolution.provenance == .annotationImplicitDisabledOption,
                "multi-stage omission must retain typed provenance"
            )
            let omittedPrepared = try preprocessed(
                source: source,
                kind: kind,
                path: path,
                environment: omitted
            )
            try require(
                omittedPrepared.source.contains("selected = 0"),
                "multi-stage omission must select disabled branch"
            )
            try require(
                !omittedPrepared.source.contains("selected = 1"),
                "multi-stage omission must not select enabled branch"
            )

            let explicitOne = try resolved(
                stage: kind,
                stages: stages,
                explicitCombos: [combo: 1]
            )
            let explicitPrepared = try preprocessed(
                source: source,
                kind: kind,
                path: path,
                environment: explicitOne
            )
            try require(
                explicitPrepared.source.contains("selected = 1"),
                "multi-stage explicit one must select enabled branch"
            )
            try require(
                !explicitPrepared.source.contains("selected = 0"),
                "multi-stage explicit one must not select disabled branch"
            )
        }
    }

    private static func explicitOneWins() throws {
        let source = shader(combo: "FEATURE_TOGGLE_A")
        let environment = try resolved(
            source: source,
            explicitCombos: ["FEATURE_TOGGLE_A": 1]
        )
        let prepared = try preprocessed(source: source, environment: environment)
        try require(prepared.source.contains("selected = 1"), "explicit one must select enabled branch")
        try require(!prepared.source.contains("selected = 0"), "explicit one must not select disabled branch")
        let resolution = try comboResolution("FEATURE_TOGGLE_A", in: environment)
        try require(
            resolution.binding.definition == .defined(.integer(1)),
            "explicit one must stay defined"
        )
        try require(
            resolution.provenance == .explicitResolvedMaterial,
            "explicit one must keep explicit provenance"
        )
    }

    private static func rejectsNonExactForms() throws {
        let combo = "STRICT_TOGGLE_C"
        let annotation = annotationLine(combo: combo)
        let cases: [(String, String)] = [
            ("non-options", annotationLine(combo: combo, type: "slider") + directBody(combo)),
            ("options-field", annotationLine(combo: combo, extra: #", "options":[0,1]"#) + directBody(combo)),
            ("require-field", annotationLine(combo: combo, extra: #", "require":{"BASE":1}"#) + directBody(combo)),
            ("requireany-field", annotationLine(combo: combo, extra: #", "requireany":true"#) + directBody(combo)),
            ("other-field", annotationLine(combo: combo, extra: #", "mode":"alternate""#) + directBody(combo)),
            ("malformed-material", annotationLine(combo: combo, extra: #", "material":1"#) + directBody(combo)),
            ("duplicate", annotation + annotation + directBody(combo)),
            ("conflict", annotation + annotationLine(combo: combo, extra: #", "default":1"#) + directBody(combo)),
            ("conditional-annotation", "#if 1\n" + annotation + "#endif\n" + directBody(combo)),
            ("malformed-nesting", annotation + "#endif\n" + directBody(combo)),
            ("ifdef", annotation + "#ifdef \(combo)\nint selected = 1;\n#endif\n"),
            ("ifndef", annotation + "#ifndef \(combo)\nint selected = 0;\n#endif\n"),
            ("defined", annotation + "#if defined(\(combo))\nint selected = 1;\n#endif\n"),
            ("elif", annotation + "#if 0\nint selected = 0;\n#elif \(combo)\nint selected = 1;\n#endif\n"),
            ("negation", annotation + "#if !\(combo)\nint selected = 0;\n#endif\n"),
            ("comparison", annotation + "#if \(combo) == 1\nint selected = 1;\n#endif\n"),
            ("arithmetic", annotation + "#if \(combo) + 0\nint selected = 1;\n#endif\n"),
            ("define", annotation + "#define \(combo) 1\n" + directBody(combo)),
            ("undef", annotation + "#undef \(combo)\n" + directBody(combo)),
            ("macro-forwarding", annotation + "#define FORWARDED \(combo)\n" + directBody(combo)),
            ("ordinary-use", annotation + "int selected = \(combo);\n" + directBody(combo)),
            ("unused", annotation + "int selected = 0;\n"),
        ]
        for (name, source) in cases {
            switch resolve(source: source) {
            case .success:
                throw HarnessFailure(message: "\(name) unexpectedly admitted")
            case .failure(let failure):
                try require(
                    failure.code == .missingDefault,
                    "\(name) must preserve missing-default, got \(failure.code.rawValue)"
                )
            }
        }
    }

    private static func shader(combo: String) -> String {
        annotationLine(combo: combo) + directBody(combo)
    }

    private static func annotationLine(
        combo: String,
        type: String = "options",
        extra: String = ""
    ) -> String {
        "// [COMBO] {\"combo\":\"\(combo)\",\"type\":\"\(type)\"\(extra)}\n"
    }

    private static func directBody(_ combo: String) -> String {
        "#if \(combo)\nint selected = 1;\n#else\nint selected = 0;\n#endif\n"
    }

    private static func resolve(
        source: String,
        explicitCombos: [String: Int] = [:]
    ) -> Result<SceneShaderVariantEnvironment, SceneShaderVariantResolver.Failure> {
        SceneShaderVariantResolver.resolve(
            stage: .fragment,
            stages: [stage(source: source)],
            explicitCombos: explicitCombos
        )
    }

    private static func resolved(
        source: String,
        explicitCombos: [String: Int] = [:]
    ) throws -> SceneShaderVariantEnvironment {
        switch resolve(source: source, explicitCombos: explicitCombos) {
        case .success(let environment): return environment
        case .failure(let failure):
            throw HarnessFailure(
                message: "resolution failed: \(failure.code.rawValue) \(failure.combo ?? "<none>")"
            )
        }
    }

    private static func resolved(
        stage kind: SceneShaderContract.StageKind,
        stages: [SceneShaderContract.Stage],
        explicitCombos: [String: Int] = [:]
    ) throws -> SceneShaderVariantEnvironment {
        switch SceneShaderVariantResolver.resolve(
            stage: kind,
            stages: stages,
            explicitCombos: explicitCombos
        ) {
        case .success(let environment): return environment
        case .failure(let failure):
            throw HarnessFailure(
                message: "multi-stage resolution failed: \(failure.code.rawValue) "
                    + "\(failure.combo ?? "<none>")"
            )
        }
    }

    private static func stage(
        source: String,
        kind: SceneShaderContract.StageKind = .fragment,
        path: String = "tests/implicit-disabled-option.frag"
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

    private static func preprocessed(
        source: String,
        kind: SceneShaderContract.StageKind = .fragment,
        path: String = "tests/implicit-disabled-option.frag",
        environment: SceneShaderVariantEnvironment
    ) throws -> SceneShaderPreparedSource {
        let stage = stage(source: source, kind: kind, path: path)
        let node = SceneShaderSourceGraph.Node(
            virtualPath: stage.relativePath,
            provenance: .loose,
            source: source,
            rawSHA256: stage.rawSHA256,
            byteCount: source.utf8.count
        )
        let graph = SceneShaderSourceGraph(
            roots: [.init(label: "fragment", virtualPath: stage.relativePath)],
            nodes: [node],
            edges: [],
            diagnostics: [],
            dependencySHA256: SceneShaderSourceGraph.dependencySHA256(
                nodes: [node],
                edges: []
            )
        )
        switch SceneShaderPreprocessor().preprocess(
            rootRelativePath: stage.relativePath,
            graph: graph,
            environment: environment
        ) {
        case .success(let prepared): return prepared
        case .failure(let failure):
            throw HarnessFailure(
                message: "preprocessing failed: \(failure.diagnostics.map(\.code.rawValue))"
            )
        }
    }

    private static func comboResolution(
        _ name: String,
        in environment: SceneShaderVariantEnvironment
    ) throws -> SceneShaderComboResolution {
        guard let resolution = environment.comboResolutions.first(where: {
            $0.binding.name == name
        }) else {
            throw HarnessFailure(message: "missing combo resolution for \(name)")
        }
        return resolution
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw HarnessFailure(message: message) }
    }

    private struct HarnessFailure: Error {
        let message: String
    }
}
