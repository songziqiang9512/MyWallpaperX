import Foundation

extension SteamWorkshopService {
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord) {
        guard record.contentType == .scene else { return }

        // Diagnostics rebuilds cache-owned derived state without mutating the
        // Workshop sample directory.
        let report = SceneDiagnosticsBuilder().build(
            rootURL: record.folderURL,
            propertyOverrides: scenePropertyOverrides(for: record)
        )

        guard let cacheDirectory = report.packageReport?.outputURL else {
            downloadError = "Scene 资源尚未解包，无法设为壁纸。请确认入口对应的资源包存在且可读。"
            return
        }
        guard let interpretationFileURL = report.interpretationFileURL else {
            downloadError = "Scene 派生解释文件生成失败：\(report.interpretationFileError ?? "未知原因")"
            return
        }
        let previewLogURL = cacheDirectory.appendingPathComponent(
            ".mywallpaperx-scene-preview-log.txt"
        )

        NotificationCenter.default.post(
            name: .steamWorkshopSceneReadyToRender,
            object: nil,
            userInfo: [
                "rootURL": record.folderURL,
                "cacheDirectory": cacheDirectory,
                "interpretationFileURL": interpretationFileURL,
                "previewLogURL": previewLogURL,
                "recordID": record.id
            ]
        )
        statusMessage = "已将 \(record.title) 发送到 Scene 壁纸宿主"
    }
}
