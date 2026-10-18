//
//  MainWindowCoordinator+PlaybackRouting.swift
//  MyWallpaperX
//

import AppKit

// MainWindowCoordinator 的播放路由观察者：各 runtime 的就绪 / 启动状态 /
// 模式切换事件到 WallpaperManager、SceneDaemonClient、WallpaperEngine 的定向分发。
// 观察者令牌与状态存储仍在 MainWindowCoordinator 主体（internal，供本 extension 读写）。
extension MainWindowCoordinator {
    static func configure(with wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        guard observerTokens.isEmpty else { return }
        observerTokens.append(ImportedVideoPlaybackObserver.make(
            name: .onlineVideoReadyToPlay, context: .onlinePlayback, wallpaperManager: wallpaperManager
        ))
        observerTokens.append(ImportedVideoPlaybackObserver.make(
            name: .steamWorkshopVideoReadyToPlay, context: .steamPlayback, wallpaperManager: wallpaperManager
        ))
        observeSteamWorkshopWebWallpaperReadyToPlay()
        observeWebPlaybackCommit()
        observeSceneFirstFrameCommit()
        observeSteamWorkshopSceneReadyToRender()
        observeSceneWallpaperLaunchState()
        observeStaticImageWallpaperReadyToApply()
        observeSteamWorkshopModeChanges()
    }

    /// 监听 Steam 下载页发出的 HTML 网页壁纸播放请求，中转到实验性的 Web 壁纸宿主。
    private static func observeSteamWorkshopWebWallpaperReadyToPlay() {
        let observer = NotificationCenter.default.addObserver(
            forName: .steamWorkshopWebWallpaperReadyToPlay,
            object: nil,
            queue: .main
        ) { notification in
            guard let entryURL = notification.userInfo?["entryURL"] as? URL,
                  let rootURL = notification.userInfo?["rootURL"] as? URL else { return }

            let propertiesJSON = notification.userInfo?["propertiesJSON"] as? String
            let recordID = notification.userInfo?["recordID"] as? String
            let language = notification.userInfo?["language"] as? String ?? "en-us"
            let runtimeProfile = notification.userInfo?["runtimeProfile"] as? WallpaperEngine.WebRuntimeProfile ?? .standard
            let resourceLifetime = notification.userInfo?["resourceLifetime"] as? PlaybackResourceLifetime
            wallpaperManager.stopAutoSwitchTimer()
            // E2a-1: web 切换入口注入产品意图纪元（只读，提交点不变）。
            let epoch: UInt64
            if let preparedEpoch = notification.userInfo?["intentEpoch"] as? UInt64 {
                guard wallpaperManager.playbackIntentEpoch == preparedEpoch,
                      wallpaperManager.requestedRuntime == .web else { return }
                epoch = preparedEpoch
            } else {
                epoch = wallpaperManager.beginPlaybackIntent(runtime: .web)
            }
            WallpaperEngine.shared.adoptIntentEpoch(epoch)
            WallpaperEngine.shared.setWebWallpaper(
                requestID: notification.userInfo?["requestID"] as? UUID ?? UUID(),
                entryURL: entryURL,
                rootURL: rootURL,
                propertiesJSON: propertiesJSON,
                recordID: recordID,
                language: language,
                runtimeProfile: runtimeProfile,
                multiDisplayEnabled: wallpaperManager.settings.multiDisplayEnabled,
                resourceLifetime: resourceLifetime
            )

        }
        observerTokens.append(observer)
    }

    private static func observeWebPlaybackCommit() {
        let observer = NotificationCenter.default.addObserver(
            forName: WallpaperEngine.webPlaybackReadyNotification, object: nil, queue: .main
        ) { notification in
            let engine = WallpaperEngine.shared
            guard let requestID = notification.userInfo?["requestID"] as? UUID,
                  requestID == engine.currentWebRequestID,
                  wallpaperManager.requestedRuntime == .web else { return }
            wallpaperManager.clearCurrentWallpaperReference()
            wallpaperManager.activeWallpaperRuntime = .web
            wallpaperManager.lastWorkshopPlaybackRecordID = engine.currentWebRecordID
            wallpaperManager.stopAutoSwitchTimer()
            wallpaperManager.isPlaying = engine.isPlaying()
            if let recordID = engine.currentWebRecordID {
                wallpaperManager.scheduleRuntimeFrameSystemWallpaperSync(kind: .web, recordID: recordID)
            }
        }
        observerTokens.append(observer)
    }

    private static func observeSceneFirstFrameCommit() {
        let observer = NotificationCenter.default.addObserver(
            forName: .sceneWallpaperFirstFrameDidPresent, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let frame = notification.object as? SceneFramePresentation,
                      frame.requestID == SceneDaemonClient.shared.activeRequestID,
                      frame.requestID == sceneHandoffRequestID,
                      wallpaperManager.requestedRuntime == .scene,
                      sceneHandoffIntentEpoch == wallpaperManager.playbackIntentEpoch else { return }
                postWallpaperRuntimeWillSwitch(to: .scene, recordID: frame.recordID)
                wallpaperManager.clearCurrentWallpaperReference()
                wallpaperManager.activeWallpaperRuntime = .scene
                wallpaperManager.lastWorkshopPlaybackRecordID = frame.recordID
                wallpaperManager.stopAutoSwitchTimer()
                WallpaperEngine.shared.stopPlayback()
                wallpaperManager.isPlaying = SceneDaemonClient.shared.isPlaying
                if let recordID = frame.recordID {
                    wallpaperManager.scheduleRuntimeFrameSystemWallpaperSync(kind: .scene, recordID: recordID)
                }
            }
        }
        observerTokens.append(observer)
    }

    /// 监听 Steam Scene 请求并定向交给独立进程控制端。
    private static func observeSteamWorkshopSceneReadyToRender() {
        let observer = NotificationCenter.default.addObserver(
            forName: .steamWorkshopSceneReadyToRender,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let request = notification.userInfo?["request"]
                        as? SteamWorkshopScenePlaybackRequest else { return }
                // Settle the previous request while its product identity is
                // still installed, before assigning the new Scene handoff.
                SceneDaemonClient.shared.cancelPreparationForRuntimeSwitch()
                SteamWorkshopService.shared.markLaunchPending(recordID: request.recordID)
                SceneDaemonClient.shared.retainResourceLifetime(
                    request.resourceLifetime,
                    rootURL: request.rootURL,
                    recordID: request.recordID
                )
                // E2a-1: scene 切换入口注入产品意图纪元（只读，提交点
                // 不变；adapter 内部 sessionGeneration 自成体系）。
                wallpaperManager.stopAutoSwitchTimer()
                let epoch = wallpaperManager.beginPlaybackIntent(runtime: .scene)
                sceneHandoffIntentEpoch = epoch
                sceneHandoffRecordID = request.recordID
                sceneHandoffRequestID = nil
                WallpaperEngine.shared.adoptIntentEpoch(epoch)
                WallpaperEngine.shared.cancelPreparationRetainingActivePlayback()
                let accepted = PlaybackCommandMultiplexer.shared.dispatch(
                    .loadScene(.init(
                        rootURL: request.rootURL,
                        propertyOverrides: request.propertyOverrides,
                        userPropertyTextures: request.userPropertyTextures,
                        recordID: request.recordID
                    )),
                    to: .scene
                )
                if !accepted {
                    SceneDaemonClient.shared.discardPendingResourceLifetime(
                        rootURL: request.rootURL,
                        recordID: request.recordID
                    )
                    SteamWorkshopService.shared.downloadError =
                        "Scene daemon 控制端尚未就绪"
                    SteamWorkshopService.shared.clearLaunchPending(
                        matching: request.recordID
                    )
                }
            }
        }
        observerTokens.append(observer)
    }

    /// 将 Scene daemon 的中心启动状态投影到 Steam 模块。
    private static func observeSceneWallpaperLaunchState() {
        let observer = NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let state = notification.object as? SceneWallpaperLaunchState else {
                    return
                }
                if state.phase == .accepted,
                   wallpaperManager.requestedRuntime == .scene,
                   sceneHandoffIntentEpoch == wallpaperManager.playbackIntentEpoch,
                   sceneHandoffRecordID == state.recordID {
                    sceneHandoffRequestID = state.requestID
                }
                let message: String
                switch state.phase {
                case .accepted, .preparingModel, .preparingPrograms,
                     .preparingResources, .preparingSurfaces:
                    message = "\(state.message)，当前壁纸会继续播放"
                case .launched:
                    message = "Scene 表面已启动，正在等待首帧显示"
                case .cancelled, .failed:
                    message = state.phase == .cancelled
                        ? "已取消 Scene 壁纸准备，当前壁纸保持不变"
                        : "Scene 壁纸准备失败，当前壁纸保持不变"
                    if wallpaperManager.requestedRuntime == .scene,
                       sceneHandoffIntentEpoch == wallpaperManager.playbackIntentEpoch,
                       sceneHandoffRecordID == state.recordID,
                       sceneHandoffRequestID == nil || sceneHandoffRequestID == state.requestID {
                        wallpaperManager.restoreCommittedPlaybackIntent()
                    }
                case .stopped:
                    // E2a-2: 用户请求的停止——选择权威回收真值。防御性
                    // 守卫：若切换已把 runtime 指向别处，本回收迟到则跳过。
                    // epoch stamp 由 stopCurrentPlayback 单点负责。
                    message = "Scene 壁纸已停止"
                    if wallpaperManager.activeWallpaperRuntime == .scene {
                        wallpaperManager.stopCurrentPlayback()
                    }
                }
                SteamWorkshopService.shared.statusMessage = message
            }
        }
        observerTokens.append(observer)
    }

    /// 监听图片库发出的「设为壁纸」请求，统一执行系统壁纸应用和动态 runtime 收尾。
    private static func observeStaticImageWallpaperReadyToApply() {
        let observer = NotificationCenter.default.addObserver(
            forName: .staticImageWallpaperReadyToApply,
            object: nil,
            queue: .main
        ) { notification in
            guard let imageURL = notification.userInfo?["imageURL"] as? URL else { return }
            guard FileManager.default.fileExists(atPath: imageURL.path) else { return }

            let workspace = NSWorkspace.shared
            for screen in NSScreen.screens {
                try? workspace.setDesktopImageURL(imageURL, for: screen, options: [:])
            }

            postWallpaperRuntimeWillSwitch(to: .systemStill)
            wallpaperManager.clearCurrentWallpaperReference()
            wallpaperManager.activeWallpaperRuntime = .systemStill
            wallpaperManager.lastWorkshopPlaybackRecordID = nil
            wallpaperManager.isPlaying = false
            wallpaperManager.stopAutoSwitchTimer()
            // E2a-1: 静态图切换入口注入产品意图纪元（只读，提交点不变）。
            WallpaperEngine.shared.adoptIntentEpoch(
                wallpaperManager.beginPlaybackIntent(runtime: .systemStill)
            )
            WallpaperEngine.shared.stopPlayback()
        }
        observerTokens.append(observer)
    }

    /// 监听 Steam 浏览/下载子页面切换，保证主菜单分发与当前工具栏语义一致。
    private static func observeSteamWorkshopModeChanges() {
        let observer = NotificationCenter.default.addObserver(
            forName: .steamWorkshopModeDidChange,
            object: nil,
            queue: .main
        ) { notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            let isDownloads = notification.userInfo?["isDownloads"] as? Bool ?? false
            isSteamDownloadsMode = enabled && isDownloads
        }
        observerTokens.append(observer)
    }
}
