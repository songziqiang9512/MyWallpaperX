#!/usr/bin/env python3
"""Sound volume scripts reach the one real AVQueuePlayer through typed snapshots."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import wave

from script.tests import scene_vector_vm_test_support as vm
from script.tests.test_scene_sound_playback_program import STUB_SOURCE

SCENE = vm.SCENE
EXTRA_SOURCES = (
    SCENE / "Systems/Media/SceneSoundPlaybackProgram.swift",
    SCENE / "Systems/Media/SceneSoundPlaybackRegistry.swift",
    SCENE / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
    SCENE / "Systems/Properties/ScenePropertyLiveUpdateState.swift",
    SCENE / "Systems/Properties/SceneEvaluationTransaction.swift",
)


def sound_preamble() -> str:
    # Reuse the existing external document/resource carriers. The VM, dynamic
    # snapshot, Sound Program, Registry, and AVQueuePlayer remain production code.
    return vm.SWIFT_PREAMBLE + STUB_SOURCE[STUB_SOURCE.index("struct SceneDocument {"):]


HARNESS = r'''
import AVFoundation

@main enum SoundVolumeChecks {
    static let target = SceneDynamicTarget.layer(layerID: 16, field: .volume)
    static let seed = 0.25
    static let passthrough = "export function update(value) { return value; }"
    static let frame = SceneScriptFrameInput(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1.0 / 60.0,
        sceneTime: 2), timeZone: TimeZone(secondsFromGMT: 0)!)

    static func layer(_ id: Int = 16, index: Int = 0,
                      kind: String = "sound") -> SceneRenderDescriptor.Layer {
        .init(id: id, layerIndex: index, name: "self-owned \(id)", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1,
            effects: [], contentKind: kind)
    }

    static func sound(resource: String, volume: Double = seed,
                      property: String? = nil, mode: String = "loop",
                      spatial: Bool? = nil) -> SceneDocument.SceneSoundLayerDefinition {
        .init(paths: [resource], authoredPathCount: 1, playbackMode: mode,
            startsSilent: true, muteInEditor: false, volume: volume,
            volumePropertyKey: property, minimumTime: nil, maximumTime: nil,
            spatialization: spatial, attenuation: nil, minimumDistance: nil)
    }

    static func prepared(audio: URL, resource: String = "audio/own.wav",
                         volume: Double = seed, property: String? = nil,
                         mode: String = "loop", spatial: Bool? = nil,
                         available: Bool = true) -> SceneSoundPlaybackProgram {
        .compile(document: .init(objects: [.init(id: 16, sound: sound(resource: resource,
            volume: volume, property: property, mode: mode, spatial: spatial))]),
            resourceView: .init(resourcesByReference: available ? [resource: audio] : [:]))
    }

    static func document(resource: String = "audio/own.wav", source: String = passthrough,
                         value: Double = seed, key: String? = nil, input: String = "gain",
                         extra: [String: Any] = [:]) -> [String: Any] {
        var wrapper: [String: Any] = ["value": value, "script": source]
        if let key { wrapper["scriptproperties"] = [input: ["user": key, "value": 2.0]] }
        wrapper.merge(extra) { _, replacement in replacement }
        return ["objects": [["id": 16, "sound": [resource], "volume": wrapper]]]
    }

    static func bindings(_ root: [String: Any]) -> [SceneScriptBindingIR] {
        SceneScriptBindingIRParser.parse(document: root).bindings
    }

    static func exclusions(_ scene: SceneRenderDescriptor, _ scripts: [SceneScriptBindingIR],
                           sound: SceneSoundPlaybackProgram,
                           timeline: Set<SceneDynamicTarget> = []) -> Set<SceneDynamicTarget> {
        let definitions = SceneScriptScalarProgram.projectedDefinitions(descriptor: scene,
            scriptBindings: scripts, timelineTargets: timeline)
        let volumeTargets = Set(definitions.compactMap { definition -> SceneDynamicTarget? in
            if case .layer(_, .volume) = definition.target { return definition.target }
            return nil
        })
        return volumeTargets.subtracting(sound.sceneScriptVolumeConsumerTargets(for: definitions))
    }

    static func candidate(_ scene: SceneRenderDescriptor, _ scripts: [SceneScriptBindingIR],
                          sound: SceneSoundPlaybackProgram,
                          properties: [SceneUserPropertyDefinition] = [],
                          timeline: Set<SceneDynamicTarget> = []) throws
        -> SceneScriptQuickJSProgramCandidate {
        try .compile(authoredDescriptor: scene, runtimeDescriptor: scene,
            scriptBindings: scripts,
            vectorProjection: SceneScriptVectorProgram.project(descriptor: scene,
                scriptBindings: scripts), userPropertyDefinitions: properties,
            timelineTargets: timeline,
            scalarExcludedTargets: exclusions(scene, scripts, sound: sound, timeline: timeline),
            stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 11)
    }

    static func snapshot(_ definitions: [SceneDynamicTargetDefinition],
                         script: [SceneDynamicTarget: SceneDynamicValue] = [:],
                         user: [SceneDynamicTarget: SceneDynamicValue] = [:])
        -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 11,
            definitions: definitions, userValues: user, sceneScriptValues: script).snapshot
    }

    // The existing Sound playback gate uses this reflection helper to inspect
    // the real registry-owned player without introducing a product accessor.
    static func player(_ registry: SceneSoundPlaybackRegistry, layer: Int) -> AVQueuePlayer {
        let sources = Mirror(reflecting: registry).children.first { $0.label == "sources" }!.value
        for child in Mirror(reflecting: sources).children {
            let pair = Array(Mirror(reflecting: child.value).children)
            if pair[0].value as? Int == layer {
                return Mirror(reflecting: pair[1].value).children
                    .first { $0.value is AVQueuePlayer }!.value as! AVQueuePlayer
            }
        }
        fatalError("existing player missing for \(layer)")
    }

    static func source(input: String, variant: Int) -> String {
        let local = ["initial", "authoredLevel", "seedVolume"][variant]
        let expression = ["\(local) * scriptProperties.\(input)",
            "scriptProperties.\(input) * \(local)",
            "(\(local) + \(local)) * (scriptProperties.\(input) / 2)"][variant]
        return """
        export var scriptProperties = createScriptProperties()
            .addSlider({name:'\(input)',value:2,min:0,max:4,integer:false}).finish();
        let \(local) = 0;
        export function init(value) { \(local) = value; }
        export function update(current) { return \(expression); }
        """
    }

    static func propertyFacts(audio: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let direct = SceneDynamicTarget.layer(layerID: 17, field: .volume)
        for (index, names) in [("level", "gain", "audio/original.wav"),
                              ("renamedLevel", "multiplier", "audio/renamed.wav"),
                              ("exposure", "factor", "sound/unseen.wav")].enumerated() {
            let (key, input, resource) = names
            let scene = SceneRenderDescriptor(layers: [layer(), layer(17, index: 1)])
            var root = document(resource: resource, source: source(input: input, variant: index),
                key: key, input: input)
            var objects = root["objects"] as! [[String: Any]]
            objects.append(["id": 17, "sound": [resource],
                "volume": ["user": "directGain", "value": 0.2]])
            root["objects"] = objects
            let plan = SceneSoundPlaybackProgram.compile(document: .init(objects: [
                .init(id: 16, sound: sound(resource: resource)),
                .init(id: 17, sound: sound(resource: resource, volume: 0.2, property: "directGain"))]),
                resourceView: .init(resourcesByReference: [resource: audio]))
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
                key: ["type": "slider", "value": 2.0, "min": 0, "max": 4],
                "directGain": ["type": "slider", "value": 0.2, "min": 0, "max": 1]])
            let scripts = bindings(root)
            let accepted = try candidate(scene, scripts, sound: plan, properties: catalog.definitions)
            let program = accepted.scalarProgram
            let compiled = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: root), catalog: catalog)
            var live = ScenePropertyLiveUpdateState(program: compiled.program,
                effectiveValues: catalog.effectiveValues(overrides: [:]),
                activeConsumerTargets: program.activeLivePropertyInputTargets.union(plan.liveConsumerTargets))
            let registry = SceneSoundPlaybackRegistry(program: plan, epoch: UInt64(index + 1))
            registry.start(paused: false, userValues: live.userValues)
            defer { registry.stop() }
            let actual = player(registry, layer: 16), directPlayer = player(registry, layer: 17)
            let initialItem = actual.currentItem
            facts[key + "-single-owner"] = accepted.domain != nil
                && accepted.constructionReport.isComplete && scripts.count == 1
                && accepted.constructionReport.expectedScalarTargets == [target]
                && accepted.constructionReport.instantiatedScalarTargets == [target]
                && accepted.constructionReport.expectedVectorTargets.isEmpty
                && accepted.constructionReport.expectedStringTargets.isEmpty
                && accepted.constructionReport.expectedCursorTargets.isEmpty
                && program.bindings.count == 1 && program.definitions.count == 1
            facts[key + "-real-property-inputs"] = compiled.diagnostics.isEmpty
                && compiled.program.rebuildRequiredPropertyKeys.isEmpty
                && compiled.program.instructions.count == 2
                && !program.activeLivePropertyInputTargets.isEmpty
            let first = program.evaluate(inputs: [target: .scalar(seed)], frame: frame,
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let definitions = program.definitions + compiled.program.definitions
            let firstSnapshot = snapshot(definitions, script: first.values, user: live.userValues)
            registry.apply(snapshot: firstSnapshot)
            facts[key + "-vm-snapshot-real-player"] = first.failures.isEmpty
                && first.values[target] == .scalar(0.5)
                && firstSnapshot[target]?.source == .sceneScript
                && actual.volume == 0.5 && actual.rate == 0
                && actual.currentItem === initialItem
            let owner = program.bindings.first
            let applied = live.apply(.number(3), forPropertyKey: key)
            let second = program.evaluate(inputs: firstSnapshot.typedValues(for: program.inputTargets,
                valueTypes: program.inputValueTypes), frame: frame,
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let changed = snapshot(definitions, script: second.values, user: live.userValues)
            registry.apply(snapshot: changed)
            facts[key + "-live-edit-same-owner-and-player"] = applied && live.revision == 1
                && program.bindings.first === owner && second.failures.isEmpty
                && second.values[target] == .scalar(0.75) && actual.volume == 0.75
                && player(registry, layer: 16) === actual && actual.currentItem === initialItem
            registry.apply(userValues: live.userValues)
            facts[key + "-unrelated-property-does-not-reset-script-gain"] = actual.volume == 0.75
            registry.pause()
            let directApplied = live.apply(.number(0.6), forPropertyKey: "directGain")
            registry.apply(userValues: live.userValues)
            facts[key + "-paused-direct-property-still-applies"] = directApplied
                && directPlayer.volume == Float(0.6) && directPlayer.rate == 0 && actual.volume == 0.75
            registry.apply(snapshot: snapshot(definitions,
                script: [target: .scalar(0.75), direct: .scalar(0.9)]))
            facts[key + "-snapshot-leaves-direct-property-owner"] = directPlayer.volume == Float(0.6)
            registry.setMasterVolume(0.5)
            facts[key + "-master-multiplies-consumed-base"] = actual.volume == 0.375
                && directPlayer.volume == Float(0.3)
            registry.setMuted(true)
            registry.apply(snapshot: snapshot(definitions, script: [target: .scalar(0.4)]))
            facts[key + "-mute-holds-zero-during-script-update"] = actual.volume == 0
                && directPlayer.volume == 0
            registry.setMuted(false)
            facts[key + "-unmute-restores-current-script-gain"] = actual.volume == Float(0.2)
                && directPlayer.volume == Float(0.3)
            registry.setMasterVolume(1)
            registry.apply(snapshot: .empty(frameIndex: 2))
            registry.apply(snapshot: snapshot(definitions, script: [target: .scalar(0.8)]),
                excludingLayerIDs: [16])
            facts[key + "-missing-and-retiring-snapshot-do-not-write"] = actual.volume == Float(0.4)
            registry.resume()
            facts[key + "-gain-does-not-start-silent-layer"] = actual.rate == 0
                && directPlayer.rate == 0 && registry.sceneScriptSnapshots()[16] == false
        }
        return facts
    }

    static func changed(_ binding: SceneScriptBindingIR,
                        path: [SceneScriptBindingPathComponent]? = nil,
                        authored: SceneJSONValue? = nil,
                        type: SceneScriptBindingValueType? = nil,
                        kind: SceneScriptBindingOwner.Kind? = nil) -> SceneScriptBindingIR {
        .init(source: binding.source,
            owner: .init(kind: kind ?? binding.owner.kind,
                objectIndex: binding.owner.objectIndex, objectID: binding.owner.objectID,
                effectIndex: binding.owner.effectIndex, effectID: binding.owner.effectID,
                passIndex: binding.owner.passIndex, passID: binding.owner.passID),
            targetPath: path ?? binding.targetPath, properties: binding.properties,
            authoredValue: authored ?? binding.authoredValue, valueType: type ?? binding.valueType,
            wrapperKeys: binding.wrapperKeys, userPropertyKey: binding.userPropertyKey)
    }

    static func admissionFacts(audio: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let scene = SceneRenderDescriptor(layers: [layer()])
        let sound = prepared(audio: audio)
        let valid = bindings(document())[0]
        let rejected: [(String, SceneRenderDescriptor, [SceneScriptBindingIR], Set<SceneDynamicTarget>)] = [
            ("wrong-host", scene, [changed(valid,
                path: [.key("objects"), .index(0), .key("gain")])], []),
            ("nested-path", scene, [changed(valid,
                path: [.key("objects"), .index(0), .key("sound"), .key("volume")])], []),
            ("wrong-owner", scene, [changed(valid, kind: .pass)], []),
            ("wrong-value-type", scene, [changed(valid, authored: .string("0.25"), type: .string)], []),
            ("non-sound", .init(layers: [layer(kind: "image")]), [valid], []),
            ("duplicate", scene, [valid, valid], []),
            ("unknown-wrapper", scene, bindings(document(extra: ["extra": true])), []),
            ("outer-user", scene, bindings(document(extra: ["user": "gain"])), []),
            ("null-outer-user", scene, bindings(document(extra: ["user": NSNull()])), []),
            ("animation-wrapper", scene, bindings(document(extra: ["animation": ["id": 1]])), []),
            ("timeline-collision", scene, [valid], [target]),
            ("negative-seed", scene, [changed(valid, authored: .number(-0.1))], []),
            ("high-seed", scene, [changed(valid, authored: .number(1.1))], []),
            ("nonfinite-seed", scene, [changed(valid, authored: .number(.infinity))], []),
        ]
        for (name, input, scripts, timeline) in rejected {
            let accepted = try candidate(input, scripts, sound: sound, timeline: timeline)
            facts[name + "-zero-owner"] = accepted.constructionReport.expectedScalarTargets.isEmpty
                && accepted.constructionReport.instantiatedScalarTargets.isEmpty
                && accepted.scalarProgram.bindings.isEmpty && accepted.scalarProgram.definitions.isEmpty
        }
        let definitions = SceneScriptScalarProgram.projectedDefinitions(descriptor: scene,
            scriptBindings: [valid])
        facts["admitted-sound-and-raw-seed-match"] = definitions.count == 1
            && sound.sceneScriptVolumeConsumerTargets(for: definitions) == [target]
        facts["unmatched-typed-target-is-not-a-consumer"] = sound.sceneScriptVolumeConsumerTargets(for: [
            .init(target: .layer(layerID: 999, field: .volume), valueType: .scalar, authoredValue: .scalar(seed)),
            .init(target: .layer(layerID: 16, field: .alpha), valueType: .scalar, authoredValue: .scalar(seed)),
        ]).isEmpty
        for (name, plan) in [
            ("missing-resource", prepared(audio: audio, available: false)),
            ("seed-conflict", prepared(audio: audio, volume: seed.nextUp)),
            ("direct-property-conflict", prepared(audio: audio, property: "gain")),
            ("ogg", prepared(audio: audio, resource: "audio/unsupported.ogg")),
            ("random-mode", prepared(audio: audio, mode: "random")),
            ("spatial", prepared(audio: audio, spatial: true)),
        ] {
            let excluded = exclusions(scene, [valid], sound: plan)
            let accepted = try candidate(scene, [valid], sound: plan)
            facts[name + "-late-zero-owner"] = excluded == [target]
                && plan.sceneScriptVolumeConsumerTargets(for: definitions).isEmpty
                && accepted.constructionReport.expectedScalarTargets.isEmpty
                && accepted.constructionReport.instantiatedScalarTargets.isEmpty
                && accepted.scalarProgram.definitions.isEmpty && accepted.scalarProgram.bindings.isEmpty
        }
        let request = """
        thisScene.createLayer('models/excluded-sound.json');
        export function update(value) { return value; }
        """
        let scripts = bindings(document(source: request))
        var resourceScene = scene
        resourceScene.modelMaterialLinks = [.init(modelPath: "models/excluded-sound.json")]
        let missing = prepared(audio: audio, available: false)
        let excluded = exclusions(resourceScene, scripts, sound: missing)
        let projection = SceneScriptVectorProgram.project(descriptor: resourceScene, scriptBindings: scripts)
        let planned = SceneScriptQuickJSProgramCandidate.plannedOwnerSources(authoredDescriptor: resourceScene,
            runtimeDescriptor: resourceScene, scriptBindings: scripts, vectorProjection: projection,
            plannedVectorTargets: projection.nonPassTargets, timelineTargets: [],
            scalarExcludedTargets: excluded, stringExcludedTargets: [], excludedStandaloneCursorLayerIDs: [])
        let accepted = try candidate(resourceScene, scripts, sound: missing)
        facts["late-exclusion-releases-resource-request"] = planned.isEmpty && accepted.domain != nil
            && accepted.domain?.dynamicImageRequestedModelPaths.isEmpty == true
            && SceneScriptDynamicImageReferenceAnalysis.references(in: request,
                descriptor: resourceScene)?.map(\.modelPath) == ["models/excluded-sound.json"]
        return facts
    }

    static func numericFacts(audio: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let peer = SceneDynamicTarget.layer(layerID: 18, field: .volume)
        let scene = SceneRenderDescriptor(layers: [layer(), layer(18, index: 1)])
        let plan = SceneSoundPlaybackProgram.compile(document: .init(objects: [
            .init(id: 16, sound: sound(resource: "audio/numeric.wav")),
            .init(id: 18, sound: sound(resource: "audio/numeric.wav", volume: 0.1))]),
            resourceView: .init(resourcesByReference: ["audio/numeric.wav": audio]))
        func scripts(_ source: String) -> [SceneScriptBindingIR] {
            var root = document(source: source)
            var objects = root["objects"] as! [[String: Any]]
            objects.append(["id": 18, "sound": ["audio/numeric.wav"], "volume": ["value": 0.1,
                "script": "export function update(value) { return 0.3; }"]])
            root["objects"] = objects
            return bindings(root)
        }
        let valuesSource = """
        const levels = [0, 1, 0.4, -0.1, 1.1, NaN, Infinity, 'bad', 0.6];
        let index = 0;
        export function update(value) { return levels[index++]; }
        """
        let program = try candidate(scene, scripts(valuesSource), sound: plan).scalarProgram
        let registry = SceneSoundPlaybackRegistry(program: plan, epoch: 4)
        registry.start(paused: false, userValues: [:]); defer { registry.stop() }
        let actual = player(registry, layer: 16), healthy = player(registry, layer: 18)
        var transaction = SceneEvaluationTransaction()
        for (index, expected) in [0.0, 1, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.6].enumerated() {
            var current = transaction.previousValues(for: program.inputTargets)
            let evaluated = program.evaluate(inputs: [target: .scalar(seed), peer: .scalar(0.1)], frame: frame)
            current.merge(evaluated.values) { _, latest in latest }
            let resolved = transaction.evaluate(frameIndex: UInt64(index + 1),
                definitions: program.definitions, sceneScriptValues: current).snapshot
            registry.apply(snapshot: resolved)
            let invalid = (3 ... 7).contains(index)
            facts["numeric-output-\(index)"] = actual.volume == Float(expected)
                && healthy.volume == Float(0.3) && healthy.rate == 0 && actual.rate == 0
                && resolved[target]?.source == .sceneScript
                && evaluated.values[peer] == .scalar(0.3)
                && (invalid ? evaluated.failures[target]?.code == "bad-return"
                        && evaluated.values[target] == nil && evaluated.failures.count == 1
                    : evaluated.failures.isEmpty && evaluated.values[target] == .scalar(expected))
        }
        facts["invalid-value-owner-recovers"] = !program.disabledTargets.contains(target)
            && player(registry, layer: 16) === actual && actual.volume == Float(0.6)
        for (name, body, code) in [
            ("exception", "throw new Error('self-owned failure');", "exception"),
            ("budget", "for (;;) {}", "budget-exceeded"),
        ] {
            let source = """
            let calls = 0;
            export function update(value) { if (++calls === 2) { \(body) } return 0.4; }
            """
            let failedProgram = try candidate(scene, scripts(source), sound: plan).scalarProgram
            let first = failedProgram.evaluate(inputs: [target: .scalar(seed), peer: .scalar(0.1)],
                frame: frame, interruptBudget: 1000)
            var state = SceneEvaluationTransaction()
            _ = state.evaluate(frameIndex: 1, definitions: failedProgram.definitions,
                sceneScriptValues: first.values)
            let failed = failedProgram.evaluate(inputs: [target: .scalar(0.4), peer: .scalar(0.3)],
                frame: frame, interruptBudget: 1000)
            var retained = state.previousValues(for: failedProgram.inputTargets)
            retained.merge(failed.values) { _, latest in latest }
            let resolved = state.evaluate(frameIndex: 2, definitions: failedProgram.definitions,
                sceneScriptValues: retained).snapshot
            registry.apply(snapshot: resolved)
            facts[name + "-failure-stays-local"] = first.failures.isEmpty
                && failed.failures[target]?.code == code && failed.values[target] == nil
                && failed.values[peer] == .scalar(0.3) && actual.volume == Float(0.4)
                && healthy.volume == Float(0.3)
        }
        for (index, value) in [-0.1, 1.1].enumerated() {
            registry.apply(snapshot: snapshot(program.definitions, script: [target: .scalar(value)]))
            facts["registry-rejects-invalid-finite-\(index)"] = actual.volume == Float(0.4)
        }
        let wrongType = snapshot([.init(target: target, valueType: .vector3,
            authoredValue: .vector3(1, 1, 1))])
        registry.apply(snapshot: wrongType)
        facts["registry-rejects-wrong-typed-entry"] = actual.volume == Float(0.4)
        return facts
    }

    static func wait(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    static func lifecycleFacts(audio: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let scene = SceneRenderDescriptor(layers: [layer(), layer(18, index: 1)])
        let plan = SceneSoundPlaybackProgram.compile(document: .init(objects: [
            .init(id: 16, sound: sound(resource: "audio/lifecycle.wav")),
            .init(id: 18, sound: sound(resource: "audio/lifecycle.wav", volume: 0.1))]),
            resourceView: .init(resourcesByReference: ["audio/lifecycle.wav": audio]))
        let program = try candidate(scene, bindings(document()), sound: plan).scalarProgram
        let registry = SceneSoundPlaybackRegistry(program: plan, epoch: 5)
        registry.start(paused: false, userValues: [:]); defer { registry.stop() }
        let actual = player(registry, layer: 16), healthy = player(registry, layer: 18)
        func update(_ volume: Double) {
            registry.apply(snapshot: snapshot(program.definitions, script: [target: .scalar(volume)]))
        }
        update(0.5)
        facts["startsilent-volume-keeps-playback-intent"] = actual.volume == 0.5
            && actual.rate == 0 && registry.sceneScriptSnapshots()[16] == false
        _ = try registry.apply([.init(layerID: 16, action: .play, destination: .soundLayer)]).get()
        let advanced = wait { CMTimeGetSeconds(actual.currentTime()) > 0.08 }
        let position = CMTimeGetSeconds(actual.currentTime())
        let item = actual.currentItem
        update(0.7)
        facts["gain-preserves-active-player-and-clock"] = advanced && actual.volume == Float(0.7)
            && actual.rate == 1 && actual.currentItem === item
            && CMTimeGetSeconds(actual.currentTime()) >= position
        _ = try registry.apply([.init(layerID: 16, action: .pause, destination: .soundLayer)]).get()
        registry.pause(); update(0.6); registry.resume()
        facts["volume-does-not-revive-author-pause"] = actual.volume == Float(0.6)
            && actual.rate == 0 && registry.sceneScriptSnapshots()[16] == false
        _ = try registry.apply([.init(layerID: 16, action: .stop, destination: .soundLayer)]).get()
        let rewound = wait { CMTimeGetSeconds(actual.currentTime()) < 0.03 }
        update(0.8); registry.resume()
        facts["volume-does-not-revive-author-stop"] = rewound && actual.volume == Float(0.8)
            && actual.rate == 0 && registry.sceneScriptSnapshots()[16] == false
        registry.retire(layerIDs: [16]); update(0.9)
        var retiredCommandRejected = false
        if case .failure(.unavailableLayer(16)) = registry.validate([
            .init(layerID: 16, action: .play, destination: .soundLayer)]) {
            retiredCommandRejected = true
        }
        facts["retired-sound-cannot-receive-or-revive"] = registry.sceneScriptSnapshots()[16] == nil
            && actual.currentItem == nil && actual.rate == 0
            && retiredCommandRejected
        facts["retirement-preserves-healthy-source"] = registry.sceneScriptSnapshots()[18] == false
            && player(registry, layer: 18) === healthy && healthy.currentItem != nil
        registry.stop(); update(0.4); registry.start(paused: false, userValues: [:])
        facts["stopped-epoch-does-not-revive"] = registry.sceneScriptSnapshots().isEmpty
            && healthy.currentItem == nil && healthy.rate == 0
        let cancelled = SceneSoundPlaybackRegistry(program: plan, epoch: 6)
        cancelled.stop(); cancelled.start(paused: false, userValues: [:])
        cancelled.apply(snapshot: snapshot(program.definitions, script: [target: .scalar(0.5)]))
        facts["cancelled-before-start-stays-empty"] = cancelled.sceneScriptSnapshots().isEmpty
        return facts
    }

    static func main() throws {
        let audio = URL(fileURLWithPath: CommandLine.arguments[1])
        var facts = try propertyFacts(audio: audio)
        facts.merge(try admissionFacts(audio: audio)) { _, latest in latest }
        facts.merge(try numericFacts(audio: audio)) { _, latest in latest }
        facts.merge(try lifecycleFacts(audio: audio)) { _, latest in latest }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def run_probe(directory: Path) -> dict:
    inputs = [*dict.fromkeys([*vm.SWIFT_SOURCES, *EXTRA_SOURCES]), *vm.C_SOURCES,
              Path(vm.__file__), Path(__file__),
              Path(__file__).with_name("test_scene_sound_playback_program.py")]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    audio = directory / "silent.wav"
    with wave.open(str(audio), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(8000)
        stream.writeframes(b"\0\0" * 32000)
    binary = vm.compile_vector_harness(directory, HARNESS, "sound-volume-script",
        extra_swift_sources=EXTRA_SOURCES, preamble=sound_preamble())
    run = subprocess.run([str(binary), str(audio)], capture_output=True, text=True, timeout=30)
    (directory / "stdout.json").write_text(run.stdout)
    (directory / "stderr.log").write_text(run.stderr)
    after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    (directory / "inputs.json").write_text(json.dumps({"before": before, "after": after,
        "harnessSHA256": hashlib.sha256(HARNESS.encode()).hexdigest(),
        "audioSHA256": hashlib.sha256(audio.read_bytes()).hexdigest(),
        "exitCode": run.returncode}, indent=2) + "\n")
    if before != after:
        raise AssertionError("source input changed during sound volume gate")
    if run.returncode:
        raise AssertionError(run.stderr)
    return json.loads(run.stdout)


class SceneScriptSoundVolumeTests(unittest.TestCase):
    def test_scalar_snapshot_reaches_same_player_and_preserves_sound_lifecycle(self) -> None:
        proof = os.environ.get("MWX_SOUND_VOLUME_TEST_EVIDENCE")
        if proof:
            directory = Path(proof)
            directory.mkdir(parents=True, exist_ok=True)
            facts = run_probe(directory)
        else:
            with tempfile.TemporaryDirectory(prefix="mwx-sound-volume-script-") as temporary:
                facts = run_probe(Path(temporary))
        self.assertTrue(facts)
        self.assertEqual([key for key, passed in facts.items() if passed is not True], [])


if __name__ == "__main__":
    unittest.main()
