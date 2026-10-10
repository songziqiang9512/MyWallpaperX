"""Real QuickJS named Timeline commands retain typed target and owner rollback."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: (1...3).map { id in
            .init(id:id,layerIndex:id-1,name:"layer\(id)",visible:true,
                originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])
        })
        let a = SceneDynamicTarget.layer(layerID:2,field:.alpha)
        let b = SceneDynamicTarget.layer(layerID:3,field:.alpha)
        let current = SceneDynamicTarget.layer(layerID:1,field:.alpha)
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.configureNamedAnimations([(a,"fade"),(b,"fade")])
        try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(
            frameIndex:1,generation:1,definitions:[]).snapshot,descriptor:descriptor)
        func owner(_ source:String) throws -> SceneScriptValueOwner {
            try .init(domain:domain,source:source,target:current,valueType:.scalar,
                effectNames:[],hasCurrentAnimation:true,generation:1,budget:.default)
        }
        func evaluate(_ o:SceneScriptValueOwner,_ time:Double=0) throws -> SceneScriptValueEvaluation {
            try o.evaluate(input:.scalar(1),frame:.init(timing:.init(
                wallDate:Date(timeIntervalSince1970:time),simulationFrameTime:0.016,sceneTime:time)),
                scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
        }
        let retained = try owner("""
        let a,b,own,n=0;
        export function init(v){a=thisScene.getLayer('layer2').getAnimation('fade');
          b=thisScene.getLayer('layer3').getAnimation('fade');own=thisObject.getAnimation();return v;}
        export function update(v){if(n++===0){a.play();b.pause();own.stop();}
          else {a.pause();b.play();}return v;}
        """)
        let first = try evaluate(retained).animationMutations
        let second = try evaluate(retained,1).animationMutations
        let failed = try owner("export function update(v){thisScene.getLayer('layer2').getAnimation('fade').play();throw new Error('rollback');}")
        let failedResult = failed.evaluate(input:.scalar(1),frame:.init(timing:.init(
            wallDate:Date(),simulationFrameTime:0.016,sceneTime:2)),scriptPropertiesJSON:"",
            userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        var failure = false
        if case .failure = failedResult { failure = true }
        let independent = try owner("export function update(v){thisScene.getLayer('layer3').getAnimation('fade').stop();return v;}")
        let third = try evaluate(independent,3).animationMutations
        let overflowing = try owner("export function update(v){let a=thisScene.getLayer('layer2').getAnimation('fade');for(let i=0;i<17;i++){try{a.play();}catch(e){}}return v;}")
        var overflowRejected = false
        do { _ = try evaluate(overflowing,3) }
        catch SceneScriptScalarRuntimeFailure.mutationOverflow { overflowRejected = true }
        let clickOwner = try owner("export function cursorClick(){thisScene.getLayer('layer2').getAnimation('fade').play();}")
        let clicked = try clickOwner.dispatchCursor(.init(kind:.click,layerID:1,
            worldPosition:.zero,localPosition:.zero),frame:.init(timing:.init(wallDate:Date(),
            simulationFrameTime:0.016,sceneTime:4)),scriptPropertiesJSON:"",userPropertiesJSON:"{}").get()
        let boolOwner = try SceneScriptValueOwner(domain:domain,source:"""
          export function cursorClick(){const a=thisScene.getLayer('layer2').getAnimation('fade');
            a.play();engine.setTimeout(()=>a.pause(),1500);}
          """,target:.layer(layerID:1,field:.visibility),valueType:.bool,effectNames:[],
          allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        let boolClick = try boolOwner.dispatchCursor(.init(kind:.click,layerID:1,
            worldPosition:.zero,localPosition:.zero),frame:.init(timing:.init(wallDate:Date(),
            simulationFrameTime:0.02,sceneTime:5)),scriptPropertiesJSON:"",userPropertiesJSON:"{}").get()
        var timerCommands:[SceneTimelinePlaybackMutation] = []
        for frameIndex in 1...100 {
            let result = try boolOwner.evaluate(input:.bool(true),frame:.init(timing:.init(
                wallDate:Date(),simulationFrameTime:0.02,sceneTime:5+Double(frameIndex)*0.02)),
                scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
            timerCommands += result.animationMutations
        }
        let out:[String:Any] = [
            "statefulBoolTimer":boolClick.animations == [.init(target:a,command:.play)]
                && timerCommands == [.init(target:a,command:.pause)],
            "overflowRejected":overflowRejected,
            "cursorTarget":clicked.animations == [.init(target:a,command:.play)],
            "firstTargets":first.map(\.target) == [a,b,current],
            "firstCommands":first.map(\.command) == [.play,.pause,.stop],
            "retainedTargets":second.map(\.target) == [a,b],
            "retainedCommands":second.map(\.command) == [.pause,.play],
            "rollback":failure,
            "peerContinues":third == [.init(target:b,command:.stop)]]
        print(String(data:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class NamedTimelineTests(unittest.TestCase):
    def test_named_commands_use_existing_typed_journal(self):
        with tempfile.TemporaryDirectory(prefix="mwx-named-timeline-") as temporary:
            binary = compile_vector_harness(Path(temporary), HARNESS, "named-timeline")
            run = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
            actual = json.loads(run.stdout.strip().splitlines()[-1])
            self.assertEqual(actual, dict.fromkeys([
                "firstTargets", "firstCommands", "retainedTargets", "retainedCommands",
                "rollback", "peerContinues", "cursorTarget", "overflowRejected", "statefulBoolTimer"], True))

if __name__ == "__main__":
    unittest.main()
