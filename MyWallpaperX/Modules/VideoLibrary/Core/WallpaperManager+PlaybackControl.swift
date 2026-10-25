import Foundation
import QuartzCore

extension WallpaperManager {
    var librarySequenceMode: WallpaperPlaybackSequence.Mode {
        switch playbackMode() {
        case .loop: return .loop
        case .random: return .random
        case .sequential: return .sequential
        }
    }

    func navigateLibraryPlayback(_ direction: ManualNavigationDirection,
                                 policy: WallpaperPlaybackSequence.NavigationPolicy = .adjacent) {
        if libraryPlaybackSequence.committed == nil {
            guard libraryPlaybackSequence.pending == nil, playbackSwitch.pending == nil,
                  let snapshot = libraryPlaybackSnapshotProvider?(nil, .global, .manualNavigation), snapshot.source == .global else { return }
            let playable = snapshot.entries.filter(\.isPlayable)
            guard let first = direction == .next ? playable.first : playable.last else { return }
            _ = requestLibraryPlayback(reference: first.reference, from: snapshot, cause: .manualNavigation)
            return
        }
        guard let proposal = libraryPlaybackSequence.proposeAdvance(direction == .next ? .next : .previous,
            policy: policy, mode: librarySequenceMode, cause: .manualNavigation,
            chooseIndex: { Int.random(in: 0..<$0) }) else { return }
        _ = dispatchLibraryPlayback(proposal)
    }

    @discardableResult
    func advanceLibraryPlayback(cause: WallpaperPlaybackCause) -> Bool {
        guard let proposal = libraryPlaybackSequence.proposeAdvance(policy: .randomHistory,
            mode: librarySequenceMode, cause: cause, chooseIndex: { Int.random(in: 0..<$0) }) else {
            libraryRotationDeadline.preparationFailed(now: CACurrentMediaTime())
            refreshAutoSwitchTimerIfNeeded()
            return false
        }
        // A synchronous failure can already have advanced to another candidate
        // or settled Stop. Only absence of a proposal means no attempt existed.
        _ = dispatchLibraryPlayback(proposal)
        return true
    }

    func updateLibraryPlaybackSource(_ snapshot: WallpaperPlaybackSequence.Snapshot,
                                     reason: WallpaperPlaybackSequence.SourceUpdateReason,
                                     targetTicket: PlaybackSwitchTicket? = nil) {
        libraryPlaybackSequence.updateSource(snapshot, reason: reason, targetTicket: targetTicket)
        refreshAutoSwitchTimerIfNeeded()
    }

    func navigateWallpaperManually(_ direction: ManualNavigationDirection) {
        guard libraryPlaybackSequence.committed != nil else { return }
        // 手动切换统一走去抖调度，避免工具栏/快捷键/鼠标连点同时打到同一条切换链路。
        guard !scheduleManualNavigationIfNeeded(direction) else { return }
        navigateLibraryPlayback(direction, policy: .randomHistory)
    }

    private func scheduleManualNavigationIfNeeded(_ direction: ManualNavigationDirection) -> Bool {
        // 在最小间隔内合并重复导航，只保留最后一次方向。
        let generation = libraryPlaybackSequence.rotationGeneration
        let now = CACurrentMediaTime()
        let elapsed = now - lastManualNavigationAt

        if elapsed >= manualNavigationMinInterval {
            pendingManualNavigationWorkItem?.cancel()
            pendingManualNavigationWorkItem = nil
            pendingManualNavigationDirection = nil
            lastManualNavigationAt = now
            return false
        }

        pendingManualNavigationDirection = direction
        pendingManualNavigationWorkItem?.cancel()

        let delay = manualNavigationMinInterval - elapsed
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.libraryPlaybackSequence.rotationGeneration == generation else { return }
            guard let pendingDirection = self.pendingManualNavigationDirection else { return }
            self.pendingManualNavigationDirection = nil
            self.pendingManualNavigationWorkItem = nil
            self.lastManualNavigationAt = CACurrentMediaTime()
            self.navigateLibraryPlayback(pendingDirection, policy: .randomHistory)
        }

        pendingManualNavigationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return true
    }

    func handlePlaybackEnded(forPath path: String) {
        guard let session = libraryPlaybackSequence.committed,
              libraryPlaybackSequence.pending == nil, session.ticket.runtime == .video,
              playbackSwitch.committed?.ticket == session.ticket,
              normalizedPath(currentWallpaper?.path ?? "") == normalizedPath(path),
              !PlaybackCommandMultiplexer.shared.isPlaybackPaused else { return }
        if settings.autoSwitchEnabled { WallpaperEngine.shared.setLoopCurrentItem(true) }
        else { advanceLibraryPlayback(cause: .ended) }
    }
}
