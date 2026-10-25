import AppKit

/// A read-only projection of the product's committed selection, never a second
/// playback or settings owner. Pending selections cannot replace the cover.
struct StatusBarPanelPresentation {
    enum Content: Equatable {
        case none
        case video(VideoWallpaper)
        case workshop(SteamWorkshopDownloadRecord)
        case remembered(WallpaperReference, WallpaperContentItem?)
        case still(URL)

        var title: String {
            switch self {
            case .none: return "还没有正在播放的壁纸"
            case let .video(item): return item.displayTitle
            case let .workshop(item): return item.title
            case let .remembered(_, item): return item?.title ?? "上次播放的壁纸"
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
                case .image: return "静态壁纸"
                case .video: return "Video"
                case .web: return "Web"
                case .scene: return "Scene"
                default: return "壁纸"
                }
            case .still: return "静态壁纸"
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

    var status: String {
        if isSwitching { return content == .none ? "正在准备壁纸…" : "\(content.kind) · 正在切换…" }
        if content == .none { return "打开主界面，选择一张喜欢的壁纸" }
        if isStandby { return "\(content.kind) · 上次播放 · 点按恢复" }
        if !content.isDynamic {
            if isRotating { return isSystemPaused ? "系统已暂停轮换" : isUserPaused ? "已暂停轮换" : "正在轮换" }
            return "已设为系统桌面"
        }
        let state = isSystemPaused ? "系统已暂停" : isUserPaused ? "已暂停" : isPlaying ? "正在播放" : "正在恢复…"
        return "\(content.kind) · \(state)"
    }

    var displayedVolume: Double { isMuted ? 0 : volume }

    var canTogglePlayback: Bool {
        isStandby ? !isSwitching : content.isDynamic || isRotating
    }

    var hasPlaybackControls: Bool { isStandby || content.isDynamic || isRotating }

    var playbackHelp: String {
        if isStandby { return "恢复上次播放的壁纸" }
        if isRotating { return isUserPaused ? "继续轮换" : "暂停轮换" }
        return isUserPaused ? "继续播放壁纸" : "暂停壁纸"
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
        case .loop: return "单循环；点按切换为顺序播放"
        case .sequential: return "顺序播放；点按切换为随机播放"
        case .random: return "随机播放；点按切换为单循环"
        case nil: return "播放方式"
        }
    }

    var preferredHeight: CGFloat { hasPlaybackControls ? (content.isDynamic ? 536 : 500) : content == .none ? 280 : 448 }

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
                    canNavigate: canNavigate)
    }
}
