"""Compile the real footer state and verify the single-owner load-more retry wiring."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "MyWallpaperX/Modules/SteamWorkshop"
CORE = MODULE / "Core"
UI = MODULE / "UI"


class SteamBrowseFailureFooterTests(unittest.TestCase):
    def test_failure_footer_state_contract(self):
        with tempfile.TemporaryDirectory(prefix="mwx-steam-footer-") as folder:
            binary = Path(folder) / "steam-browse-footer"
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-parse-as-library",
                    str(UI / "AppKitSteamWorkshopBrowserFooterComponents.swift"),
                    str(UI / "SteamWorkshopBrowserFooterSupport.swift"),
                    str(ROOT / "script/tests/fixtures/SteamBrowseFooterHarness.swift"),
                    "-o",
                    str(binary),
                ],
                check=True,
                timeout=120,
            )
            subprocess.run([str(binary)], check=True, timeout=30)

    def test_retry_reuses_current_pagination_owner(self):
        service = (CORE / "SteamWorkshopService.swift").read_text()
        browse = (CORE / "SteamWorkshopService+SteamKitBrowse.swift").read_text()
        page_loading = (CORE / "SteamWorkshopService+BrowsePageLoading.swift").read_text()
        grid = (UI / "AppKitSteamWorkshopBrowserGridView.swift").read_text()
        components = (UI / "AppKitSteamWorkshopBrowserFooterComponents.swift").read_text()

        self.assertIn("@Published var browserLoadMoreFailureMessage: String?", service)
        self.assertEqual(browse.count('browserLoadMoreFailureMessage = "加载失败 · 重试"'), 2)
        retry = page_loading[page_loading.index("    func retryLoadingMoreBrowserItems()") :]
        self.assertIn("guard browserState == .loaded", retry)
        self.assertIn("consecutiveEmptyLoadMorePages = 0", retry)
        self.assertIn("browserLoadMoreRetryAfter = .distantPast", retry)
        self.assertIn("loadMoreBrowserItemsIfNeeded()", retry)
        self.assertNotIn("steamKitBrowseStore.fetch", retry)
        self.assertIn("service.$browserLoadMoreFailureMessage", grid)
        self.assertIn("self?.service.retryLoadingMoreBrowserItems()", grid)
        self.assertIn('retryButton.setAccessibilityLabel("重试加载更多项目")', components)


if __name__ == "__main__":
    unittest.main()
