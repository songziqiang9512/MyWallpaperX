"""Real Host/QuickJS/Metal integration; set MWX_SCENE_INTEGRATION_APP to a frozen Debug executable.

Replaces the old all-surface rollback source-shape assertions. Unit coverage for
provider generations, input/timers, storage and source FIFO remains in its owner
modules; this gate verifies their Host presentation boundary with actual output.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

from .test_scene_pkg_cache_extractor import make_package


class SceneFramePresentationIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not app:
            raise unittest.SkipTest("requires an explicitly staged Debug executable")
        cls.app = Path(app).resolve(strict=True)
        cls.probe_temp = tempfile.TemporaryDirectory(prefix="mwx-compositor-pixel-probe-")
        probe = Path(cls.probe_temp.name)
        source = probe / "probe.swift"
        cls.pixel_probe = probe / "probe"
        source.write_text(r'''
import Foundation
import CoreGraphics
import ImageIO
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
let green = pixels.withUnsafeMutableBytes { raw -> Int in
    let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return stride(from: 0, to: raw.count, by: 4).filter {
        raw[$0] < 80 && raw[$0 + 1] > 160 && raw[$0 + 2] < 80
    }.count
}
print(Double(green) / Double(image.width * image.height))
''')
        subprocess.run(["xcrun", "swiftc", str(source), "-o", str(cls.pixel_probe)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "probe_temp"):
            cls.probe_temp.cleanup()

    def run_scene(self, screens, fault, switching=False):
        with tempfile.TemporaryDirectory(prefix="mwx-frame-presentation-") as temp:
            root = Path(temp)
            scene = root / "content"
            scene.mkdir()
            (scene / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
            script = """
                export function init(value) {
                    shared.initializations=(shared.initializations||0)+1;
                    if(shared.initializations!==1) throw new Error('duplicate-init');
                    return value;
                }
                export function update(value) {
                    shared.updates=(shared.updates||0)+1;
                    return shared.updates%2===1;
                }
            """
            payload = json.dumps({"version": 3,
                "general": {"orthogonalprojection": {"width": 128, "height": 128}},
                "objects": [
                    {"id": 1, "name": "Shared callback state", "image": "models/util/solidlayer.json",
                     "origin": "64 64 0", "size": "64 64", "color": "1 0 0",
                     "visible": {"value": True, "script": script}},
                    {"id": 2, "name": "Stable peer", "image": "models/util/solidlayer.json",
                     "origin": "100 100 0", "size": "16 16", "color": "0 1 0"},
                ]}).encode()
            (scene / "scene.pkg").write_bytes(make_package([("scene.json", payload)]))
            home = root / "home"
            home.mkdir()
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home),
                       MWX_SCENE_DEBUG_SURFACE_COUNT=str(screens))
            env.pop("MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE", None)
            env.pop("MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES", None)
            env.pop("MWX_SCENE_DEBUG_REJECT_FRAME_ONCE", None)
            env.update(fault)
            command = [str(self.app), "--mwx-debug-scene-root", str(scene),
                "--mwx-debug-scene-duration", "7", "--mwx-debug-scene-evidence-dir", str(root / "evidence")]
            log, result = "", None
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
                log = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, log[-5000:])
                self.assertNotIn("duplicate-init", log)
                self.assertNotIn("phase=launch-failed", log)
                self.assertRegex(log, rf"phase=ready .*surfaces={screens} ")
                self.assertIn(f"phase=stopped surfacesBefore={screens} surfacesAfter=0", log)
                values = re.findall(r"dynamic-layer-visibility-v1 frame=(\d+) generation=(\d+) layer=1 source=sceneScript value=(true|false)", log)
                self.assertGreater(len(values), 20, log[-5000:])
                frames = [int(row[0]) for row in values]
                if not switching:
                    self.assertEqual(frames, sorted(set(frames)), "executed state was replayed for one frame")
                for frame, generation, value in values:
                    self.assertEqual(int(generation), int(frame) + 1)
                    self.assertEqual(value, "true" if int(frame) % 2 == 0 else "false")
                completed = {(int(frame), int(surface)) for frame, surface in re.findall(
                    r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)}
                self.assertTrue(any(frame == 2 for frame, _ in completed), log[-5000:])
                # Real final compositor capture, in addition to command completion.
                captures = list((root / "evidence").glob("*-window.png"))
                self.assertTrue(captures)
                for capture in captures:
                    green_fraction = float(subprocess.check_output([str(self.pixel_probe), str(capture)], text=True))
                    self.assertGreater(green_fraction, 0.005, f"stable green layer missing from terminal compositor: {capture.name}")
                return log, completed
            except subprocess.TimeoutExpired as error:
                log = "".join(value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                              for value in (error.stdout, error.stderr))
                raise
            finally:
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName
                    saved.mkdir(parents=True, exist_ok=True)
                    (saved / "app.log").write_text(log)
                    (saved / "run.json").write_text(json.dumps({"command": command,
                        "returncode": result.returncode if result is not None else None,
                        "screens": screens, "fault": fault}, indent=2) + "\n")
                    for source in (root / "evidence").rglob("*"):
                        if source.is_file():
                            target = saved / source.relative_to(root / "evidence")
                            target.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copy2(source, target)
                    for name in ("project.json", "scene.pkg"):
                        shutil.copy2(scene / name, saved / name)

    def test_missing_drawable_keeps_peer_playing_and_recovers_latest(self):
        log, completed = self.run_scene(2, {"MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES": "2"})
        missing = re.findall(r"phase=drawable-unavailable frame=(\d+) surface=(\d+)", log)
        self.assertEqual([int(frame) for frame, _ in missing], [0, 1])
        absent = int(missing[0][1])
        self.assertTrue(any(frame == 0 and surface != absent for frame, surface in completed))
        self.assertNotIn((0, absent), completed)
        self.assertIn((2, absent), completed)

    def test_post_prepare_failure_does_not_replay_shared_heap(self):
        log, completed = self.run_scene(2, {"MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE": "0"})
        rejected = re.search(r"state=rejected frame=0 surface=(\d+) totalSurfaces=2", log)
        self.assertIsNotNone(rejected)
        absent = int(rejected[1])
        self.assertNotIn((0, absent), completed)
        self.assertIn((1, absent), completed)
        self.assertTrue(any(frame == 0 and surface != absent for frame, surface in completed))

    def test_all_outputs_missing_still_consume_each_simulation_once(self):
        log, completed = self.run_scene(1, {"MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES": "2"})
        self.assertFalse(any(frame < 2 for frame, _ in completed))
        self.assertRegex(log, r"phase=drawable-unavailable frame=0")
        self.assertRegex(log, r"phase=drawable-unavailable frame=1")

    def test_both_surface_seal_rejections_consume_once_and_recover(self):
        log, completed = self.run_scene(2, {"MWX_SCENE_DEBUG_REJECT_FRAME_ONCE": "0"})
        self.assertEqual(len(re.findall(r"phase=frame-seal-fault state=rejected frame=0 submitted=false", log)), 2)
        self.assertFalse(any(frame == 0 for frame, _ in completed), log[-5000:])
        recovered = {surface for frame, surface in completed if frame == 1}
        self.assertEqual(len(recovered), 2, log[-5000:])
        self.assertEqual({surface for frame, surface in completed if frame == 2}, recovered)

    def test_switch_promotes_only_after_candidate_gpu_completion(self):
        log, _ = self.run_scene(1, {"MWX_SCENE_DEBUG_SCENE_SWITCH_AFTER": "2"}, switching=True)
        promoted = re.findall(r"phase=session-activated session=(\S+) previous=(\S+) surfaces=1", log)
        self.assertEqual(len(promoted), 2, log[-7000:])
        original, replacement = promoted[0][0], promoted[1][0]
        self.assertEqual(promoted[1][1], original)
        first = log.index(f"phase=session-first-frame session={replacement}")
        promotion = log.index(f"phase=session-activated session={replacement}")
        retirement = log.index(f"phase=session-retiring session={original}")
        self.assertLess(first, promotion)
        self.assertLess(promotion, retirement)
        self.assertIn("phase=scene-switch state=triggered accepted=true", log)

    def test_candidate_rejection_retains_existing_native_windows_and_clock(self):
        log, _ = self.run_scene(1, {"MWX_SCENE_DEBUG_SCENE_SWITCH_AFTER": "2",
            "MWX_SCENE_DEBUG_REJECT_CANDIDATE_GENERATION": "2"}, switching=True)
        self.assertEqual(log.count("phase=session-activated"), 1, log[-7000:])
        self.assertIn("phase=candidate-rejected-after-gpu", log)
        self.assertRegex(log, r"phase=scene-switch state=triggered accepted=false .*preserved=true running=true")
