#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static func publishRequestedMediaThumbnail(rootURL: URL) {
        guard let relativePath = argumentValue(
            after: "--mwx-debug-scene-media-thumbnail"
        ) else { return }
        publishMediaThumbnail(relativePath: relativePath, rootURL: rootURL)
    }

    static func scheduleRequestedMediaThumbnailSequence(rootURL: URL) {
        guard let raw = argumentValue(
            after: "--mwx-debug-scene-media-thumbnail-sequence-json"
        ), let data = raw.data(using: .utf8),
           let entries = try? JSONDecoder().decode([MediaSequenceEntry].self, from: data),
           (1...8).contains(entries.count),
           entries.allSatisfy({
               $0.delay.isFinite && (0.1...60).contains($0.delay)
           }) else {
            return
        }
        for entry in entries {
            DispatchQueue.main.asyncAfter(deadline: .now() + entry.delay) {
                publishMediaThumbnail(relativePath: entry.path, rootURL: rootURL)
            }
        }
    }

    private struct MediaSequenceEntry: Decodable {
        let path: String
        let delay: TimeInterval
    }

    private static func publishMediaThumbnail(
        relativePath: String,
        rootURL: URL
    ) {
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
