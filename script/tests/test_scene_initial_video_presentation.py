"""Actual ordinary-video startup: requires MWX_SCENE_INTEGRATION_APP and screen capture permission.

Uses self-owned media and an isolated HOME. Window pixels come from the actual
ready window, not a fake provider or a late warm-source rendering harness.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

from .test_scene_material_video_asset import video_tex
from .test_scene_pkg_cache_extractor import make_package


class SceneInitialVideoPresentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not app or sys.platform != "darwin" or not shutil.which("ffmpeg"):
            raise unittest.SkipTest("requires frozen Debug App, macOS capture and ffmpeg")
        cls.app = Path(app).resolve(strict=True)
        cls.app_sha = hashlib.sha256(cls.app.read_bytes()).hexdigest()
        cls.probe_temp = tempfile.TemporaryDirectory(prefix="mwx-initial-video-color-")
        cls.addClassCleanup(cls.probe_temp.cleanup)
        source = Path(cls.probe_temp.name) / "probe.swift"
        cls.pixel_probe = Path(cls.probe_temp.name) / "probe"
        source.write_text(r'''
import Foundation
import CoreGraphics
import ImageIO
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
let stats = bytes.withUnsafeMutableBytes { raw -> [String: Double] in
    let context = CGContext(data: raw.baseAddress, width: 32, height: 32,
        bitsPerComponent: 8, bytesPerRow: 32 * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    var red = 0, cyan = 0
    for i in stride(from: 0, to: raw.count, by: 4) {
        if raw[i] > 160 && raw[i+1] < 80 && raw[i+2] < 80 { red += 1 }
        if raw[i] < 80 && raw[i+1] > 160 && raw[i+2] > 160 { cyan += 1 }
    }
    return ["red": Double(red) / 1024, "cyan": Double(cyan) / 1024]
}
print(String(data: try! JSONSerialization.data(withJSONObject: stats), encoding: .utf8)!)
''')
        subprocess.run(["xcrun", "swiftc", str(source), "-o", str(cls.pixel_probe)],
                       check=True, capture_output=True, timeout=60)

    def run_video(self, *, paused, renamed=False, screens=1, terminal=False):
        with tempfile.TemporaryDirectory(prefix="mwx-initial-video-presentation-") as temporary:
            root = Path(temporary)
            scene = root / "scene"
            scene.mkdir()
            clip = root / "red.mp4"
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "color=c=red:s=32x24:r=30:d=3", "-an", "-c:v", "libx264",
                "-pix_fmt", "yuv420p", str(clip)], check=True, capture_output=True, timeout=20)
            payload = clip.read_bytes()
            movie_id, hidden_id = (71, 97) if renamed else (1, 3)
            stem = "alternate/nested-renamed" if renamed else "owned/clip"
            model, material = "models/owned-video.json", "materials/owned-video.json"
            # Publish the paused invocation count through an actual scalar
            # consumer. A repeated callback makes cyan alpha <= 0.5, which
            # cannot satisfy the unchanged cyan pixel gate on red or gray.
            counter_alpha = "thisScene.getLayer('Cyan peer').alpha=1/shared.frames;" if paused else ""
            script = ("export function update(value) { shared.frames=(shared.frames||0)+1; "
                      + counter_alpha + " return true; }")
            objects = [
                {"id": movie_id, "name": "Renamed movie" if renamed else "Own red video",
                 "image": model, "origin": "64 64 0", "size": "128 96",
                 "visible": {"value": True, "script": script}},
                {"id": 2, "name": "Cyan peer", "image": "models/util/solidlayer.json",
                 "origin": "112 112 0", "size": "24 24", "color": "0 1 1"},
                {"id": hidden_id, "name": "Hidden truncated video", "image": "models/hidden.json",
                 "origin": "64 64 0", "size": "128 96", "visible": False},
            ]
            entry = {"version": 3, "general": {"orthogonalprojection": {"width": 128, "height": 128}},
                     "objects": objects}
            entries = [("scene.json", json.dumps(entry).encode()),
                (model, json.dumps({"material": material}).encode()),
                (material, json.dumps({"passes": [{"shader": "genericimage2", "textures": [stem]}]}).encode()),
                ("materials/" + stem + ".tex", video_tex(payload[:512] if terminal else payload)),
                ("models/hidden.json", json.dumps({"material": "materials/hidden.json"}).encode()),
                ("materials/hidden.json", json.dumps({"passes": [{"shader": "genericimage2",
                                                           "textures": ["owned/hidden"]}]}).encode()),
                ("materials/owned/hidden.tex", video_tex(payload[:512]))]
            (scene / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
            (scene / "scene.pkg").write_bytes(make_package(entries))
            home, evidence = root / "home", root / "evidence"
            home.mkdir()
            evidence.mkdir()
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT=str(screens))
            command = [str(self.app), "--mwx-debug-scene-root", str(scene),
                "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence)]
            if paused:
                command.append("--mwx-debug-scene-start-paused")
            handle = (root / "app.log").open("w")
            process = subprocess.Popen(command, env=env, stdout=handle, stderr=subprocess.STDOUT)
            screenshot = root / "window.png"
            try:
                deadline = time.monotonic() + 20
                while process.poll() is None and time.monotonic() < deadline:
                    log = (root / "app.log").read_text()
                    window = re.search(r"phase=ready .*windows=(\d+)", log)
                    if window:
                        subprocess.run(["screencapture", "-x", "-l" + window[1], str(screenshot)],
                                       check=True, capture_output=True, timeout=10)
                        break
                    time.sleep(0.1)
                self.assertTrue(screenshot.exists(), (root / "app.log").read_text()[-8000:])
                self.assertEqual(process.wait(timeout=20), 0)
                log = (root / "app.log").read_text()
                self.assertNotIn("phase=launch-failed", log)
                self.assertNotRegex(log, r"MWX SceneScript VM:.*(?:failure=|callback=rejected)")
                self.assertIn(f"phase=stopped surfacesBefore={screens} surfacesAfter=0 gpuDrained=true", log)
                pending = re.findall(r"phase=initial-video-presentation attempt=(\d+) frame=(\d+) "
                    r"surfaces=(\d+) qualified=(\d+) held=(true|false) pending=([^\n]*)", log)
                self.assertTrue(pending, log[-8000:])
                self.assertTrue(any(row[4] == "false" and str(movie_id) in row[5].split(",") for row in pending))
                self.assertTrue(any(row[2:5] == (str(screens), str(screens), "true") for row in pending))
                self.assertFalse(any(str(hidden_id) in row[5].split(",") for row in pending))
                activation = log.index("phase=session-activated")
                if not terminal:
                    publication = re.search(rf"video-frame-v1 layer={movie_id} .*generation=1 ", log)
                    self.assertIsNotNone(publication, log[-8000:])
                    self.assertLess(publication.start(), activation)
                else:
                    self.assertNotRegex(log, rf"video-frame-v1 layer={movie_id} ")
                if paused:
                    visibility = re.findall(rf"dynamic-layer-visibility-v1 frame=(\d+) .*layer={movie_id} source=sceneScript", log)
                    self.assertEqual(visibility, ["0"])
                    self.assertEqual({row[1] for row in pending}, {"0"})
                # Window PNGs carry the display ICC profile. Convert to sRGB
                # before comparing authored red/cyan; ffmpeg ignores this ICC.
                colors = json.loads(subprocess.check_output([str(self.pixel_probe), str(screenshot)], text=True))
                self.assertGreater(colors["cyan"], 0.005)
                if terminal:
                    self.assertLess(colors["red"], 0.01)
                else:
                    self.assertGreater(colors["red"], 0.7)
                self.assertEqual(hashlib.sha256(self.app.read_bytes()).hexdigest(), self.app_sha)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
                handle.close()
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName
                    saved.mkdir(parents=True, exist_ok=True)
                    for source in (root / "app.log", screenshot, scene / "project.json", scene / "scene.pkg", evidence / "scene-preview.log", evidence / "scene-runtime-evidence.json"):
                        if source.exists():
                            shutil.copy2(source, saved / source.name)
                    (saved / "run.json").write_text(json.dumps({"command": command,
                        "exit": process.returncode, "sha256": self.app_sha, "paused": paused,
                        "screens": screens, "terminal": terminal, "renamed": renamed,
                        "paused_counter_consumer": "Cyan peer alpha=1/shared.frames" if paused else None}, indent=2) + "\n")

    def test_cold_paused_waits_for_real_video_without_repeating_vm(self):
        self.run_video(paused=True)

    def test_renamed_video_two_surfaces_qualify_one_actual_attempt(self):
        self.run_video(paused=False, renamed=True, screens=2)

    def test_failed_visible_video_remains_local_fallback(self):
        self.run_video(paused=True, terminal=True)
