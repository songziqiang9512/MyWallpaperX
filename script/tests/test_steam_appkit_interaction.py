"""Run the production hit-test route and popover/row constraints in AppKit."""
import os
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_steam_library_interactions import method
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.native_app_harness import native_app_session

ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI'


class SteamAppKitInteractionTests(unittest.TestCase):
    def _download_ui_sources(self, work):
        sources = [ROOT / 'MyWallpaperX' / name for name in (
            'Models/WallpaperReference.swift', 'Models/DownloadTask.swift', 'Shared/ThumbnailRequest.swift',
            'Shared/UI/WallpaperGridScrollView.swift', 'Modules/Downloads/Core/DownloadTaskProjection.swift',
            'Modules/Downloads/UI/DownloadTaskRowPresentation.swift')]
        for name, exposed in {
            'DownloadTaskRowView.swift': ['thumbnailView', 'titleLabel', 'statusLabel', 'progressBar'],
            'DownloadTasksPopover.swift': ['retryButton', 'clearButton', 'scrollView', 'tableView', 'emptyLabel', 'noticeLabel'],
        }.items():
            text = (ROOT / 'MyWallpaperX/Modules/Downloads/UI' / name).read_text()
            for field in exposed:
                marker = 'private let ' + field + ' ='
                self.assertEqual(text.count(marker), 1)
                text = text.replace(marker, 'let ' + field + ' =', 1)
            for marker in (['private var buttons:'] if name == 'DownloadTaskRowView.swift' else
                           ['private var statesByID:', 'private var dataSource:', 'private enum Section', 'private enum Item']):
                self.assertEqual(text.count(marker), 1)
                text = text.replace(marker, marker.removeprefix('private '), 1)
            if name == 'DownloadTaskRowView.swift':
                marker = '        super.init(frame: frameRect)'
                self.assertEqual(text.count(marker), 1)
                text = text.replace(marker, marker + '\n        Self.testInstances.append { [weak self] in self }', 1)
                text = text.replace('    override init(frame frameRect: NSRect) {',
                    '    static var testInstances: [() -> DownloadTaskRowView?] = []\n    override init(frame frameRect: NSRect) {', 1)
            frozen = work / name
            frozen.write_text(text)
            sources.append(frozen)
        return sources

    def _run_fixture(self, binary, build, name, timeout):
        proof = os.environ.get('MWX_DOWNLOAD_ROW_PROOF_DIR')
        target = pathlib.Path(proof) / name if proof else None
        if target:
            target.mkdir(parents=True, exist_ok=True)
            (target / 'compile.log').write_text(build.stdout + build.stderr)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        home, temporary = binary.parent / 'home', binary.parent / 'tmp'
        home.mkdir(); temporary.mkdir()
        with native_app_session():
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temporary) + '/'),
                capture_output=True, text=True, timeout=timeout)
        if target:
            (target / 'stdout.log').write_text(run.stdout)
            (target / 'stderr.log').write_text(run.stderr)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        for diagnostic in ('Unable to simultaneously satisfy constraints', 'Conflicting constraints detected'):
            self.assertNotIn(diagnostic, run.stderr)
        return run

    def test_hit_routing_and_popover_geometry(self):
        harness = r'''
import AppKit
import Combine
final class WallpaperCardGlassBarView: NSView {
    func setProgressAnimationVisible(_ visible: Bool) {}
}
// ACTUAL_SCROLL_DISMISSAL
protocol ToolbarGridScrollDismissalSurface {}
final class TestItem: NSCollectionViewItem {
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 150)) }
}
@MainActor final class RowScaleWindow: NSWindow {
    var testScale: CGFloat = 1
    override var backingScaleFactor: CGFloat { testScale }
}
@main struct Harness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            ([view] + view.subviews.flatMap { descendants($0, NSView.self) }).compactMap { $0 as? T }
        }
        func layout(_ content: DownloadTasksContentController) {
            content.view.layoutSubtreeIfNeeded()
            content.tableView.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        func visibleRows(_ content: DownloadTasksContentController) -> [DownloadTaskRowView] {
            let table = content.tableView, range = table.rows(in: table.visibleRect)
            guard range.location != NSNotFound else { return [] }
            return (range.location..<NSMaxRange(range)).flatMap { index -> [DownloadTaskRowView] in
                guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) else { return [] }
                return descendants(cell, DownloadTaskRowView.self)
            }
        }
        do {
            let lifecycleChanges = PassthroughSubject<Void, Never>()
            var value = DownloadTaskSnapshot()
            let lifecycle = DownloadTasksContentController(snapshot: { value },
                changes: lifecycleChanges.eraseToAnyPublisher(), bindings: .init(perform: { _, _ in }),
                retryAllFailed: nil, clearHistory: nil)
            window.contentView = lifecycle.view
            window.setContentSize(NSSize(width: 400, height: 460))
            window.orderFront(nil)
            lifecycle.startObserving()
            layout(lifecycle)
            precondition(lifecycle.tableView.numberOfRows == 0 && lifecycle.statesByID.isEmpty && !lifecycle.emptyLabel.isHidden,
                "a first empty presentation has no rows or presentation consumers")
            let first = DownloadTaskRow(id: .init(reference: .init(provider: .pixabay, sourceID: "first"), attemptID: "layout"),
                title: "First", phase: .transferring)
            let second = DownloadTaskRow(id: .init(reference: .init(provider: .wallhaven, sourceID: "second"), attemptID: "layout"),
                title: "Second", phase: .transferring)
            value.active = [first, second]; value.notice = "下载历史暂不可用，请稍后重试。"
            lifecycleChanges.send(); layout(lifecycle)
            let mounted = visibleRows(lifecycle), notice = lifecycle.noticeLabel
            let firstState = ObjectIdentifier(lifecycle.statesByID[first.id]!), secondState = ObjectIdentifier(lifecycle.statesByID[second.id]!)
            precondition(mounted.count == 2 && notice.window === window && notice.stringValue == value.notice)
            for row in mounted {
                precondition(row.bounds.height == 76 && abs(row.bounds.width - (lifecycle.tableView.bounds.width - 32)) <= 0.5,
                    "visible native task rows preserve the full table width with sixteen-point side insets")
            }
            let mountedIDs = mounted.map(ObjectIdentifier.init)
            lifecycleChanges.send(); layout(lifecycle)
            precondition(visibleRows(lifecycle).map(ObjectIdentifier.init) == mountedIDs,
                "a same-value source echo keeps mounted controls in place")
            let shortNoticeHeight = lifecycle.tableView.rect(ofRow: 0).height
            value.notice = String(repeating: "下载历史暂不可用，请稍后重试。", count: 8)
            lifecycleChanges.send(); layout(lifecycle)
            precondition(lifecycle.tableView.rect(ofRow: 0).height > shortNoticeHeight
                && notice.bounds.height == lifecycle.tableView.rect(ofRow: 0).height
                && visibleRows(lifecycle).count == 2,
                "a changed multiline notice grows its native row without clipping or replacing task consumers")
            value.active = [second, first]
            lifecycleChanges.send(); layout(lifecycle)
            precondition(visibleRows(lifecycle).compactMap(\.displayedTask?.id) == [second.id, first.id]
                && ObjectIdentifier(lifecycle.statesByID[first.id]!) == firstState
                && ObjectIdentifier(lifecycle.statesByID[second.id]!) == secondState,
                "native snapshot order changes while task presentation identities remain stable")
            let removedNoticeText = notice.stringValue
            value.active = [second]; value.notice = nil
            lifecycleChanges.send(); layout(lifecycle)
            precondition(lifecycle.statesByID[first.id] == nil && visibleRows(lifecycle).compactMap(\.displayedTask?.id) == [second.id]
                && !descendants(lifecycle.tableView, NSTextField.self).contains { $0.stringValue == removedNoticeText },
                "removed tasks release their model and removed notices cannot remain visible")
            value.active = [first, second]; value.notice = "下载历史仍不可用。"
            lifecycleChanges.send(); layout(lifecycle)
            precondition(visibleRows(lifecycle).compactMap(\.displayedTask?.id) == [first.id, second.id]
                && ObjectIdentifier(lifecycle.statesByID[second.id]!) == secondState && notice.stringValue == value.notice,
                "restoring a task and notice mounts current values without replacing the retained presentation")
            lifecycle.stopObserving()
            precondition(lifecycle.statesByID.isEmpty && mounted.allSatisfy { $0.displayedTask == nil })
            lifecycle.startObserving(); layout(lifecycle)
            precondition(visibleRows(lifecycle).count == 2 && lifecycle.statesByID.count == 2,
                "reopening binds the current snapshot to the reusable native table")
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
        layout(controller)
        precondition(controller.view.fittingSize == NSSize(width: 400, height: 460))
        precondition(controller.clearButton.frame.maxX <= 384)
        precondition(controller.retryButton.title == "重试全部")
        precondition(controller.scrollView.frame.height > 350)
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.fittingSize == NSSize(width: 400, height: 460), "long titles must not enlarge queue")
        let nativeRows = visibleRows(controller)
        precondition(nativeRows.count == 3)
        precondition(nativeRows[0].buttons[.retry] == nil && nativeRows[1].buttons[.retry] == nil
            && nativeRows[2].buttons[.retry]?.isHidden == false, "only a real retry capability creates a retry control")
        for row in nativeRows {
            precondition(row.bounds.height == 76)
            precondition(row.progressBar.bounds.width > 200)
            precondition(!row.titleLabel.stringValue.isEmpty)
            let imageX = row.thumbnailView.convert(.zero, to: controller.view).x
            precondition(abs(imageX - 16) < 0.5, "row thumbnail shares the header's inset")
        }
        let historyHeading = descendants(controller.tableView, NSTextField.self)
            .first { $0.stringValue.hasPrefix("历史记录") }!
        let headingAlignment = historyHeading.alignmentRect(forFrame: historyHeading.frame)
        precondition(abs(historyHeading.superview!.convert(headingAlignment.origin, to: controller.view).x - 16) < 0.5,
            "history heading is inset from the popover edge, including native label alignment insets")
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
        layout(controller)
        precondition(controller.statesByID.count == 4 && visibleRows(controller).count == 4,
            "the native local-history panel admits all four equal source IDs without an account or source filter")
        controller.stopObserving()
        precondition(structureSubscriptions == 0 && controller.statesByID.isEmpty)
        changes.send()
        precondition(controller.statesByID.isEmpty && descendants(controller.tableView, DownloadTaskRowView.self).allSatisfy { $0.displayedTask == nil },
            "closed panel cannot consume source updates or leave a reusable view bound to old commands")
        controller.startObserving()
        layout(controller)
        precondition(structureSubscriptions == 1 && controller.statesByID.count == 4 && visibleRows(controller).count == 4)
        controller.stopObserving()
        precondition(structureSubscriptions == 0)

        var thumbnailLoads = 0, thumbnailCancels = 0, progressCancels = 0
        var progressDelivery: ((DownloadTaskProgress) -> Void)?
        var lateThumbnail: ((NSImage?) -> Void)?
        let firstImage = NSImage(size: NSSize(width: 8, height: 8)), nextImage = NSImage(size: NSSize(width: 9, height: 9))
        let firstID = DownloadTaskIdentity(reference: .init(provider: .steamWorkshop, sourceID: "lease"), attemptID: "1")
        let nextID = DownloadTaskIdentity(reference: .init(provider: .steamWorkshop, sourceID: "lease"), attemptID: "2")
        let rowHost = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 460))
        window.contentView = rowHost
        func mount(_ row: DownloadTaskRowView, in host: NSView) {
            host.addSubview(row)
            NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                row.topAnchor.constraint(equalTo: host.topAnchor), row.widthAnchor.constraint(equalTo: host.widthAnchor)])
            host.layoutSubtreeIfNeeded()
        }
        let leaseRow = DownloadTaskRowView(bindings: .init(perform: { _, _ in }, loadThumbnail: { row, _, receive in
            thumbnailLoads += 1
            if row.id == firstID { lateThumbnail = receive; receive(firstImage) } else { receive(nextImage) }
            return { thumbnailCancels += 1 }
        }, observeProgress: { _, receive in
            progressDelivery = receive
            return { progressCancels += 1 }
        }))
        let firstValue = DownloadTaskRow(id: firstID, title: "lease", phase: .transferring, thumbnailKey: "first")
        leaseRow.configure(firstValue)
        mount(leaseRow, in: rowHost)
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
        leaseRow.removeFromSuperview()
        do {
            let initial = DownloadTaskProgress(phase: .transferring, statusText: "transfer-start", fraction: 0.1,
                verifiedBytes: 100, totalBytes: 10000, sequence: 1)
            let latest = DownloadTaskProgress(phase: .transferring, statusText: "transferring", fraction: 0.3,
                verifiedBytes: 3000, totalBytes: 10000, sequence: 2)
            var loads = 0, imageCancels = 0, observers = 0, observerCancels = 0
            var deliver: ((DownloadTaskProgress) -> Void)?
            let snapshotRow = DownloadTaskRowView(bindings: .init(perform: { _, _ in }, loadThumbnail: { value, _, receive in
                loads += 1; receive(value.thumbnailKey == "first" ? firstImage : nextImage)
                return { imageCancels += 1 }
            }, observeProgress: { _, receive in
                observers += 1; deliver = receive; receive(initial)
                return { observerCancels += 1 }
            }))
            snapshotRow.configure(.init(id: firstID, title: "snapshot", phase: .preparing,
                progress: initial, thumbnailKey: "first", actions: [.pause]))
            mount(snapshotRow, in: rowHost)
            precondition(snapshotRow.statusLabel.stringValue.hasPrefix("transfer-start") && snapshotRow.progressBar.doubleValue == 0.1,
                "initial snapshot plus immediate observer delivery renders the real transfer sample")
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            deliver?(latest)
            let text = snapshotRow.statusLabel.stringValue
            precondition(text.contains("/s"), "the second real observer sample produces a displayed byte rate")
            snapshotRow.configure(.init(id: firstID, title: "renamed", phase: .preparing,
                progress: latest, thumbnailKey: "first", actions: [.cancel]))
            precondition(snapshotRow.statusLabel.stringValue == text && snapshotRow.statusLabel.toolTip == text
                && (snapshotRow.progressBar.accessibilityValue() as? String) == text
                && snapshotRow.progressBar.doubleValue == 0.3 && !snapshotRow.progressBar.isHidden,
                "a structural snapshot echo of delivered Steam transfer progress must preserve rate, tooltip and AX value")
            precondition(loads == 1 && imageCancels == 0 && observers == 1 && observerCancels == 0
                && snapshotRow.thumbnailView.image === firstImage && snapshotRow.titleLabel.stringValue == "renamed"
                && snapshotRow.buttons[.pause]?.isHidden == true && snapshotRow.buttons[.cancel]?.isHidden == false,
                "ignoring echoed progress still configures title and actions while keeping the existing consumer leases")
            snapshotRow.configure(.init(id: firstID, title: "renamed", phase: .preparing, progress: latest, thumbnailKey: "next"))
            precondition(snapshotRow.statusLabel.stringValue == text && snapshotRow.thumbnailView.image === nextImage
                && loads == 2 && imageCancels == 1 && observers == 1 && observerCancels == 0,
                "an echoed sample cannot bypass configuration of a changed thumbnail key")
            for phase in [DownloadTaskPhase.queued, .saving, .failed] {
                snapshotRow.configure(.init(id: firstID, title: "phase", phase: .preparing,
                    progress: .init(phase: phase, statusText: phase.rawValue, fraction: 0.4, sequence: 2), thumbnailKey: "next"))
                precondition(snapshotRow.statusLabel.stringValue == phase.rawValue && snapshotRow.progressBar.doubleValue == 0.4,
                    "non-transfer progress with an unchanged sequence still presents its new state")
            }
            snapshotRow.configure(.init(id: firstID, title: "metadata", phase: .transferring,
                progress: .init(phase: .transferring, statusText: "metadata-phase", fraction: 0.3,
                    verifiedBytes: 3000, totalBytes: 10000, sequence: 2), thumbnailKey: "next"))
            precondition(snapshotRow.statusLabel.stringValue.hasPrefix("metadata-phase") && snapshotRow.progressBar.doubleValue == 0.3,
                "metadata phase changes still apply a transfer sample even with the same sequence")
            for (sequence, fraction, bytes) in [(3, 0.5, Int64(5000)), (1, 0.05, Int64(500))] {
                snapshotRow.configure(.init(id: firstID, title: "sequence", phase: .transferring,
                    progress: .init(phase: .transferring, statusText: "sequence-\(sequence)", fraction: fraction,
                        verifiedBytes: bytes, totalBytes: 10000, sequence: sequence), thumbnailKey: "next"))
                precondition(snapshotRow.statusLabel.stringValue.hasPrefix("sequence-\(sequence)") && snapshotRow.progressBar.doubleValue == fraction,
                    "different transfer sequences retain existing presentation semantics, including lower sequences")
            }
            snapshotRow.configure(.init(id: nextID, title: "next-attempt", phase: .preparing,
                progress: initial, thumbnailKey: "next"))
            precondition(snapshotRow.statusLabel.stringValue.hasPrefix("transfer-start") && !snapshotRow.statusLabel.stringValue.contains("/s")
                && snapshotRow.progressBar.doubleValue == 0.1 && observers == 2 && observerCancels == 1 && loads == 3 && imageCancels == 2,
                "a new attempt resets byte sampling and binds its own consumers")
            snapshotRow.unbind()
            precondition(observerCancels == 2 && imageCancels == 3)
            let online = DownloadTaskRowView(bindings: .init(perform: { _, _ in }))
            let onlineID = DownloadTaskIdentity(reference: .init(provider: .pixabay, sourceID: "fraction"), attemptID: "online")
            for fraction in [0.2, 0.6] {
                online.configure(.init(id: onlineID, title: "online", phase: .transferring,
                    progress: .init(phase: .transferring, statusText: "online-\(fraction)", fraction: fraction)))
                precondition(online.statusLabel.stringValue == "online-\(fraction)" && online.progressBar.doubleValue == fraction,
                    "online fraction-only progress continues updating with its default zero sequence")
            }
            online.unbind()
        }
        do {
            let scaleWindow = RowScaleWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                styleMask: [.titled], backing: .buffered, defer: false)
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
            scaleWindow.contentView = host
            var targets: [ThumbnailRequest] = [], deliveries: [(NSImage?) -> Void] = []
            var cancels = 0
            let demandRow = DownloadTaskRowView(bindings: .init(perform: { _, _ in }, loadThumbnail: { _, target, receive in
                targets.append(target); deliveries.append(receive)
                if targets.count == 1 { receive(firstImage) }
                return { cancels += 1 }
            }))
            demandRow.configure(firstValue)
            precondition(targets.isEmpty, "a detached row waits for its real window backing")
            mount(demandRow, in: host)
            precondition(demandRow.window === scaleWindow && demandRow.thumbnailView.bounds.size == NSSize(width: 48, height: 48)
                && targets == [ThumbnailRequest(size: demandRow.thumbnailView.bounds.size, scale: scaleWindow.backingScaleFactor, mode: .fit)!]
                && demandRow.thumbnailView.image === firstImage,
                "first native attachment requests the actual 48-point fit surface and accepts a synchronous warm image")
            demandRow.configure(firstValue); demandRow.viewDidChangeBackingProperties()
            precondition(targets.count == 1 && cancels == 0, "same source and backing keep the current image lease")
            scaleWindow.testScale = 2
            demandRow.viewDidChangeBackingProperties()
            precondition(targets.count == 2 && targets[1] == ThumbnailRequest(size: demandRow.thumbnailView.bounds.size,
                scale: scaleWindow.backingScaleFactor, mode: .fit)! && cancels == 1
                && demandRow.thumbnailView.image === firstImage,
                "same-source backing growth replaces the demand while keeping its displayed image")
            deliveries[0](nextImage); deliveries[1](nil)
            precondition(demandRow.thumbnailView.image === firstImage, "old-target pixels and a failed upgrade cannot replace the current image")
            deliveries[1](nextImage)
            precondition(demandRow.thumbnailView.image === nextImage, "current-target pixels replace the retained image")
            demandRow.removeFromSuperview()
            mount(demandRow, in: host)
            precondition(targets.count == 2 && cancels == 1 && demandRow.thumbnailView.image === nextImage,
                "temporary native reparenting with unchanged backing preserves the existing demand and image")
            demandRow.configure(.init(id: firstID, title: "new-key", phase: .transferring, thumbnailKey: "new-key"))
            let placeholder = demandRow.thumbnailView.image
            deliveries[1](firstImage)
            precondition(targets.count == 3 && cancels == 2 && demandRow.thumbnailView.image === placeholder,
                "a changed source key clears its image and rejects the old-key callback")
            deliveries[2](nextImage)
            demandRow.configure(.init(id: nextID, title: "new-attempt", phase: .transferring, thumbnailKey: "new-key"))
            let attemptPlaceholder = demandRow.thumbnailView.image
            deliveries[2](firstImage)
            precondition(targets.count == 4 && cancels == 3 && demandRow.thumbnailView.image === attemptPlaceholder,
                "an attempt change rejects old pixels even when source key and target match")
            deliveries[3](nextImage)
            demandRow.configure(.init(id: nextID, title: "no-preview", phase: .transferring))
            let emptyPlaceholder = demandRow.thumbnailView.image
            deliveries[3](firstImage)
            precondition(targets.count == 4 && cancels == 4 && emptyPlaceholder !== nextImage
                && demandRow.thumbnailView.image === emptyPlaceholder, "a missing key cancels without starting another image request")
            demandRow.configure(.init(id: nextID, title: "live", phase: .transferring, thumbnailKey: "live"))
            deliveries[4](nextImage)
            demandRow.unbind(); deliveries[4](firstImage)
            precondition(targets.count == 5 && cancels == 5 && demandRow.displayedTask == nil
                && demandRow.thumbnailView.image === nextImage, "unbind releases the active image lease and rejects its late callback")
            scaleWindow.orderOut(nil)
        }
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
            sources = self._download_ui_sources(folder)
            path = folder / 'Harness.swift'
            path.write_text(harness)
            binary = folder / 'harness'
            result = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-parse-as-library',
                str(UI / 'SteamWorkshopKeyboardCollectionView.swift'), *map(str, sources), str(path), '-o', str(binary)],
                capture_output=True, text=True, timeout=90)
            result = self._run_fixture(binary, result, 'row-native', 30)
            self.assertIn('AppKit hit routing and queue geometry PASS', result.stdout)

    def test_long_history_uses_visible_native_rows_and_keeps_all_presentations(self):
        harness = r'''
import AppKit
import Combine
// ACTUAL_SCROLL_DISMISSAL
protocol ToolbarGridScrollDismissalSurface {}
@main struct Harness {
    @MainActor static func main() {
        _ = NSApplication.shared
        for count in [100, 1000] { autoreleasepool {
            DownloadTaskRowView.testInstances.removeAll()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let changes = PassthroughSubject<Void, Never>()
            var rows = (0..<count).map { index in
                DownloadTaskRow(id: .init(reference: .init(provider: .steamWorkshop, sourceID: "history-\(index)"), attemptID: "one"),
                    title: "History \(index)", phase: .failed, thumbnailKey: "image-\(index)", actions: [.retry, .removeHistory])
            }
            let firstID = rows[0].id, pendingID = rows[count - 1].id, removedID = rows[count - 2].id
            var active: [DownloadTaskRow] = [], sourceCache: [DownloadTaskIdentity: NSImage] = [:]
            var pending: [DownloadTaskIdentity: (NSImage?) -> Void] = [:]
            var progress: [DownloadTaskIdentity: (DownloadTaskProgress) -> Void] = [:]
            var sourceLoads = 0, sourceCancels = 0, progressLoads = 0, progressLeases = 0
            var performed: [DownloadTaskIdentity] = [], retried: [DownloadTaskIdentity] = []
            var imageWatches: [() -> Bool] = []
            let controller = DownloadTasksContentController(snapshot: { .init(active: active, history: rows) },
                changes: changes.eraseToAnyPublisher(), bindings: .init(perform: { row, _ in performed.append(row.id) },
                loadThumbnail: { row, request, receive in
                    sourceLoads += 1
                    precondition(request == ThumbnailRequest(size: NSSize(width: 48, height: 48), scale: window.backingScaleFactor, mode: .fit)!)
                    if row.id == pendingID || row.id == removedID { pending[row.id] = receive }
                    else { autoreleasepool {
                        let image = NSImage(size: NSSize(width: 48, height: 48))
                        sourceCache[row.id] = image; imageWatches.append { [weak image] in image != nil }; receive(image)
                    } }
                    return { sourceCancels += 1 }
                }, observeProgress: { row, receive in
                    progressLoads += 1; progressLeases += 1; progress[row.id] = receive
                    receive(.init(phase: .transferring, statusText: "transfer", fraction: 0.1,
                        verifiedBytes: 100, totalBytes: 10000, sequence: 1))
                    return { progressLeases -= 1 }
                }), retryAllFailed: { retried = $0.map(\.id) }, clearHistory: nil)
            @MainActor func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
                ([view] + view.subviews.flatMap { descendants($0, NSView.self) }).compactMap { $0 as? T }
            }
            @MainActor func layout() {
                controller.view.layoutSubtreeIfNeeded(); controller.tableView.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            @MainActor func snapshotIDs() -> [DownloadTaskIdentity] {
                controller.dataSource.snapshot().itemIdentifiers.compactMap {
                    if case .task(let id) = $0 { return id }; return nil
                }
            }
            @MainActor func visibleRows() -> [DownloadTaskRowView] {
                let table = controller.tableView, range = table.rows(in: table.visibleRect)
                guard range.location != NSNotFound else { return [] }
                return (range.location..<NSMaxRange(range)).flatMap { index -> [DownloadTaskRowView] in
                    guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) else { return [] }
                    return descendants(cell, DownloadTaskRowView.self)
                }
            }
            @MainActor func boundedGeometry(_ stage: String) -> (views: Int, constraints: Int) {
                let visible = visibleRows(), living = DownloadTaskRowView.testInstances.compactMap { $0() }
                var seen: Set<ObjectIdentifier> = []
                let all = (descendants(controller.view, NSView.self) + living.flatMap { descendants($0, NSView.self) })
                    .filter { seen.insert(ObjectIdentifier($0)).inserted }
                let constraints = all.reduce(0) { $0 + $1.constraints.count }
                precondition((5...7).contains(visible.count) && living.count <= visible.count + 8,
                    "only viewport rows and a bounded native reuse margin may own controls: history=\(count), stage=\(stage), "
                        + "visible=\(visible.count), living=\(living.count), registered=\(DownloadTaskRowView.testInstances.count), "
                        + "table.visibleRect=\(controller.tableView.visibleRect), table.bounds=\(controller.tableView.bounds), "
                        + "dataRows=\(controller.tableView.numberOfRows), stateRows=\(controller.statesByID.count), "
                        + "visibleRange=\(controller.tableView.rows(in: controller.tableView.visibleRect)), "
                        + "visibleFrames=\(visible.map { $0.convert($0.bounds, to: controller.tableView) }), "
                        + "livingMounted=\(living.filter { $0.isDescendant(of: controller.view) }.count)")
                precondition(all.count < (visible.count + 8) * 32 + 100 && constraints < (visible.count + 8) * 160 + 200,
                    "views and constraints must stay near the viewport rather than scale with history")
                for row in visible {
                    precondition(row.bounds.height == 76 && row.thumbnailView.alignmentRect(forFrame: row.thumbnailView.frame).size == NSSize(width: 48, height: 48)
                        && abs(row.thumbnailView.convert(.zero, to: controller.view).x - 16) < 0.5,
                        "visible task geometry: row.bounds=\(row.bounds), height=\(row.bounds.height), thumbnail.bounds=\(row.thumbnailView.bounds), thumbnail.frame=\(row.thumbnailView.frame), thumbnail.rootRect=\(row.thumbnailView.convert(row.thumbnailView.bounds, to: controller.view)), "
                            + "thumbnailX=\(row.thumbnailView.convert(.zero, to: controller.view).x), table.frame=\(controller.tableView.frame), "
                            + "row.frame=\(row.frame), parent.frame=\(String(describing: row.superview?.frame))")
                }
                return (all.count, constraints)
            }
            @MainActor func scroll(to id: DownloadTaskIdentity) {
                let index = controller.dataSource.snapshot().indexOfItem(.task(id))!
                controller.tableView.scrollRowToVisible(index); layout()
            }
            autoreleasepool {
                window.contentView = controller.view
                window.orderFront(nil)
                controller.startObserving(); layout()
            }
            let initialGeometry = autoreleasepool { boundedGeometry("initial") }
            let identities = autoreleasepool { controller.statesByID.mapValues(ObjectIdentifier.init) }
            var stateWatches = autoreleasepool { controller.statesByID.values.map { state in { [weak state] in state != nil } } }
            autoreleasepool {
                precondition(controller.statesByID.count == count && snapshotIDs() == rows.map(\.id)
                    && sourceLoads == count && progressLoads == 0 && progressLeases == 0,
                    "all terminal data and thumbnails prepare once while terminal history opens no progress lease")
            }
            let controls = autoreleasepool { visibleRows().map(ObjectIdentifier.init) }
            let retryControls = autoreleasepool { visibleRows().map { ObjectIdentifier($0.buttons[.retry]!) } }
            autoreleasepool { changes.send(); layout() }
            autoreleasepool {
                precondition(visibleRows().map(ObjectIdentifier.init) == controls
                    && visibleRows().map { ObjectIdentifier($0.buttons[.retry]!) } == retryControls
                    && sourceLoads == count && controller.statesByID.mapValues(ObjectIdentifier.init) == identities,
                    "same-value echoes retain controls, states and all prepared image leases")
                controller.retryButton.performClick(nil)
                precondition(retried == rows.map(\.id) && retried.count == count,
                    "retry-all includes failed history beyond visible native rows in source order")
            }
            autoreleasepool {
                active = [rows.removeFirst()]
                active[0] = .init(id: firstID, title: "Active", phase: .transferring, thumbnailKey: "image-0", actions: [.pause])
                changes.send(); layout()
            }
            autoreleasepool {
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                progress[firstID]?(.init(phase: .transferring, statusText: "transfer", fraction: 0.3,
                    verifiedBytes: 3000, totalBytes: 10000, sequence: 2))
            }
            var firstImage = autoreleasepool { controller.statesByID[firstID]!.image }
            let speed = autoreleasepool { controller.statesByID[firstID]!.status!.text }
            precondition(speed.contains("/s") && progressLoads == 1 && progressLeases == 1)
            autoreleasepool { scroll(to: pendingID) }
            autoreleasepool {
                precondition(!visibleRows().contains { $0.displayedTask?.id == firstID }
                    && sourceLoads == count && sourceCancels == 0 && progressLeases == 1)
            }
            let farGeometry = autoreleasepool { boundedGeometry("far") }
            autoreleasepool { scroll(to: firstID) }
            autoreleasepool {
                precondition(visibleRows().first { $0.displayedTask?.id == firstID }?.thumbnailView.image === firstImage
                    && visibleRows().first { $0.displayedTask?.id == firstID }?.statusLabel.stringValue == speed
                    && sourceLoads == count && sourceCancels == 0 && progressLoads == 1,
                    "scroll return binds the same warm pixels and speed sample without reacquiring source consumers")
            }
            autoreleasepool { rows.reverse(); changes.send(); layout() }
            autoreleasepool {
                precondition(snapshotIDs() == [firstID] + rows.map(\.id)
                    && controller.statesByID.mapValues(ObjectIdentifier.init) == identities,
                    "reordering pending history preserves every presentation identity")
            }
            autoreleasepool {
                let image = NSImage(size: NSSize(width: 49, height: 49))
                sourceCache[pendingID] = image; imageWatches.append { [weak image] in image != nil }; pending[pendingID]?(image)
                precondition(controller.statesByID[pendingID]?.image === image,
                    "a pending thumbnail follows its task identity through snapshot reordering")
            }
            autoreleasepool {
                rows.removeAll { $0.id == removedID }; changes.send(); layout()
                pending[removedID]?(NSImage(size: NSSize(width: 50, height: 50)))
                precondition(controller.statesByID[removedID] == nil && sourceCancels == 1 && sourceLoads == count,
                    "a deleted pending task cancels once and cannot be restored by its late result")
            }
            let returnedGeometry = autoreleasepool { boundedGeometry("returned") }
            autoreleasepool {
                let oldViews = descendants(controller.tableView, DownloadTaskRowView.self), actionsBeforeClose = performed.count
                controller.stopObserving()
                for row in oldViews { for button in row.buttons.values { button.performClick(nil) } }
                pending[pendingID]?(NSImage(size: NSSize(width: 51, height: 51)))
                progress[firstID]?(.init(phase: .transferring, fraction: 0.9, sequence: 3))
                changes.send(); layout()
                precondition(controller.statesByID.isEmpty && snapshotIDs().isEmpty && progressLeases == 0 && sourceCancels == count
                    && performed.count == actionsBeforeClose && oldViews.allSatisfy { $0.displayedTask == nil },
                    "close cancels every model lease and leaves retained native controls unable to issue old commands")
                firstImage = nil; sourceCache.removeAll()
            }
            autoreleasepool {
                precondition(stateWatches.allSatisfy { !$0() } && imageWatches.allSatisfy { !$0() },
                    "closed reuse views and callbacks cannot retain old presentation states or source-cache images")
            }
            stateWatches.removeAll()
            print("Table history \(count) PASS views=\(initialGeometry.views)/\(farGeometry.views)/\(returnedGeometry.views) constraints=\(initialGeometry.constraints)/\(farGeometry.constraints)/\(returnedGeometry.constraints) thumbnails=\(sourceLoads) cancels=\(sourceCancels)")
            autoreleasepool { window.contentView = nil; window.close() }
        } }
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-download-history-', dir='/private/tmp') as directory:
            work = pathlib.Path(directory)
            shared = (ROOT / 'MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift').read_text()
            harness = harness.replace('// ACTUAL_SCROLL_DISMISSAL', '@MainActor\n' + declaration(shared, 'final class ToolbarPopoverScrollDismissal:'))
            source = work / 'Harness.swift'; source.write_text(harness)
            binary = work / 'history'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-parse-as-library',
                *map(str, self._download_ui_sources(work)), str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=90)
            run = self._run_fixture(binary, build, 'history-native', 30)
            self.assertIn('Table history 100 PASS', run.stdout)
            self.assertIn('Table history 1000 PASS', run.stdout)

    def test_actual_download_thumbnail_provider_routes(self):
        harness = r'''
import AppKit
import Combine
import CryptoKit
// ACTUAL_ONLINE_MODELS
// ACTUAL_REMOTE_REQUEST
nonisolated final class WallpaperNetworkSession: @unchecked Sendable {}
// ACTUAL_CANCELLATION_AND_PRIORITIES
struct RouteEntry { let id: Int; let localURL: URL; var isAvailable = true }
struct RouteRecord { let url: URL }
struct RouteActivity { let previewURL: URL? }
@MainActor enum RouteCalls {
    static let image = NSImage(size: NSSize(width: 17, height: 9))
    static var steam: [(URL, Int, SteamWorkshopPreviewLoadCancellation, SteamWorkshopPreviewRequestPriority)] = []
    static var pixabay: [(RouteEntry, ThumbnailRequest?, ThumbnailCacheRequestCancellation, ThumbnailCacheRequestPriority)] = []
    static var local: [(String, ThumbnailRequest?, ThumbnailCacheRequestCancellation, ThumbnailCacheRequestPriority)] = []
}
@MainActor func steamWorkshopLoadPreviewImage(from url: URL, maxPixelSize: Int = 800,
    priority: SteamWorkshopPreviewRequestPriority = .visible, cancellation: SteamWorkshopPreviewLoadCancellation?,
    completion: @escaping (NSImage?) -> Void) {
    RouteCalls.steam.append((url, maxPixelSize, cancellation!, priority)); completion(RouteCalls.image)
}
@MainActor enum PixabayDownloadedThumbnailStore {
    static func loadThumbnail(_ entry: RouteEntry, request: ThumbnailRequest? = nil, priority: ThumbnailCacheRequestPriority,
        cancellation: ThumbnailCacheRequestCancellation, completion: @escaping (String, NSImage?) -> Void) {
        RouteCalls.pixabay.append((entry, request, cancellation, priority)); completion("resolved-file-key", RouteCalls.image)
    }
}
enum SILThumbnailLoadResult { case image(NSImage), unavailable }
@MainActor final class SILThumbnailProvider {
    func load(path: String, request: ThumbnailRequest? = nil, priority: ThumbnailCacheRequestPriority = .visible,
        cancellation: ThumbnailCacheRequestCancellation, completion: @escaping (SILThumbnailLoadResult) -> Void) {
        RouteCalls.local.append((path, request, cancellation, priority)); completion(.image(RouteCalls.image))
    }
}
@MainActor final class RouteSteam {
    struct Record { let previewURL: URL? }
    struct Item { let previewImageURL: URL? }
    var published: URL?, browser: URL?
    func latestDownloadRecord(for id: String) -> Record? { published.map { Record(previewURL: $0) } }
    func browserItemForDownload(id: String) -> Item? { browser.map { Item(previewImageURL: $0) } }
}
@MainActor final class RoutePixabay {
    struct Content { var entries: [RouteEntry] = [] }
    var downloadedContent = Content(), activity: RouteActivity?
    func downloadActivity(for id: Int) -> RouteActivity? { activity }
}
@MainActor final class RouteImages {
    struct Snapshot { var unavailable = Set<OnlineImageAssetID>() }
    var snapshot = Snapshot(), records: [WallpaperReference: RouteRecord] = [:]
    var activity: RouteActivity?, requestedSources: [OnlineImageSource] = []
    var preparedSources = Set<OnlineImageSource>()
    func prepareLocal(_ sources: Set<OnlineImageSource>) { preparedSources.formUnion(sources) }
    let session = WallpaperNetworkSession()
    func record(for reference: WallpaperReference) -> RouteRecord? { records[reference] }
    func localURL(for record: RouteRecord) -> URL? { record.url }
    func downloadActivity(for id: OnlineImageAssetID) -> RouteActivity? { activity }
    func thumbnailRequest(url: URL, source: OnlineImageSource) -> OnlineImageThumbnailRequest {
        requestedSources.append(source)
        return .init(url: url, scopeID: source.rawValue + "-session", session: session,
            referer: URL(string: "https://fixture.invalid/author/"))
    }
}
@MainActor final class OnlineImageThumbnailCache {
    static let shared = OnlineImageThumbnailCache()
    var ready: NSImage?
    var readyCalls: [(OnlineImageThumbnailRequest, ThumbnailRequest)] = []
    var imageCalls: [(OnlineImageThumbnailRequest, ThumbnailRequest, OnlineImageThumbnailRequestPriority)] = []
    var pending: [CheckedContinuation<NSImage?, Never>] = []
    var finished = 0, cancelled = 0
    func readyImage(for source: OnlineImageThumbnailRequest, request: ThumbnailRequest) -> NSImage? {
        readyCalls.append((source, request)); return ready
    }
    func image(for source: OnlineImageThumbnailRequest, request: ThumbnailRequest,
        priority: OnlineImageThumbnailRequestPriority) async -> NSImage? {
        imageCalls.append((source, request, priority))
        let image = await withCheckedContinuation { pending.append($0) }
        if Task.isCancelled { cancelled += 1 }
        finished += 1
        return image
    }
}
@MainActor final class DownloadTasksPopoverController {
    let bindings: DownloadTaskRowPresentation.Bindings
    init(snapshot: @escaping () -> DownloadTaskSnapshot, changes: AnyPublisher<Void, Never>,
        bindings: DownloadTaskRowPresentation.Bindings, retryAllFailed: (([DownloadTaskRow]) -> Void)?, clearHistory: (() -> Void)?) {
        self.bindings = bindings
    }
}
@MainActor final class RouteController {
    let steam = RouteSteam(), pixabay = RoutePixabay(), images = RouteImages(), localThumbnails = SILThumbnailProvider()
    final class History { var entries: [DownloadTerminalReceipt] = [] }
    let history: History? = .init()
    let changes = PassthroughSubject<Void, Never>().eraseToAnyPublisher()
    func snapshot() -> DownloadTaskSnapshot { .init() }
    func perform(_ row: DownloadTaskRow, action: DownloadTaskAction) {}
    func observeProgress(_ row: DownloadTaskRow, receive: @escaping (DownloadTaskProgress) -> Void) -> (() -> Void)? { nil }
    func clearHistory() {}
    // ACTUAL_CONTROLLER_METHODS
}
enum GridThumbnailDecoder {
    // ACTUAL_PIXEL_LIMIT
}
@main struct Harness {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let controller = RouteController()
        controller.history?.entries = [.init(id: .init(reference: .init(provider: .pixiv, sourceID: "42:p0"), attemptID: "past"),
            title: "retained", outcome: .completed, recordedAt: nil, failureMessage: nil)]
        let binding = controller.makePopoverController().bindings.loadThumbnail!
        let published = URL(fileURLWithPath: "/controlled/published.jpg"), browser = URL(string: "https://fixture.invalid/browser.jpg")!
        controller.steam.published = published; controller.steam.browser = browser
        func row(_ provider: WallpaperProvider, _ id: String) -> DownloadTaskRow {
            .init(id: .init(reference: .init(provider: provider, sourceID: id), attemptID: "current"), title: "route", phase: .completed,
                thumbnailKey: "source-key")
        }
        var checks = 0
        func check(_ passed: Bool, _ message: String) { checks += 1; precondition(passed, message) }
        check(controller.images.preparedSources == [.pixiv], "opening the panel prepares only the retained history's real image provider")
        func wait(_ condition: () -> Bool) async {
            let end = Date().addingTimeInterval(3)
            while !condition(), Date() < end { await Task.yield() }
            precondition(condition(), "controlled async route did not finish")
        }
        for (width, tier) in [(48, 256), (96, 256), (300, 512), (700, 800), (1200, 800)] {
            var delivered: NSImage?
            let cancel = binding(row(.steamWorkshop, "steam"), .init(width: width, height: width, mode: .fit)) { delivered = $0 }
            let call = RouteCalls.steam.last!
            check(call.0 == published && call.1 == tier && call.3 == .visible && delivered === RouteCalls.image,
                "real Steam binding preserves the published source, installed tier and synchronous delivery")
            cancel?(); check(call.2.cancelled, "Steam consumer cancellation reaches its original token")
        }
        controller.steam.published = nil
        _ = binding(row(.steamWorkshop, "fallback"), .init(width: 96, height: 96, mode: .fit)) { _ in }
        check(RouteCalls.steam.last!.0 == browser, "Steam keeps its browser preview fallback")
        let target = ThumbnailRequest(width: 96, height: 48, mode: .fit)
        let local = URL(fileURLWithPath: "/controlled/local.png")
        controller.pixabay.downloadedContent.entries = [.init(id: 7, localURL: local)]
        var delivered: NSImage?
        let pixabayCancel = binding(row(.pixabay, "7"), target) { delivered = $0 }
        let pixabay = RouteCalls.pixabay.last!
        check(pixabay.0.id == 7 && pixabay.1 == target && pixabay.3 == .visible && delivered === RouteCalls.image,
            "real Pixabay binding passes both target axes and fit mode to the original store")
        pixabayCancel?(); check(pixabay.2.cancelled, "Pixabay cancellation reaches its original token")
        let localID = OnlineImageAssetID(source: .wallhaven, artworkID: "local")
        controller.images.records[localID.reference] = .init(url: local)
        delivered = nil
        let localCancel = binding(row(.wallhaven, "local"), target) { delivered = $0 }
        let sil = RouteCalls.local.last!
        check(sil.0 == local.path && sil.1 == target && sil.3 == .visible && delivered === RouteCalls.image,
            "real local-image binding passes the exact request and original path to SIL")
        localCancel?(); check(sil.2.cancelled, "SIL cancellation reaches its original token")
        let remote = OnlineImageThumbnailCache.shared
        remote.ready = RouteCalls.image
        controller.pixabay.activity = .init(previewURL: browser)
        controller.pixabay.downloadedContent.entries[0].isAvailable = false
        delivered = nil
        let warmCancel = binding(row(.pixabay, "7"), target) { delivered = $0 }
        let warm = remote.readyCalls.last!
        check(warm.0.url == browser && warm.0.scopeID == nil && warm.1 == target
            && delivered === RouteCalls.image && warmCancel == nil && remote.imageCalls.isEmpty && RouteCalls.pixabay.count == 1,
            "unavailable Pixabay local content uses the exact remote request and synchronous ready image")
        controller.images.snapshot.unavailable.insert(localID)
        controller.images.activity = .init(previewURL: browser)
        _ = binding(row(.wallhaven, "local"), target) { _ in }
        let scopedWarm = remote.readyCalls.last!
        check(scopedWarm.1 == target && scopedWarm.0.scopeID == "wallhaven-session" && RouteCalls.local.count == 1,
            "unavailable online local content retains its original scoped remote fallback")
        remote.ready = nil; delivered = nil
        let coldCancel = binding(row(.pixiv, "art:p2"), target) { delivered = $0 }
        await wait { remote.pending.count == 1 }
        let cold = remote.imageCalls[0], peek = remote.readyCalls.last!
        check(cold.1 == target && peek.1 == target && cold.2 == .visible && cold.0.url == browser
            && cold.0.scopeID == "pixiv-session" && cold.0.session === controller.images.session
            && cold.0.referer == URL(string: "https://fixture.invalid/author/")
            && cold.0.cacheURL == peek.0.cacheURL && controller.images.requestedSources.last == .pixiv,
            "real remote ready and async paths preserve the exact target and source/account transport")
        remote.pending[0].resume(returning: RouteCalls.image)
        await wait { remote.finished == 1 }
        check(delivered === RouteCalls.image, "current remote cold delivery reaches the original receiver")
        coldCancel?()
        delivered = nil
        let cancelled = binding(row(.pixiv, "cancelled:p0"), target) { delivered = $0 }
        await wait { remote.pending.count == 2 }
        cancelled?(); remote.pending[1].resume(returning: RouteCalls.image)
        await wait { remote.finished == 2 }
        check(remote.cancelled == 1 && delivered == nil, "cancelled Controller Task finishes the actual source without publishing late pixels")
        check(binding(row(.videoLibrary, "unhandled"), target) { _ in } == nil,
            "unhandled providers do not acquire an unrelated thumbnail lease")
        print("Download task thumbnail routes PASS \(checks)")
    }
}
'''
        controller = (ROOT / 'MyWallpaperX/App/DownloadTasksController.swift').read_text()
        models = (ROOT / 'MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift').read_text()
        remote = (ROOT / 'MyWallpaperX/Shared/UI/OnlineImageThumbnailPipeline.swift').read_text()
        decoder = (ROOT / 'MyWallpaperX/Shared/UI/GridThumbnailDecoder.swift').read_text()
        cache = (ROOT / 'MyWallpaperX/Shared/UI/ThumbnailCache.swift').read_text()
        steam = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewRequestCoordinator.swift').read_text()
        for marker, content in {
            '// ACTUAL_CONTROLLER_METHODS': '\n'.join(method(controller, signature) for signature in (
                '    func makePopoverController(', '    private func steamPreviewURL(',
                '    private func loadThumbnail(', '    private func loadRemoteThumbnail(')),
            '// ACTUAL_ONLINE_MODELS': '\n'.join(declaration(models, signature) for signature in (
                'nonisolated enum OnlineImageSource:', 'nonisolated struct OnlineImageAssetID:')),
            '// ACTUAL_REMOTE_REQUEST': declaration(remote, 'nonisolated struct OnlineImageThumbnailRequest:'),
            '// ACTUAL_PIXEL_LIMIT': method(decoder, '    static func pixelLimit('),
            '// ACTUAL_CANCELLATION_AND_PRIORITIES': '\n'.join([
                *(declaration(cache, signature) for signature in ('nonisolated protocol ThumbnailCacheLoadCancellation:',
                    'nonisolated final class ThumbnailCacheRequestCancellation:', 'nonisolated enum ThumbnailCacheRequestPriority:')),
                *(declaration(steam, signature) for signature in ('nonisolated final class SteamWorkshopPreviewLoadCancellation:',
                    'nonisolated enum SteamWorkshopPreviewRequestPriority:')),
                declaration(remote, 'nonisolated enum OnlineImageThumbnailRequestPriority:'),
            ]),
        }.items():
            self.assertEqual(harness.count(marker), 1)
            harness = harness.replace(marker, content)
        with tempfile.TemporaryDirectory(prefix='mwx-download-thumbnail-routes-', dir='/private/tmp') as directory:
            work = pathlib.Path(directory)
            sources = [ROOT / 'MyWallpaperX' / name for name in (
                'Models/WallpaperReference.swift', 'Models/DownloadTask.swift', 'Shared/ThumbnailRequest.swift',
                'Modules/Downloads/Core/DownloadTaskProjection.swift', 'Modules/Downloads/UI/DownloadTaskRowPresentation.swift',
                'Modules/Downloads/UI/DownloadTaskRowView.swift')]
            source = work / 'Harness.swift'; source.write_text(harness)
            binary = work / 'routes'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, sources), str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=90)
            run = self._run_fixture(binary, build, 'provider-routes', 15)
            self.assertIn('Download task thumbnail routes PASS', run.stdout)
