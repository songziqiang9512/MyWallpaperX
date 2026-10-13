#!/usr/bin/env python3
"""Execute the native Scene list with production context/conditions and service leaves."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_routing import method_body

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop'
SERVICE = MODULE / 'Scene/SteamWorkshopSceneService+SceneProperties.swift'
EDITOR = MODULE / 'Scene/SteamWorkshopScenePropertyEditorView.swift'
NORMALIZATION = MODULE / 'Web/Core/SteamWorkshopService+WebPropertyNormalizationSupport.swift'


STUBS = r'''
import AppKit
import Combine
struct SteamWorkshopDownloadRecord { let id: String; let title: String }
struct NativeWebDescriptor {
    let propertyDefinitions: [SteamWorkshopWebPropertyDefinition]
    let staticContentSummary = 0
}
@MainActor final class PickerProbe: NSOpenPanel {
    static var opened: [PickerProbe] = []
    private var reply: ((NSApplication.ModalResponse) -> Void)?
    var cancellations = 0
    override var url: URL? { URL(fileURLWithPath: "/own/selected.png") }
    override func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        reply = handler
        Self.opened.append(self)
    }
    override func cancel(_ sender: Any?) { cancellations += 1 }
    func finish(_ response: NSApplication.ModalResponse) { reply?(response) }
}
@MainActor final class ColorDropInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(well: NSColorWell, color: NSColor) {
        draggingDestinationWindow = well.window
        draggingLocation = well.convert(NSPoint(x: well.bounds.midX, y: well.bounds.midY), to: nil)
        draggingPasteboard = NSPasteboard(name: .init("com.songziqiang.MyWallpaperX.Debug.ColorDrop." + UUID().uuidString))
        super.init()
        precondition(draggingPasteboard.writeObjects([color]))
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override nonisolated func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        for (offset, object) in (draggingPasteboard.readObjects(forClasses: classes, options: searchOptions) ?? []).enumerated() {
            guard let writer = object as? NSPasteboardWriting else { continue }
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(NSRect(x: draggingLocation.x, y: draggingLocation.y, width: 10, height: 10), contents: nil)
            var stop = ObjCBool(false)
            block(item, offset, &stop)
            if stop.boolValue { break }
        }
    }
}
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    let objectWillChange = ObservableObjectPublisher()
    var overrides: [String: SceneUserPropertyValue] = [:]
    var events: [(String, SceneUserPropertyValue)] = []
    var textureURL: URL?
    var textureReplies: [@MainActor (Bool) -> Void] = []
    var resetDefaults: [String: SceneUserPropertyValue] = [:]
    var webDescriptor: NativeWebDescriptor?
    var webValues: [String: SteamWorkshopWebPropertyValue] = [:]
    var webEvents: [(String, SteamWorkshopWebPropertyValue)] = []
    func resolvedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> NativeWebDescriptor? { webDescriptor }
    func effectiveWebPropertyValues(for record: SteamWorkshopDownloadRecord, descriptor: NativeWebDescriptor) -> [String: SteamWorkshopWebPropertyValue] { webValues }
    func shouldRenderWebPropertyControl(_ definition: SteamWorkshopWebPropertyDefinition, staticContentSummary: Int) -> Bool { true }
    func shouldDisplayWebProperty(_ definition: SteamWorkshopWebPropertyDefinition,
                                 values: [String: SteamWorkshopWebPropertyValue], definitions: [SteamWorkshopWebPropertyDefinition]) -> Bool { true }
    func visibleWebPropertyOptions(for definition: SteamWorkshopWebPropertyDefinition,
                                   values: [String: SteamWorkshopWebPropertyValue], definitions: [SteamWorkshopWebPropertyDefinition]) -> [SteamWorkshopWebPropertyOption] { definition.options }
    func resetWebPropertyValues(for record: SteamWorkshopDownloadRecord) {}
    func previewWebPropertyValue(_ value: SteamWorkshopWebPropertyValue, for definition: SteamWorkshopWebPropertyDefinition,
                                 record: SteamWorkshopDownloadRecord) {}
    func updateWebPropertyValue(_ value: SteamWorkshopWebPropertyValue, for definition: SteamWorkshopWebPropertyDefinition,
                                record: SteamWorkshopDownloadRecord) { webEvents.append((definition.key, value)) }
    static func effectiveWebSliderPrecision(for definition: SteamWorkshopWebPropertyDefinition) -> Int? { definition.fractionalPrecision }
    func scenePropertyOverrides(for record: SteamWorkshopDownloadRecord) -> [String: SceneUserPropertyValue] { overrides }
    func updateScenePropertyValue(_ value: SceneUserPropertyValue, definition: SceneUserPropertyDefinition,
                                  record: SteamWorkshopDownloadRecord) {
        events.append((definition.key, value))
        overrides[definition.key] = value
        objectWillChange.send()
    }
    func resetScenePropertyValues(for record: SteamWorkshopDownloadRecord,
                                  defaultValues: [String: SceneUserPropertyValue], completion: @escaping @MainActor () -> Void) {
        resetDefaults = defaultValues
        overrides = [:]; objectWillChange.send(); completion()
    }
    func resolvedSceneTexturePropertyURL(forKey key: String, record: SteamWorkshopDownloadRecord) -> URL? { textureURL }
    func updateSceneTexturePropertyURL(_ url: URL?, definition: SceneUserPropertyDefinition,
                                      record: SteamWorkshopDownloadRecord, completion: @escaping @MainActor (Bool) -> Void) {
        textureReplies.append(completion)
    }
}
'''

HARNESS = r'''
extension NSCollectionView {
    var itemCount: Int { numberOfItems(inSection: 0) }
    func scrollToRow(_ row: Int) {
        scrollToItems(at: [IndexPath(item: row, section: 0)], scrollPosition: .nearestHorizontalEdge)
    }
    func realizedCell(_ row: Int) -> NSView {
        scrollToRow(row)
        layoutSubtreeIfNeeded()
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        guard let cell = item(at: IndexPath(item: row, section: 0))?.view else { fatalError("item not realized \(row)") }
        return cell
    }
    func frameForItem(_ row: Int) -> NSRect {
        collectionViewLayout!.layoutAttributesForItem(at: IndexPath(item: row, section: 0))!.frame
    }
}
@main enum NativeListProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let service = SteamWorkshopService.shared
        let record = SteamWorkshopDownloadRecord(id: "own", title: "own")
        func definition(_ key: String, _ kind: SceneUserPropertyKind, _ value: SceneUserPropertyValue?,
                        title: String? = nil, condition: String? = nil,
                        options: [SceneUserPropertyOption] = []) -> SceneUserPropertyDefinition {
            .init(key: key, title: title ?? key, kind: kind, runtimeType: kind.rawValue,
                order: 0, index: nil, minimumValue: kind == .slider ? -1 : nil,
                maximumValue: kind == .slider ? 1 : nil, stepValue: kind == .slider ? 0.25 : nil,
                allowsFractionalValues: kind == .slider, fractionalPrecision: 2,
                displayCondition: condition, defaultValue: value, options: options)
        }
        let definitions = [
            definition("master", .bool, .bool(false)),
            definition("rate", .slider, .number(0.5)),
            definition("format", .textInput, .string("HH:mm")),
            definition("extra", .textInput, .string("hidden"), condition: "master.value == true"),
            definition("choice", .combo, .string("A"), options: [
                .init(label: "same", value: .string("A"), displayCondition: nil),
                .init(label: "same", value: .string("B"), displayCondition: nil),
                .init(label: "conditional", value: .string("C"), displayCondition: "master.value")]),
            definition("tint", .color, .string("#f60")),
            definition("cover", .sceneTexture, .string("")),
            definition("note", .text, nil, title: String(repeating: "长说明 ", count: 60)),
            definition("section", .group, nil, title: "<b>Group</b>"),
            definition("neighbor", .textInput, .string("untouched")),
        ]
        let catalog = SceneUserPropertyCatalog(definitions: definitions)
        let context = SteamWorkshopScenePropertyContext(catalog: catalog,
            actionableKeys: Set(definitions.map(\.key)), effectiveValues: catalog.defaultValues)
        let editor = SteamWorkshopScenePropertyEditorView(record: record, context: context)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 324, height: 520),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
        }
        let table = descendants(editor, NSCollectionView.self).first!
        let scroll = descendants(editor, NSScrollView.self).first!
        func row(_ key: String) -> Int {
            for row in 0..<table.itemCount {
                let cell = table.realizedCell(row)
                if descendants(cell, NSTextField.self).contains(where: { $0.stringValue == key }) { return row }
            }
            fatalError("missing row \(key)")
        }
        func control<T: NSView>(_ key: String, _ type: T.Type) -> T {
            let index = row(key); table.scrollToRow(index); table.layoutSubtreeIfNeeded()
            return descendants(table.realizedCell(index), type).first!
        }
        let initialCount = table.itemCount
        let toggle = control("master", NSButton.self)
        let formatField = descendants(table.realizedCell(row("format")), NSTextField.self).first { $0.isEditable }!
        precondition(window.makeFirstResponder(formatField))
        let textEditor = formatField.currentEditor() as! NSTextView
        textEditor.setSelectedRange(NSRange(location: 2, length: 0))
        let textDelegate = formatField.delegate!
        textDelegate.controlTextDidBeginEditing?(Notification(name: NSControl.textDidBeginEditingNotification, object: formatField))
        let beforeComposition = service.events.count
        textEditor.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        textEditor.didChangeText()
        precondition(textEditor.hasMarkedText() && service.events.count == beforeComposition, "marked text is not a committed value")
        textEditor.unmarkText()
        textEditor.didChangeText()
        precondition(service.events.last?.1 == .string(formatField.stringValue) && formatField.stringValue.contains("中"),
            "committed composition must reach the original field")
        textEditor.setSelectedRange(NSRange(location: 2, length: 0))
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        precondition(table.itemCount == initialCount + 1, "conditional insert")
        precondition(formatField.currentEditor() === textEditor && textEditor.selectedRange().location == 2,
            "unrelated insert must preserve field editor/caret")
        precondition(service.events.last?.0 == "master" && service.events.last?.1 == .bool(true))
        textEditor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        precondition((window.firstResponder as? NSTextView)?.string == "hidden",
            "actual text-editor Tab command must focus the next property")
        (window.firstResponder as? NSTextView)?.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        precondition(formatField.currentEditor() != nil,
            "actual text-editor Shift-Tab must return to the previous property")
        precondition(editor.focusNextPropertyControl(from: window.firstResponder, reverse: false), "forward virtual key traversal")
        for _ in 0..<12 {
            let responder = window.firstResponder as? NSTextView
            if responder?.string == "untouched" { break }
            precondition(editor.focusNextPropertyControl(from: window.firstResponder, reverse: false))
        }
        precondition((window.firstResponder as? NSTextView)?.string == "untouched", "offscreen input must receive focus")
        let shiftedEditor = window.firstResponder as! NSTextView
        let shiftedField = shiftedEditor.delegate as! NSTextField
        shiftedEditor.setSelectedRange(NSRange(location: 2, length: 0))
        for enabled in [false, true, false, true] {
            service.overrides["master"] = .bool(enabled)
            service.objectWillChange.send()
            for _ in 0..<5 { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001)) }
            precondition(table.itemCount == initialCount + (enabled ? 1 : 0))
            precondition(shiftedField.currentEditor() === shiftedEditor && window.firstResponder === shiftedEditor,
                "inserting/removing before focused definition must preserve its field editor")
            precondition(shiftedEditor.selectedRange().location == 2 && shiftedEditor.string == "untouched",
                "index-path shifts must preserve caret and logical value")
        }
        shiftedEditor.insertText("Z", replacementRange: NSRange(location: 2, length: 0))
        shiftedEditor.didChangeText()
        precondition(service.events.last?.0 == "neighbor" && service.events.last?.1 == .string("unZtouched"),
            "after index-path shifts an edit must target the original definition")
        precondition(editor.focusNextPropertyControl(from: window.firstResponder, reverse: true), "reverse virtual key traversal")
        let first = table.realizedCell(0)
        let firstSwitch = descendants(first, NSButton.self).first!
        precondition(!editor.focusNextPropertyControl(from: firstSwitch, reverse: true), "first row must return keyboard ownership to chrome")
        let last = table.realizedCell(table.itemCount - 1)
        let lastField = descendants(last, NSTextField.self).first { $0.isEditable }!
        precondition(!editor.focusNextPropertyControl(from: lastField, reverse: false), "last row must return keyboard ownership to chrome")
        let popup = control("choice", NSPopUpButton.self)
        precondition(popup.numberOfItems == 3, "duplicate labels must not collapse values")
        popup.selectItem(at: 1); popup.sendAction(popup.action, to: popup.target)
        precondition(service.events.last?.0 == "choice" && service.events.last?.1 == .string("B"))
        let slider = control("rate", WorkshopPropertySlider.self)
        slider.doubleValue = 0.62; slider.sendAction(slider.action, to: slider.target)
        slider.doubleValue = 0.74; slider.sendAction(slider.action, to: slider.target)
        precondition(service.events.suffix(2).map(\.1) == [.number(0.5), .number(0.75)], "continuous Scene step")
        let bounds = slider.convert(slider.bounds, to: scroll.contentView)
        precondition(bounds.minX >= 0 && bounds.maxX <= scroll.contentView.bounds.width + 0.5, "control clipping")
        let note = row(String(repeating: "长说明 ", count: 60).trimmingCharacters(in: .whitespaces))
        precondition(table.frameForItem(note).height > 40, "wrapped explanation height")
        let before = service.events.count
        let delegate = formatField.delegate!
        delegate.controlTextDidBeginEditing?(Notification(name: NSControl.textDidBeginEditingNotification, object: formatField))
        formatField.stringValue = "HH:mm:ss"
        delegate.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: formatField))
        precondition(service.events.count == before + 1 && service.events.last?.1 == .string("HH:mm:ss"))
        let reset = descendants(editor, NSButton.self).first { $0.title == "恢复默认" }!
        let well = control("tint", NSColorWell.self)
        let beforeDrop = service.events.count
        let drop = ColorDropInfo(well: well, color: NSColor(deviceRed: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        let enteredDrop = well.draggingEntered(drop)
        let preparedDrop = well.prepareForDragOperation(drop)
        print("native drag preparation", enteredDrop.rawValue, preparedDrop)
        fflush(stdout)
        precondition(preparedDrop && NSColor(from: drop.draggingPasteboard) != nil)
        let acceptedDrop = well.performDragOperation(drop)
        well.concludeDragOperation(drop)
        print("inactive color drop", acceptedDrop, "event delta", service.events.count - beforeDrop)
        fflush(stdout)
        precondition(acceptedDrop && service.events.count == beforeDrop + 1 && service.events.last?.1 == .string("0.400000 0.500000 0.600000"),
            "native inactive drop must publish exactly one color")
        well.activate(true)
        well.color = NSColor(deviceRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        well.sendAction(well.action, to: well.target)
        precondition(service.events.last?.0 == "tint" && service.events.last?.1 == .string("0.100000 0.200000 0.300000"))
        reset.performClick(nil)
        precondition(service.resetDefaults == catalog.defaultValues)
        let afterReset = service.events.count
        delegate.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: formatField))
        precondition(service.events.count == afterReset && service.overrides.isEmpty, "late end edit cannot undo reset")
        well.sendAction(well.action, to: well.target)
        precondition(service.events.count == afterReset, "inactive color reply cannot undo reset")
        precondition(table.itemCount == initialCount, "conditional removal after reset")
        service.overrides["cover"] = .string("same-path")
        service.objectWillChange.send()
        for _ in 0..<5 { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001)) }
        let textureCell = table.realizedCell(row("cover"))
        let clear = descendants(textureCell, NSButton.self).first { $0.toolTip == "恢复作者提供的默认纹理" }!
        clear.performClick(nil)
        service.textureURL = URL(fileURLWithPath: "/own/restored.png")
        service.textureReplies.removeFirst()(true)
        precondition(descendants(textureCell, NSTextField.self).contains { $0.stringValue == "restored.png" },
            "same override resource receipt must refresh readiness")
        let preserved = service.events.count
        window.contentView = nil
        delegate.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: formatField))
        precondition(service.events.count == preserved, "closed editor late event")
        window.close()
        service.overrides = [:]
        service.events = []
        let many = (0..<200).map { definition("renamed_\($0)", .bool, .bool(false)) }
        let manyCatalog = SceneUserPropertyCatalog(definitions: many)
        let manyContext = SteamWorkshopScenePropertyContext(catalog: manyCatalog,
            actionableKeys: Set(many.map(\.key)), effectiveValues: manyCatalog.defaultValues)
        let virtual = SteamWorkshopScenePropertyEditorView(record: record, context: manyContext)
        let virtualWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 324, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        virtualWindow.contentView = virtual
        virtualWindow.makeKeyAndOrderFront(nil)
        virtual.layoutSubtreeIfNeeded()
        let virtualTable = descendants(virtual, NSCollectionView.self).first!
        func liveCells() -> [NSView] {
            (0..<virtualTable.itemCount).compactMap { virtualTable.item(at: IndexPath(item: $0, section: 0))?.view }
        }
        precondition(virtualTable.itemCount == 200 && liveCells().count < 200, "list must not eagerly construct all controls")
        let firstCells = Set(liveCells().map(ObjectIdentifier.init))
        var reused = false
        for position in [70, 140, 190, 0] {
            virtualTable.scrollToRow(position)
            virtualTable.layoutSubtreeIfNeeded()
            virtualWindow.displayIfNeeded()
            reused = reused || !firstCells.isDisjoint(with: Set(liveCells().map(ObjectIdentifier.init)))
            let view = virtualTable.realizedCell(position)
            let button = descendants(view, NSButton.self).first!
            button.state = .on; button.sendAction(button.action, to: button.target)
            precondition(service.events.last?.0 == "renamed_\(position)", "reused control must bind to the current property")
            precondition(liveCells().count < 200, "scroll must retain virtualization")
        }
        precondition(reused, "native row identities should be reused")
        virtualWindow.contentView = nil; virtualWindow.close()
        service.overrides = [:]
        let mixed = [definition("retiredTint", .color, .string("0 0 0"))]
            + (0..<120).map { definition("otherKind_\($0)", .bool, .bool(false)) }
        let mixedCatalog = SceneUserPropertyCatalog(definitions: mixed)
        let mixedContext = SteamWorkshopScenePropertyContext(catalog: mixedCatalog,
            actionableKeys: Set(mixed.map(\.key)), effectiveValues: mixedCatalog.defaultValues)
        let mixedEditor = SteamWorkshopScenePropertyEditorView(record: record, context: mixedContext)
        let mixedWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 324, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        mixedWindow.contentView = mixedEditor; mixedWindow.makeKeyAndOrderFront(nil); mixedEditor.layoutSubtreeIfNeeded()
        let mixedTable = descendants(mixedEditor, NSCollectionView.self).first!
        let retired = descendants(mixedTable.realizedCell(0), NSColorWell.self).first!
        retired.activate(true)
        mixedTable.scrollToRow(100); mixedTable.layoutSubtreeIfNeeded(); mixedWindow.displayIfNeeded()
        let resetMixed = descendants(mixedEditor, NSButton.self).first { $0.title == "恢复默认" }!
        resetMixed.performClick(nil)
        precondition(!retired.isActive, "offscreen well must retire or be reached by reset")
        let retiredEvents = service.events.count
        retired.color = .green; retired.sendAction(retired.action, to: retired.target)
        precondition(service.events.count == retiredEvents, "offscreen late color must not undo reset")
        mixedWindow.contentView = nil; mixedWindow.close()
        retired.sendAction(retired.action, to: retired.target)
        precondition(service.events.count == retiredEvents, "offscreen late color must not write after close")
        let detachedDrop = ColorDropInfo(well: retired, color: .red)
        precondition(!retired.performDragOperation(detachedDrop) && service.events.count == retiredEvents,
            "detached view cannot accept a stale drop")
        for (key, condition) in [("firstGate", "firstGate.value == true"), ("otherGate", "!(!otherGate.value)"),
                                 ("thirdGate", "thirdGate.value != false")] {
            service.overrides = [:]
            let defs = [definition(key, .bool, .bool(false)),
                definition("dependent_" + key, .textInput, .string("hidden"), condition: condition),
                definition("neighbor_" + key, .textInput, .string("keep"))]
            let catalog = SceneUserPropertyCatalog(definitions: defs)
            let context = SteamWorkshopScenePropertyContext(catalog: catalog, actionableKeys: Set(defs.map(\.key)),
                effectiveValues: catalog.defaultValues)
            let view = SteamWorkshopScenePropertyEditorView(record: record, context: context)
            let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 324, height: 240),
                styleMask: [.titled], backing: .buffered, defer: false)
            owner.contentView = view; owner.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
            let table = descendants(view, NSCollectionView.self).first!
            precondition(table.itemCount == 2)
            let button = descendants(table.realizedCell(0), NSButton.self).first!
            button.state = .on; button.sendAction(button.action, to: button.target)
            precondition(table.itemCount == 3, "renamed/equivalent condition must insert only its dependent")
            button.state = .off; button.sendAction(button.action, to: button.target)
            precondition(table.itemCount == 2, "adjacent unrelated definition must stay visible")
            owner.contentView = nil; owner.close()
        }
        service.overrides = [:]; service.textureReplies = []
        let pickerDefs = [definition("pickerGate", .bool, .bool(true)),
            definition("pickerCover", .sceneTexture, .string(""), condition: "pickerGate.value")]
        let pickerCatalog = SceneUserPropertyCatalog(definitions: pickerDefs)
        let pickerContext = SteamWorkshopScenePropertyContext(catalog: pickerCatalog,
            actionableKeys: Set(pickerDefs.map(\.key)), effectiveValues: pickerCatalog.defaultValues)
        let pickerEditor = SteamWorkshopScenePropertyEditorView(record: record, context: pickerContext)
        let pickerWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 324, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        pickerWindow.contentView = pickerEditor; pickerWindow.makeKeyAndOrderFront(nil); pickerEditor.layoutSubtreeIfNeeded()
        let pickerTable = descendants(pickerEditor, NSCollectionView.self).first!
        func chooseImage() {
            let row = pickerTable.realizedCell(1)
            descendants(row, NSButton.self).first { $0.title == "选择图像" }!.performClick(nil)
        }
        chooseImage()
        let hiddenReply = PickerProbe.opened.last!
        let gate = descendants(pickerTable.realizedCell(0), NSButton.self).first!
        gate.state = .off; gate.sendAction(gate.action, to: gate.target)
        precondition(hiddenReply.cancellations == 1 && pickerTable.itemCount == 1)
        hiddenReply.finish(.OK)
        precondition(service.textureReplies.isEmpty, "hidden chooser must not submit its late URL")
        gate.state = .on; gate.sendAction(gate.action, to: gate.target)
        chooseImage()
        let resetReply = PickerProbe.opened.last!
        descendants(pickerEditor, NSButton.self).first { $0.title == "恢复默认" }!.performClick(nil)
        resetReply.finish(.OK)
        precondition(resetReply.cancellations == 1 && service.textureReplies.isEmpty,
            "reset must cancel unsubmitted picker and refuse its late URL")
        chooseImage()
        let acceptedReply = PickerProbe.opened.last!
        acceptedReply.finish(.OK); acceptedReply.finish(.OK)
        precondition(service.textureReplies.count == 1, "current selection must submit exactly once")
        chooseImage()
        let closedReply = PickerProbe.opened.last!
        pickerWindow.contentView = nil; pickerWindow.close()
        closedReply.finish(.OK)
        precondition(closedReply.cancellations == 1 && service.textureReplies.count == 1,
            "closed chooser must not submit while the earlier service transaction remains owned by the service")
        let submittedCompletion = service.textureReplies.removeFirst()
        submittedCompletion(true)
        precondition(service.textureReplies.isEmpty,
            "retiring UI must permit the original service to finish its submitted transaction")
        let webDefinition = SteamWorkshopWebPropertyDefinition(key: "renamedWebChoice", title: "choice", kind: .combo,
            runtimeType: "combo", order: 0, minimumValue: nil, maximumValue: nil, allowsFractionalValues: false,
            fractionalPrecision: nil, displayCondition: nil, directoryMode: nil, fileType: nil, defaultValue: .string("B"),
            options: [.init(label: "same", value: .string("A"), displayCondition: nil),
                      .init(label: "same", value: .string("B"), displayCondition: nil)])
        service.webDescriptor = NativeWebDescriptor(propertyDefinitions: [webDefinition])
        service.webValues = [webDefinition.key: .string("B")]
        let webEditor = SteamWorkshopWebPropertyEditorView(record: record)
        let webPopup = descendants(webEditor, NSPopUpButton.self).first!
        print("neighbor Web duplicate-title item count", webPopup.numberOfItems)
        fflush(stdout)
        precondition(webPopup.numberOfItems == 2, "neighbor Web control must preserve distinct values with duplicate labels")
        precondition(webPopup.selectedItem?.representedObject as? String == webDefinition.options[1].id)
        webPopup.selectItem(at: 0); webPopup.sendAction(webPopup.action, to: webPopup.target)
        precondition(service.webEvents.last?.0 == webDefinition.key && service.webEvents.last?.1 == .string("A"))
        print("native controls, identities, conditions, caret, continuous edits, reset and resource receipt PASS")
    }
}
'''


KEYBOARD_HARNESS = r'''
// The full-keyboard-access flag is a process-local environment leaf. No user
// preference is changed; the window, glass host, list and responders are real.
final class ProcessKeyboardApplication: NSApplication {
    override var isFullKeyboardAccessEnabled: Bool { true }
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
@main enum KeyboardProbe {
    @MainActor static func main() {
        let application = ProcessKeyboardApplication.shared
        precondition(NSApp === application && NSApp.isFullKeyboardAccessEnabled)
        func definition(_ key: String, _ kind: SceneUserPropertyKind) -> SceneUserPropertyDefinition {
            .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue, order: 0, index: nil,
                  minimumValue: 0, maximumValue: 1, stepValue: 0.1, allowsFractionalValues: true,
                  fractionalPrecision: 1, displayCondition: nil,
                  defaultValue: kind == .bool ? .bool(false) : .string(""), options: [])
        }
        let definitions = [definition("first", .bool), definition("slider", .slider),
            definition("input", .textInput), definition("color", .color)]
            + (0..<30).map { definition("middle_\($0)", .bool) }
            + [definition("last", .textInput)]
        let catalog = SceneUserPropertyCatalog(definitions: definitions)
        let context = SteamWorkshopScenePropertyContext(catalog: catalog,
            actionableKeys: Set(definitions.map(\.key)), effectiveValues: catalog.defaultValues)
        let editor = SteamWorkshopScenePropertyEditorView(record: .init(id: "own", title: "own"), context: context)
        let owner = SteamWorkshopPropertyPanelController.shared
        owner.show(title: "Scene 属性调节", subtitle: "own", content: editor)
        let window = owner.window!
        window.contentView!.layoutSubtreeIfNeeded()
        window.recalculateKeyViewLoop()
        func descendants<T: NSView>(_ view: NSView, _ kind: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, kind) }
        }
        let list = descendants(editor, NSCollectionView.self).first!
        func control<T: NSView>(_ row: Int, _ kind: T.Type) -> T {
            list.scrollToItems(at: [IndexPath(item: row, section: 0)], scrollPosition: .nearestHorizontalEdge)
            list.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            return descendants(list.item(at: IndexPath(item: row, section: 0))!.view, kind).first!
        }
        let first = control(0, NSButton.self)
        precondition(window.makeFirstResponder(first))
        window.selectNextKeyView(nil)
        precondition(window.firstResponder is WorkshopPropertySlider, "full keyboard access must include the slider")
        window.selectNextKeyView(nil)
        precondition(window.firstResponder is NSTextView, "full keyboard access must include text")
        (window.firstResponder as! NSTextView).doCommand(by: #selector(NSResponder.insertTab(_:)))
        precondition(window.firstResponder is NSColorWell, "actual text command must include the adjacent color well")
        window.selectPreviousKeyView(nil)
        precondition(window.firstResponder is NSTextView)
        let last = control(definitions.count - 1, NSTextField.self)
        let lastInput = descendants(last.superview!, NSTextField.self).first { $0.isEditable }!
        precondition(window.makeFirstResponder(lastInput))
        precondition(!editor.focusNextPropertyControl(from: window.firstResponder, reverse: false),
            "last row must return ownership to the original window key loop")
        let firstAgain = control(0, NSButton.self)
        precondition(window.makeFirstResponder(firstAgain))
        precondition(!editor.focusNextPropertyControl(from: window.firstResponder, reverse: true),
            "first row must return ownership to the original window key loop")
        let chrome = descendants(window.contentView!, NSButton.self).filter { !$0.isDescendant(of: list) }
        precondition(chrome.count == 2)
        // AppKit's native canBecomeKeyView still uses the real system preference,
        // independently of the public getter above. This fixture proves projection
        // and delegation, not system-setting full-access chrome traversal.
        print("native chrome eligibility under unchanged system preference", chrome.map { $0.canBecomeKeyView })
        owner.close()
        precondition(owner.presentationID == nil)
        print("process-local full-access projection and first/last delegation PASS; system full-access chrome not verified")
    }
}
'''


class NativeScenePropertyListTests(unittest.TestCase):
    def test_native_owner_controls_and_events(self):
        self.run_probe(HARNESS)

    def test_full_access_projection_in_property_window(self):
        panel = (ROOT / 'MyWallpaperX/App/ScenePropertyWindowController.swift').read_text()
        panel = panel[panel.index('@MainActor\nfinal class SteamWorkshopPropertyPanelController'):]
        card = (ROOT / 'MyWallpaperX/Shared/UI/InspectorHostViewController.swift').read_text()
        card = card[card.index('final class InspectorHostCardView:'):]
        self.run_probe(KEYBOARD_HARNESS + panel + card)

    def run_probe(self, harness):
        context = SERVICE.read_text().split('\nextension SteamWorkshopService {', 1)[0]
        service = SERVICE.read_text()
        normalization = NORMALIZATION.read_text()
        methods = [
            method_body(service, '    func shouldDisplaySceneProperty('),
            method_body(service, '    func visibleScenePropertyOptions('),
        ]
        names = ['normalizedWebPropertyTitleText', 'normalizedWebDisplayText', 'normalizedWebDisplaySegments',
                 'collapseRepeatedWebDisplaySegments', 'parseWebColorComponents', 'normalizeWebColorTriplet', 'parseHexWebColor']
        for name in names:
            prefix = '    private nonisolated static func ' if name in {'normalizedWebDisplaySegments', 'collapseRepeatedWebDisplaySegments', 'normalizeWebColorTriplet', 'parseHexWebColor'} else '    nonisolated static func '
            methods.append(method_body(normalization, prefix + name + '('))
        with tempfile.TemporaryDirectory(prefix='mwx-native-property-', dir='/private/tmp') as folder:
            path = Path(folder) / 'Probe.swift'
            path.write_text(STUBS + context + '\nextension SteamWorkshopService {\n' + '\n'.join(methods) + '\n}\n' + harness)
            editor = Path(folder) / 'Editor.swift'
            # Substitute only the system dialog leaf so its asynchronous reply
            # can be delivered after hidden/closed; nonce/window/row owner stays production.
            editor.write_text(EDITOR.read_text().replace('NSOpenPanel()', 'PickerProbe()'))
            sources = [ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift',
                       MODULE / 'Web/Core/SteamWorkshopWebPropertyModels.swift',
                       MODULE / 'Web/Core/SteamWorkshopService+WebDisplayConditionSupport.swift',
                       MODULE / 'Web/Core/SteamWorkshopService+WebDisplayConditionParsing.swift',
                       ROOT / 'MyWallpaperX/Shared/UI/InspectorFadingScrollView.swift',
                       MODULE / 'UI/SteamWorkshopWebPropertyEditorView.swift',
                       MODULE / 'UI/WorkshopPropertySlider.swift', editor, path]
            binary = Path(folder) / 'Probe'
            compiled = subprocess.run(['xcrun', 'swiftc', '-Onone', '-parse-as-library', *map(str, sources), '-o', str(binary)],
                                      capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
