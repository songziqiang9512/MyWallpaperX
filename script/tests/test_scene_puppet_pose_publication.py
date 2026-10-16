"""Query-local and physical render poses share one atomic Puppet journal."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static func matrix(_ x: Double) -> [Double] { [1,0,0,0,0,1,0,0,0,0,1,0,x,0,0,1] }
    static func pairChecks(layerID: Int, root: String, tip: String, neighbor: String,
                           offset: Double, scale: Double) throws -> [String: Any] {
        let domain=try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(.init(layers:[.init(id:layerID,layerIndex:0,name:"pair-\(layerID)",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])]))
        let source="""
            export function update(input){
                const subject=thisLayer;
                if(input.x===1){
                    const local=subject.getLocalBoneTransform('\(root)');
                    local.m[12]=4;subject.setLocalBoneTransform(0,local);
                }
                if(input.x===2){
                    const world=subject.getBoneTransform('\(tip)');
                    world.m[12]=100;subject.setBoneTransform(1,world);
                }
                if(input.x===3){
                    subject.setLocalBoneOrigin('\(root)',new Vec3(99,0,0));
                    subject.setLocalBoneOrigin('\(neighbor)',new Vec3(88,0,0));
                    throw new Error('abort candidate pair');
                }
                if(input.y===1)return new Vec3(subject.getLocalBoneOrigin('\(tip)').x,
                    subject.getLocalBoneOrigin(2).x,subject.getBoneTransform('\(root)').translation().x);
                return new Vec3(subject.getLocalBoneTransform('\(root)').translation().x,
                    subject.getBoneTransform('\(tip)').translation().x,
                    subject.getBoneTransform('\(neighbor)').translation().x);
            }
            """
        var placement=matrix(offset);placement[0]=scale
        let query=matrix(2)+matrix(3)+matrix(5)
        let rendered=matrix(20)+matrix(30)+matrix(50)
        func makeOwner() throws -> SceneScriptValueOwner {
            let owner=try SceneScriptValueOwner(domain:domain,source:source,
                target:.layer(layerID:layerID,field:.origin),effectNames:[],generation:1,budget:.default)
            try owner.configurePuppetBones(layerID:layerID,localMatrices:query,
                renderLocalMatrices:rendered,names:[root,tip,neighbor],parents:[-1,0,0],
                layerToWorld:placement)
            return owner
        }
        let frame=SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
        func evaluate(_ owner:SceneScriptValueOwner,_ mode:Double=0,_ view:Double=0) throws -> [String:Any] {
            let result=try owner.evaluate(input:.vector3(mode,view,0),frame:frame,
                scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,
                interruptBudget:nil).get()
            let values:[Double]
            if case let .vector3(x,y,z)=result.value { values=[x,y,z] } else { values=[] }
            return ["pose":values,"matrices":result.puppetBoneMutations.map(\.matrix),
                    "indices":result.puppetBoneMutations.map(\.boneIndex)]
        }
        var output:[String:Any]=[:]
        let owner=try makeOwner()
        output["initial"]=try evaluate(owner);owner.commitLayerMutations()
        output["localCandidate"]=try evaluate(owner,1);owner.discardLayerMutations()
        output["afterDiscard"]=try evaluate(owner);owner.commitLayerMutations()
        output["localCommitted"]=try evaluate(owner,1);owner.commitLayerMutations()
        output["afterCommit"]=try evaluate(owner);owner.commitLayerMutations()
        output["unwrittenLocal"]=try evaluate(owner,0,1);owner.commitLayerMutations()
        let worldOwner=try makeOwner()
        output["worldCandidate"]=try evaluate(worldOwner,2)
        output["worldLocal"]=try evaluate(worldOwner,0,1)
        worldOwner.discardLayerMutations()
        output["worldDiscarded"]=try evaluate(worldOwner);worldOwner.commitLayerMutations()
        for scenario in ["renderCount","renderNaN","renderOverflow","renderProductOverflow","queryNaN"] {
            let refreshed=try makeOwner()
            var nextQuery=matrix(4)+matrix(6)+matrix(8),nextRender=matrix(40)+matrix(60)+matrix(80)
            var nextPlacement=placement
            switch scenario {
            case "renderCount": nextRender.removeLast()
            case "renderNaN": nextRender[12] = .nan
            case "renderOverflow": nextRender[12]=Double(Float.greatestFiniteMagnitude)*2
            case "renderProductOverflow": nextRender[12]=Double(Float.greatestFiniteMagnitude);nextPlacement[0]=2
            default: nextQuery[12] = .nan
            }
            var rejected=false
            do { try refreshed.configurePuppetBones(layerID:layerID,localMatrices:nextQuery,
                renderLocalMatrices:nextRender,parents:[-1,0,0],layerToWorld:nextPlacement) }
            catch { rejected=true }
            output[scenario]=["rejected":rejected,"read":try evaluate(refreshed)]
            refreshed.commitLayerMutations()
        }
        let throwing=try makeOwner()
        switch throwing.evaluate(input:.vector3(3,0,0),frame:frame,scriptPropertiesJSON:"",
            userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil) {
        case .success: output["throwFailure"]="unexpected success"
        case let .failure(failure): output["throwFailure"]=failure.code
        }
        throwing.discardLayerMutations()
        output["throwPublishedWrites"]=mwx_scene_quickjs_owner_puppet_bone_mutation_count(throwing.handle)
        let peer=try makeOwner()
        output["healthyPeer"]=try evaluate(peer);peer.commitLayerMutations()
        return output
    }
    static func main() throws {
        var output:[String:Any]=[:]
        for scenario in ["parentCount","cyclicParent","nonfinitePlacement","floatOverflow","productOverflow","valid"] {
            let domain=try SceneScriptQuickJSDomain()
            try domain.configureLayerCatalog(.init(layers:[.init(id:42,layerIndex:0,name:"puppet",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])]))
            let owner=try SceneScriptValueOwner(domain:domain,source:"export function update(v){return new Vec3(thisLayer.getLocalBoneTransform('root').translation().x,thisLayer.getBoneTransform('tip').translation().x,thisLayer.getBoneParentIndex('tip'));}",target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
            try owner.configurePuppetBones(layerID:42,localMatrices:matrix(2)+matrix(3),names:["root","tip"],parents:[-1,0],layerToWorld:matrix(10))
            var local=matrix(4)+matrix(6),parents:[Int32]=[-1,0],placement=matrix(20)
            switch scenario {
            case "parentCount": parents=[-1]
            case "cyclicParent": parents=[-1,1]
            case "nonfinitePlacement": placement[0] = .nan
            case "floatOverflow": local[12] = Double(Float.greatestFiniteMagnitude)*2
            case "productOverflow": local[12] = Double(Float.greatestFiniteMagnitude);placement[0] = 2
            default: break
            }
            var rejected=false
            do { try owner.configurePuppetBones(layerID:42,localMatrices:local,parents:parents,layerToWorld:placement) }
            catch { rejected=true }
            let frame=SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
            let result=try owner.evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
            let values:[Double];if case let .vector3(x,y,z)=result.value{values=[x,y,z]}else{values=[]}
            output[scenario]=["rejected":rejected,"pose":values]
            owner.commitLayerMutations()
        }
        output["dual"]=try pairChecks(layerID:42,root:"root",tip:"tip",neighbor:"neighbor",offset:10,scale:2)
        output["renamed"]=try pairChecks(layerID:87,root:"trunk",tip:"leaf",neighbor:"branch",offset:-7,scale:0.5)
        print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]),as:UTF8.self))
    }
}
'''

class PuppetPosePublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-pose-vm-") as temp:
            binary=compile_vector_harness(Path(temp),HARNESS,"pose-publication")
            run=subprocess.run([str(binary)],capture_output=True,text=True,check=True)
            cls.result=json.loads(run.stdout)
            print(json.dumps(cls.result,sort_keys=True))

    def test_invalid_refresh_keeps_pose_hierarchy_and_names(self):
        for name in ("parentCount","cyclicParent","nonfinitePlacement","floatOverflow","productOverflow"):
            with self.subTest(name=name):
                self.assertTrue(self.result[name]["rejected"])
                self.assertEqual(self.result[name]["pose"],[2,15,0])

    def test_valid_refresh_publishes_local_and_world_pose_together(self):
        self.assertEqual(self.result["valid"],{"rejected":False,"pose":[4,30,0]})

    def test_query_local_and_render_world_remain_distinct_through_setters(self):
        for name, offset, scale in (("dual", 10, 2), ("renamed", -7, 0.5)):
            with self.subTest(variant=name):
                facts = self.result[name]
                initial = [2, offset + scale * 50, offset + scale * 70]
                written = [4, offset + scale * 34, offset + scale * 54]
                self.assertEqual(facts["initial"]["pose"], initial)
                self.assertEqual(facts["localCandidate"]["pose"], written)
                self.assertEqual(facts["localCandidate"]["indices"], [0])
                self.assertEqual(facts["localCandidate"]["matrices"][0][12], 4)
                self.assertEqual(facts["afterCommit"]["pose"], written)
                self.assertEqual(facts["unwrittenLocal"]["pose"], [3, 5, offset + scale * 4])
                self.assertEqual(facts["worldCandidate"]["pose"], [2, 100, initial[2]])
                local_x = (100 - offset) / scale - 20
                self.assertEqual(facts["worldCandidate"]["indices"], [1])
                self.assertEqual(facts["worldCandidate"]["matrices"][0][12], local_x)
                self.assertEqual(facts["worldLocal"]["pose"], [local_x, 5, offset + scale * 20])

    def test_discard_and_rejected_refresh_preserve_complete_query_render_pair(self):
        for name in ("dual", "renamed"):
            facts = self.result[name]
            initial = facts["initial"]["pose"]
            with self.subTest(variant=name):
                self.assertEqual(facts["afterDiscard"]["pose"], initial)
                self.assertEqual(facts["worldDiscarded"]["pose"], initial)
                for reason in ("renderCount", "renderNaN", "renderOverflow", "renderProductOverflow", "queryNaN"):
                    with self.subTest(reason=reason):
                        self.assertTrue(facts[reason]["rejected"])
                        self.assertEqual(facts[reason]["read"]["pose"], initial)
                        self.assertEqual(facts[reason]["read"]["indices"], [])
                self.assertEqual(facts["throwFailure"], "exception")
                self.assertEqual(facts["throwPublishedWrites"], 0)
                self.assertEqual(facts["healthyPeer"]["pose"], initial)
