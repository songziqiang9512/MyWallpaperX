import AppKit
import Combine

@MainActor enum MainWindowCoordinator { static func mainWindow() -> NSWindow? { NSApp.mainWindow } }
@MainActor private final class EditorModalObservation { var blocksBackground = false }
@MainActor private final class EditorCloseObservation { var willCloseNotifications = 0 }
@MainActor private final class EditorHostLifecycle: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

// One bounded actor queue hold delays the real cover read. No Store method,
// sheet action, metadata writer or image decoder is replaced.
extension UserCollectionsStore {
    func holdForEditorFixture(entered: DispatchSemaphore, release: DispatchSemaphore) {
        entered.signal(); release.wait()
    }
}

// Compiled in the original Editor file; this exercises its actual layout
// method without fabricating a Store or source failure with a special message.
extension WallpaperPlaylistEditorController {
    func nativeFixtureReport(_ message: String?) {
        if let message { report(message) } else { clearReport() }
    }
}

@main enum WallpaperPlaylistEditorHarness {
    @MainActor static func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, type) }
    }
    @MainActor static func settle() async { try? await Task.sleep(for: .milliseconds(35)) }
    @MainActor static func wait(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { await settle() }
        guard condition() else { throw NSError(domain: "EditorNativeFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func main() {
        initializeNativeAppHarness()
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run() } catch { fatalError("Real Editor fixture: \(error)") }
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: false) }
        }
        app.run()
    }
    @MainActor static func run() async throws {
        let app = NSApplication.shared, root = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = UserCollectionsStore(url: root.appendingPathComponent("editor.sqlite3"))
        let collections = UserCollectionsController(store: store, snapshot: try await store.snapshot())
        let host = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 1000, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false; host.center(); host.makeKeyAndOrderFront(nil); app.activate()
        defer { host.orderOut(nil); host.close() }
        try await wait("native host never became active/key") { app.isActive && host.isKeyWindow }
        let inputProbe = WallpaperModalInputProbe.install(in: host)
        let inputBefore = inputProbe.values
        try await inputProbe.deliver()
        let nativeInputWasLive = WallpaperModalInputProbe.hasOneDelivery(inputBefore, inputProbe.values)
        let sibling = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        sibling.isReleasedWhenClosed = false
        host.addChildWindow(sibling, ordered: .above); sibling.makeKeyAndOrderFront(nil)
        try await wait("native sibling input premise did not become key") { sibling.isKeyWindow }
        let siblingProbe = WallpaperModalInputProbe.install(in: sibling), siblingBefore = [0, 0, 0]
        try await siblingProbe.deliver()
        let siblingInputWasLive = WallpaperModalInputProbe.hasOneDelivery(siblingBefore, siblingProbe.values)
        host.makeKeyAndOrderFront(nil)
        try await wait("main host did not resume before Editor admission") { host.isKeyWindow }
        var checks: [String: Bool] = [:]
        var saved: [UUID] = [], closed = 0, canEdit = true
        var editors: [WallpaperPlaylistEditorController] = []
        let availability = PassthroughSubject<Void, Never>()
        let automatic = NSImage(size: NSSize(width: 24, height: 24))
        let tint = ListThumbnailTintSource()
        var tintLoads = 0
        tint.update(id: "original-main-first") { done in tintLoads += 1; done(automatic); return {} }
        let tintRevision = tint.request?.revision
        func button(_ panel: NSWindow, _ title: String) -> NSButton {
            descendants(panel.contentView!, NSButton.self).first { $0.title == title }!
        }
        func name(_ panel: NSWindow) -> NSTextField {
            descendants(panel.contentView!, NSTextField.self).first { $0.accessibilityLabel() == "播放列表名称" }!
        }
        func description(_ panel: NSWindow) -> NSTextView {
            descendants(panel.contentView!, NSTextView.self).first { $0.accessibilityLabel() == "播放列表描述，可选" }!
        }
        func preview(_ panel: NSWindow) -> NSImageView {
            descendants(panel.contentView!, NSImageView.self).first { $0.accessibilityLabel() == "播放列表封面" }!
        }
        func setName(_ panel: NSWindow, _ value: String) {
            let field = name(panel); field.stringValue = value
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        }
        func open(_ playlist: WallpaperPlaylist? = nil, members: [WallpaperOrganizationItem] = [], providesAutomaticPreview: Bool = true) async throws -> (WallpaperPlaylistEditorController, NSPanel) {
            let editor = WallpaperPlaylistEditorController(collections: collections, playlist: playlist, members: members,
                automaticImage: providesAutomaticPreview ? automatic : nil, permitsEditing: { canEdit },
                availabilityChanges: availability.eraseToAnyPublisher(), hostWindow: { host })
            editor.onClose = { closed += 1 }
            editor.onSaved = { saved.append($0) }
            editors.append(editor)
            editor.show()
            try await wait("real Editor child panel never became key") {
                host.childWindows?.contains { $0.delegate === editor && $0.isVisible && app.keyWindow === $0 } == true
            }
            let panel = host.childWindows!.first { $0.delegate === editor } as! NSPanel
            panel.contentView?.layoutSubtreeIfNeeded()
            return (editor, panel)
        }
        func cancel(_ panel: NSWindow) async throws {
            button(panel, "取消").performClick(nil)
            try await wait("Editor cancel did not retire its child panel") { !panel.isVisible && panel.parent == nil }
        }
        func current(_ id: UUID) -> WallpaperPlaylist { collections.snapshot.playlists.first { $0.id == id }! }
        func holdStore() async throws -> (Task<Void, Never>, DispatchSemaphore) {
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let task = Task { await store.holdForEditorFixture(entered: entered, release: release) }
            let didEnter: Bool = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: entered.wait(timeout: .now() + 3) == .success) }
            }
            guard didEnter else { release.signal(); throw CocoaError(.coderInvalidValue) }
            return (task, release)
        }

        let beforeDraft = collections.snapshot
        let nonKeyHost = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        checks["ordinary-focus-difference-does-not-become-a-modal-business-rejection"] = NSApp.keyWindow !== nonKeyHost
            && WallpaperLibrarySheetPresentation.permitsInput(in: nonKeyHost)
        let modalObservation = EditorModalObservation()
        let blockingFeedback = makeAppAlert(title: "模态输入边界")
        let feedbackTimer = Timer(timeInterval: 0.01, repeats: false) { _ in
            MainActor.assumeIsolated {
                modalObservation.blocksBackground = NSApp.modalWindow != nil && !WallpaperLibrarySheetPresentation.permitsInput(in: host)
                blockingFeedback.buttons[0].performClick(nil)
            }
        }
        RunLoop.main.add(feedbackTimer, forMode: .modalPanel)
        let modalResponse = runAppAlert(blockingFeedback)
        feedbackTimer.invalidate()
        checks["app-modal-feedback-blocks-background-input-without-changing-media-or-relationships"] = modalObservation.blocksBackground
            && modalResponse == .alertFirstButtonReturn && collections.snapshot == beforeDraft
        let orphan = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        checks["missing-main-host-never-falls-back-to-a-nonmodal-floating-draft"] = !WallpaperLibrarySheetPresentation.present(orphan, in: nil)
            && !orphan.isVisible && orphan.parent == nil
        let (draft, panel) = try await open()
        let beforeBlockedInput = inputProbe.values
        try await inputProbe.deliver()
        checks["editor-blocks-native-queue-background-click-drag-and-key-without-dimming-or-focus-polling"] = nativeInputWasLive
            && inputProbe.values == beforeBlockedInput && app.keyWindow === panel
            && !WallpaperLibrarySheetPresentation.permitsInput(in: host) && host.attachedSheet == nil
            && panel.isOpaque == false && panel.backgroundColor == .clear
            && host.childWindows?.filter({ $0 is WallpaperLibraryModalPanel && $0.isVisible }).count == 1
        let siblingBlockedBefore = siblingProbe.values
        try await siblingProbe.deliver()
        checks["editor-also-blocks-native-queue-click-drag-and-key-to-an-existing-nonmodal-sibling-child"] = siblingInputWasLive
            && siblingProbe.values == siblingBlockedBefore && app.keyWindow === panel && sibling.parent === host
            && !WallpaperLibrarySheetPresentation.permitsInput(in: sibling)
        sibling.close(); host.removeChildWindow(sibling)
        checks["editor-is-the-real-key-child-modal-with-original-native-controls"] = panel.delegate === draft && panel.parent === host && !panel.isSheet
            && panel.contentView is WallpaperLibrarySheetSurface && name(panel).isEditable && description(panel).isEditable
        let buttons = descendants(panel.contentView!, NSButton.self)
        checks["native-capsules-preserve-default-cancel-and-control-labels"] = ["完成", "取消", "选择封面…", "恢复自动封面"].allSatisfy { title in
            buttons.contains { $0.title == title && $0.bezelStyle == .glass && $0.controlSize == .large && $0.borderShape == .capsule && $0.isBordered }
        } && button(panel, "完成").keyEquivalent == "\r" && button(panel, "取消").keyEquivalent == "\u{1b}"
        let descriptionView = description(panel), descriptionClip = descriptionView.enclosingScrollView!.contentView
        let descriptionScroll = descriptionView.enclosingScrollView!
        let descriptionGeometry = "EditorNativeDescription documentFrame=\(descriptionView.frame), documentBounds=\(descriptionView.bounds), "
            + "clipFrame=\(descriptionClip.frame), clipBounds=\(descriptionClip.bounds), "
            + "contentSize=\(descriptionScroll.contentSize), scrollFrame=\(descriptionScroll.frame), "
            + "minSize=\(descriptionView.minSize), maxSize=\(descriptionView.maxSize), "
            + "textContainerSize=\(String(describing: descriptionView.textContainer?.containerSize)), "
            + "textInsets=\(descriptionView.textContainerInset), "
            + "widthTracksTextView=\(String(describing: descriptionView.textContainer?.widthTracksTextView)), "
            + "verticalResize=\(descriptionView.isVerticallyResizable), horizontalResize=\(descriptionView.isHorizontallyResizable), "
            + "autoresizingMask=\(descriptionView.autoresizingMask.rawValue)\n"
        FileHandle.standardError.write(Data(descriptionGeometry.utf8))
        checks["native-description-document-has-real-readable-width-and-height"] = descriptionView.frame.width > 300
            && abs(descriptionView.frame.width - descriptionClip.bounds.width) <= 1
            && descriptionView.frame.height >= descriptionClip.bounds.height
            && descriptionClip.bounds.height > 0 && descriptionClip.bounds.size == descriptionScroll.contentSize
            && descriptionScroll.frame.height == 60 && descriptionScroll.borderType == .bezelBorder
            && descriptionView.textContainer?.widthTracksTextView == true
        let body = panel.contentView!.subviews.compactMap { $0 as? NSStackView }.first!
        let rootBounds = panel.contentView!.bounds
        checks["editor-body-and-action-controls-fit-its-real-panel"] = body.fittingSize.height <= rootBounds.height - 31
            && [name(panel) as NSView, descriptionView.enclosingScrollView!, preview(panel), button(panel, "完成"), button(panel, "取消")].allSatisfy {
                rootBounds.contains($0.convert($0.bounds, to: panel.contentView))
            }
        checks["compact-music-editor-keeps-360-width-112-square-cover-without-a-520-height-floor"] = abs(rootBounds.width - 360) <= 0.5
            && rootBounds.height > 320 && rootBounds.height < 480
            && abs(rootBounds.height - body.fittingSize.height - 32) <= 0.5
            && abs(preview(panel).frame.width - 112) <= 0.5 && abs(preview(panel).frame.height - 112) <= 0.5
            && name(panel).font?.pointSize == 16
        let longFailure = Array(repeating: "完整失败说明可复制；请保留草稿，重新选择封面或稍后重试。", count: 20).joined(separator: "\n")
        draft.nativeFixtureReport(longFailure)
        panel.contentView?.layoutSubtreeIfNeeded()
        let failureField = descendants(panel.contentView!, NSTextField.self).first { $0.toolTip == longFailure }!
        let failureScroll = failureField.enclosingScrollView!
        checks["long-error-uses-real-scrollable-complete-text-with-visible-save-and-cancel"] = failureField.stringValue == longFailure
            && failureField.maximumNumberOfLines == 0 && failureField.isSelectable && failureScroll.hasVerticalScroller
            && failureField.frame.height > failureScroll.contentView.bounds.height && failureScroll.frame.height <= 120
            && [failureScroll as NSView, button(panel, "完成"), button(panel, "取消")].allSatisfy {
                panel.contentView!.bounds.contains($0.convert($0.bounds, to: panel.contentView))
            } && collections.snapshot == beforeDraft
        draft.nativeFixtureReport(nil)
        checks["clearing-an-error-removes-its-entire-reserved-space"] = failureScroll.isHidden && panel.contentView!.bounds.height < 480
        panel.makeFirstResponder(descriptionView)
        descriptionView.insertText("草稿描述\n第二行", replacementRange: NSRange(location: 0, length: descriptionView.string.utf16.count))
        checks["native-description-input-accepts-multiline-text"] = descriptionView.string == "草稿描述\n第二行"
        setName(panel, " \n ")
        checks["blank-name-disables-save-without-touching-sqlite"] = !button(panel, "完成").isEnabled && collections.snapshot == beforeDraft
        setName(panel, "中文 / 🎵")
        checks["name-is-human-text-without-filename-restrictions"] = button(panel, "完成").isEnabled
        button(panel, "选择封面…").performClick(nil)
        try await wait("native image chooser did not open") { panel.attachedSheet is NSOpenPanel }
        let chooser = panel.attachedSheet as! NSOpenPanel
        let beforeNested = collections.snapshot, savedBeforeNested = saved.count
        button(panel, "完成").performClick(nil)
        button(panel, "恢复自动封面").performClick(nil)
        button(panel, "取消").performClick(nil)
        checks["nested-native-file-chooser-revokes-held-editor-actions-without-changing-the-draft-or-store"] = panel.attachedSheet === chooser
            && panel.isVisible && collections.snapshot == beforeNested && saved.count == savedBeforeNested
            && preview(panel).image === automatic && !WallpaperLibrarySheetPresentation.permitsInput(in: panel)
            && !WallpaperLibrarySheetPresentation.permitsInput(in: host)
        checks["cover-choice-uses-one-native-image-file-without-directory-selection"] = chooser.allowedContentTypes == [.image]
            && !chooser.allowsMultipleSelection && chooser.canChooseFiles && !chooser.canChooseDirectories
        chooser.cancel(nil)
        try await wait("native image chooser cancel did not settle") { panel.attachedSheet == nil }
        checks["cancelled-cover-choice-never-writes-draft-or-store"] = collections.snapshot == beforeDraft && preview(panel).image === automatic
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        let handledEscape = panel.performKeyEquivalent(with: escape)
        try await wait("native Escape did not cancel Editor") { !panel.isVisible }
        checks["native-escape-cancels-the-entire-draft-without-save-or-ghost-list"] = handledEscape && saved.isEmpty && closed == 1
            && collections.snapshot == beforeDraft && panel.parent == nil
        host.makeKeyAndOrderFront(nil)
        try await wait("main input did not return after Editor close") { host.isKeyWindow }
        let afterEditorClose = inputProbe.values
        try await inputProbe.deliver()
        checks["editor-close-removes-its-event-monitor-and-restores-native-queue-main-click-drag-and-key"] = WallpaperModalInputProbe.hasOneDelivery(afterEditorClose, inputProbe.values)

        let (closingDraft, closingPanel) = try await open()
        setName(closingPanel, "关闭按钮只丢弃草稿")
        let beforeWindowClose = collections.snapshot, closedBeforeWindowClose = closed
        let closeObservation = EditorCloseObservation()
        let nativeCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
            object: closingPanel, queue: .main) { _ in
                MainActor.assumeIsolated { closeObservation.willCloseNotifications += 1 }
            }
        defer { NotificationCenter.default.removeObserver(nativeCloseObserver) }
        func recordCloseState(_ phase: String) {
            let closeButton = closingPanel.standardWindowButton(.closeButton)
            let saving = Mirror(reflecting: closingDraft).children.first { $0.label == "isSaving" }?.value as? Bool
            let facts = "EditorNativeClose \(phase): style=\(closingPanel.styleMask.rawValue), isSheet=\(closingPanel.isSheet), "
                + "visible=\(closingPanel.isVisible), key=\(app.keyWindow === closingPanel), "
                + "parentIsHost=\(closingPanel.parent === host), hostAttached=\(host.childWindows?.contains(closingPanel) == true), "
                + "delegateIsDraft=\(closingPanel.delegate === closingDraft), "
                + "closeButtonPresent=\(closeButton != nil), closeEnabled=\(String(describing: closeButton?.isEnabled)), "
                + "closeHidden=\(String(describing: closeButton?.isHidden)), "
                + "permitsInput=\(WallpaperLibrarySheetPresentation.permitsInput(in: closingPanel)), "
                + "saving=\(String(describing: saving)), doneEnabled=\(button(closingPanel, "完成").isEnabled), "
                + "nested=\(String(describing: closingPanel.attachedSheet?.windowNumber)), "
                + "modal=\(String(describing: app.modalWindow?.windowNumber)), "
                + "closedDelta=\(closed - closedBeforeWindowClose), willCloseNotifications=\(closeObservation.willCloseNotifications)\n"
            FileHandle.standardError.write(Data(facts.utf8))
        }
        recordCloseState("before-performClose")
        closingPanel.performClose(nil)
        recordCloseState("after-performClose-return")
        checks["borderless-modal-close-command-retires-the-native-child-without-writing-the-draft"] = closingPanel.standardWindowButton(.closeButton) == nil
            && closingPanel.parent == nil && !closingPanel.isVisible
            && closed == closedBeforeWindowClose + 1 && collections.snapshot == beforeWindowClose && saved.isEmpty
        button(closingPanel, "取消").performClick(nil)
        do {
            try await wait("native close did not retire the Editor") { closingPanel.parent == nil && !closingPanel.isVisible }
        } catch {
            recordCloseState("after-native-close-wait-failed")
            throw error
        }
        recordCloseState("after-native-close-settled")
        closingDraft.close(); closingPanel.performClose(nil); await settle()
        checks["native-editor-close-then-cancel-uses-one-owner-completion-without-writing-the-draft"] = closed == closedBeforeWindowClose + 1
            && closeObservation.willCloseNotifications == 1
            && collections.snapshot == beforeWindowClose && closingPanel.parent == nil && saved.isEmpty

        let lifecycle = EditorHostLifecycle()
        let (hostClosedDraft, hostClosedPanel) = try await open()
        setName(hostClosedPanel, "主窗关闭不能保存此草稿")
        button(hostClosedPanel, "选择封面…").performClick(nil)
        try await wait("nested chooser never opened for host-close lifecycle") {
            hostClosedPanel.attachedSheet is NSOpenPanel && hostClosedPanel.attachedSheet?.isVisible == true
                && NSApp.keyWindow === hostClosedPanel.attachedSheet
        }
        let hostClosedChooser = hostClosedPanel.attachedSheet as! NSOpenPanel
        hostClosedPanel.performClose(nil)
        checks["native-close-on-a-parent-editor-cannot-bypass-its-current-file-chooser"] = hostClosedPanel.attachedSheet === hostClosedChooser
            && hostClosedPanel.isVisible && hostClosedChooser.isVisible
        let beforeHostClose = collections.snapshot, closedBeforeHostClose = closed
        lifecycle.onClose = { hostClosedDraft.close() }
        host.delegate = lifecycle
        host.close()
        try await wait("host-close lifecycle left an Editor or file chooser floating") {
            !hostClosedPanel.isVisible && !hostClosedChooser.isVisible && hostClosedPanel.parent == nil && hostClosedPanel.attachedSheet == nil
        }
        hostClosedDraft.close(); await settle()
        checks["host-close-retires-editor-and-nested-chooser-once-with-no-unsaved-metadata"] = closed == closedBeforeHostClose + 1
            && collections.snapshot == beforeHostClose && saved.isEmpty
        host.delegate = nil; lifecycle.onClose = nil
        host.makeKeyAndOrderFront(nil)
        try await wait("host did not reopen after the lifecycle check") { host.isKeyWindow }

        let member = WallpaperOrganizationItem(reference: .init(provider: .staticImageLibrary, sourceID: "captured-member"),
            locator: .init(path: root.appendingPathComponent("untouched-media.bin").path, mediaKind: .image), isPublishedLocally: true, isAvailable: true)
        let media = Data([1, 2, 3, 4]); try media.write(to: URL(fileURLWithPath: member.locator.path!))
        let (creator, createPanel) = try await open(members: [member])
        setName(createPanel, "  固定创建 🎵  "); description(createPanel).string = "  描述正文\n第二行  "
        let beforeCreateRevision = collections.snapshot.revision
        let (saveHold, saveRelease) = try await holdStore()
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: createPanel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        let handledReturn = createPanel.performKeyEquivalent(with: enter)
        button(createPanel, "取消").performClick(nil)
        checks["native-return-admits-save-and-disables-reentry-until-its-one-transaction-settles"] = handledReturn && !button(createPanel, "完成").isEnabled
            && createPanel.isVisible && !creator.windowShouldClose(createPanel)
        saveRelease.signal(); await saveHold.value
        try await wait("native Save did not commit and close") { saved.count == 1 && !createPanel.isVisible }
        let id = saved[0], created = current(saved[0])
        checks["native-save-commits-trimmed-metadata-and-fixed-members-in-one-revision"] = created.name == "固定创建 🎵"
            && created.descriptionText == "描述正文\n第二行" && created.customCoverAssetID == nil
            && collections.snapshot.revision == beforeCreateRevision + 1 && collections.snapshot.members.map(\.reference) == [member.reference]
        checks["metadata-save-does-not-write-the-original-media-file"] = try Data(contentsOf: URL(fileURLWithPath: member.locator.path!)) == media
        let reopenedStore = UserCollectionsStore(url: root.appendingPathComponent("editor.sqlite3"), allowCreate: false)
        checks["editor-success-is-durable-in-the-real-store"] = try await reopenedStore.snapshot() == collections.snapshot

        let source = root.appendingPathComponent("original-cover.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData!.initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let sourceBytes = bitmap.representation(using: .png, properties: [:])!; try sourceBytes.write(to: source)
        let asset = try PlaylistCoverPreparation.prepare(source)
        let originalAfterPreparation = try Data(contentsOf: source)
        checks["production-image-preparer-owns-a-bounded-normalized-copy"] = asset.pixelWidth == 512 && asset.pixelHeight == 256
            && !asset.imageData.isEmpty && NSImage(data: asset.imageData) != nil && asset.imageData != sourceBytes
            && originalAfterPreparation == sourceBytes
        let corrupt = root.appendingPathComponent("corrupt-cover.png"); try Data([0, 1, 2]).write(to: corrupt)
        do { _ = try PlaylistCoverPreparation.prepare(corrupt); checks["production-image-preparer-rejects-corrupt-input-without-store-write"] = false }
        catch { checks["production-image-preparer-rejects-corrupt-input-without-store-write"] = current(id) == created }
        _ = try await collections.editPlaylistMetadata(id: id, expected: created.metadata,
            replacement: .init(name: created.name, descriptionText: created.descriptionText, customCoverAssetID: asset.id),
            coverAsset: asset, expectedEpoch: collections.snapshot.resetEpoch)
        try FileManager.default.removeItem(at: source)
        let covered = current(id)
        let (_, coverPanel) = try await open(covered)
        try await wait("owned custom cover never loaded after external source removal") { preview(coverPanel).image !== automatic }
        checks["native-editor-loads-owned-cover-after-original-file-is-gone"] = !FileManager.default.fileExists(atPath: source.path)
            && preview(coverPanel).image != nil && preview(coverPanel).contentTintColor == nil
            && button(coverPanel, "恢复自动封面").isEnabled
        let beforeCoverCancel = collections.snapshot
        button(coverPanel, "恢复自动封面").performClick(nil)
        checks["automatic-cover-is-only-a-draft-until-save"] = preview(coverPanel).image === automatic
            && !button(coverPanel, "恢复自动封面").isEnabled && collections.snapshot == beforeCoverCancel
        try await cancel(coverPanel)
        let assetAfterCancel = try await collections.playlistCoverAsset(id: asset.id, expectedEpoch: collections.snapshot.resetEpoch)
        checks["cancelled-automatic-cover-keeps-original-metadata-and-owned-bytes"] = collections.snapshot == beforeCoverCancel
            && assetAfterCancel == asset

        let (_, noAutomaticPanel) = try await open(current(id), providesAutomaticPreview: false)
        try await wait("custom cover without an automatic preview never loaded") { preview(noAutomaticPanel).contentTintColor == nil }
        let oldCustomImage = preview(noAutomaticPanel).image
        let beforeNoAutomatic = collections.snapshot
        button(noAutomaticPanel, "恢复自动封面").performClick(nil)
        let nativeMediaPixels = NSImage(systemSymbolName: WallpaperLibrarySymbols.playlist, accessibilityDescription: nil)?.tiffRepresentation
        let placeholderPixels = preview(noAutomaticPanel).image?.tiffRepresentation
        checks["automatic-reset-without-real-preview-removes-old-custom-pixels-and-shows-an-honest-placeholder"] = oldCustomImage != nil
            && preview(noAutomaticPanel).image !== oldCustomImage && nativeMediaPixels != nil && placeholderPixels == nativeMediaPixels
            && placeholderPixels != oldCustomImage?.tiffRepresentation
            && descendants(noAutomaticPanel.contentView!, NSTextField.self).contains {
                !$0.isHidden && $0.textColor == .secondaryLabelColor && $0.stringValue.contains("自动") && $0.stringValue.contains("保存")
            } && collections.snapshot == beforeNoAutomatic
        try await cancel(noAutomaticPanel)
        let assetAfterNoAutomatic = try await collections.playlistCoverAsset(id: asset.id, expectedEpoch: collections.snapshot.resetEpoch)
        checks["cancelled-automatic-reset-without-preview-keeps-owned-custom-asset-and-metadata"] = collections.snapshot == beforeNoAutomatic
            && assetAfterNoAutomatic == asset

        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let hold = Task { await store.holdForEditorFixture(entered: entered, release: release) }
        let didEnter: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: entered.wait(timeout: .now() + 3) == .success) }
        }
        guard didEnter else { throw CocoaError(.coderInvalidValue) }
        let (_, delayedPanel) = try await open(current(id))
        button(delayedPanel, "恢复自动封面").performClick(nil)
        release.signal(); await hold.value
        _ = try await store.snapshot(); await settle()
        checks["late-real-custom-cover-read-cannot-overwrite-automatic-draft"] = preview(delayedPanel).image === automatic
            && !button(delayedPanel, "恢复自动封面").isEnabled && current(id).customCoverAssetID == asset.id
        description(delayedPanel).string = " \n "
        button(delayedPanel, "完成").performClick(nil)
        try await wait("automatic-cover save did not finish") { !delayedPanel.isVisible }
        checks["saving-automatic-and-empty-description-clears-only-those-metadata-fields"] = current(id).customCoverAssetID == nil
            && current(id).descriptionText == nil && current(id).id == id && current(id).name == created.name
            && collections.snapshot.members.map(\.reference) == [member.reference]

        let (_, conflictPanel) = try await open(current(id))
        setName(conflictPanel, "旧草稿")
        let concurrentMetadata = current(id).metadata
        var concurrentReplacement = concurrentMetadata; concurrentReplacement.name = "另一个已提交名称"
        _ = try await collections.perform(.editPlaylistMetadata(id: id, expected: concurrentMetadata,
            replacement: concurrentReplacement, coverAsset: nil, at: Date()))
        let beforeConflict = collections.snapshot, savedBeforeConflict = saved.count
        button(conflictPanel, "完成").performClick(nil)
        try await wait("metadata conflict did not restore editable native sheet") { button(conflictPanel, "完成").isEnabled }
        checks["concurrent-metadata-edit-refuses-overwrite-and-keeps-the-users-draft"] = collections.snapshot == beforeConflict
            && saved.count == savedBeforeConflict && conflictPanel.isVisible && name(conflictPanel).stringValue == "旧草稿"
            && descendants(conflictPanel.contentView!, NSTextField.self).contains { !$0.isHidden && $0.textColor == .systemRed && !$0.stringValue.isEmpty }
        conflictPanel.contentView?.layoutSubtreeIfNeeded()
        let conflictBody = conflictPanel.contentView!.subviews.compactMap { $0 as? NSStackView }.first!
        checks["visible-metadata-error-keeps-save-cancel-and-draft-fields-within-native-panel"] = conflictBody.fittingSize.height <= conflictPanel.contentView!.bounds.height - 31
            && [name(conflictPanel) as NSView, description(conflictPanel).enclosingScrollView!, button(conflictPanel, "完成"), button(conflictPanel, "取消")].allSatisfy {
                conflictPanel.contentView!.bounds.contains($0.convert($0.bounds, to: conflictPanel.contentView))
            }
        try await cancel(conflictPanel)

        let (_, policyPanel) = try await open(current(id))
        setName(policyPanel, "不得在只读时保存")
        let beforePolicy = collections.snapshot, savedBeforePolicy = saved.count
        canEdit = false; availability.send()
        button(policyPanel, "完成").performClick(nil)
        let heldSave = button(policyPanel, "完成")
        _ = app.sendAction(heldSave.action!, to: heldSave.target, from: heldSave)
        await settle()
        checks["late-readonly-policy-revokes-native-save-cover-choice-and-held-click-without-store-write"] = !button(policyPanel, "完成").isEnabled
            && !button(policyPanel, "选择封面…").isEnabled
            && collections.snapshot == beforePolicy && saved.count == savedBeforePolicy && policyPanel.isVisible
        canEdit = true; availability.send(); await settle()
        checks["same-sheet-edit-policy-restores-without-a-catalog-or-snapshot-publish"] = button(policyPanel, "完成").isEnabled
            && button(policyPanel, "选择封面…").isEnabled
            && collections.snapshot == beforePolicy && name(policyPanel).stringValue == "不得在只读时保存"
        try await cancel(policyPanel)

        let (_, deletedPanel) = try await open(current(id))
        let deletedSavedCount = saved.count
        _ = try await collections.perform(.deletePlaylist(id)); await settle()
        button(deletedPanel, "完成").performClick(nil)
        let deletedSave = button(deletedPanel, "完成")
        _ = app.sendAction(deletedSave.action!, to: deletedSave.target, from: deletedSave)
        await settle()
        checks["deleted-fixed-target-cannot-be-recreated-by-an-old-editor"] = !button(deletedPanel, "完成").isEnabled
            && collections.snapshot.playlists.isEmpty && saved.count == deletedSavedCount
        try await cancel(deletedPanel)
        let (_, resetPanel) = try await open()
        let resetSavedCount = saved.count
        try await collections.reset(); await settle()
        button(resetPanel, "完成").performClick(nil)
        let resetSave = button(resetPanel, "完成")
        _ = app.sendAction(resetSave.action!, to: resetSave.target, from: resetSave)
        await settle()
        checks["reset-revokes-new-editor-draft-and-leaves-cancel-usable"] = !button(resetPanel, "完成").isEnabled
            && collections.snapshot.playlists.isEmpty && saved.count == resetSavedCount
        try await cancel(resetPanel)
        var acceptedReset = false
        var committedReset: Task<Void, Error>?
        let resetOnCommit = collections.$snapshot.sink { snapshot in
            if !acceptedReset, snapshot.playlists.contains(where: { $0.name == "Editor commit then reset" }) {
                acceptedReset = true
                committedReset = Task { @MainActor in try await collections.reset() }
            }
        }
        let (_, racingPanel) = try await open()
        let savedBeforeRace = saved.count, closedBeforeRace = closed
        setName(racingPanel, "Editor commit then reset")
        button(racingPanel, "完成").performClick(nil)
        try await wait("commit-triggered reset did not settle") { acceptedReset && !collections.isResetting && collections.snapshot.playlists.isEmpty }
        try await committedReset!.value
        try await wait("reset-invalidated successful save left its sheet stuck") { !racingPanel.isVisible }
        checks["reset-between-real-commit-and-editor-continuation-suppresses-save-and-closes-once"] = saved.count == savedBeforeRace
            && closed == closedBeforeRace + 1 && racingPanel.parent == nil && collections.snapshot.playlists.isEmpty
        resetOnCommit.cancel()

        let (admittedEditor, admittedPanel) = try await open()
        setName(admittedPanel, "已接纳保存关闭后仍结算")
        let (admittedHold, admittedRelease) = try await holdStore()
        let savedBeforeAdmittedClose = saved.count, closedBeforeAdmittedClose = closed
        button(admittedPanel, "完成").performClick(nil)
        await settle()
        checks["an-admitted-save-remains-noncancellable-by-the-native-editor-close-button"] = !button(admittedPanel, "完成").isEnabled
            && !admittedEditor.windowShouldClose(admittedPanel) && admittedPanel.isVisible
        lifecycle.onClose = { admittedEditor.close() }; host.delegate = lifecycle
        host.close()
        try await wait("host close did not retire a saving Editor's UI") { !admittedPanel.isVisible && admittedPanel.parent == nil }
        admittedRelease.signal(); await admittedHold.value
        _ = await collections.flush()
        try await wait("the admitted Store save was lost when its host closed") {
            collections.snapshot.playlists.contains { $0.name == "已接纳保存关闭后仍结算" }
        }
        admittedEditor.close(); await settle()
        checks["host-close-keeps-admitted-store-save-but-suppresses-late-editor-navigation-and-double-close"] = saved.count == savedBeforeAdmittedClose
            && closed == closedBeforeAdmittedClose + 1 && !admittedPanel.isVisible
        host.delegate = nil; lifecycle.onClose = nil
        host.makeKeyAndOrderFront(nil)
        try await wait("main host did not reopen for same-turn admission") { host.isKeyWindow }
        var sameTurnEditor: WallpaperPlaylistEditorController? = WallpaperPlaylistEditorController(collections: collections,
            playlist: nil, automaticImage: automatic, hostWindow: { host })
        weak let releasedEditor = sameTurnEditor
        var sameTurnCloses = 0, sameTurnNavigations = 0
        sameTurnEditor?.onClose = { sameTurnCloses += 1; sameTurnEditor = nil }
        sameTurnEditor?.onSaved = { _ in sameTurnNavigations += 1 }
        sameTurnEditor?.show()
        try await wait("same-turn Editor did not become a real child") { host.childWindows?.contains { $0.delegate === sameTurnEditor && $0.isKeyWindow } == true }
        let sameTurnPanel = host.childWindows!.first { $0.delegate === sameTurnEditor }!
        setName(sameTurnPanel, "同turn已准入保存不丢失")
        let beforeSameTurnSave = collections.snapshot
        button(sameTurnPanel, "完成").performClick(nil)
        // Intentionally no await or run-loop pump between admission and close.
        // onClose releases the sole UI owner; only the accepted work may retain it.
        host.close()
        checks["same-turn-host-close-releases-the-only-ui-owner-but-retains-admitted-work"] = sameTurnEditor == nil && releasedEditor != nil
            && sameTurnCloses == 1 && sameTurnNavigations == 0 && sameTurnPanel.parent == nil && !sameTurnPanel.isVisible
        try await wait("same-turn accepted save was dropped before entering the real Store") {
            collections.snapshot.playlists.contains { $0.name == "同turn已准入保存不丢失" }
        }
        _ = await collections.flush()
        try await wait("accepted Editor work did not release after its one result") { releasedEditor == nil }
        let sameTurnReopened = UserCollectionsStore(url: root.appendingPathComponent("editor.sqlite3"), allowCreate: false)
        let sameTurnDurable = try await sameTurnReopened.snapshot()
        checks["same-turn-close-still-commits-once-durably-without-late-navigation-or-editor-retention"] = collections.snapshot.revision == beforeSameTurnSave.revision + 1
            && collections.snapshot.playlists.count == beforeSameTurnSave.playlists.count + 1
            && sameTurnDurable == collections.snapshot && sameTurnCloses == 1 && sameTurnNavigations == 0 && releasedEditor == nil
        checks["sheet-material-never-observes-or-changes-the-original-main-tint-identity"] = tint.request?.revision == tintRevision
            && tint.request?.identity.itemID == "original-main-first" && tintLoads == 0
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
