"""Scalar text/light contracts through the shared real Swift/C VM harness."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
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
            _ = try SceneScriptValueOwner(
                domain: domain,
                source: source,
                target: .text(layerID: 77, field: .maxWidth),
                valueType: .scalar,
                effectNames: [],
                generation: 11, budget: .default
            )
            unsupportedTextFieldRejected = false
        } catch {
            unsupportedTextFieldRejected = true
        }

        let lightDescriptor = Self.lightDescriptor(intensity: 6)
        let lightDomain = try SceneScriptQuickJSDomain()
        try lightDomain.configureLayerCatalog(lightDescriptor)
        let lightTarget = SceneDynamicTarget.layer(
            layerID: 88, field: .intensity
        )
        let lightProgram = SceneScriptScalarProgram.compile(
            domain: lightDomain,
            descriptor: lightDescriptor,
            scriptBindings: [lightBinding(source: lightSource)],
            generation: 12
        )
        let lightResult = lightProgram.evaluate(
            inputs: [lightTarget: .scalar(6)], frame: frame
        )
        let invalidLightDomain = try SceneScriptQuickJSDomain()
        try invalidLightDomain.configureLayerCatalog(lightDescriptor)
        let invalidLightProgram = SceneScriptScalarProgram.compile(
            domain: invalidLightDomain,
            descriptor: lightDescriptor,
            scriptBindings: [lightBinding(source: invalidLightSource)],
            generation: 13
        )
        let invalidLightResult = invalidLightProgram.evaluate(
            inputs: [lightTarget: .scalar(6)], frame: frame
        )
        let nonLightIntensity = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                source: lightSource, value: 48, targetKey: "intensity"
            )],
            generation: 14
        )

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
            "lightBindings": lightProgram.bindings.count,
            "lightValue": scalar(lightResult.values[lightTarget]),
            "lightProjected": SceneScriptScalarProgram.projectedTargets(
                descriptor: lightDescriptor,
                scriptBindings: [lightBinding(source: lightSource)]
            ) == [lightTarget],
            "invalidLightCode":
                invalidLightResult.failures[lightTarget]?.code ?? "",
            "invalidLightPublished": invalidLightResult.values[lightTarget] != nil,
            "nonLightIntensityRejected": nonLightIntensity.bindings.isEmpty,
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
            scaleHasScript: nil,
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

    static func lightDescriptor(intensity: Float) -> SceneRenderDescriptor {
        .init(layers: [.init(
            id: 88,
            layerIndex: 0,
            name: "Point",
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            anglesXYZ: [0, 0, 0],
            colorRGB: [1, 1, 1],
            scaleHasScript: nil,
            alpha: 1,
            effects: [],
            contentKind: "pointLight",
            particleInstanceOverride: nil,
            text: nil,
            textStyle: nil,
            authoredLightIntensity: intensity
        )])
    }

    static func lightBinding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 0,
                objectID: 88,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("intensity")],
            properties: ["gain": .number(0.5)],
            authoredValue: .number(6),
            valueType: .number,
            wrapperKeys: ["script", "scriptproperties", "value"]
        )
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

    static let lightSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: 'gain', label: 'Gain', value: 0.5,
                    min: 0, max: 1, integer: false})
        .finish();
    export function update(value) { return value * scriptProperties.gain; }
    """

    static let invalidLightSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: 'gain', label: 'Gain', value: 0.5,
                    min: 0, max: 1, integer: false})
        .finish();
    export function update(value) { return -1; }
    """
}
'''

class SceneScriptTextPointSizeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="mwx-scene-text-size-")
        cls.addClassCleanup(cls.temp_dir.cleanup)
        cls.binary = compile_vector_harness(Path(cls.temp_dir.name), HARNESS, "text-pointsize")

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
        self.assertEqual(result["lightBindings"], 1)
        self.assertEqual(result["lightValue"], 3)
        self.assertTrue(result["lightProjected"])
        self.assertEqual(result["invalidLightCode"], "bad-return")
        self.assertFalse(result["invalidLightPublished"])
        self.assertTrue(result["nonLightIntensityRejected"])


if __name__ == "__main__":
    unittest.main()
