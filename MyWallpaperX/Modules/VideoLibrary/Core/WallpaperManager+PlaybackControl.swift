//
//  WallpaperManager+PlaybackControl.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperManager {
    func navigateWallpaperManually(_ direction: ManualNavigationDirection, userInitiated: Bool = true) {
        guard !wallpapers.isEmpty else { return }
        // 手动切换统一走去抖调度，避免工具栏/快捷键/鼠标连点同时打到同一条切换链路。
        guard !scheduleManualNavigationIfNeeded(direction, userInitiated: userInitiated) else { return }
        performManualNavigation(direction, userInitiated: userInitiated)
    }

    private func performManualNavigation(_ direction: ManualNavigationDirection, userInitiated: Bool) {
        // 用户主动操作时，先更新播放来源为当前所在分类，再在新来源里计算下一张。
        if userInitiated {
            playbackSourceContext = currentSelectionContext
        }
        switch playbackMode() {
        case .random:
            performRandomModeNavigation(direction, userInitiated: userInitiated)
        case .sequential, .loop:
            // 循环模式下手动切换按顺序规则走，不影响自动播放行为。
            playSequentialVideo(direction, userInitiated: userInitiated)
        }
    }

    /// 随机模式的导航：
    /// - 上一张：弹出 backStack，当前推入 forwardStack
    /// - 下一张：优先消费 forwardStack；耗尽后随机，并清空 forwardStack
    private func performRandomModeNavigation(_ direction: ManualNavigationDirection, userInitiated: Bool) {
        switch direction {
        case .previous:
            // 弹出 backStack，跳过已从库中删除的路径，找到第一个有效的历史项。
            var previousWallpaper: VideoWallpaper?
            while !playbackHistoryPaths.isEmpty {
                let path = playbackHistoryPaths.removeLast()
                if let w = wallpaperFromLibrary(path: path) {
                    previousWallpaper = w
                    break
                }
            }
            guard let previousWallpaper else {
                // 历史耗尽，回退到顺序规则
                playSequentialVideo(.previous, userInitiated: userInitiated)
                return
            }
            // 当前视频推入 forwardStack，以便后续"下一张"能回来
            if let current = currentWallpaper {
                let normalizedCurrent = normalizedPath(current.path)
                playbackForwardPaths.append(normalizedCurrent)
                if playbackForwardPaths.count > playbackHistoryLimit {
                    playbackForwardPaths.removeFirst(playbackForwardPaths.count - playbackHistoryLimit)
                }
            }
            setAsWallpaper(previousWallpaper, userInitiated: userInitiated, recordHistory: false)

        case .next:
            if let forwardPath = playbackForwardPaths.popLast(),
               let forwardWallpaper = wallpaperFromLibrary(path: forwardPath) {
                // 消费 forwardStack，回到切上一张之前的视频
                setAsWallpaper(forwardWallpaper, userInitiated: userInitiated, recordHistory: true)
            } else {
                // forwardStack 耗尽，随机切换并清空（防止残留）
                playbackForwardPaths.removeAll()
                playNextRandomVideo(userInitiated: userInitiated)
            }
        }
    }

    private func scheduleManualNavigationIfNeeded(_ direction: ManualNavigationDirection, userInitiated: Bool) -> Bool {
        // 在最小间隔内合并重复导航，只保留最后一次方向和“是否用户主动触发”的信息。
        let now = CACurrentMediaTime()
        let elapsed = now - lastManualNavigationAt

        if elapsed >= manualNavigationMinInterval {
            pendingManualNavigationWorkItem?.cancel()
            pendingManualNavigationWorkItem = nil
            pendingManualNavigationDirection = nil
            pendingManualNavigationUserInitiated = false
            lastManualNavigationAt = now
            return false
        }

        pendingManualNavigationDirection = direction
        pendingManualNavigationUserInitiated = pendingManualNavigationUserInitiated || userInitiated
        pendingManualNavigationWorkItem?.cancel()

        let delay = manualNavigationMinInterval - elapsed
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let pendingDirection = self.pendingManualNavigationDirection else { return }
            let pendingUserInitiated = self.pendingManualNavigationUserInitiated

            self.pendingManualNavigationDirection = nil
            self.pendingManualNavigationUserInitiated = false
            self.pendingManualNavigationWorkItem = nil
            self.lastManualNavigationAt = CACurrentMediaTime()
            self.performManualNavigation(pendingDirection, userInitiated: pendingUserInitiated)
        }

        pendingManualNavigationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return true
    }

    func advanceWallpaperForCurrentMode(triggeredByTimer: Bool = false) {
        guard !wallpapers.isEmpty else {
            return
        }
        let userInitiated = !triggeredByTimer

        switch playbackMode() {
        case .random:
            playNextRandomVideo(userInitiated: userInitiated)
        case .sequential:
            playNextSequentialVideo(userInitiated: userInitiated)
        case .loop:
            // 循环模式下 timer 不推进，只响应手动切换。
            guard !triggeredByTimer else { return }
            playNextSequentialVideo(userInitiated: userInitiated)
        }
    }

    func playPreviousSequentialVideo(userInitiated: Bool = true) {
        playSequentialVideo(.previous, userInitiated: userInitiated)
    }

    func playNextSequentialVideo(userInitiated: Bool = true) {
        guard !wallpapers.isEmpty else { return }

        playSequentialVideo(.next, userInitiated: userInitiated)
    }

    private func playNextRandomVideo(userInitiated: Bool) {
        guard !wallpapers.isEmpty else { return }

        // 随机切换时清空 forwardStack，因为开始了新的随机分支。
        playbackForwardPaths.removeAll()

        // 随机模式避免原地重复抽中当前项，保证切换有真实变化。
        // 从播放来源列表取候选视频，不跨列表切换。
        let source = playbackSourceContext.sourceWallpapers(from: self)
        let pool = source.isEmpty ? wallpapers : source
        let currentID = currentWallpaper?.id
        let candidates = pool.filter { $0.id != currentID }
        let nextWallpaper = candidates.randomElement() ?? pool.first

        guard let nextWallpaper else { return }
        setAsWallpaper(nextWallpaper, userInitiated: userInitiated)
    }

    private func wallpaperFromLibrary(path: String) -> VideoWallpaper? {
        let normalized = normalizedPath(path)
        return wallpapers.first { normalizedPath($0.path) == normalized }
    }

    func handlePlaybackFailure(forPath path: String) {
        guard activeWallpaperRuntime == .video else { return }
        let normalizedFailedPath = normalizedPath(path)
        // E2a-3: 失败项可能在 requested 层（committed 仍指旧项）——按
        // effective 选择匹配，失败回退才能触发。
        guard normalizedPath(effectiveCurrentWallpaper?.path ?? "") == normalizedFailedPath else {
            return
        }

        // Engine 侧已有 1s 去重，Manager 侧不再重复过滤，直接执行故障切换。
        guard wallpapers.count > 1 else {
            return
        }

        guard let nextWallpaper = nextWallpaperAfterFailure(failedPath: normalizedFailedPath) else {
            return
        }

        setAsWallpaper(nextWallpaper, userInitiated: false)
    }

    func handlePlaybackEnded(forPath path: String) {
        guard activeWallpaperRuntime == .video else { return }
        // 循环模式：引擎循环，永不触发此事件，直接忽略。
        guard isSwitchingPlaybackMode() else { return }

        let normalizedEndedPath = normalizedPath(path)
        guard normalizedPath(currentWallpaper?.path ?? "") == normalizedEndedPath else { return }


        if settings.autoSwitchEnabled {
            // 自动切换开启时视频应该用 loopEndObservation 循环，不应触发 playbackEnded。
            // 如果意外触发（setLoop IPC 到达前视频已播完），重新发 setLoop=true 让 daemon 循环，
            // 不切换视频，timer 继续计时。
            WallpaperEngine.shared.setLoopCurrentItem(true)
        } else {
            // 自动切换关闭：视频播完按主模式切下一张，完全回归主模式逻辑。
            advanceWallpaperForCurrentMode(triggeredByTimer: false)
        }
    }

    func nextWallpaperAfterFailure(failedPath: String) -> VideoWallpaper? {
        // 失败回退优先保证“跳到可播放项”，随机模式随机，顺序模式按当前索引后移。
        let availableWallpapers = wallpapers.filter { normalizedPath($0.path) != failedPath }
        guard !availableWallpapers.isEmpty else { return nil }

        if case .random = playbackMode() {
            return availableWallpapers.randomElement()
        }

        let failedIndex = wallpapers.firstIndex { normalizedPath($0.path) == failedPath } ?? currentWallpaperIndex() ?? currentIndex
        guard !wallpapers.isEmpty else { return nil }

        for step in 1...wallpapers.count {
            let candidateIndex = (failedIndex + step) % wallpapers.count
            let candidate = wallpapers[candidateIndex]
            if normalizedPath(candidate.path) != failedPath {
                assert(Thread.isMainThread, "currentIndex must be written on main thread")
                currentIndex = candidateIndex
                return candidate
            }
        }

        return nil
    }

    private func playSequentialVideo(_ direction: ManualNavigationDirection, userInitiated: Bool) {
        guard !wallpapers.isEmpty else { return }
        let targetIndex = sequentialAdjacentIndex(for: direction, respectsSearchFilter: userInitiated)
        assert(Thread.isMainThread, "currentIndex must be written on main thread")
        currentIndex = targetIndex
        setAsWallpaper(wallpapers[targetIndex], userInitiated: userInitiated)
    }

    private func sequentialAdjacentIndex(for direction: ManualNavigationDirection, respectsSearchFilter: Bool = true) -> Int {
        guard !wallpapers.isEmpty else { return 0 }

        // 用播放来源列表（用户点击时所在的分类/标签）取视频，在该列表内顺序切换。
        // 不用 currentSelectionContext（当前 UI 选中的分类），避免用户切换到别的分类后播放列表跟着跑。
        let source = playbackSourceContext.sourceWallpapers(from: self)
        let selectionKey = playbackSourceContext.scrollPersistenceKey
        let sorted = sortedWallpapers(source.isEmpty ? wallpapers : source, selectionKey: selectionKey)

        let baseIndex: Int
        if let current = currentWallpaper,
           let idx = sorted.firstIndex(where: { $0.id == current.id }) {
            baseIndex = idx
        } else {
            baseIndex = 0
        }

        let nextSortedIndex: Int
        switch direction {
        case .previous:
            nextSortedIndex = (baseIndex - 1 + sorted.count) % sorted.count
        case .next:
            nextSortedIndex = (baseIndex + 1) % sorted.count
        }

        let targetWallpaper = sorted[nextSortedIndex]
        // 映射回主库索引，找不到时回落到 currentIndex（防御性处理）。
        return wallpapers.firstIndex(where: { $0.id == targetWallpaper.id }) ?? currentIndex
    }
}
