"""Public instance scalars: real QuickJS, typed owner admission and CPU births."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.support.scene_vector_vm_test_support import ROOT, SWIFT_PREAMBLE, compile_vector_harness
from script.tests.scene.test_scene_particle_simulator import SWIFT_SOURCES as PARTICLE_SOURCES

SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
HARNESS = r'''
import simd
@main enum Harness {
    static let origin = SceneDynamicTarget.layer(layerID:42,field:.origin)
    static let alpha = SceneDynamicTarget.particle(layerID:42,field:.alpha)
    static let rate = SceneDynamicTarget.particle(layerID:42,field:.rate)
    static let count = SceneDynamicTarget.particle(layerID:42,field:.count)
    static let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.25,sceneTime:1))
    static func main() throws {
        var results:[String:Bool]=[:]
        let descriptor = SceneRenderDescriptor(layers:[.init(id:42,layerIndex:0,name:"particles",visible:true,
            originXYZ:[0,0,0],scaleXYZ:[1,1,1],alpha:1,effects:[],contentKind:"particle")])
        func sim(_ override:SceneParticleInstanceOverride? = nil, multi:Bool = false) throws -> SceneParticleSimulator {
            let emitter:[String:Any] = ["name":"boxrandom","rate":4,"distancemin":0,"distancemax":0]
            let root:[String:Any] = ["material":"own.json","maxcount":100,"starttime":0,"flags":0,
                "emitter":multi ? [emitter,emitter] : [emitter],
                "initializer":[["name":"lifetimerandom","min":60,"max":60]],"renderer":[["name":"sprite"]]]
            return SceneParticleSimulator(definition:try SceneParticleDefinitionParser().parse(root:root),
                instanceOverride:override,seed:91,fixedTimeStep:0.25)
        }
        func author(_ domain:SceneScriptQuickJSDomain,_ source:String,
                    target:SceneDynamicTarget = origin,valueType:SceneDynamicValueType = .vector3) throws -> SceneScriptValueOwner {
            try .init(domain:domain,source:source,target:target,valueType:valueType,effectNames:[],
                allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        }
        func evaluate(_ owner:SceneScriptValueOwner,_ input:SceneDynamicValue = .vector3(0,0,0)) throws -> SceneScriptValueEvaluation {
            try owner.evaluate(input:input,frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",
                expectedGeneration:1,interruptBudget:nil).get()
        }
        func effects(_ owner:SceneScriptValueOwner,_ value:SceneScriptValueEvaluation) -> SceneScriptOwnerEffects {
            var result = SceneScriptOwnerEffects(ownerTarget:owner.target,materialFunctionMutations:[],
                animationMutations:[],layerMutations:[],mediaPlaybackCommands:[])
            result.append(value);return result
        }
        struct Values {let values:[SceneDynamicTarget:SceneDynamicValue]}
        let sceneScriptStringResult = Values(values:[:]), sceneScriptVectorResult = Values(values:[:])
        let emptyScalarResult = SceneScriptScalarFrameResult(values:[:], failures:[:],
            materialFunctionMutations:[], animationMutations:[], layerMutations:[])
        var sceneScriptResult = emptyScalarResult
        // PRODUCTION_FRAME_SCRIPT_VALUES
        func resolution(_ runtime:SceneScriptDynamicLayerRuntime,_ admitted:[SceneScriptOwnerEffects],
                        plan:SceneScriptLayerMutationPlan? = nil,
                        returned:[SceneDynamicTarget:SceneDynamicValue] = [:]) -> SceneDynamicSnapshot {
            sceneScriptResult = .init(values:returned,failures:[:],materialFunctionMutations:[],
                animationMutations:[],layerMutations:[])
            defer {sceneScriptResult = emptyScalarResult}
            return SceneDynamicSnapshotResolver().resolve(frameIndex:0,generation:1,
                definitions:runtime.authoredLayerDefinitions,
                sceneScriptValues:frameScriptValues(admitted,layerPlan:plan ?? runtime.preflightOwnerEffects(admitted).layerPlan,excluding:[],timelineValues:[:])).snapshot
        }
        func override(_ snapshot:SceneDynamicSnapshot,_ authored:SceneParticleInstanceOverride? = nil) -> SceneParticleInstanceOverride? {
            SceneParticleInstanceOverride.resolving(authored:authored,dynamic:snapshot.particleInstanceValues(layerID:42))
        }
        // A first setter has a launch definition even without authored override or script on alpha.
        do {
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            let initial = resolution(runtime,[])
            try domain.publishLayerSnapshot(initial,descriptor:descriptor,particleInstanceLayerIDs:[42])
            let owner = try author(domain,"export function update(v){if(thisLayer.instance.alpha!==1)throw Error('neutral');thisLayer.instance.alpha=.25;return v;}")
            let simulation = try sim();simulation.advance(by:1)
            let oldIDs = Set(simulation.particles.map(\.id))
            let value = try evaluate(owner)
            let admission = runtime.preflightOwnerEffects([effects(owner,value)])
            let current = resolution(runtime,admission.admittedEffects)
            simulation.advance(by:1,dynamicInstanceOverride:override(current))
            results["first-cadence-neutral-setter"] = admission.rejectedOwners.isEmpty
                && current[alpha]?.value == .scalar(0.25) && current.authoredValue(for:alpha) == .scalar(1)
            results["old-population-keeps-birth-alpha"] = !oldIDs.isEmpty
                && simulation.particles.filter{oldIDs.contains($0.id)}.allSatisfy{$0.alpha==1}
            let fresh = simulation.particles.filter{!oldIDs.contains($0.id)}
            results["subsequent-births-consume-instance-alpha"] = !fresh.isEmpty && fresh.allSatisfy{$0.alpha==0.25}
            runtime.commit(admission.layerPlan);owner.commitLayerMutations()
            let next = SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
                definitions:runtime.authoredLayerDefinitions,sceneScriptValues:runtime.snapshot().authoredLayerValues).snapshot
            try domain.publishLayerSnapshot(next,descriptor:descriptor,particleInstanceLayerIDs:[42])
            let reader = try author(domain,"export function update(v){if(thisScene.getLayer('particles').instance.alpha!==.25)throw Error('committed mirror');return v;}",target:.layer(layerID:42,field:.scale))
            _ = try evaluate(reader)
            results["next-callback-reads-committed-mirror"] = next[alpha]?.value == .scalar(0.25)
        }
        // Return-only, aligned return/setter and another target's setter use the real frame merge.
        for (field,target) in [("rate",rate),("count",count)] {
            for (amount,births) in [(0.0,0),(0.5,2),(1.0,4),(2.0,8)] {
                for mode in ["return-only","aligned","other-target"] {
                    let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
                    let domain = try SceneScriptQuickJSDomain()
                    try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:descriptor,particleInstanceLayerIDs:[42])
                    let scalarOwner = mode != "other-target"
                    let setter = mode == "return-only" ? "" : "thisLayer.instance.\(field)=\(amount);"
                    let source = "export function update(v){\(setter)return \(scalarOwner ? String(amount) : "v");}"
                    let owner = try author(domain,source,target:scalarOwner ? target : origin,
                        valueType:scalarOwner ? .scalar : .vector3)
                    let value = try evaluate(owner,scalarOwner ? .scalar(1) : .vector3(0,0,0))
                    let admission = runtime.preflightOwnerEffects([effects(owner,value)])
                    let current = resolution(runtime,admission.admittedEffects,
                        returned:scalarOwner ? [target:value.value] : [:])
                    let key = "\(field)-\(mode)-\(amount)"
                    results["typed-frame-\(key)"] = admission.rejectedOwners.isEmpty
                        && current[target]?.value == .scalar(amount) && current.authoredValue(for:target) == .scalar(1)
                    let simulation = try sim()
                    simulation.advance(by:1,dynamicInstanceOverride:override(current))
                    let authored = SceneParticleDefinitionParser().parseInstanceOverride([field:amount])!
                    let control = try sim(authored);control.advance(by:1)
                    results["natural-consumer-\(key)"] = simulation.particles.count == births
                        && simulation.particles == control.particles && simulation.simulationTime == control.simulationTime
                        && simulation.simulationTime == (field == "rate" ? amount : 1)
                    let existing = try sim();existing.advance(by:1)
                    let old = existing.particles
                    existing.advance(by:1,dynamicInstanceOverride:override(current))
                    let elapsed = field == "rate" ? amount : 1
                    results["old-population-time-\(key)"] = !old.isEmpty && existing.simulationTime == 1 + elapsed
                        && old.allSatisfy{prior in existing.particles.contains{
                            $0.id == prior.id && $0.age == prior.age + elapsed && $0.alpha == prior.alpha}}
                    if mode != "return-only" {
                        runtime.commit(admission.layerPlan);owner.commitLayerMutations()
                        let next = SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
                            definitions:runtime.authoredLayerDefinitions,
                            sceneScriptValues:runtime.snapshot().authoredLayerValues).snapshot
                        results["committed-mirror-\(key)"] = next[target]?.value == current[target]?.value
                    }
                }
            }
        }
        // Explicit read baselines transport real journals without changing the frozen publication.
        for (field,target) in [("alpha",alpha),("rate",rate),("count",count)] {
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:descriptor,particleInstanceLayerIDs:[42])
            let writer = try author(domain,"export function update(v){thisLayer.instance.\(field)=.5;return v;}")
            let writtenBaseline = try evaluate(writer)
            writer.discardLayerMutations()
            let owner = try author(domain,"export function update(v){if(thisLayer.instance.\(field)!==v)throw Error('baseline');return v;}",
                target:target,valueType:.scalar)
            if let failure = owner.configureAuthoredLayerReadBaselines(writtenBaseline.layerMutations) {throw failure}
            let value = try evaluate(owner,.scalar(0.5))
            owner.clearAuthoredLayerReadBaselines()
            let peer = try author(domain,"export function update(v){if(thisLayer.instance.\(field)!==1)throw Error('baseline leak');return v;}")
            _ = try evaluate(peer)
            results["explicit-read-baseline-restores-publication-\(field)"] = value.value == .scalar(0.5)
                && value.layerMutations.isEmpty
            for amount in [-0.5,2.75] {
                let finite = try author(domain,"export function update(v){thisLayer.instance.\(field)=\(amount);if(thisLayer.instance.\(field)!==\(amount))throw Error('finite');return v;}")
                let written = try evaluate(finite)
                let admission = runtime.preflightOwnerEffects([effects(finite,written)])
                results["finite-number-no-amplitude-license-\(field)-\(amount)"] = admission.rejectedOwners.isEmpty
                    && resolution(runtime,admission.admittedEffects)[target]?.value == .scalar(amount)
                finite.discardLayerMutations()
            }
        }
        for (id,name) in [(42,"particles"),(73,"renamed-particle-resource")] {
            let renamed = SceneRenderDescriptor(layers:[.init(id:id,layerIndex:0,name:name,visible:true,
                originXYZ:[0,0,0],scaleXYZ:[1,1,1],alpha:1,effects:[],contentKind:"particle")])
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:renamed,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:renamed,particleInstanceLayerIDs:[id])
            let owner = try author(domain,"let h;let n=0;export function update(v){if(!h)h=thisScene.getLayer('\(name)').instance;let expected=n++===0?1:.5;if(h.rate!==expected||h.count!==(n===1?1:2))throw Error('cached mirror');h.alpha=.25;h.rate=.5;h.count=2;return v;}",
                target:.layer(layerID:id,field:.origin))
            let first = try evaluate(owner)
            let admission = runtime.preflightOwnerEffects([effects(owner,first)])
            let current = resolution(runtime,admission.admittedEffects)
            runtime.commit(admission.layerPlan);owner.commitLayerMutations()
            try domain.publishLayerSnapshot(current,descriptor:renamed,particleInstanceLayerIDs:[id])
            _ = try evaluate(owner)
            results["cached-renamed-instance-mirror-\(id)"] = current[.particle(layerID:id,field:.alpha)]?.value == .scalar(0.25)
                && current[.particle(layerID:id,field:.rate)]?.value == .scalar(0.5)
                && current[.particle(layerID:id,field:.count)]?.value == .scalar(2)
        }
        // Instance availability is independent of the stricter playback profile.
        do {
            var hierarchy = descriptor
            hierarchy.layers[0].parentID = 99
            hierarchy.layers.append(.init(id:99,layerIndex:1,name:"parent",visible:true,
                originXYZ:[0,0,0],scaleXYZ:[1,1,1],alpha:1,effects:[],contentKind:"container",childLayerIDs:[42]))
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:hierarchy,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:hierarchy,particleInstanceLayerIDs:[42])
            let owner = try author(domain,"export function update(v){thisLayer.instance.alpha=.5;thisLayer.instance.rate=.5;thisLayer.instance.count=2;return v;}")
            let value = try evaluate(owner)
            let admission = runtime.preflightOwnerEffects([effects(owner,value)])
            let simulation = try sim(multi:true)
            simulation.advance(by:1,dynamicInstanceOverride:override(resolution(runtime,admission.admittedEffects)))
            results["layer-hierarchy-multi-emitter-without-playback-capability"] = simulation.playbackObservation == nil
                && admission.rejectedOwners.isEmpty && simulation.particles.count >= 4
                && simulation.particles.allSatisfy{$0.alpha==0.5} && simulation.simulationTime == 0.5
            results["ordinary-layer-has-no-particle-definition"] = !runtime.authoredLayerDefinitions.contains{
                $0.target == .particle(layerID:99,field:.alpha)
                    || $0.target == .particle(layerID:99,field:.rate)
                    || $0.target == .particle(layerID:99,field:.count)}
            let ordinary = try author(domain,"export function update(v){thisScene.getLayer('parent').instance.rate=.5;return v;}",
                target:.layer(layerID:42,field:.scale))
            do {_ = try evaluate(ordinary);results["ordinary-layer-instance-rejected"]=false}
            catch {results["ordinary-layer-instance-rejected"]=true}
        }
        // Each explicit birth consumes the setter prefix at its callsite, including authored zero.
        for (rejected,countSeed) in [(false,0.0),(false,2.0),(true,0.0),(true,2.0)] {
            let caseKey = "\(rejected)-\(countSeed)"
            var zeroDescriptor = descriptor
            let zero = SceneParticleDefinitionParser().parseInstanceOverride(["alpha":0,"rate":0,"count":countSeed])!
            zeroDescriptor.layers[0].particleInstanceOverride = zero
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:zeroDescriptor,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            let simulations = try [sim(zero),sim(zero)]
            let transaction = SceneParticlePlaybackTransaction(instances:simulations.enumerated().map{
                .init(surfaceID:UInt32($0.offset+1),layerID:42,simulator:$0.element)},surfaceIDs:[1,2],
                charge:{try domain.chargeParticleWork($0,bytes:$1)},release:{domain.releaseParticleStorage($0)},
                isCurrent:{true},totalLiveCount:{simulations.reduce(0){$0+$1.particles.count}})
            var prefixes:[Double]=[]
            domain.beginParticlePlaybackFrame(onBoundary:{o,discarded in
                transaction.callbackBoundary(owner:UInt(bitPattern:o),discardOwner:discarded)
            }) {o,raw in
                var prefix = try SceneScriptParticlePlaybackCommandBridge.commands(owner:o).get()
                    .filter{$0.callbackEpoch==raw.callback_epoch}.map{
                        SceneParticlePlaybackTransition(layerID:$0.layerID,action:$0.action,revision:0,count:$0.count,
                            callbackEpoch:$0.callbackEpoch,ordinal:$0.ordinal)}
                prefix.append(.init(layerID:Int(raw.layer_id),action:.emit,revision:0,count:Int(raw.count),
                    callbackEpoch:raw.callback_epoch,ordinal:raw.ordinal))
                return try transaction.preview(owner:UInt(bitPattern:o),prefix:prefix){_ in
                    var alpha = 1.0
                    guard mwx_scene_quickjs_owner_particle_instance_alpha(o,42,&alpha)==MWX_SCENE_QUICKJS_OK else {
                        throw SceneScriptScalarRuntimeFailure.staleOwner
                    }
                    prefixes.append(alpha)
                    let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex:0,generation:1,
                        definitions:runtime.authoredLayerDefinitions,sceneScriptValues:[Self.alpha:.scalar(alpha)]).snapshot
                    return .init(instanceOverride:override(snapshot,zero))
                }
            }
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:zeroDescriptor,
                particlePlaybackObservations:[42:simulations[0].playbackObservation!],particleInstanceLayerIDs:[42])
            let owner = try author(domain,"export function update(v){if(thisLayer.instance.alpha!==0||thisLayer.instance.rate!==0||thisLayer.instance.count!==\(countSeed))throw Error('authored seed');thisLayer.instance.alpha=.25;thisLayer.emitParticles(2);thisLayer.instance.alpha=.5;thisLayer.emitParticles(2);return v;}")
            let before = simulations.map{$0.frameSnapshot()}
            let value = try evaluate(owner)
            results["prefix-preview-restores-population-\(caseKey)"] = zip(simulations,before).allSatisfy{
                $0.0.particles==$0.1.particles && $0.0.frameSnapshot().nextParticleID==$0.1.nextParticleID}
            let admission = runtime.preflightOwnerEffectsToFixedPoint([effects(owner,value)],
                particleObservations:[42:simulations[0].playbackObservation!],validateParticleTransitions:{_ in true},
                rejectingParticleTransitions:{ plan,bundles,_ in
                    guard transaction.prepare(plan.particleTransitions) == nil else {return Set(bundles.map(\.ownerTarget))}
                    return []
                }) {bundles, _ in rejected ? Set(bundles.map(\.ownerTarget)) : []}
            if rejected {
                owner.discardLayerMutations();transaction.discard()
                results["whole-owner-rejection-restores-instance-and-births-\(countSeed)"] = admission.admission.admittedEffects.isEmpty
                    && simulations.allSatisfy{$0.particles.isEmpty && $0.frameSnapshot().nextParticleID==0}
                    && runtime.snapshot().authoredLayerValues[alpha] == nil
                    && runtime.snapshot().authoredLayerValues[rate] == nil
                    && runtime.snapshot().authoredLayerValues[count] == nil
                let reader = try author(domain,"export function update(v){if(thisLayer.instance.alpha!==0||thisLayer.instance.rate!==0||thisLayer.instance.count!==\(countSeed))throw Error('rollback');return v;}",target:.layer(layerID:42,field:.scale))
                _ = try evaluate(reader)
            } else {
                transaction.install();runtime.commit(admission.admission.layerPlan);owner.commitLayerMutations()
                results["authored-zero-exact-emit-prefix-births-on-both-surfaces-\(countSeed)"] = prefixes == [0.25,0.25,0.5,0.5]
                    && admission.externallyRejectedOwners.isEmpty && simulations.allSatisfy{
                        $0.particles.map(\.alpha)==[0.25,0.25,0.5,0.5]}
                results["final-setter-cannot-rewrite-earlier-explicit-births-\(countSeed)"] = resolution(runtime,admission.admission.admittedEffects)[alpha]?.value == .scalar(0.5)
            }
            transaction.discard();domain.endParticlePlaybackFrame()
            results["transaction-storage-released-\(caseKey)"] = mwx_scene_quickjs_domain_particle_reserved(domain.handle)==0
        }
        // A thrown setter owner rolls back its complete journal; unrelated next owner remains usable.
        do {
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:descriptor,particleInstanceLayerIDs:[42])
            let failing = try author(domain,"export function update(v){thisLayer.instance.alpha=.25;thisLayer.instance.rate=2;thisLayer.instance.count=0;thisLayer.origin.x=7;throw Error('rollback');}")
            do {_ = try evaluate(failing);results["throw-rejects-owner"]=false} catch {results["throw-rejects-owner"]=true}
            let healthy = try author(domain,"export function update(v){if(thisLayer.instance.alpha!==1||thisLayer.instance.rate!==1||thisLayer.instance.count!==1||thisLayer.origin.x!==0)throw Error('leak');thisLayer.instance.alpha=.75;thisLayer.instance.rate=.5;thisLayer.instance.count=2;return v;}",target:.layer(layerID:42,field:.scale))
            let value = try evaluate(healthy)
            let admission = runtime.preflightOwnerEffects([effects(healthy,value)])
            results["failed-owner-keeps-healthy-peer"] = admission.rejectedOwners.isEmpty
                && resolution(runtime,admission.admittedEffects)[alpha]?.value == .scalar(0.75)
                && resolution(runtime,admission.admittedEffects)[rate]?.value == .scalar(0.5)
                && resolution(runtime,admission.admittedEffects)[count]?.value == .scalar(2)
            let mutation = value.layerMutations.first!
            let copies = [mutation.owned(by:origin),mutation.resolvingAssetPath(to:"own"),mutation.selectingAuthoredFields(.particleInstance)]
            results["mutation-copies-preserve-independent-instance-fields"] = copies.allSatisfy{
                $0.particleAlpha==0.75 && $0.particleRate==0.5 && $0.particleCount==2}
            let coalesced = SceneScriptLayerMutation.coalescing([mutation,mutation.selectingAuthoredFields(.origin)]).first
            results["mutation-coalescing-preserves-independent-instance-fields"] = coalesced?.particleAlpha == 0.75
                && coalesced?.particleRate == 0.5 && coalesced?.particleCount == 2
            runtime.commit(admission.layerPlan);healthy.commitLayerMutations()
            let destroy = SceneScriptLayerMutation(kind:.destroy,isDynamic:false,fields:[],layerID:42,orderIndex:0,
                visible:false,alpha:1,origin:.zero,scale:.init(repeating:1),angles:.zero,color:.init(repeating:1),pointSize:32,text:"",font:"",assetPath:nil)
            _ = try runtime.apply([destroy]).get()
            results["destroy-clears-particle-instance-values"] = runtime.snapshot().authoredLayerValues[alpha] == nil
                && runtime.snapshot().authoredLayerValues[rate] == nil && runtime.snapshot().authoredLayerValues[count] == nil
        }
        // Interleaved callbacks must publish the same winner now and after commit.
        for rejectPeerWrite in [false,true] {
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            let simulation = try sim()
            let observations = [42:simulation.playbackObservation!]
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:descriptor,
                particlePlaybackObservations:observations,particleInstanceLayerIDs:[42])
            let first = try author(domain,"let writes=0;export function update(v){writes++;thisLayer.visible=true;thisLayer.instance.alpha=writes===1?.25:.75;return v;}")
            let second = try author(domain,"export function update(v){thisLayer.visible=false;thisLayer.instance.alpha=.5;return v;}",
                target:.layer(layerID:42,field:.scale))
            let playing = try author(domain,"export function update(v){thisLayer.play();return v;}",
                target:.layer(layerID:42,field:.angles))
            let bundles = [effects(first,try evaluate(first)),effects(second,try evaluate(second)),
                effects(first,try evaluate(first)),effects(playing,try evaluate(playing))]
            let visible = SceneDynamicTarget.layer(layerID:42,field:.visibility)
            var healthyPeerPrepared = false
            let settled = runtime.preflightOwnerEffectsToFixedPoint(bundles,
                particleObservations:observations,validateParticleTransitions:{_ in true},
                rejectingParticleTransitions:{plan,admitted,rejected in
                    let current = SceneDynamicSnapshotResolver().resolve(frameIndex:0,generation:1,
                        definitions:runtime.authoredLayerDefinitions,
                        sceneScriptValues:frameScriptValues(admitted,layerPlan:plan,excluding:rejected,timelineValues:[:])).snapshot
                    if rejectPeerWrite && (current[visible]?.value != .bool(true)
                        || current[alpha]?.value != .scalar(0.75)) {return [playing.target]}
                    healthyPeerPrepared = plan.particleTransitions.contains{$0.action == .play}
                    return []
                }) {admitted,_ in
                    rejectPeerWrite ? Set(admitted.filter{$0.ownerTarget == second.target}.map(\.ownerTarget)) : []
                }
            let current = resolution(runtime,settled.admission.admittedEffects,plan:settled.admission.layerPlan)
            runtime.commit(settled.admission.layerPlan)
            first.commitLayerMutations()
            if rejectPeerWrite {second.discardLayerMutations()} else {second.commitLayerMutations()}
            if settled.externallyRejectedOwners.contains(playing.target) {playing.discardLayerMutations()}
            else {playing.commitLayerMutations()}
            let next = SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
                definitions:runtime.authoredLayerDefinitions,
                sceneScriptValues:runtime.snapshot().authoredLayerValues).snapshot
            results["cross-owner-alpha-current-matches-commit-\(rejectPeerWrite)"] = current[alpha]?.value == next[alpha]?.value
                && next[alpha]?.value == .scalar(rejectPeerWrite ? 0.75 : 0.5)
            results["cross-owner-visibility-current-matches-commit-\(rejectPeerWrite)"] = current[visible]?.value == next[visible]?.value
                && next[visible]?.value == .bool(rejectPeerWrite)
            results["external-writer-rejection-keeps-healthy-peer-\(rejectPeerWrite)"] = healthyPeerPrepared
                && settled.externallyRejectedOwners == (rejectPeerWrite ? [second.target] : [])
                && settled.admission.layerPlan.particleTransitions.contains{$0.action == .play}
        }
        // Missing actual instance resource and non-finite Number cannot become successful values.
        for field in ["alpha","rate","count"] {
            for available in [false,true] {
                for invalid in available ? ["Infinity","NaN","'0.5'","true","null"] : ["0.5"] {
                    let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
                    let domain = try SceneScriptQuickJSDomain()
                    try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:descriptor,
                        particleInstanceLayerIDs:available ? [42] : [])
                    let owner = try author(domain,"export function update(v){thisLayer.instance.\(field)=\(invalid);return v;}")
                    do {_ = try evaluate(owner);results["unsafe-instance-rejected-\(field)-\(available)-\(invalid)"]=false}
                    catch {results["unsafe-instance-rejected-\(field)-\(available)-\(invalid)"]=true}
                }
            }
        }
        print(String(data:try JSONSerialization.data(withJSONObject:results,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''


class ParticleInstanceAlphaTests(unittest.TestCase):
    def test_real_vm_typed_snapshot_and_birth_transactions(self):
        # Particle definitions and births are production code, replacing only unrelated VM fixture carriers.
        start = SWIFT_PREAMBLE.index("enum SceneParticleNumericValue:")
        end = SWIFT_PREAMBLE.index("struct SceneDocument", start)
        preamble = SWIFT_PREAMBLE[:start] + SWIFT_PREAMBLE[end:]
        source = (SCENE / "Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift").read_text()
        start = source.index("        func frameScriptValues(")
        end = source.index("        func timelineProjection(", start)
        harness = HARNESS.replace("        // PRODUCTION_FRAME_SCRIPT_VALUES", source[start:end])
        with tempfile.TemporaryDirectory(prefix="mwx-particle-instance-alpha-") as raw:
            binary = compile_vector_harness(Path(raw), harness, "particle-instance-alpha", preamble=preamble,
                extra_swift_sources=tuple(PARTICLE_SOURCES) + (SCENE / "Systems/Particles/SceneParticleInstanceOverride+Dynamic.swift",),
                whole_module_optimization=True,
            )
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            result = json.loads(run.stdout.strip().splitlines()[-1])
            self.assertTrue(result)
            for name, passed in result.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
