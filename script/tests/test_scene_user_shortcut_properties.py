"""App-owned shortcut selection, persistence and receipt ordering; no target opens.

The store/parser/configuration and editor are production code. Daemon outcomes,
system choosers and native opening are controlled leaves, not substitute stores.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from unittest import mock

from .test_scene_property_live_routing import method_body
from . import test_scene_native_property_list as native

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "MyWallpaperX/Modules/SteamWorkshop"
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
TYPES = ROOT / "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift"
STORE = MODULE / "Scene/SteamWorkshopSceneService+SceneShortcutProperties.swift"
SERVICE = MODULE / "Scene/SteamWorkshopSceneService+SceneProperties.swift"

STORE_CARRIERS = r'''
import Foundation
import Combine
struct SteamWorkshopDownloadRecord { let id: String }
enum EngineKind { case scene }
enum WallpaperEngineCommand {
    case setProperty([String: SceneUserPropertyValue], revision: UInt64, recordID: String)
}
enum ScenePlaybackTextureUpdateOutcome: Equatable {
    case applied, failed(String), superseded, unavailable
}
@MainActor final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    var active = false
    func hasIntent(for record: String) -> Bool { active }
}
@MainActor final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()
    var available = true
    var requests: [ScenePlaybackShortcutUpdate] = []
    var replies: [@MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void] = []
    func applyUserShortcutUpdate(_ update: ScenePlaybackShortcutUpdate,
        completion: @escaping @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void) -> Bool {
        guard available else { return false }
        requests.append(update); replies.append(completion); return true
    }
    func dispatch(_ command: WallpaperEngineCommand, to: EngineKind) -> Bool { true }
}
@MainActor final class SteamWorkshopService {
    let objectWillChange = ObservableObjectPublisher()
    let defaults: UserDefaults
    var scenePropertyCommandRevision: UInt64 = 0
    var scenePropertyEditRevisions: [String: UInt64] = [:]
    var pendingSceneShortcutProperties: [String: SceneShortcutPropertyPending] = [:]
    var scalarValues: [String: SceneUserPropertyValue] = [:]
    var textureResets: [@MainActor (Set<String>, ScenePlaybackTextureUpdateOutcome) -> Void] = []
    var reloads = 0
    init(_ defaults: UserDefaults) { self.defaults = defaults }
    func scenePropertyOverrides(for record: SteamWorkshopDownloadRecord) -> [String: SceneUserPropertyValue] { scalarValues }
    func saveScenePropertyOverrides(_ values: [String: SceneUserPropertyValue], for record: SteamWorkshopDownloadRecord) { scalarValues = values }
    func resetSceneTextureProperties(for record: SteamWorkshopDownloadRecord,
        defaultValues: [String: SceneUserPropertyValue],
        completion: @escaping @MainActor (Set<String>, ScenePlaybackTextureUpdateOutcome) -> Void) { textureResets.append(completion) }
    func scheduleActiveScenePropertyRender(for record: SteamWorkshopDownloadRecord) { reloads += 1 }
}
'''

STORE_HARNESS = r'''
@main enum StoreProbe {
    @MainActor static func main() throws {
        let suite = "com.songziqiang.MyWallpaperX.Debug.Shortcut." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = SteamWorkshopService(defaults), record = SteamWorkshopDownloadRecord(id: "own-renamed")
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "launchA": ["type": "usershortcut", "value": "", "text": "A"],
            "renamedB": ["type": "usershortcut", "value": "", "text": "B"],
            "scalar": ["type": "slider", "value": 1],
            "neighbor": ["type": "unknown-private", "value": ""]])
        let a = catalog.definitions.first { $0.key == "launchA" }!
        let b = catalog.definitions.first { $0.key == "renamedB" }!
        var facts: [String: Bool] = [:]
        facts["explicitType"] = a.kind == .userShortcut && b.kind == .userShortcut
            && catalog.unsupportedDefinitions.map(\.key) == ["neighbor"]
        let https = URL(string: "https://example.invalid/own/path")!
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var outcomes: [ScenePlaybackShortcutUpdateOutcome] = []
        service.updateSceneShortcutPropertyURL(https, definition: a, record: record) { outcomes.append($0) }
        let selected = service.storedSceneShortcutConfiguration(for: record)
        facts["localWebPersisted"] = outcomes == [.applied] && selected.references[a.key]?.url == https
            && selected.revision > 0 && service.scalarValues.isEmpty
        service.updateSceneShortcutPropertyURL(folder, definition: b, record: record) { outcomes.append($0) }
        let files = service.sceneShortcutConfiguration(for: record)
        facts["realFolderBookmark"] = files.references[b.key]?.kind == .file
            && files.references[b.key]?.bookmarkData?.isEmpty == false && files.references[a.key]?.url == https
        let reopened = SteamWorkshopService(defaults)
        facts["reopen"] = reopened.storedSceneShortcutConfiguration(for: record)
            == service.storedSceneShortcutConfiguration(for: record)
        let accepted = service.storedSceneShortcutConfiguration(for: record)
        for raw in ["file:///not-selected", "javascript:alert(1)", "ftp://example.invalid", "https://user:pass@example.invalid"] {
            if let url = URL(string: raw) {
                service.updateSceneShortcutPropertyURL(url, definition: a, record: record) { outcomes.append($0) }
            }
        }
        facts["badSelectionsPreserve"] = service.storedSceneShortcutConfiguration(for: record) == accepted
        SceneDaemonClient.shared.active = true
        let mux = PlaybackCommandMultiplexer.shared
        service.updateSceneShortcutPropertyURL(nil, definition: a, record: record) { outcomes.append($0) }
        let oldReply = mux.replies.removeFirst()
        service.updateSceneShortcutPropertyURL(https, definition: b, record: record) { outcomes.append($0) }
        facts["crossKeyPendingMerge"] = mux.requests.last!.configuration.references[a.key] == nil
            && mux.requests.last!.configuration.references[b.key]?.kind == .webURL && outcomes.last == .superseded
        let newReply = mux.replies.removeFirst()
        newReply(.applied); let latest = service.storedSceneShortcutConfiguration(for: record)
        oldReply(.applied)
        facts["lateAckCannotRestore"] = service.storedSceneShortcutConfiguration(for: record) == latest
            && latest.references[a.key] == nil
        service.updateSceneShortcutPropertyURL(https, definition: a, record: record) { outcomes.append($0) }
        mux.replies.removeFirst()(.failed("own native admission failure"))
        facts["runtimeFailurePreserves"] = service.storedSceneShortcutConfiguration(for: record) == latest
        mux.available = false
        service.updateSceneShortcutPropertyURL(https, definition: a, record: record) { outcomes.append($0) }
        facts["unavailableNoReload"] = outcomes.last == .unavailable
            && service.storedSceneShortcutConfiguration(for: record) == latest && service.reloads == 0
        mux.available = true
        service.updateSceneShortcutPropertyURL(https, definition: a, record: record) { outcomes.append($0) }
        let beforeReset = mux.replies.removeFirst()
        service.resetSceneShortcutProperties(for: record) { outcomes.append($0) }
        let resetRevision = mux.requests.last!.configuration.revision
        mux.replies.removeFirst()(.applied); beforeReset(.applied)
        facts["resetRevokesLateSelection"] = service.storedSceneShortcutConfiguration(for: record).references.isEmpty
            && service.storedSceneShortcutConfiguration(for: record).revision == resetRevision
        let invalid = ScenePlaybackShortcutConfiguration(revision: resetRevision + 7,
            references: [a.key: .init(kind: .file, url: folder, bookmarkData: Data([1, 2, 3]))])
        defaults.set(try JSONEncoder().encode(invalid), forKey: "SteamWorkshop.sceneUserShortcuts." + record.id)
        let projected = service.sceneShortcutConfiguration(for: record)
        facts["invalidBookmarkIntentHeld"] = service.sceneShortcutReference(forKey: a.key, record: record) != nil
            && projected.references.isEmpty && projected.revision == invalid.revision
        var resetOutcomes: [ScenePlaybackTextureUpdateOutcome] = []
        service.scalarValues = ["scalar": .number(2)]
        service.resetScenePropertyValues(for: record, defaultValues: ["scalar": .number(1)]) { resetOutcomes.append($0) }
        mux.replies.removeFirst()(.applied)
        facts["allResetWaitsForBoth"] = resetOutcomes.isEmpty
        service.textureResets.removeFirst()([], .applied)
        facts["allResetIncludesShortcut"] = resetOutcomes == [.applied]
            && service.storedSceneShortcutConfiguration(for: record).references.isEmpty && service.scalarValues.isEmpty
        // Superseding completion re-enters before the displaced send: only
        // the final request may be sent and its configuration retains both keys.
        var reentered = false
        service.updateSceneShortcutPropertyURL(https, definition: a, record: record) { outcome in
            if outcome == .superseded, !reentered {
                reentered = true
                service.resetSceneShortcutProperties(for: record) { _ in }
            }
        }
        let requestCount = mux.requests.count
        service.updateSceneShortcutPropertyURL(https, definition: b, record: record) { _ in }
        facts["reentrantNewestOnly"] = reentered && mux.requests.count == requestCount + 1
            && mux.requests.last!.configuration.references.isEmpty
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts), as: UTF8.self))
    }
}
'''

UI_HARNESS = r'''
@MainActor final class ShortcutAlertProbe: NSAlert {
    static var opened: [ShortcutAlertProbe] = []
    private var reply: ((NSApplication.ModalResponse) -> Void)?
    override func beginSheetModal(for window: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        reply = handler; Self.opened.append(self)
    }
    func finish(_ response: NSApplication.ModalResponse) { reply?(response) }
}
@main enum ShortcutUIProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let service = SteamWorkshopService.shared, record = SteamWorkshopDownloadRecord(id: "own", title: "own")
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "gate": ["type": "bool", "value": true, "order": 0],
            "renamedShortcut": ["type": "usershortcut", "value": "", "condition": "gate.value", "order": 1]])
        let context = SteamWorkshopScenePropertyContext(catalog: catalog,
            actionableKeys: ["gate"], effectiveValues: catalog.defaultValues)
        precondition(context.hasEditorControls && context.definitions.count == 2,
            "a declared shortcut must be configurable without a texture/value consumer")
        let onlyShortcut = SceneUserPropertyDefinitionParser().parse(properties: [
            "ownOnlyShortcut": ["type": "usershortcut", "value": ""]])
        let onlyContext = SteamWorkshopScenePropertyContext(catalog: onlyShortcut,
            actionableKeys: [], effectiveValues: onlyShortcut.defaultValues)
        precondition(service.projectedScenePropertyContext(onlyContext, for: record) != nil,
            "the ordinary service must preserve a shortcut-only editor without scalar demands")
        let editor = SteamWorkshopScenePropertyEditorView(record: record, context: context)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = editor; window.makeKeyAndOrderFront(nil)
        editor.layoutSubtreeIfNeeded()
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
        }
        let list = descendants(editor, NSCollectionView.self).first!
        func cell(_ row: Int) -> NSView {
            list.scrollToItems(at: [IndexPath(item: row, section: 0)], scrollPosition: .nearestHorizontalEdge)
            editor.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            return list.item(at: IndexPath(item: row, section: 0))!.view
        }
        func choose() {
            descendants(cell(1), NSButton.self).first { $0.action == NSSelectorFromString("chooseShortcut:") }!.performClick(nil)
        }
        choose(); let resetPicker = PickerProbe.opened.last!
        precondition(resetPicker.canChooseFiles && resetPicker.canChooseDirectories && !resetPicker.allowsMultipleSelection)
        descendants(editor, NSButton.self).first { $0.title == "恢复默认" }!.performClick(nil)
        resetPicker.finish(.OK)
        precondition(resetPicker.cancellations == 1 && service.shortcutEvents.isEmpty)
        service.finishReset(.applied)
        choose(); PickerProbe.opened.last!.finish(.cancel)
        precondition(service.shortcutEvents.isEmpty)
        choose(); let hidden = PickerProbe.opened.last!; editor.isHidden = true
        hidden.finish(.OK); precondition(hidden.cancellations == 1 && service.shortcutEvents.isEmpty)
        editor.isHidden = false
        choose(); let conditional = PickerProbe.opened.last!
        let gate = descendants(cell(0), NSButton.self).first!
        gate.state = .off; gate.sendAction(gate.action, to: gate.target)
        conditional.finish(.OK)
        precondition(conditional.cancellations == 1 && service.shortcutEvents.isEmpty)
        gate.state = .on; gate.sendAction(gate.action, to: gate.target)
        choose(); let rebound = PickerProbe.opened.last!
        let other = NSWindow(contentRect: window.frame, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        window.contentView = nil; other.contentView = editor; other.makeKeyAndOrderFront(nil)
        other.contentView = nil; window.contentView = editor; window.makeKeyAndOrderFront(nil)
        editor.layoutSubtreeIfNeeded(); rebound.finish(.OK); other.close()
        precondition(rebound.cancellations == 1 && service.shortcutEvents.isEmpty,
            "returning to the original window must not revive its old picker")
        choose(); let accepted = PickerProbe.opened.last!; accepted.finish(.OK); accepted.finish(.OK)
        precondition(service.shortcutEvents.count == 1 && service.shortcutEvents[0].0 == "renamedShortcut")
        precondition(service.events.count == 2, "selection must not create a scalar property event")
        service.shortcutConfiguration = .init(revision: 1, references: ["renamedShortcut": .init(
            kind: .webURL, url: URL(string: "https://example.invalid/previous")!, bookmarkData: nil)])
        service.shortcutReplies.removeFirst()(.applied)
        let clear = descendants(cell(1), NSButton.self).first { $0.action == NSSelectorFromString("clearShortcut:") }!
        precondition(!clear.isHidden); clear.performClick(nil)
        precondition(service.shortcutEvents.count == 2 && service.shortcutEvents.last!.1 == nil)
        service.shortcutConfiguration = .init(revision: 2, references: [:])
        service.shortcutReplies.removeFirst()(.applied)
        descendants(cell(1), NSButton.self).first { $0.action == NSSelectorFromString("chooseShortcutWeb:") }!.performClick(nil)
        let web = ShortcutAlertProbe.opened.last!
        (web.accessoryView as! NSTextField).stringValue = "https://example.invalid/own"
        web.finish(.alertFirstButtonReturn)
        precondition(service.shortcutEvents.count == 3 && service.shortcutEvents.last!.1?.scheme == "https")
        service.shortcutReplies.removeFirst()(.failed("own failure"))
        descendants(cell(1), NSButton.self).first { $0.action == NSSelectorFromString("chooseShortcutWeb:") }!.performClick(nil)
        let invalid = ShortcutAlertProbe.opened.last!
        (invalid.accessoryView as! NSTextField).stringValue = "https://user:pass@example.invalid"
        invalid.finish(.alertFirstButtonReturn)
        precondition(service.shortcutEvents.count == 3)
        descendants(cell(1), NSButton.self).first { $0.action == NSSelectorFromString("chooseShortcutWeb:") }!.performClick(nil)
        let staleWeb = ShortcutAlertProbe.opened.last!
        (staleWeb.accessoryView as! NSTextField).stringValue = "javascript:stale"
        editor.isHidden = true; staleWeb.finish(.alertFirstButtonReturn); editor.isHidden = false
        precondition(service.shortcutEvents.count == 3 && descendants(editor, NSTextField.self).first {
            $0.accessibilityIdentifier() == "scene-texture-update-status" }!.isHidden,
            "late URL validation must not revive feedback on a hidden editor")
        choose(); let closed = PickerProbe.opened.last!; window.contentView = nil; window.close(); closed.finish(.OK)
        precondition(closed.cancellations == 1 && service.shortcutEvents.count == 3 && NSApp.modalWindow == nil)
        print("shortcut native row, chooser cancel/reset/hidden/rebind and HTTP(S) validation PASS")
    }
}
'''


class SceneUserShortcutPropertyTests(unittest.TestCase):
    def test_real_store_parser_and_callback_ordering(self):
        output = ROOT / ".artifacts/tmp/usershortcut-app-20261020/tests"
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="store-", dir=output) as folder:
            work = Path(folder)
            target = work / "selected-folder"
            target.mkdir()
            probe = work / "Probe.swift"
            reset = method_body(SERVICE.read_text(), "    func resetScenePropertyValues(")
            probe.write_text(STORE_CARRIERS + "\nextension SteamWorkshopService {\n" + reset + "\n}\n" + STORE_HARNESS)
            binary = work / "probe"
            result = subprocess.run(["swiftc", "-parse-as-library", str(TYPES),
                str(SCENE / "Systems/Properties/SceneUserProperty.swift"),
                str(SCENE / "Systems/Properties/SceneUserPropertyDefinitionParser.swift"), str(STORE), str(probe),
                "-module-cache-path", str(work / "cache"), "-o", str(binary)], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(binary), str(target)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            self.assertGreaterEqual(len(facts), 13)
            for name, passed in facts.items():
                with self.subTest(behavior=name):
                    self.assertTrue(passed)

    def test_native_shortcut_editor_lifecycle(self):
        # Reuse the existing native list's real context/conditions/control
        # closure, substituting only its service/dialog leaves for this slice.
        editor = native.EDITOR.read_text().replace("NSOpenPanel()", "PickerProbe()").replace("NSAlert()", "ShortcutAlertProbe()")
        original_read = Path.read_text

        def read(path, *args, **kwargs):
            return editor if path == native.EDITOR else original_read(path, *args, **kwargs)

        with mock.patch.object(Path, "read_text", read):
            native.NativeScenePropertyListTests().run_probe(UI_HARNESS)


if __name__ == "__main__":
    unittest.main()
