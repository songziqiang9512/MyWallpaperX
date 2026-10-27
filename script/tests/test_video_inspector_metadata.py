"""Actual Video Inspector metadata helper's immediate template and async terminal.

Compiles the production DTO/helper and unchanged format/resolution/codec bodies
with the real VideoWallpaper model and AVFoundation. Inputs are a self-written
invalid video and a small generated PNG in a temporary HOME. This proves layout
facts before return, fallback terminal values and immediate cancellation. One
test-copy scheduling hook pauses after real AV work, before MainActor delivery,
to prove cancellation at that boundary without substituting AV results; it
does not establish valid-media codec/duration accuracy or native Inspector UI.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift"
MODEL = ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"
FIXTURE = ROOT / "script/tests/fixtures/VideoInspectorMetadataHarness.swift"


class VideoInspectorMetadataTests(unittest.TestCase):
    def test_real_helper_publishes_complete_template_before_return_and_honors_cancellation(self):
        source = SUPPORT.read_text()
        production = "import Foundation\nimport AVFoundation\n" + declaration(source, "struct WallpaperInspectorDetails:")
        helper_body = declaration(source, "func loadWallpaperInspectorDetails(")
        boundary = "        await MainActor.run {"
        self.assertEqual(helper_body.count(boundary), 1)
        helper_body = helper_body.replace(boundary, "        await InspectorMetadataDeliveryProbe.waitIfHeld(path)\n" + boundary, 1)
        production += "\n@discardableResult\n" + helper_body
        production += "\n" + "\n".join(declaration(source, signature) for signature in (
            "private func formattedDuration(", "private func videoResolutionText(", "private func videoCodecText("))
        paths = [SUPPORT, MODEL, FIXTURE, Path(__file__).resolve(), ROOT / "script/tests/test_ui_library_algorithms.py"]
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-inspector-metadata-", dir="/private/tmp") as folder:
            work = Path(folder)
            helper = work / "Production.swift"; helper.write_text(production)
            home = work / "home"; home.mkdir()
            env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            command = ["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                "-warnings-as-errors", str(MODEL), str(helper), str(FIXTURE),
                "-module-cache-path", str(work / "modules"), "-o", str(work / "checks")]
            build = subprocess.run(command, capture_output=True, text=True, env=env, timeout=120)
            proof = None
            if destination := os.environ.get("MWX_VIDEO_METADATA_PROOF_DIR"):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix="metadata-", dir=destination))
                (proof / "inputs.json").write_text(json.dumps({"inputs": inputs, "command": command, "scope": __doc__,
                    "transforms": ["extract production declarations; insert awaitable scheduling probe immediately before final MainActor delivery; no AV result or cancellation substitution"]}, indent=2))
                (proof / "compile.log").write_text(build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(work / "checks"), str(work)], capture_output=True, text=True, env=env, timeout=45)
            if proof:
                (proof / "stdout.log").write_text(run.stdout)
                (proof / "stderr.log").write_text(run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name + "\n" + run.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})
            print(json.dumps(checks, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
