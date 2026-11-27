import CoreFoundation
import CoreGraphics
import Foundation

nonisolated enum SceneDaemonCommand: Equatable, Sendable {
    case loadScene(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue],
        userPropertyTextures: [String: ScenePlaybackTextureReference],
        userShortcuts: ScenePlaybackShortcutConfiguration = .empty,
        animationFrameRate: AnimationFrameRate = .standard,
        recordID: String?,
        requiredUserTextureKeys: Set<String> = [],
        requestID: UUID? = nil,
        source: ScenePlaybackSource? = nil,
        sceneRenderQuality: SceneRenderQuality = .init(),
        presentation: ScenePlaybackPresentation = .init()
    )
    case setProperty(
        values: [String: SceneUserPropertyValue],
        revision: UInt64,
        recordID: String
    )
    case setUserTextures(ScenePlaybackTextureUpdate)
    case setUserShortcuts(ScenePlaybackShortcutUpdate, requestID: UUID)
    case cancelLaunch(recordID: String)
    case commitCandidate(requestID: UUID)
    case finalizeCandidate(requestID: UUID)
    case cancelCandidate(requestID: UUID, operationID: UUID? = nil)
    case setOutputActive(requestID: UUID, operationID: UUID, active: Bool)
    case retireOutput(requestID: UUID, operationID: UUID, requireRequestRetirement: Bool = false)
    case setDisplayConfiguration([SceneScreenTopology])
    case setAnimationFrameRate(AnimationFrameRate)
    case setSceneRenderQuality(SceneRenderQuality)
    case setCanvasFit(Bool)
    case setPresentation(ScenePlaybackPresentation, requestID: UUID)
    /// Normalized master volume (0...1) applied after authored/user volume.
    case setVolume(Float)
    case setMuted(Bool)
    /// 请求 daemon 自截壁纸表面一帧（JPEG 落盘后经 frameCaptured 事件
    /// 回传路径；主 App 侧无需屏幕录制权限）。
    case captureFrame(requestID: String)
    case publishAudioSpectrum(SceneDaemonAudioSpectrumFrame)
    case publishSystemMedia(SceneDaemonMediaSnapshotFrame)
    case publishSystemMediaArtwork(SceneDaemonMediaArtworkChunk)
    case controlSystemMedia(SceneDaemonMediaControl)
    case pause
    case resume
    case shutdown
}

/// Latest-only audio payload crossing from the main-App capture owner into the
/// Scene daemon. The token is expressed in the daemon's demand scope; the main
/// App's system tap has its own process-relative inclusion policy.
nonisolated struct SceneDaemonAudioSpectrumFrame: Equatable, Sendable {
    let left: [Float]
    let right: [Float]
    let left32: [Float]
    let right32: [Float]
    let left64: [Float]
    let right64: [Float]
    let captureToken: SceneAudioSpectrumCaptureToken
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

/// Pure admission rule for events arriving from an asynchronous child stdout.
/// A numeric generation alone is insufficient during graceful retirement,
/// because queued frames can arrive before that generation's termination event.
nonisolated struct SceneDaemonEventAdmission: Equatable, Sendable {
    let sessionGeneration: UInt64
    let hasActiveTransport: Bool
    let generationIsRetiring: Bool
    let terminationIsExpected: Bool

    func accepts(generation: UInt64) -> Bool {
        generation == sessionGeneration
            && hasActiveTransport
            && !generationIsRetiring
            && !terminationIsExpected
    }
}

nonisolated struct SceneRasterDisplayStatus: Equatable, Sendable {
    enum Fallback: String, Sendable {
        case deviceUnsupported
        case compatiblePathUnavailable
        case preparationFailed
    }

    let displayID: UInt32
    let samples: Int?
    var fallback: Fallback? = nil
    var shadow: SceneShadowUse? = nil
    var volume: SceneVolumeUse? = nil
    var textures: SceneTextureUse? = nil
    var postProcessing: ScenePostProcessingUse? = nil

    var wireObject: [String: Any] {
        var object: [String: Any] = ["displayID": displayID]
        object["samples"] = samples
        object["fallback"] = fallback?.rawValue
        switch shadow {
        case nil: break
        case .disabled: object["shadow"] = "disabled"
        case .noReceiver: object["shadow"] = "noReceiver"
        case .unavailable: object["shadow"] = "unavailable"
        case let .active(maps):
            object["shadow"] = maps.map { map -> [String: Any] in
                var row: [String: Any] = ["family": map.family.rawValue]
                row["face"] = map.face
                row["limit"] = map.limit?.rawValue
                return row
            }
        }
        switch volume {
        case nil: break
        case .disabled: object["volume"] = "disabled"
        case .rendered(let use):
            var row: [String: Any] = ["spot": use.spot]
            row["point"] = use.point?.rawValue
            object["volume"] = row
        }
        if let textures {
            var row: [String: [String: Any]] = [:]
            row["reduced"] = textures.reduced.map(Self.textureBinding)
            row["retained"] = textures.retained.map(Self.textureBinding)
            object["textures"] = row
        }
        if let postProcessing {
            object["postProcessing"] = ["hdrWorkingSpace": postProcessing.hdrWorkingSpace,
                "bloom": postProcessing.bloom.rawValue, "display": postProcessing.display.rawValue] as [String: Any]
        }
        return object
    }

    private static func textureBinding(_ value: SceneTextureUse.Binding) -> [String: Any] {
        ["width": value.width, "height": value.height, "baseMip": value.baseMip,
         "mipCount": value.mipCount, "reason": value.reason.rawValue]
    }
}

nonisolated enum SceneDaemonProtocol {
    static let version = 2
    static let commandFlag = "--mwx-scene-daemon"
    static let sceneRootFlag = "--mwx-scene-root"

    static func animationCadenceEvent(_ payload: [String: Any]) -> (
        requestID: UUID, requestedFPS: AnimationFrameRate, effectiveFPS: Double
    )? {
        guard let rawID = payload["requestID"] as? String,
              let requestID = UUID(uuidString: rawID),
              let requestedFPS = animationFrameRate(payload["requestedFPS"]),
              let effectiveFPS = finiteDouble(payload["effectiveFPS"]),
              effectiveFPS > 0, effectiveFPS <= Double(requestedFPS.rawValue) else { return nil }
        return (requestID, requestedFPS, effectiveFPS)
    }

    static func rasterDisplayStatuses(_ raw: Any?) -> [SceneRasterDisplayStatus]? {
        guard let objects = raw as? [[String: Any]] else { return nil }
        var statuses: [SceneRasterDisplayStatus] = []
        for object in objects {
            guard let rawID = unsignedInteger(object["displayID"]), let id = UInt32(exactly: rawID), id != 0,
                  statuses.last.map({ $0.displayID < id }) ?? true else { return nil }
            let samples = unsignedInteger(object["samples"])
            if object["samples"] != nil, samples != 1 && samples != 2 && samples != 4 { return nil }
            let fallback = (object["fallback"] as? String).flatMap(SceneRasterDisplayStatus.Fallback.init(rawValue:))
            if object["fallback"] != nil, (samples != 1 || fallback == nil) { return nil }
            statuses.append(.init(displayID: id, samples: samples.map(Int.init), fallback: fallback,
                shadow: shadowUse(object["shadow"]), volume: volumeUse(object["volume"]),
                textures: textureUse(object["textures"]), postProcessing: postProcessingUse(object["postProcessing"])))
        }
        return statuses
    }

    private static func postProcessingUse(_ raw: Any?) -> ScenePostProcessingUse? {
        guard let row = raw as? [String: Any], let hdr = boolean(row["hdrWorkingSpace"]),
              let bloom = (row["bloom"] as? String).flatMap(ScenePostProcessingUse.Bloom.init(rawValue:)),
              let display = (row["display"] as? String).flatMap(ScenePostProcessingUse.Display.init(rawValue:))
        else { return nil }
        return .init(hdrWorkingSpace: hdr, bloom: bloom, display: display)
    }

    private static func textureUse(_ raw: Any?) -> SceneTextureUse? {
        guard let row = raw as? [String: Any] else { return nil }
        let reduced = textureBinding(row["reduced"])
        let retained = textureBinding(row["retained"])
        guard row["reduced"] == nil || (reduced?.baseMip ?? 0) > 0,
              row["retained"] == nil || retained?.baseMip == 0 else { return nil }
        return .init(reduced: reduced, retained: retained)
    }

    private static func textureBinding(_ raw: Any?) -> SceneTextureUse.Binding? {
        guard let row = raw as? [String: Any],
              let width = unsignedInteger(row["width"]).flatMap(Int.init(exactly:)), width > 0,
              let height = unsignedInteger(row["height"]).flatMap(Int.init(exactly:)), height > 0,
              let baseMip = unsignedInteger(row["baseMip"]).flatMap(Int.init(exactly:)),
              let mipCount = unsignedInteger(row["mipCount"]).flatMap(Int.init(exactly:)), mipCount > 0,
              let reason = (row["reason"] as? String).flatMap(SceneTextureUse.Reason.init(rawValue:))
        else { return nil }
        return .init(width: width, height: height, baseMip: baseMip, mipCount: mipCount, reason: reason)
    }

    private static func volumeUse(_ raw: Any?) -> SceneVolumeUse? {
        if raw as? String == "disabled" { return .disabled }
        guard let row = raw as? [String: Any], let spot = boolean(row["spot"]) else { return nil }
        let point = (row["point"] as? String).flatMap(SceneVolumeUse.Point.init(rawValue:))
        if row["point"] != nil, point == nil { return nil }
        return .rendered(.init(point: point, spot: spot))
    }

    private static func shadowUse(_ raw: Any?) -> SceneShadowUse? {
        switch raw as? String {
        case "disabled": return .disabled
        case "noReceiver": return .noReceiver
        case "unavailable": return .unavailable
        default: break
        }
        guard let rows = raw as? [[String: Any]] else { return nil }
        var maps: [SceneShadowUse.Map] = []
        for row in rows {
            guard let family = (row["family"] as? String).flatMap(SceneShadowUse.Family.init(rawValue:)) else { return nil }
            let face = unsignedInteger(row["face"]).flatMap(Int.init(exactly:))
            let limit = (row["limit"] as? String).flatMap(SceneShadowUse.Limit.init(rawValue:))
            if row["face"] != nil, (face ?? 0) <= 0 { return nil }
            if row["limit"] != nil, limit == nil || face == nil { return nil }
            maps.append(.init(family: family, face: face, limit: limit))
        }
        return maps.contains { $0.face != nil } ? .active(maps) : nil
    }

    static func sourceObject(_ source: ScenePlaybackSource) throws -> [String: Any] {
        guard source.isValid,
              let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any] else {
            throw SceneDaemonProtocolFailure.invalidPayload("scene-source")
        }
        return object
    }

    private static func optionalTextureKeys(_ raw: Any?) -> Set<String>? {
        guard let raw else { return [] }
        guard let keys = raw as? [String], keys.allSatisfy({ !$0.isEmpty }),
              Set(keys).count == keys.count else { return nil }
        return Set(keys)
    }

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
            guard let renderQuality = renderQuality(payload, fallback: .init()) else {
                return .failure(.invalidPayload(action))
            }
            let requestID: UUID?
            if let raw = payload["requestID"] {
                guard let string = raw as? String, let parsed = UUID(uuidString: string) else {
                    return .failure(.invalidPayload(action))
                }
                requestID = parsed
            } else { requestID = nil }
            guard let root = payload["rootURL"] as? String,
                  !root.isEmpty,
                  let frameRate = animationFrameRate(
                    payload["profile"] ?? payload["maxFPS"] ?? AnimationFrameRate.standard.rawValue
                  ),
                  let values = propertyValues(payload["propertyOverrides"]),
                  let shortcuts = shortcutConfiguration(payload["userShortcuts"]),
                  let textures = textureReferences(
                    payload["userPropertyTextures"]
                  ), let requiredKeys = optionalTextureKeys(payload["requiredUserTextureKeys"]) else {
                return .failure(.invalidPayload(action))
            }
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL
            let source: ScenePlaybackSource?
            if let rawSource = payload["source"] {
                guard JSONSerialization.isValidJSONObject(rawSource),
                      let encoded = try? JSONSerialization.data(withJSONObject: rawSource),
                      let decoded = try? JSONDecoder().decode(ScenePlaybackSource.self, from: encoded),
                      decoded.isValid,
                      decoded.rootURL.resolvingSymlinksInPath().standardizedFileURL.path == rootURL.path else {
                    return .failure(.invalidPayload("scene-source"))
                }
                source = decoded
            } else { source = nil }
            let presentation: ScenePlaybackPresentation
            if let raw = payload["presentation"] {
                guard let decoded = decodePresentation(raw) else { return .failure(.invalidPayload("scene-presentation")) }
                presentation = decoded
            } else { presentation = .init() }
            return .success(.loadScene(
                rootURL: rootURL,
                propertyOverrides: values,
                userPropertyTextures: textures,
                userShortcuts: shortcuts,
                animationFrameRate: frameRate,
                recordID: payload["recordID"] as? String,
                requiredUserTextureKeys: requiredKeys,
                requestID: requestID,
                source: source,
                sceneRenderQuality: renderQuality,
                presentation: presentation
            ))
        case "setPresentation":
            guard let raw = payload["presentation"], let presentation = decodePresentation(raw),
                  let key = payload["requestID"] as? String, let requestID = UUID(uuidString: key) else {
                return .failure(.invalidPayload("scene-presentation"))
            }
            return .success(.setPresentation(presentation, requestID: requestID))
        case "setUserShortcuts":
            guard let configuration = shortcutConfiguration(payload["configuration"]),
                  configuration.revision > 0,
                  let recordID = payload["recordID"] as? String, !recordID.isEmpty,
                  let rawID = payload["requestID"] as? String,
                  let requestID = UUID(uuidString: rawID) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setUserShortcuts(.init(
                configuration: configuration, recordID: recordID), requestID: requestID))
        case "setUserTextures":
            guard let values = propertyValues(payload["values"]),
                  let references = textureReferences(payload["references"]),
                  let resetKeys = payload["resetKeys"] as? [String],
                  Set(resetKeys).count == resetKeys.count,
                  let revision = unsignedInteger(payload["revision"]),
                  let recordID = payload["recordID"] as? String else {
                return .failure(.invalidPayload(action))
            }
            let update = ScenePlaybackTextureUpdate(
                references: references, resetKeys: Set(resetKeys), values: values,
                revision: revision, recordID: recordID
            )
            guard update.isValid else { return .failure(.invalidPayload(action)) }
            return .success(.setUserTextures(update))
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
        case "commitCandidate", "finalizeCandidate", "cancelCandidate":
            guard let raw = payload["requestID"] as? String,
                  let requestID = UUID(uuidString: raw) else {
                return .failure(.invalidPayload(action))
            }
            switch action {
            case "commitCandidate": return .success(.commitCandidate(requestID: requestID))
            case "finalizeCandidate": return .success(.finalizeCandidate(requestID: requestID))
            default:
                let operationID: UUID?
                if let raw = payload["operationID"] {
                    guard let string = raw as? String, let parsed = UUID(uuidString: string) else {
                        return .failure(.invalidPayload(action))
                    }
                    operationID = parsed
                } else { operationID = nil }
                return .success(.cancelCandidate(requestID: requestID, operationID: operationID))
            }
        case "setOutputActive":
            guard let rawRequest = payload["requestID"] as? String,
                  let requestID = UUID(uuidString: rawRequest),
                  let rawOperation = payload["operationID"] as? String,
                  let operationID = UUID(uuidString: rawOperation),
                  let active = boolean(payload["active"]) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setOutputActive(requestID: requestID, operationID: operationID, active: active))
        case "retireOutput":
            guard let raw = payload["requestID"] as? String, let requestID = UUID(uuidString: raw),
                  let rawOperation = payload["operationID"] as? String,
                  let operationID = UUID(uuidString: rawOperation) else {
                return .failure(.invalidPayload(action))
            }
            let requireRequestRetirement: Bool
            if let value = payload["requireRequestRetirement"] {
                guard let required = boolean(value) else { return .failure(.invalidPayload(action)) }
                requireRequestRetirement = required
            } else { requireRequestRetirement = false }
            return .success(.retireOutput(requestID: requestID, operationID: operationID,
                                         requireRequestRetirement: requireRequestRetirement))
        case "setDisplayConfiguration":
            guard let topology = displayConfiguration(payload["screens"]) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setDisplayConfiguration(topology))
        case "setPerformanceProfile":
            guard let frameRate = animationFrameRate(payload["maxFPS"]) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setAnimationFrameRate(frameRate))
        case "setSceneRenderQuality":
            guard let quality = renderQuality(payload) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setSceneRenderQuality(quality))
        case "setCanvasFit":
            guard let fits = boolean(payload["fits"]) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setCanvasFit(fits))
        case "setVolume":
            guard let volume = finiteDouble(payload["volume"]),
                  (0 ... 1).contains(volume) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setVolume(Float(volume)))
        case "setMuted":
            guard let muted = boolean(payload["muted"]) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.setMuted(muted))
        case "captureFrame":
            guard let requestID = payload["requestID"] as? String,
                  !requestID.isEmpty else {
                return .failure(.invalidPayload(action))
            }
            return .success(.captureFrame(requestID: requestID))
        case "publishAudioSpectrum":
            guard let left = spectrumLevels(
                    payload["left"],
                    count: SceneAudioSpectrumSnapshot.bandCount
                  ),
                  let right = spectrumLevels(
                    payload["right"],
                    count: SceneAudioSpectrumSnapshot.bandCount
                  ),
                  let left32 = spectrumLevels(
                    payload["left32"],
                    count: SceneAudioSpectrumSnapshot.mediumBandCount
                  ),
                  let right32 = spectrumLevels(
                    payload["right32"],
                    count: SceneAudioSpectrumSnapshot.mediumBandCount
                  ),
                  let left64 = spectrumLevels(
                    payload["left64"],
                    count: SceneAudioSpectrumSnapshot.extendedBandCount
                  ),
                  let right64 = spectrumLevels(
                    payload["right64"],
                    count: SceneAudioSpectrumSnapshot.extendedBandCount
                  ),
                  let scopeEpoch = unsignedInteger(payload["scopeEpoch"]),
                  scopeEpoch > 0,
                  let includesDaemonProcessOutput = boolean(
                    payload["includesDaemonProcessOutput"]
                  ) else {
                return .failure(.invalidPayload(action))
            }
            return .success(.publishAudioSpectrum(.init(
                left: left,
                right: right,
                left32: left32,
                right32: right32,
                left64: left64,
                right64: right64,
                captureToken: .init(
                    scopeEpoch: scopeEpoch,
                    includesCurrentProcessOutput: includesDaemonProcessOutput
                )
            )))
        case "publishSystemMedia":
            guard let frame = SceneDaemonMediaWire.decode(
                SceneDaemonMediaSnapshotFrame.self, payload: payload,
                maximumBytes: SceneDaemonMediaWire.maximumMetadataBytes
            ) else { return .failure(.invalidPayload(action)) }
            return .success(.publishSystemMedia(frame))
        case "publishSystemMediaArtwork":
            guard let chunk = SceneDaemonMediaWire.decode(
                SceneDaemonMediaArtworkChunk.self, payload: payload,
                maximumBytes: SceneDaemonMediaWire.maximumChunkBytes * 2
            ), !chunk.bytes.isEmpty,
               chunk.bytes.count <= SceneDaemonMediaWire.maximumChunkBytes,
               chunk.index >= 0 else { return .failure(.invalidPayload(action)) }
            return .success(.publishSystemMediaArtwork(chunk))
        case "controlSystemMedia":
            guard let control = SceneDaemonMediaWire.decode(
                SceneDaemonMediaControl.self, payload: payload,
                maximumBytes: SceneDaemonMediaWire.maximumMetadataBytes
            ) else { return .failure(.invalidPayload(action)) }
            return .success(.controlSystemMedia(control))
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

    private static func animationFrameRate(_ raw: Any?) -> AnimationFrameRate? {
        integer(raw).flatMap(AnimationFrameRate.init(rawValue:))
    }

    static func writeRenderQuality(_ quality: SceneRenderQuality, to payload: inout [String: Any]) {
        payload["scenePostProcessing"] = quality.postProcessing.rawValue
        payload["shadowQuality"] = quality.shadows.rawValue
        payload["pointVolumeQuality"] = quality.volumeLighting.rawValue
        payload["reflectionQuality"] = quality.reflections.rawValue
        payload["textureQuality"] = quality.textures.rawValue
        payload["antiAliasingMode"] = quality.antiAliasing.rawValue
    }

    static func preparedRenderQuality(_ payload: [String: Any]) -> SceneRenderQuality? {
        guard payload["textureQuality"] != nil, payload["antiAliasingMode"] != nil else { return nil }
        return renderQuality(payload)
    }

    private static func renderQuality(_ payload: [String: Any], fallback: SceneRenderQuality? = nil) -> SceneRenderQuality? {
        let postProcessingRaw = payload["scenePostProcessing"] ?? fallback.map { $0.postProcessing.rawValue as Any }
        let shadowRaw = payload["shadowQuality"] ?? fallback.map { $0.shadows.rawValue as Any }
        let volumeLightingRaw = payload["pointVolumeQuality"] ?? fallback.map { $0.volumeLighting.rawValue as Any }
        let reflectionRaw = payload["reflectionQuality"] ?? fallback.map { $0.reflections.rawValue as Any }
        let textureRaw = payload["textureQuality"] ?? (fallback?.textures ?? .full).rawValue
        let antiAliasingRaw = payload["antiAliasingMode"] ?? (fallback?.antiAliasing ?? .none).rawValue
        guard let postProcessing = (postProcessingRaw as? String).flatMap(ScenePostProcessingMode.init(rawValue:)),
              let shadows = (shadowRaw as? String).flatMap(SceneShadowQuality.init(rawValue:)),
              let volumeLighting = (volumeLightingRaw as? String).flatMap(SceneVolumeLightingQuality.init(rawValue:)),
              let reflections = (reflectionRaw as? String).flatMap(SceneReflectionQuality.init(rawValue:)),
              let textures = (textureRaw as? String).flatMap(SceneTextureQuality.init(rawValue:)),
              let antiAliasing = (antiAliasingRaw as? String).flatMap(SceneAntiAliasingMode.init(rawValue:))
        else { return nil }
        return .init(postProcessing: postProcessing, shadows: shadows, volumeLighting: volumeLighting,
            reflections: reflections, textures: textures, antiAliasing: antiAliasing)
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
            let modeRate = finiteDouble(screen["modeRefreshRate"]).flatMap { $0 > 0 ? $0 : nil }
            let fallback = finiteDouble(screen["unknownModeRefreshLimit"]).flatMap { $0 > 0 ? $0 : nil }
            result.append(SceneScreenTopology(
                displayID: displayID,
                frame: CGRect(x: x, y: y, width: width, height: height),
                backingScaleFactor: scale,
                modeRefreshRate: modeRate,
                unknownModeRefreshLimit: modeRate == nil ? fallback : nil
            ))
        }
        return result.sorted { $0.displayID < $1.displayID }
    }

    static func presentationObject(_ presentation: ScenePlaybackPresentation) -> [String: Any] {
        ["alignment": presentation.alignment.rawValue, "position": presentation.position,
         "zoom": presentation.zoom, "listensToAudio": presentation.listensToAudio,
         "horizontalPosition": presentation.horizontalPosition, "verticalPosition": presentation.verticalPosition,
         "flippedHorizontally": presentation.flippedHorizontally, "allowsMouseParallax": presentation.allowsMouseParallax,
         "volume": presentation.volume, "rate": presentation.rate]
    }

    private static func decodePresentation(_ raw: Any) -> ScenePlaybackPresentation? {
        guard let object = raw as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: object),
              let value = try? JSONDecoder().decode(ScenePlaybackPresentation.self, from: data),
              value.isValid else { return nil }
        return value
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

    static func boolean(_ raw: Any?) -> Bool? {
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

    private static func spectrumLevels(_ raw: Any?, count: Int) -> [Float]? {
        guard let values = raw as? [Any], values.count == count else {
            return nil
        }
        var result: [Float] = []
        result.reserveCapacity(count)
        for rawValue in values {
            guard let value = finiteDouble(rawValue), value >= 0,
                  value <= Double(Float.greatestFiniteMagnitude) else {
                return nil
            }
            result.append(Float(value))
        }
        return result
    }
}
