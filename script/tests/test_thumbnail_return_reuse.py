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

# Match product isolation/conformance inference rather than the compiler defaults.
SWIFT_ISOLATION_FLAGS = ["-swift-version", "5", "-default-isolation", "MainActor"] + [
    argument
    for feature in ["DisableOutwardActorInference", "InferSendableFromCaptures",
                    "GlobalActorIsolatedTypesUsability", "MemberImportVisibility",
                    "InferIsolatedConformances", "NonisolatedNonsendingByDefault"]
    for argument in ["-enable-upcoming-feature", feature]
]


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
            sources = [shared / "GridThumbnailPrefetchDemand.swift", shared / "GridThumbnailDecoder.swift", shared / "DecodedThumbnailMemoryCache.swift", shared / "ThumbnailCache.swift",
                ROOT / "MyWallpaperX/Shared/WallpaperNetworkSession.swift",
                ROOT / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryThumbnailPipeline.swift",
                core / "SteamWorkshopModels.swift", core / "SteamWorkshopPreviewImageSupport.swift",
                core / "SteamWorkshopPreviewSource.swift", core / "SteamWorkshopPreviewRequestCoordinator.swift",
                core / "SteamWorkshopService+BrowseHydration.swift",
                core / "SteamWorkshopDownloadThumbnailPipeline.swift",
                ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewState.swift",
                ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewPlaceholderView.swift",
                ROOT / "script/tests/fixtures/ThumbnailReturnReuseChecks.swift"]
            # Expose only scheduling state/queue to hold the real worker at a
            # deterministic boundary. Instrument its actual fingerprint call;
            # no loader, coalescing, cancellation or completion body is replaced.
            prefetch_source = core / "SteamWorkshopService+BrowseHydration.swift"
            observed = prefetch_source.read_text().replace("private ", "")
            observed = observed.replace("steamWorkshopPreviewStillKey(for:", "checkedPrefetchKey(for:")
            prefetch_copy = work / prefetch_source.name
            prefetch_copy.write_text(observed)
            sources[sources.index(prefetch_source)] = prefetch_copy
            # Keep the eight local and twelve GIF disk-return assertions as
            # memory-only eviction of the original decoded owner.
            cache_source = shared / "ThumbnailCache.swift"
            cache = cache_source.read_text()
            self.assertEqual(cache.count("private let imageCache:"), 1)
            cache_copy = work / "ThumbnailCache.swift"
            cache_copy.write_text(cache.replace("private let imageCache:", "let imageCache:", 1))
            sources[sources.index(cache_source)] = cache_copy
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library", *map(str, sources),
                "-module-cache-path", str(work / "modules"), "-o", str(work / "checks")],
                capture_output=True, text=True, timeout=120)
            if proof := os.environ.get("MWX_REUSE_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "build.log").write_text(build.stdout + build.stderr)
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
            self.assertTrue({"coldAndDiskImageCallbacksStayOnMainAndCompleteOnce", "rawCallbackStaysOnMainAndCompletesOnce",
                             "warmMemoryReturnsSynchronously"}.issubset(facts["checks"]), facts)
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
