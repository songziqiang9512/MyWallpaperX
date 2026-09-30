import Foundation

final class FakeSteamTransport: SteamServiceTransporting {
    var isRunning = false
    var onOutput: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?
    var readyOnStart = true
    var replyOnSend = true
    var sends = 0
    var requests: [[String: Any]] = []
    var terminated = false
    var startThrows = false
    var advertisedCapabilities = [
        SteamServiceProtocol.stagingAcknowledgementCapability,
        SteamServiceProtocol.trendDaysCapability,
        SteamServiceProtocol.cdnDownloadCapability,
    ]
    var staleTermination: ((Int32) -> Void)?
    func start() throws {
        if startThrows {
            throw NSError(domain: "SteamServiceClientLifecycleHarness", code: 1)
        }
        isRunning = true
        staleTermination = onTermination
        if readyOnStart {
            emit([
                "v": 1, "type": "ready", "protocol": 1, "helperVersion": "0.1.0",
                "capabilities": advertisedCapabilities,
            ])
        }
    }
    func emit(_ frame: [String: Any]) {
        var data = try! JSONSerialization.data(withJSONObject: frame)
        data.append(10)
        onOutput?(data)
    }
    func send(_ data: Data) -> Bool {
        sends += 1
        let request = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        requests.append(request)
        if replyOnSend {
            emit(["v": 1, "type": "result", "requestId": request["requestId"]!, "ok": true])
        }
        return true
    }
    func closeInput() {}
    func terminate() { isRunning = false; terminated = true }
    func scheduleForcedTermination(after delay: TimeInterval) {}
    func crash(exitStatus: Int32 = 9) {
        isRunning = false
        onTermination?(exitStatus)
    }
}

/// 空闲回收的可注入计时：不真实延时；`fire()` 手动触发一次已调度的评估。
@MainActor
final class FakeSteamIdleReapTiming: SteamIdleReapTiming {
    private var pendingHandler: (@MainActor () -> Void)?
    private(set) var scheduledDelays: [TimeInterval] = []

    var hasPendingEvaluation: Bool { pendingHandler != nil }

    func schedule(after delay: TimeInterval, _ handler: @escaping @MainActor () -> Void) {
        scheduledDelays.append(delay)
        pendingHandler = handler
    }

    func cancelScheduled() { pendingHandler = nil }

    func fire() {
        guard let handler = pendingHandler else {
            fatalError("no scheduled idle-reap evaluation to fire")
        }
        pendingHandler = nil
        handler()
    }
}

@main struct SteamServiceClientLifecycleHarness {
    @MainActor static func main() async throws {
        try helperLocationLifecycle()
        let first = FakeSteamTransport()
        let client = SteamServiceClient(executablePath: "/fake", transportFactory: { _ in first })
        let response = try await client.request(command: "queryBrowse")
        precondition(response.ok == true && first.sends == 1, "cold public request/synchronous reply")

        let incompatible = FakeSteamTransport()
        incompatible.advertisedCapabilities = []
        let incompatibleClient = SteamServiceClient(
            executablePath: "/fake", transportFactory: { _ in incompatible })
        do {
            _ = try await incompatibleClient.request(
                command: "queryBrowse", requiredCapability: SteamServiceProtocol.trendDaysCapability)
            fatalError("missing required capability accepted")
        } catch SteamServiceClient.RequestError.incompatibleProtocol {
            precondition(incompatible.sends == 0, "capability rejection must precede wire send")
        }

        first.replyOnSend = false
        let pending = Task { try await client.request(command: "ping", timeout: nil) }
        await Task.yield()
        pending.cancel()
        do { _ = try await pending.value; fatalError("cancelled request succeeded") }
        catch { precondition(error is CancellationError || error as? SteamServiceClient.RequestError == .cancelled) }
        let beforeCapacity = first.sends
        var held: [Task<SteamServiceFrame, Error>] = []
        for _ in 0..<SteamServiceProtocol.maxPendingRequests {
            held.append(Task { try await client.request(command: "ping", timeout: nil) })
        }
        while first.sends < beforeCapacity + SteamServiceProtocol.maxPendingRequests { await Task.yield() }
        do { _ = try await client.request(command: "overflow"); fatalError("capacity exceeded") }
        catch SteamServiceClient.RequestError.helperError(let code, _) { precondition(code == "rateLimited") }
        first.replyOnSend = true
        _ = try await client.request(command: "cancelDownload")
        first.replyOnSend = false
        await client.stop(shutdownTimeout: 0)
        for task in held { _ = try? await task.value }

        let oversized = FakeSteamTransport()
        let limited = SteamServiceClient(executablePath: "/fake", maximumRestartAttempts: 0,
                                        transportFactory: { _ in oversized })
        _ = try await limited.start()
        oversized.onOutput?(Data((String(repeating: "x", count: SteamServiceProtocol.maxFrameBytes + 1) + "\n").utf8))
        precondition(oversized.terminated && limited.currentIdentity == nil, "complete overlong frame")

        let old = FakeSteamTransport()
        old.readyOnStart = false
        let replacement = FakeSteamTransport()
        var starts = 0
        let restarting = SteamServiceClient(executablePath: "/fake", handshakeTimeout: 0.02,
            transportFactory: { _ in starts += 1; return starts == 1 ? old : replacement })
        _ = try? await restarting.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(old.terminated && restarting.currentIdentity != nil, "teardown before restart")
        old.staleTermination?(9)
        precondition(restarting.currentIdentity != nil, "old termination cannot tear down new session")
        await restarting.stop(shutdownTimeout: 0)
        try await explicitStartDuringBackoff()
        try await publicCrashRestartLifecycle()
        try await authenticationLifecycle()
        try await accountRouteLifecycle()
        try await stagedReceiptLifecycle()
        commandTaxonomyConformance()
        try await helperIdleReapingLifecycle()
        print("Steam client lifecycle: cold start, synchronous reply, cancellation, frame limit, timeout teardown, crash restart, stale callback PASS")
    }

    // MARK: - commands.json taxonomy conformance（fixture 做双端相等锚）

    @MainActor static func commandTaxonomyConformance() {
        // #filePath = <repo>/script/tests/fixtures/SteamServiceClientLifecycleHarness.swift
        var repoRoot = (#filePath as NSString).deletingLastPathComponent // …/script/tests/fixtures
        for _ in 0..<3 {
            repoRoot = (repoRoot as NSString).deletingLastPathComponent
        }
        let fixtureURL = URL(fileURLWithPath: (repoRoot as NSString)
            .appendingPathComponent("script/tests/fixtures/steam-protocol/commands.json"))
        let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
        let commands = root["commands"] as! [String: [String: Bool]]
        func fixtureSet(_ property: String) -> Set<String> {
            Set(commands.filter { $0.value[property] == true }.keys)
        }
        func check(_ name: String, _ ok: Bool, _ detail: [String] = []) {
            precondition(ok, "taxonomy conformance failed: \(name)"
                + (detail.isEmpty ? "" : ": \(detail)"))
        }
        check("swift-command-taxonomy-shape",
              commands.count == 18
                  && commands.values.allSatisfy {
                      Set($0.keys) == ["control", "asyncDispatch", "helperEpochEntryGate",
                                       "swiftAccountScoped", "anonymousRecoverable"]
                  })
        check("swift-control-commands-match-fixture",
              fixtureSet("control") == SteamServiceClient.controlCommands,
              fixtureSet("control").symmetricDifference(SteamServiceClient.controlCommands).sorted())
        check("swift-account-scoped-commands-match-fixture",
              fixtureSet("swiftAccountScoped") == SteamServiceClient.accountScopedCommands,
              fixtureSet("swiftAccountScoped")
                  .symmetricDifference(SteamServiceClient.accountScopedCommands).sorted())
        check("swift-anonymous-recoverable-match-fixture",
              fixtureSet("anonymousRecoverable") == SteamServiceClient.anonymousReadCommands,
              fixtureSet("anonymousRecoverable")
                  .symmetricDifference(SteamServiceClient.anonymousReadCommands).sorted())
        let swiftKnownCommands = SteamServiceClient.controlCommands
            .union(SteamServiceClient.accountScopedCommands)
            .union(SteamServiceClient.anonymousReadCommands)
            .union(["ping"])
        check("swift-command-universe-covers-fixture",
              Set(commands.keys) == swiftKnownCommands,
              Set(commands.keys).symmetricDifference(swiftKnownCommands).sorted())
        print("Command taxonomy: fixture equality anchors (control/accountScoped/anonymousRecoverable/universe) PASS")
    }

    // MARK: - helper 空闲回收（fake transport + fake scheduler）

    @MainActor static func helperIdleReapingLifecycle() async throws {
        var virtualNow = Date(timeIntervalSince1970: 1_000_000)
        var transports: [FakeSteamTransport] = []
        let client = SteamServiceClient(
            executablePath: "/fake",
            transportFactory: { _ in
                let transport = FakeSteamTransport()
                transport.replyOnSend = false
                transports.append(transport)
                return transport
            },
            clock: { virtualNow })
        let route = SteamAuthRoute(client: client, persistence: .init(
            remember: { false }, setRemember: { _ in }, setRestoreAuthorized: { _ in },
            save: { _ in false }, delete: { true }, saveMetadata: { _ in }, clearMetadata: {}
        ))
        let jobStoreDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-steam-reap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: jobStoreDirectory) }
        let jobStore = SteamDownloadJobStore(
            persistenceURL: jobStoreDirectory.appendingPathComponent("jobs-v5.json"),
            now: { virtualNow })
        // 浏览面板挂载计数：与产品 owner（SteamWorkshopService
        // .browsePanelAttachmentCount）同一转移规则——初始 0，只由进窗/出窗事件
        // 增减，无合成复位；门表达式同产品装配（计数为 0 才算浏览休眠）。
        var browsePanelAttachments = 0
        var hasActiveDownloadTasks = false
        let timing = FakeSteamIdleReapTiming()
        let reaper = SteamHelperIdleReaper(
            idleTimeout: 600, pollInterval: 60,
            now: { virtualNow },
            timing: timing,
            gates: .init(
                helperQuiet: { client.isReadyAndQuiet },
                accountDormant: { route.isDormantForHelperReaping },
                downloadsDormant: { !hasActiveDownloadTasks && jobStore.activeJobs.isEmpty },
                browseDormant: { browsePanelAttachments == 0 }),
            lastActivity: { client.lastRequestActivity },
            reap: { @MainActor in await client.stop(shutdownTimeout: 0.05) })
        reaper.begin()
        precondition(timing.hasPendingEvaluation, "begin must arm the first poll")

        func fireAndAssertStillReady(_ gate: String) async {
            precondition(timing.hasPendingEvaluation)
            timing.fire()
            if case .ready = client.state {} else {
                fatalError("active \(gate) must suppress reaping (state \(client.state))")
            }
        }

        _ = try await client.start()
        precondition(client.isReadyAndQuiet && route.isDormantForHelperReaping)

        // 门 1：浏览面板开着不回收（进窗事件使挂载计数 > 0）。
        browsePanelAttachments += 1 // viewDidMoveToWindow: attached
        virtualNow = virtualNow.addingTimeInterval(601)
        await fireAndAssertStillReady("browse panel")
        browsePanelAttachments -= 1 // viewDidMoveToWindow: detached

        // 门 2：在途 pending 请求（helper 非静默）。
        transports.last!.replyOnSend = false
        let held = Task { try await client.request(command: "ping", timeout: nil) }
        while transports.last!.sends == 0 { await Task.yield() }
        virtualNow = virtualNow.addingTimeInterval(601)
        await fireAndAssertStillReady("pending request")
        held.cancel()
        while !client.isReadyAndQuiet { await Task.yield() }
        transports.last!.replyOnSend = true

        // 门 3：登录态绝不回收。
        try await driveLogin(route: route, client: client, transports: transports)
        precondition(route.isOnline && !route.isDormantForHelperReaping)
        virtualNow = virtualNow.addingTimeInterval(601)
        await fireAndAssertStillReady("signed-in account")
        await route.signOut()
        while !route.isDormantForHelperReaping { await Task.yield() }

        // 门 4：进行中认证（connecting 阶段）。
        let authTransport = transports.last!
        authTransport.replyOnSend = false
        let authBaseline = authTransport.requests.count
        let authAttempt = Task { try await route.loginQR() }
        while authTransport.requests.count <= authBaseline {
            await Task.yield()
        }
        precondition(route.phase == .connecting, "in-progress auth must hold the account gate")
        virtualNow = virtualNow.addingTimeInterval(601)
        await fireAndAssertStillReady("in-progress authentication")
        route.cancelPendingAuthentication()
        _ = try? await authAttempt.value
        while !route.isDormantForHelperReaping { await Task.yield() }
        // 显式收口取消请求，避免孤儿 pending 把静默信号拖到真实 30s 超时。
        while authTransport.requests
            .first(where: { $0["command"] as? String == "cancelAuthentication" }) == nil {
            await Task.yield()
        }
        if let cancelRequest = authTransport.requests
            .last(where: { $0["command"] as? String == "cancelAuthentication" }) {
            authTransport.emit(["v": 1, "type": "result", "requestId": cancelRequest["requestId"]!, "ok": true])
        }
        while !client.isReadyAndQuiet { await Task.yield() }
        authTransport.replyOnSend = true

        // 门 5：活动下载作业（JobStore 实际状态）。
        let (queued, _) = jobStore.enqueue(
            workshopItemId: "654321", title: "ReapFixture", accountSteamId: "76561198000000000")
        precondition(jobStore.apply(.started, toID: queued.id) != nil)
        hasActiveDownloadTasks = true
        virtualNow = virtualNow.addingTimeInterval(601)
        await fireAndAssertStillReady("active download job")
        hasActiveDownloadTasks = false
        precondition(jobStore.cancel(id: queued.id) != nil)

        // 门 6：闲置龄期不足（最近一次出站请求 < idleTimeout）。
        _ = try await client.request(command: "ping")
        virtualNow = virtualNow.addingTimeInterval(599)
        await fireAndAssertStillReady("idle age below timeout")

        print("REAP")
        // 全门满足：回收触发，复用 stop() 通道进入 terminated。
        virtualNow = virtualNow.addingTimeInterval(2)
        timing.fire()
        let reapDeadline = Date().addingTimeInterval(2)
        while client.state != .terminated && Date() < reapDeadline { await Task.yield() }
        precondition(client.state == .terminated, "all gates satisfied must reap the helper")
        precondition(transports.count == 1 && transports[0].terminated, "reap must stop the live transport")
        reaper.end()

        // 等待指定序号 transport 上出现指定命令的出站请求。
        func waitForRequest(_ command: String, index: Int) async -> [String: Any] {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if transports.count >= index,
                   let request = transports[index - 1].requests
                       .first(where: { $0["command"] as? String == command }) {
                    return request
                }
                await Task.yield()
            }
            fatalError("no \(command) request observed on transport #\(index)")
        }

        // 回收后：匿名读透明重启（client 内建 anonymousReadCommands 恢复，非扩大）。
        let browse = Task { try await client.request(command: "queryBrowse") }
        let browseRequest = await waitForRequest("queryBrowse", index: 2)
        transports.last!.emit(["v": 1, "type": "result", "ok": true,
                               "requestId": browseRequest["requestId"]!])
        let browseFrame = try await browse.value
        precondition(transports.count == 2 && browseFrame.ok == true && client.currentIdentity != nil,
                     "anonymous read must transparently restart a reaped helper")

        // 回收后：订阅意图经 owner（ensureHelperStarted）显式重启并成功。
        await client.stop(shutdownTimeout: 0)
        transports.last!.replyOnSend = false
        let query = SteamWorkshopQueryClient(client: client)
        let states = Task { try await query.subscriptionStates(ids: ["123456"]) }
        let statesRequest = await waitForRequest("querySubscriptionStates", index: 3)
        transports.last!.emit(["v": 1, "type": "result", "ok": true,
                               "requestId": statesRequest["requestId"]!,
                               "accountEpoch": client.accountEpoch,
                               "data": ["states": ["123456": true]]])
        let statesResult = try await states.value
        precondition(statesResult == ["123456": true],
                     "subscription intent must recover a reaped helper at its owner")

        // 回收后：下载意图成功（startDownload 意图入口显式重启并取得合法凭证）。
        await client.stop(shutdownTimeout: 0)
        let base = "/private/tmp/reap-fixture" // protocol fixture only, no disk I/O
        let path = base + "/job-" + String(repeating: "a", count: 32)
        let receiptTask = Task { try await query.startStagedDownload(
            jobId: "job", workshopId: "654321",
            accountSteamId: "76561198000000000", stagingRoot: base) }
        let startRequest = await waitForRequest("startDownload", index: 4)
        transports.last!.emit(["v": 1, "type": "result", "ok": true,
                               "requestId": startRequest["requestId"]!,
                               "accountEpoch": client.accountEpoch,
                               "data": ["receiptVersion": 2, "contentDigest": String(repeating: "a", count: 64),
                                        "jobId": "job", "workshopId": "654321",
                                        "accountSteamId": "76561198000000000", "stagedComplete": true,
                                        "manifestId": "18446744073709551615", "stagingPath": path,
                                        "stagingDevice": "1", "stagingInode": "2",
                                        "stagingBirthSeconds": "100", "stagingBirthNanoseconds": "200",
                                        "projectJsonPresent": true, "totalBytes": 2, "verifiedBytes": 2]])
        let receipt = try await receiptTask.value
        precondition(receipt.manifestId == "18446744073709551615" && receipt.verifiedBytes == 2,
                     "download intent must recover a reaped helper at its owner")

        // 回收后：登录意图经 SteamAuthRoute.ensureHelperReady 成功。
        try await driveLogin(route: route, client: client, transports: transports)
        precondition(route.isOnline, "login intent must recover a reaped helper")
        await route.signOut()
        await client.stop(shutdownTimeout: 0)
        print("Helper idle reap: quiet+age gates, browse/pending/signin/auth/download suppressions, transparent anonymous restart, owner-recovered subscription/download/login PASS")
    }

    /// 驱动一次成功 QR 登录（模型与 accountRouteLifecycle 相同的回包形状）。
    @MainActor static func driveLogin(route: SteamAuthRoute, client: SteamServiceClient,
                                      transports: [FakeSteamTransport]) async throws {
        let transport = transports.last!
        transport.replyOnSend = false
        let login = Task { try await route.loginQR() }
        while transport.requests.first(where: { $0["command"] as? String == "loginQR" }) == nil {
            await Task.yield()
        }
        let request = transport.requests.last!
        transport.emit(["v": 1, "type": "result", "requestId": request["requestId"]!, "ok": true,
                        "authAttemptId": request["authAttemptId"] ?? "",
                        "accountEpoch": request["accountEpoch"]!,
                        "data": ["steamId": "76561198000000003", "accountName": "re***"],
                        "private": ["refreshToken": "reap-secret", "accountName": "account"]])
        _ = try await login.value
        transport.replyOnSend = true
        precondition(route.isOnline)
    }

    @MainActor static func explicitStartDuringBackoff() async throws {
        var transports: [FakeSteamTransport] = []
        let client = SteamServiceClient(executablePath: "/fake", transportFactory: { _ in
            let transport = FakeSteamTransport()
            transports.append(transport)
            return transport
        })
        _ = try await client.start()
        transports[0].isRunning = false
        transports[0].onTermination?(1)
        _ = try await client.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        precondition(transports.count == 2 && client.currentIdentity != nil,
                     "an explicit start must consume the scheduled restart")
        await client.stop(shutdownTimeout: 0)
    }

    @MainActor static func helperLocationLifecycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-steam-helper-location-\(UUID().uuidString)", isDirectory: true)
        let helperDirectory = root.appendingPathComponent("SteamService", isDirectory: true)
        let helper = helperDirectory.appendingPathComponent("SteamService")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        precondition(FileManager.default.createFile(atPath: helper.path, contents: Data("fixture".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        precondition(
            SteamServiceClient.locateHelperExecutable(environment: [:], resourceURL: root) == helper.path,
            "product helper must resolve from the app Resources directory"
        )
        precondition(
            SteamServiceClient.locateHelperExecutable(
                environment: ["MWX_STEAM_HELPER_COMMAND": "/private/tmp/steam-helper-override"],
                resourceURL: root
            ) == "/private/tmp/steam-helper-override",
            "explicit development helper override must remain authoritative"
        )
        precondition(
            SteamServiceClient.locateHelperExecutable(
                environment: ["MWX_STEAM_HELPER_COMMAND": ""],
                resourceURL: root
            ) == nil,
            "empty explicit override must suppress the bundled helper"
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: helper.path)
        precondition(
            SteamServiceClient.locateHelperExecutable(environment: [:], resourceURL: root) == nil,
            "non-executable bundled helper must fail closed"
        )
        try FileManager.default.removeItem(at: helper)
        precondition(
            SteamServiceClient.locateHelperExecutable(environment: [:], resourceURL: root) == nil,
            "missing helper under an existing Resources directory must fail closed"
        )
        precondition(
            SteamServiceClient.locateHelperExecutable(environment: [:], resourceURL: nil) == nil,
            "missing app resource directory must fail closed"
        )
        print("Helper location: Resources executable, override authority, and fail-closed negatives PASS")
    }

    @MainActor static func publicCrashRestartLifecycle() async throws {
        let original = FakeSteamTransport()
        original.replyOnSend = false
        let replacement = FakeSteamTransport()
        let explicitRetry = FakeSteamTransport()
        explicitRetry.replyOnSend = false
        let postRetryReplacement = FakeSteamTransport()
        var transportCount = 0
        let client = SteamServiceClient(
            executablePath: "/fake",
            maximumRestartAttempts: 1,
            transportFactory: { _ in
                transportCount += 1
                switch transportCount {
                case 1: return original
                case 2: return replacement
                case 3: return explicitRetry
                default: return postRetryReplacement
                }
            }
        )
        let route = SteamAuthRoute(client: client, persistence: .init(
            remember: { false }, setRemember: { _ in }, setRestoreAuthorized: { _ in },
            save: { _ in false }, delete: { true }, saveMetadata: { _ in }, clearMetadata: {}
        ))
        let firstIdentity = try await client.start()
        let signedOutEpoch = client.accountEpoch
        original.emit(["v": 1, "type": "event", "event": "accountState",
                       "accountEpoch": signedOutEpoch, "state": "disconnected"])
        precondition(route.displayState == .signedOut && client.accountEpoch == signedOutEpoch,
                     "anonymous disconnect cannot create or advance authentication state")
        let query = Task { try await client.request(command: "queryBrowse", timeout: nil) }
        while original.requests.isEmpty { await Task.yield() }
        original.crash()
        do {
            _ = try await query.value
            fatalError("public query survived helper crash")
        } catch SteamServiceClient.RequestError.connectionLost {}
        precondition(route.displayState == .signedOut, "public crash cannot become an auth failure")

        let restartDeadline = Date().addingTimeInterval(1)
        while client.currentIdentity == nil && Date() < restartDeadline {
            await Task.yield()
        }
        guard let secondIdentity = client.currentIdentity else {
            fatalError("bounded automatic replacement did not become ready")
        }
        precondition(
            secondIdentity.sessionGeneration == firstIdentity.sessionGeneration + 1 && transportCount == 2,
            "one crash must create exactly one new helper generation"
        )
        precondition(route.displayState == .signedOut, "replacement cannot create auth intent")

        replacement.crash()
        await Task.yield()
        precondition(client.state == .terminated && transportCount == 2,
                     "restart budget must stop a ready/crash loop")
        precondition(route.displayState == .signedOut, "budget exhaustion cannot create auth intent")

        do {
            _ = try await client.request(command: "listSubscriptions")
            fatalError("account work recovered a terminated helper without account intent")
        } catch SteamServiceClient.RequestError.notReady {}
        precondition(client.state == .terminated && transportCount == 2,
                     "non-public work cannot reset the terminated-helper budget")

        let firstRetry = Task { try await client.request(command: "queryBrowse", timeout: nil) }
        let secondRetry = Task { try await client.request(command: "queryDetails", timeout: nil) }
        while explicitRetry.requests.count < 2 { await Task.yield() }
        precondition(transportCount == 3,
                     "concurrent explicit public retries must share one helper generation")
        for request in explicitRetry.requests {
            explicitRetry.emit(["v": 1, "type": "result", "requestId": request["requestId"]!, "ok": true])
        }
        let firstResult = try await firstRetry.value
        let secondResult = try await secondRetry.value
        precondition(firstResult.ok == true && secondResult.ok == true
            && Set(explicitRetry.requests.compactMap { $0["command"] as? String })
                == Set(["queryBrowse", "queryDetails"]),
            "explicit public retries must complete through the shared recovered helper")
        precondition(route.displayState == .signedOut, "public retry cannot create auth intent")

        let recoveredIdentity = client.currentIdentity
        explicitRetry.crash()
        let recoveredRestartDeadline = Date().addingTimeInterval(1)
        while client.currentIdentity == nil && Date() < recoveredRestartDeadline {
            await Task.yield()
        }
        guard let postRetryIdentity = client.currentIdentity else {
            fatalError("explicit recovery did not reset one bounded automatic restart")
        }
        precondition(postRetryIdentity.sessionGeneration == recoveredIdentity?.sessionGeneration.advanced(by: 1)
            && transportCount == 4,
            "explicit recovery must reset exactly one automatic restart budget")
        postRetryReplacement.crash()
        await Task.yield()
        precondition(client.state == .terminated && transportCount == 4,
                     "the reset automatic restart budget must remain bounded")
        await client.stop(shutdownTimeout: 0)
        print("Public crash lifecycle: signed-out isolation, typed explicit recovery, shared generation and reset bounded restart PASS")
    }
    @MainActor static func authenticationLifecycle() async throws {
        let transport = FakeSteamTransport()
        let client = SteamServiceClient(executablePath: "/fake", transportFactory: { _ in transport })
        _ = try await client.start()
        transport.replyOnSend = false
        let session = SteamAccountSession(client: client)
        func authRequests() -> [[String: Any]] {
            transport.requests.filter { $0["command"] as? String == "loginQR" }
        }
        func succeed(_ request: [String: Any], token: String) {
            transport.emit(["v": 1, "type": "result", "requestId": request["requestId"]!,
                            "authAttemptId": request["authAttemptId"]!, "accountEpoch": request["accountEpoch"]!, "ok": true,
                            "data": ["steamId": "76561198000000000", "accountName": "te***"],
                            "private": ["refreshToken": token]])
        }
        let first = Task { try await session.loginQR() }
        while authRequests().count < 1 { await Task.yield() }
        let old = authRequests()[0]
        precondition(session.activeAttemptId == old["authAttemptId"] as? String,
                     "attempt exists before first event")
        session.cancelCurrentAttempt()
        precondition(session.phase == .cancelled && session.activeAttemptId == nil)
        succeed(old, token: "cancelled-secret")
        do { _ = try await first.value; fatalError("cancelled authentication adopted") } catch {}
        precondition(session.lastSessionTokens == nil)

        let second = Task { try await session.loginQR() }
        while authRequests().count < 2 { await Task.yield() }
        let current = authRequests()[1]
        transport.emit(["v": 1, "type": "event", "event": "authState",
                        "authAttemptId": old["authAttemptId"]!, "state": "qrChallenge", "challengeUrl": "stale"])
        precondition(session.phase == .connecting, "old event cannot replace current challenge")
        transport.emit(["v": 1, "type": "event", "event": "authState",
                        "authAttemptId": current["authAttemptId"]!, "state": "qrChallenge", "challengeUrl": "current"])
        precondition(session.phase == .qrChallenge(url: "current"))
        succeed(current, token: "accepted-secret")
        _ = try await second.value
        precondition(session.lastSessionTokens?.refreshToken == "accepted-secret")
        precondition(transport.requests.filter { $0["command"] as? String == "cancelAuthentication" }
            .allSatisfy { $0["authAttemptId"] as? String == old["authAttemptId"] as? String },
            "late cancellation must target only old attempt")

        let third = Task { try await session.loginQR() }
        while authRequests().count < 3 { await Task.yield() }
        third.cancel()
        succeed(authRequests()[2], token: "task-cancelled-secret")
        do { _ = try await third.value; fatalError("cancelled parent task adopted") } catch {}
        precondition(session.lastSessionTokens == nil)
        await client.stop(shutdownTimeout: 0)

        // Cancellation while the helper is still starting must prevent a later auth send.
        let starting = FakeSteamTransport()
        starting.readyOnStart = false
        let coldClient = SteamServiceClient(executablePath: "/fake", transportFactory: { _ in starting })
        let coldSession = SteamAccountSession(client: coldClient)
        let cold = Task { try await coldSession.loginQR() }
        while !starting.isRunning { await Task.yield() }
        coldSession.cancelCurrentAttempt()
        starting.emit(["v": 1, "type": "ready", "protocol": 1, "helperVersion": "0.1.0"])
        do { _ = try await cold.value; fatalError("cold cancelled auth succeeded") } catch {}
        precondition(!starting.requests.contains { $0["command"] as? String == "loginQR" })
        await coldClient.stop(shutdownTimeout: 0)
        print("Authentication lifecycle: early close, stale event/result, retry, token adoption, parent cancellation, startup cancellation PASS")
    }

    @MainActor static func accountRouteLifecycle() async throws {
        let unavailableTransport = FakeSteamTransport()
        unavailableTransport.startThrows = true
        let unavailableClient = SteamServiceClient(
            executablePath: "/fake",
            maximumRestartAttempts: 0,
            transportFactory: { _ in unavailableTransport }
        )
        let signedOutRoute = SteamAuthRoute(client: unavailableClient, persistence: .init(
            remember: { false }, setRemember: { _ in }, setRestoreAuthorized: { _ in },
            save: { _ in false }, delete: { true }, saveMetadata: { _ in }, clearMetadata: {}
        ))
        do {
            _ = try await unavailableClient.request(command: "queryBrowse")
            fatalError("missing public helper succeeded")
        } catch SteamServiceClient.RequestError.notReady {}
        precondition(
            signedOutRoute.displayState == .signedOut,
            "public helper failure must not become an authentication failure"
        )
        precondition(
            SteamServiceClient.RequestError.notReady.localizedDescription
                == "Steam 服务组件不可用，请重新安装或更新 App 后重试。"
        )

        let transport = FakeSteamTransport()
        transport.replyOnSend = false
        let client = SteamServiceClient(executablePath: "/fake", maximumRestartAttempts: 0,
                                        transportFactory: { _ in transport })
        var remember = true
        var restoreAllowed = true
        var deleted = 0
        var savedToken: String?
        let route = SteamAuthRoute(client: client, persistence: .init(
            remember: { remember }, setRemember: { remember = $0 },
            setRestoreAuthorized: { restoreAllowed = $0 },
            save: { savedToken = $0.refreshToken; return true },
            delete: { deleted += 1; return false }, saveMetadata: { _ in }, clearMetadata: {}))
        func commands(_ name: String) -> [[String: Any]] {
            transport.requests.filter { $0["command"] as? String == name }
        }
        func succeed(_ request: [String: Any], token: String = "current-token") {
            transport.emit(["v": 1, "type": "result", "requestId": request["requestId"]!, "ok": true,
                            "authAttemptId": request["authAttemptId"] ?? "", "accountEpoch": request["accountEpoch"]!,
                            "data": ["steamId": "76561198000000002", "accountName": "ac***"],
                            "private": ["refreshToken": token, "accountName": "account"]])
        }
        let restoring = Task { try await route.restore(refreshToken: "old-token", accountName: "old") }
        while commands("restoreSession").isEmpty { await Task.yield() }
        let oldRestore = commands("restoreSession")[0]
        let login = Task { try await route.loginQR() }
        while commands("loginQR").isEmpty { await Task.yield() }
        succeed(commands("loginQR")[0])
        _ = try await login.value
        transport.emit(["v": 1, "type": "result", "requestId": oldRestore["requestId"]!, "ok": false,
                        "error": ["code": "authExpired", "message": "old rejection"]])
        do { _ = try await restoring.value; fatalError("old restore adopted") } catch {}
        precondition(route.isOnline && savedToken == "current-token" && deleted == 0 && restoreAllowed,
                     "stale restore rejection cannot delete new credentials")

        let mismatched = Task { try await client.request(command: "querySubscriptionStates", timeout: nil) }
        while commands("querySubscriptionStates").isEmpty { await Task.yield() }
        transport.emit(["v": 1, "type": "result", "ok": true,
                        "requestId": commands("querySubscriptionStates")[0]["requestId"]!,
                        "accountEpoch": client.accountEpoch - 1, "data": ["states": [:]]])
        do { _ = try await mismatched.value; fatalError("mismatched account response accepted") }
        catch SteamServiceClient.RequestError.cancelled {}
        precondition(route.isOnline)

        let oldEpoch = client.accountEpoch
        let privateQuery = Task { try await client.request(command: "listSubscriptions", timeout: nil) }
        while commands("listSubscriptions").isEmpty { await Task.yield() }
        let pending = commands("listSubscriptions")[0]
        let signout = Task { await route.signOut() }
        while commands("logout").isEmpty { await Task.yield() }
        precondition(!route.isOnline && !remember && !restoreAllowed && route.tokenDeletionFailed,
                     "logout revokes restore even when Keychain deletion fails")
        do { _ = try await privateQuery.value; fatalError("old private query survived epoch") } catch {}
        succeed(pending)
        remember = true // toggling preference alone cannot revive deleted/revoked session
        precondition(!restoreAllowed)
        let secondLogin = Task { try await route.loginQR() }
        while commands("loginQR").count < 2 { await Task.yield() }
        succeed(commands("loginQR")[1], token: "new-token")
        _ = try await secondLogin.value
        succeed(commands("logout")[0])
        _ = await signout.value
        precondition(route.isOnline && savedToken == "new-token" && restoreAllowed,
                     "late logout completion cannot erase new account")
        transport.emit(["v": 1, "type": "event", "event": "accountState",
                        "accountEpoch": oldEpoch, "state": "disconnected"])
        precondition(route.isOnline, "stale disconnect ignored")
        transport.emit(["v": 1, "type": "event", "event": "accountState",
                        "accountEpoch": client.accountEpoch, "state": "disconnected"])
        precondition(!route.isOnline && savedToken == "new-token", "disconnect clears online, retains stored token")
        let thirdLogin = Task { try await route.loginQR() }
        while commands("loginQR").count < 3 { await Task.yield() }
        succeed(commands("loginQR")[2])
        _ = try await thirdLogin.value
        transport.onTermination?(9)
        precondition(!route.isOnline, "helper exit clears online projection")
        await client.stop(shutdownTimeout: 0)
        print("Account route: stale restore, account epoch, failed Keychain deletion, delayed logout, disconnect and helper crash PASS")
    }

    @MainActor static func stagedReceiptLifecycle() async throws {
        let transport = FakeSteamTransport()
        let client = SteamServiceClient(executablePath: "/fake", transportFactory: { _ in transport })
        _ = try await client.start()
        transport.replyOnSend = false
        let query = SteamWorkshopQueryClient(client: client)
        let base = "/private/tmp/receipt-fixture" // protocol fixture only, no disk I/O
        let path = base + "/job-" + String(repeating: "a", count: 32)
        let valid: [String: Any] = ["receiptVersion": 2, "contentDigest": String(repeating: "a", count: 64), "jobId": "job", "workshopId": "123456",
            "accountSteamId": "76561198000000000", "stagedComplete": true, "manifestId": "18446744073709551615",
            "stagingPath": path, "stagingDevice": "1", "stagingInode": "2",
            "stagingBirthSeconds": "100", "stagingBirthNanoseconds": "200",
            "projectJsonPresent": true, "totalBytes": 2, "verifiedBytes": 2]
        func run(_ data: [String: Any], accept: Bool, epochDelta: Int = 0) async throws {
            let before = transport.requests.count
            let task = Task { try await query.startStagedDownload(jobId: "job", workshopId: "123456",
                accountSteamId: "76561198000000000", stagingRoot: base) }
            while transport.requests.count == before { await Task.yield() }
            let request = transport.requests.last!
            transport.emit(["v": 1, "type": "result", "ok": true, "requestId": request["requestId"]!,
                "accountEpoch": client.accountEpoch + epochDelta, "data": data])
            do {
                let receipt = try await task.value
                precondition(accept, "invalid receipt accepted")
                precondition(receipt.stagingURL.path == path && receipt.verifiedBytes == 2)
                precondition(receipt.manifestId == "18446744073709551615", "64-bit ID preserved")
                precondition(receipt.stagingLeaseIdentity == SteamWorkshopStagingLeaseIdentity(
                    device: 1, inode: 2, birthSeconds: 100, birthNanoseconds: 200),
                    "helper descriptor identity preserved")
            } catch { if accept { throw error } }
        }
        try await run(valid, accept: true)
        for key in valid.keys {
            var missing = valid; missing.removeValue(forKey: key)
            try await run(missing, accept: false)
        }
        let mutations: [(String, Any)] = [
            ("receiptVersion", 1), ("jobId", "other"), ("workshopId", "654321"),
            ("accountSteamId", "76561198000000001"), ("manifestId", "18446744073709551616"),
            ("manifestId", "-1"), ("manifestId", ""), ("stagedComplete", false),
            ("stagingDevice", "-1"), ("stagingDevice", "x"),
            ("stagingInode", "0"), ("stagingInode", "x"),
            ("stagingBirthSeconds", "0"), ("stagingBirthSeconds", "x"),
            ("stagingBirthNanoseconds", "-1"), ("stagingBirthNanoseconds", "1000000000"),
            ("stagingBirthNanoseconds", "x"),
            ("projectJsonPresent", false), ("verifiedBytes", 1), ("totalBytes", -1),
            ("totalBytes", 9 * 1024 * 1024 * 1024), ("verifiedBytes", "2"),
            ("stagingPath", "/outside/" + String(repeating: "a", count: 32)),
            ("stagingPath", base + "-other/job-" + String(repeating: "a", count: 32)),
            ("stagingPath", base + "/x/../job-" + String(repeating: "a", count: 32)),
            ("stagingPath", base + "/job-123"), ("stagingPath", base),
            ("stagingPath", path + "/child"), ("stagingPath", path + "\0")]
        for (key, value) in mutations {
            var changed = valid; changed[key] = value
            try await run(changed, accept: false)
        }
        try await run(valid, accept: false, epochDelta: -1)
        await client.stop(shutdownTimeout: 0)
        print("Staged receipt: valid, every required field, wrong identity/epoch, numeric bounds and path rejection PASS")
    }

}
