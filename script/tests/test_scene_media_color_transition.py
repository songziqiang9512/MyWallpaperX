#!/usr/bin/env python3

"""Bounded media-color SceneScript compilation and stateful vector playback."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Properties/SceneMediaColorTransitionProgram.swift",
    SCENE_ROOT / "Properties/SceneMediaColorTransitionCompiler.swift",
    SCENE_ROOT / "Properties/SceneMediaColorTransitionCompiler+Syntax.swift",
    SCENE_ROOT / "Runtime/SceneMediaThumbnailInbox.swift",
    SCENE_ROOT / "Properties/SceneMediaColorTransitionRuntime.swift",
]
PROGRAM_COMPILER_SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Properties/SceneMediaColorTransitionProgram.swift",
    SCENE_ROOT / "Properties/SceneMediaColorTransitionCompiler.swift",
    SCENE_ROOT / "Properties/SceneMediaColorTransitionCompiler+Syntax.swift",
    SCENE_ROOT / "Properties/SceneMediaColorTransitionProgramCompiler.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]
    }
}

@main
enum Harness {
    static let target = SceneDynamicTarget.effectConstant(
        layerID: 41, effectIndex: 2, passIndex: 0, name: "color"
    )
    static let otherTarget = SceneDynamicTarget.effectConstant(
        layerID: 42, effectIndex: 0, passIndex: 1, name: "color"
    )
    static let authoredColor = [0.2, 0.4, 0.6]
    static let initialUserColor: SceneUserPropertyValue = .string("0.1 0.3 0.5")
    static let initialUserValues = ["fixtureAccent": initialUserColor]

    static func main() throws {
        let binding = compile()
        let second = compile(
            source: mediaColorSource(colorChannel: "primaryColor"),
            target: otherTarget
        )
        let program = SceneMediaColorTransitionProgram.validated(
            bindings: [binding, second].compactMap { $0 }
        )

        var runtime = SceneMediaColorTransitionRuntime(program: program!)
        let initial = vector(runtime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: .empty,
            frameTime: 0
        ), target)
        let activeThumbnail = mediaInput(
            primaryColor: SIMD3(0.2, 0.9, 0.4),
            color: SIMD3(0.9, 0.7, 0.3), generation: 1,
            playbackState: 1, playbackGeneration: 1
        )
        let eventFrame = vector(runtime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: activeThumbnail,
            frameTime: 0
        ), target)
        let firstHalfStep = vector(runtime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: activeThumbnail,
            frameTime: 0.5
        ), target)
        let midpoint = vector(runtime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: activeThumbnail,
            frameTime: 0.5
        ), target)
        let completed = vector(runtime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: activeThumbnail,
            frameTime: 0
        ), target)
        let primaryCompleted = vector(runtime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: activeThumbnail,
            frameTime: 0
        ), otherTarget)
        let stoppedFallback = vector(runtime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: mediaInput(
                color: SIMD3(0.9, 0.7, 0.3), generation: 1,
                playbackState: 0, playbackGeneration: 2
            ),
            frameTime: 0.25
        ), target)
        let liveUserFallback = vector(runtime.values(
            effectivePropertyValues: ["fixtureAccent": .string("0.8 0.2 0.1")],
            mediaInput: mediaInput(
                color: SIMD3(0.9, 0.7, 0.3), generation: 1,
                playbackState: 0, playbackGeneration: 2
            ),
            frameTime: 0
        ), target)
        let zeroColorFallback = vector(runtime.values(
            effectivePropertyValues: ["fixtureAccent": .string("0.8 0.2 0.1")],
            mediaInput: mediaInput(
                color: .zero, generation: 2,
                playbackState: 1, playbackGeneration: 3
            ),
            frameTime: 0.5
        ), target)
        let malformedUserFallback = vector(runtime.values(
            effectivePropertyValues: ["fixtureAccent": .string("not-a-color")],
            mediaInput: mediaInput(
                color: .zero, generation: 2,
                playbackState: 0, playbackGeneration: 4
            ),
            frameTime: 0
        ), target)
        let missingPaletteFallback = vector(runtime.values(
            effectivePropertyValues: ["fixtureAccent": .string("0.8 0.2 0.1")],
            mediaInput: mediaInput(
                color: nil, generation: 3,
                playbackState: 1, playbackGeneration: 5
            ),
            frameTime: 0.5
        ), target)

        var unknownEventRuntime = SceneMediaColorTransitionRuntime(program: program!)
        let unknownEventFallback = vector(unknownEventRuntime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: mediaInput(
                color: nil, generation: 0,
                playbackState: 77, playbackGeneration: 1
            ),
            frameTime: 0.5
        ), target)
        var nonFiniteEventRuntime = SceneMediaColorTransitionRuntime(program: program!)
        let nonFiniteInput = mediaInput(
            color: SIMD3(.nan, 0.7, 0.3), generation: 1,
            playbackState: 1, playbackGeneration: 1
        )
        let nonFiniteEventFallback = vector(nonFiniteEventRuntime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: nonFiniteInput,
            frameTime: 0.5
        ), target)
        let negativeDeltaFrozen = vector(nonFiniteEventRuntime.values(
            effectivePropertyValues: initialUserValues,
            mediaInput: nonFiniteInput,
            frameTime: -1
        ), target)

        let duplicate = SceneMediaColorTransitionProgram.validated(
            bindings: [binding, binding].compactMap { $0 }
        )
        let wrongWrapper = compile(keys: ["script", "value"])
        let extraWrapper = compile(keys: ["script", "scriptproperties", "value", "user"])
        let directUser = compile(user: "fixtureAccent")
        let timeline = compile(timeline: 1)
        let timelineDiagnostic = compile(diagnostics: ["invalid"])
        let wrongValueKind = compile(valueKind: "vector")
        let wrongComponentCount = compile(components: [0.2, 0.4])
        let nonFiniteAuthored = compile(components: [0.2, .nan, 0.6])
        let wrongTarget = compile(target: .layer(layerID: 41, field: .color))
        let missingProperty = compile(properties: [:])
        let wrongPropertyName = compile(properties: [
            "fallbackColor": .object([
                "user": .string("fixtureAccent"),
                "value": .string("0.2 0.4 0.6"),
            ])
        ])
        let missingPropertyUser = compile(properties: topColorProperty(user: nil))
        let emptyPropertyUser = compile(properties: topColorProperty(user: ""))
        let wrongPropertyValue = compile(
            properties: ["topColor": .object([
                "user": .string("fixtureAccent"),
                "value": .number(0.2),
            ])]
        )
        let extraPropertyField = compile(
            properties: ["topColor": .object([
                "user": .string("fixtureAccent"),
                "value": .string("0.2 0.4 0.6"),
                "hidden": .bool(false),
            ])]
        )
        let extraScriptProperty = compile(properties: topColorProperty(
            extra: ["unused": .string("value")]
        ))
        let wrongDuration = compile(source: mediaColorSource(duration: 2))
        let wrongThumbnailHook = compile(source: mediaColorSource(
            thumbnailHook: "thumbnailWasChanged"
        ))
        let wrongPlaybackHook = compile(source: mediaColorSource(
            playbackHook: "playbackWasChanged"
        ))
        let wrongUpdateHook = compile(source: mediaColorSource(updateHook: "tick"))
        let wrongInterpolation = compile(source: mediaColorSource(
            interpolationMethod: "add"
        ))
        let wrongTimerOperator = compile(source: mediaColorSource(
            timerOperator: "-="
        ))
        let wrongZeroOperator = compile(source: mediaColorSource(
            zeroOperator: "!="
        ))
        let unsupportedPaletteMember = compile(source: mediaColorSource(
            colorChannel: "tertiaryColor"
        ))
        let authoredWrapperOverride = compile(
            rawValue: "1 1 1",
            components: [1, 1, 1]
        )
        let escapedBlackLiteral = compile(
            source: mediaColorSource().replacingOccurrences(
                of: "\"0 0 0\"",
                with: "\"\\\\0 0 0\""
            )
        )
        let extraHook = compile(source: mediaColorSource()
            + "\nexport function unrelatedHook() { return 0; }")
        let malformedSource = compile(source: mediaColorSource() + "\n{")
        let oversizedSource = compile(source: mediaColorSource()
            + String(repeating: " ", count: 17_000))
        let hostNameShadow = compile(source: mediaColorSource()
            .replacingOccurrences(of: "blendSeconds", with: "engine"))
        let reservedBinding = compile(source: mediaColorSource()
            .replacingOccurrences(of: "elapsedSeconds", with: "yield"))
        let returnLineBreak = compile(source: mediaColorSource()
            .replacingOccurrences(of: "return resultTint", with: "return\nresultTint"))

        let result: [String: Any] = [
            "projectFixtureCompiled": binding != nil,
            "programValidated": program?.bindings.count == 2,
            "programTargetsPreserved": program?.targets == [target, otherTarget],
            "exactVectorTarget": binding?.definition.target == target,
            "vectorValueType": binding?.definition.valueType == .vector3,
            "initial": initial,
            "eventFrame": eventFrame,
            "firstHalfStep": firstHalfStep,
            "midpoint": midpoint,
            "completed": completed,
            "primaryCompleted": primaryCompleted,
            "stoppedFallback": stoppedFallback,
            "liveUserFallback": liveUserFallback,
            "zeroColorFallback": zeroColorFallback,
            "malformedUserFallback": malformedUserFallback,
            "missingPaletteFallback": missingPaletteFallback,
            "unknownEventFallback": unknownEventFallback,
            "nonFiniteEventFallback": nonFiniteEventFallback,
            "negativeDeltaFrozen": negativeDeltaFrozen,
            "duplicateTargetRejected": duplicate == nil,
            "wrongWrapperRejected": wrongWrapper == nil,
            "extraWrapperRejected": extraWrapper == nil,
            "directUserRejected": directUser == nil,
            "timelineRejected": timeline == nil,
            "timelineDiagnosticRejected": timelineDiagnostic == nil,
            "wrongValueKindRejected": wrongValueKind == nil,
            "wrongComponentCountRejected": wrongComponentCount == nil,
            "nonFiniteAuthoredRejected": nonFiniteAuthored == nil,
            "wrongTargetRejected": wrongTarget == nil,
            "missingPropertyRejected": missingProperty == nil,
            "wrongPropertyNameRejected": wrongPropertyName == nil,
            "missingPropertyUserRejected": missingPropertyUser == nil,
            "emptyPropertyUserRejected": emptyPropertyUser == nil,
            "wrongPropertyValueRejected": wrongPropertyValue == nil,
            "extraPropertyFieldRejected": extraPropertyField == nil,
            "extraScriptPropertyRejected": extraScriptProperty == nil,
            "wrongDurationRejected": wrongDuration == nil,
            "wrongThumbnailHookRejected": wrongThumbnailHook == nil,
            "wrongPlaybackHookRejected": wrongPlaybackHook == nil,
            "wrongUpdateHookRejected": wrongUpdateHook == nil,
            "wrongInterpolationRejected": wrongInterpolation == nil,
            "wrongTimerOperatorRejected": wrongTimerOperator == nil,
            "wrongZeroOperatorRejected": wrongZeroOperator == nil,
            "unsupportedPaletteMemberRejected": unsupportedPaletteMember == nil,
            "authoredWrapperOverrideCompiled": authoredWrapperOverride != nil,
            "escapedBlackLiteralRejected": escapedBlackLiteral == nil,
            "extraHookRejected": extraHook == nil,
            "malformedSourceRejected": malformedSource == nil,
            "sourceBudgetRejected": oversizedSource == nil,
            "hostNameShadowRejected": hostNameShadow == nil,
            "reservedBindingRejected": reservedBinding == nil,
            "returnLineBreakRejected": returnLineBreak == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func compile(
        source: String = mediaColorSource(),
        rawValue: String = "0.2 0.4 0.6",
        keys: [String] = ["script", "scriptproperties", "value"],
        user: String? = nil,
        timeline: Int? = nil,
        diagnostics: [String] = [],
        valueKind: String = "binding",
        components: [Double]? = authoredColor,
        properties: [String: SceneJSONValue] = topColorProperty(),
        target: SceneDynamicTarget = target
    ) -> SceneMediaColorTransitionBinding? {
        SceneMediaColorTransitionCompiler.compile(
            value: SceneDocument.ShaderValue(
                rawValue: rawValue,
                valueKind: valueKind,
                userBinding: user,
                components: components,
                timeline: timeline,
                timelineDiagnostics: diagnostics,
                scriptSource: source,
                bindingKeys: keys
            ),
            target: target,
            properties: properties
        )
    }

    static func topColorProperty(
        user: String? = "fixtureAccent",
        extra: [String: SceneJSONValue] = [:]
    ) -> [String: SceneJSONValue] {
        var fields: [String: SceneJSONValue] = [
            "value": .string("0.2 0.4 0.6"),
        ]
        if let user { fields["user"] = .string(user) }
        var properties = extra
        properties["topColor"] = .object(fields)
        return properties
    }

    static func vector(
        _ values: [SceneDynamicTarget: SceneDynamicValue],
        _ target: SceneDynamicTarget
    ) -> [Double] {
        guard case let .vector3(x, y, z)? = values[target] else {
            return [.nan, .nan, .nan]
        }
        return [x, y, z]
    }

    static func mediaInput(
        primaryColor: SIMD3<Double>? = nil,
        color: SIMD3<Double>?,
        generation: UInt64,
        playbackState: Int?,
        playbackGeneration: UInt64
    ) -> SceneMediaThumbnailInbox.Snapshot {
        SceneMediaThumbnailInbox.Snapshot(
            current: nil,
            primaryColor: primaryColor,
            secondaryColor: color,
            generation: generation,
            playbackState: playbackState,
            playbackGeneration: playbackGeneration
        )
    }

    static func mediaColorSource(
        duration: Int = 1,
        thumbnailHook: String = "mediaThumbnailChanged",
        playbackHook: String = "mediaPlaybackChanged",
        updateHook: String = "update",
        interpolationMethod: String = "subtract",
        timerOperator: String = "+=",
        zeroOperator: String = "==",
        colorChannel: String = "secondaryColor"
    ) -> String {
        """
        "use strict"
        /* Project-owned semantic fixture; names and authored color differ from corpus data. */
        export var scriptProperties = createScriptProperties()
            .addColor({ name: "topColor", label: "Fixture Accent", value: new Vec3(0.2, 0.4, 0.6) })
            .finish()
        const blendSeconds = \(duration)
        var playbackStatus = 0
        let incomingTint = scriptProperties.topColor
        let outgoingTint = scriptProperties.topColor
        let elapsedSeconds = blendSeconds

        export function \(thumbnailHook)(thumbnailUpdate) {
            elapsedSeconds = 0
            outgoingTint = incomingTint
            incomingTint = thumbnailUpdate.\(colorChannel)
        }

        export function \(playbackHook)(playbackUpdate) {
            playbackStatus = playbackUpdate.state
        }

        export function \(updateHook)() {
            var resultTint = incomingTint
            if (elapsedSeconds < blendSeconds) {
                resultTint = incomingTint.\(interpolationMethod)(outgoingTint)
                    .multiply(elapsedSeconds / blendSeconds).add(outgoingTint)
                elapsedSeconds \(timerOperator) engine.frametime
            }
            if (incomingTint \(zeroOperator) "0 0 0" || playbackStatus == 0) {
                resultTint = scriptProperties.topColor
            }
            return resultTint
        }
        """
    }
}
'''


PROGRAM_COMPILER_HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]
    }
}

enum SceneScriptBindingValueType {
    case string
    case array
}

struct SceneScriptBindingOwner {
    enum Kind {
        case pass
        case effect
    }

    let kind: Kind
    let objectIndex: Int?
    let objectID: Int?
    let effectIndex: Int?
    let effectID: Int?
    let passIndex: Int?
    let passID: Int?
}

enum SceneScriptBindingPathComponent: Equatable {
    case key(String)
    case index(Int)
}

struct SceneScriptBindingIR {
    let source: String
    let owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let valueType: SceneScriptBindingValueType

    var targetKey: String {
        guard case let .key(key) = targetPath.last else { return "" }
        return key
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let id: Int?
            let passIndex: Int
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let effectID: Int?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let layerIndex: Int
        let effects: [EffectDescriptor]
    }

    let layers: [Layer]
}

@main
enum ProgramCompilerHarness {
    static let layerID = 8_001
    static let effectID = 8_101
    static let passID = 8_201
    static let target = SceneDynamicTarget.effectConstant(
        layerID: layerID,
        effectIndex: 0,
        passIndex: 0,
        name: "color"
    )

    static func main() throws {
        let descriptor = makeDescriptor()
        let valid = makeBinding()
        let validProgram = compile(descriptor: descriptor, bindings: [valid])
        let ownerKindMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(ownerKind: .effect)]
        )
        let objectIndexMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(objectIndex: 1)]
        )
        let layerIDMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(layerID: layerID + 1)]
        )
        let effectIDMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(effectID: effectID + 1)]
        )
        let passIDMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(passID: passID + 1)]
        )
        let pathMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(targetPath: mismatchedPath())]
        )
        let sourceMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(source: mediaColorSource() + "\n")]
        )
        let propertyPayloadOverride = compile(
            descriptor: descriptor,
            bindings: [makeBinding(properties: [
                "topColor": .object([
                    "user": .string("fixtureAccent"),
                    "value": .string("0.2 0.4 0.61"),
                ])
            ])]
        )
        let authoredMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(authored: "0.2 0.4 0.61")]
        )
        let typeMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(valueType: .array)]
        )
        let duplicateTarget = compile(
            descriptor: descriptor,
            bindings: [valid, valid]
        )

        let result: [String: Any] = [
            "validPassOwnedCompiled": validProgram?.bindings.count == 1,
            "exactTargetProjected": validProgram?.bindings.first?.definition.target == target,
            "ownerKindMismatchRejected": ownerKindMismatch?.bindings.isEmpty == true,
            "objectIndexMismatchRejected": objectIndexMismatch?.bindings.isEmpty == true,
            "layerIDMismatchRejected": layerIDMismatch?.bindings.isEmpty == true,
            "effectIDMismatchRejected": effectIDMismatch?.bindings.isEmpty == true,
            "passIDMismatchRejected": passIDMismatch?.bindings.isEmpty == true,
            "targetPathMismatchRejected": pathMismatch?.bindings.isEmpty == true,
            "sourceMismatchRejected": sourceMismatch?.bindings.isEmpty == true,
            "propertyPayloadOverrideCompiled": propertyPayloadOverride?.bindings.count == 1,
            "authoredMismatchRejected": authoredMismatch?.bindings.isEmpty == true,
            "valueTypeMismatchRejected": typeMismatch?.bindings.isEmpty == true,
            "duplicateExactTargetRejected": duplicateTarget == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        bindings: [SceneScriptBindingIR]
    ) -> SceneMediaColorTransitionProgram? {
        SceneMediaColorTransitionProgramCompiler.compile(
            descriptor: descriptor,
            scriptBindings: bindings
        )
    }

    static func makeDescriptor() -> SceneRenderDescriptor {
        SceneRenderDescriptor(layers: [
            .init(
                id: layerID,
                layerIndex: 0,
                effects: [.init(
                    effectID: effectID,
                    passes: [.init(
                        id: passID,
                        passIndex: 0,
                        constantShaderValues: [
                            "color": .init(
                                rawValue: "0.2 0.4 0.6",
                                valueKind: "binding",
                                userBinding: nil,
                                components: [0.2, 0.4, 0.6],
                                timeline: nil,
                                timelineDiagnostics: [],
                                scriptSource: mediaColorSource(),
                                bindingKeys: ["script", "scriptproperties", "value"]
                            )
                        ]
                    )]
                )]
            )
        ])
    }

    static func makeBinding(
        source: String = mediaColorSource(),
        authored: String = "0.2 0.4 0.6",
        properties: [String: SceneJSONValue] = topColorProperty(),
        valueType: SceneScriptBindingValueType = .string,
        ownerKind: SceneScriptBindingOwner.Kind = .pass,
        objectIndex: Int = 0,
        layerID: Int = layerID,
        effectID: Int = effectID,
        passID: Int = passID,
        targetPath: [SceneScriptBindingPathComponent]? = nil
    ) -> SceneScriptBindingIR {
        SceneScriptBindingIR(
            source: source,
            owner: .init(
                kind: ownerKind,
                objectIndex: objectIndex,
                objectID: layerID,
                effectIndex: 0,
                effectID: effectID,
                passIndex: 0,
                passID: passID
            ),
            targetPath: targetPath ?? expectedPath(name: "color"),
            properties: properties,
            authoredValue: .string(authored),
            valueType: valueType
        )
    }

    static func expectedPath(name: String) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(0),
            .key("effects"), .index(0),
            .key("passes"), .index(0),
            .key("constantshadervalues"), .key(name),
        ]
    }

    static func mismatchedPath() -> [SceneScriptBindingPathComponent] {
        [
            .key("object"), .index(0),
            .key("effects"), .index(0),
            .key("passes"), .index(0),
            .key("constantshadervalues"), .key("color"),
        ]
    }

    static func topColorProperty() -> [String: SceneJSONValue] {
        [
            "topColor": .object([
                "user": .string("fixtureAccent"),
                "value": .string("0.2 0.4 0.6"),
            ])
        ]
    }

    static func mediaColorSource() -> String {
        """
        "use strict"
        export var scriptProperties = createScriptProperties()
            .addColor({ name: "topColor", label: "Fixture Accent", value: new Vec3(0.2, 0.4, 0.6) })
            .finish()
        const blendSeconds = 1
        var playbackStatus = 0
        let incomingTint = scriptProperties.topColor
        let outgoingTint = scriptProperties.topColor
        let elapsedSeconds = blendSeconds

        export function mediaThumbnailChanged(thumbnailUpdate) {
            elapsedSeconds = 0
            outgoingTint = incomingTint
            incomingTint = thumbnailUpdate.secondaryColor
        }
        export function mediaPlaybackChanged(playbackUpdate) {
            playbackStatus = playbackUpdate.state
        }
        export function update() {
            var resultTint = incomingTint
            if (elapsedSeconds < blendSeconds) {
                resultTint = incomingTint.subtract(outgoingTint)
                    .multiply(elapsedSeconds / blendSeconds).add(outgoingTint)
                elapsedSeconds += engine.frametime
            }
            if (incomingTint == "0 0 0" || playbackStatus == 0) {
                resultTint = scriptProperties.topColor
            }
            return resultTint
        }
        """
    }
}
'''


class SceneMediaColorTransitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.tempdir = tempfile.TemporaryDirectory()
        directory = Path(cls.tempdir.name)

        harness = directory / "MediaColorTransitionHarness.swift"
        executable = directory / "media-color-transition-harness"
        harness.write_text(HARNESS, encoding="utf-8")
        cls._compile(swiftc, SWIFT_SOURCES, harness, executable)
        output = subprocess.run(
            [str(executable)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        cls.result = json.loads(output)

        program_harness = directory / "MediaColorTransitionProgramHarness.swift"
        program_executable = directory / "media-color-transition-program-harness"
        program_harness.write_text(PROGRAM_COMPILER_HARNESS, encoding="utf-8")
        cls._compile(
            swiftc,
            PROGRAM_COMPILER_SWIFT_SOURCES,
            program_harness,
            program_executable,
        )
        program_output = subprocess.run(
            [str(program_executable)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        cls.program_result = json.loads(program_output)

    @classmethod
    def _compile(
        cls,
        swiftc: str,
        sources: list[Path],
        harness: Path,
        executable: Path,
    ) -> None:
        try:
            subprocess.run(
                [swiftc, *map(str, sources), str(harness), "-o", str(executable)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as error:
            raise AssertionError(error.stderr) from error

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "tempdir"):
            cls.tempdir.cleanup()

    def assert_vector(self, key: str, expected: list[float]) -> None:
        self.assertEqual(len(self.result[key]), len(expected))
        for actual, wanted in zip(self.result[key], expected, strict=True):
            self.assertAlmostEqual(actual, wanted, places=12, msg=key)

    def test_project_owned_vector_profile_compiles(self) -> None:
        self.assertTrue(self.result["projectFixtureCompiled"])
        self.assertTrue(self.result["programValidated"])
        self.assertTrue(self.result["programTargetsPreserved"])
        self.assertTrue(self.result["exactVectorTarget"])
        self.assertTrue(self.result["vectorValueType"])
        self.assertTrue(self.result["authoredWrapperOverrideCompiled"])

    def test_no_event_and_stopped_state_use_live_user_top_color(self) -> None:
        self.assert_vector("initial", [0.1, 0.3, 0.5])
        self.assert_vector("stoppedFallback", [0.1, 0.3, 0.5])
        self.assert_vector("liveUserFallback", [0.8, 0.2, 0.1])
        self.assert_vector("zeroColorFallback", [0.8, 0.2, 0.1])
        self.assert_vector("malformedUserFallback", [0.2, 0.4, 0.6])
        self.assert_vector("missingPaletteFallback", [0.8, 0.2, 0.1])

    def test_secondary_color_transition_preserves_authored_update_order(self) -> None:
        self.assert_vector("eventFrame", [0.1, 0.3, 0.5])
        self.assert_vector("firstHalfStep", [0.1, 0.3, 0.5])
        self.assert_vector("midpoint", [0.5, 0.5, 0.4])
        self.assert_vector("completed", [0.9, 0.7, 0.3])
        self.assert_vector("primaryCompleted", [0.2, 0.9, 0.4])

    def test_unknown_or_nonfinite_events_do_not_mutate_safe_state(self) -> None:
        self.assert_vector("unknownEventFallback", [0.1, 0.3, 0.5])
        self.assert_vector("nonFiniteEventFallback", [0.1, 0.3, 0.5])
        self.assert_vector("negativeDeltaFrozen", [0.1, 0.3, 0.5])

    def test_non_profile_sources_shapes_and_targets_fail_closed(self) -> None:
        rejected = [key for key in self.result if key.endswith("Rejected")]
        self.assertGreaterEqual(len(rejected), 27)
        self.assertTrue(all(self.result[key] for key in rejected), rejected)

    def test_program_compiler_projects_only_lossless_pass_owned_ir(self) -> None:
        self.assertTrue(self.program_result["validPassOwnedCompiled"])
        self.assertTrue(self.program_result["exactTargetProjected"])
        self.assertTrue(self.program_result["propertyPayloadOverrideCompiled"])
        rejected = [
            key for key in self.program_result if key.endswith("Rejected")
        ]
        self.assertEqual(len(rejected), 10)
        self.assertTrue(
            all(self.program_result[key] for key in rejected), rejected
        )


if __name__ == "__main__":
    unittest.main()
