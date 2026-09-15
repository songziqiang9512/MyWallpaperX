import Foundation
import Security
import WebKit

/// SK6.2 one-time cleanup for state owned exclusively by the retired
/// acquisition backend. Each component has its own marker so one failed
/// deletion cannot repeatedly evict unrelated, newly regenerated state.
@MainActor
enum SteamWorkshopLegacyAcquisitionRetirement {
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
        retireCredential(defaults: defaults)
        retireCache(defaults: defaults, fileManager: fileManager)
        retireRuntime(defaults: defaults, fileManager: fileManager)
        retireWebDataStore(defaults: defaults)
    }

    private static func retireCredential(defaults: UserDefaults) {
        guard !defaults.bool(forKey: credentialMarker) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: credentialAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
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
        fileManager: FileManager
    ) {
        guard !defaults.bool(forKey: cacheMarker),
              let cachesRoot = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
              ).first else {
            return
        }
        let target = cachesRoot
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
        fileManager: FileManager
    ) {
        guard !defaults.bool(forKey: runtimeMarker),
              let appSupportRoot = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
              ).first else {
            return
        }
        let target = appSupportRoot
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

    private static func retireWebDataStore(defaults: UserDefaults) {
        guard !defaults.bool(forKey: webStoreMarker) else { return }
        WKWebsiteDataStore.remove(forIdentifier: webDataStoreIdentifier) { error in
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
