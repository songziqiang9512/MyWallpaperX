"""Real loader-to-descriptor terminal policy and dynamic schema qualification.

No App, Metal device, upload or visible-behavior claim. Reuse the existing
builder fixture's external leaves; the asserted model/material/state owners
and the prepared-resource layer projection are production code.
Additive templates are supplied manually; actual dynamic-resource creation
through ScenePreparedImageMaterialCatalog remains outside this gate.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_alpha_display_builder_fixture as shared


ROOT = shared.REPOSITORY_ROOT
HARNESS = r'''
@main enum TerminalPolicyHarness {
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        var result: [String: Any] = [:]
        for mode in ["native", "ortho", "override"] {
            let root = base.appendingPathComponent(mode)
            let project = try SceneProjectLoader().load(from: root)
            let document = try SceneDocumentLoader().load(from: project.entryURL, propertyCatalog: project.userProperties)
            let view = SceneResourceView(projectRootURL: root, packageRootURL: nil,
                stockAssetsRootURL: base.appendingPathComponent("stock"))
            let catalog = try SceneAssetCatalogLoader().load(resourceView: view,
                referencedResourcePaths: document.referencedResourcePaths)
            let descriptor = SceneRenderDescriptorBuilder().build(project: project,
                sceneDocument: document, assetCatalog: catalog)!
            let encoded = try JSONEncoder().encode(descriptor)
            let decoded = try JSONDecoder().decode(SceneRenderDescriptor.self, from: encoded)
            var checks: [String: Any] = [:]
            checks["states"] = Dictionary(uniqueKeysWithValues: descriptor.layers.map {
                (String($0.id), $0.imageMaterialRenderState.map {
                    ["test": $0.depthTest.rawValue, "write": $0.depthWrite.rawValue,
                     "cull": $0.cullMode.rawValue, "blend": $0.blending.rawValue,
                     "alpha": $0.alphaWriting.rawValue,
                     "depth": String($0.requiresDepthAttachment)]
                } ?? [:])
            })
            checks["neutral"] = descriptor.layers.filter {
                $0.proceduralSolidSource == .neutral
            }.map(\.id)
            checks["materialCatalogPreservedSolid"] = catalog.materials.contains {
                $0.relativePath == "materials/solid-state.json"
            }
            checks["shaderSourceKinds"] = Dictionary(uniqueKeysWithValues: catalog.shaderContracts.map {
                ($0.identity, $0.sourceKind.rawValue)
            })
            checks["roundTrip"] = decoded.layers.map(\.imageMaterialRenderState)
                == descriptor.layers.map(\.imageMaterialRenderState)
                && decoded.preparedImageMaterialStatesByModelPath
                    == descriptor.preparedImageMaterialStatesByModelPath
            checks["modelDefaults"] = descriptor.preparedImageMaterialStatesByModelPath?.keys.sorted() ?? []
            var dormantOnly = descriptor
            dormantOnly.layers = []
            checks["dormantModelRequiresDepth"] = dormantOnly.requiresImageDepthAttachment
            checks["dormantModelRequiresAdditive"] = dormantOnly.requiresImageAdditiveRGB
            var hiddenOnly = descriptor
            hiddenOnly.layers = descriptor.layers.filter { $0.id == 135 }
            checks["hiddenAdditiveRequiresPipeline"] = hiddenOnly.requiresImageAdditiveRGB
            if let state = descriptor.preparedImageMaterialStatesByModelPath?["models/additive.json"] {
                let template = SceneScriptPreparedResourceLayerTemplate(
                    modelPath: "models/additive.json", renderSizeWH: [4, 3],
                    imageMaterialRenderState: state)
                let mutation = SceneScriptLayerMutation(kind: .upsert, isDynamic: true,
                    fields: [], layerID: -97, orderIndex: 0, visible: true, solid: false,
                    alpha: 0.5, origin: .zero, scale: .init(repeating: 1), angles: .zero,
                    color: .init(repeating: 1), pointSize: 20, text: "", font: "",
                    assetPath: "models/additive.json", perspective: mode == "native")
                checks["additiveManualTemplateInherited"] = SceneRenderDescriptor.Layer.preparedResourceLayer(
                    mutation, template: template)?.imageMaterialRenderState == state
            }
            if mode == "native" {
                let state = descriptor.preparedImageMaterialStatesByModelPath!["models/enabled.json"]!
                let template = SceneScriptPreparedResourceLayerTemplate(
                    modelPath: "models/enabled.json", renderSizeWH: [4, 3],
                    imageMaterialRenderState: state)
                let mutation = SceneScriptLayerMutation(kind: .upsert, isDynamic: true,
                    fields: [], layerID: -1, orderIndex: 0, visible: true, solid: true,
                    alpha: 1, origin: .zero, scale: .init(repeating: 1), angles: .zero,
                    color: .init(repeating: 1), pointSize: 20, text: "", font: "",
                    assetPath: "models/enabled.json", perspective: true)
                let layer = SceneRenderDescriptor.Layer.preparedResourceLayer(mutation, template: template)
                var puppet = template
                puppet.puppetMeshPath = "models/mesh.mdl"
                var composition = template
                composition.kind = .composition
                checks["dynamicInherited"] = layer?.imageMaterialRenderState == state
                checks["puppetExcluded"] = SceneRenderDescriptor.Layer.preparedResourceLayer(
                    mutation, template: puppet)?.imageMaterialRenderState == nil
                checks["compositionExcluded"] = SceneRenderDescriptor.Layer.preparedResourceLayer(
                    mutation, template: composition)?.imageMaterialRenderState == nil
                var unknown = template
                unknown.imageMaterialRenderState = nil
                checks["unqualifiedDynamicRemainsNil"] = SceneRenderDescriptor.Layer.preparedResourceLayer(
                    mutation, template: unknown)?.imageMaterialRenderState == nil
            }
            result[mode] = checks
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
'''


def write_json(root: Path, relative: str, value: object) -> None:
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(value))


def fixture(base: Path) -> None:
    state = {"shader": "genericimage2", "textures": ["textures/albedo"],
             "blending": "translucent", "depthtest": "enabled",
             "depthwrite": "disabled", "cullmode": "nocull"}
    for name in ("flat", "other-stock"):
        for suffix in ("vert", "frag"):
            target = base / "stock/shaders" / f"{name}.{suffix}"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("void main() {}\n")
    write_json(base / "stock", "materials/solid-state.json", {"passes": [
        {key: value for key, value in {**state, "shader": "flat"}.items() if key != "textures"}]})
    variants = {
        "enabled": state, "disabled": {**state, "depthtest": "disabled"},
        "write": {**state, "depthtest": "disabled", "depthwrite": "enabled"},
        "omitted": {"shader": "genericimage2", "textures": ["textures/albedo"]},
        "normal": {**state, "blending": "normal"},
        "additive-depth": {**state, "blending": "additive"},
        "default-alpha": {**state, "alphawriting": "default"},
        "enabled-alpha": {**state, "alphawriting": "enabled"},
        "missing-cull": {key: value for key, value in state.items() if key != "cullmode"},
        "unknown-cull": {**state, "cullmode": "front"},
        "renamed": {**state, "shader": "GeNeRiCiMaGe4", "textures": ["textures/renamed"],
                    "blending": " TRANSLUCENT ", "depthtest": " ENABLED ", "cullmode": "NoCull"},
        "author": {**state, "shader": "shaders/my-source"},
    }
    additive = {**state, "blending": "additive", "depthtest": "disabled",
                "combos": {"VERSION": 2}}
    additive_variants = {
        "additive": additive,
        "additive-default": {**additive, "alphawriting": "default"},
        "additive-renamed": {**additive, "shader": "GeNeRiCiMaGe2",
            "textures": ["textures/renamed-source"], "blending": " ADDITIVE ",
            "depthtest": " Disabled ", "depthwrite": " DISABLED ", "cullmode": "NoCull",
            "alphawriting": " DEFAULT "},
        "additive-read": {**additive, "depthtest": "enabled"},
        "additive-write": {**additive, "depthwrite": "enabled"},
        "additive-cull": {**additive, "cullmode": "normal"},
        "additive-alpha-enabled": {**additive, "alphawriting": "enabled"},
        "additive-alpha-unknown": {**additive, "alphawriting": "unsupported"},
        "additive-version-missing": {k: v for k, v in additive.items() if k != "combos"},
        "additive-version-other": {**additive, "combos": {"VERSION": 3}},
        "additive-lighting": {**additive, "combos": {"VERSION": 2, "LIGHTING": 1}},
        "additive-unknown-combo": {**additive, "combos": {"VERSION": 2, "UNKNOWN": 1}},
        "additive-other-builtin": {**additive, "shader": "genericimage4"},
        "additive-author": {**additive, "shader": "shaders/renamed-source"},
        "additive-slot1": {**additive, "textures": [None, "textures/albedo"]},
        "additive-two-slots": {**additive, "textures": ["textures/albedo", "textures/mask"]},
        "additive-missing-depth": {k: v for k, v in additive.items() if k != "depthtest"},
        "additive-missing-cull": {k: v for k, v in additive.items() if k != "cullmode"},
        "additive-unlit": {**additive, "combos": {"LIGHTING": 0, "VERSION": 2}},
        "additive-constants": {**additive, "constantshadervalues": {"alpha": 0.5}},
        "additive-user-values": {**additive, "usershadervalues": {"alpha": "opacity"}},
        "additive-user-texture": {**additive, "usertextures": ["textures/override"]},
        "additive-source-backed-image-name": {**additive, "shader": "custom/genericimage2"},
    }
    for mode in ("native", "ortho", "override"):
        root = base / mode
        objects = []
        for index, (name, material) in enumerate(variants.items(), 1):
            write_json(root, f"models/{name}.json", {"material": f"materials/{name}.json"})
            write_json(root, f"materials/{name}.json", {"passes": [material]})
            objects.append({"id": index, "image": f"models/{name}.json", "size": "4 3"})
        for index, (name, material) in enumerate(additive_variants.items(), 100):
            write_json(root, f"models/{name}.json", {"material": f"materials/{name}.json"})
            write_json(root, f"materials/{name}.json", {"passes": [material]})
            objects.append({"id": index, "image": f"models/{name}.json", "size": "4 3"})
        write_json(root, "models/additive-multi.json", {"material": "materials/additive-multi.json"})
        write_json(root, "materials/additive-multi.json", {"passes": [additive, additive]})
        write_json(root, "models/additive-solid.json", {"solidlayer": True, "material": "materials/additive.json"})
        objects += [{"id": 130, "image": "models/additive-multi.json", "size": "4 3"},
                    {"id": 131, "image": "models/additive.json", "shape": "arbitrary"},
                    {"id": 132, "image": "models/additive.json", "colorBlendMode": 31},
                    {"id": 133, "image": "models/additive.json", "instance": {"combos": {"LIGHTING": 0}}},
                    {"id": 134, "image": "models/additive-solid.json", "size": "4 3"},
                    {"id": 135, "image": "models/additive.json", "size": "4 3", "visible": False}]
        for layer_id, name, model in [
            (20, "stock-solid", {"solidlayer": True, "material": "materials/solid-state.json"}),
            (21, "plain-solid", {"solidlayer": True}),
            (22, "other-stock", {"solidlayer": True, "material": "materials/other-stock.json"}),
            (23, "authored-solid", {"solidlayer": True, "material": "materials/author.json"}),
        ]:
            write_json(root, f"models/{name}.json", model)
            objects.append({"id": layer_id, "image": f"models/{name}.json", "size": "4 3"})
        write_json(root, "materials/other-stock.json", {"passes": [
            {key: value for key, value in {**state, "shader": "other-stock"}.items() if key != "textures"}]})
        objects += [{"id": 30, "text": "TEXT", "size": "4 3"},
                    {"id": 31, "image": "models/enabled.json", "colorBlendMode": 1},
                    {"id": 32, "image": "models/enabled.json", "shape": "arbitrary"}]
        general = {"fov": 60, "nearz": .01, "farz": 100}
        if mode == "ortho":
            general["orthogonalprojection"] = {"width": 1920, "height": 1080}
        write_json(root, "scene.json", {"general": general, "objects": objects})
        write_json(root, "project.json", {"type": "scene", "file": "scene.json"})
        for suffix in ("vert", "frag"):
            path = root / f"shaders/custom/genericimage2.{suffix}"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("void main() {}\n")
        if mode == "override":
            path = root / "shaders/flat.frag"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("void main() {}\n")


class ScenePreparedImageTerminalPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        output = os.environ.get("MWX_IMAGE_POLICY_EVIDENCE")
        with tempfile.TemporaryDirectory(prefix="mwx-image-policy-") as directory:
            base = Path(directory)
            fixture(base)
            harness = base / "Harness.swift"
            harness.write_text(shared.HARNESS_SOURCE.split("@main", 1)[0] + HARNESS)
            paths = [Path(__file__), Path(shared.__file__), *shared.SWIFT_SOURCES]
            hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
            binary = base / "probe"
            run = subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", *map(str, shared.SWIFT_SOURCES),
                str(harness), "-module-cache-path", str(base / "cache"), "-framework", "Metal", "-o", str(binary)],
                capture_output=True, text=True, timeout=180)
            if run.returncode:
                raise AssertionError(run.stdout + run.stderr)
            completed = subprocess.run([str(binary), str(base)], check=True, capture_output=True,
                text=True, timeout=30)
            cls.result = json.loads(completed.stdout)
            assert hashes == {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, "source identity drift"
            if output:
                evidence = Path(output)
                evidence.mkdir(parents=True, exist_ok=True)
                (evidence / "source-identity.json").write_text(json.dumps(hashes, indent=2))
                (evidence / "report.json").write_text(json.dumps(cls.result, indent=2))

    def test_explicit_states_and_renames_reach_real_builder(self) -> None:
        states = self.result["native"]["states"]
        self.assertEqual(states["1"]["test"], "enabled")
        self.assertEqual(states["1"]["depth"], "true")
        self.assertEqual(states["2"]["test"], "disabled")
        self.assertEqual(states["2"]["depth"], "false")
        self.assertEqual(states["3"]["write"], "enabled")
        self.assertEqual(states["11"], states["1"])
        for layer_id in (4, 5, 6, 7, 8, 9, 10, 12, 22, 23, 30, 31, 32):
            self.assertEqual(states[str(layer_id)], {}, layer_id)

    def test_stock_neutral_role_and_authored_override(self) -> None:
        native = self.result["native"]
        self.assertTrue(native["materialCatalogPreservedSolid"])
        self.assertEqual(native["neutral"], [20, 21])
        self.assertEqual(native["states"]["20"]["test"], "enabled")
        self.assertEqual(self.result["override"]["neutral"], [21])
        self.assertEqual(self.result["override"]["states"]["20"], {})

    def test_additive_profile_reaches_real_builder_and_manual_template_projection(self) -> None:
        for mode in ("native", "ortho", "override"):
            result = self.result[mode]
            states = result["states"]
            for layer_id in (100, 101, 102, 118, 135):
                with self.subTest(mode=mode, layer=layer_id):
                    state = states[str(layer_id)]
                    self.assertEqual(state["blend"], "additive")
                    self.assertEqual(state["test"], "disabled")
                    self.assertEqual(state["write"], "disabled")
                    self.assertEqual(state["cull"], "nocull")
                    self.assertEqual(state["depth"], "false")
                    self.assertEqual(state["alpha"], "default" if layer_id in (101, 102) else "unspecified")
            self.assertEqual(states["101"], states["102"])
            self.assertEqual(states["100"], states["118"])
            self.assertTrue(result["additiveManualTemplateInherited"])
            self.assertTrue(result["hiddenAdditiveRequiresPipeline"])
            self.assertEqual(result["shaderSourceKinds"]["genericimage2"], "hostBuiltin")
            self.assertEqual(result["shaderSourceKinds"]["custom/genericimage2"], "authoredSource")
            for layer_id in (*range(103, 118), *range(119, 123), 130, 131, 132, 133, 134):
                self.assertEqual(states[str(layer_id)], {}, (mode, layer_id))

    def test_native_depth_schema_and_prepared_dynamic_inheritance(self) -> None:
        for result in self.result.values():
            self.assertTrue(result["roundTrip"])
            self.assertFalse(result["dormantModelRequiresAdditive"])
        for layer_id, value in self.result["ortho"]["states"].items():
            if int(layer_id) not in (100, 101, 102, 118, 135):
                self.assertEqual(value, {}, layer_id)
        self.assertEqual(self.result["ortho"]["modelDefaults"], [
            "models/additive-default.json", "models/additive-renamed.json",
            "models/additive-unlit.json", "models/additive.json"])
        self.assertFalse(self.result["ortho"]["dormantModelRequiresDepth"])
        for key in ("dynamicInherited", "puppetExcluded", "compositionExcluded", "unqualifiedDynamicRemainsNil", "dormantModelRequiresDepth"):
            self.assertIs(self.result["native"][key], True, key)


if __name__ == "__main__":
    unittest.main()
