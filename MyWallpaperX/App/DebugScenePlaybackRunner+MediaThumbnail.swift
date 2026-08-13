#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static func publishRequestedMediaThumbnail(rootURL: URL) {
        publishRequestedMediaProperties()
        guard let relativePath = argumentValue(
            after: "--mwx-debug-scene-media-thumbnail"
        ) else { return }
        let secondaryColor: SIMD3<Double>?
        if let payload = argumentValue(
            after: "--mwx-debug-scene-media-secondary-color-json"
        ) {
            guard let parsed = normalizedColor(from: payload) else {
                NSLog(
                    "MWX DEBUG SCENE: phase=media-thumbnail-rejected reason=secondary-color"
                )
                return
            }
            secondaryColor = parsed
        } else {
            secondaryColor = nil
        }
        let playbackState: Int?
        if let rawState = argumentValue(
            after: "--mwx-debug-scene-media-playback-state"
        ) {
            guard let parsed = Int(rawState), (0...2).contains(parsed) else {
                NSLog(
                    "MWX DEBUG SCENE: phase=media-thumbnail-rejected reason=playback-state"
                )
                return
            }
            playbackState = parsed
        } else {
            playbackState = nil
        }
        guard publishMediaThumbnail(
            relativePath: relativePath,
            secondaryColor: secondaryColor,
            rootURL: rootURL
        ) else { return }
        if let playbackState {
            guard SceneMediaThumbnailInbox.shared.publishPlaybackState(
                playbackState
            ) else {
                NSLog(
                    "MWX DEBUG SCENE: phase=media-playback-rejected state=%d",
                    playbackState
                )
                return
            }
            NSLog(
                "MWX DEBUG SCENE: phase=media-playback-published state=%d",
                playbackState
            )
        }
    }

    private static func publishRequestedMediaProperties() {
        let title = argumentValue(after: "--mwx-debug-scene-media-title")
        let artist = argumentValue(after: "--mwx-debug-scene-media-artist")
        guard title != nil || artist != nil else { return }
        guard let title, let artist else {
            NSLog(
                "MWX DEBUG SCENE: phase=media-properties-rejected reason=incomplete"
            )
            return
        }
        guard SceneMediaThumbnailInbox.shared.publishMediaProperties(
            title: title,
            artist: artist
        ) else {
            NSLog(
                "MWX DEBUG SCENE: phase=media-properties-rejected reason=invalid"
            )
            return
        }
        NSLog(
            "MWX DEBUG SCENE: phase=media-properties-published generation=%llu titleUTF8Bytes=%d artistUTF8Bytes=%d",
            SceneMediaThumbnailInbox.shared.latest().propertiesGeneration,
            title.utf8.count,
            artist.utf8.count
        )
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

    @discardableResult
    private static func publishMediaThumbnail(
        relativePath: String,
        secondaryColor: SIMD3<Double>? = nil,
        rootURL: URL
    ) -> Bool {
        let resolvedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let url = URL(fileURLWithPath: relativePath, relativeTo: resolvedRootURL)
            .resolvingSymlinksInPath().standardizedFileURL
        guard !(relativePath as NSString).isAbsolutePath,
              url.path.hasPrefix(resolvedRootURL.path + "/"),
              ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              SceneMediaThumbnailInbox.shared.publish(
                  data,
                  secondaryColor: secondaryColor
              ) else {
            NSLog(
                "MWX DEBUG SCENE: phase=media-thumbnail-rejected file=%@",
                url.lastPathComponent
            )
            return false
        }
        NSLog(
            "MWX DEBUG SCENE: phase=media-thumbnail-published file=%@ bytes=%d hasSecondaryColor=%@",
            url.lastPathComponent,
            data.count,
            secondaryColor == nil ? "false" : "true"
        )
        return true
    }

    private static func normalizedColor(
        from payload: String
    ) -> SIMD3<Double>? {
        guard let data = payload.data(using: .utf8),
              let components = try? JSONDecoder().decode([Double].self, from: data),
              components.count == 3,
              components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return nil
        }
        return SIMD3(components[0], components[1], components[2])
    }
}
#endif
