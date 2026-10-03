"""Conditional fullscreen execution and atomic unavailable-cohort rejection.

All package content is authored here or by existing owned fixture helpers.
Requires MWX_SCENE_INTEGRATION_APP; only MWX_SCENE_INTEGRATION_EVIDENCE retains
inputs, logs and captures. This proves a fullscreen prerequisite, not real293
whole-key repair, particle activation, or official pixel parity.
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

from .test_scene_composition_authored_order_integration import VERTEX, encoded, measure_capture
from .test_scene_hidden_provider_integration import fixture_entries as source_fixture
from .test_scene_pkg_cache_extractor import make_package


WHITE, GRAY, GREEN = (255, 255, 255), (128, 128, 128), (0, 255, 0)
RECTS = {"background": (116, 116, 140, 140), "child": (52, 116, 76, 140),
         "nonchild": (180, 116, 204, 140)}
FRAGMENT = (b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
            b"void main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n")


def fixture_entries(*, mixed_particle=False, no_capture=False):
    def visible(condition, fallback=True):
        return {"user": {"name": "mode", "condition": condition}, "value": fallback}
    objects = [
        {"id": 1, "name": "Owned white background", "image": "models/own_solid.json",
         "origin": "128 128 0", "size": "256 256", "color": "1 1 1"},
        {"id": 20, "name": "Owned fullscreen dim filter", "image": "models/util/fullscreenlayer.json",
         "origin": "128 128 0", "size": "256 256", "visible": visible("on"),
         "effects": [{"id": 200, "file": "effects/own_dim/effect.json", "visible": True}]},
        {"id": 30, "name": "Healthy later green peer", "image": "models/own_solid.json",
         "origin": "192 128 0", "size": "48 48", "color": "0 1 0"}]
    entries = {
        "models/own_solid.json": encoded({"solidlayer": True, "width": 256, "height": 256}),
        "models/util/fullscreenlayer.json": encoded({"width": 256, "height": 256, "autosize": False}),
        "effects/own_dim/effect.json": encoded({"passes": [{"material": "materials/own_dim.json"}]}),
        "materials/own_dim.json": encoded({"passes": [{"shader": "own_dim", "textures": [None],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
        "shaders/own_dim.vert": VERTEX,
        "shaders/own_dim.frag": FRAGMENT}
    if no_capture:
        # A structural fullscreen target without an effect has no captured
        # execution owner. Its presence alone cannot advertise live readiness.
        objects[1].pop("effects")
        for name in ("effects/own_dim/effect.json", "materials/own_dim.json",
                     "shaders/own_dim.vert", "shaders/own_dim.frag"):
            entries.pop(name)
    if mixed_particle:
        objects.append({"id": 42, "name": "Unsupported live particle cohort", "particle": "particles/owned.json",
                        "origin": "64 128 0", "scale": "1 1 1", "visible": visible("unsupported", False)})
        # A real authored particle definition, even though its activation is
        # rejected. No success stub stands in for resource preparation.
        entries["particles/owned.json"] = encoded({"material": "materials/owned_particle.json",
            "maxcount": 64, "starttime": 0.5,
            "emitter": [{"name": "sphererandom", "rate": 8, "duration": 20, "instantaneous": 1,
                         "distancemin": 0, "distancemax": 0}],
            "initializer": [{"name": "lifetimerandom", "min": 30, "max": 30},
                            {"name": "sizerandom", "min": 20, "max": 20},
                            {"name": "colorrandom", "min": "255 0 0", "max": "255 0 0"}],
            "renderer": [{"name": "sprite"}]})
        entries["materials/owned_particle.json"] = encoded({"passes": [{"shader": "genericparticle",
            "textures": ["owned_particle.png"], "blending": "translucent", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries["materials/owned_particle.png"] = source_fixture()[1]["materials/white.png"]
    entries["scene.json"] = encoded({"version": 3, "general": {
        "orthogonalprojection": {"width": 256, "height": 256}, "clearcolor": "1 1 1"}, "objects": objects})
    definition = {"type": "combo", "value": "on", "options": [
        {"label": value, "value": value} for value in ("off", "on", "unsupported")]}
    return {"type": "scene", "file": "scene.json", "general": {"properties": {"mode": definition}}}, entries


def file_hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in paths if path.is_file()}


def app_hashes(app):
    return file_hashes((app, app.with_name("MyWallpaperX.debug.dylib"),
                        app.parents[1] / "Resources/default.metallib"))


class SceneFullscreenVisibilityIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def run_case(self, *, mixed_particle=False, no_capture=False):
        unavailable = mixed_particle or no_capture
        sequence = [{"mode": "on"}, {"mode": "unsupported" if mixed_particle else "off"}]
        accepted = ["false", "false"] if unavailable else ["true", "true"]
        def oracle(dim):
            return {key: {"canvasRect": RECTS[key], "expectedRGB": GREEN if key == "nonchild"
                          else GRAY if dim else WHITE} for key in RECTS}
        protocol = {"canvas": 256, "channelTolerance": 4, "minimumCorrectFraction": .99,
                    "launch": {"mode": "off"}, "sequenceEvery2Seconds": sequence,
                    "expectedStepAccepted": accepted, "mixedParticle": mixed_particle,
                    "noCapturedExecution": no_capture,
                    "snapshotTimesSeconds": {"scene-ready-window.png": 1,
                        "scene-series-0002-window.png": 3.5, "scene-after-window.png": 7},
                    "snapshotOracles": {"scene-ready-window.png": oracle(False),
                        "scene-series-0002-window.png": oracle(not unavailable),
                        "scene-after-window.png": oracle(False)},
                    "captureMapping": "centered orthographic cover, 256 square canvas"}
        project, entries = fixture_entries(mixed_particle=mixed_particle, no_capture=no_capture)
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-fullscreen-visibility-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            input_paths = (content / "project.json", content / "scene.pkg")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                "--mwx-debug-scene-duration", "9", "--mwx-debug-scene-evidence-dir", str(evidence),
                "--mwx-debug-scene-after-snapshot-delay", "7", "--mwx-debug-scene-periodic-snapshot-interval", "1",
                "--mwx-debug-scene-properties-json", json.dumps(protocol["launch"]),
                "--mwx-debug-scene-live-property-sequence-json", json.dumps(sequence)]
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                "inputSHA256": file_hashes(input_paths),
                "entrySHA256": {name: hashlib.sha256(value).hexdigest() for name, value in entries.items()},
                "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
            (root / "prerun.json").write_bytes(encoded(identity))
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                for name, expected in protocol["snapshotOracles"].items():
                    self.assertTrue((evidence / name).is_file(), (name, log[-5000:]))
                    pixels[name] = measure_capture(evidence / name, {"oracle": expected, "channelTolerance": 4})
                self.assertEqual(result.returncode, 0, log[-5000:])
                steps = re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log)
                self.assertEqual(steps, [(str(i), value) for i, value in enumerate(accepted)], log[-5000:])
                updates = re.findall(r"phase=live-property-update accepted=(true|false) surfacesBefore=(\d+) surfacesAfter=(\d+) windowsBefore=(\S+) windowsAfter=(\S+)", log)
                self.assertEqual([u[0] for u in updates], accepted)
                self.assertTrue(all(u[1] == u[2] == "1" and u[3] == u[4] for u in updates), updates)
                self.assertEqual(log.count("phase=session-candidate "), 1, log[-5000:])
                self.assertEqual(log.count("phase=session-activated "), 1, log[-5000:])
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                for reason in ("ready", "series-0002", "after"):
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-(?:failed|rejected)")
                if not unavailable:
                    self.assertRegex(log + preview, r"generic shader execution [^\n]*layer=20 effect=0 ")
                elif no_capture:
                    self.assertNotRegex(log + preview, r"generic shader execution [^\n]*layer=20 effect=0 ")
                for name, measured in pixels.items():
                    for roi, value in measured["rois"].items():
                        with self.subTest(capture=name, roi=roi):
                            self.assertGreater(value["total"], 0, value)
                            self.assertGreaterEqual(value["correct"] / value["total"], .99, value)
                            self.assertTrue(all(abs(a - b) <= 4 for a, b in
                                zip(value["centerRGB"], value["expectedRGB"])), value)
                self.assertEqual(file_hashes(input_paths), identity["inputSHA256"])
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                return log, pixels
            except subprocess.TimeoutExpired as error:
                log = "".join(v.decode(errors="replace") if isinstance(v, bytes) else v or ""
                              for v in (error.stdout, error.stderr))
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity.update(appSHA256After=app_hashes(self.app), inputSHA256After=file_hashes(input_paths))
                (root / "identity.json").write_bytes(encoded(identity))
                (root / "pixels.json").write_bytes(encoded(pixels))
                (root / "app.log").write_text(log)
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")

    def test_prepared_fullscreen_can_show_and_hide_in_authored_slot(self):
        self.run_case()

    def test_mixed_particle_cohort_rejects_even_when_particle_stays_hidden(self):
        self.run_case(mixed_particle=True)

    def test_fullscreen_without_captured_execution_keeps_visibility_rejected(self):
        self.run_case(no_capture=True)


if __name__ == "__main__":
    unittest.main()
