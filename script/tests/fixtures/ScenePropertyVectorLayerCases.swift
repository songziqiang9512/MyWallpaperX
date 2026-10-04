import Foundation

extension Harness {
    static func layerCases(_ fixture: PropertyVectorFixture) -> PropertyVectorObservations {
        let descriptor = fixture.descriptor
        let domain = fixture.domain
        let frame = fixture.frame
        let layerProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin", source: layerSource, value: "20 2250 0",
                properties: [:]
            )],
            userPropertyDefinitions: [],
            generation: 10
        )
        let layerTarget = SceneDynamicTarget.layer(layerID: 42, field: .origin)
        let layerSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [.init(
                target: layerTarget,
                valueType: .vector3,
                authoredValue: .vector3(10, 20, 30)
            )],
            timelineValues: [layerTarget: .vector3(4, 5, 6)]
        ).snapshot
        try! domain.publishLayerSnapshot(layerSnapshot, descriptor: descriptor)
        let layerResult = layerProgram.evaluate(
            inputs: [.layer(layerID: 10, field: .origin): .vector3(20, 2250, 0)],
            effectivePropertyValues: [:],
            frame: frame
        )
        let colorTarget = SceneDynamicTarget.layer(
            layerID: 500, field: .color
        )
        let colorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [colorBinding(source: layerColorSource)],
            userPropertyDefinitions: [],
            admittedLayerColorConsumerIDs: [500],
            generation: 101
        )
        let colorResult = colorProgram.evaluate(
            inputs: [colorTarget: .vector3(0.2, 0.3, 0.4)],
            effectivePropertyValues: [:], frame: frame,
            mediaThumbnailEvent: .init(
                hasThumbnail: true,
                primaryColor: .init(0.7, 0.5, 0.25),
                generation: 1
            )
        )
        let spotColorTarget = SceneDynamicTarget.layer(
            layerID: 502, field: .color
        )
        let spotColorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [colorBinding(
                source: spotColorSource,
                value: "1 1 1",
                objectIndex: 6,
                objectID: 502,
                properties: [
                    "useColor2": .object([
                        "user": .object([
                            "condition": .string("2"),
                            "name": .string("colour"),
                        ]),
                        "value": .bool(false),
                    ]),
                ]
            )],
            userPropertyDefinitions: [],
            admittedLayerColorConsumerIDs: [502],
            generation: 106
        )
        let spotColorResult = spotColorProgram.evaluate(
            inputs: [spotColorTarget: .vector3(1, 1, 1)],
            effectivePropertyValues: ["colour": .number(2)], frame: frame
        )
        let currentColorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [colorBinding(source: thisLayerColorSource)],
            userPropertyDefinitions: [],
            admittedLayerColorConsumerIDs: [500],
            generation: 102
        )
        let currentColorSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: currentColorProgram.definitions,
            sceneScriptValues: [colorTarget: .vector3(0.6, 0.4, 0.2)]
        ).snapshot
        try! domain.publishLayerSnapshot(
            currentColorSnapshot, descriptor: descriptor
        )
        let currentColorResult = currentColorProgram.evaluate(
            inputs: [colorTarget: .vector3(0.6, 0.4, 0.2)],
            effectivePropertyValues: [:], frame: frame
        )
        let undefinedColorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [colorBinding(source: undefinedColorSource)],
            userPropertyDefinitions: [],
            admittedLayerColorConsumerIDs: [500],
            generation: 103
        )
        let undefinedColorResult = undefinedColorProgram.evaluate(
            inputs: [colorTarget: .vector3(0.2, 0.3, 0.4)],
            effectivePropertyValues: [:], frame: frame
        )
        let failingColorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [colorBinding(source: failingColorSource)],
            userPropertyDefinitions: [],
            admittedLayerColorConsumerIDs: [500],
            generation: 104
        )
        let failingColorFirst = failingColorProgram.evaluate(
            inputs: [colorTarget: .vector3(0.2, 0.3, 0.4)],
            effectivePropertyValues: [:], frame: frame
        )
        let failingColorSecond = failingColorProgram.evaluate(
            inputs: [colorTarget: .vector3(0.2, 0.3, 0.4)],
            effectivePropertyValues: [:], frame: frame
        )
        let failingColorThird = failingColorProgram.evaluate(
            inputs: [colorTarget: .vector3(0.2, 0.3, 0.4)],
            effectivePropertyValues: [:], frame: frame
        )
        let failingColorFallback = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 3,
            generation: 2,
            definitions: failingColorProgram.definitions,
            sceneScriptValues: failingColorSecond.values
        ).snapshot
        let colorFailurePeer = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [
                binding(
                    key: "origin", source: layerSource,
                    value: "20 2250 0", properties: [:]
                ),
                colorBinding(
                    source: "export function update(value) { return {}; }"
                ),
            ],
            userPropertyDefinitions: [],
            admittedLayerColorConsumerIDs: [500],
            generation: 105
        )
        let colorFailurePeerResult = colorFailurePeer.evaluate(
            inputs: [
                .layer(layerID: 10, field: .origin): .vector3(20, 2250, 0),
                colorTarget: .vector3(0.2, 0.3, 0.4),
            ],
            effectivePropertyValues: [:], frame: frame
        )
        let textColorTarget = SceneDynamicTarget.text(
            layerID: 501, field: .color
        )
        let textColorProgram = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [colorBinding(
                source: scriptPropertyColorSource,
                value: "0 0 0", objectIndex: 5, objectID: 501,
                properties: [
                    "dynamicTitle": .bool(false),
                    "titleColor": .string("0.25 0.5 0.75"),
                ]
            )],
            userPropertyDefinitions: [],
            admittedLayerColorConsumerIDs: [501],
            generation: 106
        )
        let textColorResult = textColorProgram.evaluate(
            inputs: [textColorTarget: .vector3(0, 0, 0)],
            effectivePropertyValues: [:], frame: frame
        )
        let bad = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin",
                source: "export function update(value) { return {}; }",
                value: "20 2250 0",
                properties: [:]
            )],
            userPropertyDefinitions: [],
            generation: 8
        )
        let badResult = bad.evaluate(
            inputs: [.layer(layerID: 10, field: .origin): .vector3(20, 2250, 0)],
            effectivePropertyValues: [:],
            frame: frame
        )
        let duplicate = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "origin", source: originSource, value: "20 2250 0", properties: [
                    "x": .number(20), "y": .number(2250),
                ]),
                binding(key: "origin", source: originSource, value: "20 2250 0", properties: [
                    "x": .number(20), "y": .number(2250),
                ]),
            ],
            userPropertyDefinitions: [],
            generation: 9
        )
        let wrongOwner = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin", source: originSource, value: "20 2250 0",
                properties: ["x": .number(20)], ownerKind: .pass
            )],
            userPropertyDefinitions: [],
            generation: 11
        )
        let animatedOriginTarget = SceneDynamicTarget.layer(
            layerID: 10, field: .origin
        )
        let animatedOrigin = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin", source: animationSource, value: "20 2250 0",
                properties: [:],
                wrapperKeys: ["animation", "script", "value"]
            )],
            userPropertyDefinitions: [],
            timelineTargets: [animatedOriginTarget],
            generation: 12
        )
        let animatedOriginResult = animatedOrigin.evaluate(
            inputs: [animatedOriginTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: [:],
            frame: frame
        )
        let rejectedWithoutTimeline = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin", source: animationSource, value: "20 2250 0",
                properties: [:],
                wrapperKeys: ["animation", "script", "value"]
            )],
            userPropertyDefinitions: [],
            generation: 13
        )
        let animatedAlphaTarget = SceneDynamicTarget.layer(
            layerID: 10, field: .alpha
        )
        let animatedAlpha = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [alphaBinding(source: animationSource, value: 0.75)],
            timelineTargets: [animatedAlphaTarget],
            generation: 14
        )
        let animatedAlphaResult = animatedAlpha.evaluate(
            inputs: [animatedAlphaTarget: .scalar(0.75)],
            frame: frame
        )
        let genericAlpha = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [alphaBinding(
                source: "export function update(value) { return value + engine.frametime; }",
                value: 0.75,
                wrapperKeys: ["script", "value"]
            )],
            generation: 141
        )
        let genericAlphaResult = genericAlpha.evaluate(
            inputs: [animatedAlphaTarget: .scalar(0.75)],
            frame: frame
        )
        let genericPropertyAlpha = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [alphaBinding(
                source: """
                export var scriptProperties = createScriptProperties()
                export function update(value) {
                    return value + scriptProperties.step;
                }
                """,
                value: 0.75,
                properties: ["step": .number(0.25)],
                wrapperKeys: ["script", "scriptproperties", "value"]
            )],
            generation: 142
        )
        let genericPropertyAlphaResult = genericPropertyAlpha.evaluate(
            inputs: [animatedAlphaTarget: .scalar(0.75)],
            frame: frame
        )
        // Admit-bucket republish probe: the second frame feeds the first
        // frame's published scalar back as the current value, so a strictly
        // larger result can only come from re-running the update against the
        // supplied clock, not from a cached publication.
        let alphaTimeOwnerNextFrame = genericAlpha.evaluate(
            inputs: [animatedAlphaTarget: .scalar(
                scalar(genericAlphaResult.values[animatedAlphaTarget])
            )],
            frame: frame
        )
        let rejectedAlphaWrapper = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [alphaBinding(
                source: "export function update(value) { return value; }",
                value: 0.75,
                wrapperKeys: ["extra", "script", "value"]
            )],
            generation: 143
        )
        defer { fixture.retained += [layerProgram, colorProgram, spotColorProgram, currentColorProgram, undefinedColorProgram, failingColorProgram, colorFailurePeer, textColorProgram, bad, duplicate, wrongOwner, animatedOrigin, rejectedWithoutTimeline, animatedAlpha, genericAlpha, genericPropertyAlpha, rejectedAlphaWrapper] }
        return [
            "layerOrigin": { vector(
                layerResult.values[.layer(layerID: 10, field: .origin)]
            ) },
            "layerFailures": { layerResult.failures.count },
            "layerColorBindings": { colorProgram.bindings.count },
            "layerColorMediaTargets": { colorProgram.mediaThumbnailTargets
                == [colorTarget] },
            "layerColorValue": { vector(colorResult.values[colorTarget]) },
            "layerColorFailures": { colorResult.failures.count },
            "spotColorBindings": { spotColorProgram.bindings.count },
            "spotColorValue": { vector(spotColorResult.values[spotColorTarget]) },
            "spotColorFailures": { spotColorResult.failures.count },
            "layerColorCurrent": { vector(currentColorResult.values[colorTarget]) },
            "layerColorUndefined": { vector(
                undefinedColorResult.values[colorTarget]
            ) },
            "layerColorUndefinedFailures": { undefinedColorResult.failures.count },
            "layerColorFirst": { vector(failingColorFirst.values[colorTarget]) },
            "layerColorSecondFailure": {
                failingColorSecond.failures[colorTarget]?.code ?? "" },
            "layerColorSecondPublished": {
                failingColorSecond.values[colorTarget] != nil },
            "layerColorThirdFailures": { failingColorThird.failures.count },
            "layerColorThirdPublished": {
                failingColorThird.values[colorTarget] != nil },
            "layerColorFallback": { vector(
                failingColorFallback[colorTarget]?.value
            ) },
            "layerColorFallbackSource": {
                failingColorFallback[colorTarget]?.source.rawValue ?? "" },
            "layerColorFailurePeer": { vector(
                colorFailurePeerResult.values[
                    .layer(layerID: 10, field: .origin)
                ]
            ) },
            "layerColorFailurePeerFailures": {
                colorFailurePeerResult.failures.count },
            "textColorBindings": { textColorProgram.bindings.count },
            "textColorValue": { vector(textColorResult.values[textColorTarget]) },
            "textColorFailures": { textColorResult.failures.count },
            "badReturn": { badResult.failures.values.first?.code ?? "" },
            "badPublished": { !badResult.values.isEmpty },
            "duplicateRejected": { duplicate.bindings.isEmpty },
            "wrongOwnerRejected": { wrongOwner.bindings.isEmpty },
            "animationBindings": { animatedOrigin.bindings.count },
            "animationCommands": { animatedOriginResult.animationMutations.map {
                $0.command.rawValue
            } },
            "animationWithoutTimelineRejected": { rejectedWithoutTimeline.bindings.isEmpty },
            "alphaAnimationBindings": { animatedAlpha.bindings.count },
            "alphaAnimationValue": { scalar(
                animatedAlphaResult.values[animatedAlphaTarget]
            ) },
            "alphaAnimationCommands": { animatedAlphaResult.animationMutations.map {
                $0.command.rawValue
            } },
            "genericAlphaBindings": { genericAlpha.bindings.count },
            "genericAlphaValue": { scalar(genericAlphaResult.values[animatedAlphaTarget]) },
            "genericPropertyAlphaBindings": { genericPropertyAlpha.bindings.count },
            "genericPropertyAlphaValue": { scalar(
                genericPropertyAlphaResult.values[animatedAlphaTarget]
            ) },
            "alphaTimeOwnerNextFrame": { scalar(
                alphaTimeOwnerNextFrame.values[animatedAlphaTarget]
            ) },
            "genericAlphaWrongWrapperRejected": { rejectedAlphaWrapper.bindings.isEmpty },
        ]
    }
}

import Foundation

extension Harness {
    static func modelCases(_ fixture: PropertyVectorFixture) throws -> PropertyVectorObservations {
        let descriptor = fixture.descriptor
        let domain = fixture.domain
        let program = fixture.program
        let frame = fixture.frame
        let angleTarget = fixture.angleTarget
        var modelDescriptor = SceneRenderDescriptor(layers: [
            .init(
                id: 600, layerIndex: 0, name: "Unseen model",
                visible: true, originXYZ: [0, 0, 0],
                scaleXYZ: [1, 1, 1], scaleHasScript: false,
                alpha: 1, effects: [], contentKind: "model",
                staticModelPath: "models/unseen.mdl"
            ),
        ])
        modelDescriptor.modelMaterialLinks = [.init(
            modelPath: "models/unseen.mdl",
            materialPath: "materials/unseen.json"
        )]
        modelDescriptor.materialPasses = [.init(
            materialPath: "materials/unseen.json",
            passIndex: 0,
            constantShaderValues: [
                "tintback": .init(
                    scriptSource: modelTintSource,
                    components: [1, 1, 1],
                    bindingKeys: ["script", "scriptproperties", "value"],
                    scriptProperties: [
                        "useBlue": .object([
                            "user": .object([
                                "condition": .string("2"),
                                "name": .string("colour"),
                            ]),
                            "value": .bool(false),
                        ]),
                    ]
                ),
            ]
        )]
        let modelTintTarget = SceneDynamicTarget.layer(
            layerID: 600, field: .color
        )
        let modelTintProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: modelDescriptor,
            scriptBindings: [],
            userPropertyDefinitions: [],
            admittedLayerColorConsumerIDs: [600],
            generation: 33
        )
        let modelTintResult = modelTintProgram.evaluate(
            inputs: [modelTintTarget: .vector3(1, 1, 1)],
            effectivePropertyValues: ["colour": .number(2)],
            frame: frame
        )
        defer { fixture.retained += [modelTintProgram] }
        return [
            "modelTintBindings": { modelTintProgram.bindings.count },
            "modelTintValue": { vector(modelTintResult.values[modelTintTarget]) },
            "modelTintFailures": { modelTintResult.failures.count },
        ]
    }
}
