import Foundation

struct SteamWorkshopScenePlaybackRequest {
    let rootURL: URL
    let propertyOverrides: [String: SceneUserPropertyValue]
    let userPropertyTextures: [String: ScenePlaybackTextureReference]
    let recordID: String
    let resourceLifetime: PlaybackResourceLifetime?
    var source: ScenePlaybackSource? = nil
    var intentEpoch: UInt64? = nil
    var userShortcuts: ScenePlaybackShortcutConfiguration = .empty
}

extension SteamWorkshopService {
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord, newSelection: Bool = true) {
        guard record.contentType == .scene else { return }
        let intent = prepareScenePlaybackIntent?(record.id, newSelection)
        if prepareScenePlaybackIntent != nil && intent == nil { return }

        let generation = webLaunchIntentGeneration
        let admission: SceneSourceAdmission
        do {
            admission = try sceneSourceAdmission(for: record)
        } catch {
            intent?.cancel()
            clearLaunchPending(matching: record.id)
            downloadError = error.localizedDescription
            return
        }
        let propertyOverrides = scenePropertyOverrides(for: record)
        withResolvedSceneTexturePropertyReferences(for: record) { [weak self] references in
            guard let self, self.webLaunchIntentGeneration == generation,
                  intent?.isCurrent() != false else { return }
            var request = SteamWorkshopScenePlaybackRequest(
                rootURL: admission.source.rootURL, propertyOverrides: propertyOverrides,
                userPropertyTextures: references, recordID: record.id,
                resourceLifetime: admission.resourceLifetime, source: admission.source, intentEpoch: intent?.intentEpoch)
            request.userShortcuts = self.sceneShortcutConfiguration(for: record)
            NotificationCenter.default.post(name: .steamWorkshopSceneReadyToRender,
                object: nil, userInfo: ["request": request])
        }
        statusMessage = "正在后台准备 \(record.title)，当前壁纸会继续播放"
    }
}
