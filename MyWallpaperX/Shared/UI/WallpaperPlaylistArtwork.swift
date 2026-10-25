import AppKit

/// One image from the original artwork owner. Nil is a pending/unavailable cover.
@MainActor struct WallpaperPlaylistArtwork {
    let image: NSImage?
    var isCustom = false
}
