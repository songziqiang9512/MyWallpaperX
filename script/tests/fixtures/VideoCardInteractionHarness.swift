import AppKit

/// The runner compiles the complete production card and provider. Only the
/// pre-existing model/asset-validation leaves from the prefetch fixture are
/// supplied; no card methods, hierarchy or event bodies are substituted.
@main struct VideoCardInteractionHarness {
    @MainActor static func main() throws {
        initializeNativeAppHarness()
        let card = AppKitWallpaperItem()
        _ = card.view
        var checks: [String: Bool] = ["video.idle-card-has-no-glass-badge": card.playActionButton == nil]
        let manager = WallpaperManager()
        let provider = AppKitThumbnailProvider(wallpaperManager: manager)
        card.setThumbnailVisible(false)
        card.configure(wallpaper: VideoWallpaper(id: "interaction", path: "/fixture-unread-video.mp4", thumbnailPath: nil),
            isSelected: false, isPlaying: false, isFavorite: false, multiSelectMode: false,
            wallpaperManager: manager, thumbnailProvider: provider)
        checks.merge(gridCardInteractionChecks(item: card, cardRoot: card.imageContainer,
            outline: card.hoverOutlineView, isHovering: { card.isHovering }, label: "video")
        ) { _, new in new }
        let firstBadge = card.playActionButton
        checks["video.first-hover-builds-badge-at-current-size"] = firstBadge != nil
            && firstBadge!.frame == card.playActionFrame && firstBadge!.frame.width > 20
        card.refreshGridHover(isScrolling: true)
        checks["video.scroll-detaches-native-hover-tracking"] = card.imageContainer.trackingAreas.isEmpty
        card.applyPlayingState(isPlaying: true)
        checks["video.playing-stays-visible-without-hover"] = firstBadge?.isHidden == false
            && firstBadge?.alphaValue == 1 && firstBadge?.isPlaying == true
        if let badge = firstBadge {
            let center = NSPoint(x: badge.frame.midX, y: badge.frame.midY)
            checks["video.playing-hit-target-survives-lazy-creation"] = card.shouldTriggerPlayAction(at: center)
            card.applySelectionState(isSelected: true, multiSelectMode: true)
            checks["video.multi-select-disables-play-target"] = badge.isHidden && !card.shouldTriggerPlayAction(at: center)
            card.applySelectionState(isSelected: false, multiSelectMode: false)
            card.refreshGridHover(isScrolling: false)
            checks["video.restore-does-not-duplicate-tracking-or-badge"] = card.playActionButton === badge
                && card.imageContainer.trackingAreas.count == 1
        }
        card.prepareForReuse()
        checks["video.reuse-clears-badge-state-and-hit-target"] = card.playActionButton === firstBadge
            && firstBadge?.isHidden == true && firstBadge?.isPlaying == false
        let playingCard = AppKitWallpaperItem()
        playingCard.view.frame.size = NSSize(width: 230, height: 180)
        playingCard.viewDidLayout()
        playingCard.setThumbnailVisible(false)
        playingCard.configure(wallpaper: VideoWallpaper(id: "multi", path: "/fixture-unread-video.mp4", thumbnailPath: nil),
            isSelected: true, isPlaying: true, isFavorite: false, multiSelectMode: true,
            wallpaperManager: manager, thumbnailProvider: provider)
        checks["video.multi-select-does-not-build-first-playing-badge"] = playingCard.playActionButton == nil
        playingCard.applySelectionState(isSelected: false, multiSelectMode: false)
        checks["video.leaving-multi-select-first-shows-playing-badge"] = playingCard.playActionButton?.isHidden == false
            && playingCard.playActionButton?.isPlaying == true && playingCard.playActionButton?.alphaValue == 1
        playingCard.applyPlayingState(isPlaying: false)
        checks["video.stop-without-hover-hides-playing-badge"] = playingCard.playActionButton?.isHidden == true
            && playingCard.playActionButton?.alphaValue == 0
        playingCard.prepareForReuse()
        provider.cancelAllPrefetch()
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
