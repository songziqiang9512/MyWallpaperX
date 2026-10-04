"""Prepared composition visibility reaches nested capture, text and App pixels.

Every resource is self-authored. Literal static controls supply the glyph oracle;
fixed colors separately distinguish the three dim stages and healthy outside peer.
This exercises fixed ordinary groups, not official font/effect pixel parity.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_composition_authored_order_integration import VERTEX, encoded, measure_capture
from .test_scene_fullscreen_visibility_integration import FRAGMENT, app_hashes, file_hashes, white_png
from .test_scene_pkg_cache_extractor import make_package


CLOCK = """export function update(value) {
    const minutes = Math.floor(engine.runtime / 60);
    const hours = Math.floor(minutes / 60);
    return ('00' + hours).slice(-2) + ':' + ('00' + (minutes % 60)).slice(-2);
}
"""
# Authored +Y is up; the plain card's world y=180 becomes screen-canvas y=76.
RECTS = {"effect": (52, 116, 76, 140), "plain": (52, 64, 76, 88),
         "peer": (180, 116, 204, 140)}
BLACK, GREEN = (0, 0, 0), (0, 255, 0)


def dim_effect(identifier):
    return {"id": identifier, "file": "effects/own_dim/effect.json", "visible": True}


def fixture_entries(*, initial=True, control=False):
    objects = [
        {"id": 10, "name": "Owned outer composition", "origin": "128 128 0",
         "image": "models/util/composelayer.json", "size": "256 256", "copybackground": False,
         "visible": initial if control else {"user": "group", "value": True},
         "effects": [dim_effect(100)]},
        {"id": 11, "name": "Owned nested composition", "parent": 10, "origin": "0 0 0",
         "image": "models/util/composelayer.json", "size": "256 256", "copybackground": False},
        {"id": 12, "name": "Owned elapsed clock", "parent": 11, "origin": "0 -56 0",
         "text": "00:00" if control else {"value": "OLD", "script": CLOCK},
         "font": "systemfont_arial", "pointsize": 8, "size": "140 40", "color": "1 1 1",
         "horizontalalign": "center", "verticalalign": "center", "padding": 0},
        {"id": 13, "name": "Owned independently dimmed image", "parent": 11,
         "image": "models/own_white.json", "origin": "-64 0 0", "size": "48 48",
         "effects": [dim_effect(130)]},
        {"id": 16, "name": "Owned plain nested image", "parent": 11,
         "image": "models/own_white.json", "origin": "-64 52 0", "size": "48 48"},
        # No children: this group dims the already drawn enclosing nested pass.
        {"id": 17, "name": "Owned childless background capture", "parent": 11, "origin": "0 0 0",
         "image": "models/util/composelayer.json", "size": "256 256", "copybackground": True,
         "effects": [dim_effect(170)]},
        {"id": 14, "name": "Owned child stays individually hidden", "parent": 10,
         "image": "models/own_solid.json", "origin": "0 0 0", "size": "24 24",
         "visible": False, "color": "1 0 0"},
        {"id": 15, "name": "Owned root text sibling", "parent": 10, "origin": "0 56 0",
         "text": "CHILD", "font": "systemfont_arial", "pointsize": 8, "size": "140 40",
         "color": "1 1 1", "horizontalalign": "center", "verticalalign": "center", "padding": 0},
        {"id": 30, "name": "Healthy green outside peer", "image": "models/own_solid.json",
         "origin": "192 128 0", "size": "48 48", "color": "0 1 0"}]
    project = {"type": "scene", "file": "scene.json", "general": {"properties": {
        "group": {"type": "bool", "value": True}}}}
    entries = {
        "scene.json": encoded({"version": 3, "general": {
            "orthogonalprojection": {"width": 256, "height": 256}, "clearcolor": "0 0 0"}, "objects": objects}),
        # Public utility type discriminator; its model bytes are also ours.
        "models/util/composelayer.json": encoded({"width": 256, "height": 256, "autosize": False}),
        "models/own_solid.json": encoded({"solidlayer": True, "width": 256, "height": 256}),
        "models/own_white.json": encoded({"material": "materials/own_white.json"}),
        "materials/own_white.json": encoded({"passes": [{"shader": "genericimage", "textures": ["materials/own_white.png"]}]}),
        "materials/own_white.png": white_png(),
        "effects/own_dim/effect.json": encoded({"passes": [{"material": "materials/own_dim.json"}]}),
        "materials/own_dim.json": encoded({"passes": [{"shader": "own_dim", "textures": [None],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
        "shaders/own_dim.vert": VERTEX, "shaders/own_dim.frag": FRAGMENT}
    return project, entries


def measure(path, shown):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"invalid capture: {path}")
    width, height, rows = decoded
    mask = bytearray(width * height)
    glyphs = red = 0
    scale = max(width / 256, height / 256)
    for y, row in enumerate(rows):
        for x in range(width):
            rgb = row[x * 3:x * 3 + 3]
            # Images and peer are outside this strip. Include dimmed text edges.
            if abs(x + .5 - width / 2) < 32 * scale and min(rgb) >= 8 and max(rgb) - min(rgb) <= 4:
                mask[y * width + x] = 1
                glyphs += 1
            red += rgb[0] >= 8 and rgb[1] <= 4 and rgb[2] <= 4
    colors = {"effect": (32, 32, 32), "plain": (64, 64, 64), "peer": GREEN}
    oracle = {name: {"canvasRect": rect, "expectedRGB": colors[name] if shown or name == "peer" else BLACK}
              for name, rect in RECTS.items()}
    result = measure_capture(path, {"oracle": oracle, "channelTolerance": 4})
    result.update(dimensions=[width, height], glyphCount=glyphs, redCount=red,
                  glyphMaskSHA256=hashlib.sha256(mask).hexdigest())
    return result


class SceneCompositionVisibilityIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires an explicitly frozen Debug executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def run_scene(self, *, initial, control=False):
        sequence = [] if control else ([{"group": False}, {"group": True}] if initial
                                       else [{"group": True}, {"group": False}, {"group": True}])
        snapshots = {"scene-ready-window.png": initial}
        if control:
            duration, after = 4, 2
            snapshots["scene-after-window.png"] = initial
        else:
            for index, update in enumerate(sequence):
                name = ("scene-after-window.png" if index == len(sequence) - 1
                        else f"scene-series-{2 + index * 2:04d}-window.png")
                snapshots[name] = update["group"]
            after = 2 * len(sequence) + 2
            duration = after + 2
        protocol = {"canvas": 256, "initialGroupVisible": initial, "literalStaticControl": control,
            "liveEvery2Seconds": sequence, "snapshotGroupVisible": snapshots,
            "snapshotTimesSeconds": {name: after if name == "scene-after-window.png" else 1 if name == "scene-ready-window.png"
                                     else 1.5 + int(name.split("-")[2]) for name in snapshots},
            "captureMapping": "centered orthographic cover, scale=max(width/256,height/256)",
            "rois": RECTS, "shownRGB": {"effect": [32, 32, 32], "plain": [64, 64, 64], "peer": GREEN},
            "hiddenRGB": BLACK, "channelTolerance": 4, "minimumCorrectFraction": .99,
            "dimStages": {"root": 10, "childlessNestedBackgroundCapture": 17, "image": 13},
            "copyBackground": {"10": False, "11": False, "17": True},
            "glyphOracle": "literal static 00:00 and CHILD controls, identical geometry; runtime below one minute",
            "glyphMaskCanvasX": [96, 160], "minimumGlyphGray": 8, "individuallyHiddenChild": 14,
            "redPixelMinimumR": 8, "expectedRedPixels": 0,
            "evidenceBoundary": "owned fixed composition hierarchy; no official pixel parity"}
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-composition-visibility-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir(); home.mkdir()
            project, entries = fixture_entries(initial=initial, control=control)
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            inputs = (content / "project.json", content / "scene.pkg")
            command = [str(self.app), "--mwx-debug-scene-root", str(content), "--mwx-debug-scene-duration", str(duration),
                "--mwx-debug-scene-evidence-dir", str(evidence), "--mwx-debug-scene-after-snapshot-delay", str(after),
                "--mwx-debug-scene-properties-json", json.dumps({"group": initial})]
            if sequence:
                command += ["--mwx-debug-scene-live-property-sequence-json", json.dumps(sequence),
                            "--mwx-debug-scene-periodic-snapshot-interval", "1"]
            env = os.environ.copy()
            for key in tuple(env):
                if key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_")):
                    env.pop(key)
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                "inputSHA256": file_hashes(inputs), "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "entrySHA256": {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}}
            (root / "prerun.json").write_bytes(encoded(identity))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                for name, shown in snapshots.items():
                    self.assertTrue((evidence / name).is_file(), (name, log[-5000:]))
                    pixels[name] = measure(evidence / name, shown)
                self.assertEqual(result.returncode, 0, log[-5000:])
                self.assertEqual(re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log),
                                 [(str(index), "true") for index in range(len(sequence))], log[-5000:])
                updates = re.findall(r"phase=live-property-update accepted=(true|false) surfacesBefore=(\d+) surfacesAfter=(\d+) windowsBefore=(\S+) windowsAfter=(\S+)", log)
                self.assertEqual(len(updates), len(sequence))
                self.assertTrue(all(value == "true" and before == after_count == "1" and old == new
                                    for value, before, after_count, old, new in updates), updates)
                self.assertEqual(log.count("phase=session-candidate "), 1)
                self.assertEqual(log.count("phase=session-activated "), 1)
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                self.assertNotRegex(log, r"failure=exception|phase=launch-failed|phase=snapshot-(?:failed|rejected)")
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                if initial or not control:
                    for layer_id in (10, 13, 17):
                        self.assertRegex(log + preview, rf"generic shader execution [^\n]*layer={layer_id} effect=0 ")
                if not control:
                    self.assertRegex(log, r"target=text\(layerID: 12,[^\n]*callback=completed inputUTF8Bytes=\d+ outputUTF8Bytes=5 route=generic-only")
                for name, value in pixels.items():
                    reason = name.removeprefix("scene-").removesuffix("-window.png")
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                    if snapshots[name]:
                        self.assertGreater(value["glyphCount"], 100)
                    else:
                        self.assertEqual(value["glyphCount"], 0)
                    self.assertEqual(value["redCount"], 0, value)
                    for roi in value["rois"].values():
                        self.assertGreater(roi["total"], 0)
                        self.assertGreaterEqual(roi["correct"] / roi["total"], .99, roi)
                        self.assertTrue(all(abs(a - b) <= 4 for a, b in zip(roi["centerRGB"], roi["expectedRGB"])), roi)
                self.assertEqual(file_hashes(inputs), identity["inputSHA256"])
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), identity["testSHA256"])
                return pixels, snapshots
            except subprocess.TimeoutExpired as error:
                log = "".join(value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                              for value in (error.stdout, error.stderr))
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity.update(appSHA256After=app_hashes(self.app), inputSHA256After=file_hashes(inputs),
                                testSHA256After=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
                (root / "identity.json").write_bytes(encoded(identity))
                (root / "pixels.json").write_bytes(encoded(pixels))
                (root / "app.log").write_text(log)
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    label = f"control-{'shown' if initial else 'hidden'}" if control else "visible" if initial else "hidden"
                    saved = Path(destination) / self._testMethodName / label
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")

    def compare_to_static_controls(self, initial):
        shown, _ = self.run_scene(initial=True, control=True)
        hidden, _ = self.run_scene(initial=False, control=True)
        actual, snapshots = self.run_scene(initial=initial)
        for name, visible in snapshots.items():
            expected = (shown if visible else hidden)["scene-ready-window.png"]
            for key in ("dimensions", "glyphCount", "glyphMaskSHA256"):
                with self.subTest(capture=name, measurement=key):
                    self.assertEqual(actual[name][key], expected[key], (actual[name], expected))

    def test_initially_hidden_composition_shows_hides_and_restores_nested_capture(self):
        self.compare_to_static_controls(False)

    def test_visible_composition_hides_and_restores_without_showing_its_false_child(self):
        self.compare_to_static_controls(True)
