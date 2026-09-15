import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    func revealItem(_ record: SteamWorkshopDownloadRecord) {
        if record.contentType == .web {
            NSWorkspace.shared.activateFileViewerSelecting([
                record.ownEntryHTMLURL ?? record.projectFileURL ?? record.folderURL
            ])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([record.folderURL])
    }

    func promptDeleteIncompatibleWebSample(_ record: SteamWorkshopDownloadRecord) {
        let alert = makeAppAlert(
            title: "样本不兼容",
            message: "`\(record.title)` 已确认在系统 Safari 中也无法正常运行，当前按 Safari 基线视为不兼容。\n\n为避免继续触发高负载或卡顿，建议直接删除这个样本。",
            style: .warning,
            buttons: ["保留", "删除样本"]
        )
        presentAppAlert(alert, in: appModalHostWindow()) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            self.deleteDownload(itemID: record.id)
        }
    }

    func setAsWallpaper(_ record: SteamWorkshopDownloadRecord) {
        // M0.5：点击即进入 pending（≤1 runloop turn 渲染加载态）。
        // 早退路径立即清除；scene 由 launch 终态清除；video/web 由
        // runtime 切换通知清除，1.5s 兜底防挂死。
        markLaunchPending(recordID: record.id)
        if case let .missing(itemID) = record.dependencyStatus {
            clearLaunchPending(matching: record.id)
            let alert = makeAppAlert(
                title: "缺少依赖项",
                message: "`\(record.title)` 缺少依赖项 `\(itemID)`，当前无法直接播放。\n\n你可以现在下载这个依赖项，下载完成后再重新播放。",
                style: .warning,
                buttons: ["取消", "下载依赖项"]
            )
            presentAppAlert(alert, in: appModalHostWindow()) { [weak self] response in
                guard let self, response == .alertSecondButtonReturn else { return }
                self.requestMissingDependencyDownload(for: record)
            }
            return
        }

        guard canLaunchDownloadRecord(record) else {
            clearLaunchPending(matching: record.id)
            downloadError = record.contentType == .web
                ? "当前 WEB 样本仍存在运行阻断问题，暂时不能直接播放。"
                : "当前项目暂时不可播放。"
            return
        }

        // The immutable version remains readable until the concrete consumer
        // (Scene, Web, or the Video import pipeline) releases this token.
        let resourceLifetime = libraryVersionLifetime(for: record)

        if record.contentType == .scene {
            requestSceneRender(record, resourceLifetime: resourceLifetime)
            return
        }

        if record.contentType == .web {
            guard let playbackContext = resolvedWebPlaybackContext(for: record) else {
                clearLaunchPending(matching: record.id)
                downloadError = "没有找到可播放的 HTML 入口文件。"
                return
            }
            let runtimeProfile = recommendedWebRuntimeProfile(for: record)
            NotificationCenter.default.post(
                name: .steamWorkshopWebWallpaperReadyToPlay,
                object: nil,
                userInfo: [
                    "recordID": record.id,
                    "entryURL": playbackContext.effectiveEntryURL,
                    "rootURL": playbackContext.effectiveRootURL,
                    "propertiesJSON": playbackContext.propertyPayloadJSON as Any,
                    "language": playbackContext.language,
                    "runtimeProfile": runtimeProfile,
                    "resourceLifetime": resourceLifetime as Any
                ]
            )
            statusMessage = "已将 \(record.title) 发送到 HTML 网页壁纸实验宿主"
            scheduleLaunchPendingFallbackClear(recordID: record.id)
            return
        }

        guard let videoURL = record.videoURL else {
            clearLaunchPending(matching: record.id)
            downloadError = "没有找到可播放的视频文件。"
            return
        }
        let autoplayToken = ImportedVideoAutoplayGate.shared.claim()
        ImportedVideoPlaybackRequest(
            localURL: videoURL,
            autoplayToken: autoplayToken,
            resourceLifetime: resourceLifetime
        )
            .post(name: .steamWorkshopVideoReadyToPlay)
        statusMessage = "已将 \(record.title) 发送到视频库并准备播放"
        scheduleLaunchPendingFallbackClear(recordID: record.id)
    }

    // MARK: - Launch pending（M0.5）

    /// web/scene 用 recordID 归属通知清除 pending；video 没有 Steam
    /// identity 贯穿导入链，所以保留一次性兜底，且不让无归属旧通知
    /// 清除更新的点击。
    private func scheduleLaunchPendingFallbackClear(recordID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.clearLaunchPending(matching: recordID)
        }
    }

    func installLaunchPendingObservers() {
        NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let state = notification.object
                        as? SceneWallpaperLaunchState else { return }
                switch state.phase {
                case .launched, .failed, .cancelled:
                    guard let recordID = state.recordID else { return }
                    self.clearLaunchPending(matching: recordID)
                case .accepted, .preparingModel, .preparingPrograms,
                     .preparingResources, .preparingSurfaces:
                    break
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .wallpaperRuntimeWillSwitch, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let recordID = notification.userInfo?["recordID"]
                        as? String else { return }
                self.clearLaunchPending(matching: recordID)
            }
        }
    }

    func recommendedWebRuntimeProfile(for record: SteamWorkshopDownloadRecord) -> WallpaperEngine.WebRuntimeProfile {
        guard let model = resolvedWebRuntimeModel(for: record) else {
            return .standard
        }
        let flags = Set(model.runtimeRiskFlags)
        let requiresOriginCompatibility = flags.contains(.serviceWorkerRegistration)
            || flags.contains(.esModuleDependency)
            || flags.contains(.wasmStreamingUsage)
            || flags.contains(.customSchemeSensitiveWebGL)
            || flags.contains(.iframeCrossFrameAccess)
            || flags.contains(.truncatedStaticAnalysis)
        if requiresOriginCompatibility {
            return .highCompatibility
        }
        return .standard
    }
}
