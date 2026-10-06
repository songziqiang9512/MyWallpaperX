"""Run the production hit-test route and popover/row constraints in AppKit."""
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI'


class SteamAppKitInteractionTests(unittest.TestCase):
    def test_hit_routing_and_popover_geometry(self):
        source = (UI / 'SteamWorkshopDownloadTasksPopover.swift').read_text()
        layout = source[source.index('    override func loadView()'):source.index('    func startObserving()')]
        row_source = source[source.index('final class SteamWorkshopDownloadRowView:'):]
        row_init = row_source[row_source.index('    init(service:'):row_source.index('    @available')]
        harness = r'''
import AppKit
@MainActor enum UIInteractionAnimation { static let minimumPressVisualDuration: TimeInterval = 0 }
@MainActor final class SteamWorkshopService {}
@MainActor enum SteamWorkshopDownloadTasksPopoverController {
    static let panelSize = NSSize(width: 400, height: 460)
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }
final class SteamWorkshopGlassBarView: NSView {
    func setProgressAnimationVisible(_ visible: Bool) {}
}
@MainActor final class LayoutController: NSViewController {
    let countLabel = NSTextField(labelWithString: "3 项")
    let clearAllButton = NSButton(title: "全部清除", target: nil, action: nil)
    // 2305fea3 的批量重试给弹窗布局加了该按钮（真实声明在 TasksPopover:57），
    // 本桩类需同名成员才能编译抽取的 loadView。
    let retryAllFailedButton = NSButton(title: "重试全部失败", target: nil, action: nil)
    let emptyLabel = NSTextField(labelWithString: "")
    let scrollView = NSScrollView()
    let documentView = FlippedView()
    let rowsStack = NSStackView()
    @objc func handleClearAll() {}
    @objc func handleRetryAllFailed() {}
''' + layout + r'''
}
@MainActor final class Row: NSView {
    let service: SteamWorkshopService
    let onCleared: () -> Void
    let thumbnailView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let progressBar = NSLevelIndicator()
    let retryButton = NSButton(title: "重试", target: nil, action: nil)
    let actionsStack = NSStackView()
    @objc func handleRetry() {}
    // 2305fea3 的暂停/继续与插队（优先下载）键：抽取的行初始化与状态刷新
    // 引用这些成员与动作，桩保持无操作。
    let pauseButton = NSButton(title: "暂停", target: nil, action: nil)
    @objc func handlePauseToggle() {}
    var pauseHandler: (() -> Void)?
    let promoteButton = NSButton(title: "优先", target: nil, action: nil)
    @objc func handlePromote() {}
    var promoteHandler: (() -> Void)?
    let clearButton = NSButton(title: "", target: nil, action: nil)
    @objc func handleClear() {}
    required init?(coder: NSCoder) { nil }
''' + row_init + r'''
}
final class TestItem: NSCollectionViewItem {
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 150)) }
}
@main struct Harness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let controller = LayoutController()
        window.contentView = controller.view
        window.setContentSize(NSSize(width: 400, height: 460))
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.fittingSize == NSSize(width: 400, height: 460))
        precondition(controller.clearAllButton.frame.maxX <= 384)
        precondition(controller.scrollView.frame.height > 350)
        for index in 0..<3 {
            let row = Row(service: SteamWorkshopService(), onCleared: {})
            controller.rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: controller.rowsStack.widthAnchor).isActive = true
            row.titleLabel.stringValue = ["雨夜城市 · 霓虹倒影", "星际漫游 · 已完成", "山谷晨雾 · 下载失败"][index]
            row.statusLabel.stringValue = ["下载中 48% · 24 MB / 50 MB", "已完成 · 今天 10:32", "网络连接中断，请重试"][index]
            row.statusLabel.textColor = index == 2 ? .systemRed : .secondaryLabelColor
            row.progressBar.doubleValue = [0.48, 1.0, 0.0][index]
            row.retryButton.isHidden = index != 2
        }
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.fittingSize == NSSize(width: 400, height: 460), "long titles must not enlarge queue")
        for view in controller.rowsStack.arrangedSubviews {
            let row = view as! Row
            precondition(row.bounds.height == 76)
            precondition(row.progressBar.bounds.width > 200)
            precondition(!row.titleLabel.stringValue.isEmpty)
        }
        controller.emptyLabel.isHidden = true
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.white.cgColor
        window.backgroundColor = .windowBackgroundColor
        if let path = ProcessInfo.processInfo.environment["MWX_STEAM_UI_SNAPSHOT"],
           let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            let flattened = NSImage(size: controller.view.bounds.size)
            flattened.lockFocus()
            NSColor.white.setFill()
            controller.view.bounds.fill()
            bitmap.draw(in: controller.view.bounds)
            flattened.unlockFocus()
            let output = NSBitmapImageRep(data: flattened.tiffRepresentation!)!
            try! output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
        (controller.rowsStack.arrangedSubviews[0] as! Row).titleLabel.stringValue = String(repeating: "Long wallpaper title ", count: 40)
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.fittingSize == NSSize(width: 400, height: 460))
        window.orderOut(nil)
        let collection = SteamWorkshopKeyboardCollectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        collection.isSelectable = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = host
        host.addSubview(collection)
        let card = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 150))
        let image = NSImageView(frame: NSRect(x: 0, y: 0, width: 150, height: 150))
        let button = NSButton(frame: NSRect(x: 10, y: 10, width: 30, height: 30))
        card.addSubview(image); card.addSubview(button); collection.addSubview(card)
        precondition(collection.hitTest(NSPoint(x: 80, y: 80)) === collection, "preview must reach card click owner")
        precondition(collection.hitTest(button.convert(NSPoint(x: 15, y: 15), to: host)) === button, "embedded action keeps native hit target: \(String(describing: collection.hitTest(button.convert(NSPoint(x: 15, y: 15), to: host)))) collection \(collection.frame) button \(button.frame)")
        let cards = SteamWorkshopKeyboardCollectionView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        cards.isSelectable = false
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 150)
        cards.collectionViewLayout = layout
        window.contentView = cards
        let dataSource = NSCollectionViewDiffableDataSource<Int, String>(collectionView: cards) { _, _, _ in TestItem() }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0]); snapshot.appendItems(["first", "second", "third"])
        dataSource.apply(snapshot, animatingDifferences: false)
        cards.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        var opened: [IndexPath] = []
        var backgroundClicks = 0
        cards.primaryClickHandler = { opened.append($0); return true }
        cards.onBackgroundLeftClick = { backgroundClicks += 1 }
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: cards.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func center(_ index: Int) -> NSPoint {
            let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame
            return NSPoint(x: frame.midX, y: frame.midY)
        }
        for index in [1, 2, 0] {
            let point = center(index)
            precondition(cards.cardIndexPath(at: point) == IndexPath(item: index, section: 0))
            let before = opened.count
            cards.mouseDown(with: event(.leftMouseDown, point))
            precondition(opened.count == before, "open only on release")
            cards.mouseUp(with: event(.leftMouseUp, point))
            precondition(opened.count == before + 1 && opened.last == IndexPath(item: index, section: 0))
        }
        cards.mouseDown(with: event(.leftMouseDown, center(0)))
        cards.mouseUp(with: event(.leftMouseUp, center(1)))
        precondition(opened.count == 3, "drag across cards must not open")
        let background = NSPoint(x: 590, y: 390)
        cards.mouseDown(with: event(.leftMouseDown, background))
        cards.mouseUp(with: event(.leftMouseUp, background))
        precondition(backgroundClicks == 1)
        var menuPath: IndexPath?
        cards.contextMenuProvider = { menuPath = $0; return nil }
        _ = cards.menu(for: event(.rightMouseDown, center(2)))
        precondition(menuPath == IndexPath(item: 2, section: 0))
        withExtendedLifetime(dataSource) {}
        print("AppKit hit routing and queue geometry PASS")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-steam-appkit-', dir='/private/tmp') as folder:
            folder = pathlib.Path(folder)
            path = folder / 'Harness.swift'
            path.write_text(harness)
            binary = folder / 'harness'
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(UI / 'SteamWorkshopKeyboardCollectionView.swift'), str(path), '-o', str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('AppKit hit routing and queue geometry PASS', result.stdout)
