"""Real shared VM authored destroy admission and selective owner lifecycle."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import compile_vector_harness


HARNESS = r'''
import Foundation

private let controller = SceneDynamicTarget.layer(layerID: 10, field: .visibility)
private let victimAlpha = SceneDynamicTarget.layer(layerID: 20, field: .alpha)
private let victimText = SceneDynamicTarget.text(layerID: 20, field: .content)
private let victimOrigin = SceneDynamicTarget.layer(layerID: 20, field: .origin)
private let liveAlpha = SceneDynamicTarget.layer(layerID: 40, field: .alpha)

private func frame(_ time: Double) -> SceneScriptFrameInput {
    .init(timing: .init(wallDate: Date(timeIntervalSince1970: time),
        simulationFrameTime: 0.1, sceneTime: time))
}

private func descriptor(child: Bool = false) -> SceneRenderDescriptor {
    var layers: [SceneRenderDescriptor.Layer] = [
        .init(id: 10, layerIndex: 0, name: "controller", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: []),
        .init(id: 20, layerIndex: 1, name: "victim", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [],
            contentKind: "text", text: "ready", textStyle: .init(fontPath: nil,
                colorRGB: [1, 1, 1], pointSize: 32)),
        .init(id: 30, layerIndex: 2, name: "cursor", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: []),
        .init(id: 40, layerIndex: 3, name: "live", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: []),
    ]
    if child {
        layers[1].childLayerIDs = [21]
        layers.append(.init(id: 21, layerIndex: 4, name: "child", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [], parentID: 20))
    }
    for index in layers.indices { layers[index].sizeWH = [100, 100] }
    return .init(layers: layers)
}

private func binding(_ source: String, _ id: Int, _ index: Int,
                     _ field: String, _ seed: SceneJSONValue,
                     _ type: SceneScriptBindingValueType) -> SceneScriptBindingIR {
    .init(source: source, owner: .init(kind: .object, objectIndex: index,
        objectID: id, effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
        targetPath: [.key("objects"), .index(index), .key(field)], properties: [:],
        authoredValue: seed, valueType: type, wrapperKeys: ["script", "value"])
}

private func make(_ d: SceneRenderDescriptor, _ bindings: [SceneScriptBindingIR]) throws
    -> SceneScriptQuickJSProgramCandidate {
    var prepared = d
    for binding in bindings where binding.targetKey == "text" {
        if let index = binding.owner.objectIndex { prepared.layers[index].textScript = .init(source: binding.source) }
    }
    return try .compile(authoredDescriptor: prepared, runtimeDescriptor: prepared, scriptBindings: bindings,
        vectorProjection: SceneScriptVectorProgram.project(descriptor: prepared, scriptBindings: bindings),
        userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [],
        stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 1)
}

private func finish(_ c: SceneScriptQuickJSProgramCandidate, accepted: Bool = true,
                    rejected: Set<SceneDynamicTarget> = []) {
    c.vectorProgram.finalizeLayerMutations(committing: accepted, rejectedOwnerTargets: rejected)
    c.scalarProgram.finalizeLayerMutations(committing: accepted, rejectedOwnerTargets: rejected)
    c.stringProgram.finalizeLayerMutations(committing: accepted, rejectedOwnerTargets: rejected)
    c.cursorProgram.finalizeLayerMutations(committing: accepted, rejectedOwnerTargets: rejected)
}

private func cursor(_ c: SceneScriptQuickJSProgramCandidate, time: Double = 0,
                    down: Bool = false) -> SceneScriptCursorFrameResult {
    let hits = Dictionary(uniqueKeysWithValues: [20, 30].map {
        ($0, SceneScriptCursorHit(layerID: $0, worldPosition: .zero, localPosition: .zero))
    })
    return c.cursorProgram.dispatch(batch: .init(samples: [
        .init(hits: hits, pointerPosition: .zero, primaryButtonIsDown: down),
    ], overflowed: false), frame: frame(time), userPropertiesJSON: "{}")
}

private func quiet(_ outcomes: [SceneScriptOwnerTeardownOutcome]) -> Bool {
    outcomes.allSatisfy { $0.snapshot.isQuiescent && $0.snapshot.teardownStarted
        && $0.snapshot.destroyCallbackCount == 1 }
}

@main enum Harness {
    static func main() throws {
        var out: [String: Any] = [:]
        // Name, handle and authored order resolve one target, while the
        // controller's Boolean stays true and lookup remains deferred.
        var forms: [[String: Any]] = []
        for argument in ["'victim'", "thisScene.getLayerByID(20)", "1"] {
            let source = """
                export function update(value) {
                    if (thisScene.destroyLayer(\(argument)) !== true) throw new Error('result');
                    if (thisScene.getLayerByID(20) === null) throw new Error('early removal');
                    return true;
                }
                """
            let c = try make(descriptor(), [binding(source, 10, 0, "visible", .bool(true), .boolean)])
            let result = c.vectorProgram.evaluate(inputs: [controller: .bool(true)],
                effectivePropertyValues: [:], frame: frame(0))
            let topology = SceneScriptDynamicLayerRuntime(descriptor: descriptor(),
                authoredMutationLayerIDs: [10, 20, 30, 40])
            let plan = topology.preflightOwnerEffects(result.ownerEffects)
            forms.append(["failures": result.failures.count, "controller": result.values[controller] == .bool(true),
                "destroyIDs": result.layerMutations.filter { $0.kind == .destroy }.map(\.layerID),
                "deferred": topology.snapshot().destroyedAuthoredLayerIDs.isEmpty,
                "admitted": plan.rejectedOwners.isEmpty])
            finish(c)
            topology.commit(plan.layerPlan)
            forms[forms.count - 1]["committed"] = topology.snapshot().destroyedAuthoredLayerIDs == [20]
        }
        out["forms"] = forms

        // A JavaScript exception retracts the whole delete/write journal;
        // healthy peer output remains usable in that same VM.
        let throwing = try make(descriptor(), [
            binding("export function update(v){thisScene.getLayer('victim').alpha=.2;thisScene.destroyLayer('victim');throw new Error('reject');}",
                10, 0, "visible", .bool(true), .boolean),
            binding("export function update(v){return .7;}", 40, 3, "alpha", .number(1), .number),
        ])
        let failed = throwing.vectorProgram.evaluate(inputs: [controller: .bool(true)],
            effectivePropertyValues: [:], frame: frame(0))
        let peer = throwing.scalarProgram.evaluate(inputs: [liveAlpha: .scalar(1)], frame: frame(0))
        out["throw"] = ["exception": failed.failures[controller]?.code == "exception",
            "emptyJournal": failed.layerMutations.isEmpty, "healthy": peer.values[liveAlpha] == .scalar(0.7)]
        finish(throwing, rejected: [controller])

        // Static children remain a typed Swift rejection, rather than a C
        // API visibility restriction or a scene-wide failure.
        let childDescriptor = descriptor(child: true)
        let parentDelete = try make(childDescriptor, [
            binding("export function update(v){thisScene.destroyLayer('victim');return true;}",
                10, 0, "visible", .bool(true), .boolean),
        ])
        let parentResult = parentDelete.vectorProgram.evaluate(inputs: [controller: .bool(true)],
            effectivePropertyValues: [:], frame: frame(0))
        let childTopology = SceneScriptDynamicLayerRuntime(descriptor: childDescriptor,
            authoredMutationLayerIDs: [10, 20, 21, 30, 40])
        let rejected = childTopology.preflightOwnerEffects(parentResult.ownerEffects)
        out["children"] = parentResult.failures.isEmpty && rejected.rejectedOwners.count == 1
            && rejected.admittedEffects.isEmpty && childTopology.snapshot().destroyedAuthoredLayerIDs.isEmpty
        finish(parentDelete, rejected: [controller])

        let valueDomain = try SceneScriptQuickJSDomain()
        try valueDomain.configureLayerCatalog(descriptor())
        let valueOnly = try SceneScriptValueOwner(domain: valueDomain,
            source: "export function update(v){thisScene.destroyLayer('victim');return v;}",
            target: controller, valueType: .bool, effectNames: [], generation: 1, budget: .default)
        let valueOnlyResult = valueOnly.evaluate(input: .bool(true), frame: frame(0),
            scriptPropertiesJSON: "{}", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)
        if case .failure(.exception) = valueOnlyResult { out["valueOnly"] = true }
        else { out["valueOnly"] = false }

        // Initialize timer/update/cursor work for three borrowed value owners
        // and one standalone cursor owner. Destroy callback writes are cleanup
        // only, including attempts to delete a healthy authored peer.
        let interval = "engine.setInterval(()=>{thisScene.getLayer('live').alpha=.2;},100);"
        let destroy = "export function destroy(){thisScene.destroyLayer('live');throw new Error('cleanup');}"
        let c = try make(descriptor(), [
            binding("export function init(v){\(interval)return v;}export function update(v){return v;}export function cursorDown(e){thisLayer.alpha=.3;}\(destroy)",
                20, 1, "alpha", .number(1), .number),
            binding("export function init(v){\(interval)return v;}export function update(v){return v;}export function cursorDown(e){thisLayer.text='event';}\(destroy)",
                20, 1, "text", .string("ready"), .string),
            binding("export function init(v){\(interval)return v;}export function update(v){return v;}export function cursorDown(e){thisLayer.origin=new Vec3(1,0,0);}\(destroy)",
                20, 1, "origin", .string("0 0 0"), .string),
            binding("let n=0;export function init(v){engine.setInterval(()=>n++,100);return v;}export function update(v){return n/10;}",
                40, 3, "alpha", .number(1), .number),
        ])
        let standaloneOwner = try SceneScriptValueOwner(domain: c.domain!,
            source: "export function cursorDown(e){\(interval)thisLayer.alpha=.4;}\(destroy)",
            target: .layer(layerID: 30, field: .origin), effectNames: [], generation: 1, budget: .default)
        let standalone = SceneScriptCursorProgram(bindings: [.init(layerID: 30, authoredOrdinal: 100,
            owner: standaloneOwner, events: standaloneOwner.exportedCursorEvents, ownsOwner: true,
            scriptProperties: [:], ownerSeedValue: nil)], generation: 1)
        let standaloneBatch = SceneScriptCursorFrameBatch(samples: [
            .init(hits: [30: .init(layerID: 30, worldPosition: .zero, localPosition: .zero)],
                pointerPosition: .zero, primaryButtonIsDown: true),
        ], overflowed: false)
        let initialStandalone = standalone.dispatch(batch: standaloneBatch, frame: frame(0), userPropertiesJSON: "{}")
        let initialCursor = cursor(c, down: true)
        let initialVector = c.vectorProgram.evaluate(inputs: [victimOrigin: .vector3(0, 0, 0)],
            effectivePropertyValues: [:], frame: frame(0))
        let initialScalar = c.scalarProgram.evaluate(inputs: [victimAlpha: .scalar(1), liveAlpha: .scalar(1)], frame: frame(0))
        let initialString = c.stringProgram.evaluate(inputs: [victimText: .string("ready")], frame: frame(0))
        out["initialized"] = initialStandalone.failures.isEmpty && initialCursor.failures.isEmpty && initialVector.failures.isEmpty
            && initialScalar.failures.isEmpty && initialString.failures.isEmpty
        finish(c)
        standalone.finalizeLayerMutations(committing: true)
        let standaloneEdges = standalone.edgeStateSnapshot()
        let standaloneTimers = standalone.timerFrameStateSnapshot()
        let edges = c.cursorProgram.edgeStateSnapshot()
        let scalarTimers = c.scalarProgram.timerFrameStateSnapshot()
        let stringTimers = c.stringProgram.timerFrameStateSnapshot()
        let vectorTimers = c.vectorProgram.timerFrameStateSnapshot()
        let cursorTimers = c.cursorProgram.timerFrameStateSnapshot()
        let borrowed = c.cursorProgram.bindings.filter { !$0.ownsOwner && $0.layerID == 20 }.count
        let cursorOutcomes = c.cursorProgram.retire(layerIDs: [20, 30], frame: frame(0), userPropertiesJSON: "{}")
            + standalone.retire(layerIDs: [20, 30], frame: frame(0), userPropertiesJSON: "{}")
        let scalarOutcomes = c.scalarProgram.retire(layerIDs: [20, 30], frame: frame(0), userPropertiesJSON: "{}")
        let stringOutcomes = c.stringProgram.retire(layerIDs: [20, 30], frame: frame(0), userPropertiesJSON: "{}")
        let vectorOutcomes = c.vectorProgram.retire(layerIDs: [20, 30], frame: frame(0), userPropertiesJSON: "{}")
        let all = cursorOutcomes + scalarOutcomes + stringOutcomes + vectorOutcomes
        out["retired"] = ["counts": [cursorOutcomes.count, scalarOutcomes.count, stringOutcomes.count, vectorOutcomes.count],
            "borrowed": borrowed, "quiescent": quiet(all),
            "destroyThrows": all.allSatisfy(\.destroyCallbackThrew),
            "cursorUnregistered": c.cursorProgram.ownerLayerIDs.isDisjoint(with: [20, 30]) && standalone.ownerLayerIDs.isEmpty
                && c.vectorProgram.cursorOwnerRegistrations.isEmpty
                && c.scalarProgram.cursorOwnerRegistrations.isEmpty
                && c.stringProgram.cursorOwnerRegistrations.isEmpty]
        standalone.restoreEdgeState(standaloneEdges)
        standalone.restoreTimerFrameState(standaloneTimers)
        c.cursorProgram.restoreEdgeState(edges)
        c.cursorProgram.restoreTimerFrameState(cursorTimers)
        c.scalarProgram.restoreTimerFrameState(scalarTimers)
        c.stringProgram.restoreTimerFrameState(stringTimers)
        c.vectorProgram.restoreTimerFrameState(vectorTimers)
        let afterStandalone = standalone.dispatch(batch: standaloneBatch, frame: frame(1), userPropertiesJSON: "{}")
        let afterCursor = cursor(c, time: 1, down: false)
        let afterVector = c.vectorProgram.evaluate(inputs: [victimOrigin: .vector3(0, 0, 0)],
            effectivePropertyValues: [:], frame: frame(1))
        let afterScalar = c.scalarProgram.evaluate(inputs: [victimAlpha: .scalar(1), liveAlpha: .scalar(1)], frame: frame(1))
        let afterString = c.stringProgram.evaluate(inputs: [victimText: .string("ready")], frame: frame(1))
        out["after"] = ["cursorEmpty": afterStandalone.ownerEffects.isEmpty && afterStandalone.failures.isEmpty
                && afterCursor.ownerEffects.isEmpty && afterCursor.failures.isEmpty,
            "vectorEmpty": afterVector.values.isEmpty && afterVector.layerMutations.isEmpty,
            "stringEmpty": afterString.values.isEmpty && afterString.layerMutations.isEmpty,
            "onlyLive": Set(afterScalar.values.keys) == [liveAlpha] && afterScalar.layerMutations.isEmpty,
            "healthyTimer": afterScalar.values[liveAlpha] == .scalar(0.1),
            "noDeadCapture": c.cursorProgram.capturedOwnerLayerIDs.isDisjoint(with: [20, 30])]
        finish(c)
        let repeated = standalone.retire(layerIDs: [20, 30], frame: frame(1), userPropertiesJSON: "{}")
            + c.cursorProgram.retire(layerIDs: [20, 30], frame: frame(1), userPropertiesJSON: "{}")
            + c.scalarProgram.retire(layerIDs: [20, 30], frame: frame(1), userPropertiesJSON: "{}")
            + c.stringProgram.retire(layerIDs: [20, 30], frame: frame(1), userPropertiesJSON: "{}")
            + c.vectorProgram.retire(layerIDs: [20, 30], frame: frame(1), userPropertiesJSON: "{}")
        out["repeatEmpty"] = repeated.isEmpty
        let teardown = standalone.teardown(frame: frame(1), userPropertiesJSON: "{}")
            + c.vectorProgram.teardown(frame: frame(1), effectivePropertyValues: [:], userPropertiesJSON: "{}")
            + c.scalarProgram.teardown(frame: frame(1), userPropertiesJSON: "{}")
            + c.stringProgram.teardown(frame: frame(1), userPropertiesJSON: "{}")
            + c.cursorProgram.teardown(frame: frame(1), userPropertiesJSON: "{}")
        out["destroyOnce"] = teardown.filter { $0.snapshot.destroyCallbackCount == 1 }.count == 4
            && teardown.allSatisfy { !$0.destroyCallbackInvoked }
        standalone.discardTimerFrameState(standaloneTimers)
        c.cursorProgram.discardTimerFrameState(cursorTimers)
        c.scalarProgram.discardTimerFrameState(scalarTimers)
        c.stringProgram.discardTimerFrameState(stringTimers)
        c.vectorProgram.discardTimerFrameState(vectorTimers)
        print(String(decoding: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneScriptAuthoredLayerRetirementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-authored-retirement-vm-") as temp:
            binary = compile_vector_harness(Path(temp), HARNESS, "authored-retirement")
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=30)
            cls.result = json.loads(result.stdout)

    def test_name_handle_and_order_delete_defer_and_preserve_controller_boolean(self) -> None:
        for result in self.result["forms"]:
            self.assertEqual(result["failures"], 0)
            self.assertEqual(result["destroyIDs"], [20])
            for key in ("controller", "deferred", "admitted", "committed"):
                self.assertTrue(result[key], key)

    def test_throw_value_only_and_static_child_rejection_are_local(self) -> None:
        self.assertTrue(all(self.result["throw"].values()))
        self.assertTrue(self.result["valueOnly"])
        self.assertTrue(self.result["children"])

    def test_retirement_deduplicates_borrowed_owners_and_runs_cleanup_once(self) -> None:
        self.assertTrue(self.result["initialized"])
        result = self.result["retired"]
        self.assertEqual(result["counts"], [1, 1, 1, 1])
        self.assertEqual(result["borrowed"], 3)
        for key in ("quiescent", "destroyThrows", "cursorUnregistered"):
            self.assertTrue(result[key], key)
        self.assertTrue(self.result["repeatEmpty"])
        self.assertTrue(self.result["destroyOnce"])

    def test_retired_update_timer_and_cursor_work_cannot_revive_or_stop_peer(self) -> None:
        self.assertTrue(all(self.result["after"].values()), self.result["after"])


if __name__ == "__main__":
    unittest.main()
