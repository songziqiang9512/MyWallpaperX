"""Signed Scene checks for texture consumers that still require full resolution."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from PIL import Image

from script.tests.scene.test_scene_embedded_data_mip_resource import _png, _tex
from script.tests.scene.test_scene_mixed_provider_abi_integration import named_vector_entries
from script.tests.support.scene_pkg_fixture import make_package


def image_model(entries, name, rgb):
    model = f"models/{name}.json"
    material = f"materials/{name}.json"
    texture = f"materials/{name}.tex"
    entries[model] = json.dumps({"material": material}).encode()
    entries[material] = json.dumps({"passes": [{"shader": "genericimage2", "textures": [texture],
        "blending": "translucent", "depthtest": "disabled", "depthwrite": "disabled",
        "cullmode": "nocull"}]}).encode()
    mips = [(width, height, _png(width, height, bytes((*rgb, 255)) * (width * height)))
        for width, height in ((4096, 4), (2048, 2), (1024, 1))]
    entries[texture] = _tex(mips, mapped=(4096, 4), physical=(4096, 4))
    return model


class SceneTextureQualityIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        value = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not value:
            raise unittest.SkipTest("requires a frozen signed Debug App")
        app = Path(value).resolve(strict=True)
        cls.exe = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app

    def run_sample(self, project, entries):
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        work = Path(tempfile.mkdtemp(prefix="texture-quality-", dir=parent))
        if not parent:
            self.addCleanup(shutil.rmtree, work)
        content, home, evidence = (work / name for name in ("content", "home", "evidence"))
        for folder in (content, home, evidence):
            folder.mkdir()
        (content / "project.json").write_text(json.dumps(project))
        (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
        environment = {key: val for key, val in os.environ.items()
            if not key.startswith(("MWX_SCENE_", "MYWALLPAPERX_SCENE_"))}
        environment.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1")
        command = [str(self.exe), "--mwx-debug-scene-root", str(content),
            "--mwx-debug-scene-evidence-dir", str(evidence), "--mwx-debug-scene-duration", "7",
            "--mwx-debug-scene-after-snapshot-delay", "4",
            "-mwx.playback.quality", "{ sceneTextureQuality = performance; }"]
        completed = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=50)
        log = completed.stdout + completed.stderr
        (work / "app.log").write_text(log)
        self.assertEqual(completed.returncode, 0, log[-4000:])
        self.assertIn("textureQuality=performance", log)
        self.assertIn("gpuDrained=true", log)
        marker = "MWX SCENE COMPOSITION OBSERVATION: "
        frames = [json.loads(line.split(marker, 1)[1]) for line in log.splitlines() if marker in line]
        self.assertTrue(frames)
        self.assertEqual(sum(frame["truncatedRows"] for frame in frames), 0)
        rows = [row for frame in frames if frame["gpuStatus"] == "completed" for row in frame["rows"]]
        return rows, evidence / "scene-after-window.png", log

    def test_material_definition_keeps_named_source_at_full_resolution(self):
        project, entries = named_vector_entries("both", forward_nested=True)
        scene = json.loads(entries["scene.json"])
        provider = next(layer for layer in scene["objects"] if layer["id"] == 13)
        provider["image"] = image_model(entries, "definition-witness", (192, 32, 16))
        provider["visible"] = True
        self.assertFalse(provider.get("dependencies"))
        scene["objects"].append({"id": 900, "image": provider["image"], "size": "12 12", "origin": "90 100 0"})
        entries["scene.json"] = json.dumps(scene).encode()
        rows, _, log = self.run_sample(project, entries)
        self.assertIn("phase=named-target-capture layer=13 status=succeeded", log)
        for layer, expected in ((13, (4096, 4)), (900, (2048, 2))):
            dimensions = {(row["source"]["width"], row["source"]["height"]) for row in rows
                if row.get("layerID") == layer and row.get("source")
                and row["source"].get("purpose") == "straightAlbedo"}
            self.assertIn(expected, dimensions, (layer, dimensions))

    def test_computed_model_alias_remains_available_to_an_admitted_creator(self):
        project = {"title": "Owned texture quality alias", "type": "scene", "file": "scene.json"}
        entries = {}
        shared = image_model(entries, "shared", (230, 25, 15))
        seed = image_model(entries, "seed", (20, 200, 60))
        script = """
            let once = false;
            export function update(value) {
                if (!once) {
                    once = true;
                    const computed = 'models/' + ['sha', 'red'].join('') + '.json';
                    thisScene.createLayer({image:computed, origin:'128 128 0', size:'40 40'});
                }
                return value;
            }
        """
        scene = {"version": 3, "general": {"orthogonalprojection": {"width": 256, "height": 256}},
            "objects": [{"id": 11, "image": shared, "origin": "25 195 0", "size": "18 18"},
                {"id": 12, "image": seed, "origin": "220 200 0", "size": "18 18",
                    "visible": {"value": True, "script": script}}]}
        entries["scene.json"] = json.dumps(scene).encode()
        rows, picture, _ = self.run_sample(project, entries)
        dimensions = {(row["source"]["width"], row["source"]["height"]) for row in rows
            if row.get("layerID") == 11 and row.get("source") and row["source"].get("purpose") == "straightAlbedo"}
        self.assertIn((4096, 4), dimensions)
        clone_dimensions = {(row["source"]["width"], row["source"]["height"]) for row in rows
            if row.get("layerID") != 11 and row.get("source")
            and row["source"].get("logical") == shared}
        self.assertIn((4096, 4), clone_dimensions)
        with Image.open(picture) as opened:
            image = opened.convert("RGB")
            red, green, blue = image.getpixel((image.width // 2, image.height // 2))
        self.assertGreater(red, 170, (red, green, blue))
        self.assertLess(max(green, blue), 70, (red, green, blue))
