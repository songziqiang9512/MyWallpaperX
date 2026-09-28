//
//  WallpaperManager+WallpaperApplication.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import QuartzCore

extension WallpaperManager {
    func setAsWallpaper(
        _ wallpaper: VideoWallpaper,
        userInitiated: Bool = false,
        recordHistory: Bool = true,
        updateRecentList: Bool = true
    ) {
        // 设为壁纸是全局切换入口：当前播放、最近使用、系统壁纸同步都从这里串起来。
        let normalizedTargetPath = normalizedPath(wallpaper.path)
        guard pathExists(normalizedTargetPath) else {
            handleMissingWallpaperDuringSwitch(wallpaper, userInitiated: userInitiated)
            return
        }

        recordPlaybackHistoryIfNeeded(
            current: currentWallpaper,
            targetNormalizedPath: normalizedTargetPath,
            enabled: recordHistory
        )

        // E2a-3: requested 层立即写（UI 高亮即时）；committed
        // currentWallpaper 延后到 daemon ready 事件提交——失败项真值不落地。
        pendingWallpaper = wallpaper
        activeWallpaperRuntime = .video
        NotificationCenter.default.post(
            name: .onlineDownloadsPlaybackPathDidChange,
            object: nil,
            userInfo: ["path": normalizedTargetPath]
        )

        // 同步当前索引（避免切换时触发全库高频写入）
        updateCurrentWallpaperIndex(for: wallpaper.id)

        // 更新最近使用列表
        if updateRecentList {
            updateRecentWallpapers(wallpaper)
        }

        // 实际播放逻辑：使用WallpaperEngine设置壁纸
        // E2a-1: 切换入口先推进产品意图纪元并注入引擎（只读注入，
        // 提交点不变）。
        WallpaperEngine.shared.adoptIntentEpoch(beginPlaybackIntent())
        postWallpaperRuntimeWillSwitch(to: .video)
        WallpaperEngine.shared.setWallpaper(
            wallpaper,
            multiDisplayEnabled: settings.multiDisplayEnabled,
            videoFillMode: settings.videoFillMode.ipcValue,
            shouldLoopCurrentItem: shouldLoopCurrentItemInEngine()
        )
        isPlaying = WallpaperEngine.shared.isPlaying()
        PlaybackVolumeState.shared.setNormalizedVolume(Float(settings.volume / 100))
        PlaybackCommandMultiplexer.shared.dispatch(.setVolume(Float(settings.volume)))
        applySystemAudioSpectrumToEngine()

        if settings.autoSwitchEnabled && userInitiated {
            // 用户手动切换时立即重置 timer，从 0 重新计时。
            startAutoSwitchTimer()
        }

        if userInitiated {
            // 记录用户点击播放时所在的列表，后续自动切换都在此列表内进行。
            playbackSourceContext = currentSelectionContext
        }

        // 同步改变系统壁纸
        pendingSystemWallpaperSyncWorkItem?.cancel()
        pendingSystemWallpaperSyncWorkItem = nil
        if settings.syncSystemWallpaper {
            let syncWorkItem = DispatchWorkItem { [weak self] in
                self?.syncSystemWallpaper(with: wallpaper)
            }
            pendingSystemWallpaperSyncWorkItem = syncWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: syncWorkItem)
        }
    }

    func requestSetAsWallpaper(_ wallpaper: VideoWallpaper) {
        // 用户点击卡片/按钮的入口加了节流，防止高频重复点击把切换链路打爆。
        if currentWallpaper?.path == wallpaper.path {
            return
        }

        let currentTime = CACurrentMediaTime()
        guard currentTime - lastInteractiveWallpaperSetTime > interactiveWallpaperSetDebounceInterval else {
            return
        }
        lastInteractiveWallpaperSetTime = currentTime
        // 用户手动点击选择视频，清空前进和后退历史，重建新的播放历史链路。
        playbackForwardPaths.removeAll()
        playbackHistoryPaths.removeAll()
        setAsWallpaper(wallpaper, userInitiated: true)
    }

    private func handleMissingWallpaperDuringSwitch(_ wallpaper: VideoWallpaper, userInitiated: Bool) {
        // 当前项缺失时先清理索引，再找下一张可播项，避免界面停留在坏引用上。
        let normalized = normalizedPath(wallpaper.path)
        let title = wallpaper.displayTitle

        purgeMissingWallpaperFromIndex(path: normalized, displayTitle: title, notifyUser: userInitiated)

        guard let fallback = nextPlayableWallpaper(afterMissingPath: normalized) else {
            clearCurrentWallpaperAndStopPlayback()
            return
        }

        setAsWallpaper(fallback, userInitiated: false)
    }

    private func purgeMissingWallpaperFromIndex(path: String, displayTitle: String, notifyUser: Bool) {
        let normalized = normalizedPath(path)
        let matched = wallpapers.filter { normalizedPath($0.path) == normalized }
        let removedIDs = Set(matched.map(\.id))

        if !matched.isEmpty {
            for item in matched {
                removeDerivedAssets(for: removalRecord(for: item))
            }

            removeWallpapersFromCollections([normalized])
            clearSelectionAndPendingState(removedIDs)
            saveWallpapers()
        }

        if notifyUser {
            reportMissingIndexedFile(path: normalized, displayTitle: displayTitle)
        }
    }

    private func nextPlayableWallpaper(afterMissingPath failedPath: String) -> VideoWallpaper? {
        var attempts = 0
        // 循环前快照上限，避免每次删除后 wallpapers.count 缩减导致提前退出。
        let maxAttempts = max(1, wallpapers.count)
        while attempts < maxAttempts {
            guard let candidate = nextWallpaperAfterFailure(failedPath: failedPath) ?? wallpapers.first else {
                return nil
            }

            if purgeMissingCandidateIfNeeded(candidate) {
                attempts += 1
                continue
            }
            return candidate
        }
        return nil
    }

    private func purgeMissingCandidateIfNeeded(_ candidate: VideoWallpaper) -> Bool {
        let candidatePath = normalizedPath(candidate.path)
        guard !pathExists(candidatePath) else {
            return false
        }

        let candidateTitle = candidate.displayTitle
        purgeMissingWallpaperFromIndex(path: candidatePath, displayTitle: candidateTitle, notifyUser: false)
        return true
    }

    private func syncSystemWallpaper(with wallpaper: VideoWallpaper) {
        // 同步系统壁纸优先用已缓存静帧，只有缓存存在时才写系统桌面图。
        if let staticFramePath = wallpaper.staticFramePath,
           pathExists(staticFramePath) {
            applySystemWallpaperSync(from: staticFramePath)
            return
        }

        let url = URL(fileURLWithPath: wallpaper.path)
        if let cachedPath = existingStaticFramePath(for: url) {
            updateWallpaperAssetPaths(forPath: wallpaper.path, staticFramePath: cachedPath)
            applySystemWallpaperSync(from: cachedPath)
            return
        }

        // 静帧尚未生成，异步生成后再同步系统壁纸。
        generateStaticFrameIfNeeded(for: url) { [weak self] path in
            guard let self, let path else { return }
            // 确认用户当前壁纸未切走
            guard self.effectiveCurrentWallpaper?.path == wallpaper.path,
                  self.settings.syncSystemWallpaper else { return }
            self.applySystemWallpaperSync(from: path)
        }
    }

    private func applySystemWallpaperSync(from imagePath: String) {
        setDesktopWallpaper(from: imagePath)
    }

    private func setDesktopWallpaper(from imagePath: String) {
        let imageURL = URL(fileURLWithPath: imagePath)
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            do {
                try workspace.setDesktopImageURL(imageURL, for: screen, options: [:])
            } catch {
                // 系统壁纸同步失败时静默忽略，不影响视频壁纸播放。
            }
        }
    }

    /// web/scene 壁纸同步系统壁纸的运行时种类。
    enum RuntimeFrameSyncKind {
        case web
        case scene

        var logLabel: String {
            switch self {
            case .web: return "web"
            case .scene: return "scene"
            }
        }
    }

    /// 截帧延迟：覆盖 web/scene 样本常见的启动过渡动画后再取帧。
    private static let runtimeFrameSyncDelay: TimeInterval = 5

    /// web/scene 没有可提取的媒体静帧；按用户语义在启动过渡结束后截取
    /// 壁纸层一帧作为系统壁纸。延迟覆盖样本的开场动画；迟到帧不得写进
    /// 已切换走的壁纸，回调时按运行时身份二次守卫。web 宿主在主 App
    /// 进程内（免权限自截）；scene 表面属 daemon 子进程，经自截回传通道。
    func scheduleRuntimeFrameSystemWallpaperSync(
        kind: RuntimeFrameSyncKind,
        recordID: String
    ) {
        pendingSystemWallpaperSyncWorkItem?.cancel()
        pendingSystemWallpaperSyncWorkItem = nil
        guard settings.syncSystemWallpaper else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.settings.syncSystemWallpaper,
                  self.activeRuntimeMatchesFrameSyncTarget(kind, recordID: recordID)
            else { return }
            switch kind {
            case .web:
                WallpaperRuntimeFrameCapture
                    .captureInProcessWallpaperFrame { [weak self] image in
                        guard let self,
                              self.settings.syncSystemWallpaper,
                              self.activeRuntimeMatchesFrameSyncTarget(
                                  kind,
                                  recordID: recordID
                              ),
                              let image,
                              let imageURL = self.persistRuntimeSyncFrame(
                                  image,
                                  kind: kind
                              ) else {
                            return
                        }
                        self.setDesktopWallpaper(from: imageURL.path)
                    }
            case .scene:
                SceneDaemonClient.shared.captureSurfaceFrame { [weak self] frameURL in
                    guard let self, let frameURL else { return }
                    // 守卫失败也清掉 daemon 侧临时帧，避免 /private/tmp 残留。
                    defer { try? FileManager.default.removeItem(at: frameURL) }
                    guard self.settings.syncSystemWallpaper,
                          self.activeRuntimeMatchesFrameSyncTarget(
                              kind,
                              recordID: recordID
                          ) else {
                        return
                    }
                    self.applyRuntimeSyncFrameFile(frameURL, kind: kind)
                }
            }
        }
        pendingSystemWallpaperSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.runtimeFrameSyncDelay,
            execute: workItem
        )
    }

    private func activeRuntimeMatchesFrameSyncTarget(
        _ kind: RuntimeFrameSyncKind,
        recordID: String
    ) -> Bool {
        switch kind {
        case .web:
            return activeWallpaperRuntime == .web
                && WallpaperEngine.shared.currentWebRecordID == recordID
        case .scene:
            let activeRecordID = SceneDaemonClient.shared.activeRecordID
                ?? SceneDaemonClient.shared.launchState?.recordID
            return activeWallpaperRuntime == .scene
                && activeRecordID == recordID
                && !recordID.isEmpty
        }
    }

    /// scene 的 JPEG 已由 daemon 写好：拷入静帧缓存目录获得稳定文件名后
    /// 应用；daemon 侧临时帧由调用方的 defer 统一清理。
    private func applyRuntimeSyncFrameFile(
        _ source: URL,
        kind: RuntimeFrameSyncKind
    ) {
        let destination = staticFrameCacheDirectory
            .appendingPathComponent("runtime-sync-\(kind.logLabel).jpg")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            NSLog(
                "MWX SystemWallpaperSync: scene frame copy failed: %@",
                String(describing: error)
            )
            return
        }
        setDesktopWallpaper(from: destination.path)
    }

    /// 截帧落盘到静帧缓存目录（可重建派生数据），每运行时一个稳定文件名，
    /// 后一次同步覆盖前一次。格式与视频静帧管线一致（JPEG 0.9）。
    private func persistRuntimeSyncFrame(
        _ image: NSImage,
        kind: RuntimeFrameSyncKind
    ) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let jpeg = representation.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: 0.9]
              ) else {
            return nil
        }
        let url = staticFrameCacheDirectory
            .appendingPathComponent("runtime-sync-\(kind.logLabel).jpg")
        do {
            try jpeg.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func recordPlaybackHistoryIfNeeded(
        current: VideoWallpaper?,
        targetNormalizedPath: String,
        enabled: Bool
    ) {
        guard enabled, let current else { return }
        let normalizedCurrentPath = normalizedPath(current.path)
        // 目标和当前相同，不记录（原地切换）。
        guard normalizedCurrentPath != targetNormalizedPath else { return }
        // 注意：不做 last == current 的去重，避免 A→B→A 这种情况漏记 B。
        // 允许连续推入相同路径，pop 时自动跳过已从库中删除的项即可。
        playbackHistoryPaths.append(normalizedCurrentPath)
        if playbackHistoryPaths.count > playbackHistoryLimit {
            playbackHistoryPaths.removeFirst(playbackHistoryPaths.count - playbackHistoryLimit)
        }
    }

    private func updateCurrentWallpaperIndex(for wallpaperID: String) {
        if wallpapers.indices.contains(currentIndex),
           wallpapers[currentIndex].id == wallpaperID {
            return
        }
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaperID }) else { return }
        currentIndex = index
    }

    func reportMissingIndexedFile(path: String, displayTitle: String) {
        let normalized = normalizedPath(path)
        guard !missingIndexedFilePaths.contains(normalized) else { return }
        missingIndexedFilePaths.insert(normalized)
        pendingMissingIndexedTitles.insert(displayTitle)
        scheduleMissingIndexedFilesAlert()
    }

    private func scheduleMissingIndexedFilesAlert() {
        missingIndexedAlertWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.pendingMissingIndexedTitles.isEmpty else { return }
            let titles = self.pendingMissingIndexedTitles.sorted()
            self.pendingMissingIndexedTitles.removeAll()
            self.presentMissingIndexedFilesAlert(titles: titles)
        }
        missingIndexedAlertWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func presentMissingIndexedFilesAlert(titles: [String]) {
        guard !titles.isEmpty else { return }
        let preview = titles.prefix(5).joined(separator: "\n")
        let remaining = max(0, titles.count - 5)
        let suffix = remaining > 0 ? "\n还有 \(remaining) 个未显示" : ""
        let message = "检测到索引中的源文件已缺失：\n\(preview)\(suffix)\n\n请在列表中删除或重新导入这些项目。"

        let alert = makeAppAlert(
            title: "发现失效文件",
            message: message,
            style: .warning,
            buttons: ["知道了"]
        )
        presentAppAlert(alert, in: appModalHostWindow())
    }

    func presentAutoRemovedMissingIndexedFilesAlert(titles: [String]) {
        guard !titles.isEmpty else { return }
        let preview = titles.prefix(5).joined(separator: "\n")
        let remaining = max(0, titles.count - 5)
        let suffix = remaining > 0 ? "\n还有 \(remaining) 个未显示" : ""
        let message = "启动扫描发现以下源文件已缺失，系统已自动将它们从视频库移除：\n\(preview)\(suffix)\n\n对应缩略图与静帧缓存也已一并清理。"

        let alert = makeAppAlert(
            title: "已移除失效文件",
            message: message,
            style: .warning,
            buttons: ["知道了"]
        )
        presentAppAlert(alert, in: appModalHostWindow())
    }
}
