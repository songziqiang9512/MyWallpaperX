import Foundation

struct SteamWorkshopScenePlaybackRequest {
    let rootURL: URL
    let propertyOverrides: [String: SceneUserPropertyValue]
    let userPropertyTextures: [String: ScenePlaybackTextureReference]
    let recordID: String
    let resourceLifetime: PlaybackResourceLifetime?
    var intentEpoch: UInt64? = nil
    var userShortcuts: ScenePlaybackShortcutConfiguration = .empty
}

extension SteamWorkshopService {
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord, newSelection: Bool = true) {
        guard record.contentType == .scene else { return }
        let intent = prepareScenePlaybackIntent?(record.id, newSelection)
        if prepareScenePlaybackIntent != nil && intent == nil { return }

        // Every load, including texture-property reloads, owns the concrete files
        // until the daemon releases them. Callers cannot bypass lease admission.
        let resourceLifetime: PlaybackResourceLifetime?
        do {
            resourceLifetime = try libraryVersionLifetime(for: record)
        } catch {
            intent?.cancel()
            clearLaunchPending(matching: record.id)
            downloadError = error.localizedDescription
            return
        }

        let propertyOverrides = scenePropertyOverrides(for: record)
        let generation = webLaunchIntentGeneration
        withResolvedSceneTexturePropertyReferences(for: record) { [weak self] references in
            guard let self, self.webLaunchIntentGeneration == generation, intent?.isCurrent() != false else { return }
            var request = SteamWorkshopScenePlaybackRequest(
                rootURL: record.folderURL, propertyOverrides: propertyOverrides,
                userPropertyTextures: references, recordID: record.id,
                resourceLifetime: resourceLifetime, intentEpoch: intent?.intentEpoch
            )
            request.userShortcuts = self.sceneShortcutConfiguration(for: record)
            NotificationCenter.default.post(
                name: .steamWorkshopSceneReadyToRender,
                object: nil,
                userInfo: [
                    "request": request
                ]
            )
        }
        statusMessage = "正在后台准备 \(record.title)，当前壁纸会继续播放"
    }
}
