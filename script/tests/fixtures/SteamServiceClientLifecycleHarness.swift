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
    var staleTermination: ((Int32) -> Void)?
    func start() throws {
        isRunning = true
        staleTermination = onTermination
        if readyOnStart { emit(["v": 1, "type": "ready", "protocol": 1, "helperVersion": "0.1.0"]) }
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
}

@main struct SteamServiceClientLifecycleHarness {
    @MainActor static func main() async throws {
        let first = FakeSteamTransport()
        let client = SteamServiceClient(executablePath: "/fake", transportFactory: { _ in first })
        let response = try await client.request(command: "queryBrowse")
        precondition(response.ok == true && first.sends == 1, "cold public request/synchronous reply")

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
        try await authenticationLifecycle()
        try await accountRouteLifecycle()
        try await stagedReceiptLifecycle()
        print("Steam client lifecycle: cold start, synchronous reply, cancellation, frame limit, timeout teardown, stale callback PASS")
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
            "stagingPath": path, "projectJsonPresent": true, "totalBytes": 2, "verifiedBytes": 2]
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
