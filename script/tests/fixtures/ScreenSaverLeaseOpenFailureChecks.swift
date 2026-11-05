import AppKit
import Darwin
import Foundation

private nonisolated final class LeaseOpenInjection: @unchecked Sendable {
    struct Call {
        let path: String
        let flags: Int32
        let mode: mode_t
        let desiredErrno: Int32
        var json: [String: Any] {
            ["path": path, "flags": flags, "mode": mode, "desiredErrno": desiredErrno]
        }
    }
    static let shared = LeaseOpenInjection()
    private let lock = NSLock()
    private var calls: [Call] = []
    let desiredErrno = Int32(CommandLine.arguments[3])!

    func record(path: String, flags: Int32, mode: mode_t) -> Int32 {
        let call = Call(path: path, flags: flags, mode: mode, desiredErrno: desiredErrno)
        lock.lock()
        calls.append(call)
        lock.unlock()
        let data = try! JSONSerialization.data(withJSONObject: ["leaseOpenInjection": call.json], options: [.sortedKeys])
        FileHandle.standardError.write(data + Data([10]))
        return desiredErrno
    }
    func snapshot() -> [Call] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

// Only unqualified three-argument String calls resolve to this test-module leaf.
nonisolated func open(_ path: String, _ flags: Int32, _ mode: mode_t) -> Int32 {
    let desiredErrno = LeaseOpenInjection.shared.record(path: path, flags: flags, mode: mode)
    errno = desiredErrno
    return -1
}

@main private enum ScreenSaverLeaseOpenFailureChecks {
    @MainActor static func main() async {
        do { try await run() }
        catch {
            let failure = error as NSError
            let data = try! JSONSerialization.data(withJSONObject: ["fixtureError": [
                "domain": failure.domain, "code": failure.code, "description": failure.localizedDescription]], options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor private static func run() async throws {
        let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = work.appendingPathComponent("root", isDirectory: true).standardizedFileURL
        let component = work.appendingPathComponent("component/MyWallpaperXSystemWallpaper.appex", isDirectory: true)
        let media = root.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: component, withIntermediateDirectories: true)
        let current = ScreenSaverConfiguration(content: .init(kind: .video, mediaGeneration: UUID().uuidString,
            title: "current baseline", sourceIdentity: "video:current", entryRelativePath: "Video/current.mov", posterRelativePath: "poster.jpg"))
        let previous = ScreenSaverConfiguration(content: .init(kind: .video, mediaGeneration: UUID().uuidString,
            title: "previous baseline", sourceIdentity: "video:previous", entryRelativePath: "Video/previous.mov", posterRelativePath: "poster.jpg"))
        let currentBefore = try JSONEncoder().encode(current)
        let previousBefore = try JSONEncoder().encode(previous)
        let currentURL = root.appendingPathComponent("current.json")
        let previousURL = root.appendingPathComponent("previous.json")
        try currentBefore.write(to: currentURL)
        try previousBefore.write(to: previousURL)
        for configuration in [current, previous] {
            let directory = try ScreenSaverPaths.mediaRoot(in: root, generation: configuration.content!.mediaGeneration)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let mediaBefore = try FileManager.default.contentsOfDirectory(atPath: media.path).sorted()
        let owner = ScreenSaverIntegration(rootURL: root, componentSourceURL: component)
        var callbackCount = 0
        let result: Result<ScreenSaverConfiguration, Error> = await withCheckedContinuation { continuation in
            owner.publish(.init(videoURL: work.appendingPathComponent("never-decoded.mov"), title: "candidate"),
                fillMode: "aspectFill", playsOnBattery: false) { result in
                callbackCount += 1
                continuation.resume(returning: result)
            }
        }
        owner.cancelForExit()
        let calls = LeaseOpenInjection.shared.snapshot()
        let expectedFlags = O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC
        let matched: Bool
        let removed: Bool
        if calls.count == 1, let call = calls.first {
            let lease = URL(fileURLWithPath: call.path)
            let generation = lease.deletingLastPathComponent()
            matched = lease.lastPathComponent == ".lease"
                && generation.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
                    == media.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                && UUID(uuidString: generation.lastPathComponent) != nil
                && call.flags == expectedFlags && call.mode == 0o600
            removed = !FileManager.default.fileExists(atPath: generation.path)
        } else { matched = false; removed = false }
        let callbackError: Any
        let callbackSuccess: Bool
        switch result {
        case .success: callbackSuccess = true; callbackError = NSNull()
        case let .failure(error):
            let failure = error as NSError
            callbackSuccess = false
            callbackError = ["domain": failure.domain, "code": failure.code, "description": failure.localizedDescription]
        }
        let mediaAfter = try FileManager.default.contentsOfDirectory(atPath: media.path).sorted()
        let facts: [String: Any] = [
            "case": CommandLine.arguments[2], "pid": ProcessInfo.processInfo.processIdentifier,
            "desiredErrno": LeaseOpenInjection.shared.desiredErrno, "calls": calls.map(\.json),
            "assemblyValid": matched, "callbackCount": callbackCount,
            "assemblyExpectedMediaPath": media.path,
            "callbackSuccess": callbackSuccess, "callbackError": callbackError,
            "candidateMediaRemoved": removed, "mediaBefore": mediaBefore, "mediaAfter": mediaAfter,
            "currentUnchanged": try Data(contentsOf: currentURL) == currentBefore,
            "previousUnchanged": try Data(contentsOf: previousURL) == previousBefore,
            "baselineConfigurationsDecode": try JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentBefore) == current
                && JSONDecoder().decode(ScreenSaverConfiguration.self, from: previousBefore) == previous,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
