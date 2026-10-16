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
    static let sibling = ScenePuppetAnimationIdentity(layerID:42,animationLayerIndex:1,animationLayerID:208)
    static let foreign = ScenePuppetAnimationIdentity(layerID:43,animationLayerIndex:0,animationLayerID:91)
    static func prepared(_ id:ScenePuppetAnimationIdentity,_ name:String,_ current:Double,_ playing:Bool=true,
                         _ sequence:UInt64=0,fps:Double=30) -> ScenePuppetAnimationSnapshot {
        .init(identity:id,animationID:id == sibling ? 78 : 77,name:name,framesPerSecond:fps,frameCount:360,
            duration:12,currentFrame:current,isPlaying:playing,rate:1,blend:1,visible:true,
            endedSequence:sequence,supportsEndedCallbacks:true,endedFailure:nil)
    }
    static func mirrors(_ name:String="Side arc") -> [ScenePuppetAnimationSnapshot] {
        [prepared(identity,"Authored clip",3),prepared(sibling,name,29,false),prepared(foreign,"Foreign clip",55)]
    }
    static func lookupOwner(_ source:String,_ states:[ScenePuppetAnimationSnapshot]?=nil)
        throws -> (SceneScriptQuickJSDomain,SceneScriptValueOwner) {
        let domain=try SceneScriptQuickJSDomain()
        let d=SceneRenderDescriptor(layers:descriptor().layers + [
            .init(id:43,layerIndex:1,name:"foreign",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],
                scaleHasScript:nil,alpha:1,effects:[])])
        try domain.configureLayerCatalog(d)
        try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
            definitions:[]).snapshot,descriptor:d)
        let owner=try SceneScriptValueOwner(domain:domain,source:source,target:target,valueType:.bool,effectNames:[],
            puppetAnimationIdentity:identity,allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        try domain.publishPuppetAnimationSnapshot(states ?? mirrors());return(domain,owner)
    }
    static func at(_ owner:SceneScriptValueOwner,_ time:Double,_ generation:UInt64=1,delta:Double=0.016)
        -> Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure> {
        owner.evaluate(input:.bool(true),frame:.init(timing:.init(wallDate:Date(timeIntervalSince1970:0),
            simulationFrameTime:delta,sceneTime:time)),scriptPropertiesJSON:"",userPropertiesJSON:"{}",
            expectedGeneration:generation,interruptBudget:nil)
    }
    static func failed(_ result:Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure>) -> Bool {
        if case .failure=result { return true };return false
    }
    enum RecoveryFixtureFailure: Error {
        case phase(damage:String,stage:String,underlying:Error)
    }
    static func phase(_ name:String) {
        FileHandle.standardError.write(Data(("fixture-phase="+name+"\n").utf8))
    }
    static func nativeLookupRuntime(_ duplicateSource:Bool=false,siblingName:String="Side arc") throws -> ScenePuppetAnimationPlaybackRuntime {
        let first=ScenePuppetAnimationLayer(id:91,animationID:77,name:"Authored clip",additive:false,
            blend:1,blendIn:false,blendOut:false,blendTime:0,rate:1,visible:true,visibilityBinding:nil)
        let second=ScenePuppetAnimationLayer(id:duplicateSource ? 91 : 208,animationID:78,name:siblingName,additive:true,
            blend:1,blendIn:false,blendOut:false,blendTime:0,rate:1,visible:true,visibilityBinding:nil)
        func clip(_ id:Int) -> SceneMdlPuppetAnimation {
            .init(id:id,name:"clip-\(id)",mode:"loop",framesPerSecond:30,frameCount:360,
                transformsByBone:[(0...360).map{_ in .init(translation:.zero,rotation:.zero,
                    scale:SIMD3(repeating:1))}],alphaByBone:nil)
        }
        let runtime=ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID:42,selection:.init(clips:[.init(layer:first,animation:clip(77)),
            .init(layer:second,animation:clip(78))],composition:.layered),authoredLayers:[first,second]).get()
        try runtime.register(layerID:43,selection:.init(clips:[.init(layer:first,animation:clip(77))],
            composition:.singleAbsolute),authoredLayers:[first]).get()
        _=runtime.advance(frameIndex:1,sceneTime:0,dynamicValues:SceneDynamicSnapshotResolver()
            .resolve(frameIndex:1,generation:1,definitions:[]).snapshot)
        if !duplicateSource {
            let seed:[ScenePuppetAnimationCommand]=[
                .init(identity:identity,action:.setFrame(3),callbackEpoch:0,ordinal:0),
                .init(identity:sibling,action:.setFrame(29),callbackEpoch:0,ordinal:1),
                .init(identity:sibling,action:.pause,callbackEpoch:0,ordinal:2)]
            try runtime.apply(seed,frameIndex:1).get()
        }
        return runtime
    }
    static func lookupChecks() throws -> [String:Any] {
        var out:[String:Any]=[:];var variants:[Bool]=[]
        // Name resolves a real sibling, index resolves authored order rather than editor ID.
        for (name,variable,index) in [("Side arc","branch","1"),("Renamed sweep","track","Number(3)-2"),
                                     ("clip-rebound","motion","Math.floor(1.75)")] {
            phase("lookup/name-index-variant/\(name)")
            let native=try nativeLookupRuntime(siblingName:name)
            let source="""
            let cached;let visits=0;
            export function update(v){visits++;const own=thisLayer.getAnimationLayer(0);
              const \(variable)=thisLayer.getAnimationLayer('\(name)');
              if(thisLayer.id!==42||own.name!=='Authored clip'||own.getFrame()!==3)throw new Error('self identity');
              if(visits===1){cached=thisLayer.getAnimationLayer(\(index));
                if(\(variable).getFrame()!==29||\(variable).isPlaying()||cached.name!=='\(name)')throw new Error('sibling identity');
                cached.stop();if(cached.getFrame()!==0||cached.isPlaying())throw new Error('stop reset');
                cached.play();cached.setFrame(16/2);own.pause();
                return cached.getFrame()===8&&cached.isPlaying()&&!own.isPlaying();}
              return cached.getFrame()===8&&cached.isPlaying()&&!own.isPlaying();}
            """
            let (domain,owner)=try lookupOwner(source,native.snapshots())
            let first=try evaluate(owner).get();let commands=first.puppetAnimationCommands
            try native.validate(commands,sourceLayerID:42,sourceAnimationLayerID:91,frameIndex:1).get()
            try native.apply(commands,frameIndex:1).get();owner.commitLayerMutations()
            let committed=native.snapshots()
            try domain.publishPuppetAnimationSnapshot(committed)
            let next=try evaluate(owner).get();owner.commitLayerMutations()
            variants.append(first.value == .bool(true) && next.value == .bool(true)
                && actions(commands) == ["stop","play","frame:8.0","pause"]
                && commands.map(\.identity) == [sibling,sibling,sibling,identity]
                && committed.first{$0.identity == sibling}?.currentFrame == 8
                && committed.first{$0.identity == identity}?.currentFrame == 3
                && next.puppetAnimationCommands.isEmpty)
        }
        out["lookupVariants"]=variants

        // Three real primitive entries share pending state, but each ABI read
        // exports only its new commands until native acceptance/publication.
        phase("lookup/initialize-properties-update")
        let sequenceNative=try nativeLookupRuntime()
        let (sequenceDomain,sequenceOwner)=try lookupOwner("""
        let a;let updates=0;
        export function init(v){a=thisLayer.getAnimationLayer(1);a.stop();a.setFrame(7);return v;}
        export function applyUserProperties(e){if(a.getFrame()!==7||a.isPlaying())throw new Error('init journal lost');
          a.play();a.setFrame(11);}
        export function update(v){if(a.getFrame()!==11)throw new Error('property journal lost');
          if(updates++===0){if(!a.isPlaying())throw new Error('play journal lost');a.pause();}
          else if(a.isPlaying())throw new Error('native publication lost');return true;}
        """,sequenceNative.snapshots())
        let initialized=try sequenceOwner.initializeIfNeeded(input:.bool(true),frame:frame,scriptPropertiesJSON:"",
            userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()!
        let propertyChange=try sequenceOwner.dispatchUserProperties(changedPropertiesJSON:"{\"enabled\":true}",
            scriptPropertiesJSON:"",frame:frame,userPropertiesJSON:"{\"enabled\":true}").get()
        let updated=try evaluate(sequenceOwner).get()
        out["lookupPrimitiveRanges"]=[actions(initialized.puppetAnimationCommands),
            actions(propertyChange.puppetAnimationCommands),actions(updated.puppetAnimationCommands)]
        let sequenceCommands=initialized.puppetAnimationCommands+propertyChange.puppetAnimationCommands+updated.puppetAnimationCommands
        try sequenceNative.validate(sequenceCommands,sourceLayerID:42,sourceAnimationLayerID:91,frameIndex:1).get()
        try sequenceNative.apply(sequenceCommands,frameIndex:1).get();sequenceOwner.commitLayerMutations()
        let sequenceCommitted=sequenceNative.snapshots()
        out["lookupPrimitiveNative"]=sequenceCommands.allSatisfy{$0.identity == sibling}
            && sequenceCommitted.first{$0.identity == sibling}?.currentFrame == 11
            && sequenceCommitted.first{$0.identity == sibling}?.isPlaying == false
            && sequenceCommitted.first{$0.identity == identity}?.currentFrame == 3
        try sequenceDomain.publishPuppetAnimationSnapshot(sequenceCommitted)
        let afterCommit=try evaluate(sequenceOwner).get()
        out["lookupPrimitiveAfterCommit"]=afterCommit.value == .bool(true) && afterCommit.puppetAnimationCommands.isEmpty
        sequenceOwner.commitLayerMutations()

        phase("lookup/invalid-inputs")
        let (_,invalid)=try lookupOwner("""
        export function update(v){let rejected=0;
          for(const key of ['absent',-1,1.5,Infinity,NaN,91]){
            try{thisLayer.getAnimationLayer(key);}catch(e){if(e instanceof RangeError)rejected++;}}
          for(const key of [null,true,{},[]]){
            try{thisLayer.getAnimationLayer(key);}catch(e){if(e instanceof TypeError)rejected++;}}
          try{thisLayer.getAnimationLayer();}catch(e){if(e instanceof TypeError)rejected++;}
          try{thisScene.getLayer('foreign').getAnimationLayer(0);}catch(e){if(e instanceof TypeError)rejected++;}
          return rejected===12;}
        """)
        out["lookupBadInputs"]=try evaluate(invalid).get().value == .bool(true);invalid.commitLayerMutations()
        phase("lookup/duplicate-name")
        let (_,duplicate)=try lookupOwner("""
        export function update(v){let rejected=false;try{thisLayer.getAnimationLayer('Authored clip');}
          catch(e){rejected=e instanceof RangeError;}thisLayer.getAnimationLayer(1).pause();return rejected;}
        """,[prepared(identity,"Authored clip",3),prepared(sibling,"Authored clip",29,false)])
        let duplicateResult=try evaluate(duplicate).get();out["lookupDuplicateName"]=duplicateResult.value == .bool(true)
            && duplicateResult.puppetAnimationCommands.map(\.identity) == [sibling];duplicate.commitLayerMutations()

        // Other owners never observe or borrow this owner's uncommitted handle/journal.
        phase("lookup/cross-owner-writer")
        let (sharedDomain,writer)=try lookupOwner("""
        export function update(v){shared.borrowed=thisLayer.getAnimationLayer(1);shared.borrowed.setFrame(17);
          return shared.borrowed.getFrame()===17;}
        """)
        out["lookupLocalRead"]=try evaluate(writer).get().value == .bool(true)
        let observer=try SceneScriptValueOwner(domain:sharedDomain,source:"""
        export function update(v){let rejected=false;try{shared.borrowed.play();}catch(e){rejected=e instanceof TypeError;}
          return rejected&&thisObject.getFrame()===29&&!thisObject.isPlaying();}
        """,target:ScenePuppetAnimationPropertyTarget.visibility(layerID:42,animationLayerID:208),valueType:.bool,
            effectNames:[],puppetAnimationIdentity:sibling,allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        phase("lookup/cross-owner-observer-bootstrap")
        let pendingWriterCommands=mwx_scene_quickjs_owner_puppet_animation_command_count(writer.handle)
        try sharedDomain.publishPuppetAnimationSnapshot(mirrors())
        let observed=try evaluate(observer).get();out["lookupOwnerIsolation"]=observed.value == .bool(true)
            && observed.puppetAnimationCommands.isEmpty
            && mwx_scene_quickjs_owner_puppet_animation_command_count(writer.handle) == pendingWriterCommands
        observer.commitLayerMutations();writer.discardLayerMutations()
        phase("lookup/non-nested-owner")
        let ordinary=try SceneScriptValueOwner(domain:sharedDomain,source:"""
        export function update(v){try{thisLayer.getAnimationLayer(0);}catch(e){if(e instanceof TypeError)return v;}throw new Error('unprepared owner');}
        """,target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
        out["lookupNonNested"]=try ordinary.evaluate(input:.vector3(1,2,3),frame:frame,scriptPropertiesJSON:"",
            userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get().value == .vector3(1,2,3)
        ordinary.commitLayerMutations()

        phase("lookup/target-lifetime-cache")
        let (lifetimeDomain,lifetime)=try lookupOwner("""
        let cached;export function update(v){if(!cached){cached=thisLayer.getAnimationLayer(1);return true;}
          try{cached.play();}catch(e){if(e instanceof TypeError)return true;throw e;}return false;}
        """)
        _=try evaluate(lifetime).get();lifetime.commitLayerMutations()
        phase("lookup/target-missing")
        try lifetimeDomain.publishPuppetAnimationSnapshot([prepared(identity,"Authored clip",3)])
        let missingHandle=try evaluate(lifetime).get();lifetime.commitLayerMutations()
        phase("lookup/target-reappeared-old-cache")
        try lifetimeDomain.publishPuppetAnimationSnapshot(mirrors())
        let reappearedHandle=try evaluate(lifetime).get();lifetime.commitLayerMutations()
        out["lookupRetiredHandle"]=[missingHandle.value == .bool(true) && missingHandle.puppetAnimationCommands.isEmpty,
            reappearedHandle.value == .bool(true) && reappearedHandle.puppetAnimationCommands.isEmpty]
        let fresh=try SceneScriptValueOwner(domain:lifetimeDomain,source:"export function update(v){thisLayer.getAnimationLayer(1).pause();return v;}",
            target:target,valueType:.bool,effectNames:[],puppetAnimationIdentity:identity,
            allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        phase("lookup/target-reappeared-fresh-owner-bootstrap")
        try lifetimeDomain.publishPuppetAnimationSnapshot(mirrors())
        out["lookupFreshAfterReappear"]=try evaluate(fresh).get().puppetAnimationCommands.map(\.identity) == [sibling]
        fresh.commitLayerMutations();out["lookupGenerationRejected"]=failed(at(fresh,1,2))
        phase("lookup/destroyed-owner-cache")
        var retired:(SceneScriptQuickJSDomain,SceneScriptValueOwner)?=try lookupOwner(
            "export function update(v){shared.retiredSibling=thisLayer.getAnimationLayer(1);return v;}")
        let retiredDomain=retired!.0;_=try evaluate(retired!.1).get();retired!.1.commitLayerMutations();retired=nil
        let successor=try SceneScriptValueOwner(domain:retiredDomain,source:"""
        export function update(v){try{shared.retiredSibling.play();}catch(e){return e instanceof TypeError;}
          return false;}
        """,target:target,valueType:.bool,effectNames:[],puppetAnimationIdentity:identity,
            allowsStatefulLayerSideEffects:true,generation:2,budget:.default)
        phase("lookup/destroyed-owner-successor-bootstrap")
        try retiredDomain.publishPuppetAnimationSnapshot(mirrors())
        out["lookupDestroyedOwner"]=try at(successor,1,2).get().value == .bool(true)
        successor.commitLayerMutations()

        // Present-but-invalid records recover their old incarnation. A real
        // absence remains distinct (lookupRetiredHandle above).
        var metadataRecovery:[Bool]=[]
        for damage in ["finite","fps","duplicate"] {
            phase("lookup/metadata-recovery/\(damage)")
            var recoveryStage="setup"
            do {
                let (recoveryDomain,recoveryOwner)=try lookupOwner("""
                let own,peer;export function update(v){if(!own){own=thisLayer.getAnimationLayer(0);
                  peer=thisLayer.getAnimationLayer(1);}return own.getFrame()===engine.runtime
                    &&peer.getFrame()===engine.runtime+26&&!peer.isPlaying();}
                """)
                let healthyIdentity = damage == "fps" ? identity : sibling
                let healthyFrame = damage == "fps" ? 3 : 29
                let healthy=try SceneScriptValueOwner(domain:recoveryDomain,
                    source:"export function update(v){return thisObject.getFrame()===\(healthyFrame);}",
                    target:ScenePuppetAnimationPropertyTarget.visibility(layerID:42,
                        animationLayerID:healthyIdentity.animationLayerID!),valueType:.bool,effectNames:[],
                    puppetAnimationIdentity:healthyIdentity,allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
                recoveryStage="cache-initial-handles"
                try recoveryDomain.publishPuppetAnimationSnapshot(mirrors())
                _=try at(recoveryOwner,3).get();recoveryOwner.commitLayerMutations()
                var damaged=mirrors()
                if damage == "finite" { damaged[0]=prepared(identity,"Authored clip",.nan) }
                else if damage == "fps" { damaged[1]=prepared(sibling,"Side arc",29,false,fps:60) }
                else { damaged.insert(damaged[0],at:1) }
                recoveryStage="publish-invalid-and-run-healthy-owner"
                try recoveryDomain.publishPuppetAnimationSnapshot(damaged)
                // Do not execute the damaged owner: an uncaught exception has
                // its own permanent fuse and is not a publisher recovery test.
                let healthyResult=try at(healthy,4).get();healthy.commitLayerMutations()
                recoveryStage="restore-and-read-cached-handles"
                try recoveryDomain.publishPuppetAnimationSnapshot([
                    prepared(identity,"Authored clip",6),prepared(sibling,"Side arc",32,false),mirrors()[2]])
                let restored=try at(recoveryOwner,6).get();recoveryOwner.commitLayerMutations()
                recoveryStage="stable-layout-current-values"
                try recoveryDomain.publishPuppetAnimationSnapshot([
                    prepared(identity,"Authored clip",9),prepared(sibling,"Side arc",35,false),mirrors()[2]])
                let refreshed=try at(recoveryOwner,9).get();recoveryOwner.commitLayerMutations()
                metadataRecovery.append(healthyResult.value == .bool(true)
                    && healthyResult.puppetAnimationCommands.isEmpty && restored.value == .bool(true)
                    && refreshed.value == .bool(true) && refreshed.puppetAnimationCommands.isEmpty)
            } catch {
                throw RecoveryFixtureFailure.phase(damage:damage,stage:recoveryStage,underlying:error)
            }
        }
        out["lookupMetadataRecovery"]=metadataRecovery

        var forbidden:[Bool]=[]
        for (caseIndex,operation) in ["a.visible=false","a.addEndedCallback(()=>{})","throw new Error('rollback')"].enumerated() {
            phase("lookup/rejected-bundle/\(caseIndex)")
            let (_,owner)=try lookupOwner("export function update(v){const a=thisLayer.getAnimationLayer(1);a.stop();\(operation);return v;}")
            forbidden.append(failed(evaluate(owner)) && mwx_scene_quickjs_owner_puppet_animation_command_count(owner.handle)==0)
        }
        out["lookupRejectedBundles"]=forbidden
        phase("lookup/shared-command-budget")
        let (_,overflow)=try lookupOwner("""
        export function update(v){const a=thisLayer.getAnimationLayer(1);for(let i=0;i<65;i++){
          try{(i%2?a:thisObject).play();}catch(e){}}return v;}
        """)
        if case let .failure(f)=evaluate(overflow){out["lookupBudgetFailure"]=f.code}
        out["lookupBudgetCommands"]=mwx_scene_quickjs_owner_puppet_animation_command_count(overflow.handle)

        // Cached self lookup retains existing Bool arbitration and natural-ended ownership.
        phase("lookup/self-ended-and-visible-setup")
        let (selfDomain,selfOwner)=try lookupOwner("""
        let own;export function init(v){own=thisLayer.getAnimationLayer(0);
          own.addEndedCallback(()=>{own.pause();own.visible=false;});return v;}
        export function update(v){return true;}
        """)
        _=try evaluate(selfOwner).get();selfOwner.commitLayerMutations()
        phase("lookup/self-ended-and-visible-delivery")
        try selfDomain.publishPuppetAnimationSnapshot([prepared(identity,"Authored clip",3,true,1),mirrors()[1]])
        let ended=try evaluate(selfOwner).get();out["lookupSelfEnded"]=ended.value == .bool(false)
            && actions(ended.puppetAnimationCommands) == ["pause","visible:false"]
            && ended.puppetAnimationCommands.allSatisfy{$0.identity == identity};selfOwner.commitLayerMutations()
        let endedNative=try nativeLookupRuntime()
        try endedNative.validate(ended.puppetAnimationCommands,sourceLayerID:42,sourceAnimationLayerID:91,frameIndex:1).get()
        try endedNative.apply(ended.puppetAnimationCommands,frameIndex:1).get()

        phase("lookup/timer-rollback-setup")
        let (_,timer)=try lookupOwner("""
        let a;export function init(v){a=thisLayer.getAnimationLayer(1);engine.setTimeout(()=>{
          a.stop();a.setFrame(14);thisObject.visible=false;},500);return v;}
        export function update(v){return true;}
        """)
        _=try at(timer,1).get();timer.commitLayerMutations();let saved=timer.timerFrameSnapshot()
        phase("lookup/timer-fire-and-restore")
        let firstTimer=try at(timer,1.5,delta:0.5).get();timer.discardLayerMutations();timer.restoreTimerFrame(saved)
        let retryTimer=try at(timer,1.5,delta:0.5).get();out["lookupTimerRollback"]=firstTimer.value == .bool(false)
            && retryTimer.value == .bool(false) && actions(firstTimer.puppetAnimationCommands) == ["stop","frame:14.0","visible:false"]
            && actions(retryTimer.puppetAnimationCommands) == actions(firstTimer.puppetAnimationCommands)
            && firstTimer.puppetAnimationCommands.map(\.identity) == [sibling,sibling,identity]
        out["lookupTimerDetails"]=["firstValue":String(describing:firstTimer.value),
            "retryValue":String(describing:retryTimer.value),
            "firstActions":actions(firstTimer.puppetAnimationCommands),
            "retryActions":actions(retryTimer.puppetAnimationCommands),
            "firstIdentities":firstTimer.puppetAnimationCommands.map{[$0.identity.layerID,
                $0.identity.animationLayerIndex,$0.identity.animationLayerID ?? -1]},
            "retryIdentities":retryTimer.puppetAnimationCommands.map{[$0.identity.layerID,
                $0.identity.animationLayerIndex,$0.identity.animationLayerID ?? -1]}] as [String:Any]
        timer.commitLayerMutations();timer.discardTimerFrame(saved)

        phase("lookup/swift-runtime-rejection")
        let native=try nativeLookupRuntime();let (rejectDomain,reject)=try lookupOwner("""
        let n=0;export function update(v){n++;const a=thisLayer.getAnimationLayer(1);
          if(n===1){a.rate=-1;a.setFrame(10);}return n===1||(a.rate===1&&a.getFrame()===29&&!a.isPlaying());}
        """)
        try rejectDomain.publishPuppetAnimationSnapshot(native.snapshots());let before=native.snapshots()
        let rejected=try evaluate(reject).get().puppetAnimationCommands
        let rejectedAdmission=native.validate(rejected,sourceLayerID:42,sourceAnimationLayerID:91,frameIndex:1)
        out["lookupSwiftReject"] = !registration(rejectedAdmission) && native.snapshots() == before
        reject.discardLayerMutations();out["lookupSwiftRetry"]=try evaluate(reject).get().value == .bool(true)
        reject.commitLayerMutations()
        phase("lookup/source-target-admission")
        let visibleSibling=ScenePuppetAnimationCommand(identity:sibling,action:.setVisible(false),callbackEpoch:1,ordinal:0)
        let foreignTarget=ScenePuppetAnimationCommand(identity:foreign,action:.pause,callbackEpoch:1,ordinal:0)
        let duplicateNative=try nativeLookupRuntime(true)
        out["lookupRuntimeAdmission"]=[
            !registration(native.validate([],sourceLayerID:42,sourceAnimationLayerID:999,frameIndex:1)),
            registration(native.validate([visibleSibling],frameIndex:1))
                && !registration(native.validate([visibleSibling],sourceLayerID:42,sourceAnimationLayerID:91,frameIndex:1)),
            registration(native.validate([foreignTarget],frameIndex:1))
                && !registration(native.validate([foreignTarget],sourceLayerID:42,sourceAnimationLayerID:91,frameIndex:1)),
            !registration(duplicateNative.validate([],sourceLayerID:42,sourceAnimationLayerID:91,frameIndex:1)),
            native.snapshots() == before]
        return out
    }
    static func registration(_ result:Result<Void,ScenePuppetAnimationPlaybackRuntime.Failure>) -> Bool {
        if case .success=result{return true};return false
    }

    static func occurrence(_ id:ScenePuppetAnimationIdentity,_ sequence:UInt64,_ name:String,_ frame:Int=3)
        -> ScenePuppetAnimationEventOccurrence {
        .init(identity:id,sequence:sequence,name:name,frame:frame)
    }
    static func eventChecks() throws -> [String:Any] {
        var out:[String:Any]=[:]
        phase("events/order-and-parent")
        let native=try nativeLookupRuntime()
        let (domain,owner)=try lookupOwner("""
        let order='';
        export function init(v){order+='I';thisObject.stop();return v;}
        export function animationEvent(e,v){
          if(e.frame!==3)throw new Error('frame payload');
          const label=e.name;e.name='local edit';e.frame=999;order+=label;
          if(label==='A'){thisLayer.getAnimationLayer(1).play();return !v;}
          if(label==='B')return undefined;
          throw new Error('foreign parent reached');
        }
        export function update(v){if(order!=='IAB'||v!==false)throw new Error('callback order');
          thisObject.pause();return v;}
        """,native.snapshots())
        let peer=try SceneScriptValueOwner(domain:domain,source:"""
        export function animationEvent(e,v){if(e.frame!==3||(e.name!=='A'&&e.name!=='B'))throw new Error('payload copy');return v;}
        """,target:ScenePuppetAnimationPropertyTarget.visibility(layerID:42,animationLayerID:208),
            valueType:.bool,effectNames:[],puppetAnimationIdentity:sibling,
            allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        try domain.publishPuppetAnimationSnapshot(native.snapshots())
        let events=[occurrence(identity,1,"A"),occurrence(sibling,1,"B"),occurrence(foreign,1,"foreign")]
        try domain.publishPuppetAnimationEvents(events,failures:[:])
        let first=try evaluate(owner).get()
        out["eventOrderValue"]=first.value == .bool(false)
        out["eventWritablePayloadIsolated"]=try evaluate(peer).get().value == .bool(true)
        peer.commitLayerMutations()
        out["eventOrderActions"]=actions(first.puppetAnimationCommands)
        try native.validate(first.puppetAnimationCommands,sourceLayerID:42,sourceAnimationLayerID:91,frameIndex:1).get()
        try native.apply(first.puppetAnimationCommands,frameIndex:1).get();owner.commitLayerMutations()
        out["eventNativeSiblingPlaying"]=native.snapshots().first{$0.identity == sibling}?.isPlaying == true
        try domain.publishPuppetAnimationEvents(events,failures:[:])
        out["eventDeduplicated"] = !mwx_scene_quickjs_owner_has_pending_puppet_animation_events(owner.handle)

        phase("events/retry-and-property-refresh")
        let (pendingDomain,pending)=try lookupOwner("""
        export function animationEvent(e,v){thisObject.pause();return e.name==='enable';}
        """)
        try pendingDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"disable")],failures:[:])
        out["eventOnlyWakes"]=pending.requiresFrameEvaluation
        let refresh=try pending.evaluate(input:.bool(true),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",
            expectedGeneration:1,interruptBudget:nil,propertyRefresh:true).get()
        out["eventRefreshUntouched"]=refresh.value == .bool(true) && refresh.puppetAnimationCommands.isEmpty
            && mwx_scene_quickjs_owner_has_pending_puppet_animation_events(pending.handle)
        let rejected=try evaluate(pending).get();pending.discardLayerMutations()
        out["eventRejectedValue"]=rejected.value == .bool(false)
        out["eventRejectedStillPending"]=pending.requiresFrameEvaluation
        // A later cadence adds payload; rejecting the old candidate cannot lose either occurrence.
        try pendingDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"disable"),occurrence(identity,1,"enable")],failures:[:])
        let retry=try evaluate(pending).get()
        out["eventCrossCadenceRetry"]=retry.value == .bool(true) && actions(retry.puppetAnimationCommands) == ["pause","pause"]
        pending.commitLayerMutations()
        try pendingDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"disable"),occurrence(identity,1,"enable")],failures:[:])
        out["eventOnlySleeps"] = !pending.requiresFrameEvaluation

        phase("events/transaction-snapshot")
        let (rollbackDomain,rollback)=try lookupOwner("""
        export function animationEvent(e,v){thisObject.pause();return !v;}
        """)
        try rollbackDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"edge")],failures:[:])
        guard let checkpoint=mwx_scene_quickjs_owner_timer_snapshot(rollback.handle) else { fatalError("timer checkpoint") }
        _=try evaluate(rollback).get()
        out["eventTimerRestored"]=mwx_scene_quickjs_owner_timer_restore(rollback.handle,checkpoint)
        mwx_scene_quickjs_owner_timer_snapshot_destroy(checkpoint,rollback.handle)
        let replay=try evaluate(rollback).get()
        out["eventTimerReplay"]=replay.value == .bool(false) && actions(replay.puppetAnimationCommands) == ["pause"]
        rollback.commitLayerMutations()


        phase("events/temporary-unavailability")
        let (transientDomain,transient)=try lookupOwner("export function animationEvent(e,v){thisObject.pause();return false;}")
        let invalid=[prepared(identity,"Authored clip",3,fps:.nan),prepared(sibling,"Side arc",29,false),prepared(foreign,"Foreign clip",55)]
        try transientDomain.publishPuppetAnimationSnapshot(invalid)
        try transientDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"retained")],failures:[:])
        let unavailable=try evaluate(transient).get()
        out["eventTemporaryKeepsPayload"]=unavailable.puppetAnimationCommands.isEmpty
            && mwx_scene_quickjs_owner_has_pending_puppet_animation_events(transient.handle)
        try transientDomain.publishPuppetAnimationSnapshot(mirrors())
        let recovered=try evaluate(transient).get();transient.commitLayerMutations()
        out["eventTemporaryRecoversOnce"]=recovered.value == .bool(false)
            && actions(recovered.puppetAnimationCommands) == ["pause"]
            && !mwx_scene_quickjs_owner_has_pending_puppet_animation_events(transient.handle)
        try transientDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"retained")],failures:[:])
        out["eventTemporaryDedup"] = !mwx_scene_quickjs_owner_has_pending_puppet_animation_events(transient.handle)
        let (abaDomain,aba)=try lookupOwner("""
        export function animationEvent(e,v){if(e.name!=='fresh')throw new Error('retired source');thisObject.pause();return v;}
        """)
        try abaDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"old")],failures:[:])
        try abaDomain.publishPuppetAnimationSnapshot(mirrors().filter{$0.identity != sibling})
        try abaDomain.publishPuppetAnimationSnapshot(mirrors())
        try abaDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"fresh")],failures:[:])
        let replacement=try evaluate(aba).get();aba.commitLayerMutations()
        out["eventSourceABA"]=actions(replacement.puppetAnimationCommands) == ["pause"]

        phase("events/aggregate-parent-budgets")
        let (aggregateDomain,aggregate)=try lookupOwner("export function animationEvent(e,v){thisObject.pause();return v;}")
        let sources=[identity]+(100...163).map{ScenePuppetAnimationIdentity(layerID:$0,animationLayerIndex:0,animationLayerID:91)}
        // Preserve the proven receiver metadata; unrelated parents need no receiver.
        try aggregateDomain.publishPuppetAnimationSnapshot([prepared(identity,"Authored clip",3)]
            + sources.dropFirst().map{prepared($0,"bounded",0)})
        let batch=sources.flatMap{id in (1...64).map{occurrence(id,UInt64($0),"edge")}}
        try aggregateDomain.publishPuppetAnimationEvents(batch,failures:[:])
        let aggregateResult=try evaluate(aggregate).get();aggregate.commitLayerMutations()
        out["eventAggregate4160"]=batch.count == 4160 && aggregateResult.puppetAnimationCommands.count == 64
            && !mwx_scene_quickjs_owner_has_pending_puppet_animation_events(aggregate.handle)

        phase("events/local-failures")
        let (badDomain,bad)=try lookupOwner("""
        let attempts=0;export function animationEvent(e,v){attempts++;if(attempts===1)return 17;return false;}
        """)
        try badDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"edge")],failures:[:])
        if case let .failure(f)=evaluate(bad){out["eventBadReturn"]=f.code}
        // Native cursor rolls back; JS lexical attempts deliberately does not.
        out["eventBadReturnRetry"]=try evaluate(bad).get().value == .bool(false)
        bad.commitLayerMutations()
        let (throwDomain,throwing)=try lookupOwner("export function animationEvent(e,v){thisObject.stop();throw new Error('own failure');}")
        try throwDomain.publishPuppetAnimationEvents([occurrence(identity,1,"edge")],failures:[:])
        if case let .failure(f)=evaluate(throwing){out["eventThrow"]=f.code}
        out["eventThrowCommands"]=try SceneScriptPuppetAnimationBridge.commands(owner:throwing.handle).get().count
        let (limitDomain,limit)=try lookupOwner("export function animationEvent(e,v){return v;}")
        try limitDomain.publishPuppetAnimationEvents((1...65).map{occurrence(sibling,UInt64($0),"edge")},failures:[:])
        if case let .failure(f)=evaluate(limit){out["eventQueueBudget"]=f.code}
        let (failureDomain,failure)=try lookupOwner("export function animationEvent(e,v){return v;}")
        try failureDomain.publishPuppetAnimationEvents([],failures:[foreign:.unsupportedMode])
        out["eventForeignFailureQuiet"] = !failure.requiresFrameEvaluation
        try failureDomain.publishPuppetAnimationEvents([],failures:[sibling:.unsupportedMode])
        if case let .failure(f)=evaluate(failure){out["eventSourceFailure"]=f.code}
        let (_,healthy)=try make("export function update(v){return v;}")
        out["eventHealthyPeer"]=try evaluate(healthy).get().value == .bool(true)

        phase("events/retirement-and-scope")
        let (retiredDomain,retired)=try lookupOwner("export function animationEvent(e,v){throw new Error('retired payload');}")
        try retiredDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"edge")],failures:[:])
        try retiredDomain.publishPuppetAnimationSnapshot([])
        out["eventRetirementClears"] = !mwx_scene_quickjs_owner_has_pending_puppet_animation_events(retired.handle)
        let ordinaryDomain=try SceneScriptQuickJSDomain();let ordinaryDescriptor=descriptor()
        try ordinaryDomain.configureLayerCatalog(ordinaryDescriptor)
        let scalar=try SceneScriptValueOwner(domain:ordinaryDomain,
            source:"export function update(v){return v+3;} export function animationEvent(e,v){return false;}",
            target:.layer(layerID:42,field:.brightness),valueType:.scalar,effectNames:[],generation:1,budget:.default)
        let scalarResult=try scalar.evaluate(input:.scalar(2),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",
            expectedGeneration:1,interruptBudget:nil).get()
        out["eventOrdinaryScalarPreserved"]=scalarResult.value == .scalar(5)
            && mwx_scene_quickjs_domain_puppet_animation_owner_count(ordinaryDomain.handle) == 0
        let text=try SceneScriptValueOwner(domain:ordinaryDomain,
            source:"export function update(v){return v+'!';} export function animationEvent(e,v){throw new Error('not a receiver');}",
            target:.text(layerID:42,field:.content),valueType:.string,effectNames:[],generation:1,budget:.default)
        let textResult=try text.evaluate(input:.string("probe"),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",
            expectedGeneration:1,interruptBudget:nil).get()
        out["eventOrdinaryTextClonePreserved"]=textResult.value == .string("probe!") && text.supportsPreparedTextClone
        let (typeDomain,typed)=try lookupOwner("export const animationEvent=3;export function update(v){return !v;}")
        out["eventInvalidCallbackBeforeOccurrence"]=try evaluate(typed).get().value == .bool(false)
        typed.commitLayerMutations()
        try typeDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"edge")],failures:[:])
        if case let .failure(f)=evaluate(typed){out["eventInvalidCallbackAtOccurrence"]=f.code}
        let (invalidatedDomain,invalidated)=try lookupOwner("export function animationEvent(e,v){return v;}")
        try invalidatedDomain.publishPuppetAnimationEvents([occurrence(sibling,1,"edge")],failures:[:])
        mwx_scene_quickjs_owner_invalidate(invalidated.handle)
        out["eventInvalidationUnregisters"]=mwx_scene_quickjs_domain_puppet_animation_owner_count(invalidatedDomain.handle) == 0
            && !mwx_scene_quickjs_owner_has_pending_puppet_animation_events(invalidated.handle)
        return out
    }

    static func main() throws {
        phase("main/lookup-suite")
        var out=try lookupChecks()
        out.merge(try eventChecks(),uniquingKeysWith: { _,new in new })
        // Real nested parser + candidate projection, including authored properties.
        phase("main/parser-projection")
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
        phase("main/persistent-handle-setup")
        let (persistentDomain,persistent)=try make("""
        let a;
        export function init(v){a=thisObject;a.addEndedCallback(()=>{if(thisLayer.name!=="parent"||thisLayer.getBoneCount()!==1||thisLayer.getLocalBoneOrigin(0).x!==0)throw new Error("bound layer");a.stop();});return v;}
        export function update(v){return a.isPlaying() && a.getFrame()>0;}
        """)
        try persistent.configurePuppetBones(layerID:42,
            localMatrices:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],names:["root"],parents:[-1])
        _=try evaluate(persistent).get();persistent.commitLayerMutations()
        phase("main/persistent-ended-delivery")
        try persistentDomain.publishPuppetAnimationSnapshot([snapshot(1.25,1)])
        let ended=try evaluate(persistent).get()
        out["endedActions"]=actions(ended.puppetAnimationCommands);out["endedBeforeUpdate"]=ended.value == .bool(false)
        persistent.commitLayerMutations()
        out["endedOnce"]=actions(try evaluate(persistent).get().puppetAnimationCommands)
        persistent.commitLayerMutations()

        // Host rejection restores roots and controls but consumes natural-end input.
        phase("main/host-rejection-rollback")
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
        phase("main/program-owner-rejection")
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
        phase("main/self-visible-arbitration")
        let (_,visibility)=try make("""
        export function init(v){thisObject.rate=2;thisObject.blend=.25;return v;}
        export function update(v){thisObject.visible=false;return true;}
        """)
        let vis=try evaluate(visibility).get();out["visibleValue"]=vis.value == .bool(false)
        out["visibleActions"]=actions(vis.puppetAnimationCommands);out["visibleParentWrites"]=vis.layerMutations.count
        visibility.commitLayerMutations()

        // Finite raw seek is observable immediately, including unclamped bounds.
        phase("main/finite-seek")
        let (_,bounds)=try make("""
        export function update(v){thisObject.pause();thisObject.setFrame(-1.5);if(thisObject.getFrame()!==-1.5)throw new Error('raw');
          thisObject.setFrame(720.5);return !thisObject.isPlaying()&&thisObject.getFrame()===720.5;}
        """)
        let bounded=try evaluate(bounds).get();out["boundsValue"]=bounded.value == .bool(true);out["boundsActions"]=actions(bounded.puppetAnimationCommands)
        bounds.commitLayerMutations()

        phase("main/init-throw")
        let (_,throwing)=try make("export function init(v){thisObject.addEndedCallback(()=>thisObject.stop());thisObject.play();throw new Error('failed');}")
        if case let .failure(failure)=evaluate(throwing){out["throwFailure"]=failure.code}
        out["throwCommands"]=mwx_scene_quickjs_owner_puppet_animation_command_count(throwing.handle)
        phase("main/ended-throw")
        let (failedEndDomain,failedEnd)=try make("""
        let a;export function init(v){a=thisObject;a.addEndedCallback(()=>{a.pause();throw new Error('ended failed');});return v;}
        export function update(v){return v;}
        """)
        _=try evaluate(failedEnd).get();failedEnd.commitLayerMutations()
        try failedEndDomain.publishPuppetAnimationSnapshot([snapshot(2,1)])
        if case let .failure(failure)=evaluate(failedEnd){out["endedThrowFailure"]=failure.code}
        out["endedThrowCommands"]=mwx_scene_quickjs_owner_puppet_animation_command_count(failedEnd.handle)
        out["endedThrowPending"]=mwx_scene_quickjs_owner_has_pending_puppet_animation_end(failedEnd.handle)

        phase("main/stale-self-handle")
        var held:(SceneScriptQuickJSDomain,SceneScriptValueOwner)?=try make("export function init(v){shared.savedAnimation=thisObject;return v;}")
        let staleDomain=held!.0
        _=try evaluate(held!.1).get();held!.1.commitLayerMutations();held=nil
        let wrongOwner=try SceneScriptValueOwner(domain:staleDomain,source:"export function update(v){shared.savedAnimation.play();return v;}",
            target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
        let staleResult=wrongOwner.evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        if case let .failure(failure)=staleResult{out["staleHandleFailure"]=failure.code}

        phase("main/command-budget")
        let (_,overflow)=try make("export function update(v){for(let i=0;i<65;i++){try{thisObject.play();}catch(e){}}return v;}")
        if case let .failure(failure)=evaluate(overflow){out["overflowFailure"]=failure.code}
        out["overflowCommands"]=mwx_scene_quickjs_owner_puppet_animation_command_count(overflow.handle)
        phase("main/ended-root-budget")
        let (_,roots)=try make("export function init(v){for(let i=0;i<17;i++)thisObject.addEndedCallback(()=>thisObject.pause());return v;}")
        if case let .failure(failure)=evaluate(roots){out["rootBudgetFailure"]=failure.code}

        // C admits finite Float writes; the actual shared runtime rejects a
        // negative rate atomically and the owner mirror rolls back with it.
        phase("main/swift-runtime-rejection")
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

        phase("main/missing-metadata")
        let (missingDomain,missing)=try make("export function update(v){return thisObject.isPlaying();}")
        try missingDomain.publishPuppetAnimationSnapshot([])
        if case let .failure(failure)=evaluate(missing){out["missingFailure"]=failure.code}
        // Existing ordinary owners remain executable when one prepared clip is absent.
        phase("main/ordinary-peer-after-missing")
        let peer=try SceneScriptValueOwner(domain:missingDomain,source:"export function update(v){return v.add(new Vec3(1,0,0));}",
            target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
        let peerResult=try peer.evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
        out["missingPeer"]=peerResult.value == .vector3(1,0,0);peer.commitLayerMutations()

        phase("main/unsupported-ended-profile")
        try persistentDomain.publishPuppetAnimationSnapshot([snapshot(5,2,.multipleLoopsCrossed)])
        if case let .failure(failure)=evaluate(persistent){out["endedUnsupported"]=failure.code}
        out["endedUnsupportedPending"]=mwx_scene_quickjs_owner_has_pending_puppet_animation_end(persistent.handle)
        if case let .failure(failure)=evaluate(persistent){out["endedUnsupportedRetry"]=failure.code}
        phase("main/teardown")
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


    def test_named_events_chain_init_events_update_and_same_parent_native_controls(self):
        self.assertTrue(self.values["eventOrderValue"])
        self.assertTrue(self.values["eventWritablePayloadIsolated"])
        self.assertEqual(self.values["eventOrderActions"], ["stop", "play", "pause"])
        self.assertTrue(self.values["eventNativeSiblingPlaying"])
        self.assertTrue(self.values["eventDeduplicated"])

    def test_event_only_fifo_survives_rejection_new_cadence_and_property_refresh(self):
        for key in ("eventOnlyWakes", "eventRefreshUntouched", "eventRejectedValue",
                    "eventRejectedStillPending", "eventCrossCadenceRetry", "eventOnlySleeps",
                    "eventTimerRestored", "eventTimerReplay", "eventTemporaryKeepsPayload",
                    "eventTemporaryRecoversOnce", "eventTemporaryDedup", "eventSourceABA",
                    "eventAggregate4160"):
            with self.subTest(check=key):
                self.assertTrue(self.values[key])

    def test_event_failure_is_local_typed_and_native_cursor_does_not_claim_heap_rollback(self):
        self.assertEqual(self.values["eventBadReturn"], "bad-return")
        self.assertTrue(self.values["eventBadReturnRetry"])
        self.assertEqual(self.values["eventThrow"], "exception")
        self.assertEqual(self.values["eventThrowCommands"], 0)
        self.assertEqual(self.values["eventQueueBudget"], "mutation-overflow")
        self.assertEqual(self.values["eventSourceFailure"], "disabled")
        self.assertTrue(self.values["eventForeignFailureQuiet"])
        self.assertTrue(self.values["eventHealthyPeer"])
        self.assertTrue(self.values["eventRetirementClears"])
        self.assertTrue(self.values["eventOrdinaryScalarPreserved"])
        self.assertTrue(self.values["eventOrdinaryTextClonePreserved"])
        self.assertTrue(self.values["eventInvalidCallbackBeforeOccurrence"])
        self.assertEqual(self.values["eventInvalidCallbackAtOccurrence"], "bad-return")
        self.assertTrue(self.values["eventInvalidationUnregisters"])

    def test_lookup_name_index_variants_reach_the_actual_shared_runtime(self):
        self.assertEqual(self.values["lookupVariants"], [True] * 3)

    def test_lookup_pending_journal_survives_init_properties_update_without_duplicate_exports(self):
        self.assertEqual(self.values["lookupPrimitiveRanges"],
                         [["stop", "frame:7.0"], ["play", "frame:11.0"], ["pause"]])
        self.assertTrue(self.values["lookupPrimitiveNative"])
        self.assertTrue(self.values["lookupPrimitiveAfterCommit"])

    def test_lookup_input_and_owner_scope_reject_without_aliasing_self(self):
        for key in ("lookupBadInputs", "lookupDuplicateName", "lookupLocalRead",
                    "lookupOwnerIsolation", "lookupNonNested"):
            with self.subTest(check=key):
                self.assertTrue(self.values[key])

    def test_cached_lookup_handles_keep_owner_generation_and_target_lifetime(self):
        self.assertEqual(self.values["lookupRetiredHandle"], [True, True])
        for key in ("lookupFreshAfterReappear", "lookupGenerationRejected", "lookupDestroyedOwner"):
            with self.subTest(check=key):
                self.assertTrue(self.values[key])

    def test_present_invalid_metadata_recovers_cached_handles_and_stable_layout_refreshes_values(self):
        self.assertEqual(self.values["lookupMetadataRecovery"], [True] * 3)

    def test_lookup_forbidden_sibling_effects_throw_and_budget_rollback_whole_bundle(self):
        self.assertEqual(self.values["lookupRejectedBundles"], [True] * 3)
        self.assertEqual(self.values["lookupBudgetFailure"], "mutation-overflow")
        self.assertEqual(self.values["lookupBudgetCommands"], 0)

    def test_lookup_self_ended_and_timer_rollback_preserve_visibility_arbitration(self):
        self.assertTrue(self.values["lookupSelfEnded"])
        self.assertTrue(self.values["lookupTimerRollback"], self.values["lookupTimerDetails"])

    def test_lookup_runtime_admission_keeps_source_target_and_atomic_rejection(self):
        self.assertTrue(self.values["lookupSwiftReject"])
        self.assertTrue(self.values["lookupSwiftRetry"])
        self.assertEqual(self.values["lookupRuntimeAdmission"], [True] * 5)

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
