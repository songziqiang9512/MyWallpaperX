"""External model value candidates execute through the shared VM and material consumer."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness, SCENE

HARNESS = r'''
@main enum Harness {
    static func target(_ id: Int, _ name: String, _ path: String = "materials/shared.json") -> SceneDynamicTarget {
        .materialConstant(layerID:id,passIndex:0,name:name,materialPath:path)
    }
    static func emissionInputs() throws -> [String:Any] {
        var out:[String:Any] = [:]
        var descriptor = SceneRenderDescriptor(layers:(1...2).map { id in
            .init(id:id,layerIndex:id-1,name:"emission-\(id)",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],
                  alpha:1,effects:[],contentKind:"model",staticModelPath:"models/emission.mdl")
        })
        descriptor.modelMaterialLinks = [.init(modelPath:"models/emission.mdl",materialPath:"materials/shared.json")]
        let brightness = """
            export var scriptProperties = createScriptProperties();
            let n=0; export function update(v){
                n++; if(engine.runtime===3 && thisLayer.id===1)return {};
                if(engine.runtime===5 && thisLayer.id===1)return Number.MAX_VALUE;
                if(engine.runtime===6)return -1;
                return n+scriptProperties.strength+thisLayer.id;
            }
            """
        descriptor.materialPasses = [.init(materialPath:"materials/shared.json",passIndex:0,constantShaderValues:[
            "emissivebrightness":.init(scriptSource:brightness,components:[0],bindingKeys:["script","scriptproperties","value"],
                scriptProperties:["strength":.object(["user":.string("glow"),"value":.number(1)])]),
            "emissivecolor":.init(scriptSource:"""
                export var scriptProperties = createScriptProperties();
                let n=0; export function update(v){n++;return new Vec3(n/10,scriptProperties.green,thisLayer.id/10);}
                """,components:[0,0,0],bindingKeys:["script","scriptproperties","value"],
                scriptProperties:["green":.object(["user":.string("green"),"value":.number(0.2)])])
        ])]
        let catalog = SceneScriptVectorProgram.project(descriptor:descriptor,scriptBindings:[])
        out["targets"] = catalog.targets.count
        out["expectedTargets"] = catalog.targets == Set((1...2).flatMap { id in
            [target(id,"emissivebrightness"),target(id,"emissivecolor")]
        })
        let expectedInputs = Set((1...2).flatMap { id in
            [("emissivebrightness","strength"),("emissivecolor","green")].map { name, input in
                SceneDynamicTarget.scriptInstanceProperty(layerID:id,path:SceneScriptPropertyTargetPath.encoded([
                    .key("materials"),.key("materials/shared.json"),.key("passes"),.index(0),
                    .key("constantshadervalues"),.key(name),.key("scriptproperties"),.key(input)
                ]))
            }
        })
        out["liveInputTargets"] = catalog.uniqueCandidates.reduce(into:Set<SceneDynamicTarget>()) {
            $0.formUnion($1.livePropertyInputTargets)
        } == expectedInputs
        let domain = try SceneScriptQuickJSDomain()
        let program = SceneScriptVectorProgram.compile(domain:domain,descriptor:descriptor,scriptBindings:[],
            userPropertyDefinitions:[],generation:2)
        try domain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor)
        var current = Dictionary(uniqueKeysWithValues:program.definitions.map {($0.target,$0.authoredValue)})
        let base = SceneStaticModelMaterial(color:SIMD3(0.7,0.8,0.9),opacity:0.6,receivesLighting:false,
            textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,emissiveColor:.zero,
            emissiveBrightness:0,brightness:2,usesHDRBrightness:false,viewTint:nil)
        for time in 0...7 {
            if time > 0 {
                let properties:[String:SceneUserPropertyValue]
                switch time {
                case 2,3: properties = ["glow":.number(4),"green":.number(0.6)]
                case 4,5: properties = ["glow":.number(7),"green":.number(0.9)]
                default: properties = [:]
                }
                let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:Double(time)),simulationFrameTime:0.1,sceneTime:Double(time)))
                let result = program.evaluate(inputs:current,effectivePropertyValues:properties,frame:frame)
                for (key,value) in result.values {current[key] = value}
                program.finalizeLayerMutations(committing:true,rejectedOwnerTargets:Set(result.failures.keys))
                out["failures\(time)"] = result.failures.count
                out["onlyBrightnessOneFailed\(time)"] = Set(result.failures.keys) == [target(1,"emissivebrightness")]
            }
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex:UInt64(time),generation:2,
                definitions:program.definitions,sceneScriptValues:current).snapshot
            let materials = (1...2).map { base.resolvingDynamicValues(layerID:$0,materialPath:"materials/shared.json",snapshot:snapshot) }
            out["brightness\(time)"] = materials.map {Double($0.emissiveBrightness)}
            out["colors\(time)"] = materials.map {[Double($0.emissiveColor.x),Double($0.emissiveColor.y),Double($0.emissiveColor.z)]}
            out["ordinaryMaterialPreserved\(time)"] = materials.allSatisfy {
                $0.color == base.color && $0.opacity == base.opacity && $0.brightness == base.brightness
            }
            let foreign = base.resolvingDynamicValues(layerID:1,materialPath:"materials/other.json",snapshot:snapshot)
            out["foreignMaterialPreserved\(time)"] = foreign.emissiveBrightness == 0 && foreign.emissiveColor == .zero
        }
        var rejected = descriptor
        rejected.materialPasses[0].staticModelMaterialBindings = .init(state:.rejected,bindings:[],rejectionReason:"fixture")
        out["rejectedMaterialCount"] = SceneScriptVectorProgram.project(descriptor:rejected,scriptBindings:[]).targets.count
        var authored = descriptor
        authored.materialPasses[0].staticModelMaterialBindings = .init(state:.authored,bindings:[],rejectionReason:nil)
        out["authoredOptionalCount"] = SceneScriptVectorProgram.project(descriptor:authored,scriptBindings:[]).targets.count
        var aliased = descriptor
        aliased.materialPasses[0].staticModelMaterialBindings = .init(state:.authored,bindings:[
            .init(channel:.brightness,uniformName:"u_Brightness",materialKey:"emissivebrightness",components:[0])
        ],rejectionReason:nil)
        let aliasedCatalog = SceneScriptVectorProgram.project(descriptor:aliased,scriptBindings:[])
        out["aliasedTargetCount"] = aliasedCatalog.targets.count
        out["aliasedOwnersUnique"] = aliasedCatalog.duplicateTargets.isEmpty
        var conflict = descriptor
        conflict.materialPasses = [.init(materialPath:"materials/shared.json",passIndex:0,constantShaderValues:[
            "emissivebrightness":.init(scriptSource:brightness,components:[0],userValueKind:.string,bindingKeys:["script","user","value"]),
            "emissivecolor":.init(scriptSource:"export function update(v){return v;}",components:[0,0,0],bindingKeys:["animation","script","value"],timeline:true)
        ])]
        out["conflictCount"] = SceneScriptVectorProgram.project(descriptor:conflict,scriptBindings:[]).targets.count
        return out
    }
    static func main() throws {
        var out:[String:Any] = [:]
        var descriptor = SceneRenderDescriptor(layers:(1...2).map { id in
            .init(id:id,layerIndex:id-1,name:"model-\(id)",visible:id == 2,originXYZ:[0,0,0],scaleXYZ:[1,1,1],
                  alpha:1,effects:[],contentKind:"model",staticModelPath:"models/shared.mdl")
        })
        descriptor.modelMaterialLinks = [.init(modelPath:"models/shared.mdl",materialPath:"materials/shared.json")]
        let brightness = """
            let n=0; export function update(v){
                n++; if(engine.runtime===3 && thisLayer.id===1)return {};
                if(engine.runtime===5 && thisLayer.id===1)return Number.MAX_VALUE;
                return n+(shared.mode||0)+thisLayer.id;
            }
            """
        descriptor.materialPasses = [.init(materialPath:"materials/shared.json",passIndex:0,constantShaderValues:[
            "brightness":.init(scriptSource:brightness,components:[1],bindingKeys:["script","value"]),
            "color":.init(scriptSource:"""
                export var scriptProperties = createScriptProperties();
                export function update(v){return new Vec3((shared.mode||0)/10,scriptProperties.green,thisLayer.id/10);}
                """,components:[1,1,1],bindingKeys:["script","scriptproperties","value"],scriptProperties:["green":.number(0.4)])
        ])]
        let catalog = SceneScriptVectorProgram.project(descriptor:descriptor,scriptBindings:[],admittedLayerColorConsumerIDs:[2])
        out["targets"] = catalog.targets.count
        out["allMaterialTargets"] = catalog.targets.allSatisfy { if case .materialConstant = $0 {return true};return false }
        let domain = try SceneScriptQuickJSDomain()
        let program = SceneScriptVectorProgram.compile(domain:domain,descriptor:descriptor,scriptBindings:[],
            userPropertyDefinitions:[],admittedLayerColorConsumerIDs:[2],generation:1)
        try domain.publishLayerSnapshot(.empty(frameIndex:0),descriptor:descriptor)
        let producer = try SceneScriptValueOwner(domain:domain,source:"export function update(v){shared.mode=engine.runtime===1?0:5;if(engine.runtime===2)thisScene.getLayer(\"model-1\").visible=true;return v;}",
            target:.layer(layerID:2,field:.origin),effectNames:[],allowsStatefulLayerSideEffects:true,generation:1,budget:.default)
        var current = Dictionary(uniqueKeysWithValues:program.definitions.map {($0.target,$0.authoredValue)})
        let base = SceneStaticModelMaterial(color:SIMD3(1,1,1),opacity:1,receivesLighting:false,
            textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,emissiveColor:.zero,
            emissiveBrightness:0,brightness:1,usesHDRBrightness:false,viewTint:nil)
        for time in 1...5 {
            let frame = SceneScriptFrameInput(timing:.init(wallDate:Date(timeIntervalSince1970:Double(time)),simulationFrameTime:0.1,sceneTime:Double(time)))
            let publication = producer.evaluate(input:.vector3(0,0,0),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
            if time == 2, case let .success(value) = publication {
                out["peerMutationDetails"] = String(describing:value.layerMutations)
                out["peerRevealedHiddenModel"] = value.layerMutations.contains { $0.layerID == 1 && $0.visible && $0.fields.contains(.visibility) }
            }
            producer.commitLayerMutations()
            let result = program.evaluate(inputs:current,effectivePropertyValues:[:],frame:frame)
            for (key,value) in result.values {current[key] = value}
            program.finalizeLayerMutations(committing:true,rejectedOwnerTargets:Set(result.failures.keys))
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex:UInt64(time),generation:1,
                definitions:program.definitions,sceneScriptValues:current).snapshot
            let materials = (1...2).map { base.resolvingDynamicValues(layerID:$0,materialPath:"materials/shared.json",snapshot:snapshot) }
            out["brightness\(time)"] = materials.map {Double($0.brightness)}
            out["colors\(time)"] = materials.map {[Double($0.color.x),Double($0.color.y),Double($0.color.z)]}
            out["failures\(time)"] = result.failures.count
            out["foreignPath\(time)"] = Double(base.resolvingDynamicValues(layerID:1,materialPath:"materials/other.json",snapshot:snapshot).brightness)
        }
        var rejected = descriptor
        rejected.materialPasses[0].staticModelMaterialBindings = .init(state:.rejected,bindings:[],rejectionReason:"fixture")
        out["rejectedMaterialCount"] = SceneScriptVectorProgram.project(descriptor:rejected,scriptBindings:[],admittedLayerColorConsumerIDs:[2]).targets.count
        var conflict = descriptor
        conflict.materialPasses = [.init(materialPath:"materials/shared.json",passIndex:0,constantShaderValues:[
            "brightness":.init(scriptSource:brightness,components:[1],userValueKind:.string,bindingKeys:["script","user","value"]),
            "color":.init(scriptSource:"export function update(v){return v;}",components:[1,1,1],bindingKeys:["animation","script","value"],timeline:true)
        ])]
        out["conflictCount"] = SceneScriptVectorProgram.project(descriptor:conflict,scriptBindings:[],admittedLayerColorConsumerIDs:[2]).targets.count
        out["emission"] = try emissionInputs()
        let data = try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]);print(String(decoding:data,as:UTF8.self))
    }
}
'''

class SceneModelMaterialScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-model-material-script-")
        cls.addClassCleanup(cls.directory.cleanup)
        root = Path(cls.directory.name)
        # Compile the complete value owner, excluding unrelated GPU buffer/PSO construction.
        consumer = SCENE / "Rendering/Metal/SceneStaticModelMaterial.swift"
        binary = compile_vector_harness(root,HARNESS,"model-material",extra_swift_sources=(consumer,))
        result = subprocess.run([str(binary)],capture_output=True,text=True,check=True,timeout=15)
        cls.result = json.loads(result.stdout)

    def test_shared_input_private_state_and_instance_identity_reach_consumer(self):
        self.assertEqual(self.result["targets"],4)
        self.assertTrue(self.result["peerRevealedHiddenModel"], self.result.get("peerMutationDetails"))
        self.assertTrue(self.result["allMaterialTargets"])
        self.assertEqual(self.result["brightness1"],[2,3])
        self.assertEqual(self.result["brightness2"],[8,9])
        for i, color in enumerate(self.result["colors2"]):
            for actual, expected in zip(color,[0.5,0.4,(i+1)/10]):
                self.assertAlmostEqual(actual,expected,places=6)
        self.assertEqual(self.result["foreignPath2"],1)

    def test_bad_return_preserves_only_its_previous_value_and_recovers(self):
        self.assertEqual(self.result["failures3"],1)
        self.assertEqual(self.result["brightness3"],[8,10])
        self.assertEqual(self.result["failures4"],0)
        self.assertEqual(self.result["brightness4"],[10,11])
        self.assertEqual(self.result["failures5"],1)
        self.assertEqual(self.result["brightness5"],[10,12])

    def test_rejected_material_and_multiple_producers_stay_unadmitted(self):
        self.assertEqual(self.result["rejectedMaterialCount"],0)
        self.assertEqual(self.result["conflictCount"],0)

    def test_optional_emission_zero_seeds_and_live_input_identity_reach_consumer(self):
        emission = self.result["emission"]
        self.assertEqual(emission["targets"],4)
        self.assertTrue(emission["expectedTargets"])
        self.assertTrue(emission["liveInputTargets"])
        self.assertEqual(emission["brightness0"],[0,0])
        self.assertEqual(emission["colors0"],[[0,0,0],[0,0,0]])
        self.assertEqual(emission["brightness1"],[3,4])
        self.assertEqual(emission["brightness2"],[7,8])
        self.assertEqual(emission["brightness4"],[12,13])
        for time, green in [(1,0.2),(2,0.6),(4,0.9),(7,0.2)]:
            for i, color in enumerate(emission[f"colors{time}"]):
                for actual, expected in zip(color,[time/10,green,(i+1)/10]):
                    self.assertAlmostEqual(actual,expected,places=6)
        for time in range(8):
            self.assertTrue(emission[f"ordinaryMaterialPreserved{time}"])
            self.assertTrue(emission[f"foreignMaterialPreserved{time}"])

    def test_emission_bad_return_is_local_and_next_frame_recovers(self):
        emission = self.result["emission"]
        self.assertEqual(emission["failures3"],1)
        self.assertTrue(emission["onlyBrightnessOneFailed3"])
        self.assertEqual(emission["brightness3"],[7,9])
        self.assertEqual(emission["failures4"],0)
        self.assertEqual(emission["failures5"],1)
        self.assertTrue(emission["onlyBrightnessOneFailed5"])
        self.assertEqual(emission["brightness5"],[12,14])
        self.assertEqual(emission["failures6"],0)
        self.assertEqual(emission["brightness6"],[0,0])
        self.assertEqual(emission["failures7"],0)
        self.assertEqual(emission["brightness7"],[9,10])

    def test_optional_emission_preserves_material_rejection_and_conflict_rules(self):
        emission = self.result["emission"]
        self.assertEqual(emission["authoredOptionalCount"],4)
        self.assertEqual(emission["aliasedTargetCount"],4)
        self.assertTrue(emission["aliasedOwnersUnique"])
        self.assertEqual(emission["rejectedMaterialCount"],0)
        self.assertEqual(emission["conflictCount"],0)
