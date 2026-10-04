"""A decoded current media cover reaches frozen frames without replaying the VM.

Both runs use the same owned package, PNG and media inputs. A two-second decode
delay places terminal publication after the paused ready-readback request. This
checks ready/unavailable notification and frozen-frame reuse, not pixel parity.
"""
from pathlib import Path
import hashlib
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_composition_authored_order_integration import encoded
from .test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from .test_scene_pkg_cache_extractor import make_package


ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATHS = [ROOT / path for path in (
    "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift",
    "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+MediaThumbnail.swift",
    "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+EvidenceSchedule.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneMediaThumbnailTextureStore.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMediaThumbnailCoordinator.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneBaseMaterialProviderBindingCompiler.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorCandidateCatalog.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram.swift",
    "script/tests/test_scene_composition_authored_order_integration.py",
    "script/tests/test_scene_fullscreen_visibility_integration.py",
    "script/tests/test_scene_pkg_cache_extractor.py",
    "script/web_benchmark_capture.py",
)] + [Path(__file__).resolve()]
PROTOCOL = {"canvas": [256, 256], "surfaces": 2, "requestedDurationSeconds": 6,
            "pausedDecodeDelaySeconds": 2, "centerRGB": [0, 255, 255],
            "channelTolerance": 4, "minimumGreenPixels": 20,
            "minimumCoverPixels": 1000,
            "requiredCapture": "scene-ready-window.png", "optionalCapture": "scene-after-window.png",
            "evidenceBoundary": "selected surface pixels; both surfaces completion; no official parity"}
SCRIPT = """let visible=false;
let events=0;
let updates=0;
export function mediaPlaybackChanged(event) {
    if(++events!==1) throw Error('paused-media-event-replayed');
    visible=event.state===1;
}
export function update(value) {
    if(++updates>1 && engine.frametime===0) throw Error('paused-media-update-replayed');
    return visible;
}
"""


def png(rgba):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 32, 32, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + bytes(rgba) * 32) * 32)) + chunk(b"IEND", b""))


def fixture_entries():
    scene = {"version": 3, "general": {"orthogonalprojection": {"width": 256, "height": 256},
                                       "clearcolor": "0 0 0"}, "objects": [
        {"id": 11, "name": "Owned current media cover", "image": "models/own_cover.json",
         "origin": "128 128 0", "size": "64 64"},
        {"id": 30, "name": "Once-only media callback peer", "image": "models/own_solid.json",
         "origin": "192 184 0", "size": "16 16", "color": "0 1 0",
         "visible": {"value": False, "script": SCRIPT}}]}
    return {"type": "scene", "file": "scene.json"}, {
        "scene.json": encoded(scene),
        "models/own_cover.json": encoded({"material": "materials/own_cover.json"}),
        "models/own_solid.json": encoded({"solidlayer": True, "width": 256, "height": 256}),
        "materials/own_cover.json": encoded({"passes": [{"shader": "genericimage",
            "textures": ["materials/own_red.png"],
            "usertextures": [{"type": "system", "name": "$mediaThumbnail"}]}]}),
        "materials/own_red.png": png((255, 0, 0, 255))}


def measure(path):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"invalid capture: {path}")
    width, height, rows = decoded
    green = sum(row[x] <= 4 and row[x + 1] >= 251 and row[x + 2] <= 4
                for row in rows for x in range(0, width * 3, 3))
    cyan = sum(row[x] <= 4 and row[x + 1] >= 251 and row[x + 2] >= 251
               for row in rows for x in range(0, width * 3, 3))
    red = sum(row[x] >= 251 and row[x + 1] <= 4 and row[x + 2] <= 4
              for row in rows for x in range(0, width * 3, 3))
    return {"dimensions": [width, height], "centerRGB": list(rows[height // 2][width // 2 * 3:width // 2 * 3 + 3]),
            "greenCount": green, "cyanCount": cyan, "redCount": red}


class ScenePausedMediaIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires an explicitly frozen Debug executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def run_scene(self, paused, *, reject_once=False, malformed=False):
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        self.assertTrue(all(path.is_file() for path in SOURCE_PATHS), SOURCE_PATHS)
        with tempfile.TemporaryDirectory(prefix="mwx-paused-media-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir(); home.mkdir()
            project, entries = fixture_entries()
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            (content / "cover.png").write_bytes(b"OWNED MALFORMED COVER" if malformed else png((0, 255, 255, 255)))
            inputs = (content / "project.json", content / "scene.pkg", content / "cover.png")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence),
                "--mwx-debug-scene-media-thumbnail", "cover.png", "--mwx-debug-scene-media-playback-state", "1"]
            if paused:
                command.append("--mwx-debug-scene-start-paused")
            env = os.environ.copy()
            for key in tuple(env):
                if key.startswith("MWX_SCENE_DEBUG_"):
                    env.pop(key)
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="2",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            if paused:
                env["MWX_SCENE_DEBUG_MEDIA_THUMBNAIL_DELAY"] = "2"
            if reject_once:
                env["MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE"] = "0"
            expected = [255, 0, 0] if malformed else PROTOCOL["centerRGB"]
            identity = {"command": command, "paused": paused, "rejectOnce": reject_once,
                "malformed": malformed, "protocol": dict(PROTOCOL, centerRGB=expected),
                "debugEnvironment": {key: value for key, value in env.items() if key.startswith("MWX_SCENE_DEBUG_")},
                "appSHA256": self.frozen_app_hashes, "inputSHA256": file_hashes(inputs),
                "sourceSHA256": file_hashes(SOURCE_PATHS),
                "entrySHA256": {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}}
            (root / "prerun.json").write_bytes(encoded(identity))
            log, ordered_log, pixels = "", "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
                log = result.stdout + result.stderr
                ordered_log = result.stderr
                identity["returncode"] = result.returncode
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertNotRegex(log, r"failure=exception|paused-media-(?:event|update)-replayed|phase=launch-failed")
                self.assertRegex(log, r"phase=ready [^\n]*surfaces=2 ")
                self.assertIn("phase=stopped surfacesBefore=2 surfacesAfter=0", log)
                self.assertIn("gpuDrained=true", log)
                self.assertIn("phase=media-playback-published state=1", log)
                self.assertEqual(len(re.findall(r"target=layer\(layerID: 30,[^\n]*event=mediaPlaybackChanged generation=1 state=1 ", log)), 1)
                self.assertRegex(log, r"target=layer\(layerID: 30,[^\n]*callback=completed type=bool ")
                flag = "false" if malformed else "true"
                ready_events = list(re.finditer(
                    rf"MWX media thumbnail store: phase=ready generation=1 hasColor={flag} hasPreserved={flag}", ordered_log))
                self.assertEqual(len(ready_events), 2, log[-6000:])
                self.assertRegex(log, r"phase=snapshot reason=ready request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-failed reason=ready ")
                captures = [PROTOCOL["requiredCapture"]]
                if (evidence / PROTOCOL["optionalCapture"]).is_file():
                    self.assertRegex(log, r"phase=snapshot reason=after request=\d+ source=metal ")
                    captures.append(PROTOCOL["optionalCapture"])
                pixels = {name: measure(evidence / name) for name in captures}
                for name, sample in pixels.items():
                    with self.subTest(paused=paused, capture=name):
                        self.assertTrue(all(abs(a - b) <= PROTOCOL["channelTolerance"]
                            for a, b in zip(sample["centerRGB"], expected)), sample)
                        self.assertGreater(sample["greenCount"], PROTOCOL["minimumGreenPixels"], sample)
                        self.assertGreater(sample["redCount" if malformed else "cyanCount"],
                                           PROTOCOL["minimumCoverPixels"], sample)
                completed = [tuple(map(int, row)) for row in re.findall(
                    r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)]
                surfaces = {surface for _, surface in completed}
                self.assertEqual(len(surfaces), 2, log[-6000:])
                if paused:
                    self.assertTrue(completed and all(frame == 0 for frame, _ in completed), completed)
                    self.assertIn("phase=frame-driver-start paused=true", log)
                    self.assertNotIn("phase=frame-driver-start paused=false", log)
                    # Product readiness and completion are both NSLog events;
                    # preserve stderr order instead of concatenated stream order.
                    redrawn = {int(surface) for surface in re.findall(
                        r"state=completed frame=0 surface=(\d+) gpu=completed",
                        ordered_log[ready_events[-1].end():])}
                    self.assertEqual(redrawn, surfaces, log[-6000:])
                rejected = re.findall(r"state=rejected frame=0 surface=(\d+) totalSurfaces=2", ordered_log)
                self.assertEqual(len(rejected), 1 if reject_once else 0, log[-6000:])
                if reject_once:
                    self.assertIn(int(rejected[0]), redrawn)
                self.assertEqual(file_hashes(inputs), identity["inputSHA256"])
                self.assertEqual(file_hashes(SOURCE_PATHS), identity["sourceSHA256"])
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                return pixels
            except subprocess.TimeoutExpired as error:
                log = "".join(value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                              for value in (error.stdout, error.stderr))
                ordered_log = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else error.stderr or ""
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity.update(appSHA256After=app_hashes(self.app), inputSHA256After=file_hashes(inputs),
                                sourceSHA256After=file_hashes(SOURCE_PATHS))
                (root / "identity.json").write_bytes(encoded(identity))
                (root / "pixels.json").write_bytes(encoded(pixels))
                (root / "app.log").write_text(log)
                (root / "app.stderr.log").write_text(ordered_log)
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName / ("paused" if paused else "control")
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    for path in root.glob("*.log"):
                        shutil.copy2(path, saved / path.name)

    def test_current_cover_reaches_both_paused_surfaces_without_media_vm_replay(self):
        control = self.run_scene(False)[PROTOCOL["requiredCapture"]]
        paused = self.run_scene(True)[PROTOCOL["requiredCapture"]]
        for key in ("dimensions", "cyanCount"):
            self.assertEqual(paused[key], control[key], (paused, control))

    def test_late_cover_recovers_a_rejected_surface_without_media_vm_replay(self):
        self.run_scene(True, reject_once=True)

    def test_unavailable_cover_redraws_both_paused_surfaces_to_authored_fallback(self):
        self.run_scene(True, malformed=True)
