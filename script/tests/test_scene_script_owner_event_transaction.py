"""Owner rejection retries event acknowledgements without replaying accepted peers."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import SCENE, compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 0.016, sceneTime: 1))
    static let events = """
        let count = 0;
        export function mediaThumbnailChanged(e) { count += 1; }
        export function mediaPlaybackChanged(e) { count += 10; }
        export function mediaPropertiesChanged(e) { count += 100; }
        export function mediaTimelineChanged(e) { count += 1000; }
        export function applyUserProperties(e) { count += 10000; }
        """
    static func descriptor() -> SceneRenderDescriptor {
        .init(layers: (1...3).map { id in .init(id: id, layerIndex: id-1,
            name: "layer\(id)", visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1],
            scaleHasScript: nil, alpha: 1, effects: [], contentKind: "text", text: "0",
            textStyle: .init(fontPath: nil, colorRGB: nil, pointSize: 20), sizeWH: [100,100]) })
    }
    static func binding(_ id: Int, _ field: String, _ source: String) -> SceneScriptBindingIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: id-1, objectID: id,
            effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(id-1), .key(field)], properties: [:],
            authoredValue: field == "alpha" ? .number(1) : .string(field == "text" ? "0" : field == "scale" ? "1 1 1" : "0 0 0"),
            valueType: field == "alpha" ? .number : .string, wrapperKeys: ["script", "value"])
    }
    static func number(_ v: SceneDynamicValue?) -> Double {
        switch v { case let .scalar(x)?: (x * 100000).rounded(); case let .vector3(x,_,_)?: x;
        case let .string(x)?: Double(x) ?? -999; default: -999 }
    }
    static func propertyEvents() throws -> [String: Any] {
        let alpha = SceneDynamicTarget.layer(layerID: 1, field: .alpha)
        let peer = SceneDynamicTarget.layer(layerID: 1, field: .origin)
        let foreign = SceneDynamicTarget.layer(layerID: 2, field: .alpha)
        let sinkAlpha = SceneDynamicTarget.layer(layerID: 3, field: .alpha)
        let sinkOrigin = SceneDynamicTarget.layer(layerID: 3, field: .origin)
        var out: [String: Any] = [:]
        for (label, expression) in [("finite", "Number(1)/4"), ("nan", "NaN"),
                                    ("negative", "-Infinity"), ("positive", "Infinity")] {
            let d = descriptor()
            let source = """
                let count=0;
                export function init(){engine.setTimeout(()=>{
                  thisLayer.alpha=.6;thisLayer.angles=new Vec3(0,0,1);},0);}
                export function animationEvent(e,v) {
                  if(e.name!=='\(label)'||e.frame!==30||typeof v!=='number')throw Error('typed event');
                  count++;thisLayer.alpha=.75;thisLayer.scale=new Vec3(2,3,4);
                  thisScene.getLayerByID(3).alpha=count/10;
                  if(count===2){thisLayer.alpha=.5;return;}
                  return \(expression);
                }
                """
            let bindings = [binding(1, "alpha", source), binding(1, "origin", """
                let count=0;export function animationEvent(e,v){
                  if(e.name!=='\(label)'||e.frame!==30||!(v instanceof Vec3))throw Error('peer value');
                  thisScene.getLayerByID(3).origin=new Vec3(++count,0,0);
                  return new Vec3(count,2,3);
                }
                """), binding(2, "alpha", """
                let called=false;export function animationEvent(){called=true;return .9;}
                export function update(v){if(called)throw Error('foreign event');return v;}
                """)]
            let candidate = try SceneScriptQuickJSProgramCandidate.compile(
                authoredDescriptor: d, runtimeDescriptor: d, scriptBindings: bindings,
                vectorProjection: SceneScriptVectorProgram.project(descriptor: d, scriptBindings: bindings),
                userPropertyDefinitions: [], timelineTargets: [alpha, peer], scalarExcludedTargets: [],
                stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 1)
            guard let domain = candidate.domain else { fatalError("event domain") }
            let coordinator = SceneScriptMediaFrameCoordinator(vectorProgram: candidate.vectorProgram,
                stringProgram: candidate.stringProgram, scalarProgram: candidate.scalarProgram)
            let definitions = candidate.vectorProgram.definitions + candidate.scalarProgram.definitions
            let initial = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                definitions: definitions).snapshot
            try domain.publishLayerSnapshot(initial, descriptor: d)
            let prime = coordinator.initialize(vectorInputs: [peer: .vector3(0,0,0)], stringInputs: [:],
                scalarInputs: [alpha: .scalar(1), foreign: .scalar(1)], effectivePropertyValues: [:],
                frame: .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 0, sceneTime: 0)), userPropertiesJSON: "{}", audioSpectrum: .silent)
            candidate.vectorProgram.finalizeLayerMutations(committing: true)
            candidate.scalarProgram.finalizeLayerMutations(committing: true)
            coordinator.finalizeInitializations()
            let runtime = SceneScriptDynamicLayerRuntime(descriptor: d, authoredMutationLayerIDs: [1,2,3])
            func publish() throws {
                try domain.publishAnimationEvents([], failures: [:], timelineEvents: [
                    .init(target: .layer(layerID: 1, field: .scale), name: label, frame: 30)])
            }
            func evaluate() -> SceneScriptMediaFrameCoordinatorResult {
                coordinator.evaluate(vectorInputs: [peer: .vector3(0,0,0)], stringInputs: [:],
                    scalarInputs: [alpha: .scalar(1), foreign: .scalar(1)], effectivePropertyValues: [:],
                    frame: frame, userPropertiesJSON: "{}", events: .empty, audioSpectrum: .silent)
            }
            func finalize(_ rejected: Set<SceneDynamicTarget> = []) {
                candidate.vectorProgram.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejected)
                candidate.scalarProgram.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejected)
            }
            func matches(_ value: SceneDynamicValue?) -> Bool {
                guard case let .scalar(number)? = value else { return false }
                switch label {
                case "nan": return number.isNaN
                case "negative": return number == -.infinity
                case "positive": return number == .infinity
                default: return number == 0.25
                }
            }
            try publish()
            let result = evaluate()
            let admitted = runtime.preflightOwnerEffectsToFixedPoint(result.ownerEffects,
                excludingOwners: Set(result.scalar.failures.keys).union(result.vector.failures.keys)) { _, _ in [] }
            runtime.commit(admitted.admission.layerPlan)
            let scriptValues = result.scalar.valuesForAdmission(timelineValues: [alpha: .scalar(0.9)], excluding: [])
                .merging(result.vector.valuesForAdmission(timelineValues: [peer: .vector3(9,9,9)], excluding: [])) { _, new in new }
            var transaction = SceneEvaluationTransaction()
            let pending = transaction.prepare(frameIndex: 2,
                resolution: SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 1,
                    definitions: definitions, sceneScriptValues: scriptValues))
            transaction.commit(pending)
            finalize()
            var facts: [String: Bool] = [
                "owners": candidate.scalarProgram.bindings.count == 2 && candidate.vectorProgram.bindings.count == 1,
                "callbacksAccepted": result.scalar.failures.isEmpty && result.vector.failures.isEmpty,
                "primed": prime.failures.isEmpty,
                "typedReturn": matches(result.scalar.values[alpha]),
                "returnIsWriter": !result.scalar.timelineInputTargets.contains(alpha),
                "snapshotReturn": matches(transaction.previousValue(for: alpha)),
                "sameLayerPeer": result.vector.values[peer] == .vector3(1,2,3),
                "peerIsWriter": !result.vector.timelineInputTargets.contains(peer),
                "foreignQuiet": result.scalar.values[foreign] == .scalar(1),
                "otherFields": runtime.snapshot().authoredLayerValues[.layer(layerID: 1, field: .scale)] == .vector3(2,3,4),
                "priorCallbackField": runtime.snapshot().authoredLayerValues[.layer(layerID: 1, field: .angles)] != nil,
                "otherTarget": runtime.snapshot().authoredLayerValues[sinkAlpha] == .scalar(0.1),
                "queuesCommitted": candidate.scalarProgram.bindings.allSatisfy {
                    !mwx_scene_quickjs_owner_has_pending_animation_events($0.handle) }
                    && !mwx_scene_quickjs_owner_has_pending_animation_events(candidate.vectorProgram.bindings[0].owner.handle)]
            if label == "finite" {
                var current = transaction.previousValues(for: [alpha, peer, foreign])
                current.merge(runtime.snapshot().authoredLayerValues) { _, new in new }
                let next = SceneDynamicSnapshotResolver().resolve(frameIndex: 3, generation: 2,
                    definitions: definitions, sceneScriptValues: current).snapshot
                try domain.publishLayerSnapshot(next, descriptor: d)
                let getter = try SceneScriptValueOwner(domain: domain,
                    source: "export function update(){return thisScene.getLayerByID(1).alpha;}",
                    target: .layer(layerID: 3, field: .brightness), valueType: .scalar,
                    effectNames: [], generation: 1, budget: .default)
                facts["firstGetter"] = try getter.evaluate(input: .scalar(1), frame: frame,
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
                    interruptBudget: nil).get().value == .scalar(0.25)
                getter.commitLayerMutations()
                try publish()
                let checkpoint = candidate.scalarProgram.frameStateSnapshot()
                let rejected = evaluate()
                facts["laterSetter"] = rejected.scalar.values[alpha] == .scalar(0.5)
                let partial = runtime.preflightOwnerEffectsToFixedPoint(rejected.ownerEffects,
                    excludingOwners: [alpha]) { _, _ in [] }
                runtime.commit(partial.admission.layerPlan)
                candidate.scalarProgram.restoreFrameState(checkpoint, rejectedOwnerTargets: [alpha])
                finalize([alpha])
                facts["rejectedAlphaPending"] = candidate.scalarProgram.bindings.contains {
                    $0.target == alpha && mwx_scene_quickjs_owner_has_pending_animation_events($0.handle) }
                facts["peerCommittedOnce"] = runtime.snapshot().authoredLayerValues[sinkOrigin] == .vector3(2,0,0)
                facts["rejectedJournalAbsent"] = runtime.snapshot().authoredLayerValues[sinkAlpha] == .scalar(0.1)
                let retry = evaluate()
                let accepted = runtime.preflightOwnerEffectsToFixedPoint(retry.ownerEffects) { _, _ in [] }
                runtime.commit(accepted.admission.layerPlan)
                finalize()
                facts["retryOwnJournal"] = runtime.snapshot().authoredLayerValues[sinkAlpha] == .scalar(0.3)
                facts["peerNotReplayed"] = runtime.snapshot().authoredLayerValues[sinkOrigin] == .vector3(2,0,0)
                facts["retryWriter"] = retry.scalar.values[alpha] == .scalar(0.25)
                    && !retry.scalar.timelineInputTargets.contains(alpha)
            }
            out[label] = ["facts": facts, "failures": result.scalar.failures.map { $0.value.code }]
        }
        return out
    }
    static func singleAnimations() throws -> [String: Any] {
        var out: [String: Any] = [:]
        for (mode, sourceName) in [("normal", "owned motion"), ("renamed", "另一动作"),
                                   ("throw", "throw motion"), ("badargument", "finite motion"),
                                   ("admission", "reference motion")] {
            func animation(_ id: Int, _ name: String, reference: Bool = false) -> SceneMdlPuppetAnimation {
                .init(id: id, name: name, mode: "single", framesPerSecond: 30, frameCount: 30,
                    transformsByBone: [Array(repeating: .init(translation: .zero, rotation: .zero,
                        scale: SIMD3<Float>(repeating: 1)), count: 31)],
                    transformTrackStates: [reference ? .referenceCandidate : .sampled])
            }
            let dense = animation(812, mode == "admission" ? "peer motion" : sourceName)
            let requested = mode == "admission" ? animation(813, sourceName, reference: true) : dense
            let base = ScenePuppetAnimationLayer(id: 89, animationID: 812, name: "separate base",
                additive: false, blend: 1, blendIn: nil, blendOut: nil, blendTime: nil,
                rate: 1, visible: true, visibilityBinding: nil)
            let authored = mode == "admission" ? [base] : []
            let baseline = authored.count
            let d = SceneRenderDescriptor(layers: (1...3).map { id in .init(id: id, layerIndex: id-1,
                name: "layer\(id)", visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1],
                scaleHasScript: nil, alpha: 1, effects: [],
                contentKind: id == 3 ? "image" : "text", text: id == 3 ? nil : "0",
                textStyle: .init(fontPath: nil, colorRGB: nil, pointSize: 20), sizeWH: [100,100],
                puppetAnimationLayers: id == 3 ? authored : []) })
            let puppet = ScenePuppetAnimationPlaybackRuntime()
            let selection = ScenePuppetAnimationSelection(clips: authored.map { .init(layer: $0, animation: dense) },
                composition: .singleAbsolute)
            guard case .success = puppet.register(layerID: 3, selection: selection, authoredLayers: authored,
                availableSingleAnimations: mode == "admission" ? [dense, requested] : [dense]) else {
                fatalError("prepared Single source")
            }
            let initialPuppet = puppet.advance(frameIndex: 1, sceneTime: 10, dynamicValues: .empty(frameIndex: 1))
            func source(_ name: String, _ heldFrame: Int, _ tail: String, _ write: String) -> String {
                """
                let fired=false,held;
                export function update(v) {
                  if(fired){try{if(held.getFrame()!==\(heldFrame))throw Error('held');return .6;}
                    catch(e){return .3;}}
                  fired=true;
                  const image=thisScene.getLayerByID(3);
                  if(image.getAnimationLayerCount()!==\(baseline))throw Error('baseline');
                  held=image.playSingleAnimation('\(name)');
                  if(held.fps!==30||held.frameCount!==30||held.duration!==1||held.name!=='\(name)')throw Error('metadata');
                  if(!held.isPlaying()||held.getFrame()!==0||!held.visible||held.rate!==1||held.blend!==1)throw Error('birth');
                  if(image.getAnimationLayerCount()!==\(baseline+1))throw Error('birth count');
                  held.pause();held.setFrame(\(heldFrame));
                  if(held.isPlaying()||held.getFrame()!==\(heldFrame))throw Error('provisional controls');
                  if(image.getAnimationLayer(\(baseline)).getFrame()!==\(heldFrame))throw Error('index lookup');
                  if(image.getAnimationLayer('\(name)').getFrame()!==\(heldFrame))throw Error('name lookup');
                  \(write)
                  \(tail)
                  return .25;
                }
                """
            }
            let tail = mode == "throw" ? "throw Error('after creation');" :
                mode == "badargument" ? "held.setFrame(NaN);" : ""
            let bindings = [binding(1, "alpha", source(sourceName, 15, tail,
                "thisScene.getLayerByID(3).scale=new Vec3(2,3,4);")),
                binding(2, "alpha", source(dense.name, 7, "",
                "thisScene.getLayerByID(3).origin=new Vec3(7,8,9);"))]
            let candidate = try SceneScriptQuickJSProgramCandidate.compile(
                authoredDescriptor: d, runtimeDescriptor: d, scriptBindings: bindings,
                vectorProjection: SceneScriptVectorProgram.project(descriptor: d, scriptBindings: bindings),
                userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [],
                stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 1)
            guard let domain = candidate.domain else { fatalError("Single domain") }
            domain.bindPuppetAnimationSources(puppet)
            try domain.publishPuppetAnimationSnapshot(initialPuppet.animationSnapshots)
            let creator = SceneDynamicTarget.layer(layerID: 1, field: .alpha)
            let peer = SceneDynamicTarget.layer(layerID: 2, field: .alpha)
            let coordinator = SceneScriptMediaFrameCoordinator(vectorProgram: candidate.vectorProgram,
                stringProgram: candidate.stringProgram, scalarProgram: candidate.scalarProgram)
            let initial = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                definitions: candidate.scalarProgram.definitions).snapshot
            try domain.publishLayerSnapshot(initial, descriptor: d)
            _ = coordinator.initialize(vectorInputs: [:], stringInputs: [:],
                scalarInputs: [creator: .scalar(1), peer: .scalar(1)], effectivePropertyValues: [:],
                frame: frame, userPropertiesJSON: "{}", audioSpectrum: .silent)
            candidate.scalarProgram.finalizeLayerMutations(committing: true)
            coordinator.finalizeInitializations()
            let checkpoint = candidate.scalarProgram.frameStateSnapshot()
            func evaluate() -> SceneScriptMediaFrameCoordinatorResult {
                coordinator.evaluate(vectorInputs: [:], stringInputs: [:],
                    scalarInputs: [creator: .scalar(1), peer: .scalar(1)], effectivePropertyValues: [:],
                    frame: frame, userPropertiesJSON: "{}", events: .empty, audioSpectrum: .silent)
            }
            let result = evaluate()
            let layers = SceneScriptDynamicLayerRuntime(descriptor: d, authoredMutationLayerIDs: [1,2,3])
            let admitted = layers.preflightOwnerEffectsToFixedPoint(result.ownerEffects,
                excludingOwners: Set(result.scalar.failures.keys)) { owners, _ in
                Set(owners.compactMap { owner in
                    if case .failure = puppet.validate(owner.puppetAnimationCommands, frameIndex: 1) {
                        return owner.ownerTarget
                    }
                    return nil
                })
            }
            layers.commit(admitted.admission.layerPlan)
            let commands = admitted.admission.admittedEffects.flatMap(\.puppetAnimationCommands)
            let applied: Bool
            if case .success = puppet.apply(commands, frameIndex: 1) { applied = true } else { applied = false }
            let rejected = admitted.externallyRejectedOwners
            candidate.scalarProgram.restoreFrameState(checkpoint, rejectedOwnerTargets: rejected)
            candidate.scalarProgram.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejected)
            let acceptedCreator = mode == "normal" || mode == "renamed"
            let current = puppet.advance(frameIndex: 2, sceneTime: 10.25, dynamicValues: .empty(frameIndex: 2))
            try domain.publishPuppetAnimationSnapshot(current.animationSnapshots)
            let next = evaluate()
            candidate.scalarProgram.finalizeLayerMutations(committing: true)
            let created = current.animationSnapshots.filter {
                if case .created = $0.identity.instance { return true }
                return false
            }
            out[mode] = [
                "facts": [
                    "vmOutcome": (result.scalar.failures[creator] != nil) == (mode == "throw" || mode == "badargument"),
                    "peerHealthy": result.scalar.failures[peer] == nil,
                    "creatorAdmission": admitted.admission.admittedEffects.contains { $0.ownerTarget == creator } == acceptedCreator,
                    "applied": applied,
                    "count": current.animationSnapshots.count == baseline + (acceptedCreator ? 2 : 1),
                    "independentBirths": Set(created.map(\.identity)).count == (acceptedCreator ? 2 : 1),
                    "pausedFrames": created.allSatisfy { !$0.isPlaying }
                        && created.map(\.currentFrame).sorted() == (acceptedCreator ? [7,15] : [7]),
                    "creatorJournal": (layers.snapshot().authoredLayerValues[.layer(layerID: 3, field: .scale)] != nil) == acceptedCreator,
                    "peerJournal": layers.snapshot().authoredLayerValues[.layer(layerID: 3, field: .origin)] == .vector3(7,8,9),
                    "committedHandle": next.scalar.values[peer] == .scalar(0.6),
                    "discardedHandle": mode != "admission" || next.scalar.values[creator] == .scalar(0.3),
                    "sameCadenceFrozen": initialPuppet.animationSnapshots.count == baseline
                ], "failures": result.scalar.failures.map { $0.value.code }]
        }
        return out
    }
    static func exercise(
        targets: [SceneDynamicTarget],
        capture: () -> SceneScriptProgramFrameState,
        evaluate: (UInt64, UInt64) -> [SceneDynamicTarget: SceneDynamicValue],
        restore: (SceneScriptProgramFrameState, Set<SceneDynamicTarget>?) -> Void,
        finalize: (Bool, Set<SceneDynamicTarget>) -> Void
    ) -> [[Double]] {
        var values: [[Double]] = []
        func run(_ event: UInt64, _ property: UInt64) {
            let result = evaluate(event, property)
            values.append(targets.map { number(result[$0]) })
        }
        let first = capture()
        run(1, 1)
        restore(first, [targets[0]])
        finalize(true, [targets[0]])
        run(1, 1) // first-event acknowledgement absent in snapshot must be removed
        finalize(true, [])
        run(1, 1) // accepted peer and retried owner now remain quiet
        finalize(true, [])
        let prior = capture()
        run(2, 2)
        restore(prior, [targets[0]])
        finalize(true, [targets[0]])
        run(2, 2) // preserve prior generation/revision while retrying the latest
        finalize(true, [])
        run(1, 2) // observed watermark must still reject stale media input
        finalize(true, [])
        let dropped = capture()
        run(3, 3)
        restore(dropped, [targets[0]])
        restore(dropped, nil) // whole-frame discard still restores every target
        finalize(false, [])
        run(3, 3)
        finalize(true, [])
        return values
    }
    static func main() throws {
        var out: [String: Any] = [:]
        out["propertyEvents"] = try propertyEvents()
        out["singleAnimations"] = try singleAnimations()
        let d = descriptor()
        for family in ["scalar", "string", "vector", "sameLayer"] {
            let field = family == "scalar" ? "alpha" : family == "string" ? "text" : "origin"
            let output = family == "scalar" ? "count / 100000" : family == "string" ? "String(count)" : "new Vec3(count,0,0)"
            let source = events + "\nexport function update(v) { return " + output + "; }"
            let ids = family == "sameLayer" ? [1,1] : [1,2]
            let bindings = ids.enumerated().map { i, id in binding(id,
                family == "sameLayer" && i == 1 ? "scale" : field, source) }
            var d = descriptor()
            let domain = try SceneScriptQuickJSDomain()
            try domain.configureLayerCatalog(d)
            let targets: [SceneDynamicTarget] = ids.enumerated().map { i, id in
                if family == "scalar" { return .layer(layerID: id, field: .alpha) }
                if family == "string" { return .text(layerID: id, field: .content) }
                return .layer(layerID: id, field: family == "sameLayer" && i == 1 ? .scale : .origin)
            }
            let properties: [SceneUserPropertyDefinition] = [
                .init(key: "mode", title: "Mode", kind: .slider, runtimeType: "slider",
                      order: 0, index: nil, minimumValue: 0, maximumValue: 10,
                      stepValue: 1, allowsFractionalValues: false, fractionalPrecision: nil,
                      displayCondition: nil, defaultValue: .number(0), options: [])]
            func thumb(_ g: UInt64) -> SceneScriptMediaThumbnailEventInput { .init(hasThumbnail: false, generation: g) }
            func playback(_ g: UInt64) -> SceneScriptMediaPlaybackEventInput { .init(state: 1, generation: g) }
            func metadata(_ g: UInt64) -> SceneScriptMediaPropertiesEventInput { .init(title: "title", artist: "artist", generation: g) }
            func timeline(_ g: UInt64) -> SceneScriptMediaTimelineEventInput { .init(position: 1, duration: 2, generation: g) }
            if family == "scalar" {
                let p = SceneScriptScalarProgram.compile(domain: domain, descriptor: d,
                    scriptBindings: bindings, userPropertyDefinitions: properties)
                out[family+"Owners"] = p.bindings.count
                out[family] = exercise(targets: targets, capture: p.frameStateSnapshot,
                    evaluate: { g, r in p.evaluate(inputs: Dictionary(uniqueKeysWithValues: targets.map { ($0, .scalar(0)) }),
                        frame: frame, effectivePropertyValues: ["mode": .number(Double(r))], propertyRevision: r,
                        mediaThumbnailEvent: thumb(g), mediaPlaybackEvent: playback(g),
                        mediaPropertiesEvent: metadata(g), mediaTimelineEvent: timeline(g)).values },
                    restore: { p.restoreFrameState($0, rejectedOwnerTargets: $1) },
                    finalize: { p.finalizeLayerMutations(committing: $0, rejectedOwnerTargets: $1) })
            } else if family == "string" {
                let p = SceneScriptStringProgram.compile(domain: domain, descriptor: d,
                    scriptBindings: bindings, userPropertyDefinitions: properties, generation: 1)
                out[family+"Owners"] = p.bindings.count
                out[family] = exercise(targets: targets, capture: p.frameStateSnapshot,
                    evaluate: { g, r in p.evaluate(inputs: Dictionary(uniqueKeysWithValues: targets.map { ($0, .string("0")) }),
                        effectivePropertyValues: ["mode": .number(Double(r))], propertyRevision: r, frame: frame,
                        mediaThumbnailEvent: thumb(g), mediaPlaybackEvent: playback(g),
                        mediaPropertiesEvent: metadata(g), mediaTimelineEvent: timeline(g)).values },
                    restore: { p.restoreFrameState($0, rejectedOwnerTargets: $1) },
                    finalize: { p.finalizeLayerMutations(committing: $0, rejectedOwnerTargets: $1) })
            } else {
                let p = SceneScriptVectorProgram.compile(domain: domain, descriptor: d,
                    scriptBindings: bindings, userPropertyDefinitions: properties, generation: 1)
                out[family+"Owners"] = p.bindings.count
                out[family] = exercise(targets: targets, capture: p.frameStateSnapshot,
                    evaluate: { g, r in p.evaluate(inputs: Dictionary(uniqueKeysWithValues: targets.map { ($0, .vector3(0,0,0)) }),
                        effectivePropertyValues: ["mode": .number(Double(r))], frame: frame, propertyRevision: r,
                        mediaThumbnailEvent: thumb(g), mediaPlaybackEvent: playback(g),
                        mediaPropertiesEvent: metadata(g), mediaTimelineEvent: timeline(g)).values },
                    restore: { p.restoreFrameState($0, rejectedOwnerTargets: $1) },
                    finalize: { p.finalizeLayerMutations(committing: $0, rejectedOwnerTargets: $1) })
            }
        }
        // Real cursor success followed by update failure on the same borrowed VM owner.
        let source = """
            export function cursorMove(e) { thisScene.getLayerByID(3).origin = new Vec3(99,0,0); }
            export function update(v) { return {}; }
            """
        let b = binding(1, "origin", source)
        let peer = binding(2, "origin", "export function update(v) { thisScene.getLayerByID(3).alpha = 0.5; return new Vec3(7,0,0); }")
        let candidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: d, runtimeDescriptor: d, scriptBindings: [b,peer],
            vectorProjection: SceneScriptVectorProgram.project(descriptor: d, scriptBindings: [b,peer]),
            userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [],
            stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 1)
        let hit = SceneScriptCursorHit(layerID: 1, worldPosition: .zero, localPosition: .zero)
        let cursor = candidate.cursorProgram.dispatch(batch: .init(samples: [
            .init(hits: [1:hit], pointerPosition: .zero, primaryButtonIsDown: false),
            .init(hits: [1:hit], pointerPosition: .init(1,0), primaryButtonIsDown: false)
        ], overflowed: false), frame: frame, userPropertiesJSON: "{}")
        let a: SceneDynamicTarget = .layer(layerID: 1, field: .origin)
        let p: SceneDynamicTarget = .layer(layerID: 2, field: .origin)
        let update = candidate.vectorProgram.evaluate(inputs: [a: .vector3(0,0,0), p: .vector3(0,0,0)],
            effectivePropertyValues: [:], frame: frame)
        let runtime = SceneScriptDynamicLayerRuntime(descriptor: d, authoredMutationLayerIDs: [1,2,3])
        let admission = runtime.preflightOwnerEffectsToFixedPoint(cursor.ownerEffects + update.ownerEffects,
            excludingOwners: Set(cursor.failures.keys).union(update.failures.keys)) { _, _ in [] }
        runtime.commit(admission.admission.layerPlan)
        out["cursorEffects"] = cursor.ownerEffects.count
        out["updateFailure"] = update.failures[a]?.code ?? "none"
        out["failedCursorExcluded"] = admission.externallyRejectedOwners.contains(a)
        out["peerAdmitted"] = admission.admission.admittedEffects.contains { $0.ownerTarget == p }
        out["rejectedCursorPublished"] = runtime.snapshot().authoredLayerValues[.layer(layerID: 3, field: .origin)] != nil
        out["peerAlpha"] = number(runtime.snapshot().authoredLayerValues[.layer(layerID: 3, field: .alpha)])
        print(String(data: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''

class OwnerEventTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-owner-event-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        binary = compile_vector_harness(Path(cls.temp.name), HARNESS, "owner-event-transaction",
            extra_swift_sources=(SCENE / "Systems/Script/SceneScriptMediaFrameCoordinator.swift",
                                 SCENE / "Systems/Properties/SceneEvaluationTransaction.swift"),
            whole_module_optimization=True)
        run = subprocess.run([str(binary)], text=True, capture_output=True, check=True)
        cls.result = json.loads(run.stdout.strip().splitlines()[-1])

    def test_property_events_keep_real_return_domain_scope_and_owner_transactions(self):
        for label, result in self.result["propertyEvents"].items():
            with self.subTest(label=label):
                self.assertTrue(all(result["facts"].values()), result)

    def test_single_animation_uses_real_provisional_vm_journal_and_owner_admission(self):
        for mode, result in self.result["singleAnimations"].items():
            with self.subTest(mode=mode):
                self.assertTrue(all(result["facts"].values()), result)

    def test_rejected_first_event_retries_without_replaying_peer(self):
        for family in ("scalar", "string", "vector", "sameLayer"):
            with self.subTest(family=family):
                self.assertEqual(self.result[family+"Owners"], 2)
                self.assertEqual(self.result[family][:3], [[11111,11111], [22222,11111], [22222,11111]])

    def test_prior_generations_and_properties_retry_only_rejected_target(self):
        for family in ("scalar", "string", "vector", "sameLayer"):
            with self.subTest(family=family):
                self.assertEqual(self.result[family][3:5], [[33333,22222], [44444,22222]])

    def test_local_rejection_keeps_observed_event_watermark_monotonic(self):
        for family in ("scalar", "string", "vector", "sameLayer"):
            with self.subTest(family=family):
                self.assertEqual(self.result[family][5], [44444,22222])

    def test_local_then_whole_frame_rejection_retries_both_owners(self):
        for family in ("scalar", "string", "vector", "sameLayer"):
            with self.subTest(family=family):
                self.assertEqual(self.result[family][6:], [[55555,33333], [66666,44444]])

    def test_late_update_failure_retracts_cursor_effects_and_preserves_peer(self):
        self.assertEqual(self.result["cursorEffects"], 1)
        self.assertEqual(self.result["updateFailure"], "bad-return")
        self.assertTrue(self.result["failedCursorExcluded"])
        self.assertTrue(self.result["peerAdmitted"])
        self.assertFalse(self.result["rejectedCursorPublished"])
        self.assertEqual(self.result["peerAlpha"], 50000)
