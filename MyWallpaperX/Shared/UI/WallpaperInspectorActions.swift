import AppKit

/// Fixed-content actions supplied by the App composition. Source Inspectors
/// keep their layouts and metadata, without owning user relationships.
struct WallpaperInspectorActions {
    struct State: Equatable {
        let isPlaying: Bool
        let isFavorite: Bool
        let canPerformPrimary: Bool
        let canFavorite: Bool
        let canOrganize: Bool
        let playlistNames: [String]
    }

    let state: State
    let onPrimary: () -> Void
    let onToggleFavorite: () -> Void
    let onChoosePlaylist: (NSView?) -> Void
    /// Native context menus supply a cell-binding check to every actionable
    /// leaf; inspector buttons keep their anchored chooser action.
    var makePlaylistMenu: ((@escaping () -> Bool) -> NSMenu?)? = nil
    var onRestoreLibrary: (() -> Void)? = nil
}
