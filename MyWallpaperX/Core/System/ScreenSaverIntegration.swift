import AppKit
import Combine
import Darwin
import Foundation

/// Owns media publication and legacy migration. App assembly resolves intent;
/// the system component consumes the resulting self-contained configuration.
@MainActor
final class ScreenSaverIntegration: NSObject, ObservableObject {
    static let shared = ScreenSaverIntegration()
    nonisolated static let configurationChanged = ScreenSaverConfiguration.changedNotification
    nonisolated static let componentBundleIdentifier = "com.songziqiang.MyWallpaperX.ScreenSaver"

    nonisolated struct PublicationInput: Equatable, Sendable {
        let videoURL: URL
        let title: String
        /// A producer-owned content/resource revision, never a path-only key.
        /// Nil requests a fresh snapshot; options alone use updateOptions.
        let revision: String?
        let sourceIdentity: String?

        init(videoURL: URL, title: String, revision: String? = nil, sourceIdentity: String? = nil) {
            self.videoURL = videoURL
            self.title = title
            self.revision = revision
            self.sourceIdentity = sourceIdentity
        }
    }

    enum Activity: Equatable { case idle, publishing, clearing, preparing }
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var configuration: ScreenSaverConfiguration?
    /// Installation is a filesystem fact, not the system's selected module.
    @Published private(set) var isInstalled = false
    nonisolated let hasBundledComponent: Bool
    @Published private(set) var errorMessage: String?
    /// Preview consumers resolve only paths from the committed configuration.
    var configurationRoot: URL? { try? rootURL() }

    private nonisolated let queue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.screen-saver-publication", qos: .utility)
    private nonisolated let requests = Requests()
    private nonisolated let injectedRootURL: URL?
    private nonisolated let injectedInstallationURL: URL?
    private nonisolated let copyFile: @Sendable (URL, URL) throws -> Void
    // Accessed only by queue. No persisted duplicate of the App's source intent.
    private nonisolated(unsafe) var reusablePublication: (PublicationInput, ScreenSaverConfiguration.Content)?

    init(rootURL: URL? = nil, installationURL: URL? = nil, componentSourceURL: URL? = nil,
         copyFile: @escaping @Sendable (URL, URL) throws -> Void = {
             try FileManager().copyItem(at: $0, to: $1)
         }) {
        injectedRootURL = rootURL
        injectedInstallationURL = installationURL
        let source = componentSourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Extensions/MyWallpaperXSystemWallpaper.appex", isDirectory: true)
        hasBundledComponent = FileManager.default.fileExists(atPath: source.path)
        self.copyFile = copyFile
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate),
                                               name: NSApplication.willTerminateNotification, object: nil)
        refresh()
    }

    deinit {
        requests.invalidate(close: true)
        NotificationCenter.default.removeObserver(self)
    }

    /// All completions run on MainActor exactly once. Cancel invalidates commit
    /// synchronously; a copy already inside FileManager may finish privately.
    func publish(_ input: PublicationInput, fillMode: String, playsOnBattery: Bool,
                 completion: @escaping @MainActor (Result<ScreenSaverConfiguration, Error>) -> Void) {
        let request = begin(.publishing)
        queue.async { [self] in
            let result = Result {
                try publish(input, fillMode: fillMode, playsOnBattery: playsOnBattery, request: request)
            }
            complete(request, result: result, configuration: try? result.get(), completion: completion)
        }
    }

    /// Fill/battery edits retain the existing immutable generation and lease.
    func updateOptions(fillMode: String, playsOnBattery: Bool,
                       completion: @escaping @MainActor (Result<ScreenSaverConfiguration, Error>) -> Void) {
        let request = begin(.publishing)
        queue.async { [self] in
            let result = Result {
                let root = try rootURL()
                guard let current = try readConfiguration(in: root), let content = current.content else {
                    throw Failure.message("尚未保存可用的视频，请先选择视频。")
                }
                let media = try ScreenSaverPaths.mediaRoot(in: root, generation: content.mediaGeneration)
                let video = try ScreenSaverPaths.resource(content.entryRelativePath, in: media)
                let poster = try ScreenSaverPaths.resource(content.posterRelativePath, in: media)
                guard FileManager.default.isReadableFile(atPath: video.path),
                      FileManager.default.isReadableFile(atPath: poster.path) else {
                    throw Failure.message("已保存的视频或静帧不可读取，请重新保存视频。")
                }
                let value = ScreenSaverConfiguration(content: content, fillMode: fillMode,
                                                      playsOnBattery: playsOnBattery)
                try commit(value, in: root, request: request)
                return value
            }
            complete(request, result: result, configuration: try? result.get(), completion: completion)
        }
    }

    func cancel() {
        requests.invalidate()
        activity = .idle
        errorMessage = nil
    }

    func cancelForExit() {
        requests.invalidate(close: true)
        activity = .idle
    }

    func clear(completion: @escaping @MainActor (Result<ScreenSaverConfiguration, Error>) -> Void = { _ in }) {
        let request = begin(.clearing)
        queue.async { [self] in
            let result = Result { try clear(request: request) }
            complete(request, result: result, configuration: try? result.get(), completion: completion)
        }
    }

    func prepareSharedStorage(completion: @escaping @MainActor (Result<Void, Error>) -> Void = { _ in }) {
        let request = begin(.preparing)
        queue.async { [self] in
            let result = Result { try prepareStorage(request: request) }
            complete(request, result: result, completion: completion)
        }
    }

    func uninstallLegacy(completion: @escaping @MainActor (Result<Void, Error>) -> Void = { _ in }) {
        queue.async { [self] in
            let result = Result {
                let destination = try installationURL()
                guard FileManager.default.fileExists(atPath: destination.path) else { return }
                guard try isLegacyComponent(at: destination) else {
                    throw Failure.message("同名屏保组件不属于 MyWallpaperX，已保留现有文件")
                }
                try FileManager.default.removeItem(at: destination)
            }
            DispatchQueue.main.async { [weak self] in
                if case .success = result { self?.isInstalled = false }
                completion(result)
            }
        }
    }

    func refresh() {
        let request = requests.current()
        queue.async { [self] in
            let result = Result { try readConfiguration(in: rootURL()) }
            let installed = (try? isLegacyComponent(at: installationURL())) == true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requests.isCurrent(request), self.activity == .idle else { return }
                if case let .success(value) = result { self.configuration = value }
                self.isInstalled = installed
                if case let .failure(error) = result { self.errorMessage = error.localizedDescription }
            }
        }
    }

    @objc private func applicationWillTerminate() { cancelForExit() }

    private func begin(_ activity: Activity) -> UInt64 {
        let request = requests.next()
        self.activity = activity
        errorMessage = nil
        return request
    }

    private nonisolated func complete<Value: Sendable>(
        _ request: UInt64, result: Result<Value, Error>,
        configuration: ScreenSaverConfiguration? = nil,
        completion: @escaping @MainActor (Result<Value, Error>) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { completion(.failure(CocoaError(.userCancelled))); return }
            // A commit linearized before cancel remains an actual disk fact.
            // FIFO callbacks from queue preserve the order of those facts.
            if let configuration { self.configuration = configuration }
            guard self.requests.isCurrent(request) else {
                completion(.failure(CocoaError(.userCancelled)))
                return
            }
            self.activity = .idle
            if case let .failure(error) = result { self.errorMessage = error.localizedDescription }
            completion(result)
        }
    }

    private nonisolated func rootURL() throws -> URL {
        try (injectedRootURL ?? ScreenSaverPaths.currentUserRoot()).standardizedFileURL
    }

    private nonisolated func installationURL() throws -> URL {
        if let injectedInstallationURL { return injectedInstallationURL }
        let library = try ScreenSaverPaths.currentUserRoot().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return library.appendingPathComponent("Screen Savers/MyWallpaperX.saver", isDirectory: true)
    }

    private nonisolated func readConfiguration(in root: URL, name: String = "current.json") throws -> ScreenSaverConfiguration? {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(ScreenSaverConfiguration.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1 else { throw Failure.message("此屏保配置版本无法由当前 App 修改") }
        return value
    }

    private nonisolated func publish(_ input: PublicationInput, fillMode: String,
                                    playsOnBattery: Bool, request: UInt64) throws -> ScreenSaverConfiguration {
        try requests.check(request)
        let root = try rootURL()
        // Unsupported legacy content is replaceable only after this new
        // video and its own poster have been deployed successfully.
        if input.revision != nil, let reusablePublication, reusablePublication.0 == input,
           (try? readConfiguration(in: root))?.content == reusablePublication.1 {
            let value = ScreenSaverConfiguration(content: reusablePublication.1, fillMode: fillMode,
                                                  playsOnBattery: playsOnBattery)
            try commit(value, in: root, request: request)
            return value
        }
        let generation = UUID().uuidString
        let media = try ScreenSaverPaths.mediaRoot(in: root, generation: generation)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let leaseURL = media.appendingPathComponent(".lease")
        let descriptor = open(leaseURL.path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(at: media)
            throw error
        }
        var committed = false
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
            if !committed { try? FileManager.default.removeItem(at: media) }
        }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        try Self.leaseMarker.write(to: leaseURL)
        let content = try deploy(input, generation: generation, media: media, request: request)
        let value = ScreenSaverConfiguration(content: content, fillMode: fillMode, playsOnBattery: playsOnBattery)
        // Publish while retaining a shared lease. Readers can join immediately;
        // another publisher cannot collect this generation before current commits.
        guard flock(descriptor, LOCK_SH) == 0 else { throw POSIXError(.EIO) }
        try commit(value, in: root, request: request)
        committed = true
        reusablePublication = (input, content)
        return value
    }

    private nonisolated func deploy(_ input: PublicationInput, generation: String, media: URL,
                                   request: UInt64) throws -> ScreenSaverConfiguration.Content {
        try requests.check(request)
        guard input.videoURL.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let source = input.videoURL.resolvingSymlinksInPath().standardizedFileURL
        guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw Failure.message("所选视频不是可读取的文件，已保留原屏保。")
        }
        let entry = "Video/" + source.lastPathComponent
        let destination = media.appendingPathComponent(entry)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try copyFile(source, destination)
        try requests.check(request)
        do {
            try VideoStillFrame.writeJPEG(from: destination, to: media.appendingPathComponent("poster.jpg"),
                                          isCancelled: { !self.requests.isCurrent(request) })
        } catch {
            try requests.check(request)
            throw Failure.message("视频静帧生成失败，已保留原屏保。")
        }
        try requests.check(request)
        return .init(kind: .video, mediaGeneration: generation, title: input.title,
                     sourceIdentity: input.sourceIdentity, entryRelativePath: entry, posterRelativePath: "poster.jpg")
    }

    private nonisolated func clear(request: UInt64) throws -> ScreenSaverConfiguration {
        let root = try rootURL()
        // Clear replaces unsupported or damaged configuration directly;
        // a video save replaces it only after preparing a successful candidate.
        let previous = try? readConfiguration(in: root)
        let value = ScreenSaverConfiguration(content: nil, fillMode: previous?.fillMode ?? "aspectFill",
                                              playsOnBattery: previous?.playsOnBattery ?? false)
        try commit(value, in: root, request: request, preservePrevious: false)
        reusablePublication = nil
        return value
    }

    private nonisolated func commit(_ value: ScreenSaverConfiguration, in root: URL,
                                    request: UInt64, preservePrevious: Bool = true) throws {
        try requests.check(request)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let destination = root.appendingPathComponent("current.json")
        let previousURL = root.appendingPathComponent("previous.json")
        let pending = root.appendingPathComponent(".current-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: pending) }
        let data = try JSONEncoder().encode(value)
        try data.write(to: pending)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pending.path)
        let old = preservePrevious ? (try? readConfiguration(in: root)) : nil
        let backup: Data?
        if preservePrevious, old?.content != nil,
           old?.content?.mediaGeneration != value.content?.mediaGeneration {
            backup = try JSONEncoder().encode(old)
        } else { backup = nil }
        try requests.commit(request) {
            if let backup { try backup.write(to: previousURL, options: [.atomic]) }
            guard rename(pending.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            // Retire an unusable fallback only after current commits. A
            // failed/cancelled replacement of damaged input keeps both files.
            if !preservePrevious || old?.content == nil {
                _ = unlink(previousURL.path)
            }
        }
        DistributedNotificationCenter.default().postNotificationName(Self.configurationChanged,
            object: nil, userInfo: nil, deliverImmediately: true)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.configurationChanged, object: nil)
        }
        // Low-frequency maintenance only. Active consumers hold their own lock.
        queue.async { [self] in collectRetiredMedia(in: root) }
    }

    private nonisolated static let leaseMarker = Data((componentBundleIdentifier + "\n").utf8)

    private nonisolated func collectRetiredMedia(in root: URL) {
        // Unknown/corrupt configuration must not turn into deletion authority.
        let retained: Set<String>
        do {
            let current = try readConfiguration(in: root)
            let previous = try readConfiguration(in: root, name: "previous.json")
            retained = Set([current?.content?.mediaGeneration, previous?.content?.mediaGeneration].compactMap { $0 })
        } catch { return }
        let mediaRoot = root.appendingPathComponent("Media", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(at: mediaRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for child in children {
            guard UUID(uuidString: child.lastPathComponent) != nil,
                  !retained.contains(child.lastPathComponent),
                  let attributes = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  attributes.isDirectory == true, attributes.isSymbolicLink != true else { continue }
            let lease = child.appendingPathComponent(".lease")
            guard (try? Data(contentsOf: lease)) == Self.leaseMarker else { continue }
            let descriptor = open(lease.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard descriptor >= 0 else { continue }
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                try? FileManager.default.removeItem(at: child)
                flock(descriptor, LOCK_UN)
            }
            close(descriptor)
        }
    }

    private nonisolated func isLegacyComponent(at url: URL) throws -> Bool {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return info?["CFBundleIdentifier"] as? String == Self.componentBundleIdentifier
    }

    private nonisolated func prepareStorage(request: UInt64) throws {
        guard hasBundledComponent else { throw Failure.message("App 内缺少系统墙纸组件，请使用完整的 App。") }
        guard injectedRootURL == nil else { try requests.check(request); return }
        let original = try rootURL()
        let shared = try ScreenSaverPaths.sharedRoot()
        try requests.commit(request) { try Self.migrateStorage(from: original, to: shared) }
    }

    nonisolated static func migrateStorage(from original: URL, to shared: URL) throws {
        let files = FileManager.default
        if original.standardizedFileURL.path == shared.standardizedFileURL.path {
            try files.createDirectory(at: shared, withIntermediateDirectories: true)
            return
        }
        if let target = try? files.destinationOfSymbolicLink(atPath: original.path) {
            guard URL(fileURLWithPath: target).standardizedFileURL.path == shared.standardizedFileURL.path else {
                throw CocoaError(.fileWriteFileExists)
            }
            try files.createDirectory(at: shared, withIntermediateDirectories: true)
            return
        }
        try files.createDirectory(at: original, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        try files.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let target = try? files.destinationOfSymbolicLink(atPath: shared.path) {
            guard URL(fileURLWithPath: target).standardizedFileURL.path == shared.standardizedFileURL.path else {
                throw CocoaError(.fileWriteFileExists)
            }
        } else {
            guard !files.fileExists(atPath: shared.path) else { throw CocoaError(.fileWriteFileExists) }
            try files.createSymbolicLink(at: shared, withDestinationURL: shared)
        }
        // Exchanging the directory with a self-pointing link makes both names
        // valid in one filesystem operation, preserving active video/lease FDs.
        if renameatx_np(AT_FDCWD, original.path, AT_FDCWD, shared.path, UInt32(RENAME_SWAP)) != 0 {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? files.removeItem(at: shared)
            throw error
        }
    }

    private nonisolated enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case let .message(message): message }
        }
    }

    /// One epoch protects copy, poster decoding and the final rename. Holding the
    /// lock only across commit makes cancellation linearizable without a broker.
    private nonisolated final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var revision: UInt64 = 0
        private var closed = false

        func current() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            return revision
        }
        func next() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            revision &+= 1
            return revision
        }
        func invalidate(close: Bool = false) {
            lock.lock()
            revision &+= 1
            closed = closed || close
            lock.unlock()
        }
        func isCurrent(_ request: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return !closed && revision == request
        }
        func check(_ request: UInt64) throws {
            guard isCurrent(request) else { throw CocoaError(.userCancelled) }
        }
        func commit<Value>(_ request: UInt64, _ body: () throws -> Value) throws -> Value {
            lock.lock()
            defer { lock.unlock() }
            guard !closed && revision == request else { throw CocoaError(.userCancelled) }
            return try body()
        }
    }
}
