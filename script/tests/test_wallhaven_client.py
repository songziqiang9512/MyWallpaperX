"""Compile the real Wallhaven client/query/DTO and shared values against URLProtocol.

No credentials, Internet, App build, Keychain or user media are used. This covers
author/filter encoding, response projection, seed continuity, pagination,
cancellation, credential changes and HTTP failures; live observations are
separate ignored evidence.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MyWallpaperX/Modules/Wallhaven/Core"
FIXTURE = ROOT / "script/tests/fixtures/WallhavenClientHarness.swift"


@unittest.skipUnless(sys.platform == "darwin", "requires macOS Foundation URLSession")
class WallhavenClientTests(unittest.TestCase):
    def test_real_client_query_projection_failures_and_cancellation(self):
        sources = [ROOT / "MyWallpaperX/Models/WallpaperReference.swift",
                   ROOT / "MyWallpaperX/Models/WallpaperContent.swift",
                   ROOT / "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift",
                   CORE / "WallhavenQuery.swift", CORE / "WallhavenDTO.swift",
                   CORE / "WallhavenClient.swift", FIXTURE]
        before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
        with tempfile.TemporaryDirectory(prefix="mwx-wallhaven-client-", dir="/private/tmp") as directory:
            work = Path(directory)
            home = work / "home"; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            command = ["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                       "-warnings-as-errors", "-parse-as-library", *map(str, sources),
                       "-module-cache-path", str(work / "modules"), "-o", str(work / "checks")]
            built = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=120)
            proof = None
            if value := os.environ.get("MWX_WALLHAVEN_PROOF_DIR"):
                proof = Path(value); proof.mkdir(parents=True, exist_ok=True)
                (proof / "compile.log").write_text(built.stdout + built.stderr)
                (proof / "inputs.json").write_text(json.dumps(before, indent=2) + "\n")
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            arguments = [str(work / "checks")]
            if value := os.environ.get("MWX_WALLHAVEN_CAPTURE_DIR"):
                arguments.append(str(Path(value).resolve()))
            ran = subprocess.run(arguments, env=environment, capture_output=True,
                                 text=True, timeout=45)
            if proof:
                (proof / "checks.stdout.log").write_text(ran.stdout)
                (proof / "checks.stderr.log").write_text(ran.stderr)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(before, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources})


if __name__ == "__main__":
    unittest.main()
