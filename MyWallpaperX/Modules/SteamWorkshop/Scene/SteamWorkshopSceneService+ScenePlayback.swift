import Foundation

struct SteamWorkshopScenePlaybackRequest {
    let rootURL: URL
    let propertyOverrides: [String: SceneUserPropertyValue]
    let userPropertyTextureURLs: [String: URL]
    let recordID: String
}

extension SteamWorkshopService {
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord) {
        guard record.contentType == .scene else { return }

        let propertyOverrides = scenePropertyOverrides(for: record)
        withResolvedSceneTexturePropertyURLs(for: record) { userPropertyTextureURLs in
            NotificationCenter.default.post(
                name: .steamWorkshopSceneReadyToRender,
                object: nil,
                userInfo: [
                    "request": SteamWorkshopScenePlaybackRequest(
                        rootURL: record.folderURL,
                        propertyOverrides: propertyOverrides,
                        userPropertyTextureURLs: userPropertyTextureURLs,
                        recordID: record.id
                    )
                ]
            )
        }
        statusMessage = "已将 \(record.title) 发送到 Scene 壁纸宿主"
    }
}
