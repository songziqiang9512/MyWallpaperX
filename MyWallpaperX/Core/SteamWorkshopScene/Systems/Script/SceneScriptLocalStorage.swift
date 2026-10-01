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
    private var defersPersistence: Bool
    private var activationBase: Envelope?
    private var frameTransactionBase: Envelope?
    private var frameTransactionCandidate: Envelope?

    private enum Scope: Hashable {
        case global
        case screen(String?)
    }
    private struct Batch {
        let owner: UInt
        let mutations: [SceneScriptStorageMutation]
    }
    // Borrowed VM handles are used only as frame-local tokens, never dereferenced.
    // Targets remain the product's existing owner identities.
    private var frameTargets: [UInt: SceneDynamicTarget] = [:]
    private var frameBatches: [Batch] = []
    private var frameWriters: [Scope: [String: UInt]] = [:]
    private var frameClears: [Scope: UInt] = [:]
    private var frameReaders: [UInt: Set<UInt>] = [:]
    private var frameReadOwners: Set<UInt> = []
    private var frameRejected: Set<UInt> = []
    private var frameJournalBytes = 0
    private var frameMutationCount = 0
    private var frameDependencyCount = 0
    private var frameReplayMutations = 0
    private static let maximumFrameOwners = 4096
    private static let maximumFrameMutations = 4096
    private static let maximumFrameDependencies = 16_384
    private static let maximumReplayMutations = 16_384

    init(recordID: String, rootDirectory: URL? = nil, defersPersistence: Bool = false) {
        self.defersPersistence = defersPersistence
        let root = rootDirectory ?? Self.defaultRootDirectory()
        let digest = SHA256.hash(data: Data(recordID.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        fileURL = root.appendingPathComponent("\(digest).json", isDirectory: false)
    }

    func read(
        screenIdentity: String?,
        globalScope: Bool,
        key: String,
        owner: UInt? = nil
    ) -> Result<String?, SceneScriptScalarRuntimeFailure> {
        lock.lock()
        defer { lock.unlock() }
        do {
            let current = try frameTransactionCandidate ?? loadIfNeeded()
            if frameTransactionCandidate != nil, let owner {
                let scope: Scope = globalScope ? .global : .screen(screenIdentity)
                if let writer = frameWriters[scope]?[key] ?? frameClears[scope],
                   writer != owner, frameReaders[writer]?.contains(owner) != true {
                    guard frameDependencyCount < Self.maximumFrameDependencies else {
                        // JS may catch a read error. Budget refusal still owns
                        // the whole candidate result, even if no value escaped.
                        frameReadOwners.insert(owner)
                        frameRejected.insert(owner)
                        throw SceneScriptScalarRuntimeFailure.budgetExceeded(
                            "localStorage frame read dependency budget exceeded"
                        )
                    }
                    frameReaders[writer, default: []].insert(owner)
                    frameReadOwners.insert(owner)
                    frameDependencyCount += 1
                }
            }
            if globalScope { return .success(current.global[key]) }
            guard let screenIdentity else { return .success(nil) }
            return .success(current.screens[screenIdentity]?[key])
        } catch let failure as SceneScriptScalarRuntimeFailure {
            return .failure(failure)
        } catch {
            return .failure(.invalidArgument(error.localizedDescription))
        }
    }

    func apply(
        _ mutations: [SceneScriptStorageMutation],
        owner: UInt? = nil,
        target: SceneDynamicTarget? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let inFrame = frameTransactionCandidate != nil
        if inFrame, mutations.isEmpty, let owner,
           frameTargets[owner] == nil, !frameReadOwners.contains(owner) {
            return
        }
        if inFrame {
            guard let owner, let target else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "localStorage frame mutation requires an owner"
                )
            }
            if let previous = frameTargets[owner], previous != target {
                frameRejected.insert(owner)
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "localStorage frame owner identity changed"
                )
            }
            guard frameTargets[owner] != nil || frameTargets.count < Self.maximumFrameOwners else {
                throw SceneScriptScalarRuntimeFailure.budgetExceeded(
                    "localStorage frame owner budget exceeded"
                )
            }
            // Read-only owners also need an identity for dependency rejection.
            frameTargets[owner] = target
        }
        guard !mutations.isEmpty else { return }
        let bytes = mutations.reduce(0) {
            $0 + 32 + ($1.key?.utf8.count ?? 0) + ($1.json?.utf8.count ?? 0)
                + ($1.screenIdentity?.utf8.count ?? 0)
        }
        if inFrame {
            guard frameMutationCount + mutations.count <= Self.maximumFrameMutations,
                  frameJournalBytes + bytes <= Self.maximumStoredFileBytes else {
                throw SceneScriptScalarRuntimeFailure.budgetExceeded(
                    "localStorage frame operation journal budget exceeded"
                )
            }
        }
        let current = try frameTransactionCandidate ?? loadIfNeeded()
        var candidate = current
        try Self.apply(mutations, to: &candidate)
        try Self.validate(candidate, validatingValues: false)
        if inFrame, let owner {
            frameTransactionCandidate = candidate
            frameBatches.append(.init(owner: owner, mutations: mutations))
            frameMutationCount += mutations.count
            frameJournalBytes += bytes
            for mutation in mutations {
                let scope: Scope = mutation.globalScope ? .global : .screen(mutation.screenIdentity)
                if mutation.kind == .clear {
                    frameWriters[scope] = nil
                    frameClears[scope] = owner
                } else if let key = mutation.key {
                    frameWriters[scope, default: [:]][key] = owner
                }
            }
        } else if candidate != current {
            loadState = .loaded(candidate)
            if !defersPersistence { PersistenceCoordinator.shared.schedule(candidate, for: fileURL) }
        }
    }

    /// Rebuild from the committed base, retaining authored execution order and
    /// original callback batch boundaries. Removing a deletion can make a later
    /// writer exceed quota; reject that whole owner and its readers, then retry.
    func resolveRejectedOwners(_ targets: Set<SceneDynamicTarget>) -> Set<SceneDynamicTarget> {
        lock.lock()
        defer { lock.unlock() }
        guard let base = frameTransactionBase else { return targets }
        if frameReplayMutations > Self.maximumReplayMutations {
            frameTransactionCandidate = base
            return targets.union(frameTargets.values)
        }
        var rejected = frameRejected.union(frameTargets.compactMap {
            targets.contains($0.value) ? $0.key : nil
        })
        guard !rejected.isEmpty else { return targets }
        func propagate() {
            var pending = Array(rejected)
            while let writer = pending.popLast() {
                for reader in frameReaders[writer] ?? [] {
                    if rejected.insert(reader).inserted {
                        pending.append(reader)
                        if let target = frameTargets[reader] {
                            NSLog("MWX SceneScript VM: localStorage owner=%@ callback=rejected reason=read-dependency fallback=previous-current", String(describing: target))
                        }
                    }
                }
            }
        }
        while true {
            propagate()
            var candidate = base
            var failed = false
            for batch in frameBatches where !rejected.contains(batch.owner) {
                frameReplayMutations += batch.mutations.count
                guard frameReplayMutations <= Self.maximumReplayMutations else {
                    // The unsafe unit is this storage transaction's participants.
                    // Unrelated Scene owners remain eligible for the frame.
                    frameRejected.formUnion(frameTargets.keys)
                    rejected.formUnion(frameRejected)
                    NSLog("MWX SceneScript VM: localStorage callback=rejected reason=replay-budget owners=%d fallback=previous-current", frameTargets.count)
                    candidate = base
                    break
                }
                do {
                    try Self.apply(batch.mutations, to: &candidate, validatingValues: false)
                    try Self.validate(candidate, validatingValues: false)
                } catch {
                    rejected.insert(batch.owner)
                    NSLog("MWX SceneScript VM: localStorage owner=%@ callback=rejected reason=replay-quota fallback=previous-current", String(describing: frameTargets[batch.owner]))
                    failed = true
                    break
                }
            }
            if failed { continue }
            frameTransactionCandidate = candidate
            return targets.union(rejected.compactMap { frameTargets[$0] })
        }
    }

    private func clearFrameTransaction() {
        frameTransactionBase = nil
        frameTransactionCandidate = nil
        frameTargets.removeAll(keepingCapacity: true)
        frameBatches.removeAll(keepingCapacity: true)
        frameWriters.removeAll(keepingCapacity: true)
        frameClears.removeAll(keepingCapacity: true)
        frameReaders.removeAll(keepingCapacity: true)
        frameReadOwners.removeAll(keepingCapacity: true)
        frameRejected.removeAll(keepingCapacity: true)
        frameJournalBytes = 0
        frameMutationCount = 0
        frameDependencyCount = 0
        frameReplayMutations = 0
    }

    func beginFrameTransaction() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard frameTransactionCandidate == nil else { return false }
        guard let current = try? loadIfNeeded() else { return false }
        frameTransactionBase = current
        frameTransactionCandidate = current
        return true
    }

    func commitFrameTransaction() {
        lock.lock()
        defer { lock.unlock() }
        guard let candidate = frameTransactionCandidate else { return }
        let changed = candidate != frameTransactionBase
        clearFrameTransaction()
        guard changed else { return }
        loadState = .loaded(candidate)
        if !defersPersistence { PersistenceCoordinator.shared.schedule(candidate, for: fileURL) }
    }

    func discardFrameTransaction() {
        lock.lock()
        clearFrameTransaction()
        lock.unlock()
    }

    /// Activation publishes only the candidate's changed keys. An outgoing
    /// scene may have written other keys while the candidate was preparing.
    func activatePersistence(replacing previous: SceneScriptLocalStorageSession?) {
        let previousEnvelope = previous?.loadedEnvelope(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        guard defersPersistence else { return }
        guard case let .loaded(candidate) = loadState else {
            defersPersistence = false
            return
        }
        let base = activationBase ?? candidate
        var merged = previousEnvelope ?? base
        func merge(_ before: [String: String], _ after: [String: String], into current: inout [String: String]) {
            for key in Set(before.keys).union(after.keys) where before[key] != after[key] {
                current[key] = after[key]
            }
        }
        merge(base.global, candidate.global, into: &merged.global)
        for screen in Set(base.screens.keys).union(candidate.screens.keys) {
            var current = merged.screens[screen] ?? [:]
            merge(base.screens[screen] ?? [:], candidate.screens[screen] ?? [:], into: &current)
            merged.screens[screen] = current.isEmpty ? nil : current
        }
        do {
            try Self.validate(merged, validatingValues: false)
            loadState = .loaded(merged)
            defersPersistence = false
            activationBase = nil
            if merged != (previousEnvelope ?? base) {
                PersistenceCoordinator.shared.schedule(merged, for: fileURL)
            }
        } catch {
            // The merged envelope can exceed the existing storage budget when
            // both sessions add disjoint keys. Reject only this storage owner.
            loadState = .unavailable("candidate localStorage merge exceeds budget")
            NSLog("MWX SceneScript VM: localStorage activation rejected failure=%@", error.localizedDescription)
        }
    }

    /// Owner transfer ends outgoing publication before destroy callbacks.
    func retirePersistence() {
        lock.lock()
        defersPersistence = true
        lock.unlock()
    }

    private func loadedEnvelope(for requestedURL: URL) -> Envelope? {
        lock.lock()
        defer { lock.unlock() }
        guard fileURL == requestedURL, case let .loaded(envelope) = loadState else { return nil }
        return envelope
    }

    private func loadIfNeeded() throws -> Envelope {
        defer {
            if defersPersistence, activationBase == nil, case let .loaded(envelope) = loadState {
                activationBase = envelope
            }
        }
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
        _ mutations: [SceneScriptStorageMutation],
        to candidate: inout Envelope,
        validatingValues: Bool = true
    ) throws {
        for mutation in mutations {
            if mutation.globalScope {
                try apply(mutation, to: &candidate.global, validatingValues: validatingValues)
            } else {
                guard let screen = mutation.screenIdentity, !screen.isEmpty else {
                    throw SceneScriptScalarRuntimeFailure.invalidArgument(
                        "screen localStorage identity is unavailable"
                    )
                }
                var scope = candidate.screens[screen] ?? [:]
                try apply(mutation, to: &scope, validatingValues: validatingValues)
                candidate.screens[screen] = scope.isEmpty ? nil : scope
            }
        }
    }

    private static func apply(
        _ mutation: SceneScriptStorageMutation,
        to scope: inout [String: String],
        validatingValues: Bool
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
                  (!validatingValues || Self.validJSON(json)) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "localStorage set contains an invalid key or JSON value"
                )
            }
            scope[key] = json
        }
    }

    private static func validate(
        _ envelope: Envelope,
        validatingValues: Bool = true
    ) throws {
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
                          && (!validatingValues || validJSON($0.value))
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
    _ owner: OpaquePointer?,
    _ screenPointer: UnsafePointer<CChar>?,
    _ screenLength: Int,
    _ globalScope: UInt32,
    _ keyPointer: UnsafePointer<CChar>?,
    _ keyLength: Int,
    _ jsonPointer: UnsafeMutablePointer<CChar>?,
    _ jsonCapacity: Int,
    _ jsonLength: UnsafeMutablePointer<Int>?
) -> MWXSceneQuickJSStorageReadResult {
    guard let opaque, let owner, let jsonLength,
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
        key: key,
        owner: UInt(bitPattern: owner)
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
        owner: OpaquePointer,
        target: SceneDynamicTarget
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        defer { mwx_scene_quickjs_owner_discard_storage_transaction(owner) }
        guard let storageSession else { return .success(()) }
        switch SceneScriptStorageMutationBridge.mutations(owner: owner) {
        case let .failure(failure): return .failure(failure)
        case let .success(mutations):
            do {
                try storageSession.apply(mutations, owner: UInt(bitPattern: owner), target: target)
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
