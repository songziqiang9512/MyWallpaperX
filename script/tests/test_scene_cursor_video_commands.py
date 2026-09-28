"""Cursor video commands keep authored order and owner-scoped rollback."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r''' 
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
    static func target(_ field: SceneDynamicLayerField = .origin) -> SceneDynamicTarget { .layer(layerID:1,field:field) }
    static func make(_ sources: [(SceneDynamicLayerField,String)]) throws -> SceneScriptCursorProgram {
        let d = try SceneScriptQuickJSDomain()
        let descriptor = SceneRenderDescriptor(layers:[.init(id:1,layerIndex:0,name:"video",visible:true,
            originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:false,alpha:1,effects:[])])
        try d.configureLayerCatalog(descriptor)
        try d.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,definitions:[]).snapshot,
            descriptor:descriptor,videoSnapshots:[1:.init(layerID:1,duration:10,rate:1,loop:true,currentTime:0,isPlaying:true,endedGeneration:0)])
        var bindings:[SceneScriptCursorBinding] = []
        for (i,item) in sources.enumerated() {
            let o = try SceneScriptVectorOwner(domain:d,source:item.1,target:target(item.0),effectNames:[],
                allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
            bindings.append(.init(layerID:1,authoredOrdinal:i,owner:o,events:o.exportedCursorEvents,
                ownsOwner:true,scriptProperties:[:],ownerSeedValue:.vector3(0,0,0)))
        }
        return .init(bindings:bindings,generation:1)
    }
    static func sample(_ down:Bool, hit:Bool = true) -> SceneScriptCursorFrameSample {
        .init(hits:hit ? [1:.init(layerID:1,worldPosition:.zero,localPosition:.zero)] : [:],
            pointerPosition:.zero,primaryButtonIsDown:down)
    }
    static func dispatch(_ p:SceneScriptCursorProgram,_ s:[SceneScriptCursorFrameSample]) -> SceneScriptCursorFrameResult {
        p.dispatch(batch:.init(samples:s,overflowed:false),frame:frame,userPropertiesJSON:"{}")
    }
    static func commands(_ r:SceneScriptCursorFrameResult,_ field:SceneDynamicLayerField = .origin) -> [String] {
        r.ownerEffects.filter{$0.ownerTarget==target(field)}.flatMap{$0.videoCommands}.map { c in
            switch c.action {
            case .play:return "play"
            case .pause:return "pause"
            case .stop:return "stop"
            case let .setCurrentTime(v):return "seek:\(v)"
            case let .setRate(v):return "rate:\(v)"
            case let .setLoop(v):return "loop:\(v)"
            }
        }
    }
    static func main() throws {
        var out:[String:Any] = [:]
        let source = """
        export function init(v){thisLayer.getVideoTexture().loop=false;return v;}
        export function cursorEnter(e){thisLayer.getVideoTexture().pause();}
        export function cursorDown(e){let v=thisLayer.getVideoTexture();v.setCurrentTime(3);v.rate=2;}
        export function cursorClick(e){thisLayer.getVideoTexture().play();}
        export function cursorUp(e){thisLayer.getVideoTexture().stop();}
        """
        let p=try make([(.origin,source)])
        let first=dispatch(p,[sample(false),sample(true),sample(false)])
        out["ordered"]=commands(first);out["failures"]=first.failures.count
        out["layers"]=first.ownerEffects.flatMap{$0.videoCommands}.map{$0.layerID}
        p.finalizeLayerMutations(committing:true)
        out["idle"]=commands(dispatch(p,[sample(false)]));p.finalizeLayerMutations(committing:true)

        let q=try make([(.origin,"export function cursorDown(e){thisLayer.getVideoTexture().pause();}"),
            (.scale,"export function cursorDown(e){thisLayer.getVideoTexture().play();}")])
        out["first"]=commands(dispatch(q,[sample(false),sample(true)]))
        q.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        let retry=dispatch(q,[sample(true)]);out["retry"]=commands(retry);out["peerRetry"]=commands(retry,.scale)
        q.finalizeLayerMutations(committing:true)
        out["retryIdle"]=commands(dispatch(q,[sample(true)]));q.finalizeLayerMutations(committing:true)

        let bad=try make([(.origin,"export function cursorDown(e){thisLayer.getVideoTexture().pause();throw new Error('fail');}"),
            (.scale,"export function cursorDown(e){thisLayer.getVideoTexture().play();}")])
        let failed=dispatch(bad,[sample(false),sample(true)])
        out["badFailure"]=failed.failures[target()]?.code ?? "none";out["badCommands"]=commands(failed);out["peer"]=commands(failed,.scale)
        bad.finalizeLayerMutations(committing:true,rejectedOwnerTargets:Set(failed.failures.keys))

        let whole=try make([(.origin,"export function cursorDown(e){thisLayer.getVideoTexture().setCurrentTime(4);}")])
        let edge=whole.edgeStateSnapshot();out["discardCandidate"]=commands(dispatch(whole,[sample(false),sample(true)]))
        whole.finalizeLayerMutations(committing:false);whole.restoreEdgeState(edge)
        out["discardRetry"]=commands(dispatch(whole,[sample(false),sample(true)]));whole.finalizeLayerMutations(committing:true)
        print(String(decoding:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),as:UTF8.self))
    }
}
'''

class SceneCursorVideoCommandsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-cursor-video-vm-") as temp:
            binary=compile_vector_harness(Path(temp),HARNESS,"cursor-video")
            run=subprocess.run([str(binary)],check=True,capture_output=True,text=True)
            cls.value=json.loads(run.stdout)

    def test_init_and_cursor_preserve_video_command_order(self):
        self.assertEqual(self.value["failures"],0)
        self.assertEqual(self.value["ordered"],["loop:false","pause","seek:3.0","rate:2.0","stop","play"])
        self.assertEqual(self.value["layers"],[1]*6)
        self.assertEqual(self.value["idle"],[])

    def test_rejected_target_retries_without_replaying_peer(self):
        self.assertEqual(self.value["first"],["pause"])
        self.assertEqual(self.value["retry"],["pause"])
        self.assertEqual(self.value["peerRetry"],[])
        self.assertEqual(self.value["retryIdle"],[])

    def test_callback_failure_discards_only_its_video_commands(self):
        self.assertEqual(self.value["badFailure"],"exception")
        self.assertEqual(self.value["badCommands"],[])
        self.assertEqual(self.value["peer"],["play"])

    def test_discarded_frame_replays_seek_once(self):
        self.assertEqual(self.value["discardCandidate"],["seek:4.0"])
        self.assertEqual(self.value["discardRetry"],["seek:4.0"])
