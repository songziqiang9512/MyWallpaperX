import AppKit
import Combine

nonisolated enum PlaylistOrganizationAction: Equatable, Sendable {
    case create, open(UUID), rename(UUID), duplicate(UUID), delete(UUID)
}

/// Shared sheet/command rules for directory, sidebar and content menus.
/// It holds no source selection, playback state or independent relationship copy.
@MainActor final class PlaylistOrganizationActions {
    private let collections: UserCollectionsController
    private let hostWindow: () -> NSWindow?
    var onOpen: ((UUID) -> Void)?
    var onDidEdit: ((UUID, Bool) -> Void)?
    var onCreatedFromMembers: ((UUID) -> Void)?
    var onWillPresent: (() -> Void)?
    var coverPreview: ((UUID) -> NSImage?)?
    var permitsEditing: () -> Bool = { true }
    var availabilityChanges: AnyPublisher<Void, Never>?
    private var editor: WallpaperPlaylistEditorController?

    init(collections: UserCollectionsController, hostWindow: @escaping () -> NSWindow?) {
        self.collections = collections
        self.hostWindow = hostWindow
    }

    func handle(_ action: PlaylistOrganizationAction) {
        switch action {
        case .create: create()
        case .open(let id): if collections.snapshot.playlists.contains(where: { $0.id == id }) { onOpen?(id) }
        case .rename(let id): rename(id)
        case .duplicate(let id):
            let epoch = collections.snapshot.resetEpoch
            run(epoch: epoch) { try await self.collections.duplicatePlaylist(id) }
        case .delete(let id): delete(id)
        }
    }

    func create(members: [WallpaperOrganizationItem] = [], completion: (() -> Void)? = nil) {
        showEditor(playlist: nil, members: members, completion: completion)
    }

    func rename(_ id: UUID) {
        guard let playlist = collections.snapshot.playlists.first(where: { $0.id == id }) else { return }
        showEditor(playlist: playlist, members: [])
    }

    private func showEditor(playlist: WallpaperPlaylist?, members: [WallpaperOrganizationItem], completion: (() -> Void)? = nil) {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: hostWindow()), editor == nil, !collections.isResetting, permitsEditing() else { return }
        let sheet = WallpaperPlaylistEditorController(collections: collections, playlist: playlist, members: members,
            automaticImage: playlist.flatMap { coverPreview?($0.id) },
            permitsEditing: permitsEditing, availabilityChanges: availabilityChanges, hostWindow: hostWindow)
        editor = sheet
        sheet.onClose = { [weak self] in self?.editor = nil }
        sheet.onSaved = { [weak self] id in
            guard let self else { return }
            completion?()
            if playlist != nil { self.onDidEdit?(id, false) }
            else if members.isEmpty { self.onOpen?(id) }
            else { self.onCreatedFromMembers?(id) }
        }
        onWillPresent?()
        sheet.show()
    }

    func close() {
        // Closing the host retires the draft UI. An already admitted Store
        // operation retains its original epoch and may finish without navigation.
        editor?.close()
        editor = nil
    }

    func delete(_ id: UUID) {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: hostWindow()), permitsEditing(), let playlist = collections.snapshot.playlists.first(where: { $0.id == id }) else { return }
        let epoch = collections.snapshot.resetEpoch
        let count = collections.snapshot.members.filter { $0.playlistID == id }.count
        let alert = makeAppAlert(title: "删除“\(playlist.name)”？",
            message: "仅移除此列表，保留其中 \(count) 张壁纸和其他列表。",
            style: .warning, buttons: ["移除", "取消"])
        presentAppAlert(alert, in: hostWindow()) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.run(epoch: epoch, operation: { try await self.collections.perform(.deletePlaylist(id), undoName: "删除列表") }) { _ in self.onDidEdit?(id, true) }
        }
    }

    func reorder(_ ids: [UUID], completion: @escaping (Result<Int64, Error>) -> Void) {
        let epoch = collections.snapshot.resetEpoch
        guard permitsEditing(), !collections.isResetting else {
            completion(.failure(UserCollectionsError.staleResetEpoch)); return
        }
        let current = collections.snapshot.playlists.sorted { $0.sidebarRank < $1.sidebarRank }.map(\.id)
        guard ids.count == current.count, Set(ids) == Set(current) else {
            completion(.failure(UserCollectionsError.invalidOrder)); return
        }
        // A cancelled gesture or returning to the original gap creates no write
        // and no Undo transaction. The controller remains the sole store owner.
        guard ids != current else { completion(.success(collections.snapshot.revision)); return }
        Task { @MainActor in
            do {
                let committed = try await collections.perform(.reorderPlaylists(ids), undoName: "调整列表顺序", expectedEpoch: epoch)
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else {
                    throw UserCollectionsError.staleResetEpoch
                }
                completion(.success(committed.revision))
            } catch {
                completion(.failure(error))
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                let alert = makeAppAlert(title: "播放列表操作未完成", message: error.localizedDescription, buttons: ["好"])
                presentAppAlert(alert, in: hostWindow())
            }
        }
    }

    func add(_ items: [WallpaperOrganizationItem], to id: UUID, completion: (() -> Void)? = nil) {
        let epoch = collections.snapshot.resetEpoch
        run(epoch: epoch, operation: { try await self.collections.perform(.addMembers(id, items, Date()), undoName: "添加到列表") }) { _ in
            completion?()
            self.onDidEdit?(id, false)
        }
    }

    private func run<T>(epoch: UUID, operation: @escaping @MainActor () async throws -> T,
                        completion: ((T) -> Void)? = nil) {
        Task { @MainActor in
            do {
                // A sheet opened before a reinstall/reset cannot create data in
                // the new epoch. Controller performs its own serialized check.
                guard permitsEditing(), collections.snapshot.resetEpoch == epoch, !collections.isResetting else { throw UserCollectionsError.staleResetEpoch }
                let value = try await operation()
                // Reset can be accepted after the store commits but before this
                // continuation resumes. Never let that old success navigate.
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { throw UserCollectionsError.staleResetEpoch }
                guard permitsEditing() else { return }
                completion?(value)
            } catch {
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                let alert = makeAppAlert(title: "播放列表操作未完成", message: error.localizedDescription, buttons: ["好"])
                presentAppAlert(alert, in: hostWindow())
            }
        }
    }

}
