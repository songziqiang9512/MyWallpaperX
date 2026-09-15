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
    var startErrorCode: String?
    private var heldStartRequests: [String: [String: Any]] = [:]
    private func receiptData(for request: [String: Any]) -> [String: Any] {
        var data = receipt
        let payload = request["payload"] as? [String: Any]
        if payload?["workshopId"] as? String == "654321" {
            data["workshopId"] = "654321"
            data["stagingPath"] = receipt["secondStagingPath"]
        }
        data.removeValue(forKey: "secondStagingPath")
        return data
    }
    func emit(_ frame: [String: Any]) { var bytes = try! JSONSerialization.data(withJSONObject: frame); bytes.append(10); onOutput?(bytes) }
    func start() throws { isRunning = true; emit(["v":1,"type":"ready","protocol":1,"helperVersion":"test"]) }
    func send(_ data: Data) -> Bool {
        let request = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        commands.append(request)
        let command = request["command"] as! String
        let responseData = receiptData(for: request)
        if command == "startDownload" {
            emit(["v":1,"type":"event","event":"downloadProgress","requestId":request["requestId"]!,
                  "accountEpoch":request["accountEpoch"]!,"jobId":request["jobId"]!,"sequence":1,
                  "stage":"downloading","stagingPath":responseData["stagingPath"]!,
                  "manifestId":responseData["manifestId"]!])
        }
        if command == "startDownload" && hold {
            heldStartRequests[request["jobId"] as! String] = request
            return true
        }
        if command == "startDownload", let startErrorCode {
            emit(["v":1,"type":"result","ok":false,"requestId":request["requestId"]!,
                  "accountEpoch":request["accountEpoch"]!,
                  "error":["code":startErrorCode,"message":startErrorCode == "integrity"
                    ? "staging manifest changed" : "fixture network failure"]])
            return true
        }
        var data = responseData
        data["jobId"] = request["jobId"]
        emit(["v":1,"type":"result","ok":true,"requestId":request["requestId"]!,
              "accountEpoch":request["accountEpoch"]!,"data":command == "startDownload" ? data : [:]])
        return true
    }
    func finishHeldCancellation(jobId: String? = nil) {
        let selected = jobId ?? heldStartRequests.keys.first
        guard let selected, let request = heldStartRequests.removeValue(forKey: selected) else {
            fatalError("missing held start")
        }
        emit(["v":1,"type":"result","ok":false,"requestId":request["requestId"]!,
              "accountEpoch":request["accountEpoch"]!,
              "error":["code":"cancelled","message":"download cancelled"]])
    }
    func finishHeldSuccess(jobId: String? = nil) {
        let selected = jobId ?? heldStartRequests.keys.first
        guard let selected, let request = heldStartRequests.removeValue(forKey: selected) else {
            fatalError("missing held start")
        }
        var data = receiptData(for: request)
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
    let maximumConcurrentDownloads = 2
    var activeDownloadItemIDs: Set<String> = []
    var activeDownloadJobKeysByItemID: [String: String] = [:]
    var activeDownloadTasks: [String: Task<Void, Never>] = [:]
    var cancelledDownloadJobKeys: Set<String> = []
    var reservedLibraryCopyBytesByJobKey: [String: Int64] = [:]
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
            || mode == "concurrent-cancel" || mode == "concurrent-success"
        transport.startErrorCode = mode == "network-failure" ? "network"
            : mode == "manifest-mismatch" ? "integrity"
            : mode == "disk-full" ? "diskFull" : nil
        let service = SteamWorkshopService(base: base, transport: transport)
        service.downloadWorkshopItem(id: "123456", pageTitle: "test")
        while !transport.commands.contains(where: { $0["command"] as? String == "startDownload" }) { await Task.yield() }
        let key = transport.commands.first! ["jobId"] as! String
        if mode == "concurrent-cancel" {
            service.downloadWorkshopItem(id: "654321", pageTitle: "second")
            while transport.commands.filter({ $0["command"] as? String == "startDownload" }).count < 2 {
                await Task.yield()
            }
            let starts = transport.commands.filter { $0["command"] as? String == "startDownload" }
            let second = starts.first {
                ($0["payload"] as? [String: Any])?["workshopId"] as? String == "654321"
            }!
            let secondKey = second["jobId"] as! String
            precondition(service.activeDownloadTasks.count == 2 && service.activeDownloadItemIDs == ["123456", "654321"])
            service.cancelDownload(itemID: "123456")
            while !transport.commands.contains(where: {
                $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
            }) { await Task.yield() }
            transport.finishHeldCancellation(jobId: key)
            while service.activeDownloadTasks[key] != nil { await Task.yield() }
            precondition(service.activeDownloadTasks[secondKey] != nil
                && service.downloadJobStore.activeJob(forWorkshopItemId: "654321")?.state == .running,
                "cancelling A must not retire B")
            transport.finishHeldSuccess(jobId: secondKey)
        }
        if mode == "concurrent-success" {
            service.downloadWorkshopItem(id: "654321", pageTitle: "second")
            while transport.commands.filter({ $0["command"] as? String == "startDownload" }).count < 2 {
                await Task.yield()
            }
            let starts = transport.commands.filter { $0["command"] as? String == "startDownload" }
            let second = starts.first {
                ($0["payload"] as? [String: Any])?["workshopId"] as? String == "654321"
            }!
            transport.finishHeldSuccess(jobId: key)
            transport.finishHeldSuccess(jobId: second["jobId"] as? String)
        }
        if mode == "cancel" {
            service.cancelActiveDownload()
            while !transport.commands.contains(where: { $0["command"] as? String == "cancelDownload" }) {
                await Task.yield()
            }
            precondition(!service.activeDownloadTasks.isEmpty, "local queue advanced before helper drain")
            transport.finishHeldCancellation()
        }
        if mode == "switch" {
            service.steamServiceClient.accountEpoch += 1
            service.steamAuth.steamId = "76561198000000001"
            precondition(!service.activeDownloadTasks.isEmpty, "epoch change dropped the physical-drain waiter")
            transport.finishHeldSuccess()
        }
        while !service.activeDownloadTasks.isEmpty { await Task.yield() }
        let marker = base.appendingPathComponent("library/.mywallpaperx-steam-metadata/123456.json")
        if mode == "concurrent-cancel" {
            let oldMarker = try String(contentsOf: marker, encoding: .utf8)
            precondition(oldMarker == "OLD READY POINTER")
            let secondMarker = base.appendingPathComponent("library/.mywallpaperx-steam-metadata/654321.json")
            let secondResult = try JSONDecoder().decode(
                SteamWorkshopDownloadMetadataSnapshot.self,
                from: Data(contentsOf: secondMarker)
            )
            precondition(secondResult.commit?.workshopId == "654321")
            precondition(service.downloadJobStore.jobs.first { $0.workshopItemId == "123456" }?.state == .cancelled)
            precondition(service.downloadJobStore.jobs.first { $0.workshopItemId == "654321" }?.state == .completed)
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String))
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["secondStagingPath"] as! String))
        } else if mode == "concurrent-success" {
            let firstResult = try JSONDecoder().decode(
                SteamWorkshopDownloadMetadataSnapshot.self,
                from: Data(contentsOf: marker)
            )
            let secondMarker = base.appendingPathComponent("library/.mywallpaperx-steam-metadata/654321.json")
            let secondResult = try JSONDecoder().decode(
                SteamWorkshopDownloadMetadataSnapshot.self,
                from: Data(contentsOf: secondMarker)
            )
            precondition(firstResult.commit?.workshopId == "123456"
                && secondResult.commit?.workshopId == "654321")
            precondition(service.downloadJobStore.jobs.allSatisfy { $0.state == .completed })
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String))
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["secondStagingPath"] as! String))
        } else if mode == "success" {
            precondition(service.downloadError == nil, service.downloadError ?? service.statusMessage)
            let result = try JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: Data(contentsOf: marker))
            precondition(result.commit?.jobId == key && result.commit?.attempt == 1)
            precondition(service.downloadJobStore.jobs.last?.state == .completed && service.reloads == 1)
            precondition(transport.commands.filter { $0["command"] as? String == "startDownload" }.count == 1)
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String),
                "successful publication must retire its exact staging lease")
        } else if mode != "network-failure" && mode != "disk-full" {
            let oldMarker = try String(contentsOf: marker, encoding: .utf8)
            precondition(oldMarker == "OLD READY POINTER")
            precondition(service.downloadJobStore.jobs.last?.state != .completed)
            if mode == "cancel" {
                while !transport.commands.contains(where: { $0["command"] as? String == "cancelDownload" }) { await Task.yield() }
                precondition(transport.commands.contains { $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key })
                precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String),
                    "physical cancellation terminal must retire its exact staging lease")
            }
            if mode == "manifest-mismatch" {
                guard let failure = service.downloadJobStore.jobs.last else { fatalError("missing failed job") }
                precondition(failure.state == .failed && failure.stagingPath == nil
                    && failure.stagingManifestId == nil,
                    "manifest mismatch must invalidate recovery identity")
                precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String),
                    "manifest mismatch must retire its exact staging lease")
            }
        } else if mode == "network-failure" {
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
            transport.startErrorCode = nil
            service.downloadWorkshopItem(id: "123456", pageTitle: "test")
            while !service.activeDownloadTasks.isEmpty { await Task.yield() }
            let starts = transport.commands.filter { $0["command"] as? String == "startDownload" }
            precondition(starts.count == 2 && starts.last?["jobId"] as? String == failure.id + "-2",
                "explicit retry must keep logical job identity and increment attempt")
            let retryPayload = starts.last?["payload"] as? [String: Any]
            precondition(retryPayload?["resumeStagingPath"] as? String == failure.stagingPath
                && retryPayload?["resumeManifestId"] as? String == failure.stagingManifestId,
                "explicit retry must send the persisted manifest-bound staging identity")
            precondition(service.downloadJobStore.jobs.last?.state == .completed)
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String))
        } else {
            let oldMarker = try String(contentsOf: marker, encoding: .utf8)
            precondition(oldMarker == "OLD READY POINTER")
            guard let failure = service.downloadJobStore.jobs.last else { fatalError("missing failed job") }
            precondition(failure.state == .failed && failure.stagingPath != nil
                && failure.stagingManifestId == "123",
                "disk-full must retain manifest-bound staging for explicit retry")
            guard case let .failed(message)? = service.downloads.first?.status else {
                fatalError("missing disk-full card")
            }
            precondition(message.contains("磁盘空间不足") && message.contains("重试"))
            precondition(FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String))
        }
        await service.steamServiceClient.stop(shutdownTimeout: 0)
        print("EXECUTION PASS: \(mode)")
    }
}
