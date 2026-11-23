"""Production cursor event confirmation after owner/frame rejection."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from script.tests.support.scene_vector_vm_test_support import SCENE, compile_vector_harness

CURSOR_HARNESS_COMMON = r'''
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
    static func target(_ field: SceneDynamicLayerField = .origin, _ id: Int = 1) -> SceneDynamicTarget { .layer(layerID:id,field:field) }
    static func make(_ sources: [(SceneDynamicLayerField,String)], borrowed: Bool = false) throws -> (SceneScriptCursorProgram,[SceneScriptValueOwner]) {
        let d = try SceneScriptQuickJSDomain()
        try d.configureLayerCatalog(.init(layers:[.init(id:1,layerIndex:0,name:"cursor",visible:true,
            originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])]))
        var bindings:[SceneScriptCursorBinding] = [];var owners:[SceneScriptValueOwner] = []
        for (i,item) in sources.enumerated() {
            let o = try SceneScriptValueOwner(domain:d,source:item.1,target:target(item.0),effectNames:[],
                allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
            owners.append(o)
            bindings.append(.init(layerID:1,authoredOrdinal:i,owner:o,events:o.exportedCursorEvents,
                ownsOwner:!borrowed,scriptProperties:[:],ownerSeedValue:.vector3(0,0,0)))
        }
        return (.init(bindings:bindings,generation:1),owners)
    }
    static func sample(_ x: Double, _ down: Bool, hit: Bool = true, pollingScale: Double = 10) -> SceneScriptCursorFrameSample {
        let h = SceneScriptCursorHit(layerID:1,worldPosition:.init(x*10,0,0),localPosition:.init(x,0,0))
        return .init(hits:hit ? [1:h] : [:],ownerProjections:[1:h],pointerPosition:.init(Float(x),0),
            primaryButtonIsDown:down,surface:.init(canvasSize:.init(100,100),screenSize:.init(100,100),
                cursorWorldPosition:.init(x*pollingScale,0,-9000),cursorScreenPosition:.init(x,0),cursorLeftDown:down))
    }
    static func click(_ x: Double) -> [SceneScriptCursorFrameSample] { [sample(x,false),sample(x,true),sample(x,false)] }
    static func dispatch(_ p: SceneScriptCursorProgram, _ samples:[SceneScriptCursorFrameSample], overflow:Bool = false) -> SceneScriptCursorFrameResult {
        p.dispatch(batch:.init(samples:samples,overflowed:overflow),frame:frame,userPropertiesJSON:"{}")
    }
    static func values(_ r: SceneScriptCursorFrameResult, _ field:SceneDynamicLayerField = .origin) -> [Double] {
        guard let m = r.ownerEffects.first(where:{$0.ownerTarget == target(field)})?.layerMutations.last else { return [] }
        return [m.origin.x,m.origin.y,m.origin.z]
    }
    static let clicks = """
      let xs=[];
      export function cursorClick(e) { xs.push(e.localPosition.x); thisLayer.origin=new Vec3(xs.length,xs.length>1?xs[xs.length-2]:0,input.cursorWorldPosition.x); }
      """
'''

HARNESS = CURSOR_HARNESS_COMMON + r'''
    static func primaryButtonCases() throws -> [[String:Any]] {
        try (0..<2).map { variant in
            let argument = variant == 0 ? "event" : "pointerEvent"
            let guardBody = variant == 0
                ? "if (event.button !== 0) return;"
                : "if (!(pointerEvent['button'] === (1 - 1))) return;"
            let source = """
                let trace=0, pressed=0, clicks=0, held=false;
                function record(\(argument), kind, expectedDown) {
                    \(guardBody)
                    if (typeof \(argument).button !== 'number') throw Error('button type');
                    if (input.cursorLeftDown !== expectedDown) throw Error('pressed input changed');
                    trace=trace*10+kind;
                    pressed=pressed*10+(input.cursorLeftDown ? 1 : 2);
                    if (kind===4) clicks++;
                    thisLayer.origin=new Vec3(trace,pressed,clicks);
                }
                export function cursorMove(e){record(e,1,held);}
                export function cursorDown(e){held=true;record(e,2,true);}
                export function cursorUp(e){held=false;record(e,3,false);}
                export function cursorClick(e){record(e,4,false);}
                """
            let peer = """
                let moves=0, clicks=0;
                export function cursorMove(e){thisLayer.origin=new Vec3(++moves,e.localPosition.x,input.cursorLeftDown?1:0);}
                export function cursorClick(e){thisLayer.origin=new Vec3(moves,++clicks,input.cursorLeftDown?1:0);}
                """
            let scenarios: [(String,[SceneScriptCursorFrameSample])] = [
                ("inside", [sample(1,false),sample(2,false),sample(2,true),sample(3,true),sample(3,false)]),
                ("outsidePress", [sample(10,false,hit:false),sample(10,true,hit:false),sample(10,false,hit:false)]),
                ("releaseOutside", [sample(10,false),sample(10,true),sample(11,true,hit:false),sample(11,false,hit:false)]),
            ]
            var facts: [String:Any] = ["variant":variant]
            for (name,samples) in scenarios {
                let (program,_) = try make([(.origin,source),(.scale,peer)])
                let result = dispatch(program,samples)
                program.finalizeLayerMutations(committing:true)
                let idle = dispatch(program,[samples.last!])
                facts[name] = [
                    "failures":result.failures.values.map(\.code).sorted(),
                    "value":values(result), "peer":values(result,.scale),
                    "quietAfter":idle.ownerEffects.isEmpty && idle.failures.isEmpty,
                ]
                program.finalizeLayerMutations(committing:true)
            }
            return facts
        }
    }
    static func failedInitCursorCases() throws -> [[String:Any]] {
        var facts: [[String:Any]] = []
        for variant in 0..<2 {
            let targetName = variant == 0 ? "'cursor'" : "['cur','sor'].join('')"
            let argument = variant == 0 ? "event" : "tap"
            let guardBody = variant == 0 ? "event.button !== 0" : "tap['button'] !== (1 - 1)"
            let source = """
                let saved, initializations=0, clicks=0;
                export function init(v) {
                    saved=thisScene.getLayer(\(targetName));
                    ++initializations;
                    thisLayer.origin=new Vec3(999,999,999);
                    throw new TypeError('ordinary initialization failure');
                }
                export function cursorClick(\(argument)) {
                    if (\(guardBody)) return;
                    if (++clicks===2) throw new Error('later callback failure');
                    saved.visible=false;
                    thisLayer.origin=new Vec3(initializations,clicks,\(argument).localPosition.x);
                }
                """
            let peer = "let n=0;export function cursorClick(e){thisLayer.origin=new Vec3(++n,0,0);}"
            let scenarios: [(String,[SceneScriptCursorFrameSample])] = [
                ("inside", click(10)),
                ("outsidePress", [sample(10,false,hit:false),sample(10,true,hit:false),sample(10,false,hit:false)]),
                ("releaseOutside", [sample(10,false),sample(10,true),sample(11,true,hit:false),sample(11,false,hit:false)]),
            ]
            for (name,samples) in scenarios {
                let (program,owners) = try make([(.origin,source),(.scale,peer)],borrowed:true)
                let initialization = owners[0].initializeIfNeeded(input:.vector3(0,0,0),frame:frame,
                    scriptPropertiesJSON:"{}",userPropertiesJSON:"{}",expectedGeneration:1,
                    interruptBudget:nil,retainsValueForNextUpdate:true)
                guard case let .failure(failure) = initialization else { fatalError("init did not fail") }
                let first = program.dispatch(batch:.init(samples:samples,overflowed:false),frame:frame,
                    userPropertiesJSON:"{}",initializationFailures:[target():failure])
                program.finalizeLayerMutations(committing:true)
                let retried = dispatch(program,[sample(99,false)])
                let mutation = retried.ownerEffects.first{$0.ownerTarget==target()}?.layerMutations.last
                var row: [String:Any] = [
                    "variant":variant,"scenario":name,
                    "firstCode":first.failures[target()]?.code ?? "none",
                    "firstValue":values(first),"firstPeer":values(first,.scale),
                    "initTerminal":!owners[0].needsInitialization,
                    "value":values(retried),"visibility":mutation?.visible as Any? ?? NSNull(),
                    "failures":retried.failures.values.map(\.code).sorted(),
                ]
                program.finalizeLayerMutations(committing:true)
                let quiet = dispatch(program,[sample(99,false)])
                row["quiet"] = quiet.ownerEffects.isEmpty && quiet.failures.isEmpty
                program.finalizeLayerMutations(committing:true)
                if name == "inside" {
                    let later = dispatch(program,click(12))
                    row["laterCode"] = later.failures[target()]?.code ?? "none"
                    row["laterValue"] = values(later)
                    row["laterPeer"] = values(later,.scale)
                    program.finalizeLayerMutations(committing:true)
                    let fused = dispatch(program,click(13))
                    row["fusedValue"] = values(fused)
                    row["fusedPeer"] = values(fused,.scale)
                    program.finalizeLayerMutations(committing:true)
                }
                facts.append(row)
            }
        }
        return facts
    }
    static func boneOrder(burst: Bool = false, failPeer: Bool = false, mixed: Bool = false) throws -> [String:Any] {
        let second = burst
            ? "thisLayer.setBoneTransform(0,Mat4.fromTranslation(new Vec3(11,0,0)));" : ""
        let impulseAfter = mixed ? "thisLayer.applyBonePhysicsImpulse('root',new Vec3(11,0,0));" : ""
        let impulseBefore = mixed ? "thisLayer.applyBonePhysicsImpulse(0,new Vec3(29,0,0));" : ""
        let a = """
            export function cursorDown(e){
                shared.matrixOrder=(shared.matrixOrder||'')+'1';
                thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(10,0,0)));
                \(second)
                \(impulseAfter)
            }
            export function cursorUp(e){
                shared.matrixOrder+='3';
                \(impulseBefore)
                thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(30,0,0)));
                thisLayer.origin=new Vec3(Number(shared.matrixOrder),thisLayer.getLocalBoneTransform(0).translation().x,0);
            }
            """
        let failure = failPeer ? "throw new Error('reject bone peer');" : ""
        let peerImpulse = mixed ? "thisLayer.applyBonePhysicsImpulse('root',new Vec3(20,0,0),new Vec3(0));" : ""
        let b = """
            export function cursorDown(e){
                shared.matrixOrder+='2';
                \(peerImpulse)
                thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(20,0,0)));
                if(thisLayer.getLocalBoneTransform(0).translation().x!==20)throw new Error('readback');
                \(failure)
            }
            """
        let (p,owners) = try make([(.origin,a),(.scale,b)])
        let identity:[Double] = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
        for owner in owners {
            try owner.configurePuppetBones(layerID:1,localMatrices:identity,
                names:["root"],parents:[-1])
        }
        let r = dispatch(p,click(10))
        let ordered = SceneScriptPuppetBoneMutationBridge.orderedMutations(in:r.ownerEffects)
        // This is the same owner exclusion applied before the host's shared
        // ordered projection, without inventing a second bone consumer.
        let admitted = r.ownerEffects.filter{$0.ownerTarget != target(.scale)}
        let filtered = SceneScriptPuppetBoneMutationBridge.orderedMutations(in:admitted)
        func payload(_ mutation:SceneScriptPuppetBoneMutation) -> Double {
            switch mutation.operation {
            case let .matrix(matrix): return matrix[12]
            case let .impulse(value): return value.x
            }
        }
        let trace = r.ownerEffects.first{$0.ownerTarget==target()}?.layerMutations.last
        let output:[String:Any] = [
            "owners":r.ownerEffects.count,"failures":r.failures.count,
            "peerFailure":r.failures[target(.scale)]?.code ?? "none",
            "callbackTrace":trace?.origin.x ?? -1,"ownReadback":trace?.origin.y ?? -1,
            "grouped":r.ownerEffects.map{$0.puppetBoneMutations.map(payload)},
            "ordered":ordered.map(payload),
            "kinds":ordered.map { if case .matrix = $0.operation { return "matrix" }; return "impulse" },
            "epochs":ordered.map{$0.callbackEpoch},"ordinals":ordered.map{$0.ordinal},
            "filtered":filtered.map(payload),
            "filteredKinds":filtered.map { if case .matrix = $0.operation { return "matrix" }; return "impulse" },
            "filteredEpochs":filtered.map{$0.callbackEpoch}]
        p.finalizeLayerMutations(committing:true)
        return output
    }
    static func puppetCursorCases() throws -> [String:Any] {
        var out:[String:Any] = [:]
        for mode in ["normal","twice","throw","late","rejected","whole"] {
            let sourceName = "cursor motion " + mode
            let clip = SceneMdlPuppetAnimation(id:812,name:sourceName,mode:"single",framesPerSecond:30,
                frameCount:30,transformsByBone:[Array(repeating:.init(translation:.zero,rotation:.zero,
                    scale:SIMD3<Float>(repeating:1)),count:31)])
            let runtime = ScenePuppetAnimationPlaybackRuntime()
            guard case .success = runtime.register(layerID:3,
                selection:.init(clips:[],composition:.layered),authoredLayers:[],availableSingleAnimations:[clip])
                else { fatalError("cursor source") }
            let initial = runtime.advance(frameIndex:0,sceneTime:1,dynamicValues:.empty(frameIndex:0))
            let descriptor = SceneRenderDescriptor(layers:(1...3).map { id in .init(id:id,layerIndex:id-1,
                name:"cursor\(id)",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,
                alpha:1,effects:[],sizeWH:[100,100]) })
            func binding(_ id:Int,_ failed:Bool) -> SceneScriptBindingIR {
                let tail = failed && mode == "throw" ? "throw Error('after Puppet create');" : ""
                let update = failed && mode == "late" ? "export function update(v){throw Error('late update');}" : ""
                let source = """
                    export function animationEvent(event,value){return value;}
                    export function cursorClick(event) {
                        const image=thisScene.getLayerByID(3);
                        const h=image.playSingleAnimation('\(sourceName)');
                        h.pause();h.setFrame(15);
                        if(h.getFrame()!==15||h.isPlaying())throw Error('cursor provisional');
                        \(tail)
                    }
                    \(update)
                    """
                return .init(source:source,owner:.init(kind:.object,objectIndex:id-1,objectID:id,
                    effectIndex:nil,effectID:nil,passIndex:nil,passID:nil),
                    targetPath:[.key("objects"),.index(id-1),.key("visible")],properties:[:],
                    authoredValue:.bool(true),valueType:.boolean,wrapperKeys:["script","value"])
            }
            let bindings = [binding(1,true),binding(2,false)]
            let candidate = try SceneScriptQuickJSProgramCandidate.compile(authoredDescriptor:descriptor,
                runtimeDescriptor:descriptor,scriptBindings:bindings,
                vectorProjection:SceneScriptVectorProgram.project(descriptor:descriptor,scriptBindings:bindings),
                userPropertyDefinitions:[],timelineTargets:[],scalarExcludedTargets:[],stringExcludedTargets:[],
                admittedVectorPassTargets:[],generation:1)
            guard let domain = candidate.domain else { fatalError("cursor domain") }
            domain.bindPuppetAnimationSources(runtime)
            try domain.publishPuppetAnimationSnapshot(initial.animationSnapshots)
            try domain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor)
            let creator = target(.visibility,1), peer = target(.visibility,2)
            let coordinator = SceneScriptMediaFrameCoordinator(vectorProgram:candidate.vectorProgram,
                stringProgram:candidate.stringProgram,scalarProgram:candidate.scalarProgram)
            let inputs:[SceneDynamicTarget:SceneDynamicValue] = [creator:.bool(true),peer:.bool(true)]
            _ = coordinator.initialize(vectorInputs:inputs,stringInputs:[:],scalarInputs:[:],
                effectivePropertyValues:[:],frame:frame,userPropertiesJSON:"{}",audioSpectrum:.silent)
            candidate.vectorProgram.finalizeLayerMutations(committing:true);coordinator.finalizeInitializations()
            let cursor = candidate.cursorProgram
            let callbackOnly = mode == "late" || cursor.bindings.allSatisfy { !$0.owner.requiresFrameEvaluation }
            func input(_ down:Bool) -> SceneScriptCursorFrameSample {
                .init(hits:Dictionary(uniqueKeysWithValues:(1...2).map { id in
                    (id,SceneScriptCursorHit(layerID:id,worldPosition:.zero,localPosition:.zero)) }),
                    pointerPosition:.zero,primaryButtonIsDown:down)
            }
            let clicks = [input(false),input(true),input(false)]
                + (mode == "twice" ? [input(true),input(false)] : [])
            let edge = cursor.edgeStateSnapshot()
            let values = candidate.vectorProgram.frameStateSnapshot()
            func evaluate(_ effects:[SceneScriptOwnerEffects]) -> SceneScriptMediaFrameCoordinatorResult {
                coordinator.evaluate(vectorInputs:inputs,stringInputs:[:],scalarInputs:[:],
                    effectivePropertyValues:[:],frame:frame,userPropertiesJSON:"{}",events:.empty,
                    audioSpectrum:.silent,priorOwnerEffects:effects)
            }
            let layers = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[1,2,3])
            func admit(_ effects:[SceneScriptOwnerEffects],_ rejected:Set<SceneDynamicTarget>,_ cadence:UInt64)
                -> SceneScriptOwnerEffectsFixedPointAdmission {
                layers.preflightOwnerEffectsToFixedPoint(effects,excludingOwners:rejected) { owners,_ in
                    Set(owners.compactMap { owner in
                        if case .failure = runtime.validate(owner.puppetAnimationCommands,frameIndex:cadence) {
                            return owner.ownerTarget
                        }
                        return nil
                    })
                }
            }
            var events = cursor.dispatch(batch:.init(samples:clicks,overflowed:false),frame:frame,userPropertiesJSON:"{}")
            var update = evaluate(events.ownerEffects)
            let oldKeys = Set(events.ownerEffects.flatMap(\.puppetAnimationCommands).map(\.identity))
            var droppedCleanly = true
            if mode == "whole" {
                cursor.restoreEdgeState(edge);cursor.finalizeLayerMutations(committing:false)
                candidate.vectorProgram.restoreFrameState(values)
                candidate.vectorProgram.finalizeLayerMutations(committing:false)
                droppedCleanly = runtime.snapshots().isEmpty
                events = cursor.dispatch(batch:.init(samples:clicks,overflowed:false),frame:frame,userPropertiesJSON:"{}")
                update = evaluate(events.ownerEffects)
            }
            let failures = Set(events.failures.keys).union(update.vector.failures.keys)
            let rejected = failures.union(mode == "rejected" ? [creator] : [])
            let first = admit(events.ownerEffects + update.ownerEffects,rejected,0)
            layers.commit(first.admission.layerPlan)
            let commands = first.admission.admittedEffects.flatMap(\.puppetAnimationCommands)
            let applied:Bool
            if case .success = runtime.apply(commands,frameIndex:0) { applied=true } else { applied=false }
            let partial = mode == "throw" || mode == "late" || mode == "rejected"
            let expected = mode == "twice" ? 4 : partial ? 1 : 2
            let births = runtime.snapshots()
            cursor.finalizeLayerMutations(committing:true,rejectedOwnerTargets:first.externallyRejectedOwners)
            candidate.vectorProgram.restoreFrameState(values,rejectedOwnerTargets:first.externallyRejectedOwners)
            candidate.vectorProgram.finalizeLayerMutations(committing:true,rejectedOwnerTargets:first.externallyRejectedOwners)
            var facts:[String:Bool] = [
                "borrowedCallbackOnly":callbackOnly,
                "twoBorrowedOwners":cursor.bindings.count == 2 && candidate.vectorProgram.bindings.count == 2
                    && cursor.bindings.allSatisfy { binding in !binding.ownsOwner
                        && candidate.vectorProgram.bindings.contains { $0.owner === binding.owner
                            && $0.definition.target == binding.ownerTarget } },
                "cursorTransport":events.ownerEffects.flatMap(\.puppetAnimationCommands).count == (mode == "twice" ? 12 : mode == "throw" ? 3 : 6),
                "noUpdateReexport":update.ownerEffects.flatMap(\.puppetAnimationCommands).isEmpty,
                "failureScope":events.failures[peer] == nil && update.vector.failures[peer] == nil
                    && (events.failures[creator] != nil) == (mode == "throw")
                    && (update.vector.failures[creator] != nil) == (mode == "late"),
                "nativeApplied":applied && births.count == expected,
                "sameCallbackControls":births.allSatisfy { !$0.isPlaying && $0.currentFrame == 15 },
                "keysStayDistinct":Set(births.map(\.identity)).count == expected,
                "wholeDiscard":droppedCleanly && (mode != "whole" || oldKeys.isDisjoint(with:births.map(\.identity)))
            ]
            _ = runtime.apply(commands,frameIndex:0)
            facts["applyOnce"] = runtime.snapshots().count == expected
            if mode == "rejected" {
                let next = runtime.advance(frameIndex:1,sceneTime:2,dynamicValues:.empty(frameIndex:1))
                try domain.publishPuppetAnimationSnapshot(next.animationSnapshots)
                let retry = cursor.dispatch(batch:.init(samples:[input(false)],overflowed:false),frame:frame,userPropertiesJSON:"{}")
                let retryUpdate = evaluate(retry.ownerEffects)
                let accepted = admit(retry.ownerEffects + retryUpdate.ownerEffects,[],1)
                let retryCommands = accepted.admission.admittedEffects.flatMap(\.puppetAnimationCommands)
                _ = runtime.apply(retryCommands,frameIndex:1)
                cursor.finalizeLayerMutations(committing:true)
                candidate.vectorProgram.finalizeLayerMutations(committing:true)
                let quiet = cursor.dispatch(batch:.init(samples:[input(false)],overflowed:false),frame:frame,userPropertiesJSON:"{}")
                facts["retryOnlyRejected"] = retry.ownerEffects.count == 1 && retry.ownerEffects.first?.ownerTarget == creator
                    && retryCommands.count == 3 && runtime.snapshots().count == 2 && quiet.ownerEffects.isEmpty
                cursor.finalizeLayerMutations(committing:true);candidate.vectorProgram.finalizeLayerMutations(committing:true)
            }
            out[mode] = ["facts":facts,"vectorOwnerCount":candidate.vectorProgram.bindings.count,
                "cursorOwnerCount":cursor.bindings.count,"standaloneFlags":cursor.bindings.map(\.ownsOwner),
                "valueFailures":update.vector.failures.values.map(\.code)]
        }
        return out
    }
    static func puppetRegistrationDeltas() throws -> [Int] {
        let descriptor = SceneRenderDescriptor(layers:[.init(id:1,layerIndex:0,name:"cursor",visible:true,
            originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])])
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor)
        let identity = ScenePuppetAnimationIdentity(layerID:1,animationLayerIndex:0,animationLayerID:89)
        let snapshot = ScenePuppetAnimationSnapshot(identity:identity,animationID:812,name:"loop",
            framesPerSecond:30,frameCount:30,duration:1,currentFrame:0,isPlaying:true,rate:1,blend:1,
            visible:true,endedSequence:0,supportsEndedCallbacks:true,endedFailure:nil)
        let owner = try SceneScriptValueOwner(domain:domain,
            source:"export function cursorClick(){thisObject.addEndedCallback(()=>{});}",
            target:ScenePuppetAnimationPropertyTarget.visibility(layerID:1,animationLayerID:89),
            valueType:.bool,effectNames:[],puppetAnimationIdentity:identity,
            allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        try domain.publishPuppetAnimationSnapshot([snapshot])
        let program = SceneScriptCursorProgram(bindings:[.init(layerID:1,authoredOrdinal:0,owner:owner,
            events:owner.exportedCursorEvents,ownsOwner:false,scriptProperties:[:],ownerSeedValue:.bool(true))],generation:1)
        let first = dispatch(program,click(1) + [sample(1,true),sample(1,false)])
        let total = first.ownerEffects.reduce(0) { $0 + $1.puppetAnimationCallbackRegistrations }
        let delta = Int(mwx_scene_quickjs_owner_puppet_animation_registration_count(owner.handle))
        program.finalizeLayerMutations(committing:true);owner.commitLayerMutations()
        let next = dispatch(program,[sample(1,true),sample(1,false)])
        let nextDelta = next.ownerEffects.reduce(0) { $0 + $1.puppetAnimationCallbackRegistrations }
        program.finalizeLayerMutations(committing:true);owner.commitLayerMutations()
        return [first.failures.count,total,delta,next.failures.count,nextDelta]
    }
    static func main() throws {
        var out:[String:Any] = [:]
        out["primaryButton"] = try primaryButtonCases()
        out["puppetCursor"] = try puppetCursorCases()
        out["puppetRegistrationDeltas"] = try puppetRegistrationDeltas()
        out["failedInitCursor"] = try failedInitCursorCases()
        out["boneOrder"] = try boneOrder()
        out["boneBurst"] = try boneOrder(burst:true)
        out["boneThrow"] = try boneOrder(failPeer:true)
        out["boneMixed"] = try boneOrder(mixed:true)
        out["boneMixedThrow"] = try boneOrder(failPeer:true,mixed:true)
        // Distinct targets on the same layer share physical hit observation,
        // but only the rejected target retries its exact completed click.
        let (p,_) = try make([(.origin,clicks),(.scale,clicks)])
        let first = dispatch(p,click(10));out["first"] = values(first);out["firstPeer"] = values(first,.scale)
        p.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        let retried = dispatch(p,[sample(99,false)]);out["retried"] = values(retried);out["retriedPeer"] = values(retried,.scale)
        p.finalizeLayerMutations(committing:true)
        out["confirmedQuiet"] = dispatch(p,[sample(99,false)]).ownerEffects.isEmpty
        p.finalizeLayerMutations(committing:true)

        // All event envelopes are recognized before an init BAD_RETURN can
        // prevent callbacks from running; capture is retained even without down.
        let (early,_) = try make([(.origin,"""
            let initCount=0; let events=0;
            export function init(v){if(++initCount===1)return {};return v;}
            function record(n){events=events*10+n;thisLayer.origin=new Vec3(events,0,0);}
            export function cursorEnter(e){record(1);}
            export function cursorDown(e){record(2);}
            export function cursorUp(e){record(3);}
            export function cursorClick(e){record(4);}
            """)])
        let earlyFailure = dispatch(early,click(10));out["earlyFailure"] = earlyFailure.failures[target()]?.code ?? "none"
        early.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["earlyRetry"] = values(dispatch(early,[sample(10,false)]));early.finalizeLayerMutations(committing:true)
        let (upOnly,_) = try make([(.origin,"export function cursorUp(e){thisLayer.origin=new Vec3(e.localPosition.x,0,0);}")])
        _ = dispatch(upOnly,click(15));upOnly.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["upOnlyRetry"] = values(dispatch(upOnly,[sample(40,false)]));upOnly.finalizeLayerMutations(committing:true)

        let (surface,_) = try make([(.origin,"""
            let n=0;
            function check(e,down){
                if(e.localPosition.x!==10 || e.worldPosition.x!==100 || input.cursorWorldPosition.x!==10000 || input.cursorWorldPosition.z!==-9000 ||
                   input.cursorScreenPosition.x!==10 || input.cursorLeftDown!==down)throw new Error('input changed');
                thisLayer.origin=new Vec3(++n,engine.runtime,0);
            }
            export function cursorDown(e){check(e,true);} export function cursorUp(e){check(e,false);}
            """)])
        _ = dispatch(surface,[sample(10,false,pollingScale:1000),sample(10,true,pollingScale:1000),sample(10,false,pollingScale:1000)]);surface.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        let laterFrame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:3),simulationFrameTime:0.016,sceneTime:3))
        let exact = surface.dispatch(batch:.init(samples:[sample(99,false)],overflowed:false),frame:laterFrame,userPropertiesJSON:"{}")
        out["savedSurfaceFailures"] = exact.failures.count;out["savedSurfaceRetry"] = values(exact)
        surface.finalizeLayerMutations(committing:true)

        // A previously pending click plus new physical input is discarded as
        // a frame, then rebuilt once from the restored pointer batch.
        let (whole,_) = try make([(.origin,clicks)])
        _ = dispatch(whole,click(10));whole.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        let before = whole.edgeStateSnapshot()
        out["droppedCandidate"] = values(dispatch(whole,click(20)))
        whole.restoreEdgeState(before);whole.finalizeLayerMutations(committing:false)
        out["wholeRetry"] = values(dispatch(whole,click(20)))
        whole.finalizeLayerMutations(committing:true)
        out["wholeQuiet"] = dispatch(whole,[sample(20,false)]).ownerEffects.isEmpty
        whole.finalizeLayerMutations(committing:true)

        // Incomplete new raw input cannot erase an older complete pending click.
        let (overflow,_) = try make([(.origin,clicks)])
        _ = dispatch(overflow,click(10));overflow.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["rawOverflow"] = dispatch(overflow,[sample(77,false)],overflow:true).inputBatchOverflowed
        overflow.finalizeLayerMutations(committing:true)
        out["afterRawOverflow"] = values(dispatch(overflow,[sample(77,false)]))
        overflow.finalizeLayerMutations(committing:true)

        // Borrowed cursor events share the later vector result. A recoverable
        // update failure retries, and accepted events are confirmed by cursor.
        let (borrowed,owners) = try make([(.origin,clicks+"\nlet updates=0; export function update(v){if(++updates===1)return {};return v;}")],borrowed:true)
        _ = dispatch(borrowed,click(10))
        let update = owners[0].evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        if case let .failure(f) = update {out["borrowedUpdateFailure"] = f.code}
        borrowed.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()]);owners[0].discardLayerMutations()
        out["borrowedRetry"] = values(dispatch(borrowed,[sample(10,false)]))
        borrowed.finalizeLayerMutations(committing:true);owners[0].commitLayerMutations()
        out["borrowedQuiet"] = dispatch(borrowed,[sample(10,false)]).ownerEffects.isEmpty
        borrowed.finalizeLayerMutations(committing:true);owners[0].commitLayerMutations()

        // A permanent owner fuse cannot be revived by an old edge snapshot.
        let (disabled,disabledOwners) = try make([(.origin,clicks+"\nexport function update(v){throw new Error('stop');}")],borrowed:true)
        _ = dispatch(disabled,click(10));disabled.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()]);disabledOwners[0].discardLayerMutations()
        let saved = disabled.edgeStateSnapshot()
        _ = disabledOwners[0].evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        let dead = dispatch(disabled,[sample(10,false)]);out["disabledFailure"] = dead.failures[target()]?.code ?? "none"
        disabled.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        disabled.restoreEdgeState(saved);disabled.finalizeLayerMutations(committing:false)
        out["disabledQuiet"] = dispatch(disabled,[sample(10,false)]).failures.isEmpty

        // Refuse an entire overflowing target before executing a partial press
        // sequence. Another target on that very layer remains eligible.
        let (budget,budgetOwners) = try make([(.origin,clicks+"\nexport function update(v){return v;}"),(.scale,"export function cursorEnter(e){thisLayer.origin=new Vec3(900,0,0);}")],borrowed:true)
        let crowded = dispatch(budget,(0..<4097).flatMap{_ in click(10)})
        out["budgetFailure"] = crowded.failures[target()]?.code ?? "none";out["budgetUnsafe"] = values(crowded);out["budgetPeer"] = values(crowded,.scale)
        budget.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["budgetQuiet"] = dispatch(budget,[sample(10,false)]).failures.isEmpty
        let budgetUpdate = budgetOwners[0].evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        if case let .failure(f) = budgetUpdate { out["budgetBorrowedFailure"] = f.code } else { out["budgetBorrowedFailure"] = "none" }
        let (burst,_) = try make([(.origin,"""
            let n=0;function add(){thisLayer.origin=new Vec3(++n,0,0);}
            export function cursorEnter(e){add();} export function cursorDown(e){add();}
            export function cursorUp(e){add();} export function cursorClick(e){add();}
            """)])
        let burstResult = dispatch(burst,(0..<170).flatMap{_ in click(10)})
        out["burstValue"] = values(burstResult);out["burstFailures"] = burstResult.failures.count
        burst.finalizeLayerMutations(committing:true)
        let (accumulated,_) = try make([(.origin,"export function cursorClick(e){}")])
        var accumulatedFailure = "none"
        for index in 0..<65 {
            let result = dispatch(accumulated,(0..<64).flatMap{_ in click(10)})
            if let failure = result.failures[target()] { accumulatedFailure = failure.code;out["accumulatedFailureBatch"] = index+1 }
            accumulated.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        }
        out["accumulatedFailure"] = accumulatedFailure
        out["accumulatedPendingCleared"] = accumulated.edgeStateSnapshot().pendingEvents.isEmpty
        let (invalidated,_) = try make([(.origin,clicks)])
        _ = dispatch(invalidated,click(10));invalidated.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()]);invalidated.invalidate()
        out["invalidatedQuiet"] = dispatch(invalidated,[]).ownerEffects.isEmpty
        let (ended,_) = try make([(.origin,clicks)])
        _ = dispatch(ended,click(10));ended.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        _ = ended.teardown(frame:frame,userPropertiesJSON:"{}")
        out["teardownPendingEmpty"] = ended.edgeStateSnapshot().pendingEvents.isEmpty
        print(String(data:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class CursorOwnerTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-cursor-owner-test-") as temp:
            binary=compile_vector_harness(Path(temp),HARNESS,"cursor-owner",
                extra_swift_sources=(SCENE / "Systems/Script/SceneScriptMediaFrameCoordinator.swift",))
            run=subprocess.run([str(binary)],capture_output=True,text=True,check=True)
            cls.result=json.loads(run.stdout.strip().splitlines()[-1])

    def test_rejected_same_layer_target_retries_exact_input_without_replaying_peer(self):
        self.assertEqual(self.result["first"],[1,0,100]);self.assertEqual(self.result["firstPeer"],[1,0,100])
        self.assertEqual(self.result["retried"],[2,10,100]);self.assertEqual(self.result["retriedPeer"],[])
        self.assertTrue(self.result["confirmedQuiet"])

    def test_callback_only_boolean_cursor_transports_puppet_commands_through_real_admission(self):
        for mode in ("normal", "twice"):
            with self.subTest(mode=mode):
                self.assertTrue(all(self.result["puppetCursor"][mode]["facts"].values()), self.result["puppetCursor"][mode])

    def test_cursor_puppet_commands_keep_throw_late_rejection_and_frame_rollback_local(self):
        for mode in ("throw", "late", "rejected", "whole"):
            with self.subTest(mode=mode):
                self.assertTrue(all(self.result["puppetCursor"][mode]["facts"].values()), self.result["puppetCursor"][mode])

    def test_cursor_puppet_registrations_count_callback_deltas(self):
        self.assertEqual(self.result["puppetRegistrationDeltas"], [0, 2, 1, 0, 1])

    def test_init_failure_preserves_entire_press_release_sequence(self):
        self.assertEqual(self.result["earlyFailure"],"bad-return")
        self.assertEqual(self.result["earlyRetry"],[1234,0,0])
        self.assertEqual(self.result["upOnlyRetry"],[15,0,0])

    def test_saved_event_and_surface_inputs_use_current_frame_clock(self):
        self.assertEqual(self.result["savedSurfaceFailures"],0)
        self.assertEqual(self.result["savedSurfaceRetry"],[4,3,0])

    def test_primary_button_is_numeric_zero_for_move_down_up_and_click(self):
        self.assertEqual(len(self.result["primaryButton"]), 2)
        for case in self.result["primaryButton"]:
            with self.subTest(variant=case["variant"]):
                inside = case["inside"]
                self.assertEqual(inside["failures"], [])
                self.assertEqual(inside["value"], [12134, 21122, 1])
                self.assertEqual(inside["peer"], [2, 1, 0])
                self.assertTrue(inside["quietAfter"])

    def test_primary_button_guards_keep_outside_click_boundaries_and_peer(self):
        for case in self.result["primaryButton"]:
            with self.subTest(variant=case["variant"]):
                outside = case["outsidePress"]
                self.assertEqual(outside["failures"], [])
                self.assertEqual(outside["value"], [])
                self.assertEqual(outside["peer"], [])
                self.assertTrue(outside["quietAfter"])
                released = case["releaseOutside"]
                self.assertEqual(released["failures"], [])
                self.assertEqual(released["value"], [213, 112, 0])
                self.assertEqual(released["peer"], [1, 11, 1])
                self.assertTrue(released["quietAfter"])

    def test_failed_init_keeps_cached_target_and_later_click_without_repeating_init(self):
        for case in self.result["failedInitCursor"]:
            with self.subTest(variant=case["variant"],scenario=case["scenario"]):
                self.assertEqual(case["firstCode"], "init-exception")
                self.assertEqual(case["firstValue"], [])
                self.assertTrue(case["initTerminal"])
                self.assertEqual(case["failures"], [])
                self.assertTrue(case["quiet"])
                if case["scenario"] == "inside":
                    self.assertEqual(case["firstPeer"], [1, 0, 0])
                    self.assertEqual(case["value"], [1, 1, 10])
                    self.assertIs(case["visibility"], False)
                else:
                    self.assertEqual(case["value"], [])
                    self.assertEqual(case["firstPeer"], [])

    def test_later_cursor_exception_still_fuses_only_failed_owner(self):
        for case in self.result["failedInitCursor"]:
            if case["scenario"] == "inside":
                with self.subTest(variant=case["variant"]):
                    self.assertEqual(case["laterCode"], "exception")
                    self.assertEqual(case["laterValue"], [])
                    self.assertEqual(case["laterPeer"], [2, 0, 0])
                    self.assertEqual(case["fusedValue"], [])
                    self.assertEqual(case["fusedPeer"], [3, 0, 0])

    def test_whole_frame_restore_does_not_duplicate_prior_or_new_events(self):
        self.assertEqual(self.result["droppedCandidate"],[3,10,200])
        self.assertEqual(self.result["wholeRetry"],[5,10,200])
        self.assertTrue(self.result["wholeQuiet"])

    def test_new_raw_overflow_preserves_prior_complete_event(self):
        self.assertTrue(self.result["rawOverflow"])
        self.assertEqual(self.result["afterRawOverflow"],[2,10,100])

    def test_borrowed_update_rejection_retries_and_confirms(self):
        self.assertEqual(self.result["borrowedUpdateFailure"],"bad-return")
        self.assertEqual(self.result["borrowedRetry"],[2,10,100]);self.assertTrue(self.result["borrowedQuiet"])

    def test_permanent_fuse_is_not_revived_by_edge_restore(self):
        self.assertEqual(self.result["disabledFailure"],"disabled");self.assertTrue(self.result["disabledQuiet"])

    def test_pending_budget_rejects_whole_target_and_preserves_peer(self):
        self.assertEqual(self.result["budgetFailure"],"mutation-overflow")
        self.assertEqual(self.result["budgetUnsafe"],[]);self.assertEqual(self.result["budgetPeer"],[900,0,0])
        self.assertTrue(self.result["budgetQuiet"])
        self.assertIn(self.result["budgetBorrowedFailure"],["disabled","stale-owner"])

    def test_full_fresh_input_batch_can_expand_past_256_callbacks(self):
        self.assertEqual(self.result["burstValue"],[511,0,0]);self.assertEqual(self.result["burstFailures"],0)

    def test_repeated_legal_batches_bound_rejected_event_backlog(self):
        self.assertEqual(self.result["accumulatedFailure"],"mutation-overflow")
        self.assertEqual(self.result["accumulatedFailureBatch"],65)
        self.assertTrue(self.result["accumulatedPendingCleared"])

    def test_invalidate_and_teardown_clear_pending_input(self):
        self.assertTrue(self.result["invalidatedQuiet"]);self.assertTrue(self.result["teardownPendingEmpty"])

    def test_bone_matrix_journal_preserves_cross_owner_callback_order(self):
        facts = self.result["boneOrder"]
        self.assertEqual((facts["failures"], facts["owners"]), (0, 2))
        self.assertEqual((facts["callbackTrace"], facts["ownReadback"]), (123, 30))
        self.assertEqual(facts["grouped"], [[10, 30], [20]])
        self.assertEqual(facts["ordered"], [10, 20, 30])
        self.assertEqual(facts["kinds"], ["matrix"] * 3)
        self.assertTrue(all(epoch > 0 for epoch in facts["epochs"]))
        self.assertTrue(all(a < b for a, b in zip(facts["epochs"], facts["epochs"][1:])))
        self.assertEqual(facts["ordinals"], [0, 0, 0])

    def test_bone_matrix_journal_preserves_same_callback_multiple_writes(self):
        facts = self.result["boneBurst"]
        self.assertEqual((facts["failures"], facts["owners"]), (0, 2))
        self.assertEqual(facts["ordered"], [10, 11, 20, 30])
        self.assertEqual(facts["ordinals"], [0, 1, 0, 0])
        self.assertEqual(facts["epochs"][0], facts["epochs"][1])
        self.assertLess(facts["epochs"][1], facts["epochs"][2])
        self.assertLess(facts["epochs"][2], facts["epochs"][3])

    def test_bone_matrix_journal_throw_and_late_owner_exclusion_keep_peer_order(self):
        for name, expected in (("boneOrder", [10, 30]), ("boneBurst", [10, 11, 30])):
            self.assertEqual(self.result[name]["filtered"], expected)
        thrown = self.result["boneThrow"]
        self.assertEqual((thrown["failures"], thrown["owners"]), (1, 1))
        self.assertEqual(thrown["peerFailure"], "exception")
        self.assertEqual(thrown["ordered"], [10, 30])
        self.assertEqual(thrown["ordinals"], [0, 0])
        self.assertLess(thrown["epochs"][0], thrown["epochs"][1])

    def test_bone_impulses_share_cross_owner_matrix_order_and_exclusion(self):
        facts = self.result["boneMixed"]
        self.assertEqual((facts["failures"], facts["owners"]), (0, 2))
        self.assertEqual(facts["ordered"], [10, 11, 20, 20, 29, 30])
        self.assertEqual(facts["kinds"], ["matrix", "impulse", "impulse", "matrix", "impulse", "matrix"])
        self.assertEqual(facts["ordinals"], [0, 1, 0, 1, 0, 1])
        self.assertEqual(facts["filtered"], [10, 11, 29, 30])
        self.assertEqual(facts["filteredKinds"], ["matrix", "impulse", "impulse", "matrix"])
        thrown = self.result["boneMixedThrow"]
        self.assertEqual((thrown["failures"], thrown["owners"]), (1, 1))
        self.assertEqual(thrown["peerFailure"], "exception")
        self.assertEqual(thrown["ordered"], facts["filtered"])
        self.assertEqual(thrown["kinds"], facts["filteredKinds"])

if __name__ == "__main__": unittest.main()
