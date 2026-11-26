#!/usr/bin/env python3
"""Compare actual 1× and 2× main raster output in one signed Debug App."""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import unittest
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageChops

from script.scene.scene_wallpaper_graph_output_metrics import (
    structured_runtime_observations,
    terminal_composition_snapshot,
    terminal_snapshot_metrics,
)
from script.tests.scene.test_scene_composition_authored_order_integration import fixture_entries as composition_fixture
from script.tests.scene.test_scene_directional_shadow_integration import quad
from script.tests.scene.test_scene_fullscreen_visibility_integration import fixture_entries as fullscreen_fixture
from script.tests.scene.test_scene_named_model_shadow import named_fixture
from script.tests.scene.test_scene_native_world_composition import (
    DEPTH_CARD_COLORS,
    GREEN,
    ORANGE,
    measure_capture,
    perspective_image_depth_entries,
)
from script.tests.scene.test_scene_reflection_history_integration import (
    CANVAS,
    METAL_FAILURE,
    MODEL_ROIS,
    model_reflection_entries,
    rgba_png,
    sha256,
)
from script.tests.scene.test_scene_static_model_reader import build_model
from script.tests.support.scene_pkg_fixture import make_package


ADDITIVE_LAYER = 14
BACKGROUND_LAYER, ALPHA_LAYER, TEXT_LAYER, UNPREPARED_SPOT_LAYER = 29, 30, 31, 32


def model_input(variant):
    if variant == "additive-reflection":
        entries = model_reflection_entries(1)
        material = json.loads(entries["materials/receiver.json"])
        material["passes"][0]["blending"] = "additive"
        entries["materials/receiver.json"] = json.dumps(material).encode()
        scene = json.loads(entries["scene.json"])
        models = [layer["id"] for layer in scene["objects"] if "model" in layer]
        scene["objects"][0]["alpha"] = 0.5
        scene["objects"].insert(0, {
            "id": 60, "image": "models/util/solidlayer.json", "origin": "80 62 0",
            "size": "20 20", "color": "0 0.25 0",
        })
        entries["scene.json"] = json.dumps(scene).encode()
        return entries, models
    if variant in ("local-then-root-tail", "root-read-before-model"):
        entries = perspective_image_depth_entries(7)
        scene = json.loads(entries["scene.json"])
        scene["objects"] = [layer for layer in scene["objects"] if layer["id"] == 21 or "model" in layer]
        _, fullscreen = fullscreen_fixture()
        consumer = json.loads(fullscreen.pop("scene.json"))["objects"][1]
        consumer.pop("visible")
        consumer.update(id=87, origin="0 0 0", perspective=False)
        if variant == "local-then-root-tail":
            scene["objects"].append(consumer)
        else:
            scene["objects"].insert(-1, consumer)
        entries.update(fullscreen)
        entries["scene.json"] = json.dumps(scene).encode()
        return entries, [layer["id"] for layer in scene["objects"] if "model" in layer]
    if variant in ("shared-depth", "shared-depth-renamed"):
        entries = perspective_image_depth_entries(7)
        scene = json.loads(entries["scene.json"])
        scene["objects"] = [layer for layer in scene["objects"] if layer["id"] != 22]
        for layer in scene["objects"]:
            layer.pop("effects", None)
        writer = next(layer for layer in scene["objects"] if layer["id"] == 21)
        stem = "depth_card_21"
        if variant == "shared-depth-renamed":
            writer.update(id=121, image="models/camera-band.json")
            entries[writer["image"]] = entries.pop(f"models/{stem}.json").replace(
                stem.encode(), b"camera-band")
            entries["materials/camera-band.json"] = entries.pop(f"materials/{stem}.json").replace(
                stem.encode(), b"camera-band")
            stem = "camera-band"
        color = DEPTH_CARD_COLORS[1]
        stripe = Image.new("RGBA", (16, 4))
        stripe.paste((*color, 128), (0, 0, 5, 4))
        stripe.paste((*color, 255), (11, 0, 16, 4))
        png = BytesIO()
        stripe.save(png, format="PNG")
        entries[f"materials/{stem}.png"] = png.getvalue()
        entries["scene.json"] = json.dumps(scene).encode()
        return entries, [layer["id"] for layer in scene["objects"] if "model" in layer]
    alternate = variant == "renamed-hdr"
    stem = "offset-stripe" if alternate else "receiver"
    entries = model_reflection_entries(0, stem=stem)
    entries[f"materials/{stem}.png"] = rgba_png((255, 0, 0))
    scene = json.loads(entries.pop("scene.json"))
    first, second, far, edge, suffix = scene["objects"]
    scene["objects"] = [first, far, second, edge]
    points = [(45., 62.), (61., 68.), (40., 78.)] if alternate else [(39., 62.), (58., 62.), (41., 77.)]
    material = "materials/opaque-green.json"
    if alternate:
        new_material = "materials/adjusted-outline.json"
        outline = json.loads(entries.pop(material))
        outline["passes"][0]["textures"] = ["materials/adjusted-outline.png"]
        entries[new_material] = json.dumps(outline).encode()
        entries["materials/adjusted-outline.png"] = entries.pop("materials/opaque-green.png")
        entries.pop(edge["model"])
        edge["model"] = "models/adjusted-outline.mdl"
        material = new_material
        for layer in scene["objects"]:
            layer["id"] += 100
    xs, ys = zip(*points)
    entries[edge["model"]] = build_model(
        vertices=[((x, y, 0.), (0., 0., 1.), (0., 1., 0., 1.), uv)
                  for (x, y), uv in zip(points, [(0., 0.), (1., 0.), (0., 1.)])],
        indices=(0, 2, 1), bounds=(min(xs), min(ys), 0., max(xs), max(ys), 0.), material=material.encode(),
    )
    if variant == "plain":
        material = "materials/additive-marker.json"
        model = "models/additive-marker.mdl"
        additive = json.loads(entries["materials/late-blue.json"])
        additive["passes"][0].update(textures=[f"materials/{stem}.png"], blending="additive", depthwrite="disabled")
        entries[material] = json.dumps(additive).encode()
        entries[model] = quad(78, 82, 43, 46, 0, material)
        scene["objects"].append(dict(edge, id=ADDITIVE_LAYER, model=model))
    elif variant in ("suffix", "color-blend"):
        background = dict(suffix, id=BACKGROUND_LAYER, origin="80 48 0", size="160 96",
                          color="0 0 .25", perspective=False)
        suffix.update(image="models/mixed-alpha.json", origin="96 48 0", size="40 16",
                      alpha=0.5, perspective=False)
        entries["models/mixed-alpha.json"] = json.dumps({"material": "materials/mixed-alpha.json"}).encode()
        entries["materials/mixed-alpha.json"] = json.dumps({"passes": [{
            "shader": "genericimage", "textures": ["materials/mixed-alpha.png"],
            "blending": "translucent",
        }]}).encode()
        entries["materials/mixed-alpha.png"] = rgba_png((255, 255, 255))
        if variant == "color-blend":
            suffix["colorBlendMode"] = 2
        text = {"id": TEXT_LAYER, "text": "MMMM", "font": "systemfont_arial",
                "pointsize": 3, "color": "1 1 1", "origin": "126 20 0",
                "size": "48 18", "perspective": False}
        unprepared_spot = {"id": UNPREPARED_SPOT_LAYER, "light": "lspot", "visible": True, "solid": False,
                           "castvolumetrics": True, "color": "1 0 1", "origin": "20 16 0",
                           "radius": 30, "intensity": 25, "innercone": 10, "outercone": 20,
                           "density": 3, "exponent": 2, "volumetricsexponent": 2}
        scene["objects"] = [background, *scene["objects"], suffix, text, unprepared_spot]
    elif variant in ("current-color", "color-prefix"):
        _, readers = composition_fixture(copy_background=True, childless=True)
        base, consumer = json.loads(readers.pop("scene.json"))["objects"]
        consumer.update(id=87, origin="80 48 0", size="160 96")
        if variant == "color-prefix":
            base.update(id=85, origin="80 48 0", size="160 96")
            scene["objects"][:0] = [base, consumer]
        else:
            scene["objects"].append(consumer)
        entries.update(readers)
    elif variant == "named":
        named_scene, sources = named_fixture("forward-graph-neighbor")
        sources.pop("scene.json")
        scene["objects"].extend(layer for layer in named_scene["objects"] if layer["id"] in {31, 50})
        entries = sources | entries
    if alternate or variant == "history":
        scene["general"].update(hdr=True, clearenabled=alternate)
    entries["scene.json"] = json.dumps(scene, sort_keys=True).encode()
    return entries, [layer["id"] for layer in scene["objects"] if "model" in layer]


def canvas_box(image, left, top, right, bottom):
    width, height = image.size
    scale = max(width / CANVAS[0], height / CANVAS[1])
    return tuple(round(center + (point - extent / 2) * scale)
                 for point, center, extent in zip((left, top, right, bottom),
                                                  (width / 2, height / 2) * 2, CANVAS * 2))


class SceneMultisampleIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not app:
            raise unittest.SkipTest("requires a frozen signed Debug App and a visible display")
        path = Path(app).resolve(strict=True)
        cls.app = path if path.suffix == ".app" else next(parent for parent in path.parents if parent.suffix == ".app")
        cls.exe = cls.app / "Contents/MacOS/MyWallpaperX"
        outputs = (cls.exe, cls.exe.with_name("MyWallpaperX.debug.dylib"), cls.app / "Contents/Resources/default.metallib")
        cls.identity = {str(path): sha256(path) for path in outputs if path.is_file()}
        cls.verify_app()
        cls.addClassCleanup(cls.verify_app)
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
            cls.work = Path(tempfile.mkdtemp(prefix="qaa-", dir=parent))
        else:
            temporary = tempfile.TemporaryDirectory(prefix="mwx-qaa-")
            cls.addClassCleanup(temporary.cleanup)
            cls.work = Path(temporary.name)

    @classmethod
    def verify_app(cls):
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(cls.app)],
                       check=True, capture_output=True)
        if any(sha256(Path(path)) != digest for path, digest in cls.identity.items()):
            raise AssertionError("signed App changed between the paired observations")

    def run_arm(self, folder, content, samples, *, requires_presentation):
        home = folder / "home"
        home.mkdir(parents=True)
        evidence = folder / "evidence"
        evidence.mkdir()
        temporary = folder / "tmp"
        temporary.mkdir()
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(("MWX_SCENE_", "MYWALLPAPERX_SCENE_"))}
        environment.update(HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temporary),
                           MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                           MYWALLPAPERX_SCENE_DEBUG_SCENE_TIME="3.25",
                           MYWALLPAPERX_SCENE_DEBUG_WALL_DATE="2026-11-25T10:00:00Z")
        mode = {1: "none", 2: "msaa2", 4: "msaa4"}[samples]
        command = [str(self.exe), "--mwx-debug-scene-root", str(content),
                   "--mwx-debug-scene-evidence-dir", str(evidence), "--mwx-debug-scene-duration", "7",
                   "--mwx-debug-scene-after-snapshot-delay", "3.25", "--mwx-debug-scene-audio-silence-fixture",
                   "--mwx-debug-scene-performance-warmup", "1",
                   "--mwx-debug-scene-presentation-diagnostics",
                   "-mwx.playback.quality",
                   f"{{ sceneAntiAliasingMode = {mode}; }}"]
        log_file = folder / "app.log"
        with log_file.open("w") as sink:
            process = subprocess.run(command, env=environment, stdout=sink, stderr=subprocess.STDOUT, timeout=90)
        log = log_file.read_text()
        self.assertEqual(process.returncode, 0, log[-4500:])
        self.assertIn("gpuDrained=true", log)
        self.assertFalse(METAL_FAILURE.findall(log))
        presented = re.findall(r"phase=performance [^\n]+?\bpresented=(\d+)", log)
        self.assertTrue(presented, log[-4500:])
        if requires_presentation:
            self.assertGreater(int(presented[-1]), 0, log[-4500:])
        observation = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
        self.assertEqual(observation["parse_errors"], 0)
        capture = terminal_snapshot_metrics(evidence, log)
        receipt = terminal_composition_snapshot(capture, observation)
        self.assertTrue(receipt["composition_receipt_matched"], receipt)
        event, = [frame for frame in observation["events"] if frame["captureRequestID"] == capture["request_id"]
                  and frame["commandBufferToken"] == capture["command_buffer_token"]]
        self.assertTrue(event["presentRequested"], event)
        self.assertEqual(event["gpuStatus"], "completed", event)
        self.assertEqual(event["truncatedRows"], 0, event)
        self.assertEqual((capture["source_width"], capture["source_height"]),
                         (capture["output_width"], capture["output_height"]))
        (folder / "receipt.json").write_text(json.dumps({"presentedWindowFrames": int(presented[-1]),
                                                        "capture": receipt, "frame": event}, indent=2) + "\n")
        with Image.open(capture["path"]) as image:
            return image.convert("RGB"), event["rows"]

    def comparison(self, name, *, requires_presentation=True):
        entries, model_ids = model_input(name)
        folder = self.work / name
        content = folder / "input"
        content.mkdir(parents=True)
        project, package = content / "project.json", content / "scene.pkg"
        project.write_text(json.dumps({"type": "scene", "file": "scene.json"}))
        package.write_bytes(make_package(list(entries.items())))
        before = (sha256(project), sha256(package))
        arms = [(samples, self.run_arm(folder / f"requested-{samples}", content, samples,
                                      requires_presentation=requires_presentation))
                for samples in (1, 2, 4)]
        self.assertEqual((sha256(project), sha256(package)), before)
        self.assertEqual(len({image.size for _, (image, _) in arms}), 1)
        return arms, model_ids

    def assert_model_pass(self, rows, expected_samples, model_ids, *, mixed=False):
        openings = [row for row in rows if row["kind"] == "main-raster-open"]
        mixed_single_sample = mixed and expected_samples == 1
        if mixed_single_sample:
            first, opening, last = openings
            self.assertEqual([row["details"]["sampleCount"] for row in openings], ["1", "1", "1"])
            self.assertEqual([row["details"]["colorLoad"] for row in openings], ["2", "1", "1"])
            self.assertTrue(all("depthSamples" not in row["details"] for row in (first, last)))
        else:
            opening, = openings
        self.assertEqual(opening["details"]["sampleCount"], str(expected_samples), opening)
        self.assertEqual(opening["details"]["depthSamples"], str(expected_samples), opening)
        self.assertEqual(opening["details"]["depthClear"], "0.0", opening)
        self.assertEqual(opening["details"]["colorLoad"], "1" if mixed_single_sample else "2", opening)
        multisampled = expected_samples > 1
        self.assertEqual(opening["details"]["colorStore"], "2" if multisampled else "1", opening)
        self.assertEqual(opening["details"]["depthStore"], "0" if multisampled else "1", opening)
        if multisampled:
            source, target = opening["source"], opening["target"]
            self.assertEqual(source["role"], "multisample-color")
            self.assertNotEqual(source["textureToken"], target["textureToken"])
            self.assertEqual([source[k] for k in ("width", "height", "pixelFormat")],
                             [target[k] for k in ("width", "height", "pixelFormat")])
        draws = [(index, row) for index, row in enumerate(rows) if row["kind"] == "model"]
        self.assertEqual([row["layerID"] for _, row in draws], model_ids)
        for index, row in draws:
            self.assertGreater(index, rows.index(opening))
            self.assertEqual(row["target"]["textureToken"], opening["target"]["textureToken"])
            additive = row["layerID"] == ADDITIVE_LAYER
            self.assertEqual(row["details"]["blending"], "additive" if additive else "normal", row)
            self.assertEqual((row["details"]["depthTest"], row["details"]["depthWrite"]),
                             ("true", "false" if additive else "true"), row)
            self.assertEqual(row["outcome"], "draw-encoded")
        seal, = [index for index, row in enumerate(rows) if row["kind"] == "frame-seal"]
        self.assertLess(draws[-1][0], seal)
        if mixed:
            self.assert_mixed_draw_order(rows, openings, model_ids, seal)
        return draws[-1][0], seal

    def assert_mixed_draw_order(self, rows, openings, model_ids, seal):
        draws = [(index, row) for index, row in enumerate(rows) if row["kind"] in {"ordinary", "model"}]
        self.assertFalse(any(row["kind"] == "geometry" and row.get("layerID") == UNPREPARED_SPOT_LAYER
                             for row in rows))
        self.assertEqual([(row["layerID"], row["kind"]) for _, row in draws],
                         [(BACKGROUND_LAYER, "ordinary"), *((layer, "model") for layer in model_ids),
                          (ALPHA_LAYER, "ordinary"), (TEXT_LAYER, "ordinary")])
        token = rows[seal]["target"]["textureToken"]
        self.assertTrue(all(row["target"]["textureToken"] == token for row in openings))
        for index, row in draws:
            self.assertEqual(row["outcome"], "draw-encoded", row)
            self.assertEqual(row["target"]["textureToken"], token)
            self.assertTrue(rows.index(openings[0]) < index < seal)
        self.assertEqual([row["details"]["contentKind"] for _, row in draws if row["kind"] == "ordinary"],
                         ["solid", "image", "text"])
        if len(openings) == 3:
            self.assertTrue(draws[0][0] < rows.index(openings[1]) < draws[1][0])
            self.assertTrue(draws[-3][0] < rows.index(openings[2]) < draws[-2][0])

    def assert_color(self, image, location, expected):
        x, y = MODEL_ROIS[location] if isinstance(location, str) else location
        pixels = image.crop(canvas_box(image, x - 1, y - 1, x + 1, y + 1)).getcolors()
        self.assertTrue(pixels and all(max(abs(a - b) for a, b in zip(color, expected)) <= 2
                                       for _, color in pixels), (location, pixels))

    def test_model_only_resolves_a_sloped_edge_and_both_depth_orders(self):
        self.check_model_resolve("plain")

    def test_renamed_model_keeps_hdr_terminal_output(self):
        self.check_model_resolve("renamed-hdr")

    def test_plain_color_and_text_share_the_resolved_model_pass(self):
        self.check_model_resolve("suffix")

    def check_model_resolve(self, name):
        arms, model_ids = self.comparison(name)
        edge_count = []
        text_count = []
        mixed = name == "suffix"
        for samples, (image, rows) in arms:
            last_draw, seal = self.assert_model_pass(rows, samples, model_ids, mixed=mixed)
            if name == "renamed-hdr":
                self.assertTrue(any(row["kind"] == "export" and row["outcome"] == "exported"
                                    for row in rows[last_draw + 1:seal]), rows)
            for label, expected in (("grazing", (255, 0, 0)), ("front", (255, 0, 0)),
                                    ("opaquePeer", (0, 255, 0))):
                self.assert_color(image, label, expected)
            self.assert_color(image, "unoccludedBlue", (128, 0, 127) if mixed else (0, 0, 255))
            if mixed:
                self.assert_color(image, (108, 48), (128, 0, 32))
                self.assert_color(image, (110, 20), (0, 0, 64))
                text = image.crop(canvas_box(image, 101, 62, 149, 92)).getcolors(100_000)
                text_count.append(sum(count for count, rgb in text if min(rgb) >= 224))
            if name == "plain":
                self.assert_color(image, (80, 44.5), (255, 0, 255))
            box = canvas_box(image, 34, 59, 63, 81)
            edge_count.append(sum(count for count, (r, g, b) in image.crop(box).getcolors(100_000)
                                  if r <= 2 and b <= (66 if mixed else 2) and 32 <= g <= 224))
        self.assertEqual(edge_count[0], 0, edge_count)
        for count in edge_count[1:]:
            self.assertGreater(count, 24, edge_count)
            self.assertLess(count, 3 * sum(arms[0][1][0].size), edge_count)
        (self.work / name / "edge-pixels.json").write_text(json.dumps(edge_count) + "\n")
        if mixed:
            self.assertGreater(min(text_count), 24, text_count)
            for count in text_count[1:]:
                self.assertAlmostEqual(count, text_count[0], delta=0.05 * text_count[0])
            (self.work / name / "glyph-pixels.json").write_text(json.dumps(text_count) + "\n")

    def test_additive_reflection_preserves_underlying_color_with_native_samples(self):
        arms, _ = self.comparison("additive-reflection")
        baseline = None
        for samples, (image, rows) in arms:
            with self.subTest(samples=samples):
                reflector, = [row for row in rows if row["kind"] == "model-reflection" and row["layerID"] == 10]
                root = next(row for row in reversed(rows[:rows.index(reflector)]) if row["kind"] == "main-raster-open")
                self.assertEqual((root["details"]["sampleCount"], root["details"]["depthSamples"]),
                                 (str(samples), str(samples)))
                self.assertEqual(reflector["slot"], 6)
                self.assertEqual(reflector["target"]["textureToken"], root["target"]["textureToken"])
                x, y = MODEL_ROIS["grazing"]
                color = image.crop(canvas_box(image, x - 1, y - 1, x + 1, y + 1)).getpixel((0, 0))
                self.assertGreater(color[0], 10)
                self.assertAlmostEqual(color[1], 64, delta=2)
                self.assertLessEqual(color[2], 2)
                if baseline is None:
                    baseline = color
                self.assert_color(image, "grazing", baseline)

    def test_plain_translucent_writer_shares_the_native_camera_depth(self):
        regions = {
            "near-model": {"world": [.30, .16, 0], "expectedRGB": ORANGE},
            "exposed-image": {"world": [.36, -.55, 0], "expectedRGB": DEPTH_CARD_COLORS[1]},
            "transparent-hole": {"world": [0, -.55, 0], "expectedRGB": (0, 0, 0)},
            "far-model-through-hole": {"world": [0, -.35, 0], "expectedRGB": GREEN},
            "partial-alpha": {"world": [-.36, -.55, 0],
                "expectedRGB": tuple(round(channel * 128 / 255) for channel in DEPTH_CARD_COLORS[1])},
        }
        for name, writer_id in (("shared-depth", 21), ("shared-depth-renamed", 121)):
            with self.subTest(variant=name):
                arms, model_ids = self.comparison(name)
                baseline = arms[0][1][0]
                for samples, (image, rows) in arms:
                    self.assert_model_pass(rows, samples, model_ids)
                    writer, = [row for row in rows if row["kind"] == "ordinary" and row.get("layerID") == writer_id]
                    near, far = [row for row in rows if row["kind"] == "model"]
                    self.assertEqual(writer["outcome"], "draw-encoded")
                    self.assertEqual(writer["target"]["textureToken"], near["target"]["textureToken"])
                    self.assertTrue(rows.index(near) < rows.index(writer) < rows.index(far))
                    if samples > 1:
                        self.assertIsNotNone(ImageChops.difference(image, baseline).getbbox())
                    capture = self.work / name / f"requested-{samples}/evidence/scene-after-window.png"
                    measured = measure_capture(capture, regions)
                    for region, record in regions.items():
                        self.assertGreater(measured[region]["count"], 0)
                        for actual, expected in zip(measured[region]["mean"], record["expectedRGB"], strict=True):
                            self.assertAlmostEqual(actual, expected, delta=2, msg=(name, samples, region))

    def test_color_prefix_keeps_its_authored_read_and_real_model_samples(self):
        arms, _ = self.comparison("color-prefix")
        for samples, (image, rows) in arms:
            with self.subTest(samples=samples):
                self.assert_color(image, (120, 48), (0, 0, 255))
                openings = [row for row in rows if row["kind"] == "main-raster-open"]
                root = openings[0]["target"]["textureToken"]
                reader = next(i for i, row in enumerate(rows) if row.get("layerID") == 87
                              and row.get("source", {}).get("textureToken") == root
                              and row["access"] in {"texture-bind", "color-attachment-read", "copy-source"})
                first_model = next(i for i, row in enumerate(rows)
                                   if row["kind"] == "model" and row["outcome"] == "draw-encoded")
                writeback = next(i for i, row in enumerate(rows) if row.get("layerID") == 87
                                 and row["kind"] == "group" and row["outcome"] == "draw-encoded"
                                 and row["target"]["textureToken"] == root)
                self.assertLess(reader, writeback)
                self.assertLess(writeback, first_model)
                snapshots = [row for row in rows if row["kind"] == "msaa-prefix-snapshot"]
                if samples == 1:
                    self.assertFalse(snapshots)
                    self.assertTrue(all(row["details"]["sampleCount"] == "1" for row in openings))
                    continue
                snapshot, = snapshots
                native, = [row for row in openings if row["details"]["sampleCount"] != "1"]
                self.assertLess(writeback, rows.index(snapshot))
                self.assertLess(rows.index(snapshot), rows.index(native))
                self.assertLess(rows.index(native), first_model)
                self.assertEqual(snapshot["source"]["textureToken"], root)
                self.assertNotEqual(snapshot["target"]["textureToken"], root)
                self.assertEqual(native["target"]["textureToken"], root)
                self.assertEqual(native["details"]["sampleCount"], str(samples))
                self.assertEqual(native["details"]["depthSamples"], str(samples))
                self.assertEqual(native["details"]["depthClear"], "0.0")

    def test_local_graph_reuses_native_depth_before_the_single_sample_root_reader(self):
        arms, model_ids = self.comparison("local-then-root-tail", requires_presentation=False)
        for samples, (_, rows) in arms:
            openings = [row for row in rows if row["kind"] == "main-raster-open"]
            root = openings[0]["target"]["textureToken"]
            models = [row for row in rows if row["kind"] == "model"]
            self.assertEqual([row["layerID"] for row in models], model_ids)
            local, = [row for row in rows if row["kind"] == "ordinary" and row.get("layerID") == 21]
            source, = [row for row in rows if row["kind"] == "sourceCapture" and row.get("layerID") == 21]
            read, = [row for row in rows if row["kind"] == "sourceCapture" and row.get("layerID") == 87]
            self.assertNotEqual(source["source"]["textureToken"], root)
            self.assertEqual(local["target"]["textureToken"], root)
            self.assertEqual(read["source"]["textureToken"], root)
            self.assertTrue(rows.index(models[0]) < rows.index(local) < rows.index(models[-1]) < rows.index(read))
            if samples == 1:
                self.assertTrue(all(row["details"]["sampleCount"] == "1" for row in openings))
                self.assertGreater(rows.index(source), rows.index(models[0]))
                continue
            native, tail = openings
            self.assertLess(rows.index(source), rows.index(native))
            self.assertEqual(native["details"]["sampleCount"], str(samples))
            self.assertEqual(native["details"]["depthSamples"], str(samples))
            self.assertEqual(tail["target"]["textureToken"], root)
            self.assertEqual((tail["details"]["sampleCount"], tail["details"]["colorLoad"]), ("1", "1"))
            self.assertNotIn("depthSamples", tail["details"])
            self.assertLess(rows.index(read), rows.index(tail))

    def test_root_read_followed_by_a_depth_consumer_preserves_single_sample(self):
        arms, _ = self.comparison("root-read-before-model", requires_presentation=False)
        baseline = arms[0][1][0].tobytes()
        for _, (image, rows) in arms:
            self.assertEqual(image.tobytes(), baseline)
            openings = [row for row in rows if row["kind"] == "main-raster-open"]
            self.assertTrue(openings and all(row["details"]["sampleCount"] == "1" for row in openings))
            reader = next(row for row in rows if row["kind"] == "sourceCapture" and row.get("layerID") == 87)
            model = next(row for row in rows if row["kind"] == "model" and row.get("layerID") == 30)
            self.assertLess(rows.index(reader), rows.index(model))

    def test_authored_consumers_preserve_the_original_single_sample_output(self):
        for name in ("color-blend", "current-color", "named", "history"):
            with self.subTest(case=name):
                arms, _ = self.comparison(name)
                baseline = arms[0][1][0].tobytes()
                for _, (image, rows) in arms:
                    self.assertEqual(image.tobytes(), baseline)
                    openings = [row for row in rows if row["kind"] == "main-raster-open"]
                    self.assertTrue(openings and all(row["details"]["sampleCount"] == "1" for row in openings))
                    if name == "color-blend":
                        blend, = [row for row in rows if row["kind"] == "color-blend-background"
                                  and row.get("layerID") == ALPHA_LAYER and row["outcome"] == "draw-encoded"]
                        token = openings[0]["target"]["textureToken"]
                        self.assertEqual(blend["target"]["textureToken"], token)
                        if blend.get("access") == "color-attachment-read":
                            self.assertEqual(blend["source"]["textureToken"], token)
                        else:
                            self.assertTrue(any(row["kind"] == "background-copy"
                                and row.get("layerID") == ALPHA_LAYER and row["outcome"] == "encoded"
                                and row["source"]["textureToken"] == token
                                and row["target"]["textureToken"] == blend["source"]["textureToken"] for row in rows))
                    elif name == "current-color":
                        token = openings[0]["target"]["textureToken"]
                        self.assertTrue(any(row.get("layerID") == 87
                                            and row.get("source", {}).get("textureToken") == token
                                            and row["access"] in {"texture-bind", "color-attachment-read", "copy-source"}
                                            for row in rows), rows)
                    elif name == "named":
                        self.assertTrue(any(row["kind"] == "material" and row.get("layerID") == 50
                                            and row.get("slot") == 1 and row["outcome"] == "draw-encoded"
                                            and "providerLayerID: 31" in row.get("source", {}).get("logical", "")
                                            for row in rows), rows)
                    elif name == "history":
                        self.assertEqual(openings[0]["details"]["colorLoad"], "1")
                        self.assertTrue(any(row["kind"] == "scene-color-copy" and row["outcome"] == "encoded"
                                            for row in rows), rows)
