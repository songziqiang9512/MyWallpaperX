import Foundation

extension SteamWorkshopService {
    enum Constants {
        nonisolated static let workshopAppID = "431960"
        nonisolated static let steamCommunityBase = "https://steamcommunity.com/workshop/browse/"
        nonisolated static let detailBase = "https://steamcommunity.com/sharedfiles/filedetails/"
        nonisolated static let publishedFileDetailsAPI = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
        nonisolated static let authorWorkshopPageSize = 30
        nonisolated static let detailHydrationBatchSize = 4
        nonisolated static let detailHydrationExpandedBatchSize = 6
        nonisolated static let detailHydrationExpandedThreshold = 18
        nonisolated static let detailHydrationNormalThreshold = 8
        nonisolated static let detailHydrationInterBatchDelayNanoseconds: UInt64 = 1_300_000_000
        nonisolated static let detailHydrationFastInterBatchDelayNanoseconds: UInt64 = 450_000_000
        nonisolated static let detailHydrationNormalInterBatchDelayNanoseconds: UInt64 = 800_000_000
        nonisolated static let detailPrefetchBatchSize = 2
        nonisolated static let detailPrefetchInterBatchDelayNanoseconds: UInt64 = 2_000_000_000
        nonisolated static let browserInteractionDeferralInterval: TimeInterval = 1.2
        nonisolated static let detailRequestDeferralInterval: TimeInterval = 4.0
        nonisolated static let loadMoreRetryCooldown: TimeInterval = 2.0
        nonisolated static let browserDebugLoggingEnabledKey = "SteamWorkshop.browserDebugLoggingEnabled"
        nonisolated static let bundledSteamBundleName = "SteamCMDRuntime.bundle"
        nonisolated static let bundledSteamRootName = "Steam"
        nonisolated static let bundledSteamMetadataName = "runtime-metadata.json"
        nonisolated static let browserPageSize = 24
        nonisolated static let personalWorkshopPageSize = 10
        nonisolated static let cacheTTL: TimeInterval = 60 * 15
        nonisolated static let detailCacheTTL: TimeInterval = 60 * 60 * 24
        nonisolated static let defaultsLastUsername = "SteamWorkshop.lastUsername"
        nonisolated static let defaultsLastAuthenticatedAt = "SteamWorkshop.lastAuthenticatedAt"
        nonisolated static let authProbeCacheTTL: TimeInterval = 60 * 15
        nonisolated static let authProbeTimeout: TimeInterval = 20
        nonisolated static let requiredBundledItems = [
            "steamcmd.sh",
            "steamcmd",
            "steamclient.dylib",
            "libtier0_s.dylib",
            "libvstdlib_s.dylib",
            "crashhandler.dylib",
            "libaudio.dylib",
            "libsteaminput.dylib",
            "steamconsole.dylib",
            "update_hosts_cached.vdf",
            "package",
            "public",
            "Frameworks"
        ]
    }
}
