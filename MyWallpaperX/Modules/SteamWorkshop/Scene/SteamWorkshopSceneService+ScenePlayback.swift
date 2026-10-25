import Foundation

struct SteamWorkshopScenePlaybackRequest {
    let rootURL: URL
    let propertyOverrides: [String: SceneUserPropertyValue]
    let userPropertyTextures: [String: ScenePlaybackTextureReference]
    let recordID: String
    let resourceLifetime: PlaybackResourceLifetime?
    var source: ScenePlaybackSource? = nil
    var intentEpoch: UInt64? = nil
    var libraryPending: WallpaperPlaybackSequence.Pending? = nil
    var userShortcuts: ScenePlaybackShortcutConfiguration = .empty
}

extension SteamWorkshopService {
    @discardableResult
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord, newSelection: Bool = true,
                            libraryPending: WallpaperPlaybackSequence.Pending? = nil) -> Bool {
        guard record.contentType == .scene else { return false }
        if newSelection && libraryPending == nil {
            requestLibraryPlayback?(WallpaperReference(provider: .steamWorkshop, sourceID: record.id))
            return false
        }
        let intent = prepareScenePlaybackIntent?(record.id, newSelection, libraryPending)
        guard let intent else { return false }

        let generation = webLaunchIntentGeneration
        let admission: SceneSourceAdmission
        do {
            admission = try sceneSourceAdmission(for: record)
        } catch {
            intent.cancel()
            clearLaunchPending(matching: record.id)
            downloadError = error.localizedDescription
            return false
        }
        let propertyOverrides = scenePropertyOverrides(for: record)
        withResolvedSceneTexturePropertyReferences(for: record) { [weak self] references in
            guard let self, self.webLaunchIntentGeneration == generation, intent.isCurrent() else { return }
            var request = SteamWorkshopScenePlaybackRequest(
                rootURL: admission.source.rootURL, propertyOverrides: propertyOverrides,
                userPropertyTextures: references, recordID: record.id,
                resourceLifetime: admission.resourceLifetime, source: admission.source,
                intentEpoch: intent.intentEpoch, libraryPending: libraryPending
            )
            request.userShortcuts = self.sceneShortcutConfiguration(for: record)
            NotificationCenter.default.post(name: .steamWorkshopSceneReadyToRender,
                object: nil, userInfo: ["request": request])
        }
        statusMessage = "正在后台准备 \(record.title)，当前壁纸会继续播放"
        return true
    }
}
