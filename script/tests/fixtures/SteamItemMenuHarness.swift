import AppKit

struct SteamWorkshopBrowserItem { let id: String; let title: String; let detailURL: URL }
struct Record { enum Status { case ready, failed }; let id: String; var status: Status; var failureMessage: String?; let folderURL = URL(fileURLWithPath: "/private/tmp") }
struct Progress { enum Phase { case saving, transferring }; var phase: Phase; var jobKey: String }
struct Job { enum State { case failed, queued }; let id: String; let workshopItemId: String; let accountSteamId: String; let state: State }
@MainActor final class ProgressStore { var value: Progress?; func snapshot(for id: String) -> Progress? { value } }
@MainActor final class Jobs { var jobs: [Job] = []; func activeJob(forWorkshopItemId id: String) -> Job? { jobs.first { $0.workshopItemId == id && $0.state == .queued } } }
@MainActor final class Client { var accountEpoch = 1 }
@MainActor final class Auth { var isOnline = true; var steamId: String? = "account" }
@MainActor final class Subscriptions {
    enum State: Equatable { case unknown, loading, known(Bool), writing, reconciling, unconfirmed(String) }
    var value = State.known(false); var writes = 0; var reads = 0
    func state(for id: String) -> State { value }
    func toggle(_ id: String) { writes += 1 }
    func refresh(_ id: String) { reads += 1 }
}
@MainActor final class SteamWorkshopService {
    let steamServiceClient = Client(); let steamAuth = Auth(); let steamSubscriptions = Subscriptions()
    let downloadProgressStore = ProgressStore(); let downloadJobStore = Jobs()
    var downloading = false; var queued = false; var record: Record?; var commands: [String] = []
    func presentItemDetail(_ item: SteamWorkshopBrowserItem) { commands.append("detail:" + item.id) }
    func presentDownloadTaskDetail(itemID: String, title: String) { commands.append("progress:" + itemID) }
    func isDownloading(itemID: String) -> Bool { downloading }
    func isQueuedForDownload(itemID: String) -> Bool { queued }
    func latestDownloadRecord(for id: String) -> Record? { record }
    func isLaunchPending(_ id: String) -> Bool { false }
    func setAsWallpaper(_ record: Record) { commands.append("play:" + record.id) }
    func canRequestDownload(id: String) -> Bool { !queued }
    func requestDownloadForBrowserItem(_ item: SteamWorkshopBrowserItem) { commands.append("download:" + item.id) }
    func cancelDownload(itemID: String) { commands.append("cancel:" + itemID) }
    func discardFailedDownload(jobID: String) { commands.append("discard:" + jobID) }
    static func resolvedAuthorWorkshopURL(for item: SteamWorkshopBrowserItem) -> URL? { item.detailURL }
    func openAuthorWorksPage(for item: SteamWorkshopBrowserItem) { commands.append("author:" + item.id) }
    func openWorkshopDetailPage(for item: SteamWorkshopBrowserItem) { commands.append("web:" + item.id) }
    func presentSteamLoginGuidance(context: String) { commands.append("guidance") }
}
@main struct MenuHarness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let service = SteamWorkshopService()
        let item = SteamWorkshopBrowserItem(id: "1234567890", title: "作品", detailURL: URL(string: "https://example.invalid")!)
        let first = SteamWorkshopItemMenu.make(item: item, service: service)
        invoke(first, "下载壁纸")
        precondition(service.commands == ["download:1234567890"])
        service.steamServiceClient.accountEpoch += 1
        invoke(first, "下载壁纸")
        precondition(service.commands.count == 1, "stale account menu must not write")
        let known = SteamWorkshopItemMenu.make(item: item, service: service)
        service.steamSubscriptions.value = .known(true)
        invoke(known, "加入订阅")
        precondition(service.steamSubscriptions.writes == 0, "stale state must not toggle")
        service.steamSubscriptions.value = .unknown
        invoke(SteamWorkshopItemMenu.make(item: item, service: service), "查询订阅状态")
        precondition(service.steamSubscriptions.reads == 1 && service.steamSubscriptions.writes == 0)
        service.downloading = true
        service.downloadProgressStore.value = Progress(phase: .transferring, jobKey: "old")
        let active = SteamWorkshopItemMenu.make(item: item, service: service)
        service.downloadProgressStore.value?.jobKey = "new"
        invoke(active, "取消下载")
        precondition(service.commands.count == 1, "stale job menu must not cancel new attempt")
        service.downloadProgressStore.value?.phase = .saving
        let saving = SteamWorkshopItemMenu.make(item: item, service: service)
        precondition(saving.items.first { $0.title == "取消下载" }?.isEnabled == false)
        service.downloading = false; service.downloadProgressStore.value = nil; service.queued = true
        service.downloadJobStore.jobs = [Job(id: "queue1", workshopItemId: item.id, accountSteamId: "account", state: .queued)]
        let queue = SteamWorkshopItemMenu.make(item: item, service: service)
        service.downloadJobStore.jobs = [Job(id: "queue2", workshopItemId: item.id, accountSteamId: "account", state: .queued)]
        invoke(queue, "取消下载")
        precondition(service.commands.count == 1, "queued identity must stay bound")
        service.steamAuth.isOnline = false
        invoke(SteamWorkshopItemMenu.make(item: item, service: service), "加入订阅")
        precondition(service.commands.last == "guidance" && service.steamSubscriptions.writes == 0)
        print("Item menu: item, account, subscription, attempt and queued identity dispatch PASS")
    }
    @MainActor static func invoke(_ menu: NSMenu, _ title: String) {
        let item = menu.items.first { $0.title == title }!
        precondition(item.isEnabled)
        NSApp.sendAction(item.action!, to: item.target, from: item)
    }
}
