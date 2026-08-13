#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPO_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPO_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    *scene_swift_sources("shader_preprocessing_and_variant_implementation"),
]

HARNESS = r'''
import Foundation

private struct HarnessOutput: Codable {
    let checks: [String]
    let failure: String?
}

private struct LegacyAnnotationProjection: Encodable {
    let marker: String?
    let value: SceneJSONValue
    let raw: String
    let line: Int
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

private func node(_ path: String, _ source: String) -> SceneShaderSourceGraph.Node {
    .init(
        virtualPath: path,
        provenance: .loose,
        source: source,
        rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
        byteCount: source.utf8.count
    )
}

private func graph(
    rootPath: String,
    rootSource: String,
    includes: [String: String] = [:]
) -> SceneShaderSourceGraph {
    let rootNode = node(rootPath, rootSource)
    let parsed = SceneShaderContractSourceParser().parse(
        rootSource,
        stageRelativePath: rootPath
    )
    let directory = rootPath.split(separator: "/").dropLast().joined(separator: "/")
    var nodes = [rootNode]
    var edges: [SceneShaderSourceGraph.Edge] = []
    for include in parsed.includes {
        let path = directory.isEmpty
            ? include.relativePath
            : "\(directory)/\(include.relativePath)"
        if let source = includes[path] {
            let child = node(path, source)
            nodes.append(child)
            edges.append(.init(
                parentVirtualPath: rootPath,
                line: include.line,
                request: include.relativePath,
                candidates: [.init(
                    virtualPath: path,
                    provenance: .loose,
                    outcome: .resolved(rawSHA256: child.rawSHA256)
                )],
                outcome: .resolved(virtualPath: path)
            ))
        } else {
            edges.append(.init(
                parentVirtualPath: rootPath,
                line: include.line,
                request: include.relativePath,
                candidates: [],
                outcome: .missing
            ))
        }
    }
    return .init(
        roots: [.init(label: "fragment", virtualPath: rootPath)],
        nodes: nodes,
        edges: edges,
        diagnostics: [],
        dependencySHA256: SceneShaderStableDigest.hash(nodes)
    )
}

private func environment(
    _ combos: [SceneShaderMacroBinding] = []
) throws -> SceneShaderVariantEnvironment {
    try SceneShaderVariantEnvironment(stage: .fragment, combos: combos)
}

private func preprocess(
    _ source: String,
    environment: SceneShaderVariantEnvironment,
    includes: [String: String] = [:]
) -> Result<SceneShaderPreparedSource, SceneShaderPreprocessor.Failure> {
    let path = "shaders/main.frag"
    return SceneShaderPreprocessor().preprocess(
        rootRelativePath: path,
        graph: graph(rootPath: path, rootSource: source, includes: includes),
        environment: environment
    )
}

private func expectFailure(
    _ source: String,
    environment: SceneShaderVariantEnvironment,
    code: SceneShaderPreprocessor.DiagnosticCode,
    includes: [String: String] = [:]
) throws {
    switch preprocess(source, environment: environment, includes: includes) {
    case .success:
        throw HarnessFailure(description: "Expected preprocessor failure \(code.rawValue).")
    case let .failure(failure):
        try expect(
            failure.diagnostics.map(\.code) == [code],
            "Expected \(code.rawValue), got \(failure.diagnostics.map(\.code))."
        )
    }
}

private func makeStage(_ source: String) -> SceneShaderContract.Stage {
    let path = "shaders/variant.frag"
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

private func variant(
    _ stage: SceneShaderContract.Stage,
    explicit: [String: Int] = [:],
    readiness: [Int: Bool] = [:],
    formats: [Int: SceneShaderTextureFormat] = [:]
) -> Result<SceneShaderVariantEnvironment, SceneShaderVariantResolver.Failure> {
    SceneShaderVariantResolver.resolve(
        stage: .fragment,
        stages: [stage],
        explicitCombos: explicit,
        textureReadiness: readiness,
        textureFormats: formats
    )
}

private func resolved(
    _ result: Result<SceneShaderVariantEnvironment, SceneShaderVariantResolver.Failure>
) throws -> SceneShaderVariantEnvironment {
    switch result {
    case let .success(environment): return environment
    case let .failure(failure):
        throw HarnessFailure(description: "Expected variant, got \(failure).")
    }
}

private func failure(
    _ result: Result<SceneShaderVariantEnvironment, SceneShaderVariantResolver.Failure>
) throws -> SceneShaderVariantResolver.Failure {
    switch result {
    case .success:
        throw HarnessFailure(description: "Expected variant failure.")
    case let .failure(failure): return failure
    }
}

private func resolution(
    _ environment: SceneShaderVariantEnvironment,
    _ name: String
) throws -> SceneShaderComboResolution {
    guard let value = environment.comboResolutions.first(where: {
        $0.binding.name == name
    }) else {
        throw HarnessFailure(description: "Missing combo resolution for \(name).")
    }
    return value
}

private func runIdentityAndEnvironmentFixtures() throws -> [String] {
    let plain = try environment()
    try expect(
        plain.sourceDialect == .wallpaperEngineGLSLLike,
        "Authored source dialect was not explicit."
    )
    try expect(plain.backend == .mwxMetal, "Backend identity is not mwx-metal.")
    try expect(plain.environmentDefines.isEmpty, "Metal injected an unverified macro.")

    do {
        _ = try SceneShaderVariantEnvironment(
            stage: .fragment,
            environmentDefines: [.init(
                name: "VERSION",
                definition: .defined(.integer(2))
            )]
        )
        throw HarnessFailure(description: "Unverified environment injection was accepted.")
    } catch let failure as SceneShaderVariantFailure {
        try expect(
            failure.code == .unsupportedEnvironmentDefine,
            "Environment injection returned the wrong failure."
        )
    }

    for name in ["HLSL", "GLSL", "PLATFORM_ANDROID"] {
        do {
            _ = try environment([.init(
                name: name,
                definition: .defined(.integer(1))
            )])
            throw HarnessFailure(description: "Host-owned combo \(name) was accepted.")
        } catch let failure as SceneShaderVariantFailure {
            try expect(
                failure.code == .unsupportedEnvironmentDefine,
                "Host-owned combo \(name) returned the wrong failure."
            )
        }
    }

    do {
        _ = try environment([.init(
            name: "MODE",
            definition: .defined(.tokenSequence("OTHER_MODE"))
        )])
        throw HarnessFailure(description: "A combo injected a source macro token sequence.")
    } catch let failure as SceneShaderVariantFailure {
        try expect(
            failure.code == .invalidValue,
            "Source-only macro tokens returned the wrong combo failure."
        )
    }

    let ordered = try environment([
        .init(name: "MODE", definition: .defined(.integer(2))),
        .init(name: "mode", definition: .defined(.integer(1))),
    ])
    let reversed = try environment([
        .init(name: "mode", definition: .defined(.integer(1))),
        .init(name: "MODE", definition: .defined(.integer(2))),
    ])
    try expect(
        ordered.variantSHA256 == reversed.variantSHA256,
        "Equivalent case-sensitive bindings were not deterministic."
    )
    try expect(
        ordered.combos.map(\.name) == ["MODE", "mode"],
        "Case-sensitive macro identities collapsed."
    )

    let caseSchema = makeStage(
        """
        uniform float u_Upper; // [COMBO] {"combo":"MODE"}
        uniform float u_Lower; // [COMBO] {"combo":"mode"}
        """
    )
    let versioned = try resolved(variant(
        caseSchema,
        explicit: ["MODE": 2, "mode": 1]
    ))
    try expect(
        versioned.combos.map(\.name) == ["MODE", "mode"],
        "Case-distinct authored combo names collapsed."
    )
    return ["dialect_backend", "controlled_environment", "case_digest"]
}

private func runEnvironmentRequirementFixtures() throws -> [String] {
    let plain = try environment()
    try expectFailure(
        "#if VERSION >= 2\nACTIVE\n#endif",
        environment: plain,
        code: .unresolvedEnvironmentDefine
    )
    try expectFailure(
        "float version = SHADERVERSION;",
        environment: plain,
        code: .unresolvedEnvironmentDefine
    )
    switch preprocess(
        "#ifdef HLSL_SM30\nBAD\n#else\nNON_HLSL\n#endif",
        environment: plain
    ) {
    case let .success(prepared):
        try expect(
            prepared.source == "NON_HLSL",
            "The GLSL-like frontend selected an HLSL backend branch."
        )
    case let .failure(failure):
        throw HarnessFailure(description: "Known non-HLSL branch failed: \(failure).")
    }
    try expectFailure(
        "#ifdef PLATFORM_ANDROID\nACTIVE\n#endif",
        environment: plain,
        code: .unresolvedEnvironmentDefine
    )
    switch preprocess(
        "#if TEX0FORMAT == 0\nACTIVE\n#endif",
        environment: plain
    ) {
    case let .success(prepared):
        try expect(
            prepared.source == "ACTIVE",
            "An absent texture-format macro was not zero in #if."
        )
    case let .failure(failure):
        throw HarnessFailure(description: "Absent texture format failed: \(failure).")
    }
    switch preprocess(
        "#ifdef TEX0FORMAT\nBAD\n#else\nABSENT\n#endif",
        environment: plain
    ) {
    case let .success(prepared):
        try expect(
            prepared.source == "ABSENT",
            "An absent texture-format macro became defined."
        )
    case let .failure(failure):
        throw HarnessFailure(description: "Texture #ifdef failed: \(failure).")
    }
    try expectFailure(
        "float format = TEX0FORMAT;",
        environment: plain,
        code: .unresolvedEnvironmentDefine
    )
    try expectFailure(
        "#define VERSION 2\n#if VERSION >= 2\nACTIVE\n#endif",
        environment: plain,
        code: .unresolvedEnvironmentDefine
    )
    try expectFailure(
        "#undef VERSION\nSAFE",
        environment: plain,
        code: .unresolvedEnvironmentDefine
    )

    let schema = makeStage(
        """
        uniform float u_Mode; // [COMBO] {"combo":"MODE"}
        uniform float u_FormatMode; // [COMBO] {"combo":"FORMAT_MODE"}
        """
    )
    let typed = try resolved(variant(
        schema,
        explicit: ["MODE": 2, "FORMAT_MODE": 0]
    ))
    switch preprocess(
        "#if MODE >= 2 && FORMAT_MODE == 0\nACTIVE\n#endif",
        environment: typed
    ) {
    case let .success(prepared):
        try expect(prepared.source == "ACTIVE", "Typed macro source selected wrong branch.")
        try expect(
            prepared.sourceDialect == .wallpaperEngineGLSLLike
                && prepared.backend == .mwxMetal,
            "Prepared source collapsed dialect and backend identities."
        )
    case let .failure(failure):
        throw HarnessFailure(description: "Typed environment failed: \(failure).")
    }
    switch preprocess(
        "#define MODE 2\n#if MODE == 2\nSAME_VALUE\n#endif",
        environment: typed
    ) {
    case let .success(prepared):
        try expect(
            prepared.source == "SAME_VALUE",
            "A selected macro could not be repeated with the same value."
        )
    case let .failure(failure):
        throw HarnessFailure(description: "Same-value macro failed: \(failure).")
    }
    try expectFailure(
        "#undef MODE\nBAD",
        environment: typed,
        code: .conflictingMacro
    )

    let undeclared = try failure(SceneShaderVariantResolver.resolve(
        stage: .fragment,
        stages: [],
        explicitCombos: ["VERSION": 2, "TEX0FORMAT": 0]
    ))
    try expect(
        undeclared.code == .invalidEnvironment,
        "Undeclared environment-like material combo was accepted."
    )

    switch preprocess(
        "#if 0\n#if VERSION > 0\nBAD\n#endif\n#endif\nSAFE",
        environment: plain
    ) {
    case let .success(prepared):
        try expect(prepared.source == "SAFE", "Inactive environment branch was evaluated.")
    case let .failure(failure):
        throw HarnessFailure(description: "Inactive branch failed: \(failure).")
    }
    return ["unknown_environment", "typed_values", "inactive_condition"]
}

private func runReadinessFixtures() throws -> [String] {
    let stage = makeStage(
        "uniform sampler2D g_Texture2; // {\"combo\":\"HAS_TEXTURE\",\"default\":\"textures/mask\",\"options\":{\"ignored\":7}}"
    )
    let ready = try resolved(variant(stage, readiness: [2: true]))
    let readyResolution = try resolution(ready, "HAS_TEXTURE")
    try expect(
        readyResolution.binding.definition == .defined(.integer(1))
            && readyResolution.provenance == .textureReadiness
            && readyResolution.validatedTextureSlots == [2],
        "Ready texture did not produce readiness provenance."
    )
    let missing = try resolved(variant(stage, readiness: [2: false]))
    let missingResolution = try resolution(missing, "HAS_TEXTURE")
    try expect(
        missingResolution.binding.definition == .undefined
            && missingResolution.provenance == .textureReadiness,
        "Missing texture did not remain undefined with provenance."
    )
    try expectFailure(
        "#define HAS_TEXTURE 1\n#ifdef HAS_TEXTURE\nBAD\n#endif",
        environment: missing,
        code: .conflictingMacro
    )
    let unknown = try failure(variant(stage))
    try expect(
        unknown.code == .textureReadinessUnavailable,
        "Unknown sampler readiness was collapsed into an explicit missing texture."
    )

    let multipleUnknown = makeStage(
        """
        uniform sampler2D g_Texture2; // {"combo":"ZETA"}
        uniform sampler2D g_Texture1; // {"combo":"ALPHA"}
        """
    )
    let orderedUnknown = try failure(variant(multipleUnknown))
    try expect(
        orderedUnknown.code == .textureReadinessUnavailable
            && orderedUnknown.combo == "ALPHA",
        "Multiple missing readiness providers did not produce a deterministic first diagnostic."
    )

    let explicitReady = try resolved(variant(
        stage,
        explicit: ["HAS_TEXTURE": 1],
        readiness: [2: true]
    ))
    let explicitResolution = try resolution(explicitReady, "HAS_TEXTURE")
    try expect(
        explicitResolution.provenance == .explicitResolvedMaterial
            && explicitResolution.validatedTextureSlots == [2],
        "Matching explicit combo lost its selected and validated sources."
    )
    try expect(
        explicitReady.variantSHA256 == ready.variantSHA256,
        "Equivalent final variants changed digest only because provenance differed."
    )

    for (value, isReady) in [(1, false), (0, true), (0, false)] {
        let conflict = try failure(variant(
            stage,
            explicit: ["HAS_TEXTURE": value],
            readiness: [2: isReady]
        ))
        try expect(
            conflict.code == .explicitTextureReadinessConflict,
            "Explicit/readiness conflict was silently overwritten."
        )
    }

    let shared = makeStage(
        """
        uniform sampler2D g_Texture1; // {"combo":"SHARED_TEXTURE"}
        uniform sampler2D g_Texture2; // {"combo":"SHARED_TEXTURE"}
        """
    )
    let sharedFailure = try failure(variant(
        shared,
        readiness: [1: true, 2: false]
    ))
    try expect(
        sharedFailure.code == .conflictingTextureReadiness,
        "Conflicting slots selected one readiness value by iteration order."
    )

    let authoredSampler = makeStage(
        "uniform sampler2D g_Texture3; // [COMBO] {\"combo\":\"AUTHORED\",\"default\":1}"
    )
    let authored = try resolved(variant(authoredSampler, readiness: [3: false]))
    let authoredResolution = try resolution(authored, "AUTHORED")
    try expect(
        authoredResolution.binding.definition == .defined(.integer(1))
            && authoredResolution.provenance == .annotationDefault
            && authoredResolution.validatedTextureSlots.isEmpty,
        "Exact [COMBO] was conflated with sampler readiness metadata."
    )

    let unmarkedUniform = makeStage(
        "uniform float u_Bad; // {\"combo\":\"BAD\",\"default\":1}"
    )
    let unmarkedFailure = try failure(variant(unmarkedUniform))
    try expect(
        unmarkedFailure.code == .invalidAnnotation,
        "Unmarked non-sampler combo metadata entered the variant schema."
    )

    let disabled = makeStage(
        "uniform float u_Disabled; // [COMBO_OFF] {\"combo\":\"DISABLED\",\"default\":1}"
    )
    let disabledFailure = try failure(variant(disabled))
    try expect(
        disabledFailure.code == .disabledComboAnnotation,
        "Disabled combo marker was silently ignored or enabled."
    )
    let disabledZero = makeStage(
        "uniform float u_Disabled; // [COMBO_OFF] {\"combo\":\"DISABLED\",\"default\":0,\"options\":[0,1]}"
    )
    let disabledZeroEnvironment = try resolved(variant(disabledZero))
    let disabledZeroResolution = try resolution(
        disabledZeroEnvironment,
        "DISABLED"
    )
    try expect(
        disabledZeroResolution.binding.definition == .defined(.integer(0))
            && disabledZeroResolution.schemaDeclared,
        "An exact disabled-zero combo did not stay disabled."
    )
    let disabledOverride = try failure(variant(
        disabledZero,
        explicit: ["DISABLED": 1]
    ))
    try expect(
        disabledOverride.code == .disabledComboAnnotation,
        "Authored data overrode an explicitly disabled combo."
    )
    for source in [
        "uniform float u_MissingDefault; // [COMBO_OFF] {\"combo\":\"DISABLED\"}",
        "uniform float u_BooleanDefault; // [COMBO_OFF] {\"combo\":\"DISABLED\",\"default\":false}",
        "uniform float u_EmptyRequirement; // [COMBO_OFF] {\"combo\":\"DISABLED\",\"default\":0,\"require\":{}}",
        "uniform float u_FalseRequireAny; // [COMBO_OFF] {\"combo\":\"DISABLED\",\"default\":0,\"requireany\":false}",
    ] {
        let strictDisabledFailure = try failure(variant(makeStage(source)))
        try expect(
            strictDisabledFailure.code == .disabledComboAnnotation,
            "A disabled combo without an exact zero-only contract was accepted."
        )
    }

    let outOfRangeInteger = makeStage(
        "uniform float u_Large; // [COMBO] {\"combo\":\"LARGE\",\"default\":9223372036854775808}"
    )
    let outOfRangeFailure = try failure(variant(outOfRangeInteger))
    try expect(
        outOfRangeFailure.code == .invalidAnnotation,
        "An out-of-range combo integer was accepted or trapped."
    )

    for marker in ["[combo]", "[combo_off]", "OFF_COMBO"] {
        let approximate = makeStage(
            "uniform float u_Approx; // \(marker) {\"combo\":\"APPROX\",\"default\":1}"
        )
        let approximateFailure = try failure(variant(approximate))
        try expect(
            approximateFailure.code == .invalidAnnotation,
            "Approximate combo marker '\(marker)' was enabled or recognized as exact."
        )
    }
    for source in [
        "uniform float u_Missing; // [COMBO] {\"default\":1}",
        "uniform float u_DisabledMissing; // [COMBO_DISABLED] {\"default\":1}",
        "uniform float u_DisabledScalar; // [OFF_COMBO] 1",
    ] {
        let malformedMarkerFailure = try failure(variant(makeStage(source)))
        try expect(
            malformedMarkerFailure.code == .invalidAnnotation,
            "Variant marker without an object and combo identifier was ignored."
        )
    }
    return [
        "readiness_provenance", "deterministic_readiness_failure",
        "explicit_conflicts", "shared_slot_conflict",
        "typed_schema_origins", "disabled_combo_diagnostic",
    ]
}

private func runExactIntegerFixtures() throws -> [String] {
    let exactValue: Int64 = 9_007_199_254_740_993
    let exactStage = makeStage(
        "uniform float u_Mode; // [COMBO] {\"combo\":\"MODE\",\"default\":9007199254740993,\"options\":[9007199254740993]}"
    )
    let exactEnvironment = try resolved(variant(exactStage))
    let exactResolution = try resolution(exactEnvironment, "MODE")
    try expect(
        exactResolution.binding.definition
            == .defined(.integer(exactValue)),
        "A legal Int64 shader annotation was rounded through Double."
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let annotation = exactStage.annotations.first else {
        throw HarnessFailure(description: "Exact Int64 annotation was not parsed.")
    }
    let legacyProjection = LegacyAnnotationProjection(
        marker: annotation.marker,
        value: annotation.value,
        raw: annotation.raw,
        line: annotation.line
    )
    let exactEncoding = try encoder.encode(annotation)
    let legacyEncoding = try encoder.encode(legacyProjection)
    try expect(
        exactEncoding == legacyEncoding,
        "Exact variant metadata changed the R1 canonical annotation projection."
    )
    let decodedAnnotation = try JSONDecoder().decode(
        SceneShaderContract.Annotation.self,
        from: exactEncoding
    )
    guard case let .object(decodedObject) = decodedAnnotation.variantValue else {
        throw HarnessFailure(description: "Decoded annotation lost its exact variant object.")
    }
    try expect(
        decodedObject["default"]?.integerValue == exactValue,
        "Codable round-trip lost the exact Int64 variant value."
    )
    switch preprocess(
        "#if MODE == 9007199254740993\nCORRECT\n#else\nWRONG\n#endif",
        environment: exactEnvironment
    ) {
    case let .success(prepared):
        try expect(prepared.source == "CORRECT", "Exact Int64 selected the wrong variant.")
    case let .failure(failure):
        throw HarnessFailure(description: "Exact Int64 preprocessing failed: \(failure).")
    }

    let maximumStage = makeStage(
        "uniform float u_Max; // [COMBO] {\"combo\":\"MAXIMUM\",\"default\":9223372036854775807}"
    )
    let maximumEnvironment = try resolved(variant(maximumStage))
    let maximumResolution = try resolution(maximumEnvironment, "MAXIMUM")
    try expect(
        maximumResolution.binding.definition
            == .defined(.integer(Int64.max)),
        "Int64.max was rounded or rejected by shader annotation parsing."
    )
    let minimumStage = makeStage(
        "uniform float u_Min; // [COMBO] {\"combo\":\"MINIMUM\",\"default\":-9223372036854775808}"
    )
    let minimumEnvironment = try resolved(variant(minimumStage))
    let minimumResolution = try resolution(minimumEnvironment, "MINIMUM")
    try expect(
        minimumResolution.binding.definition
            == .defined(.integer(Int64.min)),
        "Int64.min was rounded or rejected by shader annotation parsing."
    )
    for source in [
        "uniform float u_PositiveOverflow; // [COMBO] {\"combo\":\"POSITIVE_OVERFLOW\",\"default\":9223372036854775808}",
        "uniform float u_NegativeOverflow; // [COMBO] {\"combo\":\"NEGATIVE_OVERFLOW\",\"default\":-9223372036854775809}",
    ] {
        let overflowFailure = try failure(variant(makeStage(source)))
        try expect(
            overflowFailure.code == .invalidAnnotation,
            "An out-of-range integer annotation entered the variant environment."
        )
    }
    let unsafeLegacy = SceneShaderContract.Annotation(
        marker: "[COMBO]",
        value: .object([
            "combo": .string("UNSAFE_LEGACY"),
            "default": .number(9_007_199_254_740_992),
        ]),
        raw: "legacy-projection-without-source",
        line: 1
    )
    let unsafeLegacyStage = SceneShaderContract.Stage(
        kind: .fragment,
        relativePath: "shaders/test.frag",
        source: "",
        rawSHA256: SceneShaderStableDigest.hash(Data()),
        includes: [],
        annotations: [unsafeLegacy],
        declarations: []
    )
    let unsafeLegacyFailure = try failure(variant(unsafeLegacyStage))
    try expect(
        unsafeLegacyFailure.code == .invalidAnnotation,
        "A rounded legacy Double entered the exact integer variant path."
    )
    let roundedFraction = makeStage(
        "uniform float u_Fraction; // [COMBO] {\"combo\":\"FRACTION\",\"default\":9007199254740993.5}"
    )
    let roundedFractionFailure = try failure(variant(roundedFraction))
    try expect(
        roundedFractionFailure.code == .invalidAnnotation,
        "An unsafe fractional annotation rounded into an integer variant."
    )
    let explicitRoundedFractionFailure = try failure(variant(
        roundedFraction,
        explicit: ["FRACTION": 1]
    ))
    try expect(
        explicitRoundedFractionFailure.code == .invalidAnnotation,
        "An explicit value hid a malformed annotation default."
    )
    return ["exact_int64_annotations", "explicit_malformed_default"]
}

private func runRequirementProviderFixtures() throws -> [String] {
    let hostNames = [
        "VERSION", "SHADERVERSION", "HLSL", "GLSL",
        "PLATFORM_ANDROID", "TEX0FORMAT", "THICKFORMAT",
    ]
    for (index, name) in hostNames.enumerated() {
        let dependent = makeStage(
            "uniform float u_Dep\(index); // [COMBO] {\"combo\":\"DEPENDENT_\(index)\",\"default\":1,\"require\":{\"\(name)\":0}}"
        )
        let environment = try resolved(variant(dependent))
        let resolution = try resolution(environment, "DEPENDENT_\(index)")
        try expect(
            resolution.binding.definition == .defined(.integer(1))
                && resolution.provenance == .annotationDefault,
            "Editor-only requirement \(name) pruned a player combo default."
        )
    }

    let typed = makeStage(
        """
        uniform float u_Version; // [COMBO] {"combo":"VERSION","default":0}
        uniform float u_Format; // [COMBO] {"combo":"TEX0FORMAT","default":0}
        uniform float u_Dependent; // [COMBO] {"combo":"DEPENDENT","default":1,"require":{"VERSION":0,"TEX0FORMAT":0}}
        """
    )
    let typedFailure = try failure(variant(typed))
    try expect(
        typedFailure.code == .invalidEnvironment,
        "Authored VERSION/format schemas were mistaken for verified host facts."
    )

    let formatStage = makeStage(
        "uniform sampler2D g_Texture2; // {\"formatcombo\":true}"
    )
    let formatEnvironment = try resolved(variant(
        formatStage,
        formats: [2: .r8]
    ))
    let formatResolution = formatEnvironment.comboResolutions.first {
        $0.binding.name == "TEX2FORMAT"
    }
    try expect(
        formatResolution?.binding.definition == .defined(.integer(9))
            && formatResolution?.provenance == .textureFormat
            && formatResolution?.validatedTextureSlots == [2],
        "Verified authored TEX format did not become a typed host macro."
    )
    let missingFormat = try failure(variant(formatStage))
    try expect(
        missingFormat.code == .textureFormatUnavailable
            && missingFormat.combo == "TEX2FORMAT",
        "Unknown authored TEX format did not fail closed."
    )
    let combinedFormat = makeStage(
        "uniform sampler2D g_Texture1; // {\"combo\":\"NORMALMAP\",\"formatcombo\":true}"
    )
    let combinedEnvironment = try resolved(variant(
        combinedFormat,
        readiness: [1: true],
        formats: [1: .rg88]
    ))
    try expect(
        combinedEnvironment.comboResolutions.contains {
            $0.binding.name == "NORMALMAP"
                && $0.provenance == .textureReadiness
        } && combinedEnvironment.comboResolutions.contains {
            $0.binding.name == "TEX1FORMAT"
                && $0.binding.definition == .defined(.integer(8))
                && $0.provenance == .textureFormat
        },
        "Sampler readiness and formatcombo metadata did not remain independent."
    )

    let unmarked = makeStage(
        """
        uniform float u_Version; // {"combo":"VERSION","default":0}
        uniform float u_Dependent; // [COMBO] {"combo":"DEPENDENT","default":1,"require":{"VERSION":0}}
        """
    )
    let unmarkedFailure = try failure(variant(unmarked))
    try expect(
        unmarkedFailure.code == .invalidAnnotation,
        "Unmarked non-sampler VERSION metadata was accepted as a schema."
    )

    for name in ["HLSL", "PLATFORM_ANDROID"] {
        let hostOwned = makeStage(
            """
            uniform float u_Host; // [COMBO] {"combo":"\(name)","default":0}
            uniform float u_Dependent; // [COMBO] {"combo":"DEPENDENT","default":1,"require":{"\(name)":0}}
            """
        )
        let hostFailure = try failure(variant(hostOwned))
        try expect(
            hostFailure.code == .invalidEnvironment,
            "Host-owned \(name) requirement was accepted through a combo schema."
        )
    }

    let ordinary = makeStage(
        "uniform float u_Dependent; // [COMBO] {\"combo\":\"DEPENDENT\",\"default\":2,\"require\":{\"ordinary_missing\":0}}"
    )
    let ordinaryEnvironment = try resolved(variant(ordinary))
    let ordinaryResolution = try resolution(ordinaryEnvironment, "DEPENDENT")
    try expect(
        ordinaryResolution.binding.definition == .defined(.integer(2)),
        "Missing editor-only requirement provider pruned a player combo default."
    )

    let multipleMissing = makeStage(
        "uniform float u_Dependent; // [COMBO] {\"combo\":\"DEPENDENT\",\"default\":1,\"require\":{\"ZETA\":0,\"ALPHA\":0}}"
    )
    let orderedMissing = try resolved(variant(multipleMissing))
    let orderedMissingResolution = try resolution(orderedMissing, "DEPENDENT")
    try expect(
        orderedMissingResolution.binding.definition == .defined(.integer(1)),
        "Multiple editor-only requirements changed the player compile map."
    )

    let samplerHostRequirement = makeStage(
        "uniform sampler2D g_Texture2; // {\"combo\":\"MASK\",\"require\":{\"VERSION\":0}}"
    )
    let samplerHostFailure = try failure(variant(
        samplerHostRequirement,
        readiness: [2: true]
    ))
    try expect(
        samplerHostFailure.code == .invalidEnvironment,
        "Unverified host requirement entered runtime sampler selection."
    )
    let samplerMissingRequirement = makeStage(
        "uniform sampler2D g_Texture2; // {\"combo\":\"MASK\",\"require\":{\"MISSING\":1}}"
    )
    let samplerMissingFailure = try failure(variant(
        samplerMissingRequirement,
        readiness: [2: true]
    ))
    try expect(
        samplerMissingFailure.code == .unresolvedRequirement,
        "Missing runtime sampler requirement did not fail closed."
    )

    let declaredUndefined = makeStage(
        """
        uniform float u_Base; // [COMBO] {"combo":"BASE"}
        uniform float u_Dependent; // [COMBO] {"combo":"DEPENDENT","default":2,"require":{"BASE":0}}
        """
    )
    let declaredFailure = try failure(variant(declaredUndefined))
    try expect(
        declaredFailure.code == .missingDefault && declaredFailure.combo == "BASE",
        "A combo with neither material value nor annotation default did not fail closed."
    )
    let explicitWithoutDefault = try resolved(variant(
        declaredUndefined,
        explicit: ["BASE": 0]
    ))
    let explicitWithoutDefaultResolution = try resolution(
        explicitWithoutDefault,
        "BASE"
    )
    try expect(
        explicitWithoutDefaultResolution.provenance == .explicitResolvedMaterial,
        "An explicit material value did not satisfy a combo with no fallback default."
    )

    let explicitProvider = makeStage(
        """
        uniform float u_Enable; // [COMBO] {"combo":"ENABLE","default":0}
        uniform sampler2D g_Texture2; // {"combo":"MASK","require":{"ENABLE":1}}
        """
    )
    let explicitEnvironment = try resolved(variant(
        explicitProvider,
        explicit: ["ENABLE": 1],
        readiness: [2: true]
    ))
    let explicitResolution = try resolution(explicitEnvironment, "MASK")
    try expect(
        explicitResolution.binding.definition == .defined(.integer(1))
            && explicitResolution.provenance == .textureReadiness,
        "Resolved material combo was not available to a runtime resource requirement."
    )

    let mutuallyExclusiveOptions = makeStage(
        """
        uniform float u_Select; // [COMBO] {"combo":"SELECT","options":[1,2]}
        uniform float u_First; // [COMBO] {"combo":"MODE","default":1,"options":[1],"require":{"SELECT":1}}
        uniform float u_Second; // [COMBO] {"combo":"MODE","default":2,"options":[2],"require":{"SELECT":2}}
        """
    )
    let selectedFirst = try failure(variant(
        mutuallyExclusiveOptions,
        explicit: ["SELECT": 1]
    ))
    try expect(
        selectedFirst.code == .conflictingDefault,
        "Conflicting duplicate combo defaults used editor requirements as runtime ordering."
    )
    let explicitConflict = try failure(variant(
        mutuallyExclusiveOptions,
        explicit: ["SELECT": 1, "MODE": 1]
    ))
    try expect(
        explicitConflict.code == .conflictingDefault,
        "An explicit combo value hid conflicting annotation defaults."
    )
    let incompleteDuplicate = makeStage(
        """
        uniform float u_First; // [COMBO] {"combo":"MODE","default":1}
        uniform float u_Second; // [COMBO] {"combo":"MODE"}
        """
    )
    let incompleteFailure = try failure(variant(incompleteDuplicate))
    try expect(
        incompleteFailure.code == .missingDefault,
        "One duplicate annotation supplied a fallback for another missing default."
    )

    let readinessProvider = makeStage(
        """
        uniform sampler2D g_Texture1; // {"combo":"MASK"}
        uniform sampler2D g_Texture2; // {"combo":"MASKED","require":{"MASK":1}}
        """
    )
    let readinessEnvironment = try resolved(variant(
        readinessProvider,
        readiness: [1: true, 2: true]
    ))
    let readinessResolution = try resolution(readinessEnvironment, "MASKED")
    try expect(
        readinessResolution.binding.definition == .defined(.integer(1)),
        "Texture readiness did not participate in the bounded requirement fixed point."
    )

    let negativeDependency = makeStage(
        """
        uniform float u_Base; // [COMBO] {"combo":"BASE","default":1,"require":{"TRIGGER":1}}
        uniform float u_Dependent; // [COMBO] {"combo":"DEPENDENT","default":1,"require":{"BASE":0}}
        """
    )
    let negativeEnvironment = try resolved(variant(
        negativeDependency,
        explicit: ["TRIGGER": 1]
    ))
    let negativeResolution = try resolution(negativeEnvironment, "DEPENDENT")
    try expect(
        negativeResolution.binding.definition == .defined(.integer(1))
            && negativeResolution.provenance == .annotationDefault,
        "An editor-only negative requirement pruned a player combo default."
    )

    let staleReadiness = makeStage(
        """
        uniform sampler2D g_Texture3; // {"combo":"MASK","require":{"ENABLE":0}}
        uniform float u_Enable; // [COMBO] {"combo":"ENABLE","default":1,"require":{"TRIGGER":1}}
        """
    )
    let staleReadinessEnvironment = try resolved(variant(
        staleReadiness,
        explicit: ["TRIGGER": 1],
        readiness: [3: true]
    ))
    let staleReadinessResolution = try resolution(
        staleReadinessEnvironment,
        "MASK"
    )
    try expect(
        staleReadinessResolution.binding.definition == .undefined
            && staleReadinessResolution.provenance == .requirementInactive
            && staleReadinessResolution.validatedTextureSlots.isEmpty,
        "An inactive readiness branch retained stale provenance or texture slots."
    )

    let cyclicRequirements = makeStage(
        """
        uniform float u_First; // [COMBO] {"combo":"FIRST","default":1,"require":{"SECOND":0}}
        uniform float u_Second; // [COMBO] {"combo":"SECOND","default":1,"require":{"FIRST":0}}
        """
    )
    let cyclicEnvironment = try resolved(variant(cyclicRequirements))
    let firstCyclicResolution = try resolution(cyclicEnvironment, "FIRST")
    let secondCyclicResolution = try resolution(cyclicEnvironment, "SECOND")
    try expect(
        firstCyclicResolution.binding.definition == .defined(.integer(1))
            && secondCyclicResolution.binding.definition == .defined(.integer(1)),
        "Editor-only cyclic requirements changed the player compile map."
    )

    let requireAny = makeStage(
        """
        uniform float u_Base; // [COMBO] {"combo":"BASE","default":1}
        uniform float u_Dependent; // [COMBO] {"combo":"DEPENDENT","default":1,"require":{"BASE":1,"VERSION":0},"requireany":true}
        """
    )
    let requireAnyEnvironment = try resolved(variant(requireAny))
    let requireAnyResolution = try resolution(requireAnyEnvironment, "DEPENDENT")
    try expect(
        requireAnyResolution.binding.definition == .defined(.integer(1)),
        "Editor-only requireany changed the player compile map."
    )

    let invalidRequireAny = makeStage(
        "uniform float u_Bad; // [COMBO] {\"combo\":\"BAD\",\"requireany\":1}"
    )
    let invalidRequireAnyFailure = try failure(variant(invalidRequireAny))
    try expect(
        invalidRequireAnyFailure.code == .invalidAnnotation,
        "Non-boolean requireany annotation was accepted."
    )
    return [
        "editor_requirements_ignored", "typed_requirement", "ordinary_requirement",
        "typed_texture_format", "unknown_texture_format_fail_closed",
        "combined_readiness_format",
        "runtime_requirement_fail_closed",
        "missing_default_fail_closed", "explicit_without_default",
        "explicit_requirement_provider", "conflicting_default_with_explicit",
        "duplicate_missing_default", "readiness_requirement_provider",
        "negative_requirement_default_fill", "stale_readiness_pruning",
        "cyclic_editor_requirement_default_fill", "requireany_type",
    ]
}

private func runIncludeDiagnosticFixtures() throws -> [String] {
    let malformed = "uniform float u_Bad; // [COMBO] {broken"
    let plain = try environment()
    try expectFailure(
        "#include \"bad.inc\"\nROOT",
        environment: plain,
        code: .malformedSourceAnnotation,
        includes: ["shaders/bad.inc": malformed]
    )

    switch preprocess(
        "#if 0\n#include \"bad.inc\"\n#endif\nSAFE",
        environment: plain,
        includes: ["shaders/bad.inc": malformed]
    ) {
    case let .success(prepared):
        try expect(prepared.source == "SAFE", "Inactive include changed prepared source.")
        try expect(
            prepared.dependencies.map(\.relativePath) == ["shaders/main.frag"],
            "Inactive malformed include entered active dependencies."
        )
    case let .failure(failure):
        throw HarnessFailure(description: "Inactive malformed include failed: \(failure).")
    }
    return ["active_include_diagnostic", "inactive_include_safe"]
}

@main
private struct SceneShaderVariantEnvironmentHarness {
    static func main() {
        do {
            let checks = try runIdentityAndEnvironmentFixtures()
                + runEnvironmentRequirementFixtures()
                + runReadinessFixtures()
                + runExactIntegerFixtures()
                + runRequirementProviderFixtures()
                + runIncludeDiagnosticFixtures()
            emit(.init(checks: checks, failure: nil))
        } catch {
            emit(.init(checks: [], failure: String(describing: error)))
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


class SceneShaderVariantEnvironmentTests(unittest.TestCase):
    def test_variant_environment_readiness_and_include_diagnostics(self):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory() as temporary_directory:
            build_root = Path(temporary_directory)
            harness = build_root / "SceneShaderVariantEnvironmentHarness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = build_root / "scene-shader-variant-environment-harness"
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
                cwd=REPO_ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        output = json.loads(completed.stdout)
        self.assertIsNone(output.get("failure"), output.get("failure"))
        self.assertEqual(
            output["checks"],
            [
                "dialect_backend",
                "controlled_environment",
                "case_digest",
                "unknown_environment",
                "typed_values",
                "inactive_condition",
                "readiness_provenance",
                "deterministic_readiness_failure",
                "explicit_conflicts",
                "shared_slot_conflict",
                "typed_schema_origins",
                "disabled_combo_diagnostic",
                "exact_int64_annotations",
                "explicit_malformed_default",
                "editor_requirements_ignored",
                "typed_requirement",
                "ordinary_requirement",
                "typed_texture_format",
                "unknown_texture_format_fail_closed",
                "combined_readiness_format",
                "runtime_requirement_fail_closed",
                "missing_default_fail_closed",
                "explicit_without_default",
                "explicit_requirement_provider",
                "conflicting_default_with_explicit",
                "duplicate_missing_default",
                "readiness_requirement_provider",
                "negative_requirement_default_fill",
                "stale_readiness_pruning",
                "cyclic_editor_requirement_default_fill",
                "requireany_type",
                "active_include_diagnostic",
                "inactive_include_safe",
            ],
        )


if __name__ == "__main__":
    unittest.main()
