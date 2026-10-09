import Foundation

// Link-only prepared facts come from the separate real neutral compiler gate.
// The declaration factory, admission, live transaction and source consumer here
// are the product owners, including the nested script-property publisher.
func customMaterialUserColorChecks() -> [String: Bool] {
    typealias Descriptor = SceneRenderDescriptor
    let model = "models/mixed-color.json", material = "materials/mixed-color.json"
    let original = Descriptor.Layer(id: 146, contentKind: "image", imagePath: model, effects: [])
    let clone = Descriptor.Layer(id: 991, contentKind: "image", imagePath: model, effects: [])
    let script = "export function update(value) { if (scriptProperties.ifchange) return value.multiply(0.5); }"
    let inputs: [String: SceneJSONValue] = ["ifchange": .object(["user": .string("animate"), "value": .bool(true)])]
    let color = SceneDocument.ShaderValue(rawValue: "0.729 0.345 0.729", userBinding: "palette",
        components: [0.729, 0.345, 0.729], userValueKind: .string, scriptSource: script,
        scriptProperties: inputs, bindingKeys: ["script", "scriptproperties", "user", "value"])
    let pass = Descriptor.MaterialPassDescriptor(materialPath: material,
        shaderPath: "genericimage", textureSlots: ["util/white"], userTextureInputs: [],
        constantShaderValues: ["arbitrary-surface": color,
            "Alpha": .init(rawValue: "1", userBinding: "opacity", components: [1],
                userValueKind: .string, bindingKeys: ["user", "value"])])
    let descriptor = Descriptor(layers: [original], modelMaterialLinks: [
        .init(modelPath: model, materialPath: material)
    ], materialPasses: [pass], texturePropertyKeys: [])
    let fact = SceneBaseMaterialColorModulationCompiler.Binding(modelPath: model,
        sourceLayerID: original.id, materialPath: material, colorKey: "arbitrary-surface",
        scriptSource: script, scriptProperties: inputs, authoredColor: SIMD3(0.729, 0.345, 0.729),
        alphaKey: "Alpha", authoredAlpha: 1, alphaUserPropertyKey: "opacity", colorUserPropertyKey: "palette")
    func definition(_ key: String, _ kind: SceneUserPropertyKind,
        _ fallback: SceneUserPropertyValue) -> SceneUserPropertyDefinition {
        .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue,
            order: 0, index: nil, minimumValue: kind == .slider ? 0 : nil,
            maximumValue: kind == .slider ? 1 : nil, stepValue: nil,
            allowsFractionalValues: true, fractionalPrecision: nil, displayCondition: nil,
            defaultValue: fallback, options: [])
    }
    let definitions = [definition("palette", .color, .string("0.729 0.345 0.729")),
        definition("animate", .bool, .bool(true)), definition("opacity", .slider, .number(1))]
    let declarations = SceneMaterialPropertyBindingCompiler.provenPropertyBindings([fact],
        descriptor: descriptor, materialInstancesByLayerID: [:])
    func propertyProgram(_ properties: [SceneUserPropertyDefinition]) -> ScenePropertyBindingCompilation {
        ScenePropertyBindingCompiler().compile(report: .init(bindings: declarations, diagnostics: []),
            catalog: .init(definitions: properties))
    }
    let compiled = propertyProgram(definitions), program = compiled.program
    let colorTarget = fact.colorPropertyTarget!, alphaTarget = fact.alphaPropertyTarget!
    let nestedTarget = SceneDynamicTarget.scriptInstanceProperty(layerID: original.id,
        path: SceneScriptPropertyTargetPath.encoded(fact.colorBindingPath + [.key("scriptproperties"), .key("ifchange")]))
    let targets = Set(program.instructions.map(\.target))
    func admitted(_ program: ScenePropertyBindingProgram, _ facts: [SceneBaseMaterialColorModulationCompiler.Binding]? = nil) -> Bool {
        SceneBaseMaterialProviderBindingCompiler.admittedSourceMaterials(facts ?? [fact], descriptor: descriptor,
            materialInstancesByLayerID: [:], propertyProgram: program, namedLayerIDs: []).count == 1
    }
    let source = SceneBaseMaterialProviderBindingCompiler.compile(descriptor: descriptor,
        materialInstancesByLayerID: [:], scriptBindings: [], materialPropertyTargets: targets, provenBindings: [fact])
    var fullFact = fact
    fullFact.canLowerToCompositor = false
    let fullSource = SceneBaseMaterialProviderBindingCompiler.compile(descriptor: descriptor,
        materialInstancesByLayerID: [:], scriptBindings: [], materialPropertyTargets: targets,
        materialColorTargets: [model: colorTarget], provenBindings: [fullFact])
    var checks: [String: Bool] = [
        "mixedHasExactlyThreeRealPublishers": compiled.diagnostics.isEmpty && declarations.count == 3
            && targets == [colorTarget, alphaTarget, nestedTarget],
        "arbitraryColorKeyUsesVector3Publisher": program.instructions.contains { $0.target == colorTarget && $0.valueType == .vector3 },
        "innerFlagUsesTheSameEncodedMaterialPath": program.instructions.contains { $0.target == nestedTarget && $0.valueType == .bool },
        "completeMixedClosureIsAdmitted": admitted(program),
        "fullProgramRetainsTheSameCompleteProducerClosure": admitted(program, [fullFact]),
        "fullProgramDoesNotRegisterMaterialMultipliers": fullSource.authoredMaterialColors.isEmpty
            && fullSource.materialColorTargets.isEmpty && fullSource.sourceMaterialAlphaPropertyTargets.isEmpty,
        "missingOuterColorProducerRejectsLowering": !admitted(propertyProgram(definitions.filter { $0.key != "palette" }).program),
        "missingInnerFlagProducerRejectsLowering": !admitted(propertyProgram(definitions.filter { $0.key != "animate" }).program),
        "missingAlphaProducerRejectsLowering": !admitted(propertyProgram(definitions.filter { $0.key != "opacity" }).program),
        "wrongColorPropertyKindRejectsLowering": !admitted(propertyProgram([
            definition("palette", .slider, .number(0.5)), definitions[1], definitions[2]]).program),
        "missingInnerInstructionRejectsLowering": !admitted(.init(definitions: program.definitions,
            instructions: program.instructions.filter { $0.target != nestedTarget })),
    ]
    let malformed = SceneBaseMaterialColorModulationCompiler.Binding(modelPath: model,
        sourceLayerID: original.id, materialPath: material, colorKey: fact.colorKey,
        scriptSource: script,
        scriptProperties: ["ifchange": .object(["user": .string("animate"), "value": .bool(true), "extra": .number(1)])],
        authoredColor: fact.authoredColor, alphaKey: "Alpha", authoredAlpha: 1,
        alphaUserPropertyKey: "opacity", colorUserPropertyKey: "palette")
    checks["malformedInnerProviderRejectsLowering"] = !admitted(program, [malformed])
    var state = ScenePropertyLiveUpdateState(program: program, effectiveValues: [
        "palette": .string("0.729 0.345 0.729"), "animate": .bool(true), "opacity": .number(1)
    ], activeConsumerTargets: targets)
    func snapshot(_ state: ScenePropertyLiveUpdateState) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: state.revision, generation: 1,
            definitions: program.definitions, userValues: state.userValues).snapshot
    }
    checks["liveColorAlphaAndNestedFlagAreAtomic"] = state.apply(replacements: [
        "palette": .string("0.2 0.6 0.8"), "animate": .bool(false), "opacity": .number(0.3)
    ], changedPropertyKeys: ["palette", "animate", "opacity"]) && state.revision == 1
    let current = snapshot(state)
    checks["fullProgramPrototypeAndCloneKeepCompositorMultipliersNeutral"] = [original, clone].allSatisfy {
        fullSource.sourceMaterialColor(layer: $0, snapshot: current) == SIMD3(1, 1, 1)
            && fullSource.sourceMaterialAlpha(layer: $0, snapshot: current) == 1
    }
    checks["fullProgramValuesRemainInTheTypedSnapshot"] = current[colorTarget]?.value == .vector3(0.2, 0.6, 0.8)
        && current[alphaTarget]?.value == .scalar(0.3)
    checks["prototypeAndCloneReadTheSameCurrentColor"] = [original, clone].allSatisfy {
        source.sourceMaterialColor(layer: $0, snapshot: current) == SIMD3(0.2, 0.6, 0.8)
            && abs(source.sourceMaterialAlpha(layer: $0, snapshot: current) - 0.3) < 0.000_001
    }
    checks["materialColorLeavesLayerStyleTargetUnwritten"] = state.userValues[.layer(layerID: original.id, field: .color)] == nil
        && state.userValues[.layer(layerID: clone.id, field: .color)] == nil
    for (name, bad) in [("malformed", SceneUserPropertyValue.string("0.2 0.6")),
                        ("nonfinite", .string("nan 0.6 0.8")), ("wrongType", .number(0.2))] {
        let before = state.userValues, values = state.effectiveValues, revision = state.revision
        checks["invalidMixedTransactionPreservesAll_\(name)"] = !state.apply(replacements: [
            "palette": bad, "animate": .bool(true), "opacity": .number(0.9)
        ], changedPropertyKeys: ["palette", "animate", "opacity"])
            && state.userValues == before && state.effectiveValues == values && state.revision == revision
    }
    checks["unavailableInnerFlagCannotPartiallyChangeColor"] = !state.apply(replacements: [
        "palette": .string("1 0 0"), "animate": .bool(true)
    ], changedPropertyKeys: ["palette", "animate"], unavailableConsumerTargets: [nestedTarget]) && state.revision == 1
    checks["finiteColorKeepsExistingClampPolicy"] = state.apply(.string("-2 0.4 3"), forPropertyKey: "palette")
        && source.sourceMaterialColor(layer: clone, snapshot: snapshot(state)) == SIMD3(0, 0.4, 1)
    return checks
}
