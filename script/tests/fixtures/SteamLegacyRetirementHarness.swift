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
        var webStoreCalls = 0
        let successful = SteamWorkshopLegacyAcquisitionRetirement.Environment(
            cachesRoot: caches,
            applicationSupportRoot: support,
            deleteCredential: {
                credentialCalls += 1
                return errSecSuccess
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
        print("PASS: exact legacy retirement is idempotent and component-retryable")
    }
}
