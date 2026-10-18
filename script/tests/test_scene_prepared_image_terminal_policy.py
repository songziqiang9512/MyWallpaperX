"""Real loader-to-descriptor terminal policy and dynamic schema qualification.

No App, Metal device, upload or visible-behavior claim. Reuse the existing
builder fixture's external leaves; the asserted model/material/state owners
and the prepared-resource layer projection are production code.
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
            let document = try SceneDocumentLoader().load(project: project, packageReport: nil)
            let catalog = try SceneAssetCatalogLoader().load(project: project,
                packageReport: nil, stockAssetsRootURL: base.appendingPathComponent("stock"))
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
            checks["roundTrip"] = decoded.layers.map(\.imageMaterialRenderState)
                == descriptor.layers.map(\.imageMaterialRenderState)
                && decoded.preparedImageMaterialStatesByModelPath
                    == descriptor.preparedImageMaterialStatesByModelPath
            checks["modelDefaults"] = descriptor.preparedImageMaterialStatesByModelPath?.keys.sorted() ?? []
            var dormantOnly = descriptor
            dormantOnly.layers = []
            checks["dormantModelRequiresDepth"] = dormantOnly.requiresImageDepthAttachment
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
        "additive": {**state, "blending": "additive"},
        "default-alpha": {**state, "alphawriting": "default"},
        "enabled-alpha": {**state, "alphawriting": "enabled"},
        "missing-cull": {key: value for key, value in state.items() if key != "cullmode"},
        "unknown-cull": {**state, "cullmode": "front"},
        "renamed": {**state, "shader": "GeNeRiCiMaGe4", "textures": ["textures/renamed"],
                    "blending": " TRANSLUCENT ", "depthtest": " ENABLED ", "cullmode": "NoCull"},
        "author": {**state, "shader": "shaders/my-source"},
    }
    for mode in ("native", "ortho", "override"):
        root = base / mode
        objects = []
        for index, (name, material) in enumerate(variants.items(), 1):
            write_json(root, f"models/{name}.json", {"material": f"materials/{name}.json"})
            write_json(root, f"materials/{name}.json", {"passes": [material]})
            objects.append({"id": index, "image": f"models/{name}.json", "size": "4 3"})
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
            force = (shared.SOURCE_ROOT / "Systems/Particles/SceneParticleControlPointForce.swift").read_text()
            start = force.index("nonisolated struct SceneParticleControlPointForceEnvironment:")
            environment = force[start:force.index("\n}", start) + 2]
            harness = base / "Harness.swift"
            harness.write_text(environment + shared.HARNESS_SOURCE.split("@main", 1)[0] + HARNESS)
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

    def test_native_only_schema_and_prepared_dynamic_inheritance(self) -> None:
        for result in self.result.values():
            self.assertTrue(result["roundTrip"])
        for value in self.result["ortho"]["states"].values():
            self.assertEqual(value, {})
        self.assertEqual(self.result["ortho"]["modelDefaults"], [])
        self.assertFalse(self.result["ortho"]["dormantModelRequiresDepth"])
        for key in ("dynamicInherited", "puppetExcluded", "compositionExcluded", "unqualifiedDynamicRemainsNil", "dormantModelRequiresDepth"):
            self.assertIs(self.result["native"][key], True, key)


if __name__ == "__main__":
    unittest.main()
