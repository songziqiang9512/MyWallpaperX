import AppKit
import Carbon
import Foundation

/// Read-only Music adapter. The caller owns source selection, queue, epoch,
/// polling, and publication. Contracts come from Music's installed public SDEF.
nonisolated enum SceneMusicPlayerSource {
    nonisolated enum PlaybackState: String, Sendable {
        case stopped, playing, paused, fastForwarding, rewinding
        var inboxValue: Int {
            switch self {
            case .stopped: 0
            case .paused: 2
            case .playing, .fastForwarding, .rewinding: 1
            }
        }
    }

    nonisolated struct Snapshot: Sendable {
        let identity: String
        let title: String
        let artist: String
        let album: String
        let state: PlaybackState
        let position: Double
        let duration: Double
        let artworkData: Data?
        let artworkFailure: Failure?
        let artworkPalette: SceneMediaArtworkPalette?
    }

    nonisolated enum ReadResult: Sendable {
        case snapshot(Snapshot)
        case noSession
        case failure(Failure)
    }

    nonisolated enum AuthorizationStatus: Equatable, Sendable {
        case authorized
        case consentRequired
        case denied
        case unavailable(Failure)
    }

    nonisolated enum Failure: Error, Equatable, Sendable {
        case invalidPID
        case targetNotRunning
        case wrongTarget
        case permissionBlocked(status: Int32, phase: String)
        case timeout(phase: String)
        case appleEvent(status: Int32, phase: String)
        case malformed(phase: String)
        case changedTrack

        static func appleEventStatus(_ status: Int32, phase: String) -> Self {
            if status == Int32(errAEEventNotPermitted) || status == Int32(errAEEventWouldRequireUserConsent) {
                return .permissionBlocked(status: status, phase: phase)
            }
            if status == Int32(errAETimeout) { return .timeout(phase: phase) }
            return .appleEvent(status: status, phase: phase)
        }
    }

    static let perEventTimeout: TimeInterval = 0.2
    static let overallTimeout: TimeInterval = 2
    static let sendOptions = NSAppleEventDescriptor.SendOptions(rawValue:
        UInt(kAEWaitReply | kAENeverInteract | kAEDontRecord | kAEDoNotPromptForUserConsent)
    )

    static func silentAuthorization(pid: pid_t) -> AuthorizationStatus {
        authorization(pid: pid, askUserIfNeeded: false)
    }

    /// Only call in response to the user's explicit authorization action.
    static func requestAuthorization(pid: pid_t) -> AuthorizationStatus {
        authorization(pid: pid, askUserIfNeeded: true)
    }

    private static func authorization(pid: pid_t, askUserIfNeeded: Bool) -> AuthorizationStatus {
        do {
            let (_, target) = try runningTarget(pid: pid)
            return try authorization(target: target, askUserIfNeeded: askUserIfNeeded)
        } catch let error as Failure { return .unavailable(error) }
        catch { return .unavailable(.malformed(phase: "authorization")) }
    }

    private static func authorization(
        target: NSAppleEventDescriptor,
        askUserIfNeeded: Bool
    ) throws -> AuthorizationStatus {
        guard let address = target.aeDesc else { throw Failure.malformed(phase: "PIDAddress") }
        let status = AEDeterminePermissionToAutomateTarget(
            address, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), askUserIfNeeded
        )
        switch status {
        case noErr: return .authorized
        case Int32(errAEEventWouldRequireUserConsent): return .consentRequired
        case Int32(errAEEventNotPermitted): return .denied
        default: return .unavailable(.appleEventStatus(status, phase: "permissionPreflight"))
        }
    }

    private static func runningTarget(pid: pid_t) throws -> (NSRunningApplication, NSAppleEventDescriptor) {
        guard pid > 0 else { throw Failure.invalidPID }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            throw Failure.targetNotRunning
        }
        guard app.bundleIdentifier == "com.apple.Music" else { throw Failure.wrongTarget }
        return (app, NSAppleEventDescriptor(processIdentifier: pid))
    }

    /// Synchronous off-frame read. No NSAppleEventDescriptor escapes this call.
    static func read(
        pid: pid_t,
        cachedArtworkIdentity: String? = nil,
        cachedArtworkData: Data? = nil,
        cachedArtworkPalette: SceneMediaArtworkPalette? = nil
    ) -> ReadResult {
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + overallTimeout
            let (app, target) = try runningTarget(pid: pid)
            switch try authorization(target: target, askUserIfNeeded: false) {
            case .authorized: break
            case .consentRequired:
                throw Failure.permissionBlocked(status: Int32(errAEEventWouldRequireUserConsent), phase: "permissionPreflight")
            case .denied:
                throw Failure.permissionBlocked(status: Int32(errAEEventNotPermitted), phase: "permissionPreflight")
            case .unavailable(let error): throw error
            }
            return try Transaction.read(
                pid: pid, cachedArtworkIdentity: cachedArtworkIdentity,
                cachedArtworkData: cachedArtworkData, cachedArtworkPalette: cachedArtworkPalette
            ) { object, phase in
                guard !app.isTerminated else { throw Failure.targetNotRunning }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { throw Failure.timeout(phase: "overall") }
                let event = Codec.request(object, target: target)
                let reply: NSAppleEventDescriptor
                do {
                    reply = try event.sendEvent(options: sendOptions, timeout: min(perEventTimeout, remaining))
                } catch {
                    guard let status = Int32(exactly: (error as NSError).code) else {
                        throw Failure.malformed(phase: phase + ".errorCode")
                    }
                    throw Failure.appleEventStatus(status, phase: phase)
                }
                guard ProcessInfo.processInfo.systemUptime <= deadline else {
                    throw Failure.timeout(phase: "overall")
                }
                return try Codec.replyValue(reply, phase: phase)
            }
        } catch let error as Failure { return .failure(error) }
        catch { return .failure(.malformed(phase: "unexpectedError")) }
    }

    nonisolated enum Codec {
        static let maximumTextBytes = 4 * 1_024
        static let maximumArtworkBytes = 16 * 1_024 * 1_024
        static let currentTrack = code("pTrk")
        static let persistentID = code("pPIS")
        static let title = code("pnam")
        static let artist = code("pArt")
        static let album = code("pAlb")
        static let duration = code("pDur")
        static let playerState = code("pPlS")
        static let position = code("pPos")
        static let rawData = code("pRaw")
        static let artworkClass = code("cArt")

        static func code(_ value: String) -> OSType {
            let bytes = Array(value.utf8)
            precondition(bytes.count == 4 && bytes.allSatisfy { $0 < 128 })
            return bytes.reduce(0) { ($0 << 8) | OSType($1) }
        }

        static func property(
            _ property: OSType,
            container: NSAppleEventDescriptor = .null()
        ) throws -> NSAppleEventDescriptor {
            try specifier(
                desiredClass: typeProperty,
                container: container,
                form: OSType(formPropertyID),
                key: NSAppleEventDescriptor(typeCode: property)
            )
        }

        static func firstArtwork(in track: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
            try specifier(
                desiredClass: artworkClass,
                container: track,
                form: OSType(formAbsolutePosition),
                key: NSAppleEventDescriptor(int32: 1)
            )
        }

        private static func specifier(
            desiredClass: OSType,
            container: NSAppleEventDescriptor,
            form: OSType,
            key: NSAppleEventDescriptor
        ) throws -> NSAppleEventDescriptor {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(NSAppleEventDescriptor(typeCode: desiredClass), forKeyword: AEKeyword(keyAEDesiredClass))
            record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
            record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
            record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
            guard let result = record.coerce(toDescriptorType: typeObjectSpecifier) else {
                throw Failure.malformed(phase: "specifier")
            }
            return result
        }

        static func request(
            _ object: NSAppleEventDescriptor,
            target: NSAppleEventDescriptor
        ) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(
                eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
                targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            event.setParam(object, forKeyword: keyDirectObject)
            return event
        }

        static func replyValue(_ reply: NSAppleEventDescriptor, phase: String) throws -> NSAppleEventDescriptor {
            if let error = reply.paramDescriptor(forKeyword: keyErrorNumber) {
                guard error.descriptorType == typeSInt32 else {
                    throw Failure.malformed(phase: phase + ".errorNumber")
                }
                if error.int32Value != 0 {
                    throw Failure.appleEventStatus(error.int32Value, phase: phase)
                }
            }
            guard let result = reply.paramDescriptor(forKeyword: keyDirectObject) else {
                throw Failure.malformed(phase: phase + ".missingReply")
            }
            return result
        }

        static func isMissing(_ descriptor: NSAppleEventDescriptor) -> Bool {
            descriptor.descriptorType == typeNull
                || (descriptor.descriptorType == typeType && descriptor.typeCodeValue == code("msng"))
        }

        static func trackReference(_ descriptor: NSAppleEventDescriptor, phase: String) throws {
            guard descriptor.descriptorType == typeObjectSpecifier else {
                throw Failure.malformed(phase: phase)
            }
        }

        static func text(_ descriptor: NSAppleEventDescriptor, phase: String) throws -> String {
            let types: [DescType] = [typeUTF8Text, typeUTF16ExternalRepresentation, typeUnicodeText, typeChar]
            guard types.contains(descriptor.descriptorType),
                  descriptor.data.count <= maximumTextBytes * 4,
                  let value = descriptor.stringValue,
                  value.utf8.count <= maximumTextBytes,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw Failure.malformed(phase: phase)
            }
            return value
        }

        static func trackID(_ descriptor: NSAppleEventDescriptor, phase: String) throws -> String {
            let value = try text(descriptor, phase: phase)
            guard !value.isEmpty, value.utf8.count <= 64,
                  value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
                throw Failure.malformed(phase: phase)
            }
            return value
        }

        static func nonnegativeReal(_ descriptor: NSAppleEventDescriptor, phase: String) throws -> Double {
            let types: [DescType] = [typeSInt16, typeSInt32, typeSInt64, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint]
            guard types.contains(descriptor.descriptorType),
                  let value = descriptor.coerce(toDescriptorType: typeIEEE64BitFloatingPoint),
                  value.data.count == MemoryLayout<Double>.size,
                  value.doubleValue.isFinite, value.doubleValue >= 0 else {
                throw Failure.malformed(phase: phase)
            }
            return value.doubleValue
        }

        static func playback(_ descriptor: NSAppleEventDescriptor) throws -> PlaybackState {
            guard descriptor.descriptorType == typeEnumerated else {
                throw Failure.malformed(phase: "playerState")
            }
            switch descriptor.enumCodeValue {
            case code("kPSS"): return .stopped
            case code("kPSP"): return .playing
            case code("kPSp"): return .paused
            case code("kPSF"): return .fastForwarding
            case code("kPSR"): return .rewinding
            default: throw Failure.malformed(phase: "playerState")
            }
        }

        static func artwork(_ descriptor: NSAppleEventDescriptor) throws -> Data? {
            if isMissing(descriptor) { return nil }
            let nonData: [DescType] = [typeAEList, typeAERecord, typeObjectSpecifier, typeAppleEvent,
                typeBoolean, typeSInt16, typeSInt32, typeSInt64, typeIEEE32BitFloatingPoint,
                typeIEEE64BitFloatingPoint, typeType, typeEnumerated, typeUTF8Text,
                typeUTF16ExternalRepresentation, typeUnicodeText, typeChar]
            guard !nonData.contains(descriptor.descriptorType), let raw = descriptor.aeDesc else {
                throw Failure.malformed(phase: "artwork")
            }
            let size = AEGetDescDataSize(raw)
            guard size >= 0, size <= maximumArtworkBytes else {
                throw Failure.malformed(phase: "artwork.byteBudget")
            }
            if size == 0 { return nil }
            let data = descriptor.data
            guard data.count == size else { throw Failure.malformed(phase: "artwork.data") }
            return data
        }

        static func requireSameTrack(_ before: String, _ after: String) throws {
            guard before == after else { throw Failure.changedTrack }
        }
    }

    nonisolated enum Transaction {
        static func read(
            pid: pid_t,
            cachedArtworkIdentity: String? = nil,
            cachedArtworkData: Data? = nil,
            cachedArtworkPalette: SceneMediaArtworkPalette? = nil,
            get: (NSAppleEventDescriptor, String) throws -> NSAppleEventDescriptor
        ) throws -> ReadResult {
            let initial = try get(Codec.property(Codec.currentTrack), "currentTrack.before")
            if Codec.isMissing(initial) {
                _ = try Codec.playback(get(
                    Codec.property(Codec.playerState), "playerState"
                ))
                let final = try get(Codec.property(Codec.currentTrack), "currentTrack.after")
                guard Codec.isMissing(final) else { throw Failure.changedTrack }
                return .noSession
            }
            try Codec.trackReference(initial, phase: "currentTrack.before")
            func trackProperty(_ code: OSType, _ phase: String) throws -> NSAppleEventDescriptor {
                try get(Codec.property(code, container: initial), phase)
            }
            let id = try Codec.trackID(trackProperty(Codec.persistentID, "persistentID.before"), phase: "persistentID.before")
            let identity = "com.apple.Music:\(pid):\(id)"
            let title = try Codec.text(trackProperty(Codec.title, "title"), phase: "title")
            let artist = try Codec.text(trackProperty(Codec.artist, "artist"), phase: "artist")
            let album = try Codec.text(trackProperty(Codec.album, "album"), phase: "album")
            let duration = try Codec.nonnegativeReal(trackProperty(Codec.duration, "duration"), phase: "duration")
            let state = try Codec.playback(get(
                Codec.property(Codec.playerState), "playerState"
            ))
            let position = try Codec.nonnegativeReal(get(
                Codec.property(Codec.position), "position"
            ), phase: "position")
            let art: Data?
            let reusesArtwork: Bool
            var artworkFailure: Failure?
            if cachedArtworkIdentity == identity, let cachedArtworkData,
               !cachedArtworkData.isEmpty, cachedArtworkData.count <= Codec.maximumArtworkBytes {
                art = cachedArtworkData
                reusesArtwork = true
            } else {
                reusesArtwork = false
                do {
                    let artwork = try Codec.firstArtwork(in: initial)
                    let raw = try get(Codec.property(Codec.rawData, container: artwork), "artwork")
                    art = try Codec.artwork(raw)
                } catch Failure.appleEvent(let status, let phase) where status == Int32(errAENoSuchObject) && phase == "artwork" {
                    // This optional absence is accepted only after the final
                    // current-track check proves that the required track matches.
                    art = nil
                } catch Failure.malformed(let phase) where phase.hasPrefix("artwork") {
                    art = nil
                    artworkFailure = .malformed(phase: phase)
                }
            }
            let final = try get(Codec.property(Codec.currentTrack), "currentTrack.after")
            guard !Codec.isMissing(final) else { throw Failure.changedTrack }
            try Codec.trackReference(final, phase: "currentTrack.after")
            let afterID = try Codec.trackID(get(
                Codec.property(Codec.persistentID, container: final), "persistentID.after"
            ), phase: "persistentID.after")
            try Codec.requireSameTrack(id, afterID)
            return .snapshot(Snapshot(
                identity: identity, title: title, artist: artist, album: album,
                state: state, position: position, duration: duration,
                artworkData: art, artworkFailure: artworkFailure,
                artworkPalette: reusesArtwork ? cachedArtworkPalette
                    : art.flatMap { SceneMediaArtworkPalette.extract(from: $0) }
            ))
        }
    }
}
