"""A rejected host pose refresh must preserve the previous complete rig."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static func matrix(_ x: Double) -> [Double] { [1,0,0,0,0,1,0,0,0,0,1,0,x,0,0,1] }
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
