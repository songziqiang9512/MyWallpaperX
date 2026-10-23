@main enum PropertyPresentationChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let rawTitle = "<b>First paragraph</b><br/>Second paragraph<br/>作者中文标题<br/>完整的中文说明"
        let plainTitle = "First paragraph\nSecond paragraph\n作者中文标题\n完整的中文说明"
        precondition(WorkshopPropertyDisplayResolver.plainText(rawTitle) == plainTitle)
        precondition(WorkshopPropertyDisplayResolver.plainText("<script>bad()</script><p>中文&nbsp;&#x4e2d;&#25991;&lt;ok&gt;</p>") == "中文 中文<ok>")
        precondition(WorkshopPropertyDisplayResolver.plainText("<img src='https://invalid.example/a.png'>") == nil)
        precondition(WorkshopPropertyDisplayResolver.plainText("1 < 3 > 2") == "1 < 3 > 2")
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "rate": ["type": "slider", "text": rawTitle, "value": 1, "min": 0, "max": 2, "order": 0],
            "toggle": ["type": "bool", "text": "作者提供的较长开关名称和中文说明", "value": true, "order": 1],
            "mode": ["type": "combo", "text": rawTitle, "value": "raw-value", "order": 2,
                "options": [["label": String(repeating: "较长的中文选项", count: 8), "value": "raw-value"]]],
            "input": ["type": "textinput", "text": rawTitle, "value": "原始输入", "order": 3],
            "authorNote": ["text": rawTitle, "value": "retained", "order": 4],
            "decoration": ["type": "text", "text": "", "order": 5],
            "explicitMissing": ["type": "", "text": "显式空类型", "value": "old", "order": 6],
            "unknown": ["type": "futureType", "text": "作者未知控件", "value": "raw", "order": 7]
        ])
        precondition(catalog.definitions.first { $0.key == "authorNote" }?.kind == .text)
        precondition(catalog.definitions.first { $0.key == "explicitMissing" }?.kind == .unsupported)
        precondition(catalog.definitions.first { $0.key == "unknown" }?.kind == .unsupported)
        precondition(catalog.definitions.first { $0.key == "decoration" }?.title == "")
        precondition(catalog.defaultValues["authorNote"] == .string("retained"))
        let readOnlyContext = SteamWorkshopScenePropertyContext(catalog: catalog,
            actionableKeys: [], effectiveValues: catalog.defaultValues)
        precondition(readOnlyContext.definitions.contains { $0.key == "authorNote" },
            "an implicit authored note stays visible even without a runtime consumer")
        precondition(!readOnlyContext.hasEditorControls, "author notes cannot manufacture editable runtime controls")
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
        }
        for width: CGFloat in [324, 356, 480] {
            let context = SteamWorkshopScenePropertyContext(catalog: catalog,
                actionableKeys: Set(catalog.definitions.map(\.key)), effectiveValues: catalog.defaultValues)
            let editor = SteamWorkshopScenePropertyEditorView(record: .init(id: "own", title: "own"), context: context)
            let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: width, height: 560),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = editor; window.orderFront(nil)
            for _ in 0..<4 { RunLoop.main.run(until: Date().addingTimeInterval(0.008)); editor.layoutSubtreeIfNeeded() }
            let list = descendants(editor, NSCollectionView.self).first!
            let scroll = descendants(editor, NSScrollView.self).first!
            for style: NSScroller.Style in [.overlay, .legacy] {
                scroll.scrollerStyle = style
                for _ in 0..<4 { RunLoop.main.run(until: Date().addingTimeInterval(0.008)); editor.layoutSubtreeIfNeeded() }
                list.scrollToItems(at: [IndexPath(item: 1, section: 0)], scrollPosition: .centeredVertically)
                scroll.flashScrollers()
                editor.layoutSubtreeIfNeeded()
                precondition(scroll.verticalScroller?.isHidden == true, "Scene scrollbar must stay hidden after style, layout and flash")
                let toggle = descendants(list.item(at: IndexPath(item: 1, section: 0))!.view, NSButton.self).first!
                let point = toggle.convert(NSPoint(x: toggle.bounds.maxX - 2, y: toggle.bounds.midY), to: editor)
                precondition(editor.hitTest(point) === toggle, "checkbox trailing click area at width \(width), scroller style \(style)")
                let previousOrigin = scroll.contentView.bounds.origin.y
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                    wheel1: -80, wheel2: 0, wheel3: 0)!
                scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
                precondition(scroll.contentView.bounds.origin.y > previousOrigin, "wheel scrolling must work without a visible scrollbar")
                precondition(scroll.verticalScroller?.isHidden == true, "Scene wheel must not reveal a scrollbar")
            }
            precondition(list.numberOfItems(inSection: 0) == 7, "empty authored decoration must not become an identifier row")
            for row in 0..<7 {
                list.scrollToItems(at: [IndexPath(item: row, section: 0)], scrollPosition: .top)
                list.layoutSubtreeIfNeeded(); editor.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                let cell = list.item(at: IndexPath(item: row, section: 0))!.view
                let title = descendants(cell, NSTextField.self).first!
                if [0, 2, 3, 4].contains(row) {
                    precondition(title.stringValue == plainTitle, "later Chinese paragraphs must not be discarded")
                }
                for control in descendants(cell, NSControl.self) {
                    let frame = control.convert(control.bounds, to: cell)
                    precondition(frame.minX >= -1 && frame.maxX <= cell.bounds.width + 1, "control escaped narrow property row")
                    precondition(frame.minY >= -1 && frame.maxY <= cell.bounds.height + 1, "control clipped by row height")
                }
                if [0, 3].contains(row) {
                    let controls = descendants(cell, NSControl.self).filter { $0 !== title }
                    let titleRect = title.convert(title.bounds, to: cell)
                    precondition(controls.allSatisfy { $0.convert($0.bounds, to: cell).maxY <= titleRect.minY - 6 },
                        "complex controls must sit below the full-width author label")
                }
                if row == 2 {
                    let popup = descendants(cell, NSPopUpButton.self).first!
                    let frame = popup.convert(popup.bounds, to: cell)
                    precondition(abs(frame.midY - title.convert(title.bounds, to: cell).midY) < 1,
                        "choice must stay beside its full multiline title")
                }
            }
            window.contentView = nil; window.close()
        }
        print("property presentation PASS: complete author text, missing-type notes, native layout at three widths; checkbox hit areas and wheel scrolling with both scroller styles")
    }
}
