#!/usr/bin/env python3

from __future__ import annotations

import os
from contextlib import nullcontext
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from .test_scene_prepared_script_resource_catalog import swift_declaration


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE_ROOT / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift",
    SCENE_ROOT / "Runtime/Frame/SceneStaticModelMaterialBindings.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Compilation/Material/SceneEffectTextureInput.swift",
    SCENE_ROOT / "Compilation/Material/SceneRenderTargetVocabulary.swift",
    SCENE_ROOT / "Resources/Textures/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Systems/Script/SceneScriptPropertyInput.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyBindings.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgram.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgramValidator.swift",
    SCENE_ROOT / "Systems/Properties/ScenePropertyLiveUpdateState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneMaterialPropertyBindingCompiler.swift",
]

STUBS = r'''
enum SceneScriptBindingPathComponent { case key(String), index(Int) }
struct SceneScriptBindingIR {
    struct Owner { let objectID: Int? }
    let owner: Owner
    let targetPath: [SceneScriptBindingPathComponent]
}
enum SceneBaseMaterialColorModulationCompiler {
    __BASE_MATERIAL_BINDING__
}

enum SceneShaderUserValueKind {
    case null, boolean, number, string, array, object
}

struct SceneDocument {
    struct SceneLayerMaterialInstance { let isMalformed: Bool; let combos: [String:Int]; let scalarShaderValues: [String:ShaderValue]? }
    struct ShaderValue {
        let userBinding: String?
        let userValueKind: SceneShaderUserValueKind?
        let components: [Double]?
        let bindingKeys: [String]
        let scriptSource: String? = nil
        let scriptProperties: [String: SceneJSONValue]? = nil
        let timeline: Int? = nil
        let timelineDiagnostics: [String] = []
        let rawValue: String
        let valueKind: String

        init(
            userBinding: String?, userValueKind: SceneShaderUserValueKind?,
            components: [Double]?, bindingKeys: [String],
            rawValue: String? = nil, valueKind: String? = nil
        ) {
            self.userBinding = userBinding
            self.userValueKind = userValueKind
            self.components = components
            self.bindingKeys = bindingKeys
            self.rawValue = rawValue ?? (components ?? []).map { String($0) }.joined(separator: " ")
            self.valueKind = valueKind ?? (userBinding == nil
                ? (components?.count == 1 ? "number" : "vector") : "binding")
        }
    }
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let puppetMeshPath: String? = nil
        let staticModelPath: String?
        let isImageRenderable = false
        let imagePath: String? = nil
        var staticBaseTexturePath: String? = nil
    }

    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }

    struct MaterialPassDescriptor {
        let materialPath: String
        let passIndex: Int
        var shaderPath: String? = nil
        var combos: [String:Int] = [:]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        var userShaderValues: [String: String] = [:]
        var texturePaths: [String] = []
        var textureSlots: [String?] = []
        var userTextureInputs: [SceneEffectTextureInput?] = []
        var staticModelMaterialBindings: SceneStaticModelMaterialBindings? = nil
    }

    let layers: [Layer]
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
}
'''
STUBS = STUBS.replace("__BASE_MATERIAL_BINDING__", swift_declaration(
    (SCENE_ROOT / "Compilation/Material/SceneBaseMaterialColorModulationCompiler.swift").read_text(),
    "    struct Binding: Sendable {",
))

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() {
        let values: [String: SceneDocument.ShaderValue] = [
            "color": wrapper("tint", [1, 1, 1]),
            "emissivecolor": wrapper("emissive", [1, 0.5, 0.25]),
            "alpha": wrapper("opacity", [0.8]),
            "brightness": wrapper("brightness", [1]),
            "emissivebrightness": wrapper("emissiveBrightness", [2]),
            "metallic": wrapper("metallic", [1]),
            "roughness": .init(
                userBinding: "roughness", userValueKind: .string,
                components: [1], bindingKeys: ["extra", "user", "value"]
            ),
        ]
        let pass0 = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/model.json",
            passIndex: 0,
            constantShaderValues: values
        )
        let pass1 = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/model.json",
            passIndex: 1,
            constantShaderValues: [:]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                .init(id: 7, staticModelPath: "models/a.mdl"),
                .init(id: 8, staticModelPath: "MODELS\\A.MDL"),
            ],
            modelMaterialLinks: [
                .init(
                    modelPath: "models/a.mdl",
                    materialPath: "MATERIALS\\MODEL.JSON"
                ),
            ],
            materialPasses: [pass0, pass1]
        )
        let bindings = SceneMaterialPropertyBindingCompiler.compile(
            descriptor: descriptor, materialInstancesByLayerID: [:]
        )
        precondition(bindings.count == 10)

        let compiler = ScenePropertyBindingCompiler()
        let compilation = compiler.compile(
            report: .init(bindings: bindings, diagnostics: []),
            catalog: .init(definitions: [
                property("tint", .color, .string("1 1 1")),
                property("emissive", .color, .string("1 0.5 0.25")),
                property("opacity", .slider, .number(0.8), 0, 1),
                property("brightness", .slider, .number(1), 0, 2),
                property("emissiveBrightness", .slider, .number(2), 0, 10),
                property("metallic", .slider, .number(1), 0, 1),
                property("roughness", .slider, .number(1), 0, 1),
            ])
        )
        precondition(compilation.diagnostics.isEmpty)
        precondition(compilation.program.definitions.count == 10)
        precondition(compilation.program.instructions.count == 10)
        let evaluation = compilation.program.evaluate(effectiveValues: [
            "tint": .string("0.2 0.4 0.6"),
            "emissive": .string("0.9 0.3 0.1"),
            "opacity": .number(0.4),
            "brightness": .number(1.75),
            "emissiveBrightness": .number(3),
            "metallic": .number(0.2),
            "roughness": .number(0.2),
        ])
        precondition(evaluation.diagnostics.isEmpty)
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 4,
            generation: 9,
            definitions: compilation.program.definitions,
            userValues: evaluation.userValues
        ).snapshot
        for layerID in [7, 8] {
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "color", materialPath: "materials/model.json"
            )]?.value == .vector3(0.2, 0.4, 0.6))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "emissivecolor", materialPath: "materials/model.json"
            )]?.value == .vector3(0.9, 0.3, 0.1))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "alpha", materialPath: "materials/model.json"
            )]?.value == .scalar(0.4))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "brightness", materialPath: "materials/model.json"
            )]?.value == .scalar(1.75))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0,
                name: "emissivebrightness", materialPath: "materials/model.json"
            )]?.value == .scalar(3))
        }

        let invalidEvaluation = compilation.program.evaluate(effectiveValues: [
            "tint": .string("0.2 0.4 0.6"),
            "emissive": .string("0.9 0.3 0.1"),
            "opacity": .number(0.4),
            "brightness": .number(3),
            "emissiveBrightness": .number(3),
        ])
        precondition(invalidEvaluation.userValues[.materialConstant(
            layerID: 7, passIndex: 0, name: "brightness", materialPath: "materials/model.json"
        )] == nil)

        let duplicatePassDescriptor = SceneRenderDescriptor(
            layers: [.init(id: 7, staticModelPath: "models/a.mdl")],
            modelMaterialLinks: descriptor.modelMaterialLinks,
            materialPasses: [pass0, pass0]
        )
        precondition(SceneMaterialPropertyBindingCompiler.compile(
            descriptor: duplicatePassDescriptor, materialInstancesByLayerID: [:]
        ).isEmpty)

        let multipart = SceneRenderDescriptor(
            layers: descriptor.layers,
            modelMaterialLinks: descriptor.modelMaterialLinks + [
                .init(modelPath: "models/a.mdl", materialPath: "materials/other.json")
            ],
            materialPasses: [pass0, .init(
                materialPath: "materials/other.json", passIndex: 0,
                constantShaderValues: ["color": wrapper("emissive", [1, 0.5, 0.25])]
            )]
        )
        let multiBindings = SceneMaterialPropertyBindingCompiler.compile(descriptor: multipart, materialInstancesByLayerID: [:])
        precondition(multiBindings.count == 12)
        let mapped = multiBindings.compactMap {
            ScenePropertyBindingCompiler.map($0, propertyKind: nil)?.target
        }
        precondition(Set(mapped).count == 12)
        for layerID in [7, 8] {
            precondition(mapped.contains(.materialConstant(
                layerID: layerID, passIndex: 0, name: "color", materialPath: "materials/other.json"
            )))
            precondition(mapped.contains(.materialConstant(
                layerID: layerID, passIndex: 0, name: "color", materialPath: "materials/model.json"
            )))
        }
        nestedMaterialInputs()
    }

    static func nestedMaterialInputs() {
        let brightnessInputs = SceneScriptPropertyInputCodec.inputs([
            "minvalue": .object(["user": .string("minimum"), "value": .number(0)]),
            "smooth": .object(["user": .string("smooth"), "value": .number(0)]),
            "literal": .number(2),
        ])!
        let colorInputs = SceneScriptPropertyInputCodec.inputs([
            "green": .object(["user": .string("green"), "value": .number(0.2)]),
        ])!
        // Reuse one material asset while preserving each layer and field's VM identity.
        let descriptor = SceneRenderDescriptor(
            layers: [.init(id: 7, staticModelPath: "models/a.mdl"),
                     .init(id: 8, staticModelPath: "models/a.mdl"),
                     .init(id: 9, staticModelPath: nil)],
            modelMaterialLinks: [.init(modelPath: "models/a.mdl", materialPath: "materials/model.json")],
            materialPasses: [.init(materialPath: "materials/model.json", passIndex: 0,
                                  constantShaderValues: [:])]
        )
        var entries: [(target: SceneDynamicTarget, inputs: [String: SceneScriptPropertyInput])] = []
        var expectedTargets: Set<SceneDynamicTarget> = []
        for layerID in [7, 8] {
            for (name, inputs) in [("emissivebrightness", brightnessInputs), ("emissivecolor", colorInputs)] {
                entries.append((.materialConstant(layerID: layerID, passIndex: 0,
                    name: name, materialPath: "materials/model.json"), inputs))
                let path: [SceneUserPropertyPathComponent] = [
                    .key("materials"), .key("materials/model.json"), .key("passes"), .index(0),
                    .key("constantshadervalues"), .key(name),
                ]
                expectedTargets.formUnion(SceneScriptPropertyInputCodec.liveConsumerTargets(
                    layerID: layerID, targetPath: SceneScriptPropertyTargetPath.encoded(path), inputs: inputs
                ))
            }
        }
        let bindings = SceneMaterialPropertyBindingCompiler.compile(
            descriptor: descriptor, materialInstancesByLayerID: [:], modelScriptInputs: entries
        )
        precondition(bindings.count == 6)
        let compilation = ScenePropertyBindingCompiler().compile(
            report: .init(bindings: bindings, diagnostics: []),
            catalog: .init(definitions: [
                property("minimum", .slider, .number(1), 0, 1),
                property("smooth", .slider, .number(0), 0, 28),
                property("green", .slider, .number(0.2), 0, 1),
            ])
        )
        precondition(compilation.diagnostics.isEmpty)
        let targets = Set(compilation.program.instructions.map(\.target))
        precondition(targets == expectedTargets && targets.count == 6)
        precondition(compilation.program.rebuildRequiredPropertyKeys.isEmpty)
        // Inputs remain script-instance properties; only the VM produces material constants.
        precondition(targets.allSatisfy { if case .scriptInstanceProperty = $0 { return true }; return false })
        var state = ScenePropertyLiveUpdateState(
            program: compilation.program,
            effectiveValues: ["minimum": .number(1), "smooth": .number(0), "green": .number(0.2)],
            activeConsumerTargets: targets
        )
        precondition(state.apply(.number(0), forPropertyKey: "minimum"))
        precondition(state.apply(replacements: ["smooth": .number(4), "green": .number(0.8)],
                                 changedPropertyKeys: ["smooth", "green"]))
        precondition(state.revision == 2)
        for instruction in compilation.program.instructions {
            let expected: Double = instruction.propertyKey == "minimum" ? 0
                : instruction.propertyKey == "smooth" ? 4 : 0.8
            precondition(state.userValues[instruction.target] == .scalar(expected))
        }
        let json = SceneScriptPropertyInputCodec.scriptPropertiesJSON(
            brightnessInputs, effectiveValues: state.effectiveValues
        )!
        let object = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Double]
        precondition(object == ["minvalue": 0, "smooth": 4, "literal": 2])
        let before = state
        for invalid in [SceneUserPropertyValue.string("bad"), .number(.nan), .number(2)] {
            precondition(!state.apply(replacements: ["minimum": invalid, "smooth": .number(5)],
                                      changedPropertyKeys: ["minimum", "smooth"]))
            unchanged(state, before)
        }
        let unavailable = compilation.program.instructions.first { $0.propertyKey == "smooth" }!.target
        precondition(!state.apply(.number(5), forPropertyKey: "smooth", unavailableConsumerTargets: [unavailable]))
        unchanged(state, before)
        var missingConsumer = ScenePropertyLiveUpdateState(
            program: compilation.program, effectiveValues: state.effectiveValues,
            activeConsumerTargets: targets.subtracting([unavailable])
        )
        let missingBefore = missingConsumer
        precondition(!missingConsumer.apply(.number(5), forPropertyKey: "smooth"))
        unchanged(missingConsumer, missingBefore)
        precondition(SceneMaterialPropertyBindingCompiler.compile(
            descriptor: descriptor, materialInstancesByLayerID: [:], modelScriptInputs: [
                (.layer(layerID: 7, field: .color), brightnessInputs),
                (.materialConstant(layerID: 9, passIndex: 0, name: "emissivebrightness",
                    materialPath: "materials/model.json"), brightnessInputs),
                (.materialConstant(layerID: 404, passIndex: 0, name: "emissivebrightness",
                    materialPath: "materials/model.json"), brightnessInputs),
            ]
        ).isEmpty)
        let metadataInput = SceneScriptPropertyInputCodec.inputs([
            "minvalue": .object(["user": .string("minimum"), "value": .number(0), "extra": .bool(true)])
        ])!
        precondition(metadataInput["minvalue"]?.resolve(effectiveValues: ["minimum": .number(0.75)]) == .number(0.75))
        precondition(SceneScriptPropertyInputCodec.inputs([
            "minvalue": .object(["user": .number(7), "value": .number(0)])
        ]) == nil)
        print("nested-material-live-transaction: OK")
    }

    static func unchanged(_ state: ScenePropertyLiveUpdateState, _ before: ScenePropertyLiveUpdateState) {
        precondition(state.effectiveValues == before.effectiveValues)
        precondition(state.userValues == before.userValues)
        precondition(state.revision == before.revision)
    }

    static func wrapper(
        _ property: String,
        _ components: [Double]
    ) -> SceneDocument.ShaderValue {
        .init(
            userBinding: property,
            userValueKind: .string,
            components: components,
            bindingKeys: ["user", "value"]
        )
    }

    static func property(
        _ key: String,
        _ kind: SceneUserPropertyKind,
        _ value: SceneUserPropertyValue,
        _ minimum: Double? = nil,
        _ maximum: Double? = nil
    ) -> SceneUserPropertyDefinition {
        .init(
            key: key, title: key, kind: kind, runtimeType: kind.rawValue,
            order: 0, index: nil, minimumValue: minimum,
            maximumValue: maximum, stepValue: nil,
            allowsFractionalValues: true, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: value, options: []
        )
    }
}
'''


class SceneStaticModelMaterialPropertyTests(unittest.TestCase):
    def run_surface_profile_probe(self, main, label, evidence):
        document = (SCENE_ROOT / "Format/SceneDocument.swift").read_text()
        support = STUBS.replace(swift_declaration(STUBS, "enum SceneShaderUserValueKind {"), "")
        support = support.replace(swift_declaration(support, "    struct ShaderValue {"), "")
        parser = "\nenum SceneDocumentLoader {\n" + "\n".join(swift_declaration(document, signature) for signature in [
            "    nonisolated static func shaderValue(", "    nonisolated private static func scriptProperties(",
            "    nonisolated private static func stringValue(",
            "    nonisolated private static func uniqueSorted(",
        ]) + "\n}\n"
        surface = swift_declaration((SCENE_ROOT / "Rendering/Metal/SceneStaticModelMaterial.swift").read_text(),
                                    "struct SceneStaticModelSurfaceProfile:")
        profile = swift_declaration((SCENE_ROOT / "Resources/Textures/ScenePreparedStaticModelResources.swift").read_text(),
                                    "    static func surfaceProfile(")
        boundary = r'''
// This CPU probe supplies resolved source roles, not a VFS implementation.
// Real root selection and texture availability belong to the native/App gates.
struct SceneResourceView {
 enum Source {case stock,loose,package}
 struct Resource {let source:Source}
 var sources:[String:Source]=[:]
 func resolvedResource(relativePath:String)->Resource? {sources[relativePath].map{Resource(source:$0)}}
}
'''
        sources = [*SOURCES, SCENE_ROOT / "Format/SceneDocument+ShaderValue.swift",
                   SCENE_ROOT / "Format/SceneTimelineAnimation.swift"]
        parent = os.environ.get(evidence)
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        directory = (nullcontext(tempfile.mkdtemp(prefix="mwx-" + label + "-", dir=parent)) if parent
                     else tempfile.TemporaryDirectory(prefix="mwx-" + label + "-"))
        with directory as temporary:
            work = Path(temporary)
            source, binary = work / "Harness.swift", work / "probe"
            source.write_text("import Foundation\n" + support + parser + boundary + surface
                              + "\nenum ScenePreparedStaticModelResources {\n" + profile + "\n}\n" + main)
            compiled = subprocess.run(["xcrun", "swiftc", *map(str, sources), str(source),
                "-module-cache-path", str(work / "cache"), "-o", str(binary)], capture_output=True, text=True)
            (work / "compile.stdout").write_text(compiled.stdout)
            (work / "compile.stderr").write_text(compiled.stderr)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            (work / "run.stdout").write_text(result.stdout)
            (work / "run.stderr").write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(label + ": OK", result.stdout)

    def test_real_shader_value_and_surface_profile_keep_rim_failures_local(self):
        main = r'''
@main enum RimSurfaceAdmissionProbe {
 static func main() {
  func parsed(_ raw:Any)->SceneDocument.ShaderValue {SceneDocumentLoader.shaderValue(from:raw)}
  func profile(_ amount:Any?=nil,_ exponent:Any?=nil,combo:Int?=1,lighting:Int=1,
               users:[String:String]=[:])->SceneStaticModelSurfaceProfile {
   var constants=["metallic":parsed(0.25),"roughness":parsed(0.75),"reflectivity":parsed(0.5)]
   if let amount {constants["rimamount"]=parsed(amount)}
   if let exponent {constants["rimexponent"]=parsed(exponent)}
   var pass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"surface",passIndex:0,
       shaderPath:"generic4",combos:["LIGHTING":lighting,"REFLECTION":1],constantShaderValues:constants)
   if let combo {pass.combos["RIMLIGHTING"]=combo}
   pass.userShaderValues=users
   let result=ScenePreparedStaticModelResources.surfaceProfile(pass,resourceView:.init())!
   precondition(result.metallic == 0.25 && result.roughness == 0.75 && result.reflectivity == 0.5,
                "A bad rim unit must not retire the valid material profile")
   return result
  }
  let valid:[Any] = [2.0,"2e0",["value":2.0],["value":"2","user":NSNull()]]
  for raw in valid {
   let result=profile(raw)
   precondition(result.rimAmount == 2 && result.rimExponent == 4)
  }
  precondition(profile().rimAmount == 2 && profile().rimExponent == 4)
  for combo in [2,-1] {precondition(profile(combo:combo).rimAmount == 2)}
  let disabled:[Int?] = [nil,0]
  for combo in disabled {precondition(profile(combo:combo).rimAmount == 0)}
  precondition(profile(lighting:0).rimAmount == 0)
  precondition(profile(0).rimAmount == 0)
  precondition(profile(2,0).rimExponent == 0)
  precondition(profile(-2).rimAmount == 0)
  precondition(profile(2,-4).rimExponent == 0)
  precondition(profile(1e300,1e300).rimAmount == Float.greatestFiniteMagnitude)
  precondition(profile(1e300,1e300).rimExponent == Float.greatestFiniteMagnitude)
  let timeline:[String:Any] = ["options":["fps":30,"length":30,"mode":"loop"],
      "c0":[["frame":0,"value":2],["frame":30,"value":3]]]
  precondition(parsed(["value":2,"animation":timeline]).timeline != nil)
  let bad:[Any] = ["2 junk","2 3","inf","nan",NSNull(),[2,3],
      ["value":2,"user":"gain"],["value":2,"user":17],
      ["value":2,"script":"export function update(v){return v;}"],
      ["value":2,"script":17],["value":2,"animation":17],
      ["value":2,"animation":timeline]]
  for raw in bad {
   precondition(profile(raw).rimAmount == 0)
   precondition(profile(2,raw).rimAmount == 0)
  }
  for key in ["rimamount","rimexponent"] {
   precondition(profile(users:[key:"property"]).rimAmount == 0)
  }
  for key in ["script","animation"] {
   let value=parsed(["value":2,key:17])
   precondition(value.bindingKeys.contains(key) && value.scriptSource == nil && value.timeline == nil)
  }
  print("rim-surface-admission: OK")
 }
}
'''
        self.run_surface_profile_probe(main, "rim-surface-admission", "MWX_MODEL_RIM_EVIDENCE")

    def test_real_shader_value_and_surface_profile_keep_chroma_tint_failures_local(self):
        main = r'''
@main enum ChromaSurfaceAdmissionProbe {
 static func main() {
  func parsed(_ raw:Any)->SceneDocument.ShaderValue {SceneDocumentLoader.shaderValue(from:raw)}
  func profile(_ tint:Any?=nil,shader:String?="chroma4",lighting:Int=1,
               users:[String:String]=[:],sources:[String:SceneResourceView.Source]=[:],
               replacing:[String:Any]=[:])->SceneStaticModelSurfaceProfile? {
   var constants=["metallic":parsed(0.25),"roughness":parsed(0.75),"reflectivity":parsed(0.5)]
   if let tint {constants["speculartint"]=parsed(tint)}
   for (key,raw) in replacing {constants[key]=parsed(raw)}
   var pass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"surface",passIndex:0,
       shaderPath:shader,combos:["LIGHTING":lighting,"REFLECTION":1],constantShaderValues:constants)
   pass.userShaderValues=users
   let result=ScenePreparedStaticModelResources.surfaceProfile(pass,resourceView:.init(sources:sources))
   if let result {
    precondition(result.metallic == 0.25 && result.roughness == 0.75 && result.reflectivity == 0.5,
                 "A bad specular tint must not retire valid common surface data")
   }
   return result
  }
  let white=SIMD3<Float>(repeating:1), tint=SIMD3<Float>(0,0.5,1)
  precondition(profile()!.kind == .chroma4 && profile()!.specularTint == white)
  precondition(profile(lighting:0)!.kind == .chroma4)
  precondition(profile(shader:"ChRoMa4")!.kind == .chroma4)
  precondition(profile(shader:"generic4")!.kind == .generic4)
  let defaults=SceneStaticModelSurfaceProfile(metallic:0,roughness:0.7)
  precondition(defaults.kind == .generic4 && defaults.specularTint == white)
  let valid:[Any] = ["0 5e-1 1",["value":"0 0.5 1"],
      ["value":"0 0.5 1","user":NSNull()]]
  for raw in valid {
   precondition(profile(raw)!.specularTint == tint)
   precondition(profile(raw,shader:"generic4")!.specularTint == white)
  }
  for raw:Any in [0.2,"2e-1",["value":0.2],["value":0.2,"user":NSNull()]] {
   precondition(profile(replacing:["tintpigmentation":raw])!.pigmentAmount == 0.2)
   precondition(profile(lighting:0,replacing:["tintpigmentation":raw])!.pigmentAmount == 0)
   precondition(profile(shader:"generic4",replacing:["tintpigmentation":raw])!.pigmentAmount == 0)
  }
  precondition(profile()!.pigmentAmount == 0)
  precondition(profile(replacing:["tintpigmentation":-1])!.pigmentAmount == 0)
  precondition(profile(replacing:["tintpigmentation":1e300])!.pigmentAmount == 1)
  let invalidAmount:[Any] = [NSNull(),"bad","0.2 0.4","nan","inf",
      ["value":0.2,"user":"amount"],["value":0.2,"user":17],
      ["value":0.2,"script":"export function update(v){return v;}"],
      ["value":0.2,"script":17],["value":0.2,"animation":17]]
  for raw in invalidAmount {
   precondition(profile(replacing:["tintpigmentation":raw])!.pigmentAmount == 0)
  }
  precondition(profile(users:["tintpigmentation":"property"],
      replacing:["tintpigmentation":0.2])!.pigmentAmount == 0)
  precondition(profile("-1 2 1e300")!.specularTint == SIMD3(0,2,Float.greatestFiniteMagnitude))
  let timeline:[String:Any] = ["options":["fps":30,"length":30,"mode":"loop"],
      "c0":[["frame":0,"value":0],["frame":30,"value":1]],
      "c1":[["frame":0,"value":0.5],["frame":30,"value":0.5]],
      "c2":[["frame":0,"value":1],["frame":30,"value":0]]]
  let animated:[String:Any] = ["value":"0 0.5 1","animation":timeline]
  precondition(parsed(animated).timeline != nil)
  let bad:[Any] = [NSNull(),17,"not a vector","0 1","0 0.5 1 2",[0.0,0.5],
      "0 nan 1","0 inf 1",
      ["value":"0 0.5 1","user":"tint"],
      ["value":"0 0.5 1","user":17],
      ["value":"0 0.5 1","script":"export function update(v){return v;}"],
      ["value":"0 0.5 1","script":17],
      ["value":"0 0.5 1","animation":17],animated]
  for raw in bad {precondition(profile(raw)!.specularTint == white)}
  precondition(profile("0 0.5 1",users:["speculartint":"property"])!.specularTint == white)
  for key in ["script","animation"] {
   let value=parsed(["value":"0 0.5 1",key:17])
   precondition(value.bindingKeys.contains(key) && value.scriptSource == nil && value.timeline == nil)
  }
  let shaders:[String?] = [nil,"custom/chroma4","chroma4.frag","genericimage","generic40"]
  for shader in shaders {precondition(profile(shader:shader) == nil)}
  for shader in ["chroma4","generic4"] {
   for suffix in [".vert",".frag"] {
    let path="shaders/"+shader+suffix
    precondition(profile(shader:shader,sources:[path:.stock]) != nil)
    for source in [SceneResourceView.Source.loose,.package] {
     precondition(profile(shader:shader,sources:[path:source]) == nil)
    }
   }
   for key in ["metallic","roughness"] {
    precondition(profile(shader:shader,users:[key:"property"]) == nil)
    precondition(profile(shader:shader,replacing:[key:["value":0.25,"script":17]]) == nil)
   }
  }
  precondition(profile(sources:["shaders/generic4.frag":.loose])!.kind == .chroma4)
  precondition(profile(shader:"generic4",sources:["shaders/chroma4.vert":.loose])!.kind == .generic4)
  print("chroma-surface-admission: OK")
 }
}
'''
        self.run_surface_profile_probe(main, "chroma-surface-admission", "MWX_MODEL_CHROMA_EVIDENCE")

    def test_real_numeric_arrays_reach_surface_and_complete_scalar_consumers(self):
        main = r'''
@main enum NumericArraySurfaceProbe {
 static func main() {
  func parsed(_ raw:Any)->SceneDocument.ShaderValue {SceneDocumentLoader.shaderValue(from:raw)}
  let white=SIMD3<Float>(repeating:1), tint=SIMD3<Float>(0,0.5,1)
  func makeProfile(_ constants:[String:SceneDocument.ShaderValue])->SceneStaticModelSurfaceProfile? {
   let pass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"renamed-surface",passIndex:0,
       shaderPath:"chroma4",combos:["LIGHTING":1,"REFLECTION":1],constantShaderValues:constants)
   return ScenePreparedStaticModelResources.surfaceProfile(pass,resourceView:.init())
  }
  for wrapped in [false,true] {
   func input(_ value:Any)->Any {wrapped ? ["value":value,"user":NSNull()] : value}
   let constants=["metallic":parsed(input([0.25])),"roughness":parsed(input([0.75])),
                  "reflectivity":parsed(input([0.5])),"speculartint":parsed(input([0,0.5,1])),
                  "color":parsed(input([0.25,0.5,1]))]
   let pass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"renamed-surface",passIndex:0,
       shaderPath:"chroma4",combos:["LIGHTING":1,"REFLECTION":1],constantShaderValues:constants)
   let profile=makeProfile(constants)!
   precondition(profile.metallic == 0.25 && profile.roughness == 0.75 && profile.reflectivity == 0.5)
   precondition(profile.specularTint == tint)
   precondition(SceneMaterialPropertyBindingCompiler.staticComponents("metallic",instance:nil,
       pass:pass,count:1,fallback:[0],requiresCompleteScalar:true) == [0.25])
   precondition(SceneMaterialPropertyBindingCompiler.staticComponents("color",instance:nil,
       pass:pass,count:3,fallback:[1,1,1]) == [0.25,0.5,1])
   let bad:[Any] = [[0,0.5], [0,0.5,1,2], [0,true,1], [0,"0.5",1], [0,NSNull(),1],
                   [0,Double.infinity,1], [0,Double.nan,1], ["coordinates":"0 0.5 1 2 3"]]
   for raw in bad {
    let fallback=makeProfile(constants.merging(["speculartint":parsed(input(raw))]) {_,new in new})!
    precondition(fallback.metallic == 0.25 && fallback.specularTint == white)
   }
   precondition(makeProfile(constants.merging(["metallic":parsed(input([0.25,0.5]))]) {_,new in new}) == nil)
   precondition(makeProfile(constants.merging(["metallic":parsed(input([true]))]) {_,new in new}) == nil)
  }
  let long=parsed([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15])
  precondition(long.components == (0..<16).map(Double.init))
  precondition(long.rawValue.split(separator:" ").count == 16)
  print("numeric-array-surface: OK")
 }
}
'''
        self.run_surface_profile_probe(main, "numeric-array-surface", "MWX_MODEL_ARRAY_EVIDENCE")

    def test_opt_in_complete_scalar_rejects_filtered_plain_and_wrapper_values(self):
        main=r'''
@main enum CompleteScalarProbe {
 static func main() {
  func projected(_ raw:String,_ values:[Double],_ keys:[String],_ count:Int=1,
                 strict:Bool=true)->[Double]? {
   let value=SceneDocument.ShaderValue(userBinding:nil,userValueKind:nil,components:values,
       bindingKeys:keys,rawValue:raw,valueKind:keys.isEmpty ? "string":"binding")
   let pass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"material",passIndex:0,
       constantShaderValues:["roughness":value])
   return SceneMaterialPropertyBindingCompiler.staticComponents("roughness",instance:nil,pass:pass,
       count:count,fallback:[0.7],requiresCompleteScalar:strict)
  }
  for keys in [[],["value"],["user","value"]] {
   precondition(projected("0.5 garbage",[0.5],keys) == nil)
   precondition(projected("  5e-1  ",[0.5],keys) == [0.5])
   precondition(projected("0.5 garbage",[0.5],keys,strict:false) == [0.5])
  }
  precondition(projected("0.5 0.25",[0.5,0.25],[],2) == nil)
  for value in [0.0,1.0,-2.0,2.0] {
   precondition(projected(String(value),[value],[]) == [value])
  }
  let pass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"material",passIndex:0,
      constantShaderValues:[:])
  precondition(SceneMaterialPropertyBindingCompiler.staticComponents("roughness",instance:nil,pass:pass,
      count:1,fallback:[0.7],requiresCompleteScalar:true) == [0.7])
  print("complete-scalar: OK")
 }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-complete-scalar-') as tmp:
            work=Path(tmp);source=work/'Harness.swift';binary=work/'probe'
            source.write_text(STUBS+main)
            compiled=subprocess.run(['xcrun','swiftc',*map(str,SOURCES),str(source),
                '-module-cache-path',str(work/'cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=subprocess.run([str(binary)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('complete-scalar: OK',result.stdout)

    def test_material_wrappers_reach_shared_typed_snapshot(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-model-material-property-") as tmp:
            root = Path(tmp)
            stubs = root / "Stubs.swift"
            harness = root / "Harness.swift"
            executable = root / "Harness"
            stubs.write_text(STUBS, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-modules")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-modules")
            compiled = subprocess.run(
                [
                    swiftc,
                    *map(str, SOURCES),
                    str(stubs),
                    str(harness),
                    "-o", str(executable),
                ],
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(executable)], capture_output=True, text=True, env=environment
            ) if compiled.returncode == 0 else compiled
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("nested-material-live-transaction: OK", completed.stdout)


if __name__ == "__main__":
    unittest.main()
