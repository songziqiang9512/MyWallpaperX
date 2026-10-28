import AppKit

/// Only Launch Services/application launch I/O is controlled. The complete
/// production factory creates native menus and dispatches real ActionMenuItems.
@MainActor final class OpenWithWorkspaceLeaf {
    static let shared = OpenWithWorkspaceLeaf()
    var handlers: [URL: [URL]] = [:], defaults: [URL: URL] = [:]
    var applicationReads: [URL] = [], defaultReads: [URL] = []
    var opens: [(files: [URL], application: URL)] = []
    var completions: [((NSRunningApplication?, Error?) -> Void)?] = []
    func urlsForApplications(toOpen url: URL) -> [URL] { applicationReads.append(url); return handlers[url] ?? [] }
    func urlForApplication(toOpen url: URL) -> URL? { defaultReads.append(url); return defaults[url] }
    func icon(forFile path: String) -> NSImage { NSImage(size: .init(width: 32, height: 32)) }
    func open(_ urls: [URL], withApplicationAt application: URL, configuration: NSWorkspace.OpenConfiguration,
              completionHandler: ((NSRunningApplication?, Error?) -> Void)?) {
        opens.append((urls, application)); completions.append(completionHandler)
    }
}

// ACTUAL_OPEN_WITH_FACTORY

@main private enum WallpaperOpenWithChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let source = OpenWithWorkspaceLeaf.shared
        let image = URL(fileURLWithPath: "/owned/image.png"), video = URL(fileURLWithPath: "/owned/video.mov")
        let first = URL(fileURLWithPath: "/Applications/First Viewer.app")
        let shared = URL(fileURLWithPath: "/Applications/Shared Viewer.app")
        let imageOnly = URL(fileURLWithPath: "/Applications/Image Viewer.app")
        source.handlers = [image: [imageOnly, shared, first, shared], video: [first, shared]]
        source.defaults = [image: shared, video: shared]
        var selection = [image, video, image], permits = true, reports: [String] = []
        var reportsOnMain = true
        let root = WallpaperOpenWithMenu.make(for: selection, permitsAction: { permits }, reportError: {
            reports.append($0.localizedDescription); reportsOnMain = reportsOnMain && Thread.isMainThread
        })!
        let menu = root.submenu!, rows = menu.items
        var checks = ["system-application-intersection-keeps-one-default-and-no-incompatible-app":
            root.title == "打开方式" && root.isEnabled && rows.count == 2 && rows[0].title.contains("Shared Viewer")
                && rows[0].title.hasSuffix("（默认）") && rows[1].title.contains("First Viewer")
                && rows.allSatisfy { $0.image?.size == NSSize(width: 16, height: 16) }]
        checks["each-distinct-file-uses-only-system-handler-and-default-resolution-once"] = source.applicationReads == [image, video]
            && source.defaultReads == [image, video]
        selection = [URL(fileURLWithPath: "/new-selection.jpg")]
        _ = NSApp.sendAction(rows[0].action!, to: rows[0].target, from: rows[0])
        checks["one-native-menu-command-opens-all-original-files-in-the-fixed-application"] = source.opens.count == 1
            && source.opens[0].files == [image, video] && source.opens[0].application == shared && source.opens[0].files != selection
        permits = false
        _ = NSApp.sendAction(rows[1].action!, to: rows[1].target, from: rows[1])
        checks["revoked-source-selection-prevents-a-held-submenu-from-opening-files"] = source.opens.count == 1
        source.completions[0]?(nil, NSError(domain: "open-with-test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Application rejected the fixed files"]))
        for _ in 0..<50 where reports.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        checks["asynchronous-native-open-failure-is-reported-on-main-without-retargeting"] = reports == ["Application rejected the fixed files"]
            && reportsOnMain && source.opens.count == 1 && source.opens[0].files == [image, video]
        source.defaults[video] = first
        let differentDefaults = WallpaperOpenWithMenu.make(for: [image, video])!
        checks["different-file-defaults-do-not-invent-a-common-default-application"] = differentDefaults.submenu?.items.count == 2
            && differentDefaults.submenu!.items.allSatisfy { !$0.title.hasSuffix("（默认）") }
        source.handlers[video] = []
        checks["no-common-system-handler-keeps-open-with-disabled"] = WallpaperOpenWithMenu.make(for: [image, video])?.isEnabled == false
        let invalidApplicationReads = source.applicationReads.count, invalidDefaultReads = source.defaultReads.count
        checks["empty-or-nonfile-targets-never-query-or-launch-applications"] = WallpaperOpenWithMenu.make(for: []) == nil
            && WallpaperOpenWithMenu.make(for: [URL(string: "https://example.invalid/video.mov")!]) == nil && source.opens.count == 1
            && source.applicationReads.count == invalidApplicationReads && source.defaultReads.count == invalidDefaultReads
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
