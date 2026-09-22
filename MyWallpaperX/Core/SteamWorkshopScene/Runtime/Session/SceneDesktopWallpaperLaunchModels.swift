import Foundation

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
    }

    let requestID: UUID
    let recordID: String?
    let phase: Phase
    let message: String

    var isInProgress: Bool {
        switch phase {
        case .accepted, .preparingModel, .preparingPrograms,
             .preparingResources, .preparingSurfaces:
            true
        case .launched, .cancelled, .failed:
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

    func check() throws {
        lock.lock()
        let isCancelled = cancelled
        lock.unlock()
        if isCancelled {
            throw SceneDesktopWallpaperHostLaunchError.cancelled
        }
    }
}

enum SceneDesktopWallpaperHostLaunchError: LocalizedError {
    case cancelled
    case missingPackageCache
    case conflictingBoundedSceneScriptTargets(String)
    case invalidBoundedSceneScriptProgramAt(String)
    case requiredImagePipelineUnavailable
    case noSurface

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Scene 启动请求已取消。"
        case .missingPackageCache:
            "Scene 资源缓存不可用。"
        case .conflictingBoundedSceneScriptTargets(let details):
            "Scene 有界脚本目标存在冲突，已停止启动。\(details)"
        case .invalidBoundedSceneScriptProgramAt(let phase):
            "Scene 有界脚本目标在 \(phase) 无法形成，已停止启动。"
        case .requiredImagePipelineUnavailable:
            "Scene 必需的图像合成 pipeline 无法形成，已保留当前壁纸。"
        case .noSurface:
            "Scene 宿主未能创建可播放表面。"
        }
    }
}
