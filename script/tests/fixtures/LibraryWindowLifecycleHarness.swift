import AppKit

// The main window is hidden, not retired: closing must keep the live
// controller/composition so an app reopen revives working controls.

final class WallpaperManager {
    static let shared = WallpaperManager()
}

final class WallpaperEngine {
    static let shared = WallpaperEngine()
    func refreshPlaybackState() {}
}

@MainActor final class MainWindowController: NSWindowController {
    static var instances: [MainWindowController] = []
    var showCount = 0

    init(wallpaperManager: WallpaperManager) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        super.init(window: window)
        MainWindowController.instances.append(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) { showCount += 1 }
}

extension Notification.Name {
    static let pixabayModeDidChange = Notification.Name("fixture-pixabay-mode")
    static let steamWorkshopModeDidChange = Notification.Name("fixture-steam-mode")
}

final class StubOnlineImages { var closes = 0; func close() { closes += 1 } }
final class StubNotice { var dismisses = 0; func dismiss() { dismisses += 1 } }
final class StubInspector {
    var closes = 0
    func closeInspector() { closes += 1 }
    func closePreview() { closes += 1 }
}
final class StubArtwork {
    var demandClears = 0
    func setDemand(sourceToken: UUID, playlistIDs: [UUID]) { demandClears += 1 }
    func updateCurrentList(first: UUID?) {}
}
final class StubCatalog {
    var cleared = 0
    func setVisibleReferences(_ references: [Int], sourceToken: UUID) { cleared += 1 }
}
final class StubPresentation { var page = "workshop" }
final class StubWorkspace {
    let catalog = StubCatalog()
    let presentation = StubPresentation()
}
final class StubAdapter {
    var clears = 0
    func updateViewport(visible: [Int], prefetch: [Int]) { clears += 1 }
}
final class StubPicker { var closes = 0; func close() { closes += 1 } }
final class StubPlaylists { var closes = 0; func close() { closes += 1 } }
final class StubCommands { let playlists: StubPlaylists? = StubPlaylists() }

final class FakeComposition {
    var isSuspended = false
    var lastRenderSignature: Int? = 1
    var publishedPages: [String] = []
    var renders = 0
    var subscriptions = Set<Int>()
    var windowObservers: [NSObjectProtocol] = []
    var windowVisibility: NSObject?
    let onlineImages = StubOnlineImages()
    let creationNotice = StubNotice()
    let inspector = StubInspector()
    let artwork = StubArtwork()
    let workspace = StubWorkspace()
    let adapter = StubAdapter()
    let picker: StubPicker? = StubPicker()
    let commands = StubCommands()
    let sidebarDemand = UUID(), directoryDemand = UUID(), gridDemand = UUID(), headerDemand = UUID()

    private func publishRemoteMode(_ page: String) { publishedPages.append(page) }
    private func render() { renders += 1 }

    // EXTRACTED_LIFECYCLE_METHODS
}

@main
struct LibraryWindowLifecycleChecks {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        var checks: [String: Bool] = [:]

        MainWindowCoordinator.mainWindowController = nil
        MainWindowController.instances.removeAll()
        let stale = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
                             styleMask: [.titled], backing: .buffered, defer: false)
        stale.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        stale.close()
        MainWindowCoordinator.activateMainWindow()
        let created = MainWindowCoordinator.mainWindowController
        checks["activationCreatesFreshController"] = created != nil
            && MainWindowController.instances.count == 1 && created?.showCount == 1 && created?.window !== stale

        let first = created
        if let first {
            MainWindowCoordinator.handleWindowWillClose(first)
            checks["closeKeepsLiveController"] = MainWindowCoordinator.mainWindowController === first
                && MainWindowCoordinator.mainWindow() === first.window
            MainWindowCoordinator.activateMainWindow()
            checks["reopenReusesLiveController"] = MainWindowCoordinator.mainWindowController === first
                && first.showCount == 2 && MainWindowController.instances.count == 1
        }

        MainWindowCoordinator.mainWindowController = nil
        checks["noControllerNoWindow"] = MainWindowCoordinator.mainWindow() == nil

        let fake = FakeComposition()
        fake.subscriptions = [1, 2]
        fake.windowObservers = [NotificationCenter.default.addObserver(
            forName: Notification.Name("fixture-lifecycle"), object: nil, queue: nil) { _ in }]
        fake.suspendForWindowClose()
        checks["suspendKeepsSubscriptions"] = fake.subscriptions == Set([1, 2])
            && fake.windowObservers.count == 1 && fake.isSuspended
        checks["suspendReleasesTransientDemand"] = fake.onlineImages.closes == 1
            && fake.artwork.demandClears == 3 && fake.adapter.clears == 1
            && fake.workspace.catalog.cleared == 1 && fake.commands.playlists?.closes == 1
        fake.resumeAfterWindowOpen()
        checks["resumeRestoresRendering"] = !fake.isSuspended && fake.lastRenderSignature == nil
            && fake.publishedPages == ["workshop"] && fake.renders == 1

        let data = try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
