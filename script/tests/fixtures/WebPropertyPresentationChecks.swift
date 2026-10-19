@main enum WebPropertyPresentationChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let service = SteamWorkshopService.shared
        let raw = "<b>First line</b><br/>Second line<br/>作者中文标题<br/>完整的中文说明"
        let text = WorkshopPropertyDisplayResolver.plainText(raw)!
        let labels = ["toggle", "rate", "color", "mode", "input", "note"]
        let kinds: [SteamWorkshopWebPropertyKind] = [.toggle, .slider, .color, .combo, .text, .label]
        let values: [SteamWorkshopWebPropertyValue] = [.bool(true), .number(0.5), .string("0.1 0.2 0.3"), .string("A"), .string("raw text"), .string("")]
        let sceneTypes = ["bool", "slider", "color", "combo", "textinput", "text"]
        let sceneValues: [Any] = [true, 0.5, "0.1 0.2 0.3", "A", "raw text", ""]
        let optionText = String(repeating: "长选项 Long option ", count: 4)
        let options = ["A", "B"].map { value in
            var option = SteamWorkshopWebPropertyOption(label: "ui_close", value: .string(value), displayCondition: nil)
            option.displayLabel = optionText
            return option
        }
        let definitions = labels.indices.map { index in
            var definition = SteamWorkshopWebPropertyDefinition(key: labels[index], title: "Legacy / summary",
                kind: kinds[index], runtimeType: sceneTypes[index], order: index, minimumValue: 0, maximumValue: 1,
                allowsFractionalValues: true, fractionalPrecision: 2, displayCondition: nil,
                directoryMode: nil, fileType: nil, defaultValue: values[index], options: index == 3 ? options : [])
            definition.displayTitle = text
            return definition
        }
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: Dictionary(uniqueKeysWithValues: labels.indices.map {
            (labels[$0], ["type": sceneTypes[$0], "text": raw, "value": sceneValues[$0],
                "order": $0, "min": 0, "max": 1, "precision": 2,
                "options": [["label": optionText, "value": "A"], ["label": optionText, "value": "B"]]] as [String: Any])
        }))
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
        }
        func settle(_ view: NSView) {
            for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.008)); view.layoutSubtreeIfNeeded() }
        }
        for width: CGFloat in [324, 356, 480] {
            service.webDescriptor = .init(propertyDefinitions: definitions)
            service.webValues = Dictionary(uniqueKeysWithValues: zip(labels, values))
            service.webEvents = []; service.webPreviews = []
            let web = SteamWorkshopWebPropertyEditorView(record: .init(id: "web", title: "web"))
            let scene = SteamWorkshopScenePropertyEditorView(record: .init(id: "scene", title: "scene"),
                context: .init(catalog: catalog, actionableKeys: Set(labels), effectiveValues: catalog.defaultValues))
            let windows = [web, scene].map { view in
                let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: width, height: 560),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = view
                view.widthAnchor.constraint(equalToConstant: width).isActive = true
                window.orderFront(nil); settle(view)
                return window
            }
            let webScroll = descendants(web, NSScrollView.self).first!
            let sceneScroll = descendants(scene, NSScrollView.self).first!
            precondition(webScroll.frame == sceneScroll.frame && webScroll.frame == web.bounds,
                "both content viewports must fill the editor without fixed reset chrome")
            let sceneList = descendants(scene, NSCollectionView.self).first!
            let webRows = descendants(web, WorkshopPropertyRowView.self)
            precondition(webRows.count == labels.count)
            for row in labels.indices {
                sceneList.scrollToItems(at: [IndexPath(item: row, section: 0)], scrollPosition: .top)
                scene.layoutSubtreeIfNeeded(); settle(scene)
                let sceneRow = descendants(sceneList.item(at: IndexPath(item: row, section: 0))!.view, WorkshopPropertyRowView.self).first!
                precondition(webRows[row].title.stringValue == text && sceneRow.title.stringValue == text)
                precondition(webRows[row].style == sceneRow.style && webRows[row].title.font == sceneRow.title.font)
                precondition(abs(webRows[row].bounds.height - sceneRow.bounds.height) < 1, "same title/type must have the same row height")
                if row == 3 {
                    for choiceRow in [webRows[row], sceneRow] {
                        let popup = descendants(choiceRow, NSPopUpButton.self).first!
                        precondition(choiceRow.style == .choice)
                        precondition(abs(choiceRow.content.frame.maxX - (choiceRow.bounds.width - 4)) < 1,
                            "choice must share the trailing control edge")
                        precondition(choiceRow.content.bounds.width <= min(180, (width - 8) / 2) + 1)
                        let titleRect = choiceRow.title.alignmentRect(forFrame: choiceRow.title.frame)
                        precondition(titleRect.maxX + 11 <= choiceRow.content.frame.minX,
                            "long choice titles must wrap beside the menu, never overlap: \(choiceRow.title.frame) \(choiceRow.content.frame)")
                        let popupFrame = popup.convert(popup.bounds, to: choiceRow)
                        precondition(abs(popupFrame.midY - choiceRow.title.frame.midY) < 1,
                            "choice and title must remain on the same row")
                        precondition(popup.lineBreakMode == .byTruncatingTail)
                    }
                }
                let webControls = descendants(webRows[row], NSControl.self)
                let sceneControls = descendants(sceneRow, NSControl.self)
                precondition(webControls.count == sceneControls.count, "same property kind must expose the same native controls")
                for (webControl, sceneControl) in zip(webControls, sceneControls) {
                    let a = webControl.convert(webControl.bounds, to: webRows[row])
                    let b = sceneControl.convert(sceneControl.bounds, to: sceneRow)
                    precondition(abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1
                        && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1, "native control geometry must match")
                }
                for control in descendants(webRows[row], NSControl.self) {
                    let frame = control.convert(control.bounds, to: webRows[row])
                    precondition(frame.minX >= -1 && frame.maxX <= width + 1 && frame.minY >= -1
                        && frame.maxY <= webRows[row].bounds.height + 1, "Web property control clipped")
                }
            }
            let reset = descendants(web, NSButton.self).first { $0.title == "恢复默认" }!
            precondition(reset.isDescendant(of: webScroll.documentView!))
            for style: NSScroller.Style in [.overlay, .legacy] {
                webScroll.scrollerStyle = style; settle(web)
                webScroll.contentView.scroll(to: .zero); webScroll.flashScrollers(); settle(web)
                let resetFrame = reset.convert(reset.bounds, to: web)
                let toggle = descendants(webRows[0], NSButton.self).first!
                let point = toggle.convert(NSPoint(x: toggle.bounds.maxX - 2, y: toggle.bounds.midY), to: web)
                precondition(web.hitTest(point) === toggle, "Web checkbox must not hit the scrollbar")
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0)!
                webScroll.scrollWheel(with: NSEvent(cgEvent: event)!)
                precondition(webScroll.contentView.bounds.origin.y > 0)
                precondition(reset.convert(reset.bounds, to: web) != resetFrame, "reset must scroll with its content")
                sceneScroll.scrollerStyle = style
                sceneScroll.contentView.scroll(to: .zero); settle(scene)
                let sceneReset = descendants(scene, NSButton.self).first { $0.title == "恢复默认" }!
                precondition(sceneReset.isDescendant(of: sceneScroll.documentView!))
                let sceneResetFrame = sceneReset.convert(sceneReset.bounds, to: scene)
                let sceneEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -100, wheel2: 0, wheel3: 0)!
                sceneScroll.scrollWheel(with: NSEvent(cgEvent: sceneEvent)!); settle(scene)
                precondition(!sceneReset.isDescendant(of: scene)
                    || sceneReset.convert(sceneReset.bounds, to: scene) != sceneResetFrame,
                    "Scene reset must also leave its original viewport position")
                sceneScroll.contentView.scroll(to: .zero); settle(scene)
                precondition(descendants(scene, NSButton.self).filter { $0.title == "恢复默认" }.count == 1)
            }
            let popup = descendants(web, NSPopUpButton.self).first!
            precondition(popup.itemArray.map(\.title) == Array(repeating: optionText, count: 2))
            popup.selectItem(at: 1); popup.sendAction(popup.action, to: popup.target)
            precondition(service.webEvents.last?.0 == "mode" && service.webEvents.last?.1 == .string("B"), "translated duplicate labels must keep distinct original values")
            settle(web)
            let well = descendants(web, NSColorWell.self).first!
            well.color = NSColor(deviceRed: 0.4, green: 0.5, blue: 0.6, alpha: 1)
            well.sendAction(well.action, to: well.target)
            precondition(service.webPreviews.last?.0 == "color")
            reset.performClick(nil)
            let committed = service.webEvents.count
            RunLoop.main.run(until: Date().addingTimeInterval(0.7))
            precondition(service.webEvents.count == committed && service.webValues["color"] == .string("0.1 0.2 0.3"), "late color commit must not undo reset")
            for window in windows { window.contentView = nil; window.close() }
        }
        let resourceKinds: [SteamWorkshopWebPropertyKind] = [.file, .directory]
        service.webDescriptor = .init(propertyDefinitions: resourceKinds.enumerated().map { index, kind in
            var definition = SteamWorkshopWebPropertyDefinition(key: "resource\(index)", title: "resource",
                kind: kind, runtimeType: kind.rawValue, order: index, minimumValue: nil, maximumValue: nil,
                allowsFractionalValues: false, fractionalPrecision: nil, displayCondition: nil,
                directoryMode: nil, fileType: "image", defaultValue: .string(""), options: [])
            definition.displayTitle = text
            return definition
        })
        service.webValues = ["resource0": .string("/own/image.png"), "resource1": .string("/own/folder")]
        let resources = SteamWorkshopWebPropertyEditorView(record: .init(id: "resources", title: "resources"))
        let resourceWindow = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 324, height: 560),
            styleMask: [.titled], backing: .buffered, defer: false)
        resourceWindow.isReleasedWhenClosed = false; resourceWindow.contentView = resources; resourceWindow.orderFront(nil); settle(resources)
        let resourceRows = descendants(resources, WorkshopPropertyRowView.self)
        precondition(resourceRows.count == 2 && resourceRows.allSatisfy { $0.style == .resource })
        let clear = descendants(resourceRows[0], NSButton.self).first { $0.toolTip == "清空当前选择" }!
        clear.performClick(nil)
        precondition(service.webEvents.last?.0 == "resource0" && service.webEvents.last?.1 == .string(""))
        settle(resources)
        precondition(service.webValues["resource1"] == .string("/own/folder"), "file clear must not change directory values")
        resourceWindow.contentView = nil; resourceWindow.close()
        let ruleMarkup = ["Before<hr data-style='section'><b>中文标题</b><HR />After<hr>", "<hr class='only-rule'/>", "文字 &lt;hr&gt;"]
        let ruleCatalog = SceneUserPropertyDefinitionParser().parse(properties: Dictionary(uniqueKeysWithValues: ruleMarkup.indices.map {
            ("rule\($0)", ["type": "text", "text": ruleMarkup[$0], "order": $0] as [String: Any])
        }))
        let localizedRuleCatalog = SceneUserPropertyDefinitionParser().parse(properties: ["renamed": ["type": "text", "text": "author_rule"]])
        let localizedRuleContext = SteamWorkshopScenePropertyContext(catalog: localizedRuleCatalog, actionableKeys: [],
            effectiveValues: [:], propertyDisplayLocalization: .init(flat: ["author_rule": "<hr>"]))
        precondition(localizedRuleContext.definitions.count == 1 && !localizedRuleContext.hasEditorControls,
            "localized authored separators are display declarations, never runtime capability")
        let projectionRecord = SteamWorkshopDownloadRecord(id: "only-notes", title: "only-notes")
        precondition(service.projectedScenePropertyContext(localizedRuleContext, for: projectionRecord) != nil,
            "real Scene admission must retain localized rule-only declarations")
        for markup in ["", "<img src='invalid'>"] {
            let decoration = SceneUserPropertyDefinitionParser().parse(properties: ["note": ["type": "text", "text": markup]])
            let context = SteamWorkshopScenePropertyContext(catalog: decoration, actionableKeys: [], effectiveValues: [:])
            precondition(service.projectedScenePropertyContext(context, for: projectionRecord) == nil,
                "empty decorations must not create an available property panel")
        }
        for width: CGFloat in [324, 480] {
            service.webDescriptor = .init(propertyDefinitions: ruleMarkup.indices.map { index in
                var definition = SteamWorkshopWebPropertyDefinition(key: "rule\(index)", title: ruleMarkup[index], kind: .label,
                    runtimeType: "text", order: index, minimumValue: nil, maximumValue: nil, allowsFractionalValues: false,
                    fractionalPrecision: nil, displayCondition: nil, directoryMode: nil, fileType: nil, defaultValue: .string(""), options: [])
                definition.displayTitleMarkup = ruleMarkup[index]
                return definition
            })
            let web = SteamWorkshopWebPropertyEditorView(record: .init(id: "rules", title: "rules"))
            let scene = SteamWorkshopScenePropertyEditorView(record: .init(id: "rules", title: "rules"),
                context: .init(catalog: ruleCatalog, actionableKeys: Set(ruleCatalog.definitions.map(\.key)), effectiveValues: [:]))
            for editor in [web as NSView, scene] {
                let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: width, height: 560),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = editor
                // The production inspector fixes its hosted editor width too.
                editor.widthAnchor.constraint(equalToConstant: width).isActive = true
                window.orderFront(nil); settle(editor)
                let list = descendants(editor, NSCollectionView.self).first
                let rows = list.map { list in
                    (0..<3).map { descendants(list.item(at: IndexPath(item: $0, section: 0))!.view, WorkshopPropertyRowView.self).first! }
                } ?? descendants(editor, WorkshopPropertyRowView.self)
                precondition(rows.count == 3)
                for (index, row) in rows.enumerated() {
                    precondition(descendants(row, NSBox.self).count == [3, 1, 0][index],
                        "all authored rules must render, escaped markup stays literal")
                    precondition(row.title.presentation == WorkshopPropertyTextContent(markup: ruleMarkup[index]))
                    for child in descendants(row, NSBox.self) {
                        let frame = child.convert(child.bounds, to: row)
                        precondition(frame.width > width - 12 && frame.minY >= -1 && frame.maxY <= row.bounds.height + 1,
                            "rule must fill the title width without clipping: \(frame), row \(row.bounds), width \(width), \(type(of: editor)) \(editor.bounds)")
                    }
                }
                precondition(descendants(editor, NSButton.self).allSatisfy { $0.title != "恢复默认" || $0.isHidden },
                    "read-only author notes and rules must not manufacture a reset action")
                window.contentView = nil; window.close()
            }
        }
        let gate = SteamWorkshopWebPropertyDefinition(key: "enabled", title: "Own enabled", kind: .toggle,
            runtimeType: "bool", order: 0, minimumValue: nil, maximumValue: nil, allowsFractionalValues: false,
            fractionalPrecision: nil, displayCondition: "enabled.value == true", directoryMode: nil, fileType: nil,
            defaultValue: .bool(true), options: [])
        service.webDescriptor = .init(propertyDefinitions: [gate]); service.webValues = ["enabled": .bool(true)]
        let hidden = SteamWorkshopWebPropertyEditorView(record: .init(id: "hidden", title: "hidden"))
        let toggle = descendants(descendants(hidden, WorkshopPropertyRowView.self).first!, NSButton.self).first!
        toggle.state = .off; toggle.sendAction(toggle.action, to: toggle.target); settle(hidden)
        precondition(service.webValues["enabled"] == .bool(false))
        for editor in [hidden, SteamWorkshopWebPropertyEditorView(record: .init(id: "hidden", title: "hidden"))] {
            precondition(descendants(editor, WorkshopPropertyRowView.self).isEmpty)
            let scroll = descendants(editor, NSScrollView.self).first!
            let reset = descendants(editor, NSButton.self).first { $0.title == "恢复默认" }!
            precondition(!editor.presentsOnlyMessage && !scroll.isHidden && !reset.isHidden,
                "all conditionally hidden controls must retain recovery, including after reopening")
        }
        descendants(hidden, NSButton.self).first { $0.title == "恢复默认" }!.performClick(nil)
        precondition(service.webValues["enabled"] == .bool(true)
            && descendants(hidden, WorkshopPropertyRowView.self).count == 1,
            "reset must restore the self-hidden control")
        service.webDescriptor = .init(propertyDefinitions: [])
        let empty = SteamWorkshopWebPropertyEditorView(record: .init(id: "empty", title: "empty"))
        precondition(empty.presentsOnlyMessage && empty.emptyStateMessage!.contains("\n"))
        print("Web/Scene presentation PASS: scrolling first-row reset, authored rules and bilingual rows, hidden scroller hit/wheel, original option payload and color/reset")
    }
}
