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
    var isSwitching = false
    var isMultiSelectMode = false
    var isHovering = false
    let thumbnailImageView = NSImageView()
    let placeholderLabel = NSTextField(labelWithString: "生成中...")
    let view = NSView()
    var currentTitle = ""
    var currentMetadata = ""
    func updateControlBarContent() {}
    func layoutThumbnail() {}
    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) {}
    func updatePlayButtonVisibility() {}
    func applyHoverVisibility(_ value: Bool, animated: Bool) {}
