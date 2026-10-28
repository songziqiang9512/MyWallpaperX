"""Real QuickJS named Timeline commands retain typed target and owner rollback."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import SCENE, SWIFT_PREAMBLE, compile_vector_harness

TIMELINE_SOURCES = [SCENE / path for path in [
    "Format/SceneTimelineAnimation.swift",
    "Systems/Timeline/SceneTimelineEvaluator.swift",
    "Systems/Timeline/SceneTimelineRuntime.swift",
    "Systems/Timeline/SceneTimelinePlaybackRuntime.swift",
]]
TIMELINE_DECLARATIONS = SCENE / "Systems/Timeline/SceneTimelineTargetCompiler.swift"


def playback_preamble():
    # The shared value-owner carrier has placeholder command DTOs. Compile the
    # actual playback owner instead, plus the production Binding/Program DTOs;
    # TargetCompiler's unrelated descriptor admission is outside this gate.
    start = SWIFT_PREAMBLE.index("enum SceneTimelinePlaybackCommand:")
    end = SWIFT_PREAMBLE.index("enum SceneParticleNumericValue:", start)
    declarations, separator, _ = TIMELINE_DECLARATIONS.read_text().partition(
        "nonisolated enum SceneTimelineTargetCompiler"
    )
    if not separator:
        raise AssertionError("production Timeline declarations unavailable")
    return SWIFT_PREAMBLE[:start] + SWIFT_PREAMBLE[end:] + declarations

HARNESS = r'''
@main enum Harness {
    // Legacy checks concern command semantics; order metadata is asserted
    // explicitly by the real multi-owner Cursor scenario below.
    static func sameCommands(_ a:[SceneTimelinePlaybackMutation],
                             _ b:[SceneTimelinePlaybackMutation]) -> Bool {
        a.count == b.count && zip(a,b).allSatisfy {
            $0.target == $1.target && $0.command == $1.command
        }
    }

    static func scenePlayback(layerName:String, resourceName:String,
                              animationName:String, equivalent:Bool) throws -> [Double] {
        let descriptor = SceneRenderDescriptor(layers: (1...3).map { id in
            var layer = SceneRenderDescriptor.Layer(id:id,layerIndex:id-1,
                name:id == 2 ? layerName : "peer\(id)",visible:true,
                originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])
            layer.imagePath = "models/\(resourceName).json"
            return layer
        })
        let layerTarget = SceneDynamicTarget.layer(layerID:2,field:.alpha)
        let sharedEffect = SceneDynamicTarget.effectConstant(
            layerID:2,effectIndex:3,passIndex:2,name:"Opacity")
        let effect = SceneDynamicTarget.effectConstant(
            layerID:3,effectIndex:4,passIndex:5,name:"g_Amount")
        // These are the supplied *named bindings*, not unnamed Program ordinals.
        // The unsupported first entry leaves a real ABI target-index gap.
        let named:[(target:SceneDynamicTarget,name:String)] = [
            (.scene(.bloomStrength),"unexported"),
            (layerTarget,"shared-name"),(sharedEffect,"shared-name"),(effect,animationName)]
        let bindings = named.dropFirst().map { target, name in
            SceneTimelineBinding(definition:.init(target:target,valueType:.scalar,
                authoredValue:.scalar(0)),animation:.init(lanes:[[
                    .init(frame:0,value:0,back:nil,front:nil,locksAngle:nil,locksLength:nil),
                    .init(frame:12,value:1.5,back:nil,front:nil,locksAngle:nil,locksLength:nil)]],
                options:.init(fps:12,length:12,mode:.single,startsPaused:true,wrapsLoop:false,
                    smoothing:nil,stiffness:nil,parent:nil,children:[],name:name),
                isRelative:false,previewValue:nil),composition:.absolute)
        }
        let program = SceneTimelineProgram(bindings:bindings,diagnostics:[])
        let playback = SceneTimelinePlaybackRuntime(program:program)
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.configureNamedAnimations(named)
        try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(
            frameIndex:0,generation:1,definitions:[]).snapshot,descriptor:descriptor)
        let literal = String(reflecting:animationName)
        let selector = equivalent ? "\(literal).split('').join('')" : literal
        let source = """
        let handle,local,n=0;
        export function init(v){let rejected=0;
          try{thisScene.getAnimation('shared-name');}catch(e){if(e instanceof RangeError)rejected++;}
          try{thisScene.getLayer('peer3').getAnimation(\(selector));}
            catch(e){if(e instanceof RangeError)rejected++;}
          if(rejected!==2)throw new Error('scope');
          local=thisScene.getLayer(\(String(reflecting:layerName))).getAnimation('shared-name');
          handle=thisScene.getAnimation(\(selector));return v;}
        export function update(v){switch(n++){case 0:local.pause();handle.play();break;
          case 1:handle.pause();break;case 2:handle.play();break;default:handle.stop();}return v;}
        """
        func owner(_ source:String) throws -> SceneScriptValueOwner {
            try .init(domain:domain,source:source,target:.layer(layerID:1,field:.alpha),
                valueType:.scalar,effectNames:[],generation:1,budget:.default)
        }
        func evaluate(_ owner:SceneScriptValueOwner,_ time:Double)
            -> Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure> {
            owner.evaluate(input:.scalar(1),frame:.init(timing:.init(wallDate:Date(),
                simulationFrameTime:0.016,sceneTime:time)),scriptPropertiesJSON:"",
                userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        }
        let controller = try owner(source)
        var frame:UInt64 = 0
        func sample(_ time:Double) throws -> Double {
            frame += 1
            let resolution = SceneDynamicSnapshotResolver().resolve(frameIndex:frame,generation:1,
                definitions:bindings.map(\.definition),timelineValues:playback.values(sceneTime:time))
            guard resolution.diagnostics.isEmpty, let value = resolution.snapshot[effect],
                  value.source == .timeline, case let .scalar(number) = value.value else {
                throw NSError(domain:"typed Timeline publication",code:1)
            }
            return number
        }
        var samples = [try sample(0)]
        let times = [0.0,0.25,1.0,1.25]
        let observations = [0.25,1.0,1.25,2.0]
        let expected:[SceneTimelinePlaybackCommand] = [.play,.pause,.play,.stop]
        for index in times.indices {
            let evaluation = try evaluate(controller,times[index]).get()
            let commands = evaluation.animationMutations
            guard sameCommands(commands, index == 0
                ? [.init(target:layerTarget,command:.pause),.init(target:effect,command:.play)]
                : [.init(target:effect,command:expected[index])]) else {
                throw NSError(domain:"full target identity or named ordinal",code:2)
            }
            try playback.apply(commands,sceneTime:times[index]).get()
            controller.commitLayerMutations()
            samples.append(try sample(observations[index]))
        }
        let failed = try owner("export function update(v){thisScene.getAnimation(\(selector)).play();throw new Error('rollback');}")
        guard case .failure = evaluate(failed,2),
              try sample(2.25) == 0 else {
            throw NSError(domain:"scene command rollback",code:3)
        }
        let peer = try owner("export function update(v){thisScene.getAnimation(\(selector)).play();return v;}")
        try playback.apply(try evaluate(peer,2.25).get().animationMutations,sceneTime:2.25).get()
        peer.commitLayerMutations()
        samples.append(try sample(2.5))
        return samples
    }

    static func combinedPlayback(renamed: Bool) throws -> [String: Any] {
        let name = renamed ? "renamed group" : "motion group"
        let card = renamed ? "other panel" : "panel"
        let root = SceneDynamicTarget.layer(layerID: 2, field: renamed ? .angles : .origin)
        let targets: [SceneDynamicTarget] = [.layer(layerID: 2, field: .origin),
            .layer(layerID: 2, field: .angles), .layer(layerID: 2, field: .scale)]
        let bases: [[Double]] = [[10,20,30], [1,2,3], [1,2,3]]
        let endpoints: [[Double]] = [[2,4,6], [4,6,8], [0.5,1,1.5]]
        let bindings = targets.enumerated().map { index, target in
            SceneTimelineBinding(definition: .init(target: target, valueType: .vector3,
                authoredValue: .vector3(bases[index][0],bases[index][1],bases[index][2])),
                animation: .init(lanes: endpoints[index].map { end in [
                    .init(frame:0,value:0,back:nil,front:nil,locksAngle:nil,locksLength:nil),
                    .init(frame:20,value:end,back:nil,front:nil,locksAngle:nil,locksLength:nil)] },
                options:.init(fps:10,length:20,mode:.single,startsPaused:true,wrapsLoop:false,
                    smoothing:nil,stiffness:nil,parent:nil,children:[],name:target == root ? name : nil),
                isRelative:true,previewValue:nil),composition:.additive,playbackOwner:root)
        }
        let program = SceneTimelineProgram(bindings:bindings,diagnostics:[])
        let playback = SceneTimelinePlaybackRuntime(program:program)
        let descriptor = SceneRenderDescriptor(layers: (1...2).map { id in
            var layer = SceneRenderDescriptor.Layer(id:id,layerIndex:id-1,
                name:id == 2 ? card : "healthy peer",visible:true,originXYZ:[10,20,30],
                scaleXYZ:[1,2,3],scaleHasScript:nil,alpha:1,effects:[])
            layer.imagePath = renamed ? "models/renamed-art.json" : "models/art.json"
            return layer
        })
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        let named = bindings.compactMap { binding in binding.animation.options.name.map {
            (target:binding.target,name:$0) } }
        try domain.configureNamedAnimations(named)
        try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(
            frameIndex:0,generation:1,definitions:[]).snapshot,descriptor:descriptor)
        let selector = renamed ? "['renamed','group'].join(' ')" : String(reflecting:name)
        let script = """
        let child,group,n=0;
        export function init(v){child=thisObject.getAnimation();
          group=thisScene.getLayer(\(String(reflecting:card))).getAnimation(\(selector));
          let missing=false;try{thisScene.getAnimation('child name');}catch(e){missing=e instanceof RangeError;}
          if(!missing)throw new Error('child lookup must not be exported');return v;}
        export function update(v){switch(n++){case 0:child.play();break;case 1:group.pause();break;
          case 2:thisScene.getAnimation(\(selector)).play();break;default:child.stop();}return v;}
        """
        let childTarget = targets.first { $0 != root }!
        func owner(_ source: String) throws -> SceneScriptValueOwner {
            try .init(domain:domain,source:source,target:childTarget,valueType:.vector3,
                effectNames:[],hasCurrentAnimation:true,generation:1,budget:.default)
        }
        func evaluate(_ owner: SceneScriptValueOwner, _ time: Double)
            -> Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure> {
            owner.evaluate(input:.vector3(0,0,0),frame:.init(timing:.init(wallDate:Date(),
                simulationFrameTime:0.016,sceneTime:time)),scriptPropertiesJSON:"",
                userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        }
        func sample(_ time: Double) throws -> [[Double]] {
            let resolution = SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
                definitions:bindings.map(\.definition),timelineValues:playback.values(sceneTime:time))
            return try targets.map { target in
                guard resolution.diagnostics.isEmpty, let entry = resolution.snapshot[target],
                      entry.source == .timeline, case let .vector3(x,y,z) = entry.value else {
                    throw NSError(domain:"combined VM typed output",code:1)
                }
                return [x,y,z]
            }
        }
        let controller = try owner(script)
        var samples = [try sample(0)]
        var commands: [SceneTimelinePlaybackMutation] = []
        for (time, observation) in [(0.0,1.0),(1.0,3.0),(3.0,4.0),(4.0,5.0)] {
            let evaluation = try evaluate(controller,time).get()
            commands += evaluation.animationMutations
            let preview = try playback.preview(evaluation.animationMutations,sceneTime:time).get()
            guard Set(preview.keys) == Set(targets) else { throw NSError(domain:"VM group preview",code:2) }
            try playback.apply(evaluation.animationMutations,sceneTime:time).get()
            controller.commitLayerMutations()
            samples.append(try sample(observation))
        }
        let before = try sample(5)
        let throwing = try owner("export function update(v){thisObject.getAnimation().play();throw new Error('abort');}")
        let throwResult = evaluate(throwing,5)
        let discarded = try owner("export function update(v){thisObject.getAnimation().play();return v;}")
        let discardedCommands = try evaluate(discarded,5).get().animationMutations
        discarded.discardLayerMutations()
        let unchanged = try sample(6) == before
        let healthy = try owner("export function update(v){thisScene.getAnimation(\(selector)).play();return v;}")
        try playback.apply(try evaluate(healthy,6).get().animationMutations,sceneTime:6).get()
        healthy.commitLayerMutations()
        samples.append(try sample(7))
        let seeker = try owner("""
        let group,n=0;
        export function init(v){group=thisScene.getLayer(\(String(reflecting:card))).getAnimation(\(selector));
          thisObject.getAnimation().stop();thisObject.getAnimation().setFrame(2.5);return v;}
        export function update(v){switch(n++){
          case 1:group.play();group.setFrame(7.5);break;
          case 2:thisScene.getAnimation(\(selector)).setFrame(1.25);group.pause();break;
          case 3:group.stop();group.setFrame(4.5);break;
          case 4:group.setFrame(6.5);group.stop();break;}return v;}
        """)
        var seekSamples: [[[Double]]] = []
        var seekCommands: [SceneTimelinePlaybackCommand] = []
        var seekPreviewIsIsolated = true
        for (time, observation) in [(8.0,9.0),(9.0,9.25),(10.0,11.0),(11.0,12.0),(12.0,13.0)] {
            let evaluation = try evaluate(seeker,time).get()
            let before = try sample(time)
            let observations = playback.observationSnapshot()
            let preview = try playback.preview(evaluation.animationMutations,sceneTime:time).get()
            let afterPreview = try sample(time)
            seekPreviewIsIsolated = seekPreviewIsIsolated && Set(preview.keys) == Set(targets)
                && afterPreview == before && playback.observationSnapshot() == observations
            try playback.apply(evaluation.animationMutations,sceneTime:time).get()
            seeker.commitLayerMutations()
            seekCommands += evaluation.animationMutations.map(\.command)
            seekSamples.append(try sample(observation))
        }
        let unchangedAfterSeek = try sample(13)
        let observationAfterSeek = playback.observationSnapshot()
        var nonfiniteRejected = true
        for frame in [Double.nan, Double.infinity, -Double.infinity] {
            let invalid = [SceneTimelinePlaybackMutation(target:root,command:.setFrame(5)),
                .init(target:childTarget,command:.setFrame(frame))]
            if case .success = playback.validate(invalid,sceneTime:13) { nonfiniteRejected = false }
            if case .success = playback.preview(invalid,sceneTime:13) { nonfiniteRejected = false }
            if case .success = playback.apply(invalid,sceneTime:13) { nonfiniteRejected = false }
            let afterInvalid = try sample(13)
            nonfiniteRejected = nonfiniteRejected && afterInvalid == unchangedAfterSeek
                && playback.observationSnapshot() == observationAfterSeek
        }
        let low = try playback.preview([.init(target:root,command:.setFrame(-100))],sceneTime:13).get()
        let high = try playback.preview([.init(target:childTarget,command:.setFrame(1e100))],sceneTime:13).get()
        let lastFrame = try playback.preview([.init(target:root,command:.setFrame(20))],sceneTime:13).get()
        let endpointsOnly = targets.allSatisfy { target in
            low[target] == bindings.first { $0.target == target }?.definition.authoredValue
        } && high == lastFrame
        let badSeek = try owner("""
        export function init(v){thisScene.getAnimation(\(selector)).setFrame(3.5);return v;}
        export function update(v){thisObject.getAnimation().setFrame(NaN);return v;}
        """)
        let badSeekFailed: Bool
        if case let .failure(failure) = evaluate(badSeek,13) {
            badSeekFailed = failure.code == "exception"
        } else { badSeekFailed = false }
        let badSeekDisabled: Bool
        if case let .failure(failure) = evaluate(badSeek,13.25) {
            badSeekDisabled = failure.code == "disabled"
        } else { badSeekDisabled = false }
        let afterBadSeek = try sample(13)
        let seekPeer = try owner("""
        let used=false;export function update(v){if(!used){used=true;
          thisScene.getAnimation(\(selector)).setFrame(12.5);}return v;}
        """)
        let peerSeek = try evaluate(seekPeer,13).get().animationMutations
        try playback.apply(peerSeek,sceneTime:13).get()
        seekPeer.commitLayerMutations()
        let peerPose = try sample(14)
        let peerRetry = try evaluate(seekPeer,14).get().animationMutations
        seekPeer.commitLayerMutations()
        let peerLaterPose = try sample(15)
        let failed: Bool
        if case .failure = throwResult { failed = true } else { failed = false }
        return ["samples":samples,"seekSamples":seekSamples,"facts":[
            "rootNamedOnce":named.count == 1 && named[0].target == root,
            "targetIdentity":commands.map(\.target) == [childTarget,root,root,childTarget],
            "commandOrder":commands.map(\.command) == [.play,.pause,.play,.stop],
            "throwDiscardNoApply":failed && unchanged && discardedCommands.count == 1,
            "seekOrder":seekCommands == [.stop,.setFrame(2.5),.play,.setFrame(7.5),
                .setFrame(1.25),.pause,.stop,.setFrame(4.5),.setFrame(6.5),.stop],
            "seekPreviewIsIsolated":seekPreviewIsIsolated,
            "nonfiniteSeekIsAtomic":nonfiniteRejected,
            "finiteSeekUsesExistingSampler":endpointsOnly,
            "badSeekDoesNotLeakInit":badSeekFailed && badSeekDisabled && afterBadSeek == unchangedAfterSeek,
            "healthySeekDoesNotReplay":peerSeek.map(\.command) == [.setFrame(12.5)]
                && peerRetry.isEmpty && peerPose == peerLaterPose]]
    }

    static func commandOwnerOrder(renamed: Bool = false, reverseOwners: Bool = false,
                                  burst: Bool = false, throwB: Bool = false) throws -> [String:Any] {
        let root = SceneDynamicTarget.layer(layerID:2,field:.origin)
        let child = SceneDynamicTarget.layer(layerID:2,field:.angles)
        let independent = SceneDynamicTarget.layer(layerID:3,field:.alpha)
        let name = renamed ? "renamed shared motion" : "shared motion"
        let members = [root,child].enumerated().map { index,target in
            SceneTimelineBinding(definition:.init(target:target,valueType:.vector3,
                authoredValue:.vector3(0,0,0)),animation:.init(lanes:(0..<3).map { lane in [
                    .init(frame:0,value:0,back:nil,front:nil,locksAngle:nil,locksLength:nil),
                    .init(frame:20,value:lane == 0 ? Double((index+1)*20) : 0,
                        back:nil,front:nil,locksAngle:nil,locksLength:nil)] },
                options:.init(fps:10,length:20,mode:.single,startsPaused:true,wrapsLoop:false,
                    smoothing:nil,stiffness:nil,parent:nil,children:[],name:index == 0 ? name : nil),
                isRelative:true,previewValue:nil),composition:.additive,playbackOwner:root)
        }
        let peer = SceneTimelineBinding(definition:.init(target:independent,valueType:.scalar,
            authoredValue:.scalar(0)),animation:.init(lanes:[[
                .init(frame:0,value:0,back:nil,front:nil,locksAngle:nil,locksLength:nil),
                .init(frame:20,value:0.8,back:nil,front:nil,locksAngle:nil,locksLength:nil)]],
            options:.init(fps:10,length:20,mode:.single,startsPaused:false,wrapsLoop:false,
                smoothing:nil,stiffness:nil,parent:nil,children:[],name:"independent"),
            isRelative:false,previewValue:nil),composition:.absolute)
        let program = SceneTimelineProgram(bindings:members+[peer],diagnostics:[])
        func values(_ runtime:SceneTimelinePlaybackRuntime,_ time:Double) throws -> [Double] {
            let result = SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
                definitions:program.bindings.map(\.definition),timelineValues:runtime.values(sceneTime:time))
            guard result.diagnostics.isEmpty,
                  case let .vector3(x,_,_)? = result.snapshot[root]?.value,
                  case let .vector3(y,_,_)? = result.snapshot[child]?.value,
                  case let .scalar(z)? = result.snapshot[independent]?.value else {
                throw NSError(domain:"ordered Timeline typed projection",code:1)
            }
            return [x,y,z]
        }
        let qualification = SceneTimelinePlaybackRuntime(program:program)
        try qualification.apply([.init(target:child,command:.play)],sceneTime:1).get()
        let qualified = try values(qualification,2)
        let descriptor = SceneRenderDescriptor(layers:(2...3).enumerated().map { index,id in
            .init(id:id,layerIndex:index,name:renamed ? "renamed\(id)" : "card\(id)",
                visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])
        })
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.configureNamedAnimations([(target:root,name:name),(target:independent,name:"independent")])
        try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(
            frameIndex:0,generation:1,definitions:[]).snapshot,descriptor:descriptor)
        let variable = renamed ? "renamedCount" : "count"
        let a = """
        let \(variable)=0;
        export function cursorDown(e){
          if(\(variable)++===0){shared.order=(shared.order||'')+'1';thisObject.getAnimation().stop();
            \(burst ? "thisObject.getAnimation().play();" : "")}
          else {thisObject.getAnimation().play();}}
        export function cursorUp(e){shared.order+='3';thisScene.getAnimation(\(String(reflecting:name))).pause();
          thisLayer.scale=new Vec3(Number(shared.order),1,1);}
        """
        let b = """
        let used=false;
        export function cursorDown(e){if(used)return;used=true;shared.order=(shared.order||'')+'2';
          thisObject.getAnimation().play();\(throwB ? "throw new Error('reject B');" : "")}
        """
        var registrations = [(root,a),(child,b)]
        if reverseOwners { registrations.reverse() }
        var owners:[SceneScriptValueOwner] = []
        var bindings:[SceneScriptCursorBinding] = []
        for (index,item) in registrations.enumerated() {
            let owner = try SceneScriptValueOwner(domain:domain,source:item.1,target:item.0,
                effectNames:[],hasCurrentAnimation:true,allowsStatefulLayerSideEffects:true,
                generation:1,budget:.default)
            owners.append(owner)
            bindings.append(.init(layerID:2,authoredOrdinal:index,owner:owner,
                events:owner.exportedCursorEvents,ownsOwner:false,scriptProperties:[:],ownerSeedValue:.vector3(0,0,0)))
        }
        let cursor = SceneScriptCursorProgram(bindings:bindings,generation:1)
        func sample(_ down:Bool) -> SceneScriptCursorFrameSample {
            let hit = SceneScriptCursorHit(layerID:2,worldPosition:.zero,localPosition:.zero)
            return .init(hits:[2:hit],ownerProjections:[2:hit],pointerPosition:.zero,primaryButtonIsDown:down,
                surface:.init(canvasSize:.init(100,100),screenSize:.init(100,100),
                    cursorWorldPosition:.init(0,0,-9000),cursorScreenPosition:.zero,cursorLeftDown:down))
        }
        func dispatch(_ samples:[SceneScriptCursorFrameSample],_ time:Double) -> SceneScriptCursorFrameResult {
            cursor.dispatch(batch:.init(samples:samples,overflowed:false),frame:.init(timing:.init(
                wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:time)),userPropertiesJSON:"{}")
        }
        let result = dispatch([sample(false),sample(true),sample(false)],1)
        let ordered = SceneScriptAnimationHandleBridge.orderedMutations(in:result.ownerEffects)
        let flat = result.ownerEffects.flatMap(\.animationMutations)
        let shuffled = SceneScriptAnimationHandleBridge.orderedMutations(in:Array(result.ownerEffects.reversed()))
        let manual = result.ownerEffects.map { effect in
            var copy = effect
            copy.animationMutations = effect.animationMutations.map {
                .init(target:$0.target,command:$0.command)
            }
            return copy
        }
        let manualFlat = manual.flatMap(\.animationMutations)
        let manualZeroTieOrder = manualFlat.allSatisfy { $0.callbackEpoch == 0 && $0.ordinal == 0 }
            && SceneScriptAnimationHandleBridge.orderedMutations(in:manual) == manualFlat
        // Explicit final-owner exclusion only; this is not the native fixed-point coordinator.
        let filtered = SceneScriptAnimationHandleBridge.orderedMutations(in:result.ownerEffects.filter { $0.ownerTarget != child })
        let playback = SceneTimelinePlaybackRuntime(program:program)
        let before = try values(playback,2)
        let preview = try playback.preview(ordered,sceneTime:1).get()
        let previewDidNotCommit = try values(playback,2) == before
        try playback.apply(ordered,sceneTime:1).get()
        let actual = try values(playback,2)
        let excluded = SceneTimelinePlaybackRuntime(program:program)
        try excluded.apply(filtered,sceneTime:1).get()
        let excludedValues = try values(excluded,2)
        var burstValues:[Double] = []
        var reversedBurstValues:[Double] = []
        if burst {
            let sameCallback = Array(ordered.prefix(2))
            let first = SceneTimelinePlaybackRuntime(program:program)
            let second = SceneTimelinePlaybackRuntime(program:program)
            try first.apply(sameCallback,sceneTime:1).get()
            try second.apply(Array(sameCallback.reversed()),sceneTime:1).get()
            burstValues = try values(first,2)
            reversedBurstValues = try values(second,2)
        }
        cursor.finalizeLayerMutations(committing:true)
        let next = dispatch([sample(true)],3)
        let healthy = SceneScriptAnimationHandleBridge.orderedMutations(in:next.ownerEffects)
        try playback.apply(healthy,sceneTime:3).get()
        let healthyValues = try values(playback,4)
        cursor.finalizeLayerMutations(committing:true)
        _ = owners
        return ["qualifiedSharedMemberClock":qualified,"failures":result.failures.count,
            "commands":ordered.map { String(describing: $0.command) },"targetIsRoot":ordered.map { $0.target == root },
            "flatCommands":flat.map { String(describing: $0.command) },"epochs":ordered.map(\.callbackEpoch),
            "ordinals":ordered.map(\.ordinal),"shuffledBundleOrderSame":ordered == shuffled,
            "manualZeroMetadataInputOrder":manualZeroTieOrder,
            "actualAt2":actual,"filteredCommands":filtered.map { String(describing: $0.command) },
            "filteredEpochs":filtered.map(\.callbackEpoch),"filteredAt2":excludedValues,
            "previewAllMembers":Set(preview.keys) == [root,child],"previewDoesNotCommit":previewDidNotCommit,
            "sameCallbackAt2":burstValues,"reversedSameCallbackAt2":reversedBurstValues,
            "healthyCommands":healthy.map { String(describing: $0.command) },"healthyAt4":healthyValues,
            "healthyEpochs":healthy.map(\.callbackEpoch),"healthyFailures":next.failures.count]
    }

    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: (1...3).map { id in
            .init(id:id,layerIndex:id-1,name:"layer\(id)",visible:true,
                originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[])
        })
        let a = SceneDynamicTarget.layer(layerID:2,field:.alpha)
        let b = SceneDynamicTarget.layer(layerID:3,field:.alpha)
        let current = SceneDynamicTarget.layer(layerID:1,field:.alpha)
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.configureNamedAnimations([(a,"fade"),(b,"fade")])
        try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(
            frameIndex:1,generation:1,definitions:[]).snapshot,descriptor:descriptor)
        func owner(_ source:String) throws -> SceneScriptValueOwner {
            try .init(domain:domain,source:source,target:current,valueType:.scalar,
                effectNames:[],hasCurrentAnimation:true,generation:1,budget:.default)
        }
        func evaluate(_ o:SceneScriptValueOwner,_ time:Double=0) throws -> SceneScriptValueEvaluation {
            try o.evaluate(input:.scalar(1),frame:.init(timing:.init(
                wallDate:Date(timeIntervalSince1970:time),simulationFrameTime:0.016,sceneTime:time)),
                scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
        }
        let retained = try owner("""
        let a,b,own,n=0;
        export function init(v){a=thisScene.getLayer('layer2').getAnimation('fade');
          b=thisScene.getLayer('layer3').getAnimation('fade');own=thisObject.getAnimation();return v;}
        export function update(v){if(n++===0){a.play();b.pause();own.stop();}
          else {a.pause();b.play();}return v;}
        """)
        let first = try evaluate(retained).animationMutations
        let second = try evaluate(retained,1).animationMutations
        let failed = try owner("export function update(v){thisScene.getLayer('layer2').getAnimation('fade').play();throw new Error('rollback');}")
        let failedResult = failed.evaluate(input:.scalar(1),frame:.init(timing:.init(
            wallDate:Date(),simulationFrameTime:0.016,sceneTime:2)),scriptPropertiesJSON:"",
            userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
        var failure = false
        if case .failure = failedResult { failure = true }
        let independent = try owner("export function update(v){thisScene.getLayer('layer3').getAnimation('fade').stop();return v;}")
        let third = try evaluate(independent,3).animationMutations
        let overflowing = try owner("export function update(v){let a=thisScene.getLayer('layer2').getAnimation('fade');for(let i=0;i<17;i++){try{a.play();}catch(e){}}return v;}")
        var overflowRejected = false
        do { _ = try evaluate(overflowing,3) }
        catch SceneScriptScalarRuntimeFailure.mutationOverflow { overflowRejected = true }
        let clickOwner = try owner("export function cursorClick(){thisScene.getLayer('layer2').getAnimation('fade').play();}")
        let clicked = try clickOwner.dispatchCursor(.init(kind:.click,layerID:1,
            worldPosition:.zero,localPosition:.zero),frame:.init(timing:.init(wallDate:Date(),
            simulationFrameTime:0.016,sceneTime:4)),scriptPropertiesJSON:"",userPropertiesJSON:"{}").get()
        let boolOwner = try SceneScriptValueOwner(domain:domain,source:"""
          export function cursorClick(){const a=thisScene.getLayer('layer2').getAnimation('fade');
            a.play();engine.setTimeout(()=>a.pause(),1500);}
          """,target:.layer(layerID:1,field:.visibility),valueType:.bool,effectNames:[],
          allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        let boolClick = try boolOwner.dispatchCursor(.init(kind:.click,layerID:1,
            worldPosition:.zero,localPosition:.zero),frame:.init(timing:.init(wallDate:Date(),
            simulationFrameTime:0.02,sceneTime:5)),scriptPropertiesJSON:"",userPropertiesJSON:"{}").get()
        var timerCommands:[SceneTimelinePlaybackMutation] = []
        for frameIndex in 1...100 {
            let result = try boolOwner.evaluate(input:.bool(true),frame:.init(timing:.init(
                wallDate:Date(),simulationFrameTime:0.02,sceneTime:5+Double(frameIndex)*0.02)),
                scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil).get()
            timerCommands += result.animationMutations
        }
        let out:[String:Any] = [
            "commandOwnerOrder":try commandOwnerOrder(),
            "renamedOwnerOrder":try commandOwnerOrder(renamed:true,reverseOwners:true),
            "burstOwnerOrder":try commandOwnerOrder(burst:true),
            "throwOwnerOrder":try commandOwnerOrder(throwB:true),
            "combined":try combinedPlayback(renamed:false),
            "renamedCombined":try combinedPlayback(renamed:true),
            "statefulBoolTimer":sameCommands(boolClick.animations,[.init(target:a,command:.play)])
                && sameCommands(timerCommands,[.init(target:a,command:.pause)]),
            "overflowRejected":overflowRejected,
            "cursorTarget":sameCommands(clicked.animations,[.init(target:a,command:.play)]),
            "firstTargets":first.map(\.target) == [a,b,current],
            "firstCommands":first.map(\.command) == [.play,.pause,.stop],
            "retainedTargets":second.map(\.target) == [a,b],
            "retainedCommands":second.map(\.command) == [.pause,.play],
            "rollback":failure,
            "peerContinues":sameCommands(third,[.init(target:b,command:.stop)]),
            "sceneSamples":try scenePlayback(layerName:"portrait",resourceName:"panel-a",
                animationName:"pulse",equivalent:false),
            "renamedSceneSamples":try scenePlayback(layerName:"renamed card",resourceName:"different-art",
                animationName:"surface-flash",equivalent:true)]
        print(String(data:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class NamedTimelineTests(unittest.TestCase):
    def test_named_commands_use_existing_typed_journal(self):
        with tempfile.TemporaryDirectory(prefix="mwx-named-timeline-") as temporary:
            binary = compile_vector_harness(Path(temporary), HARNESS, "named-timeline",
                extra_swift_sources=TIMELINE_SOURCES,preamble=playback_preamble())
            run = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
            actual = json.loads(run.stdout.strip().splitlines()[-1])
            for key in ["commandOwnerOrder", "renamedOwnerOrder", "burstOwnerOrder", "throwOwnerOrder"]:
                result = actual.pop(key)
                burst = key == "burstOwnerOrder"
                reverse = key == "renamedOwnerOrder"
                thrown = key == "throwOwnerOrder"
                self.assertEqual(result["qualifiedSharedMemberClock"], [10, 20, 0.8])
                self.assertEqual(result["failures"], int(thrown))
                expected = (["stop", "pause"] if thrown else
                            ["play", "stop", "pause"] if reverse else
                            ["stop", "play", "play", "pause"] if burst else
                            ["stop", "play", "pause"])
                self.assertEqual(result["commands"], expected)
                self.assertEqual(result["targetIsRoot"],
                                 [True, True] if thrown else [False, True, True] if reverse else
                                 [True, True, False, True] if burst else [True, False, True])
                self.assertEqual(result["flatCommands"],
                                 ["stop", "pause"] if thrown else ["play", "stop", "pause"] if reverse else
                                 ["stop", "play", "pause", "play"] if burst else ["stop", "pause", "play"])
                self.assertTrue(result["shuffledBundleOrderSame"])
                self.assertTrue(result["manualZeroMetadataInputOrder"])
                self.assertTrue(result["previewAllMembers"])
                self.assertTrue(result["previewDoesNotCommit"])
                self.assertEqual(result["actualAt2"], [0, 0, 0.8])
                self.assertEqual(result["filteredCommands"],
                                 ["stop", "play", "pause"] if burst else ["stop", "pause"])
                self.assertEqual(result["filteredAt2"], [0, 0, 0.8])
                epochs, ordinals = result["epochs"], result["ordinals"]
                self.assertEqual(result["filteredEpochs"],
                                 [epoch for epoch, is_root in zip(epochs, result["targetIsRoot"]) if is_root])
                self.assertTrue(all(x > 0 for x in epochs))
                self.assertTrue(all(a <= b for a, b in zip(epochs, epochs[1:])))
                self.assertEqual(ordinals, [0, 1, 0, 0] if burst else [0] * len(expected))
                if burst:
                    self.assertEqual(epochs[0], epochs[1])
                    self.assertTrue(epochs[1] < epochs[2] < epochs[3])
                    self.assertEqual(result["sameCallbackAt2"], [10, 20, 0.8])
                    self.assertEqual(result["reversedSameCallbackAt2"], [0, 0, 0.8])
                else:
                    self.assertTrue(all(a < b for a, b in zip(epochs, epochs[1:])))
                self.assertEqual(result["healthyCommands"], ["play"])
                self.assertEqual(result["healthyAt4"], [10, 20, 0.8])
                self.assertEqual(result["healthyFailures"], 0)
                self.assertTrue(all(x > epochs[-1] for x in result["healthyEpochs"]))
            base = [[10,20,30], [1,2,3], [1,2,3]]
            middle = [[11,22,33], [3,5,7], [1.25,2.5,3.75]]
            end = [[12,24,36], [5,8,11], [1.5,3,4.5]]
            for key in ("combined", "renamedCombined"):
                result = actual.pop(key)
                self.assertEqual(result["samples"], [base,middle,middle,end,base,middle])
                self.assertEqual(len(result["seekSamples"]), 5)
                for sample, frame in zip(result["seekSamples"], [2.5, 10, 1.25, 4.5, 0]):
                    for actual_lane, seed, delta in zip(sample, base, [[2,4,6], [4,6,8], [0.5,1,1.5]]):
                        for value, start, change in zip(actual_lane, seed, delta):
                            self.assertAlmostEqual(value, start + change * frame / 20)
                self.assertTrue(all(result["facts"].values()), result)
            for key in ["sceneSamples", "renamedSceneSamples"]:
                self.assertEqual(actual.pop(key), [0, 0.375, 0.375, 0.75, 0, 0.375])
            self.assertEqual(actual, dict.fromkeys([
                "firstTargets", "firstCommands", "retainedTargets", "retainedCommands",
                "rollback", "peerContinues", "cursorTarget", "overflowRejected", "statefulBoolTimer"], True))

if __name__ == "__main__":
    unittest.main()
