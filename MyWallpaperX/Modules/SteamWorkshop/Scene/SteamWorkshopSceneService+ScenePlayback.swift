import Foundation

struct SteamWorkshopScenePlaybackRequest {
    let rootURL: URL
    let propertyOverrides: [String: SceneUserPropertyValue]
    let userPropertyTextures: [String: ScenePlaybackTextureReference]
    let recordID: String
    let resourceLifetime: PlaybackResourceLifetime?
}

extension SteamWorkshopService {
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord) {
        guard record.contentType == .scene else { return }

        // Every load, including texture-property reloads, owns the concrete files
        // until the daemon releases them. Callers cannot bypass lease admission.
        let resourceLifetime: PlaybackResourceLifetime?
        do {
            resourceLifetime = try libraryVersionLifetime(for: record)
        } catch {
            clearLaunchPending(matching: record.id)
            downloadError = error.localizedDescription
            return
        }

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
