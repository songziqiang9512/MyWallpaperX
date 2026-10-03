"""Accepted live edits retain their intent while hidden image decode is pending.

Self-authored inputs only. Run against an explicitly frozen Debug executable via
MWX_SCENE_INTEGRATION_APP. MWX_SCENE_INTEGRATION_EVIDENCE retains requested evidence,
including failures; the isolated HOME and caches otherwise leave with the case.
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
from .test_scene_pkg_cache_extractor import make_package


CANVAS = 256
IMAGE_SIZE = 1024
BLACK, BLUE, RED, GREEN = (0, 0, 0), (0, 0, 255), (255, 0, 0), (0, 255, 0)
RECTS = {"a": (68, 116, 92, 140), "b": (164, 116, 188, 140),
         "peer": (122, 122, 134, 134)}
TOLERANCE, CORRECT_FRACTION = 4, .99


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def solid_png(color):
    """The decoded image really is 1024 square; compressed bytes stay bounded."""
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))
    compressor = zlib.compressobj(1)
    row = b"\0" + bytes((*color, 255)) * IMAGE_SIZE
    compressed = [compressor.compress(row) for _ in range(IMAGE_SIZE)]
    compressed.append(compressor.flush())
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", IMAGE_SIZE, IMAGE_SIZE, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", b"".join(compressed)) + chunk(b"IEND", b""))


def fixture_entries():
    objects = []
    entries = {}
    for key, layer_id, center, color in (("a", 11, 80, BLUE), ("b", 22, 176, RED)):
        objects.append({"id": layer_id, "name": f"Owned conditional {key}",
                        "image": f"models/{key}.json", "origin": f"{center} 128 0",
                        "size": "64 64", "visible": {
                            "user": {"name": key, "condition": "on"}, "value": True}})
        entries[f"models/{key}.json"] = encoded({"material": f"materials/{key}.json"})
        entries[f"materials/{key}.json"] = encoded({"passes": [{
            "shader": "genericimage", "textures": [f"materials/{key}.png"]}]})
        entries[f"materials/{key}.png"] = solid_png(color)
    objects.append({"id": 33, "name": "Owned healthy green peer",
                    "image": "models/own_solid.json", "origin": "128 128 0",
                    "size": "24 24", "color": "0 1 0", "visible": True})
    entries["models/own_solid.json"] = encoded({"solidlayer": True, "width": 256, "height": 256})
    entries["scene.json"] = encoded({"version": 3, "general": {
        "orthogonalprojection": {"width": CANVAS, "height": CANVAS},
        "clearcolor": "0 0 0"}, "objects": objects})
    definition = {"type": "combo", "value": "on", "options": [
        {"label": "On", "value": "on"}, {"label": "Off", "value": "off"}]}
    project = {"type": "scene", "file": "scene.json", "general": {
        "properties": {"a": definition, "b": definition}}}
    return project, entries


def file_hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in paths if path.is_file()}


def app_hashes(app):
    return file_hashes((app, app.with_name("MyWallpaperX.debug.dylib"),
                        app.parents[1] / "Resources/default.metallib"))


def measure_capture(path, colors):
    width, height, rows = png_rgb_pixels(path)
    scale = max(width / CANVAS, height / CANVAS)
    def point(x, y):
        return ((x - CANVAS / 2) * scale + width / 2,
                (y - CANVAS / 2) * scale + height / 2)
    rois = {}
    for name, rect in RECTS.items():
        x0, y0 = point(*rect[:2])
        x1, y1 = point(*rect[2:])
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"preregistered {name} ROI cropped: {(width, height)}")
        correct = total = 0
        expected = colors[name]
        for y in range(math.ceil(y0), math.floor(y1)):
            for x in range(math.ceil(x0), math.floor(x1)):
                rgb = rows[y][x * 3:x * 3 + 3]
                correct += all(abs(a - b) <= TOLERANCE for a, b in zip(rgb, expected))
                total += 1
        cx, cy = point((rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2)
        center = list(rows[math.floor(cy)][math.floor(cx) * 3:math.floor(cx) * 3 + 3])
        rois[name] = {"expectedRGB": expected, "centerRGB": center,
                      "correct": correct, "total": total}
    return {"size": [width, height], "rois": rois}


class SceneDeferredPropertyIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def run_case(self, sequence, after, transitions, accepted):
        before = {"a": BLACK, "b": BLACK, "peer": GREEN}
        after = {"a": BLUE if after[0] else BLACK, "b": RED if after[1] else BLACK,
                 "peer": GREEN}
        protocol = {"canvas": CANVAS, "decodedImageSize": [IMAGE_SIZE, IMAGE_SIZE],
                    "launch": {"a": "off", "b": "off"}, "sequence": sequence,
                    "burstDelaySeconds": 2, "expectedStepAccepted": accepted,
                    "expectedTransitions": transitions, "roiRects": RECTS,
                    "expectedCaptures": {"scene-ready-window.png": before,
                                         "scene-after-window.png": after},
                    "channelTolerance": TOLERANCE, "minimumCorrectFraction": CORRECT_FRACTION,
                    "captureMapping": "centered orthographic cover",
                    "boundary": "pending intent plus final pixels; no official parity or decode timing claim"}
        project, entries = fixture_entries()
        project_bytes, package = encoded(project), make_package(list(entries.items()))
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-deferred-property-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            (content / "project.json").write_bytes(project_bytes)
            (content / "scene.pkg").write_bytes(package)
            (root / "preregistration.json").write_bytes(encoded(protocol))
            input_paths = (content / "project.json", content / "scene.pkg")
            input_hashes = file_hashes(input_paths)
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home),
                       MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                       "--mwx-debug-scene-duration", "9", "--mwx-debug-scene-after-snapshot-delay", "7",
                       "--mwx-debug-scene-evidence-dir", str(evidence),
                       "--mwx-debug-scene-properties-json", json.dumps(protocol["launch"]),
                       "--mwx-debug-scene-live-property-sequence-json", json.dumps(sequence),
                       "--mwx-debug-scene-live-property-burst"]
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                        "inputSHA256": input_hashes,
                        "entrySHA256": {name: hashlib.sha256(value).hexdigest()
                                        for name, value in entries.items()},
                        "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
            (root / "prerun.json").write_bytes(encoded(identity))
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                for name, colors in protocol["expectedCaptures"].items():
                    self.assertTrue((evidence / name).is_file(), (name, log[-5000:]))
                    pixels[name] = measure_capture(evidence / name, colors)
                self.assertEqual(result.returncode, 0, log[-5000:])
                self.assertRegex(preview, r"prepared static base resources: entries=0 [^\n]*deferred=2 loaded=0 failed=0")
                actual_transitions = re.findall(
                    r"schema=deferred-property-transition-v1 generation=(\d+) layers=([\d,]+) state=(\S+)", log)
                self.assertEqual(actual_transitions, transitions, log[-8000:])
                steps = re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log)
                self.assertEqual(steps, [(str(i), value) for i, value in enumerate(accepted)], log[-5000:])
                updates = re.findall(r"phase=live-property-update accepted=(true|false) surfacesBefore=(\d+) surfacesAfter=(\d+) windowsBefore=(\S+) windowsAfter=(\S+)", log)
                self.assertEqual([update[0] for update in updates], accepted)
                self.assertTrue(all(u[1] == u[2] == "1" and u[3] == u[4] for u in updates), updates)
                self.assertEqual(log.count("phase=session-candidate "), 1, log[-5000:])
                self.assertEqual(log.count("phase=session-activated "), 1, log[-5000:])
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                for reason in ("ready", "after"):
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-(?:failed|rejected)")
                for name, measurement in pixels.items():
                    for roi, value in measurement["rois"].items():
                        with self.subTest(capture=name, roi=roi):
                            self.assertGreater(value["total"], 0, value)
                            self.assertGreaterEqual(value["correct"] / value["total"], CORRECT_FRACTION, value)
                            self.assertTrue(all(abs(a - b) <= TOLERANCE for a, b in
                                                zip(value["centerRGB"], value["expectedRGB"])), value)
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                self.assertEqual(file_hashes(input_paths), input_hashes)
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

    def test_independent_edits_commit_both_pending_layers(self):
        self.run_case([{"a": "on"}, {"b": "on"}], (True, True), [
            ("1", "11", "pending"), ("1", "11", "superseded"),
            ("2", "11,22", "pending"), ("2", "11,22", "committed")], ["true", "true"])

    def test_partial_cancel_preserves_other_pending_layer(self):
        self.run_case([{"a": "on", "b": "on"}, {"a": "off"}], (False, True), [
            ("1", "11,22", "pending"), ("1", "11,22", "superseded"),
            ("2", "22", "pending"), ("2", "22", "committed")], ["true", "true"])

    def test_same_key_cancel_keeps_both_layers_hidden(self):
        self.run_case([{"a": "on"}, {"a": "off"}], (False, False), [
            ("1", "11", "pending"), ("1", "11", "superseded")], ["true", "true"])

    def test_invalid_edit_retains_previous_accepted_intent(self):
        # An unknown key has no live consumer. A combo string outside its UI
        # options merely fails its condition and is not a rejection oracle.
        self.run_case([{"a": "on"}, {"b_missing": "on"}], (True, False), [
            ("1", "11", "pending"), ("1", "11", "committed")], ["true", "false"])


if __name__ == "__main__":
    unittest.main()
