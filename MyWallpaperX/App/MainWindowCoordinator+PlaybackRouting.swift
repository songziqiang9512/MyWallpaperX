import AppKit

// Shell translates module events into product requests. Selection, activation,
// rollback and retirement belong to WallpaperManager's single transaction.
extension MainWindowCoordinator {
    static func configure(with manager: WallpaperManager) {
        wallpaperManager = manager
        guard observerTokens.isEmpty else { return }
        observerTokens.append(ImportedVideoPlaybackObserver.make(
            name: .onlineVideoReadyToPlay, context: .onlinePlayback, wallpaperManager: manager))
        observerTokens.append(ImportedVideoPlaybackObserver.make(
            name: .steamWorkshopVideoReadyToPlay, context: .steamPlayback, wallpaperManager: manager))
        observe(.steamWorkshopWebWallpaperReadyToPlay) { notification in
            guard let entryURL = notification.userInfo?["entryURL"] as? URL,
                  let rootURL = notification.userInfo?["rootURL"] as? URL else { return }
            manager.setWebWallpaper(requestID: notification.userInfo?["requestID"] as? UUID ?? UUID(),
                entryURL: entryURL, rootURL: rootURL,
                propertiesJSON: notification.userInfo?["propertiesJSON"] as? String,
                recordID: notification.userInfo?["recordID"] as? String,
                language: notification.userInfo?["language"] as? String ?? "en-us",
                runtimeProfile: notification.userInfo?["runtimeProfile"] as? WallpaperEngine.WebRuntimeProfile ?? .standard,
                resourceLifetime: notification.userInfo?["resourceLifetime"] as? PlaybackResourceLifetime,
                intentEpoch: notification.userInfo?["intentEpoch"] as? UInt64,
                resourceGrants: notification.userInfo?["resourceGrants"] as? [WebWallpaperResourceGrant] ?? [])
        }
        observe(.steamWorkshopSceneReadyToRender) { notification in
            guard let request = notification.userInfo?["request"] as? SteamWorkshopScenePlaybackRequest else { return }
            SteamWorkshopService.shared.markLaunchPending(recordID: request.recordID)
            var load = ScenePlaybackLoadRequest(rootURL: request.rootURL,
                propertyOverrides: request.propertyOverrides, userPropertyTextures: request.userPropertyTextures,
                recordID: request.recordID)
            load.userShortcuts = request.userShortcuts
            manager.setSceneWallpaper(load, resourceLifetime: request.resourceLifetime, intentEpoch: request.intentEpoch)
        }
        observe(.sceneWallpaperLaunchStateDidChange) { notification in
            guard let state = notification.object as? SceneWallpaperLaunchState else { return }
            // Progress only: a Scene launched event is not a product commit.
            switch state.phase {
            case .accepted, .preparingModel, .preparingPrograms, .preparingResources, .preparingSurfaces:
                SteamWorkshopService.shared.statusMessage = "\(state.message)，当前壁纸会继续播放"
            case .launched:
                SteamWorkshopService.shared.statusMessage = "Scene 表面已启动，正在等待首帧显示"
            case .failed, .cancelled, .stopped: break
            }
        }
        observe(.wallpaperSwitchDidFail) { notification in
            SteamWorkshopService.shared.statusMessage = notification.userInfo?["message"] as? String ?? "壁纸切换失败"
        }
        observe(.staticImageWallpaperReadyToApply) { notification in
            guard let url = notification.userInfo?["imageURL"] as? URL else { return }
            manager.setStaticWallpaper(url)
        }
        observe(.steamWorkshopModeDidChange) { notification in
            isSteamDownloadsMode = notification.userInfo?["enabled"] as? Bool == true
                && notification.userInfo?["isDownloads"] as? Bool == true
        }
    }

    private static func observe(_ name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        observerTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        })
    }
}
