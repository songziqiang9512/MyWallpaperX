import AppKit

/// Fixed-content actions supplied by the App composition. Source Inspectors
/// keep their layouts and metadata, without owning user relationships.
struct WallpaperInspectorActions {
    struct State: Equatable {
        let isPlaying: Bool
        var isSwitching = false
        let isFavorite: Bool
        let canPerformPrimary: Bool
        let canFavorite: Bool
        let canOrganize: Bool
        let playlistNames: [String]

        var primaryTitle: String { isPlaying ? "停止播放" : "设为壁纸" }
        var primarySymbolName: String { isPlaying ? "stop.fill" : "photo.fill" }
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
