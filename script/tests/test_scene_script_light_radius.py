#!/usr/bin/env python3
"""Point/lpoint radius reaches the shared light snapshot through real scalar owners."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import scene_vector_vm_test_support as vm
from script.tests.test_scene_script_light_visibility import lighting_fixture


HARNESS = r'''
@main enum LightRadiusChecks {
    static let target = SceneDynamicTarget.layer(layerID: 16, field: .radius)
    static let seed = 24.0
    static let passthrough = "export function update(value) { return value; }"
    static let frame = SceneScriptFrameInput(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1 / 60,
        sceneTime: 2))

    static func descriptor(kind: String = "point", radius: Float? = Float(seed),
                           name: String = "own-lamp", hidden: Bool = false)
        -> SceneRenderDescriptor {
        var light = SceneRenderDescriptor.Layer(id: 16, layerIndex: 0,
            name: name, visible: true, originXYZ: [2, 3, 4], scaleXYZ: [1, 1, 1],
            alpha: 1, effects: [], contentKind: "pointLight")
        light.pointLight = .init(kind: kind, colorRGB: [1, 1, 1], intensity: 2,
            radius: radius, castsVolumetrics: false, castsShadow: true, isSolid: true)
        var scene = SceneRenderDescriptor(layers: [light])
        scene.lighting = .init(ambientColorRGB: nil, skylightColorRGB: nil)
        if hidden {
            scene.layers[0].parentID = 90
            scene.layers.append(.init(id: 90, layerIndex: 1, name: "hidden parent",
                visible: false, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                alpha: 1, effects: [], contentKind: "solid"))
        }
        return scene
    }

    static func document(kind: String = "point", source: String = passthrough,
                         key: String? = nil, input: String = "gain",
                         value: Any = seed, extra: [String: Any] = [:]) -> [String: Any] {
        var wrapper: [String: Any] = ["value": value, "script": source]
        if let key { wrapper["scriptproperties"] = [input: ["user": key, "value": 2.0]] }
        wrapper.merge(extra) { _, latest in latest }
        return ["objects": [["id": 16, "name": "independent light", "light": kind,
            "color": "1 1 1", "intensity": 2, "radius": wrapper]]]
    }

    static func bindings(_ root: [String: Any]) -> [SceneScriptBindingIR] {
        SceneScriptBindingIRParser.parse(document: root).bindings
    }

    static func altered(_ binding: SceneScriptBindingIR,
                        path: [SceneScriptBindingPathComponent]? = nil,
                        index: Int = 0, id: Int = 16,
                        kind: SceneScriptBindingOwner.Kind = .object,
                        user: String? = nil) -> SceneScriptBindingIR {
        .init(source: binding.source,
            owner: .init(kind: kind, objectIndex: index, objectID: id,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: path ?? binding.targetPath, properties: binding.properties,
            authoredValue: binding.authoredValue, valueType: binding.valueType,
            wrapperKeys: binding.wrapperKeys, userPropertyKey: user)
    }

    static func candidate(_ scene: SceneRenderDescriptor, _ scripts: [SceneScriptBindingIR],
                          properties: [SceneUserPropertyDefinition] = [],
                          timeline: Set<SceneDynamicTarget> = [],
                          excluded: Set<SceneDynamicTarget> = []) throws
        -> SceneScriptQuickJSProgramCandidate {
        try .compile(authoredDescriptor: scene, runtimeDescriptor: scene,
            scriptBindings: scripts, vectorProjection: SceneScriptVectorProgram.project(
                descriptor: scene, scriptBindings: scripts), userPropertyDefinitions: properties,
            timelineTargets: timeline, scalarExcludedTargets: excluded, stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 11)
    }

    static func snapshot(_ definitions: [SceneDynamicTargetDefinition],
                         script: [SceneDynamicTarget: SceneDynamicValue] = [:],
                         user: [SceneDynamicTarget: SceneDynamicValue] = [:],
                         index: UInt64 = 1) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: index, generation: 11,
            definitions: definitions, userValues: user, sceneScriptValues: script).snapshot
    }

    static func lights(_ scene: SceneRenderDescriptor, _ values: SceneDynamicSnapshot)
        -> SceneLightSnapshot {
        let byID = Dictionary(uniqueKeysWithValues: scene.layers.map { ($0.id, $0) })
        return .make(descriptor: scene,
            worldFramesByLayerID: SceneLayerWorldFrameResolver.compute(descriptor: scene, byID: byID),
            dynamicSnapshot: values)
    }

    static func active(_ scene: SceneRenderDescriptor, _ program: ScenePropertyBindingProgram,
                       _ owners: SceneScriptQuickJSProgramCandidate) -> Set<SceneDynamicTarget> {
        SceneDesktopWallpaperHost.activeLiveConsumerTargets(in: scene, propertyBindingProgram: program,
            resolvedMaterialExecutionCapabilities: .init(), soundPlaybackProgram: .init(),
            preparedStaticModelLayerIDs: [], preparedImageMaterialTargets: [],
            propertyVectorScriptProgram: owners.vectorProgram,
            sceneScriptScalarProgram: owners.scalarProgram, sceneScriptStringProgram: owners.stringProgram)
    }

    static func source(input: String, variant: Int) -> String {
        let local = ["initial", "baseRadius", "authoredDistance"][variant]
        let expression = ["\(local) * scriptProperties.\(input)",
            "scriptProperties.\(input) * \(local)",
            "(\(local) + \(local)) * (scriptProperties.\(input) / 2)"][variant]
        return """
        export var scriptProperties = createScriptProperties()
            .addSlider({name:'\(input)',value:2,min:0,max:4,integer:false}).finish();
        let \(local) = 0;
        export function init(value) { \(local) = value; }
        export function update(value) { return \(expression); }
        """
    }

    static func propertyFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (i, names) in [("distance", "gain", "point"),
                            ("reach", "multiplier", "lpoint"),
                            ("spread", "factor", "point")].enumerated() {
            let (key, input, kind) = names
            let scene = descriptor(kind: kind, name: "renamed-\(i)")
            let root = document(kind: kind, source: source(input: input, variant: i),
                key: key, input: input)
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
                key: ["type": "slider", "value": 2.0, "min": 0, "max": 4]])
            let compiled = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: root), catalog: catalog)
            let owners = try candidate(scene, bindings(root), properties: catalog.definitions)
            let program = owners.scalarProgram
            var live = ScenePropertyLiveUpdateState(program: compiled.program,
                effectiveValues: catalog.effectiveValues(overrides: [:]),
                activeConsumerTargets: active(scene, compiled.program, owners))
            let first = program.evaluate(inputs: [target: .scalar(seed)], frame: frame,
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let firstValues = snapshot(program.definitions, script: first.values)
            let firstLights = lights(scene, firstValues)
            let owner = program.bindings.first
            let applied = live.apply(.number(3), forPropertyKey: key)
            let second = program.evaluate(inputs: [target: .scalar(seed)], frame: frame,
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let secondLights = lights(scene, snapshot(program.definitions, script: second.values, index: 2))
            facts[key + "-complete-shared-owner"] = owners.constructionReport.isComplete
                && program.bindings.count == 1 && program.definitions.map(\.target) == [target]
                && compiled.diagnostics.isEmpty && compiled.program.instructions.count == 1
                && compiled.program.rebuildRequiredPropertyKeys.isEmpty
            facts[key + "-live-property-current-radius"] = applied && first.failures.isEmpty
                && second.failures.isEmpty && live.revision == 1 && program.bindings.first === owner
                && firstValues[target]?.source == .sceneScript
                && firstLights.point.first?.radius == 48 && secondLights.point.first?.radius == 72
                && firstLights.point.first?.radius == 48 && firstLights.point.first?.intensity == 2
            let unchanged = snapshot([], index: 3)
            facts[key + "-static-fallback-identical"] = lights(scene, unchanged).point.first?.radius == 24
                && lights(scene, snapshot(program.definitions)).point.first?.radius == 24
            let offApplied = live.apply(.number(0), forPropertyKey: key)
            let off = program.evaluate(inputs: [target: .scalar(seed)], frame: frame,
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let offValues = snapshot(program.definitions, script: off.values, index: 3)
            facts[key + "-scriptproperty-zero-is-off"] = offApplied && off.failures.isEmpty
                && offValues[target]?.value == .scalar(0) && offValues[target]?.source == .sceneScript
                && lights(scene, offValues).point.isEmpty && program.bindings.first === owner
        }
        let scene = descriptor(hidden: true)
        var root = document()
        var objects = root["objects"] as! [[String: Any]]
        objects[0]["radius"] = ["value": seed, "user": "distance"]
        root["objects"] = objects
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "distance": ["type": "slider", "value": 24, "min": -10, "max": 100]])
        let compiled = ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(root: root), catalog: catalog)
        let owners = try candidate(scene, [])
        let consumers = active(scene, compiled.program, owners)
        var live = ScenePropertyLiveUpdateState(program: compiled.program,
            effectiveValues: catalog.effectiveValues(overrides: [:]), activeConsumerTargets: consumers)
        let hidden = lights(scene, snapshot(compiled.program.definitions, user: live.userValues))
        let applied = live.apply(.number(60), forPropertyKey: "distance")
        let parent = SceneDynamicTarget.layer(layerID: 90, field: .visibility)
        let definitions = compiled.program.definitions + [.init(target: parent,
            valueType: .bool, authoredValue: .bool(false))]
        let shown = lights(scene, snapshot(definitions, script: [parent: .bool(true)], user: live.userValues))
        facts["hidden-property-retains-live-consumer"] = consumers.contains(target) && applied
            && hidden.point.isEmpty && shown.point.first?.radius == 60
        let offApplied = live.apply(.number(0), forPropertyKey: "distance")
        let off = snapshot(definitions, script: [parent: .bool(true)], user: live.userValues)
        facts["direct-property-zero-keeps-off-signal"] = offApplied
            && off[target]?.source == .userProperty && off[target]?.value == .scalar(0)
            && lights(scene, off).point.isEmpty
        facts["direct-property-zero-restores"] = live.apply(.number(60), forPropertyKey: "distance")
            && lights(scene, snapshot(definitions, script: [parent: .bool(true)],
                user: live.userValues)).point.first?.radius == 60
        let revision = live.revision
        facts["invalid-property-keeps-previous"] = !live.apply(.number(-1), forPropertyKey: "distance")
            && live.revision == revision && live.effectiveValues["distance"] == .number(60)
        let encoded = try JSONEncoder().encode(compiled.program)
        let cached = try JSONDecoder().decode(ScenePropertyBindingProgram.self, from: encoded)
        facts["cached-property-target-keeps-radius-identity"] = cached == compiled.program
            && cached.evaluate(effectiveValues: ["distance": .number(36)]).userValues[target] == .scalar(36)
        let old = SceneDynamicTarget.layer(layerID: 16, field: .intensity)
        facts["old-target-codable-preserved"] = try JSONDecoder().decode(SceneDynamicTarget.self,
            from: Data(#"{"layer":{"layerID":16,"field":"intensity"}}"#.utf8)) == old
        return facts
    }

    static func audioFacts() throws -> [String: Bool] {
        let source = """
        const bands = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
        export function update(value) { return 24 + bands.average[0] * 32; }
        """
        let scene = descriptor()
        let program = try candidate(scene, bindings(document(source: source))).scalarProgram
        var radii: [Float] = [], failures = 0
        let owner = program.bindings.first
        for (index, magnitude) in [Float(0), 0.5, 1, 0].enumerated() {
            let audio = SceneAudioSpectrumSnapshot(left: Array(repeating: magnitude, count: 16),
                right: Array(repeating: magnitude, count: 16), left64: [], right64: [],
                generation: UInt64(index + 1))
            let result = program.evaluate(inputs: [target: .scalar(seed)], frame: frame, audioSpectrum: audio)
            failures += result.failures.count
            if let radius = lights(scene, snapshot(program.definitions, script: result.values,
                index: UInt64(index))).point.first?.radius { radii.append(radius) }
        }
        return ["audio-current-next-frame-same-owner": failures == 0 && radii == [24, 40, 56, 24]
            && program.hasAudioConsumers && program.bindings.first === owner]
    }

    static func admissionFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let scene = descriptor()
        var cases: [(String, SceneRenderDescriptor, [SceneScriptBindingIR], Set<SceneDynamicTarget>)] = []
        for (name, extra) in [("unknown-wrapper", ["extra": true]),
                              ("animation", ["animation": ["id": 1]]),
                              ("outer-user", ["user": "distance"])] {
            cases.append((name, scene, bindings(document(extra: extra)), []))
        }
        for (name, value) in [("bool", true as Any), ("text", "24" as Any),
                              ("null", NSNull() as Any),
                              ("negative", -1 as Any), ("overflow", 1e39 as Any)] {
            cases.append((name, scene, bindings(document(value: value)), []))
        }
        let valid = bindings(document())
        cases += [("duplicate", scene, valid + valid, []), ("timeline", scene, valid, [target]),
                  ("seed-mismatch", descriptor(radius: 25), valid, []),
                  ("missing-radius", descriptor(radius: nil), valid, []),
                  ("wrong-owner-index", scene, [altered(valid[0], index: 1)], []),
                  ("wrong-owner-id", scene, [altered(valid[0], id: 17)], []),
                  ("wrong-owner-kind", scene, [altered(valid[0], kind: .pass)], []),
                  ("nested-path", scene, [altered(valid[0], path: [.key("objects"),
                    .index(0), .key("nested"), .key("radius")])], []),
                  ("wrong-field", scene, [altered(valid[0], path: [.key("objects"),
                    .index(0), .key("distance")])], []),
                  ("forged-outer-user", scene, [altered(valid[0], user: "distance")], []),
                  ("invalid-prepared-kind", descriptor(kind: "lspot"), valid, [])]
        for kind in ["lspot", "ldirectional", "image", "invalid"] {
            var input = scene
            input.layers[0].pointLight = nil
            input.layers[0].contentKind = kind
            cases.append((kind, input, bindings(document(kind: kind)), []))
            let propertyRoot: [String: Any] = ["objects": [["id": 16, "light": kind,
                "radius": ["user": "distance", "value": seed]]]]
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
                "distance": ["type": "slider", "value": 24, "min": 1, "max": 100]])
            let compiled = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: propertyRoot), catalog: catalog)
            facts[kind + "-property-not-radius"] = compiled.program.definitions.isEmpty
                && !SceneLightSnapshot.liveConsumerTargets(descriptor: input).contains(target)
        }
        for (name, input, scripts, timeline) in cases {
            let result = try candidate(input, scripts, timeline: timeline)
            facts[name + "-not-admitted"] = result.scalarProgram.bindings.isEmpty
                && result.scalarProgram.definitions.isEmpty
                && result.constructionReport.expectedScalarTargets.isEmpty
        }
        for (name, property) in [("bool", ["type": "bool", "value": true]),
                                  ("text", ["type": "textinput", "value": "24"])] {
            let root: [String: Any] = ["objects": [["id": 16, "light": "point",
                "radius": ["user": "distance", "value": seed]]]]
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: ["distance": property])
            let compiled = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: root), catalog: catalog)
            facts[name + "-property-kind-rejected"] = compiled.program.instructions.isEmpty
        }
        let excluded = try candidate(scene, valid, excluded: [target])
        facts["excluded-owner-not-admitted"] = excluded.scalarProgram.bindings.isEmpty
            && excluded.scalarProgram.definitions.isEmpty
        return facts
    }

    static func numericFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let definition = SceneDynamicTargetDefinition(target: target, valueType: .scalar,
            authoredValue: .scalar(seed))
        for (i, value) in [-1, Double.nan, .infinity, -.infinity, 1e39].enumerated() {
            let resolved = snapshot([definition], script: [target: .scalar(value)], user: [target: .scalar(36)])
            facts["invalid-snapshot-\(i)-keeps-user"] = resolved[target]?.value == .scalar(36)
                && resolved[target]?.source == .userProperty
                && lights(descriptor(), resolved).point.first?.radius == 36
            facts["invalid-direct-property-\(i)"] = !definition.acceptsUserPropertyValue(.scalar(value))
        }
        for (i, expression) in ["-1", "1e39", "NaN", "Infinity"].enumerated() {
            let source = "export function update(value) { return \(expression); }"
            var scene = descriptor()
            scene.layers.append(.init(id: 17, layerIndex: 1, name: "healthy peer",
                visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                alpha: 0.25, effects: []))
            var root = document(source: source)
            var objects = root["objects"] as! [[String: Any]]
            objects.append(["id": 17, "image": "models/independent-peer-\(i).json",
                "alpha": ["value": 0.25,
                    "script": "export function update(value) { return 0.5; }"]])
            root["objects"] = objects
            let program = try candidate(scene, bindings(root)).scalarProgram
            let peer = SceneDynamicTarget.layer(layerID: 17, field: .alpha)
            let result = program.evaluate(inputs: [target: .scalar(seed), peer: .scalar(0.25)], frame: frame)
            let fallback = snapshot(program.definitions, script: result.values, user: [target: .scalar(36)])
            facts["invalid-vm-output-\(i)-local-fallback"] = result.failures[target]?.code == "bad-return"
                && result.values[target] == nil && fallback[target]?.source == .userProperty
                && lights(scene, fallback).point.first?.radius == 36
                && result.failures.count == 1 && result.values[peer] == .scalar(0.5)
        }
        for (i, value) in [Double(Float.leastNonzeroMagnitude), 0.25, 1,
                            Double(Float.greatestFiniteMagnitude)].enumerated() {
            let program = try candidate(descriptor(radius: Float(value)), bindings(document(value: value))).scalarProgram
            let result = program.evaluate(inputs: [target: .scalar(value)], frame: frame)
            facts["valid-radius-\(i)"] = result.failures.isEmpty && program.bindings.count == 1
                && lights(descriptor(radius: Float(value)), snapshot(program.definitions,
                    script: result.values)).point.first?.radius == Float(value)
        }
        return facts
    }

    static func zeroFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (i, value) in [0.0, -0.0, Double.leastNonzeroMagnitude].enumerated() {
            let scene = descriptor(radius: Float(value))
            let program = try candidate(scene, bindings(document(value: value))).scalarProgram
            let result = program.evaluate(inputs: [target: .scalar(value)], frame: frame)
            let values = snapshot(program.definitions, script: result.values, user: [target: .scalar(36)])
            facts["zero-seed-and-quantization-\(i)"] = program.bindings.count == 1
                && result.failures.isEmpty && values[target]?.value == .scalar(value)
                && values[target]?.source == .sceneScript && lights(scene, values).point.isEmpty
                && SceneDynamicLayerValues.lightRadius(layerID: 16, authoredValue: 24,
                    snapshot: values) == 0
        }
        var scene = descriptor(radius: 0)
        var peer = SceneRenderDescriptor.Layer(id: 17, layerIndex: 1, name: "other lamp",
            visible: true, originXYZ: [9, 8, 7], scaleXYZ: [1, 1, 1], alpha: 1,
            effects: [], contentKind: "pointLight")
        peer.pointLight = .init(kind: "point", colorRGB: [0.25, 0.5, 1], intensity: 3,
            radius: 48, castsVolumetrics: false, castsShadow: false, isSolid: true)
        scene.layers.append(peer)
        let source = """
        let step = 0;
        export function update(value) { return [0, 32, 0, 64][step++]; }
        """
        let program = try candidate(scene, bindings(document(source: source, value: 0))).scalarProgram
        let owner = program.bindings.first
        var ids: [[Int]] = [], radii: [Float?] = [], previous: SceneLightSnapshot?
        var failures = 0
        for index in 0..<4 {
            let result = program.evaluate(inputs: [target: .scalar(0)], frame: frame)
            failures += result.failures.count
            let values = snapshot(program.definitions, script: result.values, index: UInt64(index))
            let current = lights(scene, values)
            ids.append(current.point.compactMap(\.layerID))
            radii.append(current.point.first(where: { $0.layerID == 16 })?.radius)
            if index == 0 { previous = current }
        }
        facts["zero-seed-restores-and-disables-next-frame"] = failures == 0
            && program.bindings.first === owner && ids == [[17], [16, 17], [17], [16, 17]]
            && radii == [nil, 32, nil, 64] && previous?.point.compactMap(\.layerID) == [17]
            && previous?.point.first?.radius == 48 && previous?.point.first?.intensity == 3
            && SceneLightSnapshot.liveConsumerTargets(descriptor: scene).contains(target)
        return facts
    }

    static func main() throws {
        var facts = try propertyFacts()
        facts.merge(try audioFacts()) { _, latest in latest }
        facts.merge(try admissionFacts()) { _, latest in latest }
        facts.merge(try numericFacts()) { _, latest in latest }
        facts.merge(try zeroFacts()) { _, latest in latest }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneScriptLightRadiusTests(unittest.TestCase):
    def test_real_scalar_property_audio_and_snapshot_radius(self) -> None:
        evidence = os.environ.get("MWX_LIGHT_RADIUS_EVIDENCE")
        with tempfile.TemporaryDirectory(prefix="mwx-light-radius-") as temporary:
            work = Path(evidence) if evidence else Path(temporary)
            work.mkdir(parents=True, exist_ok=True)
            preamble, extra = lighting_fixture(work)
            extra += (vm.SCENE / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",)
            inputs = list(dict.fromkeys([*vm.SWIFT_SOURCES, *extra, *vm.C_SOURCES,
                Path(vm.__file__), Path(__file__),
                Path(lighting_fixture.__code__.co_filename),
                vm.SCENE / "Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift",
                vm.SCENE / "Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift"]))
            before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
            binary = vm.compile_vector_harness(work, HARNESS, "light-radius",
                extra_swift_sources=extra, preamble=preamble, whole_module_optimization=True)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            (work / "stdout.json").write_text(result.stdout)
            (work / "stderr.log").write_text(result.stderr)
            after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
            (work / "inputs.json").write_text(json.dumps({"before": before, "after": after,
                "harnessSHA256": hashlib.sha256((preamble + HARNESS).encode()).hexdigest(),
                "exitCode": result.returncode}, indent=2) + "\n")
            self.assertEqual(before, after, "source changed during radius gate")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            self.assertTrue(facts)
            self.assertEqual([key for key, value in facts.items() if value is not True], [])


if __name__ == "__main__":
    unittest.main()
