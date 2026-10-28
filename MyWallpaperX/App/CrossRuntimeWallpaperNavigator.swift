import Foundation

/// Global controls follow the current playback mode in the original sequence.
/// Source files are prepared only for the selected candidate.
@MainActor
enum CrossRuntimeWallpaperNavigator {
    static func navigate(_ direction: ManualNavigationDirection) {
        WallpaperManager.shared.navigateLibraryPlayback(direction, policy: .randomHistory)
    }
}
