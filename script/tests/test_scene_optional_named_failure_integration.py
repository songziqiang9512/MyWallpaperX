"""Unsupported named/optional inputs preserve effect-entry output, not execution."""
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
from .test_scene_hidden_provider_integration import fixture_entries
from .test_scene_pkg_cache_extractor import make_package


class SceneOptionalNamedFailureIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)

    def run_optional_named(self, *, supported):
        project, entries = fixture_entries(optional=True)
        if not supported:
            # Restore the original authored material candidate, rather than
            # normalizing the three-candidate chain into the supported profile.
            material = json.loads(entries["materials/own_sample.json"])
            material["passes"][0]["textures"] = [None, "_rt_imageLayerComposite_11_a"]
            entries["materials/own_sample.json"] = json.dumps(material).encode()
        package = make_package(list(entries.items()))
        project_bytes = json.dumps(project).encode()
        hashes = {path: hashlib.sha256(data).hexdigest() for path, data in entries.items()}
        hashes["project.json"] = hashlib.sha256(project_bytes).hexdigest()
        hashes["scene.pkg"] = hashlib.sha256(package).hexdigest()
        self.assertEqual(hashes["shaders/own_sample.frag"],
                         "6346a807c217f3f5526f616d264f1bbc344139785a785b2187907bef92171ee2")
        if not supported:
            self.assertEqual(hashes["scene.pkg"],
                             "905a211c779383c75961e471d1f5495ab0b5e87263398218cb76af05e7c98274")
            self.assertEqual(hashes["project.json"],
                             "d457f7253877a4e63ec520c6031894f39003eb6209ab095b215d8e3c57175908")

        with tempfile.TemporaryDirectory(prefix="mwx-optional-named-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            (content / "project.json").write_bytes(project_bytes)
            (content / "scene.pkg").write_bytes(package)
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home),
                       MWX_SCENE_DEBUG_SURFACE_COUNT="1")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                       "--mwx-debug-scene-duration", "6",
                       "--mwx-debug-scene-evidence-dir", str(evidence),
                       "--mwx-debug-scene-properties-json", json.dumps({"mode": "off"})]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            measured = {}
            for capture in sorted(evidence.glob("*-window.png")):
                decoded = png_rgb_pixels(capture)
                self.assertIsNotNone(decoded, capture.name)
                width, height, rows = decoded
                center = list(rows[height // 2][width // 2 * 3:width // 2 * 3 + 3])
                green = blue_left = blue_center = 0
                for row in rows[::8]:
                    for offset in range(0, len(row), 24):
                        r, g, b = row[offset:offset + 3]
                        is_blue = b > 200 and r < 30 and g < 30
                        x = offset // 3
                        blue_left += is_blue and x < width * (44 / 128)
                        blue_center += is_blue and abs(x - width / 2) < width * 0.05
                        green += g > 200 and r < 30 and b < 30
                measured[capture.name] = {"size": [width, height], "center": center,
                                          "green": green, "blueLeft": blue_left,
                                          "blueCenter": blue_center}
            if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                saved = Path(destination) / self._testMethodName
                saved.mkdir(parents=True, exist_ok=True)
                shutil.copytree(content, saved / "content", dirs_exist_ok=True)
                if evidence.exists():
                    shutil.copytree(evidence, saved / "evidence", dirs_exist_ok=True)
                (saved / "app.log").write_text(log)
                (saved / "oracles.json").write_text(json.dumps(measured, indent=2))
                (saved / "input-sha256.json").write_text(json.dumps(hashes, indent=2))
                (saved / "run.json").write_text(json.dumps({
                    "command": command, "returncode": result.returncode,
                    "app": str(self.app), "supported": supported,
                    "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                }, indent=2))

            self.assertEqual(result.returncode, 0, log[-5000:])
            self.assertNotIn("phase=launch-failed", log)
            self.assertNotRegex(log, r"MWX SCENE STARTUP:[^\n]*phase=failed")
            completions = re.findall(r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)
            self.assertTrue(any(frame == "0" for frame, _ in completions), log[-5000:])
            first_surfaces = {surface for frame, surface in completions if frame == "0"}
            self.assertTrue(any(int(frame) > 0 and surface in first_surfaces
                                for frame, surface in completions), log[-5000:])
            self.assertIn("phase=stopped surfacesBefore=1 surfacesAfter=0 gpuDrained=true", log)
            self.assertEqual(set(measured), {"scene-ready-window.png", "scene-after-window.png"})
            for reason in ("ready", "after"):
                self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
            for name, value in measured.items():
                self.assertEqual(value["center"], [0, 0, 255] if supported else [255, 255, 255],
                                 (name, value))
                self.assertGreater(value["green"], 0, (name, value))
                self.assertEqual(value["blueLeft"], 0, (name, value))
                if supported:
                    self.assertGreater(value["blueCenter"], 0, (name, value))
                else:
                    self.assertEqual(value["blueCenter"], 0, (name, value))
            capture_event = "phase=named-target-capture layer=11 status=succeeded"
            binding_event = "phase=named-target-binding layer=22 status=succeeded"
            if supported:
                self.assertIn(capture_event, log)
                self.assertIn(binding_event, log)
            else:
                self.assertNotIn(capture_event, log)
                self.assertNotIn(binding_event, log)

    def test_three_candidate_stage_preserves_effect_entry_and_peer(self):
        self.run_optional_named(supported=False)

    def test_exact_two_candidate_fallback_remains_blue(self):
        self.run_optional_named(supported=True)
