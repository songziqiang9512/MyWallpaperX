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
ORTHO_MODEL_COLOR = (232, 205, 24)
LATE_MODEL_COLOR = (230, 192, 24)
FRONT_SPRITE = (2.20 * 4 / 6, 0, 2)
BEHIND_SPRITE = (2.03 * 6.6 / 6, 0, -.60)
OPEN_LATE_SPRITE = (3.24 * 6.6 / 6, 0, -.60)
LATE_MODEL = (2.47 * 7 / 6, 0, -1)
OPEN_LATE_MODEL = (2.94 * 7 / 6, 0, -1)


def fixture(arm, *, translucent=False):
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
            "blending": "translucent" if translucent else "additive", "cullmode": "nocull",
            "depthwrite": "enabled" if translucent and arm != "read-only" else "disabled",
            "depthtest": "disabled" if arm == "disabled" else "enabled",
        }]}),
    }
    objects = []

    def add_sprite(layer_id, name, origin, color, *, material=particle_material, size=.44):
        particle = f"particles/{stem}/{name}.json"
        entries[particle] = encoded({
            "material": material, "maxcount": 1, "starttime": .1, "flags": 1,
            "emitter": [{"name": "sphererandom", "rate": 0, "instantaneous": 1,
                         "distancemin": 0, "distancemax": 0}],
            "initializer": [{"name": "lifetimerandom", "min": 30, "max": 30},
                            {"name": "sizerandom", "min": size, "max": size},
                            {"name": "colorrandom", "min": color, "max": color}],
            "renderer": [{"name": "sprite"}],
        })
        objects.append({"id": layer_id + shifted, "name": name, "particle": particle,
                        "perspective": True, "origin": " ".join(map(str, origin))})

    for layer in READERS[:3] if translucent else READERS:
        add_sprite(*layer)
    objects.insert(1, {"id": 20 + shifted, "name": "writer", "model": model,
                       "perspective": True, "castshadow": False})
    if translucent:
        reader = f"materials/{stem}/late-reader.json"
        entries[reader] = encoded({"passes": [{
            "shader": "genericparticle", "textures": [f"{stem}/white.png"],
            "blending": "additive", "cullmode": "nocull",
            "depthtest": "enabled", "depthwrite": "disabled",
        }]})
        add_sprite(32, "front-sprite", FRONT_SPRITE, "0 0 255", size=1.55)
        add_sprite(33, "behind-sprite", BEHIND_SPRITE, "0 255 0", material=reader)
        add_sprite(34, "open-late-sprite", OPEN_LATE_SPRITE, "0 255 0", material=reader)
        late_model = f"models/{stem}/late-card.mdl"
        late_paint = f"materials/{stem}/late-paint.json"
        late_texture = f"materials/{stem}/late-card.png"
        # At z=-1 the card crosses the blue Sprite edge. Its outer yellow strip
        # proves visibility even if a future regression obscures the inner ROI.
        entries[late_model] = mdl_quad(2.31 * 7 / 6, 3.04 * 7 / 6, -.14, .14, -1, late_paint)
        late_pass = json.loads(model_material(late_texture))
        late_pass["passes"][0]["depthwrite"] = "disabled"
        entries[late_paint] = encoded(late_pass)
        entries[late_texture] = png(4, 4, lambda _x, _y: LATE_MODEL_COLOR)
        objects.append({"id": 40 + shifted, "name": "late model", "model": late_model,
                        "perspective": True, "castshadow": False})
    if arm == "mixed-ortho":
        ortho_model = f"models/{stem}/other-clip.mdl"
        ortho_material = f"materials/{stem}/other-clip.json"
        ortho_texture = f"materials/{stem}/other-clip.png"
        entries[ortho_model] = mdl_quad(48, 176, 48, 176, 0, ortho_material)
        entries[ortho_material] = model_material(ortho_texture)
        entries[ortho_texture] = png(4, 4, lambda _x, _y: ORTHO_MODEL_COLOR)
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
        for arm, samples in (("enabled", 1), ("disabled", 1), ("renamed", 1), ("mixed-ortho", 1),
                             ("enabled", 2), ("renamed", 4)):
            with self.subTest(arm=arm, samples=samples):
                entries, material, shifted = fixture(arm)
                name = arm if samples == 1 else f"{arm}-{samples}x"
                for path, event in self.captures(name, entries, material, samples=samples):
                    rows = event["rows"]
                    draws = [row for row in rows if row["kind"] in ("model", "particle") and row.get("slot") == 0]
                    expected_order = [10, 20, 21, 30, 31, 32] if arm == "mixed-ortho" else [10, 20, 30, 31, 32]
                    self.assertEqual([row["layerID"] for row in draws], [i + shifted for i in expected_order])
                    self.assertEqual(len({row["target"]["textureToken"] for row in draws}), 1)
                    particles = [row["details"] for row in draws if row["kind"] == "particle"]
                    reads = arm in ("enabled", "renamed")
                    self.assertEqual([row["readsSceneDepth"] for row in particles], ["false"] + [str(reads).lower()] * 3)
                    self.assertTrue(all(row["depthWriteEnabled"] == "false" for row in particles))
                    depth_tokens = {row["depthTextureToken"] for row in particles if "depthTextureToken" in row}
                    self.assertEqual(len(depth_tokens), int(reads))
                    if samples > 1:
                        self.assertTrue(all(row["usesDepthAttachment"] == "true" for row in particles))
                    self.assertEqual({row["sampleCount"] for row in particles}, {str(samples)})
                    if samples > 1:
                        root, = [row["details"] for row in rows if row["kind"] == "main-raster-open"]
                        self.assertEqual(root["depthSamples"], str(samples))
                        self.assertEqual({root["depthToken"]}, depth_tokens)
                    width, height, rgb = png_rgb_pixels(path)
                    far = BODY_COLOR if reads else (96, 0, 255)
                    colors = ((0, 255, 255), far, (96, 255, 0), (0, 0, 255))
                    for (_, name, origin, _), color in zip(READERS, colors, strict=True):
                        x, y = map(round, screen(origin, width, height))
                        self.assertEqual(tuple(rgb[y][3*x:3*x+3]), color, (path, name))
                    if samples == 4:
                        reader_y = int(screen((0, .48, 1), width, height)[1])
                        left = round(screen((-.75, 0, 1), width, height)[0])
                        self.assertTrue(any(0 < rgb[reader_y][3*x] < BODY_COLOR[0]
                                            for x in range(left-1, left+2)), path)
                    if arm == "mixed-ortho":
                        edge = min(width, height) // 10
                        yellow = bytes(ORTHO_MODEL_COLOR)
                        self.assertTrue(any(row[x:x+3] == yellow for row in rgb[:edge]
                                            for x in range(0, 3*edge, 3)))

    def test_translucent_world_sprite_reads_without_writing_scene_depth(self):
        for arm in ("enabled", "read-only", "disabled", "renamed"):
            with self.subTest(arm=arm):
                entries, material, shifted = fixture(arm, translucent=True)
                tested = arm != "disabled"
                for path, event in self.captures(f"translucent-{arm}", entries, material):
                    self.assert_translucent_capture(path, event, shifted, tested)

    def test_canvas_translucent_sprite_keeps_later_halo_coverage(self):
        controls = (
            ("read-only", "translucent", False),
            ("authored-write", "translucent", True),
            ("renamed-write", "translucent", True),
            ("additive-write", "additive", True),
        )
        reference = None
        for name, blend, writes_depth in controls:
            with self.subTest(arm=name):
                layer_id = 104 if name == "renamed-write" else 40
                material = f"materials/{name}/paint.json"
                particle = f"particles/{name}.json"
                scene = native_world_scene([{
                    "id": layer_id, "particle": particle, "origin": "640 416 0",
                }])
                scene["general"].update(orthogonalprojection={"width": 1280, "height": 832},
                                        clearcolor=".64 .64 .64", farz=10000)
                entries = {
                    "scene.json": encoded(scene),
                    material: encoded({"passes": [{
                        "shader": "genericparticle", "textures": ["particle/halo"],
                        "blending": blend, "cullmode": "nocull", "depthtest": "enabled",
                        "depthwrite": "enabled" if writes_depth else "disabled",
                    }]}),
                    particle: encoded({
                        "material": material, "maxcount": 2, "starttime": .25,
                        "emitter": [{"name": "sphererandom", "origin": origin, "rate": 0,
                                     "instantaneous": 1, "distancemin": 0, "distancemax": 0}
                                    for origin in ("-40 0 8", "0 0 -8")],
                        "initializer": [{"name": "lifetimerandom", "min": 30, "max": 30},
                                        {"name": "sizerandom", "min": 180, "max": 180},
                                        {"name": "colorrandom", "min": "220 30 30", "max": "220 30 30"}],
                        "renderer": [{"name": "sprite"}],
                    }),
                }
                for path, event in self.captures(f"canvas-{name}", entries, material):
                    draw, = [row for row in event["rows"] if row.get("layerID") == layer_id
                             and row["kind"] == "particle" and row.get("slot") == 0]
                    expected_depth = str(blend == "additive").lower()
                    self.assertEqual(draw["details"]["depthTestEnabled"], "true")
                    self.assertEqual(draw["details"]["depthWriteEnabled"], expected_depth)
                    self.assertEqual(draw["details"]["usesDepthAttachment"], expected_depth)
                    self.assertEqual(draw["details"]["instanceCount"], "2")
                    if blend == "translucent":
                        width, height, rgb = png_rgb_pixels(path)
                        x, y = width // 2 - 3, height // 2
                        r, g, b = rgb[y][3*x:3*x+3]
                        self.assertGreater(r - max(g, b), 30, (path, r, g, b))
                        crop = [row[3*(x-22):3*(x+22)] for row in rgb[y-14:y+14]]
                        if reference is None:
                            reference = crop
                        self.assertEqual(crop, reference, path)

    def test_translucent_world_sprite_keeps_private_depth_only_for_drawn_ortho_writer(self):
        for alpha, auto_canvas in ((1, False), (0, False), (1, True)):
            with self.subTest(ortho_alpha=alpha, auto_canvas=auto_canvas):
                entries, material, shifted = fixture("mixed-ortho", translucent=True)
                scene = json.loads(entries["scene.json"])
                if auto_canvas:
                    scene["general"]["orthogonalprojection"] = {"auto": True}
                layers = {layer["id"]: layer for layer in scene["objects"]}
                del entries[layers.pop(10)["particle"]]
                scene["objects"] = list(layers.values())
                ortho = layers[21]
                ortho.update(visible=True, alpha=alpha)
                entries["scene.json"] = encoded(scene)
                name = f"translucent-mixed-ortho-{alpha}" + ("-auto" if auto_canvas else "")
                # An actual private writer still prevents admission of the complete root.
                samples = 4 if alpha and not auto_canvas else 1
                for path, event in self.captures(name, entries, material, samples=samples):
                    particle_rows = [row for row in event["rows"] if row["kind"] == "particle"]
                    self.assertEqual({row["details"]["sampleCount"] for row in particle_rows}, {"1"})
                    self.assert_translucent_capture(path, event, shifted, tested=True,
                                                     orthographic_writer=bool(alpha))

    def assert_translucent_capture(self, path, event, shifted, tested, *, orthographic_writer=None):
        rows = event["rows"]
        draws = [row for row in rows if row["kind"] in ("model", "particle") and row.get("slot") == 0]
        order = [20, 30, 31, 32, 33, 34, 40]
        if orthographic_writer is None:
            order.insert(0, 10)
        if orthographic_writer:
            order.insert(1, 21)
        self.assertEqual([row["layerID"] - shifted for row in draws], order)
        by_layer = {row["layerID"] - shifted: row for row in draws}
        if orthographic_writer:
            self.assertEqual((by_layer[21]["kind"], by_layer[21]["details"]["depthWrite"]), ("model", "true"))
        seal, = [row for row in rows if row["kind"] == "frame-seal" and row["outcome"] == "sealed"]
        self.assertEqual({row["target"]["textureToken"] for row in draws}, {seal["target"]["textureToken"]})
        self.assertTrue(all(row["outcome"] == "draw-encoded" for row in draws))
        self.assertEqual([(by_layer[i]["details"]["depthTest"], by_layer[i]["details"]["depthWrite"])
                          for i in (20, 40)], [("true", "true"), ("true", "false")])

        shared, private = set(), set()
        for layer_id, row in by_layer.items():
            if row["kind"] != "particle":
                continue
            details = row["details"]
            additive = layer_id in (33, 34)
            tests_depth = additive or tested
            read = not orthographic_writer and layer_id != 10 and tests_depth
            write = bool(orthographic_writer) and not additive
            self.assertEqual(details["blendMode"], "additive" if additive else "translucent", details)
            self.assertEqual(details["usesSceneCamera"], "true", details)
            self.assertEqual(details["depthTestEnabled"], str(tests_depth).lower(), details)
            self.assertEqual(details["depthWriteEnabled"], str(write).lower(), details)
            self.assertEqual(details["readsSceneDepth"], str(read).lower(), details)
            self.assertEqual(details["usesDepthAttachment"], str(read or write).lower(), details)
            if read:
                shared.add(details["depthTextureToken"])
            elif write:
                private.add(details["depthTextureToken"])
            else:
                self.assertNotIn("depthTextureToken", details)
        self.assertEqual((len(shared), len(private)), (0, 3) if orthographic_writer else (1, 0))

        width, height, rgb = png_rgb_pixels(path)
        if orthographic_writer is not None:
            self.assertEqual(tuple(rgb[112][3*112:3*113]),
                             ORTHO_MODEL_COLOR if orthographic_writer else (0, 0, 0), path)
        probes = {
            "behind early model": (READERS[1][2], BODY_COLOR if tested and not orthographic_writer else (0, 0, 255)),
            "near over early model": (READERS[2][2], (0, 255, 0)),
            "open part of early model": ((.24, .45, 1), BODY_COLOR),
            "front sprite": (FRONT_SPRITE, (0, 0, 255)),
            "later far sprite over front sprite": (BEHIND_SPRITE, (0, 255, 255)),
            "open late sprite": (OPEN_LATE_SPRITE, (0, 255, 0)),
            "later far model over front sprite": (LATE_MODEL, LATE_MODEL_COLOR),
            "open part of late model": (OPEN_LATE_MODEL, LATE_MODEL_COLOR),
            "front sprite above late model": ((2.47 * 4 / 6, .20, 2), (0, 0, 255)),
        }
        if orthographic_writer is None:
            probes["early with no scene depth"] = (READERS[0][2], (0, 255, 255))
        for name, (position, expected) in probes.items():
            x, y = map(round, screen(position, width, height))
            self.assertEqual(tuple(rgb[y][3*x:3*x+3]), expected, (path, name))

    def test_sorted_opaque_prefix_supplies_background_and_read_only_particles(self):
        particle = "particles/reader/far.json"
        prior = {"id": 17, "name": "prior reader", "particle": particle,
                 "origin": ".288 0 -1.2", "perspective": True}
        far = (1.636364, -.14, -1.2)
        near = (1.272727, .115, .4)
        readers = [{**prior, "id": layer_id, "name": name, "origin": " ".join(map(str, position))}
                   for layer_id, name, position in ((21, "far reader", far), (22, "near reader", near))]
        for arm, sorting, tests_depth in (("sorted", True, True), ("depth-off", True, False),
                                          ("sort-off", False, True)):
            with self.subTest(arm=arm):
                entries = background_cut_entries(sorting=sorting, writes_depth=True)
                particle_entries, material, _ = fixture("enabled" if tests_depth else "disabled")
                for resource in (material, "materials/reader/white.png"):
                    entries[resource] = particle_entries[resource]
                sprite = json.loads(particle_entries[particle])
                sprite["initializer"][1].update(min=.14, max=.14)
                entries[particle] = encoded(sprite)
                scene = json.loads(entries["scene.json"])
                background, capture, _, late_model = scene["objects"]
                scene["objects"] = [background, prior, capture, *readers, late_model]
                entries["scene.json"] = encoded(scene)
                for path, event in self.captures(f"background-cut-{arm}", entries, material):
                    rows = [row for row in event["rows"] if row["kind"] in
                            ("model", "particle", "sourceCapture", "group") and row.get("slot") in (0, None)]
                    output = [(row["kind"], row["layerID"]) for row in rows]
                    expected = [("model", 1), ("particle", 17), ("sourceCapture", 20), ("group", 20),
                                ("particle", 21), ("particle", 22)]
                    expected.insert(2 if sorting else len(expected), ("model", 30))
                    self.assertEqual(output, expected)
                    capture_row = next(row for row in rows if row["kind"] == "sourceCapture")
                    draws = [row for row in rows if row["kind"] == "particle"]
                    self.assertEqual({row["target"]["textureToken"] for row in draws},
                                     {capture_row["source"]["textureToken"]})
                    self.assertEqual({row["details"]["readsSceneDepth"] for row in draws},
                                     {str(tests_depth).lower()})
                    self.assertEqual({row["details"]["depthWriteEnabled"] for row in draws}, {"false"})
                    self.assertEqual(len({row["details"]["depthTextureToken"] for row in draws
                                          if "depthTextureToken" in row["details"]}), int(tests_depth))
                    width, height, rgb = png_rgb_pixels(path)
                    green, cyan = (0, 255, 0), (0, 255, 255)
                    for position, color in (((-.36, 0, 0), (255, 0, 255) if sorting else green),
                                            (far, cyan if not tests_depth else green),
                                            (near, cyan if sorting else green)):
                        x, y = map(round, screen(position, width, height))
                        self.assertEqual(tuple(rgb[y][3*x:3*x+3]), color, (path, position))

    def test_project_color_read_cannot_discard_later_particle_depth(self):
        entries, material, _ = fixture("enabled")
        scene = json.loads(entries["scene.json"])
        scene["general"]["orthogonalprojection"] = {"auto": True}
        project = "models/util/projectlayer.json"
        entries[project] = encoded({"width": 1280, "height": 832, "autosize": False})
        scene["objects"].insert(2, {
            "id": 41, "image": project, "copybackground": True,
            "origin": "640 416 0", "size": "1280 832", "perspective": False,
            "colorBlendMode": 18, "color": "0 1 0",
        })
        entries["scene.json"] = encoded(scene)
        for path, event in self.captures("project-read-before-particles", entries, material, samples=4):
            rows = event["rows"]
            capture = next(i for i, row in enumerate(rows)
                           if row["kind"] == "sourceCapture" and row["layerID"] == 41
                           and row["outcome"] == "draw-encoded")
            far = next(i for i, row in enumerate(rows)
                       if row["kind"] == "particle" and row["layerID"] == 30 and row["slot"] == 0)
            self.assertLess(capture, far)
            self.assertEqual(rows[far]["details"]["readsSceneDepth"], "true")
            self.assertEqual({row["details"]["sampleCount"] for row in rows
                              if row["kind"] == "main-raster-open"}, {"1"})
            width, height, rgb = png_rgb_pixels(path)
            far_x, far_y = map(round, screen(READERS[1][2], width, height))
            open_x, open_y = map(round, screen(READERS[3][2], width, height))
            self.assertEqual((rgb[far_y][3*far_x+2], rgb[open_y][3*open_x+2]), (0, 255), path)

    def captures(self, name, entries, material, *, samples=1):
        quality = f"{{ sceneAntiAliasingMode = {('none' if samples == 1 else f'msaa{samples}')}; }}"
        app_runner.SceneReflectionHistoryIntegrationTests.run_case(
            self, 0, capture=True, entries=entries, material_input_path=material, rois={}, name=name,
            extra_arguments=("--mwx-debug-scene-after-snapshot-delay", "2",
                             "--mwx-debug-scene-audio-silence-fixture", "-mwx.playback.quality", quality),
        )
        work = self.evidence_root / name
        return native_world.SceneNativeWorldCompositionTests.composition_captures(
            self, work, (work / "app.log").read_text())
