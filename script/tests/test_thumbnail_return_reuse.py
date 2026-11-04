"""Real image IO, disk/memory reuse, installed-source hydration and HTTP fallback."""
import collections
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
from script.tests.test_ui_library_algorithms import declaration

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
                    if self.path == "/late-online.gif":
                        (work / "online-http-held").touch()
                        deadline = time.monotonic() + 10
                        while not (work / "online-http-release").exists() and time.monotonic() < deadline:
                            time.sleep(0.001)
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
            sources = [ROOT / "MyWallpaperX/Shared/Components/WallpaperLibraryControlStyle.swift", shared / "GridThumbnailPrefetchDemand.swift", shared / "GridThumbnailDecoder.swift", shared / "DecodedThumbnailMemoryCache.swift", shared / "ThumbnailCache.swift",
                ROOT / "MyWallpaperX/Shared/WallpaperNetworkSession.swift",
                ROOT / "MyWallpaperX/Shared/UI/OnlineImageThumbnailPipeline.swift",
                core / "SteamWorkshopModels.swift", core / "SteamWorkshopPreviewImageSupport.swift",
                core / "SteamWorkshopPreviewSource.swift", core / "SteamWorkshopPreviewRequestCoordinator.swift",
                core / "SteamWorkshopService+BrowseHydration.swift",
                core / "SteamWorkshopDownloadThumbnailPipeline.swift",
                ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewState.swift",
                ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewPlaceholderView.swift",
                ROOT / "script/tests/fixtures/ThumbnailReturnReuseChecks.swift"]
            sources.append(ROOT / "MyWallpaperX/Shared/ThumbnailRequest.swift")
            adapter_source = ROOT / 'MyWallpaperX/App/WallpaperLibraryCellAdapter.swift'
            adapter = adapter_source.read_text()
            branch = adapter.split('            case .steam(let value):', 1)[1].split('\n            case .onlineImage', 1)[0]
            prefetch = declaration(adapter, '    private final class Prefetch').replace('private final class', 'final class', 1)
            support = work / 'ActualAdapterPrefetch.swift'
            support.write_text('import AppKit\n' + prefetch + '''
enum SteamWorkshopDownloadGridSupport {
    static func fallbackDisplayItem(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        preconditionFailure("Fixture supplies the original browser item")
    }
}
@MainActor func makeAdapterSteamPrefetch(_ value: SteamWorkshopDownloadRecord, pixels: Int) -> Prefetch {
    let demand = Prefetch(assets: []), steam = SteamWorkshopService(), steamPixelLimit = pixels
''' + branch + '\n    return demand\n}\n')
            state_source = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewState.swift'
            state = state_source.read_text()
            finish = declaration(state, '    private func finish(')
            hook = '        guard generation == expected else { return }'
            self.assertEqual(finish.count(hook), 1)
            observed = finish.replace(hook, hook + '\n        if let image, case let .image(source)? = source { AdapterPrefetchRetentionProbe.record(image, source: source.url) }', 1)
            state_copy = work / state_source.name
            state_copy.write_text(state.replace(finish, observed, 1))
            sources[sources.index(state_source)] = state_copy
            sources.append(support)
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
            cache = Path(os.environ.get("MWX_THUMBNAIL_CACHE_SOURCE", cache_source)).read_text()
            self.assertEqual(cache.count("private let imageCache:"), 1)
            cache_finish = declaration(cache, "    private func finishImageRequest(")
            finish_marker = "cachesFailure: Bool = false) -> Bool {"
            self.assertEqual(cache_finish.count(finish_marker), 1)
            observed_finish = cache_finish.replace(finish_marker, finish_marker +
                '\n        defer { ReuseInputObservation.counter.increment("finish:" + key) }', 1)
            cache = cache.replace(cache_finish, observed_finish, 1)
            cache_copy = work / "ThumbnailCache.swift"
            cache_copy.write_text(cache.replace("private let imageCache:", "let imageCache:", 1))
            sources[sources.index(cache_source)] = cache_copy
            decoder_source = shared / "GridThumbnailDecoder.swift"
            decoder = decoder_source.read_text()
            boundary = "    static func decodeInput(_ input: ThumbnailInput, request: ThumbnailRequest?) -> Image? {"
            self.assertEqual(decoder.count(boundary), 1)
            decoder_copy = work / decoder_source.name
            decoder_copy.write_text(decoder.replace(boundary, boundary +
                '\n        ReuseInputObservation.counter.increment("input")', 1))
            sources[sources.index(decoder_source)] = decoder_copy
            preview_source = core / "SteamWorkshopPreviewImageSupport.swift"
            preview = preview_source.read_text()
            boundary = "nonisolated func steamWorkshopPreviewImage(from data: Data, maxPixelSize: Int) -> NSImage? {"
            self.assertEqual(preview.count(boundary), 1)
            preview_copy = work / preview_source.name
            preview_copy.write_text(preview.replace(boundary, boundary +
                '\n    ReuseInputObservation.counter.increment("steam-decode-\\(maxPixelSize)")', 1))
            sources[sources.index(preview_source)] = preview_copy
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
            if proof := os.environ.get("MWX_REUSE_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "stdout.log").write_text(run.stdout); (target / "runtime.log").write_text(run.stderr)
                (target / 'actual-adapter-prefetch.swift').write_text(support.read_text())
                (target / 'observed-preview-state.swift').write_text(state_copy.read_text())
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            facts = json.loads(run.stdout)
            if proof := os.environ.get("MWX_REUSE_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "results.json").write_text(json.dumps(dict(facts, httpRequests=hits), indent=2))
            self.assertTrue({"coldAndDiskImageCallbacksStayOnMainAndCompleteOnce", "rawCallbackStaysOnMainAndCompletesOnce",
                             "warmMemoryReturnsSynchronously"}.issubset(facts["checks"]), facts)
            for tier in [256, 512, 800]:
                self.assertTrue({f"steam-{tier}-visible-reuses-prefetched-pixels-without-decoding",
                                 f"steam-{tier}-source-replacement-does-not-borrow-old-ready-pixels",
                                 f"steam-{tier}-clear-requires-fresh-pixels-but-keeps-live-view"}.issubset(facts["checks"]), facts)
            pixels = facts["taskRowPixels"]
            self.assertEqual(pixels["steam-256"]["width"], 256)
            self.assertLess(pixels["steam-256"]["bytes"], pixels["steam-800"]["bytes"])
            self.assertEqual((pixels["still-row"]["width"], pixels["still-row"]["height"]), (96, 64))
            for name, passed in facts["checks"].items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
            self.assertEqual(hits, {"/corrupt-fallback.gif": 1, "/missing-fallback.gif": 1, "/late-online.gif": 1})
            self.assertGreaterEqual(len(facts["checks"]), 15)


if __name__ == "__main__":
    unittest.main()
