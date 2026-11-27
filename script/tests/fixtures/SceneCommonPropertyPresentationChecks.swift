import AppKit
import Combine

@MainActor final class WallpaperManager {
    static let shared = WallpaperManager()

    struct Settings {
        enum FillMode { case aspectFill, aspectFit }
        var videoFillMode: FillMode = .aspectFill
        var multiDisplayEnabled = true
    }

    @Published var settings = Settings()
}

@MainActor enum SceneCommonPropertyPresentationChecks {
    static func run() {
        _ = NSApplication.shared
        let service = SteamWorkshopService.shared
        var authorUpdates = 0
        let authorObserver = service.objectWillChange.sink { authorUpdates += 1 }
        defer { authorObserver.cancel() }
        let record = SteamWorkshopDownloadRecord(id: UUID().uuidString, title: "Scene A")
        let other = SteamWorkshopDownloadRecord(id: UUID().uuidString, title: "Scene B")
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "toneGate": ["type": "bool", "value": true, "order": 0],
            "schemecolor": ["type": "color", "value": "1 1 1", "condition": "toneGate.value", "order": 1],
        ])
        let screen = NSScreen.screens.first!.frame
        let context = SteamWorkshopScenePropertyContext(
            catalog: catalog, actionableKeys: ["schemecolor", "toneGate"], effectiveValues: catalog.defaultValues,
            canvasAspect: screen.width / screen.height * 0.7, supportsAudioProcessing: true,
            hasSound: true, supportsMouseParallax: true)
        let editor = SteamWorkshopScenePropertyEditorView(record: record, context: context)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
            _ = service.updateScenePresentation(for: record) { $0 = .init() }
            WallpaperManager.shared.settings.videoFillMode = .aspectFill
        }
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            if let result = view as? T, !result.isHiddenOrHasHiddenAncestor { return [result] }
            return view.subviews.flatMap { descendants($0, type) }
        }
        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.contentView!.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        func control<T: NSControl>(_ view: NSView, title: String, type: T.Type) -> T? {
            guard let row = descendants(view, WorkshopPropertyRowView.self).first(where: { $0.title.stringValue == title }),
                  let control = descendants(row.content, type).first else { return nil }
            let labelRect = row.title.convert(row.title.bounds, to: row)
            let controlRect = control.convert(control.bounds, to: row)
            precondition(labelRect.maxX < controlRect.minX && abs(labelRect.midY - controlRect.midY) < 2,
                "\(title) must position its label on the left and control on the right of one native row")
            if let checkbox = control as? NSButton, !(checkbox is NSPopUpButton) {
                precondition(checkbox.title.isEmpty, "checkbox label belongs in the native row title")
            }
            return control
        }
        func change(_ slider: NSSlider, to value: Int) {
            slider.integerValue = value
            slider.sendAction(slider.action, to: slider.target)
        }
        settle()
        let list = descendants(editor, NSCollectionView.self).first!
        let common = control(editor, title: String(localized: "Show Common Adjustments"), type: NSButton.self)!
        precondition(common.state == .off && descendants(editor, NSSlider.self).isEmpty && list.numberOfItems(inSection: 0) == 1,
            "opening the panel must collapse common controls and leave authored controls visible")
        common.performClick(nil)
        settle()
        precondition(common.state == .on, "the native disclosure did not toggle")
        guard let alignment = control(editor, title: String(localized: "Scene Framing"), type: NSPopUpButton.self) else {
            let viewport = list.enclosingScrollView?.contentView.bounds ?? .zero
            preconditionFailure("the expanded header must remain visible: \(String(describing: common.superview?.frame)), viewport \(viewport), items \(list.numberOfItems(inSection: 0))")
        }
        let zoom = control(editor, title: String(localized: "Camera Zoom"), type: NSSlider.self)!
        let rate = control(editor, title: String(localized: "Playback Speed"), type: NSSlider.self)!
        let listen = control(editor, title: String(localized: "Audio Listening"), type: NSButton.self)!
        let flip = control(editor, title: String(localized: "Flip Horizontally"), type: NSButton.self)!
        let parallax = control(editor, title: String(localized: "Mouse Parallax"), type: NSButton.self)!
        let volume = control(editor, title: String(localized: "Volume"), type: NSSlider.self)!
        precondition(list.numberOfItems(inSection: 0) == 2
            && descendants(list.item(at: IndexPath(item: 0, section: 0))!.view, NSColorWell.self).count == 1,
            "the bound theme color must be shown once, ahead of author rows")
        precondition(alignment.indexOfSelectedItem == 0 && listen.state == .on && zoom.integerValue == 100)
        precondition(alignment.numberOfItems == 6 && flip.state == .off && parallax.state == .on && volume.integerValue == 100)
        precondition(rate.minValue == 10 && rate.maxValue == 200 && rate.integerValue == 100)
        WallpaperManager.shared.settings.videoFillMode = .aspectFit
        settle()
        precondition(control(editor, title: String(localized: "Crop Position"), type: NSSlider.self) == nil,
            "inheriting full-canvas mode must hide the crop position")
        alignment.selectItem(withTitle: String(localized: "Cover Screen"))
        alignment.sendAction(alignment.action, to: alignment.target)
        settle()
        let crop = control(editor, title: String(localized: "Crop Position"), type: NSSlider.self)!
        precondition(crop.integerValue == 50, "work-level cover must override inherited fit for position")
        change(crop, to: 75)
        change(zoom, to: 125)
        change(rate, to: 150)
        listen.performClick(nil)
        flip.performClick(nil)
        parallax.performClick(nil)
        change(volume, to: 35)
        alignment.selectItem(withTitle: String(localized: "Free"))
        alignment.sendAction(alignment.action, to: alignment.target)
        settle()
        precondition(control(editor, title: String(localized: "Crop Position"), type: NSSlider.self) == nil)
        let horizontal = control(editor, title: String(localized: "Horizontal Position"), type: NSSlider.self)!
        let vertical = control(editor, title: String(localized: "Vertical Position"), type: NSSlider.self)!
        precondition(horizontal.integerValue == 50 && vertical.integerValue == 50)
        change(horizontal, to: 25)
        change(vertical, to: 65)
        alignment.selectItem(withTitle: String(localized: "Cover Screen"))
        alignment.sendAction(alignment.action, to: alignment.target)
        settle()
        precondition(control(editor, title: String(localized: "Horizontal Position"), type: NSSlider.self) == nil
            && control(editor, title: String(localized: "Vertical Position"), type: NSSlider.self) == nil)
        var expected = ScenePlaybackPresentation(alignment: .cover, position: 75, zoom: 125, listensToAudio: false)
        expected.flippedHorizontally = true
        expected.allowsMouseParallax = false
        expected.volume = 35
        expected.rate = 150
        expected.horizontalPosition = 25
        expected.verticalPosition = 65
        precondition(service.scenePresentation(for: record) == expected)
        precondition(authorUpdates == 0, "common controls must not broadcast an authored-property refresh")
        common.performClick(nil)
        settle()
        precondition(descendants(editor, NSSlider.self).isEmpty && list.numberOfItems(inSection: 0) == 1
            && service.scenePresentation(for: record) == expected,
            "collapsing must hide the controls and preserve the complete work value")
        common.performClick(nil)
        settle()
        precondition(crop.integerValue == 75 && zoom.integerValue == 125 && listen.state == .off
            && flip.state == .on && parallax.state == .off && volume.integerValue == 35 && rate.integerValue == 150)
        window.setContentSize(NSSize(width: 324, height: 620))
        settle()
        precondition(control(editor, title: String(localized: "Scene Framing"), type: NSPopUpButton.self) === alignment
            && control(editor, title: String(localized: "Show Common Adjustments"), type: NSButton.self) === common
            && control(editor, title: String(localized: "Playback Speed"), type: NSSlider.self) === rate
            && control(editor, title: String(localized: "Volume"), type: NSSlider.self) === volume
            && control(editor, title: String(localized: "Flip Horizontally"), type: NSButton.self) === flip,
            "the authored width contract must also lay out common controls in a narrow panel")
        window.setContentSize(NSSize(width: 324, height: 356))
        settle()
        let authorPath = IndexPath(item: 1, section: 0)
        let authorFrame = list.collectionViewLayout!.layoutAttributesForItem(at: authorPath)!.frame
        precondition(!list.visibleRect.contains(authorFrame), "the compact panel must require scrolling to reach author rows")
        list.scrollToItems(at: [authorPath], scrollPosition: .bottom)
        settle()
        precondition(list.visibleRect.contains(authorFrame), "author rows must remain reachable below expanded common controls")
        let authored = descendants(list.item(at: IndexPath(item: 1, section: 0))!.view, NSButton.self).first!
        authored.state = .off
        authored.sendAction(authored.action, to: authored.target)
        precondition(list.numberOfItems(inSection: 0) == 1, "expanded theme color must still honor its author condition")

        let empty = SteamWorkshopScenePropertyContext(catalog: .init(definitions: []),
            actionableKeys: [], effectiveValues: [:])
        let otherEditor = SteamWorkshopScenePropertyEditorView(record: other, context: empty)
        window.contentView = otherEditor
        settle()
        let otherDisclosure = control(otherEditor, title: String(localized: "Show Common Adjustments"), type: NSButton.self)!
        precondition(descendants(otherEditor, NSButton.self).contains { $0.title == String(localized: "Restore Defaults") }
            && otherDisclosure.state == .off, "a work without author controls still opens a collapsed common section with reset")
        otherDisclosure.performClick(nil)
        settle()
        precondition(control(otherEditor, title: String(localized: "Flip Horizontally"), type: NSButton.self)?.state == .off
            && control(otherEditor, title: String(localized: "Mouse Parallax"), type: NSButton.self) == nil
            && control(otherEditor, title: String(localized: "Volume"), type: NSSlider.self) == nil,
            "irrelevant controls must remain hidden for a work without a matching capability")
        precondition(service.scenePresentation(for: other) == .init()
            && service.scenePresentation(for: record) == expected,
            "a second work must keep independent common settings")
        window.contentView = editor
        settle()
        list.enclosingScrollView!.contentView.scroll(to: .zero)
        settle()
        descendants(editor, NSButton.self).first { $0.title == String(localized: "Restore Defaults") }!.performClick(nil)
        service.finishReset(.applied)
        settle()
        precondition(service.scenePresentation(for: record) == .init() && rate.integerValue == 100
            && volume.integerValue == 100 && flip.state == .off && parallax.state == .on
            && list.numberOfItems(inSection: 0) == 2, "one reset must restore the work and its author controls")
        print("native Scene common rows, crop precedence, theme condition, work identity and reset PASS")
    }
}
