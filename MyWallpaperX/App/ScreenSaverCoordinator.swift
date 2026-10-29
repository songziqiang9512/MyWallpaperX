import Combine
import Foundation

/// App assembly for explicit screen-saver commands. It resolves existing source
/// inputs; ScreenSaverIntegration remains the only deployment/installation owner.
@MainActor
public final class ScreenSaverCoordinator: ObservableObject {
    static let shared = ScreenSaverCoordinator()
    @Published private(set) var isPreparing = false
    @Published private(set) var errorMessage: String?
    private weak var workspace: WallpaperLibraryWorkspace?
    private let manager = WallpaperManager.shared
    private let integration = ScreenSaverIntegration.shared
    private var preparation: Task<Void, Never>?
    private var epoch: UInt64 = 0

    private init() {}

    func configure(workspace: WallpaperLibraryWorkspace) { self.workspace = workspace }

    func save(_ preferences: ScreenSaverPreferences, optionsOnly: Bool = false,
              completion: @escaping @MainActor (Result<Void, Error>) -> Void = { _ in }) {
        guard workspace?.presentation.canEditCollections == true else {
            let error = Failure.message("资料库正在同步或重置，请稍后再保存屏保。")
            errorMessage = error.localizedDescription
            completion(.failure(error))
            return
        }
        let previous = manager.settings.screenSaver
        var accepted = preferences
        if accepted.mode == .followDesktop {
            let currentVideo = videoReference(manager.libraryPlaybackSequence.committed?.reference)
            // Keep an options-only target even after its library source was
            // removed. This preserves intent; reuse is checked after install.
            let keepsPublishedReference = optionsOnly && previous.mode == accepted.mode
                && previous.reference == accepted.reference && accepted.reference != nil
                && integration.configuration?.content?.sourceIdentity == accepted.reference?.storageKey
            accepted.reference = currentVideo
                ?? (keepsPublishedReference ? accepted.reference : videoReference(accepted.reference))
        }
        cancel()
        let request = epoch
        do {
            // Acceptance persists before preparation. A failed deployment keeps
            // this target intent while Integration displays the actual old one.
            try persist(accepted)
        } catch {
            errorMessage = error.localizedDescription
            completion(.failure(error))
            return
        }
        isPreparing = true
        preparation = Task { [weak self] in
            guard let self else { completion(.failure(CocoaError(.userCancelled))); return }
            do {
                try await self.install(request: request)
                // The serial install barrier has delivered every earlier disk
                // publication before this association is consumed.
                let reuseMedia = optionsOnly && previous.mode == accepted.mode && previous.reference == accepted.reference
                    && accepted.reference != nil
                    && self.integration.configuration?.content?.sourceIdentity == accepted.reference?.storageKey
                if reuseMedia {
                    _ = try await self.updateOptions(accepted, request: request)
                } else {
                    guard let reference = accepted.reference else {
                        throw Failure.message(accepted.mode == .followDesktop
                            ? "还没有可跟随的视频，请先选择或播放一个本地视频。"
                            : "请选择一个本地视频。")
                    }
                    let resolved = try self.resolveInput(reference)
                    defer { withExtendedLifetime(resolved) {} }
                    try self.check(request)
                    _ = try await self.publish(resolved.input, preferences: accepted, request: request)
                }
                try self.check(request)
                self.isPreparing = false
                self.preparation = nil
                completion(.success(()))
            } catch {
                let current = self.epoch == request && !Task.isCancelled
                let reported: Error = current ? error : CocoaError(.userCancelled)
                if self.epoch == request {
                    self.isPreparing = false
                    self.preparation = nil
                }
                if current { self.errorMessage = reported.localizedDescription }
                completion(.failure(reported))
            }
        }
    }

    /// Only a successful Video desktop commit advances the remembered video.
    /// Other desktop kinds leave the last video and its publication unchanged.
    func onDesktopCommitted(_ reference: WallpaperReference) {
        var preferences = manager.settings.screenSaver
        guard preferences.mode == .followDesktop, let reference = videoReference(reference) else { return }
        preferences.reference = reference
        save(preferences)
    }

    /// Cancelling pending work retains the accepted preference for retry. App
    /// exit uses this too, so it must not erase the user's persistent intent.
    func cancel() {
        epoch &+= 1
        preparation?.cancel()
        preparation = nil
        integration.cancel()
        isPreparing = false
        errorMessage = nil
    }

    func clear(uninstall: Bool = false,
               completion: @escaping @MainActor (Result<Void, Error>) -> Void = { _ in }) {
        cancel()
        let request = epoch
        var preferences = manager.settings.screenSaver
        preferences.mode = .fixed
        preferences.reference = nil
        do { try persist(preferences) }
        catch { errorMessage = error.localizedDescription; completion(.failure(error)); return }
        let finished: @MainActor (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self, self.epoch == request else {
                completion(.failure(CocoaError(.userCancelled)))
                return
            }
            if case let .failure(error) = result { self.errorMessage = error.localizedDescription }
            completion(result)
        }
        if uninstall { integration.uninstall(completion: finished) }
        else { integration.clear { finished($0.map { _ in () }) } }
    }

    /// The configuration thumbnail comes from the committed content only.
    func publishedPosterURL() -> URL? {
        guard let configuration = integration.configuration, let content = configuration.content,
              let root = integration.configurationRoot,
              let media = try? ScreenSaverPaths.mediaRoot(in: root, generation: content.mediaGeneration) else { return nil }
        return try? ScreenSaverPaths.resource(content.posterRelativePath, in: media)
    }

    private func persist(_ preferences: ScreenSaverPreferences) throws {
        guard manager.allowsLibraryMutation else {
            throw Failure.message(manager.migrationRecoveryMessage ?? "当前资料库需要恢复，暂不能修改屏保设置。")
        }
        guard manager.settings.screenSaver != preferences else { return }
        var settings = manager.settings
        settings.screenSaver = preferences
        try manager.persistSettingsNow(settings)
        manager.settings = settings
    }

    private func check(_ request: UInt64) throws {
        guard epoch == request, !Task.isCancelled,
              workspace?.presentation.canEditCollections == true else { throw CocoaError(.userCancelled) }
    }

    private func install(request: UInt64) async throws {
        try check(request)
        try await withCheckedThrowingContinuation { continuation in
            integration.installIfNeeded { continuation.resume(with: $0) }
        }
        try check(request)
    }

    private func publish(_ input: ScreenSaverIntegration.PublicationInput, preferences: ScreenSaverPreferences,
                         request: UInt64) async throws -> ScreenSaverConfiguration {
        try check(request)
        return try await withCheckedThrowingContinuation { continuation in
            integration.publish(input, fillMode: preferences.fillMode, playsOnBattery: preferences.playsOnBattery) {
                continuation.resume(with: $0)
            }
        }
    }

    private func updateOptions(_ preferences: ScreenSaverPreferences, request: UInt64) async throws -> ScreenSaverConfiguration {
        try check(request)
        return try await withCheckedThrowingContinuation { continuation in
            integration.updateOptions(fillMode: preferences.fillMode, playsOnBattery: preferences.playsOnBattery) {
                continuation.resume(with: $0)
            }
        }
    }

    private final class ResolvedInput {
        let input: ScreenSaverIntegration.PublicationInput
        private let resourceLifetime: AnyObject?
        private let scopedURLs: [URL]

        init(input: ScreenSaverIntegration.PublicationInput, resourceLifetime: AnyObject?, scopedURLs: [URL]) {
            self.input = input; self.resourceLifetime = resourceLifetime; self.scopedURLs = scopedURLs
        }

        isolated deinit { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
    }

    private func videoReference(_ reference: WallpaperReference?) -> WallpaperReference? {
        guard let reference, let workspace,
              let content = try? workspace.content(for: reference), content.kind == .video else { return nil }
        return content.reference
    }

    private func resolveInput(_ reference: WallpaperReference) throws -> ResolvedInput {
        guard let workspace else { throw Failure.message("壁纸库尚未就绪。") }
        let content = try workspace.content(for: reference)
        guard content.kind == .video else { throw Failure.message("屏保仅支持本地视频，请重新选择。") }
        guard content.publishedAvailability.isPublishedLocally, content.publishedAvailability.isAvailable else {
            throw Failure.message("这个视频当前没有可用的本地文件，请先定位文件或完成下载。")
        }
        let url: URL
        let lifetime: PlaybackResourceLifetime?
        let owner = content.providerReference
        if owner.provider == .steamWorkshop {
            let service = SteamWorkshopService.shared
            guard let record = service.latestDownloadRecord(for: owner.sourceID),
                  record.id.utf8.elementsEqual(owner.sourceID.utf8), record.status == .ready,
                  record.contentType == .video, let video = record.videoURL else {
                throw Failure.message("创意工坊视频来源已变化或不可用，请刷新后重试。")
            }
            url = video
            lifetime = try service.libraryVersionLifetime(recordID: record.id, consumedRoots: [record.folderURL, video])
        } else {
            guard let path = content.locator.path else { throw Failure.message("本地视频位置不可用。") }
            url = URL(fileURLWithPath: path)
            lifetime = nil
        }
        let scopes = url.startAccessingSecurityScopedResource() ? [url] : []
        return .init(input: .init(videoURL: url, title: content.title,
                                 revision: content.metadata.resourceRevision, sourceIdentity: content.reference.storageKey),
                     resourceLifetime: lifetime, scopedURLs: scopes)
    }

    private nonisolated enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case let .message(message): message } }
    }
}
