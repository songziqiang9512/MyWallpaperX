import Foundation

extension Harness {
    static func materialCases(_ fixture: PropertyVectorFixture) -> PropertyVectorObservations {
        let source = """
        export var scriptProperties = createScriptProperties()
          .addCheckbox({name:'ifchange',value:true}).finish();
        export function update(value) {
          if (scriptProperties.ifchange) return value.multiply(0.5);
        }
        """
        let fact = SceneBaseMaterialColorModulationCompiler.Binding(
            modelPath: "models/mixed-color.json", sourceLayerID: 10,
            materialPath: "materials/unseen/mixed.json", colorKey: "surface-tint",
            scriptSource: source,
            scriptProperties: ["ifchange": .object(["user": .string("animate"), "value": .bool(true)])],
            authoredColor: SIMD3(0.729, 0.345, 0.729), colorUserPropertyKey: "palette")
        let target = fact.colorPropertyTarget!
        let innerPath = fact.colorBindingPath + [.key("scriptproperties"), .key("ifchange")]
        let innerTarget = SceneDynamicTarget.scriptInstanceProperty(layerID: 10,
            path: SceneScriptPropertyTargetPath.encoded(innerPath))
        func definition(_ key: String, _ kind: SceneUserPropertyKind,
            _ fallback: SceneUserPropertyValue) -> SceneUserPropertyDefinition {
            .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue, order: 0,
                index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
                allowsFractionalValues: true, fractionalPrecision: nil,
                displayCondition: nil, defaultValue: fallback, options: [])
        }
        let definitions = [definition("palette", .color, .string("0.729 0.345 0.729")),
            definition("animate", .bool, .bool(true))]
        // The actual material declaration factory is exercised by the provider
        // gate. These are its typed outputs entering the real property owner.
        let declarations: [SceneUserPropertyBinding] = [
            .init(reference: .init(key: "palette", condition: nil),
                fallbackValue: .string("0.729 0.345 0.729"), path: .init(components: fact.colorBindingPath),
                target: .materialShaderValue(layerID: 10, passIndex: 0,
                    name: fact.colorKey, materialPath: fact.materialPath)),
            .init(reference: .init(key: "animate", condition: nil), fallbackValue: .bool(true),
                path: .init(components: innerPath),
                target: .scriptProperty(layerID: 10, path: SceneScriptPropertyTargetPath.encoded(innerPath))),
        ]
        let input = ScenePropertyBindingCompiler().compile(report: .init(bindings: declarations, diagnostics: []),
            catalog: .init(definitions: definitions)).program
        let projection = SceneScriptVectorProgram.project(descriptor: fixture.descriptor, scriptBindings: [],
            admittedLayerColorConsumerIDs: [10], shaderContracts: [.init(materialBindings: [fact])])
        let vm = SceneScriptVectorProgram.compileNonPass(domain: fixture.domain, descriptor: fixture.descriptor,
            projection: projection, userPropertyDefinitions: definitions, generation: 730)
        var state = ScenePropertyLiveUpdateState(program: input, effectiveValues: [
            "palette": .string("0.729 0.345 0.729"), "animate": .bool(false)
        ], activeConsumerTargets: Set(input.instructions.map(\.target)))
        func evaluate(_ vm: SceneScriptVectorProgram) -> SceneScriptVectorFrameResult {
            vm.evaluate(inputs: state.userValues.filter { vm.inputTargets.contains($0.key) },
                effectivePropertyValues: state.effectiveValues, frame: fixture.frame, propertyRevision: state.revision)
        }
        let initial = evaluate(vm)
        let enabled = state.apply(.bool(true), forPropertyKey: "animate")
        let animated = evaluate(vm)
        let changed = state.apply(replacements: ["palette": .string("0.2 0.6 0.8"), "animate": .bool(false)],
            changedPropertyKeys: ["palette", "animate"])
        let current = evaluate(vm)
        let resolved = SceneDynamicSnapshotResolver().resolve(frameIndex: 3, generation: 730,
            definitions: input.definitions, userValues: state.userValues,
            sceneScriptValues: current.values).snapshot
        let before = state.userValues, revision = state.revision
        let rejected = !state.apply(replacements: ["palette": .string("nan 0.6 0.8"), "animate": .bool(true)],
            changedPropertyKeys: ["palette", "animate"])
        let preserved = state.userValues == before && state.revision == revision
        let badSource = source.replacingOccurrences(of: "value.multiply(0.5)", with: "'invalid-vector'")
        let badFact = SceneBaseMaterialColorModulationCompiler.Binding(modelPath: fact.modelPath,
            sourceLayerID: 10, materialPath: fact.materialPath, colorKey: fact.colorKey,
            scriptSource: badSource, scriptProperties: fact.scriptProperties,
            authoredColor: fact.authoredColor, colorUserPropertyKey: "palette")
        let badProjection = SceneScriptVectorProgram.project(descriptor: fixture.descriptor, scriptBindings: [],
            admittedLayerColorConsumerIDs: [10], shaderContracts: [.init(materialBindings: [badFact])])
        let badVM = SceneScriptVectorProgram.compileNonPass(domain: fixture.domain, descriptor: fixture.descriptor,
            projection: badProjection, userPropertyDefinitions: definitions, generation: 731)
        let enableBad = state.apply(.bool(true), forPropertyKey: "animate")
        let bad = evaluate(badVM)
        let fallback = SceneDynamicSnapshotResolver().resolve(frameIndex: 4, generation: 731,
            definitions: input.definitions, userValues: state.userValues,
            sceneScriptValues: bad.values).snapshot
        let recover = state.apply(.bool(false), forPropertyKey: "animate")
        let recovered = evaluate(badVM)
        defer { fixture.retained += [vm, badVM] }
        let result: [String: Any] = [
            "ownerCount": vm.bindings.count,
            "publisherCount": input.instructions.count,
            "borrowedExactUserTarget": projection.consumesUserProperty(key: "palette", target: target, valueType: .vector3),
            "foreignUserNotBorrowed": !projection.consumesUserProperty(key: "other", target: target, valueType: .vector3),
            "nestedTargetActive": vm.activeLivePropertyInputTargets == [innerTarget],
            "catalogExclusionKeepsPreparedFact": projection.excludingTargets([target]).materialBindings.count == 1,
            "initialUndefined": vector(initial.values[target]),
            "enabledAnimated": vector(animated.values[target]),
            "currentUndefined": vector(current.values[target]),
            "currentSource": resolved[target]?.source.rawValue ?? "missing",
            "currentFailures": initial.failures.count + animated.failures.count + current.failures.count,
            "validHotChanges": enabled && changed,
            "invalidTransactionPreserved": rejected && preserved,
            "layerStyleUntouched": state.userValues[.layer(layerID: 10, field: .color)] == nil,
            "badReturnUnpublished": bad.values[target] == nil && bad.failures.count == 1,
            "badReturnFallback": vector(fallback[target]?.value),
            "badReturnFallbackSource": fallback[target]?.source.rawValue ?? "missing",
            "recoveredUndefined": vector(recovered.values[target]),
            "recoveredFailures": recovered.failures.count,
            "badAndRecoveryChangesAccepted": enableBad && recover,
        ]
        return ["materialMixed": { result }]
    }
}
