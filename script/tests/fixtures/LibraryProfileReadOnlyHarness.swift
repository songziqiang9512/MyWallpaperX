import AppKit
import Foundation
import UniformTypeIdentifiers

// Actual command/Coordinator methods and editing projection run below. The
// panel and downstream importer only record routing; no real UI or worker runs.
// ACTUAL_LIBRARY_PAGE

@MainActor final class ImportCollectionsLeaf { var isResetting = false }
@MainActor final class ImportPresentation {
    struct State { var allowsEditing = true }
    var state = State()
    var page: WallpaperLibraryPage = .videos
    let collections: ImportCollectionsLeaf?
    init(_ collections: ImportCollectionsLeaf?) { self.collections = collections }
    // ACTUAL_CAN_EDIT
}
@MainActor final class WallpaperLibraryWorkspace {
    struct Relationships { var resetEpoch = UUID() }
    var relationships = Relationships()
    let presentation: ImportPresentation
    init(_ collections: ImportCollectionsLeaf?) { presentation = ImportPresentation(collections) }
}
@MainActor final class ImportUndoLeaf {
    final class Manager { var isApplyingTransaction = false }
    let undoManager = Manager()
}
@MainActor enum SILService { static var allowedUTTypes: [UTType] { [.image] } }

@MainActor final class RecordingImportPanel {
    static var created = 0
    static var response: NSApplication.ModalResponse = .cancel
    static var selection: [URL] = []
    static var duringModal: (() -> Void)?
    var allowsMultipleSelection = false
    var canChooseFiles = false
    var canChooseDirectories = false
    var allowedContentTypes: [UTType] = []
    var message = "", title = ""
    var urls: [URL] { Self.selection }
    init() { Self.created += 1 }
    static func reset() { created = 0; response = .cancel; selection = []; duringModal = nil }
    func runModal() -> NSApplication.ModalResponse { Self.duringModal?(); return Self.response }
    func beginSheetModal(for window: NSWindow, completionHandler: (NSApplication.ModalResponse) -> Void) {
        completionHandler(runModal())
    }
}

@MainActor final class WallpaperLibraryImportCoordinator {
    struct Request { let urls: [URL]; let page: WallpaperLibraryPage }
    let workspace: WallpaperLibraryWorkspace
    var requests: [Request] = []
    var hostReads = 0
    init(_ workspace: WallpaperLibraryWorkspace) { self.workspace = workspace }
    func hostWindow() -> NSWindow? { hostReads += 1; return nil }
    func importFiles(_ urls: [URL], to page: WallpaperLibraryPage) { requests.append(.init(urls: urls, page: page)) }
    // ACTUAL_COORDINATOR_METHODS
}

@MainActor final class WallpaperLibraryCommands {
    let workspace: WallpaperLibraryWorkspace
    let imports: WallpaperLibraryImportCoordinator
    var relationshipUndo: ImportUndoLeaf?
    init(_ workspace: WallpaperLibraryWorkspace) {
        self.workspace = workspace
        imports = WallpaperLibraryImportCoordinator(workspace)
    }
    // ACTUAL_COMMAND_METHODS
}

@main struct LibraryProfileReadOnlyHarness {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = root.appendingPathComponent("source-metadata.json")
        let selected = root.appendingPathComponent("selected-source.mp4")
        let bytes = Data("original-metadata".utf8), media = Data("owned route input".utf8)
        try bytes.write(to: source); try media.write(to: selected)
        var checks: [String: Bool] = [:]

        let recovery = WallpaperLibraryWorkspace(nil), recoveryCommands = WallpaperLibraryCommands(recovery)
        RecordingImportPanel.reset()
        recoveryCommands.importFiles()
        recoveryCommands.importFiles([selected])
        recoveryCommands.imports.chooseFiles(to: .videos)
        checks["recovery-command-refuses-panel-and-import-route"] = !recoveryCommands.canImport
            && !recoveryCommands.canOrganize && RecordingImportPanel.created == 0
        checks["recovery-denial-never-dispatches-worker-or-reads-host"] = recoveryCommands.imports.requests.isEmpty
            && recoveryCommands.imports.hostReads == 0 && recovery.presentation.page == .videos
        checks["recovery-ui-denial-keeps-original-source-bytes"] = try Data(contentsOf: source) == bytes
            && Data(contentsOf: selected) == media

        let collections = ImportCollectionsLeaf(), workspace = WallpaperLibraryWorkspace(collections)
        let commands = WallpaperLibraryCommands(workspace)
        RecordingImportPanel.reset()
        commands.importFiles([selected, selected])
        checks["editable-typed-urls-preserve-order-without-panel"] = commands.canImport && commands.imports.requests.count == 1
            && commands.imports.requests[0].urls == [selected, selected] && commands.imports.requests[0].page == .videos
            && RecordingImportPanel.created == 0 && commands.imports.hostReads == 0

        RecordingImportPanel.reset()
        RecordingImportPanel.selection = [selected]
        commands.importFiles()
        checks["cancelled-panel-does-not-dispatch-import"] = RecordingImportPanel.created == 1
            && commands.imports.requests.count == 1 && commands.imports.hostReads == 1

        RecordingImportPanel.reset()
        RecordingImportPanel.response = .OK; RecordingImportPanel.selection = [selected]
        commands.importFiles()
        checks["editable-nil-entry-dispatches-panel-selection"] = RecordingImportPanel.created == 1
            && commands.imports.requests.count == 2 && commands.imports.requests[1].urls == [selected]
            && commands.imports.requests[1].page == .videos

        RecordingImportPanel.reset()
        RecordingImportPanel.response = .OK; RecordingImportPanel.selection = [selected]
        RecordingImportPanel.duringModal = { workspace.relationships.resetEpoch = UUID() }
        commands.importFiles()
        checks["panel-reset-epoch-rejects-late-selection"] = RecordingImportPanel.created == 1
            && commands.imports.requests.count == 2

        RecordingImportPanel.reset()
        workspace.presentation.page = .favorites
        RecordingImportPanel.response = .OK; RecordingImportPanel.selection = [selected]
        RecordingImportPanel.duringModal = { workspace.presentation.page = .images }
        commands.importFiles()
        checks["panel-page-change-retains-original-target"] = commands.imports.requests.count == 3
            && commands.imports.requests[2].page == .favorites && workspace.presentation.page == .images

        RecordingImportPanel.reset()
        let accepted = commands.imports.requests.count, reads = commands.imports.hostReads
        workspace.presentation.state.allowsEditing = false
        commands.importFiles(); commands.importFiles([selected]); commands.imports.chooseFiles(to: .images)
        checks["disabled-editing-refuses-command-and-coordinator"] = !commands.canImport
            && RecordingImportPanel.created == 0 && commands.imports.requests.count == accepted
            && commands.imports.hostReads == reads

        workspace.presentation.state.allowsEditing = true; collections.isResetting = true
        commands.importFiles(); commands.importFiles([selected]); commands.imports.chooseFiles(to: .images)
        checks["reset-in-progress-refuses-command-and-coordinator"] = !commands.canImport
            && RecordingImportPanel.created == 0 && commands.imports.requests.count == accepted
        collections.isResetting = false

        let undo = ImportUndoLeaf(); undo.undoManager.isApplyingTransaction = true
        commands.relationshipUndo = undo
        commands.importFiles(); commands.importFiles([selected])
        checks["undo-transaction-blocks-both-command-routes"] = !commands.canImport
            && RecordingImportPanel.created == 0 && commands.imports.requests.count == accepted
        undo.undoManager.isApplyingTransaction = false
        checks["ending-undo-restores-original-command-admission"] = commands.canImport

        let unsupported: [WallpaperLibraryPage] = [.downloads, .workshop, .pixabay, .wallhaven, .pixiv, .playlists]
        var refused = true
        for page in unsupported {
            workspace.presentation.page = page
            commands.importFiles(); commands.importFiles([selected]); commands.imports.chooseFiles(to: page)
            refused = refused && !commands.canImport
        }
        checks["unsupported-pages-never-open-panel-or-dispatch"] = refused && RecordingImportPanel.created == 0
            && commands.imports.requests.count == accepted && commands.imports.hostReads == reads
        checks["entry-tests-preserve-all-owned-source-bytes"] = try Data(contentsOf: source) == bytes
            && Data(contentsOf: selected) == media
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
