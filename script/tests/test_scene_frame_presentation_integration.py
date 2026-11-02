"""Real Host/QuickJS/Metal integration; set MWX_SCENE_INTEGRATION_APP to a frozen Debug executable.

Replaces the old all-surface rollback source-shape assertions. Unit coverage for
provider generations, input/timers, storage and source FIFO remains in its owner
modules; this gate verifies their Host presentation boundary with actual output.
"""
from pathlib import Path
import json
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

from .scene_pkg_fixture import make_package


def compile_pixel_probe(probe: Path) -> Path:
    source, binary = probe / "probe.swift", probe / "probe"
    source.write_text(r'''
import Foundation
import CoreGraphics
import ImageIO
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let sprite = CommandLine.arguments.dropFirst(2).first == "sprite"
let cyanOnly = CommandLine.arguments.dropFirst(2).first == "cyan"
let magentaOnly = CommandLine.arguments.dropFirst(2).first == "magenta"
var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
let green = pixels.withUnsafeMutableBytes { raw -> Int in
    let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return stride(from: 0, to: raw.count, by: 4).filter {
        magentaOnly ? raw[$0] > 160 && raw[$0 + 1] < 80 && raw[$0 + 2] > 160
            : cyanOnly ? raw[$0] < 80 && raw[$0 + 1] > 160 && raw[$0 + 2] > 160
            : sprite ? raw[$0 + 2] > 160 && ((raw[$0] > 160 && raw[$0 + 1] < 80)
            || (raw[$0] < 80 && raw[$0 + 1] > 160))
            : raw[$0] < 80 && raw[$0 + 1] > 160 && raw[$0 + 2] < 80
    }.count
}
if CommandLine.arguments.dropFirst(2).first == "lifecycle" {
    let scale = max(Double(image.width) / 256, Double(image.height) / 256)
    func samples(_ rect: [Double], columns: Int, rows: Int) -> [Int] {
        var result: [Int] = []
        for y in 0..<rows { for x in 0..<columns {
            let px = Int((rect[0] + (Double(x) + 0.5) / Double(columns) * (rect[2] - rect[0]) - 128) * scale + Double(image.width) / 2)
            let py = Int((rect[1] + (Double(y) + 0.5) / Double(rows) * (rect[3] - rect[1]) - 128) * scale + Double(image.height) / 2)
            precondition(px >= 0 && px < image.width && py >= 0 && py < image.height, "preregistered lifecycle ROI cropped")
            let offset = (py * image.width + px) * 4
            result += pixels[offset..<offset + 3].map(Int.init)
        } }
        return result
    }
    let property = samples([118, 150, 138, 164], columns: 16, rows: 8)
    let mean = (0..<3).map { channel in
        Double(stride(from: channel, to: property.count, by: 3).reduce(0) { $0 + property[$1] }) / Double(property.count / 3)
    }
    let value: [String: Any] = ["size": [image.width, image.height], "propertyRGB": mean,
        "motionRGB": samples([56, 108, 200, 148], columns: 64, rows: 20)]
    print(String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self))
} else { print(Double(green) / Double(image.width * image.height)) }
''')
    subprocess.run(["xcrun", "swiftc", str(source), "-o", str(binary)], check=True, capture_output=True)
    return binary


class SceneFramePresentationIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not app:
            raise unittest.SkipTest("requires an explicitly staged Debug executable")
        cls.app = Path(app).resolve(strict=True)
        cls.probe_temp = tempfile.TemporaryDirectory(prefix="mwx-compositor-pixel-probe-")
        cls.pixel_probe = compile_pixel_probe(Path(cls.probe_temp.name))

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "probe_temp"):
            cls.probe_temp.cleanup()

    def run_scene(self, screens, fault, switching=False, retiring=False,
                  animation_retirement=False, frozen=False):
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
            if retiring:
                script = """
                    export function update(value) {
                        if (engine.runtime < 0.5) return value;
                        thisScene.destroyLayer('Owned retiring child');
                        thisScene.destroyLayer(thisLayer);
                        return false;
                    }
                """
            objects = [
                {"id": 1, "name": "Shared callback state", "image": "models/util/solidlayer.json",
                 "origin": "64 64 0", "size": "64 64", "color": "1 0 0",
                 "visible": {"value": True, "script": script}},
                {"id": 2, "name": "Stable peer", "image": "models/util/solidlayer.json",
                 "origin": "100 100 0", "size": "16 16", "color": "0 1 0"},
            ]
            if retiring:
                objects += [
                    {"id": 3, "name": "Owned retiring child", "parent": 1,
                     "image": "models/util/solidlayer.json", "origin": "0 0 0",
                     "size": "12 12", "color": "1 0 0", "visible": True},
                    {"id": 4, "name": "Live Bool owner", "image": "models/util/solidlayer.json",
                     "origin": "40 64 0", "size": "12 12", "color": "0 0 1",
                     "visible": {"value": True,
                                 "script": """export function update(value) {
                                     thisScene.destroyLayer('Sprite victim'); return true;
                                 }""" if frozen else "export function update(value) { return true; }"}},
                ]
            entries = []
            if animation_retirement:
                victim = "export function update(value) { return true; }" if frozen else """
                    let a;
                    export function update(value) {
                        if (!a) { a=thisLayer.getTextureAnimation();
                            if (!a || a.frameCount!==2) throw new Error('missing sprite metadata'); }
                        if (engine.runtime >= 0.5) {
                            a.setFrame(1); thisScene.destroyLayer(thisLayer);
                        }
                        return value;
                    }
                """
                peer = """
                    let a;
                    export function update(value) {
                        if (!a) { a=thisLayer.getTextureAnimation();
                            if (!a || a.frameCount!==2) throw new Error('missing hidden sprite metadata');
                            a.pause(); a.setFrame(1); }
                        if (engine.runtime > 0.1 && a.getFrame()!==1)
                            throw new Error('hidden sprite peer lost its paused frame');
                        return engine.runtime > 1.25;
                    }
                """
                objects += [
                    {"id": 5, "name": "Sprite victim", "image": "models/sprite.json",
                     "origin": "64 64 0", "size": "32 32", "visible": {"value": True, "script": victim},
                     "alpha": {"value": 1, "animation": {"c0": [{"frame": 0, "value": 1},
                         {"frame": 60, "value": 1}], "options": {"fps": 30, "length": 60,
                             "mode": "single", "name": "sprite fade"}}}},
                    {"id": 6, "name": "Hidden sprite peer", "image": "models/sprite.json",
                     "origin": "64 64 0", "size": "24 24", "visible": {"value": False, "script": peer}},
                ]
                # Frozen redraw checks atlas UV; rebuild checks per-View multi-image MPS output.
                blocks = [struct.pack("<HHI", color, color, 0) for color in (0xF81F, 0x07FF)]
                width = 8 if frozen else 4
                payloads = [b"".join(blocks)] if frozen else blocks
                frames = [(0, 0.0, 0.5), (0, 0.5, 0.5)] if frozen else [(0, 0.0, 1.0), (1, 0.0, 1.0)]
                atlas = b"TEXV0005\0TEXI0001\0" + struct.pack("<7I", 7, 4, width, 4, width, 4, 0)
                atlas += b"TEXB0002\0" + struct.pack("<I", len(payloads))
                for pixels in payloads:
                    atlas += struct.pack("<6I", 1, width, 4, 0, len(pixels), len(pixels)) + pixels
                atlas += b"TEXS0002\0" + struct.pack("<I", 2)
                for image_index, x, extent in frames:
                    atlas += struct.pack("<If6f", image_index, 0.25, x, 0, extent, 0, 0, 1)
                entries += [("models/sprite.json", json.dumps({"material": "materials/sprite.json"}).encode()),
                    ("materials/sprite.json", json.dumps({"passes": [{"shader": "generic4",
                        "textures": ["materials/sprite.tex"], "combos": {"LIGHTING": 0, "REFLECTION": 0,
                            "NORMALMAP": 0}, "constantshadervalues": {"alpha": 1, "brightness": 1,
                                "color": "1 1 1"}, "blending": "normal", "cullmode": "nocull"}]}).encode()),
                    ("materials/sprite.tex", atlas)]
            payload = json.dumps({"version": 3,
                "general": {"orthogonalprojection": {"width": 128, "height": 128}},
                "objects": objects}).encode()
            (scene / "scene.pkg").write_bytes(make_package([("scene.json", payload), *entries]))
            home = root / "home"
            home.mkdir()
            (root / "tmp").mkdir()
            (root / "cache").mkdir()
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home),
                       TMPDIR=str(root / "tmp"), MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "cache"),
                       MWX_SCENE_DEBUG_SURFACE_COUNT=str(screens))
            env.pop("MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE", None)
            env.pop("MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES", None)
            env.pop("MWX_SCENE_DEBUG_REJECT_FRAME_ONCE", None)
            env.update(fault)
            command = [str(self.app), "--mwx-debug-scene-root", str(scene),
                "--mwx-debug-scene-duration", "7", "--mwx-debug-scene-evidence-dir", str(root / "evidence")]
            if frozen:
                command += ["--mwx-debug-scene-start-paused", "--mwx-debug-scene-resize-sequence", "1:0.8,2:1"]
            log, result = "", None
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
                log = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, log[-5000:])
                self.assertNotIn("duplicate-init", log)
                self.assertNotIn("phase=launch-failed", log)
                self.assertRegex(log, rf"phase=ready .*surfaces={screens} ")
                self.assertIn(f"phase=stopped surfacesBefore={screens} surfacesAfter=0", log)
                self.assertRegex(log, r"phase=stopped[^\n]*gpuDrained=true")
                values = re.findall(r"dynamic-layer-visibility-v1 frame=(\d+) generation=(\d+) layer=1 source=sceneScript value=(true|false)", log)
                if not retiring:
                    self.assertGreater(len(values), 20, log[-5000:])
                    frames = [int(row[0]) for row in values]
                    if not switching:
                        self.assertEqual(frames, sorted(set(frames)), "executed state was replayed for one frame")
                    for frame, generation, value in values:
                        self.assertEqual(int(generation), int(frame) + 1)
                        self.assertEqual(value, "true" if int(frame) % 2 == 0 else "false")
                completed = {(int(frame), int(surface)) for frame, surface in re.findall(
                    r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)}
                self.assertTrue(completed if frozen else any(frame == 2 for frame, _ in completed), log[-5000:])
                # Real final compositor capture, in addition to command completion.
                captures = list((root / "evidence").glob("*-window.png"))
                self.assertTrue(captures)
                for capture in captures:
                    green_fraction = float(subprocess.check_output([str(self.pixel_probe), str(capture)], text=True))
                    self.assertGreater(green_fraction, 0.005, f"stable green layer missing from terminal compositor: {capture.name}")
                    if animation_retirement and (frozen or "surface-rebuild" in capture.name
                        or (capture.name == "scene-after-window.png"
                            and "MWX_SCENE_DEBUG_SURFACE_REBUILD_AFTER" not in fault)):
                        fraction = float(subprocess.check_output([str(self.pixel_probe), str(capture), "sprite"], text=True))
                        if frozen:
                            self.assertGreater(fraction, 0.01, f"frozen Sprite lost its adopted frame: {capture.name}")
                            cyan = float(subprocess.check_output([str(self.pixel_probe), str(capture), "cyan"], text=True))
                            self.assertLess(cyan, 0.001, "frozen atlas frame lost its original UV transform")
                        elif "surface-rebuild-settled" in capture.name:
                            cyan = float(subprocess.check_output([str(self.pixel_probe), str(capture), "cyan"], text=True))
                            magenta = float(subprocess.check_output([str(self.pixel_probe), str(capture), "magenta"], text=True))
                            self.assertGreater(cyan, 0.005, "hidden peer did not resume with its retained Sprite frame")
                            self.assertLess(magenta, 0.001, "destroyed Sprite returned after rebuild")
                        else:
                            self.assertLess(fraction, 0.001, "retired Sprite reappeared in terminal output")
                if animation_retirement:
                    self.assertNotIn("uniformDeclarationInvalid", log)
                    for message in ("missing sprite metadata", "missing hidden sprite metadata",
                                    "hidden sprite peer lost its paused frame"):
                        self.assertNotIn(message, log)
                    self.assertRegex(log, r"textureAnimationCommands=[1-9]\d* callback=committed nextFrame=true")
                    if frozen:
                        self.assertRegex(log, r"dynamic-layer-visibility-v1 frame=0 generation=1 "
                            r"layer=5 source=sceneScript value=true effective=true")
                        self.assertRegex(log, r"dynamic-layer-visibility-v1 frame=0 generation=1 "
                            r"layer=6 source=sceneScript value=false effective=false")
                        self.assertEqual(re.findall(r"phase=owner-effects-admission frame=(\d+)", log), ["0"])
                        self.assertRegex(log, r"lifecycle=layer-retirement owners=1 destroyCallbacks=0 "
                            r"quiescent=1 failures=0 sceneTime=0\.000")
                        before_retirement = log.split("lifecycle=layer-retirement", 1)[0]
                        self.assertEqual(len(set(re.findall(
                            r"state=prepared frame=0 surface=(\d+)", before_retirement))), screens)
                if "MWX_SCENE_DEBUG_SURFACE_REBUILD_AFTER" in fault:
                    observed = {stage: json.loads((root / "evidence" / f"surface-rebuild-{stage}.json").read_text())
                                for stage in ("before", "after", "settled")}
                    before, after, settled = (observed[stage] for stage in ("before", "after", "settled"))
                    self.assertTrue(before["sessionID"] and before["requestID"], observed)
                    for snapshot in observed.values():
                        self.assertEqual(snapshot["sessionID"], before["sessionID"], observed)
                        self.assertEqual(snapshot["requestID"], before["requestID"], observed)
                        self.assertEqual(snapshot["surfaceCount"], screens, observed)
                        self.assertEqual(len(snapshot["spriteAnimationLayerIDsByDisplay"]), screens, observed)
                        self.assertTrue(all(ids == [6] for ids in
                            snapshot["spriteAnimationLayerIDsByDisplay"].values()), observed)
                    self.assertTrue(set(before["windowNumbers"]).isdisjoint(after["windowNumbers"]), observed)
                    self.assertEqual(after["windowNumbers"], settled["windowNumbers"], observed)
                    self.assertGreater(before["sceneTime"], 0.5, observed)
                    self.assertAlmostEqual(before["sceneTime"], after["sceneTime"], places=9, msg=str(observed))
                    for snapshot in (before, after):
                        self.assertTrue(snapshot["isPlaybackPaused"], observed)
                        self.assertFalse(snapshot["isFrameDriverActive"], observed)
                    self.assertFalse(settled["isPlaybackPaused"], observed)
                    self.assertTrue(settled["isFrameDriverActive"], observed)
                    self.assertGreater(settled["sceneTime"], after["sceneTime"], observed)
                    captured, requested = before["capturedTopology"], before["requestedTopology"]
                    self.assertTrue(captured, observed)
                    self.assertEqual([row["displayID"] for row in captured],
                                     [row["displayID"] for row in requested], observed)
                    self.assertNotEqual(captured[0]["frame"], requested[0]["frame"], observed)
                    self.assertAlmostEqual(requested[0]["frame"][0] - captured[0]["frame"][0], 0.5)
                    self.assertAlmostEqual(requested[0]["frame"][2] - captured[0]["frame"][2], -1)
                    self.assertEqual(captured[1:], requested[1:], observed)
                    self.assertTrue({str(row["displayID"]) for row in captured}.issubset(
                        after["spriteAnimationLayerIDsByDisplay"]), observed)
                    for phase in ("after", "settled"):
                        self.assertTrue(any(f"surface-rebuild-{phase}" in path.name for path in captures), observed)
                    self.assertRegex(log, r"phase=surface-rebuild state=rebuilt accepted=true")
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
                        "screens": screens, "fault": fault, "retiring": retiring,
                        "animationRetirement": animation_retirement, "frozen": frozen}, indent=2) + "\n")
                    for source in (root / "evidence").rglob("*"):
                        if source.is_file():
                            target = saved / source.relative_to(root / "evidence")
                            target.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copy2(source, target)
                    for name in ("project.json", "scene.pkg"):
                        shutil.copy2(scene / name, saved / name)

    def test_retired_authored_branch_does_not_reappear_in_visibility_diagnostics(self):
        log, _ = self.run_scene(1, {}, retiring=True)
        self.assertRegex(log,
            r"lifecycle=layer-retirement owners=1 destroyCallbacks=0 quiescent=1 failures=0")
        rows = [(int(frame), int(layer), source, value, effective)
                for frame, layer, source, value, effective in re.findall(
                    r"dynamic-layer-visibility-v1 frame=(\d+) generation=\d+ "
                    r"layer=([1-4]) source=(\w+) value=(true|false) effective=(true|false)", log)]
        cleared = [row for row in rows if row[1:4] == (1, "authored", "true")]
        self.assertTrue(cleared, "retired visibility source never cleared to its authored fallback")
        first_cleared_frame = min(row[0] for row in cleared)
        self.assertTrue(any(frame < first_cleared_frame and layer == 1
                            and (source, value, effective) == ("sceneScript", "true", "true")
                            for frame, layer, source, value, effective in rows), log[-5000:])
        post_retirement = [row for row in rows if row[0] >= first_cleared_frame]
        for layer in (1, 3):
            retired_rows = [row for row in post_retirement if row[1] == layer]
            self.assertTrue(retired_rows, f"missing post-retirement diagnostic for layer {layer}")
            for _, _, source, value, effective in retired_rows:
                self.assertEqual((source, value), ("authored", "true"))
                self.assertEqual(effective, "false",
                    "destroyed authored layer was diagnosed as live after its field source cleared")
        for frame in {row[0] for row in post_retirement}:
            self.assertIn((frame, 2, "authored", "true", "true"), post_retirement)
            self.assertIn((frame, 4, "sceneScript", "true", "true"), post_retirement)

    def test_sprite_retirement_keeps_shared_source_peer_through_pause(self):
        log, _ = self.run_scene(2, {"MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER": "1:2",
            "MWX_SCENE_DEBUG_SURFACE_REBUILD_AFTER": "1.5"},
            retiring=True, animation_retirement=True)
        self.assertRegex(log, r"phase=pause-resume state=paused accepted=true")
        self.assertRegex(log, r"phase=pause-resume state=resumed accepted=true")

    def test_committed_destroy_keeps_paused_adopted_sprite_until_new_simulation(self):
        log, _ = self.run_scene(2, {}, retiring=True, animation_retirement=True, frozen=True)
        self.assertEqual(len(re.findall(r"phase=surface-resize .*accepted=true", log)), 2)

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


class SceneProductDaemonLifecycleIntegrationTests(unittest.TestCase):
    def test_product_daemon_lifecycle(self):
        candidate = os.environ.get("MWX_SCENE_PRODUCT_INTEGRATION_APP")
        if not candidate:
            self.skipTest("requires an explicitly staged signed Debug.Startup App")
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from script.wallpaper_startup_benchmark import (
            STARTUP_BUNDLE_ID, child_processes, finish_selection_process,
            production_preferences_identity, reset_startup_defaults, tree_identity,
        )
        from script.web_benchmark_capture import stage_signed_app, verify_staged_app, discard_staged_app
        from script.web_debug_defaults import make_debug_defaults_suite, delete_debug_defaults_suite, debug_defaults_suites
        app = Path(candidate).resolve(strict=True)
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], STARTUP_BUNDLE_ID)
        production_before = production_preferences_identity()
        root = Path(tempfile.mkdtemp(prefix="mwx-product-scene-lifecycle-"))
        cleanup = None
        try:
            output, home, workshop, scratch = (root / name for name in ("output", "home", "workshop", "tmp"))
            for path in (output, home, workshop, scratch):
                path.mkdir()
            scenes = [workshop / "Scene" / name for name in ("99100001", "99100002")]
            for index, scene in enumerate(scenes):
                scene.mkdir(parents=True)
                project = {"type": "scene", "file": "scene.json"}
                objects = [{"id": 1, "name": "Owned property background", "image": "models/owned-solid.json",
                            "origin": "128 128 0", "size": "256 256", "color": "1 0 0" if index == 0 else "0 0 1"}]
                if index == 0:
                    project["general"] = {"properties": {"gain": {"type": "slider", "value": 0.15, "min": 0, "max": 1}}}
                    objects[0]["alpha"] = {"value": 0.15, "user": "gain"}
                    objects.append({"id": 2, "name": "Owned moving witness", "image": "models/owned-solid.json",
                        "size": "24 24", "color": "1 1 1", "origin": {"value": "64 128 0", "script":
                            "export function update(value) { return new Vec3(64 + (engine.runtime * 32) % 128, 128, 0); }"}})
                document = {"version": 3, "general": {"orthogonalprojection": {"width": 256, "height": 256},
                    "clearcolor": "0 0 0"}, "objects": objects}
                (scene / "project.json").write_text(json.dumps(project))
                (scene / "scene.pkg").write_bytes(make_package([
                    ("scene.json", json.dumps(document).encode()),
                    ("models/owned-solid.json", json.dumps({"solidlayer": True, "width": 256, "height": 256}).encode())]))
            inputs_before = tree_identity(workshop)
            suite, token = make_debug_defaults_suite(), uuid.uuid4().hex
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith(("MWX_", "MYWALLPAPERX_"))}
            environment.update(HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(scratch))
            identity, cleanup, failure = None, None, None
            final_drain_verified = False
            observations = {}
            try:
                binary, identity = stage_signed_app(app / "Contents/MacOS" / info["CFBundleExecutable"], root)
                self.assertEqual(identity["bundle_identifier"], STARTUP_BUNDLE_ID)
                reset_startup_defaults(STARTUP_BUNDLE_ID)
                subprocess.run(["/usr/bin/defaults", "write", STARTUP_BUNDLE_ID,
                    "MWXStartupDefaultsToken", "-string", token], check=True, capture_output=True)
                command = [str(binary), "--mwx-debug-suppress-main-window", "--mwx-debug-workshop-root", str(workshop),
                    "--mwx-debug-user-defaults-suite", suite, "--mwx-debug-startup-defaults-token", token,
                    "--mwx-debug-scene-daemon-client", "--mwx-debug-scene-product-entry", "--mwx-debug-scene-daemon-stable",
                    "--mwx-debug-scene-root", str(scenes[0]), "--mwx-debug-scene-startup-second-root", str(scenes[1]),
                    "--mwx-debug-scene-startup-mode", "lifecycle", "--mwx-debug-scene-startup-report", str(output / "native.json"),
                    "--mwx-debug-scene-duration", "40", "--mwx-debug-scene-performance-fps", "30",
                    "--mwx-debug-scene-property-key", "gain", "--mwx-debug-scene-property-type", "number",
                    "--mwx-debug-scene-property-value", "0.85"]
                (output / "command.json").write_text(json.dumps(command, indent=2))
                children = {}
                with (output / "app.log").open("w") as log:
                    process = subprocess.Popen(command, env=environment, stdout=log,
                                               stderr=subprocess.STDOUT, start_new_session=True)
                    try:
                        deadline = time.monotonic() + 100
                        while process.poll() is None and time.monotonic() < deadline:
                            children.update(child_processes(process.pid))
                            time.sleep(0.1)
                        self.assertIsNotNone(process.poll(), "product lifecycle did not exit within 100 seconds")
                    finally:
                        cleanup = finish_selection_process(process, children)
                self.assertEqual(cleanup["exitCode"], 0, cleanup)
                self.assertTrue(cleanup["ownedProcessesExited"], cleanup)
                self.assertFalse(cleanup["remainingOwnedChildren"], cleanup)
                log = (output / "app.log").read_text()
                native = json.loads((output / "native.json").read_text())
                self.assertTrue(native["passed"], native)
                self.assertEqual(native["standardDefaultsDomain"], STARTUP_BUNDLE_ID)
                self.assertTrue(native["standardDefaultsSentinelVerified"], native)
                self.assertIn(suite, debug_defaults_suites(log))
                rows = native["rows"]
                self.assertEqual([row["recordID"] for row in rows], [scene.name for scene in scenes])
                self.assertEqual(rows[0]["daemonPID"], rows[1]["daemonPID"])
                self.assertIn(rows[1]["daemonPID"], children)
                self.assertIn(str(binary), children[rows[1]["daemonPID"]])
                for key in ("requestID", "ticketID", "executionID"):
                    self.assertNotEqual(rows[0][key], rows[1][key])
                self.assertRegex(log, rf"phase=daemon-gpu-drained request={rows[1]['requestID']} pid={rows[1]['daemonPID']} gpuDrained=true code=0")
                final_drain_verified = True
                lifecycle = native["lifecycleObservation"]
                for key in ("systemWallpaperSyncDisabled", "pauseClockFrozen", "resumeClockAdvanced",
                            "freshBSelectionInSameDaemon", "productStopClearedSelection",
                            "shutdownCompletionObserved", "daemonUnregisteredAfterShutdown"):
                    self.assertTrue(lifecycle[key], (key, lifecycle))
                ack = lifecycle["propertyAcknowledgement"]
                self.assertTrue(ack["matchedPendingProperty"])
                self.assertEqual([lifecycle["propertyDispatch"][key] for key in ("requestID", "executionID", "daemonPID")],
                                 [rows[0][key] for key in ("requestID", "executionID", "daemonPID")])
                self.assertEqual((ack["payload"]["recordID"], ack["payload"]["revision"],
                                  ack["payload"]["debugPlaybackRequestID"]), (scenes[0].name, 1, rows[0]["requestID"]))
                release = lifecycle["aLaunchResourcesReleased"]
                self.assertEqual(release["payload"]["requestID"], rows[0]["requestID"])
                self.assertTrue(release["payload"]["gpuDrained"])
                captures = lifecycle["captures"]
                self.assertEqual([capture["phase"] for capture in captures],
                    ["a-before", "a-property", "a-paused-first", "a-paused-second", "a-resumed", "b-presented"])
                self.assertEqual(len({capture["captureID"] for capture in captures}), 6)
                probe = compile_pixel_probe(root)
                for capture in captures:
                    observations[capture["phase"]] = json.loads(subprocess.check_output(
                        [str(probe), capture["path"], "lifecycle"], text=True))
                    row = rows[1 if capture["phase"] == "b-presented" else 0]
                    self.assertEqual(capture["host"]["requestID"], row["requestID"])
                    self.assertEqual(capture["host"]["daemonPID"], row["daemonPID"])
                    self.assertEqual(capture["executionID"], row["executionID"])
                    self.assertEqual(capture["daemonGeneration"], row["daemonGeneration"])
                before, changed, blue = (observations[name]["propertyRGB"] for name in ("a-before", "a-property", "b-presented"))
                self.assertGreater(changed[0] - before[0], 50, (before, changed))
                self.assertLess(max(changed[1:]), 35, changed)
                self.assertGreater(blue[2], 170, blue)
                self.assertLess(max(blue[:2]), 35, blue)
                def motion_difference(a, b):
                    first, second = (observations[name]["motionRGB"] for name in (a, b))
                    self.assertEqual(len(first), len(second))
                    return sum(abs(x - y) for x, y in zip(first, second)) / len(first)
                self.assertLess(motion_difference("a-paused-first", "a-paused-second"), 1.5)
                self.assertGreater(motion_difference("a-paused-second", "a-resumed"), 3)
                self.assertEqual(tree_identity(workshop), inputs_before)
            except BaseException as error:
                failure = error
                raise
            finally:
                cleanup_errors = []
                cleanup_complete = cleanup is None or cleanup.get("ownedProcessesExited") is True
                if not cleanup_complete:
                    cleanup_errors.append(("owned-processes", "private defaults and App retained until owned children exit"))
                try:
                    if identity:
                        verify_staged_app(identity)
                except BaseException as error:
                    cleanup_errors.append(("verify-staged-app", str(error)))
                for name, action in [
                    ("private-suite", lambda: delete_debug_defaults_suite(suite, environment)),
                    ("startup-domain", lambda: reset_startup_defaults(STARTUP_BUNDLE_ID)),
                    ("staged-app", lambda: discard_staged_app(identity) if identity else None),
                ]:
                    if not cleanup_complete:
                        continue
                    try:
                        action()
                    except BaseException as error:
                        cleanup_errors.append((name, str(error)))
                try:
                    if production_preferences_identity() != production_before:
                        cleanup_errors.append(("production-preferences", "production preferences changed"))
                except BaseException as error:
                    cleanup_errors.append(("inspect-production-preferences", str(error)))
                try:
                    (output / "observations.json").write_text(json.dumps({"pixels": observations, "cleanup": cleanup,
                        "appIdentity": identity, "failure": str(failure) if failure else None,
                        "cleanupErrors": cleanup_errors, "daemonGPUDrainCallbackVerified": final_drain_verified,
                        "passed": failure is None and not cleanup_errors and final_drain_verified}, indent=2))
                    if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                        saved = Path(destination) / self._testMethodName
                        shutil.copytree(output, saved)
                        shutil.copytree(workshop, saved / "inputs")
                except BaseException as error:
                    cleanup_errors.append(("retain-evidence", str(error)))
                if cleanup_errors:
                    if failure is not None:
                        failure.add_note("owned lifecycle cleanup errors: " + repr(cleanup_errors))
                    else:
                        self.fail(repr(cleanup_errors))
        finally:
            if cleanup is None or cleanup.get("ownedProcessesExited") is True:
                shutil.rmtree(root)
            else:
                print(f"Owned lifecycle process cleanup incomplete; retained {root}", file=sys.stderr)
