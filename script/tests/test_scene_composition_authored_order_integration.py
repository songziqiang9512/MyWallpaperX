"""Self-authored composition order/copybackground -> completed App pixels.

The approved D1 behavior oracle is fixed before launch. Every resource here is
authored by this test; solid geometry uses the product's procedural solid lane.
This checks the bounded ordinary-composition behavior, not official pixel parity
between this solid fixture and the official client's differently formatted base.
Run only against an explicitly frozen Debug App with MWX_SCENE_INTEGRATION_APP.
"""

from pathlib import Path
import hashlib
import json
import math
import os
import shutil
import subprocess
import tempfile
import unittest

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_pkg_cache_extractor import make_package


CANVAS = (256, 256)
CHANNEL_TOLERANCE = 4
MINIMUM_CORRECT_FRACTION = .99
BLUE = (0, 0, 255)
YELLOW = (255, 255, 0)
RED = (255, 0, 0)
CYAN = (0, 255, 255)
# Canvas coordinates, 12 units inside each 48x48 colored card. The central
# background ROI is disjoint from both cards and stays inside a cover viewport.
ROI_RECTS = {"background": (116, 116, 140, 140),
             "child": (52, 116, 76, 140),
             "nonchild": (180, 116, 204, 140)}
VERTEX = (b"attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
          b"varying vec2 v_TexCoord;\n"
          b"void main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n")
FRAGMENT = (b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
            b"void main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);"
            b"gl_FragColor=vec4(vec3(1.0)-c.rgb,c.a);}\n")


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def fixture_entries(*, copy_background=None, order="baseline", enabled=True,
                    effect=True, childless=False, hide_child_next_frame=False):
    """None omits the authored field; false and true remain distinct inputs."""
    if copy_background is not None and not isinstance(copy_background, bool):
        raise ValueError("copy_background must be omitted, false, or true")
    if order not in ("baseline", "nonchild-after-root", "child-before-root"):
        raise ValueError(f"unknown authored order: {order}")
    root = {"id": 20, "name": "Owned composition root",
            "image": "models/util/composelayer.json", "origin": "128 128 0",
            "size": "256 256", "visible": True}
    if copy_background is not None:
        root["copybackground"] = copy_background
    if effect:
        root["effects"] = [{"id": 200, "file": "effects/own_invert/effect.json",
                            "visible": enabled}]
    background = {"id": 1, "name": "Owned full-scene background",
                  "image": "models/own_solid.json", "origin": "128 128 0",
                  "size": "256 256", "color": "1 1 0" if childless else "0 0 1",
                  "visible": True}
    child = {"id": 21, "parent": 20, "name": "Owned yellow child",
             "image": "models/own_solid.json", "origin": "-64 0 0",
             "size": "48 48", "color": "1 1 0", "visible": True}
    if hide_child_next_frame:
        child["visible"] = {"script": "export function update(v) { return engine.runtime < 2.5; }",
                            "value": True}
    nonchild = {"id": 30, "name": "Owned red nonchild",
                "image": "models/own_solid.json", "origin": "192 128 0",
                "size": "48 48", "color": "1 0 0", "visible": True}
    if childless:
        objects = [background, root]
    elif order == "nonchild-after-root":
        objects = [background, root, nonchild, child]
    elif order == "child-before-root":
        objects = [background, nonchild, child, root]
    else:
        objects = [background, nonchild, root, child]
    scene = {"version": 3,
             "general": {"orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
                         "clearcolor": "0 0 0"}, "objects": objects}
    entries = {
        "scene.json": encoded(scene),
        # Declare our own solid model, instead of resolving a stock model.
        "models/own_solid.json": encoded({"solidlayer": True, "width": 256, "height": 256}),
        # This utility path is the public authored type discriminator. Its
        # bytes are ours; no stock model, material, image, or shader is read.
        "models/util/composelayer.json": encoded({"width": 256, "height": 256, "autosize": False}),
        "effects/own_invert/effect.json": encoded({"passes": [{"material": "materials/own_invert.json"}]}),
        "materials/own_invert.json": encoded({"passes": [{
            "shader": "own_invert", "textures": [None], "blending": "normal",
            "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
        "shaders/own_invert.vert": VERTEX,
        "shaders/own_invert.frag": FRAGMENT,
    }
    return {"type": "scene", "file": "scene.json"}, entries


def preregistration(*, copy_background=None, order="baseline", enabled=True,
                    effect=True, childless=False, hide_child_next_frame=False):
    """The expected colors come from the approved contract, never the capture."""
    active_effect = effect and enabled
    copies = copy_background is not False
    if childless:
        expected = dict.fromkeys(ROI_RECTS, BLUE if active_effect and copies else YELLOW)
    else:
        expected = {"background": YELLOW if active_effect and copies else BLUE,
                    "child": BLUE if active_effect else YELLOW,
                    "nonchild": CYAN if active_effect and copies and order != "nonchild-after-root" else RED}
    protocol = {"canvas": CANVAS,
            "parameters": {"copybackground": "omitted" if copy_background is None else copy_background,
                           "order": order, "effectPresent": effect, "effectEnabled": enabled,
                           "childless": childless},
            "worldCenters": {"composition": [128, 128], "child": [64, 128], "nonchild": [192, 128]},
            "oracle": {name: {"canvasRect": rect, "expectedRGB": expected[name]}
                       for name, rect in ROI_RECTS.items()},
            "channelTolerance": CHANNEL_TOLERANCE,
            "minimumCorrectAreaFraction": MINIMUM_CORRECT_FRACTION,
            "captureMapping": "centered orthographic cover, scale=max(width/256,height/256)",
            "timingBoundary": "ready and later after Metal readbacks; no strict adjacent-frame binding",
            "evidenceBoundary": "bounded D1 order/copybackground behavior using owned procedural solids; not official pixel parity"}
    if hide_child_next_frame:
        later_expected = dict(expected, child=expected["background"])
        protocol["parameters"]["hideChildNextFrame"] = True
        protocol["visibilityTransition"] = {"layer": 21, "initialVisible": True,
                                             "hiddenAfterRuntimeSeconds": 2.5}
        protocol["snapshotOracles"] = {
            "scene-ready-window.png": protocol["oracle"],
            "scene-after-window.png": {
                name: {"canvasRect": rect, "expectedRGB": later_expected[name]}
                for name, rect in ROI_RECTS.items()}}
    return protocol


def measure_capture(path, protocol):
    width, height, rows = png_rgb_pixels(path)
    scale = max(width / CANVAS[0], height / CANVAS[1])

    def point(x, y):
        return ((x - CANVAS[0] / 2) * scale + width / 2,
                (y - CANVAS[1] / 2) * scale + height / 2)

    measured = {}
    oracle = protocol.get("snapshotOracles", {}).get(path.name, protocol["oracle"])
    for name, spec in oracle.items():
        left, top, right, bottom = spec["canvasRect"]
        x0, y0 = point(left, top)
        x1, y1 = point(right, bottom)
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"preregistered {name} ROI cropped: {(width, height)}")
        expected = spec["expectedRGB"]
        correct = total = 0
        maximum_error = 0
        for y in range(math.ceil(y0), math.floor(y1)):
            for x in range(math.ceil(x0), math.floor(x1)):
                rgb = rows[y][x * 3:x * 3 + 3]
                error = max(abs(actual - wanted) for actual, wanted in zip(rgb, expected))
                correct += error <= protocol["channelTolerance"]
                maximum_error = max(maximum_error, error)
                total += 1
        cx, cy = point((left + right) / 2, (top + bottom) / 2)
        center = list(rows[math.floor(cy)][math.floor(cx) * 3:math.floor(cx) * 3 + 3])
        measured[name] = {"expectedRGB": expected, "centerRGB": center,
                          "correct": correct, "total": total, "maximumChannelError": maximum_error}
    return {"size": [width, height], "rois": measured}


def app_hashes(app):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (app, app.with_name("MyWallpaperX.debug.dylib")) if path.is_file()}


class SceneCompositionAuthoredOrderIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def run_case(self, **parameters):
        protocol = preregistration(**parameters)
        project, entries = fixture_entries(**parameters)
        project_bytes = encoded(project)
        package = make_package(list(entries.items()))
        inputs = {name: hashlib.sha256(value).hexdigest() for name, value in entries.items()}
        inputs.update({"project.json": hashlib.sha256(project_bytes).hexdigest(),
                       "scene.pkg": hashlib.sha256(package).hexdigest()})
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes,
                         "App changed since this integration suite began")
        with tempfile.TemporaryDirectory(prefix="mwx-composition-authored-order-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            (content / "project.json").write_bytes(project_bytes)
            (content / "scene.pkg").write_bytes(package)
            (root / "preregistration.json").write_bytes(encoded(protocol))
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home),
                       MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                       "--mwx-debug-scene-duration", "7",
                       "--mwx-debug-scene-evidence-dir", str(evidence)]
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                        "inputSHA256": inputs,
                        "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=70)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                (root / "app.log").write_text(log)
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                captures = sorted(evidence.glob("*-window.png"))
                pixels = {path.name: measure_capture(path, protocol) for path in captures}
                (root / "pixels.json").write_bytes(encoded(pixels))
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                self.assertGreaterEqual(len(captures), 2, log[-6000:])
                self.assertIn("scene-ready-window.png", pixels)
                self.assertIn("scene-after-window.png", pixels)
                for reason in ("ready", "after"):
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-(?:failed|rejected)")
                needs_visible_effect = (parameters.get("effect", True)
                                        and parameters.get("enabled", True)
                                        and not (parameters.get("childless", False)
                                                 and parameters.get("copy_background") is False))
                if needs_visible_effect:
                    self.assertRegex(log + preview, r"generic shader execution [^\n]*layer=20 effect=0 ")
                if parameters.get("hide_child_next_frame", False):
                    self.assertRegex(log, r"layer=21 source=sceneScript value=false effective=false")
                for name, measurement in pixels.items():
                    for roi, value in measurement["rois"].items():
                        with self.subTest(capture=name, roi=roi):
                            self.assertGreater(value["total"], 0, value)
                            self.assertGreaterEqual(value["correct"] / value["total"],
                                                    MINIMUM_CORRECT_FRACTION, value)
                            self.assertTrue(all(abs(actual - expected) <= CHANNEL_TOLERANCE
                                                for actual, expected in zip(value["centerRGB"], value["expectedRGB"])),
                                            value)
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes,
                                 "App changed while the integration case ran")
                return log, pixels
            except subprocess.TimeoutExpired as error:
                log = "".join(value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                              for value in (error.stdout, error.stderr))
                (root / "app.log").write_text(log)
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity["appSHA256After"] = app_hashes(self.app)
                (root / "identity.json").write_bytes(encoded(identity))
                # Keep final evidence only when explicitly requested by the run.
                # The isolated HOME, cache, and extracted fixture are temporary.
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    if (root / "app.log").exists():
                        shutil.copy2(root / "app.log", saved / "app.log")

    def test_effect_off_preserves_owned_geometry_and_colors(self):
        self.run_case(enabled=False)

    def test_missing_copybackground_inverts_background_child_and_prior_nonchild(self):
        self.run_case()

    def test_true_copybackground_matches_missing_field(self):
        self.run_case(copy_background=True)

    def test_false_copybackground_preserves_background_and_nonchild(self):
        self.run_case(copy_background=False)

    def test_nonchild_after_root_remains_red(self):
        self.run_case(order="nonchild-after-root")

    def test_child_before_root_still_enters_group(self):
        self.run_case(order="child-before-root")

    def test_no_effect_group_keeps_child_and_authored_peer(self):
        self.run_case(effect=False)

    def test_childless_false_copybackground_preserves_yellow_base(self):
        self.run_case(childless=True, copy_background=False)

    def test_childless_true_copybackground_inverts_yellow_base(self):
        self.run_case(childless=True, copy_background=True)

    def test_hidden_next_frame_child_reveals_fresh_copied_background(self):
        self.run_case(hide_child_next_frame=True)


if __name__ == "__main__":
    unittest.main()
