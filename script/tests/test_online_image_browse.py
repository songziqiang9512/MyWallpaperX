"""Real browse session and source queries with controlled response delivery.

No App, windows, network, credentials or user media. Inputs are frozen before
compilation. A same-file fixture extension ages checkedAt in the frozen Session
copy; every product method remains unchanged. This permits a stale-cache case
without a five-minute wait or a product-only test seam.
Both sources use the actual typed author identity and return through loaded or
inflight origins; only an explicit author refresh invalidates its ID snapshot.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "Combine requires macOS")
class OnlineImageBrowseTests(unittest.TestCase):
    def test_real_viewport_paginates_on_last_visible_and_recovers_after_scroll(self):
        controller = ROOT / "MyWallpaperX/Shared/UI/OnlineImageBrowserController.swift"
        fixture = ROOT / "script/tests/fixtures/OnlineImagePagingViewportHarness.swift"
        text = controller.read_text()
        content = fixture.read_text()
        for marker, signature in (("REFRESH", "        grid.scrollView.onRefresh ="),
                                  ("SCROLL_SETTLED", "        grid.onScrollSettled ="),
                                  ("VIEWPORT", "    private func viewport("),
                                  ("CANCEL_PREFETCH", "    private func cancelPrefetch("),
                                  ("FOOTER", "    private func footerText(")):
            content = content.replace("// PRODUCTION_" + marker, declaration(text, signature).replace("private func", "func"))
        scroll = ROOT / "MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift"
        identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (controller, fixture, scroll)}
        with tempfile.TemporaryDirectory(prefix="mwx-image-paging-", dir="/private/tmp") as directory:
            work = Path(directory); source = work / "Checks.swift"; source.write_text(content)
            binary = work / "checks"
            built = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                str(source), str(scroll), "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=90)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout); self.assertGreaterEqual(len(checks), 10)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(result.stdout)
        self.assertEqual(identities, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (controller, fixture, scroll)})

    def test_cache_query_pagination_author_return_and_scope_boundaries(self):
        paths = [
            "MyWallpaperX/Models/WallpaperReference.swift",
            "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageBrowserSession.swift",
            "MyWallpaperX/Modules/Wallhaven/Core/WallhavenQuery.swift",
            "MyWallpaperX/Modules/Pixiv/Core/PixivQuery.swift",
            "script/tests/fixtures/OnlineImageBrowseHarness.swift",
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-online-image-browse-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources = work / "sources"; sources.mkdir()
            frozen, identities = [], {}
            for path in paths:
                data = (ROOT / path).read_bytes()
                identities[path] = hashlib.sha256(data).hexdigest()
                target = sources / Path(path).name
                target.write_bytes(data)
                if target.name == "OnlineImageBrowserSession.swift":
                    with target.open("a") as stream:
                        stream.write("\n// Fixture input only; product methods above are unchanged.\n"
                                     "extension OnlineImageBrowserSession {\n"
                                     "    func fixtureExpireCache() { state.checkedAt = .distantPast }\n"
                                     "}\n")
                frozen.append(str(target))
            home = work / "home"; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            binary = work / "checks"
            build = subprocess.run([
                "xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors",
                "-parse-as-library", *frozen, "-module-cache-path", str(work / "modules"),
                "-o", str(binary),
            ], capture_output=True, text=True, timeout=120, env=environment)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr + repr(identities))
            run = subprocess.run([str(binary)], capture_output=True, text=True,
                                 timeout=30, env=environment)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr + repr(identities))
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
