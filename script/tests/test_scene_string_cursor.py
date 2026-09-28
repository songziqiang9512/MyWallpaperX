"""String callbacks share the initialized typed owner and its transaction."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS=r'''

@main enum Harness {
 static func make(_ source:String) throws -> SceneScriptQuickJSProgramCandidate {
  let d=SceneRenderDescriptor(layers:[.init(id:1,layerIndex:0,name:"label",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[],contentKind:"text",textScript:.init(source:source),text:"ready",textStyle:.init(fontPath:nil,colorRGB:[1,1,1],pointSize:32),sizeWH:[200,100])])
  let b=SceneScriptBindingIR(source:source,owner:.init(kind:.object,objectIndex:0,objectID:1,effectIndex:nil,effectID:nil,passIndex:nil,passID:nil),targetPath:[.key("objects"),.index(0),.key("text")],properties:[:],authoredValue:.string("ready"),valueType:.string,wrapperKeys:["script","value"])
  let c=try SceneScriptQuickJSProgramCandidate.compile(authoredDescriptor:d,runtimeDescriptor:d,scriptBindings:[b],vectorProjection:SceneScriptVectorProgram.project(descriptor:d,scriptBindings:[b]),userPropertyDefinitions:[],timelineTargets:[],scalarExcludedTargets:[],stringExcludedTargets:[],admittedVectorPassTargets:[],generation:1)
  return c
 }
 static let target:SceneDynamicTarget = .text(layerID:1,field:.content)
 static let frame=SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
 static func hit(_ c:SceneScriptQuickJSProgramCandidate) -> SceneScriptCursorFrameResult {
  c.cursorProgram.dispatch(batch:.init(samples:[.init(hits:[1:.init(layerID:1,worldPosition:.zero,localPosition:.zero)],pointerPosition:.zero,primaryButtonIsDown:false)],overflowed:false),frame:frame,userPropertiesJSON:"{}")
 }
 static func update(_ c:SceneScriptQuickJSProgramCandidate) -> SceneScriptStringFrameResult {
  c.stringProgram.evaluate(inputs:[target:.string("ready")],frame:frame)
 }
 static func commit(_ c:SceneScriptQuickJSProgramCandidate) {
  c.stringProgram.finalizeLayerMutations(committing:true);c.cursorProgram.finalizeLayerMutations(committing:true)
 }
 static func main() throws {
  var out:[String:Any]=[:]
  let c=try make("let n=0;export function init(v){n=10;return v+'!';}export function cursorEnter(e){n++;}export function update(v){return v+':'+n;}")
  let event=hit(c);let first=update(c)
  out["oneBorrowedOwner"]=c.cursorProgram.ownerCount==1 && c.cursorProgram.bindings.allSatisfy{!$0.ownsOwner}
  out["initializedBeforeEvent"]=event.failures.isEmpty && first.values[target] == .string("ready!:11")
  commit(c);_=hit(c);let second=update(c)
  out["singleInitialization"]=second.values[target] == .string("ready:11")
  let e=try make("export function cursorEnter(e){thisLayer.text='你好 🌍';}")
  let eventOnly=hit(e);out["eventOnlyText"]=eventOnly.layerMutations.first?.text == "你好 🌍"
  commit(e);out["eventOnlySleeps"]=update(e).values.isEmpty
  let retry=try make("export function init(v){thisLayer.origin=new Vec3(7,0,0);return v+'!';}export function cursorEnter(e){thisLayer.text='hover';}")
  let before=retry.stringProgram.frameStateSnapshot();let edges=retry.cursorProgram.edgeStateSnapshot();_=hit(retry);_=update(retry)
  retry.stringProgram.restoreFrameState(before,rejectedOwnerTargets:[target])
  retry.cursorProgram.restoreEdgeState(edges)
  retry.stringProgram.finalizeLayerMutations(committing:false);retry.cursorProgram.finalizeLayerMutations(committing:false)
  let repeated=hit(retry);let retried=update(retry)
  out["retryDetail"]="value=\(String(describing:retried.values[target])) text=\(String(describing:repeated.layerMutations.first?.text)) failures=\(repeated.failures) count=\(repeated.layerMutations.count)"
  out["rejectedInitializationRetries"]=repeated.failures.isEmpty && retried.values[target] == .string("ready!") && repeated.layerMutations.first?.text == "hover"
  let bad=try make("export function cursorEnter(e){throw new Error('bad event');}export function update(v){return v;}")
  out["callbackFailure"]=hit(bad).failures[target]?.code == "exception"
  let d=try SceneScriptQuickJSDomain()
  try d.configureLayerCatalog(.init(layers:[.init(id:1,layerIndex:0,name:"text",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],alpha:1,effects:[])]))
  let owner=try SceneScriptValueOwner(domain:d,source:"export function update(v){return v;}",target:target,valueType:.string,effectNames:[],generation:1,budget:.default)
  func evaluate(_ value:String,generation:UInt64=1)->Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure>{owner.evaluate(input:.string(value),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:generation,interruptBudget:nil)}
  out["unicode"]=try evaluate("你好 🌍").get().value == .string("你好 🌍")
  out["maximumUTF8"]=try evaluate(String(repeating:"a",count:65536)).get().value == .string(String(repeating:"a",count:65536))
  for (name,value) in [("nul","a\0b"),("oversize",String(repeating:"a",count:65537))] {
   if case .failure = evaluate(value){out[name]=true}else{out[name]=false}
  }
  if case .failure(.staleOwner)=evaluate("stale",generation:2){out["stale"]=true}else{out["stale"]=false}
  print(String(decoding:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),as:UTF8.self))
 }
}
'''

class StringCursorTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  with tempfile.TemporaryDirectory(prefix="mwx-string-cursor-vm-") as temp:
   exe=compile_vector_harness(Path(temp),HARNESS,"string-cursor")
   cls.value=json.loads(subprocess.run([str(exe)],check=True,capture_output=True,text=True).stdout)
   print(json.dumps(cls.value,sort_keys=True),flush=True)
 def test_shared_owner_and_initialized_event(self):
  for key in ("oneBorrowedOwner","initializedBeforeEvent","singleInitialization"):
   with self.subTest(key=key): self.assertTrue(self.value[key])
 def test_event_only_and_rejection(self):
  for key in ("eventOnlyText","eventOnlySleeps","rejectedInitializationRetries","callbackFailure"):
   with self.subTest(key=key): self.assertTrue(self.value[key])
 def test_utf8_limits_and_stale_generation(self):
  for key in ("unicode","maximumUTF8","nul","oversize","stale"):
   with self.subTest(key=key): self.assertTrue(self.value[key])
