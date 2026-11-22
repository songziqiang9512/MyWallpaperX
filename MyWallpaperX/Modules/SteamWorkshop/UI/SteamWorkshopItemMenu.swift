import AppKit

/// Presentation of existing commands. A menu captures an item identity, never an index path.
@MainActor
enum SteamWorkshopItemMenu {
    static func make(item: SteamWorkshopBrowserItem, service: SteamWorkshopService,
                     includePrimary: Bool = true, includeReveal: Bool = true, navigationVersion: Int? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let epoch = service.steamServiceClient.accountEpoch
        func add(_ title: String, _ symbol: String, enabled: Bool = true,
                 accountBound: Bool = false, action: @escaping () -> Void) {
            let entry = ActionMenuItem(title: title, symbol: symbol) {
                if let navigationVersion, service.navigationVersion != navigationVersion { return }
                guard !accountBound || service.steamServiceClient.accountEpoch == epoch else { return }
                action()
            }
            entry.isEnabled = enabled
            menu.addItem(entry)
        }
        if includePrimary {
            add(String(localized: "View Details"), "info.circle") { service.presentItemDetail(item) }
            if service.isDownloading(itemID: item.id) || service.isQueuedForDownload(itemID: item.id) {
                add(String(localized: "View Download Progress"), "list.bullet.rectangle") { service.presentDownloadTaskDetail(itemID: item.id, title: item.title) }
            } else if let record = service.latestDownloadRecord(for: item.id), record.status == .ready {
                add(String(localized: "Set as Wallpaper"), "play.circle", enabled: !service.isLaunchPending(item.id)) {
                    guard let current = service.latestDownloadRecord(for: item.id), current.status == .ready,
                          !service.isLaunchPending(item.id) else { return }
                    service.setAsWallpaper(current)
                }
            } else {
                let failed = service.latestDownloadRecord(for: item.id)?.failureMessage != nil
                add(failed ? String(localized: "Retry Download") : String(localized: "Download Wallpaper"), "arrow.down.circle", accountBound: true) {
                    guard !service.isDownloading(itemID: item.id), service.canRequestDownload(id: item.id) else { return }
                    service.requestDownloadForBrowserItem(item)
                }
            }
        }
        if service.isDownloading(itemID: item.id) || service.isQueuedForDownload(itemID: item.id) {
            let key = service.downloadProgressStore.snapshot(for: item.id)?.jobKey
            let jobID = service.downloadJobStore.activeJob(forWorkshopItemId: item.id)?.id
            add(String(localized: "Cancel Download"), "xmark.circle", enabled: service.downloadProgressStore.snapshot(for: item.id)?.phase != .saving,
                accountBound: true) {
                guard service.downloadProgressStore.snapshot(for: item.id)?.phase != .saving,
                      service.downloadProgressStore.snapshot(for: item.id)?.jobKey == key,
                      service.downloadJobStore.activeJob(forWorkshopItemId: item.id)?.id == jobID,
                      service.isDownloading(itemID: item.id) || service.isQueuedForDownload(itemID: item.id) else { return }
                service.cancelDownload(itemID: item.id)
            }
        }
        if let job = service.downloadJobStore.jobs.first(where: {
            $0.workshopItemId == item.id && $0.state == .failed && $0.accountSteamId == service.steamAuth.steamId
        }) {
            add(String(localized: "Discard Failed Job"), "xmark.bin", accountBound: true) { service.discardFailedDownload(jobID: job.id) }
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(subscription(item: item, service: service, navigationVersion: navigationVersion))
        menu.addItem(.separator())
        add(String(localized: "View Author’s Workshop"), "person.crop.circle", enabled: SteamWorkshopService.resolvedAuthorWorkshopURL(for: item) != nil) {
            service.openAuthorWorksPage(for: item)
        }
        add(String(localized: "Open Workshop Page"), "safari") { service.openWorkshopDetailPage(for: item) }
        add(String(localized: "Copy Artwork Link"), "link") { copy(item.detailURL.absoluteString) }
        add(String(localized: "Copy Artwork ID"), "number") { copy(item.id) }
        if includeReveal, service.latestDownloadRecord(for: item.id)?.status == .ready {
            menu.addItem(.separator())
            add(String(localized: "Show in Finder"), "folder") {
                guard let current = service.latestDownloadRecord(for: item.id), current.status == .ready else { return }
                FinderRevealCoordinator.shared.reveal([current.folderURL])
            }
            if let record = service.latestDownloadRecord(for: item.id), record.contentType == .video,
               let file = record.videoURL, let openWith = WallpaperOpenWithMenu.make(for: [file], permitsAction: {
                   navigationVersion == nil || service.navigationVersion == navigationVersion
               }) {
                menu.addItem(openWith)
            }
        }
        return menu
    }

    static func subscription(item: SteamWorkshopBrowserItem, service: SteamWorkshopService, navigationVersion: Int? = nil) -> NSMenuItem {
        let epoch = service.steamServiceClient.accountEpoch
        let online = service.steamAuth.isOnline
        let state = service.steamSubscriptions.state(for: item.id)
        let title: String
        var enabled = true
        if !online { title = String(localized: "Subscribe") }
        else {
            switch state {
            case .known(let subscribed): title = subscribed ? String(localized: "Unsubscribe") : String(localized: "Subscribe")
            case .unknown, .unconfirmed: title = String(localized: "Check Subscription Status")
            case .loading: title = String(localized: "Checking subscription…"); enabled = false
            case .writing, .reconciling: title = String(localized: "Verifying subscription…"); enabled = false
            }
        }
        let entry = ActionMenuItem(title: title, symbol: "bookmark") {
            if let navigationVersion, service.navigationVersion != navigationVersion { return }
            guard service.steamServiceClient.accountEpoch == epoch else { return }
            guard service.steamAuth.isOnline else { service.presentSteamLoginForUserAction(context: String(localized: "Subscribe")); return }
            guard service.steamSubscriptions.state(for: item.id) == state else { return }
            switch state {
            case .known: service.steamSubscriptions.toggle(item.id)
            case .unknown, .unconfirmed: service.steamSubscriptions.refresh(item.id)
            default: break
            }
        }
        entry.isEnabled = enabled
        if state == .known(true) { entry.toolTip = String(localized: "Unsubscribing won’t delete local files or stop playback.") }
        return entry
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
