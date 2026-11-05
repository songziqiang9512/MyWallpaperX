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
            guard let first = direction == .next ? snapshot.entries.first(where: \.isPlayable)
                : snapshot.entries.last(where: \.isPlayable) else { return }
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
