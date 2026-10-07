"""Authored deletion keeps missing named inputs local through real App preflight.

All package assets and shaders come from owned fixtures. Set a frozen Debug
MWX_SCENE_INTEGRATION_APP; a passing test proves this bounded GPU/compositor
chain, not official parity. Every run has a fresh package, HOME and shader cache.
"""
from pathlib import Path
import copy
import json
import os
import re
import subprocess
import tempfile
import unittest

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_hidden_provider_integration import fixture_entries as hidden_fixture
from .test_scene_directional_shadow_integration import png
from .test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from .test_scene_pkg_cache_extractor import make_package


REPO = Path(__file__).resolve().parents[2]
SOURCE_PATHS = tuple(REPO / "MyWallpaperX/Core/SteamWorkshopScene" / path for path in (
    "Rendering/Frame/SceneResolvedMaterialFramePreflight.swift",
    "Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift",
    "Rendering/Composition/SceneResolvedMaterialGraphComposition.swift"))


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def fixture_entries(case):
    project, entries = hidden_fixture(conditional=False, optional=True)
    scene = json.loads(entries["scene.json"])
    provider, consumer, healthy = scene["objects"]
    healthy["origin"] = "96 64 0"
    consumer["effects"][0]["passes"][0].pop("usertextures")
    provider["name"] = "retired-provider"
    provider["effects"] = [{"id": 110, "file": "effects/own_dim/effect.json", "visible": True}]
    entries.update({
        "effects/own_dim/effect.json": encoded({"passes": [{"material": "materials/own_dim.json"}]}),
        "materials/own_dim.json": encoded({"passes": [{"shader": "own_dim", "textures": [None],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
        "shaders/own_dim.vert": entries["shaders/own_sample.vert"],
        "shaders/own_dim.frag": b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
            b"void main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n"})
    target_name = provider["name"]
    terminal = consumer
    independent = None
    background = None
    if case.startswith("aggregate"):
        second = copy.deepcopy(provider)
        second.update(id=12, name="surviving-provider", image="models/green.json", origin="24 24 0")
        second["effects"][0]["id"] = 120
        entries.update({"models/green.json": encoded({"material": "materials/green.json"}),
            "materials/green.json": encoded({"passes": [{"shader": "genericimage", "textures": ["materials/green.png"]}]}),
            "materials/green.png": png((0, 255, 0, 255))})
        extra_effect = copy.deepcopy(consumer["effects"][0])
        extra_effect.update(id=221)
        extra_effect["passes"][0].update(id=2211, textures=[None, "_rt_imageLayerComposite_12_a"])
        consumer["effects"].append(extra_effect)
        consumer["dependencies"] = [11, 12]
    if case in ("upstream", "middle", "aggregate-provider"):
        consumer.update(name="middle-provider", visible=False)
        terminal = copy.deepcopy(consumer)
        terminal.update(id=44, name="visible-terminal", visible=True, dependencies=[22])
        terminal["effects"] = [copy.deepcopy(consumer["effects"][0])]
        terminal["effects"][0]["id"] = 440
        terminal["effects"][0]["passes"][0].update(id=4401, textures=[None, "_rt_imageLayerComposite_22_a"])
        if case == "middle":
            target_name = consumer["name"]
        if case == "aggregate-provider":
            # The supported nested shape is aggregate -> aggregate. A single
            # consumer of a multi-source provider is outside current admission.
            terminal["dependencies"] = [22, 12]
            last_effect = copy.deepcopy(consumer["effects"][1])
            last_effect["id"] = 441
            last_effect["passes"][0]["id"] = 4411
            terminal["effects"].append(last_effect)
            # A separate visible root must retain the surviving graph provider
            # while both aggregate consumers retire.
            independent = copy.deepcopy(terminal)
            independent.update(id=55, name="independent-consumer", origin="96 84 0", dependencies=[12])
            independent["effects"] = [independent["effects"][0]]
            independent["effects"][0]["id"] = 550
            independent["effects"][0]["passes"][0].update(id=5501, textures=[None, "_rt_imageLayerComposite_12_a"])
    if case.startswith("aggregate"):
        # Visible aggregates use the existing childless composition owner.
        # White background is the preregistered whole-consumer fallback.
        terminal.update(image="models/util/composelayer.json", origin="64 64 0",
                        size="128 128", copybackground=True)
        background = {"id": 1, "name": "White fallback witness", "image": "models/own_solid.json",
                      "origin": "64 64 0", "size": "128 128", "color": "1 1 1", "visible": True}
        entries.update({"models/util/composelayer.json": encoded({"width": 128, "height": 128, "autosize": False}),
                        "models/own_solid.json": encoded({"solidlayer": True, "width": 128, "height": 128})})
    healthy["visible"] = {"value": True, "script": """
let removed = false;
export function update(value) {
    if (engine.runtime > 2 && !removed) {
        thisScene.destroyLayer('%s'); removed = true;
    }
    return true;
}
""" % target_name}
    # Simple consumers precede providers, exercising forward preparation.
    # A nested multi-source provider uses the supported dependency-first
    # authored order; its independent surviving demand is still visible.
    if case == "aggregate-provider":
        objects = [background, provider, second, consumer, terminal, healthy, independent]
    else:
        objects = ([background] if background else []) + [terminal, healthy, provider]
        if case.startswith("aggregate"):
            objects.append(second)
        if terminal is not consumer:
            objects.append(consumer)
    scene["objects"] = objects
    entries["scene.json"] = encoded(scene)
    return project, entries


class SceneDeletedNamedProviderIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires frozen MWX_SCENE_INTEGRATION_APP")
        app = Path(configured).resolve(strict=True)
        cls.exe = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app
        cls.app_identity = app_hashes(cls.exe)
        cls.source_identity = file_hashes(SOURCE_PATHS)

    def run_case(self, case):
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        root = Path(tempfile.mkdtemp(prefix="deleted-named-" + case + "-", dir=parent))
        print(f"deleted named provider evidence: {root}", flush=True)
        content, home, evidence = root / "content", root / "home", root / "evidence"
        content.mkdir()
        home.mkdir()
        project, entries = fixture_entries(case)
        (content / "project.json").write_bytes(encoded(project))
        (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
        inputs = file_hashes(tuple(content.iterdir()))
        command = [str(self.exe), "--mwx-debug-scene-root", str(content),
            "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence),
            "--mwx-debug-scene-after-snapshot-delay", "4.2"]
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
            MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "cache"))
        (root / "prerun.json").write_bytes(encoded({"command": command, "app": self.app_identity,
            "sources": self.source_identity, "inputs": inputs, "case": case}))
        self.assertEqual(app_hashes(self.exe), self.app_identity)
        self.assertEqual(file_hashes(SOURCE_PATHS), self.source_identity)
        with (root / "app.log").open("w") as output:
            result = subprocess.run(command, cwd=REPO, env=env, stdout=output,
                stderr=subprocess.STDOUT, timeout=90)
        log = (root / "app.log").read_text()
        pixels = {}
        for path in sorted(evidence.glob("*-window.png")):
            decoded = png_rgb_pixels(path)
            self.assertIsNotNone(decoded, path.name)
            width, height, rows = decoded
            def point(x, y):
                scale = max(width / 128, height / 128)
                px = round(width / 2 + (x - 64) * scale)
                py = round(height / 2 - (y - 64) * scale)
                self.assertTrue(0 <= px < width and 0 <= py < height, (path.name, x, y, width, height))
                return list(rows[py][px * 3:][:3])
            pixels[path.name] = {"terminal": point(64, 64), "healthy": point(96, 64),
                "independent": point(96, 84)}
        after_app, after_sources = app_hashes(self.exe), file_hashes(SOURCE_PATHS)
        after_inputs = file_hashes(tuple(content.iterdir()))
        (root / "result.json").write_bytes(encoded({"exit": result.returncode, "pixels": pixels,
            "appAfter": after_app, "sourcesAfter": after_sources, "inputsAfter": after_inputs,
            "boundary": "owned same-window deletion, real Metal/compositor; no official parity"}))
        self.assertEqual(after_app, self.app_identity)
        self.assertEqual(after_sources, self.source_identity)
        self.assertEqual(after_inputs, inputs)
        self.assertEqual(result.returncode, 0, log[-5000:])
        self.assertIn("gpuDrained=true", log)
        self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
        self.assertNotRegex(log, r"phase=launch-failed|phase=snapshot-(?:failed|rejected)|failure=exception")
        self.assertNotIn("predecessor-output-not-consumed", log)
        self.assertNotIn("frame-success-blueprint-rejected", log)
        ready, after = pixels["scene-ready-window.png"], pixels["scene-after-window.png"]
        expected = [0, 128, 0] if case.startswith("aggregate") else [0, 0, 128]
        for actual, wanted in zip(ready["terminal"], expected):
            self.assertAlmostEqual(actual, wanted, delta=4)
        self.assertEqual(after["terminal"], [255, 255, 255], pixels)
        for phase in (ready, after):
            self.assertEqual(phase["healthy"], [0, 255, 0], pixels)
            if case == "aggregate-provider":
                for actual, wanted in zip(phase["independent"], [0, 128, 0]):
                    self.assertAlmostEqual(actual, wanted, delta=4)
        self.assertIn("phase=named-graph-output-publication layer=11", log)

    def test_deleted_hidden_graph_provider_keeps_healthy_output(self):
        self.run_case("single")

    def test_deleted_upstream_keeps_surviving_graph_chain_local(self):
        self.run_case("upstream")

    def test_deleted_middle_does_not_prepare_orphan_upstream(self):
        self.run_case("middle")

    def test_deleted_aggregate_member_cannot_consume_partial_vector(self):
        self.run_case("aggregate")

    def test_unavailable_aggregate_provider_preserves_independent_demand(self):
        self.run_case("aggregate-provider")


if __name__ == "__main__":
    unittest.main()
