import AppKit

@main
enum SystemWallpaperConnectionChecks {
    @MainActor static func main() async {
        do { try await check() }
        catch { print("FAIL:", error as NSError); exit(1) }
    }

    @MainActor static func check() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let runtime = SystemWallpaperRuntime(root: root)
        let server = Listener(configuration: .init(runtime: runtime))
        let listener = NSXPCListener.anonymous()
        listener.delegate = server
        listener.resume()
        let client = NSXPCConnection(listenerEndpoint: listener.endpoint)
        let receiver = Receiver()
        let agent = NSXPCInterface(with: SystemWallpaperAgentProtocol.self)
        agent.setClasses(try SystemWallpaperWire.allowedClasses(),
            for: #selector(SystemWallpaperAgentProtocol.updateSettings(_:reply:)), argumentIndex: 0, ofReply: false)
        client.exportedInterface = agent
        client.exportedObject = receiver
        client.remoteObjectInterface = NSXPCInterface(with: SystemWallpaperHostProtocol.self)
        client.resume()
        defer { client.invalidate(); listener.invalidate(); withExtendedLifetime(server) {} }
        let proxy = client.remoteObjectProxyWithErrorHandler { _ in } as! SystemWallpaperHostProtocol
        let ready: Bool = await withCheckedContinuation { continuation in
            proxy.isDownloaded(nil) { value, _ in continuation.resume(returning: value) }
        }
        guard ready else { throw CocoaError(.xpcConnectionInvalid) }
        try await wait { receiver.values.count == 1 }
        guard receiver.values == ["empty"] else { throw CocoaError(.coderReadCorrupt) }

        let value = ScreenSaverConfiguration(content: .init(kind: .video, mediaGeneration: UUID().uuidString,
            title: "IPC publication", entryRelativePath: "video.mp4", posterRelativePath: "poster.png"))
        let media = try ScreenSaverPaths.mediaRoot(in: root, generation: value.content!.mediaGeneration)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data().write(to: media.appendingPathComponent("video.mp4"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[2]),
                                        to: media.appendingPathComponent("poster.png"))
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        runtime.reload()
        runtime.reload()
        try await wait { receiver.values.count == 2 }
        guard receiver.values.last == "IPC publication" else { throw CocoaError(.coderReadCorrupt) }
        try JSONEncoder().encode(ScreenSaverConfiguration(content: nil)).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        runtime.reload()
        try await wait { receiver.values.count == 3 && receiver.invalidations == 3 }
        guard receiver.values.last == "empty" else { throw CocoaError(.coderReadCorrupt) }
        client.invalidate()
        try await Task.sleep(for: .milliseconds(30))
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        runtime.reload()
        try await Task.sleep(for: .milliseconds(30))
        guard receiver.values.count == 3 else { throw CocoaError(.xpcConnectionReplyInvalid) }
        print("PASS: actual XPC initial catalog, changed publication, clear and disconnected recipient")
    }

    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.xpcConnectionReplyInvalid)
    }

    private final class Listener: NSObject, NSXPCListenerDelegate {
        let configuration: SystemWallpaperExtensionConfiguration
        init(configuration: SystemWallpaperExtensionConfiguration) { self.configuration = configuration }
        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            configuration.accept(connection: connection)
        }
    }

    private final class Receiver: NSObject, SystemWallpaperAgentProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []
        private var snapshots = 0
        var values: [String] { lock.withLock { names } }
        var invalidations: Int { lock.withLock { snapshots } }
        func updateSettings(_ models: Any?, reply: @escaping (NSError?) -> Void) {
            let name = models.flatMap { SystemWallpaperWire.field("screenSaver", in: $0) }
                .flatMap { SystemWallpaperWire.field("groups", in: $0) as? [Any] }?.first
                .flatMap { SystemWallpaperWire.field("items", in: $0) as? [Any] }?.first
                .flatMap { SystemWallpaperWire.field("localizedName", in: $0) as? String } ?? "empty"
            lock.withLock { names.append(name) }
            reply(nil)
        }
        func invalidateSnapshots(reply: @escaping (NSError?) -> Void) {
            lock.withLock { snapshots += 1 }
            reply(nil)
        }
    }
}
