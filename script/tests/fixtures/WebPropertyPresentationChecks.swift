@main enum WebPropertyPresentationChecks {
    @MainActor static func main() {
        initializeNativeAppHarness()
        let service = SteamWorkshopService.shared
        var sliderDispatchChecks: [String: Bool] = [:]
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
            for _ in 0..<5 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.008))
                while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
                view.layoutSubtreeIfNeeded()
            }
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
                if row == 4 {
                    for textRow in [webRows[row], sceneRow] {
                        let field = descendants(textRow, NSTextField.self).first { $0.isEditable }!
                        precondition(field.superview is WallpaperFormFieldSurface && !field.isBordered && !field.drawsBackground)
                        precondition(field.stringValue == "raw text" && field.delegate != nil && field.focusRingType == .exterior)
                    }
                }
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
                precondition(webScroll.verticalScroller?.isHidden == true, "Web scrollbar must stay hidden after style, layout and flash")
                let resetFrame = reset.convert(reset.bounds, to: web)
                let toggle = descendants(webRows[0], NSButton.self).first!
                let point = toggle.convert(NSPoint(x: toggle.bounds.maxX - 2, y: toggle.bounds.midY), to: web)
                precondition(web.hitTest(point) === toggle, "Web checkbox must not hit the scrollbar")
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0)!
                webScroll.scrollWheel(with: NSEvent(cgEvent: event)!)
                precondition(webScroll.contentView.bounds.origin.y > 0)
                precondition(webScroll.verticalScroller?.isHidden == true, "Web wheel must not reveal a scrollbar")
                precondition(reset.convert(reset.bounds, to: web) != resetFrame, "reset must scroll with its content")
                sceneScroll.scrollerStyle = style
                sceneScroll.contentView.scroll(to: .zero); settle(scene)
                sceneScroll.flashScrollers(); settle(scene)
                precondition(sceneScroll.verticalScroller?.isHidden == true, "Scene shared-panel scrollbar must stay hidden after style, layout and flash")
                let sceneReset = descendants(scene, NSButton.self).first { $0.title == "恢复默认" }!
                precondition(sceneReset.isDescendant(of: sceneScroll.documentView!))
                let sceneResetFrame = sceneReset.convert(sceneReset.bounds, to: scene)
                let sceneEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -100, wheel2: 0, wheel3: 0)!
                sceneScroll.scrollWheel(with: NSEvent(cgEvent: sceneEvent)!); settle(scene)
                precondition(!sceneReset.isDescendant(of: scene)
                    || sceneReset.convert(sceneReset.bounds, to: scene) != sceneResetFrame,
                    "Scene reset must also leave its original viewport position")
                sceneScroll.contentView.scroll(to: .zero); settle(scene)
                sceneScroll.flashScrollers(); settle(scene)
                precondition(sceneScroll.verticalScroller?.isHidden == true, "Scene shared-panel scrollbar must stay hidden after style, layout and flash")
                precondition(descendants(scene, NSButton.self).filter { $0.title == "恢复默认" }.count == 1)
            }
            let input = descendants(web, NSTextField.self).first { $0.isEditable }!
            precondition(input.placeholderString == text && input.accessibilityLabel() == text,
                "Web plain display title must label the string field and its placeholder")
            let inputDelegate = input.delegate!
            let beforeUnchangedText = service.webEvents.count
            input.sendAction(input.action, to: input.target)
            inputDelegate.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: input))
            precondition(service.webEvents.count == beforeUnchangedText,
                "unchanged Return and end editing must not persist or rebuild Web text")
            input.stringValue = "temporary live preview"
            inputDelegate.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: input))
            let previewsBeforeCancel = service.webPreviews.count
            input.stringValue = "raw text"
            inputDelegate.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: input))
            precondition(service.webEvents.count == beforeUnchangedText && service.webPreviews.count == previewsBeforeCancel + 1
                && service.webPreviews.last?.1 == .string("raw text"),
                "canceling text after a live preview must restore runtime once without a persistent edit")
            input.sendAction(input.action, to: input.target)
            inputDelegate.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: input))
            precondition(service.webEvents.count == beforeUnchangedText && service.webPreviews.count == previewsBeforeCancel + 1,
                "a repeated end event after cancellation must not reproject the same runtime value")
            input.scrollToVisible(input.bounds)
            precondition(windows[0].makeFirstResponder(input))
            let inputEditor = input.currentEditor() as! NSTextView
            inputEditor.setMarkedText("候选", selectedRange: NSRange(location: 2, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0))
            precondition(inputEditor.hasMarkedText())
            let previewsBeforeMarkedText = service.webPreviews.count
            let markedText = input.stringValue
            inputDelegate.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: input))
            precondition(service.webEvents.count == beforeUnchangedText && service.webPreviews.count == previewsBeforeMarkedText + 1
                && service.webPreviews.last?.1 == .string(markedText),
                "marked text must keep the original live preview payload without a persistent edit")
            inputEditor.unmarkText()
            let editedText = "  中文完成 \n"
            input.stringValue = editedText
            input.sendAction(input.action, to: input.target)
            inputDelegate.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: input))
            precondition(service.webEvents.count == beforeUnchangedText + 1
                && service.webEvents.last?.0 == "input" && service.webEvents.last?.1 == .string(editedText),
                "changed text must preserve whitespace and persist once for Return plus end editing")
            settle(web)
            service.webValues["input"] = .string("external accepted text")
            let rebuildTrigger = descendants(web, NSPopUpButton.self).first!
            rebuildTrigger.selectItem(at: 0); rebuildTrigger.sendAction(rebuildTrigger.action, to: rebuildTrigger.target)
            settle(web)
            let projectedInput = descendants(web, NSTextField.self).first { $0.isEditable }!
            precondition(projectedInput !== input && projectedInput.stringValue == "external accepted text")
            let beforeProjectedEcho = service.webEvents.count
            projectedInput.sendAction(projectedInput.action, to: projectedInput.target)
            projectedInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: projectedInput))
            precondition(service.webEvents.count == beforeProjectedEcho,
                "rebuilding from an external accepted value must retire the old text baseline")
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
        service.webDescriptor = .init(propertyDefinitions: [definitions[1]])
        service.webValues = ["rate": .number(0.5)]
        let sliderEditor = SteamWorkshopWebPropertyEditorView(record: .init(id: "slider-events", title: "slider-events"))
        let sliderWindow = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 356, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        sliderWindow.center()
        sliderWindow.isReleasedWhenClosed = false; sliderWindow.contentView = sliderEditor
        sliderWindow.makeKeyAndOrderFront(nil); NSApp.activate()
        settle(sliderEditor)
        precondition(NSApp.isActive && sliderWindow.isKeyWindow, "native slider keyboard checks require an active key window")
        let keyboardSlider = descendants(sliderEditor, WorkshopPropertySlider.self).first!
        precondition(sliderWindow.makeFirstResponder(keyboardSlider))
        let beforeKeyCommit = service.webEvents.count, beforeKeyPreview = service.webPreviews.count
        let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: sliderWindow.windowNumber, context: nil, characters: "\u{f703}",
            charactersIgnoringModifiers: "\u{f703}", isARepeat: false, keyCode: 124)!
        NSApp.sendEvent(right)
        precondition(service.webEvents.count == beforeKeyCommit + 1 && keyboardSlider.doubleValue > 0.5
            && service.webEvents.last?.0 == "rate" && service.webEvents.last?.1 == .number(keyboardSlider.doubleValue),
            "native slider arrow input must commit its normalized value once")
        sliderDispatchChecks["native-keyboard-action-does-not-preview-before-commit"] = service.webPreviews.count == beforeKeyPreview
        settle(sliderEditor)
        let accessibleSlider = descendants(sliderEditor, WorkshopPropertySlider.self).first!
        precondition(accessibleSlider !== keyboardSlider && sliderWindow.firstResponder === accessibleSlider
            && accessibleSlider.doubleValue == keyboardSlider.doubleValue,
            "the asynchronous Web rebuild must restore slider value and keyboard focus")
        let beforeAXCommit = service.webEvents.count, beforeAXPreview = service.webPreviews.count
        let beforeAXValue = accessibleSlider.doubleValue
        // AppKit can report false after dispatching the increment; verify its actual value and action below.
        _ = accessibleSlider.accessibilityPerformIncrement()
        precondition(service.webEvents.count == beforeAXCommit + 1 && accessibleSlider.doubleValue > beforeAXValue
            && service.webEvents.last?.1 == .number(accessibleSlider.doubleValue),
            "the native accessibility increment must commit once")
        sliderDispatchChecks["native-accessibility-action-does-not-preview-before-commit"] = service.webPreviews.count == beforeAXPreview
        settle(sliderEditor)
        for (raw, expected, summary) in [(0.626, 0.63, "0.63"), (-2.0, 0.0, "0.00"), (3.0, 1.0, "1.00")] {
            let slider = descendants(sliderEditor, WorkshopPropertySlider.self).first!
            let beforeCommit = service.webEvents.count, beforePreview = service.webPreviews.count
            slider.doubleValue = raw; slider.sendAction(slider.action, to: slider.target)
            precondition(service.webEvents.count == beforeCommit + 1 && service.webEvents.last?.0 == "rate"
                && service.webEvents.last?.1 == .number(expected) && slider.doubleValue == expected,
                "nontracking Web slider actions must retain precision and native bounds")
            precondition(descendants(sliderEditor, NSTextField.self).contains { $0.stringValue == summary },
                "slider summary must use the normalized value before rebuilding")
            sliderDispatchChecks["nontracking-\(raw)-does-not-preview-before-commit"] = service.webPreviews.count == beforePreview
            settle(sliderEditor)
            precondition(descendants(sliderEditor, WorkshopPropertySlider.self).first!.doubleValue == expected)
        }
        let senderOwner = descendants(sliderEditor, WorkshopPropertySlider.self).first!
        let plain = NSSlider(value: 0.346, minValue: 0, maxValue: 1, target: senderOwner.target, action: senderOwner.action)
        let beforePlainCommit = service.webEvents.count, beforePlainPreview = service.webPreviews.count
        plain.isHighlighted = true; plain.sendAction(plain.action, to: plain.target)
        precondition(service.webEvents.count == beforePlainCommit && service.webPreviews.count == beforePlainPreview + 1
            && service.webPreviews.last?.1 == .number(0.35) && plain.doubleValue == 0.35,
            "a highlighted plain NSSlider sender must preserve its preview fallback")
        plain.isHighlighted = false; plain.doubleValue = 0.474
        let beforePlainReleasePreview = service.webPreviews.count
        plain.sendAction(plain.action, to: plain.target)
        precondition(service.webEvents.count == beforePlainCommit + 1 && service.webEvents.last?.1 == .number(0.47)
            && plain.doubleValue == 0.47, "an unhighlighted plain NSSlider sender must commit once")
        sliderDispatchChecks["plain-unhighlighted-action-does-not-preview-before-commit"] = service.webPreviews.count == beforePlainReleasePreview
        withExtendedLifetime(senderOwner) {}
        settle(sliderEditor)
        let trackingSlider = descendants(sliderEditor, WorkshopPropertySlider.self).first!
        let beforeTrackingCommit = service.webEvents.count, beforeTrackingPreview = service.webPreviews.count
        // The tracking state is controlled; the action target and end callback remain production.
        trackingSlider.isTrackingMouse = true
        for raw in [0.234, 0.678] {
            trackingSlider.doubleValue = raw; trackingSlider.sendAction(trackingSlider.action, to: trackingSlider.target)
        }
        precondition(service.webEvents.count == beforeTrackingCommit && service.webPreviews.count == beforeTrackingPreview + 2
            && service.webPreviews.suffix(2).map(\.1) == [.number(0.23), .number(0.68)]
            && trackingSlider.doubleValue == 0.68,
            "tracking slider actions must preview each normalized value without committing")
        precondition(descendants(sliderEditor, NSTextField.self).contains { $0.stringValue == "0.68" })
        trackingSlider.isTrackingMouse = false
        trackingSlider.onTrackingEnded!(trackingSlider)
        precondition(service.webEvents.count == beforeTrackingCommit + 1 && service.webPreviews.count == beforeTrackingPreview + 2
            && service.webEvents.last?.0 == "rate" && service.webEvents.last?.1 == .number(0.68),
            "the original tracking-ended callback must commit the final value once without another preview")
        settle(sliderEditor)
        let integer = SteamWorkshopWebPropertyDefinition(key: "integer-rate", title: "Integer slider", kind: .slider,
            runtimeType: "slider", order: 0, minimumValue: -2, maximumValue: 3, allowsFractionalValues: false,
            fractionalPrecision: nil, displayCondition: nil, directoryMode: nil, fileType: nil, defaultValue: .number(0), options: [])
        service.webDescriptor = .init(propertyDefinitions: [integer]); service.webValues = [integer.key: .number(0)]
        let integerEditor = SteamWorkshopWebPropertyEditorView(record: .init(id: "integer-slider", title: "integer-slider"))
        sliderWindow.contentView = integerEditor; settle(integerEditor)
        for (raw, expected) in [(-1.6, -2.0), (1.6, 2.0)] {
            let slider = descendants(integerEditor, WorkshopPropertySlider.self).first!
            let beforeCommit = service.webEvents.count, beforePreview = service.webPreviews.count
            slider.doubleValue = raw; slider.sendAction(slider.action, to: slider.target)
            precondition(service.webEvents.count == beforeCommit + 1 && service.webEvents.last?.0 == integer.key
                && service.webEvents.last?.1 == .number(expected) && slider.doubleValue == expected)
            precondition(descendants(integerEditor, NSTextField.self).contains { $0.stringValue == String(Int(expected)) },
                "integer slider normalization must retain its integer summary")
            sliderDispatchChecks["integer-\(raw)-does-not-preview-before-commit"] = service.webPreviews.count == beforePreview
            settle(integerEditor)
        }
        sliderWindow.contentView = nil; sliderWindow.close()
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
        let chooseFile = descendants(resourceRows[0], NSButton.self).first { $0.title == "选择文件" }!
        let beforeRepeatedFile = service.webEvents.count
        chooseFile.performClick(nil); chooseFile.performClick(nil)
        precondition(service.webEvents.count == beforeRepeatedFile + 2
            && service.webEvents.suffix(2).allSatisfy { $0.0 == "resource0" && $0.1 == .string("/own/selected.png") },
            "reselecting the same file must still reach its grant and explicit reapply service entry")
        let clear = descendants(resourceRows[0], NSButton.self).first { $0.toolTip == "清空当前选择" }!
        clear.performClick(nil)
        precondition(service.webEvents.last?.0 == "resource0" && service.webEvents.last?.1 == .string(""))
        settle(resources)
        precondition(service.webValues["resource1"] == .string("/own/folder"), "file clear must not change directory values")
        let chooseDirectory = descendants(resources, NSButton.self).first { $0.title == "选择文件夹" }!
        let beforeRepeatedDirectory = service.webEvents.count
        chooseDirectory.performClick(nil); chooseDirectory.performClick(nil)
        precondition(service.webEvents.count == beforeRepeatedDirectory + 2
            && service.webEvents.suffix(2).allSatisfy { $0.0 == "resource1" && $0.1 == .string("/own/selected.png") },
            "same-directory reauthorization must not use the text commit deduplication")
        resourceWindow.contentView = nil; resourceWindow.close()
        let numericText = SteamWorkshopWebPropertyDefinition(key: "numeric-text", title: "Legacy text input", kind: .text,
            runtimeType: "textinput", order: 0, minimumValue: nil, maximumValue: nil, allowsFractionalValues: true,
            fractionalPrecision: 2, displayCondition: nil, directoryMode: nil, fileType: nil, defaultValue: .number(0.5), options: [])
        service.webDescriptor = .init(propertyDefinitions: [numericText])
        service.webValues = [numericText.key: .number(0.5)]
        let formattedTextEditor = SteamWorkshopWebPropertyEditorView(record: .init(id: "numeric-text", title: "numeric-text"))
        let numericInput = descendants(formattedTextEditor, NSTextField.self).first { $0.isEditable }!
        precondition(numericInput.stringValue == "0.50")
        let beforeNumericText = service.webEvents.count
        numericInput.sendAction(numericInput.action, to: numericInput.target)
        numericInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: numericInput))
        precondition(service.webEvents.count == beforeNumericText,
            "unchanged formatted numeric text must not manufacture a number-to-string property edit")
        numericInput.stringValue = "0.6"
        numericInput.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: numericInput))
        precondition(service.webPreviews.last?.1 == .string("0.6"), "real text edits keep their original string preview semantics")
        numericInput.stringValue = "0.50"
        numericInput.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: numericInput))
        precondition(service.webPreviews.last?.1 == .number(0.5),
            "returning to the accepted display text must restore its original typed runtime value")
        let previewsAfterTypedRevert = service.webPreviews.count
        numericInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: numericInput))
        precondition(service.webEvents.count == beforeNumericText && service.webPreviews.count == previewsAfterTypedRevert)
        numericInput.stringValue = "0.7"
        numericInput.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: numericInput))
        numericInput.stringValue = "0.50"
        numericInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: numericInput))
        precondition(service.webEvents.count == beforeNumericText && service.webPreviews.count == previewsAfterTypedRevert + 2
            && service.webPreviews.last?.1 == .number(0.5), "canceling without a final change notification must also restore the typed baseline")
        numericInput.stringValue = "0.5"
        numericInput.sendAction(numericInput.action, to: numericInput.target)
        numericInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: numericInput))
        precondition(service.webEvents.count == beforeNumericText + 1 && service.webEvents.last?.1 == .string("0.5"),
            "a real text edit retains the existing raw string submission semantics")
        let composedText = "\u{00e9}", decomposedText = "e\u{0301}"
        precondition(composedText == decomposedText && !composedText.utf8.elementsEqual(decomposedText.utf8))
        service.webDescriptor = .init(propertyDefinitions: [definitions[4]])
        service.webValues = ["input": .string(composedText)]
        let unicodeEditor = SteamWorkshopWebPropertyEditorView(record: .init(id: "unicode-text", title: "unicode-text"))
        let unicodeInput = descendants(unicodeEditor, NSTextField.self).first { $0.isEditable }!
        precondition(unicodeInput.stringValue.utf8.elementsEqual(composedText.utf8))
        let beforeUnicodeText = service.webEvents.count
        unicodeInput.sendAction(unicodeInput.action, to: unicodeInput.target)
        unicodeInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: unicodeInput))
        precondition(service.webEvents.count == beforeUnicodeText, "identical raw UTF8 text remains an unchanged submission")
        unicodeInput.stringValue = decomposedText
        unicodeInput.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: unicodeInput))
        precondition(service.webPreviews.last?.1.stringValue.map { $0.utf8.elementsEqual(decomposedText.utf8) } == true,
            "a canonically equivalent but byte-different edit must retain its new preview payload")
        let beforeUnicodeCancel = service.webPreviews.count
        unicodeInput.stringValue = composedText
        unicodeInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: unicodeInput))
        precondition(service.webEvents.count == beforeUnicodeText && service.webPreviews.count == beforeUnicodeCancel + 1
            && service.webPreviews.last?.1.stringValue.map { $0.utf8.elementsEqual(composedText.utf8) } == true,
            "canceling the different Unicode spelling must restore the original raw bytes once")
        unicodeInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: unicodeInput))
        precondition(service.webEvents.count == beforeUnicodeText && service.webPreviews.count == beforeUnicodeCancel + 1,
            "an identical raw end event after Unicode cancellation must not project again")
        unicodeInput.stringValue = decomposedText
        unicodeInput.sendAction(unicodeInput.action, to: unicodeInput.target)
        unicodeInput.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: unicodeInput))
        precondition(service.webEvents.count == beforeUnicodeText + 1 && service.webEvents.last?.0 == "input"
            && service.webEvents.last?.1.stringValue.map { $0.utf8.elementsEqual(decomposedText.utf8) } == true,
            "Return and end editing must persist the different Unicode raw string exactly once")
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
        let numeric = SteamWorkshopWebPropertyDefinition(key: "numericText", title: "Numeric text", kind: .text,
            runtimeType: "text", order: 0, minimumValue: nil, maximumValue: nil, allowsFractionalValues: true,
            fractionalPrecision: nil, displayCondition: nil, directoryMode: nil, fileType: nil,
            defaultValue: .number(12.5), options: [])
        service.webDescriptor = .init(propertyDefinitions: [numeric]); service.webValues = [numeric.key: .number(12.5)]
        service.webEvents = []
        let numericEditor = SteamWorkshopWebPropertyEditorView(record: .init(id: "numeric", title: "numeric"))
        let numericField = descendants(numericEditor, NSTextField.self).first { $0.isEditable }!
        let nativeNumeric = NSTextField(string: numericField.stringValue)
        precondition(!(numericField.superview is WallpaperFormFieldSurface)
            && numericField.isBezeled == nativeNumeric.isBezeled && numericField.isBordered == nativeNumeric.isBordered
            && numericField.bezelStyle == nativeNumeric.bezelStyle && numericField.formatter === nativeNumeric.formatter,
            "numeric text retains its native control style and formatter")
        numericField.stringValue = "42.5"; numericField.sendAction(numericField.action, to: numericField.target)
        precondition(service.webEvents.last?.0 == numeric.key && service.webEvents.last?.1 == .string("42.5"),
            "authored text input with a numeric default keeps its original string submission")
        let titleCases: [(kind: SteamWorkshopWebPropertyKind, raw: String, markup: String?, plain: String?, expected: String?)] = [
            (.text, "Raw title", "<b>First</b><hr/>Second &amp; &#20013;", "ignored plain", "First\nSecond & 中"),
            (.text, "Legacy &amp; &#20013;", nil, nil, "Legacy & 中"),
            (.text, "Raw title", "", "must not fall back", "未命名属性"),
            (.text, "Raw title", nil, "", "未命名属性"),
            (.label, "Original note", "", "must not fall back", nil),
            (.group, "Original group", nil, "", nil),
        ]
        for (index, item) in titleCases.enumerated() {
            var definition = SteamWorkshopWebPropertyDefinition(key: "title\(index)", title: item.raw, kind: item.kind,
                runtimeType: "text", order: 0, minimumValue: nil, maximumValue: nil, allowsFractionalValues: false,
                fractionalPrecision: nil, displayCondition: nil, directoryMode: nil, fileType: nil,
                defaultValue: .string("kept value"), options: [])
            definition.displayTitleMarkup = item.markup; definition.displayTitle = item.plain
            service.webDescriptor = .init(propertyDefinitions: [definition]); service.webValues = [definition.key: .string("kept value")]
            let editor = SteamWorkshopWebPropertyEditorView(record: .init(id: "title-case", title: "title-case"))
            let rows = descendants(editor, WorkshopPropertyRowView.self)
            if let expected = item.expected {
                precondition(rows.count == 1)
                let field = descendants(rows[0], NSTextField.self).first { $0.isEditable }!
                precondition(rows[0].title.stringValue == expected && field.placeholderString == expected
                    && field.accessibilityLabel() == expected && field.stringValue == "kept value",
                    "Web title, placeholder and AX must preserve markup/plain/fallback and explicit-empty precedence")
                if index == 0 {
                    precondition(rows[0].title.presentation.segments == [.text("First"), .separator, .text("Second & 中")],
                        "string control titles must retain their full authored separator presentation")
                }
            } else {
                precondition(rows.isEmpty && editor.presentsOnlyMessage,
                    "explicit empty localized labels and groups must stay hidden without fallback text")
            }
        }
        service.webDescriptor = .init(propertyDefinitions: [])
        let empty = SteamWorkshopWebPropertyEditorView(record: .init(id: "empty", title: "empty"))
        precondition(empty.presentsOnlyMessage && empty.emptyStateMessage!.contains("\n"))
        print("Web slider dispatch checks", String(decoding: try! JSONSerialization.data(withJSONObject: sliderDispatchChecks, options: [.sortedKeys]), as: UTF8.self))
        fflush(stdout)
        precondition(sliderDispatchChecks.values.allSatisfy { $0 }, "nontracking Web slider actions must use only the commit service entry")
        print("Web/Scene presentation PASS: scrolling first-row reset, authored rules and bilingual rows, hidden scroller hit/wheel, original option payload and color/reset")
    }
}
