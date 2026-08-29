#!/usr/bin/env python3

"""String SceneScript failures must expose the changing lower-priority current."""

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
    VM / "SceneScriptStringProgram.swift",
    VM / "SceneScriptStringRuntime.swift",
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
        let textScript: SceneTextScriptDefinition?
        let text: String?
        let textStyle: TextStyle?
    }

    let layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [.init(
            id: 77,
            layerIndex: 0,
            name: "Song Title",
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            anglesXYZ: [0, 0, 0],
            colorRGB: nil,
            alpha: 1,
            effects: [],
            contentKind: "text",
            textScript: .init(source: source),
            text: "authored",
            textStyle: .init(fontPath: nil, colorRGB: [1, 1, 1], pointSize: 32)
        )])
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        let program = SceneScriptStringProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(source: source)],
            generation: 1
        )
        let frame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60.0,
                sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let target = SceneDynamicTarget.text(layerID: 77, field: .content)
        let warmed = program.evaluate(
            inputs: [target: .string("lower-1")],
            frame: frame
        )
        let warmedResolution = resolution(
            program: program,
            target: target,
            lowerPriorityCurrent: "lower-1",
            sceneScriptValues: warmed.values,
            frameIndex: 1
        )
        let failure = program.evaluate(
            inputs: [target: .string("lower-2")],
            frame: frame
        )
        let failureResolution = resolution(
            program: program,
            target: target,
            lowerPriorityCurrent: "lower-2",
            sceneScriptValues: failure.values,
            frameIndex: 2
        )
        let disabled = program.evaluate(
            inputs: [target: .string("lower-3")],
            frame: frame
        )
        let disabledResolution = resolution(
            program: program,
            target: target,
            lowerPriorityCurrent: "lower-3",
            sceneScriptValues: disabled.values,
            frameIndex: 3
        )
        let payload: [String: Any] = [
            "bindings": program.bindings.count,
            "warmedFailures": warmed.failures.count,
            "warmedResolution": warmedResolution,
            "failureCode": failure.failures[target]?.code ?? "",
            "failurePublished": failure.values[target] != nil,
            "failureResolution": failureResolution,
            "disabledFailures": disabled.failures.count,
            "disabledPublished": disabled.values[target] != nil,
            "disabledResolution": disabledResolution,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func binding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 0,
                objectID: 77,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("text")],
            properties: [:],
            authoredValue: .string("authored"),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func resolution(
        program: SceneScriptStringProgram,
        target: SceneDynamicTarget,
        lowerPriorityCurrent: String,
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue],
        frameIndex: UInt64
    ) -> [String: Any] {
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: frameIndex,
            generation: frameIndex,
            definitions: program.definitions,
            timelineValues: [target: .string(lowerPriorityCurrent)],
            sceneScriptValues: sceneScriptValues
        ).snapshot
        guard let resolved = snapshot[target],
              case let .string(value) = resolved.value else {
            return ["value": "missing", "source": "missing"]
        }
        return ["value": value, "source": resolved.source.rawValue]
    }

    static let source = """
    let updateCount = 0;
    export function update(value) {
        updateCount += 1;
        if (updateCount > 1) { throw new Error('string failure'); }
        return `script:${value}`;
    }
    """
}
'''


class SceneScriptStringLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required")
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="mwx-scene-string-life-")
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
        cls.binary = temporary / "scene-script-string-lifecycle"
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

    def test_warmed_failure_and_disabled_frame_use_new_lower_current(self) -> None:
        result = json.loads(
            subprocess.run(
                [str(self.binary)],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        self.assertEqual(result["bindings"], 1)
        self.assertEqual(result["warmedFailures"], 0)
        self.assertEqual(
            result["warmedResolution"],
            {"source": "sceneScript", "value": "script:lower-1"},
        )
        self.assertEqual(result["failureCode"], "exception")
        self.assertFalse(result["failurePublished"])
        self.assertEqual(
            result["failureResolution"],
            {"source": "timeline", "value": "lower-2"},
        )
        self.assertEqual(result["disabledFailures"], 0)
        self.assertFalse(result["disabledPublished"])
        self.assertEqual(
            result["disabledResolution"],
            {"source": "timeline", "value": "lower-3"},
        )


if __name__ == "__main__":
    unittest.main()
