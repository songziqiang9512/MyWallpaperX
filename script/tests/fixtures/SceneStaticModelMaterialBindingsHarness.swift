import Foundation

private typealias Bindings = SceneStaticModelMaterialBindings
private typealias Pass = SceneRenderDescriptor.MaterialPassDescriptor
private typealias Value = SceneDocument.ShaderValue

/// Self-authored declaration-only shader stages. The constant output is
/// intentionally unrelated to any Workshop asset or official shader body.
private func shader(
    alphaKey: String = "Alpha",
    colorKey: String = "Color",
    brightnessKey: String = "Brigtness",
    alphaDefault: String = "0.125",
    colorDefault: String = "[0.25,0.5,0.75]",
    brightnessDefault: String = "1.75",
    alphaType: String = "float",
    alphaSuffix: String = "",
    fragmentPrefix: String = "",
    fragmentExtra: String = "",
    vertexExtra: String = "",
    customAlphaAnnotation: String? = nil,
    conditionalAlpha: Bool = false,
    includedSources: [String: String] = [:],
    identity: String = "fixture/static-material-keys"
) -> SceneShaderContract {
    let alphaAnnotation = customAlphaAnnotation
        ?? "{\"material\":\"\(alphaKey)\",\"default\":\(alphaDefault)}"
    let ordinaryAlpha = "uniform \(alphaType) g_TintAlpha\(alphaSuffix); // \(alphaAnnotation)"
    let alpha = conditionalAlpha ? """
    // [COMBO] {"combo":"ACTIVE","default":1,"options":[0,1]}
    #if ACTIVE
    \(ordinaryAlpha)
    #else
    uniform float g_TintAlpha; // {"material":"alpha","default":1}
    #endif
    """ : ordinaryAlpha
    let vertex = """
    attribute vec3 a_Position;
    \(vertexExtra)
    void main() { gl_Position = vec4(a_Position, 1.0); }
    """
    let fragment = """
    \(fragmentPrefix)
    \(alpha)
    uniform vec3 g_TintColor; // {"material":"\(colorKey)","default":\(colorDefault)}
    uniform float g_Brightness; // {"material":"\(brightnessKey)","default":\(brightnessDefault)}
    \(fragmentExtra)
    void main() { gl_FragColor = vec4(1.0); }
    """
    func stage(_ kind: SceneShaderContract.StageKind, _ source: String) -> SceneShaderContract.Stage {
        let path = "\(identity).\(kind == .vertex ? "vert" : "frag")"
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
        return .init(
            kind: kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes, annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let stages = [stage(.vertex, vertex), stage(.fragment, fragment)]
    var nodes: [SceneShaderSourceGraph.Node] = stages.map {
        .init(
            virtualPath: $0.relativePath, provenance: .package,
            source: $0.source, rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count
        )
    }
    nodes += includedSources.sorted { $0.key < $1.key }.map { path, source in
        .init(virtualPath: path, provenance: .package, source: source,
              rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), byteCount: source.utf8.count)
    }
    let edges: [SceneShaderSourceGraph.Edge] = nodes.flatMap { node in
        SceneShaderContractSourceParser().parse(node.source, stageRelativePath: node.virtualPath)
            .includes.map { include in
                .init(parentVirtualPath: node.virtualPath, line: include.line,
                      request: include.relativePath, candidates: [],
                      outcome: includedSources[include.relativePath] == nil
                        ? .missing : .resolved(virtualPath: include.relativePath))
            }
    }
    let dependency = SceneShaderSourceGraph.dependencySHA256(nodes: nodes, edges: edges)
    return .init(
        identity: identity, sourceKind: .authoredSource,
        stages: stages, diagnostics: [], canonicalSHA256: dependency,
        sourceGraph: .init(
            roots: stages.map { .init(label: $0.kind.rawValue, virtualPath: $0.relativePath) },
            nodes: nodes, edges: edges, diagnostics: [], dependencySHA256: dependency
        )
    )
}

private func constant(_ components: [Double], raw: String? = nil, kind: String? = nil) -> Value {
    .init(userBinding: nil, userValueKind: nil, components: components, bindingKeys: [], rawValue: raw, valueKind: kind)
}

private func wrapper(
    _ propertyKey: String, _ components: [Double], keys: [String] = ["user", "value"],
    raw: String? = nil, kind: String? = nil
) -> Value {
    .init(userBinding: propertyKey, userValueKind: .string, components: components, bindingKeys: keys, rawValue: raw, valueKind: kind)
}

private func pass(
    constants: [String: Value] = [:],
    materialPath: String = "materials/keys.json",
    shaderPath: String = "fixture/static-material-keys",
    passIndex: Int = 0,
    combos: [String: Int] = [:]
) -> Pass {
    var result = Pass(materialPath: materialPath, passIndex: passIndex, constantShaderValues: constants)
    result.shaderPath = shaderPath
    result.combos = combos
    return result
}

private func compile(_ pass: Pass, _ shader: SceneShaderContract = shader()) -> Bindings {
    SceneStaticModelMaterialBindingCompiler.compile(pass: pass, shaderContracts: [shader])
}

private func summary(_ bindings: Bindings) -> [String: Any] {
    let channels: [Bindings.Channel] = [.alpha, .color, .brightness]
    let values = channels.compactMap { bindings.binding(for: $0) }
    return [
        "state": bindings.state.rawValue,
        "keys": values.map { $0.materialKey as Any? ?? NSNull() },
        "components": values.map(\.components),
        "reason": bindings.rejectionReason as Any? ?? NSNull(),
    ]
}

private func identities() -> [String: Any] {
    let both: [String: Value] = [
        "Alpha": constant([0.02]), "alpha": constant([0.8]),
        "Color": constant([0.2, 0.4, 0.6]), "color": constant([0.6, 0.4, 0.2]),
        "Brigtness": constant([1.25]), "brightness": constant([3]),
    ]
    let renamed: [String: Value] = [
        "opacityGain": constant([0.35]), "surfaceTint": constant([0.1, 0.3, 0.9]),
        "lightGain": constant([2]), "alpha": constant([1]),
        "color": constant([1, 0, 0]), "brightness": constant([7]),
    ]
    return [
        "uppercase": summary(compile(pass(constants: both))),
        "lowercase": summary(compile(pass(constants: both), shader(
            alphaKey: "alpha", colorKey: "color", brightnessKey: "brightness"
        ))),
        "renamed": summary(compile(pass(constants: renamed), shader(
            alphaKey: "opacityGain", colorKey: "surfaceTint", brightnessKey: "lightGain"
        ))),
    ]
}

private func invalidSchema() -> [String: Any] {
    let normal = pass(constants: ["Alpha": constant([0.02])])
    let cases: [String: Bindings] = [
        "bothUniformAndAnnotationAuthored": compile(pass(constants: [
            "Alpha": constant([0.02]), "g_TintAlpha": constant([1]),
        ])),
        "duplicateUniform": compile(normal, shader(fragmentExtra:
            #"uniform float g_TintAlpha; // {"material":"Alpha","default":0.125}"#
        )),
        "wrongScalarType": compile(normal, shader(alphaType: "vec2")),
        "scalarArray": compile(normal, shader(alphaSuffix: "[1]")),
        "malformedMaterialType": compile(normal, shader(customAlphaAnnotation:
            #"{"material":false,"default":0.125}"#
        )),
        "blankMaterialKey": compile(normal, shader(customAlphaAnnotation:
            #"{"material":"   ","default":0.125}"#
        )),
        "malformedAnnotation": compile(normal, shader(customAlphaAnnotation: "{broken}")),
        "conflictingAnnotation": compile(normal, shader(vertexExtra:
            #"uniform float g_TintAlpha; // {"material":"alpha","default":0.125}"#
        )),
        "materialKeyCollision": compile(normal, shader(brightnessKey: "Alpha")),
        "foreignUniformOwnsKey": compile(normal, shader(fragmentExtra:
            #"uniform vec2 u_IndependentValue; // {"material":"Alpha","default":[0,0]}"#
        )),
    ]
    return cases.mapValues(summary)
}

private func defaults() -> [String: Any] {
    let noValues = pass()
    let values: [String: Value] = [
        "g_TintAlpha": constant([0.4]), "g_TintColor": constant([0.9, 0.2, 0.1]),
        "g_Brightness": constant([2.5]),
    ]
    return [
        "annotation": summary(compile(noValues)),
        "directUniform": summary(compile(pass(constants: values))),
        "shortVectorDefault": summary(compile(noValues, shader(colorDefault: "[0.25,0.5]"))),
        "longVectorDefault": summary(compile(noValues, shader(colorDefault: "[0.25,0.5,0.75,1]"))),
        "emptyDefault": summary(compile(noValues, shader(alphaDefault: "[]"))),
        "nonFiniteDefault": summary(compile(noValues, shader(alphaDefault: #""nan""#))),
        "floatOverflowDefault": summary(compile(noValues, shader(alphaDefault: "1e100"))),
        "wrongAuthoredShape": summary(compile(pass(constants: ["Alpha": constant([0.2, 0.4])]))),
        "nonFiniteAuthored": summary(compile(pass(constants: ["Alpha": constant([.infinity])]))),
        "floatOverflowAuthored": summary(compile(pass(constants: ["Alpha": constant([1e100])]))),
    ]
}

private func proofBoundaries() -> [String: Any] {
    let authored = pass(constants: ["Alpha": constant([0.02])])
    return [
        "noReadinessFacts": summary(compile(authored, shader(fragmentExtra: """
            uniform sampler2D g_Texture0; // {"combo":"HAS_A"}
            uniform sampler2D g_Texture1; // {"combo":"HAS_B"}
            """
        ))),
        "noFormatFacts": summary(compile(authored, shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"combo":"HAS_A","formatcombo":true}"#
        ))),
        "conditionalInterface": summary(compile(authored, shader(conditionalAlpha: true))),
        // A well-formed engine-module request (stock lighting shaders all carry
        // `#require LightingV1`) must not void the interface proof: it never
        // rewrites declarations. Malformed requires still fail the proof.
        "requireDirectiveAdmitted": summary(compile(authored, shader(fragmentPrefix:
            "#require LightingV1"
        ))),
        "malformedRequireRejected": summary(compile(authored, shader(fragmentPrefix:
            "#require Lighting 1"
        ))),
        // The shadow-atlas comparison sampler (`sampler2DComparison g_Texture6`
        // with an internal-target default) is an engine-internal depth input:
        // the disjointness sweep must skip it like any other sampler instead
        // of running the material schema over `_rt_shadowAtlas` and voiding
        // the proof for generic4-family materials.
        "comparisonSamplerSkipped": summary(compile(authored, shader(fragmentExtra:
            #"uniform sampler2DComparison g_Texture6; // {"hidden":true,"default":"_rt_shadowAtlas"}"#
        ))),
        "conditionalDuplicate": summary(compile(authored, shader(fragmentExtra: """
            #if defined(HAS_A)
            uniform float g_TintAlpha; // {"material":"Alpha","default":0.125}
            #endif
            """
        ))),
        "conditionalKeyCollision": summary(compile(authored, shader(fragmentExtra: """
            #if defined(HAS_A)
            uniform float u_OptionalValue; // {"material":"Alpha","default":0.125}
            #endif
            """
        ))),
        "macroRewrite": summary(compile(authored, shader(fragmentPrefix: """
            #define g_TintAlpha u_RewrittenAlpha
            """
        ))),
        "unresolvedInclude": summary(compile(authored, shader(fragmentExtra: #"#include "unknown.glsl""#))),
        "vertexFragmentConflict": summary(compile(authored, shader(vertexExtra:
            #"uniform float g_TintAlpha; // {"material":"alpha","default":0.125}"#
        ))),
        "sameLineHiddenDeclaration": summary(compile(authored, shader(fragmentExtra:
            "uniform float u_Extra; uniform float g_TintAlpha;"
        ))),
        "bareMacroPrefix": summary(compile(authored, shader(
            fragmentPrefix: "#define EMPTY",
            fragmentExtra: #"EMPTY uniform float u_Extra; // {"material":"Alpha","default":0.125}"#
        ))),
        "explicitUniformCombo": summary(compile(pass(constants: ["Alpha": constant([0.02])], combos: ["g_TintAlpha": 1]))),
        "explicitTypeCombo": summary(compile(pass(constants: ["Alpha": constant([0.02])], combos: ["float": 1]))),
        "authoredUniformCombo": summary(compile(authored, shader(fragmentPrefix:
            #"// [COMBO] {"combo":"g_TintAlpha","default":1}"#
        ))),
        "samplerUniformCombo": summary(compile(authored, shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"combo":"g_TintAlpha"}"#
        ))),
    ]
}

private func numericInput() -> [String: Any] {
    let vector = [0.2, 0.4, 0.6]
    return [
        "malformedScalar": summary(compile(pass(constants: ["Alpha": constant([0.02], raw: "0.02 bad", kind: "string")]))),
        "malformedVector": summary(compile(pass(constants: ["Color": constant(vector, raw: "0.2 bad 0.4 0.6", kind: "vector")]))),
        "malformedWrapper": summary(compile(pass(constants: ["Alpha": wrapper("opacity", [0.02], raw: "0.02 bad")]))),
        "projectionMismatch": summary(compile(pass(constants: ["Alpha": constant([0.02], raw: "0.2", kind: "number")]))),
        "unknownKind": summary(compile(pass(constants: ["Alpha": constant([0.02], raw: "0.02", kind: "object")]))),
        "commaVector": summary(compile(pass(constants: ["Color": constant(vector, raw: "0.2,0.4,0.6", kind: "string")]))),
        "tabVector": summary(compile(pass(constants: ["Color": constant(vector, raw: "0.2\t0.4\t0.6", kind: "string")]))),
        "commaWrapper": summary(compile(pass(constants: ["Color": wrapper("tint", vector, raw: "0.2,0.4,0.6")]))),
        "whitespaceStaticKey": summary(compile(pass(constants: [" Alpha ": constant([0.02])]), shader(alphaKey: " Alpha "))),
        "whitespacePropertyKey": summary(compile(pass(constants: [" Alpha ": wrapper("opacity", [0.02])]), shader(alphaKey: " Alpha "))),
    ]
}

private func property(
    _ key: String, _ kind: SceneUserPropertyKind, _ value: SceneUserPropertyValue
) -> SceneUserPropertyDefinition {
    .init(
        key: key, title: key, kind: kind, runtimeType: kind.rawValue,
        order: 0, index: nil, minimumValue: kind == .slider ? 0 : nil,
        maximumValue: kind == .slider ? 10 : nil, stepValue: nil,
        allowsFractionalValues: true, fractionalPrecision: nil,
        displayCondition: nil, defaultValue: value, options: []
    )
}

private func snapshot(
    _ program: ScenePropertyBindingProgram, values: [String: SceneUserPropertyValue], frameIndex: UInt64
) -> SceneDynamicSnapshot {
    let evaluation = program.evaluate(effectiveValues: values)
    return SceneDynamicSnapshotResolver().resolve(
        frameIndex: frameIndex, generation: 9,
        definitions: program.definitions, userValues: evaluation.userValues
    ).snapshot
}

private func materialTarget(layerID: Int, name: String, path: String) -> SceneDynamicTarget {
    .materialConstant(layerID: layerID, passIndex: 0, name: name, materialPath: path)
}

private func read(_ snapshot: SceneDynamicSnapshot, layerID: Int, names: [String], path: String) -> [[Double]] {
    names.map { name in
        switch snapshot[materialTarget(layerID: layerID, name: name, path: path)]?.value {
        case let .scalar(value): [value]
        case let .vector3(x, y, z): [x, y, z]
        default: []
        }
    }
}

private func properties() -> [String: Any] {
    let path7 = "materials/upper.json"
    let path8 = "materials/lower.json"
    var upper = pass(constants: [
        "Alpha": wrapper("opacity7", [0.02]), "Color": wrapper("tint7", [0.2, 0.4, 0.6]),
        "Brigtness": wrapper("gain7", [1.25]),
        "emissivecolor": wrapper("emissionTint7", [0.9, 0.3, 0.1]),
        "emissivebrightness": wrapper("emissionGain7", [2]),
        "alpha": wrapper("staleOpacity", [1]), "color": wrapper("staleTint", [1, 0, 0]),
        "brightness": wrapper("staleGain", [8]),
    ], materialPath: path7)
    var lower = pass(constants: [
        "alpha": wrapper("opacity8", [0.8]), "color": wrapper("tint8", [0.6, 0.4, 0.2]),
        "brightness": wrapper("gain8", [3]),
        "Alpha": wrapper("staleOpacity", [1]),
    ], materialPath: path8)
    upper.staticModelMaterialBindings = compile(upper)
    lower.staticModelMaterialBindings = compile(lower, shader(
        alphaKey: "alpha", colorKey: "color", brightnessKey: "brightness"
    ))
    let descriptor = SceneRenderDescriptor(
        layers: [.init(id: 7, staticModelPath: "models/upper.mdl"), .init(id: 8, staticModelPath: "models/lower.mdl")],
        modelMaterialLinks: [
            .init(modelPath: "models/upper.mdl", materialPath: "MATERIALS\\UPPER.JSON"),
            .init(modelPath: "models/lower.mdl", materialPath: path8),
        ],
        materialPasses: [upper, lower]
    )
    let bindings = SceneMaterialPropertyBindingCompiler.compile(descriptor: descriptor, materialInstancesByLayerID: [:])
    let compilation = ScenePropertyBindingCompiler().compile(
        report: .init(bindings: bindings, diagnostics: []),
        catalog: .init(definitions: [
            property("opacity7", .slider, .number(0.02)), property("tint7", .color, .string("0.2 0.4 0.6")),
            property("gain7", .slider, .number(1.25)), property("opacity8", .slider, .number(0.8)),
            property("emissionTint7", .color, .string("0.9 0.3 0.1")), property("emissionGain7", .slider, .number(2)),
            property("tint8", .color, .string("0.6 0.4 0.2")), property("gain8", .slider, .number(3)),
            property("staleOpacity", .slider, .number(1)), property("staleTint", .color, .string("1 0 0")),
            property("staleGain", .slider, .number(8)),
        ])
    )
    let effective: [String: SceneUserPropertyValue] = [
        "opacity7": .number(0.3), "tint7": .string("0.1 0.5 0.9"), "gain7": .number(2),
        "emissionTint7": .string("0.7 0.3 0.2"), "emissionGain7": .number(4),
        "opacity8": .number(0.7), "tint8": .string("0.9 0.5 0.1"), "gain8": .number(3),
        "staleOpacity": .number(1), "staleTint": .string("1 0 0"), "staleGain": .number(8),
    ]
    let first = snapshot(compilation.program, values: effective, frameIndex: 4)
    var nextValues = effective
    nextValues["opacity7"] = .number(0.1)
    let next = snapshot(compilation.program, values: nextValues, frameIndex: 5)
    let upperNames = ["Alpha", "Color", "Brigtness"]
    let lowerNames = ["alpha", "color", "brightness"]
    let targetSet = Set(compilation.program.definitions.map(\.target))
    let expectedTargets = Set((upperNames + ["emissivecolor", "emissivebrightness"]).map { materialTarget(layerID: 7, name: $0, path: path7) }
        + lowerNames.map { materialTarget(layerID: 8, name: $0, path: path8) })

    var claimedEmission = pass(constants: [
        "emissivecolor": wrapper("emissionTint7", [0.9, 0.3, 0.1]),
        "emissivebrightness": wrapper("emissionGain7", [2]),
    ])
    claimedEmission.staticModelMaterialBindings = compile(claimedEmission, shader(
        colorKey: "emissivecolor", brightnessKey: "emissivebrightness"
    ))
    let claimedDescriptor = SceneRenderDescriptor(
        layers: [.init(id: 7, staticModelPath: "models/claimed.mdl")],
        modelMaterialLinks: [.init(modelPath: "models/claimed.mdl", materialPath: claimedEmission.materialPath)],
        materialPasses: [claimedEmission]
    )
    let claimedBindings = SceneMaterialPropertyBindingCompiler.compile(
        descriptor: claimedDescriptor, materialInstancesByLayerID: [:]
    )

    var invalid = pass(constants: ["Alpha": wrapper("opacity7", [0.2], keys: ["extra", "user", "value"])])
    invalid.staticModelMaterialBindings = compile(invalid)
    let invalidDescriptor = SceneRenderDescriptor(
        layers: [.init(id: 7, staticModelPath: "models/invalid.mdl")],
        modelMaterialLinks: [.init(modelPath: "models/invalid.mdl", materialPath: invalid.materialPath)],
        materialPasses: [invalid]
    )
    var rejected = pass(constants: ["Alpha": constant([.infinity])], materialPath: path7)
    rejected.staticModelMaterialBindings = compile(rejected)
    let rejectedDescriptor = SceneRenderDescriptor(
        layers: descriptor.layers, modelMaterialLinks: descriptor.modelMaterialLinks, materialPasses: [rejected]
    )
    let unavailablePath = "materials/unavailable.json"
    var unavailable = pass(constants: [
        "alpha": wrapper("opacity7", [0.02]), "color": wrapper("tint7", [0.2, 0.4, 0.6]),
        "brightness": wrapper("gain7", [1.25]),
        "emissivecolor": wrapper("emissionTint7", [0.9, 0.3, 0.1]),
        "emissivebrightness": wrapper("emissionGain7", [2]),
    ], materialPath: unavailablePath)
    unavailable.staticModelMaterialBindings = compile(unavailable, shader(conditionalAlpha: true))
    let unavailableDescriptor = SceneRenderDescriptor(
        layers: [.init(id: 9, staticModelPath: "models/unavailable.mdl")],
        modelMaterialLinks: [.init(modelPath: "models/unavailable.mdl", materialPath: unavailablePath)],
        materialPasses: [unavailable]
    )
    let unavailableBindings = SceneMaterialPropertyBindingCompiler.compile(
        descriptor: unavailableDescriptor, materialInstancesByLayerID: [:]
    )
    let unavailableCompilation = ScenePropertyBindingCompiler().compile(
        report: .init(bindings: unavailableBindings, diagnostics: []),
        catalog: .init(definitions: [
            property("opacity7", .slider, .number(0.02)), property("tint7", .color, .string("0.2 0.4 0.6")),
            property("gain7", .slider, .number(1.25)), property("emissionTint7", .color, .string("0.9 0.3 0.1")),
            property("emissionGain7", .slider, .number(2)),
        ])
    )
    let unavailableSnapshot = snapshot(unavailableCompilation.program, values: effective, frameIndex: 6)
    return [
        "bindingCount": bindings.count, "definitionCount": compilation.program.definitions.count,
        "instructionCount": compilation.program.instructions.count,
        "diagnostics": compilation.diagnostics.count,
        "layer7": read(first, layerID: 7, names: upperNames, path: path7),
        "layer8": read(first, layerID: 8, names: lowerNames, path: path8),
        "emission7": read(first, layerID: 7, names: ["emissivecolor", "emissivebrightness"], path: path7),
        "claimedEmissionBindingCount": claimedBindings.count,
        "claimedEmissionTargetCount": Set(claimedBindings.compactMap {
            ScenePropertyBindingCompiler.map($0, propertyKind: nil)?.target
        }).count,
        "exactTargets": targetSet == expectedTargets,
        "staleAliasesAbsent": lowerNames.allSatisfy { first[materialTarget(layerID: 7, name: $0, path: path7)] == nil }
            && upperNames.allSatisfy { first[materialTarget(layerID: 8, name: $0, path: path8)] == nil },
        "peerMaterialsAbsent": first[materialTarget(layerID: 7, name: "Alpha", path: path8)] == nil
            && first[materialTarget(layerID: 8, name: "alpha", path: path7)] == nil,
        "independentNextFrame": read(next, layerID: 7, names: ["Alpha"], path: path7) == [[0.1]]
            && read(next, layerID: 8, names: lowerNames, path: path8) == read(first, layerID: 8, names: lowerNames, path: path8),
        "invalidWrapperBindings": SceneMaterialPropertyBindingCompiler.compile(
            descriptor: invalidDescriptor, materialInstancesByLayerID: [:]
        ).count,
        "rejectedMaterialBindings": SceneMaterialPropertyBindingCompiler.compile(
            descriptor: rejectedDescriptor, materialInstancesByLayerID: [:]
        ).count,
        "unavailableState": unavailable.staticModelMaterialBindings!.state.rawValue,
        "unavailableBindingCount": unavailableBindings.count,
        "unavailableDiagnostics": unavailableCompilation.diagnostics.count,
        "unavailableLegacyValues": read(unavailableSnapshot, layerID: 9,
            names: ["alpha", "color", "brightness", "emissivecolor", "emissivebrightness"], path: unavailablePath),
    ]
}

private func sources() -> [String: Any] {
    let host = SceneShaderContract(
        identity: "fixture/static-material-keys", sourceKind: .hostBuiltin,
        stages: [], diagnostics: [], canonicalSHA256: "builtin"
    )
    return [
        "hostBuiltin": summary(SceneStaticModelMaterialBindingCompiler.compile(pass: pass(), shaderContracts: [host])),
        "missing": summary(SceneStaticModelMaterialBindingCompiler.compile(pass: pass(), shaderContracts: [])),
        "ambiguous": summary(SceneStaticModelMaterialBindingCompiler.compile(pass: pass(), shaderContracts: [shader(), shader()])),
        "noPassZero": summary(compile(pass(passIndex: 1))),
    ]
}

private func albedoDefaults() -> [String: Any] {
    let ordinary = #"uniform sampler2D g_Texture0; // {"default":"util/white","material":"albedo"}"#
    let white = shader(fragmentExtra: ordinary)
    func path(_ pass: Pass = pass(), _ contract: SceneShaderContract = white,
              contracts: [SceneShaderContract]? = nil) -> Any {
        SceneStaticModelMaterialBindingCompiler.defaultAlbedoAssetPath(
            pass: pass, shaderContracts: contracts ?? [contract]) as Any? ?? NSNull()
    }
    var null = pass(); null.textureSlots = [nil]
    var normalOnly = pass(); normalOnly.textureSlots = [nil, "fixtures/normal"]
    var tailAbsent = pass(); tailAbsent.textureSlots = [nil, nil]
    var explicit = pass(); explicit.textureSlots = ["fixtures/authored-blue"]
    var badPath = pass(); badPath.textureSlots = ["fixtures/missing-explicit"]
    var user = pass(); user.userTextureInputs = [.init(kind: .property, value: "chosen")]
    var userPath = pass(); userPath.userTextureInputs = [.init(kind: .path, value: "fixtures/user")]
    let unavailable = shader(fragmentExtra: ordinary, conditionalAlpha: true)
    let ambiguousSampler = """
        \(ordinary)
        #if defined(OPTIONAL)
        uniform sampler2D g_Texture0; // {"default":"fixtures/other"}
        #endif
        """
    let conditionalInclude = shader(fragmentExtra: """
        \(ordinary)
        #if defined(OPTIONAL)
        #include "fixture/conditional.glsl"
        #endif
        """, includedSources: ["fixture/conditional.glsl":
            #"uniform sampler2D g_Texture0; // {"default":"fixtures/other"}"#])
    let unconditionalInclude = shader(fragmentExtra: #"#include "fixture/default.glsl""#,
        includedSources: ["fixture/default.glsl": ordinary])
    func tamperedGraph(_ contract: SceneShaderContract, rawMismatch: Bool) -> SceneShaderContract {
        guard let graph = contract.sourceGraph else { preconditionFailure("fixture graph missing") }
        var nodes = graph.nodes
        if rawMismatch {
            guard let index = nodes.firstIndex(where: { $0.virtualPath == "fixture/default.glsl" })
            else { preconditionFailure("fixture include missing") }
            let node = nodes[index]
            nodes[index] = .init(virtualPath: node.virtualPath, provenance: node.provenance,
                source: node.source, rawSHA256: String(repeating: "0", count: 64), byteCount: node.byteCount)
        }
        let digest = rawMismatch
            ? SceneShaderSourceGraph.dependencySHA256(nodes: nodes, edges: graph.edges)
            : String(repeating: "0", count: 64)
        return .init(identity: contract.identity, sourceKind: contract.sourceKind,
            stages: contract.stages, diagnostics: contract.diagnostics,
            canonicalSHA256: contract.canonicalSHA256,
            sourceGraph: .init(roots: graph.roots, nodes: nodes, edges: graph.edges,
                diagnostics: graph.diagnostics, dependencySHA256: digest))
    }
    let unrelatedFormat = shader(fragmentExtra: """
        \(ordinary)
        uniform sampler2D g_Texture7; // {"combo":"HAS_OTHER","formatcombo":true}
        """)
    let variant = SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: unrelatedFormat, compatibilityTarget: .windowsDX11ShaderModel4,
        combos: [:], textureReadiness: Dictionary(uniqueKeysWithValues: (0..<8).map { ($0, $0 == 7) }))
    let variantFailure: String
    if case let .rejected(failure) = variant {
        variantFailure = failure.details.first ?? "unclassified"
    } else { variantFailure = "not-rejected" }
    var result: [String: Any] = [
        "omitted": path(), "null": path(null), "normalOnly": path(normalOnly),
        "tailReadiness": path(tailAbsent, shader(fragmentExtra: """
            \(ordinary)
            uniform sampler2D g_Texture7; // {"combo":"HAS_TAIL"}
            """)),
        "colored": path(pass(), shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"fixtures/colored","material":"albedo"}"#)),
        "explicit": path(explicit), "explicitStillAuthored": explicit.textureSlots[0] as Any,
        "badPath": path(badPath), "badPathStillAuthored": badPath.textureSlots[0] as Any,
        "user": path(user), "userPath": path(userPath),
        "passOne": path(pass(passIndex: 1)),
        "unavailableUniformState": compile(pass(), unavailable).state.rawValue,
        "unavailableUniformDefault": path(pass(), unavailable),
        "unconditionalInclude": path(pass(), unconditionalInclude),
        "conditionalInclude": path(pass(), conditionalInclude),
        "conditionalSameName": path(pass(), shader(fragmentExtra: ambiguousSampler)),
        "missingContract": path(contracts: []),
        "duplicateContract": path(contracts: [white, white]),
        "graphDigestMismatch": path(pass(), tamperedGraph(white, rawMismatch: false)),
        "graphRawMismatch": path(pass(), tamperedGraph(unconditionalInclude, rawMismatch: true)),
        "unrelatedFormatDefault": path(tailAbsent, unrelatedFormat),
        "unrelatedFormatVariantFailure": variantFailure,
    ]
    let rejected: [String: SceneShaderContract] = [
        "conditionalOnly": shader(fragmentExtra: "#if defined(OPTIONAL)\n\(ordinary)\n#endif"),
        "readiness": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"util/white","combo":"HAS_BASE"}"#),
        "macroRename": shader(fragmentPrefix: "#define g_Texture0 g_Texture1", fragmentExtra: ordinary),
        "conditionalMacroAlias": shader(fragmentPrefix: "#define SLOT g_Texture0", fragmentExtra: """
            \(ordinary)
            #if defined(OPTIONAL)
            uniform sampler2D SLOT; // {"default":"util/white"}
            #endif
            """),
        "noDefault": shader(fragmentExtra: #"uniform sampler2D g_Texture0; // {"material":"albedo"}"#),
        "opacityMode": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"util/white","mode":"opacitymask"}"#),
        "format": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"util/white","format":"rgba8"}"#),
        "internal": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"_rt_FullFrameBuffer"}"#),
        "conflict": shader(fragmentExtra: ordinary, vertexExtra:
            #"uniform sampler2D g_Texture0; // {"default":"fixtures/other"}"#),
        "malformedDefault": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":false}"#),
        "invalidAssetPath": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"../escape"}"#),
        "samplerArray": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0[2]; // {"default":"util/white"}"#),
        "annotationComboSampler": shader(fragmentPrefix:
            #"// [COMBO] {"combo":"g_Texture0","default":0,"options":[0,1]}"#,
            fragmentExtra: ordinary),
        "annotationComboType": shader(fragmentPrefix:
            #"// [COMBO] {"combo":"sampler2D","default":0,"options":[0,1]}"#,
            fragmentExtra: ordinary),
        "tokenPasteOtherVertex": shader(fragmentExtra: ordinary,
            vertexExtra: "#define CONCAT(a,b) a##b"),
        "tokenPasteOtherFragment": shader(fragmentExtra: "#define CONCAT(a,b) a##b",
            vertexExtra: ordinary),
        "emptyPrefixHiddenConditional": shader(fragmentPrefix: "#define EMPTY", fragmentExtra: """
            #if defined(OPTIONAL)
            EMPTY uniform sampler2D g_Texture0; // {"default":"fixtures/other"}
            #endif
            """, vertexExtra: ordinary),
        "materialNormal": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"util/white","material":"normal"}"#),
        "materialNoise": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"util/white","material":"noise"}"#),
        "graphMaterialAlias": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"util/white","material":"framebuffer"}"#),
        "registeredDataDefault": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"gradient/gradient_fire","material":"albedo"}"#),
        "registeredNoiseDefault": shader(fragmentExtra:
            #"uniform sampler2D g_Texture0; // {"default":"util/noise","material":"albedo"}"#),
    ]
    for (name, contract) in rejected { result[name] = path(pass(), contract) }
    return result
}

@main
private enum SceneStaticModelMaterialBindingsHarness {
    static func main() throws {
        let result: [String: Any]
        switch CommandLine.arguments.dropFirst().first {
        case "identities": result = identities()
        case "invalidSchema": result = invalidSchema()
        case "defaults": result = defaults()
        case "properties": result = properties()
        case "sources": result = sources()
        case "proofBoundaries": result = proofBoundaries()
        case "numericInput": result = numericInput()
        case "albedoDefaults": result = albedoDefaults()
        default: throw NSError(domain: "material-bindings-fixture", code: 1)
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
