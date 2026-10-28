"""Exercise the shared Steam grid keyboard owner and its AppKit wiring."""
import pathlib
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration


ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI"
KEYBOARD = UI / "SteamWorkshopGridKeyboardNavigation.swift"


class SteamKeyboardNavigationTests(unittest.TestCase):
    def test_actual_mouse_policy_keeps_focus_double_click_and_explicit_details(self):
        browser = (UI / "AppKitSteamWorkshopBrowserGridView.swift").read_text()
        fragments = {
            "// ACTUAL_CLICK_WIRING": declaration(browser, "        collectionView.primaryClickHandler = "),
            "// ACTUAL_OPEN_ITEM": declaration(browser, "    private func openItem(").replace("private func", "func", 1),
            "// ACTUAL_SELECTED_ITEM": declaration(browser, "    var selectedItem:"),
            "// ACTUAL_PRIMARY_CAPABILITY": declaration(browser, "    var selectedPrimaryAction:"),
            "// ACTUAL_PRIMARY_ACTION": declaration(browser, "    private func primaryAction("),
            "// ACTUAL_PERFORM_PRIMARY": declaration(browser, "    private func performPrimaryAction("),
            "// ACTUAL_SELECTED_PRIMARY": declaration(browser, "    func performSelectedPrimaryAction("),
            "// ACTUAL_SELECTED_DETAILS": declaration(browser, "    func inspectSelectedItem("),
            "// ACTUAL_CARD_DOWNLOAD_ACTION": declaration(browser, "{ [weak self] in\n                guard let self, let current = self.itemsByID[id] else { return }\n                self.onDownload(current)"),
            "// ACTUAL_EXPLICIT_DETAIL_ACTION": declaration(browser, "{ [weak self] in _ = self?.openItem(withID: id) }"),
            "// ACTUAL_CLICK_PREFERENCE": next(line for line in browser.splitlines() if "var opensDetailsOnSingleClick:" in line),
        }
        harness = r'''
import AppKit

struct SteamWorkshopBrowserItem { let id: String }
struct SteamWorkshopDownloadRecord { let id: String }
enum TestProgressPhase { case transferring, saving, failed }
struct TestProgress { let phase: TestProgressPhase }
@MainActor final class TestProgressStore {
    var values: [String: TestProgress] = [:]
    func snapshot(for id: String) -> TestProgress? { values[id] }
}
@MainActor final class TestService {
    var downloading = Set<String>(), queued = Set<String>(), pending = Set<String>()
    var records: [String: SteamWorkshopDownloadRecord] = [:]
    let downloadProgressStore = TestProgressStore()
    func isDownloading(itemID: String) -> Bool { downloading.contains(itemID) }
    func isQueuedForDownload(itemID: String) -> Bool { queued.contains(itemID) }
    func isLaunchPending(_ id: String) -> Bool { pending.contains(id) }
    func downloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { records[id] }
}
enum AppKitSteamWorkshopBrowserItem {
    struct OrganizationPresentation {
        var isPlaying = false, isSwitching = false, canPlay = true, canDownload = true
        var onPrimary: (() -> Void)?
    }
}
@MainActor enum WallpaperLibrarySheetPresentation {
    static var permits = true
    static func permitsInput(in window: NSWindow?) -> Bool { permits && window != nil }
}
@MainActor final class ClickItem: NSCollectionViewItem {
    override func loadView() { view = NSView() }
}
@MainActor final class ClickGridProbe {
    let collectionView: SteamWorkshopKeyboardCollectionView
    let dataSource: NSCollectionViewDiffableDataSource<Int, String>
    var window: NSWindow? { collectionView.window }
    var itemsByID = ["first": SteamWorkshopBrowserItem(id: "first"), "second": SteamWorkshopBrowserItem(id: "second")]
    var keyboardFocusedID: String?
    let service = TestService()
    var makeOrganization: ((SteamWorkshopBrowserItem) -> AppKitSteamWorkshopBrowserItem.OrganizationPresentation?)?
    var thumbnailDemandIsVisible = true
    var focusEvents: [String] = []
    var opened: [String] = []
    var downloaded: [String] = [], applied: [String] = [], stopped: [String] = []
    var onOpen: (SteamWorkshopBrowserItem) -> Void = { _ in }
    var onDownload: (SteamWorkshopBrowserItem) -> Void = { _ in }
    var onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void = { _ in }
    // ACTUAL_SELECTED_ITEM
    // ACTUAL_PRIMARY_CAPABILITY
    // ACTUAL_CLICK_PREFERENCE
    init(_ collection: SteamWorkshopKeyboardCollectionView, _ source: NSCollectionViewDiffableDataSource<Int, String>) {
        collectionView = collection; dataSource = source
        onOpen = { [weak self] item in self?.opened.append(item.id) }
        onDownload = { [weak self] item in self?.downloaded.append(item.id) }
        onSetAsWallpaper = { [weak self] record in self?.applied.append(record.id) }
    }
    func bind() {
        // ACTUAL_CLICK_WIRING
    }
    func updateKeyboardFocusItem(withID id: String?, focused: Bool) {
        focusEvents.append((id ?? "<none>") + ":" + String(focused))
    }
    // ACTUAL_OPEN_ITEM
    // ACTUAL_PRIMARY_ACTION
    // ACTUAL_PERFORM_PRIMARY
    // ACTUAL_SELECTED_PRIMARY
    // ACTUAL_SELECTED_DETAILS
    func explicitDetailAction(_ id: String) -> () -> Void {
        return // ACTUAL_EXPLICIT_DETAIL_ACTION
    }
    func cardDownloadAction(_ id: String) -> () -> Void {
        return // ACTUAL_CARD_DOWNLOAD_ACTION
    }
}
@main struct Harness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.close() }
        let collection = SteamWorkshopKeyboardCollectionView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        collection.isSelectable = false
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 150)
        collection.collectionViewLayout = layout
        collection.register(ClickItem.self, forItemWithIdentifier: .init("item"))
        window.contentView = collection
        let source = NSCollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, path, _ in
            collection.makeItem(withIdentifier: .init("item"), for: path)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0]); snapshot.appendItems(["first", "second"])
        source.apply(snapshot, animatingDifferences: false)
        collection.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let grid = ClickGridProbe(collection, source)
        grid.bind()
        func mouse(_ index: Int, count: Int) {
            let path = IndexPath(item: index, section: 0)
            let rect = layout.layoutAttributesForItem(at: path)!.frame
            let point = collection.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1)!
            }
            collection.mouseDown(with: event(.leftMouseDown))
            collection.mouseUp(with: event(.leftMouseUp))
        }
        mouse(0, count: 1)
        precondition(grid.opened.isEmpty && grid.keyboardFocusedID == "first" && window.firstResponder === collection,
            "default single click must update focus without opening details")
        mouse(1, count: 1)
        precondition(grid.opened.isEmpty && grid.keyboardFocusedID == "second"
            && Array(grid.focusEvents.suffix(2)) == ["first:false", "second:true"],
            "selection-only clicks must retain the original current/previous focus updates")
        grid.opensDetailsOnSingleClick = { true }
        mouse(0, count: 1)
        precondition(grid.opened == ["first"] && grid.keyboardFocusedID == "first",
            "the live preference must allow exactly one single-click detail delivery")
        grid.opensDetailsOnSingleClick = { false }
        mouse(1, count: 2)
        precondition(grid.opened == ["first", "second"] && grid.keyboardFocusedID == "second",
            "double click must retain its explicit original open semantics")
        precondition(grid.selectedItem?.id == "second" && grid.selectedPrimaryAction != nil
            && grid.performSelectedPrimaryAction() && grid.downloaded == ["second"] && grid.opened == ["first", "second"],
            "Return downloads the fixed selected remote item without opening details")
        grid.service.records["second"] = .init(id: "second")
        precondition(grid.performSelectedPrimaryAction() && grid.applied == ["second"],
            "the same selected primary applies its published local record")
        grid.makeOrganization = { [weak grid] item in
            .init(isPlaying: true, onPrimary: { grid?.stopped.append(item.id) })
        }
        precondition(grid.performSelectedPrimaryAction() && grid.stopped == ["second"],
            "a playing item delegates Stop to its original fixed organization action")
        let heldStop = grid.selectedPrimaryAction!
        grid.makeOrganization = nil
        heldStop()
        precondition(grid.stopped == ["second", "second"] && grid.applied == ["second"],
            "a selected action factory retains the original Stop callback instead of reclassifying it as Apply")
        grid.service.downloading.insert("second")
        precondition(grid.selectedPrimaryAction == nil && !grid.performSelectedPrimaryAction(),
            "Return cannot reenter a running transfer")
        grid.service.downloading.removeAll()
        grid.service.downloadProgressStore.values["second"] = .init(phase: .saving)
        precondition(!grid.performSelectedPrimaryAction(), "Return cannot reenter saving")
        grid.service.downloadProgressStore.values["second"] = .init(phase: .failed)
        precondition(grid.performSelectedPrimaryAction() && grid.downloaded == ["second", "second"] && grid.applied == ["second"],
            "an update failure retries its original download while the ready old version remains published")
        grid.cardDownloadAction("second")()
        precondition(grid.downloaded == ["second", "second", "second"] && grid.applied == ["second"],
            "the original card Retry callback must never reclassify a ready old version as Apply")
        grid.service.downloadProgressStore.values.removeAll()
        grid.service.pending.insert("second")
        precondition(!grid.performSelectedPrimaryAction(), "Return cannot reenter a pending launch")
        grid.service.pending.removeAll()
        grid.thumbnailDemandIsVisible = false
        precondition(!grid.performSelectedPrimaryAction() && !grid.inspectSelectedItem(), "hidden consumer cannot run commands")
        grid.thumbnailDemandIsVisible = true
        WallpaperLibrarySheetPresentation.permits = false
        precondition(!grid.performSelectedPrimaryAction() && !grid.inspectSelectedItem(), "a sheet owns the input domain")
        WallpaperLibrarySheetPresentation.permits = true
        precondition(grid.inspectSelectedItem() && grid.opened == ["first", "second", "second"],
            "the explicit info command remains independent of primary")
        let explicit = grid.explicitDetailAction("first")
        explicit()
        precondition(grid.opened == ["first", "second", "second", "first"] && grid.keyboardFocusedID == "first",
            "the original onOpen producer used by detail controls and AX must bypass the mouse-only preference")
        grid.itemsByID.removeValue(forKey: "first")
        explicit()
        precondition(grid.opened.count == 4, "a retained explicit action cannot open a removed source item")
        withExtendedLifetime(source) {}
        print("Steam actual mouse policy: fixed primary, busy rejection, double click and explicit details PASS")
    }
}
'''
        for marker, fragment in fragments.items():
            self.assertEqual(harness.count(marker), 1)
            harness = harness.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix="mwx-steam-click-policy-", dir="/private/tmp") as directory:
            root = pathlib.Path(directory)
            source = root / "Harness.swift"
            source.write_text(harness)
            collection = root / "SteamWorkshopKeyboardCollectionView.swift"
            collection.write_bytes((UI / collection.name).read_bytes())
            binary = root / "checks"
            build = subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", "-warnings-as-errors", str(collection),
                 str(ROOT / "MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift"), str(source), "-o", str(binary)],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=25)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("Steam actual mouse policy:", run.stdout)

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

    def test_live_browser_wires_its_navigation_owner(self):
        browser = (UI / "AppKitSteamWorkshopBrowserGridView.swift").read_text()
        item = (UI / "AppKitSteamWorkshopBrowserItem.swift").read_text()
        self.assertIn("private var keyboardFocusedID: String?", browser)
        self.assertIn("isKeyboardFocused: keyboardFocusedID == id", browser)
        self.assertIn("SteamWorkshopGridKeyboardNavigation.destinationIndex", browser)
        self.assertIn("return performSelectedPrimaryAction()", browser)
        self.assertIn("onOpen(item)", browser)
        self.assertIn("return handleEscapeKey()", browser)
        self.assertEqual(browser.count("guard !event.isARepeat else { return true }"), 1)
        focus_setter = item.split("func setKeyboardFocus(_ focused: Bool)", 1)[1].split("\n    }", 1)[0]
        self.assertIn("currentIsKeyboardFocused = focused", focus_setter)
        focus_item = browser.split("private func focusItem(at index: Int)", 1)[1].split("private func handleArrowKey", 1)[0]
        self.assertNotIn("service.", focus_item)


if __name__ == "__main__":
    unittest.main()
