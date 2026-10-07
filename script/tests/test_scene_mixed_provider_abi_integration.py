"""Real App mixed-provider color ABI with an ordinary three-sampler shader.

Owned package inputs only. A frozen MWX_SCENE_INTEGRATION_APP is required;
passing pixels/receipts establish this bounded chain, not official parity.
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

from .test_scene_hidden_provider_integration import fixture_entries as hidden_fixture
from .test_scene_directional_shadow_integration import png
from .test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from .test_scene_composition_authored_order_integration import measure_capture
from .test_scene_pkg_cache_extractor import make_package


REPO = Path(__file__).resolve().parents[2]
FRAGMENT = b'''uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1; // {"mode":"rgbmask","default":"util/white"}
uniform sampler2D g_Texture2; // {"mode":"opacitymask"}
varying vec2 v_TexCoord;
void main() {
    vec4 base = texSample2D(g_Texture0, v_TexCoord);
    vec4 ink = texSample2D(g_Texture1, v_TexCoord);
    vec4 mask = texSample2D(g_Texture2, v_TexCoord);
    ink.rgb *= base.rgb;
    ink.a *= mask.r;
    gl_FragColor = ink;
}
'''
SOURCE_RGBA = (200, 80, 160, 128)
MASK_RGBA = (128, 128, 128, 255)
# Straight color crosses the named PMA publication boundary, then alpha and
# the independent mask are applied once. Double-premultiplication halves RGB.
EXPECTED_RGB = tuple(round(c * SOURCE_RGBA[3] / 255 * MASK_RGBA[0] / 255)
                     for c in SOURCE_RGBA[:3])


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def fixture_entries(*, three_candidates=False):
    project, entries = hidden_fixture(optional=True)
    scene = json.loads(entries["scene.json"])
    provider, consumer, peer = scene["objects"]
    provider["name"] = "Hidden half-alpha colored named source"
    consumer["name"] = "Ordinary three-slot color and opacity-mask consumer"
    peer["origin"] = "96 64 0"
    instance = consumer["effects"][0]["passes"][0]
    instance["textures"].append(None)
    instance["usertextures"].append(None)
    material = json.loads(entries["materials/own_sample.json"])
    material["passes"][0]["textures"] = [None,
        "_rt_imageLayerComposite_11_a" if three_candidates else None,
        "materials/own_opacity.png"]
    source_material = json.loads(entries["materials/blue.json"])
    source_material["passes"][0]["blending"] = "translucent"
    entries.update({"scene.json": encoded(scene),
                    "materials/own_sample.json": encoded(material),
                    "materials/blue.json": encoded(source_material),
                    "materials/blue.png": png(SOURCE_RGBA),
                    "materials/own_opacity.png": png(MASK_RGBA),
                    "shaders/own_sample.frag": FRAGMENT})
    return project, entries


class SceneMixedProviderABIIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App")
        app = Path(configured).resolve(strict=True)
        cls.exe = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app
        cls.app_identity = app_hashes(cls.exe)

    def run_case(self, *, three_candidates=False):
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        root = Path(tempfile.mkdtemp(prefix="mixed-provider-abi-", dir=parent))
        if not parent:
            self.addCleanup(shutil.rmtree, root)
        print(f"mixed provider ABI evidence: {root}", flush=True)
        content, home, evidence = root / "content", root / "home", root / "evidence"
        content.mkdir()
        home.mkdir()
        project, entries = fixture_entries(three_candidates=three_candidates)
        (content / "project.json").write_bytes(encoded(project))
        (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
        expected = (255, 255, 255) if three_candidates else EXPECTED_RGB
        # Reuse the existing 256-square capture mapper: this 128-square scene
        # occupies the same normalized coordinates after doubling the ROIs.
        oracle = {"consumer": {"canvasRect": (116, 116, 140, 140), "expectedRGB": expected},
                  "hiddenProvider": {"canvasRect": (36, 116, 60, 140), "expectedRGB": (0, 0, 0)},
                  "peer": {"canvasRect": (186, 122, 198, 134), "expectedRGB": (0, 255, 0)}}
        protocol = {"threeCandidates": three_candidates, "sourceRGBA": SOURCE_RGBA,
                    "maskRGBA": MASK_RGBA, "expectedConsumerRGB": expected,
                    "sceneCanvas": 128, "oracleCanvas": 256,
                    "channelTolerance": 2, "minimumCorrectFraction": .99,
                    "oracle": oracle, "optionalSystemInput": "absent mediaThumbnail",
                    "colorBoundary": "named PMA sample -> straight RGB, alpha mask -> one PMA output"}
        command = [str(self.exe), "--mwx-debug-scene-root", str(content),
                   "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence),
                   "--mwx-debug-scene-properties-json", json.dumps({"mode": "off"})]
        before_inputs = file_hashes(tuple(content.iterdir()))
        identity = {"command": command, "appSHA256": self.app_identity,
                    "inputSHA256": before_inputs,
                    "entrySHA256": {name: hashlib.sha256(value).hexdigest() for name, value in entries.items()},
                    "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "protocol": protocol}
        (root / "prerun.json").write_bytes(encoded(identity))
        self.assertEqual(app_hashes(self.exe), self.app_identity)
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                   MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
        with (root / "app.log").open("w") as output:
            result = subprocess.run(command, cwd=REPO, env=env, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=90)
        log = (root / "app.log").read_text()
        preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
        captures = sorted(evidence.glob("*-window.png"))
        pixels = {path.name: measure_capture(path, protocol) for path in captures}
        (root / "result.json").write_bytes(encoded({"exit": result.returncode, "pixels": pixels,
            "appAfter": app_hashes(self.exe), "inputsAfter": file_hashes(tuple(content.iterdir())),
            "boundary": "owned inputs and actual Metal/compositor, no official parity"}))
        self.assertEqual(app_hashes(self.exe), self.app_identity)
        self.assertEqual(file_hashes(tuple(content.iterdir())), before_inputs)
        self.assertEqual(result.returncode, 0, log[-5000:])
        self.assertNotRegex(log, r"MWX SCENE STARTUP:[^\n]*phase=failed")
        self.assertNotIn("phase=launch-failed", log)
        completions = re.findall(r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)
        surfaces = {surface for frame, surface in completions if frame == "0"}
        self.assertTrue(surfaces, log[-5000:])
        self.assertTrue(any(int(frame) > 0 and surface in surfaces for frame, surface in completions))
        self.assertIn("phase=stopped surfacesBefore=1 surfacesAfter=0 gpuDrained=true", log)
        self.assertEqual(set(pixels), {"scene-ready-window.png", "scene-after-window.png"})
        for reason in ("ready", "after"):
            self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
        for capture, measured in pixels.items():
            for roi, value in measured["rois"].items():
                with self.subTest(capture=capture, roi=roi):
                    self.assertGreater(value["total"], 0, value)
                    self.assertGreaterEqual(value["correct"] / value["total"], .99, value)
        capture_event = "phase=named-target-capture layer=11 status=succeeded"
        binding_event = "phase=named-target-binding layer=22 status=succeeded"
        if three_candidates:
            self.assertIn("optional-named-fallback-unproven", log + preview)
            self.assertNotIn(binding_event, log)
            self.assertNotRegex(log + preview, r"generic shader execution [^\n]*layer=22 effect=0 ")
        else:
            self.assertNotIn("optional-named-fallback-unproven", log + preview)
            self.assertIn(capture_event, log)
            self.assertIn(binding_event, log)
            self.assertRegex(log + preview, r"generic shader execution [^\n]*layer=22 effect=0 ")

    def test_ordinary_three_slot_fallback_preserves_half_alpha_named_color(self):
        self.run_case()

    def test_three_candidate_chain_degrades_locally_and_preserves_peer(self):
        self.run_case(three_candidates=True)


if __name__ == "__main__":
    unittest.main()
