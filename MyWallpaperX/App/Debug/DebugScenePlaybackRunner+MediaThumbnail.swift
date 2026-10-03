#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static func publishRequestedMediaThumbnail(rootURL: URL) {
        publishRequestedMediaProperties()
        publishRequestedMediaTimeline()
        guard let relativePath = argumentValue(
            after: "--mwx-debug-scene-media-thumbnail"
        ) else { return }
        let primary = requestedMediaColor(
            after: "--mwx-debug-scene-media-primary-color-json",
            label: "primary"
        )
        guard primary.isValid else { return }
        let secondary = requestedMediaColor(
            after: "--mwx-debug-scene-media-secondary-color-json",
            label: "secondary"
        )
        guard secondary.isValid else { return }
        let tertiary = requestedMediaColor(
            after: "--mwx-debug-scene-media-tertiary-color-json",
            label: "tertiary"
        )
        guard tertiary.isValid else { return }
        let text = requestedMediaColor(
            after: "--mwx-debug-scene-media-text-color-json",
            label: "text"
        )
        guard text.isValid else { return }
        let highContrast = requestedMediaColor(
            after: "--mwx-debug-scene-media-high-contrast-color-json",
            label: "high-contrast"
        )
        guard highContrast.isValid else { return }
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
            primaryColor: primary.value,
            secondaryColor: secondary.value,
            tertiaryColor: tertiary.value,
            textColor: text.value,
            highContrastColor: highContrast.value,
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
            artist: artist,
            subTitle: argumentValue(
                after: "--mwx-debug-scene-media-sub-title"
            ) ?? "",
            albumTitle: argumentValue(
                after: "--mwx-debug-scene-media-album-title"
            ) ?? "",
            albumArtist: argumentValue(
                after: "--mwx-debug-scene-media-album-artist"
            ) ?? "",
            genres: argumentValue(
                after: "--mwx-debug-scene-media-genres"
            ) ?? "",
            contentType: argumentValue(
                after: "--mwx-debug-scene-media-content-type"
            ) ?? ""
        ) else {
            NSLog(
                "MWX DEBUG SCENE: phase=media-properties-rejected reason=invalid"
            )
            return
        }
        let snapshot = SceneMediaThumbnailInbox.shared.latest()
        NSLog(
            "MWX DEBUG SCENE: phase=media-properties-published generation=%llu titleUTF8Bytes=%d artistUTF8Bytes=%d subTitleUTF8Bytes=%d albumTitleUTF8Bytes=%d albumArtistUTF8Bytes=%d genresUTF8Bytes=%d contentTypeUTF8Bytes=%d",
            snapshot.propertiesGeneration,
            snapshot.properties?.title.utf8.count ?? 0,
            snapshot.properties?.artist.utf8.count ?? 0,
            snapshot.properties?.subTitle.utf8.count ?? 0,
            snapshot.properties?.albumTitle.utf8.count ?? 0,
            snapshot.properties?.albumArtist.utf8.count ?? 0,
            snapshot.properties?.genres.utf8.count ?? 0,
            snapshot.properties?.contentType.utf8.count ?? 0
        )
    }

    private static func publishRequestedMediaTimeline() {
        let rawPosition = argumentValue(
            after: "--mwx-debug-scene-media-position"
        )
        let rawDuration = argumentValue(
            after: "--mwx-debug-scene-media-duration"
        )
        guard rawPosition != nil || rawDuration != nil else { return }
        guard let rawPosition, let rawDuration,
              let position = Double(rawPosition), position.isFinite, position >= 0,
              let duration = Double(rawDuration), duration.isFinite, duration >= 0,
              SceneMediaThumbnailInbox.shared.publishMediaTimeline(
                  position: position,
                  duration: duration
              ) else {
            NSLog(
                "MWX DEBUG SCENE: phase=media-timeline-rejected reason=invalid"
            )
            return
        }
        let snapshot = SceneMediaThumbnailInbox.shared.latest()
        NSLog(
            "MWX DEBUG SCENE: phase=media-timeline-published generation=%llu position=%.9g duration=%.9g",
            snapshot.timelineGeneration,
            snapshot.timeline?.position ?? 0,
            snapshot.timeline?.duration ?? 0
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
        primaryColor: SIMD3<Double>? = nil,
        secondaryColor: SIMD3<Double>? = nil,
        tertiaryColor: SIMD3<Double>? = nil,
        textColor: SIMD3<Double>? = nil,
        highContrastColor: SIMD3<Double>? = nil,
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
                  primaryColor: primaryColor,
                  secondaryColor: secondaryColor,
                  tertiaryColor: tertiaryColor,
                  textColor: textColor,
                  highContrastColor: highContrastColor
              ) else {
            NSLog(
                "MWX DEBUG SCENE: phase=media-thumbnail-rejected file=%@",
                url.lastPathComponent
            )
            return false
        }
        NSLog(
            "MWX DEBUG SCENE: phase=media-thumbnail-published file=%@ bytes=%d hasPrimaryColor=%@ hasSecondaryColor=%@ hasTertiaryColor=%@ hasTextColor=%@ hasHighContrastColor=%@",
            url.lastPathComponent,
            data.count,
            primaryColor == nil ? "false" : "true",
            secondaryColor == nil ? "false" : "true",
            tertiaryColor == nil ? "false" : "true",
            textColor == nil ? "false" : "true",
            highContrastColor == nil ? "false" : "true"
        )
        return true
    }

    private static func requestedMediaColor(
        after argument: String,
        label: String
    ) -> (value: SIMD3<Double>?, isValid: Bool) {
        guard let payload = argumentValue(after: argument) else {
            return (nil, true)
        }
        guard let color = normalizedColor(from: payload) else {
            NSLog(
                "MWX DEBUG SCENE: phase=media-thumbnail-rejected reason=%@-color",
                label
            )
            return (nil, false)
        }
        return (color, true)
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
