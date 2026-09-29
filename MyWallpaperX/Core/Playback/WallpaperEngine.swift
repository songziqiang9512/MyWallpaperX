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
    /// E2a-3: a play request reached ready on the daemon for the current
    /// content path — the selection authority commits its deferred truth on
    /// this signal.
    public static let playbackReadyNotification = Notification.Name("WallpaperEnginePlaybackReadyNotification")

    // 一个 display 对应一个 daemon session；后面所有播放、暂停、换壁纸都围绕这个会话表展开。
    final class DisplayDaemonSession {
        let displayID: CGDirectDisplayID
        let transport: DaemonProcessTransport
        var outputFrames = DaemonNewlineFrameBuffer()
        var nextRequestID = 0
        var latestRequestedPlayRequestID: Int?
        var latestAcceptedPlayRequestID: Int?
        var latestReadyPlayRequestID: Int?
        var launched = false

        // 退避计数：连续崩溃次数，成功播放后清零。
        var consecutiveCrashCount: Int = 0

        init(displayID: CGDirectDisplayID, transport: DaemonProcessTransport) {
            self.displayID = displayID
            self.transport = transport
        }

        var process: Process { transport.process }
        var inputPipe: Pipe { transport.inputPipe }
        var outputPipe: Pipe { transport.outputPipe }
        var errorPipe: Pipe { transport.errorPipe }
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
    /// E2a-4: a web launch is preparing over a still-running video runtime —
    /// the video sessions retire only on web `.ready`, and a web `.failed`
    /// restores the video kind so the old visible output is retained.
    var pendingVideoRetirementOnWebReady = false
    /// E2a-4: video truth retained while a web launch prepares over it.
    var retainedVideoWallpaper: VideoWallpaper?
    var retainedVideoContentPath: String?
    var retainedVideoMultiDisplayEnabled: Bool?
    var playbackIntentEpoch: UInt64 = 0
    lazy var dedicatedWebHostAdapter: WebWallpaperHostAdapter = DedicatedWebWallpaperHostPlaceholderAdapter()
    var displayIDs: [CGDirectDisplayID] = []
    var playbackPaused = false
    var isPlaybackPaused: Bool { playbackPaused }
    var targetPlaybackRate: Float = 1.0
    var currentVolumeNormalized: Float = 0.5
    var effectiveVolumeNormalized: Float {
        PlaybackMuteState.shared.isMuted ? 0 : currentVolumeNormalized
    }
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
    var sceneDaemonAudioSpectrumDemand = SceneAudioSpectrumCaptureDemand.none
    var sceneDaemonAudioSpectrumGeneration: UInt64?
    var sceneAudioSpectrumCaptureRouting = SceneAudioSpectrumCaptureRoutingState()
    let systemAudioSpectrumLevelHandoff = LatestValueHandoff<[Float]>()
    let webAudioSpectrumLevelHandoff = LatestValueHandoff<[Float]>()
    let sceneAudioSpectrumRouteHandoff = LatestValueHandoff<
        SceneAudioSpectrumRoutedFrame
    >()

    var lastFailureVideoPath: String?
    var lastFailureAt: TimeInterval = 0
    var lastEndedVideoPath: String?
    var lastEndedAt: TimeInterval = 0
    static let defaultSpectrumBarCount = 28
    let spectrumPushMinInterval: CFTimeInterval = 1.0 / 30.0
    let webSpectrumPushMinInterval: CFTimeInterval = 1.0 / 30.0

    override init() {
        currentSpectrumLevels = Array(repeating: 0, count: WallpaperEngine.defaultSpectrumBarCount)
        systemAudioSpectrumService = SystemAudioSpectrumService(barCount: WallpaperEngine.defaultSpectrumBarCount)
        super.init()
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        scanDisplays()
    }

    public func setWallpaper(
        _ wallpaper: VideoWallpaper,
        multiDisplayEnabled: Bool,
        videoFillMode: String,
        shouldLoopCurrentItem: Bool
    ) {
        // 对外统一入口接收每个合法切换；交互去抖由调用层负责。
        beginPlaybackIntent()
        pendingVideoRetirementOnWebReady = false
        applyWallpaper(
            wallpaper,
            multiDisplayEnabled: multiDisplayEnabled,
            videoFillMode: videoFillMode,
            shouldLoopCurrentItem: shouldLoopCurrentItem
        )
    }

    func applyWallpaper(
        _ wallpaper: VideoWallpaper,
        multiDisplayEnabled: Bool,
        videoFillMode: String,
        shouldLoopCurrentItem: Bool
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
    currentWebRecordID = nil
            currentWebRequestID = nil
        }

        // 先更新内存态，再决定是否复用现有 daemon session 或下发新的 play 命令。
        currentWallpaper = wallpaper
        currentContentPath = incomingNormalizedPath
        currentPlaybackContentKind = .video
        currentVideoFillMode = videoFillMode
        currentMultiDisplayEnabled = multiDisplayEnabled
        currentShouldLoopCurrentItem = shouldLoopCurrentItem

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
            PlaybackPolicyController.shared.refresh()
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

        PlaybackPolicyController.shared.refresh()
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    func beginPlaybackIntent() {
        playbackIntentEpoch &+= 1
    }

    /// E2a-1 read-only injection: adopts the product-level intent epoch
    /// published by the selection authority. Monotonic — internal restarts
    /// (web host failover) keep their own increment; a stale product value
    /// is ignored. The daemon recovery guard's equality comparison keeps
    /// detecting any newer intent either way.
    public func adoptIntentEpoch(_ product: UInt64) {
        playbackIntentEpoch = PlaybackIntentEpoch.adopted(
            mirror: playbackIntentEpoch,
            product: product
        )
    }

    public func stopPlayback() {
        beginPlaybackIntent()
        // E2a-4: a staged web launch retains video sessions; stopping the
        // web side must retire them too or they zombie (visible + audible).
        let retirePendingVideo = pendingVideoRetirementOnWebReady
        pendingVideoRetirementOnWebReady = false
        retainedVideoWallpaper = nil
        retainedVideoContentPath = nil
        retainedVideoMultiDisplayEnabled = nil
        if currentPlaybackContentKind == .web {
            setWebAudioSpectrumRequested(false)
            if retirePendingVideo {
                for displayID in Array(displaySessions.keys) {
                    terminateSession(for: displayID)
                }
            }
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
        currentWallpaper = nil
    }

    public func cleanup() {
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
    }

    public func setVolume(_ volume: Float) {
        let fallback = currentVolumeNormalized * 100
        let sanitized = volume.isFinite ? min(max(volume, 0), 100) : fallback
        let normalizedVolume = sanitized / 100
        currentVolumeNormalized = normalizedVolume
        let effectiveVolume = PlaybackMuteState.shared.isMuted ? 0 : normalizedVolume

        if currentPlaybackContentKind == .web {
            dispatchWebRuntimeCommand(.setVolume(effectiveVolume))
        }
        // A preparing Web surface may still retain the previous video sessions.
        // Every live surface obeys the same result throughout the transition.
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "setVolume", videoPath: nil, framePath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: effectiveVolume, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
        }
    }

    public func setFillMode(_ fillMode: String) {
        // 同步镜像：屏幕参数变化/daemon 崩溃恢复重发 play 时读取的是
        // 引擎镜像，不更新会把填充模式回跳到上一次装载时的值。
        currentVideoFillMode = fillMode
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "setFillMode", videoPath: nil, framePath: nil, propertiesJSON: nil, fillMode: fillMode, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
        }
    }

    public func setLoopCurrentItem(_ shouldLoop: Bool) {
        // 只更新循环状态，不重载视频，避免切换自动切换开关时画面闪烁。
        // 不做去重，确保每次开关操作都能可靠送达 daemon。
        currentShouldLoopCurrentItem = shouldLoop
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "setLoop", videoPath: nil, framePath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: shouldLoop, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
        }
    }

    public func setPlaybackRate(_ rate: Float) {
        // Web 宿主可独立调整速率，不能为了调速而意外恢复已经暂停的页面。
        let clampedRate = max(0.25, min(2.0, rate))
        targetPlaybackRate = clampedRate
        if currentPlaybackContentKind == .web {
            dispatchWebRuntimeCommand(.setPlaybackRate(clampedRate))
        }
        guard !playbackPaused else { return }
        // A preparing Web surface may still retain the previous video sessions.
        // Every live surface obeys the same result throughout the transition.
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "resume", videoPath: nil, framePath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: clampedRate, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
        }
    }

    public func isPlaying() -> Bool {
        guard !playbackPaused else { return false }

        if currentPlaybackContentKind == .web {
            return currentContentPath != nil
        }

        return displaySessions.values.contains { $0.process.isRunning }
    }

    public func togglePlayback() {
        PlaybackCommandMultiplexer.shared.dispatch(playbackPaused ? .resume : .pause)
    }

    public func refreshPlaybackState() {
        // 状态评估只走统一入口，避免 UI / 系统通知各自直接改 pause 状态。
        PlaybackPolicyController.shared.refresh()
    }

    public func getCurrentWallpaper() -> VideoWallpaper? {
        currentWallpaper
    }

}
