#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static func publishRequestedMediaThumbnail(rootURL: URL) {
        guard let relativePath = argumentValue(
            after: "--mwx-debug-scene-media-thumbnail"
        ) else { return }
        let resolvedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let url = URL(fileURLWithPath: relativePath, relativeTo: resolvedRootURL)
            .resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(resolvedRootURL.path + "/"),
              ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              SceneMediaThumbnailInbox.shared.publish(data) else {
            NSLog(
                "MWX DEBUG SCENE: phase=media-thumbnail-rejected file=%@",
                url.lastPathComponent
            )
            return
        }
        NSLog(
            "MWX DEBUG SCENE: phase=media-thumbnail-published file=%@ bytes=%d",
            url.lastPathComponent,
            data.count
        )
    }
}
#endif
