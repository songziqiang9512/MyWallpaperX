"""Fullscreen layer/effect visibility and atomic unavailable-cohort rejection.

All package content is authored here or by existing owned fixture helpers.
Requires MWX_SCENE_INTEGRATION_APP; only MWX_SCENE_INTEGRATION_EVIDENCE retains
inputs, logs and captures. Owned fullscreen/particle cohorts do not establish
real293 whole-key repair or official pixel parity.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

from .test_scene_composition_authored_order_integration import VERTEX, encoded, measure_capture
from .test_scene_pkg_cache_extractor import make_package


WHITE, GRAY, GREEN, RED = (255, 255, 255), (128, 128, 128), (0, 255, 0), (255, 0, 0)
RECTS = {"background": (116, 116, 140, 140), "child": (52, 116, 76, 140),
         "nonchild": (180, 116, 204, 140)}
FRAGMENT = (b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
            b"void main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n")


def white_png():
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff" * 16) * 4)) + chunk(b"IEND", b""))


def fixture_entries(*, mixed_particle=False, no_capture=False, inactive_effect=False,
                    missing_shader=False, legal_particle=False):
    def visible(condition, fallback=True):
        return {"user": {"name": "mode", "condition": condition}, "value": fallback}
    objects = [
        {"id": 1, "name": "Owned white background", "image": "models/own_solid.json",
         "origin": "128 128 0", "size": "256 256", "color": "1 1 1"},
        {"id": 20, "name": "Owned fullscreen dim filter", "image": "models/util/fullscreenlayer.json",
         "origin": "128 128 0", "size": "256 256", "visible": visible("on"),
         "effects": [{"id": 200, "file": "effects/own_dim/effect.json",
                      "visible": {"user": "fx", "value": False} if inactive_effect else True}]},
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
        # This authored fullscreen layer contributes no pixels. Visibility is
        # a legal no-op; an unavailable authored effect is a different case.
        objects[1].pop("effects")
        for name in ("effects/own_dim/effect.json", "materials/own_dim.json",
                     "shaders/own_dim.vert", "shaders/own_dim.frag"):
            entries.pop(name)
    if missing_shader:
        entries.pop("shaders/own_dim.frag")
    if mixed_particle or legal_particle:
        particle_visibility = ({"user": "fx", "value": False}
                               if legal_particle and inactive_effect
                               else visible("on" if legal_particle else "unsupported", False))
        size = 48 if legal_particle else 20
        objects.append({"id": 42, "name": "Owned red particle cohort" if legal_particle
                        else "Particle cohort with missing texture", "particle": "particles/owned.json",
                        "origin": "64 128 0", "scale": "1 1 1",
                        "visible": particle_visibility})
        # The negative cohort deliberately omits its actual texture. The legal
        # cohort uses a stationary sprite after the fullscreen authored slot.
        entries["particles/owned.json"] = encoded({"material": "materials/owned_particle.json",
            "maxcount": 64, "starttime": 0.5,
            "emitter": [{"name": "sphererandom", "rate": 8, "duration": 20, "instantaneous": 1,
                         "distancemin": 0, "distancemax": 0}],
            "initializer": [{"name": "lifetimerandom", "min": 30, "max": 30},
                            {"name": "sizerandom", "min": size, "max": size},
                            {"name": "colorrandom", "min": "255 0 0", "max": "255 0 0"}],
            "renderer": [{"name": "sprite"}]})
        entries["materials/owned_particle.json"] = encoded({"passes": [{"shader": "genericparticle",
            "textures": ["owned_particle.png"], "blending": "translucent", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull"}]})
        if legal_particle:
            entries["materials/owned_particle.png"] = white_png()
    entries["scene.json"] = encoded({"version": 3, "general": {
        "orthogonalprojection": {"width": 256, "height": 256}, "clearcolor": "1 1 1"}, "objects": objects})
    definition = {"type": "combo", "value": "on", "options": [
        {"label": value, "value": value} for value in ("off", "on", "unsupported")]}
    properties = {"mode": definition}
    if inactive_effect:
        properties["fx"] = {"type": "bool", "value": False}
    return {"type": "scene", "file": "scene.json", "general": {"properties": properties}}, entries


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

    def run_case(self, *, mixed_particle=False, no_capture=False, inactive_effect=False,
                 missing_shader=False, legal_particle=False, launch=None, sequence=None,
                 expected_dims=None):
        unavailable = mixed_particle or missing_shader
        launch = launch or {"mode": "off", **({"fx": False} if inactive_effect else {})}
        sequence = sequence or [{"mode": "on"}, {"mode": "unsupported" if mixed_particle else "off"}]
        if expected_dims is None:
            expected_dims = [not (unavailable or no_capture), False]
        self.assertEqual(len(sequence), len(expected_dims))
        accepted = ["false" if unavailable else "true"] * len(sequence)
        def oracle(dim, particle=False):
            return {key: {"canvasRect": RECTS[key], "expectedRGB": GREEN if key == "nonchild"
                          else RED if key == "child" and particle
                          else GRAY if dim else WHITE} for key in RECTS}
        after_delay = 2 * len(sequence) + 3
        snapshots = {"scene-ready-window.png": oracle(False)}
        times = {"scene-ready-window.png": 1}
        for index, dim in enumerate(expected_dims):
            # Each intermediate capture is 1.5s after its property request and
            # 0.5s before the next; the last gets the existing settled 'after'.
            name = ("scene-after-window.png" if index == len(sequence) - 1
                    else f"scene-series-{2 + index * 2:04d}-window.png")
            snapshots[name] = oracle(dim, legal_particle and index == 0)
            times[name] = after_delay if index == len(sequence) - 1 else 3.5 + index * 2
        protocol = {"canvas": 256, "channelTolerance": 4, "minimumCorrectFraction": .99,
                    "launch": launch, "sequenceEvery2Seconds": sequence,
                    "expectedStepAccepted": accepted, "mixedParticleMissingTexture": mixed_particle,
                    "noEffectNoOp": no_capture, "initiallyInactiveEffect": inactive_effect,
                    "missingEffectFragment": missing_shader, "legalParticleCohort": legal_particle,
                    "snapshotTimesSeconds": times, "snapshotOracles": snapshots,
                    "captureMapping": "centered orthographic cover, 256 square canvas"}
        project, entries = fixture_entries(mixed_particle=mixed_particle, no_capture=no_capture,
            inactive_effect=inactive_effect, missing_shader=missing_shader, legal_particle=legal_particle)
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
                "--mwx-debug-scene-duration", str(after_delay + 2), "--mwx-debug-scene-evidence-dir", str(evidence),
                "--mwx-debug-scene-after-snapshot-delay", str(after_delay), "--mwx-debug-scene-periodic-snapshot-interval", "1",
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
                for name in snapshots:
                    reason = name.removeprefix("scene-").removesuffix("-window.png")
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-(?:failed|rejected)")
                if not unavailable and not no_capture:
                    self.assertRegex(log + preview, r"generic shader execution [^\n]*layer=20 effect=0 ")
                elif no_capture or missing_shader:
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

    def test_missing_particle_texture_rejects_the_entire_fullscreen_cohort(self):
        self.run_case(mixed_particle=True)

    def test_fullscreen_without_effect_accepts_visibility_as_noop(self):
        self.run_case(no_capture=True)

    def test_initially_inactive_effect_preserves_layer_toggle_and_live_bool(self):
        self.run_case(inactive_effect=True,
            sequence=[{"mode": "on"}, {"fx": True}, {"fx": False}, {"mode": "off"}],
            expected_dims=[False, True, False, False])

    def test_effect_changes_while_layer_hidden_are_retained_for_show(self):
        self.run_case(inactive_effect=True, launch={"mode": "on", "fx": False},
            sequence=[{"mode": "off"}, {"fx": True}, {"mode": "on"}, {"mode": "off"},
                      {"fx": False}, {"mode": "on"}],
            expected_dims=[False, False, True, False, False, False])

    def test_active_effect_missing_shader_rejects_fullscreen_visibility(self):
        self.run_case(missing_shader=True)

    def test_legal_particle_and_inactive_fullscreen_effect_share_bool_key(self):
        self.run_case(legal_particle=True, inactive_effect=True,
            launch={"mode": "on", "fx": False}, sequence=[{"fx": True}, {"fx": False}],
            expected_dims=[True, False])


if __name__ == "__main__":
    unittest.main()
