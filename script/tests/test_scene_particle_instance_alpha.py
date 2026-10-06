"""Public instance alpha: real QuickJS, typed owner admission and CPU births."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import ROOT, SWIFT_PREAMBLE, compile_vector_harness
from .test_scene_particle_simulator import SWIFT_SOURCES as PARTICLE_SOURCES

SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
HARNESS = r'''
import simd
@main enum Harness {
    static let origin = SceneDynamicTarget.layer(layerID:42,field:.origin)
    static let alpha = SceneDynamicTarget.particle(layerID:42,field:.alpha)
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
                    target:SceneDynamicTarget = origin) throws -> SceneScriptValueOwner {
            try .init(domain:domain,source:source,target:target,valueType:.vector3,effectNames:[],
                allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        }
        func evaluate(_ owner:SceneScriptValueOwner) throws -> SceneScriptValueEvaluation {
            try owner.evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",
                expectedGeneration:1,interruptBudget:nil).get()
        }
        func effects(_ owner:SceneScriptValueOwner,_ value:SceneScriptValueEvaluation) -> SceneScriptOwnerEffects {
            var result = SceneScriptOwnerEffects(ownerTarget:owner.target,materialFunctionMutations:[],
                animationMutations:[],layerMutations:[],videoCommands:[])
            result.append(value);return result
        }
        struct Values {let values:[SceneDynamicTarget:SceneDynamicValue]}
        let sceneScriptStringResult = Values(values:[:]), sceneScriptResult = Values(values:[:]), sceneScriptVectorResult = Values(values:[:])
        // PRODUCTION_FRAME_SCRIPT_VALUES
        func resolution(_ runtime:SceneScriptDynamicLayerRuntime,_ admitted:[SceneScriptOwnerEffects]) -> SceneDynamicSnapshot {
            SceneDynamicSnapshotResolver().resolve(frameIndex:0,generation:1,
                definitions:runtime.authoredLayerDefinitions,
                sceneScriptValues:frameScriptValues(admitted,excluding:[])).snapshot
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
        // Instance availability is independent of the stricter playback profile.
        do {
            var hierarchy = descriptor
            hierarchy.layers[0].parentID = 99
            hierarchy.layers.append(.init(id:99,layerIndex:1,name:"parent",visible:true,
                originXYZ:[0,0,0],scaleXYZ:[1,1,1],alpha:1,effects:[],contentKind:"container",childLayerIDs:[42]))
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:hierarchy,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:hierarchy,particleInstanceLayerIDs:[42])
            let owner = try author(domain,"export function update(v){thisLayer.instance.alpha=.5;return v;}")
            let value = try evaluate(owner)
            let admission = runtime.preflightOwnerEffects([effects(owner,value)])
            let simulation = try sim(multi:true)
            simulation.advance(by:1,dynamicInstanceOverride:override(resolution(runtime,admission.admittedEffects)))
            results["layer-hierarchy-multi-emitter-without-playback-capability"] = simulation.playbackObservation == nil
                && admission.rejectedOwners.isEmpty && simulation.particles.count >= 4
                && simulation.particles.allSatisfy{$0.alpha==0.5}
            results["ordinary-layer-has-no-particle-definition"] = !runtime.authoredLayerDefinitions.contains{
                $0.target == .particle(layerID:99,field:.alpha)}
        }
        // Each explicit birth consumes the setter prefix at its callsite, including authored zero.
        for rejected in [false,true] {
            var zeroDescriptor = descriptor
            let zero = SceneParticleDefinitionParser().parseInstanceOverride(["alpha":0])!
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
            let owner = try author(domain,"export function update(v){if(thisLayer.instance.alpha!==0)throw Error('authored zero');thisLayer.instance.alpha=.25;thisLayer.emitParticles(2);thisLayer.instance.alpha=.5;thisLayer.emitParticles(2);return v;}")
            let before = simulations.map{$0.frameSnapshot()}
            let value = try evaluate(owner)
            results["prefix-preview-restores-population-\(rejected)"] = zip(simulations,before).allSatisfy{
                $0.0.particles==$0.1.particles && $0.0.frameSnapshot().nextParticleID==$0.1.nextParticleID}
            let admission = runtime.preflightOwnerEffectsToFixedPoint([effects(owner,value)],
                particleObservations:[42:simulations[0].playbackObservation!],validateParticleTransitions:{_ in true},
                rejectingParticleTransitions:{ transitions,bundles,_ in
                    guard transaction.prepare(transitions) == nil else {return Set(bundles.map(\.ownerTarget))}
                    return []
                }) {bundles in rejected ? Set(bundles.map(\.ownerTarget)) : []}
            if rejected {
                owner.discardLayerMutations();transaction.discard()
                results["whole-owner-rejection-restores-alpha-and-births"] = admission.admission.admittedEffects.isEmpty
                    && simulations.allSatisfy{$0.particles.isEmpty && $0.frameSnapshot().nextParticleID==0}
                    && runtime.snapshot().authoredLayerValues[alpha] == nil
                let reader = try author(domain,"export function update(v){if(thisLayer.instance.alpha!==0)throw Error('rollback');return v;}",target:.layer(layerID:42,field:.scale))
                _ = try evaluate(reader)
            } else {
                transaction.install();runtime.commit(admission.admission.layerPlan);owner.commitLayerMutations()
                results["authored-zero-setter-prefix-births-on-both-surfaces"] = prefixes == [0.25,0.25,0.5,0.5]
                    && admission.externallyRejectedOwners.isEmpty && simulations.allSatisfy{
                        $0.particles.map(\.alpha)==[0.25,0.25,0.5,0.5]}
                results["final-setter-cannot-rewrite-earlier-explicit-births"] = resolution(runtime,admission.admission.admittedEffects)[alpha]?.value == .scalar(0.5)
            }
            transaction.discard();domain.endParticlePlaybackFrame()
            results["transaction-storage-released-\(rejected)"] = mwx_scene_quickjs_domain_particle_reserved(domain.handle)==0
        }
        // A thrown setter owner rolls back its complete journal; unrelated next owner remains usable.
        do {
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:descriptor,particleInstanceLayerIDs:[42])
            let failing = try author(domain,"export function update(v){thisLayer.instance.alpha=.25;thisLayer.origin.x=7;throw Error('rollback');}")
            do {_ = try evaluate(failing);results["throw-rejects-owner"]=false} catch {results["throw-rejects-owner"]=true}
            let healthy = try author(domain,"export function update(v){if(thisLayer.instance.alpha!==1 || thisLayer.origin.x!==0)throw Error('leak');thisLayer.instance.alpha=.75;return v;}",target:.layer(layerID:42,field:.scale))
            let value = try evaluate(healthy)
            let admission = runtime.preflightOwnerEffects([effects(healthy,value)])
            results["failed-owner-keeps-healthy-peer"] = admission.rejectedOwners.isEmpty
                && resolution(runtime,admission.admittedEffects)[alpha]?.value == .scalar(0.75)
            let mutation = value.layerMutations.first!
            let copies = [mutation.owned(by:origin),mutation.resolvingAssetPath(to:"own"),mutation.selectingAuthoredFields(.particleAlpha)]
            results["mutation-copies-preserve-independent-alpha"] = copies.allSatisfy{$0.particleAlpha==0.75}
            results["mutation-coalescing-preserves-independent-alpha"] = SceneScriptLayerMutation.coalescing([
                mutation,mutation.selectingAuthoredFields(.origin)]).first?.particleAlpha == 0.75
            runtime.commit(admission.layerPlan);healthy.commitLayerMutations()
            let destroy = SceneScriptLayerMutation(kind:.destroy,isDynamic:false,fields:[],layerID:42,orderIndex:0,
                visible:false,alpha:1,origin:.zero,scale:.init(repeating:1),angles:.zero,color:.init(repeating:1),pointSize:32,text:"",font:"",assetPath:nil)
            _ = try runtime.apply([destroy]).get()
            results["destroy-clears-particle-alpha-value"] = runtime.snapshot().authoredLayerValues[alpha] == nil
        }
        // Missing actual instance resource and non-finite Number cannot become successful values.
        for available in [false,true] {
            let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
            let domain = try SceneScriptQuickJSDomain()
            try domain.publishLayerSnapshot(resolution(runtime,[]),descriptor:descriptor,
                particleInstanceLayerIDs:available ? [42] : [])
            let source = available ? "thisLayer.instance.alpha=Infinity;" : "thisLayer.instance.alpha=.25;"
            let owner = try author(domain,"export function update(v){\(source)return v;}")
            do {_ = try evaluate(owner);results["unsafe-instance-rejected-\(available)"]=false}
            catch {results["unsafe-instance-rejected-\(available)"]=true}
        }
        print(String(data:try JSONSerialization.data(withJSONObject:results,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''


class ParticleInstanceAlphaTests(unittest.TestCase):
    def test_real_vm_typed_snapshot_and_birth_transactions(self):
        # Particle definitions and births are production code, replacing only unrelated VM fixture carriers.
        start = SWIFT_PREAMBLE.index("enum SceneParticleNumericValue:")
        end = SWIFT_PREAMBLE.index("struct SceneRenderDescriptor", start)
        preamble = SWIFT_PREAMBLE[:start] + SWIFT_PREAMBLE[end:]
        source = (SCENE / "Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift").read_text()
        start = source.index("        func frameScriptValues(")
        end = source.index("        func timelineProjection(", start)
        harness = HARNESS.replace("        // PRODUCTION_FRAME_SCRIPT_VALUES", source[start:end])
        with tempfile.TemporaryDirectory(prefix="mwx-particle-instance-alpha-") as raw:
            binary = compile_vector_harness(Path(raw), harness, "particle-instance-alpha", preamble=preamble,
                extra_swift_sources=tuple(PARTICLE_SOURCES) + (SCENE / "Systems/Particles/SceneParticleInstanceOverride+Dynamic.swift",))
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            result = json.loads(run.stdout.strip().splitlines()[-1])
            self.assertTrue(result)
            for name, passed in result.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
