#if DEBUG
import AppKit
import Foundation

// Launch-argument parsing surface shared by the DEBUG Scene runners. The
// daemon-client runner reuses `argumentValue(after:)` and the strict property
// parsers instead of keeping a private copy.
extension DebugScenePlaybackRunner {
    static var requestedDuration: TimeInterval {
        guard let raw = argumentValue(after: "--mwx-debug-scene-duration"),
              let duration = TimeInterval(raw), duration.isFinite else {
            return 10
        }
        return min(max(duration, 7), 3_600)
    }

    static var requestedDropDynamicValuesFrameIndex: UInt64? {
        guard let raw = argumentValue(
            after: "--mwx-debug-scene-drop-dynamic-values-frame"
        ),
              let frameIndex = UInt64(raw),
              frameIndex > 0 else {
            return nil
        }
        return frameIndex
    }

    static var requestedAfterSnapshotDelay: TimeInterval {
        guard let raw = argumentValue(after: "--mwx-debug-scene-after-snapshot-delay"),
              let delay = TimeInterval(raw), delay.isFinite else {
            return 3
        }
        return min(max(delay, 1.1), requestedDuration - 0.5)
    }

    static var requestedPeriodicSnapshotInterval: TimeInterval? {
        if let raw = argumentValue(
            after: "--mwx-debug-scene-periodic-snapshot-interval"
        ),
           let interval = TimeInterval(raw),
           interval.isFinite,
           interval >= 0.08 {
            return min(interval, 10)
        }
        return ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-periodic-snapshots"
        ) ? 5 : nil
    }

    static var requestedResizeSequence: [(delay: TimeInterval, scale: CGFloat)] {
        guard let raw = argumentValue(after: "--mwx-debug-scene-resize-sequence") else {
            return []
        }
        return raw.split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let delay = TimeInterval(String(parts[0])),
                  let scale = Double(String(parts[1])),
                  delay > 0,
                  delay < requestedDuration - 0.75,
                  scale.isFinite,
                  scale > 0,
                  scale <= 1 else { return nil }
            return (delay, CGFloat(scale))
        }.sorted { $0.delay < $1.delay }
    }

    static var requestedHoverPointer: SIMD2<Float>? {
        guard let payload = argumentValue(
            after: "--mwx-debug-scene-hover-pointer-json"
        ),
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let x = (object["x"] as? NSNumber)?.doubleValue,
              let y = (object["y"] as? NSNumber)?.doubleValue,
              x.isFinite,
              y.isFinite,
              (-1...1).contains(x),
              (-1...1).contains(y) else {
            return nil
        }
        return SIMD2(Float(x), Float(y))
    }

    static var requestedHoverPointerStationaryEntry: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-hover-pointer-stationary-entry"
        )
    }

    static var requestedPrimaryClick: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-primary-click"
        )
    }

    static var requestedPrimaryClickSubframe: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-primary-click-subframe"
        )
    }

    static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static var requestedPropertyOverrides: [String: SceneUserPropertyValue] {
        requestedPropertyValues(after: "--mwx-debug-scene-properties-json")
    }

    static var requestedLivePropertySequence: [[String: SceneUserPropertyValue]]? {
        let flag = "--mwx-debug-scene-live-property-sequence-json"
        guard ProcessInfo.processInfo.arguments.contains(flag) else {
            let single = requestedPropertyValues(after: "--mwx-debug-scene-live-properties-json")
            return single.isEmpty ? [] : [single]
        }
        guard let payload = argumentValue(after: flag),
              let data = payload.data(using: .utf8), data.count <= 65_536,
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        var sequence: [[String: SceneUserPropertyValue]] = []
        for object in objects {
            guard let values = propertyValues(from: object) else { return nil }
            sequence.append(values)
        }
        return sequence
    }

    static func requestedPropertyValues(
        after flag: String
    ) -> [String: SceneUserPropertyValue] {
        strictRequestedPropertyValues(after: flag) ?? [:]
    }

    static func strictRequestedPropertyValues(
        after flag: String
    ) -> [String: SceneUserPropertyValue]? {
        guard let payload = argumentValue(after: flag) else { return [:] }
        guard let data = payload.data(using: .utf8), data.count <= 65_536,
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return nil
        }
        return propertyValues(from: object)
    }

    private static func propertyValues(
        from object: [String: Any]
    ) -> [String: SceneUserPropertyValue]? {
        guard object.count <= 64 else { return nil }
        var values: [String: SceneUserPropertyValue] = [:]
        for (key, rawValue) in object {
            guard !key.isEmpty,
                  key.utf8.count <= 512,
                  key.unicodeScalars.allSatisfy({
                      $0.value >= 32 && $0.value != 127
                  }),
                  let value = SceneUserPropertyValue.parse(rawValue) else {
                return nil
            }
            values[key] = value
        }
        return values
    }

    static func requestedUserPropertyTextureURLs(rootURL: URL) -> [String: URL] {
        guard let payload = argumentValue(after: "--mwx-debug-scene-textures-json"),
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        let resolvedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRootURL.path + "/"
        return object.reduce(into: [:]) { urls, entry in
            let url = URL(fileURLWithPath: entry.value, relativeTo: resolvedRootURL)
                .resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(rootPrefix),
                  SceneUserPropertyTextureLoader.supports(url: url),
                  FileManager.default.fileExists(atPath: url.path) else {
                NSLog(
                    "MWX DEBUG SCENE: phase=user-texture-rejected key=%@ file=%@",
                    entry.key,
                    url.lastPathComponent
                )
                return
            }
            urls[entry.key] = url
        }
    }
}
#endif
