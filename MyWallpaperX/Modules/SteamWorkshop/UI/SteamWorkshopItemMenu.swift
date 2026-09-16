import AppKit

/// Presentation of existing commands. A menu captures an item identity, never an index path.
@MainActor
enum SteamWorkshopItemMenu {
    static func make(item: SteamWorkshopBrowserItem, service: SteamWorkshopService,
                     includePrimary: Bool = true) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let epoch = service.steamServiceClient.accountEpoch
        func add(_ title: String, _ symbol: String, enabled: Bool = true,
                 accountBound: Bool = false, action: @escaping () -> Void) {
            let entry = SteamWorkshopMenuItem(title: title, symbol: symbol) {
                guard !accountBound || service.steamServiceClient.accountEpoch == epoch else { return }
                action()
            }
            entry.isEnabled = enabled
            menu.addItem(entry)
        }
        if includePrimary {
            add("查看详情", "info.circle") { service.presentItemDetail(item) }
            if service.isDownloading(itemID: item.id) || service.isQueuedForDownload(itemID: item.id) {
                add("查看下载进度", "list.bullet.rectangle") { service.presentDownloadTaskDetail(itemID: item.id, title: item.title) }
            } else if let record = service.latestDownloadRecord(for: item.id), record.status == .ready {
                add("设为壁纸", "play.circle", enabled: !service.isLaunchPending(item.id)) {
                    guard let current = service.latestDownloadRecord(for: item.id), current.status == .ready,
                          !service.isLaunchPending(item.id) else { return }
                    service.setAsWallpaper(current)
                }
            } else {
                let failed = service.latestDownloadRecord(for: item.id)?.failureMessage != nil
                add(failed ? "重试下载" : "下载壁纸", "arrow.down.circle", accountBound: true) {
                    guard !service.isDownloading(itemID: item.id), service.canRequestDownload(id: item.id) else { return }
                    service.requestDownloadForBrowserItem(item)
                }
            }
        }
        if service.isDownloading(itemID: item.id) || service.isQueuedForDownload(itemID: item.id) {
            let key = service.downloadProgressStore.snapshot(for: item.id)?.jobKey
            let jobID = service.downloadJobStore.activeJob(forWorkshopItemId: item.id)?.id
            add("取消下载", "xmark.circle", enabled: service.downloadProgressStore.snapshot(for: item.id)?.phase != .saving,
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
            add("放弃失败任务", "xmark.bin", accountBound: true) { service.discardFailedDownload(jobID: job.id) }
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(subscription(item: item, service: service))
        menu.addItem(.separator())
        add("查看作者工坊", "person.crop.circle", enabled: SteamWorkshopService.resolvedAuthorWorkshopURL(for: item) != nil) {
            service.openAuthorWorksPage(for: item)
        }
        add("打开工坊页面", "safari") { service.openWorkshopDetailPage(for: item) }
        add("复制作品链接", "link") { copy(item.detailURL.absoluteString) }
        add("复制作品 ID", "number") { copy(item.id) }
        if service.latestDownloadRecord(for: item.id)?.status == .ready {
            menu.addItem(.separator())
            add("在 Finder 中显示", "folder") {
                guard let current = service.latestDownloadRecord(for: item.id), current.status == .ready else { return }
                NSWorkspace.shared.activateFileViewerSelecting([current.folderURL])
            }
        }
        return menu
    }

    static func subscription(item: SteamWorkshopBrowserItem, service: SteamWorkshopService) -> NSMenuItem {
        let epoch = service.steamServiceClient.accountEpoch
        let online = service.steamAuth.isOnline
        let state = service.steamSubscriptions.state(for: item.id)
        let title: String
        var enabled = true
        if !online { title = "加入订阅" }
        else {
            switch state {
            case .known(let subscribed): title = subscribed ? "取消订阅" : "加入订阅"
            case .unknown, .unconfirmed: title = "查询订阅状态"
            case .loading: title = "正在查询订阅…"; enabled = false
            case .writing, .reconciling: title = "正在核对订阅…"; enabled = false
            }
        }
        let entry = SteamWorkshopMenuItem(title: title, symbol: "bookmark") {
            guard service.steamServiceClient.accountEpoch == epoch else { return }
            guard service.steamAuth.isOnline else { service.presentSteamLoginForUserAction(context: "订阅"); return }
            guard service.steamSubscriptions.state(for: item.id) == state else { return }
            switch state {
            case .known: service.steamSubscriptions.toggle(item.id)
            case .unknown, .unconfirmed: service.steamSubscriptions.refresh(item.id)
            default: break
            }
        }
        entry.isEnabled = enabled
        if state == .known(true) { entry.toolTip = "取消订阅不会删除本地文件或中断播放。" }
        return entry
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
final class SteamWorkshopMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, symbol: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}
