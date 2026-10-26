//
//  WallpaperManager+WallpaperApplication.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import QuartzCore

extension WallpaperManager {
    func setAsWallpaper(_ wallpaper: VideoWallpaper,
                        admission: ImportedVideoPlaybackAdmission? = nil,
                        libraryPending: WallpaperPlaybackSequence.Pending? = nil) {
        let libraryPending = libraryPending ?? admission?.libraryPending
        guard let libraryPending else {
            _ = requestLibraryPlayback(reference: .init(provider: .videoLibrary, sourceID: wallpaper.id))
            return
        }
        guard acceptsLibraryPlayback(libraryPending), libraryPending.ticket.runtime == .video else { return }
        if let admission, !acceptsImportedVideoPlayback(admission) { return }
        let targetPath = normalizedPath(wallpaper.path)
        guard pathExists(targetPath) else {
            switchFailed(libraryPending.ticket, reason: "视频文件已不可用，已保留原壁纸")
            return
        }
        pendingWallpaper = wallpaper
        NotificationCenter.default.post(name: .onlineDownloadsPlaybackPathDidChange,
                                       object: nil, userInfo: ["path": targetPath])
        guard acceptsLibraryPlayback(libraryPending) else { return }
        prepareVideoSwitch(wallpaper, admission: admission, libraryPending: libraryPending)
        PlaybackVolumeState.shared.setNormalizedVolume(Float(settings.volume / 100))
        PlaybackCommandMultiplexer.shared.dispatch(.setVolume(Float(settings.volume)))
    }

    func requestSetAsWallpaper(_ wallpaper: VideoWallpaper) {
        let now = CACurrentMediaTime()
        guard now - lastInteractiveWallpaperSetTime > interactiveWallpaperSetDebounceInterval else { return }
        lastInteractiveWallpaperSetTime = now
        _ = requestLibraryPlayback(reference: .init(provider: .videoLibrary, sourceID: wallpaper.id))
    }

    func syncSystemWallpaper(with wallpaper: VideoWallpaper) {
        let committedExecution = playbackSwitch.committed
        // 同步系统壁纸优先用已缓存静帧，只有缓存存在时才写系统桌面图。
        if let staticFramePath = wallpaper.staticFramePath,
           pathExists(staticFramePath) {
            applySystemWallpaperSync(from: staticFramePath)
            return
        }

        let url = URL(fileURLWithPath: wallpaper.path)
        // 静帧 owner 统一查询缓存，未命中才异步生成。
        generateStaticFrameIfNeeded(for: url) { [weak self] path in
            guard let self, let path else { return }
            // 确认用户当前壁纸未切走
            guard self.playbackSwitch.committed == committedExecution,
                  self.currentWallpaper?.path == wallpaper.path,
                  self.settings.syncSystemWallpaper else { return }
            self.applySystemWallpaperSync(from: path)
        }
    }

    private func applySystemWallpaperSync(from imagePath: String) {
        setDesktopWallpaper(from: imagePath)
    }

    private func setDesktopWallpaper(from imagePath: String) {
        let sourceURL = URL(fileURLWithPath: imagePath)
        // macOS 桌面服务以文件 URL 为缓存键：同 URL 重复 setDesktop
        // ImageURL 会被静默去重（文件内容覆盖也不刷新桌面）。同步帧的
        // 源文件名是稳定的（<hash>_frame.jpg / runtime-sync-<kind>.jpg），
        // 第二次同步同一路径就会"看起来没同步"。因此每次同步先拷贝到
        // 唯一命名的副本，用新 URL 强制桌面刷新，写完清掉上一次的副本。
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let desktopCopyURL = staticFrameCacheDirectory
            .appendingPathComponent("system-wallpaper-active-\(stamp).jpg")
        do {
            try? FileManager.default.removeItem(at: desktopCopyURL)
            try FileManager.default.copyItem(at: sourceURL, to: desktopCopyURL)
        } catch {
            // 拷贝失败退回直接引用源文件（同 URL 去重风险可接受，至少不倒退）。
#if DEBUG
            NSLog(
                "MWX SystemWallpaperSync: desktop copy failed: %@",
                String(describing: error)
            )
#endif
            applySourceImageDirectly(sourceURL)
            return
        }
        if applySourceImageDirectly(desktopCopyURL) {
            // 至少一屏成功才清理历史副本；全屏失败时桌面偏好仍指向上一份
            // 副本，不能把它删成悬挂引用。
            removePreviousDesktopCopies(keeping: desktopCopyURL)
        }
    }

    /// 逐屏应用；返回是否至少一屏成功。
    @discardableResult
    private func applySourceImageDirectly(_ imageURL: URL) -> Bool {
        let workspace = NSWorkspace.shared
        var didApplyAnyScreen = false
        for screen in NSScreen.screens {
            let previousURL = workspace.desktopImageURL(for: screen)
            let previousOptions = workspace.desktopImageOptions(for: screen) ?? [:]
            do {
                try workspace.setDesktopImageURL(imageURL, for: screen, options: [:])
                rememberSystemDesktopWrite(imageURL, on: screen, previousURL: previousURL, options: previousOptions)
                didApplyAnyScreen = true
            } catch {
                // 系统壁纸同步失败时静默忽略，不影响视频壁纸播放。
            }
        }
        return didApplyAnyScreen
    }

    /// A process-local baseline over the existing desktop writer. Repeated
    /// pictures and later sync frames never replace the user's first settings.
    func rememberSystemDesktopWrite(_ url: URL, on screen: NSScreen, previousURL: URL?,
                                    options: [NSWorkspace.DesktopImageOptionKey: Any]) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let id = number.uint32Value
        let actualOptions = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        if systemDesktopWallpapers[id] != nil {
            systemDesktopWallpapers[id]?.lastWrittenURL = url
            systemDesktopWallpapers[id]?.lastWrittenOptions = actualOptions
        } else {
            systemDesktopWallpapers[id] = .init(originalURL: previousURL, originalOptions: options,
                lastWrittenURL: url, lastWrittenOptions: actualOptions)
        }
    }

    /// Only a successful static-image application grants exit restoration.
    /// Dynamic-only runs preserve their existing exit behavior. A subsequent
    /// external desktop choice is not an App-owned value to replace.
    func restoreSystemDesktopWallpaperOnTermination() {
        defer { systemDesktopWallpapers.removeAll(); didApplySystemStillThisRun = false }
        guard didApplySystemStillThisRun, !settings.syncSystemWallpaper else { return }
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let saved = systemDesktopWallpapers[number.uint32Value], let original = saved.originalURL,
                  workspace.desktopImageURL(for: screen) == saved.lastWrittenURL,
                  NSDictionary(dictionary: workspace.desktopImageOptions(for: screen) ?? [:])
                    .isEqual(NSDictionary(dictionary: saved.lastWrittenOptions)) else { continue }
            do { try workspace.setDesktopImageURL(original, for: screen, options: saved.originalOptions) }
            catch { NSLog("MWX desktop restoration failed: %@", error.localizedDescription) }
        }
    }

    /// At most two URLs per display, never a library or copied user media.
    /// Existing cache cleanup must not remove the baseline or current desktop.
    var protectedSystemDesktopURLs: Set<URL> {
        Set(systemDesktopWallpapers.values.flatMap { [$0.originalURL, $0.lastWrittenURL].compactMap { $0 } })
    }

    func clearUnprotectedStaticFrameFiles() {
        let protected = protectedSystemDesktopURLs
        let directory = staticFrameCacheDirectory
        if protected.isEmpty { try? FileManager.default.removeItem(at: directory); return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !protected.contains(file) { try? FileManager.default.removeItem(at: file) }
    }

    /// Retain only the current sync copy and the bounded desktop ownership URLs.
    private func removePreviousDesktopCopies(keeping current: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: staticFrameCacheDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let protected = protectedSystemDesktopURLs
        for item in contents where item.lastPathComponent.hasPrefix("system-wallpaper-active-") {
            guard item != current, !protected.contains(item) else { continue }
            try? FileManager.default.removeItem(at: item)
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
    /// 已切换走的壁纸，回调时按运行时身份二次守卫。Web/Scene 表面均属独立播放进程，经各自的自截回传通道。
    func scheduleRuntimeFrameSystemWallpaperSync(
        kind: RuntimeFrameSyncKind,
        recordID: String
    ) {
        pendingSystemWallpaperSyncWorkItem?.cancel()
        pendingSystemWallpaperSyncWorkItem = nil
        guard settings.syncSystemWallpaper else { return }
        let committedExecution = playbackSwitch.committed
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.settings.syncSystemWallpaper,
                  self.playbackSwitch.committed == committedExecution,
                  self.activeRuntimeMatchesFrameSyncTarget(kind, recordID: recordID)
            else { return }
            switch kind {
            case .web:
                WallpaperEngine.shared.captureWebWallpaperFrame { [weak self] image in
                        guard let self,
                              self.settings.syncSystemWallpaper,
                              self.playbackSwitch.committed == committedExecution,
                  self.activeRuntimeMatchesFrameSyncTarget(
                                  kind,
                                  recordID: recordID
                              ),
                              let image else {
                            return
                        }
                        // TIFF→JPEG 编码与落盘是 CPU/IO 重活，移出主线程，
                        // 避免卡住正在播放的壁纸 UI；应用桌面仍回主线程
                        // （NSScreen/setDesktopImageURL 的 AppKit 主线程合同）。
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            guard let self,
                                  let imageURL = self.persistRuntimeSyncFrame(
                                      image,
                                      kind: kind
                                  ) else {
                                return
                            }
                            // 编码窗口内壁纸可能已切走，应用前二次守卫：
                            // 迟到帧不得写进已切换走的壁纸。
                            DispatchQueue.main.async { [weak self] in
                                guard let self,
                                      self.settings.syncSystemWallpaper,
                                      self.playbackSwitch.committed == committedExecution,
                  self.activeRuntimeMatchesFrameSyncTarget(
                                          kind,
                                          recordID: recordID
                                      ) else {
                                    return
                                }
                                self.setDesktopWallpaper(from: imageURL.path)
                            }
                        }
                    }
            case .scene:
                SceneDaemonClient.shared.captureSurfaceFrame { [weak self] frameURL in
                    guard let self, let frameURL else { return }
                    // 守卫失败也清掉 daemon 侧临时帧，避免 /private/tmp 残留。
                    defer { try? FileManager.default.removeItem(at: frameURL) }
                    guard self.settings.syncSystemWallpaper,
                          self.playbackSwitch.committed == committedExecution,
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
#if DEBUG
            NSLog(
                "MWX SystemWallpaperSync: scene frame copy failed: %@",
                String(describing: error)
            )
#endif
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
            try jpeg.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }



    func updateCurrentWallpaperIndex(for wallpaperID: String) {
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
        let message = "源文件已缺失，可重新定位或导入：\n\(preview)\(suffix)"

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
        let message = "已从视频库移除缺失文件：\n\(preview)\(suffix)"

        let alert = makeAppAlert(
            title: "已移除失效文件",
            message: message,
            style: .warning,
            buttons: ["知道了"]
        )
        presentAppAlert(alert, in: appModalHostWindow())
    }
}
