"""Actual ordinary/effect-video startup: requires a frozen Debug App and screen capture.

Uses self-owned media and an isolated HOME. Window pixels come from the actual
ready window, not a fake provider or a late warm-source rendering harness.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zlib

from .test_scene_composition_authored_order_integration import VERTEX
from .test_scene_material_video_asset import video_tex
from .scene_pkg_fixture import make_package


def video_material(texture):
    return json.dumps({"passes": [{"shader": "genericimage2", "textures": [texture],
        "blending": "translucent", "depthtest": "disabled", "depthwrite": "disabled",
        "cullmode": "nocull", "combos": {"VERSION": 2}}]}).encode()


def red_png():
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", 32, 24, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff\0\0\xff" * 32) * 24))
            + chunk(b"IEND", b""))


def automatic_video_scene(red_payload, blue_payload, *, renamed=False, hidden_mode=None):
    """Self-owned prepared videos and a discrete scene-time selector.

    Both source names and the equivalent selector expression vary. This is an
    input definition only; the native gate below owns rendering and observation.
    """
    names = ["First take", "Second take"] if not renamed else ["Amber source", "Azure source"]
    stems = ["owned/phase-a", "owned/phase-b"] if not renamed else ["different/nested/amber", "different/nested/azure"]
    ids = [11, 23] if not renamed else [701, 919]
    selector = "Math.floor(engine.runtime / 2) % 2" if not renamed else "engine.runtime < 2 ? 0 : (engine.runtime < 4 ? 1 : 0)"
    visibility = ""
    if hidden_mode == "alpha-zero":
        visibility = "if (pick === 1) config.alpha = 0;"
    elif hidden_mode == "offscreen":
        visibility = "if (pick === 1) config.origin = new Vec3(4096, 4096, 0);"
    controller = """
        let presets = [], live, selected = -1, requested = -1;
        export function init(value) {
            const names = __NAMES__;
            presets = names.map(name => thisScene.getInitialLayerConfig(thisScene.getLayer(name)));
            names.forEach(name => thisScene.destroyLayer(name));
            return false;
        }
        export function update(value) {
            const pick = requested < 0 ? (__SELECTOR__) : requested;
            if (pick !== selected) {
                const config = Object.assign({}, presets[pick]);
                config.visible = true;
                __VISIBILITY__
                const next = thisScene.createLayer(config);
                if (!next) throw Error('owned prepared video did not construct');
                next.getVideoTexture().play();
                if (live) thisScene.destroyLayer(live);
                live = next; selected = pick;
            }
            return false;
        }
        export function applyUserProperties(properties) {
            if (properties.hasOwnProperty('scenechoice')) requested = Number(properties.scenechoice);
        }
    """.replace("__NAMES__", json.dumps(names)).replace("__SELECTOR__", selector).replace("__VISIBILITY__", visibility)
    if renamed:
        for old, new in (("presets", "savedConfigurations"), ("live", "activeCarrier"),
                         ("selected", "selectionIndex"), ("requested", "selectionRequest"), ("pick", "nextIndex")):
            controller = controller.replace(old, new)
    objects = [{"id": 2, "name": "Cyan background", "image": "models/util/solidlayer.json",
                "origin": "64 64 0", "size": "128 128", "color": "0 1 1"}]
    entries = []
    for identity, name, stem, payload in zip(ids, names, stems, (red_payload, blue_payload)):
        model, material = f"models/{stem}.json", f"materials/{stem}.json"
        objects.append({"id": identity, "name": name, "image": model, "visible": False,
                        "origin": "64 64 0", "size": "128 128"})
        entries.extend([(model, json.dumps({"material": material}).encode()),
                        (material, video_material(stem)),
                        (f"materials/{stem}.tex", video_tex(payload))])
    objects.append({"id": 31, "name": "Discrete scene-time selector", "image": "models/util/solidlayer.json",
                    "visible": {"value": False, "script": controller}, "origin": "0 0 0", "size": "1 1"})
    scene = {"version": 3, "general": {"orthogonalprojection": {"width": 128, "height": 128}}, "objects": objects}
    project = {"type": "scene", "file": "scene.json", "general": {"properties": {"scenechoice": {
        "type": "combo", "text": "Source selection", "value": "-1", "options": [
            {"label": "Automatic", "value": "-1"}, {"label": "Red", "value": "0"}, {"label": "Blue", "value": "1"}]}}}}
    return project, [("scene.json", json.dumps(scene).encode()), *entries]


def prepare_video_switch_scene(destination, *, renamed=False, selection="-1"):
    """Generate one isolated input package; never launch an App or request GPU."""
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    payloads, media = [], []
    for color in ("red", "blue"):
        clip = destination / f"{color}.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            f"color=c={color}:s=32x24:r=30:d=5", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(clip)],
            check=True, capture_output=True, timeout=20)
        payload = clip.read_bytes()
        payloads.append(payload)
        media.append({"file": clip.name, "sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload)})
    project, entries = automatic_video_scene(*payloads, renamed=renamed)
    project["general"]["properties"]["scenechoice"]["value"] = selection
    project_bytes, package_bytes = json.dumps(project).encode(), make_package(entries)
    (destination / "project.json").write_bytes(project_bytes)
    (destination / "scene.pkg").write_bytes(package_bytes)
    receipt = {"sceneRoot": str(destination), "renamedEquivalent": renamed, "initialSelection": selection,
        "property": "scenechoice", "propertyValues": {"automatic": "-1", "red": "0", "blue": "1"},
        "automaticSchedule": "red [0,2), blue [2,4), red [4,6)", "media": media,
        "projectSHA256": hashlib.sha256(project_bytes).hexdigest(), "packageSHA256": hashlib.sha256(package_bytes).hexdigest()}
    (destination / "switch-input.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


class SceneInitialVideoPresentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not app or sys.platform != "darwin" or not shutil.which("ffmpeg"):
            raise unittest.SkipTest("requires frozen Debug App, macOS capture and ffmpeg")
        cls.app = Path(app).resolve(strict=True)
        cls.app_sha = hashlib.sha256(cls.app.read_bytes()).hexdigest()
        cls.debug_dylib = cls.app.with_name("MyWallpaperX.debug.dylib").resolve(strict=True)
        cls.debug_dylib_sha = hashlib.sha256(cls.debug_dylib.read_bytes()).hexdigest()
        cls.fixture_generator_sha = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
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
    var red = 0, cyan = 0, blue = 0, pink = 0
    for i in stride(from: 0, to: raw.count, by: 4) {
        if raw[i] > 160 && raw[i+1] < 80 && raw[i+2] < 80 { red += 1 }
        if raw[i] < 80 && raw[i+1] > 160 && raw[i+2] > 160 { cyan += 1 }
        if raw[i] < 80 && raw[i+1] < 80 && raw[i+2] > 160 { blue += 1 }
        if raw[i] > 245 && raw[i+1] >= 55 && raw[i+1] <= 74
            && raw[i+2] >= 55 && raw[i+2] <= 74 { pink += 1 }
    }
    let center = (16 * 32 + 16) * 4
    return ["red": Double(red) / 1024, "cyan": Double(cyan) / 1024, "blue": Double(blue) / 1024,
            "pink": Double(pink) / 1024,
            "centerRed": Double(raw[center]), "centerGreen": Double(raw[center+1]),
            "centerBlue": Double(raw[center+2])]
}
print(String(data: try! JSONSerialization.data(withJSONObject: stats), encoding: .utf8)!)
''')
        subprocess.run(["xcrun", "swiftc", str(source), "-o", str(cls.pixel_probe)],
                       check=True, capture_output=True, timeout=60)

    def run_video(self, *, paused, renamed=False, screens=1, terminal=False, utility=False, static=False):
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
            if utility:
                shader = f"{stem}/prefix-mix"
                fragment = (
                    b'uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}\n'
                    b'uniform sampler2D g_Texture1; // {"material":"albedo"}\n'
                    b"varying vec2 v_TexCoord;\nvoid main(){"
                    b"vec4 source=texSample2D(g_Texture0,v_TexCoord);"
                    b"vec3 video=texSample2D(g_Texture1,v_TexCoord).rgb;"
                    b"gl_FragColor=vec4(mix(source.rgb,video,0.75),source.a);}\n")
                vertex = VERTEX
                if renamed:
                    vertex = vertex.replace(b"v_TexCoord", b"ownedUV")
                    fragment = fragment.replace(b"v_TexCoord", b"ownedUV").replace(
                        b"source", b"capturedPrefix").replace(b"video", b"incomingRGB")
                model = "models/util/composelayer.json"
                objects = [{"id": 4, "name": "White captured background",
                            "image": "models/util/solidlayer.json", "origin": "64 64 0",
                            "size": "128 128", "color": "1 1 1"}]
                entries = [(model, json.dumps({"width": 128, "height": 128, "autosize": False}).encode()),
                           (f"shaders/{shader}.vert", vertex), (f"shaders/{shader}.frag", fragment)]
                for identity, hidden in ((movie_id, False), (hidden_id, True)):
                    effect = f"effects/{stem}/{identity}/effect.json"
                    material = f"materials/{stem}/{identity}.json"
                    asset = f"materials/{stem}-hidden.tex" if hidden else f"materials/{stem}.{'png' if static else 'tex'}"
                    image = (video_tex(payload[:512]) if hidden or terminal
                             else red_png() if static else video_tex(payload))
                    objects.append({"id": identity, "name": "Hidden truncated video" if hidden else "Utility movie",
                                    "image": model, "origin": "64 64 0", "size": "128 128",
                                    "visible": False if hidden else {"value": True, "script": script},
                                    "copybackground": True, "config": {"passthrough": False},
                                    "effects": [{"id": identity * 10, "file": effect}]})
                    entries.extend([(effect, json.dumps({"passes": [{"material": material}]}).encode()),
                                    (material, json.dumps({"passes": [{"shader": shader, "textures": [None, asset],
                                        "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled",
                                        "cullmode": "nocull"}]}).encode()), (asset, image)])
                objects.append({"id": 2, "name": "Cyan peer", "image": "models/util/solidlayer.json",
                                "origin": "112 112 0", "size": "24 24", "color": "0 1 1"})
            else:
                objects = [
                    {"id": movie_id, "name": "Renamed movie" if renamed else "Own red video",
                     "image": model, "origin": "64 64 0", "size": "128 96",
                     "visible": {"value": True, "script": script}},
                    {"id": 2, "name": "Cyan peer", "image": "models/util/solidlayer.json",
                     "origin": "112 112 0", "size": "24 24", "color": "0 1 1"},
                    {"id": hidden_id, "name": "Hidden truncated video", "image": "models/hidden.json",
                     "origin": "64 64 0", "size": "128 96", "visible": False},
                ]
                entries = [
                    (model, json.dumps({"material": material}).encode()),
                    (material, video_material(stem)),
                    ("materials/" + stem + ".tex", video_tex(payload[:512] if terminal else payload)),
                    ("models/hidden.json", json.dumps({"material": "materials/hidden.json"}).encode()),
                    ("materials/hidden.json", video_material("owned/hidden")),
                    ("materials/owned/hidden.tex", video_tex(payload[:512]))]
            entry = {"version": 3, "general": {"orthogonalprojection": {"width": 128, "height": 128}},
                     "objects": objects}
            entries.insert(0, ("scene.json", json.dumps(entry).encode()))
            (scene / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
            (scene / "scene.pkg").write_bytes(make_package(entries))
            fixture_sha = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in (scene / "project.json", scene / "scene.pkg")}
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
            screenshots, colors = [], []
            try:
                deadline = time.monotonic() + 20
                while process.poll() is None and time.monotonic() < deadline:
                    log = (root / "app.log").read_text()
                    windows = re.search(r"phase=ready .*windows=([0-9,]+)", log)
                    if windows:
                        self.assertEqual(len(windows[1].split(",")), screens, log[-8000:])
                        for index, window in enumerate(windows[1].split(",")):
                            capture = screenshot if index == 0 else root / f"window-{index}.png"
                            screenshots.append(capture)
                            subprocess.run(["screencapture", "-x", "-l" + window, str(capture)],
                                           check=True, capture_output=True, timeout=10)
                        break
                    time.sleep(0.1)
                self.assertTrue(screenshot.exists(), (root / "app.log").read_text()[-8000:])
                self.assertEqual(process.wait(timeout=20), 0)
                log = (root / "app.log").read_text()
                # Window PNGs carry the display ICC profile. Convert to sRGB
                # before comparing the authored colors; ffmpeg ignores this ICC.
                colors = [json.loads(subprocess.check_output([str(self.pixel_probe), str(capture)], text=True))
                          for capture in screenshots]
                self.assertNotIn("phase=launch-failed", log)
                self.assertNotRegex(log, r"MWX SceneScript VM:.*(?:failure=|callback=rejected)")
                self.assertIn(f"phase=stopped surfacesBefore={screens} surfacesAfter=0 gpuDrained=true", log)
                pending = re.findall(r"phase=initial-video-presentation attempt=(\d+) frame=(\d+) "
                    r"surfaces=(\d+) qualified=(\d+) held=(true|false) pending=([^\n]*)", log)
                self.assertTrue(pending, log[-8000:])
                if not utility and not terminal:
                    self.assertTrue(any(row[4] == "false" and str(movie_id) in row[5].split(",") for row in pending))
                self.assertTrue(any(row[2:5] == (str(screens), str(screens), "true") for row in pending))
                self.assertFalse(any(str(hidden_id) in row[5].split(",") for row in pending))
                activation = log.index("phase=session-activated")
                owner = "asset" if utility else "ordinary"
                publications = list(re.finditer(rf"schema=video-frame-v1 owner={owner} source=([0-9A-Fa-f-]{{36}}) "
                    r"epoch=(\d+) frame=(\d+) generation=(\d+) ", log))
                if not terminal and not static:
                    # One publishable video plus the hidden truncated negative
                    # identifies this fixture's Source without making
                    # its shared owner carry the logical consumer's layer ID.
                    self.assertEqual(len({row[1] for row in publications}), 1, log[-8000:])
                    first = [row for row in publications if row[4] == "1"]
                    self.assertTrue(first, log[-8000:])
                    self.assertGreater(int(first[0][2]), 0)
                    self.assertLess(first[0].start(), activation)
                else:
                    self.assertEqual(publications, [], log[-8000:])
                if paused:
                    visibility = re.findall(rf"dynamic-layer-visibility-v1 frame=(\d+) .*layer={movie_id} source=sceneScript", log)
                    self.assertEqual(visibility, ["0"])
                    self.assertEqual({row[1] for row in pending}, {"0"})
                for observed in colors:
                    self.assertGreater(observed["cyan"], 0.005)
                    if utility:
                        if terminal:
                            self.assertLess(observed["pink"], 0.01)
                            for channel in ("centerRed", "centerGreen", "centerBlue"):
                                self.assertAlmostEqual(observed[channel], 255, delta=4)
                        else:
                            # Pink requires both the white capture and red slot;
                            # a source-free 0.75 * red must fail this oracle.
                            self.assertGreater(observed["pink"], 0.7, observed)
                    elif terminal:
                        self.assertLess(observed["red"], 0.01)
                    else:
                        self.assertGreater(observed["red"], 0.7)
                self.assertEqual(hashlib.sha256(self.app.read_bytes()).hexdigest(), self.app_sha)
                self.assertEqual(hashlib.sha256(self.debug_dylib.read_bytes()).hexdigest(), self.debug_dylib_sha)
                self.assertEqual({path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in (scene / "project.json", scene / "scene.pkg")}, fixture_sha)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
                handle.close()
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName
                    saved.mkdir(parents=True, exist_ok=True)
                    for source in (root / "app.log", *screenshots, scene / "project.json", scene / "scene.pkg", evidence / "scene-preview.log", evidence / "scene-runtime-evidence.json"):
                        if source.exists():
                            shutil.copy2(source, saved / source.name)
                    (saved / "run.json").write_text(json.dumps({"command": command,
                        "exit": process.returncode, "sha256": self.app_sha, "paused": paused,
                        "screens": screens, "terminal": terminal, "renamed": renamed,
                        "utility": utility, "staticControl": static, "windowColors": colors,
                        "debugDylibSHA256": self.debug_dylib_sha,
                        "appSHA256After": hashlib.sha256(self.app.read_bytes()).hexdigest(),
                        "debugDylibSHA256After": hashlib.sha256(self.debug_dylib.read_bytes()).hexdigest(),
                        "fixtureGeneratorSHA256": self.fixture_generator_sha, "fixtureSHA256": fixture_sha,
                        "fixtureSHA256After": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                              for path in (scene / "project.json", scene / "scene.pkg")},
                        "paused_counter_consumer": "Cyan peer alpha=1/shared.frames" if paused else None}, indent=2) + "\n")

    def test_cold_paused_waits_for_real_video_without_repeating_vm(self):
        self.run_video(paused=True)

    def test_renamed_video_two_surfaces_qualify_one_actual_attempt(self):
        self.run_video(paused=False, renamed=True, screens=2)

    def test_failed_visible_video_remains_local_fallback(self):
        self.run_video(paused=True, terminal=True)

    def test_static_utility_effect_slot_keeps_white_capture_contribution(self):
        self.run_video(paused=True, utility=True, static=True)

    def test_cold_paused_utility_effect_video_has_real_first_pixels(self):
        self.run_video(paused=True, utility=True)

    def test_renamed_utility_effect_video_on_two_surfaces(self):
        self.run_video(paused=False, renamed=True, screens=2, utility=True)

    def test_failed_utility_effect_video_keeps_background_and_peer(self):
        self.run_video(paused=True, terminal=True, utility=True)

    def run_automatic_switch(self, *, renamed=False, screens=1, hidden_mode=None, property_mode=False):
        with tempfile.TemporaryDirectory(prefix="mwx-video-switch-presentation-") as temporary:
            root = Path(temporary)
            scene, home = root / "scene", root / "home"
            scene.mkdir(); home.mkdir()
            evidence = root / "evidence"
            evidence.mkdir()
            payloads = []
            for color in ("red", "blue"):
                clip = root / f"{color}.mp4"
                subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                    f"color=c={color}:s=32x24:r=30:d=5", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(clip)],
                    check=True, capture_output=True, timeout=20)
                payloads.append(clip.read_bytes())
            project, entries = automatic_video_scene(*payloads, renamed=renamed, hidden_mode=hidden_mode)
            if property_mode:
                project["general"]["properties"]["scenechoice"]["value"] = "0"
            (scene / "project.json").write_text(json.dumps(project))
            (scene / "scene.pkg").write_bytes(make_package(entries))
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                               MWX_SCENE_DEBUG_SURFACE_COUNT=str(screens))
            command = [str(self.app), "--mwx-debug-scene-root", str(scene), "--mwx-debug-scene-duration", "6.5",
                       "--mwx-debug-scene-evidence-dir", str(evidence)]
            if property_mode:
                command += ["--mwx-debug-scene-live-property-sequence-json", json.dumps([
                    {"scenechoice": "1"}, {"scenechoice": "0"}])]
            frames, windows, capture_deadline = [], [], None
            with (root / "app.log").open("w") as handle:
                process = subprocess.Popen(command, env=environment, stdout=handle, stderr=subprocess.STDOUT)
                try:
                    deadline = time.monotonic() + 25
                    while process.poll() is None and time.monotonic() < deadline:
                        log = (root / "app.log").read_text()
                        if not windows:
                            ready = re.search(r"phase=ready .*windows=([0-9,]+)", log)
                            if ready:
                                windows = ready[1].split(",")
                                capture_deadline = time.monotonic() + 5
                        if windows and time.monotonic() < capture_deadline and len(frames) < 96 * screens:
                            for window in windows:
                                screenshot = root / f"screen-{window}-{len(frames):03}.png"
                                capture = subprocess.run(["screencapture", "-x", "-l" + window, str(screenshot)],
                                    capture_output=True, text=True, timeout=10)
                                if capture.returncode:
                                    if process.poll() is not None:
                                        break
                                    self.fail(capture.stderr)
                                colors = json.loads(subprocess.check_output([str(self.pixel_probe), str(screenshot)], text=True))
                                frames.append({"window": window, "hostTime": time.monotonic(), "file": screenshot.name, **colors})
                        time.sleep(0.05)
                    self.assertEqual(process.wait(timeout=5), 0)
                    log = (root / "app.log").read_text()
                    self.assertEqual(len(windows), screens, log[-8000:])
                    self.assertNotRegex(log, r"MWX SceneScript VM:.*(?:failure=|callback=rejected)")
                    if property_mode:
                        self.assertEqual(re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log),
                                         [("0", "true"), ("1", "true")], log[-8000:])
                    self.assertIn(f"phase=stopped surfacesBefore={screens} surfacesAfter=0 gpuDrained=true", log)
                    self.assertTrue((evidence / "scene-preview.log").is_file())
                    actual = json.loads((evidence / "scene-runtime-evidence.json").read_text())["runtimeInput"]["renderDescriptor"]
                    material_paths = {path for path, _ in entries if path.startswith("materials/") and path.endswith(".json")}
                    passes = [value for value in actual["materialPasses"] if value["materialPath"] in material_paths]
                    self.assertEqual({value["materialPath"] for value in passes}, material_paths)
                    self.assertTrue(all((value["blending"], value["depthTest"], value["depthWrite"], value["cullMode"])
                        == ("translucent", "disabled", "disabled", "nocull") for value in passes))
                    for window in windows:
                        rows = [row for row in frames if row["window"] == window]
                        self.assertGreater(len(rows), 10)
                        self.assertTrue(any(row["red"] > 0.7 for row in rows), rows)
                        if hidden_mode:
                            self.assertTrue(any(row["cyan"] > 0.7 for row in rows), rows)
                            self.assertFalse(any(row["blue"] > 0.05 for row in rows), rows)
                            colors = ["red" if row["red"] > 0.7 else "cyan" for row in rows]
                        else:
                            self.assertTrue(any(row["blue"] > 0.7 for row in rows), rows)
                            self.assertTrue(all(row["red"] + row["blue"] > 0.7 for row in rows), rows)
                            colors = ["red" if row["red"] > 0.7 else "blue" for row in rows]
                        changes = [color for index, color in enumerate(colors) if index == 0 or colors[index - 1] != color]
                        self.assertEqual(changes[:3], ["red", "cyan" if hidden_mode else "blue", "red"], rows)
                    if hidden_mode:
                        self.assertNotRegex(log, r"phase=video-switch-presentation[^\n]*present=false")
                    self.assertEqual(hashlib.sha256(self.app.read_bytes()).hexdigest(), self.app_sha)
                    self.assertEqual(hashlib.sha256(self.debug_dylib.read_bytes()).hexdigest(), self.debug_dylib_sha)
                finally:
                    if process.poll() is None:
                        process.terminate(); process.wait(timeout=5)
                    if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                        saved = Path(destination) / self._testMethodName
                        saved.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(root / "app.log", saved / "app.log")
                        shutil.copy2(scene / "scene.pkg", saved / "scene.pkg")
                        shutil.copy2(scene / "project.json", saved / "project.json")
                        for name in ("scene-preview.log", "scene-runtime-evidence.json"):
                            if (evidence / name).exists():
                                shutil.copy2(evidence / name, saved / name)
                        for frame in frames:
                            shutil.copy2(root / frame["file"], saved / frame["file"])
                        (saved / "run.json").write_text(json.dumps({"command": command, "exit": process.returncode,
                            "appSHA256": self.app_sha, "renamed": renamed, "screens": screens, "hiddenMode": hidden_mode,
                            "debugDylibSHA256": self.debug_dylib_sha,
                            "debugDylibSHA256After": hashlib.sha256(self.debug_dylib.read_bytes()).hexdigest(),
                            "fixtureGeneratorSHA256": self.fixture_generator_sha,
                            "propertyMode": property_mode,
                            "mediaSHA256": [hashlib.sha256(payload).hexdigest() for payload in payloads],
                            "observation": "sampled actual window pixels; unsampled display intervals remain unqualified",
                            "frames": frames}, indent=2) + "\n")

    def test_scene_time_video_switch_samples_actual_presented_colors(self):
        self.run_automatic_switch()

    def test_renamed_equivalent_video_switch_on_two_surfaces(self):
        self.run_automatic_switch(renamed=True, screens=2)

    def test_live_property_video_switch_samples_actual_presented_colors(self):
        self.run_automatic_switch(property_mode=True)

    def test_alpha_zero_incoming_video_does_not_hold_previous_output(self):
        self.run_automatic_switch(hidden_mode="alpha-zero")

    def test_offscreen_incoming_video_does_not_hold_previous_output(self):
        self.run_automatic_switch(renamed=True, hidden_mode="offscreen")
