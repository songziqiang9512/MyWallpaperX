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
                if let path = entry.path {
                    publishMediaThumbnail(relativePath: path, rootURL: rootURL)
                } else {
                    SceneMediaThumbnailInbox.shared.clear()
                    NSLog("MWX DEBUG SCENE: phase=media-thumbnail-cleared")
                }
            }
        }
    }

    private struct MediaSequenceEntry: Decodable {
        let path: String?
        let delay: TimeInterval

        private enum CodingKeys: String, CodingKey {
            case path
            case clear
            case delay
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let path = try values.decodeIfPresent(String.self, forKey: .path)
            let clear = try values.decodeIfPresent(Bool.self, forKey: .clear) ?? false
            guard (path != nil) != clear else {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: values,
                    debugDescription: "exactly one media sequence action is required"
                )
            }
            self.path = path
            self.delay = try values.decode(TimeInterval.self, forKey: .delay)
        }
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
