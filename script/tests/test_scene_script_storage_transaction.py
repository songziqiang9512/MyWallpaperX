"""Production Swift/C localStorage owner journal, read dependency and quota gates."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970:0), simulationFrameTime: 0.016, sceneTime: 1))
    static func target(_ id: Int) -> SceneDynamicTarget { .layer(layerID: id, field: .origin) }
    static func session(_ name: String) -> SceneScriptLocalStorageSession {
        .init(recordID: name, rootDirectory: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
    static func mutation(_ kind: SceneScriptStorageMutation.Kind, _ key: String? = nil,
                         _ json: String? = nil, screen: String? = nil) -> SceneScriptStorageMutation {
        .init(kind: kind, globalScope: screen == nil, screenIdentity: screen, key: key, json: json)
    }
    static func value(_ s: SceneScriptLocalStorageSession, _ key: String, screen: String? = nil) throws -> String {
        try s.read(screenIdentity: screen, globalScope: screen == nil, key: key).get() ?? "missing"
    }
    static func write(_ s: SceneScriptLocalStorageSession, _ owner: Int, _ mutations: [SceneScriptStorageMutation]) throws {
        try s.apply(mutations, owner: UInt(owner), target: target(owner))
    }
    static func domain(_ s: SceneScriptLocalStorageSession) throws -> SceneScriptQuickJSDomain {
        let d = try SceneScriptQuickJSDomain(); try d.configureStorage(s); try d.setStorageScreenIdentity("one")
        try d.configureLayerCatalog(.init(layers: (1...8).map { id in .init(id: id, layerIndex: id-1, name: "owner\(id)",
            visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: nil, alpha: 1, effects: []) }))
        return d
    }
    static func owner(_ d: SceneScriptQuickJSDomain, _ id: Int, _ source: String) throws -> SceneScriptValueOwner {
        try .init(domain: d, source: source, target: target(id), effectNames: [],
            allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
    }
    static func run(_ o: SceneScriptValueOwner) throws -> Double {
        let result = try o.evaluate(input: .vector3(0,0,0), frame: frame, scriptPropertiesJSON: "",
            userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        try o.commitStorage().get()
        if case let .vector3(x,_,_) = result.value { return x }; return -1
    }
    static func ids(_ rejected: Set<SceneDynamicTarget>) -> [Int] {
        (1...8).filter { rejected.contains(target($0)) }
    }
    static func main() throws {
        var out: [String:Any] = [:]
        let active = session("activation")
        try active.apply([mutation(.set,"seed","1"), mutation(.set,"deleted","7")])
        let candidate = SceneScriptLocalStorageSession(recordID:"activation",
            rootDirectory:URL(fileURLWithPath:CommandLine.arguments[1]), defersPersistence:true)
        _ = try value(candidate,"seed")
        try candidate.apply([mutation(.set,"seed","2"), mutation(.delete,"deleted")])
        try active.apply([mutation(.set,"peer","3")])
        out["candidateBeforePromotion"] = try [value(candidate,"seed"), value(session("activation"),"seed")]
        active.retirePersistence()
        candidate.activatePersistence(replacing:active)
        out["candidateMerged"] = try [value(candidate,"seed"),value(candidate,"peer"),value(candidate,"deleted")]
        try active.apply([mutation(.set,"seed","99")])
        out["retiredCannotPublish"] = try value(session("activation"),"seed")
        let abandoned = SceneScriptLocalStorageSession(recordID:"activation",
            rootDirectory:URL(fileURLWithPath:CommandLine.arguments[1]), defersPersistence:true)
        try abandoned.apply([mutation(.set,"seed","88")])
        out["abandonedCannotPublish"] = try value(session("activation"),"seed")
        // Same-key overwrite/no-op must retain the later writer, even when
        // its operation initially left the merged candidate unchanged.
        let same = session("same"); _ = same.beginFrameTransaction()
        try write(same, 1, [mutation(.set,"k","1")]); try write(same, 2, [mutation(.set,"k","1")])
        out["sameRejected"] = ids(same.resolveRejectedOwners([target(1)]))
        same.commitFrameTransaction(); out["sameValue"] = try value(same,"k")
        let order = session("order"); try order.apply([mutation(.set,"base","9")]); _ = order.beginFrameTransaction()
        try write(order,1,[mutation(.set,"k","1")]);try write(order,2,[mutation(.clear)]);try write(order,3,[mutation(.set,"j","3")])
        _ = order.resolveRejectedOwners([target(2)]);order.commitFrameTransaction()
        out["orderedValues"] = try [value(order,"base"),value(order,"k"),value(order,"j")]
        let repeated = session("repeated");_ = repeated.beginFrameTransaction()
        try write(repeated,1,[mutation(.set,"k","1")]);try write(repeated,2,[mutation(.set,"k","2")]);try write(repeated,1,[mutation(.set,"j","3")])
        _ = repeated.resolveRejectedOwners([target(1)]);repeated.commitFrameTransaction()
        out["allBatchesRetracted"] = try [value(repeated,"k"),value(repeated,"j")]

        // Actual C getters (including the implicit read in delete) create
        // transitive dependencies. Owner 4 is a read-only typed consumer.
        let s = session("dependencies");let d = try domain(s);_ = s.beginFrameTransaction()
        let a = try owner(d,1,"export function update(v){localStorage.set('k',5,'global');return v;}")
        let b = try owner(d,2,"export function update(v){localStorage.set('j',localStorage.get('k','global')+1,'global');return v;}")
        let c = try owner(d,3,"export function update(v){localStorage.set('m',localStorage.get('j','global')+1,'global');return v;}")
        let reader = try owner(d,4,"export function update(v){return new Vec3(localStorage.get('m','global'),0,0);}")
        let independent = try owner(d,5,"export function update(v){localStorage.set('safe',8,'global');return new Vec3(8,0,0);}")
        _ = try run(a);_ = try run(b);_ = try run(c);out["provisionalRead"] = try run(reader);_ = try run(independent)
        let runtime = SceneScriptDynamicLayerRuntime(descriptor: .init(layers: []), authoredMutationLayerIDs: [])
        let fixed = runtime.preflightOwnerEffectsToFixedPoint([], excludingOwners: [target(1)],
            rejectingDependents: { s.resolveRejectedOwners($0) }) { _ in [] }
        out["dependencyRejected"] = ids(fixed.externallyRejectedOwners)
        s.commitFrameTransaction();out["dependencyValues"] = try [value(s,"k"),value(s,"j"),value(s,"m"),value(s,"safe")]
        // The exact same VM handles are reused next frame; old dependency edges
        // must not retract a reader when its input is now committed baseline.
        _ = s.beginFrameTransaction();_ = try run(independent);_ = s.resolveRejectedOwners([]);s.commitFrameTransaction()
        _ = s.beginFrameTransaction();out["freshRejected"] = ids(s.resolveRejectedOwners([target(1)]));s.discardFrameTransaction()

        let clear = session("clear");try clear.apply([mutation(.set,"k","4")]);let dc = try domain(clear);_ = clear.beginFrameTransaction()
        let ca = try owner(dc,1,"export function update(v){localStorage.clear('global');return v;}")
        let cb = try owner(dc,2,"export function update(v){return new Vec3(localStorage.get('k','global')===undefined?1:0,0,0);}")
        let cd = try owner(dc,3,"export function update(v){return new Vec3(localStorage.delete('k','global')?1:0,0,0);}")
        _ = try run(ca);out["missingRead"] = try run(cb);out["missingDelete"] = try run(cd)
        out["clearRejected"] = ids(clear.resolveRejectedOwners([target(1)]));clear.commitFrameTransaction();out["clearRestored"] = try value(clear,"k")

        let scopes = session("scopes");let ds = try domain(scopes);_ = scopes.beginFrameTransaction()
        let sa = try owner(ds,1,"export function update(v){localStorage.set('k',9);return v;}")
        let sb = try owner(ds,2,"export function update(v){return new Vec3(localStorage.get('k')||0,0,0);}")
        let sg = try owner(ds,3,"export function update(v){return new Vec3(localStorage.get('k','global')||0,0,0);}")
        _ = try run(sa);try ds.setStorageScreenIdentity("two");out["otherScreenRead"] = try run(sb);out["globalRead"] = try run(sg)
        out["scopeRejected"] = ids(scopes.resolveRejectedOwners([target(1)]));scopes.commitFrameTransaction()

        // A prior callback may write storage before another owner's update,
        // while authored layer admission still orders that reader first.
        let stable = session("stable-seeds"); let stableDomain = try domain(stable)
        _ = stable.beginFrameTransaction()
        let seed = try owner(stableDomain,1,"export function update(v){localStorage.set('seed',1,'global');thisScene.getLayerByID(8).alpha=0.3;return v;}")
        let dependent = try owner(stableDomain,2,"export function update(v){localStorage.get('seed','global');thisScene.getLayerByID(8).alpha=0.2;return v;}")
        let peer = try owner(stableDomain,3,"export function update(v){localStorage.set('safe',8,'global');thisScene.getLayerByID(7).alpha=0.7;return v;}")
        func effects(_ o: SceneScriptValueOwner) throws -> SceneScriptOwnerEffects {
            let result = try o.evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",
                userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
            try o.commitStorage().get()
            return .init(ownerTarget:o.target,materialFunctionMutations:[],animationMutations:[],
                layerMutations:result.layerMutations,videoCommands:[])
        }
        let seedEffects = try effects(seed), dependentEffects = try effects(dependent), peerEffects = try effects(peer)
        let orderedEffects = [dependentEffects,seedEffects,peerEffects]
        let descriptor = SceneRenderDescriptor(layers:(1...8).map { id in .init(id:id,layerIndex:id-1,
            name:"owner\(id)",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[]) })
        let recoveringRuntime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[7,8])
        let recovery = recoveringRuntime.preflightOwnerEffectsToFixedPoint(orderedEffects) { admitted in
            admitted.contains { $0.ownerTarget == target(2) } ? [target(2)] : []
        }
        out["runtimeRecoveryAccepted"] = ids(Set(recovery.admission.admittedEffects.map(\.ownerTarget)))
        out["runtimeRecoveryRejected"] = ids(recovery.externallyRejectedOwners)
        let stableRuntime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[7,8])
        let stableAdmission = stableRuntime.preflightOwnerEffectsToFixedPoint(orderedEffects,
            rejectingDependents:{stable.resolveRejectedOwners($0)}) { _ in [] }
        out["stableAccepted"] = ids(Set(stableAdmission.admission.admittedEffects.map(\.ownerTarget)))
        out["stableRejected"] = ids(stableAdmission.externallyRejectedOwners)
        out["stableSeedDiagnostics"] = ids(Set(stableAdmission.admission.rejectedOwners.compactMap(\.ownerTarget)))
        stableRuntime.commit(stableAdmission.admission.layerPlan)
        let published = stableRuntime.snapshot().authoredLayerValues
        out["stableSeedWasNotPublished"] = published[.layer(layerID:8,field:.alpha)] == nil
        out["stablePeerPublished"] = published[.layer(layerID:7,field:.alpha)] == .scalar(0.7)
        stable.commitFrameTransaction();out["stableStorage"] = try [value(stable,"seed"),value(stable,"safe")]

        // Deleting a committed key makes room for a later writer. Removing that
        // deletion must reject the now-overquota writer and its readers.
        let quota = session("quota");try quota.apply((0..<256).map { mutation(.set,"k\($0)","1") });_ = quota.beginFrameTransaction()
        try write(quota,1,[mutation(.delete,"k0")]);try write(quota,2,[mutation(.set,"new","2")])
        _ = try quota.read(screenIdentity:nil,globalScope:true,key:"new",owner:3).get();try write(quota,3,[])
        out["quotaRejected"] = ids(quota.resolveRejectedOwners([target(1)]));quota.commitFrameTransaction()
        out["quotaValues"] = try [value(quota,"k0"),value(quota,"new")]
        _ = quota.beginFrameTransaction()
        try write(quota,1,[mutation(.set,"new","2"),mutation(.delete,"k0")]) // legal batch final state
        try write(quota,2,[mutation(.set,"k1","7")])
        out["batchRejected"] = ids(quota.resolveRejectedOwners([target(2)]));quota.commitFrameTransaction()
        out["batchValues"] = try [value(quota,"k0"),value(quota,"new"),value(quota,"k1")]

        // Empty clear after an earlier clear still owns the missing value.
        let tombstone = session("tombstone");try tombstone.apply([mutation(.set,"k","1")]);_ = tombstone.beginFrameTransaction()
        try write(tombstone,1,[mutation(.clear)]);try write(tombstone,2,[mutation(.clear)])
        _ = try tombstone.read(screenIdentity:nil,globalScope:true,key:"k",owner:3).get();try write(tombstone,3,[])
        out["noopClearRejected"] = ids(tombstone.resolveRejectedOwners([target(1)]));tombstone.commitFrameTransaction()
        out["noopClearValue"] = try value(tombstone,"k")

        let rollback = session("rollback");try rollback.apply([mutation(.set,"k","0")]);_ = rollback.beginFrameTransaction()
        try write(rollback,1,[mutation(.set,"k","1")]);try write(rollback,2,[mutation(.set,"j","2")])
        _ = rollback.resolveRejectedOwners([target(1)]);rollback.discardFrameTransaction()
        out["wholeFrameValues"] = try [value(rollback,"k"),value(rollback,"j")]
        _ = rollback.beginFrameTransaction();try write(rollback,1,[mutation(.set,"k","3")]);rollback.commitFrameTransaction()
        out["nextFrameValue"] = try value(rollback,"k")

        let identity = session("identity");_ = identity.beginFrameTransaction();try write(identity,1,[mutation(.set,"k","1")])
        do { try identity.apply([],owner:1,target:target(2));out["identityFailure"] = "none" }
        catch let f as SceneScriptScalarRuntimeFailure { out["identityFailure"] = f.code }
        out["identityRejected"] = ids(identity.resolveRejectedOwners([]));identity.commitFrameTransaction();out["identityValue"] = try value(identity,"k")

        // Many overwritten values leave a tiny final envelope but must still
        // hit a bounded frame journal, then release the budget on discard.
        let budget = session("budget");_ = budget.beginFrameTransaction();var accepted = 0
        do { for _ in 0..<100 { try write(budget,1,[mutation(.set,"k","\""+String(repeating:"a",count:60_000)+"\"")]);accepted += 1 } }
        catch let f as SceneScriptScalarRuntimeFailure { out["journalFailure"] = f.code }
        out["journalAccepted"] = accepted;budget.discardFrameTransaction();_ = budget.beginFrameTransaction()
        try write(budget,1,[mutation(.set,"ok","1")]);budget.commitFrameTransaction();out["journalReset"] = try value(budget,"ok")
        let edges = session("edges");_ = edges.beginFrameTransaction()
        for i in 1...64 { try edges.apply([mutation(.set,"k\(i)","1")],owner:UInt(i),target:target(i+10000)) }
        for reader in 1000..<1256 {
            for writer in 1...64 { _ = try edges.read(screenIdentity:nil,globalScope:true,key:"k\(writer)",owner:UInt(reader)).get() }
            try write(edges,reader,[])
        }
        // Two-phase C reads must not double charge a previously recorded edge.
        out["duplicateRead"] = try edges.read(screenIdentity:nil,globalScope:true,key:"k1",owner:1000).get() ?? "missing"
        do { _ = try edges.read(screenIdentity:nil,globalScope:true,key:"k1",owner:2000).get();out["edgeBudget"] = "none" }
        catch let f as SceneScriptScalarRuntimeFailure { out["edgeBudget"] = f.code }
        let edgeDomain = try domain(edges)
        let caught = try owner(edgeDomain,8,"export function update(v){try { localStorage.get('k1','global'); } catch(e) {} return new Vec3(77,0,0);}")
        out["caughtBudgetValue"] = try run(caught)
        let caughtRejections = edges.resolveRejectedOwners([])
        out["caughtBudgetRejected"] = caughtRejections.contains(target(8))
        out["caughtBudgetRejectionCount"] = caughtRejections.count
        edges.discardFrameTransaction()
        let operations = session("operations");_ = operations.beginFrameTransaction();var count = 0
        do { for _ in 0..<4100 { try write(operations,1,[mutation(.set,"k","1")]);count += 1 } }
        catch let f as SceneScriptScalarRuntimeFailure { out["operationBudget"] = f.code }
        out["operationCount"] = count;operations.discardFrameTransaction()
        let replay = session("replay");try replay.apply((0..<256).map { mutation(.set,"k\($0)","1") });_ = replay.beginFrameTransaction()
        try write(replay,1,[mutation(.delete,"k0")])
        for _ in 0..<1000 { try write(replay,2,[mutation(.set,"k1","2")]) }
        for owner in 100..<120 {
            try write(replay,owner,[mutation(.set,"new","1")])
            try write(replay,owner,[mutation(.delete,"new")])
        }
        let bounded = replay.resolveRejectedOwners([target(1)]);out["replayParticipantsRejected"] = bounded.count
        replay.commitFrameTransaction();out["replayBaseline"] = try [value(replay,"k0"),value(replay,"k1"),value(replay,"new")]
        let cumulative = session("cumulative");_ = cumulative.beginFrameTransaction()
        try write(cumulative,1,[mutation(.set,"a","1")])
        for _ in 0..<200 { try write(cumulative,2,[mutation(.set,"b","2")]) }
        var cumulativeRejected: Set<SceneDynamicTarget> = []
        for _ in 0..<100 { cumulativeRejected = cumulative.resolveRejectedOwners([target(1)]) }
        out["cumulativeRejected"] = ids(cumulativeRejected)
        cumulative.commitFrameTransaction();out["cumulativeValues"] = try [value(cumulative,"a"),value(cumulative,"b")]
        _ = cumulative.beginFrameTransaction();try write(cumulative,1,[mutation(.set,"a","3")]);try write(cumulative,2,[mutation(.set,"b","4")])
        out["cumulativeResetRejected"] = ids(cumulative.resolveRejectedOwners([target(1)]))
        cumulative.commitFrameTransaction();out["cumulativeResetValue"] = try value(cumulative,"b")
        Thread.sleep(forTimeInterval:0.5)
        out["persistedValues"] = try [value(session("dependencies"),"safe"),value(session("dependencies"),"k"),value(session("quota"),"new")]
        print(String(data: try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class StorageTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-storage-owner-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        root=Path(cls.temp.name)
        binary=compile_vector_harness(root,HARNESS,"storage-owner")
        run=subprocess.run([str(binary),str(root/"store")],capture_output=True,text=True,check=True)
        cls.result=json.loads(run.stdout.strip().splitlines()[-1])

    def test_candidate_storage_is_private_until_promotion_and_merges_active_peer_writes(self):
        self.assertEqual(self.result["candidateBeforePromotion"], ["2", "1"])
        self.assertEqual(self.result["candidateMerged"], ["2", "3", "missing"])
        self.assertEqual(self.result["retiredCannotPublish"], "2")
        self.assertEqual(self.result["abandonedCannotPublish"], "2")

    def test_ordered_overwrite_noop_clear_and_all_owner_batches(self):
        self.assertEqual(self.result["sameRejected"],[1]);self.assertEqual(self.result["sameValue"],"1")
        self.assertEqual(self.result["orderedValues"],["9","1","3"])
        self.assertEqual(self.result["allBatchesRetracted"],["2","missing"])
        self.assertEqual(self.result["noopClearRejected"],[1]);self.assertEqual(self.result["noopClearValue"],"missing")

    def test_transitive_and_read_only_outputs_rejected_independent_peer_persists(self):
        self.assertEqual(self.result["provisionalRead"],7)
        self.assertEqual(self.result["dependencyRejected"],[1,2,3,4])
        self.assertEqual(self.result["dependencyValues"],["missing","missing","missing","8"])
        self.assertEqual(self.result["freshRejected"],[1])
        self.assertEqual(self.result["persistedValues"],["8","missing","2"])

    def test_missing_get_and_delete_depend_on_clear(self):
        self.assertEqual(self.result["missingRead"],1);self.assertEqual(self.result["missingDelete"],0)
        self.assertEqual(self.result["clearRejected"],[1,2,3]);self.assertEqual(self.result["clearRestored"],"4")

    def test_runtime_recovery_precedes_stable_storage_rejection(self):
        self.assertEqual(self.result["runtimeRecoveryAccepted"],[1,3])
        self.assertEqual(self.result["runtimeRecoveryRejected"],[2])
        self.assertEqual(self.result["stableAccepted"],[3])
        self.assertEqual(self.result["stableRejected"],[1,2])
        self.assertEqual(self.result["stableSeedDiagnostics"],[1])
        self.assertTrue(self.result["stableSeedWasNotPublished"])
        self.assertTrue(self.result["stablePeerPublished"])
        self.assertEqual(self.result["stableStorage"],["missing","8"])

    def test_screen_and_global_scopes_do_not_create_false_dependencies(self):
        self.assertEqual(self.result["otherScreenRead"],0);self.assertEqual(self.result["globalRead"],0)
        self.assertEqual(self.result["scopeRejected"],[1])

    def test_quota_revalidation_preserves_original_batch_boundary(self):
        self.assertEqual(self.result["quotaRejected"],[1,2,3]);self.assertEqual(self.result["quotaValues"],["1","missing"])
        self.assertEqual(self.result["batchRejected"],[2]);self.assertEqual(self.result["batchValues"],["missing","2","1"])

    def test_whole_frame_rollback_and_next_frame_reset(self):
        self.assertEqual(self.result["wholeFrameValues"],["0","missing"]);self.assertEqual(self.result["nextFrameValue"],"3")

    def test_token_identity_change_fails_closed(self):
        self.assertEqual(self.result["identityFailure"],"invalid-argument")
        self.assertEqual(self.result["identityRejected"],[1]);self.assertEqual(self.result["identityValue"],"missing")

    def test_overwrite_journal_budget_is_bounded_and_released(self):
        self.assertEqual(self.result["journalFailure"],"budget-exceeded")
        self.assertGreater(self.result["journalAccepted"],0);self.assertLess(self.result["journalAccepted"],100)
        self.assertEqual(self.result["journalReset"],"1")

    def test_read_edges_deduplicate_and_have_a_frame_budget(self):
        self.assertEqual(self.result["duplicateRead"],"1")
        self.assertEqual(self.result["edgeBudget"],"budget-exceeded")

    def test_operation_and_replay_work_are_bounded(self):
        self.assertEqual(self.result["operationBudget"],"budget-exceeded")
        self.assertEqual(self.result["operationCount"],4096)
        self.assertEqual(self.result["replayParticipantsRejected"],22)
        self.assertEqual(self.result["replayBaseline"],["1","1","missing"])

    def test_replay_budget_accumulates_across_host_fixed_point_rounds(self):
        self.assertEqual(self.result["cumulativeRejected"],[1,2])
        self.assertEqual(self.result["cumulativeValues"],["missing","missing"])
        self.assertEqual(self.result["cumulativeResetRejected"],[1])
        self.assertEqual(self.result["cumulativeResetValue"],"4")

    def test_catching_a_c_read_budget_error_cannot_commit_the_owner_output(self):
        self.assertEqual(self.result["caughtBudgetValue"],77)
        self.assertTrue(self.result["caughtBudgetRejected"])
        self.assertEqual(self.result["caughtBudgetRejectionCount"],1)
