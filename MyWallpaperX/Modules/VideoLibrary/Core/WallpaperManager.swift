//
//  WallpaperManager.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import Foundation
import Combine

class WallpaperManager: ObservableObject {
    enum ActiveWallpaperRuntime: String, Codable {
        case video
        case web
        case scene
        case systemStill
    }

    static let recentWallpapersLimit: Int = 25
    static let defaultTags: [String] = ["自然景观", "科技未来", "游戏CG", "卡通动漫"]
    struct HotkeySettingsSnapshot: Equatable {
        let systemHotkeysEnabled: Bool
        let previousWallpaperHotkey: FunctionKeyShortcut
        let nextWallpaperHotkey: FunctionKeyShortcut
        let togglePlaybackHotkey: FunctionKeyShortcut
        let toggleMuteHotkey: FunctionKeyShortcut

        init(settings: WallpaperSettings) {
            systemHotkeysEnabled = settings.systemHotkeysEnabled
            previousWallpaperHotkey = settings.previousWallpaperHotkey
            nextWallpaperHotkey = settings.nextWallpaperHotkey
            togglePlaybackHotkey = settings.togglePlaybackHotkey
            toggleMuteHotkey = settings.toggleMuteHotkey
        }
    }

    static let shared = WallpaperManager()
    
    @Published var selectedCategory: Category = .myWallpapers
    @Published var selectedTag: String? = nil
    @Published var wallpapers: [VideoWallpaper] = [] {
        didSet {
            syncSelectedWallpaperInspectorIfNeeded()
        }
    }
    @Published var settings: WallpaperSettings = WallpaperSettings()
    @Published var selectedWallpaperId: String? = nil {
        didSet {
            syncSelectedWallpaperInspectorIfNeeded()
        }
    }
    @Published var selectedWallpaperIds: Set<String> = [] {
        didSet {
            syncSelectedWallpaperInspectorIfNeeded()
        }
    }
    @Published var inspectedWallpaperID: String? = nil
    @Published var isMultiSelectMode: Bool = false {
        didSet {
            syncSelectedWallpaperInspectorIfNeeded()
        }
    }
    @Published var isDragSelecting: Bool = false
    @Published var currentWallpaper: VideoWallpaper? = nil
    @Published var recentlyUsedWallpapers: [VideoWallpaper] = []
    @Published var isPlaying: Bool = true
    @Published var activeWallpaperRuntime: ActiveWallpaperRuntime = .video
    // E2a-3: requested 层选择（立即写，UI 高亮读 effectiveCurrentWallpaper）；
    // committed currentWallpaper 延后到 daemon ready 提交——失败项真值不落地。
    @Published var pendingWallpaper: VideoWallpaper? = nil
    var effectiveCurrentWallpaper: VideoWallpaper? {
        pendingWallpaper ?? currentWallpaper
    }
    // E2a-1: requested 层的产品级意图纪元——唯一选择权威在每次切换入口
    // 递增；runtime adapter 以单调采纳作为执行事实镜像（只读注入，
    // 不改变任何提交点）。
    private var playbackIntentEpochCounter = PlaybackIntentEpoch()
    var playbackIntentEpoch: UInt64 { playbackIntentEpochCounter.value }

    @discardableResult
    func beginPlaybackIntent() -> UInt64 {
        playbackIntentEpochCounter.begin()
    }
    
    // 标签管理
    @Published var tags: [String] = WallpaperManager.defaultTags
    
    // 搜索功能
    @Published var searchQuery: String = ""
    @Published var isSearchFieldActive: Bool = false
    @Published var visibleGridColumnCount: Int = 4

    // 网格缩放：用户手动调整的期望列数偏移（-2~+2），叠加到宽度自适应结果上。
    // 0 = 默认（纯宽度自适应），负数 = 更大卡片，正数 = 更多列。
    @Published var gridZoomOffset: Int = 0 {
        didSet {
            UserDefaults.standard.set(gridZoomOffset, forKey: "gridZoomOffset")
        }
    }

    // 每个列表独立排序状态，key = WallpaperSelectionContext.scrollPersistenceKey。
    @Published var perSelectionSortStates: [String: SortState] = [:]
    
    // 自动切换计时器
    var autoSwitchTimer: Timer?

    // 播放列表来源：记录用户点击播放时所在的列表，后续切换都在此列表内进行。
    // userInitiated=true 时更新；自动切换时保持不变。
    var playbackSourceContext: WallpaperSelectionContext = .category(.myWallpapers)
    var currentIndex: Int = 0
    let deletionQueue = DispatchQueue(label: "com.mywallpaper.delete", qos: .utility)
    
    // 缩略图缓存队列和缓存字典
    let thumbnailQueue = DispatchQueue(label: "com.mywallpaper.thumbnail", qos: .utility, attributes: .concurrent)
    let staticFrameQueue = DispatchQueue(label: "com.mywallpaper.staticframe", qos: .background)
    var thumbnailCache: [String: String] = [:]
    let thumbnailCacheLock = NSLock()
    let thumbnailGenerationLimiter = DispatchSemaphore(value: 2)
    var thumbnailInFlightHandlers: [String: [(String?) -> Void]] = [:]
    let thumbnailInFlightLock = NSLock()
    var scheduledStaticFramePaths = Set<String>()
    let staticFrameScheduleLock = NSLock()
    var cacheGeneration: UInt64 = 0
    let cacheGenerationLock = NSLock()
    var missingIndexedFilePaths = Set<String>()
    var pendingMissingIndexedTitles = Set<String>()
    var missingIndexedAlertWorkItem: DispatchWorkItem?
    var missingIndexedSourceScanWorkItem: DispatchWorkItem?
    var thumbnailGenerationFailures: [String: Date] = [:]
    let thumbnailGenerationFailureLock = NSLock()
    var wallpapersAutoSaveWorkItem: DispatchWorkItem?
    var recentWallpapersAutoSaveWorkItem: DispatchWorkItem?
    var settingsAutoSaveWorkItem: DispatchWorkItem?
    var pendingSystemWallpaperSyncWorkItem: DispatchWorkItem?
    let importPreparationQueue = DispatchQueue(label: "com.mywallpaper.import.prepare", qos: .userInitiated)
    let importAssetPipelineQueue = DispatchQueue(label: "com.mywallpaper.import.assets", qos: .utility)
    let importPreparationStateLock = NSLock()
    var importPreparationWorkItem: DispatchWorkItem?
    var importPreparationGeneration: UInt64 = 0
    var lastAppliedHotkeySettings: HotkeySettingsSnapshot?
    
    // 默认设置
    let defaultSettings = WallpaperSettings()
    
    // UserDefaults 键
    let settingsKey = "WallpaperSettings"
    let wallpapersKey = "Wallpapers"
    let tagsKey = "WallpaperTags"
    let currentWallpaperKey = "CurrentWallpaper"
    let recentWallpapersKey = "RecentWallpapers"
    let playbackStateKey = "PlaybackState"
    let activeWallpaperRuntimeKey = "ActiveWallpaperRuntime"
    let perSelectionSortStatesKey = "PerSelectionSortStates"
    
    // 用于存储 Combine 订阅
    private var cancellables = Set<AnyCancellable>()
    var previousAudibleVolume: Double = 50.0
    var lastInteractiveWallpaperSetTime: CFTimeInterval = 0
    let interactiveWallpaperSetDebounceInterval: CFTimeInterval = 0.22
    var lastManualNavigationAt: CFTimeInterval = 0
    let manualNavigationMinInterval: CFTimeInterval = 0.18
    var pendingManualNavigationDirection: ManualNavigationDirection?
    var pendingManualNavigationUserInitiated: Bool = false
    var pendingManualNavigationWorkItem: DispatchWorkItem?
    // #7 已移除 Manager 侧 lastPlaybackFailure/Ended 去重变量。
    // Engine 在 handlePlaybackFailureEvent / handlePlaybackEndedEvent 已有 1s 去重窗口，Manager 侧不再重复过滤。
    var playbackHistoryPaths: [String] = []
    var playbackForwardPaths: [String] = []   // 随机模式"上一张"后，"下一张"优先消费此栈
    let playbackHistoryLimit: Int = 10
    let thumbnailReadySubject = PassthroughSubject<String, Never>()
    
    let thumbnailCacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("WallpaperThumbnails")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    let staticFrameCacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("WallpaperStaticFrames")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    init() {
        // 加载顺序不能乱：先把持久化库和标签装进内存，再恢复最近使用/当前壁纸，最后再恢复播放态。
        loadSettings()
        sanitizeSystemHotkeySettingsIfNeeded()
        normalizePlaybackSettings()
        loadWallpapers()
        loadSampleData()
        loadTags()
        loadSavedState()
        loadPerSelectionSortStates()
        gridZoomOffset = UserDefaults.standard.object(forKey: "gridZoomOffset") as? Int ?? 0
        refreshAutoSwitchTimerIfNeeded()
        restorePlaybackState()
        restorePersistedSystemAudioSpectrumIfNeeded()
        
        // 后台扫描缺失的视频元数据（时长、分辨率等）
        scanForMissingMetadata()
        
        // 监听设置变化，自动保存
        $settings
        .dropFirst()
        .sink { [weak self] newSettings in
            guard let self else { return }
            self.sanitizeSystemHotkeySettingsIfNeeded()
            self.scheduleSettingsAutoPersist()
            let hotkeySnapshot = HotkeySettingsSnapshot(settings: newSettings)
            if self.lastAppliedHotkeySettings != hotkeySnapshot {
                self.lastAppliedHotkeySettings = hotkeySnapshot
                GlobalHotkeyManager.shared.update(with: newSettings)
            }
            // 播放速率变化时立即同步到引擎。
            self.applyPlaybackRateToEngine()
            self.applySystemAudioSpectrumToEngine()
        }
        .store(in: &cancellables)

        $wallpapers
        .dropFirst()
        .sink { [weak self] _ in
            guard let self else { return }
            self.scheduleWallpapersAutoPersist()
        }
        .store(in: &cancellables)

        // 监听当前壁纸变化，自动保存
        $currentWallpaper
        .dropFirst()
        .sink {[weak self] _ in
            self?.saveCurrentWallpaper()
        }
        .store(in: &cancellables)
        
        // 监听播放状态变化，自动保存
        $isPlaying
        .dropFirst()
        .sink {[weak self] _ in
            self?.savePlaybackState()
        }
        .store(in: &cancellables)

        $activeWallpaperRuntime
        .dropFirst()
        .sink { [weak self] _ in
            self?.saveActiveWallpaperRuntime()
        }
        .store(in: &cancellables)

        observePlaybackEvents(storeIn: &cancellables)

        GlobalHotkeyManager.shared.update(with: settings)
        lastAppliedHotkeySettings = HotkeySettingsSnapshot(settings: settings)
    }

    private func restorePersistedSystemAudioSpectrumIfNeeded() {
        guard settings.systemAudioSpectrumEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.settings.systemAudioSpectrumEnabled else { return }
            self.applySystemAudioSpectrumToEngine()
        }
    }

    var pendingCardInteraction = false
    var pendingCardInteractionResetWorkItem: DispatchWorkItem?
    let thumbnailFailureRetryCooldown: TimeInterval = 12

    func normalizedPath(_ path: String) -> String {
        // 路径比较统一先做标准化，避免符号链接、相对路径和大小写差异造成重复项。
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    var thumbnailReadyPublisher: AnyPublisher<String, Never> {
        thumbnailReadySubject.eraseToAnyPublisher()
    }

    func notifyThumbnailReady(forPath path: String) {
        // 缩略图完成只发一个标准化路径事件，让网格自己决定要刷新哪几张卡片。
        let normalized = normalizedPath(path)
        if Thread.isMainThread {
            // 缩略图就绪通知必须回主线程发出，避免卡片刷新和数据源更新跨线程。
            thumbnailReadySubject.send(normalized)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.thumbnailReadySubject.send(normalized)
            }
        }
    }

    func pathExists(_ path: String) -> Bool {
        // 文件存在性检查保持最薄包装，方便上层区分“存在但不可读”和“完全缺失”。
        FileManager.default.fileExists(atPath: path)
    }

    func isReadablePath(_ path: String) -> Bool {
        FileManager.default.isReadableFile(atPath: path)
    }

    func normalizedSourcePathExists(_ path: String) -> Bool {
        pathExists(normalizedPath(path))
    }

    func normalizedSourcePathReadable(_ path: String) -> Bool {
        isReadablePath(normalizedPath(path))
    }

    func findWallpaperIndex(forPath path: String) -> Int? {
        // 主库索引查找只按标准化路径命中，避免同一文件被当成多份资源。
        let normalized = normalizedPath(path)
        return wallpapers.firstIndex { normalizedPath($0.path) == normalized }
    }

    @discardableResult
    func upsertWallpaper(_ wallpaper: VideoWallpaper) -> String {
        // 导入 / 恢复 / 预览资产回写都走同一条 upsert 入口，避免重复写入和多处 merge 规则分叉。
        if let index = findWallpaperIndex(forPath: wallpaper.path) {
            mergeWallpaper(wallpaper, into: &wallpapers[index])
            return wallpapers[index].id
        }

        wallpapers.append(wallpaper)
        return wallpaper.id
    }

    func currentWallpaperIndex() -> Int? {
        // currentIndex 是热路径缓存，命中时直接返回；不命中才回退到全库查找。
        guard let currentWallpaper else { return nil }
        if wallpapers.indices.contains(currentIndex),
           wallpapers[currentIndex].id == currentWallpaper.id {
            return currentIndex
        }
        return wallpapers.firstIndex(where: { $0.id == currentWallpaper.id })
    }

    func normalizeRecentWallpapers(limit: Int = WallpaperManager.recentWallpapersLimit, requireExistingFiles: Bool) {
        // 最近使用是快照列表，先回填到主库对象再做去重和限长，避免快照字段漂移。
        let libraryByPath = wallpapers.reduce(into: [String: VideoWallpaper]()) { result, wallpaper in
            result[normalizedPath(wallpaper.path)] = wallpaper
        }
        guard !libraryByPath.isEmpty else {
            if !recentlyUsedWallpapers.isEmpty {
                recentlyUsedWallpapers.removeAll()
            }
            return
        }

        var seenPaths = Set<String>()
        var normalizedRecent: [VideoWallpaper] = []
        normalizedRecent.reserveCapacity(min(limit, recentlyUsedWallpapers.count))

        for wallpaper in recentlyUsedWallpapers {
            let normalized = normalizedPath(wallpaper.path)
            guard let canonicalWallpaper = libraryByPath[normalized] else { continue }
            guard !requireExistingFiles || pathExists(normalized) else { continue }
            guard seenPaths.insert(normalized).inserted else { continue }
            normalizedRecent.append(canonicalWallpaper)
            if normalizedRecent.count == limit {
                break
            }
        }

        recentlyUsedWallpapers = normalizedRecent
    }

    func constrainRecentWallpapersToLibrary() {
        // 保留现有列表但剔除不在主库中的项，供持久化写盘前收口。
        normalizeRecentWallpapers(limit: WallpaperManager.recentWallpapersLimit, requireExistingFiles: false)
    }

    private func mergeWallpaper(_ incoming: VideoWallpaper, into existing: inout VideoWallpaper) {
        // 合并策略只补缺不覆盖用户态数据，收藏/标签/缓存路径都尽量保留已有值。
        existing.thumbnailPath = existing.thumbnailPath ?? incoming.thumbnailPath
        existing.staticFramePath = existing.staticFramePath ?? incoming.staticFramePath
        existing.isFavorite = existing.isFavorite || incoming.isFavorite
        existing.lastUsed = max(existing.lastUsed, incoming.lastUsed)
        for tag in incoming.tags where !existing.tags.contains(tag) {
            existing.tags.append(tag)
        }
    }

}

extension Notification.Name {
    static let wallpaperManagerDidResetToFreshInstallState = Notification.Name(
        "WallpaperManagerDidResetToFreshInstallState"
    )

    static let wallpaperManagerDidImportPersonalSettings = Notification.Name(
        "WallpaperManagerDidImportPersonalSettings"
    )
}
