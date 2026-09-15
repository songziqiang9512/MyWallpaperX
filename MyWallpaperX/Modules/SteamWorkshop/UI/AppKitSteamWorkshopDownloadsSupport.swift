//
//  AppKitSteamWorkshopDownloadsSupport.swift
//  MyWallpaperX
//

import AppKit
import QuickLook
import QuickLookUI

final class SteamWorkshopDownloadsBridge {
    static let shared = SteamWorkshopDownloadsBridge()
    weak var container: AppKitSteamWorkshopDownloadsContainerView?
    var isActive: Bool = false

    func previewSelected() { container?.previewSelected() }
    func moveSelectionByArrowKey(_ keyCode: UInt16) { container?.moveSelectionByArrowKey(keyCode) }

    var hasPreviewableSelection: Bool {
        container?.hasPreviewableSelection ?? false
    }
}

final class SteamWorkshopDownloadsQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = SteamWorkshopDownloadsQuickLookController()

    private var previewURL: URL?
    private var refreshPreview: (() -> URL?)?

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func open(previewURL: URL, refreshPreview: @escaping () -> URL?) {
        self.previewURL = previewURL
        self.refreshPreview = refreshPreview
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let disallowed: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowed).isEmpty else { return false }

        switch event.keyCode {
        case 49:
            close()
            return true
        case 123, 124, 125, 126:
            SteamWorkshopDownloadsBridge.shared.moveSelectionByArrowKey(event.keyCode)
            if let nextURL = refreshPreview?() {
                previewURL = nextURL
                panel.reloadData()
            }
            return true
        case 53:
            close()
            return true
        default:
            return false
        }
    }
}
