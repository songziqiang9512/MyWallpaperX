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
    SCENE / "Properties/ScenePropertyBindingProgram.swift",
    SCENE / "Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SCENE / "Properties/ScenePropertyBindingProgramValidator.swift",
    SCENE / "Properties/ScenePropertyLiveUpdateState.swift",
    SCENE / "Properties/ScenePuppetAnimationPropertyTarget.swift",
    SCENE / "Properties/SceneUserProperty.swift",
    SCENE / "Properties/SceneScriptDynamicProviderHostContract.swift",
    SCENE / "Properties/SceneUserPropertyBindings.swift",
    VM / "SceneScriptPropertyInput.swift",
    SCENE / "Resources/SceneNamedTextureReference.swift",
    SCENE / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE
    / "RenderGraph/LayerDependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
    SCENE / "Runtime/SceneAudioSpectrum.swift",
    VM / "SceneScriptScalarRuntime.swift",
    VM / "SceneScriptLocalStorage.swift",
    VM / "SceneScriptOwnerLifecycleBridge.swift",
    VM / "SceneScriptAnimationHandleBridge.swift",
    VM / "SceneScriptAudioHost.swift",
    VM / "SceneScriptEffectHandleBridge.swift",
    VM / "SceneScriptLayerHandleBridge.swift",
    VM / "SceneScriptLayerRuntimeDescriptorBridge.swift",
    VM / "SceneScriptMediaEventBridge.swift",
    VM / "SceneScriptMediaFrameCoordinator.swift",
    VM / "SceneScriptScalarProgram.swift",
    VM / "SceneScriptScalarProgram+Projection.swift",
    VM / "SceneScriptStringProgram.swift",
    VM / "SceneScriptStringRuntime.swift",
    VM / "SceneScriptVectorCandidateCatalog.swift",
    VM / "SceneScriptVectorProgramModels.swift",
    VM / "SceneScriptVectorProgram.swift",
    VM / "SceneScriptVectorProgram+Registrations.swift",
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
            let title, artist, subTitle, albumTitle, albumArtist, genres, contentType: String
        }
        struct Timeline { let position, duration: Double }
        let current: Data?
        let primaryColor: SIMD3<Double>?
        let secondaryColor: SIMD3<Double>?
        let tertiaryColor: SIMD3<Double>?
        let textColor: SIMD3<Double>?
        let highContrastColor: SIMD3<Double>?
        let generation: UInt64
        let playbackState: Int?
        let playbackGeneration: UInt64
        let properties: Properties?
        let propertiesGeneration: UInt64
        let timeline: Timeline?
        let timelineGeneration: UInt64
    }
}

struct SceneTextScriptDefinition {
    let source: String
}

struct SceneScriptDynamicImageReference: Equatable, Hashable, Sendable {
    let authoredPath: String
    let modelPath: String
}

enum SceneScriptDynamicImageReferenceAnalysis {
    static func references(
        in source: String,
        descriptor: SceneRenderDescriptor
    ) -> [SceneScriptDynamicImageReference]? { nil }
}

struct SceneShaderContract {}

enum SceneBaseMaterialColorModulationCompiler {
    struct Binding {
        let modelPath: String
        let sourceLayerID: Int
        let scriptSource: String
        let scriptProperties: [String: SceneJSONValue]
        let authoredColor: SIMD3<Double>
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        dynamicImageModelPaths: Set<String>,
        admittedLayerColorConsumerIDs: Set<Int>
    ) -> [Binding] { [] }
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
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let id: Int?
            let constantShaderValues: [String: ShaderValue]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]

            init(
                passIndex: Int,
                id: Int?,
                constantShaderValues: [String: ShaderValue],
                textureSlots: [String?] = [],
                userTextureInputs: [SceneEffectTextureInput?] = []
            ) {
                self.passIndex = passIndex
                self.id = id
                self.constantShaderValues = constantShaderValues
                self.textureSlots = textureSlots
                self.userTextureInputs = userTextureInputs
            }
        }

        let name: String?
        let effectID: Int?
        let passes: [PassDescriptor]
        let id: String
        let visible: Bool?

        init(
            name: String?,
            effectID: Int? = nil,
            passes: [PassDescriptor] = [],
            id: String = "effect",
            visible: Bool? = true
        ) {
            self.name = name
            self.effectID = effectID
            self.passes = passes
            self.id = id
            self.visible = visible
        }
    }
    struct Layer {
        let id: Int
        let layerIndex: Int
        let name: String?
        var visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        var anglesXYZ: [Float]? = nil
        var colorRGB: [Float]? = nil
        var spotLight: Bool? = nil
        var directionalLight: Bool? = nil
        let scaleHasScript: Bool?
        let alpha: Double?
        let effects: [EffectDescriptor]
        var contentKind: String = "image"
        var particleInstanceOverride: SceneParticleInstanceOverride? = nil
        var textScript: SceneTextScriptDefinition? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var effectFiles: [String] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var utilityLayer: Int? = nil
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
        let result = program.evaluate(
            inputs: [
                .layer(layerID: 10, field: .origin): .vector3(20, 2250, 0),
                .layer(layerID: 10, field: .scale): .vector3(1.5, 1.5, 1.5),
                angleTarget: .vector3(0, 0, Double(Float.pi / 2)),
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
            effectivePropertyValues: ["renamedProperty": .number(0.2)]
        )
        let dynamicScalarStable = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .number(0.2)]
        )
        let dynamicScalarChanged = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .number(0.35)]
        )
        let dynamicScalarWrongType = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .string("wrong")]
        )
        let dynamicScalarRecovered = dynamicScalarProgram.evaluate(
            inputs: [dynamicScalarTarget: .scalar(-0.2)], frame: frame,
            effectivePropertyValues: ["renamedProperty": .number(0.4)]
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
                == [dynamicScalarLiveTarget]
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
        let passTimelineTarget = SceneDynamicTarget.effectConstant(
            layerID: 10,
            effectIndex: 0,
            passIndex: 0,
            name: "unseenTimelineScalar"
        )
        let passTimeline = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: mediaAnimationSource,
                value: 1,
                wrapperKeys: ["animation", "script", "value"]
            )],
            timelineTargets: [passTimelineTarget],
            generation: 151
        )
        let passTimelineResult = passTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.4)],
            frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        let passTimelineDuplicate = passTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.6)],
            frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        let passTimelineWithoutTarget = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: mediaAnimationSource,
                value: 1,
                wrapperKeys: ["animation", "script", "value"]
            )],
            generation: 152
        )
        let passTimelineWrongWrapper = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: mediaAnimationSource,
                value: 1,
                wrapperKeys: ["animation", "extra", "script", "value"]
            )],
            timelineTargets: [passTimelineTarget],
            generation: 153
        )
        let passTimelineWithProperties = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: mediaAnimationSource,
                value: 1,
                wrapperKeys: ["animation", "script", "value"],
                properties: ["unexpected": .number(1)]
            )],
            timelineTargets: [passTimelineTarget],
            generation: 154
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
            title: "春日歌", artist: "Artist", subTitle: "Live",
            albumTitle: "Album", albumArtist: "Album Artist",
            genres: "Rock,Pop", contentType: "music", generation: 1
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
        let orderedDomain = try SceneScriptQuickJSDomain()
        var orderedDescriptor = descriptor
        orderedDescriptor.layers[2].textScript = .init(
            source: orderedStringMediaSource
        )
        let orderedBindings = [
            alphaBinding(
                source: orderedScalarMediaSource, value: 0.75,
                wrapperKeys: ["script", "value"]
            ),
            binding(
                key: "origin", source: orderedVectorMediaSource,
                value: "10 20 30", properties: [:],
                objectIndex: 1, objectID: 42,
                wrapperKeys: ["script", "value"]
            ),
            textBinding(source: orderedStringMediaSource, value: "Placeholder"),
        ]
        let orderedVector = SceneScriptVectorProgram.compile(
            domain: orderedDomain, descriptor: orderedDescriptor,
            scriptBindings: orderedBindings,
            userPropertyDefinitions: [], generation: 18
        )
        let orderedString = SceneScriptStringProgram.compile(
            domain: orderedDomain, descriptor: orderedDescriptor,
            scriptBindings: orderedBindings, generation: 18
        )
        let orderedScalar = SceneScriptScalarProgram.compile(
            domain: orderedDomain, descriptor: orderedDescriptor,
            scriptBindings: orderedBindings, generation: 18
        )
        let orderedEvents = SceneScriptMediaFrameEvents(
            playback: .init(state: 1, generation: 1),
            properties: stringEvent,
            thumbnail: .init(hasThumbnail: true, generation: 1),
            timeline: .init(position: 12.5, duration: 90, generation: 1)
        )
        let orderedResult = SceneScriptMediaFrameCoordinator.evaluate(
            vectorProgram: orderedVector,
            stringProgram: orderedString,
            scalarProgram: orderedScalar,
            vectorInputs: [
                .layer(layerID: 42, field: .origin): .vector3(10, 20, 30)
            ],
            stringInputs: [stringTarget: .string("Placeholder")],
            scalarInputs: [animatedAlphaTarget: .scalar(0.75)],
            effectivePropertyValues: [:], frame: frame,
            userPropertiesJSON: "{}", events: orderedEvents,
            audioSpectrum: .silent
        )
        let orderedDuplicate = SceneScriptMediaFrameCoordinator.evaluate(
            vectorProgram: orderedVector,
            stringProgram: orderedString,
            scalarProgram: orderedScalar,
            vectorInputs: [
                .layer(layerID: 42, field: .origin): .vector3(10, 20, 30)
            ],
            stringInputs: [stringTarget: .string("Placeholder")],
            scalarInputs: [animatedAlphaTarget: .scalar(0.75)],
            effectivePropertyValues: [:], frame: frame,
            userPropertiesJSON: "{}", events: orderedEvents,
            audioSpectrum: .silent
        )
        let payload: [String: Any] = [
            "bindings": program.bindings.count,
            "origin": vector(result.values[.layer(layerID: 10, field: .origin)]),
            "scale": vector(result.values[.layer(layerID: 10, field: .scale)]),
            "angleValue": vector(result.values[angleTarget]),
            "angleFailure": result.failures[angleTarget]?.code ?? "",
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
            "dynamicScalarBindings": dynamicScalarProgram.bindings.count,
            "dynamicScalarFirst": scalar(
                dynamicScalarFirst.values[dynamicScalarTarget]
            ),
            "dynamicScalarStable": scalar(
                dynamicScalarStable.values[dynamicScalarTarget]
            ),
            "dynamicScalarChanged": scalar(
                dynamicScalarChanged.values[dynamicScalarTarget]
            ),
            "dynamicScalarWrongTypeFailure":
                dynamicScalarWrongType.failures[dynamicScalarTarget]?.code ?? "",
            "dynamicScalarWrongTypePublished":
                dynamicScalarWrongType.values[dynamicScalarTarget] != nil,
            "dynamicScalarRecovered": scalar(
                dynamicScalarRecovered.values[dynamicScalarTarget]
            ),
            "dynamicScalarFallback": scalar(
                dynamicScalarFallback.values[dynamicScalarTarget]
            ),
            "dynamicScalarMalformedRejected":
                malformedDynamicScalar.bindings.isEmpty,
            "dynamicScalarLiveTarget":
                dynamicScalarProgram.livePropertyInputTargets
                    == [dynamicScalarLiveTarget],
            "dynamicVectorLiveTarget":
                dynamicVectorProgram.livePropertyInputTargets
                    == [dynamicVectorLiveTarget],
            "nullOuterUserScalarAdmitted": nullOuterUserScalarAdmitted,
            "failingDynamicScalarInitiallyActive":
                failingDynamicScalarInitiallyActive,
            "failingDynamicScalarBecameUnavailable":
                failingDynamicScalarBecameUnavailable,
            "failingDynamicVectorInitiallyActive":
                failingDynamicVectorInitiallyActive,
            "failingDynamicVectorBecameUnavailable":
                failingDynamicVectorBecameUnavailable,
            "disabledScalarLiveUpdateRejected": disabledScalarLiveUpdateRejected,
            "disabledScalarLiveUpdateWasAtomic": disabledScalarLiveUpdateWasAtomic,
            "disabledVectorLiveUpdateRejected": disabledVectorLiveUpdateRejected,
            "disabledVectorLiveUpdateWasAtomic": disabledVectorLiveUpdateWasAtomic,
            "activeVectorSiblingAccepted": activeVectorSiblingAccepted,
            "layerOrigin": vector(
                layerResult.values[.layer(layerID: 10, field: .origin)]
            ),
            "layerFailures": layerResult.failures.count,
            "layerColorBindings": colorProgram.bindings.count,
            "layerColorMediaTargets": colorProgram.mediaThumbnailTargets
                == [colorTarget],
            "layerColorValue": vector(colorResult.values[colorTarget]),
            "layerColorFailures": colorResult.failures.count,
            "spotColorBindings": spotColorProgram.bindings.count,
            "spotColorValue": vector(spotColorResult.values[spotColorTarget]),
            "spotColorFailures": spotColorResult.failures.count,
            "layerColorCurrent": vector(currentColorResult.values[colorTarget]),
            "layerColorUndefined": vector(
                undefinedColorResult.values[colorTarget]
            ),
            "layerColorUndefinedFailures": undefinedColorResult.failures.count,
            "layerColorFirst": vector(failingColorFirst.values[colorTarget]),
            "layerColorSecondFailure":
                failingColorSecond.failures[colorTarget]?.code ?? "",
            "layerColorSecondPublished":
                failingColorSecond.values[colorTarget] != nil,
            "layerColorThirdFailures": failingColorThird.failures.count,
            "layerColorThirdPublished":
                failingColorThird.values[colorTarget] != nil,
            "layerColorFallback": vector(
                failingColorFallback[colorTarget]?.value
            ),
            "layerColorFallbackSource":
                failingColorFallback[colorTarget]?.source.rawValue ?? "",
            "layerColorFailurePeer": vector(
                colorFailurePeerResult.values[
                    .layer(layerID: 10, field: .origin)
                ]
            ),
            "layerColorFailurePeerFailures":
                colorFailurePeerResult.failures.count,
            "textColorBindings": textColorProgram.bindings.count,
            "textColorValue": vector(textColorResult.values[textColorTarget]),
            "textColorFailures": textColorResult.failures.count,
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
            "genericAlphaBindings": genericAlpha.bindings.count,
            "genericAlphaValue": scalar(genericAlphaResult.values[animatedAlphaTarget]),
            "genericPropertyAlphaBindings": genericPropertyAlpha.bindings.count,
            "genericPropertyAlphaValue": scalar(
                genericPropertyAlphaResult.values[animatedAlphaTarget]
            ),
            "genericAlphaWrongWrapperRejected": rejectedAlphaWrapper.bindings.isEmpty,
            "mediaAnimationCommands": mediaOriginResult.animationMutations.map {
                $0.command.rawValue
            },
            "mediaGenerationDeduplicated":
                duplicateMediaOriginResult.animationMutations.isEmpty,
            "passTimelineBindings": passTimeline.bindings.count,
            "passTimelineValue": scalar(
                passTimelineResult.values[passTimelineTarget]
            ),
            "passTimelineCommands": passTimelineResult.animationMutations.map {
                $0.command.rawValue
            },
            "passTimelineGenerationDeduplicated":
                passTimelineDuplicate.animationMutations.isEmpty,
            "passTimelineWithoutTargetRejected":
                passTimelineWithoutTarget.bindings.isEmpty,
            "passTimelineWrongWrapperRejected":
                passTimelineWrongWrapper.bindings.isEmpty,
            "passTimelinePropertiesRejected":
                passTimelineWithProperties.bindings.isEmpty,
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
                string(duplicateStringResult.values[stringTarget]) ==
                    "春日歌 / Artist / Live / Album / Album Artist / Rock,Pop / music",
            "orderedMediaTrace": string(orderedResult.string.values[stringTarget]),
            "orderedMediaDuplicateTrace":
                string(orderedDuplicate.string.values[stringTarget]),
            "orderedMediaFailures": orderedResult.vector.failures.count
                + orderedResult.string.failures.count
                + orderedResult.scalar.failures.count,
            "orderedLayerMutationOrder": orderedResult.layerMutations.map(\.layerID),
            "orderedLayerMutationFields": orderedResult.layerMutations.map {
                $0.fields == [.visibility] && !$0.visible
            },
            "orderedDuplicateLayerMutations": orderedDuplicate.layerMutations.count,
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

    static func propertyProgram(
        bindings: [(String, SceneDynamicTarget)]
    ) -> ScenePropertyBindingProgram {
        ScenePropertyBindingProgram(
            definitions: bindings.map {
                .init(target: $0.1, valueType: .scalar, authoredValue: .scalar(0))
            },
            instructions: bindings.map {
                .init(
                    propertyKey: $0.0,
                    path: .init(components: [.key($0.0)]),
                    target: $0.1,
                    valueType: .scalar
                )
            }
        )
    }

    static func unchanged(
        _ state: ScenePropertyLiveUpdateState,
        from before: ScenePropertyLiveUpdateState
    ) -> Bool {
        state.effectiveValues == before.effectiveValues
            && state.userValues == before.userValues
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

    static func alphaBinding(
        source: String,
        value: Double,
        properties: [String: SceneJSONValue] = [:],
        wrapperKeys: [String] = ["animation", "script", "value"]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: 0, objectID: 10,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("alpha")],
            properties: properties,
            authoredValue: .number(value),
            valueType: .number,
            wrapperKeys: wrapperKeys
        )
    }

    static func binding(
        key: String,
        source: String,
        value: String,
        properties: [String: SceneJSONValue],
        ownerKind: SceneScriptBindingOwner.Kind = .object,
        objectIndex: Int = 0,
        objectID: Int = 10,
        wrapperKeys: [String]? = nil
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: ownerKind, objectIndex: objectIndex, objectID: objectID,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(objectIndex), .key(key)],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: wrapperKeys ?? (properties.isEmpty
                ? ["script", "value"]
                : ["script", "scriptproperties", "value"])
        )
    }

    static func colorBinding(
        source: String,
        value: String = "0.2 0.3 0.4",
        objectIndex: Int = 4,
        objectID: Int = 500,
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: objectIndex, objectID: objectID,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [
                .key("objects"), .index(objectIndex), .key("color"),
            ],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: properties.isEmpty
                ? ["script", "value"]
                : ["script", "scriptproperties", "value"]
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

    static let angleSource = """
    export function update(value) {
      value.y = 0.15;
      return value;
    }
    """

    static let propertyEventSource = """
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'step',value:1}).finish();
    let applied = 0;
    let initialized = false;
    export function init(value) {
      initialized = true;
      return value;
    }
    export function applyUserProperties(changed) {
      if (!initialized) { throw new Error('properties before init'); }
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
    export function update(value) {
      if (scriptProperties.size < 0) { throw new Error('vector provider failure'); }
      return scriptProperties.size;
    }
    """

    static let layerSource = """
    export function update(value) {
      const day = 1;
      const destination = thisScene.getLayer(`C${day}`).origin;
      return destination.copy();
    }
    """

    static let layerColorSource = """
    let color = new Vec3(0.2, 0.3, 0.4);
    export function mediaThumbnailChanged(event) {
      color.x = event.primaryColor.x;
      color.y = event.primaryColor.y;
      color.z = event.primaryColor.z;
    }
    export function update(value) { return color.copy(); }
    """

    static let spotColorSource = """
    import * as WEColor from 'WEColor';
    export var scriptProperties = createScriptProperties()
      .addCheckbox({name:'useColor2',value:false}).finish();
    export function update(value) {
      return scriptProperties.useColor2
        ? WEColor.normalizeColor(new Vec3(200, 200, 255))
        : value;
    }
    """

    static let scriptPropertyColorSource = """
    export var scriptProperties = createScriptProperties();
    export function update(value) {
      if (scriptProperties.dynamicTitle) { return value; }
      return new Vec3(scriptProperties.titleColor);
    }
    """

    static let thisLayerColorSource = """
    export function update(value) { return thisLayer.color; }
    """

    static let undefinedColorSource = """
    export function update(value) {}
    """

    static let failingColorSource = """
    let calls = { value: 0 };
    export function update(value) {
      calls.value += 1;
      if (calls.value == 1) { return value.multiply(2); }
      throw new Error('color failure');
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
        mediaData = [event.title, event.artist, event.subTitle, event.albumTitle, event.albumArtist, event.genres, event.contentType].join(" / ");
    }
    """

    static let orderedScalarMediaSource = """
    function mark(value) { shared.mediaOrder = (shared.mediaOrder || "") + value; }
    let initialized = false;
    export function init(value) { initialized = true; mark("sI"); return value; }
    export function mediaPlaybackChanged() {
        if (!initialized) { throw new Error("scalar media before init"); }
        mark("sP");
    }
    export function mediaPropertiesChanged() { thisLayer.visible = false; mark("sR"); }
    export function mediaThumbnailChanged() { mark("sH"); }
    export function mediaTimelineChanged() { mark("sL"); }
    export function update(value) { mark("sU"); return value; }
    """

    static let orderedVectorMediaSource = """
    function mark(value) { shared.mediaOrder = (shared.mediaOrder || "") + value; }
    let initialized = false;
    export function init(value) { initialized = true; mark("vI"); return value; }
    export function mediaPlaybackChanged() {
        if (!initialized) { throw new Error("vector media before init"); }
        mark("vP");
    }
    export function mediaPropertiesChanged() { thisLayer.visible = false; mark("vR"); }
    export function mediaThumbnailChanged() { mark("vH"); }
    export function mediaTimelineChanged() { mark("vL"); }
    export function update(value) { mark("vU"); return value; }
    """

    static let orderedStringMediaSource = """
    function mark(value) { shared.mediaOrder = (shared.mediaOrder || "") + value; }
    let initialized = false;
    export function init(value) { initialized = true; mark("tI"); return value; }
    export function mediaPlaybackChanged() {
        if (!initialized) { throw new Error("string media before init"); }
        mark("tP");
    }
    export function mediaPropertiesChanged() { thisLayer.visible = false; mark("tR"); }
    export function mediaThumbnailChanged() { mark("tH"); }
    export function mediaTimelineChanged() { mark("tL"); }
    export function update() { mark("tU"); return shared.mediaOrder; }
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

    static let dynamicScalarSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: "newSlider", value: 50})
        .finish();
    let initialized = false;
    export function init(value) {
        initialized = true;
        return value;
    }
    export function applyUserProperties() {
        if (!initialized) { throw new Error("properties before scalar init"); }
    }
    export function update(value) {
        if (scriptProperties.newSlider < 0) {
            throw new Error("scalar provider failure");
        }
        return -scriptProperties.newSlider;
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
            VM / "SceneQuickJS.c", VM / "SceneQuickJSValueHost.c",
            VM / "SceneQuickJSAnimationHost.c",
            VM / "SceneQuickJSModuleHost.c",
            VM / "SceneQuickJSAudioHost.c",
            VM / "SceneQuickJSMediaEventHost.c",
            VM / "SceneQuickJSHandleHost.c",
            VM / "SceneQuickJSLayerHost.c",
            VM / "SceneQuickJSLayerSnapshotHost.c",
            VM / "SceneQuickJSStorageHost.c",
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
        self.assertEqual(value["bindings"], 3)
        self.assertEqual(value["origin"], [40, 2100, 0])
        self.assertEqual(value["scale"], [1.25, 1.25, 1.25])
        self.assertEqual(value["failures"], 0)
        self.assertEqual(value["mutations"], [
            {"layerID": 10, "effectIndex": 0, "name": "clearHistory"},
        ])
        self.assertEqual(value["layerOrigin"], [4, 5, 6])
        self.assertEqual(value["layerFailures"], 0)

    def test_layer_angle_vm_boundary_uses_degrees_and_publishes_radians(self) -> None:
        value = self.result()
        self.assertEqual(value["angleFailure"], "", value)
        angles = value["angleValue"]
        self.assertAlmostEqual(angles[0], 0, delta=1e-6)
        self.assertAlmostEqual(
            angles[1], 0.15 * 3.141592653589793 / 180, delta=1e-6
        )
        self.assertAlmostEqual(
            angles[2], 3.141592653589793 / 2, delta=1e-6
        )

    def test_spot_light_color_is_a_typed_model_light_consumer(self) -> None:
        value = self.result()
        self.assertEqual(value["spotColorBindings"], 1, value)
        self.assertAlmostEqual(value["spotColorValue"][0], 200 / 255)
        self.assertAlmostEqual(value["spotColorValue"][1], 200 / 255)
        self.assertEqual(value["spotColorValue"][2], 1, value)
        self.assertEqual(value["spotColorFailures"], 0, value)

    def test_generic_pass_vec2_uses_typed_scene_script_publication(self) -> None:
        value = self.result()
        self.assertEqual(value["passVectorBindings"], 1)
        self.assertEqual(value["passVectorValue"], [2, 2])
        self.assertEqual(value["passVectorFailures"], 0)
        self.assertTrue(value["passVectorWrongWrapperRejected"])
        self.assertTrue(value["passVectorUserProviderRejected"])

    def test_direct_image_color_uses_shared_vec3_vm_and_current_fallback(self) -> None:
        value = self.result()
        self.assertEqual(value["layerColorBindings"], 1)
        self.assertTrue(value["layerColorMediaTargets"])
        self.assertEqual(value["layerColorValue"], [0.7, 0.5, 0.25])
        self.assertEqual(value["layerColorFailures"], 0)
        self.assertEqual(value["layerColorCurrent"], [0.6, 0.4, 0.2])
        self.assertEqual(value["layerColorUndefined"], [0.2, 0.3, 0.4])
        self.assertEqual(value["layerColorUndefinedFailures"], 0)
        self.assertEqual(value["layerColorFirst"], [0.4, 0.6, 0.8])
        self.assertEqual(value["layerColorSecondFailure"], "exception")
        self.assertFalse(value["layerColorSecondPublished"])
        self.assertEqual(value["layerColorThirdFailures"], 0)
        self.assertFalse(value["layerColorThirdPublished"])
        self.assertEqual(value["layerColorFallback"], [0.2, 0.3, 0.4])
        self.assertEqual(value["layerColorFallbackSource"], "authored")
        self.assertEqual(value["layerColorFailurePeer"], [10, 20, 30])
        self.assertEqual(value["layerColorFailurePeerFailures"], 1)

    def test_effectful_text_color_uses_static_script_properties_and_vec3_vm(self) -> None:
        value = self.result()
        self.assertEqual(value["textColorBindings"], 1)
        self.assertEqual(value["textColorValue"], [0.25, 0.5, 0.75])
        self.assertEqual(value["textColorFailures"], 0)

    def test_generic_pass_vec3_executes_wecolor_into_typed_publication(self) -> None:
        value = self.result()
        self.assertEqual(value["passColorBindings"], 1)
        self.assertEqual(value["passColorValue"], [0, 1, 1])
        self.assertEqual(value["passColorFailures"], 0)

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
        self.assertEqual(value["genericAlphaBindings"], 1)
        self.assertAlmostEqual(value["genericAlphaValue"], 0.75 + 1 / 60)
        self.assertEqual(value["genericPropertyAlphaBindings"], 1)
        self.assertEqual(value["genericPropertyAlphaValue"], 1.0)
        self.assertTrue(value["genericAlphaWrongWrapperRejected"])
        self.assertEqual(value["mediaAnimationCommands"], ["stop", "play"])
        self.assertTrue(value["mediaGenerationDeduplicated"])
        self.assertEqual(value["passTimelineBindings"], 1)
        self.assertEqual(value["passTimelineValue"], 0.4)
        self.assertEqual(value["passTimelineCommands"], ["stop", "play"])
        self.assertTrue(value["passTimelineGenerationDeduplicated"])
        self.assertTrue(value["passTimelineWithoutTargetRejected"])
        self.assertTrue(value["passTimelineWrongWrapperRejected"])
        self.assertTrue(value["passTimelinePropertiesRejected"])
        self.assertEqual(value["playbackBindings"], 1)
        self.assertEqual(value["playbackPlaying"], 0.5)
        self.assertEqual(value["playbackNextFrame"], 1.0)
        self.assertEqual(value["playbackStopped"], 0.5)
        self.assertEqual(value["playbackFailures"], 0)

    def test_media_properties_event_updates_generic_string_owner(self) -> None:
        value = self.result()
        self.assertEqual(value["stringBindings"], 1)
        self.assertEqual(value["stringValue"], "春日歌 / Artist / Live / Album / Album Artist / Rock,Pop / music")
        self.assertEqual(value["stringFailures"], 0)
        self.assertTrue(value["stringGenerationDeduplicated"])

    def test_media_events_follow_authored_family_and_callback_order(self) -> None:
        value = self.result()
        first = "sIsPsRsHsLsUvIvPvRvHvLvUtItPtRtHtLtU"
        self.assertEqual(value["orderedMediaTrace"], first)
        self.assertEqual(value["orderedMediaDuplicateTrace"], first + "sUvUtU")
        self.assertEqual(value["orderedMediaFailures"], 0)
        self.assertEqual(value["orderedLayerMutationOrder"], [10, 42, 77])
        self.assertEqual(value["orderedLayerMutationFields"], [True, True, True])
        self.assertEqual(value["orderedDuplicateLayerMutations"], 0)

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

    def test_scalar_script_properties_follow_live_typed_user_input(self) -> None:
        value = self.result()
        self.assertEqual(value["dynamicScalarBindings"], 1)
        self.assertAlmostEqual(value["dynamicScalarFirst"], -0.2)
        self.assertAlmostEqual(value["dynamicScalarStable"], -0.2)
        self.assertAlmostEqual(value["dynamicScalarChanged"], -0.35)
        self.assertEqual(value["dynamicScalarWrongTypeFailure"], "invalid-argument")
        self.assertFalse(value["dynamicScalarWrongTypePublished"])
        self.assertAlmostEqual(value["dynamicScalarRecovered"], -0.4)
        self.assertEqual(value["dynamicScalarFallback"], -50)
        self.assertTrue(value["dynamicScalarMalformedRejected"])
        self.assertTrue(value["dynamicScalarLiveTarget"])
        self.assertTrue(value["dynamicVectorLiveTarget"])
        self.assertTrue(value["nullOuterUserScalarAdmitted"])
        self.assertTrue(value["failingDynamicScalarInitiallyActive"])
        self.assertTrue(value["failingDynamicScalarBecameUnavailable"])
        self.assertTrue(value["failingDynamicVectorInitiallyActive"])
        self.assertTrue(value["failingDynamicVectorBecameUnavailable"])
        self.assertTrue(value["disabledScalarLiveUpdateRejected"])
        self.assertTrue(value["disabledScalarLiveUpdateWasAtomic"])
        self.assertTrue(value["disabledVectorLiveUpdateRejected"])
        self.assertTrue(value["disabledVectorLiveUpdateWasAtomic"])
        self.assertTrue(value["activeVectorSiblingAccepted"])

    def test_apply_user_properties_uses_initial_full_then_changed_delta(self) -> None:
        value = self.result()
        self.assertEqual(value["propertyEventFirst"], [5, 2250, 0])
        self.assertEqual(value["propertyEventStable"], [5, 2250, 0])
        self.assertEqual(value["propertyEventChanged"], [7, 2250, 0])
        self.assertEqual(value["propertyEventFailures"], 0)


if __name__ == "__main__":
    unittest.main()
