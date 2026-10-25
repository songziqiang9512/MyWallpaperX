import AppKit
import Foundation
import SQLite3
import UniformTypeIdentifiers

/// The native file picker is the only replaced user-input boundary. Source
/// import workers, availability projection and relationship transactions run.
@MainActor final class RelocationOpenPanel {
    static var selectedURL: URL?
    static var response = NSApplication.ModalResponse.OK
    static var last: RelocationOpenPanel?
    var allowsMultipleSelection = true, canChooseFiles = false, canChooseDirectories = true
    var allowedContentTypes: [UTType] = []
    var title = "", prompt = "", message = ""
    var url: URL? { Self.selectedURL }
    var urls: [URL] { url.map { [$0] } ?? [] }
    init() { Self.last = self }
    func runModal() -> NSApplication.ModalResponse { Self.response }
    func beginSheetModal(for window: NSWindow, completionHandler: @escaping (NSApplication.ModalResponse) -> Void) { completionHandler(Self.response) }
}

@main struct WallpaperLibraryRelocationHarness {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(5)
        while !condition(), Date() < end { try await Task.sleep(nanoseconds: 5_000_000) }
        precondition(condition(), "Relocation did not reach the expected real source/Store boundary")
    }
    static func png(_ url: URL) throws {
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jh3sAAAAASUVORK5CYII=")!.write(to: url)
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var checks: [String: Bool] = [:]
        var serial = 0
        func setup(_ provider: WallpaperProvider, minimalLocator: Bool = false) async throws -> (UserCollectionsStore, UserCollectionsController, WallpaperLibraryWorkspace,
            WallpaperManager, SILService, WallpaperLibraryImportCoordinator, WallpaperReference, URL) {
            serial += 1
            let folder = root.appendingPathComponent("case-\(serial)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(provider == .videoLibrary ? "replacement.mp4" : "replacement.png")
            if provider == .videoLibrary { try Data("controlled video admission".utf8).write(to: file) } else { try Self.png(file) }
            let old = WallpaperReference(provider: provider, sourceID: "lost-\(serial)")
            let kind = provider == .videoLibrary ? WallpaperMediaKind.video : .image
            let store = UserCollectionsStore(url: folder.appendingPathComponent("relationships.sqlite3"))
            let initial = try await store.snapshot()
            let list = WallpaperPlaylist(name: "Original list", createdAt: Date(timeIntervalSince1970: 10), sidebarRank: 0)
            var payload = LibraryCollectionsImport(playlists: [list],
                members: [.init(playlistID: list.id, reference: old, position: 0, addedAt: Date(timeIntervalSince1970: 20))],
                favorites: [.init(reference: old, favoritedAt: Date(timeIntervalSince1970: 30))],
                recent: [.init(reference: old, lastSuccessfulUseAt: Date(timeIntervalSince1970: 40), commitSequence: 42, migrationOrder: nil)])
            if !minimalLocator {
                payload.locators = [.init(reference: old, locator: .init(path: folder.appendingPathComponent("missing").path, titleHint: "Original title", mediaKind: kind))]
            }
            let snapshot = try await store.installMigration(payload, manifestID: "relocation-fixture", expectedEpoch: initial.resetEpoch)
            let controller = UserCollectionsController(store: store, snapshot: snapshot)
            let workspace = WallpaperLibraryWorkspace(controller)
            workspace.contentValues[old] = try WallpaperLibraryQuery.resolve([old], catalog: .init(), relationships: snapshot)[0]
            let manager = WallpaperManager(), images = SILService(folder.appendingPathComponent("images.json"))
            let coordinator = WallpaperLibraryImportCoordinator(workspace: workspace, manager: manager, images: images, hostWindow: { nil })
            RelocationOpenPanel.selectedURL = file; RelocationOpenPanel.response = .OK
            return (store, controller, workspace, manager, images, coordinator, old, file)
        }
        for provider in [WallpaperProvider.videoLibrary, .staticImageLibrary] {
            let (_, controller, workspace, _, _, coordinator, old, _) = try await setup(provider, minimalLocator: true)
            precondition(workspace.contentValues[old]?.kind == .unknown && controller.snapshot.locators.isEmpty)
            coordinator.chooseReplacement(for: old)
            try await wait { workspace.catalog.refreshes == 1 }
            let actual = controller.snapshot
            checks["\(provider.rawValue)-missing-locator-uses-provider-for-explicit-file-repair"] = actual.aliases.count == 1
                && actual.aliases[0].alias == old && actual.aliases[0].canonical.provider == provider
                && actual.locators.count == 1
                && actual.locators[0].locator.mediaKind == (provider == .videoLibrary ? .video : .image)
        }
        for provider in [WallpaperProvider.videoLibrary, .staticImageLibrary] {
            let (_, controller, workspace, manager, images, coordinator, old, file) = try await setup(provider)
            let before = controller.snapshot
            coordinator.chooseReplacement(for: old)
            try await wait { workspace.catalog.refreshes == 1 }
            let state = controller.snapshot, alias = state.aliases.first!
            let new = alias.canonical
            checks["\(provider.rawValue)-native-choice-imports-same-provider-and-explicit-proof"] = alias.alias == old
                && alias.proof == .explicitUserRelocation && new.provider == provider && new != old
                && RelocationOpenPanel.last?.allowsMultipleSelection == false && RelocationOpenPanel.last?.canChooseDirectories == false
                && RelocationOpenPanel.last?.prompt == "关联此文件"
            checks["\(provider.rawValue)-atomic-repair-keeps-playlist-favorite-and-recent-order"] = state.playlists.map(\.id) == before.playlists.map(\.id)
                && state.members.count == 1 && state.members[0].reference == new && state.members[0].position == 0
                && state.members[0].addedAt == before.members[0].addedAt && state.favorites.count == 1
                && state.favorites[0].reference == new && state.favorites[0].favoritedAt == before.favorites[0].favoritedAt
                && state.recent.count == 1 && state.recent[0].reference == new && state.recent[0].commitSequence == 42
            let selectedPath = Data(file.resolvingSymlinksInPath().standardizedFileURL.path.utf8)
            let storedPath = state.locators[0].locator.path.map { Data(URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path.utf8) }
            checks["\(provider.rawValue)-target-locator-replaces-old-missing-locator"] = state.locators.count == 1
                && state.locators[0].reference == new && storedPath == selectedPath
            let actual: [WallpaperContentItem]
            if provider == .videoLibrary {
                actual = await manager.libraryContentItems(from: manager.wallpapers, reusing: [], refreshAvailability: true)
            } else { actual = await images.libraryContentItems(from: images.wallpapers, reusing: [], refreshAvailability: true) }
            let catalog = provider == .videoLibrary ? WallpaperLibraryCatalog(videos: actual) : WallpaperLibraryCatalog(images: actual)
            let resolved = try WallpaperLibraryQuery.resolve([old], catalog: catalog, relationships: state)[0]
            checks["\(provider.rawValue)-old-reference-resolves-through-actual-source-projection"] = resolved.reference == new
                && resolved.publishedAvailability.isAvailable && resolved.capabilities.contains(.play)
                && manager.automaticPlays == 0 && manager.indexAcknowledgements == (provider == .videoLibrary ? 1 : 0)
        }
        for provider in [WallpaperProvider.videoLibrary, .staticImageLibrary] {
            let (_, controller, workspace, manager, images, coordinator, old, file) = try await setup(provider)
            let neighborFolder = file.deletingLastPathComponent().appendingPathComponent("neighbor", isDirectory: true)
            try FileManager.default.createDirectory(at: neighborFolder, withIntermediateDirectories: true)
            let neighbor = neighborFolder.appendingPathComponent(file.lastPathComponent)
            if provider == .videoLibrary { try Data("same name, distinct file".utf8).write(to: neighbor) } else { try png(neighbor) }
            let neighborReference: WallpaperReference
            if provider == .videoLibrary {
                let existing = VideoWallpaper(title: file.lastPathComponent, path: manager.normalizedPath(neighbor.path))
                manager.wallpapers = [existing]
                neighborReference = .init(provider: provider, sourceID: existing.id)
            } else {
                let existing = SILWallpaper(path: neighbor.path)
                images.wallpapers = [existing]; images.save()
                neighborReference = .init(provider: provider, sourceID: existing.id)
            }
            coordinator.chooseReplacement(for: old)
            try await wait { workspace.catalog.refreshes == 1 }
            let alias = controller.snapshot.aliases.first!
            let targetPath = controller.snapshot.locators.first { $0.reference == alias.canonical }!.locator.path!
            checks["\(provider.rawValue)-same-name-neighbor-is-never-guessed-as-replacement"] = alias.canonical != neighborReference
                && Data(URL(fileURLWithPath: targetPath).resolvingSymlinksInPath().standardizedFileURL.path.utf8)
                    == Data(file.resolvingSymlinksInPath().standardizedFileURL.path.utf8)
                && (provider == .videoLibrary ? manager.wallpapers.count : images.wallpapers.count) == 2
        }
        do {
            let (_, controller, workspace, manager, images, coordinator, old, _) = try await setup(.staticImageLibrary)
            let before = controller.snapshot
            RelocationOpenPanel.response = .cancel
            coordinator.chooseReplacement(for: old)
            try await Task.sleep(nanoseconds: 80_000_000)
            checks["cancelled-file-panel-leaves-source-and-relationships-unchanged"] = controller.snapshot == before
                && manager.wallpapers.isEmpty && images.wallpapers.isEmpty && workspace.catalog.refreshes == 0
            workspace.presentation.canEditCollections = false
            let panel = RelocationOpenPanel.last
            RelocationOpenPanel.response = .OK
            coordinator.chooseReplacement(for: old)
            checks["readonly-recovery-does-not-open-relocation-panel"] = RelocationOpenPanel.last === panel && controller.snapshot == before
        }
        do {
            let (_, controller, workspace, manager, _, coordinator, old, _) = try await setup(.videoLibrary)
            let before = controller.snapshot, alerts = presentedImportAlerts.count
            RelocationOpenPanel.selectedURL = URL(fileURLWithPath: "/controlled-missing-replacement.mp4")
            coordinator.chooseReplacement(for: old)
            try await wait { presentedImportAlerts.count > alerts }
            checks["failed-original-import-never-publishes-alias-or-phantom-success"] = controller.snapshot == before
                && manager.wallpapers.isEmpty && workspace.catalog.refreshes == 0 && presentedImportAlerts.last?.0 == "文件未关联"
        }
        do {
            let (_, controller, workspace, manager, _, coordinator, old, _) = try await setup(.videoLibrary)
            let before = controller.snapshot, alerts = presentedImportAlerts.count
            manager.indexAcknowledgementFails = true
            coordinator.chooseReplacement(for: old)
            try await wait { presentedImportAlerts.count > alerts }
            checks["video-source-durability-refusal-keeps-import-but-does-not-link"] = controller.snapshot == before
                && manager.wallpapers.count == 1 && manager.indexAcknowledgements == 1 && workspace.catalog.refreshes == 0
        }
        do {
            let (_, controller, workspace, _, images, coordinator, old, _) = try await setup(.staticImageLibrary)
            let before = controller.snapshot, alerts = presentedImportAlerts.count
            ImageImportProbe.shared.failNextSynchronization()
            coordinator.chooseReplacement(for: old)
            try await wait { presentedImportAlerts.count > alerts }
            let actual = try JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: images.persistenceURL))
            checks["image-write-after-ack-failure-keeps-readable-source-without-any-relationship-success"] = actual.count == 1
                && images.wallpapers == actual && controller.snapshot == before && workspace.catalog.refreshes == 0
                && presentedImportAlerts.last?.1.contains("未获保存确认") == true
        }
        do {
            let (_, controller, workspace, manager, _, coordinator, old, _) = try await setup(.videoLibrary)
            let before = controller.snapshot
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            coordinator.chooseReplacement(for: old)
            RelocationOpenPanel.response = .cancel
            coordinator.chooseReplacement(for: old)
            hold.1.signal()
            try await wait { manager.wallpapers.count == 1 }
            try await Task.sleep(nanoseconds: 60_000_000)
            checks["newer-panel-cancellation-revokes-older-import-repair-not-its-source"] = controller.snapshot == before
                && manager.indexAcknowledgements == 0 && workspace.catalog.refreshes == 0
        }
        do {
            let (_, controller, workspace, manager, _, coordinator, old, _) = try await setup(.videoLibrary)
            let before = controller.snapshot
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            coordinator.chooseReplacement(for: old)
            workspace.presentation.page = .favorites
            hold.1.signal()
            try await wait { manager.wallpapers.count == 1 }
            try await Task.sleep(nanoseconds: 60_000_000)
            checks["page-change-does-not-rebind-or-hijack-a-later-selection"] = controller.snapshot == before
                && manager.indexAcknowledgements == 0 && workspace.catalog.refreshes == 0
        }
        do {
            let (_, controller, workspace, manager, _, coordinator, old, file) = try await setup(.videoLibrary)
            let before = controller.snapshot
            let image = file.deletingLastPathComponent().appendingPathComponent("wrong-provider.png")
            try png(image); RelocationOpenPanel.selectedURL = image
            coordinator.chooseReplacement(for: old)
            try await Task.sleep(nanoseconds: 60_000_000)
            checks["wrong-provider-file-choice-does-not-start-import-or-mutate-relationships"] = controller.snapshot == before
                && manager.wallpapers.isEmpty && workspace.catalog.refreshes == 0
        }
        do {
            let (_, controller, workspace, manager, images, coordinator, old, _) = try await setup(.videoLibrary)
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            coordinator.chooseReplacement(for: old)
            try await controller.reset(); manager.resetForAudit(); images.resetForAudit()
            let afterReset = controller.snapshot
            hold.1.signal(); try await Task.sleep(nanoseconds: 150_000_000)
            checks["reset-revokes-old-panel-import-and-relationship-commit"] = controller.snapshot == afterReset
                && manager.wallpapers.isEmpty && workspace.catalog.refreshes == 0
        }
        do {
            let (_, controller, workspace, manager, _, coordinator, old, file) = try await setup(.videoLibrary)
            let before = controller.snapshot, alerts = presentedImportAlerts.count
            let originalURL = file.deletingLastPathComponent().appendingPathComponent("original-restored.mp4")
            manager.wallpapers = [VideoWallpaper(id: old.sourceID, title: "Original", path: originalURL.path)]
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            coordinator.chooseReplacement(for: old)
            try Data("restored original".utf8).write(to: originalURL)
            hold.1.signal()
            try await wait { presentedImportAlerts.count > alerts }
            checks["actual-owner-recovered-original-refuses-unnecessary-rebinding"] = controller.snapshot == before
                && manager.wallpapers.count == 2 && manager.indexAcknowledgements == 0 && workspace.catalog.refreshes == 0
        }
        // The transaction is also the final guard after FIFO queueing. It
        // validates canonical roots rather than trusting the earlier panel.
        for scenario in ["source-alias", "target-alias", "cross-provider", "no-relation", "unavailable-target", "rollback"] {
            let (store, controller, _, _, _, _, old, file) = try await setup(.videoLibrary)
            let target = WallpaperReference(provider: .videoLibrary, sourceID: "new-" + scenario)
            let third = WallpaperReference(provider: .videoLibrary, sourceID: "third")
            let targetItem = WallpaperOrganizationItem(reference: scenario == "cross-provider" ? .init(provider: .staticImageLibrary, sourceID: "new") : target,
                locator: .init(path: file.path, mediaKind: .video), isPublishedLocally: true, isAvailable: scenario != "unavailable-target")
            if scenario == "source-alias" { _ = try await controller.perform(.linkAlias(.init(alias: old, canonical: third, proof: .restoredSourceRecord), Date())) }
            if scenario == "target-alias" { _ = try await controller.perform(.linkAlias(.init(alias: target, canonical: third, proof: .restoredSourceRecord), Date())) }
            if scenario == "no-relation" {
                _ = try await controller.perform([.removeMembers(controller.snapshot.playlists[0].id, [old], Date()),
                    .setFavorite(.init(reference: old, locator: .init(), isPublishedLocally: false, isAvailable: false), false, Date()), .clearRecent])
            }
            if scenario == "rollback" {
                var db: OpaquePointer?
                precondition(sqlite3_open(file.deletingLastPathComponent().appendingPathComponent("relationships.sqlite3").path, &db) == SQLITE_OK)
                defer { sqlite3_close(db) }
                precondition(sqlite3_exec(db, "CREATE TRIGGER refuse_relocation BEFORE INSERT ON aliases BEGIN SELECT RAISE(ABORT,'controlled relocation write failure'); END", nil, nil, nil) == SQLITE_OK)
            }
            let before = controller.snapshot
            var refused = false
            do { _ = try await controller.perform(.relocateLocalReference(old, targetItem, Date()), expectedEpoch: before.resetEpoch) }
            catch { refused = true }
            let persisted = try await store.snapshot()
            checks["conditional-sql-\(scenario)-preserves-complete-prior-relationships"] = refused
                && controller.snapshot == before && persisted == before
        }
        do {
            let (_, controller, _, _, _, _, old, file) = try await setup(.staticImageLibrary)
            let item = WallpaperOrganizationItem(reference: old, locator: .init(path: file.path, mediaKind: .image), isPublishedLocally: true, isAvailable: true)
            _ = try await controller.perform(.relocateLocalReference(old, item, Date()))
            checks["same-original-id-restoration-reuses-identity-without-self-alias"] = controller.snapshot.aliases.isEmpty
                && controller.snapshot.members[0].reference == old && controller.snapshot.locators[0].locator.path == file.path
        }
        do {
            let (store, controller, _, _, _, _, old, file) = try await setup(.videoLibrary)
            let target = WallpaperReference(provider: .videoLibrary, sourceID: "already-organized-target")
            let item = WallpaperOrganizationItem(reference: target,
                locator: .init(path: file.path, mediaKind: .video), isPublishedLocally: true, isAvailable: true)
            let playlist = controller.snapshot.playlists[0].id
            _ = try await controller.perform([.addMembers(playlist, [item], Date(timeIntervalSince1970: 50)),
                .setFavorite(item, true, Date(timeIntervalSince1970: 60))])
            let before = controller.snapshot.organizationState
            _ = try await controller.perform(.relocateLocalReference(old, item, Date(timeIntervalSince1970: 70)))
            let after = controller.snapshot
            checks["existing-target-relationships-merge-once-with-earliest-position-and-dates"] = after.members.count == 1
                && after.members[0].reference == target && after.members[0].position == 0
                && after.members[0].addedAt == Date(timeIntervalSince1970: 20)
                && after.favorites.count == 1 && after.favorites[0].reference == target
                && after.favorites[0].favoritedAt == Date(timeIntervalSince1970: 30)
                && after.recent.count == 1 && after.recent[0].reference == target
            var refused = false
            do { _ = try await controller.perform(.restoreOrganization(expected: before, replacement: before)) }
            catch { refused = true }
            let persisted = try await store.snapshot()
            checks["old-organization-undo-cannot-write-aliased-reference-back"] = refused
                && controller.snapshot == after && persisted == after
            let stale = WallpaperOrganizationItem(reference: old, locator: .init(), isPublishedLocally: false, isAvailable: false)
            _ = try await controller.perform(.setFavorite(stale, false, Date()))
            checks["fixed-old-reference-metadata-action-resolves-current-canonical-target"] = controller.snapshot.favorites.isEmpty
                && controller.snapshot.members[0].reference == target && controller.snapshot.aliases == after.aliases
        }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
