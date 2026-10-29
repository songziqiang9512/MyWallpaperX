"""Prepared text wrapper ownership through the production C and Swift owners."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import ROOT, SWIFT_PREAMBLE, compile_vector_harness


# The shared harness intentionally omits renderer descriptor projection. Supply
# its external metadata DTO here; topology/journal admission and commit remain
# the production C domain and SceneScriptDynamicLayerRuntime implementation.
_TEXT_STUB = """    static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
        nil
    }"""
_TEXT_METADATA = """    static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
        guard mutation.isDynamic, mutation.kind == .upsert,
              let pointSize = SceneTextDescriptor.renderedPointSize(mutation.pointSize) else { return nil }
        return .init(id: mutation.layerID, layerIndex: mutation.orderIndex, name: nil,
            solid: mutation.solid, usesPerspective: mutation.perspective, visible: mutation.visible,
            originXYZ: [Float(mutation.origin.x), Float(mutation.origin.y), Float(mutation.origin.z)],
            scaleXYZ: [Float(mutation.scale.x), Float(mutation.scale.y), Float(mutation.scale.z)],
            anglesXYZ: [Float(mutation.angles.x), Float(mutation.angles.y), Float(mutation.angles.z)],
            alpha: mutation.alpha, effects: [], contentKind: "text", text: mutation.text,
            textStyle: .init(fontPath: mutation.font, colorRGB: [1,1,1], pointSize: pointSize))
    }"""
assert SWIFT_PREAMBLE.count(_TEXT_STUB) == 1
PREAMBLE = SWIFT_PREAMBLE.replace(_TEXT_STUB, _TEXT_METADATA, 1)


HARNESS = r'''
import Foundation

enum SceneDocumentLoader {
    static func floatValue(_ value: Any?) -> Float? { (value as? NSNumber)?.floatValue }
    static func floatVector(_ value: Any?) -> [Float]? { (value as? [NSNumber])?.map(\.floatValue) }
}

@main enum Harness {
    static let clock = """
        export var scriptProperties={prefix:'fallback'};
        let births=0, ticks=0, tag='unset';
        export function init(v) { ++births; ticks=10; engine.setInterval(()=>{},1000000); return v+'|I'+births; }
        export function applyUserProperties(p) { if ('prefixKey' in p) tag=p.prefixKey; }
        export function update(v) { return scriptProperties.prefix+'|'+tag+'|I'+births+'|N'+(++ticks)+'|'+v; }
        export function destroy() { if (births!==1) throw Error('bad lifetime'); }
        """
    static func frame(_ t: Double) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                           simulationFrameTime: 1.0/60, sceneTime: t))
    }
    static func wrapper(_ source: String, user: SceneJSONValue = .null) -> SceneJSONValue {
        .object(["script": .string(source), "value": .string("base"), "user": user,
                 "scriptproperties": .object(["prefix": .object([
                    "user": .string("prefixKey"), "value": .string("fallback")])])])
    }
    static func layer(_ id: Int, _ index: Int, _ name: String,
                      _ text: SceneJSONValue, source: String? = nil,
                      sourceEffect: Bool = false) -> SceneRenderDescriptor.Layer {
        .init(id: id, layerIndex: index, name: name, visible: true,
              originXYZ: [0,0,0], scaleXYZ: [1,1,1], alpha: 1,
              effects: sourceEffect ? [.init(name:"source-effect")] : [],
              contentKind: "text", textScript: source.map { .init(source: $0) }, text: "base",
              textStyle: .init(fontPath: nil, colorRGB: [1,1,1], pointSize: 32),
              initialConfiguration: .object(["name": .string(name), "text": text]))
    }
    static func binding(_ id: Int, _ index: Int, _ source: String) -> SceneScriptBindingIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: index, objectID: id,
            effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(index), .key("text")],
            properties: ["prefix": .object(["user": .string("prefixKey"), "value": .string("fallback")])],
            authoredValue: .string("base"), valueType: .string,
            wrapperKeys: ["script", "scriptproperties", "user", "value"])
    }
    struct Fixture {
        let domain: SceneScriptQuickJSDomain
        let program: SceneScriptStringProgram
        let descriptor: SceneRenderDescriptor
        let properties: ScenePropertyBindingProgram
        let values: [String: SceneUserPropertyValue]
        var userValues: [SceneDynamicTarget: SceneDynamicValue] {
            properties.evaluate(effectiveValues: values).userValues
        }
        var userJSON: String {
            SceneScriptPropertyInputCodec.userPropertiesJSON(values: values, kinds: [:])
        }
    }
    static func fixture(clockSource: String = clock, renamed: Bool = false,
                        duplicateUser: Bool = false, sourceEffect: Bool = false,
                        currentAnimation: Bool = false, scriptOuterUser: Bool = true,
                        particleEmitter: Bool = false) throws -> Fixture {
        let name = renamed ? "renamed-watch" : "clock"
        let bad = "export var scriptProperties={prefix:'fallback'}; export function init(v){return {};} export function update(v){return v;}"
        var descriptor = SceneRenderDescriptor(layers: [
            layer(101,0,name,wrapper(clockSource,user:scriptOuterUser ? .string("bodyKey"):.null),source: clockSource,sourceEffect:sourceEffect),
            layer(102,1,"user-template",.object(["user": .string("caption"), "value": .string("base")])),
            layer(103,2,"value-template",.object(["value": .string("base")])),
            layer(104,3,"bad-template",wrapper(bad),source: bad),
            layer(110,4,"controller",.string("controller"))
        ])
        if duplicateUser {
            descriptor.layers.append(layer(107,5,"user-peer",
                .object(["value":.string("base"),"user":.string("caption")])))
        }
        descriptor.layers.append(layer(108,descriptor.layers.count,"null-user-value",
            .object(["value":.string("base"),"user":.null])))
        if particleEmitter {
            var emitter=layer(42,descriptor.layers.count,"emitter",.string("particle"))
            emitter.contentKind="particle";descriptor.layers.append(emitter)
        }
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: descriptor,
            particlePlaybackObservations:particleEmitter ? [42:particleObservation]:[:])
        let program = SceneScriptStringProgram.compile(domain: domain, descriptor: descriptor,
            scriptBindings: [binding(101,0,clockSource),binding(104,3,bad)],
            timelineTargets: currentAnimation ? [.text(layerID:101,field:.content)] : [],generation: 1)
        var targets = [SceneDynamicTarget.text(layerID: 101,field: .content),
                       SceneDynamicTarget.text(layerID: 102,field: .content)]
        var keys=["bodyKey","caption"]
        if duplicateUser { targets.append(.text(layerID:107,field:.content)); keys.append("caption") }
        let properties = ScenePropertyBindingProgram(definitions: targets.map {
            .init(target: $0,valueType: .string,authoredValue: .string("base"))
        },instructions: zip(targets,keys).map { target,key in
            .init(propertyKey: key,path: .init(components: [.key(key)]),
                  target: target,valueType: .string)
        })
        let registered = program.configurePreparedTextTemplates(domain: domain,
            descriptor: descriptor,propertyBindingProgram: properties)
        precondition(registered.isEmpty, "prepared registration: \(registered)")
        let fixture = Fixture(domain: domain,program: program,descriptor: descriptor,
            properties: properties,values: ["bodyKey": .string("launch-body"),
                                            "caption": .string("user-live"),"prefixKey": .string("P")])
        precondition(program.preparePreparedTextCloneInputs(userValues: fixture.userValues,
            effectivePropertyValues: fixture.values,propertyRevision: 0).isEmpty)
        return fixture
    }
    static func creator(_ f: Fixture, _ code: String) throws -> SceneScriptValueOwner {
        try .init(domain: f.domain,source: code,target: .layer(layerID: 110,field: .origin),
            valueType: .vector3,effectNames: [],allowsStatefulLayerSideEffects: true,
            generation: 1,budget: .default)
    }
    static func run(_ owner: SceneScriptValueOwner, _ f: Fixture, _ t: Double = 1)
        -> Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure> {
        owner.evaluate(input: .vector3(t,0,0),frame: frame(t),scriptPropertiesJSON: "",
            userPropertiesJSON: f.userJSON,expectedGeneration: 1,interruptBudget: nil)
    }
    static func text(_ value: SceneDynamicValue?) -> String {
        guard case let .string(value)? = value else { return "<missing>" }; return value
    }
    static func status<T>(_ result: Result<T,SceneScriptScalarRuntimeFailure>) -> String {
        switch result { case .success: return "ok"; case let .failure(error): return error.code }
    }
    static func adopt(_ fixture:Fixture, _ committed:[SceneScriptLayerMutation]=[], at time:Double=1)
        -> SceneScriptPreparedTextCloneAdoption {
        fixture.program.adoptCommittedPreparedTextClones(frame:frame(time),liveTextTemplates:
            Dictionary(committed.filter{$0.isDynamic && $0.kind == .upsert && $0.textTemplateIdentity != 0}
                .map{($0.layerID,$0.textTemplateIdentity)},uniquingKeysWith:{_,new in new}))
    }
    static func runtime(_ f:Fixture) -> SceneScriptDynamicLayerRuntime {
        .init(descriptor:f.descriptor,authoredMutationLayerIDs:[110,103],
            textTemplates:f.program.preparedTextTemplates,
            layerOrderProjection:{ f.domain.projectPendingLayerOrder(accepting:$0) })
    }
    static func effects(_ evaluation:SceneScriptValueEvaluation,_ owner:SceneScriptValueOwner)
        -> SceneScriptOwnerEffects {
        var output=SceneScriptOwnerEffects(ownerTarget:owner.target,materialFunctionMutations:[],
            animationMutations:[],layerMutations:[],mediaPlaybackCommands:[])
        output.append(evaluation)
        return output
    }
    static func peer(_ f:Fixture,_ source:String) throws -> SceneScriptValueOwner {
        try .init(domain:f.domain,source:source,target:.layer(layerID:103,field:.origin),
            valueType:.vector3,effectNames:[],generation:1,budget:.default)
    }
    static func dual(_ renamed: Bool) throws -> [String: Any] {
        let variant=renamed ? clock.replacingOccurrences(of:"births",with:"activations")
            .replacingOccurrences(of:"ticks",with:"steps").replacingOccurrences(of:"tag",with:"label") : clock
        let f = try fixture(clockSource:variant,renamed: renamed)
        let target = SceneDynamicTarget.text(layerID: 101,field: .content)
        let original = f.program.evaluate(inputs: [target:.string("launch-body")],
            effectivePropertyValues: f.values,propertyRevision: 0,targetFilter: target,
            frame: frame(0),userPropertiesJSON: f.userJSON)
        f.program.finalizeLayerMutations(committing: true)
        let name = renamed ? "renamed-watch" : "clock"
        let owner = try creator(f,"""
            let a,b;
            export function update(v) {
                if (!a) {
                    const config=thisScene.getInitialLayerConfig('\(name)');
                    const raw=config.text;
                    const equivalent={value:raw.value,user:raw.user,scriptproperties:raw.scriptproperties,script:raw.script};
                    a=thisScene.createLayer({name:'left',text:equivalent});
                    b=thisScene.createLayer({name:'right',text:raw});
                    if (!a || !b || a.text!=='launch-body|I1' || b.text!=='launch-body|I1')
                        throw Error('synchronous fresh init');
                } else if(v.x===5) { thisScene.destroyLayer(a); }
                else {
                    let stale=false; try { thisScene.destroyLayer(a); } catch (_) { stale=true; }
                    if(!stale) throw Error('stale handle accepted');
                }
                return v;
            }
            """)
        let created = try run(owner,f).get()
        let births = created.layerMutations.filter { $0.isDynamic && $0.kind == .upsert }
        owner.commitLayerMutations()
        let adoption = adopt(f,births)
        let targets = births.map { SceneDynamicTarget.text(layerID:$0.layerID,field:.content) }
        var inputs = Dictionary(uniqueKeysWithValues: zip(targets,births.map { SceneDynamicValue.string($0.text) }))
        inputs[target] = original.values[target]
        let first = f.program.evaluate(inputs: inputs,effectivePropertyValues: f.values,
            propertyRevision: 0,excludedTargets: [.text(layerID:104,field:.content)],
            frame: frame(2),userPropertiesJSON: f.userJSON)
        f.program.finalizeLayerMutations(committing: true)
        let one = f.program.evaluate(inputs: first.values,effectivePropertyValues: f.values,
            propertyRevision: 0,targetFilter: targets.first,frame: frame(3),userPropertiesJSON: f.userJSON)
        f.program.finalizeLayerMutations(committing: true)
        let changed: [String:SceneUserPropertyValue] = ["prefixKey":.string("Q"),"bodyKey":.string("next-body")]
        var nextInputs = first.values; nextInputs.merge(one.values) { _,new in new }
        let next = f.program.evaluate(inputs: nextInputs,effectivePropertyValues: changed,
            propertyRevision: 1,excludedTargets: [.text(layerID:104,field:.content)],
            frame: frame(4),userPropertiesJSON: "{\"prefixKey\":\"Q\",\"bodyKey\":\"next-body\"}")
        f.program.finalizeLayerMutations(committing: true)
        let removal = try run(owner,f,5).get()
        owner.commitLayerMutations()
        let removedIDs = Set(removal.layerMutations.filter { $0.kind == .destroy }.map(\.layerID))
        let held=f.program.timerFrameStateSnapshot()
        let heldLedger=f.program.frameStateSnapshot()
        let retire = f.program.retire(layerIDs: removedIDs,frame: frame(5),
            effectivePropertyValues: changed,userPropertiesJSON: f.userJSON)
        let repeatRetire = f.program.retire(layerIDs: removedIDs,frame: frame(5),
            effectivePropertyValues: changed,userPropertiesJSON: f.userJSON)
        f.program.restoreTimerFrameState(held)
        f.program.discardTimerFrameState(held)
        f.program.restoreFrameState(heldLedger)
        let stale=run(owner,f,6)
        owner.commitLayerMutations()
        let live=Set(f.program.bindings.map(\.target))
        let peerActive=targets.filter { live.contains($0) }.count
        let creatorRetire=owner.teardown(frame: frame(7),scriptPropertiesJSON: "",userPropertiesJSON:f.userJSON)
        let peerIDs=Set(births.map(\.layerID)).subtracting(removedIDs)
        let peerRetire=f.program.retire(layerIDs:peerIDs,frame:frame(7),
            effectivePropertyValues:changed,userPropertiesJSON:f.userJSON)
        return ["births":births.count,"birthValues":births.map(\.text),
            "adopted":adoption.definitions.count,"adoptionFailures":adoption.failures.count,
            "queueFailure":adoption.queueFailure?.code ?? "none",
            "first":targets.map { text(first.values[$0]) },"original":text(first.values[target]),
            "filtered":targets.map { text(one.values[$0]) },
            "changed":targets.map { text(next.values[$0]) },
            "destroyed":removedIDs.count,"destroyCalls":retire.filter(\.destroyCallbackInvoked).count,
            "repeatDestroyCalls":repeatRetire.filter(\.destroyCallbackInvoked).count,
            "peerStillActive":peerActive,"staleHandle":status(stale),
            "staleMutations":(try? stale.get().layerMutations.count) ?? -1,
            "creatorQuiescent":creatorRetire.snapshot.isQuiescent,
            "peerDestroyCalls":peerRetire.filter(\.destroyCallbackInvoked).count,
            "remainingBindings":f.program.bindings.count,
            "capturedOwners":held.capturedValueOwners?.count ?? -1]
    }
    static func wrappers() throws -> [String:Any] {
        let f=try fixture()
        let owner=try creator(f,"""
            export function update(v) {
                const u=thisScene.createLayer({text:thisScene.getInitialLayerConfig('user-template').text});
                const s=thisScene.createLayer({text:thisScene.getInitialLayerConfig('value-template').text});
                const n=thisScene.createLayer({text:thisScene.getInitialLayerConfig('null-user-value').text});
                if (!u || !s || !n || u.text!=='user-live' || s.text!=='base' || n.text!=='base') throw Error('wrapper input');
                let hits=0;
                const bad={value:'base'}; Object.defineProperty(bad,'script',{get(){++hits;return 'x';},enumerable:true});
                if(thisScene.createLayer({text:bad})!==null || hits!==0) throw Error('getter executed');
                const proxy=new Proxy({value:'base'},{ownKeys(){throw Error('proxy trap');}});
                if(thisScene.createLayer({text:proxy})!==null) throw Error('proxy accepted');
                const changed=thisScene.getInitialLayerConfig('clock').text;changed.script+=' ';
                if(thisScene.createLayer({text:changed})!==null) throw Error('modified source accepted');
                if(thisScene.createLayer({text:{value:'unknown'}})!==null) throw Error('unknown accepted');
                if(thisScene.createLayer({text:{value:'base',user:17}})!==null) throw Error('invalid user accepted');
                return v;
            }
            """)
        let result=run(owner,f)
        let mutations=(try? result.get().layerMutations) ?? []
        owner.commitLayerMutations()
        let adopted=adopt(f,mutations)
        return ["status":status(result),"count":mutations.count,
            "templateCount":mutations.filter{$0.textTemplateIdentity != 0}.count,
            "texts":mutations.map(\.text),"scriptOwners":adopted.definitions.count]
    }
    static func rejection(_ suffix:String, bad:Bool=false,
                          source:String=clock,currentAnimation:Bool=false) throws -> [String:Any] {
        let f=try fixture(clockSource:source,currentAnimation:currentAnimation)
        let owner=try creator(f,"""
            export function update(v) {
                const config=thisScene.getInitialLayerConfig('\(bad ? "bad-template":"clock")');
                try { thisScene.createLayer({text:config.text}); } catch (_) {}
                \(suffix)
                return v;
            }
            """)
        let result=run(owner,f)
        owner.discardLayerMutations()
        let adopted=adopt(f)
        let peer=try creator(f,"export function update(v){return new Vec3(7,8,9);}")
        let healthy=run(peer,f)
        peer.commitLayerMutations()
        var lifecycle=MWXSceneQuickJSLifecycleSnapshot()
        _=mwx_scene_quickjs_owner_lifecycle_snapshot(owner.handle,&lifecycle)
        return ["status":status(result),"adopted":adopted.definitions.count,
                "peer":status(healthy),"remaining":lifecycle.active_dynamic_layer_count]
    }
    static func retiredSource() throws -> [String:Any] {
        let f=try fixture()
        let target=SceneDynamicTarget.text(layerID:101,field:.content)
        _=f.program.evaluate(inputs:[target:.string("launch-body")],effectivePropertyValues:f.values,
            propertyRevision:0,targetFilter:target,frame:frame(0),userPropertiesJSON:f.userJSON)
        f.program.finalizeLayerMutations(committing:true)
        _=f.program.retire(layerIDs:[101],frame:frame(0),userPropertiesJSON:f.userJSON)
        let owner=try creator(f,"""
            export function update(v){const a=thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text});
                if(!a || a.text!=='launch-body|I1')throw Error('retired template');return v;}
            """)
        let result=run(owner,f)
        owner.commitLayerMutations()
        let adopted=adopt(f,(try? result.get().layerMutations) ?? [])
        return ["status":status(result),"adopted":adopted.definitions.count]
    }
    static func duplicateTemplates() throws -> [String:Any] {
        let f=try fixture(duplicateUser:true)
        let a=try creator(f,"""
            export function update(v){
                for(const name of ['user-template','user-peer']) {
                    const layer=thisScene.createLayer({text:thisScene.getInitialLayerConfig(name).text});
                    if(!layer || layer.text!=='user-live')throw Error('equivalent prepared templates');
                }return v;}
            """)
        let accepted=try run(a,f).get()
        a.commitLayerMutations()
        var conflict=f.userValues
        conflict[.text(layerID:107,field:.content)] = .string("different")
        let refresh=f.program.preparePreparedTextCloneInputs(userValues:conflict,
            effectivePropertyValues:f.values,propertyRevision:1)
        let b=try creator(f,"""
            export function update(v){
                if(thisScene.createLayer({text:thisScene.getInitialLayerConfig('user-template').text})!==null)
                    throw Error('conflicting prepared inputs accepted');
                if(!thisScene.createLayer({text:thisScene.getInitialLayerConfig('value-template').text}))
                    throw Error('healthy peer rejected');return v;}
            """)
        let rejected=run(b,f)
        b.commitLayerMutations()
        return ["accepted":accepted.layerMutations.count,
            "canonicalCount":Set(accepted.layerMutations.map(\.textTemplateIdentity)).count,
            "refreshFailures":refresh.count,"conflictStatus":status(rejected),
            "healthyCount":(try? rejected.get().layerMutations.count) ?? -1]
    }
    static func parentJobs() throws -> [String:Any] {
        let f=try fixture()
        let owner=try creator(f,"""
            let seen=0;
            export function update(v){
                if(v.x===1){
                    Promise.resolve().then(()=>{seen=1;thisLayer.alpha=0.25;});
                    if(thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text})!==null)
                        throw Error('pending parent job was consumed by child');
                }return new Vec3(seen,0,0);}
            """)
        let first=try run(owner,f).get()
        owner.commitLayerMutations()
        let second=try run(owner,f,2).get()
        owner.commitLayerMutations()
        let adopted=adopt(f,at:2)
        return ["first":first.value == .vector3(0,0,0),"parentJobRan":second.value == .vector3(1,0,0),
            "jobAlpha":first.layerMutations.first?.alpha ?? -1,"adopted":adopted.definitions.count]
    }
    static func childBoundary(_ source:String, sourceEffect:Bool=false,
                              scriptOuterUser:Bool=true) throws -> [String:Any] {
        let f=try fixture(clockSource:source,sourceEffect:sourceEffect,scriptOuterUser:scriptOuterUser)
        let expected=(scriptOuterUser ? "launch-body|I1":"base|I1") + (sourceEffect ? "|E0":"")
        let effectProbe=sourceEffect ? """
            return new Vec3(thisScene.getLayer('clock').getEffectCount(),0,0);
            """ : "return v;"
        let owner=try creator(f,"""
            export function update(v){const raw=thisScene.getInitialLayerConfig('clock').text;
                const a=thisScene.createLayer({text:raw}),b=thisScene.createLayer({text:raw});
                if(!a || !b || a.text!=='\(expected)' || b.text!=='\(expected)')
                    throw Error('child boundary');\(effectProbe)}
            """)
        let created=run(owner,f)
        owner.commitLayerMutations()
        let adopted=adopt(f,(try? created.get().layerMutations) ?? [])
        var output:[String:Any]=["status":status(created),"adopted":adopted.definitions.count,
            "birthCount":(try? created.get().layerMutations.count) ?? -1]
        if sourceEffect, case let .vector3(original,_,_)? = try? created.get().value {
            output["sourceEffectCount"]=original
            output["childEffectTexts"]=(try? created.get().layerMutations.filter(\.isDynamic).map(\.text)) ?? []
        }
        return output
    }
    static func unwired(_ source:String) throws -> [String:Any] {
        let f=try fixture(clockSource:source)
        let owner=try creator(f,"""
            export function update(v){
                if(thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text})!==null)
                    throw Error('unwired template admitted');
                if(!thisScene.createLayer({text:thisScene.getInitialLayerConfig('value-template').text}))
                    throw Error('healthy wrapper rejected');return v;}
            """)
        let result=run(owner,f)
        owner.commitLayerMutations()
        return ["status":status(result),"count":(try? result.get().layerMutations.count) ?? -1,
            "adopted":adopt(f,(try? result.get().layerMutations) ?? []).definitions.count]
    }
    static func isolatedUpdateFailure() throws -> [String:Any] {
        let source=clock.replacingOccurrences(of:"export function update(v) { return",
            with:"export function update(v) { if(thisLayer.name==='left' && engine.runtime===2)return {}; return")
        let f=try fixture(clockSource:source)
        let owner=try creator(f,"""
            export function update(v){const raw=thisScene.getInitialLayerConfig('clock').text;
                thisScene.createLayer({name:'left',text:raw});thisScene.createLayer({name:'right',text:raw});return v;}
            """)
        let created=try run(owner,f).get()
        owner.commitLayerMutations()
        _=adopt(f,created.layerMutations)
        let targets=created.layerMutations.map{SceneDynamicTarget.text(layerID:$0.layerID,field:.content)}
        let inputs=Dictionary(uniqueKeysWithValues:zip(targets,created.layerMutations.map{SceneDynamicValue.string($0.text)}))
        let first=f.program.evaluate(inputs:inputs,effectivePropertyValues:f.values,propertyRevision:0,
            frame:frame(2),userPropertiesJSON:f.userJSON)
        f.program.finalizeLayerMutations(committing:true)
        var current=inputs;current.merge(first.values){_,new in new}
        let retry=f.program.evaluate(inputs:current,effectivePropertyValues:f.values,propertyRevision:0,
            frame:frame(3),userPropertiesJSON:f.userJSON)
        f.program.finalizeLayerMutations(committing:true)
        return ["failure":first.failures[targets[0]]?.code ?? "none",
            "failedValue":text(first.values[targets[0]]),"healthy":text(first.values[targets[1]]),
            "retry":targets.map{text(retry.values[$0])},"retryFailures":retry.failures.count]
    }
    static func retirementCycles() throws -> [String:Any] {
        let f=try fixture()
        let owner=try creator(f,"""
            let a;
            export function update(v){if(v.x%2===1)a=thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text});
                else thisScene.destroyLayer(a);return v;}
            """)
        var counts:[Int]=[],pinned=true,released=true,ledgerPruned=true
        for cycle in 0..<3 {
            let birth=Double(cycle*2+1)
            let created=try run(owner,f,birth).get()
            owner.commitLayerMutations()
            let adoption=adopt(f,created.layerMutations,at:birth)
            guard let definition=adoption.definitions.first,let mutation=created.layerMutations.first else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument("cycle birth unavailable")
            }
            _=f.program.evaluate(inputs:[definition.target:.string(mutation.text)],
                effectivePropertyValues:f.values,propertyRevision:0,targetFilter:definition.target,
                frame:frame(birth+0.25),userPropertiesJSON:f.userJSON)
            f.program.finalizeLayerMutations(committing:true)
            weak var retiredOwner=f.program.bindings.last
            do {
                let timer=f.program.timerFrameStateSnapshot(),ledger=f.program.frameStateSnapshot()
                _=try run(owner,f,birth+1).get()
                owner.commitLayerMutations()
                _=f.program.retire(layerIDs:[mutation.layerID],frame:frame(birth+1),
                    effectivePropertyValues:f.values,userPropertiesJSON:f.userJSON)
                pinned = pinned && retiredOwner != nil
                f.program.restoreTimerFrameState(timer)
                f.program.discardTimerFrameState(timer)
                f.program.restoreFrameState(ledger)
                ledgerPruned = ledgerPruned && f.program.frameStateSnapshot().appliedUserProperties.changedJSON(
                    for:definition.target,current:f.values,kinds:[:],revision:0) != nil
            }
            released = released && retiredOwner == nil
            counts.append(f.program.bindings.count)
        }
        return ["counts":counts,"pinned":pinned,"released":released,"ledgerPruned":ledgerPruned,
            "definitions":f.program.definitions.count,"inputs":f.program.inputTargets.count,
            "properties":f.program.propertyInputsByTarget.count,"retiredTombstones":f.program.retiredTargets.count]
    }
    static let sortingSource="""
        export var scriptProperties={prefix:'fallback'};
        export function init(v){thisScene.sortLayer(thisLayer,0);return v+'|sort';}
        export function update(v){thisScene.sortLayer(thisLayer,engine.runtime===2?thisScene.getLayerCount()-1:0);
            if(engine.runtime===4)throw Error('child sort rollback');return v;}
        """
    static func sortedClone() throws -> [String:Any] {
        let f=try fixture(clockSource:sortingSource),layers=runtime(f)
        let owner=try creator(f,"""
            export function init(v){thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text});return v;}
            export function update(v){return v;}
            """)
        let born=try run(owner,f).get(),birthEffect=effects(born,owner)
        let birth=layers.preflightOwnerEffects([birthEffect])
        let birthRaw=try f.domain.projectPendingLayerOrder(accepting:Set([birthEffect.layerTopologyOwnerIdentity].compactMap{$0})).get()
        layers.commit(birth.layerPlan);owner.commitLayerMutations()
        let adoption=f.program.adoptCommittedPreparedTextClones(frame:frame(1),
            liveTextTemplates:birth.layerPlan.textTemplateIdentitiesByLayerID)
        guard let definition=adoption.definitions.first,let mutation=born.layerMutations.first else {
            return ["birthFailures":birth.rejectedOwners.count,"adopted":adoption.definitions.count]
        }
        let id=mutation.layerID,base=f.descriptor.renderOrderLayerIDs
        let initialized=layers.snapshot().renderOrderLayerIDs == [id]+base
        let changed=f.program.evaluate(inputs:[definition.target:.string(mutation.text)],
            effectivePropertyValues:f.values,propertyRevision:0,targetFilter:definition.target,
            frame:frame(2),userPropertiesJSON:f.userJSON)
        let update=layers.preflightOwnerEffects(changed.ownerEffects)
        let updateRaw=try f.domain.projectPendingLayerOrder(accepting:Set(changed.ownerEffects.compactMap(\.layerTopologyOwnerIdentity))).get()
        layers.commit(update.layerPlan);f.program.finalizeLayerMutations(committing:true)
        let updated=layers.snapshot().renderOrderLayerIDs == base+[id]
        let healthy=try peer(f,"export function update(v){thisScene.sortLayer(thisLayer,v.x===4?1:0);return v;}")
        let late=f.program.evaluate(inputs:changed.values,effectivePropertyValues:f.values,
            propertyRevision:0,targetFilter:definition.target,frame:frame(3),userPropertiesJSON:f.userJSON)
        let peerLate=effects(try run(healthy,f,3).get(),healthy)
        let latePlan=layers.preflightOwnerEffectsToFixedPoint(late.ownerEffects+[peerLate],
            excludingOwners:[definition.target],rejectingExternally:{_, _ in []})
        let lateExpected=[103]+base.filter{$0 != 103}+[id]
        layers.commit(latePlan.admission.layerPlan)
        f.program.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[definition.target]);healthy.commitLayerMutations()
        let lateSafe=layers.snapshot().renderOrderLayerIDs == lateExpected
        let failed=f.program.evaluate(inputs:changed.values,effectivePropertyValues:f.values,
            propertyRevision:0,targetFilter:definition.target,frame:frame(4),userPropertiesJSON:f.userJSON)
        let peerThrow=effects(try run(healthy,f,4).get(),healthy)
        let throwPlan=layers.preflightOwnerEffects([peerThrow])
        layers.commit(throwPlan.layerPlan);healthy.commitLayerMutations()
        f.program.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[definition.target])
        var throwExpected=base.filter{$0 != 103}+[id];throwExpected.insert(103,at:1)
        return ["birthFailures":birth.rejectedOwners.count,"adopted":adoption.definitions.count,
            "birthRawMatches":birthRaw == birth.layerPlan.order,"initOrder":initialized,
            "updateFailures":update.rejectedOwners.count,"updateRawMatches":updateRaw == update.layerPlan.order,
            "updateOrder":updated,"lateOrder":lateSafe,"latePeers":latePlan.admission.admittedEffects.count,
            "throwFailure":failed.failures[definition.target]?.code ?? "none",
            "throwOrder":layers.snapshot().renderOrderLayerIDs == throwExpected]
    }
    static func rejectedBirthSort(_ throwsParent:Bool) throws -> [String:Any] {
        let f=try fixture(clockSource:sortingSource),layers=runtime(f)
        let owner=try creator(f,"""
            export function init(v){thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text});return v;}
            export function update(v){\(throwsParent ? "throw Error('parent sort rollback');":"return v;")}
            """)
        let created=run(owner,f)
        let healthy=try peer(f,"export function update(v){thisScene.sortLayer(thisLayer,0);return v;}")
        let healthyEffect=effects(try run(healthy,f).get(),healthy)
        let candidates=(try? created.get()).map{[effects($0,owner),healthyEffect]} ?? [healthyEffect]
        let accepted=layers.preflightOwnerEffectsToFixedPoint(candidates,
            excludingOwners:throwsParent ? []:[owner.target],rejectingExternally:{_, _ in []})
        layers.commit(accepted.admission.layerPlan);owner.discardLayerMutations();healthy.commitLayerMutations()
        let adopted=f.program.adoptCommittedPreparedTextClones(frame:frame(1),
            liveTextTemplates:accepted.admission.layerPlan.textTemplateIdentitiesByLayerID)
        return ["status":status(created),"adopted":adopted.definitions.count,
            "healthyOrder":layers.snapshot().renderOrderLayerIDs == [103]+f.descriptor.renderOrderLayerIDs.filter{$0 != 103},
            "admittedPeers":accepted.admission.admittedEffects.count,"dynamic":layers.snapshot().dynamicLayers.count]
    }
    static func textSetters(_ mode:String) throws -> [String:Any] {
        let source="export var scriptProperties={prefix:'fallback'};export function init(v){return v;}export function update(v){if(engine.runtime===2)thisLayer.pointsize=Number.MAX_VALUE;thisLayer.text='child-change';thisLayer.origin=new Vec3(engine.runtime,0,0);return v;}"
        let f=try fixture(clockSource:source),layers=runtime(f)
        let owner=try creator(f,"""
            export function init(v){const a=thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text});a.text='creator-change';a.pointsize=0;return v;}
            export function update(v){\(mode == "throw" ? "throw Error('setter parent rollback');":"return v;")}
            """)
        let created=run(owner,f)
        let healthy=try peer(f,"export function update(v){thisScene.createLayer({text:'healthy-peer'});return v;}")
        let healthyEffect=effects(try run(healthy,f).get(),healthy)
        let candidates=(try? created.get()).map{[effects($0,owner),healthyEffect]} ?? [healthyEffect]
        let result=layers.preflightOwnerEffectsToFixedPoint(candidates,
            excludingOwners:mode == "late" ? [owner.target]:[],rejectingExternally:{_, _ in []})
        layers.commit(result.admission.layerPlan)
        if mode == "accepted" { owner.commitLayerMutations() } else { owner.discardLayerMutations() }
        healthy.commitLayerMutations()
        let adoption=f.program.adoptCommittedPreparedTextClones(frame:frame(1),
            liveTextTemplates:result.admission.layerPlan.textTemplateIdentitiesByLayerID)
        let creatorText=layers.snapshot().dynamicLayers.first{$0.text == "creator-change"}?.text ?? "absent"
        let creatorSize=layers.snapshot().dynamicLayers.first{$0.text == "creator-change"}?.textStyle?.pointSize ?? -1
        var childText="absent",childFailures=0,textDirty=false
        var childRawSize: Double = -1, childSize: Float = -1, retainedRawSize: Double = -1
        var retainedSize: Float = -1, partialSizeDirty=false
        if let definition=adoption.definitions.first {
            let update=f.program.evaluate(inputs:[definition.target:.string("creator-change")],
                effectivePropertyValues:f.values,propertyRevision:0,targetFilter:definition.target,
                frame:frame(2),userPropertiesJSON:f.userJSON)
            textDirty=update.layerMutations.contains{$0.fields.contains(.text)}
            let plan=layers.preflightOwnerEffects(update.ownerEffects)
            childFailures=plan.rejectedOwners.count+update.failures.count
            layers.commit(plan.layerPlan);f.program.finalizeLayerMutations(committing:true)
            childText=layers.snapshot().dynamicLayers.first{$0.id == SceneScriptLayerMutationBridge.layerID(for:definition.target)}?.text ?? "absent"
            childRawSize=update.layerMutations.first?.pointSize ?? -1
            childSize=layers.snapshot().dynamicLayers.first{$0.id == SceneScriptLayerMutationBridge.layerID(for:definition.target)}?.textStyle?.pointSize ?? -1
            let partial=f.program.evaluate(inputs:[definition.target:.string("child-change")],
                effectivePropertyValues:f.values,propertyRevision:0,targetFilter:definition.target,
                frame:frame(3),userPropertiesJSON:f.userJSON)
            partialSizeDirty=partial.layerMutations.contains{$0.fields.contains(.pointSize)}
            retainedRawSize=partial.layerMutations.first?.pointSize ?? -1
            let partialPlan=layers.preflightOwnerEffects(partial.ownerEffects)
            childFailures += partialPlan.rejectedOwners.count+partial.failures.count
            layers.commit(partialPlan.layerPlan);f.program.finalizeLayerMutations(committing:true)
            retainedSize=layers.snapshot().dynamicLayers.first{$0.id == SceneScriptLayerMutationBridge.layerID(for:definition.target)}?.textStyle?.pointSize ?? -1
        }
        return ["status":status(created),"adopted":adoption.definitions.count,
            "creatorText":creatorText,"childText":childText,"childFailures":childFailures,"textDirty":textDirty,
            "creatorSize":creatorSize,"childRawSize":childRawSize,"childSize":childSize,
            "retainedRawSize":retainedRawSize,"retainedSize":retainedSize,"partialSizeDirty":partialSizeDirty,
            "healthy":layers.snapshot().dynamicLayers.contains{$0.text == "healthy-peer"},
            "rejections":result.admission.rejectedOwners.count,"dynamic":layers.snapshot().dynamicLayers.count]
    }
    static func sameFrameCreatorDeletion() throws -> [String:Any] {
        let f=try fixture(),layers=runtime(f)
        let owner=try creator(f,"export function update(v){thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text});return v;}")
        let born=try run(owner,f).get()
        let deleter=try peer(f,"export function update(v){thisScene.destroyLayer('controller');return v;}")
        let deleted=try run(deleter,f).get()
        let admission=layers.preflightOwnerEffects([effects(born,owner),effects(deleted,deleter)])
        layers.commit(admission.layerPlan);owner.commitLayerMutations();deleter.commitLayerMutations()
        let adopted=f.program.adoptCommittedPreparedTextClones(frame:frame(1),
            liveTextTemplates:admission.layerPlan.textTemplateIdentitiesByLayerID)
        let again=f.program.adoptCommittedPreparedTextClones(frame:frame(1),
            liveTextTemplates:admission.layerPlan.textTemplateIdentitiesByLayerID)
        return ["rejections":admission.rejectedOwners.count,"dynamic":layers.snapshot().dynamicLayers.count,
            "liveTemplates":admission.layerPlan.textTemplateIdentitiesByLayerID.count,
            "adopted":adopted.definitions.count,"again":again.definitions.count,
            "failures":adopted.failures.count,"bindings":f.program.bindings.count]
    }
    static func dynamicStringBounds() throws -> [String:Any] {
        let source="""
            export var scriptProperties={prefix:'fallback'};
            export function init(v){return v;}
            export function update(v){
                if(thisLayer.name==='clock' && engine.runtime===9)return 'x'.repeat(65536);
                if(thisLayer.name==='bounded'){
                    if(engine.runtime===2)return 'x'.repeat(4096);
                    if(engine.runtime===3)return 'x'.repeat(4097);
                    if(engine.runtime===4)return 'a\\u0000b';
                    return engine.runtime>=6?v:'good';
                }return 'healthy@'+engine.runtime;
            }
            """
        let f=try fixture(clockSource:source),layers=runtime(f)
        let owner=try creator(f,"""
            export function update(v){const raw=thisScene.getInitialLayerConfig('clock').text;
                thisScene.createLayer({name:'bounded',text:raw});thisScene.createLayer({name:'healthy',text:raw});return v;}
            """)
        let born=try run(owner,f).get(),admission=layers.preflightOwnerEffects([effects(born,owner)])
        layers.commit(admission.layerPlan);owner.commitLayerMutations()
        let adoption=f.program.adoptCommittedPreparedTextClones(frame:frame(1),
            liveTextTemplates:admission.layerPlan.textTemplateIdentitiesByLayerID)
        let targets=born.layerMutations.map{SceneDynamicTarget.text(layerID:$0.layerID,field:.content)}
        guard adoption.definitions.count==2,let bounded=f.program.bindings.first(where:{$0.target==targets[0]}) else {
            return ["adopted":adoption.definitions.count]
        }
        var current=Dictionary(uniqueKeysWithValues:zip(targets,born.layerMutations.map{SceneDynamicValue.string($0.text)}))
        var statuses:[String]=[],lengths:[Int]=[],healthy:[String]=[]
        for t in 2...5 {
            let result=f.program.evaluate(inputs:current,effectivePropertyValues:f.values,
                propertyRevision:0,frame:frame(Double(t)),userPropertiesJSON:f.userJSON)
            statuses.append(result.failures[targets[0]]?.code ?? "ok")
            lengths.append(text(result.values[targets[0]]).utf8.count)
            healthy.append(text(result.values[targets[1]]))
            current.merge(result.values){_,new in new}
            f.program.finalizeLayerMutations(committing:true,rejectedOwnerTargets:Set(result.failures.keys))
        }
        func inputStatus(_ input:String) -> String {
            let result=bounded.evaluate(input:.string(input),frame:frame(6),scriptPropertiesJSON:"{\"prefix\":\"P\"}",
                userPropertiesJSON:f.userJSON,expectedGeneration:1,interruptBudget:nil)
            if case .success = result { bounded.commitLayerMutations() } else { bounded.discardLayerMutations() }
            return status(result)
        }
        let sourceTarget=SceneDynamicTarget.text(layerID:101,field:.content)
        let invalid=layers.projectPreparedTextUserValues(from:[sourceTarget:.string(String(repeating:"x",count:4097))],
            previousValue:{_ in .string("previous")})
        let nul=layers.projectPreparedTextUserValues(from:[sourceTarget:.string("a\0b")],
            previousValue:{_ in .string("previous")})
        let fallback=layers.projectPreparedTextUserValues(from:[sourceTarget:.string("a\0b")])
        let valid=layers.projectPreparedTextUserValues(from:[sourceTarget:.string(String(repeating:"x",count:4096))])
        let authored=f.program.bindings.first{$0.target==sourceTarget}!
        let normal=try authored.evaluate(input:.string("normal"),frame:frame(9),scriptPropertiesJSON:"{\"prefix\":\"P\"}",
            userPropertiesJSON:f.userJSON,expectedGeneration:1,interruptBudget:nil).get()
        authored.commitLayerMutations()
        return ["statuses":statuses,"lengths":lengths,"healthy":healthy,
            "inputs":[inputStatus(String(repeating:"x",count:4096)),inputStatus(String(repeating:"x",count:4097)),inputStatus("a\0b")],
            "userPrevious":targets.allSatisfy{invalid[$0] == .string("previous") && nul[$0] == .string("previous")},
            "userFallback":targets.allSatisfy{fallback[$0] == .string("base")},
            "userValid":targets.allSatisfy{text(valid[$0]).utf8.count==4096},
            "normalAuthored":text(normal.value).utf8.count]
    }
    static let particleObservation=SceneParticlePlaybackObservation(liveAny:false,emissionPending:false,
        rearmHasWork:false,intent:.playing,revision:0)
    static func particleScope(_ withParticles:Bool,badChild:Bool=false) throws -> [String:Any] {
        let bad="export var scriptProperties={prefix:'fallback'};export function init(v){thisScene.getLayer('emitter').emitParticles(9);return v;}"
        let f=try fixture(clockSource:badChild ? bad:clock,particleEmitter:withParticles),layers=runtime(f)
        let owner=try creator(f,"""
            export function update(v){
                \(withParticles ? "const p=thisScene.getLayer('emitter');p.stop();p.emitParticles(2);":"")
                const a=thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text});
                if(!a)throw Error('create rejected in normal cadence scope');
                \(withParticles ? "p.emitParticles(3);":"")
                return v;}
            """)
        let healthy=try peer(f,withParticles
            ? "export function update(v){thisScene.getLayer('emitter').emitParticles(4);return v;}"
            : "export function update(v){return new Vec3(7,8,9);}")
        var counts:[Int]=[],prefixes:[[Int]]=[],discarded:[UInt]=[]
        f.domain.beginParticlePlaybackFrame(onBoundary:{native,discard in
            if discard { discarded.append(UInt(bitPattern:native)) }
        }) { native,raw in
            if counts.isEmpty { try f.domain.chargeParticleWork(1,bytes:64) }
            counts.append(Int(raw.count))
            prefixes.append(try SceneScriptParticlePlaybackCommandBridge.commands(owner:native).get()
                .filter{$0.callbackEpoch==raw.callback_epoch}.map(\.count))
            return .init(liveAny:true,emissionPending:false,rearmHasWork:false,intent:.stopped,revision:0)
        }
        defer { f.domain.endParticlePlaybackFrame() }
        let created=run(owner,f),suffix=run(healthy,f)
        let candidates=[(try? created.get()).map{effects($0,owner)},
                        (try? suffix.get()).map{effects($0,healthy)}].compactMap{$0}
        let plan=layers.preflightOwnerEffects(candidates,
            particleObservations:withParticles ? [42:particleObservation]:[:])
        layers.commit(plan.layerPlan)
        if case .success = created { owner.commitLayerMutations() } else { owner.discardLayerMutations() }
        healthy.commitLayerMutations()
        let adoption=f.program.adoptCommittedPreparedTextClones(frame:frame(1),
            liveTextTemplates:plan.layerPlan.textTemplateIdentitiesByLayerID)
        var later="missing"
        if let definition=adoption.definitions.first {
            let result=f.program.evaluate(inputs:[definition.target:.string("launch-body|I1")],
                effectivePropertyValues:f.values,propertyRevision:0,targetFilter:definition.target,
                frame:frame(2),userPropertiesJSON:f.userJSON)
            later=text(result.values[definition.target]);f.program.finalizeLayerMutations(committing:true)
        }
        let reserved=mwx_scene_quickjs_domain_particle_reserved(f.domain.handle)
        if reserved>0 { mwx_scene_quickjs_domain_particle_release(f.domain.handle,reserved) }
        return ["status":status(created),"healthy":status(suffix),"adopted":adoption.definitions.count,
            "rejections":plan.rejectedOwners.count,"counts":counts,"prefixes":prefixes,
            "parentCommands":(try? created.get().particlePlaybackCommands.count) ?? 0,
            "parentDiscard":discarded.contains(UInt(bitPattern:owner.handle)),
            "reserved":reserved,"later":later]
    }
    static func main() throws {
        let childJob="export var scriptProperties={prefix:'fallback'}; export function init(v){Promise.resolve().then(()=>{throw Error('child job must not run');});return v;}"
        let nested="export var scriptProperties={prefix:'fallback'}; export function init(v){if(thisScene.createLayer({text:thisScene.getInitialLayerConfig('clock').text})!==null)throw Error('nested script');return v+'|I1';}"
        let effect="export var scriptProperties={prefix:'fallback'}; export function init(v){if(thisLayer.getEffectCount()!==0 || thisLayer.getEffect('source-effect')!==null)throw Error('fake effect');return v+'|I1|E'+thisLayer.getEffectCount();}"
        let animation="export var scriptProperties={prefix:'fallback'}; export function init(v){thisObject.getAnimation().play();return v;}"
        let output:[String:Any]=["dual":try dual(false),"renamed":try dual(true),
            "booleanText":try BooleanTextCloneChecks.run(false),
            "booleanTextRenamed":try BooleanTextCloneChecks.run(true),
            "wrappers":try wrappers(),"parentThrow":try rejection("throw Error('parent');"),
            "lateDiscard":try rejection(""),"badInit":try rejection("",bad:true),
            "retiredSource":try retiredSource(),"duplicates":try duplicateTemplates(),
            "parentJobs":try parentJobs(),"childJob":try rejection("",source:childJob),
            "depthOne":try childBoundary(nested),"effectBoundary":try childBoundary(effect,sourceEffect:true),
            "unsupportedCommand":try rejection("",source:animation,currentAnimation:true),
            "unwiredMedia":try unwired("export function mediaPropertiesChanged(p){}"),
            "unwiredCursor":try unwired("export function cursorClick(){}"),
            "unwiredAudio":try unwired("const audio=engine.registerAudioBuffers(16);export function update(v){return v;}"),
            "isolatedUpdateFailure":try isolatedUpdateFailure(),"retirementCycles":try retirementCycles(),
            "scriptNullUser":try childBoundary(clock,scriptOuterUser:false),
            "sortedClone":try sortedClone(),"sortParentThrow":try rejectedBirthSort(true),
            "sortLateDiscard":try rejectedBirthSort(false),
            "textAccepted":try textSetters("accepted"),"textParentThrow":try textSetters("throw"),
            "textLateDiscard":try textSetters("late"),"sameFrameCreatorDeletion":try sameFrameCreatorDeletion(),
            "dynamicStringBounds":try dynamicStringBounds(),
            "emptyParticleScope":try particleScope(false),"particlePrefix":try particleScope(true),
            "childParticleRejected":try particleScope(true,badChild:true),
            "initNUL":try rejection("",source:"export var scriptProperties={prefix:'fallback'};export function init(v){return 'a\\u0000b';}")]
        print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]),as:UTF8.self))
    }
}
'''


class PreparedTextCloneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-prepared-text-")
        cls.addClassCleanup(cls.directory.cleanup)
        binary = compile_vector_harness(Path(cls.directory.name), HARNESS, "prepared-text", preamble=PREAMBLE,
            extra_swift_sources=(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextDescriptor.swift",
                Path(__file__).parent / "fixtures/SceneScriptBooleanTextCloneChecks.swift"),
            whole_module_optimization=True,
        )
        execution = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
        cls.result = json.loads(execution.stdout)

    def test_committed_clones_keep_fresh_init_update_and_user_state(self) -> None:
        for name in ("dual", "renamed"):
            with self.subTest(name=name):
                row = self.result[name]
                self.assertEqual(row["births"], 2)
                self.assertEqual(row["birthValues"], ["launch-body|I1"] * 2)
                self.assertEqual((row["adopted"], row["adoptionFailures"], row["queueFailure"]), (2, 0, "none"))
                self.assertTrue(all(value.startswith("P|P|I1|N11|") for value in row["first"]))
                self.assertTrue(row["original"].startswith("P|P|I1|N12|"))
                self.assertTrue(row["filtered"][0].startswith("P|P|I1|N12|"))
                self.assertEqual(row["filtered"][1], "<missing>")
                self.assertTrue(row["changed"][0].startswith("Q|Q|I1|N13|"))
                self.assertTrue(row["changed"][1].startswith("Q|Q|I1|N12|"))
                self.assertEqual((row["destroyed"], row["destroyCalls"], row["repeatDestroyCalls"], row["peerStillActive"]), (1, 1, 0, 1))
                self.assertEqual((row["staleHandle"], row["staleMutations"], row["creatorQuiescent"], row["peerDestroyCalls"]), ("ok", 0, True, 1))
                self.assertEqual((row["remainingBindings"], row["capturedOwners"]), (2, 4))

    def test_boolean_creator_keeps_text_and_authored_updates_in_one_transaction(self) -> None:
        for name in ("booleanText", "booleanTextRenamed"):
            with self.subTest(name=name):
                row = self.result[name]
                self.assertEqual(row["status"], "ok")
                self.assertEqual((row["births"], row["rejected"], row["adopted"]), (1, 0, 1))
                self.assertTrue(row["authoredAngles"])
                self.assertTrue(row["discardRetainsVisible"])
                self.assertEqual(row["afterDestroy"], 0)
                self.assertEqual(row["unknownImage"], "invalid-argument")

    def test_user_value_and_safe_own_data_admission(self) -> None:
        row = self.result["wrappers"]
        self.assertEqual(row["status"], "ok")
        self.assertEqual((row["count"], row["templateCount"], row["scriptOwners"]), (3, 3, 0))
        self.assertEqual(row["texts"], ["user-live", "base", "base"])
        self.assertEqual(self.result["scriptNullUser"], {"status": "ok", "adopted": 2, "birthCount": 2})

    def test_parent_and_child_failures_discard_only_the_creator_bundle(self) -> None:
        for name, expected in (("parentThrow", "exception"), ("badInit", "exception"),
                               ("childJob", "exception"), ("unsupportedCommand", "exception"), ("initNUL", "exception"),
                               ("lateDiscard", "ok")):
            with self.subTest(name=name):
                row = self.result[name]
                self.assertEqual(row["status"], expected)
                self.assertEqual((row["adopted"], row["remaining"], row["peer"]), (0, 0, "ok"))

    def test_source_retirement_preserves_the_prepared_template(self) -> None:
        self.assertEqual(self.result["retiredSource"], {"status": "ok", "adopted": 1})

    def test_equivalent_templates_share_identity_and_conflicting_inputs_reject(self) -> None:
        self.assertEqual(self.result["duplicates"], {"accepted": 2, "canonicalCount": 1,
            "refreshFailures": 0, "conflictStatus": "ok", "healthyCount": 1})

    def test_parent_job_residue_is_preserved_and_child_depth_is_bounded(self) -> None:
        self.assertEqual(self.result["parentJobs"], {"first": True, "parentJobRan": True,
            "jobAlpha": 0.25, "adopted": 0})
        self.assertEqual(self.result["depthOne"], {"status": "ok", "adopted": 2, "birthCount": 2})

    def test_dynamic_text_does_not_inherit_fake_effect_consumers(self) -> None:
        self.assertEqual(self.result["effectBoundary"], {"status": "ok", "adopted": 2,
            "birthCount": 2, "sourceEffectCount": 1,
            "childEffectTexts": ["launch-body|I1|E0", "launch-body|I1|E0"]})

    def test_unwired_templates_reject_locally(self) -> None:
        for name in ("unwiredMedia", "unwiredCursor", "unwiredAudio"):
            with self.subTest(name=name):
                self.assertEqual(self.result[name], {"status": "ok", "count": 1, "adopted": 0})

    def test_bad_clone_update_preserves_the_healthy_peer_and_retries(self) -> None:
        row = self.result["isolatedUpdateFailure"]
        self.assertEqual((row["failure"], row["failedValue"], row["retryFailures"]), ("bad-return", "<missing>", 0))
        self.assertTrue(row["healthy"].startswith("P|P|I1|N11|"))
        self.assertTrue(row["retry"][0].startswith("P|P|I1|N11|"))
        self.assertTrue(row["retry"][1].startswith("P|P|I1|N12|"))

    def test_retirement_reclaims_owners_after_captured_timer_frames_release(self) -> None:
        self.assertEqual(self.result["retirementCycles"], {"counts": [2, 2, 2],
            "pinned": True, "released": True, "ledgerPruned": True,
            "definitions": 2, "inputs": 2, "properties": 2, "retiredTombstones": 0})

    def test_clone_sort_replays_through_real_journal_and_topology_commit(self) -> None:
        self.assertEqual(self.result["sortedClone"], {"birthFailures": 0, "adopted": 1,
            "birthRawMatches": True, "initOrder": True, "updateFailures": 0,
            "updateRawMatches": True, "updateOrder": True, "lateOrder": True,
            "latePeers": 1, "throwFailure": "exception", "throwOrder": True})
        for name, status in (("sortParentThrow", "exception"), ("sortLateDiscard", "ok")):
            with self.subTest(name=name):
                self.assertEqual(self.result[name], {"status": status, "adopted": 0,
                    "healthyOrder": True, "admittedPeers": 1, "dynamic": 0})

    def test_explicit_dynamic_text_setters_commit_or_rollback_with_the_owner(self) -> None:
        self.assertEqual(self.result["textAccepted"], {"status": "ok", "adopted": 1,
            "creatorText": "creator-change", "childText": "child-change", "childFailures": 0,
            "textDirty": True, "healthy": True, "rejections": 0, "dynamic": 2,
            "creatorSize": 1, "childRawSize": float.fromhex("0x1.fffffffffffffp+1023"), "childSize": 1024,
            "retainedRawSize": float.fromhex("0x1.fffffffffffffp+1023"), "retainedSize": 1024,
            "partialSizeDirty": False})
        for name, status in (("textParentThrow", "exception"), ("textLateDiscard", "ok")):
            with self.subTest(name=name):
                self.assertEqual(self.result[name], {"status": status, "adopted": 0,
                    "creatorText": "absent", "childText": "absent", "childFailures": 0,
                    "textDirty": False, "healthy": True, "rejections": 0, "dynamic": 1,
                    "creatorSize": -1, "childRawSize": -1, "childSize": -1,
                    "retainedRawSize": -1, "retainedSize": -1, "partialSizeDirty": False})

    def test_birth_removed_with_its_creator_is_not_adopted(self) -> None:
        self.assertEqual(self.result["sameFrameCreatorDeletion"], {"rejections": 0,
            "dynamic": 0, "liveTemplates": 0, "adopted": 0, "again": 0, "failures": 0, "bindings": 2})

    def test_dynamic_string_bounds_fail_locally_and_keep_authored_limits(self) -> None:
        self.assertEqual(self.result["dynamicStringBounds"], {
            "statuses": ["ok", "bad-return", "bad-return", "ok"],
            "lengths": [4096, 9, 9, 4], "healthy": ["healthy@2", "healthy@3", "healthy@4", "healthy@5"],
            "inputs": ["ok", "invalid-argument", "invalid-argument"],
            "userPrevious": True, "userFallback": True, "userValid": True, "normalAuthored": 65536})

    def test_normal_particle_cadence_scope_preserves_parent_prefix_and_suffix(self) -> None:
        empty = self.result["emptyParticleScope"]
        self.assertEqual((empty["status"], empty["healthy"], empty["adopted"], empty["rejections"]), ("ok", "ok", 1, 0))
        self.assertEqual((empty["counts"], empty["reserved"], empty["parentDiscard"]), ([], 0, False))
        self.assertTrue(empty["later"].startswith("P|P|I1|N11|"))
        row = self.result["particlePrefix"]
        self.assertEqual((row["status"], row["healthy"], row["adopted"], row["rejections"]), ("ok", "ok", 1, 0))
        self.assertEqual((row["counts"], row["prefixes"], row["parentCommands"]), ([2, 3, 4], [[0], [0, 2], []], 3))
        self.assertEqual((row["reserved"], row["parentDiscard"]), (64, False))
        self.assertTrue(row["later"].startswith("P|P|I1|N11|"))
        bad = self.result["childParticleRejected"]
        self.assertEqual((bad["status"], bad["healthy"], bad["adopted"], bad["parentDiscard"]), ("exception", "ok", 0, True))
        self.assertEqual((bad["counts"], bad["reserved"]), ([2, 4], 64))


if __name__ == "__main__":
    unittest.main()
