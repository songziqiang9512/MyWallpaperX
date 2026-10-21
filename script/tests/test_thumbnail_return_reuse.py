"""Real image IO, disk/memory reuse, installed-source hydration and HTTP fallback."""
import collections
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ThumbnailReturnReuseTests(unittest.TestCase):
    def test_cached_returns_and_local_first_network_fallback(self):
        with tempfile.TemporaryDirectory(prefix="mwx-thumbnail-return-", dir="/private/tmp") as folder:
            work = Path(folder)
            # Served bytes remain independent of the local preview that the
            # Swift fixture later replaces and deletes.
            hits = collections.Counter()

            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    hits[self.path] += 1
                    body = (work / "remote.gif").read_bytes()
                    self.send_response(200)
                    self.send_header("Content-Type", "image/gif")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)

                def log_message(self, *_):
                    pass

            core = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core"
            shared = ROOT / "MyWallpaperX/Shared/UI"
            sources = [shared / "GridThumbnailDecoder.swift", shared / "DecodedThumbnailMemoryCache.swift", shared / "ThumbnailCache.swift",
                ROOT / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryThumbnailPipeline.swift",
                core / "SteamWorkshopModels.swift", core / "SteamWorkshopPreviewImageSupport.swift",
                core / "SteamWorkshopPreviewSource.swift", core / "SteamWorkshopPreviewRequestCoordinator.swift",
                core / "SteamWorkshopService+BrowseHydration.swift",
                core / "SteamWorkshopDownloadThumbnailPipeline.swift",
                ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewState.swift",
                ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewPlaceholderView.swift",
                ROOT / "script/tests/fixtures/ThumbnailReturnReuseChecks.swift"]
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                "-module-cache-path", str(work / "modules"), "-o", str(work / "checks")],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                run = subprocess.run([str(work / "checks")], env=dict(os.environ,
                    HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home"),
                    REUSE_FIXTURE_ROOT=str(work), REUSE_FIXTURE_REMOTE=f"http://127.0.0.1:{server.server_port}"),
                    capture_output=True, text=True, timeout=60)
            finally:
                server.shutdown(); server.server_close(); thread.join()
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            facts = json.loads(run.stdout)
            for name, passed in facts["checks"].items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
            self.assertEqual(hits, {"/corrupt-fallback.gif": 1, "/missing-fallback.gif": 1})
            self.assertGreaterEqual(len(facts["checks"]), 15)
            if proof := os.environ.get("MWX_REUSE_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "results.json").write_text(json.dumps(dict(facts, httpRequests=hits), indent=2))
                (target / "runtime.log").write_text(run.stderr)


if __name__ == "__main__":
    unittest.main()
