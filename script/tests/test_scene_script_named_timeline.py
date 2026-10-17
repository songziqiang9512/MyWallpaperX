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
            guard commands == (index == 0
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
        let failed: Bool
        if case .failure = throwResult { failed = true } else { failed = false }
        return ["samples":samples,"facts":[
            "rootNamedOnce":named.count == 1 && named[0].target == root,
            "targetIdentity":commands.map(\.target) == [childTarget,root,root,childTarget],
            "commandOrder":commands.map(\.command) == [.play,.pause,.play,.stop],
            "throwDiscardNoApply":failed && unchanged && discardedCommands.count == 1]]
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
            "combined":try combinedPlayback(renamed:false),
            "renamedCombined":try combinedPlayback(renamed:true),
            "statefulBoolTimer":boolClick.animations == [.init(target:a,command:.play)]
                && timerCommands == [.init(target:a,command:.pause)],
            "overflowRejected":overflowRejected,
            "cursorTarget":clicked.animations == [.init(target:a,command:.play)],
            "firstTargets":first.map(\.target) == [a,b,current],
            "firstCommands":first.map(\.command) == [.play,.pause,.stop],
            "retainedTargets":second.map(\.target) == [a,b],
            "retainedCommands":second.map(\.command) == [.pause,.play],
            "rollback":failure,
            "peerContinues":third == [.init(target:b,command:.stop)],
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
            base = [[10,20,30], [1,2,3], [1,2,3]]
            middle = [[11,22,33], [3,5,7], [1.25,2.5,3.75]]
            end = [[12,24,36], [5,8,11], [1.5,3,4.5]]
            for key in ("combined", "renamedCombined"):
                result = actual.pop(key)
                self.assertEqual(result["samples"], [base,middle,middle,end,base,middle])
                self.assertTrue(all(result["facts"].values()), result)
            for key in ["sceneSamples", "renamedSceneSamples"]:
                self.assertEqual(actual.pop(key), [0, 0.375, 0.375, 0.75, 0, 0.375])
            self.assertEqual(actual, dict.fromkeys([
                "firstTargets", "firstCommands", "retainedTargets", "retainedCommands",
                "rollback", "peerContinues", "cursorTarget", "overflowRejected", "statefulBoolTimer"], True))

if __name__ == "__main__":
    unittest.main()
