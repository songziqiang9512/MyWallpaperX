import Foundation

// No AppKit or account process is created. Only the modal response, auth IO
// and download leaves are controlled; the entire service entry below is real.
@MainActor final class NSAlert {
    enum Response { case alertFirstButtonReturn, alertSecondButtonReturn }
    static var response = Response.alertFirstButtonReturn
    static var onModal: (() -> Void)?
    static var shown = 0
    var messageText = "", informativeText = ""
    func addButton(withTitle: String) {}
    func runModal() -> Response {
        Self.shown += 1
        Self.onModal?()
        return Self.response
    }
    static func reset() { response = .alertFirstButtonReturn; onModal = nil; shown = 0 }
}
@MainActor func runAppAlert(_ alert: NSAlert) -> NSAlert.Response { alert.runModal() }
@MainActor final class SignoutAuth {
    enum Phase { case online, idle }
    final class Client { var accountEpoch: UInt64 = 7 }
    let client = Client()
    var steamId: String? = "A"
    var phase = Phase.online
    var accountName = "Original account"
    var cleared = true
    var holdsReply = false
    var reply: CheckedContinuation<Void, Never>?
    var calls = 0
    var returned = false
    func replaceAccount(_ id: String) { client.accountEpoch += 1; steamId = id; phase = .online }
    func signOut() async -> Bool {
        calls += 1
        client.accountEpoch += 1
        steamId = nil
        phase = .idle
        if holdsReply { await withCheckedContinuation { reply = $0 } }
        returned = true
        return cleared
    }
}
@MainActor final class SignoutJobs {
    var queuedCount = 0
    var calls = 0
    var lastSaveSucceeded = true
    func cancelAll() -> [String] { calls += 1; queuedCount = 0; return ["queued"] }
}
@MainActor final class SignoutService {
    let steamAuth = SignoutAuth()
    let downloadJobStore = SignoutJobs()
    var activeDownloadTasks: [String: Bool] = [:]
    var pausedDownloadItemIDs: Set<String> = ["paused"]
    var steamJobItemPayloads = ["queued": "payload"]
    var removed: [String] = []
    var cancellations = 0
    var statusMessage = "Original status"
    var downloadError: String?
    func cancelDownloadImmediately(showFeedback: Bool) { cancellations += 1; activeDownloadTasks.removeAll() }
    func removeTransientRecord(id: String) { removed.append(id) }
    // PRODUCTION_SIGNOUT
}

@main enum LibraryToolbarSignoutChecks {
    @MainActor static func main() async throws {
        var checks: [String: Bool] = [:]
        func settle() async { for _ in 0..<8 { await Task.yield() } }
        func wait(_ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(1)
            while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
            return condition()
        }
        func untouched(_ service: SignoutService) -> Bool {
            service.steamAuth.calls == 0 && service.cancellations == 0 && service.downloadJobStore.calls == 0
                && service.pausedDownloadItemIDs == ["paused"] && service.steamJobItemPayloads == ["queued": "payload"]
                && service.removed.isEmpty && service.statusMessage == "Original status" && service.downloadError == nil
        }

        NSAlert.reset()
        let duringConfirmation = SignoutService()
        duringConfirmation.activeDownloadTasks = ["running": true]
        NSAlert.onModal = { duringConfirmation.steamAuth.replaceAccount("B") }
        duringConfirmation.signOutEverywhere()
        await settle()
        checks["modal-account-change-cannot-cancel-downloads-or-sign-out-the-new-account"] = NSAlert.shown == 1
            && untouched(duringConfirmation) && duringConfirmation.steamAuth.steamId == "B"
            && duringConfirmation.activeDownloadTasks == ["running": true]

        NSAlert.reset()
        let beforeTask = SignoutService()
        beforeTask.signOutEverywhere()
        beforeTask.steamAuth.replaceAccount("B")
        await settle()
        checks["task-admission-rechecks-the-original-account-before-any-side-effect"] = NSAlert.shown == 0
            && untouched(beforeTask) && beforeTask.steamAuth.steamId == "B"

        NSAlert.reset()
        let cancelled = SignoutService()
        cancelled.downloadJobStore.queuedCount = 1
        NSAlert.response = .alertSecondButtonReturn
        cancelled.signOutEverywhere()
        await settle()
        checks["modal-cancel-retains-account-queue-and-all-source-facts"] = NSAlert.shown == 1
            && untouched(cancelled) && cancelled.downloadJobStore.queuedCount == 1 && cancelled.steamAuth.steamId == "A"

        NSAlert.reset()
        let accepted = SignoutService()
        accepted.activeDownloadTasks = ["running": true]
        accepted.downloadJobStore.queuedCount = 1
        NSAlert.onModal = { accepted.steamAuth.accountName = "Updated same account" }
        accepted.signOutEverywhere()
        let acceptedFinished = await wait { accepted.statusMessage == "已退出 Steam 登录。" }
        checks["same-account-confirmation-and-metadata-echo-execute-normal-signout-once"] = acceptedFinished
            && NSAlert.shown == 1 && accepted.steamAuth.calls == 1 && accepted.steamAuth.client.accountEpoch == 8
            && accepted.steamAuth.steamId == nil && accepted.activeDownloadTasks.isEmpty && accepted.cancellations == 1
        checks["normal-signout-keeps-original-download-owner-cleanup"] = accepted.downloadJobStore.calls == 1
            && accepted.downloadJobStore.queuedCount == 0 && accepted.pausedDownloadItemIDs.isEmpty
            && accepted.removed == ["queued"] && accepted.steamJobItemPayloads.isEmpty

        NSAlert.reset()
        let immediate = SignoutService()
        immediate.signOutEverywhere()
        let immediateFinished = await wait { immediate.statusMessage == "已退出 Steam 登录。" }
        checks["no-task-account-still-signs-out-without-a-confirmation"] = immediateFinished
            && NSAlert.shown == 0 && immediate.steamAuth.calls == 1 && immediate.cancellations == 1

        NSAlert.reset()
        let repeated = SignoutService()
        repeated.signOutEverywhere(); repeated.signOutEverywhere()
        let repeatedFinished = await wait { repeated.statusMessage == "已退出 Steam 登录。" }
        await settle()
        checks["two-same-stack-signout-requests-cannot-run-cleanup-twice"] = repeatedFinished
            && repeated.steamAuth.calls == 1 && repeated.cancellations == 1 && repeated.downloadJobStore.calls == 1

        NSAlert.reset()
        let late = SignoutService()
        late.steamAuth.holdsReply = true
        late.signOutEverywhere()
        let waiting = await wait { late.steamAuth.reply != nil }
        checks["logout-await-precondition-uses-the-real-original-account-retirement"] = waiting
            && late.steamAuth.client.accountEpoch == 8 && late.steamAuth.steamId == nil && late.steamAuth.calls == 1
        late.steamAuth.replaceAccount("B")
        // B subsequently logs out too. An idle phase alone cannot authorize
        // A's delayed completion to replace B's current status.
        late.steamAuth.client.accountEpoch += 1; late.steamAuth.steamId = nil; late.steamAuth.phase = .idle
        late.statusMessage = "New account status"
        late.steamAuth.reply?.resume(); late.steamAuth.reply = nil
        let returned = await wait { late.steamAuth.returned }
        await settle()
        checks["late-logout-result-cannot-overwrite-a-later-idle-account-status"] = returned
            && late.statusMessage == "New account status" && late.steamAuth.calls == 1 && late.cancellations == 1

        NSAlert.reset()
        let failedTokenClear = SignoutService()
        failedTokenClear.steamAuth.cleared = false
        failedTokenClear.signOutEverywhere()
        let tokenResult = await wait { failedTokenClear.statusMessage == "已退出并禁止自动恢复，但 Keychain 中的旧令牌清理失败。" }
        checks["normal-token-clear-failure-retains-the-original-actionable-status"] = tokenResult
            && failedTokenClear.steamAuth.calls == 1

        NSAlert.reset()
        let failedQueueSave = SignoutService()
        failedQueueSave.downloadJobStore.lastSaveSucceeded = false
        failedQueueSave.signOutEverywhere()
        let queueFinished = await wait { failedQueueSave.statusMessage == "已退出 Steam 登录。" }
        checks["queue-save-error-is-not-hidden-by-successful-account-signout"] = queueFinished
            && failedQueueSave.downloadError == "取消队列未能保存；任务执行已停止，请检查磁盘后重试。"
            && failedQueueSave.steamAuth.calls == 1

        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
