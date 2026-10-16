"""Scalar text/light contracts through the shared real Swift/C VM harness."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import ROOT, compile_vector_harness

HARNESS = r'''
// External JSON carrier only; the point-size render normalization is production.
enum SceneDocumentLoader {
    static func floatValue(_ value: Any?) -> Float? { (value as? NSNumber)?.floatValue }
    static func floatVector(_ value: Any?) -> [Float]? {
        (value as? [NSNumber])?.map(\.floatValue)
    }
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
            "setterRoundTrips": try [setterRoundTrip(false), setterRoundTrip(true)],
            "setterFiniteDomain": try setterFiniteDomain(),
            "setterRejections": try setterRejections(),
            "setterPartialMerge": try setterPartialMerge(),
            "setterRestrictedOwners": try setterRestrictedOwners(),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func setterDescriptor() -> SceneRenderDescriptor {
        var descriptor = Self.descriptor(pointSize: 48)
        descriptor.layers.append(.init(id: 88, layerIndex: 1, name: "image-peer",
            visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], alpha: 1,
            effects: [], contentKind: "image"))
        return descriptor
    }

    static func setterFrame(_ time: Double) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1.0 / 60, sceneTime: time))
    }

    static func setterOwner(_ domain: SceneScriptQuickJSDomain, _ source: String) throws
        -> SceneScriptValueOwner {
        try .init(domain: domain, source: source,
            target: .text(layerID: 77, field: .content), valueType: .string,
            effectNames: [], generation: 30, budget: .default)
    }

    static func setterEvaluate(_ owner: SceneScriptValueOwner)
        -> Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure> {
        owner.evaluate(input: .string("12:00"), frame: setterFrame(1),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}",
            expectedGeneration: 30, interruptBudget: nil)
    }

    static func setterCode<T>(_ result: Result<T, SceneScriptScalarRuntimeFailure>) -> String {
        switch result { case .success: return "ok"; case let .failure(error): return error.code }
    }

    static func setterRoundTrip(_ renamed: Bool) throws -> [String: Any] {
        var descriptor = setterDescriptor()
        var source = """
        const face=engine.registerAsset('fonts/own.ttf');let last=48;
        export function mediaPropertiesChanged(event){
            const picked=thisScene.getLayerByID(77);
            if(thisLayer.pointsize!==last||picked.pointsize!==last)throw Error('current size');
            if(event.title==='partial'){
                thisLayer.text='partial';thisLayer.font=face;thisLayer.origin=new Vec3(3,4,0);return;
            }
            const next=last+12;thisLayer.pointsize=next-4;
            if(picked.pointsize!==next-4)throw Error('lookup read-your-writes');
            picked.pointsize=next;
            if(thisLayer.pointsize!==next)throw Error('owner read-your-writes');
            thisLayer.text=event.title;last=next;
        }
        """
        if renamed {
            source = source.replacingOccurrences(of: "picked", with: "selected")
                .replacingOccurrences(of: "last", with: "previousSize")
                .replacingOccurrences(of: "next=previousSize+12", with: "next=previousSize+3*4")
                .replacingOccurrences(of: "fonts/own.ttf", with: "fonts/renamed.ttf")
        }
        descriptor.layers[0].textScript = .init(source: source)
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerRuntimeFields(descriptor)
        let ir = SceneScriptBindingIR(source: source,
            owner: .init(kind: .object, objectIndex: 0, objectID: 77,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key("text")], properties: [:],
            authoredValue: .string("12:00"), valueType: .string, wrapperKeys: ["script", "value"])
        let program = SceneScriptStringProgram.compile(domain: domain, descriptor: descriptor,
            scriptBindings: [ir], generation: 30)
        let layers = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [77])
        let target = SceneDynamicTarget.text(layerID: 77, field: .pointSize)
        var sizes: [Double] = [], texts: [String] = [], dirty: [Bool] = [], failures = 0
        var sources: [String] = [], held: SceneDynamicSnapshot?
        for (index, title) in ["one", "two", "partial"].enumerated() {
            let result = program.evaluate(inputs: [.text(layerID: 77, field: .content): .string("12:00")],
                frame: setterFrame(Double(index + 1)),
                mediaPropertiesEvent: .init(title: title, artist: "Own Artist", generation: UInt64(index + 1)))
            failures += result.failures.count
            dirty.append(result.layerMutations.contains { $0.fields.contains(.pointSize) })
            try layers.apply(result.layerMutations).get()
            program.finalizeLayerMutations(committing: true)
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: UInt64(index + 1),
                generation: UInt64(index + 1), definitions: layers.authoredLayerDefinitions,
                userValues: [target: .scalar(80)], timelineValues: [target: .scalar(90)],
                sceneScriptValues: layers.snapshot().authoredLayerValues).snapshot
            sizes.append(scalar(snapshot[target]?.value)); sources.append(snapshot[target]?.source.rawValue ?? "missing")
            if case let .string(value)? = snapshot[.text(layerID: 77, field: .content)]?.value { texts.append(value) }
            if held == nil { held = snapshot }
            try domain.publishLayerSnapshot(snapshot, descriptor: descriptor)
        }
        return ["bindings": program.bindings.count, "sizes": sizes, "texts": texts,
            "pointSizeDirty": dirty, "failures": failures, "sources": sources,
            "heldSize": scalar(held?[target]?.value)]
    }

    static func setterFiniteDomain() throws -> [[String: Any]] {
        try [0.0, 1025.0, Double.greatestFiniteMagnitude].map { value in
            let descriptor = setterDescriptor(), domain = try SceneScriptQuickJSDomain()
            try domain.configureLayerRuntimeFields(descriptor)
            let owner = try setterOwner(domain,
                "export function update(v){thisLayer.pointsize=\(value);return v;}")
            let result = setterEvaluate(owner), evaluation = try result.get()
            let layers = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [77])
            try layers.apply(evaluation.layerMutations).get()
            let target = SceneDynamicTarget.text(layerID: 77, field: .pointSize)
            let raw = scalar(layers.snapshot().authoredLayerValues[target])
            guard let rendered = SceneTextDescriptor.renderedPointSize(raw) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument("finite point size did not normalize")
            }
            let style = SceneTextDescriptor.parse(["pointsize": rendered])
            return ["raw": raw, "expectedRaw": value,
                "dirty": evaluation.layerMutations.first?.fields.contains(.pointSize) == true,
                "rendered": Double(style.pointSize), "renderFinite": style.pointSize.isFinite]
        }
    }

    static func setterRejections() throws -> [String: Any] {
        let attempts = ["thisLayer.pointsize=NaN;", "thisLayer.pointsize=Infinity;",
            "thisLayer.pointsize='72';", "thisScene.getLayerByID(88).pointsize=72;",
            "thisLayer.id=99;", "thisScene.createLayer({text:'bad',pointsize:1025});"]
        var codes: [String] = [], noMutations: [Bool] = [], observers: [String] = []
        for attempt in attempts {
            let domain = try SceneScriptQuickJSDomain()
            try domain.configureLayerRuntimeFields(setterDescriptor())
            let owner = try setterOwner(domain,
                "export function update(v){thisLayer.text='leak';thisLayer.pointsize=72;\(attempt)return v;}")
            let result = setterEvaluate(owner)
            codes.append(setterCode(result))
            noMutations.append(mwx_scene_quickjs_owner_layer_mutation_count(owner.handle) == 0)
            let observer = try setterOwner(domain,
                "export function update(v){return thisLayer.pointsize+'|'+thisLayer.text;}")
            if case let .string(value) = try setterEvaluate(observer).get().value { observers.append(value) }
        }
        return ["codes": codes, "noMutations": noMutations, "observed": observers]
    }

    static func setterPartialMerge() throws -> [String: Any] {
        let descriptor = setterDescriptor(), domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerRuntimeFields(descriptor)
        let first = try setterOwner(domain,
            "export function update(v){thisLayer.pointsize=72;return v;}")
        let later = try setterOwner(domain,
            "const f=engine.registerAsset('fonts/partial.ttf');export function update(v){thisLayer.text='partial';thisLayer.font=f;thisLayer.origin=new Vec3(3,4,0);return v;}")
        let a = try setterEvaluate(first).get().layerMutations
        let b = try setterEvaluate(later).get().layerMutations
        let merged = SceneScriptLayerMutation.coalescing(a + b)
        let layers = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [77])
        try layers.apply(merged).get()
        let value = layers.snapshot().authoredLayerValues[.text(layerID: 77, field: .pointSize)]
        return ["earlierRaw": a.first?.pointSize ?? -1, "laterUnwrittenRaw": b.first?.pointSize ?? -1,
            "laterPointSizeDirty": b.first?.fields.contains(.pointSize) == true,
            "mergedSize": merged.first?.pointSize ?? -1, "typedSize": scalar(value),
            "mergedFields": merged.first?.fields == [.pointSize, .text, .font, .origin]]
    }

    static func setterRestrictedOwners() throws -> [String: Any] {
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerRuntimeFields(setterDescriptor())
        let readonly = try SceneScriptValueOwner(domain: domain,
            source: "export function update(v){thisLayer.pointsize=72;return v;}",
            target: .layer(layerID: 77, field: .visibility), valueType: .bool,
            effectNames: [], generation: 30, budget: .default)
        let denied = readonly.evaluate(input: .bool(true), frame: setterFrame(1),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 30, interruptBudget: nil)
        let stale = try setterOwner(domain,
            "export function update(v){thisLayer.pointsize=72;return v;}")
        mwx_scene_quickjs_owner_invalidate(stale.handle)
        return ["valueOnly": setterCode(denied), "stale": setterCode(setterEvaluate(stale)),
            "valueOnlyMutations": mwx_scene_quickjs_owner_layer_mutation_count(readonly.handle),
            "staleMutations": mwx_scene_quickjs_owner_layer_mutation_count(stale.handle)]
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
        cls.binary = compile_vector_harness(Path(cls.temp_dir.name), HARNESS, "text-pointsize",
            extra_swift_sources=(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextDescriptor.swift",))
        cls.result = json.loads(subprocess.run([str(cls.binary)], check=True,
            capture_output=True, text=True).stdout)

    def test_exact_pointsize_owner_publishes_and_failures_stay_local(self) -> None:
        result = self.result
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

    def test_layer_handle_pointsize_reaches_typed_snapshot_and_current(self) -> None:
        for row in self.result["setterRoundTrips"]:
            self.assertEqual(row, {"bindings": 1, "sizes": [60, 72, 72],
                "texts": ["one", "two", "partial"], "pointSizeDirty": [True, True, False],
                "failures": 0, "sources": ["sceneScript"] * 3, "heldSize": 60})
        self.assertEqual(self.result["setterPartialMerge"], {"earlierRaw": 72,
            "laterUnwrittenRaw": 48, "laterPointSizeDirty": False,
            "mergedSize": 72, "typedSize": 72, "mergedFields": True})

    def test_setter_finite_raw_values_use_the_production_render_normalization(self) -> None:
        rows = self.result["setterFiniteDomain"]
        self.assertEqual([row["rendered"] for row in rows], [1, 1024, 1024])
        for row in rows:
            self.assertEqual(row["raw"], row["expectedRaw"])
            self.assertTrue(row["dirty"])
            self.assertTrue(row["renderFinite"])

    def test_invalid_setter_bundle_rolls_back_and_restricted_owners_stay_closed(self) -> None:
        self.assertEqual(self.result["setterRejections"], {"codes": ["exception"] * 6,
            "noMutations": [True] * 6, "observed": ["48|12:00"] * 6})
        self.assertEqual(self.result["setterRestrictedOwners"], {"valueOnly": "exception",
            "stale": "stale-owner", "valueOnlyMutations": 0, "staleMutations": 0})


if __name__ == "__main__":
    unittest.main()
