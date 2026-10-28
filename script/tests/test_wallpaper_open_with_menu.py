"""Native Open With menus with controlled system handler/launch I/O only.

No external application, user file, window or network request is opened.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperOpenWithMenuTests(unittest.TestCase):
    def test_system_handlers_fixed_multiselection_and_async_failure(self):
        product = ROOT / "MyWallpaperX/Shared/UI/WallpaperOpenWithMenu.swift"
        actions = ROOT / "MyWallpaperX/Shared/Components/ActionMenuItem.swift"
        fixture = ROOT / "script/tests/fixtures/WallpaperOpenWithMenuChecks.swift"
        inputs = [product, actions, fixture, Path(__file__)]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        source = product.read_text()
        self.assertEqual(source.count("NSWorkspace.shared"), 1)
        source = source.replace("NSWorkspace.shared", "OpenWithWorkspaceLeaf.shared")
        body = fixture.read_text().replace("// ACTUAL_OPEN_WITH_FACTORY", source)
        with tempfile.TemporaryDirectory(prefix="mwx-open-with-", dir="/private/tmp") as folder:
            work = Path(folder)
            actual = work / "Checks.swift"; actual.write_text(body)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors",
                str(actions), str(actual), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            self.assertTrue(checks)
            for name, value in checks.items():
                with self.subTest(name=name): self.assertIs(value, True, result.stdout + result.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})


if __name__ == "__main__": unittest.main()
