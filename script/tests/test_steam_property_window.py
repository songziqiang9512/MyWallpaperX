"""Exercise the production property window's geometry and ownership contract."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class SteamPropertyWindowTests(unittest.TestCase):
    def test_independent_normal_window_matches_inspector(self):
        source = (ROOT / 'MyWallpaperX/App/ScenePropertyWindowController.swift').read_text()
        source = source[source.index('@MainActor\nfinal class SteamWorkshopPropertyPanelController'):]
        stubs = r'''
import AppKit
@MainActor protocol WorkshopPropertyKeyTraversal: AnyObject {
    func focusNextPropertyControl(from responder: NSResponder?, reverse: Bool) -> Bool
}
enum Module { case steamWorkshop }
struct InspectorCardToken { let module: Module; let cardID: String }
struct InspectorHostRequest {
    static let defaultPreferredWidth: CGFloat = 360
    enum Chrome { case infoPanel }
    let token: InspectorCardToken
    let title: String
    let subtitle: String
    let chromeStyle: Chrome
}
enum InspectorHostActions {
    static func postClose(module: Module, cardID: String) {}
}
final class TraversalView: NSView, WorkshopPropertyKeyTraversal {
    var directions: [Bool] = []
    var consumes = true
    override var intrinsicContentSize: NSSize { NSSize(width: -1, height: 400) }
    func focusNextPropertyControl(from responder: NSResponder?, reverse: Bool) -> Bool {
        directions.append(reverse)
        return consumes
    }
}
@main struct Harness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        main.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        main.center()
        let detail = InspectorHostCardView(frame: NSRect(x: 720, y: 18, width: 360, height: 680))
        main.contentView!.addSubview(detail)
        main.orderFront(nil)
        let owner = SteamWorkshopPropertyPanelController.shared
        owner.show(title: "属性调节", subtitle: "测试", content: NSView())
        let panel = owner.window!
        let anchor = main.convertToScreen(detail.convert(detail.bounds, to: nil))
        precondition(panel.level == .normal && panel.parent == nil)
        precondition(panel.frame.size == anchor.size)
        precondition(panel.hasShadow)
        precondition(!(panel.contentView as! InspectorHostCardView).drawsShadow)
        precondition((panel.contentView as! InspectorHostCardView).stretchesHostedContent)
        precondition(panel.contentView?.layer?.masksToBounds == true)
        precondition(panel.minSize == panel.maxSize && !panel.styleMask.contains(.resizable))
        precondition(abs(panel.frame.maxX + 12 - anchor.minX) < 1)
        precondition(panel.isMovableByWindowBackground)
        detail.removeFromSuperview()
        main.orderOut(nil)
        precondition(panel.isVisible, "property window must outlive the detail/main presentation")
        let traversal = TraversalView()
        owner.show(title: "属性调节", subtitle: "测试", content: traversal)
        panel.contentView!.layoutSubtreeIfNeeded()
        func descendants<T: NSView>(_ view: NSView, _ kind: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { descendants($0, kind) }
        }
        let subtitle = descendants(panel.contentView!, NSTextField.self).first { $0.stringValue == "测试" }!
        precondition(subtitle.frame.height < 40, "fixed subtitle must not absorb spare panel height")
        precondition(traversal.frame.height > 550, "property viewport must receive spare panel height")
        let header = descendants(panel.contentView!, NSButton.self).first { $0.toolTip == "关闭详情" }!
        precondition(panel.contentView!.convert(header.bounds, from: header).maxY > panel.frame.height - 80, "header must stay at panel top")
        print("headerTop", panel.contentView!.convert(header.bounds, from: header).maxY, "subtitle", subtitle.frame.height, "viewport", traversal.frame.height)
        panel.selectNextKeyView(nil)
        panel.selectPreviousKeyView(nil)
        precondition(traversal.directions == [false, true], "property panel must delegate only its current editor")
        owner.close()
        panel.selectNextKeyView(nil)
        precondition(traversal.directions == [false, true], "closed presentation must drop key traversal")
        precondition(owner.presentationID == nil)
        print("Property window ownership and geometry PASS")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-property-window-', dir='/private/tmp') as folder:
            path = pathlib.Path(folder) / 'Harness.swift'
            card = (ROOT / 'MyWallpaperX/Shared/UI/InspectorHostViewController.swift').read_text()
            card = card[card.index('final class InspectorHostCardView:'): ]
            path.write_text(stubs + source + card)
            binary = path.with_suffix('')
            compiled = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path), '-o', str(binary)],
                                      capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout, end="")
