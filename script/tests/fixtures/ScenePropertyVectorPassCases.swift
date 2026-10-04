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
        func evaluateUserColor(_ raw: String) -> SceneScriptVectorFrameResult {
            let properties: [String: SceneUserPropertyValue] = ["palette": .string(raw)]
            return userColorProgram.evaluate(
                inputs: userColorInput.evaluate(effectiveValues: properties).userValues,
                effectivePropertyValues: properties, frame: frame
            )
        }
        let userColorProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor, scriptBindings: userColorIR.bindings
        )
        let userColorFirst = evaluateUserColor("0.2 0.3 0.4")
        let userColorChanged = evaluateUserColor("0.1 0.2 0.3")
        let userColorInvalid = evaluateUserColor("not a color")
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
