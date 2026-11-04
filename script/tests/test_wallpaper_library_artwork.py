"""Demand-lifetime playlist composition and delegation to original thumbnail owners.

Source delegation uses controlled leaves. Retention uses real ImageIO JPEGs and
the decoded LRU; AV/network/visibility regressions remain in their nearest gates.
Selection, source alpha and cancellation use actual composed pixels.
"""
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from script.tests.native_app_harness import native_app_session
from script.tests.test_thumbnail_return_reuse import SWIFT_ISOLATION_FLAGS
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryArtworkTests(unittest.TestCase):
    def test_real_steam_terminal_source_lifetime(self):
        names = (
            "MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Models/WallpaperLibraryPage.swift", "MyWallpaperX/Shared/UI/WallpaperPlaylistArtwork.swift",
            "MyWallpaperX/Shared/UI/ListThumbnailTintSource.swift", "MyWallpaperX/Shared/ThumbnailRequest.swift",
            "MyWallpaperX/Shared/UI/GridThumbnailDecoder.swift", "MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift",
            "MyWallpaperX/Shared/UI/ThumbnailCache.swift", "MyWallpaperX/Shared/Components/WallpaperLibraryControlStyle.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewImageSupport.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewSource.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewRequestCoordinator.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopDownloadThumbnailPipeline.swift",
            "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewState.swift",
            "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopPreviewPlaceholderView.swift",
            "MyWallpaperX/App/WallpaperLibraryArtworkProvider.swift",
            "script/tests/fixtures/WallpaperLibraryArtworkHarness.swift",
            "script/tests/fixtures/ArtworkSteamSourceLifetimeChecks.swift")
        paths = [ROOT / name for name in names]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        proof = Path(os.environ["MWX_ARTWORK_PROOF_DIR"]) / "steam" if os.environ.get("MWX_ARTWORK_PROOF_DIR") else None
        if proof: proof.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mwx-artwork-steam-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen = []
            for index, path in enumerate(paths):
                source = path.read_text()
                if path.name == "WallpaperLibraryArtworkProvider.swift":
                    factory = declaration(source, "    static func liveLoader(")
                    branch = factory.split("            case .steamWorkshop:\n", 1)[1].split("            case .pixabay:", 1)[0]
                    convenience = declaration(source, "    convenience init(manager:")
                    source = source.replace(convenience, "").replace(factory, "")
                    # Keep the exact State creation/configure/cancel branch;
                    # only unused source dispatch and service lookup are leaves.
                    source += '''
@MainActor func makeActualSteamArtworkLoader(_ steam: SteamWorkshopService) -> WallpaperLibraryArtworkProvider.Loader {
    return { content, completion in
        let reference = content.providerReference
        func matches(_ id: String) -> Bool { id.utf8.elementsEqual(reference.sourceID.utf8) }
        guard content.publishedAvailability == .available else { completion(nil); return {} }
''' + branch + "\n    }\n}\n"
                    if proof: (proof / "actual-steam-artwork.swift").write_text(source)
                elif path.name == "WallpaperLibraryArtworkHarness.swift":
                    source = "import AppKit\nimport ImageIO\n" + declaration(source, "@MainActor func artworkEncodedSourceData(")
                elif path.name == "SteamWorkshopPreviewSource.swift":
                    source = source.replace(declaration(source, "func steamWorkshopPreviewSources("), "")
                elif path.name == "SteamWorkshopPreviewState.swift":
                    initializer = "init(loaders: Loaders? = nil) { self.loaders = loaders ?? .live() }"
                    self.assertEqual(source.count(initializer), 1)
                    source = source.replace(initializer, initializer[:-1] + "; ArtworkSteamObservation.states.append(.init(self)) }")
                    finish = declaration(source, "    private func finish(")
                    hook = "        guard generation == expected else { return }"
                    self.assertEqual(finish.count(hook), 1)
                    observed = finish.replace(hook, hook + '''
        if let image, let source {
            switch source {
            case .image(let value), .video(let value): ArtworkSteamObservation.record(image, source: value.url)
            }
        }''', 1)
                    source = source.replace(finish, observed)
                    if proof: (proof / "observed-preview-state.swift").write_text(source)
                target = work / f"Source{index}.swift"
                target.write_text(source); frozen.append(target)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *SWIFT_ISOLATION_FLAGS,
                *map(str, frozen), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            if proof: (proof / "build.log").write_text(build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            hits = {"retry": 0}

            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    hits["retry"] += 1
                    body = b"" if hits["retry"] == 1 else (work / "cold.jpg").read_bytes()
                    self.send_response(503 if hits["retry"] == 1 else 200)
                    self.send_header("Content-Type", "image/jpeg")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers(); self.wfile.write(body)

                def log_message(self, *_):
                    pass

            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            home = work / "home"; home.mkdir()
            try:
                with native_app_session():
                    run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                        ARTWORK_STEAM_ROOT=str(work), ARTWORK_STEAM_REMOTE=f"http://127.0.0.1:{server.server_port}"),
                        capture_output=True, text=True, timeout=90)
            finally:
                server.shutdown(); server.server_close(); thread.join()
            if proof:
                (proof / "stdout.log").write_text(run.stdout); (proof / "stderr.log").write_text(run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            result = json.loads(run.stdout)
            result["httpRequests"] = hits
            if proof: (proof / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            print("ARTWORK STEAM RESOURCE " + json.dumps(result["resource"], sort_keys=True), flush=True)
            self.assertGreaterEqual(len(result["checks"]), 20)
            for name, passed in result["checks"].items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            self.assertGreaterEqual(hits["retry"], 2)
            resource = result["resource"]
            self.assertEqual(resource["inputCount"], 96)
            self.assertEqual(resource["clearedSources"], {"alive": 0, "bytes": 0})
            self.assertEqual(resource["clearedOutputs"]["alive"], 96)
            self.assertEqual(resource["retiredOutputs"], {"alive": 0, "bytes": 0})
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})

    def test_visible_demand_identity_cancellation_composition_and_tint(self):
        paths = [ROOT / name for name in (
            "MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Models/WallpaperLibraryPage.swift", "MyWallpaperX/Shared/UI/WallpaperPlaylistArtwork.swift", "MyWallpaperX/Shared/UI/ListThumbnailTintSource.swift",
            "MyWallpaperX/Shared/ThumbnailRequest.swift", "MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift", "MyWallpaperX/Core/OnlineImages/OnlineImageContentProjection.swift",
            "script/tests/fixtures/OnlineImageLibraryAppStub.swift",
            "MyWallpaperX/App/WallpaperLibraryArtworkProvider.swift", "script/tests/fixtures/WallpaperLibraryArtworkHarness.swift")]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        proof = Path(os.environ["MWX_ARTWORK_PROOF_DIR"]) if os.environ.get("MWX_ARTWORK_PROOF_DIR") else None
        if proof: proof.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mwx-artwork-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen = []
            for index, path in enumerate(paths):
                target = work / f"Source{index}.swift"
                target.write_bytes(path.read_bytes()); frozen.append(target)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, frozen), "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=120)
            if proof: (proof / "build.log").write_text(build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            with native_app_session():
                run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                    capture_output=True, text=True, timeout=30)
            if proof:
                (proof / "stdout.log").write_text(run.stdout)
                (proof / "stderr.log").write_text(run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            result = json.loads(run.stdout)
            if proof: (proof / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            print("ARTWORK RESOURCE " + json.dumps(result["resource"], sort_keys=True), flush=True)
            checks = result["checks"]
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            resource = result["resource"]
            self.assertEqual(resource["inputCount"], 96)
            self.assertEqual(resource["clearedSources"], {"alive": 0, "bytes": 0})
            self.assertEqual(resource["clearedOutputs"]["alive"], 96)
            self.assertEqual(resource["retiredOutputs"], {"alive": 0, "bytes": 0})
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__": unittest.main()
