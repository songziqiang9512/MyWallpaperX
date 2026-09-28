"""Scalar callbacks borrow the value owner, preserve initialization and retry."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS=r'''
@main enum Harness {
 static let frame=SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
 static func make(_ source:String,effect:Bool=false) throws -> (SceneScriptQuickJSProgramCandidate,SceneDynamicTarget) {
  let target:SceneDynamicTarget=effect ? .effectConstant(layerID:1,effectIndex:0,passIndex:0,name:"amount") : .layer(layerID:1,field:.alpha)
  let pass=SceneRenderDescriptor.EffectDescriptor.PassDescriptor(passIndex:0,id:20,constantShaderValues:["amount":.init(scriptSource:source,components:[0.5])])
  let d=SceneRenderDescriptor(layers:[.init(id:1,layerIndex:0,name:"subject",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:0.5,
     effects:effect ? [.init(name:"effect",effectID:10,passes:[pass])] : [],contentKind:"image",sizeWH:[100,100])])
  let b=SceneScriptBindingIR(source:source,owner:.init(kind:effect ? .pass : .object,objectIndex:0,objectID:1,effectIndex:effect ? 0:nil,effectID:effect ? 10:nil,passIndex:effect ? 0:nil,passID:effect ? 20:nil),
    targetPath:effect ? [.key("objects"),.index(0),.key("effects"),.index(0),.key("passes"),.index(0),.key("constantshadervalues"),.key("amount")] : [.key("objects"),.index(0),.key("alpha")],
    properties:[:],authoredValue:.number(0.5),valueType:.number,wrapperKeys:["script","value"])
  return(try SceneScriptQuickJSProgramCandidate.compile(authoredDescriptor:d,runtimeDescriptor:d,scriptBindings:[b],
    vectorProjection:SceneScriptVectorProgram.project(descriptor:d,scriptBindings:[b]),userPropertyDefinitions:[],timelineTargets:[],scalarExcludedTargets:[],stringExcludedTargets:[],admittedVectorPassTargets:[],generation:1),target)
 }
 static func hit(_ c:SceneScriptQuickJSProgramCandidate,_ down:Bool=false) -> SceneScriptCursorFrameResult {
  c.cursorProgram.dispatch(batch:.init(samples:[.init(hits:[1:.init(layerID:1,worldPosition:.zero,localPosition:.zero)],pointerPosition:.zero,primaryButtonIsDown:down)],overflowed:false),frame:frame,userPropertiesJSON:"{}")
 }
 static func update(_ c:SceneScriptQuickJSProgramCandidate,_ t:SceneDynamicTarget) -> Double {
  let r=c.scalarProgram.evaluate(inputs:[t:.scalar(0.5)],frame:frame)
  guard case let .scalar(x)?=r.values[t] else{return -999};return x
 }
 static func commit(_ c:SceneScriptQuickJSProgramCandidate) {
  c.scalarProgram.finalizeLayerMutations(committing:true);c.cursorProgram.finalizeLayerMutations(committing:true)
 }
 static func main() throws {
  var out:[String:Any]=[:]
  let (c,t)=try make("""
    let count=0;export function init(v){count=10;return .25;}
    export function cursorEnter(e){count+=1;}
    export function update(v){return v+count/100;}
    """)
  let h=hit(c);out["cursorOwners"]=c.cursorProgram.ownerCount;out["borrowed"]=c.cursorProgram.bindings.allSatisfy{!$0.ownsOwner};out["failures"]=h.failures.count
  out["first"]=update(c,t);commit(c);_=hit(c);out["idle"]=update(c,t);commit(c)
  let (e,et)=try make("export function cursorEnter(e){thisObject.amount=.75;}",effect:true)
  _=hit(e);out["effectFirst"]=update(e,et);commit(e);_=hit(e);out["effectIdle"]=update(e,et);commit(e)
  let (r,rt)=try make("let n=0;export function cursorDown(e){n+=1;}export function update(v){return n/10;}")
  _=hit(r);_=update(r,rt);commit(r)
  let snap=r.scalarProgram.frameStateSnapshot();_=hit(r,true);out["rejectedCandidate"]=update(r,rt)
  r.scalarProgram.restoreFrameState(snap,rejectedOwnerTargets:[rt]);r.scalarProgram.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[rt]);r.cursorProgram.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[rt])
  _=hit(r,true);out["retry"]=update(r,rt);commit(r);_=hit(r,true);out["retryIdle"]=update(r,rt);commit(r)
  let (m,_)=try make("export function cursorEnter(e){thisLayer.getEffect(0).executeMaterialFunction('reset');}",effect:true)
  let material=hit(m);out["materialNames"]=material.ownerEffects.flatMap(\.materialFunctionMutations).map(\.functionName)
  out["materialFailures"]=material.failures.count;commit(m)
  out["materialIdle"]=hit(m).ownerEffects.flatMap(\.materialFunctionMutations).count
  let (bad,bt)=try make("export function cursorEnter(e){throw new Error('bad');}export function update(v){return v;}")
  out["callbackFailure"]=hit(bad).failures[bt]?.code ?? "none"
  print(String(decoding:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),as:UTF8.self))
 }
}
'''
class ScalarCursorTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  with tempfile.TemporaryDirectory(prefix='mwx-scalar-cursor-vm-') as temp:
   exe=compile_vector_harness(Path(temp),HARNESS,'scalar-cursor')
   cls.value=json.loads(subprocess.run([str(exe)],check=True,capture_output=True,text=True).stdout)
 def test_cursor_and_update_share_initialized_owner(self):
  self.assertEqual(self.value['cursorOwners'],1)
  self.assertTrue(self.value['borrowed']);self.assertEqual(self.value['failures'],0)
  self.assertAlmostEqual(self.value['first'],.36);self.assertAlmostEqual(self.value['idle'],.61)
 def test_event_only_effect_parameter_publishes_then_sleeps(self):
  self.assertEqual(self.value['effectFirst'],.75);self.assertEqual(self.value['effectIdle'],-999)
 def test_rejected_event_retries_once_then_stays_quiet(self):
  self.assertEqual(self.value['rejectedCandidate'],.1);self.assertEqual(self.value['retry'],.2);self.assertEqual(self.value['retryIdle'],.2)
 def test_cursor_exception_remains_local_failure(self):
  self.assertEqual(self.value['callbackFailure'],'exception')

 def test_callback_material_commands_publish_once_through_owner_effects(self):
  self.assertEqual(self.value['materialNames'],['reset'])
  self.assertEqual(self.value['materialFailures'],0)
  self.assertEqual(self.value['materialIdle'],0)
