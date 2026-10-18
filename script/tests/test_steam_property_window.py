"""Exercise the production property window's geometry and ownership contract."""
import pathlib
import os
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
    enum Chrome { case standard, infoPanel }
    let token: InspectorCardToken
    let title: String
    let subtitle: String?
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
        func descendants<T: NSView>(_ view: NSView, _ kind: T.Type) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, kind) }
        }
        func checkHeader(_ card: InspectorHostCardView) {
            card.layoutSubtreeIfNeeded()
            let close = descendants(card, NSButton.self).first { $0.toolTip == "关闭详情" }!
            let row = close.superview!
            // AppKit constrains alignment rects; NSButton's frame includes
            // native cell insets and need not have the same height.
            let closeRect = close.alignmentRect(forFrame: close.frame)
            let icons = row.subviews.compactMap { $0 as? NSImageView }.filter { !$0.isHidden }
            precondition(abs(closeRect.height - 18) < 0.5, "close button must keep its 18pt height")
            precondition(abs(closeRect.width - 32) < 0.5, "close button width must remain unchanged")
            precondition(row.bounds.contains(closeRect), "close button escaped the header")
            precondition(row.frame.height < 64, "header must not absorb spare panel height")
            precondition(abs(closeRect.midY - row.bounds.midY) < 0.5, "close button must stay centered")
            for image in icons where !image.isHidden {
                precondition(abs(image.alignmentRect(forFrame: image.frame).height - 18) < 0.5,
                             "header icon must retain its own height")
            }
            for label in descendants(row, NSTextField.self) where !label.isHiddenOrHasHiddenAncestor {
                precondition(label.frame.height >= label.intrinsicContentSize.height - 0.5,
                             "mixed-height header text must not be vertically clipped")
            }
        }
        func capture(_ view: NSView, _ name: String) {
            guard let directory = ProcessInfo.processInfo.environment["MWX_PROPERTY_WINDOW_PROOF_DIR"] else { return }
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                preconditionFailure("native panel snapshot unavailable")
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
        // The same production card owns detail, info and both property styles.
        let preview = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 620),
            styleMask: [.borderless], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false
        var headerCases = 0
        for dark in [false, true] {
            preview.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for width in [CGFloat(300), 360, 460] {
                for index in 0..<4 {
                    let card = InspectorHostCardView()
                    let properties = index >= 2
                    card.stretchesHostedContent = properties
                    card.compactHeader = properties
                    card.headerTitleOverride = properties ? (index == 2 ? "Scene 属性调节" : "Web 属性调节") : nil
                    let body = TraversalView()
                    let request = InspectorHostRequest(token: .init(module: .steamWorkshop, cardID: "header"),
                        title: index == 0 ? "测试作品：用于检查长标题截断与关闭按钮布局" : "详情",
                        subtitle: index == 0 ? "作者名称 · 测试副标题" : nil,
                        chromeStyle: index == 0 ? .standard : .infoPanel)
                    card.configure(request: request, hostedContentView: body)
                    let container = NSView()
                    preview.contentView = container
                    card.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(card)
                    NSLayoutConstraint.activate([
                        card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                        card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                        card.topAnchor.constraint(equalTo: container.topAnchor),
                        card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                        card.widthAnchor.constraint(equalToConstant: width),
                        card.heightAnchor.constraint(equalToConstant: 620)
                    ])
                    preview.setContentSize(NSSize(width: width, height: 620))
                    preview.orderFront(nil)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                    card.refreshAppearance()
                    precondition(abs(card.frame.width - width) < 0.5, "exercise the requested panel width")
                    checkHeader(card)
                    if properties { precondition(body.frame.height > 500, "property editor must receive spare height") }
                    var closes = 0
                    card.onClose = { closes += 1 }
                    let close = descendants(card, NSButton.self).first { $0.toolTip == "关闭详情" }!
                    close.performClick(nil)
                    precondition(closes == 1, "close action must still reach its owner")
                    if width == 360 {
                        capture(card, "header-\(index)-\(dark ? "dark" : "light")")
                    }
                    card.configure(request: nil, hostedContentView: nil)
                    card.configure(request: request, hostedContentView: body)
                    checkHeader(card)
                    headerCases += 1
                }
            }
        }
        preview.orderOut(nil)
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
        // The production status presentation keeps titles at the top and
        // centers natural-height text within the entire panel, including its header.
        var messageCases = 0
        for dark in [false, true] {
            panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for (index, text) in ["正在准备 Scene 属性…",
                "当前 Scene 没有可调节的受支持属性，或属性模型尚未解析成功。"].enumerated() {
                owner.showMessage(title: "Scene 属性调节", subtitle: "无可调节项的作品", message: text)
                let message = descendants(panel.contentView!, NSTextField.self).first { $0.stringValue == text }!
                panel.contentView!.layoutSubtreeIfNeeded()
                checkHeader(panel.contentView as! InspectorHostCardView)
                let close = descendants(panel.contentView!, NSButton.self).first { $0.toolTip == "关闭详情" }!
                let header = panel.contentView!.convert(close.bounds, from: close)
                let messageRect = panel.contentView!.convert(message.bounds, from: message)
                precondition(header.maxY > panel.frame.height - 80, "empty/loading header must stay at panel top")
                let viewport = message.superview!
                precondition(viewport.frame.height > 500, "message viewport must receive spare height")
                let panelRect = panel.contentView!.bounds
                precondition(abs(messageRect.midY - panelRect.midY) < 0.5,
                             "status text must stay vertically centered in the entire panel")
                precondition(abs(messageRect.midX - panelRect.midX) < 0.5 && message.alignment == .center,
                             "status text must stay horizontally centered")
                precondition(message.frame.height < 100, "short status text must not fill the editor viewport")
                (panel.contentView as! InspectorHostCardView).refreshAppearance()
                capture(panel.contentView!, "message-\(index)-\(dark ? "dark" : "light")")
                messageCases += 1
            }
        }
        let traversal = TraversalView()
        owner.show(title: "属性调节", subtitle: "测试", content: traversal)
        panel.contentView!.layoutSubtreeIfNeeded()
        let subtitle = descendants(panel.contentView!, NSTextField.self).first { $0.stringValue == "测试" }!
        precondition(subtitle.frame.height < 40, "fixed subtitle must not absorb spare panel height")
        precondition(traversal.frame.height > 550, "property viewport must receive spare panel height")
        let header = descendants(panel.contentView!, NSButton.self).first { $0.toolTip == "关闭详情" }!
        checkHeader(panel.contentView as! InspectorHostCardView)
        precondition(panel.contentView!.convert(header.bounds, from: header).maxY > panel.frame.height - 80, "header must stay at panel top")
        print("headerTop", panel.contentView!.convert(header.bounds, from: header).maxY, "subtitle", subtitle.frame.height, "viewport", traversal.frame.height)
        panel.selectNextKeyView(nil)
        panel.selectPreviousKeyView(nil)
        precondition(traversal.directions == [false, true], "property panel must delegate only its current editor")
        owner.close()
        panel.selectNextKeyView(nil)
        precondition(traversal.directions == [false, true], "closed presentation must drop key traversal")
        precondition(owner.presentationID == nil)
        print("Shared inspector header cases PASS", headerCases)
        print("Property window loading/unavailable cases PASS", messageCases)
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
            for message in ['Unable to simultaneously satisfy constraints', 'Conflicting constraints detected']:
                self.assertNotIn(message, result.stdout + result.stderr)
            self.assertIn('Shared inspector header cases PASS 24', result.stdout)
            self.assertIn('Property window loading/unavailable cases PASS 4', result.stdout)
            print(result.stdout, end="")
            proof = os.environ.get('MWX_PROPERTY_WINDOW_PROOF_DIR')
            if proof:
                (pathlib.Path(proof) / 'compile.log').write_text(compiled.stdout + compiled.stderr)
                (pathlib.Path(proof) / 'runtime.log').write_text(result.stdout + result.stderr)
