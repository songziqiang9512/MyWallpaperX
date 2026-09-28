"""Local bone position API reuses the matrix journal without losing the basis."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static func main() throws {
        let domain=try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(.init(layers:[.init(id:42,layerIndex:0,name:"puppet",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])]))
        let source="""
            export function update(v){
                if(v.x===1){
                    const copy=thisLayer.getLocalBoneOrigin('root');copy.x=999;
                    if(thisLayer.getLocalBoneOrigin(0).x!==2)throw new Error('aliased getter');
                    thisLayer.setLocalBoneOrigin('root',new Vec3(5,6,7));
                    const pose=thisLayer.getLocalBoneTransform(0);
                    if(pose.m[0]!==2||pose.m[5]!==3||pose.m[10]!==1||pose.m[15]!==1)throw new Error('lost basis');
                    return thisLayer.getBoneTransform('tip').translation();
                }
                if(v.x===2){
                    const invalid=[()=>thisLayer.setLocalBoneOrigin(0,new Vec3(NaN,0,0)),
                        ()=>thisLayer.setLocalBoneOrigin(0,new Vec3(1e39,0,0)),
                        ()=>thisLayer.setLocalBoneOrigin('missing',new Vec3(0,0,0)),
                        ()=>thisLayer.setLocalBoneOrigin(0,{x:1,y:2}),
                        ()=>thisLayer.setLocalBoneOrigin(0),
                        ()=>thisLayer.getLocalBoneOrigin(0,1)];
                    let rejected=0;for(const call of invalid){try{call();}catch(e){rejected++;}}
                    return new Vec3(rejected,thisLayer.getLocalBoneOrigin(0).x,thisLayer.getBoneParentIndex('tip'));
                }
                if(v.x===3){thisLayer.setLocalBoneOrigin(0,new Vec3(8,9,10));throw new Error('abort');}
                if(v.x===4){for(let i=0;i<257;i++)thisLayer.setLocalBoneOrigin(0,new Vec3(i,0,0));}
                return thisLayer.getLocalBoneOrigin(0);
            }
            """
        let root:[Double]=[2,0,0,0,0,3,0,0,0,0,1,0,2,3,0,1]
        let tip:[Double]=[0,1,0,0,-1,0,0,0,0,0,1,0,3,2,0,1]
        let layer:[Double]=[1,0,0,0,0,1,0,0,0,0,1,0,10,0,0,1]
        func makeOwner() throws -> SceneScriptValueOwner {
            let owner=try SceneScriptValueOwner(domain:domain,source:source,target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
            try owner.configurePuppetBones(layerID:42,localMatrices:root+tip,names:["root","tip"],parents:[-1,0],layerToWorld:layer)
            return owner
        }
        var owner=try makeOwner()
        let frame=SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
        var output:[String:Any]=[:]
        func run(_ mode:Double,_ key:String,commit:Bool=true,generation:UInt64=1) {
            let result=owner.evaluate(input:.vector3(mode,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:generation,interruptBudget:nil)
            switch result {
            case let .success(e):
                if case let .vector3(x,y,z)=e.value{output[key]=[x,y,z]}
                output[key+"Writes"]=e.puppetBoneMutations.count
                output[key+"Matrices"]=e.puppetBoneMutations.map(\.matrix)
                if commit {owner.commitLayerMutations()}else{owner.discardLayerMutations()}
            case let .failure(e):output[key+"Failure"]=e.code;owner.discardLayerMutations()
            }
        }
        run(1,"candidate",commit:false);run(0,"rolledBack")
        run(2,"invalid");run(1,"committed");run(0,"nextFrame")
        run(0,"stale",generation:2)
        run(3,"throwing");run(0,"afterThrow")
        owner=try makeOwner()
        run(4,"overflow");run(0,"afterOverflow")
        print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]),as:UTF8.self))
    }
}
'''

class PuppetBoneOriginTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-bone-origin-vm-") as temp:
            exe=compile_vector_harness(Path(temp),HARNESS,"bone-origin")
            r=subprocess.run([str(exe)],capture_output=True,text=True,check=True)
            cls.value=json.loads(r.stdout)
            print(json.dumps(cls.value,sort_keys=True))

    def test_local_setter_preserves_basis_and_updates_descendant_world_pose(self):
        self.assertEqual(self.value.get('candidate'),[21,12,7])
        self.assertEqual(self.value.get('candidateWrites'),1)
        m=self.value['candidateMatrices'][0]
        self.assertEqual(m,[2,0,0,0,0,3,0,0,0,0,1,0,5,6,7,1])

    def test_copy_getter_commit_and_discard_share_matrix_transaction(self):
        self.assertEqual(self.value.get('rolledBack'),[2,3,0])
        self.assertEqual(self.value.get('nextFrame'),[5,6,7])
        self.assertEqual(self.value.get('invalid'),[6,2,0])
        self.assertEqual(self.value.get('invalidWrites'),0)

    def test_exception_and_budget_failure_stop_owner_without_publishing(self):
        self.assertEqual(self.value.get('throwingFailure'),'exception')
        self.assertEqual(self.value.get('afterThrowFailure'),'disabled')
        self.assertNotIn('throwingWrites',self.value)
        self.assertEqual(self.value.get('overflowFailure'),'exception')
        self.assertEqual(self.value.get('afterOverflowFailure'),'disabled')
        self.assertNotIn('overflowWrites',self.value)
        self.assertEqual(self.value.get('staleFailure'),'stale-owner')
