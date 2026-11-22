import AppKit

/// A read-only projection of the product's committed selection, never a second
/// playback or settings owner. Pending selections cannot replace the cover.
struct StatusBarPanelPresentation {
    static let scale: CGFloat = 0.88
    // Whole-point presentation sizes keep native window rounding from
    // changing the requested geometry across displays.
    static let preferredWidth: CGFloat = (344 * scale).rounded()
    enum Content: Equatable {
        case none
        case video(VideoWallpaper)
        case workshop(SteamWorkshopDownloadRecord)
        case remembered(WallpaperReference, WallpaperContentItem?)
        case still(URL)

        var title: String {
            switch self {
            case .none: return String(localized: "No Wallpaper Playing")
            case let .video(item): return item.displayTitle
            case let .workshop(item): return item.title
            case let .remembered(_, item): return item?.title ?? String(localized: "Last Played Wallpaper")
            case let .still(url): return url.deletingPathExtension().lastPathComponent
            }
        }

        var kind: String {
            switch self {
            case .none: return ""
            case .video: return "Video"
            case let .workshop(item): return item.contentType == .scene ? "Scene" : "Web"
            case let .remembered(_, item):
                switch item?.kind {
                case .image: return String(localized: "Static Wallpaper")
                case .video: return "Video"
                case .web: return "Web"
                case .scene: return "Scene"
                default: return String(localized: "Wallpaper")
                }
            case .still: return String(localized: "Static Wallpaper")
            }
        }

        var isDynamic: Bool {
            switch self {
            case .video, .workshop: return true
            case let .remembered(_, item): return item?.kind == .video || item?.kind == .web || item?.kind == .scene
            case .none, .still: return false
            }
        }

        var hasProperties: Bool {
            if case .workshop = self { return true }
            return false
        }
    }

    let content: Content
    let isStandby: Bool
    let playbackMode: WallpaperManager.PlaybackMode?
    let isPlaying: Bool
    let isUserPaused: Bool
    let isSystemPaused: Bool
    let isSwitching: Bool
    let isRotating: Bool
    let isMuted: Bool
    let volume: Double
    let canNavigate: Bool
    var favoriteReference: WallpaperReference? = nil
    var isFavorite = false
    var canFavorite = false

    var status: String {
        if isSwitching { return content == .none ? String(localized: "Preparing Wallpaper…") : String(localized: "\(content.kind) · Switching…") }
        if content == .none { return String(localized: "Open the main window and choose a wallpaper you like") }
        if isStandby { return String(localized: "\(content.kind) · Last Played · Click to Restore") }
        if !content.isDynamic {
            if isRotating { return isSystemPaused ? String(localized: "Rotation Paused by the System") : isUserPaused ? String(localized: "Rotation paused") : String(localized: "Rotating") }
            return String(localized: "Set as system desktop")
        }
        let state = isSystemPaused ? String(localized: "Paused by the system") : isUserPaused ? String(localized: "Paused") : isPlaying ? String(localized: "Playing") : String(localized: "Restoring…")
        return "\(content.kind) · \(state)"
    }

    var displayedVolume: Double { isMuted ? 0 : volume }

    var canTogglePlayback: Bool {
        isStandby ? !isSwitching : content.isDynamic || isRotating
    }

    var hasPlaybackControls: Bool { isStandby || content.isDynamic || isRotating }

    var playbackHelp: String {
        if isStandby { return String(localized: "Resume Last Played Wallpaper") }
        if isRotating { return isUserPaused ? String(localized: "Resume Rotation") : String(localized: "Pause Rotation") }
        return isUserPaused ? String(localized: "Resume Wallpaper") : String(localized: "Pause Wallpaper")
    }

    var modeSymbol: String {
        switch playbackMode {
        case .loop: return "repeat.1"
        case .sequential: return "list.number"
        case .random: return "shuffle"
        case nil: return "repeat.1"
        }
    }

    var modeHelp: String {
        switch playbackMode {
        case .loop: return String(localized: "Single loop; click to switch to sequential playback")
        case .sequential: return String(localized: "Play in order; click to switch to shuffle")
        case .random: return String(localized: "Shuffle; click to switch to repeat one")
        case nil: return String(localized: "Playback Method")
        }
    }

    var preferredHeight: CGFloat {
        let height: CGFloat = hasPlaybackControls ? (content.isDynamic ? 536 : 500) : content == .none ? 280 : 448
        return (height * Self.scale).rounded()
    }

    static func capture(manager: WallpaperManager, service: SteamWorkshopService,
                        rememberedReference: WallpaperReference? = nil, rememberedContent: WallpaperContentItem? = nil) -> Self {
        var content: Content
        if let committed = manager.playbackSwitch.committed,
           let selection = manager.switchSelections[committed.ticket.id] {
            switch selection {
            case let .video(item): content = .video(item)
            case let .web(id), let .scene(id):
                content = service.downloads.first(where: { $0.id == id }).map(Content.workshop) ?? .none
            case let .systemStill(url): content = .still(url)
            }
        } else { content = .none }

        let isStandby = manager.playbackSwitch.committed == nil && rememberedReference != nil
        if isStandby, let reference = rememberedReference {
            if let item = rememberedContent, item.providerReference.provider == .videoLibrary,
               let video = manager.wallpapers.first(where: { $0.id == item.providerReference.sourceID }) {
                content = .video(video)
            } else if let item = rememberedContent, item.providerReference.provider == .steamWorkshop,
                      let record = service.downloads.first(where: { $0.id == item.providerReference.sourceID }),
                      record.contentType == .web || record.contentType == .scene {
                content = .workshop(record)
            } else { content = .remembered(reference, rememberedContent) }
        }
        let mode = content == .none ? nil : manager.playbackMode()
        let session = manager.libraryPlaybackSequence.committed
        let canNavigate = session.map { current in
            current.snapshot.entries.contains { $0.isPlayable && $0.reference != current.reference }
        } ?? false
        let commands = PlaybackCommandMultiplexer.shared
        return Self(content: content, isStandby: isStandby, playbackMode: mode,
                    isPlaying: !isStandby && commands.isAnyEnginePlaying,
                    isUserPaused: commands.isUserPaused, isSystemPaused: commands.isSystemPaused,
                    isSwitching: manager.playbackSwitch.pending != nil || manager.libraryPlaybackSequence.pending != nil
                        || service.launchPendingRecordID != nil,
                    isRotating: !isStandby && !content.isDynamic && content != .none && manager.libraryRotationEligible,
                    isMuted: PlaybackMuteState.shared.isMuted,
                    volume: min(100, max(0, manager.settings.volume)),
                    canNavigate: canNavigate,
                    favoriteReference: content == .none ? nil : isStandby ? rememberedReference : session?.reference)
    }
}
