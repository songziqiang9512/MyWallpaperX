import Foundation

extension SteamWorkshopService {
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord) {
        guard record.contentType == .scene else { return }

        // SceneDiagnosticsBuilder always overwrites the derived interpretation
        // file under rootURL, so deleting it on disk auto-rebuilds here.
        let report = SceneDiagnosticsBuilder().build(rootURL: record.folderURL)

        guard let cacheDirectory = report.packageReport?.outputURL else {
            downloadError = "Scene 资源尚未解包，无法设为壁纸。请确认入口对应的资源包存在且可读。"
            return
        }
        guard report.interpretationFileURL != nil else {
            downloadError = "Scene 派生解释文件生成失败：\(report.interpretationFileError ?? "未知原因")"
            return
        }

        NotificationCenter.default.post(
            name: .steamWorkshopSceneReadyToRender,
            object: nil,
            userInfo: [
                "rootURL": record.folderURL,
                "cacheDirectory": cacheDirectory
            ]
        )
        statusMessage = "已将 \(record.title) 发送到 Scene 壁纸宿主"
    }
}
