"""Real VM boundary: JS heap identity survives rejected typed host effects."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
import Foundation
@main enum Harness {
    static func domain() throws -> SceneScriptQuickJSDomain {
        let d = try SceneScriptQuickJSDomain()
        try d.configureLayerCatalog(.init(layers: (1...3).map {
            .init(id: $0, layerIndex: $0-1, name: "layer\($0)", visible: true,
                  originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: nil,
                  alpha: 1, effects: [])
        }))
        return d
    }
    static func owner(_ d: SceneScriptQuickJSDomain, _ source: String,
                      id: Int = 1, stateful: Bool = true) throws -> SceneScriptValueOwner {
        try .init(domain: d, source: source, target: .layer(layerID: id, field: .origin),
            valueType: stateful ? .vector3 : .bool,
            effectNames: [], allowsStatefulLayerSideEffects: stateful,
            generation: 1, budget: .default)
    }
    static func run(_ o: SceneScriptValueOwner, _ time: Double = 1,
                    generation: UInt64 = 1, budget: UInt64? = nil,
                    input: SceneDynamicValue = .vector3(0,0,0))
        -> Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure> {
        o.evaluate(input: input, frame: .init(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 0.016,
            sceneTime: time)), scriptPropertiesJSON: "", userPropertiesJSON: "{}",
            expectedGeneration: generation, interruptBudget: budget)
    }
    static func xyz(_ r: Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure>) throws -> [Double] {
        guard case let .vector3(x,y,z) = try r.get().value else { return [] }
        return [x,y,z]
    }
    static func code(_ r: Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure>) -> String {
        switch r { case .success: "ok"; case let .failure(f): f.code }
    }
    static func main() throws {
        var out: [String:Any] = [:]
        let d = try domain()
        let aliases = try owner(d, """
            let root, child;
            export function update(v) {
                if (!root) { shared.child={x:1}; root=shared; child=shared.child; }
                if (engine.runtime===2) { child.x=9; thisLayer.origin=new Vec3(99,0,0); }
                return new Vec3(root===shared?1:0, child===shared.child?1:0, shared.child.x);
            }
            """)
        out["seed"] = try xyz(run(aliases)); aliases.commitLayerMutations()
        let pending = try run(aliases, 2).get()
        out["pendingLayerCount"] = pending.layerMutations.count
        aliases.discardLayerMutations()
        let next = try run(aliases, 3).get()
        out["aliasAfterDiscard"] = try xyz(.success(next))
        out["discardedLayerCount"] = next.layerMutations.count
        aliases.commitLayerMutations()

        let writer = try owner(d, """
            let n=0;
            export function update(v) {
                if (!shared.fn) {
                    shared.fn=()=>++n; shared.map=new Map([['key',7]]);
                    shared.set=new Set([8]); shared.bytes=new Uint8Array([9]);
                    shared.date=new Date(1234); shared.cycle={}; shared.cycle.self=shared.cycle;
                    shared.symbol=Symbol('identity'); shared.proto=Object.create({answer:10});
                    Object.defineProperty(shared,'lazy',{get(){return 11;},enumerable:true});
                }
                return v;
            }
            """, id: 2)
        _ = try run(writer).get(); writer.commitLayerMutations()
        let reader = try owner(d, """
            export function update(v) {
                const valid=shared.map.get('key')===7 && shared.set.has(8) && shared.bytes[0]===9
                    && shared.date.getTime()===1234 && shared.cycle.self===shared.cycle
                    && typeof shared.symbol==='symbol' && shared.proto.answer===10 && shared.lazy===11;
                return new Vec3(shared.fn(),valid?1:0,0);
            }
            """, id: 3)
        var values: [[Double]] = []
        for time in 1...5 {
            values.append(try xyz(run(reader, Double(time))))
            if time % 2 == 0 { reader.discardLayerMutations() }
            else { reader.commitLayerMutations() }
        }
        out["crossScriptValues"] = values

        let replacement = try owner(d, """
            let old;
            export function update(v) {
                if (!old) { old=shared; shared={fresh:13}; }
                return new Vec3(old!==shared?1:0,old.child.x,shared.fresh);
            }
            """)
        out["replacement"] = try xyz(run(replacement)); replacement.discardLayerMutations()
        out["replacementAfterDiscard"] = try xyz(run(replacement, 2))

        let failed = try owner(d, """
            export function update(v) {
                shared.attempts=(shared.attempts||0)+1;
                if(engine.runtime===1) return {};
                return new Vec3(shared.attempts,0,0);
            }
            """)
        out["badReturn"] = code(run(failed)); failed.discardLayerMutations()
        let observer = try owner(d, "export function update(v){return new Vec3(shared.attempts,0,0);}", id: 3)
        out["failedWriterVisible"] = try xyz(run(observer)); observer.commitLayerMutations()
        let retry = try run(failed, 2).get()
        out["retry"] = try xyz(.success(retry)); out["retryLayerCount"] = retry.layerMutations.count
        failed.commitLayerMutations()

        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let storage = SceneScriptLocalStorageSession(recordID: "shared-boundary", rootDirectory: root)
        try d.configureStorage(storage); try d.setStorageScreenIdentity("screen")
        _ = storage.beginFrameTransaction()
        let mixed = try owner(d, """
            export function update(v){
                if(engine.runtime===1){ shared.retained=17;
                    localStorage.set('candidate',19,'global'); thisLayer.origin=new Vec3(99,0,0); }
                return new Vec3(shared.retained||0,localStorage.get('candidate','global')||0,0);
            }
            """)
        out["mixedCandidate"] = try xyz(run(mixed)); try mixed.commitStorage().get()
        mixed.discardLayerMutations(); storage.discardFrameTransaction()
        _ = storage.beginFrameTransaction()
        let restored = try run(mixed, 2).get()
        out["mixedAfterDiscard"] = try xyz(.success(restored))
        out["mixedLayerCount"] = restored.layerMutations.count
        storage.discardFrameTransaction()

        let initializer = try owner(d, "export function init(v){shared.inits=(shared.inits||0)+1;return new Vec3(shared.inits,0,0);}")
        out["initFirst"] = try xyz(run(initializer)); initializer.discardLayerMutations()
        out["initRetry"] = try xyz(run(initializer)); initializer.commitLayerMutations()

        let exception = try owner(d, "export function update(v){shared.thrown=23;throw new Error('failed');}")
        out["exception"] = code(run(exception)); exception.discardLayerMutations()
        out["exceptionRetry"] = code(run(exception, 2))
        let afterException = try owner(d, "export function update(v){return new Vec3(shared.thrown,0,0);}", id: 3)
        out["exceptionHeap"] = try xyz(run(afterException))
        let pure = try owner(d,"export function update(v){return new Vec3(shared.thrown,0,0);}", stateful: false)
        out["valueOnlyGuard"] = code(run(pure,input:.bool(false)))
        let stale = try owner(d,"export function update(v){return v;}")
        out["staleGeneration"] = code(run(stale, generation: 2))
        let other = try domain()
        let isolated = try owner(other,"export function update(v){return new Vec3(Object.keys(shared).length,0,0);}")
        out["isolatedDomain"] = try xyz(run(isolated))
        let handleWriter = try owner(d, """
            export function update(v) {
                if(engine.runtime===1) { shared.handle=thisLayer; return v; }
                try { shared.handle.alpha=0.4; } catch(e) { return new Vec3(1,0,0); }
                return v;
            }
            """)
        _ = try run(handleWriter).get(); handleWriter.commitLayerMutations()
        let handleReader = try owner(d, """
            export function update(v) {
                try { shared.handle.origin=new Vec3(99,0,0); }
                catch(e) { return new Vec3(1,0,0); }
                return v;
            }
            """, id: 2)
        let foreign = try run(handleReader).get()
        out["sharedForeignHandle"] = try xyz(.success(foreign))
        out["sharedForeignHandleMutations"] = foreign.layerMutations.count
        handleReader.commitLayerMutations()
        let persistent = try run(handleWriter, 2).get()
        out["sharedPersistentHandle"] = try xyz(.success(persistent))
        out["sharedPersistentHandleMutations"] = persistent.layerMutations.count
        handleWriter.commitLayerMutations()
        let loopWriter = try owner(d,"export function update(v){shared.loop=()=>{while(true){}};return v;}")
        _ = try run(loopWriter).get(); loopWriter.commitLayerMutations()
        let loopReader = try owner(d,"export function update(v){shared.loop();return v;}",id:2)
        out["sharedFunctionBudget"] = code(run(loopReader,budget:64))
        let memoryWriter = try owner(d,"export function update(v){shared.allocate=()=>new Array(10000000).fill(1);return v;}")
        _ = try run(memoryWriter).get(); memoryWriter.commitLayerMutations()
        let memoryReader = try owner(d,"export function update(v){shared.allocate();return v;}",id:3)
        out["sharedFunctionMemory"] = code(run(memoryReader))
        print(String(decoding: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneScriptSharedIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="scene-shared-identity-")
        root = Path(cls.temp.name)
        binary = compile_vector_harness(root, HARNESS, "shared-identity")
        result = subprocess.run([str(binary), str(root / "storage")], capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.value = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_aliases_survive_typed_discard_without_preserving_layer_journal(self):
        self.assertEqual(self.value["seed"], [1, 1, 1])
        self.assertEqual(self.value["pendingLayerCount"], 1)
        self.assertEqual(self.value["aliasAfterDiscard"], [1, 1, 9])
        self.assertEqual(self.value["discardedLayerCount"], 0)

    def test_functions_and_objects_remain_shared_across_callbacks(self):
        self.assertEqual(self.value["crossScriptValues"], [[n, 1, 0] for n in range(1, 6)])

    def test_author_assignment_keeps_normal_old_alias_semantics(self):
        self.assertEqual(self.value["replacement"], [1, 9, 13])
        self.assertEqual(self.value["replacementAfterDiscard"], [1, 9, 13])

    def test_failed_writer_heap_is_visible_but_layer_journal_is_not(self):
        self.assertEqual(self.value["badReturn"], "bad-return")
        self.assertEqual(self.value["failedWriterVisible"], [1, 0, 0])
        self.assertEqual(self.value["retry"], [2, 0, 0])
        self.assertEqual(self.value["retryLayerCount"], 0)

    def test_storage_and_layer_discard_stay_independent_from_heap(self):
        self.assertEqual(self.value["mixedCandidate"], [17, 19, 0])
        self.assertEqual(self.value["mixedAfterDiscard"], [17, 0, 0])
        self.assertEqual(self.value["mixedLayerCount"], 0)

    def test_retried_initialization_may_repeat_heap_side_effect(self):
        self.assertEqual(self.value["initFirst"], [1, 0, 0])
        self.assertEqual(self.value["initRetry"], [2, 0, 0])

    def test_exception_disable_value_only_and_domain_isolation(self):
        self.assertEqual(self.value["exception"], "exception")
        self.assertEqual(self.value["exceptionRetry"], "disabled")
        self.assertEqual(self.value["exceptionHeap"], [23, 0, 0])
        self.assertEqual(self.value["valueOnlyGuard"], "exception")
        self.assertEqual(self.value["staleGeneration"], "stale-owner")
        self.assertEqual(self.value["isolatedDomain"], [0, 0, 0])

    def test_shared_function_calls_keep_execution_and_memory_budgets(self):
        self.assertEqual(self.value["sharedFunctionBudget"], "budget-exceeded")
        self.assertEqual(self.value["sharedFunctionMemory"], "memory-exceeded")

    def test_shared_handle_preserves_owner_identity_and_persistence(self):
        self.assertEqual(self.value["sharedForeignHandle"], [1, 0, 0])
        self.assertEqual(self.value["sharedForeignHandleMutations"], 0)
        self.assertEqual(self.value["sharedPersistentHandle"], [0, 0, 0])
        self.assertEqual(self.value["sharedPersistentHandleMutations"], 1)
