"""Run the production hit-test route and popover/row constraints in AppKit."""
import os
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration

ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI'


class SteamAppKitInteractionTests(unittest.TestCase):
    def test_hit_routing_and_popover_geometry(self):
        harness = r'''
import AppKit
import Combine
@MainActor enum UIInteractionAnimation { static let minimumPressVisualDuration: TimeInterval = 0 }
final class WallpaperCardGlassBarView: NSView {
    func setProgressAnimationVisible(_ visible: Bool) {}
}
// ACTUAL_SCROLL_DISMISSAL
protocol ToolbarGridScrollDismissalSurface {}
final class TestItem: NSCollectionViewItem {
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 150)) }
}
@main struct Harness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        do {
            let lifecycleChanges = PassthroughSubject<Void, Never>()
            var value = DownloadTaskSnapshot()
            let lifecycle = DownloadTasksContentController(snapshot: { value },
                changes: lifecycleChanges.eraseToAnyPublisher(), bindings: .init(perform: { _, _ in }),
                retryAllFailed: nil, clearHistory: nil)
            window.contentView = lifecycle.view
            window.setContentSize(NSSize(width: 400, height: 460))
            lifecycle.startObserving()
            lifecycle.view.layoutSubtreeIfNeeded()
            precondition(lifecycle.rowsStack.arrangedSubviews.isEmpty && !lifecycle.emptyLabel.isHidden,
                "a first empty presentation must load without installing cross-hierarchy constraints")
            func widths(_ child: NSView) -> [NSLayoutConstraint] {
                lifecycle.rowsStack.constraints.filter {
                    $0.isActive && ($0.firstItem as? NSView) === child && $0.firstAttribute == .width
                        && ($0.secondItem as? NSView) === lifecycle.rowsStack && $0.secondAttribute == .width
                        && $0.relation == .equal && $0.multiplier == 1 && $0.constant == 0
                }
            }
            func widthReceipt(_ child: NSView) -> String {
                let stack = lifecycle.rowsStack
                let candidates = stack.constraints.filter {
                    ($0.firstItem as? NSView) === child && $0.firstAttribute == .width
                        && ($0.secondItem as? NSView) === stack && $0.secondAttribute == .width
                }.map {
                    "\($0), active=\($0.isActive), relation=\($0.relation), multiplier=\($0.multiplier), constant=\($0.constant), priority=\($0.priority.rawValue)"
                }
                return "child=\(type(of: child)), mounted=\(child.superview === stack), frame=\(child.frame), bounds=\(child.bounds), "
                    + "alignment=\(child.alignmentRect(forFrame: child.frame)), stackFrame=\(stack.frame), stackBounds=\(stack.bounds), "
                    + "stackAlignment=\(stack.alignmentRect(forFrame: stack.frame)), effectiveWidths=\(widths(child).count), candidates=\(candidates)"
            }
            func layout() { lifecycle.view.layoutSubtreeIfNeeded() }
            func rows() -> [DownloadTaskRowView] {
                lifecycle.rowsStack.arrangedSubviews.compactMap { $0 as? DownloadTaskRowView }
            }
            let first = DownloadTaskRow(id: .init(reference: .init(provider: .pixabay, sourceID: "first"), attemptID: "layout"),
                title: "First", phase: .transferring)
            let second = DownloadTaskRow(id: .init(reference: .init(provider: .wallhaven, sourceID: "second"), attemptID: "layout"),
                title: "Second", phase: .transferring)
            value.active = [first, second]; value.notice = "下载历史暂不可用，请稍后重试。"
            lifecycleChanges.send(); layout()
            let mounted = rows(), notice = lifecycle.noticeLabel
            precondition(mounted.count == 2 && notice.superview === lifecycle.rowsStack)
            for child in [notice as NSView] + mounted.map({ $0 as NSView }) {
                let childAlignment = child.alignmentRect(forFrame: child.frame)
                let stackAlignment = lifecycle.rowsStack.alignmentRect(forFrame: lifecycle.rowsStack.frame)
                precondition(widths(child).count == 1 && abs(childAlignment.width - stackAlignment.width) <= 0.5,
                    "notice and rows must install one effective full-width constraint after joining the native stack: " + widthReceipt(child))
            }
            value.active = [second, first]
            lifecycleChanges.send(); layout()
            precondition(rows()[0] === mounted[1] && rows()[1] === mounted[0],
                "queue reorder must move existing native rows rather than rebuilding them")
            precondition(widths(notice).count == 1 && mounted.allSatisfy { widths($0).count == 1 },
                "reordering retained views cannot add duplicate width constraints: " + widthReceipt(notice)
                    + " rows=" + mounted.map { widthReceipt($0) }.joined(separator: " | "))
            value.active = [second]; value.notice = nil
            lifecycleChanges.send(); layout()
            precondition(notice.superview == nil && mounted[0].superview == nil && mounted[0].displayedTask == nil,
                "removed notices and rows must leave the real view hierarchy and release their consumers")
            value.active = [first, second]; value.notice = "下载历史仍不可用。"
            lifecycleChanges.send(); layout()
            precondition(rows().count == 2 && rows()[0] !== mounted[0] && rows()[1] === mounted[1]
                && notice.superview === lifecycle.rowsStack && notice.stringValue == "下载历史仍不可用。",
                "restoring a notice and a removed task must mount the current values while retaining the live row")
            precondition(widths(notice).count == 1 && rows().allSatisfy { widths($0).count == 1 },
                "a real reinstallation must restore one width constraint without reviving removed constraints: " + widthReceipt(notice)
                    + " rows=" + rows().map { widthReceipt($0) }.joined(separator: " | "))
            lifecycle.stopObserving()
            lifecycle.startObserving(); layout()
            precondition(widths(notice).count == 1 && rows().allSatisfy { widths($0).count == 1 },
                "closing and reopening the same content controller must preserve valid native constraints: " + widthReceipt(notice)
                    + " rows=" + rows().map { widthReceipt($0) }.joined(separator: " | "))
            lifecycle.stopObserving()
        }
        let changes = PassthroughSubject<Void, Never>()
        var structureSubscriptions = 0, retriedAll = 0, clearedHistory = 0
        let observedChanges = changes.handleEvents(receiveSubscription: { _ in structureSubscriptions += 1 },
            receiveCancel: { structureSubscriptions -= 1 }).eraseToAnyPublisher()
        var rows = (0..<3).map { index in
            DownloadTaskRow(id: .init(reference: .init(provider: .steamWorkshop, sourceID: String(index)), attemptID: "layout"),
                title: ["雨夜城市 · 霓虹倒影", "星际漫游 · 已完成", "山谷晨雾 · 下载失败"][index],
                phase: [DownloadTaskPhase.transferring, .completed, .failed][index],
                statusText: ["下载中 48% · 24 MB / 50 MB", "已完成 · 今天 10:32", "网络连接中断，请重试"][index],
                progress: .init(phase: [.transferring, .completed, .failed][index], fraction: [0.48, 1.0, 0.0][index]),
                actions: index == 2 ? [.retry] : [])
        }
        let controller = DownloadTasksContentController(snapshot: { DownloadTaskProjection.snapshot(current: rows, history: []) },
            changes: observedChanges, bindings: .init(perform: { _, _ in }),
            retryAllFailed: { _ in retriedAll += 1 }, clearHistory: { clearedHistory += 1 })
        window.contentView = controller.view
        controller.startObserving()
        controller.startObserving()
        precondition(structureSubscriptions == 1, "opening an existing panel cannot duplicate its subscriptions")
        window.setContentSize(NSSize(width: 400, height: 460))
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.fittingSize == NSSize(width: 400, height: 460))
        precondition(controller.clearButton.frame.maxX <= 384)
        precondition(controller.scrollView.frame.height > 350)
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.fittingSize == NSSize(width: 400, height: 460), "long titles must not enlarge queue")
        let nativeRows = controller.rowsStack.arrangedSubviews.compactMap { $0 as? DownloadTaskRowView }
        precondition(nativeRows.count == 3)
        precondition(nativeRows[0].buttons[.retry] == nil && nativeRows[1].buttons[.retry] == nil
            && nativeRows[2].buttons[.retry]?.isHidden == false, "only a real retry capability creates a retry control")
        for row in nativeRows {
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
        rows[0] = DownloadTaskRow(id: rows[0].id, title: String(repeating: "Long wallpaper title ", count: 40), phase: .transferring)
        changes.send()
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.fittingSize == NSSize(width: 400, height: 460))
        controller.retryButton.performClick(nil)
        controller.clearButton.performClick(nil)
        precondition(retriedAll == 1 && clearedHistory == 1, "bulk actions dispatch directly without creating a second queue or confirmation")
        rows = [WallpaperProvider.steamWorkshop, .pixabay, .wallhaven, .pixiv].map { provider in
            .init(id: .init(reference: .init(provider: provider, sourceID: "7"), attemptID: "local"),
                  title: provider.rawValue, phase: .completed, actions: [.removeHistory])
        }
        changes.send()
        precondition(controller.rowsStack.arrangedSubviews.compactMap { $0 as? DownloadTaskRowView }.count == 4,
            "the native local-history panel admits all four equal source IDs without an account or source filter")
        controller.stopObserving()
        precondition(structureSubscriptions == 0 && controller.rowsStack.arrangedSubviews.isEmpty)
        changes.send()
        precondition(controller.rowsStack.arrangedSubviews.isEmpty, "closed panel must not consume source updates")
        controller.startObserving()
        precondition(structureSubscriptions == 1 && controller.rowsStack.arrangedSubviews.compactMap { $0 as? DownloadTaskRowView }.count == 4)
        controller.stopObserving()
        precondition(structureSubscriptions == 0)

        var thumbnailLoads = 0, thumbnailCancels = 0, progressCancels = 0
        var progressDelivery: ((DownloadTaskProgress) -> Void)?
        var lateThumbnail: ((NSImage?) -> Void)?
        let firstImage = NSImage(size: NSSize(width: 8, height: 8)), nextImage = NSImage(size: NSSize(width: 9, height: 9))
        let firstID = DownloadTaskIdentity(reference: .init(provider: .steamWorkshop, sourceID: "lease"), attemptID: "1")
        let nextID = DownloadTaskIdentity(reference: .init(provider: .steamWorkshop, sourceID: "lease"), attemptID: "2")
        let leaseRow = DownloadTaskRowView(bindings: .init(perform: { _, _ in }, loadThumbnail: { row, receive in
            thumbnailLoads += 1
            if row.id == firstID { lateThumbnail = receive; receive(firstImage) } else { receive(nextImage) }
            return { thumbnailCancels += 1 }
        }, observeProgress: { _, receive in
            progressDelivery = receive
            return { progressCancels += 1 }
        }))
        let firstValue = DownloadTaskRow(id: firstID, title: "lease", phase: .transferring, thumbnailKey: "first")
        leaseRow.configure(firstValue)
        progressDelivery?(.init(phase: .transferring, fraction: 0.1, verifiedBytes: 100, totalBytes: 10000, sequence: 1))
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        progressDelivery?(.init(phase: .transferring, fraction: 0.3, verifiedBytes: 3000, totalBytes: 10000, sequence: 2))
        precondition(leaseRow.statusLabel.stringValue.contains("/s"), "a live row keeps byte speed sampling")
        let speedText = leaseRow.statusLabel.stringValue
        leaseRow.configure(firstValue)
        precondition(thumbnailLoads == 1 && thumbnailCancels == 0 && progressCancels == 0
            && leaseRow.thumbnailView.image === firstImage && leaseRow.statusLabel.stringValue == speedText,
            "same-attempt echo retains warm pixels, progress lease and its speed sample")
        leaseRow.configure(.init(id: nextID, title: "next", phase: .transferring, thumbnailKey: "next"))
        lateThumbnail?(firstImage)
        precondition(leaseRow.thumbnailView.image === nextImage && thumbnailCancels == 1 && progressCancels == 1,
            "reused row cancels only its old leases and cannot accept old-attempt pixels")
        leaseRow.unbind()
        precondition(thumbnailCancels == 2 && progressCancels == 2)
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
        var clickCounts: [Int] = []
        var backgroundClicks = 0
        cards.primaryClickHandler = { path, clickCount in opened.append(path); clickCounts.append(clickCount); return true }
        cards.onBackgroundLeftClick = { backgroundClicks += 1 }
        func event(_ type: NSEvent.EventType, _ point: NSPoint, clickCount: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: cards.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: clickCount, pressure: 1)!
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
        cards.mouseDown(with: event(.leftMouseDown, center(0), clickCount: 2))
        cards.mouseUp(with: event(.leftMouseUp, center(0), clickCount: 2))
        precondition(opened.count == 4 && opened.last == IndexPath(item: 0, section: 0)
            && clickCounts == [1, 1, 1, 2], "the real mouse release must forward its original click count once")
        withExtendedLifetime(dataSource) {}
        print("AppKit hit routing and queue geometry PASS")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-steam-appkit-', dir='/private/tmp') as folder:
            folder = pathlib.Path(folder)
            shared = (ROOT / 'MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift').read_text()
            harness = harness.replace('// ACTUAL_SCROLL_DISMISSAL', '@MainActor\n' + declaration(shared, 'final class ToolbarPopoverScrollDismissal:'))
            sources = [ROOT / 'MyWallpaperX' / name for name in (
                'Models/WallpaperReference.swift', 'Models/DownloadTask.swift',
                'Shared/UI/WallpaperGridScrollView.swift',
                'Modules/Downloads/Core/DownloadTaskProjection.swift')]
            for name, exposed in {
                'DownloadTaskRowView.swift': ['thumbnailView', 'titleLabel', 'statusLabel', 'progressBar'],
                'DownloadTasksPopover.swift': ['retryButton', 'clearButton', 'scrollView', 'rowsStack', 'emptyLabel', 'noticeLabel'],
            }.items():
                text = (ROOT / 'MyWallpaperX/Modules/Downloads/UI' / name).read_text()
                for field in exposed:
                    marker = 'private let ' + field + ' ='
                    self.assertEqual(text.count(marker), 1)
                    text = text.replace(marker, 'let ' + field + ' =', 1)
                if name == 'DownloadTaskRowView.swift':
                    self.assertEqual(text.count('private var buttons:'), 1)
                    text = text.replace('private var buttons:', 'var buttons:', 1)
                frozen = folder / name
                frozen.write_text(text)
                sources.append(frozen)
            path = folder / 'Harness.swift'
            path.write_text(harness)
            binary = folder / 'harness'
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(UI / 'SteamWorkshopKeyboardCollectionView.swift'), *map(str, sources), str(path), '-o', str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('AppKit hit routing and queue geometry PASS', result.stdout)
