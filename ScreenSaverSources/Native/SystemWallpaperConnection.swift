import AppKit

final class SystemWallpaperConnection: NSObject, SystemWallpaperHostProtocol, @unchecked Sendable {
    private let identifier = UUID()
    private let runtime: SystemWallpaperRuntime
    private weak var connection: NSXPCConnection?
    private var catalogObserver: NSObjectProtocol?
    @MainActor private var stopped = false

    init(runtime: SystemWallpaperRuntime, connection: NSXPCConnection) {
        self.runtime = runtime
        self.connection = connection
        super.init()
        catalogObserver = NotificationCenter.default.addObserver(
            forName: ScreenSaverConfiguration.changedNotification, object: runtime, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishCatalog() }
        }
    }

    deinit {
        if let catalogObserver { NotificationCenter.default.removeObserver(catalogObserver) }
    }

    func acquire(_ id: Any?, request: Any?, reply: @escaping (Any?, NSError?) -> Void) {
        do {
            guard let id = SystemWallpaperWire.identifier(id), let request else { throw CocoaError(.coderReadCorrupt) }
            let geometry = try SystemWallpaperWire.geometry(in: request)
            Task { @MainActor in
                do {
                    guard !self.stopped else { throw CocoaError(.userCancelled) }
                    let context = try self.runtime.acquire(connection: self.identifier, request: id, geometry: geometry)
                    reply(try SystemWallpaperWire.remoteContext(context), nil)
                } catch { reply(nil, error as NSError) }
            }
        } catch { reply(nil, error as NSError) }
    }

    func update(_ id: Any?, request: Any?, reply: @escaping (NSError?) -> Void) {
        do {
            guard let id = SystemWallpaperWire.identifier(id), let request else { throw CocoaError(.coderReadCorrupt) }
            let geometry = try SystemWallpaperWire.geometry(in: request)
            Task { @MainActor in
                do {
                    if !self.stopped { try self.runtime.update(connection: self.identifier, request: id, geometry: geometry) }
                    reply(nil)
                } catch { reply(error as NSError) }
            }
        } catch { reply(error as NSError) }
    }

    func invalidate(_ id: Any?, reply: @escaping (NSError?) -> Void) {
        let id = SystemWallpaperWire.identifier(id)
        Task { @MainActor in
            if let id { self.runtime.invalidate(connection: self.identifier, request: id) }
            reply(nil)
        }
    }

    func snapshot(_ id: Any?, reply: @escaping (Any?, NSError?) -> Void) { reply(nil, nil) }

    func settings(_ types: Any?, reply: @escaping (Any?, NSError?) -> Void) {
        Task { @MainActor in
            do {
                self.runtime.reload()
                reply(try SystemWallpaperWire.settings(SystemWallpaperCatalog(media: self.runtime.media)), nil)
            } catch { reply(nil, error as NSError) }
        }
    }

    func selectedChoicesChanged(_ id: Any?, reply: @escaping (NSError?) -> Void) { reply(nil) }
    func isDownloaded(_ id: Any?, reply: @escaping (Bool, NSError?) -> Void) { reply(true, nil) }

    @MainActor func stop() {
        stopped = true
        if let catalogObserver { NotificationCenter.default.removeObserver(catalogObserver) }
        catalogObserver = nil
        runtime.invalidate(connection: identifier)
    }

    @MainActor func publishCatalog() {
        guard !stopped, let connection,
              let models = try? SystemWallpaperWire.settings(SystemWallpaperCatalog(media: runtime.media)),
              let agent = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? SystemWallpaperAgentProtocol else { return }
        agent.updateSettings(models) { error in
            if error == nil { agent.invalidateSnapshots { _ in } }
        }
    }
}
