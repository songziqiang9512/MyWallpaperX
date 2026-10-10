"""Cursor-owned timers reuse real ValueOwner cadence and frame transactions."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static let animationTarget = SceneDynamicTarget.layer(layerID:3,field:.alpha)
    static func ownerTarget(_ id:Int=1) -> SceneDynamicTarget { .layer(layerID:id,field:.visibility) }
    static func descriptor() -> SceneRenderDescriptor {
        .init(layers:(1...3).map { id in
            .init(id:id,layerIndex:id-1,name:"layer\(id)",visible:true,
                originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[],sizeWH:[100,100])
        })
    }
    static func binding(_ source:String,_ id:Int=1) -> SceneScriptBindingIR {
        .init(source:source,owner:.init(kind:.object,objectIndex:id-1,objectID:id,
            effectIndex:nil,effectID:nil,passIndex:nil,passID:nil),
            targetPath:[.key("objects"),.index(id-1),.key("visible")],
            properties:[:],authoredValue:.bool(true),valueType:.boolean,wrapperKeys:["script","value"])
    }
    static func make(_ sources:[String]) throws -> SceneScriptCursorProgram {
        let d=try SceneScriptQuickJSDomain();let desc=descriptor()
        try d.configureLayerCatalog(desc)
        try d.configureNamedAnimations([(animationTarget,"fade")])
        try d.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(
            frameIndex:1,generation:1,definitions:[]).snapshot,descriptor:desc)
        let construction=SceneScriptCursorProgram.compileCandidate(domain:d,descriptor:desc,
            scriptBindings:sources.enumerated().map { binding($0.element,$0.offset+1) },
            rejectedTargets:[],generation:1)
        precondition(construction.failures.isEmpty && construction.program.ownerCount==sources.count)
        precondition(construction.program.bindings.allSatisfy(\.ownsOwner))
        return construction.program
    }
    static func frame(_ time:Double,_ step:Double) -> SceneScriptFrameInput {
        .init(timing:.init(wallDate:Date(timeIntervalSince1970:time),simulationFrameTime:step,sceneTime:time))
    }
    static func click(_ ids:[Int]=[1]) -> [SceneScriptCursorFrameSample] {
        let hits=Dictionary(uniqueKeysWithValues:ids.map { id in
            (id,SceneScriptCursorHit(layerID:id,worldPosition:.zero,localPosition:.zero))
        })
        return [false,true,false].map {
            .init(hits:hits,pointerPosition:.zero,primaryButtonIsDown:$0)
        }
    }
    static func dispatch(_ p:SceneScriptCursorProgram,_ samples:[SceneScriptCursorFrameSample],
                         _ time:Double,_ step:Double,_ overflow:Bool=false) -> SceneScriptCursorFrameResult {
        p.dispatch(batch:.init(samples:samples,overflowed:overflow),frame:frame(time,step),userPropertiesJSON:"{}")
    }
    static func pause(_ result:SceneScriptCursorFrameResult) -> Bool {
        result.animationMutations == [.init(target:animationTarget,command:.pause)]
            && result.ownerEffects.count==1
            && result.ownerEffects[0].ownerTarget==ownerTarget()
    }
    static let source="""
        let armed=false;
        export function cursorClick(e){
          if(armed){thisLayer.origin=new Vec3(thisLayer.alpha,0,0);return;}
          armed=true;const a=thisScene.getLayer('layer3').getAnimation('fade');a.play();
          engine.setTimeout(()=>{a.pause();thisLayer.alpha=.5;},1500);
        }
        """
    static func arm(_ p:SceneScriptCursorProgram) -> SceneScriptCursorFrameResult {
        let clicked=dispatch(p,click(),0,0);p.finalizeLayerMutations(committing:true)
        // Preserve the existing timer host's first-cadence baseline behavior.
        let waiting=dispatch(p,[],0.1,0.1);precondition(waiting.ownerEffects.isEmpty)
        p.finalizeLayerMutations(committing:true);return clicked
    }
    static func main() throws {
        var out:[String:Bool]=[:]
        let p=try make([source]);let owner=p.bindings[0].owner
        out["idleDoesNotRunVM"] = dispatch(p,[],0,0).ownerEffects.isEmpty
            && !mwx_scene_quickjs_owner_is_initialized(owner.handle)
        p.finalizeLayerMutations(committing:true)
        out["clickUsesNamedTarget"] = arm(p).animationMutations == [.init(target:animationTarget,command:.play)]
        let due=dispatch(p,[],1.6,1.5)
        out["noPointerBatchAdvancesTimer"] = pause(due) && due.failures.isEmpty
            && due.layerMutations.first?.alpha==0.5
        out["returnValueNotPublished"] = due.layerMutations.allSatisfy { !$0.fields.contains(.visibility) }
        p.finalizeLayerMutations(committing:true)
        out["acceptedTimerConsumedOnce"] = dispatch(p,[],1.7,0.1).ownerEffects.isEmpty
            && mwx_scene_quickjs_owner_active_timer_count(owner.handle)==0
        p.finalizeLayerMutations(committing:true)

        let ordered=try make([source]);_ = arm(ordered)
        let orderedResult=dispatch(ordered,click(),1.6,1.5)
        out["timerBeforeCursorInSameBundle"] = pause(orderedResult)
            && orderedResult.layerMutations.first?.origin.x==0.5
            && orderedResult.layerMutations.first?.alpha==0.5
        ordered.finalizeLayerMutations(committing:true)

        let overflow=try make([source]);_ = arm(overflow)
        let overflowResult=dispatch(overflow,click(),1.6,1.5,true)
        out["pointerOverflowDoesNotStopTimer"] = pause(overflowResult)
            && overflowResult.inputBatchOverflowed
            && overflowResult.layerMutations.allSatisfy { !$0.fields.contains(.origin) }
        overflow.finalizeLayerMutations(committing:true)

        let dropped=try make([source]);_ = arm(dropped)
        let savedEdges=dropped.edgeStateSnapshot(), savedTimers=dropped.timerFrameStateSnapshot()
        let rejected=dispatch(dropped,[],1.6,1.5)
        dropped.restoreEdgeState(savedEdges);dropped.finalizeLayerMutations(committing:false)
        dropped.restoreTimerFrameState(savedTimers);dropped.discardTimerFrameState(savedTimers)
        let retried=dispatch(dropped,[],1.6,1.5)
        out["droppedFrameRestoresTimer"] = pause(rejected) && pause(retried)
        dropped.finalizeLayerMutations(committing:true)
        out["restoredTimerConsumedOnce"] = dispatch(dropped,[],1.7,0.1).ownerEffects.isEmpty
        dropped.finalizeLayerMutations(committing:true)

        let failSource="""
          export function cursorClick(e){engine.setTimeout(()=>{
            thisLayer.alpha=.2;thisScene.getLayer('layer3').getAnimation('fade').pause();
            throw new Error('timer failure');},1500);}
          """
        let failed=try make([failSource,"export function cursorClick(e){thisLayer.alpha=.7;}"])
        _ = arm(failed)
        let failedEdges=failed.edgeStateSnapshot(), failedTimers=failed.timerFrameStateSnapshot()
        let failResult=dispatch(failed,click([1,2]),1.6,1.5)
        out["timerFailureIsolatesOwner"] = failResult.failures[ownerTarget()] != nil
            && failResult.failures[ownerTarget(2)]==nil
            && failResult.animationMutations.isEmpty
            && failResult.ownerEffects.map(\.ownerTarget)==[ownerTarget(2)]
            && failResult.layerMutations.map(\.layerID)==[2]
            && failResult.layerMutations[0].alpha==0.7
        failed.restoreEdgeState(failedEdges);failed.finalizeLayerMutations(committing:false)
        failed.restoreTimerFrameState(failedTimers);failed.discardTimerFrameState(failedTimers)
        out["rollbackDoesNotReviveFailedTimerOwner"] = dispatch(failed,[],1.6,1.5).ownerEffects.isEmpty
        failed.finalizeLayerMutations(committing:true)

        let d=try SceneScriptQuickJSDomain();let desc=descriptor();try d.configureLayerCatalog(desc)
        try d.configureNamedAnimations([(animationTarget,"fade")])
        try d.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(
            frameIndex:1,generation:1,definitions:[]).snapshot,descriptor:desc)
        let borrowedOwner=try SceneScriptValueOwner(domain:d,
            source:source+"\nexport function update(v){return v;}",
            target:.layer(layerID:1,field:.origin),effectNames:[],generation:1,budget:.default)
        let borrowed=SceneScriptCursorProgram(bindings:[.init(layerID:1,authoredOrdinal:0,
            owner:borrowedOwner,events:borrowedOwner.exportedCursorEvents,ownsOwner:false,
            scriptProperties:[:],ownerSeedValue:.vector3(0,0,0))],generation:1)
        _ = dispatch(borrowed,click(),0,0)
        _ = try borrowedOwner.evaluate(input:.vector3(0,0,0),frame:frame(0,0),
            scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
        borrowed.finalizeLayerMutations(committing:true);borrowedOwner.commitLayerMutations()
        let borrowedCursor=dispatch(borrowed,[],1.5,1.5)
        out["borrowedCursorDoesNotTick"] = borrowedCursor.ownerEffects.isEmpty
            && mwx_scene_quickjs_owner_active_timer_count(borrowedOwner.handle)==1
        let borrowedValue=try borrowedOwner.evaluate(input:.vector3(0,0,0),frame:frame(1.5,1.5),
            scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
        out["borrowedValueProgramTicksOnce"] = borrowedValue.animationMutations == [.init(target:animationTarget,command:.pause)]
            && mwx_scene_quickjs_owner_active_timer_count(borrowedOwner.handle)==0
        borrowed.finalizeLayerMutations(committing:true);borrowedOwner.commitLayerMutations()
        out["borrowedTimerDoesNotRepeat"] = dispatch(borrowed,[],1.6,0.1).ownerEffects.isEmpty
        borrowed.finalizeLayerMutations(committing:true);borrowedOwner.commitLayerMutations()

        for name in ["init","update"] {
            let rejected=SceneScriptCursorProgram.compileCandidate(domain:try SceneScriptQuickJSDomain(),
                descriptor:desc,scriptBindings:[binding("export function cursorClick(e){} export function \(name)(v){return v;}")],
                rejectedTargets:[],generation:1)
            out["stillRejects\(name)"] = rejected.program.ownerCount==0
                && rejected.failures[ownerTarget()] == .invalidSource
        }
        print(String(data:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''


class CursorTimerCadenceTests(unittest.TestCase):
    def test_standalone_timers_share_cursor_owner_transaction(self):
        with tempfile.TemporaryDirectory(prefix="mwx-cursor-timer-") as temporary:
            binary = compile_vector_harness(Path(temporary), HARNESS, "cursor-timer")
            run = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            actual = json.loads(run.stdout.strip().splitlines()[-1])
            self.assertEqual(actual, dict.fromkeys([
                "idleDoesNotRunVM", "clickUsesNamedTarget", "noPointerBatchAdvancesTimer",
                "returnValueNotPublished", "acceptedTimerConsumedOnce", "timerBeforeCursorInSameBundle",
                "pointerOverflowDoesNotStopTimer", "droppedFrameRestoresTimer", "restoredTimerConsumedOnce",
                "timerFailureIsolatesOwner", "rollbackDoesNotReviveFailedTimerOwner",
                "borrowedCursorDoesNotTick", "borrowedValueProgramTicksOnce", "borrowedTimerDoesNotRepeat",
                "stillRejectsinit", "stillRejectsupdate",
            ], True))


if __name__ == "__main__":
    unittest.main()
