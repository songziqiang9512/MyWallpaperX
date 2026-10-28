"""Behavioral initialization commit/retry gates through production Swift and C."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness, VM
from .test_scene_script_named_timeline import playback_preamble, TIMELINE_SOURCES
from .test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES as PUPPET_SOURCES

HARNESS = r'''
import Foundation

extension SceneFrameTiming { var frameIndex: UInt64 { UInt64(sceneTime) } }
// This gate exercises both animation consumers; unrelated providers must stay unreachable.
struct SceneTextureAnimationPlaybackRuntime {
    func validate(_ commands: [SceneTextureAnimationCommand], sceneTime: Double) -> Result<Void, NSError> {
        fatalError("unexpected texture validation")
    }
}
struct SceneVideoTextureSourceRegistry {
    func validate(_ commands: [SceneScriptMediaPlaybackCommand], timing: SceneFrameTiming) -> Result<Void, NSError> {
        fatalError("unexpected video validation")
    }
}
struct SceneSoundPlaybackRegistry {
    func validate(_ commands: [SceneScriptMediaPlaybackCommand]) -> Result<Void, NSError> {
        fatalError("unexpected sound validation")
    }
}

@main enum Harness {
    static func frame(_ runtime: Double) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1.0 / 60, sceneTime: runtime))
    }
    static func domain() throws -> SceneScriptQuickJSDomain {
        let d = try SceneScriptQuickJSDomain()
        try d.configureLayerCatalog(.init(layers: [.init(id: 1, layerIndex: 0,
            name: "subject", visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1],
            scaleHasScript: nil, alpha: 1, effects: [])]))
        return d
    }
    static func vector(_ d: SceneScriptQuickJSDomain, _ source: String,
                       boolean: Bool = false) throws -> SceneScriptValueOwner {
        try .init(domain: d, source: source,
            target: .layer(layerID: 1, field: boolean ? .visibility : .origin),
            valueType: boolean ? .bool : .vector3, effectNames: [],
            allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
    }
    static func value<T>(_ r: Result<T, SceneScriptScalarRuntimeFailure>) -> String {
        switch r { case .success: return "ok"; case let .failure(f): return f.code }
    }
    static func x(_ r: Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure>) -> Double {
        guard case let .success(e) = r, case let .vector3(x,_,_) = e.value else { return -999 }
        return x
    }
    static func evaluate(_ o: SceneScriptValueOwner, _ input: Double, _ time: Double = 1)
        -> Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure> {
        o.evaluate(input: .vector3(input, 0, 0), frame: frame(time),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil)
    }
    static func cohort(_ retryVariant: Bool) throws -> [String: Bool] {
        let vm = try SceneScriptQuickJSDomain()
        let tick = frame(1)
        let animatedAlphaTarget = SceneDynamicTarget.layer(layerID: 1, field: .alpha)
        let stringTarget = SceneDynamicTarget.text(layerID: 3, field: .content)
        let token = retryVariant ? "renamedSeed" : "seed"
        let textToken = retryVariant ? "renamedText" : "textSeed"
        let scalarSource = """
        export function init(value) {
            shared.calls=(shared.calls||0)+1; shared.\(token)=6;
            engine.setInterval(()=>{shared.ticks=(shared.ticks||0)+1;}, 10000);
            if (\(retryVariant ? "true" : "false") && shared.calls===1) return {};
            return value*0.5;
        }
        """
        let vectorSource = """
        export function init(value) { thisLayer.alpha=0.2; return value.add(new Vec3(1,0,0)); }
        export function update(value) {
            if(shared.\(token)!==6 || shared.\(textToken)!==7) throw new Error('update before all init');
            thisLayer.alpha=0.4; return new Vec3(value.x, shared.calls, shared.ticks||0);
        }
        """
        let textSource = "export function init(value){shared.\(textToken)=7;return value+'!';}"
        let scene = SceneRenderDescriptor(layers: [
            .init(id: 1, layerIndex: 0, name: "scalar", visible: true, originXYZ: [0,0,0],
                scaleXYZ: [1,1,1], alpha: 0.75, effects: []),
            .init(id: 2, layerIndex: 1, name: "vector", visible: true, originXYZ: [10,20,30],
                scaleXYZ: [1,1,1], alpha: 1, effects: []),
            .init(id: 3, layerIndex: 2, name: "text", visible: true, originXYZ: [0,0,0],
                scaleXYZ: [1,1,1], alpha: 1, effects: [], contentKind: "text",
                textScript: .init(source: textSource), text: "Placeholder",
                textStyle: .init(fontPath: nil, colorRGB: nil, pointSize: 12))])
        func binding(_ index: Int, _ key: String, _ source: String, _ authored: SceneJSONValue) -> SceneScriptBindingIR {
            .init(source: source, owner: .init(kind: .object, objectIndex: index, objectID: index+1,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                targetPath: [.key("objects"), .index(index), .key(key)], properties: [:],
                authoredValue: authored, valueType: key == "alpha" ? .number : .string,
                wrapperKeys: ["script", "value"])
        }
        let definitions = [binding(0, "alpha", scalarSource, .number(0.75)),
            binding(1, "origin", vectorSource, .string("10 20 30")),
            binding(2, "text", textSource, .string("Placeholder"))]
        let sources = retryVariant ? Array(definitions.reversed()) : definitions
        let vectors = SceneScriptVectorProgram.compile(domain: vm, descriptor: scene,
            scriptBindings: sources, userPropertyDefinitions: [], generation: 19)
        let strings = SceneScriptStringProgram.compile(domain: vm, descriptor: scene,
            scriptBindings: sources, generation: 19)
        let scalars = SceneScriptScalarProgram.compile(domain: vm, descriptor: scene,
            scriptBindings: sources, generation: 19)
        let scheduler = SceneScriptMediaFrameCoordinator(vectorProgram: vectors,
            stringProgram: strings, scalarProgram: scalars)
        let probe = try SceneScriptValueOwner(domain: vm,
            source: "export function update(v){return new Vec3(shared.calls||0,shared.\(textToken)||0,0);}",
            target: .layer(layerID: 1, field: .origin), effectNames: [], generation: 19, budget: .default)
        let preparedProbe = try probe.evaluate(input: .vector3(0,0,0), frame: tick,
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 19,
            interruptBudget: nil).get()
        probe.commitLayerMutations()
        let vTarget = SceneDynamicTarget.layer(layerID: 2, field: .origin)
        let vInputs: [SceneDynamicTarget: SceneDynamicValue] = [vTarget: .vector3(10,20,30)]
        let sInputs: [SceneDynamicTarget: SceneDynamicValue] = [animatedAlphaTarget: .scalar(0.75)]
        let tInputs: [SceneDynamicTarget: SceneDynamicValue] = [stringTarget: .string("Placeholder")]
        func start() -> (failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure], effects: [SceneScriptOwnerEffects]) {
            scheduler.initialize(vectorInputs: vInputs, stringInputs: tInputs, scalarInputs: sInputs,
                effectivePropertyValues: [:], frame: tick, userPropertiesJSON: "{}", audioSpectrum: .silent)
        }
        func update(_ failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure],
                    current: SceneScriptMediaFrameCoordinatorResult? = nil) -> SceneScriptMediaFrameCoordinatorResult {
            scheduler.evaluate(vectorInputs: current?.vector.values ?? vInputs,
                stringInputs: current?.string.values ?? tInputs, scalarInputs: current?.scalar.values ?? sInputs,
                effectivePropertyValues: [:], frame: tick, userPropertiesJSON: "{}",
                events: .init(playback: nil, properties: nil, thumbnail: nil, timeline: nil),
                audioSpectrum: .silent, initializationFailures: failures)
        }
        func finish(_ commit: Bool) {
            vectors.finalizeLayerMutations(committing: commit)
            strings.finalizeLayerMutations(committing: commit)
            scalars.finalizeLayerMutations(committing: commit)
            scheduler.finalizeInitializations()
        }
        let first = start(), firstValue = update(first.failures)
        let firstTimers = mwx_scene_quickjs_owner_active_timer_count(scalars.bindings[0].handle)
        finish(false)
        let rejectedTimers = mwx_scene_quickjs_owner_active_timer_count(scalars.bindings[0].handle)
        let retry = start(), retryValue = update(retry.failures)
        let retryTimers = mwx_scene_quickjs_owner_active_timer_count(scalars.bindings[0].handle)
        finish(true)
        let settled = start(), settledValue = update(settled.failures, current: retryValue)
        finish(true)
        let initWrites = retry.effects.flatMap(\.layerMutations).filter { $0.layerID == 2 }
        let updateWrites = retryValue.ownerEffects.flatMap(\.layerMutations).filter { $0.layerID == 2 }
        return [
            "prepareDidNotInitialize": preparedProbe.value == .vector3(0,0,0),
            "firstUpdateSawAllSeeds": firstValue.vector.values[vTarget] == .vector3(11,1,0),
            "failedInitNotRepeatedByUpdate": first.failures.count == (retryVariant ? 1 : 0)
                && firstValue.scalar.failures.count == (retryVariant ? 1 : 0),
            "badInitKeptValueFallback": (firstValue.scalar.values[animatedAlphaTarget] == nil) == retryVariant,
            "initValueCarriedOnce": retryValue.scalar.values[animatedAlphaTarget] == .scalar(0.375)
                && retryValue.string.values[stringTarget] == .string("Placeholder!")
                && retryValue.vector.values[vTarget] == .vector3(11,2,0),
            "initAndUpdateWritesPreserved": initWrites.count == 1 && initWrites.first?.alpha == 0.2
                && updateWrites.count == 1 && updateWrites.first?.alpha == 0.4,
            "timerRollbackAndRetry": firstTimers == (retryVariant ? 0 : 1)
                && rejectedTimers == 0 && retryTimers == 1,
            "settledDoesNotInitializeAgain": settled.effects.isEmpty && settled.failures.isEmpty
                && settledValue.vector.values[vTarget] == .vector3(11,2,0),
            "initOnlyKeepsAcceptedValue": settledValue.scalar.values[animatedAlphaTarget] == .scalar(0.375)
                && settledValue.string.values[stringTarget] == nil,
        ]
    }

    @MainActor static func mixedAnimationSeek(_ failure: String, renamed: Bool = false) throws -> [String: Bool] {
        let vm = try SceneScriptQuickJSDomain()
        let puppet = ScenePuppetAnimationPlaybackRuntime()
        let requested = renamed ? 29.25 : 29.0
        let timelineName = renamed ? "renamed blush" : "blush"
        let parentNames = (0..<4).map { renamed ? "renamed parent \($0)" : "parent \($0)" }
        let clips = (0..<4).map { index in
            ScenePuppetAnimationLayer(id: 101+index, animationID: 201+index,
                name: renamed ? "renamed clip \(index)" : "clip \(index)", additive: false,
                blend: 1, blendIn: false, blendOut: false, blendTime: 0, rate: 1,
                visible: false, visibilityBinding: nil)
        }
        var layers = (0..<6).map { index in
            SceneRenderDescriptor.Layer(id: index < 2 ? index+1 : index+9, layerIndex: index,
                name: index < 2 ? "controller \(index)" : parentNames[index-2], visible: true,
                originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: nil, alpha: 1, effects: [])
        }
        for index in clips.indices {
            layers[index+2].puppetAnimationLayers = [clips[index]]
            layers[index+2].imagePath = renamed ? "models/alternate-\(index).json" : "models/art-\(index).json"
            let track = (0...60).map { frame in SceneMdlPuppetAnimation.Transform(
                translation: SIMD3(Float(frame),0,0), rotation: .zero, scale: SIMD3(repeating: 1)) }
            let animation = SceneMdlPuppetAnimation(id: 201+index, name: clips[index].name!,
                mode: "loop", framesPerSecond: 30, frameCount: 60, transformsByBone: [track])
            try puppet.register(layerID: index+11, selection: .init(
                clips: [.init(layer: clips[index], animation: animation)], composition: .singleAbsolute),
                authoredLayers: [clips[index]]).get()
        }
        let descriptor = SceneRenderDescriptor(layers: layers)
        try vm.configureLayerCatalog(descriptor)
        let effect = SceneDynamicTarget.effectConstant(layerID: 2, effectIndex: 0, passIndex: 0, name: "amount")
        let timeline = SceneTimelinePlaybackRuntime(program: .init(bindings: [.init(
            definition: .init(target: effect, valueType: .scalar, authoredValue: .scalar(0)),
            animation: .init(lanes: [[
                .init(frame: 0, value: 0, back: nil, front: nil, locksAngle: nil, locksLength: nil),
                .init(frame: 60, value: 1, back: nil, front: nil, locksAngle: nil, locksLength: nil)]],
                options: .init(fps: 30, length: 60, mode: .single, startsPaused: true, wrapsLoop: false,
                    smoothing: nil, stiffness: nil, parent: nil, children: [], name: timelineName),
                isRelative: false, previewValue: nil), composition: .absolute)], diagnostics: []))
        try vm.configureNamedAnimations([(effect, timelineName)])
        let empty = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1, definitions: []).snapshot
        try vm.publishLayerSnapshot(empty, descriptor: descriptor)
        _ = puppet.advance(frameIndex: 1, sceneTime: 1, dynamicValues: empty)
        let identities = (0..<4).map { ScenePuppetAnimationIdentity(
            layerID: $0+11, animationLayerIndex: 0, animationLayerID: $0+101) }
        try puppet.apply(identities.prefix(2).enumerated().map { index, identity in
            .init(identity: identity, action: .pause, callbackEpoch: 0, ordinal: UInt32(index))
        }, frameIndex: 1).get()
        try vm.publishPuppetAnimationSnapshot(puppet.snapshots())
        let handles = clips.indices.map { index in
            let selector = renamed ? "(\(index)-\(index))" : String(reflecting: clips[index].name!)
            return "thisScene.getLayer(\(String(reflecting: parentNames[index]))).getAnimationLayer(\(selector))"
        }
        let effectSelector = renamed ? "['renamed','blush'].join(' ')" : String(reflecting: timelineName)
        let seeks = handles.enumerated().map { index, handle in
            let ordinary = index == 0 ? "thisScene.getAnimation(\(effectSelector)).setFrame(position);" : ""
            return "\(handle).setFrame(position);\(ordinary)"
        }.joined()
        let source = """
        export function init(value){let position=\(requested);
          thisLayer.origin=new Vec3(9,0,0);\(seeks)
          if(engine.runtime<2){\(failure == "throw" ? "throw new Error('late init');" : failure == "rate" ? "\(handles[3]).rate=-1;" : "")}
          return value;}
        """
        func binding(_ index: Int, _ source: String) -> SceneScriptBindingIR {
            .init(source: source, owner: .init(kind: .object, objectIndex: index, objectID: index+1,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                targetPath: [.key("objects"), .index(index), .key("visible")], properties: [:],
                authoredValue: .bool(true), valueType: .boolean, wrapperKeys: ["script", "value"])
        }
        let program = SceneScriptVectorProgram.compile(domain: vm, descriptor: descriptor,
            scriptBindings: [binding(0, source), binding(1,
                "export function init(value){thisLayer.origin=new Vec3(3,0,0);return value;}")],
            userPropertyDefinitions: [], generation: 1)
        let sourceTarget = SceneDynamicTarget.layer(layerID: 1, field: .visibility)
        let peerTarget = SceneDynamicTarget.layer(layerID: 2, field: .visibility)
        let sourceOrigin = SceneDynamicTarget.layer(layerID: 1, field: .origin)
        let peerOrigin = SceneDynamicTarget.layer(layerID: 2, field: .origin)
        guard let sourceOwner = program.bindings.first(where: { $0.definition.target == sourceTarget })?.owner,
              let peerOwner = program.bindings.first(where: { $0.definition.target == peerTarget })?.owner else {
            throw NSError(domain: "mixed seek preparation", code: 1)
        }
        let layerRuntime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [1,2])
        func step(_ time: Double) throws -> (SceneScriptVectorFrameResult, [SceneScriptOwnerEffects], Set<SceneDynamicTarget>) {
            let timing = SceneFrameTiming(wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1.0/60, sceneTime: time)
            _ = puppet.advance(frameIndex: timing.frameIndex, sceneTime: time, dynamicValues: empty)
            try vm.publishPuppetAnimationSnapshot(puppet.snapshots())
            let previous = program.frameStateSnapshot()
            let result = program.evaluate(inputs: [sourceTarget: .bool(true), peerTarget: .bool(true)],
                effectivePropertyValues: [:], frame: frame(time), userPropertiesJSON: "{}")
            let fixed = layerRuntime.preflightOwnerEffectsToFixedPoint(result.ownerEffects,
                excludingOwners: Set(result.failures.keys)) { admitted in
                Set(SceneScriptOwnerEffectsRuntimeValidation.failures(for: admitted,
                    timelineRuntime: timeline, textureAnimationRuntime: .init(), videoRegistry: nil,
                    timing: timing, puppetAnimationRuntime: puppet).map(\.ownerTarget))
            }
            let admitted = fixed.admission.admittedEffects
            let rejected = fixed.externallyRejectedOwners.union(fixed.admission.rejectedOwners.compactMap(\.ownerTarget))
            let commands = SceneScriptAnimationHandleBridge.orderedMutations(in: admitted)
            _ = try timeline.preview(commands, sceneTime: time).get()
            try timeline.apply(commands, sceneTime: time).get()
            try puppet.apply(admitted.flatMap(\.puppetAnimationCommands), frameIndex: timing.frameIndex).get()
            layerRuntime.commit(fixed.admission.layerPlan)
            program.restoreFrameState(previous, rejectedOwnerTargets: rejected)
            program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejected)
            return (result, admitted, rejected)
        }
        func position(_ expected: Double) -> Bool {
            guard case let .scalar(value)? = timeline.values(sceneTime: 100)[effect] else { return false }
            return abs(value-expected/60) < 1e-12 && puppet.snapshots().allSatisfy {
                $0.currentFrame == expected && !$0.visible && $0.rate == 1
                    && $0.isPlaying == ($0.identity.layerID >= 13)
            }
        }
        let first = try step(1)
        let originalBundle = first.0.ownerEffects.first { $0.ownerTarget == sourceTarget }
        let sameInitEpoch = originalBundle.map { bundle in
            guard let epoch = bundle.animationMutations.first?.callbackEpoch, epoch > 0 else { return false }
            return bundle.puppetAnimationCommands.allSatisfy { $0.callbackEpoch == epoch }
        } ?? (failure == "throw")
        let accepted = failure == "none"
        let firstPosition = position(accepted ? requested : 0)
        let firstLayers = layerRuntime.snapshot().authoredLayerValues
        let rejectedNeedsRetry = failure != "rate" || sourceOwner.needsInitialization
        let rejectedJournalsEmpty = accepted || (first.1.flatMap(\.animationMutations).isEmpty
            && first.1.flatMap(\.puppetAnimationCommands).isEmpty)
        let second = try step(2)
        let retriedPosition = position(failure == "throw" ? 0 : requested)
        let third = try step(3)
        return [
            "completeSourceBundle": failure == "throw" ? originalBundle == nil
                : originalBundle?.animationMutations.map(\.command) == [.setFrame(requested)]
                    && originalBundle?.puppetAnimationCommands.count == (failure == "rate" ? 5 : 4)
                    && originalBundle?.layerMutations.count == 1,
            "wholeSourceAdmission": first.1.contains { $0.ownerTarget == sourceTarget } == accepted
                && first.2.contains(sourceTarget) != accepted,
            "firstRuntimeState": firstPosition,
            "oneCallbackEpoch": sameInitEpoch,
            "layerWriteIsAtomic": firstLayers[sourceOrigin] == (accepted ? .vector3(9,0,0) : nil),
            "healthyPeerSurvives": first.1.contains { $0.ownerTarget == peerTarget }
                && firstLayers[peerOrigin] == .vector3(3,0,0) && !peerOwner.needsInitialization,
            "rejectedJournalsCleared": rejectedJournalsEmpty,
            "rejectedInitRetries": rejectedNeedsRetry && retriedPosition
                && second.1.contains { $0.ownerTarget == sourceTarget } == (failure == "rate"),
            "successDoesNotReplay": !second.1.contains { $0.ownerTarget == peerTarget }
                && third.1.isEmpty && position(failure == "throw" ? 0 : requested),
            "throwKeepsFuse": failure != "throw" || first.0.failures[sourceTarget]?.code == "exception",
        ]
    }

    @MainActor static func main() throws {
        var payload: [String: Any] = [:]
        for explicit in [false, true] {
            let suffix = explicit ? "Explicit" : "Implicit"
            let d = try domain()
            let s = try SceneScriptValueOwner(domain: d,
                source: "export function init(v) { if (engine.runtime < 1) return {}; return 0.75; } export function update(v) { return v; }",
                target: .layer(layerID: 1, field: .alpha), valueType: .scalar,
                effectNames: [], generation: 1, budget: .default)
            func scalar(_ t: Double) -> String {
                if explicit { return value(s.initializeIfNeeded(input: .scalar(0.5), frame: frame(t),
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)) }
                return value(s.evaluate(input: .scalar(0.5), frame: frame(t), scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil))
            }
            payload["scalar"+suffix] = [scalar(0), scalar(2)]
            s.commitLayerMutations()
            let v = try vector(d, "export function init(v) { if (engine.runtime < 1) return {}; return new Vec3(11,0,0); } export function update(v) { return v; }")
            func vec(_ t: Double) -> String {
                if explicit { return value(v.initializeIfNeeded(input: .vector3(1,0,0), frame: frame(t),
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)) }
                return value(evaluate(v, 1, t))
            }
            payload["vector"+suffix] = [vec(0), vec(2)]
            v.commitLayerMutations()
            let string = try SceneScriptValueOwner(domain: d,
                source: "export function init(v) { if (engine.runtime < 1) return {}; return 'ready'; }",
                target: .text(layerID: 1, field: .content), valueType: .string, effectNames: [], generation: 1, budget: .default)
            func text(_ t: Double) -> String {
                if explicit { return value(string.initializeIfNeeded(input: .string("authored"), frame: frame(t),
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)) }
                return value(string.evaluate(input: .string("authored"), frame: frame(t), scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil))
            }
            payload["string"+suffix] = [text(0), text(2)]
            string.commitLayerMutations()
        }
        let d = try domain()
        let initOnly = try vector(d, "export function init(v) { return new Vec3(v.x+10,0,0); }")
        let first = evaluate(initOnly, 1)
        initOnly.discardLayerMutations()
        payload["retryNeedsInit"] = initOnly.needsInitialization
        let retry = evaluate(initOnly, 2)
        initOnly.commitLayerMutations()
        payload["retryValues"] = [x(first), x(retry)]
        payload["committedQuiet"] = !initOnly.requiresFrameEvaluation

        let pending = try vector(d, "export function init(v) { return new Vec3(v.x+10,0,0); }")
        _ = try pending.initializeIfNeeded(input: .vector3(1,0,0), frame: frame(1),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil, retainsValueForNextUpdate: true).get()
        pending.commitLayerMutations() // cursor accepted; vector had no input this frame
        let consumed = evaluate(pending, 100)
        payload["provisionalConsumptionQuiet"] = !pending.requiresFrameEvaluation
        pending.discardLayerMutations() // later frame's consumption is rejected
        let restored = evaluate(pending, 200)
        pending.commitLayerMutations()
        let settled = evaluate(pending, 300)
        pending.commitLayerMutations()
        payload["deferredValues"] = [x(consumed), x(restored), x(settled)]

        let timer = try vector(d, "export function init(v) { engine.setInterval(() => {}, 10); return v; } export function update(v) { return v; }")
        let checkpoint = timer.timerFrameSnapshot()
        _ = evaluate(timer, 1)
        payload["timerProvisional"] = mwx_scene_quickjs_owner_active_timer_count(timer.handle)
        timer.discardLayerMutations() // owner-local rejection, without whole-frame restore
        payload["timerRejected"] = mwx_scene_quickjs_owner_active_timer_count(timer.handle)
        _ = evaluate(timer, 1, 2)
        payload["timerRetried"] = mwx_scene_quickjs_owner_active_timer_count(timer.handle)
        timer.discardLayerMutations() // host-wide discard after a retry
        timer.restoreTimerFrame(checkpoint)
        timer.discardTimerFrame(checkpoint)
        payload["timerFrameRejected"] = mwx_scene_quickjs_owner_active_timer_count(timer.handle)
        _ = evaluate(timer, 1, 3)
        timer.commitLayerMutations()
        payload["timerCommitted"] = mwx_scene_quickjs_owner_active_timer_count(timer.handle)

        let scalarInit = try SceneScriptValueOwner(domain: d,
            source: "export function init(v) { return engine.runtime / 10; }",
            target: .layer(layerID: 1, field: .alpha), valueType: .scalar,
            effectNames: [], generation: 1, budget: .default)
        func scalarValue(_ time: Double) throws -> Double {
            let result = try scalarInit.evaluate(input: .scalar(0.5), frame: frame(time),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
            guard case let .scalar(x) = result.value else { return -999 }
            return x
        }
        let scalarFirst = try scalarValue(1)
        scalarInit.discardLayerMutations()
        let scalarRetry = try scalarValue(2)
        scalarInit.commitLayerMutations()
        payload["scalarLocalValues"] = [scalarFirst, scalarRetry]
        payload["scalarQuiet"] = !scalarInit.requiresFrameEvaluation
        let textInit = try SceneScriptValueOwner(domain: d,
            source: "export function init(v) { thisLayer.origin = new Vec3(11,0,0); return v+'!'; }",
            target: .text(layerID: 1, field: .content), valueType: .string, effectNames: [], generation: 1, budget: .default)
        let stringFirst = try textInit.initializeIfNeeded(input: .string("A"), frame: frame(1),
            scriptPropertiesJSON: "",
            userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        textInit.discardLayerMutations()
        let stringRetry = try textInit.initializeIfNeeded(input: .string("B"), frame: frame(2),
            scriptPropertiesJSON: "",
            userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        textInit.commitLayerMutations()
        let stringSettled = try textInit.initializeIfNeeded(input: .string("C"), frame: frame(3),
            scriptPropertiesJSON: "",
            userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        payload["stringLocalValues"] = [stringFirst?.value == .string("A!"),
            stringRetry?.value == .string("B!"), stringSettled == nil,
            stringRetry?.layerMutations.count == 1, !textInit.requiresFrameEvaluation]
        let stringTimer = try SceneScriptValueOwner(domain: d,
            source: "export function init(v) { engine.setTimeout(() => { thisLayer.origin = new Vec3(31,0,0); }, 1000); return v+'!'; }",
            target: .text(layerID: 1, field: .content), valueType: .string, effectNames: [], generation: 1, budget: .default)
        func timerText(_ input: String, _ time: Double, _ delta: Double = 0) throws -> SceneScriptValueEvaluation {
            let currentFrame = SceneScriptFrameInput(timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: delta, sceneTime: time))
            return try stringTimer.evaluate(input: .string(input), frame: currentFrame,
                scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        }
        let timerInit = try timerText("A", 0)
        stringTimer.discardLayerMutations()
        let stringNeedsRetry = stringTimer.requiresFrameEvaluation
        let timerRetry = try timerText("B", 2, 2)
        stringTimer.commitLayerMutations()
        let timerWaiting = try timerText("B!", 2.5, 0.5)
        stringTimer.commitLayerMutations()
        let timerFired = try timerText("B!", 3.1, 0.6)
        stringTimer.commitLayerMutations()
        payload["stringTimerRetry"] = [timerInit.value == .string("A!"),
            stringNeedsRetry, timerRetry.value == .string("B!"),
            timerWaiting.layerMutations.isEmpty, timerFired.layerMutations.count == 1,
            timerFired.value == .string("B!"), !stringTimer.requiresFrameEvaluation]
        let transient = try vector(d, "export function init(v) { return new Vec3(v.x+10,0,0); }")
        _ = try transient.initializeIfNeeded(input: .vector3(1,0,0), frame: frame(1),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil, retainsValueForNextUpdate: true).get()
        transient.discardLayerMutations()
        payload["uncommittedCursorValue"] = x(evaluate(transient, 2))
        transient.commitLayerMutations()
        let boolean = try vector(d, "export function init(v) { if(engine.runtime < 1) return '3'; return true; } export function update(v) { return v; }", boolean: true)
        var booleanValues: [Bool] = []
        func boolResult(_ time: Double) -> String {
            let evaluated = boolean.evaluate(input: .bool(false), frame: frame(time), scriptPropertiesJSON: "",
                userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)
            if case let .success(output) = evaluated, case let .bool(value) = output.value { booleanValues.append(value) }
            return value(evaluated)
        }
        payload["booleanNonBoolInit"] = [boolResult(0), boolResult(2)]
        payload["booleanValues"] = booleanValues
        boolean.commitLayerMutations()
        let runaway = try vector(d, "export function init(v) { while(true) {} } export function update(v) { return v; }")
        let budgetFailure = value(runaway.evaluate(input: .vector3(1,0,0), frame: frame(1),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: 64))
        runaway.discardLayerMutations()
        payload["budgetFuse"] = [budgetFailure, value(evaluate(runaway, 1, 2))]
        let memory = try vector(d, "export function init(v) { return new Array(10000000).fill(1); } export function update(v) { return v; }")
        let memoryFailure = value(evaluate(memory, 1))
        memory.discardLayerMutations()
        payload["memoryFuse"] = [memoryFailure, value(evaluate(memory, 1, 2))]
        let exception = try vector(d, "export function init(v) { throw new Error('broken'); } export function update(v) { return v; }")
        let hard = value(evaluate(exception, 1))
        exception.discardLayerMutations()
        payload["permanent"] = [hard, value(evaluate(exception, 1, 2))]
        let stale = try vector(d, "export function init(v) { return v; }")
        payload["stale"] = value(stale.initializeIfNeeded(input: .vector3(1,0,0), frame: frame(1),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 2, interruptBudget: nil))
        payload["cohorts"] = try [cohort(false), cohort(true)]
        payload["mixedSeeks"] = try [mixedAnimationSeek("none"), mixedAnimationSeek("none", renamed: true),
            mixedAnimationSeek("throw"), mixedAnimationSeek("rate")]
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

class SceneScriptInitializationTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="scene-init-transaction-")
        binary = compile_vector_harness(Path(cls.temporary.name), HARNESS, "initialization",
            extra_swift_sources=tuple([VM / "SceneScriptMediaFrameCoordinator.swift", *TIMELINE_SOURCES,
                *PUPPET_SOURCES, SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift",
                VM / "SceneScriptOwnerEffectsRuntimeValidation.swift"]), preamble=playback_preamble())
        result = subprocess.run([str(binary)], capture_output=True, text=True)
        if result.returncode: raise AssertionError(result.stdout + result.stderr)
        cls.value = json.loads(result.stdout.strip().splitlines()[-1])
    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()
    def test_bad_initialization_return_is_retryable_in_all_six_paths(self):
        for kind in ("scalar", "vector", "string"):
            for route in ("Explicit", "Implicit"):
                with self.subTest(kind=kind, route=route):
                    self.assertEqual(self.value[kind+route], ["bad-return", "ok"])
    def test_rejected_initialization_retries_then_quiesces(self):
        self.assertTrue(self.value["retryNeedsInit"])
        self.assertEqual(self.value["retryValues"], [11, 12])
        self.assertTrue(self.value["committedQuiet"])
    def test_committed_cursor_value_survives_rejected_later_consumption(self):
        self.assertEqual(self.value["deferredValues"], [11, 11, 300])
        self.assertTrue(self.value["provisionalConsumptionQuiet"])
    def test_init_timers_follow_local_and_whole_frame_rejection(self):
        self.assertEqual([self.value[k] for k in ("timerProvisional", "timerRejected", "timerRetried", "timerFrameRejected", "timerCommitted")], [1,0,1,0,1])
    def test_permanent_failure_and_stale_generation_remain_closed(self):
        self.assertEqual(self.value["permanent"], ["exception", "disabled"])
        self.assertEqual(self.value["stale"], "stale-owner")

    def test_scalar_and_string_share_initialization_commit_boundary(self):
        self.assertEqual(self.value["scalarLocalValues"], [0.1, 0.2])
        self.assertTrue(self.value["scalarQuiet"])
        self.assertEqual(self.value["stringLocalValues"], [True] * 5)
    def test_string_init_only_timer_is_replaced_on_rejection_and_then_quiesces(self):
        self.assertEqual(self.value["stringTimerRetry"], [True] * 7)
    def test_uncommitted_cursor_value_cannot_leak_into_retry(self):
        self.assertEqual(self.value["uncommittedCursorValue"], 12)
    def test_prepared_cross_family_initializers_precede_callbacks_and_share_commit(self):
        for variant in self.value["cohorts"]:
            for behavior, passed in variant.items():
                self.assertTrue(passed, (behavior, variant))
    def test_effectful_boolean_non_bool_init_preserves_current_input(self):
        self.assertEqual(self.value["booleanNonBoolInit"], ["ok", "ok"])
        self.assertEqual(self.value["booleanValues"], [False, False])
    def test_cross_parent_puppet_and_property_seeks_share_one_init_admission(self):
        for scenario in self.value["mixedSeeks"]:
            for behavior, passed in scenario.items():
                self.assertTrue(passed, (behavior, scenario))
    def test_timeout_and_memory_failure_remain_permanently_disabled(self):
        self.assertEqual(self.value["budgetFuse"], ["budget-exceeded", "disabled"])
        self.assertEqual(self.value["memoryFuse"], ["memory-exceeded", "disabled"])
