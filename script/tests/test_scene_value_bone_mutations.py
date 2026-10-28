"""Scalar/string bone side effects survive callbacks and owner transactions."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness, ROOT

LAUNCH_STUBS = r'''
struct BoneOwnerList { let bindings: [SceneScriptValueOwner] }
struct SceneDesktopWallpaperLaunchContext {
    let propertyVectorScriptProgram: SceneScriptVectorProgram
    let sceneScriptScalarProgram: BoneOwnerList
    let sceneScriptStringProgram: BoneOwnerList
    let sceneScriptCursorProgram: SceneScriptCursorProgram
}
'''
# Compile the real shared-owner configurator; asset preparation is outside
# this callback transaction gate and has its own resource fixtures.
_launch_source = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperLaunchContext+PuppetBones.swift").read_text()
LAUNCH_SOURCE = "extension SceneDesktopWallpaperLaunchContext {\n" + _launch_source[
    _launch_source.index("    func configurePuppetBones("):]
VALIDATION_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptOwnerEffectsRuntimeValidation.swift"

HARNESS = r'''
// Unrelated registries are never entered by this bone-only validation gate.
extension SceneFrameTiming { var frameIndex: UInt64 { 1 } }
struct SceneTimelinePlaybackRuntime {
    func validate(_ commands:[SceneTimelinePlaybackMutation],sceneTime:Double) -> Result<Void,NSError> { fatalError("unexpected Timeline validation") }
}
struct SceneTextureAnimationPlaybackRuntime {
    func validate(_ commands:[SceneTextureAnimationCommand],sceneTime:Double) -> Result<Void,NSError> { fatalError("unexpected texture validation") }
}
struct SceneVideoTextureSourceRegistry {
    func validate(_ commands:[SceneScriptMediaPlaybackCommand],timing:SceneFrameTiming) -> Result<Void,NSError> { fatalError("unexpected video validation") }
}
struct SceneSoundPlaybackRegistry {
    func validate(_ commands:[SceneScriptMediaPlaybackCommand]) -> Result<Void,NSError> { fatalError("unexpected sound validation") }
}
struct ScenePuppetAnimationPlaybackRuntime {
    typealias Failure = NSError
    func validate(_ commands:[ScenePuppetAnimationCommand],frameIndex:UInt64) -> Result<Void,Failure> { fatalError("unexpected clip validation") }
    func validate(_ commands:[ScenePuppetAnimationCommand],sourceLayerID:Int,sourceAnimationLayerID:Int,frameIndex:UInt64) -> Result<Void,Failure> { fatalError("unexpected clip validation") }
}
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1))
    static func commands(_ effects:[SceneScriptOwnerEffects], _ target:SceneDynamicTarget) -> [String] {
        effects.filter{$0.ownerTarget==target}.flatMap{$0.puppetBoneMutations}.map {
            let identity="\($0.layerID):\($0.boneIndex):"
            switch $0.operation {
            case let .matrix(matrix): return identity+"\(matrix[12])"
            case let .impulse(v): return identity+"impulse:\(v.x),\(v.y),\(v.z)"
            }
        }
    }

    @MainActor static func validateBoneOwners() -> [String:Any] {
        let target=SceneDynamicTarget.layer(layerID:1,field:.origin)
        let peerTarget=SceneDynamicTarget.layer(layerID:2,field:.origin)
        let matrix:[Double]=[1,0,0,0,0,1,0,0,0,0,1,0,3,0,0,1]
        let valid=SceneScriptPuppetBoneMutation(layerID:1,boneIndex:0,matrix:matrix)
        let peer=SceneScriptOwnerEffects(ownerTarget:peerTarget,materialFunctionMutations:[],
            animationMutations:[],layerMutations:[],mediaPlaybackCommands:[],
            puppetBoneMutations:[.init(layerID:2,boneIndex:0,matrix:matrix)])
        var overflow=matrix;overflow[12]=1e300
        let cases:[(String,SceneScriptPuppetBoneMutation)]=[
            ("impulse",.init(layerID:1,boneIndex:0,operation:.impulse(SIMD3(1e300,0,0)))),
            ("matrix",.init(layerID:1,boneIndex:0,matrix:overflow)),
            ("edge",.init(layerID:1,boneIndex:0,operation:.impulse(SIMD3(Double(Float.greatestFiniteMagnitude),0,0))))]
        var result:[String:Any]=[:]
        for (name,command) in cases {
            let owner=SceneScriptOwnerEffects(ownerTarget:target,materialFunctionMutations:[],
                animationMutations:[],layerMutations:[],mediaPlaybackCommands:[],
                puppetBoneMutations:[valid,command])
            let effects=[owner,peer]
            let failures=SceneScriptOwnerEffectsRuntimeValidation.failures(for:effects,
                timelineRuntime:.init(),textureAnimationRuntime:.init(),videoRegistry:nil,
                timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:frame.frameTime,sceneTime:frame.runtime))
            let rejected=Set(failures.map(\.ownerTarget))
            let admitted=effects.filter { !rejected.contains($0.ownerTarget) }
            result[name]=["failures":failures.count,"commandCounts":failures.map(\.commandCount),
                "ownerCommands":admitted.first { $0.ownerTarget==target }?.puppetBoneMutations.count ?? 0,
                "peerCommands":commands(admitted,peerTarget)]
        }
        return result
    }
    @MainActor static func main() throws {
        var out:[String:Any]=[:]
        out["boneValidation"]=validateBoneOwners()
        for family in ["scalar","string"] {
            for scenario in ["ordered","implicitInit","rejected","badReturn","exception"] {
                let field=family=="scalar" ? "alpha" : "text"
                let body:String
                switch scenario {
                case "ordered": body="""
                    export function init(v){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(1,0,0)));return v;}
                    export function applyUserProperties(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(2,0,0)));}
                    export function mediaPlaybackChanged(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(3,0,0)));}
                    export function mediaPropertiesChanged(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(4,0,0)));}
                    export function mediaThumbnailChanged(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(5,0,0)));}
                    export function mediaTimelineChanged(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(6,0,0)));}
                    export function update(v){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(7,0,0)));return v;}
                    """
                case "implicitInit": body="""
                    export function init(v){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(1,0,0)));return v;}
                    export function update(v){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(3,0,0)));return v;}
                    """
                case "rejected": body="export function mediaPlaybackChanged(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(3,0,0)));thisLayer.applyBonePhysicsImpulse('root',new Vec3(6,2,1));}"
                case "badReturn": body="""
                    export function mediaPlaybackChanged(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(3,0,0)));}
                    export function update(v){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(6,0,0)));thisLayer.applyBonePhysicsImpulse(0,new Vec3(7,8,9));return {};}
                    """
                default: body="export function mediaPlaybackChanged(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(3,0,0)));thisLayer.applyBonePhysicsImpulse(0,new Vec3(7,8,9));throw new Error('failed');}"
                }
                let sources=[body, "export function mediaPlaybackChanged(e){thisLayer.setLocalBoneTransform(0,Mat4.fromTranslation(new Vec3(5,0,0)));}"]
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
                    let matrix:[Double]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
                    let context=SceneDesktopWallpaperLaunchContext(
                        propertyVectorScriptProgram:.compile(domain:domain,descriptor:descriptor,scriptBindings:[],userPropertyDefinitions:[],generation:1),
                        sceneScriptScalarProgram:.init(bindings:family=="scalar" ? p.bindings : []),
                        sceneScriptStringProgram:.init(bindings:family=="string" ? p.bindings : []),
                        sceneScriptCursorProgram:.init(bindings:[],generation:1))
                    for id in 1...2 { let configured=try context.configurePuppetBones(layerID:id,localMatrices:matrix,names:["root"]); precondition(configured) }
                    let missing=try context.configurePuppetBones(layerID:99,localMatrices:matrix,names:["root"])
                    precondition(!missing)
                    out[family+"-"+scenario+"Owners"]=p.bindings.count
                    exercise(capture:p.frameStateSnapshot,evaluate:{
                        let r=p.evaluate(inputs:[targets[0]:.scalar(1),targets[1]:.scalar(1)],frame:frame,effectivePropertyValues:["mode":.number(1)],propertyRevision:1,
                            mediaThumbnailEvent:.init(hasThumbnail:false,generation:1),mediaPlaybackEvent:playback,
                            mediaPropertiesEvent:.init(title:"title",artist:"artist",generation:1),mediaTimelineEvent:.init(position:1,duration:2,generation:1))
                        return(r.ownerEffects,r.failures)
                    },restore:{p.restoreFrameState($0,rejectedOwnerTargets:$1)},finalize:{p.finalizeLayerMutations(committing:$0,rejectedOwnerTargets:$1)})
                } else {
                    let p=SceneScriptStringProgram.compile(domain:domain,descriptor:descriptor,scriptBindings:bindings,userPropertyDefinitions:properties,generation:1)
                    let matrix:[Double]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
                    let context=SceneDesktopWallpaperLaunchContext(
                        propertyVectorScriptProgram:.compile(domain:domain,descriptor:descriptor,scriptBindings:[],userPropertyDefinitions:[],generation:1),
                        sceneScriptScalarProgram:.init(bindings:family=="scalar" ? p.bindings : []),
                        sceneScriptStringProgram:.init(bindings:family=="string" ? p.bindings : []),
                        sceneScriptCursorProgram:.init(bindings:[],generation:1))
                    for id in 1...2 { let configured=try context.configurePuppetBones(layerID:id,localMatrices:matrix,names:["root"]); precondition(configured) }
                    let missing=try context.configurePuppetBones(layerID:99,localMatrices:matrix,names:["root"])
                    precondition(!missing)
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

class SceneValueBoneMutationsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-value-bones-vm-") as temp:
            binary=compile_vector_harness(Path(temp),LAUNCH_STUBS+LAUNCH_SOURCE+HARNESS,"value-bones",
                extra_swift_sources=(VALIDATION_SOURCE,))
            run=subprocess.run([str(binary)],check=True,capture_output=True,text=True)
            cls.value=json.loads(run.stdout)
            print(json.dumps(cls.value,sort_keys=True))

    def test_init_user_media_update_keep_order_and_target(self):
        for family in ("scalar","string"):
            key=family+"-ordered"
            self.assertEqual(self.value[key+"Owners"],2)
            self.assertEqual(self.value[key+"Failure"],"none")
            self.assertEqual(self.value[key],["1:0:1.0","1:0:2.0","1:0:3.0","1:0:4.0","1:0:5.0","1:0:6.0","1:0:7.0"])

    def test_implicit_init_and_update_keep_bone_mutations(self):
        for family in ("scalar","string"):
            self.assertEqual(self.value[family+"-implicitInit"],["1:0:1.0","1:0:3.0"])

    def test_float_overflow_rejects_complete_bone_owner_and_preserves_peer(self):
        for name in ("impulse","matrix"):
            self.assertEqual(self.value["boneValidation"][name],
                {"failures":1,"commandCounts":[2],"ownerCommands":0,"peerCommands":["2:0:3.0"]})
        self.assertEqual(self.value["boneValidation"]["edge"],
            {"failures":0,"commandCounts":[],"ownerCommands":2,"peerCommands":["2:0:3.0"]})

    def test_rejected_owner_retries_without_replaying_accepted_peer(self):
        for family in ("scalar","string"):
            key=family+"-rejected"
            expected=["1:0:3.0","1:0:impulse:6.0,2.0,1.0"]
            self.assertEqual(self.value[key],expected)
            self.assertEqual(self.value[key+"Retry"],expected)
            self.assertEqual(self.value[key+"Peer"],["2:0:5.0"])
            self.assertEqual(self.value[key+"PeerRetry"],[])
            self.assertEqual(self.value[key+"Idle"],[])
            self.assertEqual(self.value[key+"Whole"],expected)
            self.assertEqual(self.value[key+"WholePeer"],["2:0:5.0"])

    def test_failed_callback_or_return_discards_only_failed_owner(self):
        for family in ("scalar","string"):
            for scenario,code in (("badReturn","bad-return"),("exception","exception")):
                key=family+"-"+scenario
                self.assertEqual(self.value[key+"Failure"],code)
                self.assertEqual(self.value[key],[])
                self.assertEqual(self.value[key+"Peer"],["2:0:5.0"])
