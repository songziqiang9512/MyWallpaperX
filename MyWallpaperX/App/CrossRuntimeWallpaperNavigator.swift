import Foundation

/// Global navigation delegates candidate order and failure advance to the one
/// sequence owner. Source files are prepared only for the selected candidate.
@MainActor
enum CrossRuntimeWallpaperNavigator {
    static func navigate(_ direction: ManualNavigationDirection) {
        WallpaperManager.shared.navigateLibraryPlayback(direction, policy: .adjacent)
    }
}
