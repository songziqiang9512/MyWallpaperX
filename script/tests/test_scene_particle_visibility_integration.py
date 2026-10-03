"""Actual prepared-particle visibility, birth positions and local rejection.

All inputs are authored here. Requires an explicitly frozen Debug App and
retains evidence only under MWX_SCENE_INTEGRATION_EVIDENCE. The root-particle
oracle does not claim child-system behavior or official pixel parity.
"""
from pathlib import Path
import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_composition_authored_order_integration import encoded, measure_capture
from .test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from .test_scene_pkg_cache_extractor import make_package


def white_png():
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff" * 16) * 4)) + chunk(b"IEND", b""))


def fixture_entries(*, missing_texture=False, script_mode=None, show_emit=None):
    visibility = {"user": {"name": "mode", "condition": "on"}, "value": True}
    particle = {"id": 42, "name": "Owned experiment", "particle": "particles/owned.json",
                "origin": "48 128 0", "scale": "1 1 1", "visible": visibility}
    peer = {"id": 1, "name": "Stable green peer", "image": "models/owned_solid.json",
            "origin": "192 128 0", "size": "24 24", "color": "0 1 0"}
    # An authored reference clock travels at the declared velocity. Reading it
    # from the same Metal frame avoids treating PNG export time as capture time.
    marker = {"id": 2, "name": "Owned visible-age clock", "image": "models/owned_solid.json",
              "size": "6 6", "color": "0 0 1", "origin": {"value": "48 96 0", "script": (
                  "let age=0; let previous=false; export function update(value) {"
                  "const on=engine.userProperties.mode==='on';"
                  "if (!on || !previous) age=0; if (on) age+=engine.frametime; previous=on;"
                  "return new Vec3(48+20*age,96,0); }")}}
    if script_mode == "setter":
        particle["visible"] = False
        # If this owner's unprepared particle write is admitted, its returned
        # alpha also removes the healthy peer. Rejection must retain green.
        callback = "thisScene.getLayer('Owned experiment').visible=true; return 0;"
        peer["alpha"] = {"value": 1, "script": (
            "export function init(value) {" + callback + "}"
            "export function update(value) {" + callback + "}")}
    elif script_mode == "return":
        particle["visible"] = {"value": False, "script":
            "export function init(value) { return true; }"
            "export function update(value) { return true; }"}
    elif script_mode == "visible-cycle":
        condition = "(engine.runtime >= 2 && engine.runtime < 4) || engine.runtime >= 6"
        particle["visible"] = {"value": False, "script":
            "export function update(value) { return " + condition + "; }"}
        marker["origin"]["script"] = marker["origin"]["script"].replace(
            "engine.userProperties.mode==='on'", condition)
    if show_emit:
        particle["visible"] = False
        commands = "p.emitParticles(3); p.visible=true;" if show_emit == "before" else "p.visible=true; p.emitParticles(3);"
        marker["origin"]["script"] = (
            "let sent=false; let age=0; export function update(value) {"
            "if (!sent && engine.runtime >= 2) { const p=thisScene.getLayer('Owned experiment');"
            + commands + "sent=true; } if (sent) age+=engine.frametime;"
            "return new Vec3(48+20*age,96,0); }")
    definition = {"material": "materials/owned_particle.json", "maxcount": 32, "starttime": 0,
        "flags": 1, "emitter": [{"name": "sphererandom", "rate": 1, "instantaneous": 1,
                                  "distancemin": 0, "distancemax": 0}],
        "initializer": [{"name": "lifetimerandom", "min": 6, "max": 6},
                        {"name": "sizerandom", "min": 10, "max": 10},
                        {"name": "colorrandom", "min": "255 255 255", "max": "255 255 255"},
                        {"name": "velocityrandom", "min": "20 0 0", "max": "20 0 0"}],
        "operator": [{"name": "movement", "flags": 1, "gravity": "0 0 0"}],
        "renderer": [{"name": "sprite"}]}
    if show_emit:
        definition["emitter"][0].update(rate=0, instantaneous=0)
    entries = {"scene.json": encoded({"version": 3, "general": {
        "orthogonalprojection": {"width": 256, "height": 256}, "clearcolor": "0 0 0"},
        "objects": [particle, peer, marker]}),
        "models/owned_solid.json": encoded({"solidlayer": True, "width": 256, "height": 256}),
        "particles/owned.json": encoded(definition),
        "materials/owned_particle.json": encoded({"passes": [{"shader": "genericparticle",
            "textures": ["owned_white.png"], "blending": "translucent", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull"}]})}
    if not missing_texture:
        entries["materials/owned_white.png"] = white_png()
    definition = {"type": "combo", "value": "on", "options": [
        {"label": value, "value": value} for value in ("off", "on")]}
    project = {"type": "scene", "file": "scene.json", "general": {"properties": {"mode": definition}}}
    return project, entries


def measure_particles(path):
    """Read actual sprites and the independent clock from declared canvas ROIs."""
    width, height, rows = png_rgb_pixels(path)
    scale = max(width / 256, height / 256)
    def components(top, bottom, blue=False):
        left, right = [(x - 128) * scale + width / 2 for x in (24, 176)]
        y0, y1 = [(y - 128) * scale + height / 2 for y in (top, bottom)]
        if not (0 <= left < right <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"preregistered ROI cropped: {(width, height)}")
        columns, count = [], 0
        for x in range(math.ceil(left), math.floor(right)):
            i = x * 3
            hits = sum((row[i] <= 4 and row[i + 1] <= 4 and row[i + 2] >= 251) if blue
                       else (row[i] >= 251 and row[i + 1] >= 251 and row[i + 2] >= 251)
                       for row in rows[math.ceil(y0):math.floor(y1)])
            count += hits
            if hits:
                columns.append(x)
        groups = []
        for x in columns:
            if not groups or x > groups[-1][-1] + 1:
                groups.append([])
            groups[-1].append(x)
        return count, [((group[0] + group[-1] + 1) / 2 - width / 2) / scale + 128 for group in groups]
    count, centers = components(112, 144)
    marker_count, marker_centers = components(154, 166, blue=True)
    return {"whitePixels": count, "centersCanvasX": centers,
        "markerPixels": marker_count, "markerCentersCanvasX": marker_centers,
        "peer": measure_capture(path, {"channelTolerance": 4, "oracle": {
            "green": {"canvasRect": (184, 120, 200, 136), "expectedRGB": (0, 255, 0)}}})}


class SceneParticleVisibilityIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def run_case(self, *, screens=1, missing_texture=False, script_mode=None, show_emit=None):
        rejected = missing_texture or script_mode in ("setter", "return")
        sequence = [] if script_mode or show_emit else [{"mode": "on"}, {"mode": "off"}, {"mode": "on"}]
        accepted = ["false" if rejected else "true"] * len(sequence)
        times = {"scene-ready-window.png": 1, "scene-series-0002-window.png": 2.5,
                 "scene-series-0006-window.png": 4.5, "scene-series-0010-window.png": 6.5,
                 "scene-after-window.png": 8}
        if show_emit:
            times = {"scene-ready-window.png": 1, "scene-series-0002-window.png": 2.5,
                     "scene-after-window.png": 6}
        protocol = {"canvas": 256, "particleROI": [24, 112, 176, 144],
            "clockROI": [24, 154, 176, 166],
            "launch": {"mode": "off"}, "sequenceEvery2Seconds": sequence,
            "snapshotTimesSeconds": times, "expectedAccepted": accepted, "surfaceCount": screens,
            "missingTexture": missing_texture, "scriptMode": script_mode, "showEmitOrder": show_emit,
            "particleInputs": {"originX": 48, "velocityXPerSecond": 20, "rate": 0 if show_emit else 1,
                               "initialBurst": 0 if show_emit else 1, "explicitCount": 3 if show_emit else 0,
                               "lifetime": 6, "size": 10, "starttime": 0},
            "oracle": {"hiddenCaptures": list(times) if rejected else [
                "scene-ready-window.png"] if show_emit else ["scene-ready-window.png", "scene-series-0006-window.png"],
                "clock": "blue marker x=48+20*visibleAge, authored y96 projects to screen y160",
                "clockPredicate": "same show/emit callback sent flag" if show_emit else
                    "authored runtime visibility cycle" if script_mode == "visible-cycle" else "actual user mode off-to-on",
                "oldestParticleMatchesClockTolerance": 2, "birthSpacing": 20,
                "birthSpacingTolerance": 2, "showAgeRange": [.2, .9],
                "afterAgeRange": [3.5, 4.8] if show_emit else [1.5, 2.8],
                "birthBoundaryCountTolerance": 1, "greenChannelTolerance": 4, "greenCorrectFraction": .99}}
        project, entries = fixture_entries(missing_texture=missing_texture, script_mode=script_mode, show_emit=show_emit)
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-particle-visibility-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            input_paths = (content / "project.json", content / "scene.pkg")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                "--mwx-debug-scene-duration", "8" if show_emit else "10", "--mwx-debug-scene-evidence-dir", str(evidence),
                "--mwx-debug-scene-after-snapshot-delay", "6" if show_emit else "8", "--mwx-debug-scene-periodic-snapshot-interval", ".5",
                "--mwx-debug-scene-properties-json", json.dumps(protocol["launch"])]
            if sequence:
                command += ["--mwx-debug-scene-live-property-sequence-json", json.dumps(sequence)]
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                "inputSHA256": file_hashes(input_paths),
                "entrySHA256": {key: hashlib.sha256(value).hexdigest() for key, value in entries.items()},
                "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
            (root / "prerun.json").write_bytes(encoded(identity))
            env = os.environ.copy()
            for key in ("MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE", "MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES"):
                env.pop(key, None)
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT=str(screens),
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                for name in times:
                    self.assertTrue((evidence / name).is_file(), (name, log[-6000:]))
                    pixels[name] = measure_particles(evidence / name)
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertEqual(re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log),
                                 [(str(i), value) for i, value in enumerate(accepted)], log[-6000:])
                updates = re.findall(r"phase=live-property-update accepted=(true|false) surfacesBefore=(\d+) surfacesAfter=(\d+) windowsBefore=(\S+) windowsAfter=(\S+)", log)
                self.assertEqual([value[0] for value in updates], accepted)
                self.assertTrue(all(u[1] == u[2] == str(screens) and u[3] == u[4] for u in updates), updates)
                self.assertEqual(log.count("phase=session-candidate "), 1, log[-6000:])
                self.assertEqual(log.count("phase=session-activated "), 1, log[-6000:])
                self.assertIn("gpuDrained=true", log)
                completed = set(re.findall(r"state=completed frame=[1-9]\d* surface=(\d+) gpu=completed", log))
                self.assertEqual(len(completed), screens, completed)
                self.assertIn(f"phase=stopped surfacesBefore={screens} surfacesAfter=0", log)
                for name in times:
                    reason = name.removeprefix("scene-").removesuffix("-window.png")
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-(?:failed|rejected)")
                if script_mode in ("setter", "return"):
                    self.assertNotIn("failure=exception", log)
                    self.assertRegex(log, r"phase=owner-effects-admission frame=0 [^\n]*externallyRejected=[1-9]\d* ")
                for name, measured in pixels.items():
                    self.assertEqual(len(measured["markerCentersCanvasX"]), 1, (name, measured))
                    green = measured["peer"]["rois"]["green"]
                    self.assertGreater(green["total"], 0, (name, green))
                    self.assertGreaterEqual(green["correct"] / green["total"], .99, (name, green))
                for name in protocol["oracle"]["hiddenCaptures"]:
                    self.assertEqual(pixels[name]["whitePixels"], 0, (name, pixels[name]))
                if not rejected:
                    for name in [key for key in times if key not in protocol["oracle"]["hiddenCaptures"]]:
                        centers = pixels[name]["centersCanvasX"]
                        marker_x = pixels[name]["markerCentersCanvasX"][0]
                        age = (marker_x - 48) / 20
                        bounds = ([3.5, 4.8] if show_emit else [1.5, 2.8]) if name == "scene-after-window.png" else [.2, .9]
                        self.assertTrue(bounds[0] <= age <= bounds[1], (name, age))
                        self.assertTrue(centers, (name, pixels[name]))
                        self.assertLessEqual(abs(max(centers) - marker_x), 2, (name, centers, marker_x))
                        self.assertTrue(all(46 <= x <= marker_x + 2 for x in centers), (name, centers))
                        if show_emit or name != "scene-after-window.png":
                            self.assertEqual(len(centers), 1, (name, centers))
                        else:
                            self.assertLessEqual(abs(len(centers) - (math.floor(age) + 1)), 1, (name, centers, age))
                        for a, b in zip(centers, centers[1:]):
                            self.assertLessEqual(abs(b - a - 20), 2, (name, centers))
                if show_emit:
                    consumed = re.findall(r"phase=particle-transition-consumed frame=(\d+) layer=42 revision=(\d+) action=4 surface=(\d+)", log)
                    self.assertEqual(len(consumed), screens, consumed)
                    preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                    self.assertEqual([int(v) for v in re.findall(r"particle initial live: (\d+)", preview)], [0, 3])
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

    def test_initial_hidden_root_show_hide_show_restarts_birth_positions(self):
        self.run_case()

    def test_two_prepared_surfaces_accept_the_same_visibility_sequence(self):
        self.run_case(screens=2)

    def test_missing_texture_rejects_visibility(self):
        self.run_case(missing_texture=True)

    def test_script_setter_cannot_show_an_unprepared_particle_owner(self):
        self.run_case(missing_texture=True, script_mode="setter")

    def test_visible_return_cannot_show_an_unprepared_particle_owner(self):
        self.run_case(missing_texture=True, script_mode="return")

    def test_visible_return_shows_hides_and_restarts_a_prepared_particle_owner(self):
        self.run_case(script_mode="visible-cycle")

    def test_same_callback_emit_then_show_preserves_explicit_births(self):
        self.run_case(show_emit="before")

    def test_same_callback_show_then_emit_preserves_explicit_births(self):
        self.run_case(show_emit="after")


if __name__ == "__main__":
    unittest.main()
