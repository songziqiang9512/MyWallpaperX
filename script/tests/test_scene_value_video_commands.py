"""Scalar/string video side effects survive callbacks and owner transactions."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
    static func commands(_ effects:[SceneScriptOwnerEffects], _ target:SceneDynamicTarget) -> [String] {
        effects.filter{$0.ownerTarget==target}.flatMap{$0.videoCommands}.map { c in
            let action:String
            switch c.action {
            case .play: action="play"
            case .pause: action="pause"
            case .stop: action="stop"
            case let .setCurrentTime(v): action="seek:\(v)"
            case let .setRate(v): action="rate:\(v)"
            case let .setLoop(v): action="loop:\(v)"
            }
            return "\(c.layerID):"+action
        }
    }
    static func main() throws {
        var out:[String:Any]=[:]
        for family in ["scalar","string"] {
            for scenario in ["ordered","implicitInit","rejected","badReturn","exception"] {
                let field=family=="scalar" ? "alpha" : "text"
                let body:String
                switch scenario {
                case "ordered": body="""
                    export function init(v){thisLayer.getVideoTexture().loop=false;return v;}
                    export function applyUserProperties(e){thisLayer.getVideoTexture().rate=2;}
                    export function mediaPlaybackChanged(e){thisLayer.getVideoTexture().pause();}
                    export function mediaPropertiesChanged(e){thisLayer.getVideoTexture().setCurrentTime(3);}
                    export function mediaThumbnailChanged(e){thisLayer.getVideoTexture().play();}
                    export function mediaTimelineChanged(e){thisLayer.getVideoTexture().stop();}
                    export function update(v){thisLayer.getVideoTexture().rate=1;return v;}
                    """
                case "implicitInit": body="""
                    export function init(v){thisLayer.getVideoTexture().loop=false;return v;}
                    export function update(v){thisLayer.getVideoTexture().pause();return v;}
                    """
                case "rejected": body="export function mediaPlaybackChanged(e){thisLayer.getVideoTexture().pause();}"
                case "badReturn": body="""
                    export function mediaPlaybackChanged(e){thisLayer.getVideoTexture().pause();}
                    export function update(v){thisLayer.getVideoTexture().stop();return {};}
                    """
                default: body="export function mediaPlaybackChanged(e){thisLayer.getVideoTexture().pause();throw new Error('failed');}"
                }
                let sources=[body, "export function mediaPlaybackChanged(e){thisLayer.getVideoTexture().play();}"]
                var descriptor=SceneRenderDescriptor(layers:(1...2).map { id in .init(id:id,layerIndex:id-1,name:"video\(id)",visible:true,
                    originXYZ:[0,0,0],scaleXYZ:[1,1,1],scaleHasScript:nil,alpha:1,effects:[],contentKind:"text",text:"0",
                    textStyle:.init(fontPath:nil,colorRGB:nil,pointSize:20),sizeWH:[100,100]) })
                if family=="string" {for i in descriptor.layers.indices {descriptor.layers[i].textScript = .init(source:sources[i])}}
                let bindings=sources.enumerated().map { i,source in SceneScriptBindingIR(source:source,
                    owner:.init(kind:.object,objectIndex:i,objectID:i+1,effectIndex:nil,effectID:nil,passIndex:nil,passID:nil),
                    targetPath:[.key("objects"),.index(i),.key(field)],properties:[:],
                    authoredValue:family=="scalar" ? .number(1) : .string("0"),
                    valueType:family=="scalar" ? .number : .string,wrapperKeys:["script","value"]) }
                let targets:[SceneDynamicTarget]=(1...2).map{family=="scalar" ? .layer(layerID:$0,field:.alpha) : .text(layerID:$0,field:.content)}
                let domain=try SceneScriptQuickJSDomain();try domain.configureLayerCatalog(descriptor)
                try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,definitions:[]).snapshot,
                    descriptor:descriptor,videoSnapshots:Dictionary(uniqueKeysWithValues:(1...2).map{($0,.init(layerID:$0,duration:10,rate:1,loop:true,currentTime:0,isPlaying:true,endedGeneration:0))}))
                let properties:[SceneUserPropertyDefinition]=[.init(key:"mode",title:"Mode",kind:.slider,runtimeType:"slider",order:0,index:nil,
                    minimumValue:0,maximumValue:10,stepValue:1,allowsFractionalValues:false,fractionalPrecision:nil,displayCondition:nil,defaultValue:.number(0),options:[])]
                func exercise(capture:()->SceneScriptProgramFrameState,
                    evaluate:()->([SceneScriptOwnerEffects],[SceneDynamicTarget:SceneScriptScalarRuntimeFailure]),
                    restore:(SceneScriptProgramFrameState,Set<SceneDynamicTarget>?)->Void,
                    finalize:(Bool,Set<SceneDynamicTarget>)->Void) {
                    let key=family+"-"+scenario
                    let snapshot=capture();let first=evaluate()
                    out[key]=commands(first.0,targets[0]);out[key+"Peer"]=commands(first.0,targets[1])
                    out[key+"Failure"]=first.1[targets[0]]?.code ?? "none"
                    if scenario=="rejected" {
                        restore(snapshot,[targets[0]]);finalize(true,[targets[0]])
                        let retry=evaluate();out[key+"Retry"]=commands(retry.0,targets[0]);out[key+"PeerRetry"]=commands(retry.0,targets[1])
                        finalize(true,[]);out[key+"Idle"]=commands(evaluate().0,targets[0]);finalize(true,[])
                        restore(snapshot,nil);finalize(false,[])
                        let whole=evaluate();out[key+"Whole"]=commands(whole.0,targets[0]);out[key+"WholePeer"]=commands(whole.0,targets[1])
                    } else {finalize(true,Set(first.1.keys))}
                }
                let playback:SceneScriptMediaPlaybackEventInput?=scenario=="implicitInit" ? nil : .init(state:1,generation:1)
                if family=="scalar" {
                    let p=SceneScriptScalarProgram.compile(domain:domain,descriptor:descriptor,scriptBindings:bindings,userPropertyDefinitions:properties)
                    out[family+"-"+scenario+"Owners"]=p.bindings.count
                    exercise(capture:p.frameStateSnapshot,evaluate:{
                        let r=p.evaluate(inputs:[targets[0]:.scalar(1),targets[1]:.scalar(1)],frame:frame,effectivePropertyValues:["mode":.number(1)],propertyRevision:1,
                            mediaThumbnailEvent:.init(hasThumbnail:false,generation:1),mediaPlaybackEvent:playback,
                            mediaPropertiesEvent:.init(title:"title",artist:"artist",generation:1),mediaTimelineEvent:.init(position:1,duration:2,generation:1))
                        return(r.ownerEffects,r.failures)
                    },restore:{p.restoreFrameState($0,rejectedOwnerTargets:$1)},finalize:{p.finalizeLayerMutations(committing:$0,rejectedOwnerTargets:$1)})
                } else {
                    let p=SceneScriptStringProgram.compile(domain:domain,descriptor:descriptor,scriptBindings:bindings,userPropertyDefinitions:properties,generation:1)
                    out[family+"-"+scenario+"Owners"]=p.bindings.count
                    exercise(capture:p.frameStateSnapshot,evaluate:{
                        let r=p.evaluate(inputs:[targets[0]:.string("0"),targets[1]:.string("0")],effectivePropertyValues:["mode":.number(1)],propertyRevision:1,frame:frame,
                            mediaThumbnailEvent:.init(hasThumbnail:false,generation:1),mediaPlaybackEvent:playback,
                            mediaPropertiesEvent:.init(title:"title",artist:"artist",generation:1),mediaTimelineEvent:.init(position:1,duration:2,generation:1))
                        return(r.ownerEffects,r.failures)
                    },restore:{p.restoreFrameState($0,rejectedOwnerTargets:$1)},finalize:{p.finalizeLayerMutations(committing:$0,rejectedOwnerTargets:$1)})
                }
            }
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),as:UTF8.self))
    }
}
'''

class SceneValueVideoCommandsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-value-video-vm-") as temp:
            binary=compile_vector_harness(Path(temp),HARNESS,"value-video")
            run=subprocess.run([str(binary)],check=True,capture_output=True,text=True)
            cls.value=json.loads(run.stdout)

    def test_init_user_media_update_keep_order_and_target(self):
        for family in ("scalar","string"):
            key=family+"-ordered"
            self.assertEqual(self.value[key+"Owners"],2)
            self.assertEqual(self.value[key+"Failure"],"none")
            self.assertEqual(self.value[key],["1:loop:false","1:rate:2.0","1:pause","1:seek:3.0","1:play","1:stop","1:rate:1.0"])

    def test_implicit_init_and_update_keep_video_commands(self):
        for family in ("scalar","string"):
            self.assertEqual(self.value[family+"-implicitInit"],["1:loop:false","1:pause"])

    def test_rejected_owner_retries_without_replaying_accepted_peer(self):
        for family in ("scalar","string"):
            key=family+"-rejected"
            self.assertEqual(self.value[key],["1:pause"])
            self.assertEqual(self.value[key+"Retry"],["1:pause"])
            self.assertEqual(self.value[key+"Peer"],["2:play"])
            self.assertEqual(self.value[key+"PeerRetry"],[])
            self.assertEqual(self.value[key+"Idle"],[])
            self.assertEqual(self.value[key+"Whole"],["1:pause"])
            self.assertEqual(self.value[key+"WholePeer"],["2:play"])

    def test_failed_callback_or_return_discards_only_failed_owner(self):
        for family in ("scalar","string"):
            for scenario,code in (("badReturn","bad-return"),("exception","exception")):
                key=family+"-"+scenario
                self.assertEqual(self.value[key+"Failure"],code)
                self.assertEqual(self.value[key],[])
                self.assertEqual(self.value[key+"Peer"],["2:play"])
