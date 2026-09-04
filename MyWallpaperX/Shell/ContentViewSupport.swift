//
//  ContentViewSupport.swift
//  MyWallpaperX
//

import QuickLook
import QuickLookUI
import AppKit

enum SelectedItem: Hashable {
    case category(Category)
    case tag(String)
    case silTag(String)          // 图片库专属标签，与视频库 tag 完全独立
    case staticImageLibrary
    case onlineLibrary
    case onlineDownloads         // 在线库已下载项管理
    case steamWorkshop
    case steamSubscribed
    case steamDownloads
}

extension Notification.Name {
    static let appKitRequestScrollToTopForCurrentSelection = Notification.Name("AppKitRequestScrollToTopForCurrentSelection")
    static let appKitLibraryGridScrollToTopAnimationWillStart = Notification.Name("AppKitLibraryGridScrollToTopAnimationWillStart")
    static let appKitLibraryGridScrollToTopAnimationDidEnd = Notification.Name("AppKitLibraryGridScrollToTopAnimationDidEnd")
    static let appKitSelectItemRequested = Notification.Name("AppKitSelectItemRequested")
    static let appOpenSettingsRequested = Notification.Name("AppOpenSettingsRequested")
    /// 在线图库模式切换通知，由 Shell 发出，OnlineLibrary 模块接收
    static let onlineLibraryModeDidChange = Notification.Name("OnlineLibraryModeDidChange")
    /// 在线库视频下载完成，携带本地 URL 和原始播放请求身份，由 Coordinator 中转给视频库
    static let onlineVideoReadyToPlay = Notification.Name("OnlineVideoReadyToPlay")
    /// 当前播放视频路径变化（在线已下载项播放态同步）
    static let onlineDownloadsPlaybackPathDidChange = Notification.Name("OnlineDownloadsPlaybackPathDidChange")
    /// Steam 创意工坊视频播放请求，由 Coordinator 中转给视频库静默导入并播放
    static let steamWorkshopVideoReadyToPlay = Notification.Name("SteamWorkshopVideoReadyToPlay")
    /// Steam 创意工坊 HTML 网页壁纸准备播放，由 Coordinator 中转给 Web 壁纸实验宿主
    static let steamWorkshopWebWallpaperReadyToPlay = Notification.Name("SteamWorkshopWebWallpaperReadyToPlay")
    /// Steam 创意工坊 Scene 壁纸准备渲染，由 Coordinator 启动桌面级 Scene 宿主
    /// userInfo: ["cacheDirectory": URL]（Scene 缓存解包目录，含解释文件和图片资源）
    static let steamWorkshopSceneReadyToRender = Notification.Name("SteamWorkshopSceneReadyToRender")
    /// 图片壁纸库模式切换通知，由 Shell 发出，StaticImageLibrary 模块接收
    static let staticImageLibraryModeDidChange = Notification.Name("StaticImageLibraryModeDidChange")
    /// Steam 创意工坊模式切换通知，由 Shell 发出，Steam 模块接收
    static let steamWorkshopModeDidChange = Notification.Name("SteamWorkshopModeDidChange")
    /// 图片库请求将某张图片设为系统壁纸，由 MainWindowCoordinator 统一执行运行时切换和停播收尾
    static let staticImageWallpaperReadyToApply = Notification.Name("StaticImageWallpaperReadyToApply")
    /// Steam 创意工坊浏览上下文变化通知，用于同步作者工坊返回态与筛选控件状态
    static let steamWorkshopBrowseContextDidChange = Notification.Name("SteamWorkshopBrowseContextDidChange")
}

final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var previewURL: URL?
    
    private override init() {
        super.init()
    }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    @discardableResult
    func openPreview(for wallpaper: VideoWallpaper?) -> Bool {
        // 打开预览只负责把当前选中项映射到 QL panel，不在这里改选择状态。
        guard let targetURL = previewURLIfAvailable(for: wallpaper) else { return false }
        presentPreview(for: targetURL)
        return true
    }

    func syncVisiblePreview(for wallpaper: VideoWallpaper?) {
        // 仅当预览面板已经可见时才同步内容，避免外部状态变化把面板反复抢开。
        guard isVisible else { return }
        guard let targetURL = previewURLIfAvailable(for: wallpaper) else { return }
        guard previewURL != targetURL else { return }
        presentPreview(for: targetURL)
    }

    private func previewURLIfAvailable(for wallpaper: VideoWallpaper?) -> URL? {
        guard let wallpaper else { return nil }
        let targetURL = URL(fileURLWithPath: wallpaper.path)
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
        return targetURL
    }

    private func presentPreview(for targetURL: URL) {
        previewURL = targetURL
        guard let panel = QLPreviewPanel.shared() else {
            return
        }
        // QLPreviewPanel 依赖 dataSource / delegate 持有一致，否则会出现闪现或按键失效。
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
    
    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
    }

    func closePreview() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }

        // 这里接管空格/方向键/ESC，避免系统把事件交回主窗口后再次触发预览开关。
        switch event.keyCode {
        case 49: // Space
            closePreview()
            return true
        case 123, 124, 125, 126: // Arrows
            guard WallpaperManager.shared.moveSingleSelectionByArrowKey(event.keyCode, ignoreSearchFieldState: true) else { return true }
            syncVisiblePreview(for: WallpaperManager.shared.selectedWallpaperForQuickLook)
            return true
        case 53: // ESC
            closePreview()
            return true
        default:
            guard let normalizedArrow = normalizeArrowKeyCode(from: event) else { return false }
            guard WallpaperManager.shared.moveSingleSelectionByArrowKey(normalizedArrow, ignoreSearchFieldState: true) else { return true }
            syncVisiblePreview(for: WallpaperManager.shared.selectedWallpaperForQuickLook)
            return true
        }
    }

    private func normalizeArrowKeyCode(from event: NSEvent) -> UInt16? {
        if [123, 124, 125, 126].contains(event.keyCode) {
            return event.keyCode
        }
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first?.value else {
            return nil
        }
        switch scalar {
        case 0xF702: return 123 // left
        case 0xF703: return 124 // right
        case 0xF701: return 125 // down
        case 0xF700: return 126 // up
        default: return nil
        }
    }
}
