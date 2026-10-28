import AppKit

/// Launch Services owns application discovery and defaults. A menu holds only
/// the files the user clicked; opening another selection never retargets it.
@MainActor enum WallpaperOpenWithMenu {
    static func make(for urls: [URL], permitsAction: @escaping () -> Bool = { true },
                     reportError: @escaping @MainActor @Sendable (Error) -> Void = { _ = NSApp.presentError($0) }) -> NSMenuItem? {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return nil }
        var seenFiles = Set<URL>()
        let files = urls.filter { seenFiles.insert($0).inserted }
        let workspace = NSWorkspace.shared
        var seenApplications = Set<URL>()
        var applications = workspace.urlsForApplications(toOpen: files[0]).filter { seenApplications.insert($0).inserted }
        for file in files.dropFirst() {
            if applications.isEmpty { break }
            let handlers = Set(workspace.urlsForApplications(toOpen: file))
            applications.removeAll { !handlers.contains($0) }
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
        item.submenu = menu
        item.isEnabled = !applications.isEmpty
        guard !applications.isEmpty else { return item }
        let defaults = files.map { workspace.urlForApplication(toOpen: $0) }
        let defaultApplication = defaults.first.flatMap { $0 }.flatMap { candidate in
            defaults.allSatisfy { $0 == candidate } ? candidate : nil
        }
        if let defaultApplication, let index = applications.firstIndex(of: defaultApplication) {
            applications.remove(at: index); applications.insert(defaultApplication, at: 0)
        }
        for application in applications {
            let name = FileManager.default.displayName(atPath: application.path)
            let title = application == defaultApplication ? "\(name)（默认）" : name
            let item = ActionMenuItem(title: title, symbol: "") {
                guard permitsAction() else { return }
                workspace.open(files, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    guard let error else { return }
                    Task { @MainActor in reportError(error) }
                }
            }
            item.image = workspace.icon(forFile: application.path).copy() as? NSImage
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        return item
    }
}
