import Foundation

/// A launch-time observation of real prepared callback consumers. The Host
/// remains the authority for each later update; this only projects panel rows.
nonisolated struct ScenePreparedCallbackPropertyReachability: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Sendable {
        let rootPath: String
        let projectWitness: String
        let sceneWitness: String
    }
    let source: Source
    let scriptGeneration: UInt64
    let propertyKeys: Set<String>
}

nonisolated struct SceneWallpaperLaunchState: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case accepted
        case preparingModel
        case preparingPrograms
        case preparingResources
        case preparingSurfaces
        case launched
        case cancelled
        case failed
        /// E2a-2: a user-requested `.stop` completed. Emitted only from the
        /// command path — switching away from Scene stays silent so the
        /// incoming runtime's commit is never raced by a stale recycle.
        case stopped
    }

    let requestID: UUID
    let recordID: String?
    let phase: Phase
    let message: String
    var callbackPropertyReachability: ScenePreparedCallbackPropertyReachability? = nil

    var isInProgress: Bool {
        switch phase {
        case .accepted, .preparingModel, .preparingPrograms,
             .preparingResources, .preparingSurfaces:
            true
        case .launched, .cancelled, .failed, .stopped:
            false
        }
    }
}

extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange = Notification.Name(
        "SceneWallpaperLaunchStateDidChange"
    )
}

nonisolated final class SceneWallpaperLaunchCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func check() throws {
        if isCancelled {
            throw SceneDesktopWallpaperHostLaunchError.cancelled
        }
    }
}

enum SceneDesktopWallpaperHostLaunchError: LocalizedError {
    case cancelled
    case conflictingBoundedSceneScriptTargets(String)
    case invalidBoundedSceneScriptProgramAt(String)
    case requiredImagePipelineUnavailable
    case requiredUserTextureUnavailable
    case noSurface
    case firstFrameFailed
    case firstFrameTimeout

    var errorDescription: String? {
        switch self {
        case .cancelled:
            String(localized: "Scene launch request was canceled.")
        case .conflictingBoundedSceneScriptTargets(let details):
            String(localized: "The bounded Scene script target has a conflict; launch stopped. \(details)")
        case .invalidBoundedSceneScriptProgramAt(let phase):
            String(localized: "The bounded Scene script target couldn’t be formed in \(phase); launch stopped.")
        case .requiredImagePipelineUnavailable:
            String(localized: "The image compositing pipeline required by Scene couldn’t be built; the current wallpaper was kept.")
        case .requiredUserTextureUnavailable:
            String(localized: "The images selected by Scene couldn’t be fully prepared; the current wallpaper was kept.")
        case .firstFrameFailed:
            String(localized: "The Scene candidate’s first frame failed to run; the current wallpaper was kept.")
        case .firstFrameTimeout:
            String(localized: "Timed out waiting for the Scene candidate’s first frame; the current wallpaper was kept.")
        case .noSurface:
            String(localized: "The Scene host couldn’t create a playable surface.")
        }
    }
}
