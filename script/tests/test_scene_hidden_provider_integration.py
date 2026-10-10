"""Launch visibility may hide display without deferring a consumed named source."""
from pathlib import Path
import copy
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

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_pkg_cache_extractor import make_package


def fixture_entries(conditional=True, consumer=True, consumer_hidden=False, optional=False, shadow=False):
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff)
    def png(color):
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress((b"\0" + bytes(color) * 4) * 4)) + chunk(b"IEND", b""))
    visibility = {"user": {"name": "mode", "condition": "on"}, "value": True} if conditional else False
    scene = {"version": 3, "general": {"orthogonalprojection": {"width": 128, "height": 128}, "clearcolor": "0 0 0"},
             "objects": [{"id": 11, "name": "Blue source display", "image": "models/blue.json", "origin": "24 64 0", "size": "24 24", "visible": visibility},
                         {"id": 33, "name": "Green unaffected peer", "image": "models/util/solidlayer.json", "origin": "110 110 0", "size": "12 12", "color": "0 1 0"}]}
    if consumer:
        scene["objects"].insert(1, {"id": 22, "name": "Named source consumer", "image": "models/white.json", "origin": "64 64 0", "size": "24 24", "dependencies": [11],
                                    "effects": [{"id": 220, "file": "effects/own_sample/effect.json", "visible": True,
                                                 "passes": [{"id": 221, "textures": [None, "_rt_imageLayerComposite_11_a"]}]}]})
    if consumer:
        scene["objects"][1]["visible"] = not consumer_hidden
        if optional or shadow:
            scene["objects"][1]["effects"][0]["passes"][0]["usertextures"] = [None, {"type": "system", "name": "$mediaThumbnail"} if optional else "materials/white.png"]
    project = {"type": "scene", "file": "scene.json", "general": {"properties": {"mode": {"type": "combo", "value": "on", "options": [{"label": "On", "value": "on"}, {"label": "Off", "value": "off"}]}}}}
    entries = {"scene.json": json.dumps(scene).encode(),
               "models/blue.json": json.dumps({"material": "materials/blue.json"}).encode(),
               "models/white.json": json.dumps({"material": "materials/white.json"}).encode(),
               "materials/blue.json": json.dumps({"passes": [{"shader": "genericimage", "textures": ["materials/blue.png"]}]}).encode(),
               "materials/white.json": json.dumps({"passes": [{"shader": "genericimage", "textures": ["materials/white.png"]}]}).encode(),
               "materials/blue.png": png((0, 0, 255, 255)), "materials/white.png": png((255, 255, 255, 255)),
               "effects/own_sample/effect.json": json.dumps({"passes": [{"material": "materials/own_sample.json"}]}).encode(),
               "materials/own_sample.json": json.dumps({"passes": [{"shader": "own_sample", "textures": [None, "_rt_imageLayerComposite_11_a"], "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}).encode(),
               "shaders/own_sample.vert": b"attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n",
               "shaders/own_sample.frag": b"uniform sampler2D g_Texture1;\nvarying vec2 v_TexCoord;\nvoid main(){gl_FragColor=texSample2D(g_Texture1,v_TexCoord);}\n"}
    if optional:
        # Keep the admitted two-candidate chain: instance system -> instance
        # named source. Repeating that source in the material creates a third
        # candidate, outside the current bounded mixed-provider contract.
        material = json.loads(entries["materials/own_sample.json"])
        material["passes"][0]["textures"] = [None, None]
        entries["materials/own_sample.json"] = json.dumps(material).encode()
        # The existing mixed system/named profile requires an explicit sampler
        # purpose and its admitted overlay color transfer, not arbitrary RGBA.
        entries["shaders/own_sample.frag"] = b'''uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1; // {"mode":"rgbmask","default":"util/white"}
uniform float g_Multiply; // {"material":"multiply","default":1}
uniform float g_AlphaMultiply; // {"material":"alpha","default":1}
varying vec2 v_TexCoord;
vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {
    return mix(base, (blend), opacity);
}
void main() {
    vec4 base = texSample2D(g_Texture0, v_TexCoord);
    vec4 overlay = texSample2D(g_Texture1, v_TexCoord);
    float weight = g_Multiply * overlay.a;
    base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight);
    base.a = overlay.a * g_AlphaMultiply;
    gl_FragColor = base;
}
'''
    return project, entries


class SceneHiddenProviderIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)

    def run_provider(self, conditional=True, consumer=True, launch="off", live=None, consumer_hidden=False, optional=False, shadow=False, inactive_direct=False):
        project, entries = fixture_entries(conditional, consumer, consumer_hidden, optional, shadow)
        if inactive_direct:
            scene = json.loads(entries["scene.json"])
            effects = scene["objects"][1]["effects"]
            direct = copy.deepcopy(effects[0])
            direct["id"] = 219
            direct["passes"][0].pop("usertextures", None)
            effects.insert(0, direct)
            inactive = copy.deepcopy(direct)
            inactive.update(id=222, file="effects/own_invert/effect.json",
                            visible={"value": True, "user": {"name": "mode", "condition": "on"},
                                     "script": "export function update(value) { return value; }"})
            effects.append(inactive)
            # Layer-access scripts reserve effect targets before initial
            # visibility filtering, as in media-driven dependency consumers.
            scene["objects"][2]["visible"] = {"value": True, "script":
                "export function update(value) { thisScene.getLayer('Named source consumer').getEffect(2).visible = engine.runtime > 2; return true; }"}
            material = json.loads(entries["materials/own_sample.json"])
            material["passes"][0]["shader"] = "own_invert"
            entries.update({"scene.json": json.dumps(scene).encode(),
                "effects/own_invert/effect.json": json.dumps({"passes": [{"material": "materials/own_invert.json"}]}).encode(),
                "materials/own_invert.json": json.dumps(material).encode(),
                "shaders/own_invert.vert": entries["shaders/own_sample.vert"],
                "shaders/own_invert.frag": b"uniform sampler2D g_Texture1;\nvarying vec2 v_TexCoord;\nvoid main(){gl_FragColor=texSample2D(g_Texture1,v_TexCoord).bgra;}\n"})
        with tempfile.TemporaryDirectory(prefix="mwx-hidden-provider-") as temp:
            root = Path(temp)
            content = root / "content"
            content.mkdir()
            (content / "project.json").write_text(json.dumps(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            home = root / "home"
            home.mkdir()
            evidence = root / "evidence"
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1")
            command = [str(self.app), "--mwx-debug-scene-root", str(content), "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence), "--mwx-debug-scene-properties-json", json.dumps({"mode": launch})]
            if live is not None:
                command += ["--mwx-debug-scene-live-properties-json", json.dumps({"mode": live})]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            captures = sorted(evidence.glob("*-window.png"))
            preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
            measured = {}
            for capture in captures:
                width, height, rows = png_rgb_pixels(capture)
                center = list(rows[height // 2][width // 2 * 3:width // 2 * 3 + 3])
                blue = green = 0
                blue_left = blue_center = 0
                for row in rows[::8]:
                    for x in range(0, len(row), 24):
                        r, g, b = row[x:x+3]
                        is_blue = b > 200 and r < 30 and g < 30
                        blue += is_blue
                        # Midpoint between provider right edge (36) and consumer left edge (52).
                        blue_left += is_blue and x // 3 < width * (44 / 128)
                        blue_center += is_blue and abs(x // 3 - width / 2) < width * 0.05
                        green += g > 200 and r < 30 and b < 30
                measured[capture.name] = {"size": [width, height], "center": center, "blue": blue, "green": green, "blueLeft": blue_left, "blueCenter": blue_center}
            if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                saved = Path(destination) / self._testMethodName
                saved.mkdir(parents=True, exist_ok=True)
                shutil.copytree(content, saved / "content", dirs_exist_ok=True)
                if evidence.exists():
                    shutil.copytree(evidence, saved / "evidence", dirs_exist_ok=True)
                (saved / "app.log").write_text(log)
                (saved / "oracles.json").write_text(json.dumps(measured, indent=2))
                hashes = {key: hashlib.sha256(value).hexdigest() for key, value in entries.items()}
                hashes["project.json"] = hashlib.sha256((content / "project.json").read_bytes()).hexdigest()
                hashes["scene.pkg"] = hashlib.sha256((content / "scene.pkg").read_bytes()).hexdigest()
                (saved / "input-sha256.json").write_text(json.dumps(hashes, indent=2))
                (saved / "run.json").write_text(json.dumps({"command": command, "returncode": result.returncode, "app": str(self.app)}, indent=2))
            self.assertEqual(result.returncode, 0, log[-5000:])
            self.assertIn("gpuDrained=true", log)
            self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
            self.assertGreaterEqual(len(measured), 2)
            for name, value in measured.items():
                self.assertGreater(value["green"], 0, name)
                expected = [255, 255, 255] if shadow else [0, 0, 255] if consumer and not consumer_hidden else [0, 0, 0]
                if inactive_direct and name == "scene-after-window.png":
                    expected = [255, 0, 0]
                self.assertEqual(value["center"], expected, (name, value))
            if consumer and not shadow and not consumer_hidden:
                self.assertIn("phase=named-target-capture layer=11 status=succeeded", log)
                self.assertIn("phase=named-target-binding layer=22 status=succeeded", log)
                self.assertRegex(preview, r"prepared static base resources: entries=2 .*deferred=0 loaded=2 failed=0")
            if consumer_hidden:
                self.assertRegex(preview, r"prepared static base resources: entries=2 .*deferred=0 loaded=2 failed=0")
            if shadow:
                self.assertRegex(preview, r"prepared static base resources: entries=1 .*deferred=1 loaded=1 failed=0")
                self.assertNotIn("phase=named-target-capture layer=11 status=succeeded", log)
            for name, value in measured.items():
                shown = conditional and (live if name == "scene-after-window.png" and live is not None else launch) == "on"
                if shown:
                    self.assertGreater(value["blueLeft"], 0, (name, value))
                else:
                    self.assertEqual(value["blueLeft"], 0, (name, value))
            if live is not None:
                self.assertIn("phase=live-property-update accepted=true surfacesBefore=1 surfacesAfter=1", log)
            return log, preview, measured

    def test_inactive_direct_and_optional_siblings_hot_activate(self):
        self.run_provider(optional=True, inactive_direct=True, live="on")

    def test_constant_hidden_provider_remains_available(self):
        self.run_provider(conditional=False)

    def test_launch_hidden_conditional_provider_remains_available(self):
        self.run_provider()

    def test_hidden_unconsumed_image_stays_deferred(self):
        _, preview, _ = self.run_provider(consumer=False)
        self.assertRegex(preview, r"deferred=1\b")

    def test_live_show_keeps_consumer_and_reveals_source(self):
        self.run_provider(live="on")

    def test_live_hide_keeps_consumer_without_source_display(self):
        self.run_provider(launch="on", live="off")

    def test_hidden_consumer_source_is_conservatively_prepared(self):
        self.run_provider(consumer_hidden=True)

    def test_terminal_user_texture_does_not_prepare_named_source(self):
        self.run_provider(shadow=True)

    def test_optional_absent_provider_retains_named_fallback_source(self):
        self.run_provider(optional=True)
