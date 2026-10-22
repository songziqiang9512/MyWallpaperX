import AppKit

/// The runner compiles the complete production card and provider. Only the
/// pre-existing model/asset-validation leaves from the prefetch fixture are
/// supplied; no card methods, hierarchy or event bodies are substituted.
@main struct VideoCardInteractionHarness {
    @MainActor static func main() throws {
        initializeNativeAppHarness()
        let card = AppKitWallpaperItem()
        _ = card.view
        let manager = WallpaperManager()
        let provider = AppKitThumbnailProvider(wallpaperManager: manager)
        card.setThumbnailVisible(false)
        card.configure(wallpaper: VideoWallpaper(id: "interaction", path: "/fixture-unread-video.mp4", thumbnailPath: nil),
            isSelected: false, isPlaying: false, isFavorite: false, multiSelectMode: false,
            wallpaperManager: manager, thumbnailProvider: provider)
        let checks = gridCardInteractionChecks(item: card, cardRoot: card.imageContainer,
            outline: card.hoverOutlineView, isHovering: { card.isHovering }, label: "video")
        card.prepareForReuse()
        provider.cancelAllPrefetch()
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
