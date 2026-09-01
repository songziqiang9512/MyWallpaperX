import CryptoKit
import Foundation

nonisolated struct SceneScriptStorageMutation: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case set, delete, clear }

    let kind: Kind
    let globalScope: Bool
    let screenIdentity: String?
    let key: String?
    let json: String?
}

nonisolated final class SceneScriptLocalStorageSession: @unchecked Sendable {
    private struct Envelope: Codable, Equatable, Sendable {
        let version: Int
        var global: [String: String]
        var screens: [String: [String: String]]

        static let empty = Self(version: 1, global: [:], screens: [:])
    }

    private enum LoadState {
        case unloaded
        case loaded(Envelope)
        case unavailable(String)
    }

    /// A single process-wide writer serializes replacement of a wallpaper's
    /// envelope. It keeps only the newest snapshot per file, so a script that
    /// writes every frame cannot turn the render thread into a disk-I/O loop.
    private final class PersistenceCoordinator: @unchecked Sendable {
        private struct Pending {
            var envelope: Envelope
            var revision: UInt64
            var scheduled: Bool
            var attempts: Int
        }

        static let shared = PersistenceCoordinator()

        private let lock = NSLock()
        private let queue = DispatchQueue(
            label: "com.mywallpaperx.scene-script-local-storage",
            qos: .utility
        )
        private var pendingByURL: [URL: Pending] = [:]

        func latestSnapshot(for fileURL: URL) -> Envelope? {
            lock.lock()
            defer { lock.unlock() }
            return pendingByURL[fileURL]?.envelope
        }

        func schedule(_ envelope: Envelope, for fileURL: URL) {
            lock.lock()
            let shouldEnqueue: Bool
            if var pending = pendingByURL[fileURL] {
                pending.envelope = envelope
                pending.revision &+= 1
                pending.attempts = 0
                shouldEnqueue = !pending.scheduled
                pending.scheduled = true
                pendingByURL[fileURL] = pending
            } else {
                pendingByURL[fileURL] = .init(
                    envelope: envelope,
                    revision: 1,
                    scheduled: true,
                    attempts: 0
                )
                shouldEnqueue = true
            }
            lock.unlock()
            if shouldEnqueue { enqueue(fileURL, delay: .milliseconds(250)) }
        }

        private func enqueue(
            _ fileURL: URL,
            delay: DispatchTimeInterval
        ) {
            queue.asyncAfter(deadline: .now() + delay) { [self] in
                persistLatest(for: fileURL)
            }
        }

        private func persistLatest(for fileURL: URL) {
            lock.lock()
            guard let snapshot = pendingByURL[fileURL] else {
                lock.unlock()
                return
            }
            lock.unlock()

            let failure: String?
            do {
                let data = try sceneScriptStorageEncoder().encode(
                    snapshot.envelope
                )
                guard data.count <= SceneScriptLocalStorageSession
                    .maximumStoredFileBytes else {
                    throw SceneScriptScalarRuntimeFailure.budgetExceeded(
                        "encoded localStorage envelope exceeds its file budget"
                    )
                }
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                failure = nil
            } catch {
                failure = error.localizedDescription
            }

            lock.lock()
            guard var current = pendingByURL[fileURL] else {
                lock.unlock()
                return
            }
            if current.revision != snapshot.revision {
                current.scheduled = true
                pendingByURL[fileURL] = current
                lock.unlock()
                enqueue(fileURL, delay: .milliseconds(250))
                return
            }
            if let failure {
                current.attempts += 1
                let shouldRetry = current.attempts < 3
                current.scheduled = shouldRetry
                pendingByURL[fileURL] = current
                lock.unlock()
                NSLog(
                    "MWX SceneScript VM: localStorage persistence failure=%@ retry=%@",
                    failure,
                    shouldRetry ? "scheduled" : "deferred-until-next-mutation"
                )
                if shouldRetry { enqueue(fileURL, delay: .seconds(1)) }
                return
            }
            pendingByURL.removeValue(forKey: fileURL)
            lock.unlock()
        }
    }

    private static let maximumStoredFileBytes = 3 * 1_048_576
    private static let maximumScreenScopes = 32

    private let lock = NSLock()
    private let fileURL: URL
    private var loadState: LoadState = .unloaded

    init(recordID: String, rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        let digest = SHA256.hash(data: Data(recordID.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        fileURL = root.appendingPathComponent("\(digest).json", isDirectory: false)
    }

    func read(
        screenIdentity: String?,
        globalScope: Bool,
        key: String
    ) -> Result<String?, SceneScriptScalarRuntimeFailure> {
        lock.lock()
        defer { lock.unlock() }
        do {
            let current = try loadIfNeeded()
            if globalScope { return .success(current.global[key]) }
            guard let screenIdentity else { return .success(nil) }
            return .success(current.screens[screenIdentity]?[key])
        } catch let failure as SceneScriptScalarRuntimeFailure {
            return .failure(failure)
        } catch {
            return .failure(.invalidArgument(error.localizedDescription))
        }
    }

    func apply(_ mutations: [SceneScriptStorageMutation]) throws {
        guard !mutations.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let current = try loadIfNeeded()
        var candidate = current
        for mutation in mutations {
            if mutation.globalScope {
                try Self.apply(mutation, to: &candidate.global)
            } else {
                guard let screenIdentity = mutation.screenIdentity,
                      !screenIdentity.isEmpty else {
                    throw SceneScriptScalarRuntimeFailure.invalidArgument(
                        "screen localStorage identity is unavailable"
                    )
                }
                var scope = candidate.screens[screenIdentity] ?? [:]
                try Self.apply(mutation, to: &scope)
                candidate.screens[screenIdentity] = scope.isEmpty ? nil : scope
            }
        }
        guard candidate != current else { return }
        try Self.validate(candidate)
        loadState = .loaded(candidate)
        PersistenceCoordinator.shared.schedule(candidate, for: fileURL)
    }

    private func loadIfNeeded() throws -> Envelope {
        switch loadState {
        case let .loaded(envelope): return envelope
        case let .unavailable(message):
            throw SceneScriptScalarRuntimeFailure.invalidArgument(message)
        case .unloaded: break
        }
        if let pending = PersistenceCoordinator.shared.latestSnapshot(for: fileURL) {
            loadState = .loaded(pending)
            return pending
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: fileURL.path,
            isDirectory: &isDirectory
        ) else {
            loadState = .loaded(.empty)
            return .empty
        }
        guard !isDirectory.boolValue else {
            return try failLoad("localStorage path is a directory")
        }
        guard let data = boundedStoredData() else {
            return try failLoad("localStorage envelope is unreadable or oversized")
        }
        let decoded: Envelope
        do {
            decoded = try JSONDecoder().decode(Envelope.self, from: data)
            guard decoded.version == 1 else {
                return try failLoad("localStorage envelope version is unsupported")
            }
            try Self.validate(decoded)
        } catch let failure as SceneScriptScalarRuntimeFailure {
            return try failLoad(String(describing: failure))
        } catch {
            return try failLoad("localStorage envelope is invalid")
        }
        loadState = .loaded(decoded)
        return decoded
    }

    private func failLoad(_ message: String) throws -> Envelope {
        loadState = .unavailable(message)
        throw SceneScriptScalarRuntimeFailure.invalidArgument(message)
    }

    private func boundedStoredData() -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(
            upToCount: Self.maximumStoredFileBytes + 1
        ), data.count <= Self.maximumStoredFileBytes else { return nil }
        return data
    }

    private static func apply(
        _ mutation: SceneScriptStorageMutation,
        to scope: inout [String: String]
    ) throws {
        switch mutation.kind {
        case .clear:
            scope.removeAll(keepingCapacity: true)
        case .delete:
            guard let key = mutation.key else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "localStorage delete is missing its key"
                )
            }
            scope.removeValue(forKey: key)
        case .set:
            guard let key = mutation.key, let json = mutation.json,
                  key.utf8.count <= 256, json.utf8.count <= 65_536,
                  Self.validJSON(json) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "localStorage set contains an invalid key or JSON value"
                )
            }
            scope[key] = json
        }
    }

    private static func validate(_ envelope: Envelope) throws {
        guard envelope.screens.count <= maximumScreenScopes,
              envelope.screens.keys.allSatisfy({
                  !$0.isEmpty && $0.utf8.count <= 256
              }) else {
            throw SceneScriptScalarRuntimeFailure.budgetExceeded(
                "localStorage screen scope budget exceeded"
            )
        }
        let scopes = [envelope.global] + Array(envelope.screens.values)
        guard scopes.allSatisfy({ $0.count <= 256 }) else {
            throw SceneScriptScalarRuntimeFailure.budgetExceeded(
                "localStorage scope exceeds 256 entries"
            )
        }
        for scope in scopes {
            let bytes = scope.reduce(0) {
                $0 + $1.key.utf8.count + $1.value.utf8.count
            }
            guard bytes <= 262_144,
                  scope.allSatisfy({
                      $0.key.utf8.count <= 256
                          && $0.value.utf8.count <= 65_536
                          && validJSON($0.value)
                  }) else {
                throw SceneScriptScalarRuntimeFailure.budgetExceeded(
                    "localStorage scope exceeds its byte budget"
                )
            }
        }
        let total = scopes.flatMap { $0 }.reduce(0) {
            $0 + $1.key.utf8.count + $1.value.utf8.count
        }
        guard total <= 1_048_576 else {
            throw SceneScriptScalarRuntimeFailure.budgetExceeded(
                "localStorage wallpaper exceeds 1 MiB"
            )
        }
    }

    private static func validJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        )) != nil
    }

    private static func defaultRootDirectory() -> URL {
        let identifier = Bundle.main.bundleIdentifier ?? "MyWallpaperX"
        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("SceneScriptLocalStorage", isDirectory: true)
    }
}

private nonisolated func sceneScriptStorageEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}

private nonisolated func sceneScriptStorageString(
    _ pointer: UnsafePointer<CChar>?,
    _ length: Int
) -> String? {
    guard length >= 0, length == 0 || pointer != nil else { return nil }
    let bytes = UnsafeRawBufferPointer(start: pointer, count: length)
    return String(bytes: bytes, encoding: .utf8)
}

private nonisolated func sceneScriptLocalStorageRead(
    _ opaque: UnsafeMutableRawPointer?,
    _ screenPointer: UnsafePointer<CChar>?,
    _ screenLength: Int,
    _ globalScope: UInt32,
    _ keyPointer: UnsafePointer<CChar>?,
    _ keyLength: Int,
    _ jsonPointer: UnsafeMutablePointer<CChar>?,
    _ jsonCapacity: Int,
    _ jsonLength: UnsafeMutablePointer<Int>?
) -> MWXSceneQuickJSStorageReadResult {
    guard let opaque, let jsonLength,
          globalScope <= 1,
          let key = sceneScriptStorageString(keyPointer, keyLength),
          let screen = sceneScriptStorageString(screenPointer, screenLength) else {
        return MWX_SCENE_QUICKJS_STORAGE_READ_ERROR
    }
    let session = Unmanaged<SceneScriptLocalStorageSession>
        .fromOpaque(opaque).takeUnretainedValue()
    switch session.read(
        screenIdentity: screen.isEmpty ? nil : screen,
        globalScope: globalScope != 0,
        key: key
    ) {
    case .failure:
        jsonLength.pointee = 0
        return MWX_SCENE_QUICKJS_STORAGE_READ_ERROR
    case .success(nil):
        jsonLength.pointee = 0
        return MWX_SCENE_QUICKJS_STORAGE_READ_MISSING
    case let .success(json?):
    let bytes = Array(json.utf8)
    jsonLength.pointee = bytes.count
    guard let jsonPointer, jsonCapacity > bytes.count else {
        return MWX_SCENE_QUICKJS_STORAGE_READ_BUFFER_TOO_SMALL
    }
    for (index, byte) in bytes.enumerated() {
        jsonPointer[index] = CChar(bitPattern: byte)
    }
    jsonPointer[bytes.count] = 0
    return MWX_SCENE_QUICKJS_STORAGE_READ_FOUND
    }
}

nonisolated enum SceneScriptStorageMutationBridge {
    static func mutations(
        owner: OpaquePointer
    ) -> Result<[SceneScriptStorageMutation], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_storage_mutation_count(owner)
        guard count <= 64 else {
            return .failure(.mutationOverflow(
                "localStorage mutation buffer exceeded"
            ))
        }
        var output: [SceneScriptStorageMutation] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            var raw = MWXSceneQuickJSStorageMutation()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_storage_mutation_at(
                owner, index, &raw, &diagnostic, diagnostic.count
            )
            guard result == MWX_SCENE_QUICKJS_OK,
                  raw.global_scope <= 1,
                  let screen = sceneScriptStorageString(
                      raw.screen_identity, raw.screen_identity_length
                  ),
                  let key = sceneScriptStorageString(raw.key, raw.key_length),
                  let json = sceneScriptStorageString(raw.json, raw.json_length)
            else {
                return .failure(.invalidArgument(String(cString: diagnostic)))
            }
            let kind: SceneScriptStorageMutation.Kind
            switch raw.kind {
            case UInt32(MWX_SCENE_QUICKJS_STORAGE_SET.rawValue): kind = .set
            case UInt32(MWX_SCENE_QUICKJS_STORAGE_DELETE.rawValue): kind = .delete
            case UInt32(MWX_SCENE_QUICKJS_STORAGE_CLEAR.rawValue): kind = .clear
            default:
                return .failure(.invalidArgument(
                    "unknown localStorage mutation kind"
                ))
            }
            output.append(.init(
                kind: kind,
                globalScope: raw.global_scope != 0,
                screenIdentity: screen.isEmpty ? nil : screen,
                key: key.isEmpty && raw.key == nil ? nil : key,
                json: json.isEmpty && raw.json == nil ? nil : json
            ))
        }
        return .success(output)
    }
}

extension SceneScriptQuickJSDomain {
    func configureStorage(_ session: SceneScriptLocalStorageSession) throws {
        var diagnostic = [CChar](repeating: 0, count: 512)
        let opaque = Unmanaged.passUnretained(session).toOpaque()
        let result = mwx_scene_quickjs_domain_configure_storage(
            handle, sceneScriptLocalStorageRead, opaque,
            &diagnostic, diagnostic.count
        )
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                String(cString: diagnostic)
            )
        }
        storageSession = session
    }

    func setStorageScreenIdentity(_ identity: String?) throws {
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result: MWXSceneQuickJSResult
        if let identity {
            result = identity.withCString {
                mwx_scene_quickjs_domain_set_storage_screen_identity(
                    handle, $0, identity.utf8.count,
                    &diagnostic, diagnostic.count
                )
            }
        } else {
            result = mwx_scene_quickjs_domain_set_storage_screen_identity(
                handle, nil, 0, &diagnostic, diagnostic.count
            )
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                String(cString: diagnostic)
            )
        }
    }

    func commitStorage(
        owner: OpaquePointer
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        defer { mwx_scene_quickjs_owner_discard_storage_transaction(owner) }
        guard let storageSession else { return .success(()) }
        switch SceneScriptStorageMutationBridge.mutations(owner: owner) {
        case let .failure(failure): return .failure(failure)
        case let .success(mutations):
            do {
                try storageSession.apply(mutations)
                return .success(())
            } catch let failure as SceneScriptScalarRuntimeFailure {
                return .failure(failure)
            } catch {
                return .failure(.invalidArgument(
                    "localStorage commit failed: \(error.localizedDescription)"
                ))
            }
        }
    }

    func discardStorage(owner: OpaquePointer) {
        mwx_scene_quickjs_owner_discard_storage_transaction(owner)
    }
}
