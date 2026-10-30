import Foundation

extension Harness {
    static func passCases(_ fixture: PropertyVectorFixture) -> PropertyVectorObservations {
        let descriptor = fixture.descriptor
        let domain = fixture.domain
        let program = fixture.program
        let frame = fixture.frame
        let passVectorTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "scale"
        )
        let passVectorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passVectorBinding(
                source: passVectorSource, value: "1 1",
                wrapperKeys: ["script", "user", "value"]
            )],
            userPropertyDefinitions: [],
            generation: 20
        )
        let passVectorResult = passVectorProgram.evaluate(
            inputs: [passVectorTarget: .vector2(1, 1)],
            effectivePropertyValues: [:],
            frame: frame
        )
        let rejectedPassVectorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passVectorBinding(
                source: passVectorSource, value: "1 1",
                wrapperKeys: ["extra", "script", "user", "value"]
            )],
            userPropertyDefinitions: [],
            generation: 21
        )
        let userBoundPassVectorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passVectorBinding(
                key: "scaleUser", source: passVectorSource, value: "1 1",
                wrapperKeys: ["script", "user", "value"]
            )],
            userPropertyDefinitions: [],
            generation: 22
        )
        let passColorTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "color"
        )
        let userColorRoot: [String: Any] = ["objects": [[
            "id": 10, "effects": [["id": 100, "passes": [[
                "id": 200, "constantshadervalues": ["userColor": [
                    "script": passVectorSource, "scriptproperties": [:],
                    "user": "palette", "value": "1 1 1",
                ]],
            ]]]],
        ]]]
        let userColorIR = SceneScriptBindingIRParser.parse(document: userColorRoot)
        func projectedUserColor(_ key: String?) -> Int {
            let original = userColorIR.bindings[0]
            let binding = SceneScriptBindingIR(
                source: original.source, owner: original.owner,
                targetPath: original.targetPath, properties: original.properties,
                authoredValue: original.authoredValue, valueType: original.valueType,
                wrapperKeys: original.wrapperKeys, userPropertyKey: key
            )
            return SceneScriptVectorProgram.project(
                descriptor: descriptor, scriptBindings: [binding]
            ).passTargets.count
        }
        let userColorTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "userColor"
        )
        let palette = SceneUserPropertyDefinition(
            key: "palette", title: "Palette", kind: .color, runtimeType: "color",
            order: 0, index: nil, minimumValue: nil, maximumValue: nil,
            stepValue: nil, allowsFractionalValues: true, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: .string("1 1 1"), options: []
        )
        let userColorInput = ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(root: userColorRoot),
            catalog: .init(definitions: [palette])
        ).program
        let userColorProgram = SceneScriptVectorProgram.compile(
            domain: domain, descriptor: descriptor, scriptBindings: userColorIR.bindings,
            userPropertyDefinitions: [palette], generation: 120
        )
        var userColorState = ScenePropertyLiveUpdateState(program: userColorInput,
            effectiveValues: ["palette": .string("1 1 1")],
            activeConsumerTargets: userColorProgram.livePropertyInputTargets)
        var userColorChanges: [Bool] = []
        func evaluateUserColor(_ raw: String) -> SceneScriptVectorFrameResult {
            userColorChanges.append(userColorState.apply(.string(raw), forPropertyKey: "palette"))
            return userColorProgram.evaluate(
                inputs: userColorState.userValues,
                effectivePropertyValues: userColorState.effectiveValues, frame: frame,
                propertyRevision: userColorState.revision
            )
        }
        let userColorProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor, scriptBindings: userColorIR.bindings
        )
        let userColorFirst = evaluateUserColor("0.2 0.3 0.4")
        let userColorChanged = evaluateUserColor("0.1 0.2 0.3")
        let beforeInvalidColor = userColorState
        let invalidColorAccepted = userColorState.apply(.string("not a color"), forPropertyKey: "palette")
        let invalidColorProperties: [String: SceneUserPropertyValue] = ["palette": .string("not a color")]
        let userColorInvalid = userColorProgram.evaluate(
            inputs: userColorInput.evaluate(effectiveValues: invalidColorProperties).userValues,
            effectivePropertyValues: invalidColorProperties, frame: frame)
        let passColorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passVectorBinding(
                key: "color", source: passColorSource, value: "1 1 1",
                wrapperKeys: ["script", "scriptproperties", "value"],
                properties: [
                    "speed": .number(0.25),
                    "saturation": .number(1),
                    "brightness": .number(1),
                ]
            )],
            userPropertyDefinitions: [],
            generation: 23
        )
        let partitionedPassProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [
                passVectorBinding(
                    source: passVectorSource, value: "1 1",
                    wrapperKeys: ["script", "user", "value"]
                ),
                passVectorBinding(
                    key: "color", source: passColorSource, value: "1 1 1",
                    wrapperKeys: ["script", "scriptproperties", "value"],
                    properties: [
                        "speed": .number(0.25),
                        "saturation": .number(1),
                        "brightness": .number(1),
                    ]
                ),
            ],
            userPropertyDefinitions: [],
            excludedTargets: [passColorTarget],
            generation: 24
        )
        let partitionedPassResult = partitionedPassProgram.evaluate(
            inputs: [
                passVectorTarget: .vector2(1, 1),
                passColorTarget: .vector3(1, 1, 1),
            ],
            effectivePropertyValues: [:],
            frame: frame
        )
        let passColorResult = passColorProgram.evaluate(
            inputs: [passColorTarget: SceneDynamicValue.vector3(1, 1, 1)].filter {
                passColorProgram.inputTargets.contains($0.key)
                    && passColorProgram.inputValueTypes.contains($0.value.valueType)
            },
            effectivePropertyValues: [:],
            frame: frame
        )
        defer { fixture.retained += [passVectorProgram, rejectedPassVectorProgram, userBoundPassVectorProgram, userColorProgram, passColorProgram, partitionedPassProgram] }
        return [
            "passVectorBindings": { passVectorProgram.bindings.count },
            "passVectorValue": { vector2(passVectorResult.values[passVectorTarget]) },
            "passVectorFailures": { passVectorResult.failures.count },
            "passVectorWrongWrapperRejected": { rejectedPassVectorProgram.bindings.isEmpty },
            "passVectorUserProviderRejected": { userBoundPassVectorProgram.bindings.isEmpty },
            "userColorExactInput": { userColorProjection.consumesUserProperty(
                key: "palette", target: userColorTarget, valueType: .vector3) },
            "userColorLiveFacts": { [
                "outerLiveInputRegistered": userColorProgram.livePropertyInputTargets.contains(userColorTarget),
                "oneRegisteredTarget": userColorProgram.livePropertyInputTargets == [userColorTarget],
                "hotChangesAccepted": userColorChanges == [true, true],
                "rejectedUpdateAtomic": !invalidColorAccepted && unchanged(userColorState, from: beforeInvalidColor)
                    && userColorState.revision == beforeInvalidColor.revision,
            ] },
            "userColorForeignInput": { userColorProjection.consumesUserProperty(
                key: "foreign", target: userColorTarget, valueType: .vector3) },
            "userColorScalarInput": { userColorProjection.consumesUserProperty(
                key: "palette", target: userColorTarget, valueType: .scalar) },
            "userColorInputKey": { userColorIR.bindings.first?.userPropertyKey ?? "missing" },
            "userColorMismatchedKeyCount": { projectedUserColor("foreignPalette") },
            "userColorMissingKeyCount": { projectedUserColor(nil) },
            "userColorIRCount": { userColorIR.bindings.count },
            "userColorOwnerCount": { userColorProgram.bindings.count },
            "userColorInputCount": { userColorInput.instructions.count },
            "userColorFirst": { vector(userColorFirst.values[userColorTarget]) },
            "userColorChanged": { vector(userColorChanged.values[userColorTarget]) },
            "userColorInvalidUnpublished": { userColorInvalid.values[userColorTarget] == nil },
            "passColorBindings": { passColorProgram.bindings.count },
            "passColorValue": { vector(passColorResult.values[passColorTarget]) },
            "passColorFailures": { passColorResult.failures.count },
            "partitionedMediaTargetExcluded": { !partitionedPassProgram.definitions
                .contains { $0.target == passColorTarget } },
            "partitionedGenericPeerPreserved": { partitionedPassProgram.definitions
                .map(\.target) == [passVectorTarget] },
            "partitionedGenericPeerValue": { vector2(
                partitionedPassResult.values[passVectorTarget]
            ) },
            "partitionedMediaTargetNotPublished": {
                partitionedPassResult.values[passColorTarget] == nil },
            "partitionedGenericPeerSucceeded": { partitionedPassResult.failures.isEmpty },
        ]
    }
}

extension Harness {
    static func namedUserPassScalarCases(_ fixture: PropertyVectorFixture) -> PropertyVectorObservations {
        let keys = ["script", "user", "value"]
        func root(_ wrapper: [String: Any], name: String) -> [String: Any] {
            ["objects": [["id": 10, "effects": [["id": 100, "passes": [[
                "id": 200, "constantshadervalues": [name: wrapper],
            ]]]]]]]
        }
        func descriptor(_ source: String, name: String, user: String,
                        components: [Double] = [0.6], bindingKeys: [String]? = nil,
                        properties: [String: SceneJSONValue]? = nil) -> SceneRenderDescriptor {
            .init(layers: [.init(id: 10, layerIndex: 0, name: "Owned scalar peer", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], scaleHasScript: false, alpha: 1,
                effects: [.init(name: "Owned pass", effectID: 100, passes: [.init(
                    passIndex: 0, id: 200, constantShaderValues: [name: .init(
                        scriptSource: source, components: components, userValueKind: .string,
                        userBinding: user, bindingKeys: bindingKeys ?? keys,
                        scriptProperties: properties)])])])])
        }
        func definition(_ key: String, kind: SceneUserPropertyKind = .slider) -> SceneUserPropertyDefinition {
            .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue, order: 0,
                index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
                allowsFractionalValues: true, fractionalPrecision: nil, displayCondition: nil,
                defaultValue: kind == .color ? .string("1 1 1") : .number(0.25), options: [])
        }
        let variants: [(String, String, String, [String: Any]?, String?)] = [
            ("amount", "phase", "export function update(value) { return value * 3 + 0.125; }", nil, nil),
            ("tilt", "gain", "export function update(incoming) { const v = incoming; return 0.125 + 3 * v; }", nil, nil),
            ("spin", "knob", "export function update(input) { return (input + 0.125 / 3) * 3; }", nil, nil),
            ("emptyProperties", "outer", "export function update(value) { return value * 3 + 0.125; }", [:], nil),
            ("brightness", "opacity", """
                export var scriptProperties = createScriptProperties()
                    .addSlider({name: 'multiplier', value: 3}).addSlider({name: 'bias', value: 0.125}).finish();
                let initialized = 0;
                export function init(value) { initialized++; return value; }
                export function update(value) {
                    if (initialized !== 1) throw new Error('owner recreated');
                    return value * scriptProperties.multiplier + scriptProperties.bias;
                }
                """, ["multiplier": ["user": "factor", "value": 3.0], "bias": 0.125], "factor"),
            ("rotation", "dial", """
                export var scriptProperties = createScriptProperties()
                    .addSlider({name: 'slope', value: 3}).addSlider({name: 'offset', value: 0.125}).finish();
                let starts = 0;
                export function init(input) { starts += 1; return input; }
                export function update(incoming) {
                    if (starts != 1) throw new Error('owner recreated');
                    const parameters = scriptProperties;
                    return parameters.offset + parameters.slope * incoming;
                }
                """, ["slope": ["user": "gradient", "value": 3.0], "offset": 0.125], "gradient"),
        ]
        var variantValues: [[Double]] = [], variantFacts: [[String: Bool]] = []
        var propertyValues: [String: [Double]] = [:], propertyFacts: [String: [String: Bool]] = [:]
        for (ordinal, variant) in variants.enumerated() {
            let (name, user, source, properties, innerUser) = variant
            var wrapper: [String: Any] = ["script": source, "user": user, "value": 0.15]
            if let properties { wrapper["scriptproperties"] = properties }
            let metadata = properties?.compactMapValues(SceneJSONValue.init(jsonObject:))
            let document = root(wrapper, name: name)
            let parsed = SceneScriptBindingIRParser.parse(document: document)
            let prepared = descriptor(source, name: name, user: user,
                bindingKeys: wrapper.keys.sorted(), properties: metadata)
            let target = SceneDynamicTarget.effectConstant(layerID: 10, effectIndex: 0, passIndex: 0, name: name)
            let definitions = [definition(user)] + (innerUser.map { [definition($0)] } ?? [])
            let input = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: document),
                catalog: .init(definitions: definitions))
            let vm = SceneScriptScalarProgram.compile(domain: fixture.domain, descriptor: prepared,
                scriptBindings: parsed.bindings, userPropertyDefinitions: definitions,
                generation: UInt64(1_500 + ordinal))
            fixture.retained.append(vm)
            let initialOwners = vm.bindings.map(ObjectIdentifier.init)
            var effective: [String: SceneUserPropertyValue] = [user: .number(0.6)]
            if let innerUser { effective[innerUser] = .number(3) }
            var state = ScenePropertyLiveUpdateState(program: input.program,
                effectiveValues: effective, activeConsumerTargets: vm.livePropertyInputTargets)
            var outputs: [Double] = [], failed = 0, sources: [String] = []
            var changes = true
            let updates = innerUser == nil ? [(0.6, 3.0), (0.2, 3.0), (0.4, 3.0)]
                : [(0.6, 3.0), (0.2, 3.0), (0.2, 2.0), (0.4, 2.0), (0.4, 3.0)]
            for (current, factor) in updates {
                changes = state.apply(.number(current), forPropertyKey: user) && changes
                if let innerUser { changes = state.apply(.number(factor), forPropertyKey: innerUser) && changes }
                let preliminary = SceneDynamicSnapshotResolver().resolve(frameIndex: state.revision,
                    generation: vm.generation, definitions: input.program.definitions,
                    userValues: state.userValues).snapshot
                let evaluated = vm.evaluate(inputs: preliminary.values(for: vm.inputTargets),
                    frame: fixture.frame, effectivePropertyValues: state.effectiveValues,
                    propertyRevision: state.revision)
                let settled = SceneDynamicSnapshotResolver().resolve(frameIndex: state.revision,
                    generation: vm.generation, definitions: input.program.definitions,
                    userValues: state.userValues, sceneScriptValues: evaluated.values).snapshot
                outputs.append(scalar(settled[target]?.value))
                sources.append(settled[target]?.source.rawValue ?? "missing")
                failed += evaluated.failures.count
            }
            let innerTarget = innerUser.flatMap { key in
                input.program.instructions.first { $0.propertyKey == key }?.target
            }
            let facts = [
                "rawFallbackRetained": parsed.bindings.first?.authoredValue == .number(0.15)
                    && vm.definitions.first?.authoredValue == .scalar(0.15),
                "resolvedCurrentDiffers": prepared.layers[0].effects[0].passes[0]
                    .constantShaderValues[name]?.components == [0.6],
                "exactParserIdentity": parsed.bindings.count == 1 && parsed.diagnostics.isEmpty
                    && parsed.bindings[0].userPropertyKey == user
                    && parsed.bindings[0].wrapperKeys == wrapper.keys.sorted()
                    && parsed.bindings[0].properties == (metadata ?? [:]),
                "oneOwnerAndInput": vm.bindings.count == 1
                    && input.program.instructions.count == (innerUser == nil ? 1 : 2),
                "sameVMForAllChanges": !initialOwners.isEmpty && vm.bindings.map(ObjectIdentifier.init) == initialOwners,
                "outerLiveInputRegistered": vm.livePropertyInputTargets.contains(target),
                "distinctPropertyInput": innerUser == nil || innerTarget.map {
                    $0 != target && vm.livePropertyInputTargets.contains($0)
                } == true,
                "hotChanges": changes,
                "scriptIsSoleSettledSource": sources == Array(repeating: "sceneScript", count: updates.count),
                "noVMFailures": failed == 0,
            ]
            if properties == nil { variantValues.append(outputs); variantFacts.append(facts) }
            else { propertyValues[name] = outputs; propertyFacts[name] = facts }
        }
        let (name, user, source, _, _) = variants[0]
        let document = root(["script": source, "user": user, "value": 0.15], name: name)
        let parsed = SceneScriptBindingIRParser.parse(document: document)
        let prepared = descriptor(source, name: name, user: user)
        let target = SceneDynamicTarget.effectConstant(layerID: 10, effectIndex: 0, passIndex: 0, name: name)
        var parserRejections: [String: Bool] = [:]
        let rejected: [(String, [String: Any])] = [
            ("bool", ["value": true]), ("numericString", ["value": "0.15"]),
            ("vec2", ["value": "1 2"]), ("array", ["value": [1, 2, 3]]),
            ("nonFinite", ["value": Double.infinity]), ("emptyUser", ["user": ""]),
            ("numericUser", ["user": 3]), ("paddedUser", ["user": " phase "]),
            ("extra", ["extra": 1]), ("animation", ["animation": [:]]),
            ("malformedProperties", ["scriptproperties": [1, 2]]),
        ]
        for (label, replacement) in rejected {
            var wrapper: [String: Any] = ["script": source, "user": user, "value": 0.15]
            wrapper.merge(replacement) { _, new in new }
            let result = SceneScriptBindingIRParser.parse(document: root(wrapper, name: name))
            parserRejections[label] = result.bindings.isEmpty && !result.diagnostics.isEmpty
        }
        let legacyWrappers: [[String: Any]] = [["script": source, "value": 0.15],
            ["script": source, "user": NSNull(), "value": 0.15],
            ["script": passVectorSource, "user": "palette", "value": "1 1 1"]]
        let legacyParser = legacyWrappers.map {
            SceneScriptBindingIRParser.parse(document: root($0, name: name)).bindings.count
        }
        let binding = parsed.bindings[0]
        func altered(userKey: String?, path: [SceneScriptBindingPathComponent]? = nil) -> SceneScriptBindingIR {
            .init(source: binding.source, owner: binding.owner, targetPath: path ?? binding.targetPath,
                properties: binding.properties, authoredValue: binding.authoredValue, valueType: binding.valueType,
                wrapperKeys: binding.wrapperKeys, userPropertyKey: userKey)
        }
        let projectionFacts = [
            "missingInputIdentity": SceneScriptScalarProgram.projectedTargets(descriptor: prepared,
                scriptBindings: [altered(userKey: nil)]).isEmpty,
            "wrongInputIdentity": SceneScriptScalarProgram.projectedTargets(descriptor: prepared,
                scriptBindings: [altered(userKey: "foreign")]).isEmpty,
            "wrongTarget": SceneScriptScalarProgram.projectedTargets(descriptor: prepared,
                scriptBindings: [altered(userKey: user, path: Array(binding.targetPath.dropLast()) + [.key("foreign")])]).isEmpty,
            "wrongSource": SceneScriptScalarProgram.projectedTargets(descriptor: descriptor("export function update(v) { return v; }", name: name, user: user),
                scriptBindings: parsed.bindings).isEmpty,
            "duplicateOwner": SceneScriptScalarProgram.projectedTargets(descriptor: prepared,
                scriptBindings: parsed.bindings + parsed.bindings).isEmpty,
            "excludedTarget": SceneScriptScalarProgram.projectedDefinitions(descriptor: prepared,
                scriptBindings: parsed.bindings, excludedTargets: [target]).isEmpty,
        ]
        var propertyFailures: [String: Bool] = [:]
        for (label, catalog) in [("missing", []), ("wrongKey", [definition("foreign")]),
                                  ("wrongKind", [definition(user, kind: .color)]),
                                  ("duplicate", [definition(user), definition(user)])] {
            let input = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: document), catalog: .init(definitions: catalog))
            let vm = SceneScriptScalarProgram.compile(domain: fixture.domain, descriptor: prepared,
                scriptBindings: parsed.bindings, generation: UInt64(1_550 + propertyFailures.count))
            fixture.retained.append(vm)
            var state = ScenePropertyLiveUpdateState(program: input.program,
                effectiveValues: [user: .number(0.6)], activeConsumerTargets: vm.livePropertyInputTargets)
            let fallback = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: vm.generation,
                definitions: vm.definitions, userValues: state.userValues).snapshot
            let evaluated = vm.evaluate(inputs: fallback.values(for: vm.inputTargets), frame: fixture.frame)
            propertyFailures[label] = !input.diagnostics.isEmpty && input.program.instructions.isEmpty
                && state.userValues[target] == nil && !state.apply(.number(0.4), forPropertyKey: user)
                && vm.bindings.count == 1 && vm.definitions.first?.authoredValue == .scalar(0.15)
                && evaluated.failures.isEmpty && abs(scalar(evaluated.values[target]) - 0.575) < 1e-10
        }
        var badFallbacks: [String: Double] = [:], badFacts: [String: Bool] = [:]
        let badReturns = [("bool", "true"), ("string", "'0.5'"), ("vec2", "new Vec2(1, 2)"),
                          ("nan", "NaN"), ("infinity", "Infinity"),
                          ("throw", "(() => { throw new Error('owned failure'); })()"),
                          ("undefined", "undefined")]
        let returnCases = [false, true].flatMap { properties in
            badReturns.map { ($0.0, $0.1, properties) }
        }
        for (ordinal, pair) in returnCases.enumerated() {
            let (kind, expression, properties) = pair
            let label = properties ? "properties-\(kind)" : kind
            let prefix = properties ? "export var scriptProperties = createScriptProperties().addSlider({name:'adjustment', value:1}).finish();" : ""
            let script = prefix + "export function update(value) { return \(expression); }"
            var wrapper: [String: Any] = ["script": script, "user": user, "value": 0.15]
            if properties { wrapper["scriptproperties"] = ["adjustment": 1.0] }
            let badRoot = root(wrapper, name: name)
            let badIR = SceneScriptBindingIRParser.parse(document: badRoot)
            let input = ScenePropertyBindingCompiler().compile(report: SceneUserPropertyBindingParser().parse(root: badRoot),
                catalog: .init(definitions: [definition(user)])).program
            let vm = SceneScriptScalarProgram.compile(domain: fixture.domain,
                descriptor: descriptor(script, name: name, user: user, bindingKeys: wrapper.keys.sorted(),
                    properties: properties ? ["adjustment": .number(1)] : nil), scriptBindings: badIR.bindings,
                userPropertyDefinitions: [definition(user)], generation: UInt64(1_600 + ordinal))
            fixture.retained.append(vm)
            let state = ScenePropertyLiveUpdateState(program: input, effectiveValues: [user: .number(0.4)],
                activeConsumerTargets: vm.livePropertyInputTargets)
            let evaluated = vm.evaluate(inputs: state.userValues, frame: fixture.frame,
                effectivePropertyValues: state.effectiveValues, propertyRevision: state.revision)
            let settled = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: vm.generation,
                definitions: input.definitions, userValues: state.userValues, sceneScriptValues: evaluated.values).snapshot
            badFallbacks[label] = scalar(settled[target]?.value)
            // The existing Scalar VM coerces Bool/numeric String returns; only
            // the raw named wrapper remains exact Number at parser admission.
            let coerced = kind == "bool" ? 1.0 : kind == "string" ? 0.5 : nil
            badFacts[label] = vm.bindings.count == 1 && (kind == "undefined" || coerced != nil
                ? evaluated.failures.isEmpty && settled[target]?.source == .sceneScript
                : evaluated.values[target] == nil && evaluated.failures.count == 1 && settled[target]?.source == .userProperty)
        }
        return ["namedUserScalar": { ["variantValues": variantValues, "variantFacts": variantFacts,
            "parserRejections": parserRejections, "legacyParserCounts": legacyParser,
            "projectionRejections": projectionFacts, "propertyDefinitionFailures": propertyFailures,
            "badFallbacks": badFallbacks, "badReturnFacts": badFacts,
            "propertyValues": propertyValues, "propertyFacts": propertyFacts] as [String: Any] }]
    }
}
