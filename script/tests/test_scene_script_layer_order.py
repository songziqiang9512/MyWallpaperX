"""Real QuickJS -> Swift mutation/candidate-order synchronization.

The shared compiler supplies external descriptor metadata. This harness only
constructs dynamic descriptor records; VM execution, mutation decoding,
coalescing, admission, topology order and rollback are product code.
"""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import SWIFT_PREAMBLE, compile_vector_harness

PREAMBLE = SWIFT_PREAMBLE[:SWIFT_PREAMBLE.index("extension SceneRenderDescriptor.Layer {")] + r'''
extension SceneRenderDescriptor.Layer {
    static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
        guard let pointSize = SceneTextDescriptor.renderedPointSize(mutation.pointSize) else { return nil }
        return .init(id: mutation.layerID, layerIndex: mutation.orderIndex, name: nil,
            visible: mutation.visible, originXYZ: [0,0,0], scaleXYZ: [1,1,1], alpha: mutation.alpha,
            effects: [], contentKind: "text", text: mutation.text,
            textStyle: .init(fontPath: mutation.font, colorRGB: [1,1,1], pointSize: pointSize))
    }
    static func preparedResourceLayer(_ mutation: SceneScriptLayerMutation,
                             template: SceneScriptPreparedResourceLayerTemplate) -> Self? {
        var layer = Self(id: mutation.layerID, layerIndex: mutation.orderIndex,
            name: nil, visible: mutation.visible, originXYZ: [0,0,0],
            scaleXYZ: [1,1,1], alpha: mutation.alpha, effects: [])
        layer.imagePath = template.modelPath
        return layer
    }
}
'''
SCENE_ROOT = Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene"
EXTRA_SOURCES = (
    SCENE_ROOT / "Systems/Text/SceneTextDescriptor.swift",
)


HARNESS = r'''
// External JSON carrier; render normalization is the production text owner.
enum SceneDocumentLoader {
    static func floatValue(_ value: Any?) -> Float? { (value as? NSNumber)?.floatValue }
    static func floatVector(_ value: Any?) -> [Float]? { (value as? [NSNumber])?.map(\.floatValue) }
}
@main enum Harness {
    static func setup(_ path: String, labels: [String] = ["A","B","C"]) throws -> (SceneRenderDescriptor,SceneScriptQuickJSDomain,SceneScriptDynamicLayerRuntime) {
        var descriptor = SceneRenderDescriptor(layers: labels.indices.map { index in
            let id = 101 + index
            return .init(id:id,layerIndex:index,name:labels[index],visible:true,
                  originXYZ:[0,0,0],scaleXYZ:[1,1,1],alpha:1,effects:[])
        })
        descriptor.modelMaterialLinks = [.init(modelPath:path,materialPath:"material")]
        let catalog: [String:SceneScriptPreparedResourceLayerTemplate] = [path:.init(modelPath:path,renderSizeWH:[200,100])]
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.configurePreparedResourceLayerCatalog(catalog)
        try domain.publishLayerSnapshot(.empty(frameIndex:1),descriptor:descriptor)
        let runtime = SceneScriptDynamicLayerRuntime(descriptor:descriptor,
            authoredMutationLayerIDs:[101,102,103],preparedResourceLayerTemplates:catalog,
            layerOrderProjection:{ domain.projectPendingLayerOrder(accepting:$0) })
        return (descriptor,domain,runtime)
    }
    static func owner(_ domain: SceneScriptQuickJSDomain, _ layerID: Int, _ source: String) throws -> SceneScriptValueOwner {
        try .init(domain:domain,source:source,target:.layer(layerID:layerID,field:.color),
            valueType:.vector3,effectNames:[],allowsStatefulLayerSideEffects:true,
            generation:1,budget:.default)
    }
    static func evaluate(_ owner: SceneScriptValueOwner, _ input: Double = 0) throws -> SceneScriptValueEvaluation {
        try owner.evaluate(input:.vector3(input,0,0),frame:.init(timing:.init(
            wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:1/60,sceneTime:input)),
            scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
    }
    static func effects(_ value: SceneScriptValueEvaluation, _ owner: SceneScriptValueOwner) -> SceneScriptOwnerEffects {
        var effects = SceneScriptOwnerEffects(ownerTarget:owner.target,
            materialFunctionMutations:[],animationMutations:[],layerMutations:[],mediaPlaybackCommands:[])
        effects.append(value)
        effects.layerMutations = SceneScriptLayerMutation.coalescing(effects.layerMutations)
        return effects
    }
    static func apply(_ effects: [SceneScriptOwnerEffects], _ runtime: SceneScriptDynamicLayerRuntime) -> SceneScriptLayerMutationApplyOutcome {
        let admission = runtime.preflightOwnerEffects(effects)
        runtime.commit(admission.layerPlan)
        return admission.layerPlan.outcome
    }
    static func cOrder(_ domain: SceneScriptQuickJSDomain, observerLayerID: Int = 101) throws -> [String] {
        let observer = try SceneScriptValueOwner(domain:domain,source:"""
            export function update(v){return thisScene.enumerateLayers().map(layer=>layer.name).join(',');}
            """,target:.text(layerID:observerLayerID,field:.content),valueType:.string,effectNames:[],generation:1,budget:.default)
        let value = try observer.evaluate(input:.string(""),frame:.init(timing:.init(
            wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:1/60,sceneTime:0)),
            scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
        guard case let .string(order) = value.value else { fatalError("order observer") }
        return order.split(separator:",").map(String.init)
    }
    static func swiftOrder(_ runtime: SceneScriptDynamicLayerRuntime, _ dynamic: [Int:String] = [:]) -> [String] {
        let names = [101:"A",102:"B",103:"C",104:"D"].merging(dynamic){_,new in new}
        return runtime.snapshot().renderOrderLayerIDs.map { names[$0] ?? "unknown" }
    }
    static func sortAndField(_ statements: String) throws -> [String:Any] {
        let (_,domain,runtime) = try setup("models/order.json")
        let value = try owner(domain,102,"export function update(v){\(statements);return new Vec3(1,1,1);}")
        let effect = effects(try evaluate(value),value)
        let mutations = effect.layerMutations
        let outcome = apply([effect],runtime)
        let result: [String:Any] = ["c":try cOrder(domain),"swift":swiftOrder(runtime),
            "failures":outcome.failures.count,"alpha":runtime.snapshot().authoredLayerValues[.layer(layerID:102,field:.alpha)] == .scalar(0.5),
            "mutationCount":mutations.count,"fields":mutations.map { $0.fields.rawValue },"indices":mutations.map(\.orderIndex),
            "carrierKept":effect.layerTopologyOwnerIdentity != nil]
        value.discardLayerMutations()
        return result
    }
    static func twoCreates(_ reverse: Bool, _ path: String, _ variable: String) throws -> [String:Any] {
        let (_,domain,runtime) = try setup(path)
        let first = try owner(domain,101,"""
            export function update(v){const \(variable)=thisScene.createLayer({name:'X',image:'\(path)',size:'200 100'});
                thisScene.sortLayer(\(variable),thisScene.getLayerIndex(thisScene.getLayer('C')));return new Vec3(1,1,1);}
            """)
        let second = try owner(domain,103,"""
            export function update(v){const peer=thisScene.createLayer({name:'Y',image:'\(path)',size:new Vec2(100*2,50+50)});
                thisScene.sortLayer(peer,thisScene.getLayerIndex(thisScene.getLayer('A')));return new Vec3(1,1,1);}
            """)
        var mutations:[SceneScriptLayerMutation] = []
        var packages:[SceneScriptOwnerEffects] = []
        var names:[Int:String] = [:]
        for value in reverse ? [second,first] : [first,second] {
            let effect = effects(try evaluate(value),value)
            packages.append(effect)
            let batch = effect.layerMutations
            names[batch.first(where:\.isDynamic)!.layerID] = value === first ? "X":"Y"
            mutations += batch
        }
        let outcome = apply(packages,runtime)
        let result:[String:Any] = ["c":try cOrder(domain),"swift":swiftOrder(runtime,names),
            "failures":outcome.failures.count,"indices":mutations.filter(\.isDynamic).map(\.orderIndex)]
        first.discardLayerMutations();second.discardLayerMutations()
        return result
    }
    static func propertyOnly() throws -> [String:Any] {
        let (_,domain,runtime) = try setup("models/order.json")
        let creator = try owner(domain,101,"""
            let existing;
            export function update(v){if(v.x===0){existing=thisScene.createLayer({name:'X',image:'models/order.json'});
                thisScene.sortLayer(existing,1);}else{existing.alpha=0.5;}return new Vec3(1,1,1);}
            """)
        let initialEffect = effects(try evaluate(creator),creator)
        let initial = initialEffect.layerMutations
        _ = apply([initialEffect],runtime);creator.commitLayerMutations()
        let names = [initial.first(where:\.isDynamic)!.layerID:"X"]
        let initialOrder = swiftOrder(runtime,names)
        let property = effects(try evaluate(creator,1),creator)
        let sorter = try owner(domain,103,"""
            export function update(v){thisScene.sortLayer(thisLayer,0);return new Vec3(1,1,1);}
            """)
        let sort = effects(try evaluate(sorter),sorter)
        let outcome = apply([property,sort],runtime)
        let result:[String:Any] = ["initial":initialOrder,"c":try cOrder(domain),
            "swift":swiftOrder(runtime,names),"failures":outcome.failures.count]
        creator.discardLayerMutations();sorter.discardLayerMutations()
        return result
    }

    static func lateRejection() throws -> [String:Any] {
        let (_,domain,runtime) = try setup("models/order.json")
        let first = try owner(domain,101,"export function update(v){thisScene.sortLayer(thisLayer,2);return new Vec3(1,1,1);}")
        let peer = try owner(domain,102,"export function update(v){thisScene.sortLayer(thisLayer,1);thisScene.sortLayer(thisScene.getLayer('C'),1);return new Vec3(1,1,1);}")
        let packages = try [effects(evaluate(first),first),effects(evaluate(peer),peer)]
        let before = try cOrder(domain)
        let settled = runtime.preflightOwnerEffectsToFixedPoint(packages) { _, _ in [first.target] }
        runtime.commit(settled.admission.layerPlan)
        first.discardLayerMutations();peer.commitLayerMutations()
        let committed = swiftOrder(runtime)
        let after = try cOrder(domain)
        let cleared = first.pendingLayerTopologyIdentity == nil && peer.pendingLayerTopologyIdentity == nil
            && mwx_scene_quickjs_domain_has_pending_layer_topology(domain.handle) == 0
        _ = apply([],runtime)
        return ["before":before,"c":after,"swift":committed,
            "firstRejected":settled.externallyRejectedOwners.contains(first.target),
            "healthyPeer":settled.admission.admittedEffects.contains { $0.ownerTarget == peer.target },
            "cleared":cleared,"emptyCadenceStable":swiftOrder(runtime) == committed]
    }
    static func interleavedCallbacks() throws -> [[String:Any]] {
        let sharedFirst = """
            export function update(v){
                if(v.x===0)thisScene.sortLayer(thisScene.getLayer('C'),0);
                else thisScene.sortLayer(thisScene.getLayer('B'),2);
                thisScene.getLayer('C').alpha=0.5;return new Vec3(1,1,1);}
            """
        let sharedPeer = """
            export function update(v){thisScene.sortLayer(thisScene.getLayer('C'),2);
                thisLayer.alpha=0.25;return new Vec3(1,1,1);}
            """
        return try [
            (first:"export function update(v){thisScene.sortLayer(thisLayer,v.x===0?2:1);return new Vec3(1,1,1);}",
             peer:"export function update(v){thisScene.sortLayer(thisScene.getLayer('C'),0);return new Vec3(1,1,1);}",rejectFirst:false),
            (first:sharedFirst,peer:sharedPeer,rejectFirst:false),
            (first:sharedFirst,peer:sharedPeer,rejectFirst:true),
        ].map { scripts in
            let (_,domain,runtime) = try setup("models/order.json")
            let first = try owner(domain,101,scripts.first)
            let peer = try owner(domain,102,scripts.peer)
            var firstEffects = effects(try evaluate(first),first)
            let peerEffects = effects(try evaluate(peer),peer)
            firstEffects.append(try evaluate(first,1))
            firstEffects.layerMutations = SceneScriptLayerMutation.coalescing(firstEffects.layerMutations)
            let packages = [firstEffects,peerEffects]
            let before = try cOrder(domain)
            let settled = runtime.preflightOwnerEffectsToFixedPoint(packages) { _, _ in
                scripts.rejectFirst ? [first.target] : []
            }
            runtime.commit(settled.admission.layerPlan)
            if scripts.rejectFirst { first.discardLayerMutations() }
            else { first.commitLayerMutations() }
            peer.commitLayerMutations()
            return ["before":before,"c":try cOrder(domain),"swift":swiftOrder(runtime),
                "failures":settled.admission.rejectedOwners.count,
                "dtoCounts":packages.map { $0.layerMutations.count },
                "propertyFieldsOnly":packages.flatMap(\.layerMutations).allSatisfy { $0.fields == .alpha },
                "alphaC":runtime.snapshot().authoredLayerValues[.layer(layerID:103,field:.alpha)] == .scalar(0.5),
                "alphaB":runtime.snapshot().authoredLayerValues[.layer(layerID:102,field:.alpha)] == .scalar(0.25),
                "firstRejected":settled.externallyRejectedOwners.contains(first.target),
                "healthyPeer":settled.admission.admittedEffects.contains { $0.ownerTarget == peer.target },
                "carriersKept":packages.allSatisfy { $0.layerTopologyOwnerIdentity != nil },
                "cleared":first.pendingLayerTopologyIdentity == nil && peer.pendingLayerTopologyIdentity == nil
                    && mwx_scene_quickjs_domain_has_pending_layer_topology(domain.handle) == 0]
        }
    }
    static func destroyShift() throws -> [String:Any] {
        let (_,domain,runtime) = try setup("models/order.json")
        let existing = try owner(domain,101,"""
            let previous;export function update(v){if(v.x===0){previous=thisScene.createLayer({name:'Y',image:'models/order.json'});
                thisScene.sortLayer(previous,0);}else{thisScene.destroyLayer(previous);}return new Vec3(1,1,1);}
            """)
        let initial = effects(try evaluate(existing),existing)
        _ = apply([initial],runtime);existing.commitLayerMutations()
        let xOwner = try owner(domain,103,"""
            export function update(v){const fresh=thisScene.createLayer({name:'X',image:'models/order.json'});
                thisScene.sortLayer(fresh,1);return new Vec3(1,1,1);}
            """)
        let xEffects = effects(try evaluate(xOwner),xOwner)
        let removed = effects(try evaluate(existing,1),existing)
        let names = [initial.layerMutations.first(where:\.isDynamic)!.layerID:"Y",
                     xEffects.layerMutations.first(where:\.isDynamic)!.layerID:"X"]
        _ = apply([xEffects,removed],runtime)
        let result:[String:Any] = ["c":try cOrder(domain),"swift":swiftOrder(runtime,names)]
        xOwner.commitLayerMutations();existing.commitLayerMutations()
        return result
    }
    static func clippedBooleanCarrier() throws -> [String:Any] {
        let (descriptor,domain,runtime) = try setup("models/order.json")
        let target = SceneDynamicTarget.layer(layerID:102,field:.visibility)
        let binding = SceneScriptBindingIR(source:"""
            export function init(v){thisScene.sortLayer(thisLayer,0);return true;}
            export function mediaPlaybackChanged(){thisLayer.visible=false;}
            export function update(v){return true;}
            """,owner:.init(kind:.object,objectIndex:1,objectID:102,effectIndex:nil,effectID:nil,passIndex:nil,passID:nil),
            targetPath:[.key("objects"),.index(1),.key("visible")],properties:[:],authoredValue:.bool(true),
            valueType:.boolean,wrapperKeys:["script","value"])
        let program = SceneScriptVectorProgram.compile(domain:domain,descriptor:descriptor,
            scriptBindings:[binding],userPropertyDefinitions:[],generation:1)
        let frame = program.evaluate(inputs:[target:.bool(true)],effectivePropertyValues:[:],
            frame:.init(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:1/60,sceneTime:0)),
            mediaPlaybackEvent:.init(state:1,generation:1))
        let outcome = apply(frame.ownerEffects,runtime)
        let result:[String:Any] = ["c":try cOrder(domain),"swift":swiftOrder(runtime),
            "programFailures":frame.failures.count,"layerDTOs":frame.layerMutations.count,
            "carrierKept":frame.ownerEffects.contains { $0.layerTopologyOwnerIdentity != nil },
            "failures":outcome.failures.count]
        program.finalizeLayerMutations(committing:true)
        return result
    }

    static func authoredTombstone() throws -> [String:Any] {
        let (descriptor,domain,runtime) = try setup("models/order.json",labels:["A","B","C","D"])
        let remover = try owner(domain,102,"export function update(v){thisScene.destroyLayer(thisScene.getLayer('A'));return new Vec3(1,1,1);}")
        let sorter = try owner(domain,104,"export function update(v){thisScene.sortLayer(thisLayer,2);return new Vec3(1,1,1);}")
        let packages = try [effects(evaluate(remover),remover),effects(evaluate(sorter),sorter)]
        let raw = try cOrder(domain)
        let settled = runtime.preflightOwnerEffects(packages)
        runtime.commit(settled.layerPlan)
        remover.commitLayerMutations();sorter.commitLayerMutations()
        try domain.publishLayerSnapshot(.empty(frameIndex:2),descriptor:descriptor,
            destroyedAuthoredLayerIDs:runtime.snapshot().destroyedAuthoredLayerIDs)
        return ["raw":raw,"c":try cOrder(domain,observerLayerID:102),
            "swift":swiftOrder(runtime),"removedA":runtime.snapshot().destroyedAuthoredLayerIDs.contains(101),
            "failures":settled.rejectedOwners.count]
    }
    static func thrownSort() throws -> [String:Any] {
        let (_,domain,runtime) = try setup("models/order.json")
        let rejected = try owner(domain,102,"export function update(v){thisScene.sortLayer(thisLayer,0);thisLayer.alpha=0.5;throw Error('order-owner-threw');}")
        var failed = false
        do {_ = try evaluate(rejected)}catch{failed=String(describing:error).contains("order-owner-threw")}
        let afterThrow = try cOrder(domain)
        let cleared = rejected.pendingLayerTopologyIdentity == nil
            && mwx_scene_quickjs_domain_has_pending_layer_topology(domain.handle) == 0
        let healthy = try owner(domain,103,"export function update(v){thisScene.sortLayer(thisLayer,0);return new Vec3(1,1,1);}")
        _ = apply([effects(try evaluate(healthy),healthy)],runtime)
        let result:[String:Any] = ["failed":failed,"cleared":cleared,"afterThrow":afterThrow,
            "c":try cOrder(domain),"swift":swiftOrder(runtime)]
        healthy.commitLayerMutations()
        return result
    }

    static func returnControlsContinuation(_ path: String, _ variable: String) throws -> [String:Any] {
        let (_,domain,runtime) = try setup(path)
        let successful = try owner(domain,102,"""
            export function update(v){const \(variable)=thisScene.sortLayer(thisLayer,1-1);
                if(\(variable)!==true || typeof \(variable)!=='boolean')throw Error('normal-sort-return');
                if(\(variable)===true){thisLayer.alpha=0.5;
                    const following=thisScene.sortLayer(thisScene.getLayer('C'),thisScene.getLayerIndex(thisScene.getLayer('A')));
                    if(following!==true)throw Error('second-sort-return');}
                return new Vec3(1,1,1);}
            """)
        _ = apply([effects(try evaluate(successful),successful)],runtime)
        successful.commitLayerMutations()
        let settled = swiftOrder(runtime)
        let alpha = runtime.snapshot().authoredLayerValues[.layer(layerID:102,field:.alpha)] == .scalar(0.5)
        let noop = try owner(domain,101,"export function update(v){if(thisScene.sortLayer(thisLayer,2)!==undefined)throw Error('unmeasured-noop-exit-changed');return new Vec3(1,1,1);}")
        let untouched = try evaluate(noop)
        let noOpPreserved = untouched.layerMutations.isEmpty && untouched.layerTopologyOwnerIdentity == nil
        noop.discardLayerMutations()
        let throwing = try owner(domain,101,"""
            export function update(v){if(thisScene.sortLayer(thisScene.getLayer('B'),2)!==true)throw Error('return-missing');
                thisLayer.alpha=0.1;throw Error('return-controlled-throw');}
            """)
        var throwPreserved = false
        do{_ = try evaluate(throwing)}catch{throwPreserved=String(describing:error).contains("return-controlled-throw")}
        let invalid = try owner(domain,101,"""
            export function update(v){
                for(const [layer,index] of [[thisLayer,-1],[thisLayer,0.5],[thisScene.getLayer('missing'),0]]){
                    let caught=false,successBranch=false;
                    try{if(thisScene.sortLayer(layer,index)===true)successBranch=true;}
                    catch(e){caught=e instanceof TypeError;}
                    if(!caught || successBranch)throw Error('invalid-sort-success');}
                thisLayer.alpha=0.75;return new Vec3(1,1,1);}
            """)
        let invalidEffects = effects(try evaluate(invalid),invalid)
        _ = apply([invalidEffects],runtime)
        let result:[String:Any] = ["c":try cOrder(domain),"swift":swiftOrder(runtime),
            "invalidHadNoTopology":invalidEffects.layerTopologyOwnerIdentity == nil,
            "settled":settled,"typedAlpha":alpha,"noOpPreserved":noOpPreserved,
            "throwPreserved":throwPreserved,"invalidDidNotEnterSuccess":runtime.snapshot().authoredLayerValues[.layer(layerID:101,field:.alpha)] == .scalar(0.75)]
        invalid.commitLayerMutations()
        return result
    }
    static func unavailableProjection() throws -> [String:Any] {
        let (descriptor,domain,_) = try setup("models/order.json")
        let value = try owner(domain,102,"export function update(v){thisScene.sortLayer(thisLayer,0);return new Vec3(1,1,1);}")
        let effect = effects(try evaluate(value),value)
        let missing = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[])
        let missingAdmission = missing.preflightOwnerEffects([effect])
        let nilProvider = SceneScriptDynamicLayerRuntime(descriptor:descriptor,authoredMutationLayerIDs:[],
            layerOrderProjection:{_ in .success(nil)})
        let nilAdmission = nilProvider.preflightOwnerEffects([effect])
        value.discardLayerMutations()
        let inactive = domain.projectPendingLayerOrder(accepting:[effect.layerTopologyOwnerIdentity!])
        let inactiveFailed:Bool
        if case .failure = inactive {inactiveFailed=true}else{inactiveFailed=false}
        return ["missingRejected":missingAdmission.rejectedOwners.count == 1,
            "nilRejected":nilAdmission.rejectedOwners.count == 1,"inactiveRejected":inactiveFailed,
            "unchanged":swiftOrder(missing) == ["A","B","C"] && swiftOrder(nilProvider) == ["A","B","C"],
            "discardCleared":mwx_scene_quickjs_domain_has_pending_layer_topology(domain.handle) == 0]
    }
    static func shortLivedBirth(_ path: String, _ variable: String,
                               splitCallbacks: Bool = false, rejectBirth: Bool = false) throws -> [String:Any] {
        let (_,domain,runtime) = try setup(path)
        let creator = try owner(domain,101,"""
            let \(variable);export function update(v){
                if(v.x===0){\(variable)=thisScene.createLayer({name:'temporary',image:'\(path)',size:new Vec2(200,100)});
                    if(!\(splitCallbacks)){thisScene.destroyLayer(\(variable));}}
                else if(v.x===1){thisScene.destroyLayer(\(variable));}
                else{const replacement=thisScene.createLayer({name:'replacement',image:'\(path)'});
                    let stale=false;try{thisScene.destroyLayer(\(variable));}catch(e){stale=e instanceof TypeError;}
                    if(!stale)throw Error('old-birth-handle-revived');thisScene.destroyLayer(replacement);}
                return new Vec3(1,1,1);}
            """)
        var birth = effects(try evaluate(creator),creator)
        if splitCallbacks {
            birth.append(try evaluate(creator,1))
            birth.layerMutations = SceneScriptLayerMutation.coalescing(birth.layerMutations)
        }
        let born = birth.layerMutations.first(where:\.isDynamic)!
        var unknown = born
        unknown.fields.remove(.created)
        let unknownPlan = runtime.preflightIsolatingOwners([unknown])
        let unknownRejected = unknownPlan.outcome.failures.contains {
            if case .staleOwner = $0.failure { return true }; return false
        }
        var missing = birth
        missing.layerMutations = birth.layerMutations.map { $0.resolvingAssetPath(to:"models/unprepared.json") }
        let peer = try owner(domain,102,"export function update(v){thisLayer.alpha=.5;return new Vec3(1,1,1);}")
        let peerEffects = effects(try evaluate(peer),peer)
        let missingAdmission = runtime.preflightOwnerEffects([missing,peerEffects])
        let missingRejectedLocally = missingAdmission.rejectedOwners.map(\.ownerTarget) == [creator.target]
            && missingAdmission.layerPlan.createdDynamicLayerMutations.isEmpty
            && missingAdmission.admittedEffects.map(\.ownerTarget) == [peer.target]
        let originalDefinitionTargets = Set(runtime.authoredLayerDefinitions.map(\.target))
        let fixed = runtime.preflightOwnerEffectsToFixedPoint([birth,peerEffects]) { _, _ in
            rejectBirth ? [creator.target] : []
        }
        let plan = fixed.admission.layerPlan
        let readOnly = runtime.snapshot().dynamicLayers.isEmpty && runtime.snapshot().authoredLayerValues.isEmpty
        runtime.commit(plan)
        if rejectBirth { creator.discardLayerMutations() } else { creator.commitLayerMutations() }
        peer.commitLayerMutations()
        let acceptedBirth = plan.createdDynamicLayerMutations.first
        var oldHandleStayedStale = true
        var nextBirthHasNewIdentity = true
        if !rejectBirth {
            let next = effects(try evaluate(creator,2),creator)
            let nextAdmission = runtime.preflightOwnerEffects([next])
            oldHandleStayedStale = nextAdmission.rejectedOwners.isEmpty
            nextBirthHasNewIdentity = nextAdmission.layerPlan.createdDynamicLayerMutations.first
                .map { $0.layerID != born.layerID && $0.isNewborn && $0.kind == .destroy } ?? false
            runtime.commit(nextAdmission.layerPlan)
            creator.commitLayerMutations()
        }
        return ["birthRecord":born.isNewborn && born.kind == .destroy && born.assetPath == path
                    && born.size == SIMD2<Double>(200,100),
            "candidateBirthCount":plan.createdDynamicLayerMutations.count,
            "candidateResource":rejectBirth || (acceptedBirth?.assetPath == path && acceptedBirth?.kind == .destroy),
            "unknownRejected":unknownRejected,"missingRejectedLocally":missingRejectedLocally,
            "readOnly":readOnly,"noTopologyPublication":runtime.snapshot().dynamicLayers.isEmpty
                && !plan.dynamicTopologyChanged && swiftOrder(runtime) == ["A","B","C"],
            "onlyPeerSchemaGrowth":Set(runtime.authoredLayerDefinitions.map(\.target))
                == originalDefinitionTargets.union([.layer(layerID:102,field:.alpha)]),
            "peerCommitted":runtime.snapshot().authoredLayerValues[.layer(layerID:102,field:.alpha)] == .scalar(0.5),
            "rejectedOwnerAbsent":!rejectBirth || fixed.externallyRejectedOwners == [creator.target],
            "oldHandleStayedStale":oldHandleStayedStale,"nextBirthHasNewIdentity":nextBirthHasNewIdentity,
            "c":try cOrder(domain)]
    }
    static func shortLivedText(_ expression: String, existing: Bool = false) throws -> [String:Any] {
        let (_,domain,runtime) = try setup("models/text-neighbor.json")
        let creator = try owner(domain,101,"""
            let caption;export function update(v){if(v.x===0)caption=thisScene.createLayer({text:'temporary'});
                if(\(existing) && v.x===0)return new Vec3(1,1,1);
                caption.pointsize=\(expression);thisScene.destroyLayer(caption);return new Vec3(1,1,1);}
            """)
        if existing {
            _ = apply([effects(try evaluate(creator),creator)],runtime)
            creator.commitLayerMutations()
        }
        let evaluated: SceneScriptValueEvaluation
        do { evaluated = try evaluate(creator,existing ? 1 : 0) } catch {
            return ["rejected":true,"noPublication":runtime.snapshot().dynamicLayers.isEmpty,
                "noPending":mwx_scene_quickjs_domain_has_pending_layer_topology(domain.handle) == 0,
                "c":try cOrder(domain)]
        }
        let birth = effects(evaluated,creator)
        let revision = runtime.authoredDefinitionRevision
        let admission = runtime.preflightOwnerEffects([birth])
        let record = birth.layerMutations.first(where:\.isDynamic)!
        runtime.commit(admission.layerPlan)
        creator.commitLayerMutations()
        return ["rejected":!admission.rejectedOwners.isEmpty,
            "cleanDestroyMask":record.fields == (existing ? [] : [.created]),"raw":record.pointSize,
            "rendered":SceneRenderDescriptor.Layer.dynamicText(record)?.textStyle?.pointSize ?? -1,
            "candidateBirthCount":admission.layerPlan.createdDynamicLayerMutations.count,
            "noPublication":runtime.snapshot().dynamicLayers.isEmpty && (existing || !admission.layerPlan.dynamicTopologyChanged),
            "noSchemaGrowth":runtime.authoredDefinitionRevision == revision,
            "c":try cOrder(domain)]
    }
    static func main() throws {
        print(String(decoding:try JSONSerialization.data(withJSONObject:[
            "authored":[sortAndField("thisScene.sortLayer(thisLayer,0);thisLayer.alpha=0.5"),
                sortAndField("thisLayer.alpha=0.5;thisScene.sortLayer(thisLayer,0)"),
                sortAndField("thisScene.sortLayer(thisScene.getLayer('B'),1-1);thisLayer.alpha=0.5")],
            "sortOnly":sortAndField("thisScene.sortLayer(thisLayer,0)"),
            "alphaOnly":sortAndField("thisLayer.alpha=0.5"),
            "creates":[twoCreates(false,"models/order.json","newLayer"),twoCreates(false,"models/renamed.json","renamedCopy")],
            "reverse":twoCreates(true,"models/order.json","newLayer"),
            "propertyOnly":propertyOnly(),"late":lateRejection(),"interleaved":interleavedCallbacks(),
            "destroyShift":destroyShift(),"tombstone":authoredTombstone(),"throw":thrownSort(),"carrier":clippedBooleanCarrier(),"missing":unavailableProjection(),
            "returnControls":[returnControlsContinuation("models/order.json","moved"),returnControlsContinuation("models/renamed-return.json","shifted")],
            "manySorts":sortAndField("for(let step=0;step<300;step++){thisScene.sortLayer(thisLayer,step%2===0?0:2);}thisScene.sortLayer(thisLayer,0);thisLayer.alpha=0.5"),
            "shortLived":[shortLivedBirth("models/order.json","temporary"),
                shortLivedBirth("models/renamed-short-lived.json","removed",splitCallbacks:true)],
            "rejectedBirth":shortLivedBirth("models/order.json","withdrawn",rejectBirth:true),
            "shortLivedText":try ["0","1-1","2048","1024*2"].map { try shortLivedText($0) },
            "existingTextDestroy":try ["0","2048"].map { try shortLivedText($0,existing:true) },
            "invalidShortLivedText":try ["NaN","Infinity","'2048'"].map { try shortLivedText($0) } ],options:[.sortedKeys]),as:UTF8.self))
    }
}
'''

class SceneScriptLayerOrderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="scene-layer-order-")
        cls.addClassCleanup(cls.temporary.cleanup)
        binary = compile_vector_harness(Path(cls.temporary.name), HARNESS, "layer-order", preamble=PREAMBLE, extra_swift_sources=EXTRA_SOURCES, whole_module_optimization=True)
        completed = subprocess.run([str(binary)], capture_output=True, text=True)
        if completed.returncode:
            raise AssertionError(completed.stdout + completed.stderr)
        cls.result = json.loads(completed.stdout.strip().splitlines()[-1])

    def test_authored_sort_survives_same_callback_property_write(self) -> None:
        for result in self.result["authored"]:
            self.assertEqual(result["c"], ["B","A","C"])
            self.assertEqual(result["swift"], result["c"])
            self.assertIs(result["alpha"], True)
            self.assertEqual(result["failures"], 0)
            self.assertEqual(result["mutationCount"], 1)

    def test_later_callback_creation_preserves_earlier_shifted_layer_order(self) -> None:
        for result in self.result["creates"]:
            self.assertEqual(result["c"], ["Y","A","B","X","C"])
            self.assertEqual(result["swift"], result["c"])
            self.assertEqual(result["failures"], 0)

    def test_short_lived_birth_keeps_accepted_resource_without_publishing_topology(self) -> None:
        for result in self.result["shortLived"]:
            self.assertEqual(result["candidateBirthCount"], 1)
            self.assertEqual(result["c"], ["A", "B", "C"])
            for key in ("birthRecord", "candidateResource", "unknownRejected", "missingRejectedLocally",
                        "readOnly", "noTopologyPublication", "onlyPeerSchemaGrowth", "peerCommitted",
                        "oldHandleStayedStale", "nextBirthHasNewIdentity"):
                self.assertIs(result[key], True, key)

    def test_rejected_short_lived_birth_does_not_leave_candidate_or_reject_peer(self) -> None:
        result = self.result["rejectedBirth"]
        self.assertEqual(result["candidateBirthCount"], 0)
        self.assertEqual(result["c"], ["A", "B", "C"])
        for key in ("birthRecord", "unknownRejected", "missingRejectedLocally", "readOnly",
                    "noTopologyPublication", "onlyPeerSchemaGrowth", "peerCommitted", "rejectedOwnerAbsent"):
            self.assertIs(result[key], True, key)

    def test_destroyed_text_birth_retains_finite_scalar_and_uses_original_render_clamp(self) -> None:
        for result, raw, rendered in zip(self.result["shortLivedText"], [0, 0, 2048, 2048], [1, 1, 1024, 1024]):
            self.assertIs(result["rejected"], False)
            self.assertEqual(result["raw"], raw)
            self.assertEqual(result["rendered"], rendered)
            self.assertEqual(result["candidateBirthCount"], 1)
            self.assertEqual(result["c"], ["A", "B", "C"])
            for key in ("cleanDestroyMask", "noPublication", "noSchemaGrowth"):
                self.assertIs(result[key], True, key)
        for result, raw, rendered in zip(self.result["existingTextDestroy"], [0, 2048], [1, 1024]):
            self.assertIs(result["rejected"], False)
            self.assertEqual(result["raw"], raw)
            self.assertEqual(result["rendered"], rendered)
            self.assertEqual(result["candidateBirthCount"], 0)
            for key in ("cleanDestroyMask", "noPublication", "noSchemaGrowth"):
                self.assertIs(result[key], True, key)
        for result in self.result["invalidShortLivedText"]:
            for key in ("rejected", "noPublication", "noPending"):
                self.assertIs(result[key], True, key)
            self.assertEqual(result["c"], ["A", "B", "C"])

    def test_property_only_dynamic_upsert_does_not_supply_stale_sort(self) -> None:
        result = self.result["propertyOnly"]
        self.assertEqual(result["initial"], ["A","X","B","C"])
        self.assertEqual(result["c"], ["C","A","X","B"])
        self.assertEqual(result["swift"], result["c"])
        self.assertEqual(result["failures"], 0)

    def test_late_rejection_reprojects_healthy_operations_and_clears_commit_journal(self) -> None:
        result = self.result["late"]
        self.assertEqual(result["before"], ["B", "C", "A"])
        self.assertEqual(result["c"], ["A", "C", "B"])
        self.assertEqual(result["swift"], result["c"])
        for key in ("firstRejected", "healthyPeer", "cleared", "emptyCadenceStable"):
            self.assertIs(result[key], True, key)

    def test_global_callback_order_survives_owner_coalescing_and_dynamic_destroy(self) -> None:
        expected_rows = [
            (["C", "A", "B"], ["C", "A", "B"], [0, 0], False, False, False),
            (["A", "C", "B"], ["A", "C", "B"], [1, 1], True, True, False),
            (["A", "C", "B"], ["A", "B", "C"], [1, 1], False, True, True),
        ]
        self.assertEqual(len(self.result["interleaved"]), len(expected_rows))
        for result, (before, order, counts, alpha_c, alpha_b, rejected) in zip(
                self.result["interleaved"], expected_rows):
            with self.subTest(order=order, rejected=rejected):
                self.assertEqual(result["before"], before)
                self.assertEqual(result["c"], order)
                self.assertEqual(result["swift"], order)
                self.assertEqual(result["dtoCounts"], counts)
                self.assertEqual(result["failures"], 0)
                self.assertIs(result["alphaC"], alpha_c)
                self.assertIs(result["alphaB"], alpha_b)
                self.assertIs(result["firstRejected"], rejected)
                for key in ("propertyFieldsOnly", "healthyPeer", "carriersKept", "cleared"):
                    self.assertIs(result[key], True, key)
        result = self.result["destroyShift"]
        self.assertEqual(result["c"], ["X", "A", "B", "C"])
        self.assertEqual(result["swift"], result["c"])

    def test_boolean_return_clips_attributes_without_losing_topology_carrier(self) -> None:
        result = self.result["carrier"]
        self.assertEqual(result["programFailures"], 0)
        self.assertEqual(result["layerDTOs"], 0)
        self.assertIs(result["carrierKept"], True)
        self.assertEqual(result["c"], ["B", "A", "C"])
        self.assertEqual(result["swift"], result["c"])
        self.assertEqual(result["failures"], 0)

    def test_authored_tombstone_keeps_raw_slot_until_common_retirement(self) -> None:
        result = self.result["tombstone"]
        self.assertEqual(result["raw"], ["A", "B", "D", "C"])
        self.assertEqual(result["swift"], ["B", "D", "C"])
        self.assertEqual(result["c"], result["swift"])
        self.assertIs(result["removedA"], True)
        self.assertEqual(result["failures"], 0)

    def test_throw_discards_sort_and_healthy_peer_keeps_its_order(self) -> None:
        result = self.result["throw"]
        self.assertIs(result["failed"], True)
        self.assertIs(result["cleared"], True)
        self.assertEqual(result["afterThrow"], ["A", "B", "C"])
        self.assertEqual(result["swift"], ["C", "A", "B"])
        self.assertEqual(result["c"], result["swift"])

    def test_missing_stale_and_nil_projection_fail_without_publication(self) -> None:
        for key, value in self.result["missing"].items():
            self.assertIs(value, True, key)

    def test_success_boolean_controls_following_properties_and_second_sort(self) -> None:
        for result in self.result["returnControls"]:
            self.assertEqual(result["settled"], ["B", "C", "A"])
            self.assertEqual(result["c"], result["settled"])
            self.assertEqual(result["swift"], result["settled"])
            for key in ("typedAlpha", "noOpPreserved", "throwPreserved", "invalidDidNotEnterSuccess", "invalidHadNoTopology"):
                self.assertIs(result[key], True, key)

    def test_many_sorts_of_one_layer_use_original_journal_budget(self) -> None:
        result = self.result["manySorts"]
        self.assertEqual(result["c"], ["B", "A", "C"])
        self.assertEqual(result["swift"], result["c"])
        self.assertEqual(result["mutationCount"], 1)
        self.assertEqual(result["failures"], 0)

    def test_sort_only_alpha_only_and_non_shifting_callback_order_neighbors(self) -> None:
        for name, expected in [("sortOnly",["B","A","C"]),("alphaOnly",["A","B","C"]),
                               ("reverse",["Y","A","B","X","C"])]:
            with self.subTest(name=name):
                result = self.result[name]
                self.assertEqual(result["c"], expected)
                self.assertEqual(result["swift"], expected)
                self.assertEqual(result["failures"], 0)
        self.assertEqual(self.result["sortOnly"]["mutationCount"], 0)
        self.assertEqual(self.result["sortOnly"]["fields"], [])
        self.assertIs(self.result["sortOnly"]["carrierKept"], True)
        self.assertEqual(self.result["alphaOnly"]["mutationCount"], 1)
        self.assertIs(self.result["alphaOnly"]["carrierKept"], False)

if __name__ == "__main__":
    unittest.main()
