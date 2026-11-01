import ExtensionFoundation
import Foundation

// Objective-C selectors are the system extension's wire ABI; private model classes
// are loaded and admitted once per connection by SystemWallpaperWire.
@objc(MWXWallpaperExtensionProtocol)
protocol SystemWallpaperHostProtocol {
    @objc(acquireWithId:request:reply:)
    func acquire(_ id: Any?, request: Any?, reply: @escaping (Any?, NSError?) -> Void)
    @objc(updateWithId:request:reply:)
    func update(_ id: Any?, request: Any?, reply: @escaping (NSError?) -> Void)
    @objc(invalidateWithId:reply:)
    func invalidate(_ id: Any?, reply: @escaping (NSError?) -> Void)
    @objc(snapshotWithId:reply:)
    func snapshot(_ id: Any?, reply: @escaping (Any?, NSError?) -> Void)
    @objc(provideSettingsViewModelsWithContentTypes:reply:)
    func settings(_ types: Any?, reply: @escaping (Any?, NSError?) -> Void)
    @objc(selectedChoicesDidChangeFor:reply:)
    func selectedChoicesChanged(_ id: Any?, reply: @escaping (NSError?) -> Void)
    @objc(isChoiceDownloadedWith:reply:)
    func isDownloaded(_ id: Any?, reply: @escaping (Bool, NSError?) -> Void)
}

@objc(MWXWallpaperAgentProtocol)
protocol SystemWallpaperAgentProtocol {
    @objc(updateSettingsViewModels:reply:)
    func updateSettings(_ models: Any?, reply: @escaping (NSError?) -> Void)
    @objc(invalidateSnapshotsWithReply:)
    func invalidateSnapshots(reply: @escaping (NSError?) -> Void)
}

@main
@MainActor
final class MyWallpaperXSystemWallpaperExtension: NSObject, AppExtension {
    private let runtime = SystemWallpaperRuntime()
    required override init() { super.init() }
    var configuration: SystemWallpaperExtensionConfiguration { SystemWallpaperExtensionConfiguration(runtime: runtime) }
}

struct SystemWallpaperExtensionConfiguration: AppExtensionConfiguration {
    let runtime: SystemWallpaperRuntime
    func accept(connection: NSXPCConnection) -> Bool {
        do {
            let interface = NSXPCInterface(with: SystemWallpaperHostProtocol.self)
            let classes = try SystemWallpaperWire.allowedClasses()
            for (selector, arguments, returnsObject) in [
                (#selector(SystemWallpaperHostProtocol.acquire(_:request:reply:)), 2, true),
                (#selector(SystemWallpaperHostProtocol.update(_:request:reply:)), 2, false),
                (#selector(SystemWallpaperHostProtocol.invalidate(_:reply:)), 1, false),
                (#selector(SystemWallpaperHostProtocol.snapshot(_:reply:)), 1, true),
                (#selector(SystemWallpaperHostProtocol.settings(_:reply:)), 1, true),
                (#selector(SystemWallpaperHostProtocol.selectedChoicesChanged(_:reply:)), 1, false),
                (#selector(SystemWallpaperHostProtocol.isDownloaded(_:reply:)), 1, false)
            ] {
                for index in 0..<arguments {
                    interface.setClasses(classes, for: selector, argumentIndex: index, ofReply: false)
                }
                if returnsObject {
                    interface.setClasses(classes, for: selector, argumentIndex: 0, ofReply: true)
                }
            }
            let agent = NSXPCInterface(with: SystemWallpaperAgentProtocol.self)
            agent.setClasses(classes, for: #selector(SystemWallpaperAgentProtocol.updateSettings(_:reply:)),
                             argumentIndex: 0, ofReply: false)
            connection.remoteObjectInterface = agent
            let handler = SystemWallpaperConnection(runtime: runtime, connection: connection)
            connection.exportedInterface = interface
            connection.exportedObject = handler
            connection.invalidationHandler = {
                Task { @MainActor in handler.stop() }
            }
            connection.resume()
            Task { @MainActor in handler.publishCatalog() }
            return true
        } catch { return false }
    }
}
