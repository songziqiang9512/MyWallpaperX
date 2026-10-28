import Foundation

extension Notification.Name {
    static let appKitRequestScrollToTopForCurrentSelection = Notification.Name("AppKitRequestScrollToTopForCurrentSelection")
    static let appKitLibraryGridScrollToTopAnimationWillStart = Notification.Name("AppKitLibraryGridScrollToTopAnimationWillStart")
    static let appKitLibraryGridScrollToTopAnimationDidEnd = Notification.Name("AppKitLibraryGridScrollToTopAnimationDidEnd")
    static let appKitSelectItemRequested = Notification.Name("AppKitSelectItemRequested")
    static let appOpenSettingsRequested = Notification.Name("AppOpenSettingsRequested")
    /// 在线图库模式切换通知，由 Shell 发出，Pixabay 模块接收
    static let pixabayModeDidChange = Notification.Name("PixabayModeDidChange")
    /// Pixabay视频下载完成，携带本地 URL 和原始播放请求身份，由 Coordinator 中转给视频库
    static let pixabayVideoReadyToPlay = Notification.Name("PixabayVideoReadyToPlay")
    /// 当前播放视频路径变化（在线已下载项播放态同步）
    static let pixabayDownloadsPlaybackPathDidChange = Notification.Name("PixabayDownloadsPlaybackPathDidChange")
    /// Steam 创意工坊视频播放请求，由 Coordinator 中转给视频库静默导入并播放
    static let steamWorkshopVideoReadyToPlay = Notification.Name("SteamWorkshopVideoReadyToPlay")
    /// Steam 创意工坊 HTML 网页壁纸准备播放，由 Coordinator 中转给 Web 壁纸实验宿主
    static let steamWorkshopWebWallpaperReadyToPlay = Notification.Name("SteamWorkshopWebWallpaperReadyToPlay")
    /// Steam 创意工坊 Scene 壁纸准备渲染，由 Coordinator 启动桌面级 Scene 宿主
    /// userInfo: ["cacheDirectory": URL]（Scene 缓存解包目录，含解释文件和图片资源）
    static let steamWorkshopSceneReadyToRender = Notification.Name("SteamWorkshopSceneReadyToRender")
    /// Steam 创意工坊 Scene 下载入库完成，由装配层触发 daemon 预热（best-effort）
    static let steamWorkshopSceneDownloadCompleted = Notification.Name("SteamWorkshopSceneDownloadCompleted")
    /// 图片壁纸库模式切换通知，由 Shell 发出，StaticImageLibrary 模块接收
    static let staticImageLibraryModeDidChange = Notification.Name("StaticImageLibraryModeDidChange")
    /// Steam 创意工坊模式切换通知，由 Shell 发出，Steam 模块接收
    static let steamWorkshopModeDidChange = Notification.Name("SteamWorkshopModeDidChange")
    /// 图片库请求将某张图片设为系统壁纸，由 MainWindowCoordinator 统一执行运行时切换和停播收尾
    static let staticImageWallpaperReadyToApply = Notification.Name("StaticImageWallpaperReadyToApply")
    /// Steam 创意工坊浏览上下文变化通知，用于同步作者工坊返回态与筛选控件状态
    static let steamWorkshopBrowseContextDidChange = Notification.Name("SteamWorkshopBrowseContextDidChange")
}
