"""Native Sprite visibility through the actual root compositor and its depth."""
import json
import os
from pathlib import Path
import tempfile
import unittest

from script.tests.scene import test_scene_reflection_history_integration as app_runner
from script.tests.scene import test_scene_native_world_composition as native_world
from script.tests.scene.test_scene_native_world_composition import (
    encoded, mdl_quad, model_material,
    native_world_scene, png, screen,
)
from script.tests.scene.test_scene_native_camera_frame_integration import background_cut_entries
from script.web.web_benchmark_capture import png_rgb_pixels


READERS = (
    (10, "early", (-2.20, 0, 0), "0 255 255"),
    (30, "far", (-.52, 0, 0), "0 0 255"),
    (31, "near", (.56, 0, 2), "0 255 0"),
    (32, "open", (2.20, 0, 0), "0 0 255"),
)
BODY_COLOR = (96, 0, 0)


def fixture(arm):
    shifted = 200 if arm == "renamed" else 0
    stem = "retitled" if shifted else "reader"
    particle_material = f"materials/{stem}/sprite.json"
    model = f"models/{stem}/card.mdl"
    paint = f"materials/{stem}/paint.json"
    texture = f"materials/{stem}/card.png"
    entries = {
        model: mdl_quad(-.75, 1.25, -.67, .67, 1, paint),
        paint: model_material(texture),
        texture: png(4, 4, lambda _x, _y: BODY_COLOR),
        f"materials/{stem}/white.png": png(4, 4, lambda _x, _y: (255, 255, 255)),
        particle_material: encoded({"passes": [{
            "shader": "genericparticle", "textures": [f"{stem}/white.png"],
            "blending": "additive", "cullmode": "nocull", "depthwrite": "disabled",
            "depthtest": "disabled" if arm == "disabled" else "enabled",
        }]}),
    }
    objects = []
    for layer_id, name, origin, color in READERS:
        particle = f"particles/{stem}/{name}.json"
        entries[particle] = encoded({
            "material": particle_material, "maxcount": 1, "starttime": .1, "flags": 1,
            "emitter": [{"name": "sphererandom", "rate": 0, "instantaneous": 1,
                         "distancemin": 0, "distancemax": 0}],
            "initializer": [{"name": "lifetimerandom", "min": 30, "max": 30},
                            {"name": "sizerandom", "min": .44, "max": .44},
                            {"name": "colorrandom", "min": color, "max": color}],
            "renderer": [{"name": "sprite"}],
        })
        objects.append({"id": layer_id + shifted, "name": name, "particle": particle,
                        "perspective": True, "origin": " ".join(map(str, origin))})
    objects.insert(1, {"id": 20 + shifted, "name": "writer", "model": model,
                       "perspective": True, "castshadow": False})
    if arm == "mixed-ortho":
        ortho_model = f"models/{stem}/other-clip.mdl"
        ortho_material = f"materials/{stem}/other-clip.json"
        ortho_texture = f"materials/{stem}/other-clip.png"
        entries[ortho_model] = mdl_quad(48, 176, 48, 176, 0, ortho_material)
        entries[ortho_material] = model_material(ortho_texture)
        entries[ortho_texture] = png(4, 4, lambda _x, _y: (232, 205, 24))
        objects.insert(2, {"id": 21, "name": "other projection", "model": ortho_model,
                           "perspective": False, "castshadow": False})
    scene = native_world_scene(objects)
    scene["general"]["transparentsorting"] = False
    entries["scene.json"] = encoded(scene)
    return entries, particle_material, shifted


class SceneParticleMainDepthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires a frozen Scene App executable")
        cls.app = Path(configured).resolve(strict=True)
        app_binaries = [cls.app, cls.app.with_name("MyWallpaperX.debug.dylib"),
                        cls.app.parent.parent / "Resources/default.metallib"]
        cls.app_identity = {str(path): app_runner.sha256(path) for path in app_binaries if path.is_file()}
        cls.evidence_root = Path(tempfile.mkdtemp(prefix="native-particle-depth-",
                                                dir=os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")))
        sources = [Path(__file__), Path(app_runner.__file__),
                   Path(native_world.__file__), Path(__file__).with_name("test_scene_native_camera_frame_integration.py")]
        cls.source_identity = {str(path): app_runner.sha256(path) for path in sources}
        print(f"Native particle depth evidence: {cls.evidence_root}", flush=True)

    def test_read_only_world_sprite_obeys_earlier_model_depth(self):
        for arm in ("enabled", "disabled", "renamed", "mixed-ortho"):
            with self.subTest(arm=arm):
                entries, material, shifted = fixture(arm)
                for path, event in self.captures(arm, entries, material):
                    rows = event["rows"]
                    draws = [row for row in rows if row["kind"] in ("model", "particle") and row.get("slot") == 0]
                    expected_order = [10, 20, 21, 30, 31, 32] if arm == "mixed-ortho" else [10, 20, 30, 31, 32]
                    self.assertEqual([row["layerID"] for row in draws], [i + shifted for i in expected_order])
                    self.assertEqual(len({row["target"]["textureToken"] for row in draws}), 1)
                    particles = [row["details"] for row in draws if row["kind"] == "particle"]
                    reads = arm in ("enabled", "renamed")
                    self.assertEqual([row["readsSceneDepth"] for row in particles], ["false"] + [str(reads).lower()] * 3)
                    self.assertTrue(all(row["depthWriteEnabled"] == "false" for row in particles))
                    self.assertEqual(len({row["depthTextureToken"] for row in particles if "depthTextureToken" in row}), int(reads))
                    width, height, rgb = png_rgb_pixels(path)
                    far = BODY_COLOR if reads else (96, 0, 255)
                    colors = ((0, 255, 255), far, (96, 255, 0), (0, 0, 255))
                    for (_, name, origin, _), color in zip(READERS, colors, strict=True):
                        x, y = map(round, screen(origin, width, height))
                        self.assertEqual(tuple(rgb[y][3*x:3*x+3]), color, (path, name))
                    if arm == "mixed-ortho":
                        edge = min(width, height) // 10
                        yellow = bytes((232, 205, 24))
                        self.assertTrue(any(row[x:x+3] == yellow for row in rgb[:edge]
                                            for x in range(0, 3*edge, 3)))

    def test_late_model_does_not_cross_particle_and_background_capture(self):
        entries = background_cut_entries(sorting=True, writes_depth=True)
        particle_entries, material, _ = fixture("enabled")
        particle = "particles/reader/far.json"
        for path in (particle, material, "materials/reader/white.png"):
            entries[path] = particle_entries[path]
        scene = json.loads(entries["scene.json"])
        background, capture, _, late_model = scene["objects"]
        prior = {"id": 17, "name": "prior reader", "particle": particle,
                 "origin": ".288 0 -1.2", "perspective": True}
        middle = {**prior, "id": 21, "name": "middle reader", "origin": "1.636364 0 -1.2"}
        after = {**middle, "id": 31, "name": "late reader"}
        scene["objects"] = [background, prior, capture, middle, late_model, after]
        entries["scene.json"] = encoded(scene)
        for path, event in self.captures("background-cut", entries, material):
            rows = [row for row in event["rows"]
                    if row["kind"] in ("model", "particle", "sourceCapture", "group") and row.get("slot") in (0, None)]
            self.assertEqual([(row["kind"], row["layerID"]) for row in rows],
                             [("model", 1), ("particle", 17), ("sourceCapture", 20), ("group", 20),
                              ("particle", 21), ("model", 30), ("particle", 31)])
            readers = [row for row in rows if row["kind"] == "particle"]
            self.assertEqual(len({r["details"]["depthTextureToken"] for r in readers}), 1)
            self.assertEqual(rows[2]["source"]["textureToken"], readers[0]["target"]["textureToken"])
            width, height, rgb = png_rgb_pixels(path)
            for position in ((-.36, 0, 0), (1.5, 0, -.6)):
                x, y = map(round, screen(position, width, height))
                self.assertEqual(tuple(rgb[y][3*x:3*x+3]), (0, 255, 0), (path, position))

    def captures(self, name, entries, material):
        app_runner.SceneReflectionHistoryIntegrationTests.run_case(
            self, 0, capture=True, entries=entries, material_input_path=material, rois={}, name=name,
            extra_arguments=("--mwx-debug-scene-after-snapshot-delay", "2",
                             "--mwx-debug-scene-audio-silence-fixture"),
        )
        work = self.evidence_root / name
        return native_world.SceneNativeWorldCompositionTests.composition_captures(
            self, work, (work / "app.log").read_text())
