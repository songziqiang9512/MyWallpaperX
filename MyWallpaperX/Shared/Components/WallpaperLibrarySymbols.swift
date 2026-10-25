import AppKit

/// One media meaning for playlist artwork in the directory, sidebar and menus.
@MainActor enum WallpaperLibrarySymbols {
    static let playlist = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil) != nil
        ? "photo.on.rectangle.angled" : "photo.on.rectangle"
}
