"""Prepared static model/image cohorts reach real same-window Metal pixels.

Static show/hide controls supply independent visual references. All MDL, PNG,
material and scene bytes are owned fixtures; this does not establish official
model/shadow parity, animated model support or named-provider readiness.
"""
from pathlib import Path
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import unittest

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_composition_authored_order_integration import encoded
from .test_scene_directional_shadow_integration import fixture_entries as shadow_fixture, png, quad
from .test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from .test_scene_pkg_cache_extractor import make_package


CANVAS = (160, 96)
TOLERANCE = 4
RECTS = {"shadow": (58, 46, 62, 50), "caster": (78, 46, 82, 50),
         "receiver": (138, 46, 142, 50), "ownFalse": (130, 46, 134, 50),
         "image": (36, 70, 44, 78), "peer": (132, 70, 140, 78)}
SOURCES = (Path(__file__), Path(__file__).with_name("test_scene_directional_shadow_integration.py"),
           Path(__file__).with_name("test_scene_static_model_reader.py"),
           Path(__file__).with_name("test_scene_pkg_cache_extractor.py"),
           Path(__file__).with_name("test_scene_fullscreen_visibility_integration.py"),
           Path(__file__).with_name("test_scene_composition_authored_order_integration.py"),
           Path(__file__).parents[1] / "web_benchmark_capture.py")


def fixture_entries(*, control=None, bad_model=False):
    # The existing owned fixture casts toward +X,+Z. Local caster X50..70
    # plus the ordinary parent's +20 produces world X70..90 and shadow X50..70.
    scene, entries = shadow_fixture(caster_x=50, parent_offset=20)
    caster = next(layer for layer in scene["objects"] if layer["id"] == 2)
    visibility = ({"user": {"name": "mode", "condition": "shown"}, "value": True}
                  if control is None else control)
    caster.update(name="Owned conditional model", visible=visibility)
    scene["objects"] += [
        {"id": 5, "name": "Owned model child remains individually false", "parent": 6,
         "model": "models/own_false.mdl", "origin": "0 96 0", "perspective": False,
         "visible": False, "castshadow": True},
        {"id": 9, "name": "Independent black image plate", "image": "models/own_solid.json",
         "origin": "40 24 0", "size": "20 20", "color": "0 0 0"},
        {"id": 10, "name": "Owned ordinary image in the same combo cohort",
         "image": "models/own_blue.json", "origin": "40 24 0", "size": "16 16",
         "visible": visibility},
        {"id": 30, "name": "Independent healthy green peer", "image": "models/own_solid.json",
         "origin": "136 24 0", "size": "16 16", "color": "0 1 0"}]
    entries.update({
        "models/own_false.mdl": quad(104, 120, 38, 58, 30, "materials/own_red.json"),
        "materials/own_red.json": encoded({"passes": [{"shader": "genericimage",
            "textures": ["materials/own_red.png"], "combos": {"LIGHTING": 0},
            "blending": "normal", "cullmode": "nocull", "depthtest": "enabled", "depthwrite": "enabled"}]}),
        "materials/own_red.png": png([255, 0, 0, 255]),
        "models/own_solid.json": encoded({"solidlayer": True, "width": 160, "height": 96}),
        "models/own_blue.json": encoded({"material": "materials/own_blue.json"}),
        "materials/own_blue.json": encoded({"passes": [{"shader": "genericimage", "textures": ["materials/own_blue.png"]}]}),
        "materials/own_blue.png": png([0, 0, 255, 255])})
    if bad_model:
        entries["models/caster.mdl"] = b"OWNED_INVALID_MDL\x00"
    entries["scene.json"] = encoded(scene)
    project = {"type": "scene", "file": "scene.json", "general": {"properties": {
        "mode": {"type": "combo", "value": "shown", "options": [
            {"label": value, "value": value} for value in ("hidden", "shown")]}}}}
    return project, entries


def measure(path):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"invalid PNG: {path}")
    width, height, rows = decoded
    scale = max(width / CANVAS[0], height / CANVAS[1])
    def point(x, y):
        return ((x - CANVAS[0] / 2) * scale + width / 2,
                (y - CANVAS[1] / 2) * scale + height / 2)
    rois = {}
    for name, rect in RECTS.items():
        left, top = point(*rect[:2]); right, bottom = point(*rect[2:])
        if not (0 <= left < right <= width and 0 <= top < bottom <= height):
            raise AssertionError(f"preregistered ROI cropped: {name}, {(width, height)}")
        colors = [tuple(rows[y][x * 3:x * 3 + 3]) for y in range(math.ceil(top), math.floor(bottom))
                  for x in range(math.ceil(left), math.floor(right))]
        if not colors:
            raise AssertionError(f"empty ROI: {name}")
        expected = (0, 255, 0) if name == "peer" else None
        rois[name] = {"mean": [sum(rgb[c] for rgb in colors) / len(colors) for c in range(3)],
                      "total": len(colors), "greenFraction": sum(
                          max(abs(a - b) for a, b in zip(rgb, expected)) <= TOLERANCE
                          for rgb in colors) / len(colors) if expected else None}
    red_count = sum(row[x] >= 251 and row[x + 1] <= 4 and row[x + 2] <= 4
                    for row in rows for x in range(0, width * 3, 3))
    return {"dimensions": [width, height], "rois": rois, "redCount": red_count}


class SceneModelVisibilityIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        app = Path(configured).resolve(strict=True)
        cls.app = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app
        cls.frozen_app_hashes = app_hashes(cls.app)
        cls.frozen_source_hashes = file_hashes(SOURCES)
        cls.controls = None

    def run_scene(self, label, *, control=None, bad_model=False):
        sequence = [] if control is not None else ([{"mode": "shown"}, {"mode": "hidden"}]
                    if bad_model else [{"mode": "shown"}, {"mode": "hidden"}, {"mode": "shown"}])
        after = 2 if control is not None else 2 * len(sequence) + 2
        snapshots = {"scene-ready-window.png": bool(control)}
        for index in range(len(sequence)):
            name = ("scene-after-window.png" if index == len(sequence) - 1
                    else f"scene-series-{2 + index * 2:04d}-window.png")
            snapshots[name] = not bad_model and sequence[index]["mode"] == "shown"
        snapshots.setdefault("scene-after-window.png", bool(control))
        accepted = ["false" if bad_model else "true"] * len(sequence)
        protocol = {"canvas": CANVAS, "rectangles": RECTS, "tolerance": TOLERANCE,
            "initialMode": "shown" if control else "hidden", "staticControl": control,
            "sequenceEvery2Seconds": sequence, "acceptedSteps": accepted,
            "snapshotShown": snapshots, "badModel": bad_model, "parentOffset": [20, 0, 0],
            "snapshotTimesSeconds": {name: after if name == "scene-after-window.png" else 1
                                     if name == "scene-ready-window.png" else 1.5 + int(name.split("-")[2])
                                     for name in snapshots},
            "ownFalseModelLayerID": 5, "expectedRedPixels": 0, "peerRGB": [0, 255, 0],
            "imageShownRGB": [0, 0, 255], "imageHiddenRGB": [0, 0, 0],
            "shadowOracle": "show: ambient survives and shadow <30% of unoccluded receiver; hide: receiver restored",
            "comparisonOracle": "same geometry with authored literal visibility, every ROI mean within 4 channels",
            "evidenceBoundary": "owned static model/image cohort, no official pixel parity"}
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        self.assertEqual(file_hashes(SOURCES), self.frozen_source_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-model-visibility-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir(); home.mkdir()
            project, entries = fixture_entries(control=control, bad_model=bad_model)
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            inputs = (content / "project.json", content / "scene.pkg")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                "--mwx-debug-scene-duration", str(after + 2), "--mwx-debug-scene-evidence-dir", str(evidence),
                "--mwx-debug-scene-after-snapshot-delay", str(after),
                "--mwx-debug-scene-properties-json", json.dumps({"mode": protocol["initialMode"]})]
            if sequence:
                command += ["--mwx-debug-scene-live-property-sequence-json", json.dumps(sequence),
                            "--mwx-debug-scene-periodic-snapshot-interval", "1"]
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                "sourceSHA256": self.frozen_source_hashes, "inputSHA256": file_hashes(inputs),
                "entrySHA256": {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}}
            (root / "prerun.json").write_bytes(encoded(identity))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            (root / "scene-input.json").write_bytes(entries["scene.json"])
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                for name in snapshots:
                    self.assertTrue((evidence / name).is_file(), (name, log[-6000:]))
                    pixels[name] = measure(evidence / name)
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertEqual(re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log),
                                 [(str(i), value) for i, value in enumerate(accepted)], log[-6000:])
                updates = re.findall(r"phase=live-property-update accepted=(true|false) surfacesBefore=(\d+) surfacesAfter=(\d+) windowsBefore=(\S+) windowsAfter=(\S+)", log)
                self.assertEqual([row[0] for row in updates], accepted)
                self.assertTrue(all(row[1] == row[2] == "1" and row[3] == row[4] for row in updates), updates)
                self.assertEqual(log.count("phase=session-candidate "), 1)
                self.assertEqual(log.count("phase=session-activated "), 1)
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                self.assertNotRegex(log, r"phase=launch-failed|phase=snapshot-(?:failed|rejected)|failure=exception")
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                prepared = re.search(r"prepared static model layers: \[([^\]]*)\]", preview)
                self.assertIsNotNone(prepared, preview[-3000:])
                self.assertEqual({int(value.strip()) for value in prepared[1].split(",") if value.strip()},
                                 {1, 5} if bad_model else {1, 2, 5})
                for name, measurement in pixels.items():
                    reason = name.removeprefix("scene-").removesuffix("-window.png")
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                    self.assertEqual(measurement["redCount"], 0, (name, measurement))
                    self.assertGreaterEqual(measurement["rois"]["peer"]["greenFraction"], .99)
                    expected = [0, 0, 255] if snapshots[name] else [0, 0, 0]
                    for actual, wanted in zip(measurement["rois"]["image"]["mean"], expected):
                        self.assertAlmostEqual(actual, wanted, delta=TOLERANCE, msg=name)
                if control is not None:
                    for roi in RECTS:
                        for ready, later in zip(pixels["scene-ready-window.png"]["rois"][roi]["mean"],
                                                pixels["scene-after-window.png"]["rois"][roi]["mean"]):
                            self.assertAlmostEqual(ready, later, delta=TOLERANCE, msg=f"static control: {roi}")
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                self.assertEqual(file_hashes(inputs), identity["inputSHA256"])
                self.assertEqual(file_hashes(SOURCES), self.frozen_source_hashes)
                return pixels, snapshots
            except subprocess.TimeoutExpired as error:
                log = "".join(value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                              for value in (error.stdout, error.stderr))
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity.update(appSHA256After=app_hashes(self.app), inputSHA256After=file_hashes(inputs),
                                sourceSHA256After=file_hashes(SOURCES))
                (root / "identity.json").write_bytes(encoded(identity))
                (root / "pixels.json").write_bytes(encoded(pixels))
                (root / "app.log").write_text(log)
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName / label
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")

    def static_controls(self):
        if self.controls is None:
            self.__class__.controls = {shown: self.run_scene("control-shown" if shown else "control-hidden",
                control=shown)[0]["scene-ready-window.png"] for shown in (False, True)}
        hidden, shown = self.controls[False]["rois"], self.controls[True]["rois"]
        self.assertGreater(min(hidden["receiver"]["mean"]), 50)
        for channel in range(3):
            self.assertAlmostEqual(hidden["caster"]["mean"][channel], hidden["receiver"]["mean"][channel], delta=TOLERANCE)
            self.assertAlmostEqual(hidden["shadow"]["mean"][channel], hidden["receiver"]["mean"][channel], delta=TOLERANCE)
            for control in (hidden, shown):
                self.assertAlmostEqual(control["ownFalse"]["mean"][channel], control["receiver"]["mean"][channel], delta=TOLERANCE)
            self.assertAlmostEqual(shown["receiver"]["mean"][channel], hidden["receiver"]["mean"][channel], delta=TOLERANCE)
            self.assertGreater(shown["shadow"]["mean"][channel], 2)
            self.assertLess(shown["shadow"]["mean"][channel], hidden["shadow"]["mean"][channel] * .3)
        green = shown["caster"]["mean"]
        self.assertGreater(green[1], max(green[0], green[2]) + 20)
        return self.controls

    def compare_controls(self, pixels, snapshots):
        controls = self.static_controls()
        for name, shown in snapshots.items():
            self.assertEqual(pixels[name]["dimensions"], controls[shown]["dimensions"])
            for roi in RECTS:
                for actual, expected in zip(pixels[name]["rois"][roi]["mean"], controls[shown]["rois"][roi]["mean"]):
                    self.assertAlmostEqual(actual, expected, delta=TOLERANCE, msg=f"{name}: {roi}")

    def test_initially_hidden_model_and_image_show_hide_show_without_depth_or_shadow_ghosts(self):
        self.static_controls()
        self.compare_controls(*self.run_scene("live-cycle"))

    def test_unprepared_model_rejects_the_whole_combo_and_keeps_the_image_hidden(self):
        self.static_controls()
        self.compare_controls(*self.run_scene("bad-model", bad_model=True))
