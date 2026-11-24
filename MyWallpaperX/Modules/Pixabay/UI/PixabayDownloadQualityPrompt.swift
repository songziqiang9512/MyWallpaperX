import AppKit

@MainActor func presentPixabayDownload(_ item: PixabayVideoItem, service: PixabayService, in window: NSWindow?) {
    guard !service.downloadingIDs.contains(item.id) else { return }
    let options = service.downloadedIDs.contains(item.id) ? [] : item.videoDownloadOptions
    guard options.count > 1 else {
        service.download(item: item, tier: options.first?.tier)
        return
    }

    let title = String(localized: "Video Quality")
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    popup.setAccessibilityLabel(title)
    popup.addItems(withTitles: options.map { option in
        let tier: String = switch option.tier {
        case .large: String(localized: "Large")
        case .medium: String(localized: "Medium")
        case .small: String(localized: "Small")
        case .tiny: String(localized: "Tiny")
        }
        let resolution = option.width > 0 && option.height > 0 ? "\(option.width) × \(option.height)" : nil
        let fileSize = option.expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [tier, resolution, fileSize].compactMap { $0 }.joined(separator: " · ")
    })
    popup.selectItem(at: 0)
    popup.sizeToFit()
    let alert = makeAppAlert(title: title, message: item.displayTitle,
        buttons: [String(localized: "Download Video"), String(localized: "Cancel")], accessoryView: popup)
    presentAppAlert(alert, in: window) { response in
        guard response == .alertFirstButtonReturn, options.indices.contains(popup.indexOfSelectedItem) else { return }
        service.download(item: item, tier: options[popup.indexOfSelectedItem].tier)
    }
}
