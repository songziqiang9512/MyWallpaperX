#!/usr/bin/env python3
"""Compare actual 1× and 2× root model raster output in one signed Debug App."""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from script.scene.scene_wallpaper_graph_output_metrics import (
    structured_runtime_observations,
    terminal_composition_snapshot,
    terminal_snapshot_metrics,
)
from script.tests.scene.test_scene_composition_authored_order_integration import fixture_entries as composition_fixture
from script.tests.scene.test_scene_directional_shadow_integration import quad
from script.tests.scene.test_scene_named_model_shadow import named_fixture
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


def model_input(variant):
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
    elif variant == "suffix":
        scene["objects"].append(suffix)
    elif variant == "current-color":
        _, readers = composition_fixture(copy_background=True, childless=True)
        _, consumer = json.loads(readers.pop("scene.json"))["objects"]
        consumer.update(id=87, origin="80 48 0", size="160 96")
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
            raise AssertionError("signed App changed between the 1× and 2× observations")

    def run_arm(self, folder, content, samples):
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
        command = [str(self.exe), "--mwx-debug-scene-root", str(content),
                   "--mwx-debug-scene-evidence-dir", str(evidence), "--mwx-debug-scene-duration", "7",
                   "--mwx-debug-scene-after-snapshot-delay", "3.25", "--mwx-debug-scene-audio-silence-fixture",
                   "--mwx-debug-scene-performance-warmup", "1",
                   "-mwx.playback.quality",
                   f"{{ sceneAntiAliasingMode = {'msaa2' if samples == 2 else 'none'}; }}"]
        log_file = folder / "app.log"
        with log_file.open("w") as sink:
            process = subprocess.run(command, env=environment, stdout=sink, stderr=subprocess.STDOUT, timeout=90)
        log = log_file.read_text()
        self.assertEqual(process.returncode, 0, log[-4500:])
        self.assertIn("gpuDrained=true", log)
        self.assertFalse(METAL_FAILURE.findall(log))
        presented = re.findall(r"phase=performance [^\n]+?\bpresented=(\d+)", log)
        self.assertTrue(presented and int(presented[-1]) > 0, log[-4500:])
        observation = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
        self.assertEqual(observation["parse_errors"], 0)
        capture = terminal_snapshot_metrics(evidence, log)
        receipt = terminal_composition_snapshot(capture, observation)
        self.assertTrue(receipt["composition_receipt_matched"], receipt)
        event, = [frame for frame in observation["events"] if frame["captureRequestID"] == capture["request_id"]
                  and frame["commandBufferToken"] == capture["command_buffer_token"]]
        self.assertTrue(event["presentRequested"], event)
        self.assertEqual(event["truncatedRows"], 0, event)
        self.assertEqual((capture["source_width"], capture["source_height"]),
                         (capture["output_width"], capture["output_height"]))
        (folder / "receipt.json").write_text(json.dumps({"presentedWindowFrames": int(presented[-1]),
                                                        "capture": receipt, "frame": event}, indent=2) + "\n")
        with Image.open(capture["path"]) as image:
            return image.convert("RGB"), event["rows"]

    def comparison(self, name):
        entries, model_ids = model_input(name)
        folder = self.work / name
        content = folder / "input"
        content.mkdir(parents=True)
        project, package = content / "project.json", content / "scene.pkg"
        project.write_text(json.dumps({"type": "scene", "file": "scene.json"}))
        package.write_bytes(make_package(list(entries.items())))
        before = (sha256(project), sha256(package))
        baseline = self.run_arm(folder / "requested-1", content, 1)
        experiment = self.run_arm(folder / "requested-2", content, 2)
        self.assertEqual((sha256(project), sha256(package)), before)
        self.assertEqual(baseline[0].size, experiment[0].size)
        return baseline, experiment, model_ids

    def assert_model_pass(self, rows, expected_samples, model_ids):
        opening, = [row for row in rows if row["kind"] == "main-raster-open"]
        self.assertEqual(opening["details"]["sampleCount"], str(expected_samples), opening)
        self.assertEqual(opening["details"]["depthSamples"], str(expected_samples), opening)
        self.assertEqual(opening["details"]["depthClear"], "0.0", opening)
        self.assertEqual(opening["details"]["colorLoad"], "2", opening)
        self.assertEqual(opening["details"]["colorStore"], str(expected_samples), opening)
        self.assertEqual(opening["details"]["depthStore"], "0" if expected_samples == 2 else "1", opening)
        if expected_samples == 2:
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
        return draws[-1][0], seal

    def assert_color(self, image, location, expected):
        x, y = MODEL_ROIS[location] if isinstance(location, str) else location
        pixels = image.crop(canvas_box(image, x - 1, y - 1, x + 1, y + 1)).getcolors()
        self.assertTrue(pixels and all(max(abs(a - b) for a, b in zip(color, expected)) <= 2
                                       for _, color in pixels), (location, pixels))

    def test_model_only_resolves_a_sloped_edge_and_both_depth_orders(self):
        self.check_model_resolve("plain")

    def test_renamed_model_keeps_hdr_terminal_output(self):
        self.check_model_resolve("renamed-hdr")

    def check_model_resolve(self, name):
        baseline, experiment, model_ids = self.comparison(name)
        edge_count = []
        for samples, (image, rows) in enumerate((baseline, experiment), 1):
            last_draw, seal = self.assert_model_pass(rows, samples, model_ids)
            if name == "renamed-hdr":
                self.assertTrue(any(row["kind"] == "export" and row["outcome"] == "exported"
                                    for row in rows[last_draw + 1:seal]), rows)
            for label, expected in (("grazing", (255, 0, 0)), ("front", (255, 0, 0)),
                                    ("unoccludedBlue", (0, 0, 255)), ("opaquePeer", (0, 255, 0))):
                self.assert_color(image, label, expected)
            if name == "plain":
                self.assert_color(image, (80, 44.5), (255, 0, 255))
            box = canvas_box(image, 34, 59, 63, 81)
            edge_count.append(sum(count for count, (r, g, b) in image.crop(box).getcolors(100_000)
                                  if max(r, b) <= 2 and 32 <= g <= 224))
        self.assertEqual(edge_count[0], 0, edge_count)
        self.assertGreater(edge_count[1], 24, edge_count)
        self.assertLess(edge_count[1], 3 * sum(experiment[0].size), edge_count)
        (self.work / name / "edge-pixels.json").write_text(json.dumps(edge_count) + "\n")

    def test_authored_consumers_preserve_the_original_single_sample_output(self):
        for name in ("suffix", "current-color", "named", "history"):
            with self.subTest(case=name):
                baseline, experiment, _ = self.comparison(name)
                self.assertEqual(baseline[0].tobytes(), experiment[0].tobytes())
                for _, rows in (baseline, experiment):
                    openings = [row for row in rows if row["kind"] == "main-raster-open"]
                    self.assertTrue(openings and all(row["details"]["sampleCount"] == "1" for row in openings))
                    if name == "suffix":
                        self.assertEqual(len(openings), 2, openings)
                        self.assertTrue(any(row["kind"] == "ordinary" and row.get("layerID") == 30 for row in rows))
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
