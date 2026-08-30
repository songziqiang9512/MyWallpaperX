#!/usr/bin/env python3

"""Generic SceneScript scalar owner for an exact text pointsize binding."""

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
    SCENE / "Properties/SceneScriptDynamicProviderHostContract.swift",
    SCENE / "Properties/SceneUserPropertyBindings.swift",
    VM / "SceneScriptPropertyInput.swift",
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
    VM / "SceneScriptScalarProgram+Projection.swift",
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
    }

    struct Layer {
        let id: Int
        let layerIndex: Int
        let name: String?
        let visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        let colorRGB: [Float]?
        let alpha: Double?
        let effects: [EffectDescriptor]
        let contentKind: String
        let particleInstanceOverride: SceneParticleInstanceOverride?
        let text: String?
        let textStyle: TextStyle?
    }

    let layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let descriptor = Self.descriptor(pointSize: 48)
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        let frame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60.0,
                sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let target = SceneDynamicTarget.text(
            layerID: 77,
            field: .pointSize
        )

        let program = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(source: source)],
            generation: 1
        )
        let result = program.evaluate(
            inputs: [target: .scalar(48)],
            frame: frame,
            mediaThumbnailEvent: .init(hasThumbnail: false, generation: 1),
            mediaPlaybackEvent: .init(state: 0, generation: 1)
        )
        let warmedResolution = resolution(
            definitions: program.definitions,
            target: target,
            lowerPriorityCurrent: 48,
            sceneScriptValues: result.values,
            frameIndex: 1
        )
        let exception = program.evaluate(
            inputs: [target: .scalar(60)],
            frame: frame
        )
        let failureResolution = resolution(
            definitions: program.definitions,
            target: target,
            lowerPriorityCurrent: 60,
            sceneScriptValues: exception.values,
            frameIndex: 2
        )
        let disabled = program.evaluate(
            inputs: [target: .scalar(72)],
            frame: frame
        )
        let disabledResolution = resolution(
            definitions: program.definitions,
            target: target,
            lowerPriorityCurrent: 72,
            sceneScriptValues: disabled.values,
            frameIndex: 3
        )

        let mismatch = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(source: source, value: 47)],
            generation: 2
        )
        let wrongType = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                source: source,
                authoredValue: .string("48"),
                valueType: .string
            )],
            generation: 3
        )
        let wrongWrapper = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                source: source,
                wrapperKeys: ["extra", "script", "value"]
            )],
            generation: 4
        )
        let wrongPath = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                source: source,
                targetKey: "fontsize"
            )],
            generation: 5
        )
        let wrongOwner = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                source: source,
                ownerKind: .pass
            )],
            generation: 6
        )
        let duplicate = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(source: source), binding(source: source)],
            generation: 7
        )
        let authoredHighDescriptor = Self.descriptor(pointSize: 1025)
        let authoredHigh = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: authoredHighDescriptor,
            scriptBindings: [binding(source: source, value: 1025)],
            generation: 8
        )
        let lowProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(source: lowSource)],
            generation: 9
        )
        let low = lowProgram.evaluate(
            inputs: [target: .scalar(48)],
            frame: frame
        )
        let highProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(source: highSource)],
            generation: 10
        )
        let high = highProgram.evaluate(
            inputs: [target: .scalar(48)],
            frame: frame
        )
        let unsupportedTextFieldRejected: Bool
        do {
            _ = try SceneScriptScalarOwner(
                domain: domain,
                source: source,
                target: .text(layerID: 77, field: .maxWidth),
                authoredValue: 48,
                effectNames: [],
                generation: 11
            )
            unsupportedTextFieldRejected = false
        } catch {
            unsupportedTextFieldRejected = true
        }

        let payload: [String: Any] = [
            "bindings": program.bindings.count,
            "value": scalar(result.values[target]),
            "failureCount": result.failures.count,
            "mismatchRejected": mismatch.bindings.isEmpty,
            "wrongTypeRejected": wrongType.bindings.isEmpty,
            "wrongWrapperRejected": wrongWrapper.bindings.isEmpty,
            "wrongPathRejected": wrongPath.bindings.isEmpty,
            "wrongOwnerRejected": wrongOwner.bindings.isEmpty,
            "duplicateRejected": duplicate.bindings.isEmpty,
            "exceptionCode": exception.failures[target]?.code ?? "",
            "exceptionPublished": exception.values[target] != nil,
            "disabledFailures": disabled.failures.count,
            "disabledPublished": disabled.values[target] != nil,
            "warmedResolution": warmedResolution,
            "failureResolution": failureResolution,
            "disabledResolution": disabledResolution,
            "authoredHighAccepted": authoredHigh.bindings.count == 1
                && SceneScriptScalarProgram.projectedTargets(
                    descriptor: authoredHighDescriptor,
                    scriptBindings: [binding(source: source, value: 1025)]
                ) == [target],
            "lowCode": low.failures[target]?.code ?? "",
            "lowValue": scalar(low.values[target]),
            "highCode": high.failures[target]?.code ?? "",
            "highValue": scalar(high.values[target]),
            "unsupportedTextFieldRejected": unsupportedTextFieldRejected,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func scalar(_ value: SceneDynamicValue?) -> Double {
        guard case let .scalar(number)? = value else { return -1 }
        return number
    }

    static func resolution(
        definitions: [SceneDynamicTargetDefinition],
        target: SceneDynamicTarget,
        lowerPriorityCurrent: Double,
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue],
        frameIndex: UInt64
    ) -> [String: Any] {
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: frameIndex,
            generation: frameIndex,
            definitions: definitions,
            timelineValues: [target: .scalar(lowerPriorityCurrent)],
            sceneScriptValues: sceneScriptValues
        ).snapshot
        guard let resolved = snapshot[target] else {
            return ["value": -1, "source": "missing"]
        }
        return ["value": scalar(resolved.value), "source": resolved.source.rawValue]
    }

    static func descriptor(pointSize: Float) -> SceneRenderDescriptor {
        .init(layers: [.init(
            id: 77,
            layerIndex: 0,
            name: "Clock",
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            anglesXYZ: [0, 0, 0],
            colorRGB: nil,
            alpha: 1,
            effects: [],
            contentKind: "text",
            particleInstanceOverride: nil,
            text: "12:00",
            textStyle: .init(
                fontPath: nil,
                colorRGB: [1, 1, 1],
                pointSize: pointSize
            )
        )])
    }

    static func binding(
        source: String,
        value: Double = 48,
        authoredValue: SceneJSONValue? = nil,
        valueType: SceneScriptBindingValueType = .number,
        wrapperKeys: [String] = ["script", "value"],
        targetKey: String = "pointsize",
        ownerKind: SceneScriptBindingOwner.Kind = .object
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: ownerKind,
                objectIndex: 0,
                objectID: 77,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key(targetKey)],
            properties: [:],
            authoredValue: authoredValue ?? .number(value),
            valueType: valueType,
            wrapperKeys: wrapperKeys
        )
    }

    static let source = """
    let updateCount = 0;
    export function update(value) {
        updateCount += 1;
        if (updateCount > 1) { throw new Error('pointsize failure'); }
        return value + 8;
    }
    """

    static let lowSource = """
    export function update(value) { return 0; }
    """

    static let highSource = """
    export function update(value) { return 1025; }
    """
}
'''


class SceneScriptTextPointSizeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required")
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="mwx-scene-text-size-")
        temporary = Path(cls.temp_dir.name)
        objects: list[Path] = []
        for source in [
            VM / "SceneQuickJS.c",
            VM / "SceneQuickJSValueHost.c",
            VM / "SceneQuickJSAnimationHost.c",
            VM / "SceneQuickJSModuleHost.c",
            VM / "SceneQuickJSAudioHost.c",
            VM / "SceneQuickJSMediaEventHost.c",
            VM / "SceneQuickJSHandleHost.c",
            VM / "SceneQuickJSLayerHost.c",
            VM / "SceneQuickJSLayerSnapshotHost.c",
            VM / "SceneQuickJSJobHost.c",
            VM / "SceneQuickJSTimerHost.c",
            QUICKJS / "quickjs.c",
            QUICKJS / "dtoa.c",
            QUICKJS / "libregexp.c",
            QUICKJS / "libunicode.c",
        ]:
            output = temporary / f"{source.stem}.o"
            subprocess.run(
                [
                    clang,
                    "-std=c11",
                    "-O0",
                    "-c",
                    str(source),
                    "-o",
                    str(output),
                    "-I",
                    str(VM),
                    "-I",
                    str(QUICKJS),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            objects.append(output)
        harness = temporary / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = temporary / "scene-script-text-pointsize"
        compilation = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                "-O",
                "-import-objc-header",
                str(VM / "SceneQuickJS.h"),
                "-Xcc",
                f"-I{VM}",
                "-o",
                str(cls.binary),
                *map(str, SOURCES),
                str(harness),
                *map(str, objects),
                "-Xlinker",
                "-lm",
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(compilation.stdout + compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def test_exact_pointsize_owner_publishes_and_failures_stay_local(self) -> None:
        result = json.loads(
            subprocess.run(
                [str(self.binary)],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        self.assertEqual(result["bindings"], 1)
        self.assertEqual(result["value"], 56)
        self.assertEqual(result["failureCount"], 0)
        self.assertTrue(result["mismatchRejected"])
        self.assertTrue(result["wrongTypeRejected"])
        self.assertTrue(result["wrongWrapperRejected"])
        self.assertTrue(result["wrongPathRejected"])
        self.assertTrue(result["wrongOwnerRejected"])
        self.assertTrue(result["duplicateRejected"])
        self.assertEqual(result["exceptionCode"], "exception")
        self.assertFalse(result["exceptionPublished"])
        self.assertEqual(result["disabledFailures"], 0)
        self.assertFalse(result["disabledPublished"])
        self.assertEqual(
            result["warmedResolution"],
            {"source": "sceneScript", "value": 56},
        )
        self.assertEqual(
            result["failureResolution"],
            {"source": "timeline", "value": 60},
        )
        self.assertEqual(
            result["disabledResolution"],
            {"source": "timeline", "value": 72},
        )
        self.assertTrue(result["authoredHighAccepted"])
        self.assertEqual(result["lowCode"], "")
        self.assertEqual(result["lowValue"], 0)
        self.assertEqual(result["highCode"], "")
        self.assertEqual(result["highValue"], 1025)
        self.assertTrue(result["unsupportedTextFieldRejected"])


if __name__ == "__main__":
    unittest.main()
