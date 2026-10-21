    var currentWallpaperID: String?
    var currentWallpaper: VideoWallpaper?
    var imageTaskID: UUID?
    var imageCancellation: ThumbnailCacheRequestCancellation?
    var loadingPlaceholderWorkItem: DispatchWorkItem?
    weak var thumbnailWallpaperManager: WallpaperManager?
    weak var currentThumbnailProvider: AppKitThumbnailProvider?
    var isThumbnailDemandPaused = false
    var thumbnailRequestIsPending = false
    var isPlaying = false
    var isMultiSelectMode = false
    var isHovering = false
    let thumbnailImageView = NSImageView()
    let placeholderLabel = NSTextField(labelWithString: "生成中...")
    let favoriteBadgeContainer = NSView()
    let favoriteBadge = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let metaLabel = NSTextField(labelWithString: "")
    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) {}
    func updatePlayButtonVisibility() {}
    func applyHoverVisibility(_ value: Bool, animated: Bool) {}
