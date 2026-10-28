"""Native translucent form fields and the original shared API-key sheet.

Only service storage/search are recording leaves. The actual presentation
methods, shared controller, text editor, NSAlert baseline, native key equivalents, Tab queue and surfaces run unchanged.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperFormFieldTests(unittest.TestCase):
    def test_native_api_key_input_default_cancel_and_shared_surface(self):
        paths = [ROOT / path for path in (
            "MyWallpaperX/Shared/Components/WallpaperFormFieldStyle.swift",
            "MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift",
            "MyWallpaperX/Shared/UI/ModalPresentation.swift",
            "MyWallpaperX/Shared/UI/WallpaperAPIKeyPanelController.swift",
            "script/tests/fixtures/NativeAppHarness.swift")]
        producer = ROOT / "MyWallpaperX/Modules/Pixabay/UI/PixabayBrowserView.swift"
        fixture = ROOT / "script/tests/fixtures/WallpaperFormFieldHarness.swift"
        observed = paths + [producer, fixture, Path(__file__), ROOT / "script/tests/native_app_harness.py",
                            ROOT / "script/tests/test_ui_library_algorithms.py",
                            ROOT / "script/tests/test_video_thumbnail_prefetch.py"]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        original = producer.read_text()
        methods = []
        for signature in ("    @objc private func presentAPIKeyEditFromAction(", "    @objc private func presentAPIKeyEdit("):
            self.assertEqual(original.count(signature), 1, signature)
            methods.append(declaration(original, signature))
        body = fixture.read_text()
        self.assertEqual(body.count("// ACTUAL_API_KEY_PRESENTATION"), 1)
        body = body.replace("// ACTUAL_API_KEY_PRESENTATION", "\n".join(methods))
        with tempfile.TemporaryDirectory(prefix="mwx-form-fields-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            copies = []
            for path in paths:
                target = work / path.name
                shutil.copy2(path, target)
                copies.append(str(target))
            target = work / "Checks.swift"
            target.write_text(body)
            binary = prepare_native_app(work, "WallpaperFormFields")
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *copies, str(target), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=40)
            diagnostic = f"LaunchServices={run.launch_returncode}\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
            self.assertEqual(run.launch_returncode, 0, diagnostic)
            self.assertTrue(run.stdout.strip().startswith("{"), diagnostic)
            checks = json.loads(run.stdout)
            self.assertTrue(checks, diagnostic)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, diagnostic)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == "__main__":
    unittest.main()
