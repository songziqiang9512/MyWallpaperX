"""RF03 real QuickJS -> Swift owner admission -> two real simulators."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from .scene_vector_vm_test_support import compile_vector_harness, SWIFT_PREAMBLE, ROOT
from .test_scene_particle_simulator import SWIFT_SOURCES as PARTICLE_SOURCES

HARNESS = r'''
struct SceneDesktopWallpaperLaunchContext {
    struct Input {let renderDescriptor:SceneRenderDescriptor}
    struct Program {let generation:UInt64}
    let runtimeInput:Input
    let propertyVectorScriptProgram:Program
}
final class SceneDesktopWallpaperSession {
    final class View {
        let simulator:SceneParticleSimulator?
        init(_ simulator:SceneParticleSimulator?) {self.simulator=simulator}
        func particlePlaybackObservation(layerID:Int)->SceneParticlePlaybackObservation? {simulator?.playbackObservation}
    }
    struct Surface {let metalView:View;let scriptGeneration:UInt64}
    var surfaces:[UInt32:Surface]=[:]
    var preparedSurfaceIDs:Set<UInt32>=[]
}
// PRODUCTION_SESSION_PROJECTION
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970:0), simulationFrameTime:0.25, sceneTime:1))
    static let target = SceneDynamicTarget.particle(layerID:42,field:.alpha)
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers:[.init(id:42,layerIndex:0,name:"particles",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[],contentKind:"particle",sizeWH:[100,100])])
        func simulator(_ initial:SceneParticlePlaybackSnapshot = .init(), start:Double = 0.5) throws -> SceneParticleSimulator {
            let root:[String:Any] = ["material":"p.json","maxcount":100,"starttime":start,
                "emitter":[["name":"boxrandom","rate":4,"duration":1,"distancemax":2]],
                "initializer":[["name":"lifetimerandom","min":10,"max":10]],"renderer":[["name":"sprite"]]]
            return SceneParticleSimulator(definition:try SceneParticleDefinitionParser().parse(root:root),initialPlayback:initial,seed:81,fixedTimeStep:0.25)
        }
        func owner(_ domain:SceneScriptQuickJSDomain,_ source:String,_ target:SceneDynamicTarget = target) throws -> SceneScriptValueOwner {
            try SceneScriptValueOwner(domain:domain,source:source,target:target,valueType:.scalar,effectNames:[],allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        }
        func evaluate(_ owner:SceneScriptValueOwner,_ value:Double = 1) throws -> SceneScriptValueEvaluation {
            try owner.evaluate(input:.scalar(value),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
        }
        func effects(_ owner:SceneScriptValueOwner,_ evaluation:SceneScriptValueEvaluation)->SceneScriptOwnerEffects {
            var result=SceneScriptOwnerEffects(ownerTarget:owner.target,materialFunctionMutations:[],animationMutations:[],layerMutations:[],videoCommands:[])
            result.append(evaluation);return result
        }
        var result:[String:Bool]=[:]
        for method in ["pause","stop"] {
            let domain=try SceneScriptQuickJSDomain();try domain.configureLayerCatalog(descriptor)
            let a=try simulator(),b=try simulator();let before=a.particles
            try domain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor,particlePlaybackObservations:[42:a.playbackObservation!])
            let author=try owner(domain,"export function init(v){thisLayer.\(method)(); if(thisLayer.isPlaying()!==\(method == "pause" ? "true":"false"))throw Error('query');return v;} export function update(v){return v;}")
            let evaluation=try evaluate(author)
            let state=SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
            let admission=state.preflightOwnerEffectsToFixedPoint([effects(author,evaluation)],particleObservations:[42:a.playbackObservation!],validateParticleTransitions:{ !$0.isEmpty }) { _ in [] }
            precondition(admission.admission.rejectedOwners.isEmpty)
            for command in admission.admission.layerPlan.particleTransitions {a.applyPlaybackTransition(command);b.applyPlaybackTransition(command)}
            a.advance(by:0.25);b.advance(by:0.25)
            state.commit(admission.admission.layerPlan);author.commitLayerMutations()
            result["init_"+method] = method == "pause" ? !before.isEmpty && a.particles.map(\.id)==before.map(\.id) && a.particles[0].age>before[0].age : a.particles.isEmpty
            let rebuilt=try simulator(state.snapshot().particlePlayback[42]!)
            result["rebuild_"+method] = rebuilt.particles.isEmpty && rebuilt.playback==state.snapshot().particlePlayback[42]
            let consumed=a.frameSnapshot()
            for command in admission.admission.layerPlan.particleTransitions {a.applyPlaybackTransition(command)}
            result["no_replay_"+method] = a.frameSnapshot().particles==consumed.particles && a.playback==consumed.playback
        }
        let scalarSource="export function init(v){thisLayer.pause();return v;} export function update(v){return v;}"
        var scalarDescriptor=descriptor
        scalarDescriptor.layers[0].particleInstanceOverride=SceneParticleDefinitionParser().parseInstanceOverride(["alpha":["value":1,"script":scalarSource]])
        let binding=SceneScriptBindingIR(source:scalarSource,owner:.init(kind:.object,objectIndex:0,objectID:42,effectIndex:nil,effectID:nil,passIndex:nil,passID:nil),targetPath:[.key("objects"),.index(0),.key("instanceoverride"),.key("alpha")],properties:[:],authoredValue:.number(1),valueType:.number,wrapperKeys:["script","value"])
        let scalarDomain=try SceneScriptQuickJSDomain()
        try scalarDomain.configureLayerCatalog(scalarDescriptor)
        let scalar=SceneScriptScalarProgram.compile(domain:scalarDomain,descriptor:scalarDescriptor,scriptBindings:[binding])
        let scalarSim=try simulator()
        try scalarDomain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:scalarDescriptor,particlePlaybackObservations:[42:scalarSim.playbackObservation!])
        let scalarResult=scalar.evaluate(inputs:[target:.scalar(1)],frame:frame,effectivePropertyValues:[:])
        result["real_scalar_program_init_effect"] = scalar.bindings.count==1 && scalarResult.failures.isEmpty && scalarResult.ownerEffects.flatMap(\.particlePlaybackCommands).map(\.action)==[.pause]
        scalar.finalizeLayerMutations(committing:true)
        let domain=try SceneScriptQuickJSDomain();try domain.configureLayerCatalog(descriptor)
        let a=try simulator(),b=try simulator()
        try domain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor,particlePlaybackObservations:[42:a.playbackObservation!])
        let source="export function update(v){if(v===1)thisLayer.stop();else if(v===2)thisLayer.play();else thisLayer.pause();return v;}"
        let first=try owner(domain,source),second=try owner(domain,source,.particle(layerID:42,field:.size))
        let stop=try evaluate(first,1),play=try evaluate(second,2),pause=try evaluate(first,3)
        var firstEffects=effects(first,stop);firstEffects.append(pause)
        let secondEffects=effects(second,play)
        let state=SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
        let observations=[42:a.playbackObservation!]
        let plan=state.preflightOwnerEffects([firstEffects,secondEffects],particleObservations:observations).layerPlan
        result["cross_owner_order"] = plan.particleTransitions.map(\.action)==[.stop,.play,.pause]
        let late=state.preflightOwnerEffectsToFixedPoint([firstEffects,secondEffects],particleObservations:observations,validateParticleTransitions:{_ in true}) { _ in [first.target] }
        result["late_rejection"] = late.admission.layerPlan.particleTransitions.map(\.action)==[.play] && a.playback.revision==0 && b.playback.revision==0
        first.discardLayerMutations()
        result["c_discard"] = mwx_scene_quickjs_owner_particle_playback_command_count(first.handle)==0
        let separateCallbacks=try owner(domain,"export function init(v){thisLayer.stop();if(thisLayer.isPlaying())throw Error('init');return v;} export function update(v){if(!thisLayer.isPlaying())throw Error('committed callback snapshot');thisLayer.pause();return v;}")
        let separate=try evaluate(separateCallbacks).particlePlaybackCommands
        result["callback_epoch_overlay"] = separate.count==2 && separate[0].callbackEpoch<separate[1].callbackEpoch && separate.map(\.ordinal)==[0,0]
        separateCallbacks.discardLayerMutations()
        let query=try owner(domain,"export function update(v){thisLayer.stop();if(thisLayer.isPlaying())throw Error('stop');thisLayer.play();if(!thisLayer.isPlaying())throw Error('rearm');return v;}",.particle(layerID:42,field:.rate))
        result["stop_query_play"] = try evaluate(query).particlePlaybackCommands.map(\.action)==[.stop,.play]
        query.discardLayerMutations()
        let throwing=try owner(domain,"export function update(v){thisLayer.stop();throw Error('late');}")
        do {_ = try evaluate(throwing);result["callback_discard"]=false} catch {result["callback_discard"]=mwx_scene_quickjs_owner_particle_playback_command_count(throwing.handle)==0}
        let bounded=try owner(domain,"export function update(v){for(let n=0;n<v;n++)thisLayer.pause();return v;}",.particle(layerID:42,field:.count))
        let boundary=try evaluate(bounded,64)
        result["budget_boundary"] = boundary.particlePlaybackCommands.count==64
        bounded.discardLayerMutations()
        do {_ = try evaluate(bounded,65);result["budget_overflow"]=false} catch {result["budget_overflow"]=mwx_scene_quickjs_owner_particle_playback_command_count(bounded.handle)==0}
        let budgetEffects=effects(bounded,boundary)
        let overPlan=state.preflightOwnerEffects([budgetEffects,secondEffects],particleObservations:observations)
        result["scene_budget_overflow"] = overPlan.admittedEffects.isEmpty && overPlan.layerPlan.particleTransitions.isEmpty
        try domain.publishLayerSnapshot(.empty(frameIndex:1),descriptor:descriptor)
        do {_ = try evaluate(query);result["missing_unavailable"]=false} catch {result["missing_unavailable"]=true}
        // Finished emission may retain live particles: play rearms only schedule.
        let finished=try simulator(start:0);finished.advance(by:1.25)
        let before=finished.frameSnapshot()
        try domain.publishLayerSnapshot(.empty(frameIndex:2),descriptor:descriptor,particlePlaybackObservations:[42:finished.playbackObservation!])
        let rearm=try owner(domain,"export function update(v){thisLayer.play();if(!thisLayer.isPlaying())throw Error('rearm');return v;}")
        let evaluated=try evaluate(rearm)
        let rearmPlan=state.preflightOwnerEffects([effects(rearm,evaluated)],particleObservations:[42:finished.playbackObservation!]).layerPlan
        for command in rearmPlan.particleTransitions {finished.applyPlaybackTransition(command)}
        result["finished_rearm_preserves_live"] = !before.particles.isEmpty && finished.particles==before.particles && finished.frameSnapshot().random.state==before.random.state
        finished.advance(by:0.25)
        result["finished_rearm_birth"] = finished.particles.count>before.particles.count
        let pointerRoot:[String:Any] = ["material":"p.json","maxcount":8,"starttime":1,
            "controlpoint":[["id":0,"flags":1,"offset":"0 0 0"]],
            "emitter":[["name":"sphererandom","instantaneous":4,"rate":0,"distancemin":0,"distancemax":0,"speedmin":1,"speedmax":1,"directions":"0 0 0"]],
            "initializer":[["name":"lifetimerandom","min":10,"max":10]],"renderer":[["name":"sprite"]]]
        let pointerDefinition=try SceneParticleDefinitionParser().parse(root:pointerRoot)
        let inside=SceneParticleSimulator(definition:pointerDefinition,seed:71,fixedTimeStep:0.1)
        let outside=SceneParticleSimulator(definition:pointerDefinition,seed:71,fixedTimeStep:0.1)
        inside.advance(by:0.1,dynamicControlPoints:[0:SIMD3(5,6,0)])
        outside.advance(by:0.1,dynamicControlPoints:[0:SIMD3(repeating:.nan)])
        result["real_pointer_divergence"] = !inside.particles.isEmpty && outside.particles.isEmpty
        for sim in [inside,outside] {sim.applyPlaybackTransition(.init(layerID:42,action:.pause,revision:1))}
        let session=SceneDesktopWallpaperSession()
        let context=SceneDesktopWallpaperLaunchContext(runtimeInput:.init(renderDescriptor:descriptor),propertyVectorScriptProgram:.init(generation:1))
        let committed:[Int:SceneParticlePlaybackSnapshot]=[42:.init(intent:.paused,revision:1)]
        session.preparedSurfaceIDs=[1,2]
        session.surfaces=[1:.init(metalView:.init(inside),scriptGeneration:1),2:.init(metalView:.init(outside),scriptGeneration:1)]
        let forward=session.particlePlaybackObservations(context:context,committed:committed)
        session.surfaces=[2:.init(metalView:.init(inside),scriptGeneration:1),1:.init(metalView:.init(outside),scriptGeneration:1)]
        let backward=session.particlePlaybackObservations(context:context,committed:committed)
        result["session_OR_order_independent"] = forward==backward && forward[42]?.liveAny==true
        let hiddenDescriptor=SceneRenderDescriptor(layers:[.init(id:42,layerIndex:0,name:"particles",visible:false,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:0,effects:[],contentKind:"particle",sizeWH:[100,100])])
        let hiddenContext=SceneDesktopWallpaperLaunchContext(runtimeInput:.init(renderDescriptor:hiddenDescriptor),propertyVectorScriptProgram:.init(generation:1))
        result["prepared_hidden_instance_query"] = session.particlePlaybackObservations(context:hiddenContext,committed:committed)[42]?.liveAny==true
        try domain.publishLayerSnapshot(.empty(frameIndex:4),descriptor:descriptor,particlePlaybackObservations:forward)
        let hiddenStop=try owner(domain,"export function update(v){thisLayer.stop();if(thisLayer.isPlaying())throw Error('stop hidden live');return v;}")
        result["prepared_hidden_instance_stop"] = try evaluate(hiddenStop).particlePlaybackCommands.map(\.action)==[.stop]
        hiddenStop.discardLayerMutations()
        session.surfaces[2]=nil
        result["session_missing_surface_unavailable"] = session.particlePlaybackObservations(context:context,committed:committed).isEmpty
        session.surfaces[2] = .init(metalView:.init(nil),scriptGeneration:1)
        result["session_missing_instance_unavailable"] = session.particlePlaybackObservations(context:context,committed:committed).isEmpty
        session.surfaces[2] = .init(metalView:.init(inside),scriptGeneration:2)
        result["session_stale_generation_unavailable"] = session.particlePlaybackObservations(context:context,committed:committed).isEmpty
        let zeroRoot:[String:Any] = ["material":"p.json","emitter":[["name":"boxrandom","rate":0,"instantaneous":0]],"renderer":[["name":"sprite"]]]
        let zero=SceneParticleSimulator(definition:try SceneParticleDefinitionParser().parse(root:zeroRoot))
        try domain.publishLayerSnapshot(.empty(frameIndex:3),descriptor:descriptor,particlePlaybackObservations:[42:zero.playbackObservation!])
        let noWork=try owner(domain,"export function update(v){thisLayer.play();if(thisLayer.isPlaying())throw Error('zero work');return v;}")
        result["zero_work_query_false"] = try evaluate(noWork).particlePlaybackCommands.count==1
        noWork.discardLayerMutations()
        try domain.publishLayerSnapshot(.empty(frameIndex:5),descriptor:descriptor,awaitingHostFrameOutcome:true)
        do {_ = try evaluate(noWork);result["staged_missing_unavailable"]=false} catch {result["staged_missing_unavailable"]=true}
        domain.discardCommittedLayerSnapshot()
        let restoredOwner=try owner(domain,"export function update(v){thisLayer.play();if(thisLayer.isPlaying())throw Error('zero work after rollback');return v;}")
        result["observation_rollback"] = try evaluate(restoredOwner).particlePlaybackCommands.count==1
        noWork.discardLayerMutations()
        for method in ["play","pause","stop","isPlaying"] {
            let unsupported=try owner(domain,"export function update(v){thisLayer.\(method)(true);return v;}")
            do {_ = try evaluate(unsupported);result["unsupported_argument_"+method]=false} catch {result["unsupported_argument_"+method]=mwx_scene_quickjs_owner_particle_playback_command_count(unsupported.handle)==0}
        }
        let caught=try owner(domain,"export function update(v){try{for(let i=0;i<65;i++)thisLayer.pause();}catch(e){}return v;}",.particle(layerID:42,field:.count))
        do {_ = try evaluate(caught);result["caught_budget_overflow"]=false} catch {result["caught_budget_overflow"]=mwx_scene_quickjs_owner_particle_playback_command_count(caught.handle)==0}
        let timerDomain=try SceneScriptQuickJSDomain();try timerDomain.configureLayerCatalog(descriptor)
        try timerDomain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor,particlePlaybackObservations:observations)
        let timers=try owner(timerDomain,"""
            export function init(v){
              engine.setTimeout(()=>{thisLayer.stop(); Promise.resolve().then(()=>{if(thisLayer.isPlaying())throw Error('timer microtask');});},10);
              engine.setTimeout(()=>{if(!thisLayer.isPlaying())throw Error('timer isolation');thisLayer.pause();},10);
              return v;
            }
            export function update(v){if(!thisLayer.isPlaying())throw Error('timer update isolation');return v;}
            """)
        _ = try evaluate(timers);timers.commitLayerMutations()
        let timerFrame=SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.25,sceneTime:2))
        if let fired=try? timers.evaluate(input:.scalar(1),frame:timerFrame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get() {
            let commands=fired.particlePlaybackCommands
            result["timer_callback_isolation"] = commands.map(\.action)==[.stop,.pause] && commands[0].callbackEpoch<commands[1].callbackEpoch
        } else {result["timer_callback_isolation"]=false}
        var videoDescriptor=descriptor
        videoDescriptor.layers.append(.init(id:43,layerIndex:1,name:"video",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[],contentKind:"image",sizeWH:[100,100]))
        let videoDomain=try SceneScriptQuickJSDomain();try videoDomain.configureLayerCatalog(videoDescriptor)
        func publishVideo(_ generation:UInt64) throws {
            try videoDomain.publishLayerSnapshot(.empty(frameIndex:generation),descriptor:videoDescriptor,
                videoSnapshots:[43:.init(layerID:43,duration:10,rate:1,loop:false,currentTime:10,isPlaying:false,endedGeneration:generation)],
                particlePlaybackObservations:observations)
        }
        try publishVideo(0)
        let ended=try owner(videoDomain,"""
            export function init(v){let video=thisScene.getLayerByID(43).getVideoTexture();
              video.addEndedCallback(()=>{thisLayer.stop();Promise.resolve().then(()=>{if(thisLayer.isPlaying())throw Error('ended microtask');});});
              video.addEndedCallback(()=>{if(!thisLayer.isPlaying())throw Error('ended isolation');thisLayer.pause();});return v;}
            export function update(v){if(!thisLayer.isPlaying())throw Error('ended update isolation');return v;}
            """)
        _ = try evaluate(ended);ended.commitLayerMutations();try publishVideo(1)
        if let fired=try? evaluate(ended) {
            let commands=fired.particlePlaybackCommands
            result["ended_callback_isolation"] = commands.map(\.action)==[.stop,.pause] && commands[0].callbackEpoch<commands[1].callbackEpoch
        } else {result["ended_callback_isolation"]=false}
        let endedOverflow=try owner(videoDomain,"""
            export function init(v){thisScene.getLayerByID(43).getVideoTexture().addEndedCallback(()=>{for(let n=0;n<65;n++)thisLayer.pause();});return v;}
            export function update(v){return v;}
            """)
        _ = try evaluate(endedOverflow);endedOverflow.commitLayerMutations();try publishVideo(2)
        do {_ = try evaluate(endedOverflow);result["ended_uncaught_overflow_classification"]=false}
        catch let failure as SceneScriptScalarRuntimeFailure {
            if case .mutationOverflow = failure {result["ended_uncaught_overflow_classification"] = mwx_scene_quickjs_owner_particle_playback_command_count(endedOverflow.handle)==0}
            else {result["ended_uncaught_overflow_classification"]=false}
        }
        var budgetDescriptor=descriptor
        for id in 100..<356 { budgetDescriptor.layers.append(.init(id:id,layerIndex:id-99,name:"budget\(id)",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[],contentKind:"image",sizeWH:[10,10])) }
        let budgetDomain=try SceneScriptQuickJSDomain();try budgetDomain.configureLayerCatalog(budgetDescriptor)
        try budgetDomain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:budgetDescriptor,particlePlaybackObservations:[42:zero.playbackObservation!])
        let budgetState=SceneScriptDynamicLayerRuntime(descriptor:budgetDescriptor,authoredMutationLayerIDs:Set(100..<356))
        for size in [255,256] {
            let mixed=try owner(budgetDomain,"export function update(v){for(let n=100;n<100+v;n++)thisScene.getLayer('budget'+n).origin=new Vec3(1,2,3);thisLayer.pause();return v;}")
            let mixedEvaluation=try evaluate(mixed,Double(size))
            var cursorBundle=effects(mixed,mixedEvaluation);cursorBundle.particlePlaybackCommands=[]
            var updateBundle=effects(mixed,mixedEvaluation);updateBundle.layerMutations=[]
            let admission=budgetState.preflightOwnerEffects([cursorBundle,updateBundle],particleObservations:[42:zero.playbackObservation!])
            result[size==255 ? "split_owner_budget_boundary":"split_owner_budget_overflow"] = size==255
                ? admission.rejectedOwners.isEmpty && admission.layerPlan.particleTransitions.count==1 && mixedEvaluation.layerMutations.count==255
                : !admission.rejectedOwners.isEmpty && admission.admittedEffects.isEmpty && mixedEvaluation.layerMutations.count==256
            mixed.discardLayerMutations()
        }
        print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class ParticlePlaybackTransactionTests(unittest.TestCase):
    def test_real_author_admission_and_simulation(self):
        with tempfile.TemporaryDirectory(prefix="mwx-rf03-transaction-") as raw:
            # Replace only the existing VM fixture's particle-value stand-ins
            # with the actual definitions used by the real simulator.
            start=SWIFT_PREAMBLE.index("enum SceneParticleNumericValue:")
            end=SWIFT_PREAMBLE.index("struct SceneRenderDescriptor",start)
            preamble=SWIFT_PREAMBLE[:start]+SWIFT_PREAMBLE[end:]
            source=(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift").read_text()
            projection=source[source.index("extension SceneDesktopWallpaperSession {\n    func particlePlaybackObservations("):]
            harness=HARNESS.replace("// PRODUCTION_SESSION_PROJECTION",projection)
            binary=compile_vector_harness(Path(raw),harness,"particle-transaction",
                extra_swift_sources=tuple(PARTICLE_SOURCES),preamble=preamble)
            run=subprocess.run([str(binary)],capture_output=True,text=True,timeout=20)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            result=json.loads(run.stdout.strip().splitlines()[-1])
            self.assertTrue(result)
            for name,value in result.items():
                with self.subTest(name=name):self.assertTrue(value,run.stdout+run.stderr)

if __name__ == "__main__":unittest.main()
