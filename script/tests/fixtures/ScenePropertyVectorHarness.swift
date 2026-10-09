import Foundation
import simd

/// Keeps the original shared domain and prepared owners alive through all cases.
typealias PropertyVectorObservations = [String: () -> Any]

final class PropertyVectorFixture {
    let descriptor: SceneRenderDescriptor
    let domain: SceneScriptQuickJSDomain
    let program: SceneScriptVectorProgram
    let frame: SceneScriptFrameInput
    let angleTarget: SceneDynamicTarget
    var retained: [Any] = []

    init(descriptor: SceneRenderDescriptor, domain: SceneScriptQuickJSDomain,
         program: SceneScriptVectorProgram, frame: SceneScriptFrameInput, angleTarget: SceneDynamicTarget) {
        self.descriptor = descriptor; self.domain = domain; self.program = program
        self.frame = frame; self.angleTarget = angleTarget
    }
}

@main enum Harness {
    static func makeFixture() throws -> PropertyVectorFixture {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(
                id: 10, layerIndex: 0, name: "anchor", visible: true,
                originXYZ: [20, 2250, 0], scaleXYZ: [1.5, 1.5, 1.5],
                anglesXYZ: [0, 0, Float.pi / 2],
                scaleHasScript: true, alpha: 0.75,
                effects: [.init(
                    name: "history", effectID: 100,
                    passes: [.init(
                        passIndex: 0, id: 200,
                        constantShaderValues: [
                            "alpha": .init(
                                scriptSource: mediaPlaybackSource,
                                components: [1]
                            ),
                            "scale": .init(
                                scriptSource: passVectorSource,
                                components: [1, 1],
                                userValueKind: .null
                            ),
                            "scaleUser": .init(
                                scriptSource: passVectorSource,
                                components: [1, 1],
                                userValueKind: .string
                            ),
                            "userColor": .init(
                                scriptSource: passVectorSource,
                                components: [0.123456789, 0.25, 0.5],
                                userValueKind: .string,
                                userBinding: "palette",
                                bindingKeys: ["script", "scriptproperties", "user", "value"]
                            ),
                            "color": .init(
                                scriptSource: passColorSource,
                                components: [1, 1, 1]
                            ),
                            "audioScalar": .init(
                                scriptSource: passAudioScalarSource,
                                components: [1]
                            ),
                            "audioScalarUser": .init(
                                scriptSource: passAudioScalarSource,
                                components: [1],
                                userValueKind: .string
                            ),
                            "dynamicScalar": .init(
                                scriptSource: dynamicScalarSource,
                                components: [-0.2]
                            ),
                            "dynamicScalarNull": .init(
                                scriptSource: dynamicScalarSource,
                                components: [-0.2],
                                userValueKind: .null
                            ),
                            "colormode": .init(
                                scriptSource: currentPropertyEventSource,
                                components: [0]
                            ),
                            "unseenTimelineScalar": .init(
                                scriptSource: mediaAnimationSource,
                                components: [1]
                            ),
                        ]
                    )]
                )]
            ),
            .init(
                id: 42, layerIndex: 1, name: "C1", visible: true,
                originXYZ: [10, 20, 30], scaleXYZ: [1, 1, 1],
                scaleHasScript: false, alpha: nil, effects: []
            ),
            .init(
                id: 77, layerIndex: 2, name: "Song Title", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                scaleHasScript: false, alpha: nil, effects: [],
                contentKind: "text",
                textScript: .init(source: mediaPropertiesSource),
                text: "Placeholder"
            ),
            .init(
                id: 139, layerIndex: 3, name: "Audio particles", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                scaleHasScript: false, alpha: nil, effects: [],
                contentKind: "particle",
                particleInstanceOverride: .init(
                    id: nil, alpha: nil,
                    size: .init(
                        value: .scalar(1), userPropertyKey: nil,
                        hasScript: true, hasAnimation: false
                    ),
                    lifetime: nil,
                    rate: .init(
                        value: .scalar(2), userPropertyKey: nil,
                        hasScript: true, hasAnimation: false
                    ),
                    speed: nil, count: nil, brightness: nil, color: nil,
                    normalizedColor: nil, controlPoints: [:],
                    controlPointAngles: [:]
                )
            ),
            .init(
                id: 500, layerIndex: 4, name: "Direct color", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                colorRGB: [0.2, 0.3, 0.4],
                scaleHasScript: false, alpha: 1, effects: []
            ),
            .init(
                id: 501, layerIndex: 5, name: "Effectful text color",
                visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                colorRGB: [0, 0, 0],
                scaleHasScript: false, alpha: 1,
                effects: [.init(name: "renamed blur")],
                contentKind: "text", text: "renamed text",
                textStyle: .init(
                    fontPath: nil, colorRGB: [0, 0, 0], pointSize: 32
                )
            ),
            .init(
                id: 502, layerIndex: 6, name: "Authored spot color",
                visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                colorRGB: [1, 1, 1], spotLight: true,
                scaleHasScript: false, alpha: 1, effects: [],
                contentKind: "spotLight"
            ),
        ])
        let domain = try SceneScriptQuickJSDomain()
        let program = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "origin", source: originSource, value: "20 2250 0", properties: [
                    "x": .object(["user": .string("x1"), "value": .number(20)]),
                    "y": .object(["user": .string("y1"), "value": .number(2250)]),
                ]),
                binding(key: "scale", source: scaleSource, value: "1.5 1.5 1.5", properties: [
                    "size": .object(["user": .string("size"), "value": .number(1.5)]),
                ]),
                binding(
                    key: "angles", source: angleSource,
                    value: "0 0 1.5707963", properties: [:]
                ),
            ],
            userPropertyDefinitions: [],
            generation: 7
        )
        let frame = SceneScriptFrameInput(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1.0 / 60.0,
            sceneTime: 2
        ), timeZone: TimeZone(secondsFromGMT: 0)!)
        let angleTarget = SceneDynamicTarget.layer(
            layerID: 10, field: .angles
        )
        return .init(descriptor: descriptor, domain: domain, program: program,
            frame: frame, angleTarget: angleTarget)
    }

    static func main() throws {
        let fixture = try makeFixture()
        defer { withExtendedLifetime(fixture) {} }
        var observations = vectorCases(fixture)
        observations.merge(passCases(fixture)) { _, _ in preconditionFailure("duplicate fixture result") }
        let property = propertyCases(fixture)
        observations.merge(property.observations) { _, _ in preconditionFailure("duplicate fixture result") }
        observations.merge(particleCases(fixture, audioSnapshot: property.audioSnapshot)) { _, _ in preconditionFailure("duplicate fixture result") }
        observations.merge(layerCases(fixture)) { _, _ in preconditionFailure("duplicate fixture result") }
        observations.merge(try mediaCases(fixture)) { _, _ in preconditionFailure("duplicate fixture result") }
        observations.merge(try modelCases(fixture)) { _, _ in preconditionFailure("duplicate fixture result") }
        observations.merge(materialCases(fixture)) { _, _ in preconditionFailure("duplicate fixture result") }
        let descriptor = fixture.descriptor
        observations.merge([
            "textWrapperAdmission": { Dictionary(uniqueKeysWithValues: [
                ["script", "value"],
                ["script", "scriptproperties", "value"],
                ["script", "user", "value"],
                ["script", "scriptproperties", "user", "value"],
                ["animation", "script", "value"],
                ["script", "scriptproperties"],
            ].map { keys in
                (
                    keys.joined(separator: "+"),
                    SceneScriptStringProgram.projectedTargets(
                        descriptor: descriptor,
                        scriptBindings: [
                            textBinding(
                                source: mediaPropertiesSource,
                                value: "Placeholder",
                                wrapperKeys: keys
                            )
                        ]
                    ).contains(.text(layerID: 77, field: .content))
                )
            }) },
        ]) { _, _ in preconditionFailure("duplicate fixture result") }
        let orderedKeys = ["bindings", "origin", "scale", "targetFilteredValueCount", "targetFilteredOriginPublished", "angleValue", "angleFailure", "failures", "mutations", "passVectorBindings", "passVectorValue", "passVectorFailures", "passVectorWrongWrapperRejected", "passVectorUserProviderRejected", "userColorExactInput", "userColorForeignInput", "userColorScalarInput", "userColorInputKey", "userColorMismatchedKeyCount", "userColorMissingKeyCount", "userColorIRCount", "userColorOwnerCount", "userColorInputCount", "userColorFirst", "userColorChanged", "userColorInvalidUnpublished", "passColorBindings", "passColorValue", "passColorFailures", "currentPropertyFirst", "currentPropertyStableSkipped", "currentPropertyChanged", "currentPropertyTimer", "currentPropertySettledSkipped", "currentPropertyLiveConsumer", "invalidCurrentPropertyFailure", "invalidCurrentPropertyPublished", "invalidCurrentPropertyConsumerDisabled", "partitionedMediaTargetExcluded", "partitionedGenericPeerPreserved", "partitionedGenericPeerValue", "partitionedMediaTargetNotPublished", "partitionedGenericPeerSucceeded", "passAudioBindings", "passAudioDemand", "passAudioValue", "passAudioFailures", "passAudioWrongWrapperRejected", "passAudioUserProviderRejected", "dynamicScalarBindings", "dynamicScalarFirst", "dynamicScalarStable", "dynamicScalarChanged", "dynamicScalarWrongTypeFailure", "dynamicScalarWrongTypePublished", "dynamicScalarRecovered", "dynamicScalarFallback", "dynamicScalarMalformedRejected", "dynamicScalarLiveTarget", "dynamicVectorLiveTarget", "nullOuterUserScalarAdmitted", "failingDynamicScalarInitiallyActive", "failingDynamicScalarBecameUnavailable", "failingDynamicVectorInitiallyActive", "failingDynamicVectorBecameUnavailable", "disabledScalarLiveUpdateRejected", "disabledScalarLiveUpdateWasAtomic", "disabledVectorLiveUpdateRejected", "disabledVectorLiveUpdateWasAtomic", "activeVectorSiblingAccepted", "layerOrigin", "layerFailures", "layerColorBindings", "layerColorMediaTargets", "layerColorValue", "layerColorFailures", "spotColorBindings", "spotColorValue", "spotColorFailures", "layerColorCurrent", "layerColorUndefined", "layerColorUndefinedFailures", "layerColorFirst", "layerColorSecondFailure", "layerColorSecondPublished", "layerColorThirdFailures", "layerColorThirdPublished", "layerColorFallback", "layerColorFallbackSource", "layerColorFailurePeer", "layerColorFailurePeerFailures", "textColorBindings", "textColorValue", "textColorFailures", "badReturn", "badPublished", "duplicateRejected", "wrongOwnerRejected", "animationBindings", "animationCommands", "animationWithoutTimelineRejected", "alphaAnimationBindings", "alphaAnimationValue", "alphaAnimationCommands", "genericAlphaBindings", "genericAlphaValue", "genericPropertyAlphaBindings", "genericPropertyAlphaValue", "alphaTimeOwnerNextFrame", "genericAlphaWrongWrapperRejected", "mediaAnimationCommands", "mediaGenerationDeduplicated", "passTimelineBindings", "passTimelineKeepsTimelineValueOwner", "passTimelineCommands", "passTimelineGenerationDeduplicated", "passTimelineWithoutTargetRejected", "passTimelineWrongWrapperRejected", "passTimelinePropertiesRejected", "playbackBindings", "playbackPlaying", "playbackNextFrame", "playbackStopped", "playbackFailures", "stringBindings", "stringValue", "stringFailures", "stringGenerationDeduplicated", "orderedMediaTrace", "orderedMediaDuplicateTrace", "orderedMediaFailures", "orderedLayerMutationOrder", "orderedLayerMutationFields", "orderedDuplicateLayerMutations", "orderedNextGenerationTrace", "orderedNextGenerationVector", "orderedNextGenerationScalar", "orderedNextGenerationLayerMutations", "orderedInvalidatedValues", "orderedInvalidatedFailures", "orderedInvalidatedLayerMutations", "audioScaleBindings", "audioScaleDemand", "audioScaleValue", "audioScaleFailures", "particleScalarBadValues", "particleScalarBadFailures", "particleScalarBadSizeAbsent", "particleScalarRecovered", "particleColor", "particleColorRecovered", "particleColorBadRejected", "particleColorCursorOwners", "particleColorMarkerCleared", "particleColorNegativeAdmission", "particleScalarMarkersCleared", "particleScalarHiddenPreserved", "particleScalarPartialExact", "particleScalarDuplicateCount", "particleScalarConflictCount", "particleScalarParsed", "particleScalarBindings", "particleScalarValues", "particleScalarFailures", "particleAudioBindings", "particleAudioDemand", "particleAudioValue", "particleAudioFailures", "particlePropertyFreeBindings", "particleNullUserBindings", "particleNullUserParseFailures", "particleConflictingUserRejected", "particleUnknownWrapperRejected", "particleAdmittedVisible", "particleAdmittedRateScriptRemoved", "particleAdmittedSiblingPreserved", "particleStaticFallbackVisible", "particleStaticRatePreserved", "particleStaticSiblingPreserved", "propertyEventFirst", "propertyEventStable", "propertyEventChanged", "propertyEventFailures", "propertyRevisionFirstDelta", "propertyRevisionStableSkipped", "propertyRevisionChangedDelta", "modelTintBindings", "modelTintValue", "modelTintFailures", "textWrapperAdmission"]
        let payloadKeys = orderedKeys + [
            "angleSnapshotValue", "angleSnapshotSource", "angleWorldDirection", "materialMixed",
            "passTimelineAfterRejection", "passTimelineThrowUnpublished",
        ]
        precondition(observations.count == payloadKeys.count)
        let payload = Dictionary(uniqueKeysWithValues: payloadKeys.map { ($0, observations[$0]!()) })
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}

import Foundation

extension Harness {
    static func vectorCases(_ fixture: PropertyVectorFixture) -> PropertyVectorObservations {
        let descriptor = fixture.descriptor
        let program = fixture.program
        let frame = fixture.frame
        let angleTarget = fixture.angleTarget
        let result = program.evaluate(
            inputs: [
                .layer(layerID: 10, field: .origin): .vector3(20, 2250, 0),
                .layer(layerID: 10, field: .scale): .vector3(1.5, 1.5, 1.5),
                angleTarget: .vector3(0, 0, Double(Float.pi / 2)),
            ].filter {
                program.inputTargets.contains($0.key)
                    && program.inputValueTypes.contains($0.value.valueType)
            },
            effectivePropertyValues: [
                "x1": .number(40), "y1": .number(2100), "size": .number(1.25),
            ],
            frame: frame
        )
        let angleSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1, generation: 1, definitions: program.definitions,
            sceneScriptValues: result.values
        ).snapshot
        let layerIndex = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let staticWorld = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: layerIndex)
        let angleWorld = SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: descriptor, byID: layerIndex,
            snapshot: angleSnapshot, staticFrames: staticWorld)[10]!
        let worldDirection = simd_normalize(-SIMD3(angleWorld.columns.0.x,
            angleWorld.columns.0.y, angleWorld.columns.0.z))
        let targetFilteredResult = program.evaluate(
            inputs: [
                .layer(layerID: 10, field: .origin): .vector3(20, 2250, 0),
                .layer(layerID: 10, field: .scale): .vector3(1.5, 1.5, 1.5),
            ],
            effectivePropertyValues: ["x1": .number(40), "y1": .number(2100), "size": .number(1.25)],
            frame: frame,
            targetFilter: .layer(layerID: 10, field: .scale)
        )
        return [
            "bindings": { program.bindings.count },
            "origin": { vector(result.values[.layer(layerID: 10, field: .origin)]) },
            "scale": { vector(result.values[.layer(layerID: 10, field: .scale)]) },
            "targetFilteredValueCount": { targetFilteredResult.values.count },
            "targetFilteredOriginPublished": { targetFilteredResult.values[
                .layer(layerID: 10, field: .origin)
            ] != nil },
            "angleValue": { vector(result.values[angleTarget]) },
            "angleFailure": { result.failures[angleTarget]?.code ?? "" },
            "angleSnapshotValue": { vector(angleSnapshot[angleTarget]?.value) },
            "angleSnapshotSource": { angleSnapshot[angleTarget]?.source.rawValue ?? "" },
            "angleWorldDirection": { [worldDirection.x, worldDirection.y, worldDirection.z] },
            "failures": { result.failures.count },
            "mutations": { result.materialFunctionMutations.map {
                ["layerID": $0.layerID, "effectIndex": $0.effectIndex,
                 "name": $0.functionName] as [String: Any]
            } },
        ]
    }
}
