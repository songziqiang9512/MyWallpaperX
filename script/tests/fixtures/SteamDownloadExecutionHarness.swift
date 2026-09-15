import Foundation

struct SteamWorkshopBrowserItem: Codable { let id: String; let title: String; var fileSizeText: String? { nil } }
struct SteamWorkshopPendingDownloadRequest { let id: String; let pageTitle: String?; let item: SteamWorkshopBrowserItem? }
struct SteamWorkshopDownloadRecord {
    enum Dependency { case none, missing(String) }
    enum Status: Equatable { case queued, downloading, ready, failed(String) }
    let id: String; let title: String; let sizeText: String; let dependencyStatus = Dependency.none
    let status: Status
}
// Data-only stand-ins isolate the real executor/publication methods from unrelated AppKit rendering.
struct SteamWorkshopDownloadMetadataSnapshot: Codable {
    let fetchedAt: Date; let item: SteamWorkshopBrowserItem; let sourceVideoRelativePath: String?
    let previewRelativePath: String?; let exportedVideoURL: URL?; let legacyFolderURL: URL?
    var commit: SteamWorkshopLibraryCommit? = nil
}
@MainActor final class Auth { var steamId: String? = "76561198000000000"; var isOnline: Bool { steamId != nil } }
final class Transport: SteamServiceTransporting {
    var isRunning = false
    var onOutput: ((Data) -> Void)?; var onError: ((String) -> Void)?; var onTermination: ((Int32) -> Void)?
    var commands: [[String: Any]] = []
    var receipt: [String: Any] = [:]
    var hold = false
    var failStart = false
    private var heldStartRequest: [String: Any]?
    func emit(_ frame: [String: Any]) { var bytes = try! JSONSerialization.data(withJSONObject: frame); bytes.append(10); onOutput?(bytes) }
    func start() throws { isRunning = true; emit(["v":1,"type":"ready","protocol":1,"helperVersion":"test"]) }
    func send(_ data: Data) -> Bool {
        let request = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        commands.append(request)
        let command = request["command"] as! String
        if command == "startDownload" {
            emit(["v":1,"type":"event","event":"downloadProgress","requestId":request["requestId"]!,
                  "accountEpoch":request["accountEpoch"]!,"jobId":request["jobId"]!,"sequence":1,
                  "stage":"downloading","stagingPath":receipt["stagingPath"]!])
        }
        if command == "startDownload" && hold {
            heldStartRequest = request
            return true
        }
        if command == "startDownload" && failStart {
            emit(["v":1,"type":"result","ok":false,"requestId":request["requestId"]!,
                  "accountEpoch":request["accountEpoch"]!,
                  "error":["code":"network","message":"fixture network failure"]])
            return true
        }
        var data = receipt
        data["jobId"] = request["jobId"]
        emit(["v":1,"type":"result","ok":true,"requestId":request["requestId"]!,
              "accountEpoch":request["accountEpoch"]!,"data":command == "startDownload" ? data : [:]])
        return true
    }
    func finishHeldCancellation() {
        guard let request = heldStartRequest else { fatalError("missing held start") }
        heldStartRequest = nil
        emit(["v":1,"type":"result","ok":false,"requestId":request["requestId"]!,
              "accountEpoch":request["accountEpoch"]!,
              "error":["code":"cancelled","message":"download cancelled"]])
    }
    func finishHeldSuccess() {
        guard let request = heldStartRequest else { fatalError("missing held start") }
        heldStartRequest = nil
        var data = receipt
        data["jobId"] = request["jobId"]
        emit(["v":1,"type":"result","ok":true,"requestId":request["requestId"]!,
              "accountEpoch":request["accountEpoch"]!,"data":data])
    }
    func closeInput() {}
    func terminate() { isRunning = false }
    func scheduleForcedTermination(after delay: TimeInterval) {}
}
@MainActor final class SteamWorkshopService {
    let steamAuth = Auth()
    let steamServiceClient: SteamServiceClient
    let steamWorkshopQueryClient: SteamWorkshopQueryClient
    let downloadJobStore: SteamDownloadJobStore
    let libraryRootURL: URL; let steamDownloadStagingRootURL: URL
    var steamDownloadLibraryRootURL: URL { (try? SteamWorkshopLibraryTransaction.configuredRoot(libraryRootURL)) ?? libraryRootURL }
    var activeDownloadTask: Task<Void, Never>?; var activeDownloadItemID: String?; var activeDownloadJobKey: String?
    var activeDownloadWasCancelled = false
    var statusMessage = ""; var downloadError: String?
    var isAuthenticating = false; var isLoginSheetPresented = false
    enum Phase { case credentials, awaitingGuardCode }; var authPhase = Phase.credentials
    var steamJobItemPayloads: [String: SteamWorkshopBrowserItem] = [:]
    var downloads: [SteamWorkshopDownloadRecord] = []
    var reloads = 0
    init(base: URL, transport: Transport) {
        steamServiceClient = SteamServiceClient(executablePath: "/fake", transportFactory: { _ in transport })
        steamWorkshopQueryClient = SteamWorkshopQueryClient(client: steamServiceClient)
        downloadJobStore = SteamDownloadJobStore(persistenceURL: base.appendingPathComponent("jobs.json"))
        libraryRootURL = base.appendingPathComponent("library")
        steamDownloadStagingRootURL = base.appendingPathComponent("staging", isDirectory: true)
    }
    func browserItemForDownload(id: String) -> SteamWorkshopBrowserItem? { nil }
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { downloads.first { $0.id == id } }
    func presentSteamLoginGuidance(context: String) { statusMessage = "login required" }
    func appendSteamAuthDebugLog(_ message: String) {}
    func upsertTransientRecord(id: String, title: String, status: SteamWorkshopDownloadRecord.Status, sizeText: String) {
        let record = SteamWorkshopDownloadRecord(id: id, title: title, sizeText: sizeText, status: status)
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index] = record
        } else {
            downloads.append(record)
        }
    }
    func reloadInstalledItems() { reloads += 1 }
    static func itemByMergingAuthorMetadata(into: SteamWorkshopBrowserItem?, id: String, title: String?,
        author: String, authorProfileURL: URL?, authorWorkshopURL: URL?) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(id: id, title: title ?? "test")
    }
}
@main struct Harness {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let mode = CommandLine.arguments[2]
        let transport = Transport()
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("receipt.json"))) as! [String: Any]
        transport.receipt = fixture["data"] as! [String: Any]
        transport.hold = mode == "cancel" || mode == "switch"
        transport.failStart = mode == "network-failure"
        let service = SteamWorkshopService(base: base, transport: transport)
        service.downloadWorkshopItem(id: "123456", pageTitle: "test")
        while !transport.commands.contains(where: { $0["command"] as? String == "startDownload" }) { await Task.yield() }
        let key = transport.commands.first! ["jobId"] as! String
        if mode == "cancel" {
            service.cancelActiveDownload()
            while !transport.commands.contains(where: { $0["command"] as? String == "cancelDownload" }) {
                await Task.yield()
            }
            precondition(service.activeDownloadTask != nil, "local queue advanced before helper drain")
            transport.finishHeldCancellation()
        }
        if mode == "switch" {
            service.steamServiceClient.accountEpoch += 1
            service.steamAuth.steamId = "76561198000000001"
            precondition(service.activeDownloadTask != nil, "epoch change dropped the physical-drain waiter")
            transport.finishHeldSuccess()
        }
        while service.activeDownloadTask != nil { await Task.yield() }
        let marker = base.appendingPathComponent("library/.mywallpaperx-steam-metadata/123456.json")
        if mode == "success" {
            precondition(service.downloadError == nil, service.downloadError ?? service.statusMessage)
            let result = try JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: Data(contentsOf: marker))
            precondition(result.commit?.jobId == key && result.commit?.attempt == 1)
            precondition(service.downloadJobStore.jobs.last?.state == .completed && service.reloads == 1)
            precondition(transport.commands.filter { $0["command"] as? String == "startDownload" }.count == 1)
        } else if mode != "network-failure" {
            let oldMarker = try String(contentsOf: marker, encoding: .utf8)
            precondition(oldMarker == "OLD READY POINTER")
            precondition(service.downloadJobStore.jobs.last?.state != .completed)
            if mode == "cancel" {
                while !transport.commands.contains(where: { $0["command"] as? String == "cancelDownload" }) { await Task.yield() }
                precondition(transport.commands.contains { $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key })
            }
        } else {
            let oldMarker = try String(contentsOf: marker, encoding: .utf8)
            precondition(oldMarker == "OLD READY POINTER")
            guard let failure = service.downloadJobStore.jobs.last else { fatalError("missing failed job") }
            precondition(failure.state == .failed && failure.attempt == 1 && failure.stagingPath != nil)
            guard case let .failed(message)? = service.downloads.first?.status else {
                fatalError("missing failed card")
            }
            precondition(!message.isEmpty && message == failure.failureMessage)
            let reloaded = SteamDownloadJobStore(persistenceURL: base.appendingPathComponent("jobs.json"))
            precondition(reloaded.failedJob(
                forWorkshopItemId: "123456", accountSteamId: "76561198000000000")?.id == failure.id)
            transport.failStart = false
            service.downloadWorkshopItem(id: "123456", pageTitle: "test")
            while service.activeDownloadTask != nil { await Task.yield() }
            let starts = transport.commands.filter { $0["command"] as? String == "startDownload" }
            precondition(starts.count == 2 && starts.last?["jobId"] as? String == failure.id + "-2",
                "explicit retry must keep logical job identity and increment attempt")
            precondition(service.downloadJobStore.jobs.last?.state == .completed)
        }
        await service.steamServiceClient.stop(shutdownTimeout: 0)
        print("EXECUTION PASS: \(mode)")
    }
}
