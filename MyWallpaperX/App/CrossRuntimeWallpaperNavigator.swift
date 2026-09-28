import Foundation

/// 全局「上一张/下一张」导航：视频库与已安装工坊 Web/Scene 单品统一
/// 轮换（F1-F12 热键、状态栏与菜单栏共用）。
///
/// 切换源：`[视频库全部条目] + [工坊 web/scene 单品]` 两段环形序列。
/// 视频段用库存储顺序；工坊段用 downloads 现有排序（updatedAt 降序）。
/// 工坊视频项播放时会导入视频库，不进序列避免双计；依赖缺失项与
/// `cachedCanLaunchDownloadRecord` 判定不可播放的工坊项跳过——与
/// setAsWallpaper 的拒播判据对齐，避免轮到会被静默拒播的项后该方向
/// 卡死，也避免轮换被"缺依赖"弹窗打断。当前位置按运行时身份定位（video=currentWallpaper.id；
/// web/scene=活动 recordID），定位失败时 next 从头、previous 从尾。
/// 前进/后退为环形序，目标等于当前项时不动作；第一版不做跨引擎历史
/// 回退（热键/状态栏的 previous 即序列前项；视频内历史回退仅在
/// 视频库工具栏保留）。
@MainActor
enum CrossRuntimeWallpaperNavigator {
    static func navigate(_ direction: ManualNavigationDirection) {
        let manager = WallpaperManager.shared
        let workshop = SteamWorkshopService.shared

        let videos = manager.wallpapers
        let workshopRecords = workshop.downloads.filter { record in
            guard record.contentType == .web || record.contentType == .scene else {
                return false
            }
            // 依赖缺失项跳过：轮到它会弹"缺少依赖项"对话框打断轮换。
            if case .missing = record.dependencyStatus {
                return false
            }
            // 与 setAsWallpaper 的拒播判据对齐（ready + fatal 校验），
            // 避免轮到会被静默拒播的项后该方向卡死。
            return workshop.cachedCanLaunchDownloadRecord(record)
        }
        let workshopBase = videos.count
        let totalCount = workshopBase + workshopRecords.count
        guard totalCount > 0 else { return }

        let currentIndex = currentIndexInRotation(
            videos: videos,
            workshopRecords: workshopRecords,
            workshopBase: workshopBase
        )

        let targetIndex: Int
        switch direction {
        case .next:
            targetIndex = currentIndex
                .map { ($0 + 1) % totalCount }
                ?? 0
        case .previous:
            targetIndex = currentIndex
                .map { ($0 - 1 + totalCount) % totalCount }
                ?? (totalCount - 1)
        }
        guard targetIndex != currentIndex else { return }

        if targetIndex < workshopBase {
            let wallpaper = videos[targetIndex]
            manager.requestSetAsWallpaper(wallpaper)
        } else {
            workshop.setAsWallpaper(workshopRecords[targetIndex - workshopBase])
        }
    }

    private static func currentIndexInRotation(
        videos: [VideoWallpaper],
        workshopRecords: [SteamWorkshopDownloadRecord],
        workshopBase: Int
    ) -> Int? {
        let manager = WallpaperManager.shared
        switch manager.activeWallpaperRuntime {
        case .video:
            guard let currentID = manager.currentWallpaper?.id else { return nil }
            return videos.firstIndex { $0.id == currentID }
        case .web:
            guard let recordID = WallpaperEngine.shared.currentWebRecordID else {
                return nil
            }
            return workshopRecords
                .firstIndex { $0.id == recordID }
                .map { $0 + workshopBase }
        case .scene:
            let recordID = SceneDaemonClient.shared.activeRecordID
                ?? SceneDaemonClient.shared.launchState?.recordID
            guard let recordID else { return nil }
            return workshopRecords
                .firstIndex { $0.id == recordID }
                .map { $0 + workshopBase }
        default:
            return nil
        }
    }
}
