"""Dynamic solid travels through the VM journal and typed next-frame publication."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''

@main enum Harness {
 static let frame=SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
 static func make(_ source:String,effect:Bool=false, solid:Bool=true) throws -> (SceneScriptQuickJSProgramCandidate,SceneDynamicTarget) {
  let target:SceneDynamicTarget=effect ? .effectConstant(layerID:1,effectIndex:0,passIndex:0,name:"amount") : .layer(layerID:1,field:.alpha)
  let pass=SceneRenderDescriptor.EffectDescriptor.PassDescriptor(passIndex:0,id:20,constantShaderValues:["amount":.init(scriptSource:source,components:[0.5])])
  let d=SceneRenderDescriptor(layers:[.init(id:1,layerIndex:0,name:"subject",solid:solid,visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:0.5,
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

 static func descriptor(_ solid:Bool) -> SceneRenderDescriptor {
  .init(layers:[.init(id:1,layerIndex:0,name:"subject",solid:solid,visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:0.5,effects:[],contentKind:"image",sizeWH:[100,100])])
 }
 static func main() throws {
  var out:[String:Any]=[:]
  let solidTarget:SceneDynamicTarget = .layer(layerID:1,field:.solid)
  for initial in [true,false] {
   let key=initial ? "disable":"enable"
   let(c,t)=try make("export function update(v){let before=thisLayer.solid;thisLayer.solid=!before;if(thisLayer.solid===before)throw new Error('not staged');return before?.25:.75;}",solid:initial)
   let r=c.scalarProgram.evaluate(inputs:[t:.scalar(0.5)],frame:frame)
   out[key+"Failures"]=r.failures.count
   out[key+"Initial"]=r.values[t] == .scalar(initial ? 0.25:0.75)
   out[key+"Mutation"]=r.layerMutations.count == 1 && r.layerMutations[0].fields.contains(.solid) && r.layerMutations[0].solid == !initial
   let runtime=SceneScriptDynamicLayerRuntime(descriptor:descriptor(initial),authoredMutationLayerIDs:[1])
   try runtime.apply(r.layerMutations).get()
   let values=runtime.snapshot().authoredLayerValues
   out[key+"Typed"]=values[solidTarget] == .bool(!initial)
   out[key+"StableTopology"]=runtime.topologyRevision == 0
   commit(c)
   let snapshot=SceneDynamicSnapshotResolver().resolve(frameIndex:2,generation:1,definitions:runtime.authoredLayerDefinitions,sceneScriptValues:values).snapshot
   try c.domain!.publishLayerSnapshot(snapshot,descriptor:descriptor(initial))
   let next=c.scalarProgram.evaluate(inputs:[t:.scalar(0.5)],frame:frame)
   out[key+"NextFrame"]=next.values[t] == .scalar(initial ? 0.75:0.25)
   c.scalarProgram.finalizeLayerMutations(committing:false)
   let retry=c.scalarProgram.evaluate(inputs:[t:.scalar(0.5)],frame:frame)
   out[key+"Rollback"]=retry.values[t] == next.values[t] && retry.layerMutations.first?.solid == initial
   c.scalarProgram.finalizeLayerMutations(committing:false)
  }
  let(c,t)=try make("export function update(v){thisLayer.solid=false;thisLayer.visible=false;return v;}")
  let r=c.scalarProgram.evaluate(inputs:[t:.scalar(0.5)],frame:frame)
  out["otherFieldPreserved"]=r.layerMutations.count == 1 && r.layerMutations[0].fields.contains([.solid,.visibility]) && !r.layerMutations[0].solid && !r.layerMutations[0].visible
  let(b,bt)=try make("export function update(v){thisLayer.solid=false;throw new Error('reject');}")
  let rejected=b.scalarProgram.evaluate(inputs:[bt:.scalar(0.5)],frame:frame)
  out["exceptionIsolated"]=rejected.failures.count == 1 && rejected.layerMutations.isEmpty

  let(on,ot)=try make("export function update(v){thisLayer.solid=true;return v;}",solid:false)
  let enabled=on.scalarProgram.evaluate(inputs:[ot:.scalar(0.5)],frame:frame)
  let runtime=SceneScriptDynamicLayerRuntime(descriptor:descriptor(true),authoredMutationLayerIDs:[1])
  let peer:SceneDynamicTarget = .effectConstant(layerID:1,effectIndex:0,passIndex:0,name:"amount")
  let first=r.layerMutations[0].owned(by:t)
  let conflict=enabled.layerMutations[0].owned(by:peer)
  let plan=runtime.preflightIsolatingOwners([first,conflict])
  out["preflightUnpublished"]=runtime.snapshot().authoredLayerValues.isEmpty
  out["conflictIsolated"]=plan.outcome.failures.count == 1 && plan.outcome.failures[0].ownerTarget == peer
  runtime.commit(plan)
  out["acceptedOwnerPreserved"]=runtime.snapshot().authoredLayerValues[solidTarget] == .bool(false)
  let(d,dt)=try make("let layer;export function update(v){if(v===0){layer=thisScene.createLayer({text:'probe',solid:false});}else if(v===1){layer.solid=true;}return layer.solid?.75:.25;}")
  let created=d.scalarProgram.evaluate(inputs:[dt:.scalar(0)],frame:frame)
  out["dynamicCreatedFalse"]=created.layerMutations.first?.solid == false && created.values[dt] == .scalar(0.25)
  commit(d)
  let changed=d.scalarProgram.evaluate(inputs:[dt:.scalar(1)],frame:frame)
  out["dynamicStagedTrue"]=changed.layerMutations.first?.solid == true && changed.values[dt] == .scalar(0.75)
  d.scalarProgram.finalizeLayerMutations(committing:false)
  let restored=d.scalarProgram.evaluate(inputs:[dt:.scalar(2)],frame:frame)
  out["dynamicRollback"]=restored.values[dt] == .scalar(0.25)
  let(cap,ct)=try make("let n=0;export function cursorDown(e){thisLayer.solid=false;n=1;}export function cursorUp(e){n+=2;}export function cursorClick(e){n+=4;}export function update(v){return n/10;}")
  _=hit(cap);_=update(cap,ct);commit(cap)
  let down=hit(cap,true);_=update(cap,ct);commit(cap)
  out["captureClosed"]=down.layerMutations.first?.solid == false
  _=cap.cursorProgram.dispatch(batch:.init(samples:[.init(hits:[:],pointerPosition:.zero,primaryButtonIsDown:false)],overflowed:false),frame:frame,userPropertiesJSON:"{}")
  out["captureUpWithoutClick"]=update(cap,ct) == 0.3
  print(String(decoding:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),as:UTF8.self))
 }
}
'''

class DynamicSolidTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  with tempfile.TemporaryDirectory(prefix="mwx-solid-vm-") as temp:
   exe=compile_vector_harness(Path(temp),HARNESS,"solid")
   cls.value=json.loads(subprocess.run([str(exe)],check=True,capture_output=True,text=True).stdout)
 def test_both_directions_publish_and_read_back_next_frame(self):
  for direction in ("disable","enable"):
   self.assertEqual(self.value[direction+"Failures"],0)
   for stage in ("Initial","Mutation","Typed","StableTopology","NextFrame","Rollback"):
    with self.subTest(direction=direction,stage=stage):
     self.assertTrue(self.value[direction+stage])
 def test_other_boolean_field_and_exception(self):
  self.assertTrue(self.value["otherFieldPreserved"])
  self.assertTrue(self.value["exceptionIsolated"])

 def test_conflicts_dynamic_journal_and_capture_release(self):
  for key in ("preflightUnpublished","conflictIsolated","acceptedOwnerPreserved","dynamicCreatedFalse","dynamicStagedTrue","dynamicRollback","captureClosed","captureUpWithoutClick"):
   with self.subTest(key=key): self.assertTrue(self.value[key])
