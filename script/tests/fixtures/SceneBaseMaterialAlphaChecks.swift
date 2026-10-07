import Foundation

// The proven fact is a link-only DTO; the separate neutral-tint compiler gate
// proves its schema origin. All property, live-state and consumer code here is
// the product implementation, with no VM or Metal device.
func customMaterialAlphaChecks() -> [String: Bool] {
    typealias Descriptor = SceneRenderDescriptor
    let modelPath = "models/custom-opacity.json"
    let materialPath = "materials/custom-opacity.json"
    let original = Descriptor.Layer(id: 501, contentKind: "image", imagePath: modelPath, effects: [])
    let clone = Descriptor.Layer(id: 599, contentKind: "image", imagePath: "MODELS\\CUSTOM-OPACITY.JSON", effects: [])
    let target = SceneDynamicTarget.materialConstant(layerID: original.id, passIndex: 0,
        name: "transmission-amount", materialPath: materialPath)
    let value = SceneDocument.ShaderValue(rawValue: "0.6", userBinding: "liveOpacity",
        components: [0.6], userValueKind: .string, bindingKeys: ["value", "user"])
    let pass = Descriptor.MaterialPassDescriptor(materialPath: materialPath,
        shaderPath: "genericimage", textureSlots: ["albedo"], userTextureInputs: [],
        constantShaderValues: ["transmission-amount": value,
            "Alpha": .init(rawValue: "1", userBinding: nil, components: [1])])
    let descriptor = Descriptor(layers: [original], modelMaterialLinks: [
        .init(modelPath: modelPath, materialPath: materialPath)
    ], materialPasses: [pass], texturePropertyKeys: [])
    let fact = SceneBaseMaterialColorModulationCompiler.Binding(modelPath: modelPath,
        sourceLayerID: original.id, materialPath: materialPath, colorKey: "surface-key",
        scriptSource: nil, scriptProperties: [:], authoredColor: SIMD3(0.2, 0.4, 0.6),
        alphaKey: "transmission-amount", authoredAlpha: 0.6, alphaUserPropertyKey: "liveOpacity")
    let declarations = SceneMaterialPropertyBindingCompiler.compile(descriptor: descriptor,
        materialInstancesByLayerID: [:], provenBindings: [fact])
    func compile(_ definitions: [SceneUserPropertyDefinition]) -> ScenePropertyBindingCompilation {
        ScenePropertyBindingCompiler().compile(report: .init(bindings: declarations, diagnostics: []),
            catalog: .init(definitions: definitions))
    }
    func property(_ minimum: Double? = 0, _ maximum: Double? = 1) -> SceneUserPropertyDefinition {
        .init(key: "liveOpacity", title: "Opacity", kind: .slider,
            runtimeType: "slider", order: 0, index: nil, minimumValue: minimum, maximumValue: maximum,
            stepValue: nil, allowsFractionalValues: true, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: .number(0.5), options: [])
    }
    let compiled = compile([property()])
    let program = compiled.program
    let targets = Set(program.instructions.map(\.target))
    let material = SceneBaseMaterialProviderBindingCompiler.compile(descriptor: descriptor,
        materialInstancesByLayerID: [:], scriptBindings: [], materialPropertyTargets: targets,
        provenBindings: [fact])
    func admitted(_ program: ScenePropertyBindingProgram,
        layers: [Descriptor.Layer]? = nil,
        instances: [Int: SceneDocument.SceneLayerMaterialInstance] = [:],
        named: Set<Int> = []) -> Bool {
        !SceneBaseMaterialProviderBindingCompiler.admittedSourceMaterials([fact],
            descriptor: .init(layers: layers ?? descriptor.layers,
                modelMaterialLinks: descriptor.modelMaterialLinks,
                materialPasses: descriptor.materialPasses, texturePropertyKeys: []),
            materialInstancesByLayerID: instances, propertyProgram: program,
            namedLayerIDs: named).isEmpty
    }
    func snapshot(_ values: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: program.definitions, userValues: values).snapshot
    }
    let initial = snapshot(program.evaluate(effectiveValues: ["liveOpacity": .number(0.5)]).userValues)
    let empty = SceneDynamicSnapshot.empty(frameIndex: 0)
    func near(_ first: Float, _ second: Float) -> Bool { abs(first - second) < 0.000_001 }
    var checks: [String: Bool] = [
        "arbitraryMaterialKeyPublishesOnePrototypeTarget": declarations.count == 1
            && compiled.diagnostics.isEmpty && targets == [target],
        "modelConsumerUsesThePreparedTarget": material.sourceMaterialAlphaPropertyTargets == [target],
        "originalAndCloneSharePrototypeAlpha": material.sourceMaterialAlpha(layer: original, snapshot: initial) == 0.5
            && material.sourceMaterialAlpha(layer: clone, snapshot: initial) == 0.5,
        "absentTypedValueUsesAuthoredFallback": near(material.sourceMaterialAlpha(layer: clone, snapshot: empty), 0.6),
        "missingPropertyHasNoPublisher": compile([]).program.instructions.isEmpty,
        "healthyProducerIsAdmitted": admitted(program),
        "missingProducerCannotLowerEitherChannel": !admitted(compile([]).program),
        "widePropertyRangeCannotLowerEitherChannel": !admitted(compile([property(-1, 2)]).program),
        "missingPropertyRangeCannotLowerEitherChannel": !admitted(compile([property(nil, nil)]).program),
        "missingInstructionCannotLowerEitherChannel": !admitted(.init(
            definitions: program.definitions, instructions: [])),
        "sameModelNamedCloneCannotLowerEitherChannel": !admitted(program, layers: [original, clone], named: [clone.id]),
        "duplicateMaterialPassHasNoPublisher": SceneMaterialPropertyBindingCompiler.compile(
            descriptor: .init(layers: [original], modelMaterialLinks: descriptor.modelMaterialLinks,
                materialPasses: [pass, pass], texturePropertyKeys: []),
            materialInstancesByLayerID: [:], provenBindings: [fact]).isEmpty,
        "oneFactFeedsColorAndAlpha": material.authoredMaterialColors[modelPath] == SIMD3(0.2, 0.4, 0.6)
            && material.sourceMaterialAlphaByModel.count == 1,
    ]
    let instance = SceneDocument.SceneLayerMaterialInstance(id: nil, textureSlots: [], userTextureInputs: [],
        hasUserTextureOverride: false, combos: [:], unknownKeys: [], isMalformed: false)
    checks["sameModelInstanceCloneCannotLowerEitherChannel"] = !admitted(program,
        layers: [original, clone], instances: [clone.id: instance])
    checks["authoredStockAliasAlphaCannotOverrideProvenUniform"] = material.sourceMaterialAlphaByLayerID.isEmpty
        && material.sourceMaterialAlpha(layer: original, snapshot: initial) == 0.5
        && material.sourceMaterialAlpha(layer: clone, snapshot: initial) == 0.5
    var exactFact = fact
    exactFact.alphaKey = "Alpha"
    var exactPass = pass
    exactPass.constantShaderValues = ["Alpha": value]
    let exactDescriptor = Descriptor(layers: [original], modelMaterialLinks: descriptor.modelMaterialLinks,
        materialPasses: [exactPass], texturePropertyKeys: [])
    let exactDeclarations = SceneMaterialPropertyBindingCompiler.compile(descriptor: exactDescriptor,
        materialInstancesByLayerID: [:], provenBindings: [exactFact])
    let exactProgram = ScenePropertyBindingCompiler().compile(
        report: .init(bindings: exactDeclarations, diagnostics: []), catalog: .init(definitions: [property()]))
    let exactTarget = SceneDynamicTarget.materialConstant(layerID: original.id, passIndex: 0,
        name: "Alpha", materialPath: materialPath)
    checks["exactAlphaHasOnePropertyProducer"] = exactDeclarations.count == 1
        && exactProgram.diagnostics.isEmpty && exactProgram.program.instructions.count == 1
        && exactProgram.program.definitions.count == 1
        && exactProgram.program.instructions.first?.target == exactTarget
    // Follow RuntimeModel's actual order: qualify proposed facts before they
    // retire a builtin producer. A hidden same-model sibling remains in this
    // closure even though it is not rendered at startup.
    var visibleA = original
    visibleA.visible = true
    var hiddenB = clone
    hiddenB.visible = false
    let pair = Descriptor(layers: [visibleA, hiddenB], modelMaterialLinks: descriptor.modelMaterialLinks,
        materialPasses: [exactPass], texturePropertyKeys: [])
    var otherConstantInstance = instance
    otherConstantInstance.scalarShaderValues = ["emissivebrightness": .init(rawValue: "0.2", userBinding: nil, components: [0.2])]
    for (name, definitions, instances, named) in [
        ("healthy", [property()], [Int: SceneDocument.SceneLayerMaterialInstance](), Set<Int>()),
        ("hiddenInstance", [property()], [hiddenB.id: otherConstantInstance], Set<Int>()),
        ("hiddenNamed", [property()], [:], Set([hiddenB.id])),
        ("wideRange", [property(-1, 2)], [:], Set<Int>()),
        ("noRange", [property(nil, nil)], [:], Set<Int>()),
        ("missingProducer", [], [:], Set<Int>()),
    ] {
        let proposed = SceneMaterialPropertyBindingCompiler.provenPropertyBindings([exactFact],
            descriptor: pair, materialInstancesByLayerID: instances)
        let proposedProgram = ScenePropertyBindingCompiler().compile(
            report: .init(bindings: proposed, diagnostics: []), catalog: .init(definitions: definitions)).program
        let admittedFacts = SceneBaseMaterialProviderBindingCompiler.admittedSourceMaterials([exactFact],
            descriptor: pair, materialInstancesByLayerID: instances,
            propertyProgram: proposedProgram, namedLayerIDs: named)
        let full = SceneMaterialPropertyBindingCompiler.compile(descriptor: pair,
            materialInstancesByLayerID: instances, provenBindings: admittedFacts)
        let fullProgram = ScenePropertyBindingCompiler().compile(
            report: .init(bindings: full, diagnostics: []), catalog: .init(definitions: definitions))
        let expectedDeclarationCount = name == "healthy" ? 1 : 2
        let expectedPublisherCount = name == "missingProducer" ? 0 : expectedDeclarationCount
        let fullTargets = Set(fullProgram.program.instructions.map(\.target))
        let source = SceneBaseMaterialProviderBindingCompiler.compile(descriptor: pair,
            materialInstancesByLayerID: instances, scriptBindings: [],
            materialPropertyTargets: fullTargets, provenBindings: admittedFacts)
        let frame = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: fullProgram.program.definitions,
            userValues: fullProgram.program.evaluate(effectiveValues: ["liveOpacity": .number(0.25)]).userValues).snapshot
        checks["preparedOrderRetainsProducer_\(name)"] = admittedFacts.count == (name == "healthy" ? 1 : 0)
            && full.count == expectedDeclarationCount && fullTargets.count == expectedPublisherCount
        checks["preparedOrderRetainsConsumer_\(name)"] = name == "missingProducer"
            ? source.sourceMaterialAlphaByLayerID.isEmpty && source.sourceMaterialAlphaByModel.isEmpty
            : source.sourceMaterialAlpha(layer: visibleA, snapshot: frame) == 0.25
                && source.sourceMaterialAlpha(layer: hiddenB, snapshot: frame) == 0.25
        if name != "healthy" {
            let bTarget = SceneDynamicTarget.materialConstant(layerID: hiddenB.id, passIndex: 0,
                name: "Alpha", materialPath: materialPath)
            checks["builtinFallbackKeepsBothLayerTargets_\(name)"] = Set(full.compactMap {
                ScenePropertyBindingCompiler.map($0, propertyKind: nil)?.target
            }) == [exactTarget, bTarget]
        }
    }
    var state = ScenePropertyLiveUpdateState(program: program,
        effectiveValues: ["liveOpacity": .number(0.5)], activeConsumerTargets: targets)
    let events: [(SceneUserPropertyValue, Bool, UInt64, Float)] = [
        (.number(0.25), true, 1, 0.25), (.number(0.25), true, 1, 0.25),
        (.number(0), true, 2, 0), (.string("bad"), false, 2, 0),
        (.number(2), false, 2, 0), (.number(1), true, 3, 1),
    ]
    for (index, event) in events.enumerated() {
        let accepted = state.apply(event.0, forPropertyKey: "liveOpacity")
        let frame = snapshot(state.userValues)
        checks["liveEvent_\(index)_isAtomicAndShared"] = accepted == event.1
            && state.revision == event.2
            && material.sourceMaterialAlpha(layer: original, snapshot: frame) == event.3
            && material.sourceMaterialAlpha(layer: clone, snapshot: frame) == event.3
    }
    let before = state.userValues
    checks["unavailableConsumerRejectsWithoutMutation"] = !state.apply(.number(0.3),
        forPropertyKey: "liveOpacity", unavailableConsumerTargets: [target])
        && state.userValues == before && state.revision == 3
    var inactive = ScenePropertyLiveUpdateState(program: program,
        effectiveValues: ["liveOpacity": .number(0.5)], activeConsumerTargets: [])
    checks["inactiveConsumerCannotAcceptLiveMutation"] = !inactive.apply(.number(0.3), forPropertyKey: "liveOpacity")
        && inactive.revision == 0
    let precedence = SceneBaseMaterialProviderBindingProgram(baseMaterialBindings: [:],
        sourceMaterialAlphaByLayerID: [original.id: .constant(0.9)],
        sourceMaterialAlphaByModel: [modelPath: .property(target: target, fallback: 0.6)])
    checks["builtinLayerOwnerKeepsPrecedence"] = precedence.sourceMaterialAlpha(layer: original, snapshot: initial) == 0.9
        && precedence.sourceMaterialAlpha(layer: clone, snapshot: initial) == 0.5
    let staticMaterial = SceneBaseMaterialProviderBindingCompiler.compile(descriptor: descriptor,
        materialInstancesByLayerID: [:], scriptBindings: [], materialPropertyTargets: [],
        provenBindings: [.init(modelPath: modelPath, sourceLayerID: original.id,
            materialPath: materialPath, colorKey: "surface-key", scriptSource: nil,
            scriptProperties: [:], authoredColor: SIMD3(repeating: 1), authoredAlpha: 0.25)])
    checks["staticAlphaHasNoPropertyOwner"] = staticMaterial.sourceMaterialAlphaPropertyTargets.isEmpty
        && staticMaterial.sourceMaterialAlpha(layer: original, snapshot: initial) == 0.25
        && staticMaterial.sourceMaterialAlpha(layer: clone, snapshot: initial) == 0.25
    for (name, keys, user) in [("extraWrapper", ["extra", "user", "value"], "liveOpacity"),
                              ("invalidUserName", ["user", "value"], "") ] {
        var rejectedPass = pass
        rejectedPass.constantShaderValues["transmission-amount"] = .init(rawValue: "0.6", userBinding: user,
            components: [0.6], userValueKind: .string, bindingKeys: keys)
        checks["propertyFactoryRejects_\(name)"] = SceneMaterialPropertyBindingCompiler.compile(
            descriptor: .init(layers: [original], modelMaterialLinks: descriptor.modelMaterialLinks,
                materialPasses: [rejectedPass], texturePropertyKeys: []),
            materialInstancesByLayerID: [:], provenBindings: [fact]).isEmpty
    }
    return checks
}
