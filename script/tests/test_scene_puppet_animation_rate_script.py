#!/usr/bin/env python3
"""Authored nested Number owners drive the existing Puppet cadence consumer."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import ROOT, compile_vector_harness
from .test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES as PUPPET_SOURCES


# The shared VM fixture supplies the real parser, ScalarProgram, value owner,
# typed resolver and C VM. These are the existing animation sampler/runtime,
# rather than a replacement clock or an expectation-shaped playback stub.
EXTRA_SWIFT_SOURCES = tuple(dict.fromkeys([
    *PUPPET_SOURCES,
    SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift",
]))

HARNESS = r'''
struct RateFixture {
    let document: [String: Any]
    let descriptor: SceneRenderDescriptor
    let bindings: [SceneScriptBindingIR]

    init(_ objects: [[String: Any]]) {
        document = ["objects": objects]
        bindings = SceneScriptBindingIRParser.parse(document: document).bindings
        // The external descriptor carrier has no independent parsing rules:
        // animation metadata and binding IR both consume this authored JSON.
        descriptor = .init(layers: objects.enumerated().map { index, object in
            .init(id: object["id"] as! Int, layerIndex: index,
                name: object["name"] as? String, visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [],
                puppetMeshPath: object["model"] as? String,
                puppetAnimationLayers: ScenePuppetAnimationLayer.parse(object["animationlayers"]))
        })
    }
}

@main enum Harness {
    static let target = ScenePuppetAnimationPropertyTarget.rate(layerID: 42, animationLayerID: 91)
    static let sibling = ScenePuppetAnimationPropertyTarget.rate(layerID: 42, animationLayerID: 208)
    static let foreign = ScenePuppetAnimationPropertyTarget.rate(layerID: 43, animationLayerID: 91)
    static let identity = ScenePuppetAnimationIdentity(layerID: 42,
        animationLayerIndex: 0, animationLayerID: 91)

    static func frame(_ time: Double) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1, sceneTime: time))
    }
    static func authored(_ id: Int, name: String, source: String? = nil,
                         seed: Any = 1.0, properties: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["id": id, "animation": id + 1000,
            "name": name, "visible": true, "rate": seed, "blend": 1.0,
            "additive": true, "blendin": false, "blendout": false, "blendtime": 0.0]
        if let source {
            var wrapper: [String: Any] = ["value": seed, "script": source]
            if !properties.isEmpty { wrapper["scriptproperties"] = properties }
            result["rate"] = wrapper
        }
        return result
    }
    static func fixture(_ source: String, renamed: Bool = false) -> RateFixture {
        let names = renamed ? ["Renamed sweep", "Other arc"] : ["Primary motion", "Side motion"]
        let path = renamed ? "models/renamed-resource.json" : "models/original-resource.json"
        return RateFixture((42...43).map { parent in
            let layers = [91, 208].enumerated().map { index, id in
                authored(id, name: names[index], source: source,
                    properties: ["parent": parent, "name": names[index],
                        "rate": Double(parent - 40) + Double(index) / 2])
            }
            return ["id": parent, "name": "parent-\(parent)", "model": path,
                "animationlayers": layers + [authored(307, name: "Static peer", seed: 1.25)]]
        })
    }
    static func single(_ source: String, peer: String? = nil) -> RateFixture {
        var clips = [authored(91, name: "Primary motion", source: source)]
        if let peer { clips.append(authored(208, name: "Healthy peer", source: peer)) }
        return RateFixture([["id": 42, "name": "parent", "model": "models/own.json",
            "animationlayers": clips]])
    }
    static func runtime(_ fixture: RateFixture, initialize: Bool = true) throws -> ScenePuppetAnimationPlaybackRuntime {
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        for layer in fixture.descriptor.layers {
            let clips = layer.puppetAnimationLayers.map { entry in
                ScenePuppetAnimationSelection.Clip(layer: entry,
                    animation: .init(id: entry.animationID!, name: entry.name!, mode: "loop",
                        framesPerSecond: 10, frameCount: 1000,
                        transformsByBone: [], alphaByBone: nil))
            }
            try runtime.register(layerID: layer.id,
                selection: .init(clips: clips, composition: .layered),
                authoredLayers: layer.puppetAnimationLayers).get()
        }
        if initialize {
            _ = runtime.advance(frameIndex: 0, sceneTime: 0, dynamicValues: .empty(frameIndex: 0))
        }
        return runtime
    }
    static func prepared(_ fixture: RateFixture) throws
        -> (SceneScriptQuickJSDomain, SceneScriptScalarProgram, ScenePuppetAnimationPlaybackRuntime) {
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(fixture.descriptor)
        try domain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: fixture.descriptor)
        let program = SceneScriptScalarProgram.compile(domain: domain,
            descriptor: fixture.descriptor, scriptBindings: fixture.bindings, generation: 1)
        let playback = try runtime(fixture)
        try domain.publishPuppetAnimationSnapshot(playback.snapshots())
        return (domain, program, playback)
    }
    static func resolve(_ definitions: [SceneDynamicTargetDefinition],
                        _ values: [SceneDynamicTarget: SceneDynamicValue], _ index: UInt64)
        -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: index, generation: 1,
            definitions: definitions, sceneScriptValues: values).snapshot
    }
    static func number(_ value: SceneDynamicValue?) -> Double {
        guard case let .scalar(number)? = value else { return -999 }
        return number
    }
    static func state(_ playback: ScenePuppetAnimationPlaybackRuntime,
                      parent: Int = 42, id: Int = 91) -> [Double] {
        let value = playback.snapshots().first {
            $0.identity.layerID == parent && $0.identity.animationLayerID == id
        }!
        return [value.currentFrame, value.rate]
    }
    static func command(_ action: ScenePuppetAnimationCommand.Action, _ epoch: UInt64)
        -> ScenePuppetAnimationCommand {
        .init(identity: identity, action: action, callbackEpoch: epoch, ordinal: 0)
    }
    static func mutate(_ value: SceneScriptBindingIR,
                       owner: SceneScriptBindingOwner? = nil,
                       path: [SceneScriptBindingPathComponent]? = nil,
                       wrapper: [String]? = nil, seed: SceneJSONValue? = nil,
                       type: SceneScriptBindingValueType? = nil) -> SceneScriptBindingIR {
        .init(source: value.source, owner: owner ?? value.owner,
            targetPath: path ?? value.targetPath, properties: value.properties,
            authoredValue: seed ?? value.authoredValue, valueType: type ?? value.valueType,
            wrapperKeys: wrapper ?? value.wrapperKeys, userPropertyKey: value.userPropertyKey)
    }
    static func qualification() -> [String: Any] {
        let input = fixture("export function update(value){return value;}")
        let first = input.bindings.first { $0.owner.objectID == 42 && $0.owner.animationLayerID == 91 }!
        let projections: ([SceneScriptBindingIR], SceneRenderDescriptor) -> Set<SceneDynamicTarget> = {
            SceneScriptScalarProgram.projectedTargets(descriptor: $1, scriptBindings: $0)
        }
        var rejected: [String: Bool] = [:]
        var wrongParent = first.owner; wrongParent = .init(kind: wrongParent.kind,
            objectIndex: wrongParent.objectIndex, objectID: 999, effectIndex: nil,
            effectID: nil, passIndex: nil, passID: nil,
            animationLayerIndex: wrongParent.animationLayerIndex,
            animationLayerID: wrongParent.animationLayerID)
        var wrongIndex = first.owner; wrongIndex.animationLayerIndex = 1
        var wrongID = first.owner; wrongID.animationLayerID = 208
        let wrongKind = SceneScriptBindingOwner(kind: .object,
            objectIndex: 0, objectID: 42, effectIndex: nil, effectID: nil,
            passIndex: nil, passID: nil, animationLayerIndex: 0, animationLayerID: 91)
        let wrongObjectIndex = SceneScriptBindingOwner(kind: .animationLayer,
            objectIndex: 1, objectID: 42, effectIndex: nil, effectID: nil,
            passIndex: nil, passID: nil, animationLayerIndex: 0, animationLayerID: 91)
        let cases: [(String, SceneScriptBindingIR)] = [
            ("parentID", mutate(first, owner: wrongParent)),
            ("objectIndex", mutate(first, owner: wrongObjectIndex)),
            ("animationIndex", mutate(first, owner: wrongIndex)),
            ("animationID", mutate(first, owner: wrongID)),
            ("ownerKind", mutate(first, owner: wrongKind)),
            ("path", mutate(first, path: [.key("objects"), .index(0),
                .key("animationlayers"), .index(1), .key("rate")])),
            ("field", mutate(first, path: [.key("objects"), .index(0),
                .key("animationlayers"), .index(0), .key("blend")])),
            ("wrapper", mutate(first, wrapper: ["extra", "script", "scriptproperties", "value"])),
            ("seed", mutate(first, seed: .number(2))),
            ("type", mutate(first, seed: .string("1"), type: .string)),
        ]
        for (name, candidate) in cases {
            rejected[name] = projections([candidate], input.descriptor).isEmpty
        }
        var objects = input.document["objects"] as! [[String: Any]]
        var layers = objects[0]["animationlayers"] as! [[String: Any]]
        layers[1]["id"] = 91; objects[0]["animationlayers"] = layers
        let duplicated = RateFixture(objects)
        let duplicateIDs = projections(duplicated.bindings, duplicated.descriptor)
        var noFlag = input.descriptor
        noFlag.layers[0].puppetAnimationLayers[0].hasRateScript = nil
        rejected["unpreparedScript"] = projections([first], noFlag).isEmpty
        for invalidSeed in [-1.0, 1e100] {
            let invalid = RateFixture([["id": 42, "name": "parent",
                "animationlayers": [authored(91, name: "invalid", source: first.source,
                    seed: invalidSeed)]]])
            rejected["authoredSeed\(invalidSeed)"] = projections(invalid.bindings, invalid.descriptor).isEmpty
        }
        let targets = projections(input.bindings, input.descriptor)
        return ["count": targets.count, "bindingCount": input.bindings.count,
            "rejected": rejected,
            "duplicateWrapperLocal": projections(input.bindings + [first], input.descriptor)
                == targets.subtracting([target]),
            "duplicateIDLocal": duplicateIDs.count == 2
                && duplicateIDs.allSatisfy { if case .scriptInstanceProperty(43, _) = $0 { true } else { false } },
            "staticNeighborsAbsent": !targets.contains(ScenePuppetAnimationPropertyTarget.rate(
                layerID: 42, animationLayerID: 307))
                && input.descriptor.layers[0].puppetAnimationLayers[2].hasRateScript != true,
            "parserPath": first.targetPath == [.key("objects"), .index(0),
                .key("animationlayers"), .index(0), .key("rate")],
            "parserIdentity": first.owner.kind == .animationLayer
                && first.owner.objectID == 42 && first.owner.animationLayerIndex == 0
                && first.owner.animationLayerID == 91]
    }
    static func variants() throws -> [[String: Any]] {
        var reports: [[String: Any]] = []
        for renamed in [false, true] {
            var source = """
            export var scriptProperties={parent:0,name:'',rate:0};
            const resource=engine.registerAsset('fixtures/original.json');
            export function update(value){const motion=thisObject;
              if(thisLayer.id!==scriptProperties.parent||motion.name!==scriptProperties.name
                ||motion.frameCount!==1000||motion.fps!==10)throw Error('nested identity');
              if(thisLayer.getAnimationLayer(motion.name).getFrame()!==motion.getFrame())
                throw Error('nested handle');return scriptProperties.rate;}
            """
            if renamed {
                source = source.replacingOccurrences(of: "motion", with: "animation")
                    .replacingOccurrences(of: "resource", with: "asset")
                    .replacingOccurrences(of: "original.json", with: "renamed.json")
                    .replacingOccurrences(of: "return scriptProperties.rate;",
                        with: "return (scriptProperties.rate*4)/2/2;")
            }
            let input = fixture(source, renamed: renamed)
            let (domain, program, playback) = try prepared(input)
            let result = program.evaluate(inputs: Dictionary(uniqueKeysWithValues:
                program.definitions.map { ($0.target, $0.authoredValue) }), frame: frame(0))
            let staticTarget = ScenePuppetAnimationPropertyTarget.rate(layerID: 42, animationLayerID: 307)
            // A typed value alone cannot upgrade an authored static neighbour
            // into a prepared script consumer.
            let accepted = resolve(program.definitions + [.init(target: staticTarget,
                valueType: .scalar, authoredValue: .scalar(1.25))],
                result.values.merging([staticTarget: .scalar(99)]) { _, new in new }, 1)
            _ = playback.advance(frameIndex: 1, sceneTime: 1, dynamicValues: accepted)
            try domain.publishPuppetAnimationSnapshot(playback.snapshots())
            reports.append(["bindings": program.bindings.count, "failures": result.failures.count,
                "failureDetails": result.failures.map { String(describing: $0.key) + ": " + String(describing: $0.value) },
                "values": [number(result.values[target]), number(result.values[sibling]),
                    number(result.values[foreign]), number(result.values[
                        ScenePuppetAnimationPropertyTarget.rate(layerID: 43, animationLayerID: 208)])],
                "poses": [state(playback), state(playback, id: 208), state(playback, parent: 43),
                    state(playback, parent: 43, id: 208), state(playback, id: 307)],
                "source": accepted[target]?.source.rawValue ?? "missing"])
        }
        return reports
    }
    static func cadence() throws -> [String: Any] {
        let source = """
        let index=0;const speeds=[2,0,3,0.5];
        export function update(value){return speeds[index++];}
        """
        let (domain, program, playback) = try prepared(single(source))
        var poses: [[Double]] = []
        _ = playback.advance(frameIndex: 1, sceneTime: 1, dynamicValues: .empty(frameIndex: 1))
        poses.append(state(playback))
        func evaluate(_ time: Double) -> SceneDynamicSnapshot {
            let result = program.evaluate(inputs: [target: .scalar(1)], frame: frame(time))
            precondition(result.failures.isEmpty && result.values[target] != nil)
            return resolve(program.definitions, result.values, UInt64(time))
        }
        var accepted = evaluate(1)
        _ = playback.advance(frameIndex: 1, sceneTime: 999, dynamicValues: accepted)
        poses.append(state(playback))
        _ = playback.advance(frameIndex: 2, sceneTime: 2, dynamicValues: accepted)
        poses.append(state(playback)); try domain.publishPuppetAnimationSnapshot(playback.snapshots())
        accepted = evaluate(2)
        _ = playback.advance(frameIndex: 2, sceneTime: 999, dynamicValues: accepted)
        poses.append(state(playback))
        _ = playback.advance(frameIndex: 3, sceneTime: 3, dynamicValues: accepted)
        poses.append(state(playback))
        _ = playback.advance(frameIndex: 4, sceneTime: 4, dynamicValues: .empty(frameIndex: 4))
        poses.append(state(playback)); try domain.publishPuppetAnimationSnapshot(playback.snapshots())
        accepted = evaluate(4)
        _ = playback.advance(frameIndex: 5, sceneTime: 5, dynamicValues: accepted)
        poses.append(state(playback)); try domain.publishPuppetAnimationSnapshot(playback.snapshots())
        accepted = evaluate(5)
        _ = playback.advance(frameIndex: 6, sceneTime: 6, dynamicValues: accepted)
        poses.append(state(playback))
        let changed = resolve(program.definitions, [target: .scalar(2)], 7)
        try playback.apply([command(.pause, 100)], frameIndex: 6).get()
        _ = playback.advance(frameIndex: 7, sceneTime: 7, dynamicValues: changed)
        poses.append(state(playback))
        try playback.apply([command(.play, 101)], frameIndex: 7).get()
        _ = playback.advance(frameIndex: 8, sceneTime: 8, dynamicValues: changed)
        poses.append(state(playback))
        try playback.apply([command(.setVisible(false), 102)], frameIndex: 8).get()
        _ = playback.advance(frameIndex: 9, sceneTime: 9,
            dynamicValues: resolve(program.definitions, [target: .scalar(3)], 9))
        poses.append(state(playback))
        try playback.apply([command(.setVisible(true), 103)], frameIndex: 9).get()
        _ = playback.advance(frameIndex: 10, sceneTime: 10, dynamicValues: .empty(frameIndex: 10))
        poses.append(state(playback))
        try playback.apply([command(.setFrame(7), 104)], frameIndex: 10).get()
        _ = playback.advance(frameIndex: 11, sceneTime: 11, dynamicValues: changed)
        poses.append(state(playback))
        let last = playback.advance(frameIndex: 11, sceneTime: 777,
            dynamicValues: resolve(program.definitions, [target: .scalar(99)], 11))
        let stale = playback.advance(frameIndex: 10, sceneTime: 999,
            dynamicValues: resolve(program.definitions, [target: .scalar(99)], 10))
        return ["poses": poses, "sameAndStale": last.animationSnapshots == stale.animationSnapshots
            && state(playback) == poses.last!]
    }
    static func failures() throws -> [[String: Any]] {
        var output: [[String: Any]] = []
        let invalid = ["return -1;", "return NaN;", "return Infinity;", "return 1e100;",
            "return 'not-a-number';", "throw Error('own failure');",
            "thisLayer.alpha=0.25;return 2;", "thisLayer.origin=new Vec3(1,2,3);return 2;"]
        for statement in invalid {
            let input = single("export function update(v){thisObject.rate=4;\(statement)}",
                peer: "export function update(v){return 2.5;}")
            let (_, program, playback) = try prepared(input)
            let result = program.evaluate(inputs: [target: .scalar(1), sibling: .scalar(1)], frame: frame(0))
            let snapshot = resolve(program.definitions, result.values, 1)
            _ = playback.advance(frameIndex: 1, sceneTime: 1, dynamicValues: snapshot)
            let owner = program.bindings.first { $0.target == target }!
            output.append(["code": result.failures[target]?.code ?? "missing",
                "invalidAbsent": result.values[target] == nil,
                "peerValue": number(result.values[sibling]),
                "failedCommandsAbsent": mwx_scene_quickjs_owner_puppet_animation_command_count(owner.handle) == 0,
                "bundleAbsent": !result.ownerEffects.contains { $0.ownerTarget == target },
                "parentWritesAbsent": result.layerMutations.isEmpty,
                "fallbackSource": snapshot[target]?.source.rawValue ?? "missing",
                "poses": [state(playback), state(playback, id: 208)]])
        }
        return output
    }
    static func acceptedSources() throws -> [String: Any] {
        let (domain, program, playback) = try prepared(single("""
        let count=0;export function update(value){if(count++===0)return 2;return -1;}
        """))
        let first = program.evaluate(inputs: [target: .scalar(1)], frame: frame(0))
        _ = playback.advance(frameIndex: 1, sceneTime: 1,
            dynamicValues: resolve(program.definitions, first.values, 1))
        var poses = [state(playback)]
        try domain.publishPuppetAnimationSnapshot(playback.snapshots())
        let failed = program.evaluate(inputs: [target: .scalar(2)], frame: frame(1))
        let authoredFallback = resolve(program.definitions, failed.values, 2)
        let user = SceneDynamicSnapshotResolver().resolve(frameIndex: 4, generation: 1,
            definitions: program.definitions, userValues: [target: .scalar(99)]).snapshot
        let timeline = SceneDynamicSnapshotResolver().resolve(frameIndex: 5, generation: 1,
            definitions: program.definitions, timelineValues: [target: .scalar(99)]).snapshot
        let badNegative = resolve(program.definitions, [target: .scalar(-1)], 6)
        let badFloat = resolve(program.definitions, [target: .scalar(1e100)], 7)
        let wrongOwner = resolve(program.definitions + [.init(target: foreign,
            valueType: .scalar, authoredValue: .scalar(1))], [foreign: .scalar(99)], 8)
        let snapshots = [authoredFallback, .empty(frameIndex: 3), user, timeline,
            badNegative, badFloat, wrongOwner]
        for (index, snapshot) in snapshots.enumerated() {
            _ = playback.advance(frameIndex: UInt64(index + 2), sceneTime: Double(index + 2),
                dynamicValues: snapshot)
            poses.append(state(playback))
        }
        try playback.apply([command(.setRate(3), 100)], frameIndex: 8).get()
        _ = playback.advance(frameIndex: 9, sceneTime: 9, dynamicValues: authoredFallback)
        poses.append(state(playback))
        _ = playback.advance(frameIndex: 10, sceneTime: 10,
            dynamicValues: resolve(program.definitions, [target: .scalar(2)], 10))
        poses.append(state(playback))
        return ["poses": poses, "failure": failed.values[target] == nil && failed.failures[target] != nil,
            "sources": [authoredFallback, user, timeline].map { $0[target]?.source.rawValue ?? "missing" }]
    }
    static func firstCadenceAndLateParent() throws -> [String: Any] {
        let input = single("export function update(value){return 2;}")
        let playback = try runtime(input, initialize: false)
        let definitions = SceneScriptScalarProgram.projectedDefinitions(
            descriptor: input.descriptor, scriptBindings: input.bindings)
        let value = resolve(definitions, [target: .scalar(2)], 1)
        _ = playback.advance(frameIndex: 1, sceneTime: 5, dynamicValues: value)
        let first = state(playback)
        let layer = input.descriptor.layers[0].puppetAnimationLayers[0]
        try playback.register(layerID: 43, selection: .init(clips: [.init(layer: layer,
            animation: .init(id: layer.animationID!, name: layer.name!, mode: "loop",
                framesPerSecond: 10, frameCount: 1000,
                transformsByBone: [], alphaByBone: nil))], composition: .singleAbsolute),
            authoredLayers: [layer]).get()
        let bothDefinitions = definitions + [.init(target: foreign, valueType: .scalar,
            authoredValue: .scalar(1))]
        _ = playback.advance(frameIndex: 1, sceneTime: 999,
            dynamicValues: resolve(bothDefinitions, [target: .scalar(99), foreign: .scalar(3)], 1))
        let same = [state(playback), state(playback, parent: 43)]
        _ = playback.advance(frameIndex: 2, sceneTime: 6,
            dynamicValues: resolve(bothDefinitions, [target: .scalar(2), foreign: .scalar(3)], 2))
        return ["first": first, "same": same,
            "next": [state(playback), state(playback, parent: 43)]]
    }
    static func numericVisibility() throws -> [[String: Any]] {
        var output: [[String: Any]] = []
        for (body, rate) in [("return 0;", 0.0), ("thisObject.visible=false;return 2;", 2.0)] {
            let (domain, program, playback) = try prepared(single("export function update(v){\(body)}"))
            let result = program.evaluate(inputs: [target: .scalar(1)], frame: frame(0))
            let commands = result.ownerEffects.flatMap(\.puppetAnimationCommands)
            try playback.validate(commands, sourceLayerID: 42, sourceAnimationLayerID: 91, frameIndex: 0).get()
            try playback.apply(commands, frameIndex: 0).get()
            program.finalizeLayerMutations(committing: true)
            let next = playback.advance(frameIndex: 1, sceneTime: 1,
                dynamicValues: resolve(program.definitions, result.values, 1))
            try domain.publishPuppetAnimationSnapshot(playback.snapshots())
            output.append(["value": number(result.values[target]), "expected": rate,
                "visible": playback.snapshots()[0].visible,
                "samplePresent": next[42]!.samples[0] != nil,
                "commands": commands.count, "state": state(playback)])
        }
        return output
    }
    static func scalarEvents() throws -> [String: Any] {
        let (domain, program, playback) = try prepared(single("""
        export function animationEvent(event,value){
          if(typeof value!=='number')throw Error('numeric event input');
          if(event.name==='set')return value+1.5;return undefined;}
        export function update(value){return value;}
        """))
        try domain.publishPuppetAnimationEvents([
            .init(identity: identity, sequence: 1, name: "set", frame: 1),
            .init(identity: identity, sequence: 2, name: "keep", frame: 2)], failures: [:])
        let result = program.evaluate(inputs: [target: .scalar(1)], frame: frame(0))
        program.finalizeLayerMutations(committing: true)
        _ = playback.advance(frameIndex: 1, sceneTime: 1,
            dynamicValues: resolve(program.definitions, result.values, 1))
        var rejected: [Bool] = []
        for expression in ["true", "NaN", "Infinity", "'2'"] {
            let (badDomain, bad, _) = try prepared(single(
                "export function animationEvent(event,value){thisObject.pause();return \(expression);}",
                peer: "export function update(value){return 2.5;}"))
            try badDomain.publishPuppetAnimationEvents([
                .init(identity: identity, sequence: 1, name: "bad", frame: 1)], failures: [:])
            let failed = bad.evaluate(inputs: [target: .scalar(1), sibling: .scalar(1)], frame: frame(0))
            rejected.append(failed.failures[target] != nil && failed.values[target] == nil
                && number(failed.values[sibling]) == 2.5
                && !failed.ownerEffects.contains { $0.ownerTarget == target }
                && mwx_scene_quickjs_owner_puppet_animation_command_count(
                    bad.bindings.first { $0.target == target }!.handle) == 0)
        }
        return ["value": number(result.values[target]), "failures": result.failures.count,
            "pose": state(playback), "rejected": rejected,
            "consumed": !mwx_scene_quickjs_owner_has_pending_puppet_animation_events(program.bindings[0].handle)]
    }
    static func sortCohort() throws -> [String: Any] {
        let input = RateFixture([
            ["id": 42, "name": "first", "animationlayers": [authored(91, name: "first",
                source: "export function update(value){thisObject.rate=4;thisScene.sortLayer(thisLayer,1);return 2;}")]],
            ["id": 43, "name": "last", "animationlayers": [authored(91, name: "peer",
                source: "export function update(value){return 2.5;}")]],
        ])
        let (domain, program, _) = try prepared(input)
        let result = program.evaluate(inputs: [target: .scalar(1), foreign: .scalar(1)], frame: frame(0))
        return ["failed": result.failures[target] != nil && result.values[target] == nil,
            "peer": number(result.values[foreign]),
            "bundleAbsent": !result.ownerEffects.contains { $0.ownerTarget == target },
            "topologyCleared": mwx_scene_quickjs_domain_has_pending_layer_topology(domain.handle) == 0,
            "commandsCleared": mwx_scene_quickjs_owner_puppet_animation_command_count(
                program.bindings.first { $0.target == target }!.handle) == 0]
    }
    static func mediaCallbackCohort() throws -> [[String: Any]] {
        var output: [[String: Any]] = []
        for invalid in [true, false] {
            let body = invalid ? "thisObject.rate=4;thisLayer.alpha=0.25;" : "thisObject.rate=4;"
            let input = single("""
            export function mediaPlaybackChanged(event){\(body)}
            export function update(value){return 2;}
            """, peer: "export function update(value){return 2.5;}")
            let (_, program, playback) = try prepared(input)
            let result = program.evaluate(inputs: [target: .scalar(1), sibling: .scalar(1)],
                frame: frame(0), mediaPlaybackEvent: .init(state: 1, generation: 1))
            let commands = result.ownerEffects.filter { $0.ownerTarget == target }
                .flatMap(\.puppetAnimationCommands)
            if !invalid {
                try playback.validate(commands, sourceLayerID: 42, sourceAnimationLayerID: 91,
                    frameIndex: 0).get()
                try playback.apply(commands, frameIndex: 0).get()
            }
            let beforeAdvance = state(playback)
            let owner = program.bindings.first { $0.target == target }!
            let pendingCommands = mwx_scene_quickjs_owner_puppet_animation_command_count(owner.handle)
            program.finalizeLayerMutations(committing: true)
            _ = playback.advance(frameIndex: 1, sceneTime: 1,
                dynamicValues: resolve(program.definitions, result.values, 1))
            output.append(["invalid": invalid, "failed": result.failures[target] != nil,
                "value": number(result.values[target]), "peer": number(result.values[sibling]),
                "bundleAbsent": !result.ownerEffects.contains { $0.ownerTarget == target },
                "commands": commands.count, "pendingCommands": pendingCommands,
                "parentWritesAbsent": result.layerMutations.isEmpty,
                "beforeAdvance": beforeAdvance,
                "poses": [state(playback), state(playback, id: 208)]])
        }
        return output
    }
    static func lateRejection() throws -> [String: Any] {
        let input = single("""
        let count=0;export function update(v){
          if(count++===0){thisObject.setFrame(17);return 4;}return thisObject.getFrame();}
        """,
            peer: "export function update(v){return 2.5;}")
        let (_, program, playback) = try prepared(input)
        let result = program.evaluate(inputs: [target: .scalar(1), sibling: .scalar(1)], frame: frame(0))
        let effects = result.ownerEffects.first { $0.ownerTarget == target }!
        let refusal = playback.validate(effects.puppetAnimationCommands,
            sourceLayerID: 42, sourceAnimationLayerID: 999, frameIndex: 0)
        let rejected: Bool
        if case .failure = refusal { rejected = true } else { rejected = false }
        let admitted = result.valuesForAdmission(timelineValues: [:], excluding: [target])
        program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [target])
        let observed = program.evaluate(inputs: [target: .scalar(1), sibling: .scalar(1)], frame: frame(0))
        program.finalizeLayerMutations(committing: false)
        let snapshot = resolve(program.definitions, admitted, 1)
        _ = playback.advance(frameIndex: 1, sceneTime: 1, dynamicValues: snapshot)
        return ["nativeRefused": rejected, "commandCount": effects.puppetAnimationCommands.count,
            "ownerValueAbsent": admitted[target] == nil,
            "rolledBackMirror": number(observed.values[target]),
            "peerValue": number(admitted[sibling]),
            "poses": [state(playback), state(playback, id: 208)]]
    }
    static func main() throws {
        let report: [String: Any] = ["qualification": qualification(),
            "variants": try variants(), "cadence": try cadence(),
            "failures": try failures(), "lateRejection": try lateRejection(),
            "acceptedSources": try acceptedSources(), "firstCadence": try firstCadenceAndLateParent(),
            "numericVisibility": try numericVisibility(), "scalarEvents": try scalarEvents(),
            "sortCohort": try sortCohort(), "mediaCallbackCohort": try mediaCallbackCohort()]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report))
    }
}
'''


class PuppetAnimationRateScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        output_root = ROOT / ".artifacts/tmp/animation-rate-source-329-20261020/tests"
        output_root.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="rate-script-", dir=output_root)
        try:
            binary = compile_vector_harness(Path(cls.temporary.name), HARNESS,
                "puppet-rate-script", extra_swift_sources=EXTRA_SWIFT_SOURCES)
            cls.result = json.loads(subprocess.check_output([binary], text=True, timeout=60))
        except BaseException:
            cls.temporary.cleanup()
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_parser_and_prepared_identity_qualify_only_unique_rate_owners(self) -> None:
        value = self.result["qualification"]
        self.assertEqual((value["bindingCount"], value["count"]), (4, 4))
        for key, passed in value["rejected"].items():
            self.assertTrue(passed, key)
        for key in ("duplicateWrapperLocal", "duplicateIDLocal", "staticNeighborsAbsent",
                    "parserPath", "parserIdentity"):
            self.assertTrue(value[key], key)

    def test_renamed_equivalent_sources_preserve_parent_and_animation_isolation(self) -> None:
        for value in self.result["variants"]:
            self.assertEqual((value["bindings"], value["failures"]), (4, 0), value)
            self.assertEqual(value["values"], [2, 2.5, 3, 3.5])
            self.assertEqual(value["poses"], [[20, 2], [25, 2.5], [30, 3], [35, 3.5], [12.5, 1.25]])
            self.assertEqual(value["source"], "sceneScript")

    def test_next_cadence_rate_changes_preserve_phase_pause_seek_and_freeze(self) -> None:
        value = self.result["cadence"]
        self.assertEqual(value["poses"], [
            [10, 1], [10, 1], [30, 2], [30, 2], [30, 0], [30, 0],
            [60, 3], [65, 0.5], [65, 2], [85, 2], [85, 3], [115, 3], [27, 2],
        ])
        self.assertTrue(value["sameAndStale"])

    def test_invalid_returns_and_host_failures_drop_the_owner_bundle_keep_peer(self) -> None:
        for value in self.result["failures"]:
            self.assertNotEqual(value["code"], "missing")
            self.assertTrue(value["invalidAbsent"])
            self.assertEqual(value["peerValue"], 2.5)
            self.assertTrue(value["failedCommandsAbsent"])
            self.assertTrue(value["bundleAbsent"])
            self.assertTrue(value["parentWritesAbsent"])
            self.assertEqual(value["fallbackSource"], "authored")
            self.assertEqual(value["poses"], [[10, 1], [25, 2.5]])

    def test_late_native_refusal_excludes_the_rate_value_and_keeps_peer(self) -> None:
        value = self.result["lateRejection"]
        self.assertTrue(value["nativeRefused"])
        self.assertEqual(value["commandCount"], 1)
        self.assertTrue(value["ownerValueAbsent"])
        self.assertEqual(value["rolledBackMirror"], 0)
        self.assertEqual(value["peerValue"], 2.5)
        self.assertEqual(value["poses"], [[10, 1], [25, 2.5]])

    def test_only_valid_script_sources_change_an_accepted_or_api_rate(self) -> None:
        value = self.result["acceptedSources"]
        self.assertTrue(value["failure"])
        self.assertEqual(value["sources"], ["authored", "userProperty", "timeline"])
        self.assertEqual(value["poses"], [[20, 2], [40, 2], [60, 2], [80, 2], [100, 2],
            [120, 2], [140, 2], [160, 2], [190, 3], [210, 2]])

    def test_nonzero_first_cadence_and_late_parent_anchor_existing_phase(self) -> None:
        value = self.result["firstCadence"]
        self.assertEqual(value["first"], [50, 2])
        self.assertEqual(value["same"], [[50, 2], [50, 3]])
        self.assertEqual(value["next"], [[70, 2], [80, 3]])

    def test_numeric_returns_do_not_change_boolean_visibility(self) -> None:
        zero, hidden = self.result["numericVisibility"]
        self.assertEqual((zero["value"], zero["state"], zero["commands"]), (0, [0, 0], 0))
        self.assertTrue(zero["visible"])
        self.assertTrue(zero["samplePresent"])
        self.assertEqual((hidden["value"], hidden["state"], hidden["commands"]), (2, [0, 2], 1))
        self.assertFalse(hidden["visible"])
        self.assertFalse(hidden["samplePresent"])

    def test_animation_events_pass_numbers_keep_undefined_and_reject_other_types(self) -> None:
        value = self.result["scalarEvents"]
        self.assertEqual((value["value"], value["failures"], value["pose"]), (2.5, 0, [25, 2.5]))
        self.assertEqual(value["rejected"], [True] * 4)
        self.assertTrue(value["consumed"])

    def test_nested_rate_owner_cannot_leave_a_sort_topology_transaction(self) -> None:
        value = self.result["sortCohort"]
        self.assertTrue(value["failed"])
        self.assertEqual(value["peer"], 2.5)
        self.assertTrue(value["bundleAbsent"])
        self.assertTrue(value["topologyCleared"])
        self.assertTrue(value["commandsCleared"])

    def test_media_callback_cohort_is_checked_before_the_following_update(self) -> None:
        invalid, valid = self.result["mediaCallbackCohort"]
        self.assertTrue(invalid["failed"])
        self.assertEqual(invalid["value"], -999)
        self.assertTrue(invalid["bundleAbsent"])
        self.assertEqual((invalid["commands"], invalid["pendingCommands"]), (0, 0))
        self.assertEqual(invalid["beforeAdvance"], [0, 1])
        self.assertEqual(invalid["poses"], [[10, 1], [25, 2.5]])
        self.assertFalse(valid["failed"])
        self.assertEqual(valid["value"], 2)
        self.assertFalse(valid["bundleAbsent"])
        self.assertEqual(valid["commands"], 1)
        self.assertEqual(valid["beforeAdvance"], [0, 4])
        self.assertEqual(valid["poses"], [[20, 2], [25, 2.5]])
        for value in (invalid, valid):
            self.assertEqual(value["peer"], 2.5)
            self.assertTrue(value["parentWritesAbsent"])


if __name__ == "__main__":
    unittest.main()
