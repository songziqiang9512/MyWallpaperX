"""Signed Scene checks for physical texture quality and exact consumers."""

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


def image_model(entries, name, rgb, sizes=((4096, 4), (2048, 2), (1024, 1)), *, invalid_levels=()):
    model = f"models/{name}.json"
    material = f"materials/{name}.json"
    texture = f"materials/{name}.tex"
    entries[model] = json.dumps({"material": material}).encode()
    entries[material] = json.dumps({"passes": [{"shader": "genericimage2", "textures": [texture],
        "blending": "translucent", "depthtest": "disabled", "depthwrite": "disabled",
        "cullmode": "nocull"}]}).encode()
    mips = [
        (width, height, _png(width, height, bytes((*rgb, 255)) * (width * height),
                            invalid_filter=level in invalid_levels))
        for level, (width, height) in enumerate(sizes)
    ]
    entries[texture] = _tex(mips, mapped=sizes[0], physical=sizes[0])
    return model


class SceneTextureQualityIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        value = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not value:
            raise unittest.SkipTest("requires a frozen signed Debug App")
        app = Path(value).resolve(strict=True)
        cls.exe = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app

    def run_sample(self, project, entries, *, mode="performance", resizes=None):
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
        command = [str(self.exe), "--mwx-debug-scene-root", str(content), "--mwx-debug-scene-background",
            "--mwx-debug-scene-evidence-dir", str(evidence), "--mwx-debug-scene-duration", "10" if resizes else "7",
            "--mwx-debug-scene-after-snapshot-delay", "8" if resizes else "4",
            "-mwx.playback.quality", f"{{ sceneTextureQuality = {mode}; }}"]
        if resizes:
            environment["MWX_SCENE_DEBUG_INITIAL_WINDOW_SCALE"] = "0.20"
            command += ["--mwx-debug-scene-start-paused", "--mwx-debug-scene-resize-sequence", resizes]
        completed = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=50)
        log = completed.stdout + completed.stderr
        (work / "app.log").write_text(log)
        self.assertEqual(completed.returncode, 0, log[-4000:])
        self.assertIn(f"textureQuality={mode}", log)
        self.assertIn("gpuDrained=true", log)
        marker = "MWX SCENE COMPOSITION OBSERVATION: "
        frames = [json.loads(line.split(marker, 1)[1]) for line in log.splitlines() if marker in line]
        self.assertTrue(frames)
        self.assertEqual(sum(frame["truncatedRows"] for frame in frames), 0)
        rows = [row for frame in frames if frame["gpuStatus"] == "completed" for row in frame["rows"]]
        return rows, evidence / "scene-after-window.png", log

    def test_automatic_mip_uses_each_sufficient_level_and_releases_retired_textures(self):
        project = {"title": "Owned automatic texture resize", "type": "scene", "file": "scene.json"}
        entries = {}
        sizes = tuple((4096 >> level, 2048 >> level) for level in range(5))
        red = image_model(entries, "scalable-red", (230, 25, 15), sizes=sizes)
        blue = image_model(entries, "partial-blue-tail", (15, 50, 225), sizes=sizes, invalid_levels=(0, 1))
        entries["scene.json"] = json.dumps({"version": 3,
            "general": {"orthogonalprojection": {"width": 4096, "height": 2048}, "parallax": False},
            "objects": [
                {"id": 119, "image": red, "origin": "2048 1024 0", "size": "4096 2048"},
                {"id": 120, "image": red, "origin": "3400 660 0", "size": "500 300"},
                {"id": 121, "image": blue, "origin": "-400 1024 0", "size": "4096 2048"},
            ],
        }).encode()
        rows, image_path, log = self.run_sample(
            project, entries, mode="auto", resizes="1.3:.45,3.8:.20,5.2:1"
        )
        sources_by_layer = {layer: [] for layer in (119, 120, 121)}
        for row in rows:
            if row["kind"] == "ordinary" and row["outcome"] == "draw-encoded" and row.get("layerID") in sources_by_layer:
                source = row["source"]
                sources_by_layer[row["layerID"]].append((source["width"], source["height"], source["textureToken"]))
        sources = sources_by_layer[119]
        observed = list(dict.fromkeys(sources))
        self.assertEqual(sources_by_layer[120], sources)
        self.assertEqual(len(sources_by_layer[121]), len(sources))
        self.assertEqual({entry[:2] for entry in sources_by_layer[121]}, {(1024, 512)})
        self.assertEqual(len(set(sources_by_layer[121])), 1)
        self.assertEqual([entry[:2] for entry in observed], [(1024, 512), (2048, 1024), (4096, 2048)])
        for previous, current in zip(observed, observed[1:]):
            self.assertNotEqual(previous[2], current[2])
        mip_order = {entry: index for index, entry in enumerate(observed)}
        binds = [mip_order[source] for source in sources]
        self.assertEqual(binds, sorted(binds))
        self.assertEqual(binds[-1], 2)
        for index, scale in enumerate(("0.4500", "0.2000", "1.0000")):
            self.assertIn(f"phase=surface-resize index={index} scale={scale} accepted=true", log)
        for width, height, _ in observed[:-1]:
            self.assertRegex(
                log, rf"phase=automatic-mip-retirement layer=119 size={width}x{height} bytes=[1-9]\d* released=true"
            )
        with Image.open(image_path) as image:
            pixels = image.convert("RGB")
            self.assertEqual(pixels.getpixel((image.width // 2, image.height // 2)), (230, 25, 15))
            self.assertEqual(pixels.getpixel((image.width // 20, image.height // 2)), (15, 50, 225))

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
        sizes = tuple((4096 >> level, 512 >> level) for level in range(3))
        shared = image_model(entries, "shared", (230, 25, 15), sizes=sizes)
        seed = image_model(entries, "seed", (20, 200, 60), sizes=((128, 128),))
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
        for mode in ("auto", "performance"):
            with self.subTest(mode=mode):
                rows, picture, _ = self.run_sample(project, entries, mode=mode)
                draws = {(row["layerID"], row["source"]["textureToken"]) for row in rows
                    if row["kind"] == "ordinary" and row["outcome"] == "draw-encoded"
                    and row["access"] == "texture-bind" and row.get("source")
                    and (row["source"]["width"], row["source"]["height"]) == sizes[0]}
                bound_shared_model_layers = {row["layerID"] for row in rows
                    if row["kind"] == "source-selection" and row.get("source")
                    and row["source"].get("logical") == shared
                    and (row["layerID"], row["source"]["textureToken"]) in draws}
                self.assertIn(11, bound_shared_model_layers)
                self.assertTrue(any(layer_id < 0 for layer_id in bound_shared_model_layers))
                with Image.open(picture) as opened:
                    image = opened.convert("RGB")
                    red, green, blue = image.getpixel((image.width // 2, image.height // 2))
                self.assertGreater(red, 170, (red, green, blue))
                self.assertLess(max(green, blue), 70, (red, green, blue))
