import AppKit

/// Recovery commands for unavailable relationships. The original source
/// services still own authentication, download admission and external pages.
@MainActor enum WallpaperLibraryDownloadRecovery {
    /// Return on a non-playable row may retry an original source task or
    /// recover a deleted download. It never becomes a playback request.
    static func makePrimaryAction(for item: WallpaperContentItem, workspace: WallpaperLibraryWorkspace,
                                  steam: SteamWorkshopService, online: OnlineLibraryService) -> (() -> Void)? {
        let reference = item.reference
        guard !item.capabilities.contains(.play), matchesSourceIdentity(item, in: workspace),
              workspace.presentation.canEditCollections, workspace.collections?.isResetting == false else { return nil }
        let epoch = workspace.relationships.resetEpoch, page = workspace.presentation.page
        switch reference.provider {
        case .steamWorkshop:
            guard steam.recoveryWorkshopDetailURL(itemID: reference.sourceID) != nil,
                  downloadable(item) || (eligible(reference, in: workspace) != nil && steam.latestDownloadRecord(for: reference.sourceID) == nil) else { return nil }
            let account = steam.steamServiceClient.accountEpoch
            return { [weak workspace, weak steam] in
                guard let workspace, let steam, workspace.relationships.resetEpoch == epoch,
                      workspace.presentation.page == page, workspace.presentation.canEditCollections,
                      workspace.collections?.isResetting == false, steam.steamServiceClient.accountEpoch == account,
                      let current = try? workspace.content(for: reference), current.reference == reference,
                      matchesSourceIdentity(current, in: workspace), !current.capabilities.contains(.play),
                      steam.recoveryWorkshopDetailURL(itemID: reference.sourceID) != nil,
                      downloadable(current) || (eligible(reference, in: workspace) != nil && steam.latestDownloadRecord(for: reference.sourceID) == nil) else { return }
                steam.downloadWorkshopItem(id: reference.sourceID, pageTitle: current.title)
            }
        case .pixabay:
            guard let id = Int(reference.sourceID), id > 0, String(id).utf8.elementsEqual(reference.sourceID.utf8),
                  online.items.contains(where: { $0.id == id }),
                  downloadable(item) || eligible(reference, in: workspace) != nil else { return nil }
            return { [weak workspace, weak online] in
                guard let workspace, let online, workspace.relationships.resetEpoch == epoch,
                      workspace.presentation.page == page, workspace.presentation.canEditCollections,
                      workspace.collections?.isResetting == false,
                      let current = try? workspace.content(for: reference), current.reference == reference,
                      matchesSourceIdentity(current, in: workspace), !current.capabilities.contains(.play),
                      downloadable(current) || eligible(reference, in: workspace) != nil,
                      let source = online.items.first(where: { $0.id == id }) else { return }
                online.download(item: source)
            }
        case .wallhaven, .pixiv:
            let library = OnlineImageLibrary.shared
            guard library.record(for: reference) != nil,
                  downloadable(item) || eligible(reference, in: workspace) != nil else { return nil }
            return { [weak workspace, weak library] in
                guard let workspace, let library, workspace.relationships.resetEpoch == epoch,
                      workspace.presentation.page == page, workspace.presentation.canEditCollections,
                      workspace.collections?.isResetting == false,
                      let current = try? workspace.content(for: reference), current.reference == reference, !current.capabilities.contains(.play),
                      matchesSourceIdentity(current, in: workspace), library.record(for: reference) != nil else { return }
                library.retry(reference)
            }
        default: return nil
        }
    }

    static func makeMenu(for item: WallpaperContentItem, workspace: WallpaperLibraryWorkspace,
                         steam: SteamWorkshopService, online: OnlineLibraryService) -> NSMenu? {
        let reference = item.reference
        guard eligible(reference, in: workspace) != nil else { return nil }
        let epoch = workspace.relationships.resetEpoch
        let page = workspace.presentation.page
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch reference.provider {
        case .steamWorkshop:
            // The original service validates real Workshop IDs. Independent
            // video:<stem> records have no remote work to recover.
            guard steam.recoveryWorkshopDetailURL(itemID: reference.sourceID) != nil,
                  steam.latestDownloadRecord(for: reference.sourceID) == nil else { return nil }
            let account = steam.steamServiceClient.accountEpoch
            if let download = makePrimaryAction(for: item, workspace: workspace, steam: steam, online: online) {
                menu.addItem(ActionMenuItem(title: "重新下载", symbol: "arrow.down.circle", handler: download))
            }
            menu.addItem(ActionMenuItem(title: "查看创意工坊页面", symbol: "safari") { [weak workspace, weak steam] in
                guard let workspace, let steam, workspace.relationships.resetEpoch == epoch,
                      workspace.presentation.page == page, steam.steamServiceClient.accountEpoch == account,
                      eligible(reference, in: workspace) != nil else { return }
                steam.openWorkshopDetailPage(itemID: reference.sourceID)
            })
        case .pixabay:
            guard let id = Int(reference.sourceID), id > 0,
                  String(id).utf8.elementsEqual(reference.sourceID.utf8) else { return nil }
            // A browse item is an original owner fact, not a fabricated CDN
            // URL or a second persistent copy of remote download metadata.
            if let download = makePrimaryAction(for: item, workspace: workspace, steam: steam, online: online) {
                menu.addItem(ActionMenuItem(title: "重新下载", symbol: "arrow.down.circle", handler: download))
            }
            menu.addItem(ActionMenuItem(title: "查看 Pixabay 原网页", symbol: "safari") { [weak workspace, weak online] in
                guard let workspace, let online, workspace.relationships.resetEpoch == epoch,
                      workspace.presentation.page == page, eligible(reference, in: workspace) != nil else { return }
                online.openVideoSourcePage(id: id)
            })
        case .wallhaven, .pixiv:
            let library = OnlineImageLibrary.shared
            guard library.record(for: reference) != nil else { return nil }
            if let download = makePrimaryAction(for: item, workspace: workspace, steam: steam, online: online) {
                menu.addItem(ActionMenuItem(title: "重新下载", symbol: "arrow.down.circle", handler: download))
            }
            menu.addItem(ActionMenuItem(title: "查看原网页", symbol: "safari") { [weak workspace, weak library] in
                guard let workspace, let library, workspace.relationships.resetEpoch == epoch,
                      workspace.presentation.page == page, eligible(reference, in: workspace) != nil,
                      let record = library.record(for: reference) else { return }
                NSWorkspace.shared.open(record.sourceURL)
            })
        default: return nil
        }
        return menu
    }

    private static func downloadable(_ item: WallpaperContentItem) -> Bool {
        !item.capabilities.intersection([.download, .retryDownload, .retryUpdate]).isEmpty
    }

    private static func matchesSourceIdentity(_ item: WallpaperContentItem, in workspace: WallpaperLibraryWorkspace) -> Bool {
        if item.providerReference == item.reference { return true }
        // Deleted downloaded videos may retain their original local backing
        // row. Only the relationship store's proven alias may bridge it.
        guard item.providerReference.provider == .videoLibrary,
              let canonical = try? WallpaperLibraryQuery.canonicalReferences([item.providerReference], relationships: workspace.relationships) else { return false }
        return canonical[item.providerReference] == item.reference
    }

    private static func eligible(_ reference: WallpaperReference, in workspace: WallpaperLibraryWorkspace) -> WallpaperContentItem? {
        guard workspace.presentation.canEditCollections,
              workspace.collections?.isResetting == false,
              [.steamWorkshop, .pixabay, .wallhaven, .pixiv].contains(reference.provider),
              let current = try? workspace.content(for: reference),
              current.reference == reference, matchesSourceIdentity(current, in: workspace),
              current.publishedAvailability == .unavailable else { return nil }
        if reference.provider == .wallhaven || reference.provider == .pixiv {
            return OnlineImageLibrary.shared.record(for: reference) != nil ? current : nil
        }
        let state = workspace.relationships
        let related = state.members.map(\.reference) + state.favorites.map(\.reference) + state.recent.map(\.reference)
        guard let canonical = try? WallpaperLibraryQuery.canonicalReferences(Set(related), relationships: state),
              related.contains(where: { canonical[$0] == reference }) else { return nil }
        return current
    }
}
