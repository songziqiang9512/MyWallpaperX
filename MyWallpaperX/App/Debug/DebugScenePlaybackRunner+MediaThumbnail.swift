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
        ) else { return }
        guard raw.utf8.count <= 2 * 1_024 * 1_024,
           let data = raw.data(using: .utf8),
           let entries = try? JSONDecoder().decode([MediaSequenceEntry].self, from: data),
           (1...8).contains(entries.count) else {
            NSLog("MWX DEBUG SCENE: phase=media-sequence-rejected reason=invalid")
            return
        }
        let start = DispatchTime.now()
        let groups = Dictionary(grouping: Array(entries.enumerated()), by: { $0.element.delay })
        for delay in groups.keys.sorted() {
            guard let group = groups[delay] else { continue }
            // One callback preserves array order for equal timestamps. These
            // remain independent inbox channels, not an atomic media session.
            DispatchQueue.main.asyncAfter(deadline: start + delay) {
                for (index, entry) in group {
                    publishMediaSequenceEntry(entry, index: index, rootURL: rootURL)
                }
            }
        }
    }

    private static func publishMediaSequenceEntry(
        _ entry: MediaSequenceEntry,
        index: Int,
        rootURL: URL
    ) {
        let inbox = SceneMediaThumbnailInbox.shared
        let accepted: Bool
        let action: String
        switch entry.action {
        case .path(let path):
            action = "path"
            accepted = publishMediaThumbnail(relativePath: path, rootURL: rootURL)
        case .clear:
            action = "clear"
            inbox.clear()
            accepted = inbox.latest().current == nil
            if accepted {
                NSLog("MWX DEBUG SCENE: phase=media-thumbnail-cleared")
            }
        case .properties(let properties):
            action = "properties"
            accepted = inbox.publishMediaProperties(
                title: properties.title, artist: properties.artist,
                subTitle: properties.subTitle, albumTitle: properties.albumTitle,
                albumArtist: properties.albumArtist, genres: properties.genres,
                contentType: properties.contentType
            )
        case .playbackState(let state):
            action = "playbackState"
            accepted = inbox.publishPlaybackState(state)
        case .timeline(let timeline):
            action = "timeline"
            accepted = inbox.publishMediaTimeline(
                position: timeline.position, duration: timeline.duration
            )
        }
        let snapshot = inbox.latest()
        NSLog(
            "MWX DEBUG SCENE: phase=media-sequence-step index=%d action=%@ accepted=%@ artGeneration=%llu playbackGeneration=%llu propertiesGeneration=%llu timelineGeneration=%llu",
            index, action, accepted ? "true" : "false", snapshot.generation,
            snapshot.playbackGeneration, snapshot.propertiesGeneration,
            snapshot.timelineGeneration
        )
    }

    private struct MediaSequenceEntry: Decodable {
        enum Action {
            case path(String)
            case clear
            case properties(MediaSequenceProperties)
            case playbackState(Int)
            case timeline(MediaSequenceTimeline)
        }

        let action: Action
        let delay: TimeInterval

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case path, clear, delay, properties, playbackState, timeline
        }

        init(from decoder: Decoder) throws {
            try validateMediaSequenceKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let path = try values.decodeIfPresent(String.self, forKey: .path)
            let clear = try values.decodeIfPresent(Bool.self, forKey: .clear) ?? false
            let properties = try values.contains(.properties)
                ? values.decode(MediaSequenceProperties.self, forKey: .properties) : nil
            let state = try values.contains(.playbackState)
                ? values.decode(Int.self, forKey: .playbackState) : nil
            let timeline = try values.contains(.timeline)
                ? values.decode(MediaSequenceTimeline.self, forKey: .timeline) : nil
            let delay = try values.decode(TimeInterval.self, forKey: .delay)
            guard [path != nil, clear, properties != nil, state != nil, timeline != nil]
                .filter({ $0 }).count == 1,
                delay.isFinite, (0.1...60).contains(delay),
                path.map({ !$0.isEmpty && isValidMediaSequenceString($0) }) != false,
                state.map({ (0...2).contains($0) }) != false else {
                throw DecodingError.dataCorruptedError(
                    forKey: .delay,
                    in: values,
                    debugDescription: "one bounded media sequence action is required"
                )
            }
            if let path { action = .path(path) }
            else if let properties { action = .properties(properties) }
            else if let state { action = .playbackState(state) }
            else if let timeline { action = .timeline(timeline) }
            else { action = .clear }
            self.delay = delay
        }
    }

    private struct MediaSequenceProperties: Decodable {
        let title: String
        let artist: String
        let subTitle: String
        let albumTitle: String
        let albumArtist: String
        let genres: String
        let contentType: String

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case title, artist, subTitle, albumTitle, albumArtist, genres, contentType
        }

        init(from decoder: Decoder) throws {
            try validateMediaSequenceKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let values = try decoder.container(keyedBy: CodingKeys.self)
            title = try values.decode(String.self, forKey: .title)
            artist = try values.decode(String.self, forKey: .artist)
            func optional(_ key: CodingKeys) throws -> String {
                try values.contains(key) ? values.decode(String.self, forKey: key) : ""
            }
            subTitle = try optional(.subTitle)
            albumTitle = try optional(.albumTitle)
            albumArtist = try optional(.albumArtist)
            genres = try optional(.genres)
            contentType = try optional(.contentType)
            guard [title, artist, subTitle, albumTitle, albumArtist, genres, contentType]
                .allSatisfy(isValidMediaSequenceString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .title, in: values, debugDescription: "invalid media property"
                )
            }
        }
    }

    private struct MediaSequenceTimeline: Decodable {
        let position: Double
        let duration: Double

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case position, duration
        }

        init(from decoder: Decoder) throws {
            try validateMediaSequenceKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let values = try decoder.container(keyedBy: CodingKeys.self)
            position = try values.decode(Double.self, forKey: .position)
            duration = try values.decode(Double.self, forKey: .duration)
            guard position.isFinite, position >= 0, duration.isFinite, duration >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .position, in: values, debugDescription: "invalid media timeline"
                )
            }
        }
    }

    private struct MediaSequenceKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    nonisolated private static func validateMediaSequenceKeys(
        _ decoder: Decoder,
        allowed: [String]
    ) throws {
        let values = try decoder.container(keyedBy: MediaSequenceKey.self)
        guard values.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "unknown media sequence field"
            ))
        }
    }

    nonisolated private static func isValidMediaSequenceString(_ value: String) -> Bool {
        value.utf8.count <= SceneMediaThumbnailInbox.maximumMediaPropertyUTF8ByteCount
            && !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
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
