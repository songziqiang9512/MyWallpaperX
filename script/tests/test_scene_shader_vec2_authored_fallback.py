"""Missing shader-property inputs retain a typed authored fallback, not a VM."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_property_binding_program as property_fixture
from script.tests import test_scene_resolved_material_program_finalizer as material_fixture

ROOT = Path(__file__).resolve().parents[2]
SOURCES = list(dict.fromkeys([
    *property_fixture.SWIFT_SOURCES,
    *material_fixture.SWIFT_SOURCES,
    *material_fixture.SHARED_FIXTURE_SOURCES,
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectStageAuthoredFallbackOwnerPartition.swift",
]))

HARNESS = r'''
import Foundation

@main
enum Vec2FallbackHarness {
    static func property(_ key: String, _ kind: SceneUserPropertyKind,
                         _ value: SceneUserPropertyValue?) -> SceneUserPropertyDefinition {
        .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue,
              order: 0, index: nil, minimumValue: nil, maximumValue: nil,
              stepValue: nil, allowsFractionalValues: true, fractionalPrecision: nil,
              displayCondition: nil, defaultValue: value, options: [])
    }

    static func root(_ key: String, _ value: Any, layer: Int = 41,
                     name: String = "Coverage", resource: String = "effects/own/frame.json",
                     rawUser: Any? = nil) -> [String: Any] {
        let pass: [String: Any] = ["id": 9,
            "constantshadervalues": [name: ["user": rawUser ?? key, "value": value]]]
        let effect: [String: Any] = ["id": 5, "file": resource, "passes": [pass]]
        return ["objects": [["id": layer, "effects": [effect]]]]
    }

    static func compile(_ root: [String: Any], properties: [SceneUserPropertyDefinition] = [])
        -> ScenePropertyBindingCompilation {
        ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(root: root),
            catalog: .init(definitions: properties))
    }

    static func components(_ value: SceneDynamicValue) -> [Double] {
        switch value {
        case let .scalar(x): [x]
        case let .vector2(x, y): [x, y]
        case let .vector3(x, y, z): [x, y, z]
        default: []
        }
    }

    static func summary(_ compilation: ScenePropertyBindingCompilation) -> [String: Any] {
        let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: compilation.program.definitions).snapshot
        return ["definitions": compilation.program.definitions.count,
            "instructions": compilation.program.instructions.count,
            "values": compilation.program.definitions.map { components($0.authoredValue) },
            "types": compilation.program.definitions.map { $0.valueType.rawValue },
            "snapshotCount": snapshot.count,
            "diagnostics": compilation.diagnostics.map { $0.code.rawValue }.sorted()]
    }

    static func admission(_ definition: SceneDynamicTargetDefinition, key: String,
                          contributors: [Template.DynamicUniformSource]? = nil,
                          attachments: [Template.DynamicUniformScriptAttachment] = [],
                          wrongFallbackTarget: Bool = false,
                          bindingKeys: [String] = ["user", "value"]) -> String {
        guard case let .effectConstant(layer, effect, pass, name) = definition.target else { return "wrongTarget" }
        let values = components(definition.authoredValue)
        let declaration = Template.UniformDeclaration(name: name, value: .dynamic(.init(
            target: definition.target, valueContributors: contributors ?? [.userProperty(key)],
            scriptAttachments: attachments,
            authoredFallback: .init(valueKind: "binding", componentBitPatterns: values.map(\.bitPattern),
                authoredBindingKeys: bindingKeys), authoredBindingKeys: bindingKeys)))
        let shader = contract(revision: "own-vec2-" + name,
            fragmentSourceOverride: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            uniform vec2 u_Value; // {"material":"\(name)","default":"0 0.55"}
            void main() { gl_FragColor = texture2D(g_Texture0, v_TexCoord) * vec4(u_Value, 0.0, 1.0); }
            """)
        let material = template(shader, uniformDeclarations: [declaration])
        if wrongFallbackTarget {
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                definitions: [definition]).snapshot
            let other = SceneDynamicTarget.effectConstant(layerID: layer + 1,
                effectIndex: effect, passIndex: pass, name: name)
            return snapshot[other] == nil ? "targetAbsent" : "accepted"
        }
        if bindingKeys != ["user", "value"] {
            return SceneResolvedMaterialDirectUserBindingContract.matches(bindingKeys)
                ? "accepted" : "invalidProducerWrapper"
        }
        let field = SceneAuthoredShaderUniformLayout.Field(name: "u_Value", type: .float2, offset: 0)
        let schema = SceneResolvedMaterialShaderSchema.Uniform(name: "u_Value", materialKeys: [name],
            defaultValue: staticValue([0, 0.55]), authoredRange: nil)
        do {
            let prepared = try SceneResolvedMaterialProgramFinalizer.prepareUniformBindings(
                template: material, fields: [field], activeUniforms: ["u_Value": schema],
                activeTextureSlots: [0], neutralTextureResolution: nil)
            guard prepared.count == 1,
                  case let .dynamic(binding) = prepared[0].source,
                  binding.declaration.target == definition.target,
                  binding.fallback?.componentBitPatterns == values.map(\.bitPattern),
                  prepared[0].field.type == .float2,
                  prepared[0].field.storageByteSize == 8 else { return "typedBindingMismatch" }
            return "accepted"
        } catch let failure as SceneResolvedMaterialFailure {
            return failure.code.rawValue
        } catch { return "unexpectedFailure" }
    }

    static func main() throws {
        var output: [String: Any] = [:]
        var positives: [[String: Any]] = []
        for (key, name, resource, layer, raw) in [
            ("unregisteredOpacity", "Coverage", "effects/own/frame.json", 41, "0 0.55"),
            ("renamedPair", "InteriorPair", "effects/another/shape.json", 73, " 0\t0.55000\n")
        ] {
            let compilation = compile(root(key, raw, layer: layer, name: name, resource: resource))
            var row = summary(compilation)
            if let definition = compilation.program.definitions.first {
                let expected: [Double] = [0, 0.55]
                let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 3, generation: 2,
                    definitions: compilation.program.definitions).snapshot
                let value = snapshot[definition.target]?.value
                let bytes = value.flatMap { SceneResolvedMaterialUniformEncoder.encode($0, as: .float2) }
                let independentBytes = expected.map(Float.init).withUnsafeBytes { Data($0) }
                row["float2BytesExact"] = bytes == independentBytes
                row["fullTarget"] = definition.target == .effectConstant(
                    layerID: layer, effectIndex: 0, passIndex: 0, name: name)
                row["noFakeLiveValue"] = compilation.program.evaluate(
                    effectiveValues: [key: .string("0.8 0.9")]).userValues.isEmpty
                row["admission"] = admission(definition, key: key)
                row["wrongLayer"] = admission(definition, key: key, wrongFallbackTarget: true)
                row["timelineConflict"] = admission(definition, key: key,
                    contributors: [.userProperty(key), .timeline])
                row["scriptConflict"] = admission(definition, key: key,
                    contributors: [.userProperty(key), .sceneScript])
                row["unprovedScriptAttachment"] = admission(definition, key: key, attachments: [.unproven])
                row["producerWrapperKey"] = admission(definition, key: key,
                    bindingKeys: ["script", "user", "value"])
            }
            positives.append(row)
        }
        output["positives"] = positives

        let key = "invalidDefinition"
        let invalidCatalogs: [[SceneUserPropertyDefinition]] = [
            [property(key, .bool, .bool(true))],
            [property(key, .color, .string("1 1 1")), property(key, .color, .string("0 0 0"))],
            [property(key, .textInput, nil)]
        ]
        output["invalidDefinitions"] = invalidCatalogs.map {
            summary(compile(root(key, "0 0.55"), properties: $0))
        }
        output["invalidFallbacks"] = ["", "0", "0 bad", "0 nan", "0 inf", "0 1e300",
            "0 1 2 3", "0,0.55"].map { raw in summary(compile(root("absent", raw))) }
        output["malformedUser"] = summary(compile(root("absent", "0 0.55", rawUser: false)))
        let color = compile(root("tint", "0 0.55"), properties: [property("tint", .color, .string("1 1 1"))])
        let slider = compile(root("amount", "0 0.55"), properties: [property("amount", .slider, .number(0.5))])
        output["realColorTwoRejected"] = summary(color)
        output["realSliderTwoRejected"] = summary(slider)
        let liveColor = compile(root("tint", "0.1 0.2 0.3"), properties: [property("tint", .color, .string("1 1 1"))])
        output["realColorThree"] = summary(liveColor)
        output["realColorLive"] = liveColor.program.evaluate(
            effectiveValues: ["tint": .string("0.7 0.8 0.9")]).userValues.values.map { components($0) }
        output["realSliderEqual"] = summary(compile(root("amount", "0.5 0.5"),
            properties: [property("amount", .slider, .number(0.5))]))
        output["legacyMissingEqual"] = summary(compile(root("absent", "0.5 0.5")))
        var duplicate = root("first", "0 0.55")
        duplicate["objects"] = (duplicate["objects"] as! [[String: Any]])
            + (root("second", "0.2 0.8")["objects"] as! [[String: Any]])
        output["duplicateTarget"] = summary(compile(duplicate))
        output["floatOverflowConsumerRejected"] = SceneResolvedMaterialUniformEncoder.encode(
            SceneDynamicValue.vector2(0, 1e300), as: .float2) == nil
        output["CPUOnly"] = true // no Metal device/command queue is created
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneShaderVec2AuthoredFallbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-shader-vec2-fallback-")
        cls.addClassCleanup(cls.temp.cleanup)
        work = Path(cls.temp.name)
        proof = os.environ.get("MWX_SHADER_VEC2_FALLBACK_PROOF_DIR")
        cls.proof = Path(proof) if proof else None
        if cls.proof:
            cls.proof.mkdir(parents=True, exist_ok=True)
        harness = work / "Harness.swift"
        harness.write_text(HARNESS)
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
        if cls.proof:
            (cls.proof / "source-before.json").write_text(json.dumps(before, indent=2) + "\n")
            (cls.proof / "Harness.swift").write_text(HARNESS)
        environment = os.environ.copy()
        environment.update(CLANG_MODULE_CACHE_PATH=str(work / "clang-cache"),
                           SWIFT_MODULECACHE_PATH=str(work / "swift-cache"),
                           MWX_SCENE_GENERIC_SHADER_CACHE=str(work / "shader-cache"))
        binary = work / "vec2-fallback"
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                   *(str(p) for p in SOURCES), str(harness), "-framework", "Metal",
                   "-framework", "CoreGraphics", "-framework", "ImageIO",
                   "-module-cache-path", str(work / "module-cache"), "-o", str(binary)]
        compiled = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=300)
        if cls.proof:
            (cls.proof / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
            (cls.proof / "compile.stdout").write_text(compiled.stdout)
            (cls.proof / "compile.stderr").write_text(compiled.stderr)
        if compiled.returncode:
            after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
            if cls.proof:
                (cls.proof / "source-after.json").write_text(json.dumps(after, indent=2) + "\n")
            raise AssertionError(compiled.stderr)
        ran = subprocess.run([str(binary)], capture_output=True, text=True, env=environment, timeout=30)
        after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
        if cls.proof:
            (cls.proof / "source-before.json").write_text(json.dumps(before, indent=2) + "\n")
            (cls.proof / "source-after.json").write_text(json.dumps(after, indent=2) + "\n")
            (cls.proof / "Harness.swift").write_text(HARNESS)
            (cls.proof / "run.stdout").write_text(ran.stdout)
            (cls.proof / "run.stderr").write_text(ran.stderr)
        if before != after or ran.returncode:
            raise AssertionError(f"source drift={before != after}; runtime={ran.stderr}")
        cls.result = json.loads(ran.stdout)
        if cls.proof:
            (cls.proof / "observations.json").write_text(json.dumps(cls.result, indent=2) + "\n")

    def test_missing_or_invalid_definition_keeps_vec2_without_live_producer(self) -> None:
        for row in [*self.result["positives"], *self.result["invalidDefinitions"]]:
            with self.subTest(row=row):
                self.assertEqual(row["definitions"], 1)
                self.assertEqual(row["types"], ["vector2"])
                self.assertEqual(row["values"], [[0, 0.55]])
                self.assertEqual(row["instructions"], 0)
                self.assertEqual(row["snapshotCount"], 1)
        for row in self.result["positives"]:
            self.assertTrue(row["float2BytesExact"])
            self.assertTrue(row["fullTarget"])
            self.assertTrue(row["noFakeLiveValue"])
            self.assertEqual(row["admission"], "accepted")

    def test_invalid_values_existing_kinds_and_duplicate_target_stay_bounded(self) -> None:
        # A single numeric string is an existing scalar fallback, not Vec2.
        for index, row in enumerate(self.result["invalidFallbacks"]):
            with self.subTest(index=index):
                self.assertEqual(row["definitions"], int(index == 1))
                self.assertEqual(row["instructions"], 0)
        for key in ["malformedUser", "realColorTwoRejected", "realSliderTwoRejected", "duplicateTarget"]:
            self.assertEqual(self.result[key]["definitions"], 0, key)
            self.assertEqual(self.result[key]["instructions"], 0, key)
        self.assertEqual(self.result["realColorThree"]["types"], ["vector3"])
        self.assertEqual(self.result["realColorThree"]["instructions"], 1)
        self.assertEqual(self.result["realColorLive"], [[0.7, 0.8, 0.9]])
        self.assertEqual(self.result["realSliderEqual"]["types"], ["scalar"])
        self.assertEqual(self.result["realSliderEqual"]["instructions"], 1)
        self.assertEqual(self.result["legacyMissingEqual"]["types"], ["scalar"])
        self.assertTrue(self.result["floatOverflowConsumerRejected"])

    def test_exact_material_fallback_does_not_mask_other_writers(self) -> None:
        for row in self.result["positives"]:
            for key in ["wrongLayer", "timelineConflict", "scriptConflict", "unprovedScriptAttachment", "producerWrapperKey"]:
                self.assertNotEqual(row[key], "accepted", key)
        self.assertTrue(self.result["CPUOnly"])


if __name__ == "__main__":
    unittest.main()
