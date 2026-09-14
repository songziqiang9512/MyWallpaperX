import CoreFoundation
import CoreGraphics
import Foundation

nonisolated enum SceneDaemonCommand: Equatable, Sendable {
    case loadScene(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue],
        userPropertyTextures: [String: ScenePlaybackTextureReference],
        profile: PlaybackPerformanceProfile,
        recordID: String?
    )
    case setProperty(
        values: [String: SceneUserPropertyValue],
        revision: UInt64,
        recordID: String
    )
    case cancelLaunch(recordID: String)
    case setDisplayConfiguration([SceneScreenTopology])
    case setPerformanceProfile(PlaybackPerformanceProfile)
    case setMuted(Bool)
    case pause
    case resume
    case shutdown
}

nonisolated enum SceneDaemonProtocolFailure: Error, Equatable {
    case malformedEnvelope
    case unsupportedVersion(Int)
    case unsupportedCommand(String)
    case invalidPayload(String)

    var code: String {
        switch self {
        case .malformedEnvelope: "malformed-envelope"
        case .unsupportedVersion: "unsupported-protocol-version"
        case .unsupportedCommand: "unsupported-command"
        case .invalidPayload: "invalid-command-payload"
        }
    }
}

nonisolated enum SceneDaemonProtocol {
    static let version = 1
    static let commandFlag = "--mwx-scene-daemon"
    static let sceneRootFlag = "--mwx-scene-root"

    static func decodeCommand(
        _ data: Data
    ) -> Result<SceneDaemonCommand, SceneDaemonProtocolFailure> {
        guard let payload = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let version = integer(payload["v"]),
              let action = payload["cmd"] as? String else {
            return .failure(.malformedEnvelope)
        }
        guard version == self.version else {
            return .failure(.unsupportedVersion(version))
        }
        switch action {
        case "loadScene":
            guard let root = payload["rootURL"] as? String,
                  !root.isEmpty,
                  let profile = profile(payload["profile"] ?? payload["maxFPS"]),
                  let values = propertyValues(payload["propertyOverrides"]),
                  let textures = textureReferences(
                    payload["userPropertyTextures"]
                  ) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.loadScene(
                rootURL: URL(fileURLWithPath: root, isDirectory: true)
                    .resolvingSymlinksInPath().standardizedFileURL,
                propertyOverrides: values,
                userPropertyTextures: textures,
                profile: profile,
                recordID: payload["recordID"] as? String
            ))
        case "setProperty":
            guard let values = propertyValues(payload["values"]),
                  !values.isEmpty,
                  let revision = unsignedInteger(payload["revision"]),
                  revision > 0,
                  let recordID = payload["recordID"] as? String,
                  !recordID.isEmpty else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setProperty(
                values: values,
                revision: revision,
                recordID: recordID
            ))
        case "cancelLaunch":
            guard let recordID = payload["recordID"] as? String,
                  !recordID.isEmpty else {
                return .failure(.invalidPayload(action))
            }
            return .success(.cancelLaunch(recordID: recordID))
        case "setDisplayConfiguration":
            guard let topology = displayConfiguration(payload["screens"]) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setDisplayConfiguration(topology))
        case "setPerformanceProfile":
            guard let profile = profile(payload["maxFPS"]) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setPerformanceProfile(profile))
        case "setMuted":
            guard let muted = boolean(payload["muted"]) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setMuted(muted))
        case "pause": return .success(.pause)
        case "resume": return .success(.resume)
        case "shutdown": return .success(.shutdown)
        default: return .failure(.unsupportedCommand(action))
        }
    }

    private static func propertyValues(
        _ raw: Any?
    ) -> [String: SceneUserPropertyValue]? {
        guard raw == nil || raw is [String: Any] else { return nil }
        let dictionary = raw as? [String: Any] ?? [:]
        var result: [String: SceneUserPropertyValue] = [:]
        result.reserveCapacity(dictionary.count)
        for (key, value) in dictionary {
            guard !key.isEmpty, let parsed = SceneUserPropertyValue.parse(value) else {
                return nil
            }
            result[key] = parsed
        }
        return result
    }

    private static func textureReferences(
        _ raw: Any?
    ) -> [String: ScenePlaybackTextureReference]? {
        guard raw == nil || raw is [String: Any] else { return nil }
        let dictionary = raw as? [String: Any] ?? [:]
        var result: [String: ScenePlaybackTextureReference] = [:]
        result.reserveCapacity(dictionary.count)
        for (key, rawReference) in dictionary {
            guard !key.isEmpty,
                  let reference = rawReference as? [String: Any],
                  let path = reference["path"] as? String,
                  !path.isEmpty else { return nil }
            let bookmarkData: Data?
            if let bookmark = reference["bookmark"] as? String {
                guard let decoded = Data(base64Encoded: bookmark) else {
                    return nil
                }
                bookmarkData = decoded
            } else {
                bookmarkData = nil
            }
            result[key] = ScenePlaybackTextureReference(
                url: URL(fileURLWithPath: path)
                    .resolvingSymlinksInPath().standardizedFileURL,
                bookmarkData: bookmarkData
            )
        }
        return result
    }

    private static func profile(_ raw: Any?) -> PlaybackPerformanceProfile? {
        guard let value = integer(raw) else { return nil }
        return PlaybackPerformanceProfile(rawValue: value)
    }

    private static func displayConfiguration(
        _ raw: Any?
    ) -> [SceneScreenTopology]? {
        guard let screens = raw as? [[String: Any]], !screens.isEmpty else {
            return nil
        }
        var displayIDs: Set<CGDirectDisplayID> = []
        var result: [SceneScreenTopology] = []
        result.reserveCapacity(screens.count)
        for screen in screens {
            guard let rawID = unsignedInteger(screen["id"]),
                  rawID > 0, rawID <= UInt64(UInt32.max),
                  let frame = screen["frame"] as? [String: Any],
                  let x = finiteDouble(frame["x"]),
                  let y = finiteDouble(frame["y"]),
                  let width = finiteDouble(frame["width"]), width > 0,
                  let height = finiteDouble(frame["height"]), height > 0,
                  let scale = finiteDouble(screen["scale"]), scale > 0 else {
                return nil
            }
            let displayID = CGDirectDisplayID(rawID)
            guard displayIDs.insert(displayID).inserted else { return nil }
            result.append(SceneScreenTopology(
                displayID: displayID,
                frame: CGRect(x: x, y: y, width: width, height: height),
                backingScaleFactor: scale
            ))
        }
        return result.sorted { $0.displayID < $1.displayID }
    }

    private static func integer(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.intValue
        return NSNumber(value: value) == number ? value : nil
    }

    private static func unsignedInteger(_ raw: Any?) -> UInt64? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.uint64Value
        return NSNumber(value: value) == number ? value : nil
    }

    private static func boolean(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func finiteDouble(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }
}
