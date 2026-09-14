import Combine
import Foundation

/// M0.3：设置面板动作集（闭包注入——Shared 层不感知具体模块类型）。
/// SettingsWindowController 构造时从 WallpaperManager 捕获实现。
struct AppSettingsActions {
    var applyEngineSettings: (_ reloadWallpaper: Bool) -> Void = { _ in }
    var applyPlaybackRateToEngine: () -> Void = {}
    var applySystemAudioSpectrumToEngine: () -> Void = {}
    var clearAllCaches: () -> Void = {}
    var exportPersonalSettings: (_ url: URL) throws -> PersonalSettingsExportSummary = { _ in
        PersonalSettingsExportSummary(wallpaperCount: 0, tagCount: 0)
    }
    var importPersonalSettings: (_ url: URL) throws -> PersonalSettingsImportSummary = { _ in
        PersonalSettingsImportSummary(
            mergedWallpaperCount: 0, createdWallpaperCount: 0,
            missingPathCount: 0, tagCount: 0
        )
    }
    var refreshAutoSwitchTimerIfNeeded: () -> Void = {}
    var resetToFreshInstallState: () -> Void = {}
    var setLoopPlaybackEnabled: (_ enabled: Bool) -> Void = { _ in }
    var setRandomPlaybackEnabled: (_ enabled: Bool) -> Void = { _ in }
    var setSequentialPlaybackEnabled: (_ enabled: Bool) -> Void = { _ in }
    var setSyncSystemWallpaperEnabled: (_ enabled: Bool) -> Void = { _ in }
    var startAutoSwitchTimer: () -> Void = {}
    var stopAutoSwitchTimer: () -> Void = {}
    var updateLoginItemStatus: () -> Void = {}
    var updateVolume: (_ volume: Double) -> Void = { _ in }
}

/// M0.3：设置面板可绑定依赖——settings 值 + 动作闭包集。
/// ObservableObject 让视图订阅 objectWillChange 刷新 UI。
final class AppSettingsPanelDependency: ObservableObject {
    @Published var settings: WallpaperSettings
    let actions: AppSettingsActions

    init(settings: WallpaperSettings, actions: AppSettingsActions) {
        self.settings = settings
        self.actions = actions
    }
}
