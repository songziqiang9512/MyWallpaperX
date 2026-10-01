"""Actual App terminal color/history and paused resize; explicitly staged Debug App only."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_pkg_cache_extractor import make_package


class ScenePersistentColorIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not app:
            raise unittest.SkipTest("requires an explicitly frozen Debug executable")
        cls.app = Path(app).resolve(strict=True)

    def run_color(self, once=False, resize=False, clear=False, app=None, expected_color=(191, 64, 128)):
        visibility = {"value": True, "script": "export function update(value){shared.ticks=(shared.ticks||0)+1; return shared.ticks===1;}"} if once else True
        scene = {"version": 3, "general": {"orthogonalprojection": {"width": 128, "height": 128}, "clearcolor": "0 0 0", "clearenabled": clear, "hdr": True},
                 "objects": [{"id": 1, "name": "HDR source", "image": "models/util/solidlayer.json", "origin": "64 64 0", "size": "64 64", "color": "1 0.25 0.5", "visible": visibility},
                             {"id": 2, "name": "Stable green peer", "image": "models/util/solidlayer.json", "origin": "110 110 0", "size": "12 12", "color": "0 1 0"}]}
        if resize:
            scene["objects"].append({"id": 3, "name": "Offscreen callback witness", "image": "models/util/solidlayer.json", "origin": "1000 1000 0", "size": "1 1", "visible": {"value": True, "script": "export function update(value){shared.frames=(shared.frames||0)+1; return shared.frames%2===1;}"}})
        with tempfile.TemporaryDirectory(prefix="mwx-persistent-color-app-") as temp:
            root = Path(temp)
            content = root / "content"
            content.mkdir()
            payload = json.dumps(scene, sort_keys=True, separators=(",", ":")).encode()
            (content / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
            (content / "scene.pkg").write_bytes(make_package([("scene.json", payload)]))
            home = root / "home"
            home.mkdir()
            evidence = root / "evidence"
            env = os.environ.copy()
            for key in ("MWX_SCENE_DEBUG_SURFACE_COUNT", "MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES", "MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE", "MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER"):
                env.pop(key, None)
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home))
            command = [str(app or self.app), "--mwx-debug-scene-root", str(content), "--mwx-debug-scene-duration", "8", "--mwx-debug-scene-evidence-dir", str(evidence)]
            if resize:
                env["MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER"] = "1.5:3"
                command.extend(["--mwx-debug-scene-resize-sequence", "2:0.5,3:1"])
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            captures = list(evidence.glob("*-window.png"))
            if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                saved = Path(destination) / self._testMethodName
                saved.mkdir(parents=True, exist_ok=True)
                (saved / "app.log").write_text(log)
                (saved / "scene.json").write_bytes(payload)
                for capture in captures:
                    shutil.copy2(capture, saved / capture.name)
            self.assertEqual(result.returncode, 0, log[-6000:])
            self.assertNotIn("failure=exception", log)
            self.assertIn("gpuDrained=true", log)
            self.assertRegex(log, r"state=completed frame=\d+ surface=\d+ gpu=completed")
            self.assertGreaterEqual(len(captures), 2)
            measurements = {}
            for capture in captures:
                decoded = png_rgb_pixels(capture)
                self.assertIsNotNone(decoded)
                width, height, rows = decoded
                # Author layer tint is normalized to [0, 1]; M(1)=0.75.
                # The float owner gate separately exercises superwhite inputs.
                # The preserved 16-bit PNG is reduced only for this broad
                # display oracle; the owner GPU gate checks float precision.
                center = rows[height // 2][(width // 2) * 3:(width // 2) * 3 + 3]
                for actual, expected in zip(center, expected_color):
                    self.assertLessEqual(abs(actual - expected), 1, (capture.name, list(center)))
                def is_hdr(pixel):
                    return all(abs(actual - expected) <= 1 for actual, expected in zip(pixel, expected_color))
                horizontal = [x for x in range(width) if is_hdr(rows[height // 2][x * 3:x * 3 + 3])]
                vertical = [y for y in range(height) if is_hdr(rows[y][(width // 2) * 3:(width // 2) * 3 + 3])]
                self.assertTrue(horizontal and vertical)
                measurements[capture.name] = {"size": (width, height), "bounds": (min(horizontal), max(horizontal), min(vertical), max(vertical))}
            if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                (Path(destination) / self._testMethodName / "oracles.json").write_text(json.dumps(measurements, indent=2) + "\n")
            return log, measurements

    def test_continuous_hdr_is_mapped_once(self):
        self.run_color()

    def test_clear_true_preserves_terminal_mapping_at_surface_extent(self):
        self.run_color(clear=True)

    def test_draw_once_then_hidden_retains_unmapped_history(self):
        log, _ = self.run_color(once=True)
        self.assertRegex(log, r"frame=0 .*layer=1 source=sceneScript value=true")
        self.assertRegex(log, r"frame=1 .*layer=1 source=sceneScript value=false")

    def test_paused_resize_redraws_current_snapshot_without_vm_advance(self):
        log, captures = self.run_color(resize=True)
        paused = log.index("phase=pause-resume state=paused accepted=true")
        resumed = log.index("phase=pause-resume state=resumed accepted=true")
        # Resume synchronously starts the driver before its accepted log;
        # the next VM update is legal once playback-state requests resumed.
        resume_requested = log.index("phase=playback-state requested=resumed", paused)
        middle = log[paused:resume_requested]
        self.assertIn("phase=surface-resize index=0 scale=0.5000 accepted=true", middle)
        self.assertIn("phase=surface-resize index=1 scale=1.0000 accepted=true", middle)
        self.assertNotRegex(middle, r"layer=3 source=sceneScript")
        resize_work = middle[middle.index("phase=surface-resize index=0"):]
        completed = re.findall(r"diagnostic=scene-color-completed frame=(\d+) allocation=(\d+) member=\d+ authoredDraw=true mapped=true", resize_work)
        self.assertEqual(len(completed), 2)
        self.assertEqual(len({frame for frame, _ in completed}), 1)
        self.assertEqual(len({allocation for _, allocation in completed}), 2)
        self.assertRegex(log[:paused], r"layer=3 source=sceneScript")
        self.assertRegex(log[resumed:], r"layer=3 source=sceneScript")
        ready = captures["scene-ready-window.png"]
        half = captures["scene-resize-00-window.png"]
        restored = captures["scene-resize-01-window.png"]
        full = ready["size"]
        self.assertEqual(half["size"], (full[0] // 2, full[1] // 2))
        self.assertEqual(restored["size"], full)
        for original, resized in zip(ready["bounds"], half["bounds"]):
            self.assertLessEqual(abs(original / 2 - resized), 1)
        self.assertEqual(restored["bounds"], ready["bounds"])

    def test_missing_optional_mapping_exports_safe_raw(self):
        fault_app = os.environ.get("MWX_SCENE_MAPPING_FAILURE_APP")
        if not fault_app:
            self.skipTest("requires an isolated signed App with only mapping functions removed")
        log, _ = self.run_color(once=True, app=Path(fault_app).resolve(strict=True), expected_color=(255, 64, 128))
        self.assertIn("MWX Scene display mapping: default library functions unavailable", log)
        self.assertRegex(log, r"diagnostic=scene-color-completed frame=[1-9]\d* .*mapped=false")
        self.assertNotRegex(log, r"diagnostic=scene-color-completed .*mapped=true")
