import AppKit
import UniformTypeIdentifiers

/// Organizes only the actual successful receipts of the existing importers.
/// A page change cannot redirect a command to a different list or favorite set.
@MainActor final class WallpaperLibraryImportCoordinator {
    private let workspace: WallpaperLibraryWorkspace
    private let manager: WallpaperManager
    private let images: SILService
    private let hostWindow: () -> NSWindow?
    private var relocationGeneration: UInt64 = 0

    init(workspace: WallpaperLibraryWorkspace, manager: WallpaperManager, images: SILService,
         hostWindow: @escaping () -> NSWindow?) {
        self.workspace = workspace; self.manager = manager; self.images = images; self.hostWindow = hostWindow
    }

    static func permitsImport(to page: WallpaperLibraryPage) -> Bool {
        switch page {
        case .videos, .images, .recent, .favorites, .playlist: return true
        default: return false
        }
    }

    func chooseFiles(to page: WallpaperLibraryPage) {
        guard Self.permitsImport(to: page), workspace.presentation.canEditCollections else { return }
        let epoch = workspace.relationships.resetEpoch
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = page != .videos && page != .recent
        panel.allowedContentTypes = page == .images ? SILService.allowedUTTypes
            : page == .videos || page == .recent ? [.movie, .video, .mpeg4Movie, .quickTimeMovie]
            : [.movie, .video, .image]
        panel.message = panel.canChooseDirectories ? "文件夹仅递归导入图片；视频请直接选择文件。" : ""
        panel.title = page == .images ? "导入图片" : page == .videos || page == .recent ? "导入视频" : "导入壁纸"
        let accept: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, self.workspace.relationships.resetEpoch == epoch else { return }
            self.importFiles(panel.urls, to: page)
        }
        if let window = hostWindow() { panel.beginSheetModal(for: window, completionHandler: accept) }
        else { accept(panel.runModal()) }
    }

    func importFiles(_ urls: [URL], to page: WallpaperLibraryPage) {
        guard Self.permitsImport(to: page), workspace.presentation.canEditCollections,
              let collections = workspace.collections, !urls.isEmpty else { return }
        let epoch = collections.snapshot.resetEpoch
        let acceptsImages = page != .videos && page != .recent
        var imageURLs: [URL] = [], videoURLs: [URL] = []
        var rejected: [WallpaperSourceImportResult.Item] = []
        for url in urls where url.isFileURL {
            let type = UTType(filenameExtension: url.pathExtension)
            let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if acceptsImages, type?.conforms(to: .image) == true || directory {
                imageURLs.append(url)
            } else if page != .images, type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
                videoURLs.append(url)
            } else {
                rejected.append(.init(sourceURL: url, disposition: .failed, organizationItem: nil, failureMessage: "该页面不接受此文件类型"))
            }
        }
        let batch = Batch(order: urls, remaining: (imageURLs.isEmpty ? 0 : 1) + (videoURLs.isEmpty ? 0 : 1),
                          admittedRelationships: collections.snapshot)
        batch.results = [WallpaperSourceImportResult(items: rejected)]
        guard batch.remaining > 0 else {
            finish(batch, page: page, collections: collections, epoch: epoch)
            return
        }
        let accept: (WallpaperSourceImportResult) -> Void = { [self] result in
            guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
            batch.results.append(result)
            batch.remaining -= 1
            guard batch.remaining == 0 else { return }
            self.finish(batch, page: page, collections: collections, epoch: epoch)
        }
        if !videoURLs.isEmpty {
            manager.processImportedVideos(from: videoURLs, presentingIn: hostWindow(), context: .library,
                presentsSummary: false, completion: accept)
        }
        if !imageURLs.isEmpty {
            images.importImages(from: imageURLs, presentingIn: hostWindow(), presentsSummary: false, completion: accept)
        }
    }

    static func canRelocate(_ content: WallpaperContentItem, relationships: UserCollectionsSnapshot) -> Bool {
        guard content.publishedAvailability == .unavailable, content.reference == content.providerReference else { return false }
        switch (content.reference.provider, content.kind) {
        case (.videoLibrary, .video), (.videoLibrary, .unknown),
             (.staticImageLibrary, .image), (.staticImageLibrary, .unknown): break
        default: return false
        }
        let references = relationships.members.map(\.reference) + relationships.favorites.map(\.reference) + relationships.recent.map(\.reference)
        guard let resolved = try? WallpaperLibraryQuery.canonicalReferences(Set(references), relationships: relationships) else { return false }
        return references.contains { resolved[$0] == content.reference }
    }

    /// Only an explicit single-file choice can repair a retained local
    /// relationship. Neither a filename match nor a new import claims it.
    func chooseReplacement(for reference: WallpaperReference) {
        guard workspace.presentation.canEditCollections, workspace.collections != nil,
              let content = try? workspace.content(for: reference), content.reference == reference,
              Self.canRelocate(content, relationships: workspace.relationships) else { return }
        relocationGeneration &+= 1
        let generation = relocationGeneration, epoch = workspace.relationships.resetEpoch, page = workspace.presentation.page
        let admittedRelationships = workspace.relationships
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = reference.provider == .staticImageLibrary ? SILService.allowedUTTypes
            : [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.title = "重新定位壁纸文件"
        panel.prompt = "关联此文件"
        panel.message = "请选择这张壁纸的新位置；将保留原播放列表、特别喜爱和最近使用。不会移动或删除文件。"
        let accept: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.importReplacement(url, for: reference, epoch: epoch, generation: generation, page: page,
                                   admittedRelationships: admittedRelationships)
        }
        if let window = hostWindow() { panel.beginSheetModal(for: window, completionHandler: accept) }
        else { accept(panel.runModal()) }
    }

    private func importReplacement(_ url: URL, for reference: WallpaperReference, epoch: UUID, generation: UInt64,
                                   page: WallpaperLibraryPage, admittedRelationships: UserCollectionsSnapshot) {
        guard workspace.presentation.canEditCollections, workspace.relationships.resetEpoch == epoch,
              relocationGeneration == generation, workspace.presentation.page == page, url.isFileURL,
              let latest = try? workspace.content(for: reference), latest.reference == reference,
              Self.canRelocate(latest, relationships: workspace.relationships) else { return }
        let type = UTType(filenameExtension: url.pathExtension)
        guard reference.provider == .staticImageLibrary ? SILService.isSupportedImage(url)
            : type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true else { return }
        let accept: (WallpaperSourceImportResult) -> Void = { [self] result in
            Task { @MainActor [self] in
                guard let collections = self.workspace.collections,
                      self.relocationGeneration == generation, collections.snapshot.resetEpoch == epoch,
                      !collections.isResetting, self.workspace.presentation.canEditCollections,
                      self.workspace.presentation.page == page else { return }
                do {
                    let selectedPath = Data(url.resolvingSymlinksInPath().standardizedFileURL.path.utf8)
                    guard result.items.count == 1, let receipt = result.items.first,
                          receipt.disposition != .failed,
                          Data(receipt.sourceURL.resolvingSymlinksInPath().standardizedFileURL.path.utf8) == selectedPath,
                          let replacement = receipt.organizationItem, replacement.reference.provider == reference.provider,
                          replacement.isPublishedLocally, replacement.isAvailable else {
                        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: result.failures.first?.failureMessage ?? "所选文件未能成功入库，原关联保持不变。"])
                    }
                    let recovered = replacement.reference != reference ? await self.originalIsAvailable(reference) : false
                    guard self.relocationGeneration == generation, collections.snapshot.resetEpoch == epoch,
                          !collections.isResetting, self.workspace.presentation.canEditCollections,
                          self.workspace.presentation.page == page else { return }
                    guard let current = try? self.workspace.content(for: reference), current.reference == reference,
                          current.providerReference == reference,
                          !recovered, replacement.reference == reference || current.publishedAvailability != .available else {
                        throw UserCollectionsError.organizationConflict
                    }
                    // Video's normal writer is debounced; this explicit repair
                    // waits for its existing serial index owner before linking.
                    if reference.provider == .videoLibrary { try self.manager.persistWallpaperIndexNow(self.manager.wallpapers) }
                    let revisions = try WallpaperLibraryQuery.libraryExclusionRevisions(for: [reference, replacement.reference],
                        relationships: admittedRelationships)
                    // Link and clear share one SQL transaction. A later hide on
                    // either identity wins over this already-admitted repair.
                    _ = try await collections.perform([
                        .relocateLocalReference(reference, replacement, Date()),
                        .clearLibraryExclusion(replacement.reference, expectedRevision: revisions.values.max())
                    ], expectedEpoch: epoch)
                    guard self.relocationGeneration == generation, collections.snapshot.resetEpoch == epoch else { return }
                    self.workspace.catalog.refreshAvailability()
                } catch {
                    guard self.relocationGeneration == generation, collections.snapshot.resetEpoch == epoch,
                          !collections.isResetting, self.workspace.presentation.page == page else { return }
                    let alert = makeAppAlert(title: "文件未关联", message: error.localizedDescription
                        + "\n成功入库的文件仍保留在资料库中；原播放列表、特别喜爱和最近使用不会因此丢失。")
                    presentAppAlert(alert, in: self.hostWindow())
                }
            }
        }
        if reference.provider == .staticImageLibrary {
            images.importImages(from: [url], presentingIn: hostWindow(), presentsSummary: false, completion: accept)
        } else {
            manager.processImportedVideos(from: [url], presentingIn: hostWindow(), context: .library, presentsSummary: false, completion: accept)
        }
    }

    private func originalIsAvailable(_ reference: WallpaperReference) async -> Bool {
        switch reference.provider {
        case .videoLibrary:
            guard let value = manager.wallpapers.first(where: { $0.id.utf8.elementsEqual(reference.sourceID.utf8) }) else { return false }
            return await manager.libraryContentItems(from: [value], reusing: [], refreshAvailability: true).first?.publishedAvailability.isAvailable == true
        case .staticImageLibrary:
            guard let value = images.wallpapers.first(where: { $0.id.utf8.elementsEqual(reference.sourceID.utf8) }) else { return false }
            return await images.libraryContentItems(from: [value], reusing: [], refreshAvailability: true).first?.publishedAvailability.isAvailable == true
        default: return false
        }
    }

    private final class Batch {
        let order: [(path: String, isDirectory: Bool)]
        let admittedRelationships: UserCollectionsSnapshot
        var remaining: Int
        var results: [WallpaperSourceImportResult] = []
        init(order: [URL], remaining: Int, admittedRelationships: UserCollectionsSnapshot) {
            self.order = order.map { ($0.resolvingSymlinksInPath().standardizedFileURL.path,
                                      (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) }
            self.remaining = remaining
            self.admittedRelationships = admittedRelationships
        }
    }

    private func finish(_ batch: Batch, page: WallpaperLibraryPage, collections: UserCollectionsController, epoch: UUID) {
        // Source receipts preserve their own recursive order. Top-level mixed
        // files follow the user's original selection, never Set enumeration.
        func rank(_ item: WallpaperOrganizationItem) -> Int {
            guard let path = item.locator.path else { return Int.max }
            let normalized = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            return batch.order.firstIndex { input in
                input.path == normalized || input.isDirectory && normalized.hasPrefix(input.path.hasSuffix("/") ? input.path : input.path + "/")
            } ?? Int.max
        }
        // Resolve each imported path once; sorting must not repeat filesystem
        // normalization for every comparison in a large mixed import.
        let imported = batch.results.flatMap(\.organizationItems)
        var ranked: [(item: WallpaperOrganizationItem, rank: Int, offset: Int)] = imported.enumerated().map {
            (item: $0.element, rank: rank($0.element), offset: $0.offset)
        }
        ranked.sort {
            $0.rank == $1.rank ? $0.offset < $1.offset : $0.rank < $1.rank
        }
        let ordered = ranked.map { $0.item }
        Task { @MainActor [self] in
            guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
            do {
                if !ordered.isEmpty {
                let revisions = try WallpaperLibraryQuery.libraryExclusionRevisions(for: Set(ordered.map(\.reference)),
                    relationships: batch.admittedRelationships)
                var commands = ordered.map { UserCollectionsCommand.clearLibraryExclusion($0.reference, expectedRevision: revisions[$0.reference]) }
                var undoName: String?
                switch page {
                case .playlist(let id):
                    guard collections.snapshot.playlists.contains(where: { $0.id == id }) else {
                        throw UserCollectionsError.missingPlaylist
                    }
                    commands.append(.addMembers(id, ordered, Date())); undoName = "导入并加入列表"
                case .favorites:
                    commands += ordered.map { .setFavorite($0, true, Date()) }; undoName = "导入并特别喜爱"
                default: break
                }
                try await collections.perform(commands, undoName: undoName, expectedEpoch: epoch)
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                self.workspace.didEditMembers(of: page)
                }
                guard collections.snapshot.resetEpoch == epoch else { return }
                let added = batch.results.reduce(0) { $0 + $1.addedCount }
                let existing = batch.results.reduce(0) { $0 + $1.existingCount }
                let failures = batch.results.flatMap(\.failures)
                var lines = ["新增入库：\(added) 项", "已在资料库：\(existing) 项", "未完成：\(failures.count) 项"]
                lines += failures.prefix(8).map { $0.sourceURL.lastPathComponent + "：" + ($0.failureMessage ?? "未完成") }
                if failures.count > 8 { lines.append("另有 \(failures.count - 8) 项未显示") }
                let alert = makeAppAlert(title: "导入结果", message: lines.joined(separator: "\n"))
                presentAppAlert(alert, in: self.hostWindow())
            } catch {
                guard collections.snapshot.resetEpoch == epoch else { return }
                let alert = makeAppAlert(title: "导入整理未完成", message: error.localizedDescription + "\n已成功导入的原始壁纸仍保留在资料库中。")
                presentAppAlert(alert, in: self.hostWindow())
            }
        }
    }
}
