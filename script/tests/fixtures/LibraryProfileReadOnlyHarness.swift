import Foundation
import AppKit

// Independent existing UI guards remain covered after the old synchronous
// schema5 relation writer retires. Actual profile apply has its own real gate.
final class WallpaperManager {
    var allowsLibraryMutation = false
    var migrationRecoveryMessage: String? = "recovery-original-source"
    var wallpapers: [VideoWallpaper] = []
    var tags: [String] = []
    var writes = 0
    var readOnlyReports = 0
    var isMultiSelectMode = true
    var currentSelectionContext = WallpaperSelectionContext()
    var selectionReads = 0
    func reportMigrationReadOnly(in window: NSWindow?) { readOnlyReports += 1 }
    func selectedLibraryWallpaperIndices(for context: WallpaperSelectionContext) -> [Int] { selectionReads += 1; return Array(wallpapers.indices) }
    func exitMultiSelectMode() { isMultiSelectMode = false }
    func normalizedTagList(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }
    func saveTags() { writes += 1 }
    func saveWallpapers() { writes += 1 }
    func makeImportOpenPanel() -> NSOpenPanel { preconditionFailure("Recovery must not present a file panel") }
    func processImportedVideos(from urls: [URL], presentingIn window: NSWindow?, context: ImportContext) { writes += 1 }
    // PRODUCTION_IMPORT_UI
}
enum ImportContext { case library }
struct WallpaperSelectionContext {}
enum MainWindowCoordinator { static func mainWindow() -> NSWindow? { nil } }
@main struct LibraryProfileReadOnlyHarness {
    static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let manager = WallpaperManager()
        var checks: [String: Bool] = [:]
        let source = root.appendingPathComponent("source-metadata.json")
        let bytes = Data("original-metadata".utf8); try bytes.write(to: source)
        manager.importVideos()
        checks["readonly-import-ui-reports-without-opening-file-panel"] = manager.readOnlyReports == 1 && manager.selectionReads == 0 && manager.isMultiSelectMode
            && manager.wallpapers.isEmpty && manager.tags.isEmpty
        checks["recovery-ui-denial-keeps-original-source-bytes"] = try Data(contentsOf: source) == bytes
        checks["recovery-ui-denial-performs-no-old-source-writes"] = manager.writes == 0
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
