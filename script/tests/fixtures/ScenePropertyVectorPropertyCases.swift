import Foundation

extension Harness {
    static func propertyCases(_ fixture: PropertyVectorFixture) -> (observations: PropertyVectorObservations, audioSnapshot: SceneAudioSpectrumSnapshot) {
        let descriptor = fixture.descriptor
        let domain = fixture.domain
        let program = fixture.program
        let frame = fixture.frame
        let currentPropertyTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "colormode"
        )
        let modeDefinition = SceneUserPropertyDefinition(
            key: "ui_editor_properties_mode", title: "Mode", kind: .combo,
            runtimeType: "combo", order: 0, index: nil,
            minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: false, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: .string("1"), options: []
        )
        let currentPropertyProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "colormode", source: currentPropertyEventSource, value: 0
            )],
            userPropertyDefinitions: [modeDefinition],
            generation: 240
        )
        let currentPropertyFirst = currentPropertyProgram.evaluate(
            inputs: [currentPropertyTarget: .scalar(0)],
            frame: frame,
            effectivePropertyValues: [
                "ui_editor_properties_mode": .string("1")
            ],
            propertyRevision: 1
        )
        let currentPropertyStable = currentPropertyProgram.evaluate(
            inputs: [currentPropertyTarget: .scalar(1)],
            frame: frame,
            effectivePropertyValues: [
                "ui_editor_properties_mode": .string("1")
            ],
            propertyRevision: 1
        )
        let currentPropertyChanged = currentPropertyProgram.evaluate(
            inputs: [currentPropertyTarget: .scalar(1)],
            frame: frame,
            effectivePropertyValues: [
                "ui_editor_properties_mode": .string("3")
            ],
            propertyRevision: 2
        )
        let timerFrame = SceneScriptFrameInput(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0.025),
            simulationFrameTime: 0.025,
            sceneTime: 2.025
        ), timeZone: TimeZone(secondsFromGMT: 0)!)
        let currentPropertyTimer = currentPropertyProgram.evaluate(
            inputs: [currentPropertyTarget: .scalar(3)],
            frame: timerFrame,
            effectivePropertyValues: [
                "ui_editor_properties_mode": .string("3")
            ],
            propertyRevision: 2
        )
        let settledFrame = SceneScriptFrameInput(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0.05),
            simulationFrameTime: 0.025,
            sceneTime: 2.05
        ), timeZone: TimeZone(secondsFromGMT: 0)!)
        let currentPropertySettled = currentPropertyProgram.evaluate(
            inputs: [currentPropertyTarget: .scalar(9)],
            frame: settledFrame,
            effectivePropertyValues: [
                "ui_editor_properties_mode": .string("3")
            ],
            propertyRevision: 2
        )
        let invalidCurrentPropertyProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "colormode", source: currentPropertyEventSource, value: 0
            )],
            userPropertyDefinitions: [modeDefinition],
            generation: 241
        )
        let invalidCurrentProperty = invalidCurrentPropertyProgram.evaluate(
            inputs: [currentPropertyTarget: .scalar(0)],
            frame: frame,
            effectivePropertyValues: [
                "ui_editor_properties_mode": .string("invalid")
            ],
            propertyRevision: 1
        )
        let propertyEventProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin",
                source: propertyEventSource,
                value: "20 2250 0",
                properties: ["step": .number(3)]
            )],
            userPropertyDefinitions: [],
            generation: 17
        )
        let propertyEventTarget = SceneDynamicTarget.layer(
            layerID: 10, field: .origin
        )
        let propertyEventFirst = propertyEventProgram.evaluate(
            inputs: [propertyEventTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: ["mode": .number(2)], frame: frame,
            propertyRevision: 1
        )
        let propertyEventStable = propertyEventProgram.evaluate(
            inputs: [propertyEventTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: ["mode": .number(2)], frame: frame,
            propertyRevision: 1
        )
        let propertyEventChanged = propertyEventProgram.evaluate(
            inputs: [propertyEventTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: ["mode": .number(4)], frame: frame,
            propertyRevision: 2
        )
        var appliedPropertyState = SceneScriptAppliedUserPropertyState()
        let propertyStateTarget = SceneDynamicTarget.layer(
            layerID: 10, field: .origin
        )
        let propertyStateFirst = appliedPropertyState.changedJSON(
            for: propertyStateTarget, current: ["mode": .number(2)],
            kinds: [:], revision: 1
        )
        appliedPropertyState.record(
            ["mode": .number(2)], revision: 1, for: propertyStateTarget
        )
        let propertyStateStable = appliedPropertyState.changedJSON(
            for: propertyStateTarget, current: ["mode": .number(2)],
            kinds: [:], revision: 1
        )
        let propertyStateChanged = appliedPropertyState.changedJSON(
            for: propertyStateTarget, current: ["mode": .number(4)],
            kinds: [:], revision: 2
        )
        let audioScaleProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "scale", source: audioScaleSource, value: "1.5 1.5 1.5",
                properties: [
                    "frequency": .number(0), "minvalue": .number(1),
                ]
            )],
            userPropertyDefinitions: [],
            generation: 18
        )
        let audioSnapshot = SceneAudioSpectrumSnapshot(
            left: [1] + Array(repeating: 0, count: 15),
            right: Array(repeating: 0, count: 16),
            left32: Array(repeating: 0, count: 32),
            right32: Array(repeating: 0, count: 32),
            left64: Array(repeating: 0, count: 64),
            right64: Array(repeating: 0, count: 64),
            generation: 1
        )
        let passAudioTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "audioScalar"
        )
        let passAudioProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "audioScalar", source: passAudioScalarSource, value: 1,
                wrapperKeys: ["script", "scriptproperties", "value"],
                properties: [
                    "frequency": .number(0), "minvalue": .number(1),
                    "maxvalue": .number(2), "smoothing": .number(20),
                ]
            )],
            generation: 24
        )
        let passAudioResult = passAudioProgram.evaluate(
            inputs: [passAudioTarget: .scalar(1)], frame: frame,
            audioSpectrum: audioSnapshot
        )
        let dynamicScalarTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "dynamicScalar"
        )
        let dynamicScalarProperties: [String: SceneJSONValue] = [
            "newSlider": .object([
                "user": .string("renamedProperty"),
                "value": .number(50),
            ]),
        ]
        let dynamicScalarProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "dynamicScalar", source: dynamicScalarSource, value: -0.2,
                wrapperKeys: ["script", "scriptproperties", "value"],
                properties: dynamicScalarProperties
            )],
            generation: 27
        )
        let dynamicScalarFirst = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .number(0.2)],
            propertyRevision: 1
        )
        let dynamicScalarStable = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .number(0.2)],
            propertyRevision: 1
        )
        let dynamicScalarChanged = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .number(0.35)],
            propertyRevision: 2
        )
        let dynamicScalarWrongType = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .string("wrong")],
            propertyRevision: 3
        )
        let dynamicScalarRecovered = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .number(0.4)],
            propertyRevision: 4
        )
        let dynamicScalarFallbackProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "dynamicScalar", source: dynamicScalarSource, value: -0.2,
                wrapperKeys: ["script", "scriptproperties", "value"],
                properties: dynamicScalarProperties
            )],
            generation: 28
        )
        let dynamicScalarFallback = dynamicScalarFallbackProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: [:]
        )
        let dynamicScalarLiveTarget = SceneDynamicTarget.scriptInstanceProperty(
            layerID: 10,
            path: [
                SceneScriptPropertyTargetPath.keyComponent("objects"),
                SceneScriptPropertyTargetPath.indexComponent(0),
                SceneScriptPropertyTargetPath.keyComponent("effects"),
                SceneScriptPropertyTargetPath.indexComponent(0),
                SceneScriptPropertyTargetPath.keyComponent("passes"),
                SceneScriptPropertyTargetPath.indexComponent(0),
                SceneScriptPropertyTargetPath.keyComponent("constantshadervalues"),
                SceneScriptPropertyTargetPath.keyComponent("dynamicScalar"),
                SceneScriptPropertyTargetPath.keyComponent("scriptproperties"),
                SceneScriptPropertyTargetPath.keyComponent("newSlider"),
            ]
        )
        let nullOuterUserScalarTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0,
            name: "dynamicScalarNull"
        )
        let nullOuterUserScalarProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "dynamicScalarNull", source: dynamicScalarSource, value: -0.2,
                wrapperKeys: ["script", "scriptproperties", "user", "value"],
                properties: dynamicScalarProperties
            )],
            generation: 31
        )
        let nullOuterUserScalarAdmitted =
            nullOuterUserScalarProgram.definitions.map(\.target)
                == [nullOuterUserScalarTarget]
        let dynamicVectorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin", source: originSource, value: "20 2250 0",
                properties: [
                    "x": .object([
                        "user": .string("renamedProperty"),
                        "value": .number(20),
                    ]),
                    "y": .number(2250),
                ]
            )],
            userPropertyDefinitions: [],
            generation: 30
        )
        let dynamicVectorLiveTarget = SceneDynamicTarget.scriptInstanceProperty(
            layerID: 10,
            path: [
                SceneScriptPropertyTargetPath.keyComponent("objects"),
                SceneScriptPropertyTargetPath.indexComponent(0),
                SceneScriptPropertyTargetPath.keyComponent("origin"),
                SceneScriptPropertyTargetPath.keyComponent("scriptproperties"),
                SceneScriptPropertyTargetPath.keyComponent("x"),
            ]
        )
        let malformedDynamicScalar = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "dynamicScalar", source: dynamicScalarSource, value: -0.2,
                wrapperKeys: ["script", "scriptproperties", "value"],
                properties: [
                    "newSlider": .object([
                        "extra": .bool(true),
                        "user": .string("renamedProperty"),
                        "value": .number(50),
                    ]),
                ]
            )],
            generation: 29
        )
        let failingDynamicScalarInitiallyActive =
            dynamicScalarProgram.activeLivePropertyInputTargets
                == [dynamicScalarLiveTarget, dynamicScalarTarget]
        let failingDynamicScalarResult = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .number(-1)]
        )
        let failingDynamicScalarBecameUnavailable =
            failingDynamicScalarResult.failures[dynamicScalarTarget] != nil
                && dynamicScalarProgram.activeLivePropertyInputTargets.isEmpty
        let scaleLiveTarget = SceneDynamicTarget.scriptInstanceProperty(
            layerID: 10,
            path: [
                SceneScriptPropertyTargetPath.keyComponent("objects"),
                SceneScriptPropertyTargetPath.indexComponent(0),
                SceneScriptPropertyTargetPath.keyComponent("scale"),
                SceneScriptPropertyTargetPath.keyComponent("scriptproperties"),
                SceneScriptPropertyTargetPath.keyComponent("size"),
            ]
        )
        let failingDynamicVectorInitiallyActive =
            program.activeLivePropertyInputTargets.contains(scaleLiveTarget)
        let failingDynamicVectorResult = program.evaluate(
            inputs: [
                .layer(layerID: 10, field: .origin): .vector3(20, 2250, 0),
                .layer(layerID: 10, field: .scale): .vector3(1.5, 1.5, 1.5),
            ],
            effectivePropertyValues: [
                "x1": .number(40), "y1": .number(2100), "size": .number(-1),
            ],
            frame: frame
        )
        let failingDynamicVectorBecameUnavailable =
            failingDynamicVectorResult.failures[
                .layer(layerID: 10, field: .scale)
            ] != nil
                && !program.activeLivePropertyInputTargets.contains(scaleLiveTarget)
                && program.activeLivePropertyInputTargets.contains(
                    dynamicVectorLiveTarget
                )
        let scalarUnavailableTargets = dynamicScalarProgram.livePropertyInputTargets
            .subtracting(dynamicScalarProgram.activeLivePropertyInputTargets)
        let directScalarConsumer = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "directScalar"
        )
        var disabledScalarLiveState = ScenePropertyLiveUpdateState(
            program: propertyProgram(bindings: [
                ("renamedProperty", dynamicScalarLiveTarget),
                ("renamedProperty", directScalarConsumer),
            ]),
            effectiveValues: ["renamedProperty": .number(0.2)],
            activeConsumerTargets: dynamicScalarProgram.livePropertyInputTargets
                .union([directScalarConsumer])
        )
        let beforeDisabledScalarLiveState = disabledScalarLiveState
        let disabledScalarLiveUpdateRejected = !disabledScalarLiveState.apply(
            .number(0.35),
            forPropertyKey: "renamedProperty",
            unavailableConsumerTargets: scalarUnavailableTargets
        )
        let disabledScalarLiveUpdateWasAtomic = unchanged(
            disabledScalarLiveState,
            from: beforeDisabledScalarLiveState
        )
        let vectorUnavailableTargets = program.livePropertyInputTargets
            .subtracting(program.activeLivePropertyInputTargets)
        var disabledVectorLiveState = ScenePropertyLiveUpdateState(
            program: propertyProgram(bindings: [
                ("size", scaleLiveTarget),
                ("x1", dynamicVectorLiveTarget),
            ]),
            effectiveValues: ["size": .number(1.5), "x1": .number(40)],
            activeConsumerTargets: program.livePropertyInputTargets
        )
        let beforeDisabledVectorLiveState = disabledVectorLiveState
        let disabledVectorLiveUpdateRejected = !disabledVectorLiveState.apply(
            .number(2),
            forPropertyKey: "size",
            unavailableConsumerTargets: vectorUnavailableTargets
        )
        let disabledVectorLiveUpdateWasAtomic = unchanged(
            disabledVectorLiveState,
            from: beforeDisabledVectorLiveState
        )
        let activeVectorSiblingAccepted = disabledVectorLiveState.apply(
            .number(41),
            forPropertyKey: "x1",
            unavailableConsumerTargets: vectorUnavailableTargets
        ) && scalar(disabledVectorLiveState.userValues[dynamicVectorLiveTarget]) == 41
        let rejectedPassAudioWrapper = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "audioScalar", source: passAudioScalarSource, value: 1,
                wrapperKeys: ["extra", "script", "scriptproperties", "value"],
                properties: ["frequency": .number(0)]
            )],
            generation: 25
        )
        let rejectedPassAudioProvider = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "audioScalarUser", source: passAudioScalarSource, value: 1,
                wrapperKeys: ["script", "scriptproperties", "value"],
                properties: ["frequency": .number(0)]
            )],
            generation: 26
        )
        let audioScaleResult = audioScaleProgram.evaluate(
            inputs: [.layer(layerID: 10, field: .scale): .vector3(1.5, 1.5, 1.5)],
            effectivePropertyValues: [:],
            frame: frame,
            audioSpectrum: audioSnapshot
        )
        defer { fixture.retained += [currentPropertyProgram, invalidCurrentPropertyProgram, propertyEventProgram, audioScaleProgram, passAudioProgram, dynamicScalarProgram, dynamicScalarFallbackProgram, nullOuterUserScalarProgram, dynamicVectorProgram, malformedDynamicScalar, rejectedPassAudioWrapper, rejectedPassAudioProvider] }
        let observations: PropertyVectorObservations = [
            "currentPropertyFirst": { scalar(
                currentPropertyFirst.values[currentPropertyTarget]
            ) },
            "currentPropertyStableSkipped": {
                currentPropertyStable.values[currentPropertyTarget] == nil },
            "currentPropertyChanged": { scalar(
                currentPropertyChanged.values[currentPropertyTarget]
            ) },
            "currentPropertyTimer": { scalar(
                currentPropertyTimer.values[currentPropertyTarget]
            ) },
            "currentPropertySettledSkipped": {
                currentPropertySettled.values[currentPropertyTarget] == nil },
            "currentPropertyLiveConsumer": {
                currentPropertyProgram.liveUserPropertyConsumerTargetsByKey[
                    "ui_editor_properties_mode"
                ] == [currentPropertyTarget]
                && currentPropertyProgram.livePropertyInputTargets
                    == [currentPropertyTarget] },
            "invalidCurrentPropertyFailure": {
                invalidCurrentProperty.failures[currentPropertyTarget]?.code
                    ?? "" },
            "invalidCurrentPropertyPublished": {
                invalidCurrentProperty.values[currentPropertyTarget] != nil },
            "invalidCurrentPropertyConsumerDisabled": {
                invalidCurrentPropertyProgram.activeLivePropertyInputTargets
                    .isEmpty },
            "passAudioBindings": { passAudioProgram.bindings.count },
            "passAudioDemand": { passAudioProgram.hasAudioConsumers },
            "passAudioValue": { scalar(passAudioResult.values[passAudioTarget]) },
            "passAudioFailures": { passAudioResult.failures.count },
            "passAudioWrongWrapperRejected": { rejectedPassAudioWrapper.bindings.isEmpty },
            "passAudioUserProviderRejected": { rejectedPassAudioProvider.bindings.isEmpty },
            "dynamicScalarBindings": { dynamicScalarProgram.bindings.count },
            "dynamicScalarFirst": { scalar(
                dynamicScalarFirst.values[dynamicScalarTarget]
            ) },
            "dynamicScalarStable": { scalar(
                dynamicScalarStable.values[dynamicScalarTarget]
            ) },
            "dynamicScalarChanged": { scalar(
                dynamicScalarChanged.values[dynamicScalarTarget]
            ) },
            "dynamicScalarWrongTypeFailure": {
                dynamicScalarWrongType.failures[dynamicScalarTarget]?.code ?? "" },
            "dynamicScalarWrongTypePublished": {
                dynamicScalarWrongType.values[dynamicScalarTarget] != nil },
            "dynamicScalarRecovered": { scalar(
                dynamicScalarRecovered.values[dynamicScalarTarget]
            ) },
            "dynamicScalarFallback": { scalar(
                dynamicScalarFallback.values[dynamicScalarTarget]
            ) },
            "dynamicScalarMalformedRejected": {
                malformedDynamicScalar.bindings.isEmpty },
            "dynamicScalarLiveTarget": {
                dynamicScalarProgram.livePropertyInputTargets
                    == [dynamicScalarLiveTarget, dynamicScalarTarget] },
            "dynamicVectorLiveTarget": {
                dynamicVectorProgram.livePropertyInputTargets
                    == [dynamicVectorLiveTarget] },
            "nullOuterUserScalarAdmitted": { nullOuterUserScalarAdmitted },
            "failingDynamicScalarInitiallyActive": {
                failingDynamicScalarInitiallyActive },
            "failingDynamicScalarBecameUnavailable": {
                failingDynamicScalarBecameUnavailable },
            "failingDynamicVectorInitiallyActive": {
                failingDynamicVectorInitiallyActive },
            "failingDynamicVectorBecameUnavailable": {
                failingDynamicVectorBecameUnavailable },
            "disabledScalarLiveUpdateRejected": { disabledScalarLiveUpdateRejected },
            "disabledScalarLiveUpdateWasAtomic": { disabledScalarLiveUpdateWasAtomic },
            "disabledVectorLiveUpdateRejected": { disabledVectorLiveUpdateRejected },
            "disabledVectorLiveUpdateWasAtomic": { disabledVectorLiveUpdateWasAtomic },
            "activeVectorSiblingAccepted": { activeVectorSiblingAccepted },
            "audioScaleBindings": { audioScaleProgram.bindings.count },
            "audioScaleDemand": { audioScaleProgram.hasAudioConsumers },
            "audioScaleValue": { vector(audioScaleResult.values[
                .layer(layerID: 10, field: .scale)
            ]) },
            "audioScaleFailures": { audioScaleResult.failures.count },
            "propertyEventFirst": { vector(
                propertyEventFirst.values[propertyEventTarget]
            ) },
            "propertyEventStable": { vector(
                propertyEventStable.values[propertyEventTarget]
            ) },
            "propertyEventChanged": { vector(
                propertyEventChanged.values[propertyEventTarget]
            ) },
            "propertyEventFailures": { propertyEventFirst.failures.count
                + propertyEventStable.failures.count
                + propertyEventChanged.failures.count },
            "propertyRevisionFirstDelta": { propertyStateFirst != nil },
            "propertyRevisionStableSkipped": { propertyStateStable == nil },
            "propertyRevisionChangedDelta": { propertyStateChanged != nil },
        ]
        return (observations, audioSnapshot)
    }
}
