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
    carriers = STUB_SOURCE[STUB_SOURCE.index("struct SceneDocument {"):]
    resource_start = carriers.index("struct SceneResource {")
    # The shared VM carrier now owns the camera schema. Merge the Sound DTO
    # members into that same document rather than declaring a second type.
    document_body = carriers[:resource_start].split("{", 1)[1].rsplit("}", 1)[0]
    preamble = vm.SWIFT_PREAMBLE.replace(
        "struct SceneDocument {", "struct SceneDocument {" + document_body, 1
    )
    return preamble + carriers[resource_start:]


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
                      spatial: Bool? = nil, minimumTime: Double? = nil,
                      maximumTime: Double? = nil) -> SceneDocument.SceneSoundLayerDefinition {
        .init(paths: [resource], authoredPathCount: 1, playbackMode: mode,
            startsSilent: true, muteInEditor: false, volume: volume,
            volumePropertyKey: property, minimumTime: minimumTime, maximumTime: maximumTime,
            spatialization: spatial, attenuation: nil, minimumDistance: nil)
    }

    static func prepared(audio: URL, resource: String = "audio/own.wav",
                         volume: Double = seed, property: String? = nil,
                         mode: String = "loop", spatial: Bool? = nil,
                         available: Bool = true, minimumTime: Double? = nil,
                         maximumTime: Double? = nil) throws -> SceneSoundPlaybackProgram {
        try .compile(document: .init(objects: [.init(id: 16, sound: sound(resource: resource,
            volume: volume, property: property, mode: mode, spatial: spatial,
            minimumTime: minimumTime, maximumTime: maximumTime))]),
            resourceView: .init(resourcesByReference: available ? [resource: audio] : [:]), privateCacheDirectory: FileManager.default.temporaryDirectory)
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
                           timeline: Set<SceneDynamicTarget> = [],
                           resolvedVolumes: [String: Double] = [:]) -> Set<SceneDynamicTarget> {
        let definitions = SceneScriptScalarProgram.projectedDefinitions(descriptor: scene,
            scriptBindings: scripts, timelineTargets: timeline)
        let volumeTargets = Set(definitions.compactMap { definition -> SceneDynamicTarget? in
            if case .layer(_, .volume) = definition.target { return definition.target }
            return nil
        })
        let named = SceneScriptScalarProgram.projectedVolumePropertyKeys(descriptor: scene,
            scriptBindings: scripts, timelineTargets: timeline)
        return volumeTargets.subtracting(sound.sceneScriptVolumeConsumerTargets(for: definitions,
            namedPropertyKeys: named, resolvedPropertyVolumes: resolvedVolumes))
    }

    static func candidate(_ scene: SceneRenderDescriptor, _ scripts: [SceneScriptBindingIR],
                          sound: SceneSoundPlaybackProgram,
                          properties: [SceneUserPropertyDefinition] = [],
                          timeline: Set<SceneDynamicTarget> = [],
                          resolvedVolumes: [String: Double] = [:]) throws
        -> SceneScriptQuickJSProgramCandidate {
        try .compile(authoredDescriptor: scene, runtimeDescriptor: scene,
            scriptBindings: scripts,
            vectorProjection: SceneScriptVectorProgram.project(descriptor: scene,
                scriptBindings: scripts), userPropertyDefinitions: properties,
            timelineTargets: timeline,
            scalarExcludedTargets: exclusions(scene, scripts, sound: sound, timeline: timeline,
                resolvedVolumes: resolvedVolumes),
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
            let plan = try SceneSoundPlaybackProgram.compile(document: .init(objects: [
                .init(id: 16, sound: sound(resource: resource)),
                .init(id: 17, sound: sound(resource: resource, volume: 0.2, property: "directGain"))]),
                resourceView: .init(resourcesByReference: [resource: audio]), privateCacheDirectory: FileManager.default.temporaryDirectory)
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
                        kind: SceneScriptBindingOwner.Kind? = nil,
                        source: String? = nil, property: String? = nil,
                        inputs: [String: SceneJSONValue]? = nil) -> SceneScriptBindingIR {
        .init(source: source ?? binding.source,
            owner: .init(kind: kind ?? binding.owner.kind,
                objectIndex: binding.owner.objectIndex, objectID: binding.owner.objectID,
                effectIndex: binding.owner.effectIndex, effectID: binding.owner.effectID,
                passIndex: binding.owner.passIndex, passID: binding.owner.passID),
            targetPath: path ?? binding.targetPath, properties: inputs ?? binding.properties,
            authoredValue: authored ?? binding.authoredValue, valueType: type ?? binding.valueType,
            wrapperKeys: binding.wrapperKeys, userPropertyKey: property ?? binding.userPropertyKey)
    }

    static func namedDocument(key: String, condition: String, pause: String, play: String,
                              source: String, resource: String,
                              extra: [String: Any] = [:]) -> [String: Any] {
        var wrapper: [String: Any] = [
            "user": key,
            "scriptproperties": [
                pause: ["user": ["name": condition, "condition": "0"], "value": false],
                play: ["user": ["name": condition, "condition": "1"], "value": false],
            ],
        ]
        wrapper.merge(extra) { _, replacement in replacement }
        return document(resource: resource, source: source, value: 0.2, extra: wrapper)
    }

    static func namedScene(_ root: [String: Any], kind: String = "sound") -> SceneRenderDescriptor {
        var owner = layer(kind: kind)
        owner.initialConfiguration = SceneJSONValue(jsonObject: (root["objects"] as! [Any])[0])
        return .init(layers: [owner])
    }

    static func scalar(_ value: SceneDynamicValue?, is expected: Double) -> Bool {
        guard case let .scalar(actual)? = value else { return false }
        return abs(actual - expected) < 1e-12
    }

    static func namedFacts(audio: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (index, names) in [
            ("outerGain", "switchA", "silence", "audible", "audio/named.wav"),
            ("renamedSlider", "gateB", "hold", "resume", "media/renamed.wav"),
            ("strength", "selector", "freeze", "continueSound", "sound/unseen.wav"),
        ].enumerated() {
            let (key, condition, pause, play, resource) = names
            let local = ["current", "level", "amount"][index]
            let expression = ["\(local) * .5 + .1", ".1 + \(local) / 2",
                "(\(local) + \(local)) / 4 + .1"][index]
            let source = """
            export var scriptProperties = createScriptProperties()
                .addCheckbox({name:'\(pause)',value:false})
                .addCheckbox({name:'\(play)',value:false}).finish();
            export function update(\(local)) {
                if (scriptProperties.\(pause)) thisLayer.pause();
                else if (scriptProperties.\(play)) thisLayer.play();
                return \(expression);
            }
            """
            let root = namedDocument(key: key, condition: condition, pause: pause, play: play,
                source: source, resource: resource)
            let scene = namedScene(root), scripts = bindings(root)
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
                key: ["type": "slider", "value": 0.4, "min": 0, "max": 1],
                condition: ["type": "combo", "value": "1", "options": [
                    ["label": "Off", "value": "0"], ["label": "On", "value": "1"]]],
            ])
            let unassigned = try prepared(audio: audio, resource: resource, volume: 0.8, property: key)
            let accepted = try candidate(scene, scripts, sound: unassigned,
                properties: catalog.definitions, resolvedVolumes: [key: 0.8])
            let program = accepted.scalarProgram
            let plan = unassigned.assigningSceneScriptVolumes(
                accepted.constructionReport.instantiatedScalarTargets)
            let compiled = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: root), catalog: catalog)
            var live = ScenePropertyLiveUpdateState(program: compiled.program,
                effectiveValues: catalog.effectiveValues(overrides: [key: .number(0.8)]),
                activeConsumerTargets: program.activeLivePropertyInputTargets.union(plan.liveConsumerTargets))
            let definitions = compiled.program.definitions
            let registry = SceneSoundPlaybackRegistry(program: plan, epoch: UInt64(20 + index))
            registry.start(paused: false, userValues: live.userValues)
            defer { registry.stop() }
            let actual = player(registry, layer: 16)
            let owner = program.bindings.first
            let prefix = "named-\(index)-"
            facts[prefix + "loop-item-ready-before-gain"] = wait { actual.currentItem != nil }
            facts[prefix + "raw-default-saved-separate"] = scripts.first?.authoredValue == .number(0.2)
                && catalog.definitions.first(where: { $0.key == key })?.defaultValue == .number(0.4)
                && unassigned.bindings.first?.authoredVolume == 0.8
                && live.userValues[target] == .scalar(0.8)
            facts[prefix + "one-real-owner-and-live-inputs"] = accepted.constructionReport.isComplete
                && program.bindings.count == 1 && program.definitions.count == 1
                && accepted.constructionReport.instantiatedScalarTargets == [target]
                && compiled.diagnostics.isEmpty && compiled.program.instructions.count == 3
                && compiled.program.rebuildRequiredPropertyKeys.isEmpty
                && SceneScriptScalarProgram.projectedVolumePropertyKeys(descriptor: scene,
                    scriptBindings: scripts) == [target: key]
            var transaction = SceneEvaluationTransaction()
            func evaluate(_ expected: Double, action: SceneScriptMediaPlaybackCommand.Action) throws {
                let previousIntent = registry.sceneScriptSnapshots()[16]
                try accepted.domain?.publishLayerSnapshot(.empty(frameIndex: live.revision),
                    descriptor: scene, soundPlaybackSnapshots: registry.sceneScriptSnapshots(),
                    runtimeFieldLayerIDs: [])
                let result = program.evaluate(inputs: [target: live.userValues[target]!], frame: frame,
                    effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
                let commands = result.ownerEffects.flatMap(\.mediaPlaybackCommands)
                let resolved = transaction.evaluate(frameIndex: live.revision + 1,
                    definitions: definitions, userValues: live.userValues,
                    sceneScriptValues: result.values).snapshot
                let suffix = String(live.revision)
                facts[prefix + "vm-transform-" + suffix] = result.failures.isEmpty
                    && scalar(result.values[target], is: expected)
                    && resolved[target]?.source == .sceneScript
                    && scalar(resolved[target]?.value, is: expected)
                    && commands.count == 1 && commands.first?.action == action
                    && commands.first?.destination == .soundLayer && commands.first?.layerID == 16
                    && registry.sceneScriptSnapshots()[16] == previousIntent
                _ = try registry.validate(commands).get()
                // A looper owns item rotation across playback. Prove gain
                // publication preserves the currently queued items before
                // applying the independently validated author playback command.
                let itemBeforeGain = actual.currentItem
                let queueBeforeGain = actual.items()
                registry.apply(snapshot: resolved)
                facts[prefix + "gain-preserves-current-item-and-queue-" + suffix] = itemBeforeGain != nil
                    && actual.currentItem === itemBeforeGain
                    && actual.items().elementsEqual(queueBeforeGain, by: { $0 === $1 })
                _ = try registry.apply(commands).get()
                program.finalizeLayerMutations(committing: true)
                facts[prefix + "same-real-player-and-owner-" + suffix] = actual.volume == Float(expected)
                    && player(registry, layer: 16) === actual
                    && program.bindings.first === owner
            }
            try evaluate(0.5, action: .play)
            facts[prefix + "initial-author-play"] = wait { actual.rate == 1 }
            let edit = live.apply(.number(0.4), forPropertyKey: key)
            registry.apply(userValues: live.userValues)
            facts[prefix + "direct-writer-exited"] = edit && actual.volume == Float(0.5)
            try evaluate(0.3, action: .play)
            for (input, output) in [(0.6, 0.4), (0.4, 0.3)] {
                let previousGain = actual.volume
                facts[prefix + "continuous-input-\(input)"] = live.apply(.number(input), forPropertyKey: key)
                registry.apply(userValues: live.userValues)
                facts[prefix + "snapshot-only-writer-\(input)"] = actual.volume == previousGain
                try evaluate(output, action: .play)
            }
            facts[prefix + "conditional-pause-input-live"] = live.apply(.string("0"), forPropertyKey: condition)
            try evaluate(0.3, action: .pause)
            facts[prefix + "conditional-pause-reaches-player"] = actual.rate == 0
                && registry.sceneScriptSnapshots()[16] == false
            registry.pause()
            facts[prefix + "conditional-play-input-live"] = live.apply(.string("1"), forPropertyKey: condition)
            try evaluate(0.3, action: .play)
            facts[prefix + "host-pause-stays-independent"] = actual.rate == 0
            registry.resume()
            facts[prefix + "resume-preserves-author-play"] = wait { actual.rate == 1 }
            let resendRevision = live.revision
            facts[prefix + "same-value-noop"] = live.apply(.number(0.4), forPropertyKey: key)
                && live.revision == resendRevision && actual.volume == Float(0.3)
            registry.retire(layerIDs: [16])
            registry.apply(snapshot: snapshot(definitions, script: [target: .scalar(0.9)]))
            facts[prefix + "retired-named-source-stays-retired"] = actual.currentItem == nil
                && registry.sceneScriptSnapshots().isEmpty
            // A candidate that constructs no Scalar owner keeps the original
            // immediate writer. This does not simulate Session orchestration.
            let failedRoot = namedDocument(key: key, condition: condition, pause: pause, play: play,
                source: "export function update(value) { return (", resource: resource)
            let failed = try candidate(namedScene(failedRoot), bindings(failedRoot), sound: unassigned,
                properties: catalog.definitions, resolvedVolumes: [key: 0.8])
            facts[prefix + "construction-failure-has-no-owner"] = failed.scalarProgram.bindings.isEmpty
                && failed.constructionReport.instantiatedScalarTargets.isEmpty
            let fallbackPlan = unassigned.assigningSceneScriptVolumes(
                failed.constructionReport.instantiatedScalarTargets)
            let direct = SceneSoundPlaybackRegistry(program: fallbackPlan,
                epoch: UInt64(30 + index))
            direct.start(paused: true, userValues: [target: .scalar(0.8)])
            let fallback = player(direct, layer: 16)
            direct.apply(snapshot: snapshot(definitions, script: [target: .scalar(0.1)]))
            facts[prefix + "unconstructed-owner-keeps-direct"] = fallback.volume == Float(0.8)
            direct.apply(userValues: [target: .scalar(0.4)])
            facts[prefix + "unconstructed-paused-direct-applies"] = fallback.volume == Float(0.4)
                && fallback.rate == 0
            direct.stop()
        }
        return facts
    }

    static func namedAdmissionFacts(audio: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let source = "export function update(value) { return value * .5 + .1; }"
        let root = namedDocument(key: "gain", condition: "mode", pause: "pause", play: "play",
            source: source, resource: "audio/named-admission.wav")
        let scene = namedScene(root), valid = bindings(root)[0]
        let plan = try prepared(audio: audio, resource: "audio/named-admission.wav", volume: 0.8, property: "gain")
        let plain = bindings(document(source: source))[0]
        let rejected: [(String, SceneRenderDescriptor, [SceneScriptBindingIR], Set<SceneDynamicTarget>)] = [
            ("source-mismatch", scene, [changed(valid, source: source + " ")], []),
            ("key-mismatch", scene, [changed(valid, property: "other")], []),
            ("input-mismatch", scene, [changed(valid, inputs: ["pause": .bool(true)])], []),
            ("duplicate", scene, [valid, valid], []),
            ("plain-and-named-duplicate", scene, [valid, plain], []),
            ("timeline", scene, [valid], [target]),
            ("wrong-host", namedScene(root, kind: "image"), [valid], []),
            ("wrong-path", scene, [changed(valid,
                path: [.key("objects"), .index(0), .key("alpha")])], []),
            ("bool-seed", scene, [changed(valid, authored: .bool(true), type: .boolean)], []),
            ("string-seed", scene, [changed(valid, authored: .string("0.2"), type: .string)], []),
            ("negative-seed", scene, [changed(valid, authored: .number(-0.1))], []),
            ("high-seed", scene, [changed(valid, authored: .number(1.1))], []),
            ("nonfinite-seed", scene, [changed(valid, authored: .number(.infinity))], []),
        ]
        for (name, input, scripts, timeline) in rejected {
            let accepted = try candidate(input, scripts, sound: plan, timeline: timeline,
                resolvedVolumes: ["gain": 0.8])
            facts["named-reject-" + name] = accepted.scalarProgram.bindings.isEmpty
                && accepted.constructionReport.expectedScalarTargets.isEmpty
                && SceneScriptScalarProgram.projectedVolumePropertyKeys(descriptor: input,
                    scriptBindings: scripts, timelineTargets: timeline).isEmpty
        }
        for (name, extra) in [
            ("bool", ["value": true] as [String: Any]), ("string", ["value": "0.2"]),
            ("null", ["value": NSNull()]), ("invalid-source", ["script": 4]),
            ("extra", ["extra": false]), ("animation", ["animation": ["id": 4]]),
        ] {
            let malformed = namedDocument(key: "gain", condition: "mode", pause: "pause", play: "play",
                source: source, resource: "audio/named-admission.wav", extra: extra)
            let parsed = SceneScriptBindingIRParser.parse(document: malformed)
            facts["named-reader-reject-" + name] = parsed.bindings.isEmpty && !parsed.diagnostics.isEmpty
        }
        let definitions = SceneScriptScalarProgram.projectedDefinitions(descriptor: scene, scriptBindings: [valid])
        let keys = SceneScriptScalarProgram.projectedVolumePropertyKeys(descriptor: scene, scriptBindings: [valid])
        let simpleRoot = document(source: source, value: 0.2, extra: ["user": "gain"])
        let simple = try candidate(namedScene(simpleRoot), bindings(simpleRoot), sound: plan,
            resolvedVolumes: ["gain": 0.8]).scalarProgram
        let simpleValue = simple.evaluate(inputs: [target: .scalar(0.8)], frame: frame)
        facts["named-without-declared-properties"] = simple.bindings.count == 1
            && simpleValue.failures.isEmpty && scalar(simpleValue.values[target], is: 0.5)
        facts["named-late-proof-raw-differs-from-resolved"] = plan.sceneScriptVolumeConsumerTargets(
            for: definitions, namedPropertyKeys: keys, resolvedPropertyVolumes: ["gain": 0.8]) == [target]
        for (name, sound, named, resolved) in [
            ("missing-key-proof", plan, [:], ["gain": 0.8]),
            ("wrong-key-proof", plan, [target: "other"], ["gain": 0.8]),
            ("wrong-target-proof", plan, [.layer(layerID: 999, field: .volume): "gain"], ["gain": 0.8]),
            ("missing-resolved-proof", plan, keys, [:]),
            ("wrong-resolved-proof", plan, keys, ["gain": 0.4]),
            ("nonfinite-resolved-proof", plan, keys, ["gain": Double.nan]),
            ("wrong-source-property", try prepared(audio: audio, volume: 0.8, property: "other"), keys, ["gain": 0.8]),
            ("missing-resource", try prepared(audio: audio, volume: 0.8, property: "gain", available: false), keys, ["gain": 0.8]),
        ] {
            facts["named-late-reject-" + name] = sound.sceneScriptVolumeConsumerTargets(for: definitions,
                namedPropertyKeys: named, resolvedPropertyVolumes: resolved).isEmpty
            if named == keys {
                let excluded = try candidate(scene, [valid], sound: sound, resolvedVolumes: resolved)
                facts["named-late-no-owner-" + name] = excluded.scalarProgram.bindings.isEmpty
                    && excluded.constructionReport.expectedScalarTargets.isEmpty
                    && excluded.constructionReport.instantiatedScalarTargets.isEmpty
            }
        }
        let missing = try candidate(scene, [valid], sound: plan)
        facts["named-no-proof-owner-never-constructed"] = missing.scalarProgram.bindings.isEmpty
            && missing.constructionReport.expectedScalarTargets.isEmpty
        return facts
    }

    static func admissionFacts(audio: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let scene = SceneRenderDescriptor(layers: [layer()])
        let sound = try prepared(audio: audio)
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
            ("outer-user-without-descriptor-identity", scene, bindings(document(extra: ["user": "gain"])), []),
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
        let random = try prepared(audio: audio, mode: "random", minimumTime: 1, maximumTime: 2)
        let randomCandidate = try candidate(scene, [valid], sound: random)
        facts["random-prepared-volume-consumer"] = random.sceneScriptVolumeConsumerTargets(for: definitions) == [target]
            && randomCandidate.constructionReport.instantiatedScalarTargets == [target]
            && randomCandidate.scalarProgram.bindings.count == 1
        for (name, plan) in [
            ("missing-resource", try prepared(audio: audio, available: false)),
            ("seed-conflict", try prepared(audio: audio, volume: seed.nextUp)),
            ("direct-property-conflict", try prepared(audio: audio, property: "gain")),
            ("unsupported-format", try prepared(audio: audio, resource: "audio/unsupported.webm")),
            ("random-interval", try prepared(audio: audio, mode: "random")),
            ("unknown-mode", try prepared(audio: audio, mode: "once")),
            ("spatial", try prepared(audio: audio, spatial: true)),
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
        let missing = try prepared(audio: audio, available: false)
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
        let plan = try SceneSoundPlaybackProgram.compile(document: .init(objects: [
            .init(id: 16, sound: sound(resource: "audio/numeric.wav")),
            .init(id: 18, sound: sound(resource: "audio/numeric.wav", volume: 0.1))]),
            resourceView: .init(resourcesByReference: ["audio/numeric.wav": audio]), privateCacheDirectory: FileManager.default.temporaryDirectory)
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
        let plan = try SceneSoundPlaybackProgram.compile(document: .init(objects: [
            .init(id: 16, sound: sound(resource: "audio/lifecycle.wav")),
            .init(id: 18, sound: sound(resource: "audio/lifecycle.wav", volume: 0.1))]),
            resourceView: .init(resourcesByReference: ["audio/lifecycle.wav": audio]), privateCacheDirectory: FileManager.default.temporaryDirectory)
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

    // This checks the real Scalar/C mode, independently of Session publication.
    static func propertyRefreshFacts(audio: URL) throws -> [String: Bool] {
        let peer = SceneDynamicTarget.layer(layerID: 18, field: .volume)
        let resource = "audio/property-refresh.wav"
        let source = """
        let updates=0, ticks=0, media=0, changes=0, jobs=0;
        export function init(v) { Promise.resolve().then(()=>{jobs++;}); return v; }
        export function applyUserProperties(e) {
            changes++;
            if(changes===1) engine.setTimeout(()=>{ticks++;},0);
            Promise.resolve().then(()=>{jobs++;});
        }
        export function mediaPlaybackChanged(e) { media+=1; }
        export function mediaPropertiesChanged(e) { media+=2; }
        export function mediaThumbnailChanged(e) { media+=4; }
        export function mediaTimelineChanged(e) { media+=8; }
        export function update(v) {
            updates++; Promise.resolve().then(()=>{jobs++;});
            return (updates+ticks*10+media*100+changes*10000+jobs*100000)/10000000;
        }
        """
        let scene = SceneRenderDescriptor(layers: [layer(), layer(18, index: 1)])
        let root: [String: Any] = ["objects": [16, 18].map { id in
            ["id": id, "sound": [resource], "volume": ["script": source, "value": seed]]
                as [String: Any]
        }]
        let soundPlan = try SceneSoundPlaybackProgram.compile(document: .init(objects: [16, 18].map {
            .init(id: $0, sound: sound(resource: resource))
        }), resourceView: .init(resourcesByReference: [resource: audio]), privateCacheDirectory: FileManager.default.temporaryDirectory)
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "mode": ["type": "slider", "value": 0, "min": 0, "max": 1]])
        let accepted = try candidate(scene, bindings(root), sound: soundPlan,
            properties: catalog.definitions)
        let program = accepted.scalarProgram
        var facts: [String: Bool] = [:]
        let domain = accepted.domain!
        let originTarget = SceneDynamicTarget.layer(layerID: 18, field: .origin)
        let scaleTarget = SceneDynamicTarget.layer(layerID: 18, field: .scale)
        let base = snapshot([
            .init(target: originTarget, valueType: .vector3, authoredValue: .vector3(0, 0, 0)),
            .init(target: scaleTarget, valueType: .vector3, authoredValue: .vector3(1, 1, 1)),
        ], script: [originTarget: .vector3(37, -12, 5), scaleTarget: .vector3(2, 3, 4)])
        try domain.publishLayerSnapshot(base, descriptor: scene,
            soundPlaybackSnapshots: [16: false, 18: false])
        let reader = try SceneScriptValueOwner(domain: domain, source: """
            export function update(v) {
                const peer=thisScene.getLayerByID(18);
                return new Vec3(peer.origin.x,peer.origin.y,
                    peer.scale.x+(thisLayer.isPlaying()?10:0));
            }
            """, target: .layer(layerID: 16, field: .origin), effectNames: [],
            generation: 11, budget: .default)
        func readPeer() throws -> SceneDynamicValue {
            let value = try reader.evaluate(input: .vector3(0, 0, 0), frame: frame,
                scriptPropertiesJSON: "", userPropertiesJSON: "{}",
                expectedGeneration: 11, interruptBudget: nil).get().value
            reader.commitLayerMutations()
            return value
        }
        let fullRead = try readPeer()
        try domain.publishSoundPlaybackSnapshot(base, descriptor: scene,
            soundPlaybackSnapshots: [16: true, 18: false], catalogToken: domain.layerCatalogSignature!)
        let partialRead = try readPeer()
        domain.discardCommittedLayerSnapshot()
        facts["partial-sound-snapshot-preserves-dynamic-peer-origin-and-scale"] =
            fullRead == .vector3(37, -12, 2) && partialRead == .vector3(37, -12, 12)
        facts["partial-sound-snapshot-discard-restores-vm-mirror"] =
            try readPeer() == .vector3(37, -12, 2)
        let owner = program.bindings.first { $0.target == target }!
        let other = program.bindings.first { $0.target == peer }!
        let inputs: [SceneDynamicTarget: SceneDynamicValue] = [target: .scalar(seed), peer: .scalar(seed)]
        func timing(_ runtime: Double, _ delta: Double = 0) -> SceneScriptFrameInput {
            .init(timing: .init(wallDate: Date(timeIntervalSince1970: runtime),
                simulationFrameTime: delta, sceneTime: runtime), timeZone: TimeZone(secondsFromGMT: 0)!)
        }
        // Real callback pre-arms both owners while init is still pending. All
        // three primitive paths therefore encounter due work at a new runtime.
        for binding in program.bindings {
            _ = try binding.dispatchUserProperties(changedPropertiesJSON: "{\"mode\":0}",
                scriptPropertiesJSON: "", frame: timing(0), userPropertiesJSON: "{}").get()
            binding.commitLayerMutations()
        }
        let events = SceneScriptMediaFrameEvents(
            playback: .init(state: 1, generation: 7),
            properties: .init(title: "Owned title", artist: "Owned artist", generation: 7),
            thumbnail: .init(hasThumbnail: false, generation: 7),
            timeline: .init(position: 1, duration: 2, generation: 7))
        let observed = program.observeMediaEvents(events)
        let before = program.frameStateSnapshot()
        func mediaUnconsumed() -> Bool {
            let state = program.frameStateSnapshot()
            return state.observedMediaPlaybackEvent == before.observedMediaPlaybackEvent
                && state.observedMediaPropertiesEvent == before.observedMediaPropertiesEvent
                && state.observedMediaThumbnailEvent == before.observedMediaThumbnailEvent
                && state.observedMediaTimelineEvent == before.observedMediaTimelineEvent
                && state.consumedMediaPlaybackGenerations.isEmpty
                && state.consumedMediaPropertiesGenerations.isEmpty
                && state.consumedMediaThumbnailGenerations.isEmpty
                && state.consumedMediaTimelineGenerations.isEmpty
        }
        facts["refresh-fixture-two-real-owners-and-due-timers"] = accepted.constructionReport.isComplete
            && program.bindings.count == 2 && owner.needsInitialization && other.needsInitialization
            && mwx_scene_quickjs_owner_active_timer_count(owner.handle) == 1
            && mwx_scene_quickjs_owner_active_timer_count(other.handle) == 1
        let empty = program.evaluate(inputs: inputs, frame: timing(4),
            effectivePropertyValues: ["mode": .number(0)], propertyRevision: 0,
            propertyRefresh: true, mediaPlaybackEvent: .init(state: 0, generation: 8))
        facts["refresh-without-filter-does-not-observe-or-call-owners"] = empty.values.isEmpty
            && empty.failures.isEmpty && empty.ownerEffects.isEmpty && mediaUnconsumed()
            && owner.needsInitialization && other.needsInitialization
        let first = program.evaluate(inputs: inputs, frame: timing(5),
            effectivePropertyValues: ["mode": .number(0)], propertyRevision: 0,
            targetFilter: target, propertyRefresh: true, observedMediaEvents: observed)
        program.finalizeLayerMutations(committing: true)
        facts["refresh-init-property-update-drain-jobs-without-timer-or-media"] = first.failures.isEmpty
            && scalar(first.values[target], is: 0.0320001) && first.values[peer] == nil
            && mediaUnconsumed() && other.needsInitialization
            && mwx_scene_quickjs_owner_active_timer_count(owner.handle) == 1
            && mwx_scene_quickjs_owner_active_timer_count(other.handle) == 1
        let second = program.evaluate(inputs: inputs, frame: timing(6),
            effectivePropertyValues: ["mode": .number(1)], propertyRevision: 1,
            targetFilter: target, propertyRefresh: true, observedMediaEvents: observed)
        program.finalizeLayerMutations(committing: true)
        facts["refresh-advancing-runtime-zero-delta-keeps-peer-and-timer-frozen"] = second.failures.isEmpty
            && scalar(second.values[target], is: 0.0530002) && second.values[peer] == nil
            && mediaUnconsumed() && other.needsInitialization
            && mwx_scene_quickjs_owner_active_timer_count(owner.handle) == 1
        let resumed = program.evaluate(inputs: inputs, frame: timing(7, 0.1),
            effectivePropertyValues: ["mode": .number(1)], propertyRevision: 1,
            observedMediaEvents: observed)
        program.finalizeLayerMutations(committing: true)
        let consumed = program.frameStateSnapshot()
        let generations: [SceneDynamicTarget: UInt64] = [target: 7, peer: 7]
        facts["refresh-normal-mode-consumes-each-pending-event-and-timer-once"] = resumed.failures.isEmpty
            && scalar(resumed.values[target], is: 0.0631513)
            && scalar(resumed.values[peer], is: 0.0321511)
            && consumed.consumedMediaPlaybackGenerations == generations
            && consumed.consumedMediaPropertiesGenerations == generations
            && consumed.consumedMediaThumbnailGenerations == generations
            && consumed.consumedMediaTimelineGenerations == generations
            && mwx_scene_quickjs_owner_active_timer_count(owner.handle) == 0
            && mwx_scene_quickjs_owner_active_timer_count(other.handle) == 0
        let repeated = program.evaluate(inputs: inputs, frame: timing(8, 0.1),
            effectivePropertyValues: ["mode": .number(1)], propertyRevision: 1,
            observedMediaEvents: observed)
        program.finalizeLayerMutations(committing: true)
        facts["refresh-normal-mode-does-not-replay-events-or-extra-peer-updates"] = repeated.failures.isEmpty
            && scalar(repeated.values[target], is: 0.0731514)
            && scalar(repeated.values[peer], is: 0.0421512)
        return facts
    }

    static func main() throws {
        let audio = URL(fileURLWithPath: CommandLine.arguments[1])
        var facts = try propertyFacts(audio: audio)
        facts.merge(try admissionFacts(audio: audio)) { _, latest in latest }
        facts.merge(try numericFacts(audio: audio)) { _, latest in latest }
        facts.merge(try lifecycleFacts(audio: audio)) { _, latest in latest }
        facts.merge(try namedFacts(audio: audio)) { _, latest in latest }
        facts.merge(try namedAdmissionFacts(audio: audio)) { _, latest in latest }
        facts.merge(try propertyRefreshFacts(audio: audio)) { _, latest in latest }
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
