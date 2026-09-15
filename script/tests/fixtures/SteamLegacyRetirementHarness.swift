import Foundation
import Security

@main
struct SteamLegacyRetirementHarness {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let defaultsName = "com.songziqiang.MyWallpaperX.Debug.LegacyRetirementHarness"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            fatalError("unable to create isolated defaults")
        }
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let fileManager = FileManager.default
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let cacheTarget = caches
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
        let runtimeTarget = support
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshopRuntime", isDirectory: true)
        let cacheSentinel = caches
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("keep-cache", isDirectory: false)
        let runtimeSentinel = support
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("keep-runtime", isDirectory: false)
        try fileManager.createDirectory(at: cacheTarget, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimeTarget, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cacheSentinel)
        try Data("runtime".utf8).write(to: runtimeSentinel)

        var credentialCalls = 0
        var webStoreFetchCalls = 0
        var webStoreCalls = 0
        let legacyWebStoreIdentifier = UUID(
            uuidString: "8ED08F8C-9DC7-45E8-8F71-1EDDA4DD29C5"
        )!
        let successful = SteamWorkshopLegacyAcquisitionRetirement.Environment(
            cachesRoot: caches,
            applicationSupportRoot: support,
            deleteCredential: {
                credentialCalls += 1
                return errSecSuccess
            },
            fetchWebDataStoreIdentifiers: { completion in
                webStoreFetchCalls += 1
                completion([legacyWebStoreIdentifier])
            },
            removeWebDataStore: { completion in
                webStoreCalls += 1
                completion(nil)
            }
        )
        SteamWorkshopLegacyAcquisitionRetirement.run(
            defaults: defaults,
            fileManager: fileManager,
            environment: successful
        )
        SteamWorkshopLegacyAcquisitionRetirement.run(
            defaults: defaults,
            fileManager: fileManager,
            environment: successful
        )
        precondition(credentialCalls == 1)
        precondition(webStoreFetchCalls == 1)
        precondition(webStoreCalls == 1)
        precondition(!fileManager.fileExists(atPath: cacheTarget.path))
        precondition(!fileManager.fileExists(atPath: runtimeTarget.path))
        precondition(fileManager.fileExists(atPath: cacheSentinel.path))
        precondition(fileManager.fileExists(atPath: runtimeSentinel.path))

        let retryDefaultsName = defaultsName + ".Retry"
        guard let retryDefaults = UserDefaults(suiteName: retryDefaultsName) else {
            fatalError("unable to create retry defaults")
        }
        retryDefaults.removePersistentDomain(forName: retryDefaultsName)
        defer { retryDefaults.removePersistentDomain(forName: retryDefaultsName) }
        var retryCalls = 0
        let failing = SteamWorkshopLegacyAcquisitionRetirement.Environment(
            cachesRoot: nil,
            applicationSupportRoot: nil,
            deleteCredential: {
                retryCalls += 1
                return errSecInteractionNotAllowed
            },
            fetchWebDataStoreIdentifiers: { completion in completion([]) },
            removeWebDataStore: { completion in completion(nil) }
        )
        SteamWorkshopLegacyAcquisitionRetirement.run(
            defaults: retryDefaults,
            fileManager: fileManager,
            environment: failing
        )
        SteamWorkshopLegacyAcquisitionRetirement.run(
            defaults: retryDefaults,
            fileManager: fileManager,
            environment: failing
        )
        precondition(retryCalls == 2, "failed component must remain retryable")

        let recovered = SteamWorkshopLegacyAcquisitionRetirement.Environment(
            cachesRoot: nil,
            applicationSupportRoot: nil,
            deleteCredential: {
                retryCalls += 1
                return errSecSuccess
            },
            fetchWebDataStoreIdentifiers: { completion in completion([]) },
            removeWebDataStore: { completion in completion(nil) }
        )
        SteamWorkshopLegacyAcquisitionRetirement.run(
            defaults: retryDefaults,
            fileManager: fileManager,
            environment: recovered
        )
        SteamWorkshopLegacyAcquisitionRetirement.run(
            defaults: retryDefaults,
            fileManager: fileManager,
            environment: recovered
        )
        precondition(retryCalls == 3, "recovered component must mark completion")

        let absentDefaultsName = defaultsName + ".AbsentWebStore"
        guard let absentDefaults = UserDefaults(suiteName: absentDefaultsName) else {
            fatalError("unable to create absent-store defaults")
        }
        absentDefaults.removePersistentDomain(forName: absentDefaultsName)
        defer { absentDefaults.removePersistentDomain(forName: absentDefaultsName) }
        var absentFetchCalls = 0
        var absentRemoveCalls = 0
        let absent = SteamWorkshopLegacyAcquisitionRetirement.Environment(
            cachesRoot: nil,
            applicationSupportRoot: nil,
            deleteCredential: { errSecItemNotFound },
            fetchWebDataStoreIdentifiers: { completion in
                absentFetchCalls += 1
                completion([])
            },
            removeWebDataStore: { completion in
                absentRemoveCalls += 1
                completion(nil)
            }
        )
        SteamWorkshopLegacyAcquisitionRetirement.run(
            defaults: absentDefaults,
            fileManager: fileManager,
            environment: absent
        )
        SteamWorkshopLegacyAcquisitionRetirement.run(
            defaults: absentDefaults,
            fileManager: fileManager,
            environment: absent
        )
        precondition(absentFetchCalls == 1, "absent store must mark completion")
        precondition(absentRemoveCalls == 0, "absent store must not be removed")
        print("PASS: exact legacy retirement is idempotent and component-retryable")
    }
}
