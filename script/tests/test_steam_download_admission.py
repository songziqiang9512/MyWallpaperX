"""Execute the actual service admission methods against the real JobStore, without runtime/UI I/O."""
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core"


class SteamDownloadAdmissionTests(unittest.TestCase):
    def test_explicit_signed_out_action_opens_login_without_banner(self):
        service = (CORE / "SteamWorkshopService.swift").read_text()
        action = service[service.index("    func presentSteamLoginForUserAction"):]
        action = action[:action.index("    // MARK:")]
        self.assertIn('statusMessage = ""', action)
        self.assertIn("showLoginPanel()", action)
        browser = (ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserView.swift").read_text()
        self.assertNotIn("loginGuidanceBanner", browser)
        self.assertNotIn("showLoginPanel()", browser)

    def test_service_admission(self):
        source = (CORE / "SteamWorkshopService+Downloads.swift").read_text()
        names = ["downloadWorkshopItem", "downloadAdmissionAccount", "canRequestDownload",
                 "startDownloadRequest", "enqueueDownloadRequest", "processNextQueuedDownloadIfPossible"]
        methods = []
        for name in names:
            start = re.search(r"^    (?:private )?func " + name + r"\(", source, re.M)
            self.assertIsNotNone(start, name)
            end = source.index("\n    }", start.start()) + len("\n    }")
            methods.append(source[start.start():end])
        stub = r'''
import Foundation
struct SteamWorkshopBrowserItem {}
struct SteamWorkshopPendingDownloadRequest {
    let id: String; let pageTitle: String?; let item: SteamWorkshopBrowserItem?
}
@MainActor final class Auth {
    var steamId: String?
    var isOnline: Bool { steamId != nil }
}
@MainActor final class SteamWorkshopService {
    let steamAuth = Auth()
    let downloadJobStore: SteamDownloadJobStore
    var statusMessage = ""
    let maximumConcurrentDownloads = 2
    var activeDownloadItemIDs: Set<String> = []
    var activeDownloadJobKeysByItemID: [String: String] = [:]
    var activeDownloadTasks: [String: Task<Void, Never>] = [:]
    var reservedLibraryCopyBytesByJobKey: [String: Int64] = [:]
    var isLoginSheetPresented = false
    enum Phase { case credentials, awaitingGuardCode }
    var authPhase = Phase.credentials
    var isAuthenticating = false
    var isDownloadWorkflowBusy = false
    var steamJobItemPayloads: [String: SteamWorkshopBrowserItem] = [:]
    var started = 0
    var projected = 0
    var guidance = 0
    init(_ url: URL) { downloadJobStore = SteamDownloadJobStore(persistenceURL: url) }
    func presentSteamLoginForUserAction(context: String) { guidance += 1; isLoginSheetPresented = true }
    func browserItemForDownload(id: String) -> SteamWorkshopBrowserItem? { nil }
    func appendSteamAuthDebugLog(_ text: String) {}
    func isQueuedDownloadRequest(id: String) -> Bool { downloadJobStore.isQueuedOrRunning(workshopItemId: id) }
    func beginDownloadWorkflow(_ request: SteamWorkshopPendingDownloadRequest) {
        started += 1
        activeDownloadItemIDs.insert(request.id)
        activeDownloadTasks[request.id] = Task {}
    }
    enum Status { case queued }
    func upsertTransientRecord(id: String, title: String, status: Status, sizeText: String) { projected += 1 }
    func downloadStatusSizeText(for id: String) -> String { "" }
}
extension SteamWorkshopService {
METHODS
    func enqueueDirect() { enqueueDownloadRequest(id: "123456", pageTitle: nil, item: SteamWorkshopBrowserItem()) }
    func resumeQueue() { processNextQueuedDownloadIfPossible() }
}
@main struct Harness {
    @MainActor static func main() {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        func service(_ name: String) -> SteamWorkshopService { SteamWorkshopService(base.appendingPathComponent(name)) }
        for busy in [false, true] {
            let s = service("signed-out-\(busy).json")
            s.isDownloadWorkflowBusy = busy
            s.downloadWorkshopItem(id: "123456")
            s.enqueueDirect()
            s.startDownloadRequest(.init(id: "123456", pageTitle: nil, item: nil))
            precondition(s.downloadJobStore.jobs.isEmpty && s.started == 0 && s.projected == 0)
            precondition(s.steamJobItemPayloads.isEmpty && s.guidance == 3 && s.isLoginSheetPresented)
            s.steamAuth.steamId = "A"
            s.resumeQueue()
            precondition(s.started == 0, "login cannot revive a rejected click")
        }
        let queued = service("queued.json")
        queued.steamAuth.steamId = "A"; queued.isDownloadWorkflowBusy = true
        queued.activeDownloadItemIDs = ["999999"]
        queued.activeDownloadTasks = ["busy-a": Task {}, "busy-b": Task {}]
        queued.downloadWorkshopItem(id: "123456")
        queued.downloadWorkshopItem(id: "123456")
        precondition(queued.downloadJobStore.jobs.count == 1 && queued.projected == 1)
        precondition(queued.downloadJobStore.jobs[0].accountSteamId == "A")
        // Simulate a recovered queue (no executor). Signed-out and another account cannot pop it.
        queued.steamAuth.steamId = nil
        queued.activeDownloadItemIDs.removeAll()
        queued.activeDownloadTasks.removeAll()
        queued.resumeQueue()
        precondition(queued.downloadJobStore.jobs[0].state == .queued)
        queued.steamAuth.steamId = "B"
        queued.resumeQueue()
        precondition(queued.started == 0)
        queued.startDownloadRequest(.init(id: "123456", pageTitle: nil, item: nil))
        precondition(queued.started == 0, "direct start cannot adopt another account's job")
        queued.steamAuth.steamId = "A"
        queued.resumeQueue()
        precondition(queued.started == 1 && queued.downloadJobStore.jobs[0].attempt == 1)
        let immediate = service("immediate.json")
        immediate.steamAuth.steamId = "A"
        immediate.downloadWorkshopItem(id: "654321")
        immediate.downloadWorkshopItem(id: "654322")
        immediate.downloadWorkshopItem(id: "654323")
        precondition(immediate.started == 2 && immediate.activeDownloadTasks.count == 2,
            "started=\(immediate.started) active=\(immediate.activeDownloadTasks.count) states=\(immediate.downloadJobStore.jobs.map { $0.state.rawValue })")
        precondition(immediate.downloadJobStore.jobs[0].accountSteamId == "A")
        precondition(immediate.downloadJobStore.activeJob(forWorkshopItemId: "654323")?.state == .queued,
            "third job must remain queued behind the two-slot executor")
        print("Download admission: signed-out idle/busy/direct entry, no login replay, dedup, account isolation and two-slot cap PASS")
    }
}
'''.replace("METHODS", "\n".join(methods))
        with tempfile.TemporaryDirectory(prefix="mwx-steam-admission-") as directory:
            root = pathlib.Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(stub)
            binary = root / "admission"
            dependencies = [
                ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift",
                ROOT / "MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift",
                *[CORE / name for name in ("SteamServiceProtocol.swift", "SteamServiceClient.swift",
                    "SteamWorkshopQueryClient.swift", "SteamWorkshopLibraryTransaction.swift")],
            ]
            subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, dependencies), str(CORE / "SteamWorkshopJobStore.swift"),
                            str(harness), "-o", str(binary)], check=True, timeout=120)
            subprocess.run([str(binary), directory], check=True, timeout=15)


if __name__ == "__main__":
    unittest.main()
