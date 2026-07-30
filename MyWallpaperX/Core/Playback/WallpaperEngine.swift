//
//  WallpaperEngine.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//


import Foundation
import AVFoundation
import AppKit
import CoreGraphics

public final class WallpaperEngine: NSObject {
    enum PlaybackContentKind: String {
        case video
        case web
    }

    public static let shared = WallpaperEngine()
    public static let playbackFailedNotification = Notification.Name("WallpaperEnginePlaybackFailedNotification")
    public static let playbackEndedNotification = Notification.Name("WallpaperEnginePlaybackEndedNotification")

    // 一个 display 对应一个 daemon session；后面所有播放、暂停、换壁纸都围绕这个会话表展开。
    final class DisplayDaemonSession {
        let displayID: CGDirectDisplayID
        let process: Process
        let inputPipe: Pipe
        let outputPipe: Pipe
        let errorPipe: Pipe
        var outputBuffer = Data()
        var nextRequestID = 0
        var latestRequestedPlayRequestID: Int?
        var latestAcceptedPlayRequestID: Int?
        var latestReadyPlayRequestID: Int?
        var launched = false

        // 退避计数：连续崩溃次数，成功播放后清零。
        var consecutiveCrashCount: Int = 0

        init(displayID: CGDirectDisplayID, process: Process, inputPipe: Pipe, outputPipe: Pipe, errorPipe: Pipe) {
            self.displayID = displayID
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
        }
    }

    // 每个 display 的退避计数独立维护，session 重建时继承，成功后归零。
    var displayCrashCounts: [CGDirectDisplayID: Int] = [:]

    var displaySessions: [CGDirectDisplayID: DisplayDaemonSession] = [:]
    var currentWallpaper: VideoWallpaper?
    var currentContentPath: String?
    var currentPlaybackContentKind: PlaybackContentKind?
    var currentWebPropertiesJSON: String?
    var currentWebRecordID: String?
    var currentWebRequestID: UUID?
    var currentWebHostStrategy: WebWallpaperHostStrategy = .dedicatedHostPlaceholder
    var currentWebLaunchSource: WebWallpaperLaunchSource?
    var playbackIntentEpoch: UInt64 = 0
    lazy var dedicatedWebHostAdapter: WebWallpaperHostAdapter = DedicatedWebWallpaperHostPlaceholderAdapter()
    var displayIDs: [CGDirectDisplayID] = []
    var screenLocked = false
    var visibilityReductionActive = false
    var playbackPaused = false
    var isPlaybackPaused: Bool { playbackPaused }
    var reducedPerformanceMode = false
    var targetPlaybackRate: Float = 1.0
    var currentVolumeNormalized: Float = 0.5
    var currentVideoFillMode = VideoFillMode.aspectFill.rawValue
    var currentMultiDisplayEnabled = true
    var currentShouldLoopCurrentItem = false
    var currentSystemAudioSpectrumEnabled = false
    var currentSystemAudioSpectrumColorHex = "#F4FBFF"
    var currentSystemAudioSpectrumOffsetX: Float = 0
    var currentSystemAudioSpectrumOffsetY: Float = 0
    var currentSystemAudioSpectrumBarCount = WallpaperEngine.defaultSpectrumBarCount
    var currentSystemAudioSpectrumPeakCapsEnabled = true
    var currentWebAudioSpectrumRequested = false
    var currentSpectrumLevels: [Float]
    var lastSpectrumPushAt: CFTimeInterval = 0
    var lastWebSpectrumPushAt: CFTimeInterval = 0
    var lastWebSpectrumLevels: [Float] = []
    var systemAudioSpectrumService: SystemAudioSpectrumService

    var pauseWhenOtherAppFocused = true
    var pauseWhenOtherAppFullscreen = true
    var pauseWhenUnplugged = false
    var pauseWhenIdle = false
    var idleMonitorTimer: DispatchSourceTimer?
    var idleMonitorReady = false  // 定时器触发过至少一次才允许评估 idle 状态，防止开启开关瞬间误暂停
    var idleTimeoutMinutes = 10

    var systemSleeping = false
    var displaysSleeping = false
    var activeSystemInterruptions: Set<PlaybackSystemInterruption> = []
    var lastFailureVideoPath: String?
    var lastFailureAt: TimeInterval = 0
    var lastEndedVideoPath: String?
    var lastEndedAt: TimeInterval = 0
    var suppressFullscreenPauseUntil: TimeInterval = 0
    var pendingPlaybackStateRefreshWorkItem: DispatchWorkItem?
    var pendingPlaybackStateRefreshDeadline: CFTimeInterval?
    var lastPlaybackStateEvaluationAt: CFTimeInterval = 0
    let playbackStateEvaluationMinInterval: TimeInterval = 0.10
    var powerStateFallbackTimer: DispatchSourceTimer?
    var lastObservedOnBattery: Bool?
    var lastObservedLowPowerMode: Bool?
    var lastFullscreenSpaceState: Bool?
    var lastFullscreenSpaceStateAt: CFTimeInterval = 0
    let fullscreenSpaceStateCacheTTL: TimeInterval = 0.25
    static let defaultSpectrumBarCount = 28
    let spectrumPushMinInterval: CFTimeInterval = 1.0 / 30.0
    let webSpectrumPushMinInterval: CFTimeInterval = 1.0 / 30.0

    override init() {
        currentSpectrumLevels = Array(repeating: 0, count: WallpaperEngine.defaultSpectrumBarCount)
        systemAudioSpectrumService = SystemAudioSpectrumService(barCount: WallpaperEngine.defaultSpectrumBarCount)
        super.init()
        lastObservedLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        dedicatedWebHostAdapter.eventHandler = { [weak self] event in
            if Thread.isMainThread {
                self?.handleWebHostEvent(event)
            } else {
                DispatchQueue.main.async {
                    self?.handleWebHostEvent(event)
                }
            }
        }
        systemAudioSpectrumService = makeSystemAudioSpectrumService(barCount: WallpaperEngine.defaultSpectrumBarCount)
        observeSceneAudioSpectrumDemand()
        setupNotifications()
        scanDisplays()
    }

    public func setWallpaper(
        _ wallpaper: VideoWallpaper,
        multiDisplayEnabled: Bool,
        videoFillMode: String,
        shouldLoopCurrentItem: Bool,
        pauseWhenOtherAppFocused: Bool,
        pauseWhenOtherAppFullscreen: Bool,
        pauseWhenUnplugged: Bool,
        pauseWhenIdle: Bool,
        idleTimeoutMinutes: Int
    ) {
        // 对外统一入口接收每个合法切换；交互去抖由调用层负责。
        beginPlaybackIntent()
        applyWallpaper(
            wallpaper,
            multiDisplayEnabled: multiDisplayEnabled,
            videoFillMode: videoFillMode,
            shouldLoopCurrentItem: shouldLoopCurrentItem,
            pauseWhenOtherAppFocused: pauseWhenOtherAppFocused,
            pauseWhenOtherAppFullscreen: pauseWhenOtherAppFullscreen,
            pauseWhenUnplugged: pauseWhenUnplugged,
            pauseWhenIdle: pauseWhenIdle,
            idleTimeoutMinutes: idleTimeoutMinutes
        )
    }

    func applyWallpaper(
        _ wallpaper: VideoWallpaper,
        multiDisplayEnabled: Bool,
        videoFillMode: String,
        shouldLoopCurrentItem: Bool,
        pauseWhenOtherAppFocused: Bool,
        pauseWhenOtherAppFullscreen: Bool,
        pauseWhenUnplugged: Bool,
        pauseWhenIdle: Bool,
        idleTimeoutMinutes: Int
    ) {
        let previousNormalizedPath = currentWallpaper.map { normalizedPath($0.path) }
        let incomingNormalizedPath = normalizedPath(wallpaper.path)
        let previousVideoFillMode = currentVideoFillMode
        let previousMultiDisplayEnabled = currentMultiDisplayEnabled
        let previousShouldLoopCurrentItem = currentShouldLoopCurrentItem

        if currentPlaybackContentKind == .web {
            setWebAudioSpectrumRequested(false)
            dispatchWebRuntimeCommand(.stop)
            currentContentPath = nil
            currentWebPropertiesJSON = nil
            currentWebLaunchSource = nil
            currentWebRecordID = nil
            currentWebRequestID = nil
            setPlaybackPausedState(false)
        }

        // 先更新内存态，再决定是否复用现有 daemon session 或下发新的 play 命令。
        currentWallpaper = wallpaper
        currentContentPath = incomingNormalizedPath
        currentPlaybackContentKind = .video
        currentVideoFillMode = videoFillMode
        currentMultiDisplayEnabled = multiDisplayEnabled
        currentShouldLoopCurrentItem = shouldLoopCurrentItem
        self.pauseWhenOtherAppFocused = pauseWhenOtherAppFocused
        self.pauseWhenOtherAppFullscreen = pauseWhenOtherAppFullscreen
        self.pauseWhenUnplugged = pauseWhenUnplugged
        self.pauseWhenIdle = pauseWhenIdle
        self.idleTimeoutMinutes = idleTimeoutMinutes
        refreshPowerStateFallbackMonitoring()
        refreshIdleMonitoring()

        scanDisplays()
        let targetDisplayIDs = multiDisplayEnabled ? displayIDs : [displayIDs.first].compactMap { $0 }
        let existingDisplayIDs = Set(displaySessions.keys)
        let targetDisplayIDSet = Set(targetDisplayIDs)
        let noObsoleteDisplaySessions = existingDisplayIDs.isSubset(of: targetDisplayIDSet)
        let targetSessionsReady = !targetDisplayIDs.isEmpty
            && targetDisplayIDs.allSatisfy { displaySessions[$0]?.process.isRunning == true }

        let isSameWallpaperRequest = previousNormalizedPath == incomingNormalizedPath
        let isConfigurationUnchanged =
            previousVideoFillMode == videoFillMode
            && previousMultiDisplayEnabled == multiDisplayEnabled
            && previousShouldLoopCurrentItem == shouldLoopCurrentItem

        // 同一壁纸、同一配置且 session 仍然有效时，直接刷新播放状态，不重建播放链路。
        if isSameWallpaperRequest
            && isConfigurationUnchanged
            && noObsoleteDisplaySessions
            && targetSessionsReady {
            requestPlaybackStateEvaluation(immediate: true)
            return
        }

        for displayID in targetDisplayIDs {
            guard let session = ensureSession(for: displayID) else { continue }
            sendPlayCommand(
                for: wallpaper.path,
                framePath: wallpaper.staticFramePath,
                fillMode: videoFillMode,
                shouldLoopCurrentItem: shouldLoopCurrentItem,
                to: session
            )
        }

        let obsoleteDisplayIDs = Set(displaySessions.keys).subtracting(targetDisplayIDs)
        for displayID in obsoleteDisplayIDs {
            terminateSession(for: displayID)
        }

        requestPlaybackStateEvaluation(immediate: true)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    func beginPlaybackIntent() {
        playbackIntentEpoch &+= 1
    }

    public func updateSettings(
        pauseWhenOtherAppFocused: Bool,
        pauseWhenOtherAppFullscreen: Bool,
        pauseWhenUnplugged: Bool,
        pauseWhenIdle: Bool,
        idleTimeoutMinutes: Int
    ) {
        // 这里只更新暂停策略和闲置阈值，避免把设置层的其它变更混进引擎热路径。
        self.pauseWhenOtherAppFocused = pauseWhenOtherAppFocused
        self.pauseWhenOtherAppFullscreen = pauseWhenOtherAppFullscreen
        self.pauseWhenUnplugged = pauseWhenUnplugged
        self.pauseWhenIdle = pauseWhenIdle
        self.idleTimeoutMinutes = idleTimeoutMinutes
        refreshPowerStateFallbackMonitoring()
        refreshIdleMonitoring()

        requestPlaybackStateEvaluation(immediate: true)
    }

    public func stopPlayback() {
        beginPlaybackIntent()
        if currentPlaybackContentKind == .web {
            setWebAudioSpectrumRequested(false)
            dispatchWebRuntimeCommand(.stop)
        } else {
            for displayID in Array(displaySessions.keys) {
                terminateSession(for: displayID)
            }
        }
        currentContentPath = nil
        currentPlaybackContentKind = nil
        currentWebPropertiesJSON = nil
        currentWebRecordID = nil
        currentWebRequestID = nil
        currentWebLaunchSource = nil
        currentWallpaper = nil
        SceneDesktopWallpaperHost.shared.setPlaybackPaused(playbackPaused)
    }

    public func cleanup() {
        // 退出或重建时必须清掉定时器和挂起评估，否则旧状态会继续回写。
        powerStateFallbackTimer?.cancel()
        powerStateFallbackTimer = nil
        idleMonitorTimer?.cancel()
        idleMonitorTimer = nil
        pendingPlaybackStateRefreshWorkItem?.cancel()
        pendingPlaybackStateRefreshWorkItem = nil
        pendingPlaybackStateRefreshDeadline = nil
        stopPlayback()
        systemAudioSpectrumService.setConsumers(overlayEnabled: false, webEnabled: false)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        displayIDs.removeAll()
        currentWallpaper = nil
        currentContentPath = nil
        currentPlaybackContentKind = nil
        currentWebPropertiesJSON = nil
        currentWebRecordID = nil
        currentWebRequestID = nil
        currentWebLaunchSource = nil
    }

    public func setVolume(_ volume: Float) {
        let normalizedVolume = min(max(volume, 0), 100) / 100
        currentVolumeNormalized = normalizedVolume

        if currentPlaybackContentKind == .web {
            dispatchWebRuntimeCommand(.setVolume(normalizedVolume))
        } else {
            for session in displaySessions.values where session.process.isRunning {
                send(DaemonCommand(action: "setVolume", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: normalizedVolume, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            }
        }
    }

    public func setFillMode(_ fillMode: String) {
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "setFillMode", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: fillMode, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
        }
    }

    public func setLoopCurrentItem(_ shouldLoop: Bool) {
        // 只更新循环状态，不重载视频，避免切换自动切换开关时画面闪烁。
        // 不做去重，确保每次开关操作都能可靠送达 daemon。
        currentShouldLoopCurrentItem = shouldLoop
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "setLoop", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: shouldLoop, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
        }
    }

    public func setPlaybackRate(_ rate: Float) {
        // Web 宿主可独立调整速率，不能为了调速而意外恢复已经暂停的页面。
        let clampedRate = max(0.25, min(2.0, rate))
        targetPlaybackRate = clampedRate
        if currentPlaybackContentKind == .web {
            dispatchWebRuntimeCommand(.setPlaybackRate(clampedRate))
            return
        }
        guard !playbackPaused else { return }
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "resume", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: clampedRate, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
        }
    }

    public func isPlaying() -> Bool {
        let sceneHost = SceneDesktopWallpaperHost.shared
        if sceneHost.activeRecordID != nil {
            return !playbackPaused && sceneHost.isPlaybackActive
        }
        guard !playbackPaused else { return false }

        if currentPlaybackContentKind == .web {
            switch currentWebHostStrategy {
            case .daemonDiagnosticsHarness:
                return displaySessions.values.contains { $0.process.isRunning }
            case .dedicatedHostPlaceholder:
                return currentContentPath != nil
            }
        }

        return displaySessions.values.contains { $0.process.isRunning }
    }

    public func togglePlayback() {
        if playbackPaused {
            resumeAllPlayers()
        } else {
            pauseAllPlayers()
        }
    }

    public func refreshPlaybackState() {
        // 状态评估只走统一入口，避免 UI / 系统通知各自直接改 pause 状态。
        requestPlaybackStateEvaluation(immediate: true)
    }

    public func getCurrentWallpaper() -> VideoWallpaper? {
        currentWallpaper
    }

}
