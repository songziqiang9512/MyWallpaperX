"""Compile the real footer state and verify passive status and the single-owner scroll continuation wiring."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "MyWallpaperX/Modules/SteamWorkshop"
CORE = MODULE / "Core"
UI = MODULE / "UI"


class SteamBrowseFailureFooterTests(unittest.TestCase):
    def test_failure_footer_state_contract(self):
        with tempfile.TemporaryDirectory(prefix="mwx-steam-footer-") as folder:
            binary = Path(folder) / "steam-browse-footer"
            fixture = Path(folder) / "Checks.swift"
            actual = declaration((CORE / "SteamWorkshopService+BrowsePageLoading.swift").read_text(),
                                 "    func retryLoadingMoreBrowserItems()")
            fixture.write_text((ROOT / "script/tests/fixtures/SteamBrowseFooterHarness.swift").read_text()
                               .replace("// ACTUAL_RETRY", actual))
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-parse-as-library",
                    str(UI / "AppKitSteamWorkshopBrowserFooterComponents.swift"),
                    str(UI / "SteamWorkshopBrowserFooterSupport.swift"),
                    str(fixture),
                    "-o",
                    str(binary),
                ],
                check=True,
                timeout=120,
            )
            subprocess.run([str(binary)], check=True, timeout=30)

    def test_scroll_continuation_reuses_current_pagination_owner(self):
        service = (CORE / "SteamWorkshopService.swift").read_text()
        browse = (CORE / "SteamWorkshopService+SteamKitBrowse.swift").read_text()
        page_loading = (CORE / "SteamWorkshopService+BrowsePageLoading.swift").read_text()
        grid = (UI / "AppKitSteamWorkshopBrowserGridView.swift").read_text()
        components = (UI / "AppKitSteamWorkshopBrowserFooterComponents.swift").read_text()

        self.assertIn("@Published var browserLoadMoreFailureMessage: String?", service)
        self.assertEqual(browse.count('browserLoadMoreFailureMessage = "加载失败 · 重试"'), 2)
        retry = page_loading[page_loading.index("    func retryLoadingMoreBrowserItems()") :]
        self.assertIn("consecutiveEmptyLoadMorePages = 0", retry)
        self.assertIn("browserLoadMoreRetryAfter = .distantPast", retry)
        self.assertIn("loadMoreBrowserItemsIfNeeded()", retry)
        self.assertNotIn("steamKitBrowseStore.fetch", retry)
        self.assertIn("service.$browserLoadMoreFailureMessage", grid)
        self.assertIn("service.retryLoadingMoreBrowserItems()", grid)
        self.assertIn("scrollView.onScrollSettled", grid)
        self.assertNotIn("NSButton", components)
        self.assertNotIn("retryHandler", components)


if __name__ == "__main__":
    unittest.main()
