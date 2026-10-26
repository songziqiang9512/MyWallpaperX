import AppKit
import QuickLookUI

final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let defaultContentSize = NSSize(width: 1180, height: 760)
    private let composition: WallpaperLibraryWindowComposition
    private let toolbar: WallpaperLibraryWindowToolbar
    private var hasShownWindow = false
    var libraryCommands: WallpaperLibraryCommands { composition.commands }
    var libraryPresentation: WallpaperLibraryPresentation { composition.workspace.presentation }
    func selectedBrowserOrganizationActions() -> WallpaperInspectorActions? { composition.selectedBrowserOrganizationActions() }

    init(wallpaperManager: WallpaperManager) {
        guard let workspace = MyWallpaperXApplication.libraryWorkspace else {
            preconditionFailure("The main window requires the admitted library workspace")
        }
        let composition = WallpaperLibraryWindowComposition(workspace: workspace, manager: wallpaperManager,
            images: .shared, steam: .shared, online: .shared)
        self.composition = composition
        let window = NSWindow(contentViewController: composition.split)
        window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        window.title = "MyWallpaperX"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .shadow
        window.toolbarStyle = .unified
        window.setContentSize(Self.defaultContentSize)
        window.minSize = NSSize(width: 900, height: 650)
        window.isReleasedWhenClosed = true
        window.isRestorable = false
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.level = .normal
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        toolbar = WallpaperLibraryWindowToolbar(window: window, workspace: workspace, commands: composition.commands,
            gridWidth: { [weak composition] in composition?.gridClipWidth ?? 0 },
            makeDirectoryReturnAction: { [weak composition] in composition?.makeDirectoryReturnAction() },
            onlineImages: composition.onlineImages)
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        composition.onGridLayoutChanged = { [weak self] in self?.toolbar.refreshSourceLayout() }
        composition.onNavigationContextChanged = { [weak self] in self?.toolbar.refresh() }
        composition.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }
        if !hasShownWindow { window.center(); hasShownWindow = true }
        MainWindowCoordinator.activate(window: window)
    }

    func windowWillClose(_ notification: Notification) {
        composition.close()
        MainWindowCoordinator.handleWindowWillClose(self)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        composition.commands.relationshipUndo?.undoManager
    }

    var canDeleteSelectedPlaylist: Bool { composition.canDeleteSelectedPlaylist }
    func deleteSelectedPlaylist() { composition.deleteSelectedPlaylist() }

    func performLibraryZoom(_ delta: Int) { toolbar.performZoom(delta: delta) }
    func canZoomLibrary(_ delta: Int) -> Bool { toolbar.canZoom(delta: delta) }
    func focusLibrarySearch() { toolbar.focusSearch() }
    func navigateLibraryPage(_ page: WallpaperLibraryPage) { composition.navigate(to: page) }
    func refreshOnlineImages() { composition.onlineImages.refreshCurrent() }
    var selectedOnlineImageContent: WallpaperContentItem? { composition.onlineImages.selectedContent }
    func inspectSelectedOnlineImage() { composition.onlineImages.inspectSelected() }
    func previewSelectedOnlineImage() { composition.onlineImages.previewSelected() }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        composition.inspector.acceptsPreviewPanelControl(panel)
    }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if let panel { composition.inspector.attach(to: panel) }
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if let panel { composition.inspector.detach(from: panel) }
    }
}
