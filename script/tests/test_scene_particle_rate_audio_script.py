#!/usr/bin/env python3

"""Bounded 16-band SceneScript particle-rate producer and fail-closed projection."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Properties/SceneAudioScaledValueScriptDefinition.swift",
    SCENE / "Properties/SceneDynamicSnapshot.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+SyntaxLexer.swift",
    SCENE / "Properties/SceneAudioScaledValueSyntax.swift",
    SCENE / "Properties/SceneAudioScaledValueProgram.swift",
    SCENE / "Properties/SceneAudioScaledValueCompiler.swift",
    SCENE / "Properties/SceneScriptedLayerTransformProjection.swift",
    SCENE / "Runtime/SceneAudioSpectrum.swift",
    SCENE / "Properties/SceneAudioScaledValueRuntime.swift",
]

HARNESS = r'''
import Foundation

enum SceneParticleNumericValue: Equatable, Codable, Sendable {
    case scalar(Double)
}

struct SceneParticleBoundValue: Equatable, Codable, Sendable {
    let value: SceneParticleNumericValue?
    let userPropertyKey: String?
    let hasScript: Bool
    let hasAnimation: Bool
}

struct SceneParticleInstanceOverride: Equatable, Codable, Sendable {
    let id: Int?
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
    struct Layer {
        let id: Int
        let contentKind: String
        var visible: Bool?
        var particleInstanceOverride: SceneParticleInstanceOverride?
        var particleRateAudioScript: SceneAudioScaledValueScriptDefinition?
        var scaleHasScript: Bool?
        var scaleAudioScript: SceneAudioScaledValueScriptDefinition?
        var scaleXYZ: [Float]?
    }
    var layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let goodOne = layer(id: 5944, initial: 1, maximum: 2)
        let goodTwo = layer(id: 31057, initial: 2, maximum: 3)
        let malformed = layer(
            id: 9000, initial: 1, maximum: 2,
            source: source.replacingOccurrences(of: "Math.min(1.0, smoothValue)",
                                                with: "Math.max(1.0, smoothValue)")
        )
        let unsupportedField = SceneRenderDescriptor.Layer(
            id: 9001,
            contentKind: "particle",
            visible: true,
            particleInstanceOverride: override(
                alpha: bound(1, script: true), rate: bound(1)
            ),
            particleRateAudioScript: nil,
            scaleHasScript: false,
            scaleAudioScript: nil,
            scaleXYZ: nil
        )
        let goodScale = scaleLayer(id: 1314)
        let malformedScale = scaleLayer(
            id: 9002,
            source: source.replacingOccurrences(
                of: "engine.AUDIO_RESOLUTION_16",
                with: "engine.AUDIO_RESOLUTION_32"
            )
        )
        let outOfBudget = layer(id: 9003, initial: 1, maximum: 9)
        let descriptor = SceneRenderDescriptor(
            layers: [
                goodOne, goodTwo, malformed, unsupportedField,
                goodScale, malformedScale, outOfBudget,
            ]
        )
        let program = SceneAudioScaledValueProgramCompiler.compile(
            descriptor: descriptor
        )
        let audioProjected = SceneAudioScaledValueProjection.apply(
            program: program, to: descriptor
        )
        let projected = SceneScriptedLayerTransformProjection.apply(
            audioScaledValueProgram: program,
            admittedSceneScriptScaleLayerIDs: [],
            to: audioProjected
        )
        let initialValues = SceneAudioScaledValueRuntime.initialValues(
            program: program
        )
        var runtime = SceneAudioScaledValueRuntime(program: program)
        let silent = runtime.values(audioSpectrum: .silent, frameTime: 1.0 / 60.0)
        let halfInput = SceneAudioSpectrumSnapshot(
            left: [1] + Array(repeating: 0, count: 15),
            right: Array(repeating: 0, count: 16),
            generation: 1
        )
        let halfStep = runtime.values(audioSpectrum: halfInput, frameTime: 0.025)
        let fullInput = SceneAudioSpectrumSnapshot(
            left: [1] + Array(repeating: 0, count: 15),
            right: [1] + Array(repeating: 0, count: 15),
            generation: 2
        )
        let fullStep = runtime.values(audioSpectrum: fullInput, frameTime: 1)
        let invalidFrame = runtime.values(
            audioSpectrum: .silent, frameTime: -.infinity
        )

        let resolvedDefinition = SceneAudioScaledValueScriptDefinition.parse(
            authoredWrapper: [
                "script": source,
                "scriptproperties": ["maxvalue": ["user": "gain", "value": 2]],
                "value": 1,
            ],
            resolvedWrapper: [
                "script": source,
                "scriptproperties": [
                    "frequency": 0,
                    "smoothing": 20,
                    "minvalue": 0.8,
                    "maxvalue": ["user": "gain", "value": 2.5],
                ],
                "value": 1,
            ]
        )

        let payload: [String: Any] = [
            "bindings": program.bindings.count,
            "rejectedParticle": program.rejectedParticleLayerIDs,
            "rejectedScale": program.rejectedScaleLayerIDs,
            "admittedParticle": Array(program.admittedParticleLayerIDs).sorted(),
            "admittedScale": Array(program.admittedScaleLayerIDs).sorted(),
            "projectedVisible": projected.layers.map { $0.visible ?? false },
            "projectedRateHasScript": projected.layers.map {
                $0.particleInstanceOverride?.rate?.hasScript ?? false
            },
            "initialOne": scalar(initialValues, layer: 5944),
            "initialTwo": scalar(initialValues, layer: 31057),
            "initialScale": vector(initialValues, layer: 1314),
            "silentOne": scalar(silent, layer: 5944),
            "silentTwo": scalar(silent, layer: 31057),
            "halfOne": scalar(halfStep, layer: 5944),
            "halfTwo": scalar(halfStep, layer: 31057),
            "fullOne": scalar(fullStep, layer: 5944),
            "fullTwo": scalar(fullStep, layer: 31057),
            "fullScale": vector(fullStep, layer: 1314),
            "invalidFrameOne": scalar(invalidFrame, layer: 5944),
            "resolvedMaximum": resolvedDefinition?.properties["maxvalue"]?.numberValue
                ?? Double.nan,
            "syntaxGood": SceneAudioScaledValueSyntax.parse(source) != nil,
            "syntaxWrongResolution": SceneAudioScaledValueSyntax.parse(
                source.replacingOccurrences(of: "AUDIO_RESOLUTION_16",
                                            with: "AUDIO_RESOLUTION_32")
            ) != nil,
            "syntaxMissingClamp": SceneAudioScaledValueSyntax.parse(
                source.replacingOccurrences(
                    of: "smoothValue = Math.min(1.0, smoothValue);", with: ""
                )
            ) != nil,
            "syntaxWrongInit": SceneAudioScaledValueSyntax.parse(
                source.replacingOccurrences(
                    of: "(typeof value === 'number') ? value : value.x",
                    with: "value"
                )
            ) != nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func layer(
        id: Int,
        initial: Double,
        maximum: Double,
        source script: String = source
    ) -> SceneRenderDescriptor.Layer {
        SceneRenderDescriptor.Layer(
            id: id,
            contentKind: "particle",
            visible: true,
            particleInstanceOverride: override(rate: bound(initial, script: true)),
            particleRateAudioScript: SceneAudioScaledValueScriptDefinition(
                source: script,
                properties: [
                    "frequency": .number(0),
                    "smoothing": .number(20),
                    "minvalue": .number(0.8),
                    "maxvalue": .number(maximum),
                ],
                authoredValue: .number(initial),
                wrapperKeys: ["script", "scriptproperties", "value"]
            ),
            scaleHasScript: false,
            scaleAudioScript: nil,
            scaleXYZ: nil
        )
    }

    static func scaleLayer(
        id: Int,
        source script: String = source
    ) -> SceneRenderDescriptor.Layer {
        SceneRenderDescriptor.Layer(
            id: id,
            contentKind: "image",
            visible: true,
            particleInstanceOverride: nil,
            particleRateAudioScript: nil,
            scaleHasScript: true,
            scaleAudioScript: SceneAudioScaledValueScriptDefinition(
                source: script,
                properties: [
                    "frequency": .number(0),
                    "smoothing": .number(15),
                    "minvalue": .number(0.8),
                    "maxvalue": .number(1.2),
                ],
                authoredValue: .string("1.00000 1.00000 1.00000"),
                wrapperKeys: ["script", "scriptproperties", "value"]
            ),
            scaleXYZ: [1, 1, 1]
        )
    }

    static func bound(_ value: Double, script: Bool = false) -> SceneParticleBoundValue {
        .init(value: .scalar(value), userPropertyKey: nil,
              hasScript: script, hasAnimation: false)
    }

    static func override(
        alpha: SceneParticleBoundValue? = nil,
        rate: SceneParticleBoundValue? = nil
    ) -> SceneParticleInstanceOverride {
        .init(
            id: nil, alpha: alpha, size: nil, lifetime: nil, rate: rate,
            speed: nil, count: nil, brightness: nil, color: nil,
            normalizedColor: nil, controlPoints: [:], controlPointAngles: [:]
        )
    }

    static func scalar(
        _ values: [SceneDynamicTarget: SceneDynamicValue], layer: Int
    ) -> Double {
        guard case let .scalar(value)? = values[.particle(layerID: layer, field: .rate)] else {
            return .nan
        }
        return value
    }

    static func vector(
        _ values: [SceneDynamicTarget: SceneDynamicValue], layer: Int
    ) -> [Double] {
        guard case let .vector3(x, y, z)? = values[
            .layer(layerID: layer, field: .scale)
        ] else { return [] }
        return [x, y, z]
    }

    static let source = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'frequency',label:'frequency',value:0,min:0,max:15,integer:true})
      .addSlider({name:'smoothing',label:'smoothing',value:15,min:0,max:25,integer:false})
      .addSlider({name:'minvalue',label:'minimum',value:0.8,min:0,max:3,integer:false})
      .addSlider({name:'maxvalue',label:'maximum',value:1.2,min:0,max:3,integer:false})
      .finish();
    const audioBuffer = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
    let smoothValue = 0;
    let initialValue;
    export function update() {
      const valueDelta = scriptProperties.maxvalue - scriptProperties.minvalue;
      const audioDelta = audioBuffer.average[scriptProperties.frequency] - smoothValue;
      smoothValue += audioDelta * Math.min(1.0, engine.frametime * scriptProperties.smoothing);
      smoothValue = Math.min(1.0, smoothValue);
      return initialValue * (smoothValue * valueDelta + scriptProperties.minvalue);
    }
    export function init(value) {
      initialValue = (typeof value === 'number') ? value : value.x;
    }
    """
}
'''


class SceneParticleRateAudioScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory()
        temp = Path(cls.temp_dir.name)
        harness = temp / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = temp / "particle-rate-audio"
        subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                "-O",
                "-o",
                str(cls.binary),
                *map(str, SOURCES),
                str(harness),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def result(self) -> dict[str, object]:
        completed = subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True
        )
        return json.loads(completed.stdout)

    def test_stock_shape_compiles_and_unsupported_forms_fail_closed(self) -> None:
        value = self.result()
        self.assertEqual(value["bindings"], 3)
        self.assertEqual(value["admittedParticle"], [5944, 31057])
        self.assertEqual(value["admittedScale"], [1314])
        self.assertEqual(value["rejectedParticle"], [9000, 9001, 9003])
        self.assertEqual(value["rejectedScale"], [9002])
        self.assertEqual(
            value["projectedVisible"],
            [True, True, False, False, True, False, False],
        )
        self.assertEqual(
            value["projectedRateHasScript"],
            [False, False, True, False, False, False, True],
        )
        self.assertTrue(value["syntaxGood"])
        self.assertFalse(value["syntaxWrongResolution"])
        self.assertFalse(value["syntaxMissingClamp"])
        self.assertFalse(value["syntaxWrongInit"])
        self.assertAlmostEqual(value["resolvedMaximum"], 2.5)

    def test_silence_uses_authored_minimum_and_audio_uses_exact_smoothing(self) -> None:
        value = self.result()
        self.assertAlmostEqual(value["initialOne"], 0.8)
        self.assertAlmostEqual(value["initialTwo"], 1.6)
        self.assertEqual(value["initialScale"], [0.8, 0.8, 0.8])
        self.assertAlmostEqual(value["silentOne"], 0.8)
        self.assertAlmostEqual(value["silentTwo"], 1.6)
        self.assertAlmostEqual(value["halfOne"], 1.1)
        self.assertAlmostEqual(value["halfTwo"], 2.7)
        self.assertAlmostEqual(value["fullOne"], 2.0)
        self.assertAlmostEqual(value["fullTwo"], 6.0)
        self.assertEqual(value["fullScale"], [1.2, 1.2, 1.2])
        self.assertAlmostEqual(value["invalidFrameOne"], 2.0)


if __name__ == "__main__":
    unittest.main()
