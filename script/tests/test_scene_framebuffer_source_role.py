"""Loaded authored declarations nominate a Program source, without shader execution.

The project/document/catalog/descriptor owners are real. The reused builder
support stubs unrelated runtime leaves; this gate does not qualify Program/GPU
output, source ordering, depth or App behavior.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_alpha_display_builder_fixture as builder


SCENE = builder.SOURCE_ROOT
HARNESS = r'''
@main
enum FramebufferRoleProbe {
    static func main() throws {
        var rows: [String: Any] = [:]
        for path in CommandLine.arguments.dropFirst() {
            let root = URL(fileURLWithPath: path)
            let project = try SceneProjectLoader().load(from: root)
            let document = try SceneDocumentLoader().load(project: project, packageReport: nil)
            let catalog = try SceneAssetCatalogLoader().load(project: project,
                packageReport: nil, referencedResourcePaths: document.referencedResourcePaths,
                stockAssetsRootURL: nil)
            let descriptor = SceneRenderDescriptorBuilder().build(project: project,
                sceneDocument: document, assetCatalog: catalog)
            let layer = descriptor?.layers.first { $0.imagePath != nil }
            let role = layer?.utilityLayer?.framebufferSource
            let legacy = try JSONDecoder().decode(SceneUtilityLayer.self,
                from: Data("{\"kind\":\"composition\",\"copyBackground\":true,\"passthrough\":false}".utf8))
            var roundtrip = false
            if let utility = layer?.utilityLayer {
                let bytes = try JSONEncoder().encode(utility)
                roundtrip = try JSONDecoder().decode(SceneUtilityLayer.self, from: bytes) == utility
            }
            rows[root.lastPathComponent] = [
                "role": role != nil, "material": role?.materialPath ?? "",
                "receiverID": layer?.id ?? Int.min,
                "kind": layer?.contentKind ?? "absent", "roundtrip": roundtrip,
                "modelPassthrough": catalog.models.first?.passthrough.map { $0 ? 1 : 0 } ?? -1,
                "copyBackground": layer?.utilityLayer?.copyBackground ?? false,
                "layerPassthrough": layer?.utilityLayer?.passthrough ?? false,
                "legacyRoleAbsent": legacy.framebufferSource == nil,
            ]
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def inputs(name: str):
    """Only the named declaration changes from the same independent carrier."""
    renamed = name == "renamed"
    model = "models/independent-card.json" if renamed else "models/owned-plane.json"
    material = "materials/independent-read.json" if renamed else "materials/owned-read.json"
    shader = "independent/projected-copy" if renamed else "owned-source"
    model_value = {"material": material, "passthrough": True}
    pass_value = {"shader": shader, "textures": ["_rt_FullFrameBuffer"],
                  "blending": "translucent", "depthtest": "enabled",
                  "depthwrite": "disabled", "cullmode": "nocull"}
    receiver = {"id": 2, "parent": 1, "image": model, "size": "64 32",
                "effects": [{"id": 21, "file": "effects/owned/effect.json", "visible": True}]}
    scene = {"version": 3, "general": {"orthogonalprojection": None},
             "objects": [{"id": 1, "origin": "0 0 -2"}, receiver]}
    materials = [pass_value]
    if name == "negative-id":
        receiver["id"] = -2
    elif name == "numeric-true":
        model_value["passthrough"] = 1
    elif name == "string-true":
        model_value["passthrough"] = "true"
    elif name == "missing-passthrough":
        model_value.pop("passthrough")
    elif name == "false-passthrough":
        model_value["passthrough"] = False
    elif name == "solid":
        model_value["solidlayer"] = True
    elif name == "orthographic":
        scene["general"]["orthogonalprojection"] = {"width": 320, "height": 200}
    elif name == "flat-override":
        receiver["perspective"] = False
    elif name == "instance":
        receiver["instance"] = {}
    elif name == "child":
        scene["objects"].append({"id": 3, "parent": 2})
    elif name == "dependency":
        receiver["dependencies"] = [1]
    elif name == "layer-config":
        receiver["config"] = {"passthrough": True}
    elif name == "copy-background":
        receiver["copybackground"] = False
    elif name == "advanced-blend":
        receiver["colorBlendMode"] = 1
    elif name == "no-effect":
        receiver["effects"] = []
    elif name == "hidden-effect":
        receiver["effects"][0]["visible"] = False
    elif name == "two-passes":
        materials.append(copy.deepcopy(pass_value))
    elif name == "asset-input":
        pass_value["textures"] = ["owned-color.png"]
    elif name == "other-provider":
        pass_value["textures"] = ["_rt_MipMappedFrameBuffer"]
    elif name == "two-inputs":
        pass_value["textures"].append("owned-color.png")
    elif name.startswith("omit-"):
        pass_value.pop(name.removeprefix("omit-"))
    elif name == "depth-write":
        pass_value["depthwrite"] = "enabled"
    elif name == "additive":
        pass_value["blending"] = "additive"
    elif name == "back-cull":
        pass_value["cullmode"] = "back"
    elif name == "rt-case":
        pass_value["textures"] = ["_RT_fUlLfRaMeBuFfEr"]
    vertex = "uniform mat4 g_ModelViewProjectionMatrix; attribute vec3 a_Position; attribute vec2 a_TexCoord; varying vec2 uv; void main(){uv=a_TexCoord;gl_Position=vec4(a_Position,1.0);}"
    fragment = 'uniform sampler2D g_Texture0; // {"hidden":true}\nvarying vec2 uv; void main(){gl_FragColor=texSample2D(g_Texture0,uv);}'
    return {
        "project.json": {"type": "scene", "file": "scene.json"}, "scene.json": scene,
        model: model_value, material: {"passes": materials},
        "effects/owned/effect.json": {"passes": [{"material": "materials/owned-effect.json"}]},
        "materials/owned-effect.json": {"passes": [{"shader": shader, "textures": [None]}]},
        f"shaders/{shader}.vert": vertex, f"shaders/{shader}.frag": fragment,
    }


class SceneFramebufferSourceRoleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift toolchain unavailable")
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-framebuffer-role-")
        cls.addClassCleanup(cls.directory.cleanup)
        root = Path(cls.directory.name)
        names = ["positive", "renamed", "rt-case", "negative-id", "numeric-true", "string-true",
                 "missing-passthrough", "false-passthrough", "solid", "orthographic", "flat-override",
                 "instance", "child", "dependency", "layer-config", "copy-background", "advanced-blend",
                 "no-effect", "hidden-effect", "two-passes", "asset-input", "other-provider", "two-inputs",
                 "omit-blending", "omit-depthtest", "omit-depthwrite", "omit-cullmode",
                 "depth-write", "additive", "back-cull"]
        roots = []
        for name in names:
            case = root / name
            for path, value in inputs(name).items():
                target = case / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(value if isinstance(value, str) else json.dumps(value))
            roots.append(case)
        force = (SCENE / "Systems/Particles/SceneParticleControlPointForce.swift").read_text()
        start = force.index("nonisolated struct SceneParticleControlPointForceEnvironment:")
        environment = force[start:force.index("\n}", start) + 2]
        source = root / "Probe.swift"
        source.write_text(environment + "\n" + builder.HARNESS_SOURCE.split("@main", 1)[0] + HARNESS)
        binary = root / "probe"
        compiled = subprocess.run(["xcrun", "--sdk", "macosx", "swiftc",
            *map(str, dict.fromkeys(builder.SWIFT_SOURCES)), str(source), "-framework", "Metal",
            "-module-cache-path", str(root / "modules"), "-o", str(binary)],
            capture_output=True, text=True, timeout=180)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        ran = subprocess.run([str(binary), *map(str, roots)], capture_output=True, text=True, timeout=30)
        if ran.returncode:
            raise AssertionError(ran.stdout + ran.stderr)
        cls.facts = json.loads(ran.stdout)

    def test_loaded_semantics_survive_resource_renaming_and_roundtrip(self):
        for name in ("positive", "renamed", "rt-case"):
            with self.subTest(name=name):
                row = self.facts[name]
                self.assertTrue(row["role"], row)
                self.assertEqual(row["kind"], "composition")
                self.assertTrue(row["roundtrip"])
                self.assertTrue(row["copyBackground"])
                self.assertFalse(row["layerPassthrough"])
                self.assertTrue(row["legacyRoleAbsent"])
        self.assertEqual(self.facts["renamed"]["material"], "materials/independent-read.json")

    def test_other_shapes_and_unproven_states_do_not_gain_a_source_role(self):
        for name, row in self.facts.items():
            if name not in {"positive", "renamed", "rt-case"}:
                with self.subTest(name=name):
                    self.assertFalse(row["role"], row)
        self.assertEqual(self.facts["numeric-true"]["modelPassthrough"], -1)
        self.assertEqual(self.facts["string-true"]["modelPassthrough"], -1)
        self.assertEqual(self.facts["negative-id"]["receiverID"], -2)


if __name__ == "__main__":
    unittest.main()
