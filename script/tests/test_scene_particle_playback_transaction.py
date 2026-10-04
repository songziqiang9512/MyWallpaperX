"""RF03 real QuickJS -> Swift owner admission -> two real simulators."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from .scene_vector_vm_test_support import compile_vector_harness, SWIFT_PREAMBLE, ROOT
from .test_scene_particle_simulator import SWIFT_SOURCES as PARTICLE_SOURCES

HARNESS = r'''
import simd
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
        func simulator(_ initial:SceneParticlePlaybackSnapshot = .init(), start:Double = 0.5,
                       rate:Double = 4) throws -> SceneParticleSimulator {
            let root:[String:Any] = ["material":"p.json","maxcount":100,"starttime":start,
                "emitter":[["name":"boxrandom","rate":rate,"duration":1,"distancemax":2]],
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
        do {
            let emitDomain=try SceneScriptQuickJSDomain();try emitDomain.configureLayerCatalog(descriptor)
            let emitSim=try simulator(start:0), secondSim=try simulator(start:0)
            let tx=SceneParticlePlaybackTransaction(instances:[
                .init(surfaceID:1,layerID:42,simulator:emitSim),
                .init(surfaceID:2,layerID:42,simulator:secondSim)], surfaceIDs:[1,2],
                charge:{try emitDomain.chargeParticleWork($0,bytes:$1)},
                release:{emitDomain.releaseParticleStorage($0)},isCurrent:{true},
                totalLiveCount:{emitSim.particles.count+secondSim.particles.count})
            emitDomain.beginParticlePlaybackFrame(onBoundary:{native,discarded in
                tx.callbackBoundary(owner:UInt(bitPattern:native),discardOwner:discarded)
            }) { native, raw in
                var prefix=try SceneScriptParticlePlaybackCommandBridge.commands(owner:native).get()
                    .filter{$0.callbackEpoch==raw.callback_epoch}.map {
                        SceneParticlePlaybackTransition(layerID:$0.layerID,action:$0.action,revision:0,
                            count:$0.count,callbackEpoch:$0.callbackEpoch,ordinal:$0.ordinal)
                    }
                prefix.append(.init(layerID:Int(raw.layer_id),action:.emit,revision:0,count:Int(raw.count),
                    callbackEpoch:raw.callback_epoch,ordinal:raw.ordinal))
                return try tx.preview(owner:UInt(bitPattern:native),prefix:prefix){_ in .init()}
            }
            try emitDomain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor,particlePlaybackObservations:[42:emitSim.playbackObservation!])
            let emitAuthor=try owner(emitDomain,"export function update(v){thisLayer.stop();thisLayer.emitParticles(3);if(!thisLayer.isPlaying())throw Error('real emit query');return v;}")
            do {
                let evaluated=try evaluate(emitAuthor)
                let state=SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
                let admitted=state.preflightOwnerEffectsToFixedPoint([effects(emitAuthor,evaluated)],
                    particleObservations:[42:emitSim.playbackObservation!],validateParticleTransitions:{_ in true},
                    rejectingParticleTransitions:{ commands,bundles,_ in
                        guard let failed=tx.prepare(commands) else{return []}
                        return Set(bundles.filter{$0.particlePlaybackCommands.contains{$0.callbackEpoch==failed.callbackEpoch && $0.ordinal==failed.ordinal}}.map(\.ownerTarget))
                    }){_ in []}
                tx.install()
            result["explicit_emit_actual_query"] = admitted.externallyRejectedOwners.isEmpty
                    && emitSim.particles.count==3 && secondSim.particles.count==3
                    && emitSim.playback.intent == .stopped && emitSim.frameSnapshot().nextParticleID==3
                let ids=emitSim.particles.map(\.id)
                emitSim.advance(by:0.25);secondSim.advance(by:0.25)
                result["explicit_emit_real_events_after_advance"] = emitSim.consumeBirthEvents().map(\.id)==ids
                    && emitSim.consumeBirthEvents().isEmpty && emitSim.particles.count==3
                    && emitSim.particles[0].age==0.25
            } catch {result["explicit_emit_actual_query"]=false}
            tx.discard()
            result["explicit_emit_native_storage_released"] = mwx_scene_quickjs_domain_particle_reserved(emitDomain.handle)==0
            result["explicit_emit_native_work_charged"] = mwx_scene_quickjs_domain_particle_work(emitDomain.handle)<emitDomain.budget.interruptBudget
            emitDomain.endParticlePlaybackFrame()
        }
        for order in ["before", "after"] {
            for failsPreparation in [false, true] {
                var hiddenDescriptor = descriptor
                hiddenDescriptor.layers[0].visible = false
                let d = try SceneScriptQuickJSDomain(); try d.configureLayerCatalog(hiddenDescriptor)
                let a = try simulator(start: 0, rate: 0), b = try simulator(start: 0, rate: 0)
                var current = true
                var installedVisibility: [UInt32: SceneParticlePlaybackVisibility] = [:]
                var installedSurfaces: [UInt32] = []
                let tx = SceneParticlePlaybackTransaction(instances: [a, b].enumerated().map { index, sim in
                    SceneParticlePlaybackTransaction.Instance(surfaceID: UInt32(index + 1), layerID: 42, simulator: sim,
                        visibility: .init(isVisible: false, resetsPopulation: true),
                        install: { state, visibility in
                            sim.restoreFrame(state)
                            installedSurfaces.append(UInt32(index + 1))
                            installedVisibility[UInt32(index + 1)] = visibility
                        })
                }, surfaceIDs: [1, 2], charge: { try d.chargeParticleWork($0, bytes: $1) },
                   release: { d.releaseParticleStorage($0) }, isCurrent: { current },
                   totalLiveCount: { a.particles.count + b.particles.count })
                func beginPlaybackFrame() {
                    d.beginParticlePlaybackFrame(onBoundary: { native, discarded in
                        tx.callbackBoundary(owner: UInt(bitPattern: native), discardOwner: discarded)
                    }) { native, raw in
                        var prefix = try SceneScriptParticlePlaybackCommandBridge.commands(owner: native).get()
                            .filter { $0.callbackEpoch == raw.callback_epoch }.map {
                                SceneParticlePlaybackTransition(layerID: $0.layerID, action: $0.action, revision: 0,
                                    count: $0.count, callbackEpoch: $0.callbackEpoch, ordinal: $0.ordinal)
                            }
                        prefix.append(.init(layerID: Int(raw.layer_id), action: .emit, revision: 0,
                            count: Int(raw.count), callbackEpoch: raw.callback_epoch, ordinal: raw.ordinal))
                        return try tx.preview(owner: UInt(bitPattern: native), prefix: prefix) { _ in .init() }
                    }
                }
                let key = "same-frame-\(order)-\(failsPreparation ? "failed" : "accepted")"
                let runtime = SceneScriptDynamicLayerRuntime(descriptor: hiddenDescriptor, authoredMutationLayerIDs: [])
                // Seed both real owners through the prior committed callback;
                // simulator and Runtime revisions must describe the same emit.
                beginPlaybackFrame()
                try d.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: hiddenDescriptor,
                    particlePlaybackObservations: [42: a.playbackObservation!])
                let seedAuthor = try owner(d, "export function update(v){thisLayer.emitParticles(2);return v;}")
                let seedValue = try evaluate(seedAuthor)
                let seed = runtime.preflightOwnerEffects([effects(seedAuthor, seedValue)],
                    particleObservations: [42: a.playbackObservation!])
                let seedPrepared = tx.prepare(seed.layerPlan.particleTransitions) == nil
                if seedPrepared && !seed.layerPlan.particleTransitions.isEmpty {
                    tx.install(); runtime.commit(seed.layerPlan); seedAuthor.commitLayerMutations()
                }
                result[key + "-prior-hidden-emit-commits-through-real-owner"] = seed.rejectedOwners.isEmpty
                    && seedPrepared && [a, b].allSatisfy { $0.particles.map(\.id) == [0, 1] && $0.playback.revision == 1 }
                    && runtime.snapshot().particlePlayback[42]?.revision == 1
                tx.discard(); d.endParticlePlaybackFrame()
                let before = [a.frameSnapshot(), b.frameSnapshot()]
                installedVisibility.removeAll(); installedSurfaces.removeAll()
                beginPlaybackFrame()
                try d.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: hiddenDescriptor,
                    particlePlaybackObservations: [42: a.playbackObservation!])
                let commands = order == "before" ? "thisLayer.emitParticles(3);thisLayer.visible=true;"
                    : "thisLayer.visible=true;thisLayer.emitParticles(3);"
                let author = try owner(d, "export function update(v){\(commands)return v;}")
                let evaluated = try evaluate(author)
                result[key + "-preview-restores-real-committed-state"] = zip([a, b], before).allSatisfy { sim, old in
                    sim.particles == old.particles && sim.playback == old.playback
                        && sim.frameSnapshot().random.state == old.random.state
                        && sim.frameSnapshot().nextParticleID == old.nextParticleID
                } && installedVisibility.isEmpty && installedSurfaces.isEmpty
                current = !failsPreparation
                let admitted = runtime.preflightOwnerEffectsToFixedPoint([effects(author, evaluated)],
                    particleObservations: [42: a.playbackObservation!], validateParticleTransitions: { _ in true },
                    rejectingParticleTransitions: { transitions, bundles, _ in
                        let candidate = runtime.preflightOwnerEffects(bundles,
                            particleObservations: [42: a.playbackObservation!]).layerPlan
                        guard case let .bool(visible)? = candidate.authoredLayerValues[
                            .layer(layerID: 42, field: .visibility)] else { return Set(bundles.map(\.ownerTarget)) }
                        guard let failed = tx.prepare(transitions, visibility: { _ in
                            .init(isVisible: visible, resetsPopulation: true)
                        }) else { return [] }
                        return Set(bundles.filter { $0.particlePlaybackCommands.contains {
                            $0.callbackEpoch == failed.callbackEpoch && $0.ordinal == failed.ordinal
                        }}.map(\.ownerTarget))
                    }) { _ in [] }
                if failsPreparation {
                    result[key + "-rejects-whole-owner-without-install"] = admitted.externallyRejectedOwners == [author.target]
                        && admitted.admission.layerPlan.particleTransitions.isEmpty
                        && admitted.admission.layerPlan.authoredLayerValues.isEmpty && installedVisibility.isEmpty
                        && installedSurfaces.isEmpty
                        && zip([a, b], before).allSatisfy { sim, old in
                            sim.particles == old.particles && sim.playback == old.playback
                                && sim.frameSnapshot().random.state == old.random.state
                                && sim.frameSnapshot().nextParticleID == old.nextParticleID
                        }
                } else {
                    tx.install()
                    result[key + "-reset-before-replay-and-visibility-install"] = admitted.externallyRejectedOwners.isEmpty
                        && installedVisibility.count == 2
                        && installedSurfaces.sorted() == [1, 2]
                        && installedVisibility.values.allSatisfy { $0.isVisible && $0.resetsPopulation }
                        && [a, b].allSatisfy { $0.particles.map(\.id) == [2, 3, 4] && $0.playback.revision == 2 }
                    a.advance(by: 0.25); b.advance(by: 0.25)
                    result[key + "-new-births-survive-next-advance"] = [a, b].allSatisfy {
                        $0.particles.map(\.id) == [2, 3, 4] && $0.particles.allSatisfy { $0.age == 0.25 }
                    }
                }
                let installedIDs = installedVisibility.keys.sorted()
                let liveIDs = [a, b].map { $0.particles.map(\.id) }
                let trace: [String] = ["fixture visibility transaction \(key):",
                    "seedRejected=\(seed.rejectedOwners.count)",
                    "internalRejected=\(admitted.admission.rejectedOwners.count)",
                    "externalRejected=\(admitted.externallyRejectedOwners.count)",
                    "transitions=\(admitted.admission.layerPlan.particleTransitions.count)",
                    "ids=\(liveIDs) installed=\(installedIDs)"]
                FileHandle.standardError.write(Data((trace.joined(separator: " ") + "\n").utf8))
                tx.discard()
                result[key + "-all-native-storage-released"] = mwx_scene_quickjs_domain_particle_reserved(d.handle) == 0
                d.endParticlePlaybackFrame()
            }
        }
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
        func emissionScope(_ sims:[SceneParticleSimulator], background:[SceneParticleSimulator] = [],
            context:@escaping (OpaquePointer,SceneParticlePlaybackTransaction.Instance)throws->SceneParticleSimulator.EmissionContext = {_,_ in .init()}) throws
            -> (SceneScriptQuickJSDomain,SceneParticlePlaybackTransaction) {
            let d=try SceneScriptQuickJSDomain();try d.configureLayerCatalog(descriptor)
            let instances=sims.enumerated().map {SceneParticlePlaybackTransaction.Instance(surfaceID:UInt32($0.offset+1),layerID:42,simulator:$0.element)}
            let tx=SceneParticlePlaybackTransaction(instances:instances,surfaceIDs:Set(instances.map(\.surfaceID)),
                charge:{try d.chargeParticleWork($0,bytes:$1)},release:{d.releaseParticleStorage($0)},
                isCurrent:{true},totalLiveCount:{try d.chargeParticleWork(UInt64(sims.count+background.count),bytes:0);return (sims+background).reduce(0){$0+$1.particles.count}})
            d.beginParticlePlaybackFrame(onBoundary:{o,discarded in tx.callbackBoundary(owner:UInt(bitPattern:o),discardOwner:discarded)}) {o,raw in
                var prefix=try SceneScriptParticlePlaybackCommandBridge.commands(owner:o).get().filter{$0.callbackEpoch==raw.callback_epoch}.map{
                    SceneParticlePlaybackTransition(layerID:$0.layerID,action:$0.action,revision:0,count:$0.count,callbackEpoch:$0.callbackEpoch,ordinal:$0.ordinal)}
                prefix.append(.init(layerID:Int(raw.layer_id),action:.emit,revision:0,count:Int(raw.count),callbackEpoch:raw.callback_epoch,ordinal:raw.ordinal))
                return try tx.preview(owner:UInt(bitPattern:o),prefix:prefix){try context(o,$0)}
            }
            try d.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor,particlePlaybackObservations:[42:sims[0].playbackObservation!])
            return (d,tx)
        }
        func prepareEmission(_ state:SceneScriptDynamicLayerRuntime,_ tx:SceneParticlePlaybackTransaction,
            _ bundles:[SceneScriptOwnerEffects],_ sim:SceneParticleSimulator, rejected:Set<SceneDynamicTarget> = []) -> SceneScriptOwnerEffectsFixedPointAdmission {
            state.preflightOwnerEffectsToFixedPoint(bundles,excludingOwners:rejected,
                particleObservations:[42:sim.playbackObservation!],validateParticleTransitions:{_ in true},
                rejectingParticleTransitions:{commands,admitted,_ in
                    guard let failed=tx.prepare(commands) else{return []}
                    return Set(admitted.filter{$0.particlePlaybackCommands.contains{$0.callbackEpoch==failed.callbackEpoch && $0.ordinal==failed.ordinal}}.map(\.ownerTarget))
                }){_ in []}
        }
        for argument in ["", "-1", "1.5", "NaN", "Infinity", "'2'", "true", "null", "1,2", "1025"] {
            let sim=try simulator(start:0)
            let (d,tx)=try emissionScope([sim])
            let author=try owner(d,"export function update(v){let rejected=false;try{thisLayer.emitParticles(\(argument));}catch(e){rejected=true;}if(!rejected)throw Error('accepted invalid');return v;}")
            result["explicit-invalid-"+argument] = (try? evaluate(author)) != nil && sim.particles.isEmpty && sim.frameSnapshot().nextParticleID==0
            tx.discard();result["explicit-invalid-bytes-"+argument] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }
        do {
            let sim=try simulator(start:0)
            let (d,tx)=try emissionScope([sim])
            let author=try owner(d,"export function update(v){thisLayer.pause();try{thisLayer.emitParticles(101);}catch(e){}return v;}")
            do {_=try evaluate(author);result["caught-capacity-rejects-whole-owner"]=false}
            catch {result["caught-capacity-rejects-whole-owner"] = sim.particles.isEmpty && sim.playback.intent == .playing
                && mwx_scene_quickjs_owner_particle_playback_command_count(author.handle)==0}
            tx.discard();result["caught-capacity-storage-released"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }
        var queryWork:[UInt64]=[]
        for queries in [0,100] {
            let sim=try simulator(start:0)
            let (d,tx)=try emissionScope([sim])
            let author=try owner(d,"export function update(v){thisLayer.emitParticles(2);for(let i=0;i<\(queries);i++){if(!thisLayer.isPlaying())throw Error('query');}return v;}")
            let evaluated=try evaluate(author)
            queryWork.append(mwx_scene_quickjs_domain_particle_work(d.handle))
            let plan=prepareEmission(SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[]),tx,[effects(author,evaluated)],sim)
            tx.install()
            result["query-no-rebirth-\(queries)"] = plan.externallyRejectedOwners.isEmpty && sim.particles.map(\.id)==[0,1]
            tx.discard();d.endParticlePlaybackFrame()
        }
        result["query-constant-cost-not-prefix-replay"] = queryWork[0]-queryWork[1]==100
        for mode in ["throw","work","bytes"] {
            let sim=try simulator(start:0)
            let before=sim.frameSnapshot()
            let (d,tx)=try emissionScope([sim])
            let author=try owner(d,mode=="throw"
                ? "export function update(v){thisLayer.emitParticles(3);throw Error('late');}"
                : "export function update(v){try{thisLayer.emitParticles(3);}catch(e){}return v;}")
            let held=mode=="bytes" ? d.budget.maximumNativeTransientBytes-64:0
            if mode=="work" {try d.chargeParticleWork(d.budget.interruptBudget-1,bytes:0)}
            if held>0 {try d.chargeParticleWork(0,bytes:held)}
            do {_=try evaluate(author);result["explicit-unsafe-or-throw-"+mode]=false}
            catch {result["explicit-unsafe-or-throw-"+mode] = sim.particles.isEmpty && sim.frameSnapshot().random.state==before.random.state
                && sim.frameSnapshot().nextParticleID==before.nextParticleID && sim.birthEvents.isEmpty
                && mwx_scene_quickjs_owner_particle_playback_command_count(author.handle)==0}
            if held>0 {d.releaseParticleStorage(held)}
            tx.discard();result["explicit-reject-storage-"+mode] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }
        do {
            let sim=try simulator(start:0)
            let (d,tx)=try emissionScope([sim])
            try d.chargeParticleWork(99_999,bytes:0)
            try d.chargeParticleWork(1,bytes:0)
            result["native-work-exact-boundary"] = mwx_scene_quickjs_domain_particle_work(d.handle)==0
            do {try d.chargeParticleWork(1,bytes:0);result["native-work-over-one"]=false}
            catch {result["native-work-over-one"]=true}
            tx.discard();d.endParticlePlaybackFrame()
        }
        do {
            let sim=try simulator(start:0)
            let (d,tx)=try emissionScope([sim])
            let first=try owner(d,"export function update(v){thisLayer.emitParticles(80);return v;}")
            let second=try owner(d,"export function update(v){thisLayer.emitParticles(30);return v;}",.particle(layerID:42,field:.size))
            let a=try evaluate(first),b=try evaluate(second)
            let state=SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
            let admitted=prepareEmission(state,tx,[effects(first,a),effects(second,b)],sim)
            tx.install()
            result["capacity-conflict-only-failing-owner"] = admitted.externallyRejectedOwners==[second.target]
                && sim.particles.count==80 && sim.frameSnapshot().nextParticleID==80
            tx.discard();result["capacity-conflict-storage-released"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }
        do {
            let sim=try simulator(start:0)
            let (d,tx)=try emissionScope([sim])
            let first=try owner(d,"export function update(v){thisLayer.emitParticles(7);return v;}")
            let second=try owner(d,"export function update(v){thisLayer.emitParticles(3);return v;}",.particle(layerID:42,field:.size))
            let a=try evaluate(first),b=try evaluate(second)
            let admitted=prepareEmission(SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[]),tx,
                [effects(first,a),effects(second,b)],sim,rejected:[first.target])
            let reference=try simulator(start:0)
            let prepared=try reference.preparePlaybackCandidate(commands:[(.init(layerID:42,action:.emit,revision:1,count:3),.init())],charge:{_,_ in},release:{_ in})
            tx.install()
            result["late-owner-removal-recomputes-id-rng"] = admitted.externallyRejectedOwners==[first.target]
                && sim.particles==prepared.state.particles && sim.frameSnapshot().random.state==prepared.state.random.state
            tx.discard();d.endParticlePlaybackFrame()
        }
        do {
            let a=try simulator(.init(intent:.stopped),start:0),b=try simulator(.init(intent:.stopped),start:0)
            let filled=try b.preparePlaybackCandidate(commands:[(.init(layerID:42,action:.emit,revision:1,count:99),.init())],charge:{_,_ in},release:{_ in})
            b.restoreFrame(filled.state)
            let beforeA=a.frameSnapshot(),beforeB=b.frameSnapshot()
            let (d,tx)=try emissionScope([a,b])
            let author=try owner(d,"export function update(v){thisLayer.emitParticles(2);return v;}")
            do {_=try evaluate(author);result["surface-second-capacity-no-partial"]=false}
            catch {result["surface-second-capacity-no-partial"] = a.particles==beforeA.particles && b.particles==beforeB.particles
                && a.frameSnapshot().random.state==beforeA.random.state && b.frameSnapshot().random.state==beforeB.random.state}
            tx.discard();result["surface-failure-native-release"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }

        do {
            let sim=try simulator(start:0)
            var checks:Int32=0
            let cancelled:MWXSceneQuickJSCancellationCheck = {opaque in
                guard let opaque else{return 0}
                let p=opaque.assumingMemoryBound(to:Int32.self);p.pointee += 1
                return p.pointee>=5 ? 1:0
            }
            var activeDomain:SceneScriptQuickJSDomain?
            try withUnsafeMutablePointer(to:&checks) {pointer in
                let (d,tx)=try emissionScope([sim],context:{_,_ in
                    mwx_scene_quickjs_domain_set_cancellation_check(activeDomain!.handle,cancelled,UnsafeMutableRawPointer(pointer));return .init()
                });activeDomain=d
                let author=try owner(d,"export function update(v){try{thisLayer.emitParticles(10);}catch(e){}return v;}")
                let before=sim.frameSnapshot()
                do {_=try evaluate(author);result["native-cancel-during-real-birth"]=false}
                catch {result["native-cancel-during-real-birth"] = sim.particles==before.particles
                    && sim.frameSnapshot().random.state==before.random.state && sim.frameSnapshot().nextParticleID==before.nextParticleID}
                mwx_scene_quickjs_domain_set_cancellation_check(d.handle,nil,nil)
                tx.discard();result["native-cancel-storage-released"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0
                d.endParticlePlaybackFrame();activeDomain=nil
            }
            result["native-cancel-actual-checks"] = checks>=5
        }
        do {
            let sim=try simulator(start:0)
            let (d,tx)=try emissionScope([sim])
            let timers=try owner(d,"""
                export function init(v){
                    engine.setTimeout(()=>{thisLayer.emitParticles(2);},10);
                    engine.setTimeout(()=>{thisLayer.emitParticles(2);},10);return v;}
                export function update(v){return v;}
                """)
            _=try evaluate(timers);timers.commitLayerMutations()
            let before=mwx_scene_quickjs_domain_particle_work(d.handle)
            let later=SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.25,sceneTime:2))
            let fired=try timers.evaluate(input:.scalar(1),frame:later,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
            let after=mwx_scene_quickjs_domain_particle_work(d.handle)
            let admitted=prepareEmission(SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[]),tx,[effects(timers,fired)],sim)
            tx.install()
            result["native-timers-one-cadence-accumulates"] = fired.particlePlaybackCommands.count==2 && after<before
                && admitted.externallyRejectedOwners.isEmpty && sim.particles.map(\.id)==[0,1,2,3]
            tx.discard();d.endParticlePlaybackFrame()
        }
        do {
            let a=try simulator(start:0),b=try simulator(start:0)
            var valid=true
            let d=try SceneScriptQuickJSDomain()
            let tx=SceneParticlePlaybackTransaction(instances:[.init(surfaceID:1,layerID:42,simulator:a),.init(surfaceID:2,layerID:42,simulator:b)],surfaceIDs:[1,2],
                charge:{try d.chargeParticleWork($0,bytes:$1)},release:{d.releaseParticleStorage($0)},isCurrent:{valid},totalLiveCount:{a.particles.count+b.particles.count})
            d.beginParticlePlaybackFrame(onBoundary:{_,_ in}){_,_ in throw SceneParticleEmissionFailure.unavailable}
            let transition=SceneParticlePlaybackTransition(layerID:42,action:.emit,revision:1,count:2,callbackEpoch:1,ordinal:0)
            _=try tx.preview(owner:1,prefix:[transition]){_ in .init()}
            valid=false
            result["all-surface-invalidated-before-final-admission"] = tx.prepare([transition]) != nil && a.particles.isEmpty && b.particles.isEmpty
            tx.discard();result["all-surface-invalidated-storage-release"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }
        do {
            let root:[String:Any] = ["material":"p.json","maxcount":8,"flags":1,
                "emitter":[["name":"boxrandom","rate":0]],
                "initializer":[["name":"lifetimerandom","min":10,"max":10],["name":"velocityrandom","min":"80 0 0","max":"80 0 0"]],
                "operator":[["name":"movement","flags":1,"gravity":"0 0 0"]],"renderer":[["name":"sprite"]]]
            let sim=SceneParticleSimulator(definition:try SceneParticleDefinitionParser().parse(root:root),
                worldSpaceFrame:SceneParticleWorldSpaceFrame(worldFrame:matrix_identity_float4x4))
            let index=SceneDynamicSnapshotResolver.prepare(definitions:[.init(target:.layer(layerID:42,field:.angles),valueType:.vector3,authoredValue:.vector3(0,0,0))])
            let projection=SceneScriptLayerWorldTransformProjection(descriptor:descriptor,catalogSignature:"fixture")!
            var captured:[SIMD3<Double>]=[]
            let (d,tx)=try emissionScope([sim],context:{native,instance in
                var origin=[Double](repeating:0,count:3),scale=[Double](repeating:0,count:3),angles=[Double](repeating:0,count:3)
                guard mwx_scene_quickjs_owner_particle_transform(native,42,&origin,&scale,&angles)==MWX_SCENE_QUICKJS_OK else {throw SceneScriptScalarRuntimeFailure.staleOwner}
                captured.append(.init(angles[0],angles[1],angles[2]))
                let snapshot=SceneDynamicSnapshotResolver().resolve(frameIndex:0,generation:0,index:index,
                    sceneScriptValues:[.layer(layerID:42,field:.angles):.vector3(0,0,SceneScriptAngleUnits.radians(fromDegrees:angles[2]))]).snapshot
                let frame=projection.worldFrames(for:snapshot)[42]!
                return .init(worldFrame:SceneParticleWorldSpaceFrame(worldFrame:frame))
            })
            let author=try owner(d,"export function update(v){thisLayer.angles=new Vec3(0,0,0);thisLayer.emitParticles(1);thisLayer.angles=new Vec3(0,0,90);thisLayer.emitParticles(1);return v;}")
            let evaluated=try evaluate(author)
            let admitted=prepareEmission(SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[42]),tx,[effects(author,evaluated)],sim)
            tx.install()
            result["actual-transform-setter-prefix-world-birth"] = admitted.externallyRejectedOwners.isEmpty
                && captured==[SIMD3(0,0,0),SIMD3(0,0,90)] && sim.particles.count==2
                && abs(sim.particles[0].velocity.x-80)<0.01 && abs(sim.particles[1].velocity.x)<0.01
                && abs(abs(sim.particles[1].velocity.y)-80)<0.01
            tx.discard();result["transform-prefix-native-storage-release"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }

        for count in [64,65] {
            let sim=try simulator(start:0), before=sim.frameSnapshot()
            let (d,tx)=try emissionScope([sim])
            let author=try owner(d,"export function update(v){try{for(let n=0;n<\(count);n++)thisLayer.emitParticles(0);}catch(e){}return v;}")
            do {
                let evaluation=try evaluate(author)
                result["zero-command-quota-\(count)"] = count==64 && evaluation.particlePlaybackCommands.count==64
                    && sim.particles.isEmpty && sim.frameSnapshot().random.state==before.random.state && sim.frameSnapshot().nextParticleID==0
            } catch {result["zero-command-quota-\(count)"] = count==65 && mwx_scene_quickjs_owner_particle_playback_command_count(author.handle)==0}
            tx.discard();result["zero-native-release-\(count)"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }
        do {
            let sim=try simulator(start:0), old=sim.frameSnapshot()
            sim.restoreFrame(.init(playback:old.playback,particles:old.particles,diagnostics:old.diagnostics,
                transientRenderBirths:old.transientRenderBirths,birthEvents:old.birthEvents,deathEvents:old.deathEvents,
                simulationTime:old.simulationTime,activeInstanceOverride:old.activeInstanceOverride,activeWorldSpaceFrame:old.activeWorldSpaceFrame,
                explicitBirthEventStart:old.explicitBirthEventStart,emitters:old.emitters,random:old.random,accumulator:old.accumulator,
                nextParticleID:UInt64.max,normalizedLives:old.normalizedLives,dynamicControlPoints:old.dynamicControlPoints,
                dynamicControlPointAngles:old.dynamicControlPointAngles,audioInput:old.audioInput,
                observedNonSilentAudioComponents:old.observedNonSilentAudioComponents,pendingAudioEvaluationObservations:old.pendingAudioEvaluationObservations,
                eventColorContext:old.eventColorContext,stepSnapshotRecorder:old.stepSnapshotRecorder,
                positionOscillationCache:old.positionOscillationCache))
            let (d,tx)=try emissionScope([sim])
            let author=try owner(d,"export function update(v){thisLayer.pause();try{thisLayer.emitParticles(1);}catch(e){}return v;}")
            do {_=try evaluate(author);result["caught-id-overflow-rejects-owner"]=false}
            catch {result["caught-id-overflow-rejects-owner"] = sim.frameSnapshot().nextParticleID==UInt64.max
                && sim.particles.isEmpty && sim.playback.intent == .playing && sim.frameSnapshot().random.state==old.random.state
                && mwx_scene_quickjs_owner_particle_playback_command_count(author.handle)==0}
            tx.discard();result["id-overflow-native-release"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }
        for baseline in [65_534,65_535] {
            var background:[SceneParticleSimulator]=[]
            var remaining=baseline
            while remaining>0 {
                let count=min(20_000,remaining);remaining-=count
                let root:[String:Any] = ["material":"p.json","maxcount":count,
                    "emitter":[["name":"boxrandom","instantaneous":count,"rate":0]],
                    "initializer":[["name":"lifetimerandom","min":10,"max":10]],"renderer":[["name":"sprite"]]]
                let sim=SceneParticleSimulator(definition:SceneParticleDefinitionParser().parse(root:root))
                sim.advance(by:0.02);background.append(sim)
            }
            let a=try simulator(start:0),b=try simulator(start:0)
            let (d,tx)=try emissionScope([a,b],background:background)
            let author=try owner(d,"export function update(v){thisLayer.pause();try{thisLayer.emitParticles(1);}catch(e){}return v;}")
            let actualBaseline=background.reduce(0){$0+$1.particles.count}
            FileHandle.standardError.write(Data("background \(baseline): \(background.map{ $0.particles.count })\n".utf8))
            result["actual-background-count-\(baseline)"] = actualBaseline==baseline
            do {
                let evaluated=try evaluate(author)
                let plan=prepareEmission(SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[]),tx,[effects(author,evaluated)],a)
                tx.install()
                result["actual-scene-live-\(baseline)"] = baseline==65_534 && actualBaseline==baseline
                    && plan.externallyRejectedOwners.isEmpty && a.particles.count==1 && b.particles.count==1
                    && actualBaseline+a.particles.count+b.particles.count==65_536
            } catch {
                result["actual-scene-live-\(baseline)"] = baseline==65_535 && actualBaseline==baseline
                    && a.particles.isEmpty && b.particles.isEmpty && a.playback.intent == .playing && b.playback.intent == .playing
                    && mwx_scene_quickjs_owner_particle_playback_command_count(author.handle)==0
            }
            tx.discard();result["scene-live-release-\(baseline)"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
        }
        do {
            var dual=descriptor
            dual.layers.append(.init(id:43,layerIndex:1,name:"other",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[],contentKind:"particle",sizeWH:[100,100]))
            let a=try simulator(start:0),b=try simulator(start:0)
            let d=try SceneScriptQuickJSDomain();try d.configureLayerCatalog(dual)
            let tx=SceneParticlePlaybackTransaction(instances:[.init(surfaceID:1,layerID:42,simulator:a),.init(surfaceID:1,layerID:43,simulator:b)],surfaceIDs:[1],charge:{try d.chargeParticleWork($0,bytes:$1)},release:{d.releaseParticleStorage($0)},isCurrent:{true},totalLiveCount:{a.particles.count+b.particles.count})
            var peak:UInt64=0
            d.beginParticlePlaybackFrame(onBoundary:{o,discarded in tx.callbackBoundary(owner:UInt(bitPattern:o),discardOwner:discarded)}) {o,raw in
                var prefix=try SceneScriptParticlePlaybackCommandBridge.commands(owner:o).get().filter{$0.callbackEpoch==raw.callback_epoch}.map{SceneParticlePlaybackTransition(layerID:$0.layerID,action:$0.action,revision:0,count:$0.count,callbackEpoch:$0.callbackEpoch,ordinal:$0.ordinal)}
                prefix.append(.init(layerID:Int(raw.layer_id),action:.emit,revision:0,count:Int(raw.count),callbackEpoch:raw.callback_epoch,ordinal:raw.ordinal))
                let observation=try tx.preview(owner:UInt(bitPattern:o),prefix:prefix){_ in .init()}
                peak=max(peak,UInt64(mwx_scene_quickjs_domain_particle_reserved(d.handle)));return observation
            }
            try d.publishLayerSnapshot(.empty(frameIndex:0),descriptor:dual,particlePlaybackObservations:[42:a.playbackObservation!,43:b.playbackObservation!])
            let author=try owner(d,"export function update(v){thisLayer.emitParticles(2);thisScene.getLayer('other').emitParticles(2);thisLayer.emitParticles(2);try{thisScene.getLayer('other').emitParticles(101);}catch(e){}return v;}")
            do {_=try evaluate(author);result["cross-layer-prefix-failure-releases-candidates"]=false}
            catch {result["cross-layer-prefix-failure-releases-candidates"] = a.particles.isEmpty && b.particles.isEmpty
                && a.frameSnapshot().nextParticleID==0 && b.frameSnapshot().nextParticleID==0 && peak>0
                && mwx_scene_quickjs_owner_particle_playback_command_count(author.handle)==0}
            tx.discard();result["cross-layer-native-reserved-zero"] = mwx_scene_quickjs_domain_particle_reserved(d.handle)==0;d.endParticlePlaybackFrame()
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
            print(run.stdout + run.stderr)
            result=json.loads(run.stdout.strip().splitlines()[-1])
            self.assertTrue(result)
            for name,value in result.items():
                with self.subTest(name=name):self.assertTrue(value,run.stdout+run.stderr)

if __name__ == "__main__":unittest.main()
