"""Behavioral initialization commit/retry gates through production Swift and C."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
import Foundation

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
    static func main() throws {
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
            let string = try SceneScriptStringOwner(domain: d,
                source: "export function init(v) { if (engine.runtime < 1) return {}; return 'ready'; }",
                target: .text(layerID: 1, field: .content), effectNames: [], generation: 1, budget: .default)
            func text(_ t: Double) -> String {
                if explicit { return value(string.initializeIfNeeded(input: "authored", frame: frame(t),
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)) }
                return value(string.evaluate(input: "authored", frame: frame(t), scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil))
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
        let textInit = try SceneScriptStringOwner(domain: d,
            source: "export function init(v) { thisLayer.origin = new Vec3(11,0,0); return v+'!'; }",
            target: .text(layerID: 1, field: .content), effectNames: [], generation: 1, budget: .default)
        let stringFirst = try textInit.initializeIfNeeded(input: "A", frame: frame(1),
            userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        textInit.discardLayerMutations()
        let stringRetry = try textInit.initializeIfNeeded(input: "B", frame: frame(2),
            userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        textInit.commitLayerMutations()
        let stringSettled = try textInit.initializeIfNeeded(input: "C", frame: frame(3),
            userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        payload["stringLocalValues"] = [stringFirst?.value == .string("A!"),
            stringRetry?.value == .string("B!"), stringSettled == nil,
            stringRetry?.layerMutations.count == 1, !textInit.requiresFrameEvaluation]
        let stringTimer = try SceneScriptStringOwner(domain: d,
            source: "export function init(v) { engine.setTimeout(() => { thisLayer.origin = new Vec3(31,0,0); }, 1000); return v+'!'; }",
            target: .text(layerID: 1, field: .content), effectNames: [], generation: 1, budget: .default)
        func timerText(_ input: String, _ time: Double, _ delta: Double = 0) throws -> SceneScriptStringEvaluation {
            let currentFrame = SceneScriptFrameInput(timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: delta, sceneTime: time))
            return try stringTimer.evaluate(input: input, frame: currentFrame,
                userPropertiesJSON: "{}", expectedGeneration: 1).get()
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
        let boolean = try vector(d, "export function init(v) { if(engine.runtime < 1) return 3; return true; } export function update(v) { return v; }", boolean: true)
        func boolResult(_ time: Double) -> String {
            value(boolean.evaluate(input: .bool(false), frame: frame(time), scriptPropertiesJSON: "",
                userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil))
        }
        payload["booleanRetry"] = [boolResult(0), boolResult(2)]
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
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

class SceneScriptInitializationTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="scene-init-transaction-")
        binary = compile_vector_harness(Path(cls.temporary.name), HARNESS, "initialization")
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
    def test_effectful_boolean_bad_return_retries(self):
        self.assertEqual(self.value["booleanRetry"], ["bad-return", "ok"])
    def test_timeout_and_memory_failure_remain_permanently_disabled(self):
        self.assertEqual(self.value["budgetFuse"], ["budget-exceeded", "disabled"])
        self.assertEqual(self.value["memoryFuse"], ["memory-exceeded", "disabled"])
