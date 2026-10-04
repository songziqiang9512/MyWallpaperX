"""Delayed text publication redraws a frozen host frame without VM replay.

The pixel oracle is a serial static NEW TEXT control from the same frozen App.
Both fixtures and their solid model are authored here; fonts use a system alias.
Only the ready readback is required while paused. A later after request can
terminate at teardown because this fixture schedules no further invalidation.
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
from .test_scene_composition_authored_order_integration import encoded
from .test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from .test_scene_pkg_cache_extractor import make_package


SCRIPT = """export function init(value) {
    shared.textInitializations=(shared.textInitializations||0)+1;
    if(shared.textInitializations!==1) throw Error('paused-text-init-replayed');
    return 'NEW TEXT';
}
export function update(value) {
    shared.textUpdates=(shared.textUpdates||0)+1;
    if(shared.textUpdates>1) throw Error('paused-text-update-replayed');
    return value;
}
"""
PROTOCOL = {"canvas": [256, 256], "surfaces": 2, "requestedDurationSeconds": 6,
            "pausedRasterDelaySeconds": 2, "requiredCapture": "scene-ready-window.png",
            "whiteCoreMinimumChannel": 240, "whiteCoreChannelSpread": 4,
            "minimumWhitePixels": 100, "minimumGreenPixels": 20,
            "comparison": "exact dimensions, white pixel count, bounding box and white-mask SHA256",
            "evidenceBoundary": "first selected surface pixels; both surfaces GPU completion; no official parity"}


def fixture_entries(paused):
    scene = {"version": 3, "general": {"orthogonalprojection": {"width": 256, "height": 256},
                                       "clearcolor": "0 0 0"}, "objects": [
        {"id": 11, "name": "Owned paused text", "text": {"value": "OLD", "script": SCRIPT} if paused else "NEW TEXT",
         "font": "systemfont_arial", "pointsize": 8, "origin": "128 128 0", "size": "220 80",
         "color": "1 1 1", "horizontalalign": "center", "verticalalign": "center", "padding": 0},
        {"id": 30, "name": "Healthy green peer", "image": "models/own_solid.json",
         "origin": "192 184 0", "size": "16 16", "color": "0 1 0"}]}
    return {"type": "scene", "file": "scene.json"}, {
        "scene.json": encoded(scene),
        "models/own_solid.json": encoded({"solidlayer": True, "width": 256, "height": 256})}


def measure(path):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"invalid capture: {path}")
    width, height, rows = decoded
    mask = bytearray(width * height)
    xs, ys, green = [], [], 0
    for y, row in enumerate(rows):
        for x in range(width):
            r, g, b = row[x * 3:x * 3 + 3]
            if min(r, g, b) >= 240 and max(r, g, b) - min(r, g, b) <= 4:
                mask[y * width + x] = 1
                xs.append(x); ys.append(y)
            green += r <= 4 and g >= 251 and b <= 4
    return {"dimensions": [width, height], "whiteCount": len(xs), "greenCount": green,
            "whiteBounds": [min(xs), min(ys), max(xs), max(ys)] if xs else None,
            "whiteMaskSHA256": hashlib.sha256(mask).hexdigest()}


class ScenePausedTextIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires an explicitly frozen Debug executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def run_scene(self, paused):
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-paused-text-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir(); home.mkdir()
            project, entries = fixture_entries(paused)
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            inputs = (content / "project.json", content / "scene.pkg")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence)]
            if paused:
                command.append("--mwx-debug-scene-start-paused")
            env = os.environ.copy()
            for key in tuple(env):
                if key.startswith("MWX_SCENE_DEBUG_"):
                    env.pop(key)
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="2",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            if paused:
                env["MWX_SCENE_DEBUG_TEXT_RASTER_DELAY"] = "2"
            identity = {"command": command, "paused": paused, "protocol": PROTOCOL,
                "appSHA256": self.frozen_app_hashes, "inputSHA256": file_hashes(inputs),
                "entrySHA256": {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()},
                "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
            (root / "prerun.json").write_bytes(encoded(identity))
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertNotRegex(log, r"failure=exception|paused-text-(?:init|update)-replayed|phase=launch-failed")
                self.assertRegex(log, r"phase=ready [^\n]*surfaces=2 ")
                self.assertIn("phase=stopped surfacesBefore=2 surfacesAfter=0", log)
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"phase=snapshot reason=ready request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-failed reason=ready ")
                pixels = measure(evidence / PROTOCOL["requiredCapture"])
                self.assertGreater(pixels["whiteCount"], PROTOCOL["minimumWhitePixels"], pixels)
                self.assertGreater(pixels["greenCount"], PROTOCOL["minimumGreenPixels"], pixels)
                completed = [tuple(map(int, row)) for row in re.findall(
                    r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)]
                self.assertEqual(len({surface for _, surface in completed}), 2, log[-6000:])
                if paused:
                    self.assertTrue(completed and all(frame == 0 for frame, _ in completed), completed)
                    self.assertGreaterEqual(len(completed), 4, completed)
                    publication_offset = log.index("phase=dynamic-text-published layer=11 ")
                    redrawn = [tuple(map(int, row)) for row in re.findall(
                        r"state=completed frame=(\d+) surface=(\d+) gpu=completed",
                        log[publication_offset:])]
                    self.assertEqual({surface for _, surface in redrawn},
                                     {surface for _, surface in completed}, redrawn)
                    self.assertIn("phase=frame-driver-start paused=true", log)
                    self.assertNotIn("phase=frame-driver-start paused=false", log)
                    self.assertEqual(len(re.findall(r"phase=dynamic-text-published layer=11 generation=\d+ ", log)), 2)
                    self.assertEqual(len(re.findall(r"target=text\(layerID: 11,[^\n]*callback=completed inputUTF8Bytes=\d+ outputUTF8Bytes=8 route=generic-only", log)), 1)
                self.assertEqual(file_hashes(inputs), identity["inputSHA256"])
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), identity["testSHA256"])
                return pixels
            except subprocess.TimeoutExpired as error:
                log = "".join(value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                              for value in (error.stdout, error.stderr))
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity.update(appSHA256After=app_hashes(self.app), inputSHA256After=file_hashes(inputs))
                (root / "identity.json").write_bytes(encoded(identity))
                (root / "pixels.json").write_bytes(encoded(pixels))
                (root / "app.log").write_text(log)
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName / ("paused" if paused else "control")
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")

    def test_delayed_text_publication_redraws_both_paused_surfaces_without_vm_replay(self):
        control = self.run_scene(False)
        paused = self.run_scene(True)
        for key in ("dimensions", "whiteCount", "whiteBounds", "whiteMaskSHA256"):
            with self.subTest(measurement=key):
                self.assertEqual(paused[key], control[key], (paused, control))
