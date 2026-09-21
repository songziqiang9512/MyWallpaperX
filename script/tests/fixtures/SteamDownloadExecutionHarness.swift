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
    let previewRelativePath: String?; let exportedVideoURL: URL?; let legacyFolderURL: URL?; var legacyRemoved: Bool? = nil
    var commit: SteamWorkshopLibraryCommit? = nil
}
@MainActor final class Auth { var steamId: String? = "76561198000000000"; var isOnline: Bool { steamId != nil } }
final class Transport: SteamServiceTransporting {
    var isRunning = false
    var onOutput: ((Data) -> Void)?; var onError: ((String) -> Void)?; var onTermination: ((Int32) -> Void)?
    var commands: [[String: Any]] = []
    var receipt: [String: Any] = [:]
    var hold = false
    var requireStagingAcknowledgement = false
    var failJobStoreBeforeAllocatedEvent = false
    var jobStoreURL: URL?
    var savedJobStoreURL: URL?
    var observedPersistedIdentityBeforeAcknowledgement = false
    var advertisedStagingAcknowledgementCapability: String? = SteamServiceProtocol.stagingAcknowledgementCapability
    var rejectStagingAcknowledgementWithIntegrity = false
    var allocatedEventHasWrongAccountEpoch = false
    var allocatedEventOmitsAccountEpoch = false
    var allocatedEventHasWrongBirth = false; var terminalReceiptHasWrongBirth = false
    var replaceStagingBeforeProgress = false
    var startErrorCode: String?
    private var didReplaceStaging = false
    private var heldStartRequests: [String: [String: Any]] = [:]
    private func receiptData(for request: [String: Any]) -> [String: Any] {
        var data = receipt
        let payload = request["payload"] as? [String: Any]
        if payload?["workshopId"] as? String == "654321" {
            data["workshopId"] = "654321"
            data["stagingPath"] = receipt["secondStagingPath"]
            data["stagingDevice"] = receipt["secondStagingDevice"]
            data["stagingInode"] = receipt["secondStagingInode"]
            data["stagingBirthSeconds"] = receipt["secondStagingBirthSeconds"]
            data["stagingBirthNanoseconds"] = receipt["secondStagingBirthNanoseconds"]
        }
        data.removeValue(forKey: "secondStagingPath")
        data.removeValue(forKey: "secondStagingDevice")
        data.removeValue(forKey: "secondStagingInode")
        data.removeValue(forKey: "secondStagingBirthSeconds")
        data.removeValue(forKey: "secondStagingBirthNanoseconds")
        return data
    }
    func emit(_ frame: [String: Any]) { var bytes = try! JSONSerialization.data(withJSONObject: frame); bytes.append(10); onOutput?(bytes) }
    func start() throws {
        isRunning = true
        emit([
            "v": 1, "type": "ready", "protocol": 1, "helperVersion": "test",
            "capabilities": advertisedStagingAcknowledgementCapability.map {
                ["ping", "shutdown", $0]
            } ?? ["ping", "shutdown"],
        ])
    }
    func send(_ data: Data) -> Bool {
        let request = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        commands.append(request)
        let command = request["command"] as! String
        let responseData = receiptData(for: request)
        if command == "startDownload" {
            if failJobStoreBeforeAllocatedEvent {
                let original = jobStoreURL!.appendingPathExtension("before-allocation")
                try! FileManager.default.moveItem(at: jobStoreURL!, to: original)
                try! FileManager.default.createDirectory(
                    at: jobStoreURL!, withIntermediateDirectories: false
                )
                savedJobStoreURL = original
            }
            if replaceStagingBeforeProgress && !didReplaceStaging {
                didReplaceStaging = true
                let target = URL(fileURLWithPath: responseData["stagingPath"] as! String, isDirectory: true)
                let original = target.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("original-prebind", isDirectory: true)
                try! FileManager.default.moveItem(at: target, to: original)
                try! FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                try! Data("replacement".utf8).write(to: target.appendingPathComponent("sentinel"))
            }
            var progress: [String: Any] = [
                "v": 1, "type": "event", "event": "downloadProgress",
                "requestId": request["requestId"]!, "jobId": request["jobId"]!, "sequence": 1,
                "stage": requireStagingAcknowledgement || failJobStoreBeforeAllocatedEvent
                    ? "allocated" : "downloading",
                "stagingPath": responseData["stagingPath"]!,
                "manifestId": responseData["manifestId"]!,
                "stagingDevice": responseData["stagingDevice"]!,
                "stagingInode": responseData["stagingInode"]!,
                "stagingBirthSeconds": responseData["stagingBirthSeconds"]!,
                "stagingBirthNanoseconds": responseData["stagingBirthNanoseconds"]!,
            ]
            if !allocatedEventOmitsAccountEpoch {
                let accountEpoch = request["accountEpoch"] as! Int
                progress["accountEpoch"] = allocatedEventHasWrongAccountEpoch
                    ? accountEpoch + 1 : accountEpoch
            }
            if allocatedEventHasWrongBirth {
                progress["stagingBirthSeconds"] = String(Int64(
                    responseData["stagingBirthSeconds"] as! String)! + 1)
            }
            emit(progress)
        }
        if command == "startDownload"
            && (hold || requireStagingAcknowledgement || failJobStoreBeforeAllocatedEvent) {
            heldStartRequests[request["jobId"] as! String] = request
            return true
        }
        if command == "acknowledgeDownloadStaging" {
            precondition(requireStagingAcknowledgement)
            let payload = request["payload"] as! [String: Any]
            let persisted = try! JSONSerialization.jsonObject(
                with: Data(contentsOf: jobStoreURL!)
            ) as! [String: Any]
            let jobs = persisted["jobs"] as! [[String: Any]]
            let jobKey = request["jobId"] as! String
            let job = jobs.first { candidate in
                guard let id = candidate["id"] as? String,
                      let attempt = candidate["attempt"] as? Int else { return false }
                return "\(id)-\(attempt)" == jobKey
            }!
            let identity = job["stagingLeaseIdentity"] as! [String: Any]
            precondition(job["stagingPath"] as? String == payload["stagingPath"] as? String)
            precondition(job["stagingManifestId"] as? String == payload["manifestId"] as? String)
            precondition(String(identity["device"] as! UInt64) == payload["stagingDevice"] as? String)
            precondition(String(identity["inode"] as! UInt64) == payload["stagingInode"] as? String)
            precondition(String(identity["birthSeconds"] as! Int64) == payload["stagingBirthSeconds"] as? String)
            precondition(String(identity["birthNanoseconds"] as! Int64) == payload["stagingBirthNanoseconds"] as? String)
            observedPersistedIdentityBeforeAcknowledgement = true
            emit(["v":1,"type":"result","ok":true,"requestId":request["requestId"]!,
                  "accountEpoch":request["accountEpoch"]!,
                  "data":["acknowledged":!rejectStagingAcknowledgementWithIntegrity]])
            if rejectStagingAcknowledgementWithIntegrity {
                try! FileManager.default.removeItem(
                    at: URL(fileURLWithPath: responseData["stagingPath"] as! String)
                )
                finishHeldFailure(
                    jobId: jobKey,
                    code: "integrity",
                    message: "staging acknowledgement timed out"
                )
            } else if let startErrorCode {
                finishHeldFailure(
                    jobId: jobKey,
                    code: startErrorCode,
                    message: startErrorCode == "integrity"
                        ? "staging manifest changed" : "fixture network failure"
                )
            } else if !hold {
                finishHeldSuccess(jobId: jobKey)
            }
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
    func finishHeldFailure(jobId: String, code: String, message: String) {
        guard let request = heldStartRequests.removeValue(forKey: jobId) else {
            fatalError("missing held start")
        }
        emit(["v":1,"type":"result","ok":false,"requestId":request["requestId"]!,
              "accountEpoch":request["accountEpoch"]!,
              "error":["code":code,"message":message]])
    }
    func restoreJobStoreAfterAllocationFailure() {
        guard let jobStoreURL, let savedJobStoreURL else { fatalError("missing failed JobStore fixture") }
        try! FileManager.default.removeItem(at: jobStoreURL)
        try! FileManager.default.moveItem(at: savedJobStoreURL, to: jobStoreURL)
        self.savedJobStoreURL = nil
    }
    func finishHeldSuccess(jobId: String? = nil) {
        let selected = jobId ?? heldStartRequests.keys.first
        guard let selected, let request = heldStartRequests.removeValue(forKey: selected) else {
            fatalError("missing held start")
        }
        var data = receiptData(for: request)
        data["jobId"] = request["jobId"]
        if terminalReceiptHasWrongBirth {
            data["stagingBirthNanoseconds"] = String((Int64(
                data["stagingBirthNanoseconds"] as! String)! + 1) % 1_000_000_000)
        }
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
    let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    let libraryRootURL: URL; let steamDownloadStagingRootURL: URL
    var steamDownloadLibraryRootURL: URL { (try? SteamWorkshopLibraryTransaction.configuredRoot(libraryRootURL)) ?? libraryRootURL }
    let maximumConcurrentDownloads = 2
    var terminalDownloadCleanupTask: Task<Void, Never>?
    var activeDownloadItemIDs: Set<String> = []
    var activeDownloadJobKeysByItemID: [String: String] = [:]
    var activeDownloadTasks: [String: Task<Void, Never>] = [:]
    var cancellationFeedbackByDownloadJobKey: [String: Bool] = [:]
    var reservedLibraryCopyBytesByJobKey: [String: Int64] = [:]
    var legacyLibraryPublicationMigrationTask: Task<Void, Never>?
    var statusMessage = ""; var downloadError: String?
    var isAuthenticating = false; var isLoginSheetPresented = false
    enum Phase { case credentials, awaitingGuardCode }; var authPhase = Phase.credentials
    var steamJobItemPayloads: [String: SteamWorkshopBrowserItem] = [:]
    var downloads: [SteamWorkshopDownloadRecord] = []; var selectedDownloadID: String?; var selectedDownloadIDs: Set<String> = []; var isDownloadsMultiSelectMode = false
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
    func presentSteamLoginForUserAction(context: String) { statusMessage = "login required" }
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
        let stagingRoot = base.appendingPathComponent("staging", isDirectory: true)
        let firstIdentity = try SteamWorkshopLibraryTransaction.stagingLeaseIdentity(
            stagingURL: URL(fileURLWithPath: transport.receipt["stagingPath"] as! String), stagingRoot: stagingRoot)
        transport.receipt["stagingDevice"] = String(firstIdentity.device); transport.receipt["stagingInode"] = String(firstIdentity.inode); transport.receipt["stagingBirthSeconds"] = String(firstIdentity.birthSeconds!); transport.receipt["stagingBirthNanoseconds"] = String(firstIdentity.birthNanoseconds!)
        let secondURL = URL(fileURLWithPath: transport.receipt["secondStagingPath"] as! String)
        if FileManager.default.fileExists(atPath: secondURL.path) {
            let secondIdentity = try SteamWorkshopLibraryTransaction.stagingLeaseIdentity(stagingURL: secondURL, stagingRoot: stagingRoot)
            transport.receipt["secondStagingDevice"] = String(secondIdentity.device); transport.receipt["secondStagingInode"] = String(secondIdentity.inode); transport.receipt["secondStagingBirthSeconds"] = String(secondIdentity.birthSeconds!); transport.receipt["secondStagingBirthNanoseconds"] = String(secondIdentity.birthNanoseconds!)
        }
        transport.jobStoreURL = base.appendingPathComponent("jobs.json")
        let rejectedJobStoreTarget = base.appendingPathComponent("missing-jobstore-target.json")
        if mode == "corrupt-current-jobstore" { try FileManager.default.createSymbolicLink(at: transport.jobStoreURL!, withDestinationURL: rejectedJobStoreTarget) }
        if mode == "missing-staging-ack-capability" { transport.advertisedStagingAcknowledgementCapability = nil }
        if mode == "old-staging-ack-capability" { transport.advertisedStagingAcknowledgementCapability = "download-staging-ack-v1" }
        transport.requireStagingAcknowledgement = mode != "missing-staging-ack-capability" && mode != "old-staging-ack-capability"
        transport.failJobStoreBeforeAllocatedEvent = mode == "staging-save-failure"; transport.rejectStagingAcknowledgementWithIntegrity = mode == "staging-ack-timeout"
        transport.allocatedEventHasWrongAccountEpoch = mode == "allocated-wrong-account-epoch"; transport.allocatedEventOmitsAccountEpoch = mode == "allocated-missing-account-epoch"
        transport.allocatedEventHasWrongBirth = mode == "allocated-wrong-birth"; transport.terminalReceiptHasWrongBirth = mode == "terminal-wrong-birth"
        transport.hold = mode.hasPrefix("ready-update-delete") || ["cancel", "switch", "concurrent-cancel", "concurrent-success",
            "prebind-replacement", "legacy-v4-partial-retry", "allocated-wrong-account-epoch",
            "allocated-missing-account-epoch", "allocated-wrong-birth"].contains(mode)
        transport.replaceStagingBeforeProgress = mode == "prebind-replacement"
        transport.startErrorCode = ["network-failure", "missing-resume-fresh", "busy-retry", "abandon"].contains(mode) ? "network" : mode == "manifest-mismatch" ? "integrity" : mode == "disk-full" ? "diskFull" : nil
        if mode == "legacy-v4-partial-retry" {
            let legacyURL = base.appendingPathComponent("jobs.json")
            let legacyStore = SteamDownloadJobStore(persistenceURL: legacyURL)
            let legacyJob = legacyStore.enqueue(
                workshopItemId: "123456",
                title: "legacy partial",
                accountSteamId: "76561198000000000"
            ).job
            precondition(legacyStore.apply(.started, toID: legacyJob.id) != nil)
            let oldPath = transport.receipt["stagingPath"] as! String
            let oldIdentity = try SteamWorkshopLibraryTransaction.stagingLeaseIdentity(
                stagingURL: URL(fileURLWithPath: oldPath, isDirectory: true),
                stagingRoot: base.appendingPathComponent("staging", isDirectory: true)
            )
            precondition(legacyStore.apply(.stagingAllocated(
                path: oldPath,
                manifestId: transport.receipt["manifestId"] as! String,
                leaseIdentity: oldIdentity
            ), toID: legacyJob.id) != nil)
            var persisted = try JSONSerialization.jsonObject(
                with: Data(contentsOf: legacyURL)
            ) as! [String: Any]
            persisted["version"] = 4
            var jobs = persisted["jobs"] as! [[String: Any]]
            var oldIdentityObject = jobs[0]["stagingLeaseIdentity"] as! [String: Any]
            oldIdentityObject.removeValue(forKey: "birthSeconds")
            oldIdentityObject.removeValue(forKey: "birthNanoseconds")
            jobs[0]["stagingLeaseIdentity"] = oldIdentityObject
            persisted["jobs"] = jobs
            try JSONSerialization.data(withJSONObject: persisted, options: [.sortedKeys])
                .write(to: legacyURL, options: .atomic)
            let oldURL = URL(fileURLWithPath: oldPath, isDirectory: true)
            try FileManager.default.moveItem(
                at: oldURL,
                to: base.appendingPathComponent("legacy-partial-original", isDirectory: true)
            )
            try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: false)
            try Data("replacement".utf8).write(to: oldURL.appendingPathComponent("sentinel"))
        }
        let service = SteamWorkshopService(base: base, transport: transport)
        if try await service.runReadyUpdateDeletionFixtureIfNeeded(mode: mode, transport: transport) { return }
        if mode.hasPrefix("migration-") {
            let library = service.steamDownloadLibraryRootURL
            let legacyName = "11111111-1111-4111-8111-111111111111"
            let legacyContent = library
                .appendingPathComponent(SteamWorkshopLibraryTransaction.versionsName, isDirectory: true)
                .appendingPathComponent(legacyName, isDirectory: true)
                .appendingPathComponent("content", isDirectory: true)
            try FileManager.default.createDirectory(at: legacyContent, withIntermediateDirectories: true)
            let staged = URL(
                fileURLWithPath: transport.receipt["stagingPath"] as! String,
                isDirectory: true
            )
            for name in ["project.json", "index.html"] {
                try Data(contentsOf: staged.appendingPathComponent(name))
                    .write(to: legacyContent.appendingPathComponent(name))
            }
            let legacy = SteamWorkshopLibraryCommit(
                version: 1,
                workshopId: "123456",
                jobId: "legacy-job-1",
                attempt: 1,
                directoryName: legacyName,
                manifestId: "123",
                contentDigest: transport.receipt["contentDigest"] as! String,
                contentType: "web",
                entryPath: "index.html",
                committedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            var snapshot = SteamWorkshopDownloadMetadataSnapshot(
                fetchedAt: legacy.committedAt,
                item: SteamWorkshopBrowserItem(id: "123456", title: "legacy"),
                sourceVideoRelativePath: nil,
                previewRelativePath: nil,
                exportedVideoURL: nil,
                legacyFolderURL: legacyContent
            )
            snapshot.commit = legacy
            try SteamWorkshopLibraryTransaction.publish(
                metadata: JSONEncoder().encode(snapshot),
                itemID: legacy.workshopId,
                libraryRoot: library
            )
            let candidates = try service.loadManagedDownloadSnapshots(requireComplete: true)
            if mode == "migration-cas" {
                var removed = legacy
                removed.removed = true
                var newer = snapshot
                newer.commit = removed
                try SteamWorkshopLibraryTransaction.publish(
                    metadata: JSONEncoder().encode(newer),
                    itemID: legacy.workshopId,
                    libraryRoot: library
                )
            }
            if mode == "migration-capacity" {
                service.reservedLibraryCopyBytesByJobKey["fixture-blocker"] = 0
            }
            var unblock: Task<Void, Error>?
            if mode == "migration-retry" {
                let blocker = library.appendingPathComponent("Web")
                try Data("temporary-blocker".utf8).write(to: blocker)
                unblock = Task.detached {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    try FileManager.default.removeItem(at: blocker)
                }
            }
            service.scheduleLegacyLibraryPublicationMigration(from: candidates)
            guard let migrationTask = service.legacyLibraryPublicationMigrationTask else {
                fatalError("migration task was not scheduled")
            }
            if mode == "migration-capacity" {
                try await Task.sleep(nanoseconds: 150_000_000)
                let waiting = try service.loadManagedDownloadSnapshots(requireComplete: true)["123456"]
                precondition(waiting?.commit == legacy,
                    "migration must wait behind the shared copy-capacity owner")
                service.reservedLibraryCopyBytesByJobKey["fixture-blocker"] = nil
            }
            await migrationTask.value
            if let unblock { try await unblock.value }
            let current = try service.loadManagedDownloadSnapshots(requireComplete: true)["123456"]
            if mode == "migration-cas" {
                precondition(current?.commit?.removed == true && current?.commit?.version == 1,
                    "a newer metadata pointer must win before migration publication")
                precondition(service.reloads == 0)
            } else {
                guard let migrated = current?.commit else { fatalError("missing migrated pointer") }
                precondition(migrated.version == 2 && migrated.workshopId == legacy.workshopId)
                precondition(SteamWorkshopLibraryTransaction.isAvailable(
                    migrated, libraryRoot: library
                ))
                precondition(SteamWorkshopLibraryTransaction.isAvailable(
                    legacy, libraryRoot: library
                ), "migration must not move or delete the previous-current v1 tree")
                let publicDirectories = try FileManager.default.contentsOfDirectory(
                    at: library.appendingPathComponent("Web", isDirectory: true),
                    includingPropertiesForKeys: nil
                ).filter { $0.lastPathComponent.hasPrefix("123456-") }
                precondition(publicDirectories.count == 1,
                    "one service migration must publish exactly one public generation")
                precondition(service.reloads == 1)
            }
            precondition(service.legacyLibraryPublicationMigrationTask == nil)
            precondition(service.reservedLibraryCopyBytesByJobKey.isEmpty)
            await service.steamServiceClient.stop(shutdownTimeout: 0)
            print("EXECUTION PASS: \(mode)")
            return
        }
        service.downloadWorkshopItem(id: "123456", pageTitle: "test")
        if mode == "corrupt-current-jobstore" {
            let preservedJobStoreLink = try FileManager.default.destinationOfSymbolicLink(atPath: transport.jobStoreURL!.path)
            let storeSiblings = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            precondition(!service.downloadJobStore.lastSaveSucceeded && service.downloadJobStore.jobs.isEmpty
                && service.activeDownloadTasks.isEmpty && service.statusMessage == "下载任务无法保存，未开始下载。")
            precondition(!transport.commands.contains { $0["command"] as? String == "startDownload" })
            precondition(preservedJobStoreLink == rejectedJobStoreTarget.path && !FileManager.default.fileExists(atPath: rejectedJobStoreTarget.path)
                && !storeSiblings.contains { $0.lastPathComponent.hasPrefix("jobs.corrupted-") })
            await service.steamServiceClient.stop(shutdownTimeout: 0); print("EXECUTION PASS: \(mode)"); return
        }
        if mode == "missing-staging-ack-capability" || mode == "old-staging-ack-capability" {
            for _ in 0..<100_000 where !service.activeDownloadTasks.isEmpty { await Task.yield() }
            precondition(service.activeDownloadTasks.isEmpty)
            precondition(!transport.commands.contains { $0["command"] as? String == "startDownload" },
                "a helper without the mandatory staging ack capability must never start a download")
            precondition(service.downloadJobStore.jobs.last?.state == .failed)
            let marker = base.appendingPathComponent("library/.mywallpaperx-steam-metadata/123456.json")
            let oldMarker = try String(contentsOf: marker, encoding: .utf8)
            precondition(oldMarker == "OLD READY POINTER")
            await service.steamServiceClient.stop(shutdownTimeout: 0)
            print("EXECUTION PASS: \(mode)")
            return
        }
        while !transport.commands.contains(where: { $0["command"] as? String == "startDownload" }) { await Task.yield() }
        let key = transport.commands.first! ["jobId"] as! String
        if mode == "staging-ack" {
            var observedAcknowledgement = false
            for _ in 0..<100_000 {
                if transport.commands.contains(where: {
                    $0["command"] as? String == "acknowledgeDownloadStaging"
                        && $0["jobId"] as? String == key
                }) {
                    observedAcknowledgement = true
                    break
                }
                await Task.yield()
            }
            precondition(observedAcknowledgement,
                "helper start advanced without a durable staging acknowledgement")
        }
        if mode == "staging-save-failure" {
            var observedCancellation = false
            for _ in 0..<100_000 {
                if transport.commands.contains(where: {
                    $0["command"] as? String == "cancelDownload"
                        && $0["jobId"] as? String == key
                }) {
                    observedCancellation = true
                    break
                }
                await Task.yield()
            }
            precondition(observedCancellation,
                "failed staging persistence did not cancel the helper start")
            precondition(!transport.commands.contains(where: {
                $0["command"] as? String == "acknowledgeDownloadStaging"
            }), "failed staging persistence must never release helper writes")
            transport.restoreJobStoreAfterAllocationFailure()
            try FileManager.default.removeItem(
                at: URL(fileURLWithPath: transport.receipt["stagingPath"] as! String)
            )
            transport.finishHeldCancellation(jobId: key)
        }
        if ["allocated-wrong-account-epoch", "allocated-missing-account-epoch", "allocated-wrong-birth"].contains(mode) {
            while !transport.commands.contains(where: {
                $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
            }) { await Task.yield() }
            precondition(!transport.commands.contains {
                $0["command"] as? String == "acknowledgeDownloadStaging"
            }, "an unscoped or physically mismatched allocated event must never release helper writes")
            precondition(service.downloadJobStore.job(id: key.split(separator: "-").dropLast().joined(separator: "-"))?.stagingPath == nil)
            transport.finishHeldCancellation(jobId: key)
        }
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
        if mode == "prebind-replacement" || mode == "legacy-v4-partial-retry" {
            while !transport.commands.contains(where: {
                $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
            }) { await Task.yield() }
            transport.finishHeldCancellation(jobId: key)
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
        } else if mode == "success" || mode == "staging-ack" {
            precondition(service.downloadError == nil, service.downloadError ?? service.statusMessage)
            let result = try JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: Data(contentsOf: marker))
            precondition(result.commit?.jobId == key && result.commit?.attempt == 1)
            precondition(service.downloadJobStore.jobs.last?.state == .completed && service.reloads == 1)
            precondition(transport.commands.filter { $0["command"] as? String == "startDownload" }.count == 1)
            if mode == "staging-ack" {
                precondition(transport.observedPersistedIdentityBeforeAcknowledgement)
                precondition(transport.commands.filter {
                    $0["command"] as? String == "acknowledgeDownloadStaging"
                }.count == 1)
            }
            let corrupt = marker.deletingLastPathComponent().appendingPathComponent("654321.json")
            try Data("broken-json".utf8).write(to: corrupt)
            precondition(service.managedDownloadSnapshots().keys.sorted() == ["123456"])
            do {
                _ = try service.loadManagedDownloadSnapshots(requireComplete: true)
                fatalError("corrupt metadata must prevent GC, while display retains valid entries")
            } catch {}
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String),
                "successful publication must retire its exact staging lease")
        } else if !["network-failure", "missing-resume-fresh", "busy-retry", "abandon", "publish-failure", "disk-full"].contains(mode) {
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
            if mode == "staging-save-failure" {
                precondition(service.downloadJobStore.jobs.last?.state == .failed
                    && service.downloadJobStore.jobs.last?.stagingPath == nil
                    && service.downloadJobStore.jobs.last?.failureMessage?.isEmpty == false,
                    "persistence failure must remain visible without adopting helper storage")
                precondition(!FileManager.default.fileExists(
                    atPath: transport.receipt["stagingPath"] as! String
                ), "unacknowledged helper lease must be retired without App ownership")
            }
            if mode == "staging-ack-timeout" {
                precondition(service.downloadJobStore.jobs.last?.state == .failed
                    && service.downloadJobStore.jobs.last?.stagingPath == nil
                    && service.downloadJobStore.jobs.last?.stagingLeaseIdentity == nil,
                    "ack timeout must invalidate the helper-deleted recovery lease")
            }
            if mode == "allocated-wrong-account-epoch" || mode == "allocated-missing-account-epoch"
                || mode == "allocated-wrong-birth" {
                precondition(service.downloadJobStore.jobs.last?.state == .failed
                    && service.downloadJobStore.jobs.last?.stagingPath == nil,
                    "unscoped allocated events must not bind durable storage: \(String(describing: service.downloadJobStore.jobs.last))")
            }
            if mode == "terminal-wrong-birth" {
                precondition(service.downloadJobStore.jobs.last?.state == .failed
                    && service.downloadJobStore.jobs.last?.stagingLeaseIdentity?.isComplete == true,
                    "terminal birth mismatch must fail without replacing the allocated identity")
                precondition(FileManager.default.fileExists(
                    atPath: transport.receipt["stagingPath"] as! String
                ), "terminal mismatch must retain attributable staging for explicit recovery")
            }
            if mode == "prebind-replacement" {
                let replacement = URL(
                    fileURLWithPath: transport.receipt["stagingPath"] as! String,
                    isDirectory: true
                )
                precondition(service.downloadJobStore.jobs.last?.stagingPath == nil,
                    "a mismatched first progress event must not bind a lexical staging name")
                let replacementSentinel = try String(
                    contentsOf: replacement.appendingPathComponent("sentinel"),
                    encoding: .utf8
                )
                precondition(replacementSentinel == "replacement",
                    "rejected replacement must never be path-cleaned")
                precondition(FileManager.default.fileExists(
                    atPath: base.appendingPathComponent("original-prebind").path
                ), "the original helper lease remains separately attributable")
            }
            if mode == "legacy-v4-partial-retry" {
                let start = transport.commands.first { $0["command"] as? String == "startDownload" }!
                let payload = start["payload"] as! [String: Any]
                precondition(payload["resumeStagingPath"] == nil
                    && payload["resumeManifestId"] == nil
                    && payload["resumeStagingDevice"] == nil
                    && payload["resumeStagingInode"] == nil
                    && payload["resumeStagingBirthSeconds"] == nil
                    && payload["resumeStagingBirthNanoseconds"] == nil,
                    "device+inode-only v4 partial must start a fresh helper lease")
                let replacement = URL(
                    fileURLWithPath: transport.receipt["stagingPath"] as! String,
                    isDirectory: true
                )
                let sentinel = try String(
                    contentsOf: replacement.appendingPathComponent("sentinel"),
                    encoding: .utf8
                )
                precondition(sentinel == "replacement")
                precondition(FileManager.default.fileExists(
                    atPath: base.appendingPathComponent("legacy-partial-original").path
                ))
            }
        } else if ["network-failure", "missing-resume-fresh", "busy-retry", "abandon", "publish-failure"].contains(mode) {
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
            if mode == "abandon" {
                let sibling = service.steamDownloadStagingRootURL.appendingPathComponent("keep.txt")
                try Data("keep".utf8).write(to: sibling)
                service.discardFailedDownload(jobID: failure.id)
                await service.terminalDownloadCleanupTask?.value
                precondition(!FileManager.default.fileExists(atPath: failure.stagingPath!))
                precondition(FileManager.default.fileExists(atPath: sibling.path))
                let after = SteamDownloadJobStore(persistenceURL: base.appendingPathComponent("jobs.json"))
                precondition(after.failedJob(forWorkshopItemId: "123456", accountSteamId: failure.accountSteamId) == nil)
                precondition(service.downloads.isEmpty)
                await service.steamServiceClient.stop(shutdownTimeout: 0)
                print("EXECUTION PASS: \(mode)")
                return
            }
            if mode == "publish-failure" {
                precondition(FileManager.default.fileExists(atPath: failure.stagingPath!))
                let index = marker.deletingLastPathComponent()
                try FileManager.default.removeItem(at: index) // fixture symlink only
                try FileManager.default.moveItem(at: base.appendingPathComponent("outside-index"), to: index)
            }
            if mode == "missing-resume-fresh" {
                try FileManager.default.removeItem(atPath: failure.stagingPath!)
                transport.receipt["stagingPath"] = transport.receipt["secondStagingPath"]
                transport.receipt["stagingDevice"] = transport.receipt["secondStagingDevice"]; transport.receipt["stagingInode"] = transport.receipt["secondStagingInode"]
                transport.receipt["stagingBirthSeconds"] = transport.receipt["secondStagingBirthSeconds"]; transport.receipt["stagingBirthNanoseconds"] = transport.receipt["secondStagingBirthNanoseconds"]
            }
            transport.startErrorCode = nil
            if mode == "busy-retry" {
                service.reservedLibraryCopyBytesByJobKey["fixture-other"] = 0
                service.downloadWorkshopItem(id: "123456", pageTitle: "test")
                let queued = service.downloadJobStore.job(id: failure.id)!
                precondition(queued.state == .queued && queued.attempt == 1 && queued.stagingPath == failure.stagingPath)
                precondition(service.downloadJobStore.jobs.count == 1
                    && transport.commands.filter { $0["command"] as? String == "startDownload" }.count == 1)
                service.reservedLibraryCopyBytesByJobKey.removeAll()
            }
            service.downloadWorkshopItem(id: "123456", pageTitle: "test")
            while !service.activeDownloadTasks.isEmpty { await Task.yield() }
            let starts = transport.commands.filter { $0["command"] as? String == "startDownload" }
            precondition(starts.count == 2 && starts.last?["jobId"] as? String == failure.id + "-2",
                "explicit retry must keep logical job identity and increment attempt")
            let retryPayload = starts.last?["payload"] as? [String: Any]
            if mode == "missing-resume-fresh" {
                precondition(retryPayload?["resumeStagingPath"] == nil
                    && retryPayload?["resumeManifestId"] == nil
                    && retryPayload?["resumeStagingDevice"] == nil
                    && retryPayload?["resumeStagingInode"] == nil
                    && retryPayload?["resumeStagingBirthSeconds"] == nil
                    && retryPayload?["resumeStagingBirthNanoseconds"] == nil,
                    "a missing persisted lease must restart fresh on the same explicit retry")
            } else {
                precondition(retryPayload?["resumeStagingPath"] as? String == failure.stagingPath
                    && retryPayload?["resumeManifestId"] as? String == failure.stagingManifestId
                    && retryPayload?["resumeStagingDevice"] as? String
                        == failure.stagingLeaseIdentity.map { String($0.device) }
                    && retryPayload?["resumeStagingInode"] as? String
                        == failure.stagingLeaseIdentity.map { String($0.inode) }
                    && retryPayload?["resumeStagingBirthSeconds"] as? String
                        == failure.stagingLeaseIdentity?.birthSeconds.map(String.init)
                    && retryPayload?["resumeStagingBirthNanoseconds"] as? String
                        == failure.stagingLeaseIdentity?.birthNanoseconds.map(String.init),
                    "explicit retry must send the complete descriptor-bound staging identity")
            }
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
