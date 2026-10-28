"""Real AppKit preview images survive hover, eviction and detail reconstruction.

Exercises production card/container code with generated media in an isolated HOME.
The lifecycle fixture also controls asynchronous delivery to reject stale results.
"""
from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_steam_list_thumbnail_animation import SOURCES, SUPPORT, UI
from script.tests.native_app_harness import prepare_native_app, run_native_app

ROOT = pathlib.Path(__file__).resolve().parents[2]


class SteamPreviewLifecycleTests(unittest.TestCase):
    def test_preview_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="mwx-preview-lifecycle-", dir="/private/tmp") as directory:
            work = pathlib.Path(directory)
            support = work / "Support.swift"
            support.write_text(SUPPORT.replace(
                "@Published var source: Int = 0",
                "@Published var source: Int = 0\n    @Published var previewReloadToken: Int = 0"))
            sources = [*SOURCES, UI / "SteamWorkshopItemDetailPreviewSupport.swift",
                       ROOT / "script/tests/fixtures/GridCardInteractionChecks.swift",
                       ROOT / "script/tests/fixtures/NativeAppHarness.swift"]
            sources += [ROOT / "MyWallpaperX" / name for name in (
                "Models/WallpaperReference.swift", "Models/WallpaperContent.swift", "Models/WallpaperLibraryPage.swift",
                "Shared/Components/WallpaperLibraryGridMetrics.swift", "Shared/UI/BoxSelectionState.swift",
                "Shared/UI/GridThumbnailPrefetchDemand.swift", "Shell/WallpaperLibraryGridController.swift")]
            # Visible preview preservation is exercised after decoded-memory
            # eviction; clearing disk here would change that original oracle.
            cache_source = ROOT / "MyWallpaperX/Shared/UI/ThumbnailCache.swift"
            cache = cache_source.read_text()
            self.assertEqual(cache.count("private let imageCache:"), 1)
            cache_copy = work / "ThumbnailCache.swift"
            cache_copy.write_text(cache.replace("private let imageCache:", "let imageCache:", 1))
            sources[sources.index(cache_source)] = cache_copy
            # The generic native row consumes the original real preview cache.
            # Expose only its image view in the test copy for pixel identity.
            row_path = ROOT / "MyWallpaperX/Modules/Downloads/UI/DownloadTaskRowView.swift"
            row = row_path.read_text()
            self.assertEqual(row.count("private let thumbnailView ="), 1)
            row_copy = work / "DownloadTaskRowView.swift"
            row_copy.write_text(row.replace("private let thumbnailView =", "let thumbnailView =", 1))
            sources += [row_copy, ROOT / "MyWallpaperX/Models/DownloadTask.swift",
                        ROOT / "MyWallpaperX/Modules/Downloads/Core/DownloadTaskProjection.swift"]
            probe = work / "PopoverPreviewProbe.swift"
            probe.write_text(POPOVER_PROBE)
            harness = ROOT / "script/tests/fixtures/SteamPreviewLifecycleHarness.swift"
            binary = work / "preview"
            build = subprocess.run([
                "xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                str(support), str(harness), str(probe), str(ROOT / "script/tests/fixtures/SteamPreviewStateChecks.swift"), "-module-cache-path", str(work / "modules"),
                "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            result = subprocess.run([str(binary), str(work)],
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            proof = os.environ.get("MWX_PREVIEW_PROOF_DIR")
            if proof:
                target = pathlib.Path(proof)
                target.mkdir(parents=True, exist_ok=True)
                (target / "facts.json").write_text(json.dumps(facts, indent=2) + "\n")
                (target / "runtime.log").write_text(result.stderr)
                (target / "compile.log").write_text(build.stdout + build.stderr)
            for name, passed in facts.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
            self.assertTrue(facts)

            # Added active-hover checks need LaunchServices. Its status is only
            # the launcher's; the original direct-child exit assertion above stays.
            native_binary = prepare_native_app(work, "SteamPreviewChecks")
            shutil.copy2(binary, native_binary)
            interaction = run_native_app(native_binary, ["--card-interactions"], timeout=45,
                                         proof_environment="MWX_PREVIEW_PROOF_DIR")
            self.assertEqual(interaction.launch_returncode, 0, interaction.stdout + interaction.stderr)
            interaction_checks = json.loads(interaction.stdout)
            self.assertEqual(len(interaction_checks), 32)
            for name, passed in interaction_checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)
            if proof:
                (target / "card-interactions.json").write_text(interaction.stdout)
                (target / "card-interactions-runtime.log").write_text(interaction.stderr)



POPOVER_PROBE = r'''
import AppKit
@MainActor final class SteamPopoverPreviewProbe {
    let row: DownloadTaskRowView
    let url: URL
    var thumbnailView: NSImageView { row.thumbnailView }
    init(url: URL) {
        self.url = url
        row = DownloadTaskRowView(bindings: .init(perform: { _, _ in }, loadThumbnail: { _, receive in
            let cancellation = SteamWorkshopPreviewLoadCancellation()
            steamWorkshopLoadPreviewImage(from: url, cancellation: cancellation, completion: receive)
            return { cancellation.cancel() }
        }))
    }
    func load() {
        row.configure(.init(id: .init(reference: .init(provider: .steamWorkshop, sourceID: "row"), attemptID: "preview"),
                            title: "queue preview", phase: .completed, thumbnailKey: url.absoluteString))
    }
    func unbind() { row.unbind() }
}
'''

if __name__ == "__main__":
    unittest.main()
