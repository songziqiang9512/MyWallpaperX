import Foundation

struct SteamWorkshopScenePlaybackRequest {
    let rootURL: URL
    let propertyOverrides: [String: SceneUserPropertyValue]
    let userPropertyTextures: [String: ScenePlaybackTextureReference]
    let recordID: String
    let resourceLifetime: PlaybackResourceLifetime?
}

extension SteamWorkshopService {
    func requestSceneRender(
        _ record: SteamWorkshopDownloadRecord,
        resourceLifetime: PlaybackResourceLifetime? = nil
    ) {
        guard record.contentType == .scene else { return }

        let propertyOverrides = scenePropertyOverrides(for: record)
        withResolvedSceneTexturePropertyReferences(for: record) { references in
            NotificationCenter.default.post(
                name: .steamWorkshopSceneReadyToRender,
                object: nil,
                userInfo: [
                    "request": SteamWorkshopScenePlaybackRequest(
                        rootURL: record.folderURL,
                        propertyOverrides: propertyOverrides,
                        userPropertyTextures: references,
                        recordID: record.id,
                        resourceLifetime: resourceLifetime
                    )
                ]
            )
        }
        statusMessage = "正在后台准备 \(record.title)，当前壁纸会继续播放"
    }
}
