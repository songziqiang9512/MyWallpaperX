import Foundation
import Security
import WebKit

/// SK6.2 one-time cleanup for state owned exclusively by the retired
/// acquisition backend. Each component has its own marker so one failed
/// deletion cannot repeatedly evict unrelated, newly regenerated state.
@MainActor
enum SteamWorkshopLegacyAcquisitionRetirement {
    struct Environment {
        let cachesRoot: URL?
        let applicationSupportRoot: URL?
        let deleteCredential: @MainActor () -> OSStatus
        let removeWebDataStore: @MainActor (
            @escaping @MainActor @Sendable (Error?) -> Void
        ) -> Void

        @MainActor
        static func live(fileManager: FileManager) -> Environment {
            Environment(
                cachesRoot: fileManager.urls(
                    for: .cachesDirectory,
                    in: .userDomainMask
                ).first,
                applicationSupportRoot: fileManager.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first,
                deleteCredential: {
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: credentialService,
                        kSecAttrAccount as String: credentialAccount
                    ]
                    return SecItemDelete(query as CFDictionary)
                },
                removeWebDataStore: { completion in
                    WKWebsiteDataStore.remove(
                        forIdentifier: webDataStoreIdentifier,
                        completionHandler: completion
                    )
                }
            )
        }
    }

    private static let credentialMarker = "SteamWorkshop.retirement.credential.v1"
    private static let cacheMarker = "SteamWorkshop.retirement.cache.v1"
    private static let runtimeMarker = "SteamWorkshop.retirement.runtime.v1"
    private static let webStoreMarker = "SteamWorkshop.retirement.webStore.v1"

    private static let credentialService = "com.songziqiang.MyWallpaperX.steam"
    private static let credentialAccount = "steamPassword"
    private static let webDataStoreIdentifier = UUID(
        uuidString: "8ED08F8C-9DC7-45E8-8F71-1EDDA4DD29C5"
    )!

    static func run(
        defaults: UserDefaults,
        fileManager: FileManager = .default
    ) {
        run(
            defaults: defaults,
            fileManager: fileManager,
            environment: .live(fileManager: fileManager)
        )
    }

    /// Injectable only at the system boundary so isolated gates can execute
    /// the production marker/retry/path logic without touching the login
    /// Keychain or the dedicated live WebKit store.
    static func run(
        defaults: UserDefaults,
        fileManager: FileManager,
        environment: Environment
    ) {
        retireCredential(defaults: defaults, environment: environment)
        retireCache(
            defaults: defaults,
            fileManager: fileManager,
            root: environment.cachesRoot
        )
        retireRuntime(
            defaults: defaults,
            fileManager: fileManager,
            root: environment.applicationSupportRoot
        )
        retireWebDataStore(defaults: defaults, environment: environment)
    }

    private static func retireCredential(
        defaults: UserDefaults,
        environment: Environment
    ) {
        guard !defaults.bool(forKey: credentialMarker) else { return }
        let status = environment.deleteCredential()
        guard status == errSecSuccess || status == errSecItemNotFound else {
            NSLog("[SteamWorkshopRetirement] legacy credential deletion failed: %d", status)
            return
        }
        defaults.removeObject(forKey: "SteamWorkshop.lastUsername")
        defaults.removeObject(forKey: "SteamWorkshop.lastAuthenticatedAt")
        defaults.set(true, forKey: credentialMarker)
    }

    private static func retireCache(
        defaults: UserDefaults,
        fileManager: FileManager,
        root: URL?
    ) {
        guard !defaults.bool(forKey: cacheMarker),
              let root else {
            return
        }
        let target = root
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
            .standardizedFileURL
        do {
            try removeIfPresent(target, fileManager: fileManager)
            defaults.set(true, forKey: cacheMarker)
        } catch {
            NSLog(
                "[SteamWorkshopRetirement] legacy cache deletion failed: %@",
                error.localizedDescription
            )
        }
    }

    private static func retireRuntime(
        defaults: UserDefaults,
        fileManager: FileManager,
        root: URL?
    ) {
        guard !defaults.bool(forKey: runtimeMarker),
              let root else {
            return
        }
        let target = root
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshopRuntime", isDirectory: true)
            .standardizedFileURL
        do {
            try removeIfPresent(target, fileManager: fileManager)
            defaults.set(true, forKey: runtimeMarker)
        } catch {
            NSLog(
                "[SteamWorkshopRetirement] legacy runtime deletion failed: %@",
                error.localizedDescription
            )
        }
    }

    private static func retireWebDataStore(
        defaults: UserDefaults,
        environment: Environment
    ) {
        guard !defaults.bool(forKey: webStoreMarker) else { return }
        environment.removeWebDataStore { error in
            guard error == nil else {
                NSLog(
                    "[SteamWorkshopRetirement] legacy web store deletion failed: %@",
                    error!.localizedDescription
                )
                return
            }
            defaults.set(true, forKey: webStoreMarker)
        }
    }

    private static func removeIfPresent(
        _ target: URL,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: target.path,
            isDirectory: &isDirectory
        ) else {
            return
        }
        try fileManager.removeItem(at: target)
    }
}
