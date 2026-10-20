"""Exercise the SIL source-probe owner across blocked filesystem completions."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]


class UISILVisiblePathProbeTests(unittest.TestCase):
    def test_single_flight_and_current_visible_resource_identity(self):
        product = (ROOT / "MyWallpaperX/Modules/StaticImageLibrary/UI/SILGridContainerView.swift").read_text()
        template = (ROOT / "script/tests/fixtures/UISILVisiblePathProbeHarness.swift").read_text()
        state = "\n".join(next(line for line in product.splitlines() if field in line) for field in [
            "private var isMissingPathProbeInFlight", "private var needsMissingPathProbeAfterFlight",
        ])
        probe = declaration(product, "    private func probeMissingPaths(")
        # Substitute only the filesystem leaf; scheduling, in-flight lifetime,
        # resource/visibility admission and collection reload use the real body.
        self.assertEqual(probe.count("FileManager.default"), 1)
        source = template.replace("// PRODUCTION_STATE", state).replace(
            "// PRODUCTION_PROBE", probe.replace("FileManager.default", "ProbeFileManager.shared"))
        with tempfile.TemporaryDirectory(prefix="mwx-sil-source-probe-", dir="/private/tmp") as directory:
            work = Path(directory)
            swift = work / "Checks.swift"
            swift.write_text(source)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift),
                                    "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 14)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
