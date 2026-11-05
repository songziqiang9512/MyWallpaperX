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
SOURCE_ROLE_CASES = (
    "positive", "renamed", "rt-case", "dependency", "declared-early", "declared-late",
    "authored-dependency", "effect-named-early", "effect-named-late", "effect-named-renamed",
)
HARNESS = r'''
@main
enum FramebufferRoleProbe {
    static func main() throws {
        var rows: [String: Any] = [:]
        for path in CommandLine.arguments.dropFirst() {
            let root = URL(fileURLWithPath: path)
            let project = try SceneProjectLoader().load(from: root)
            let document = try SceneDocumentLoader().load(from: project.entryURL, propertyCatalog: project.userProperties)
            let view = SceneResourceView(projectRootURL: root, packageRootURL: nil, stockAssetsRootURL: nil)
            let catalog = try SceneAssetCatalogLoader().load(resourceView: view,
                referencedResourcePaths: document.referencedResourcePaths)
            let descriptor = SceneRenderDescriptorBuilder().build(project: project,
                sceneDocument: document, assetCatalog: catalog)
            let layer = descriptor?.layers.first { $0.imagePath != nil && $0.parentID == 1 }
            let role = layer?.utilityLayer?.framebufferSource
            let model = catalog.models.first { $0.relativePath == layer?.imagePath }
            let sourceMaterial = catalog.materials.first { $0.relativePath == model?.materialPath }
            let legacy = try JSONDecoder().decode(SceneUtilityLayer.self,
                from: Data("{\"kind\":\"composition\",\"copyBackground\":true,\"passthrough\":false}".utf8))
            var roundtrip = false
            if let utility = layer?.utilityLayer {
                let bytes = try JSONEncoder().encode(utility)
                roundtrip = try JSONDecoder().decode(SceneUtilityLayer.self, from: bytes) == utility
            }
            let sourceTextureSlots: [String] =
                sourceMaterial?.passes.first?.textureSlots.compactMap { $0 } ?? []
            let effectTextureSlots: [String] =
                layer?.effects.flatMap { $0.passes.flatMap(\.texturePaths) } ?? []
            var row: [String: Any] = [:]
            row["role"] = role != nil
            row["material"] = role?.materialPath ?? ""
            row["receiverID"] = layer?.id ?? Int.min
            row["kind"] = layer?.contentKind ?? "absent"
            row["roundtrip"] = roundtrip
            row["modelPassthrough"] = model?.passthrough.map { $0 ? 1 : 0 } ?? -1
            row["authoredLayerIDs"] = document.objects.map(\.id)
            row["dependencyLayerIDs"] = layer?.dependencyLayerIDs ?? []
            row["authoredDependencyLayerIDs"] = layer?.authoredDependencies.map(\.layerID) ?? []
            row["sourceTextureSlots"] = sourceTextureSlots
            row["effectTextureSlots"] = effectTextureSlots
            row["copyBackground"] = layer?.utilityLayer?.copyBackground ?? false
            row["layerPassthrough"] = layer?.utilityLayer?.passthrough ?? false
            row["legacyRoleAbsent"] = legacy.framebufferSource == nil
            rows[root.lastPathComponent] = row
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def inputs(name: str):
    """Only the named declaration changes from the same independent carrier."""
    renamed = name in {"renamed", "effect-named-renamed"}
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
    effect_file = "effects/owned/effect.json"
    effect_material = "materials/owned-effect.json"
    effect_shader = shader
    effect_textures = [None]
    extra = {}
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
    elif name in {"declared-early", "declared-late", "authored-dependency",
                  "effect-named-early", "effect-named-late", "effect-named-renamed", "named-source-input"}:
        provider_model = "models/other-resource.json" if renamed else "models/provider.json"
        provider_material = "materials/other-resource.json" if renamed else "materials/provider.json"
        provider_texture = "materials/other-color.png" if renamed else "materials/provider-color.png"
        provider = {"id": 3, "image": provider_model, "size": "1 1"}
        late = name in {"declared-late", "authored-dependency", "effect-named-late"}
        scene["objects"].insert(2 if late else 1, provider)
        receiver["dependencies"] = [{"id": 3}] if name == "authored-dependency" else [3]
        extra.update({provider_model: {"material": provider_material, "width": 1, "height": 1},
                      provider_material: {"passes": [{"shader": shader, "textures": [provider_texture]}]}})
        if name.startswith("effect-named-"):
            effect_shader = "moved/named-consumer" if renamed else "owned-named-consumer"
            effect_textures = [None, "_rt_imageLayerComposite_3_a"]
            receiver["effects"][0]["passes"] = [{"textures": effect_textures}]
            if renamed:
                effect_file = "effects/moved/named.json"
                effect_material = "materials/moved/named.json"
                receiver["effects"][0]["file"] = effect_file
        elif name == "named-source-input":
            pass_value["textures"] = ["_rt_imageLayerComposite_3_a"]
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
    files = {
        "project.json": {"type": "scene", "file": "scene.json"}, "scene.json": scene,
        model: model_value, material: {"passes": materials},
        effect_file: {"passes": [{"material": effect_material}]},
        effect_material: {"passes": [{"shader": effect_shader, "textures": effect_textures}]},
        f"shaders/{shader}.vert": vertex, f"shaders/{shader}.frag": fragment,
        **extra,
    }
    if extra:
        # A complete owned resource separates role nomination from missing-source behavior.
        files[provider_texture] = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c635075cffd0f00034701d9d7ce0da80000000049454e44ae426082")
    if name.startswith("effect-named-"):
        files[f"shaders/{effect_shader}.vert"] = vertex
        files[f"shaders/{effect_shader}.frag"] = (
            'uniform sampler2D g_Texture0; // {"hidden":true}\n'
            'uniform sampler2D g_Texture1; // {"material":"albedo"}\n'
            'varying vec2 uv; void main(){gl_FragColor=mix(texSample2D(g_Texture0,uv),'
            'texSample2D(g_Texture1,uv),0.5);}'
        )
    return files


class SceneFramebufferSourceRoleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift toolchain unavailable")
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-framebuffer-role-")
        cls.addClassCleanup(cls.directory.cleanup)
        root = Path(cls.directory.name)
        names = [*SOURCE_ROLE_CASES, "named-source-input", "negative-id", "numeric-true", "string-true",
                 "missing-passthrough", "false-passthrough", "solid", "orthographic", "flat-override",
                 "instance", "child", "layer-config", "copy-background", "advanced-blend",
                 "no-effect", "hidden-effect", "two-passes", "asset-input", "other-provider", "two-inputs",
                 "omit-blending", "omit-depthtest", "omit-depthwrite", "omit-cullmode",
                 "depth-write", "additive", "back-cull"]
        roots = []
        for name in names:
            case = root / name
            for path, value in inputs(name).items():
                target = case / path
                target.parent.mkdir(parents=True, exist_ok=True)
                if isinstance(value, bytes):
                    target.write_bytes(value)
                else:
                    target.write_text(value if isinstance(value, str) else json.dumps(value))
            roots.append(case)
        source = root / "Probe.swift"
        source.write_text(builder.HARNESS_SOURCE.split("@main", 1)[0] + HARNESS)
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

    def test_declarations_and_effect_named_inputs_preserve_the_source_role(self):
        for name in SOURCE_ROLE_CASES[3:]:
            with self.subTest(name=name):
                row = self.facts[name]
                self.assertTrue(row["role"], row)
                self.assertEqual(row["kind"], "composition")
                self.assertEqual(row["sourceTextureSlots"], ["_rt_FullFrameBuffer"])
                self.assertTrue(row["roundtrip"])
        for name in ("dependency", "declared-early", "declared-late", "authored-dependency"):
            self.assertEqual(self.facts[name]["effectTextureSlots"], [])
        self.assertEqual(self.facts["dependency"]["dependencyLayerIDs"], [1])
        self.assertEqual(self.facts["authored-dependency"]["dependencyLayerIDs"], [])
        self.assertEqual(self.facts["authored-dependency"]["authoredDependencyLayerIDs"], [3])
        for name in ("declared-early", "effect-named-early", "effect-named-renamed"):
            self.assertLess(self.facts[name]["authoredLayerIDs"].index(3),
                            self.facts[name]["authoredLayerIDs"].index(2))
        for name in ("declared-late", "authored-dependency", "effect-named-late"):
            self.assertGreater(self.facts[name]["authoredLayerIDs"].index(3),
                               self.facts[name]["authoredLayerIDs"].index(2))
        for name in ("effect-named-early", "effect-named-late", "effect-named-renamed"):
            self.assertEqual(self.facts[name]["effectTextureSlots"], ["_rt_imageLayerComposite_3_a"])
            self.assertEqual(self.facts[name]["dependencyLayerIDs"], [3])
            self.assertEqual(self.facts[name]["authoredDependencyLayerIDs"], [])
        self.assertEqual(self.facts["effect-named-renamed"]["material"],
                         "materials/independent-read.json")

    def test_other_shapes_and_unproven_states_do_not_gain_a_source_role(self):
        for name, row in self.facts.items():
            if name not in SOURCE_ROLE_CASES:
                with self.subTest(name=name):
                    self.assertFalse(row["role"], row)
        self.assertEqual(self.facts["named-source-input"]["sourceTextureSlots"],
                         ["_rt_imageLayerComposite_3_a"])
        self.assertEqual(self.facts["numeric-true"]["modelPassthrough"], -1)
        self.assertEqual(self.facts["string-true"]["modelPassthrough"], -1)
        self.assertEqual(self.facts["negative-id"]["receiverID"], -2)


if __name__ == "__main__":
    unittest.main()
