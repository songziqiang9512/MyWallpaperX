"""Execute the real prepared IAnimationLayer host and its owner transaction."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness
from .test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES as PUPPET_SOURCES

HARNESS = r'''
@main enum Harness {
    static let identity = ScenePuppetAnimationIdentity(layerID:42,animationLayerIndex:0,animationLayerID:91)
    static let target = ScenePuppetAnimationPropertyTarget.visibility(layerID:42,animationLayerID:91)
    static let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
    static func snapshot(_ current:Double=0,_ sequence:UInt64=0,_ failure:ScenePuppetAnimationEndedFailure?=nil) -> ScenePuppetAnimationSnapshot {
        .init(identity:identity,animationID:77,name:"Authored clip",framesPerSecond:30,frameCount:360,duration:12,
            currentFrame:current,isPlaying:true,rate:1,blend:1,visible:true,endedSequence:sequence,
            supportsEndedCallbacks:failure == nil,endedFailure:failure)
    }
    static func descriptor(_ layers:[ScenePuppetAnimationLayer]=[]) -> SceneRenderDescriptor {
        .init(layers:[.init(id:42,layerIndex:0,name:"parent",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],
            scaleHasScript:nil,alpha:1,effects:[],puppetAnimationLayers:layers)])
    }
    static func make(_ source:String) throws -> (SceneScriptQuickJSDomain,SceneScriptValueOwner) {
        let domain=try SceneScriptQuickJSDomain();let d=descriptor()
        try domain.configureLayerCatalog(d)
        try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,definitions:[]).snapshot,descriptor:d)
        let owner=try SceneScriptValueOwner(domain:domain,source:source,target:target,valueType:.bool,effectNames:[],
            puppetAnimationIdentity:identity,allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        try domain.publishPuppetAnimationSnapshot([snapshot()]);return(domain,owner)
    }
    static func evaluate(_ owner:SceneScriptValueOwner,_ value:Bool=true) -> Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure> {
        owner.evaluate(input:.bool(value),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
    }
    static func actions(_ commands:[ScenePuppetAnimationCommand]) -> [String] {
        commands.map { c in switch c.action {
            case .play: "play"
            case .pause: "pause"
            case .stop: "stop"
            case let .setFrame(v): "frame:\(v)"
            case let .setRate(v): "rate:\(v)"
            case let .setBlend(v): "blend:\(v)"
            case let .setVisible(v): "visible:\(v)"
        }}
    }
    static func main() throws {
        var out:[String:Any]=[:]
        // Real nested parser + candidate projection, including authored properties.
        let source="""
        export var scriptProperties=createScriptProperties().addSlider({name:'percentage',value:1,min:0,max:1,integer:false}).finish();
        export function init(v) {
            const a=('addEndedCallback' in thisObject)?thisObject:thisObject.getAnimation();
            if(a.name!=='Authored clip'||a.fps!==30||a.duration!==12)throw new Error('metadata');
            a.play();a.setFrame(a.frameCount*scriptProperties.percentage);
            return a.isPlaying() && Math.abs(a.getFrame()-334.8)<.001;
        }
        """
        let raw:[String:Any]=["objects":[["id":42,"animationlayers":[["id":91,"animation":77,
            "visible":["value":true,"script":source,"scriptproperties":["percentage":0.93]]]]]]]
        let parsed=SceneScriptBindingIRParser.parse(document:raw)
        let authored=ScenePuppetAnimationLayer.parse((raw["objects"] as! [[String:Any]])[0]["animationlayers"])
        let d=descriptor(authored);let domain=try SceneScriptQuickJSDomain();try domain.configureLayerCatalog(d)
        let projection=SceneScriptVectorProgram.project(descriptor:d,scriptBindings:parsed.bindings,timelineTargets:[],admittedLayerColorConsumerIDs:[])
        let program=SceneScriptVectorProgram.compileNonPass(domain:domain,descriptor:d,projection:projection,userPropertyDefinitions:[],generation:1)
        try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,definitions:[]).snapshot,descriptor:d)
        try domain.publishPuppetAnimationSnapshot([snapshot()])
        let result=program.evaluate(inputs:[target:.bool(true)],effectivePropertyValues:[:],frame:frame)
        out["parserCandidates"]=projection.uniqueCandidates.count
        out["parserFailures"]=result.failures.count
        out["parserActions"]=actions(result.ownerEffects.flatMap(\.puppetAnimationCommands))
        out["parserValue"]=result.values[target] == .bool(true)
        out["parentWrites"]=result.layerMutations.count
        program.finalizeLayerMutations(committing:true)

        // Module-owned persistent handle; ended callbacks run before update.
        let (persistentDomain,persistent)=try make("""
        let a;
        export function init(v){a=thisObject;a.addEndedCallback(()=>{if(thisLayer.name!=="parent"||thisLayer.getBoneCount()!==1||thisLayer.getLocalBoneOrigin(0).x!==0)throw new Error("bound layer");a.stop();});return v;}
        export function update(v){return a.isPlaying() && a.getFrame()>0;}
        """)
        try persistent.configurePuppetBones(layerID:42,
            localMatrices:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],names:["root"],parents:[-1])
        _=try evaluate(persistent).get();persistent.commitLayerMutations()
        try persistentDomain.publishPuppetAnimationSnapshot([snapshot(1.25,1)])
        let ended=try evaluate(persistent).get()
        out["endedActions"]=actions(ended.puppetAnimationCommands);out["endedBeforeUpdate"]=ended.value == .bool(false)
        persistent.commitLayerMutations()
        out["endedOnce"]=actions(try evaluate(persistent).get().puppetAnimationCommands)
        persistent.commitLayerMutations()

        // Host rejection restores roots and controls but consumes natural-end input.
        let (rollbackDomain,rollback)=try make("""
        let a;export function init(v){a=thisObject;a.addEndedCallback(()=>a.pause());return v;}
        export function update(v){if(!a.isPlaying())a.addEndedCallback(()=>a.setFrame(23));return v;}
        """)
        _=try evaluate(rollback).get();rollback.commitLayerMutations()
        try rollbackDomain.publishPuppetAnimationSnapshot([snapshot(2,1)])
        let saved=rollback.timerFrameSnapshot()
        out["rollbackFirst"]=actions(try evaluate(rollback).get().puppetAnimationCommands)
        rollback.discardLayerMutations();rollback.restoreTimerFrame(saved)
        out["rollbackRetry"]=actions(try evaluate(rollback).get().puppetAnimationCommands)
        rollback.commitLayerMutations();rollback.discardTimerFrame(saved)
        try rollbackDomain.publishPuppetAnimationSnapshot([snapshot(3,2)])
        out["rollbackNextEnd"]=actions(try evaluate(rollback).get().puppetAnimationCommands)
        rollback.commitLayerMutations()

        // The same rejection boundary through the real program owner bundle.
        let programSource="""
        let a;export function init(v){a=thisObject;a.addEndedCallback(()=>a.pause());return v;}
        export function update(v){if(!a.isPlaying())a.addEndedCallback(()=>a.setFrame(23));return v;}
        """
        let (programDomain,_)=try make("export function update(v){return v;}")
        let c=SceneScriptVectorCandidate(authoredOrdinal:0,source:programSource,
            definition:.init(target:target,valueType:.bool,authoredValue:.bool(true)),properties:[:],livePropertyInputTargets:[],
            hasCurrentAnimation:false,dynamicImageReferences:[],requiresStatefulOwner:true,evaluatesAfterSharedProviders:false,
            dynamicMaterialModelPath:nil,puppetAnimationIdentity:identity)
        let rejectedProgram=SceneScriptVectorProgram.compileNonPass(domain:programDomain,descriptor:descriptor(),
            projection:.init(candidates:[c]),userPropertyDefinitions:[],generation:1)
        try programDomain.publishPuppetAnimationSnapshot([snapshot()])
        let rootOnly=rejectedProgram.evaluate(inputs:[target:.bool(true)],effectivePropertyValues:[:],frame:frame)
        out["rootOnlyBundles"]=rootOnly.ownerEffects.count
        out["rootOnlyCommands"]=rootOnly.ownerEffects.flatMap(\.puppetAnimationCommands).count
        out["rootOnlyRegistrations"]=rootOnly.ownerEffects.reduce(0){$0+$1.puppetAnimationCallbackRegistrations}
        rejectedProgram.finalizeLayerMutations(committing:true)
        try programDomain.publishPuppetAnimationSnapshot([snapshot(2,1)])
        let programSaved=rejectedProgram.timerFrameStateSnapshot()
        let rejectedFrame=rejectedProgram.evaluate(inputs:[target:.bool(true)],effectivePropertyValues:[:],frame:frame)
        out["programRejectedActions"]=actions(rejectedFrame.ownerEffects.flatMap(\.puppetAnimationCommands))
        out["programRootRegistrations"]=rejectedFrame.ownerEffects.reduce(0){$0+$1.puppetAnimationCallbackRegistrations}
        rejectedProgram.restoreTimerFrameState(programSaved)
        rejectedProgram.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target])
        let retryFrame=rejectedProgram.evaluate(inputs:[target:.bool(true)],effectivePropertyValues:[:],frame:frame)
        out["programRetryActions"]=actions(retryFrame.ownerEffects.flatMap(\.puppetAnimationCommands))
        rejectedProgram.finalizeLayerMutations(committing:true)
        rejectedProgram.discardTimerFrameState(programSaved)
        try programDomain.publishPuppetAnimationSnapshot([snapshot(3,2)])
        let nextEnd=rejectedProgram.evaluate(inputs:[target:.bool(true)],effectivePropertyValues:[:],frame:frame)
        out["programNextEndActions"]=actions(nextEnd.ownerEffects.flatMap(\.puppetAnimationCommands))
        rejectedProgram.finalizeLayerMutations(committing:true)

        // Setter visibility and returned nested Bool share one publication.
        let (_,visibility)=try make("""
        export function init(v){thisObject.rate=2;thisObject.blend=.25;return v;}
        export function update(v){thisObject.visible=false;return true;}
        """)
        let vis=try evaluate(visibility).get();out["visibleValue"]=vis.value == .bool(false)
        out["visibleActions"]=actions(vis.puppetAnimationCommands);out["visibleParentWrites"]=vis.layerMutations.count
        visibility.commitLayerMutations()

        // Finite raw seek is observable immediately, including unclamped bounds.
        let (_,bounds)=try make("""
        export function update(v){thisObject.pause();thisObject.setFrame(-1.5);if(thisObject.getFrame()!==-1.5)throw new Error('raw');
          thisObject.setFrame(720.5);return !thisObject.isPlaying()&&thisObject.getFrame()===720.5;}
        """)
        let bounded=try evaluate(bounds).get();out["boundsValue"]=bounded.value == .bool(true);out["boundsActions"]=actions(bounded.puppetAnimationCommands)
        bounds.commitLayerMutations()

        let (_,throwing)=try make("export function init(v){thisObject.addEndedCallback(()=>thisObject.stop());thisObject.play();throw new Error('failed');}")
        if case let .failure(failure)=evaluate(throwing){out["throwFailure"]=failure.code}
        out["throwCommands"]=mwx_scene_quickjs_owner_puppet_animation_command_count(throwing.handle)
        let (failedEndDomain,failedEnd)=try make("""
        let a;export function init(v){a=thisObject;a.addEndedCallback(()=>{a.pause();throw new Error('ended failed');});return v;}
        export function update(v){return v;}
        """)
        _=try evaluate(failedEnd).get();failedEnd.commitLayerMutations()
        try failedEndDomain.publishPuppetAnimationSnapshot([snapshot(2,1)])
        if case let .failure(failure)=evaluate(failedEnd){out["endedThrowFailure"]=failure.code}
        out["endedThrowCommands"]=mwx_scene_quickjs_owner_puppet_animation_command_count(failedEnd.handle)
        out["endedThrowPending"]=mwx_scene_quickjs_owner_has_pending_puppet_animation_end(failedEnd.handle)

        var held:(SceneScriptQuickJSDomain,SceneScriptValueOwner)?=try make("export function init(v){shared.savedAnimation=thisObject;return v;}")
        let staleDomain=held!.0
        _=try evaluate(held!.1).get();held!.1.commitLayerMutations();held=nil
        let wrongOwner=try SceneScriptValueOwner(domain:staleDomain,source:"export function update(v){shared.savedAnimation.play();return v;}",
            target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
        let staleResult=wrongOwner.evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        if case let .failure(failure)=staleResult{out["staleHandleFailure"]=failure.code}

        let (_,overflow)=try make("export function update(v){for(let i=0;i<65;i++){try{thisObject.play();}catch(e){}}return v;}")
        if case let .failure(failure)=evaluate(overflow){out["overflowFailure"]=failure.code}
        out["overflowCommands"]=mwx_scene_quickjs_owner_puppet_animation_command_count(overflow.handle)
        let (_,roots)=try make("export function init(v){for(let i=0;i<17;i++)thisObject.addEndedCallback(()=>thisObject.pause());return v;}")
        if case let .failure(failure)=evaluate(roots){out["rootBudgetFailure"]=failure.code}

        // C admits finite Float writes; the actual shared runtime rejects a
        // negative rate atomically and the owner mirror rolls back with it.
        let authoredLayer=ScenePuppetAnimationLayer(id:91,animationID:77,name:"Authored clip",additive:false,
            blend:1,blendIn:false,blendOut:false,blendTime:0,rate:1,visible:true,visibilityBinding:nil)
        let clip=SceneMdlPuppetAnimation(id:77,name:"Authored clip",mode:"loop",framesPerSecond:30,frameCount:360,
            transformsByBone:[(0...360).map{_ in .init(translation:.zero,rotation:.zero,scale:SIMD3(repeating:1))}],alphaByBone:nil)
        let runtime=ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID:42,selection:.init(clips:[.init(layer:authoredLayer,animation:clip)],composition:.singleAbsolute),
            authoredLayers:[authoredLayer]).get()
        _=runtime.advance(frameIndex:1,sceneTime:0,dynamicValues:SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,definitions:[]).snapshot)
        let (rejectDomain,rejectOwner)=try make("""
        let n=0;export function update(v){n++;const a=thisObject;if(n===1){a.rate=-1;a.setFrame(10);}
            else if(a.rate!==1||a.getFrame()!==0)throw new Error('rejected mirror leaked');return v;}
        """)
        try rejectDomain.publishPuppetAnimationSnapshot(runtime.snapshots())
        let nativeBefore=runtime.snapshots()
        let invalidCommands=try evaluate(rejectOwner).get().puppetAnimationCommands
        out["swiftRejectNativeActions"]=actions(invalidCommands)
        if case .failure=runtime.validate(invalidCommands,frameIndex:1){out["swiftRejectInvalid"]=true}
        out["swiftRejectUnchanged"]=runtime.snapshots() == nativeBefore
        rejectOwner.discardLayerMutations()
        out["swiftRejectMirrorRetry"]=actions(try evaluate(rejectOwner).get().puppetAnimationCommands)
        rejectOwner.commitLayerMutations()

        let (missingDomain,missing)=try make("export function update(v){return thisObject.isPlaying();}")
        try missingDomain.publishPuppetAnimationSnapshot([])
        if case let .failure(failure)=evaluate(missing){out["missingFailure"]=failure.code}
        // Existing ordinary owners remain executable when one prepared clip is absent.
        let peer=try SceneScriptValueOwner(domain:missingDomain,source:"export function update(v){return v.add(new Vec3(1,0,0));}",
            target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
        let peerResult=try peer.evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
        out["missingPeer"]=peerResult.value == .vector3(1,0,0);peer.commitLayerMutations()

        try persistentDomain.publishPuppetAnimationSnapshot([snapshot(5,2,.multipleLoopsCrossed)])
        if case let .failure(failure)=evaluate(persistent){out["endedUnsupported"]=failure.code}
        out["endedUnsupportedPending"]=mwx_scene_quickjs_owner_has_pending_puppet_animation_end(persistent.handle)
        if case let .failure(failure)=evaluate(persistent){out["endedUnsupportedRetry"]=failure.code}
        let (_,teardown)=try make("export function init(v){thisObject.addEndedCallback(()=>thisObject.stop());return v;}")
        _=try evaluate(teardown).get();teardown.commitLayerMutations()
        let torn=teardown.teardown(frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}")
        out["teardownQuiescent"]=torn.snapshot.isQuiescent
        out["teardownPendingEnd"]=mwx_scene_quickjs_owner_has_pending_puppet_animation_end(teardown.handle)
        print(String(data:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class PuppetAnimationHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="mwx-puppet-animation-host-")
        cls.binary = compile_vector_harness(Path(cls.tmp.name), HARNESS, "puppet-animation",
            extra_swift_sources=tuple([*PUPPET_SOURCES,
                SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift"]))
        run = subprocess.run([str(cls.binary)], capture_output=True, text=True)
        if run.returncode:
            cls.tmp.cleanup()
            raise AssertionError(run.stdout + run.stderr)
        cls.values = json.loads(run.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_nested_author_init_receives_metadata_and_seek_commands(self):
        v=self.values
        self.assertEqual(v["parserCandidates"],1)
        self.assertEqual(v["parserFailures"],0)
        self.assertEqual(v["parserActions"],["play","frame:334.8"])
        self.assertTrue(v["parserValue"])
        self.assertEqual(v["parentWrites"],0)

    def test_persistent_handle_and_ended_callback_precedes_update(self):
        self.assertEqual(self.values["endedActions"],["stop"])
        self.assertTrue(self.values["endedBeforeUpdate"])
        self.assertEqual(self.values["endedOnce"],[])

    def test_host_rejection_restores_roots_without_replaying_consumed_end(self):
        self.assertEqual(self.values["rollbackFirst"],["pause"])
        self.assertEqual(self.values["rollbackRetry"],[])
        self.assertEqual(self.values["rollbackNextEnd"],["pause"])
        self.assertEqual(self.values["programRejectedActions"],["pause"])
        self.assertEqual(self.values["programRootRegistrations"],1)
        self.assertEqual(self.values["rootOnlyBundles"],1)
        self.assertEqual(self.values["rootOnlyCommands"],0)
        self.assertEqual(self.values["rootOnlyRegistrations"],1)
        self.assertEqual(self.values["programRetryActions"],[])
        self.assertEqual(self.values["programNextEndActions"],["pause"])

    def test_visibility_setter_publishes_nested_bool(self):
        self.assertTrue(self.values["visibleValue"])
        self.assertEqual(self.values["visibleActions"],["rate:2.0","blend:0.25","visible:false"])
        self.assertEqual(self.values["visibleParentWrites"],0)

    def test_raw_seek_and_failure_budgets(self):
        self.assertTrue(self.values["boundsValue"])
        self.assertEqual(self.values["boundsActions"],["pause","frame:-1.5","frame:720.5"])
        self.assertEqual(self.values["throwFailure"],"exception")
        self.assertEqual(self.values["throwCommands"],0)
        self.assertEqual(self.values["overflowFailure"],"mutation-overflow")
        self.assertEqual(self.values["overflowCommands"],0)
        self.assertEqual(self.values["rootBudgetFailure"],"exception")
        self.assertEqual(self.values["endedThrowFailure"],"exception")
        self.assertEqual(self.values["endedThrowCommands"],0)
        self.assertFalse(self.values["endedThrowPending"])
        self.assertEqual(self.values["staleHandleFailure"],"exception")

    def test_actual_shared_runtime_rejects_controls_atomically(self):
        self.assertEqual(self.values["swiftRejectNativeActions"],["rate:-1.0","frame:10.0"])
        self.assertTrue(self.values["swiftRejectInvalid"])
        self.assertTrue(self.values["swiftRejectUnchanged"])
        self.assertEqual(self.values["swiftRejectMirrorRetry"],[])

    def test_missing_metadata_is_local_and_ended_profile_is_honest(self):
        self.assertEqual(self.values["missingFailure"],"exception")
        self.assertTrue(self.values["missingPeer"])
        self.assertEqual(self.values["endedUnsupported"],"disabled")
        self.assertFalse(self.values["endedUnsupportedPending"])
        self.assertEqual(self.values["endedUnsupportedRetry"],"disabled")
        self.assertTrue(self.values["teardownQuiescent"])
        self.assertFalse(self.values["teardownPendingEnd"])
