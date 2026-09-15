"""Exercise the shared Steam grid keyboard owner and its AppKit wiring."""
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI"
KEYBOARD = UI / "SteamWorkshopGridKeyboardNavigation.swift"


class SteamKeyboardNavigationTests(unittest.TestCase):
    def test_navigation_clamps_rows_and_rejects_non_navigation_keys(self):
        harness = r'''
import Foundation

@main struct Harness {
    static func main() {
        func destination(_ key: UInt16, _ current: Int?, count: Int = 10, columns: Int = 3) -> Int? {
            SteamWorkshopGridKeyboardNavigation.destinationIndex(
                keyCode: key,
                currentIndex: current,
                itemCount: count,
                columnCount: columns
            )
        }

        precondition(destination(124, nil) == 1)
        precondition(destination(123, 0) == nil)
        precondition(destination(124, 0) == 1)
        precondition(destination(126, 5) == 2)
        precondition(destination(125, 5) == 8)
        precondition(destination(125, 8) == 9)
        precondition(destination(125, 9) == nil)
        precondition(destination(12, 5) == nil)
        precondition(destination(124, 0, count: 0) == nil)
        precondition(SteamWorkshopGridKeyboardNavigation.isPrimaryActionKey(36))
        precondition(SteamWorkshopGridKeyboardNavigation.isPrimaryActionKey(76))
        precondition(!SteamWorkshopGridKeyboardNavigation.isPrimaryActionKey(49))
        print("Steam grid keyboard navigation: arrows, bounds and primary keys PASS")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-steam-keyboard-") as directory:
            root = pathlib.Path(directory)
            source = root / "Harness.swift"
            source.write_text(harness)
            binary = root / "keyboard"
            subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", str(KEYBOARD), str(source), "-o", str(binary)],
                check=True,
                timeout=120,
            )
            subprocess.run([str(binary)], check=True, timeout=15)

    def test_browser_and_downloads_share_the_navigation_owner(self):
        browser = (UI / "AppKitSteamWorkshopBrowserGridView.swift").read_text()
        downloads = (UI / "AppKitSteamWorkshopDownloadsGridView.swift").read_text()
        item = (UI / "AppKitSteamWorkshopBrowserItem.swift").read_text()

        self.assertIn("private var keyboardFocusedID: String?", browser)
        self.assertIn("isKeyboardFocused: keyboardFocusedID == id", browser)
        self.assertIn("SteamWorkshopGridKeyboardNavigation.destinationIndex", browser)
        self.assertIn("return handlePrimaryActionKey()", browser)
        self.assertIn("onOpen(item)", browser)
        self.assertIn("return handleEscapeKey()", browser)
        self.assertIn("SteamWorkshopGridKeyboardNavigation.destinationIndex", downloads)
        self.assertIn("SteamWorkshopGridKeyboardNavigation.isPrimaryActionKey", downloads)
        self.assertEqual(browser.count("guard !event.isARepeat else { return true }"), 1)
        self.assertEqual(downloads.count("guard !event.isARepeat else { return true }"), 1)

        focus_setter = item.split("func setKeyboardFocus(_ focused: Bool)", 1)[1].split("\n    }", 1)[0]
        self.assertIn("currentIsKeyboardFocused = focused", focus_setter)

        focus_item = browser.split("private func focusItem(at index: Int)", 1)[1].split(
            "private func handleArrowKey", 1
        )[0]
        self.assertNotIn("service.", focus_item)


if __name__ == "__main__":
    unittest.main()
