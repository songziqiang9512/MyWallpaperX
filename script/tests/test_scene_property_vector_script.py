#!/usr/bin/env python3

"""Generic QuickJS Vec3 owner and previous-current boundary."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
VM = SCENE / "Runtime/SceneScript"
QUICKJS = VM / "QuickJSNG"
SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Format/SceneScriptBindingDefinition.swift",
    SCENE / "Properties/SceneDynamicSnapshot.swift",
    SCENE / "Properties/SceneUserProperty.swift",
    SCENE / "Runtime/SceneAudioSpectrum.swift",
    VM / "SceneScriptScalarRuntime.swift",
    VM / "SceneScriptOwnerLifecycleBridge.swift",
    VM / "SceneScriptAnimationHandleBridge.swift",
    VM / "SceneScriptAudioHost.swift",
    VM / "SceneScriptEffectHandleBridge.swift",
    VM / "SceneScriptLayerHandleBridge.swift",
    VM / "SceneScriptLayerRuntimeDescriptorBridge.swift",
    VM / "SceneScriptMediaEventBridge.swift",
    VM / "SceneScriptScalarProgram.swift",
    VM / "SceneScriptStringProgram.swift",
    VM / "SceneScriptStringRuntime.swift",
    VM / "SceneScriptVectorProgram.swift",
    VM / "SceneScriptVectorRuntime.swift",
]

HARNESS = r'''
import Foundation

struct SceneFrameTiming {
    let wallDate: Date
    let simulationFrameTime: TimeInterval
    let sceneTime: TimeInterval
}

final class SceneMediaThumbnailInbox {
    struct Snapshot {
        struct Properties {
            let title: String
            let artist: String
        }
        let current: Data?
        let generation: UInt64
        let playbackState: Int?
        let playbackGeneration: UInt64
        let properties: Properties?
        let propertiesGeneration: UInt64
    }
}

struct SceneTextScriptDefinition {
    let source: String
}

struct SceneScriptMaterialFunctionMutation: Equatable, Sendable {
    let layerID: Int
    let effectIndex: Int
    let functionName: String
}

enum SceneTimelinePlaybackCommand: String, Equatable, Sendable {
    case play
    case pause
    case stop
}

struct SceneTimelinePlaybackMutation: Equatable, Sendable {
    let target: SceneDynamicTarget
    let command: SceneTimelinePlaybackCommand
}

enum SceneParticleNumericValue: Equatable, Sendable {
    case scalar(Double)
    case vector([Double])
    var scalarValue: Double? {
        guard case let .scalar(value) = self else { return nil }
        return value
    }
}

struct SceneParticleBoundValue: Equatable, Sendable {
    let value: SceneParticleNumericValue?
    let userPropertyKey: String?
    let hasScript: Bool
    let hasAnimation: Bool
}

struct SceneParticleInstanceOverride: Equatable, Sendable {
    let alpha: SceneParticleBoundValue?
    let size: SceneParticleBoundValue?
    let lifetime: SceneParticleBoundValue?
    let rate: SceneParticleBoundValue?
    let speed: SceneParticleBoundValue?
    let count: SceneParticleBoundValue?
    let brightness: SceneParticleBoundValue?
    let color: SceneParticleBoundValue?
    let normalizedColor: SceneParticleBoundValue?
    let controlPoints: [Int: SceneParticleBoundValue]
    let controlPointAngles: [Int: SceneParticleBoundValue]
}

struct SceneRenderDescriptor {
    enum SceneShaderUserValueKind { case null, string }
    struct TextStyle {
        let fontPath: String?
        let colorRGB: [Float]?
        let pointSize: Float?
    }
    struct ShaderValue {
        let scriptSource: String?
        let components: [Double]?
        let userValueKind: SceneShaderUserValueKind?

        init(
            scriptSource: String?, components: [Double]?,
            userValueKind: SceneShaderUserValueKind? = nil
        ) {
            self.scriptSource = scriptSource
            self.components = components
            self.userValueKind = userValueKind
        }
    }
    struct PassDescriptor {
        let passIndex: Int
        let id: Int?
        let constantShaderValues: [String: ShaderValue]
    }
    struct EffectDescriptor {
        let name: String?
        let effectID: Int?
        let passes: [PassDescriptor]

        init(
            name: String?,
            effectID: Int? = nil,
            passes: [PassDescriptor] = []
        ) {
            self.name = name
            self.effectID = effectID
            self.passes = passes
        }
    }
    struct Layer {
        let id: Int
        let layerIndex: Int
        let name: String?
        var visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]? = nil
        let colorRGB: [Float]? = nil
        let scaleHasScript: Bool?
        let alpha: Double?
        let effects: [EffectDescriptor]
        var contentKind: String = "image"
        var particleInstanceOverride: SceneParticleInstanceOverride? = nil
        var textScript: SceneTextScriptDefinition? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil
    }
    var layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(
                id: 10, layerIndex: 0, name: "anchor", visible: true,
                originXYZ: [20, 2250, 0], scaleXYZ: [1.5, 1.5, 1.5],
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
                    alpha: nil, size: nil, lifetime: nil,
                    rate: .init(
                        value: .scalar(2), userPropertyKey: nil,
                        hasScript: true, hasAnimation: false
                    ),
                    speed: nil, count: nil, brightness: nil, color: nil,
                    normalizedColor: nil, controlPoints: [:],
                    controlPointAngles: [:]
                )
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
            ],
            userPropertyDefinitions: [],
            generation: 7
        )
        let frame = SceneScriptFrameInput(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1.0 / 60.0,
            sceneTime: 2
        ), timeZone: TimeZone(secondsFromGMT: 0)!)
        let result = program.evaluate(
            inputs: [
                .layer(layerID: 10, field: .origin): .vector3(20, 2250, 0),
                .layer(layerID: 10, field: .scale): .vector3(1.5, 1.5, 1.5),
            ],
            effectivePropertyValues: [
                "x1": .number(40), "y1": .number(2100), "size": .number(1.25),
            ],
            frame: frame
        )
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
            inputs: [passColorTarget: .vector3(1, 1, 1)],
            effectivePropertyValues: [:],
            frame: frame
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
            effectivePropertyValues: ["mode": .number(2)],
            frame: frame
        )
        let propertyEventStable = propertyEventProgram.evaluate(
            inputs: [propertyEventTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: ["mode": .number(2)],
            frame: frame
        )
        let propertyEventChanged = propertyEventProgram.evaluate(
            inputs: [propertyEventTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: ["mode": .number(4)],
            frame: frame
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
        let particleAudioTarget = SceneDynamicTarget.particle(
            layerID: 139, field: .rate
        )
        let particleAudioProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [particleRateBinding(
                source: particleAudioSource, value: 2
            )],
            generation: 19
        )
        let particleAudioResult = particleAudioProgram.evaluate(
            inputs: [particleAudioTarget: .scalar(2)],
            frame: frame,
            audioSpectrum: audioSnapshot
        )
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
        let layerResult = layerProgram.evaluate(
            inputs: [.layer(layerID: 10, field: .origin): .vector3(20, 2250, 0)],
            effectivePropertyValues: [:],
            frame: frame,
            layerSnapshot: layerSnapshot
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
        let mediaOrigin = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin", source: mediaAnimationSource, value: "20 2250 0",
                properties: [:],
                wrapperKeys: ["animation", "script", "value"]
            )],
            userPropertyDefinitions: [],
            timelineTargets: [animatedOriginTarget],
            generation: 15
        )
        let mediaEvent = SceneScriptMediaThumbnailEventInput(
            hasThumbnail: true,
            generation: 8
        )
        let mediaOriginResult = mediaOrigin.evaluate(
            inputs: [animatedOriginTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: [:], frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        let duplicateMediaOriginResult = mediaOrigin.evaluate(
            inputs: [animatedOriginTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: [:], frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        let playbackTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "alpha"
        )
        let playbackProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "alpha", source: mediaPlaybackSource, value: 1
            )],
            generation: 16
        )
        let playbackFrame = SceneScriptFrameInput(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 0.25,
            sceneTime: 2
        ), timeZone: TimeZone(secondsFromGMT: 0)!)
        let playing = playbackProgram.evaluate(
            inputs: [playbackTarget: .scalar(1)], frame: playbackFrame,
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )
        let playingNextFrame = playbackProgram.evaluate(
            inputs: [playbackTarget: .scalar(1)], frame: playbackFrame,
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )
        let stopped = playbackProgram.evaluate(
            inputs: [playbackTarget: .scalar(1)], frame: playbackFrame,
            mediaPlaybackEvent: .init(state: 0, generation: 2)
        )
        let stringTarget = SceneDynamicTarget.text(
            layerID: 77, field: .content
        )
        let stringProgram = SceneScriptStringProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [textBinding(
                source: mediaPropertiesSource,
                value: "Placeholder"
            )],
            generation: 17
        )
        let stringEvent = SceneScriptMediaPropertiesEventInput(
            title: "春日歌",
            artist: "Artist",
            generation: 1
        )
        let stringResult = stringProgram.evaluate(
            inputs: [stringTarget: .string("Placeholder")],
            frame: frame,
            mediaPropertiesEvent: stringEvent
        )
        let duplicateStringResult = stringProgram.evaluate(
            inputs: [stringTarget: .string("Placeholder")],
            frame: frame,
            mediaPropertiesEvent: stringEvent
        )
        let payload: [String: Any] = [
            "bindings": program.bindings.count,
            "origin": vector(result.values[.layer(layerID: 10, field: .origin)]),
            "scale": vector(result.values[.layer(layerID: 10, field: .scale)]),
            "failures": result.failures.count,
            "mutations": result.materialFunctionMutations.map {
                ["layerID": $0.layerID, "effectIndex": $0.effectIndex,
                 "name": $0.functionName] as [String: Any]
            },
            "passVectorBindings": passVectorProgram.bindings.count,
            "passVectorValue": vector2(passVectorResult.values[passVectorTarget]),
            "passVectorFailures": passVectorResult.failures.count,
            "passVectorWrongWrapperRejected": rejectedPassVectorProgram.bindings.isEmpty,
            "passVectorUserProviderRejected": userBoundPassVectorProgram.bindings.isEmpty,
            "passColorBindings": passColorProgram.bindings.count,
            "passColorValue": vector(passColorResult.values[passColorTarget]),
            "passColorFailures": passColorResult.failures.count,
            "partitionedMediaTargetExcluded": !partitionedPassProgram.definitions
                .contains { $0.target == passColorTarget },
            "partitionedGenericPeerPreserved": partitionedPassProgram.definitions
                .map(\.target) == [passVectorTarget],
            "partitionedGenericPeerValue": vector2(
                partitionedPassResult.values[passVectorTarget]
            ),
            "partitionedMediaTargetNotPublished":
                partitionedPassResult.values[passColorTarget] == nil,
            "partitionedGenericPeerSucceeded": partitionedPassResult.failures.isEmpty,
            "passAudioBindings": passAudioProgram.bindings.count,
            "passAudioDemand": passAudioProgram.hasAudioConsumers,
            "passAudioValue": scalar(passAudioResult.values[passAudioTarget]),
            "passAudioFailures": passAudioResult.failures.count,
            "passAudioWrongWrapperRejected": rejectedPassAudioWrapper.bindings.isEmpty,
            "passAudioUserProviderRejected": rejectedPassAudioProvider.bindings.isEmpty,
            "layerOrigin": vector(
                layerResult.values[.layer(layerID: 10, field: .origin)]
            ),
            "layerFailures": layerResult.failures.count,
            "badReturn": badResult.failures.values.first?.code ?? "",
            "badPublished": !badResult.values.isEmpty,
            "duplicateRejected": duplicate.bindings.isEmpty,
            "wrongOwnerRejected": wrongOwner.bindings.isEmpty,
            "animationBindings": animatedOrigin.bindings.count,
            "animationCommands": animatedOriginResult.animationMutations.map {
                $0.command.rawValue
            },
            "animationWithoutTimelineRejected": rejectedWithoutTimeline.bindings.isEmpty,
            "alphaAnimationBindings": animatedAlpha.bindings.count,
            "alphaAnimationValue": scalar(
                animatedAlphaResult.values[animatedAlphaTarget]
            ),
            "alphaAnimationCommands": animatedAlphaResult.animationMutations.map {
                $0.command.rawValue
            },
            "mediaAnimationCommands": mediaOriginResult.animationMutations.map {
                $0.command.rawValue
            },
            "mediaGenerationDeduplicated":
                duplicateMediaOriginResult.animationMutations.isEmpty,
            "playbackBindings": playbackProgram.bindings.count,
            "playbackPlaying": scalar(playing.values[playbackTarget]),
            "playbackNextFrame": scalar(playingNextFrame.values[playbackTarget]),
            "playbackStopped": scalar(stopped.values[playbackTarget]),
            "playbackFailures": playing.failures.count
                + playingNextFrame.failures.count + stopped.failures.count,
            "stringBindings": stringProgram.bindings.count,
            "stringValue": string(stringResult.values[stringTarget]),
            "stringFailures": stringResult.failures.count,
            "stringGenerationDeduplicated":
                string(duplicateStringResult.values[stringTarget]) == "春日歌 / Artist",
            "audioScaleBindings": audioScaleProgram.bindings.count,
            "audioScaleDemand": audioScaleProgram.hasAudioConsumers,
            "audioScaleValue": vector(audioScaleResult.values[
                .layer(layerID: 10, field: .scale)
            ]),
            "audioScaleFailures": audioScaleResult.failures.count,
            "particleAudioBindings": particleAudioProgram.bindings.count,
            "particleAudioDemand": particleAudioProgram.hasAudioConsumers,
            "particleAudioValue": scalar(
                particleAudioResult.values[particleAudioTarget]
            ),
            "particleAudioFailures": particleAudioResult.failures.count,
            "propertyEventFirst": vector(
                propertyEventFirst.values[propertyEventTarget]
            ),
            "propertyEventStable": vector(
                propertyEventStable.values[propertyEventTarget]
            ),
            "propertyEventChanged": vector(
                propertyEventChanged.values[propertyEventTarget]
            ),
            "propertyEventFailures": propertyEventFirst.failures.count
                + propertyEventStable.failures.count
                + propertyEventChanged.failures.count,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func vector(_ value: SceneDynamicValue?) -> [Double] {
        guard case let .vector3(x, y, z)? = value else { return [] }
        return [x, y, z]
    }

    static func vector2(_ value: SceneDynamicValue?) -> [Double] {
        guard case let .vector2(x, y)? = value else { return [] }
        return [x, y]
    }

    static func scalar(_ value: SceneDynamicValue?) -> Double {
        guard case let .scalar(number)? = value else { return -1 }
        return number
    }

    static func string(_ value: SceneDynamicValue?) -> String {
        guard case let .string(text)? = value else { return "" }
        return text
    }

    static func textBinding(source: String, value: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 2,
                objectID: 77,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(2), .key("text")],
            properties: [:],
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func alphaBinding(source: String, value: Double) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: 0, objectID: 10,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("alpha")],
            properties: [:],
            authoredValue: .number(value),
            valueType: .number,
            wrapperKeys: ["animation", "script", "value"]
        )
    }

    static func binding(
        key: String,
        source: String,
        value: String,
        properties: [String: SceneJSONValue],
        ownerKind: SceneScriptBindingOwner.Kind = .object,
        wrapperKeys: [String]? = nil
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: ownerKind, objectIndex: 0, objectID: 10,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key(key)],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: wrapperKeys ?? (properties.isEmpty
                ? ["script", "value"]
                : ["script", "scriptproperties", "value"])
        )
    }

    static func passBinding(
        key: String,
        source: String,
        value: Double,
        wrapperKeys: [String] = ["script", "value"],
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .pass, objectIndex: 0, objectID: 10,
                effectIndex: 0, effectID: 100, passIndex: 0, passID: 200
            ),
            targetPath: [
                .key("objects"), .index(0), .key("effects"), .index(0),
                .key("passes"), .index(0), .key("constantshadervalues"),
                .key(key),
            ],
            properties: properties,
            authoredValue: .number(value),
            valueType: .number,
            wrapperKeys: wrapperKeys
        )
    }

    static func passVectorBinding(
        key: String = "scale",
        source: String,
        value: String,
        wrapperKeys: [String],
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .pass, objectIndex: 0, objectID: 10,
                effectIndex: 0, effectID: 100, passIndex: 0, passID: 200
            ),
            targetPath: [
                .key("objects"), .index(0), .key("effects"), .index(0),
                .key("passes"), .index(0), .key("constantshadervalues"),
                .key(key),
            ],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: wrapperKeys
        )
    }

    static func particleRateBinding(
        source: String,
        value: Double
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: 3, objectID: 139,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [
                .key("objects"), .index(3),
                .key("instanceoverride"), .key("rate"),
            ],
            properties: [
                "frequency": .number(0), "minvalue": .number(1),
            ],
            authoredValue: .number(value),
            valueType: .number,
            wrapperKeys: ["script", "scriptproperties", "value"]
        )
    }

    static let originSource = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'x',label:'X',value:20,min:0,max:3800,integer:false})
      .addSlider({name:'y',label:'Y',value:2250,min:0,max:3800,integer:false})
      .finish();
    export function update(value) {
      thisLayer.getEffect('history').executeMaterialFunction('clearHistory');
      value.x = scriptProperties.x;
      value.y = scriptProperties.y - 0;
      return value;
    }
    """

    static let propertyEventSource = """
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'step',value:1}).finish();
    let applied = 0;
    export function applyUserProperties(changed) {
      if (changed.hasOwnProperty('mode')) {
        applied = scriptProperties.step + engine.userProperties.mode;
      }
    }
    export function update(value) {
      value.x = applied;
      return value;
    }
    """

    static let scaleSource = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'size',label:'Size',value:1.5,min:1,max:3,integer:false})
      .finish();
    export function update(value) { return scriptProperties.size; }
    """

    static let layerSource = """
    export function update(value) {
      const day = 1;
      const destination = thisScene.getLayer(`C${day}`).origin;
      return destination.copy();
    }
    """

    static let animationSource = """
    export function init(value) {
      thisObject.getAnimation().play();
      return value;
    }
    """

    static let mediaAnimationSource = """
    export function mediaThumbnailChanged(event) {
      if (event.hasThumbnail) {
        const animation = thisObject.getAnimation();
        animation.stop();
        animation.play();
      }
    }
    """

    static let mediaPlaybackSource = """
    'use strict'
    var secondsPerFade = 1
    var resultScale = 1
    var unusedPlaybackSlot = 0
    var scalarAccumulator = 0
    secondsPerFade = 1 / secondsPerFade
    var playbackBranch = MediaPlaybackEvent.PLAYBACK_STOPPED

    export function mediaPlaybackChanged(playbackEvent) {
        if (playbackEvent.state == MediaPlaybackEvent.PLAYBACK_STOPPED) {
            playbackBranch = 0
        } else if (playbackEvent.state == MediaPlaybackEvent.PLAYBACK_PLAYING) {
            playbackBranch = 1
        } else if (playbackEvent.state == MediaPlaybackEvent.PLAYBACK_PAUSED) {
            playbackBranch = 2
        } else {
            playbackBranch = 3
        }
    }

    export function update(authoredScalar) {
        if (playbackBranch == 0) {
            scalarAccumulator = scalarAccumulator - (secondsPerFade * engine.frametime * 2)
            if (scalarAccumulator < 0) { scalarAccumulator = 0 }
        } else if (playbackBranch == 1) {
            scalarAccumulator = scalarAccumulator + (secondsPerFade * engine.frametime * 2)
            if (scalarAccumulator > 1) { scalarAccumulator = 1 }
        } else if (playbackBranch == 2) {
            scalarAccumulator = scalarAccumulator + (secondsPerFade * engine.frametime * 2)
            if (scalarAccumulator > 1) { scalarAccumulator = 1 }
        }
        return scalarAccumulator * resultScale
    }
    """

    static let mediaPropertiesSource = """
    let mediaData = "";
    export function update(value) { return mediaData || value; }
    export function mediaPropertiesChanged(event) {
        mediaData = event.title + " / " + event.artist;
    }
    """

    static let audioScaleSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: "frequency", value: 0})
        .addSlider({name: "minvalue", value: 1})
        .finish();
    const audioBuffer = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
    let initialValue;
    export function init(value) { initialValue = value; }
    export function update() {
        return initialValue.multiply(
            scriptProperties.minvalue + audioBuffer.average[scriptProperties.frequency]
        );
    }
    """

    static let passVectorSource = """
    export function update(value) { return value.multiply(2); }
    """

    static let passColorSource = """
    import * as WEColor from 'WEColor';
    export let scriptProperties = createScriptProperties()
        .addSlider({name: 'speed', value: 0.25})
        .addSlider({name: 'saturation', value: 1})
        .addSlider({name: 'brightness', value: 1})
        .finish();
    export function update(value) {
        return WEColor.hsv2rgb({
            x: engine.runtime * scriptProperties.speed,
            y: scriptProperties.saturation,
            z: scriptProperties.brightness
        });
    }
    """

    static let passAudioScalarSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: "frequency", value: 0})
        .addSlider({name: "minvalue", value: 1})
        .addSlider({name: "maxvalue", value: 2})
        .addSlider({name: "smoothing", value: 20})
        .finish();
    const audioBuffer = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
    let initialValue = 0;
    export function init(value) { initialValue = value; return value; }
    export function update() {
        return initialValue * (
            scriptProperties.minvalue
            + audioBuffer.average[scriptProperties.frequency]
        );
    }
    """

    static let particleAudioSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: "frequency", value: 0})
        .addSlider({name: "minvalue", value: 1})
        .finish();
    const audioBuffer = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
    let initialValue = 0;
    export function init(value) { initialValue = value; return value; }
    export function update() {
        return initialValue * (
            scriptProperties.minvalue
            + audioBuffer.average[scriptProperties.frequency]
        );
    }
    """
}
'''


class ScenePropertyVectorScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required")
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="mwx-scene-vec3-")
        temp = Path(cls.temp_dir.name)
        objects: list[Path] = []
        for source in [
            VM / "SceneQuickJS.c", VM / "SceneQuickJSAnimationHost.c",
            VM / "SceneQuickJSModuleHost.c",
            VM / "SceneQuickJSAudioHost.c",
            VM / "SceneQuickJSMediaEventHost.c",
            VM / "SceneQuickJSHandleHost.c",
            VM / "SceneQuickJSLayerHost.c",
            VM / "SceneQuickJSJobHost.c",
            VM / "SceneQuickJSTimerHost.c",
            QUICKJS / "quickjs.c", QUICKJS / "dtoa.c",
            QUICKJS / "libregexp.c", QUICKJS / "libunicode.c",
        ]:
            output = temp / f"{source.stem}.o"
            subprocess.run([
                clang, "-std=c11", "-O0", "-c", str(source), "-o", str(output),
                "-I", str(VM), "-I", str(QUICKJS),
            ], check=True, capture_output=True, text=True)
            objects.append(output)
        harness = temp / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = temp / "property-vector-script"
        compilation = subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-O",
            "-import-objc-header", str(VM / "SceneQuickJS.h"),
            "-Xcc", f"-I{VM}",
            "-o", str(cls.binary), *map(str, SOURCES), str(harness),
            *map(str, objects), "-Xlinker", "-lm",
        ], capture_output=True, text=True)
        if compilation.returncode != 0:
            raise AssertionError(compilation.stdout + compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def result(self) -> dict[str, object]:
        completed = subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True
        )
        return json.loads(completed.stdout)

    def test_generic_vec3_executes_script_properties_and_scalar_splat(self) -> None:
        value = self.result()
        self.assertEqual(value["bindings"], 2)
        self.assertEqual(value["origin"], [40, 2100, 0])
        self.assertEqual(value["scale"], [1.25, 1.25, 1.25])
        self.assertEqual(value["failures"], 0)
        self.assertEqual(value["mutations"], [
            {"layerID": 10, "effectIndex": 0, "name": "clearHistory"},
        ])
        self.assertEqual(value["layerOrigin"], [4, 5, 6])
        self.assertEqual(value["layerFailures"], 0)

    def test_generic_pass_vec2_uses_typed_scene_script_publication(self) -> None:
        value = self.result()
        self.assertEqual(value["passVectorBindings"], 1)
        self.assertEqual(value["passVectorValue"], [2, 2])
        self.assertEqual(value["passVectorFailures"], 0)
        self.assertTrue(value["passVectorWrongWrapperRejected"])
        self.assertTrue(value["passVectorUserProviderRejected"])

    def test_generic_pass_vec3_executes_wecolor_into_typed_publication(self) -> None:
        value = self.result()
        self.assertEqual(value["passColorBindings"], 1)
        self.assertEqual(value["passColorValue"], [0, 1, 1])
        self.assertEqual(value["passColorFailures"], 0)

    def test_exact_media_target_partition_preserves_disjoint_generic_peer(self) -> None:
        value = self.result()
        self.assertTrue(value["partitionedMediaTargetExcluded"])
        self.assertTrue(value["partitionedGenericPeerPreserved"])
        self.assertEqual(value["partitionedGenericPeerValue"], [2, 2])
        self.assertTrue(value["partitionedMediaTargetNotPublished"])
        self.assertTrue(value["partitionedGenericPeerSucceeded"])

    def test_generic_pass_scalar_executes_static_properties_and_audio(self) -> None:
        value = self.result()
        self.assertEqual(value["passAudioBindings"], 1)
        self.assertTrue(value["passAudioDemand"])
        self.assertEqual(value["passAudioValue"], 1.5)
        self.assertEqual(value["passAudioFailures"], 0)
        self.assertTrue(value["passAudioWrongWrapperRejected"])
        self.assertTrue(value["passAudioUserProviderRejected"])

    def test_bad_return_is_local_and_duplicate_target_is_rejected(self) -> None:
        value = self.result()
        self.assertEqual(value["badReturn"], "bad-return")
        self.assertFalse(value["badPublished"])
        self.assertTrue(value["duplicateRejected"])
        self.assertTrue(value["wrongOwnerRejected"])
        self.assertEqual(value["animationBindings"], 1)
        self.assertEqual(value["animationCommands"], ["play"])
        self.assertTrue(value["animationWithoutTimelineRejected"])
        self.assertEqual(value["alphaAnimationBindings"], 1)
        self.assertEqual(value["alphaAnimationValue"], 0.75)
        self.assertEqual(value["alphaAnimationCommands"], ["play"])
        self.assertEqual(value["mediaAnimationCommands"], ["stop", "play"])
        self.assertTrue(value["mediaGenerationDeduplicated"])
        self.assertEqual(value["playbackBindings"], 1)
        self.assertEqual(value["playbackPlaying"], 0.5)
        self.assertEqual(value["playbackNextFrame"], 1.0)
        self.assertEqual(value["playbackStopped"], 0.5)
        self.assertEqual(value["playbackFailures"], 0)

    def test_media_properties_event_updates_generic_string_owner(self) -> None:
        value = self.result()
        self.assertEqual(value["stringBindings"], 1)
        self.assertEqual(value["stringValue"], "春日歌 / Artist")
        self.assertEqual(value["stringFailures"], 0)
        self.assertTrue(value["stringGenerationDeduplicated"])

    def test_audio_buffers_update_generic_vec3_owner(self) -> None:
        value = self.result()
        self.assertEqual(value["audioScaleBindings"], 1)
        self.assertTrue(value["audioScaleDemand"])
        self.assertEqual(value["audioScaleValue"], [2.25, 2.25, 2.25])
        self.assertEqual(value["audioScaleFailures"], 0)

    def test_audio_buffers_update_generic_particle_rate_owner(self) -> None:
        value = self.result()
        self.assertEqual(value["particleAudioBindings"], 1)
        self.assertTrue(value["particleAudioDemand"])
        self.assertEqual(value["particleAudioValue"], 3.0)
        self.assertEqual(value["particleAudioFailures"], 0)

    def test_apply_user_properties_uses_initial_full_then_changed_delta(self) -> None:
        value = self.result()
        self.assertEqual(value["propertyEventFirst"], [5, 2250, 0])
        self.assertEqual(value["propertyEventStable"], [5, 2250, 0])
        self.assertEqual(value["propertyEventChanged"], [7, 2250, 0])
        self.assertEqual(value["propertyEventFailures"], 0)


if __name__ == "__main__":
    unittest.main()
