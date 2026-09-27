"""Production cursor event confirmation after owner/frame rejection."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
    static func target(_ field: SceneDynamicLayerField = .origin, _ id: Int = 1) -> SceneDynamicTarget { .layer(layerID:id,field:field) }
    static func make(_ sources: [(SceneDynamicLayerField,String)], borrowed: Bool = false) throws -> (SceneScriptCursorProgram,[SceneScriptVectorOwner]) {
        let d = try SceneScriptQuickJSDomain()
        try d.configureLayerCatalog(.init(layers:[.init(id:1,layerIndex:0,name:"cursor",visible:true,
            originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])]))
        var bindings:[SceneScriptCursorBinding] = [];var owners:[SceneScriptVectorOwner] = []
        for (i,item) in sources.enumerated() {
            let o = try SceneScriptVectorOwner(domain:d,source:item.1,target:target(item.0),effectNames:[],
                allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
            owners.append(o)
            bindings.append(.init(layerID:1,authoredOrdinal:i,owner:o,events:o.exportedCursorEvents,
                ownsOwner:!borrowed,scriptProperties:[:],ownerSeedValue:.vector3(0,0,0)))
        }
        return (.init(bindings:bindings,generation:1),owners)
    }
    static func sample(_ x: Double, _ down: Bool, hit: Bool = true) -> SceneScriptCursorFrameSample {
        let h = SceneScriptCursorHit(layerID:1,worldPosition:.init(x*10,0,0),localPosition:.init(x,0,0))
        return .init(hits:hit ? [1:h] : [:],ownerProjections:[1:h],pointerPosition:.init(Float(x),0),
            primaryButtonIsDown:down,surface:.init(canvasSize:.init(100,100),screenSize:.init(100,100),
                cursorWorldPosition:.init(x*10,0,0),cursorScreenPosition:.init(x,0),cursorLeftDown:down))
    }
    static func click(_ x: Double) -> [SceneScriptCursorFrameSample] { [sample(x,false),sample(x,true),sample(x,false)] }
    static func dispatch(_ p: SceneScriptCursorProgram, _ samples:[SceneScriptCursorFrameSample], overflow:Bool = false) -> SceneScriptCursorFrameResult {
        p.dispatch(batch:.init(samples:samples,overflowed:overflow),frame:frame,userPropertiesJSON:"{}")
    }
    static func values(_ r: SceneScriptCursorFrameResult, _ field:SceneDynamicLayerField = .origin) -> [Double] {
        guard let m = r.ownerEffects.first(where:{$0.ownerTarget == target(field)})?.layerMutations.last else { return [] }
        return [m.origin.x,m.origin.y,m.origin.z]
    }
    static let clicks = """
      let xs=[];
      export function cursorClick(e) { xs.push(e.localPosition.x); thisLayer.origin=new Vec3(xs.length,xs.length>1?xs[xs.length-2]:0,input.cursorWorldPosition.x); }
      """
    static func main() throws {
        var out:[String:Any] = [:]
        // Distinct targets on the same layer share physical hit observation,
        // but only the rejected target retries its exact completed click.
        let (p,_) = try make([(.origin,clicks),(.scale,clicks)])
        let first = dispatch(p,click(10));out["first"] = values(first);out["firstPeer"] = values(first,.scale)
        p.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        let retried = dispatch(p,[sample(99,false)]);out["retried"] = values(retried);out["retriedPeer"] = values(retried,.scale)
        p.finalizeLayerMutations(committing:true)
        out["confirmedQuiet"] = dispatch(p,[sample(99,false)]).ownerEffects.isEmpty
        p.finalizeLayerMutations(committing:true)

        // All event envelopes are recognized before an init BAD_RETURN can
        // prevent callbacks from running; capture is retained even without down.
        let (early,_) = try make([(.origin,"""
            let initCount=0; let events=0;
            export function init(v){if(++initCount===1)return {};return v;}
            function record(n){events=events*10+n;thisLayer.origin=new Vec3(events,0,0);}
            export function cursorEnter(e){record(1);}
            export function cursorDown(e){record(2);}
            export function cursorUp(e){record(3);}
            export function cursorClick(e){record(4);}
            """)])
        let earlyFailure = dispatch(early,click(10));out["earlyFailure"] = earlyFailure.failures[target()]?.code ?? "none"
        early.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["earlyRetry"] = values(dispatch(early,[sample(10,false)]));early.finalizeLayerMutations(committing:true)
        let (upOnly,_) = try make([(.origin,"export function cursorUp(e){thisLayer.origin=new Vec3(e.localPosition.x,0,0);}")])
        _ = dispatch(upOnly,click(15));upOnly.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["upOnlyRetry"] = values(dispatch(upOnly,[sample(40,false)]));upOnly.finalizeLayerMutations(committing:true)

        let (surface,_) = try make([(.origin,"""
            let n=0;
            function check(e,down){
                if(e.localPosition.x!==10 || e.worldPosition.x!==100 || input.cursorWorldPosition.x!==100 ||
                   input.cursorScreenPosition.x!==10 || input.cursorLeftDown!==down)throw new Error('input changed');
                thisLayer.origin=new Vec3(++n,engine.runtime,0);
            }
            export function cursorDown(e){check(e,true);} export function cursorUp(e){check(e,false);}
            """)])
        _ = dispatch(surface,click(10));surface.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        let laterFrame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:3),simulationFrameTime:0.016,sceneTime:3))
        let exact = surface.dispatch(batch:.init(samples:[sample(99,false)],overflowed:false),frame:laterFrame,userPropertiesJSON:"{}")
        out["savedSurfaceFailures"] = exact.failures.count;out["savedSurfaceRetry"] = values(exact)
        surface.finalizeLayerMutations(committing:true)

        // A previously pending click plus new physical input is discarded as
        // a frame, then rebuilt once from the restored pointer batch.
        let (whole,_) = try make([(.origin,clicks)])
        _ = dispatch(whole,click(10));whole.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        let before = whole.edgeStateSnapshot()
        out["droppedCandidate"] = values(dispatch(whole,click(20)))
        whole.restoreEdgeState(before);whole.finalizeLayerMutations(committing:false)
        out["wholeRetry"] = values(dispatch(whole,click(20)))
        whole.finalizeLayerMutations(committing:true)
        out["wholeQuiet"] = dispatch(whole,[sample(20,false)]).ownerEffects.isEmpty
        whole.finalizeLayerMutations(committing:true)

        // Incomplete new raw input cannot erase an older complete pending click.
        let (overflow,_) = try make([(.origin,clicks)])
        _ = dispatch(overflow,click(10));overflow.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["rawOverflow"] = dispatch(overflow,[sample(77,false)],overflow:true).inputBatchOverflowed
        overflow.finalizeLayerMutations(committing:true)
        out["afterRawOverflow"] = values(dispatch(overflow,[sample(77,false)]))
        overflow.finalizeLayerMutations(committing:true)

        // Borrowed cursor events share the later vector result. A recoverable
        // update failure retries, and accepted events are confirmed by cursor.
        let (borrowed,owners) = try make([(.origin,clicks+"\nlet updates=0; export function update(v){if(++updates===1)return {};return v;}")],borrowed:true)
        _ = dispatch(borrowed,click(10))
        let update = owners[0].evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        if case let .failure(f) = update {out["borrowedUpdateFailure"] = f.code}
        borrowed.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()]);owners[0].discardLayerMutations()
        out["borrowedRetry"] = values(dispatch(borrowed,[sample(10,false)]))
        borrowed.finalizeLayerMutations(committing:true);owners[0].commitLayerMutations()
        out["borrowedQuiet"] = dispatch(borrowed,[sample(10,false)]).ownerEffects.isEmpty
        borrowed.finalizeLayerMutations(committing:true);owners[0].commitLayerMutations()

        // A permanent owner fuse cannot be revived by an old edge snapshot.
        let (disabled,disabledOwners) = try make([(.origin,clicks+"\nexport function update(v){throw new Error('stop');}")],borrowed:true)
        _ = dispatch(disabled,click(10));disabled.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()]);disabledOwners[0].discardLayerMutations()
        let saved = disabled.edgeStateSnapshot()
        _ = disabledOwners[0].evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        let dead = dispatch(disabled,[sample(10,false)]);out["disabledFailure"] = dead.failures[target()]?.code ?? "none"
        disabled.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        disabled.restoreEdgeState(saved);disabled.finalizeLayerMutations(committing:false)
        out["disabledQuiet"] = dispatch(disabled,[sample(10,false)]).failures.isEmpty

        // Refuse an entire overflowing target before executing a partial press
        // sequence. Another target on that very layer remains eligible.
        let (budget,budgetOwners) = try make([(.origin,clicks+"\nexport function update(v){return v;}"),(.scale,"export function cursorEnter(e){thisLayer.origin=new Vec3(900,0,0);}")],borrowed:true)
        let crowded = dispatch(budget,(0..<4097).flatMap{_ in click(10)})
        out["budgetFailure"] = crowded.failures[target()]?.code ?? "none";out["budgetUnsafe"] = values(crowded);out["budgetPeer"] = values(crowded,.scale)
        budget.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["budgetQuiet"] = dispatch(budget,[sample(10,false)]).failures.isEmpty
        let budgetUpdate = budgetOwners[0].evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        if case let .failure(f) = budgetUpdate { out["budgetBorrowedFailure"] = f.code } else { out["budgetBorrowedFailure"] = "none" }
        let (burst,_) = try make([(.origin,"""
            let n=0;function add(){thisLayer.origin=new Vec3(++n,0,0);}
            export function cursorEnter(e){add();} export function cursorDown(e){add();}
            export function cursorUp(e){add();} export function cursorClick(e){add();}
            """)])
        let burstResult = dispatch(burst,(0..<170).flatMap{_ in click(10)})
        out["burstValue"] = values(burstResult);out["burstFailures"] = burstResult.failures.count
        burst.finalizeLayerMutations(committing:true)
        let (accumulated,_) = try make([(.origin,"export function cursorClick(e){}")])
        var accumulatedFailure = "none"
        for index in 0..<65 {
            let result = dispatch(accumulated,(0..<64).flatMap{_ in click(10)})
            if let failure = result.failures[target()] { accumulatedFailure = failure.code;out["accumulatedFailureBatch"] = index+1 }
            accumulated.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        }
        out["accumulatedFailure"] = accumulatedFailure
        out["accumulatedPendingCleared"] = accumulated.edgeStateSnapshot().pendingEvents.isEmpty
        let (invalidated,_) = try make([(.origin,clicks)])
        _ = dispatch(invalidated,click(10));invalidated.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()]);invalidated.invalidate()
        out["invalidatedQuiet"] = dispatch(invalidated,[]).ownerEffects.isEmpty
        let (ended,_) = try make([(.origin,clicks)])
        _ = dispatch(ended,click(10));ended.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        _ = ended.teardown(frame:frame,userPropertiesJSON:"{}")
        out["teardownPendingEmpty"] = ended.edgeStateSnapshot().pendingEvents.isEmpty
        print(String(data:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class CursorOwnerTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-cursor-owner-test-") as temp:
            binary=compile_vector_harness(Path(temp),HARNESS,"cursor-owner")
            run=subprocess.run([str(binary)],capture_output=True,text=True,check=True)
            cls.result=json.loads(run.stdout.strip().splitlines()[-1])

    def test_rejected_same_layer_target_retries_exact_input_without_replaying_peer(self):
        self.assertEqual(self.result["first"],[1,0,100]);self.assertEqual(self.result["firstPeer"],[1,0,100])
        self.assertEqual(self.result["retried"],[2,10,100]);self.assertEqual(self.result["retriedPeer"],[])
        self.assertTrue(self.result["confirmedQuiet"])

    def test_init_failure_preserves_entire_press_release_sequence(self):
        self.assertEqual(self.result["earlyFailure"],"bad-return")
        self.assertEqual(self.result["earlyRetry"],[1234,0,0])
        self.assertEqual(self.result["upOnlyRetry"],[15,0,0])

    def test_saved_event_and_surface_inputs_use_current_frame_clock(self):
        self.assertEqual(self.result["savedSurfaceFailures"],0)
        self.assertEqual(self.result["savedSurfaceRetry"],[4,3,0])

    def test_whole_frame_restore_does_not_duplicate_prior_or_new_events(self):
        self.assertEqual(self.result["droppedCandidate"],[3,10,200])
        self.assertEqual(self.result["wholeRetry"],[5,10,200])
        self.assertTrue(self.result["wholeQuiet"])

    def test_new_raw_overflow_preserves_prior_complete_event(self):
        self.assertTrue(self.result["rawOverflow"])
        self.assertEqual(self.result["afterRawOverflow"],[2,10,100])

    def test_borrowed_update_rejection_retries_and_confirms(self):
        self.assertEqual(self.result["borrowedUpdateFailure"],"bad-return")
        self.assertEqual(self.result["borrowedRetry"],[2,10,100]);self.assertTrue(self.result["borrowedQuiet"])

    def test_permanent_fuse_is_not_revived_by_edge_restore(self):
        self.assertEqual(self.result["disabledFailure"],"disabled");self.assertTrue(self.result["disabledQuiet"])

    def test_pending_budget_rejects_whole_target_and_preserves_peer(self):
        self.assertEqual(self.result["budgetFailure"],"mutation-overflow")
        self.assertEqual(self.result["budgetUnsafe"],[]);self.assertEqual(self.result["budgetPeer"],[900,0,0])
        self.assertTrue(self.result["budgetQuiet"])
        self.assertIn(self.result["budgetBorrowedFailure"],["disabled","stale-owner"])

    def test_full_fresh_input_batch_can_expand_past_256_callbacks(self):
        self.assertEqual(self.result["burstValue"],[511,0,0]);self.assertEqual(self.result["burstFailures"],0)

    def test_repeated_legal_batches_bound_rejected_event_backlog(self):
        self.assertEqual(self.result["accumulatedFailure"],"mutation-overflow")
        self.assertEqual(self.result["accumulatedFailureBatch"],65)
        self.assertTrue(self.result["accumulatedPendingCleared"])

    def test_invalidate_and_teardown_clear_pending_input(self):
        self.assertTrue(self.result["invalidatedQuiet"]);self.assertTrue(self.result["teardownPendingEmpty"])

if __name__ == "__main__": unittest.main()
